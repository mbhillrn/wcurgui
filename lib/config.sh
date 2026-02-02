#!/bin/bash
# MBTC-DASH - Shared Configuration
# Handles loading/saving config that all scripts share

# ═══════════════════════════════════════════════════════════════════════════════
# CONFIGURATION PATHS
# ═══════════════════════════════════════════════════════════════════════════════

# Use local data folder within the project
MBTC_BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export MBTC_CONFIG_DIR="$MBTC_BASE_DIR/data"
export MBTC_DATA_DIR="$MBTC_BASE_DIR/data"
export MBTC_CACHE_FILE="$MBTC_CONFIG_DIR/config.conf"
export MBTC_DB_FILE="$MBTC_DATA_DIR/peers.db"

# ═══════════════════════════════════════════════════════════════════════════════
# ENVIRONMENT VARIABLES (MBTC_ prefix)
# ═══════════════════════════════════════════════════════════════════════════════

# These are set when config is loaded
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
export MBTC_WEB_PORT="58333"
export MBTC_CONFIGURED=0

# ═══════════════════════════════════════════════════════════════════════════════
# CONFIG FILE FUNCTIONS
# ═══════════════════════════════════════════════════════════════════════════════

# Load configuration from cache file
# Returns: 0 if loaded successfully, 1 if no config exists
load_config() {
    [[ ! -f "$MBTC_CACHE_FILE" ]] && return 1

    # Source the config file to load variables
    source "$MBTC_CACHE_FILE" 2>/dev/null || return 1

    # Validate we have at least CLI path
    [[ -z "$MBTC_CLI_PATH" ]] && return 1

    MBTC_CONFIGURED=1
    return 0
}

# Save current configuration to cache file
save_config() {
    mkdir -p "$MBTC_CONFIG_DIR"

    cat > "$MBTC_CACHE_FILE" << EOF
# MBTC-DASH Configuration
# Generated: $(date)

MBTC_CLI_PATH="$MBTC_CLI_PATH"
MBTC_DATADIR="$MBTC_DATADIR"
MBTC_CONF="$MBTC_CONF"
MBTC_NETWORK="$MBTC_NETWORK"
MBTC_RPC_HOST="$MBTC_RPC_HOST"
MBTC_RPC_PORT="$MBTC_RPC_PORT"
MBTC_RPC_USER="$MBTC_RPC_USER"
MBTC_COOKIE_PATH="$MBTC_COOKIE_PATH"
MBTC_WEB_PORT="${MBTC_WEB_PORT:-58333}"
MBTC_CONFIGURED=1
EOF
    chmod 600 "$MBTC_CACHE_FILE"
}

# Check if config exists and is valid
config_exists() {
    [[ -f "$MBTC_CACHE_FILE" ]] && load_config &>/dev/null
}

# Clear saved configuration
clear_config() {
    rm -f "$MBTC_CACHE_FILE"
    MBTC_CLI_PATH=""
    MBTC_DATADIR=""
    MBTC_CONF=""
    MBTC_NETWORK="main"
    MBTC_RPC_HOST="127.0.0.1"
    MBTC_RPC_PORT="8332"
    MBTC_RPC_USER=""
    MBTC_RPC_PASS=""
    MBTC_COOKIE_PATH=""
    MBTC_VERSION=""
    MBTC_WEB_PORT="58333"
    MBTC_CONFIGURED=0
}

# ═══════════════════════════════════════════════════════════════════════════════
# CLI COMMAND BUILDER
# ═══════════════════════════════════════════════════════════════════════════════

# Build bitcoin-cli command with all necessary flags
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

# Run a bitcoin-cli command
run_cli() {
    local cli_cmd
    cli_cmd=$(get_cli_command)
    $cli_cmd "$@"
}

# Test RPC connection
test_rpc() {
    run_cli getblockchaininfo &>/dev/null
}

# ═══════════════════════════════════════════════════════════════════════════════
# INITIALIZATION
# ═══════════════════════════════════════════════════════════════════════════════

# Ensure directories exist
init_dirs() {
    mkdir -p "$MBTC_CONFIG_DIR"
    mkdir -p "$MBTC_DATA_DIR"
}

# Auto-load config on source (but don't fail if not found)
init_dirs
load_config 2>/dev/null || true
