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
import QtQuick.Controls.Material
import QtQuick.Layouts

Window {
    id: root

    // Compact by default; every page reflows (label column sized to its text,
    // long labels stacked above their control) so it also fits translations.
    width: 600
    height: 500
    minimumWidth: 520
    minimumHeight: 420
    flags: Qt.Window | Qt.WindowTitleHint | Qt.WindowCloseButtonHint | Qt.WindowSystemMenuHint
    title: qsTr("Stellar Preferences")
    color: ColorPalette.cardBg

    Material.theme: ColorPalette.materialTheme
    Material.foreground: ColorPalette.textPrimary
    Material.background: ColorPalette.materialBg
    Material.accent: "#4488dd"

    property int    initialPage: 0   // Tab indices: 0=Connection,1=Categories,2=Downloads,3=Browser,4=Speed Limiter,5=Notifications,6=General,7=Media,8=Torrents,9=RSS,10=Associations,11=Language,12=About
    readonly property int pageAssociations: 10
    readonly property int pageLanguage: 11
    readonly property int pageAbout: 12
    property bool   torrentAssociationDefault: false
    property bool   magnetAssociationDefault: false
    property string associationStatusText: ""
    signal whatsNewRequested()

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

    // ── Per-server connection-count exceptions (Connections tab) ──────────
    // editPerServerConnLimitsJson is the source of truth; serverConnModel is a
    // view rebuilt from it for the table. Each entry: {scheme, server, conns}.
    ListModel { id: serverConnModel }

    function reloadServerConnModel() {
        serverConnModel.clear()
        var arr = []
        try { arr = JSON.parse(root.editPerServerConnLimitsJson || "[]") } catch (e) { arr = [] }
        if (!Array.isArray(arr)) arr = []
        for (var i = 0; i < arr.length; ++i) {
            var e = arr[i] || {}
            serverConnModel.append({
                server: String(e.server || ""),
                conns:  Math.max(1, Math.min(32, parseInt(e.conns) || 1))
            })
        }
    }

    function commitServerConnModel() {
        var arr = []
        for (var i = 0; i < serverConnModel.count; ++i) {
            var e = serverConnModel.get(i)
            arr.push({ server: e.server, conns: e.conns })
        }
        root.editPerServerConnLimitsJson = JSON.stringify(arr)
    }

    function openServerConnDialog(index) {
        if (index >= 0 && index < serverConnModel.count) {
            var e = serverConnModel.get(index)
            serverConnDialog.editIndex = index
            serverConnDialog.serverValue = e.server
            serverConnDialog.connsValue  = e.conns
        } else {
            serverConnDialog.editIndex = -1
            serverConnDialog.serverValue = ""
            serverConnDialog.connsValue  = 1
        }
        serverConnDialog.show()
        serverConnDialog.raise()
        serverConnDialog.requestActivate()
    }

    function deleteServerConnRule(index) {
        if (index < 0 || index >= serverConnModel.count) return
        serverConnModel.remove(index)
        commitServerConnModel()
    }

    function applyServerConnRule(index, server, conns) {
        var row = { server: server, conns: conns }
        if (index >= 0 && index < serverConnModel.count)
            serverConnModel.set(index, row)
        else
            serverConnModel.append(row)
        commitServerConnModel()
    }

    ServerConnLimitDialog {
        id: serverConnDialog
        onAccepted: root.applyServerConnRule(editIndex, serverValue, connsValue)
    }

    // Plain var properties - no live binding to App.settings so that
    // settingsChanged can detect when the user has made changes.
    property int    editMaxConcurrent:         0
    property int    editMaxConcurrentTorrents: 0
    property bool   editGlobalDownloadLimitEnabled: false
    property int    editGlobalDownloadLimitMBytes: 200
    property int    editGlobalDownloadLimitHours: 5
    property bool   editGlobalDownloadLimitWarn: true
    property int    editSegmentsPerDownload:   0
    property string editPerServerConnLimitsJson: "[]"
    property string editDefaultSavePath:       ""
    property string editTemporaryDirectory:    ""
    property string editTorrentCustomSavePath: ""
    property bool   editGlobalSpeedLimitEnabled: false
    property bool   editMinimizeToTray:        false
    property bool   editCloseToTray:           false
    property bool   editShowTips:              true
    property bool   editShowExceptionsDialog:  true
    property int    editMaxRetries:            0
    property int    editConnectionTimeoutSecs: 0
    property int    editDuplicateAction:       0
    property bool   editStartImmediately:      false
    property bool   editSpeedLimiterOnStartup: false
    property int    editGlobalUploadLimitKBps:        0
    property int    editSavedUploadLimitKBps:         0
    property int    editSavedUploadLimitKBpsBaseline: 0
    property bool   editShowDownloadComplete:  true
    property bool   editShowCompletionNotification: true
    property bool   editShowErrorNotification: true
    property bool   editSpeedInTrayTooltip:    true
    property bool   editSpeedInTitleBar:       false
    property bool   editSpeedInStatusBar:      false
    property bool   editRatioInStatusBar:      false
    property bool   editConnectionsInStatusBar: false
    property bool   editDhtNodesInStatusBar:    false
    property bool   editShowPublicIpInStatusBar: false
    property bool   editStartDownloadWhileFileInfo: true
    property bool   editFillDescriptionMetadata: true
    property bool   editShowQueueSelectionOnDownloadLater: true
    property bool   editShowQueueSelectionOnBatchDownload: true
    property bool   editUseCustomUserAgent:    false
    property string editCustomUserAgent:       ""
    property int    editSavedSpeedLimitKBps:   500
    property int    editBypassInterceptKey:    0
    property bool   editLaunchOnStartup:       false
    property bool   editTorrentStopOnStartup:  false
    property bool   editClipboardMonitorEnabled: false
    property int    editDoubleClickAction:     0
    property bool   editSpeedScheduleEnabled:  false
    property string editSpeedScheduleJson:     "[]"
    property bool   editAutoCheckUpdates:      true
    property int    editLastTryDateStyle:      0
    property bool   editLastTryUse24Hour:      true
    property bool   editLastTryShowSeconds:    true
    // yt-dlp settings
    property string editYtdlpCustomBinaryPath: ""
    property bool   editYtdlpAutoUpdate:          false
    property string editYtdlpJsRuntimePath:       ""
    property string editYtdlpDefaultCookieBrowser: ""
    property bool   editTorrentEnabled:        false
    property bool   editTorrentEnableDht:      true
    property bool   editTorrentDhtAutoSuspend: true
    property bool   editTorrentEnableLsd:      true
    property bool   editTorrentEnableUpnp:     true
    property bool   editTorrentEnableNatPmp:   true
    property bool   editTorrentEnablePex:      true
    property bool   editTorrentAnnounceToAllTiers:    true
    property bool   editTorrentAnnounceToAllTrackers: false
    property int    editTorrentListenPort:     6881
    property int    editTorrentConnectionsLimit: 200
    property int    editTorrentConnectionsLimitPerTorrent: 0
    property int    editTorrentUploadSlotsLimit: 8
    property int    editTorrentUploadSlotsLimitPerTorrent: 0
    property int    editTorrentProtocol: 0
    property string editTorrentCustomUserAgent: ""
    property string editTorrentBindInterface:  ""
    property bool   editTorrentAllowDiscoveryWhenBound: false
    property string editTorrentBlockedPeerUserAgents: ""
    property var    editTorrentBlockedPeerCountries: []
    property var    editTorrentBannedPeers: []
    property bool   editTorrentAutoBanAbusivePeers: false
    property bool   editTorrentAutoBanMediaPlayerPeers: false
    property bool   editTorrentAnonymousMode: false
    property int    editTorrentEncryptionMode: 0
    property int    editTorrentStorageMode: 0
    property bool   editTorrentPieceExtentAffinity: false
    property bool   editTorrentCoalesceReads: false
    property bool   editTorrentCoalesceWrites: false
    property int    editTorrentDiskIoType: 0
    property int    editTorrentDiskWriteQueueMiB: 64
    property var    torrentAdapterOptions:     []
    property var    torrentCountryOptions:     []
    property string selectedTorrentCountryCode: ""
    property string manualBanPeerText: ""
    // Proxy settings - 0=None, 1=System, 2=HTTP/HTTPS, 3=SOCKS5
    property int    editProxyType:     0
    property string editProxyHost:     ""
    property int    editProxyPort:     8080
    property string editProxyUsername: ""
    property string editProxyPassword: ""
    property var    ipToCityDbInfo:    ({})
    // RSS settings
    property bool   editRssEnabled:             true
    property int    editRssRefreshIntervalMins:  30
    property int    editRssSameHostDelayMs:      2000
    property int    editRssMaxArticlesPerFeed:   50
    property bool   editRssAutoDownloadEnabled:  false
    property bool   editRssSmartFilterRepack:    true
    property string editRssSmartFiltersJson:     "[]"
    // Language - empty string = English (default), "fr" = French, etc.
    property string editUiLanguage:             ""
    // Tray icon style: 0=Colored, 1=White, 2=Black
    property int    editTrayIconStyle:          0
    // UI scale factor: 0.0 = system default, otherwise 0.5-3.0
    property double editUiScaleFactor:          0.0
    // Font point size: 0 = system default, otherwise 6-32
    property int    editUiFontPointSize:        0
    // Dark mode: true = dark, false = light
    property bool   editDarkMode:              true

    readonly property string defaultUserAgent: "Stellar/" + App.appVersion
    readonly property string displayedUserAgent: editUseCustomUserAgent
        ? editCustomUserAgent
        : defaultUserAgent
    // Sample date/time used for the format combo labels and the live preview.
    // Refreshed to "now" each time the settings window opens (see onVisibleChanged)
    // so the examples always reflect the current date instead of a hardcoded one.
    property var _previewNow: new Date()

    function _pad2(n) { return (n < 10 ? "0" : "") + n }

    // Format _previewNow's date portion for the given style index (0-3).
    function _previewDatePart(style) {
        var d = root._previewNow
        var y = d.getFullYear(), mo = d.getMonth() + 1, day = d.getDate()
        switch (style) {
        case 1: return mo + "/" + day + "/" + y
        case 2: return day + "/" + mo + "/" + y
        case 3: return y + "-" + root._pad2(mo) + "-" + root._pad2(day)
        default:
            var months = ["Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"]
            return months[d.getMonth()] + " " + day + " " + y
        }
    }

    function _previewTimePart(use24, showSeconds) {
        var d = root._previewNow
        var h = d.getHours(), m = d.getMinutes(), s = d.getSeconds()
        if (use24)
            return showSeconds ? root._pad2(h) + ":" + root._pad2(m) + ":" + root._pad2(s)
                               : root._pad2(h) + ":" + root._pad2(m)
        var ampm = h >= 12 ? "PM" : "AM"
        var h12 = h % 12; if (h12 === 0) h12 = 12
        return showSeconds ? h12 + ":" + root._pad2(m) + ":" + root._pad2(s) + " " + ampm
                           : h12 + ":" + root._pad2(m) + " " + ampm
    }

    readonly property string lastTryPreview:
        _previewDatePart(editLastTryDateStyle) + " "
        + _previewTimePart(editLastTryUse24Hour, editLastTryShowSeconds)

    function _normalizedMonitoredExtensionsText() {
        return monitoredExtsArea
            ? monitoredExtsArea.text.split(/[\s,]+/).map(function(s) {
                return s.trim().toLowerCase().replace(/^\./, "")
            }).filter(function(s) { return s.length > 0 }).join("|")
            : App.settings.monitoredExtensions.join("|")
    }

    function _normalizedExcludedSitesText() {
        return excludedSitesArea
            ? excludedSitesArea.text.split(/[\s,]+/).map(function(s) {
                return s.trim()
            }).filter(function(s) { return s.length > 0 }).join("|")
            : App.settings.excludedSites.join("|")
    }

    function _normalizedExcludedAddressesText() {
        return excludedAddrsArea
            ? excludedAddrsArea.text.split("\n").map(function(s) {
                return s.trim()
            }).filter(function(s) { return s.length > 0 }).join("|")
            : App.settings.excludedAddresses.join("|")
    }

    function refreshTorrentNetworkAdapters() {
        var adapters = App.torrentNetworkAdapters()
        torrentAdapterOptions = adapters && adapters.length ? adapters : [{
            id: "",
            name: qsTr("Any interface"),
            details: qsTr("Follow the system route (used by your other apps).")
        }]
        var boundId = editTorrentBindInterface && editTorrentBindInterface.length > 0
            ? editTorrentBindInterface
            : App.settings.torrentBindInterface
        ensureTorrentAdapterOption(boundId)
    }

    function indexOfTorrentAdapter(adapterId) {
        for (var i = 0; i < torrentAdapterOptions.length; ++i) {
            if ((torrentAdapterOptions[i].id || "") === (adapterId || ""))
                return i
        }
        return 0
    }

    function torrentAdapterDetails(adapterId) {
        var index = indexOfTorrentAdapter(adapterId)
        if (index >= 0 && index < torrentAdapterOptions.length)
            return torrentAdapterOptions[index].details || ""
        return ""
    }

    function ensureTorrentAdapterOption(adapterId) {
        if (!adapterId || indexOfTorrentAdapter(adapterId) !== 0 || (torrentAdapterOptions.length > 0 && (torrentAdapterOptions[0].id || "") === adapterId))
            return
        torrentAdapterOptions = torrentAdapterOptions.concat([{
            id: adapterId,
            name: adapterId + qsTr(" (Unavailable)"),
            details: qsTr("This adapter is not currently available. Reconnect it or choose a different adapter.")
        }])
    }

    function refreshTorrentCountryOptions() {
        var options = App.torrentCountryOptions()
        torrentCountryOptions = options && options.length ? options : []
        if (selectedTorrentCountryCode.length === 0 && torrentCountryOptions.length > 0)
            selectedTorrentCountryCode = torrentCountryOptions[0].code || ""
    }

    function torrentCountryName(code) {
        var cc = String(code || "").toUpperCase()
        for (var i = 0; i < torrentCountryOptions.length; ++i) {
            var option = torrentCountryOptions[i]
            if ((option.code || "").toUpperCase() === cc)
                return option.name || cc
        }
        return cc
    }

    function addBlockedTorrentCountry(code) {
        var cc = String(code || "").trim().toUpperCase()
        if (cc.length !== 2)
            return
        var next = editTorrentBlockedPeerCountries.slice()
        if (next.indexOf(cc) !== -1)
            return
        next.push(cc)
        next.sort()
        editTorrentBlockedPeerCountries = next
    }

    function removeBlockedTorrentCountry(code) {
        var cc = String(code || "").trim().toUpperCase()
        var next = editTorrentBlockedPeerCountries.filter(function(v) { return String(v).toUpperCase() !== cc })
        editTorrentBlockedPeerCountries = next
    }

    function refreshIpToCityDbInfo() {
        App.refreshIpToCityDbInfo()
        ipToCityDbInfo = App.ipToCityDbInfo
    }

    function formatBytes(bytes) {
        var n = Number(bytes || 0)
        if (n <= 0) return "0 B"
        var units = ["B", "KB", "MB", "GB", "TB"]
        var i = 0
        while (n >= 1024 && i < units.length - 1) {
            n /= 1024
            ++i
        }
        return n.toFixed(i === 0 ? 0 : 2) + " " + units[i]
    }

    // Ratio colour ramp (shared with FilePropertiesDialog/StatisticsDialog): red→orange→green→lime→cyan→blue→purple→magenta
    function ratioColor(r) {
        r = r || 0
        function lerp(a, b, t) {
            return Math.round(a + (b - a) * Math.max(0, Math.min(1, t)))
        }
        function rgb(hr, hg, hb) {
            return "#" + ("0" + hr.toString(16)).slice(-2)
                       + ("0" + hg.toString(16)).slice(-2)
                       + ("0" + hb.toString(16)).slice(-2)
        }
        var stops = [
            [0.0,  255, 85,  85],
            [0.5,  255, 153, 68],
            [1.0,  85,  204, 102],
            [2.0,  153, 238, 85],
            [4.0,  68,  221, 204],
            [6.0,  68,  153, 255],
            [8.0,  170, 85,  255],
            [10.0, 255, 68,  204]
        ]
        if (r <= stops[0][0]) return rgb(stops[0][1], stops[0][2], stops[0][3])
        if (r >= stops[stops.length-1][0]) return rgb(stops[stops.length-1][1], stops[stops.length-1][2], stops[stops.length-1][3])
        for (var i = 1; i < stops.length; i++) {
            if (r <= stops[i][0]) {
                var t = (r - stops[i-1][0]) / (stops[i][0] - stops[i-1][0])
                return rgb(lerp(stops[i-1][1], stops[i][1], t),
                           lerp(stops[i-1][2], stops[i][2], t),
                           lerp(stops[i-1][3], stops[i][3], t))
            }
        }
        return "#ff44cc"
    }

    Component.onCompleted: {
        refreshTorrentNetworkAdapters()
        refreshTorrentCountryOptions()
        refreshIpToCityDbInfo()
        refreshAssociationStatus()
        resetEdits()
        catList.currentIndex = root.initialPage
    }
    onInitialPageChanged: {
        if (visible)
            catList.currentIndex = root.initialPage
    }
    function _centerOnOwner() {
        var owner = root.transientParent
        if (owner) {
            x = owner.x + Math.round((owner.width  - width)  / 2)
            y = owner.y + Math.round((owner.height - height) / 2)
            return
        }
        x = Math.round((Screen.width  - width)  / 2)
        y = Math.round((Screen.height - height) / 2)
    }

    function refreshAssociationStatus() {
        torrentAssociationDefault = App.isTorrentFileAssociationDefault()
        magnetAssociationDefault = App.isMagnetAssociationDefault()
    }

    function showAssociationResult(message, successText) {
        associationStatusText = (message && message.length > 0) ? message : successText
        refreshAssociationStatus()
    }

    onVisibleChanged: {
        if (visible) {
            _previewNow = new Date()   // refresh date-format samples to current time
            _centerOnOwner()
            refreshTorrentNetworkAdapters()
            refreshTorrentCountryOptions()
            refreshIpToCityDbInfo()
            refreshAssociationStatus()
            resetEdits()
            catList.currentIndex = root.initialPage
        }
    }

    // The browser extension adds/removes sites ("never intercept on this site")
    // while this window may be open. Once the user has typed in the box its text
    // binding is gone, and pressing OK would write the stale text back and undo
    // the extension's change, so the difference is merged into the text instead.
    property var _knownExcludedSites: App.settings.excludedSites.slice()
    Connections {
        target: App.settings
        function onExcludedSitesChanged() {
            var now = App.settings.excludedSites
            var before = root._knownExcludedSites
            root._knownExcludedSites = now.slice()
            if (!excludedSitesArea)
                return
            var tokens = excludedSitesArea.text.split(/[\s,]+/).filter(function(s) { return s.length > 0 })
            var changed = false
            now.forEach(function(site) {
                if (before.indexOf(site) < 0 && tokens.indexOf(site) < 0) { tokens.push(site); changed = true }
            })
            before.forEach(function(site) {
                var i = tokens.indexOf(site)
                if (now.indexOf(site) < 0 && i >= 0) { tokens.splice(i, 1); changed = true }
            })
            if (changed)
                excludedSitesArea.text = tokens.join(" ")
        }
    }

    Connections {
        target: App
        function onIpToCityDbInfoChanged() {
            root.ipToCityDbInfo = App.ipToCityDbInfo
        }
    }

    // Track whether anything has been changed
    readonly property bool settingsChanged:
        editMaxConcurrent         !== App.settings.maxConcurrent        ||
        editMaxConcurrentTorrents !== App.settings.maxConcurrentTorrents ||
        editGlobalDownloadLimitEnabled !== App.settings.globalDownloadLimitEnabled ||
        editGlobalDownloadLimitMBytes  !== App.settings.globalDownloadLimitMBytes  ||
        editGlobalDownloadLimitHours   !== App.settings.globalDownloadLimitHours   ||
        editGlobalDownloadLimitWarn    !== App.settings.globalDownloadLimitWarn    ||
        editSegmentsPerDownload   !== App.settings.segmentsPerDownload  ||
        editPerServerConnLimitsJson !== App.settings.perServerConnLimitsJson ||
        editDefaultSavePath       !== App.settings.defaultSavePath      ||
        editTemporaryDirectory    !== App.settings.temporaryDirectory   ||
        editTorrentCustomSavePath !== App.settings.torrentCustomSavePath ||
        editMinimizeToTray        !== App.settings.minimizeToTray       ||
        editCloseToTray           !== App.settings.closeToTray          ||
        editShowTips              !== App.settings.showTips             ||
        editMaxRetries            !== App.settings.maxRetries           ||
        editConnectionTimeoutSecs !== App.settings.connectionTimeoutSecs ||
        editDuplicateAction       !== App.settings.duplicateAction  ||
        editStartImmediately      !== App.settings.startImmediately ||
        editSpeedLimiterOnStartup !== App.settings.speedLimiterOnStartup ||
        editGlobalSpeedLimitEnabled !== App.settings.speedLimiterEnabled ||
        editGlobalUploadLimitKBps !== editSavedUploadLimitKBpsBaseline ||
        editStartDownloadWhileFileInfo !== App.settings.startDownloadWhileFileInfo ||
        editFillDescriptionMetadata !== App.settings.fillDescriptionMetadata ||
        editUseCustomUserAgent    !== App.settings.useCustomUserAgent ||
        editCustomUserAgent       !== App.settings.customUserAgent ||
        editShowQueueSelectionOnDownloadLater !== App.settings.showQueueSelectionOnDownloadLater ||
        editShowQueueSelectionOnBatchDownload  !== App.settings.showQueueSelectionOnBatchDownload ||
        editBypassInterceptKey    !== App.settings.bypassInterceptKey ||
        editSavedSpeedLimitKBps   !== App.settings.savedSpeedLimitKBps ||
        editShowDownloadComplete  !== App.settings.showDownloadComplete ||
        editShowCompletionNotification !== App.settings.showCompletionNotification ||
        editShowErrorNotification !== App.settings.showErrorNotification ||
        editSpeedInTrayTooltip    !== App.settings.speedInTrayTooltip ||
        editSpeedInTitleBar       !== App.settings.speedInTitleBar ||
        editSpeedInStatusBar      !== App.settings.speedInStatusBar ||
        editRatioInStatusBar      !== App.settings.ratioInStatusBar ||
        editConnectionsInStatusBar !== App.settings.connectionsInStatusBar ||
        editDhtNodesInStatusBar    !== App.settings.dhtNodesInStatusBar ||
        editShowPublicIpInStatusBar !== App.settings.showPublicIpInStatusBar ||
        editLaunchOnStartup       !== App.settings.launchOnStartup ||
        editTorrentStopOnStartup  !== App.settings.torrentStopOnStartup ||
        editClipboardMonitorEnabled !== App.settings.clipboardMonitorEnabled ||
        editDoubleClickAction     !== App.settings.doubleClickAction ||
        editSpeedScheduleEnabled  !== App.settings.speedScheduleEnabled ||
        editSpeedScheduleJson     !== App.settings.speedScheduleJson ||
        editAutoCheckUpdates      !== App.settings.autoCheckUpdates ||
        editLastTryDateStyle      !== App.settings.lastTryDateStyle ||
        editLastTryUse24Hour      !== App.settings.lastTryUse24Hour ||
        editLastTryShowSeconds    !== App.settings.lastTryShowSeconds ||
        editYtdlpCustomBinaryPath !== App.settings.ytdlpCustomBinaryPath ||
        editYtdlpAutoUpdate            !== App.settings.ytdlpAutoUpdate            ||
        editYtdlpJsRuntimePath         !== App.settings.ytdlpJsRuntimePath         ||
        editYtdlpDefaultCookieBrowser  !== App.settings.ytdlpDefaultCookieBrowser  ||
        editTorrentEnabled        !== App.settings.torrentEnabled        ||
        editTorrentEnableDht      !== App.settings.torrentEnableDht      ||
        editTorrentDhtAutoSuspend !== App.settings.torrentDhtAutoSuspend ||
        editTorrentEnableLsd      !== App.settings.torrentEnableLsd      ||
        editTorrentEnableUpnp     !== App.settings.torrentEnableUpnp     ||
        editTorrentEnableNatPmp   !== App.settings.torrentEnableNatPmp   ||
        editTorrentEnablePex      !== App.settings.torrentEnablePex      ||
        editTorrentAnnounceToAllTiers    !== App.settings.torrentAnnounceToAllTiers    ||
        editTorrentAnnounceToAllTrackers !== App.settings.torrentAnnounceToAllTrackers ||
        editTorrentListenPort     !== App.settings.torrentListenPort     ||
        editTorrentConnectionsLimit !== App.settings.torrentConnectionsLimit ||
        editTorrentConnectionsLimitPerTorrent !== App.settings.torrentConnectionsLimitPerTorrent ||
        editTorrentUploadSlotsLimit !== App.settings.torrentUploadSlotsLimit ||
        editTorrentUploadSlotsLimitPerTorrent !== App.settings.torrentUploadSlotsLimitPerTorrent ||
        editTorrentProtocol !== App.settings.torrentProtocol ||
        editTorrentCustomUserAgent !== App.settings.torrentCustomUserAgent ||
        editTorrentBindInterface  !== App.settings.torrentBindInterface  ||
        editTorrentAllowDiscoveryWhenBound !== App.settings.torrentAllowDiscoveryWhenBound ||
        editTorrentBlockedPeerUserAgents !== App.settings.torrentBlockedPeerUserAgents ||
        JSON.stringify(editTorrentBlockedPeerCountries) !== JSON.stringify(App.settings.torrentBlockedPeerCountries) ||
        JSON.stringify(editTorrentBannedPeers) !== JSON.stringify(App.settings.torrentBannedPeers) ||
        editTorrentAutoBanAbusivePeers !== App.settings.torrentAutoBanAbusivePeers ||
        editTorrentAutoBanMediaPlayerPeers !== App.settings.torrentAutoBanMediaPlayerPeers ||
        editTorrentAnonymousMode !== App.settings.torrentAnonymousMode ||
        editTorrentEncryptionMode !== App.settings.torrentEncryptionMode ||
        editTorrentStorageMode    !== App.settings.torrentStorageMode    ||
        editTorrentPieceExtentAffinity !== App.settings.torrentPieceExtentAffinity ||
        editTorrentCoalesceReads  !== App.settings.torrentCoalesceReads  ||
        editTorrentCoalesceWrites !== App.settings.torrentCoalesceWrites ||
        editTorrentDiskIoType     !== App.settings.torrentDiskIoType     ||
        editTorrentDiskWriteQueueMiB !== App.settings.torrentDiskWriteQueueMiB ||
        editProxyType             !== App.settings.proxyType             ||
        editProxyHost             !== App.settings.proxyHost             ||
        editProxyPort             !== App.settings.proxyPort             ||
        editProxyUsername         !== App.settings.proxyUsername         ||
        editProxyPassword         !== App.settings.proxyPassword ||
        editRssEnabled                !== App.settings.rssEnabled              ||
        editRssRefreshIntervalMins    !== App.settings.rssRefreshIntervalMins  ||
        editRssSameHostDelayMs        !== App.settings.rssSameHostDelayMs      ||
        editRssMaxArticlesPerFeed     !== App.settings.rssMaxArticlesPerFeed   ||
        editRssAutoDownloadEnabled    !== App.settings.rssAutoDownloadEnabled  ||
        editRssSmartFilterRepack      !== App.settings.rssSmartFilterRepack    ||
        editRssSmartFiltersJson       !== App.settings.rssSmartFiltersJson     ||
        editUiLanguage                !== App.settings.uiLanguage ||
        editTrayIconStyle             !== App.settings.trayIconStyle ||
        editUiScaleFactor             !== App.settings.uiScaleFactor ||
        editUiFontPointSize           !== App.settings.uiFontPointSize ||
        editDarkMode                  !== App.settings.darkMode

    property bool catDirty:       false
    readonly property bool browserChanged:
        _normalizedMonitoredExtensionsText() !== App.settings.monitoredExtensions.join("|") ||
        _normalizedExcludedSitesText() !== App.settings.excludedSites.join("|") ||
        _normalizedExcludedAddressesText() !== App.settings.excludedAddresses.join("|") ||
        editShowExceptionsDialog !== App.settings.showExceptionsDialog

    readonly property bool hasChanges: settingsChanged || catDirty || browserChanged
    readonly property var visibleTorrentBannedPeers: (function() {
        var activeByEndpoint = {}
        var active = App.torrentBannedPeers || []
        for (var i = 0; i < active.length; ++i) {
            var peer = active[i]
            if (!peer || !peer.permanent)
                continue
            var endpoint = String(peer.endpoint || "")
            if (endpoint.length > 0)
                activeByEndpoint[endpoint] = peer
        }

        var out = []
        for (var j = 0; j < root.editTorrentBannedPeers.length; ++j) {
            var manualEndpoint = String(root.editTorrentBannedPeers[j] || "")
            if (manualEndpoint.length === 0)
                continue
            var existing = activeByEndpoint[manualEndpoint]
            out.push(existing ? existing : {
                endpoint: manualEndpoint,
                reason: qsTr("Manual ban"),
                countryCode: "",
                client: "",
                permanent: true
            })
        }
        return out
    })()

    RssDownloadRulesDialog {
        id: rssDownloadRulesDialog
    }

    Window {
        id: restartPrompt
        title: qsTr("Restart Required")
        width: 360
        height: promptCol.implicitHeight + 24
        flags: Qt.Dialog | Qt.WindowTitleHint | Qt.WindowCloseButtonHint | Qt.MSWindowsFixedSizeDialogHint
        modality: Qt.WindowModal
        transientParent: root
        color: ColorPalette.cardBg
        Material.theme: ColorPalette.materialTheme
    Material.foreground: ColorPalette.textPrimary
        Material.background: ColorPalette.materialBg
        Material.accent: "#4488dd"

        property string promptText: ""

        function open() {
            x = root.x + Math.round((root.width  - width)  / 2)
            y = root.y + Math.round((root.height - height) / 2)
            show()
            raise()
            requestActivate()
        }

        ColumnLayout {
            id: promptCol
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 16 }
            spacing: 16

            Text {
                Layout.fillWidth: true
                text: restartPrompt.promptText
                color: ColorPalette.textPrimary
                font.pixelSize: 12 * App.fontScale
                wrapMode: Text.WordWrap
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Item { Layout.fillWidth: true }

                DlgButton {
                    text: qsTr("Restart Now")
                    primary: true
                    onClicked: App.restartApp()
                }
                DlgButton {
                    text: qsTr("Later")
                    onClicked: restartPrompt.close()
                }
            }
        }
    }

    FolderDialog {
        id: saveFolderDlg
        currentFolder: root.editDefaultSavePath.length > 0
                       ? fileUrlFromPath(root.editDefaultSavePath) : ""
        onAccepted: {
            var path = pathFromFileUrl(folder)
            root.editDefaultSavePath = path
        }
    }

    FolderDialog {
        id: tempFolderDlg
        currentFolder: root.editTemporaryDirectory.length > 0
                       ? fileUrlFromPath(root.editTemporaryDirectory) : ""
        onAccepted: {
            var path = pathFromFileUrl(folder)
            root.editTemporaryDirectory = path
        }
    }

    FolderDialog {
        id: torrentCustomSaveFolderDlg
        currentFolder: root.editTorrentCustomSavePath.length > 0
                       ? fileUrlFromPath(root.editTorrentCustomSavePath) : ""
        onAccepted: {
            var path = pathFromFileUrl(folder)
            root.editTorrentCustomSavePath = path
        }
    }

    // File picker for a custom yt-dlp binary location
    FileDialog {
        id: ytdlpFileDlg
        title: qsTr("Select yt-dlp binary")
        fileMode: FileDialog.OpenFile
        nameFilters: Qt.platform.os === "windows"
                     ? ["yt-dlp executable (yt-dlp.exe)", "All files (*)"]
                     : ["yt-dlp executable (yt-dlp)", "All files (*)"]
        onAccepted: {
            var path = file.toString()
                .replace(/^file:\/\/\//, "").replace(/^file:\/\//, "")
            root.editYtdlpCustomBinaryPath = path
        }
    }

    // File picker for a custom JS runtime (deno/node/bun/qjs) location
    FileDialog {
        id: jsRuntimeFileDlg
        title: qsTr("Select JavaScript runtime binary")
        fileMode: FileDialog.OpenFile
        nameFilters: Qt.platform.os === "windows"
                     ? ["Executable (*.exe)", "All files (*)"]
                     : ["All files (*)"]
        onAccepted: {
            var path = file.toString()
                .replace(/^file:\/\/\//, "").replace(/^file:\/\//, "")
            root.editYtdlpJsRuntimePath = path
        }
    }

    // Backup & Restore: export all data to / import all data from a .stellarbackup file
    FileDialog {
        id: exportBackupDlg
        title: qsTr("Export Stellar Backup")
        fileMode: FileDialog.SaveFile
        defaultSuffix: "stellarbackup"
        nameFilters: ["Stellar backup (*.stellarbackup)", "All files (*)"]
        onAccepted: App.exportAllData(root.pathFromFileUrl(file))
    }

    FileDialog {
        id: importBackupDlg
        title: qsTr("Import Stellar Backup")
        fileMode: FileDialog.OpenFile
        nameFilters: ["Stellar backup (*.stellarbackup)", "All files (*)"]
        onAccepted: App.importAllData(root.pathFromFileUrl(file), true)
    }

    // Result feedback for backup/restore.
    Connections {
        target: App
        function onDataExported(path) {
            exportResultDlg.promptText =
                qsTr("Your data was exported to:\n%1").arg(path)
            exportResultDlg.open()
        }
        function onDataImported() {
            importResultDlg.open()
        }
    }

    // Themed export-success dialog (in-app Window, matches the rest of the UI).
    Window {
        id: exportResultDlg
        title: qsTr("Backup Complete")
        width: 360
        height: exportResultCol.implicitHeight + 24
        flags: Qt.Dialog | Qt.WindowTitleHint | Qt.WindowCloseButtonHint | Qt.MSWindowsFixedSizeDialogHint
        modality: Qt.WindowModal
        transientParent: root
        color: ColorPalette.cardBg
        Material.theme: ColorPalette.materialTheme
    Material.foreground: ColorPalette.textPrimary
        Material.background: ColorPalette.materialBg
        Material.accent: "#4488dd"

        property string promptText: ""

        function open() {
            x = root.x + Math.round((root.width  - width)  / 2)
            y = root.y + Math.round((root.height - height) / 2)
            show(); raise(); requestActivate()
        }

        ColumnLayout {
            id: exportResultCol
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 16 }
            spacing: 16

            Text {
                Layout.fillWidth: true
                text: exportResultDlg.promptText
                color: ColorPalette.textPrimary
                font.pixelSize: 12 * App.fontScale
                wrapMode: Text.WordWrap
            }

            RowLayout {
                Layout.fillWidth: true
                Item { Layout.fillWidth: true }
                DlgButton {
                    text: qsTr("OK")
                    primary: true
                    onClicked: exportResultDlg.close()
                }
            }
        }
    }

    // Themed import-success dialog. The restart is triggered by the button click
    // (not automatically) so the user keeps control and the relaunch is reliable.
    Window {
        id: importResultDlg
        title: qsTr("Import Complete")
        width: 380
        height: importResultCol.implicitHeight + 24
        flags: Qt.Dialog | Qt.WindowTitleHint | Qt.MSWindowsFixedSizeDialogHint
        modality: Qt.WindowModal
        transientParent: root
        color: ColorPalette.cardBg
        Material.theme: ColorPalette.materialTheme
    Material.foreground: ColorPalette.textPrimary
        Material.background: ColorPalette.materialBg
        Material.accent: "#4488dd"

        function open() {
            x = root.x + Math.round((root.width  - width)  / 2)
            y = root.y + Math.round((root.height - height) / 2)
            show(); raise(); requestActivate()
        }

        ColumnLayout {
            id: importResultCol
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 16 }
            spacing: 16

            Text {
                Layout.fillWidth: true
                text: qsTr("Your data was restored successfully. Stellar needs to restart to apply it.")
                color: ColorPalette.textPrimary
                font.pixelSize: 12 * App.fontScale
                wrapMode: Text.WordWrap
            }

            RowLayout {
                Layout.fillWidth: true
                Item { Layout.fillWidth: true }
                DlgButton {
                    text: qsTr("Restart Now")
                    primary: true
                    onClicked: App.restartApp()
                }
            }
        }
    }

    // ── Category editor ───────────────────────────────────────────────────
    // Categories live in App.categoryModel rather than in edit* properties: the
    // form is written back whenever another category is selected and on Apply.

    function flushCategoryForm() {
        if (catPage.catEditId === "")
            return
        var exts = catEditExts.text.split(/[\s,]+/).map(function(s) {
            return s.trim().replace(/^\./, "").toLowerCase()
        }).filter(function(s) { return s.length > 0 })
        var sites = catEditSites.text.split(/\s+/).filter(function(s) { return s.length > 0 })
        App.categoryModel.updateCategory(catPage.catEditId, catEditName.text.trim(), exts, sites, catEditPath.text.trim())
    }

    function loadCategory(index) {
        var d = App.categoryModel.categoryData(index)
        // "all" is the built-in All Downloads view: nothing to edit.
        if (!d || !d.id || d.id === "all") {
            catPage.catEditId = ""
            return
        }
        catEditName.text  = d.label || ""
        catEditExts.text  = (d.extensions || []).join(" ").toUpperCase()
        catEditSites.text = (d.sitePatterns || []).join(" ")
        catEditPath.text  = (d.savePath || "").replace(/\\/g, "/")
        catPage.catEditBuiltIn = !!d.builtIn
        catPage.catEditId = d.id
    }

    function removeCurrentCategory() {
        if (catPage.catEditBuiltIn || catPage.catEditId === "")
            return
        var id = catPage.catEditId
        catPage.catEditId = ""   // the removed category must not be flushed back
        App.categoryModel.removeCategory(id)
        // Row 0 is the hidden All Downloads view; show the first real category.
        // If the selection already sits on row 1 no change signal fires, so load
        // whatever category moved into it.
        if (catEditList.currentIndex === 1)
            loadCategory(1)
        else
            catEditList.currentIndex = 1
    }

    // The Browser text areas edit the saved lists directly (not edit*
    // properties), so reopening after Cancel must put their text back.
    function resetBrowserFields() {
        monitoredExtsArea.text = App.settings.monitoredExtensions.join(" ").toUpperCase()
        excludedSitesArea.text = App.settings.excludedSites.join(" ")
        excludedAddrsArea.text = App.settings.excludedAddresses.join("\n")
    }

    function applySettings() {
        flushCategoryForm()
        catDirty = false

        // Flush browser integration settings
        if (browserChanged) {
            var monExts = monitoredExtsArea.text.split(/[\s,]+/).map(function(s) {
                return s.trim().toLowerCase().replace(/^\./, "")
            }).filter(function(s) { return s.length > 0 })
            App.settings.monitoredExtensions = monExts

            var excSites = excludedSitesArea.text.split(/[\s,]+/).filter(function(s) { return s.length > 0 })
            App.settings.excludedSites = excSites

            var excAddrs = excludedAddrsArea.text.split("\n").map(function(s) {
                return s.trim()
            }).filter(function(s) { return s.length > 0 })
            App.settings.excludedAddresses = excAddrs

            App.settings.showExceptionsDialog = editShowExceptionsDialog
        }

        App.settings.maxConcurrent         = editMaxConcurrent
        App.settings.maxConcurrentTorrents = editMaxConcurrentTorrents
        App.settings.globalDownloadLimitEnabled = editGlobalDownloadLimitEnabled
        App.settings.globalDownloadLimitMBytes  = editGlobalDownloadLimitMBytes
        App.settings.globalDownloadLimitHours   = editGlobalDownloadLimitHours
        App.settings.globalDownloadLimitWarn    = editGlobalDownloadLimitWarn
        App.settings.segmentsPerDownload   = editSegmentsPerDownload
        App.settings.perServerConnLimitsJson = editPerServerConnLimitsJson
        App.settings.defaultSavePath       = editDefaultSavePath
        App.settings.temporaryDirectory    = editTemporaryDirectory
        App.settings.torrentCustomSavePath = editTorrentCustomSavePath
        App.settings.savedSpeedLimitKBps   = editSavedSpeedLimitKBps
        App.settings.speedLimiterEnabled   = editGlobalSpeedLimitEnabled
        if (editGlobalSpeedLimitEnabled) {
            App.settings.globalSpeedLimitKBps  = editSavedSpeedLimitKBps
            App.settings.globalUploadLimitKBps = editGlobalUploadLimitKBps
        } else {
            editSavedUploadLimitKBps = editGlobalUploadLimitKBps
            App.settings.globalSpeedLimitKBps  = 0
            App.settings.globalUploadLimitKBps = 0
        }
        App.settings.minimizeToTray        = editMinimizeToTray
        App.settings.closeToTray           = editCloseToTray
        App.settings.trayIconStyle         = editTrayIconStyle
        App.settings.showTips              = editShowTips
        App.settings.maxRetries            = editMaxRetries
        App.settings.connectionTimeoutSecs = editConnectionTimeoutSecs
        App.settings.duplicateAction       = editDuplicateAction
        App.settings.startImmediately       = editStartImmediately
        App.settings.speedLimiterOnStartup  = editSpeedLimiterOnStartup
        App.settings.startDownloadWhileFileInfo = editStartDownloadWhileFileInfo
        App.settings.fillDescriptionMetadata = editFillDescriptionMetadata
        App.settings.showQueueSelectionOnDownloadLater = editShowQueueSelectionOnDownloadLater
        App.settings.showQueueSelectionOnBatchDownload  = editShowQueueSelectionOnBatchDownload
        App.settings.useCustomUserAgent    = editUseCustomUserAgent
        App.settings.customUserAgent       = editCustomUserAgent
        App.settings.bypassInterceptKey    = editBypassInterceptKey
        App.settings.showDownloadComplete   = editShowDownloadComplete
        App.settings.showCompletionNotification = editShowCompletionNotification
        App.settings.showErrorNotification  = editShowErrorNotification
        App.settings.speedInTrayTooltip     = editSpeedInTrayTooltip
        App.settings.speedInTitleBar        = editSpeedInTitleBar
        App.settings.speedInStatusBar       = editSpeedInStatusBar
        App.settings.ratioInStatusBar       = editRatioInStatusBar
        App.settings.connectionsInStatusBar = editConnectionsInStatusBar
        App.settings.dhtNodesInStatusBar    = editDhtNodesInStatusBar
        App.settings.showPublicIpInStatusBar = editShowPublicIpInStatusBar
        App.settings.launchOnStartup        = editLaunchOnStartup
        App.settings.torrentStopOnStartup   = editTorrentStopOnStartup
        App.settings.clipboardMonitorEnabled = editClipboardMonitorEnabled
        App.settings.doubleClickAction      = editDoubleClickAction
        App.settings.speedScheduleEnabled   = editSpeedScheduleEnabled
        App.settings.speedScheduleJson      = editSpeedScheduleJson
        App.settings.autoCheckUpdates       = editAutoCheckUpdates
        App.settings.lastTryDateStyle       = editLastTryDateStyle
        App.settings.lastTryUse24Hour       = editLastTryUse24Hour
        App.settings.lastTryShowSeconds     = editLastTryShowSeconds
        App.settings.ytdlpCustomBinaryPath  = editYtdlpCustomBinaryPath
        App.settings.ytdlpAutoUpdate             = editYtdlpAutoUpdate
        App.settings.ytdlpJsRuntimePath          = editYtdlpJsRuntimePath
        App.settings.ytdlpDefaultCookieBrowser   = editYtdlpDefaultCookieBrowser
        App.settings.torrentEnabled         = editTorrentEnabled
        App.settings.torrentEnableDht       = editTorrentEnableDht
        App.settings.torrentDhtAutoSuspend  = editTorrentDhtAutoSuspend
        App.settings.torrentEnableLsd       = editTorrentEnableLsd
        App.settings.torrentEnableUpnp      = editTorrentEnableUpnp
        App.settings.torrentEnableNatPmp    = editTorrentEnableNatPmp
        App.settings.torrentEnablePex       = editTorrentEnablePex
        App.settings.torrentAnnounceToAllTiers    = editTorrentAnnounceToAllTiers
        App.settings.torrentAnnounceToAllTrackers = editTorrentAnnounceToAllTrackers
        App.settings.torrentListenPort      = editTorrentListenPort
        App.settings.torrentConnectionsLimit = editTorrentConnectionsLimit
        App.settings.torrentConnectionsLimitPerTorrent = editTorrentConnectionsLimitPerTorrent
        App.settings.torrentUploadSlotsLimit = editTorrentUploadSlotsLimit
        App.settings.torrentUploadSlotsLimitPerTorrent = editTorrentUploadSlotsLimitPerTorrent
        App.settings.torrentProtocol = editTorrentProtocol
        App.settings.torrentCustomUserAgent = editTorrentCustomUserAgent
        App.settings.torrentBindInterface   = editTorrentBindInterface
        App.settings.torrentAllowDiscoveryWhenBound = editTorrentAllowDiscoveryWhenBound
        App.settings.torrentBlockedPeerUserAgents = editTorrentBlockedPeerUserAgents
        App.settings.torrentBlockedPeerCountries = editTorrentBlockedPeerCountries
        App.settings.torrentBannedPeers = editTorrentBannedPeers
        App.settings.torrentAutoBanAbusivePeers = editTorrentAutoBanAbusivePeers
        App.settings.torrentAutoBanMediaPlayerPeers = editTorrentAutoBanMediaPlayerPeers
        App.settings.torrentAnonymousMode = editTorrentAnonymousMode
        App.settings.torrentEncryptionMode = editTorrentEncryptionMode
        App.settings.torrentStorageMode    = editTorrentStorageMode
        App.settings.torrentPieceExtentAffinity = editTorrentPieceExtentAffinity
        App.settings.torrentCoalesceReads  = editTorrentCoalesceReads
        App.settings.torrentCoalesceWrites = editTorrentCoalesceWrites
        App.settings.torrentDiskIoType     = editTorrentDiskIoType
        App.settings.torrentDiskWriteQueueMiB = editTorrentDiskWriteQueueMiB
        App.settings.proxyType              = editProxyType
        App.settings.proxyHost              = editProxyHost
        App.settings.proxyPort              = editProxyPort
        App.settings.proxyUsername          = editProxyUsername
        App.settings.proxyPassword          = editProxyPassword
        App.settings.rssEnabled             = editRssEnabled
        App.settings.rssRefreshIntervalMins = editRssRefreshIntervalMins
        App.settings.rssSameHostDelayMs     = editRssSameHostDelayMs
        App.settings.rssMaxArticlesPerFeed  = editRssMaxArticlesPerFeed
        App.settings.rssAutoDownloadEnabled = editRssAutoDownloadEnabled
        App.settings.rssSmartFilterRepack   = editRssSmartFilterRepack
        App.settings.rssSmartFiltersJson    = editRssSmartFiltersJson
        var languageChanged    = editUiLanguage      !== App.settings.uiLanguage
        var appearanceChanged  = editUiScaleFactor   !== App.settings.uiScaleFactor
                              || editUiFontPointSize  !== App.settings.uiFontPointSize
        if (languageChanged)
            App.applyUiLanguage(editUiLanguage)
        App.settings.uiScaleFactor   = editUiScaleFactor
        App.settings.uiFontPointSize = editUiFontPointSize
        App.settings.darkMode        = editDarkMode
        App.settings.save()
        // Sync edit properties so settingsChanged resets to false
        resetEdits()
        if (languageChanged) {
            restartPrompt.promptText = qsTr("A restart is required for the language change to take effect. Restart now?")
            restartPrompt.open()
        } else if (appearanceChanged) {
            restartPrompt.promptText = qsTr("A restart is required for appearance changes to take effect. Restart now?")
            restartPrompt.open()
        }
    }

    function resetEdits() {
        refreshTorrentNetworkAdapters()
        editMaxConcurrent         = App.settings.maxConcurrent
        editMaxConcurrentTorrents = App.settings.maxConcurrentTorrents
        editGlobalDownloadLimitEnabled = App.settings.globalDownloadLimitEnabled
        editGlobalDownloadLimitMBytes  = App.settings.globalDownloadLimitMBytes
        editGlobalDownloadLimitHours   = App.settings.globalDownloadLimitHours
        editGlobalDownloadLimitWarn    = App.settings.globalDownloadLimitWarn
        editSegmentsPerDownload   = App.settings.segmentsPerDownload
        editPerServerConnLimitsJson = App.settings.perServerConnLimitsJson || "[]"
        reloadServerConnModel()
        editDefaultSavePath       = App.settings.defaultSavePath
        editTemporaryDirectory    = App.settings.temporaryDirectory
        editTorrentCustomSavePath = App.settings.torrentCustomSavePath
        editSavedSpeedLimitKBps   = App.settings.savedSpeedLimitKBps
        var activeUpload = App.settings.globalUploadLimitKBps
        var activeDown   = App.settings.globalSpeedLimitKBps
        if (activeDown > 0 || activeUpload > 0)
            editSavedUploadLimitKBps = activeUpload
        editGlobalUploadLimitKBps = editSavedUploadLimitKBps
        editSavedUploadLimitKBpsBaseline = editSavedUploadLimitKBps
        editMinimizeToTray        = App.settings.minimizeToTray
        editCloseToTray           = App.settings.closeToTray
        editTrayIconStyle         = App.settings.trayIconStyle
        editShowTips              = App.settings.showTips
        editShowExceptionsDialog  = App.settings.showExceptionsDialog
        editMaxRetries            = App.settings.maxRetries
        editConnectionTimeoutSecs = App.settings.connectionTimeoutSecs
        editDuplicateAction       = App.settings.duplicateAction
        editStartImmediately      = App.settings.startImmediately
        editSpeedLimiterOnStartup = App.settings.speedLimiterOnStartup
        editGlobalSpeedLimitEnabled = App.settings.speedLimiterEnabled
        editStartDownloadWhileFileInfo = App.settings.startDownloadWhileFileInfo
        editFillDescriptionMetadata = App.settings.fillDescriptionMetadata
        editShowQueueSelectionOnDownloadLater = App.settings.showQueueSelectionOnDownloadLater
        editShowQueueSelectionOnBatchDownload  = App.settings.showQueueSelectionOnBatchDownload
        editUseCustomUserAgent    = App.settings.useCustomUserAgent
        editCustomUserAgent       = App.settings.customUserAgent
        editBypassInterceptKey    = App.settings.bypassInterceptKey
        editShowDownloadComplete  = App.settings.showDownloadComplete
        editShowCompletionNotification = App.settings.showCompletionNotification
        editShowErrorNotification = App.settings.showErrorNotification
        editSpeedInTrayTooltip    = App.settings.speedInTrayTooltip
        editSpeedInTitleBar       = App.settings.speedInTitleBar
        editSpeedInStatusBar      = App.settings.speedInStatusBar
        editRatioInStatusBar      = App.settings.ratioInStatusBar
        editConnectionsInStatusBar = App.settings.connectionsInStatusBar
        editDhtNodesInStatusBar    = App.settings.dhtNodesInStatusBar
        editShowPublicIpInStatusBar = App.settings.showPublicIpInStatusBar
        editLaunchOnStartup       = App.settings.launchOnStartup
        editTorrentStopOnStartup  = App.settings.torrentStopOnStartup
        editClipboardMonitorEnabled = App.settings.clipboardMonitorEnabled
        editDoubleClickAction     = App.settings.doubleClickAction
        editSpeedScheduleEnabled  = App.settings.speedScheduleEnabled
        editSpeedScheduleJson     = App.settings.speedScheduleJson || "[]"
        editAutoCheckUpdates      = App.settings.autoCheckUpdates
        editLastTryDateStyle      = App.settings.lastTryDateStyle
        editLastTryUse24Hour      = App.settings.lastTryUse24Hour
        editLastTryShowSeconds    = App.settings.lastTryShowSeconds
        editYtdlpCustomBinaryPath = App.settings.ytdlpCustomBinaryPath
        editYtdlpAutoUpdate            = App.settings.ytdlpAutoUpdate
        editYtdlpJsRuntimePath         = App.settings.ytdlpJsRuntimePath
        editYtdlpDefaultCookieBrowser  = App.settings.ytdlpDefaultCookieBrowser
        editTorrentEnabled        = App.settings.torrentEnabled
        editTorrentEnableDht      = App.settings.torrentEnableDht
        editTorrentDhtAutoSuspend = App.settings.torrentDhtAutoSuspend
        editTorrentEnableLsd      = App.settings.torrentEnableLsd
        editTorrentEnableUpnp     = App.settings.torrentEnableUpnp
        editTorrentEnableNatPmp   = App.settings.torrentEnableNatPmp
        editTorrentEnablePex      = App.settings.torrentEnablePex
        editTorrentAnnounceToAllTiers    = App.settings.torrentAnnounceToAllTiers
        editTorrentAnnounceToAllTrackers = App.settings.torrentAnnounceToAllTrackers
        editTorrentListenPort     = App.settings.torrentListenPort
        editTorrentConnectionsLimit = App.settings.torrentConnectionsLimit
        editTorrentConnectionsLimitPerTorrent = App.settings.torrentConnectionsLimitPerTorrent
        editTorrentUploadSlotsLimit = App.settings.torrentUploadSlotsLimit
        editTorrentUploadSlotsLimitPerTorrent = App.settings.torrentUploadSlotsLimitPerTorrent
        editTorrentProtocol = App.settings.torrentProtocol
        editTorrentCustomUserAgent = App.settings.torrentCustomUserAgent
        editTorrentBindInterface  = App.settings.torrentBindInterface
        editTorrentAllowDiscoveryWhenBound = App.settings.torrentAllowDiscoveryWhenBound
        editTorrentBlockedPeerUserAgents = App.settings.torrentBlockedPeerUserAgents
        editTorrentBlockedPeerCountries = App.settings.torrentBlockedPeerCountries.slice()
        editTorrentBannedPeers = App.settings.torrentBannedPeers.slice()
        editTorrentAutoBanAbusivePeers = App.settings.torrentAutoBanAbusivePeers
        editTorrentAutoBanMediaPlayerPeers = App.settings.torrentAutoBanMediaPlayerPeers
        editTorrentAnonymousMode = App.settings.torrentAnonymousMode
        editTorrentEncryptionMode = App.settings.torrentEncryptionMode
        editTorrentStorageMode    = App.settings.torrentStorageMode
        editTorrentPieceExtentAffinity = App.settings.torrentPieceExtentAffinity
        editTorrentCoalesceReads  = App.settings.torrentCoalesceReads
        editTorrentCoalesceWrites = App.settings.torrentCoalesceWrites
        editTorrentDiskIoType     = App.settings.torrentDiskIoType
        editTorrentDiskWriteQueueMiB = App.settings.torrentDiskWriteQueueMiB
        ensureTorrentAdapterOption(editTorrentBindInterface)
        editProxyType             = App.settings.proxyType
        editProxyHost             = App.settings.proxyHost
        editProxyPort             = App.settings.proxyPort
        editProxyUsername         = App.settings.proxyUsername
        editProxyPassword         = App.settings.proxyPassword
        editRssEnabled             = App.settings.rssEnabled
        editRssRefreshIntervalMins = App.settings.rssRefreshIntervalMins
        editRssSameHostDelayMs     = App.settings.rssSameHostDelayMs
        editRssMaxArticlesPerFeed  = App.settings.rssMaxArticlesPerFeed
        editRssAutoDownloadEnabled = App.settings.rssAutoDownloadEnabled
        editRssSmartFilterRepack   = App.settings.rssSmartFilterRepack
        editRssSmartFiltersJson    = App.settings.rssSmartFiltersJson || "[]"
        editUiLanguage             = App.settings.uiLanguage
        editUiScaleFactor          = App.settings.uiScaleFactor
        editUiFontPointSize        = App.settings.uiFontPointSize
        editDarkMode               = App.settings.darkMode
        resetBrowserFields()
        loadCategory(catEditList.currentIndex)
        // Reset dirty flags so Apply button is disabled until user actually changes something
        catDirty = false
    }

    // Small label above a field in stacked forms (category editor, rule cards).
    component FormLabel: Text {
        color: ColorPalette.textSecond
        font.pixelSize: 12 * App.fontScale
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 0

            // ── Sidebar ─────────────────────────────────────────────────────
            Rectangle {
                Layout.fillHeight: true
                Layout.preferredWidth: Math.ceil(navMeasure.implicitWidth) + 28
                color: ColorPalette.panelBg

                // Longest page name at the sidebar font, so the sidebar is only as
                // wide as a translation needs.
                Column {
                    id: navMeasure
                    visible: false
                    Repeater {
                        model: catList.model
                        Text { required property string modelData; text: modelData; font.pixelSize: 13 * App.fontScale }
                    }
                }

                ListView {
                    id: catList
                    anchors.fill: parent
                    anchors.topMargin: 8
                    clip: true
                    interactive: contentHeight > height
                    model: [qsTr("Connection"), qsTr("Categories"), qsTr("Downloads"), qsTr("Browser"), qsTr("Speed Limiter"), qsTr("Notifications"), qsTr("General"), qsTr("Media"), qsTr("Torrents"), qsTr("RSS"), qsTr("Associations"), qsTr("Language"), qsTr("About")]
                    currentIndex: root.initialPage

                    delegate: Rectangle {
                        required property int index
                        required property string modelData
                        readonly property bool selected: catList.currentIndex === index

                        width: ListView.view.width
                        height: 30
                        color: selected ? ColorPalette.selectionBg
                             : (navArea.containsMouse ? ColorPalette.hoverBg : "transparent")

                        // Accent edge marks the open page, as in the main window's sidebar.
                        Rectangle {
                            anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
                            width: 3
                            color: ColorPalette.accent
                            visible: parent.selected
                        }

                        Text {
                            anchors { verticalCenter: parent.verticalCenter; left: parent.left; leftMargin: 16; right: parent.right; rightMargin: 8 }
                            text: parent.modelData
                            color: parent.selected ? ColorPalette.selectionText : ColorPalette.textPrimary
                            font.pixelSize: 13 * App.fontScale
                            elide: Text.ElideRight
                        }

                        MouseArea {
                            id: navArea
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: catList.currentIndex = parent.index
                        }
                    }
                }
            }

            Rectangle {
                Layout.fillHeight: true
                implicitWidth: 1
                color: ColorPalette.border
            }

            // ── Pages (order = page indices; see initialPage) ────────────────
            StackLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                currentIndex: catList.currentIndex

                // 0 ── Connection ─────────────────────────────────────────────
                SettingsPage {
                    title: qsTr("Connection")

                    SettingsScroll {
                        SettingsSection {
                            title: qsTr("Connections")

                            SettingsRow {
                                label: qsTr("Simultaneous downloads")
                                SettingsNumber { from: 1; to: 16; value: root.editMaxConcurrent; onEdited: (v) => root.editMaxConcurrent = v }
                            }
                            SettingsRow {
                                label: qsTr("Simultaneous torrents")
                                SettingsNumber { from: 1; to: 50; value: root.editMaxConcurrentTorrents; onEdited: (v) => root.editMaxConcurrentTorrents = v }
                            }
                            SettingsRow {
                                label: qsTr("Connections per download")
                                SettingsNumber { from: 1; to: 32; value: root.editSegmentsPerDownload; onEdited: (v) => root.editSegmentsPerDownload = v }
                            }
                            SettingsRow {
                                label: qsTr("Connection timeout")
                                SettingsNumber { from: 5; to: 120; suffix: qsTr("seconds"); value: root.editConnectionTimeoutSecs; onEdited: (v) => root.editConnectionTimeoutSecs = v }
                            }
                            SettingsRow {
                                label: qsTr("Retry failed downloads")
                                SettingsNumber { from: 0; to: 10; suffix: qsTr("times"); value: root.editMaxRetries; onEdited: (v) => root.editMaxRetries = v }
                            }
                        }

                        SettingsSection {
                            title: qsTr("Per-server connections")
                            description: qsTr("Override the connection count for specific servers. Use an asterisk (*) as a wildcard.")

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 10

                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 150
                                    color: ColorPalette.inputBg
                                    border.color: ColorPalette.border
                                    radius: 3
                                    clip: true

                                    ColumnLayout {
                                        anchors.fill: parent
                                        anchors.margins: 1
                                        spacing: 0

                                        Rectangle {
                                            Layout.fillWidth: true
                                            implicitHeight: 24
                                            color: ColorPalette.panelBg
                                            RowLayout {
                                                anchors { fill: parent; leftMargin: 8; rightMargin: 8 }
                                                Text { Layout.fillWidth: true; text: qsTr("Server"); color: ColorPalette.textSecond; font.pixelSize: 12 * App.fontScale; font.bold: true }
                                                Text { Layout.preferredWidth: 80; text: qsTr("Connections"); color: ColorPalette.textSecond; font.pixelSize: 12 * App.fontScale; font.bold: true }
                                            }
                                            Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: ColorPalette.border }
                                        }

                                        ListView {
                                            id: serverConnList
                                            Layout.fillWidth: true
                                            Layout.fillHeight: true
                                            clip: true
                                            // Only a list that overflows takes the wheel; otherwise it
                                            // reaches the page so scrolling doesn't stall here.
                                            interactive: contentHeight > height
                                            model: serverConnModel
                                            currentIndex: -1
                                            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                                            delegate: Rectangle {
                                                id: connRow
                                                required property int index
                                                required property string server
                                                required property int conns
                                                width: ListView.view.width
                                                height: 26
                                                color: serverConnList.currentIndex === index ? ColorPalette.selectionBg
                                                     : (index % 2 === 0 ? "transparent" : ColorPalette.rowAltBg)
                                                RowLayout {
                                                    anchors { fill: parent; leftMargin: 8; rightMargin: 8 }
                                                    Text { Layout.fillWidth: true; text: connRow.server; color: ColorPalette.textPrimary; font.pixelSize: 12 * App.fontScale; elide: Text.ElideRight }
                                                    Text { Layout.preferredWidth: 80; text: connRow.conns; color: ColorPalette.textPrimary; font.pixelSize: 12 * App.fontScale }
                                                }
                                                MouseArea {
                                                    anchors.fill: parent
                                                    onClicked: serverConnList.currentIndex = connRow.index
                                                    onDoubleClicked: { serverConnList.currentIndex = connRow.index; root.openServerConnDialog(connRow.index) }
                                                }
                                            }

                                            Text {
                                                anchors.centerIn: parent
                                                visible: serverConnList.count === 0
                                                text: qsTr("No exceptions")
                                                color: ColorPalette.textDisabled
                                                font.pixelSize: 12 * App.fontScale
                                            }
                                        }
                                    }
                                }

                                ColumnLayout {
                                    Layout.alignment: Qt.AlignTop
                                    Layout.fillWidth: false
                                    Layout.preferredWidth: 90
                                    spacing: 6
                                    DlgButton { text: qsTr("New");    Layout.fillWidth: true; onClicked: root.openServerConnDialog(-1) }
                                    DlgButton { text: qsTr("Edit");   Layout.fillWidth: true; enabled: serverConnList.currentIndex >= 0; onClicked: root.openServerConnDialog(serverConnList.currentIndex) }
                                    DlgButton { text: qsTr("Delete"); Layout.fillWidth: true; enabled: serverConnList.currentIndex >= 0; destructive: true; onClicked: root.deleteServerConnRule(serverConnList.currentIndex) }
                                }
                            }
                        }

                        SettingsSection {
                            title: qsTr("Global download limit")

                            SettingsCheck {
                                text: qsTr("Pause all downloads after a data limit is reached")
                                checked: root.editGlobalDownloadLimitEnabled
                                onToggled: (on) => root.editGlobalDownloadLimitEnabled = on
                            }
                            Flow {
                                Layout.fillWidth: true
                                Layout.leftMargin: 22
                                spacing: 8
                                enabled: root.editGlobalDownloadLimitEnabled
                                Text {
                                    height: 28
                                    verticalAlignment: Text.AlignVCenter
                                    text: qsTr("Download no more than")
                                    color: parent.enabled ? ColorPalette.textPrimary : ColorPalette.textDisabled
                                    font.pixelSize: 13 * App.fontScale
                                }
                                SettingsNumber { from: 1; to: 9999999; suffix: qsTr("MB every"); value: root.editGlobalDownloadLimitMBytes; onEdited: (v) => root.editGlobalDownloadLimitMBytes = v }
                                SettingsNumber { from: 1; to: 720; suffix: qsTr("hours"); value: root.editGlobalDownloadLimitHours; onEdited: (v) => root.editGlobalDownloadLimitHours = v }
                            }
                            SettingsCheck {
                                Layout.leftMargin: 22
                                enabled: root.editGlobalDownloadLimitEnabled
                                text: qsTr("Show a warning when the limit pauses downloads")
                                checked: root.editGlobalDownloadLimitWarn
                                onToggled: (on) => root.editGlobalDownloadLimitWarn = on
                            }
                        }

                        SettingsSection {
                            title: qsTr("User agent")

                            SettingsCheck {
                                text: qsTr("Use a custom user agent")
                                checked: root.editUseCustomUserAgent
                                onToggled: (on) => root.editUseCustomUserAgent = on
                            }
                            SettingsTextField {
                                value: root.displayedUserAgent
                                readOnly: !root.editUseCustomUserAgent
                                onEdited: (text) => root.editCustomUserAgent = text
                            }
                            SettingsHint {
                                text: root.editUseCustomUserAgent
                                      ? qsTr("This value will be sent exactly as entered.")
                                      : qsTr("Stellar's built-in user agent, shown for reference. Turn on the option above to replace it.")
                            }
                        }

                        SettingsSection {
                            title: qsTr("Proxy")

                            SettingsRow {
                                label: qsTr("Proxy type")
                                SettingsCombo {
                                    model: [qsTr("No proxy"), qsTr("Use system proxy"), qsTr("HTTP / HTTPS proxy"), qsTr("SOCKS5 proxy")]
                                    value: root.editProxyType
                                    onEdited: (index) => root.editProxyType = index
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                visible: root.editProxyType === 2 || root.editProxyType === 3
                                spacing: 8

                                SettingsRow {
                                    label: qsTr("Host")
                                    SettingsTextField { value: root.editProxyHost; onEdited: (text) => root.editProxyHost = text }
                                }
                                SettingsRow {
                                    label: qsTr("Port")
                                    SettingsNumber { from: 1; to: 65535; value: root.editProxyPort; onEdited: (v) => root.editProxyPort = v }
                                }
                                SettingsRow {
                                    label: qsTr("Username")
                                    SettingsTextField { placeholderText: qsTr("Optional"); value: root.editProxyUsername; onEdited: (text) => root.editProxyUsername = text }
                                }
                                SettingsRow {
                                    label: qsTr("Password")
                                    SettingsTextField { placeholderText: qsTr("Optional"); echoMode: TextInput.Password; value: root.editProxyPassword; onEdited: (text) => root.editProxyPassword = text }
                                }
                            }

                            SettingsHint {
                                visible: root.editProxyType !== 0
                                text: root.editProxyType === 1
                                      ? qsTr("Stellar will use the proxy configured in your operating system network settings.")
                                      : qsTr("All downloads, video downloads, update checks, and torrent peer/tracker connections are routed through this proxy.")
                            }

                            RowLayout {
                                id: proxyTestRow
                                visible: root.editProxyType !== 0
                                Layout.fillWidth: true
                                spacing: 10

                                property bool _testing: false
                                property string _result: ""
                                property bool _ok: false

                                Timer {
                                    id: proxyTestTimeout
                                    interval: 12000  // 2 s headroom over the 10 s network timeout
                                    repeat: false
                                    onTriggered: {
                                        if (proxyTestRow._testing) {
                                            proxyTestRow._testing = false
                                            proxyTestRow._ok = false
                                            proxyTestRow._result = qsTr("Timed out - proxy did not respond")
                                        }
                                    }
                                }

                                Connections {
                                    target: App
                                    function onProxyTestResult(success, message) {
                                        proxyTestTimeout.stop()
                                        proxyTestRow._testing = false
                                        proxyTestRow._ok = success
                                        proxyTestRow._result = message
                                    }
                                }

                                DlgButton {
                                    text: proxyTestRow._testing ? qsTr("Testing...") : qsTr("Test Proxy")
                                    enabled: !proxyTestRow._testing
                                    onClicked: {
                                        proxyTestRow._result = ""
                                        proxyTestRow._testing = true
                                        proxyTestTimeout.restart()
                                        App.testProxy()
                                    }
                                }
                                Text {
                                    Layout.fillWidth: true
                                    visible: proxyTestRow._result.length > 0
                                    text: proxyTestRow._result
                                    textFormat: Text.PlainText
                                    color: proxyTestRow._ok ? ColorPalette.successText : ColorPalette.errorText
                                    font.pixelSize: 12 * App.fontScale
                                    wrapMode: Text.WordWrap
                                }
                            }
                        }
                    }
                }

                // 1 ── Categories ─────────────────────────────────────────────
                SettingsPage {
                    id: catPage
                    title: qsTr("Categories")

                    property bool catEditBuiltIn: false
                    property string catEditId: ""

                    FolderDialog {
                        id: catSaveFolderDlg
                        currentFolder: catEditPath.text.length > 0 ? root.fileUrlFromPath(catEditPath.text) : ""
                        onAccepted: {
                            catEditPath.text = root.pathFromFileUrl(folder).replace(/\\/g, "/")
                            root.catDirty = true
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.margins: 16
                        spacing: 12

                        // Category list. Fixed width so a long extension list in the
                        // form can never push it around.
                        ColumnLayout {
                            id: catListColumn
                            // As wide as the longest category name (within limits), so
                            // the form keeps the width it needs in a compact window.
                            readonly property int listWidth: Math.max(96, Math.min(150, Math.ceil(catNameMeasure.implicitWidth) + 24))
                            Layout.fillHeight: true
                            Layout.preferredWidth: listWidth
                            Layout.minimumWidth: listWidth
                            Layout.maximumWidth: listWidth
                            spacing: 6

                            Column {
                                id: catNameMeasure
                                visible: false
                                Repeater {
                                    model: App.categoryModel
                                    Text { required property string categoryLabel; text: categoryLabel; font.pixelSize: 12 * App.fontScale }
                                }
                            }

                            Rectangle {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                color: ColorPalette.inputBg
                                border.color: ColorPalette.border
                                radius: 3
                                clip: true

                                ListView {
                                    id: catEditList
                                    anchors.fill: parent
                                    anchors.margins: 1
                                    clip: true
                                    interactive: contentHeight > height
                                    model: App.categoryModel
                                    // Row 0 is the built-in "All Downloads" view, which has
                                    // nothing to edit and is hidden below.
                                    currentIndex: 1
                                    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                                    Component.onCompleted: root.loadCategory(currentIndex)
                                    onCurrentIndexChanged: {
                                        root.flushCategoryForm()
                                        root.loadCategory(currentIndex)
                                    }

                                    delegate: Rectangle {
                                        required property int index
                                        required property string categoryId
                                        required property string categoryLabel
                                        readonly property bool selected: catEditList.currentIndex === index

                                        width: ListView.view.width
                                        visible: categoryId !== "all"
                                        height: visible ? 26 : 0
                                        color: selected ? ColorPalette.selectionBg
                                             : (catItemArea.containsMouse ? ColorPalette.hoverBg : "transparent")

                                        Text {
                                            anchors { verticalCenter: parent.verticalCenter; left: parent.left; leftMargin: 8; right: parent.right; rightMargin: 6 }
                                            text: parent.categoryLabel
                                            color: parent.selected ? ColorPalette.selectionText : ColorPalette.textPrimary
                                            font.pixelSize: 12 * App.fontScale
                                            elide: Text.ElideRight
                                        }
                                        MouseArea {
                                            id: catItemArea
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            enabled: parent.visible
                                            onClicked: catEditList.currentIndex = parent.index
                                        }
                                    }
                                }
                            }

                            RowLayout {
                                spacing: 6
                                SettingsIconButton {
                                    glyph: "+"
                                    toolTip: qsTr("Add category")
                                    onClicked: {
                                        App.categoryModel.addCategory("New Category")
                                        catEditList.currentIndex = App.categoryModel.categoryCount() - 1
                                    }
                                }
                                SettingsIconButton {
                                    glyph: "\u2212"
                                    toolTip: qsTr("Remove category")
                                    enabled: !catPage.catEditBuiltIn && catPage.catEditId !== ""
                                    onClicked: root.removeCurrentCategory()
                                }
                            }
                        }

                        // Edit form for the selected category.
                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            spacing: 14

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 4
                                FormLabel { text: qsTr("Name") }
                                SettingsTextField {
                                    id: catEditName
                                    onEdited: root.catDirty = true
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 4
                                FormLabel { text: qsTr("File types") }
                                SettingsTextArea {
                                    id: catEditExts
                                    implicitHeight: 64
                                    placeholderText: "MP4 MKV AVI MOV"
                                    onEdited: root.catDirty = true
                                }
                                SettingsHint { text: qsTr("Space or comma-separated. Case-insensitive.") }
                                // A category type the browser isn't told to capture never
                                // reaches this category from the browser.
                                Text {
                                    Layout.fillWidth: true
                                    wrapMode: Text.WordWrap
                                    font.pixelSize: 11 * App.fontScale
                                    color: ColorPalette.warningText
                                    visible: text.length > 0
                                    text: {
                                        var typed = catEditExts.text.split(/[\s,]+/).map(function(s) {
                                            return s.trim().toLowerCase().replace(/^\./, "")
                                        }).filter(function(s) { return s.length > 0 })
                                        var monitored = monitoredExtsArea.text.split(/[\s,]+/).map(function(s) {
                                            return s.trim().toLowerCase().replace(/^\./, "")
                                        }).filter(function(s) { return s.length > 0 })
                                        var missing = typed.filter(function(e) { return monitored.indexOf(e) < 0 })
                                        return missing.length > 0
                                            ? qsTr("Not in the browser's captured file types: %1").arg(missing.join(", "))
                                            : ""
                                    }
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 4
                                FormLabel { text: qsTr("Sites") }
                                SettingsTextField {
                                    id: catEditSites
                                    placeholderText: "*.youtube.com *.vimeo.com"
                                    onEdited: root.catDirty = true
                                }
                                SettingsHint { text: qsTr("Downloads from matching sites will automatically go into this category.") }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 4
                                FormLabel { text: qsTr("Save to folder") }
                                SettingsPathField {
                                    id: catEditPath
                                    onEdited: root.catDirty = true
                                    onBrowse: catSaveFolderDlg.open()
                                }
                            }

                            Item { Layout.fillHeight: true }
                        }
                    }
                }

                // 2 ── Downloads ──────────────────────────────────────────────
                SettingsPage {
                    title: qsTr("Downloads")

                    SettingsScroll {
                        SettingsSection {
                            title: qsTr("Folders")

                            SettingsRow {
                                label: qsTr("Default save folder")
                                stacked: true
                                SettingsPathField {
                                    value: root.editDefaultSavePath
                                    onEdited: (text) => root.editDefaultSavePath = text
                                    onBrowse: saveFolderDlg.open()
                                }
                            }
                            SettingsRow {
                                label: qsTr("Torrent save folder")
                                stacked: true
                                hint: qsTr("This is the remembered custom torrent folder used when the torrent metadata dialog is set to use a custom save folder by default.")
                                SettingsPathField {
                                    value: root.editTorrentCustomSavePath
                                    onEdited: (text) => root.editTorrentCustomSavePath = text
                                    onBrowse: torrentCustomSaveFolderDlg.open()
                                }
                            }
                            SettingsRow {
                                label: qsTr("Temporary folder")
                                stacked: true
                                hint: qsTr("Stellar stores partially downloaded file parts and metadata here while downloading and assembling files.")
                                SettingsPathField {
                                    value: root.editTemporaryDirectory
                                    onEdited: (text) => root.editTemporaryDirectory = text
                                    onBrowse: tempFolderDlg.open()
                                }
                            }
                        }

                        SettingsSection {
                            title: qsTr("Adding downloads")

                            SettingsCheck {
                                text: qsTr("Start downloading immediately (skip file info dialog)")
                                checked: root.editStartImmediately
                                onToggled: (on) => root.editStartImmediately = on
                            }
                            SettingsCheck {
                                text: qsTr("Start downloading immediately while displaying \"Download File Info\" dialog")
                                checked: root.editStartDownloadWhileFileInfo
                                onToggled: (on) => root.editStartDownloadWhileFileInfo = on
                            }
                            SettingsCheck {
                                text: qsTr("Show download complete dialog")
                                checked: root.editShowDownloadComplete
                                onToggled: (on) => root.editShowDownloadComplete = on
                            }
                            SettingsCheck {
                                text: qsTr("Auto-fill the description field with file metadata (bitrate, resolution, codec, etc.)")
                                checked: root.editFillDescriptionMetadata
                                onToggled: (on) => root.editFillDescriptionMetadata = on
                            }
                            SettingsCheck {
                                text: qsTr("Show queue selection panel on pressing Download Later")
                                checked: root.editShowQueueSelectionOnDownloadLater
                                onToggled: (on) => root.editShowQueueSelectionOnDownloadLater = on
                            }
                            SettingsCheck {
                                text: qsTr("Show queue selection panel on closing batch downloads dialog")
                                checked: root.editShowQueueSelectionOnBatchDownload
                                onToggled: (on) => root.editShowQueueSelectionOnBatchDownload = on
                            }
                            SettingsHint {
                                text: qsTr("Note: These settings don't apply to queue processing for the Start Downloading Immediately setting and Show Download Complete dialog setting.")
                            }
                        }

                        SettingsSection {
                            title: qsTr("File list")

                            SettingsRow {
                                label: qsTr("If a duplicate URL is added")
                                SettingsCombo {
                                    model: [qsTr("Ask me what to do"), qsTr("Add with a numbered file name"), qsTr("Overwrite the existing download"), qsTr("Resume / show complete dialog")]
                                    value: root.editDuplicateAction
                                    onEdited: (index) => root.editDuplicateAction = index
                                }
                            }
                            SettingsRow {
                                label: qsTr("Double-clicking a download")
                                SettingsCombo {
                                    model: [qsTr("Open file properties dialog"), qsTr("Open file"), qsTr("Open folder")]
                                    value: root.editDoubleClickAction
                                    onEdited: (index) => root.editDoubleClickAction = index
                                }
                            }
                        }

                        SettingsSection {
                            title: qsTr("Last try date")

                            SettingsRow {
                                label: qsTr("Date format")
                                SettingsCombo {
                                    model: [root._previewDatePart(0), root._previewDatePart(1), root._previewDatePart(2), root._previewDatePart(3)]
                                    value: root.editLastTryDateStyle
                                    onEdited: (index) => root.editLastTryDateStyle = index
                                }
                            }
                            SettingsRow {
                                label: qsTr("Time format")
                                SettingsCombo {
                                    model: [qsTr("24-hour time"), qsTr("12-hour time")]
                                    value: root.editLastTryUse24Hour ? 0 : 1
                                    onEdited: (index) => root.editLastTryUse24Hour = index === 0
                                }
                            }
                            SettingsRow {
                                label: ""
                                SettingsCheck {
                                    text: qsTr("Show seconds")
                                    checked: root.editLastTryShowSeconds
                                    onToggled: (on) => root.editLastTryShowSeconds = on
                                }
                            }
                            SettingsRow {
                                label: qsTr("Preview")
                                Text {
                                    text: root.lastTryPreview
                                    color: ColorPalette.textPrimary
                                    font.pixelSize: 13 * App.fontScale
                                    font.family: "Consolas, monospace"
                                }
                            }
                        }
                    }
                }

                // 3 ── Browser ────────────────────────────────────────────────
                SettingsPage {
                    title: qsTr("Browser")

                    SettingsScroll {
                        SettingsSection {
                            title: qsTr("Captured file types")
                            description: qsTr("Automatically start downloading the following file types:")

                            SettingsTextArea {
                                id: monitoredExtsArea
                                implicitHeight: 88
                                value: App.settings.monitoredExtensions.join(" ").toUpperCase()
                            }
                            SettingsHint { text: qsTr("Space or comma-separated. Case-insensitive.") }
                        }

                        SettingsSection {
                            title: qsTr("Excluded sites")
                            description: qsTr("Don't start downloading automatically from the following sites:")

                            SettingsTextArea {
                                id: excludedSitesArea
                                implicitHeight: 64
                                value: App.settings.excludedSites.join(" ")
                            }
                            SettingsHint { text: qsTr("Space-separated host patterns. Wildcards (*) supported, e.g. *.update.microsoft.com") }
                        }

                        SettingsSection {
                            title: qsTr("Address Exceptions")
                            description: qsTr("Don't start downloading from the following addresses:")

                            SettingsTextArea {
                                id: excludedAddrsArea
                                implicitHeight: 140
                                wrap: false
                                monospace: true
                                value: App.settings.excludedAddresses.join("\n")
                            }
                            SettingsHint { text: qsTr("One URL pattern per line. Wildcards (*) supported.") }
                            SettingsCheck {
                                text: qsTr("Show the dialog to add an address to the list of exceptions for a twice cancelled download")
                                checked: root.editShowExceptionsDialog
                                onToggled: (on) => root.editShowExceptionsDialog = on
                            }
                        }

                        SettingsSection {
                            title: qsTr("Bypass Download Interception")

                            SettingsRow {
                                label: qsTr("Bypass key")
                                hint: qsTr("Hold this key while clicking a download link to skip interception and let the browser download.")
                                SettingsCombo {
                                    model: [qsTr("None"), "Alt", "Ctrl", "Shift"]
                                    value: root.editBypassInterceptKey
                                    onEdited: (index) => root.editBypassInterceptKey = index
                                }
                            }
                        }
                    }
                }

                // 4 ── Speed Limiter ──────────────────────────────────────────
                SettingsPage {
                    title: qsTr("Speed Limiter")

                    SettingsScroll {
                        SettingsSection {
                            title: qsTr("Speed limiter")

                            SettingsCheck {
                                text: qsTr("Enable speed limiter")
                                checked: root.editGlobalSpeedLimitEnabled
                                onToggled: (on) => root.editGlobalSpeedLimitEnabled = on
                            }
                            SettingsRow {
                                label: qsTr("Maximum download")
                                SettingsNumber { from: 0; to: 10000000; suffix: qsTr("KB/s"); value: root.editSavedSpeedLimitKBps; onEdited: (v) => root.editSavedSpeedLimitKBps = v }
                            }
                            SettingsRow {
                                label: qsTr("Maximum upload")
                                SettingsNumber { from: 0; to: 10000000; suffix: qsTr("KB/s"); value: root.editGlobalUploadLimitKBps; onEdited: (v) => root.editGlobalUploadLimitKBps = v }
                            }
                            SettingsCheck {
                                text: qsTr("Always turn on speed limiter on Stellar startup")
                                checked: root.editSpeedLimiterOnStartup
                                onToggled: (on) => root.editSpeedLimiterOnStartup = on
                            }
                        }

                        // Each rule: days[], onHour (1-12), onMinute, onAmPm, offHour,
                        // offMinute, offAmPm, downLimitKBps, upLimitKBps — the format
                        // Main.qml's runSpeedScheduleCheck() evaluates. The editors work
                        // in minutes-since-midnight and a weekday bitmask, and convert at
                        // the edges so stored rules stay compatible.
                        SettingsSection {
                            id: scheduleSection
                            title: qsTr("Schedule")

                            readonly property var dayNames: ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
                            property var rules: {
                                try {
                                    var parsed = JSON.parse(root.editSpeedScheduleJson || "[]")
                                    return Array.isArray(parsed) ? parsed : []
                                } catch (e) {
                                    return []
                                }
                            }

                            function saveRules(arr) { root.editSpeedScheduleJson = JSON.stringify(arr) }
                            function patchRule(index, fields) {
                                var arr = rules.slice()
                                var r = JSON.parse(JSON.stringify(arr[index] || {}))
                                for (var k in fields) r[k] = fields[k]
                                arr[index] = r
                                saveRules(arr)
                            }
                            function daysToMask(days) {
                                var mask = 0
                                for (var i = 0; i < dayNames.length; ++i)
                                    if (days && days.indexOf(dayNames[i]) >= 0) mask |= (1 << i)
                                return mask
                            }
                            function maskToDays(mask) {
                                return dayNames.filter(function(name, i) { return (mask & (1 << i)) !== 0 })
                            }
                            function ruleMinutes(hour, minute, ampm) {
                                var h = parseInt(hour) || 12
                                var m = parseInt(minute) || 0
                                var h24 = ampm === "PM" ? (h < 12 ? h + 12 : 12) : (h === 12 ? 0 : h)
                                return h24 * 60 + m
                            }
                            function timeFields(prefix, minutes) {
                                var h24 = Math.floor(minutes / 60) % 24
                                var m = minutes % 60
                                var fields = {}
                                fields[prefix + "Hour"] = String(h24 % 12 === 0 ? 12 : h24 % 12)
                                fields[prefix + "Minute"] = m < 10 ? "0" + m : String(m)
                                fields[prefix + "AmPm"] = h24 >= 12 ? "PM" : "AM"
                                return fields
                            }

                            SettingsCheck {
                                text: qsTr("Enable speed limiter scheduler")
                                checked: root.editSpeedScheduleEnabled
                                onToggled: (on) => root.editSpeedScheduleEnabled = on
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                visible: root.editSpeedScheduleEnabled
                                spacing: 8

                                Repeater {
                                    model: scheduleSection.rules.length
                                    delegate: Rectangle {
                                        id: ruleCard
                                        required property int index
                                        readonly property var rule: scheduleSection.rules[index] || {}

                                        Layout.fillWidth: true
                                        implicitHeight: ruleCol.implicitHeight + 20
                                        color: ColorPalette.rowAltBg
                                        border.color: ColorPalette.border
                                        radius: 3

                                        ColumnLayout {
                                            id: ruleCol
                                            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 10 }
                                            spacing: 8

                                            RowLayout {
                                                Layout.fillWidth: true
                                                Text {
                                                    Layout.fillWidth: true
                                                    text: qsTr("Rule %1").arg(ruleCard.index + 1)
                                                    color: ColorPalette.textSecond
                                                    font.pixelSize: 12 * App.fontScale
                                                    font.bold: true
                                                }
                                                SettingsLink {
                                                    text: qsTr("Remove")
                                                    color: ColorPalette.errorText
                                                    onClicked: {
                                                        var arr = scheduleSection.rules.slice()
                                                        arr.splice(ruleCard.index, 1)
                                                        scheduleSection.saveRules(arr)
                                                    }
                                                }
                                            }

                                            DayOfWeekSelector {
                                                daysMask: scheduleSection.daysToMask(ruleCard.rule.days)
                                                onToggled: (mask) => scheduleSection.patchRule(ruleCard.index, { days: scheduleSection.maskToDays(mask) })
                                            }
                                            SettingsRow {
                                                label: qsTr("From")
                                                TimeField {
                                                    minutes: scheduleSection.ruleMinutes(ruleCard.rule.onHour || "9", ruleCard.rule.onMinute, ruleCard.rule.onAmPm || "AM")
                                                    onEdited: (m) => scheduleSection.patchRule(ruleCard.index, scheduleSection.timeFields("on", m))
                                                }
                                            }
                                            SettingsRow {
                                                label: qsTr("To")
                                                TimeField {
                                                    minutes: scheduleSection.ruleMinutes(ruleCard.rule.offHour || "5", ruleCard.rule.offMinute, ruleCard.rule.offAmPm || "PM")
                                                    onEdited: (m) => scheduleSection.patchRule(ruleCard.index, scheduleSection.timeFields("off", m))
                                                }
                                            }
                                            SettingsRow {
                                                label: qsTr("Download")
                                                SettingsNumber {
                                                    from: 1; to: 10000000; suffix: qsTr("KB/s")
                                                    value: parseInt(ruleCard.rule.downLimitKBps) || 500
                                                    onEdited: (v) => scheduleSection.patchRule(ruleCard.index, { downLimitKBps: v })
                                                }
                                            }
                                            SettingsRow {
                                                label: qsTr("Upload")
                                                SettingsNumber {
                                                    from: 1; to: 10000000; suffix: qsTr("KB/s")
                                                    value: parseInt(ruleCard.rule.upLimitKBps) || 500
                                                    onEdited: (v) => scheduleSection.patchRule(ruleCard.index, { upLimitKBps: v })
                                                }
                                            }
                                        }
                                    }
                                }

                                DlgButton {
                                    text: qsTr("Add Rule")
                                    onClicked: {
                                        var arr = scheduleSection.rules.slice()
                                        arr.push({ days: ["Mon", "Tue", "Wed", "Thu", "Fri"],
                                                   onHour: "9", onMinute: "00", onAmPm: "AM",
                                                   offHour: "5", offMinute: "00", offAmPm: "PM",
                                                   downLimitKBps: 500, upLimitKBps: 500 })
                                        scheduleSection.saveRules(arr)
                                    }
                                }

                                SettingsHint {
                                    text: qsTr("Rules are evaluated every minute; the first matching rule wins. Scheduled download and upload limits are cleared automatically when no rule is active.")
                                }
                            }
                        }
                    }
                }

                // 5 ── Notifications ──────────────────────────────────────────
                SettingsPage {
                    title: qsTr("Notifications")

                    SettingsScroll {
                        SettingsSection {
                            title: qsTr("Desktop notifications")

                            SettingsCheck {
                                text: qsTr("Show notification when download completes")
                                checked: root.editShowCompletionNotification
                                onToggled: (on) => root.editShowCompletionNotification = on
                            }
                            SettingsCheck {
                                text: qsTr("Show notification on download error")
                                checked: root.editShowErrorNotification
                                onToggled: (on) => root.editShowErrorNotification = on
                            }
                        }
                    }
                }

                // 6 ── General ────────────────────────────────────────────────
                SettingsPage {
                    title: qsTr("General")

                    SettingsScroll {
                        SettingsSection {
                            title: qsTr("Startup")

                            SettingsCheck {
                                text: qsTr("Launch Stellar on startup")
                                checked: root.editLaunchOnStartup
                                onToggled: (on) => root.editLaunchOnStartup = on
                            }
                            SettingsCheck {
                                text: qsTr("Pause torrents on startup")
                                checked: root.editTorrentStopOnStartup
                                onToggled: (on) => root.editTorrentStopOnStartup = on
                            }
                            SettingsCheck {
                                text: qsTr("Automatically check for updates")
                                checked: root.editAutoCheckUpdates
                                onToggled: (on) => root.editAutoCheckUpdates = on
                            }
                        }

                        SettingsSection {
                            title: qsTr("Window")

                            SettingsCheck {
                                text: qsTr("Minimize to system tray")
                                checked: root.editMinimizeToTray
                                onToggled: (on) => root.editMinimizeToTray = on
                            }
                            SettingsCheck {
                                text: qsTr("Close to system tray")
                                checked: root.editCloseToTray
                                onToggled: (on) => root.editCloseToTray = on
                            }
                            SettingsCheck {
                                text: qsTr("Show tips in bottom bar")
                                checked: root.editShowTips
                                onToggled: (on) => root.editShowTips = on
                            }
                        }

                        SettingsSection {
                            title: qsTr("Appearance")

                            SettingsRow {
                                label: qsTr("Theme")
                                SettingsCombo {
                                    model: [qsTr("Dark"), qsTr("Light")]
                                    value: root.editDarkMode ? 0 : 1
                                    onEdited: (index) => root.editDarkMode = index === 0
                                }
                            }
                            SettingsRow {
                                id: uiScaleRow
                                label: qsTr("UI scale")
                                readonly property var scaleValues: [0.0, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0, 2.5, 3.0]
                                SettingsCombo {
                                    model: [qsTr("System default"), "75%", "100%", "125%", "150%", "175%", "200%", "250%", "300%"]
                                    value: Math.max(0, uiScaleRow.scaleValues.indexOf(root.editUiScaleFactor))
                                    onEdited: (index) => root.editUiScaleFactor = uiScaleRow.scaleValues[index]
                                }
                            }
                            SettingsRow {
                                id: fontSizeRow
                                label: qsTr("Font size")
                                readonly property var fontValues: [0, 8, 9, 10, 11, 12, 13, 14, 16, 18, 20]
                                SettingsCombo {
                                    model: [qsTr("System default"), "8pt", "9pt", "10pt", "11pt", "12pt", "13pt", "14pt", "16pt", "18pt", "20pt"]
                                    value: Math.max(0, fontSizeRow.fontValues.indexOf(root.editUiFontPointSize))
                                    onEdited: (index) => root.editUiFontPointSize = fontSizeRow.fontValues[index]
                                }
                            }
                            SettingsRow {
                                label: qsTr("Tray icon style")
                                SettingsCombo {
                                    model: [qsTr("Colored"), qsTr("White"), qsTr("Black")]
                                    value: root.editTrayIconStyle
                                    onEdited: (index) => root.editTrayIconStyle = index
                                }
                            }
                            SettingsHint { text: qsTr("A restart is required for appearance changes to take effect.") }
                        }

                        SettingsSection {
                            title: qsTr("Status display")

                            SettingsCheck {
                                text: qsTr("Show speed in tray icon tooltip")
                                checked: root.editSpeedInTrayTooltip
                                onToggled: (on) => root.editSpeedInTrayTooltip = on
                            }
                            SettingsCheck {
                                text: qsTr("Show speed in title bar")
                                checked: root.editSpeedInTitleBar
                                onToggled: (on) => root.editSpeedInTitleBar = on
                            }
                            SettingsCheck {
                                text: qsTr("Show speed in status bar")
                                checked: root.editSpeedInStatusBar
                                onToggled: (on) => root.editSpeedInStatusBar = on
                            }
                            SettingsCheck {
                                text: qsTr("Show ratio in status bar")
                                checked: root.editRatioInStatusBar
                                onToggled: (on) => root.editRatioInStatusBar = on
                            }
                            SettingsCheck {
                                text: qsTr("Show torrent connections in status bar")
                                checked: root.editConnectionsInStatusBar
                                onToggled: (on) => root.editConnectionsInStatusBar = on
                            }
                            SettingsCheck {
                                text: qsTr("Show DHT nodes in status bar")
                                checked: root.editDhtNodesInStatusBar
                                onToggled: (on) => root.editDhtNodesInStatusBar = on
                            }
                            SettingsCheck {
                                text: qsTr("Show public IP in status bar")
                                description: qsTr("Detects your public IP via libtorrent and your active connection type. Hover the indicator to see WiFi SSID/signal or warnings about incoming connections.")
                                checked: root.editShowPublicIpInStatusBar
                                onToggled: (on) => root.editShowPublicIpInStatusBar = on
                            }
                        }

                        SettingsSection {
                            title: qsTr("Clipboard Monitoring")

                            SettingsCheck {
                                text: qsTr("Automatically start downloading URLs placed in the clipboard")
                                description: qsTr("When a URL matching a monitored file type is copied to the clipboard, Stellar will ask if you want to download it. Only file types listed under Browser › Automatically start downloading the following file types are picked up.")
                                checked: root.editClipboardMonitorEnabled
                                onToggled: (on) => root.editClipboardMonitorEnabled = on
                            }
                        }

                        SettingsSection {
                            title: qsTr("Backup & Restore")
                            description: qsTr("Export everything - settings, downloads, torrents (with their share ratios), queues, categories and statistics - to a single backup file. Import it later into a fresh Stellar install to restore it all. Importing replaces the current data (a timestamped backup is kept) and restarts Stellar.")

                            RowLayout {
                                spacing: 8
                                DlgButton {
                                    text: qsTr("Export All Data…")
                                    onClicked: {
                                        exportBackupDlg.currentFile = root.fileUrlFromPath(
                                            (App.settings.defaultSavePath || "") + "/stellar-backup-"
                                            + Qt.formatDate(new Date(), "yyyyMMdd") + ".stellarbackup")
                                        exportBackupDlg.open()
                                    }
                                }
                                DlgButton {
                                    text: qsTr("Import Data…")
                                    onClicked: importBackupDlg.open()
                                }
                            }
                        }
                    }
                }

                // 7 ── Media ──────────────────────────────────────────────────
                SettingsPage {
                    title: qsTr("Media")

                    SettingsScroll {
                        SettingsSection {
                            title: qsTr("yt-dlp")
                            description: qsTr("Stellar uses yt-dlp to download videos from YouTube, Vimeo, Twitter/X, Instagram and hundreds of other sites. When you paste a video URL into Add URL, a format picker will appear.")

                            SettingsStatus {
                                level: App.ytdlpManager.available ? SettingsStatus.Level.Ok
                                     : App.ytdlpManager.downloading ? SettingsStatus.Level.Busy
                                     : SettingsStatus.Level.Error
                                text: App.ytdlpManager.statusText
                            }

                            Rectangle {
                                Layout.fillWidth: true
                                implicitHeight: 6
                                radius: 3
                                color: ColorPalette.progressTrack
                                visible: App.ytdlpManager.downloading
                                Rectangle {
                                    width: parent.width * (App.ytdlpManager.downloadProgress / 100.0)
                                    height: parent.height
                                    radius: parent.radius
                                    color: ColorPalette.progressDownloading
                                }
                            }

                            RowLayout {
                                spacing: 8
                                DlgButton {
                                    text: App.ytdlpManager.available ? qsTr("Update yt-dlp") : qsTr("Download yt-dlp")
                                    enabled: !App.ytdlpManager.downloading
                                    onClicked: {
                                        if (App.ytdlpManager.available)
                                            App.ytdlpManager.selfUpdate()
                                        else
                                            App.downloadYtdlpBinary()
                                    }
                                }
                                DlgButton {
                                    text: qsTr("Cancel")
                                    visible: App.ytdlpManager.downloading
                                    onClicked: App.ytdlpManager.cancelDownload()
                                }
                                DlgButton {
                                    text: qsTr("Re-check")
                                    enabled: !App.ytdlpManager.downloading
                                    onClicked: App.ytdlpManager.checkAvailability()
                                }
                            }

                            SettingsCheck {
                                text: qsTr("Automatically update yt-dlp at startup")
                                description: qsTr("When enabled, Stellar will run \"yt-dlp -U\" at startup to keep the binary up to date. Requires an active internet connection.")
                                checked: root.editYtdlpAutoUpdate
                                onToggled: (on) => root.editYtdlpAutoUpdate = on
                            }

                            SettingsRow {
                                label: qsTr("Custom binary path")
                                stacked: true
                                hint: qsTr("Leave blank to use the bundled binary (recommended). Set to the absolute path of your own yt-dlp executable if you want to use a specific version.")
                                SettingsPathField {
                                    placeholderText: qsTr("(auto - use bundled or system yt-dlp)")
                                    value: root.editYtdlpCustomBinaryPath
                                    onEdited: (text) => root.editYtdlpCustomBinaryPath = text
                                    onBrowse: ytdlpFileDlg.open()
                                }
                            }

                            SettingsRow {
                                id: cookieBrowserRow
                                label: qsTr("Default cookie browser")
                                hint: qsTr("When set, Stellar will automatically retry yt-dlp downloads that require login using this browser's cookies, without prompting.")
                                readonly property var browsers: ["None", "Chrome", "Firefox", "Edge", "Brave", "Opera", "Vivaldi", "Safari"]
                                function indexForBrowser(v) {
                                    v = (v || "").toLowerCase()
                                    for (var i = 1; i < browsers.length; ++i)
                                        if (browsers[i].toLowerCase() === v) return i
                                    return 0
                                }
                                SettingsCombo {
                                    model: [qsTr("None"), "Chrome", "Firefox", "Edge", "Brave", "Opera", "Vivaldi", "Safari"]
                                    value: cookieBrowserRow.indexForBrowser(root.editYtdlpDefaultCookieBrowser)
                                    onEdited: (index) => root.editYtdlpDefaultCookieBrowser = index === 0 ? "" : cookieBrowserRow.browsers[index].toLowerCase()
                                }
                            }
                        }

                        SettingsSection {
                            title: qsTr("FFmpeg")

                            SettingsStatus {
                                level: App.ytdlpManager.ffmpegAvailable ? SettingsStatus.Level.Ok : SettingsStatus.Level.Error
                                text: App.ytdlpManager.ffmpegAvailable
                                      ? qsTr("ffmpeg found: %1").arg(App.ytdlpManager.ffmpegPath)
                                      : qsTr("ffmpeg not found - HD downloads will be limited to pre-muxed formats (max ~480p)")
                            }
                            SettingsHint {
                                visible: App.ffmpegUpdateStatus.length > 0
                                text: App.ffmpegUpdateStatus
                            }
                            RowLayout {
                                spacing: 8
                                DlgButton {
                                    text: App.ffmpegUpdating ? qsTr("Updating FFmpeg...") : qsTr("Update FFmpeg")
                                    enabled: !App.ffmpegUpdating
                                    onClicked: App.updateFfmpegBinary()
                                }
                                DlgButton {
                                    text: qsTr("Get ffmpeg (gyan.dev)")
                                    visible: !App.ytdlpManager.ffmpegAvailable
                                    onClicked: App.openExternalUrl("https://www.gyan.dev/ffmpeg/builds/")
                                }
                            }
                            SettingsNote {
                                visible: !App.ytdlpManager.ffmpegAvailable
                                text: qsTr("ffmpeg is required to merge separate video and audio streams into MP4/MKV. Without it, YouTube downloads fall back to a single pre-muxed stream (usually WebM, max 480p).\n\nTo fix: download ffmpeg from gyan.dev/ffmpeg/builds (Essentials build), extract ffmpeg.exe from the bin/ folder, and place it in the same folder as yt-dlp.exe. Then click Re-check above.")
                            }
                        }

                        SettingsSection {
                            title: qsTr("JavaScript runtime")

                            SettingsStatus {
                                level: App.ytdlpManager.jsRuntimeAvailable ? SettingsStatus.Level.Ok : SettingsStatus.Level.Error
                                text: App.ytdlpManager.jsRuntimeAvailable
                                      ? qsTr("%1 found: %2").arg(App.ytdlpManager.jsRuntimeName).arg(App.ytdlpManager.jsRuntimePath)
                                      : qsTr("No JS runtime found - YouTube n-challenge solving disabled")
                            }
                            SettingsNote {
                                visible: !App.ytdlpManager.jsRuntimeAvailable
                                text: qsTr("yt-dlp requires an external JavaScript runtime to solve YouTube's n-challenge (URL throttling). Without it, YouTube downloads may fail or return only low-quality storyboard formats.\n\nInstall one of: Deno (deno.com), Node.js (nodejs.org), Bun (bun.sh), or QuickJS. Place it in the same folder as yt-dlp.exe or add it to your system PATH, then click Re-check in the yt-dlp status section above.")
                            }
                            SettingsRow {
                                label: qsTr("Custom runtime path")
                                stacked: true
                                hint: qsTr("Override the auto-detected runtime path. Leave blank to use auto-detection (searches yt-dlp folder, app folder, and system PATH).")
                                SettingsPathField {
                                    placeholderText: qsTr("(auto-detect from PATH and yt-dlp folder)")
                                    value: root.editYtdlpJsRuntimePath
                                    onEdited: (text) => root.editYtdlpJsRuntimePath = text
                                    onBrowse: jsRuntimeFileDlg.open()
                                }
                            }
                        }
                    }
                }

                // 8 ── Torrents ───────────────────────────────────────────────
                // Split into tabs: as one page it ran to several screens.
                SettingsPage {
                    title: qsTr("Torrents")

                    // Legal notice shown when enabling BitTorrent
                    Popup {
                        id: torrentLegalNotice
                        parent: Overlay.overlay
                        anchors.centerIn: parent
                        width: 480
                        modal: true
                        closePolicy: Popup.NoAutoClose
                        padding: 0
                        background: Rectangle { color: ColorPalette.cardBg; border.color: ColorPalette.border; radius: 6 }
                        contentItem: ColumnLayout {
                            spacing: 12
                            Text {
                                Layout.fillWidth: true
                                Layout.topMargin: 20
                                Layout.leftMargin: 20
                                Layout.rightMargin: 20
                                text: qsTr("BitTorrent - Legal Notice")
                                color: ColorPalette.textHeader
                                font.pixelSize: 15 * App.fontScale
                                font.bold: true
                            }
                            Text {
                                Layout.fillWidth: true
                                Layout.leftMargin: 20
                                Layout.rightMargin: 20
                                wrapMode: Text.WordWrap
                                color: ColorPalette.textPrimary
                                font.pixelSize: 12 * App.fontScale
                                lineHeight: 1.4
                                text: qsTr("Stellar is a file-sharing program. When you download a torrent, your IP address becomes visible to other peers in the swarm and you simultaneously upload (seed) data to others.\n\nAnything you share via BitTorrent is your sole responsibility. Ensure you have the right to distribute the content.\n\nIt is strongly recommended to bind Stellar to a VPN network interface and verify that your VPN is active before using torrents, to protect your IP address from exposure.")
                            }
                            RowLayout {
                                Layout.fillWidth: true
                                Layout.leftMargin: 20
                                Layout.rightMargin: 20
                                Layout.bottomMargin: 20
                                spacing: 8
                                Item { Layout.fillWidth: true }
                                DlgButton {
                                    text: qsTr("Cancel")
                                    onClicked: torrentLegalNotice.close()
                                }
                                DlgButton {
                                    text: qsTr("I Understand, Enable")
                                    primary: true
                                    onClicked: {
                                        torrentLegalNotice.close()
                                        root.editTorrentEnabled = true
                                    }
                                }
                            }
                        }
                    }

                    SettingsTabBar {
                        id: torrentTabs
                        model: [qsTr("General"), qsTr("Network"), qsTr("Privacy"), qsTr("Storage"), qsTr("Database")]
                    }

                    StackLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        currentIndex: torrentTabs.currentIndex

                        // ── General ───────────────────────────────────────────
                        SettingsScroll {
                            SettingsSection {
                                SettingsCheck {
                                    text: qsTr("Enable BitTorrent support")
                                    description: qsTr("These settings apply to .torrent files and magnet links.")
                                    checked: root.editTorrentEnabled
                                    // Turning it on goes through the legal notice; the box keeps
                                    // showing editTorrentEnabled until that is accepted.
                                    onToggled: (on) => {
                                        if (on)
                                            torrentLegalNotice.open()
                                        else
                                            root.editTorrentEnabled = false
                                    }
                                }
                            }

                            SettingsSection {
                                title: qsTr("Limits")

                                SettingsRow {
                                    label: qsTr("Global max connections")
                                    SettingsNumber { from: 1; to: 100000; value: root.editTorrentConnectionsLimit; onEdited: (v) => root.editTorrentConnectionsLimit = v }
                                }
                                SettingsRow {
                                    label: qsTr("Max connections per torrent")
                                    SettingsNumber { from: 0; to: 100000; value: root.editTorrentConnectionsLimitPerTorrent; onEdited: (v) => root.editTorrentConnectionsLimitPerTorrent = v }
                                }
                                SettingsRow {
                                    label: qsTr("Global max upload slots")
                                    SettingsNumber { from: 0; to: 100000; value: root.editTorrentUploadSlotsLimit; onEdited: (v) => root.editTorrentUploadSlotsLimit = v }
                                }
                                SettingsRow {
                                    label: qsTr("Max upload slots per torrent")
                                    SettingsNumber { from: 0; to: 100000; value: root.editTorrentUploadSlotsLimitPerTorrent; onEdited: (v) => root.editTorrentUploadSlotsLimitPerTorrent = v }
                                }
                                SettingsHint { text: qsTr("0 = unlimited (per-torrent fields and global upload slots)") }
                            }

                            SettingsSection {
                                id: torrentStatsSection
                                title: qsTr("Statistics")
                                description: qsTr("Cumulative transfer totals across all torrents, including removed ones.")

                                property var stats: ({})
                                function refresh() { stats = App.torrentAllTimeStats() }
                                Component.onCompleted: refresh()

                                Timer {
                                    interval: 2000
                                    running: torrentStatsSection.visible && root.visible
                                    repeat: true
                                    onTriggered: torrentStatsSection.refresh()
                                }

                                SettingsRow {
                                    label: qsTr("Total Downloaded")
                                    Text { text: root.formatBytes(torrentStatsSection.stats.downloadedBytes || 0); color: ColorPalette.textPrimary; font.pixelSize: 13 * App.fontScale }
                                }
                                SettingsRow {
                                    label: qsTr("Total Uploaded")
                                    Text { text: root.formatBytes(torrentStatsSection.stats.uploadedBytes || 0); color: ColorPalette.textPrimary; font.pixelSize: 13 * App.fontScale }
                                }
                                SettingsRow {
                                    label: qsTr("All-time Share Ratio")
                                    Text {
                                        text: (torrentStatsSection.stats.ratio || 0).toFixed(3)
                                        color: root.ratioColor(torrentStatsSection.stats.ratio || 0)
                                        font.pixelSize: 13 * App.fontScale
                                        font.bold: true
                                    }
                                }
                            }
                        }

                        // ── Network ───────────────────────────────────────────
                        SettingsScroll {
                            SettingsSection {
                                title: qsTr("Listening port")

                                SettingsRow {
                                    label: qsTr("Listen port")
                                    SettingsNumber { from: 1; to: 65535; value: root.editTorrentListenPort; onEdited: (v) => root.editTorrentListenPort = v }
                                    DlgButton {
                                        implicitHeight: 28
                                        text: App.torrentPortTestInProgress ? qsTr("Testing...") : qsTr("Test Port")
                                        enabled: !App.torrentPortTestInProgress
                                        onClicked: App.testTorrentPort()
                                    }
                                }
                                // Always laid out, two lines tall, so a result appearing
                                // doesn't push the rest of the page down.
                                SettingsRow {
                                    Text {
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: Math.max(implicitHeight, 2 * fontMetrics.height)
                                        FontMetrics { id: fontMetrics; font.pixelSize: 12 * App.fontScale }
                                        verticalAlignment: Text.AlignTop
                                        text: App.torrentPortTestMessage.length > 0 ? App.torrentPortTestMessage : qsTr("Not tested yet.")
                                        // Carries text from the port-check server.
                                        textFormat: Text.PlainText
                                        color: App.torrentPortTestStatus === "open" ? ColorPalette.successText
                                             : App.torrentPortTestStatus === "closed" ? ColorPalette.errorText
                                             : App.torrentPortTestMessage.length > 0 ? ColorPalette.textSecond
                                             : ColorPalette.textMuted
                                        font.pixelSize: 12 * App.fontScale
                                        wrapMode: Text.WordWrap
                                    }
                                }
                                SettingsHint {
                                    text: qsTr("Test whether your current torrent listen port is reachable from the public internet. This helps confirm whether your VPN port forwarding, router forwarding, and firewall rules are actually allowing inbound torrent connections.")
                                }
                                SettingsRow {
                                    label: qsTr("Protocol")
                                    SettingsCombo {
                                        model: [qsTr("TCP and µTP"), qsTr("µTP only"), qsTr("TCP only")]
                                        value: root.editTorrentProtocol
                                        onEdited: (index) => root.editTorrentProtocol = index
                                    }
                                }
                            }

                            SettingsSection {
                                title: qsTr("Peer discovery")

                                SettingsCheck {
                                    text: "DHT"
                                    description: qsTr("Find peers without a tracker using a distributed hash table.")
                                    checked: root.editTorrentEnableDht
                                    onToggled: (on) => root.editTorrentEnableDht = on
                                }
                                SettingsCheck {
                                    enabled: root.editTorrentEnableDht
                                    text: qsTr("Disable DHT when idle")
                                    description: qsTr("Turn DHT off automatically when no torrents are running, so the app stops announcing itself to the network while idle.")
                                    checked: root.editTorrentDhtAutoSuspend
                                    onToggled: (on) => root.editTorrentDhtAutoSuspend = on
                                }
                                SettingsCheck {
                                    text: "LSD"
                                    enabled: !root.editTorrentAnonymousMode
                                    description: root.editTorrentAnonymousMode
                                        ? qsTr("Disabled by anonymous mode.")
                                        : qsTr("Discover peers on your local network without going through the internet.")
                                    checked: root.editTorrentEnableLsd
                                    onToggled: (on) => root.editTorrentEnableLsd = on
                                }
                                SettingsCheck {
                                    text: "UPnP"
                                    enabled: !root.editTorrentAnonymousMode
                                    description: root.editTorrentAnonymousMode
                                        ? qsTr("Disabled by anonymous mode.")
                                        : qsTr("Automatically open a port on your router so peers can connect to you.")
                                    checked: root.editTorrentEnableUpnp
                                    onToggled: (on) => root.editTorrentEnableUpnp = on
                                }
                                SettingsCheck {
                                    text: "NAT-PMP"
                                    enabled: !root.editTorrentAnonymousMode
                                    description: root.editTorrentAnonymousMode
                                        ? qsTr("Disabled by anonymous mode.")
                                        : qsTr("Like UPnP but for Apple routers - enable both and whichever your router supports will be used.")
                                    checked: root.editTorrentEnableNatPmp
                                    onToggled: (on) => root.editTorrentEnableNatPmp = on
                                }
                                SettingsCheck {
                                    text: "PeX"
                                    description: qsTr("Peer Exchange: share peer lists between connected peers so you find more sources without hitting the tracker.")
                                    checked: root.editTorrentEnablePex
                                    onToggled: (on) => root.editTorrentEnablePex = on
                                }
                                SettingsCheck {
                                    text: qsTr("Announce to all tiers")
                                    description: qsTr("Contact every tracker tier instead of stopping at the first one that answers. Magnet links put each tracker in its own tier.")
                                    checked: root.editTorrentAnnounceToAllTiers
                                    onToggled: (on) => root.editTorrentAnnounceToAllTiers = on
                                }
                                SettingsCheck {
                                    text: qsTr("Announce to all trackers in a tier")
                                    description: qsTr("Contact every tracker within a tier, not just the first working one. More peers, more tracker traffic.")
                                    checked: root.editTorrentAnnounceToAllTrackers
                                    onToggled: (on) => root.editTorrentAnnounceToAllTrackers = on
                                }
                            }

                            SettingsSection {
                                title: qsTr("Network interface")

                                StyledComboBox {
                                    id: torrentAdapterCombo
                                    Layout.fillWidth: true
                                    implicitHeight: 28
                                    font.pixelSize: 13 * App.fontScale
                                    model: root.torrentAdapterOptions
                                    currentIndex: root.indexOfTorrentAdapter(root.editTorrentBindInterface)
                                    displayText: {
                                        var option = currentIndex >= 0 && currentIndex < root.torrentAdapterOptions.length
                                            ? root.torrentAdapterOptions[currentIndex] : null
                                        return option ? option.name : qsTr("Any interface")
                                    }
                                    delegate: ItemDelegate {
                                        id: adapterItem
                                        required property int index
                                        required property var modelData
                                        width: torrentAdapterCombo.width
                                        highlighted: torrentAdapterCombo.highlightedIndex === index
                                        padding: 6
                                        contentItem: Column {
                                            spacing: 2
                                            Text {
                                                width: parent.width
                                                text: adapterItem.modelData.name || ""
                                                color: torrentAdapterCombo.currentIndex === adapterItem.index ? ColorPalette.accent : ColorPalette.textPrimary
                                                font.pixelSize: 12 * App.fontScale
                                                elide: Text.ElideRight
                                            }
                                            Text {
                                                width: parent.width
                                                text: adapterItem.modelData.details || ""
                                                color: ColorPalette.textMuted
                                                font.pixelSize: 11 * App.fontScale
                                                elide: Text.ElideRight
                                            }
                                        }
                                        background: Rectangle {
                                            color: adapterItem.highlighted ? ColorPalette.selectionBg : ColorPalette.inputBg
                                        }
                                    }
                                    onActivated: (index) => {
                                        var option = root.torrentAdapterOptions[index]
                                        root.editTorrentBindInterface = option ? (option.id || "") : ""
                                        currentIndex = Qt.binding(function() { return root.indexOfTorrentAdapter(root.editTorrentBindInterface) })
                                    }
                                }

                                // Honest explainer: empty = follow system route; named = hard bind + fail-closed.
                                SettingsHint {
                                    text: root.editTorrentBindInterface.length > 0
                                          ? qsTr("Torrent traffic is locked to this interface. If your VPN disconnects or the interface goes away, Stellar pauses torrents instead of leaking onto another connection. Bind to your VPN adapter to route all torrent traffic, including IPv6, through the VPN.")
                                          : qsTr("Any interface: torrent traffic follows the system route, just like your other apps. If a VPN is your active connection it goes through the VPN; if the VPN drops, traffic continues on the normal connection. Pick a specific adapter for strict VPN-only binding.")
                                }
                                SettingsHint {
                                    visible: root.editTorrentBindInterface.length > 0 && text.length > 0
                                    text: root.torrentAdapterDetails(root.editTorrentBindInterface)
                                }

                                // Allow LAN discovery while bound (advanced). Default off = harden.
                                SettingsCheck {
                                    visible: root.editTorrentBindInterface.length > 0
                                    text: qsTr("Allow UPnP, NAT-PMP and Local Service Discovery while bound")
                                    description: root.editTorrentAllowDiscoveryWhenBound
                                        ? qsTr("These talk to your local router and can expose your listen port around the tunnel. Only enable this when binding to a trusted LAN adapter, not a VPN.")
                                        : qsTr("UPnP, NAT-PMP and Local Service Discovery are disabled while bound, since they talk to the local router and would expose your listen port around the tunnel.")
                                    checked: root.editTorrentAllowDiscoveryWhenBound
                                    onToggled: (on) => root.editTorrentAllowDiscoveryWhenBound = on
                                }
                            }
                        }

                        // ── Privacy ───────────────────────────────────────────
                        SettingsScroll {
                            SettingsSection {
                                title: qsTr("Privacy")

                                SettingsCheck {
                                    text: qsTr("Anonymous mode")
                                    checked: root.editTorrentAnonymousMode
                                    onToggled: (on) => root.editTorrentAnonymousMode = on
                                }
                                SettingsNote {
                                    visible: root.editTorrentAnonymousMode
                                    warning: true
                                    text: qsTr("Anonymous mode does not hide your IP address. It only limits the information your client broadcasts (user-agent and client fingerprint). For real privacy, use a VPN.")
                                }
                                SettingsRow {
                                    label: qsTr("Encryption Mode")
                                    SettingsCombo {
                                        // Index maps to torrentEncryptionMode: 0 = Prefer, 1 = Require, 2 = Allow.
                                        model: [qsTr("Prefer encryption"), qsTr("Require encryption"), qsTr("Allow encryption")]
                                        value: root.editTorrentEncryptionMode
                                        onEdited: (index) => root.editTorrentEncryptionMode = index
                                    }
                                }
                                SettingsRow {
                                    label: qsTr("Custom bittorrent user agent")
                                stacked: true
                                    SettingsTextField {
                                        placeholderText: qsTr("Default: Stellar/%1").arg(App.appVersion)
                                        value: root.editTorrentCustomUserAgent
                                        onEdited: (text) => root.editTorrentCustomUserAgent = text
                                    }
                                }
                            }

                            SettingsSection {
                                title: qsTr("Torrent Security")
                                description: qsTr("Manual peer bans apply immediately. Blocked user-agent substrings, blocked countries, and auto-ban options apply when you click Apply or OK.")

                                SettingsCheck {
                                    text: qsTr("Auto Ban Xunlei, QQ, Baidu, Xfplay, DLBT and Offline downloader")
                                    checked: root.editTorrentAutoBanAbusivePeers
                                    onToggled: (on) => root.editTorrentAutoBanAbusivePeers = on
                                }
                                SettingsCheck {
                                    text: qsTr("Auto Ban BitTorrent Media Player Peer")
                                    checked: root.editTorrentAutoBanMediaPlayerPeers
                                    onToggled: (on) => root.editTorrentAutoBanMediaPlayerPeers = on
                                }

                                FormLabel { Layout.topMargin: 4; text: qsTr("Blocked user agents") }
                                SettingsTextArea {
                                    implicitHeight: 90
                                    placeholderText: qsTr("One substring per line, for example:\naria2")
                                    value: root.editTorrentBlockedPeerUserAgents
                                    onEdited: (text) => root.editTorrentBlockedPeerUserAgents = text
                                }
                                SettingsHint { text: qsTr("One substring per line. If a peer client string contains any line above, Stellar auto-bans that peer until the matching line is removed and the settings are applied.") }

                                FormLabel { Layout.topMargin: 4; text: qsTr("Block peers by country") }
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 8
                                    StyledComboBox {
                                        id: blockedCountryCombo
                                        Layout.fillWidth: true
                                        implicitHeight: 28
                                        font.pixelSize: 13 * App.fontScale
                                        model: root.torrentCountryOptions
                                        textRole: "name"
                                        currentIndex: {
                                            for (var i = 0; i < root.torrentCountryOptions.length; ++i)
                                                if ((root.torrentCountryOptions[i].code || "") === root.selectedTorrentCountryCode)
                                                    return i
                                            return root.torrentCountryOptions.length > 0 ? 0 : -1
                                        }
                                        displayText: {
                                            var option = currentIndex >= 0 && currentIndex < root.torrentCountryOptions.length
                                                ? root.torrentCountryOptions[currentIndex] : null
                                            return option ? ((option.code || "") + " - " + (option.name || "")) : ""
                                        }
                                        onActivated: (index) => {
                                            var option = root.torrentCountryOptions[index]
                                            root.selectedTorrentCountryCode = option ? (option.code || "") : ""
                                        }
                                    }
                                    DlgButton {
                                        implicitHeight: 28
                                        text: qsTr("Add")
                                        enabled: root.selectedTorrentCountryCode.length === 2
                                        onClicked: root.addBlockedTorrentCountry(root.selectedTorrentCountryCode)
                                    }
                                }
                                Flow {
                                    Layout.fillWidth: true
                                    spacing: 6
                                    visible: root.editTorrentBlockedPeerCountries.length > 0
                                    Repeater {
                                        model: root.editTorrentBlockedPeerCountries
                                        delegate: Rectangle {
                                            id: countryChip
                                            required property string modelData
                                            implicitWidth: chipRow.implicitWidth + 16
                                            implicitHeight: 26
                                            radius: 13
                                            color: ColorPalette.panelBg
                                            border.color: ColorPalette.border
                                            Row {
                                                id: chipRow
                                                anchors.centerIn: parent
                                                spacing: 6
                                                Image {
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    source: "qrc:/app/qml/flags/" + String(countryChip.modelData || "").toLowerCase() + ".svg"
                                                    width: 16
                                                    height: 12
                                                    sourceSize.width: 16
                                                    sourceSize.height: 12
                                                    fillMode: Image.PreserveAspectFit
                                                }
                                                Text {
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    text: countryChip.modelData + " - " + root.torrentCountryName(countryChip.modelData)
                                                    color: ColorPalette.textPrimary
                                                    font.pixelSize: 12 * App.fontScale
                                                }
                                                Text {
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    text: "✕"
                                                    color: chipRemove.containsMouse ? ColorPalette.errorText : ColorPalette.textSecond
                                                    font.pixelSize: 11 * App.fontScale
                                                    MouseArea {
                                                        id: chipRemove
                                                        anchors.fill: parent
                                                        anchors.margins: -4
                                                        hoverEnabled: true
                                                        cursorShape: Qt.PointingHandCursor
                                                        onClicked: root.removeBlockedTorrentCountry(countryChip.modelData)
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                                SettingsHint {
                                    visible: root.editTorrentBlockedPeerCountries.length === 0
                                    text: qsTr("No blocked countries.")
                                }

                                FormLabel { Layout.topMargin: 4; text: qsTr("Manually ban peer") }
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 8
                                    SettingsTextField {
                                        placeholderText: qsTr("IP address, for example 203.0.113.42")
                                        value: root.manualBanPeerText
                                        onEdited: (text) => root.manualBanPeerText = text
                                    }
                                    DlgButton {
                                        implicitHeight: 28
                                        text: qsTr("Ban")
                                        enabled: root.manualBanPeerText.trim().length > 0
                                        onClicked: {
                                            if (App.banTorrentPeer("", root.manualBanPeerText.trim(), 0, "", ""))
                                                root.manualBanPeerText = ""
                                        }
                                    }
                                }
                                SettingsHint { text: qsTr("Manual bans are permanent until you remove them from the banned peers list below.") }

                                FormLabel { Layout.topMargin: 4; text: qsTr("Manually banned peers") }
                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 150
                                    color: ColorPalette.inputBg
                                    border.color: ColorPalette.border
                                    radius: 3
                                    clip: true

                                    ListView {
                                        id: bannedPeersList
                                        anchors.fill: parent
                                        anchors.margins: 1
                                        clip: true
                                        interactive: contentHeight > height
                                        model: root.visibleTorrentBannedPeers
                                        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                                        delegate: Rectangle {
                                            id: bannedRow
                                            required property int index
                                            required property var modelData
                                            width: ListView.view.width
                                            implicitHeight: 40
                                            color: index % 2 === 0 ? "transparent" : ColorPalette.rowAltBg

                                            RowLayout {
                                                anchors { fill: parent; leftMargin: 10; rightMargin: 8 }
                                                spacing: 8
                                                ColumnLayout {
                                                    Layout.fillWidth: true
                                                    spacing: 1
                                                    Text {
                                                        Layout.fillWidth: true
                                                        text: bannedRow.modelData.endpoint || ""
                                                        color: ColorPalette.textPrimary
                                                        font.pixelSize: 12 * App.fontScale
                                                        font.bold: true
                                                        elide: Text.ElideRight
                                                    }
                                                    Text {
                                                        Layout.fillWidth: true
                                                        text: [bannedRow.modelData.reason || "",
                                                               bannedRow.modelData.countryCode || "",
                                                               bannedRow.modelData.client || ""]
                                                              .filter(function(s) { return s.length > 0 }).join(" · ")
                                                        color: ColorPalette.textMuted
                                                        font.pixelSize: 11 * App.fontScale
                                                        elide: Text.ElideRight
                                                    }
                                                }
                                                DlgButton {
                                                    implicitHeight: 28
                                                    text: bannedRow.modelData.permanent ? qsTr("Unban") : qsTr("Active")
                                                    enabled: !!bannedRow.modelData.permanent
                                                    onClicked: {
                                                        var endpoint = String(bannedRow.modelData.endpoint || "")
                                                        root.editTorrentBannedPeers = root.editTorrentBannedPeers.filter(function(v) {
                                                            return String(v) !== endpoint
                                                        })
                                                    }
                                                }
                                            }
                                        }

                                        Text {
                                            anchors.centerIn: parent
                                            visible: bannedPeersList.count === 0
                                            text: qsTr("No banned peers")
                                            color: ColorPalette.textDisabled
                                            font.pixelSize: 12 * App.fontScale
                                        }
                                    }
                                }
                            }
                        }

                        // ── Storage ───────────────────────────────────────────
                        SettingsScroll {
                            SettingsSection {
                                title: qsTr("Storage")

                                SettingsRow {
                                    label: qsTr("Allocation mode")
                                    hint: qsTr("Applies to new torrents only. Pre-allocate reserves full disk space immediately; sparse allocates on demand.")
                                    SettingsCombo {
                                        model: [qsTr("Sparse"), qsTr("Pre-allocate")]
                                        value: root.editTorrentStorageMode
                                        onEdited: (index) => root.editTorrentStorageMode = index
                                    }
                                }
                                SettingsRow {
                                    label: qsTr("Disk I/O type")
                                    hint: {
                                        switch (root.editTorrentDiskIoType) {
                                        case 1: return qsTr("Memory-mapped: files are mapped directly into memory. Windows and Linux read and write torrent data through the page cache with minimal CPU usage. Recommended for most users.")
                                        case 2: return qsTr("POSIX: reads and writes go through standard file calls without memory-mapping. Uses less address space than memory-mapped, which can help on 32-bit systems or when seeding many large torrents simultaneously.")
                                        default: return qsTr("Default: Stellar picks the best mode for your platform automatically.")
                                        }
                                    }
                                    SettingsCombo {
                                        model: [qsTr("Default"), qsTr("Memory-mapped"), qsTr("POSIX")]
                                        value: root.editTorrentDiskIoType
                                        onEdited: (index) => root.editTorrentDiskIoType = index
                                    }
                                }
                                SettingsRow {
                                    label: qsTr("Disk write queue")
                                    SettingsNumber { from: 1; to: 65536; suffix: qsTr("MiB"); value: root.editTorrentDiskWriteQueueMiB; onEdited: (v) => root.editTorrentDiskWriteQueueMiB = v }
                                }
                            }

                            SettingsSection {
                                title: qsTr("Advanced")

                                SettingsCheck {
                                    text: qsTr("Piece extent affinity")
                                    description: qsTr("Download pieces in 4 MiB adjacent extents. Reduces fragmentation on torrents with small piece sizes.")
                                    checked: root.editTorrentPieceExtentAffinity
                                    onToggled: (on) => root.editTorrentPieceExtentAffinity = on
                                }
                                SettingsCheck {
                                    text: qsTr("Coalesce disk reads")
                                    checked: root.editTorrentCoalesceReads
                                    onToggled: (on) => root.editTorrentCoalesceReads = on
                                }
                                SettingsCheck {
                                    text: qsTr("Coalesce disk writes")
                                    description: qsTr("Coalescing merges small I/O operations into larger buffers before writing to disk. May improve throughput on fragmented torrents.")
                                    checked: root.editTorrentCoalesceWrites
                                    onToggled: (on) => root.editTorrentCoalesceWrites = on
                                }
                            }
                        }

                        // ── Database ──────────────────────────────────────────
                        SettingsScroll {
                            SettingsSection {
                                title: qsTr("IP-to-City Database")

                                SettingsRow {
                                    label: qsTr("Version")
                                    Text { Layout.fillWidth: true; text: root.ipToCityDbInfo.versionStatus || qsTr("Unknown"); color: ColorPalette.textPrimary; font.pixelSize: 12 * App.fontScale; wrapMode: Text.WordWrap }
                                }
                                SettingsRow {
                                    label: qsTr("Path")
                                    Text { Layout.fillWidth: true; text: root.ipToCityDbInfo.path || qsTr("Not found"); color: ColorPalette.textPrimary; font.pixelSize: 12 * App.fontScale; wrapMode: Text.WrapAnywhere }
                                }
                                SettingsRow {
                                    label: qsTr("Size")
                                    Text { text: root.formatBytes(root.ipToCityDbInfo.sizeBytes || 0); color: ColorPalette.textPrimary; font.pixelSize: 12 * App.fontScale }
                                }
                                SettingsRow {
                                    label: qsTr("Entries")
                                    Text { text: root.ipToCityDbInfo.entryCountFormatted || qsTr("Unknown"); color: ColorPalette.textPrimary; font.pixelSize: 12 * App.fontScale }
                                }
                                SettingsRow {
                                    label: qsTr("Last Modified")
                                    Text { text: root.ipToCityDbInfo.lastModified || qsTr("Unknown"); color: ColorPalette.textPrimary; font.pixelSize: 12 * App.fontScale }
                                }
                                SettingsRow {
                                    label: qsTr("Status")
                                    Text {
                                        Layout.fillWidth: true
                                        text: App.ipToCityDbUpdateStatus.length > 0
                                            ? App.ipToCityDbUpdateStatus
                                            : (root.ipToCityDbInfo.loaded ? qsTr("Loaded") : qsTr("Available but not loaded"))
                                        color: App.ipToCityDbUpdateStatus.length > 0 ? ColorPalette.textPrimary
                                             : (root.ipToCityDbInfo.loaded ? ColorPalette.successText : ColorPalette.warningText)
                                        font.pixelSize: 12 * App.fontScale
                                        wrapMode: Text.WordWrap
                                    }
                                }

                                RowLayout {
                                    Layout.topMargin: 4
                                    spacing: 8
                                    DlgButton {
                                        text: App.ipToCityDbUpdating ? qsTr("Downloading...") : qsTr("Update IP-to-City DB")
                                        enabled: !App.ipToCityDbUpdating
                                        onClicked: App.updateIpToCityDbFromCachedUrl()
                                    }
                                    DlgButton {
                                        text: qsTr("Refresh Info")
                                        onClicked: root.refreshIpToCityDbInfo()
                                    }
                                }
                                SettingsHint {
                                    text: App.ipToCityDbUpdateUrl && App.ipToCityDbUpdateUrl.length > 0
                                        ? qsTr("Source: %1").arg(App.ipToCityDbUpdateUrl)
                                        : qsTr("Resolved automatically from db-ip.com when you update.")
                                }
                            }
                        }
                    }
                }

                // 9 ── RSS ────────────────────────────────────────────────────
                SettingsPage {
                    title: qsTr("RSS")

                    SettingsScroll {
                        SettingsSection {
                            title: qsTr("Feed Fetching")

                            SettingsCheck {
                                text: qsTr("Enable fetching RSS feeds")
                                checked: root.editRssEnabled
                                onToggled: (on) => root.editRssEnabled = on
                            }
                            SettingsRow {
                                enabled: root.editRssEnabled
                                label: qsTr("Feeds refresh interval")
                                SettingsNumber { from: 1; to: 1440; suffix: qsTr("minutes"); value: root.editRssRefreshIntervalMins; onEdited: (v) => root.editRssRefreshIntervalMins = v }
                            }
                            SettingsRow {
                                enabled: root.editRssEnabled
                                label: qsTr("Same host request delay")
                                SettingsNumber { from: 0; to: 60; suffix: qsTr("seconds"); value: Math.round(root.editRssSameHostDelayMs / 1000); onEdited: (v) => root.editRssSameHostDelayMs = v * 1000 }
                            }
                            SettingsRow {
                                enabled: root.editRssEnabled
                                label: qsTr("Maximum articles per feed")
                                SettingsNumber { from: 1; to: 10000; value: root.editRssMaxArticlesPerFeed; onEdited: (v) => root.editRssMaxArticlesPerFeed = v }
                            }
                        }

                        SettingsSection {
                            title: qsTr("Torrent Auto Downloader")

                            SettingsCheck {
                                text: qsTr("Enable auto downloading of RSS torrents")
                                checked: root.editRssAutoDownloadEnabled
                                onToggled: (on) => root.editRssAutoDownloadEnabled = on
                            }
                            DlgButton {
                                text: qsTr("Edit Auto Downloading Rules...")
                                onClicked: {
                                    rssDownloadRulesDialog.show()
                                    rssDownloadRulesDialog.raise()
                                    rssDownloadRulesDialog.requestActivate()
                                }
                            }
                        }

                        SettingsSection {
                            title: qsTr("Smart Episode Filter")

                            SettingsCheck {
                                text: qsTr("Download REPACK/PROPER episodes")
                                checked: root.editRssSmartFilterRepack
                                onToggled: (on) => root.editRssSmartFilterRepack = on
                            }
                            FormLabel { Layout.topMargin: 4; text: qsTr("Episode detection patterns (one per line):") }
                            SettingsTextArea {
                                implicitHeight: 110
                                wrap: false
                                monospace: true
                                value: {
                                    try {
                                        var arr = JSON.parse(root.editRssSmartFiltersJson || "[]")
                                        return Array.isArray(arr) ? arr.join("\n") : ""
                                    } catch (e) {
                                        return ""
                                    }
                                }
                                onEdited: (text) => {
                                    var lines = text.split("\n").map(function(s) { return s.trim() })
                                                    .filter(function(s) { return s.length > 0 })
                                    root.editRssSmartFiltersJson = JSON.stringify(lines)
                                }
                            }
                            SettingsHint { text: qsTr("These regular expressions are used to extract season/episode numbers for smart duplicate detection.") }
                        }
                    }
                }

                // 10 ── Associations ──────────────────────────────────────────
                SettingsPage {
                    title: qsTr("Associations")

                    SettingsScroll {
                        SettingsSection {
                            title: qsTr("Default app")
                            description: qsTr("Make Stellar the default app for .torrent files and magnet links. On Windows 10/11, click the button then confirm the change in the Windows Default Apps settings page that opens.")

                            SettingsRow {
                                label: qsTr(".torrent files")
                                Text {
                                    Layout.fillWidth: true
                                    text: root.torrentAssociationDefault ? qsTr("Currently handled by Stellar") : qsTr("Stellar is not the current default")
                                    color: root.torrentAssociationDefault ? ColorPalette.successText : ColorPalette.warningText
                                    font.pixelSize: 12 * App.fontScale
                                    wrapMode: Text.WordWrap
                                }
                            }
                            SettingsRow {
                                label: qsTr("magnet: links")
                                Text {
                                    Layout.fillWidth: true
                                    text: root.magnetAssociationDefault ? qsTr("Currently handled by Stellar") : qsTr("Stellar is not the current default")
                                    color: root.magnetAssociationDefault ? ColorPalette.successText : ColorPalette.warningText
                                    font.pixelSize: 12 * App.fontScale
                                    wrapMode: Text.WordWrap
                                }
                            }

                            Flow {
                                Layout.fillWidth: true
                                Layout.topMargin: 4
                                spacing: 8
                                DlgButton {
                                    text: qsTr("Set .torrent Default")
                                    onClicked: root.showAssociationResult(App.setTorrentFileAssociationDefault(), qsTr("Stellar is now the default app for .torrent files."))
                                }
                                DlgButton {
                                    text: qsTr("Set Magnet Default")
                                    onClicked: root.showAssociationResult(App.setMagnetAssociationDefault(), qsTr("Stellar is now the default app for magnet links."))
                                }
                                DlgButton {
                                    text: qsTr("Refresh Status")
                                    onClicked: {
                                        root.associationStatusText = ""
                                        root.refreshAssociationStatus()
                                    }
                                }
                            }
                            Text {
                                    Layout.fillWidth: true
                                    text: root.associationStatusText.length > 0
                                        ? root.associationStatusText
                                        : qsTr("If your desktop environment overrides the app-level association, refresh the status after the system finishes applying the change.")
                                    color: root.associationStatusText.length > 0 && root.associationStatusText.indexOf("Failed") === 0
                                           ? ColorPalette.errorText : ColorPalette.textMuted
                                    font.pixelSize: 11 * App.fontScale
                                    wrapMode: Text.WordWrap
                            }
                        }
                    }
                }

                // 11 ── Language ──────────────────────────────────────────────
                SettingsPage {
                    title: qsTr("Language")

                    SettingsScroll {
                        SettingsSection {
                            title: qsTr("Interface Language")
                            description: qsTr("Select the language used throughout the Stellar interface. A restart is required for all text to update.")

                            SettingsRow {
                                id: languageRow
                                label: qsTr("Language")
                                // Shared list (UTF-8 native names) from the LanguageList singleton.
                                readonly property var langEntries: LanguageList.entries
                                function indexForCode(code) {
                                    for (var i = 0; i < langEntries.length; ++i)
                                        if (langEntries[i].code === code) return i
                                    return 0
                                }
                                SettingsCombo {
                                    model: languageRow.langEntries.map(function(e) { return e.display })
                                    value: languageRow.indexForCode(root.editUiLanguage)
                                    onEdited: (index) => root.editUiLanguage = languageRow.langEntries[index].code
                                }
                            }
                        }
                    }
                }

                // 12 ── About ─────────────────────────────────────────────────
                SettingsPage {
                    title: qsTr("About")

                    SettingsScroll {
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 16

                            Image {
                                Layout.preferredWidth: 64
                                Layout.preferredHeight: 64
                                source: "../icons/app/stellar.png"
                                fillMode: Image.PreserveAspectFit
                                smooth: true
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 4

                                Text {
                                    text: "Stellar Download Manager"
                                    color: ColorPalette.textHeader
                                    font.pixelSize: 16 * App.fontScale
                                    font.bold: true
                                }
                                RowLayout {
                                    spacing: 8
                                    Text {
                                        text: qsTr("Version %1 Beta").arg(App.appVersion)
                                        color: ColorPalette.textSecond
                                        font.pixelSize: 12 * App.fontScale
                                    }
                                    Text {
                                        visible: App.updateAvailable
                                        text: qsTr("Update available: %1").arg(App.updateVersion)
                                        color: ColorPalette.successText
                                        font.pixelSize: 12 * App.fontScale
                                    }
                                }
                                RowLayout {
                                    spacing: 14
                                    SettingsLink { text: qsTr("Check for updates"); onClicked: App.checkForUpdates(true) }
                                    SettingsLink { text: qsTr("What's New"); onClicked: root.whatsNewRequested() }
                                }
                            }
                        }

                        SettingsSection {
                            title: qsTr("Build")

                            SettingsRow {
                                label: qsTr("Build date")
                                Text { text: App.buildTimeFormatted; color: ColorPalette.textPrimary; font.pixelSize: 12 * App.fontScale }
                            }
                            SettingsRow {
                                label: qsTr("Qt version")
                                Text { text: App.qtVersion; color: ColorPalette.textPrimary; font.pixelSize: 12 * App.fontScale }
                            }
                            SettingsRow {
                                label: qsTr("Platform")
                                Text {
                                    text: {
                                        const os = Qt.platform.os
                                        if (os === "windows") return qsTr("Windows")
                                        if (os === "linux")   return qsTr("Linux")
                                        if (os === "osx")     return qsTr("macOS")
                                        return os.charAt(0).toUpperCase() + os.slice(1)
                                    }
                                    color: ColorPalette.textPrimary
                                    font.pixelSize: 12 * App.fontScale
                                }
                            }
                        }

                        SettingsSection {
                            title: qsTr("License")

                            Flow {
                                Layout.fillWidth: true
                                spacing: 14
                                Text { text: "Copyright © 2026 Ninka_"; color: ColorPalette.textSecond; font.pixelSize: 12 * App.fontScale }
                                SettingsLink { text: qsTr("GNU GPL v3.0"); url: "https://www.gnu.org/licenses/gpl-3.0.html" }
                                SettingsLink { text: qsTr("Stellar Website"); url: "https://stellardownloadmanager.org/" }
                                SettingsLink { text: qsTr("GitHub"); url: "https://github.com/Ninka-Rex/Stellar" }
                                SettingsLink { text: qsTr("Releases"); url: "https://github.com/Ninka-Rex/Stellar/releases" }
                            }
                            SettingsHint {
                                text: qsTr("Stellar is free software: you may redistribute and/or modify it under the terms of the GNU General Public License, version 3.")
                                    + " " + qsTr("This program is distributed in the hope that it will be useful, but without any warranty; without even the implied warranty of merchantability or fitness for a particular purpose.")
                            }
                        }

                        // FFmpeg is invoked as an external executable (not linked into
                        // Stellar); attribution is required by its LGPL-2.1+ / GPL-2+
                        // license. Full license texts are in THIRD-PARTY-NOTICES.txt.
                        SettingsSection {
                            title: qsTr("Third-party software")

                            Repeater {
                                model: [
                                    { name: "FFmpeg", license: "LGPL-2.1+ / GPL-2+",
                                      text: "Copyright © 2000–present the FFmpeg developers. " + qsTr("Used for merging video and audio streams.") + " " + qsTr("FFmpeg is a trademark of Fabrice Bellard."),
                                      links: [{ label: "ffmpeg.org", url: "https://ffmpeg.org/" }, { label: qsTr("Git source"), url: "https://git.ffmpeg.org/ffmpeg.git" }] },
                                    { name: "libtorrent", license: "BSD-3-Clause",
                                      text: "Copyright © Arvid Norberg and contributors. " + qsTr("Used for BitTorrent protocol support."),
                                      links: [{ label: "libtorrent.org", url: "https://libtorrent.org/" }, { label: "GitHub", url: "https://github.com/arvidn/libtorrent" }] },
                                    { name: "yt-dlp", license: "The Unlicense",
                                      text: "yt-dlp contributors (The Unlicense, public-domain dedication). " + qsTr("Used for video metadata extraction and media downloading features."),
                                      links: [{ label: qsTr("yt-dlp on GitHub"), url: "https://github.com/yt-dlp/yt-dlp" }, { label: qsTr("Unlicense"), url: "http://unlicense.org/" }] },
                                    { name: "Qt " + App.qtVersion, license: "LGPL-3",
                                      text: "Copyright © The Qt Company Ltd. " + qsTr("Used under the LGPL-3 with the Qt LGPL exception."),
                                      links: [{ label: "code.qt.io", url: "https://code.qt.io/" }] },
                                    { name: "DB-IP City Lite", license: "CC BY 4.0",
                                      text: qsTr("Stellar uses the DB-IP City Lite geolocation database, distributed under Creative Commons Attribution 4.0."),
                                      links: [{ label: "db-ip.com", url: "https://db-ip.com/" }] }
                                ]
                                delegate: ColumnLayout {
                                    id: creditEntry
                                    required property var modelData
                                    Layout.fillWidth: true
                                    spacing: 3

                                    RowLayout {
                                        spacing: 8
                                        Text { text: creditEntry.modelData.name; color: ColorPalette.textPrimary; font.pixelSize: 12 * App.fontScale; font.bold: true }
                                        Text { text: creditEntry.modelData.license; color: ColorPalette.textMuted; font.pixelSize: 11 * App.fontScale }
                                    }
                                    SettingsHint { text: creditEntry.modelData.text }
                                    Row {
                                        spacing: 14
                                        Repeater {
                                            model: creditEntry.modelData.links
                                            delegate: SettingsLink {
                                                required property var modelData
                                                text: modelData.label
                                                url: modelData.url
                                                font.pixelSize: 11 * App.fontScale
                                            }
                                        }
                                    }
                                }
                            }

                            SettingsHint { text: qsTr("Full license texts are in THIRD-PARTY-NOTICES.txt, included with this installation.") }
                        }

                        Text {
                            text: qsTr("Thanks for using Stellar") + " 💙"
                            color: ColorPalette.textMuted
                            font.pixelSize: 11 * App.fontScale
                        }
                    }
                }
            }
        }

        // ── Footer ──────────────────────────────────────────────────────────
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 1
            color: ColorPalette.border
        }
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 52
            color: ColorPalette.panelBg

            RowLayout {
                anchors { right: parent.right; verticalCenter: parent.verticalCenter; rightMargin: 12 }
                spacing: 8

                DlgButton {
                    text: qsTr("OK")
                    primary: true
                    onClicked: { root.applySettings(); root.close() }
                }
                DlgButton {
                    text: qsTr("Cancel")
                    onClicked: root.close()
                }
                DlgButton {
                    text: qsTr("Apply")
                    enabled: root.hasChanges
                    onClicked: root.applySettings()
                }
            }
        }
    }
}
