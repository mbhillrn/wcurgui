# M₿Core Dashboard - Live Bitcoin Core Peer Map (Geolocation)

A lightweight real-time monitoring dashboard for Bitcoin Core nodes that visualizes peer connections on an interactive world map.

![MBCore Dashboard](docs/images/1.Full.Front.Dash.png)

- Interactive world map of YOUR node's actual connected peers
- No accounts, no external services requiring signup, runs locally!
- Real-time with automatic (and optoinal) updates of software and maintained geolocation database
- Zero config - just point at bitcoind
- Dashboard supports all 5 protocols (IPv4, IPv6, Tor, I2P, CJDNS) with color-coded network indicators
- Geolocation supported on public internet protocols (Ipv4, Ipv6)
- Connect, disconnect, and ban peers directly from the dashboard
- Mempool info with real-time stats
- Live Bitcoin price with persistent price move indication
- Lightweight single script install
- Two-column layout with sidebar, finite world map, and unified settings
- Scrollable peer list with color-coded connection types and network text
- Click peer to zoom directly to location on the map!
- GeoIP database with one-click server update directly from Github repo (now without even leaving the map!)

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

Running a Bitcoin node is more enjoyable when you can see your peers across the globe. Traditional monitoring solutions require complex setup and configuration. MBCore Dashboard provides instant visualization with zero configuration beyond pointing it at your node.

## Features

### Dashboard Layout
- **Two-Column Layout** - Sidebar with node info, system stats, price, and recent updates alongside the main map
- **M₿Core Branding** - Color-coded header with darker blue M/Core and lighter blue ₿ symbol
- **Unified Settings** - Single settings dropdown for refresh rates, visibility toggles, and panel configuration

### Map
- **Interactive World Map** - Leaflet.js dark map (CartoDB Dark Matter) with full vertical coverage from Russia to Antarctica
- **Map Display Modes** - Normal (finite), Wrap + Points (world wraps with ghost markers), Wrap Only (world wraps), and Stretched (horizontal stretch to see more)
- **Fit All Button** - One-click zoom to show all connected peers; auto-fits on page load and when changing map modes
- **Network-Colored Markers** - Each peer dot is colored by its network type (IPv4 yellow, IPv6 red, Tor blue, I2P purple, CJDNS light purple)
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

**Clone and run** - the script handles everything else:

```bash
git clone https://github.com/mbhillrn/Bitcoin-Core-Peer-Map.git
cd Bitcoin-Core-Peer-Map
./da.sh
```

That's it. On first run you'll be walked through setup - just press `y` at each prompt. Here's what to expect:

---

### Step 1: Prerequisites & Virtual Environment

The script checks for required tools and sets up a Python environment. Press `y` to install:

![Prerequisites and venv setup](docs/images/2.venv-prompt.png)

Packages install automatically:

![Package installation](docs/images/3.install-success.png)

### Step 2: Bitcoin Core Detection

Your Bitcoin Core setup is auto-detected. Press `y` to accept:

![Bitcoin Core detection](docs/images/4.detection.png)

If detection fails or finds the wrong paths, press `n` to enter them manually:

![Manual configuration](docs/images/4a.manual.bitcoin.conf.entry.png)

### Step 3: Geo/IP Database Setup

Choose how to handle peer geolocation data (Option 1 recommended):

![GeoIP Database Setup](docs/images/4c.GeoIP.First.Run.png)

- **Option 1: Enable and keep updated** (Recommended) - Downloads a shared database of known Bitcoin node locations for instant lookups. Auto-updates on each start.
- **Option 2: Enable, self-managed** - Only caches peers you discover yourself. No external database.
- **Option 3: Don't use a database** - Relies on live API lookups only (still usable, but limited to one call per 1-2 seconds).

If you choose Option 1, the database downloads in seconds:

![GeoIP Database Download](docs/images/4d.GeoIP.dbdl.png)

### Step 4: Launch the Dashboard

You'll land at the main menu. Press `1` to start the dashboard:

![Main Menu](docs/images/5.main-menu.png)

The dashboard launches and shows you your access URLs:

![Dashboard Launch](docs/images/10.dashboard-launch.png)

