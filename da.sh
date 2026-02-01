#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════
#  MBTC-DASH - Bitcoin Core Dashboard
#  A monitoring and management interface for Bitcoin Core
# ═══════════════════════════════════════════════════════════════════════════════

set -e

# Get the directory where this script lives
MBTC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export MBTC_DIR

# Source libraries
source "$MBTC_DIR/lib/ui.sh"
source "$MBTC_DIR/lib/prereqs.sh"
source "$MBTC_DIR/lib/config.sh"

# Read version from VERSION file
VERSION=$(cat "$MBTC_DIR/VERSION" 2>/dev/null || echo "0.0.0")
GITHUB_REPO="mbhillrn/MBCore-Dashboard"
GITHUB_VERSION_URL="https://raw.githubusercontent.com/$GITHUB_REPO/main/VERSION"
UPDATE_AVAILABLE=0
LATEST_VERSION=""

# Venv paths
VENV_DIR="$MBTC_DIR/venv"
VENV_PYTHON="$VENV_DIR/bin/python3"

# ═══════════════════════════════════════════════════════════════════════════════
# CTRL+C HANDLING
# ═══════════════════════════════════════════════════════════════════════════════

CTRL_C_COUNT=0
CTRL_C_TIME=0

handle_ctrl_c() {
    local now
    now=$(date +%s)

    if (( now - CTRL_C_TIME > 2 )); then
        CTRL_C_COUNT=0
    fi

    CTRL_C_TIME=$now
    ((CTRL_C_COUNT++))

    if [[ $CTRL_C_COUNT -eq 1 ]]; then
        echo ""
        msg_warn "Press Ctrl+C again to quit"
    else
        echo ""
        msg_info "Goodbye!"
        cursor_show
        exit 0
    fi
}

trap handle_ctrl_c SIGINT

# Cleanup temp files on exit
cleanup_temp() {
    rm -f "/tmp/mbtc_update_check_$$"
}
trap cleanup_temp EXIT

# ═══════════════════════════════════════════════════════════════════════════════
# BANNER
# ═══════════════════════════════════════════════════════════════════════════════

show_banner() {
    clear
    echo ""
    echo -e "${T_PRIMARY}"
    cat << 'EOF'
███╗   ███╗██████╗  ██████╗ ██████╗ ██████╗ ███████╗
████╗ ████║██╔══██╗██╔════╝██╔═══██╗██╔══██╗██╔════╝
██╔████╔██║██████╔╝██║     ██║   ██║██████╔╝█████╗
██║╚██╔╝██║██╔══██╗██║     ██║   ██║██╔══██╗██╔══╝
██║ ╚═╝ ██║██████╔╝╚██████╗╚██████╔╝██║  ██║███████╗
╚═╝     ╚═╝╚═════╝  ╚═════╝ ╚═════╝ ╚═╝  ╚═╝╚══════╝
EOF
    echo -e "${RST}"
    echo -e "  ${T_WHITE}Dashboard${RST}  ${T_DIM}v${VERSION}${RST} ${T_WHITE}(Bitcoin Core peer info/map/tools)${RST}"
    echo -e "  ────────────────────────────────────────────────────"
    echo -e "  ${T_DIM}Created by mbhillrn${RST}"
    echo -e "  ${T_DIM}MIT License - Free to use, modify, and distribute${RST}"
    echo -e "  ${T_DIM}Support (btc): bc1qy63057zemrskq0n02avq9egce4cpuuenm5ztf5${RST}"
    echo ""
}

# ═══════════════════════════════════════════════════════════════════════════════
# STATUS DISPLAY
# ═══════════════════════════════════════════════════════════════════════════════

