#!/usr/bin/env bash
export VERSION="dev"
# ^ Github action release.yml replaces the line above with 'export VERSION="<tag>"'

# RESPONSIBILITY: INSTALL ONLY THIS VERSION

set -euo pipefail

# Check if the script is being run as root

if [ "$(id -u)" -ne 0 ]; then
    echo "This script must be run as root (use sudo)." >&2
    exit 1
fi

# Prepare

log_file=./wallmonitor_install.log

repository_url="https://github.com/tmoleary21/dashboard"
latest_release="$repository_url/releases/latest/download" # Unused. Could be fallback here, but will definitely be needed in update.sh
versioned_release="$repository_url/releases/download/$VERSION"

echo "Prepared" >> $log_file

# Prompt for config values

if [ -f "./environment.sh" ]; then

    source ./environment.sh
    echo "Environment variables enabled"

else

    read -p "App directory [/var/dashboard]: " input
    app_dir=${input:-"/var/dashboard"}

    read -p "Wrapped site URL WRAPPED_SITE [http://localhost:5174]: " input
    WRAPPED_SITE=${input:-"http://localhost:5174"}

    read -p "Notification drop directory [$app_dir/drop]: " input
    NOTIFICATIONS_DROP_DIR=${input:-"$app_dir/drop"}

    echo "Acquired config values"

fi

# Kiosk user and configuration
#
# Created before anything is written into app_dir, and before the dependency
# install, so that everything installed below can be handed to the user the
# services actually run as.

KIOSK_USER="${KIOSK_USER:-kiosk}"
KIOSK_BIND_URL=127.0.0.1
KIOSK_PORT=8000
KIOSK_URL="http://${KIOSK_BIND_URL}:${KIOSK_PORT}"

echo "==> Creating user '${KIOSK_USER}' (if not already present)..."
if id "$KIOSK_USER" &>/dev/null; then
    echo "    User '${KIOSK_USER}' already exists, skipping creation."
else
    adduser --disabled-password --gecos "" "$KIOSK_USER"
fi

echo "==> Adding '${KIOSK_USER}' to required groups..."
# video/input/render normally exist already; seat comes with seatd, which is not
# installed yet at this point, so create whichever are missing first.
for group in video input render seat; do
    groupadd -f "$group"
done
usermod -aG video,input,render,seat "$KIOSK_USER"

echo "Added kiosk user"  >> $log_file

# Set up app_dir

mkdir -p "$app_dir"
echo "Created app directory"  >> $log_file

# Download wrapper app

wrapper_url="$versioned_release/wrapper.tar.gz"
if ! wget "$wrapper_url"; then
  msg="Could not retrieve wrapper.tar.gz from $wrapper_url"
  echo $msg >&2
  echo $msg >> $log_file
  exit 2
fi
mkdir -p "$app_dir/wrapper"
mv ./wrapper.tar.gz "$app_dir/wrapper"
echo "Downloaded wrapper.tar.gz"  >> $log_file


wallmonitor_url="$versioned_release/wallmonitor.tar.gz"
if ! wget "$wallmonitor_url"; then
  msg="Could not retrieve wallmonitor scripts from $wallmonitor_url"
  echo $msg >&2
  echo $msg >> $log_file
  exit 2
fi
mv ./wallmonitor.tar.gz "$app_dir"
echo "Downloaded wallmonitor.tar.gz"  >> $log_file


# Install scripts

cd "$app_dir"
tar -xvf ./wallmonitor.tar.gz
scripts_dir="$app_dir/wallmonitor"
cd "$scripts_dir"

echo "Installed scripts"  >> $log_file

# Kiosk configuration is written to environment.sh so start.sh, check-update.sh
# and update.sh all read the same values instead of redefining them.
# Add to this with more environment variables if needed in the future
cat > environment.sh <<EOF
export VERSION=$VERSION
export KIOSK_USER=$KIOSK_USER
export KIOSK_BIND_URL=$KIOSK_BIND_URL
export KIOSK_PORT=$KIOSK_PORT
export KIOSK_URL=$KIOSK_URL

