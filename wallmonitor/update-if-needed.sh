#!/usr/bin/env bash
# Check for an update and install it if there is one.
# Exit 0: an update was installed, and the new version's install.sh has already
#         taken over from here (including re-running start.sh).
# Exit 2: this version is current, or the check or the update failed - either way
#         the caller should carry on with the version already installed.

# RESPONSIBILITY: DECIDE WHETHER TO UPDATE, AND HAND OFF TO update.sh IF SO

set -euo pipefail

# Check if the script is being run as root

if [ "$(id -u)" -ne 0 ]; then
    echo "This script must be run as root (use sudo)." >&2
    exit 1 # Not root
fi

# Prepare

log_file=/var/log/wallmonitor-install.log
config_file=/etc/wallmonitor/environment.sh
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ -f "$config_file" ]; then
    source "$config_file"
elif [ -f "$script_dir/environment.sh" ]; then
    source "$script_dir/environment.sh"
fi

NOTIFICATIONS_DROP_DIR="${NOTIFICATIONS_DROP_DIR:-${app_dir:-/var/dashboard}/drop}"

# This runs unattended at boot, so a failure has to end up somewhere a person
# will see it: the wrapper app displays whatever is dropped in here.

notify() {
    local message="$1"

    echo "$message" >&2
    echo "$message" >> "$log_file" || true

    if mkdir -p "$NOTIFICATIONS_DROP_DIR" 2>/dev/null; then
        echo "$message" > "$NOTIFICATIONS_DROP_DIR/$(date +%Y-%m-%d_%H-%M-%S)-update.txt" 2>/dev/null || true
    fi
}

# Check update
#
# 0 = a new release is available, 2 = current, anything else = the check itself
# could not be completed, which is worth saying out loud rather than treating as
# "nothing to do".

check_status=0
"$script_dir/check-update.sh" || check_status=$?

case "$check_status" in
    0)
        ;;
    2)
        echo "already at latest release" >> $log_file
        exit 2 # No update
        ;;
    *)
        notify "Wallmonitor update check failed (exit $check_status). Staying on ${VERSION:-an unknown version}."
        exit 2 # Carry on with whatever is installed
        ;;
esac

# Install the update
#
# `if ! var=$(...)` rather than assigning and then inspecting $?: under set -e a
# failing assignment ends the script outright, so the previous form could never
# reach its own error handling - which is why a failed update left no trace.
# update.sh restores the previous version before returning non-zero, so there is
# something to fall back to here.

if ! update_output=$("$script_dir/update.sh" 2>&1); then
    notify "Wallmonitor update failed, staying on ${VERSION:-an unknown version}:

$update_output"
    exit 2 # The previous version is back in place and runnable
fi

echo "$update_output" >> $log_file

# update.sh ran the new version's install.sh, which ends by running start.sh, so
# the services are already up on the new version.
exit 0
