#!/usr/bin/env bash
export VERSION="dev"
# ^ Github action release.yml replaces the line above with 'export VERSION="<tag>"'

# RESPONSIBILITY: INSTALL ONLY THIS VERSION

set -euo pipefail

# The version this copy of the script installs. Captured before any config is
# sourced, because the config records the version that is *already installed* -
# sourcing it would otherwise overwrite the tag being installed here, and every
# subsequent boot would compare that stale tag against the latest release, find
# a difference, and update again forever.
install_version="$VERSION"

# Check if the script is being run as root

if [ "$(id -u)" -ne 0 ]; then
    echo "This script must be run as root (use sudo)." >&2
    exit 1
fi

# Prepare

# Absolute rather than ./, so every script in the set writes to one log instead
# of scattering copies across whichever directory each was invoked from.
log_file=/var/log/wallmonitor-install.log

# The config lives outside app_dir on purpose. install.sh has to read it before
# it knows where app_dir is, and update.sh moves app_dir's contents around
# before handing over to the new install.sh - which is exactly how an update
# used to lose the config and fall back to prompting on a tty-less boot.
config_file=/etc/wallmonitor/environment.sh

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
default_app_dir=/var/dashboard

repository_url="https://github.com/tmoleary21/dashboard"
latest_release="$repository_url/releases/latest/download" # Unused. Could be fallback here, but will definitely be needed in update.sh
versioned_release="$repository_url/releases/download/$install_version"

echo "Prepared" >> $log_file

# Report a failure where it can actually be seen: the wrapper app displays
# anything dropped in NOTIFICATIONS_DROP_DIR, and an update runs unattended at
# boot. install.sh is published as a standalone release asset, so this cannot
# live in a file shared with the other scripts.

notify() {
    local message="$1"
    local dir="${NOTIFICATIONS_DROP_DIR:-$default_app_dir/drop}"

    echo "$message" >&2
    echo "$message" >> "$log_file" || true

    if mkdir -p "$dir" 2>/dev/null; then
        echo "$message" > "$dir/$(date +%Y-%m-%d_%H-%M-%S)-install.txt" 2>/dev/null || true
    fi
}

trap 'notify "install.sh $install_version failed at line $LINENO (exit $?)"' ERR

# Load config
#
# Checked in order of authority: the canonical location, then a copy beside this
# script or in the working directory (a hand-run install from a checkout), then
# any copy left inside app_dir by an older layout. That last case matters for
# exactly one boot - the update that moves to $config_file - because update.sh
# archives wallmonitor/ before running this script, making the archived copy the
# only config on the box.

find_config() {
    local candidate
    for candidate in "$config_file" ./environment.sh "$script_dir/environment.sh"; do
        if [ -f "$candidate" ]; then
            echo "$candidate"
            return 0
        fi
    done

    # Newest surviving copy from the pre-$config_file layout. ls -t rather than
    # find -printf so this does not depend on GNU find; these paths are ours and
    # contain no spaces, so the word splitting is deliberate.
    local candidates
    candidates=$(find "$default_app_dir" -maxdepth 3 -type f -name environment.sh 2>/dev/null)
    if [ -n "$candidates" ]; then
        candidate=$(ls -t $candidates 2>/dev/null | head -1)
        if [ -n "$candidate" ]; then
            echo "$candidate"
            return 0
        fi
    fi

    return 1
}

if found_config=$(find_config); then

    source "$found_config"
    echo "Loaded config from $found_config"
    echo "Loaded config from $found_config" >> $log_file

elif [ -t 0 ]; then

    read -p "App directory [$default_app_dir]: " input
    app_dir=${input:-"$default_app_dir"}

    read -p "Wrapped site URL WRAPPED_SITE [http://localhost:5174]: " input
    WRAPPED_SITE=${input:-"http://localhost:5174"}

    read -p "Notification drop directory [$app_dir/drop]: " input
    NOTIFICATIONS_DROP_DIR=${input:-"$app_dir/drop"}

    echo "Acquired config values"

else

    # Without this the prompts above would read EOF, set -e would abort midway,
    # and an unattended update would fail with nothing explaining why.
    notify "install.sh $install_version: no config found at $config_file and no terminal to prompt on. Nothing installed."
    exit 3

fi