Open the URL in your browser and you're in:

![MBCore Dashboard](docs/images/1.Full.Front.Dash.png)

**For access scenarios (headless, SSH tunnel, firewall), see [How To Access The Dashboard](#how-to-access-the-dashboard) below or the detailed [QUICKSTART.md](QUICKSTART.md).**

### Recovering from Incomplete Installation

If a previous installation was interrupted (power loss, etc.), the script detects this and offers to reset:

```
MBCore Dashboard virtual environment needs to be reset

We found an existing MBCore Dashboard virtual environment, but it appears
to be incomplete (possibly from a previous installation that didn't finish).

This only affects the ./venv folder inside this project directory.
Your other Python environments are not affected.

? Reset the MBCore Dashboard virtual environment? [y/N] y
```

---

## How To Access The Dashboard

When you select `1) Enter MBCore Dashboard` from the main menu, you'll see this screen:

![Dashboard Launch](docs/images/10.dashboard-launch.png)

The dashboard runs as a local web server. Open the URL in any browser to access it.

### From the Same Machine

Use either address - both work:
- `http://127.0.0.1:58333` (localhost)
- `http://[your-lan-ip]:58333` (shown on screen)

On GUI machines with a desktop, the browser opens automatically.

### From Another Computer on Your Network (for headless setups, or just from another computer!)

Use the LAN IP shown on the dashboard launch screen:
```
http://192.168.x.x:58333
```

Your actual IP will be displayed. If it won't connect, your firewall may be blocking port 58333 - see the next section: [Firewall Configuration](#firewall-configuration).

### From Outside Your Network (SSH Tunnel)

If you're accessing a machine from outside your network, or just prefer a tunnel for security:

1. From your local computer, SSH with port forwarding:
   ```bash
   ssh -L 58333:127.0.0.1:58333 user@remote-machine
   ```

2. Start the dashboard on the remote machine via that SSH session

3. Open `http://127.0.0.1:58333` in your local browser

The tunnel forwards your local port to the remote machine. No firewall changes needed.

---

### Quick Reference

| Situation | How to Access |
|-----------|---------------|
| Full GUI machine | Run `./da.sh` → browser auto-opens to `http://127.0.0.1:58333` |
| Headless + LAN access | Run `./da.sh` → note IP shown on screen → browse to `http://[that-ip]:58333` from any device on your network |
| Headless + SSH tunnel | `ssh -L 58333:127.0.0.1:58333 user@host` → run `./da.sh` → browse to `http://127.0.0.1:58333` on your local machine |

---

## Firewall Configuration

**The dashboard includes a built-in Firewall Helper!** From the main menu, select `3) Firewall Helper`:

![Firewall Helper](docs/images/6.firewall-helper.png)

The Firewall Helper automatically:
- Detects your IP address and subnet
- Checks if UFW or firewalld is active
- Shows your current firewall rules for the dashboard port
- Provides ready-to-use commands to reverse any changes

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

1. **Process Detection** - Checks first if `bitcoind` (or similar process) is running and extracts `-datadir` and `-conf` from process arguments
2. **Systemd Detection** - If bitcoind isn't running, checks systemd service configurations and extracts from there.
3. **Config File Search** - If still unfound, looks in common locations (`~/.bitcoin/`, `/etc/bitcoin/`, etc.)
4. **Data Directory Search** - Unlikely, but if settings still ar not located, it searches for the blockchain data directory
5. **Authentication** - Finds cookie auth file or reads RPC credentials
6. **RPC Test** - Verifies connection to Bitcoin Core

All detected settings are saved locally for fast startup on subsequent runs.

### Geo-Location

- Uses MBCore database of geolocated bitcoin nodes, bitcoin-cli, and ip-api.com (free tier, no API key required)
- Rate limited to 45 requests/minute (script uses 1.5s delay between calls)
- Private networks (Tor, I2P, CJDNS) are marked as "Private Location" (and placed with the penguins in Antarctica - more on this later)

### Database

**Geo/IP Database** (`./data/geo.db`):
- Utilizes MBCore database full of geolocated Bitcoin Core nodes
- Caches full API responses to minimize API calls
- Stores: geographic location, ISP, AS info, timezone, currency, and more
- Shared across sessions - data persists even after restart
- Optionally (recommended/default) downloads from the [Bitcoin Node GeoIP Dataset](https://github.com/mbhillrn/Bitcoin-Node-GeoIP-Dataset) for instant lookups
- Check integrity, reset, and configure from the main menu (**g) Geo/IP Database**)
- First-run prompts you to enable/disable database caching (just enable it, theres no reason not to)
- With database, you can block all traffic but bitcoin core traffic and still geolocate peers from offline data

## Main Menu Options

![Main Menu](docs/images/5.main-menu.png)

1. **Enter MBCore Web Dashboard** - Launch the web-based dashboard with interactive map
2. **Reset MBCore Config** - Clear saved Bitcoin Core configuration
3. **Firewall Helper** - Configure firewall for network access

Additional options:
- **g) Geo/IP Database** - Manage the geo-location cache database (integrity check, reset, advanced options)
- **d) Rerun Detection** - Re-detect Bitcoin Core settings
- **m) Manual Settings** - Manually enter Bitcoin Core paths
- **p) Port Settings** - Change the dashboard port (default: 58333). Useful if port 58333 is in use or you prefer a different port. This setting persists across reboots and updates.
- **u) Update** - Update to the latest version (shown when an update is available)

