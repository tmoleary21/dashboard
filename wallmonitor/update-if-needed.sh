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

notify() {
    local message="$1"

    echo "$message" >&2
    echo "$message" >> "$log_file" || true

    if [[ ! -n "$NOTIFICATIONS_DROP_DIR" ]]; then
        msg="Could not create notification. NOTIFICATIONS_DROP_DIR empty"
        echo "$msg" >&2
        echo "$msg" >> "$log_file" || true
        return
    fi

    local dir="${NOTIFICATIONS_DROP_DIR}"

    if mkdir -p "$dir" 2>/dev/null; then
        echo "$message" >> "$dir/note_$(date +"%Y-%m-%d_%H-%M-%S").txt" 2>/dev/null || true
    fi
}

if [ -f "/etc/dashboard/environment.sh" ]; then
    source /etc/dashboard/environment.sh
    echo "Environment variables enabled"
fi

export log_file=${log_file:-"${PWD}/wallmonitor_install.log"}


# Wait for network availability

i=1
until host github.com > /dev/null 2>&1 && ping -c 1 -W 1 github.com > /dev/null 2>&1; do
  echo "Waiting for DNS and Network... (tried $i)"
  sleep 2
  ((++i))

  if [ $i -gt 5 ]; then
    notify "Could not access github.com for update"
    exit 3 # No network access after multiple tries
  fi

done
echo "DNS and Network are up!"


# Check update
#
# check-update.sh exits 0 when the latest release differs from this one. update.sh
# replaces this process: it downloads the new install.sh and execs it, and that
# ends by running the new version's start.sh. If update.sh cannot fetch the new
# release it exits 2, which is reported here as "nothing to update" so a failed
# download degrades to running the current version rather than to no display.

if ./check-update.sh; then
    update_status=0
    error_output=$({ ./update.sh; } 3>&1 1>&3 2>&1) || update_status=$?
    if [ ! $update_status -eq 0 ]; then
        notify "$error_output"
    fi
else
    echo "already at latest release" >> "$log_file"
    exit 2 # No update
fi

