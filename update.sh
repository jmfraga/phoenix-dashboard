#!/bin/bash
# Dashboard data updater for Jarvis

DATA_FILE="/Users/juanma/clawd/dashboard/data/dashboard.json"

# Ensure GOG password is set (needed for LaunchAgent context)
if [ -z "$GOG_KEYRING_PASSWORD" ]; then
    export GOG_KEYRING_PASSWORD=$(cat /Users/juanma/clawd/secrets/gog_keyring_password.txt 2>/dev/null)
fi

# Calendars to check
CAL_PRIMARY="primary"
CAL_DRFRAGA="mdb2or88q08h6s1ifr7f4tqeq4@group.calendar.google.com"
ACCOUNT="asistente.docfraga@gmail.com"

# Get weather (try wttr.in first, fallback to Open-Meteo)
WEATHER=$(curl -s --max-time 3 "wttr.in/Queretaro?format=%c|%t|%C" 2>/dev/null | head -1)

if [ -z "$WEATHER" ] || [ ${#WEATHER} -lt 3 ]; then
    # Fallback to Open-Meteo
    METEO=$(curl -s --max-time 3 "https://api.open-meteo.com/v1/forecast?latitude=20.59&longitude=-100.39&current_weather=true" 2>/dev/null)
    TEMP=$(echo "$METEO" | jq -r '.current_weather.temperature // 0' 2>/dev/null)
    WEATHERCODE=$(echo "$METEO" | jq -r '.current_weather.weathercode // 0' 2>/dev/null)
    
    # WMO weather codes to emoji
    case "$WEATHERCODE" in
        0) WEATHER_ICON="☀️"; WEATHER_DESC="Despejado" ;;
        1|2|3) WEATHER_ICON="⛅"; WEATHER_DESC="Parcialmente nublado" ;;
        45|48) WEATHER_ICON="🌫️"; WEATHER_DESC="Neblina" ;;
        51|53|55) WEATHER_ICON="🌧️"; WEATHER_DESC="Llovizna" ;;
        61|63|65) WEATHER_ICON="🌧️"; WEATHER_DESC="Lluvia" ;;
        71|73|75) WEATHER_ICON="❄️"; WEATHER_DESC="Nieve" ;;
        80|81|82) WEATHER_ICON="🌦️"; WEATHER_DESC="Chubascos" ;;
        95|96|99) WEATHER_ICON="⛈️"; WEATHER_DESC="Tormenta" ;;
        *) WEATHER_ICON="🌤️"; WEATHER_DESC="Clima" ;;
    esac
    WEATHER_TEMP="${TEMP}°C"
else
    WEATHER_ICON=$(echo "$WEATHER" | cut -d'|' -f1 | tr -d ' ')
    WEATHER_TEMP=$(echo "$WEATHER" | cut -d'|' -f2 | tr -d ' ')
    WEATHER_DESC=$(echo "$WEATHER" | cut -d'|' -f3)
fi

# Generate weather tip based on temperature
TEMP_NUM=$(echo "$WEATHER_TEMP" | grep -o '[0-9-]*' | head -1)
if [ -n "$TEMP_NUM" ]; then
    if [ "$TEMP_NUM" -le 10 ]; then
        WEATHER_TIP="🧥 Sal abrigado"
    elif [ "$TEMP_NUM" -le 15 ]; then
        WEATHER_TIP="🧣 Lleva chamarra"
    elif [ "$TEMP_NUM" -le 20 ]; then
        WEATHER_TIP="👍 Clima agradable"
    elif [ "$TEMP_NUM" -le 28 ]; then
        WEATHER_TIP="😎 Día cálido"
    else
        WEATHER_TIP="🥵 Mucho calor, hidrátate"
    fi
else
    WEATHER_TIP=""
fi

# Check for rain in description
if echo "$WEATHER_DESC" | grep -qi "rain\|lluvia\|shower"; then
    WEATHER_TIP="☔ Lleva paraguas"
fi

# Get system stats
CPU=$(ps -A -o %cpu | awk '{s+=$1} END {print int(s/4)}' 2>/dev/null || echo "10")
RAM=$(vm_stat 2>/dev/null | awk '/Pages active|Pages wired/ {sum+=$NF} END {print int(sum*4096/1024/1024/1024/16*100)}' || echo "50")
DISK=$(df -h / 2>/dev/null | tail -1 | awk '{gsub(/%/,""); print $5}' || echo "0")