# Put the installing version back after the config overwrote it, so anything
# inheriting the environment sees the version actually being installed.
VERSION="$install_version"

# Defaults, so an older or partly written config cannot trip set -u below.
app_dir="${app_dir:-$default_app_dir}"
WRAPPED_SITE="${WRAPPED_SITE:-http://localhost:5174}"
NOTIFICATIONS_DROP_DIR="${NOTIFICATIONS_DROP_DIR:-$app_dir/drop}"

# Kiosk user and configuration
#
# Created before anything is written into app_dir, and before the dependency
# install, so that everything installed below can be handed to the user the
# services actually run as.

KIOSK_USER="${KIOSK_USER:-kiosk}"
KIOSK_BIND_URL=127.0.0.1
KIOSK_PORT=8000
KIOSK_URL="http://${KIOSK_BIND_URL}:${KIOSK_PORT}"

echo "==> Creating user '${KIOSK_USER}' (if not already present)..."
if id "$KIOSK_USER" &>/dev/null; then
    echo "    User '${KIOSK_USER}' already exists, skipping creation."
else
    adduser --disabled-password --gecos "" "$KIOSK_USER"
fi

echo "==> Adding '${KIOSK_USER}' to required groups..."
# video/input/render normally exist already; seat comes with seatd, which is not
# installed yet at this point, so create whichever are missing first.
for group in video input render seat; do
    groupadd -f "$group"
done
usermod -aG video,input,render,seat "$KIOSK_USER"

echo "Added kiosk user"  >> $log_file

# Set up app_dir

mkdir -p "$app_dir"
echo "Created app directory"  >> $log_file

# Download wrapper app

wrapper_url="$versioned_release/wrapper.tar.gz"
if ! wget "$wrapper_url"; then
  notify "install.sh $install_version: could not retrieve wrapper.tar.gz from $wrapper_url"
  exit 2
fi
mkdir -p "$app_dir/wrapper"
mv ./wrapper.tar.gz "$app_dir/wrapper"
echo "Downloaded wrapper.tar.gz"  >> $log_file


wallmonitor_url="$versioned_release/wallmonitor.tar.gz"
if ! wget "$wallmonitor_url"; then
  notify "install.sh $install_version: could not retrieve wallmonitor scripts from $wallmonitor_url"
  exit 2
fi
mv ./wallmonitor.tar.gz "$app_dir"
echo "Downloaded wallmonitor.tar.gz"  >> $log_file


# Install scripts

cd "$app_dir"
tar -xvf ./wallmonitor.tar.gz
scripts_dir="$app_dir/wallmonitor"
cd "$scripts_dir"

echo "Installed scripts"  >> $log_file

# Write the config so start.sh, check-update.sh and update.sh all read the same
# values instead of redefining them. app_dir is included because the scripts
# that run at boot need it and nothing else tells them where it is - its absence
# is what used to make the "config found" path die on an unbound variable.
# Add to this with more environment variables if needed in the future

write_config() {
    cat <<EOF
export app_dir=$app_dir
export VERSION=$install_version
export KIOSK_USER=$KIOSK_USER
export KIOSK_BIND_URL=$KIOSK_BIND_URL
export KIOSK_PORT=$KIOSK_PORT
export KIOSK_URL=$KIOSK_URL

export WRAPPED_SITE=$WRAPPED_SITE
export NOTIFICATIONS_DROP_DIR=$NOTIFICATIONS_DROP_DIR
EOF
}

mkdir -p "$(dirname "$config_file")"
write_config > "$config_file"
chmod 644 "$config_file"

# A copy here too, so a still-installed older start.sh or check-update.sh - which
# source ./environment.sh relative to this directory - keeps working across the
# one update that introduces $config_file.
write_config > environment.sh

