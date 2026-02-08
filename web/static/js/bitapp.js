/* ============================================================
   MBCore vNext — Canvas World Map with Real Bitcoin Peers
   Phase 2.1: Real peer data from /api/peers, no fake nodes
   ============================================================
   - Fetches real peers from the existing MBCoreServer backend
   - Renders them on a canvas world map (no Leaflet)
   - Private/overlay networks (Tor, I2P, CJDNS) placed in Antarctica
   - Polls every 10s with fade-in for new peers, fade-out for gone peers
   - Pan, zoom, hover tooltips all preserved from Phase 1
   ============================================================ */

(function () {
    'use strict';

    // ═══════════════════════════════════════════════════════════
    // CONFIGURATION
    // ═══════════════════════════════════════════════════════════

    const CFG = {
        pollInterval: 10000,       // ms between /api/peers fetches
        infoPollInterval: 15000,   // ms between /api/info fetches
        nodeRadius: 3,             // base circle radius in px
        glowRadius: 14,            // outer glow radius in px
        pulseSpeed: 0.0018,        // glow pulse speed (radians per ms)
        fadeInDuration: 800,       // ms for new node spawn animation
        fadeOutDuration: 1500,     // ms for disconnected node fade-out
        minZoom: 0.5,
        maxZoom: 8,
        zoomStep: 1.15,
        panSmooth: 0.12,           // smoothing factor for view interpolation
        gridSpacing: 30,           // degrees between grid lines
        coastlineWidth: 1.0,
    };

    // ═══════════════════════════════════════════════════════════
    // NETWORK COLOURS (match bitstyle.css --net-* variables)
    // ═══════════════════════════════════════════════════════════

    const NET_COLORS = {
        ipv4:  { r: 227, g: 179, b: 65  },   // gold
        ipv6:  { r: 240, g: 113, b: 120 },   // coral
        onion: { r: 74,  g: 158, b: 255 },   // sky blue (Tor)
        i2p:   { r: 139, g: 92,  b: 246 },   // purple
        cjdns: { r: 210, g: 168, b: 255 },   // lavender
    };
    // Fallback colour for unknown network types
    const NET_COLOR_UNKNOWN = { r: 120, g: 130, b: 140 };

    // Map internal network names to display-friendly labels
    const NET_DISPLAY = {
        ipv4: 'IPv4', ipv6: 'IPv6', onion: 'Tor', i2p: 'I2P', cjdns: 'CJDNS',
    };

    // ═══════════════════════════════════════════════════════════
    // ANTARCTICA RESEARCH STATIONS
    // Private/overlay peers get placed here (same stations as v5)
    // ═══════════════════════════════════════════════════════════

    const ANTARCTICA_STATIONS = [
        { lat: -67.6020, lon: 62.8730  },  // Mawson Station
        { lat: -68.5760, lon: 77.9670  },  // Davis Station
        { lat: -66.2810, lon: 110.5280 },  // Casey Station
        { lat: -66.6630, lon: 140.0010 },  // Dumont d'Urville
        { lat: -69.0050, lon: 39.5800  },  // Syowa Station
        { lat: -70.6670, lon: 11.6330  },  // Novolazarevskaya
        { lat: -70.7500, lon: -8.2500  },  // Neumayer Station
        { lat: -70.4500, lon: -2.8420  },  // SANAE IV Station
    ];

    // Cache so each peer always lands on the same Antarctica spot
    const antarcticaCache = {};

    // ═══════════════════════════════════════════════════════════
    // CANVAS & VIEW STATE
    // ═══════════════════════════════════════════════════════════

    const canvas = document.getElementById('worldmap');
    const ctx = canvas.getContext('2d');
    let W, H;  // canvas logical dimensions (CSS pixels)

    // Current view (smoothly interpolated each frame)
    let view = { x: 0, y: 0, zoom: 1 };
    // Target view (set instantly by user input, view lerps toward it)
    let targetView = { x: 0, y: 0, zoom: 1 };

    // Mouse drag state
    let dragging = false;
    let dragStart = { x: 0, y: 0 };
    let dragViewStart = { x: 0, y: 0 };

    // ═══════════════════════════════════════════════════════════
    // NODE STATE
    // Nodes are built from /api/peers responses.
    // Each node has animation metadata (spawnTime, fadeOutStart).
    // ═══════════════════════════════════════════════════════════

    let nodes = [];          // currently visible + fading-out nodes
    let knownPeerIds = {};   // id -> true, tracks which peers we've seen

    // ═══════════════════════════════════════════════════════════
    // WORLD GEOMETRY STATE
    // Land polygons, lake polygons, borders, and cities loaded
    // from static assets. Each layer appears at different zoom levels.
    // ═══════════════════════════════════════════════════════════

    let worldPolygons = [];
    let lakePolygons = [];
    let borderLines = [];      // country border line strings
    let stateLines = [];       // state/province border line strings
    let cityPoints = [];       // { n: name, p: population, c: [lon,lat] }
    let worldReady = false;
    let lakesReady = false;
    let bordersReady = false;
    let statesReady = false;
    let citiesReady = false;

    // Zoom thresholds for progressive detail layers
    // Country borders render at ALL zoom levels (no threshold)
    const ZOOM_SHOW_STATES  = 3.0;   // state/province borders appear
    const ZOOM_SHOW_CITIES_MAJOR = 3.5;  // cities > 5M population (only with borders as context)
    const ZOOM_SHOW_CITIES_LARGE = 4.5;  // cities > 1M population
    const ZOOM_SHOW_CITIES_MED   = 5.5;  // cities > 300K population
    const ZOOM_SHOW_CITIES_ALL   = 7.0;  // all cities

    // DOM references
    const clockEl = document.getElementById('clock');
    const tooltipEl = document.getElementById('node-tooltip');
    let hoveredNode = null;

    // ═══════════════════════════════════════════════════════════
    // HELPERS
    // ═══════════════════════════════════════════════════════════

    /** Mercator projection: lon/lat -> normalised 0..1 coordinates */
    function project(lon, lat) {
        const x = (lon + 180) / 360;
        const latRad = lat * Math.PI / 180;
        const mercN = Math.log(Math.tan(Math.PI / 4 + latRad / 2));
        const y = 0.5 - mercN / (2 * Math.PI);
        return { x, y };
    }

    /** Convert lon/lat to screen pixel coordinates using current view */
    function worldToScreen(lon, lat) {
        const p = project(lon, lat);
        const sx = (p.x - 0.5) * W * view.zoom + W / 2 - view.x * view.zoom;
        const sy = (p.y - 0.5) * H * view.zoom + H / 2 - view.y * view.zoom;
        return { x: sx, y: sy };
    }

    /** Convert screen pixel coordinates back to lon/lat */
    function screenToWorld(sx, sy) {
        const px = ((sx - W / 2 + view.x * view.zoom) / (W * view.zoom)) + 0.5;
        const py = ((sy - H / 2 + view.y * view.zoom) / (H * view.zoom)) + 0.5;
        const lon = px * 360 - 180;
        const mercN = (0.5 - py) * 2 * Math.PI;
        const lat = (2 * Math.atan(Math.exp(mercN)) - Math.PI / 2) * 180 / Math.PI;
        return { lon, lat };
    }

    function rgba(c, a) {
        return `rgba(${c.r},${c.g},${c.b},${a})`;
    }

    function lerp(a, b, t) {
        return a + (b - a) * t;
    }

    function clamp(v, min, max) {
        return Math.max(min, Math.min(max, v));
    }

    /** Simple deterministic hash for stable Antarctica placement */
    function hashString(str) {
        let hash = 0;
        for (let i = 0; i < str.length; i++) {
            hash = ((hash << 5) - hash) + str.charCodeAt(i);
            hash = hash & hash;  // force 32-bit integer
        }
        return hash;
    }

    // ═══════════════════════════════════════════════════════════
    // ANTARCTICA PLACEMENT
    // Peers with location_status "private" or "unavailable" (or
    // overlay networks like Tor/I2P/CJDNS) are placed near
    // Antarctic research stations with a deterministic offset
    // so they don't jump around between refreshes.
    // ═══════════════════════════════════════════════════════════

    function getAntarcticaPosition(addr) {
        if (antarcticaCache[addr]) return antarcticaCache[addr];

        const h1 = hashString(addr);
        const h2 = hashString(addr + '_offset');

        // Pick a station deterministically
        const idx = Math.abs(h1) % ANTARCTICA_STATIONS.length;
        const station = ANTARCTICA_STATIONS[idx];

        // Small offset (±0.5 deg) so peers near same station don't stack
        const latOff = ((Math.abs(h2) % 100) / 100 - 0.5) * 1.0;
        const lonOff = ((Math.abs(h2 >> 8) % 100) / 100 - 0.5) * 1.0;

        const pos = { lat: station.lat + latOff, lon: station.lon + lonOff };
        antarcticaCache[addr] = pos;
        return pos;
    }

    // ═══════════════════════════════════════════════════════════
    // WORLD MAP GEOMETRY — Real Natural Earth 50m landmasses
    // Loaded from /static/assets/world-50m.json on startup.
    // Format: array of polygons, each polygon is an array of
    // rings (outer + holes), each ring is [[lon,lat], ...].
    // Source: Natural Earth (public domain), stripped to coords only.
    // 50m gives much better coastline detail than 110m (~1410 polygons
    // vs 127), while still being fast to load and render on canvas.
    // ═══════════════════════════════════════════════════════════

    async function loadWorldGeometry() {
        try {
            const resp = await fetch('/static/assets/world-50m.json');
            if (!resp.ok) throw new Error(`HTTP ${resp.status}`);
            const polygons = await resp.json();

            // Convert to our internal format: each entry is { rings: [[[lon,lat],...], ...] }
            // The first ring is the outer boundary, subsequent rings are holes (lakes etc)
            worldPolygons = polygons;
            worldReady = true;
            console.log(`[vNext] Loaded ${polygons.length} land polygons`);
        } catch (err) {
            console.error('[vNext] Failed to load world geometry, using fallback:', err);
            // Fallback: minimal hand-traced outlines so the map isn't blank
            worldPolygons = [
                [[[-130,50],[-125,60],[-115,68],[-95,72],[-80,72],[-65,62],[-55,50],[-60,45],[-68,44],[-75,38],[-82,30],[-90,28],[-97,26],[-105,30],[-118,34],[-125,42],[-130,50]]],
                [[[-80,10],[-75,12],[-63,10],[-52,4],[-42,0],[-35,-5],[-35,-12],[-38,-18],[-42,-22],[-48,-28],[-52,-33],[-58,-38],[-65,-45],[-68,-53],[-72,-48],[-75,-42],[-72,-35],[-68,-28],[-70,-18],[-75,-10],[-80,0],[-80,10]]],
                [[[-10,36],[0,38],[3,42],[5,44],[2,48],[-5,48],[-8,54],[-5,58],[5,62],[12,58],[18,55],[24,58],[30,60],[35,58],[42,55],[45,50],[40,45],[35,40],[28,36],[20,36],[12,38],[5,38],[0,36],[-10,36]]],
                [[[-15,12],[-17,15],[-12,25],[-5,35],[0,36],[10,37],[12,32],[20,32],[25,30],[32,32],[35,30],[42,12],[50,2],[42,-5],[40,-12],[35,-22],[30,-30],[22,-34],[18,-34],[15,-28],[12,-18],[8,-5],[5,5],[0,6],[-8,5],[-15,12]]],
                [[[28,36],[35,40],[42,48],[50,50],[55,55],[60,60],[65,68],[75,72],[90,72],[100,68],[115,65],[125,60],[130,55],[140,55],[145,50],[142,44],[135,38],[128,34],[122,30],[115,24],[108,18],[105,12],[100,5],[98,8],[95,15],[88,22],[80,28],[72,32],[60,38],[50,40],[42,45],[35,40],[28,36]]],
                [[[115,-15],[120,-14],[130,-12],[135,-14],[140,-16],[148,-20],[152,-25],[153,-28],[150,-33],[145,-38],[137,-35],[130,-32],[122,-33],[116,-32],[114,-28],[114,-22],[118,-20],[120,-18],[115,-15]]],
            ];
            worldReady = true;
        }
    }

    // ═══════════════════════════════════════════════════════════
    // LAKES GEOMETRY — Natural Earth 50m major lakes
    // Loaded from /static/assets/lakes-50m.json on startup.
    // Rendered on top of land using the ocean background colour
    // to "carve out" Great Lakes, Caspian Sea, Lake Victoria, etc.
    // ═══════════════════════════════════════════════════════════

    async function loadLakeGeometry() {
        try {
            const resp = await fetch('/static/assets/lakes-50m.json');
            if (!resp.ok) throw new Error(`HTTP ${resp.status}`);
            lakePolygons = await resp.json();
            lakesReady = true;
            console.log(`[vNext] Loaded ${lakePolygons.length} lake polygons`);
        } catch (err) {
            // Lakes are non-critical — map still works without them
            console.warn('[vNext] Failed to load lake geometry:', err);
        }
    }

    // ═══════════════════════════════════════════════════════════
    // COUNTRY BORDERS — Natural Earth 50m admin-0 boundary lines
    // Subtle dashed lines between countries, visible at medium zoom.
    // ═══════════════════════════════════════════════════════════

    async function loadBorderGeometry() {
        try {
            const resp = await fetch('/static/assets/borders-50m.json');
            if (!resp.ok) throw new Error(`HTTP ${resp.status}`);
            borderLines = await resp.json();
            bordersReady = true;
            console.log(`[vNext] Loaded ${borderLines.length} country border lines`);
        } catch (err) {
            console.warn('[vNext] Failed to load country borders:', err);
        }
    }

    // ═══════════════════════════════════════════════════════════
    // STATE/PROVINCE BORDERS — Natural Earth 50m admin-1 lines
    // Even subtler lines, visible only at higher zoom.
    // ═══════════════════════════════════════════════════════════

    async function loadStateGeometry() {
        try {
            const resp = await fetch('/static/assets/states-50m.json');
            if (!resp.ok) throw new Error(`HTTP ${resp.status}`);
            stateLines = await resp.json();
            statesReady = true;
            console.log(`[vNext] Loaded ${stateLines.length} state/province border lines`);
        } catch (err) {
            console.warn('[vNext] Failed to load state borders:', err);
        }
    }

    // ═══════════════════════════════════════════════════════════
    // CITIES — Natural Earth 50m populated places
    // Point data with name and population, shown at high zoom.
    // ═══════════════════════════════════════════════════════════

    async function loadCityData() {
        try {
            const resp = await fetch('/static/assets/cities-50m.json');
            if (!resp.ok) throw new Error(`HTTP ${resp.status}`);
            cityPoints = await resp.json();
            citiesReady = true;
            console.log(`[vNext] Loaded ${cityPoints.length} cities`);
        } catch (err) {
            console.warn('[vNext] Failed to load city data:', err);
        }
    }

    // ═══════════════════════════════════════════════════════════
    // DATA FETCHING — Real peers from /api/peers
    // ═══════════════════════════════════════════════════════════

    /**
     * Fetch peers from the backend and transform them into canvas nodes.
     * - Peers with valid lat/lon and location_status "ok" use real coords
     * - Private/unavailable/pending peers go to Antarctica
     * - Existing nodes that are no longer in the response start fading out
     * - New nodes fade in with a spawn animation
     */
    async function fetchPeers() {
        try {
            const resp = await fetch('/api/peers');
            if (!resp.ok) throw new Error(`HTTP ${resp.status}`);
            const peers = await resp.json();

            const now = Date.now();

            // Build a set of peer IDs from this response
            const currentIds = new Set();
            for (const p of peers) currentIds.add(p.id);

            // ── Mark departed peers for fade-out ──
            // If a node was alive and is no longer in the response, start its fade-out
            for (const node of nodes) {
                if (node.alive && !currentIds.has(node.peerId)) {
                    node.alive = false;
                    node.fadeOutStart = now;
                }
            }

            // ── Add or update existing peers ──
            for (const peer of peers) {
                const existing = nodes.find(n => n.peerId === peer.id && n.alive);

                // Determine map coordinates
                let lat, lon;
                const isPrivate = (
                    peer.location_status === 'private' ||
                    peer.location_status === 'unavailable' ||
                    peer.location_status === 'pending'
                );

                if (isPrivate || (peer.lat === 0 && peer.lon === 0)) {
                    // Place in Antarctica with stable position
                    const pos = getAntarcticaPosition(peer.addr || `peer-${peer.id}`);
                    lat = pos.lat;
                    lon = pos.lon;
                } else {
                    lat = peer.lat;
                    lon = peer.lon;
                }

                // Resolve network colour
                const netKey = peer.network || 'ipv4';
                const color = NET_COLORS[netKey] || NET_COLOR_UNKNOWN;

                if (existing) {
                    // ── Update in place (peer still connected) ──
                    // Update data that might change (ping, bytes, etc)
                    existing.lat = lat;
                    existing.lon = lon;
                    existing.ping = peer.ping_ms || 0;
                    existing.city = peer.city || '';
                    existing.country = peer.country || peer.countryCode || '';
                    existing.subver = peer.subver || '';
                    existing.direction = peer.direction || '';
                    existing.conntime_fmt = peer.conntime_fmt || '';
                    existing.isp = peer.isp || '';
                    existing.isPrivate = isPrivate;
                    existing.location_status = peer.location_status;
                } else {
                    // ── New peer — create node with spawn animation ──
                    nodes.push({
                        peerId: peer.id,
                        lat,
                        lon,
                        net: netKey,
                        color,
                        city: peer.city || '',
                        country: peer.country || peer.countryCode || '',
                        subver: peer.subver || '',
                        direction: peer.direction || '',
                        ping: peer.ping_ms || 0,
                        conntime_fmt: peer.conntime_fmt || '',
                        isp: peer.isp || '',
                        isPrivate,
                        location_status: peer.location_status,
                        addr: peer.addr || '',
                        // Animation state
                        phase: Math.random() * Math.PI * 2,  // random pulse phase
                        spawnTime: now,                       // triggers fade-in animation
                        alive: true,
                        fadeOutStart: null,
                    });
                }
            }

            // ── Garbage collect fully faded-out nodes ──
            nodes = nodes.filter(n => {
                if (!n.alive && n.fadeOutStart) {
                    return (now - n.fadeOutStart) < CFG.fadeOutDuration;
                }
                return true;
            });

            // Update connection status in the topbar
            updateConnectionStatus(peers.length > 0);

        } catch (err) {
            console.error('[vNext] Failed to fetch peers:', err);
            updateConnectionStatus(false);
        }
    }

    // ═══════════════════════════════════════════════════════════
    // DATA FETCHING — Node info from /api/info (block height)
    // ═══════════════════════════════════════════════════════════

    let lastBlockHeight = null;

    async function fetchInfo() {
        try {
            const resp = await fetch('/api/info?currency=USD');
            if (!resp.ok) return;
            const info = await resp.json();

            // Update block height HUD
            if (info.last_block && info.last_block.height) {
                lastBlockHeight = info.last_block.height;
            }
        } catch (err) {
            console.error('[vNext] Failed to fetch info:', err);
        }
    }

    // ═══════════════════════════════════════════════════════════
    // CONNECTION STATUS (topbar dot + text)
    // ═══════════════════════════════════════════════════════════

    function updateConnectionStatus(connected) {
        const dot = document.getElementById('status-dot');
        const txt = document.getElementById('status-text');
        if (connected) {
            dot.classList.add('online');
            txt.textContent = 'Connected';
        } else {
            dot.classList.remove('online');
            txt.textContent = 'Offline';
        }
    }

    // ═══════════════════════════════════════════════════════════
    // CANVAS RESIZE
    // Handles high-DPI displays via devicePixelRatio scaling.
    // ═══════════════════════════════════════════════════════════

    function resize() {
        const dpr = window.devicePixelRatio || 1;
        W = window.innerWidth;
        H = window.innerHeight;
        canvas.width = W * dpr;
        canvas.height = H * dpr;
        canvas.style.width = W + 'px';
        canvas.style.height = H + 'px';
        ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    }

    // ═══════════════════════════════════════════════════════════
    // DRAWING — Grid, landmasses, lakes, borders, cities, nodes
    // World is locked to a single copy (no horizontal wrap).
    // ═══════════════════════════════════════════════════════════

    /**
     * Returns longitude offsets for world rendering.
     * Currently locked to a single copy (no horizontal wrap).
     */
    function getWrapOffsets() {
        return [0];
    }

    /** Draw subtle lat/lon grid lines (with wrap) */
    function drawGrid() {
        ctx.strokeStyle = 'rgba(88,166,255,0.04)';
        ctx.lineWidth = 0.5;
        const offsets = getWrapOffsets();

        for (const off of offsets) {
            // Longitude lines (vertical on map)
            for (let lon = -180; lon <= 180; lon += CFG.gridSpacing) {
                ctx.beginPath();
                for (let lat = -85; lat <= 85; lat += 2) {
                    const s = worldToScreen(lon + off, lat);
                    if (lat === -85) ctx.moveTo(s.x, s.y);
                    else ctx.lineTo(s.x, s.y);
                }
                ctx.stroke();
            }

            // Latitude lines (horizontal on map)
            for (let lat = -60; lat <= 80; lat += CFG.gridSpacing) {
                ctx.beginPath();
                for (let lon = -180; lon <= 180; lon += 2) {
                    const s = worldToScreen(lon + off, lat);
                    if (lon === -180) ctx.moveTo(s.x, s.y);
                    else ctx.lineTo(s.x, s.y);
                }
                ctx.stroke();
            }
        }
    }

    /**
     * Draw a set of polygons (land or lakes) at a given longitude offset.
     * Each polygon has one or more rings: ring[0] = outer boundary,
     * ring[1+] = holes. Uses evenodd fill rule to cut out holes.
     */
    function drawPolygonSet(polygons, fillStyle, strokeStyle, lonOffset) {
        ctx.fillStyle = fillStyle;
        ctx.strokeStyle = strokeStyle;
        ctx.lineWidth = CFG.coastlineWidth;

        for (const poly of polygons) {
            ctx.beginPath();
            for (const ring of poly) {
                for (let i = 0; i < ring.length; i++) {
                    const s = worldToScreen(ring[i][0] + lonOffset, ring[i][1]);
                    if (i === 0) ctx.moveTo(s.x, s.y);
                    else ctx.lineTo(s.x, s.y);
                }
                ctx.closePath();
            }
            ctx.fill('evenodd');
            ctx.stroke();
        }
    }

    /** Draw landmasses at all visible wrap positions */
    function drawLandmasses() {
        if (!worldReady) return;
        const offsets = getWrapOffsets();
        for (const off of offsets) {
            drawPolygonSet(worldPolygons, '#151d28', '#253040', off);
        }
    }

    /** Draw lakes on top of land using ocean colour to "carve" them out */
    function drawLakes() {
        if (!lakesReady) return;
        const offsets = getWrapOffsets();
        for (const off of offsets) {
            // Lakes filled with ocean colour, subtle darker stroke
            drawPolygonSet(lakePolygons, '#06080c', '#1a2230', off);
        }
    }

    /**
     * Draw line strings (borders) at a given longitude offset.
     * Used for both country and state borders.
     */
    function drawLineSet(lines, strokeStyle, lineWidth, lonOffset) {
        ctx.strokeStyle = strokeStyle;
        ctx.lineWidth = lineWidth;
        for (const line of lines) {
            ctx.beginPath();
            for (let i = 0; i < line.length; i++) {
                const s = worldToScreen(line[i][0] + lonOffset, line[i][1]);
                if (i === 0) ctx.moveTo(s.x, s.y);
                else ctx.lineTo(s.x, s.y);
            }
            ctx.stroke();
        }
    }

    /** Draw country borders at all zoom levels — always visible */
    function drawCountryBorders() {
        if (!bordersReady) return;
        // Constant subtle alpha at all zoom levels; slightly brighter when zoomed in
        const alpha = 0.12 + clamp((view.zoom - 1) / 4, 0, 1) * 0.08;
        const offsets = getWrapOffsets();
        for (const off of offsets) {
            drawLineSet(borderLines, `rgba(88,166,255,${alpha})`, 0.5, off);
        }
    }

    /** Draw state/province borders at all wrap positions (zoom >= ZOOM_SHOW_STATES) */
    function drawStateBorders() {
        if (!statesReady || view.zoom < ZOOM_SHOW_STATES) return;
        const alpha = clamp((view.zoom - ZOOM_SHOW_STATES) / 0.8, 0, 1) * 0.08;
        const offsets = getWrapOffsets();
        for (const off of offsets) {
            drawLineSet(stateLines, `rgba(88,166,255,${alpha})`, 0.3, off);
        }
    }

    /**
     * Draw city labels at all wrap positions.
     * Cities only appear at high zoom where borders provide context:
     *   zoom 3.5+  → mega-cities (>5M)
     *   zoom 4.5+  → large cities (>1M)
     *   zoom 5.5+  → medium cities (>300K)
     *   zoom 7.0+  → all cities
     */
    function drawCities() {
        if (!citiesReady || view.zoom < ZOOM_SHOW_CITIES_MAJOR) return;

        // Determine population cutoff based on zoom
        let minPop;
        if (view.zoom >= ZOOM_SHOW_CITIES_ALL)        minPop = 0;
        else if (view.zoom >= ZOOM_SHOW_CITIES_MED)    minPop = 300000;
        else if (view.zoom >= ZOOM_SHOW_CITIES_LARGE)  minPop = 1000000;
        else                                            minPop = 5000000;

        // Overall opacity fades in from the first threshold
        const alpha = clamp((view.zoom - ZOOM_SHOW_CITIES_MAJOR) / 0.5, 0, 1) * 0.7;

        const offsets = getWrapOffsets();
        ctx.textAlign = 'left';
        ctx.textBaseline = 'middle';

        for (const city of cityPoints) {
            if (city.p < minPop) continue;

            for (const off of offsets) {
                const s = worldToScreen(city.c[0] + off, city.c[1]);
                // Cull off-screen cities
                if (s.x < -50 || s.x > W + 50 || s.y < -20 || s.y > H + 20) continue;

                // Small dot
                ctx.fillStyle = `rgba(212,218,228,${alpha * 0.5})`;
                ctx.beginPath();
                ctx.arc(s.x, s.y, 1.5, 0, Math.PI * 2);
                ctx.fill();

                // City name label
                const fontSize = city.p > 5000000 ? 10 : city.p > 1000000 ? 9 : 8;
                ctx.font = `${fontSize}px 'SF Mono','Fira Code',Consolas,monospace`;
                ctx.fillStyle = `rgba(212,218,228,${alpha * 0.6})`;
                ctx.fillText(city.n, s.x + 5, s.y);
            }
        }
    }

    /**
     * Draw a single node at a specific screen position.
     * Shared by drawNode() for each wrap offset.
     */
    function drawNodeAt(sx, sy, c, r, gr, pulse, opacity) {
        // Outer glow (radial gradient)
        const grad = ctx.createRadialGradient(sx, sy, r, sx, sy, gr);
        grad.addColorStop(0, rgba(c, 0.5 * pulse * opacity));
        grad.addColorStop(0.5, rgba(c, 0.15 * pulse * opacity));
        grad.addColorStop(1, rgba(c, 0));
        ctx.fillStyle = grad;
        ctx.beginPath();
        ctx.arc(sx, sy, gr, 0, Math.PI * 2);
        ctx.fill();

        // Core dot
        ctx.fillStyle = rgba(c, 0.9 * opacity);
        ctx.beginPath();
        ctx.arc(sx, sy, r, 0, Math.PI * 2);
        ctx.fill();

        // Bright white centre highlight
        ctx.fillStyle = rgba({ r: 255, g: 255, b: 255 }, 0.6 * pulse * opacity);
        ctx.beginPath();
        ctx.arc(sx, sy, r * 0.4, 0, Math.PI * 2);
        ctx.fill();
    }

    /**
     * Draw a single node on the canvas at all visible wrap positions.
     * Handles fade-in, pulse glow, fade-out animations.
     */
    function drawNode(node, now, wrapOffsets) {
        if (now < node.spawnTime) return;

        const c = node.color;

        // ── Calculate overall opacity (handles fade-in and fade-out) ──
        let opacity = 1;
        const age = now - node.spawnTime;
        if (age < CFG.fadeInDuration) {
            opacity = age / CFG.fadeInDuration;
        }
        if (!node.alive && node.fadeOutStart) {
            const fadeAge = now - node.fadeOutStart;
            opacity = Math.max(0, 1 - fadeAge / CFG.fadeOutDuration);
            if (opacity <= 0) return;
        }

        // Pulsing factor (continuous sine wave)
        const pulse = 0.6 + 0.4 * Math.sin(node.phase + age * CFG.pulseSpeed);

        // Spawn "pop" scale effect (first 600ms)
        let scale = 1;
        if (age < 600) {
            const t = age / 600;
            scale = t < 0.6 ? (t / 0.6) * 1.4 : 1.4 - 0.4 * ((t - 0.6) / 0.4);
        }

        const r = CFG.nodeRadius * scale;
        const gr = CFG.glowRadius * scale * pulse;

        // Draw at each wrap offset
        for (const off of wrapOffsets) {
            const s = worldToScreen(node.lon + off, node.lat);
            // Skip if well off screen (with glow margin)
            if (s.x < -gr || s.x > W + gr || s.y < -gr || s.y > H + gr) continue;
            drawNodeAt(s.x, s.y, c, r, gr, pulse, opacity);
        }
    }

    /**
     * Draw subtle connection lines between nearby nodes.
     * Only draws between nodes that are close on screen (< 250px apart)
     * and skips fading-out nodes to avoid visual clutter.
     * Uses wrap offsets so connections work across the date line.
     */
    function drawConnectionLines(now, wrapOffsets) {
        ctx.lineWidth = 0.5;
        const aliveNodes = nodes.filter(n => n.alive);

        for (const off of wrapOffsets) {
            for (let i = 0; i < aliveNodes.length; i++) {
                const j = (i + 1) % aliveNodes.length;
                const a = worldToScreen(aliveNodes[i].lon + off, aliveNodes[i].lat);
                const b = worldToScreen(aliveNodes[j].lon + off, aliveNodes[j].lat);

                const dx = b.x - a.x;
                const dy = b.y - a.y;
                const dist = Math.sqrt(dx * dx + dy * dy);
                if (dist > 250 || dist < 20) continue;

                const alpha = 0.08 * (1 - dist / 250);
                ctx.strokeStyle = rgba(aliveNodes[i].color, alpha);
                ctx.beginPath();
                ctx.moveTo(a.x, a.y);
                ctx.lineTo(b.x, b.y);
                ctx.stroke();
            }
        }
    }

    // ═══════════════════════════════════════════════════════════
    // HUD — Peer count, block height, network badges
    // Updated every frame from current node state.
    // ═══════════════════════════════════════════════════════════

    function updateHUD() {
        // Count alive nodes by network type
        const netCounts = { ipv4: 0, ipv6: 0, onion: 0, i2p: 0, cjdns: 0 };
        let total = 0;
        for (const n of nodes) {
            if (!n.alive) continue;
            total++;
            if (netCounts.hasOwnProperty(n.net)) netCounts[n.net]++;
        }

        // Peer count
        document.getElementById('hud-peers').textContent = total;

        // Block height (from /api/info, not faked)
        const blockEl = document.getElementById('hud-block');
        if (lastBlockHeight !== null) {
            blockEl.textContent = lastBlockHeight.toLocaleString();
        } else {
            blockEl.textContent = '---';
        }

        // Network badges with live counts
        for (const net of Object.keys(NET_COLORS)) {
            // Map "onion" -> "tor" for the CSS class
            const cssClass = net === 'onion' ? 'tor' : net;
            const badge = document.querySelector(`.net-${cssClass}`);
            if (badge) {
                const label = NET_DISPLAY[net] || net.toUpperCase();
                badge.textContent = `${label} ${netCounts[net]}`;
            }
        }
    }

    /** Update the clock display in the topbar */
    function updateClock() {
        const now = new Date();
        const h = String(now.getHours()).padStart(2, '0');
        const m = String(now.getMinutes()).padStart(2, '0');
        const s = String(now.getSeconds()).padStart(2, '0');
        clockEl.textContent = `${h}:${m}:${s}`;
    }

    // ═══════════════════════════════════════════════════════════
    // TOOLTIP — Shows peer info on hover
    // ═══════════════════════════════════════════════════════════

    /** Find the nearest alive node within hit radius of screen coords.
     *  Checks all wrap offsets so hovering works on wrapped copies too. */
    function findNodeAtScreen(sx, sy) {
        const hitRadius = 12;
        const offsets = getWrapOffsets();
        for (let i = nodes.length - 1; i >= 0; i--) {
            if (!nodes[i].alive) continue;
            for (const off of offsets) {
                const s = worldToScreen(nodes[i].lon + off, nodes[i].lat);
                const dx = s.x - sx;
                const dy = s.y - sy;
                if (dx * dx + dy * dy < hitRadius * hitRadius) {
                    return nodes[i];
                }
            }
        }
        return null;
    }

    /** Display tooltip near the cursor with peer details */
    function showTooltip(node, mx, my) {
        // Location display: real city or "Private Network"
        const locationText = node.isPrivate
            ? '<span style="color:#4a5568;">Private Network</span>'
            : `${node.city}${node.country ? ', ' + node.country : ''}`;

        // Network label with colour
        const netLabel = NET_DISPLAY[node.net] || node.net.toUpperCase();

        tooltipEl.innerHTML =
            `<div class="tt-label">PEER ${node.peerId}</div>` +
            `<div class="tt-value">${locationText}</div>` +
            `<div style="color:${rgba(node.color, 0.9)};margin-top:2px;">${netLabel} &middot; ${node.direction}</div>` +
            (node.subver ? `<div style="color:#7a8494;font-size:10px;margin-top:2px;">${node.subver}</div>` : '') +
            `<div class="tt-label" style="margin-top:4px;">PING</div>` +
            `<div class="tt-value">${node.ping}ms</div>` +
            (node.conntime_fmt ? `<div class="tt-label" style="margin-top:2px;">UPTIME</div><div class="tt-value">${node.conntime_fmt}</div>` : '');

        tooltipEl.classList.remove('hidden');

        // Position tooltip near cursor, clamped to viewport
        const tx = mx + 16;
        const ty = my - 10;
        tooltipEl.style.left = Math.min(tx, W - 200) + 'px';
        tooltipEl.style.top = Math.max(ty, 48) + 'px';
    }

    function hideTooltip() {
        tooltipEl.classList.add('hidden');
        hoveredNode = null;
    }

    // ═══════════════════════════════════════════════════════════
    // MAIN RENDER LOOP
    // Runs at ~60fps via requestAnimationFrame.
    // ═══════════════════════════════════════════════════════════

    function frame() {
        const now = Date.now();

        // Smooth view interpolation (pan/zoom easing)
        view.x = lerp(view.x, targetView.x, CFG.panSmooth);
        view.y = lerp(view.y, targetView.y, CFG.panSmooth);
        view.zoom = lerp(view.zoom, targetView.zoom, CFG.panSmooth);

        // Clear canvas with ocean colour
        ctx.fillStyle = '#06080c';
        ctx.fillRect(0, 0, W, H);

        // Compute wrap offsets once per frame
        const wrapOffsets = getWrapOffsets();

        // Draw layers bottom-to-top:
        // 1. Grid lines (always visible)
        drawGrid();
        // 2. Land polygons (always visible)
        drawLandmasses();
        // 3. Lakes carved out on top of land (always visible)
        drawLakes();
        // 4. Country borders (always visible at all zoom levels)
        drawCountryBorders();
        // 5. State/province borders (zoom >= 3.0, fades in)
        drawStateBorders();
        // 6. City labels (zoom >= 3.5, high zoom only with borders as context)
        drawCities();
        // 7. Connection mesh lines between nearby peers
        drawConnectionLines(now, wrapOffsets);

        // 5. Peer nodes (alive + fading out) at all wrap positions
        for (const node of nodes) {
            drawNode(node, now, wrapOffsets);
        }

        // Update HUD overlays
        updateHUD();
        updateClock();

        requestAnimationFrame(frame);
    }

    // ═══════════════════════════════════════════════════════════
    // INTERACTION — Pan, zoom, touch, hover
    // ═══════════════════════════════════════════════════════════

    // ── Mouse pan ──
    canvas.addEventListener('mousedown', (e) => {
        dragging = true;
        dragStart.x = e.clientX;
        dragStart.y = e.clientY;
        dragViewStart.x = targetView.x;
        dragViewStart.y = targetView.y;
    });

    window.addEventListener('mousemove', (e) => {
        if (dragging) {
            // Pan the view by drag delta
            const dx = e.clientX - dragStart.x;
            const dy = e.clientY - dragStart.y;
            targetView.x = dragViewStart.x - dx;
            targetView.y = dragViewStart.y - dy;
            hideTooltip();
        } else {
            // Hover detection for tooltip
            const node = findNodeAtScreen(e.clientX, e.clientY);
            if (node) {
                showTooltip(node, e.clientX, e.clientY);
                hoveredNode = node;
                canvas.style.cursor = 'pointer';
            } else if (hoveredNode) {
                hideTooltip();
                canvas.style.cursor = 'grab';
            }
        }
    });

    window.addEventListener('mouseup', () => {
        dragging = false;
    });

    // ── Mouse wheel zoom (zooms toward cursor position) ──
    canvas.addEventListener('wheel', (e) => {
        e.preventDefault();
        const dir = e.deltaY < 0 ? 1 : -1;
        const factor = dir > 0 ? CFG.zoomStep : 1 / CFG.zoomStep;
        const newZoom = clamp(targetView.zoom * factor, CFG.minZoom, CFG.maxZoom);

        // Remember world point under cursor before zoom
        const mx = e.clientX;
        const my = e.clientY;
        const worldBefore = screenToWorld(mx, my);

        targetView.zoom = newZoom;

        // Adjust pan so the world point stays under the cursor after zoom
        const pBefore = project(worldBefore.lon, worldBefore.lat);
        const sxAfter = (pBefore.x - 0.5) * W * targetView.zoom + W / 2 - targetView.x * targetView.zoom;
        const syAfter = (pBefore.y - 0.5) * H * targetView.zoom + H / 2 - targetView.y * targetView.zoom;
        targetView.x += (sxAfter - mx) / targetView.zoom;
        targetView.y += (syAfter - my) / targetView.zoom;
    }, { passive: false });

    // ── Touch pan (single finger) ──
    let touchStart = null;
    canvas.addEventListener('touchstart', (e) => {
        if (e.touches.length === 1) {
            touchStart = { x: e.touches[0].clientX, y: e.touches[0].clientY };
            dragViewStart.x = targetView.x;
            dragViewStart.y = targetView.y;
        }
    }, { passive: true });

    canvas.addEventListener('touchmove', (e) => {
        if (touchStart && e.touches.length === 1) {
            const dx = e.touches[0].clientX - touchStart.x;
            const dy = e.touches[0].clientY - touchStart.y;
            targetView.x = dragViewStart.x - dx;
            targetView.y = dragViewStart.y - dy;
        }
    }, { passive: true });

    canvas.addEventListener('touchend', () => { touchStart = null; }, { passive: true });

    // ── Zoom buttons ──
    document.getElementById('zoom-in').addEventListener('click', () => {
        targetView.zoom = clamp(targetView.zoom * CFG.zoomStep, CFG.minZoom, CFG.maxZoom);
    });
    document.getElementById('zoom-out').addEventListener('click', () => {
        targetView.zoom = clamp(targetView.zoom / CFG.zoomStep, CFG.minZoom, CFG.maxZoom);
    });
    document.getElementById('zoom-reset').addEventListener('click', () => {
        targetView.x = 0;
        targetView.y = 0;
        targetView.zoom = 1;
    });

    // ═══════════════════════════════════════════════════════════
    // INIT — Start everything
    // ═══════════════════════════════════════════════════════════

    function init() {
        // Setup canvas size and DPI scaling
        resize();
        window.addEventListener('resize', resize);

        // Load all Natural Earth geometry layers (async, each renders once loaded)
        loadWorldGeometry();
        loadLakeGeometry();
        loadBorderGeometry();
        loadStateGeometry();
        loadCityData();

        // Fetch real peer data immediately, then poll every 10s
        fetchPeers();
        setInterval(fetchPeers, CFG.pollInterval);

        // Fetch node info (block height etc) immediately, then poll every 15s
        fetchInfo();
        setInterval(fetchInfo, CFG.infoPollInterval);

        // Start the render loop (grid + nodes render immediately,
        // landmasses + lakes appear once JSON assets finish loading)
        requestAnimationFrame(frame);
    }

    init();

})();
