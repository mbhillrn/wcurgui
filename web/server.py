#!/usr/bin/env python3
"""
MBTC-DASH - Web Server
Local web dashboard for Bitcoin Core peer monitoring
"""

import json
import os
import queue
import sqlite3
import subprocess
import sys
import threading
import time
from datetime import datetime
from pathlib import Path
from typing import Optional

from flask import Flask, jsonify, render_template, Response

import requests

# ═══════════════════════════════════════════════════════════════════════════════
# CONFIGURATION
# ═══════════════════════════════════════════════════════════════════════════════

REFRESH_INTERVAL = 10  # Seconds between peer refreshes
GEO_API_DELAY = 1.5    # Seconds between API calls (stay under 45/min limit)
GEO_API_URL = "http://ip-api.com/json"
GEO_API_FIELDS = "status,country,countryCode,region,regionName,city,district,lat,lon,isp,as,hosting,query"

# Paths - use local data folder within the project
SCRIPT_DIR = Path(__file__).parent
PROJECT_DIR = SCRIPT_DIR.parent
DATA_DIR = PROJECT_DIR / 'data'
CONFIG_FILE = DATA_DIR / 'config.conf'
DB_FILE = DATA_DIR / 'peers.db'
TEMPLATES_DIR = SCRIPT_DIR / 'templates'
STATIC_DIR = SCRIPT_DIR / 'static'

# Geo status codes
GEO_OK = 0
GEO_PRIVATE = 1
GEO_UNAVAILABLE = 2

# Retry intervals for GEO_UNAVAILABLE (in seconds): 1d, 3d, 7d, 7d...
RETRY_INTERVALS = [86400, 259200, 604800, 604800]

# Flask app
app = Flask(__name__,
            template_folder=str(TEMPLATES_DIR),
            static_folder=str(STATIC_DIR))

# Event queue for SSE updates
update_queue = queue.Queue()

# Current peer data (shared between threads)
current_peers = []
current_peers_lock = threading.Lock()

# ═══════════════════════════════════════════════════════════════════════════════
# CONFIG LOADING
# ═══════════════════════════════════════════════════════════════════════════════

class Config:
    """Load MBTC configuration from cache file"""

    def __init__(self):
        self.cli_path = "bitcoin-cli"
        self.datadir = ""
        self.conf = ""
        self.network = "main"
        self.rpc_host = "127.0.0.1"
        self.rpc_port = "8332"
        self.cookie_path = ""
        self.rpc_user = ""

    def load(self) -> bool:
        """Load config from cache file"""
        if not CONFIG_FILE.exists():
            return False

        try:
            with open(CONFIG_FILE, 'r') as f:
                for line in f:
                    line = line.strip()
                    if line.startswith('#') or '=' not in line:
                        continue
                    key, value = line.split('=', 1)
                    value = value.strip('"').strip("'")

                    if key == 'MBTC_CLI_PATH':
                        self.cli_path = value
                    elif key == 'MBTC_DATADIR':
                        self.datadir = value
                    elif key == 'MBTC_CONF':
                        self.conf = value
                    elif key == 'MBTC_NETWORK':
                        self.network = value
                    elif key == 'MBTC_RPC_HOST':
                        self.rpc_host = value
                    elif key == 'MBTC_RPC_PORT':
                        self.rpc_port = value
                    elif key == 'MBTC_COOKIE_PATH':
                        self.cookie_path = value
                    elif key == 'MBTC_RPC_USER':
                        self.rpc_user = value

            return bool(self.cli_path)
        except Exception:
            return False

    def get_cli_command(self) -> list:
        """Build bitcoin-cli command with all necessary flags"""
        cmd = [self.cli_path]

        if self.datadir:
            cmd.append(f"-datadir={self.datadir}")
        if self.conf:
            cmd.append(f"-conf={self.conf}")

        if self.network == "test":
            cmd.append("-testnet")
        elif self.network == "signet":
            cmd.append("-signet")
        elif self.network == "regtest":
            cmd.append("-regtest")

        return cmd


