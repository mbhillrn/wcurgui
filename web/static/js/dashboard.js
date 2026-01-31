/**
 * MBTC-DASH - Dashboard JavaScript
 * Handles peer data fetching, table rendering, map, and real-time updates
 */

// Configuration
const REFRESH_INTERVAL = 10000; // 10 seconds
const API_BASE = '';

// Antarctica coords for private AND unavailable locations
const ANTARCTICA_LAT = -82.8628;
const ANTARCTICA_LON = 135.0000;

// State
let currentPeers = [];
let sortColumn = null;  // null = unsorted (default)
let sortDirection = null;  // null, 'asc', or 'desc'
let refreshTimer = null;
let countdown = 10;
let eventSource = null;
let map = null;
let markers = {};

// Column visibility state - all visible by default (23 columns)
const defaultVisibleColumns = [
    'id', 'network', 'ip', 'port', 'direction', 'subver',
    'city', 'region', 'regionName', 'country', 'countryCode', 'continent', 'continentCode',
    'bytessent', 'bytesrecv', 'ping_ms', 'conntime', 'connection_type', 'services_abbrev',
    'lat', 'lon', 'isp',
    'in_addrman'
];
let visibleColumns = [...defaultVisibleColumns];

// Column labels for the config modal
const columnLabels = {
    'id': 'Peer ID',
    'network': 'Network',
    'ip': 'IP Address',
    'port': 'Port',
    'direction': 'Direction',
    'subver': 'User Agent',
    'city': 'City',
    'region': 'Region',
    'regionName': 'Region Name',
    'country': 'Country',
    'countryCode': 'Country Code',
    'continent': 'Continent',
    'continentCode': 'Continent Code',
    'bytessent': 'Bytes Sent',
    'bytesrecv': 'Bytes Recv',
    'ping_ms': 'Ping',
    'conntime': 'Conn Time',
    'connection_type': 'Conn Type',
    'services_abbrev': 'Services',
    'lat': 'Latitude',
    'lon': 'Longitude',
    'isp': 'ISP',
    'in_addrman': 'In Addrman'
};

// DOM Elements
const peerTbody = document.getElementById('peer-tbody');
const peerCount = document.getElementById('peer-count');
const statusIndicator = document.getElementById('status-indicator');
const connectionStatus = document.getElementById('connection-status');
const refreshTimerEl = document.getElementById('refresh-timer');
const changesTbody = document.getElementById('changes-tbody');

// Initialize
document.addEventListener('DOMContentLoaded', () => {
    setupTableSorting();
    setupColumnResize();
    setupColumnConfig();
    setupPanelResize();
    initMap();
    fetchPeers();
    fetchStats();
    fetchChanges();
    setupSSE();
    startCountdown();
    loadColumnPreferences();
});

// Setup column resizing via drag
function setupColumnResize() {
    const table = document.getElementById('peer-table');
    if (!table) return;

    let isResizing = false;
    let currentTh = null;
    let startX = 0;
    let startWidth = 0;

    // Detect if click is near the right edge of a header
    table.addEventListener('mousedown', (e) => {
        const th = e.target.closest('th');
        if (!th) return;

        const rect = th.getBoundingClientRect();
        const isNearEdge = e.clientX > rect.right - 8;

        if (isNearEdge) {
            e.preventDefault();
            e.stopPropagation();
            isResizing = true;
            currentTh = th;
            startX = e.clientX;
            startWidth = th.offsetWidth;
            th.classList.add('resizing');
            document.body.style.cursor = 'col-resize';
            document.body.style.userSelect = 'none';
        }
    });

    document.addEventListener('mousemove', (e) => {
        if (!isResizing || !currentTh) return;
        const deltaX = e.clientX - startX;
        const newWidth = Math.max(40, startWidth + deltaX);
        currentTh.style.width = newWidth + 'px';
        currentTh.style.minWidth = newWidth + 'px';
    });

    document.addEventListener('mouseup', () => {
        if (isResizing && currentTh) {
            currentTh.classList.remove('resizing');
            currentTh = null;
            isResizing = false;
            document.body.style.cursor = '';
            document.body.style.userSelect = '';
        }
    });

    // Change cursor when near edge
    table.addEventListener('mousemove', (e) => {
        if (isResizing) return;
        const th = e.target.closest('th');
        if (!th) return;

        const rect = th.getBoundingClientRect();
        const isNearEdge = e.clientX > rect.right - 8;
        th.style.cursor = isNearEdge ? 'col-resize' : 'pointer';
    });
}

