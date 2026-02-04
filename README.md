# M₿Core Dashboard - Live Bitcoin Core Peer Map

A lightweight real-time monitoring dashboard for Bitcoin Core nodes that visualizes peer connections on an interactive world map.

- Interactive world map of YOUR node's actual connected peers
- Zero config - just point at bitcoind
- All 5 protocols (IPv4, IPv6, Tor, I2P, CJDNS) with color-coded network indicators
- Connect, disconnect, and ban peers directly from the dashboard
- Mempool info with real-time stats
- Live Bitcoin price with persistent green/red coloring
- No accounts, no external services requiring signup, runs locally
- Lightweight single script install
- Real-time with SSE updates
- Two-column layout with sidebar, finite world map, and unified settings
- Scrollable peer list with color-coded connection types and network text
- Clickable recent updates to fly to peer locations on the map
- GeoIP database with one-click update from GitHub

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

### Dashboard Layout
- **Two-Column Layout** - Sidebar with node info, system stats, price, and recent updates alongside the main map
- **M₿Core Branding** - Color-coded header with darker blue M/Core and lighter blue ₿ symbol
- **Unified Settings** - Single settings dropdown for refresh rates, visibility toggles, and panel configuration

### Map
- **Interactive World Map** - Leaflet.js dark map (CartoDB Dark Matter) with full vertical coverage from Russia to Antarctica
- **Map Display Modes** - Normal (finite), Wrap + Points (world wraps with ghost markers), Wrap Only (world wraps), and Stretched (horizontal stretch to see more)
- **Fit All Button** - One-click zoom to show all connected peers; auto-fits on page load and when changing map modes
- **Network-Colored Markers** - Each peer dot is colored by its network type (IPv4 yellow, IPv6 red, Tor blue, I2P purple, CJDNS pink)
- **Antarctica Clustering** - Private network peers (Tor, I2P, CJDNS) are placed at stable positions along the northern Antarctic coastline
- **Region Selector** - Quick-jump to World, North America, South America, Europe, Africa, Middle East, Asia, Oceania, or Antarctica
- **Hide/Show Antarctica** - Toggle private network dots in the map legend
- **New Peer Animations** - Green pulse that fades to network color when a new peer connects

### Peer Table
- **Scrollable Peer List** - Fixed-height table with scroll for large peer counts
- **Network-Colored Text** - All columns use network-specific colors for quick visual identification
- **Connection Type Badges** - Green-highlighted box for inbound (INB), blue-highlighted box for outbound types (OFR, BLO, MAN, FET, FEL)
- **Bytes Sent/Received** - Sent in blue, received in green for easy differentiation
- **Addrman Status** - Green for Yes, red for No
- **Column Separators** - Visible borders between column headers for easier resizing
- **Column Configuration** - Show/hide any of 38+ columns including extended geo fields
- **Drag-and-Drop Reorder** - Rearrange columns by dragging headers
- **Resizable Columns** - Drag column edges to resize
- **3-State Sorting** - Click headers to cycle: unsorted → ascending → descending
- **Network Filters** - Filter by all, IPv4, IPv6, Tor, I2P, or CJDNS; active filter stays bold in its network color
- **Configurable Row Limit** - Show 5 to 50 visible rows (default 15) via the column config menu
- **Click to Map** - Click any peer row to fly to its location on the map

### Node Info Sidebar
- **Peer Count** - Total connected peers with hover tooltip
- **Blockchain Size** - Total size displayed without space (e.g., "817.5GB")
- **Node Type** - Full vs Pruned with hover tooltip
- **Indexed** - Whether txindex is enabled
- **IBD Status** - Initial Block Download status on both label and value

### System Information
- **CPU & RAM** - Live percentages with detailed breakdown tooltips on both labels and values
- **Network Traffic** - Real-time inbound/outbound traffic bars with adaptive scaling
- **MBCore DB** - Click to see GeoIP database details with colored settings (green for On, blue for paths)
- **Database Update** - Prominent blue update button that shows "Working..." feedback immediately

### Bitcoin Price
- **Live Price** - Real-time from Coinbase API with configurable update interval
- **Persistent Coloring** - Green when price goes up, red when it goes down, stays colored
- **10 Currencies** - USD, EUR, GBP, JPY, CHF, CAD, AUD, CNY, HKD, SGD

### Node Status Bar
- **Protocol Status** - Shows enabled and not-configured networks with color-coded names
- **Hover Tooltips** - Full protocol line hover for configuration details
- **Help Cursor** - Visual indicator that hovering reveals information
- **Connected Count** - Total peers with "Total Connected Peers" tooltip
- **Mempool & Last Block** - Click for detailed modal views

### Recent Updates
- **Fixed-Size Panel** - Scrollable list that doesn't push the map down
- **Clickable Connections** - Click a green (connected) entry to fly to that peer on the map
- **Configurable Window** - Show last 10s, 20s, 30s, 1m, 2m, or 5m of changes
- **Detailed Panel** - Toggle a full changes table below the peer list

### Peer Management
- **Connect Peer** - Manually add peers with CLI command preview
- **Disconnect/Ban** - Remove peers with optional 24-hour IP ban
- **Ban List** - View and manage all active bans
- **BTC Address Copy** - Click-to-copy with fallback for HTTP contexts

### Other
- **Auto-Detection** - Automatically finds your Bitcoin Core installation, datadir, and authentication
- **Peer Geolocation** - Looks up geographic location using ip-api.com (no API key needed)
- **Real-Time Updates** - Server-Sent Events push changes instantly
- **Smart Caching** - GeoIP data cached in SQLite to minimize API calls
- **Auto-Update** - One-click updates from the main menu
- **Configurable Refresh** - Set update frequency in seconds (default: 10s)

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

