#!/usr/bin/env bash
# Start process:
# If not installed, prompt user to run install
# Check for updates, and run update
# Start the wrapper app server and the kiosk browser
# (Installing and enabling the units is install.sh's job)

# RESPONSIBILITY: RUN THE UPDATE CHECK, THEN RUN WHICHEVER VERSION ENDED UP INSTALLED

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
#
# Exit 0 means an update was installed, and that chain has already re-run
# install.sh and, through it, this script - so this older copy has nothing left
# to do. Exit 2 means we are current and should go on to start the services.

if ./update-if-needed.sh; then
    exit 0
fi

# Ensure services are running. All three units are installed and enabled by
# install.sh, so on a normal boot systemd has already brought them up and this is
# a no-op. The kiosk unit waits for the wrapper to actually answer before
# starting cage.
#
# --no-block is required, not cosmetic: when this runs from inside
# wallmonitor-update.service (via update.sh -> install.sh), both units below are
# ordered after that still-activating unit, so a blocking start would wait on a
# job that cannot run until this process exits - a deadlock until the unit's
# start timeout. restart rather than start so a mid-session update replaces a
# wrapper that is already serving the old dist.

systemctl restart --no-block wallmonitor-wrapper.service wallmonitor-kiosk.service

# END START

