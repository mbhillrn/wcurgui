# MBCore Dashboard

A lightweight monitoring tool for Bitcoin Core nodes that visualizes peer connections on an interactive world map.

**Requires:** Bitcoin Core (`bitcoind`) installed and running on your system.

**No accounts, registrations, or sign-ups required.** Everything runs locally on your machine.

## Why?

Running a Bitcoin node is more enjoyable when you can see your peers across the globe. Traditional monitoring solutions like Grafana require complex setup and configuration. MBCore Dashboard provides instant visualization with zero configuration beyond pointing it at your node.

## Features

- **Interactive World Map** - Watch your peer connections in real-time on a Leaflet.js map
- **Auto-Detection** - Automatically finds your Bitcoin Core installation, datadir, and authentication
- **Peer Geolocation** - Looks up geographic location for each peer using free APIs (no API key needed)
- **Real-Time Updates** - Server-Sent Events push changes to your browser instantly
- **Network Stats** - See connection counts by network type (IPv4, IPv6, Tor, I2P, CJDNS)
- **Connection History** - Track recently connected and disconnected peers
- **Web Dashboard** - Clean, responsive interface accessible from any device on your network
- **Smart Caching** - Geo-location data is cached in a local SQLite database to minimize API calls
- **Configurable Refresh Rate** - Set your preferred update frequency in seconds (default: 10s)
- **Interactive Peer Selection** - Click any peer row to highlight it on the map
- **Version Display** - Shows current version in the header
- **Auto-Update** - Checks for updates from GitHub and offers one-click updates from the menu
- **Antarctica Toggle** - Hide or show private network peers displayed in the Antarctica map area
- **Live BTC Price** - Real-time Bitcoin price from Coinbase API with 10 currency options (USD, EUR, GBP, JPY, CHF, CAD, AUD, CNY, HKD, SGD)
- **Blockchain Status** - View blockchain size, node type (full/pruned), index status, and sync state
- **Network Scores** - Display local address scores for IPv4 and IPv6 from Bitcoin Core
- **System Monitor** - Live CPU and memory usage percentages
- **Collapsible Info Panel** - Configurable panel with show/hide options for each metric

## Quick Start

```bash
# Clone the repository
git clone https://github.com/mbhillrn/MBCore-Dashboard.git
cd MBCore-Dashboard

# Run the dashboard
./da.sh
```

The script will:
1. Check for required dependencies (and offer to install missing ones)
2. Auto-detect your Bitcoin Core installation
3. Launch the web dashboard

Then open your browser to the displayed URL (typically `http://localhost:58333`).

## Network Access & Firewall

The dashboard runs on **port 58333** by default.

### Accessing from the Same Computer (Local)

Simply open your browser to:
```
http://127.0.0.1:58333
```
No firewall configuration needed.

### Accessing from Another Computer on Your Network

To access the dashboard from a phone, tablet, or another computer on your local network:

1. Use your computer's local IP address (e.g., `http://192.168.1.100:58333`)
2. **You may need to open the firewall port** - see below

### Firewall Configuration

**The dashboard includes a built-in Firewall Helper!** From the main menu, select `f) Firewall Helper` to:
- Auto-detect your IP and subnet
- Check if UFW is active
- Optionally add the firewall rule for you

#### Manual Firewall Commands (Ubuntu/Mint/Debian with UFW)

```bash
# Option 1: Allow only your local network (recommended)
sudo ufw allow from 192.168.1.0/24 to any port 58333 proto tcp

# Option 2: Allow from anywhere on the machine
sudo ufw allow 58333/tcp
```

Replace `192.168.1.0/24` with your actual subnet (the Firewall Helper will detect this for you).

#### To Remove the Firewall Rule Later

```bash
# If you used Option 1:
sudo ufw delete allow from 192.168.1.0/24 to any port 58333 proto tcp

# If you used Option 2:
sudo ufw delete allow 58333/tcp
```

#### No Firewall?

If you don't have a firewall enabled (or UFW is inactive), the dashboard should work without any configuration.

## Dependencies

All dependencies are automatically detected on startup. If anything is missing, you'll be offered the option to install it.

### System Tools (Required)

| Tool | Purpose |
|------|---------|
| `jq` | JSON parser for RPC responses |
| `curl` | HTTP client for API calls |
| `sqlite3` | Database for caching peer geo-location data |
| `python3` | Python interpreter (3.8+) |
| `vmstat` | System statistics for CPU monitoring |
| `awk` | Text processing for system stats |

### System Tools (Optional)

| Tool | Purpose |
|------|---------|
| `ss` | Socket statistics for network info |
| `bc` | Calculator for math operations |

### Bitcoin Core

| Tool | Purpose |
|------|---------|
| `bitcoin-cli` | RPC interface to communicate with bitcoind |
| `bitcoind` | Bitcoin Core daemon (must be running) |

### Python Packages (Terminal)

These are installed automatically into a local virtual environment (`./venv/`).

| Package | Purpose |
|---------|---------|
| `rich` | Rich terminal UI library |
| `requests` | HTTP library for API calls |