chmod +x ./*.sh

echo "Wrote config to $config_file"  >> $log_file

# Install wrapper app

cd "$app_dir/wrapper"
rm -rf ./server
tar -xvf ./wrapper.tar.gz

cd server

cat > .env <<EOF
WRAPPED_SITE=$WRAPPED_SITE
NOTIFICATIONS_DROP_DIR=$NOTIFICATIONS_DROP_DIR
EOF

chmod +x ./start-prod.sh

echo "Installed wrapper app"  >> $log_file

# Prep dependencies

# Non-fatal: this also runs unattended at boot during an update, where a slow or
# half-up network would otherwise abort the whole install. A stale package list
# is fine - everything needed is normally installed already.
apt-get update || echo "Warning: apt-get update failed, continuing with the cached package list" >> $log_file

# Install:
# - chromium for browser to load the webapp
# - cage to be the single-window display server
# - seatd as a dependency to cage
# - uv for running python server

apt-get install -y cage chromium seatd >> $log_file
systemctl enable --now seatd

# uv, installed as $KIOSK_USER rather than for root or system-wide: that is the
# user the wrapper service runs as, and uv keeps its cache and its managed
# python interpreters under the invoking user's home regardless, so this keeps
# everything uv-related in one place owned by one user. runuser sets HOME to the
# target user's, which is what sends the install to $kiosk_home/.local/bin.
# curl -LsSf https://astral.sh/uv/install.sh | sh # Not everything starts with curl
kiosk_home=$(getent passwd "$KIOSK_USER" | cut -d: -f6)
uv_bin="$kiosk_home/.local/bin/uv"

# Skipped when uv is already there, which it is on every update: this is a
# network fetch inside the boot-time update window, and uv updates itself.
if [ -x "$uv_bin" ]; then
    echo "uv already installed at $uv_bin"  >> $log_file
else
    runuser -u "$KIOSK_USER" -- env UV_INSTALL_DIR="$kiosk_home/.local/bin" \
        sh -c 'wget -qO- https://astral.sh/uv/install.sh | sh' >> $log_file

    if [ ! -x "$uv_bin" ]; then
        notify "install.sh $install_version: uv did not install to $uv_bin"
        exit 2
    fi
fi

echo "Updated software and installed dependencies"  >> $log_file

# Hand app_dir to the kiosk user
#
# The units below run as $KIOSK_USER, so everything install just wrote - the
# scripts, the wrapper dist, environment.sh, .env, the drop directory, and the
# venv uv is about to create - has to be owned by it rather than by root.

echo "==> Giving '${KIOSK_USER}' ownership of $app_dir..."
mkdir -p "$NOTIFICATIONS_DROP_DIR"
chown -R "$KIOSK_USER:$KIOSK_USER" "$app_dir"
chmod -R u+rwX "$app_dir"
# The drop directory is configurable and may live outside app_dir.
chown -R "$KIOSK_USER:$KIOSK_USER" "$NOTIFICATIONS_DROP_DIR"

echo "Gave $KIOSK_USER ownership of $app_dir"  >> $log_file

# Pre-build the wrapper's python environment, as the kiosk user
#
# Doing it here rather than leaving it to the first start means the venv and the
# python 3.13 interpreter uv has to fetch are already in place - the service
# would otherwise do all of it at boot, and fail if the network is not up yet.
# Non-fatal, because the service retries on start anyway and a display on the
# old version beats no display.

cd "$app_dir/wrapper/server"
if ! runuser -u "$KIOSK_USER" -- "$uv_bin" sync >> $log_file 2>&1; then
    msg="Warning: 'uv sync' failed for $KIOSK_USER; wrapper service will retry on start"
    echo "$msg" >&2
    echo "$msg" >> $log_file
fi

echo "Installed wrapper python dependencies for $KIOSK_USER"  >> $log_file

# Setup wrapper app service

echo "==> Installing wallmonitor-wrapper systemd service..."
cat > /etc/systemd/system/wallmonitor-wrapper.service <<EOF
[Unit]
Description=Wallmonitor wrapper static file server
After=network.target

[Service]
Type=simple
WorkingDirectory=$app_dir/wrapper/server
# start-prod.sh calls uv by name, and uv lives in the kiosk user's home, which
# is not on systemd's default unit PATH - the rest of this is that default.
Environment=PATH=$kiosk_home/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
ExecStart=$app_dir/wrapper/server/start-prod.sh
Restart=always
RestartSec=1
User=$KIOSK_USER

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable wallmonitor-wrapper.service # No --now. Job of start.sh

echo "Set up wrapper app service"  >> $log_file

# Setup kiosk browser service
#
# The unit owns tty1 directly, so no autologin/.bash_profile chain is needed.
# PAMName=login makes pam_systemd open a real login session for the kiosk user,
# which is what gives cage its seat and XDG_RUNTIME_DIR.

echo "==> Installing wallmonitor-kiosk systemd service..."
cat > /etc/systemd/system/wallmonitor-kiosk.service <<EOF
[Unit]
Description=Wallmonitor kiosk browser
Wants=wallmonitor-wrapper.service
After=wallmonitor-wrapper.service seatd.service systemd-user-sessions.service
Conflicts=getty@tty1.service
After=getty@tty1.service
# A wall display should retry forever rather than give up after the default
# limit of 5 starts in 10s.
StartLimitIntervalSec=0

[Service]
Type=simple
User=$KIOSK_USER

# Stuff I don't understand yet. But provides a TTY and a seat for cage
PAMName=login
TTYPath=/dev/tty1
TTYReset=yes
TTYVHangup=yes
TTYVTDisallocate=yes
StandardInput=tty-fail
StandardOutput=journal
StandardError=journal
UtmpIdentifier=tty1
UtmpMode=user

# wallmonitor-wrapper is Type=simple, so systemd considers it started as soon as
# python3 execs - before the socket is listening. Wait for a real response so
# chromium doesn't load an error page and sit on it.
ExecStartPre=/bin/sh -c 'for i in \$(seq 1 60); do wget -q -O /dev/null "$KIOSK_URL" && exit 0; sleep 0.5; done; exit 1'
ExecStart=/usr/bin/cage -s -d -- /usr/bin/chromium --kiosk --app=$KIOSK_URL \\
    --enable-features=UseOzonePlatform --ozone-platform=wayland \\
    --noerrdialogs --disable-infobars --disable-session-crashed-bubble \\
    --disable-features=TranslateUI --no-first-run \\
    --check-for-update-interval=31536000
Restart=always
RestartSec=2

[Install]
WantedBy=multi-user.target
EOF

echo "Set up kiosk browser service"  >> $log_file


# Setup boot-time update check service
#
# This is what makes a reboot pick up a new release: it runs the update check
# before the wrapper and kiosk units, so they end up starting whichever version
# is installed once it has finished. The dependency is ordering only - no
# Requires - so a failed check or a dead network still leaves the display coming
# up on the version already on disk.

echo "==> Installing wallmonitor-update systemd service..."
cat > /etc/systemd/system/wallmonitor-update.service <<EOF
[Unit]
Description=Wallmonitor boot-time update check
Wants=network-online.target
After=network-online.target
Before=wallmonitor-wrapper.service wallmonitor-kiosk.service

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=$scripts_dir
ExecStart=$scripts_dir/update-if-needed.sh
# Explicit, though it is also the default: there is no terminal here. install.sh
# relies on this to tell an unattended update from a hand-run one.
StandardInput=null
# An update re-runs install.sh, which downloads dists and runs apt-get, so give
# it real time - but not unlimited, because the two units above wait on it.
TimeoutStartSec=600
# Exit 2 is update-if-needed.sh reporting "already current", which is the normal
# boot outcome rather than a failure. Anything else is left to fail so it shows
# up in systemctl --failed instead of passing for "nothing to do".
SuccessExitStatus=2

[Install]
WantedBy=multi-user.target
EOF

echo "Set up boot-time update check service"  >> $log_file


# Finish

systemctl daemon-reload
systemctl enable wallmonitor-kiosk.service # No --now. Job of start.sh
systemctl enable wallmonitor-update.service # No --now. It runs on the next boot

# network-online.target is only ordered after something that actually waits for
# the network, so without one of these enabled the update check can run before
# DNS resolves and every boot looks like "no update available".
for wait_unit in NetworkManager-wait-online.service systemd-networkd-wait-online.service; do
    if systemctl list-unit-files "$wait_unit" &>/dev/null \
        && [ -n "$(systemctl list-unit-files --no-legend "$wait_unit")" ]; then
        systemctl enable "$wait_unit" || true
        echo "Enabled $wait_unit"  >> $log_file
    fi
done

echo ""
echo "==> Done."
echo "    Kiosk user:  ${KIOSK_USER}"
echo "    Kiosk URL:   ${KIOSK_URL}"
echo ""
echo "Reboot to test auto start: sudo reboot"

# Start

echo "Finished install. Running start"  >> $log_file

cd "$scripts_dir"
exec ./start.sh