// Setup panel resize handles
function setupPanelResize() {
    const handles = document.querySelectorAll('.resize-handle');
    handles.forEach(handle => {
        const panelId = handle.dataset.panel;
        const panel = document.getElementById(panelId);
        if (!panel) return;

        let isResizing = false;
        let startY = 0;
        let startHeight = 0;

        handle.addEventListener('mousedown', (e) => {
            isResizing = true;
            startY = e.clientY;
            startHeight = panel.offsetHeight;
            document.body.style.cursor = 'ns-resize';
            document.body.style.userSelect = 'none';
            e.preventDefault();
        });

        document.addEventListener('mousemove', (e) => {
            if (!isResizing) return;
            const deltaY = e.clientY - startY;
            const newHeight = Math.max(100, startHeight + deltaY);
            panel.style.height = newHeight + 'px';
        });

        document.addEventListener('mouseup', () => {
            if (isResizing) {
                isResizing = false;
                document.body.style.cursor = '';
                document.body.style.userSelect = '';
                // Trigger map resize if it's the map panel
                if (panelId === 'map-panel' && map) {
                    map.invalidateSize();
                }
            }
        });
    });
}

// Initialize Leaflet map
function initMap() {
    // Bounds to prevent panning too far outside world
    const worldBounds = L.latLngBounds(
        L.latLng(-85, -180),  // Southwest corner
        L.latLng(85, 180)     // Northeast corner
    );

    map = L.map('map', {
        center: [20, 0],
        zoom: 1,                   // Zoomed out to show whole world
        minZoom: 1,
        maxZoom: 18,
        worldCopyJump: true,       // Single-extent mode: wrap at edges
        maxBounds: worldBounds,    // Confined box: restrict panning
        maxBoundsViscosity: 0.8    // How "sticky" the bounds are (0-1)
    });

    // Dark tile layer (CartoDB Dark Matter)
    L.tileLayer('https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png', {
        attribution: '&copy; <a href="https://www.openstreetmap.org/copyright">OSM</a> &copy; <a href="https://carto.com/">CARTO</a>',
        subdomains: 'abcd',
        maxZoom: 19,
        noWrap: false  // Allow world to wrap for continuous scrolling
    }).addTo(map);

    // Fix map size when container resizes
    const mapContainer = document.getElementById('map-panel');
    if (mapContainer) {
        const resizeObserver = new ResizeObserver(() => {
            map.invalidateSize();
        });
        resizeObserver.observe(mapContainer);
    }
}

// Antarctica cluster positions for private networks
const ANTARCTICA_CLUSTERS = {
    'onion': { lat: -80, lon: -120 },   // West Antarctica
    'i2p':   { lat: -82, lon: -30 },    // Near Weddell Sea
    'cjdns': { lat: -78, lon: 60 },     // East Antarctica
    'unavailable': { lat: -85, lon: 150 } // Ross Ice Shelf area
};

// Network colors (matching CSS)
const NETWORK_COLORS = {
    'ipv4':  '#d29922', // yellow
    'ipv6':  '#e69500', // orange
    'onion': '#c74e4e', // mild red
    'i2p':   '#58a6ff', // light blue
    'cjdns': '#d296c7', // light pink
    'unavailable': '#6e7681' // gray
};

