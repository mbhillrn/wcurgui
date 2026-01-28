#!/bin/bash
# MBTC-DASH - Bitcoin Core Detection
# Detects Bitcoin Core installation, datadir, conf, and auth settings
# All detected values stored in MBTC_* environment variables

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/ui.sh"

# ═══════════════════════════════════════════════════════════════════════════════
# ENVIRONMENT VARIABLES (MBTC_ prefix to avoid conflicts)
# These are exported so other scripts can use them
# ═══════════════════════════════════════════════════════════════════════════════

export MBTC_CLI_PATH=""
export MBTC_DATADIR=""
export MBTC_CONF=""
export MBTC_NETWORK="main"
export MBTC_RPC_HOST="127.0.0.1"
export MBTC_RPC_PORT="8332"
export MBTC_RPC_USER=""
export MBTC_RPC_PASS=""
export MBTC_COOKIE_PATH=""
export MBTC_VERSION=""
export MBTC_RUNNING=0

# ═══════════════════════════════════════════════════════════════════════════════
# CONFIGURATION
# ═══════════════════════════════════════════════════════════════════════════════

CACHE_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/mbtc-dash"
CACHE_FILE="$CACHE_DIR/detection_cache.conf"

# Common datadir locations
DATADIR_CANDIDATES=(
    "$HOME/.bitcoin"
    "/var/lib/bitcoind"
    "/var/lib/bitcoin"
    "/srv/bitcoin"
    "/data/bitcoin"
    "/opt/bitcoin/data"
    "/home/bitcoin/.bitcoin"
)

# Fallback binary search paths
BINARY_SEARCH_PATHS=(
    "/usr/bin"
    "/usr/local/bin"
    "/opt/bitcoin/bin"
    "/snap/bin"
    "$HOME/bin"
    "$HOME/.local/bin"
)

# Common conf file locations
CONF_CANDIDATES=(
    "$HOME/.bitcoin/bitcoin.conf"
    "/etc/bitcoin/bitcoin.conf"
    "/etc/bitcoind/bitcoin.conf"
    "/srv/bitcoin/bitcoin.conf"
    "/var/lib/bitcoind/bitcoin.conf"
)

# ═══════════════════════════════════════════════════════════════════════════════
# CTRL+C HANDLING
# ═══════════════════════════════════════════════════════════════════════════════

CTRL_C_COUNT=0
CTRL_C_TIME=0

handle_ctrl_c() {
    local now
    now=$(date +%s)

    # Reset counter if more than 2 seconds since last Ctrl+C
    if (( now - CTRL_C_TIME > 2 )); then
        CTRL_C_COUNT=0
    fi

    CTRL_C_TIME=$now
    ((CTRL_C_COUNT++))

    if [[ $CTRL_C_COUNT -eq 1 ]]; then
        echo ""
        msg_warn "Press Ctrl+C again to force quit (or wait for current operation to finish)"
    else
        echo ""
        msg_info "Force quitting..."
        cursor_show
        exit 130
    fi
}

trap handle_ctrl_c SIGINT

# ═══════════════════════════════════════════════════════════════════════════════
# CACHE FUNCTIONS
# ═══════════════════════════════════════════════════════════════════════════════

save_cache() {
    mkdir -p "$CACHE_DIR"

    cat > "$CACHE_FILE" << EOF
# MBTC-DASH Detection Cache
# Generated: $(date)
MBTC_CLI_PATH="$MBTC_CLI_PATH"
MBTC_DATADIR="$MBTC_DATADIR"
MBTC_CONF="$MBTC_CONF"
MBTC_NETWORK="$MBTC_NETWORK"
MBTC_RPC_HOST="$MBTC_RPC_HOST"
MBTC_RPC_PORT="$MBTC_RPC_PORT"
MBTC_RPC_USER="$MBTC_RPC_USER"
MBTC_COOKIE_PATH="$MBTC_COOKIE_PATH"
EOF
    chmod 600 "$CACHE_FILE"
    msg_ok "Configuration saved to cache"
}