config = Config()


# ═══════════════════════════════════════════════════════════════════════════════
# DATABASE FUNCTIONS
# ═══════════════════════════════════════════════════════════════════════════════

def init_database():
    """Initialize SQLite database for peer geo caching"""
    DATA_DIR.mkdir(parents=True, exist_ok=True)

    conn = sqlite3.connect(DB_FILE)
    conn.execute('''
        CREATE TABLE IF NOT EXISTS peers_geo (
            ip TEXT PRIMARY KEY,
            network_type TEXT,
            geo_status INTEGER DEFAULT 0,
            geo_retry_count INTEGER DEFAULT 0,
            geo_last_lookup INTEGER,
            country TEXT,
            country_code TEXT,
            region TEXT,
            region_name TEXT,
            city TEXT,
            district TEXT,
            lat REAL,
            lon REAL,
            isp TEXT,
            as_info TEXT,
            hosting INTEGER,
            first_seen INTEGER,
            last_seen INTEGER,
            connection_count INTEGER DEFAULT 1
        )
    ''')
    conn.execute('CREATE INDEX IF NOT EXISTS idx_geo_status ON peers_geo(geo_status)')
    conn.execute('CREATE INDEX IF NOT EXISTS idx_last_seen ON peers_geo(last_seen)')
    conn.execute('CREATE INDEX IF NOT EXISTS idx_network_type ON peers_geo(network_type)')
    conn.commit()
    conn.close()


def get_peer_geo(ip: str) -> Optional[dict]:
    """Get cached geo data for a peer"""
    conn = sqlite3.connect(DB_FILE)
    conn.row_factory = sqlite3.Row
    cursor = conn.execute('SELECT * FROM peers_geo WHERE ip = ?', (ip,))
    row = cursor.fetchone()
    conn.close()
    return dict(row) if row else None


def should_retry_geo(ip: str) -> bool:
    """Check if we should retry geo lookup for an unavailable IP"""
    geo = get_peer_geo(ip)
    if not geo:
        return True

    if geo['geo_status'] in (GEO_OK, GEO_PRIVATE):
        return False

    # Calculate retry interval
    retry_count = geo['geo_retry_count'] or 0
    interval_idx = min(retry_count, len(RETRY_INTERVALS) - 1)
    interval = RETRY_INTERVALS[interval_idx]

    elapsed = int(time.time()) - (geo['geo_last_lookup'] or 0)
    return elapsed >= interval


def upsert_peer_geo(ip: str, network_type: str, geo_status: int,
                    country: str = "", country_code: str = "",
                    region: str = "", region_name: str = "",
                    city: str = "", district: str = "",
                    lat: float = 0, lon: float = 0,
                    isp: str = "", as_info: str = "", hosting: int = 0):
    """Insert or update peer geo data"""
    now = int(time.time())
    conn = sqlite3.connect(DB_FILE)

    conn.execute('''
        INSERT INTO peers_geo (
            ip, network_type, geo_status, geo_last_lookup,
            country, country_code, region, region_name, city, district,
            lat, lon, isp, as_info, hosting,
            first_seen, last_seen, connection_count
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 1)
        ON CONFLICT(ip) DO UPDATE SET
            geo_status = excluded.geo_status,
            geo_last_lookup = excluded.geo_last_lookup,
            geo_retry_count = CASE WHEN excluded.geo_status = ? THEN geo_retry_count + 1 ELSE 0 END,
            country = COALESCE(NULLIF(excluded.country, ''), country),
            country_code = COALESCE(NULLIF(excluded.country_code, ''), country_code),
            region = COALESCE(NULLIF(excluded.region, ''), region),
            region_name = COALESCE(NULLIF(excluded.region_name, ''), region_name),
            city = COALESCE(NULLIF(excluded.city, ''), city),
            district = COALESCE(NULLIF(excluded.district, ''), district),
            lat = CASE WHEN excluded.lat != 0 THEN excluded.lat ELSE lat END,
            lon = CASE WHEN excluded.lon != 0 THEN excluded.lon ELSE lon END,
            isp = COALESCE(NULLIF(excluded.isp, ''), isp),
            as_info = COALESCE(NULLIF(excluded.as_info, ''), as_info),
            hosting = excluded.hosting,
            last_seen = excluded.last_seen,
            connection_count = connection_count + 1
    ''', (ip, network_type, geo_status, now,
          country, country_code, region, region_name, city, district,
          lat, lon, isp, as_info, hosting,
          now, now, GEO_UNAVAILABLE))

    conn.commit()
    conn.close()


