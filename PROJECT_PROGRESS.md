# MBTC-DASH Project Progress

## Overview
Bitcoin Core monitoring and management GUI - terminal-based dashboard.

## Completed Features

### v0.1.0 - Core Detection System
- **Bitcoin Core Detection** (`da.sh`): Auto-detects bitcoind installation
  - Checks running processes first (extracts -datadir, -conf from args)
  - Interrogates systemd services if applicable
  - Falls back to common install locations
  - Full system search option with warnings
  - Manual entry at every step with 'b' to go back
  - Validates via RPC connection test
  - Caches successful config for fast subsequent runs
  - Graceful Ctrl+C (first warns, second force quits)

- **Prerequisites Checker** (`lib/prereqs.sh`): Validates required tools
  - jq, curl, sqlite3 (required)
  - ss, bc (optional)
  - Offers to install missing packages

- **UI Library** (`lib/ui.sh`, `lib/colors.sh`): Blue theme
  - Color-coded output (blue primary, green success, red errors)
  - Progress spinners and bars
  - Bordered sections and tables
  - Pretty box drawing characters

### v0.1.1 - Peer List with Geo-Location
- **Peer List Display** (`scripts/peerlist.sh`)
  - Fetches peers via `bitcoin-cli getpeerinfo`
  - Geo-locates IPv4/IPv6 using ip-api.com
  - Rate limited (1.5s delay, 45 req/min)
  - Progress bar during geo lookups
  - Live refresh every 10 seconds
  - Press 'q' to quit gracefully

- **Database Caching** (`lib/database.sh`)
  - SQLite database for peer geo data
  - Geo status: GEO_OK, GEO_PRIVATE (tor/i2p/cjdns), GEO_UNAVAILABLE
  - Smart retry: 1d, 3d, 7d, then 7d forever
  - Tracks first_seen, last_seen, connection_count

- **Environment Variables** (MBTC_ prefix)
  - MBTC_CLI_PATH, MBTC_DATADIR, MBTC_CONF
  - MBTC_NETWORK, MBTC_RPC_HOST, MBTC_RPC_PORT
  - MBTC_COOKIE_PATH, MBTC_RPC_USER

## Planned Features
- [ ] Peer map visualization (web-based)
- [ ] Mempool statistics graphs
- [ ] Blockchain info display
- [ ] System metrics (CPU, RAM, disk)
- [ ] Wallet balance + price conversion
- [ ] Security checks for exposed ports

---
*Last updated: Peer list with geo-location caching*