load_cache() {
    [[ ! -f "$CACHE_FILE" ]] && return 1

    # Source the cache file to load variables
    source "$CACHE_FILE" 2>/dev/null || return 1

    # Check if we have at least CLI path
    [[ -z "$MBTC_CLI_PATH" ]] && return 1

    return 0
}

display_cached_config() {
    echo ""
    echo -e "${T_SECONDARY}${BOLD}Cached Configuration:${RST}"
    echo ""
    print_kv "Bitcoin CLI" "${MBTC_CLI_PATH:-not set}" 18
    print_kv "Data Directory" "${MBTC_DATADIR:-not set}" 18
    print_kv "Config File" "${MBTC_CONF:-not set}" 18
    print_kv "Network" "${MBTC_NETWORK:-main}" 18
    print_kv "RPC Host:Port" "${MBTC_RPC_HOST:-127.0.0.1}:${MBTC_RPC_PORT:-8332}" 18
    if [[ -n "$MBTC_COOKIE_PATH" ]]; then
        print_kv "Auth" "Cookie ($MBTC_COOKIE_PATH)" 18
    elif [[ -n "$MBTC_RPC_USER" ]]; then
        print_kv "Auth" "User/Pass ($MBTC_RPC_USER)" 18
    fi
    echo ""
}

# ═══════════════════════════════════════════════════════════════════════════════
# PROCESS DETECTION
# ═══════════════════════════════════════════════════════════════════════════════

detect_running_process() {
    local pinfo
    pinfo=$(pgrep -a bitcoind 2>/dev/null | head -1) || return 1
    [[ -z "$pinfo" ]] && return 1

    MBTC_RUNNING=1

    local args
    args=$(echo "$pinfo" | cut -d' ' -f3-)

    # Parse arguments from running process
    [[ "$args" =~ -datadir=([^[:space:]]+) ]] && MBTC_DATADIR="${BASH_REMATCH[1]}"
    [[ "$args" =~ -conf=([^[:space:]]+) ]] && MBTC_CONF="${BASH_REMATCH[1]}"

    if [[ "$args" =~ -testnet ]]; then
        MBTC_NETWORK="test"
        MBTC_RPC_PORT="18332"
    elif [[ "$args" =~ -signet ]]; then
        MBTC_NETWORK="signet"
        MBTC_RPC_PORT="38332"
    elif [[ "$args" =~ -regtest ]]; then
        MBTC_NETWORK="regtest"
        MBTC_RPC_PORT="18443"
    fi

    [[ "$args" =~ -rpcport=([0-9]+) ]] && MBTC_RPC_PORT="${BASH_REMATCH[1]}"
    [[ "$args" =~ -rpcuser=([^[:space:]]+) ]] && MBTC_RPC_USER="${BASH_REMATCH[1]}"
    [[ "$args" =~ -rpcpassword=([^[:space:]]+) ]] && MBTC_RPC_PASS="${BASH_REMATCH[1]}"
    [[ "$args" =~ -rpccookiefile=([^[:space:]]+) ]] && MBTC_COOKIE_PATH="${BASH_REMATCH[1]}"

    return 0
}

# ═══════════════════════════════════════════════════════════════════════════════
# SYSTEMD DETECTION
# ═══════════════════════════════════════════════════════════════════════════════

detect_systemd_service() {
    command -v systemctl &>/dev/null || return 1

    local services
    services=$(systemctl list-units --type=service --all 2>/dev/null | grep -iE 'bitcoin' | awk '{print $1}')
    [[ -z "$services" ]] && return 1

    for service in $services; do
        # Check if active
        systemctl is-active --quiet "$service" 2>/dev/null || continue

        local exec_start
        exec_start=$(systemctl show "$service" --property=ExecStart 2>/dev/null)

        [[ "$exec_start" =~ -datadir=([^[:space:]\;]+) ]] && MBTC_DATADIR="${BASH_REMATCH[1]}"
        [[ "$exec_start" =~ -conf=([^[:space:]\;]+) ]] && MBTC_CONF="${BASH_REMATCH[1]}"

        [[ -n "$MBTC_DATADIR" || -n "$MBTC_CONF" ]] && return 0
    done

    return 1
}

