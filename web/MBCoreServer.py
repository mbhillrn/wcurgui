#!/usr/bin/env python3
"""
MBTC-DASH - FastAPI Web Server
Local web dashboard for Bitcoin Core peer monitoring

Features:
- Fixed port 58333 (or manual selection if blocked)
- Real-time updates via Server-Sent Events
- Map with Leaflet.js
- All peer columns available
"""

import json
import os
import queue
import socket
import sqlite3
import subprocess
import sys
import threading
import time
from datetime import datetime
from pathlib import Path
from typing import Optional

import requests
import uvicorn
from fastapi import FastAPI, Request
from fastapi.responses import HTMLResponse
from fastapi.staticfiles import StaticFiles
from fastapi.templating import Jinja2Templates
from sse_starlette.sse import EventSourceResponse

# ═══════════════════════════════════════════════════════════════════════════════
# CONFIGURATION
# ═══════════════════════════════════════════════════════════════════════════════

REFRESH_INTERVAL = 10  # Seconds between peer refreshes
GEO_API_DELAY = 1.5    # Seconds between API calls
GEO_API_URL = "http://ip-api.com/json"
# All available fields from ip-api.com (except query, status, message, reverse)
GEO_API_FIELDS = "status,continent,continentCode,country,countryCode,region,regionName,city,district,zip,lat,lon,timezone,offset,currency,isp,org,as,asname,mobile,proxy,hosting"
RECENT_WINDOW = 20     # Seconds for recent changes

# Geo database repository URL
GEO_DB_REPO_URL = "https://raw.githubusercontent.com/mbhillrn/Bitcoin-Node-GeoIP-Dataset/main/geo.db"

# Default port for web dashboard (can be configured)
DEFAULT_WEB_PORT = 58333

# Paths
SCRIPT_DIR = Path(__file__).parent
PROJECT_DIR = SCRIPT_DIR.parent
DATA_DIR = PROJECT_DIR / 'data'
TMP_DIR = DATA_DIR / 'tmp'
CONFIG_FILE = DATA_DIR / 'config.conf'
GEO_DB_FILE = DATA_DIR / 'geo.db'  # Geolocation cache database
STATIC_DIR = SCRIPT_DIR / 'static'
TEMPLATES_DIR = SCRIPT_DIR / 'templates'
VERSION_FILE = PROJECT_DIR / 'VERSION'

# Read version from file
def get_version():
    try:
        return VERSION_FILE.read_text().strip()
    except Exception:
        return "0.0.0"

VERSION = get_version()


def get_configured_port():
    """Read configured port from config file, return default if not set"""
    try:
        if CONFIG_FILE.exists():
            with open(CONFIG_FILE, 'r') as f:
                for line in f:
                    line = line.strip()
                    if line.startswith('MBTC_WEB_PORT='):
                        value = line.split('=', 1)[1].strip('"').strip("'")
                        port = int(value)
                        if 1024 <= port <= 65535:
                            return port
    except Exception:
        pass
    return DEFAULT_WEB_PORT


def save_port_to_config(port: int):
    """Save the port to the config file (for port busy scenarios)"""
    try:
        if CONFIG_FILE.exists():
            lines = CONFIG_FILE.read_text().splitlines()
            found = False
            new_lines = []
            for line in lines:
                if line.startswith('MBTC_WEB_PORT='):
                    new_lines.append(f'MBTC_WEB_PORT="{port}"')
                    found = True
                else:
                    new_lines.append(line)
            if not found:
                # Add before MBTC_CONFIGURED line if it exists
                final_lines = []
                for line in new_lines:
                    if line.startswith('MBTC_CONFIGURED='):
                        final_lines.append(f'MBTC_WEB_PORT="{port}"')
                    final_lines.append(line)
                new_lines = final_lines if final_lines else new_lines + [f'MBTC_WEB_PORT="{port}"']
            CONFIG_FILE.write_text('\n'.join(new_lines) + '\n')
    except Exception as e:
        print(f"Warning: Could not save port to config: {e}")


def detect_active_firewall():
    """Detect if ufw or firewalld is active. Returns (name, is_active) or (None, False)"""
    try:
        # Check ufw first
        result = subprocess.run(
            ['systemctl', 'is-active', 'ufw'],
            capture_output=True, text=True, timeout=5
        )
        if result.stdout.strip() == 'active':
            return ('ufw', True)
    except Exception:
        pass

    try:
        # Check firewalld
        result = subprocess.run(
            ['systemctl', 'is-active', 'firewalld'],
            capture_output=True, text=True, timeout=5
        )
        if result.stdout.strip() == 'active':
            return ('firewalld', True)
    except Exception:
        pass

    return (None, False)

# Geo status codes
GEO_OK = 0
GEO_PRIVATE = 1
GEO_UNAVAILABLE = 2

RETRY_INTERVALS = [86400, 259200, 604800, 604800]

# ═══════════════════════════════════════════════════════════════════════════════
# GLOBAL STATE
# ═══════════════════════════════════════════════════════════════════════════════

# FastAPI app
app = FastAPI(title="MBTC-DASH", description="Bitcoin Peer Dashboard")
templates = Jinja2Templates(directory=str(TEMPLATES_DIR))

# Thread-safe state
current_peers = []
peers_lock = threading.Lock()

recent_changes = []
changes_lock = threading.Lock()

geo_queue = queue.Queue()
pending_lookups = set()
pending_lock = threading.Lock()

stop_flag = threading.Event()

# SSE clients and update events
sse_update_event = threading.Event()
last_update_type = "connected"

# ═══════════════════════════════════════════════════════════════════════════════
# SESSION CACHE (in-memory, cleared on restart)
# ═══════════════════════════════════════════════════════════════════════════════

# Geo cache: {ip: {continent, continentCode, country, countryCode, region, regionName, city, lat, lon, isp, status}}
geo_cache = {}
geo_cache_lock = threading.Lock()

# Peer ID to IP mapping (so we have IP when peer disconnects)
peer_ip_map = {}
peer_ip_map_lock = threading.Lock()

# Track pending geo lookups count for map status
geo_pending_count = 0
geo_pending_lock = threading.Lock()

# Addrman cache: {addr: True/False} - populated from getnodeaddresses
addrman_cache = set()
addrman_cache_lock = threading.Lock()


# ═══════════════════════════════════════════════════════════════════════════════
# CONFIG
# ═══════════════════════════════════════════════════════════════════════════════

class Config:
    def __init__(self):
        self.cli_path = "bitcoin-cli"
        self.datadir = ""
        self.conf = ""
        self.network = "main"
        self._raw_config = {}  # Store all config values

    def load(self) -> bool:
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
                    self._raw_config[key] = value
                    if key == 'MBTC_CLI_PATH':
                        self.cli_path = value
                    elif key == 'MBTC_DATADIR':
                        self.datadir = value
                    elif key == 'MBTC_CONF':
                        self.conf = value
                    elif key == 'MBTC_NETWORK':
                        self.network = value
            return bool(self.cli_path)
        except Exception:
            return False

    def get(self, key: str, default: str = '') -> str:
        """Get a config value by key with optional default"""
        return self._raw_config.get(key, default)

    def get_cli_command(self) -> list:
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
# GEOLOCATION DATABASE (geo.db)
# ═══════════════════════════════════════════════════════════════════════════════

# Database settings (loaded from config)
geo_db_enabled = False
geo_db_auto_update = True

def cleanup_tmp_dir():
    """Remove any leftover temp files from interrupted downloads"""
    if TMP_DIR.exists():
        for f in TMP_DIR.iterdir():
            try:
                f.unlink()
            except Exception:
                pass


