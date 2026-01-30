#!/usr/bin/env python3
"""
MBTC-DASH - Peer List Display
Shows connected peers with geo-location data
Table displays IMMEDIATELY - geo lookups happen in background
"""

import json
import os
import queue
import signal
import sqlite3
import subprocess
import sys
import threading
import time
from datetime import datetime
from pathlib import Path
from typing import Optional

import requests
from rich.console import Console, Group
from rich.live import Live
from rich.panel import Panel
from rich.table import Table
from rich.text import Text
from rich.style import Style

# ═══════════════════════════════════════════════════════════════════════════════
# CONFIGURATION
# ═══════════════════════════════════════════════════════════════════════════════

REFRESH_INTERVAL = 10  # Seconds between peer list refreshes
GEO_API_DELAY = 1.5    # Seconds between API calls (stay under 45/min limit)
GEO_API_URL = "http://ip-api.com/json"
GEO_API_FIELDS = "status,country,countryCode,region,regionName,city,district,lat,lon,isp,as,hosting,query"

# Paths - use local data folder within the project
SCRIPT_DIR = Path(__file__).parent
PROJECT_DIR = SCRIPT_DIR.parent
DATA_DIR = PROJECT_DIR / 'data'
CONFIG_FILE = DATA_DIR / 'config.conf'
DB_FILE = DATA_DIR / 'peers.db'

# Geo status codes
GEO_OK = 0
GEO_PRIVATE = 1
GEO_UNAVAILABLE = 2

# Retry intervals for GEO_UNAVAILABLE (in seconds): 1d, 3d, 7d, 7d...
RETRY_INTERVALS = [86400, 259200, 604800, 604800]

# ═══════════════════════════════════════════════════════════════════════════════
# STYLES
# ═══════════════════════════════════════════════════════════════════════════════

STYLE_HEADER = Style(color="dodger_blue1", bold=True)
STYLE_BORDER = Style(color="steel_blue")
STYLE_DIM = Style(color="grey70")
STYLE_SUCCESS = Style(color="green")
STYLE_WARN = Style(color="yellow")
STYLE_ERROR = Style(color="red")
STYLE_NEW = Style(color="green", bold=True)
STYLE_DISCONNECTED = Style(color="red", bold=True)
STYLE_LOCATING = Style(color="yellow", italic=True)

console = Console()

# ═══════════════════════════════════════════════════════════════════════════════
# GLOBAL STATE
# ═══════════════════════════════════════════════════════════════════════════════

# Thread-safe queue for geo lookups
geo_queue = queue.Queue()

# Recent changes (thread-safe access via lock)
recent_changes = []
recent_changes_lock = threading.Lock()
RECENT_WINDOW = 20  # seconds

# Currently pending geo lookups (to avoid duplicates)
pending_lookups = set()
pending_lookups_lock = threading.Lock()

# Flag to stop background thread
stop_flag = threading.Event()

# Addrman cache (refreshed periodically)
addrman_ips = set()
addrman_last_refresh = 0
addrman_lock = threading.Lock()
ADDRMAN_REFRESH_INTERVAL = 60  # seconds


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

    conn = sqlite3.connect(DB_FILE, check_same_thread=False)
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


def get_db_connection():
    """Get a database connection (thread-safe)"""
    return sqlite3.connect(DB_FILE, check_same_thread=False)


def get_peer_geo(ip: str) -> Optional[dict]:
    """Get cached geo data for a peer"""
    conn = get_db_connection()
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
    conn = get_db_connection()

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
    conn = get_db_connection()
    conn.execute('UPDATE peers_geo SET last_seen = ? WHERE ip = ?', (now, ip))
    conn.commit()
    conn.close()


def get_peer_stats() -> dict:
    """Get database statistics"""
    conn = get_db_connection()
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


def is_private_ip(ip: str) -> bool:
    """Check if IP is RFC1918 private or other non-routable"""
    # Simple check for common private ranges
    if ip.startswith('10.') or ip.startswith('192.168.'):
        return True
    if ip.startswith('172.'):
        try:
            second_octet = int(ip.split('.')[1])
            if 16 <= second_octet <= 31:
                return True
        except:
            pass
    if ip.startswith('127.') or ip == 'localhost':
        return True
    # IPv6 link-local, loopback
    if ip.startswith('fe80:') or ip == '::1':
        return True
    return False


def is_public_address(network_type: str, ip: str) -> bool:
    """Check if address can be geolocated"""
    if network_type not in ('ipv4', 'ipv6'):
        return False
    if is_private_ip(ip):
        return False
    return True


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


