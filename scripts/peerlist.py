#!/usr/bin/env python3
"""
MBTC-DASH - Peer List Display
Shows connected peers with geo-location data using Rich for smooth live updates
"""

import json
import os
import signal
import sqlite3
import subprocess
import sys
import time
from datetime import datetime
from pathlib import Path
from typing import Optional

import requests
from rich.console import Console, Group
from rich.live import Live
from rich.panel import Panel
from rich.progress import Progress, SpinnerColumn, BarColumn, TextColumn, TaskProgressColumn
from rich.table import Table
from rich.text import Text
from rich.layout import Layout
from rich.style import Style

# ═══════════════════════════════════════════════════════════════════════════════
# CONFIGURATION
# ═══════════════════════════════════════════════════════════════════════════════

REFRESH_INTERVAL = 10  # Seconds between refreshes
GEO_API_DELAY = 1.5    # Seconds between API calls (stay under 45/min limit)
GEO_API_URL = "http://ip-api.com/json"
GEO_API_FIELDS = "status,country,countryCode,region,regionName,city,district,lat,lon,isp,as,hosting,query"

# Paths
CONFIG_DIR = Path(os.environ.get('XDG_CONFIG_HOME', Path.home() / '.config')) / 'mbtc-dash'
DATA_DIR = Path(os.environ.get('XDG_DATA_HOME', Path.home() / '.local' / 'share')) / 'mbtc-dash'
CONFIG_FILE = CONFIG_DIR / 'config.conf'
CONFIG_FILE_OLD = CONFIG_DIR / 'detection_cache.conf'  # Backwards compat
DB_FILE = DATA_DIR / 'peers.db'

# Geo status codes
GEO_OK = 0
GEO_PRIVATE = 1
GEO_UNAVAILABLE = 2

# Retry intervals for GEO_UNAVAILABLE (in seconds): 1d, 3d, 7d, 7d...
RETRY_INTERVALS = [86400, 259200, 604800, 604800]

# Track peer history for recently connected/disconnected
PEER_HISTORY = []  # Last 3 snapshots of peer IDs
MAX_HISTORY = 3

# Recent changes log (for the bottom panel)
RECENT_CHANGES = []  # List of (timestamp, change_type, peer_info)
MAX_RECENT_CHANGES = 10

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

console = Console()


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
        # Check new location first, then old for backwards compat
        config_file = None
        if CONFIG_FILE.exists():
            config_file = CONFIG_FILE
        elif CONFIG_FILE_OLD.exists():
            config_file = CONFIG_FILE_OLD
        else:
            return False

        try:
            with open(config_file, 'r') as f:
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
# PEER PROCESSING (DONE OUTSIDE LIVE CONTEXT)
# ═══════════════════════════════════════════════════════════════════════════════

def process_peers_with_progress(peers: list) -> list:
    """Process all peers, fetch missing geo data with progress bar (OUTSIDE Live context)"""
    # Find peers that need geo lookup
    new_lookups = []
    all_ips = []

    for peer in peers:
        addr = peer.get('addr', '')
        network_type = peer.get('network', get_network_type(addr))
        ip = extract_ip(addr)

        all_ips.append((ip, network_type))

        if is_public_address(network_type):
            geo = get_peer_geo(ip)
            if not geo or should_retry_geo(ip):
                new_lookups.append((ip, network_type))

    # Process new lookups with progress bar (NOT inside Live context)
    if new_lookups:
        total = len(new_lookups)
        console.print(f"\n[bold cyan]{len(peers)} Bitcoin Peers found.[/] Currently stalking each one's location...")

        with Progress(
            SpinnerColumn(),
            TextColumn("[progress.description]{task.description}"),
            BarColumn(),
            TaskProgressColumn(),
            TextColumn("({task.completed}/{task.total})"),
            console=console,
        ) as progress:
            task = progress.add_task("Locating peers...", total=total)

            for i, (ip, network_type) in enumerate(new_lookups):
                # Fetch from API
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

                progress.update(task, advance=1)

                if i < total - 1:
                    time.sleep(GEO_API_DELAY)

        console.print("[green]✓[/] Location lookup complete!\n")

    # Update last_seen for all current peers (no API calls needed)
    for ip, network_type in all_ips:
        geo = get_peer_geo(ip)
        if geo:
            update_peer_seen(ip)
        elif not is_public_address(network_type):
            upsert_peer_geo(ip, network_type, GEO_PRIVATE)

    return all_ips


# ═══════════════════════════════════════════════════════════════════════════════
# DISPLAY
# ═══════════════════════════════════════════════════════════════════════════════

def truncate(text: str, max_len: int) -> str:
    """Truncate string to max length"""
    if len(text) > max_len:
        return text[:max_len-3] + "..."
    return text


