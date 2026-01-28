#!/bin/bash
# WCURGUI - Bitcoin Core Detection
# Detects Bitcoin Core installation, datadir, conf, and auth settings

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/ui.sh"

# ═══════════════════════════════════════════════════════════════════════════════
# CONFIGURATION
# ═══════════════════════════════════════════════════════════════════════════════

# Cache file location
CACHE_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/wcurgui"
CACHE_FILE="$CACHE_DIR/detection_cache.json"

# Detection results (exported for other scripts)
export BITCOIN_CLI_PATH=""
export BITCOIN_DATADIR=""
export BITCOIN_CONF=""
export BITCOIN_NETWORK="main"   # main, test, signet, regtest
export BITCOIN_RPC_HOST="127.0.0.1"
export BITCOIN_RPC_PORT="8332"
export BITCOIN_RPC_USER=""
export BITCOIN_RPC_PASS=""
export BITCOIN_COOKIE_PATH=""
export BITCOIN_VERSION=""
export BITCOIN_RUNNING=0
export BITCOIN_DETECTION_METHOD=""

# Common datadir locations to search (Linux)
DATADIR_CANDIDATES=(
    "$HOME/.bitcoin"
    "/var/lib/bitcoind"
    "/var/lib/bitcoin"
    "/srv/bitcoin"
    "/data/bitcoin"
    "/opt/bitcoin/data"
    "/home/bitcoin/.bitcoin"
)

# Fallback binary search locations (only used if bitcoin-cli not in PATH)
BINARY_SEARCH_PATHS=(
    "/usr/bin"
    "/usr/local/bin"
    "/opt/bitcoin/bin"
    "/snap/bin"
    "$HOME/bin"
    "$HOME/.local/bin"
)

# ═══════════════════════════════════════════════════════════════════════════════
# CACHE FUNCTIONS
# ═══════════════════════════════════════════════════════════════════════════════

save_cache() {
    mkdir -p "$CACHE_DIR"
    cat > "$CACHE_FILE" << EOF
{
    "cli_path": "$BITCOIN_CLI_PATH",
    "datadir": "$BITCOIN_DATADIR",
    "conf": "$BITCOIN_CONF",
    "network": "$BITCOIN_NETWORK",
    "rpc_host": "$BITCOIN_RPC_HOST",
    "rpc_port": "$BITCOIN_RPC_PORT",
    "cookie_path": "$BITCOIN_COOKIE_PATH",
    "timestamp": "$(date -Iseconds)"
}
EOF
    chmod 600 "$CACHE_FILE"
}

load_cache() {
    [[ ! -f "$CACHE_FILE" ]] && return 1

    local cached
    cached=$(cat "$CACHE_FILE" 2>/dev/null) || return 1

    if command -v jq &>/dev/null; then
        BITCOIN_CLI_PATH=$(echo "$cached" | jq -r '.cli_path // empty')
        BITCOIN_DATADIR=$(echo "$cached" | jq -r '.datadir // empty')
        BITCOIN_CONF=$(echo "$cached" | jq -r '.conf // empty')
        BITCOIN_NETWORK=$(echo "$cached" | jq -r '.network // "main"')
        BITCOIN_RPC_HOST=$(echo "$cached" | jq -r '.rpc_host // "127.0.0.1"')
        BITCOIN_RPC_PORT=$(echo "$cached" | jq -r '.rpc_port // "8332"')
        BITCOIN_COOKIE_PATH=$(echo "$cached" | jq -r '.cookie_path // empty')
    fi

    # Validate cached cli still works
    if [[ -n "$BITCOIN_CLI_PATH" ]]; then
        "$BITCOIN_CLI_PATH" --version &>/dev/null && return 0
    fi

    return 1
}

# ═══════════════════════════════════════════════════════════════════════════════
# PROCESS DETECTION - Check if bitcoind is running
# ═══════════════════════════════════════════════════════════════════════════════