# Calendar: preserve from file (updated by morning cron)
CALENDAR=$(jq -c '.calendar // [{"time":"✓","title":"Sin eventos hoy"}]' "$DATA_FILE" 2>/dev/null)
[ -z "$CALENDAR" ] && CALENDAR='[{"time":"✓","title":"Sin eventos hoy"}]'

# Model info: preserve from file (updated by heartbeat)
MODEL_NAME="opus-4-5"
CONTEXT_PCT=$(jq -r '.model.contextPercent // 50' "$DATA_FILE" 2>/dev/null)
USAGE_DAY=$(jq -r '.model.usageDay // "--"' "$DATA_FILE" 2>/dev/null)
USAGE_WEEK=$(jq -r '.model.usageWeek // "--"' "$DATA_FILE" 2>/dev/null)

# Read current values to preserve
JARVIS_STATUS=$(jq -r '.jarvis.status // "Listo"' "$DATA_FILE" 2>/dev/null || echo "Listo")
JARVIS_VERSION=$(jq -r '.jarvis.version // "OpenClaw"' "$DATA_FILE" 2>/dev/null || echo "OpenClaw")
JARVIS_THINKING=$(jq -r '.jarvis.thinking // false' "$DATA_FILE" 2>/dev/null || echo "false")
NOTIFICATION=$(jq -r '.notification // null' "$DATA_FILE" 2>/dev/null)
KANBAN=$(jq -c '.kanban // []' "$DATA_FILE" 2>/dev/null || echo "[]")
EXERCISE=$(jq -c '.exercise // {"days":{"lun":false,"mar":false,"mie":false,"jue":false,"vie":false,"sab":false,"dom":false},"goal":4}' "$DATA_FILE" 2>/dev/null)

# New widgets: preserve from file
TRENDING=$(jq -c '.trending // [{"category":"ia","title":"Cargando...","time":"--"}]' "$DATA_FILE" 2>/dev/null)
NIGHTLY=$(jq -c '.nightly // {"project":"--","status":"--"}' "$DATA_FILE" 2>/dev/null)
YESTERDAY=$(jq -c '.yesterday // []' "$DATA_FILE" 2>/dev/null)
PHOENIX_TASK=$(jq -r '.phoenix.currentTask // .jarvis.currentTask // "--"' "$DATA_FILE" 2>/dev/null)

# Thought message (preserve from file)
THOUGHT=$(jq -r '.thought // "🐦‍🔥"' "$DATA_FILE" 2>/dev/null || echo "🐦‍🔥")

# Fetch Iris metrics via SSH
IRIS_METRICS=$(ssh -o ConnectTimeout=2 -o StrictHostKeyChecking=no jmfraga@<tailscale-ip> "cat /home/jmfraga/.openclaw/workspace/shared_with_phoenix/outbox/iris-status.json 2>/dev/null" 2>/dev/null || echo '{"status":"offline"}')

# Extract Iris data
IRIS_STATUS=$(echo "$IRIS_METRICS" | jq -r '.status // "offline"' 2>/dev/null || echo "offline")
IRIS_VERSION=$(echo "$IRIS_METRICS" | jq -r '.openclaw.version // "n/a"' 2>/dev/null || echo "n/a")
IRIS_MODEL=$(echo "$IRIS_METRICS" | jq -r '.openclaw.model // "n/a"' 2>/dev/null || echo "n/a")
IRIS_CONTEXT=$(echo "$IRIS_METRICS" | jq -r '.openclaw.contextPercent // 0' 2>/dev/null || echo "0")
IRIS_CPU=$(echo "$IRIS_METRICS" | jq -r '.system.cpu // 0' 2>/dev/null || echo "0")
IRIS_RAM=$(echo "$IRIS_METRICS" | jq -r '.system.ram // 0' 2>/dev/null || echo "0")
IRIS_TEMP=$(echo "$IRIS_METRICS" | jq -r '.system.temp // 0' 2>/dev/null || echo "0")
IRIS_DISK=$(echo "$IRIS_METRICS" | jq -r '.system.disk // 0' 2>/dev/null || echo "0")
IRIS_UPTIME=$(echo "$IRIS_METRICS" | jq -r '.system.uptime // 0' 2>/dev/null || echo "0")
IRIS_TIMESTAMP=$(echo "$IRIS_METRICS" | jq -r '.timestamp // "unknown"' 2>/dev/null || echo "unknown")
IRIS_PENDING_PAIRS=$(echo "$IRIS_METRICS" | jq -r '.pendingPairs // 0' 2>/dev/null || echo "0")

