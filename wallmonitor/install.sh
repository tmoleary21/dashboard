#!/usr/bin/env bash
# Release: dev
# ^ Github action release.yml replaces the line above with "# Release: <tag>"

set -euo pipefail

# Check if the script is being run as root

if [ "$(id -u)" -ne 0 ]; then
    echo "This script must be run as root (use sudo)." >&2
    exit 1
fi

# Prepare

log_file=./wallmonitor_install.log

repository_url="https://github.com/tmoleary21/dashboard"
latest_release="$repository_url/releases/latest/download"
app_dir=/var/dashboard
mkdir -p "$app_dir"

# Update script

script_url="$latest_release/install.sh"
if wget -O new-install.sh "$script_url" >> $log_file; then
  new_release_tag=$(sed -n '2s/^# Release: //p' ./new-install.sh)
  echo $new_release_tag >> $log_file
  this_release_tag=$(sed -n '2s/^# Release: //p' ./install.sh)
  echo $this_release_tag >> $log_file

  if [ "$new_release_tag" != "$this_release_tag" ]; then
    echo "install script updated" >> $log_file

    mv new-install.sh "$app_dir"
    cd "$app_dir"
    script_path="./install.sh"

    if [ -e "$script_path" ]; then
      mv "$script_path" "./old-install.sh"
    fi
    mv new-install.sh "$script_path"
    chmod +x "$script_path"

    exec ./install.sh "$@"  # Runs instead. Replaces running script

  else 
    echo "no install script update" >> $log_file
    rm new-install.sh
  fi
fi

# Download wrapper app

wrapper_dist_url="$latest_release/wrapper-dist.tar.gz"
if ! wget "$wrapper_dist_url"; then
  msg="Could not retrieve dist from $wrapper_dist_url"
  echo $msg
  echo $msg >> $log_file
  exit 2
fi

# Install wrapper app

mkdir -p "$app_dir/wrapper"
mv ./wrapper-dist.tar.gz "$app_dir/wrapper"
cd "$app_dir/wrapper"
rm -rf ./dist
tar -xf ./wrapper-dist.tar.gz
cd -

# Prep dependencies

apt-get update

# Install:
# - chromium for browser to load the webapp
# - cage to be the single-window display server
# - seatd as a dependency to cage

apt-get install -y cage chromium seatd >> $log_file

# Set up seatd

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

# Start wrapper

KIOSK_BIND_URL=127.0.0.1
KIOSK_PORT=8000
cd "$app_dir/wrapper/dist"
python3 -m http.server "$KIOSK_PORT" --bind "$KIOSK_BIND_URL" &
cd -

# Enable kiosk mode

KIOSK_URL="http://${KIOSK_BIND_URL}:${KIOSK_PORT}"
# export XDG_RUNTIME_DIR=/run/user/$(id -u)

# cage -s -d -- chromium --enable-features=UseOzonePlatform --ozone-platform=wayland --kiosk --noerrdialogs --no-first-run --disable-infobars \
#   --disable-session-crashed-bubble --disable-features=TranslateUI \
#   --check-for-update-interval=31536000 \
#   --app=http://127.0.0.1:8000

echo "==> Writing ${KIOSK_HOME}/.bash_profile..."
cat > "${KIOSK_HOME}/.bash_profile" <<EOF
if [ -z "\$DISPLAY" ] && [ "\$(tty)" = "/dev/tty1" ]; then
    while true; do
        cage -s -d -- chromium --kiosk --app=${KIOSK_URL} \\
            --enable-features=UseOzonePlatform --ozone-platform=wayland \\
            --noerrdialogs --disable-infobars --disable-session-crashed-bubble \\
            --disable-features=TranslateUI --no-first-run --disable-infobars \\
            --check-for-update-interval=31536000
        sleep 2
    done
fi
EOF

chown "${KIOSK_USER}:${KIOSK_USER}" "${KIOSK_HOME}/.bash_profile"
chmod 644 "${KIOSK_HOME}/.bash_profile"

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
echo "Reboot to test: sudo reboot"
