#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════
#  WCURGUI - Bitcoin Core GUI Dashboard
#  A terminal-based monitoring and management interface for Bitcoin Core
# ═══════════════════════════════════════════════════════════════════════════════

set -e

# Get the directory where this script lives
WCURGUI_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export WCURGUI_DIR

# Source libraries
source "$WCURGUI_DIR/lib/ui.sh"
source "$WCURGUI_DIR/lib/prereqs.sh"
source "$WCURGUI_DIR/lib/detection.sh"

VERSION="0.1.0"

# ═══════════════════════════════════════════════════════════════════════════════
# BANNER
# ═══════════════════════════════════════════════════════════════════════════════

show_banner() {
    clear
    echo ""
    echo -e "${T_PRIMARY}"
    cat << 'EOF'
 ██╗    ██╗ ██████╗██╗   ██╗██████╗  ██████╗ ██╗   ██╗██╗
 ██║    ██║██╔════╝██║   ██║██╔══██╗██╔════╝ ██║   ██║██║
 ██║ █╗ ██║██║     ██║   ██║██████╔╝██║  ███╗██║   ██║██║
 ██║███╗██║██║     ██║   ██║██╔══██╗██║   ██║██║   ██║██║
 ╚███╔███╔╝╚██████╗╚██████╔╝██║  ██║╚██████╔╝╚██████╔╝██║
  ╚══╝╚══╝  ╚═════╝ ╚═════╝ ╚═╝  ╚═╝ ╚═════╝  ╚═════╝ ╚═╝
EOF
    echo -e "${RST}"
    echo -e "  ${T_DIM}Bitcoin Core GUI Dashboard${RST}          ${T_DIM}v${VERSION}${RST}"
    echo ""
    print_divider "═" 60
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
        exit 1
    fi

    # Run detection
    if ! run_detection; then
        echo ""
        msg_err "Could not detect Bitcoin Core"
        msg_info "Make sure Bitcoin Core is installed"
        exit 1
    fi

    echo ""
    msg_ok "Detection complete!"
}

main "$@"