def extract_port(addr: str) -> str:
    """Extract port from address"""
    if addr.startswith('['):
        # IPv6: [addr]:port
        if ']:' in addr:
            return addr.split(']:')[1]
    elif ':' in addr:
        return addr.rsplit(':', 1)[1]
    return ""


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


def refresh_addrman():
    """Refresh the addrman IP cache (called periodically)"""
    global addrman_ips, addrman_last_refresh

    now = time.time()
    with addrman_lock:
        if now - addrman_last_refresh < ADDRMAN_REFRESH_INTERVAL:
            return  # Still fresh

    try:
        cmd = config.get_cli_command() + ['getnodeaddresses', '0']
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=60)
        if result.returncode == 0:
            data = json.loads(result.stdout)
            new_ips = set()
            for entry in data:
                addr = entry.get('address', '')
                if addr:
                    new_ips.add(addr)

            with addrman_lock:
                addrman_ips = new_ips
                addrman_last_refresh = now
    except Exception:
        pass


def is_in_addrman(ip: str) -> bool:
    """Check if IP is in the addrman cache"""
    with addrman_lock:
        return ip in addrman_ips


# ═══════════════════════════════════════════════════════════════════════════════
# BACKGROUND GEO LOOKUP WORKER
# ═══════════════════════════════════════════════════════════════════════════════

def geo_lookup_worker():
    """Background thread that processes geo lookups from queue"""
    while not stop_flag.is_set():
        try:
            # Get item from queue with timeout (so we can check stop_flag)
            try:
                ip, network_type = geo_queue.get(timeout=0.5)
            except queue.Empty:
                continue

            # Do the lookup
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

            # Remove from pending
            with pending_lookups_lock:
                pending_lookups.discard(ip)

            geo_queue.task_done()

            # Rate limit
            time.sleep(GEO_API_DELAY)

        except Exception:
            pass


def queue_geo_lookup(ip: str, network_type: str):
    """Add IP to geo lookup queue if not already pending"""
    with pending_lookups_lock:
        if ip in pending_lookups:
            return
        pending_lookups.add(ip)

    geo_queue.put((ip, network_type))


def is_geo_pending(ip: str) -> bool:
    """Check if geo lookup is pending for this IP"""
    with pending_lookups_lock:
        return ip in pending_lookups


# ═══════════════════════════════════════════════════════════════════════════════
# DISPLAY HELPERS
# ═══════════════════════════════════════════════════════════════════════════════

def truncate(text: str, max_len: int) -> str:
    """Truncate string to max length"""
    if len(text) > max_len:
        return text[:max_len-3] + "..."
    return text


def format_location(ip: str, network_type: str) -> tuple:
    """Format location string, returns (text, style)"""
    if network_type in ('onion', 'i2p', 'cjdns'):
        return ("PRIVATE LOCATION", STYLE_WARN)

    if is_private_ip(ip):
        return ("PRIVATE LOCATION", STYLE_WARN)

    # Check if pending
    if is_geo_pending(ip):
        return ("Stalking location...", STYLE_LOCATING)

    geo = get_peer_geo(ip)
    if not geo:
        return ("Stalking location...", STYLE_LOCATING)

    if geo['geo_status'] == GEO_PRIVATE:
        return ("PRIVATE LOCATION", STYLE_WARN)
    elif geo['geo_status'] == GEO_UNAVAILABLE or not geo.get('city'):
        return ("LOCATION UNAVAILABLE", STYLE_DIM)
    else:
        return (f"{geo['city']}, {geo['country_code']}", None)


def add_recent_change(change_type: str, peer_info: dict):
    """Add a change to recent changes list"""
    with recent_changes_lock:
        recent_changes.append((time.time(), change_type, peer_info))


def get_recent_changes():
    """Get recent changes within the window"""
    now = time.time()
    with recent_changes_lock:
        # Prune old changes
        recent_changes[:] = [(t, c, p) for t, c, p in recent_changes if now - t < RECENT_WINDOW]
        return list(recent_changes)


# ═══════════════════════════════════════════════════════════════════════════════
# TABLE CREATION
# ═══════════════════════════════════════════════════════════════════════════════