// Update map markers with network colors
function updateMap() {
    // Clear existing markers
    Object.values(markers).forEach(marker => map.removeLayer(marker));
    markers = {};

    currentPeers.forEach(peer => {
        let lat, lon;
        const network = peer.network || 'ipv4';
        const color = NETWORK_COLORS[network] || NETWORK_COLORS['ipv4'];

        if (peer.location_status === 'private') {
            // Private locations: cluster by network type in Antarctica
            const cluster = ANTARCTICA_CLUSTERS[network] || ANTARCTICA_CLUSTERS['onion'];
            lat = cluster.lat + (Math.random() - 0.5) * 4;
            lon = cluster.lon + (Math.random() - 0.5) * 20;
        } else if (peer.location_status === 'unavailable') {
            // Unavailable locations: separate area in Antarctica
            const cluster = ANTARCTICA_CLUSTERS['unavailable'];
            lat = cluster.lat + (Math.random() - 0.5) * 3;
            lon = cluster.lon + (Math.random() - 0.5) * 15;
        } else if (peer.lat && peer.lon) {
            lat = peer.lat;
            lon = peer.lon;
        } else {
            return; // Skip if no location
        }

        const marker = L.circleMarker([lat, lon], {
            radius: 6,
            fillColor: color,
            color: '#ffffff',
            weight: 1,
            opacity: 0.8,
            fillOpacity: 0.7
        });

        // Enhanced popup with network info
        const networkLabel = network.toUpperCase();
        const statusLabel = peer.location_status === 'private' ? ' (Private)' :
                           peer.location_status === 'unavailable' ? ' (Unavailable)' : '';

        marker.bindPopup(`
            <strong>${peer.ip}</strong><br>
            <span style="color: ${color}">${networkLabel}</span>${statusLabel}<br>
            ${peer.location_status === 'ok' ? `${peer.city}, ${peer.countryCode}` : peer.location}<br>
            ${peer.isp || '-'}<br>
            <span style="color: ${peer.direction === 'IN' ? '#3fb950' : '#58a6ff'}">${peer.direction}</span>
            | ${peer.subver}
        `);

        marker.addTo(map);
        markers[peer.id] = marker;
    });
}

// Setup table column sorting - 3-state cycle: unsorted → asc → desc → unsorted
function setupTableSorting() {
    const headers = document.querySelectorAll('.peer-table th[data-sort]');
    headers.forEach(header => {
        header.addEventListener('click', () => {
            const column = header.dataset.sort;

            // 3-state cycle: null → asc → desc → null
            if (sortColumn === column) {
                if (sortDirection === 'asc') {
                    sortDirection = 'desc';
                } else if (sortDirection === 'desc') {
                    sortColumn = null;
                    sortDirection = null;
                }
            } else {
                sortColumn = column;
                sortDirection = 'asc';
            }

            // Update header styles
            headers.forEach(h => h.classList.remove('sorted-asc', 'sorted-desc'));
            if (sortColumn === column && sortDirection) {
                header.classList.add(sortDirection === 'asc' ? 'sorted-asc' : 'sorted-desc');
            }

            renderPeers();
        });
    });
}

// Setup column configuration modal
function setupColumnConfig() {
    const configBtn = document.getElementById('column-config-btn');
    const modal = document.getElementById('column-config-modal');
    const closeBtn = document.getElementById('modal-close');
    const checkboxContainer = document.getElementById('column-checkboxes');

    if (!configBtn || !modal || !closeBtn || !checkboxContainer) return;

    // Populate checkboxes
    function populateCheckboxes() {
        checkboxContainer.innerHTML = '';
        defaultVisibleColumns.forEach(col => {
            const label = document.createElement('label');
            label.className = 'column-checkbox';
            label.innerHTML = `
                <input type="checkbox" data-col="${col}" ${visibleColumns.includes(col) ? 'checked' : ''}>
                ${columnLabels[col] || col}
            `;
            checkboxContainer.appendChild(label);
        });

        // Add change handlers
        checkboxContainer.querySelectorAll('input[type="checkbox"]').forEach(cb => {
            cb.addEventListener('change', () => {
                const col = cb.dataset.col;
                if (cb.checked) {
                    if (!visibleColumns.includes(col)) {
                        visibleColumns.push(col);
                    }
                } else {
                    visibleColumns = visibleColumns.filter(c => c !== col);
                }
                applyColumnVisibility();
                saveColumnPreferences();
            });
        });
    }

    // Open modal
    configBtn.addEventListener('click', () => {
        populateCheckboxes();
        modal.classList.add('active');
    });

    // Close modal
    closeBtn.addEventListener('click', () => {
        modal.classList.remove('active');
    });

    // Close on outside click
    modal.addEventListener('click', (e) => {
        if (e.target === modal) {
            modal.classList.remove('active');
        }
    });

    // Close on Escape key
    document.addEventListener('keydown', (e) => {
        if (e.key === 'Escape' && modal.classList.contains('active')) {
            modal.classList.remove('active');
        }
    });
}

