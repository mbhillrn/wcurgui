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

VERSION="0.2.0"

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
    echo -e "  ${T_INFO}1)${RST} Peer List          ${T_DIM}- View connected peers with geo-location${RST}"
    echo -e "  ${T_INFO}2)${RST} Blockchain Info    ${T_DIM}- View chain status (coming soon)${RST}"
    echo -e "  ${T_INFO}3)${RST} Mempool Stats      ${T_DIM}- View mempool data (coming soon)${RST}"
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

    # Run Python peer list
    python3 "$MBTC_DIR/scripts/peerlist.py"
}

run_detection() {
    "$MBTC_DIR/scripts/detect.sh"
    # Reload config after detection
    load_config
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

    # Check if config exists, if not run detection
    if [[ "$MBTC_CONFIGURED" -ne 1 ]]; then
        echo ""
        msg_info "No configuration found. Running Bitcoin Core detection..."
        echo ""
        echo -en "${T_DIM}Press Enter to continue...${RST}"
        read -r
        run_detection
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
                msg_info "Blockchain info coming soon..."
                echo ""
                echo -en "${T_DIM}Press Enter to continue...${RST}"
                read -r
                ;;
            3)
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