show_status() {
    echo ""
    echo -e "${T_SECONDARY}${BOLD}Current Configuration${RST}"
    echo ""

    if [[ "$MBTC_CONFIGURED" -eq 1 ]]; then
        print_kv "Bitcoin CLI" "${MBTC_CLI_PATH:-not set}" 16
        print_kv "Data Directory" "${MBTC_DATADIR:-not set}" 16
        print_kv "Network" "${MBTC_NETWORK:-main}" 16
        print_kv "RPC" "${MBTC_RPC_HOST:-127.0.0.1}:${MBTC_RPC_PORT:-8332}" 16

        # Show auth method
        if [[ -n "$MBTC_COOKIE_PATH" && -f "$MBTC_COOKIE_PATH" ]]; then
            print_kv "Auth" "Cookie" 16
        elif [[ -n "$MBTC_RPC_USER" ]]; then
            print_kv "Auth" "RPC User ($MBTC_RPC_USER)" 16
        else
            print_kv "Auth" "Default" 16
        fi

        # Quick RPC test
        if test_rpc 2>/dev/null; then
            echo ""
            msg_ok "Bitcoin Core is running and responding"
        else
            echo ""
            msg_warn "Bitcoin Core not responding (is bitcoind running?)"
        fi
    else
        msg_warn "Not configured - run detection first"
    fi
    echo ""
}

# ═══════════════════════════════════════════════════════════════════════════════
# MAIN MENU
# ═══════════════════════════════════════════════════════════════════════════════

show_menu() {
    echo ""
    echo -e "${T_SECONDARY}${BOLD}Main Menu${RST}"
    echo ""
    echo -e "  ${T_INFO}1)${RST} Enter MBCore Web Dashboard"
    echo -e "     ${T_DIM}- Bitcoin Core peer info/map/tools${RST}"
    echo -e "     ${T_DIM}- Instructions on access viewable on the next page!${RST}"
    echo -e "  ${T_INFO}2)${RST} Reset MBCore Config"
    echo -e "     ${T_DIM}- Clear saved configuration${RST}"
    echo -e "  ${T_INFO}3)${RST} Reset MBCore Database"
    echo -e "     ${T_DIM}- Clear peer geo-location cache${RST}"
    echo -e "  ${T_INFO}4)${RST} Firewall Helper"
    echo -e "     ${T_DIM}- Configure firewall for network access${RST}"
    echo ""
    echo -e "  ${T_DIM}d)${RST} Rerun Detection    ${T_DIM}- Re-detect Bitcoin Core settings${RST}"
    echo -e "  ${T_DIM}m)${RST} Manual Settings    ${T_DIM}- Manually enter Bitcoin Core settings${RST}"
    if [[ "$UPDATE_AVAILABLE" -eq 1 ]]; then
        echo -e "  ${T_WARN}u)${RST} Update             ${T_DIM}- Update to v${LATEST_VERSION}${RST}"
    fi
    echo ""
    echo -e "  ${T_ERROR}q)${RST} Quit"
    echo ""
}

run_web_dashboard() {
    if [[ "$MBTC_CONFIGURED" -ne 1 ]]; then
        msg_err "Bitcoin Core not configured. Run detection first."
        echo ""
        echo -en "${T_DIM}Press Enter to continue...${RST}"
        read -r
        return
    fi

    # Check if web packages are available
    if ! is_web_available; then
        msg_err "Web dashboard packages not installed"
        msg_info "Please run the prerequisites check to install web packages"
        echo ""
        echo -en "${T_DIM}Press Enter to continue...${RST}"
        read -r
        return
    fi

    # Run web server using venv
    clear
    "$VENV_PYTHON" "$MBTC_DIR/web/server.py"
}

run_detection() {
    "$MBTC_DIR/scripts/detect.sh"
    # Reload config after detection
    load_config
}