def update_peer_seen(ip: str):
    """Update last_seen timestamp"""
    now = int(time.time())
    conn = sqlite3.connect(DB_FILE)
    conn.execute('UPDATE peers_geo SET last_seen = ? WHERE ip = ?', (now, ip))
    conn.commit()
    conn.close()


def get_peer_stats() -> dict:
    """Get database statistics"""
    conn = sqlite3.connect(DB_FILE)
    cursor = conn.execute('''
        SELECT
            COUNT(*) as total,
            SUM(CASE WHEN geo_status = 0 THEN 1 ELSE 0 END) as geo_ok,
            SUM(CASE WHEN geo_status = 1 THEN 1 ELSE 0 END) as private,
            SUM(CASE WHEN geo_status = 2 THEN 1 ELSE 0 END) as unavailable,
            SUM(CASE WHEN network_type = 'ipv4' THEN 1 ELSE 0 END) as ipv4,
            SUM(CASE WHEN network_type = 'ipv6' THEN 1 ELSE 0 END) as ipv6,
            SUM(CASE WHEN network_type = 'onion' THEN 1 ELSE 0 END) as onion,
            SUM(CASE WHEN network_type = 'i2p' THEN 1 ELSE 0 END) as i2p,
            SUM(CASE WHEN network_type = 'cjdns' THEN 1 ELSE 0 END) as cjdns
        FROM peers_geo
    ''')
    row = cursor.fetchone()
    conn.close()

    return {
        'total': row[0] or 0,
        'geo_ok': row[1] or 0,
        'private': row[2] or 0,
        'unavailable': row[3] or 0,
        'ipv4': row[4] or 0,
        'ipv6': row[5] or 0,
        'onion': row[6] or 0,
        'i2p': row[7] or 0,
        'cjdns': row[8] or 0,
    }


# ═══════════════════════════════════════════════════════════════════════════════
# NETWORK UTILITIES
# ═══════════════════════════════════════════════════════════════════════════════

def get_network_type(addr: str) -> str:
    """Determine network type from address"""
    if '.onion' in addr:
        return 'onion'
    elif '.i2p' in addr:
        return 'i2p'
    elif addr.startswith('fc') or addr.startswith('fd'):
        return 'cjdns'
    elif ':' in addr and addr.count(':') > 1:
        return 'ipv6'
    else:
        return 'ipv4'


def is_public_address(network_type: str) -> bool:
    """Check if address can be geolocated"""
    return network_type in ('ipv4', 'ipv6')


def extract_ip(addr: str) -> str:
    """Extract IP from address (remove port)"""
    # IPv6 with port: [2001:db8::1]:8333
    if addr.startswith('['):
        return addr.split(']')[0][1:]
    # IPv4 with port or other
    elif ':' in addr and not addr.count(':') > 1:
        return addr.rsplit(':', 1)[0]
    else:
        return addr.split(':')[0] if ':' in addr else addr


def fetch_geo_api(ip: str) -> Optional[dict]:
    """Fetch geo data from API"""
    try:
        url = f"{GEO_API_URL}/{ip}?fields={GEO_API_FIELDS}"
        response = requests.get(url, timeout=10)
        data = response.json()

        if data.get('status') == 'success':
            return data
    except Exception:
        pass
    return None


def format_bytes(bytes_val: int) -> str:
    """Format bytes to human readable"""
    if bytes_val >= 1073741824:
        return f"{bytes_val / 1073741824:.1f}GB"
    elif bytes_val >= 1048576:
        return f"{bytes_val / 1048576:.1f}MB"
    elif bytes_val >= 1024:
        return f"{bytes_val / 1024:.1f}KB"
    else:
        return f"{bytes_val}B"