### Python Packages (Web Dashboard)

| Package | Purpose |
|---------|---------|
| `fastapi` | FastAPI web framework |
| `uvicorn` | ASGI server for FastAPI |
| `jinja2` | Template engine for FastAPI |
| `sse-starlette` | Server-Sent Events for real-time updates |

## How It Works

### Bitcoin Core Detection

On first run, MBCore Dashboard automatically detects your Bitcoin Core setup:

1. **Process Detection** - Checks if `bitcoind` is running and extracts `-datadir` and `-conf` from process arguments
2. **Systemd Detection** - If bitcoind isn't running, checks systemd service configurations
3. **Config File Search** - Looks in common locations (`~/.bitcoin/`, `/etc/bitcoin/`, etc.)
4. **Data Directory Search** - Locates the blockchain data directory
5. **Authentication** - Finds cookie auth file or reads RPC credentials from config
6. **RPC Test** - Verifies connection to Bitcoin Core

All detected settings are saved locally for fast startup on subsequent runs.

### Geo-Location

- Uses ip-api.com (free tier, no API key required)
- Rate limited to 45 requests/minute (script uses 1.5s delay between calls)
- Private networks (Tor, I2P, CJDNS) are marked as "Private Location"
- Failed lookups retry with exponential backoff: 1 day, 3 days, 7 days, then weekly

### Database

Peer data is cached in a local SQLite database at `./data/peers.db`:

- Geographic location (city, region, country, continent, coordinates)
- ISP and AS information
- First seen / last seen timestamps
- Connection count history

The database can be reset from the main menu if needed.

## Main Menu Options

1. **Enter MBCore Web Dashboard** - Launch the web-based dashboard with interactive map
2. **Reset Config** - Clear saved Bitcoin Core configuration
3. **Reset Database** - Clear the peer geo-location cache

Additional options:
- **d) Rerun Detection** - Re-detect Bitcoin Core settings
- **m) Manual Settings** - Manually enter Bitcoin Core paths
- **t) Terminal View** - Basic terminal-based peer list (limited features)
- **u) Update** - Update to the latest version (shown when an update is available)

## Usage Tips

### Refresh Rate

The map update frequency can be adjusted in the stats bar using the "Update Freq" text input. Enter any number of seconds (default: 10). Your preference is saved automatically.

**Recommendation:** On a decently powered machine, a 10-second refresh rate provides a good balance between responsiveness and resource usage. Lower-powered systems may prefer 15 or 30 seconds.

### Peer Selection

Click any row in the peer table to highlight that peer on the map. The map will pan to show the peer's location and display its information popup.

### Private Networks on the Map

Peers using private networks (Tor, I2P, CJDNS) and peers with unavailable geo-location don't have real geographic coordinates. These peers are still shown on the map, scattered across the northern coast of Antarctica. Each peer maintains a stable position during its connection, so dots won't jump around between refreshes. You can identify them by their network color in the popup.

If you prefer not to see these Antarctica dots, click the "Hide" link in the map legend (next to "Private"). Click "Show" to bring them back. Your preference is saved automatically.

### Info Panel

The info panel displays live system and Bitcoin data including:
- **BTC Price** - Current Bitcoin price (updates every 60 seconds by default)
- **Last Block** - Date/time and height of the most recent block
- **Blockchain** - Storage size and node status (Full/Pruned, Indexed, sync state)
- **Network Scores** - Local address advertisement scores for IPv4 and IPv6
- **System Stats** - Current CPU and memory usage

Click the gear icon on the right to configure:
- **Currency** - Choose from USD, EUR, GBP, JPY, CHF, CAD, AUD, CNY, HKD, or SGD
- **Update Interval** - Set how often the panel refreshes (30s, 1m, 2m, or 5m)
- **Show/Hide** - Toggle visibility of individual metrics
- **Collapse Panel** - Minimize the panel to just the gear icon

## Project Structure

```
MBCore-Dashboard/
├── da.sh              # Main entry point
├── lib/               # Shell libraries (UI, config, prereqs)
├── scripts/           # Detection and terminal tools
├── web/               # FastAPI server and frontend
├── data/              # Local database and config (created on first run)
├── venv/              # Python virtual environment (created on first run)
└── docs/              # Documentation
```

## Troubleshooting

### Dashboard won't load from another computer
- Use the **Firewall Helper** from the main menu (`f` key) for easy setup
- Or manually ensure your firewall allows port 58333 (see [Firewall Configuration](#firewall-configuration) above)

### Dashboard won't load at all
- Close any browser tabs from previous dashboard sessions
- Check if port 58333 is in use: `ss -tlnp | grep 58333`

### Bitcoin Core not detected
- Make sure `bitcoind` is running
- Try the manual settings option from the main menu

### Geo-location showing "Unknown"
- The API may be rate limited; wait a few minutes and refresh
- Check your internet connection

## License

MIT License - Free to use, modify, and distribute.

## Support

If you find this useful, consider a small donation:

**Bitcoin:** `bc1qy63057zemrskq0n02avq9egce4cpuuenm5ztf5`

---

*Created by mbhillrn*