export WRAPPED_SITE=$WRAPPED_SITE
export NOTIFICATIONS_DROP_DIR=$NOTIFICATIONS_DROP_DIR
EOF

chmod +x ./*.sh

echo "Generated environment.sh"  >> $log_file

# Install wrapper app

cd "$app_dir/wrapper"
rm -rf ./server
tar -xvf ./wrapper.tar.gz

cd server

cat > .env <<EOF
WRAPPED_SITE=$WRAPPED_SITE
NOTIFICATIONS_DROP_DIR=$NOTIFICATIONS_DROP_DIR
EOF

chmod +x ./start-prod.sh

echo "Installed wrapper app"  >> $log_file

# Prep dependencies

apt-get update

# Install:
# - chromium for browser to load the webapp
# - cage to be the single-window display server
# - seatd as a dependency to cage
# - uv for running python server

apt-get install -y cage chromium seatd >> $log_file
systemctl enable --now seatd

# uv, installed system-wide rather than into root's home: the wrapper service
# runs as $KIOSK_USER, so uv has to sit on a PATH that user has. The symlinks
# into /usr/local/bin are what do that (it is also on systemd's default unit
# PATH). UV_NO_MODIFY_PATH stops the installer from writing its shell env
# scripts beside the binaries, where an "env" file would shadow /usr/bin/env.
# curl -LsSf https://astral.sh/uv/install.sh | sh # Not everything starts with curl
uv_install_dir=/opt/uv
mkdir -p "$uv_install_dir"
wget -qO- https://astral.sh/uv/install.sh \
    | env UV_INSTALL_DIR="$uv_install_dir" UV_NO_MODIFY_PATH=1 sh >> $log_file

if [ ! -x "$uv_install_dir/uv" ]; then
    msg="uv did not install to $uv_install_dir"
    echo "$msg" >&2
    echo "$msg" >> $log_file
    exit 2
fi

chmod -R a+rX "$uv_install_dir"
ln -sf "$uv_install_dir/uv" /usr/local/bin/uv
ln -sf "$uv_install_dir/uvx" /usr/local/bin/uvx
export PATH="/usr/local/bin:$PATH"

echo "Updated software and installed dependencies"  >> $log_file

# Hand app_dir to the kiosk user
#
# The units below run as $KIOSK_USER, so everything install just wrote - the
# scripts, the wrapper dist, environment.sh, .env, the drop directory, and the
# venv uv is about to create - has to be owned by it rather than by root.

echo "==> Giving '${KIOSK_USER}' ownership of $app_dir..."
mkdir -p "$NOTIFICATIONS_DROP_DIR"
chown -R "$KIOSK_USER:$KIOSK_USER" "$app_dir"
chmod -R u+rwX "$app_dir"
# The drop directory is configurable and may live outside app_dir.
chown -R "$KIOSK_USER:$KIOSK_USER" "$NOTIFICATIONS_DROP_DIR"

echo "Gave $KIOSK_USER ownership of $app_dir"  >> $log_file

# Pre-build the wrapper's python environment, as the kiosk user
#
# Run through runuser on purpose: uv keeps its cache and its managed python
# interpreters under the invoking user's home, so doing this as root would leave
# the service user to redo all of it on first start - and fail if the network is
# not up yet. Non-fatal, because the service retries on start anyway and a
# display on the old version beats no display.

cd "$app_dir/wrapper/server"
kiosk_home=$(getent passwd "$KIOSK_USER" | cut -d: -f6)
if ! runuser -u "$KIOSK_USER" -- env HOME="$kiosk_home" /usr/local/bin/uv sync >> $log_file 2>&1; then
    msg="Warning: 'uv sync' failed for $KIOSK_USER; wrapper service will retry on start"
    echo "$msg" >&2
    echo "$msg" >> $log_file
fi

echo "Installed wrapper python dependencies for $KIOSK_USER"  >> $log_file

# Setup wrapper app service

echo "==> Installing wallmonitor-wrapper systemd service..."
cat > /etc/systemd/system/wallmonitor-wrapper.service <<EOF
[Unit]
Description=Wallmonitor wrapper static file server
After=network.target

[Service]
Type=simple
WorkingDirectory=$app_dir/wrapper/server
ExecStart=$app_dir/wrapper/server/start-prod.sh
Restart=always
RestartSec=1
User=$KIOSK_USER

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable wallmonitor-wrapper.service # No --now. Job of start.sh

echo "Set up wrapper app service"  >> $log_file

# Setup kiosk browser service
#
# The unit owns tty1 directly, so no autologin/.bash_profile chain is needed.
# PAMName=login makes pam_systemd open a real login session for the kiosk user,
# which is what gives cage its seat and XDG_RUNTIME_DIR.

echo "==> Installing wallmonitor-kiosk systemd service..."
cat > /etc/systemd/system/wallmonitor-kiosk.service <<EOF
[Unit]
Description=Wallmonitor kiosk browser
Wants=wallmonitor-wrapper.service
After=wallmonitor-wrapper.service seatd.service systemd-user-sessions.service
Conflicts=getty@tty1.service
After=getty@tty1.service
# A wall display should retry forever rather than give up after the default
# limit of 5 starts in 10s.
StartLimitIntervalSec=0

[Service]
Type=simple
User=$KIOSK_USER

# Stuff I don't understand yet. But provides a TTY and a seat for cage
PAMName=login
TTYPath=/dev/tty1
TTYReset=yes
TTYVHangup=yes
TTYVTDisallocate=yes
StandardInput=tty-fail
StandardOutput=journal
StandardError=journal
UtmpIdentifier=tty1
UtmpMode=user

# wallmonitor-wrapper is Type=simple, so systemd considers it started as soon as
# python3 execs - before the socket is listening. Wait for a real response so
# chromium doesn't load an error page and sit on it.
ExecStartPre=/bin/sh -c 'for i in \$(seq 1 60); do wget -q -O /dev/null "$KIOSK_URL" && exit 0; sleep 0.5; done; exit 1'
ExecStart=/usr/bin/cage -s -d -- /usr/bin/chromium --kiosk --app=$KIOSK_URL \\
    --enable-features=UseOzonePlatform --ozone-platform=wayland \\
    --noerrdialogs --disable-infobars --disable-session-crashed-bubble \\
    --disable-features=TranslateUI --no-first-run \\
    --check-for-update-interval=31536000
Restart=always
RestartSec=2

[Install]
WantedBy=multi-user.target
EOF

echo "Set up kiosk browser service"  >> $log_file


# Setup boot-time update check service
#
# This is what makes a reboot pick up a new release: it runs the update check
# before the wrapper and kiosk units, so they end up starting whichever version
# is installed once it has finished. The dependency is ordering only - no
# Requires - so a failed check or a dead network still leaves the display coming
# up on the version already on disk.

echo "==> Installing wallmonitor-update systemd service..."
cat > /etc/systemd/system/wallmonitor-update.service <<EOF
[Unit]
Description=Wallmonitor boot-time update check
Wants=network-online.target
After=network-online.target
Before=wallmonitor-wrapper.service wallmonitor-kiosk.service

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=$scripts_dir
ExecStart=$scripts_dir/update-if-needed.sh
# An update re-runs install.sh, which downloads dists and runs apt-get, so give
# it real time - but not unlimited, because the two units above wait on it.
TimeoutStartSec=600
# Exit 2 is update-if-needed.sh reporting "already current", which is the normal
# boot outcome rather than a failure.
SuccessExitStatus=2

[Install]
WantedBy=multi-user.target
EOF

echo "Set up boot-time update check service"  >> $log_file


# Finish

systemctl daemon-reload
systemctl enable wallmonitor-kiosk.service # No --now. Job of start.sh
systemctl enable wallmonitor-update.service # No --now. It runs on the next boot

echo ""
echo "==> Done."
echo "    Kiosk user:  ${KIOSK_USER}"
echo "    Kiosk URL:   ${KIOSK_URL}"
echo ""
echo "Reboot to test auto start: sudo reboot"

# Start

echo "Finished install. Running start"  >> $log_file

cd "$scripts_dir"
exec ./start.sh