detect_running_process() {
    local pinfo
    pinfo=$(pgrep -a bitcoind 2>/dev/null | head -1) || return 1
    [[ -z "$pinfo" ]] && return 1

    BITCOIN_RUNNING=1
    BITCOIN_DETECTION_METHOD="process"

    # Extract arguments from running process
    local args
    args=$(echo "$pinfo" | cut -d' ' -f3-)

    # Parse -datadir
    if [[ "$args" =~ -datadir=([^[:space:]]+) ]]; then
        BITCOIN_DATADIR="${BASH_REMATCH[1]}"
    fi

    # Parse -conf
    if [[ "$args" =~ -conf=([^[:space:]]+) ]]; then
        BITCOIN_CONF="${BASH_REMATCH[1]}"
    fi

    # Parse network flags
    if [[ "$args" =~ -testnet ]]; then
        BITCOIN_NETWORK="test"
        BITCOIN_RPC_PORT="18332"
    elif [[ "$args" =~ -signet ]]; then
        BITCOIN_NETWORK="signet"
        BITCOIN_RPC_PORT="38332"
    elif [[ "$args" =~ -regtest ]]; then
        BITCOIN_NETWORK="regtest"
        BITCOIN_RPC_PORT="18443"
    fi

    # Parse RPC settings from args
    [[ "$args" =~ -rpcport=([0-9]+) ]] && BITCOIN_RPC_PORT="${BASH_REMATCH[1]}"
    [[ "$args" =~ -rpcuser=([^[:space:]]+) ]] && BITCOIN_RPC_USER="${BASH_REMATCH[1]}"
    [[ "$args" =~ -rpcpassword=([^[:space:]]+) ]] && BITCOIN_RPC_PASS="${BASH_REMATCH[1]}"
    [[ "$args" =~ -rpccookiefile=([^[:space:]]+) ]] && BITCOIN_COOKIE_PATH="${BASH_REMATCH[1]}"

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
        systemctl is-active --quiet "$service" 2>/dev/null || continue

        BITCOIN_DETECTION_METHOD="systemd"

        local exec_start
        exec_start=$(systemctl show "$service" --property=ExecStart 2>/dev/null)

        [[ "$exec_start" =~ -datadir=([^[:space:]\;]+) ]] && BITCOIN_DATADIR="${BASH_REMATCH[1]}"
        [[ "$exec_start" =~ -conf=([^[:space:]\;]+) ]] && BITCOIN_CONF="${BASH_REMATCH[1]}"

        [[ -n "$BITCOIN_DATADIR" ]] && return 0
    done

    return 1
}

# ═══════════════════════════════════════════════════════════════════════════════
# BITCOIN-CLI DETECTION
# The smart way: just try it first, only search if "command not found"
# ═══════════════════════════════════════════════════════════════════════════════

detect_bitcoin_cli() {
    # Already found?
    [[ -n "$BITCOIN_CLI_PATH" && -x "$BITCOIN_CLI_PATH" ]] && return 0

    # Just try running bitcoin-cli directly
    local result
    result=$(bitcoin-cli --version 2>&1)
    local exit_code=$?

    # If it worked, we're done
    if [[ $exit_code -eq 0 ]]; then
        BITCOIN_CLI_PATH=$(command -v bitcoin-cli)
        BITCOIN_VERSION=$(echo "$result" | head -1 | grep -oP 'v[\d.]+' || echo "unknown")
        BITCOIN_DETECTION_METHOD="${BITCOIN_DETECTION_METHOD:-path}"
        return 0
    fi

    # Check if it's "command not found" vs some other error
    if [[ "$result" == *"command not found"* ]] || [[ "$result" == *"not found"* ]]; then
        # Not in PATH - need to search for it
        msg_warn "bitcoin-cli not in PATH, searching common locations..."

        for dir in "${BINARY_SEARCH_PATHS[@]}"; do
            if [[ -x "$dir/bitcoin-cli" ]]; then
                # Found it, verify it works
                local test_result
                test_result=$("$dir/bitcoin-cli" --version 2>&1)
                if [[ $? -eq 0 ]]; then
                    BITCOIN_CLI_PATH="$dir/bitcoin-cli"
                    BITCOIN_VERSION=$(echo "$test_result" | head -1 | grep -oP 'v[\d.]+' || echo "unknown")
                    BITCOIN_DETECTION_METHOD="search"
                    return 0
                fi
            fi
        done

        # Really not found - probably not installed
        msg_err "bitcoin-cli not found - is Bitcoin Core installed?"
        return 1
    fi

    # Some other error (not "command not found") - cli exists but errored
    # This shouldn't happen with --version, but handle it
    BITCOIN_CLI_PATH=$(command -v bitcoin-cli 2>/dev/null)
    if [[ -n "$BITCOIN_CLI_PATH" ]]; then
        BITCOIN_VERSION="unknown"
        return 0
    fi

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

    # Check for testnet/signet/regtest subdirs
    for subdir in testnet3 signet regtest; do
        [[ -d "$dir/$subdir/blocks" ]] && return 0
    done

    return 1
}

