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
    title: _isTorrent ? "Torrent Properties" : "File Properties"
    // Sizes are enforced via onItemChanged/onVisibleChanged so the window
    // always fits the content type, even when the user switches items.
    color: "#1e1e1e"
    flags: Qt.Dialog | Qt.WindowTitleHint | Qt.WindowCloseButtonHint | Qt.WindowSystemMenuHint

    Material.theme: Material.Dark
    Material.background: "#1e1e1e"
    Material.accent: "#4488dd"

    property var item: null
    readonly property bool _isTorrent: item ? !!item.isTorrent : false
    readonly property var torrentFileModel:    _isTorrent ? App.torrentFileModel(item.id)    : null
    readonly property var torrentPeerModel:    _isTorrent ? App.torrentPeerModel(item.id)    : null
    readonly property var torrentTrackerModel: _isTorrent ? App.torrentTrackerModel(item.id) : null
    readonly property bool peerListActive: visible && _isTorrent && currentTab === 3
    readonly property bool peerMapActive: visible && _isTorrent && currentTab === 4
    readonly property bool peerUpdatesActive: visible && _isTorrent && (currentTab === 3 || currentTab === 4 || currentTab === 5)
    readonly property bool trackerTabActive: visible && _isTorrent && currentTab === 6
    readonly property var activePeerListModel: peerListActive ? torrentPeerModel : null
    readonly property var activePeerMapModel: peerMapActive ? torrentPeerModel : null
    readonly property var activeTrackerListModel: trackerTabActive ? torrentTrackerModel : null
    readonly property var activeTrackerMapModel: (peerMapActive && peerMapShowTrackers) ? torrentTrackerModel : null
    readonly property string _torrentStatusText: item ? safeStr(item.status) : ""
    readonly property bool _torrentIsMoving: _torrentStatusText === "Moving"

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
    property bool _suppressPeerViewportRestore: false
    property bool _peerViewportRestorePending: false
    property bool _peerViewportRestoreByAnchor: false

    // Column order (persisted as JSON key arrays)
    property string peerColOrderJson: '["country","endpoint","port","client","progress","down","up","downloaded","uploaded","type"]'
    property string trkColOrderJson:  '["tracker","status","source","seeders","peers","message"]'
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
        { title: "Country",  key: "country",  sortKey: "country" },
        { title: "Peer",     key: "endpoint", sortKey: "endpoint" },
        { title: "Port",     key: "port",     sortKey: "port" },
        { title: "Client",   key: "client",   sortKey: "client" },
        { title: "Progress", key: "progress", sortKey: "progress" },
        { title: "Down",     key: "down",     sortKey: "down" },
        { title: "Up",       key: "up",       sortKey: "up" },
        { title: "Downloaded", key: "downloaded", sortKey: "downloaded" },
        { title: "Uploaded", key: "uploaded", sortKey: "uploaded" },
        { title: "Flags",    key: "type",     sortKey: "type" }
    ]
    readonly property var _trkColDefs: [
        { title: "Tracker", key: "tracker" },
        { title: "Status",  key: "status" },
        { title: "Source",  key: "source" },
        { title: "Seeders", key: "seeders" },
        { title: "Peers",   key: "peers" },
        { title: "Message", key: "message" }
    ]
    readonly property var _fileColDefs: [
        { title: "Name",     key: "name" },
        { title: "Progress", key: "progress" },
        { title: "Size",     key: "size" }
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
        var _w = trkColTracker + trkColStatus + trkColSource + trkColSeeders + trkColPeers + trkColMessage
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
    property real trkColTracker: 520
    property real trkColStatus:  120
    property real trkColSource:   80
    property real trkColSeeders:  70
    property real trkColPeers:    70
    property real trkColMessage:  260

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
    property int    editPerTorrentDownLimitKBps: 0
    property int    editPerTorrentUpLimitKBps: 0
    property bool   peerMapHoverVisible: false
    property real   peerMapZoom: 1.0
    property real   peerMapPanX: 0
    property real   peerMapPanY: 0
    property real   peerMapLonOffset: 0.5
    property real   peerMapLatOffset: 4.5
    property bool   peerMapYouHoverVisible: false
    property bool   peerMapShowTrackers: true
    property bool   peerMapShowInactive: true
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
    property bool showTrackerAdd: false

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
        property alias trkColMessage: root.trkColMessage
        property alias peerColOrderJson: root.peerColOrderJson
        property alias trkColOrderJson:  root.trkColOrderJson
        property alias fileColOrderJson: root.fileColOrderJson
        property alias swarmStatsStoreJson: root.swarmStatsStoreJson
    }

    // ── Window sizing ────────────────────────────────────────────────────────
    function _applySize() {
        if (_isTorrent) {
            minimumWidth  = 820
            minimumHeight = 700
            width  = 820
            height = 700
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

    onItemChanged:  {
        currentTab = 0
        showTrackerAdd = false
        speedSamples = []
        speedHoverActive = false
        editPerTorrentDownLimitKBps = (root.item && root.item.isTorrent) ? (root.item.perTorrentDownLimitKBps | 0) : 0
        editPerTorrentUpLimitKBps = (root.item && root.item.isTorrent) ? (root.item.perTorrentUpLimitKBps | 0) : 0
        if (torrentPeerModel) torrentPeerModel.sortBy(peerSortKey, peerSortAscending)
        if (root.item && root.item.isTorrent)
            refreshSpeedHistory()
        root.loadSwarmStatsForCurrent()
        root._applySize()
        if (visible)
            root._centerOnOwner()
    }
    onVisibleChanged: {
        if (visible) {
            root._applySize()
            root._centerOnOwner()
            raise()
            requestActivate()
            root.loadSwarmStatsForCurrent()
        } else {
            root.persistSwarmStatsForCurrent()
        }
    }
    onPeerUpdatesActiveChanged: {
        if (torrentPeerModel) {
            torrentPeerModel.setLiveUpdatesEnabled(peerUpdatesActive)
            root.syncPeerStructuralUpdates()
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
        if (root.currentTab === 5 && root.swarmCanvasRef)
            root.swarmCanvasRef.requestPaint()
        if (root.currentTab === 5 && root.swarmLiveCanvasRef) root.swarmLiveCanvasRef.requestPaint()
        if (root.currentTab === 5 && root.swarmClientPieRef) root.swarmClientPieRef.requestPaint()
        if (root.currentTab === 5 && root.swarmCountryPieRef) root.swarmCountryPieRef.requestPaint()
    }
    onSpeedSpanIndexChanged: if (speedGraphCanvasRef) speedGraphCanvasRef.requestPaint()

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
            // unsaved edits — otherwise the user's in-flight changes win.
            if (!speedLimitDialog.dirty) {
                root.editPerTorrentDownLimitKBps = root.item.perTorrentDownLimitKBps | 0
                root.editPerTorrentUpLimitKBps   = root.item.perTorrentUpLimitKBps   | 0
            }
        }
        function onSpeedChanged() {
            if (root.visible && root._isTorrent && root.currentTab === 1 && speedGraphCanvasRef)
                speedGraphCanvasRef.requestPaint()
        }
        function onTorrentStatsChanged() {
            if (root.visible && root._isTorrent && root.currentTab === 1 && speedGraphCanvasRef)
                speedGraphCanvasRef.requestPaint()
        }
    }

    // ── Helpers ──────────────────────────────────────────────────────────────
    function safeStr(v) { return (v === undefined || v === null) ? "" : String(v) }
    function torrentStatusLabel() {
        switch (_torrentStatusText) {
        case "Paused": return "Stopped"
        case "Checking": return "Checking files"
        case "Downloading": return "Downloading"
        case "Moving": return "Moving"
        case "Seeding": return "Seeding"
        case "Queued": return "Queued"
        case "Completed": return "Complete"
        case "Error": return "Problem"
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
        default: return "#aeb6bf"
        }
    }
    function countryFlagSource(code) {
        var cc = safeStr(code).trim().toLowerCase()
        if (!cc || cc.length !== 2)
            return ""
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
        if (name.indexOf("utorrent") !== -1 || name.indexOf("µtorrent") !== -1 || name.indexOf("μtorrent") !== -1 || name.indexOf("microtorrent") !== -1)
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
        if (lower.indexOf("utorrent") !== -1 || lower.indexOf("microtorrent") !== -1) return "uTorrent"
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
    function refreshSpeedHistory() {
        if (!_isTorrent || !item) {
            speedSamples = []
            return
        }
        speedSamples = App.torrentSpeedHistory(item.id, speedSpanSeconds)
        if (currentTab === 1 && speedGraphCanvasRef)
            speedGraphCanvasRef.requestPaint()
    }
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
        // world-map.svg (Natural Earth 110m) uses equirectangular projection spanning ±90°.
        // x = (lon+180)/360*width, y = (90-lat)/180*height
        lat = Math.max(-90, Math.min(90, lat))
        var normalized = (90 - lat) / 180
        var drawableHeight = peerMapSvgMaxY - peerMapSvgMinY
        return ((peerMapSvgMinY + normalized * drawableHeight) / 387.0) * height
    }
    function peerLineWidth(peer) {
        if (!peer)
            return 1
        var speed = Math.max(Number(peer.downSpeed) || 0, Number(peer.upSpeed) || 0)
        if (speed <= 0)
            return 0
        if (speed >= 5 * 1024 * 1024)
            return 4
        if (speed >= 1024 * 1024)
            return 3
        if (speed >= 128 * 1024)
            return 2
        return 1.5
    }
    function flagColor(flag) {
        switch (flag) {
        case "IN":  return "#e8c84a"   // yellow — incoming
        case "OUT": return "#7a8899"   // muted — outgoing
        case "TRK": return "#5f93c9"   // blue — tracker
        case "DHT": return "#4db8ff"   // cyan-blue — DHT
        case "PEX": return "#a06de8"   // purple — PeX
        case "LSD": return "#4caf7d"   // green — local
        case "UTP": return "#5ecfe8"   // teal — uTP
        case "ENC": return "#7dd87d"   // green — encrypted
        case "SNB": return "#e86a5c"   // red — snubbed
        case "UPO": return "#c97de8"   // magenta — upload-only
        case "OPT": return "#e8a35c"   // orange — optimistic
        case "HPX": return "#ff8ab4"   // pink — holepunch
        case "I2P": return "#a8ff78"   // lime — I2P
        default:    return "#708396"
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
        if (speed >= 5 * 1024 * 1024)      alpha = 0.88
        else if (speed >= 1024 * 1024)     alpha = 0.70
        else if (speed >= 256 * 1024)      alpha = 0.52
        else if (speed >= 32 * 1024)       alpha = 0.36
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

    // Formats seconds into human-readable "Xh Xm" / "Xm Xs" / "Xs" / "—"
    function formatDuration(secs) {
        var s = Math.max(0, secs | 0)
        if (s <= 0) return "—"
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
        if (key === "tracker") return trkColTracker
        if (key === "status")  return trkColStatus
        if (key === "source")  return trkColSource
        if (key === "seeders") return trkColSeeders
        if (key === "peers")   return trkColPeers
        if (key === "message") return trkColMessage
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
        _suppressPeerViewportRestore = true
        if (peerSortKey === key)
            peerSortAscending = !peerSortAscending
        else {
            peerSortKey = key
            peerSortAscending = (key === "country" || key === "endpoint" || key === "client" || key === "type" || key === "region" || key === "city")
        }
        torrentPeerModel.sortBy(peerSortKey, peerSortAscending)
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
        var samples = swarmVisibleSamples().slice(-Math.max(60, Math.round(swarmPeriodSeconds / 60)))
        if (samples.length === 0)
            return { t: Date.now(), peers: 0, seeders: 0, ratio: 0 }
        return samples[samples.length - 1]
    }

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
            if (root.currentTab === 5 && root.swarmCanvasRef)
                root.swarmCanvasRef.requestPaint()
            if (root.currentTab === 5 && root.swarmLiveCanvasRef) root.swarmLiveCanvasRef.requestPaint()
            if (root.currentTab === 5 && root.swarmClientPieRef) root.swarmClientPieRef.requestPaint()
            if (root.currentTab === 5 && root.swarmCountryPieRef) root.swarmCountryPieRef.requestPaint()
        }
    }

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

    // ── Shared components ────────────────────────────────────────────────────
    component ReadOnlyField: Rectangle {
        property alias fieldText: ti.text
        property color textColor: "#d0d0d0"
        implicitHeight: 26
        color: "#1b1b1b"
        border.color: ti.activeFocus ? "#4488dd" : "#3a3a3a"
        radius: 2
        clip: true
        TextInput {
            id: ti
            anchors { fill: parent; leftMargin: 6; rightMargin: 6 }
            verticalAlignment: TextInput.AlignVCenter
            color: parent.textColor
            font.pixelSize: 12
            readOnly: true; selectByMouse: true; clip: true
        }
    }

    // ── File chooser ─────────────────────────────────────────────────────────
    FileDialog {
        id: moveFileDialog
        title: _isTorrent ? "Move Torrent Data To..." : "Move File To..."
        fileMode: FileDialog.SaveFile
        currentFolder: {
            if (!root.item) return ""
            var p = safeStr(root.item.savePath).replace(/\\/g, "/")
            return p ? ("file:///" + p) : ""
        }
        currentFile: {
            if (!root.item) return ""
            var p = safeStr(root.item.savePath).replace(/\\/g, "/")
            var f = safeStr(root.item.filename)
            return (p && f) ? ("file:///" + p + "/" + f) : ""
        }
        onAccepted: {
            if (!root.item) return
            var newPath = selectedFile.toString().replace(/^file:\/\/\//, "").replace(/^file:\/\//, "")
            if (newPath.length > 0) App.moveDownloadFile(root.item.id, newPath)
        }
    }
    FolderDialog {
        id: moveTorrentDialog
        currentFolder: {
            if (!root.item) return ""
            var p = safeStr(root.item.savePath).replace(/\\/g, "/")
            return p ? ("file:///" + p) : ""
        }
        onAccepted: {
            if (!root.item) return
            var newPath = selectedFolder.toString().replace(/^file:\/\/\//, "").replace(/^file:\/\//, "")
            if (newPath.length > 0) App.moveDownloadFile(root.item.id, newPath)
        }
    }

    // ── Root layout ──────────────────────────────────────────────────────────
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 0
        spacing: _isTorrent ? 8 : 6

        Loader {
            id: propertiesLoader
            Layout.fillWidth: true
            Layout.fillHeight: true
            sourceComponent: _isTorrent ? torrentLayout : regularLayout
            onLoaded: {
                root._applySize()
                if (root.visible)
                    root._centerOnOwner()
            }
        }

        // Bottom button bar
        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 12
            Layout.rightMargin: 12
            Layout.bottomMargin: 8
            spacing: 6
            DlgButton {
                visible: root._isTorrent
                text: "Torrent Settings..."
                enabled: !!root.item
                onClicked: {
                    speedLimitDialog.torrentItem = root.item
                    speedLimitDialog.show()
                    speedLimitDialog.raise()
                    speedLimitDialog.requestActivate()
                }
            }
            Item { Layout.fillWidth: true }
            RowLayout {
                visible: root._isTorrent
                spacing: 6
                DlgButton {
                    text: "Start"
                    enabled: !!root.item && safeStr(root.item.status) === "Paused"
                    onClicked: { if (root.item) App.resumeDownload(root.item.id) }
                }
                DlgButton {
                    text: "Stop"
                    enabled: !!root.item
                             && safeStr(root.item.status) !== "Paused"
                             && safeStr(root.item.status) !== "Error"
                    onClicked: { if (root.item) App.pauseDownload(root.item.id) }
                }
            }
            Item {
                visible: root._isTorrent
                Layout.preferredWidth: 10
            }
            DlgButton {
                text: "Open folder"
                enabled: !!root.item
                onClicked: { if (root.item) App.openFolderSelectFile(root.item.id) }
            }
            DlgButton {
                text: "Open file"
                enabled: {
                    if (!root.item) return false
                    if (!_isTorrent) return true
                    // For torrents: enabled when we know it's a single-file torrent.
                    // torrentIsSingleFile defaults true until metadata shows multiple files,
                    // so stopped single-file torrents also get the button.
                    return !!root.item.torrentIsSingleFile
                }
                onClicked: { if (root.item) App.openFile(root.item.id) }
            }
            DlgButton { text: "Close"; primary: true; onClicked: root.close() }
        }
    }

    // ── Per-torrent speed limit dialog (opened from General tab) ─────────────
    TorrentSpeedLimitDialog {
        id: speedLimitDialog
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // Regular HTTP/FTP file layout
    // ═══════════════════════════════════════════════════════════════════════════
    Component {
        id: regularLayout
        ColumnLayout {
            spacing: 8

            // Header card
            Rectangle {
                Layout.fillWidth: true; Layout.preferredHeight: 74
                color: "#222228"; border.width: 0; radius: 0
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
                            color: "#ffffff"; font.pixelSize: 14; font.bold: true
                            elide: Text.ElideMiddle; Layout.fillWidth: true
                        }
                        Text {
                            text: ""
                            color: "#8ea1b5"; font.pixelSize: 10
                            elide: Text.ElideRight; Layout.fillWidth: true
                            visible: false
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8
                            Text {
                                text: root.item ? safeStr(root.item.status) : "--"
                                color: root.item && safeStr(root.item.status) === "Downloading" ? "#62a8ff"
                                     : root.item && safeStr(root.item.status) === "Paused" ? "#b7b7b7"
                                     : root.item && safeStr(root.item.status) === "Completed" ? "#67bb7a"
                                     : root.item && safeStr(root.item.status) === "Error" ? "#d97b7b"
                                     : "#aeb6bf"
                                font.pixelSize: 11
                                font.bold: true
                            }
                            Text {
                                text: root.item ? root.compactBytes(root.item.totalBytes) : "--"
                                color: "#8f98a1"; font.pixelSize: 11
                                elide: Text.ElideRight; Layout.fillWidth: true
                            }
                        }
                    }
                }
            }

            // Details card
            Rectangle {
                Layout.fillWidth: true; Layout.fillHeight: true
                color: "#1e1e1e"; border.color: "#2d2d2d"; radius: 3

                ColumnLayout {
                    anchors { fill: parent; margins: 8 }
                    spacing: 6

                    GridLayout {
                        Layout.fillWidth: true
                        columns: 2; columnSpacing: 8; rowSpacing: 6

                        Text { text: "Status";  color: "#8899aa"; font.pixelSize: 12; font.bold: true }
                        Text { text: root.item ? safeStr(root.item.status) : "--"; color: "#c8c8c8"; font.pixelSize: 12; Layout.fillWidth: true }

                        Text { text: "Size";    color: "#8899aa"; font.pixelSize: 12; font.bold: true }
                        Text { text: root.item ? root.formatBytes(root.item.totalBytes) : "--"; color: "#c8c8c8"; font.pixelSize: 12 }

                        Text { text: "Save to"; color: "#8899aa"; font.pixelSize: 12; font.bold: true }
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
                            DlgButton { text: "Move"; enabled: !!root.item; onClicked: { if (root._isTorrent) moveTorrentDialog.open(); else moveFileDialog.open() } }
                        }

                        Text { text: "Address"; color: "#8899aa"; font.pixelSize: 12; font.bold: true }
                        ReadOnlyField {
                            Layout.fillWidth: true
                            fieldText: root.item ? safeStr(root.item.url) : "--"
                            textColor: "#4488dd"
                        }

                        Text { text: "Web page"; color: "#8899aa"; font.pixelSize: 12; font.bold: true }
                        Text {
                            text: { var p = root.item ? safeStr(root.item.parentUrl) : ""; return p || "(unknown)" }
                            color: "#c8c8c8"; font.pixelSize: 12; elide: Text.ElideMiddle; Layout.fillWidth: true
                        }

                        Text { text: "Referer"; color: "#8899aa"; font.pixelSize: 12; font.bold: true }
                        Text {
                            text: { var r = root.item ? safeStr(root.item.referrer) : ""; return r || "(none)" }
                            color: "#c8c8c8"; font.pixelSize: 12; elide: Text.ElideMiddle; Layout.fillWidth: true
                        }

                        Text { text: "Description"; color: "#8899aa"; font.pixelSize: 12; font.bold: true }
                        TextField {
                            Layout.fillWidth: true; implicitHeight: 26
                            text: root.item ? safeStr(root.item.description) : ""
                            color: "#d0d0d0"; font.pixelSize: 12
                            background: Rectangle { color: "#1b1b1b"; border.color: parent.activeFocus ? "#4488dd" : "#3a3a3a"; radius: 2 }
                            leftPadding: 6; topPadding: 0; bottomPadding: 0
                            onTextChanged: if (root.item && text !== root.item.description) App.setDownloadDescription(root.item.id, text)
                        }

                        Text { text: "Login"; color: "#8899aa"; font.pixelSize: 12; font.bold: true }
                        TextField {
                            Layout.fillWidth: true; implicitHeight: 26
                            text: root.item ? safeStr(root.item.username) : ""
                            color: "#d0d0d0"; font.pixelSize: 12
                            background: Rectangle { color: "#1b1b1b"; border.color: parent.activeFocus ? "#4488dd" : "#3a3a3a"; radius: 2 }
                            leftPadding: 6; topPadding: 0; bottomPadding: 0
                            onTextChanged: if (root.item && text !== root.item.username) App.setDownloadUsername(root.item.id, text)
                        }

                        Text { text: "Password"; color: "#8899aa"; font.pixelSize: 12; font.bold: true }
                        TextField {
                            Layout.fillWidth: true; implicitHeight: 26
                            text: root.item ? safeStr(root.item.password) : ""
                            echoMode: TextInput.Password
                            color: "#d0d0d0"; font.pixelSize: 12
                            background: Rectangle { color: "#1b1b1b"; border.color: parent.activeFocus ? "#4488dd" : "#3a3a3a"; radius: 2 }
                            leftPadding: 6; topPadding: 0; bottomPadding: 0
                            onTextChanged: if (root.item && text !== root.item.password) App.setDownloadPassword(root.item.id, text)
                        }
                    }
                    Item { Layout.fillHeight: true }
                }
            }
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // Torrent layout
    // ═══════════════════════════════════════════════════════════════════════════
    Component {
        id: torrentLayout
        ColumnLayout {
            spacing: 8

            // ── Summary header ────────────────────────────────────────────────
            Rectangle {
                Layout.fillWidth: true; Layout.preferredHeight: 170
                color: "#222228"; border.width: 0; radius: 0

                ColumnLayout {
                    anchors { fill: parent; leftMargin: 22; rightMargin: 22; topMargin: 14; bottomMargin: 26 }
                    spacing: 10

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.bottomMargin: 10
                        spacing: 10

                        Item {
                            Layout.preferredWidth: 36
                            Layout.preferredHeight: 36

                            Image {
                                anchors.centerIn: parent
                                width: 30
                                height: 30
                                source: {
                                    if (!root.item) return ""
                                    var p = safeStr(root.item.savePath).replace(/\\/g, "/")
                                    var f = safeStr(root.item.filename)
                                    return (p && f) ? ("image://fileicon/" + p + "/" + f) : ""
                                }
                                sourceSize: Qt.size(30, 30)
                                fillMode: Image.PreserveAspectFit
                                asynchronous: true
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true; spacing: 4
                            Text {
                                text: root.item ? safeStr(root.item.filename) : ""
                                color: "#ffffff"; font.pixelSize: 18; font.bold: true
                                elide: Text.ElideMiddle; Layout.fillWidth: true
                            }
                            Text {
                                text: {
                                    if (!root.item) return ""
                                    var h = safeStr(root.item.torrentInfoHash)
                                    return h ? ("Hash: " + h) : "Waiting for metadata…"
                                }
                                color: "#8ea1b5"; font.pixelSize: 11
                                elide: Text.ElideMiddle; Layout.fillWidth: true
                            }
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 8
                                Text {
                                    text: root.torrentStatusLabel()
                                    color: root.torrentStatusAccent()
                                    font.pixelSize: 11
                                    font.bold: true
                                }

                                Text {
                                    text: root.item ? ("ETA: " + (safeStr(root.item.timeLeft).length > 0 ? safeStr(root.item.timeLeft) : "--")) : "ETA: --"
                                    color: "#8f98a1"
                                    font.pixelSize: 11
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                }
                            }
                        }
                    }

                    // Progress bar
                    RowLayout {
                        Layout.fillWidth: true; spacing: 8
                        Text {
                            text: root.item ? Math.round(root.clampPct(root.item.progress) * 100) + "%" : "0%"
                            color: "#ffffff"; font.pixelSize: 15; font.bold: true
                            Layout.preferredWidth: 46
                        }
                        Rectangle {
                            Layout.fillWidth: true; height: 6; radius: 3
                            color: "#232323"; border.color: "#2d2d2d"
                            Rectangle {
                                width: Math.max(0, parent.width * (root.item ? root.clampPct(root.item.progress) : 0))
                                height: parent.height; radius: parent.radius; color: "#4488dd"
                            }
                        }
                        Text {
                            text: root.item ? root.compactSpeed(root.item.speed) : "0 B/s"
                            color: "#c8c8c8"; font.pixelSize: 12; Layout.preferredWidth: 90
                            horizontalAlignment: Text.AlignRight
                        }
                    }

                    // Stats strip
                    Row {
                        Layout.fillWidth: true; spacing: 0
                        Repeater {
                            model: [
                                { l: "Downloaded", v: root.item ? root.compactBytes(root.item.torrentDownloaded) : "--" },
                                { l: "Uploaded",   v: root.item ? root.compactBytes(root.item.torrentUploaded)   : "--" },
                                { l: "Ratio",      v: root.item ? root.ratioText(root.item.torrentRatio)         : "0.00" },
                                { l: "Seeders",    v: root.item ? String(root.item.torrentSeeders | 0)           : "0" },
                                { l: "Peers",      v: root.item ? String(root.item.torrentPeers   | 0)           : "0" },
                                { l: "ETA",        v: root.item ? (safeStr(root.item.timeLeft).length > 0 ? safeStr(root.item.timeLeft) : "--") : "--" },
                                { l: "Size",       v: root.item ? root.compactBytes(root.item.totalBytes)        : "--" }
                            ]
                            delegate: Item {
                                width: parent.width / 7; height: 36
                                Column {
                                    anchors.verticalCenter: parent.verticalCenter; spacing: 1
                                    Text { text: modelData.l; color: "#7e8791"; font.pixelSize: 10 }
                                    Text { text: modelData.v; color: "#e0e0e0"; font.pixelSize: 12; font.bold: true }
                                }
                            }
                        }
                    }
                }
            }

            // ── Tab strip ─────────────────────────────────────────────────────
            Rectangle {
                Layout.fillWidth: true; height: 34
                color: "#252525"

                Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: "#111" }

                Row {
                    anchors.fill: parent; spacing: 0
                    Repeater {
                        model: ["General", "Speed", "Files", "Peers", "Swarm Map", "Swarm Statistics", "Trackers"]
                        delegate: Rectangle {
                            width: tabLbl.implicitWidth + 28; height: parent.height
                            color: root.currentTab === index
                                   ? "#1e1e1e"
                                   : (tabHov.containsMouse ? "#2e2e2e" : "transparent")
                            Text {
                                id: tabLbl; anchors.centerIn: parent
                                text: modelData
                                color: root.currentTab === index ? "#ffffff" : "#909090"
                                font.pixelSize: 12
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

            // ── Tab pages ─────────────────────────────────────────────────────
            StackLayout {
                Layout.fillWidth: true; Layout.fillHeight: true
                currentIndex: root.currentTab

                // ── General ───────────────────────────────────────────────────
                Item {
                    ColumnLayout {
                        anchors { fill: parent; margins: 10 }
                        spacing: 8

                        // — Torrent info card —
                        Rectangle {
                            Layout.fillWidth: true
                            color: "#1e1e1e"; border.color: "#2d2d2d"; radius: 3
                            implicitHeight: infoCol.implicitHeight + 16

                            ColumnLayout {
                                id: infoCol
                                anchors { fill: parent; margins: 10 }
                                spacing: 6

                                Text {
                                    text: "TORRENT INFO"
                                    color: "#8899aa"; font.pixelSize: 10; font.bold: true
                                }

                                RowLayout {
                                    Layout.fillWidth: true; spacing: 8
                                    Text { text: "Source"; color: "#8899aa"; font.pixelSize: 12; Layout.preferredWidth: 70 }
                                    ReadOnlyField {
                                        Layout.fillWidth: true
                                        fieldText: root.item ? safeStr(root.item.torrentSource) : ""
                                        textColor: "#b9c8d7"
                                    }
                                }

                                RowLayout {
                                    Layout.fillWidth: true; spacing: 8
                                    Text { text: "Info hash"; color: "#8899aa"; font.pixelSize: 12; Layout.preferredWidth: 70 }
                                    ReadOnlyField { Layout.fillWidth: true; fieldText: root.item ? safeStr(root.item.torrentInfoHash) : "" }
                                    DlgButton {
                                        text: "Copy"
                                        enabled: !!root.item && safeStr(root.item.torrentInfoHash).length > 0
                                        onClicked: {
                                            var h = safeStr(root.item.torrentInfoHash)
                                            if (h.length > 0) App.copyToClipboard(h)
                                        }
                                    }
                                }

                                RowLayout {
                                    Layout.fillWidth: true; spacing: 8
                                    Text { text: "Metadata"; color: "#8899aa"; font.pixelSize: 12; Layout.preferredWidth: 70 }
                                    Text {
                                        readonly property bool hasMetadata: !!root.item && root.item.torrentHasMetadata
                                        text: hasMetadata ? "Available" : "Fetching from swarm..."
                                        color: hasMetadata ? "#67bb7a" : "#d2b26f"
                                        font.pixelSize: 11
                                        font.bold: true
                                    }
                                }
                            }
                        }

                        // — Save location + Transfer stats (merged) —
                        Rectangle {
                            Layout.fillWidth: true
                            color: "#1e1e1e"; border.color: "#2d2d2d"; radius: 3
                            implicitHeight: saveStatsCol.implicitHeight + 16

                            ColumnLayout {
                                id: saveStatsCol
                                anchors { fill: parent; margins: 10 }
                                spacing: 8

                                // Save location
                                ColumnLayout {
                                    Layout.fillWidth: true; spacing: 4
                                    Text {
                                        text: "SAVE LOCATION"
                                        color: "#8899aa"; font.pixelSize: 10; font.bold: true
                                    }
                                    RowLayout {
                                        Layout.fillWidth: true; spacing: 6
                                        ReadOnlyField { Layout.fillWidth: true; fieldText: root.item ? safeStr(root.item.savePath) : "" }
                                        DlgButton { text: "Move"; enabled: !!root.item && !root._torrentIsMoving; onClicked: { if (root._isTorrent) moveTorrentDialog.open(); else moveFileDialog.open() } }
                                    }
                                }

                                Rectangle { Layout.fillWidth: true; height: 1; color: "#2a2a2a" }

                                // Transfer stats
                                ColumnLayout {
                                    Layout.fillWidth: true; spacing: 8
                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 8

                                        Text {
                                            text: "TRANSFER STATS"
                                            color: "#8899aa"; font.pixelSize: 10; font.bold: true
                                        }
                                        Item { Layout.fillWidth: true }
                                        DlgButton {
                                            text: "Verify Local Data"
                                            enabled: !!root.item && !root._torrentIsMoving
                                            onClicked: {
                                                if (root.item) App.forceRecheckTorrent(root.item.id)
                                            }
                                        }
                                    }

                                    GridLayout {
                                        Layout.fillWidth: true
                                        columns: 4; columnSpacing: 8; rowSpacing: 4

                                        // Progress section
                                        Text { text: "Pieces"; color: "#8899aa"; font.pixelSize: 11 }
                                        Text {
                                            text: {
                                                if (!root.item) return "—"
                                                var done = root.item.torrentPiecesDone | 0
                                                var total = root.item.torrentPiecesTotal | 0
                                                if (total <= 0) return done > 0 ? String(done) : "—"
                                                return done + " / " + total + "  (" + Math.round(done / total * 100) + "%)"
                                            }
                                            color: "#c8c8c8"; font.pixelSize: 11; Layout.fillWidth: true
                                        }
                                        Text { text: "Availability"; color: "#8899aa"; font.pixelSize: 11 }
                                        Text {
                                            text: {
                                                if (!root.item) return "—"
                                                var av = root.item.torrentAvailability
                                                return (typeof av === "number" && av > 0) ? av.toFixed(2) + " copies" : "—"
                                            }
                                            color: "#c8c8c8"; font.pixelSize: 11; Layout.fillWidth: true
                                        }

                                        // Speed section
                                        Text { text: "Download speed"; color: "#8899aa"; font.pixelSize: 11 }
                                        Text {
                                            text: root.item ? root.compactSpeed(root.item.torrentDownloadSpeed) : "—"
                                            color: "#c8c8c8"; font.pixelSize: 11; Layout.fillWidth: true
                                        }
                                        Text { text: "Upload speed"; color: "#8899aa"; font.pixelSize: 11 }
                                        Text {
                                            text: root.item ? root.compactSpeed(root.item.torrentUploadSpeed) : "—"
                                            color: "#c8c8c8"; font.pixelSize: 11; Layout.fillWidth: true
                                        }

                                        // Activity section
                                        Text { text: "Connections"; color: "#8899aa"; font.pixelSize: 11 }
                                        Text {
                                            text: root.item ? String(root.item.torrentConnections | 0) : "—"
                                            color: "#c8c8c8"; font.pixelSize: 11; Layout.fillWidth: true
                                        }
                                        Text { text: "Active"; color: "#8899aa"; font.pixelSize: 11 }
                                        Text {
                                            text: root.item ? root.formatDuration(root.item.torrentActiveTimeSecs) : "—"
                                            color: "#c8c8c8"; font.pixelSize: 11; Layout.fillWidth: true
                                        }

                                        // Seeding section
                                        Text { text: "Seeding"; color: "#8899aa"; font.pixelSize: 11 }
                                        Text {
                                            text: root.item ? root.formatDuration(root.item.torrentSeedingTimeSecs) : "—"
                                            color: "#c8c8c8"; font.pixelSize: 11; Layout.fillWidth: true
                                        }
                                        Text { text: "Wasted"; color: "#8899aa"; font.pixelSize: 11 }
                                        Text {
                                            text: {
                                                if (!root.item) return "—"
                                                var w = root.item.torrentWastedBytes
                                                return (w > 0) ? root.compactBytes(w) : "None"
                                            }
                                            color: (root.item && root.item.torrentWastedBytes > 0) ? "#c0a54a" : "#c8c8c8"
                                            font.pixelSize: 11; Layout.fillWidth: true
                                        }

                                        // Share ratio
                                        Text { text: "Share ratio"; color: "#8899aa"; font.pixelSize: 11 }
                                        Text {
                                            text: root.item ? root.ratioText(root.item.torrentRatio) : "—"
                                            color: {
                                                if (!root.item) return "#c8c8c8"
                                                var r = Number(root.item.torrentRatio)
                                                if (r >= 1.0) return "#6aaa6a"
                                                if (r >= 0.5) return "#c0a54a"
                                                return "#c8c8c8"
                                            }
                                            font.pixelSize: 11; Layout.fillWidth: true
                                        }
                                        Text { text: "Speed limit"; color: "#8899aa"; font.pixelSize: 11; visible: !!root.item && (root.item.perTorrentDownLimitKBps > 0 || root.item.perTorrentUpLimitKBps > 0) }
                                        Text {
                                            text: {
                                                if (!root.item) return ""
                                                var d = root.item.perTorrentDownLimitKBps | 0
                                                var u = root.item.perTorrentUpLimitKBps   | 0
                                                var parts = []
                                                if (d > 0) parts.push("↓ " + d + " KB/s")
                                                if (u > 0) parts.push("↑ " + u + " KB/s")
                                                return parts.join("  •  ")
                                            }
                                            color: "#e8a040"; font.pixelSize: 11; Layout.fillWidth: true
                                            visible: !!root.item && (root.item.perTorrentDownLimitKBps > 0 || root.item.perTorrentUpLimitKBps > 0)
                                        }
                                    }

                                    Rectangle { Layout.fillWidth: true; height: 1; color: "#2a2a2a" }

                                    ColumnLayout {
                                        Layout.fillWidth: true; spacing: 4
                                        Text { text: "DESCRIPTION"; color: "#8899aa"; font.pixelSize: 10; font.bold: true }
                                        TextField {
                                            Layout.fillWidth: true; implicitHeight: 26
                                            text: root.item ? safeStr(root.item.description) : ""
                                            color: "#d0d0d0"; font.pixelSize: 12
                                            background: Rectangle { color: "#1b1b1b"; border.color: parent.activeFocus ? "#4488dd" : "#3a3a3a"; radius: 2 }
                                            leftPadding: 6; topPadding: 0; bottomPadding: 0
                                            onTextChanged: if (root.item && text !== root.item.description) App.setDownloadDescription(root.item.id, text)
                                        }
                                    }

                                }
                            }
                        }

                        // — Description —
                    }
                }

                // Speed
                Item {
                    ColumnLayout {
                        anchors { fill: parent; margins: 10 }
                        spacing: 8

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 10
                            Text { text: "Time span"; color: "#a0a0a0"; font.pixelSize: 12 }
                            ComboBox {
                                Layout.preferredWidth: 118
                                model: root.speedSpanOptions.map(function(o){ return o.label })
                                currentIndex: root.speedSpanIndex
                                onActivated: root.speedSpanIndex = currentIndex
                            }
                            Item { Layout.fillWidth: true }
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            color: "#171717"
                            border.color: "#2d2d2d"
                            radius: 3
                            clip: true

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

                                    var topPad = 12
                                    var rightPad = 56
                                    var bottomPad = 24
                                    var leftPad = 8
                                    var plotX = leftPad
                                    var plotY = topPad
                                    var plotW = Math.max(10, w - leftPad - rightPad)
                                    var plotH = Math.max(10, h - topPad - bottomPad)
                                    var nowMs = Date.now()
                                    var startMs = nowMs - root.speedSpanSeconds * 1000
                                    var samples = root.speedVisibleSamples()

                                    var maxV = 1
                                    for (var i = 0; i < samples.length; ++i)
                                        maxV = Math.max(maxV, Number(samples[i].down) || 0, Number(samples[i].up) || 0)

                                    var scale = Math.pow(10, Math.floor(Math.log(maxV) / Math.log(10)))
                                    var norm = maxV / scale
                                    var step = (norm <= 1) ? 1 : (norm <= 2 ? 2 : (norm <= 5 ? 5 : 10))
                                    var axisTop = Math.max(1, step * scale)
                                    while (axisTop < maxV) axisTop *= 2

                                    function pxForTime(t) {
                                        return plotX + ((t - startMs) / (root.speedSpanSeconds * 1000)) * plotW
                                    }
                                    function pyForRate(v) {
                                        return plotY + plotH - (Math.max(0, v) / axisTop) * plotH
                                    }

                                    ctx.fillStyle = "#101010"
                                    ctx.fillRect(0, 0, w, h)
                                    ctx.strokeStyle = "#262626"
                                    ctx.lineWidth = 1
                                    for (var gy = 0; gy <= 4; ++gy) {
                                        var y = Math.round(plotY + (plotH * gy / 4)) + 0.5
                                        ctx.beginPath(); ctx.moveTo(plotX, y); ctx.lineTo(plotX + plotW, y); ctx.stroke()
                                    }
                                    for (var gx = 0; gx <= 6; ++gx) {
                                        var x = Math.round(plotX + (plotW * gx / 6)) + 0.5
                                        ctx.beginPath(); ctx.moveTo(x, plotY); ctx.lineTo(x, plotY + plotH); ctx.stroke()
                                    }

                                    function drawSeries(key, stroke, fill) {
                                        if (samples.length === 0) return
                                        ctx.beginPath()
                                        for (var i = 0; i < samples.length; ++i) {
                                            var x = pxForTime(samples[i].t)
                                            var y = pyForRate(samples[i][key])
                                            if (i === 0) ctx.moveTo(x, y); else ctx.lineTo(x, y)
                                        }
                                        ctx.strokeStyle = stroke
                                        ctx.lineWidth = 1.8
                                        ctx.stroke()

                                        ctx.beginPath()
                                        for (var j = 0; j < samples.length; ++j) {
                                            var fx = pxForTime(samples[j].t)
                                            var fy = pyForRate(samples[j][key])
                                            if (j === 0) ctx.moveTo(fx, fy); else ctx.lineTo(fx, fy)
                                        }
                                        ctx.lineTo(pxForTime(samples[samples.length - 1].t), plotY + plotH)
                                        ctx.lineTo(pxForTime(samples[0].t), plotY + plotH)
                                        ctx.closePath()
                                        ctx.fillStyle = fill
                                        ctx.fill()
                                    }
                                    drawSeries("down", "#4ea2ff", "rgba(78,162,255,0.15)")
                                    drawSeries("up", "#58cc88", "rgba(88,204,136,0.12)")

                                    ctx.fillStyle = "#7c8a99"
                                    ctx.font = "11px sans-serif"
                                    ctx.textAlign = "left"
                                    ctx.textBaseline = "middle"
                                    for (var ly = 0; ly <= 4; ++ly) {
                                        var val = axisTop * (1 - ly / 4)
                                        var ty = plotY + (plotH * ly / 4)
                                        ctx.fillText(root.speedAxisLabel(val), plotX + plotW + 6, ty)
                                    }
                                    ctx.textAlign = "center"
                                    ctx.textBaseline = "top"
                                    for (var lx = 0; lx <= 6; ++lx) {
                                        var secAgo = Math.round(root.speedSpanSeconds * (1 - lx / 6))
                                        var tx = plotX + plotW * lx / 6
                                        var label = secAgo >= 60 ? (Math.round(secAgo / 60) + "m") : (secAgo + "s")
                                        ctx.fillText("-" + label, tx, plotY + plotH + 5)
                                    }

                                    if (root.speedHoverActive) {
                                        var hx = Math.max(plotX, Math.min(plotX + plotW, root.speedHoverX))
                                        ctx.strokeStyle = "rgba(255,255,255,0.30)"
                                        ctx.lineWidth = 1
                                        ctx.beginPath()
                                        ctx.moveTo(hx + 0.5, plotY)
                                        ctx.lineTo(hx + 0.5, plotY + plotH)
                                        ctx.stroke()
                                    }
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                onPositionChanged: function(mouse) {
                                    root.speedHoverActive = true
                                    root.speedHoverX = mouse.x - 10
                                    speedGraphCanvasLoader.requestPaint()
                                }
                                onEntered: {
                                    root.speedHoverActive = true
                                    speedGraphCanvasLoader.requestPaint()
                                }
                                onExited: {
                                    root.speedHoverActive = false
                                    speedGraphCanvasLoader.requestPaint()
                                }
                            }

                            Rectangle {
                                id: speedHoverTip
                                visible: root.speedHoverActive
                                radius: 3
                                color: "#101722"
                                border.color: "#2f465d"
                                anchors.top: parent.top
                                anchors.topMargin: 14
                                x: Math.max(10, Math.min(parent.width - width - 10, root.speedHoverX + 16))
                                width: tipCol.implicitWidth + 12
                                height: tipCol.implicitHeight + 10

                                readonly property var _samples: root.speedVisibleSamples()
                                readonly property real _plotLeft: 8
                                readonly property real _plotRightPad: 56
                                readonly property real _plotWidth: Math.max(1, speedGraphCanvasLoader.width - _plotLeft - _plotRightPad)
                                readonly property real _ratio: Math.max(0, Math.min(1, (root.speedHoverX - _plotLeft) / _plotWidth))
                                readonly property real _targetT: Date.now() - root.speedSpanSeconds * 1000 + (_ratio * root.speedSpanSeconds * 1000)
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
                                        color: "#dbe8f6"
                                        font.pixelSize: 11
                                        font.bold: true
                                    }
                                    Text {
                                        text: speedHoverTip._point ? root.formatAgoNatural(speedHoverTip._ageSec) : ""
                                        color: "#a8b8c8"
                                        font.pixelSize: 10
                                    }
                                    Text {
                                        text: speedHoverTip._point ? ("Down " + root.compactSpeed(speedHoverTip._point.down)) : ""
                                        color: "#8fc0f2"
                                        font.pixelSize: 11
                                    }
                                    Text {
                                        text: speedHoverTip._point ? ("Up   " + root.compactSpeed(speedHoverTip._point.up)) : ""
                                        color: "#97ddb3"
                                        font.pixelSize: 11
                                    }
                                }
                            }
                        }

                        GridLayout {
                            id: speedStatsCard
                            Layout.fillWidth: true
                            Layout.topMargin: 4
                            columns: 8
                            columnSpacing: 12
                            rowSpacing: 4

                            readonly property var _samples: root.speedVisibleSamples()
                            readonly property var _down: root.speedStats(_samples, "down")
                            readonly property var _up: root.speedStats(_samples, "up")

                            Text { text: "Down now"; color: "#7e8b99"; font.pixelSize: 11 }
                            Text { text: root.compactSpeed(speedStatsCard._down.current); color: "#4ea2ff"; font.bold: true; font.pixelSize: 12 }
                            Text { text: "Down avg"; color: "#7e8b99"; font.pixelSize: 11 }
                            Text { text: root.compactSpeed(speedStatsCard._down.avg); color: "#9fc3ea"; font.pixelSize: 12 }
                            Text { text: "Up now"; color: "#7e8b99"; font.pixelSize: 11 }
                            Text { text: root.compactSpeed(speedStatsCard._up.current); color: "#58cc88"; font.bold: true; font.pixelSize: 12 }
                            Text { text: "Up avg"; color: "#7e8b99"; font.pixelSize: 11 }
                            Text { text: root.compactSpeed(speedStatsCard._up.avg); color: "#a8dfbf"; font.pixelSize: 12 }

                            Text { text: "Down peak"; color: "#7e8b99"; font.pixelSize: 11 }
                            Text { text: root.compactSpeed(speedStatsCard._down.max); color: "#6f7d8b"; font.pixelSize: 11 }
                            Text { text: ""; Layout.columnSpan: 2 }
                            Text { text: "Up peak"; color: "#7e8b99"; font.pixelSize: 11 }
                            Text { text: root.compactSpeed(speedStatsCard._up.max); color: "#6f7d8b"; font.pixelSize: 11 }
                            Text { text: ""; Layout.columnSpan: 2 }
                        }
                    }
                }
                // ── Files ─────────────────────────────────────────────────────
                Item {
                    ColumnLayout {
                        anchors.fill: parent; spacing: 0

                        // Header bar
                        Rectangle {
                            id: fileHeader
                            Layout.fillWidth: true; height: 26
                            color: "#2d2d2d"; clip: true
                            Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: "#3a3a3a" }

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
                                        text: "Name"; color: "#b0b0b0"; font.pixelSize: 12; font.bold: true
                                    }
                                    Rectangle { anchors.right: parent.right; width: 1; height: parent.height; color: "#3a3a3a" }
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
                                        text: "Progress"; color: "#b0b0b0"; font.pixelSize: 12; font.bold: true; elide: Text.ElideRight
                                    }
                                    Rectangle { anchors.right: parent.right; width: 1; height: parent.height; color: "#3a3a3a" }
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
                                        text: "Size"; color: "#b0b0b0"; font.pixelSize: 12; font.bold: true; elide: Text.ElideRight
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
                            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                            ScrollBar.horizontal: ScrollBar { policy: ScrollBar.AsNeeded }

                            Text {
                                anchors.centerIn: parent
                                visible: fileList.count === 0
                                text: "No file information available"
                                color: "#666666"; font.pixelSize: 12
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

                                width: Math.max(ListView.view.width, fileList.contentWidth); height: 26
                                color: isFolder ? "#1f1f1f" : (index % 2 === 0 ? "#1c1c1c" : "#222222")

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
                                            text: fd.expanded ? "▾" : "▸"
                                            color: "#888"; font.pixelSize: 11
                                        }
                                        MouseArea {
                                            visible: fd.isFolder; anchors.fill: parent
                                            acceptedButtons: Qt.LeftButton
                                            onClicked: if (root.torrentFileModel) root.torrentFileModel.toggleExpanded(fd.index)
                                        }
                                    }

                                    // Wanted checkbox — shown for both files and folders.
                                    // Toggling a folder entry sets wanted on all its children.
                                    Item {
                                        width: 22; height: parent.height
                                        Rectangle {
                                            anchors.centerIn: parent
                                            width: 14; height: 14; radius: 2
                                            color: fd.wanted ? "#4488dd" : "#1b1b1b"
                                            border.color: fd.wanted ? "#4488dd" : "#3a3a3a"
                                            Text {
                                                visible: fd.wanted; anchors.centerIn: parent
                                                text: "✓"; color: "#fff"
                                                font.pixelSize: 10; font.bold: true
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

                                    // Name — width subtracts: depth-indent, expand-toggle (16),
                                    // checkbox (22), icon (16) + gap (4), outer margins (6+8).
                                    Text {
                                        width: root.fileColName - Math.max(0, fd.depth) * 14 - 16 - 22 - 16
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: safeStr(fd.name)
                                        color: !fd.wanted ? "#555" : (fd.isFolder ? "#e0e0e0" : "#d0d0d0")
                                        font.pixelSize: 12; font.bold: fd.isFolder
                                        elide: Text.ElideMiddle
                                    }

                                    // Progress column: percentage label + bar aligned to column start
                                    Item {
                                        width: root.fileColProgress; height: parent.height

                                        Text {
                                            id: progPctLbl
                                            anchors { left: parent.left; leftMargin: 6; verticalCenter: parent.verticalCenter }
                                            text: Math.round(root.clampPct(fd.progress) * 100) + "%"
                                            color: fd.wanted ? "#b0b0b0" : "#555"
                                            font.pixelSize: 11
                                            width: 34
                                        }

                                        Rectangle {
                                            anchors {
                                                left: progPctLbl.right; leftMargin: 4
                                                right: parent.right; rightMargin: 6
                                                verticalCenter: parent.verticalCenter
                                            }
                                            height: 4; radius: 2
                                            color: "#2a2a2a"
                                            Rectangle {
                                                width: Math.max(0, parent.width * root.clampPct(fd.progress))
                                                height: parent.height; radius: parent.radius
                                                color: fd.wanted ? "#33bb44" : "#555"
                                            }
                                        }
                                    }

                                    // Size
                                    Text {
                                        width: root.fileColSize; anchors.verticalCenter: parent.verticalCenter
                                        text: root.compactBytes(fd.size)
                                        color: fd.wanted ? "#b0b0b0" : "#555"
                                        font.pixelSize: 12; horizontalAlignment: Text.AlignRight
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
                            title: "Rename"
                            color: "#1e1e1e"
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
                                        source: "icons/rename.ico"
                                        sourceSize: Qt.size(16, 16)
                                        fillMode: Image.PreserveAspectFit
                                        asynchronous: true
                                    }
                                    Text {
                                        text: "Rename item"
                                        color: "#e0e0e0"; font.pixelSize: 14; font.bold: true
                                    }
                                }
                                Text {
                                    text: "Enter a new file or folder name:"
                                    color: "#aaaaaa"; font.pixelSize: 12
                                }
                                TextField {
                                    id: renameInput
                                    Layout.fillWidth: true
                                    color: "#d0d0d0"; font.pixelSize: 12
                                    selectByMouse: true
                                    leftPadding: 8
                                    background: Rectangle {
                                        color: "#1b1b1b"
                                        border.color: parent.activeFocus ? "#4488dd" : "#3a3a3a"
                                        radius: 3
                                    }
                                    Keys.onReturnPressed: renameConfirmBtn.clicked()
                                    Keys.onEnterPressed:  renameConfirmBtn.clicked()
                                }
                                RowLayout {
                                    Layout.fillWidth: true; spacing: 8
                                    Item { Layout.fillWidth: true }
                                    DlgButton {
                                        text: "Cancel"
                                        onClicked: renameDialog.close()
                                    }
                                    DlgButton {
                                        id: renameConfirmBtn
                                        text: "Rename"
                                        primary: true
                                        enabled: renameInput.text.trim().length > 0 && renameInput.text.trim() !== renameDialog._currentName
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
                                color: "#252525"
                                border.color: "#3a3a3a"
                                radius: 4
                            }

                            contentItem: Column {
                                spacing: 0

                                Rectangle {
                                    width: 180
                                    height: 34
                                    color: downloadCtxHover.containsMouse ? "#303030" : "transparent"

                                    Row {
                                        anchors.verticalCenter: parent.verticalCenter
                                        anchors.left: parent.left
                                        anchors.leftMargin: 10
                                        spacing: 8

                                        Rectangle {
                                            width: 14
                                            height: 14
                                            radius: 2
                                            color: fileCtxPopup._wanted ? "#4488dd" : "#1b1b1b"
                                            border.color: fileCtxPopup._wanted ? "#4488dd" : "#3a3a3a"
                                            Text {
                                                visible: fileCtxPopup._wanted
                                                anchors.centerIn: parent
                                                text: "✓"
                                                color: "#fff"
                                                font.pixelSize: 10
                                                font.bold: true
                                            }
                                        }

                                        Text {
                                            text: "Download"
                                            color: "#e0e0e0"
                                            font.pixelSize: 12
                                        }
                                    }

                                    MouseArea {
                                        id: downloadCtxHover
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        onClicked: {
                                            if (root.item)
                                                App.setTorrentFileWanted(root.item.id, fileCtxPopup._row, !fileCtxPopup._wanted)
                                            fileCtxPopup.close()
                                        }
                                    }
                                }

                                Rectangle { width: 180; height: 1; color: "#3a3a3a" }

                                Rectangle {
                                    width: 180
                                    height: 34
                                    color: renameCtxHover.containsMouse ? "#303030" : "transparent"

                                    Image {
                                        anchors.verticalCenter: parent.verticalCenter
                                        anchors.left: parent.left
                                        anchors.leftMargin: 10
                                        width: 16
                                        height: 16
                                        source: "icons/rename.ico"
                                        sourceSize: Qt.size(16, 16)
                                        fillMode: Image.PreserveAspectFit
                                        asynchronous: true
                                    }
                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        anchors.left: parent.left
                                        anchors.leftMargin: 32
                                        text: "Rename..."
                                        color: "#e0e0e0"
                                        font.pixelSize: 12
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

                // ── Peers ─────────────────────────────────────────────────────
                Item {
                    // Peer column widths live on root so they survive tab switches.
                    // Each column header cell has a DragHandler resize handle, mirroring
                    // the exact pattern from DownloadTable.qml.
                    readonly property real totalW:
                        root.peerColCountry + root.peerColPeer + root.peerColPort + root.peerColClient +
                        root.peerColProgress + root.peerColDown + root.peerColUp + root.peerColDownloaded + root.peerColUploaded + root.peerColType

                    ColumnLayout {
                        anchors.fill: parent; spacing: 0

                        // Header — styled identically to DownloadTable
                        Rectangle {
                            id: peerHeader
                            Layout.fillWidth: true; height: 26
                            color: "#2d2d2d"; clip: true

                            Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: "#3a3a3a" }

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
                                        color: hdrMa.containsMouse && !rhDrag.active ? "#383838" : "transparent"
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
                                            color: root.peerSortKey === modelData.sortKey ? "#88bbff" : "#b0b0b0"
                                            font.pixelSize: 12; font.bold: true
                                            elide: Text.ElideRight
                                        }

                                        Text {
                                            id: sortArrow
                                            anchors { verticalCenter: parent.verticalCenter; right: rh.left; rightMargin: 4 }
                                            text: root.peerSortAscending ? "▲" : "▼"
                                            color: "#88bbff"; font.pixelSize: 9
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
                                            width: 1; height: parent.height; color: "#3a3a3a"
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
                            ScrollBar.vertical:   ScrollBar { policy: ScrollBar.AsNeeded }
                            ScrollBar.horizontal: ScrollBar { policy: ScrollBar.AsNeeded }
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
                                function onLayoutAboutToBeChanged() {
                                    root.savePeerListViewport()
                                }
                                function onLayoutChanged() {
                                    if (root._suppressPeerViewportRestore) {
                                        root._suppressPeerViewportRestore = false
                                        return
                                    }
                                    if (root._peerViewportRestorePending)
                                        root.restorePeerListViewport()
                                }
                            }

                            Text {
                                anchors.centerIn: parent
                                visible: peerListView.count === 0
                                text: "No peers connected"
                                color: "#666"; font.pixelSize: 12
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

                                width: Math.max(peerListView.width, peerListView.contentWidth)
                                height: 26

                                color: peerRowMa.containsMouse
                                       ? "#2a2a2a"
                                       : (index % 2 === 0 ? "#1c1c1c" : "#222222")

                                MouseArea {
                                    id: peerRowMa; anchors.fill: parent; hoverEnabled: true
                                    ToolTip.visible: containsMouse
                                    ToolTip.text: {
                                        var cc = safeStr(pd.countryCode)
                                        var region = safeStr(pd.regionCode)
                                        var regionName = safeStr(pd.regionName)
                                        var city = safeStr(pd.cityName)
                                        var place = city
                                        if (region && (cc === "US" || cc === "CA"))
                                            place += (place ? ", " : "") + region
                                        else if (regionName)
                                            place += (place ? ", " : "") + regionName
                                        return pd.endpoint + ":" + pd.port + (cc || place ? ("\n" + (pd.countryFlag || "??") + " " + (cc || "??") + (place ? (" - " + place) : "")) : "\nLocation unavailable")
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
                                            Text {
                                                anchors.verticalCenter: parent.verticalCenter
                                                text: {
                                                    var cc = safeStr(pd.countryCode)
                                                    var region = safeStr(pd.regionCode)
                                                    if (cc === "US" || cc === "CA") return region || cc || "--"
                                                    return cc || "--"
                                                }
                                                color: "#d0d0d0"; font.pixelSize: 12; elide: Text.ElideRight
                                            }
                                        }
                                    }
                                    Item {
                                        x: root._peerColXMap["endpoint"] || 0
                                        width: root.peerColPeer; height: parent.height; clip: true
                                        Text {
                                            anchors { fill: parent; leftMargin: 6 }
                                            verticalAlignment: Text.AlignVCenter
                                            text: safeStr(pd.endpoint); color: "#d0d0d0"; font.pixelSize: 12; elide: Text.ElideRight
                                        }
                                    }
                                    Item {
                                        x: root._peerColXMap["port"] || 0
                                        width: root.peerColPort; height: parent.height; clip: true
                                        Text {
                                            anchors { fill: parent; leftMargin: 6 }
                                            verticalAlignment: Text.AlignVCenter
                                            text: pd.port > 0 ? String(pd.port) : ""
                                            color: "#d0d0d0"; font.pixelSize: 12; elide: Text.ElideRight
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
                                                text: root.baseClientName(pd.client); color: "#b0b0b0"; font.pixelSize: 12; elide: Text.ElideRight
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
                                            color: "#b0b0b0"; font.pixelSize: 12
                                        }
                                    }
                                    Item {
                                        x: root._peerColXMap["down"] || 0
                                        width: root.peerColDown; height: parent.height; clip: true
                                        Text {
                                            anchors { fill: parent; leftMargin: 6 }
                                            verticalAlignment: Text.AlignVCenter
                                            text: root.compactSpeed(pd.downSpeed); color: "#ffffff"; font.pixelSize: 12
                                        }
                                    }
                                    Item {
                                        x: root._peerColXMap["up"] || 0
                                        width: root.peerColUp; height: parent.height; clip: true
                                        Text {
                                            anchors { fill: parent; leftMargin: 6 }
                                            verticalAlignment: Text.AlignVCenter
                                            text: root.compactSpeed(pd.upSpeed); color: "#ffffff"; font.pixelSize: 12
                                        }
                                    }
                                    Item {
                                        x: root._peerColXMap["downloaded"] || 0
                                        width: root.peerColDownloaded; height: parent.height; clip: true
                                        Text {
                                            anchors { fill: parent; leftMargin: 6 }
                                            verticalAlignment: Text.AlignVCenter
                                            text: root.compactBytes(pd.downloaded); color: "#d9d9d9"; font.pixelSize: 12
                                        }
                                    }
                                    Item {
                                        x: root._peerColXMap["uploaded"] || 0
                                        width: root.peerColUploaded; height: parent.height; clip: true
                                        Text {
                                            anchors { fill: parent; leftMargin: 6 }
                                            verticalAlignment: Text.AlignVCenter
                                            text: root.compactBytes(pd.uploaded); color: "#d9d9d9"; font.pixelSize: 12
                                        }
                                    }
                                    Item {
                                        x: root._peerColXMap["type"] || 0
                                        width: root.peerColType; height: parent.height; clip: true
                                        Row {
                                            anchors { left: parent.left; leftMargin: 4; verticalCenter: parent.verticalCenter }
                                            spacing: 2
                                            Repeater {
                                                model: pd.flags ? pd.flags.split(" ").filter(function(f){ return f.length > 0 && f !== "OUT" }) : []
                                                delegate: Rectangle {
                                                    required property string modelData
                                                    height: 14; width: badgeLbl.implicitWidth + 6
                                                    radius: 2; color: "transparent"
                                                    border.color: flagBadgeColor(modelData); border.width: 1
                                                    function flagBadgeColor(flag) {
                                                        if (flag === "Seed") return "#c0a54a"
                                                        if (flag === "Peer") return "#7a8899"
                                                        return root.flagColor(flag)
                                                    }
                                                    Text {
                                                        id: badgeLbl
                                                        anchors.centerIn: parent
                                                        text: modelData; color: "white"
                                                        font.pixelSize: 9; font.bold: true
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // Flags legend
                        Row {
                            Layout.fillWidth: true
                            Layout.topMargin: 2
                            Layout.bottomMargin: 2
                            spacing: 6

                            Text {
                                text: "Legend:"
                                color: "#6a8099"
                                font.pixelSize: 10
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            Repeater {
                                model: [
                                    { flag: "OUT",  tip: "Outgoing: you connected to them" },
                                    { flag: "TRK",  tip: "Found via tracker" },
                                    { flag: "DHT",  tip: "Found via DHT (no tracker needed)" },
                                    { flag: "PEX",  tip: "Peer Exchange: another peer referred them" },
                                    { flag: "LSD",  tip: "Local network discovery" },
                                    { flag: "UTP",  tip: "Uses uTP, a protocol that avoids congesting your network" },
                                    { flag: "ENC",  tip: "Traffic is encrypted" },
                                    { flag: "SNB",  tip: "Snubbed: they stopped sending data, probably moving on" },
                                    { flag: "UPO",  tip: "Upload only: they have the full file and are not downloading" },
                                    { flag: "OPT",  tip: "Optimistic unchoke: given a free upload slot to discover better peers" },
                                    { flag: "HPX",  tip: "Holepunched: bypassed a firewall or NAT to connect directly" }
                                ]
                                delegate: Rectangle {
                                    required property var modelData
                                    height: 14
                                    width: lgText.implicitWidth + 6
                                    radius: 2
                                    color: "transparent"
                                    border.color: root.flagColor(modelData.flag)
                                    border.width: 1
                                    anchors.verticalCenter: parent.verticalCenter

                                    Text {
                                        id: lgText
                                        anchors.centerIn: parent
                                        text: modelData.flag
                                        color: "white"
                                        font.pixelSize: 9
                                        font.bold: true
                                    }

                                    ToolTip.visible: lgMa.containsMouse
                                    ToolTip.text: modelData.tip
                                    MouseArea { id: lgMa; anchors.fill: parent; hoverEnabled: true; acceptedButtons: Qt.NoButton }
                                }
                            }
                        }
                    }
                }

                // ── Peer Map ────────────────────────────────────────────────
                Item {
                    Rectangle {
                        anchors.fill: parent
                        color: "#141b24"
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
                                    text: root.activePeerMapModel ? (root.activePeerMapModel.rowCount() + " peers") : "0 peers"
                                    color: "#8ea1b5"
                                    font.pixelSize: 11
                                }
                                Item { Layout.fillWidth: true }

                                // Inactive peers toggle
                                Row {
                                    Layout.alignment: Qt.AlignVCenter
                                    spacing: 5
                                    CheckBox {
                                        id: inactiveCheck
                                        checked: root.peerMapShowInactive
                                        onCheckedChanged: root.peerMapShowInactive = checked
                                        implicitHeight: 20
                                        indicator: Rectangle {
                                            width: 14; height: 14; radius: 2
                                            color: inactiveCheck.checked ? "#4488dd" : "#1b1b1b"
                                            border.color: inactiveCheck.checked ? "#4488dd" : "#3a3a3a"
                                            Text { visible: inactiveCheck.checked; text: "✓"; color: "#fff"; font.pixelSize: 10; anchors.centerIn: parent }
                                        }
                                        contentItem: Item {}
                                    }
                                    Text { text: "Inactive"; color: "#8ea1b5"; font.pixelSize: 11 }
                                }

                                // Tracker dots toggle
                                Row {
                                    Layout.alignment: Qt.AlignVCenter
                                    spacing: 5
                                    CheckBox {
                                        id: trackerDotsCheck
                                        checked: root.peerMapShowTrackers
                                        onCheckedChanged: root.peerMapShowTrackers = checked
                                        implicitHeight: 20
                                        indicator: Rectangle {
                                            width: 14; height: 14; radius: 2
                                            color: trackerDotsCheck.checked ? "#4488dd" : "#1b1b1b"
                                            border.color: trackerDotsCheck.checked ? "#4488dd" : "#3a3a3a"
                                            Text { visible: trackerDotsCheck.checked; text: "✓"; color: "#fff"; font.pixelSize: 10; anchors.centerIn: parent }
                                        }
                                        contentItem: Item {}
                                    }
                                    Text { text: "Trackers"; color: "#8ea1b5"; font.pixelSize: 11 }
                                }

                                Rectangle {
                                    color: "#1a252f"
                                    border.color: "transparent"
                                    radius: 2
                                    implicitHeight: 24
                                    implicitWidth: legendRow.implicitWidth + 16
                                    Row {
                                        id: legendRow
                                        anchors.centerIn: parent
                                        spacing: 10
                                        Rectangle { width: 10; height: 10; radius: 5; color: "#5f93c9"; anchors.verticalCenter: parent.verticalCenter }
                                        Text { text: "Peer"; color: "#b8c5d3"; font.pixelSize: 11; anchors.verticalCenter: parent.verticalCenter }
                                        Rectangle { width: 10; height: 10; radius: 5; color: "#4caf7d"; anchors.verticalCenter: parent.verticalCenter }
                                        Text { text: "Seed"; color: "#b8c5d3"; font.pixelSize: 11; anchors.verticalCenter: parent.verticalCenter }
                                        Rectangle { width: 10; height: 10; radius: 5; color: "#9959e6"; anchors.verticalCenter: parent.verticalCenter }
                                        Text { text: "You"; color: "#b8c5d3"; font.pixelSize: 11; anchors.verticalCenter: parent.verticalCenter }
                                        Rectangle { width: 8; height: 8; radius: 4; color: "#e8d57a"; anchors.verticalCenter: parent.verticalCenter }
                                        Text { text: "Tracker"; color: "#b8c5d3"; font.pixelSize: 11; anchors.verticalCenter: parent.verticalCenter }
                                        // Line type legend
                                        Rectangle { width: 18; height: 2; color: "#5f93c9"; anchors.verticalCenter: parent.verticalCenter }
                                        Text { text: "DL"; color: "#b8c5d3"; font.pixelSize: 11; anchors.verticalCenter: parent.verticalCenter }
                                        Rectangle { width: 18; height: 2; color: "#4caf7d"; anchors.verticalCenter: parent.verticalCenter }
                                        Text { text: "UL"; color: "#b8c5d3"; font.pixelSize: 11; anchors.verticalCenter: parent.verticalCenter }
                                        Rectangle { width: 18; height: 2; color: "#9959e6"; anchors.verticalCenter: parent.verticalCenter }
                                        Text { text: "Both"; color: "#b8c5d3"; font.pixelSize: 11; anchors.verticalCenter: parent.verticalCenter }
                                    }
                                }
                            }

                            Rectangle {
                                id: peerMapFrame
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                color: "#0d141c"
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
                                            source: "icons/world-map.svg"
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
                                            required property double progress   // fraction 0–1; was missing, causing all peers to show 0%

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
                                                border.color: markerMouse.containsMouse ? "#edf3f8" : "#081018"
                                                border.width: 1
                                            }

                                            Rectangle {
                                                visible: false
                                                anchors.bottom: parent.top
                                                anchors.horizontalCenter: parent.horizontalCenter
                                                anchors.bottomMargin: 6
                                                width: 220
                                                implicitHeight: tooltipCol.implicitHeight + 10
                                                color: "#111923"
                                                border.color: "#324555"
                                                radius: 3
                                                z: 10

                                                Column {
                                                    id: tooltipCol
                                                    anchors.fill: parent
                                                    anchors.margins: 5
                                                    spacing: 2

                                                    Text { text: endpoint + ":" + port; color: "#f0f5fb"; font.pixelSize: 11; font.bold: true; elide: Text.ElideRight; width: parent.width }
                                                    Text { text: client; color: "#c5d2de"; font.pixelSize: 11; elide: Text.ElideRight; width: parent.width }
                                                    Text { text: root.peerPlaceText(parent.parent); color: "#95a9bb"; font.pixelSize: 10; elide: Text.ElideRight; width: parent.width }
                                                    Text { text: (isSeed ? "Seed" : "Peer") + " • " + source; color: isSeed ? "#f6b84c" : "#56d27f"; font.pixelSize: 10; width: parent.width }
                                                    Text { text: "Down " + root.compactSpeed(downSpeed) + "  Up " + root.compactSpeed(upSpeed); color: "#9fb6c8"; font.pixelSize: 10; width: parent.width }
                                                    Text { text: "RTT " + (rtt > 0 ? (rtt + " ms") : "--"); color: "#9fb6c8"; font.pixelSize: 10; width: parent.width }
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
                                                border.color: "#081018"; border.width: 1
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
                                            border.color: "#081018"
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
                                        color: "#101821"
                                        border.color: "#314252"
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
                                                    color: "#f0f5fb"
                                                    font.pixelSize: 13
                                                    font.bold: true
                                                    elide: Text.ElideRight
                                                    width: Math.min(implicitWidth, parent.width - portLbl.width - 5)
                                                }
                                                Text {
                                                    id: portLbl
                                                    text: root.peerMapHoverPort
                                                    color: "#6a8099"
                                                    font.pixelSize: 13
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
                                                    text: root.baseClientName(root.peerMapHoverClient)
                                                    color: "#c5d2de"
                                                    font.pixelSize: 12
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
                                                    color: "#95a9bb"
                                                    font.pixelSize: 11
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
                                                    model: {
                                                        var base = root.peerMapHoverIsSeed ? ["Seed"] : ["Peer"]
                                                        var fl = root.peerMapHoverFlags ? root.peerMapHoverFlags.split(" ").filter(function(f){ return f.length > 0 }) : []
                                                        return base.concat(fl)
                                                    }
                                                    delegate: Rectangle {
                                                        required property string modelData
                                                        height: 14
                                                        width: mapBadgeLbl.implicitWidth + 6
                                                        radius: 2
                                                        color: Qt.rgba(0, 0, 0, 0.3)
                                                        border.color: mapFlagColor(modelData)
                                                        border.width: 1

                                                        function mapFlagColor(flag) {
                                                            if (flag === "Seed") return "#c0a54a"
                                                            if (flag === "Peer") return "#7a8899"
                                                            return root.flagColor(flag)
                                                        }

                                                        Text {
                                                            id: mapBadgeLbl
                                                            anchors.centerIn: parent
                                                            text: modelData
                                                            color: "white"
                                                            font.pixelSize: 9
                                                            font.bold: true
                                                        }
                                                    }
                                                }
                                            }

                                            // Speed row
                                            Text {
                                                text: "↓ " + root.compactSpeed(root.peerMapHoverDownSpeed) + "  ↑ " + root.compactSpeed(root.peerMapHoverUpSpeed)
                                                color: "#9fb6c8"
                                                font.pixelSize: 11
                                                width: parent.width
                                            }

                                            // Ping + progress row
                                            Text {
                                                text: "Ping " + (root.peerMapHoverRtt > 0 ? (root.peerMapHoverRtt + " ms") : "—") + "  " + Math.round(root.peerMapHoverProgress * 100) + "% done"
                                                color: "#9fb6c8"
                                                font.pixelSize: 11
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
                                        color: "#101821"
                                        border.color: "#314252"
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
                                                    color: "#f0f5fb"
                                                    font.pixelSize: 13
                                                    font.bold: true
                                                    elide: Text.ElideRight
                                                    width: parent.width - 14
                                                }
                                            }

                                            // Country
                                            Text {
                                                visible: root.peerMapTrackerHoverCountry.length > 0
                                                text: root.peerMapTrackerHoverCountry
                                                color: "#95a9bb"
                                                font.pixelSize: 11
                                                width: parent.width
                                            }

                                            // Divider
                                            Rectangle { width: parent.width; height: 1; color: "#243040" }

                                            // Status
                                            Row {
                                                spacing: 4
                                                Text { text: "Status"; color: "#6a8099"; font.pixelSize: 11 }
                                                Text {
                                                    text: root.peerMapTrackerHoverStatus || "Unknown"
                                                    color: {
                                                        var s = root.peerMapTrackerHoverStatus.toLowerCase()
                                                        if (s === "working") return "#4caf7d"
                                                        if (s === "not contacted") return "#888"
                                                        return "#e8a35c"
                                                    }
                                                    font.pixelSize: 11
                                                    font.bold: true
                                                }
                                            }

                                            // Tier
                                            Row {
                                                visible: root.peerMapTrackerHoverTier >= 0
                                                spacing: 4
                                                Text { text: "Tier"; color: "#6a8099"; font.pixelSize: 11 }
                                                Text { text: String(root.peerMapTrackerHoverTier); color: "#c5d2de"; font.pixelSize: 11 }
                                            }

                                            // Peers reported
                                            Row {
                                                spacing: 4
                                                Text { text: "Peers"; color: "#6a8099"; font.pixelSize: 11 }
                                                Text {
                                                    text: root.peerMapTrackerHoverCount > 0 ? String(root.peerMapTrackerHoverCount) : "—"
                                                    color: "#c5d2de"; font.pixelSize: 11
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
                                        color: "#101821"
                                        border.color: "#314252"
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
                                                    color: "#f0f5fb"
                                                    font.pixelSize: 13
                                                    font.bold: true
                                                    elide: Text.ElideRight
                                                    width: Math.min(implicitWidth, parent.width - youPortLbl.width - 5)
                                                }
                                                Text {
                                                    id: youPortLbl
                                                    text: root.torrentPeerModel ? root.torrentPeerModel.localPort : ""
                                                    color: "#6a8099"
                                                    font.pixelSize: 13
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
                                                    text: "Stellar"
                                                    color: "#c5d2de"
                                                    font.pixelSize: 12
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
                                                    text: root.torrentPeerModel ? root.torrentPeerModel.localCityName : ""
                                                    color: "#95a9bb"
                                                    font.pixelSize: 11
                                                    elide: Text.ElideRight
                                                    width: parent.width - 21
                                                    anchors.verticalCenter: parent.verticalCenter
                                                }
                                            }

                                            Text {
                                                text: "You (this client)"
                                                color: "#66a7ff"
                                                font.pixelSize: 11
                                                width: parent.width
                                            }
                                            Text {
                                                visible: !!root.item
                                                text: Math.round((root.item ? root.item.progress : 0) * 100) + "% done"
                                                color: "#9fb6c8"
                                                font.pixelSize: 11
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
                                        text: "No connected peers to plot"
                                        color: "#708396"
                                        font.pixelSize: 12
                                    }

                                    Text {
                                        anchors.centerIn: parent
                                        visible: !!root.activePeerMapModel && root.activePeerMapModel.rowCount() > 0 && !root.activePeerMapModel.hasLocalLocation
                                        text: "Waiting for your public IP so the local map position can be shown"
                                        color: "#708396"
                                        font.pixelSize: 12
                                    }

                                }
                            }
                        }
                    }
                }

                // ── Trackers ──────────────────────────────────────────────────
                Item {
                    ColumnLayout {
                        anchors { fill: parent; margins: 10 }
                        spacing: 6

                        RowLayout {
                            Layout.fillWidth: true
                            Text { text: "Window"; color: "#8ea1b5"; font.pixelSize: 12 }
                            ComboBox {
                                Layout.preferredWidth: 130
                                model: root.swarmPeriodOptions.map(function(o){ return o.label })
                                currentIndex: root.swarmPeriodIndex
                                onActivated: root.swarmPeriodIndex = currentIndex
                            }
                            Item { Layout.fillWidth: true }
                        }
                        Text {
                            Layout.fillWidth: true
                            text: "Tip: Peers/Seeders come from tracker-reported swarm counts (not just currently connected peers). Ratio is uploaded ÷ downloaded and helps estimate health."
                            color: "#8ea1b5"
                            font.pixelSize: 10
                            wrapMode: Text.WordWrap
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 208
                            spacing: 8

                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 208
                                color: "#171717"
                                border.color: "#2d2d2d"
                                radius: 3
                                ColumnLayout {
                                    anchors { fill: parent; margins: 8 }
                                    spacing: 4
                                    Text { text: "Client Fingerprint Breakdown"; color: "#d7d7d7"; font.pixelSize: 12; font.bold: true }
                                    Text {
                                        text: {
                                            var filtered = root.breakdownExcludedCount(root.swarmClientBreakdown, "client")
                                            return filtered > 0 ? ("Filtered " + String(filtered) + " unknown peers") : "Top identified clients"
                                        }
                                        color: "#8ea1b5"
                                        font.pixelSize: 10
                                    }
                                    RowLayout {
                                        Layout.fillWidth: true
                                        Layout.fillHeight: true
                                        spacing: 8
                                        Canvas {
                                            id: clientPie
                                            Layout.preferredWidth: 168
                                            Layout.preferredHeight: 168
                                            antialiasing: true
                                            renderTarget: Canvas.Image
                                            Component.onCompleted: root.swarmClientPieRef = clientPie
                                            Component.onDestruction: if (root.swarmClientPieRef === clientPie) root.swarmClientPieRef = null
                                            onPaint: {
                                                var ctx = getContext("2d")
                                                ctx.reset()
                                                var rows = root.swarmClientRows
                                                var cx = width / 2
                                                var cy = height / 2
                                                var radius = Math.max(24, Math.min(width, height) / 2 - 2)
                                                if (rows.length === 0) {
                                                    ctx.strokeStyle = "#2d2d2d"
                                                    ctx.lineWidth = 1
                                                    ctx.beginPath(); ctx.arc(cx, cy, radius, 0, Math.PI * 2); ctx.stroke()
                                                    return
                                                }
                                                var totalPct = 0
                                                for (var t = 0; t < rows.length; ++t)
                                                    totalPct += Math.max(0, Number(rows[t].pct) || 0)
                                                totalPct = Math.max(0.000001, totalPct)
                                                var start = -Math.PI / 2
                                                for (var i = 0; i < rows.length; ++i) {
                                                    var frac = Math.max(0, Number(rows[i].pct) || 0) / totalPct
                                                    var end = (i === rows.length - 1) ? (-Math.PI / 2 + Math.PI * 2) : (start + frac * Math.PI * 2)
                                                    ctx.beginPath()
                                                    ctx.moveTo(cx, cy)
                                                    ctx.arc(cx, cy, radius, start, end, false)
                                                    ctx.closePath()
                                                    ctx.fillStyle = rows[i].color
                                                    ctx.fill()
                                                    start = end
                                                }
                                            }
                                        }
                                        ListView {
                                            Layout.fillWidth: true
                                            Layout.fillHeight: true
                                            clip: true
                                            spacing: 1
                                            model: root.swarmClientLegendRows
                                            delegate: RowLayout {
                                                required property var modelData
                                                width: ListView.view.width
                                                spacing: 5
                                                Rectangle {
                                                    Layout.preferredWidth: 8
                                                    Layout.preferredHeight: 8
                                                    radius: 4
                                                    color: modelData.color
                                                    border.color: "#0f0f0f"
                                                    border.width: 1
                                                    Layout.alignment: Qt.AlignVCenter
                                                }
                                                Image {
                                                    Layout.preferredWidth: 14
                                                    Layout.preferredHeight: 14
                                                    fillMode: Image.PreserveAspectFit
                                                    source: root.torrentClientIconSource(modelData.label)
                                                    visible: status === Image.Ready
                                                }
                                                Text {
                                                    text: modelData.label
                                                    color: "#b6c0ca"
                                                    font.pixelSize: 11
                                                    Layout.fillWidth: true
                                                    elide: Text.ElideRight
                                                }
                                                Text { text: modelData.pct.toFixed(1) + "%"; color: "#9fb2c6"; font.pixelSize: 11; Layout.preferredWidth: 46; horizontalAlignment: Text.AlignRight }
                                            }
                                        }
                                    }
                                }
                            }

                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 208
                                color: "#171717"
                                border.color: "#2d2d2d"
                                radius: 3
                                ColumnLayout {
                                    anchors { fill: parent; margins: 8 }
                                    spacing: 4
                                    Text { text: "Country Breakdown"; color: "#d7d7d7"; font.pixelSize: 12; font.bold: true }
                                    Text {
                                        text: {
                                            var filtered = root.breakdownExcludedCount(root.swarmCountryBreakdown, "country")
                                            return filtered > 0 ? ("Filtered " + String(filtered) + " unknown peers") : "Top identified countries"
                                        }
                                        color: "#8ea1b5"
                                        font.pixelSize: 10
                                    }
                                    RowLayout {
                                        Layout.fillWidth: true
                                        Layout.fillHeight: true
                                        spacing: 8
                                        Canvas {
                                            id: countryPie
                                            Layout.preferredWidth: 168
                                            Layout.preferredHeight: 168
                                            antialiasing: true
                                            renderTarget: Canvas.Image
                                            Component.onCompleted: root.swarmCountryPieRef = countryPie
                                            Component.onDestruction: if (root.swarmCountryPieRef === countryPie) root.swarmCountryPieRef = null
                                            onPaint: {
                                                var ctx = getContext("2d")
                                                ctx.reset()
                                                var rows = root.swarmCountryRows
                                                var cx = width / 2
                                                var cy = height / 2
                                                var radius = Math.max(24, Math.min(width, height) / 2 - 2)
                                                if (rows.length === 0) {
                                                    ctx.strokeStyle = "#2d2d2d"
                                                    ctx.lineWidth = 1
                                                    ctx.beginPath(); ctx.arc(cx, cy, radius, 0, Math.PI * 2); ctx.stroke()
                                                    return
                                                }
                                                var totalPct = 0
                                                for (var t = 0; t < rows.length; ++t)
                                                    totalPct += Math.max(0, Number(rows[t].pct) || 0)
                                                totalPct = Math.max(0.000001, totalPct)
                                                var start = -Math.PI / 2
                                                for (var i = 0; i < rows.length; ++i) {
                                                    var frac = Math.max(0, Number(rows[i].pct) || 0) / totalPct
                                                    var end = (i === rows.length - 1) ? (-Math.PI / 2 + Math.PI * 2) : (start + frac * Math.PI * 2)
                                                    ctx.beginPath()
                                                    ctx.moveTo(cx, cy)
                                                    ctx.arc(cx, cy, radius, start, end, false)
                                                    ctx.closePath()
                                                    ctx.fillStyle = rows[i].color
                                                    ctx.fill()
                                                    start = end
                                                }
                                            }
                                        }
                                        ListView {
                                            Layout.fillWidth: true
                                            Layout.fillHeight: true
                                            clip: true
                                            spacing: 1
                                            model: root.swarmCountryLegendRows
                                            delegate: RowLayout {
                                                required property var modelData
                                                width: ListView.view.width
                                                spacing: 5
                                                Rectangle {
                                                    Layout.preferredWidth: 8
                                                    Layout.preferredHeight: 8
                                                    radius: 4
                                                    color: modelData.color
                                                    border.color: "#0f0f0f"
                                                    border.width: 1
                                                    Layout.alignment: Qt.AlignVCenter
                                                }
                                                Image {
                                                    Layout.preferredWidth: 18
                                                    Layout.preferredHeight: 12
                                                    fillMode: Image.PreserveAspectFit
                                                    source: root.countryFlagSource(modelData.label)
                                                    visible: status === Image.Ready
                                                }
                                                Text {
                                                    text: modelData.label
                                                    color: "#b6c0ca"
                                                    font.pixelSize: 11
                                                    Layout.fillWidth: true
                                                    elide: Text.ElideRight
                                                }
                                                Text { text: modelData.pct.toFixed(1) + "%"; color: "#9fb2c6"; font.pixelSize: 11; Layout.preferredWidth: 46; horizontalAlignment: Text.AlignRight }
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 178
                            color: "#171717"
                            border.color: "#2d2d2d"
                            radius: 3
                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: 8
                                spacing: 4
                                Text { text: "Live Peer/Seeder/Ratio Chart"; color: "#d7d7d7"; font.pixelSize: 12; font.bold: true }
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 10
                                    readonly property var s: root.swarmLegendSample()
                                    Text { text: "Peers " + String(Number(parent.s.peers) || 0); color: "#4b9cff"; font.pixelSize: 11 }
                                    Text { text: "Seeders " + String(Number(parent.s.seeders) || 0); color: "#66bb7a"; font.pixelSize: 11 }
                                    Text { text: "Ratio " + root.ratioText(parent.s.ratio); color: "#f0c25a"; font.pixelSize: 11 }
                                    Item { Layout.fillWidth: true }
                                    Text { text: root.formatClockTime(parent.s.t); color: "#9fb2c6"; font.pixelSize: 11 }
                                }
                                Item {
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    id: swarmLiveCanvas
                                    Canvas {
                                        id: swarmLivePlot
                                        anchors.fill: parent
                                        antialiasing: true
                                        renderTarget: Canvas.Image
                                        Component.onCompleted: root.swarmLiveCanvasRef = swarmLivePlot
                                        Component.onDestruction: if (root.swarmLiveCanvasRef === swarmLivePlot) root.swarmLiveCanvasRef = null
                                        onPaint: {
                                            var ctx = getContext("2d")
                                            ctx.reset()
                                            var w = width
                                            var h = height
                                            if (w < 40 || h < 40)
                                                return
                                            var top = 12
                                            var right = 60
                                            var bottom = 24
                                            var left = 8
                                            var plotX = left
                                            var plotY = top
                                            var plotW = Math.max(10, w - left - right)
                                            var plotH = Math.max(10, h - top - bottom)
                                            var nowMs = Date.now()
                                            var startMs = nowMs - root.swarmPeriodSeconds * 1000
                                            var samples = root.swarmVisibleSamples().slice(-Math.max(60, Math.round(root.swarmPeriodSeconds / 60)))
                                            var maxPeers = 1
                                            var maxRatio = 1
                                            for (var i = 0; i < samples.length; ++i) {
                                                maxPeers = Math.max(maxPeers, Number(samples[i].peers) || 0, Number(samples[i].seeders) || 0)
                                                maxRatio = Math.max(maxRatio, Number(samples[i].ratio) || 0)
                                            }
                                            var peerScale = Math.pow(10, Math.floor(Math.log(maxPeers) / Math.log(10)))
                                            var peerNorm = maxPeers / peerScale
                                            var peerStep = (peerNorm <= 1) ? 1 : (peerNorm <= 2 ? 2 : (peerNorm <= 5 ? 5 : 10))
                                            var peerAxisTop = Math.max(1, peerStep * peerScale)
                                            while (peerAxisTop < maxPeers) peerAxisTop *= 2
                                            var ratioAxisTop = Math.max(1, Math.ceil(maxRatio * 10) / 10)

                                            function pxForTime(t) {
                                                return plotX + ((t - startMs) / (root.swarmPeriodSeconds * 1000)) * plotW
                                            }
                                            function pyForPeers(v) {
                                                return plotY + plotH - (Math.max(0, v) / peerAxisTop) * plotH
                                            }
                                            function pyForRatio(v) {
                                                return plotY + plotH - (Math.max(0, v) / ratioAxisTop) * plotH
                                            }

                                            ctx.fillStyle = "#101010"
                                            ctx.fillRect(0, 0, w, h)
                                            ctx.strokeStyle = "#262626"
                                            ctx.lineWidth = 1
                                            for (var gy = 0; gy <= 4; ++gy) {
                                                var y = Math.round(plotY + (plotH * gy / 4)) + 0.5
                                                ctx.beginPath(); ctx.moveTo(plotX, y); ctx.lineTo(plotX + plotW, y); ctx.stroke()
                                            }
                                            for (var gx = 0; gx <= 6; ++gx) {
                                                var x = Math.round(plotX + (plotW * gx / 6)) + 0.5
                                                ctx.beginPath(); ctx.moveTo(x, plotY); ctx.lineTo(x, plotY + plotH); ctx.stroke()
                                            }

                                            function drawPeerSeries(key, stroke, fill) {
                                                if (samples.length === 0) return
                                                ctx.beginPath()
                                                for (var i = 0; i < samples.length; ++i) {
                                                    var x = pxForTime(samples[i].t)
                                                    var y = pyForPeers(samples[i][key])
                                                    if (i === 0) ctx.moveTo(x, y); else ctx.lineTo(x, y)
                                                }
                                                ctx.strokeStyle = stroke
                                                ctx.lineWidth = 1.8
                                                ctx.stroke()

                                                ctx.beginPath()
                                                for (var j = 0; j < samples.length; ++j) {
                                                    var fx = pxForTime(samples[j].t)
                                                    var fy = pyForPeers(samples[j][key])
                                                    if (j === 0) ctx.moveTo(fx, fy); else ctx.lineTo(fx, fy)
                                                }
                                                ctx.lineTo(pxForTime(samples[samples.length - 1].t), plotY + plotH)
                                                ctx.lineTo(pxForTime(samples[0].t), plotY + plotH)
                                                ctx.closePath()
                                                ctx.fillStyle = fill
                                                ctx.fill()
                                            }
                                            drawPeerSeries("peers", "#4ea2ff", "rgba(78,162,255,0.15)")
                                            drawPeerSeries("seeders", "#58cc88", "rgba(88,204,136,0.12)")

                                            if (samples.length > 0) {
                                                ctx.strokeStyle = "#f0c25a"
                                                ctx.lineWidth = 1.7
                                                ctx.setLineDash([5, 4])
                                                ctx.beginPath()
                                                for (var k = 0; k < samples.length; ++k) {
                                                    var rx = pxForTime(samples[k].t)
                                                    var ry = pyForRatio(samples[k].ratio)
                                                    if (k === 0) ctx.moveTo(rx, ry); else ctx.lineTo(rx, ry)
                                                }
                                                ctx.stroke()
                                                ctx.setLineDash([])
                                            }

                                            ctx.fillStyle = "#7c8a99"
                                            ctx.font = "11px sans-serif"
                                            ctx.textAlign = "left"
                                            ctx.textBaseline = "middle"
                                            for (var ly = 0; ly <= 4; ++ly) {
                                                var peerVal = peerAxisTop * (1 - ly / 4)
                                                var ty = plotY + (plotH * ly / 4)
                                                ctx.fillText(String(Math.round(peerVal)), plotX + plotW + 6, ty)
                                            }
                                            ctx.textAlign = "center"
                                            ctx.textBaseline = "top"
                                            for (var lx = 0; lx <= 6; ++lx) {
                                                var secAgo = Math.round(root.swarmPeriodSeconds * (1 - lx / 6))
                                                var tx = plotX + plotW * lx / 6
                                                var label = secAgo >= 60 ? (Math.round(secAgo / 60) + "m") : (secAgo + "s")
                                                ctx.fillText("-" + label, tx, plotY + plotH + 5)
                                            }

                                            if (root.swarmLiveHoverActive && samples.length > 0) {
                                                var nx = Math.max(0, Math.min(1, (root.swarmLiveHoverX - plotX) / plotW))
                                                var idx = Math.max(0, Math.min(samples.length - 1, Math.round(nx * (samples.length - 1))))
                                                var sx = plotX + (samples.length <= 1 ? 0 : (plotW * idx / (samples.length - 1)))
                                                var sample = samples[idx]
                                                root.swarmHoverSample = sample
                                                ctx.strokeStyle = "#9fb2c6"
                                                ctx.lineWidth = 1
                                                ctx.beginPath()
                                                ctx.moveTo(sx, plotY)
                                                ctx.lineTo(sx, plotY + plotH)
                                                ctx.stroke()

                                                function dotPeers(color, key) {
                                                    var value = Number(sample[key]) || 0
                                                    var sy = pyForPeers(value)
                                                    ctx.beginPath()
                                                    ctx.arc(sx, sy, 3, 0, Math.PI * 2)
                                                    ctx.fillStyle = color
                                                    ctx.fill()
                                                }
                                                dotPeers("#4ea2ff", "peers")
                                                dotPeers("#58cc88", "seeders")
                                                ctx.beginPath()
                                                ctx.arc(sx, pyForRatio(Number(sample.ratio) || 0), 3, 0, Math.PI * 2)
                                                ctx.fillStyle = "#f0c25a"
                                                ctx.fill()

                                            } else {
                                                root.swarmHoverSample = null
                                            }
                                        }
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        acceptedButtons: Qt.NoButton
                                        onPositionChanged: function(mouse) {
                                            root.swarmLiveHoverX = mouse.x
                                            root.swarmLiveHoverActive = true
                                            if (root.swarmLiveCanvasRef) root.swarmLiveCanvasRef.requestPaint()
                                        }
                                        onExited: {
                                            root.swarmLiveHoverActive = false
                                            root.swarmHoverSample = null
                                            if (root.swarmLiveCanvasRef) root.swarmLiveCanvasRef.requestPaint()
                                        }
                                    }
                                    Rectangle {
                                        visible: root.swarmLiveHoverActive && !!root.swarmHoverSample
                                        radius: 3
                                        color: "#101722"
                                        border.color: "#2f465d"
                                        anchors.top: parent.top
                                        anchors.topMargin: 10
                                        x: Math.max(10, Math.min(parent.width - width - 10, root.swarmLiveHoverX + 14))
                                        width: swarmTipCol.implicitWidth + 12
                                        height: swarmTipCol.implicitHeight + 10
                                        Column {
                                            id: swarmTipCol
                                            anchors.centerIn: parent
                                            spacing: 2
                                            Text {
                                                text: root.swarmHoverSample ? root.formatClockTime(root.swarmHoverSample.t) : ""
                                                color: "#dbe8f6"
                                                font.pixelSize: 11
                                                font.bold: true
                                            }
                                            Text {
                                                text: root.swarmHoverSample ? ("Peers " + String(Number(root.swarmHoverSample.peers) || 0)) : ""
                                                color: "#8fc0f2"
                                                font.pixelSize: 11
                                            }
                                            Text {
                                                text: root.swarmHoverSample ? ("Seeders " + String(Number(root.swarmHoverSample.seeders) || 0)) : ""
                                                color: "#97ddb3"
                                                font.pixelSize: 11
                                            }
                                            Text {
                                                text: root.swarmHoverSample ? ("Ratio " + root.ratioText(root.swarmHoverSample.ratio)) : ""
                                                color: "#f0c25a"
                                                font.pixelSize: 11
                                            }
                                        }
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
                        // DHT/PEX/LSD are virtual "trackers" with no real URL — disable
                        // destructive/copy actions so right-clicking them feels inert.
                        property bool isSystemEntry: false

                        Action {
                            text: "Copy URL"
                            enabled: !trackerCtxMenu.isSystemEntry
                            onTriggered: {
                                if (trackerCtxMenu.trackerUrl.length > 0)
                                    App.copyToClipboard(trackerCtxMenu.trackerUrl)
                            }
                        }
                        MenuSeparator {}
                        Action {
                            text: "Remove tracker"
                            enabled: !trackerCtxMenu.isSystemEntry
                            onTriggered: {
                                if (root.item && trackerCtxMenu.trackerUrl.length > 0)
                                    App.removeTorrentTracker(root.item.id, trackerCtxMenu.trackerUrl)
                            }
                        }
                    }

                    // Add tracker panel — slides in/out from the top
                    ColumnLayout {
                        anchors.fill: parent; spacing: 0

                        // Toolbar row with count + add button
                        Rectangle {
                            Layout.fillWidth: true; height: 34
                            color: "#252525"
                            Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: "#111" }

                            RowLayout {
                                anchors { fill: parent; leftMargin: 10; rightMargin: 10 }
                                Text {
                                    text: "Trackers"
                                    color: "#e0e0e0"; font.pixelSize: 12; font.bold: true
                                }
                                Text {
                                    text: trackerList.count + (trackerList.count === 1 ? " tracker" : " trackers")
                                    color: "#666"; font.pixelSize: 11
                                    leftPadding: 8
                                }
                                Item { Layout.fillWidth: true }
                                DlgButton {
                                    text: root.showTrackerAdd ? "Cancel" : "Add trackers…"
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
                            color: "#1d2030"; border.color: "#2a3050"
                            clip: true
                            visible: root.showTrackerAdd

                            Behavior on Layout.preferredHeight { NumberAnimation { duration: 120 } }

                            ColumnLayout {
                                anchors { fill: parent; margins: 10 }
                                spacing: 6

                                Text {
                                    text: "Paste tracker URLs - one per line. Lines starting with # are ignored."
                                    color: "#8899bb"; font.pixelSize: 11; wrapMode: Text.WordWrap
                                    Layout.fillWidth: true
                                }

                                Rectangle {
                                    Layout.fillWidth: true; Layout.fillHeight: true
                                    color: "#1b1b1b"
                                    border.color: trackerInput.activeFocus ? "#4488dd" : "#3a3a3a"; radius: 2; clip: true

                                    ScrollView {
                                        anchors.fill: parent
                                        TextArea {
                                            id: trackerInput
                                            placeholderText: "udp://tracker.opentrackr.org:1337/announce\nhttps://tracker.example.org/announce"
                                            color: "#d0d0d0"; placeholderTextColor: "#444"
                                            font.pixelSize: 11; wrapMode: TextArea.NoWrap
                                            selectByMouse: true; background: null; padding: 6
                                        }
                                    }
                                }

                                RowLayout {
                                    Layout.fillWidth: true; spacing: 6
                                    Text {
                                        id: addStatusTxt; text: ""
                                        color: "#6aaa6a"; font.pixelSize: 11
                                    }
                                    Item { Layout.fillWidth: true }
                                    DlgButton {
                                        text: "Add"
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
                                            addStatusTxt.text = added + " added" + (failed ? ", " + failed + " failed" : "")
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
                            color: "#2d2d2d"; clip: true
                            Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: "#3a3a3a" }
                            Item {
                                x: -trackerList.contentX
                                width: root.trkColTracker + root.trkColStatus + root.trkColSource + root.trkColSeeders + root.trkColPeers + root.trkColMessage
                                height: parent.height

                                Repeater {
                                    model: root._trkColsOrdered
                                    delegate: Rectangle {
                                        id: trkHdrCell
                                        x: root._trkColXMap[modelData.key] || 0
                                        width: root._trkColW(modelData.key)
                                        height: trackerHeader.height
                                        color: trkHdrMa.containsMouse && !trkRhDrag.active ? "#383838" : "transparent"
                                        opacity: root._trkColDragging && root._trkColDragFromKey === modelData.key ? 0.5 : 1.0

                                        // Insert-before indicator
                                        Rectangle {
                                            anchors.left: parent.left
                                            width: 2; height: parent.height
                                            color: "#4488dd"
                                            visible: root._trkColDragging && root._trkColDragInsertBeforeKey === modelData.key
                                        }

                                        Text {
                                            anchors { verticalCenter: parent.verticalCenter; left: parent.left; leftMargin: 6; right: trkRh.left; rightMargin: 2 }
                                            text: modelData.title; color: "#b0b0b0"; font.pixelSize: 12; font.bold: true; elide: Text.ElideRight
                                        }
                                        Rectangle { anchors.right: parent.right; width: 1; height: parent.height; color: "#3a3a3a" }

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
                                                    if      (k === "tracker") root.trkColTracker = newW
                                                    else if (k === "status")  root.trkColStatus  = newW
                                                    else if (k === "source")  root.trkColSource  = newW
                                                    else if (k === "seeders") root.trkColSeeders = newW
                                                    else if (k === "peers")   root.trkColPeers   = newW
                                                    else if (k === "message") root.trkColMessage = newW
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
                            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                            ScrollBar.horizontal: ScrollBar { policy: ScrollBar.AsNeeded }
                            contentWidth: root.trkColTracker + root.trkColStatus + root.trkColSource + root.trkColSeeders + root.trkColPeers + root.trkColMessage

                            Text {
                                anchors.centerIn: parent
                                visible: trackerList.count === 0
                                text: "No trackers"
                                color: "#666"; font.pixelSize: 12
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
                                required property string message
                                required property bool   isSystemEntry

                                width: Math.max(ListView.view.width, trackerList.contentWidth); height: 28
                                color: trMa.containsMouse
                                       ? "#2a2a2a"
                                       : (index % 2 === 0 ? "#1c1c1c" : "#222222")

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
                                            text: safeStr(trd.url); color: "#d0d0d0"; font.pixelSize: 12; elide: Text.ElideRight
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
                                                if (s.indexOf("error") >= 0 || s.indexOf("fail") >= 0) return "#cc6060"
                                                if (s.indexOf("working") >= 0 || s.indexOf("ok") >= 0) return "#55cc66"
                                                return "#b0b0b0"
                                            }
                                            font.pixelSize: 12; elide: Text.ElideRight
                                        }
                                    }
                                    Item {
                                        x: root._trkColXMap["source"] || 0
                                        width: root.trkColSource; height: parent.height; clip: true
                                        Text {
                                            anchors { fill: parent; leftMargin: 6 }
                                            verticalAlignment: Text.AlignVCenter
                                            text: safeStr(trd.source); color: "#b0b0b0"; font.pixelSize: 12; elide: Text.ElideRight
                                        }
                                    }
                                    Item {
                                        x: root._trkColXMap["seeders"] || 0
                                        width: root.trkColSeeders; height: parent.height; clip: true
                                        Text {
                                            anchors { fill: parent; leftMargin: 6 }
                                            verticalAlignment: Text.AlignVCenter
                                            text: String(trd.seeders | 0); color: "#c0a54a"; font.pixelSize: 12
                                        }
                                    }
                                    Item {
                                        x: root._trkColXMap["peers"] || 0
                                        width: root.trkColPeers; height: parent.height; clip: true
                                        Text {
                                            anchors { fill: parent; leftMargin: 6 }
                                            verticalAlignment: Text.AlignVCenter
                                            text: String(trd.peers | 0); color: "#b0b0b0"; font.pixelSize: 12
                                        }
                                    }
                                    Item {
                                        x: root._trkColXMap["message"] || 0
                                        width: root.trkColMessage; height: parent.height; clip: true
                                        Text {
                                            anchors { fill: parent; leftMargin: 6 }
                                            verticalAlignment: Text.AlignVCenter
                                            text: safeStr(trd.message).length > 0 ? safeStr(trd.message) : (trd.isSystemEntry ? "" : ("Tier " + String(trd.tier | 0)))
                                            color: "#8ea1b5"; font.pixelSize: 12; elide: Text.ElideRight
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
            }
        }
    }
}
