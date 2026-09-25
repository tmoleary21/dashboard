#!/usr/bin/env bash
# Assume an update is necessary (check-update.sh has been run)
# Run install

# RESPONSIBILITY: DOWNLOAD LATEST INSTALL SCRIPT AND RUN

set -euo pipefail

# Check if the script is being run as root

if [ "$(id -u)" -ne 0 ]; then
    echo "This script must be run as root (use sudo)." >&2
    exit 1 # Not root
fi

# Prepare

if [ -f ./environment.sh ]; then
    source ./environment.sh
fi

log_file=./wallmonitor_install.log

repository_url="https://github.com/tmoleary21/dashboard"
latest_release="$repository_url/releases/latest/download"
app_dir=/var/dashboard

# Use new install script

script_url="$latest_release/install.sh"
if [ ! -f "new-install.sh" ]; then
    if ! wget -O new-install.sh "$script_url" >> $log_file; then
        exit 2
    fi
fi
mv new-install.sh "$app_dir"
cd "$app_dir"
script_path="./install.sh"

if [ -z "$VERSION" ]; then
    VERSION=old
fi
mkdir -p "$app_dir/$VERSION"
mv wallmonitor wrapper "$app_dir/$VERSION"

mv new-install.sh "$script_path"
chmod +x "$script_path"
exec ./install.sh