**Geo/IP Database** (`./data/geo.db`):
- Caches full API responses from ip-api.com to minimize API calls
- Stores: geographic location, ISP, AS info, timezone, currency, and more
- Shared across sessions - data persists even after restart
- Optionally downloads from the [Bitcoin Node GeoIP Dataset](https://github.com/mbhillrn/Bitcoin-Node-GeoIP-Dataset) for instant lookups
- Check integrity, reset, and configure from the main menu (**g) Geo/IP Database**)
- First-run prompts you to enable/disable database caching

## Main Menu Options

1. **Enter MBCore Web Dashboard** - Launch the web-based dashboard with interactive map
2. **Reset Config** - Clear saved Bitcoin Core configuration
3. **Firewall Helper** - Configure firewall for network access

Additional options:
- **g) Geo/IP Database** - Manage the geo-location cache database (integrity check, reset, advanced options)
- **d) Rerun Detection** - Re-detect Bitcoin Core settings
- **m) Manual Settings** - Manually enter Bitcoin Core paths
- **p) Port Settings** - Change the dashboard port (default: 58333). Useful if port 58333 is in use or you prefer a different port. This setting persists across reboots and updates.
- **u) Update** - Update to the latest version (shown when an update is available)

## Usage Tips

### Refresh Rate

The peer update frequency can be adjusted in the settings dropdown (gear icon in the header). Enter any number of seconds (default: 10). Bitcoin price has its own independent update interval (also configurable, default: 10s).

**Recommendation:** 10 seconds provides a good balance between responsiveness and resource usage.

### Peer Selection

Click any row in the peer table to highlight that peer on the map. The map will fly to the peer's location and display its information popup. You can also click connected entries in the Recent Updates sidebar to fly to newly connected peers.

### Private Networks on the Map

Peers using private networks (Tor, I2P, CJDNS) and peers with unavailable geo-location don't have real geographic coordinates. These peers are shown on the map, scattered across the northern coast of Antarctica. Each peer maintains a stable position during its connection. You can identify them by their network color.

Click "Hide"/"Show" in the map legend (next to "Private") to toggle Antarctica dots.

### Sidebar

The right sidebar displays live system and Bitcoin data in collapsible sections:

- **Node Info** - Peers, blockchain size, node type, indexed status, IBD status (all with hover tooltips on both labels and values)
- **System Information** - CPU and RAM with detailed breakdown tooltips, network traffic bars, MBCore DB status
- **Bitcoin Price** - Live price with persistent green/red coloring, click currency label to change
- **Recent Updates** - Fixed-height scrollable list of peer connections/disconnections

Use the settings dropdown to show/hide individual sections.

### Blockchain Info

Click the **Blockchain** button in the Node Status panel header to view detailed blockchain information:

- **Chain** - The blockchain network (main, test, signet, regtest)
- **Sync Progress** - Visual progress bar showing verified blocks vs. total headers
- **Block Height** - Current height of the local blockchain
- **Best Block Hash** - Hash of the tip of the best valid chain
- **Difficulty** - Current mining difficulty target (human-readable, e.g. "141.7 T" - hover for full number)
- **Median Time** - Median timestamp of the last 11 blocks
- **Chain Work** - Total proof-of-work in the active chain
- **Initial Block Download** - Whether the node is still syncing
- **Size on Disk** - How much disk space the blockchain uses
- **Pruning Enabled** - Whether old blocks are deleted (shows lowest kept block)
- **Prune Target** - Target size for pruning (if enabled)
- **Softforks** - Status of all protocol upgrades (taproot, segwit, etc.)

### Mempool Info

Click the **Mempool** button in the Node Status panel header to view detailed mempool statistics:

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

The peer table displays detailed information about each connected peer. Click the gear icon above the table to customize which columns are visible. Columns always reset to defaults on page load.

#### Connection Type Badges

The **Type** column shows highlighted badges indicating how each peer is connected:

| Badge | Background | Text Color | Direction | Description |
|-------|-----------|------------|-----------|-------------|
| **INB** | Green | Green | Inbound | Peer initiated the connection to you |
| **OFR** | Blue | Blue | Outbound | Normal outbound peer (transactions + blocks) |
| **BLO** | Blue | Yellow | Outbound | Block relay only (no tx or addr relay) |
| **MAN** | Blue | Blue | Outbound | Manually added via addnode RPC or config |
| **FET** | Blue | Light Blue | Outbound | Short-lived connection to solicit addresses |
| **FEL** | Blue | Light Blue | Outbound | Short-lived connection to test reachability |

Hover over any badge to see its full description.

#### Direction Badges (Optional Column)

| Badge | Color | Description |
|-------|-------|-------------|
| **IN** | Green | Inbound - They connected to us |
| **OUT** | Blue | Outbound - We connected to them |

#### Data Coloring

| Column | Color Scheme |
|--------|-------------|
| **Network text** | All columns use network-specific colors (IPv4 yellow, IPv6 red, Tor blue, I2P purple, CJDNS pink) |
| **Bytes Sent** | Blue |
| **Bytes Received** | Green |
| **In Addrman?** | Green for Yes, Red for No |

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
- The API is throttled to one every 1.5 seconds, which is reasonably fast. "Stalking..." means that it is still finding the location of that peer.
- Check your internet connection

## License

MIT License - Free to use, modify, and distribute.

## Support

If you find this useful, consider a small donation:

**Bitcoin:** `bc1qy63057zemrskq0n02avq9egce4cpuuenm5ztf5`

---

*Created by [@mbhillrn](https://github.com/mbhillrn/Bitcoin-Core-Peer-Map)*
