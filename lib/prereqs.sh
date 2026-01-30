#!/bin/bash
# MBTC-DASH - Prerequisites Checker
# Checks for required tools and offers to install missing ones

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/ui.sh"

# Get base directory (parent of lib/)
MBTC_BASE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
VENV_DIR="$MBTC_BASE_DIR/venv"

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

# Python packages - Terminal mode (required for basic functionality)
declare -a PYTHON_TERMINAL_PACKAGES=(
    "rich|Rich terminal UI library"
    "requests|HTTP library for API calls"
)

# Python packages - Web mode (required for web dashboard)
declare -a PYTHON_WEB_PACKAGES=(
    "fastapi|FastAPI web framework"
    "uvicorn|ASGI server for FastAPI"
    "jinja2|Template engine for FastAPI"
    "sse_starlette|Server-Sent Events for FastAPI"
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
# VENV FUNCTIONS
# ═══════════════════════════════════════════════════════════════════════════════

# Check if venv exists and is valid
venv_exists() {
    [[ -d "$VENV_DIR" && -f "$VENV_DIR/bin/python3" ]]
}

# Create virtual environment
create_venv() {
    msg_info "Creating virtual environment in ./venv/..."

    if python3 -m venv "$VENV_DIR" 2>/dev/null; then
        msg_ok "Virtual environment created"
        return 0
    else
        msg_err "Failed to create virtual environment"
        msg_info "You may need to install python3-venv:"
        msg_info "  Debian/Ubuntu: sudo apt install python3-venv"
        msg_info "  Fedora: sudo dnf install python3-virtualenv"
        return 1
    fi
}

# Get the pip command for venv
get_venv_pip() {
    echo "$VENV_DIR/bin/pip"
}

# Get the python command for venv
get_venv_python() {
    echo "$VENV_DIR/bin/python3"
}

# Check if package is installed in venv
venv_pkg_exists() {
    local pkg="$1"
    if venv_exists; then
        "$VENV_DIR/bin/python3" -c "import $pkg" 2>/dev/null
    else
        return 1
    fi
}

# Install package in venv
install_venv_pkg() {
    local pkg="$1"
    local pip_cmd
    pip_cmd=$(get_venv_pip)

    # Handle package name vs import name differences
    local install_name="$pkg"
    case "$pkg" in
        sse_starlette) install_name="sse-starlette" ;;
    esac

    msg_info "Installing $pkg..."
    if "$pip_cmd" install "$install_name" --quiet 2>/dev/null; then
        msg_ok "Installed $pkg"
        return 0
    else
        msg_err "Failed to install $pkg"
        return 1
    fi
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

    # Check Python packages using venv
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
# PYTHON PACKAGE CHECKING (VENV-BASED)
# ═══════════════════════════════════════════════════════════════════════════════

# Check Python packages and setup venv if needed
# Sets global: PYTHON_MODE ("full", "terminal", "none")
run_python_check() {
    # Skip if python3 not installed
    if ! cmd_exists python3; then
        PYTHON_MODE="none"
        return 1
    fi

    echo ""
    echo -e "${T_DIM}Checking your python...${RST}"

    # Check if venv exists
    if ! venv_exists; then
        msg_warn "No virtual environment found"
    fi

    # Check terminal packages
    local missing_terminal=()
    local present_terminal=()

    for entry in "${PYTHON_TERMINAL_PACKAGES[@]}"; do
        IFS='|' read -r pkg desc <<< "$entry"
        if venv_pkg_exists "$pkg"; then
            present_terminal+=("$pkg|$desc")
        else
            missing_terminal+=("$pkg|$desc")
        fi
    done

    # Check web packages
    local missing_web=()
    local present_web=()

    for entry in "${PYTHON_WEB_PACKAGES[@]}"; do
        IFS='|' read -r pkg desc <<< "$entry"
        if venv_pkg_exists "$pkg"; then
            present_web+=("$pkg|$desc")
        else
            missing_web+=("$pkg|$desc")
        fi
    done

    # Determine what's missing
    local need_venv=0
    local need_terminal=0
    local need_web=0

    if ! venv_exists; then
        need_venv=1
    fi
    if [[ ${#missing_terminal[@]} -gt 0 ]]; then
        need_terminal=1
    fi
    if [[ ${#missing_web[@]} -gt 0 ]]; then
        need_web=1
    fi

    # If nothing missing, we're good - show success message
    if [[ $need_terminal -eq 0 && $need_web -eq 0 ]]; then
        msg_ok "Nice package, it slipped right into the virtual environment"
        for item in "${present_terminal[@]}"; do
            IFS='|' read -r pkg desc <<< "$item"
            msg_bullet "${pkg} ${T_DIM}(${desc})${RST}"
        done
        echo ""
        echo -e "${T_DIM}Checking dashboard site necessities...${RST}"
        for item in "${present_web[@]}"; do
            IFS='|' read -r pkg desc <<< "$item"
            msg_ok "${pkg} ${T_DIM}(${desc})${RST}"
        done
        PYTHON_MODE="full"
        return 0
    fi

    # Show what's missing
    if [[ $need_terminal -eq 1 ]]; then
        msg_warn "No package found... (required):"
        for item in "${missing_terminal[@]}"; do
            IFS='|' read -r pkg desc <<< "$item"
            msg_bullet "${pkg} ${T_DIM}(${desc})${RST}"
        done
    fi

    echo ""
    echo -e "${T_DIM}Checking dashboard site necessities:${RST}"
    if [[ $need_web -eq 1 ]]; then
        msg_warn "Missing:"
        for item in "${missing_web[@]}"; do
            IFS='|' read -r pkg desc <<< "$item"
            msg_bullet "${pkg} ${T_DIM}(${desc})${RST}"
        done
    fi

    echo ""

    # Offer to install
    if prompt_yn "Setup virtual environment and install packages?"; then
        # Create venv if needed
        if [[ $need_venv -eq 1 ]]; then
            echo ""
            echo -e "Creating virtual environment..."
            echo -e "${T_DIM}──────────────────────────────────${RST}"
            if ! create_venv; then
                msg_err "Cannot proceed without virtual environment"
                PYTHON_MODE="none"
                return 1
            fi

            # Upgrade pip
            msg_info "Upgrading pip..."
            if "$VENV_DIR/bin/pip" install --upgrade pip --quiet 2>/dev/null; then
                msg_ok "Pip upgraded"
            fi
        fi

        # Install terminal packages first (required)
        local terminal_failed=0
        if [[ $need_terminal -eq 1 ]]; then
            echo ""
            echo -e "Installing terminal packages..."
            echo -e "${T_DIM}───────────────────────────────────${RST}"
            for item in "${missing_terminal[@]}"; do
                IFS='|' read -r pkg desc <<< "$item"
                if ! install_venv_pkg "$pkg"; then
                    terminal_failed=1
                fi
            done
        fi

        if [[ $terminal_failed -eq 1 ]]; then
            msg_err "Failed to install required terminal packages"
            msg_err "The program cannot run without these packages"
            PYTHON_MODE="none"
            return 1
        fi

        # Install web packages
        local web_failed=0
        if [[ $need_web -eq 1 ]]; then
            echo ""
            echo -e "Installing web dashboard packages..."
            echo -e "${T_DIM}────────────────────────────────────${RST}"
            for item in "${missing_web[@]}"; do
                IFS='|' read -r pkg desc <<< "$item"
                if ! install_venv_pkg "$pkg"; then
                    web_failed=1
                fi
            done
        fi

        if [[ $web_failed -eq 1 ]]; then
            echo ""
            msg_warn "Some web packages failed to install"
            msg_warn "Web dashboard will not be available"
            msg_ok "Terminal mode will work normally"
            PYTHON_MODE="terminal"
            return 0
        fi

        echo ""
        echo -e "${T_SUCCESS}** All packages installed successfully!! **${RST}"
        PYTHON_MODE="full"
        return 0
    else
        # User declined - offer options
        echo ""
        msg_warn "Python packages are required to run this program."
        echo ""
        echo "Options:"
        echo "  1) Install packages (recommended)"
        echo "  2) Continue without web dashboard (terminal only)"
        echo "  3) Exit"
        echo ""
        echo -en "${T_PROMPT}Choose [1-3]: ${RST}"
        read -r choice

        case "$choice" in
            1)
                # Recursively call to install
                run_python_check
                return $?
                ;;
            2)
                if [[ $need_terminal -eq 1 ]]; then
                    msg_err "Terminal packages are required even for terminal-only mode"
                    msg_err "Please install packages or exit"
                    PYTHON_MODE="none"
                    return 1
                fi
                msg_warn "Continuing in terminal-only mode"
                msg_warn "Web dashboard will not be available"
                PYTHON_MODE="terminal"
                return 0
                ;;
            *)
                msg_info "Exiting..."
                PYTHON_MODE="none"
                exit 0
                ;;
        esac
    fi
}

# Check if web mode is available
is_web_available() {
    for entry in "${PYTHON_WEB_PACKAGES[@]}"; do
        IFS='|' read -r pkg desc <<< "$entry"
        if ! venv_pkg_exists "$pkg"; then
            return 1
        fi
    done
    return 0
}

# Check if terminal mode is available
is_terminal_available() {
    for entry in "${PYTHON_TERMINAL_PACKAGES[@]}"; do
        IFS='|' read -r pkg desc <<< "$entry"
        if ! venv_pkg_exists "$pkg"; then
            return 1
        fi
    done
    return 0
}