// Apply column visibility to table
function applyColumnVisibility() {
    const headers = document.querySelectorAll('.peer-table th[data-col]');
    headers.forEach(th => {
        const col = th.dataset.col;
        if (visibleColumns.includes(col)) {
            th.classList.remove('col-hidden');
        } else {
            th.classList.add('col-hidden');
        }
    });

    // Re-render to apply to body cells
    renderPeers();
}

// Save column preferences to localStorage
function saveColumnPreferences() {
    try {
        localStorage.setItem('mbcore_visible_columns', JSON.stringify(visibleColumns));
    } catch (e) {
        console.warn('Could not save column preferences:', e);
    }
}

// Load column preferences from localStorage
function loadColumnPreferences() {
    try {
        const saved = localStorage.getItem('mbcore_visible_columns');
        if (saved) {
            visibleColumns = JSON.parse(saved);
            applyColumnVisibility();
        }
    } catch (e) {
        console.warn('Could not load column preferences:', e);
    }
}

// Fetch peer data from API
async function fetchPeers() {
    try {
        const response = await fetch(`${API_BASE}/api/peers`);
        if (!response.ok) throw new Error('Failed to fetch peers');

        currentPeers = await response.json();
        renderPeers();
        updateMap();

        // Update status
        statusIndicator.classList.add('connected');
        statusIndicator.classList.remove('error');
        connectionStatus.textContent = 'Connected';
    } catch (error) {
        console.error('Error fetching peers:', error);
        statusIndicator.classList.add('error');
        statusIndicator.classList.remove('connected');
        connectionStatus.textContent = 'Error';

        peerTbody.innerHTML = `
            <tr class="loading-row">
                <td colspan="10">Error loading peers. Is bitcoind running?</td>
            </tr>
        `;
    }
}

// Fetch stats from API
async function fetchStats() {
    try {
        const response = await fetch(`${API_BASE}/api/stats`);
        if (!response.ok) throw new Error('Failed to fetch stats');

        const stats = await response.json();
        const enabled = stats.enabled_networks || ['ipv4'];
        const networks = stats.networks || {};

        // Connected count
        document.getElementById('stat-connected').textContent = stats.connected || 0;

        // Update peer header total count
        const countTotal = document.getElementById('count-total');
        if (countTotal) {
            countTotal.textContent = stats.connected || 0;
        }

        // Network stats - only show if enabled, with (in/out) format in stats bar
        // and network counts in peer header
        const networkNames = ['ipv4', 'ipv6', 'onion', 'i2p', 'cjdns'];
        const networkLabels = { 'ipv4': 'IPV4', 'ipv6': 'IPV6', 'onion': 'TOR', 'i2p': 'I2P', 'cjdns': 'CJDNS' };

        networkNames.forEach(net => {
            // Stats bar elements
            const wrap = document.getElementById(`stat-${net}-wrap`);
            const val = document.getElementById(`stat-${net}`);

            // Peer header count elements
            const countEl = document.getElementById(`count-${net}`);
            const sepEl = document.getElementById(`sep-${net}`);

            if (wrap && val) {
                if (enabled.includes(net)) {
                    wrap.style.display = '';
                    const netData = networks[net] || {in: 0, out: 0};
                    val.textContent = `(${netData.in}/${netData.out})`;

                    // Update peer header counts
                    if (countEl) {
                        const total = netData.in + netData.out;
                        countEl.textContent = `${networkLabels[net]} ${total}`;
                        countEl.style.display = '';
                    }
                    if (sepEl) {
                        sepEl.style.display = '';
                    }
                } else {
                    wrap.style.display = 'none';
                    if (countEl) countEl.style.display = 'none';
                    if (sepEl) sepEl.style.display = 'none';
                }
            }
        });

        // Show/hide separators correctly between enabled networks
        // Each sep-X comes AFTER count-X, so we hide sep-X if the NEXT network is not visible
        for (let i = 0; i < networkNames.length - 1; i++) {
            const net = networkNames[i];
            const sepEl = document.getElementById(`sep-${net}`);
            if (!sepEl) continue;

            // Check if any network AFTER this one is enabled
            let nextEnabled = false;
            for (let j = i + 1; j < networkNames.length; j++) {
                if (enabled.includes(networkNames[j])) {
                    nextEnabled = true;
                    break;
                }
            }

            // Show separator only if current network is enabled AND a later network is enabled
            if (enabled.includes(net) && nextEnabled) {
                sepEl.style.display = '';
            } else {
                sepEl.style.display = 'none';
            }
        }

        // Update protocol status in header
        updateProtocolStatus(enabled);

        // Update map status indicator
        updateMapStatus(stats.geo_pending || 0);
    } catch (error) {
        console.error('Error fetching stats:', error);
        updateMapStatus(-1); // Error state
    }
}

