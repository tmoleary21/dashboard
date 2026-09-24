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
versioned_release="$repository_url/releases/tag/$VERSION"
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
tar -xf ./wallmonitor.tar.gz

# Add to this with more environment variables if needed in the future
cat > environment.sh <<EOF
export VERSION=$VERSION
EOF

chmod +x environment.sh

# Install wrapper app

mkdir -p "$app_dir/wrapper"
mv ./wrapper-dist.tar.gz "$app_dir/wrapper"
cd "$app_dir/wrapper"
rm -rf ./dist
tar -xf ./wrapper-dist.tar.gz

# Prep dependencies

apt-get update

# Install:
# - chromium for browser to load the webapp
# - cage to be the single-window display server
# - seatd as a dependency to cage

apt-get install -y cage chromium seatd >> $log_file
systemctl enable --now seatd

# Kiosk user

KIOSK_USER="kiosk"
echo "==> Creating user '${KIOSK_USER}' (if not already present)..."
if id "$KIOSK_USER" &>/dev/null; then
    echo "    User '${KIOSK_USER}' already exists, skipping creation."
else
    adduser --disabled-password --gecos "" "$KIOSK_USER"
fi

echo "==> Adding '${KIOSK_USER}' to required groups..."
groupadd -f seat
usermod -aG video,input,render,seat "$KIOSK_USER"

KIOSK_HOME=$(getent passwd "$KIOSK_USER" | cut -d: -f6)

# Setup wrapper app service

KIOSK_BIND_URL=127.0.0.1
KIOSK_PORT=8000

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

# Configure autologin

echo "==> Configuring autologin on tty1 for '${KIOSK_USER}'..."
mkdir -p /etc/systemd/system/getty@tty1.service.d
cat > /etc/systemd/system/getty@tty1.service.d/autologin.conf <<EOF
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin ${KIOSK_USER} --noclear %I \$TERM
EOF

# Finish

systemctl daemon-reload
systemctl restart getty@tty1

echo ""
echo "==> Done."
echo "    Kiosk user:  ${KIOSK_USER}"
echo "    Kiosk URL:   ${KIOSK_URL}"
echo ""
echo "Reboot to test auto start: sudo reboot"

# Start

exec ./start.sh

