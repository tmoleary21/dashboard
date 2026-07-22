
# Update repository

git checkout main
git fetch
git pull

# Prep dependencies

sudo apt update

# Install chromium

sudo apt install chromium

# Start wrapper

cd /var/dashboard/wallmonitor
python3 -m http.server 8000 --bind 127.0.0.1 &
cd -

# Stark kiosk mode

chromium-browser --kiosk --noerrdialogs --no-first-run --disable-infobars \
  --disable-session-crashed-bubble --disable-features=TranslateUI \
  --check-for-update-interval=31536000 \
  --app=http://127.0.0.1:8000