// Update protocol status indicator in header
function updateProtocolStatus(enabled) {
    const enabledEl = document.getElementById('protocols-enabled');
    const disabledEl = document.getElementById('protocols-disabled');
    if (!enabledEl || !disabledEl) return;

    const allProtocols = ['ipv4', 'ipv6', 'onion', 'i2p', 'cjdns'];
    const protoLabels = { 'ipv4': 'IPv4', 'ipv6': 'IPv6', 'onion': 'Tor', 'i2p': 'I2P', 'cjdns': 'CJDNS' };

    // Build enabled list
    const enabledList = allProtocols
        .filter(p => enabled.includes(p))
        .map(p => `<span class="proto-${p}">${protoLabels[p]}</span>`)
        .join(' ');

    // Build disabled list
    const disabledProtos = allProtocols.filter(p => !enabled.includes(p));

    enabledEl.innerHTML = enabledList || '<span style="color: var(--text-dim)">None</span>';

    if (disabledProtos.length === 0) {
        disabledEl.innerHTML = '<span class="proto-all-configured">All Protocols Configured</span>';
    } else {
        const disabledList = disabledProtos
            .map(p => `<span class="proto-${p}">${protoLabels[p]}</span>`)
            .join(' ');
        disabledEl.innerHTML = disabledList;
    }
}

// Update map status indicator (orange=updating, green=updated, red=error)
function updateMapStatus(pending) {
    const dot = document.getElementById('map-status-dot');
    const text = document.getElementById('map-status-text');
    if (!dot || !text) return;

    // Remove all status classes
    dot.classList.remove('status-ok', 'status-pending', 'status-error');

    if (pending < 0) {
        // Error
        dot.classList.add('status-error');
        text.textContent = 'Error';
    } else if (pending > 0) {
        // Still loading
        dot.classList.add('status-pending');
        text.textContent = `Updating... (${pending})`;
    } else {
        // All done
        dot.classList.add('status-ok');
        text.textContent = 'Updated!';
    }
}

// Fetch recent changes from API
async function fetchChanges() {
    try {
        const response = await fetch(`${API_BASE}/api/changes`);
        if (!response.ok) throw new Error('Failed to fetch changes');

        const changes = await response.json();
        renderChanges(changes);
    } catch (error) {
        console.error('Error fetching changes:', error);
    }
}

// Render recent changes table
function renderChanges(changes) {
    if (!changes || changes.length === 0) {
        changesTbody.innerHTML = `
            <tr class="loading-row">
                <td colspan="4">No recent changes</td>
            </tr>
        `;
        return;
    }

    const rows = changes.map(change => {
        const time = new Date(change.time * 1000).toLocaleTimeString();
        const eventClass = change.type === 'connected' ? 'event-connected' : 'event-disconnected';

        return `
            <tr>
                <td>${time}</td>
                <td class="${eventClass}">${change.type}</td>
                <td>${change.peer.ip || '-'}</td>
                <td>${change.peer.network || '-'}</td>
            </tr>
        `;
    }).join('');

    changesTbody.innerHTML = rows;
}

// Setup Server-Sent Events for real-time updates
function setupSSE() {
    if (eventSource) {
        eventSource.close();
    }

    eventSource = new EventSource(`${API_BASE}/api/events`);

    eventSource.onmessage = (event) => {
        const data = JSON.parse(event.data);

        switch (data.type) {
            case 'connected':
                console.log('SSE connected');
                break;
            case 'peers_update':
                fetchPeers();
                fetchStats();
                fetchChanges();
                resetCountdown();
                break;
            case 'geo_update':
                // Geo data updated for a specific IP, refresh to get new data
                fetchPeers();
                break;
            case 'keepalive':
                // Just a keepalive, do nothing
                break;
        }
    };

    eventSource.onerror = (error) => {
        console.error('SSE error:', error);
        statusIndicator.classList.remove('connected');
        connectionStatus.textContent = 'Reconnecting...';

        // Reconnect after 5 seconds
        setTimeout(setupSSE, 5000);
    };
}