def init_geo_database():
    """Initialize the geolocation database with full schema"""
    DATA_DIR.mkdir(parents=True, exist_ok=True)
    TMP_DIR.mkdir(parents=True, exist_ok=True)
    cleanup_tmp_dir()
    conn = sqlite3.connect(GEO_DB_FILE)
    conn.execute('''
        CREATE TABLE IF NOT EXISTS geo_cache (
            ip TEXT PRIMARY KEY,
            continent TEXT,
            continentCode TEXT,
            country TEXT,
            countryCode TEXT,
            region TEXT,
            regionName TEXT,
            city TEXT,
            district TEXT,
            zip TEXT,
            lat REAL,
            lon REAL,
            timezone TEXT,
            utc_offset INTEGER,
            currency TEXT,
            isp TEXT,
            org TEXT,
            as_info TEXT,
            asname TEXT,
            mobile INTEGER DEFAULT 0,
            proxy INTEGER DEFAULT 0,
            hosting INTEGER DEFAULT 0,
            last_updated INTEGER
        )
    ''')
    conn.execute('CREATE INDEX IF NOT EXISTS idx_geo_country ON geo_cache(countryCode)')
    conn.execute('CREATE INDEX IF NOT EXISTS idx_geo_updated ON geo_cache(last_updated)')
    conn.execute('PRAGMA journal_mode=WAL')
    conn.commit()
    conn.close()


def check_geo_db_integrity() -> tuple:
    """Check database integrity. Returns (is_ok, message)"""
    if not GEO_DB_FILE.exists():
        return (True, "Database does not exist yet")
    try:
        conn = sqlite3.connect(GEO_DB_FILE)
        cursor = conn.execute("PRAGMA integrity_check")
        result = cursor.fetchone()[0]
        conn.close()
        if result == "ok":
            return (True, "Database integrity OK")
        else:
            return (False, f"Integrity check failed: {result}")
    except Exception as e:
        return (False, f"Error checking database: {str(e)}")


def get_geo_db_stats() -> dict:
    """Get statistics about the geo database with status"""
    base = {'status': 'disabled', 'entries': 0, 'size_mb': 0, 'last_updated': None, 'oldest_updated': None, 'db_path': str(GEO_DB_FILE)}
    if not geo_db_enabled:
        return base
    if not GEO_DB_FILE.exists():
        base['status'] = 'not_found'
        return base
    try:
        conn = sqlite3.connect(GEO_DB_FILE)
        cursor = conn.execute('SELECT COUNT(*) FROM geo_cache')
        count = cursor.fetchone()[0]
        cursor = conn.execute('SELECT MAX(last_updated) FROM geo_cache')
        last = cursor.fetchone()[0]
        cursor = conn.execute('SELECT MIN(last_updated) FROM geo_cache WHERE last_updated > 0')
        oldest = cursor.fetchone()[0]
        conn.close()
        size_mb = GEO_DB_FILE.stat().st_size / (1024 * 1024)
        base.update({'status': 'ok', 'entries': count, 'size_mb': round(size_mb, 2), 'last_updated': last, 'oldest_updated': oldest})
        return base
    except Exception as e:
        base['status'] = 'error'
        base['error'] = str(e)
        return base


def get_geo_from_db(ip: str) -> Optional[dict]:
    """Look up IP in geo database"""
    if not geo_db_enabled or not GEO_DB_FILE.exists():
        return None
    try:
        conn = sqlite3.connect(GEO_DB_FILE)
        conn.row_factory = sqlite3.Row
        cursor = conn.execute('SELECT * FROM geo_cache WHERE ip = ?', (ip,))
        row = cursor.fetchone()
        conn.close()
        return dict(row) if row else None
    except:
        return None


def save_geo_to_db(ip: str, data: dict):
    """Save geo data to database"""
    if not geo_db_enabled:
        return
    try:
        now = int(time.time())
        conn = sqlite3.connect(GEO_DB_FILE, timeout=5)
        conn.execute('''
            INSERT INTO geo_cache (
                ip, continent, continentCode, country, countryCode,
                region, regionName, city, district, zip,
                lat, lon, timezone, utc_offset, currency,
                isp, org, as_info, asname, mobile, proxy, hosting, last_updated
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(ip) DO UPDATE SET
                continent = excluded.continent,
                continentCode = excluded.continentCode,
                country = excluded.country,
                countryCode = excluded.countryCode,
                region = excluded.region,
                regionName = excluded.regionName,
                city = excluded.city,
                district = excluded.district,
                zip = excluded.zip,
                lat = excluded.lat,
                lon = excluded.lon,
                timezone = excluded.timezone,
                utc_offset = excluded.utc_offset,
                currency = excluded.currency,
                isp = excluded.isp,
                org = excluded.org,
                as_info = excluded.as_info,
                asname = excluded.asname,
                mobile = excluded.mobile,
                proxy = excluded.proxy,
                hosting = excluded.hosting,
                last_updated = excluded.last_updated
        ''', (
            ip,
            data.get('continent', ''),
            data.get('continentCode', ''),
            data.get('country', ''),
            data.get('countryCode', ''),
            data.get('region', ''),
            data.get('regionName', ''),
            data.get('city', ''),
            data.get('district', ''),
            data.get('zip', ''),
            data.get('lat', 0),
            data.get('lon', 0),
            data.get('timezone', ''),
            data.get('offset', 0),
            data.get('currency', ''),
            data.get('isp', ''),
            data.get('org', ''),
            data.get('as', ''),
            data.get('asname', ''),
            1 if data.get('mobile', False) else 0,
            1 if data.get('proxy', False) else 0,
            1 if data.get('hosting', False) else 0,
            now
        ))
        conn.commit()
        conn.close()
    except Exception as e:
        print(f"Error saving to geo database: {e}")


def refresh_addrman_cache():
    """Refresh the addrman cache from getnodeaddresses"""
    global addrman_cache
    try:
        cmd = config.get_cli_command() + ['getnodeaddresses', '0']  # 0 = all addresses
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
        if result.returncode == 0:
            addresses = json.loads(result.stdout)
            new_cache = set()
            for addr_info in addresses:
                addr = addr_info.get('address', '')
                if addr:
                    new_cache.add(addr)
            with addrman_cache_lock:
                addrman_cache = new_cache
    except Exception as e:
        print(f"Addrman refresh error: {e}")


def is_in_addrman(ip: str) -> bool:
    """Check if an IP is in the addrman cache"""
    with addrman_cache_lock:
        return ip in addrman_cache


# ═══════════════════════════════════════════════════════════════════════════════
# NETWORK UTILITIES
# ═══════════════════════════════════════════════════════════════════════════════

def get_network_type(addr: str) -> str:
    if '.onion' in addr:
        return 'onion'
    elif '.i2p' in addr:
        return 'i2p'
    elif addr.startswith('fc') or addr.startswith('fd'):
        return 'cjdns'
    elif ':' in addr and addr.count(':') > 1:
        return 'ipv6'
    return 'ipv4'


def is_private_ip(ip: str) -> bool:
    if ip.startswith('10.') or ip.startswith('192.168.'):
        return True
    if ip.startswith('172.'):
        try:
            if 16 <= int(ip.split('.')[1]) <= 31:
                return True
        except:
            pass
    if ip.startswith('127.') or ip == 'localhost':
        return True
    if ip.startswith('fe80:') or ip == '::1':
        return True
    return False


def is_public_address(network_type: str, ip: str) -> bool:
    return network_type in ('ipv4', 'ipv6') and not is_private_ip(ip)


def extract_ip(addr: str) -> str:
    if addr.startswith('['):
        return addr.split(']')[0][1:]
    elif ':' in addr and addr.count(':') <= 1:
        return addr.rsplit(':', 1)[0]
    return addr.split(':')[0] if ':' in addr else addr


