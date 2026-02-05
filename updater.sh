#!/bin/bash
# Auto-updater for Jarvis Dashboard - runs every 30 seconds

LOG_DIR="/Users/juanma/clawd/dashboard/logs"
mkdir -p "$LOG_DIR"

# Load GOG password
export GOG_KEYRING_PASSWORD="$(cat /Users/juanma/clawd/secrets/gog_keyring_password.txt)"

echo "$(date): Updater started with GOG_KEYRING_PASSWORD length: ${#GOG_KEYRING_PASSWORD}" >> "$LOG_DIR/updater.log"

while true; do
    bash /Users/juanma/clawd/dashboard/update.sh >> "$LOG_DIR/update.log" 2>&1
    sleep 30
done