def create_peer_table(peers: list, term_height: int) -> Table:
    """Create the peer table with Rich"""
    table = Table(
        show_header=True,
        header_style=STYLE_HEADER,
        border_style=STYLE_BORDER,
        expand=True,
        box=None,
    )

    table.add_column("ID", style="white", width=7)
    table.add_column("Address", style="white", width=18)
    table.add_column("Port", style="white", width=5)
    table.add_column("Dir", style="white", width=3)
    table.add_column("Net", style="white", width=5)
    table.add_column("AM", style="white", width=2)  # Addrman
    table.add_column("Location", style="white", width=20)
    table.add_column("ISP", style="white", width=14)
    table.add_column("Ping", style="white", width=6)
    table.add_column("Recv", style="white", width=8)
    table.add_column("Sent", style="white", width=8)
    table.add_column("Version", style="white", width=16)

    # Calculate how many rows we can show
    # Reserve space for header (6 lines) + footer (4 lines) + table header (2 lines)
    available_rows = max(5, term_height - 14)

    for i, peer in enumerate(peers[:available_rows]):
        peer_id = str(peer.get('id', ''))
        addr = peer.get('addr', '')
        network_type = peer.get('network', get_network_type(addr))
        ip = extract_ip(addr)
        port = extract_port(addr)

        # Location with style
        location_text, location_style = format_location(ip, network_type)
        location = Text(truncate(location_text, 20))
        if location_style:
            location.stylize(location_style)

        # ISP from database
        geo = get_peer_geo(ip)
        isp = truncate(geo.get('isp', '-') if geo else '-', 14)

        # Direction
        direction = "IN" if peer.get('inbound') else "OUT"

        # Addrman check
        in_addrman = Text("Y" if is_in_addrman(ip) else "-")
        if is_in_addrman(ip):
            in_addrman.stylize(STYLE_SUCCESS)

        # Ping
        ping = peer.get('pingtime') or peer.get('pingwait') or 0
        ping_str = f"{int(ping * 1000)}ms" if ping else "-"

        # Bytes
        sent = format_bytes(peer.get('bytessent', 0))
        recv = format_bytes(peer.get('bytesrecv', 0))

        # Version
        version = truncate(peer.get('subver', '').replace('/', ''), 16)

        table.add_row(
            peer_id,
            truncate(ip, 18),
            port,
            direction,
            network_type[:5],
            in_addrman,
            location,
            isp,
            ping_str,
            recv,
            sent,
            version,
        )

    if len(peers) > available_rows:
        table.add_row(
            "", "", "", "", "", "",
            Text(f"... and {len(peers) - available_rows} more peers", style=STYLE_DIM),
            "", "", "", "", ""
        )

    return table


def create_changes_panel() -> Panel:
    """Create panel showing recent connections/disconnections"""
    changes = get_recent_changes()

    if not changes:
        content = Text("No changes in last 20s", style=STYLE_DIM)
    else:
        lines = []
        for timestamp, change_type, peer_info in changes[-8:]:  # Show last 8
            ip = peer_info.get('ip', 'unknown')
            port = peer_info.get('port', '')
            network = peer_info.get('network', 'unknown')
            time_str = datetime.fromtimestamp(timestamp).strftime('%H:%M:%S')

            addr_str = f"{ip}:{port}" if port else ip

            if change_type == 'connected':
                lines.append(Text(f"+ {addr_str} ({network}) [{time_str}]", style=STYLE_NEW))
            else:
                lines.append(Text(f"- {addr_str} ({network}) [{time_str}]", style=STYLE_DISCONNECTED))

        content = Text("\n").join(lines)

    return Panel(
        content,
        title=f"Recent Changes (last {RECENT_WINDOW}s)",
        border_style=STYLE_BORDER,
        padding=(0, 1),
        height=min(len(changes) + 3, 10) if changes else 4
    )


def create_display(peers: list, stats: dict, next_refresh: int, pending_count: int, term_height: int) -> Group:
    """Create the full display layout"""
    parts = []

    # Header
    header_text = Text()
    header_text.append("═" * 110 + "\n", style=STYLE_HEADER)
    header_text.append("  MBTC-DASH Peer List", style=STYLE_HEADER)
    header_text.append(" " * 40, style=STYLE_DIM)
    header_text.append("Press 'q' to quit | ", style=STYLE_DIM)
    if pending_count > 0:
        header_text.append(f"Locating: {pending_count} ", style=STYLE_LOCATING)
    header_text.append(f"| Refresh: {next_refresh}s\n", style=STYLE_DIM)
    header_text.append("═" * 110, style=STYLE_HEADER)
    parts.append(header_text)

    # Peer count
    parts.append(Text(f"\nConnected peers: {len(peers)}\n", style="bold cyan"))

    # Peer table
    if peers:
        parts.append(create_peer_table(peers, term_height))
    else:
        parts.append(Text("No peers connected", style=STYLE_DIM))

    # Stats line
    stats_text = Text(f"\nDB: {stats['geo_ok']} geo | {stats['private']} priv | {stats['unavailable']} unavail | Net: {stats['ipv4']} v4, {stats['ipv6']} v6, {stats['onion']} tor, {stats['i2p']} i2p\n", style=STYLE_DIM)
    parts.append(stats_text)

    # Recent changes panel
    parts.append(create_changes_panel())

    # Footer
    now = datetime.now().strftime('%H:%M:%S')
    footer_text = Text(f"Updated: {now}", style=STYLE_DIM)
    parts.append(footer_text)

    return Group(*parts)


