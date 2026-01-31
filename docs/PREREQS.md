# MBTC-DASH - Prerequisites

## Required Tools

### Core Requirements
| Tool | Purpose | Install Command (Debian/Ubuntu) |
|------|---------|--------------------------------|
| `bash` | Shell (v4.0+) | Pre-installed |
| `jq` | JSON parsing for RPC responses | `sudo apt install jq` |
| `curl` | HTTP requests (RPC, APIs) | `sudo apt install curl` |
| `sqlite3` | Database for caching peer geo-data | `sudo apt install sqlite3` |

### Bitcoin Core
| Tool | Purpose | Notes |
|------|---------|-------|
| `bitcoin-cli` | RPC interface to bitcoind | Part of Bitcoin Core installation |
| `bitcoind` | Bitcoin daemon | Must be running for full functionality |

### Optional (for enhanced features)
| Tool | Purpose | Install Command |
|------|---------|-----------------|
| `ss` or `netstat` | Network connection info | `sudo apt install iproute2` |
| `bc` | Math calculations | `sudo apt install bc` |

## Detection Notes
- The program will auto-detect missing prerequisites on startup
- You will be prompted to install any missing required tools
- Optional tools enhance functionality but are not required

## Database
- Peer geo-location data is cached in SQLite at `~/.local/share/mbtc-dash/peers.db`
- Geo data for private networks (Tor/I2P/CJDNS) is marked as "PRIVATE LOCATION"
- Failed lookups retry after: 1 day, 3 days, 7 days, then every 7 days

## API Rate Limits
- Geo-location uses ip-api.com (free tier)
- Rate limited to 45 requests/minute
- Script uses 1.5s delay between API calls to stay under limit

---
*This file is auto-updated as new features are added*
