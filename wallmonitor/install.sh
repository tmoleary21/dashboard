# Github action release.yml adds "# Release: <tag>" to the top of this file (above here)

# Prepare

log_file=./wallmonitor_install.log

repository_url="https://github.com/tmoleary21/dashboard"
latest_release="$repository_url/releases/latest/download"
app_dir=/var/dashboard
mkdir -p "$app_dir"

# Update script

script_url="$latest_release/install.sh"
if wget -O new-install.sh "$script_url" >> $log_file; then
  new_release_tag=$(sed -n '1s/^# Release: //p' new-install.sh)
  echo $new_release_tag >> $log_file
  this_release_tag=$(sed -n '1s/^# Release: //p' install.sh)
  echo $this_release_tag >> $log_file

  if [ "$new_release_tag" != "$this_release_tag" ]; then
    echo "install script updated" >> $log_file
    # mv new-install.sh "$app_dir"
    script_path="$app_dir/install.sh"
    if [ -e "$script_path" ]; then
      mv "$script_path" "$app_path/old-install.sh"
    fi
    mv new-install.sh "$script_path"
    chmod +x "$script_path"
    exec "$script_path" "$@" # Runs instead. Replaces running script
  else 
    echo "no install script update" >> $log_file
    rm new-install.sh
  fi
fi

# Download wrapper app

wrapper_dist_url="$latest_release/wrapper-dist.tar.gz"
if ! wget "$wrapper_dist_url"; then
  msg="Could not retrieve dist from $wrapper_dist_url"
  echo $msg
  echo $msg >> $log_file
  exit
fi

# Install wrapper app

mkdir -p "$app_dir/wrapper"
mv ./wrapper-dist.tar.gz "$app_dir/wrapper"
cd "$app_dir/wrapper"
tar -xf ./wrapper-dist.tar.gz
rm -rf ./dist
mv ./wrapper-dist ./dist
cd -

# Prep dependencies

sudo apt-get update

# Install chromium

sudo apt-get install -y chromium >> $log_file
sudo apt-get install -y cage >> $log_file

# Start wrapper

cd "$app_dir/dist"
python3 -m http.server 8000 --bind 127.0.0.1 &
cd -

# Stark kiosk mode

cage -s -d -- chromium --kiosk --noerrdialogs --no-first-run --disable-infobars \
  --disable-session-crashed-bubble --disable-features=TranslateUI \
  --check-for-update-interval=31536000 \
  --app=http://127.0.0.1:8000
