#!/usr/bin/env python3
"""
Clawdbot Health Dashboard - Lightweight monitoring server
Run: python3 server.py [port]
Default port: 8765
"""

import json
import subprocess
import os
import sys
from http.server import HTTPServer, SimpleHTTPRequestHandler
from datetime import datetime
import urllib.parse

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8765

def run_cmd(cmd, timeout=5):
    """Run a shell command and return output"""
    try:
        result = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=timeout)
        return result.stdout.strip()
    except:
        return None

def get_system_info():
    """Collect system information"""
    info = {
        "timestamp": datetime.now().isoformat(),
        "hostname": run_cmd("hostname"),
        "os": run_cmd("uname -s"),
        "os_version": run_cmd("sw_vers -productVersion") or run_cmd("uname -r"),
        "arch": run_cmd("uname -m"),
        "uptime": run_cmd("uptime"),
    }
    
    # CPU info
    cpu_usage = run_cmd("ps -A -o %cpu | awk '{s+=$1} END {print s}'")
    info["cpu_usage_percent"] = round(float(cpu_usage), 1) if cpu_usage else None
    info["cpu_cores"] = run_cmd("sysctl -n hw.ncpu")
    
    # Memory (macOS)
    mem_total = run_cmd("sysctl -n hw.memsize")
    if mem_total:
        mem_total_gb = int(mem_total) / (1024**3)
        info["memory_total_gb"] = round(mem_total_gb, 1)
    
    # Memory pressure (macOS)
    vm_stat = run_cmd("vm_stat")
    if vm_stat:
        lines = vm_stat.split('\n')
        stats = {}
        for line in lines[1:]:
            if ':' in line:
                key, val = line.split(':')
                val = val.strip().rstrip('.')
                if val.isdigit():
                    stats[key.strip()] = int(val)
        
        page_size = 16384  # macOS default
        free = stats.get('Pages free', 0) * page_size
        active = stats.get('Pages active', 0) * page_size
        inactive = stats.get('Pages inactive', 0) * page_size
        wired = stats.get('Pages wired down', 0) * page_size
        compressed = stats.get('Pages occupied by compressor', 0) * page_size
        
        used = active + wired + compressed
        total = free + used + inactive
        if total > 0:
            info["memory_used_percent"] = round((used / total) * 100, 1)
            info["memory_used_gb"] = round(used / (1024**3), 1)
    
    # Disk usage
    disk = run_cmd("df -h / | tail -1 | awk '{print $5}'")
    info["disk_usage_percent"] = disk.rstrip('%') if disk else None
    disk_avail = run_cmd("df -h / | tail -1 | awk '{print $4}'")
    info["disk_available"] = disk_avail
    
    # Temperature (macOS - requires powermetrics or osx-cpu-temp)
    temp = run_cmd("which osx-cpu-temp > /dev/null && osx-cpu-temp 2>/dev/null")
    if temp:
        info["cpu_temp"] = temp
    else:
        # Try alternative
        temp = run_cmd("sudo powermetrics -n 1 -i 1 --samplers smc 2>/dev/null | grep 'CPU die temperature' | awk '{print $4}'")
        info["cpu_temp"] = f"{temp}°C" if temp else "N/A (install osx-cpu-temp)"
    
    # Load average
    load = run_cmd("sysctl -n vm.loadavg")
    if load:
        info["load_average"] = load.strip('{}').strip()
    
    return info

def get_clawdbot_info():
    """Get Clawdbot health info"""
    health_json = run_cmd("clawdbot health --json 2>/dev/null", timeout=10)
    if health_json:
        try:
            return json.loads(health_json)
        except:
            pass
    return {"error": "Could not fetch Clawdbot health"}

def get_clawdbot_status():
    """Get Clawdbot status summary"""
    status = run_cmd("clawdbot status 2>/dev/null", timeout=10)
    return status or "Could not fetch status"

def get_recent_logs():
    """Get recent Clawdbot logs (errors only)"""
    logs = run_cmd("clawdbot logs 2>&1 | grep -i 'error\\|warn' | tail -10", timeout=5)
    return logs.split('\n') if logs else []

def get_session_status():
    """Get current session info"""
    sessions = run_cmd("clawdbot sessions --limit 5 --json 2>/dev/null", timeout=10)
    if sessions:
        try:
            return json.loads(sessions)
        except:
            pass
    return None

class DashboardHandler(SimpleHTTPRequestHandler):
    def do_GET(self):
        parsed = urllib.parse.urlparse(self.path)
        
        if parsed.path == '/api/health':
            self.send_json({
                "system": get_system_info(),
                "clawdbot": get_clawdbot_info(),
                "errors": get_recent_logs(),
            })
        elif parsed.path == '/api/status':
            self.send_json({
                "status": get_clawdbot_status(),
                "sessions": get_session_status(),
            })
        elif parsed.path == '/' or parsed.path == '/index.html':
            self.path = '/index.html'
            return SimpleHTTPRequestHandler.do_GET(self)
        else:
            return SimpleHTTPRequestHandler.do_GET(self)
    
    def send_json(self, data):
        self.send_response(200)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Access-Control-Allow-Origin', '*')
        self.end_headers()
        self.wfile.write(json.dumps(data, indent=2).encode())
    
    def log_message(self, format, *args):
        pass  # Quiet logging

if __name__ == '__main__':
    os.chdir(os.path.dirname(os.path.abspath(__file__)))
    server = HTTPServer(('0.0.0.0', PORT), DashboardHandler)
    print(f"🦞 Clawdbot Dashboard running on http://0.0.0.0:{PORT}")
    print(f"   Access via Tailscale: http://<tailscale-ip>:{PORT}")
    server.serve_forever()
