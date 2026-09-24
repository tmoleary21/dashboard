# Start process:
# If not installed, prompt user to run install
# Check for updates, and run update
# Create systemd unit for wrapper app server
# Start kiosk mode
# Enable autologin (should this be in install?)

# RESPONSIBILITY: RUN UPDATE CHECKER, IF UPDATE RUN UPDATE, IF NOT RUN THIS VERSION

# PREP
set -euo pipefail

# Check if the script is being run as root

if [ "$(id -u)" -ne 0 ]; then
    echo "This script must be run as root (use sudo)." >&2
    exit 1
fi

# Prepare

if [ -f ./environment.sh ]; then
    source ./environment.sh
fi

log_file=./wallmonitor_install.log

# Check Update
if ./check-update.sh; then
    exec ./update.sh
fi

# Ensure wallmonitor wrapper service is started

systemctl start wallmonitor-wrapper.service

# Enable kiosk mode

KIOSK_URL="http://${KIOSK_BIND_URL}:${KIOSK_PORT}"

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

# END START

