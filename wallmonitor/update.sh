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

if [ -f "/etc/dashboard/environment.sh" ]; then
    source /etc/dashboard/environment.sh
    echo "Environment variables enabled"
fi

VERSION=${VERSION:-}
APP_DIR=${APP_DIR:-}

if [ -z "$APP_DIR" ]; then
    echo "APP_DIR variable empty"
    exit 4
fi

export log_file=${log_file:-"${PWD}/wallmonitor_install.log"}

repository_url="https://github.com/tmoleary21/dashboard"
latest_release="$repository_url/releases/latest/download"
# APP_DIR=/var/dashboard

# Use new install script

script_url="$latest_release/install.sh"
if [ ! -f "new-install.sh" ]; then
    if ! wget -O new-install.sh "$script_url" >> "$log_file"; then
        exit 2
    fi
fi
mv new-install.sh "$APP_DIR"
cd "$APP_DIR"

if [ -z "$VERSION" ]; then
    OLD_DIR=old
else
    OLD_DIR="$VERSION"
fi
mkdir -p "$APP_DIR/$OLD_DIR"
mv wallmonitor wrapper "$APP_DIR/$OLD_DIR"
rm -rf ./*.tar.gz

script_path="./install.sh"
mv new-install.sh "$script_path"
chmod +x "$script_path"
# exec ./install.sh

install_status=0
./install.sh || install_status=$?
if [ ! $install_status -eq 0 ]; then
    cd "$APP_DIR"
    rm -rf ./wallmonitor ./wrapper ./*.tar.gz ./install.sh
    cp -a "$APP_DIR/$OLD_DIR/." "$APP_DIR/" # Rollback
    
    cp ./wallmonitor/install.sh ./install.sh
    chmod +x ./install.sh

    rollback_status=0
    ./install.sh || rollback_status=$?
    
    if [ "$rollback_status" -eq 0 ]; then
        rm -rf "./$OLD_DIR" # Don't remove backup if failed to reinstall
    fi
    exit "$install_status"
fi