def extract_port(addr: str) -> str:
    if addr.startswith('[') and ']:' in addr:
        return addr.split(']:')[1]
    elif ':' in addr and addr.count(':') <= 1:
        return addr.rsplit(':', 1)[1]
    return ""


def get_local_ips() -> list:
    """Get all local IP addresses with their subnets"""
    ips = []
    subnets = []
    try:
        # Try to get all interfaces with subnet info
        result = subprocess.run(['ip', '-4', 'addr', 'show'], capture_output=True, text=True)
        for line in result.stdout.split('\n'):
            if 'inet ' in line:
                parts = line.strip().split()
                if len(parts) >= 2:
                    ip_cidr = parts[1]  # e.g., "192.168.4.100/24"
                    ip = ip_cidr.split('/')[0]
                    if not ip.startswith('127.'):
                        if ip not in ips:
                            ips.append(ip)
                        # Calculate subnet for firewall rules
                        if '/' in ip_cidr:
                            prefix = int(ip_cidr.split('/')[1])
                            # Calculate network address
                            ip_parts = [int(x) for x in ip.split('.')]
                            mask = (0xFFFFFFFF << (32 - prefix)) & 0xFFFFFFFF
                            net_int = (ip_parts[0] << 24 | ip_parts[1] << 16 | ip_parts[2] << 8 | ip_parts[3]) & mask
                            net_addr = f"{(net_int >> 24) & 0xFF}.{(net_int >> 16) & 0xFF}.{(net_int >> 8) & 0xFF}.{net_int & 0xFF}/{prefix}"
                            if net_addr not in subnets:
                                subnets.append(net_addr)
    except:
        pass

    if not ips:
        ips.append('127.0.0.1')
    if not subnets:
        subnets.append('192.168.0.0/16')  # Fallback
    return ips, subnets


def check_port_available(port: int) -> bool:
    """Check if a port is available (with SO_REUSEADDR for TIME_WAIT sockets)"""
    try:
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        sock.bind(('', port))
        sock.close()
        return True
    except OSError:
        return False


def kill_existing_dashboard():
    """Find and kill any existing dashboard server processes"""
    import os
    my_pid = os.getpid()
    try:
        # Find Python processes running MBCoreServer.py
        result = subprocess.run(
            ['pgrep', '-f', 'python.*MBCoreServer\\.py'],
            capture_output=True, text=True
        )
        if result.returncode == 0:
            pids = [int(p) for p in result.stdout.strip().split('\n') if p]
            for pid in pids:
                if pid != my_pid:
                    try:
                        os.kill(pid, signal.SIGTERM)
                        time.sleep(0.5)  # Give it time to terminate
                    except ProcessLookupError:
                        pass  # Process already gone
    except Exception:
        pass  # pgrep might not be available


# ═══════════════════════════════════════════════════════════════════════════════
# BITCOIN RPC
# ═══════════════════════════════════════════════════════════════════════════════

def get_peer_info() -> list:
    try:
        cmd = config.get_cli_command() + ['getpeerinfo']
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
        if result.returncode == 0:
            return json.loads(result.stdout)
    except:
        pass
    return []


def get_enabled_networks() -> list:
    """Get list of enabled/reachable networks from getnetworkinfo"""
    enabled = []
    try:
        cmd = config.get_cli_command() + ['getnetworkinfo']
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
        if result.returncode == 0:
            info = json.loads(result.stdout)
            for net in info.get('networks', []):
                if net.get('reachable', False):
                    enabled.append(net.get('name', ''))
    except:
        pass
    # Return at least ipv4 as default
    return enabled if enabled else ['ipv4']


# ═══════════════════════════════════════════════════════════════════════════════
# GEO LOOKUP
# ═══════════════════════════════════════════════════════════════════════════════

def fetch_geo_api(ip: str) -> Optional[dict]:
    try:
        url = f"{GEO_API_URL}/{ip}?fields={GEO_API_FIELDS}"
        response = requests.get(url, timeout=10)
        data = response.json()
        if data.get('status') == 'success':
            return data
    except:
        pass
    return None


def geo_worker():
    """Background thread for geo lookups - checks DB first, then API, stores in both"""
    global geo_pending_count
    while not stop_flag.is_set():
        try:
            ip, network_type = geo_queue.get(timeout=0.5)
        except queue.Empty:
            continue

        data = None
        from_db = False

        # First check the geo database
        db_data = get_geo_from_db(ip)
        if db_data:
            data = db_data
            from_db = True
        else:
            # Not in database, call the API
            data = fetch_geo_api(ip)
            if data:
                # Save to database for future lookups
                save_geo_to_db(ip, data)

        # Store in SESSION CACHE (fast in-memory lookup)
        with geo_cache_lock:
            if data:
                geo_cache[ip] = {
                    'status': 'ok',
                    'continent': data.get('continent', ''),
                    'continentCode': data.get('continentCode', ''),
                    'country': data.get('country', ''),
                    'countryCode': data.get('countryCode', ''),
                    'region': data.get('region', ''),
                    'regionName': data.get('regionName', ''),
                    'city': data.get('city', ''),
                    'district': data.get('district', ''),
                    'zip': data.get('zip', ''),
                    'lat': data.get('lat', 0),
                    'lon': data.get('lon', 0),
                    'timezone': data.get('timezone', ''),
                    'offset': data.get('utc_offset') if from_db else data.get('offset', 0),
                    'currency': data.get('currency', ''),
                    'isp': data.get('isp', ''),
                    'org': data.get('org', ''),
                    'as': data.get('as_info') if from_db else data.get('as', ''),
                    'asname': data.get('asname', ''),
                    'mobile': data.get('mobile', False),
                    'proxy': data.get('proxy', False),
                    'hosting': data.get('hosting', False),
                }
            else:
                geo_cache[ip] = {
                    'status': 'unavailable',
                    'continent': '', 'continentCode': '',
                    'country': '', 'countryCode': '',
                    'region': '', 'regionName': '',
                    'city': '', 'district': '', 'zip': '',
                    'lat': 0, 'lon': 0,
                    'timezone': '', 'offset': 0, 'currency': '',
                    'isp': '', 'org': '', 'as': '', 'asname': '',
                    'mobile': False, 'proxy': False, 'hosting': False,
                }

        with pending_lock:
            pending_lookups.discard(ip)

        # Update pending count
        with geo_pending_lock:
            geo_pending_count = len(pending_lookups)

        broadcast_update('geo_update', {'ip': ip})

        # Only delay if we called the API (not when loading from DB)
        if not from_db:
            time.sleep(GEO_API_DELAY)


def get_cached_geo(ip: str) -> dict:
    """Get geo from SESSION CACHE (instant, no DB)"""
    with geo_cache_lock:
        return geo_cache.get(ip)


def set_cached_geo_private(ip: str):
    """Mark IP as private in session cache"""
    with geo_cache_lock:
        geo_cache[ip] = {
            'status': 'private',
            'continent': '', 'continentCode': '',
            'country': '', 'countryCode': '',
            'region': '', 'regionName': '',
            'city': '', 'district': '', 'zip': '',
            'lat': 0, 'lon': 0,
            'timezone': '', 'offset': 0, 'currency': '',
            'isp': '', 'org': '', 'as': '', 'asname': '',
            'mobile': False, 'proxy': False, 'hosting': False,
        }


def queue_geo_lookup(ip: str, network_type: str):
    with pending_lock:
        if ip in pending_lookups:
            return
        pending_lookups.add(ip)
    geo_queue.put((ip, network_type))


# ═══════════════════════════════════════════════════════════════════════════════
# DATA REFRESH
# ═══════════════════════════════════════════════════════════════════════════════

