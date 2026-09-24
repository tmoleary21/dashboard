# Start process:
# If not installed, prompt user to run install
# Check for updates, and run update
# Start the wrapper app server and the kiosk browser
# (Installing and enabling the units is install.sh's job)

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

# Ensure services are started. Both are installed and enabled by install.sh, so
# on a normal boot systemd has already brought them up and these are no-ops.
# The kiosk unit waits for the wrapper to actually answer before starting cage.

systemctl start wallmonitor-wrapper.service
systemctl start wallmonitor-kiosk.service

# END START

