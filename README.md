# MBCore Dashboard - Live Bitcoin Core Peer Map

A lightweight real-time monitoring dashboard for Bitcoin Core nodes that visualizes peer connections on an interactive world map.

- Interactive world map of YOUR node's actual connected peers
- Zero config - just point at bitcoind
- All 5 protocols (IPv4, IPv6, Tor, I2P, CJDNS)
- Connect, disconnect, and ban peers directly from the dashboard
- Mempool info with real-time stats
- No accounts, no external services requiring signup, runs locally
- Lightweight single script install
- Real-time with SSE updates
- Beautiful aesthetic

**Requires:** Bitcoin Core (`bitcoind`) installed and running on your system.

**Download Repo "Quick" Reference**
```bash
# Clone the repository
git clone https://github.com/mbhillrn/Bitcoin-Core-Peer-Map.git
cd Bitcoin-Core-Peer-Map
```

---

## Table of Contents

- [Tested On / Compatibility](#tested-on--compatibility)
- [Why?](#why)
- [Features](#features)
- [Quick Start](#quick-start)
- [First Run](#first-run)
- [How To Access The Dashboard](#how-to-access-the-dashboard)
- [Firewall Configuration](#firewall-configuration)
- [Dependencies](#dependencies)
- [How It Works](#how-it-works)
- [Main Menu Options](#main-menu-options)
- [Usage Tips](#usage-tips)
- [Project Structure](#project-structure)
- [Troubleshooting](#troubleshooting)
- [License](#license)
- [Support](#support)

---

## Tested On / Compatibility

**Tested and works out of the box:**
- Ubuntu 22.04, 24.04
- Linux Mint
- Debian

**Should work with minor adjustments:**
- Fedora, Arch Linux (Python venv is included by default, but if issues occur, the script will guide you)

**May need additional configuration:**
- Docker-based Bitcoin Core setups
- Other Linux distributions
- Non-standard Bitcoin Core installations

If you're running a less common setup and run into issues, please [open an issue on GitHub](https://github.com/mbhillrn/Bitcoin-Core-Peer-Map/issues). If you know your way around your system, you can likely get it working - and your feedback helps us improve compatibility for everyone.

---

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
- **Mempool Info** - View detailed mempool statistics including pending transactions, fees, memory usage, and policy settings
- **Peer Management** - Connect to new peers, disconnect existing peers, and manage IP bans directly from the dashboard

## Quick Start

```bash
# Clone the repository
git clone https://github.com/mbhillrn/Bitcoin-Core-Peer-Map.git
cd Bitcoin-Core-Peer-Map

# Run the dashboard
./da.sh
```

The script will:
1. Check for required dependencies (and offer to install missing ones)
2. Auto-detect your Bitcoin Core installation
3. Create a Python virtual environment
4. Launch the web dashboard on port 58333

**For detailed setup instructions, see [QUICKSTART.md](QUICKSTART.md).**

---

## First Run

On first run, the script automatically handles setup. Here's what you might see:

### Python Virtual Environment Setup

The dashboard uses a Python virtual environment to keep its packages isolated. If you don't have one yet:

```
Checking your python...
⚠ No virtual environment found
? Setup virtual environment and install packages? [y/N] y
```

### Ubuntu/Debian: Missing python3-venv

Ubuntu and Debian require an extra package for Python virtual environments. If it's not installed, you'll see:

```
Python said:

The virtual environment was not created successfully because ensurepip is not
available...

We can fix this for you!

On Ubuntu/Debian systems, Python needs an extra package to create
virtual environments. We can install it now.

? Install python3.12-venv now? [y/N] y
```

Just press `y` and enter your password - the script handles the rest.

### Recovering from Incomplete Installation

If a previous installation was interrupted, the script detects this and offers to reset:

```
MBCore Dashboard virtual environment needs to be reset

We found an existing MBCore Dashboard virtual environment, but it appears
to be incomplete (possibly from a previous installation that didn't finish).

This only affects the ./venv folder inside this project directory.
Your other Python environments are not affected.

? Reset the MBCore Dashboard virtual environment? [y/N] y
```

### Successful Setup

Once everything is installed, you'll see:

```
✓ Virtual environment created
✓ Pip upgraded
✓ Installed rich
✓ Installed requests
✓ Installed fastapi
✓ Installed uvicorn
✓ Installed jinja2
✓ Installed sse_starlette

** All packages installed successfully!! **
```

After this, the script proceeds to detect your Bitcoin Core installation.

---

## How To Access The Dashboard

### Scenarios:

- **Scenario 1:** Bitcoin Core on a full GUI Linux/Ubuntu machine with desktop and browser (not headless)
- **Scenario 2:** Bitcoin Core on a headless Linux machine (no desktop/browser)
  - Option A: Expose on LAN
  - Option B: SSH Tunnel

---

### Scenario 1: Full GUI Linux/Ubuntu Machine (Not Headless)

This is the easiest case. On the machine running Bitcoin Core:

```bash
cd /path/to/Bitcoin-Core-Peer-Map
./da.sh
```

The script will:
1. Check prerequisites (jq, curl, sqlite3, python3, etc.)
2. Detect your Bitcoin Core setup
3. Create a Python virtual environment
4. Start the web server on port 58333
5. **Automatically open your browser** to `http://127.0.0.1:58333`

You're done - the dashboard appears in your browser.

---

### Scenario 2: Headless Linux Machine (No Desktop/Browser)

A headless machine has no local browser, so you need to access the dashboard from another device.

---

#### Scenario 2 Option A: Expose on LAN

On the Bitcoin Core machine (either directly or via SSH), start the dashboard:

```bash
cd /path/to/Bitcoin-Core-Peer-Map
./da.sh
```

The script will:
1. Check prerequisites (jq, curl, sqlite3, python3, etc.)
2. Detect your Bitcoin Core setup
3. Create a Python virtual environment
4. Start the web server on port 58333

Select option `1) Enter MBCore Dashboard` from the main menu.

When the dashboard starts, it displays the access URLs right on screen:

```
════════════════════════════════════════════════════════════════════════════════════
  ** FOLLOW THESE INSTRUCTIONS TO GET TO THE DASHBOARD! **
════════════════════════════════════════════════════════════════════════════════════

  To enter the dashboard, visit (First run? See README/QUICKSTART)

  Scenario 1 - Local Machine Only:
      http://127.0.0.1:58333

  Scenario 2 - From Another Device on Your Network:
    Option A - Direct LAN Access (may need firewall configured - SEE README)
      http://192.168.x.x:58333  <- Your node's detected IP

    Option B - SSH Tunnel (SEE README - then visit)
      http://127.0.0.1:58333

────────────────────────────────────────────────────────────────────────────────────
  TROUBLESHOOTING: SEE THE README
────────────────────────────────────────────────────────────────────────────────────
```

**Your machine's IP address will be displayed on this screen.** From any other computer on your network, open a browser and go to that address:

```
(EXAMPLE) http://192.168.x.xxx:58333
```

The correct IP for your setup will be shown in the terminal output.

**If it won't connect from another device:** Your firewall may be blocking port 58333. See [Firewall Configuration](#firewall-configuration) below.

---

#### Scenario 2 Option B: SSH Tunnel

From your **other computer** (the one with a browser):

```bash
# SSH into the headless machine with a tunnel
ssh -L 58333:127.0.0.1:58333 user@headless-machine-ip
```

Then on the headless machine (via that SSH session):

```bash
cd /path/to/Bitcoin-Core-Peer-Map
./da.sh
```

The script will:
1. Check prerequisites (jq, curl, sqlite3, python3, etc.)
2. Detect your Bitcoin Core setup
3. Create a Python virtual environment
4. Start the web server on port 58333

Select option `1) Enter MBCore Dashboard` from the main menu.

Now on your **local computer's browser**, go to:
```
http://127.0.0.1:58333
```

The tunnel forwards your local port 58333 to the headless machine's port 58333. No firewall changes needed.

---

### Quick Reference

| Situation | How to Access |
|-----------|---------------|
| Full GUI machine | Run `./da.sh` → browser auto-opens to `http://127.0.0.1:58333` |
| Headless + LAN access | Run `./da.sh` → note IP shown on screen → browse to `http://[that-ip]:58333` from any device on your network |
| Headless + SSH tunnel | `ssh -L 58333:127.0.0.1:58333 user@host` → run `./da.sh` → browse to `http://127.0.0.1:58333` on your local machine |

---

## Firewall Configuration

**The dashboard includes a built-in Firewall Helper!** From the main menu, select `4) Firewall Helper` to:
- Auto-detect your IP and subnet
- Check if UFW or firewalld is active
- Optionally add the firewall rule for you

**Using a different port?** Use `p) Port Settings` from the main menu to change the dashboard port before running the Firewall Helper. The helper will automatically use your configured port.

### Manual Firewall Commands (Ubuntu/Mint/Debian with UFW)

```bash
# Option 1: Allow only your local network (recommended)
sudo ufw allow from 192.168.1.0/24 to any port 58333 proto tcp

# Option 2: Allow from anywhere on the machine
sudo ufw allow 58333/tcp
```

Replace `192.168.1.0/24` with your actual subnet (the Firewall Helper will detect this for you).

### To Remove the Firewall Rule Later

```bash
# If you used Option 1:
sudo ufw delete allow from 192.168.1.0/24 to any port 58333 proto tcp

# If you used Option 2:
sudo ufw delete allow 58333/tcp
```

### No Firewall?

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

### Python Packages

These are installed automatically into a local virtual environment (`./venv/`).

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
4. **Firewall Helper** - Configure firewall for network access

Additional options:
- **d) Rerun Detection** - Re-detect Bitcoin Core settings
- **m) Manual Settings** - Manually enter Bitcoin Core paths
- **p) Port Settings** - Change the dashboard port (default: 58333). Useful if port 58333 is in use or you prefer a different port. This setting persists across reboots and updates.
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

### Mempool Info

Click the **MemPool Info** button in the Node Status panel header to view detailed mempool statistics:

- **Pending Transactions** - Number of unconfirmed transactions
- **Data Size** - Total size of transaction data in the mempool
- **Memory Usage** - RAM used by the mempool
- **Total Fees** - Sum of all fees waiting (shown in BTC and your selected currency)
- **Max Mempool Size** - Configured maximum mempool size
- **Min Accepted Fee** - Minimum fee rate for mempool acceptance (shown in both sat/vB and BTC/kvB)
- **Min Relay Fee** - Policy minimum for transaction relay
- **RBF Increment** - Minimum fee bump for Replace-By-Fee
- **Unbroadcast Txs** - Transactions not yet announced to peers
- **Full RBF** - Whether full Replace-By-Fee is enabled
- **Bare Multisig Relay** - Policy for bare multisig transactions
- **Max Data Carrier** - Maximum OP_RETURN data size

### Peer Management

The dashboard provides tools to manage peer connections directly:

#### Connect to Peer

Click **Connect Peer** in the Connected Peers panel to manually connect to a peer. Enter the peer's listening address in one of these formats:

- **IPv4:** `192.168.1.10` (port 8333 used if omitted)
- **IPv6:** `[2001:db8::1]` (port 8333 used if omitted)
- **Tor:** `abc...xyz.onion` (port 8333 used if omitted)
- **CJDNS:** `[fc00::1]` (passed as-is)
- **I2P:** `abc...xyz.b32.i2p:0` (port :0 is required)

The modal also shows the full CLI command for permanently adding a peer.

#### Disconnect Peer

Click **Disconnect Peer** to open the peer management dropdown:

1. Enter the **Peer ID** (shown in the ID column of the peer table)
2. Optionally check **Ban IP for 24 hours** to also ban the peer's IP
3. Click **Disconnect** to execute

**Note:** Banning only works for IPv4 and IPv6 peers. Tor, I2P, and CJDNS peers don't have bannable IP identities in Bitcoin Core.

#### Manage Bans

From the Disconnect Peer dropdown:

- **List Banned IPs** - View all currently banned IPs with expiry times and individual unban buttons
- **Clear All Bans** - Remove all IP bans at once

### Dashboard Column Reference

The peer table displays detailed information about each connected peer. Click the gear icon (⚙️) above the table to customize which columns are visible.

#### Connection Type Badges

The **Type** column shows color-coded badges indicating how each peer is connected:

| Badge | Color | Description |
|-------|-------|-------------|
| **INB** | 🟢 Green | **Inbound** - They connected to us (full relay) |
| **OFR** | 🔵 Blue | **Outbound Full Relay** - We connected to them (transactions + blocks) |
| **BLO** | 🔵 Dark Blue | **Block Relay Only** - We connected, blocks only (no transactions - privacy feature) |
| **MAN** | 🩷 Pink | **Manual** - Added via `addnode` command |
| **FET** | 🩵 Cyan | **Address Fetch** - Temporary connection to get peer addresses |
| **FEL** | 🩵 Cyan | **Feeler** - Temporary connection to test if a node is reachable |

Hover over any badge to see its full description.

#### Direction Badges (Optional Column)

The **in/out** column (available via Configure) shows simple direction badges:

| Badge | Color | Description |
|-------|-------|-------------|
| **IN** | 🟢 Green | Inbound - They connected to us |
| **OUT** | 🔵 Blue | Outbound - We connected to them |

#### Other Key Columns

| Column | Description |
|--------|-------------|
| **ID** | Peer ID assigned by Bitcoin Core |
| **Net** | Network type (ipv4, ipv6, onion, i2p, cjdns) |
| **Since** | Connection duration (e.g., `2m30s`, `1h15m`, `3d4h`) |
| **Service** | Service flags (N=NETWORK, W=WITNESS, etc.) |
| **In Addrman?** | Whether this peer's address is in our address manager |

## Project Structure

```
Bitcoin-Core-Peer-Map/
├── da.sh              # Main entry point
├── lib/               # Shell libraries (UI, config, prereqs)
├── scripts/           # Detection scripts
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