// Render peers to table - 23 COLUMNS with network colors
function renderPeers() {
    if (currentPeers.length === 0) {
        peerTbody.innerHTML = `
            <tr class="loading-row">
                <td colspan="23">No peers connected</td>
            </tr>
        `;
        peerCount.textContent = '0 peers';
        return;
    }

    // Sort peers (or keep original order if unsorted)
    let sortedPeers;
    if (sortColumn && sortDirection) {
        sortedPeers = [...currentPeers].sort((a, b) => {
            let aVal = a[sortColumn];
            let bVal = b[sortColumn];

            // Handle numeric sorting
            if (typeof aVal === 'number' && typeof bVal === 'number') {
                return sortDirection === 'asc' ? aVal - bVal : bVal - aVal;
            }

            // Handle null/undefined
            if (aVal == null) aVal = '';
            if (bVal == null) bVal = '';

            // String comparison
            const cmp = String(aVal).localeCompare(String(bVal));
            return sortDirection === 'asc' ? cmp : -cmp;
        });
    } else {
        // No sorting - keep original order (by peer ID from API)
        sortedPeers = [...currentPeers];
    }

    // Helper to check if column is visible
    const isVisible = (col) => visibleColumns.includes(col);
    const hiddenClass = (col) => isVisible(col) ? '' : 'col-hidden';

    // Build table HTML - 23 COLUMNS
    const rows = sortedPeers.map(peer => {
        // Network type determines row color class
        const networkRowClass = `network-row-${peer.network}`;
        const directionClass = peer.direction === 'IN' ? 'in' : 'out';

        // City display with status
        let cityDisplay = peer.city || '-';
        let cityClass = '';
        if (peer.location_status === 'private') {
            cityDisplay = 'PRIVATE';
            cityClass = 'location-private';
        } else if (peer.location_status === 'unavailable') {
            cityDisplay = 'UNAVAILABLE';
            cityClass = 'location-unavailable';
        } else if (peer.location_status === 'pending') {
            cityDisplay = 'Stalking...';
            cityClass = 'location-pending';
        }

        // In addrman display
        const inAddrman = peer.in_addrman ? 'Yes' : 'No';
        const addrmanClass = peer.in_addrman ? 'addrman-yes' : 'addrman-no';

        return `
            <tr data-id="${peer.id}" class="${networkRowClass}">
                <!-- 1-6: getpeerinfo (instant) -->
                <td data-col="id" class="cell-white ${hiddenClass('id')}" title="Peer ID: ${peer.id}">${peer.id}</td>
                <td data-col="network" class="network-${peer.network} ${hiddenClass('network')}" title="Network: ${peer.network}">${peer.network}</td>
                <td data-col="ip" class="${hiddenClass('ip')}" title="${peer.addr}">${truncate(peer.ip, 20)}</td>
                <td data-col="port" class="${hiddenClass('port')}" title="Port: ${peer.port || '-'}">${peer.port || '-'}</td>
                <td data-col="direction" class="${hiddenClass('direction')}" title="${peer.direction === 'IN' ? 'Inbound: They connected to us' : 'Outbound: We connected to them'}"><span class="direction-badge ${directionClass}">${peer.direction}</span></td>
                <td data-col="subver" class="${hiddenClass('subver')}" title="${peer.subver}">${truncate(peer.subver, 18)}</td>
                <!-- 7-13: ip-api geo (loads second) -->
                <td data-col="city" class="${cityClass} ${hiddenClass('city')}" title="City: ${cityDisplay}">${truncate(cityDisplay, 15)}</td>
                <td data-col="region" class="${hiddenClass('region')}" title="Region: ${peer.region || '-'}">${peer.region || '-'}</td>
                <td data-col="regionName" class="${hiddenClass('regionName')}" title="Region Name: ${peer.regionName || '-'}">${truncate(peer.regionName || '-', 12)}</td>
                <td data-col="country" class="${hiddenClass('country')}" title="Country: ${peer.country || '-'}">${truncate(peer.country || '-', 12)}</td>
                <td data-col="countryCode" class="${hiddenClass('countryCode')}" title="Country Code: ${peer.countryCode || '-'}">${peer.countryCode || '-'}</td>
                <td data-col="continent" class="${hiddenClass('continent')}" title="Continent: ${peer.continent || '-'}">${truncate(peer.continent || '-', 10)}</td>
                <td data-col="continentCode" class="${hiddenClass('continentCode')}" title="Continent Code: ${peer.continentCode || '-'}">${peer.continentCode || '-'}</td>
                <!-- 14-19: more getpeerinfo -->
                <td data-col="bytessent" class="cell-white ${hiddenClass('bytessent')}" title="Bytes Sent: ${peer.bytessent_fmt}">${peer.bytessent_fmt}</td>
                <td data-col="bytesrecv" class="cell-white ${hiddenClass('bytesrecv')}" title="Bytes Received: ${peer.bytesrecv_fmt}">${peer.bytesrecv_fmt}</td>
                <td data-col="ping_ms" class="cell-white ${hiddenClass('ping_ms')}" title="Ping: ${peer.ping_ms != null ? peer.ping_ms + 'ms' : '-'}">${peer.ping_ms != null ? peer.ping_ms + 'ms' : '-'}</td>
                <td data-col="conntime" class="cell-white ${hiddenClass('conntime')}" title="Connected: ${peer.conntime_fmt}">${peer.conntime_fmt}</td>
                <td data-col="connection_type" class="${hiddenClass('connection_type')}" title="Connection Type: ${peer.connection_type || '-'}">${truncate(peer.connection_type || '-', 12)}</td>
                <td data-col="services_abbrev" class="cell-white ${hiddenClass('services_abbrev')}" title="${(peer.services || []).join(', ')}">${peer.services_abbrev || '-'}</td>
                <!-- 20-22: more ip-api -->
                <td data-col="lat" class="cell-white ${hiddenClass('lat')}" title="Latitude: ${peer.lat ? peer.lat.toFixed(4) : '-'}">${peer.lat ? peer.lat.toFixed(2) : '-'}</td>
                <td data-col="lon" class="cell-white ${hiddenClass('lon')}" title="Longitude: ${peer.lon ? peer.lon.toFixed(4) : '-'}">${peer.lon ? peer.lon.toFixed(2) : '-'}</td>
                <td data-col="isp" class="${hiddenClass('isp')}" title="ISP: ${peer.isp || '-'}">${truncate(peer.isp || '-', 15)}</td>
                <!-- 23: addrman status -->
                <td data-col="in_addrman" class="cell-white ${addrmanClass} ${hiddenClass('in_addrman')}" title="In Address Manager: ${inAddrman}">${inAddrman}</td>
            </tr>
        `;
    }).join('');

    peerTbody.innerHTML = rows;
    peerCount.textContent = `${currentPeers.length} peers`;
}

