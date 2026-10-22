#!/bin/bash

# STRICT MODE
set -euo pipefail
IFS=$'\n\t'

# Check if the script is being run as root

if [ "$(id -u)" -ne 0 ]; then
    echo "This script must be run as root (use sudo)." >&2
    exit 1
fi

export log_file=${log_file:-"${PWD}/wallmonitor_install.log"}

# Prompt for config values
if [ -f "/etc/dashboard/environment.sh" ]; then
    this_version="${VERSION}"
    source /etc/dashboard/environment.sh
    echo "Environment variables enabled"
    export VERSION=${this_version}
else

    APP_DIR=${APP_DIR:-"/var/dashboard"}

    read -p "Wrapped site URL WRAPPED_SITE [http://localhost:5174]: " input
    WRAPPED_SITE=${input:-"http://localhost:5174"}

    read -p "Notification drop directory [$APP_DIR/drop]: " input
    NOTIFICATIONS_DROP_DIR=${input:-"$APP_DIR/drop"}

    echo "Acquired config values"
fi

APP_DIR=${APP_DIR:-"/var/dashboard"}

# Set up APP_DIR
mkdir -p "$APP_DIR"
echo "Created app directory"  >> "$log_file"
config_dir="/etc/dashboard"
mkdir -p "$config_dir"
echo "Created config directory"  >> "$log_file"

# Download wrapper app
repository_url="https://github.com/tmoleary21/dashboard"
# latest_release="$repository_url/releases/latest/download" # Unused. Could be fallback here, but will definitely be needed in update.sh
versioned_release="$repository_url/releases/download/$VERSION"
wrapper_url="$versioned_release/wrapper.tar.gz"
if ! wget "$wrapper_url"; then
    msg="Could not retrieve wrapper.tar.gz from $wrapper_url"
    echo "$msg" >&2
    echo "$msg" >> "$log_file"
    exit 2
fi
mkdir -p "$APP_DIR/wrapper"
mv ./wrapper.tar.gz "$APP_DIR/wrapper"
echo "Downloaded wrapper.tar.gz"  >> "$log_file"

# Install wrapper app
cd "$APP_DIR/wrapper"
rm -rf ./server
tar -xvf ./wrapper.tar.gz
cd server
chmod +x ./start-prod.sh

cat > .env <<EOF
WRAPPED_SITE=$WRAPPED_SITE
NOTIFICATIONS_DROP_DIR=$NOTIFICATIONS_DROP_DIR
EOF

echo "Installed wrapper app"  >> "$log_file"

# Kiosk configuration. Written to environment.sh so start.sh, check-update.sh and
# update.sh all read the same values instead of redefining them.
# TODO: This currently will overwrite existing environment.sh variables
KIOSK_USER="kiosk"
KIOSK_BIND_URL=127.0.0.1
KIOSK_PORT=8000
KIOSK_URL="http://${KIOSK_BIND_URL}:${KIOSK_PORT}"

# Add to this with more environment variables if needed in the future
cat > "${config_dir}/environment.sh" <<EOF
export VERSION=$VERSION
export KIOSK_USER=$KIOSK_USER
export KIOSK_BIND_URL=$KIOSK_BIND_URL
export KIOSK_PORT=$KIOSK_PORT
export KIOSK_URL=$KIOSK_URL

export WRAPPED_SITE=$WRAPPED_SITE
export NOTIFICATIONS_DROP_DIR=$NOTIFICATIONS_DROP_DIR
EOF
echo "Generated environment.sh"  >> "$log_file"

# Prep dependencies
apt-get update

# Install:
# - chromium for browser to load the webapp
# - cage to be the single-window display server
# - seatd as a dependency to cage
# - uv for running python server
apt-get install -y cage chromium seatd >> "$log_file"
systemctl enable --now seatd

echo "Updated software and installed dependencies"  >> "$log_file"

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

echo "Added kiosk user"  >> "$log_file"

# Install UV for kiosk user
uv_install='wget -qO- https://astral.sh/uv/install.sh | sh'
runuser -l "$KIOSK_USER" -c "$uv_install"

# Setup wrapper app service

echo "==> Installing wallmonitor-wrapper systemd service..."
cat > /etc/systemd/system/wallmonitor-wrapper.service <<EOF
[Unit]
Description=Wallmonitor wrapper static file server
After=network.target

[Service]
Type=simple
WorkingDirectory=$APP_DIR/wrapper/server
ExecStart=/bin/bash -l -c '$APP_DIR/wrapper/server/start-prod.sh'
Restart=always
RestartSec=1
User=$KIOSK_USER

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable wallmonitor-wrapper.service # No --now. Job of start.sh

echo "Set up wrapper app service"  >> "$log_file"

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

echo "Set up kiosk browser service"  >> "$log_file"

systemctl enable wallmonitor-kiosk.service # No --now. Job of start.sh

# Start
echo "Finished install. Running start"  >> "$log_file"

cd "$APP_DIR/wallmonitor"
exec ./start.sh