/**
 * MBTC-DASH - Dashboard JavaScript
 * Handles peer data fetching, table rendering, map, and real-time updates
 */

// Configuration
let refreshInterval = 10000; // 10 seconds default (can be changed by user)
let changesWindowSeconds = 20; // seconds to show in Recent Changes (default 20)
let showAntarcticaDots = true; // show private network dots in Antarctica (default true)
const API_BASE = '';

// State
let currentPeers = [];
let sortColumn = null;  // null = unsorted (default)
let sortDirection = null;  // null, 'asc', or 'desc'
let refreshTimer = null;
let countdown = 10;
let eventSource = null;
let map = null;
let markers = {};
let networkFilter = 'all';  // 'all', 'ipv4', 'ipv6', 'onion', 'i2p', 'cjdns'
let columnWidths = {};
let hasSavedColumnWidths = false;
let autoSizedColumns = false;

// Changes table column state
let changesColumnWidths = {};

// All available columns (for reference)
const allColumns = [
    'id', 'network', 'ip', 'port', 'direction', 'subver',
    'city', 'region', 'regionName', 'country', 'countryCode', 'continent', 'continentCode',
    'bytessent', 'bytesrecv', 'ping_ms', 'conntime', 'connection_type', 'services_abbrev',
    'lat', 'lon', 'isp',
    'in_addrman'
];

// Default visible columns in user's preferred order
const defaultVisibleColumns = [
    'network', 'conntime', 'direction', 'ip', 'port', 'subver',
    'connection_type', 'services_abbrev',
    'city', 'regionName', 'country', 'continent', 'isp',
    'ping_ms', 'bytessent', 'bytesrecv',
    'in_addrman'
];
let visibleColumns = [...defaultVisibleColumns];

// Column order (for drag-and-drop reordering) - start with default order
let columnOrder = [...defaultVisibleColumns];

// Column labels for the config modal (must match column headers!)
const columnLabels = {
    'id': 'ID',
    'network': 'Net',
    'ip': 'IP',
    'port': 'Port',
    'direction': 'in/out',
    'subver': 'Node ver/name',
    'city': 'City',
    'region': 'State/reg',
    'regionName': 'State/reg (full)',
    'country': 'Country',
    'countryCode': 'Ctry Code',
    'continent': 'Continent',
    'continentCode': 'ContC',
    'bytessent': 'Sent',
    'bytesrecv': 'Received',
    'ping_ms': 'Ping',
    'conntime': 'Since',
    'connection_type': 'Type',
    'services_abbrev': 'Service',
    'lat': 'Lat',
    'lon': 'Lon',
    'isp': 'ISP',
    'in_addrman': 'In Addrman?'
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
    loadColumnPreferences();  // Load saved order/visibility first
    setupRefreshRateControl(); // Load refresh rate preference early
    setupChangesWindowControl(); // Load changes window preference
    setupAntarcticaToggle(); // Setup Antarctica show/hide toggle
    // Don't load saved column widths on startup - let fitColumnsToWindow handle it after data loads
    // This ensures columns always fit the window properly on page load
    // But DO set initial changes table widths (it's a small fixed table)
    setInitialChangesColumnWidths();
    setupTableSorting();
    setupColumnResize();
    setupChangesColumnResize();
    setupColumnDrag();
    setupColumnConfig();
    setupNetworkFilter();
    setupRestoreDefaults();
    setupPanelResize();
    setupPeerRowClick();
    initMap();
    fetchPeers();
    fetchStats();
    fetchChanges();
    setupSSE();
    startCountdown();
});

// Setup network filter buttons
function setupNetworkFilter() {
    document.querySelectorAll('.network-filter-btn').forEach(btn => {
        btn.addEventListener('click', () => {
            const filter = btn.dataset.filter;
            if (filter) {
                networkFilter = filter;
                // Update active state
                document.querySelectorAll('.network-filter-btn').forEach(b => b.classList.remove('active'));
                btn.classList.add('active');
                // Re-render peers with filter
                renderPeers();
            }
        });
    });
}

// Setup peer row click to show map popup
function setupPeerRowClick() {
    const tbody = document.getElementById('peer-tbody');
    if (!tbody) return;

    tbody.addEventListener('click', (e) => {
        const row = e.target.closest('tr[data-id]');
        if (!row) return;

        const peerId = parseInt(row.dataset.id, 10);
        if (isNaN(peerId)) return;

        // Find the marker for this peer
        const marker = markers[peerId];
        if (marker && map) {
            // Get marker position and pan map to it
            const pos = marker.getLatLng();
            map.setView(pos, Math.max(map.getZoom(), 3), { animate: true });

            // Open the popup
            marker.openPopup();

            // Highlight the row briefly
            row.classList.add('row-selected');
            setTimeout(() => row.classList.remove('row-selected'), 1500);
        }
    });
}

// Setup restore defaults button
function setupRestoreDefaults() {
    const btn = document.getElementById('restore-defaults-btn');
    if (btn) {
        btn.addEventListener('click', () => {
            // Reset to defaults
            visibleColumns = [...defaultVisibleColumns];
            columnOrder = [...defaultVisibleColumns];
            networkFilter = 'all';

            // Update filter button states
            document.querySelectorAll('.network-filter-btn').forEach(b => b.classList.remove('active'));
            const allBtn = document.querySelector('.network-filter-btn[data-filter="all"]');
            if (allBtn) allBtn.classList.add('active');

            // Clear localStorage
            try {
                localStorage.removeItem('mbcore_visible_columns');
                localStorage.removeItem('mbcore_column_order');
                localStorage.removeItem('mbcore_column_widths');
                localStorage.removeItem('mbcore_changes_column_widths');
            } catch (e) {}

            // Reset peer table column widths - clear inline styles and set defaults
            const table = document.getElementById('peer-table');
            if (table) {
                table.querySelectorAll('th[data-col], td[data-col]').forEach(cell => {
                    cell.style.width = '';
                    cell.style.maxWidth = '';
                });
            }
            columnWidths = {};
            hasSavedColumnWidths = false;
            autoSizedColumns = false;
            setInitialColumnWidths();

            // Reset changes table column widths
            const changesTable = document.getElementById('changes-table');
            if (changesTable) {
                changesTable.querySelectorAll('th[data-col], td[data-col]').forEach(cell => {
                    cell.style.width = '';
                    cell.style.maxWidth = '';
                });
            }
            changesColumnWidths = {};
            setInitialChangesColumnWidths();

            // Re-apply and re-render
            applyColumnVisibility();
            reorderTableColumns();
            renderPeers();
        });
    }
}