def refresh_worker():
    """Background thread for periodic data refresh - uses SESSION CACHE"""
    global current_peers, recent_changes, geo_pending_count
    previous_ids = set()
    addrman_refresh_counter = 0

    while not stop_flag.is_set():
        peers = get_peer_info()

        with peers_lock:
            current_peers = peers

        # Refresh addrman cache every 6 cycles (60 seconds)
        addrman_refresh_counter += 1
        if addrman_refresh_counter >= 6:
            refresh_addrman_cache()
            addrman_refresh_counter = 0

        # Track changes
        current_ids = set()
        now = time.time()

        for peer in peers:
            peer_id = str(peer.get('id', ''))
            current_ids.add(peer_id)
            addr = peer.get('addr', '')
            network_type = peer.get('network', get_network_type(addr))
            ip = extract_ip(addr)
            port = extract_port(addr)

            # Track peer ID -> IP mapping (so we have IP when they disconnect)
            with peer_ip_map_lock:
                peer_ip_map[peer_id] = {'ip': ip, 'port': port, 'network': network_type}

            # New peer connected (or first run)
            if peer_id not in previous_ids:
                if previous_ids:  # Only add to changes after first run
                    with changes_lock:
                        recent_changes.append((now, 'connected', {'ip': ip, 'port': port, 'network': network_type}))

            # Queue geo lookup if not already cached
            cached = get_cached_geo(ip)
            if cached is None:
                if is_public_address(network_type, ip):
                    queue_geo_lookup(ip, network_type)
                else:
                    # Private IP - mark as private in session cache
                    set_cached_geo_private(ip)

        # Handle disconnected peers - NOW WITH IP!
        # Use pop() to remove the entry after reading (prevents memory leak)
        for pid in previous_ids - current_ids:
            with peer_ip_map_lock:
                peer_info = peer_ip_map.pop(pid, {})
            ip = peer_info.get('ip', f'peer#{pid}')
            port = peer_info.get('port', '')
            network = peer_info.get('network', '?')
            with changes_lock:
                recent_changes.append((now, 'disconnected', {'ip': ip, 'port': port, 'network': network}))

        # Update pending count
        with geo_pending_lock:
            geo_pending_count = len(pending_lookups)

        # Prune old changes
        with changes_lock:
            recent_changes = [(t, c, p) for t, c, p in recent_changes if now - t < RECENT_WINDOW]

        previous_ids = current_ids

        # Broadcast update
        broadcast_update('peers_update', {})

        time.sleep(REFRESH_INTERVAL)


# ═══════════════════════════════════════════════════════════════════════════════
# WEBSOCKET
# ═══════════════════════════════════════════════════════════════════════════════

def broadcast_update(event_type: str, data: dict):
    """Signal SSE clients of update"""
    global last_update_type
    last_update_type = event_type
    sse_update_event.set()


# ═══════════════════════════════════════════════════════════════════════════════
# HELPERS
# ═══════════════════════════════════════════════════════════════════════════════

def format_bytes(b: int) -> str:
    """Format bytes to human readable string"""
    if b < 1024:
        return f"{b}B"
    elif b < 1024 * 1024:
        return f"{b / 1024:.1f}KB"
    elif b < 1024 * 1024 * 1024:
        return f"{b / (1024 * 1024):.1f}MB"
    else:
        return f"{b / (1024 * 1024 * 1024):.2f}GB"


# Connection type abbreviations
CONNECTION_TYPE_ABBREV = {
    'outbound-full-relay': 'OFR',
    'block-relay-only': 'BLO',
    'inbound': 'INB',
    'manual': 'MAN',
    'addr-fetch': 'FET',
    'feeler': 'FEL',
}

def abbrev_connection_type(conn_type: str) -> str:
    """Abbreviate connection type for compact display"""
    return CONNECTION_TYPE_ABBREV.get(conn_type, conn_type[:3].upper() if conn_type else '-')


# ═══════════════════════════════════════════════════════════════════════════════
# API ROUTES
# ═══════════════════════════════════════════════════════════════════════════════

@app.get("/api/peers")
async def api_peers():
    """Get all current peers with full data - uses SESSION CACHE (no DB queries!)"""
    with peers_lock:
        peers_snapshot = list(current_peers)

    result = []
    for peer in peers_snapshot:
        addr = peer.get('addr', '')
        network_type = peer.get('network', get_network_type(addr))
        ip = extract_ip(addr)
        port = extract_port(addr)

        # Get geo from SESSION CACHE (instant - no DB!)
        geo = get_cached_geo(ip)

        # Determine location status
        if network_type in ('onion', 'i2p', 'cjdns') or is_private_ip(ip):
            location_status = 'private'
            location = 'PRIVATE'
        elif geo and geo.get('status') == 'ok' and geo.get('city'):
            location_status = 'ok'
            location = f"{geo['city']}, {geo.get('countryCode', '')}"
        elif geo and geo.get('status') == 'unavailable':
            location_status = 'unavailable'
            location = 'UNAVAILABLE'
        else:
            location_status = 'pending'
            location = 'Stalking...'

        # Services abbreviation
        services = peer.get('servicesnames', [])
        services_abbrev = ' '.join([s[0] if s else '' for s in services[:5]])

        # Connection time formatted - two most significant non-zero units, no spaces
        conntime = peer.get('conntime', 0)
        if conntime:
            elapsed = int(time.time()) - conntime
            days = elapsed // 86400
            hours = (elapsed % 86400) // 3600
            minutes = (elapsed % 3600) // 60
            seconds = elapsed % 60

            if days > 0:
                # Days + next non-zero unit
                if hours > 0:
                    conn_fmt = f"{days}d{hours}h"
                elif minutes > 0:
                    conn_fmt = f"{days}d{minutes}m"
                elif seconds > 0:
                    conn_fmt = f"{days}d{seconds}s"
                else:
                    conn_fmt = f"{days}d"
            elif hours > 0:
                # Hours + next non-zero unit
                if minutes > 0:
                    conn_fmt = f"{hours}h{minutes}m"
                elif seconds > 0:
                    conn_fmt = f"{hours}h{seconds}s"
                else:
                    conn_fmt = f"{hours}h"
            elif minutes > 0:
                # Minutes + seconds
                if seconds > 0:
                    conn_fmt = f"{minutes}m{seconds}s"
                else:
                    conn_fmt = f"{minutes}m"
            else:
                # Just seconds
                conn_fmt = f"{seconds}s"
        else:
            conn_fmt = "-"

        # Build response with ALL 26 columns in specified order
        result.append({
            # 1-6: getpeerinfo (instant)
            'id': peer.get('id'),
            'network': network_type,
            'ip': ip,
            'port': port,
            'direction': 'IN' if peer.get('inbound') else 'OUT',
            'subver': peer.get('subver', '').replace('/', ''),

            # 7-13: ip-api geo (loads second)
            'city': geo.get('city', '') if geo else '',
            'region': geo.get('region', '') if geo else '',
            'regionName': geo.get('regionName', '') if geo else '',
            'country': geo.get('country', '') if geo else '',
            'countryCode': geo.get('countryCode', '') if geo else '',
            'continent': geo.get('continent', '') if geo else '',
            'continentCode': geo.get('continentCode', '') if geo else '',

            # 14-20: more getpeerinfo
            'bytessent': peer.get('bytessent', 0),
            'bytesrecv': peer.get('bytesrecv', 0),
            'bytessent_fmt': format_bytes(peer.get('bytessent', 0)),
            'bytesrecv_fmt': format_bytes(peer.get('bytesrecv', 0)),
            'ping_ms': int((peer.get('pingtime') or 0) * 1000),
            'conntime': conntime,
            'conntime_fmt': conn_fmt,
            'version': peer.get('version', 0),
            'connection_type': peer.get('connection_type', ''),
            'connection_type_abbrev': abbrev_connection_type(peer.get('connection_type', '')),
            'services': services,
            'services_abbrev': services_abbrev,

            # 21-23: more ip-api
            'lat': geo.get('lat', 0) if geo else 0,
            'lon': geo.get('lon', 0) if geo else 0,
            'isp': geo.get('isp', '') if geo else '',

            # New geo columns (from expanded API)
            'district': geo.get('district', '') if geo else '',
            'zip': geo.get('zip', '') if geo else '',
            'timezone': geo.get('timezone', '') if geo else '',
            'offset': geo.get('offset', 0) if geo else 0,
            'currency': geo.get('currency', '') if geo else '',
            'org': geo.get('org', '') if geo else '',
            'as': geo.get('as', '') if geo else '',
            'asname': geo.get('asname', '') if geo else '',
            'mobile': geo.get('mobile', False) if geo else False,
            'proxy': geo.get('proxy', False) if geo else False,
            'hosting': geo.get('hosting', False) if geo else False,

            # Addrman status
            'in_addrman': is_in_addrman(ip),

            # Extra fields for UI
            'location': location,
            'location_status': location_status,
            'addr': addr,
        })

    return result