### Port Settings

![Port Settings](docs/images/9.port-settings.png)

Change the dashboard port if 58333 conflicts with another service or you prefer a different port. The setting persists across restarts and updates.

### Auto-Update

When a new version is available, you'll see the update prompt:

![Auto Update](docs/images/8.Auto.Update.png)

Press `y` to update - your configuration and database are preserved.

### Geo/IP Database Settings

Access advanced database options from the main menu with `g`:

![Geo/IP Database Settings](docs/images/7.geo-database.png)

## Usage Tips

**Pro tip:** Hover over labels and values throughout the dashboard - many elements reveal additional details in tooltips.

### Refresh Rate

![Settings Dropdown](docs/images/17.settings-dropdown.png)

The peer update frequency can be adjusted in the settings dropdown (gear icon in the header). Enter any number of seconds (default: 10).

![Currency Settings](docs/images/17a.Currency-menu.png)

Bitcoin price has its own settings - click the currency label (USD, EUR, etc.) to change currency or adjust the price update interval.

**Recommendation:** 10 seconds provides a good balance between responsiveness and resource usage.

### Map Features

#### Map Display Modes

![Map Modes](docs/images/11.map-modes.png)

Choose how the map displays:
- **Normal** - Standard finite world map
- **Wrap + Points** - World wraps with ghost markers at edges
- **Wrap Only** - World wraps without ghost markers
- **Stretched** - Horizontal stretch to see more area

#### Region Selector

![Region Selector](docs/images/12.region-selector.png)

Quick-jump to specific regions: World, North America, South America, Europe, Africa, Middle East, Asia, Oceania, or Antarctica.

#### Peer Popups

![Peer Popup](docs/images/13.peer-popup.png)

Click any peer dot on the map to see detailed information:
- **ID** - The peer's Bitcoin Core ID
- **Address** - The peer's network address
- **Network** - IPv4, IPv6, Tor, I2P, or CJDNS
- **Location** - City, region, country, continent
- **ISP** - Internet service provider (e.g., SpaceX Starlink)
- **Connection** - INB (inbound) or outbound type
- **Duration** - How long connected (e.g., 7d3h)

#### Private Networks (Antarctica)

![Antarctica](docs/images/14.antarctica.png)

Peers using private networks (Tor, I2P, CJDNS) don't have real geographic coordinates. These peers are displayed along the northern coast of Antarctica for visualization. The popup shows "(Location Private) - Shown in Antarctica for display only."

![Show/Hide Antarctica Toggle](docs/images/25.show.hide.penguin.png)

Toggle Antarctica dots on/off using the "Hide"/"Show" link in the map legend, right next to the penguin!

### Peer Table

![Peer Table](docs/images/24.peer.table.list.png)

The peer table shows all connected peers with live data. The header displays network counts with delta indicators (+1, -2) as peers connect and disconnect.