run_manual_config() {
    clear
    show_banner

    echo ""
    echo -e "${T_SECONDARY}${BOLD}Manual Configuration${RST}"
    echo ""
    echo -e "${T_DIM}Enter the paths to your Bitcoin Core configuration.${RST}"
    echo -e "${T_DIM}(After entering these, the rest will be auto-detected)${RST}"
    echo -e "${T_DIM}(You may enter * to go back to detection, or just press Enter to use the example path)${RST}"
    echo ""

    # Try to detect a default conf path
    local default_conf=""
    if [[ -f "/srv/bitcoin/bitcoin.conf" ]]; then
        default_conf="/srv/bitcoin/bitcoin.conf"
    elif [[ -f "$HOME/.bitcoin/bitcoin.conf" ]]; then
        default_conf="$HOME/.bitcoin/bitcoin.conf"
    elif [[ -f "/etc/bitcoin/bitcoin.conf" ]]; then
        default_conf="/etc/bitcoin/bitcoin.conf"
    fi

    # Ask for bitcoin.conf path
    local conf_path=""
    while true; do
        if [[ -n "$default_conf" ]]; then
            echo -en "${T_INFO}Location of bitcoin.conf${RST} ${T_DIM}(ex: ${default_conf}):${RST} "
        else
            echo -en "${T_INFO}Location of bitcoin.conf:${RST} "
        fi
        read -r conf_path

        # Handle * to go back
        if [[ "$conf_path" == "*" ]]; then
            run_detection
            return
        fi

        # Use default if just Enter pressed
        if [[ -z "$conf_path" && -n "$default_conf" ]]; then
            conf_path="$default_conf"
        fi

        conf_path="${conf_path/#\~/$HOME}"

        if [[ -z "$conf_path" ]]; then
            msg_err "Please enter a path"
        elif [[ -f "$conf_path" ]]; then
            msg_ok "Found: $conf_path"
            break
        else
            msg_err "File not found: $conf_path"
        fi
    done

    # Ask for datadir (optional if we can find it)
    local datadir=""
    local conf_dir
    conf_dir=$(dirname "$conf_path")

    if [[ -d "$conf_dir/blocks" ]] || [[ -f "$conf_dir/.cookie" ]]; then
        echo ""
        echo -e "${T_INFO}Detected datadir:${RST} $conf_dir"
        if prompt_yn "Use this as data directory?"; then
            datadir="$conf_dir"
        fi
    fi

    if [[ -z "$datadir" ]]; then
        echo ""
        # Use conf_dir as the example/default
        local default_datadir="$conf_dir"

        while true; do
            echo -en "${T_INFO}Location of Bitcoin Core data directory${RST} ${T_DIM}(ex: ${default_datadir}):${RST} "
            read -r datadir

            # Handle * to go back
            if [[ "$datadir" == "*" ]]; then
                run_detection
                return
            fi

            # Use default if just Enter pressed
            if [[ -z "$datadir" ]]; then
                datadir="$default_datadir"
            fi

            datadir="${datadir/#\~/$HOME}"

            if [[ -d "$datadir" ]]; then
                msg_ok "Found: $datadir"
                break
            else
                msg_err "Directory not found: $datadir"
            fi
        done
    fi

    # Set the manual values
    MBTC_CONF="$conf_path"
    MBTC_DATADIR="$datadir"

    # Now run detection to fill in the rest (CLI, network, auth, etc.)
    echo ""
    echo -e "${T_SECONDARY}${BOLD}Auto-detecting remaining settings...${RST}"

    # Source detection script functions
    source "$MBTC_DIR/scripts/detect.sh"

    # Detect CLI
    if detect_bitcoin_cli; then
        msg_ok "Found bitcoin-cli: $MBTC_CLI_PATH"
    fi

    # Parse config file for network settings
    if [[ -f "$MBTC_CONF" ]]; then
        parse_conf_file "$MBTC_CONF"
    fi

    # Find cookie
    find_cookie
    if [[ -n "$MBTC_COOKIE_PATH" && -f "$MBTC_COOKIE_PATH" ]]; then
        msg_ok "Found cookie auth: $MBTC_COOKIE_PATH"
    fi

    # Test RPC
    echo ""
    if test_rpc; then
        msg_ok "RPC connection successful!"
    else
        msg_warn "RPC connection failed - bitcoind may not be running"
    fi

    # Save config
    save_config
    msg_ok "Configuration saved!"

    echo ""
    echo -en "${T_DIM}Press Enter to continue...${RST}"
    read -r
}

