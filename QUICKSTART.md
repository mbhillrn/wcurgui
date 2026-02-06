# MBCore Dashboard - Quick Start Guide

## Install & Run

```bash
git clone https://github.com/mbhillrn/Bitcoin-Core-Peer-Map.git
cd Bitcoin-Core-Peer-Map
./da.sh
```

On first run, the script walks you through setup. Press `y` at each prompt:

![Prerequisites and venv setup](docs/images/2.venv-prompt.png)

![Package installation](docs/images/3.install-success.png)

It auto-detects your Bitcoin Core installation. Press `y` to accept:

![Bitcoin Core detection](docs/images/4.detection.png)

Choose your Geo/IP database preference (Option 1 recommended):

![GeoIP Database Setup](docs/images/4c.GeoIP.First.Run.png)

![GeoIP Database Download](docs/images/4d.GeoIP.dbdl.png)

You'll land at the main menu. Press `1` to launch the dashboard:

![Main Menu](docs/images/5.main-menu.png)

The dashboard starts and shows your access URLs:

![Dashboard Launch](docs/images/10.dashboard-launch.png)

Open the URL in your browser:

![MBCore Dashboard](docs/images/1.Full.Front.Dash.png)

That's it. The rest of this guide covers how to access the dashboard in different setups.

---

## How It Works

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

`./da.sh` detects your Bitcoin Core, launches a FastAPI server on port 58333, and serves the dashboard to your browser with live updates via Server-Sent Events (SSE).

---

## How To Access The Dashboard

### Scenario 1: GUI Machine (has a desktop & browser)

Just run `./da.sh` — the browser opens automatically to `http://127.0.0.1:58333`. Done.

---

### Scenario 2: Headless Machine (no desktop/browser)

You need to access the dashboard from another device. Two options:

#### Option A: Direct LAN Access (recommended)

1. Start the dashboard on the headless machine (via SSH or directly):
   ```bash
   ./da.sh
   ```

2. Select `1) Enter MBCore Dashboard` from the main menu

3. The launch screen shows your machine's IP:

   ![Dashboard Launch](docs/images/10.dashboard-launch.png)

4. From any other device on your network, open a browser to:
   ```
   http://[your-machines-ip]:58333
   ```
   (The exact IP is displayed on the launch screen.)

**Won't connect?** Your firewall is probably blocking port 58333. The dashboard has a built-in **Firewall Helper** — select option `3` from the main menu:

![Firewall Helper](docs/images/6.firewall-helper.png)

Or manually:
```bash
sudo ufw allow from 192.168.0.0/16 to any port 58333 proto tcp
```

---

#### Option B: SSH Tunnel

No firewall changes needed with this method.

1. From your **local computer** (the one with a browser), SSH in with a tunnel:
   ```bash
   ssh -L 58333:127.0.0.1:58333 user@headless-machine-ip
   ```

2. In that SSH session, start the dashboard:
   ```bash
   ./da.sh
   ```

3. Select `1) Enter MBCore Dashboard` from the main menu

4. On your **local computer's browser**, go to:
   ```
   http://127.0.0.1:58333
   ```

The tunnel forwards your local port to the remote machine.

---

## Quick Reference

| Situation | How to Access |
|-----------|---------------|
| GUI machine | Run `./da.sh` → browser auto-opens to `http://127.0.0.1:58333` |
| Headless + LAN | Run `./da.sh` → browse to `http://[ip-shown-on-screen]:58333` from any device |
| Headless + SSH tunnel | `ssh -L 58333:127.0.0.1:58333 user@host` → run `./da.sh` → browse to `http://127.0.0.1:58333` locally |

---

## Key Files & Ports

| Item | Location/Value |
|------|----------------|
| Main script | `./da.sh` |
| Web server | `web/MBCoreServer.py` (FastAPI + Uvicorn) |
| **Default Port** | **58333** (configurable via `p) Port Settings` in main menu) |
| Config | `data/config.conf` (auto-generated) |
| Geo/IP cache DB | `data/geo.db` (SQLite) |
| Python venv | `./venv/` (auto-created) |

### Changing the Dashboard Port

From the main menu, select `p) Port Settings`:

![Port Settings](docs/images/9.port-settings.png)

Enter your preferred port (1024-65535). The setting persists across reboots and updates.

**Note:** If you change the port, update your firewall rules and SSH tunnel commands to match.

---

## Troubleshooting

### Dashboard won't load from another computer
- Use the **Firewall Helper** from the main menu (option `3`) for easy setup
- Or manually ensure your firewall allows port 58333

### Dashboard won't load at all
- Close any browser tabs from previous dashboard sessions
- Check if port 58333 is in use: `ss -tlnp | grep 58333`

### Bitcoin Core not detected
- Make sure `bitcoind` is running
- Try the manual settings option from the main menu

---

For full feature documentation, see the [README](README.md).