// Truncate string
function truncate(str, maxLen) {
    if (!str) return '-';
    if (str.length <= maxLen) return str;
    return str.substring(0, maxLen - 3) + '...';
}

// Countdown timer
function startCountdown() {
    countdown = REFRESH_INTERVAL / 1000;
    updateCountdownDisplay();

    refreshTimer = setInterval(() => {
        countdown--;
        if (countdown <= 0) {
            countdown = REFRESH_INTERVAL / 1000;
        }
        updateCountdownDisplay();
        updateLocalTime();
    }, 1000);

    // Initialize local time
    updateLocalTime();
}

function resetCountdown() {
    countdown = REFRESH_INTERVAL / 1000;
    updateCountdownDisplay();
}

function updateCountdownDisplay() {
    // Update footer timer
    refreshTimerEl.textContent = `Refreshing in ${countdown}s`;
    // Update stats bar countdown
    const statCountdown = document.getElementById('stat-countdown');
    if (statCountdown) {
        statCountdown.textContent = `${countdown}s`;
    }
}

function updateLocalTime() {
    const now = new Date();
    const timeStr = now.toLocaleTimeString();
    const statLocaltime = document.getElementById('stat-localtime');
    if (statLocaltime) {
        statLocaltime.textContent = timeStr;
    }
}

// Cleanup on page unload
window.addEventListener('beforeunload', () => {
    if (eventSource) {
        eventSource.close();
    }
    if (refreshTimer) {
        clearInterval(refreshTimer);
    }
});