def format_conntime(conntime: int) -> str:
    """Format connection time to human readable"""
    if not conntime:
        return "-"
    elapsed = int(time.time()) - conntime
    if elapsed < 3600:
        return f"{elapsed // 60}m"
    elif elapsed < 86400:
        hours = elapsed // 3600
        mins = (elapsed % 3600) // 60
        return f"{hours}h {mins}m"
    else:
        days = elapsed // 86400
        hours = (elapsed % 86400) // 3600
        return f"{days}d {hours}h"


# ═══════════════════════════════════════════════════════════════════════════════
# BITCOIN RPC
# ═══════════════════════════════════════════════════════════════════════════════

def get_peer_info() -> list:
    """Get peer info from bitcoin-cli"""
    try:
        cmd = config.get_cli_command() + ['getpeerinfo']
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
        if result.returncode == 0:
            return json.loads(result.stdout)
    except Exception:
        pass
    return []


# ═══════════════════════════════════════════════════════════════════════════════
# BACKGROUND GEO LOOKUP
# ═══════════════════════════════════════════════════════════════════════════════

def geo_lookup_worker():
    """Background worker that processes geo lookups one at a time"""
    while True:
        time.sleep(1)  # Check every second

        with current_peers_lock:
            peers_snapshot = list(current_peers)

        for peer in peers_snapshot:
            addr = peer.get('addr', '')
            network_type = peer.get('network', get_network_type(addr))
            ip = extract_ip(addr)

            if is_public_address(network_type):
                if should_retry_geo(ip):
                    # Do the geo lookup
                    data = fetch_geo_api(ip)

                    if data:
                        upsert_peer_geo(
                            ip, network_type, GEO_OK,
                            data.get('country', ''),
                            data.get('countryCode', ''),
                            data.get('region', ''),
                            data.get('regionName', ''),
                            data.get('city', ''),
                            data.get('district', ''),
                            data.get('lat', 0),
                            data.get('lon', 0),
                            data.get('isp', ''),
                            data.get('as', ''),
                            1 if data.get('hosting') else 0
                        )
                    else:
                        upsert_peer_geo(ip, network_type, GEO_UNAVAILABLE)

                    # Notify clients of update
                    try:
                        update_queue.put_nowait({'type': 'geo_update', 'ip': ip})
                    except queue.Full:
                        pass

                    # Rate limit
                    time.sleep(GEO_API_DELAY)
            elif not get_peer_geo(ip):
                # Private network, insert with PRIVATE status
                upsert_peer_geo(ip, network_type, GEO_PRIVATE)


def peer_refresh_worker():
    """Background worker that periodically refreshes peer list"""
    while True:
        peers = get_peer_info()

        with current_peers_lock:
            global current_peers
            current_peers = peers

        # Update last_seen for all current peers
        for peer in peers:
            addr = peer.get('addr', '')
            ip = extract_ip(addr)
            if get_peer_geo(ip):
                update_peer_seen(ip)

        # Notify clients
        try:
            update_queue.put_nowait({'type': 'peers_update'})
        except queue.Full:
            pass

        time.sleep(REFRESH_INTERVAL)


# ═══════════════════════════════════════════════════════════════════════════════
# API ENDPOINTS
# ═══════════════════════════════════════════════════════════════════════════════

@app.route('/')
def index():
    """Serve main dashboard page"""
    return render_template('index.html')


