# MBCore Dashboard

A lightweight monitoring tool for Bitcoin Core nodes that visualizes peer connections on an interactive world map.

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
- **Configurable Refresh Rate** - Choose your preferred update frequency (5s, 10s, 15s, 30s, or 60s)
- **Interactive Peer Selection** - Click any peer row to highlight it on the map

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

## Dependencies

All dependencies are automatically detected on startup. If anything is missing, you'll be offered the option to install it.

### System Tools (Required)

| Tool | Purpose |
|------|---------|
| `jq` | JSON parser for RPC responses |
| `curl` | HTTP client for API calls |
| `sqlite3` | Database for caching peer geo-location data |
| `python3` | Python interpreter (3.8+) |

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

## Usage Tips

### Refresh Rate

The map update frequency can be adjusted using the buttons in the map panel header. Available options are 5s, 10s, 15s, 30s, and 60s. Your preference is saved automatically.

**Recommendation:** On a decently powered machine, a 10-second refresh rate provides a good balance between responsiveness and resource usage. Lower-powered systems may prefer 15s or 30s.

### Peer Selection

Click any row in the peer table to highlight that peer on the map. The map will pan to show the peer's location (or Antarctica cluster for private networks) and display its information popup.

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

### Dashboard won't load in browser
- Ensure your firewall allows the dashboard port (default: 58333)
- Ubuntu/Mint: `sudo ufw allow 58333/tcp`

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
