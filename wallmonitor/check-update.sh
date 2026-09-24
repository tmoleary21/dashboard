# Check for version difference with github latest release

# RESPONSIBILITY: CHECK FOR UPDATE

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
mkdir -p "$app_dir"


# Check update
script_url="$latest_release/install.sh"
if wget -O new-install.sh "$script_url" >> $log_file; then
  new_release_tag=$(sed -n '2s/^# Release: //p' ./new-install.sh)
  echo $new_release_tag >> $log_file
  this_release_tag="$VERSION"
  echo $this_release_tag >> $log_file

  if [ "$new_release_tag" != "$this_release_tag" ]; then
    echo "install script updated" >> $log_file
    exit 0 # Update    
  fi
fi

echo "no install script update" >> $log_file
rm new-install.sh
exit 2 # No Update