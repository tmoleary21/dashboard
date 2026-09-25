#!/usr/bin/env bash
# Check for an update and install it if there is one.
# Exit 0: an update was installed, and the new version's install.sh has already
#         taken over from here (including re-running start.sh).
# Exit 2: this version is current, or the update could not be fetched - either
#         way the caller should carry on with the version already installed.

# RESPONSIBILITY: DECIDE WHETHER TO UPDATE, AND HAND OFF TO update.sh IF SO

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

# Check update
#
# check-update.sh exits 0 when the latest release differs from this one. update.sh
# replaces this process: it downloads the new install.sh and execs it, and that
# ends by running the new version's start.sh. If update.sh cannot fetch the new
# release it exits 2, which is reported here as "nothing to update" so a failed
# download degrades to running the current version rather than to no display.

if ./check-update.sh; then
    exec ./update.sh
fi

echo "already at latest release" >> $log_file
exit 2 # No update