@app.get("/api/changes")
async def api_changes():
    """Get recent peer changes"""
    with changes_lock:
        changes = list(recent_changes)
    return [{'time': t, 'type': c, 'peer': p} for t, c, p in changes]


@app.get("/api/stats")
async def api_stats():
    """Get dashboard statistics"""
    # Get fresh peer info from RPC
    peers = get_peer_info()
    peer_count = len(peers)

    # Count by network type with in/out breakdown
    network_counts = {
        'ipv4': {'in': 0, 'out': 0},
        'ipv6': {'in': 0, 'out': 0},
        'onion': {'in': 0, 'out': 0},
        'i2p': {'in': 0, 'out': 0},
        'cjdns': {'in': 0, 'out': 0}
    }
    for peer in peers:
        network = peer.get('network', 'ipv4')
        if network in network_counts:
            if peer.get('inbound'):
                network_counts[network]['in'] += 1
            else:
                network_counts[network]['out'] += 1

    # Get enabled networks from getnetworkinfo
    enabled_networks = get_enabled_networks()

    # Get pending geo count for map status
    with geo_pending_lock:
        pending = geo_pending_count

    # System stats (CPU via /proc/stat, memory via /proc/meminfo) - very fast
    system_stats = {'cpu_pct': None, 'mem_pct': None}
    try:
        # CPU usage via /proc/stat (instant read, compare with previous sample)
        cpu_pct = None
        try:
            with open('/proc/stat', 'r') as f:
                line = f.readline()  # First line is aggregate CPU
                parts = line.split()
                if len(parts) >= 8:
                    # user, nice, system, idle, iowait, irq, softirq, steal
                    idle = int(parts[4]) + int(parts[5])  # idle + iowait
                    total = sum(int(x) for x in parts[1:])  # sum all CPU fields including steal
                    if hasattr(api_stats, '_prev_cpu'):
                        prev_idle, prev_total = api_stats._prev_cpu
                        d_idle = idle - prev_idle
                        d_total = total - prev_total
                        if d_total > 0:
                            cpu_pct = round(100 * (1 - d_idle / d_total), 0)
                    api_stats._prev_cpu = (idle, total)
        except:
            pass

        # Memory usage via /proc/meminfo (instant)
        mem_pct = None
        try:
            with open('/proc/meminfo', 'r') as f:
                mem_total = 0
                mem_avail = 0
                for line in f:
                    if line.startswith('MemTotal:'):
                        mem_total = int(line.split()[1])
                    elif line.startswith('MemAvailable:'):
                        mem_avail = int(line.split()[1])
                if mem_total > 0:
                    mem_pct = round((1 - mem_avail / mem_total) * 100, 1)
        except:
            pass

        system_stats = {'cpu_pct': cpu_pct, 'mem_pct': mem_pct}
    except:
        pass

    # Geo DB entry count (cheap SQLite count)
    geo_entry_count = 0
    try:
        stats = get_geo_db_stats()
        geo_entry_count = stats.get('entries', 0)
    except:
        pass

    return {
        'connected': peer_count,
        'networks': network_counts,
        'enabled_networks': enabled_networks,
        'geo_pending': pending,
        'last_update': datetime.now().strftime('%H:%M:%S'),
        'refresh_interval': REFRESH_INTERVAL,
        'system_stats': system_stats,
        'geo_entry_count': geo_entry_count,
    }


# ═══════════════════════════════════════════════════════════════════════════════
# NETWORK SPEED ENDPOINT (fast polling, reads /proc/net/dev)
# ═══════════════════════════════════════════════════════════════════════════════

_prev_net_sample = None

@app.get("/api/netspeed")
async def api_netspeed():
    """Get current network throughput by reading /proc/net/dev (instant, zero cost)"""
    global _prev_net_sample
    try:
        now = time.time()
        rx_total = 0
        tx_total = 0
        with open('/proc/net/dev', 'r') as f:
            for line in f:
                line = line.strip()
                if ':' not in line or line.startswith('Inter') or line.startswith('face'):
                    continue
                iface, data = line.split(':', 1)
                iface = iface.strip()
                if iface == 'lo':
                    continue  # Skip loopback
                parts = data.split()
                if len(parts) >= 9:
                    rx_total += int(parts[0])  # bytes received
                    tx_total += int(parts[8])  # bytes transmitted

        result = {'rx_bps': 0, 'tx_bps': 0, 'ts': now}
        if _prev_net_sample:
            dt = now - _prev_net_sample['ts']
            if dt > 0:
                result['rx_bps'] = max(0, (rx_total - _prev_net_sample['rx']) / dt)
                result['tx_bps'] = max(0, (tx_total - _prev_net_sample['tx']) / dt)
        _prev_net_sample = {'rx': rx_total, 'tx': tx_total, 'ts': now}
        return result
    except Exception as e:
        return {'rx_bps': 0, 'tx_bps': 0, 'error': str(e)}