# ═══════════════════════════════════════════════════════════════════════════════
# BITCOIN-CLI DETECTION
# ═══════════════════════════════════════════════════════════════════════════════

detect_bitcoin_cli() {
    # Just try running it
    local result
    result=$(bitcoin-cli --version 2>&1)
    local exit_code=$?

    if [[ $exit_code -eq 0 ]]; then
        MBTC_CLI_PATH=$(command -v bitcoin-cli)
        MBTC_VERSION=$(echo "$result" | head -1 | grep -oP 'v[\d.]+' || echo "unknown")
        return 0
    fi

    # Command not found - search for it
    if [[ "$result" == *"command not found"* ]] || [[ "$result" == *"not found"* ]]; then
        for dir in "${BINARY_SEARCH_PATHS[@]}"; do
            if [[ -x "$dir/bitcoin-cli" ]]; then
                local test_result
                test_result=$("$dir/bitcoin-cli" --version 2>&1)
                if [[ $? -eq 0 ]]; then
                    MBTC_CLI_PATH="$dir/bitcoin-cli"
                    MBTC_VERSION=$(echo "$test_result" | head -1 | grep -oP 'v[\d.]+' || echo "unknown")
                    return 0
                fi
            fi
        done
        return 1
    fi

    # Some other error but cli exists
    MBTC_CLI_PATH=$(command -v bitcoin-cli 2>/dev/null)
    [[ -n "$MBTC_CLI_PATH" ]] && return 0

    return 1
}

# ═══════════════════════════════════════════════════════════════════════════════
# CONFIG FILE DETECTION
# ═══════════════════════════════════════════════════════════════════════════════

validate_conf_file() {
    local conf="$1"
    [[ -f "$conf" ]] && return 0
    return 1
}

find_conf_file() {
    # Already found?
    [[ -n "$MBTC_CONF" ]] && validate_conf_file "$MBTC_CONF" && return 0

    # Check in datadir first if we have it
    if [[ -n "$MBTC_DATADIR" && -f "$MBTC_DATADIR/bitcoin.conf" ]]; then
        MBTC_CONF="$MBTC_DATADIR/bitcoin.conf"
        return 0
    fi

    # Check common locations
    for conf in "${CONF_CANDIDATES[@]}"; do
        if validate_conf_file "$conf"; then
            MBTC_CONF="$conf"
            # Also grab datadir from same location if not set
            if [[ -z "$MBTC_DATADIR" ]]; then
                local dir
                dir=$(dirname "$conf")
                if validate_datadir "$dir"; then
                    MBTC_DATADIR="$dir"
                fi
            fi
            return 0
        fi
    done

    return 1
}

parse_conf_file() {
    local conf="$1"
    [[ ! -f "$conf" ]] && return 1

    while IFS='=' read -r key value; do
        [[ "$key" =~ ^[[:space:]]*# ]] && continue
        [[ -z "$key" ]] && continue

        key=$(echo "$key" | xargs)
        value=$(echo "$value" | xargs)

        case "$key" in
            datadir)     [[ -z "$MBTC_DATADIR" ]] && MBTC_DATADIR="$value" ;;
            testnet)     [[ "$value" == "1" ]] && MBTC_NETWORK="test" && MBTC_RPC_PORT="18332" ;;
            signet)      [[ "$value" == "1" ]] && MBTC_NETWORK="signet" && MBTC_RPC_PORT="38332" ;;
            regtest)     [[ "$value" == "1" ]] && MBTC_NETWORK="regtest" && MBTC_RPC_PORT="18443" ;;
            rpcuser)     MBTC_RPC_USER="$value" ;;
            rpcpassword) MBTC_RPC_PASS="$value" ;;
            rpcport)     MBTC_RPC_PORT="$value" ;;
            rpcbind)     [[ "$MBTC_RPC_HOST" == "127.0.0.1" ]] && MBTC_RPC_HOST="$value" ;;
            rpccookiefile) MBTC_COOKIE_PATH="$value" ;;
        esac
    done < "$conf"
    return 0
}

