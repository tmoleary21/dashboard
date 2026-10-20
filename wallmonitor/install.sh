#!/bin/bash
export VERSION="dev"
# ^ Github action release.yml replaces the line above with 'export VERSION="<tag>"'

# RESPONSIBILITY: INSTALL ONLY THIS VERSION

# STRICT MODE
set -euo pipefail
IFS=$'\n\t'

# Check if the script is being run as root

if [ "$(id -u)" -ne 0 ]; then
    echo "This script must be run as root (use sudo)." >&2
    exit 1
fi

# Prepare

export log_file="${PWD}/wallmonitor_install.log"
echo "Prepared" >> $log_file

# Initialize config

usage() {
    echo "Usage: $0 [-h] [-v] [-f filename]"
    echo "  -w             Show this help message"
    exit 1
}

if [ -f "/etc/dashboard/environment.sh" ]; then
    this_version="${VERSION}"
    source /etc/dashboard/environment.sh
    echo "Environment variables enabled"
    export VERSION=${this_version}
fi

while getopts "hdw:" variable; do
    case "${variable}" in
        h)
            usage
            ;;
        d)
            DRY="true"
            ;;
        w)
            APP_DIR="${OPTARG}"
            ;;
        :)
            # Executed if a flag requiring an argument is left blank
            echo "Error: Option -${OPTARG} requires an argument." >&2
            usage
            ;;
        \?)
            # Executed if an unknown/invalid flag is passed
            echo "Error: Invalid option -${OPTARG}" >&2
            usage
            ;;
    esac
done

DRY=${DRY:-"false"}
APP_DIR=${APP_DIR:-"/var/dashboard"}
mkdir -p "${APP_DIR}"

# Download wallmonitor scripts
repository_url="https://github.com/tmoleary21/dashboard"
versioned_release="$repository_url/releases/download/$VERSION"
wallmonitor_url="$versioned_release/wallmonitor.tar.gz"
if ! wget "$wallmonitor_url"; then
  msg="Could not retrieve wallmonitor scripts from $wallmonitor_url"
  echo $msg >&2
  echo $msg >> $log_file
  exit 2
fi
mv ./wallmonitor.tar.gz "$APP_DIR"
echo "Downloaded wallmonitor.tar.gz"  >> $log_file


# Install scripts
cd "$APP_DIR"
tar -xvf ./wallmonitor.tar.gz
scripts_dir="$APP_DIR/wallmonitor"
cd "$scripts_dir"
echo "Installed scripts"  >> $log_file
chmod +x ./*.sh

if [[ $DRY != "false" ]]; then
    echo "SKIPPED FOR DRY RUN: creation of update service and install-app.sh in ${scripts_dir}"
    exit 0
fi

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
systemctl enable wallmonitor-update.service # No --now. It runs on the next boot


export APP_DIR="${APP_DIR}"

echo "Running install-app.sh in ${scripts_dir}"   
cd "${scripts_dir}"
exec ./install-app.sh
