#!/bin/bash
# MBTC-DASH - Peer List Display
# Shows connected peers with geo-location data

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MBTC_DIR="$(dirname "$SCRIPT_DIR")"

# Source libraries
source "$MBTC_DIR/lib/ui.sh"
source "$MBTC_DIR/lib/database.sh"

# Load detection cache if exists
CACHE_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/mbtc-dash/detection_cache.conf"
[[ -f "$CACHE_FILE" ]] && source "$CACHE_FILE"

# ═══════════════════════════════════════════════════════════════════════════════
# CONFIGURATION
# ═══════════════════════════════════════════════════════════════════════════════

REFRESH_INTERVAL=10      # Seconds between refreshes
GEO_API_DELAY=1.5        # Seconds between API calls (stay under 45/min limit)
GEO_API_URL="http://ip-api.com/json"
GEO_API_FIELDS="status,country,countryCode,region,regionName,city,district,lat,lon,isp,as,hosting,query"

# Track state
RUNNING=1
QUIT_REQUESTED=0
LAST_PEER_COUNT=0
declare -A KNOWN_PEERS      # Track known peer IDs

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
        msg_warn "Press Ctrl+C again to force quit (or 'q' to quit gracefully)"
        return
    else
        echo ""
        msg_info "Force quitting..."
        cursor_show
        stty echo 2>/dev/null
        exit 130
    fi
}

trap handle_ctrl_c SIGINT

# Cleanup on exit
cleanup() {
    cursor_show
    stty echo 2>/dev/null
    echo ""
}
trap cleanup EXIT

# ═══════════════════════════════════════════════════════════════════════════════
# NETWORK TYPE DETECTION
# ═══════════════════════════════════════════════════════════════════════════════

# Determine network type from address
get_network_type() {
    local addr="$1"

    if [[ "$addr" =~ \.onion ]]; then
        echo "onion"
    elif [[ "$addr" =~ \.i2p ]]; then
        echo "i2p"
    elif [[ "$addr" =~ ^fc || "$addr" =~ ^fd ]]; then
        # CJDNS uses fc00::/8 address space
        echo "cjdns"
    elif [[ "$addr" =~ : ]]; then
        echo "ipv6"
    else
        echo "ipv4"
    fi
}

# Check if address is public (can be geolocated)
is_public_address() {
    local network_type="$1"
    [[ "$network_type" == "ipv4" || "$network_type" == "ipv6" ]]
}

# Extract IP from addr (remove port)
extract_ip() {
    local addr="$1"

    # IPv6 with port: [2001:db8::1]:8333 -> 2001:db8::1
    if [[ "$addr" =~ ^\[([^\]]+)\] ]]; then
        echo "${BASH_REMATCH[1]}"
    # IPv4 with port: 1.2.3.4:8333 -> 1.2.3.4
    elif [[ "$addr" =~ ^([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+): ]]; then
        echo "${BASH_REMATCH[1]}"
    # Onion/I2P: keep as-is but remove port
    elif [[ "$addr" =~ ^([^:]+): ]]; then
        echo "${BASH_REMATCH[1]}"
    else
        echo "$addr"
    fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# GEO-LOCATION API
# ═══════════════════════════════════════════════════════════════════════════════

# Fetch geo data from API
# Returns: JSON response or empty on failure
fetch_geo_api() {
    local ip="$1"
    local url="${GEO_API_URL}/${ip}?fields=${GEO_API_FIELDS}"

    local response
    response=$(curl -s --max-time 10 "$url" 2>/dev/null)

    # Check if response is valid JSON with success status
    if [[ -n "$response" ]] && echo "$response" | jq -e '.status == "success"' &>/dev/null; then
        echo "$response"
    else
        echo ""
    fi
}

# Process geo lookup for a single IP
# Handles caching, rate limiting, retries
process_geo_lookup() {
    local ip="$1"
    local network_type="$2"

    # Private network - no geo lookup needed
    if ! is_public_address "$network_type"; then
        if ! peer_exists "$ip"; then
            insert_private_peer "$ip" "$network_type"
        else
            update_peer_seen "$ip"
        fi
        return 0
    fi

    # Check if we have cached data
    if peer_exists "$ip"; then
        if ! should_retry_geo "$ip"; then
            # Use cached data, just update last_seen
            update_peer_seen "$ip"
            return 0
        fi
    fi

    # Need to fetch from API
    local response
    response=$(fetch_geo_api "$ip")

    if [[ -n "$response" ]]; then
        # Parse response
        local country country_code region region_name city district lat lon isp as_info hosting

        country=$(echo "$response" | jq -r '.country // ""')
        country_code=$(echo "$response" | jq -r '.countryCode // ""')
        region=$(echo "$response" | jq -r '.region // ""')
        region_name=$(echo "$response" | jq -r '.regionName // ""')
        city=$(echo "$response" | jq -r '.city // ""')
        district=$(echo "$response" | jq -r '.district // ""')
        lat=$(echo "$response" | jq -r '.lat // 0')
        lon=$(echo "$response" | jq -r '.lon // 0')
        isp=$(echo "$response" | jq -r '.isp // ""')
        as_info=$(echo "$response" | jq -r '.as // ""')
        hosting=$(echo "$response" | jq -r 'if .hosting then 1 else 0 end')

        upsert_peer_geo "$ip" "$network_type" $GEO_OK \
            "$country" "$country_code" "$region" "$region_name" \
            "$city" "$district" "$lat" "$lon" "$isp" "$as_info" "$hosting"

        return 0
    else
        # API failed - mark as unavailable
        insert_unavailable_peer "$ip" "$network_type"
        return 1
    fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# PEER DATA FETCHING
# ═══════════════════════════════════════════════════════════════════════════════

# Get peer info from bitcoin-cli
get_peer_info() {
    local cli_cmd="${MBTC_CLI_PATH:-bitcoin-cli}"

    [[ -n "$MBTC_DATADIR" ]] && cli_cmd+=" -datadir=$MBTC_DATADIR"
    [[ -n "$MBTC_CONF" ]] && cli_cmd+=" -conf=$MBTC_CONF"

    case "$MBTC_NETWORK" in
        test)   cli_cmd+=" -testnet" ;;
        signet) cli_cmd+=" -signet" ;;
        regtest) cli_cmd+=" -regtest" ;;
    esac

    $cli_cmd getpeerinfo 2>/dev/null
}