def format_location(ip: str, network_type: str) -> str:
    """Format location string"""
    if network_type in ('onion', 'i2p', 'cjdns'):
        return "[PRIVATE LOCATION]"

    geo = get_peer_geo(ip)
    if not geo:
        return "[LOCATION UNAVAILABLE]"

    if geo['geo_status'] == GEO_PRIVATE:
        return "[PRIVATE LOCATION]"
    elif geo['geo_status'] == GEO_UNAVAILABLE or not geo.get('city'):
        return "[LOCATION UNAVAILABLE]"
    else:
        return f"{geo['city']}, {geo['country_code']}"


def create_peer_table(peers: list) -> Table:
    """Create the peer table with Rich"""
    table = Table(
        show_header=True,
        header_style=STYLE_HEADER,
        border_style=STYLE_BORDER,
        expand=True,
        box=None,
    )

    table.add_column("ID", style="white", width=6)
    table.add_column("Address", style="white", width=24)
    table.add_column("Location", style="white", width=22)
    table.add_column("ISP", style="white", width=18)
    table.add_column("In/Out", style="white", width=6)
    table.add_column("Ping", style="white", width=7)
    table.add_column("Sent/Recv", style="white", width=16)
    table.add_column("Version", style="white", width=20)

    for peer in peers:
        peer_id = str(peer.get('id', ''))
        addr = peer.get('addr', '')
        network_type = peer.get('network', get_network_type(addr))
        ip = extract_ip(addr)

        # Location
        location = truncate(format_location(ip, network_type), 22)

        # ISP from database
        geo = get_peer_geo(ip)
        isp = truncate(geo.get('isp', '-') if geo else '-', 18)

        # Direction
        direction = "IN" if peer.get('inbound') else "OUT"

        # Ping
        ping = peer.get('pingtime') or peer.get('pingwait') or 0
        ping_str = f"{int(ping * 1000)}ms" if ping else "-"

        # Bytes
        sent = format_bytes(peer.get('bytessent', 0))
        recv = format_bytes(peer.get('bytesrecv', 0))

        # Version
        version = truncate(peer.get('subver', '').replace('/', ''), 20)

        table.add_row(
            peer_id,
            truncate(ip, 24),
            location,
            isp,
            direction,
            ping_str,
            f"{sent} / {recv}",
            version,
        )

    return table


def create_changes_panel() -> Panel:
    """Create panel showing recent connections/disconnections"""
    if not RECENT_CHANGES:
        content = Text("No recent changes", style=STYLE_DIM)
    else:
        lines = []
        for timestamp, change_type, peer_info in RECENT_CHANGES[-MAX_RECENT_CHANGES:]:
            ip = peer_info.get('ip', 'unknown')
            network = peer_info.get('network', 'unknown')
            time_str = datetime.fromtimestamp(timestamp).strftime('%H:%M:%S')

            if change_type == 'connected':
                lines.append(Text(f"+{ip} {network} connected ({time_str})", style=STYLE_NEW))
            else:
                lines.append(Text(f"-{ip} {network} disconnected ({time_str})", style=STYLE_DISCONNECTED))

        content = Text("\n").join(lines)

    return Panel(
        content,
        title="Recent Changes (last 30s)",
        border_style=STYLE_BORDER,
        padding=(0, 1),
        height=min(len(RECENT_CHANGES) + 3, 8) if RECENT_CHANGES else 4
    )


def create_display(peers: list, stats: dict, next_refresh: int, error: str = "") -> Group:
    """Create the full display layout"""
    parts = []

    # Header
    header_text = Text()
    header_text.append("═" * 110 + "\n", style=STYLE_HEADER)
    header_text.append("  MBTC-DASH Peer List", style=STYLE_HEADER)
    header_text.append(" " * 50, style=STYLE_DIM)
    header_text.append(f"Press 'q' to quit | Refresh: {REFRESH_INTERVAL}s\n", style=STYLE_DIM)
    header_text.append("═" * 110, style=STYLE_HEADER)
    parts.append(header_text)

    # Error or peer count
    if error:
        parts.append(Text(f"\n⚠ {error}\n", style=STYLE_WARN))
    else:
        parts.append(Text(f"\nConnected peers: {len(peers)}\n", style="bold cyan"))

    # Peer table
    if peers:
        parts.append(create_peer_table(peers))
    else:
        parts.append(Text("No peers connected", style=STYLE_DIM))

    # Stats
    stats_text = Text(f"\nDatabase stats: {stats['geo_ok']} geolocated | {stats['private']} private | {stats['unavailable']} unavailable | Networks: {stats['ipv4']} IPv4, {stats['ipv6']} IPv6, {stats['onion']} Tor, {stats['i2p']} I2P, {stats['cjdns']} CJDNS\n", style=STYLE_DIM)
    parts.append(stats_text)

    # Recent changes panel (bottom)
    parts.append(create_changes_panel())

    # Footer
    now = datetime.now().strftime('%Y-%m-%d %H:%M:%S')
    footer_text = Text(f"\nLast update: {now} | Next refresh in {next_refresh}s", style=STYLE_DIM)
    parts.append(footer_text)

    return Group(*parts)


