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
import Qt.labs.platform
import QtQuick.Controls
// Also makes MenuItem/Menu resolve to Controls rather than Qt.labs.platform.
import QtQuick.Controls.Material
import QtQuick.Layouts
import QtCore

// Everything shown for one download: the HTTP/FTP property sheet, or the
// torrent summary + General/Speed/Files/Peers/... tabs. Hosted by
// FilePropertiesWindow (one window per download) and, embedded, by the main
// window's torrent details pane (follows the table selection).
//
// Not itself a window any more; the file keeps its name because it is the
// qsTr() context of every string here, which all 77 translations are keyed on.
Item {
    id: root

    // On the content (not just the hosting window) so the nested Rename / Peer
    // Info / Add-sources windows inherit it too — without it their text
    // selection falls back to Material's default pink accent.
    Material.theme: ColorPalette.materialTheme
    Material.foreground: ColorPalette.textPrimary
    Material.background: ColorPalette.materialBg
    Material.accent: ColorPalette.accent

    // Set by the host while the view is actually on screen. Gates every live
    // libtorrent model, timer and poll, so a hidden dialog or collapsed pane
    // costs nothing.
    property bool active: false
    // Docked in the main window instead of a dialog: the summary header is
    // dropped (the table row already shows it) and the selected tab survives
    // switching to another torrent.
    property bool embedded: false
    // The Loader swapped between the HTTP and torrent layouts.
    signal layoutSwapped()
    // Footer "Close" (dialog only).
    signal closeRequested()

    // Torrent windows are titled after the torrent so several open properties
    // windows can be told apart in the taskbar.
    readonly property string windowTitle: {
        if (!_isTorrent) return qsTr("File Properties")
        var name = safeStr(item.filename)
        return name.length > 0 ? qsTr("%1 Properties").arg(name) : qsTr("Torrent Properties")
    }

    property var item: null
    readonly property bool _isTorrent: item ? !!item.isTorrent : false
    readonly property bool _isYtdlp: item ? !!item.isYtdlp : false
    readonly property var torrentFileModel:    _isTorrent ? App.torrentFileModel(item.id)    : null
    readonly property var torrentPeerModel:    _isTorrent ? App.torrentPeerModel(item.id)    : null
    readonly property var torrentTrackerModel: _isTorrent ? App.torrentTrackerModel(item.id) : null
    readonly property bool peerListActive: active && _isTorrent && currentTab === 3
    readonly property bool peerMapActive: active && _isTorrent && currentTab === 4
    readonly property bool peerUpdatesActive: active && _isTorrent && (currentTab === 3 || currentTab === 4)
    // Tab 2 = Files. Gate the per-tick file_progress() walk in libtorrent on
    // whether the user can actually see the file list - when hidden, skip the
    // expensive piece-granularity scan entirely.
    readonly property bool fileUpdatesActive: active && _isTorrent && currentTab === 2
    readonly property bool trackerTabActive:  active && _isTorrent && currentTab === 5
    // Gate tracker model rebuilds (QUrl parse + geo-IP + status snapshot lookups
    // per tracker ? per torrent) on tracker tab visibility.

    // Leases follow the model, not just the tab: the embedded pane swaps item
    // while a tab stays open, and the previous torrent must stop updating.
    TorrentLiveUpdatesLease {
        model: root.torrentFileModel
        wanted: root.fileUpdatesActive
        onAcquired: if (root.item) App.refreshTorrentModelsNow(root.item.id)
    }
    TorrentLiveUpdatesLease {
        model: root.torrentTrackerModel
        wanted: root.trackerTabActive
        onAcquired: if (root.item) App.refreshTorrentModelsNow(root.item.id)
    }
    TorrentLiveUpdatesLease {
        model: root.torrentPeerModel
        wanted: root.peerUpdatesActive
        onAcquired: if (root.item) App.refreshTorrentModelsNow(root.item.id)
    }
    readonly property bool webSeedsTabActive: active && _isTorrent && currentTab === 6
    readonly property var activePeerListModel: peerListActive ? torrentPeerModel : null
    readonly property var activePeerMapModel: peerMapActive ? torrentPeerModel : null
    readonly property var activeTrackerListModel: trackerTabActive ? torrentTrackerModel : null
    readonly property var activeTrackerMapModel: (peerMapActive && App.settings.swarmMapShowTrackers) ? torrentTrackerModel : null
    readonly property string _torrentStatusText: item ? safeStr(item.status) : ""
    readonly property bool _torrentIsMoving: _torrentStatusText === "Moving"
    readonly property bool _torrentHasSpeedLimit: !!item && ((item.perTorrentDownLimitKBps | 0) > 0 || (item.perTorrentUpLimitKBps | 0) > 0)
    readonly property string _torrentComment: item ? safeStr(item.torrentComment).trim() : ""

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
    property string trkColOrderJson:  '["icon","tracker","status","source","seeders","peers","nextAnnounce","message"]'
    property string fileColOrderJson: '["name","progress","size","remaining","availability","priority"]'

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
        // Tracker favicon; zero-width (hidden) while torrentTrackerFavicons is off.
        { title: "",                    key: "icon",          sortKey: "" },
        { title: qsTr("Tracker"),       key: "tracker",       sortKey: "tracker" },
        { title: qsTr("Status"),        key: "status",        sortKey: "status" },
        { title: qsTr("Source"),        key: "source",        sortKey: "source" },
        { title: qsTr("Seeders"),       key: "seeders",       sortKey: "seeders" },
        { title: qsTr("Peers"),         key: "peers",         sortKey: "peers" },
        { title: qsTr("Next Announce"), key: "nextAnnounce",  sortKey: "nextAnnounce" },
        { title: qsTr("Message"),       key: "message",       sortKey: "message" }
    ]
    readonly property var _fileColDefs: [
        { title: qsTr("Name"),         key: "name" },
        { title: qsTr("Progress"),     key: "progress" },
        { title: qsTr("Size"),         key: "size" },
        { title: qsTr("Remaining"),    key: "remaining" },
        { title: qsTr("Availability"), key: "availability" },
        { title: qsTr("Priority"),     key: "priority" }
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
        var _w = _trkColsTotalW
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
        var _w = _fileColsTotalW
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
    property real fileColName:         420
    property real fileColProgress:     100
    property real fileColSize:          80
    property real fileColRemaining:     80
    property real fileColAvailability:  80
    property real fileColPriority:     110
    readonly property real _fileColsTotalW: fileColName + fileColProgress + fileColSize
                                            + fileColRemaining + fileColAvailability + fileColPriority

    // Tracker list column widths
    readonly property real trkColIcon: 26
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
    // Torrent tab strip, in StackLayout page order (currentTab indexes this).
    readonly property var torrentTabTitles: [qsTr("General"), qsTr("Speed"), qsTr("Files"), qsTr("Peers"), qsTr("Swarm Map"),
                                             qsTr("Trackers"), qsTr("Web Seeds"), qsTr("Piece Map"), qsTr("Settings")]
    // HTTP/FTP tabs, docked pane only (the properties window shows one sheet).
    // Same indices as the torrent General/Speed pages, so the speed plumbing
    // keys off currentTab === 1 for both.
    readonly property var httpTabTitles: [qsTr("General"), qsTr("Speed")]
    readonly property bool _httpTabs: embedded && !_isTorrent
    readonly property int tabCount: _isTorrent ? torrentTabTitles.length : (_httpTabs ? httpTabTitles.length : 1)
    readonly property bool speedTabActive: active && !!item && currentTab === 1 && (_isTorrent || _httpTabs)
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


    // Speed history state (torrent Speed tab). `tick` is the x-axis label step.
    readonly property var speedSpanOptions: [
        { label: qsTr("1m"),  value: 60,    tick: 15 },
        { label: qsTr("5m"),  value: 300,   tick: 60 },
        { label: qsTr("15m"), value: 900,   tick: 180 },
        { label: qsTr("1h"),  value: 3600,  tick: 900 },
        { label: qsTr("6h"),  value: 21600, tick: 3600 },
        { label: qsTr("24h"), value: 86400, tick: 14400 }
    ]
    property int speedSpanIndex: 2
    readonly property var _speedSpan: speedSpanOptions[Math.max(0, Math.min(speedSpanIndex, speedSpanOptions.length - 1))]
    readonly property int speedSpanSeconds: _speedSpan.value
    // Latest AppController::speedSeries() result (null = nothing yet).
    property var speedSeries: null
    // Y ceiling; only changes when the data outgrows it or shrinks well below
    // it, so the scale holds still between refreshes.
    property real _speedAxisTop: 0
    // Bucket under the mouse, -1 when not hovering the plot.
    property int speedHoverBucket: -1
    property var speedGraphCanvasRef: null
    // Plot insets inside the graph frame, shared by painting and hover mapping.
    // The plot runs edge to edge; axis labels are drawn inside it.
    readonly property real _speedPlotLeft: 0
    readonly property real _speedPlotRight: 0
    // Room for the one-line readout band above the plot.
    readonly property real _speedPlotTop: Math.round(18 * App.fontScale) + 14
    readonly property real _speedPlotBottom: 18

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
        property alias fileColPriority: root.fileColPriority
        property alias fileColRemaining: root.fileColRemaining
        property alias fileColAvailability: root.fileColAvailability
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
        property alias speedSpanIndex: root.speedSpanIndex
    }

    onItemChanged:  {
        if (!embedded)
            currentTab = 0
        speedSeries = null
        _speedAxisTop = 0
        speedHoverBucket = -1
        if (torrentPeerModel) torrentPeerModel.sortBy(peerSortKey, peerSortAscending)
        if (root.item)
            refreshSpeedHistory()
        root.loadSwarmStatsForCurrent()
    }
    onActiveChanged: {
        if (active)
            root.loadSwarmStatsForCurrent()
        else
            root.persistSwarmStatsForCurrent()
    }
    onPeerUpdatesActiveChanged: root.syncPeerStructuralUpdates()
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
    onSpeedSpanSecondsChanged: {
        // A new span is a different scale; don't carry the old ceiling over.
        _speedAxisTop = 0
        speedHoverBucket = -1
        refreshSpeedHistory()
    }

    Timer {
        id: speedHistoryTimer
        // Torrent speeds are published on the 2 s alert tick; polling faster
        // would only redraw the same values.
        interval: 2000
        repeat: true
        running: root.speedTabActive
        // Also the only repaint path: painting straight from speed/stats
        // signals used stale data and flickered the graph every alert tick.
        onTriggered: root.refreshSpeedHistory()
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
            return "../icons/app/stellar.png"
        if (name.indexOf("qbittorrent") !== -1 || name.indexOf("qbittorrent enhanced") !== -1)
            return "../icons/torrent-client-logos/qbittorrent.png"
        if (name.indexOf("transmission") !== -1)
            return "../icons/torrent-client-logos/transmission.png"
        if (name.indexOf("deluge") !== -1)
            return "../icons/torrent-client-logos/deluge.png"
        if (name.indexOf("ktorrent") !== -1)
            return "../icons/torrent-client-logos/ktorrent.png"
        if (name.indexOf("tixati") !== -1)
            return "../icons/torrent-client-logos/tixati-icon.png"
        if (name.indexOf("picotorrent") !== -1)
            return "../icons/torrent-client-logos/picotorrent.png"
        if (name.indexOf("biglybt") !== -1 || name.indexOf("vuze") !== -1 || name.indexOf("azureus") !== -1)
            return name.indexOf("biglybt") !== -1
                ? "../icons/torrent-client-logos/biglybt.png"
                : "../icons/torrent-client-logos/vuze.png"
        if (name.indexOf("utorrent") !== -1 || name.indexOf("\u00b5torrent") !== -1 || name.indexOf("\u03bctorrent") !== -1 || name.indexOf("microtorrent") !== -1)
            return "../icons/torrent-client-logos/utorrent.png"
        if (name.indexOf("bitcomet") !== -1)
            return "../icons/torrent-client-logos/bitcomet.png"
        if (name.indexOf("bittorrent") !== -1)
            return "../icons/torrent-client-logos/bittorrent.png"
        if (name.indexOf("bitlord") !== -1)
            return "../icons/torrent-client-logos/BitLord_logo_2022.png"
        if (name.indexOf("frostwire") !== -1)
            return "../icons/torrent-client-logos/frostwire.png"
        if (name.indexOf("folx") !== -1)
            return "../icons/torrent-client-logos/folx.png"
        if (name.indexOf("libretorrent") !== -1)
            return "../icons/torrent-client-logos/libretorrent.png"
        if (name.indexOf("libtorrent") !== -1 || name.indexOf("rasterbar") !== -1)
            return "../icons/torrent-client-logos/Libtorrent-rasterbar-logo.png"
        if (name.indexOf("elementum") !== -1)
            return "../icons/torrent-client-logos/elementum.png"
        if (name.indexOf("fdm") !== -1 || name.indexOf("free download manager") !== -1)
            return "../icons/torrent-client-logos/FDM.png"
        if (name.indexOf("xunlei") !== -1 || name.indexOf("thunder") !== -1)
            return "../icons/torrent-client-logos/XunLei.png"
        if (name.indexOf("mediaget") !== -1)
            return "../icons/torrent-client-logos/MediaGet2.png"
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
    function refreshSpeedHistory() {
        if (!item) {
            speedSeries = null
            return
        }
        var plotW = speedGraphCanvasRef
            ? speedGraphCanvasRef.width - _speedPlotLeft - _speedPlotRight : 600
        // About 3 px per bucket: dense enough to follow the curve, coarse enough
        // that every point is an average of real samples.
        var buckets = Math.max(20, Math.min(600, Math.floor(plotW / 3)))
        var series = App.speedSeries(item.id, speedSpanSeconds, buckets)
        var peak = 0
        for (var i = 0; i < series.down.length; ++i)
            peak = Math.max(peak, series.down[i], series.up[i])
        // Grow at once so nothing is clipped; shrink only once the data uses
        // under 40 % of the height, so small wobbles don't rescale the plot.
        if (peak > _speedAxisTop * 0.95 || peak < _speedAxisTop * 0.4)
            _speedAxisTop = speedAxisCeiling(peak)
        if (speedHoverBucket >= series.down.length)
            speedHoverBucket = -1
        speedSeries = series
        if (speedGraphCanvasRef)
            speedGraphCanvasRef.requestPaint()
    }
    // Smallest round ceiling above bps whose quarters are round too (four grid
    // bands), in the unit the axis labels will use. Floor of 4 KB/s so an idle
    // torrent still gets a readable axis.
    function speedAxisCeiling(bps) {
        var v = Math.max(Number(bps) || 0, 4096) * 1.05
        var steps = [1, 2, 3, 4, 5, 6, 8, 10, 12, 16, 20, 30, 40, 50, 60, 80,
                     100, 120, 160, 200, 300, 400, 500, 600, 800]
        var unit = 1
        while (unit < 1073741824 && v > 800 * unit)
            unit *= 1024
        for (var i = 0; i < steps.length; ++i) {
            if (steps[i] * unit >= v)
                return steps[i] * unit
        }
        return 1024 * unit
    }
    // Axis label in the unit of the axis ceiling so every label on one axis
    // shares a unit ("250 KB/s, 500 KB/s ..." rather than mixing B, KB, MB).
    function speedAxisLabel(bps, top) {
        var units = ["B/s", "KB/s", "MB/s", "GB/s"]
        var u = 0
        var scale = 1
        while (u < units.length - 1 && top >= 1024 * scale) {
            scale *= 1024
            ++u
        }
        return parseFloat((bps / scale).toFixed(2)) + " " + units[u]
    }
    function speedTickLabel(secondsAgo) {
        if (secondsAgo <= 0) return qsTr("now")
        if (secondsAgo % 3600 === 0) return "-" + (secondsAgo / 3600) + "h"
        if (secondsAgo % 60 === 0) return "-" + (secondsAgo / 60) + "m"
        return "-" + secondsAgo + "s"
    }
    // Centre time of a bucket; the live bucket sits at "now" rather than in the
    // future half it hasn't reached yet.
    function speedBucketTime(series, i) {
        return Math.min(series.startMs + (i + 0.5) * series.bucketMs, series.nowMs)
    }
    // "host:port" that stays unambiguous for IPv6 ("[2001:db8::1]:51413").
    function formatEndpoint(ip, port) {
        var host = safeStr(ip)
        if (host.indexOf(":") !== -1)
            host = "[" + host + "]"
        var p = Number(port) | 0
        return p > 0 ? host + ":" + p : host
    }
    // Host part of a tracker URL, without scheme, credentials, port or path;
    // bracketed IPv6 literals keep their brackets off and their colons intact.
    function urlHost(url) {
        var m = /^[a-z][a-z0-9+.-]*:\/\/(?:[^@\/]*@)?(\[[^\]]+\]|[^:\/?#]+)/i.exec(safeStr(url))
        if (!m)
            return safeStr(url)
        return m[1].charAt(0) === "[" ? m[1].slice(1, -1) : m[1]
    }
    // ── World map projection ─────────────────────────────────────────────
    // icons/images/world-map-*.svg is Natural Earth 110m in plate carrée,
    // fitted to the data's bounding box: lon -180..180 and lat 83.645..-90 land
    // on viewBox x 1..799 and y 1..385.91, at 798/360 px per degree on both
    // axes. Every map here (swarm map, peer info) places points through these.
    readonly property var worldMap: ({ width: 800, height: 387, x0: 1, y0: 1, pxPerDeg: 798 / 360, latTop: 83.64513 })
    function worldMapX(longitude, width) {
        var lon = Number(longitude)
        lon = isFinite(lon) ? Math.max(-180, Math.min(180, lon)) : 0
        return (worldMap.x0 + (lon + 180) * worldMap.pxPerDeg) / worldMap.width * width
    }
    function worldMapY(latitude, height) {
        var lat = Number(latitude)
        lat = isFinite(lat) ? Math.max(-90, Math.min(worldMap.latTop, lat)) : 0
        return (worldMap.y0 + (worldMap.latTop - lat) * worldMap.pxPerDeg) / worldMap.height * height
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

        var lx = root.worldMapX(root.torrentPeerModel.localLongitude, width)
        var ly = root.worldMapY(root.torrentPeerModel.localLatitude, height)
        var px = root.worldMapX(peer.longitude, width)
        var py = root.worldMapY(peer.latitude, height)
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
    function flagTip(flag) {
        switch (flag) {
        case "IN":  return qsTr("Incoming: they connected to you")
        case "OUT": return qsTr("Outgoing: you connected to them")
        case "TRK": return qsTr("Found via tracker")
        case "DHT": return qsTr("Found via DHT (no tracker needed)")
        case "PEX": return qsTr("Found through another peer you're connected to")
        case "LSD": return qsTr("Found on your local network (same Wi-Fi or LAN)")
        case "UTP": return qsTr("Connected over uTP (UDP) instead of TCP. uTP backs off when your connection is busy, so browsing and calls stay responsive")
        case "ENC": return qsTr("Traffic is encrypted")
        case "SNB": return qsTr("Stalled: they haven't sent any data in a while")
        case "UPO": return qsTr("They already have the whole file and are only uploading")
        case "OPT": return qsTr("Given a trial upload slot to see if they're worth keeping")
        case "HPX": return qsTr("Connected through a firewall using another peer's help")
        case "I2P": return qsTr("Connected over the I2P anonymous network")
        default:    return flag
        }
    }
    function peerMapColor(peer) {
        if (!peer)
            return "#5f93c9"
        return peer.isSeed ? "#4caf7d" : "#5f93c9"
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
        if (key === "icon")          return App.settings.torrentTrackerFavicons ? trkColIcon : 0
        if (key === "tracker")       return trkColTracker
        if (key === "status")        return trkColStatus
        if (key === "source")        return trkColSource
        if (key === "seeders")       return trkColSeeders
        if (key === "peers")         return trkColPeers
        if (key === "nextAnnounce")  return trkColNextAnnounce
        if (key === "message")       return trkColMessage
        return 80
    }
    readonly property real _trkColsTotalW: (App.settings.torrentTrackerFavicons ? trkColIcon : 0)
        + trkColTracker + trkColStatus + trkColSource + trkColSeeders + trkColPeers + trkColNextAnnounce + trkColMessage
    function _fileColW(key) {
        if (key === "name")         return fileColName
        if (key === "progress")     return fileColProgress
        if (key === "size")         return fileColSize
        if (key === "remaining")    return fileColRemaining
        if (key === "availability") return fileColAvailability
        if (key === "priority")     return fileColPriority
        return 80
    }
    function _setFileColW(key, w) {
        if (key === "name")              fileColName = Math.max(180, w)
        else if (key === "progress")     fileColProgress = Math.max(60, w)
        else if (key === "size")         fileColSize = Math.max(50, w)
        else if (key === "remaining")    fileColRemaining = Math.max(50, w)
        else if (key === "availability") fileColAvailability = Math.max(50, w)
        else if (key === "priority")     fileColPriority = Math.max(60, w)
    }

    // Priority display helpers. -1 = Mixed (folder with differing children).
    function priorityLabel(p) {
        if (p === -1) return qsTr("Mixed")
        if (p === 1)  return qsTr("Low")
        if (p === 6)  return qsTr("High")
        if (p === 7)  return qsTr("Maximum")
        return qsTr("Normal")
    }
    function priorityColor(p) {
        // Theme-aware primary text; Mixed dimmed.
        return p === -1 ? ColorPalette.textDisabled : ColorPalette.textPrimary
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
        torrentPeerModel.setStructuralUpdatesDeferred(active && _isTorrent && currentTab === 3 && moving)
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
        running: root.active && root._isTorrent
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
    // Plain text cell of a Files-tab row, placed by the column map.
    component FileCell: Text {
        height: parent ? parent.height : 24
        leftPadding: 6; rightPadding: 6
        verticalAlignment: Text.AlignVCenter
        font.pixelSize: 12 * App.fontScale
        elide: Text.ElideRight
    }

    // One line per direction: the live rate up front, the
    // span's average / peak / total muted after it.
    component SpeedLine: Row {
        id: speedLine
        property string label
        property color swatch
        property real current: 0
        property real avg: -1
        property real peak: -1
        property real total: -1
        // Off when the readout band is too narrow for avg/peak/total.
        property bool showStats: true
        spacing: 6
        Rectangle {
            width: 10; height: 2
            color: speedLine.swatch
            anchors.verticalCenter: parent.verticalCenter
        }
        Text {
            text: speedLine.label
            color: ColorPalette.textSecond
            font.pixelSize: 12 * App.fontScale
        }
        // Left-aligned in a slot sized for the widest likely value, so the
        // stats after it don't shift as the speed changes.
        TextMetrics {
            id: speedValueMetrics
            font.pixelSize: 12 * App.fontScale
            font.weight: Font.DemiBold
            text: "000.0 MB/s"
        }
        Text {
            width: Math.max(implicitWidth, speedValueMetrics.advanceWidth)
            text: root.compactSpeed(speedLine.current)
            color: ColorPalette.textPrimary
            font.pixelSize: 12 * App.fontScale
            font.weight: Font.DemiBold
        }
        Text {
            leftPadding: 6
            visible: speedLine.showStats && speedLine.avg >= 0
            text: qsTr("avg %1").arg(root.compactSpeed(speedLine.avg)) + "   "
                  + qsTr("peak %1").arg(root.compactSpeed(speedLine.peak)) + "   "
                  + qsTr("%1 total").arg(root.compactBytes(speedLine.total))
            color: ColorPalette.textMuted
            font.pixelSize: 11 * App.fontScale
            anchors.verticalCenter: parent.verticalCenter
        }
    }

    // Speed tab page: the graph fills the page edge to edge; the readout and
    // span picker float over its top band. Shared by the torrent tabs and the
    // docked HTTP pane (only one is loaded at a time).
    component SpeedPage: Item {
        Rectangle {
            id: speedGraphFrame
            anchors.fill: parent
            color: ColorPalette.cardBg

            readonly property real plotW: width - root._speedPlotLeft - root._speedPlotRight
            readonly property real plotH: height - root._speedPlotTop - root._speedPlotBottom

            function xForTime(series, t) {
                var spanMs = root.speedSpanSeconds * 1000
                return root._speedPlotLeft + (t - (series.nowMs - spanMs)) / spanMs * plotW
            }
            function yForRate(v) {
                var top = Math.max(1, root._speedAxisTop)
                return root._speedPlotTop + plotH - Math.min(1, Math.max(0, v) / top) * plotH
            }

            Canvas {
                id: speedGraphCanvas
                anchors.fill: parent
                renderTarget: Canvas.Image
                Component.onCompleted: root.speedGraphCanvasRef = speedGraphCanvas
                Component.onDestruction: {
                    if (root.speedGraphCanvasRef === speedGraphCanvas)
                        root.speedGraphCanvasRef = null
                }
                // Bucket count follows the plot width.
                onWidthChanged: Qt.callLater(root.refreshSpeedHistory)
                onHeightChanged: requestPaint()

                onPaint: {
                    var ctx = getContext("2d")
                    ctx.reset()
                    var frame = speedGraphFrame
                    var left = root._speedPlotLeft
                    var topY = root._speedPlotTop
                    var pw = frame.plotW
                    var ph = frame.plotH
                    if (pw < 40 || ph < 30)
                        return
                    var axisTop = Math.max(1, root._speedAxisTop)
                    ctx.font = Math.round(10 * App.fontScale) + "px sans-serif"

                    // Grid: four bands, labels share the ceiling's unit.
                    ctx.lineWidth = 1
                    ctx.textBaseline = "top"
                    ctx.textAlign = "left"
                    for (var g = 0; g <= 4; ++g) {
                        var gy = Math.round(topY + ph * g / 4) + 0.5
                        ctx.strokeStyle = g === 4 ? ColorPalette.border : ColorPalette.dividerBg
                        ctx.beginPath(); ctx.moveTo(left, gy); ctx.lineTo(left + pw, gy); ctx.stroke()
                        if (g === 4)
                            continue
                        ctx.fillStyle = ColorPalette.textMuted
                        ctx.fillText(root.speedAxisLabel(axisTop * (1 - g / 4), axisTop), left + 6, gy + 3)
                    }

                    // Time ticks counted back from "now" at the span's step.
                    var spanSec = root.speedSpanSeconds
                    var tick = root._speedSpan.tick
                    ctx.textBaseline = "top"
                    for (var k = 0; k * tick <= spanSec; ++k) {
                        var tx = left + pw * (1 - k * tick / spanSec)
                        ctx.textAlign = k === 0 ? "right" : (k * tick === spanSec ? "left" : "center")
                        if (k === 0) tx -= 6
                        else if (k * tick === spanSec) tx += 6
                        ctx.fillStyle = ColorPalette.textMuted
                        ctx.fillText(root.speedTickLabel(k * tick), tx, topY + ph + 4)
                    }

                    var series = root.speedSeries
                    if (!series)
                        return
                    var spanStart = series.nowMs - spanSec * 1000

                    // Straight segments between bucket averages (a spline
                    // overshoots spikes and invents speeds that never
                    // happened); buckets without data break the line.
                    function drawSeries(values, color, fillAlpha) {
                        var run = []
                        function flush() {
                            if (run.length === 0)
                                return
                            var baseY = topY + ph
                            ctx.beginPath()
                            ctx.moveTo(run[0][0], baseY)
                            for (var a = 0; a < run.length; ++a)
                                ctx.lineTo(run[a][0], run[a][1])
                            ctx.lineTo(run[run.length - 1][0], baseY)
                            ctx.closePath()
                            ctx.fillStyle = Qt.rgba(color.r, color.g, color.b, fillAlpha)
                            ctx.fill()
                            ctx.beginPath()
                            ctx.moveTo(run[0][0], run[0][1])
                            for (var b = 1; b < run.length; ++b)
                                ctx.lineTo(run[b][0], run[b][1])
                            if (run.length === 1)
                                ctx.lineTo(run[0][0] + 1, run[0][1])
                            ctx.strokeStyle = color
                            ctx.lineWidth = 1.5
                            ctx.stroke()
                            run = []
                        }
                        for (var i = 0; i < values.length; ++i) {
                            var t = root.speedBucketTime(series, i)
                            if (values[i] < 0 || t < spanStart) {
                                flush()
                                continue
                            }
                            run.push([frame.xForTime(series, t), frame.yForRate(values[i])])
                        }
                        flush()
                    }
                    // Upload first so download draws on top.
                    if (root._isTorrent)
                        drawSeries(series.up, ColorPalette.progressGreen, 0.12)
                    drawSeries(series.down, ColorPalette.progressDownloading, 0.18)
                }
            }

            Canvas {
                id: speedHoverCanvas
                anchors.fill: parent
                renderTarget: Canvas.Image
                onPaint: {
                    var ctx = getContext("2d")
                    ctx.reset()
                    var series = root.speedSeries
                    var i = root.speedHoverBucket
                    if (!series || i < 0 || series.down[i] < 0)
                        return
                    var frame = speedGraphFrame
                    var x = Math.round(frame.xForTime(series, root.speedBucketTime(series, i))) + 0.5
                    ctx.strokeStyle = ColorPalette.textMuted
                    ctx.lineWidth = 1
                    ctx.beginPath()
                    ctx.moveTo(x, root._speedPlotTop)
                    ctx.lineTo(x, root._speedPlotTop + frame.plotH)
                    ctx.stroke()
                    var dots = [[series.down[i], ColorPalette.progressDownloading]]
                    if (root._isTorrent)
                        dots.unshift([series.up[i], ColorPalette.progressGreen])
                    for (var d = 0; d < dots.length; ++d) {
                        ctx.beginPath()
                        ctx.arc(x, frame.yForRate(dots[d][0]), 3, 0, 2 * Math.PI)
                        ctx.fillStyle = dots[d][1]
                        ctx.fill()
                    }
                }
                Connections {
                    target: root
                    function onSpeedHoverBucketChanged() { speedHoverCanvas.requestPaint() }
                    function onSpeedSeriesChanged() { speedHoverCanvas.requestPaint() }
                }
            }

            Text {
                anchors.centerIn: parent
                visible: {
                    var s = root.speedSeries
                    if (!s) return true
                    for (var i = 0; i < s.down.length; ++i)
                        if (s.down[i] >= 0) return false
                    return true
                }
                text: qsTr("No speed recorded in this period yet")
                color: ColorPalette.textMuted
                font.pixelSize: 12 * App.fontScale
            }

            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                function bucketAt(mx) {
                    var s = root.speedSeries
                    if (!s || mx < root._speedPlotLeft || mx > root._speedPlotLeft + speedGraphFrame.plotW)
                        return -1
                    var spanMs = root.speedSpanSeconds * 1000
                    var t = s.nowMs - spanMs + (mx - root._speedPlotLeft) / speedGraphFrame.plotW * spanMs
                    var i = Math.floor((t - s.startMs) / s.bucketMs)
                    return Math.max(0, Math.min(s.down.length - 1, i))
                }
                onPositionChanged: function(mouse) { root.speedHoverBucket = bucketAt(mouse.x) }
                onExited: root.speedHoverBucket = -1
            }

            Rectangle {
                id: speedHoverTip
                readonly property var _s: root.speedSeries
                readonly property int _i: root.speedHoverBucket
                readonly property bool _has: !!_s && _i >= 0 && _i < _s.down.length && _s.down[_i] >= 0
                readonly property real _x: _has ? speedGraphFrame.xForTime(_s, root.speedBucketTime(_s, _i)) : 0
                visible: _has
                // Beside the hover line, flipped left near the right edge.
                x: _x + 12 + width < speedGraphFrame.width - 4 ? _x + 12 : _x - 12 - width
                y: root._speedPlotTop + 4
                width: tipGrid.implicitWidth + 16
                height: tipGrid.implicitHeight + 10
                radius: 3
                color: ColorPalette.tooltipBg
                border.color: ColorPalette.tooltipBorder

                GridLayout {
                    id: tipGrid
                    anchors.centerIn: parent
                    columns: 2
                    columnSpacing: 10
                    rowSpacing: 2
                    Text {
                        Layout.columnSpan: 2
                        text: speedHoverTip._has ? root.formatClockTime(root.speedBucketTime(speedHoverTip._s, speedHoverTip._i)) : ""
                        color: ColorPalette.tooltipText
                        font.pixelSize: 11 * App.fontScale
                        font.bold: true
                    }
                    Text { text: qsTr("Download"); color: ColorPalette.textSecond; font.pixelSize: 11 * App.fontScale }
                    Text {
                        Layout.alignment: Qt.AlignRight
                        text: speedHoverTip._has ? root.compactSpeed(speedHoverTip._s.down[speedHoverTip._i]) : ""
                        color: ColorPalette.tooltipText
                        font.pixelSize: 11 * App.fontScale
                    }
                    Text { visible: root._isTorrent; text: qsTr("Upload"); color: ColorPalette.textSecond; font.pixelSize: 11 * App.fontScale }
                    Text {
                        visible: root._isTorrent
                        Layout.alignment: Qt.AlignRight
                        text: speedHoverTip._has ? root.compactSpeed(speedHoverTip._s.up[speedHoverTip._i]) : ""
                        color: ColorPalette.tooltipText
                        font.pixelSize: 11 * App.fontScale
                    }
                }
            }

            // ── Readout band (above the plot, same surface) ─────────────
            // The avg/peak/total figures are dropped when they'd run into the
            // span picker. Decided from an invisible full-width copy: measuring
            // the shown row would flip-flop, as hiding the stats shrinks it.
            SpeedReadout {
                id: speedReadoutFull
                x: 8; y: 6
                opacity: 0
                enabled: false
            }
            SpeedReadout {
                x: 8; y: 6
                showStats: speedReadoutFull.implicitWidth <= speedSpanPicker.x - 8 - 16
            }

            // Span picker: plain labels, the current one underlined.
            Row {
                id: speedSpanPicker
                anchors { right: parent.right; top: parent.top; rightMargin: 8; topMargin: 6 }
                spacing: 2
                Repeater {
                    model: root.speedSpanOptions
                    delegate: Item {
                        required property var modelData
                        required property int index
                        readonly property bool current: root.speedSpanIndex === index
                        width: spanLabel.implicitWidth + 14
                        height: 20
                        Text {
                            id: spanLabel
                            anchors.centerIn: parent
                            text: modelData.label
                            color: parent.current ? ColorPalette.textPrimary
                                 : spanMouse.containsMouse ? ColorPalette.textSecond : ColorPalette.textMuted
                            font.pixelSize: 11 * App.fontScale
                            font.weight: parent.current ? Font.DemiBold : Font.Normal
                        }
                        Rectangle {
                            visible: parent.current
                            anchors { bottom: parent.bottom; horizontalCenter: parent.horizontalCenter }
                            width: spanLabel.implicitWidth; height: 2
                            color: ColorPalette.accent
                        }
                        MouseArea {
                            id: spanMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.speedSpanIndex = index
                        }
                    }
                }
            }
        }
    }

    // Flat tab strip over a StackLayout page set; currentTab indexes `titles`.
    component TabStrip: Rectangle {
        id: tabStrip
        required property var titles
        Layout.fillWidth: true; height: 34
        color: ColorPalette.panelBg

        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: ColorPalette.border }

        Row {
            anchors.fill: parent; spacing: 0
            Repeater {
                model: tabStrip.titles
                delegate: Rectangle {
                    required property var modelData
                    required property int index
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
                    MouseArea {
                        id: tabHov; anchors.fill: parent; hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.currentTab = index
                    }
                }
            }
        }
    }

    // Speed tab readout: download and (torrents) upload lines side by side.
    component SpeedReadout: Row {
        property bool showStats: true
        readonly property var _s: root.speedSeries
        spacing: 24
        SpeedLine {
            label: qsTr("Download")
            swatch: ColorPalette.progressDownloading
            current: root.item ? root.item.speed : 0
            avg: parent._s ? parent._s.downAvg : -1
            peak: parent._s ? parent._s.downPeak : -1
            total: parent._s ? parent._s.downBytes : -1
            showStats: parent.showStats
        }
        SpeedLine {
            visible: root._isTorrent
            label: qsTr("Upload")
            swatch: ColorPalette.progressGreen
            current: root.item ? root.item.torrentUploadSpeed : 0
            avg: parent._s ? parent._s.upAvg : -1
            peak: parent._s ? parent._s.upPeak : -1
            total: parent._s ? parent._s.upBytes : -1
            showStats: parent.showStats
        }
    }

    // Action beside a ReadOnlyField (Move..., Copy): a text link, so it doesn't
    // squeeze the field the way a button does.
    component SheetLink: SettingsLink {
        Layout.alignment: Qt.AlignVCenter
    }

        // ?? File chooser ?????????????????????????????????????????????????????????
    FileDialog {
        id: moveFileDialog
        title: _isTorrent ? qsTr("Move Torrent Data To...") : qsTr("Move File To...")
        fileMode: FileDialog.SaveFile
        folder: {
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
            var newPath = pathFromFileUrl(file)
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
            var newPath = pathFromFileUrl(folder)
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
            onLoaded: root.layoutSwapped()
        }

        RowLayout {
            // The docked pane relies on the main toolbar instead.
            visible: !root.embedded
            Layout.fillWidth: true
            Layout.leftMargin: 12
            Layout.rightMargin: 12
            Layout.bottomMargin: 8
            Layout.topMargin: 8
            spacing: 6
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
            DlgButton { text: qsTr("Close"); primary: true; onClicked: root.closeRequested() }
        }
    }

    // ??????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????
    // Regular HTTP/FTP file layout
    // ??????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????
    Component {
        id: regularLayout
        ColumnLayout {
            spacing: root._httpTabs ? 0 : 8

            // Header card (the docked pane sits under the table row instead)
            Rectangle {
                visible: !root.embedded
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

            TabStrip {
                visible: root._httpTabs
                titles: root.httpTabTitles
            }

            StackLayout {
                Layout.fillWidth: true; Layout.fillHeight: true
                currentIndex: root._httpTabs ? root.currentTab : 0

                // Details card
                Rectangle {
                    color: ColorPalette.cardBg; border.width: 0; radius: root._httpTabs ? 0 : 3

                    ScrollView {
                        id: regularScrollView
                        // Flush right so the scrollbar sits at the edge (see
                        // generalScrollView).
                        anchors { fill: parent; topMargin: 8; bottomMargin: 8; leftMargin: 8 }
                        clip: true
                        rightPadding: regularScrollView.ScrollBar.vertical.visible ? regularScrollView.ScrollBar.vertical.width + 6 : 8
                        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
                        ScrollBar.vertical.policy: ScrollBar.AsNeeded

                        ColumnLayout {
                            width: regularScrollView.availableWidth
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

                                // yt-dlp signs in with browser cookies, never with these.
                                Text { visible: !root._isYtdlp; text: qsTr("Login"); color: ColorPalette.textSecond; font.pixelSize: 12 * App.fontScale; font.bold: true }
                                TextField {
                                    visible: !root._isYtdlp
                                    Layout.fillWidth: true; implicitHeight: 26
                                    text: root.item ? safeStr(root.item.username) : ""
                                    color: ColorPalette.textPrimary; font.pixelSize: 12 * App.fontScale
                                    background: Rectangle { color: ColorPalette.inputBg; border.color: parent.activeFocus ? "#4488dd" : ColorPalette.border; radius: 2 }
                                    leftPadding: 6; topPadding: 0; bottomPadding: 0
                                    onTextChanged: if (root.item && text !== root.item.username) App.setDownloadUsername(root.item.id, text)
                                }

                                Text { visible: !root._isYtdlp; text: qsTr("Password"); color: ColorPalette.textSecond; font.pixelSize: 12 * App.fontScale; font.bold: true }
                                TextField {
                                    visible: !root._isYtdlp
                                    Layout.fillWidth: true; implicitHeight: 26
                                    text: root.item ? safeStr(root.item.password) : ""
                                    echoMode: TextInput.Password
                                    color: ColorPalette.textPrimary; font.pixelSize: 12 * App.fontScale
                                    background: Rectangle { color: ColorPalette.inputBg; border.color: parent.activeFocus ? "#4488dd" : ColorPalette.border; radius: 2 }
                                    leftPadding: 6; topPadding: 0; bottomPadding: 0
                                    onTextChanged: if (root.item && text !== root.item.password) App.setDownloadPassword(root.item.id, text)
                                }
                            }
                        }
                    }
                }

                SpeedPage {}
            }
        }
    }

    //??????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????
    // Torrent layout
    // ??????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????
    Component {
        id: torrentLayout
        ColumnLayout {
            // Tab pages sit flush under the tab strip; each page sets its own
            // inner padding.
            spacing: 0

            AddTorrentSourcesDialog {
                id: addSourcesDialog
                transientParent: root.Window.window
                onAdded: (mode, count) => {
                    if (mode === "webSeeds") webSeedsTab._rebuildModel()
                    else if (root.item) App.refreshTorrentModelsNow(root.item.id)
                }
            }

            // ?? Summary header ????????????????????????????????????????????????
            // Compact two-row layout: icon + title/status + ETA on row 1; progress
            // bar with percent + down/up speed + seeders/peers on row 2. The full
            // stats grid lives on the General tab.
            Rectangle {
                visible: !root.embedded
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
                        TorrentProgressBar {
                            Layout.fillWidth: true
                            implicitHeight: 5
                            item: root.item
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

            TabStrip { titles: root.torrentTabTitles }

            // ?? Tab pages ?????????????????????????????????????????????????????
            StackLayout {
                Layout.fillWidth: true; Layout.fillHeight: true
                currentIndex: root.currentTab

                // ?? General ???????????????????????????????????????????????????
                Item {
                    ScrollView {
                        id: generalScrollView
                        // Flush with the pane's right edge so the scrollbar sits
                        // there; the page's right margin is padding instead.
                        anchors { fill: parent; topMargin: 8; bottomMargin: 4; leftMargin: 14 }
                        clip: true
                        // The scrollbar overlays the content: while it shows, the
                        // margin becomes its width so the right-hand links (Move...,
                        // Copy) stay clear of it.
                        rightPadding: generalScrollView.ScrollBar.vertical.visible ? generalScrollView.ScrollBar.vertical.width + 6 : 14
                        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
                        ScrollBar.vertical.policy: ScrollBar.AsNeeded

                        // Plain property sheet: three titled groups, muted keys,
                        // primary values, no tinted values or boxed cards. Every
                        // key is a SheetKey so the value columns line up across
                        // the groups.
                        ColumnLayout {
                            width: generalScrollView.availableWidth
                            spacing: 4

                            SectionHeader { text: qsTr("Transfer") }

                            GridLayout {
                                Layout.fillWidth: true
                                columns: 6; columnSpacing: 10; rowSpacing: 2

                                SheetKey   { text: qsTr("Downloaded") }
                                SheetValue { text: root.item ? root.compactBytes(root.item.torrentDownloaded) : "-" }
                                SheetKey   { text: qsTr("Uploaded") }
                                SheetValue { text: root.item ? root.compactBytes(root.item.torrentUploaded) : "-" }
                                SheetKey   { text: qsTr("Share ratio") }
                                SheetValue { text: root.item ? root.ratioText(root.item.torrentRatio) : "-" }

                                SheetKey   { text: qsTr("Pieces") }
                                SheetValue {
                                    text: {
                                        if (!root.item) return "-"
                                        var done = root.item.torrentPiecesDone | 0
                                        var total = root.item.torrentPiecesTotal | 0
                                        if (total <= 0) return done > 0 ? String(done) : "-"
                                        return done + " / " + total + " (" + Math.round(done / total * 100) + "%)"
                                    }
                                }
                                SheetKey   { text: qsTr("Availability") }
                                SheetValue {
                                    text: { if (!root.item) return "-"; var av = root.item.torrentAvailability; return (typeof av === "number" && av > 0) ? av.toFixed(2) : "-" }
                                }
                                SheetKey   { text: qsTr("Wasted") }
                                SheetValue {
                                    text: { if (!root.item) return "-"; var w = root.item.torrentWastedBytes; return (w > 0) ? root.compactBytes(w) : "-" }
                                }

                                SheetKey   { text: qsTr("Connections") }
                                SheetValue { text: root.item ? String(root.item.torrentConnections | 0) : "-" }
                                SheetKey   { text: qsTr("Active time") }
                                SheetValue { text: root.item ? root.formatDuration(root.item.torrentActiveTimeSecs) : "-" }
                                SheetKey   { text: qsTr("Seed time") }
                                SheetValue { text: root.item ? root.formatDuration(root.item.torrentSeedingTimeSecs) : "-" }

                                // Only present when a per-torrent cap is set, so an
                                // unlimited torrent has no row of "Unlimited".
                                SheetKey {
                                    text: qsTr("Speed limit")
                                    visible: root._torrentHasSpeedLimit
                                }
                                SheetValue {
                                    Layout.columnSpan: 5
                                    visible: root._torrentHasSpeedLimit
                                    text: {
                                        if (!root.item) return ""
                                        var d = root.item.perTorrentDownLimitKBps | 0
                                        var u = root.item.perTorrentUpLimitKBps   | 0
                                        return "↓ " + (d > 0 ? d + " KB/s" : qsTr("Unlimited"))
                                             + "    ↑ " + (u > 0 ? u + " KB/s" : qsTr("Unlimited"))
                                    }
                                }
                            }

                            SectionHeader { text: qsTr("Location"); Layout.topMargin: 7 }

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 10
                                SheetKey { text: qsTr("Save to") }
                                ReadOnlyField { Layout.fillWidth: true; fieldText: root.item ? safeStr(root.item.savePath) : "" }
                                SheetLink {
                                    text: qsTr("Move...")
                                    enabled: !!root.item && !root._torrentIsMoving
                                    onClicked: moveTorrentDialog.open()
                                }
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 10
                                SheetKey { text: qsTr("Category") }
                                StyledComboBox {
                                    id: categoryCombo
                                    Layout.preferredWidth: 180
                                    implicitHeight: 26
                                    model: App.categoryModel
                                    textRole: "categoryLabel"
                                    valueRole: "categoryId"
                                    font.pixelSize: 12 * App.fontScale
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
                                }
                                Text {
                                    Layout.leftMargin: 8
                                    text: qsTr("Note")
                                    color: ColorPalette.textSecond
                                    font.pixelSize: 12 * App.fontScale
                                }
                                TextField {
                                    Layout.fillWidth: true
                                    implicitHeight: 26
                                    text: root.item ? safeStr(root.item.description) : ""
                                    color: ColorPalette.textPrimary; font.pixelSize: 12 * App.fontScale
                                    background: Rectangle { color: ColorPalette.inputBg; border.color: parent.activeFocus ? ColorPalette.borderFocus : ColorPalette.border; radius: 2 }
                                    leftPadding: 6; topPadding: 0; bottomPadding: 0
                                    onTextChanged: if (root.item && text !== root.item.description) App.setDownloadDescription(root.item.id, text)
                                }
                            }

                            SectionHeader { text: qsTr("Torrent"); Layout.topMargin: 7 }

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 10
                                SheetKey { text: qsTr("Info hash") }
                                ReadOnlyField { Layout.fillWidth: true; fieldText: root.item ? safeStr(root.item.torrentInfoHash) : "" }
                                SheetLink {
                                    text: qsTr("Copy")
                                    enabled: !!root.item && safeStr(root.item.torrentInfoHash).length > 0
                                    onClicked: App.copyToClipboard(safeStr(root.item.torrentInfoHash))
                                }
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 10
                                SheetKey { text: qsTr("Source") }
                                ReadOnlyField { Layout.fillWidth: true; fieldText: root.item ? safeStr(root.item.torrentSource) : "" }
                                SheetLink {
                                    text: qsTr("Copy")
                                    enabled: !!root.item && safeStr(root.item.torrentSource).length > 0
                                    onClicked: App.copyToClipboard(safeStr(root.item.torrentSource))
                                }
                            }

                            GridLayout {
                                Layout.fillWidth: true
                                columns: 6; columnSpacing: 10; rowSpacing: 2

                                SheetKey   { text: qsTr("Added") }
                                SheetValue { text: root.item ? (safeStr(root.item.addedDateStr) || "-") : "-" }
                                SheetKey   { text: qsTr("Created on") }
                                SheetValue { text: root.item ? (safeStr(root.item.torrentCreatedOn) || "-") : "-" }
                                SheetKey   { text: qsTr("Created by") }
                                SheetValue { text: root.item ? (safeStr(root.item.torrentCreator) || "-") : "-" }

                                SheetKey   { text: qsTr("Private") }
                                SheetValue { text: (!!root.item && root.item.torrentIsPrivate) ? qsTr("Yes") : qsTr("No") }
                                SheetKey   { text: qsTr("Metadata") }
                                SheetValue { text: (!!root.item && root.item.torrentHasMetadata) ? qsTr("Available") : qsTr("Fetching…") }
                                Item { Layout.columnSpan: 2 }

                                SheetKey {
                                    text: qsTr("Comment")
                                    visible: root._torrentComment.length > 0
                                    Layout.alignment: Qt.AlignTop
                                }
                                SheetValue {
                                    Layout.columnSpan: 5
                                    visible: root._torrentComment.length > 0
                                    text: root._torrentComment
                                    elide: Text.ElideNone
                                    wrapMode: Text.Wrap
                                    maximumLineCount: 4
                                }
                            }
                        }
                    }
                }

                SpeedPage {}
                // ?? Files ?????????????????????????????????????????????????????
                Item {
                    ColumnLayout {
                        anchors.fill: parent; spacing: 0

                        // Header: drag a title to reorder, drag its right edge to resize.
                        Rectangle {
                            id: fileHeader
                            Layout.fillWidth: true; height: 26
                            color: ColorPalette.dividerBg; clip: true
                            Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: ColorPalette.border }

                            Item {
                                x: -fileList.contentX
                                width: root._fileColsTotalW
                                height: parent.height

                                Repeater {
                                    model: root._fileColsOrdered
                                    delegate: Rectangle {
                                        required property var modelData
                                        required property int index
                                        x: root._fileColXMap[modelData.key] || 0
                                        width: root._fileColW(modelData.key)
                                        height: fileHeader.height
                                        color: fHdrMa.containsMouse && !fRhDrag.active ? ColorPalette.border : "transparent"
                                        opacity: root._fileColDragging && root._fileColDragFromKey === modelData.key ? 0.5 : 1.0

                                        // Insert-before indicator (left edge)
                                        Rectangle {
                                            width: 2; height: parent.height
                                            color: ColorPalette.accent
                                            visible: root._fileColDragging && root._fileColDragInsertBeforeKey === modelData.key
                                        }
                                        // Insert-after-last indicator
                                        Rectangle {
                                            anchors.right: parent.right
                                            width: 2; height: parent.height
                                            color: ColorPalette.accent
                                            visible: root._fileColDragging && root._fileColDragInsertBeforeKey === "__end__"
                                                     && index === root._fileColsOrdered.length - 1
                                        }

                                        Text {
                                            anchors { verticalCenter: parent.verticalCenter; left: parent.left; leftMargin: 6
                                                      right: fRh.left; rightMargin: 2 }
                                            text: modelData.title
                                            color: ColorPalette.textPrimary
                                            font.pixelSize: 12 * App.fontScale; font.bold: true
                                            elide: Text.ElideRight
                                        }

                                        MouseArea {
                                            id: fHdrMa
                                            anchors { fill: parent; rightMargin: 10 }
                                            hoverEnabled: true
                                            cursorShape: root._fileColDragging ? Qt.ClosedHandCursor : Qt.ArrowCursor
                                            onPressed: {
                                                root._fileColDragFromKey = modelData.key
                                                root._fileColDragging = true
                                            }
                                            onPositionChanged: {
                                                if (!root._fileColDragging) return
                                                var mx = mapToItem(fileHeader, mouseX, 0).x + fileList.contentX
                                                var insertKey = "__end__"
                                                for (var i = 0; i < root._fileColsOrdered.length; i++) {
                                                    var col = root._fileColsOrdered[i]
                                                    if (mx < (root._fileColXMap[col.key] || 0) + root._fileColW(col.key) / 2) { insertKey = col.key; break }
                                                }
                                                root._fileColDragInsertBeforeKey = insertKey
                                            }
                                            onReleased: {
                                                if (root._fileColDragging && root._fileColDragInsertBeforeKey !== "")
                                                    root._applyFileColReorder()
                                                root._fileColDragFromKey = ""
                                                root._fileColDragInsertBeforeKey = ""
                                                root._fileColDragging = false
                                            }
                                        }

                                        Rectangle { anchors.right: parent.right; width: 1; height: parent.height; color: ColorPalette.border }

                                        // Resize handle
                                        Item {
                                            id: fRh; width: 10; height: parent.height; anchors.right: parent.right; z: 10
                                            property real _startW: 0
                                            Rectangle { anchors.right: parent.right; width: 2; height: parent.height
                                                color: (fRhDrag.active || fRhHov.hovered) ? "#6aa0ff" : "transparent"; opacity: 0.8 }
                                            HoverHandler { id: fRhHov; cursorShape: Qt.SizeHorCursor }
                                            DragHandler {
                                                id: fRhDrag; target: null; xAxis.enabled: true; yAxis.enabled: false; cursorShape: Qt.SizeHorCursor
                                                onActiveChanged: if (active) fRh._startW = root._fileColW(modelData.key)
                                                onTranslationChanged: if (active) root._setFileColW(modelData.key, Math.round(fRh._startW + translation.x))
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        ListView {
                            id: fileList
                            Layout.fillWidth: true; Layout.fillHeight: true
                            clip: true; model: root.torrentFileModel; spacing: 0
                            contentWidth: root._fileColsTotalW
                            flickableDirection: Flickable.HorizontalAndVerticalFlick
                            boundsBehavior: Flickable.StopAtBounds
                            cacheBuffer: 520
                            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                            ScrollBar.horizontal: ScrollBar { policy: ScrollBar.AsNeeded }

                            Text {
                                anchors.centerIn: parent
                                visible: fileList.count === 0
                                text: qsTr("No file information available")
                                color: ColorPalette.textDisabled; font.pixelSize: 12 * App.fontScale
                            }

                            // Cells are fixed Items placed by the column map (no Repeater
                            // in a ListView delegate — a context per cell is too slow).
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
                                required property int    priority
                                required property double remaining
                                required property double availability

                                readonly property color textColor: wanted ? ColorPalette.textPrimary : ColorPalette.textDisabled

                                width: Math.max(fileList.width, fileList.contentWidth); height: 24
                                // Hover tint as in the Peers list. A HoverHandler (not a
                                // MouseArea's containsMouse) so the row stays lit over the
                                // expander and checkbox inside it.
                                color: fileRowHover.hovered ? ColorPalette.border
                                     : isFolder ? ColorPalette.toolbarBg
                                     : (index % 2 === 0 ? ColorPalette.windowBg : ColorPalette.rowAltBg)
                                HoverHandler { id: fileRowHover }

                                // Double-click: folders expand/collapse, files open. Below
                                // the cells so the expander and checkbox keep their clicks.
                                MouseArea {
                                    anchors.fill: parent
                                    acceptedButtons: Qt.LeftButton
                                    onDoubleClicked: {
                                        if (fd.isFolder) {
                                            if (root.torrentFileModel) root.torrentFileModel.toggleExpanded(fd.index)
                                        } else if (root.item) {
                                            App.openTorrentEntry(root.item.id, fd.path)
                                        }
                                    }
                                }

                                // Name: indent, expander, wanted checkbox, icon, name.
                                Item {
                                    x: root._fileColXMap["name"] || 0
                                    width: root.fileColName; height: parent.height
                                    clip: true
                                    Row {
                                        anchors { fill: parent; leftMargin: 4 }
                                        spacing: 0
                                        Item { width: Math.max(0, fd.depth) * 16; height: parent.height }
                                        Item {
                                            width: 18; height: parent.height
                                            TreeExpander {
                                                visible: fd.isFolder
                                                anchors.centerIn: parent
                                                expanded: fd.expanded
                                            }
                                            MouseArea {
                                                visible: fd.isFolder; anchors.fill: parent
                                                onClicked: if (root.torrentFileModel) root.torrentFileModel.toggleExpanded(fd.index)
                                            }
                                        }
                                        // Toggling a folder sets wanted on all its children.
                                        Item {
                                            width: 22; height: parent.height
                                            Rectangle {
                                                anchors.centerIn: parent
                                                width: 14; height: 14; radius: 2
                                                color: fd.wanted ? ColorPalette.accent : ColorPalette.inputBg
                                                border.color: fd.wanted ? ColorPalette.accent : ColorPalette.border
                                                Text {
                                                    visible: fd.wanted; anchors.centerIn: parent
                                                    text: "✓"; color: "#ffffff"
                                                    font.pixelSize: 10 * App.fontScale; font.bold: true
                                                }
                                            }
                                            MouseArea {
                                                anchors.fill: parent; enabled: !!root.item
                                                onClicked: App.setTorrentFileWanted(root.item.id, fd.index, !fd.wanted)
                                            }
                                        }
                                        // OS file/folder icon; a trailing "/" asks the provider
                                        // for the folder icon.
                                        Image {
                                            width: 16; height: 16
                                            anchors.verticalCenter: parent.verticalCenter
                                            source: root.item
                                                    ? ("image://fileicon/" + safeStr(root.item.savePath).replace(/\\/g, "/")
                                                       + "/" + safeStr(fd.path) + (fd.isFolder ? "/" : ""))
                                                    : ""
                                            sourceSize: Qt.size(16, 16)
                                            fillMode: Image.PreserveAspectFit
                                            asynchronous: true
                                        }
                                        Item { width: 5; height: 1 }
                                        Text {
                                            width: root.fileColName - 4 - Math.max(0, fd.depth) * 16 - 18 - 22 - 16 - 5 - 6
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: safeStr(fd.name)
                                            textFormat: Text.PlainText
                                            color: fd.textColor
                                            font.pixelSize: 12 * App.fontScale; font.bold: fd.isFolder
                                            elide: Text.ElideMiddle
                                        }
                                    }
                                }

                                // Progress: percentage + bar.
                                Item {
                                    x: root._fileColXMap["progress"] || 0
                                    width: root.fileColProgress; height: parent.height
                                    Text {
                                        id: progPctLbl
                                        anchors { left: parent.left; leftMargin: 6; verticalCenter: parent.verticalCenter }
                                        width: 34
                                        text: Math.round(root.clampPct(fd.progress) * 100) + "%"
                                        color: fd.textColor
                                        font.pixelSize: 11 * App.fontScale
                                    }
                                    Rectangle {
                                        anchors { left: progPctLbl.right; leftMargin: 4; right: parent.right; rightMargin: 8
                                                  verticalCenter: parent.verticalCenter }
                                        height: 4; radius: 2
                                        color: ColorPalette.border
                                        Rectangle {
                                            width: Math.max(0, parent.width * root.clampPct(fd.progress))
                                            height: parent.height; radius: parent.radius
                                            color: fd.wanted ? ColorPalette.progressDownloading : ColorPalette.textDisabled
                                        }
                                    }
                                }

                                FileCell {
                                    color: fd.textColor
                                    x: root._fileColXMap["size"] || 0
                                    width: root.fileColSize
                                    text: root.compactBytes(fd.size)
                                }
                                FileCell {
                                    color: fd.textColor
                                    x: root._fileColXMap["remaining"] || 0
                                    width: root.fileColRemaining
                                    // Skipped files will never download, so "remaining" is moot.
                                    text: fd.wanted ? root.compactBytes(fd.remaining) : "-"
                                }
                                FileCell {
                                    color: fd.textColor
                                    x: root._fileColXMap["availability"] || 0
                                    width: root.fileColAvailability
                                    text: fd.availability < 0 ? qsTr("N/A")
                                        : (fd.availability >= 1 ? "100%" : (fd.availability * 100).toFixed(1) + "%")
                                }

                                FileCell {
                                    x: root._fileColXMap["priority"] || 0
                                    width: root.fileColPriority
                                    text: fd.wanted ? root.priorityLabel(fd.priority) : qsTr("Do not download")
                                    color: fd.wanted ? root.priorityColor(fd.priority) : ColorPalette.textDisabled
                                }

                                // Right-click: a MouseArea rather than TapHandler, which
                                // doesn't fire reliably for these ListView rows on Windows.
                                MouseArea {
                                    anchors.fill: parent
                                    acceptedButtons: Qt.RightButton
                                    onClicked: {
                                        fileCtxMenu._fileIndex = fd.fileIndex
                                        fileCtxMenu._path = fd.path
                                        fileCtxMenu._name = fd.name
                                        fileCtxMenu._wanted = fd.wanted
                                        fileCtxMenu._isFolder = fd.isFolder
                                        fileCtxMenu._priority = fd.priority
                                        fileCtxMenu.popup()
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
                            transientParent: root.Window.window
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
                                        source: "../icons/actions/edit-rename.svg"
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

                        // Thin right-click menu — mirrors the main download table's
                        // CtxMenuItem style (22px rows, opaque bg). See DownloadTable.qml.
                        // Order: open / reveal, copy, rename, then priority.
                        Menu {
                            id: fileCtxMenu
                            topPadding: 0; bottomPadding: 0
                            delegate: FileCtxMenuItem {}
                            property int _fileIndex: -1
                            property string _path: ""
                            property string _name: ""
                            property bool _wanted: true
                            property bool _isFolder: false
                            property int _priority: 4

                            // Stable identifiers — the visible row number shifts on
                            // expand/collapse, the file index / path don't.
                            function _applyPriority(level) {
                                if (!root.item) return
                                if (_fileIndex >= 0)
                                    App.setTorrentFilePriorityByIndex(root.item.id, _fileIndex, level)
                                else
                                    App.setTorrentFilePriorityByPath(root.item.id, _path, level)
                            }
                            function _setWanted(wanted) {
                                if (!root.item) return
                                if (_fileIndex >= 0)
                                    App.setTorrentFileWantedByIndex(root.item.id, _fileIndex, wanted)
                                else
                                    App.setTorrentFileWantedByPath(root.item.id, _path, wanted)
                            }

                            FileCtxMenuItem {
                                text: qsTr("Open")
                                iconSrc: "actions/document-open.svg"
                                onTriggered: if (root.item) App.openTorrentEntry(root.item.id, fileCtxMenu._path)
                            }
                            FileCtxMenuItem {
                                text: qsTr("Open Containing Folder")
                                iconSrc: "actions/folder-open.svg"
                                onTriggered: if (root.item) App.revealTorrentEntry(root.item.id, fileCtxMenu._path)
                            }
                            MenuSeparator {}
                            FileCtxMenuItem {
                                text: qsTr("Copy Path")
                                iconSrc: "actions/copy-path.svg"
                                onTriggered: {
                                    if (!root.item) return
                                    var p = App.torrentEntryPath(root.item.id, fileCtxMenu._path)
                                    if (p.length > 0) App.copyToClipboard(p)
                                }
                            }
                            FileCtxMenuItem {
                                text: qsTr("Copy Name")
                                iconSrc: "actions/copy-name.svg"
                                onTriggered: App.copyToClipboard(fileCtxMenu._name)
                            }
                            MenuSeparator {}
                            FileCtxMenuItem {
                                text: qsTr("Rename...")
                                iconSrc: "actions/edit-rename.svg"
                                onTriggered: renameDialog.openForRename(fileCtxMenu._path, fileCtxMenu._name, fileCtxMenu._fileIndex, fileCtxMenu._isFolder)
                            }
                            MenuSeparator {}
                            // Submenu rendered DownloadTable-style: a plain item with an
                            // inline ▶ that pops a child Menu manually on hover. A real
                            // Menu{title} subMenu renders the style file's tiny PNG arrow.
                            FileCtxMenuItem {
                                id: _fpPriorityItem
                                text: qsTr("Priority") + "  ▶"
                                iconSrc: "status/priority.svg"
                                onTriggered: _fpPriorityMenu.popup(_fpPriorityItem.width, 0)
                                onHoveredChanged: {
                                    if (hovered) { _fpPriorityMenu.popup(_fpPriorityItem.width, 0) }
                                    else { _fpPriorityCloseTimer.restart() }
                                }
                                Menu {
                                    id: _fpPriorityMenu
                                    delegate: FileCtxMenuItem {}
                                    topPadding: 0; bottomPadding: 0
                                    onAboutToHide: _fpPriorityCloseTimer.stop()
                                    FileCtxMenuItem {
                                        text: qsTr("Do not download"); iconSrc: "status/priority-skip.svg"
                                        checkable: true; checked: !fileCtxMenu._wanted
                                        onTriggered: fileCtxMenu._setWanted(false)
                                    }
                                    MenuSeparator {}
                                    FileCtxMenuItem {
                                        text: qsTr("Low"); iconSrc: "status/priority-low.svg"
                                        checkable: true; checked: fileCtxMenu._wanted && fileCtxMenu._priority === 1
                                        onTriggered: fileCtxMenu._applyPriority(1)
                                    }
                                    FileCtxMenuItem {
                                        text: qsTr("Normal"); iconSrc: "status/priority-normal.svg"
                                        checkable: true; checked: fileCtxMenu._wanted && fileCtxMenu._priority === 4
                                        onTriggered: fileCtxMenu._applyPriority(4)
                                    }
                                    FileCtxMenuItem {
                                        text: qsTr("High"); iconSrc: "status/priority-high.svg"
                                        checkable: true; checked: fileCtxMenu._wanted && fileCtxMenu._priority === 6
                                        onTriggered: fileCtxMenu._applyPriority(6)
                                    }
                                    FileCtxMenuItem {
                                        text: qsTr("Maximum"); iconSrc: "status/priority-maximum.svg"
                                        checkable: true; checked: fileCtxMenu._wanted && fileCtxMenu._priority === 7
                                        onTriggered: fileCtxMenu._applyPriority(7)
                                    }
                                }
                                Timer { id: _fpPriorityCloseTimer; interval: 300; onTriggered: { if (!_fpPriorityMenu.activeFocus) _fpPriorityMenu.close() } }
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
                            // Pointer tracking for peerTip: the tip stays up when a live
                            // update slides a row out from under a still cursor.
                            HoverHandler { id: peerListHover }
                            LiveHoverTip {
                                id: peerTip
                                parent: peerListView
                                pointer: peerListHover.point.position
                                viewHovered: peerListHover.hovered
                            }
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

                            // Same thin 22px rows as the Files / Trackers menus.
                            Menu {
                                id: peerCtxMenu
                                topPadding: 0; bottomPadding: 0
                                delegate: FileCtxMenuItem {}
                                property string endpoint: ""
                                property int port: 0
                                property string client: ""
                                property string countryCode: ""
                                property var peerData: ({})

                                FileCtxMenuItem {
                                    text: qsTr("Peer Info")
                                    iconSrc: "actions/peer-info.svg"
                                    enabled: peerCtxMenu.endpoint.length > 0
                                    onTriggered: peerInfoDialog.openForPeer(peerCtxMenu.peerData)
                                }
                                FileCtxMenuItem {
                                    text: qsTr("Ban peer")
                                    iconSrc: "actions/peer-ban.svg"
                                    enabled: !!root.item && peerCtxMenu.endpoint.length > 0
                                    onTriggered: {
                                        if (!root.item)
                                            return
                                        if (root.torrentPeerModel)
                                            root.torrentPeerModel.removePeer(peerCtxMenu.endpoint, peerCtxMenu.port)
                                        App.banTorrentPeer(root.item.id, peerCtxMenu.endpoint, peerCtxMenu.port,
                                                           peerCtxMenu.client, peerCtxMenu.countryCode)
                                    }
                                }
                            }

                            Window {
                                id: peerInfoDialog
                                width: 600
                                height: 520
                                minimumWidth: 560
                                minimumHeight: 480
                                modality: Qt.ApplicationModal
                                flags: Qt.Window | Qt.WindowTitleHint | Qt.WindowCloseButtonHint | Qt.WindowSystemMenuHint
                                title: qsTr("Peer Info")
                                color: ColorPalette.cardBg

                                // Last known row for this peer; refreshed from the model while
                                // open. When the peer leaves, the last values stay on screen and
                                // `connected` drops so the header can say so.
                                property var peerData: ({})
                                property string peerKey: ""
                                property bool connected: true
                                readonly property var flagList: root.peerFlagsList(peerData.flags)
                                function hasFlag(f) { return flagList.indexOf(f) !== -1 }

                                function openForPeer(peer) {
                                    peerData = peer || ({})
                                    peerKey = root.safeStr(peerData.endpoint) + "|" + (Number(peerData.port) | 0)
                                    connected = true
                                    show()
                                    raise()
                                    requestActivate()
                                }
                                function refresh() {
                                    if (!root.torrentPeerModel || peerKey.length === 0)
                                        return
                                    var live = root.torrentPeerModel.peerByKey(peerKey)
                                    if (live && live.endpoint !== undefined) {
                                        peerData = live
                                        connected = true
                                    } else {
                                        connected = false
                                    }
                                }
                                Timer {
                                    interval: 1000
                                    repeat: true
                                    running: peerInfoDialog.visible
                                    onTriggered: peerInfoDialog.refresh()
                                }

                                ColumnLayout {
                                    anchors { fill: parent; leftMargin: 14; rightMargin: 14; topMargin: 12; bottomMargin: 12 }
                                    spacing: 4

                                    // Identity: client logo, address, client string, copy.
                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 10

                                        Image {
                                            Layout.preferredWidth: 24
                                            Layout.preferredHeight: 24
                                            source: root.torrentClientIconSource(peerInfoDialog.peerData.client)
                                            sourceSize: Qt.size(24, 24)
                                            fillMode: Image.PreserveAspectFit
                                            smooth: true
                                            visible: status === Image.Ready
                                        }
                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: 1
                                            Text {
                                                Layout.fillWidth: true
                                                text: root.formatEndpoint(peerInfoDialog.peerData.endpoint, peerInfoDialog.peerData.port) || "-"
                                                color: ColorPalette.textHeader
                                                font.pixelSize: 14 * App.fontScale
                                                font.bold: true
                                                textFormat: Text.PlainText
                                                elide: Text.ElideMiddle
                                            }
                                            Text {
                                                Layout.fillWidth: true
                                                text: {
                                                    var c = root.safeStr(peerInfoDialog.peerData.client) || qsTr("Unknown client")
                                                    return peerInfoDialog.connected ? c : qsTr("%1 · disconnected").arg(c)
                                                }
                                                color: ColorPalette.textSecond
                                                font.pixelSize: 12 * App.fontScale
                                                textFormat: Text.PlainText
                                                elide: Text.ElideRight
                                            }
                                        }
                                        SheetLink {
                                            text: qsTr("Copy")
                                            enabled: root.safeStr(peerInfoDialog.peerData.endpoint).length > 0
                                            onClicked: App.copyToClipboard(root.formatEndpoint(peerInfoDialog.peerData.endpoint, peerInfoDialog.peerData.port))
                                        }
                                    }

                                    SectionHeader { text: qsTr("Transfer"); Layout.topMargin: 8 }
                                    GridLayout {
                                        Layout.fillWidth: true
                                        columns: 4; columnSpacing: 10; rowSpacing: 2

                                        SheetKey  { text: qsTr("Download speed") }
                                        SheetValue { text: root.compactSpeed(peerInfoDialog.peerData.downSpeed) }
                                        SheetKey  { text: qsTr("Upload speed") }
                                        SheetValue { text: root.compactSpeed(peerInfoDialog.peerData.upSpeed) }

                                        SheetKey  { text: qsTr("Downloaded") }
                                        SheetValue { text: root.compactBytes(peerInfoDialog.peerData.downloaded) }
                                        SheetKey  { text: qsTr("Uploaded") }
                                        SheetValue { text: root.compactBytes(peerInfoDialog.peerData.uploaded) }

                                        SheetKey  { text: qsTr("Has") }
                                        SheetValue { text: Math.round(root.clampPct(peerInfoDialog.peerData.progress) * 100) + "%" }
                                        SheetKey  { text: qsTr("Ping") }
                                        SheetValue {
                                            readonly property bool measured: (Number(peerInfoDialog.peerData.rtt) || 0) > 0
                                            text: measured ? peerInfoDialog.peerData.rtt + " ms" : qsTr("Not measured")
                                            color: measured ? ColorPalette.textPrimary : ColorPalette.textMuted
                                            HoverHandler { id: pingHover }
                                            ThemedToolTip {
                                                visible: pingHover.hovered
                                                text: qsTr("Measured from how fast this peer answers block requests, so it's only known while you're downloading from it.")
                                            }
                                        }
                                    }

                                    SectionHeader { text: qsTr("Connection"); Layout.topMargin: 7 }
                                    GridLayout {
                                        Layout.fillWidth: true
                                        columns: 4; columnSpacing: 10; rowSpacing: 2

                                        SheetKey  { text: qsTr("Role") }
                                        SheetValue { text: peerInfoDialog.peerData.isSeed ? qsTr("Seed") : qsTr("Peer") }
                                        SheetKey  { text: qsTr("Direction") }
                                        SheetValue { text: peerInfoDialog.hasFlag("IN") ? qsTr("Incoming") : qsTr("Outgoing") }

                                        SheetKey  { text: qsTr("Found via") }
                                        SheetValue {
                                            text: {
                                                var names = { TRK: qsTr("Tracker"), DHT: "DHT", PEX: "PeX", LSD: qsTr("Local network") }
                                                var out = []
                                                for (var k in names)
                                                    if (peerInfoDialog.hasFlag(k)) out.push(names[k])
                                                return out.length > 0 ? out.join(", ") : "-"
                                            }
                                        }
                                        SheetKey  { text: qsTr("Protocol") }
                                        SheetValue {
                                            text: {
                                                var p = peerInfoDialog.hasFlag("I2P") ? "I2P" : (peerInfoDialog.hasFlag("UTP") ? "uTP" : "TCP")
                                                return peerInfoDialog.hasFlag("HPX") ? qsTr("%1, holepunched").arg(p) : p
                                            }
                                        }

                                        SheetKey  { text: qsTr("Encryption") }
                                        SheetValue { text: peerInfoDialog.hasFlag("ENC") ? qsTr("Encrypted") : qsTr("Not encrypted") }
                                        SheetKey  { text: qsTr("State") }
                                        SheetValue {
                                            text: {
                                                var out = []
                                                if (peerInfoDialog.hasFlag("SNB")) out.push(qsTr("Snubbed"))
                                                if (peerInfoDialog.hasFlag("OPT")) out.push(qsTr("Optimistic unchoke"))
                                                if (peerInfoDialog.hasFlag("UPO")) out.push(qsTr("Upload only"))
                                                return out.length > 0 ? out.join(", ") : qsTr("Normal")
                                            }
                                        }
                                    }

                                    SectionHeader { text: qsTr("Location"); Layout.topMargin: 7 }
                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 8
                                        Image {
                                            Layout.preferredWidth: 18
                                            Layout.preferredHeight: 12
                                            source: root.countryFlagSource(peerInfoDialog.peerData.countryCode)
                                            sourceSize: Qt.size(18, 12)
                                            fillMode: Image.PreserveAspectFit
                                            visible: status === Image.Ready
                                        }
                                        SheetValue {
                                            text: root.peerPlaceText(peerInfoDialog.peerData) || qsTr("Unknown")
                                        }
                                        Text {
                                            readonly property bool known: !!root.torrentPeerModel && root.torrentPeerModel.hasLocalLocation
                                                && root.hasGeoCoordinates(peerInfoDialog.peerData.latitude, peerInfoDialog.peerData.longitude)
                                            visible: known
                                            text: known ? qsTr("%1 away").arg(root.distanceSummary(peerInfoDialog.peerData.latitude, peerInfoDialog.peerData.longitude)) : ""
                                            color: ColorPalette.textMuted
                                            font.pixelSize: 12 * App.fontScale
                                        }
                                    }

                                    // You -> peer on the world map (zoomed to fit both).
                                    Rectangle {
                                        Layout.fillWidth: true
                                        Layout.fillHeight: true
                                        Layout.topMargin: 4
                                        Layout.minimumHeight: 120
                                        color: ColorPalette.mapCanvasBg
                                        border.color: ColorPalette.border
                                        radius: 2
                                        clip: true

                                        Item {
                                            id: peerInfoMap
                                            anchors.fill: parent
                                            anchors.margins: 1
                                            readonly property real mapHeight: height
                                            readonly property real baseMapWidth: mapHeight * (800.0 / 387.0)
                                            readonly property real baseMapX: (width - baseMapWidth) / 2
                                            readonly property bool hasLocal: !!root.torrentPeerModel && root.torrentPeerModel.hasLocalLocation
                                            readonly property bool hasPeer: root.hasGeoCoordinates(peerInfoDialog.peerData.latitude, peerInfoDialog.peerData.longitude)
                                            readonly property var transformData: root.peerInfoMapTransform(peerInfoDialog.peerData, baseMapWidth, mapHeight)
                                            readonly property real absLocalX: baseMapX + transformData.localX
                                            readonly property real localY: transformData.localY
                                            readonly property real absPeerX: baseMapX + transformData.peerX
                                            readonly property real peerY: transformData.peerY

                                            Image {
                                                x: parent.baseMapX + parent.transformData.offsetX
                                                y: parent.transformData.offsetY
                                                width: parent.baseMapWidth * parent.transformData.scale
                                                height: parent.mapHeight * parent.transformData.scale
                                                source: ColorPalette.dark ? "../icons/images/world-map-dark.svg" : "../icons/images/world-map-light.svg"
                                                fillMode: Image.Stretch
                                                smooth: true
                                                sourceSize.width: 1200
                                                sourceSize.height: 581
                                            }

                                            // Straight link between the two points.
                                            Rectangle {
                                                readonly property real dx: parent.absPeerX - parent.absLocalX
                                                readonly property real dy: parent.peerY - parent.localY
                                                visible: parent.hasLocal && parent.hasPeer
                                                x: parent.absLocalX
                                                y: parent.localY - height / 2
                                                width: Math.sqrt(dx * dx + dy * dy)
                                                height: 2
                                                radius: 1
                                                rotation: Math.atan2(dy, dx) * 180 / Math.PI
                                                transformOrigin: Item.Left
                                                color: ColorPalette.accent
                                                opacity: 0.8
                                            }

                                            component MapDot: Rectangle {
                                                width: 10; height: 10; radius: 5
                                                border.color: ColorPalette.mapBorder
                                                border.width: 1
                                            }
                                            component MapLabel: Text {
                                                color: ColorPalette.mapLabelText
                                                style: Text.Outline
                                                styleColor: ColorPalette.mapLabelBg
                                                font.pixelSize: 10 * App.fontScale
                                                font.bold: true
                                            }
                                            MapDot { visible: parent.hasLocal; x: parent.absLocalX - 5; y: parent.localY - 5; color: "#9959e6" }
                                            MapDot { visible: parent.hasPeer; x: parent.absPeerX - 5; y: parent.peerY - 5; color: root.peerMapColor(peerInfoDialog.peerData) }
                                            MapLabel { visible: parent.hasLocal; x: parent.absLocalX + 8; y: parent.localY - 7; text: qsTr("You") }
                                            MapLabel { visible: parent.hasPeer; x: parent.absPeerX + 8; y: parent.peerY - 7; text: qsTr("Peer") }

                                            Text {
                                                anchors.centerIn: parent
                                                visible: !parent.hasPeer
                                                text: qsTr("This peer's location is unknown")
                                                color: ColorPalette.textMuted
                                                font.pixelSize: 12 * App.fontScale
                                            }
                                        }
                                    }

                                    RowLayout {
                                        Layout.fillWidth: true
                                        Layout.topMargin: 8
                                        spacing: 8
                                        DlgButton {
                                            text: qsTr("Ban Peer")
                                            destructive: true
                                            enabled: !!root.item && root.safeStr(peerInfoDialog.peerData.endpoint).length > 0
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
                                        Item { Layout.fillWidth: true }
                                        DlgButton { text: qsTr("Close"); primary: true; onClicked: peerInfoDialog.close() }
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

                                readonly property string _peerKey: pd.endpoint + "|" + pd.port
                                readonly property string _tipText: {
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
                                    return root.formatEndpoint(pd.endpoint, pd.port) + "\n" + locBlock + "\n" + clientLine
                                }
                                on_TipTextChanged: if (peerRowMa.containsMouse) peerTip.refresh(_peerKey, _tipText)
                                // A destroyed or recycled row never gets its hover-exit; drop its entry.
                                Component.onDestruction: peerTip.hoverLeave(_peerKey)
                                ListView.onPooled: peerTip.hoverLeave(_peerKey)

                                MouseArea {
                                    id: peerRowMa; anchors.fill: parent; hoverEnabled: true
                                    acceptedButtons: Qt.LeftButton
                                    onContainsMouseChanged: {
                                        if (containsMouse)
                                            peerTip.hoverEnter(pd._peerKey, pd._tipText)
                                        else
                                            peerTip.hoverLeave(pd._peerKey)
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
                                                model: root.peerFlagsList(pd.flags)
                                                delegate: PeerFlagBadge {
                                                    required property string modelData
                                                    flag: modelData
                                                    tip: root.flagTip(modelData)
                                                    hoverTip: peerTip
                                                    hoverKey: pd._peerKey
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
                                        peerCtxMenu.popup()
                                    }
                                }
                            }
                        }
                    }
                }

                // ?? Swarm Map ????????????????????????????????????????????????
                Item {
                    SwarmMap {
                        anchors.fill: parent
                        view: root
                        peerModel: root.activePeerMapModel
                        trackerModel: root.activeTrackerMapModel
                        torrentProgress: root.item ? root.item.progress : 0
                        contentKey: root.item ? root.safeStr(root.item.id) : ""
                    }
                }

                Item {
                    // Shared context menu for tracker rows. Same thin 22px rows as
                    // the Files tab menu (FileCtxMenuItem).
                    Menu {
                        id: trackerCtxMenu
                        topPadding: 0; bottomPadding: 0
                        delegate: FileCtxMenuItem {}
                        property string trackerUrl: ""
                        // DHT/PEX/LSD are virtual "trackers" with no real URL - disable
                        // destructive/copy actions so right-clicking them feels inert.
                        property bool isSystemEntry: false

                        FileCtxMenuItem {
                            text: qsTr("Force Reannounce")
                            iconSrc: "actions/tracker-reannounce.svg"
                            enabled: !trackerCtxMenu.isSystemEntry && !!root.item
                            onTriggered: {
                                if (root.item && trackerCtxMenu.trackerUrl.length > 0)
                                    App.forceReannounceTorrent(root.item.id, [trackerCtxMenu.trackerUrl])
                            }
                        }
                        FileCtxMenuItem {
                            text: qsTr("Copy URL")
                            iconSrc: "actions/copy-link.svg"
                            enabled: !trackerCtxMenu.isSystemEntry
                            onTriggered: {
                                if (trackerCtxMenu.trackerUrl.length > 0)
                                    App.copyToClipboard(trackerCtxMenu.trackerUrl)
                            }
                        }
                        FileCtxMenuItem {
                            text: qsTr("Remove tracker")
                            iconSrc: "actions/edit-delete.svg"
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
                                    text: qsTr("Add trackers...")
                                    primary: true
                                    onClicked: if (root.item) addSourcesDialog.openFor("trackers", root.item.id)
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
                                width: root._trkColsTotalW
                                height: parent.height

                                Repeater {
                                    model: root._trkColsOrdered
                                    delegate: Rectangle {
                                        id: trkHdrCell
                                        visible: width > 0
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
                                                if (root._trkColDragInsertBeforeKey === "" && modelData.sortKey.length > 0)
                                                    root.sortTrackers(modelData.sortKey)
                                            }
                                        }

                                        // Resize handle (the icon column is fixed-width)
                                        Item {
                                            id: trkRh; width: 10; height: parent.height; anchors.right: parent.right; z: 10
                                            visible: modelData.key !== "icon"
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
                            contentWidth: root._trkColsTotalW

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
                                        visible: width > 0
                                        x: root._trkColXMap["icon"] || 0
                                        width: root._trkColW("icon"); height: parent.height
                                        Image {
                                            anchors.centerIn: parent
                                            width: 16; height: 16
                                            sourceSize: Qt.size(16, 16)
                                            // `revision` re-runs this once a background fetch lands.
                                            source: {
                                                App.trackerIcons.revision
                                                return parent.visible && !trd.isSystemEntry ? App.trackerIcons.iconFor(trd.url) : ""
                                            }
                                            fillMode: Image.PreserveAspectFit
                                            smooth: true
                                            asynchronous: true
                                        }
                                    }
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
                                    text: qsTr("Add seed...")
                                    primary: true
                                    onClicked: if (root.item) addSourcesDialog.openFor("webSeeds", root.item.id)
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
                                topPadding: 0; bottomPadding: 0
                                delegate: FileCtxMenuItem {}
                                property string seedUrl:  ""
                                property string seedType: ""

                                FileCtxMenuItem {
                                    text: qsTr("Copy URL")
                                    iconSrc: "actions/copy-link.svg"
                                    onTriggered: {
                                        if (webSeedCtxMenu.seedUrl.length > 0)
                                            App.copyToClipboard(webSeedCtxMenu.seedUrl)
                                    }
                                }
                                FileCtxMenuItem {
                                    text: qsTr("Open in browser")
                                    iconSrc: "places/globe.svg"
                                    onTriggered: {
                                        if (webSeedCtxMenu.seedUrl.length > 0)
                                            App.openExternalUrl(webSeedCtxMenu.seedUrl)
                                    }
                                }
                                FileCtxMenuItem {
                                    text: qsTr("Remove seed")
                                    iconSrc: "actions/edit-delete.svg"
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
                }

                // ?? Piece Map ?????????????????????????????????????????????????
                Item {
                    id: pieceMapTab

                    readonly property bool isActive: root.active && visible && root._isTorrent && root.currentTab === 7
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
                        anchors { fill: parent; leftMargin: 6; rightMargin: 6; topMargin: 4; bottomMargin: 6 }
                        spacing: 4

                        // Legend (left) and summary (right) share one row.
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 12

                            Row {
                                spacing: 10

                                Text {
                                    text: qsTr("Legend:")
                                    color: ColorPalette.textSecond; font.pixelSize: 11 * App.fontScale
                                    anchors.verticalCenter: parent.verticalCenter
                                }

                                Repeater {
                                    model: [
                                    { color: "#2ecc71", label: qsTr("Have") },
                                    { color: "#4a9de8", label: qsTr("Downloading") },
                                    { color: "#c0392b", label: qsTr("Rare") },
                                    { color: "#e2b13c", label: qsTr("Common") },
                                    { color: "#e67e22", label: qsTr("High Priority") },
                                    { color: ColorPalette.textMuted, label: qsTr("Skipped") },
                                    { color: ColorPalette.cardBg, label: qsTr("Unavailable") }
                                    ]
                                    delegate: Row {
                                        required property var modelData
                                        spacing: 4
                                        anchors.verticalCenter: parent.verticalCenter
                                        Rectangle {
                                            width: 10; height: 10
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
                            }

                            Text {
                                id: pieceSummaryText
                                Layout.fillWidth: true
                                horizontalAlignment: Text.AlignRight
                                // Yields to the legend when space is short.
                                elide: Text.ElideRight
                                color: ColorPalette.textSecond; font.pixelSize: 11 * App.fontScale
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
                                    var parts = [qsTr("%1 pieces").arg(d.length),
                                    qsTr("%1 downloaded").arg(have)]
                                    if (partial > 0) parts.push(qsTr("%1 downloading").arg(partial))
                                    if (skipped > 0) parts.push(qsTr("%1 skipped").arg(skipped))
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
                                // Largest whole-pixel cell (capped at 14) whose grid still
                                // fits, starting from the area-per-piece estimate so the
                                // grid fills the canvas instead of leaving a band below.
                                for (var cs = Math.min(14, Math.floor(Math.sqrt(width * height / n))); cs >= 2; --cs) {
                                    var cols = Math.floor(width / cs)
                                    if (cols > 0 && Math.ceil(n / cols) * cs <= height)
                                        return cs
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
                                // Missing pieces shaded by swarm rarity. Green is reserved for
                                // "Have" only, so the gradient runs red (rare) -> amber (common)
                                // and never collides with the have/common-green ambiguity.
                                var t2 = maxRarity > 1 ? (cnt - 1) / (maxRarity - 1) : 1.0
                                // t2=0 -> rare #c0392b (red), t2=1 -> common #e2b13c (amber)
                                var r = Math.round(0xc0 + (0xe2 - 0xc0) * t2)
                                var g = Math.round(0x39 + (0xb1 - 0x39) * t2)
                                var b = Math.round(0x2b + (0x3c - 0x2b) * t2)
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
                                    ctx.fillText(qsTr("No piece data available"), width / 2, height / 2)
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
                                            status = qsTr("Downloaded")
                                        } else if (val === -3) {
                                            status = qsTr("Skipped (file not selected)")
                                        } else if (val <= -4) {
                                            var pct = Math.min(99, -(val + 4))
                                            status = qsTr("Downloading - %1% of blocks received").arg(pct)
                                        } else {
                                            var hp  = (val & 0x10000) !== 0
                                            var cnt = val & 0xFFFF
                                            if (cnt === 0)
                                                status = qsTr("Unavailable - no peers have this piece")
                                            else
                                                status = qsTr("Missing - %n peer(s) have it", "", cnt) + (hp ? qsTr(" (high priority)") : "")
                                        }
                                        return qsTr("Piece #%1").arg(idx) + "\n" + status
                                    }
                                }
                            }
                        }
                    }
                }

                // ?? Settings (per-torrent limits / discovery / mode) ??????????
                Item {
                    TorrentSettingsPanel {
                        anchors.fill: parent
                        torrentItem: root.currentTab === 8 ? root.item : null
                    }
                }
            }
        }
    }
}