**Default columns:** ID, Net, Duration, Type, IP, Port, Node ver/name, Service, City, State/Region, Country, Continent, ISP, Ping, Sent, Received, In Addrman?

#### Network Filters

![Peer Table Filters](docs/images/15.peer-table-filters.png)

Filter peers by network type using the buttons above the table: All, IPv4, IPv6, Tor, I2P, or CJDNS. The active filter stays highlighted in its network color.

#### Column Configuration

![Column Config](docs/images/16.column-config.png)

Click the column button (≡) above the table to show/hide columns. You can also:
- Drag column headers to reorder
- Drag column edges to resize
- Click headers to sort (cycles: unsorted → ascending → descending)

### Sidebar

![Sidebar](docs/images/23.Nodeinfo.systeminfo.bitcoinprice.recentupdates.png)

The right sidebar displays live data in collapsible sections:

- **Node Info** - Peers, blockchain size, node type, indexed status, IBD status
- **System Information** - CPU, RAM, network traffic bars, MBCore DB status
- **Bitcoin Price** - Live price with green/red coloring based on direction
- **Recent Updates** - Scrollable list of peer connections/disconnections

Click section headers to collapse/expand. Use the settings dropdown to hide sections entirely.

### Blockchain Info

![Blockchain Modal](docs/images/19.blockchain-modal.png)

Click the **Blockchain** link in the sidebar to view detailed blockchain information. Hover over values for additional details.

### Mempool Info

![Mempool Modal](docs/images/18.mempool-modal.png)

Click the **Mempool** link in the sidebar to view detailed mempool statistics including pending transactions, fees, and policy settings.

### Peer Management

The dashboard provides tools to manage peer connections directly.

#### Connect to Peer

![Connect Peer](docs/images/20.connect-peer.png)

Click **Connect Peer** to manually connect to a peer. The modal shows examples for every protocol:

- **IPv4:** `192.168.1.10` (port 8333 used if omitted)
- **IPv6:** `[2001:db8::1]` (port 8333 used if omitted)
- **Tor:** `abc...xyz.onion` (port 8333 used if omitted)
- **CJDNS:** `[fc00::1]` (passed as-is)
- **I2P:** `abc...xyz.b32.i2p:0` (port :0 is required)

As you type an address, the modal automatically generates:
- A **bitcoin-cli addnode** command with your detected datadir and conf paths - copy and paste to add the peer permanently via terminal
- An **addnode=** line to paste directly into your bitcoin.conf file

#### Disconnect Peer

![Disconnect Peer](docs/images/22.disconnect.button.menu.png)

Click **Disconnect Peer** to open the management menu:

1. Enter the **Peer ID** (shown in the ID column of the peer table)
2. Optionally check **Ban IP for 24 hours**
3. Click **Disconnect**

**Note:** Banning only works for IPv4 and IPv6 peers. Tor, I2P, and CJDNS peers don't have bannable IP identities in Bitcoin Core.

#### Manage Bans

From the Disconnect Peer menu:

- **List Banned IPs** - View all banned IPs with expiry times and individual unban buttons
- **Clear All Bans** - Remove all IP bans at once

### Geo/IP Database (Dashboard)

![Geo/IP Database Modal](docs/images/21.geo.ip.database.modal.png)

Click **MBCore DB** in the sidebar to view database details:

- **Entries** - Number of cached peer locations
- **Size** - Database file size
- **Oldest** - Age of oldest entry
- **Location** - Path to the database file
- **Auto-lookup/Auto-update** - Current settings

Click **Update** to check for new entries from the shared database - no need to go back to the terminal menu.

### Dashboard Column Reference

The peer table displays detailed information about each connected peer. Click the column button (≡) above the table to customize visible columns.

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
| **Network text** | All columns use network-specific colors (IPv4 yellow, IPv6 red, Tor blue, I2P purple, CJDNS light purple) |
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

If you find this useful, consider a donation:

**Bitcoin:** `bc1qy63057zemrskq0n02avq9egce4cpuuenm5ztf5`

---

*Created by [@mbhillrn](https://github.com/mbhillrn/Bitcoin-Core-Peer-Map)*