// Flag to prevent sort when just finished resizing
let justResized = false;

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
        applyColumnWidth(currentTh.dataset.col, `${newWidth}px`);
    });

    document.addEventListener('mouseup', () => {
        if (isResizing && currentTh) {
            currentTh.classList.remove('resizing');
            saveColumnWidths(); // Save widths after resize
            currentTh = null;
            isResizing = false;
            document.body.style.cursor = '';
            document.body.style.userSelect = '';
            // Set flag to prevent sort click that follows resize
            justResized = true;
            setTimeout(() => { justResized = false; }, 100);
        }
    });

    // Change cursor when near edge
    table.addEventListener('mousemove', (e) => {
        if (isResizing) return;
        const th = e.target.closest('th');
        if (!th) return;

        const rect = th.getBoundingClientRect();
        const isNearEdge = e.clientX > rect.right - 8;
        th.style.cursor = isNearEdge ? 'col-resize' : 'grab';
    });
}

// Setup changes table column resizing
function setupChangesColumnResize() {
    const table = document.getElementById('changes-table');
    if (!table) return;

    let isResizing = false;
    let currentTh = null;
    let startX = 0;
    let startWidth = 0;

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
        applyChangesColumnWidth(currentTh.dataset.col, `${newWidth}px`);
    });

    document.addEventListener('mouseup', () => {
        if (isResizing && currentTh) {
            currentTh.classList.remove('resizing');
            saveChangesColumnWidths();
            currentTh = null;
            isResizing = false;
            document.body.style.cursor = '';
            document.body.style.userSelect = '';
        }
    });

    table.addEventListener('mousemove', (e) => {
        if (isResizing) return;
        const th = e.target.closest('th');
        if (!th) return;

        const rect = th.getBoundingClientRect();
        const isNearEdge = e.clientX > rect.right - 8;
        th.style.cursor = isNearEdge ? 'col-resize' : 'default';
    });
}

// Apply column width to changes table
function applyChangesColumnWidth(col, width) {
    changesColumnWidths[col] = width;
    const table = document.getElementById('changes-table');
    if (!table) return;

    table.querySelectorAll(`th[data-col="${col}"], td[data-col="${col}"]`).forEach(cell => {
        cell.style.width = width;
        cell.style.maxWidth = width;
    });
}

// Get inline style for changes column
function getChangesColumnWidthStyle(col) {
    const width = changesColumnWidths[col];
    return width ? ` style="width: ${width}; max-width: ${width};"` : '';
}

// Save changes column widths
function saveChangesColumnWidths() {
    try {
        localStorage.setItem('mbcore_changes_column_widths', JSON.stringify(changesColumnWidths));
    } catch (e) {
        console.warn('Could not save changes column widths:', e);
    }
}

// Load changes column widths
function loadChangesColumnWidths() {
    try {
        const saved = localStorage.getItem('mbcore_changes_column_widths');
        if (saved) {
            const widths = JSON.parse(saved) || {};
            Object.entries(widths).forEach(([col, width]) => {
                if (width) applyChangesColumnWidth(col, width);
            });
            return Object.keys(widths).length > 0;
        }
    } catch (e) {
        console.warn('Could not load changes column widths:', e);
    }
    return false;
}

// Set initial changes column widths
function setInitialChangesColumnWidths() {
    // Always set all column widths to ensure none are missing
    changesColumnWidths = {};  // Clear any old cached values
    const defaultWidths = { 'time': 80, 'event': 90, 'ip': 140, 'network': 70 };
    Object.entries(defaultWidths).forEach(([col, width]) => {
        applyChangesColumnWidth(col, `${width}px`);
    });
}

// Setup column drag-and-drop reordering
function setupColumnDrag() {
    const table = document.getElementById('peer-table');
    if (!table) return;

    const thead = table.querySelector('thead tr');
    if (!thead) return;

    let draggedTh = null;
    let draggedCol = null;

    // Make headers draggable
    thead.querySelectorAll('th[data-col]').forEach(th => {
        th.setAttribute('draggable', 'true');

        th.addEventListener('dragstart', (e) => {
            // Don't drag if near resize edge
            const rect = th.getBoundingClientRect();
            if (e.clientX > rect.right - 10) {
                e.preventDefault();
                return;
            }

            draggedTh = th;
            draggedCol = th.dataset.col;
            th.classList.add('dragging');
            e.dataTransfer.effectAllowed = 'move';
            e.dataTransfer.setData('text/plain', draggedCol);
        });

        th.addEventListener('dragend', () => {
            if (draggedTh) {
                draggedTh.classList.remove('dragging');
            }
            draggedTh = null;
            draggedCol = null;
            // Remove all drag-over styles
            thead.querySelectorAll('th').forEach(h => h.classList.remove('drag-over'));
        });

        th.addEventListener('dragover', (e) => {
            e.preventDefault();
            e.dataTransfer.dropEffect = 'move';
            if (th !== draggedTh) {
                th.classList.add('drag-over');
            }
        });

        th.addEventListener('dragleave', () => {
            th.classList.remove('drag-over');
        });

        th.addEventListener('drop', (e) => {
            e.preventDefault();
            th.classList.remove('drag-over');

            if (!draggedCol || th.dataset.col === draggedCol) return;

            const targetCol = th.dataset.col;

            // Reorder the columnOrder array
            const fromIndex = columnOrder.indexOf(draggedCol);
            const toIndex = columnOrder.indexOf(targetCol);

            if (fromIndex !== -1 && toIndex !== -1) {
                // Remove from old position
                columnOrder.splice(fromIndex, 1);
                // Insert at new position
                columnOrder.splice(toIndex, 0, draggedCol);

                // Reorder the actual table columns
                reorderTableColumns();
                saveColumnPreferences();
            }
        });
    });
}

