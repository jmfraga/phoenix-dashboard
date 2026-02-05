#!/bin/bash
# Start Jarvis Dashboard

cd /Users/juanma/clawd/dashboard

echo "🐦‍🔥 Starting Jarvis Dashboard..."

# Kill any existing dashboard server on port 8888
lsof -ti:8888 | xargs kill 2>/dev/null

# Start simple HTTP server
python3 -m http.server 8888 &
SERVER_PID=$!

echo "📺 Dashboard running at http://localhost:8888"
echo "   Server PID: $SERVER_PID"

# Initial data update
bash update.sh

echo "✅ Ready! Open http://localhost:8888 in the secondary display"
echo ""
echo "To stop: kill $SERVER_PID"
