#!/bin/bash
# MBTC-DASH - SQLite Database Management
# Handles peer geo-location caching and statistics

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/colors.sh"
source "$SCRIPT_DIR/config.sh"

# ═══════════════════════════════════════════════════════════════════════════════
# DATABASE CONFIGURATION
# ═══════════════════════════════════════════════════════════════════════════════

# Use paths from config.sh
DB_DIR="$MBTC_DATA_DIR"
DB_FILE="$MBTC_DB_FILE"

# Geo status codes
GEO_OK=0
GEO_PRIVATE=1           # Onion/I2P/CJDNS - can't be geolocated
GEO_UNAVAILABLE=2       # Public IP but API failed

# Retry intervals for GEO_UNAVAILABLE (in seconds)
# 1 day, 3 days, 7 days, then 7 days forever
RETRY_INTERVALS=(86400 259200 604800 604800)

# ═══════════════════════════════════════════════════════════════════════════════
# DATABASE INITIALIZATION
# ═══════════════════════════════════════════════════════════════════════════════

init_database() {
    mkdir -p "$DB_DIR"

    sqlite3 "$DB_FILE" << 'EOF'
CREATE TABLE IF NOT EXISTS peers_geo (
    ip TEXT PRIMARY KEY,
    network_type TEXT,          -- ipv4, ipv6, onion, i2p, cjdns
    geo_status INTEGER DEFAULT 0,  -- 0=ok, 1=private, 2=unavailable
    geo_retry_count INTEGER DEFAULT 0,
    geo_last_lookup INTEGER,    -- Unix timestamp
    country TEXT,
    country_code TEXT,
    region TEXT,
    region_name TEXT,
    city TEXT,
    district TEXT,
    lat REAL,
    lon REAL,
    isp TEXT,
    as_info TEXT,
    hosting INTEGER,
    first_seen INTEGER,
    last_seen INTEGER,
    connection_count INTEGER DEFAULT 1
);

CREATE INDEX IF NOT EXISTS idx_geo_status ON peers_geo(geo_status);
CREATE INDEX IF NOT EXISTS idx_last_seen ON peers_geo(last_seen);
CREATE INDEX IF NOT EXISTS idx_network_type ON peers_geo(network_type);
EOF

    return $?
}

# ═══════════════════════════════════════════════════════════════════════════════
# PEER LOOKUP FUNCTIONS
# ═══════════════════════════════════════════════════════════════════════════════

# Check if peer exists in database
peer_exists() {
    local ip="$1"
    local count
    count=$(sqlite3 "$DB_FILE" "SELECT COUNT(*) FROM peers_geo WHERE ip = '$ip';")
    [[ "$count" -gt 0 ]]
}

# Get peer geo data from database
# Returns JSON string or empty if not found
get_peer_geo() {
    local ip="$1"
    sqlite3 -json "$DB_FILE" "SELECT * FROM peers_geo WHERE ip = '$ip' LIMIT 1;" 2>/dev/null | jq -r '.[0] // empty'
}