# Process all peers and fetch missing geo data
# Shows progress bar for new lookups
process_peers() {
    local peer_json="$1"

    # Get list of IPs that need API lookup
    local -a new_ips=()
    local -a all_peers=()

    # Parse peer data
    local peer_count
    peer_count=$(echo "$peer_json" | jq 'length')

    for ((i=0; i<peer_count; i++)); do
        local peer
        peer=$(echo "$peer_json" | jq ".[$i]")

        local addr network_type ip
        addr=$(echo "$peer" | jq -r '.addr')
        network_type=$(echo "$peer" | jq -r '.network // "ipv4"')
        ip=$(extract_ip "$addr")

        all_peers+=("$ip|$network_type")

        # Check if this IP needs API lookup
        if is_public_address "$network_type"; then
            if ! peer_exists "$ip" || should_retry_geo "$ip"; then
                new_ips+=("$ip|$network_type")
            fi
        fi
    done

    # If we have new IPs to lookup, show progress
    if [[ ${#new_ips[@]} -gt 0 ]]; then
        echo ""
        local total=${#new_ips[@]}
        local current=0

        for entry in "${new_ips[@]}"; do
            IFS='|' read -r ip network_type <<< "$entry"
            ((current++))

            # Progress bar
            local pct=$((current * 100 / total))
            local filled=$((current * 30 / total))
            local empty=$((30 - filled))

            echo -en "\r${T_INFO}Finding Accountabilibuddies:${RST} ["
            echo -en "${T_SUCCESS}$(printf '%*s' "$filled" '' | tr ' ' '█')${RST}"
            echo -en "${T_DIM}$(printf '%*s' "$empty" '' | tr ' ' '░')${RST}"
            echo -en "] ${current}/${total} ${T_DIM}(rate limited: ~1.5s each, Oh Hamburgers!)${RST}"

            # Fetch geo data
            process_geo_lookup "$ip" "$network_type"

            # Rate limit
            if [[ $current -lt $total ]]; then
                sleep "$GEO_API_DELAY"
            fi
        done

        echo ""
        msg_ok "Geo-location data updated for $total new peers"
        echo ""
    fi

    # Update last_seen for all current peers (even cached ones)
    for entry in "${all_peers[@]}"; do
        IFS='|' read -r ip network_type <<< "$entry"
        if peer_exists "$ip"; then
            update_peer_seen "$ip"
        elif ! is_public_address "$network_type"; then
            insert_private_peer "$ip" "$network_type"
        fi
    done
}

# ═══════════════════════════════════════════════════════════════════════════════
# TABLE DISPLAY
# ═══════════════════════════════════════════════════════════════════════════════

# Format bytes to human readable
format_bytes() {
    local bytes=$1
    if [[ $bytes -ge 1073741824 ]]; then
        echo "$(echo "scale=1; $bytes / 1073741824" | bc)GB"
    elif [[ $bytes -ge 1048576 ]]; then
        echo "$(echo "scale=1; $bytes / 1048576" | bc)MB"
    elif [[ $bytes -ge 1024 ]]; then
        echo "$(echo "scale=1; $bytes / 1024" | bc)KB"
    else
        echo "${bytes}B"
    fi
}

# Format location string
format_location() {
    local ip="$1"
    local network_type="$2"

    # Check network type first
    if [[ "$network_type" == "onion" || "$network_type" == "i2p" || "$network_type" == "cjdns" ]]; then
        echo "[PRIVATE LOCATION]"
        return
    fi

    # Get from database
    local geo_data
    geo_data=$(get_peer_geo "$ip")

    if [[ -z "$geo_data" ]]; then
        echo "[LOCATION UNAVAILABLE]"
        return
    fi

    local status city country_code
    status=$(echo "$geo_data" | jq -r '.geo_status // 2')
    city=$(echo "$geo_data" | jq -r '.city // ""')
    country_code=$(echo "$geo_data" | jq -r '.country_code // ""')

    if [[ "$status" -eq $GEO_PRIVATE ]]; then
        echo "[PRIVATE LOCATION]"
    elif [[ "$status" -eq $GEO_UNAVAILABLE || -z "$city" ]]; then
        echo "[LOCATION UNAVAILABLE]"
    else
        echo "${city}, ${country_code}"
    fi
}

# Truncate string to max length
truncate_str() {
    local str="$1"
    local max="$2"

    if [[ ${#str} -gt $max ]]; then
        echo "${str:0:$((max-3))}..."
    else
        echo "$str"
    fi
}

# Display peer table
display_peer_table() {
    local peer_json="$1"

    # Table header
    echo ""
    printf "${T_TABLE_HEADER}%-8s ${T_TABLE_BORDER}│${T_TABLE_HEADER} %-22s ${T_TABLE_BORDER}│${T_TABLE_HEADER} %-20s ${T_TABLE_BORDER}│${T_TABLE_HEADER} %-18s ${T_TABLE_BORDER}│${T_TABLE_HEADER} %-6s ${T_TABLE_BORDER}│${T_TABLE_HEADER} %-7s ${T_TABLE_BORDER}│${T_TABLE_HEADER} %-14s ${T_TABLE_BORDER}│${T_TABLE_HEADER} %-18s${RST}\n" \
        "ID" "Address" "Location" "ISP" "In/Out" "Ping" "Sent/Recv" "Version"

    # Separator
    printf "${T_TABLE_BORDER}─────────┼────────────────────────┼──────────────────────┼────────────────────┼────────┼─────────┼────────────────┼───────────────────${RST}\n"

    # Parse and display each peer
    local peer_count
    peer_count=$(echo "$peer_json" | jq 'length')

    for ((i=0; i<peer_count; i++)); do
        local peer
        peer=$(echo "$peer_json" | jq ".[$i]")

        local id addr network inbound ping bytessent bytesrecv subver
        local ip location isp direction ping_str sent recv version

        id=$(echo "$peer" | jq -r '.id')
        addr=$(echo "$peer" | jq -r '.addr')
        network=$(echo "$peer" | jq -r '.network // "ipv4"')
        inbound=$(echo "$peer" | jq -r '.inbound')
        ping=$(echo "$peer" | jq -r '.pingtime // .pingwait // 0')
        bytessent=$(echo "$peer" | jq -r '.bytessent // 0')
        bytesrecv=$(echo "$peer" | jq -r '.bytesrecv // 0')
        subver=$(echo "$peer" | jq -r '.subver // ""')

        # Process fields
        ip=$(extract_ip "$addr")
        location=$(format_location "$ip" "$network")
        direction=$([[ "$inbound" == "true" ]] && echo "IN" || echo "OUT")

        # Get ISP from database
        local geo_data isp_raw
        geo_data=$(get_peer_geo "$ip")
        if [[ -n "$geo_data" ]]; then
            isp_raw=$(echo "$geo_data" | jq -r '.isp // "-"')
            isp=$(truncate_str "$isp_raw" 18)
        else
            isp="-"
        fi

        # Format ping
        if [[ "$ping" == "0" || -z "$ping" ]]; then
            ping_str="-"
        else
            ping_str="$(echo "scale=0; $ping * 1000 / 1" | bc)ms"
        fi

        # Format bytes
        sent=$(format_bytes "$bytessent")
        recv=$(format_bytes "$bytesrecv")

        # Format version (remove slashes and truncate)
        version=$(truncate_str "${subver//\//}" 18)

        # Truncate address for display
        local addr_display
        addr_display=$(truncate_str "$ip" 22)

        # Alternate row colors
        local row_color=$T_TABLE_ROW
        [[ $((i % 2)) -eq 1 ]] && row_color=$T_TABLE_ALT

        printf "${row_color}%-8s ${T_TABLE_BORDER}│${row_color} %-22s ${T_TABLE_BORDER}│${row_color} %-20s ${T_TABLE_BORDER}│${row_color} %-18s ${T_TABLE_BORDER}│${row_color} %-6s ${T_TABLE_BORDER}│${row_color} %-7s ${T_TABLE_BORDER}│${row_color} %6s / %-6s ${T_TABLE_BORDER}│${row_color} %-18s${RST}\n" \
            "$id" "$addr_display" "$(truncate_str "$location" 20)" "$isp" "$direction" "$ping_str" "$sent" "$recv" "$version"
    done

    echo ""
}

# ═══════════════════════════════════════════════════════════════════════════════
# MAIN DISPLAY LOOP
# ═══════════════════════════════════════════════════════════════════════════════

show_header() {
    clear
    echo -e "${T_PRIMARY}"
    echo "═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════"
    echo "  MBTC-DASH Peer List                                                           Press 'q' to quit | Refresh: ${REFRESH_INTERVAL}s"
    echo "═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════"
    echo -e "${RST}"
}

main_loop() {
    # Initialize database
    init_database

    # Check if we have bitcoin-cli configured
    if [[ -z "$MBTC_CLI_PATH" ]] && ! command -v bitcoin-cli &>/dev/null; then
        msg_err "bitcoin-cli not found. Run da.sh first to configure."
        exit 1
    fi

    # Non-blocking input setup
    stty -echo -icanon time 0 min 0 2>/dev/null || true

    local last_refresh=0
    local peer_json=""

    while [[ $RUNNING -eq 1 ]]; do
        local now
        now=$(date +%s)

        # Check for quit key
        local key
        key=$(dd bs=1 count=1 2>/dev/null || true)
        if [[ "$key" == "q" || "$key" == "Q" ]]; then
            RUNNING=0
            break
        fi

        # Refresh data every REFRESH_INTERVAL seconds
        if [[ $((now - last_refresh)) -ge $REFRESH_INTERVAL ]]; then
            show_header

            # Fetch peer data
            echo -e "${T_DIM}Fetching peer data...${RST}"
            peer_json=$(get_peer_info)

            if [[ -z "$peer_json" || "$peer_json" == "[]" ]]; then
                msg_warn "No peers connected or bitcoind not running"
            else
                local peer_count
                peer_count=$(echo "$peer_json" | jq 'length')

                echo -e "${T_INFO}Connected peers: ${BWHITE}${peer_count}${RST}"

                # Process geo lookups (will show progress bar if needed)
                process_peers "$peer_json"

                # Display table
                display_peer_table "$peer_json"

                # Show stats
                local stats
                stats=$(get_peer_stats)
                if [[ -n "$stats" ]]; then
                    IFS='|' read -r total geo_ok private unavailable ipv4 ipv6 onion i2p cjdns <<< "$stats"
                    echo -e "${T_DIM}Database stats: ${geo_ok} geolocated | ${private} private | ${unavailable} unavailable | Networks: ${ipv4} IPv4, ${ipv6} IPv6, ${onion} Tor, ${i2p} I2P, ${cjdns} CJDNS${RST}"
                fi
            fi

            # Show last update time
            echo ""
            echo -e "${T_DIM}Last update: $(date '+%Y-%m-%d %H:%M:%S') | Next refresh in ${REFRESH_INTERVAL}s${RST}"

            last_refresh=$now
        fi

        # Small sleep to prevent CPU spin
        sleep 0.1
    done

    # Restore terminal
    stty echo icanon 2>/dev/null || true
    echo ""
    msg_ok "Peer list closed"
}

# ═══════════════════════════════════════════════════════════════════════════════
# ENTRY POINT
# ═══════════════════════════════════════════════════════════════════════════════

main_loop "$@"
