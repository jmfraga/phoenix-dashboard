#!/bin/bash
# Jarvis Dashboard Auto-start
# Waits for system to be ready, then starts dashboard

DASHBOARD_DIR="/Users/juanma/clawd/dashboard"
LOG_DIR="$DASHBOARD_DIR/logs"

mkdir -p "$LOG_DIR"

echo "$(date): Starting Jarvis Dashboard..." >> "$LOG_DIR/dashboard.log"

# Wait for network and system to be ready
sleep 10

# Kill any existing HTTP server
pkill -f "python3 -m http.server 8888" 2>/dev/null

# Start HTTP server
cd "$DASHBOARD_DIR"
nohup python3 -m http.server 8888 >> "$LOG_DIR/server.log" 2>&1 &
echo "$(date): HTTP server started on port 8888" >> "$LOG_DIR/dashboard.log"

# Note: Updater is managed by separate LaunchAgent (com.jarvis.dashboard-updater)
# with KeepAlive=true for automatic restart if it dies
echo "$(date): Updater managed by LaunchAgent" >> "$LOG_DIR/dashboard.log"

# Wait for server to be ready
sleep 3

# Open Chrome in app mode on secondary display
open -na "Google Chrome" --args --app=http://localhost:8888

echo "$(date): Dashboard launched!" >> "$LOG_DIR/dashboard.log"