# Check if we should retry geo lookup for an unavailable IP
should_retry_geo() {
    local ip="$1"
    local now
    now=$(date +%s)

    local row
    row=$(sqlite3 "$DB_FILE" "SELECT geo_status, geo_retry_count, geo_last_lookup FROM peers_geo WHERE ip = '$ip';")

    [[ -z "$row" ]] && return 0  # Not in DB, should lookup

    IFS='|' read -r status retry_count last_lookup <<< "$row"

    # If status is OK or PRIVATE, no retry needed
    [[ "$status" -eq $GEO_OK || "$status" -eq $GEO_PRIVATE ]] && return 1

    # Calculate retry interval based on retry count
    local interval_idx=$retry_count
    [[ $interval_idx -ge ${#RETRY_INTERVALS[@]} ]] && interval_idx=$((${#RETRY_INTERVALS[@]} - 1))
    local interval=${RETRY_INTERVALS[$interval_idx]}

    # Check if enough time has passed
    local elapsed=$((now - last_lookup))
    [[ $elapsed -ge $interval ]]
}

# ═══════════════════════════════════════════════════════════════════════════════
# INSERT/UPDATE FUNCTIONS
# ═══════════════════════════════════════════════════════════════════════════════

# Insert or update peer with geo data
# Args: ip, network_type, geo_status, country, country_code, region, region_name, city, district, lat, lon, isp, as_info, hosting
upsert_peer_geo() {
    local ip="$1"
    local network_type="$2"
    local geo_status="$3"
    local country="$4"
    local country_code="$5"
    local region="$6"
    local region_name="$7"
    local city="$8"
    local district="$9"
    local lat="${10}"
    local lon="${11}"
    local isp="${12}"
    local as_info="${13}"
    local hosting="${14:-0}"

    local now
    now=$(date +%s)

    # Escape single quotes for SQL
    country="${country//\'/\'\'}"
    region="${region//\'/\'\'}"
    region_name="${region_name//\'/\'\'}"
    city="${city//\'/\'\'}"
    district="${district//\'/\'\'}"
    isp="${isp//\'/\'\'}"
    as_info="${as_info//\'/\'\'}"

    sqlite3 "$DB_FILE" << EOF
INSERT INTO peers_geo (
    ip, network_type, geo_status, geo_last_lookup,
    country, country_code, region, region_name, city, district,
    lat, lon, isp, as_info, hosting,
    first_seen, last_seen, connection_count
) VALUES (
    '$ip', '$network_type', $geo_status, $now,
    '$country', '$country_code', '$region', '$region_name', '$city', '$district',
    $lat, $lon, '$isp', '$as_info', $hosting,
    $now, $now, 1
)
ON CONFLICT(ip) DO UPDATE SET
    geo_status = $geo_status,
    geo_last_lookup = $now,
    geo_retry_count = CASE WHEN $geo_status = $GEO_UNAVAILABLE THEN geo_retry_count + 1 ELSE 0 END,
    country = COALESCE(NULLIF('$country', ''), country),
    country_code = COALESCE(NULLIF('$country_code', ''), country_code),
    region = COALESCE(NULLIF('$region', ''), region),
    region_name = COALESCE(NULLIF('$region_name', ''), region_name),
    city = COALESCE(NULLIF('$city', ''), city),
    district = COALESCE(NULLIF('$district', ''), district),
    lat = CASE WHEN $lat != 0 THEN $lat ELSE lat END,
    lon = CASE WHEN $lon != 0 THEN $lon ELSE lon END,
    isp = COALESCE(NULLIF('$isp', ''), isp),
    as_info = COALESCE(NULLIF('$as_info', ''), as_info),
    hosting = $hosting,
    last_seen = $now,
    connection_count = connection_count + 1;
EOF
}

# Update last_seen timestamp for a peer
update_peer_seen() {
    local ip="$1"
    local now
    now=$(date +%s)

    sqlite3 "$DB_FILE" "UPDATE peers_geo SET last_seen = $now WHERE ip = '$ip';"
}

# Insert a private network peer (onion/i2p/cjdns)
insert_private_peer() {
    local ip="$1"
    local network_type="$2"

    upsert_peer_geo "$ip" "$network_type" $GEO_PRIVATE "" "" "" "" "" "" 0 0 "" "" 0
}

# Insert peer with unavailable geo
insert_unavailable_peer() {
    local ip="$1"
    local network_type="$2"

    upsert_peer_geo "$ip" "$network_type" $GEO_UNAVAILABLE "" "" "" "" "" "" 0 0 "" "" 0
}

# ═══════════════════════════════════════════════════════════════════════════════
# QUERY FUNCTIONS
# ═══════════════════════════════════════════════════════════════════════════════

# Get total peer count
get_peer_count() {
    sqlite3 "$DB_FILE" "SELECT COUNT(*) FROM peers_geo;"
}

# Get peers by geo status
get_peers_by_status() {
    local status="$1"
    sqlite3 -json "$DB_FILE" "SELECT * FROM peers_geo WHERE geo_status = $status ORDER BY last_seen DESC;"
}

# Get all peers as JSON
get_all_peers_json() {
    sqlite3 -json "$DB_FILE" "SELECT * FROM peers_geo ORDER BY last_seen DESC;"
}

# Get peer statistics
get_peer_stats() {
    sqlite3 "$DB_FILE" << 'EOF'
SELECT
    COUNT(*) as total,
    SUM(CASE WHEN geo_status = 0 THEN 1 ELSE 0 END) as geo_ok,
    SUM(CASE WHEN geo_status = 1 THEN 1 ELSE 0 END) as private,
    SUM(CASE WHEN geo_status = 2 THEN 1 ELSE 0 END) as unavailable,
    SUM(CASE WHEN network_type = 'ipv4' THEN 1 ELSE 0 END) as ipv4,
    SUM(CASE WHEN network_type = 'ipv6' THEN 1 ELSE 0 END) as ipv6,
    SUM(CASE WHEN network_type = 'onion' THEN 1 ELSE 0 END) as onion,
    SUM(CASE WHEN network_type = 'i2p' THEN 1 ELSE 0 END) as i2p,
    SUM(CASE WHEN network_type = 'cjdns' THEN 1 ELSE 0 END) as cjdns
FROM peers_geo;
EOF
}

# ═══════════════════════════════════════════════════════════════════════════════
# UTILITY FUNCTIONS
# ═══════════════════════════════════════════════════════════════════════════════

# Reset all unavailable peers to retry geo lookup
reset_unavailable_peers() {
    local now
    now=$(date +%s)
    sqlite3 "$DB_FILE" "UPDATE peers_geo SET geo_retry_count = 0, geo_last_lookup = 0 WHERE geo_status = $GEO_UNAVAILABLE;"
}

# Delete all cached data
reset_database() {
    rm -f "$DB_FILE"
    init_database
}

# Export functions
export -f init_database
export -f peer_exists
export -f get_peer_geo
export -f should_retry_geo
export -f upsert_peer_geo
export -f update_peer_seen
export -f insert_private_peer
export -f insert_unavailable_peer
export -f get_peer_count
export -f get_peers_by_status
export -f get_all_peers_json
export -f get_peer_stats
export -f reset_unavailable_peers
export -f reset_database

export DB_FILE
export GEO_OK
export GEO_PRIVATE
export GEO_UNAVAILABLE