reset_config() {
    echo ""
    if prompt_yn "Are you sure you want to clear saved configuration?"; then
        clear_config
        msg_ok "Configuration cleared"
    else
        msg_info "Cancelled"
    fi
    echo ""
    echo -en "${T_DIM}Press Enter to continue...${RST}"
    read -r
}

reset_database() {
    echo ""
    local db_path="$MBTC_DIR/data/peers.db"
    if [[ -f "$db_path" ]]; then
        if prompt_yn "Are you sure you want to clear the peer geo-location cache?"; then
            rm -f "$db_path"
            msg_ok "Database cleared"
        else
            msg_info "Cancelled"
        fi
    else
        msg_info "No database found to clear"
    fi
    echo ""
    echo -en "${T_DIM}Press Enter to continue...${RST}"
    read -r
}

# ═══════════════════════════════════════════════════════════════════════════════
# FIREWALL HELPER
# ═══════════════════════════════════════════════════════════════════════════════

get_local_network_info() {
    # Get primary local IP and subnet
    local ip_info
    ip_info=$(ip -4 addr show 2>/dev/null | grep -oP 'inet \K[0-9./]+' | grep -v '^127\.' | head -1)

    if [[ -n "$ip_info" ]]; then
        LOCAL_IP="${ip_info%/*}"
        local prefix="${ip_info#*/}"

        # Calculate network address from IP and prefix
        if [[ "$prefix" =~ ^[0-9]+$ ]] && [[ "$prefix" -ge 8 ]] && [[ "$prefix" -le 30 ]]; then
            IFS='.' read -ra ip_parts <<< "$LOCAL_IP"
            local mask=$(( 0xFFFFFFFF << (32 - prefix) ))
            local net_int=$(( (ip_parts[0] << 24) | (ip_parts[1] << 16) | (ip_parts[2] << 8) | ip_parts[3] ))
            net_int=$(( net_int & mask ))
            LOCAL_SUBNET="$(( (net_int >> 24) & 0xFF )).$(( (net_int >> 16) & 0xFF )).$(( (net_int >> 8) & 0xFF )).$(( net_int & 0xFF ))/$prefix"
        else
            # Fallback: assume /24 for common home networks
            IFS='.' read -ra ip_parts <<< "$LOCAL_IP"
            LOCAL_SUBNET="${ip_parts[0]}.${ip_parts[1]}.${ip_parts[2]}.0/24"
        fi
    else
        LOCAL_IP="127.0.0.1"
        LOCAL_SUBNET="192.168.0.0/16"
    fi
}