@app.get("/api/info")
async def api_info(currency: str = "USD"):
    """Get dashboard info panel data: BTC price, block info, blockchain stats, network scores, geo DB stats"""
    result = {
        'btc_price': None,
        'btc_currency': currency,
        'last_block': None,
        'blockchain': None,
        'network_scores': None,
        'geo_db_stats': None,
    }

    # 1. Bitcoin price from Coinbase API
    try:
        response = requests.get(f"https://api.coinbase.com/v2/prices/BTC-{currency}/spot", timeout=5)
        if response.status_code == 200:
            data = response.json()
            price = data.get('data', {}).get('amount')
            if price:
                result['btc_price'] = price
    except Exception as e:
        print(f"BTC price fetch error: {e}")

    # 2. Last block info
    try:
        # Get best block hash
        cmd = config.get_cli_command() + ['getbestblockhash']
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=10)
        if r.returncode == 0:
            blockhash = r.stdout.strip()
            # Get block header
            cmd = config.get_cli_command() + ['getblockheader', blockhash]
            r = subprocess.run(cmd, capture_output=True, text=True, timeout=10)
            if r.returncode == 0:
                header = json.loads(r.stdout)
                height = header.get('height', 0)
                block_time = header.get('time', 0)
                result['last_block'] = {
                    'height': height,
                    'time': block_time
                }
    except Exception as e:
        print(f"Last block fetch error: {e}")

    # 3. Blockchain stats (size, pruned, indexed, IBD status)
    try:
        cmd = config.get_cli_command() + ['getblockchaininfo']
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=10)
        if r.returncode == 0:
            info = json.loads(r.stdout)
            pruned = info.get('pruned', False)
            size_bytes = info.get('size_on_disk', 0)
            size_gb = round(size_bytes / 1e9, 1)
            ibd = info.get('initialblockdownload', False)

            # Check if txindex is enabled
            indexed = False
            try:
                cmd = config.get_cli_command() + ['getindexinfo']
                r2 = subprocess.run(cmd, capture_output=True, text=True, timeout=10)
                if r2.returncode == 0:
                    index_info = json.loads(r2.stdout)
                    indexed = 'txindex' in index_info
            except:
                pass

            result['blockchain'] = {
                'size_gb': size_gb,
                'pruned': pruned,
                'indexed': indexed,
                'ibd': ibd
            }
    except Exception as e:
        print(f"Blockchain stats fetch error: {e}")

    # 4. Network scores from getnetworkinfo localaddresses
    try:
        cmd = config.get_cli_command() + ['getnetworkinfo']
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=10)
        if r.returncode == 0:
            netinfo = json.loads(r.stdout)
            local_addrs = netinfo.get('localaddresses', [])
            scores = {'ipv4': None, 'ipv6': None}
            for addr_info in local_addrs:
                addr = addr_info.get('address', '')
                score = addr_info.get('score', 0)
                # Determine network type
                if addr.endswith('.onion') or addr.endswith('.i2p'):
                    continue  # Skip Tor/I2P
                elif addr.startswith('fc') or addr.startswith('fd'):
                    continue  # Skip CJDNS
                elif ':' in addr and addr.count(':') > 1:
                    # IPv6
                    if scores['ipv6'] is None or score > scores['ipv6']:
                        scores['ipv6'] = score
                else:
                    # IPv4
                    if scores['ipv4'] is None or score > scores['ipv4']:
                        scores['ipv4'] = score
            result['network_scores'] = scores
    except Exception as e:
        print(f"Network scores fetch error: {e}")

    # 5. Geo database stats (always returned so frontend can show status)
    try:
        stats = get_geo_db_stats()
        if stats.get('entries', 0) > 0:
            oldest_age_days = None
            if stats.get('oldest_updated'):
                oldest_age_days = int((time.time() - stats['oldest_updated']) / 86400)
            stats['oldest_age_days'] = oldest_age_days
        stats['auto_lookup'] = geo_db_enabled
        stats['auto_update'] = geo_db_auto_update
        result['geo_db_stats'] = stats
    except Exception:
        result['geo_db_stats'] = {'status': 'error', 'error': 'Failed to query database'}

    return result


@app.get("/api/events")
async def api_events(request: Request):
    """Server-Sent Events endpoint for real-time updates"""

    async def event_generator():
        global last_update_type
        # Send initial connected message
        yield {"event": "message", "data": json.dumps({"type": "connected"})}

        while not stop_flag.is_set():
            # Check if client disconnected
            if await request.is_disconnected():
                break

            # Wait for update event or timeout for keepalive (short timeout for fast shutdown)
            if sse_update_event.wait(timeout=2):
                sse_update_event.clear()
                yield {"event": "message", "data": json.dumps({"type": last_update_type})}
            else:
                # Send keepalive
                yield {"event": "message", "data": json.dumps({"type": "keepalive"})}

    return EventSourceResponse(event_generator())


@app.get("/api/mempool")
async def api_mempool(currency: str = "USD"):
    """Get mempool info for the mempool info overlay"""
    result = {
        'mempool': None,
        'btc_price': None,
        'error': None
    }

    try:
        cmd = config.get_cli_command() + ['getmempoolinfo']
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
        if r.returncode == 0:
            result['mempool'] = json.loads(r.stdout)
        else:
            result['error'] = r.stderr.strip() or 'Failed to get mempool info'
    except Exception as e:
        result['error'] = str(e)

    # Also fetch BTC price for total fees display
    try:
        response = requests.get(f"https://api.coinbase.com/v2/prices/BTC-{currency}/spot", timeout=5)
        if response.status_code == 200:
            data = response.json()
            price = data.get('data', {}).get('amount')
            if price:
                result['btc_price'] = float(price)
    except Exception:
        pass

    return result


@app.get("/api/blockchain")
async def api_blockchain():
    """Get blockchain info for the blockchain info overlay"""
    result = {
        'blockchain': None,
        'error': None
    }

    try:
        cmd = config.get_cli_command() + ['getblockchaininfo']
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
        if r.returncode == 0:
            result['blockchain'] = json.loads(r.stdout)
        else:
            result['error'] = r.stderr.strip() or 'Failed to get blockchain info'
    except Exception as e:
        result['error'] = str(e)

    return result


@app.post("/api/peer/disconnect")
async def api_peer_disconnect(request: Request):
    """Disconnect a peer by ID"""
    try:
        data = await request.json()
        peer_id = data.get('peer_id')

        if peer_id is None:
            return {'success': False, 'error': 'peer_id is required'}

        # Use disconnectnode with empty address and nodeid
        cmd = config.get_cli_command() + ['disconnectnode', '', str(peer_id)]
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=30)

        if r.returncode == 0:
            return {'success': True}
        else:
            return {'success': False, 'error': r.stderr.strip() or 'Sent, no response (status unknown)'}
    except Exception as e:
        return {'success': False, 'error': str(e)}


@app.post("/api/peer/ban")
async def api_peer_ban(request: Request):
    """Ban a peer by ID (24 hours). Only works for IPv4/IPv6."""
    try:
        data = await request.json()
        peer_id = data.get('peer_id')

        if peer_id is None:
            return {'success': False, 'error': 'peer_id is required'}

        # First, get peer info to find the address and network type
        cmd = config.get_cli_command() + ['getpeerinfo']
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=30)

        if r.returncode != 0:
            return {'success': False, 'error': 'Failed to get peer info'}

        peers = json.loads(r.stdout)
        peer = None
        for p in peers:
            if p.get('id') == int(peer_id):
                peer = p
                break

        if not peer:
            return {'success': False, 'error': f'Peer ID {peer_id} not found'}

        network = peer.get('network', 'ipv4')
        addr = peer.get('addr', '')

        # Only IPv4 and IPv6 can be banned
        if network not in ('ipv4', 'ipv6'):
            return {
                'success': False,
                'error': f'Cannot ban {network.upper()} peers. Ban works for IPv4/IPv6 IPs only. Tor/I2P/CJDNS don\'t have bannable IP identities in Core.'
            }

        # Extract IP from address (remove port and brackets)
        if addr.startswith('['):
            # IPv6: [2001:db8::1]:8333 -> 2001:db8::1
            ip = addr.split(']')[0][1:]
        elif ':' in addr and addr.count(':') <= 1:
            # IPv4: 192.168.1.1:8333 -> 192.168.1.1
            ip = addr.rsplit(':', 1)[0]
        else:
            ip = addr

        # Ban for 24 hours (86400 seconds)
        cmd = config.get_cli_command() + ['setban', ip, 'add', '86400']
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=30)

        if r.returncode == 0:
            return {'success': True, 'banned_ip': ip, 'network': network}
        else:
            return {'success': False, 'error': r.stderr.strip() or 'Sent, no response (status unknown)'}
    except Exception as e:
        return {'success': False, 'error': str(e)}


@app.post("/api/peer/unban")
async def api_peer_unban(request: Request):
    """Unban a specific IP/subnet"""
    try:
        data = await request.json()
        address = data.get('address')

        if not address:
            return {'success': False, 'error': 'address is required'}

        cmd = config.get_cli_command() + ['setban', address, 'remove']
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=30)

        if r.returncode == 0:
            return {'success': True}
        else:
            return {'success': False, 'error': r.stderr.strip() or 'Failed to unban address'}
    except Exception as e:
        return {'success': False, 'error': str(e)}


