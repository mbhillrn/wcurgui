#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════
#  MBTC-DASH - Bitcoin Core Dashboard
#  A terminal-based monitoring and management interface for Bitcoin Core
# ═══════════════════════════════════════════════════════════════════════════════

set -e

# Get the directory where this script lives
MBTC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export MBTC_DIR

# Source libraries
source "$MBTC_DIR/lib/ui.sh"
source "$MBTC_DIR/lib/prereqs.sh"
source "$MBTC_DIR/lib/config.sh"

VERSION="2.0.0"

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
    echo ""
    echo -e "  ${T_WARN}d)${RST} Rerun Detection    ${T_DIM}- Re-detect Bitcoin Core settings${RST}"
    echo -e "  ${T_WARN}m)${RST} Manual Settings    ${T_DIM}- Manually enter Bitcoin Core settings${RST}"
    echo -e "  ${T_DIM}t)${RST} Terminal View      ${T_DIM}- Very limited terminal peer list${RST}"
    echo ""
    echo -e "  ${T_ERROR}q)${RST} Quit"
    echo ""
}

run_peer_list() {
    if [[ "$MBTC_CONFIGURED" -ne 1 ]]; then
        msg_err "Bitcoin Core not configured. Run detection first."
        echo ""
        echo -en "${T_DIM}Press Enter to continue...${RST}"
        read -r
        return
    fi

    # Check if venv exists and terminal packages are available
    if ! is_terminal_available; then
        msg_err "Python packages not installed"
        msg_info "Please run the prerequisites check from the main menu"
        echo ""
        echo -en "${T_DIM}Press Enter to continue...${RST}"
        read -r
        return
    fi

    # Run Python peer list using venv
    "$VENV_PYTHON" "$MBTC_DIR/scripts/peerlist.py"
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
# MAIN
# ═══════════════════════════════════════════════════════════════════════════════

main() {
    show_banner

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

    # Main loop
    while true; do
        show_banner
        show_status
        show_menu

        echo -en "${T_DIM}Choice:${RST} "
        read -r choice

        case "$choice" in
            1)
                run_web_dashboard
                ;;
            d|D)
                run_detection
                ;;
            m|M)
                run_manual_config
                ;;
            2)
                reset_config
                ;;
            3)
                reset_database
                ;;
            t|T)
                run_peer_list
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
