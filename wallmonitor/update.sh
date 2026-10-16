#!/usr/bin/env bash
# Assume an update is necessary (check-update.sh has been run)
# Run install

# RESPONSIBILITY: SWAP IN THE LATEST INSTALL SCRIPT AND RUN IT, OR PUT THE
# VERSION THAT WAS WORKING BACK

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

repository_url="https://github.com/tmoleary21/dashboard"
latest_release="$repository_url/releases/latest/download"

# The config has to resolve before anything moves. The new install.sh needs it,
# and failing to find one after the archive step below is what used to leave a
# box with its old version archived and no new version installed.

if [ -f "$config_file" ]; then
    source "$config_file"
elif [ -f "$script_dir/environment.sh" ]; then
    source "$script_dir/environment.sh"
else
    echo "no config at $config_file, refusing to update" >> $log_file
    exit 2
fi

app_dir="${app_dir:-/var/dashboard}"
installed_version="${VERSION:-old}"

# Use new install script
#
# check-update.sh has normally just left it here; fetched again only when this
# script is run on its own.

mkdir -p "$state_dir"
new_install="$state_dir/new-install.sh"
script_url="$latest_release/install.sh"

if [ ! -f "$new_install" ]; then
    if ! wget --tries=3 --timeout=10 -O "$new_install" "$script_url" >> $log_file 2>&1; then
        rm -f "$new_install"
        echo "could not retrieve $script_url" >> $log_file
        exit 2
    fi
fi

cd "$app_dir"
script_path="$app_dir/install.sh"
mv "$new_install" "$script_path"
chmod +x "$script_path"

# Archive the running version instead of extracting on top of it
#
# These scripts are read from disk as they run, so letting tar write over them
# mid-execution would feed the shell whatever landed at its current offset.
# Moving them leaves the inodes the running shells hold intact, and gives us a
# copy to put back if the new version fails to install.

archive_dir="$app_dir/$installed_version"
mkdir -p "$archive_dir"

archived=""
for dir in wallmonitor wrapper; do
    if [ -d "$app_dir/$dir" ]; then
        rm -rf "$archive_dir/$dir"
        mv "$app_dir/$dir" "$archive_dir/$dir"
        archived="$archived $dir"
    fi
done

echo "archived $installed_version to $archive_dir" >> $log_file

restore() {
    local dir
    for dir in $archived; do
        rm -rf "$app_dir/$dir"
        mv "$archive_dir/$dir" "$app_dir/$dir"
    done
    echo "restored $installed_version after a failed update" >> $log_file
}

# Run as a child rather than exec'ing, so that a failure can still be undone.
# install.sh ends by running start.sh, so on success the new version is already
# installed and started by the time this returns.

status=0
"$script_path" || status=$?

if [ "$status" -ne 0 ]; then
    restore
    exit "$status"
fi
