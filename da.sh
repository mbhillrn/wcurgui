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
source "$MBTC_DIR/lib/detection.sh"

VERSION="0.1.0"

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
    print_divider "═" 78
    echo ""
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

    # Run detection
    if ! run_detection; then
        echo ""
        msg_err "Could not detect Bitcoin Core"
        msg_info "Make sure Bitcoin Core is installed"
        echo ""
        echo -en "${T_DIM}Press Enter to exit...${RST}"
        read -r
        exit 1
    fi

    echo ""
    msg_ok "Detection complete!"
    echo ""
    echo -e "${T_DIM}Environment variables set:${RST}"
    echo -e "  ${BWHITE}\$MBTC_CLI_PATH${RST}   = $MBTC_CLI_PATH"
    echo -e "  ${BWHITE}\$MBTC_DATADIR${RST}    = $MBTC_DATADIR"
    echo -e "  ${BWHITE}\$MBTC_CONF${RST}       = $MBTC_CONF"
    echo -e "  ${BWHITE}\$MBTC_NETWORK${RST}    = $MBTC_NETWORK"
    echo -e "  ${BWHITE}\$MBTC_RPC_HOST${RST}   = $MBTC_RPC_HOST"
    echo -e "  ${BWHITE}\$MBTC_RPC_PORT${RST}   = $MBTC_RPC_PORT"
    [[ -n "$MBTC_COOKIE_PATH" ]] && echo -e "  ${BWHITE}\$MBTC_COOKIE_PATH${RST}= $MBTC_COOKIE_PATH"
    [[ -n "$MBTC_RPC_USER" ]] && echo -e "  ${BWHITE}\$MBTC_RPC_USER${RST}   = $MBTC_RPC_USER"
    echo ""
    echo -e "${T_DIM}Cache saved to: $CACHE_FILE${RST}"
    echo ""
    print_divider "═" 78
    echo ""
    echo -en "${T_INFO}Press Enter to exit...${RST}"
    read -r
}

main "$@"
