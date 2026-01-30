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

VERSION="0.2.2"

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
             ██ ██
███╗   ███╗████████╗████████╗ ██████╗         ██████╗  █████╗ ███████╗██╗  ██╗
████╗ ████║██╔════██║   ██╔═╝ ██╔═══╝         ██╔══██╗██╔══██╗██╔════╝██║  ██║
██╔████╔██║████████╔╝   ██║   ██║             ██║  ██║███████║███████╗███████║
██║╚██╔╝██║██╔════██╗   ██║   ██║             ██║  ██║██╔══██║╚════██║██╔══██║
██║ ╚═╝ ██║████████╔╝   ██║   ╚██████╗        ██████╔╝██║  ██║███████║██║  ██║
╚═╝     ╚═╝╚═██ ██═╝    ╚═╝    ╚═════╝        ╚═════╝ ╚═╝  ╚═╝╚══════╝╚═╝  ╚═╝
EOF
    echo -e "${RST}"
    echo -e "  ${T_DIM}MBTC-Dashboard${RST}          ${T_DIM}v${VERSION}${RST}"
    echo ""
}

# ═══════════════════════════════════════════════════════════════════════════════
# STATUS DISPLAY
# ═══════════════════════════════════════════════════════════════════════════════

show_status() {
    echo ""
    print_section "Current Configuration"

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

    print_section_end
}

# ═══════════════════════════════════════════════════════════════════════════════
# MAIN MENU
# ═══════════════════════════════════════════════════════════════════════════════

show_menu() {
    echo ""
    echo -e "${T_SECONDARY}${BOLD}Main Menu${RST}"
    echo ""
    echo -e "  ${T_INFO}1)${RST} Peer List          ${T_DIM}- View connected peers with geo-location (terminal)${RST}"
    echo -e "  ${T_INFO}2)${RST} Web Dashboard      ${T_DIM}- Launch local web dashboard${RST}"
    echo -e "  ${T_INFO}3)${RST} Blockchain Info    ${T_DIM}- View chain status (coming soon)${RST}"
    echo -e "  ${T_INFO}4)${RST} Mempool Stats      ${T_DIM}- View mempool data (coming soon)${RST}"
    echo ""
    echo -e "  ${T_WARN}d)${RST} Run Detection      ${T_DIM}- Detect/configure Bitcoin Core${RST}"
    echo -e "  ${T_WARN}r)${RST} Reset Config       ${T_DIM}- Clear saved configuration${RST}"
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
    print_header "Manual Configuration"

    echo ""
    echo -e "${T_SECONDARY}Enter the paths to your Bitcoin Core configuration.${RST}"
    echo -e "${T_DIM}(After entering these, the rest will be auto-detected)${RST}"
    echo ""

    # Ask for bitcoin.conf path
    local conf_path=""
    while true; do
        echo -en "${T_INFO}Path to bitcoin.conf${RST} ${T_DIM}(or 'b' to go back):${RST} "
        read -r conf_path

        if [[ "$conf_path" == "b" || "$conf_path" == "B" ]]; then
            return
        fi

        conf_path="${conf_path/#\~/$HOME}"

        if [[ -f "$conf_path" ]]; then
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
        while true; do
            echo -en "${T_INFO}Path to data directory${RST} ${T_DIM}(or 'b' to go back):${RST} "
            read -r datadir

            if [[ "$datadir" == "b" || "$datadir" == "B" ]]; then
                return
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
    msg_info "Auto-detecting remaining settings..."

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
                run_peer_list
                ;;
            2)
                run_web_dashboard
                ;;
            3)
                msg_info "Blockchain info coming soon..."
                echo ""
                echo -en "${T_DIM}Press Enter to continue...${RST}"
                read -r
                ;;
            4)
                msg_info "Mempool stats coming soon..."
                echo ""
                echo -en "${T_DIM}Press Enter to continue...${RST}"
                read -r
                ;;
            d|D)
                run_detection
                ;;
            r|R)
                reset_config
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