@app.get("/api/bans")
async def api_bans():
    """List all banned IPs"""
    try:
        cmd = config.get_cli_command() + ['listbanned']
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=30)

        if r.returncode == 0:
            bans = json.loads(r.stdout)
            return {'success': True, 'bans': bans}
        else:
            return {'success': False, 'error': r.stderr.strip() or 'Failed to list bans', 'bans': []}
    except Exception as e:
        return {'success': False, 'error': str(e), 'bans': []}


@app.post("/api/bans/clear")
async def api_bans_clear():
    """Clear all bans"""
    try:
        cmd = config.get_cli_command() + ['clearbanned']
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=30)

        if r.returncode == 0:
            return {'success': True}
        else:
            return {'success': False, 'error': r.stderr.strip() or 'Failed to clear bans'}
    except Exception as e:
        return {'success': False, 'error': str(e)}


@app.post("/api/peer/connect")
async def api_peer_connect(request: Request):
    """Connect to a peer using addnode onetry"""
    try:
        data = await request.json()
        address = data.get('address', '').strip()

        if not address:
            return {'success': False, 'error': 'address is required'}

        # Normalize the address based on type
        normalized = address

        # Detect address type and normalize
        if '.b32.i2p' in address.lower():
            # I2P - must have :0 port
            if ':' not in address or not address.endswith(':0'):
                return {'success': False, 'error': 'I2P addresses must end with :0 (e.g., abc...xyz.b32.i2p:0)'}
        elif '.onion' in address.lower():
            # Tor - add :8333 if no port
            if ':' not in address:
                normalized = address + ':8333'
        elif address.startswith('[') and address.startswith('[fc'):
            # CJDNS - pass as-is (Core handles it)
            pass
        elif address.startswith('['):
            # IPv6 - add :8333 if no port
            if ']:' not in address:
                normalized = address + ':8333'
        else:
            # IPv4 - add :8333 if no port
            if ':' not in address:
                normalized = address + ':8333'

        cmd = config.get_cli_command() + ['addnode', normalized, 'onetry']
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=30)

        if r.returncode == 0:
            return {'success': True, 'address': normalized}
        else:
            return {'success': False, 'error': r.stderr.strip() or 'Failed to connect to peer'}
    except Exception as e:
        return {'success': False, 'error': str(e)}


@app.post("/api/geodb/update")
async def api_geodb_update():
    """Download and merge the latest geo database from the server"""
    if not geo_db_enabled:
        return {'success': False, 'message': 'Geo database is disabled'}
    try:
        TMP_DIR.mkdir(parents=True, exist_ok=True)
        tmp_path = TMP_DIR / 'geo_download.db'
        # Download remote database
        resp = requests.get(GEO_DB_REPO_URL, timeout=60, stream=True)
        if resp.status_code != 200:
            return {'success': False, 'message': f'Download failed (HTTP {resp.status_code})'}
        with open(tmp_path, 'wb') as f:
            for chunk in resp.iter_content(chunk_size=8192):
                f.write(chunk)
        # Validate it's a real SQLite database with the expected table
        try:
            tmp_conn = sqlite3.connect(tmp_path)
            remote_rows = tmp_conn.execute('SELECT * FROM geo_cache').fetchall()
            col_names = [desc[0] for desc in tmp_conn.execute('SELECT * FROM geo_cache LIMIT 0').description]
            tmp_conn.close()
        except Exception:
            tmp_path.unlink(missing_ok=True)
            return {'success': False, 'message': 'Downloaded file is not a valid geo database'}
        remote_count = len(remote_rows)
        if remote_count == 0:
            tmp_path.unlink(missing_ok=True)
            return {'success': False, 'message': 'Remote database is empty'}
        if not GEO_DB_FILE.exists():
            # No local DB — just use the downloaded one
            tmp_path.rename(GEO_DB_FILE)
            return {'success': True, 'message': f'Downloaded database ({remote_count} entries)'}
        # Merge: read remote rows into memory, insert into local DB
        tmp_path.unlink(missing_ok=True)
        placeholders = ','.join(['?'] * len(col_names))
        conn = sqlite3.connect(GEO_DB_FILE, timeout=5)
        before = conn.execute('SELECT COUNT(*) FROM geo_cache').fetchone()[0]
        conn.executemany(f"INSERT OR IGNORE INTO geo_cache ({','.join(col_names)}) VALUES ({placeholders})", remote_rows)
        conn.commit()
        total = conn.execute('SELECT COUNT(*) FROM geo_cache').fetchone()[0]
        conn.close()
        new_count = total - before
        if new_count > 0:
            return {'success': True, 'message': f'+{new_count} new entries ({total} total)'}
        else:
            return {'success': True, 'message': f'Already up to date ({total} entries)'}
    except Exception as e:
        return {'success': False, 'message': str(e)}


@app.get("/api/cli-info")
async def api_cli_info():
    """Get the CLI command info for display to user"""
    cmd_parts = config.get_cli_command()
    return {
        'cli_path': config.cli_path,
        'datadir': config.datadir,
        'conf': config.conf,
        'network': config.network,
        'base_command': ' '.join(cmd_parts)
    }


@app.get("/", response_class=HTMLResponse)
async def root(request: Request):
    """Serve the main dashboard page"""
    return templates.TemplateResponse("index.html", {"request": request, "version": VERSION})


# Mount static files
if STATIC_DIR.exists():
    app.mount("/static", StaticFiles(directory=str(STATIC_DIR)), name="static")


# ═══════════════════════════════════════════════════════════════════════════════
# MAIN
# ═══════════════════════════════════════════════════════════════════════════════

import asyncio
import signal

# ANSI color codes
C_RESET = "\033[0m"
C_BOLD = "\033[1m"
C_DIM = "\033[2m"
C_RED = "\033[31m"
C_GREEN = "\033[32m"
C_YELLOW = "\033[33m"
C_BLUE = "\033[34m"
C_PINK = "\033[35m"
C_CYAN = "\033[36m"
C_WHITE = "\033[37m"

def get_manual_port() -> int:
    """Prompt user for a manual port number"""
    print(f"\n{C_BOLD}Enter a port number:{C_RESET}")
    print(f"{C_DIM}  Suggested alternatives: 58334, 58335, 8080, 8888{C_RESET}")
    print()

    while True:
        try:
            port_input = input(f"{C_YELLOW}Port (or 'q' to quit): {C_RESET}").strip().lower()
        except (KeyboardInterrupt, EOFError):
            print()
            sys.exit(0)

        if port_input == 'q':
            sys.exit(0)

        try:
            custom_port = int(port_input)
            if 1024 <= custom_port <= 65535:
                if check_port_available(custom_port):
                    return custom_port
                else:
                    print(f"{C_RED}Port {custom_port} is also in use. Try another.{C_RESET}")
            else:
                print(f"{C_RED}Port must be between 1024 and 65535{C_RESET}")
        except ValueError:
            print(f"{C_RED}Invalid port number{C_RESET}")


