#!/bin/bash
# MBTC-DASH - Prerequisites Checker
# Checks for required tools and offers to install missing ones

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/ui.sh"

# ═══════════════════════════════════════════════════════════════════════════════
# PREREQUISITE DEFINITIONS
# ═══════════════════════════════════════════════════════════════════════════════

# Format: "command|description|install_cmd_debian|install_cmd_fedora|install_cmd_arch|required"
# required: 1 = must have, 0 = optional (enhances features)

declare -a PREREQS=(
    "jq|JSON parser for RPC responses|apt install -y jq|dnf install -y jq|pacman -S --noconfirm jq|1"
    "curl|HTTP client for API calls|apt install -y curl|dnf install -y curl|pacman -S --noconfirm curl|1"
    "sqlite3|SQLite database for caching|apt install -y sqlite3|dnf install -y sqlite|pacman -S --noconfirm sqlite|1"
    "python3|Python interpreter for dashboard|apt install -y python3|dnf install -y python3|pacman -S --noconfirm python|1"
    "ss|Socket statistics (network info)|apt install -y iproute2|dnf install -y iproute|pacman -S --noconfirm iproute2|0"
    "bc|Calculator for math operations|apt install -y bc|dnf install -y bc|pacman -S --noconfirm bc|0"
)

# Bitcoin-specific (checked separately)
declare -a BITCOIN_TOOLS=(
    "bitcoin-cli|Bitcoin Core RPC client"
    "bitcoind|Bitcoin Core daemon"
)

# Python packages (checked separately)
declare -a PYTHON_PACKAGES=(
    "rich|Rich terminal UI library"
    "requests|HTTP library for API calls"
)

# ═══════════════════════════════════════════════════════════════════════════════
# DETECTION FUNCTIONS
# ═══════════════════════════════════════════════════════════════════════════════

# Detect package manager
detect_pkg_manager() {
    if command -v apt &>/dev/null; then
        echo "debian"
    elif command -v dnf &>/dev/null; then
        echo "fedora"
    elif command -v pacman &>/dev/null; then
        echo "arch"
    elif command -v brew &>/dev/null; then
        echo "macos"
    else
        echo "unknown"
    fi
}

# Check if command exists
cmd_exists() {
    command -v "$1" &>/dev/null
}

# Check if running as root
is_root() {
    [[ $EUID -eq 0 ]]
}

# Check if sudo is available
has_sudo() {
    command -v sudo &>/dev/null && sudo -n true 2>/dev/null
}

# ═══════════════════════════════════════════════════════════════════════════════
# PREREQUISITE CHECKING
# ═══════════════════════════════════════════════════════════════════════════════

# Check a single prerequisite
# Returns: 0 if present, 1 if missing required, 2 if missing optional
check_prereq() {
    local entry="$1"

    IFS='|' read -r cmd desc install_deb install_fed install_arch required <<< "$entry"

    if cmd_exists "$cmd"; then
        return 0
    else
        if [[ "$required" == "1" ]]; then
            return 1
        else
            return 2
        fi
    fi
}

# Get install command for current system
get_install_cmd() {
    local entry="$1"
    local pkg_mgr="$2"

    IFS='|' read -r cmd desc install_deb install_fed install_arch required <<< "$entry"

    case "$pkg_mgr" in
        debian) echo "$install_deb" ;;
        fedora) echo "$install_fed" ;;
        arch)   echo "$install_arch" ;;
        *)      echo "" ;;
    esac
}

# Check all prerequisites
# Returns arrays: MISSING_REQUIRED, MISSING_OPTIONAL
check_all_prereqs() {
    MISSING_REQUIRED=()
    MISSING_OPTIONAL=()
    PRESENT=()

    for entry in "${PREREQS[@]}"; do
        IFS='|' read -r cmd desc _ _ _ required <<< "$entry"

        check_prereq "$entry"
        local result=$?

        if [[ $result -eq 0 ]]; then
            PRESENT+=("$cmd|$desc")
        elif [[ $result -eq 1 ]]; then
            MISSING_REQUIRED+=("$entry")
        else
            MISSING_OPTIONAL+=("$entry")
        fi
    done
}

# ═══════════════════════════════════════════════════════════════════════════════
# INSTALLATION FUNCTIONS
# ═══════════════════════════════════════════════════════════════════════════════