# ═══════════════════════════════════════════════════════════════════════════════
# PEER PROCESSING
# ═══════════════════════════════════════════════════════════════════════════════

def process_peers(peers: list, previous_ids: set) -> set:
    """Process peers: queue geo lookups, track changes. Returns new peer IDs set."""
    current_ids = set()
    now = time.time()

    for peer in peers:
        peer_id = str(peer.get('id', ''))
        current_ids.add(peer_id)

        addr = peer.get('addr', '')
        network_type = peer.get('network', get_network_type(addr))
        ip = extract_ip(addr)
        port = extract_port(addr)

        # Track new connections
        if peer_id not in previous_ids and previous_ids:  # Don't log on first load
            add_recent_change('connected', {'ip': ip, 'port': port, 'network': network_type})

        # Handle geo lookup
        if is_public_address(network_type, ip):
            geo = get_peer_geo(ip)
            if not geo or should_retry_geo(ip):
                queue_geo_lookup(ip, network_type)
            elif geo:
                update_peer_seen(ip)
        else:
            # Private network
            geo = get_peer_geo(ip)
            if not geo:
                upsert_peer_geo(ip, network_type, GEO_PRIVATE)

    # Track disconnections
    for peer_id in previous_ids - current_ids:
        # We don't have peer info anymore, just note it
        add_recent_change('disconnected', {'ip': f'peer#{peer_id}', 'port': '', 'network': '?'})

    return current_ids


# ═══════════════════════════════════════════════════════════════════════════════
# MAIN
# ═══════════════════════════════════════════════════════════════════════════════

def main():
    # Initialize
    init_database()

    # Load config
    if not config.load():
        console.print("[red]Error:[/] Configuration not found. Run ./da.sh first to configure.")
        sys.exit(1)

    # Signal handler for graceful exit
    def signal_handler(sig, frame):
        stop_flag.set()

    signal.signal(signal.SIGINT, signal_handler)
    signal.signal(signal.SIGTERM, signal_handler)

    # Start background geo lookup worker
    geo_thread = threading.Thread(target=geo_lookup_worker, daemon=True)
    geo_thread.start()

    # Keyboard input (non-blocking)
    import select
    import termios
    import tty

    old_settings = termios.tcgetattr(sys.stdin)

    try:
        tty.setcbreak(sys.stdin.fileno())

        # Initial fetch
        console.print("[bold cyan]Fetching peers and addrman...[/]")
        peers = get_peer_info()
        refresh_addrman()  # Initial addrman fetch

        if not peers:
            console.print("[yellow]No peers found. Is bitcoind running?[/]")

        # Process initial peers (queue geo lookups immediately)
        current_peer_ids = process_peers(peers, set())

        last_refresh = time.time()

        # Enter Live context immediately - table shows right away
        with Live(console=console, refresh_per_second=4, screen=True) as live:
            while not stop_flag.is_set():
                now = time.time()

                # Check for quit key
                if select.select([sys.stdin], [], [], 0)[0]:
                    key = sys.stdin.read(1)
                    if key.lower() == 'q':
                        break

                # Refresh peer list periodically
                if now - last_refresh >= REFRESH_INTERVAL:
                    new_peers = get_peer_info()
                    if new_peers:
                        current_peer_ids = process_peers(new_peers, current_peer_ids)
                        peers = new_peers
                    refresh_addrman()  # Also refresh addrman cache
                    last_refresh = now

                # Calculate countdown
                next_refresh = max(0, int(REFRESH_INTERVAL - (now - last_refresh)))

                # Get stats and pending count
                stats = get_peer_stats()
                with pending_lookups_lock:
                    pending_count = len(pending_lookups)

                # Get terminal size
                term_height = console.size.height

                # Update display
                display = create_display(peers, stats, next_refresh, pending_count, term_height)
                live.update(display)

                time.sleep(0.1)

    except Exception as e:
        console.print(f"[red]Error:[/] {e}")
    finally:
        # Cleanup
        stop_flag.set()
        termios.tcsetattr(sys.stdin, termios.TCSADRAIN, old_settings)
        console.print("\n[green]Peer list closed[/]")


if __name__ == "__main__":
    main()
