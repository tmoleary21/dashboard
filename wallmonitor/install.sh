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
app_dir=/var/dashboard
mkdir -p "$app_dir"

# Download wrapper app

wrapper_dist_url="$versioned_release/wrapper-dist.tar.gz"
if ! wget "$wrapper_dist_url"; then
  msg="Could not retrieve dist from $wrapper_dist_url"
  echo $msg
  echo $msg >> $log_file
  exit 2
fi

wallmonitor_url="$versioned_release/wallmonitor.tar.gz"
if ! wget "$wallmonitor_url"; then
  msg="Could not retrieve wallmonitor scripts from $wallmonitor_url"
  echo $msg
  echo $msg >> $log_file
  exit 2
fi

# Install scripts

mv ./wallmonitor.tar.gz "$app_dir"
cd "$app_dir"
tar -xvf ./wallmonitor.tar.gz
scripts_dir="$app_dir/wallmonitor"
cd "$scripts_dir"

# Kiosk configuration. Written to environment.sh so start.sh, check-update.sh and
# update.sh all read the same values instead of redefining them.

KIOSK_USER="kiosk"
KIOSK_BIND_URL=127.0.0.1
KIOSK_PORT=8000
KIOSK_URL="http://${KIOSK_BIND_URL}:${KIOSK_PORT}"

# Add to this with more environment variables if needed in the future
cat > environment.sh <<EOF
export VERSION=$VERSION
export KIOSK_USER=$KIOSK_USER
export KIOSK_BIND_URL=$KIOSK_BIND_URL
export KIOSK_PORT=$KIOSK_PORT
export KIOSK_URL=$KIOSK_URL
EOF

chmod +x environment.sh

# Install wrapper app

mkdir -p "$app_dir/wrapper"
mv ./wrapper-dist.tar.gz "$app_dir/wrapper"
cd "$app_dir/wrapper"
rm -rf ./dist
tar -xvf ./wrapper-dist.tar.gz

# Prep dependencies

apt-get update

# Install:
# - chromium for browser to load the webapp
# - cage to be the single-window display server
# - seatd as a dependency to cage

apt-get install -y cage chromium seatd >> $log_file
systemctl enable --now seatd

# Kiosk user

echo "==> Creating user '${KIOSK_USER}' (if not already present)..."
if id "$KIOSK_USER" &>/dev/null; then
    echo "    User '${KIOSK_USER}' already exists, skipping creation."
else
    adduser --disabled-password --gecos "" "$KIOSK_USER"
fi

echo "==> Adding '${KIOSK_USER}' to required groups..."
groupadd -f seat
usermod -aG video,input,render,seat "$KIOSK_USER"

# Setup wrapper app service

echo "==> Installing wallmonitor-wrapper systemd service..."
cat > /etc/systemd/system/wallmonitor-wrapper.service <<EOF
[Unit]
Description=Wallmonitor wrapper static file server
After=network.target

[Service]
Type=simple
WorkingDirectory=$app_dir/wrapper/dist
ExecStart=/usr/bin/python3 -m http.server $KIOSK_PORT --bind $KIOSK_BIND_URL
Restart=always
RestartSec=1
User=$KIOSK_USER

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable wallmonitor-wrapper.service # No --now. Job of start.sh

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


# Finish

systemctl daemon-reload
systemctl enable wallmonitor-kiosk.service # No --now. Job of start.sh

echo ""
echo "==> Done."
echo "    Kiosk user:  ${KIOSK_USER}"
echo "    Kiosk URL:   ${KIOSK_URL}"
echo ""
echo "Reboot to test auto start: sudo reboot"

# Start

cd "$scripts_dir"
exec ./start.sh