firewall_helper() {
    clear
    show_banner

    echo ""
    echo -e "${T_SECONDARY}${BOLD}Firewall Helper${RST}"
    echo ""
    echo -e "${T_DIM}This tool helps you configure your firewall to allow network access${RST}"
    echo -e "${T_DIM}to the MBCore Dashboard from other computers on your local network.${RST}"
    echo ""

    # Get network info
    get_local_network_info
    local port=58333

    echo -e "${T_INFO}Detected Network Info:${RST}"
    echo -e "  Your IP:        ${T_SUCCESS}$LOCAL_IP${RST}"
    echo -e "  Your Subnet:    ${T_SUCCESS}$LOCAL_SUBNET${RST}"
    echo -e "  Dashboard Port: ${T_SUCCESS}$port${RST}"
    echo ""

    # Check for UFW
    if command -v ufw &>/dev/null; then
        local ufw_status
        ufw_status=$(sudo ufw status 2>/dev/null)
        local ufw_status_line
        ufw_status_line=$(echo "$ufw_status" | head -1)

        if [[ "$ufw_status_line" == *"active"* ]]; then
            echo -e "${T_SUCCESS}✓${RST} UFW firewall detected and ${T_SUCCESS}active${RST}"
            echo ""

            # Check if port 58333 is already allowed
            if echo "$ufw_status" | grep -qE "$port/(tcp|udp)|$port\s+ALLOW"; then
                echo -e "${T_SUCCESS}✓${RST} Port $port is ${T_SUCCESS}already allowed${RST} in your firewall!"
                echo ""
                echo -e "${T_DIM}Current rules for port $port:${RST}"
                echo "$ufw_status" | grep -E "$port" | while read -r line; do
                    echo -e "  ${T_DIM}$line${RST}"
                done
                echo ""
                echo -e "${T_INFO}You're all set! The dashboard should be accessible from your network.${RST}"
                echo -e "  ${T_SUCCESS}http://$LOCAL_IP:$port${RST}"
                echo ""
                echo -e "${T_DIM}To remove the rule later, run:${RST}"
                echo -e "  ${T_DIM}sudo ufw delete allow from $LOCAL_SUBNET to any port $port proto tcp${RST}"
                echo -e "  ${T_DIM}  - or -${RST}"
                echo -e "  ${T_DIM}sudo ufw delete allow $port/tcp${RST}"
            else
                echo -e "${T_WARN}⚠${RST} Port $port is ${T_WARN}not yet allowed${RST} in your firewall"
                echo ""
                echo -e "${T_INFO}I can add a firewall rule to allow dashboard access.${RST}"
                echo ""
                echo -e "  ${T_DIM}This command will be run:${RST}"
                echo -e "  ${T_WARN}sudo ufw allow from $LOCAL_SUBNET to any port $port proto tcp${RST}"
                echo ""
                echo -e "${T_DIM}This allows computers on your local network ($LOCAL_SUBNET) to connect.${RST}"
                echo ""
                echo -e "${T_DIM}To remove later, run:${RST}"
                echo -e "  ${T_DIM}sudo ufw delete allow from $LOCAL_SUBNET to any port $port proto tcp${RST}"
                echo ""

                if prompt_yn "Add this firewall rule now?"; then
                    echo ""
                    if sudo ufw allow from "$LOCAL_SUBNET" to any port "$port" proto tcp; then
                        echo ""
                        msg_ok "Firewall rule added successfully!"
                        echo ""
                        echo -e "${T_INFO}You can now access the dashboard from other computers at:${RST}"
                        echo -e "  ${T_SUCCESS}http://$LOCAL_IP:$port${RST}"
                    else
                        echo ""
                        msg_err "Failed to add firewall rule"
                    fi
                else
                    msg_info "Cancelled"
                fi
            fi

        elif [[ "$ufw_status_line" == *"inactive"* ]]; then
            echo -e "${T_WARN}⚠${RST} UFW firewall detected but ${T_WARN}inactive${RST}"
            echo ""
            echo -e "${T_DIM}Since UFW is not active, you likely don't need to configure it.${RST}"
            echo -e "${T_DIM}The dashboard should be accessible from your network already.${RST}"
            echo ""
            echo -e "${T_INFO}If you want to enable UFW later, here's the command to allow the dashboard:${RST}"
            echo -e "  ${T_WARN}sudo ufw allow from $LOCAL_SUBNET to any port $port proto tcp${RST}"
        else
            echo -e "${T_WARN}⚠${RST} UFW detected but status unclear"
            echo ""
            echo -e "${T_DIM}Run 'sudo ufw status' to check your firewall status.${RST}"
            echo ""
            echo -e "${T_INFO}If you need to allow dashboard access, run:${RST}"
            echo -e "  ${T_WARN}sudo ufw allow from $LOCAL_SUBNET to any port $port proto tcp${RST}"
        fi
    else
        # UFW not found
        echo -e "${T_INFO}ℹ${RST} Common firewall (UFW) not detected"
        echo ""
        echo -e "${T_DIM}You may not have a firewall enabled, so the dashboard should work fine.${RST}"
        echo ""
        echo -e "${T_DIM}If you know you have a firewall, please open port ${T_WARN}$port/tcp${T_DIM} manually.${RST}"
        echo ""
        echo -e "${T_INFO}If you install UFW later, use this command:${RST}"
        echo -e "  ${T_WARN}sudo ufw allow from $LOCAL_SUBNET to any port $port proto tcp${RST}"
    fi

    echo ""
    echo -en "${T_DIM}Press Enter to continue...${RST}"
    read -r
}