// Reorder table columns based on columnOrder
function reorderTableColumns() {
    const table = document.getElementById('peer-table');
    if (!table) return;

    const thead = table.querySelector('thead tr');
    const tbody = table.querySelector('tbody');
    if (!thead) return;

    // Get all header cells as a map
    const headerCells = {};
    thead.querySelectorAll('th[data-col]').forEach(th => {
        headerCells[th.dataset.col] = th;
    });

    // Clear and rebuild header row in new order
    const existingHeaders = Array.from(thead.querySelectorAll('th[data-col]'));
    existingHeaders.forEach(th => th.remove());

    columnOrder.forEach(col => {
        if (headerCells[col]) {
            thead.appendChild(headerCells[col]);
        }
    });

    // Re-render the table body with new column order
    renderPeers();
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

// Antarctica research station coordinates (all on land, near coast)
// These are real research stations - Peninsula excluded (too close to S. America)
const ANTARCTICA_STATIONS = [
    // Ross Sea region (Pacific side)
    { lat: -77.8460, lon: 166.6670 },  // McMurdo Station
    { lat: -77.8480, lon: 166.7600 },  // Scott Base
    { lat: -77.8000, lon: 166.6000 },  // Hut Point Peninsula
    // East Antarctica coastal (Indian Ocean side)
    { lat: -67.6020, lon: 62.8730 },   // Mawson Station
    { lat: -68.5760, lon: 77.9670 },   // Davis Station
    { lat: -66.2810, lon: 110.5280 },  // Casey Station
    { lat: -66.6630, lon: 140.0010 },  // Dumont d'Urville Station
    // Additional coastal stations (Atlantic side, excluding peninsula)
    { lat: -69.0050, lon: 39.5800 },   // Syowa Station
    { lat: -70.6670, lon: 11.6330 },   // Novolazarevskaya
    { lat: -70.7500, lon: -8.2500 },   // Neumayer Station
    { lat: -70.4500, lon: -2.8420 }    // SANAE IV Station
];

// Cache for stable Antarctica positions (keyed by peer addr)
// This ensures dots don't move around during a connection
const antarcticaPositionCache = {};

// Simple string hash function for stable pseudo-random positioning
function hashString(str) {
    let hash = 0;
    for (let i = 0; i < str.length; i++) {
        const char = str.charCodeAt(i);
        hash = ((hash << 5) - hash) + char;
        hash = hash & hash; // Convert to 32-bit integer
    }
    return hash;
}

// Get stable Antarctica position for a peer (cached per addr)
// Peers are placed near research stations with small random offset
function getStableAntarcticaPosition(peerAddr, network, locationType) {
    // Use addr as key to ensure same peer always gets same position
    const cacheKey = peerAddr || `unknown-${Date.now()}`;

    if (antarcticaPositionCache[cacheKey]) {
        return antarcticaPositionCache[cacheKey];
    }

    // Use hash to pick a station and generate small offset
    const hash1 = hashString(cacheKey);
    const hash2 = hashString(cacheKey + '_offset');

    // Pick a station based on hash
    const stationIndex = Math.abs(hash1) % ANTARCTICA_STATIONS.length;
    const station = ANTARCTICA_STATIONS[stationIndex];

    // Generate small offset (±0.5 degrees) to avoid exact overlap
    const latOffset = ((Math.abs(hash2) % 100) / 100 - 0.5) * 1.0;
    const lonOffset = ((Math.abs(hash2 >> 8) % 100) / 100 - 0.5) * 1.0;

    const lat = station.lat + latOffset;
    const lon = station.lon + lonOffset;

    // Cache the position
    antarcticaPositionCache[cacheKey] = { lat, lon };
    return { lat, lon };
}

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

        if (peer.location_status === 'private' || peer.location_status === 'unavailable') {
            // Private/unavailable locations: show in Antarctica if enabled
            if (!showAntarcticaDots) return; // Skip if Antarctica dots are hidden
            // Use stable positions so dots don't move during a connection
            const pos = getStableAntarcticaPosition(peer.addr, network, peer.location_status);
            lat = pos.lat;
            lon = pos.lon;
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
            // Skip sort if we just finished resizing a column
            if (justResized) return;

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
    // Only apply to peer table, not changes table
    const headers = document.querySelectorAll('#peer-table th[data-col]');
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
        localStorage.setItem('mbcore_column_order', JSON.stringify(columnOrder));
    } catch (e) {
        console.warn('Could not save column preferences:', e);
    }
}

// Save column widths to localStorage
function saveColumnWidths() {
    try {
        localStorage.setItem('mbcore_column_widths', JSON.stringify(columnWidths));
    } catch (e) {
        console.warn('Could not save column widths:', e);
    }
}

// Apply column width to both th and td cells
function applyColumnWidth(col, width) {
    columnWidths[col] = width;
    const table = document.getElementById('peer-table');
    if (!table) return;

    table.querySelectorAll(`th[data-col="${col}"], td[data-col="${col}"]`).forEach(cell => {
        cell.style.width = width;
        cell.style.maxWidth = width;
    });
}

// Get inline style string for column width
function getColumnWidthStyle(col) {
    const width = columnWidths[col];
    return width ? ` style="width: ${width}; max-width: ${width};"` : '';
}

