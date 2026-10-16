#!/usr/bin/env bash
# Check for version difference with github latest release

# RESPONSIBILITY: CHECK FOR UPDATE
#
# Exit 0: a different release is available, and its install script is waiting in
#         $state_dir/new-install.sh
# Exit 2: this version is current
# Exit 3: the check could not be performed - no config, no network, nothing
#         readable at the other end. Deliberately distinct from 2: reporting a
#         failed check as "already current" is what made a boot that never got
#         as far as updating look exactly like a boot with nothing to do.

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
state_dir=/var/lib/wallmonitor

if [ -f "$config_file" ]; then
    source "$config_file"
elif [ -f "$script_dir/environment.sh" ]; then
    # Older layout, still the only copy until the next install writes $config_file
    source "$script_dir/environment.sh"
else
    echo "no config at $config_file, cannot tell which version is installed" >> $log_file
    exit 3 # Cannot check
fi

repository_url="https://github.com/tmoleary21/dashboard"
latest_release="$repository_url/releases/latest/download"

this_release_tag="${VERSION:-}"
if [ -z "$this_release_tag" ]; then
    echo "no VERSION in the config, cannot compare releases" >> $log_file
    exit 3 # Cannot check
fi

# Check update
#
# Retried, because this runs at boot: network-online.target does not guarantee
# DNS is answering yet, and one failed wget used to be reported as "no update".

mkdir -p "$state_dir"
new_install="$state_dir/new-install.sh"
script_url="$latest_release/install.sh"

downloaded=no
for attempt in 1 2 3 4 5; do
    if wget --tries=3 --timeout=10 -O "$new_install" "$script_url" >> $log_file 2>&1; then
        downloaded=yes
        break
    fi
    echo "attempt $attempt: could not fetch $script_url" >> $log_file
    if [ "$attempt" -lt 5 ]; then
        sleep 3
    fi
done

if [ "$downloaded" != yes ]; then
    rm -f "$new_install"
    echo "gave up fetching $script_url" >> $log_file
    exit 3 # Cannot check
fi

new_release_tag=$(sed -n '2s/^export VERSION="\(.*\)"$/\1/p' "$new_install")
if [ -z "$new_release_tag" ]; then
    rm -f "$new_install"
    echo "no version on line 2 of $script_url" >> $log_file
    exit 3 # Cannot check
fi

echo "$this_release_tag =?= $new_release_tag" >> $log_file

if [ "$new_release_tag" != "$this_release_tag" ]; then
    echo "install script updated: $this_release_tag -> $new_release_tag" >> $log_file
    exit 0 # Update
fi

rm -f "$new_install"
echo "no install script update" >> $log_file
exit 2 # No Update