# ═══════════════════════════════════════════════════════════════════════════════
# VERSION CHECK AND AUTO-UPDATE
# ═══════════════════════════════════════════════════════════════════════════════

UPDATE_CHECK_FILE="/tmp/mbtc_update_check_$$"

check_for_updates() {
    # Only check if curl is available and we have internet
    if ! command -v curl &>/dev/null; then
        return 1
    fi

    # Fetch the VERSION file from GitHub (with 3 second timeout)
    local remote_version
    remote_version=$(curl -s --connect-timeout 3 "$GITHUB_VERSION_URL" 2>/dev/null | tr -d '[:space:]')

    if [[ -z "$remote_version" ]]; then
        return 1
    fi

    # Compare versions (simple string comparison works for semver)
    if [[ "$remote_version" != "$VERSION" ]]; then
        # Check if remote is newer (compare major.minor.patch)
        local IFS='.'
        read -ra local_parts <<< "$VERSION"
        read -ra remote_parts <<< "$remote_version"

        for i in 0 1 2; do
            local lp=${local_parts[$i]:-0}
            local rp=${remote_parts[$i]:-0}
            if (( rp > lp )); then
                # Write to temp file so parent can read it (subshell can't set parent vars)
                echo "$remote_version" > "$UPDATE_CHECK_FILE"
                return 0
            elif (( rp < lp )); then
                return 0
            fi
        done
    fi

    return 0
}

# Read update check results from background process
read_update_check() {
    if [[ -f "$UPDATE_CHECK_FILE" ]]; then
        LATEST_VERSION=$(cat "$UPDATE_CHECK_FILE")
        UPDATE_AVAILABLE=1
        rm -f "$UPDATE_CHECK_FILE"
    fi
}

show_update_banner() {
    if [[ "$UPDATE_AVAILABLE" -eq 1 ]]; then
        echo ""
        echo -e "  ${T_WARN}⚡ Update available!${RST} ${T_DIM}v${VERSION} → v${LATEST_VERSION}${RST}"
        echo -e "  ${T_DIM}Run option 'u' from the menu to update${RST}"
    fi
}