find_datadir() {
    # Already found from process/systemd?
    [[ -n "$BITCOIN_DATADIR" ]] && validate_datadir "$BITCOIN_DATADIR" && return 0

    # Check default first
    if validate_datadir "$HOME/.bitcoin"; then
        BITCOIN_DATADIR="$HOME/.bitcoin"
        return 0
    fi

    # Check candidate locations
    for dir in "${DATADIR_CANDIDATES[@]}"; do
        if validate_datadir "$dir"; then
            BITCOIN_DATADIR="$dir"
            return 0
        fi
    done

    # Check mounted drives
    for mount in /mnt/* /media/*/* /data/*; do
        [[ -d "$mount" ]] || continue
        for subdir in bitcoin .bitcoin bitcoind; do
            if validate_datadir "$mount/$subdir"; then
                BITCOIN_DATADIR="$mount/$subdir"
                return 0
            fi
        done
    done 2>/dev/null

    return 1
}

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

# ═══════════════════════════════════════════════════════════════════════════════
# CONFIG FILE DETECTION
# ═══════════════════════════════════════════════════════════════════════════════

parse_conf_file() {
    local conf="$1"
    [[ ! -f "$conf" ]] && return 1

    while IFS='=' read -r key value; do
        [[ "$key" =~ ^[[:space:]]*# ]] && continue
        [[ -z "$key" ]] && continue

        key=$(echo "$key" | xargs)
        value=$(echo "$value" | xargs)

        case "$key" in
            datadir)     [[ -z "$BITCOIN_DATADIR" ]] && BITCOIN_DATADIR="$value" ;;
            testnet)     [[ "$value" == "1" ]] && BITCOIN_NETWORK="test" && BITCOIN_RPC_PORT="18332" ;;
            signet)      [[ "$value" == "1" ]] && BITCOIN_NETWORK="signet" && BITCOIN_RPC_PORT="38332" ;;
            regtest)     [[ "$value" == "1" ]] && BITCOIN_NETWORK="regtest" && BITCOIN_RPC_PORT="18443" ;;
            rpcuser)     BITCOIN_RPC_USER="$value" ;;
            rpcpassword) BITCOIN_RPC_PASS="$value" ;;
            rpcport)     BITCOIN_RPC_PORT="$value" ;;
            rpcbind)     [[ "$BITCOIN_RPC_HOST" == "127.0.0.1" ]] && BITCOIN_RPC_HOST="$value" ;;
            rpccookiefile) BITCOIN_COOKIE_PATH="$value" ;;
        esac
    done < "$conf"
    return 0
}

find_and_parse_conf() {
    # If conf already set, validate it
    if [[ -n "$BITCOIN_CONF" && -f "$BITCOIN_CONF" ]]; then
        parse_conf_file "$BITCOIN_CONF"
        return 0
    fi

    # Look in datadir
    if [[ -n "$BITCOIN_DATADIR" && -f "$BITCOIN_DATADIR/bitcoin.conf" ]]; then
        BITCOIN_CONF="$BITCOIN_DATADIR/bitcoin.conf"
        parse_conf_file "$BITCOIN_CONF"
        return 0
    fi

    # Check common system locations
    for conf in /etc/bitcoin/bitcoin.conf /etc/bitcoind/bitcoin.conf; do
        if [[ -f "$conf" ]]; then
            BITCOIN_CONF="$conf"
            parse_conf_file "$BITCOIN_CONF"
            return 0
        fi
    done

    return 1
}

# ═══════════════════════════════════════════════════════════════════════════════
# COOKIE AUTH DETECTION
# ═══════════════════════════════════════════════════════════════════════════════

find_cookie() {
    [[ -n "$BITCOIN_COOKIE_PATH" && -f "$BITCOIN_COOKIE_PATH" ]] && return 0

    local effective_datadir
    effective_datadir=$(get_network_datadir "$BITCOIN_DATADIR" "$BITCOIN_NETWORK")

    if [[ -f "$effective_datadir/.cookie" ]]; then
        BITCOIN_COOKIE_PATH="$effective_datadir/.cookie"
        return 0
    fi

    [[ -f "$BITCOIN_DATADIR/.cookie" ]] && BITCOIN_COOKIE_PATH="$BITCOIN_DATADIR/.cookie" && return 0

    return 1
}

# ═══════════════════════════════════════════════════════════════════════════════
# CLI COMMAND BUILDER
# ═══════════════════════════════════════════════════════════════════════════════

get_cli_command() {
    local cmd="${BITCOIN_CLI_PATH:-bitcoin-cli}"

    [[ -n "$BITCOIN_DATADIR" ]] && cmd+=" -datadir=$BITCOIN_DATADIR"
    [[ -n "$BITCOIN_CONF" ]] && cmd+=" -conf=$BITCOIN_CONF"

    case "$BITCOIN_NETWORK" in
        test)   cmd+=" -testnet" ;;
        signet) cmd+=" -signet" ;;
        regtest) cmd+=" -regtest" ;;
    esac

    echo "$cmd"
}

# ═══════════════════════════════════════════════════════════════════════════════
# MAIN DETECTION FUNCTION
# ═══════════════════════════════════════════════════════════════════════════════

run_detection() {
    print_section "Bitcoin Core Detection"

    # Step 1: Check cache first
    print_step 1 5 "Checking cached configuration"
    if load_cache; then
        msg_ok "Using cached configuration"
        BITCOIN_DETECTION_METHOD="cache"
        display_detection_results
        print_section_end
        return 0
    fi
    msg_info "No valid cache, running fresh detection"

    # Step 2: Check for running bitcoind process
    print_step 2 5 "Checking for running bitcoind"
    start_spinner "Scanning processes"
    if detect_running_process; then
        stop_spinner 0 "Found running bitcoind (PID: $(pgrep bitcoind | head -1))"
    else
        stop_spinner 0 "bitcoind not running"
    fi

    # Also check systemd
    if [[ -z "$BITCOIN_DATADIR" ]]; then
        detect_systemd_service && msg_ok "Found systemd service config"
    fi

    # Step 3: Check bitcoin-cli (the smart way)
    print_step 3 5 "Checking bitcoin-cli"
    start_spinner "Testing bitcoin-cli"
    if detect_bitcoin_cli; then
        stop_spinner 0 "Found: $BITCOIN_CLI_PATH ($BITCOIN_VERSION)"
    else
        stop_spinner 1 "bitcoin-cli not available"
        print_section_end
        return 1
    fi

    # Step 4: Find datadir
    print_step 4 5 "Locating data directory"
    start_spinner "Searching"
    if find_datadir; then
        stop_spinner 0 "Found: $BITCOIN_DATADIR"
    else
        stop_spinner 1 "Could not locate datadir"
    fi

    # Step 5: Find config and auth settings
    print_step 5 5 "Reading configuration"
    start_spinner "Parsing"
    find_and_parse_conf
    find_cookie

    if [[ -n "$BITCOIN_COOKIE_PATH" && -f "$BITCOIN_COOKIE_PATH" ]]; then
        stop_spinner 0 "Cookie auth: $BITCOIN_COOKIE_PATH"
    elif [[ -n "$BITCOIN_RPC_USER" ]]; then
        stop_spinner 0 "User/pass auth configured"
    else
        stop_spinner 0 "Using defaults"
    fi

    # Save what we found
    save_cache

    display_detection_results
    print_section_end
    return 0
}

# ═══════════════════════════════════════════════════════════════════════════════
# DISPLAY RESULTS
# ═══════════════════════════════════════════════════════════════════════════════

display_detection_results() {
    echo ""
    echo -e "${T_PRIMARY}${BOX_H}${BOX_H}${BOX_H} Detection Results ${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${RST}"
    echo ""

    print_kv "Detection Method" "${BITCOIN_DETECTION_METHOD:-fresh}" 20
    print_kv "Bitcoin CLI" "${BITCOIN_CLI_PATH:-not found}" 20
    print_kv "Version" "${BITCOIN_VERSION:-unknown}" 20
    print_kv "Data Directory" "${BITCOIN_DATADIR:-not found}" 20
    print_kv "Config File" "${BITCOIN_CONF:-default}" 20
    print_kv "Network" "${BITCOIN_NETWORK}" 20
    print_kv "RPC Host:Port" "${BITCOIN_RPC_HOST}:${BITCOIN_RPC_PORT}" 20

    if [[ -n "$BITCOIN_COOKIE_PATH" && -f "$BITCOIN_COOKIE_PATH" ]]; then
        print_kv "Auth Method" "Cookie" 20
        print_kv "Cookie File" "$BITCOIN_COOKIE_PATH" 20
    elif [[ -n "$BITCOIN_RPC_USER" ]]; then
        print_kv "Auth Method" "User/Password" 20
        print_kv "RPC User" "$BITCOIN_RPC_USER" 20
    else
        print_kv "Auth Method" "Default (cookie expected)" 20
    fi

    if [[ "$BITCOIN_RUNNING" -eq 1 ]]; then
        echo ""
        echo -e "  ${T_SUCCESS}${SYM_CHECK} bitcoind is running${RST}"
    fi

    echo ""
    echo -e "${T_DIM}Full CLI command:${RST}"
    echo -e "  ${BWHITE}$(get_cli_command)${RST}"
}

# Export for other scripts
export -f get_cli_command