# Install a single package
install_prereq() {
    local entry="$1"
    local pkg_mgr
    pkg_mgr=$(detect_pkg_manager)

    IFS='|' read -r cmd desc _ _ _ _ <<< "$entry"

    local install_cmd
    install_cmd=$(get_install_cmd "$entry" "$pkg_mgr")

    if [[ -z "$install_cmd" ]]; then
        msg_err "Cannot auto-install '$cmd' - unknown package manager"
        msg_info "Please install '$cmd' manually"
        return 1
    fi

    # Add sudo if needed
    if ! is_root && has_sudo; then
        install_cmd="sudo $install_cmd"
    elif ! is_root; then
        msg_err "Need root privileges to install packages"
        msg_info "Run: sudo $install_cmd"
        return 1
    fi

    msg_info "Installing $cmd..."
    if eval "$install_cmd" &>/dev/null; then
        msg_ok "Installed $cmd"
        return 0
    else
        msg_err "Failed to install $cmd"
        return 1
    fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# MAIN CHECK FUNCTION
# ═══════════════════════════════════════════════════════════════════════════════

# Run the full prerequisites check with UI
# Returns: 0 if all required present, 1 if missing required
run_prereq_check() {
    local auto_install="${1:-0}"
    local pkg_mgr
    pkg_mgr=$(detect_pkg_manager)

    print_section "Prerequisites Check"

    check_all_prereqs

    # Show present tools
    if [[ ${#PRESENT[@]} -gt 0 ]]; then
        for item in "${PRESENT[@]}"; do
            IFS='|' read -r cmd desc <<< "$item"
            msg_ok "${cmd} ${T_DIM}(${desc})${RST}"
        done
    fi

    # Show missing optional
    if [[ ${#MISSING_OPTIONAL[@]} -gt 0 ]]; then
        echo ""
        msg_warn "Optional tools not found:"
        for entry in "${MISSING_OPTIONAL[@]}"; do
            IFS='|' read -r cmd desc _ _ _ _ <<< "$entry"
            msg_bullet "${cmd} ${T_DIM}(${desc})${RST}"
        done
    fi

    # Handle missing required
    if [[ ${#MISSING_REQUIRED[@]} -gt 0 ]]; then
        echo ""
        msg_err "Required tools not found:"
        for entry in "${MISSING_REQUIRED[@]}"; do
            IFS='|' read -r cmd desc _ _ _ _ <<< "$entry"
            msg_bullet "${cmd} ${T_DIM}(${desc})${RST}"
        done

        echo ""

        if [[ "$auto_install" == "1" ]]; then
            msg_info "Auto-installing missing required tools..."
            local all_installed=1
            for entry in "${MISSING_REQUIRED[@]}"; do
                if ! install_prereq "$entry"; then
                    all_installed=0
                fi
            done

            if [[ $all_installed -eq 0 ]]; then
                msg_err "Some required tools could not be installed"
                print_section_end
                return 1
            fi
        else
            if prompt_yn "Install missing required tools?"; then
                local all_installed=1
                for entry in "${MISSING_REQUIRED[@]}"; do
                    if ! install_prereq "$entry"; then
                        all_installed=0
                    fi
                done

                if [[ $all_installed -eq 0 ]]; then
                    msg_err "Some required tools could not be installed"
                    print_section_end
                    return 1
                fi
            else
                msg_err "Cannot continue without required tools"
                print_section_end
                return 1
            fi
        fi
    fi

    # Check for Bitcoin tools (informational only at this stage)
    echo ""
    echo -e "${T_DIM}Bitcoin Core tools:${RST}"
    for entry in "${BITCOIN_TOOLS[@]}"; do
        IFS='|' read -r cmd desc <<< "$entry"
        if cmd_exists "$cmd"; then
            local version
            version=$($cmd --version 2>/dev/null | head -1 || echo "unknown version")
            msg_ok "${cmd} ${T_DIM}(${version})${RST}"
        else
            msg_warn "${cmd} ${T_DIM}(not in PATH - will search)${RST}"
        fi
    done

    # Check Python packages
    run_python_check

    print_section_end
    return 0
}

# Quick check without UI (for scripts)
quick_prereq_check() {
    check_all_prereqs
    [[ ${#MISSING_REQUIRED[@]} -eq 0 ]]
}

# ═══════════════════════════════════════════════════════════════════════════════
# PYTHON PACKAGE CHECKING
# ═══════════════════════════════════════════════════════════════════════════════

# Check if Python package is installed
python_pkg_exists() {
    local pkg="$1"
    python3 -c "import $pkg" 2>/dev/null
}

# Install Python package
install_python_pkg() {
    local pkg="$1"
    local desc="$2"

    msg_info "Installing Python package: $pkg..."

    # Try pip3 first, then pip
    if command -v pip3 &>/dev/null; then
        if pip3 install --user "$pkg" &>/dev/null; then
            msg_ok "Installed $pkg"
            return 0
        fi
    elif command -v pip &>/dev/null; then
        if pip install --user "$pkg" &>/dev/null; then
            msg_ok "Installed $pkg"
            return 0
        fi
    fi

    msg_err "Failed to install $pkg"
    msg_info "Try: pip3 install $pkg"
    return 1
}

# Check all Python packages
check_python_packages() {
    MISSING_PYTHON=()
    PRESENT_PYTHON=()

    for entry in "${PYTHON_PACKAGES[@]}"; do
        IFS='|' read -r pkg desc <<< "$entry"

        if python_pkg_exists "$pkg"; then
            PRESENT_PYTHON+=("$pkg|$desc")
        else
            MISSING_PYTHON+=("$pkg|$desc")
        fi
    done
}

# Run Python package check with UI
run_python_check() {
    # Skip if python3 not installed
    if ! cmd_exists python3; then
        return 1
    fi

    echo ""
    echo -e "${T_DIM}Python packages:${RST}"

    check_python_packages

    # Show present packages
    for item in "${PRESENT_PYTHON[@]}"; do
        IFS='|' read -r pkg desc <<< "$item"
        msg_ok "${pkg} ${T_DIM}(${desc})${RST}"
    done

    # Handle missing packages
    if [[ ${#MISSING_PYTHON[@]} -gt 0 ]]; then
        echo ""
        msg_warn "Missing Python packages:"
        for item in "${MISSING_PYTHON[@]}"; do
            IFS='|' read -r pkg desc <<< "$item"
            msg_bullet "${pkg} ${T_DIM}(${desc})${RST}"
        done

        echo ""
        if prompt_yn "Install missing Python packages?"; then
            for item in "${MISSING_PYTHON[@]}"; do
                IFS='|' read -r pkg desc <<< "$item"
                install_python_pkg "$pkg" "$desc"
            done
        else
            msg_warn "Some features may not work without required Python packages"
            return 1
        fi
    fi

    return 0
}