def main():
    global geo_db_enabled, geo_db_auto_update

    if not config.load():
        print("Error: Configuration not found. Run ./da.sh first to configure.")
        sys.exit(1)

    # Load geo database settings from config
    geo_db_enabled = config.get('GEO_DB_ENABLED', 'false').lower() == 'true'
    geo_db_auto_update = config.get('GEO_DB_AUTO_UPDATE', 'true').lower() == 'true'

    # Initialize geo database if enabled
    if geo_db_enabled:
        init_geo_database()

    # Kill any existing dashboard processes that might be holding the port
    kill_existing_dashboard()

    # Use configured port from config file
    port = get_configured_port()
    if not check_port_available(port):
        print(f"\n{C_YELLOW}⚠ Port {port} is in use, waiting for it to be released...{C_RESET}")
        # Retry 3 times with 1.5 second delays
        for attempt in range(3):
            time.sleep(1.5)
            if check_port_available(port):
                print(f"{C_GREEN}✓ Port {port} is now available{C_RESET}\n")
                break
        else:
            # Still not available - ask user what to do
            print(f"\n{C_RED}✗ Port {port} is still in use{C_RESET}")
            print(f"{C_YELLOW}  Another application may be using this port.{C_RESET}")
            print(f"{C_DIM}  Tip: Check with 'lsof -i :{port}' or 'ss -tlnp | grep {port}'{C_RESET}")
            print()
            print(f"{C_BOLD}Choose an option:{C_RESET}")
            print(f"  {C_GREEN}1{C_RESET}) Enter a different port manually")
            print(f"  {C_GREEN}q{C_RESET}) Quit")
            print()

            while True:
                try:
                    choice = input(f"{C_YELLOW}Enter choice (1/q): {C_RESET}").strip().lower()
                except (KeyboardInterrupt, EOFError):
                    print()
                    sys.exit(0)

                if choice == 'q':
                    sys.exit(0)
                elif choice == '1':
                    port = get_manual_port()
                    # Save the new port to config so it persists
                    save_port_to_config(port)
                    print(f"{C_GREEN}✓ Using port {port} (saved to config){C_RESET}\n")
                    break
                else:
                    print(f"{C_RED}Invalid choice. Enter 1 or q{C_RESET}")

    # Get local IPs and subnets
    local_ips, subnets = get_local_ips()

    # Start background threads
    geo_thread = threading.Thread(target=geo_worker, daemon=True)
    geo_thread.start()

    refresh_thread = threading.Thread(target=refresh_worker, daemon=True)
    refresh_thread.start()

    # Initial addrman cache refresh
    refresh_addrman_cache()

    # Get primary LAN IP (first non-localhost)
    lan_ip = local_ips[0] if local_ips else "127.0.0.1"
    subnet = subnets[0] if subnets else "192.168.0.0/16"

    # Detect firewall
    firewall_name, firewall_active = detect_active_firewall()

    # Print access info with colors and formatting
    line_w = 84
    logo_w = 52  # Width of MBCORE ASCII art
    print("")
    print(f"{C_BLUE}{'═' * line_w}{C_RESET}")
    print(f"  {C_BOLD}{C_BLUE}███╗   ███╗██████╗  ██████╗ ██████╗ ██████╗ ███████╗{C_RESET}")
    print(f"  {C_BOLD}{C_BLUE}████╗ ████║██╔══██╗██╔════╝██╔═══██╗██╔══██╗██╔════╝{C_RESET}")
    print(f"  {C_BOLD}{C_BLUE}██╔████╔██║██████╔╝██║     ██║   ██║██████╔╝█████╗  {C_RESET}")
    print(f"  {C_BOLD}{C_BLUE}██║╚██╔╝██║██╔══██╗██║     ██║   ██║██╔══██╗██╔══╝  {C_RESET}")
    print(f"  {C_BOLD}{C_BLUE}██║ ╚═╝ ██║██████╔╝╚██████╗╚██████╔╝██║  ██║███████╗{C_RESET}")
    print(f"  {C_BOLD}{C_BLUE}╚═╝     ╚═╝╚═════╝  ╚═════╝ ╚═════╝ ╚═╝  ╚═╝╚══════╝{C_RESET}")
    print(f"  Dashboard v{VERSION} {C_WHITE}(Bitcoin Core peer info / map / tools){C_RESET}")
    print(f"  {C_BLUE}{'─' * logo_w}{C_RESET}")
    print(f"  Created by mbhillrn")
    print(f"  MIT License – Free to use, modify, and distribute")
    print(f"  {C_BOLD}{C_YELLOW}Support (btc):{C_RESET} {C_GREEN}bc1qy63057zemrskq0n02avq9egce4cpuuenm5ztf5{C_RESET}")
    print(f"{C_BLUE}{'═' * line_w}{C_RESET}")
    print(f"  {C_BOLD}{C_YELLOW}** INSTRUCTIONS TO VIEW DASHBOARD! **{C_RESET}")
    print(f"{C_BLUE}{'═' * line_w}{C_RESET}")
    print("")
    print(f"  The dashboard is viewed in your WEB BROWSER (Chrome, Firefox, etc).")
    print(f"  This is easy — just open ONE of the links below.")
    print("")
    url_lan = f"http://{lan_ip}:{port}"
    url_local = f"http://127.0.0.1:{port}"
    print(f"  {C_BOLD}{C_YELLOW}Opening your browser on the SAME computer this program is running on:{C_RESET}")
    print(f"      {C_CYAN}{url_local}{C_RESET}")
    print("")
    print(f"  {C_BOLD}{C_YELLOW}Opening your browser on ANOTHER computer on your local network:{C_RESET}")
    print(f"    {C_BOLD}{C_YELLOW}Option A{C_RESET} – Direct network access {C_BOLD}{C_YELLOW}(recommended){C_RESET}")
    print(f"      {C_CYAN}{url_lan}{C_RESET}  {C_DIM}<- auto-detected node IP{C_RESET}")
    # Show firewall warning if detected
    if firewall_active and firewall_name:
        print(f"      {C_RED}Firewall detected ({firewall_name}): may need configuring for port {port}{C_RESET}")
    print(f"      {C_DIM}(If you use a firewall, it may need to be configured.{C_RESET}")
    print(f"      {C_DIM} Please see the README or run the Firewall Helper Tool{C_RESET}")
    print(f"      {C_DIM} from the main menu (Option 3).){C_RESET}")
    print("")
    print(f"    {C_BOLD}{C_YELLOW}Option B{C_RESET} – SSH tunnel (advanced, see README)")
    print(f"      {C_CYAN}{url_local}{C_RESET}")
    print("")
    print(f"{C_BLUE}{'─' * line_w}{C_RESET}")
    print(f"  {C_RED}🔴 The README has been created to guide you through this process.{C_RESET}")
    print(f"  {C_RED}🔴 Please review it if this is your first time running MBCore or need to troubleshoot.{C_RESET}")
    print(f"{C_BLUE}{'─' * line_w}{C_RESET}")
    print(f"  Press {C_PINK}Ctrl+C{C_RESET} to stop the dashboard (press twice to force)")
    print(f"{C_BLUE}{'═' * line_w}{C_RESET}")
    print("")

    # Signal handler for fast shutdown
    shutdown_count = [0]
    def signal_handler(signum, frame):
        shutdown_count[0] += 1
        stop_flag.set()
        sse_update_event.set()  # Wake up SSE generators
        if shutdown_count[0] == 1:
            print(f"\n{C_YELLOW}Shutting down... (press Ctrl+C again to force){C_RESET}")
        elif shutdown_count[0] >= 2:
            print(f"\n{C_RED}Force exit!{C_RESET}")
            os._exit(0)

    signal.signal(signal.SIGINT, signal_handler)
    signal.signal(signal.SIGTERM, signal_handler)

    # Run server
    try:
        uvicorn.run(app, host="0.0.0.0", port=port, log_level="warning")
    except KeyboardInterrupt:
        pass
    except SystemExit:
        pass
    finally:
        stop_flag.set()
        print(f"\n{C_GREEN}Shutdown complete.{C_RESET}")


if __name__ == "__main__":
    main()