# Determine fleet health
if [ "$IRIS_STATUS" = "online" ]; then
    FLEET_STATUS="🟢 Ambos sistemas operativos"
else
    FLEET_STATUS="🟡 Solo Phoenix operativo"
fi

# Extract Iris currentTask and yesterday from metrics
IRIS_CURRENT_TASK=$(echo "$IRIS_METRICS" | jq -r '.currentTask // "--"' 2>/dev/null || echo "--")

# Yesterday might be string (convert to array) or already array
IRIS_YESTERDAY_RAW=$(echo "$IRIS_METRICS" | jq -r '.yesterday // ""' 2>/dev/null || echo "")
if echo "$IRIS_YESTERDAY_RAW" | jq -e 'type == "array"' >/dev/null 2>&1; then
    IRIS_YESTERDAY="$IRIS_YESTERDAY_RAW"
elif [ -n "$IRIS_YESTERDAY_RAW" ] && [ "$IRIS_YESTERDAY_RAW" != "null" ]; then
    # Convert string with "- " bullets to array
    IRIS_YESTERDAY=$(echo "$IRIS_YESTERDAY_RAW" | grep -o '\- [^-]*' | sed 's/^- //' | jq -R -s 'split("\n") | map(select(length > 0))' 2>/dev/null || echo "[]")
else
    IRIS_YESTERDAY="[]"
fi

# If Iris has yesterday data, use it; otherwise use preserved
if [ "$IRIS_YESTERDAY" != "[]" ] && [ "$IRIS_YESTERDAY" != "null" ]; then
    YESTERDAY="$IRIS_YESTERDAY"
fi

# Build JSON
cat > "$DATA_FILE" << EOF
{
  "jarvis": {
    "status": "$JARVIS_STATUS",
    "version": "$JARVIS_VERSION",
    "thinking": $JARVIS_THINKING,
    "currentTask": "$PHOENIX_TASK"
  },
  "phoenix": {
    "currentTask": "$PHOENIX_TASK"
  },
  "iris": {
    "status": "$IRIS_STATUS",
    "version": "$IRIS_VERSION",
    "model": "$IRIS_MODEL",
    "currentTask": "$IRIS_CURRENT_TASK",
    "yesterday": $IRIS_YESTERDAY,
    "openclaw": {
      "version": "$IRIS_VERSION",
      "model": "$IRIS_MODEL",
      "contextPercent": $IRIS_CONTEXT
    },
    "system": {
      "cpu": $IRIS_CPU,
      "ram": $IRIS_RAM,
      "temp": $IRIS_TEMP,
      "disk": $IRIS_DISK
    },
    "uptime": $IRIS_UPTIME,
    "timestamp": "$IRIS_TIMESTAMP",
    "pendingPairs": $IRIS_PENDING_PAIRS
  },
  "fleet": {
    "status": "$FLEET_STATUS"
  },
  "weather": {
    "icon": "$WEATHER_ICON",
    "temp": "$WEATHER_TEMP",
    "desc": "Querétaro",
    "tip": "$WEATHER_TIP"
  },
  "model": {
    "name": "$MODEL_NAME",
    "contextPercent": $CONTEXT_PCT,
    "usageDay": "$USAGE_DAY",
    "usageWeek": "$USAGE_WEEK"
  },
  "system": {
    "cpu": $CPU,
    "ram": $RAM,
    "disk": $DISK
  },
  "calendar": $CALENDAR,
  "kanban": $KANBAN,
  "thought": "$THOUGHT",
  "notification": $( [ "$NOTIFICATION" = "null" ] && echo "null" || echo "\"$NOTIFICATION\"" ),
  "exercise": $EXERCISE,
  "trending": $TRENDING,
  "nightly": $NIGHTLY,
  "yesterday": $YESTERDAY
}
EOF
