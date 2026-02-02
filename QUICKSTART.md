# MBCore-Dashboard Quick Start Guide

## What Is It?

**MBCore-Dashboard** is a web-based monitoring tool for Bitcoin Core nodes. It gives you:

- A real-time world map showing where your peers are located
- Peer connection statistics (IPv4, IPv6, Tor, I2P, CJDNS)
- Bitcoin price tracking
- Blockchain status
- CPU/memory usage
- Connection/disconnection history

## How It Works (Architecture)

```
┌─────────────────────────────────────────────────────────────────┐
│                        YOUR MACHINE                              │
│                                                                  │
│  ┌──────────────┐      RPC calls       ┌──────────────────────┐ │
│  │   bitcoind   │ ◄──────────────────► │  FastAPI Server      │ │
│  │ (Bitcoin Core)│   (bitcoin-cli)      │  (Python on :58333)  │ │
│  └──────────────┘                       └──────────┬───────────┘ │
│                                                    │             │
│                                         HTTP + SSE │             │
│                                                    ▼             │
│                                         ┌──────────────────────┐ │
│                                         │  Web Browser         │ │
│                                         │  (Leaflet.js map)    │ │
│                                         └──────────────────────┘ │
└─────────────────────────────────────────────────────────────────┘
```

1. You run `./da.sh` - This is the main entry point (bash script)
2. It auto-detects your Bitcoin Core installation
3. Launches a FastAPI Python server on port 58333
4. Displays the access URLs on screen
5. The browser shows the dashboard with live peer data via Server-Sent Events (SSE)

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

**If it won't connect from another device:** Your firewall may be blocking port 58333.

**Firewall Setup:**

The dashboard includes a **Firewall Helper** in the main menu (option `4`) that works with UFW to automatically configure the firewall for you.

**Using a different port?** Use `p) Port Settings` from the main menu to change the dashboard port first. The Firewall Helper will automatically use your configured port.

Or you can manually allow the port:
```bash
# Replace 58333 with your configured port if different
sudo ufw allow from 192.168.0.0/16 to any port 58333 proto tcp
```

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

## Quick Reference

| Situation | How to Access |
|-----------|---------------|
| Full GUI machine | Run `./da.sh` → browser auto-opens to `http://127.0.0.1:58333` |
| Headless + LAN access | Run `./da.sh` → note IP shown on screen → browse to `http://[that-ip]:58333` from any device on your network |
| Headless + SSH tunnel | `ssh -L 58333:127.0.0.1:58333 user@host` → run `./da.sh` → browse to `http://127.0.0.1:58333` on your local machine |

---

## Key Files & Ports

| Item | Location/Value |
|------|----------------|
| Main script | `./da.sh` |
| Web server | `web/server.py` (FastAPI + Uvicorn) |
| **Default Port** | **58333** (configurable via `p) Port Settings` in main menu) |
| Config | `data/config.conf` (auto-generated) |
| Peer cache DB | `data/peers.db` (SQLite) |
| Python venv | `./venv/` (auto-created) |

### Changing the Dashboard Port

If port 58333 is in use or you prefer a different port:

1. From the main menu, select `p) Port Settings`
2. Choose option `1) Change port`
3. Enter your preferred port number (1024-65535, high ports like 49152+ recommended)
4. The setting persists across reboots and updates

**Note:** If you change the port, remember to update your firewall rules and SSH tunnel commands to use the new port.

---

## Prerequisites

The script auto-checks for these and **offers to install missing dependencies automatically**:

- `bitcoind` running
- `bitcoin-cli` available
- `python3` (3.8+), `jq`, `curl`, `sqlite3`

The Python packages (fastapi, uvicorn, etc.) are installed automatically into a virtual environment.

**Ubuntu/Debian users:** If `python3-venv` isn't installed, the script will detect this and offer to install it for you. Just press `y` when prompted.

**First run taking a while?** The script needs to set up a Python virtual environment and install packages. This only happens once - subsequent runs are much faster.

For more details on what happens during first run, see the [First Run](README.md#first-run) section in the README.

---

## Troubleshooting

### Dashboard won't load from another computer
- Use the **Firewall Helper** from the main menu (`f` key) for easy setup
- Or manually ensure your firewall allows port 58333

### Dashboard won't load at all
- Close any browser tabs from previous dashboard sessions
- Check if port 58333 is in use: `ss -tlnp | grep 58333`

### Bitcoin Core not detected
- Make sure `bitcoind` is running
- Try the manual settings option from the main menu

---

For more details, see the full [README.md](README.md).