# ═══════════════════════════════════════════════════════════════════════════════
# MAIN
# ═══════════════════════════════════════════════════════════════════════════════

def main():
    global PEER_HISTORY, RECENT_CHANGES

    # Initialize
    init_database()

    # Load config
    if not config.load():
        console.print("[red]Error:[/] Configuration not found. Run ./da.sh first to configure.")
        sys.exit(1)

    # Signal handler for graceful exit
    running = True

    def signal_handler(sig, frame):
        nonlocal running
        running = False

    signal.signal(signal.SIGINT, signal_handler)
    signal.signal(signal.SIGTERM, signal_handler)

    # Keyboard input (non-blocking)
    import select
    import termios
    import tty

    old_settings = termios.tcgetattr(sys.stdin)

    try:
        tty.setcbreak(sys.stdin.fileno())

        # Initial fetch and geo processing (OUTSIDE Live context)
        console.print("[bold cyan]Fetching peer data...[/]")
        peers = get_peer_info()

        if peers:
            process_peers_with_progress(peers)

        current_peer_ids = {str(p.get('id', '')): p for p in peers}
        last_refresh = time.time()

        # Now enter the Live context for smooth table updates
        with Live(console=console, refresh_per_second=4, screen=True) as live:
            while running:
                now = time.time()

                # Check for quit key
                if select.select([sys.stdin], [], [], 0)[0]:
                    key = sys.stdin.read(1)
                    if key.lower() == 'q':
                        break

                # Refresh data (geo lookups already done, just update table)
                if now - last_refresh >= REFRESH_INTERVAL:
                    # Fetch new peer list
                    new_peers = get_peer_info()

                    if new_peers:
                        new_peer_ids = {str(p.get('id', '')): p for p in new_peers}

                        # Find changes
                        current_ids = set(current_peer_ids.keys())
                        new_ids = set(new_peer_ids.keys())

                        # Newly connected
                        for pid in (new_ids - current_ids):
                            peer = new_peer_ids[pid]
                            addr = peer.get('addr', '')
                            network_type = peer.get('network', get_network_type(addr))
                            ip = extract_ip(addr)
                            RECENT_CHANGES.append((now, 'connected', {'ip': ip, 'network': network_type}))

                        # Disconnected
                        for pid in (current_ids - new_ids):
                            peer = current_peer_ids[pid]
                            addr = peer.get('addr', '')
                            network_type = peer.get('network', get_network_type(addr))
                            ip = extract_ip(addr)
                            RECENT_CHANGES.append((now, 'disconnected', {'ip': ip, 'network': network_type}))

                        # Trim old changes (older than 30 seconds)
                        RECENT_CHANGES = [(t, c, p) for t, c, p in RECENT_CHANGES if now - t < 30]

                        # Check for new IPs that need geo lookup
                        needs_lookup = []
                        for peer in new_peers:
                            addr = peer.get('addr', '')
                            network_type = peer.get('network', get_network_type(addr))
                            ip = extract_ip(addr)

                            if is_public_address(network_type):
                                geo = get_peer_geo(ip)
                                if not geo or should_retry_geo(ip):
                                    needs_lookup.append((ip, network_type))
                            elif not get_peer_geo(ip):
                                # Private network, just insert
                                upsert_peer_geo(ip, network_type, GEO_PRIVATE)

                        # If there are new IPs to lookup, we need to exit Live, do lookup, re-enter
                        # For now, just update what we have and note that location is pending
                        # (The next full refresh will pick them up)

                        peers = new_peers
                        current_peer_ids = new_peer_ids

                    last_refresh = now

                # Calculate time until next refresh
                next_refresh = max(0, int(REFRESH_INTERVAL - (now - last_refresh)))

                # Get stats
                stats = get_peer_stats()

                # Update display
                error_msg = "" if peers else "No peers connected or bitcoind not running"
                display = create_display(peers, stats, next_refresh, error_msg)
                live.update(display)

                time.sleep(0.1)

    finally:
        termios.tcsetattr(sys.stdin, termios.TCSADRAIN, old_settings)
        console.print("\n[green]✓[/] Peer list closed")


if __name__ == "__main__":
    main()