@app.route('/api/peers')
def api_peers():
    """Get current peer list with geo data"""
    with current_peers_lock:
        peers_snapshot = list(current_peers)

    result = []
    for peer in peers_snapshot:
        addr = peer.get('addr', '')
        network_type = peer.get('network', get_network_type(addr))
        ip = extract_ip(addr)

        geo = get_peer_geo(ip)

        # Format location
        if network_type in ('onion', 'i2p', 'cjdns'):
            location = "PRIVATE LOCATION"
            country_code = "PRIV"
        elif geo and geo['geo_status'] == GEO_OK and geo.get('city'):
            location = f"{geo['city']}, {geo['country_code']}"
            country_code = geo['country_code']
        elif geo and geo['geo_status'] == GEO_PRIVATE:
            location = "PRIVATE LOCATION"
            country_code = "PRIV"
        else:
            location = "LOCATION UNAVAILABLE"
            country_code = "N/A"

        # Format ping
        ping = peer.get('pingtime') or peer.get('pingwait') or 0
        ping_ms = int(ping * 1000) if ping else None

        result.append({
            'id': peer.get('id', ''),
            'addr': addr,
            'ip': ip,
            'network': network_type,
            'location': location,
            'country_code': country_code,
            'country': geo.get('country', '') if geo else '',
            'region': geo.get('region_name', '') if geo else '',
            'city': geo.get('city', '') if geo else '',
            'lat': geo.get('lat', 0) if geo else 0,
            'lon': geo.get('lon', 0) if geo else 0,
            'isp': geo.get('isp', '') if geo else '',
            'as_info': geo.get('as_info', '') if geo else '',
            'inbound': peer.get('inbound', False),
            'direction': 'IN' if peer.get('inbound') else 'OUT',
            'ping_ms': ping_ms,
            'bytessent': peer.get('bytessent', 0),
            'bytesrecv': peer.get('bytesrecv', 0),
            'bytessent_fmt': format_bytes(peer.get('bytessent', 0)),
            'bytesrecv_fmt': format_bytes(peer.get('bytesrecv', 0)),
            'subver': peer.get('subver', '').replace('/', ''),
            'version': peer.get('version', ''),
            'conntime': peer.get('conntime', 0),
            'conntime_fmt': format_conntime(peer.get('conntime', 0)),
            'services': peer.get('servicesnames', []),
            'connection_type': peer.get('connection_type', ''),
            'lastsend': peer.get('lastsend', 0),
            'lastrecv': peer.get('lastrecv', 0),
        })

    return jsonify(result)


@app.route('/api/stats')
def api_stats():
    """Get database statistics"""
    stats = get_peer_stats()
    with current_peers_lock:
        stats['connected'] = len(current_peers)
    stats['last_update'] = datetime.now().strftime('%Y-%m-%d %H:%M:%S')
    return jsonify(stats)


@app.route('/api/events')
def api_events():
    """Server-Sent Events endpoint for real-time updates"""
    def generate():
        # Send initial connection event
        yield f"data: {json.dumps({'type': 'connected'})}\n\n"

        while True:
            try:
                # Wait for update with timeout
                event = update_queue.get(timeout=30)
                yield f"data: {json.dumps(event)}\n\n"
            except queue.Empty:
                # Send keepalive
                yield f"data: {json.dumps({'type': 'keepalive'})}\n\n"

    return Response(generate(), mimetype='text/event-stream')


# ═══════════════════════════════════════════════════════════════════════════════
# MAIN
# ═══════════════════════════════════════════════════════════════════════════════

def main():
    # Initialize
    init_database()

    # Load config
    if not config.load():
        print("Error: Configuration not found. Run ./da.sh first to configure.")
        sys.exit(1)

    # Do initial peer fetch
    global current_peers
    current_peers = get_peer_info()
    print(f"Initial fetch: {len(current_peers)} peers found")

    # Start background workers
    geo_thread = threading.Thread(target=geo_lookup_worker, daemon=True)
    geo_thread.start()

    refresh_thread = threading.Thread(target=peer_refresh_worker, daemon=True)
    refresh_thread.start()

    # Start Flask server
    print("\n" + "="*60)
    print("  MBTC-DASH Web Server")
    print("="*60)
    print(f"\n  Open in browser: http://127.0.0.1:5000")
    print(f"  Press Ctrl+C to stop\n")

    app.run(host='127.0.0.1', port=5000, debug=False, threaded=True)


if __name__ == "__main__":
    main()