// Load and apply saved column widths
function loadColumnWidths() {
    try {
        const saved = localStorage.getItem('mbcore_column_widths');
        if (saved) {
            const widths = JSON.parse(saved) || {};
            const entries = Object.entries(widths).filter(([, width]) => width);
            entries.forEach(([col, width]) => {
                applyColumnWidth(col, width);
            });
            if (entries.length) {
                hasSavedColumnWidths = true;
                return true; // Widths were loaded
            }
        }
    } catch (e) {
        console.warn('Could not load column widths:', e);
    }
    return false; // No saved widths
}

// Set initial column widths based on content (if no saved widths)
function setInitialColumnWidths() {
    const table = document.getElementById('peer-table');
    if (!table) return;

    // Default widths for known columns (px) - compact sizes
    const defaultWidths = {
        'id': 45,
        'network': 60,
        'ip': 120,
        'port': 50,
        'direction': 45,
        'subver': 120,
        'city': 80,
        'region': 50,
        'regionName': 90,
        'country': 80,
        'countryCode': 45,
        'continent': 80,
        'continentCode': 45,
        'bytessent': 65,
        'bytesrecv': 65,
        'ping_ms': 50,
        'conntime': 65,
        'connection_type': 50,
        'services_abbrev': 70,
        'lat': 55,
        'lon': 55,
        'isp': 100,
        'in_addrman': 65
    };

    table.querySelectorAll('th[data-col]').forEach(th => {
        const col = th.dataset.col;
        // Only set if no width already set
        if (!columnWidths[col] && defaultWidths[col]) {
            applyColumnWidth(col, defaultWidths[col] + 'px');
        }
    });
}

// Auto-size columns based on content (first 30 rows)
function autoSizeColumns() {
    // Replaced with fitColumnsToWindow - this is now just an alias
    fitColumnsToWindow();
}

// Fit columns proportionally to window width
function fitColumnsToWindow() {
    const table = document.getElementById('peer-table');
    const container = document.querySelector('.table-container');
    if (!table || !container) return;

    // Default widths for known columns (px) - used as proportional weights
    const defaultWidths = {
        'id': 45,
        'network': 60,
        'ip': 120,
        'port': 50,
        'direction': 45,
        'subver': 120,
        'city': 80,
        'region': 50,
        'regionName': 90,
        'country': 80,
        'countryCode': 45,
        'continent': 80,
        'continentCode': 45,
        'bytessent': 65,
        'bytesrecv': 65,
        'ping_ms': 50,
        'conntime': 65,
        'connection_type': 50,
        'services_abbrev': 70,
        'lat': 55,
        'lon': 55,
        'isp': 100,
        'in_addrman': 65
    };

    // Get available width (container width minus some padding for scrollbar)
    const availableWidth = container.clientWidth - 20;

    // Calculate total default width for visible columns
    let totalDefaultWidth = 0;
    visibleColumns.forEach(col => {
        totalDefaultWidth += defaultWidths[col] || 60;
    });

    // Calculate scale factor (but don't go below 0.5 or above 1.5)
    const scale = Math.min(1.5, Math.max(0.5, availableWidth / totalDefaultWidth));

    // Apply scaled widths to visible columns
    visibleColumns.forEach(col => {
        const baseWidth = defaultWidths[col] || 60;
        const scaledWidth = Math.max(40, Math.round(baseWidth * scale));
        applyColumnWidth(col, `${scaledWidth}px`);
    });

    saveColumnWidths();
}

// Load column preferences from localStorage
function loadColumnPreferences() {
    try {
        const savedVisible = localStorage.getItem('mbcore_visible_columns');
        if (savedVisible) {
            visibleColumns = JSON.parse(savedVisible);
        }

        const savedOrder = localStorage.getItem('mbcore_column_order');
        if (savedOrder) {
            columnOrder = JSON.parse(savedOrder);
            // Ensure all default columns are in the order (in case new columns were added)
            defaultVisibleColumns.forEach(col => {
                if (!columnOrder.includes(col)) {
                    columnOrder.push(col);
                }
            });
        }

        applyColumnVisibility();

        // Reorder header cells to match saved column order
        reorderHeaderCells();
    } catch (e) {
        console.warn('Could not load column preferences:', e);
    }
}