# Full system search for conf file
search_conf_file() {
    echo ""
    msg_warn "This may take a while depending on your system..."
    echo ""

    start_spinner "Searching entire system for bitcoin.conf"

    local found
    found=$(find / -name "bitcoin.conf" -type f 2>/dev/null | head -10)

    stop_spinner 0 "Search complete"

    if [[ -z "$found" ]]; then
        msg_err "No bitcoin.conf found on system"
        return 1
    fi

    # Show what we found
    echo ""
    echo -e "${T_SECONDARY}Found these config files:${RST}"
    echo ""

    local i=1
    local -a found_array
    while IFS= read -r file; do
        [[ -z "$file" ]] && continue
        found_array+=("$file")
        echo -e "  ${T_INFO}${i})${RST} $file"
        ((i++))
    done <<< "$found"

    echo -e "  ${T_WARN}b)${RST} Go back"
    echo ""

    local choice
    echo -en "${T_DIM}Select config file [1-$((i-1))]:${RST} "
    read -r choice

    if [[ "$choice" == "b" || "$choice" == "B" ]]; then
        return 2  # Go back
    fi

    if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice < i )); then
        MBTC_CONF="${found_array[$((choice-1))]}"
        msg_ok "Selected: $MBTC_CONF"
        return 0
    fi

    msg_err "Invalid selection"
    return 1
}

# ═══════════════════════════════════════════════════════════════════════════════
# DATADIR DETECTION
# ═══════════════════════════════════════════════════════════════════════════════

validate_datadir() {
    local dir="$1"
    [[ ! -d "$dir" ]] && return 1

    # Check for typical Bitcoin Core files/folders
    if [[ -d "$dir/blocks" ]] || [[ -f "$dir/bitcoin.conf" ]] || [[ -f "$dir/.cookie" ]]; then
        return 0
    fi

    for subdir in testnet3 signet regtest; do
        [[ -d "$dir/$subdir/blocks" ]] && return 0
    done

    return 1
}