run_update() {
    echo ""
    echo -e "${T_SECONDARY}${BOLD}Updating MBCore Dashboard...${RST}"
    echo ""

    # Check if we're in a git repo
    if [[ ! -d "$MBTC_DIR/.git" ]]; then
        msg_err "Not a git repository. Please update manually:"
        echo ""
        echo -e "  ${T_DIM}cd $MBTC_DIR${RST}"
        echo -e "  ${T_DIM}git pull origin main${RST}"
        echo ""
        echo -en "${T_DIM}Press Enter to continue...${RST}"
        read -r
        return 1
    fi

    # Check for uncommitted changes
    cd "$MBTC_DIR" || return 1

    if ! git diff-index --quiet HEAD -- 2>/dev/null; then
        msg_warn "You have uncommitted changes. Stashing them..."
        git stash
    fi

    # Pull the latest changes
    echo -e "${T_INFO}Pulling latest changes from GitHub...${RST}"
    if git pull origin main; then
        msg_ok "Update successful!"
        echo ""
        msg_info "Automatically restarting with new version..."
        sleep 1
        # Restart the script with the new version using absolute path
        exec "$MBTC_DIR/da.sh"
    else
        msg_err "Update failed. Please try manually:"
        echo ""
        echo -e "  ${T_DIM}cd $MBTC_DIR${RST}"
        echo -e "  ${T_DIM}git pull origin main${RST}"
        echo ""
        echo -en "${T_DIM}Press Enter to continue...${RST}"
        read -r
        return 1
    fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# MAIN
# ═══════════════════════════════════════════════════════════════════════════════

main() {
    show_banner

    # Check for updates in the background (non-blocking)
    check_for_updates &
    local update_pid=$!

    # Check prerequisites
    if ! run_prereq_check; then
        msg_err "Cannot continue without required prerequisites"
        echo ""
        echo -en "${T_DIM}Press Enter to exit...${RST}"
        read -r
        exit 1
    fi

    # Check if config exists
    if [[ "$MBTC_CONFIGURED" -ne 1 ]]; then
        echo ""
        msg_info "No configuration found. Running Bitcoin Core detection..."
        sleep 1
        run_detection
    else
        # Config exists - ask if it's correct on first run
        show_status

        echo ""
        echo -e "${T_WARN}?${RST} These are the detected settings. Are they correct?"
        echo ""
        echo -e "  ${T_INFO}1)${RST} Yes, continue to main menu"
        echo -e "  ${T_INFO}2)${RST} No, run detection again"
        echo -e "  ${T_INFO}3)${RST} No, enter settings manually"
        echo -e "  ${T_ERROR}q)${RST} Quit"
        echo ""

        echo -en "${T_DIM}Choice [1-3/q]:${RST} "
        read -r startup_choice

        case "$startup_choice" in
            1)
                save_config
                msg_ok "Configuration saved"
                ;;
            2)
                run_detection
                ;;
            3)
                run_manual_config
                ;;
            q|Q)
                msg_info "Goodbye!"
                exit 0
                ;;
            *)
                msg_ok "Using existing configuration"
                ;;
        esac
    fi

    # Wait for update check to complete (with timeout)
    wait "$update_pid" 2>/dev/null || true

    # Read update check results from background process
    read_update_check

    # If update available, prompt the user
    if [[ "$UPDATE_AVAILABLE" -eq 1 ]]; then
        echo ""
        echo -e "  ${T_WARN}═══════════════════════════════════════════════════════════${RST}"
        echo -e "  ${T_WARN}⚡ UPDATE AVAILABLE!${RST}"
        echo -e "  ${T_DIM}Your version:${RST}   v${VERSION}"
        echo -e "  ${T_SUCCESS}Latest version:${RST} v${LATEST_VERSION}"
        echo -e "  ${T_WARN}═══════════════════════════════════════════════════════════${RST}"
        echo ""
        if prompt_yn "Would you like to update now?"; then
            run_update
        else
            msg_info "You can update later by pressing 'u' in the menu"
            sleep 1
        fi
    fi

    # Main loop
    while true; do
        show_banner
        show_update_banner
        show_status
        show_menu

        echo -en "${T_DIM}Choice:${RST} "
        read -r choice

        case "$choice" in
            1)
                run_web_dashboard
                ;;
            2)
                reset_config
                ;;
            3)
                reset_database
                ;;
            4|f|F)
                firewall_helper
                ;;
            d|D)
                run_detection
                ;;
            m|M)
                run_manual_config
                ;;
            u|U)
                if [[ "$UPDATE_AVAILABLE" -eq 1 ]]; then
                    run_update
                else
                    msg_info "Already running the latest version (v${VERSION})"
                    sleep 1
                fi
                ;;
            q|Q)
                echo ""
                msg_info "Goodbye!"
                exit 0
                ;;
            *)
                msg_warn "Invalid option"
                sleep 0.5
                ;;
        esac
    done
}

main "$@"
