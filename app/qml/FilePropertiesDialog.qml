// Stellar Download Manager
// Copyright (C) 2026 Ninka_
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program. If not, see <https://www.gnu.org/licenses/>.

import QtQuick
import QtQuick.Window
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts
import QtQuick.Dialogs
import QtCore

Window {
    id: root
    title: _isTorrent ? qsTr("Torrent Properties") : qsTr("File Properties")
    // Sizes are enforced via onItemChanged/onVisibleChanged so the window
    // always fits the content type, even when the user switches items.
    color: ColorPalette.cardBg
    flags: Qt.Dialog | Qt.WindowTitleHint | Qt.WindowCloseButtonHint | Qt.WindowSystemMenuHint

    Material.theme: ColorPalette.materialTheme
    Material.foreground: ColorPalette.textPrimary
    Material.background: ColorPalette.materialBg
    Material.accent: "#4488dd"

    property var item: null
    readonly property bool _isTorrent: item ? !!item.isTorrent : false
    readonly property var torrentFileModel:    _isTorrent ? App.torrentFileModel(item.id)    : null
    readonly property var torrentPeerModel:    _isTorrent ? App.torrentPeerModel(item.id)    : null
    readonly property var torrentTrackerModel: _isTorrent ? App.torrentTrackerModel(item.id) : null
    readonly property bool peerListActive: visible && _isTorrent && currentTab === 3
    readonly property bool peerMapActive: visible && _isTorrent && currentTab === 4
    readonly property bool peerUpdatesActive: visible && _isTorrent && (currentTab === 3 || currentTab === 4)
    // Tab 2 = Files. Gate the per-tick file_progress() walk in libtorrent on
    // whether the user can actually see the file list - when hidden, skip the
    // expensive piece-granularity scan entirely.
    readonly property bool fileUpdatesActive: visible && _isTorrent && currentTab === 2
    onFileUpdatesActiveChanged: {
        if (torrentFileModel) {
            torrentFileModel.setLiveUpdatesEnabled(fileUpdatesActive)
            if (fileUpdatesActive && item)
                App.refreshTorrentModelsNow(item.id)
        }
    }
    readonly property bool trackerTabActive:  visible && _isTorrent && currentTab === 5
    // Gate tracker model rebuilds (QUrl parse + geo-IP + status snapshot lookups
    // per tracker ? per torrent) on tracker tab visibility.
    onTrackerTabActiveChanged: {
        if (torrentTrackerModel) {
            torrentTrackerModel.setLiveUpdatesEnabled(trackerTabActive)
            if (trackerTabActive && item)
                App.refreshTorrentModelsNow(item.id)
        }
    }
    readonly property bool webSeedsTabActive: visible && _isTorrent && currentTab === 6
    readonly property var activePeerListModel: peerListActive ? torrentPeerModel : null
    readonly property var activePeerMapModel: peerMapActive ? torrentPeerModel : null
    readonly property var activeTrackerListModel: trackerTabActive ? torrentTrackerModel : null
    readonly property var activeTrackerMapModel: (peerMapActive && peerMapShowTrackers) ? torrentTrackerModel : null
    readonly property string _torrentStatusText: item ? safeStr(item.status) : ""
    readonly property bool _torrentIsMoving: _torrentStatusText === "Moving"

    function fileUrlFromPath(path) {
        var p = String(path || "").trim().replace(/\\/g, "/")
        if (p.length === 0 || p.indexOf("file://") === 0)
            return p
        return Qt.platform.os === "windows"
            ? ("file:///" + p)
            : (p.startsWith("/") ? ("file://" + p) : ("file:///" + p))
    }

    function pathFromFileUrl(url) {
        var p = String(url || "")
        if (Qt.platform.os === "windows")
            return p.replace(/^file:\/\/\//, "")
        return p.replace(/^file:\/\//, "")
    }

    // Peer column widths (resizable)
    property real peerColCountry:   82
    property real peerColPeer:     180
    property real peerColPort:      68
    property real peerColClient:   170
    property real peerColProgress:  72
    property real peerColDown:      90
    property real peerColUp:        90
    property real peerColDownloaded: 110
    property real peerColUploaded:   110
    property real peerColType:     170
    property real _resizingPeerCol: -1   // index of col being dragged
    property real _resizingPeerStart: 0
    property int  _peerSavedTopRow: 0
    property real _peerSavedRowOffset: 0
    property real _peerSavedContentY: 0
    property real _peerSavedContentX: 0
    property string _peerSavedTopKey: ""
    property var  _peerListViewRef: null

    property bool _peerViewportRestorePending: false
    property bool _peerViewportRestoreByAnchor: false
    property real _peerLiveReorderY: 0

    // Column order (persisted as JSON key arrays)
    property string peerColOrderJson: '["country","endpoint","port","client","progress","down","up","downloaded","uploaded","type"]'
    property string trkColOrderJson:  '["tracker","status","source","seeders","peers","nextAnnounce","message"]'
    property string fileColOrderJson: '["name","progress","size"]'

    // Peer column drag-reorder state
    property string _peerColDragFromKey: ""
    property string _peerColDragInsertBeforeKey: ""
    property bool   _peerColDragging: false

    // Tracker column drag-reorder state
    property string _trkColDragFromKey: ""
    property string _trkColDragInsertBeforeKey: ""
    property bool   _trkColDragging: false

    // File column drag-reorder state
    property string _fileColDragFromKey: ""
    property string _fileColDragInsertBeforeKey: ""
    property bool   _fileColDragging: false

    // Static column definitions (never change)
    readonly property var _peerColDefs: [
        { title: qsTr("Country"),  key: "country",  sortKey: "country" },
        { title: qsTr("Peer"),     key: "endpoint", sortKey: "endpoint" },
        { title: qsTr("Port"),     key: "port",     sortKey: "port" },
        { title: qsTr("Client"),   key: "client",   sortKey: "client" },
        { title: qsTr("Progress"), key: "progress", sortKey: "progress" },
        { title: qsTr("Down"),     key: "down",     sortKey: "down" },
        { title: qsTr("Up"),       key: "up",       sortKey: "up" },
        { title: qsTr("Downloaded"), key: "downloaded", sortKey: "downloaded" },
        { title: qsTr("Uploaded"), key: "uploaded", sortKey: "uploaded" },
        { title: qsTr("Flags"),    key: "type",     sortKey: "type" }
    ]
    readonly property var _trkColDefs: [
        { title: qsTr("Tracker"),       key: "tracker",       sortKey: "tracker" },
        { title: qsTr("Status"),        key: "status",        sortKey: "status" },
        { title: qsTr("Source"),        key: "source",        sortKey: "source" },
        { title: qsTr("Seeders"),       key: "seeders",       sortKey: "seeders" },
        { title: qsTr("Peers"),         key: "peers",         sortKey: "peers" },
        { title: qsTr("Next Announce"), key: "nextAnnounce",  sortKey: "nextAnnounce" },
        { title: qsTr("Message"),       key: "message",       sortKey: "message" }
    ]
    readonly property var _fileColDefs: [
        { title: qsTr("Name"),     key: "name" },
        { title: qsTr("Progress"), key: "progress" },
        { title: qsTr("Size"),     key: "size" }
    ]

    // Ordered column arrays (reactive on JSON order strings)
    property var _peerColsOrdered: {
        try {
            var keys = JSON.parse(peerColOrderJson)
            if (Array.isArray(keys) && keys.length === _peerColDefs.length)
                return keys.map(function(k){ return _peerColDefs.find(function(c){ return c.key===k }) }).filter(Boolean)
        } catch(e) {}
        return _peerColDefs.slice()
    }
    property var _trkColsOrdered: {
        try {
            var keys = JSON.parse(trkColOrderJson)
            if (Array.isArray(keys) && keys.length === _trkColDefs.length)
                return keys.map(function(k){ return _trkColDefs.find(function(c){ return c.key===k }) }).filter(Boolean)
        } catch(e) {}
        return _trkColDefs.slice()
    }
    property var _fileColsOrdered: {
        try {
            var keys = JSON.parse(fileColOrderJson)
            if (Array.isArray(keys) && keys.length === _fileColDefs.length)
                return keys.map(function(k){ return _fileColDefs.find(function(c){ return c.key===k }) }).filter(Boolean)
        } catch(e) {}
        return _fileColDefs.slice()
    }

    // X-offset maps (reactive on widths AND order)
    property var _peerColXMap: {
        var _w = peerColCountry + peerColPeer + peerColPort + peerColClient
               + peerColProgress + peerColDown + peerColUp + peerColDownloaded + peerColUploaded + peerColType
        var _o = peerColOrderJson   // reactive dep on order
        var map = {}, x = 0
        for (var i = 0; i < _peerColsOrdered.length; i++) {
            var col = _peerColsOrdered[i]
            map[col.key] = x
            x += _peerColW(col.key)
        }
        return map
    }
    property var _trkColXMap: {
        var _w = trkColTracker + trkColStatus + trkColSource + trkColSeeders + trkColPeers + trkColNextAnnounce + trkColMessage
        var _o = trkColOrderJson
        var map = {}, x = 0
        for (var i = 0; i < _trkColsOrdered.length; i++) {
            var col = _trkColsOrdered[i]
            map[col.key] = x
            x += _trkColW(col.key)
        }
        return map
    }
    property var _fileColXMap: {
        var _w = fileColName + fileColProgress + fileColSize
        var _o = fileColOrderJson
        var map = {}, x = 0
        for (var i = 0; i < _fileColsOrdered.length; i++) {
            var col = _fileColsOrdered[i]
            map[col.key] = x
            x += _fileColW(col.key)
        }
        return map
    }

    // File list column widths
    property real fileColName:     520
    property real fileColProgress: 100
    property real fileColSize:      90

    // Tracker list column widths
    property real trkColTracker:       400
    property real trkColStatus:        110
    property real trkColSource:         80
    property real trkColSeeders:        70
    property real trkColPeers:          70
    property real trkColNextAnnounce:  110
    property real trkColMessage:       260

    // Tracker sort
    property string trkSortKey: ""
    property bool   trkSortAscending: true

    // Peer sort
    property string peerSortKey: "country"
    property bool   peerSortAscending: true

    property int    currentTab: 0
    readonly property var swarmPeriodOptions: [
        { label: "1 min", secs: 60 },
        { label: "5 min", secs: 300 },
        { label: "15 min", secs: 900 },
        { label: "1 hour", secs: 3600 },
        { label: "6 hours", secs: 21600 },
        { label: "24 hours", secs: 86400 }
    ]
    property int swarmPeriodIndex: 3
    readonly property int swarmPeriodSeconds: swarmPeriodOptions[Math.max(0, Math.min(swarmPeriodIndex, swarmPeriodOptions.length - 1))].secs
    property string swarmStatsStoreJson: "{}"
    property var swarmStatsStore: ({})
    property var swarmSamples: []
    property var swarmClientBreakdown: ({})
    property var swarmCountryBreakdown: ({})
    property var swarmClientRows: []
    property var swarmCountryRows: []
    property var swarmClientLegendRows: []
    property var swarmCountryLegendRows: []
    property var swarmTimeLabels: []
    property var swarmCanvasRef: null
    property var swarmLiveCanvasRef: null
    property var swarmClientPieRef: null
    property var swarmCountryPieRef: null
    property bool swarmLiveHoverActive: false
    property real swarmLiveHoverX: 0
    property var swarmHoverSample: null
    property real _swarmNowMs: 0
    property var _swarmDecimated: []
    property int    editPerTorrentDownLimitKBps: 0
    property int    editPerTorrentUpLimitKBps: 0
    property bool   peerMapHoverVisible: false
    property real   peerMapZoom: 1.0
    property real   peerMapPanX: 0
    property real   peerMapPanY: 0
    property real   peerMapLonOffset: 0.5
    property real   peerMapLatOffset: 4.5
    property bool   peerMapYouHoverVisible: false
    property bool   peerMapShowTrackers: App.settings.swarmMapShowTrackers
    property bool   peerMapShowInactive: App.settings.swarmMapShowInactive
    property real   peerMapHoverProgress: 0.0
    readonly property real peerMapSvgMinX: 1.0
    readonly property real peerMapSvgMaxX: 799.0
    readonly property real peerMapSvgMinY: 1.0
    readonly property real peerMapSvgMaxY: 385.91
    property real   peerMapHoverX: 0
    property real   peerMapHoverY: 0
    property string peerMapHoverEndpoint: ""
    property int    peerMapHoverPort: 0
    property string peerMapHoverClient: ""
    property string peerMapHoverCountryCode: ""
    property string peerMapHoverRegionCode: ""
    property string peerMapHoverRegionName: ""
    property string peerMapHoverCityName: ""
    property int    peerMapHoverRtt: 0
    property int    peerMapHoverDownSpeed: 0
    property int    peerMapHoverUpSpeed: 0
    property bool   peerMapHoverIsSeed: false
    property string peerMapHoverSource: ""
    property string peerMapHoverFlags: ""

    // Tracker map hover tooltip state
    property bool   peerMapTrackerHoverVisible: false
    property real   peerMapTrackerHoverX: 0
    property real   peerMapTrackerHoverY: 0
    property string peerMapTrackerHoverHost: ""
    property string peerMapTrackerHoverCountry: ""
    property string peerMapTrackerHoverStatus: ""
    property int    peerMapTrackerHoverTier: -1
    property int    peerMapTrackerHoverCount: 0
    property string peerMapTrackerHoverUrl: ""

    // Tracker add panel visibility
    property bool showTrackerAdd:  false
    property bool showWebSeedAdd:  false

    // Speed history state (torrent Speed tab)
    readonly property var speedSpanOptions: [
        { label: "30 sec", value: 30 },
        { label: "1 min", value: 60 },
        { label: "3 min", value: 180 },
        { label: "5 min", value: 300 },
        { label: "10 min", value: 600 },
        { label: "1 hour", value: 3600 },
        { label: "3 hours", value: 10800 },
        { label: "6 hours", value: 21600 },
        { label: "1 day", value: 86400 }
    ]
    property int speedSpanIndex: 5
    readonly property int speedSpanSeconds: speedSpanOptions[Math.max(0, Math.min(speedSpanIndex, speedSpanOptions.length - 1))].value
    property var speedSamples: []
    property bool speedHoverActive: false
    property real speedHoverX: 0
    property int speedSampleIntervalMs: 2000
    property var speedGraphCanvasRef: null

    Settings {
        category: "FilePropertiesDialog"
        property alias peerColCountry: root.peerColCountry
        property alias peerColPeer: root.peerColPeer
        property alias peerColPort: root.peerColPort
        property alias peerColClient: root.peerColClient
        property alias peerColProgress: root.peerColProgress
        property alias peerColDown: root.peerColDown
        property alias peerColUp: root.peerColUp
        property alias peerColDownloaded: root.peerColDownloaded
        property alias peerColUploaded: root.peerColUploaded
        property alias peerColType: root.peerColType
        property alias fileColName: root.fileColName
        property alias fileColProgress: root.fileColProgress
        property alias fileColSize: root.fileColSize
        property alias trkColTracker: root.trkColTracker
        property alias trkColStatus: root.trkColStatus
        property alias trkColSource: root.trkColSource
        property alias trkColSeeders: root.trkColSeeders
        property alias trkColPeers: root.trkColPeers
        property alias trkColNextAnnounce: root.trkColNextAnnounce
        property alias trkColMessage: root.trkColMessage
        property alias peerColOrderJson: root.peerColOrderJson
        property alias trkColOrderJson:  root.trkColOrderJson
        property alias fileColOrderJson: root.fileColOrderJson
        property alias swarmStatsStoreJson: root.swarmStatsStoreJson
    }

    // ?? Window sizing ????????????????????????????????????????????????????????
    function _applySize() {
        var torrent = !!(root.item && root.item.isTorrent)
        minimumWidth  = 0
        minimumHeight = 0
        if (torrent) {
            minimumWidth  = 800
            minimumHeight = 500
            width  = 800
            height = 500
        } else {
            minimumWidth  = 470
            minimumHeight = 420
            width  = 470
            height = 420
        }
    }

    function _centerOnOwner() {
        var owner = root.transientParent
        if (owner) {
            x = owner.x + Math.round((owner.width - width) / 2)
            y = owner.y + Math.round((owner.height - height) / 2)
            return
        }
        x = Math.round((Screen.width - width) / 2)
        y = Math.round((Screen.height - height) / 2)
    }

    // Works around a Qt layout invalidation bug when the Loader swaps between
    // regularLayout and torrentLayout.  The new component is created and sized
    // within the same event-loop tick as the old one is destroyed, but Qt
    // coalesces the relayout into that same frame - before the new component's
    // implicit sizes have fully propagated through the ColumnLayout chain.
    // Result: the footer buttons overlap the content or disappear entirely.
    // A zero-delay timer fires on the *next* tick and nudges the window width
    // by +1/-1, which is the same thing a manual drag does: it forces a clean,
    // full layout pass with the new content already in the tree.
    Timer {
        id: layoutNudgeTimer
        interval: 0
        repeat: false
        onTriggered: {
            root.width = root.width + 1
            root.width = root.width - 1
        }
    }

    onItemChanged:  {
        currentTab = 0
        showTrackerAdd = false
        showWebSeedAdd = false
        speedSamples = []
        _speedAxisTop = 1
        speedHoverActive = false
        editPerTorrentDownLimitKBps = (root.item && root.item.isTorrent) ? (root.item.perTorrentDownLimitKBps | 0) : 0
        editPerTorrentUpLimitKBps = (root.item && root.item.isTorrent) ? (root.item.perTorrentUpLimitKBps | 0) : 0
        if (torrentPeerModel) torrentPeerModel.sortBy(peerSortKey, peerSortAscending)
        if (root.item && root.item.isTorrent)
            refreshSpeedHistory()
        root.loadSwarmStatsForCurrent()
    }
    onVisibleChanged: {
        if (visible) {
            raise()
            requestActivate()
            Qt.callLater(function() {
                root._applySize()
                root._centerOnOwner()
            })
            root.loadSwarmStatsForCurrent()
        } else {
            root.persistSwarmStatsForCurrent()
        }
    }
    onPeerUpdatesActiveChanged: {
        if (torrentPeerModel) {
            torrentPeerModel.setLiveUpdatesEnabled(peerUpdatesActive)
            root.syncPeerStructuralUpdates()
            if (peerUpdatesActive && item)
                App.refreshTorrentModelsNow(item.id)
        }
    }
    onCurrentTabChanged: {
        root.syncPeerStructuralUpdates()
        if (root.currentTab === 1)
            root.refreshSpeedHistory()
        if (root.currentTab === 5 && root.swarmCanvasRef)
            root.swarmCanvasRef.requestPaint()
        if (root.currentTab === 5 && root.swarmLiveCanvasRef) root.swarmLiveCanvasRef.requestPaint()
        if (root.currentTab === 5 && root.swarmClientPieRef) root.swarmClientPieRef.requestPaint()
        if (root.currentTab === 5 && root.swarmCountryPieRef) root.swarmCountryPieRef.requestPaint()
    }
    onSwarmPeriodIndexChanged: {
        root.swarmClientBreakdown = root.mergeBreakdownFromSamples("client")
        root.swarmCountryBreakdown = root.mergeBreakdownFromSamples("country")
        root.swarmClientRows = root.breakdownRows(root.swarmClientBreakdown, "client")
        root.swarmCountryRows = root.breakdownRows(root.swarmCountryBreakdown, "country")
        root.swarmClientLegendRows = root.topBreakdownRows(root.swarmClientRows, 8)
        root.swarmCountryLegendRows = root.topBreakdownRows(root.swarmCountryRows, 8)
        Qt.callLater(root._rebuildSwarmCache)
        if (root.currentTab === 5 && root.swarmCanvasRef)
            root.swarmCanvasRef.requestPaint()
        if (root.currentTab === 5 && root.swarmLiveCanvasRef) root.swarmLiveCanvasRef.requestPaint()
        if (root.currentTab === 5 && root.swarmClientPieRef) root.swarmClientPieRef.requestPaint()
        if (root.currentTab === 5 && root.swarmCountryPieRef) root.swarmCountryPieRef.requestPaint()
    }
    // onSpeedSpanIndexChanged ? onSpeedSpanSecondsChanged ? _rebuildDecimatedCache ? requestPaint()

    Timer {
        id: speedHistoryTimer
        interval: root.speedSampleIntervalMs
        repeat: true
        running: root.visible && root._isTorrent && root.currentTab === 1
        onTriggered: root.refreshSpeedHistory()
    }

    Connections {
        target: root.item
        function onTorrentLimitsChanged() {
            if (!root.item || !root.item.isTorrent)
                return
            // Sync cached edit values only when the speed limit dialog has no
            // unsaved edits - otherwise the user's in-flight changes win.
            if (!speedLimitDialog.dirty) {
                root.editPerTorrentDownLimitKBps = root.item.perTorrentDownLimitKBps | 0
                root.editPerTorrentUpLimitKBps   = root.item.perTorrentUpLimitKBps   | 0
            }
        }
        // No direct repaint on speed/stats signals - the 2 s speedHistoryTimer
        // already calls refreshSpeedHistory() which repaints after rebuilding
        // the decimated cache.  Bypassing that and painting with stale data
        // caused the graph to flicker on every libtorrent alert tick.
    }

    // ?? Helpers ??????????????????????????????????????????????????????????????
    function safeStr(v) { return (v === undefined || v === null) ? "" : String(v) }
    function torrentStatusLabel() {
        switch (_torrentStatusText) {
        case "Paused": return qsTr("Stopped")
        case "Checking": return qsTr("Checking files")
        case "Downloading": return qsTr("Downloading")
        case "Moving": return qsTr("Moving")
        case "Seeding": return qsTr("Seeding")
        case "Queued": return qsTr("Queued")
        case "Completed": return qsTr("Complete")
        case "Error": return qsTr("Problem")
        default: return _torrentStatusText.length > 0 ? _torrentStatusText : "--"
        }
    }
    function torrentStatusAccent() {
        switch (_torrentStatusText) {
        case "Downloading": return "#62a8ff"
        case "Moving": return "#e0a85a"
        case "Seeding": return "#67bb7a"
        case "Paused": return "#b7b7b7"
        case "Checking": return "#d2b26f"
        case "Queued": return "#8fb4d9"
        case "Error": return "#d97b7b"
        default: return ColorPalette.textPrimary
        }
    }
    function countryFlagSource(code) {
        var cc = safeStr(code).trim().toLowerCase()
        if (!cc || cc.length !== 2)
            return ""
        // Flags are registered as qt_add_resources with PREFIX "/" and path
        // "app/qml/flags/*.svg", so the absolute QRC path is used here.
        return "qrc:/app/qml/flags/" + cc + ".svg"
    }
    function torrentClientIconSource(clientName) {
        var name = baseClientName(clientName).toLowerCase()
        if (!name)
            return ""
        if (name.indexOf("stellar") !== -1)
            return "icons/milky-way.png"
        if (name.indexOf("qbittorrent") !== -1 || name.indexOf("qbittorrent enhanced") !== -1)
            return "icons/torrent-client-logos/qbittorrent.png"
        if (name.indexOf("transmission") !== -1)
            return "icons/torrent-client-logos/transmission.png"
        if (name.indexOf("deluge") !== -1)
            return "icons/torrent-client-logos/deluge.png"
        if (name.indexOf("ktorrent") !== -1)
            return "icons/torrent-client-logos/ktorrent.png"
        if (name.indexOf("tixati") !== -1)
            return "icons/torrent-client-logos/tixati-icon.png"
        if (name.indexOf("picotorrent") !== -1)
            return "icons/torrent-client-logos/picotorrent.png"
        if (name.indexOf("biglybt") !== -1 || name.indexOf("vuze") !== -1 || name.indexOf("azureus") !== -1)
            return name.indexOf("biglybt") !== -1
                ? "icons/torrent-client-logos/biglybt.png"
                : "icons/torrent-client-logos/vuze.png"
        if (name.indexOf("utorrent") !== -1 || name.indexOf("\u00b5torrent") !== -1 || name.indexOf("\u03bctorrent") !== -1 || name.indexOf("microtorrent") !== -1)
            return "icons/torrent-client-logos/utorrent.png"
        if (name.indexOf("bitcomet") !== -1)
            return "icons/torrent-client-logos/bitcomet.png"
        if (name.indexOf("bittorrent") !== -1)
            return "icons/torrent-client-logos/bittorrent.png"
        if (name.indexOf("bitlord") !== -1)
            return "icons/torrent-client-logos/BitLord_logo_2022.png"
        if (name.indexOf("frostwire") !== -1)
            return "icons/torrent-client-logos/frostwire.png"
        if (name.indexOf("folx") !== -1)
            return "icons/torrent-client-logos/folx.png"
        if (name.indexOf("libretorrent") !== -1)
            return "icons/torrent-client-logos/libretorrent.png"
        if (name.indexOf("libtorrent") !== -1 || name.indexOf("rasterbar") !== -1)
            return "icons/torrent-client-logos/Libtorrent-rasterbar-logo.png"
        if (name.indexOf("elementum") !== -1)
            return "icons/torrent-client-logos/elementum.png"
        if (name.indexOf("fdm") !== -1 || name.indexOf("free download manager") !== -1)
            return "icons/torrent-client-logos/FDM.png"
        if (name.indexOf("xunlei") !== -1 || name.indexOf("thunder") !== -1)
            return "icons/torrent-client-logos/XunLei.png"
        if (name.indexOf("mediaget") !== -1)
            return "icons/torrent-client-logos/MediaGet2.png"
        return ""
    }

    function fileType(name) {
        var n = safeStr(name).toLowerCase()
        if (!n) return "Unknown"
        if (/\.(mp4|mkv|avi|mov|wmv|flv|webm|m4v|3gp|mpeg|mpg|ogv|rmvb|rm)$/.test(n)) return "Video File"
        if (/\.(mp3|flac|wav|aac|ogg|m4a|wma|aif|ra|opus)$/.test(n))                  return "Audio File"
        if (/\.(zip|rar|7z|tar|gz|bz2|xz|zst|r\d+)$/.test(n))                         return "Archive"
        if (/\.(exe|msi|msu|deb|rpm|apk)$/.test(n))                                    return "Installer"
        if (/\.(pdf|doc|docx|xls|xlsx|ppt|pptx)$/.test(n))                             return "Document"
        if (/\.(jpg|jpeg|png|gif|bmp|webp|tiff|svg|ico)$/.test(n))                     return "Image"
        if (/\.(torrent)$/.test(n))                                                     return "Torrent"
        return "File"
    }

    function formatBytes(b) {
        var v = Number(b)
        if (!isFinite(v) || v <= 0) return "--"
        if (v < 1024)        return v + " B"
        if (v < 1048576)     return (v / 1024).toFixed(2)       + " KB (" + v + " Bytes)"
        if (v < 1073741824)  return (v / 1048576).toFixed(2)    + " MB (" + v + " Bytes)"
        return (v / 1073741824).toFixed(2) + " GB (" + v + " Bytes)"
    }

    function compactBytes(b) {
        var v = Number(b)
        if (!isFinite(v) || v <= 0) return "0 B"
        var kb = v / 1024.0, mb = kb / 1024.0, gb = mb / 1024.0
        if (gb >= 0.95) return gb.toFixed(2) + " GB"
        if (mb >= 0.95) return mb.toFixed(1) + " MB"
        if (kb >= 0.95) return kb.toFixed(1) + " KB"
        return Math.round(v) + " B"
    }

    function compactSpeed(bps) {
        var v = Number(bps)
        if (!isFinite(v) || v <= 0) return "0 B/s"
        return compactBytes(v) + "/s"
    }
    function speedAxisLabel(bps) {
        var v = Number(bps)
        if (!isFinite(v) || v <= 0) return "0 B/s"
        return compactSpeed(v)
    }
    function baseClientName(clientName) {
        var name = safeStr(clientName).trim()
        if (!name)
            return "Unknown"
        var lower = name.toLowerCase()
        if (lower.indexOf("deluge") !== -1) return "Deluge"
        if (lower.indexOf("qbittorrent") !== -1) return "qBittorrent"
        if (lower.indexOf("transmission") !== -1) return "Transmission"
        if (lower.indexOf("utorrent") !== -1 || lower.indexOf("\u00b5torrent") !== -1 || lower.indexOf("\u03bctorrent") !== -1 || lower.indexOf("microtorrent") !== -1) return "uTorrent"
        if (lower.indexOf("libtorrent") !== -1 || lower.indexOf("rasterbar") !== -1) return "libtorrent"
        name = name.replace(/\s*[/ ]\d+(?:\.\d+)*\s*$/g, "")
        name = name.replace(/\s+v\d+(?:\.\d+)*\s*$/gi, "")
        name = name.trim()
        return name.length > 0 ? name : "Unknown"
    }
    function formatClockTime(ms) {
        var d = new Date(Number(ms) || 0)
        if (isNaN(d.getTime()))
            return "--:--:--"
        return d.toLocaleTimeString(Qt.locale(), "h:mm:ss AP")
    }
    function formatAgoNatural(seconds) {
        var s = Math.max(0, seconds | 0)
        var h = Math.floor(s / 3600)
        var m = Math.floor((s % 3600) / 60)
        var sec = s % 60
        if (h > 0)
            return h + " hr " + m + " min ago"
        if (m > 0)
            return m + " min " + sec + " sec ago"
        return sec + " sec ago"
    }
    // Stable time anchor for the graph's right edge.  Set once per data refresh
    // and reused by every paint and hover-position calculation so the x-axis
    // doesn't shift between repaints (which caused the jitter).
    property real _speedNowMs: 0

    function refreshSpeedHistory() {
        if (!_isTorrent || !item) {
            speedSamples = []
            _speedNowMs = Date.now()
            return
        }
        _speedNowMs = Date.now()
        speedSamples = App.torrentSpeedHistory(item.id, speedSpanSeconds, 1000)
        // requestPaint() is called by _rebuildDecimatedCache (via Qt.callLater)
        // after the smoothed cache and stable axis ceiling are both ready.
    }
    // Reduce pts to at most maxPts by averaging each bucket.
    // Averaging preserves the real throughput shape - peak-only decimation
    // exaggerates spikes and produces a misleadingly jagged curve on long spans.
    // Time-aligned bucket decimation.  Bucket boundaries are snapped to multiples
    // of bucketMs from the Unix epoch, so they are identical across every refresh
    // call.  Only the rightmost (current) bucket changes as new samples arrive;
    // all completed buckets are frozen - the line stays still and scrolls left.
    function decimateSamples(pts, maxPts) {
        if (pts.length === 0) return pts
        var spanMs   = root.speedSpanSeconds * 1000
        var bucketMs = spanMs / maxPts
        // Snap right edge of grid to the nearest completed bucket boundary at or
        // before nowMs.  This keeps all bucket edges fixed to absolute time so
        // completed buckets never shift when new samples arrive.
        var nowMs      = root._speedNowMs || Date.now()
        var gridOrigin = Math.floor(nowMs / bucketMs) * bucketMs
        // gridOrigin is the last bucket boundary <= nowMs; the grid covers
        // [gridOrigin - spanMs, gridOrigin).  Samples between gridOrigin and
        // nowMs land in the last (open) bucket which shifts - that's intentional,
        // only the live bucket changes.
        var startMs    = gridOrigin - spanMs
        var out = []
        // maxPts fixed buckets + 1 live (partial) bucket covering [gridOrigin, nowMs)
        for (var bi = 0; bi <= maxPts; ++bi) {
            var bucketStart = startMs + bi * bucketMs
            var bucketEnd   = (bi < maxPts) ? (bucketStart + bucketMs) : (nowMs + 1)
            var sumDown = 0, sumUp = 0, n = 0
            for (var pi = 0; pi < pts.length; ++pi) {
                var t = pts[pi].t
                if (t >= bucketStart && t < bucketEnd) {
                    sumDown += Number(pts[pi].down) || 0
                    sumUp   += Number(pts[pi].up)   || 0
                    n++
                }
            }
            if (n > 0)
                out.push({ t: bucketStart + (bucketEnd - bucketStart) * 0.5, down: sumDown / n, up: sumUp / n })
        }
        return out.length > 0 ? out : pts
    }

    // Cached decimated sample array and stable Y-axis ceiling - rebuilt only
    // when the raw data or the selected time span changes, NOT on every mouse
    // move or canvas repaint.  Keeping axisTop stable prevents the Y-axis from
    // jumping every tick; the canvas and hover tooltip both read from these.
    property var  _speedDecimated: []
    property real _speedAxisTop: 1        // stable Y ceiling, pixels don't shift on hover
    function _rebuildDecimatedCache() {
        var rows = speedVisibleSamples()
        var span = speedSpanSeconds

        // Step 1 - decimate to a target point count that scales inversely with
        // the span.  Shorter spans keep more detail; longer spans merge more
        // raw samples per bucket so individual spikes are averaged away.
        // At 1 hour with ~1000 raw points each bucket covers ~13 raw samples
        // (?26 s of data), which collapses narrow spikes into their true average.
        var canvasW   = speedGraphCanvasRef ? speedGraphCanvasRef.width : 600
        var plotW     = Math.max(60, canvasW - 62)
        // Base density: 1 pt per 3 px, then halve for each span tier above 10 min.
        var basePts   = Math.ceil(plotW / 3)
        var spanScale = span < 600 ? 1.0 : span < 1800 ? 0.6 : span < 3600 ? 0.4 : span < 10800 ? 0.25 : 0.15
        var targetPts = Math.max(40, Math.ceil(basePts * spanScale))
        rows = decimateSamples(rows, targetPts)

        _speedDecimated = rows

        // Compute and cache the stable Y-axis ceiling from the smoothed data.
        // Using the previous _speedAxisTop as a floor prevents the axis from
        // shrinking on every minor dip - it only grows immediately, then
        // gently decays toward the true max so the scale stays readable.
        var maxV = 1
        for (var si = 0; si < rows.length; ++si)
            maxV = Math.max(maxV, Number(rows[si].down) || 0, Number(rows[si].up) || 0)
        // Fixed human-friendly speed ladder (bytes/s).  Pick the smallest step
        // that fits maxV with at least one grid interval of headroom.
        var speedSteps = [
            102400,   204800,   512000,             // 100, 200, 500 KB/s
            1048576,  2097152,  5242880,             // 1, 2, 5 MB/s
            10485760, 20971520, 52428800,            // 10, 20, 50 MB/s
            104857600, 209715200, 524288000,         // 100, 200, 500 MB/s
            1073741824                               // 1 GB/s
        ]
        var newTop = speedSteps[speedSteps.length - 1]
        for (var li = 0; li < speedSteps.length; ++li) {
            if (speedSteps[li] >= maxV) { newTop = speedSteps[li]; break }
        }
        // Allow axis to grow immediately to the next step, but decay slowly so
        // a brief spike doesn't permanently lock the scale at a high tier.
        // toward the true ceiling per refresh so axis doesn't thrash up/down.
        var prev = _speedAxisTop
        if (newTop >= prev) {
            _speedAxisTop = newTop
        } else {
            // Decay: move 20% of the gap per sample refresh (~2 s interval)
            _speedAxisTop = Math.max(newTop, prev - (prev - newTop) * 0.20)
        }

        // Repaint now that both the smoothed data and stable axis ceiling are ready.
        if (currentTab === 1 && speedGraphCanvasRef)
            speedGraphCanvasRef.requestPaint()
    }
    onSpeedSamplesChanged:     Qt.callLater(_rebuildDecimatedCache)
    onSpeedSpanSecondsChanged: Qt.callLater(_rebuildDecimatedCache)

    function speedVisibleSamples() {
        var now = Date.now()
        var start = now - (speedSpanSeconds * 1000)
        var rows = []
        for (var i = 0; i < speedSamples.length; ++i) {
            var s = speedSamples[i]
            if (s.t >= start)
                rows.push(s)
        }
        if (rows.length === 0) {
            var down = item ? Math.max(0, Number(item.speed) || 0) : 0
            var up = item ? Math.max(0, Number(item.torrentUploadSpeed) || 0) : 0
            rows.push({ t: now, down: down, up: up })
        }
        return rows
    }
    function speedStats(samples, key) {
        var k = key || "down"
        var current = 0
        var maxv = 0
        var sum = 0
        for (var i = 0; i < samples.length; ++i) {
            var v = Math.max(0, Number(samples[i][k]) || 0)
            if (v > maxv) maxv = v
            sum += v
            if (i === samples.length - 1)
                current = v
        }
        var avg = samples.length > 0 ? (sum / samples.length) : 0
        return { current: current, avg: avg, max: maxv }
    }
    function peerMapX(longitude, width) {
        var lon = Number(longitude) + root.peerMapLonOffset
        if (!isFinite(lon))
            lon = 0
        var normalized = (lon + 180.0) / 360.0
        var drawableWidth = peerMapSvgMaxX - peerMapSvgMinX
        return ((peerMapSvgMinX + normalized * drawableWidth) / 800.0) * width
    }
    function peerMapY(latitude, width, height) {
        var lat = Number(latitude) + root.peerMapLatOffset
        if (!isFinite(lat))
            lat = 0
        // ?? world-map.svg (Natural Earth 110m) uses equirectangular projection spanning 90. ??
        // x = (lon+180)/360*width, y = (90-lat)/180*height
        lat = Math.max(-90, Math.min(90, lat))
        var normalized = (90 - lat) / 180
        var drawableHeight = peerMapSvgMaxY - peerMapSvgMinY
        return ((peerMapSvgMinY + normalized * drawableHeight) / 387.0) * height
    }
    function countryFullName(cc) {
        var names = {
            "AF":"Afghanistan","AX":"?land Islands","AL":"Albania","DZ":"Algeria","AS":"American Samoa",
            "AD":"Andorra","AO":"Angola","AI":"Anguilla","AQ":"Antarctica","AG":"Antigua and Barbuda",
            "AR":"Argentina","AM":"Armenia","AW":"Aruba","AU":"Australia","AT":"Austria",
            "AZ":"Azerbaijan","BS":"Bahamas","BH":"Bahrain","BD":"Bangladesh","BB":"Barbados",
            "BY":"Belarus","BE":"Belgium","BZ":"Belize","BJ":"Benin","BM":"Bermuda",
            "BT":"Bhutan","BO":"Bolivia","BQ":"Bonaire","BA":"Bosnia and Herzegovina","BW":"Botswana",
            "BV":"Bouvet Island","BR":"Brazil","IO":"British Indian Ocean Territory","BN":"Brunei",
            "BG":"Bulgaria","BF":"Burkina Faso","BI":"Burundi","CV":"Cabo Verde","KH":"Cambodia",
            "CM":"Cameroon","CA":"Canada","KY":"Cayman Islands","CF":"Central African Republic",
            "TD":"Chad","CL":"Chile","CN":"China","CX":"Christmas Island","CC":"Cocos Islands",
            "CO":"Colombia","KM":"Comoros","CG":"Congo","CD":"DR Congo","CK":"Cook Islands",
            "CR":"Costa Rica","CI":"C?te d'Ivoire","HR":"Croatia","CU":"Cuba","CW":"Cura?ao",
            "CY":"Cyprus","CZ":"Czech Republic","DK":"Denmark","DJ":"Djibouti","DM":"Dominica",
            "DO":"Dominican Republic","EC":"Ecuador","EG":"Egypt","SV":"El Salvador","GQ":"Equatorial Guinea",
            "ER":"Eritrea","EE":"Estonia","SZ":"Eswatini","ET":"Ethiopia","FK":"Falkland Islands",
            "FO":"Faroe Islands","FJ":"Fiji","FI":"Finland","FR":"France","GF":"French Guiana",
            "PF":"French Polynesia","TF":"French Southern Territories","GA":"Gabon","GM":"Gambia",
            "GE":"Georgia","DE":"Germany","GH":"Ghana","GI":"Gibraltar","GR":"Greece",
            "GL":"Greenland","GD":"Grenada","GP":"Guadeloupe","GU":"Guam","GT":"Guatemala",
            "GG":"Guernsey","GN":"Guinea","GW":"Guinea-Bissau","GY":"Guyana","HT":"Haiti",
            "HM":"Heard Island","VA":"Holy See","HN":"Honduras","HK":"Hong Kong","HU":"Hungary",
            "IS":"Iceland","IN":"India","ID":"Indonesia","IR":"Iran","IQ":"Iraq",
            "IE":"Ireland","IM":"Isle of Man","IL":"Israel","IT":"Italy","JM":"Jamaica",
            "JP":"Japan","JE":"Jersey","JO":"Jordan","KZ":"Kazakhstan","KE":"Kenya",
            "KI":"Kiribati","KP":"North Korea","KR":"South Korea","KW":"Kuwait","KG":"Kyrgyzstan",
            "LA":"Laos","LV":"Latvia","LB":"Lebanon","LS":"Lesotho","LR":"Liberia",
            "LY":"Libya","LI":"Liechtenstein","LT":"Lithuania","LU":"Luxembourg","MO":"Macao",
            "MG":"Madagascar","MW":"Malawi","MY":"Malaysia","MV":"Maldives","ML":"Mali",
            "MT":"Malta","MH":"Marshall Islands","MQ":"Martinique","MR":"Mauritania","MU":"Mauritius",
            "YT":"Mayotte","MX":"Mexico","FM":"Micronesia","MD":"Moldova","MC":"Monaco",
            "MN":"Mongolia","ME":"Montenegro","MS":"Montserrat","MA":"Morocco","MZ":"Mozambique",
            "MM":"Myanmar","NA":"Namibia","NR":"Nauru","NP":"Nepal","NL":"Netherlands",
            "NC":"New Caledonia","NZ":"New Zealand","NI":"Nicaragua","NE":"Niger","NG":"Nigeria",
            "NU":"Niue","NF":"Norfolk Island","MK":"North Macedonia","MP":"Northern Mariana Islands",
            "NO":"Norway","OM":"Oman","PK":"Pakistan","PW":"Palau","PS":"Palestine",
            "PA":"Panama","PG":"Papua New Guinea","PY":"Paraguay","PE":"Peru","PH":"Philippines",
            "PN":"Pitcairn","PL":"Poland","PT":"Portugal","PR":"Puerto Rico","QA":"Qatar",
            "RE":"R?union","RO":"Romania","RU":"Russia","RW":"Rwanda","BL":"Saint Barth?lemy",
            "SH":"Saint Helena","KN":"Saint Kitts and Nevis","LC":"Saint Lucia","MF":"Saint Martin",
            "PM":"Saint Pierre and Miquelon","VC":"Saint Vincent and the Grenadines","WS":"Samoa",
            "SM":"San Marino","ST":"Sao Tome and Principe","SA":"Saudi Arabia","SN":"Senegal",
            "RS":"Serbia","SC":"Seychelles","SL":"Sierra Leone","SG":"Singapore","SX":"Sint Maarten",
            "SK":"Slovakia","SI":"Slovenia","SB":"Solomon Islands","SO":"Somalia","ZA":"South Africa",
            "GS":"South Georgia","SS":"South Sudan","ES":"Spain","LK":"Sri Lanka","SD":"Sudan",
            "SR":"Suriname","SJ":"Svalbard and Jan Mayen","SE":"Sweden","CH":"Switzerland",
            "SY":"Syria","TW":"Taiwan","TJ":"Tajikistan","TZ":"Tanzania","TH":"Thailand",
            "TL":"Timor-Leste","TG":"Togo","TK":"Tokelau","TO":"Tonga","TT":"Trinidad and Tobago",
            "TN":"Tunisia","TR":"Turkey","TM":"Turkmenistan","TC":"Turks and Caicos Islands",
            "TV":"Tuvalu","UG":"Uganda","UA":"Ukraine","AE":"United Arab Emirates",
            "GB":"United Kingdom","US":"United States","UM":"US Minor Outlying Islands",
            "UY":"Uruguay","UZ":"Uzbekistan","VU":"Vanuatu","VE":"Venezuela","VN":"Vietnam",
            "VG":"British Virgin Islands","VI":"US Virgin Islands","WF":"Wallis and Futuna",
            "EH":"Western Sahara","YE":"Yemen","ZM":"Zambia","ZW":"Zimbabwe"
        }
        return names[cc] || cc
    }
    function peerLocationLabel(countryCode, regionName, cityName) {
        var cc = safeStr(countryCode).trim().toUpperCase()
        var region = safeStr(regionName).trim()
        var city = safeStr(cityName).trim()
        var placeParts = []
        if (city.length > 0)
            placeParts.push(city)
        if (region.length > 0)
            placeParts.push(region)
        var lines = []
        if (placeParts.length > 0)
            lines.push(placeParts.join(", "))
        if (cc.length > 0)
            lines.push(countryFullName(cc))
        return lines.length > 0 ? lines.join("\n") : "Location unavailable"
    }
    function hasGeoCoordinates(latitude, longitude) {
        var lat = Number(latitude)
        var lon = Number(longitude)
        return isFinite(lat) && isFinite(lon) && !(lat === 0 && lon === 0)
    }
    function haversineKm(lat1, lon1, lat2, lon2) {
        var a1 = Number(lat1), o1 = Number(lon1), a2 = Number(lat2), o2 = Number(lon2)
        if (!isFinite(a1) || !isFinite(o1) || !isFinite(a2) || !isFinite(o2))
            return NaN
        var rad = Math.PI / 180.0
        var dLat = (a2 - a1) * rad
        var dLon = (o2 - o1) * rad
        var s1 = Math.sin(dLat / 2.0)
        var s2 = Math.sin(dLon / 2.0)
        var aa = s1 * s1 + Math.cos(a1 * rad) * Math.cos(a2 * rad) * s2 * s2
        var c = 2.0 * Math.atan2(Math.sqrt(aa), Math.sqrt(1.0 - aa))
        return 6371.0 * c
    }
    function distanceSummary(latitude, longitude) {
        if (!root.torrentPeerModel || !root.torrentPeerModel.hasLocalLocation || !hasGeoCoordinates(latitude, longitude))
            return "Distance unavailable"
        var km = haversineKm(root.torrentPeerModel.localLatitude, root.torrentPeerModel.localLongitude,
                             latitude, longitude)
        if (!isFinite(km))
            return "Distance unavailable"
        var mi = km * 0.621371
        return km.toFixed(km >= 100 ? 0 : 1) + " km (" + mi.toFixed(mi >= 100 ? 0 : 1) + " mi)"
    }
    function peerInfoMapTransform(peer, width, height) {
        var marginX = 34
        var marginY = 52
        var localOk = !!root.torrentPeerModel && root.torrentPeerModel.hasLocalLocation
        var peerOk = peer && root.hasGeoCoordinates(peer.latitude, peer.longitude)
        if (!localOk || !peerOk)
            return { scale: 1, offsetX: 0, offsetY: 0, localX: width / 2, localY: height / 2, peerX: width / 2, peerY: height / 2 }

        var lx = root.peerMapX(root.torrentPeerModel.localLongitude, width)
        var ly = root.peerMapY(root.torrentPeerModel.localLatitude, width, height)
        var px = root.peerMapX(peer.longitude, width)
        var py = root.peerMapY(peer.latitude, width, height)
        var minX = Math.min(lx, px)
        var maxX = Math.max(lx, px)
        var minY = Math.min(ly, py)
        var maxY = Math.max(ly, py)
        var spanX = Math.max(24, maxX - minX)
        var spanY = Math.max(18, maxY - minY)
        var fitScale = Math.min((width - marginX * 2) / spanX, (height - marginY * 2) / spanY)
        var scale = Math.min(16, Math.max(0.8, fitScale))
        var cx = (lx + px) / 2
        var cy = (ly + py) / 2
        return {
            scale: scale,
            offsetX: width / 2 - cx * scale,
            offsetY: height / 2 - cy * scale,
            localX: lx * scale + (width / 2 - cx * scale),
            localY: ly * scale + (height / 2 - cy * scale),
            peerX: px * scale + (width / 2 - cx * scale),
            peerY: py * scale + (height / 2 - cy * scale)
        }
    }
    function peerFlagsList(flags) {
        var raw = safeStr(flags).trim()
        return raw.length > 0 ? raw.split(/\s+/) : []
    }
    function peerLineWidth(peer) {
        if (!peer)
            return 1
        var speed = Math.max(Number(peer.downSpeed) || 0, Number(peer.upSpeed) || 0)
        if (speed <= 0)
            return 0
        var base = 1.5
        if (speed >= 5 * 1000 * 1000)
            base = 4
        else if (speed >= 1000 * 1000)
            base = 3
        else if (speed >= 128 * 1024)
            base = 2

        // The map surface itself is zoom-scaled, so compensate here to keep the
        // connection thickness visually consistent as the user zooms in/out.
        var zoom = Math.max(1.0, Number(root.peerMapZoom) || 1.0)
        return Math.max(1, base / zoom)
    }
    function flagColor(flag) {
        switch (flag) {
        case "IN":  return "#e8c84a"   // yellow - incoming
        case "OUT": return ColorPalette.textSecond   // muted - outgoing
        case "TRK": return "#5f93c9"   // blue - tracker
        case "DHT": return "#4db8ff"   // cyan-blue - DHT
        case "PEX": return "#a06de8"   // purple - PeX
        case "LSD": return "#4caf7d"   // green - local
        case "UTP": return "#5ecfe8"   // teal - uTP
        case "ENC": return "#7dd87d"   // green - encrypted
        case "SNB": return "#e86a5c"   // red - snubbed
        case "UPO": return "#c97de8"   // magenta - upload-only
        case "OPT": return "#e8a35c"   // orange - optimistic
        case "HPX": return "#ff8ab4"   // pink - holepunch
        case "I2P": return "#a8ff78"   // lime - I2P
        default:    return ColorPalette.textSecond
        }
    }
    function flagTip(flag) {
        switch (flag) {
        case "IN":  return qsTr("Incoming: they connected to you")
        case "OUT": return qsTr("Outgoing: you connected to them")
        case "TRK": return qsTr("Found via tracker")
        case "DHT": return qsTr("Found via DHT (no tracker needed)")
        case "PEX": return qsTr("Found through another peer you're connected to")
        case "LSD": return qsTr("Found on your local network (same Wi-Fi or LAN)")
        case "UTP": return qsTr("Uses uTP, a protocol that avoids congesting your network")
        case "ENC": return qsTr("Traffic is encrypted")
        case "SNB": return qsTr("Stalled: they haven't sent any data in a while")
        case "UPO": return qsTr("They already have the whole file and are only uploading")
        case "OPT": return qsTr("Given a trial upload slot to see if they're worth keeping")
        case "HPX": return qsTr("Connected through a firewall using another peer's help")
        case "I2P": return qsTr("Connected over the I2P anonymous network")
        default:    return flag
        }
    }
    function peerTraffic(peer) {
        if (!peer)
            return 0
        return Math.max(Number(peer.downSpeed) || 0, Number(peer.upSpeed) || 0)
    }
    function peerMapColor(peer) {
        if (!peer)
            return "#5f93c9"
        return peer.isSeed ? "#4caf7d" : "#5f93c9"
    }
    function peerMapLineColor(peer) {
        if (!peer)
            return "#00000000"
        var dl = Number(peer.downSpeed) || 0
        var ul = Number(peer.upSpeed) || 0
        var speed = Math.max(dl, ul)
        if (speed <= 0)
            return "#00000000"
        var alpha = 0.22
        if (speed >= 5 * 1000 * 1000)      alpha = 0.88
        else if (speed >= 1000 * 1000)     alpha = 0.70
        else if (speed >= 250 * 1000)      alpha = 0.52
        else if (speed >= 30 * 1000)       alpha = 0.36
        // download-only: blue; upload-only: green; both: purple
        if (dl > 0 && ul > 0)
            return Qt.rgba(0.6, 0.35, 0.9, alpha)   // purple
        if (ul > 0)
            return Qt.rgba(0.30, 0.69, 0.48, alpha)  // green
        return Qt.rgba(0.373, 0.576, 0.788, alpha)   // blue
    }
    function peerPlaceText(peer) {
        if (!peer)
            return ""
        var cc = safeStr(peer.countryCode)
        var city = safeStr(peer.cityName)
        var region = safeStr(peer.regionCode)
        var regionName = safeStr(peer.regionName)
        var parts = []
        if (city)
            parts.push(city)
        if (region && (cc === "US" || cc === "CA"))
            parts.push(region)
        else if (regionName)
            parts.push(regionName)
        if (cc)
            parts.push(cc)
        return parts.join(", ")
    }
    function showPeerMapHover(peer, x, y) {
        peerMapHoverVisible = !!peer
        if (!peer)
            return
        peerMapHoverEndpoint = safeStr(peer.endpoint)
        peerMapHoverPort = peer.port | 0
        peerMapHoverClient = safeStr(peer.client)
        peerMapHoverCountryCode = safeStr(peer.countryCode)
        peerMapHoverRegionCode = safeStr(peer.regionCode)
        peerMapHoverRegionName = safeStr(peer.regionName)
        peerMapHoverCityName = safeStr(peer.cityName)
        peerMapHoverRtt = peer.rtt | 0
        peerMapHoverDownSpeed = peer.downSpeed | 0
        peerMapHoverUpSpeed = peer.upSpeed | 0
        peerMapHoverIsSeed = !!peer.isSeed
        peerMapHoverSource = safeStr(peer.source)
        peerMapHoverFlags = safeStr(peer.flags)
        peerMapHoverProgress = Number(peer.progress) || 0
        peerMapHoverX = Number(x) || 0
        peerMapHoverY = Number(y) || 0
    }
    function hidePeerMapHover() {
        peerMapHoverVisible = false
    }

    function ratioText(value) {
        var v = Number(value)
        return isFinite(v) ? v.toFixed(2) : "0.00"
    }

    // Formats seconds into human-readable "Xh Xm" / "Xm Xs" / "Xs" / "-"
    function formatDuration(secs) {
        var s = Math.max(0, secs | 0)
        if (s <= 0) return "-"
        var h = Math.floor(s / 3600)
        var m = Math.floor((s % 3600) / 60)
        var r = s % 60
        if (h > 0) return h + "h " + m + "m"
        if (m > 0) return m + "m " + r + "s"
        return r + "s"
    }

    function clampPct(v) {
        var x = Number(v)
        return (!isFinite(x) || x < 0) ? 0 : (x > 1 ? 1 : x)
    }

    function applyTorrentSpeedLimits() {
        if (!root.item || !root.item.isTorrent)
            return
        var down = Math.max(0, editPerTorrentDownLimitKBps | 0)
        var up = Math.max(0, editPerTorrentUpLimitKBps | 0)
        App.setTorrentSpeedLimits(root.item.id, down, up)
    }

    function _peerColW(key) {
        if (key === "country")  return peerColCountry
        if (key === "endpoint") return peerColPeer
        if (key === "port")     return peerColPort
        if (key === "client")   return peerColClient
        if (key === "progress") return peerColProgress
        if (key === "down")     return peerColDown
        if (key === "up")       return peerColUp
        if (key === "downloaded") return peerColDownloaded
        if (key === "uploaded") return peerColUploaded
        if (key === "type")     return peerColType
        return 80
    }
    function _trkColW(key) {
        if (key === "tracker")       return trkColTracker
        if (key === "status")        return trkColStatus
        if (key === "source")        return trkColSource
        if (key === "seeders")       return trkColSeeders
        if (key === "peers")         return trkColPeers
        if (key === "nextAnnounce")  return trkColNextAnnounce
        if (key === "message")       return trkColMessage
        return 80
    }
    function _fileColW(key) {
        if (key === "name")     return fileColName
        if (key === "progress") return fileColProgress
        if (key === "size")     return fileColSize
        return 80
    }

    function _applyPeerColReorder() {
        if (!_peerColDragFromKey) return
        var keys = _peerColsOrdered.map(function(c){ return c.key })
        var fromIdx = keys.indexOf(_peerColDragFromKey)
        if (fromIdx < 0) return
        var toIdx = _peerColDragInsertBeforeKey === "__end__"
            ? keys.length : keys.indexOf(_peerColDragInsertBeforeKey)
        if (toIdx < 0 || toIdx === fromIdx) return
        var moved = keys.splice(fromIdx, 1)[0]
        if (toIdx > fromIdx) toIdx--
        keys.splice(toIdx, 0, moved)
        peerColOrderJson = JSON.stringify(keys)
    }
    function _applyTrkColReorder() {
        if (!_trkColDragFromKey) return
        var keys = _trkColsOrdered.map(function(c){ return c.key })
        var fromIdx = keys.indexOf(_trkColDragFromKey)
        if (fromIdx < 0) return
        var toIdx = _trkColDragInsertBeforeKey === "__end__"
            ? keys.length : keys.indexOf(_trkColDragInsertBeforeKey)
        if (toIdx < 0 || toIdx === fromIdx) return
        var moved = keys.splice(fromIdx, 1)[0]
        if (toIdx > fromIdx) toIdx--
        keys.splice(toIdx, 0, moved)
        trkColOrderJson = JSON.stringify(keys)
    }
    function _applyFileColReorder() {
        if (!_fileColDragFromKey) return
        var keys = _fileColsOrdered.map(function(c){ return c.key })
        var fromIdx = keys.indexOf(_fileColDragFromKey)
        if (fromIdx < 0) return
        var toIdx = _fileColDragInsertBeforeKey === "__end__"
            ? keys.length : keys.indexOf(_fileColDragInsertBeforeKey)
        if (toIdx < 0 || toIdx === fromIdx) return
        var moved = keys.splice(fromIdx, 1)[0]
        if (toIdx > fromIdx) toIdx--
        keys.splice(toIdx, 0, moved)
        fileColOrderJson = JSON.stringify(keys)
    }

    function sortPeers(key) {
        if (!torrentPeerModel) return
        if (peerSortKey === key)
            peerSortAscending = !peerSortAscending
        else {
            peerSortKey = key
            peerSortAscending = (key === "country" || key === "endpoint" || key === "client" || key === "type" || key === "region" || key === "city")
        }
        torrentPeerModel.sortBy(peerSortKey, peerSortAscending)
    }

    function sortTrackers(key) {
        if (!activeTrackerListModel) return
        if (trkSortKey === key)
            trkSortAscending = !trkSortAscending
        else {
            trkSortKey = key
            // Text columns default ascending; numeric/time columns default descending (highest first)
            trkSortAscending = (key === "tracker" || key === "status" || key === "source" || key === "message")
        }
        activeTrackerListModel.sortBy(trkSortKey, trkSortAscending)
    }

    function savePeerListViewport() {
        var list = root._peerListViewRef
        if (!list)
            return
        _peerSavedTopRow = Math.max(0, Math.floor(list.contentY / 26))
        _peerSavedRowOffset = list.contentY - (_peerSavedTopRow * 26)
        _peerSavedContentY = list.contentY
        _peerSavedContentX = list.contentX
        _peerSavedTopKey = root.torrentPeerModel ? root.torrentPeerModel.peerKeyAt(_peerSavedTopRow) : ""
        _peerViewportRestorePending = true
        _peerViewportRestoreByAnchor = list.moving || (root.torrentPeerModel && root.torrentPeerModel.structuralUpdatesDeferred())
    }

    function syncPeerStructuralUpdates() {
        if (!torrentPeerModel)
            return
        var moving = !!_peerListViewRef && _peerListViewRef.moving
        torrentPeerModel.setStructuralUpdatesDeferred(visible && _isTorrent && currentTab === 3 && moving)
    }

    function swarmStatsKey() {
        if (!root.item)
            return ""
        var hash = safeStr(root.item.torrentInfoHash)
        if (hash.length > 0)
            return hash
        return safeStr(root.item.id)
    }

    function parseSwarmStatsStore() {
        try {
            var obj = JSON.parse(swarmStatsStoreJson || "{}")
            if (obj && typeof obj === "object")
                swarmStatsStore = obj
            else
                swarmStatsStore = {}
        } catch (e) {
            swarmStatsStore = {}
        }
    }

    function serializeSwarmStatsStore() {
        swarmStatsStoreJson = JSON.stringify(swarmStatsStore || {})
    }

    function loadSwarmStatsForCurrent() {
        parseSwarmStatsStore()
        var key = swarmStatsKey()
        if (!key || !swarmStatsStore[key] || !Array.isArray(swarmStatsStore[key].samples)) {
            swarmSamples = []
            swarmClientBreakdown = {}
            swarmCountryBreakdown = {}
            swarmClientRows = []
            swarmCountryRows = []
            swarmClientLegendRows = []
            swarmCountryLegendRows = []
            return
        }
        swarmSamples = swarmStatsStore[key].samples.slice()
        swarmClientBreakdown = mergeBreakdownFromSamples("client")
        swarmCountryBreakdown = mergeBreakdownFromSamples("country")
        swarmClientRows = breakdownRows(swarmClientBreakdown, "client")
        swarmCountryRows = breakdownRows(swarmCountryBreakdown, "country")
        swarmClientLegendRows = topBreakdownRows(swarmClientRows, 8)
        swarmCountryLegendRows = topBreakdownRows(swarmCountryRows, 8)
        Qt.callLater(_rebuildSwarmCache)
    }

    function persistSwarmStatsForCurrent() {
        parseSwarmStatsStore()
        var key = swarmStatsKey()
        if (!key)
            return
        swarmStatsStore[key] = { samples: swarmSamples.slice() }
        serializeSwarmStatsStore()
    }

    function appendSwarmSample() {
        if (!root.item || !root._isTorrent || !root.torrentPeerModel)
            return
        var now = Date.now()
        // Prefer tracker/list counts over currently connected peers.
        var trackerPeers = Number(root.item.torrentListPeers) || 0
        var trackerSeeders = Number(root.item.torrentListSeeders) || 0
        var peers = trackerPeers > 0 ? trackerPeers : (Number(root.item.torrentPeers) || 0)
        var seeders = trackerSeeders > 0 ? trackerSeeders : (Number(root.item.torrentSeeders) || 0)
        var ratio = Number(root.item.torrentRatio) || 0
        var client = root.torrentPeerModel.breakdownByClient()
        var country = root.torrentPeerModel.breakdownByCountry()
        swarmSamples.push({ t: now, peers: peers, seeders: seeders, ratio: ratio, client: client, country: country })
        var cutoff = now - (24 * 60 * 60 * 1000)
        while (swarmSamples.length > 0 && swarmSamples[0].t < cutoff)
            swarmSamples.shift()
    }

    function swarmVisibleSamples() {
        var now = Date.now()
        var cutoff = now - (swarmPeriodSeconds * 1000)
        var rows = []
        for (var i = 0; i < swarmSamples.length; ++i) {
            var s = swarmSamples[i]
            if (s.t >= cutoff)
                rows.push(s)
        }
        if (rows.length === 0 && root.item) {
            rows.push({
                t: now,
                peers: (Number(root.item.torrentListPeers) || 0) > 0 ? (Number(root.item.torrentListPeers) || 0) : (Number(root.item.torrentPeers) || 0),
                seeders: (Number(root.item.torrentListSeeders) || 0) > 0 ? (Number(root.item.torrentListSeeders) || 0) : (Number(root.item.torrentSeeders) || 0),
                ratio: Number(root.item.torrentRatio) || 0,
                client: root.torrentPeerModel ? root.torrentPeerModel.breakdownByClient() : {},
                country: root.torrentPeerModel ? root.torrentPeerModel.breakdownByCountry() : {}
            })
        }
        return rows
    }

    function mergeBreakdownFromSamples(kind) {
        var rows = swarmVisibleSamples()
        var merged = {}
        for (var i = 0; i < rows.length; ++i) {
            var m = rows[i][kind] || {}
            for (var key in m) {
                if (!Object.prototype.hasOwnProperty.call(m, key))
                    continue
                var value = Number(m[key]) || 0
                if (value <= 0)
                    continue
                var normalizedKey = key
                if (kind === "client")
                    normalizedKey = baseClientName(key)
                else if (kind === "country") {
                    normalizedKey = safeStr(key).trim().toUpperCase()
                    if (!normalizedKey)
                        normalizedKey = "Unknown"
                }
                merged[normalizedKey] = (Number(merged[normalizedKey]) || 0) + value
            }
        }
        return merged
    }

    function isSwarmUnknownLabel(kind, label) {
        var raw = safeStr(label).trim()
        if (raw.length === 0)
            return true
        var upper = raw.toUpperCase()
        if (upper === "OTHER")
            return true
        if (kind === "country") {
            if (upper === "UNKNOWN" || upper === "N/A" || upper === "NA" || upper === "--" || upper === "??" || upper === "ZZ")
                return true
            return !/^[A-Z]{2}$/.test(upper)
        }
        var lower = raw.toLowerCase()
        return lower === "unknown" || lower === "other" || lower === "n/a"
            || lower === "na" || lower === "none" || lower === "?"
            || lower === "-"
    }

    function swarmSliceColor(kind, index) {
        var clientPalette = ["#4b9cff", "#53c0a4", "#f0c25a", "#d986ff", "#fa7f72", "#62cfff", "#7fd36b", "#e3a25a"]
        var countryPalette = ["#66bb7a", "#5ed0b6", "#b6d45f", "#4da9ff", "#e3bb58", "#e58f65", "#cf80f2", "#6cd7f5"]
        var palette = kind === "country" ? countryPalette : clientPalette
        return palette[Math.max(0, index) % palette.length]
    }

    function breakdownExcludedCount(mapObj, kind) {
        var excluded = 0
        for (var key in mapObj) {
            if (!Object.prototype.hasOwnProperty.call(mapObj, key))
                continue
            var count = Number(mapObj[key]) || 0
            if (count <= 0)
                continue
            if (isSwarmUnknownLabel(kind, key))
                excluded += count
        }
        return excluded
    }

    function breakdownRows(mapObj, kind) {
        var total = 0
        var rows = []
        for (var key in mapObj) {
            if (!Object.prototype.hasOwnProperty.call(mapObj, key))
                continue
            var count = Number(mapObj[key]) || 0
            if (count <= 0)
                continue
            if (isSwarmUnknownLabel(kind, key))
                continue
            total += count
            rows.push({ label: key, count: count })
        }
        rows.sort(function(a, b) { return b.count - a.count })
        var out = []
        for (var i = 0; i < rows.length; ++i) {
            var pct = total > 0 ? (rows[i].count * 100.0 / total) : 0
            out.push({
                label: rows[i].label,
                count: rows[i].count,
                pct: pct,
                color: swarmSliceColor(kind, i)
            })
        }
        return out
    }
    function topBreakdownRows(rows, limit) {
        var n = Math.max(0, Math.min(rows.length, limit || 8))
        var out = []
        for (var i = 0; i < n; ++i)
            out.push(rows[i])
        return out
    }
    function pieSliceAt(rows, normPos) {
        var p = Math.max(0, Math.min(0.999999, Number(normPos) || 0))
        var acc = 0
        for (var i = 0; i < rows.length; ++i) {
            acc += Math.max(0, Number(rows[i].pct) || 0) / 100.0
            if (p <= acc)
                return rows[i]
        }
        return rows.length > 0 ? rows[rows.length - 1] : null
    }
    function swarmLegendSample() {
        if (swarmLiveHoverActive && swarmHoverSample)
            return swarmHoverSample
        var d = _swarmDecimated
        if (d.length === 0)
            return { t: Date.now(), peers: 0, seeders: 0, ratio: 0 }
        return d[d.length - 1]
    }

    function _rebuildSwarmCache() {
        _swarmNowMs = Date.now()
        var rows = swarmVisibleSamples()
        // Decimate to a canvas-friendly count before blurring.
        var maxPts = 400
        if (rows.length > maxPts) {
            var step = rows.length / maxPts
            var dec = []
            for (var bi = 0; bi < maxPts; ++bi) {
                var lo = Math.floor(bi * step)
                var hi = Math.min(rows.length - 1, Math.floor((bi + 1) * step) - 1)
                if (lo > hi) hi = lo
                var sp = 0, ss = 0, sr = 0, n = 0
                for (var j = lo; j <= hi; ++j) {
                    sp += Number(rows[j].peers)   || 0
                    ss += Number(rows[j].seeders) || 0
                    sr += Number(rows[j].ratio)   || 0
                    n++
                }
                var mid = rows[Math.floor((lo + hi) / 2)]
                dec.push({ t: mid.t, peers: sp / n, seeders: ss / n, ratio: sr / n,
                           client: mid.client, country: mid.country })
            }
            rows = dec
        }
        // Box-blur passes scale with span length.
        var span = swarmPeriodSeconds
        var passes = span < 600 ? 0 : span < 3600 ? 1 : span < 10800 ? 3 : 6
        for (var p = 0; p < passes; ++p) {
            var blurred = new Array(rows.length)
            for (var i = 0; i < rows.length; ++i) {
                if (i === 0 || i === rows.length - 1) {
                    blurred[i] = rows[i]
                } else {
                    blurred[i] = {
                        t:       rows[i].t,
                        peers:   (rows[i-1].peers   + rows[i].peers   + rows[i+1].peers)   / 3,
                        seeders: (rows[i-1].seeders + rows[i].seeders + rows[i+1].seeders) / 3,
                        ratio:   (rows[i-1].ratio   + rows[i].ratio   + rows[i+1].ratio)   / 3,
                        client:  rows[i].client,
                        country: rows[i].country
                    }
                }
            }
            rows = blurred
        }
        _swarmDecimated = rows
    }

    /* Swarm Statistics monitoring timer - disabled pending rework
    Timer {
        id: swarmStatsTimer
        interval: 60000
        repeat: true
        running: root.visible && root._isTorrent
        onTriggered: {
            if (!root.torrentPeerModel)
                return
            root.appendSwarmSample()
            root.swarmClientBreakdown = root.mergeBreakdownFromSamples("client")
            root.swarmCountryBreakdown = root.mergeBreakdownFromSamples("country")
            root.swarmClientRows = root.breakdownRows(root.swarmClientBreakdown, "client")
            root.swarmCountryRows = root.breakdownRows(root.swarmCountryBreakdown, "country")
            root.swarmClientLegendRows = root.topBreakdownRows(root.swarmClientRows, 8)
            root.swarmCountryLegendRows = root.topBreakdownRows(root.swarmCountryRows, 8)
            root.persistSwarmStatsForCurrent()
            root._rebuildSwarmCache()
            if (root.currentTab === 5 && root.swarmCanvasRef)
                root.swarmCanvasRef.requestPaint()
            if (root.currentTab === 5 && root.swarmLiveCanvasRef) root.swarmLiveCanvasRef.requestPaint()
            if (root.currentTab === 5 && root.swarmClientPieRef) root.swarmClientPieRef.requestPaint()
            if (root.currentTab === 5 && root.swarmCountryPieRef) root.swarmCountryPieRef.requestPaint()
        }
    }
    */

    function restorePeerListViewport() {
        if (!_peerViewportRestorePending)
            return
        Qt.callLater(function() {
            var list = root._peerListViewRef
            if (!list || list.count <= 0)
                return
            var maxX = Math.max(0, list.contentWidth - list.width)
            var maxY = Math.max(0, list.contentHeight - list.height)
            if (root._peerViewportRestoreByAnchor) {
                var row = -1
                if (root.torrentPeerModel && root._peerSavedTopKey.length > 0)
                    row = root.torrentPeerModel.indexOfPeerKey(root._peerSavedTopKey)
                if (row < 0)
                    row = Math.max(0, Math.min(root._peerSavedTopRow, list.count - 1))
                list.positionViewAtIndex(row, ListView.Beginning)
                list.contentY = Math.max(0, Math.min(maxY, list.contentY + root._peerSavedRowOffset))
            } else {
                list.contentY = Math.max(0, Math.min(maxY, root._peerSavedContentY))
            }
            list.contentX = Math.max(0, Math.min(maxX, root._peerSavedContentX))
            root._peerViewportRestorePending = false
            root._peerViewportRestoreByAnchor = false
        })
    }

    // ?? Shared components ????????????????????????????????????????????????????
    component ReadOnlyField: Rectangle {
        property alias fieldText: ti.text
        property color textColor: ColorPalette.textPrimary
        implicitHeight: 26
        color: ColorPalette.inputBg
        border.color: ti.activeFocus ? "#4488dd" : ColorPalette.border
        radius: 2
        clip: true
        TextInput {
            id: ti
            anchors { fill: parent; leftMargin: 6; rightMargin: 6 }
            verticalAlignment: TextInput.AlignVCenter
            color: parent.textColor
            font.pixelSize: 12 * App.fontScale
            readOnly: true; selectByMouse: true; clip: true
        }
    }

    // ?? File chooser ?????????????????????????????????????????????????????????
    FileDialog {
        id: moveFileDialog
        title: _isTorrent ? qsTr("Move Torrent Data To...") : qsTr("Move File To...")
        fileMode: FileDialog.SaveFile
        currentFolder: {
            if (!root.item) return ""
            var p = safeStr(root.item.savePath).replace(/\\/g, "/")
            return p ? fileUrlFromPath(p) : ""
        }
        currentFile: {
            if (!root.item) return ""
            var p = safeStr(root.item.savePath).replace(/\\/g, "/")
            var f = safeStr(root.item.filename)
            return (p && f) ? fileUrlFromPath(p + "/" + f) : ""
        }
        onAccepted: {
            if (!root.item) return
            var newPath = pathFromFileUrl(selectedFile)
            if (newPath.length > 0) App.moveDownloadFile(root.item.id, newPath)
        }
    }
    FolderDialog {
        id: moveTorrentDialog
        currentFolder: {
            if (!root.item) return ""
            var p = safeStr(root.item.savePath).replace(/\\/g, "/")
            return p ? fileUrlFromPath(p) : ""
        }
        onAccepted: {
            if (!root.item) return
            var newPath = pathFromFileUrl(selectedFolder)
            if (newPath.length > 0) App.moveDownloadFile(root.item.id, newPath)
        }
    }

    // ?? Root layout ??????????????????????????????????????????????????????????
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 0
        spacing: 0

        Loader {
            id: propertiesLoader
            Layout.fillWidth: true
            Layout.fillHeight: true
            sourceComponent: _isTorrent ? torrentLayout : regularLayout
            onLoaded: {
                root._applySize()
                if (root.visible)
                    root._centerOnOwner()
                // Nudge the window size in a later event-loop tick to force
                // Qt to run a full layout pass with the new Loader content.
                // The Loader swap invalidates geometry but Qt coalesces the
                // relayout into the current frame - which runs before the new
                // component's implicit sizes have fully propagated. A deferred
                // +1/-1 nudge triggers a second, clean layout pass.
                layoutNudgeTimer.restart()
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 12
            Layout.rightMargin: 12
            Layout.bottomMargin: 8
            Layout.topMargin: 8
            spacing: 6
            DlgButton {
                visible: root._isTorrent
                text: qsTr("Torrent Settings...")
                enabled: !!root.item
                onClicked: {
                    speedLimitDialog.torrentItem = root.item
                    speedLimitDialog.show()
                    speedLimitDialog.raise()
                    speedLimitDialog.requestActivate()
                }
            }
            DlgButton {
                visible: root._isTorrent
                text: qsTr("Verify Local Data")
                enabled: !!root.item && !root._torrentIsMoving
                onClicked: { if (root.item) App.forceRecheckTorrent(root.item.id) }
            }
            Item { Layout.fillWidth: true }
            DlgButton {
                visible: root._isTorrent
                text: qsTr("Start")
                enabled: !!root.item && safeStr(root.item.status) === "Paused"
                onClicked: { if (root.item) App.resumeDownload(root.item.id) }
            }
            DlgButton {
                visible: root._isTorrent
                text: qsTr("Stop")
                enabled: !!root.item
                         && safeStr(root.item.status) !== "Paused"
                         && safeStr(root.item.status) !== "Error"
                onClicked: { if (root.item) App.pauseDownload(root.item.id) }
            }
            Item {
                visible: root._isTorrent
                Layout.preferredWidth: 10
            }
            DlgButton {
                text: qsTr("Open folder")
                enabled: !!root.item
                onClicked: { if (root.item) App.openFolderSelectFile(root.item.id) }
            }
            DlgButton {
                text: qsTr("Open file")
                enabled: !!root.item
                onClicked: { if (root.item) App.openFile(root.item.id) }
            }
            DlgButton { text: qsTr("Close"); primary: true; onClicked: root.close() }
        }
    }

    // ?? Per-torrent speed limit dialog (opened from General tab) ?????????????
    TorrentSpeedLimitDialog {
        id: speedLimitDialog
    }

    // ??????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????
    // Regular HTTP/FTP file layout
    // ??????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????
    Component {
        id: regularLayout
        ColumnLayout {
            spacing: 8

            // Header card
            Rectangle {
                Layout.fillWidth: true; Layout.preferredHeight: 74
                color: ColorPalette.headerStripBg; border.width: 0; radius: 0
                RowLayout {
                    anchors { fill: parent; leftMargin: 14; rightMargin: 14; topMargin: 10; bottomMargin: 10 }
                    spacing: 8
                    Image {
                        Layout.preferredWidth: 22; Layout.preferredHeight: 22
                        source: {
                            if (!root.item) return ""
                            var p = safeStr(root.item.savePath).replace(/\\/g, "/")
                            var f = safeStr(root.item.filename)
                            return (p && f) ? ("image://fileicon/" + p + "/" + f) : ""
                        }
                        sourceSize: Qt.size(32, 32); fillMode: Image.PreserveAspectFit
                        asynchronous: true
                    }
                    ColumnLayout {
                        Layout.fillWidth: true; spacing: 4
                        Text {
                            text: root.item ? safeStr(root.item.filename) : ""
                            color: ColorPalette.textHeader; font.pixelSize: 14 * App.fontScale; font.bold: true
                            elide: Text.ElideMiddle; Layout.fillWidth: true
                        }
                        Text {
                            text: ""
                            color: ColorPalette.textPrimary; font.pixelSize: 10 * App.fontScale
                            elide: Text.ElideRight; Layout.fillWidth: true
                            visible: false
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8
                            Text {
                                text: root.item ? safeStr(root.item.statusText) : "--"
                                color: root.item && safeStr(root.item.status) === "Downloading" ? "#62a8ff"
                                     : root.item && safeStr(root.item.status) === "Paused" ? "#b7b7b7"
                                     : root.item && safeStr(root.item.status) === "Completed" ? "#67bb7a"
                                     : root.item && safeStr(root.item.status) === "Error" ? "#d97b7b"
                                     : ColorPalette.textPrimary
                                font.pixelSize: 11 * App.fontScale
                                font.bold: true
                            }
                            Text {
                                text: root.item ? root.compactBytes(root.item.totalBytes) : "--"
                                color: ColorPalette.textPrimary; font.pixelSize: 11 * App.fontScale
                                elide: Text.ElideRight; Layout.fillWidth: true
                            }
                        }
                    }
                }
            }

            // Details card
            Rectangle {
                Layout.fillWidth: true; Layout.fillHeight: true
                color: ColorPalette.cardBg; border.width: 0; radius: 3

                ColumnLayout {
                    anchors { fill: parent; margins: 8 }
                    spacing: 6

                    GridLayout {
                        Layout.fillWidth: true
                        columns: 2; columnSpacing: 8; rowSpacing: 6

                        Text { text: qsTr("Status");  color: ColorPalette.textSecond; font.pixelSize: 12 * App.fontScale; font.bold: true }
                        Text { text: root.item ? safeStr(root.item.statusText) : "--"; color: ColorPalette.textPrimary; font.pixelSize: 12 * App.fontScale; Layout.fillWidth: true }

                        Text { text: qsTr("Size");    color: ColorPalette.textSecond; font.pixelSize: 12 * App.fontScale; font.bold: true }
                        Text { text: root.item ? root.formatBytes(root.item.totalBytes) : "--"; color: ColorPalette.textPrimary; font.pixelSize: 12 * App.fontScale }

                        Text { text: qsTr("Save to"); color: ColorPalette.textSecond; font.pixelSize: 12 * App.fontScale; font.bold: true }
                        RowLayout {
                            Layout.fillWidth: true; spacing: 6
                            ReadOnlyField {
                                Layout.fillWidth: true
                                fieldText: {
                                    if (!root.item) return "--"
                                    var p = safeStr(root.item.savePath).replace(/\//g, "\\")
                                    var f = safeStr(root.item.filename)
                                    return p + ((p && f) ? "\\" : "") + f
                                }
                            }
                            DlgButton { text: qsTr("Move"); enabled: !!root.item; onClicked: { if (root._isTorrent) moveTorrentDialog.open(); else moveFileDialog.open() } }
                        }

                        Text { text: qsTr("Address"); color: ColorPalette.textSecond; font.pixelSize: 12 * App.fontScale; font.bold: true }
                        ReadOnlyField {
                            Layout.fillWidth: true
                            fieldText: root.item ? safeStr(root.item.url) : "--"
                            textColor: "#4488dd"
                        }

                        Text { text: qsTr("Web page"); color: ColorPalette.textSecond; font.pixelSize: 12 * App.fontScale; font.bold: true }
                        Text {
                            text: { var p = root.item ? safeStr(root.item.parentUrl) : ""; return p || "(unknown)" }
                            color: ColorPalette.textPrimary; font.pixelSize: 12 * App.fontScale; elide: Text.ElideMiddle; Layout.fillWidth: true
                        }

                        Text { text: qsTr("Referer"); color: ColorPalette.textSecond; font.pixelSize: 12 * App.fontScale; font.bold: true }
                        Text {
                            text: { var r = root.item ? safeStr(root.item.referrer) : ""; return r || "(none)" }
                            color: ColorPalette.textPrimary; font.pixelSize: 12 * App.fontScale; elide: Text.ElideMiddle; Layout.fillWidth: true
                        }

                        Text { text: qsTr("Description"); color: ColorPalette.textSecond; font.pixelSize: 12 * App.fontScale; font.bold: true }
                        TextField {
                            Layout.fillWidth: true; implicitHeight: 26
                            text: root.item ? safeStr(root.item.description) : ""
                            color: ColorPalette.textPrimary; font.pixelSize: 12 * App.fontScale
                            background: Rectangle { color: ColorPalette.inputBg; border.color: parent.activeFocus ? "#4488dd" : ColorPalette.border; radius: 2 }
                            leftPadding: 6; topPadding: 0; bottomPadding: 0
                            onTextChanged: if (root.item && text !== root.item.description) App.setDownloadDescription(root.item.id, text)
                        }

                        Text { text: qsTr("Login"); color: ColorPalette.textSecond; font.pixelSize: 12 * App.fontScale; font.bold: true }
                        TextField {
                            Layout.fillWidth: true; implicitHeight: 26
                            text: root.item ? safeStr(root.item.username) : ""
                            color: ColorPalette.textPrimary; font.pixelSize: 12 * App.fontScale
                            background: Rectangle { color: ColorPalette.inputBg; border.color: parent.activeFocus ? "#4488dd" : ColorPalette.border; radius: 2 }
                            leftPadding: 6; topPadding: 0; bottomPadding: 0
                            onTextChanged: if (root.item && text !== root.item.username) App.setDownloadUsername(root.item.id, text)
                        }

                        Text { text: qsTr("Password"); color: ColorPalette.textSecond; font.pixelSize: 12 * App.fontScale; font.bold: true }
                        TextField {
                            Layout.fillWidth: true; implicitHeight: 26
                            text: root.item ? safeStr(root.item.password) : ""
                            echoMode: TextInput.Password
                            color: ColorPalette.textPrimary; font.pixelSize: 12 * App.fontScale
                            background: Rectangle { color: ColorPalette.inputBg; border.color: parent.activeFocus ? "#4488dd" : ColorPalette.border; radius: 2 }
                            leftPadding: 6; topPadding: 0; bottomPadding: 0
                            onTextChanged: if (root.item && text !== root.item.password) App.setDownloadPassword(root.item.id, text)
                        }
                    }
                    Item { Layout.fillHeight: true }
                }
            }
        }
    }

    //??????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????
    // Torrent layout
    // ??????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????
    Component {
        id: torrentLayout
        ColumnLayout {
            spacing: 8

            // ?? Summary header ????????????????????????????????????????????????
            // Compact two-row layout: icon + title/status + ETA on row 1; progress
            // bar with percent + down/up speed + seeders/peers on row 2. The full
            // stats grid lives on the General tab.
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: contentCol.implicitHeight + 8
                color: ColorPalette.headerStripBg; border.width: 0; radius: 0

                ColumnLayout {
                    id: contentCol
                    anchors { fill: parent; leftMargin: 14; rightMargin: 14; topMargin: 4; bottomMargin: 4 }
                    spacing: 4

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        Image {
                            Layout.preferredWidth: 22
                            Layout.preferredHeight: 22
                            source: {
                                if (!root.item) return ""
                                var p = safeStr(root.item.savePath).replace(/\\/g, "/")
                                var f = safeStr(root.item.filename)
                                return (p && f) ? ("image://fileicon/" + p + "/" + f) : ""
                            }
                            sourceSize: Qt.size(22, 22)
                            fillMode: Image.PreserveAspectFit
                            asynchronous: true
                        }

                        Text {
                            text: root.item ? safeStr(root.item.filename) : ""
                            color: ColorPalette.textHeader; font.pixelSize: 13 * App.fontScale; font.bold: true
                            elide: Text.ElideMiddle; Layout.fillWidth: true
                        }

                        Text {
                            text: root.torrentStatusLabel()
                            color: ColorPalette.textHeader
                            font.pixelSize: 11 * App.fontScale
                            font.bold: true
                        }

                        // Hide ETA once the download is complete (no remaining time
                        // to show).
                        Text {
                            readonly property string _eta: root.item ? safeStr(root.item.timeLeft) : ""
                            readonly property bool _isCompleteState: {
                                if (!root.item) return false
                                var s = safeStr(root.item.status)
                                return s === "Completed" || s === "Seeding"
                            }
                            visible: !_isCompleteState && _eta.length > 0
                            text: qsTr("ETA: %1").arg(_eta)
                            color: ColorPalette.textPrimary
                            font.pixelSize: 11 * App.fontScale
                            elide: Text.ElideRight
                        }
                    }

                    // Progress bar + live transfer + swarm stats
                    RowLayout {
                        Layout.fillWidth: true; spacing: 8
                        Text {
                            text: root.item ? Math.round(root.clampPct(root.item.progress) * 100) + "%" : "0%"
                            color: ColorPalette.textHeader; font.pixelSize: 12 * App.fontScale; font.bold: true
                            Layout.preferredWidth: 38
                        }
                        // Have / total bytes (e.g. "123 MB / 3.2 GB"). Hidden until
                        // metadata arrives (totalBytes <= 0 for magnets in fetch).
                        Text {
                            visible: root.item && root.item.totalBytes > 0
                            text: root.item
                                ? root.compactBytes(root.item.doneBytes) + " / " + root.compactBytes(root.item.totalBytes)
                                : ""
                            color: ColorPalette.textHeader; font.pixelSize: 11 * App.fontScale
                        }
                        Rectangle {
                            Layout.fillWidth: true; height: 5; radius: 2
                            color: ColorPalette.cardBg; border.color: ColorPalette.dividerBg
                            Rectangle {
                                width: Math.max(0, parent.width * (root.item ? root.clampPct(root.item.progress) : 0))
                                height: parent.height; radius: parent.radius; color: "#4488dd"
                            }
                        }
                        // ? down speed
                        Text {
                            text: "↓ " + (root.item ? root.compactSpeed(root.item.speed) : "0 B/s")
                            color: ColorPalette.textHeader; font.pixelSize: 11 * App.fontScale
                        }
                        // ? up speed
                        Text {
                            text: "↑ " + (root.item ? root.compactSpeed(root.item.torrentUploadSpeed) : "0 B/s")
                            color: ColorPalette.textHeader; font.pixelSize: 11 * App.fontScale
                        }
                        // Seeders: connected (total)
                        Text {
                            text: root.item ? qsTr("Seeds: %1 (%2)").arg(root.item.torrentSeeders | 0).arg(root.item.torrentListSeeders | 0) : qsTr("Seeds: %1 (%2)").arg(0).arg(0)
                            color: ColorPalette.textPrimary; font.pixelSize: 11 * App.fontScale
                        }
                        // Peers: connected (total)
                        Text {
                            text: root.item ? qsTr("Peers: %1 (%2)").arg(root.item.torrentPeers | 0).arg(root.item.torrentListPeers | 0) : qsTr("Peers: %1 (%2)").arg(0).arg(0)
                            color: ColorPalette.textPrimary; font.pixelSize: 11 * App.fontScale
                        }
                    }
                }
            }

            // ?? Tab strip ?????????????????????????????????????????????????????
            Rectangle {
                Layout.fillWidth: true; height: 34
                color: ColorPalette.panelBg

                Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: ColorPalette.border }

                Row {
                    anchors.fill: parent; spacing: 0
                    Repeater {
                        model: [qsTr("General"), qsTr("Speed"), qsTr("Files"), qsTr("Peers"), qsTr("Swarm Map"), qsTr("Trackers"), qsTr("Web Seeds"), qsTr("Piece Map")]
                        delegate: Rectangle {
                            width: tabLbl.implicitWidth + 28; height: parent.height
                            color: root.currentTab === index
                                   ? ColorPalette.cardBg
                                   : (tabHov.containsMouse ? ColorPalette.hoverBg : "transparent")
                            Text {
                                id: tabLbl; anchors.centerIn: parent
                                text: modelData
                                color: root.currentTab === index ? ColorPalette.textHeader : ColorPalette.textSecond
                                font.pixelSize: 12 * App.fontScale
                            }
                            Rectangle {
                                anchors.bottom: parent.bottom
                                width: parent.width; height: 2
                                color: "transparent"
                            }
                            MouseArea {
                                id: tabHov; anchors.fill: parent; hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.currentTab = index
                            }
                        }
                    }
                }
            }

            // ?? Tab pages ?????????????????????????????????????????????????????
            StackLayout {
                Layout.fillWidth: true; Layout.fillHeight: true
                currentIndex: root.currentTab

                // ?? General ???????????????????????????????????????????????????
                Item {
                    ScrollView {
                        id: generalScrollView
                        anchors { fill: parent; topMargin: 2; bottomMargin: 2; leftMargin: 12; rightMargin: 12 }
                        clip: true
                        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
                        ScrollBar.vertical.policy: ScrollBar.AsNeeded

                        ColumnLayout {
                            width: generalScrollView.availableWidth
                            spacing: 0

                            // ?? Info + Save (merged, compact) ?????????????????
                            // 2-col grid: label | content-row (field + optional actions).
                            // Action buttons live inside the content row so each row
                            // controls its own action area independently - no off-center
                            // buttons or stretched fields.
                            GridLayout {
                                id: infoGrid
                                Layout.fillWidth: true
                                Layout.topMargin: 8
                                columns: 2
                                columnSpacing: 8
                                rowSpacing: 5
                                property real lw: 68

                                // Source
                                Text { text: qsTr("Source"); color: ColorPalette.textSecond; font.pixelSize: 11 * App.fontScale; Layout.preferredWidth: parent.lw; Layout.alignment: Qt.AlignVCenter }
                                ReadOnlyField {
                                    Layout.fillWidth: true
                                    fieldText: root.item ? safeStr(root.item.torrentSource) : ""
                                    textColor: ColorPalette.textPrimary
                                }

                                // Info hash - sized to fit a SHA1/SHA256 hash; badge + Copy follow inline.
                                Text { text: qsTr("Info hash"); color: ColorPalette.textSecond; font.pixelSize: 11 * App.fontScale; Layout.preferredWidth: parent.lw; Layout.alignment: Qt.AlignVCenter }
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 8
                                    ReadOnlyField {
                                        Layout.preferredWidth: 360
                                        Layout.maximumWidth: 360
                                        fieldText: root.item ? safeStr(root.item.torrentInfoHash) : ""
                                    }
                                    Item { Layout.fillWidth: true }
                                    DlgButton {
                                        text: qsTr("Copy")
                                        enabled: !!root.item && safeStr(root.item.torrentInfoHash).length > 0
                                        onClicked: { var h = safeStr(root.item.torrentInfoHash); if (h.length > 0) App.copyToClipboard(h) }
                                    }
                                }

                                // Save to
                                Text { text: qsTr("Save to"); color: ColorPalette.textSecond; font.pixelSize: 11 * App.fontScale; Layout.preferredWidth: parent.lw; Layout.alignment: Qt.AlignVCenter }
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 8
                                    ReadOnlyField { Layout.fillWidth: true; fieldText: root.item ? safeStr(root.item.savePath) : "" }
                                    DlgButton {
                                        text: qsTr("Move...")
                                        enabled: !!root.item && !root._torrentIsMoving
                                        onClicked: { if (root._isTorrent) moveTorrentDialog.open(); else moveFileDialog.open() }
                                    }
                                }

                                // Category
                                Text { text: qsTr("Category"); color: ColorPalette.textSecond; font.pixelSize: 11 * App.fontScale; Layout.preferredWidth: parent.lw; Layout.alignment: Qt.AlignVCenter }
                                ComboBox {
                                    id: categoryCombo
                                    Layout.preferredWidth: 180
                                    Layout.fillWidth: false
                                    implicitHeight: 26
                                    model: App.categoryModel
                                    textRole: "categoryLabel"
                                    valueRole: "categoryId"
                                    font.pixelSize: 11 * App.fontScale
                                    property bool _syncing: false
                                    function _syncFromItem() {
                                        if (!root.item) return
                                        _syncing = true
                                        var idx = indexOfValue(root.item.category)
                                        currentIndex = idx >= 0 ? idx : 0
                                        _syncing = false
                                    }
                                    Component.onCompleted: _syncFromItem()
                                    Connections {
                                        target: root
                                        function onItemChanged() { categoryCombo._syncFromItem() }
                                    }
                                    Connections {
                                        target: root.item
                                        ignoreUnknownSignals: true
                                        function onCategoryChanged() { categoryCombo._syncFromItem() }
                                    }
                                    onActivated: {
                                        if (_syncing || !root.item) return
                                        var newId = currentValue
                                        if (!newId) return
                                        if (newId !== root.item.category)
                                            App.setDownloadCategory(root.item.id, newId)
                                    }

                                    // Themed look — default Qt ComboBox uses the
                                    // system palette, giving white-on-white popup
                                    // items in this dialog. Theme content, field
                                    // and popup explicitly via ColorPalette.
                                    contentItem: Text {
                                        leftPadding: 8
                                        text: categoryCombo.displayText
                                        font: categoryCombo.font
                                        color: ColorPalette.textPrimary
                                        verticalAlignment: Text.AlignVCenter
                                        elide: Text.ElideRight
                                    }
                                    background: Rectangle {
                                        color: ColorPalette.cardBg
                                        border.color: categoryCombo.activeFocus ? "#4488dd" : ColorPalette.border
                                        radius: 2
                                    }
                                    delegate: ItemDelegate {
                                        width: categoryCombo.width
                                        height: 24
                                        highlighted: categoryCombo.highlightedIndex === index
                                        contentItem: Text {
                                            text: model.categoryLabel
                                            font.pixelSize: 11 * App.fontScale
                                            color: ColorPalette.textPrimary
                                            verticalAlignment: Text.AlignVCenter
                                            elide: Text.ElideRight
                                        }
                                        background: Rectangle {
                                            color: parent.highlighted ? ColorPalette.toolbarHoverBg : "transparent"
                                        }
                                    }
                                    popup: Popup {
                                        y: categoryCombo.height
                                        width: categoryCombo.width
                                        implicitHeight: Math.min(contentItem.implicitHeight, 240)
                                        padding: 1
                                        contentItem: ListView {
                                            clip: true
                                            implicitHeight: contentHeight
                                            model: categoryCombo.popup.visible ? categoryCombo.delegateModel : null
                                            currentIndex: categoryCombo.highlightedIndex
                                            ScrollIndicator.vertical: ScrollIndicator {}
                                        }
                                        background: Rectangle {
                                            color: ColorPalette.cardBg
                                            border.color: ColorPalette.border
                                            radius: 2
                                        }
                                    }
                                }

                                // Note
                                Text { text: qsTr("Note"); color: ColorPalette.textSecond; font.pixelSize: 11 * App.fontScale; Layout.preferredWidth: parent.lw; Layout.alignment: Qt.AlignVCenter }
                                TextField {
                                    Layout.fillWidth: true
                                    implicitHeight: 26
                                    text: root.item ? safeStr(root.item.description) : ""
                                    color: ColorPalette.textPrimary; font.pixelSize: 11 * App.fontScale
                                    background: Rectangle { color: ColorPalette.inputBg; border.color: parent.activeFocus ? "#4488dd" : ColorPalette.border; radius: 2 }
                                    leftPadding: 7; topPadding: 0; bottomPadding: 0
                                    onTextChanged: if (root.item && text !== root.item.description) App.setDownloadDescription(root.item.id, text)
                                }
                            }

                            Rectangle { Layout.fillWidth: true; height: 1; color: ColorPalette.border; Layout.topMargin: 8; Layout.bottomMargin: 0 }

                            // ?? Transfer Stats section ?????????????????????????
                            GridLayout {
                                Layout.fillWidth: true
                                Layout.topMargin: 7
                                columns: 6; columnSpacing: 8; rowSpacing: 5
                                property real lw: 80

                                Text { text: qsTr("Downloaded");  color: ColorPalette.textSecond; font.pixelSize: 11 * App.fontScale; Layout.preferredWidth: parent.lw }
                                Text { text: root.item ? root.compactBytes(root.item.torrentDownloaded) : "-"; color: ColorPalette.textPrimary; font.pixelSize: 11 * App.fontScale; Layout.fillWidth: true }
                                Text { text: qsTr("Uploaded");    color: ColorPalette.textSecond; font.pixelSize: 11 * App.fontScale; Layout.preferredWidth: parent.lw }
                                Text { text: root.item ? root.compactBytes(root.item.torrentUploaded) : "-";   color: ColorPalette.textPrimary; font.pixelSize: 11 * App.fontScale; Layout.fillWidth: true }
                                Text { text: qsTr("Wasted");      color: ColorPalette.textSecond; font.pixelSize: 11 * App.fontScale; Layout.preferredWidth: parent.lw }
                                Text {
                                    text: { if (!root.item) return "-"; var w = root.item.torrentWastedBytes; return (w > 0) ? root.compactBytes(w) : "-" }
                                    color: (root.item && root.item.torrentWastedBytes > 0) ? "#b8924a" : ColorPalette.textPrimary
                                    font.pixelSize: 11 * App.fontScale; Layout.fillWidth: true
                                }

                                Text { text: qsTr("Down speed");  color: ColorPalette.textSecond; font.pixelSize: 11 * App.fontScale; Layout.preferredWidth: parent.lw }
                                Text { text: root.item ? root.compactSpeed(root.item.speed) : "-"; color: "#4ea2ff"; font.pixelSize: 11 * App.fontScale; Layout.fillWidth: true }
                                Text { text: qsTr("Up speed");    color: ColorPalette.textSecond; font.pixelSize: 11 * App.fontScale; Layout.preferredWidth: parent.lw }
                                Text { text: root.item ? root.compactSpeed(root.item.torrentUploadSpeed) : "-"; color: "#4cc87a"; font.pixelSize: 11 * App.fontScale; Layout.fillWidth: true }
                                Text { text: qsTr("Connections"); color: ColorPalette.textSecond; font.pixelSize: 11 * App.fontScale; Layout.preferredWidth: parent.lw }
                                Text { text: root.item ? String(root.item.torrentConnections | 0) : "-"; color: ColorPalette.textPrimary; font.pixelSize: 11 * App.fontScale; Layout.fillWidth: true }

                                Text { text: qsTr("Share ratio"); color: ColorPalette.textSecond; font.pixelSize: 11 * App.fontScale; Layout.preferredWidth: parent.lw }
                                Text {
                                    text: root.item ? root.ratioText(root.item.torrentRatio) : "-"
                                    color: { if (!root.item) return ColorPalette.textPrimary; var r = Number(root.item.torrentRatio); return r >= 1.0 ? "#5eaa6e" : r >= 0.5 ? "#c09a50" : ColorPalette.textPrimary }
                                    font.pixelSize: 11 * App.fontScale; Layout.fillWidth: true
                                }
                                // Pieces + Availability on their own row - piece text can be long
                                Text { text: qsTr("Pieces");      color: ColorPalette.textSecond; font.pixelSize: 11 * App.fontScale; Layout.preferredWidth: parent.lw; Layout.columnSpan: 1 }
                                Text {
                                    text: {
                                        if (!root.item) return "-"
                                        var done = root.item.torrentPiecesDone | 0
                                        var total = root.item.torrentPiecesTotal | 0
                                        if (total <= 0) return done > 0 ? String(done) : "-"
                                        return done + " / " + total + " (" + Math.round(done / total * 100) + "%)"
                                    }
                                    color: ColorPalette.textPrimary; font.pixelSize: 11 * App.fontScale; Layout.fillWidth: true; Layout.columnSpan: 1
                                }
                                Text { text: qsTr("Availability"); color: ColorPalette.textSecond; font.pixelSize: 11 * App.fontScale; Layout.preferredWidth: parent.lw }
                                Text {
                                    text: { if (!root.item) return "-"; var av = root.item.torrentAvailability; return (typeof av === "number" && av > 0) ? av.toFixed(2) : "-" }
                                    color: ColorPalette.textPrimary; font.pixelSize: 11 * App.fontScale; Layout.fillWidth: true
                                }

                                Text { text: qsTr("Metadata"); color: ColorPalette.textSecond; font.pixelSize: 11 * App.fontScale; Layout.preferredWidth: parent.lw }
                                Text {
                                    text: (!!root.item && root.item.torrentHasMetadata) ? qsTr("Available") : qsTr("Fetching…")
                                    color: (!!root.item && root.item.torrentHasMetadata) ? "#5eaa6e" : "#c09a50"
                                    font.pixelSize: 11 * App.fontScale; Layout.fillWidth: true; Layout.columnSpan: 3
                                }

                                Text { text: qsTr("Active time"); color: ColorPalette.textSecond; font.pixelSize: 11 * App.fontScale; Layout.preferredWidth: parent.lw }
                                Text { text: root.item ? root.formatDuration(root.item.torrentActiveTimeSecs) : "-";   color: ColorPalette.textPrimary; font.pixelSize: 11 * App.fontScale; Layout.fillWidth: true }
                                Text { text: qsTr("Seed time");   color: ColorPalette.textSecond; font.pixelSize: 11 * App.fontScale; Layout.preferredWidth: parent.lw }
                                Text { text: root.item ? root.formatDuration(root.item.torrentSeedingTimeSecs) : "-"; color: ColorPalette.textPrimary; font.pixelSize: 11 * App.fontScale; Layout.fillWidth: true }
                                // Padding item to complete the 6-column row before metadata rows.
                                // Seed time label+value already used 2 of 6 columns, so this
                                // must span the remaining 4 — otherwise the next row's label
                                // wraps into the wrong column and label/value swap sides.
                                // Always present so the grid stays aligned regardless of which
                                // metadata fields are populated.
                                Item { Layout.columnSpan: 4; Layout.fillWidth: true }

                                // Each metadata field gets its own full row (label + 5-col value)
                                Text { text: qsTr("Description"); color: ColorPalette.textSecond; font.pixelSize: 11 * App.fontScale; Layout.preferredWidth: parent.lw; Layout.alignment: Qt.AlignVCenter
                                    visible: !!root.item && safeStr(root.item.torrentComment).length > 0 }
                                Text { text: root.item ? safeStr(root.item.torrentComment) : ""; color: ColorPalette.textPrimary; font.pixelSize: 11 * App.fontScale; Layout.fillWidth: true; Layout.columnSpan: 5; wrapMode: Text.WordWrap
                                    visible: !!root.item && safeStr(root.item.torrentComment).length > 0 }

                                Text { text: qsTr("Created by"); color: ColorPalette.textSecond; font.pixelSize: 11 * App.fontScale; Layout.preferredWidth: parent.lw; Layout.alignment: Qt.AlignVCenter
                                    visible: !!root.item && safeStr(root.item.torrentCreator).length > 0 }
                                Text { text: root.item ? safeStr(root.item.torrentCreator) : ""; color: ColorPalette.textPrimary; font.pixelSize: 11 * App.fontScale; Layout.fillWidth: true; Layout.columnSpan: 5; wrapMode: Text.WordWrap
                                    visible: !!root.item && safeStr(root.item.torrentCreator).length > 0 }

                                Text { text: qsTr("Created on"); color: ColorPalette.textSecond; font.pixelSize: 11 * App.fontScale; Layout.preferredWidth: parent.lw; Layout.alignment: Qt.AlignVCenter
                                    visible: !!root.item && safeStr(root.item.torrentCreatedOn).length > 0 }
                                Text { text: root.item ? safeStr(root.item.torrentCreatedOn) : ""; color: ColorPalette.textPrimary; font.pixelSize: 11 * App.fontScale; Layout.fillWidth: true; Layout.columnSpan: 5
                                    visible: !!root.item && safeStr(root.item.torrentCreatedOn).length > 0 }
                                Text {
                                    text: qsTr("Speed limit"); color: ColorPalette.textSecond; font.pixelSize: 11 * App.fontScale; Layout.preferredWidth: parent.lw
                                    visible: !!root.item && (root.item.perTorrentDownLimitKBps > 0 || root.item.perTorrentUpLimitKBps > 0)
                                }
                                Text {
                                    text: {
                                        if (!root.item) return ""
                                        var d = root.item.perTorrentDownLimitKBps | 0
                                        var u = root.item.perTorrentUpLimitKBps   | 0
                                        var parts = []
                                        if (d > 0) parts.push("? " + d + " KB/s")
                                        if (u > 0) parts.push("? " + u + " KB/s")
                                        return parts.join("  ?  ")
                                    }
                                    color: "#d09040"; font.pixelSize: 11 * App.fontScale; Layout.fillWidth: true
                                    visible: !!root.item && (root.item.perTorrentDownLimitKBps > 0 || root.item.perTorrentUpLimitKBps > 0)
                                }
                            }

                        }
                    }
                }

                // Speed
                Item {
                    ColumnLayout {
                        anchors { fill: parent; margins: 10 }
                        spacing: 8

                        // Graph card - fills remaining space
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            color: ColorPalette.inputBg
                            border.color: ColorPalette.border
                            radius: 3
                            clip: true

                            // Main graph canvas - only repaints when data/span changes.
                            // The crosshair lives in a separate overlay canvas so hover
                            // mouse moves don't trigger a full graph redraw.
                            Canvas {
                                id: speedGraphCanvasLoader
                                anchors.fill: parent
                                anchors.margins: 10
                                antialiasing: true
                                renderTarget: Canvas.Image
                                Component.onCompleted: root.speedGraphCanvasRef = speedGraphCanvasLoader
                                Component.onDestruction: {
                                    if (root.speedGraphCanvasRef === speedGraphCanvasLoader)
                                        root.speedGraphCanvasRef = null
                                }

                                onPaint: {
                                    var ctx = getContext("2d")
                                    ctx.reset()
                                    var w = width
                                    var h = height
                                    if (w < 40 || h < 40)
                                        return

                                    var topPad    = 8
                                    var rightPad  = 58
                                    var bottomPad = 20
                                    var leftPad   = 4
                                    var plotX = leftPad
                                    var plotY = topPad
                                    var plotW = Math.max(10, w - leftPad - rightPad)
                                    var plotH = Math.max(10, h - topPad - bottomPad)

                                    // Stable time anchor set at data-refresh time; using
                                    // Date.now() here caused per-repaint x-position jitter.
                                    var nowMs   = root._speedNowMs || Date.now()
                                    var startMs = nowMs - root.speedSpanSeconds * 1000

                                    // Pre-built decimated+smoothed cache - never recomputed on hover.
                                    var samples = root._speedDecimated

                                    // Stable Y ceiling cached in _speedAxisTop - computed once per
                                    // data refresh, decays slowly so the scale doesn't thrash.
                                    var axisTop = Math.max(1, root._speedAxisTop)

                                    function pxForTime(t) {
                                        return plotX + ((t - startMs) / (root.speedSpanSeconds * 1000)) * plotW
                                    }
                                    function pyForRate(v) {
                                        return plotY + plotH - (Math.max(0, v) / axisTop) * plotH
                                    }

                                    // Background
                                    ctx.fillStyle = ColorPalette.mapCanvasBg
                                    ctx.fillRect(0, 0, w, h)

                                    // Horizontal grid lines only
                                    var gridLines = 4
                                    ctx.lineWidth = 1
                                    for (var gy = 0; gy <= gridLines; ++gy) {
                                        var gy2 = Math.round(plotY + plotH * gy / gridLines) + 0.5
                                        ctx.strokeStyle = ColorPalette.mapGrid
                                        ctx.beginPath(); ctx.moveTo(plotX, gy2); ctx.lineTo(plotX + plotW, gy2); ctx.stroke()
                                    }

                                    // Catmull-Rom spline area+line series.
                                    // Passes through every data point with smooth tangents derived
                                    // from neighbours.  Control-point conversion:
                                    //   cp1 = P[i]   + (P[i+1] - P[i-1]) / 6
                                    //   cp2 = P[i+1] - (P[i+2] - P[i])   / 6
                                    function drawSmoothedSeries(key, stroke, fillTop, fillBottom) {
                                        var n = samples.length
                                        if (n === 0) return

                                        var xs = new Array(n), ys = new Array(n)
                                        for (var pi = 0; pi < n; ++pi) {
                                            xs[pi] = pxForTime(samples[pi].t)
                                            ys[pi] = pyForRate(samples[pi][key])
                                        }

                                        var baseY  = plotY + plotH
                                        var firstX = xs[0]

                                        function buildSplinePath() {
                                            ctx.moveTo(xs[0], ys[0])
                                            if (n === 1) {
                                                ctx.lineTo(xs[0], ys[0])
                                            } else {
                                                for (var ci = 0; ci < n - 1; ++ci) {
                                                    var im1 = Math.max(0, ci - 1)
                                                    var ip2 = Math.min(n - 1, ci + 2)
                                                    var cp1x = xs[ci]     + (xs[ci + 1] - xs[im1]) / 6
                                                    var cp1y = ys[ci]     + (ys[ci + 1] - ys[im1]) / 6
                                                    var cp2x = xs[ci + 1] - (xs[ip2]    - xs[ci])  / 6
                                                    var cp2y = ys[ci + 1] - (ys[ip2]    - ys[ci])  / 6
                                                    // Clamp control point Y to plot bounds so Catmull-Rom
                                                    // overshoot on steep spikes never draws below zero or
                                                    // above the top of the plot area.
                                                    cp1y = Math.max(plotY, Math.min(baseY, cp1y))
                                                    cp2y = Math.max(plotY, Math.min(baseY, cp2y))
                                                    ctx.bezierCurveTo(cp1x, cp1y, cp2x, cp2y, xs[ci + 1], ys[ci + 1])
                                                }
                                            }
                                        }

                                        var grad = ctx.createLinearGradient(0, plotY, 0, baseY)
                                        grad.addColorStop(0, fillTop)
                                        grad.addColorStop(1, fillBottom)
                                        ctx.beginPath()
                                        buildSplinePath()
                                        ctx.lineTo(xs[n - 1], baseY)
                                        ctx.lineTo(firstX, baseY)
                                        ctx.closePath()
                                        ctx.fillStyle = grad
                                        ctx.fill()

                                        ctx.beginPath()
                                        buildSplinePath()
                                        ctx.strokeStyle = stroke
                                        ctx.lineWidth = 1.5
                                        ctx.stroke()
                                    }

                                    // Upload behind download so download renders on top
                                    drawSmoothedSeries("up",   "#3dba6a", "rgba(61,186,106,0.20)", "rgba(61,186,106,0.02)")
                                    drawSmoothedSeries("down", "#4490e8", "rgba(68,144,232,0.28)", "rgba(68,144,232,0.03)")

                                    // Y-axis labels - right side
                                    ctx.fillStyle = ColorPalette.textDisabled
                                    ctx.font = "10px sans-serif"
                                    ctx.textAlign = "left"
                                    ctx.textBaseline = "middle"
                                    for (var ly = 0; ly <= gridLines; ++ly) {
                                        var val = axisTop * (1 - ly / gridLines)
                                        var ty = plotY + plotH * ly / gridLines
                                        ctx.fillText(root.speedAxisLabel(val), plotX + plotW + 5, ty)
                                    }

                                    // X-axis time labels
                                    ctx.fillStyle = ColorPalette.textDisabled
                                    ctx.textAlign = "center"
                                    ctx.textBaseline = "top"
                                    for (var lx = 0; lx <= 6; ++lx) {
                                        var secAgo = Math.round(root.speedSpanSeconds * (1 - lx / 6))
                                        var tx = plotX + plotW * lx / 6
                                        var timeLabel = secAgo >= 3600
                                            ? (Math.floor(secAgo / 3600) + "h")
                                            : (secAgo >= 60 ? (Math.round(secAgo / 60) + "m") : (secAgo + "s"))
                                        ctx.fillText("-" + timeLabel, tx, plotY + plotH + 3)
                                    }
                                }
                            }

                            // Crosshair overlay - tiny canvas that only redraws on mouse move.
                            // Keeping this separate prevents the full graph from repainting on
                            // every pixel of mouse movement, which was the main source of jitter.
                            Canvas {
                                id: speedHoverCanvas
                                anchors.fill: speedGraphCanvasLoader
                                antialiasing: false
                                renderTarget: Canvas.Image

                                onPaint: {
                                    var ctx = getContext("2d")
                                    ctx.reset()
                                    if (!root.speedHoverActive)
                                        return
                                    var topPad    = 8
                                    var rightPad  = 58
                                    var bottomPad = 20
                                    var leftPad   = 4
                                    var plotX = leftPad
                                    var plotY = topPad
                                    var plotW = Math.max(10, width - leftPad - rightPad)
                                    var plotH = Math.max(10, height - topPad - bottomPad)
                                    var hx = Math.round(Math.max(plotX, Math.min(plotX + plotW, root.speedHoverX))) + 0.5
                                    ctx.strokeStyle = "rgba(180,200,230,0.22)"
                                    ctx.lineWidth = 1
                                    ctx.setLineDash([3, 3])
                                    ctx.beginPath()
                                    ctx.moveTo(hx, plotY)
                                    ctx.lineTo(hx, plotY + plotH)
                                    ctx.stroke()
                                    ctx.setLineDash([])
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                onPositionChanged: function(mouse) {
                                    root.speedHoverActive = true
                                    root.speedHoverX = mouse.x - 10
                                    speedHoverCanvas.requestPaint()
                                }
                                onEntered: {
                                    root.speedHoverActive = true
                                    speedHoverCanvas.requestPaint()
                                }
                                onExited: {
                                    root.speedHoverActive = false
                                    speedHoverCanvas.requestPaint()
                                }
                            }

                            Rectangle {
                                id: speedHoverTip
                                visible: root.speedHoverActive
                                radius: 3
                                color: ColorPalette.mapCanvasBg
                                border.color: ColorPalette.mapBorder
                                anchors.top: parent.top
                                anchors.topMargin: 14
                                x: Math.max(10, Math.min(parent.width - width - 10, root.speedHoverX + 16))
                                width: tipCol.implicitWidth + 12
                                height: tipCol.implicitHeight + 10

                                readonly property var _samples: root._speedDecimated
                                readonly property real _plotLeft: 4
                                readonly property real _plotRightPad: 58
                                readonly property real _plotWidth: Math.max(1, speedGraphCanvasLoader.width - _plotLeft - _plotRightPad)
                                readonly property real _ratio: Math.max(0, Math.min(1, (root.speedHoverX - _plotLeft) / _plotWidth))
                                readonly property real _targetT: (root._speedNowMs || Date.now()) - root.speedSpanSeconds * 1000 + (_ratio * root.speedSpanSeconds * 1000)
                                readonly property int _nearestIndex: {
                                    if (_samples.length === 0) return -1
                                    var best = 0
                                    var bestDiff = Math.abs((_samples[0].t || 0) - _targetT)
                                    for (var i = 1; i < _samples.length; ++i) {
                                        var d = Math.abs((_samples[i].t || 0) - _targetT)
                                        if (d < bestDiff) { best = i; bestDiff = d }
                                    }
                                    return best
                                }
                                readonly property var _point: (_nearestIndex >= 0 && _nearestIndex < _samples.length) ? _samples[_nearestIndex] : null
                                readonly property int _ageSec: _point ? Math.max(0, Math.round((Date.now() - _point.t) / 1000)) : 0

                                Column {
                                    id: tipCol
                                    anchors.centerIn: parent
                                    spacing: 2
                                    Text {
                                        text: speedHoverTip._point ? root.formatClockTime(speedHoverTip._point.t) : ""
                                        color: ColorPalette.textPrimary
                                        font.pixelSize: 11 * App.fontScale
                                        font.bold: true
                                    }
                                    Text {
                                        text: speedHoverTip._point ? root.formatAgoNatural(speedHoverTip._ageSec) : ""
                                        color: ColorPalette.textPrimary
                                        font.pixelSize: 10 * App.fontScale
                                    }
                                    Text {
                                        text: speedHoverTip._point ? ("↓ " + root.compactSpeed(speedHoverTip._point.down)) : ""
                                        color: "#7ab8f5"
                                        font.pixelSize: 11 * App.fontScale
                                    }
                                    Text {
                                        text: speedHoverTip._point ? ("↑ " + root.compactSpeed(speedHoverTip._point.up)) : ""
                                        color: "#82d4a0"
                                        font.pixelSize: 11 * App.fontScale
                                    }
                                }
                            }
                        }

                        // Stats row + time span selector at the bottom
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 0

                            // Stats grid on the left
                            GridLayout {
                                id: speedStatsCard
                                columns: 6
                                columnSpacing: 14
                                rowSpacing: 3

                                readonly property var _samples: root.speedVisibleSamples()
                                readonly property var _down: root.speedStats(_samples, "down")
                                readonly property var _up: root.speedStats(_samples, "up")

                                // Legend dots
                                Rectangle { width: 8; height: 8; radius: 4; color: "#4490e8" }
                                Text { text: qsTr("Down"); color: ColorPalette.textSecond; font.pixelSize: 11 * App.fontScale }
                                Text { text: root.compactSpeed(speedStatsCard._down.current); color: "#4ea2ff"; font.bold: true; font.pixelSize: 12 * App.fontScale }
                                Text { text: "avg"; color: ColorPalette.textDisabled; font.pixelSize: 10 * App.fontScale }
                                Text { text: root.compactSpeed(speedStatsCard._down.avg); color: "#7ba8d0"; font.pixelSize: 11 * App.fontScale }
                                Text { text: "peak " + root.compactSpeed(speedStatsCard._down.max); color: ColorPalette.textDisabled; font.pixelSize: 10 * App.fontScale }

                                Rectangle { width: 8; height: 8; radius: 4; color: "#3dba6a" }
                                Text { text: qsTr("Up"); color: ColorPalette.textSecond; font.pixelSize: 11 * App.fontScale }
                                Text { text: root.compactSpeed(speedStatsCard._up.current); color: "#4cc87a"; font.bold: true; font.pixelSize: 12 * App.fontScale }
                                Text { text: "avg"; color: ColorPalette.textDisabled; font.pixelSize: 10 * App.fontScale }
                                Text { text: root.compactSpeed(speedStatsCard._up.avg); color: "#7abf9a"; font.pixelSize: 11 * App.fontScale }
                                Text { text: "peak " + root.compactSpeed(speedStatsCard._up.max); color: ColorPalette.textDisabled; font.pixelSize: 10 * App.fontScale }
                            }

                            Item { Layout.fillWidth: true }

                            // Time span selector - compact, bottom-right
                            RowLayout {
                                spacing: 6
                                Text { text: qsTr("Span"); color: ColorPalette.textDisabled; font.pixelSize: 11 * App.fontScale }
                                ComboBox {
                                    implicitWidth: 90
                                    implicitHeight: 24
                                    model: root.speedSpanOptions.map(function(o){ return o.label })
                                    currentIndex: root.speedSpanIndex
                                    onActivated: root.speedSpanIndex = currentIndex
                                    font.pixelSize: 11 * App.fontScale
                                    contentItem: Text {
                                        leftPadding: 8
                                        text: parent.displayText
                                        font: parent.font
                                        color: ColorPalette.textPrimary
                                        verticalAlignment: Text.AlignVCenter
                                    }
                                    background: Rectangle {
                                        color: ColorPalette.cardBg
                                        border.color: parent.activeFocus ? "#4488dd" : ColorPalette.border
                                        radius: 2
                                    }
                                }
                            }
                        }
                    }
                }
                // ?? Files ?????????????????????????????????????????????????????
                Item {
                    ColumnLayout {
                        anchors.fill: parent; spacing: 0

                        // Header bar
                        Rectangle {
                            id: fileHeader
                            Layout.fillWidth: true; height: 26
                            color: ColorPalette.dividerBg; clip: true
                            Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: ColorPalette.border }

                            Row {
                                x: -fileList.contentX
                                width: root.fileColName + root.fileColProgress + root.fileColSize
                                height: parent.height
                                spacing: 0

                                // Name (fill)
                                Item {
                                    width: root.fileColName
                                    height: parent.height
                                    Text {
                                        anchors { verticalCenter: parent.verticalCenter; left: parent.left; leftMargin: 44 }
                                        text: qsTr("Name"); color: ColorPalette.textPrimary; font.pixelSize: 12 * App.fontScale; font.bold: true
                                    }
                                    Rectangle { anchors.right: parent.right; width: 1; height: parent.height; color: ColorPalette.border }
                                    Item {
                                        id: fNameRh; width: 10; height: parent.height; anchors.right: parent.right; z: 10
                                        property real _startW: 0
                                        Rectangle { anchors.right: parent.right; width: 2; height: parent.height
                                            color: (fNameDrag.active || fNameHov.hovered) ? "#6aa0ff" : "transparent"; opacity: 0.8 }
                                        HoverHandler { id: fNameHov; cursorShape: Qt.SizeHorCursor }
                                        DragHandler {
                                            id: fNameDrag; target: null; xAxis.enabled: true; yAxis.enabled: false; cursorShape: Qt.SizeHorCursor
                                            onActiveChanged: if (active) fNameRh._startW = root.fileColName
                                            onTranslationChanged: if (active) root.fileColName = Math.max(180, Math.round(fNameRh._startW + translation.x))
                                        }
                                    }
                                }

                                // Progress (resizable)
                                Item {
                                    width: root.fileColProgress; height: parent.height
                                    Text {
                                        anchors { verticalCenter: parent.verticalCenter; left: parent.left; leftMargin: 6; right: fProgRh.left; rightMargin: 2 }
                                        text: qsTr("Progress"); color: ColorPalette.textPrimary; font.pixelSize: 12 * App.fontScale; font.bold: true; elide: Text.ElideRight
                                    }
                                    Rectangle { anchors.right: parent.right; width: 1; height: parent.height; color: ColorPalette.border }
                                    Item {
                                        id: fProgRh; width: 10; height: parent.height; anchors.right: parent.right; z: 10
                                        property real _startW: 0
                                        Rectangle { anchors.right: parent.right; width: 2; height: parent.height
                                            color: (fProgDrag.active || fProgHov.hovered) ? "#6aa0ff" : "transparent"; opacity: 0.8 }
                                        HoverHandler { id: fProgHov; cursorShape: Qt.SizeHorCursor }
                                        DragHandler {
                                            id: fProgDrag; target: null; xAxis.enabled: true; yAxis.enabled: false; cursorShape: Qt.SizeHorCursor
                                            onActiveChanged: if (active) fProgRh._startW = root.fileColProgress
                                            onTranslationChanged: if (active) root.fileColProgress = Math.max(60, Math.round(fProgRh._startW + translation.x))
                                        }
                                    }
                                }

                                // Size (resizable)
                                Item {
                                    width: root.fileColSize; height: parent.height
                                    Text {
                                        anchors { verticalCenter: parent.verticalCenter; left: parent.left; leftMargin: 6; right: fSizeRh.left; rightMargin: 2 }
                                        text: qsTr("Size"); color: ColorPalette.textPrimary; font.pixelSize: 12 * App.fontScale; font.bold: true; elide: Text.ElideRight
                                    }
                                    Item {
                                        id: fSizeRh; width: 10; height: parent.height; anchors.right: parent.right; z: 10
                                        property real _startW: 0
                                        Rectangle { anchors.right: parent.right; width: 2; height: parent.height
                                            color: (fSizeDrag.active || fSizeHov.hovered) ? "#6aa0ff" : "transparent"; opacity: 0.8 }
                                        HoverHandler { id: fSizeHov; cursorShape: Qt.SizeHorCursor }
                                        DragHandler {
                                            id: fSizeDrag; target: null; xAxis.enabled: true; yAxis.enabled: false; cursorShape: Qt.SizeHorCursor
                                            onActiveChanged: if (active) fSizeRh._startW = root.fileColSize
                                            onTranslationChanged: if (active) root.fileColSize = Math.max(50, Math.round(fSizeRh._startW + translation.x))
                                        }
                                    }
                                }
                            }
                        }

                        ListView {
                            id: fileList
                            Layout.fillWidth: true; Layout.fillHeight: true
                            clip: true; model: root.torrentFileModel; spacing: 0
                            contentWidth: root.fileColName + root.fileColProgress + root.fileColSize
                            flickableDirection: Flickable.HorizontalAndVerticalFlick
                            cacheBuffer: 520
                            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                            ScrollBar.horizontal: ScrollBar { policy: ScrollBar.AlwaysOn }

                            Text {
                                anchors.centerIn: parent
                                visible: fileList.count === 0
                                text: qsTr("No file information available")
                                color: ColorPalette.textDisabled; font.pixelSize: 12 * App.fontScale
                            }

                            delegate: Rectangle {
                                id: fd
                                required property int    index
                                required property string name
                                required property string path
                                required property bool   wanted
                                required property double size
                                required property double progress
                                required property bool   isFolder
                                required property int    depth
                                required property bool   expanded
                                required property int    fileIndex

                                width: Math.max(fileList.width, fileList.contentWidth); height: 26
                                color: isFolder ? ColorPalette.toolbarBg : (index % 2 === 0 ? ColorPalette.windowBg : ColorPalette.rowAltBg)

                                Row {
                                    anchors { fill: parent; leftMargin: 6; rightMargin: 8 }
                                    spacing: 0

                                    // Indent
                                    Item { width: Math.max(0, fd.depth) * 14; height: parent.height }

                                    // Expand toggle
                                    Item {
                                        width: 16; height: parent.height
                                        Text {
                                            visible: fd.isFolder; anchors.centerIn: parent
                                            text: fd.expanded ? "▼" : "▶"
                                            color: "#888"; font.pixelSize: 11 * App.fontScale
                                        }
                                        MouseArea {
                                            visible: fd.isFolder; anchors.fill: parent
                                            acceptedButtons: Qt.LeftButton
                                            onClicked: if (root.torrentFileModel) root.torrentFileModel.toggleExpanded(fd.index)
                                        }
                                    }

                                    // Wanted checkbox - shown for both files and folders.
                                    // Toggling a folder entry sets wanted on all its children.
                                    Item {
                                        width: 22; height: parent.height
                                        Rectangle {
                                            anchors.centerIn: parent
                                            width: 14; height: 14; radius: 2
                                            color: fd.wanted ? "#4488dd" : ColorPalette.inputBg
                                            border.color: fd.wanted ? "#4488dd" : ColorPalette.border
                                            Text {
                                                visible: fd.wanted; anchors.centerIn: parent
                                                text: "✓"; color: ColorPalette.textPrimary
                                                font.pixelSize: 10 * App.fontScale; font.bold: true
                                            }
                                        }
                                        MouseArea {
                                            anchors.fill: parent; enabled: !!root.item
                                            acceptedButtons: Qt.LeftButton
                                            onClicked: App.setTorrentFileWanted(root.item.id, fd.index, !fd.wanted)
                                        }
                                    }

                                    // OS file/folder icon via FileIconImageProvider.
                                    // Folders request a trailing "/" path which the provider uses
                                    // as a hint to fetch the system folder icon instead of a file icon.
                                    Image {
                                        width: 16; height: 16
                                        anchors.verticalCenter: parent.verticalCenter
                                        source: root.item
                                                ? ("image://fileicon/"
                                                   + safeStr(root.item.savePath).replace(/\\/g, "/")
                                                   + "/" + safeStr(fd.path)
                                                   + (fd.isFolder ? "/" : ""))
                                                : ""
                                        sourceSize: Qt.size(16, 16)
                                        fillMode: Image.PreserveAspectFit
                                        asynchronous: true
                                    }

                                    // Name - width subtracts: depth-indent, expand-toggle (16),
                                    // checkbox (22), icon (16) + gap (4), outer margins (6+8).
                                    Text {
                                        width: root.fileColName - Math.max(0, fd.depth) * 14 - 16 - 22 - 16
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: safeStr(fd.name)
                                        color: !fd.wanted ? ColorPalette.textDisabled : (fd.isFolder ? ColorPalette.textPrimary : ColorPalette.textPrimary)
                                        font.pixelSize: 12 * App.fontScale; font.bold: fd.isFolder
                                        elide: Text.ElideMiddle
                                    }

                                    // Progress column: percentage label + bar aligned to column start
                                    Item {
                                        width: root.fileColProgress; height: parent.height

                                        Text {
                                            id: progPctLbl
                                            anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                                            text: Math.round(root.clampPct(fd.progress) * 100) + "%"
                                            color: fd.wanted ? ColorPalette.textPrimary : ColorPalette.textDisabled
                                            font.pixelSize: 11 * App.fontScale
                                            width: 34
                                        }

                                        Rectangle {
                                            anchors {
                                                left: progPctLbl.right; leftMargin: 4
                                                right: parent.right; rightMargin: 6
                                                verticalCenter: parent.verticalCenter
                                            }
                                            height: 4; radius: 2
                                            color: ColorPalette.border
                                            Rectangle {
                                                width: Math.max(0, parent.width * root.clampPct(fd.progress))
                                                height: parent.height; radius: parent.radius
                                                color: fd.wanted ? "#33bb44" : ColorPalette.textDisabled
                                            }
                                        }
                                    }

                                    // Size
                                    Text {
                                        width: root.fileColSize; anchors.verticalCenter: parent.verticalCenter
                                        text: root.compactBytes(fd.size)
                                        color: fd.wanted ? ColorPalette.textPrimary : ColorPalette.textDisabled
                                        font.pixelSize: 12 * App.fontScale; horizontalAlignment: Text.AlignLeft
                                    }
                                }

                                // Handle right-clicks with a dedicated MouseArea because
                                // TapHandler is not firing reliably for these ListView rows on Windows.
                                MouseArea {
                                    anchors.fill: parent
                                    acceptedButtons: Qt.RightButton
                                    onClicked: function(mouse) {
                                        if (mouse.button !== Qt.RightButton)
                                            return
                                        fileCtxPopup._row = fd.index
                                        fileCtxPopup._fileIndex = fd.fileIndex
                                        fileCtxPopup._path = fd.path
                                        fileCtxPopup._name = fd.name
                                        fileCtxPopup._wanted = fd.wanted
                                        fileCtxPopup._isFolder = fd.isFolder
                                        var pos = mapToItem(Overlay.overlay, mouse.x, mouse.y)
                                        fileCtxPopup.x = pos.x
                                        fileCtxPopup.y = pos.y
                                        fileCtxPopup.open()
                                    }
                                }
                            }
                        }

                        Window {
                            id: renameDialog
                            width: 420
                            height: 150
                            minimumWidth: 420
                            maximumWidth: 420
                            minimumHeight: 150
                            maximumHeight: 150
                            visible: false
                            title: qsTr("Rename")
                            color: ColorPalette.cardBg
                            transientParent: root
                            modality: Qt.NonModal
                            flags: Qt.Dialog | Qt.WindowTitleHint | Qt.WindowCloseButtonHint | Qt.WindowSystemMenuHint
                            property string _path: ""
                            property string _currentName: ""
                            property int _fileIndex: -1
                            property bool _isFolder: false

                            function openForRename(path, name, fileIndex, isFolder) {
                                _path = path
                                _currentName = name
                                _fileIndex = fileIndex
                                _isFolder = isFolder
                                renameInput.text = name
                                show()
                                raise()
                                requestActivate()
                            }

                            onVisibleChanged: {
                                if (!visible)
                                    return
                                Qt.callLater(function() {
                                    renameInput.forceActiveFocus()
                                    renameInput.selectAll()
                                })
                            }

                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: 14
                                spacing: 10

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 8
                                    Image {
                                        Layout.preferredWidth: 16
                                        Layout.preferredHeight: 16
                                        source: "icons/rename.svg"
                                        sourceSize: Qt.size(16, 16)
                                        fillMode: Image.PreserveAspectFit
                                        asynchronous: true
                                    }
                                    Text {
                                        text: qsTr("Rename item")
                                        color: ColorPalette.textPrimary; font.pixelSize: 14 * App.fontScale; font.bold: true
                                    }
                                }
                                Text {
                                    text: qsTr("Enter a new file or folder name:")
                                    color: ColorPalette.textSecond; font.pixelSize: 12 * App.fontScale
                                }
                                TextField {
                                    id: renameInput
                                    Layout.fillWidth: true
                                    color: ColorPalette.textPrimary; font.pixelSize: 12 * App.fontScale
                                    selectByMouse: true
                                    leftPadding: 8
                                    background: Rectangle {
                                        color: ColorPalette.inputBg
                                        border.color: parent.activeFocus ? "#4488dd" : ColorPalette.border
                                        radius: 3
                                    }
                                    Keys.onReturnPressed: renameConfirmBtn.clicked()
                                    Keys.onEnterPressed:  renameConfirmBtn.clicked()
                                }
                                RowLayout {
                                    Layout.fillWidth: true; spacing: 8
                                    Item { Layout.fillWidth: true }
                                    DlgButton {
                                        text: qsTr("Cancel")
                                        onClicked: renameDialog.close()
                                    }
                                    DlgButton {
                                        id: renameConfirmBtn
                                        text: qsTr("Rename")
                                        primary: true
                                        enabled: {
                                            var t = renameInput.text.trim()
                                            return t.length > 0
                                                && t !== renameDialog._currentName
                                                && t !== "." && t !== ".."
                                                && t.indexOf("/") === -1
                                                && t.indexOf("\\") === -1
                                        }
                                        onClicked: {
                                            var newName = renameInput.text.trim()
                                            if (newName.length > 0 && root.item) {
                                                if (renameDialog._isFolder)
                                                    App.renameTorrentPath(root.item.id, renameDialog._path, newName)
                                                else
                                                    App.renameTorrentFile(root.item.id, renameDialog._fileIndex, newName)
                                            }
                                            renameDialog.close()
                                        }
                                    }
                                }
                            }
                        }

                        Popup {
                            id: fileCtxPopup
                            parent: Overlay.overlay
                            modal: false
                            padding: 0
                            closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
                            property int _row: -1
                            property int _fileIndex: -1
                            property string _path: ""
                            property string _name: ""
                            property bool _wanted: true
                            property bool _isFolder: false

                            background: Rectangle {
                                color: ColorPalette.panelBg
                                border.color: ColorPalette.border
                                radius: 4
                            }

                            contentItem: Column {
                                spacing: 0

                                Rectangle {
                                    width: 180
                                    height: 34
                                    color: downloadCtxHover.containsMouse ? ColorPalette.border : "transparent"

                                    Row {
                                        anchors.verticalCenter: parent.verticalCenter
                                        anchors.left: parent.left
                                        anchors.leftMargin: 10
                                        spacing: 8

                                        Rectangle {
                                            width: 14
                                            height: 14
                                            radius: 2
                                            color: fileCtxPopup._wanted ? "#4488dd" : ColorPalette.inputBg
                                            border.color: fileCtxPopup._wanted ? "#4488dd" : ColorPalette.border
                                            Text {
                                                visible: fileCtxPopup._wanted
                                                anchors.centerIn: parent
                                                text: "✓"
                                                color: ColorPalette.textPrimary
                                                font.pixelSize: 10 * App.fontScale
                                                font.bold: true
                                            }
                                        }

                                        Text {
                                            text: qsTr("Download")
                                            color: ColorPalette.textPrimary
                                            font.pixelSize: 12 * App.fontScale
                                        }
                                    }

                                    MouseArea {
                                        id: downloadCtxHover
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        onClicked: {
                                            if (root.item) {
                                                // Use stable identifiers instead of the visible row
                                                // number, which changes when folders expand/collapse.
                                                if (fileCtxPopup._fileIndex >= 0)
                                                    App.setTorrentFileWantedByIndex(root.item.id, fileCtxPopup._fileIndex, !fileCtxPopup._wanted)
                                                else
                                                    App.setTorrentFileWantedByPath(root.item.id, fileCtxPopup._path, !fileCtxPopup._wanted)
                                            }
                                            fileCtxPopup.close()
                                        }
                                    }
                                }

                                Rectangle { width: 180; height: 1; color: ColorPalette.border }

                                Rectangle {
                                    width: 180
                                    height: 34
                                    color: renameCtxHover.containsMouse ? ColorPalette.border : "transparent"

                                    Image {
                                        anchors.verticalCenter: parent.verticalCenter
                                        anchors.left: parent.left
                                        anchors.leftMargin: 10
                                        width: 16
                                        height: 16
                                        source: "icons/rename.svg"
                                        sourceSize: Qt.size(16, 16)
                                        fillMode: Image.PreserveAspectFit
                                        asynchronous: true
                                    }
                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        anchors.left: parent.left
                                        anchors.leftMargin: 32
                                        text: qsTr("Rename...")
                                        color: ColorPalette.textPrimary
                                        font.pixelSize: 12 * App.fontScale
                                    }

                                    MouseArea {
                                        id: renameCtxHover
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        onClicked: {
                                            fileCtxPopup.close()
                                            renameDialog.openForRename(fileCtxPopup._path, fileCtxPopup._name, fileCtxPopup._fileIndex, fileCtxPopup._isFolder)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // ?? Peers ?????????????????????????????????????????????????????
                Item {
                    // Peer column widths live on root so they survive tab switches.
                    // Each column header cell has a DragHandler resize handle, mirroring
                    // the exact pattern from DownloadTable.qml.
                    readonly property real totalW:
                        root.peerColCountry + root.peerColPeer + root.peerColPort + root.peerColClient +
                        root.peerColProgress + root.peerColDown + root.peerColUp + root.peerColDownloaded + root.peerColUploaded + root.peerColType

                    ColumnLayout {
                        anchors.fill: parent; spacing: 0

                        // Header - styled identically to DownloadTable
                        Rectangle {
                            id: peerHeader
                            Layout.fillWidth: true; height: 26
                            color: ColorPalette.dividerBg; clip: true

                            Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: ColorPalette.border }

                            Item {
                                x: -peerListView.contentX
                                width: parent.parent.totalW
                                height: parent.height

                                Repeater {
                                    model: root._peerColsOrdered
                                    delegate: Rectangle {
                                        id: peerHdrCell
                                        x: root._peerColXMap[modelData.key] || 0
                                        width: root._peerColW(modelData.key)
                                        height: peerHeader.height
                                        color: hdrMa.containsMouse && !rhDrag.active ? ColorPalette.border : "transparent"
                                        opacity: root._peerColDragging && root._peerColDragFromKey === modelData.key ? 0.5 : 1.0

                                        // Insert-before indicator (left edge)
                                        Rectangle {
                                            anchors.left: parent.left
                                            width: 2; height: parent.height
                                            color: "#4488dd"
                                            visible: root._peerColDragging && root._peerColDragInsertBeforeKey === modelData.key
                                        }

                                        Text {
                                            anchors {
                                                verticalCenter: parent.verticalCenter
                                                left: parent.left; leftMargin: 6
                                                right: sortArrow.left; rightMargin: 2
                                            }
                                            text: modelData.title
                                            color: root.peerSortKey === modelData.sortKey ? "#88bbff" : ColorPalette.textPrimary
                                            font.pixelSize: 12 * App.fontScale; font.bold: true
                                            elide: Text.ElideRight
                                        }

                                        Text {
                                            id: sortArrow
                                            anchors { verticalCenter: parent.verticalCenter; right: rh.left; rightMargin: 4 }
                                            text: root.peerSortAscending ? "▲" : "▼"
                                            color: "#88bbff"; font.pixelSize: 9 * App.fontScale
                                            visible: root.peerSortKey === modelData.sortKey
                                        }

                                        MouseArea {
                                            id: hdrMa
                                            anchors { fill: parent; rightMargin: 10 }
                                            hoverEnabled: true
                                            cursorShape: root._peerColDragging ? Qt.ClosedHandCursor : Qt.PointingHandCursor
                                            onPressed: {
                                                root._peerColDragFromKey = modelData.key
                                                root._peerColDragging = true
                                            }
                                            onPositionChanged: {
                                                if (!root._peerColDragging) return
                                                var mx = mapToItem(peerHeader, mouseX, 0).x + peerListView.contentX
                                                var insertKey = "__end__"
                                                for (var i = 0; i < root._peerColsOrdered.length; i++) {
                                                    var col = root._peerColsOrdered[i]
                                                    var cx = root._peerColXMap[col.key] || 0
                                                    if (mx < cx + root._peerColW(col.key) / 2) { insertKey = col.key; break }
                                                }
                                                root._peerColDragInsertBeforeKey = insertKey
                                            }
                                            onReleased: {
                                                if (root._peerColDragging) root._applyPeerColReorder()
                                                root._peerColDragFromKey = ""
                                                root._peerColDragInsertBeforeKey = ""
                                                root._peerColDragging = false
                                            }
                                            onClicked: {
                                                if (root._peerColDragInsertBeforeKey === "") root.sortPeers(modelData.sortKey)
                                            }
                                        }

                                        Rectangle {
                                            anchors.right: parent.right
                                            width: 1; height: parent.height; color: ColorPalette.border
                                        }

                                        // Resize handle
                                        Item {
                                            id: rh; width: 10; height: parent.height
                                            anchors.right: parent.right; z: 10
                                            property real _startW: 0

                                            Rectangle {
                                                anchors.right: parent.right
                                                width: 2; height: parent.height
                                                color: (rhDrag.active || rhHov.hovered) ? "#6aa0ff" : "transparent"
                                                opacity: rhDrag.active ? 1.0 : 0.75
                                            }

                                            HoverHandler { id: rhHov; cursorShape: Qt.SizeHorCursor }

                                            DragHandler {
                                                id: rhDrag; target: null
                                                xAxis.enabled: true; yAxis.enabled: false
                                                cursorShape: Qt.SizeHorCursor

                                                onActiveChanged: {
                                                    if (active) rh._startW = root._peerColW(modelData.key)
                                                }

                                                onTranslationChanged: {
                                                    if (!active) return
                                                    var newW = Math.max(50, Math.round(rh._startW + translation.x))
                                                    var k = modelData.key
                                                    if      (k === "country")  root.peerColCountry  = newW
                                                    else if (k === "endpoint") root.peerColPeer     = newW
                                                    else if (k === "port")     root.peerColPort     = newW
                                                    else if (k === "client")   root.peerColClient   = newW
                                                    else if (k === "progress") root.peerColProgress = newW
                                                    else if (k === "down")     root.peerColDown     = newW
                                                    else if (k === "up")       root.peerColUp       = newW
                                                    else if (k === "downloaded") root.peerColDownloaded = newW
                                                    else if (k === "uploaded") root.peerColUploaded = newW
                                                    else if (k === "type")     root.peerColType     = newW
                                                }
                                            }
                                        }

                                        // Insert-after-last indicator (right edge of last column)
                                        Rectangle {
                                            anchors.right: parent.right
                                            width: 2; height: parent.height
                                            color: "#4488dd"
                                            visible: root._peerColDragging
                                                && root._peerColDragInsertBeforeKey === "__end__"
                                                && index === root._peerColsOrdered.length - 1
                                        }
                                    }
                                }
                            }
                        }

                        // Peer list
                        ListView {
                            id: peerListView
                            Layout.fillWidth: true; Layout.fillHeight: true
                            clip: true; model: root.activePeerListModel; spacing: 0
                            contentWidth: root.peerColCountry + root.peerColPeer + root.peerColPort + root.peerColClient +
                                          root.peerColProgress + root.peerColDown + root.peerColUp + root.peerColDownloaded + root.peerColUploaded + root.peerColType
                            // Enable horizontal drag-to-pan in addition to the scrollbar.
                            // Without this the ListView only intercepts vertical flick gestures.
                            flickableDirection: Flickable.HorizontalAndVerticalFlick
                            ScrollBar.vertical:   ScrollBar { policy: ScrollBar.AsNeeded }
                            ScrollBar.horizontal: ScrollBar { policy: ScrollBar.AlwaysOn }
                            focus: true
                            reuseItems: true
                            Component.onCompleted: root._peerListViewRef = peerListView
                            Component.onDestruction: if (root._peerListViewRef === peerListView) root._peerListViewRef = null
                            onMovingChanged: root.syncPeerStructuralUpdates()

                            Connections {
                                target: root.torrentPeerModel
                                function onModelAboutToBeReset() {
                                    root.savePeerListViewport()
                                }
                                function onModelReset() {
                                    if (root._peerViewportRestorePending)
                                        root.restorePeerListViewport()
                                }
                                // Save contentY before a live reorder (layoutChanged from
                                // setEntries) and restore it immediately after. QML's ListView
                                // does not preserve scroll position across layoutChanged when
                                // rows shift - without this the view jumps to the top every
                                // time a new peer enters a speed-sorted list.
                                function onLiveReorderAboutToHappen() {
                                    root._peerLiveReorderY = peerListView.contentY
                                }
                                function onLiveReorderHappened() {
                                    peerListView.contentY = root._peerLiveReorderY
                                }
                            }

                            Text {
                                anchors.centerIn: parent
                                visible: peerListView.count === 0
                                text: qsTr("No peers connected")
                                color: ColorPalette.textDisabled; font.pixelSize: 12 * App.fontScale
                            }

                            Popup {
                                id: peerCtxMenu
                                parent: Overlay.overlay
                                modal: false
                                width: 180
                                height: 69
                                padding: 0
                                closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
                                property string endpoint: ""
                                property int port: 0
                                property string client: ""
                                property string countryCode: ""
                                property var peerData: ({})

                                background: Rectangle {
                                    color: ColorPalette.panelBg
                                    border.color: ColorPalette.border
                                    radius: 4
                                }

                                contentItem: Column {
                                    spacing: 0

                                    Rectangle {
                                        width: 180
                                        height: 34
                                        color: peerInfoHover.containsMouse ? ColorPalette.border : "transparent"

                                        Text {
                                            anchors.verticalCenter: parent.verticalCenter
                                            anchors.left: parent.left
                                            anchors.leftMargin: 10
                                            text: qsTr("Peer Info")
                                            color: peerCtxMenu.endpoint.length > 0 ? ColorPalette.textPrimary : ColorPalette.textDisabled
                                            font.pixelSize: 12 * App.fontScale
                                        }

                                        MouseArea {
                                            id: peerInfoHover
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            enabled: peerCtxMenu.endpoint.length > 0
                                            onClicked: {
                                                peerInfoDialog.openForPeer(peerCtxMenu.peerData)
                                                peerCtxMenu.close()
                                            }
                                        }
                                    }

                                    Rectangle { width: 180; height: 1; color: ColorPalette.border }

                                    Rectangle {
                                        width: 180
                                        height: 34
                                        color: peerBanHover.containsMouse ? ColorPalette.border : "transparent"

                                        Text {
                                            anchors.verticalCenter: parent.verticalCenter
                                            anchors.left: parent.left
                                            anchors.leftMargin: 10
                                            text: qsTr("Ban peer")
                                            color: (!!root.item && peerCtxMenu.endpoint.length > 0) ? ColorPalette.textPrimary : ColorPalette.textDisabled
                                            font.pixelSize: 12 * App.fontScale
                                        }

                                        MouseArea {
                                            id: peerBanHover
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            enabled: !!root.item && peerCtxMenu.endpoint.length > 0
                                            onClicked: {
                                                if (root.item) {
                                                    if (root.torrentPeerModel)
                                                        root.torrentPeerModel.removePeer(peerCtxMenu.endpoint, peerCtxMenu.port)
                                                    App.banTorrentPeer(root.item.id, peerCtxMenu.endpoint, peerCtxMenu.port,
                                                                       peerCtxMenu.client, peerCtxMenu.countryCode)
                                                }
                                                peerCtxMenu.close()
                                            }
                                        }
                                    }
                                }
                            }

                            Window {
                                id: peerInfoDialog
                                width: 580
                                height: 420
                                minimumWidth: 560
                                minimumHeight: 400
                                modality: Qt.ApplicationModal
                                flags: Qt.Window | Qt.WindowTitleHint | Qt.WindowCloseButtonHint | Qt.WindowSystemMenuHint
                                title: qsTr("Peer Info")
                                color: ColorPalette.cardBg
                                property var peerData: ({})
                                function blankPeerData() {
                                    return {
                                        endpoint: "",
                                        port: 0,
                                        client: "",
                                        countryCode: "",
                                        countryFlag: "",
                                        regionCode: "",
                                        regionName: "",
                                        cityName: "",
                                        progress: 0,
                                        downSpeed: 0,
                                        upSpeed: 0,
                                        downloaded: 0,
                                        uploaded: 0,
                                        isSeed: false,
                                        flags: "",
                                        latitude: 0,
                                        longitude: 0,
                                        rtt: 0,
                                        source: ""
                                    }
                                }
                                function openForPeer(peer) {
                                    peerData = blankPeerData()
                                    peerData = peer || blankPeerData()
                                    show()
                                    raise()
                                    requestActivate()
                                }

                                Rectangle {
                                    anchors.fill: parent
                                    color: ColorPalette.cardBg

                                    ColumnLayout {
                                        anchors.fill: parent
                                        anchors.margins: 10
                                        spacing: 6

                                        Rectangle {
                                            Layout.fillWidth: true
                                            color: "transparent"
                                            border.width: 0
                                            implicitHeight: headerRow.implicitHeight

                                            RowLayout {
                                                id: headerRow
                                                anchors.fill: parent
                                                spacing: 8

                                                Image {
                                                    source: root.torrentClientIconSource(peerInfoDialog.peerData.client)
                                                    width: 28
                                                    height: 28
                                                    sourceSize.width: 28
                                                    sourceSize.height: 28
                                                    Layout.rightMargin: 6
                                                    fillMode: Image.PreserveAspectFit
                                                    smooth: true
                                                    visible: status === Image.Ready
                                                }
                                                ColumnLayout {
                                                    Layout.fillWidth: true
                                                    spacing: 2

                                                    Row {
                                                        Layout.fillWidth: true
                                                        spacing: 6

                                                        Text {
                                                            text: root.safeStr(peerInfoDialog.peerData.endpoint) || "--"
                                                            color: ColorPalette.textPrimary
                                                            font.pixelSize: 15 * App.fontScale
                                                            font.bold: true
                                                            elide: Text.ElideRight
                                                            anchors.verticalCenter: parent.verticalCenter
                                                        }
                                                        Text {
                                                            text: String(peerInfoDialog.peerData.port || 0)
                                                            color: ColorPalette.textDisabled
                                                            font.pixelSize: 15 * App.fontScale
                                                            anchors.verticalCenter: parent.verticalCenter
                                                        }
                                                    }
                                                    Text {
                                                        text: root.safeStr(peerInfoDialog.peerData.client) || "Unknown client"
                                                        color: ColorPalette.clientText
                                                        font.pixelSize: 12 * App.fontScale
                                                        elide: Text.ElideRight
                                                        Layout.fillWidth: true
                                                    }
                                                    Text {
                                                        text: root.peerLocationLabel(peerInfoDialog.peerData.countryCode, peerInfoDialog.peerData.regionName, peerInfoDialog.peerData.cityName)
                                                        color: ColorPalette.textPrimary
                                                        font.pixelSize: 11 * App.fontScale
                                                        elide: Text.ElideRight
                                                        Layout.fillWidth: true
                                                    }
                                                }
                                                Image {
                                                    source: root.countryFlagSource(peerInfoDialog.peerData.countryCode)
                                                    width: 28
                                                    height: 20
                                                    sourceSize.width: 28
                                                    sourceSize.height: 20
                                                    fillMode: Image.PreserveAspectFit
                                                    smooth: true
                                                    visible: status === Image.Ready
                                                }
                                            }
                                        }

                                        RowLayout {
                                            id: infoColumns
                                            Layout.fillWidth: true
                                            spacing: 16

                                            Column {
                                                Layout.fillWidth: true
                                                Layout.preferredWidth: 1
                                                Layout.alignment: Qt.AlignTop
                                                spacing: 3

                                                Text { text: qsTr("Connection"); color: ColorPalette.textPrimary; font.pixelSize: 13 * App.fontScale; font.bold: true; bottomPadding: 2 }
                                                Text { text: qsTr("Source: %1").arg(root.safeStr(peerInfoDialog.peerData.source) || "Unknown"); color: ColorPalette.textPrimary; font.pixelSize: 12 * App.fontScale }
                                                Text { text: qsTr("Role: %1").arg(peerInfoDialog.peerData.isSeed ? qsTr("Seeder") : qsTr("Peer")); color: ColorPalette.textPrimary; font.pixelSize: 12 * App.fontScale }
                                                Text { text: qsTr("Ping: %1").arg((Number(peerInfoDialog.peerData.rtt) || 0) > 0 ? (String(peerInfoDialog.peerData.rtt) + " ms") : "--"); color: ColorPalette.textPrimary; font.pixelSize: 12 * App.fontScale }
                                                Text { text: qsTr("Progress: %1%").arg(Math.round(root.clampPct(peerInfoDialog.peerData.progress) * 100)); color: ColorPalette.textPrimary; font.pixelSize: 12 * App.fontScale }
                                            }

                                            Column {
                                                Layout.fillWidth: true
                                                Layout.preferredWidth: 1
                                                Layout.alignment: Qt.AlignTop
                                                spacing: 3

                                                Text { text: qsTr("Transfer"); color: ColorPalette.textPrimary; font.pixelSize: 13 * App.fontScale; font.bold: true; bottomPadding: 2 }
                                                Text { text: qsTr("Down: %1").arg(root.compactSpeed(peerInfoDialog.peerData.downSpeed)); color: ColorPalette.textPrimary; font.pixelSize: 12 * App.fontScale }
                                                Text { text: qsTr("Up: %1").arg(root.compactSpeed(peerInfoDialog.peerData.upSpeed)); color: ColorPalette.textPrimary; font.pixelSize: 12 * App.fontScale }
                                                Text { text: qsTr("Total down: %1").arg(root.compactBytes(peerInfoDialog.peerData.downloaded)); color: ColorPalette.textPrimary; font.pixelSize: 12 * App.fontScale }
                                                Text { text: qsTr("Total up: %1").arg(root.compactBytes(peerInfoDialog.peerData.uploaded)); color: ColorPalette.textPrimary; font.pixelSize: 12 * App.fontScale }
                                            }

                                            Column {
                                                Layout.fillWidth: true
                                                Layout.preferredWidth: 1
                                                Layout.alignment: Qt.AlignTop
                                                spacing: 3

                                                Text { text: qsTr("Location"); color: ColorPalette.textPrimary; font.pixelSize: 13 * App.fontScale; font.bold: true; bottomPadding: 2 }
                                                Text { text: root.peerLocationLabel(peerInfoDialog.peerData.countryCode, peerInfoDialog.peerData.regionName, peerInfoDialog.peerData.cityName); color: ColorPalette.textPrimary; font.pixelSize: 12 * App.fontScale; wrapMode: Text.WordWrap; width: parent.width }
                                                Text { text: qsTr("Distance: %1").arg(root.distanceSummary(peerInfoDialog.peerData.latitude, peerInfoDialog.peerData.longitude)); color: ColorPalette.textPrimary; font.pixelSize: 12 * App.fontScale; wrapMode: Text.WordWrap; width: parent.width }
                                                Text { text: qsTr("Country: %1").arg(root.safeStr(peerInfoDialog.peerData.countryCode) || "--"); color: ColorPalette.textPrimary; font.pixelSize: 12 * App.fontScale }
                                                Text { text: qsTr("Client: %1").arg(root.safeStr(peerInfoDialog.peerData.client) || "Unknown"); color: ColorPalette.clientText; font.pixelSize: 12 * App.fontScale; elide: Text.ElideRight; width: parent.width }
                                            }
                                        }

                                        Rectangle {
                                            Layout.fillWidth: true
                                            Layout.fillHeight: true
                                            Layout.minimumHeight: 170
                                            color: ColorPalette.mapTooltipBg
                                            border.color: ColorPalette.mapBorder
                                            clip: true

                                            // Map label: no background; outline gives contrast against any map color
                                            component MapLabel: Text {
                                                color: ColorPalette.mapLabelText
                                                style: Text.Outline
                                                styleColor: ColorPalette.mapLabelBg
                                                font.pixelSize: 10 * App.fontScale
                                                font.bold: true
                                            }

                                            Item {
                                                anchors.fill: parent
                                                anchors.margins: 6
                                                readonly property real mapHeight: height
                                                readonly property real baseMapWidth: mapHeight * (800.0 / 387.0)
                                                readonly property real baseMapX: (width - baseMapWidth) / 2
                                                readonly property bool hasLocal: !!root.torrentPeerModel && root.torrentPeerModel.hasLocalLocation
                                                readonly property bool hasPeer: root.hasGeoCoordinates(peerInfoDialog.peerData.latitude, peerInfoDialog.peerData.longitude)
                                                readonly property var transformData: root.peerInfoMapTransform(peerInfoDialog.peerData, baseMapWidth, mapHeight)
                                                readonly property real localX: transformData.localX
                                                readonly property real localY: transformData.localY
                                                readonly property real peerX: transformData.peerX
                                                readonly property real peerY: transformData.peerY
                                                // Absolute (un-rotated) endpoints + midpoint of the You<->Peer line
                                                readonly property real absLocalX: baseMapX + localX
                                                readonly property real absPeerX: baseMapX + peerX
                                                readonly property real midX: (absLocalX + absPeerX) / 2
                                                readonly property real midY: (localY + peerY) / 2
                                                readonly property real lineLen: Math.sqrt(Math.pow(absPeerX - absLocalX, 2) + Math.pow(peerY - localY, 2))

                                                Item {
                                                    x: parent.baseMapX + parent.transformData.offsetX
                                                    y: parent.transformData.offsetY
                                                    width: parent.baseMapWidth * parent.transformData.scale
                                                    height: parent.mapHeight * parent.transformData.scale

                                                    Image {
                                                        id: mapImage
                                                        anchors.fill: parent
                                                        source: ColorPalette.dark ? "icons/world-map.svg" : "icons/world-map-light.svg"
                                                        fillMode: Image.Stretch
                                                        smooth: true
                                                        sourceSize.width: 1200
                                                        sourceSize.height: 581
                                                    }
                                                }

                                                Item {
                                                    visible: parent.hasLocal && parent.hasPeer
                                                    readonly property real x1: parent.absLocalX
                                                    readonly property real y1: parent.localY
                                                    readonly property real x2: parent.absPeerX
                                                    readonly property real y2: parent.peerY
                                                    readonly property real dx: x2 - x1
                                                    readonly property real dy: y2 - y1
                                                    readonly property real length: Math.sqrt(dx * dx + dy * dy)

                                                    x: x1
                                                    y: y1
                                                    width: length
                                                    height: 2
                                                    rotation: Math.atan2(dy, dx) * 180 / Math.PI
                                                    transformOrigin: Item.Left

                                                    Rectangle {
                                                        anchors.verticalCenter: parent.verticalCenter
                                                        width: parent.width
                                                        height: 2
                                                        color: "#6db6ff"
                                                    }
                                                }

                                                Rectangle { visible: parent.hasLocal; x: parent.absLocalX - 4; y: parent.localY - 4; width: 8; height: 8; radius: 4; color: "#8a63ff"; border.color: ColorPalette.textHeader; border.width: 1 }
                                                Rectangle { visible: parent.hasPeer; x: parent.absPeerX - 4; y: parent.peerY - 4; width: 8; height: 8; radius: 4; color: peerInfoDialog.peerData.isSeed ? "#67bb7a" : "#62a8ff"; border.color: ColorPalette.textHeader; border.width: 1 }
                                                MapLabel { visible: parent.hasLocal; x: parent.absLocalX + 6; y: parent.localY - 7; text: qsTr("You") }
                                                MapLabel { visible: parent.hasPeer; x: parent.absPeerX + 6; y: parent.peerY - 7; text: qsTr("Peer") }

                                                // Distance at line midpoint; hidden when nodes too close (labels would collide)
                                                MapLabel {
                                                    visible: parent.hasLocal && parent.hasPeer && parent.lineLen > 70 && text.length > 0
                                                    x: parent.midX - implicitWidth / 2
                                                    y: parent.midY - implicitHeight - 5
                                                    text: root.distanceSummary(peerInfoDialog.peerData.latitude, peerInfoDialog.peerData.longitude)
                                                }
                                            }
                                        }

                                        RowLayout {
                                            Layout.fillWidth: true
                                            spacing: 10

                                            RowLayout {
                                                Layout.fillWidth: true
                                                spacing: 6

                                                Text {
                                                    text: qsTr("Flags")
                                                    color: ColorPalette.textPrimary
                                                    font.pixelSize: 11 * App.fontScale
                                                    font.bold: true
                                                    visible: root.peerFlagsList(peerInfoDialog.peerData.flags).length > 0
                                                }

                                                Flow {
                                                    Layout.fillWidth: true
                                                    spacing: 6

                                                    Repeater {
                                                        model: root.peerFlagsList(peerInfoDialog.peerData.flags)
                                                        delegate: Rectangle {
                                                            required property string modelData
                                                            height: 14
                                                            width: badgeLbl.implicitWidth + 6
                                                            radius: 2
                                                            color: "transparent"
                                                            border.color: badgeColor(modelData)
                                                            border.width: 1
                                                            function badgeColor(flag) {
                                                                if (flag === "Seed") return "#c0a54a"
                                                                if (flag === "Peer") return ColorPalette.textSecond
                                                                return root.flagColor(flag)
                                                            }

                                                            ThemedToolTip {
                                                                visible: badgeMouse.containsMouse
                                                                text: {
                                                                    switch (modelData) {
                                                                    case "IN": return "Incoming connection"
                                                                    case "OUT": return "Outgoing connection"
                                                                    case "TRK": return "Discovered via tracker"
                                                                    case "DHT": return "Discovered via DHT"
                                                                    case "PEX": return "Discovered via peer exchange"
                                                                    case "LSD": return "Discovered via local service discovery"
                                                                    case "UTP": return "Using uTP"
                                                                    case "ENC": return "Encrypted connection"
                                                                    case "SNB": return "Peer is snubbed"
                                                                    case "UPO": return "Upload-only peer"
                                                                    case "OPT": return "Optimistically unchoked"
                                                                    case "HPX": return "Holepunched connection"
                                                                    case "I2P": return "I2P transport"
                                                                    default: return modelData
                                                                    }
                                                                }
                                                            }

                                                            Text {
                                                                id: badgeLbl
                                                                anchors.centerIn: parent
                                                                text: modelData
                                                                color: ColorPalette.textPrimary
                                                                font.pixelSize: 9 * App.fontScale
                                                                font.bold: true
                                                            }

                                                            MouseArea {
                                                                id: badgeMouse
                                                                anchors.fill: parent
                                                                hoverEnabled: true
                                                                acceptedButtons: Qt.NoButton
                                                            }
                                                        }
                                                    }
                                                }
                                            }

                                            RowLayout {
                                                spacing: 8
                                                DlgButton {
                                                    text: qsTr("Ban Peer")
                                                    destructive: true
                                                    enabled: !!root.item && root.safeStr(peerInfoDialog.peerData.endpoint).length > 0
                                                    height: 28
                                                    implicitHeight: 28
                                                    Layout.preferredHeight: 28
                                                    Layout.minimumHeight: 28
                                                    Layout.maximumHeight: 28
                                                    Layout.preferredWidth: 84
                                                    Layout.minimumWidth: 84
                                                    Layout.maximumWidth: 84
                                                    onClicked: {
                                                        if (root.item) {
                                                            if (root.torrentPeerModel)
                                                                root.torrentPeerModel.removePeer(peerInfoDialog.peerData.endpoint, peerInfoDialog.peerData.port)
                                                            App.banTorrentPeer(root.item.id,
                                                                               peerInfoDialog.peerData.endpoint,
                                                                               peerInfoDialog.peerData.port,
                                                                               peerInfoDialog.peerData.client,
                                                                               peerInfoDialog.peerData.countryCode)
                                                        }
                                                        peerInfoDialog.close()
                                                    }
                                                }
                                                DlgButton {
                                                    text: qsTr("Close")
                                                    primary: true
                                                    height: 28
                                                    implicitHeight: 28
                                                    Layout.preferredHeight: 28
                                                    Layout.minimumHeight: 28
                                                    Layout.maximumHeight: 28
                                                    Layout.preferredWidth: 84
                                                    Layout.minimumWidth: 84
                                                    Layout.maximumWidth: 84
                                                    onClicked: peerInfoDialog.close()
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            delegate: Rectangle {
                                id: pd
                                required property int    index
                                required property string endpoint
                                required property int    port
                                required property string client
                                required property string countryCode
                                required property string countryFlag
                                required property string regionCode
                                required property string regionName
                                required property string cityName
                                required property real   progress
                                required property int    downSpeed
                                required property int    upSpeed
                                required property var    downloaded
                                required property var    uploaded
                                required property bool   isSeed
                                required property string flags
                                required property real   latitude
                                required property real   longitude
                                required property int    rtt
                                required property string source

                                width: Math.max(peerListView.width, peerListView.contentWidth)
                                height: 26

                                color: peerRowMa.containsMouse
                                       ? ColorPalette.border
                                       : (index % 2 === 0 ? ColorPalette.windowBg : ColorPalette.rowAltBg)

                                MouseArea {
                                    id: peerRowMa; anchors.fill: parent; hoverEnabled: true
                                    acceptedButtons: Qt.LeftButton
                                    ThemedToolTip {
                                        visible: peerRowMa.containsMouse
                                        text: {
                                            var cc = safeStr(pd.countryCode).toUpperCase()
                                            var regionName = safeStr(pd.regionName)
                                            var regionCode = safeStr(pd.regionCode)
                                            var city = safeStr(pd.cityName)
                                            var placeParts = []
                                            if (city) placeParts.push(city)
                                            if (regionCode && (cc === "US" || cc === "CA")) placeParts.push(regionCode)
                                            else if (regionName) placeParts.push(regionName)
                                            var locLine = placeParts.length > 0 ? placeParts.join(", ") : ""
                                            var fullCountry = cc ? countryFullName(cc) : ""
                                            var locBlock = locLine ? locLine + (fullCountry ? "\n" + fullCountry : "") : (fullCountry || "Location unavailable")
                                            var clientLine = safeStr(pd.client) || "Unknown client"
                                            return pd.endpoint + ":" + pd.port + "\n" + locBlock + "\n" + clientLine
                                        }
                                    }
                                }

                                Item {
                                    anchors.fill: parent

                                    Item {
                                        x: root._peerColXMap["country"] || 0
                                        width: root.peerColCountry; height: parent.height; clip: true
                                        Row {
                                            anchors.centerIn: parent
                                            spacing: 4
                                            Image {
                                                width: 20; height: 15
                                                fillMode: Image.PreserveAspectFit; smooth: true; asynchronous: true
                                                source: root.countryFlagSource(pd.countryCode)
                                                visible: status === Image.Ready
                                            }
                                        }
                                    }
                                    Item {
                                        x: root._peerColXMap["endpoint"] || 0
                                        width: root.peerColPeer; height: parent.height; clip: true
                                        Text {
                                            anchors { fill: parent; leftMargin: 6 }
                                            verticalAlignment: Text.AlignVCenter
                                            text: safeStr(pd.endpoint); color: ColorPalette.textPrimary; font.pixelSize: 12 * App.fontScale; elide: Text.ElideRight
                                        }
                                    }
                                    Item {
                                        x: root._peerColXMap["port"] || 0
                                        width: root.peerColPort; height: parent.height; clip: true
                                        Text {
                                            anchors { fill: parent; leftMargin: 6 }
                                            verticalAlignment: Text.AlignVCenter
                                            text: pd.port > 0 ? String(pd.port) : ""
                                            color: ColorPalette.textPrimary; font.pixelSize: 12 * App.fontScale; elide: Text.ElideRight
                                        }
                                    }
                                    Item {
                                        x: root._peerColXMap["client"] || 0
                                        width: root.peerColClient; height: parent.height; clip: true
                                        Item {
                                            anchors { fill: parent; leftMargin: 6; rightMargin: 6 }
                                            Image {
                                                id: clientIcon
                                                anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                                                width: 16; height: 16
                                                fillMode: Image.PreserveAspectFit; smooth: true; asynchronous: true
                                                source: root.torrentClientIconSource(pd.client)
                                                visible: status === Image.Ready
                                            }
                                            Text {
                                                anchors {
                                                    left: clientIcon.visible ? clientIcon.right : parent.left
                                                    leftMargin: clientIcon.visible ? 6 : 0
                                                    right: parent.right; verticalCenter: parent.verticalCenter
                                                }
                                                text: pd.client; color: ColorPalette.textPrimary; font.pixelSize: 12 * App.fontScale; elide: Text.ElideRight
                                            }
                                        }
                                    }
                                    Item {
                                        x: root._peerColXMap["progress"] || 0
                                        width: root.peerColProgress; height: parent.height; clip: true
                                        Text {
                                            anchors { fill: parent; leftMargin: 6 }
                                            verticalAlignment: Text.AlignVCenter
                                            text: Math.round(root.clampPct(pd.progress) * 100) + "%"
                                            color: ColorPalette.textPrimary; font.pixelSize: 12 * App.fontScale
                                        }
                                    }
                                    Item {
                                        x: root._peerColXMap["down"] || 0
                                        width: root.peerColDown; height: parent.height; clip: true
                                        Text {
                                            anchors { fill: parent; leftMargin: 6 }
                                            verticalAlignment: Text.AlignVCenter
                                            text: root.compactSpeed(pd.downSpeed); color: ColorPalette.textHeader; font.pixelSize: 12 * App.fontScale
                                        }
                                    }
                                    Item {
                                        x: root._peerColXMap["up"] || 0
                                        width: root.peerColUp; height: parent.height; clip: true
                                        Text {
                                            anchors { fill: parent; leftMargin: 6 }
                                            verticalAlignment: Text.AlignVCenter
                                            text: root.compactSpeed(pd.upSpeed); color: ColorPalette.textHeader; font.pixelSize: 12 * App.fontScale
                                        }
                                    }
                                    Item {
                                        x: root._peerColXMap["downloaded"] || 0
                                        width: root.peerColDownloaded; height: parent.height; clip: true
                                        Text {
                                            anchors { fill: parent; leftMargin: 6 }
                                            verticalAlignment: Text.AlignVCenter
                                            text: root.compactBytes(pd.downloaded); color: ColorPalette.textPrimary; font.pixelSize: 12 * App.fontScale
                                        }
                                    }
                                    Item {
                                        x: root._peerColXMap["uploaded"] || 0
                                        width: root.peerColUploaded; height: parent.height; clip: true
                                        Text {
                                            anchors { fill: parent; leftMargin: 6 }
                                            verticalAlignment: Text.AlignVCenter
                                            text: root.compactBytes(pd.uploaded); color: ColorPalette.textPrimary; font.pixelSize: 12 * App.fontScale
                                        }
                                    }
                                    Item {
                                        x: root._peerColXMap["type"] || 0
                                        width: root.peerColType; height: parent.height; clip: true
                                        Row {
                                            anchors { left: parent.left; leftMargin: 4; verticalCenter: parent.verticalCenter }
                                            spacing: 2
                                            Repeater {
                                                model: pd.flags ? pd.flags.split(" ").filter(function(f){ return f.length > 0 }) : []
                                                delegate: Rectangle {
                                                    required property string modelData
                                                    height: 14; width: badgeLbl.implicitWidth + 6
                                                    radius: 2; color: "transparent"
                                                    border.color: flagBadgeColor(modelData); border.width: 1
                                                    function flagBadgeColor(flag) {
                                                        if (flag === "Seed") return "#c0a54a"
                                                        if (flag === "Peer") return ColorPalette.textSecond
                                                        return root.flagColor(flag)
                                                    }
                                                    Text {
                                                        id: badgeLbl
                                                        anchors.centerIn: parent
                                                        text: modelData; color: ColorPalette.textPrimary
                                                        font.pixelSize: 9 * App.fontScale; font.bold: true
                                                    }
                                                    HoverHandler { id: badgeHover }
                                                    ThemedToolTip {
                                                        visible: badgeHover.hovered
                                                        text: root.flagTip(modelData)
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }

                                // Match the working file-list pattern: keep the context-menu
                                // MouseArea on the topmost row layer so it receives right-clicks.
                                MouseArea {
                                    anchors.fill: parent
                                    acceptedButtons: Qt.RightButton
                                    onClicked: function(mouse) {
                                        if (mouse.button !== Qt.RightButton)
                                            return
                                        peerCtxMenu.endpoint = pd.endpoint
                                        peerCtxMenu.port = pd.port
                                        peerCtxMenu.client = pd.client
                                        peerCtxMenu.countryCode = pd.countryCode
                                        peerCtxMenu.peerData = {
                                            endpoint: pd.endpoint,
                                            port: pd.port,
                                            client: pd.client,
                                            countryCode: pd.countryCode,
                                            countryFlag: pd.countryFlag,
                                            regionCode: pd.regionCode,
                                            regionName: pd.regionName,
                                            cityName: pd.cityName,
                                            progress: pd.progress,
                                            downSpeed: pd.downSpeed,
                                            upSpeed: pd.upSpeed,
                                            downloaded: pd.downloaded,
                                            uploaded: pd.uploaded,
                                            isSeed: pd.isSeed,
                                            flags: pd.flags,
                                            latitude: pd.latitude,
                                            longitude: pd.longitude,
                                            rtt: pd.rtt,
                                            source: pd.source
                                        }
                                        var pos = mapToItem(Overlay.overlay, mouse.x, mouse.y)
                                        peerCtxMenu.x = pos.x
                                        peerCtxMenu.y = pos.y
                                        peerCtxMenu.open()
                                    }
                                }
                            }
                        }

                        // Flags legend
                        Row {
                            Layout.fillWidth: true
                            Layout.topMargin: 2
                            Layout.bottomMargin: 2
                            Layout.leftMargin: 10
                            spacing: 6

                            Text {
                                text: qsTr("Legend:")
                                color: ColorPalette.textHeader
                                font.pixelSize: 10 * App.fontScale
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            Repeater {
                                model: ["IN", "OUT", "TRK", "DHT", "PEX", "LSD", "UTP", "ENC", "SNB", "UPO", "OPT", "HPX"]
                                delegate: Rectangle {
                                    required property string modelData
                                    height: 14
                                    width: lgText.implicitWidth + 6
                                    radius: 2
                                    color: "transparent"
                                    border.color: root.flagColor(modelData)
                                    border.width: 1
                                    anchors.verticalCenter: parent.verticalCenter

                                    Text {
                                        id: lgText
                                        anchors.centerIn: parent
                                        text: modelData
                                        color: ColorPalette.textPrimary
                                        font.pixelSize: 9 * App.fontScale
                                        font.bold: true
                                    }

                                    HoverHandler { id: lgHover }
                                    ThemedToolTip {
                                        visible: lgHover.hovered
                                        text: root.flagTip(modelData)
                                    }
                                }
                            }
                        }
                    }
                }

                // ?? Peer Map ????????????????????????????????????????????????
                Item {
                    Rectangle {
                        anchors.fill: parent
                        color: ColorPalette.mapCanvasBg
                        border.width: 0
                        radius: 3

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 6
                            spacing: 8

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 12

                                Text {
                                    text: root.activePeerMapModel
                                        ? qsTr("%1 known peers").arg(root.activePeerMapModel.count)
                                        : qsTr("0 known peers")
                                    color: ColorPalette.textPrimary
                                    font.pixelSize: 11 * App.fontScale
                                }
                                Item { Layout.fillWidth: true }

                                // Inactive peers toggle
                                Row {
                                    Layout.alignment: Qt.AlignVCenter
                                    spacing: 5
                                    StyledCheckBox {
                                        id: inactiveCheck
                                        checked: root.peerMapShowInactive
                                        onCheckedChanged: App.settings.swarmMapShowInactive = checked
                                        implicitHeight: 20
                                        indicator: Rectangle {
                                            width: 14; height: 14; radius: 2
                                            color: inactiveCheck.checked ? "#4488dd" : ColorPalette.inputBg
                                            border.color: inactiveCheck.checked ? "#4488dd" : ColorPalette.border
                                            Text { visible: inactiveCheck.checked; text: "✓"; color: ColorPalette.textPrimary; font.pixelSize: 10 * App.fontScale; anchors.centerIn: parent }
                                        }
                                        contentItem: Item {}
                                    }
                                    Text { text: qsTr("Inactive"); color: ColorPalette.textPrimary; font.pixelSize: 11 * App.fontScale }
                                }

                                // Tracker dots toggle
                                Row {
                                    Layout.alignment: Qt.AlignVCenter
                                    spacing: 5
                                    StyledCheckBox {
                                        id: trackerDotsCheck
                                        checked: root.peerMapShowTrackers
                                        onCheckedChanged: App.settings.swarmMapShowTrackers = checked
                                        implicitHeight: 20
                                        indicator: Rectangle {
                                            width: 14; height: 14; radius: 2
                                            color: trackerDotsCheck.checked ? "#4488dd" : ColorPalette.inputBg
                                            border.color: trackerDotsCheck.checked ? "#4488dd" : ColorPalette.border
                                            Text { visible: trackerDotsCheck.checked; text: "✓"; color: ColorPalette.textPrimary; font.pixelSize: 10 * App.fontScale; anchors.centerIn: parent }
                                        }
                                        contentItem: Item {}
                                    }
                                    Text { text: qsTr("Trackers"); color: ColorPalette.textPrimary; font.pixelSize: 11 * App.fontScale }
                                }

                                Rectangle {
                                    color: ColorPalette.mapPanelBg
                                    border.color: "transparent"
                                    radius: 2
                                    implicitHeight: 24
                                    implicitWidth: legendRow.implicitWidth + 16
                                    Row {
                                        id: legendRow
                                        anchors.centerIn: parent
                                        spacing: 10
                                        Rectangle { width: 10; height: 10; radius: 5; color: "#5f93c9"; anchors.verticalCenter: parent.verticalCenter }
                                        Text { text: qsTr("Peer"); color: ColorPalette.textPrimary; font.pixelSize: 11 * App.fontScale; anchors.verticalCenter: parent.verticalCenter }
                                        Rectangle { width: 10; height: 10; radius: 5; color: "#4caf7d"; anchors.verticalCenter: parent.verticalCenter }
                                        Text { text: qsTr("Seed"); color: ColorPalette.textPrimary; font.pixelSize: 11 * App.fontScale; anchors.verticalCenter: parent.verticalCenter }
                                        Rectangle { width: 10; height: 10; radius: 5; color: "#9959e6"; anchors.verticalCenter: parent.verticalCenter }
                                        Text { text: qsTr("You"); color: ColorPalette.textPrimary; font.pixelSize: 11 * App.fontScale; anchors.verticalCenter: parent.verticalCenter }
                                        Rectangle { width: 8; height: 8; radius: 4; color: "#e8d57a"; anchors.verticalCenter: parent.verticalCenter }
                                        Text { text: qsTr("Tracker"); color: ColorPalette.textPrimary; font.pixelSize: 11 * App.fontScale; anchors.verticalCenter: parent.verticalCenter }
                                        // Line type legend
                                        Rectangle { width: 18; height: 2; color: "#5f93c9"; anchors.verticalCenter: parent.verticalCenter }
                                        Text { text: qsTr("DL"); color: ColorPalette.textPrimary; font.pixelSize: 11 * App.fontScale; anchors.verticalCenter: parent.verticalCenter }
                                        Rectangle { width: 18; height: 2; color: "#4caf7d"; anchors.verticalCenter: parent.verticalCenter }
                                        Text { text: qsTr("UL"); color: ColorPalette.textPrimary; font.pixelSize: 11 * App.fontScale; anchors.verticalCenter: parent.verticalCenter }
                                        Rectangle { width: 18; height: 2; color: "#9959e6"; anchors.verticalCenter: parent.verticalCenter }
                                        Text { text: qsTr("Both"); color: ColorPalette.textPrimary; font.pixelSize: 11 * App.fontScale; anchors.verticalCenter: parent.verticalCenter }
                                    }
                                }
                            }

                            Rectangle {
                                id: peerMapFrame
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                color: ColorPalette.mapCanvasBg
                                radius: 3
                                clip: true

                                Item {
                                    id: mapRoot
                                    anchors.fill: parent
                                    anchors.margins: 8
                                    clip: true

                                    Item {
                                        id: mapCanvas
                                        x: root.peerMapPanX
                                        y: root.peerMapPanY
                                        width: mapRoot.width
                                        height: mapRoot.height
                                        scale: root.peerMapZoom
                                        transformOrigin: Item.TopLeft

                                        readonly property real mapX: worldMapImage.x + (worldMapImage.width - worldMapImage.paintedWidth) / 2
                                        readonly property real mapY: worldMapImage.y + (worldMapImage.height - worldMapImage.paintedHeight) / 2
                                        readonly property real mapWidth: worldMapImage.paintedWidth
                                        readonly property real mapHeight: worldMapImage.paintedHeight

                                        Image {
                                            id: worldMapImage
                                            anchors.fill: parent
                                            source: ColorPalette.dark ? "icons/world-map.svg" : "icons/world-map-light.svg"
                                            fillMode: Image.PreserveAspectFit
                                            smooth: true
                                            sourceSize.width: 2400
                                            sourceSize.height: 1161
                                        }

                                    Repeater {
                                        id: peerLineRepeater
                                        model: root.activePeerMapModel
                                        delegate: Item {
                                            required property double latitude
                                            required property double longitude
                                            required property bool isSeed
                                            required property int downSpeed
                                            required property int upSpeed

                                            readonly property bool hasCoordinates: isFinite(latitude) && isFinite(longitude) && !(latitude === 0 && longitude === 0)
                                            readonly property bool hasLocalCoordinates: !!root.activePeerMapModel && root.activePeerMapModel.hasLocalLocation
                                            readonly property real hubX: mapCanvas.mapX + root.peerMapX(root.activePeerMapModel ? root.activePeerMapModel.localLongitude : 0, mapCanvas.mapWidth)
                                            readonly property real hubY: mapCanvas.mapY + root.peerMapY(root.activePeerMapModel ? root.activePeerMapModel.localLatitude : 0, mapCanvas.mapWidth, mapCanvas.mapHeight)
                                            readonly property real targetX: mapCanvas.mapX + root.peerMapX(longitude, mapCanvas.mapWidth)
                                            readonly property real targetY: mapCanvas.mapY + root.peerMapY(latitude, mapCanvas.mapWidth, mapCanvas.mapHeight)
                                            readonly property real dx: targetX - hubX
                                            readonly property real dy: targetY - hubY
                                            readonly property real length: Math.sqrt(dx * dx + dy * dy)

                                            visible: hasCoordinates && hasLocalCoordinates && root.peerTraffic(this) > 0
                                            x: hubX
                                            y: hubY
                                            width: length
                                            height: root.peerLineWidth(this)
                                            rotation: Math.atan2(dy, dx) * 180 / Math.PI
                                            transformOrigin: Item.Left

                                            Rectangle {
                                                anchors.verticalCenter: parent.verticalCenter
                                                width: parent.width
                                                height: parent.height
                                                radius: height / 2
                                                color: root.peerMapLineColor(parent)
                                            }
                                        }
                                    }

                                    property int plottedPeerCount: 0

                                    Repeater {
                                        id: peerMarkerRepeater
                                        model: root.activePeerMapModel
                                        delegate: Item {
                                            required property string endpoint
                                            required property int port
                                            required property string client
                                            required property string countryCode
                                            required property string regionCode
                                            required property string regionName
                                            required property string cityName
                                            required property double latitude
                                            required property double longitude
                                            required property int rtt
                                            required property int downSpeed
                                            required property int upSpeed
                                            required property bool isSeed
                                            required property string source
                                            required property string flags
                                            required property double progress   // fraction 0-1; was missing, causing all peers to show 0%

                                            readonly property bool hasCoordinates: isFinite(latitude) && isFinite(longitude) && !(latitude === 0 && longitude === 0)
                                            readonly property bool isActive: downSpeed > 0 || upSpeed > 0
                                            visible: hasCoordinates && (root.peerMapShowInactive || isActive)
                                            Component.onCompleted: { if (hasCoordinates) mapCanvas.plottedPeerCount++ }
                                            onHasCoordinatesChanged: { mapCanvas.plottedPeerCount += hasCoordinates ? 1 : -1 }
                                            Component.onDestruction: { if (hasCoordinates) mapCanvas.plottedPeerCount-- }
                                            x: mapCanvas.mapX + root.peerMapX(longitude, mapCanvas.mapWidth) - width / 2
                                            y: mapCanvas.mapY + root.peerMapY(latitude, mapCanvas.mapWidth, mapCanvas.mapHeight) - height / 2
                                            width: 16
                                            height: 16
                                            scale: 1.0 / root.peerMapZoom
                                            transformOrigin: Item.Center

                                            Rectangle {
                                                anchors.centerIn: parent
                                                width: 10
                                                height: 10
                                                radius: 5
                                                color: root.peerMapColor(parent)
                                                border.color: markerMouse.containsMouse ? ColorPalette.textPrimary : ColorPalette.mapBorder
                                                border.width: 1
                                            }

                                            Rectangle {
                                                visible: false
                                                anchors.bottom: parent.top
                                                anchors.horizontalCenter: parent.horizontalCenter
                                                anchors.bottomMargin: 6
                                                width: 220
                                                implicitHeight: tooltipCol.implicitHeight + 10
                                                color: ColorPalette.mapTooltipBg
                                                border.color: ColorPalette.mapBorder
                                                radius: 3
                                                z: 10

                                                Column {
                                                    id: tooltipCol
                                                    anchors.fill: parent
                                                    anchors.margins: 5
                                                    spacing: 2

                                                    Text { text: endpoint + ":" + port; color: ColorPalette.textPrimary; font.pixelSize: 11 * App.fontScale; font.bold: true; elide: Text.ElideRight; width: parent.width }
                                                    Text { text: client; color: ColorPalette.textPrimary; font.pixelSize: 11 * App.fontScale; elide: Text.ElideRight; width: parent.width }
                                                    Text { text: root.peerPlaceText(parent.parent); color: ColorPalette.textPrimary; font.pixelSize: 10 * App.fontScale; elide: Text.ElideRight; width: parent.width }
                                                    Text { text: (isSeed ? qsTr("Seed") : qsTr("Peer")) + " . " + source; color: isSeed ? "#f6b84c" : "#56d27f"; font.pixelSize: 10 * App.fontScale; width: parent.width }
                                                    Text { text: qsTr("Down %1  Up %2").arg(root.compactSpeed(downSpeed)).arg(root.compactSpeed(upSpeed)); color: ColorPalette.textPrimary; font.pixelSize: 10 * App.fontScale; width: parent.width }
                                                    Text { text: qsTr("RTT %1").arg(rtt > 0 ? (rtt + " ms") : "--"); color: ColorPalette.textPrimary; font.pixelSize: 10 * App.fontScale; width: parent.width }
                                                }
                                            }

                                            MouseArea {
                                                id: markerMouse
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                acceptedButtons: Qt.NoButton
                                                onEntered: {
                                                    var p = parent.mapToItem(mapRoot, parent.width / 2, 0)
                                                    root.showPeerMapHover(parent, p.x, p.y)
                                                }
                                                onPositionChanged: {
                                                    var p = parent.mapToItem(mapRoot, parent.width / 2, 0)
                                                    root.showPeerMapHover(parent, p.x, p.y)
                                                }
                                                onExited: root.hidePeerMapHover()
                                            }
                                        }
                                    }

                                    // Tracker dots
                                    Repeater {
                                        model: root.activeTrackerMapModel
                                        delegate: Item {
                                            required property double latitude
                                            required property double longitude
                                            required property string url
                                            required property string countryCode
                                            required property bool isSystemEntry
                                            required property string status
                                            required property int count
                                            required property int tier

                                            readonly property bool hasCoordinates: !isSystemEntry && isFinite(latitude) && isFinite(longitude) && !(latitude === 0 && longitude === 0)
                                            visible: hasCoordinates
                                            x: mapCanvas.mapX + root.peerMapX(longitude, mapCanvas.mapWidth) - width / 2
                                            y: mapCanvas.mapY + root.peerMapY(latitude, mapCanvas.mapWidth, mapCanvas.mapHeight) - height / 2
                                            width: 14; height: 14
                                            scale: 1.0 / root.peerMapZoom
                                            transformOrigin: Item.Center

                                            Rectangle {
                                                anchors.centerIn: parent
                                                width: 8; height: 8; radius: 4
                                                color: "#e8d57a"
                                                border.color: ColorPalette.mapBorder; border.width: 1
                                            }
                                            MouseArea {
                                                id: trackerDotMouse
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                acceptedButtons: Qt.NoButton
                                                onEntered: {
                                                    var host = url.replace(/^(udp|http|https):\/\//, "").replace(/\/.*$/, "")
                                                    root.peerMapTrackerHoverHost = host
                                                    root.peerMapTrackerHoverCountry = countryCode
                                                    root.peerMapTrackerHoverStatus = status
                                                    root.peerMapTrackerHoverTier = tier
                                                    root.peerMapTrackerHoverCount = count
                                                    root.peerMapTrackerHoverUrl = url
                                                    var dotX = mapCanvas.x + (mapCanvas.mapX + root.peerMapX(longitude, mapCanvas.mapWidth) - width/2) * root.peerMapZoom
                                                    var dotY = mapCanvas.y + (mapCanvas.mapY + root.peerMapY(latitude, mapCanvas.mapWidth, mapCanvas.mapHeight) - height/2) * root.peerMapZoom
                                                    root.peerMapTrackerHoverX = dotX
                                                    root.peerMapTrackerHoverY = dotY
                                                    root.peerMapTrackerHoverVisible = true
                                                }
                                                onExited: root.peerMapTrackerHoverVisible = false
                                            }
                                        }
                                    }

                                    Item {
                                        id: youDot
                                        visible: !!root.activePeerMapModel && root.activePeerMapModel.hasLocalLocation
                                        x: mapCanvas.mapX + root.peerMapX(root.activePeerMapModel ? root.activePeerMapModel.localLongitude : 0, mapCanvas.mapWidth) - width / 2
                                        y: mapCanvas.mapY + root.peerMapY(root.activePeerMapModel ? root.activePeerMapModel.localLatitude : 0, mapCanvas.mapWidth, mapCanvas.mapHeight) - height / 2
                                        width: 16
                                        height: 16
                                        scale: 1.0 / root.peerMapZoom
                                        transformOrigin: Item.Center

                                        Rectangle {
                                            anchors.centerIn: parent
                                            width: 10
                                            height: 10
                                            radius: 5
                                            color: "#9959e6"
                                            border.color: ColorPalette.mapBorder
                                            border.width: 1
                                        }

                                        MouseArea {
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            acceptedButtons: Qt.NoButton
                                            onEntered: root.peerMapYouHoverVisible = true
                                            onExited:  root.peerMapYouHoverVisible = false
                                        }
                                    }

                                    }

                                    Rectangle {
                                        visible: root.peerMapHoverVisible
                                        x: Math.max(10, Math.min(parent.width - width - 10, root.peerMapHoverX + 14))
                                        y: Math.max(10, Math.min(parent.height - height - 10, root.peerMapHoverY - height / 2))
                                        width: 200
                                        implicitHeight: mapTooltipCol.implicitHeight + 10
                                        color: ColorPalette.mapTooltipBg
                                        border.color: ColorPalette.mapBorder
                                        radius: 4
                                        z: 20

                                        Column {
                                            id: mapTooltipCol
                                            anchors.fill: parent
                                            anchors.margins: 7
                                            spacing: 4

                                            // IP  Port row
                                            Row {
                                                spacing: 5
                                                width: parent.width
                                                Text {
                                                    text: root.peerMapHoverEndpoint
                                                    color: ColorPalette.textPrimary
                                                    font.pixelSize: 13 * App.fontScale
                                                    font.bold: true
                                                    elide: Text.ElideRight
                                                    width: Math.min(implicitWidth, parent.width - portLbl.width - 5)
                                                }
                                                Text {
                                                    id: portLbl
                                                    text: root.peerMapHoverPort
                                                    color: ColorPalette.textSecond
                                                    font.pixelSize: 13 * App.fontScale
                                                    font.bold: true
                                                    anchors.baseline: parent.children[0].baseline
                                                }
                                            }

                                            // Client icon + name row
                                            Row {
                                                spacing: 5
                                                width: parent.width
                                                visible: root.peerMapHoverClient.length > 0
                                                Image {
                                                    source: root.torrentClientIconSource(root.baseClientName(root.peerMapHoverClient))
                                                    width: 14; height: 14
                                                    fillMode: Image.PreserveAspectFit
                                                    smooth: true
                                                    visible: source !== ""
                                                    anchors.verticalCenter: parent.verticalCenter
                                                }
                                                Text {
                                                    text: root.peerMapHoverClient
                                                    color: ColorPalette.textPrimary
                                                    font.pixelSize: 12 * App.fontScale
                                                    elide: Text.ElideRight
                                                    width: parent.width - (parent.children[0].visible ? 19 : 0)
                                                    anchors.verticalCenter: parent.verticalCenter
                                                }
                                            }

                                            // Flag + location row
                                            Row {
                                                spacing: 5
                                                width: parent.width
                                                visible: root.peerMapHoverCountryCode.length > 0
                                                Image {
                                                    source: root.countryFlagSource(root.peerMapHoverCountryCode)
                                                    width: 16; height: 11
                                                    fillMode: Image.PreserveAspectFit
                                                    smooth: true
                                                    anchors.verticalCenter: parent.verticalCenter
                                                }
                                                Text {
                                                    text: root.peerPlaceText({
                                                        countryCode: root.peerMapHoverCountryCode,
                                                        regionCode: root.peerMapHoverRegionCode,
                                                        regionName: root.peerMapHoverRegionName,
                                                        cityName: root.peerMapHoverCityName
                                                    })
                                                    color: ColorPalette.textPrimary
                                                    font.pixelSize: 11 * App.fontScale
                                                    elide: Text.ElideRight
                                                    width: parent.width - 21
                                                    anchors.verticalCenter: parent.verticalCenter
                                                }
                                            }

                                            // Flags row
                                            Flow {
                                                width: parent.width
                                                spacing: 2
                                                Repeater {
                                                    model: root.peerMapHoverFlags
                                                        ? root.peerMapHoverFlags.split(" ").filter(function(f){ return f.length > 0 })
                                                        : []
                                                    delegate: Rectangle {
                                                        required property string modelData
                                                        height: 14
                                                        width: mapBadgeLbl.implicitWidth + 6
                                                        radius: 2
                                                        color: "transparent"
                                                        border.color: mapFlagColor(modelData)
                                                        border.width: 1

                                                        function mapFlagColor(flag) {
                                                            if (flag === "Seed") return "#c0a54a"
                                                            if (flag === "Peer") return ColorPalette.textSecond
                                                            return root.flagColor(flag)
                                                        }

                                                        Text {
                                                            id: mapBadgeLbl
                                                            anchors.centerIn: parent
                                                            text: modelData
                                                            color: ColorPalette.textPrimary
                                                            font.pixelSize: 9 * App.fontScale
                                                            font.bold: true
                                                        }
                                                    }
                                                }
                                            }

                                            // Speed row
                                            Text {
                                                text: qsTr("↓ %1  ↑ %2").arg(root.compactSpeed(root.peerMapHoverDownSpeed)).arg(root.compactSpeed(root.peerMapHoverUpSpeed))
                                                color: ColorPalette.textPrimary
                                                font.pixelSize: 11 * App.fontScale
                                                width: parent.width
                                            }

                                            // Ping + progress row
                                            Text {
                                                text: qsTr("Ping %1  %2% done").arg(root.peerMapHoverRtt > 0 ? (root.peerMapHoverRtt + " ms") : "-").arg(Math.round(root.peerMapHoverProgress * 100))
                                                color: ColorPalette.textPrimary
                                                font.pixelSize: 11 * App.fontScale
                                                width: parent.width
                                            }
                                        }
                                    }

                                    // Tracker hover tooltip
                                    Rectangle {
                                        visible: root.peerMapTrackerHoverVisible
                                        x: Math.max(10, Math.min(parent.width - width - 10, root.peerMapTrackerHoverX + 14))
                                        y: Math.max(10, Math.min(parent.height - height - 10, root.peerMapTrackerHoverY - height / 2))
                                        width: 210
                                        implicitHeight: trackerTipCol.implicitHeight + 10
                                        color: ColorPalette.mapPanelBg
                                        border.color: ColorPalette.mapBorder
                                        radius: 4
                                        z: 22

                                        Column {
                                            id: trackerTipCol
                                            anchors.fill: parent
                                            anchors.margins: 7
                                            spacing: 4

                                            // Host row
                                            Row {
                                                spacing: 6
                                                width: parent.width
                                                Rectangle {
                                                    width: 8; height: 8; radius: 4
                                                    color: "#e8d57a"
                                                    anchors.verticalCenter: parent.verticalCenter
                                                }
                                                Text {
                                                    text: root.peerMapTrackerHoverHost
                                                    color: ColorPalette.textPrimary
                                                    font.pixelSize: 13 * App.fontScale
                                                    font.bold: true
                                                    elide: Text.ElideRight
                                                    width: parent.width - 14
                                                }
                                            }

                                            // Country
                                            Text {
                                                visible: root.peerMapTrackerHoverCountry.length > 0
                                                text: root.peerMapTrackerHoverCountry
                                                color: ColorPalette.textPrimary
                                                font.pixelSize: 11 * App.fontScale
                                                width: parent.width
                                            }

                                            // Divider
                                            Rectangle { width: parent.width; height: 1; color: ColorPalette.mapGrid }

                                            // Status
                                            Row {
                                                spacing: 4
                                                Text { text: qsTr("Status"); color: ColorPalette.textSecond; font.pixelSize: 11 * App.fontScale }
                                                Text {
                                                    text: root.peerMapTrackerHoverStatus || qsTr("Unknown")
                                                    color: {
                                                        var s = root.peerMapTrackerHoverStatus.toLowerCase()
                                                        if (s === "working") return "#4caf7d"
                                                        if (s === "not contacted") return "#888"
                                                        return "#e8a35c"
                                                    }
                                                    font.pixelSize: 11 * App.fontScale
                                                    font.bold: true
                                                }
                                            }

                                            // Tier
                                            Row {
                                                visible: root.peerMapTrackerHoverTier >= 0
                                                spacing: 4
                                                Text { text: qsTr("Tier"); color: ColorPalette.textSecond; font.pixelSize: 11 * App.fontScale }
                                                Text { text: String(root.peerMapTrackerHoverTier); color: ColorPalette.textPrimary; font.pixelSize: 11 * App.fontScale }
                                            }

                                            // Peers reported
                                            Row {
                                                spacing: 4
                                                Text { text: qsTr("Peers"); color: ColorPalette.textSecond; font.pixelSize: 11 * App.fontScale }
                                                Text {
                                                    text: root.peerMapTrackerHoverCount > 0 ? String(root.peerMapTrackerHoverCount) : "-"
                                                    color: ColorPalette.textPrimary; font.pixelSize: 11 * App.fontScale
                                                }
                                            }
                                        }
                                    }

                                    // "You" hover tooltip
                                    Rectangle {
                                        visible: root.peerMapYouHoverVisible && !!root.torrentPeerModel && root.torrentPeerModel.hasLocalLocation
                                        x: {
                                            if (!root.torrentPeerModel) return 0
                                            var dotX = mapCanvas.x + (mapCanvas.mapX + root.peerMapX(root.torrentPeerModel.localLongitude, mapCanvas.mapWidth)) * root.peerMapZoom
                                            return Math.max(10, Math.min(parent.width - width - 10, dotX + 14))
                                        }
                                        y: {
                                            if (!root.torrentPeerModel) return 0
                                            var dotY = mapCanvas.y + (mapCanvas.mapY + root.peerMapY(root.torrentPeerModel.localLatitude, mapCanvas.mapWidth, mapCanvas.mapHeight)) * root.peerMapZoom
                                            return Math.max(10, Math.min(parent.height - height - 10, dotY - height / 2))
                                        }
                                        width: 200
                                        implicitHeight: youTooltipCol.implicitHeight + 10
                                        color: ColorPalette.mapPanelBg
                                        border.color: ColorPalette.mapBorder
                                        radius: 4
                                        z: 21

                                        Column {
                                            id: youTooltipCol
                                            anchors.fill: parent
                                            anchors.margins: 7
                                            spacing: 4

                                            Row {
                                                spacing: 5
                                                width: parent.width
                                                Text {
                                                    text: root.torrentPeerModel ? root.torrentPeerModel.localIp : ""
                                                    color: ColorPalette.textPrimary
                                                    font.pixelSize: 13 * App.fontScale
                                                    font.bold: true
                                                    elide: Text.ElideRight
                                                    width: Math.min(implicitWidth, parent.width - youPortLbl.width - 5)
                                                }
                                                Text {
                                                    id: youPortLbl
                                                    text: root.torrentPeerModel ? root.torrentPeerModel.localPort : ""
                                                    color: ColorPalette.textSecond
                                                    font.pixelSize: 13 * App.fontScale
                                                    font.bold: true
                                                    visible: root.torrentPeerModel && root.torrentPeerModel.localPort > 0
                                                }
                                            }

                                            Row {
                                                spacing: 5
                                                width: parent.width
                                                Image {
                                                    source: "icons/milky-way.png"
                                                    width: 14; height: 14
                                                    fillMode: Image.PreserveAspectFit
                                                    smooth: true
                                                    anchors.verticalCenter: parent.verticalCenter
                                                }
                                                Text {
                                                    text: root.torrentPeerModel && root.torrentPeerModel.localClientName.length > 0
                                                          ? root.torrentPeerModel.localClientName
                                                          : ("Stellar/" + App.appVersion)
                                                    color: ColorPalette.textPrimary
                                                    font.pixelSize: 12 * App.fontScale
                                                    anchors.verticalCenter: parent.verticalCenter
                                                }
                                            }

                                            Row {
                                                spacing: 5
                                                width: parent.width
                                                visible: !!root.torrentPeerModel && root.torrentPeerModel.localCountryCode.length > 0
                                                Image {
                                                    source: root.torrentPeerModel ? root.countryFlagSource(root.torrentPeerModel.localCountryCode) : ""
                                                    width: 16; height: 11
                                                    fillMode: Image.PreserveAspectFit
                                                    smooth: true
                                                    anchors.verticalCenter: parent.verticalCenter
                                                }
                                                Text {
                                                    text: {
                                                        if (!root.torrentPeerModel)
                                                            return ""
                                                        var parts = []
                                                        var city = root.torrentPeerModel.localCityName
                                                        var region = root.torrentPeerModel.localRegionName
                                                        var country = root.torrentPeerModel.localCountryCode
                                                        if (city && city.length > 0)
                                                            parts.push(city)
                                                        if (region && region.length > 0)
                                                            parts.push(region)
                                                        if (country && country.length > 0)
                                                            parts.push(country)
                                                        return parts.join(", ")
                                                    }
                                                    color: ColorPalette.textPrimary
                                                    font.pixelSize: 11 * App.fontScale
                                                    elide: Text.ElideRight
                                                    width: parent.width - 21
                                                    anchors.verticalCenter: parent.verticalCenter
                                                }
                                            }

                                            Text {
                                                text: qsTr("You (this client)")
                                                color: "#66a7ff"
                                                font.pixelSize: 11 * App.fontScale
                                                width: parent.width
                                            }
                                            Text {
                                                visible: !!root.item
                                                text: Math.round((root.item ? root.item.progress : 0) * 100) + "% done"
                                                color: ColorPalette.textPrimary
                                                font.pixelSize: 11 * App.fontScale
                                                width: parent.width
                                            }
                                        }
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        acceptedButtons: Qt.LeftButton
                                        cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                                        property real lastX: 0
                                        property real lastY: 0
                                        onPressed: function(mouse) {
                                            lastX = mouse.x
                                            lastY = mouse.y
                                        }
                                        onPositionChanged: function(mouse) {
                                            if (!pressed)
                                                return
                                            root.peerMapPanX += mouse.x - lastX
                                            root.peerMapPanY += mouse.y - lastY
                                            lastX = mouse.x
                                            lastY = mouse.y
                                        }
                                        onWheel: function(wheel) {
                                            var oldZoom = root.peerMapZoom
                                            var zoomDelta = wheel.angleDelta.y > 0 ? 1.12 : 0.89
                                            root.peerMapZoom = Math.max(1.0, Math.min(5.0, root.peerMapZoom * zoomDelta))
                                            var factor = root.peerMapZoom / oldZoom
                                            root.peerMapPanX = wheel.x - (wheel.x - root.peerMapPanX) * factor
                                            root.peerMapPanY = wheel.y - (wheel.y - root.peerMapPanY) * factor
                                        }
                                        onDoubleClicked: {
                                            root.peerMapZoom = 1.0
                                            root.peerMapPanX = 0
                                            root.peerMapPanY = 0
                                            root.hidePeerMapHover()
                                        }
                                    }

                                    Text {
                                        anchors.centerIn: parent
                                        visible: !root.activePeerMapModel || mapCanvas.plottedPeerCount === 0
                                        text: qsTr("No connected peers to plot")
                                        color: ColorPalette.textSecond
                                        font.pixelSize: 12 * App.fontScale
                                    }

                                    Text {
                                        anchors.centerIn: parent
                                        visible: !!root.activePeerMapModel && root.activePeerMapModel.rowCount() > 0 && !root.activePeerMapModel.hasLocalLocation
                                        text: qsTr("Waiting for your public IP so the local map position can be shown")
                                        color: ColorPalette.textSecond
                                        font.pixelSize: 12 * App.fontScale
                                    }

                                }
                            }
                        }
                    }
                }

                Item {
                    // Shared context menu for tracker rows
                    Menu {
                        id: trackerCtxMenu
                        property string trackerUrl: ""
                        // DHT/PEX/LSD are virtual "trackers" with no real URL - disable
                        // destructive/copy actions so right-clicking them feels inert.
                        property bool isSystemEntry: false

                        Action {
                            text: qsTr("Force Reannounce")
                            enabled: !trackerCtxMenu.isSystemEntry && !!root.item
                            onTriggered: {
                                if (root.item && trackerCtxMenu.trackerUrl.length > 0)
                                    App.forceReannounceTorrent(root.item.id, [trackerCtxMenu.trackerUrl])
                            }
                        }
                        MenuSeparator {}
                        Action {
                            text: qsTr("Copy URL")
                            enabled: !trackerCtxMenu.isSystemEntry
                            onTriggered: {
                                if (trackerCtxMenu.trackerUrl.length > 0)
                                    App.copyToClipboard(trackerCtxMenu.trackerUrl)
                            }
                        }
                        MenuSeparator {}
                        Action {
                            text: qsTr("Remove tracker")
                            enabled: !trackerCtxMenu.isSystemEntry
                            onTriggered: {
                                if (root.item && trackerCtxMenu.trackerUrl.length > 0)
                                    App.removeTorrentTracker(root.item.id, trackerCtxMenu.trackerUrl)
                            }
                        }
                    }

                    // Add tracker panel - slides in/out from the top
                    ColumnLayout {
                        anchors.fill: parent; spacing: 0

                        // Toolbar row with count + add button
                        Rectangle {
                            Layout.fillWidth: true; height: 34
                            color: ColorPalette.panelBg
                            Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: ColorPalette.border }

                            RowLayout {
                                anchors { fill: parent; leftMargin: 10; rightMargin: 10 }
                                Text {
                                    text: qsTr("Trackers")
                                    color: ColorPalette.textPrimary; font.pixelSize: 12 * App.fontScale; font.bold: true
                                }
                                Text {
                                    text: qsTr("%n tracker(s)", "", trackerList.count)
                                    color: ColorPalette.textDisabled; font.pixelSize: 11 * App.fontScale
                                    leftPadding: 8
                                }
                                Item { Layout.fillWidth: true }

                                Text {
                                    id: reannounceStatusTxt
                                    text: ""
                                    color: "#6aaa6a"; font.pixelSize: 11 * App.fontScale
                                    Layout.alignment: Qt.AlignVCenter
                                    opacity: 0
                                    Behavior on opacity { NumberAnimation { duration: 200 } }
                                }
                                Timer {
                                    id: reannounceStatusTimer
                                    interval: 2500
                                    onTriggered: reannounceStatusTxt.opacity = 0
                                }

                                DlgButton {
                                    id: reannounceAllBtn
                                    text: qsTr("Reannounce All")
                                    enabled: !!root.item
                                    ThemedToolTip {
                                        visible: reannounceAllBtn.hovered
                                        delay: 400
                                        text: qsTr("Tell every tracker you're here right now, instead of waiting for the\nnormal announce interval. Useful if your peer count suddenly dropped.")
                                    }
                                    onClicked: {
                                        if (!root.item) return
                                        App.forceReannounceTorrent(root.item.id)
                                        reannounceStatusTxt.text = qsTr("Reannouncing...")
                                        reannounceStatusTxt.color = "#6aaa6a"
                                        reannounceStatusTxt.opacity = 1
                                        reannounceStatusTimer.restart()
                                        trackerRowFlashTimer.restart()
                                    }
                                }

                                Timer {
                                    id: trackerRowFlashTimer
                                    interval: 500
                                    property bool flashing: false
                                    onTriggered: flashing = false
                                    onRunningChanged: if (running) flashing = true
                                }
                                DlgButton {
                                    text: root.showTrackerAdd ? qsTr("Cancel") : qsTr("Add trackers...")
                                    primary: !root.showTrackerAdd
                                    onClicked: {
                                        root.showTrackerAdd = !root.showTrackerAdd
                                        if (root.showTrackerAdd) trackerInput.forceActiveFocus()
                                    }
                                }
                            }
                        }

                        // Add tracker panel (collapsible)
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: root.showTrackerAdd ? 130 : 0
                            color: ColorPalette.infoBoxBg; border.color: ColorPalette.infoBoxBorder
                            clip: true
                            visible: root.showTrackerAdd

                            Behavior on Layout.preferredHeight { NumberAnimation { duration: 120 } }

                            ColumnLayout {
                                anchors { fill: parent; margins: 10 }
                                spacing: 6

                                Text {
                                    text: qsTr("Paste tracker URLs - one per line. Lines starting with # are ignored.")
                                    color: ColorPalette.infoBoxText; font.pixelSize: 11 * App.fontScale; wrapMode: Text.WordWrap
                                    Layout.fillWidth: true
                                }

                                Rectangle {
                                    Layout.fillWidth: true; Layout.fillHeight: true
                                    color: ColorPalette.inputBg
                                    border.color: trackerInput.activeFocus ? "#4488dd" : ColorPalette.border; radius: 2; clip: true

                                    ScrollView {
                                        anchors.fill: parent
                                        TextArea {
                                            id: trackerInput
                                            placeholderText: "udp://tracker.opentrackr.org:1337/announce\nhttps://tracker.example.org/announce"
                                            color: ColorPalette.textPrimary; placeholderTextColor: ColorPalette.border
                                            font.pixelSize: 11 * App.fontScale; wrapMode: TextArea.NoWrap
                                            selectByMouse: true; background: null; padding: 6
                                        }
                                    }
                                }

                                RowLayout {
                                    Layout.fillWidth: true; spacing: 6
                                    Text {
                                        id: addStatusTxt; text: ""
                                        color: "#6aaa6a"; font.pixelSize: 11 * App.fontScale
                                    }
                                    Item { Layout.fillWidth: true }
                                    DlgButton {
                                        text: qsTr("Add")
                                        primary: true
                                        enabled: !!root.item && trackerInput.text.trim().length > 0
                                        onClicked: {
                                            if (!root.item) return
                                            var lines = trackerInput.text.split(/\r?\n/)
                                            var added = 0, failed = 0
                                            for (var i = 0; i < lines.length; ++i) {
                                                var u = lines[i].trim()
                                                if (!u || u[0] === "#") continue
                                                App.addTorrentTracker(root.item.id, u) ? added++ : failed++
                                            }
                                            if (added > 0) trackerInput.clear()
                                            addStatusTxt.text = failed
                                                ? qsTr("%1 added, %2 failed").arg(added).arg(failed)
                                                : qsTr("%1 added").arg(added)
                                            addStatusTxt.color = failed > 0 ? "#c0a54a" : "#6aaa6a"
                                            if (added > 0 && failed === 0) root.showTrackerAdd = false
                                            addStatusClearTimer.restart()
                                        }
                                    }
                                }
                            }
                        }

                        // Tracker list header
                        Rectangle {
                            id: trackerHeader
                            Layout.fillWidth: true; height: 26
                            color: ColorPalette.dividerBg; clip: true
                            Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: ColorPalette.border }
                            Item {
                                x: -trackerList.contentX
                                width: root.trkColTracker + root.trkColStatus + root.trkColSource + root.trkColSeeders + root.trkColPeers + root.trkColNextAnnounce + root.trkColMessage
                                height: parent.height

                                Repeater {
                                    model: root._trkColsOrdered
                                    delegate: Rectangle {
                                        id: trkHdrCell
                                        x: root._trkColXMap[modelData.key] || 0
                                        width: root._trkColW(modelData.key)
                                        height: trackerHeader.height
                                        color: trkHdrMa.containsMouse && !trkRhDrag.active ? ColorPalette.border : "transparent"
                                        opacity: root._trkColDragging && root._trkColDragFromKey === modelData.key ? 0.5 : 1.0

                                        // Insert-before indicator
                                        Rectangle {
                                            anchors.left: parent.left
                                            width: 2; height: parent.height
                                            color: "#4488dd"
                                            visible: root._trkColDragging && root._trkColDragInsertBeforeKey === modelData.key
                                        }

                                        Text {
                                            anchors { verticalCenter: parent.verticalCenter; left: parent.left; leftMargin: 6; right: trkSortArrow.left; rightMargin: 2 }
                                            text: modelData.title
                                            color: root.trkSortKey === modelData.sortKey ? "#88bbff" : ColorPalette.textPrimary
                                            font.pixelSize: 12 * App.fontScale; font.bold: true; elide: Text.ElideRight
                                        }
                                        Text {
                                            id: trkSortArrow
                                            anchors { verticalCenter: parent.verticalCenter; right: trkRh.left; rightMargin: 4 }
                                            text: root.trkSortAscending ? "▲" : "▼"
                                            color: "#88bbff"; font.pixelSize: 9 * App.fontScale
                                            visible: root.trkSortKey === modelData.sortKey
                                        }
                                        Rectangle { anchors.right: parent.right; width: 1; height: parent.height; color: ColorPalette.border }

                                        MouseArea {
                                            id: trkHdrMa
                                            anchors { fill: parent; rightMargin: 10 }
                                            hoverEnabled: true
                                            cursorShape: root._trkColDragging ? Qt.ClosedHandCursor : Qt.PointingHandCursor
                                            onPressed: {
                                                root._trkColDragFromKey = modelData.key
                                                root._trkColDragging = true
                                            }
                                            onPositionChanged: {
                                                if (!root._trkColDragging) return
                                                var mx = mapToItem(trackerHeader, mouseX, 0).x + trackerList.contentX
                                                var insertKey = "__end__"
                                                for (var i = 0; i < root._trkColsOrdered.length; i++) {
                                                    var col = root._trkColsOrdered[i]
                                                    var cx = root._trkColXMap[col.key] || 0
                                                    if (mx < cx + root._trkColW(col.key) / 2) { insertKey = col.key; break }
                                                }
                                                root._trkColDragInsertBeforeKey = insertKey
                                            }
                                            onReleased: {
                                                if (root._trkColDragging) root._applyTrkColReorder()
                                                root._trkColDragFromKey = ""
                                                root._trkColDragInsertBeforeKey = ""
                                                root._trkColDragging = false
                                            }
                                            onClicked: {
                                                if (root._trkColDragInsertBeforeKey === "") root.sortTrackers(modelData.sortKey)
                                            }
                                        }

                                        // Resize handle
                                        Item {
                                            id: trkRh; width: 10; height: parent.height; anchors.right: parent.right; z: 10
                                            property real _startW: 0
                                            Rectangle { anchors.right: parent.right; width: 2; height: parent.height
                                                color: (trkRhDrag.active || trkRhHov.hovered) ? "#6aa0ff" : "transparent"; opacity: 0.8 }
                                            HoverHandler { id: trkRhHov; cursorShape: Qt.SizeHorCursor }
                                            DragHandler {
                                                id: trkRhDrag; target: null; xAxis.enabled: true; yAxis.enabled: false; cursorShape: Qt.SizeHorCursor
                                                onActiveChanged: if (active) trkRh._startW = root._trkColW(modelData.key)
                                                onTranslationChanged: {
                                                    if (!active) return
                                                    var k = modelData.key
                                                    var minW = (k === "tracker") ? 220 : (k === "message") ? 120 : 55
                                                    var newW = Math.max(minW, Math.round(trkRh._startW + translation.x))
                                                    if      (k === "tracker")      root.trkColTracker      = newW
                                                    else if (k === "status")       root.trkColStatus       = newW
                                                    else if (k === "source")       root.trkColSource       = newW
                                                    else if (k === "seeders")      root.trkColSeeders      = newW
                                                    else if (k === "peers")        root.trkColPeers        = newW
                                                    else if (k === "nextAnnounce") root.trkColNextAnnounce = newW
                                                    else if (k === "message")      root.trkColMessage      = newW
                                                }
                                            }
                                        }

                                        // Insert-after-last indicator
                                        Rectangle {
                                            anchors.right: parent.right
                                            width: 2; height: parent.height
                                            color: "#4488dd"
                                            visible: root._trkColDragging
                                                && root._trkColDragInsertBeforeKey === "__end__"
                                                && index === root._trkColsOrdered.length - 1
                                        }
                                    }
                                }
                            }
                        }

                        // Tracker rows
                        ListView {
                            id: trackerList
                            Layout.fillWidth: true; Layout.fillHeight: true
                            clip: true; model: root.activeTrackerListModel; spacing: 0
                            flickableDirection: Flickable.HorizontalAndVerticalFlick
                            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                            ScrollBar.horizontal: ScrollBar { policy: ScrollBar.AlwaysOn }
                            contentWidth: root.trkColTracker + root.trkColStatus + root.trkColSource + root.trkColSeeders + root.trkColPeers + root.trkColNextAnnounce + root.trkColMessage

                            Text {
                                anchors.centerIn: parent
                                visible: trackerList.count === 0
                                text: qsTr("No trackers")
                                color: ColorPalette.textDisabled; font.pixelSize: 12 * App.fontScale
                            }

                            delegate: Rectangle {
                                id: trd
                                required property int    index
                                required property string url
                                required property string status
                                required property int    tier
                                required property string source
                                required property int    seeders
                                required property int    peers
                                required property int    nextAnnounceSecs
                                required property string message
                                required property bool   isSystemEntry

                                width: Math.max(ListView.view.width, trackerList.contentWidth); height: 28
                                color: trackerRowFlashTimer.flashing
                                       ? ColorPalette.mapGrid
                                       : (trMa.containsMouse ? ColorPalette.hoverBg : (index % 2 === 0 ? ColorPalette.windowBg : ColorPalette.rowAltBg))
                                Behavior on color { ColorAnimation { duration: trackerRowFlashTimer.flashing ? 80 : 350 } }

                                MouseArea {
                                    id: trMa; anchors.fill: parent; hoverEnabled: true
                                    acceptedButtons: Qt.RightButton
                                    onClicked: {
                                        trackerCtxMenu.trackerUrl = trd.url
                                        trackerCtxMenu.isSystemEntry = trd.isSystemEntry
                                        trackerCtxMenu.popup()
                                    }
                                }

                                Item {
                                    anchors.fill: parent

                                    Item {
                                        x: (root._trkColXMap["tracker"] || 0) + 8
                                        width: root.trkColTracker - 8; height: parent.height; clip: true
                                        Text {
                                            anchors { fill: parent }
                                            verticalAlignment: Text.AlignVCenter
                                            text: safeStr(trd.url); color: ColorPalette.textPrimary; font.pixelSize: 12 * App.fontScale; elide: Text.ElideRight
                                        }
                                    }
                                    Item {
                                        x: root._trkColXMap["status"] || 0
                                        width: root.trkColStatus; height: parent.height; clip: true
                                        Text {
                                            anchors { fill: parent; leftMargin: 6 }
                                            verticalAlignment: Text.AlignVCenter
                                            text: safeStr(trd.status)
                                            color: {
                                                var s = safeStr(trd.status).toLowerCase()
                                                if (s === "not working") return "#cc6060"
                                                if (s.indexOf("error") >= 0 || s.indexOf("fail") >= 0) return "#cc6060"
                                                if (s === "working") return "#55cc66"
                                                if (s.indexOf("announcing") >= 0 || s.indexOf("reannouncing") >= 0) return "#c0a54a"
                                                return ColorPalette.textPrimary
                                            }
                                            font.pixelSize: 12 * App.fontScale; elide: Text.ElideRight
                                        }
                                    }
                                    Item {
                                        x: root._trkColXMap["source"] || 0
                                        width: root.trkColSource; height: parent.height; clip: true
                                        Text {
                                            anchors { fill: parent; leftMargin: 6 }
                                            verticalAlignment: Text.AlignVCenter
                                            text: safeStr(trd.source); color: ColorPalette.textPrimary; font.pixelSize: 12 * App.fontScale; elide: Text.ElideRight
                                        }
                                    }
                                    Item {
                                        x: root._trkColXMap["seeders"] || 0
                                        width: root.trkColSeeders; height: parent.height; clip: true
                                        Text {
                                            anchors { fill: parent; leftMargin: 6 }
                                            verticalAlignment: Text.AlignVCenter
                                            text: String(trd.seeders | 0); color: "#c0a54a"; font.pixelSize: 12 * App.fontScale
                                        }
                                    }
                                    Item {
                                        x: root._trkColXMap["peers"] || 0
                                        width: root.trkColPeers; height: parent.height; clip: true
                                        Text {
                                            anchors { fill: parent; leftMargin: 6 }
                                            verticalAlignment: Text.AlignVCenter
                                            text: String(trd.peers | 0); color: ColorPalette.textPrimary; font.pixelSize: 12 * App.fontScale
                                        }
                                    }
                                    Item {
                                        x: root._trkColXMap["nextAnnounce"] || 0
                                        width: root.trkColNextAnnounce; height: parent.height; clip: true
                                        Text {
                                            anchors { fill: parent; leftMargin: 6 }
                                            verticalAlignment: Text.AlignVCenter
                                            color: ColorPalette.textPrimary; font.pixelSize: 12 * App.fontScale
                                            text: {
                                                if (trd.isSystemEntry) return ""
                                                var s = trd.nextAnnounceSecs | 0
                                                if (s < 0) return qsTr("-")
                                                if (s === 0) return qsTr("Now")
                                                var h = Math.floor(s / 3600)
                                                var m = Math.floor((s % 3600) / 60)
                                                var sec = s % 60
                                                if (h > 0) return qsTr("%1h %2m").arg(h).arg(m)
                                                if (m > 0) return qsTr("%1m %2s").arg(m).arg(sec)
                                                return qsTr("%1s").arg(sec)
                                            }
                                        }
                                    }
                                    Item {
                                        x: root._trkColXMap["message"] || 0
                                        width: root.trkColMessage; height: parent.height; clip: true
                                        Text {
                                            anchors { fill: parent; leftMargin: 6 }
                                            verticalAlignment: Text.AlignVCenter
                                            text: {
                                                var msg = safeStr(trd.message)
                                                if (msg.length > 0) return msg
                                                if (trd.isSystemEntry) return ""
                                                var s = safeStr(trd.status)
                                                return s === "Idle" ? qsTr("Waiting to announce") : ""
                                            }
                                            color: safeStr(trd.message).length > 0 ? ColorPalette.textPrimary : ColorPalette.textDisabled
                                            font.pixelSize: 12 * App.fontScale; elide: Text.ElideRight
                                        }
                                    }
                                }
                            }
                        }
                    }

                    Timer {
                        id: addStatusClearTimer; interval: 4000
                        onTriggered: addStatusTxt.text = ""
                    }
                }

                // ?? Web Seeds ?????????????????????????????????????????????????
                Item {
                    id: webSeedsTab

                    // Build a flat ListModel from the two seed lists whenever either changes.
                    // Each entry has: url (string), seedType (string: "URL Seed" or "HTTP Seed")
                    ListModel { id: webSeedModel }

                    function _rebuildModel() {
                        webSeedModel.clear()
                        if (!root.item) return
                        var urlSeeds  = root.item.torrentUrlSeeds  || []
                        var httpSeeds = root.item.torrentHttpSeeds || []
                        for (var i = 0; i < urlSeeds.length; ++i)
                            webSeedModel.append({ url: urlSeeds[i],  seedType: "URL Seed" })
                        for (var j = 0; j < httpSeeds.length; ++j)
                            webSeedModel.append({ url: httpSeeds[j], seedType: "HTTP Seed" })
                    }

                    Connections {
                        target: root
                        function onItemChanged() { webSeedsTab._rebuildModel() }
                    }

                    Connections {
                        target: root.item
                        enabled: !!root.item
                        function onTorrentChanged() {
                            if (root.webSeedsTabActive) webSeedsTab._rebuildModel()
                        }
                    }

                    onVisibleChanged: {
                        if (visible && root.webSeedsTabActive) _rebuildModel()
                    }

                    ColumnLayout {
                        anchors.fill: parent; spacing: 0

                        // Toolbar
                        Rectangle {
                            Layout.fillWidth: true; height: 34
                            color: ColorPalette.panelBg
                            Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: ColorPalette.border }

                            RowLayout {
                                anchors { fill: parent; leftMargin: 10; rightMargin: 10 }
                                Text {
                                    text: qsTr("Web Seeds")
                                    color: ColorPalette.textPrimary; font.pixelSize: 12 * App.fontScale; font.bold: true
                                }
                                Text {
                                    text: qsTr("%n seed(s)", "", webSeedModel.count)
                                    color: ColorPalette.textDisabled; font.pixelSize: 11 * App.fontScale
                                    leftPadding: 8
                                }
                                Item { Layout.fillWidth: true }
                                DlgButton {
                                    text: root.showWebSeedAdd ? qsTr("Cancel") : qsTr("Add seed...")
                                    primary: !root.showWebSeedAdd
                                    onClicked: {
                                        root.showWebSeedAdd = !root.showWebSeedAdd
                                        if (root.showWebSeedAdd) webSeedInput.forceActiveFocus()
                                    }
                                }
                            }
                        }

                        // Add web seed panel (collapsible)
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: root.showWebSeedAdd ? 130 : 0
                            color: ColorPalette.infoBoxBg; border.color: ColorPalette.infoBoxBorder
                            clip: true
                            visible: root.showWebSeedAdd

                            Behavior on Layout.preferredHeight { NumberAnimation { duration: 120 } }

                            ColumnLayout {
                                anchors { fill: parent; margins: 10 }
                                spacing: 6

                                Text {
                                    text: qsTr("Paste web seed URLs - one per line. URL seeds (BEP-19) and HTTP seeds (BEP-17) are both accepted.")
                                    color: ColorPalette.infoBoxText; font.pixelSize: 11 * App.fontScale; wrapMode: Text.WordWrap
                                    Layout.fillWidth: true
                                }

                                Rectangle {
                                    Layout.fillWidth: true; Layout.fillHeight: true
                                    color: ColorPalette.inputBg
                                    border.color: webSeedInput.activeFocus ? "#4488dd" : ColorPalette.border; radius: 2; clip: true

                                    ScrollView {
                                        anchors.fill: parent
                                        TextArea {
                                            id: webSeedInput
                                            placeholderText: "https://example.com/files/\nhttps://mirror.example.org/files/"
                                            color: ColorPalette.textPrimary; placeholderTextColor: ColorPalette.border
                                            font.pixelSize: 11 * App.fontScale; wrapMode: TextArea.NoWrap
                                            selectByMouse: true; background: null; padding: 6
                                        }
                                    }
                                }

                                RowLayout {
                                    Layout.fillWidth: true; spacing: 6
                                    Text {
                                        id: webSeedAddStatusTxt; text: ""
                                        color: "#6aaa6a"; font.pixelSize: 11 * App.fontScale
                                    }
                                    Item { Layout.fillWidth: true }
                                    DlgButton {
                                        text: qsTr("Add")
                                        primary: true
                                        enabled: !!root.item && webSeedInput.text.trim().length > 0
                                        onClicked: {
                                            if (!root.item) return
                                            var lines = webSeedInput.text.split(/\r?\n/)
                                            var added = 0
                                            for (var i = 0; i < lines.length; ++i) {
                                                var u = lines[i].trim()
                                                if (!u || u[0] === "#") continue
                                                App.addTorrentWebSeed(root.item.id, u)
                                                added++
                                            }
                                            if (added > 0) {
                                                webSeedInput.clear()
                                                webSeedAddStatusTxt.text = qsTr("%1 added").arg(added)
                                                webSeedAddStatusTxt.color = "#6aaa6a"
                                                root.showWebSeedAdd = false
                                                webSeedsTab._rebuildModel()
                                            }
                                            webSeedAddStatusClearTimer.restart()
                                        }
                                    }
                                }
                            }
                        }

                        // List header
                        Rectangle {
                            Layout.fillWidth: true; height: 26
                            color: ColorPalette.dividerBg; clip: true
                            Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: ColorPalette.border }
                            Row {
                                anchors { fill: parent; leftMargin: 8 }
                                Text {
                                    width: webSeedList.width * 0.72
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: qsTr("URL"); color: ColorPalette.textPrimary; font.pixelSize: 12 * App.fontScale; font.bold: true; elide: Text.ElideRight
                                }
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: qsTr("Type"); color: ColorPalette.textPrimary; font.pixelSize: 12 * App.fontScale; font.bold: true
                                }
                            }
                        }

                        // Seed rows
                        ListView {
                            id: webSeedList
                            Layout.fillWidth: true; Layout.fillHeight: true
                            clip: true
                            model: webSeedModel
                            spacing: 0
                            flickableDirection: Flickable.HorizontalAndVerticalFlick
                            contentWidth: Math.max(width, 680)
                            ScrollBar.vertical:   ScrollBar { policy: ScrollBar.AsNeeded }
                            ScrollBar.horizontal: ScrollBar { policy: ScrollBar.AlwaysOn }

                            Text {
                                anchors.centerIn: parent
                                visible: webSeedList.count === 0
                                text: qsTr("No web seeds")
                                color: ColorPalette.textDisabled; font.pixelSize: 12 * App.fontScale
                            }

                            delegate: Rectangle {
                                id: wsd
                                required property int    index
                                required property string url
                                required property string seedType

                                width: Math.max(ListView.view.width, webSeedList.contentWidth); height: 28
                                color: wsMa.containsMouse ? ColorPalette.hoverBg : (index % 2 === 0 ? ColorPalette.windowBg : ColorPalette.rowAltBg)

                                MouseArea {
                                    id: wsMa; anchors.fill: parent; hoverEnabled: true
                                    acceptedButtons: Qt.RightButton
                                    onClicked: {
                                        webSeedCtxMenu.seedUrl  = wsd.url
                                        webSeedCtxMenu.seedType = wsd.seedType
                                        webSeedCtxMenu.popup()
                                    }
                                }

                                Row {
                                    anchors { fill: parent; leftMargin: 8 }
                                    spacing: 0
                                    Item {
                                        width: webSeedList.width * 0.72
                                        height: parent.height; clip: true
                                        Text {
                                            anchors { fill: parent }
                                            verticalAlignment: Text.AlignVCenter
                                            text: wsd.url
                                            color: ColorPalette.textPrimary; font.pixelSize: 12 * App.fontScale; elide: Text.ElideRight
                                        }
                                    }
                                    Item {
                                        width: webSeedList.width * 0.28
                                        height: parent.height; clip: true
                                        Text {
                                            anchors { fill: parent }
                                            verticalAlignment: Text.AlignVCenter
                                            text: wsd.seedType
                                            color: wsd.seedType === "URL Seed" ? "#6aaa6a" : "#c0a54a"
                                            font.pixelSize: 12 * App.fontScale
                                        }
                                    }
                                }
                            }

                            Menu {
                                id: webSeedCtxMenu
                                property string seedUrl:  ""
                                property string seedType: ""

                                Action {
                                    text: qsTr("Copy URL")
                                    onTriggered: {
                                        if (webSeedCtxMenu.seedUrl.length > 0)
                                            App.copyToClipboard(webSeedCtxMenu.seedUrl)
                                    }
                                }
                                Action {
                                    text: qsTr("Open in browser")
                                    onTriggered: {
                                        if (webSeedCtxMenu.seedUrl.length > 0)
                                            App.openExternalUrl(webSeedCtxMenu.seedUrl)
                                    }
                                }
                                MenuSeparator {}
                                Action {
                                    text: qsTr("Remove seed")
                                    onTriggered: {
                                        if (root.item && webSeedCtxMenu.seedUrl.length > 0) {
                                            App.removeTorrentWebSeed(root.item.id, webSeedCtxMenu.seedUrl)
                                            webSeedsTab._rebuildModel()
                                        }
                                    }
                                }
                            }
                        }
                    }

                    Timer {
                        id: webSeedAddStatusClearTimer; interval: 4000
                        onTriggered: webSeedAddStatusTxt.text = ""
                    }
                }

                // ?? Piece Map ?????????????????????????????????????????????????
                Item {
                    id: pieceMapTab

                    readonly property bool isActive: visible && root._isTorrent && root.currentTab === 7
                    property var pieceData: []
                    // maxRarity is the highest peer-count seen; used to scale the rarity gradient.
                    property int maxRarity: 1
                    // flashSet: sparse object mapping piece index ? flash colour string.
                    // Populated on each refresh for pieces whose status changed; cleared by flashTimer.
                    property var flashSet: ({})
                    property bool hasFlash: false

                    onIsActiveChanged: {
                        if (isActive) pieceRefreshTimer.restart()
                        else          pieceRefreshTimer.stop()
                    }

                    // Clear stale data whenever the dialog switches to a different download
                    // so a seeding torrent never briefly shows the previous torrent's pieces.
                    Connections {
                        target: root
                        function onItemChanged() {
                            pieceMapTab.pieceData = []
                            pieceMapTab.flashSet = ({})
                            pieceMapTab.hasFlash = false
                        }
                    }

                    function refresh() {
                        if (!root._isTorrent || !root.item) return
                        var raw = App.torrentPieceMap(root.item.id)
                        if (!raw || raw.length === 0) return

                        var mx = 1
                        for (var i = 0; i < raw.length; ++i) {
                            var v = raw[i] & 0xFFFF
                            if (v > mx) mx = v
                        }
                        pieceMapTab.maxRarity = mx

                        // Only flash on meaningful status-category changes, not peer-count noise.
                        // Category: -2=have, -3=skipped, -4..=downloading, 0=unavailable, >0=missing
                        function cat(v) {
                            if (v === -2) return 0   // have
                            if (v === -3) return 1   // skipped
                            if (v <= -4)  return 2   // downloading
                            if (v === 0)  return 3   // unavailable
                            return 4                 // missing (any peer count)
                        }
                        var prev = pieceMapTab.pieceData
                        var newFlash = ({})
                        var anyFlash = false
                        if (prev && prev.length === raw.length) {
                            for (var j = 0; j < raw.length; ++j) {
                                if (cat(prev[j]) !== cat(raw[j])) {
                                    newFlash[j] = pieceCanvas.lightenColor(
                                        pieceCanvas.pieceColor(raw[j], mx), 0.55)
                                    anyFlash = true
                                }
                            }
                        }

                        pieceMapTab.pieceData = raw
                        if (anyFlash) {
                            pieceMapTab.flashSet = newFlash
                            pieceMapTab.hasFlash = true
                            pieceCanvas.requestPaint()   // draw flash frame
                            flashTimer.restart()
                        } else {
                            pieceCanvas.requestPaint()
                        }
                    }

                    Timer {
                        id: flashTimer
                        interval: 160; repeat: false
                        onTriggered: {
                            pieceMapTab.flashSet = ({})
                            pieceMapTab.hasFlash = false
                            pieceCanvas.requestPaint()   // draw final colour
                        }
                    }

                    Timer {
                        id: pieceRefreshTimer
                        interval: 2000; repeat: true; running: pieceMapTab.isActive
                        onTriggered: pieceMapTab.refresh()
                    }
                    // Also refresh immediately when tab becomes active
                    Connections {
                        target: pieceMapTab
                        function onIsActiveChanged() {
                            if (pieceMapTab.isActive) pieceMapTab.refresh()
                        }
                    }

                    ColumnLayout {
                        anchors { fill: parent; margins: 10 }
                        spacing: 8

                        // Legend row
                        Row {
                            Layout.fillWidth: true
                            spacing: 14

                            Text {
                                text: qsTr("Legend:")
                                color: ColorPalette.textSecond; font.pixelSize: 11 * App.fontScale
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            Repeater {
                                model: [
                                    { color: "#2ecc71", label: "Have" },
                                    { color: "#4a9de8", label: "Downloading" },
                                    { color: "#c0392b", label: "Rare" },
                                    { color: "#27ae60", label: "Common" },
                                    { color: "#e67e22", label: "High Priority" },
                                    { color: ColorPalette.textMuted, label: "Skipped" },
                                    { color: ColorPalette.cardBg, label: "Unavailable" }
                                ]
                                delegate: Row {
                                    required property var modelData
                                    spacing: 5
                                    anchors.verticalCenter: parent.verticalCenter
                                    Rectangle {
                                        width: 14; height: 14; radius: 2
                                        color: modelData.color
                                        border.color: Qt.darker(modelData.color, 1.3); border.width: 1
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                    Text {
                                        text: modelData.label; color: ColorPalette.textPrimary; font.pixelSize: 11 * App.fontScale
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                }
                            }

                            Item { Layout.fillWidth: true }

                            Text {
                                id: pieceSummaryText
                                color: ColorPalette.textSecond; font.pixelSize: 11 * App.fontScale
                                anchors.verticalCenter: parent.verticalCenter
                                text: {
                                    var d = pieceMapTab.pieceData
                                    if (!d || d.length === 0) return ""
                                    var have = 0, partial = 0, skipped = 0, missing = 0
                                    for (var i = 0; i < d.length; ++i) {
                                        var v = d[i]
                                        if (v === -2)      have++
                                        else if (v === -3) skipped++
                                        else if (v <= -4)  partial++
                                        else               missing++
                                    }
                                    var parts = [d.length + " pieces", have + " downloaded"]
                                    if (partial > 0) parts.push(partial + " downloading")
                                    if (skipped > 0) parts.push(skipped + " skipped")
                                    return parts.join("  -  ")
                                }
                            }
                        }

                        // Canvas
                        Canvas {
                            id: pieceCanvas
                            Layout.fillWidth: true
                            Layout.fillHeight: true

                            // Hover state for tooltip
                            property int hoveredPiece: -1
                            property int hoveredPieceStatus: 0
                            property int hoveredPieceAvail: 0

                            // Resolve piece index from mouse position given current layout
                            function pieceAt(mx, my) {
                                var d = pieceMapTab.pieceData
                                if (!d || d.length === 0) return -1
                                var cs = cellSizeForCount(d.length)
                                if (cs <= 0) return -1
                                var cols = Math.max(1, Math.floor(width / cs))
                                var col = Math.floor(mx / cs)
                                var row = Math.floor(my / cs)
                                var idx = row * cols + col
                                return (idx >= 0 && idx < d.length) ? idx : -1
                            }

                            function cellSizeForCount(n) {
                                if (n <= 0) return 14
                                // Ideal: fit all pieces in available area at reasonable cell size
                                // Start at 14px, step down to 2px minimum; pick largest that fits
                                var sizes = [14, 12, 10, 8, 6, 4, 3, 2]
                                for (var i = 0; i < sizes.length; ++i) {
                                    var cs = sizes[i]
                                    var cols = Math.floor(width / cs)
                                    if (cols <= 0) continue
                                    var rows = Math.ceil(n / cols)
                                    if (rows * cs <= height) return cs
                                }
                                // At 2px still doesn't fit: use run-length mode (1 col = many pieces)
                                return -Math.ceil(n / Math.max(1, Math.floor(width / 2)))
                            }

                            // Returns CSS colour for a piece value using the encoding from C++:
                            //   -2                : have
                            //   -3                : skipped (user deselected)
                            //   -(4+pct)  (-4..-103): downloading, pct% of blocks done
                            //   0                 : unavailable (no peers)
                            //   N                 : N peers have it (normal priority)
                            //   N | 0x10000       : N peers, high-priority piece
                            function pieceColor(val, maxRarity) {
                                if (val === -2) return "#2ecc71"   // have - green
                                if (val === -3) return ColorPalette.textMuted   // skipped - grey
                                if (val <= -4) {
                                    // Downloading: shade of blue proportional to block progress.
                                    // pct = 0 ? dark blue, pct = 99 ? bright cyan-blue
                                    var pct = Math.min(99, -(val + 4))
                                    var t = pct / 99
                                    var r2 = Math.round(0x1a + (0x4a - 0x1a) * t)
                                    var g2 = Math.round(0x4a + (0x9d - 0x4a) * t)
                                    var b2 = Math.round(0x80 + (0xe8 - 0x80) * t)
                                    return "rgb(" + r2 + "," + g2 + "," + b2 + ")"
                                }
                                var hp  = (val & 0x10000) !== 0
                                var cnt = val & 0xFFFF
                                if (cnt === 0) return ColorPalette.inputBg    // unavailable - near black
                                if (hp) return "#e67e22"           // high priority - orange
                                // Map 1..maxRarity to red (rare) ? green (common)
                                var t2 = maxRarity > 1 ? (cnt - 1) / (maxRarity - 1) : 1.0
                                // t2=0 ? rare #c0392b (red), t2=1 ? common #27ae60 (green)
                                var r = Math.round(0xc0 + (0x27 - 0xc0) * t2)
                                var g = Math.round(0x39 + (0xae - 0x39) * t2)
                                var b = Math.round(0x2b + (0x60 - 0x2b) * t2)
                                return "rgb(" + r + "," + g + "," + b + ")"
                            }

                            // Blend a CSS colour string toward white by factor t (0=unchanged, 1=white).
                            // Handles both "#rrggbb" and "rgb(r,g,b)" formats.
                            function lightenColor(color, t) {
                                var r, g, b
                                if (color.charAt(0) === '#') {
                                    r = parseInt(color.substr(1, 2), 16)
                                    g = parseInt(color.substr(3, 2), 16)
                                    b = parseInt(color.substr(5, 2), 16)
                                } else {
                                    var m = color.match(/rgb\s*\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*\)/)
                                    if (!m) return color
                                    r = parseInt(m[1]); g = parseInt(m[2]); b = parseInt(m[3])
                                }
                                r = Math.round(r + (255 - r) * t)
                                g = Math.round(g + (255 - g) * t)
                                b = Math.round(b + (255 - b) * t)
                                return "rgb(" + r + "," + g + "," + b + ")"
                            }

                            onPaint: {
                                var ctx = getContext("2d")
                                ctx.clearRect(0, 0, width, height)
                                ctx.fillStyle = ColorPalette.mapCanvasBg
                                ctx.fillRect(0, 0, width, height)

                                var d = pieceMapTab.pieceData
                                if (!d || d.length === 0) {
                                    ctx.fillStyle = ColorPalette.textDisabled
                                    ctx.font = "13px sans-serif"
                                    ctx.textAlign = "center"
                                    ctx.fillText("No piece data available", width / 2, height / 2)
                                    return
                                }

                                var maxR   = pieceMapTab.maxRarity
                                var flash  = pieceMapTab.hasFlash ? pieceMapTab.flashSet : null
                                var cs = cellSizeForCount(d.length)

                                if (cs > 0) {
                                    // Normal mode: one cell per piece
                                    var cols = Math.max(1, Math.floor(width / cs))
                                    var gap = cs >= 4 ? 1 : 0
                                    for (var i = 0; i < d.length; ++i) {
                                        var col = i % cols
                                        var row = Math.floor(i / cols)
                                        // Use flash colour for changed pieces on the first paint after refresh
                                        ctx.fillStyle = (flash && flash[i] !== undefined)
                                            ? flash[i]
                                            : pieceColor(d[i], maxR)
                                        ctx.fillRect(col * cs + gap, row * cs + gap, cs - gap, cs - gap)
                                    }
                                } else {
                                    // Run mode: many pieces per 2px column - colour by dominant status in range
                                    var piecesPerCol = -cs  // cs is negative in run mode
                                    var numCols = Math.ceil(d.length / piecesPerCol)
                                    var colW = 2
                                    for (var c = 0; c < numCols; ++c) {
                                        var start = c * piecesPerCol
                                        var end = Math.min(start + piecesPerCol, d.length)
                                        // Count statuses in this run
                                        var haveCount = 0, partialCount = 0, skipCount = 0
                                        var rareSum = 0, rareN = 0
                                        for (var j = start; j < end; ++j) {
                                            var dv = d[j]
                                            if (dv === -2)       haveCount++
                                            else if (dv === -3)  skipCount++
                                            else if (dv <= -4)   partialCount++
                                            else if (dv > 0)     { rareSum += (dv & 0xFFFF); rareN++ }
                                        }
                                        var runLen = end - start
                                        var domColor
                                        if (haveCount >= runLen * 0.5)
                                            domColor = "#2ecc71"
                                        else if (partialCount > 0)
                                            domColor = "#4a9de8"
                                        else if (rareN > 0)
                                            domColor = pieceColor(Math.round(rareSum / rareN), maxR)
                                        else if (skipCount > 0)
                                            domColor = ColorPalette.textMuted
                                        else
                                            domColor = ColorPalette.inputBg
                                        ctx.fillStyle = domColor
                                        ctx.fillRect(c * colW, 0, colW, height)
                                    }
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true

                                onPositionChanged: function(mouse) {
                                    var idx = pieceCanvas.pieceAt(mouse.x, mouse.y)
                                    pieceCanvas.hoveredPiece = idx
                                    if (idx >= 0 && idx < pieceMapTab.pieceData.length)
                                        pieceCanvas.hoveredPieceAvail = pieceMapTab.pieceData[idx]
                                    else
                                        pieceCanvas.hoveredPieceAvail = 0
                                }
                                onExited: pieceCanvas.hoveredPiece = -1

                                ThemedToolTip {
                                    visible: pieceCanvas.hoveredPiece >= 0
                                    delay: 0
                                    text: {
                                        var idx = pieceCanvas.hoveredPiece
                                        if (idx < 0) return ""
                                        var val = pieceCanvas.hoveredPieceAvail
                                        var status
                                        if (val === -2) {
                                            status = "Downloaded"
                                        } else if (val === -3) {
                                            status = "Skipped (file not selected)"
                                        } else if (val <= -4) {
                                            var pct = Math.min(99, -(val + 4))
                                            status = "Downloading - " + pct + "% of blocks received"
                                        } else {
                                            var hp  = (val & 0x10000) !== 0
                                            var cnt = val & 0xFFFF
                                            if (cnt === 0)
                                                status = "Unavailable - no peers have this piece"
                                            else
                                                status = "Missing - " + cnt + (cnt === 1 ? " peer has it" : " peers have it") + (hp ? " (high priority)" : "")
                                        }
                                        return "Piece #" + idx + "\n" + status
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