// Reorder just the header cells (without re-rendering data)
function reorderHeaderCells() {
    const table = document.getElementById('peer-table');
    if (!table) return;

    const thead = table.querySelector('thead tr');
    if (!thead) return;

    // Get all header cells as a map
    const headerCells = {};
    thead.querySelectorAll('th[data-col]').forEach(th => {
        headerCells[th.dataset.col] = th;
    });

    // Clear and rebuild header row in new order
    const existingHeaders = Array.from(thead.querySelectorAll('th[data-col]'));
    existingHeaders.forEach(th => th.remove());

    columnOrder.forEach(col => {
        if (headerCells[col]) {
            thead.appendChild(headerCells[col]);
        }
    });
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

        // Update peer header total count (with "all" prefix)
        const countTotal = document.getElementById('count-total');
        if (countTotal) {
            countTotal.textContent = `all ${stats.connected || 0}`;
        }

        // Network stats - ALWAYS show all networks in Node Status panel
        // Use stacked In X / Out Y format with separate elements
        const networkNames = ['ipv4', 'ipv6', 'onion', 'i2p', 'cjdns'];
        const networkLabels = { 'ipv4': 'IPV4', 'ipv6': 'IPV6', 'onion': 'TOR', 'i2p': 'I2P', 'cjdns': 'CJDNS' };

        networkNames.forEach(net => {
            // Node Status panel network column elements
            const wrap = document.getElementById(`net-${net}-wrap`);
            const inEl = document.getElementById(`stat-${net}-in`);
            const outEl = document.getElementById(`stat-${net}-out`);

            // Peer header count elements
            const countEl = document.getElementById(`count-${net}`);
            const sepEl = document.getElementById(`sep-${net}`);

            // Always show network in Node Status panel
            if (wrap) {
                wrap.classList.remove('hidden');

                if (enabled.includes(net)) {
                    // Configured - show actual counts
                    wrap.classList.remove('not-configured');
                    const netData = networks[net] || {in: 0, out: 0};
                    if (inEl) inEl.textContent = netData.in;
                    if (outEl) outEl.textContent = netData.out;

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
                    // Not configured - show dashes and add class
                    wrap.classList.add('not-configured');
                    if (inEl) inEl.textContent = '-';
                    if (outEl) outEl.textContent = '-';

                    // Hide from peer header if not configured
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
    const hintEl = document.getElementById('protocol-hint');
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
        if (hintEl) hintEl.style.display = 'none';
    } else {
        const disabledList = disabledProtos
            .map(p => `<span class="proto-${p}">${protoLabels[p]}</span>`)
            .join(' ');
        disabledEl.innerHTML = disabledList;
        if (hintEl) hintEl.style.display = '';
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
    // Filter changes based on user-configured window
    const now = Date.now() / 1000;
    const filteredChanges = (changes || []).filter(change => {
        return (now - change.time) < changesWindowSeconds;
    });

    if (filteredChanges.length === 0) {
        changesTbody.innerHTML = `
            <tr class="loading-row">
                <td colspan="4">No recent changes</td>
            </tr>
        `;
        return;
    }

    const rows = filteredChanges.map(change => {
        const time = new Date(change.time * 1000).toLocaleTimeString();
        const eventClass = change.type === 'connected' ? 'event-connected' : 'event-disconnected';

        return `
            <tr>
                <td data-col="time"${getChangesColumnWidthStyle('time')}>${time}</td>
                <td data-col="event" class="${eventClass}"${getChangesColumnWidthStyle('event')}>${change.type}</td>
                <td data-col="ip"${getChangesColumnWidthStyle('ip')}>${change.peer.ip || '-'}</td>
                <td data-col="network"${getChangesColumnWidthStyle('network')}>${change.peer.network || '-'}</td>
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
    // Apply network filter
    let filteredPeers = currentPeers;
    if (networkFilter !== 'all') {
        filteredPeers = currentPeers.filter(p => p.network === networkFilter);
    }

    if (filteredPeers.length === 0) {
        const msg = networkFilter === 'all' ? 'No peers connected' : `No ${networkFilter.toUpperCase()} peers`;
        peerTbody.innerHTML = `
            <tr class="loading-row">
                <td colspan="23">${msg}</td>
            </tr>
        `;
        peerCount.textContent = networkFilter === 'all' ? '0 peers' : `0/${currentPeers.length} peers`;
        return;
    }

    // Sort peers (or keep original order if unsorted)
    let sortedPeers;
    if (sortColumn && sortDirection) {
        sortedPeers = [...filteredPeers].sort((a, b) => {
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
        sortedPeers = [...filteredPeers];
    }

    // Helper to check if column is visible
    const isVisible = (col) => visibleColumns.includes(col);
    const hiddenClass = (col) => isVisible(col) ? '' : 'col-hidden';

    // Build table HTML - 23 COLUMNS
    const rows = sortedPeers.map(peer => {
        // Network type determines row color class
        const networkRowClass = `network-row-${peer.network}`;
        const directionClass = peer.direction === 'IN' ? 'in' : 'out';

        // Geo field displays based on status
        // For private networks: all geo fields show "Private"
        // For pending lookups: all geo fields show "Stalking..."
        // For unavailable: all geo fields show "N/A"
        let geoClass = '';
        let geoDisplay = {};

        if (peer.location_status === 'private') {
            geoClass = 'location-private';
            geoDisplay = {
                city: 'Private', region: 'Private', regionName: 'Private',
                country: 'Private', countryCode: 'Priv', continent: 'Private',
                continentCode: 'Priv', lat: '-', lon: '-', isp: 'Private'
            };
        } else if (peer.location_status === 'unavailable') {
            geoClass = 'location-unavailable';
            geoDisplay = {
                city: 'N/A', region: 'N/A', regionName: 'N/A',
                country: 'N/A', countryCode: 'N/A', continent: 'N/A',
                continentCode: 'N/A', lat: '-', lon: '-', isp: 'N/A'
            };
        } else if (peer.location_status === 'pending') {
            geoClass = 'location-pending';
            geoDisplay = {
                city: 'Stalking...', region: 'Stalking...', regionName: 'Stalking...',
                country: 'Stalking...', countryCode: '...', continent: 'Stalking...',
                continentCode: '...', lat: '-', lon: '-', isp: 'Stalking...'
            };
        } else {
            // Normal display - use actual values
            geoDisplay = {
                city: peer.city || '-',
                region: peer.region || '-',
                regionName: peer.regionName || '-',
                country: peer.country || '-',
                countryCode: peer.countryCode || '-',
                continent: peer.continent || '-',
                continentCode: peer.continentCode || '-',
                lat: peer.lat ? peer.lat.toFixed(2) : '-',
                lon: peer.lon ? peer.lon.toFixed(2) : '-',
                isp: peer.isp || '-'
            };
        }

        // In addrman display
        const inAddrman = peer.in_addrman ? 'Yes' : 'No';
        const addrmanClass = peer.in_addrman ? 'addrman-yes' : 'addrman-no';

        // Network text color class for ALL columns except direction and in_addrman
        const netTextClass = `network-${peer.network}`;

        // Cell definitions for dynamic column ordering
        // Note: No JS truncation - CSS handles text-overflow with ellipsis
        // When column is resized wider, full text shows automatically
        const cellDefs = {
            'id': { class: netTextClass, title: `Peer ID: ${peer.id}`, content: peer.id },
            'network': { class: netTextClass, title: `Network: ${peer.network}`, content: peer.network },
            'ip': { class: netTextClass, title: peer.addr, content: peer.ip || '-' },
            'port': { class: netTextClass, title: `Port: ${peer.port || '-'}`, content: peer.port || '-' },
            'direction': { class: '', title: peer.direction === 'IN' ? 'Inbound: They connected to us' : 'Outbound: We connected to them', content: `<span class="direction-badge ${directionClass}">${peer.direction}</span>` },
            'subver': { class: netTextClass, title: peer.subver, content: peer.subver || '-' },
            'city': { class: `${geoClass} ${netTextClass}`, title: `City: ${geoDisplay.city}`, content: geoDisplay.city },
            'region': { class: `${geoClass} ${netTextClass}`, title: `State/Region: ${geoDisplay.region}`, content: geoDisplay.region },
            'regionName': { class: `${geoClass} ${netTextClass}`, title: `State/Region Name: ${geoDisplay.regionName}`, content: geoDisplay.regionName },
            'country': { class: `${geoClass} ${netTextClass}`, title: `Country: ${geoDisplay.country}`, content: geoDisplay.country },
            'countryCode': { class: `${geoClass} ${netTextClass}`, title: `Country Code: ${geoDisplay.countryCode}`, content: geoDisplay.countryCode },
            'continent': { class: `${geoClass} ${netTextClass}`, title: `Continent: ${geoDisplay.continent}`, content: geoDisplay.continent },
            'continentCode': { class: `${geoClass} ${netTextClass}`, title: `Continent Code: ${geoDisplay.continentCode}`, content: geoDisplay.continentCode },
            'bytessent': { class: netTextClass, title: `Bytes Sent: ${peer.bytessent_fmt}`, content: peer.bytessent_fmt },
            'bytesrecv': { class: netTextClass, title: `Bytes Received: ${peer.bytesrecv_fmt}`, content: peer.bytesrecv_fmt },
            'ping_ms': { class: netTextClass, title: `Ping: ${peer.ping_ms != null ? peer.ping_ms + 'ms' : '-'}`, content: peer.ping_ms != null ? peer.ping_ms + 'ms' : '-' },
            'conntime': { class: netTextClass, title: `Connected: ${peer.conntime_fmt}`, content: peer.conntime_fmt },
            'connection_type': { class: netTextClass, title: `Connection Type: ${peer.connection_type || '-'}`, content: peer.connection_type_abbrev || '-' },
            'services_abbrev': { class: netTextClass, title: (peer.services || []).join(', '), content: peer.services_abbrev || '-' },
            'lat': { class: `${geoClass} ${netTextClass}`, title: `Latitude: ${geoDisplay.lat}`, content: geoDisplay.lat },
            'lon': { class: `${geoClass} ${netTextClass}`, title: `Longitude: ${geoDisplay.lon}`, content: geoDisplay.lon },
            'isp': { class: `${geoClass} ${netTextClass}`, title: `ISP: ${geoDisplay.isp}`, content: geoDisplay.isp },
            'in_addrman': { class: addrmanClass, title: `In Address Manager: ${inAddrman}`, content: inAddrman }
        };

        // Build cells in column order
        const cells = columnOrder.map(col => {
            const def = cellDefs[col];
            if (!def) return '';
            return `<td data-col="${col}" class="${def.class} ${hiddenClass(col)}" title="${def.title}"${getColumnWidthStyle(col)}>${def.content}</td>`;
        }).join('');

        return `<tr data-id="${peer.id}" class="${networkRowClass}">${cells}</tr>`;
    }).join('');

    peerTbody.innerHTML = rows;
    // Fit columns to window on first data load
    if (!autoSizedColumns && currentPeers.length) {
        fitColumnsToWindow();
        autoSizedColumns = true;
    }
    // Show count with filter info
    if (networkFilter === 'all') {
        peerCount.textContent = `${filteredPeers.length} peers`;
    } else {
        peerCount.textContent = `${filteredPeers.length}/${currentPeers.length} peers`;
    }
}

// Truncate string
function truncate(str, maxLen) {
    if (!str) return '-';
    if (str.length <= maxLen) return str;
    return str.substring(0, maxLen - 3) + '...';
}

// Countdown timer
function startCountdown() {
    countdown = refreshInterval / 1000;
    updateCountdownDisplay();

    refreshTimer = setInterval(() => {
        countdown--;
        if (countdown <= 0) {
            countdown = refreshInterval / 1000;
        }
        updateCountdownDisplay();
        updateLocalTime();
    }, 1000);

    // Initialize local time
    updateLocalTime();
}

function resetCountdown() {
    countdown = refreshInterval / 1000;
    updateCountdownDisplay();
}

// Setup refresh rate control (text input in stats bar)
function setupRefreshRateControl() {
    // Load saved preference
    try {
        const saved = localStorage.getItem('mbcore_refresh_interval');
        if (saved) {
            const interval = parseInt(saved, 10);
            if (interval >= 1000 && interval <= 300000) { // 1s to 5min
                refreshInterval = interval;
            }
        }
    } catch (e) {}

    const input = document.getElementById('refresh-rate-input');
    if (!input) return;

    // Set initial value from loaded preference
    input.value = refreshInterval / 1000;

    // Handle input changes (on blur or enter)
    const applyValue = () => {
        const seconds = parseInt(input.value, 10);
        if (!isNaN(seconds) && seconds >= 1 && seconds <= 300) {
            refreshInterval = seconds * 1000;

            // Save preference
            try {
                localStorage.setItem('mbcore_refresh_interval', refreshInterval.toString());
            } catch (e) {}

            // Reset countdown to new interval
            resetCountdown();
        } else {
            // Invalid input, reset to current value
            input.value = refreshInterval / 1000;
        }
    };

    input.addEventListener('blur', applyValue);
    input.addEventListener('keydown', (e) => {
        if (e.key === 'Enter') {
            e.preventDefault();
            applyValue();
            input.blur();
        }
    });
}

// Setup changes window control (dropdown in Recent Changes header)
function setupChangesWindowControl() {
    // Load saved preference
    try {
        const saved = localStorage.getItem('mbcore_changes_window');
        if (saved) {
            const seconds = parseInt(saved, 10);
            if (seconds >= 10 && seconds <= 300) {
                changesWindowSeconds = seconds;
            }
        }
    } catch (e) {}

    const btn = document.getElementById('changes-config-btn');
    const dropdown = document.getElementById('changes-config-dropdown');
    const valueSpan = document.getElementById('changes-window-value');
    if (!btn || !dropdown) return;

    // Update display
    updateChangesWindowDisplay();

    // Toggle dropdown on button click
    btn.addEventListener('click', (e) => {
        e.stopPropagation();
        dropdown.classList.toggle('active');
    });

    // Close dropdown when clicking outside
    document.addEventListener('click', () => {
        dropdown.classList.remove('active');
    });

    // Handle option clicks
    dropdown.querySelectorAll('.dropdown-option').forEach(option => {
        option.addEventListener('click', (e) => {
            e.stopPropagation();
            const seconds = parseInt(option.dataset.seconds, 10);
            if (!isNaN(seconds)) {
                changesWindowSeconds = seconds;

                // Save preference
                try {
                    localStorage.setItem('mbcore_changes_window', seconds.toString());
                } catch (e) {}

                // Update display
                updateChangesWindowDisplay();

                // Close dropdown
                dropdown.classList.remove('active');

                // Refresh changes to apply filter
                fetchChanges();
            }
        });
    });
}

function updateChangesWindowDisplay() {
    const valueSpan = document.getElementById('changes-window-value');
    const dropdown = document.getElementById('changes-config-dropdown');

    if (valueSpan) {
        // Display in seconds or minutes
        if (changesWindowSeconds >= 60) {
            valueSpan.textContent = (changesWindowSeconds / 60);
            valueSpan.nextSibling.textContent = ' minute' + (changesWindowSeconds > 60 ? 's' : '');
        } else {
            valueSpan.textContent = changesWindowSeconds;
            valueSpan.nextSibling.textContent = ' seconds';
        }
    }

    // Update active state on buttons
    if (dropdown) {
        dropdown.querySelectorAll('.dropdown-option').forEach(option => {
            const seconds = parseInt(option.dataset.seconds, 10);
            if (seconds === changesWindowSeconds) {
                option.classList.add('active');
            } else {
                option.classList.remove('active');
            }
        });
    }
}

// Setup Antarctica dots show/hide toggle
function setupAntarcticaToggle() {
    const toggle = document.getElementById('antarctica-toggle');
    if (!toggle) return;

    // Load saved preference (default to showing)
    try {
        const saved = localStorage.getItem('mbcore_show_antarctica');
        if (saved !== null) {
            showAntarcticaDots = saved === 'true';
            toggle.textContent = showAntarcticaDots ? 'Hide' : 'Show';
        }
    } catch (e) {}

    toggle.addEventListener('click', (e) => {
        e.preventDefault();
        showAntarcticaDots = !showAntarcticaDots;
        toggle.textContent = showAntarcticaDots ? 'Hide' : 'Show';

        // Save preference
        try {
            localStorage.setItem('mbcore_show_antarctica', showAntarcticaDots.toString());
        } catch (e) {}

        // Refresh map to apply change
        updateMap();
    });
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
    if (infoTimer) {
        clearInterval(infoTimer);
    }
});

// ═══════════════════════════════════════════════════════════════════════════════
// NODE STATUS PANEL
// ═══════════════════════════════════════════════════════════════════════════════

let infoCurrency = 'USD';
let infoTimer = null;
let infoVisibility = {
    networks: true,
    chain: true,
    system: true,
    btc: true
};

// Initialize node status panel on DOM load
document.addEventListener('DOMContentLoaded', () => {
    loadNodeStatusPreferences();
    setupNodeStatusControls();
    fetchInfoPanel();
    startInfoPanelTimer();
});

// Load node status panel preferences from localStorage
function loadNodeStatusPreferences() {
    try {
        // Currency
        const savedCurrency = localStorage.getItem('mbcore_info_currency');
        if (savedCurrency) {
            infoCurrency = savedCurrency;
            const select = document.getElementById('info-currency-select');
            if (select) select.value = infoCurrency;
        }

        // Visibility settings
        const savedVisibility = localStorage.getItem('mbcore_card_visibility');
        if (savedVisibility) {
            infoVisibility = JSON.parse(savedVisibility);
        }
        applyCardVisibility();
    } catch (e) {
        console.warn('Could not load node status preferences:', e);
    }
}

// Setup node status panel controls
function setupNodeStatusControls() {
    const configBtn = document.getElementById('node-config-btn');
    const dropdown = document.getElementById('node-config-dropdown');

    // Toggle dropdown with fixed positioning
    if (configBtn && dropdown) {
        configBtn.addEventListener('click', (e) => {
            e.stopPropagation();

            // Position dropdown relative to button using fixed positioning
            const btnRect = configBtn.getBoundingClientRect();
            dropdown.style.top = (btnRect.bottom + 4) + 'px';
            dropdown.style.right = (window.innerWidth - btnRect.right) + 'px';
            dropdown.style.left = 'auto';

            dropdown.classList.toggle('active');
        });

        // Close dropdown when clicking outside
        document.addEventListener('click', () => {
            dropdown.classList.remove('active');
        });

        dropdown.addEventListener('click', (e) => {
            e.stopPropagation();
        });

        // Reposition dropdown on window resize
        window.addEventListener('resize', () => {
            if (dropdown.classList.contains('active')) {
                const btnRect = configBtn.getBoundingClientRect();
                dropdown.style.top = (btnRect.bottom + 4) + 'px';
                dropdown.style.right = (window.innerWidth - btnRect.right) + 'px';
            }
        });
    }

    // Currency select
    const currencySelect = document.getElementById('info-currency-select');
    if (currencySelect) {
        currencySelect.addEventListener('change', () => {
            infoCurrency = currencySelect.value;
            localStorage.setItem('mbcore_info_currency', infoCurrency);
            fetchInfoPanel(); // Refresh immediately
        });
    }

    // Visibility checkboxes for cards
    const visibilityMap = {
        'info-show-networks': 'networks',
        'info-show-chain': 'chain',
        'info-show-system': 'system',
        'info-show-btc': 'btc'
    };

    Object.entries(visibilityMap).forEach(([id, key]) => {
        const checkbox = document.getElementById(id);
        if (checkbox) {
            checkbox.checked = infoVisibility[key];
            checkbox.addEventListener('change', () => {
                infoVisibility[key] = checkbox.checked;
                localStorage.setItem('mbcore_card_visibility', JSON.stringify(infoVisibility));
                applyCardVisibility();
            });
        }
    });
}

// Apply visibility settings to cards
function applyCardVisibility() {
    const cards = {
        'networks': 'card-networks',
        'chain': 'card-node',
        'system': 'card-system',
        'btc': 'card-btc'
    };

    Object.entries(cards).forEach(([key, id]) => {
        const el = document.getElementById(id);
        if (el) {
            if (infoVisibility[key]) {
                el.classList.remove('hidden');
            } else {
                el.classList.add('hidden');
            }
        }
    });
}

// Start info panel update timer (uses the main refresh interval)
function startInfoPanelTimer() {
    // Info panel updates every 60 seconds by default
    infoTimer = setInterval(() => {
        fetchInfoPanel();
    }, 60000);
}

// Fetch info panel data from API
async function fetchInfoPanel() {
    try {
        const response = await fetch(`${API_BASE}/api/info?currency=${infoCurrency}`);
        if (!response.ok) throw new Error('Failed to fetch info');

        const data = await response.json();
        updateInfoPanel(data);
    } catch (error) {
        console.error('Error fetching info panel:', error);
    }
}

// Format price with appropriate decimal places
function formatPrice(priceStr, currency) {
    if (!priceStr) return '-';

    const price = parseFloat(priceStr);
    if (isNaN(price)) return '-';

    // Currencies that typically don't use decimals
    const noDecimalCurrencies = ['JPY', 'KRW'];

    if (noDecimalCurrencies.includes(currency)) {
        return Math.round(price).toLocaleString();
    }

    // If the price has more than 2 decimal places, show up to 4
    // Otherwise show 2
    const decimalPart = priceStr.split('.')[1] || '';
    if (decimalPart.length > 2) {
        // Show up to 4 decimals, but trim trailing zeros
        const formatted = price.toFixed(4);
        return parseFloat(formatted).toLocaleString(undefined, {
            minimumFractionDigits: 2,
            maximumFractionDigits: 4
        });
    } else {
        return price.toLocaleString(undefined, {
            minimumFractionDigits: 2,
            maximumFractionDigits: 2
        });
    }
}

// Format block time to local time string
function formatBlockTime(timestamp) {
    if (!timestamp) return '-';

    const date = new Date(timestamp * 1000);
    const month = date.getMonth() + 1;
    const day = date.getDate();
    let hours = date.getHours();
    const minutes = date.getMinutes().toString().padStart(2, '0');
    const ampm = hours >= 12 ? 'p' : 'a';
    hours = hours % 12;
    hours = hours ? hours : 12; // 0 becomes 12

    return `${month}/${day} ${hours}:${minutes}${ampm}`;
}

// Update node status panel with data
function updateInfoPanel(data) {
    // BTC Price
    const priceEl = document.getElementById('info-btc-price');
    const currencyEl = document.getElementById('info-btc-currency');
    if (priceEl) {
        priceEl.textContent = '$' + formatPrice(data.btc_price, data.btc_currency);
    }
    if (currencyEl) {
        currencyEl.textContent = data.btc_currency || 'USD';
    }

    // Last Block
    const blockEl = document.getElementById('info-last-block');
    if (blockEl && data.last_block) {
        const timeStr = formatBlockTime(data.last_block.time);
        blockEl.textContent = `${timeStr} (${data.last_block.height.toLocaleString()})`;
    }

    // Node Info Card
    const sizeEl = document.getElementById('info-chain-size');
    const typeEl = document.getElementById('info-node-type');
    const indexedEl = document.getElementById('info-node-indexed');
    const syncEl = document.getElementById('info-sync-status');

    if (data.blockchain) {
        if (sizeEl) {
            sizeEl.textContent = `${data.blockchain.size_gb} GB`;
        }
        if (typeEl) {
            typeEl.textContent = data.blockchain.pruned ? 'Pruned' : 'Full Node';
        }
        if (indexedEl) {
            indexedEl.textContent = data.blockchain.indexed ? 'Indexed' : 'Not Indexed';
        }
        if (syncEl) {
            const upToDate = !data.blockchain.ibd;
            syncEl.textContent = upToDate ? 'Up to date' : 'Syncing...';
            syncEl.className = 'node-info-value ' + (upToDate ? 'status-ok' : 'status-syncing');
        }
    }

    // Network Scores (IPv4 and IPv6 only)
    const ipv4El = document.getElementById('info-score-ipv4');
    const ipv6El = document.getElementById('info-score-ipv6');
    if (data.network_scores) {
        if (ipv4El) {
            ipv4El.textContent = data.network_scores.ipv4 !== null
                ? data.network_scores.ipv4.toLocaleString()
                : '-';
        }
        if (ipv6El) {
            ipv6El.textContent = data.network_scores.ipv6 !== null
                ? data.network_scores.ipv6.toLocaleString()
                : '-';
        }
    }

    // System Stats
    const cpuEl = document.getElementById('info-cpu');
    const memEl = document.getElementById('info-mem');
    if (data.system_stats) {
        if (cpuEl) {
            cpuEl.textContent = data.system_stats.cpu_pct !== null
                ? data.system_stats.cpu_pct
                : '-';
        }
        if (memEl) {
            memEl.textContent = data.system_stats.mem_pct !== null
                ? data.system_stats.mem_pct
                : '-';
        }
    }
}