find_datadir() {
    # Already found?
    [[ -n "$MBTC_DATADIR" ]] && validate_datadir "$MBTC_DATADIR" && return 0

    # If we have conf, check its directory
    if [[ -n "$MBTC_CONF" ]]; then
        local conf_dir
        conf_dir=$(dirname "$MBTC_CONF")
        if validate_datadir "$conf_dir"; then
            MBTC_DATADIR="$conf_dir"
            return 0
        fi
    fi

    # Check default
    if validate_datadir "$HOME/.bitcoin"; then
        MBTC_DATADIR="$HOME/.bitcoin"
        return 0
    fi

    # Check candidates
    for dir in "${DATADIR_CANDIDATES[@]}"; do
        if validate_datadir "$dir"; then
            MBTC_DATADIR="$dir"
            return 0
        fi
    done

    # Check mounted drives
    for mount in /mnt/* /media/*/* /data/*; do
        [[ -d "$mount" ]] || continue
        for subdir in bitcoin .bitcoin bitcoind; do
            if validate_datadir "$mount/$subdir"; then
                MBTC_DATADIR="$mount/$subdir"
                return 0
            fi
        done
    done 2>/dev/null

    return 1
}

# Full system search for datadir
search_datadir() {
    echo ""
    msg_warn "Searching for blocks/blk*.dat files - this may take a LONG time..."
    echo ""

    start_spinner "Searching entire system for Bitcoin data"

    local found
    found=$(find / -name "blk00000.dat" -type f 2>/dev/null | head -5)

    stop_spinner 0 "Search complete"

    if [[ -z "$found" ]]; then
        msg_err "No Bitcoin blockchain data found on system"
        return 1
    fi

    echo ""
    echo -e "${T_SECONDARY}Found blockchain data in:${RST}"
    echo ""

    local i=1
    local -a found_array
    while IFS= read -r file; do
        [[ -z "$file" ]] && continue
        # Get parent of blocks directory (the datadir)
        local datadir
        datadir=$(dirname "$(dirname "$file")")
        found_array+=("$datadir")
        echo -e "  ${T_INFO}${i})${RST} $datadir"
        ((i++))
    done <<< "$found"

    echo -e "  ${T_WARN}b)${RST} Go back"
    echo ""

    local choice
    echo -en "${T_DIM}Select data directory [1-$((i-1))]:${RST} "
    read -r choice

    if [[ "$choice" == "b" || "$choice" == "B" ]]; then
        return 2
    fi

    if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice < i )); then
        MBTC_DATADIR="${found_array[$((choice-1))]}"

        # Confirm with user
        echo ""
        if prompt_yn "Use $MBTC_DATADIR as data directory?"; then
            msg_ok "Selected: $MBTC_DATADIR"
            return 0
        else
            return 1
        fi
    fi

    msg_err "Invalid selection"
    return 1
}

# ═══════════════════════════════════════════════════════════════════════════════
# COOKIE AUTH DETECTION
# ═══════════════════════════════════════════════════════════════════════════════

get_network_datadir() {
    local base="$1"
    local network="$2"

    case "$network" in
        test|testnet) echo "$base/testnet3" ;;
        signet)       echo "$base/signet" ;;
        regtest)      echo "$base/regtest" ;;
        *)            echo "$base" ;;
    esac
}

find_cookie() {
    [[ -n "$MBTC_COOKIE_PATH" && -f "$MBTC_COOKIE_PATH" ]] && return 0

    local effective_datadir
    effective_datadir=$(get_network_datadir "$MBTC_DATADIR" "$MBTC_NETWORK")

    if [[ -f "$effective_datadir/.cookie" ]]; then
        MBTC_COOKIE_PATH="$effective_datadir/.cookie"
        return 0
    fi

    [[ -f "$MBTC_DATADIR/.cookie" ]] && MBTC_COOKIE_PATH="$MBTC_DATADIR/.cookie" && return 0

    return 1
}

# ═══════════════════════════════════════════════════════════════════════════════
# CLI COMMAND BUILDER & TEST
# ═══════════════════════════════════════════════════════════════════════════════

get_cli_command() {
    local cmd="${MBTC_CLI_PATH:-bitcoin-cli}"

    [[ -n "$MBTC_DATADIR" ]] && cmd+=" -datadir=$MBTC_DATADIR"
    [[ -n "$MBTC_CONF" ]] && cmd+=" -conf=$MBTC_CONF"

    case "$MBTC_NETWORK" in
        test)   cmd+=" -testnet" ;;
        signet) cmd+=" -signet" ;;
        regtest) cmd+=" -regtest" ;;
    esac

    echo "$cmd"
}

test_rpc_connection() {
    local cli_cmd
    cli_cmd=$(get_cli_command)

    # Try a simple RPC call
    local result
    result=$($cli_cmd getblockchaininfo 2>&1)

    if [[ $? -eq 0 ]] && [[ "$result" != *"error"* ]]; then
        return 0
    fi

    return 1
}

# ═══════════════════════════════════════════════════════════════════════════════
# MANUAL INPUT FUNCTIONS
# ═══════════════════════════════════════════════════════════════════════════════

manual_enter_conf() {
    echo ""
    echo -e "${T_SECONDARY}Enter path to bitcoin.conf${RST}"
    echo -e "${T_DIM}(or 'b' to go back)${RST}"
    echo ""

    local input
    echo -en "${T_INFO}Path:${RST} "
    read -r input

    if [[ "$input" == "b" || "$input" == "B" ]]; then
        return 2
    fi

    # Expand ~ if used
    input="${input/#\~/$HOME}"

    if [[ -f "$input" ]]; then
        MBTC_CONF="$input"
        msg_ok "Config file set: $MBTC_CONF"

        # Check if datadir is in same location
        local conf_dir
        conf_dir=$(dirname "$input")
        if [[ -z "$MBTC_DATADIR" ]] && validate_datadir "$conf_dir"; then
            MBTC_DATADIR="$conf_dir"
            msg_ok "Also found datadir: $MBTC_DATADIR"
        fi
        return 0
    else
        msg_err "File not found: $input"
        return 1
    fi
}

manual_enter_datadir() {
    echo ""
    echo -e "${T_SECONDARY}Enter path to Bitcoin data directory${RST}"
    echo -e "${T_DIM}(or 'b' to go back)${RST}"
    echo ""

    local input
    echo -en "${T_INFO}Path:${RST} "
    read -r input

    if [[ "$input" == "b" || "$input" == "B" ]]; then
        return 2
    fi

    input="${input/#\~/$HOME}"

    if validate_datadir "$input"; then
        MBTC_DATADIR="$input"
        msg_ok "Data directory set: $MBTC_DATADIR"

        # Check for conf in this dir
        if [[ -z "$MBTC_CONF" && -f "$input/bitcoin.conf" ]]; then
            MBTC_CONF="$input/bitcoin.conf"
            msg_ok "Also found config: $MBTC_CONF"
        fi
        return 0
    elif [[ -d "$input" ]]; then
        msg_warn "Directory exists but doesn't look like a Bitcoin datadir"
        if prompt_yn "Use it anyway?"; then
            MBTC_DATADIR="$input"
            return 0
        fi
        return 1
    else
        msg_err "Directory not found: $input"
        return 1
    fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# DISPLAY RESULTS
# ═══════════════════════════════════════════════════════════════════════════════

display_detection_results() {
    echo ""
    print_header "Detection Results"
    echo ""

    print_kv "Bitcoin CLI" "${MBTC_CLI_PATH:-not found}" 18
    print_kv "Version" "${MBTC_VERSION:-unknown}" 18
    print_kv "Data Directory" "${MBTC_DATADIR:-not found}" 18
    print_kv "Config File" "${MBTC_CONF:-not found}" 18
    print_kv "Network" "${MBTC_NETWORK}" 18
    print_kv "RPC Host:Port" "${MBTC_RPC_HOST}:${MBTC_RPC_PORT}" 18

    if [[ -n "$MBTC_COOKIE_PATH" && -f "$MBTC_COOKIE_PATH" ]]; then
        print_kv "Auth Method" "Cookie" 18
        print_kv "Cookie File" "$MBTC_COOKIE_PATH" 18
    elif [[ -n "$MBTC_RPC_USER" ]]; then
        print_kv "Auth Method" "User/Password" 18
        print_kv "RPC User" "$MBTC_RPC_USER" 18
    else
        print_kv "Auth Method" "Default" 18
    fi

    if [[ "$MBTC_RUNNING" -eq 1 ]]; then
        echo ""
        echo -e "  ${T_SUCCESS}${SYM_CHECK} bitcoind is running${RST}"
    fi

    echo ""
    echo -e "${T_DIM}Full CLI command:${RST}"
    echo -e "  ${BWHITE}$(get_cli_command)${RST}"
    echo ""
}

# ═══════════════════════════════════════════════════════════════════════════════
# MAIN DETECTION FLOW
# ═══════════════════════════════════════════════════════════════════════════════

run_detection() {
    print_header "Bitcoin Core Detection"

    # ─────────────────────────────────────────────────────────────────────────
    # STEP 1: Check cache
    # ─────────────────────────────────────────────────────────────────────────
    print_section "Step 1: Checking Cached Configuration"

    if load_cache; then
        display_cached_config

        echo -e "${T_WARN}?${RST} Is this configuration correct?"
        echo ""
        echo -e "  ${T_INFO}1)${RST} Yes, use this configuration"
        echo -e "  ${T_INFO}2)${RST} No, run auto-detection"
        echo -e "  ${T_INFO}3)${RST} No, enter settings manually"
        echo ""

        local choice
        echo -en "${T_DIM}Choice [1-3]:${RST} "
        read -r choice

        case "$choice" in
            1)
                msg_ok "Using cached configuration"
                # Still need to get version and test
                detect_bitcoin_cli
                find_cookie
                if [[ -n "$MBTC_CONF" ]]; then
                    parse_conf_file "$MBTC_CONF"
                fi
                print_section_end
                # Skip to RPC test
                goto_rpc_test=1
                ;;
            2)
                msg_info "Running auto-detection..."
                # Clear cached values
                MBTC_CLI_PATH=""
                MBTC_DATADIR=""
                MBTC_CONF=""
                print_section_end
                ;;
            3)
                msg_info "Manual configuration..."
                MBTC_CLI_PATH=""
                MBTC_DATADIR=""
                MBTC_CONF=""
                print_section_end
                goto_manual=1
                ;;
            *)
                msg_info "Running auto-detection..."
                MBTC_CLI_PATH=""
                MBTC_DATADIR=""
                MBTC_CONF=""
                print_section_end
                ;;
        esac
    else
        msg_info "No cached configuration found"
        print_section_end
    fi

    # Skip detection if using cache
    if [[ "${goto_rpc_test:-0}" -eq 1 ]]; then
        # Jump to RPC test
        :
    elif [[ "${goto_manual:-0}" -eq 1 ]]; then
        # Manual configuration flow
        print_section "Manual Configuration"

        # Manual conf entry
        while true; do
            manual_enter_conf
            local result=$?
            [[ $result -eq 0 ]] && break
            [[ $result -eq 2 ]] && break  # Go back (but nowhere to go)
        done

        # Manual datadir if not found
        if [[ -z "$MBTC_DATADIR" ]]; then
            while true; do
                manual_enter_datadir
                local result=$?
                [[ $result -eq 0 ]] && break
                [[ $result -eq 2 ]] && break
            done
        fi

        detect_bitcoin_cli
        print_section_end
    else
        # ─────────────────────────────────────────────────────────────────────
        # STEP 2: Check running process
        # ─────────────────────────────────────────────────────────────────────
        print_section "Step 2: Checking Running Processes"

        start_spinner "Scanning for bitcoind process"
        if detect_running_process; then
            stop_spinner 0 "Found running bitcoind (PID: $(pgrep bitcoind | head -1))"
            [[ -n "$MBTC_DATADIR" ]] && msg_ok "Extracted datadir: $MBTC_DATADIR"
            [[ -n "$MBTC_CONF" ]] && msg_ok "Extracted conf: $MBTC_CONF"
        else
            stop_spinner 0 "bitcoind not running"

            # Check systemd
            msg_info "Checking systemd services..."
            if detect_systemd_service; then
                msg_ok "Found configuration from systemd service"
                [[ -n "$MBTC_DATADIR" ]] && msg_ok "Datadir: $MBTC_DATADIR"
                [[ -n "$MBTC_CONF" ]] && msg_ok "Conf: $MBTC_CONF"
            else
                msg_info "No systemd bitcoin service found"
            fi
        fi
        print_section_end

        # ─────────────────────────────────────────────────────────────────────
        # STEP 3: Find config file
        # ─────────────────────────────────────────────────────────────────────
        print_section "Step 3: Locating Config File"

        start_spinner "Searching common locations"
        if find_conf_file; then
            stop_spinner 0 "Found: $MBTC_CONF"
        else
            stop_spinner 1 "Config file not found in common locations"

            echo ""
            echo -e "${T_WARN}?${RST} How would you like to proceed?"
            echo ""
            echo -e "  ${T_INFO}1)${RST} Search entire system ${T_DIM}(may take a LONG time)${RST}"
            echo -e "  ${T_INFO}2)${RST} Enter path manually"
            echo -e "  ${T_INFO}3)${RST} Skip ${T_DIM}(continue without config file)${RST}"
            echo ""

            local choice
            echo -en "${T_DIM}Choice [1-3]:${RST} "
            read -r choice

            case "$choice" in
                1)
                    search_conf_file
                    ;;
                2)
                    while true; do
                        manual_enter_conf
                        local result=$?
                        [[ $result -eq 0 ]] && break
                        [[ $result -eq 2 ]] && break
                    done
                    ;;
                3)
                    msg_info "Skipping config file"
                    ;;
            esac
        fi

        # Parse config if we have it
        if [[ -n "$MBTC_CONF" && -f "$MBTC_CONF" ]]; then
            msg_info "Parsing config file..."
            parse_conf_file "$MBTC_CONF"
            [[ -n "$MBTC_DATADIR" ]] && msg_ok "Found datadir in config: $MBTC_DATADIR"
        fi
        print_section_end

        # ─────────────────────────────────────────────────────────────────────
        # STEP 4: Find data directory
        # ─────────────────────────────────────────────────────────────────────
        print_section "Step 4: Locating Data Directory"

        if [[ -n "$MBTC_DATADIR" ]] && validate_datadir "$MBTC_DATADIR"; then
            msg_ok "Already found: $MBTC_DATADIR"
        else
            start_spinner "Searching common locations"
            if find_datadir; then
                stop_spinner 0 "Found: $MBTC_DATADIR"
            else
                stop_spinner 1 "Data directory not found in common locations"

                echo ""
                echo -e "${T_WARN}?${RST} How would you like to proceed?"
                echo ""
                echo -e "  ${T_INFO}1)${RST} Search entire system for blockchain data ${T_DIM}(VERY slow!)${RST}"
                echo -e "  ${T_INFO}2)${RST} Enter path manually"
                echo -e "  ${T_INFO}3)${RST} Skip ${T_DIM}(continue without datadir)${RST}"
                echo ""

                local choice
                echo -en "${T_DIM}Choice [1-3]:${RST} "
                read -r choice

                case "$choice" in
                    1)
                        search_datadir
                        ;;
                    2)
                        while true; do
                            manual_enter_datadir
                            local result=$?
                            [[ $result -eq 0 ]] && break
                            [[ $result -eq 2 ]] && break
                        done
                        ;;
                    3)
                        msg_info "Skipping data directory"
                        ;;
                esac
            fi
        fi
        print_section_end

        # ─────────────────────────────────────────────────────────────────────
        # STEP 5: Find bitcoin-cli
        # ─────────────────────────────────────────────────────────────────────
        print_section "Step 5: Testing bitcoin-cli"

        start_spinner "Checking bitcoin-cli"
        if detect_bitcoin_cli; then
            stop_spinner 0 "Found: $MBTC_CLI_PATH ($MBTC_VERSION)"
        else
            stop_spinner 1 "bitcoin-cli not found"
            msg_err "Bitcoin Core does not appear to be installed"
            print_section_end
            return 1
        fi
        print_section_end
    fi

    # ─────────────────────────────────────────────────────────────────────────
    # STEP 6: Find cookie auth
    # ─────────────────────────────────────────────────────────────────────────
    print_section "Step 6: Checking Authentication"

    find_cookie
    if [[ -n "$MBTC_COOKIE_PATH" && -f "$MBTC_COOKIE_PATH" ]]; then
        msg_ok "Cookie auth: $MBTC_COOKIE_PATH"
    elif [[ -n "$MBTC_RPC_USER" ]]; then
        msg_ok "User/password auth configured"
    else
        msg_info "Using default authentication"
    fi
    print_section_end

    # ─────────────────────────────────────────────────────────────────────────
    # STEP 7: Test RPC connection
    # ─────────────────────────────────────────────────────────────────────────
    print_section "Step 7: Testing RPC Connection"

    echo ""
    echo -e "${T_DIM}Testing command: $(get_cli_command) getblockchaininfo${RST}"
    echo ""

    start_spinner "Connecting to Bitcoin Core"
    if test_rpc_connection; then
        stop_spinner 0 ""
        echo ""
        echo -e "  ${T_SUCCESS}${BOLD}╔════════════════════════════════════════╗${RST}"
        echo -e "  ${T_SUCCESS}${BOLD}║   bitcoin-cli TEST SUCCESSFUL!         ║${RST}"
        echo -e "  ${T_SUCCESS}${BOLD}╚════════════════════════════════════════╝${RST}"
        echo ""
    else
        stop_spinner 1 "RPC connection failed"
        msg_warn "Could not connect to Bitcoin Core RPC"
        msg_info "bitcoind may not be running, or auth settings may be incorrect"
    fi
    print_section_end

    # ─────────────────────────────────────────────────────────────────────────
    # Save and display results
    # ─────────────────────────────────────────────────────────────────────────
    save_cache
    display_detection_results

    return 0
}

# Export functions
export -f get_cli_command
