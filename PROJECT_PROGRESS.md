# MBTC-DASH Project Progress

## Overview
Bitcoin Core monitoring and management dashboard - terminal-based with Python Rich for smooth UI.

## Architecture

```
da.sh                    # Main entry - shows menu, orchestrates everything
scripts/
  detect.sh              # Bitcoin Core detection (datadir, conf, RPC)
  peerlist.py            # Peer list with Rich live tables
lib/
  colors.sh              # Color definitions and theme
  config.sh              # Shared config loading (MBTC_* variables)
  database.sh            # SQLite functions for peer caching
  prereqs.sh             # Prerequisites checking
  ui.sh                  # UI helpers (spinners, boxes, prompts)
```

## Completed Features

### v0.1.0 - Core Detection System
- **Bitcoin Core Detection** (`scripts/detect.sh`): Auto-detects bitcoind installation
  - Checks running processes first (extracts -datadir, -conf from args)
  - Interrogates systemd services if applicable
  - Falls back to common install locations
  - Full system search option with warnings
  - Manual entry at every step with 'b' to go back
  - Validates via RPC connection test
  - Caches successful config for fast subsequent runs
  - Graceful Ctrl+C (first warns, second force quits)

- **Prerequisites Checker** (`lib/prereqs.sh`): Validates required tools
  - jq, curl, sqlite3, python3 (required)
  - ss, bc (optional)
  - Python packages: rich, requests
  - Offers to install missing packages

- **UI Library** (`lib/ui.sh`, `lib/colors.sh`): Blue theme
  - Color-coded output (blue primary, green success, red errors)
  - Progress spinners and bars
  - Bordered sections and tables
  - Pretty box drawing characters

### v0.2.0 - Python Rich Integration + Menu System
- **Main Dashboard** (`da.sh`): Central orchestrator
  - Banner display with version
  - Prerequisites check on startup
  - Auto-runs detection if no config found
  - Main menu with numbered options
  - Shows current configuration status
  - Quick RPC health check

- **Peer List with Rich** (`scripts/peerlist.py`): Smooth live updates
  - Python Rich for flicker-free table updates
  - Geo-locates IPv4/IPv6 using ip-api.com
  - Rate limited (1.5s delay, 45 req/min)
  - Progress indicator during geo lookups
  - Live refresh every 10 seconds
  - **Recently Connected/Disconnected tracking** (last 30 seconds)
  - New peers highlighted in green with + prefix
  - Press 'q' to quit gracefully

- **Shared Configuration** (`lib/config.sh`)
  - Single config file used by all scripts
  - Config at `~/.config/mbtc-dash/config.conf`
  - Database at `~/.local/share/mbtc-dash/peers.db`
  - Functions: load_config, save_config, get_cli_command, test_rpc

- **Database Caching** (`lib/database.sh`)
  - SQLite database for peer geo data
  - Geo status: GEO_OK, GEO_PRIVATE (tor/i2p/cjdns), GEO_UNAVAILABLE
  - Smart retry: 1d, 3d, 7d, then 7d forever
  - Tracks first_seen, last_seen, connection_count

- **Environment Variables** (MBTC_ prefix)
  - MBTC_CLI_PATH, MBTC_DATADIR, MBTC_CONF
  - MBTC_NETWORK, MBTC_RPC_HOST, MBTC_RPC_PORT
  - MBTC_COOKIE_PATH, MBTC_RPC_USER
  - MBTC_CONFIGURED (flag for config loaded)

## Planned Features
- [ ] Peer map visualization (web-based)
- [ ] Blockchain info display (height, difficulty, sync status)
- [ ] Mempool statistics graphs
- [ ] System metrics (CPU, RAM, disk)
- [ ] Wallet balance + price conversion
- [ ] Security checks for exposed ports

---
*Last updated: Python Rich integration, menu system, peer connection tracking*
