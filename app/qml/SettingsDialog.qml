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

Window {
    id: root

    width: 665
    height: 500
    minimumWidth: 665
    minimumHeight: 500
    flags: Qt.Window | Qt.WindowTitleHint | Qt.WindowCloseButtonHint | Qt.WindowSystemMenuHint
    title: "Stellar Preferences"
    color: "#1e1e1e"

    Material.theme: Material.Dark
    Material.background: "#1e1e1e"
    Material.accent: "#4488dd"

    property int    initialPage: 0   // Tab indices: 0=Connection,1=Categories,2=Downloads,3=Browser,4=Speed Limiter,5=Notifications,6=General,7=Media,8=Torrents,9=RSS,10=Associations,11=About
    readonly property int pageAssociations: 10
    readonly property int pageAbout: 11
    property bool   torrentAssociationDefault: false
    property bool   magnetAssociationDefault: false
    property string associationStatusText: ""
    signal whatsNewRequested()

    // Plain var properties — no live binding to App.settings so that
    // settingsChanged can detect when the user has made changes.
    property int    editMaxConcurrent:         0
    property int    editSegmentsPerDownload:   0
    property string editDefaultSavePath:       ""
    property string editTemporaryDirectory:    ""
    property int    editGlobalSpeedLimitKBps:  0
    property bool   editMinimizeToTray:        false
    property bool   editCloseToTray:           false
    property bool   editShowTips:              true
    property bool   editShowExceptionsDialog:  true
    property int    editMaxRetries:            0
    property int    editConnectionTimeoutSecs: 0
    property int    editDuplicateAction:       0
    property bool   editStartImmediately:      false
    property bool   editSpeedLimiterOnStartup: false
    property int    editGlobalUploadLimitKBps: 0
    property bool   editShowDownloadComplete:  true
    property bool   editShowCompletionNotification: true
    property bool   editShowErrorNotification: true
    property bool   editShowFinishedCount:     true
    property bool   editSpeedInTrayTooltip:    true
    property bool   editSpeedInTitleBar:       false
    property bool   editSpeedInStatusBar:      false
    property bool   editEstimatedOnlineUsersInStatusBar: false
    property bool   editRatioInStatusBar:      false
    property bool   editStartDownloadWhileFileInfo: true
    property bool   editShowQueueSelectionOnDownloadLater: true
    property bool   editShowQueueSelectionOnBatchDownload: true
    property bool   editUseCustomUserAgent:    false
    property string editCustomUserAgent:       ""
    property int    editSavedSpeedLimitKBps:   500
    property int    editBypassInterceptKey:    0
    property bool   editLaunchOnStartup:       false
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
    property bool   editYtdlpAutoUpdate:       false
    property string editYtdlpJsRuntimePath:    ""
    property bool   editTorrentEnableDht:      true
    property bool   editTorrentEnableLsd:      true
    property bool   editTorrentEnableUpnp:     true
    property bool   editTorrentEnableNatPmp:   true
    property int    editTorrentListenPort:     6881
    property int    editTorrentConnectionsLimit: 200
    property int    editTorrentConnectionsLimitPerTorrent: 0
    property int    editTorrentUploadSlotsLimit: 8
    property int    editTorrentUploadSlotsLimitPerTorrent: 0
    property int    editTorrentProtocol: 0
    property string editTorrentCustomUserAgent: ""
    property string editTorrentBindInterface:  ""
    property string editTorrentBlockedPeerUserAgents: ""
    property var    editTorrentBlockedPeerCountries: []
    property var    editTorrentBannedPeers: []
    property bool   editTorrentAutoBanAbusivePeers: false
    property bool   editTorrentAutoBanMediaPlayerPeers: false
    property int    editTorrentEncryptionMode: 0
    property var    torrentAdapterOptions:     []
    property var    torrentCountryOptions:     []
    property string selectedTorrentCountryCode: ""
    property string manualBanPeerText: ""
    // Proxy settings — 0=None, 1=System, 2=HTTP/HTTPS, 3=SOCKS5
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

    readonly property string defaultUserAgent: "Stellar/" + App.appVersion
    readonly property string displayedUserAgent: editUseCustomUserAgent
        ? editCustomUserAgent
        : defaultUserAgent
    readonly property string lastTryPreview: {
        var datePart
        switch (editLastTryDateStyle) {
        case 1:
            datePart = "4/10/2026"
            break
        case 2:
            datePart = "10/4/2026"
            break
        case 3:
            datePart = "2026-04-10"
            break
        default:
            datePart = "Apr 10 2026"
            break
        }

        var timePart
        if (editLastTryUse24Hour)
            timePart = editLastTryShowSeconds ? "15:49:22" : "15:49"
        else
            timePart = editLastTryShowSeconds ? "3:49:22 PM" : "3:49 PM"

        return datePart + " " + timePart
    }

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
            name: "Default route",
            details: "Let the OS choose the active network adapter."
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
            name: adapterId + " (Unavailable)",
            details: "This adapter is not currently available. Reconnect it or choose a different adapter."
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

    component ProxyRadioButton: RadioButton {
        topPadding: 0
        bottomPadding: 0
        contentItem: Text {
            text: parent.text
            color: "#d0d0d0"
            font.pixelSize: 13
            leftPadding: parent.indicator.width + 4
            verticalAlignment: Text.AlignVCenter
        }
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
            _centerOnOwner()
            refreshTorrentNetworkAdapters()
            refreshTorrentCountryOptions()
            refreshIpToCityDbInfo()
            refreshAssociationStatus()
            resetEdits()
            catList.currentIndex = root.initialPage
        }
    }

    Connections {
        target: App
        function onIpToCityDbInfoChanged() {
            root.ipToCityDbInfo = App.ipToCityDbInfo
        }
    }

    Connections {
        target: App.settings
        function onGlobalSpeedLimitKBpsChanged() {
            root.editGlobalSpeedLimitKBps = App.settings.globalSpeedLimitKBps
            if (root.editGlobalSpeedLimitKBps > 0 && root.editSavedSpeedLimitKBps === 0) {
                root.editSavedSpeedLimitKBps = root.editGlobalSpeedLimitKBps
            }
        }
    }

    // Track whether anything has been changed
    readonly property bool settingsChanged:
        editMaxConcurrent         !== App.settings.maxConcurrent        ||
        editSegmentsPerDownload   !== App.settings.segmentsPerDownload  ||
        editDefaultSavePath       !== App.settings.defaultSavePath      ||
        editTemporaryDirectory    !== App.settings.temporaryDirectory   ||
        editGlobalSpeedLimitKBps  !== App.settings.globalSpeedLimitKBps ||
        editMinimizeToTray        !== App.settings.minimizeToTray       ||
        editCloseToTray           !== App.settings.closeToTray          ||
        editShowTips              !== App.settings.showTips             ||
        editMaxRetries            !== App.settings.maxRetries           ||
        editConnectionTimeoutSecs !== App.settings.connectionTimeoutSecs ||
        editDuplicateAction       !== App.settings.duplicateAction  ||
        editStartImmediately      !== App.settings.startImmediately ||
        editSpeedLimiterOnStartup !== App.settings.speedLimiterOnStartup ||
        editGlobalUploadLimitKBps !== App.settings.globalUploadLimitKBps ||
        editStartDownloadWhileFileInfo !== App.settings.startDownloadWhileFileInfo ||
        editUseCustomUserAgent    !== App.settings.useCustomUserAgent ||
        editCustomUserAgent       !== App.settings.customUserAgent ||
        editShowQueueSelectionOnDownloadLater !== App.settings.showQueueSelectionOnDownloadLater ||
        editShowQueueSelectionOnBatchDownload  !== App.settings.showQueueSelectionOnBatchDownload ||
        editBypassInterceptKey    !== App.settings.bypassInterceptKey ||
        editSavedSpeedLimitKBps   !== App.settings.savedSpeedLimitKBps ||
        editShowDownloadComplete  !== App.settings.showDownloadComplete ||
        editShowCompletionNotification !== App.settings.showCompletionNotification ||
        editShowErrorNotification !== App.settings.showErrorNotification ||
        editShowFinishedCount     !== App.settings.showFinishedCount ||
        editSpeedInTrayTooltip    !== App.settings.speedInTrayTooltip ||
        editSpeedInTitleBar       !== App.settings.speedInTitleBar ||
        editSpeedInStatusBar      !== App.settings.speedInStatusBar ||
        editEstimatedOnlineUsersInStatusBar !== App.settings.estimatedOnlineUsersInStatusBar ||
        editRatioInStatusBar      !== App.settings.ratioInStatusBar ||
        editLaunchOnStartup       !== App.settings.launchOnStartup ||
        editClipboardMonitorEnabled !== App.settings.clipboardMonitorEnabled ||
        editDoubleClickAction     !== App.settings.doubleClickAction ||
        editSpeedScheduleEnabled  !== App.settings.speedScheduleEnabled ||
        editSpeedScheduleJson     !== App.settings.speedScheduleJson ||
        editAutoCheckUpdates      !== App.settings.autoCheckUpdates ||
        editLastTryDateStyle      !== App.settings.lastTryDateStyle ||
        editLastTryUse24Hour      !== App.settings.lastTryUse24Hour ||
        editLastTryShowSeconds    !== App.settings.lastTryShowSeconds ||
        editYtdlpCustomBinaryPath !== App.settings.ytdlpCustomBinaryPath ||
        editYtdlpAutoUpdate       !== App.settings.ytdlpAutoUpdate       ||
        editYtdlpJsRuntimePath    !== App.settings.ytdlpJsRuntimePath    ||
        editTorrentEnableDht      !== App.settings.torrentEnableDht      ||
        editTorrentEnableLsd      !== App.settings.torrentEnableLsd      ||
        editTorrentEnableUpnp     !== App.settings.torrentEnableUpnp     ||
        editTorrentEnableNatPmp   !== App.settings.torrentEnableNatPmp   ||
        editTorrentListenPort     !== App.settings.torrentListenPort     ||
        editTorrentConnectionsLimit !== App.settings.torrentConnectionsLimit ||
        editTorrentConnectionsLimitPerTorrent !== App.settings.torrentConnectionsLimitPerTorrent ||
        editTorrentUploadSlotsLimit !== App.settings.torrentUploadSlotsLimit ||
        editTorrentUploadSlotsLimitPerTorrent !== App.settings.torrentUploadSlotsLimitPerTorrent ||
        editTorrentProtocol !== App.settings.torrentProtocol ||
        editTorrentCustomUserAgent !== App.settings.torrentCustomUserAgent ||
        editTorrentBindInterface  !== App.settings.torrentBindInterface  ||
        editTorrentBlockedPeerUserAgents !== App.settings.torrentBlockedPeerUserAgents ||
        JSON.stringify(editTorrentBlockedPeerCountries) !== JSON.stringify(App.settings.torrentBlockedPeerCountries) ||
        JSON.stringify(editTorrentBannedPeers) !== JSON.stringify(App.settings.torrentBannedPeers) ||
        editTorrentAutoBanAbusivePeers !== App.settings.torrentAutoBanAbusivePeers ||
        editTorrentAutoBanMediaPlayerPeers !== App.settings.torrentAutoBanMediaPlayerPeers ||
        editTorrentEncryptionMode !== App.settings.torrentEncryptionMode ||
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
        editRssSmartFiltersJson       !== App.settings.rssSmartFiltersJson

    property bool catDirty:       false
    property bool loadingCategory: false   // suppresses onTextChanged during programmatic load
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
                reason: "Manual ban",
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

    FolderDialog {
        id: saveFolderDlg
        currentFolder: root.editDefaultSavePath.length > 0
                       ? ("file:///" + root.editDefaultSavePath.replace(/\\/g, "/")) : ""
        onAccepted: {
            var path = selectedFolder.toString()
                           .replace(/^file:\/\/\//, "").replace(/^file:\/\//, "")
            root.editDefaultSavePath = path
        }
    }

    FolderDialog {
        id: tempFolderDlg
        currentFolder: root.editTemporaryDirectory.length > 0
                       ? ("file:///" + root.editTemporaryDirectory.replace(/\\/g, "/")) : ""
        onAccepted: {
            var path = selectedFolder.toString()
                           .replace(/^file:\/\/\//, "").replace(/^file:\/\//, "")
            root.editTemporaryDirectory = path
        }
    }

    // File picker for a custom yt-dlp binary location
    FileDialog {
        id: ytdlpFileDlg
        title: "Select yt-dlp binary"
        fileMode: FileDialog.OpenFile
        nameFilters: Qt.platform.os === "windows"
                     ? ["yt-dlp executable (yt-dlp.exe)", "All files (*)"]
                     : ["yt-dlp executable (yt-dlp)", "All files (*)"]
        onAccepted: {
            var path = selectedFile.toString()
                .replace(/^file:\/\/\//, "").replace(/^file:\/\//, "")
            root.editYtdlpCustomBinaryPath = path
        }
    }

    // File picker for a custom JS runtime (deno/node/bun/qjs) location
    FileDialog {
        id: jsRuntimeFileDlg
        title: "Select JavaScript runtime binary"
        fileMode: FileDialog.OpenFile
        nameFilters: Qt.platform.os === "windows"
                     ? ["Executable (*.exe)", "All files (*)"]
                     : ["All files (*)"]
        onAccepted: {
            var path = selectedFile.toString()
                .replace(/^file:\/\/\//, "").replace(/^file:\/\//, "")
            root.editYtdlpJsRuntimePath = path
        }
    }

    function applySettings() {
        // Always flush the current category form
        if (catPage.catEditId !== "") {
            var exts = catEditExts.text.split(",").map(function(s) {
                return s.trim().replace(/^\./, "").toLowerCase()
            }).filter(function(s) { return s.length > 0 })
            var sites = catEditSites.text.split(/\s+/).filter(function(s) { return s.length > 0 })
            App.categoryModel.updateCategory(catPage.catEditId, catEditName.text.trim(), exts, sites, catEditPath.text.trim())
            catDirty = false
        }

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
        App.settings.segmentsPerDownload   = editSegmentsPerDownload
        App.settings.defaultSavePath       = editDefaultSavePath
        App.settings.temporaryDirectory    = editTemporaryDirectory
        App.settings.globalSpeedLimitKBps  = editGlobalSpeedLimitKBps
        App.settings.minimizeToTray        = editMinimizeToTray
        App.settings.closeToTray           = editCloseToTray
        App.settings.showTips              = editShowTips
        App.settings.maxRetries            = editMaxRetries
        App.settings.connectionTimeoutSecs = editConnectionTimeoutSecs
        App.settings.duplicateAction       = editDuplicateAction
        App.settings.startImmediately       = editStartImmediately
        App.settings.speedLimiterOnStartup  = editSpeedLimiterOnStartup
        App.settings.globalUploadLimitKBps = editGlobalUploadLimitKBps
        App.settings.startDownloadWhileFileInfo = editStartDownloadWhileFileInfo
        App.settings.showQueueSelectionOnDownloadLater = editShowQueueSelectionOnDownloadLater
        App.settings.showQueueSelectionOnBatchDownload  = editShowQueueSelectionOnBatchDownload
        App.settings.useCustomUserAgent    = editUseCustomUserAgent
        App.settings.customUserAgent       = editCustomUserAgent
        App.settings.bypassInterceptKey    = editBypassInterceptKey
        App.settings.savedSpeedLimitKBps    = editSavedSpeedLimitKBps
        App.settings.showDownloadComplete   = editShowDownloadComplete
        App.settings.showCompletionNotification = editShowCompletionNotification
        App.settings.showErrorNotification  = editShowErrorNotification
        App.settings.showFinishedCount      = editShowFinishedCount
        App.settings.speedInTrayTooltip     = editSpeedInTrayTooltip
        App.settings.speedInTitleBar        = editSpeedInTitleBar
        App.settings.speedInStatusBar       = editSpeedInStatusBar
        App.settings.estimatedOnlineUsersInStatusBar = editEstimatedOnlineUsersInStatusBar
        App.settings.ratioInStatusBar       = editRatioInStatusBar
        App.settings.launchOnStartup        = editLaunchOnStartup
        App.settings.clipboardMonitorEnabled = editClipboardMonitorEnabled
        App.settings.doubleClickAction      = editDoubleClickAction
        App.settings.speedScheduleEnabled   = editSpeedScheduleEnabled
        App.settings.speedScheduleJson      = editSpeedScheduleJson
        App.settings.autoCheckUpdates       = editAutoCheckUpdates
        App.settings.lastTryDateStyle       = editLastTryDateStyle
        App.settings.lastTryUse24Hour       = editLastTryUse24Hour
        App.settings.lastTryShowSeconds     = editLastTryShowSeconds
        App.settings.ytdlpCustomBinaryPath  = editYtdlpCustomBinaryPath
        App.settings.ytdlpAutoUpdate        = editYtdlpAutoUpdate
        App.settings.ytdlpJsRuntimePath     = editYtdlpJsRuntimePath
        App.settings.torrentEnableDht       = editTorrentEnableDht
        App.settings.torrentEnableLsd       = editTorrentEnableLsd
        App.settings.torrentEnableUpnp      = editTorrentEnableUpnp
        App.settings.torrentEnableNatPmp    = editTorrentEnableNatPmp
        App.settings.torrentListenPort      = editTorrentListenPort
        App.settings.torrentConnectionsLimit = editTorrentConnectionsLimit
        App.settings.torrentConnectionsLimitPerTorrent = editTorrentConnectionsLimitPerTorrent
        App.settings.torrentUploadSlotsLimit = editTorrentUploadSlotsLimit
        App.settings.torrentUploadSlotsLimitPerTorrent = editTorrentUploadSlotsLimitPerTorrent
        App.settings.torrentProtocol = editTorrentProtocol
        App.settings.torrentCustomUserAgent = editTorrentCustomUserAgent
        App.settings.torrentBindInterface   = editTorrentBindInterface
        App.settings.torrentBlockedPeerUserAgents = editTorrentBlockedPeerUserAgents
        App.settings.torrentBlockedPeerCountries = editTorrentBlockedPeerCountries
        App.settings.torrentBannedPeers = editTorrentBannedPeers
        App.settings.torrentAutoBanAbusivePeers = editTorrentAutoBanAbusivePeers
        App.settings.torrentAutoBanMediaPlayerPeers = editTorrentAutoBanMediaPlayerPeers
        App.settings.torrentEncryptionMode = editTorrentEncryptionMode
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
        App.settings.save()
        // Sync edit properties so settingsChanged resets to false
        resetEdits()
    }

    function resetEdits() {
        refreshTorrentNetworkAdapters()
        editMaxConcurrent         = App.settings.maxConcurrent
        editSegmentsPerDownload   = App.settings.segmentsPerDownload
        editDefaultSavePath       = App.settings.defaultSavePath
        editTemporaryDirectory    = App.settings.temporaryDirectory
        editGlobalSpeedLimitKBps  = App.settings.globalSpeedLimitKBps
        editMinimizeToTray        = App.settings.minimizeToTray
        editCloseToTray           = App.settings.closeToTray
        editShowTips              = App.settings.showTips
        editShowExceptionsDialog  = App.settings.showExceptionsDialog
        editMaxRetries            = App.settings.maxRetries
        editConnectionTimeoutSecs = App.settings.connectionTimeoutSecs
        editDuplicateAction       = App.settings.duplicateAction
        editStartImmediately      = App.settings.startImmediately
        editSpeedLimiterOnStartup = App.settings.speedLimiterOnStartup
        editGlobalUploadLimitKBps = App.settings.globalUploadLimitKBps
        editStartDownloadWhileFileInfo = App.settings.startDownloadWhileFileInfo
        editShowQueueSelectionOnDownloadLater = App.settings.showQueueSelectionOnDownloadLater
        editShowQueueSelectionOnBatchDownload  = App.settings.showQueueSelectionOnBatchDownload
        editUseCustomUserAgent    = App.settings.useCustomUserAgent
        editCustomUserAgent       = App.settings.customUserAgent
        editBypassInterceptKey    = App.settings.bypassInterceptKey
        editSavedSpeedLimitKBps   = App.settings.savedSpeedLimitKBps
        editShowDownloadComplete  = App.settings.showDownloadComplete
        editShowCompletionNotification = App.settings.showCompletionNotification
        editShowErrorNotification = App.settings.showErrorNotification
        editShowFinishedCount     = App.settings.showFinishedCount
        editSpeedInTrayTooltip    = App.settings.speedInTrayTooltip
        editSpeedInTitleBar       = App.settings.speedInTitleBar
        editSpeedInStatusBar      = App.settings.speedInStatusBar
        editEstimatedOnlineUsersInStatusBar = App.settings.estimatedOnlineUsersInStatusBar
        editRatioInStatusBar      = App.settings.ratioInStatusBar
        editLaunchOnStartup       = App.settings.launchOnStartup
        editClipboardMonitorEnabled = App.settings.clipboardMonitorEnabled
        editDoubleClickAction     = App.settings.doubleClickAction
        editSpeedScheduleEnabled  = App.settings.speedScheduleEnabled
        editSpeedScheduleJson     = App.settings.speedScheduleJson || "[]"
        editAutoCheckUpdates      = App.settings.autoCheckUpdates
        editLastTryDateStyle      = App.settings.lastTryDateStyle
        editLastTryUse24Hour      = App.settings.lastTryUse24Hour
        editLastTryShowSeconds    = App.settings.lastTryShowSeconds
        editYtdlpCustomBinaryPath = App.settings.ytdlpCustomBinaryPath
        editYtdlpAutoUpdate       = App.settings.ytdlpAutoUpdate
        editYtdlpJsRuntimePath    = App.settings.ytdlpJsRuntimePath
        editTorrentEnableDht      = App.settings.torrentEnableDht
        editTorrentEnableLsd      = App.settings.torrentEnableLsd
        editTorrentEnableUpnp     = App.settings.torrentEnableUpnp
        editTorrentEnableNatPmp   = App.settings.torrentEnableNatPmp
        editTorrentListenPort     = App.settings.torrentListenPort
        editTorrentConnectionsLimit = App.settings.torrentConnectionsLimit
        editTorrentConnectionsLimitPerTorrent = App.settings.torrentConnectionsLimitPerTorrent
        editTorrentUploadSlotsLimit = App.settings.torrentUploadSlotsLimit
        editTorrentUploadSlotsLimitPerTorrent = App.settings.torrentUploadSlotsLimitPerTorrent
        editTorrentProtocol = App.settings.torrentProtocol
        editTorrentCustomUserAgent = App.settings.torrentCustomUserAgent
        editTorrentBindInterface  = App.settings.torrentBindInterface
        editTorrentBlockedPeerUserAgents = App.settings.torrentBlockedPeerUserAgents
        editTorrentBlockedPeerCountries = App.settings.torrentBlockedPeerCountries.slice()
        editTorrentBannedPeers = App.settings.torrentBannedPeers.slice()
        editTorrentAutoBanAbusivePeers = App.settings.torrentAutoBanAbusivePeers
        editTorrentAutoBanMediaPlayerPeers = App.settings.torrentAutoBanMediaPlayerPeers
        editTorrentEncryptionMode = App.settings.torrentEncryptionMode
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
        // Reset dirty flags so Apply button is disabled until user actually changes something
        catDirty = false
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 0

            // Sidebar
            Rectangle {
                Layout.fillHeight: true
                width: 160
                color: "#252525"

                ListView {
                    id: catList
                    anchors.fill: parent
                    anchors.topMargin: 8
                    model: ["Connection", "Categories", "Downloads", "Browser", "Speed Limiter", "Notifications", "General", "Media", "Torrents", "RSS", "Associations", "About"]
                    currentIndex: root.initialPage

                    delegate: Rectangle {
                        width: ListView.view.width
                        height: 36
                        color: catList.currentIndex === index ? "#1e3a6e" : (ma.containsMouse ? "#2a2a2a" : "transparent")

                        Text {
                            anchors { verticalCenter: parent.verticalCenter; left: parent.left; leftMargin: 16 }
                            text: modelData
                            color: catList.currentIndex === index ? "#ffffff" : "#c0c0c0"
                            font.pixelSize: 13
                        }

                        MouseArea {
                            id: ma
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: catList.currentIndex = index
                        }
                    }
                }
            }

            // Content pages
            StackLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                currentIndex: catList.currentIndex

                // Connection
                Item {
                    ScrollView {
                        anchors.fill: parent
                        contentWidth: availableWidth
                        clip: true

                    ColumnLayout {
                        width: parent.width
                        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
                        spacing: 10

                        Text { text: "Connection"; color: "#ffffff"; font.pixelSize: 16; font.bold: true }
                        Rectangle { Layout.fillWidth: true; height: 1; color: "#3a3a3a" }

                        GridLayout {
                            columns: 3; columnSpacing: 10; rowSpacing: 10

                            Text { text: "Maximum simultaneous downloads:"; color: "#c0c0c0"; font.pixelSize: 13 }
                            SpinBox { from: 1; to: 16; value: root.editMaxConcurrent; onValueModified: root.editMaxConcurrent = value; padding: 0 }
                            Item {}

                            Text { text: "Segments per download:"; color: "#c0c0c0"; font.pixelSize: 13 }
                            SpinBox { from: 1; to: 16; value: root.editSegmentsPerDownload; onValueModified: root.editSegmentsPerDownload = value; padding: 0 }
                            Item {}

                            Text { text: "Connection timeout (seconds):"; color: "#c0c0c0"; font.pixelSize: 13 }
                            SpinBox { from: 5; to: 120; value: root.editConnectionTimeoutSecs; onValueModified: root.editConnectionTimeoutSecs = value; padding: 0 }
                            Item {}

                            Text { text: "Retry failed downloads:"; color: "#c0c0c0"; font.pixelSize: 13 }
                            SpinBox { from: 0; to: 10; value: root.editMaxRetries; onValueModified: root.editMaxRetries = value; padding: 0 }
                            Text { text: "times"; color: "#a0a0a0"; font.pixelSize: 13 }
                        }

                        Rectangle { Layout.fillWidth: true; height: 1; color: "#2e2e2e" }

                        Text {
                            text: "User Agent"
                            color: "#ffffff"; font.pixelSize: 14; font.bold: true
                        }

                        Text {
                            text: "When custom mode is off, Stellar uses its built-in User-Agent with the current version."
                            color: "#c0c0c0"; font.pixelSize: 13
                            wrapMode: Text.WordWrap
                            Layout.fillWidth: true
                        }

                        CheckBox {
                            text: "Use custom user agent"
                            topPadding: 0; bottomPadding: 0
                            checked: root.editUseCustomUserAgent
                            onCheckedChanged: root.editUseCustomUserAgent = checked
                            contentItem: Text {
                                text: parent.text
                                color: "#d0d0d0"; font.pixelSize: 13
                                leftPadding: parent.indicator.width + 4
                            }
                        }

                        TextField {
                            Layout.fillWidth: true
                            text: root.displayedUserAgent
                            readOnly: !root.editUseCustomUserAgent
                            selectByMouse: true
                            onTextEdited: root.editCustomUserAgent = text
                            color: root.editUseCustomUserAgent ? "#d0d0d0" : "#7a7a7a"
                            font.pixelSize: 13
                            background: Rectangle {
                                color: root.editUseCustomUserAgent ? "#2d2d2d" : "#252525"
                                border.color: root.editUseCustomUserAgent ? "#4a4a4a" : "#3a3a3a"
                                radius: 3
                            }
                        }

                        Text {
                            text: root.editUseCustomUserAgent
                                  ? "This value will be sent exactly as entered."
                                  : "Built-in default shown above. Enable the checkbox to edit and override it."
                            color: "#555"; font.pixelSize: 10
                            wrapMode: Text.WordWrap
                            Layout.fillWidth: true
                        }

                        Rectangle { Layout.fillWidth: true; height: 1; color: "#2e2e2e"; Layout.topMargin: 4 }

                        Text {
                            text: "Proxy"
                            color: "#ffffff"; font.pixelSize: 14; font.bold: true
                        }

                        // Type selector
                        ColumnLayout {
                            spacing: 6

                            ProxyRadioButton {
                                id: proxyNoneRadio
                                text: "No proxy"
                                checked: root.editProxyType === 0
                                onClicked: root.editProxyType = 0
                            }
                            ProxyRadioButton {
                                text: "Use system proxy"
                                checked: root.editProxyType === 1
                                onClicked: root.editProxyType = 1
                            }
                            ProxyRadioButton {
                                text: "HTTP / HTTPS proxy"
                                checked: root.editProxyType === 2
                                onClicked: root.editProxyType = 2
                            }
                            ProxyRadioButton {
                                text: "SOCKS5 proxy"
                                checked: root.editProxyType === 3
                                onClicked: root.editProxyType = 3
                            }
                        }

                        // Host / port / auth — only shown for custom proxy types
                        ColumnLayout {
                            visible: root.editProxyType === 2 || root.editProxyType === 3
                            spacing: 8
                            Layout.fillWidth: true

                            // Host + port row
                            RowLayout {
                                spacing: 8
                                Layout.fillWidth: true

                                Text { text: "Host:"; color: "#c0c0c0"; font.pixelSize: 13 }
                                TextField {
                                    Layout.fillWidth: true
                                    text: root.editProxyHost
                                    selectByMouse: true
                                    font.pixelSize: 13
                                    onTextEdited: root.editProxyHost = text
                                    background: Rectangle {
                                        color: "#2d2d2d"; border.color: parent.activeFocus ? "#4488dd" : "#4a4a4a"; radius: 3
                                    }
                                    color: "#d0d0d0"
                                }
                                Text { text: "Port:"; color: "#c0c0c0"; font.pixelSize: 13 }
                                TextField {
                                    implicitWidth: 120
                                    text: root.editProxyPort.toString()
                                    selectByMouse: true
                                    font.pixelSize: 13
                                    inputMethodHints: Qt.ImhDigitsOnly
                                    validator: IntValidator { bottom: 1; top: 65535 }
                                    onTextEdited: {
                                        var v = parseInt(text)
                                        if (!isNaN(v) && v >= 1 && v <= 65535)
                                            root.editProxyPort = v
                                    }
                                    background: Rectangle {
                                        color: "#2d2d2d"; border.color: parent.activeFocus ? "#4488dd" : "#4a4a4a"; radius: 3
                                    }
                                    color: "#d0d0d0"
                                }
                            }

                            // Auth (optional)
                            GridLayout {
                                columns: 2; columnSpacing: 8; rowSpacing: 6
                                Layout.fillWidth: true

                                Text { text: "Username:"; color: "#c0c0c0"; font.pixelSize: 13 }
                                TextField {
                                    Layout.fillWidth: true
                                    placeholderText: "Optional"
                                    text: root.editProxyUsername
                                    selectByMouse: true
                                    font.pixelSize: 13
                                    onTextEdited: root.editProxyUsername = text
                                    background: Rectangle {
                                        color: "#2d2d2d"; border.color: parent.activeFocus ? "#4488dd" : "#4a4a4a"; radius: 3
                                    }
                                    color: "#d0d0d0"
                                }

                                Text { text: "Password:"; color: "#c0c0c0"; font.pixelSize: 13 }
                                TextField {
                                    Layout.fillWidth: true
                                    placeholderText: "Optional"
                                    text: root.editProxyPassword
                                    echoMode: TextInput.Password
                                    selectByMouse: true
                                    font.pixelSize: 13
                                    onTextEdited: root.editProxyPassword = text
                                    background: Rectangle {
                                        color: "#2d2d2d"; border.color: parent.activeFocus ? "#4488dd" : "#4a4a4a"; radius: 3
                                    }
                                    color: "#d0d0d0"
                                }
                            }

                            Text {
                                text: "All downloads, video downloads, update checks, and torrent peer/tracker connections are routed through this proxy."
                                color: "#555"; font.pixelSize: 10
                                wrapMode: Text.WordWrap
                                Layout.fillWidth: true
                            }
                        }

                        Text {
                            visible: root.editProxyType === 1
                            text: "Stellar will use the proxy configured in your operating system network settings."
                            color: "#555"; font.pixelSize: 10
                            wrapMode: Text.WordWrap
                            Layout.fillWidth: true
                        }

                        // ── Proxy test ────────────────────────────────────────
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
                                        proxyTestRow._result = "Timed out — proxy did not respond"
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
                                text: proxyTestRow._testing ? "Testing…" : "Test Proxy"
                                enabled: !proxyTestRow._testing
                                onClicked: {
                                    proxyTestRow._result = ""
                                    proxyTestRow._testing = true
                                    proxyTestTimeout.restart()
                                    App.testProxy()
                                }
                            }
                            Text {
                                visible: proxyTestRow._result.length > 0
                                text: proxyTestRow._result
                                color: proxyTestRow._ok ? "#66cc88" : "#dd6655"
                                font.pixelSize: 11
                                Layout.fillWidth: true
                                wrapMode: Text.WordWrap
                            }
                        }

                        Item { height: 12 }
                    }
                    }
                }

                // Categories
                Item {
                    id: catPage
                    property bool catEditBuiltIn: false
                    property string catEditId: ""

                    FolderDialog {
                        id: catSaveFolderDlg
                        onAccepted: {
                            var path = selectedFolder.toString()
                                .replace(/^file:\/\/\//, "").replace(/^file:\/\//, "")
                                .replace(/\//g, "\\")
                            catEditPath.text = path
                        }
                    }

                    ColumnLayout {
                        anchors { fill: parent; margins: 12 }
                        spacing: 10

                        Text { text: "Categories"; color: "#ffffff"; font.pixelSize: 16; font.bold: true }
                        Rectangle { Layout.fillWidth: true; height: 1; color: "#3a3a3a" }

                        RowLayout {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            spacing: 12

                            // ── Left: category list ──────────────────────────
                            ColumnLayout {
                                Layout.fillHeight: true
                                Layout.preferredWidth: 170
                                spacing: 4

                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    color: "#252525"
                                    border.color: "#3a3a3a"
                                    radius: 2
                                    clip: true

                                    ListView {
                                        id: catEditList
                                        anchors.fill: parent
                                        clip: true
                                        model: App.categoryModel
                                        currentIndex: 1
                                        ScrollBar.vertical: ScrollBar {}

                                        Component.onCompleted: {
                                            var d = App.categoryModel.categoryData(currentIndex)
                                            if (!d || !d.id) return
                                            root.loadingCategory = true
                                            catEditName.text  = d.label || ""
                                            catEditExts.text  = (d.extensions || []).join(", ")
                                            catEditSites.text = (d.sitePatterns || []).join(" ")
                                            catEditPath.text  = d.savePath || ""
                                            catPage.catEditBuiltIn = !!d.builtIn
                                            catPage.catEditId = d.id || ""
                                            root.loadingCategory = false
                                        }

                                        onCurrentIndexChanged: {
                                            // Always save the previous category before switching
                                            if (catPage.catEditId !== "") {
                                                var exts = catEditExts.text.split(",").map(function(s) {
                                                    return s.trim().replace(/^\./, "").toLowerCase()
                                                }).filter(function(s) { return s.length > 0 })
                                                var sites = catEditSites.text.split(/\s+/).filter(function(s) { return s.length > 0 })
                                                App.categoryModel.updateCategory(catPage.catEditId, catEditName.text.trim(), exts, sites, catEditPath.text.trim())
                                            }

                                            var d = App.categoryModel.categoryData(currentIndex)
                                            if (!d || !d.id) return
                                            root.loadingCategory = true
                                            catEditName.text  = d.label || ""
                                            catEditExts.text  = (d.extensions || []).join(", ")
                                            catEditSites.text = (d.sitePatterns || []).join(" ")
                                            catEditPath.text  = d.savePath || ""
                                            catPage.catEditBuiltIn = !!d.builtIn
                                            catPage.catEditId = d.id || ""
                                            root.loadingCategory = false
                                        }

                                        delegate: Rectangle {
                                            width: ListView.view.width
                                            // Hide the built-in "All Downloads" category (id = "all")
                                            visible: categoryId !== "all"
                                            height: visible ? 32 : 0
                                            color: catEditList.currentIndex === index
                                                   ? "#1e3a6e"
                                                   : (catItemMa.containsMouse ? "#2a2a2a" : "transparent")

                                            Text {
                                                anchors { verticalCenter: parent.verticalCenter; left: parent.left; leftMargin: 10; right: parent.right; rightMargin: 6 }
                                                text: categoryLabel
                                                color: catEditList.currentIndex === index ? "#ffffff" : "#c0c0c0"
                                                font.pixelSize: 12
                                                elide: Text.ElideRight
                                            }
                                            MouseArea {
                                                id: catItemMa
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                enabled: visible
                                                onClicked: catEditList.currentIndex = index
                                            }
                                        }
                                    }
                                }

                                // Add / Remove buttons below the list
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 6

                                    Rectangle {
                                        width: 32; height: 26; radius: 3
                                        color: addCatMa.containsMouse ? "#445544" : "#333"
                                        border.color: "#555"
                                        Text {
                                            anchors.centerIn: parent
                                            text: "+"
                                            color: "#c0c0c0"
                                            font.pixelSize: 16
                                            font.bold: true
                                        }
                                        MouseArea {
                                            id: addCatMa
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                App.categoryModel.addCategory("New Category")
                                                catEditList.currentIndex = App.categoryModel.categoryCount() - 1
                                            }
                                        }
                                    }

                                    Rectangle {
                                        width: 32; height: 26; radius: 3
                                        enabled: !catPage.catEditBuiltIn && catPage.catEditId !== ""
                                        color: delCatMa.containsMouse && enabled ? "#554444" : "#333"
                                        border.color: "#555"
                                        opacity: enabled ? 1.0 : 0.4
                                        Text {
                                            anchors.centerIn: parent
                                            text: "−"
                                            color: "#e0a0a0"
                                            font.pixelSize: 18
                                            font.bold: true
                                        }
                                        MouseArea {
                                            id: delCatMa
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: parent.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                                            onClicked: {
                                                if (!catPage.catEditBuiltIn) {
                                                    App.categoryModel.removeCategory(catPage.catEditId)
                                                    catEditList.currentIndex = 0
                                                }
                                            }
                                        }
                                    }

                                    Item { Layout.fillWidth: true }
                                }
                            }

                            // ── Right: edit form ─────────────────────────────
                            ColumnLayout {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                spacing: 12

                                // Name
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 4
                                    Text { text: "Name"; color: "#909090"; font.pixelSize: 11 }
                                    TextField {
                                        id: catEditName
                                        Layout.fillWidth: true
                                        implicitHeight: 30
                                        font.pixelSize: 12; color: "#d0d0d0"
                                        background: Rectangle { color: "#2d2d2d"; border.color: "#4a4a4a"; radius: 3 }
                                        leftPadding: 8
                                        onTextChanged: if (!root.loadingCategory) root.catDirty = true
                                    }
                                }

                                // File types
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 4
                                    Text { text: "File types  (comma-separated, e.g.  mp4, mkv, avi)"; color: "#909090"; font.pixelSize: 11 }
                                    ScrollView {
                                        Layout.fillWidth: true
                                        implicitHeight: 52
                                        clip: true
                                        background: Rectangle { color: "#2d2d2d"; border.color: "#4a4a4a"; radius: 3 }
                                        TextArea {
                                            id: catEditExts
                                            wrapMode: TextArea.Wrap
                                            font.pixelSize: 12; color: "#d0d0d0"
                                            background: null
                                            padding: 6
                                            placeholderText: "mp4, mkv, avi, mov"
                                            onTextChanged: if (!root.loadingCategory) root.catDirty = true
                                        }
                                    }
                                    // Warn when a category extension isn't in the browser auto-download list
                                    Text {
                                        Layout.fillWidth: true
                                        wrapMode: Text.WordWrap
                                        font.pixelSize: 11
                                        color: "#e8c840"
                                        visible: text.length > 0
                                        text: {
                                            var typed = catEditExts.text.split(/[\s,]+/).map(function(s) {
                                                return s.trim().toLowerCase().replace(/^\./, "")
                                            }).filter(function(s) { return s.length > 0 })

                                            // Use the live browser tab field if available, else fall back to saved setting
                                            var monitored = monitoredExtsArea
                                                ? monitoredExtsArea.text.split(/[\s,]+/).map(function(s) {
                                                    return s.trim().toLowerCase().replace(/^\./, "")
                                                }).filter(function(s) { return s.length > 0 })
                                                : App.settings.monitoredExtensions.slice()

                                            var missing = typed.filter(function(e) {
                                                return e.length > 0 && monitored.indexOf(e) < 0
                                            })
                                            return missing.length > 0
                                                ? "⚠ Not in browser auto-download list: " + missing.join(", ")
                                                : ""
                                        }
                                    }
                                }

                                // Sites
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 4
                                    Text { text: "Auto-assign from sites  (space-separated, * wildcard)"; color: "#909090"; font.pixelSize: 11 }
                                    TextField {
                                        id: catEditSites
                                        Layout.fillWidth: true
                                        implicitHeight: 30
                                        placeholderText: "*.youtube.com *.vimeo.com"
                                        font.pixelSize: 12; color: "#d0d0d0"
                                        background: Rectangle { color: "#2d2d2d"; border.color: "#4a4a4a"; radius: 3 }
                                        leftPadding: 8
                                        onTextChanged: if (!root.loadingCategory) root.catDirty = true
                                    }
                                    Text {
                                        text: "Downloads from matching sites will automatically go into this category."
                                        color: "#555"; font.pixelSize: 10
                                        wrapMode: Text.WordWrap
                                        Layout.fillWidth: true
                                    }
                                }

                                // Save to
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 4
                                    Text { text: "Save to folder"; color: "#909090"; font.pixelSize: 11 }
                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 6
                                        TextField {
                                            id: catEditPath
                                            Layout.fillWidth: true
                                            implicitHeight: 30
                                            font.pixelSize: 12; color: "#d0d0d0"
                                            background: Rectangle { color: "#2d2d2d"; border.color: "#4a4a4a"; radius: 3 }
                                            leftPadding: 8
                                            onTextChanged: if (!root.loadingCategory) root.catDirty = true
                                        }
                                        Rectangle {
                                            width: 32; height: 30; radius: 3
                                            color: browseMa.containsMouse ? "#445" : "#333"
                                            border.color: "#555"
                                            Text { anchors.centerIn: parent; text: "…"; color: "#c0c0c0"; font.pixelSize: 13 }
                                            MouseArea {
                                                id: browseMa
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: catSaveFolderDlg.open()
                                            }
                                        }
                                    }
                                }

                                Item { Layout.fillHeight: true }
                            }
                        }
                    }
                }

                // Downloads
                Item {
                    ScrollView {
                        anchors.fill: parent
                        contentWidth: availableWidth
                        clip: true

                        ColumnLayout {
                            width: parent.width - 24
                            x: 12
                            y: 12
                            spacing: 10

                        Text { text: "Downloads"; color: "#ffffff"; font.pixelSize: 16; font.bold: true }
                        Rectangle { Layout.fillWidth: true; height: 1; color: "#3a3a3a" }

                        Text { text: "Default save folder:"; color: "#c0c0c0"; font.pixelSize: 13 }
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8
                            TextField {
                                Layout.fillWidth: true
                                text: root.editDefaultSavePath
                                onTextChanged: root.editDefaultSavePath = text
                                color: "#d0d0d0"; font.pixelSize: 13
                                background: Rectangle { color: "#2d2d2d"; border.color: "#4a4a4a"; radius: 3 }
                            }
                            Button {
                                text: "Browse…"; font.pixelSize: 12
                                background: Rectangle { color: "#3a3a3a"; radius: 3 }
                                contentItem: Text { text: parent.text; color: "#d0d0d0"; font: parent.font; horizontalAlignment: Text.AlignHCenter }
                                onClicked: saveFolderDlg.open()
                            }
                        }

                        Rectangle { Layout.fillWidth: true; height: 1; color: "#2e2e2e" }

                        Text { text: "Stellar temporary directory:"; color: "#c0c0c0"; font.pixelSize: 13 }
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8
                            TextField {
                                Layout.fillWidth: true
                                text: root.editTemporaryDirectory
                                onTextChanged: root.editTemporaryDirectory = text
                                color: "#d0d0d0"; font.pixelSize: 13
                                background: Rectangle { color: "#2d2d2d"; border.color: "#4a4a4a"; radius: 3 }
                            }
                            DlgButton {
                                text: "Browse"
                                onClicked: tempFolderDlg.open()
                            }
                        }

                        Text {
                            text: "Stellar stores partially downloaded file parts and metadata here while downloading and assembling files."
                            color: "#7a7a7a"; font.pixelSize: 11
                            wrapMode: Text.WordWrap
                            Layout.fillWidth: true
                        }

                        CheckBox {
                            text: "Start downloading immediately (skip file info dialog)"
                            topPadding: 0; bottomPadding: 0
                            checked: root.editStartImmediately
                            onCheckedChanged: root.editStartImmediately = checked
                            contentItem: Text { text: parent.text; color: "#d0d0d0"; font.pixelSize: 13; leftPadding: parent.indicator.width + 4 }
                        }

                        CheckBox {
                            text: "Show download complete dialog"
                            topPadding: 0; bottomPadding: 0
                            checked: root.editShowDownloadComplete
                            onCheckedChanged: root.editShowDownloadComplete = checked
                            contentItem: Text { text: parent.text; color: "#d0d0d0"; font.pixelSize: 13; leftPadding: parent.indicator.width + 4 }
                        }

                        CheckBox {
                            text: "Start downloading immediately while displaying \"Download File Info\" dialog"
                            topPadding: 0; bottomPadding: 0
                            checked: root.editStartDownloadWhileFileInfo
                            onCheckedChanged: root.editStartDownloadWhileFileInfo = checked
                            contentItem: Text { text: parent.text; color: "#d0d0d0"; font.pixelSize: 13; leftPadding: parent.indicator.width + 4; wrapMode: Text.WordWrap; Layout.fillWidth: true }
                        }

                        CheckBox {
                            text: "Show queue selection panel on pressing Download Later"
                            topPadding: 0; bottomPadding: 0
                            checked: root.editShowQueueSelectionOnDownloadLater
                            onCheckedChanged: root.editShowQueueSelectionOnDownloadLater = checked
                            contentItem: Text { text: parent.text; color: "#d0d0d0"; font.pixelSize: 13; leftPadding: parent.indicator.width + 4; wrapMode: Text.WordWrap; Layout.fillWidth: true }
                        }
                        CheckBox {
                            text: "Show queue selection panel on closing batch downloads dialog"
                            topPadding: 0; bottomPadding: 0
                            checked: root.editShowQueueSelectionOnBatchDownload
                            onCheckedChanged: root.editShowQueueSelectionOnBatchDownload = checked
                            contentItem: Text { text: parent.text; color: "#d0d0d0"; font.pixelSize: 13; leftPadding: parent.indicator.width + 4; wrapMode: Text.WordWrap; Layout.fillWidth: true }
                        }
                        Text {
                            text: "Note: These settings don't apply to queue processing for the Start Downloading Immediately setting and Show Download Complete dialog setting."
                            color: "#7a7a7a"; font.pixelSize: 10
                            wrapMode: Text.WordWrap
                            Layout.fillWidth: true
                        }

                        Rectangle { Layout.fillWidth: true; height: 1; color: "#2e2e2e" }

                        Text { text: "If a duplicate URL is added:"; color: "#c0c0c0"; font.pixelSize: 13 }
                        ComboBox {
                            id: duplicateActionCombo
                            model: [
                                "Ask me what to do",
                                "Add with a numbered file name",
                                "Overwrite the existing download",
                                "Resume / show complete dialog"
                            ]
                            currentIndex: root.editDuplicateAction
                            implicitWidth: 260
                            font.pixelSize: 12
                            background: Rectangle { color: "#2d2d2d"; border.color: "#4a4a4a"; radius: 3 }
                            contentItem: Text {
                                leftPadding: 8
                                text: duplicateActionCombo.displayText
                                color: "#d0d0d0"; font: duplicateActionCombo.font
                                verticalAlignment: Text.AlignVCenter
                            }
                            onCurrentIndexChanged: root.editDuplicateAction = currentIndex
                        }

                        Rectangle { Layout.fillWidth: true; height: 1; color: "#2e2e2e" }

                        Text { text: "Double-clicking on a download in the file list:"; color: "#c0c0c0"; font.pixelSize: 13 }
                        ComboBox {
                            id: doubleClickActionCombo
                            model: [
                                "Open file properties dialog",
                                "Open file",
                                "Open folder"
                            ]
                            currentIndex: root.editDoubleClickAction
                            implicitWidth: 260
                            font.pixelSize: 12
                            background: Rectangle { color: "#2d2d2d"; border.color: "#4a4a4a"; radius: 3 }
                            contentItem: Text {
                                leftPadding: 8
                                text: doubleClickActionCombo.displayText
                                color: "#d0d0d0"; font: doubleClickActionCombo.font
                                verticalAlignment: Text.AlignVCenter
                            }
                            onCurrentIndexChanged: root.editDoubleClickAction = currentIndex
                        }

                        Rectangle { Layout.fillWidth: true; height: 1; color: "#2e2e2e" }

                        Text { text: "Last try date format:"; color: "#c0c0c0"; font.pixelSize: 13 }
                        ComboBox {
                            id: lastTryDateStyleCombo
                            model: [
                                "Apr 10 2026",
                                "4/10/2026",
                                "10/4/2026",
                                "2026-04-10"
                            ]
                            currentIndex: root.editLastTryDateStyle
                            implicitWidth: 220
                            font.pixelSize: 12
                            background: Rectangle { color: "#2d2d2d"; border.color: "#4a4a4a"; radius: 3 }
                            contentItem: Text {
                                leftPadding: 8
                                text: lastTryDateStyleCombo.displayText
                                color: "#d0d0d0"; font: lastTryDateStyleCombo.font
                                verticalAlignment: Text.AlignVCenter
                            }
                            onCurrentIndexChanged: root.editLastTryDateStyle = currentIndex
                        }

                        Text { text: "Time format:"; color: "#c0c0c0"; font.pixelSize: 13 }
                        ComboBox {
                            id: lastTryTimeModeCombo
                            model: [
                                "24-hour time",
                                "12-hour time"
                            ]
                            currentIndex: root.editLastTryUse24Hour ? 0 : 1
                            implicitWidth: 220
                            font.pixelSize: 12
                            background: Rectangle { color: "#2d2d2d"; border.color: "#4a4a4a"; radius: 3 }
                            contentItem: Text {
                                leftPadding: 8
                                text: lastTryTimeModeCombo.displayText
                                color: "#d0d0d0"; font: lastTryTimeModeCombo.font
                                verticalAlignment: Text.AlignVCenter
                            }
                            onCurrentIndexChanged: root.editLastTryUse24Hour = currentIndex === 0
                        }

                        CheckBox {
                            text: "Show seconds"
                            topPadding: 0; bottomPadding: 0
                            checked: root.editLastTryShowSeconds
                            onCheckedChanged: root.editLastTryShowSeconds = checked
                            contentItem: Text { text: parent.text; color: "#d0d0d0"; font.pixelSize: 13; leftPadding: parent.indicator.width + 4 }
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: previewColumn.implicitHeight + 16
                            radius: 4
                            color: "#242424"
                            border.color: "#3a3a3a"

                            ColumnLayout {
                                id: previewColumn
                                anchors.fill: parent
                                anchors.margins: 8
                                spacing: 4

                                Text { text: "Preview"; color: "#909090"; font.pixelSize: 11 }
                                Text { text: root.lastTryPreview; color: "#f0f0f0"; font.pixelSize: 13; font.family: "Consolas" }
                            }
                        }

                            Item { height: 12 }
                        }
                    }
                }

                // Browser Integration
                Item {
                    id: browserPage

                    ScrollView {
                        anchors.fill: parent
                        contentWidth: availableWidth
                        clip: true

                        ColumnLayout {
                            width: browserPage.width - 24
                            x: 12; y: 12
                            spacing: 10

                            Text { text: "Browser Integration"; color: "#ffffff"; font.pixelSize: 16; font.bold: true }
                            Rectangle { Layout.fillWidth: true; height: 1; color: "#3a3a3a" }

                            // ── Monitored file types ──────────────────────────────
                            Text {
                                text: "Automatically start downloading the following file types:"
                                color: "#c0c0c0"; font.pixelSize: 13
                                wrapMode: Text.WordWrap
                                Layout.fillWidth: true
                            }

                            ScrollView {
                                Layout.fillWidth: true
                                implicitHeight: 72
                                clip: true
                                background: Rectangle { color: "#2d2d2d"; border.color: "#4a4a4a"; radius: 3 }
                                TextArea {
                                    id: monitoredExtsArea
                                    wrapMode: TextArea.Wrap
                                    font.pixelSize: 11
                                    font.family: "monospace"
                                    color: "#d0d0d0"
                                    background: null
                                    padding: 6
                                    text: App.settings.monitoredExtensions.join(" ").toUpperCase()
                                }
                            }

                            Text {
                                text: "Space or comma-separated. Case-insensitive."
                                color: "#555"; font.pixelSize: 10
                            }

                            Rectangle { Layout.fillWidth: true; height: 1; color: "#2e2e2e" }

                            // ── Excluded sites ────────────────────────────────────
                            Text {
                                text: "Don't start downloading automatically from the following sites:"
                                color: "#c0c0c0"; font.pixelSize: 13
                                wrapMode: Text.WordWrap
                                Layout.fillWidth: true
                            }

                            ScrollView {
                                Layout.fillWidth: true
                                implicitHeight: 60
                                clip: true
                                background: Rectangle { color: "#2d2d2d"; border.color: "#4a4a4a"; radius: 3 }
                                TextArea {
                                    id: excludedSitesArea
                                    wrapMode: TextArea.Wrap
                                    font.pixelSize: 11
                                    font.family: "monospace"
                                    color: "#d0d0d0"
                                    background: null
                                    padding: 6
                                    text: App.settings.excludedSites.join(" ")
                                }
                            }

                            Text {
                                text: "Space-separated host patterns. Wildcards (*) supported, e.g. *.update.microsoft.com"
                                color: "#555"; font.pixelSize: 10
                                wrapMode: Text.WordWrap
                                Layout.fillWidth: true
                            }

                            Rectangle { Layout.fillWidth: true; height: 1; color: "#2e2e2e" }

                            // ── Address Exceptions ────────────────────────────────
                            Text {
                                text: "Address Exceptions"
                                color: "#ffffff"; font.pixelSize: 14; font.bold: true
                            }

                            CheckBox {
                                id: showExceptDlgChk
                                text: "Show the dialog to add an address to the list of exceptions for a twice cancelled download"
                                topPadding: 0; bottomPadding: 0
                                Layout.fillWidth: true
                                checked: root.editShowExceptionsDialog
                                onCheckedChanged: root.editShowExceptionsDialog = checked
                                contentItem: Text {
                                    text: parent.text
                                    color: "#d0d0d0"; font.pixelSize: 12
                                    leftPadding: parent.indicator.width + 4
                                    wrapMode: Text.WordWrap
                                    width: parent.width
                                }
                            }

                            Text {
                                text: "Don't start downloading from the following addresses:"
                                color: "#c0c0c0"; font.pixelSize: 13
                                wrapMode: Text.WordWrap
                                Layout.fillWidth: true
                            }

                            ScrollView {
                                Layout.fillWidth: true
                                implicitHeight: 160
                                clip: true
                                background: Rectangle { color: "#2d2d2d"; border.color: "#4a4a4a"; radius: 3 }
                                TextArea {
                                    id: excludedAddrsArea
                                    wrapMode: TextArea.NoWrap
                                    font.pixelSize: 11
                                    font.family: "monospace"
                                    color: "#d0d0d0"
                                    background: null
                                    padding: 6
                                    text: App.settings.excludedAddresses.join("\n")
                                }
                            }

                            Text {
                                text: "One URL pattern per line. Wildcards (*) supported."
                                color: "#555"; font.pixelSize: 10
                            }

                            Rectangle { Layout.fillWidth: true; height: 1; color: "#2e2e2e" }

                            // ── Bypass interception key ────────────────────────────
                            Text {
                                text: "Bypass Download Interception"
                                color: "#ffffff"; font.pixelSize: 14; font.bold: true
                            }

                            Text {
                                text: "Hold this key while clicking a download link to skip interception and let the browser download:"
                                color: "#c0c0c0"; font.pixelSize: 13
                                wrapMode: Text.WordWrap
                                Layout.fillWidth: true
                            }

                            Row {
                                spacing: 12
                                ComboBox {
                                    id: bypassKeyCombo
                                    model: ["None", "Alt", "Ctrl", "Shift"]
                                    currentIndex: root.editBypassInterceptKey
                                    implicitWidth: 120
                                    font.pixelSize: 12
                                    background: Rectangle { color: "#2d2d2d"; border.color: "#4a4a4a"; radius: 3 }
                                    contentItem: Text {
                                        leftPadding: 8
                                        text: bypassKeyCombo.displayText
                                        color: "#d0d0d0"; font: bypassKeyCombo.font
                                        verticalAlignment: Text.AlignVCenter
                                    }
                                    onCurrentIndexChanged: root.editBypassInterceptKey = currentIndex
                                }
                            }

                            Item { height: 10 }
                        }
                    }
                }

                // Speed Limiter
                Item {
                    id: speedLimiterPage
                    ScrollView {
                        anchors.fill: parent
                        contentWidth: availableWidth
                        clip: true

                    ColumnLayout {
                        width: speedLimiterPage.width - 24
                        x: 12; y: 12
                        spacing: 10

                        Text { text: "Speed Limiter"; color: "#ffffff"; font.pixelSize: 16; font.bold: true }
                        Rectangle { Layout.fillWidth: true; height: 1; color: "#3a3a3a" }

                            CheckBox {
                                id: globalLimitChk
                                text: "Enable global speed limit"
                                topPadding: 0; bottomPadding: 0
                                checked: root.editGlobalSpeedLimitKBps > 0
                                onToggled: { 
                                    if (!checked) {
                                        root.editGlobalSpeedLimitKBps = 0
                                    } else {
                                        root.editGlobalSpeedLimitKBps = root.editSavedSpeedLimitKBps
                                    }
                                }
                                contentItem: Text { text: parent.text; color: "#d0d0d0"; font.pixelSize: 13; leftPadding: parent.indicator.width + 4 }
                            }

                            RowLayout {
                                spacing: 8
                                Text { text: "Maximum speed:"; color: "#a0a0a0"; font.pixelSize: 13 }
                                TextField {
                                    id: speedLimitField
                                    implicitWidth: 90
                                    color: "#d0d0d0"; font.pixelSize: 13
                                    background: Rectangle { color: "#2d2d2d"; border.color: "#4a4a4a"; radius: 3 }

                                    // Populate once on load and whenever the settings are reset
                                    function syncFromModel() {
                                        var val = root.editGlobalSpeedLimitKBps > 0
                                            ? root.editGlobalSpeedLimitKBps
                                            : root.editSavedSpeedLimitKBps
                                        if (parseInt(text) !== val)
                                            text = val.toString()
                                    }
                                    Component.onCompleted: syncFromModel()
                                    Connections {
                                        target: root
                                        function onEditGlobalSpeedLimitKBpsChanged() { speedLimitField.syncFromModel() }
                                        function onEditSavedSpeedLimitKBpsChanged()  {
                                            // Only sync when the field isn't the one driving the change
                                            if (!speedLimitField.activeFocus)
                                                speedLimitField.syncFromModel()
                                        }
                                    }

                                    onTextEdited: {
                                        var v = parseInt(text)
                                        if (!isNaN(v) && v > 0) {
                                            if (globalLimitChk.checked)
                                                root.editGlobalSpeedLimitKBps = v
                                            root.editSavedSpeedLimitKBps = v
                                        }
                                    }
                                }
                                Text { text: "KB/s"; color: "#a0a0a0"; font.pixelSize: 13 }
                            }

                            CheckBox {
                                id: globalUploadLimitChk
                                text: "Enable global upload limit"
                                topPadding: 0; bottomPadding: 0
                                checked: root.editGlobalUploadLimitKBps > 0
                                onToggled: {
                                    if (!checked) {
                                        root.editGlobalUploadLimitKBps = 0
                                    } else if (root.editGlobalUploadLimitKBps <= 0) {
                                        root.editGlobalUploadLimitKBps = 500
                                    }
                                }
                                contentItem: Text { text: parent.text; color: "#d0d0d0"; font.pixelSize: 13; leftPadding: parent.indicator.width + 4 }
                            }

                            RowLayout {
                                spacing: 8
                                Text { text: "Maximum upload:"; color: "#a0a0a0"; font.pixelSize: 13 }
                                TextField {
                                    id: uploadLimitField
                                    implicitWidth: 90
                                    color: "#d0d0d0"; font.pixelSize: 13
                                    background: Rectangle { color: "#2d2d2d"; border.color: "#4a4a4a"; radius: 3 }

                                    function syncFromModel() {
                                        var val = root.editGlobalUploadLimitKBps > 0 ? root.editGlobalUploadLimitKBps : 500
                                        if (parseInt(text) !== val)
                                            text = val.toString()
                                    }
                                    Component.onCompleted: syncFromModel()
                                    Connections {
                                        target: root
                                        function onEditGlobalUploadLimitKBpsChanged() {
                                            if (!uploadLimitField.activeFocus)
                                                uploadLimitField.syncFromModel()
                                        }
                                    }
                                    onTextEdited: {
                                        var v = parseInt(text)
                                        if (!isNaN(v) && v > 0 && globalUploadLimitChk.checked)
                                            root.editGlobalUploadLimitKBps = v
                                    }
                                }
                                Text { text: "KB/s"; color: "#a0a0a0"; font.pixelSize: 13 }
                            }

                        CheckBox {
                            text: "Always turn on speed limiter on Stellar startup"
                            topPadding: 0; bottomPadding: 0
                            checked: root.editSpeedLimiterOnStartup
                            onCheckedChanged: root.editSpeedLimiterOnStartup = checked
                            contentItem: Text { text: parent.text; color: "#d0d0d0"; font.pixelSize: 13; leftPadding: parent.indicator.width + 4; wrapMode: Text.WordWrap; Layout.fillWidth: true }
                        }

                        Rectangle { Layout.fillWidth: true; height: 1; color: "#3a3a3a" }

                        // ── Speed Limiter Scheduler ───────────────────────────────────────────────
                        // Each rule: days[], onHour (1-12), onMinute (0-59), onAmPm, offHour,
                        // offMinute, offAmPm, downLimitKBps, upLimitKBps. Stored in editSpeedScheduleJson.
                        CheckBox {
                            text: "Enable speed limiter scheduler"
                            topPadding: 0; bottomPadding: 0
                            checked: root.editSpeedScheduleEnabled
                            onCheckedChanged: root.editSpeedScheduleEnabled = checked
                            contentItem: Text { text: parent.text; color: "#d0d0d0"; font.pixelSize: 13; leftPadding: parent.indicator.width + 4 }
                        }

                        ColumnLayout {
                            id: scheduleCol
                            visible: root.editSpeedScheduleEnabled
                            Layout.fillWidth: true
                            spacing: 8

                            property var rules: {
                                try { return JSON.parse(root.editSpeedScheduleJson || "[]") }
                                catch(e) { return [] }
                            }
                            function saveRules(arr) { root.editSpeedScheduleJson = JSON.stringify(arr) }
                            function blankRule() {
                                return { days: ["Mon","Tue","Wed","Thu","Fri"],
                                         onHour: "9", onMinute: "00", onAmPm: "AM",
                                         offHour: "5", offMinute: "00", offAmPm: "PM",
                                         downLimitKBps: 500, upLimitKBps: 500 }
                            }

                            // ── Per-rule cards ───────────────────────────────────────────────────
                            // Style matches GrabberScheduleDialog: #1b1b1b panels, #333 borders,
                            // #e0e0e0 text, 12px font, 26px tall inputs with small ▲▼ arrows.
                            Repeater {
                                model: scheduleCol.rules.length
                                delegate: Rectangle {
                                    id: ruleCard
                                    required property int index
                                    Layout.fillWidth: true
                                    implicitHeight: cardCol.implicitHeight + 18
                                    color: "#1b1b1b"
                                    radius: 3
                                    border.color: "#333333"

                                    property var rule: scheduleCol.rules[ruleCard.index] || scheduleCol.blankRule()

                                    // Clone this rule's field k to value v and persist to JSON
                                    function patch(k, v) {
                                        var arr = JSON.parse(root.editSpeedScheduleJson || "[]")
                                        var r = JSON.parse(JSON.stringify(arr[ruleCard.index]))
                                        r[k] = v
                                        arr[ruleCard.index] = r
                                        scheduleCol.saveRules(arr)
                                    }
                                    // Toggle a day in/out of this rule's days array
                                    function patchDay(day, on) {
                                        var arr = JSON.parse(root.editSpeedScheduleJson || "[]")
                                        var r = JSON.parse(JSON.stringify(arr[ruleCard.index]))
                                        var idx = r.days.indexOf(day)
                                        if (on && idx < 0) r.days.push(day)
                                        else if (!on && idx >= 0) r.days.splice(idx, 1)
                                        arr[ruleCard.index] = r
                                        scheduleCol.saveRules(arr)
                                    }

                                    ColumnLayout {
                                        id: cardCol
                                        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 10 }
                                        spacing: 8

                                        // ── Header ───────────────────────────────────────────────
                                        RowLayout {
                                            Layout.fillWidth: true
                                            Text {
                                                text: "Rule " + (ruleCard.index + 1)
                                                color: "#888888"; font.pixelSize: 11; font.bold: true
                                            }
                                            Item { Layout.fillWidth: true }
                                            Text {
                                                text: "Remove"
                                                color: removeHov.containsMouse ? "#ff7777" : "#aa3333"
                                                font.pixelSize: 11
                                                MouseArea {
                                                    id: removeHov
                                                    anchors.fill: parent
                                                    hoverEnabled: true
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: {
                                                        var arr = JSON.parse(root.editSpeedScheduleJson || "[]")
                                                        arr.splice(ruleCard.index, 1)
                                                        scheduleCol.saveRules(arr)
                                                    }
                                                }
                                            }
                                        }

                                        // ── Day pills — clickable, blue when active ───────────────
                                        RowLayout {
                                            spacing: 3
                                            Repeater {
                                                model: ["Mon","Tue","Wed","Thu","Fri","Sat","Sun"]
                                                delegate: Rectangle {
                                                    required property int index
                                                    required property var modelData
                                                    property bool on: ruleCard.rule.days && ruleCard.rule.days.indexOf(modelData) >= 0
                                                    width: 36; height: 22; radius: 2
                                                    color: on ? "#1a3a6a" : "#252525"
                                                    border.color: on ? "#4488dd" : "#3a3a3a"
                                                    Text {
                                                        anchors.centerIn: parent
                                                        text: modelData
                                                        color: on ? "#aaccff" : "#666666"
                                                        font.pixelSize: 11
                                                    }
                                                    MouseArea {
                                                        anchors.fill: parent
                                                        cursorShape: Qt.PointingHandCursor
                                                        onClicked: ruleCard.patchDay(modelData, !on)
                                                    }
                                                }
                                            }
                                        }

                                        // ── On → Off / Limit row ──────────────────────────────────
                                        // Uses the same compact input style as GrabberScheduleDialog:
                                        // TextInput in a 50×26 Rectangle, colon separator, DarkCombo for AM/PM.
                                        RowLayout {
                                            spacing: 4
                                            Layout.fillWidth: true

                                            Text { text: "On"; color: "#aaaaaa"; font.pixelSize: 12 }

                                            // On-hour input (1–12)
                                            Rectangle {
                                                width: 50; height: 26; radius: 2
                                                color: "#1b1b1b"; border.color: onHourFld.activeFocus ? "#4488dd" : "#3a3a3a"
                                                TextInput {
                                                    id: onHourFld
                                                    anchors { fill: parent; leftMargin: 6; rightMargin: 6 }
                                                    text: String(ruleCard.rule.onHour || "9")
                                                    color: "#e0e0e0"; font.pixelSize: 12
                                                    horizontalAlignment: TextInput.AlignHCenter
                                                    verticalAlignment: TextInput.AlignVCenter
                                                    validator: IntValidator { bottom: 1; top: 12 }
                                                    onTextEdited: ruleCard.patch("onHour", text)
                                                }
                                            }
                                            Text { text: ":"; color: "#aaaaaa"; font.pixelSize: 13 }
                                            // On-minute input (00–59), zero-padded
                                            Rectangle {
                                                width: 50; height: 26; radius: 2
                                                color: "#1b1b1b"; border.color: onMinFld.activeFocus ? "#4488dd" : "#3a3a3a"
                                                TextInput {
                                                    id: onMinFld
                                                    anchors { fill: parent; leftMargin: 6; rightMargin: 6 }
                                                    text: {
                                                        var m = parseInt(ruleCard.rule.onMinute)
                                                        return isNaN(m) ? "00" : (m < 10 ? "0" + m : String(m))
                                                    }
                                                    color: "#e0e0e0"; font.pixelSize: 12
                                                    horizontalAlignment: TextInput.AlignHCenter
                                                    verticalAlignment: TextInput.AlignVCenter
                                                    validator: IntValidator { bottom: 0; top: 59 }
                                                    onTextEdited: ruleCard.patch("onMinute", text)
                                                }
                                            }
                                            // AM/PM combo for On time — same style as DarkCombo
                                            ComboBox {
                                                model: ["AM","PM"]
                                                currentIndex: (ruleCard.rule.onAmPm || "AM") === "PM" ? 1 : 0
                                                implicitWidth: 62; implicitHeight: 26
                                                font.pixelSize: 12
                                                contentItem: Text {
                                                    leftPadding: 8; rightPadding: 20
                                                    text: parent.displayText; color: "#e0e0e0"; font: parent.font
                                                    verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight
                                                }
                                                background: Rectangle { color: "#1b1b1b"; border.color: "#3a3a3a"; radius: 2 }
                                                indicator: Text { x: parent.width-width-6; y: (parent.height-height)/2; text: "▼"; color: "#888"; font.pixelSize: 8 }
                                                popup.background: Rectangle { color: "#2a2a2a"; border.color: "#444"; radius: 3 }
                                                onCurrentIndexChanged: ruleCard.patch("onAmPm", currentIndex === 1 ? "PM" : "AM")
                                            }

                                            Text { text: "→"; color: "#555555"; font.pixelSize: 13; leftPadding: 2; rightPadding: 2 }
                                            Text { text: "Off"; color: "#aaaaaa"; font.pixelSize: 12 }

                                            // Off-hour input (1–12)
                                            Rectangle {
                                                width: 50; height: 26; radius: 2
                                                color: "#1b1b1b"; border.color: offHourFld.activeFocus ? "#4488dd" : "#3a3a3a"
                                                TextInput {
                                                    id: offHourFld
                                                    anchors { fill: parent; leftMargin: 6; rightMargin: 6 }
                                                    text: String(ruleCard.rule.offHour || "5")
                                                    color: "#e0e0e0"; font.pixelSize: 12
                                                    horizontalAlignment: TextInput.AlignHCenter
                                                    verticalAlignment: TextInput.AlignVCenter
                                                    validator: IntValidator { bottom: 1; top: 12 }
                                                    onTextEdited: ruleCard.patch("offHour", text)
                                                }
                                            }
                                            Text { text: ":"; color: "#aaaaaa"; font.pixelSize: 13 }
                                            // Off-minute input (00–59)
                                            Rectangle {
                                                width: 50; height: 26; radius: 2
                                                color: "#1b1b1b"; border.color: offMinFld.activeFocus ? "#4488dd" : "#3a3a3a"
                                                TextInput {
                                                    id: offMinFld
                                                    anchors { fill: parent; leftMargin: 6; rightMargin: 6 }
                                                    text: {
                                                        var m = parseInt(ruleCard.rule.offMinute)
                                                        return isNaN(m) ? "00" : (m < 10 ? "0" + m : String(m))
                                                    }
                                                    color: "#e0e0e0"; font.pixelSize: 12
                                                    horizontalAlignment: TextInput.AlignHCenter
                                                    verticalAlignment: TextInput.AlignVCenter
                                                    validator: IntValidator { bottom: 0; top: 59 }
                                                    onTextEdited: ruleCard.patch("offMinute", text)
                                                }
                                            }
                                            // AM/PM combo for Off time
                                            ComboBox {
                                                model: ["AM","PM"]
                                                currentIndex: (ruleCard.rule.offAmPm || "PM") === "PM" ? 1 : 0
                                                implicitWidth: 62; implicitHeight: 26
                                                font.pixelSize: 12
                                                contentItem: Text {
                                                    leftPadding: 8; rightPadding: 20
                                                    text: parent.displayText; color: "#e0e0e0"; font: parent.font
                                                    verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight
                                                }
                                                background: Rectangle { color: "#1b1b1b"; border.color: "#3a3a3a"; radius: 2 }
                                                indicator: Text { x: parent.width-width-6; y: (parent.height-height)/2; text: "▼"; color: "#888"; font.pixelSize: 8 }
                                                popup.background: Rectangle { color: "#2a2a2a"; border.color: "#444"; radius: 3 }
                                                onCurrentIndexChanged: ruleCard.patch("offAmPm", currentIndex === 1 ? "PM" : "AM")
                                            }

                                        }

                                        // ── Speed limit row ───────────────────────────────────────
                                        RowLayout {
                                            spacing: 6
                                            Text { text: "Download"; color: "#aaaaaa"; font.pixelSize: 12 }
                                            Rectangle {
                                                width: 70; height: 26; radius: 2
                                                color: "#1b1b1b"; border.color: downLimitFld.activeFocus ? "#4488dd" : "#3a3a3a"
                                                TextInput {
                                                    id: downLimitFld
                                                    anchors { fill: parent; leftMargin: 6; rightMargin: 6 }
                                                    text: String(ruleCard.rule.downLimitKBps || 500)
                                                    color: "#e0e0e0"; font.pixelSize: 12
                                                    horizontalAlignment: TextInput.AlignHCenter
                                                    verticalAlignment: TextInput.AlignVCenter
                                                    validator: IntValidator { bottom: 1; top: 999999 }
                                                    onTextEdited: {
                                                        var v = parseInt(text)
                                                        if (!isNaN(v) && v > 0) ruleCard.patch("downLimitKBps", v)
                                                    }
                                                }
                                            }
                                            Text { text: "KB/s"; color: "#aaaaaa"; font.pixelSize: 12 }
                                            Item { Layout.preferredWidth: 10 }
                                            Text { text: "Upload"; color: "#aaaaaa"; font.pixelSize: 12 }
                                            Rectangle {
                                                width: 70; height: 26; radius: 2
                                                color: "#1b1b1b"; border.color: upLimitFld.activeFocus ? "#4488dd" : "#3a3a3a"
                                                TextInput {
                                                    id: upLimitFld
                                                    anchors { fill: parent; leftMargin: 6; rightMargin: 6 }
                                                    text: String(ruleCard.rule.upLimitKBps || 500)
                                                    color: "#e0e0e0"; font.pixelSize: 12
                                                    horizontalAlignment: TextInput.AlignHCenter
                                                    verticalAlignment: TextInput.AlignVCenter
                                                    validator: IntValidator { bottom: 1; top: 999999 }
                                                    onTextEdited: {
                                                        var v = parseInt(text)
                                                        if (!isNaN(v) && v > 0) ruleCard.patch("upLimitKBps", v)
                                                    }
                                                }
                                            }
                                            Text { text: "KB/s"; color: "#aaaaaa"; font.pixelSize: 12 }
                                        }
                                    }
                                }
                            } // Repeater

                            // ── Add Rule button ──────────────────────────────────────────────────
                            DlgButton {
                                text: "+ Add Rule"
                                onClicked: {
                                    var arr = JSON.parse(root.editSpeedScheduleJson || "[]")
                                    arr.push(scheduleCol.blankRule())
                                    scheduleCol.saveRules(arr)
                                }
                            }

                            // Informational note — same blue-tinted style as GrabberScheduleDialog
                            Rectangle {
                                Layout.fillWidth: true
                                implicitHeight: scheduleNote.implicitHeight + 16
                                color: "#1a2030"; border.color: "#2a3050"; radius: 3
                                Text {
                                    id: scheduleNote
                                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: 8 }
                                    text: "Click a day pill to toggle it. Rules are evaluated every minute; first matching rule wins. Scheduled download and upload limits are cleared automatically when no rule is active."
                                    color: "#8899bb"; font.pixelSize: 11; wrapMode: Text.WordWrap
                                }
                            }
                        } // scheduleCol

                        Item { height: 12 }
                    }
                    } // ScrollView
                }

                // Notifications
                Item {
                    ColumnLayout {
                        anchors { fill: parent; margins: 12 }
                        spacing: 10

                        Text { text: "Notifications"; color: "#ffffff"; font.pixelSize: 16; font.bold: true }
                        Rectangle { Layout.fillWidth: true; height: 1; color: "#3a3a3a" }

                        CheckBox {
                            text: "Show notification when download completes"
                            topPadding: 0; bottomPadding: 0
                            checked: root.editShowCompletionNotification
                            onCheckedChanged: root.editShowCompletionNotification = checked
                            contentItem: Text { text: parent.text; color: "#d0d0d0"; font.pixelSize: 13; leftPadding: parent.indicator.width + 4 }
                        }
                        CheckBox {
                            text: "Show notification on download error"
                            topPadding: 0; bottomPadding: 0
                            checked: root.editShowErrorNotification
                            onCheckedChanged: root.editShowErrorNotification = checked
                            contentItem: Text { text: parent.text; color: "#d0d0d0"; font.pixelSize: 13; leftPadding: parent.indicator.width + 4 }
                        }

                        Item { Layout.fillHeight: true }
                    }
                }

                // General
                Item {
                    ScrollView {
                        anchors.fill: parent
                        contentWidth: availableWidth
                        clip: true

                    ColumnLayout {
                        width: parent.width
                        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
                        spacing: 10

                        Text { text: "General"; color: "#ffffff"; font.pixelSize: 16; font.bold: true }
                        Rectangle { Layout.fillWidth: true; height: 1; color: "#3a3a3a" }

                        CheckBox {
                            text: "Minimize to system tray"
                            topPadding: 0; bottomPadding: 0
                            checked: root.editMinimizeToTray
                            onCheckedChanged: root.editMinimizeToTray = checked
                            contentItem: Text { text: parent.text; color: "#d0d0d0"; font.pixelSize: 13; leftPadding: parent.indicator.width + 4 }
                        }
                        CheckBox {
                            text: "Close to system tray"
                            topPadding: 0; bottomPadding: 0
                            checked: root.editCloseToTray
                            onCheckedChanged: root.editCloseToTray = checked
                            contentItem: Text { text: parent.text; color: "#d0d0d0"; font.pixelSize: 13; leftPadding: parent.indicator.width + 4 }
                        }
                        CheckBox {
                            text: "Launch Stellar on startup"
                            topPadding: 0; bottomPadding: 0
                            checked: root.editLaunchOnStartup
                            onCheckedChanged: root.editLaunchOnStartup = checked
                            contentItem: Text { text: parent.text; color: "#d0d0d0"; font.pixelSize: 13; leftPadding: parent.indicator.width + 4 }
                        }
                        CheckBox {
                            text: "Show tips in bottom bar"
                            topPadding: 0; bottomPadding: 0
                            checked: root.editShowTips
                            onCheckedChanged: root.editShowTips = checked
                            contentItem: Text { text: parent.text; color: "#d0d0d0"; font.pixelSize: 13; leftPadding: parent.indicator.width + 4 }
                        }
                        CheckBox {
                            text: "Show finished download count in status bar"
                            topPadding: 0; bottomPadding: 0
                            checked: root.editShowFinishedCount
                            onCheckedChanged: root.editShowFinishedCount = checked
                            contentItem: Text { text: parent.text; color: "#d0d0d0"; font.pixelSize: 13; leftPadding: parent.indicator.width + 4 }
                        }

                        Rectangle { Layout.fillWidth: true; height: 1; color: "#3a3a3a" }
                        Text { text: "Speed Display"; color: "#ffffff"; font.pixelSize: 14; font.bold: true }

                        CheckBox {
                            text: "Show speed in tray icon tooltip"
                            topPadding: 0; bottomPadding: 0
                            checked: root.editSpeedInTrayTooltip
                            onCheckedChanged: root.editSpeedInTrayTooltip = checked
                            contentItem: Text { text: parent.text; color: "#d0d0d0"; font.pixelSize: 13; leftPadding: parent.indicator.width + 4 }
                        }
                        CheckBox {
                            text: "Show speed in title bar"
                            topPadding: 0; bottomPadding: 0
                            checked: root.editSpeedInTitleBar
                            onCheckedChanged: root.editSpeedInTitleBar = checked
                            contentItem: Text { text: parent.text; color: "#d0d0d0"; font.pixelSize: 13; leftPadding: parent.indicator.width + 4 }
                        }
                        CheckBox {
                            text: "Show speed in status bar"
                            topPadding: 0; bottomPadding: 0
                            checked: root.editSpeedInStatusBar
                            onCheckedChanged: root.editSpeedInStatusBar = checked
                            contentItem: Text { text: parent.text; color: "#d0d0d0"; font.pixelSize: 13; leftPadding: parent.indicator.width + 4 }
                        }
                        CheckBox {
                            text: "Show estimated online users in status bar"
                            topPadding: 0; bottomPadding: 0
                            checked: root.editEstimatedOnlineUsersInStatusBar
                            onCheckedChanged: root.editEstimatedOnlineUsersInStatusBar = checked
                            contentItem: Text {
                                text: parent.text
                                color: "#d0d0d0"
                                font.pixelSize: 13
                                leftPadding: parent.indicator.width + 4
                            }
                        }
                        Text {
                            text: "Uses DHT node-ID density to estimate global BitTorrent users. Confidence rises as more unique node IDs are observed; a trailing * in the status bar means the estimate is still low-confidence."
                            color: "#7a7a7a"
                            font.pixelSize: 11
                            wrapMode: Text.WordWrap
                            Layout.fillWidth: true
                            visible: root.editEstimatedOnlineUsersInStatusBar
                        }
                        CheckBox {
                            text: "Show ratio in status bar"
                            topPadding: 0; bottomPadding: 0
                            checked: root.editRatioInStatusBar
                            onCheckedChanged: root.editRatioInStatusBar = checked
                            contentItem: Text { text: parent.text; color: "#d0d0d0"; font.pixelSize: 13; leftPadding: parent.indicator.width + 4 }
                        }

                        Rectangle { Layout.fillWidth: true; height: 1; color: "#3a3a3a" }

                        Text { text: "Updates"; color: "#ffffff"; font.pixelSize: 14; font.bold: true }

                        CheckBox {
                            text: "Automatically check for updates"
                            topPadding: 0; bottomPadding: 0
                            checked: root.editAutoCheckUpdates
                            onCheckedChanged: root.editAutoCheckUpdates = checked
                            contentItem: Text { text: parent.text; color: "#d0d0d0"; font.pixelSize: 13; leftPadding: parent.indicator.width + 4 }
                        }

                        Rectangle { Layout.fillWidth: true; height: 1; color: "#3a3a3a" }

                        Text { text: "Clipboard Monitoring"; color: "#ffffff"; font.pixelSize: 14; font.bold: true }

                        CheckBox {
                            text: "Automatically start downloading URLs placed in the clipboard"
                            topPadding: 0; bottomPadding: 0
                            checked: root.editClipboardMonitorEnabled
                            onCheckedChanged: root.editClipboardMonitorEnabled = checked
                            contentItem: Text { text: parent.text; color: "#d0d0d0"; font.pixelSize: 13; leftPadding: parent.indicator.width + 4; wrapMode: Text.WordWrap; Layout.fillWidth: true }
                        }

                        Text {
                            text: "When a URL matching a monitored file type is copied to the clipboard, Stellar will ask if you want to download it. Only file types listed under Browser \u203a Automatically start downloading the following file types are picked up."
                            color: "#7a7a7a"; font.pixelSize: 11
                            wrapMode: Text.WordWrap
                            Layout.fillWidth: true
                            visible: root.editClipboardMonitorEnabled
                        }

                        Item { Layout.fillHeight: true }
                    }
                    } // ScrollView
                } // General

                // Media (video/audio downloader)
                Item {
                    ScrollView {
                        anchors.fill: parent
                        contentWidth: availableWidth
                        clip: true

                    ColumnLayout {
                        width: parent.width
                        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
                        spacing: 10

                        Text { text: "Video Downloader"; color: "#ffffff"; font.pixelSize: 16; font.bold: true }
                        Rectangle { Layout.fillWidth: true; height: 1; color: "#3a3a3a" }

                        Text {
                            Layout.fillWidth: true
                            text: "Stellar uses yt-dlp to download videos from YouTube, Vimeo, Twitter/X, Instagram and hundreds of other sites. When you paste a video URL into Add URL, a format picker will appear."
                            color: "#909090"; font.pixelSize: 12
                            wrapMode: Text.WordWrap
                        }

                        Rectangle { Layout.fillWidth: true; height: 1; color: "#2a2a2a" }

                        // ── Status indicator ──────────────────────────────────────────
                        Text { text: "Binary status"; color: "#c0c0c0"; font.pixelSize: 13; font.bold: true }

                        RowLayout {
                            spacing: 10

                            // Status dot
                            Rectangle {
                                width: 10; height: 10; radius: 5
                                color: App.ytdlpManager.available ? "#44cc44"
                                     : (App.ytdlpManager.downloading ? "#ddaa22" : "#cc4444")
                            }

                            Text {
                                text: App.ytdlpManager.statusText
                                color: "#c0c0c0"
                                font.pixelSize: 12
                                Layout.fillWidth: true
                                wrapMode: Text.WordWrap
                            }
                        }

                        // Download/update progress bar (shown during download)
                        Rectangle {
                            Layout.fillWidth: true
                            height: 8; radius: 4
                            color: "#2a2a2a"
                            visible: App.ytdlpManager.downloading

                            Rectangle {
                                width: parent.width * (App.ytdlpManager.downloadProgress / 100.0)
                                height: parent.height; radius: parent.radius
                                color: "#4488dd"
                            }
                        }

                        RowLayout {
                            spacing: 8
                            DlgButton {
                                text: App.ytdlpManager.available ? "Update yt-dlp" : "Download yt-dlp"
                                enabled: !App.ytdlpManager.downloading
                                onClicked: {
                                    if (App.ytdlpManager.available)
                                        App.ytdlpManager.selfUpdate()
                                    else
                                        App.downloadYtdlpBinary()
                                }
                            }
                            DlgButton {
                                text: "Cancel"
                                visible: App.ytdlpManager.downloading
                                onClicked: App.ytdlpManager.cancelDownload()
                            }
                            DlgButton {
                                text: "Re-check"
                                enabled: !App.ytdlpManager.downloading
                                onClicked: App.ytdlpManager.checkAvailability()
                            }
                        }

                        Rectangle { Layout.fillWidth: true; height: 1; color: "#2a2a2a" }

                        // ── ffmpeg status ─────────────────────────────────────────────
                        Text { text: "ffmpeg status"; color: "#c0c0c0"; font.pixelSize: 13; font.bold: true }

                        RowLayout {
                            spacing: 10
                            Rectangle {
                                width: 10; height: 10; radius: 5
                                color: App.ytdlpManager.ffmpegAvailable ? "#44cc44" : "#cc4444"
                            }
                            Text {
                                Layout.fillWidth: true
                                text: App.ytdlpManager.ffmpegAvailable
                                      ? ("ffmpeg found: " + App.ytdlpManager.ffmpegPath)
                                      : "ffmpeg not found — HD downloads will be limited to pre-muxed formats (max ~480p)"
                                color: App.ytdlpManager.ffmpegAvailable ? "#c0c0c0" : "#dd8844"
                                font.pixelSize: 12
                                wrapMode: Text.WordWrap
                            }
                        }

                        Text {
                            Layout.fillWidth: true
                            visible: App.ffmpegUpdateStatus.length > 0
                            text: App.ffmpegUpdateStatus
                            color: App.ffmpegUpdating ? "#9ab8ff" : "#9a9a9a"
                            font.pixelSize: 11
                            wrapMode: Text.WordWrap
                        }

                        RowLayout {
                            spacing: 8
                            DlgButton {
                                text: App.ffmpegUpdating ? "Updating FFmpeg..." : "Update FFmpeg"
                                enabled: !App.ffmpegUpdating
                                onClicked: App.updateFfmpegBinary()
                            }
                            DlgButton {
                                text: "Get ffmpeg (gyan.dev)"
                                visible: !App.ytdlpManager.ffmpegAvailable
                                onClicked: Qt.openUrlExternally("https://www.gyan.dev/ffmpeg/builds/")
                            }
                        }

                        // Info box explaining what to do
                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: ffmpegNote.height + 16
                            radius: 4
                            color: "#1a2030"
                            border.color: "#2a3050"
                            visible: !App.ytdlpManager.ffmpegAvailable

                            Text {
                                id: ffmpegNote
                                anchors { left: parent.left; right: parent.right; top: parent.top; leftMargin: 8; rightMargin: 8; topMargin: 8 }
                                text: "ffmpeg is required to merge separate video and audio streams into MP4/MKV. " +
                                      "Without it, YouTube downloads fall back to a single pre-muxed stream (usually WebM, max 480p).\n\n" +
                                      "To fix: download ffmpeg from gyan.dev/ffmpeg/builds (Essentials build), " +
                                      "extract ffmpeg.exe from the bin/ folder, and place it in the same folder as yt-dlp.exe. " +
                                      "Then click Re-check above."
                                color: "#8899bb"; font.pixelSize: 11
                                wrapMode: Text.WordWrap
                            }
                        }

                        DlgButton {
                            visible: false
                        }

                        Rectangle { Layout.fillWidth: true; height: 1; color: "#2a2a2a" }

                        // ── Custom binary path ────────────────────────────────────────
                        Text { text: "Custom binary path"; color: "#c0c0c0"; font.pixelSize: 13; font.bold: true }

                        Text {
                            Layout.fillWidth: true
                            text: "Leave blank to use the bundled binary (recommended). Set to the absolute path of your own yt-dlp executable if you want to use a specific version."
                            color: "#808080"; font.pixelSize: 11
                            wrapMode: Text.WordWrap
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 6

                            TextField {
                                id: ytdlpPathField
                                Layout.fillWidth: true
                                font.pixelSize:   12
                                color:            "#d0d0d0"
                                leftPadding:      8
                                rightPadding:     8
                                placeholderText:  "(auto - use bundled or system yt-dlp)"
                                placeholderTextColor: "#555555"
                                text: root.editYtdlpCustomBinaryPath
                                onTextChanged: root.editYtdlpCustomBinaryPath = text
                                background: Rectangle {
                                    color:        "#1b1b1b"
                                    border.color: ytdlpPathField.activeFocus ? "#4488dd" : "#3a3a3a"
                                    radius: 3
                                }
                            }

                            DlgButton {
                                text: "Browse…"
                                onClicked: ytdlpFileDlg.open()
                            }
                        }

                        Rectangle { Layout.fillWidth: true; height: 1; color: "#2a2a2a" }

                        // ── JavaScript runtime (EJS n-challenge solver) ───────────────
                        Text { text: "JavaScript runtime"; color: "#c0c0c0"; font.pixelSize: 13; font.bold: true }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            Rectangle {
                                width:  10; height: 10; radius: 5
                                color: App.ytdlpManager.jsRuntimeAvailable ? "#44cc44" : "#cc4444"
                            }
                            Text {
                                Layout.fillWidth: true
                                text: App.ytdlpManager.jsRuntimeAvailable
                                      ? (App.ytdlpManager.jsRuntimeName + " found: " + App.ytdlpManager.jsRuntimePath)
                                      : "No JS runtime found — YouTube n-challenge solving disabled"
                                color: App.ytdlpManager.jsRuntimeAvailable ? "#c0c0c0" : "#dd8844"
                                font.pixelSize: 12
                                elide: Text.ElideRight
                            }
                        }

                        // Info box shown when no runtime is detected
                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: jsRuntimeNote.height + 16
                            radius: 4
                            color: "#1a2030"
                            border.color: "#2a3050"
                            visible: !App.ytdlpManager.jsRuntimeAvailable

                            Text {
                                id: jsRuntimeNote
                                anchors { left: parent.left; right: parent.right; top: parent.top; leftMargin: 8; rightMargin: 8; topMargin: 8 }
                                text: "yt-dlp requires an external JavaScript runtime to solve YouTube's n-challenge (URL throttling). " +
                                      "Without it, YouTube downloads may fail or return only low-quality storyboard formats.\n\n" +
                                      "Install one of: Deno (deno.com), Node.js (nodejs.org), Bun (bun.sh), or QuickJS. " +
                                      "Place it in the same folder as yt-dlp.exe or add it to your system PATH, then click Re-check in the yt-dlp status section above."
                                color: "#8899bb"; font.pixelSize: 11
                                wrapMode: Text.WordWrap
                            }
                        }

                        Text {
                            Layout.fillWidth: true
                            text: "Override the auto-detected runtime path. Leave blank to use auto-detection (searches yt-dlp folder, app folder, and system PATH)."
                            color: "#808080"; font.pixelSize: 11
                            wrapMode: Text.WordWrap
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 6

                            TextField {
                                id: jsRuntimePathField
                                Layout.fillWidth: true
                                font.pixelSize:   12
                                color:            "#d0d0d0"
                                leftPadding:      8
                                rightPadding:     8
                                placeholderText:  "(auto-detect from PATH and yt-dlp folder)"
                                placeholderTextColor: "#555555"
                                text: root.editYtdlpJsRuntimePath
                                onTextChanged: root.editYtdlpJsRuntimePath = text
                                background: Rectangle {
                                    color:        "#1b1b1b"
                                    border.color: jsRuntimePathField.activeFocus ? "#4488dd" : "#3a3a3a"
                                    radius: 3
                                }
                            }

                            DlgButton {
                                text: "Browse…"
                                onClicked: jsRuntimeFileDlg.open()
                            }
                        }

                        Rectangle { Layout.fillWidth: true; height: 1; color: "#2a2a2a" }

                        // ── Auto-update option ────────────────────────────────────────
                        CheckBox {
                            id: ytdlpAutoUpdateCheck
                            text: "Automatically update yt-dlp at startup"
                            font.pixelSize: 12
                            topPadding: 0
                            bottomPadding: 0
                            checked: root.editYtdlpAutoUpdate
                            onCheckedChanged: root.editYtdlpAutoUpdate = checked
                            contentItem: Text {
                                text: parent.text
                                color: "#c0c0c0"
                                font: parent.font
                                leftPadding: parent.indicator.width + parent.spacing
                                verticalAlignment: Text.AlignVCenter
                            }
                        }

                        Text {
                            Layout.fillWidth: true
                            text: "When enabled, Stellar will run \"yt-dlp -U\" at startup to keep the binary up to date. Requires an active internet connection."
                            color: "#666666"; font.pixelSize: 11
                            wrapMode: Text.WordWrap
                        }

                        Item { height: 12 }
                    }
                    } // ScrollView
                } // Media

                // Torrents
                Item {
                    ScrollView {
                        anchors.fill: parent
                        contentWidth: availableWidth
                        clip: true

                    ColumnLayout {
                        width: parent.width
                        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
                        spacing: 10

                        Text { text: "Torrent Downloads"; color: "#ffffff"; font.pixelSize: 16; font.bold: true }
                        Rectangle { Layout.fillWidth: true; height: 1; color: "#3a3a3a" }

                        Text {
                            Layout.fillWidth: true
                            text: "These settings apply to .torrent files and magnet links."
                            color: "#909090"; font.pixelSize: 12
                            wrapMode: Text.WordWrap
                        }

                        GridLayout {
                            Layout.fillWidth: true
                            columns: 2
                            columnSpacing: 10
                            rowSpacing: 8

                            Text { text: "Listen port"; color: "#c0c0c0"; font.pixelSize: 12 }
                            TextField {
                                Layout.preferredWidth: 120
                                text: String(root.editTorrentListenPort)
                                validator: IntValidator { bottom: 1; top: 65535 }
                                color: "#d0d0d0"
                                background: Rectangle { color: "#1b1b1b"; border.color: parent.activeFocus ? "#4488dd" : "#3a3a3a"; radius: 3 }
                                onTextEdited: { var n = parseInt(text, 10); if (!isNaN(n)) root.editTorrentListenPort = n }
                            }

                            Text { text: "Global max connections"; color: "#c0c0c0"; font.pixelSize: 12 }
                            TextField {
                                Layout.preferredWidth: 120
                                text: String(root.editTorrentConnectionsLimit)
                                validator: IntValidator { bottom: 1; top: 100000 }
                                color: "#d0d0d0"
                                background: Rectangle { color: "#1b1b1b"; border.color: parent.activeFocus ? "#4488dd" : "#3a3a3a"; radius: 3 }
                                onTextEdited: { var n = parseInt(text, 10); if (!isNaN(n) && n >= 1) root.editTorrentConnectionsLimit = n }
                            }

                            Text { text: "Max connections per torrent"; color: "#c0c0c0"; font.pixelSize: 12 }
                            TextField {
                                Layout.preferredWidth: 120
                                text: String(root.editTorrentConnectionsLimitPerTorrent)
                                validator: IntValidator { bottom: 0; top: 100000 }
                                color: "#d0d0d0"
                                background: Rectangle { color: "#1b1b1b"; border.color: parent.activeFocus ? "#4488dd" : "#3a3a3a"; radius: 3 }
                                onTextEdited: { var n = parseInt(text, 10); if (!isNaN(n) && n >= 0) root.editTorrentConnectionsLimitPerTorrent = n }
                            }

                            Text { text: "Global max upload slots"; color: "#c0c0c0"; font.pixelSize: 12 }
                            TextField {
                                Layout.preferredWidth: 120
                                text: String(root.editTorrentUploadSlotsLimit)
                                validator: IntValidator { bottom: 0; top: 100000 }
                                color: "#d0d0d0"
                                background: Rectangle { color: "#1b1b1b"; border.color: parent.activeFocus ? "#4488dd" : "#3a3a3a"; radius: 3 }
                                onTextEdited: { var n = parseInt(text, 10); if (!isNaN(n) && n >= 0) root.editTorrentUploadSlotsLimit = n }
                            }

                            Text { text: "Max upload slots per torrent"; color: "#c0c0c0"; font.pixelSize: 12 }
                            TextField {
                                Layout.preferredWidth: 120
                                text: String(root.editTorrentUploadSlotsLimitPerTorrent)
                                validator: IntValidator { bottom: 0; top: 100000 }
                                color: "#d0d0d0"
                                background: Rectangle { color: "#1b1b1b"; border.color: parent.activeFocus ? "#4488dd" : "#3a3a3a"; radius: 3 }
                                onTextEdited: { var n = parseInt(text, 10); if (!isNaN(n) && n >= 0) root.editTorrentUploadSlotsLimitPerTorrent = n }
                            }

                            Item {}
                            Text { text: "0 = unlimited (per-torrent fields and global upload slots)"; color: "#666666"; font.pixelSize: 10 }

                            Text { text: "Protocol"; color: "#c0c0c0"; font.pixelSize: 12 }
                            ComboBox {
                                id: torrentProtocolCombo
                                Layout.preferredWidth: 160
                                model: ["TCP and μTP", "μTP only", "TCP only"]
                                currentIndex: root.editTorrentProtocol
                                font.pixelSize: 12
                                background: Rectangle { color: "#2d2d2d"; border.color: torrentProtocolCombo.activeFocus ? "#4488dd" : "#3a3a3a"; radius: 3 }
                                contentItem: Text {
                                    leftPadding: 8
                                    text: torrentProtocolCombo.displayText
                                    color: "#d0d0d0"; font: torrentProtocolCombo.font
                                    verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight
                                }
                                onActivated: root.editTorrentProtocol = currentIndex
                            }
                        }

                        CheckBox {
                            text: "Enable NAT-PMP"
                            topPadding: 0
                            bottomPadding: 0
                            checked: root.editTorrentEnableNatPmp
                            onCheckedChanged: root.editTorrentEnableNatPmp = checked
                            contentItem: Text { text: parent.text; color: "#d0d0d0"; font.pixelSize: 13; leftPadding: parent.indicator.width + 4 }
                        }

                        Rectangle { Layout.fillWidth: true; height: 1; color: "#2a2a2a" }

                        Text { text: "Port Test"; color: "#ffffff"; font.pixelSize: 14; font.bold: true }

                        Text {
                            Layout.fillWidth: true
                            text: "Test whether your current torrent listen port is reachable from the public internet. This helps confirm whether your VPN port forwarding, router forwarding, and firewall rules are actually allowing inbound torrent connections."
                            color: "#666666"
                            font.pixelSize: 11
                            wrapMode: Text.WordWrap
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 10

                            Button {
                                text: App.torrentPortTestInProgress ? "Testing..." : "Test Port"
                                enabled: !App.torrentPortTestInProgress
                                onClicked: App.testTorrentPort()
                            }

                            Text {
                                Layout.fillWidth: true
                                text: App.torrentPortTestMessage
                                color: {
                                    if (App.torrentPortTestStatus === "open")
                                        return "#7bd88f"
                                    if (App.torrentPortTestStatus === "closed")
                                        return "#ff8a80"
                                    if (App.torrentPortTestStatus === "testing")
                                        return "#d0d0d0"
                                    return "#a0a0a0"
                                }
                                font.pixelSize: 11
                                wrapMode: Text.WordWrap
                            }
                        }

                        Rectangle { Layout.fillWidth: true; height: 1; color: "#2a2a2a" }

                        Text { text: "Networking"; color: "#ffffff"; font.pixelSize: 14; font.bold: true }

                        CheckBox {
                            text: "Enable DHT"
                            topPadding: 0
                            bottomPadding: 0
                            checked: root.editTorrentEnableDht
                            onCheckedChanged: root.editTorrentEnableDht = checked
                            contentItem: Text { text: parent.text; color: "#d0d0d0"; font.pixelSize: 13; leftPadding: parent.indicator.width + 4 }
                        }
                        CheckBox {
                            text: "Enable local service discovery"
                            topPadding: 0
                            bottomPadding: 0
                            checked: root.editTorrentEnableLsd
                            onCheckedChanged: root.editTorrentEnableLsd = checked
                            contentItem: Text { text: parent.text; color: "#d0d0d0"; font.pixelSize: 13; leftPadding: parent.indicator.width + 4 }
                        }
                        CheckBox {
                            text: "Enable UPnP"
                            topPadding: 0
                            bottomPadding: 0
                            checked: root.editTorrentEnableUpnp
                            onCheckedChanged: root.editTorrentEnableUpnp = checked
                            contentItem: Text { text: parent.text; color: "#d0d0d0"; font.pixelSize: 13; leftPadding: parent.indicator.width + 4 }
                        }

                        Rectangle { Layout.fillWidth: true; height: 1; color: "#2a2a2a" }

                        Text { text: "Advanced"; color: "#ffffff"; font.pixelSize: 14; font.bold: true }

                        Text { text: "Custom bittorrent user agent"; color: "#c0c0c0"; font.pixelSize: 12 }
                        TextField {
                            Layout.fillWidth: true
                            text: root.editTorrentCustomUserAgent
                            placeholderText: "Default: Stellar/" + App.appVersion
                            onTextChanged: root.editTorrentCustomUserAgent = text
                            color: "#d0d0d0"
                            background: Rectangle { color: "#1b1b1b"; border.color: parent.activeFocus ? "#4488dd" : "#3a3a3a"; radius: 3 }
                        }

                        Text { text: "Bind to network adapter"; color: "#c0c0c0"; font.pixelSize: 12 }
                        ComboBox {
                            id: torrentAdapterCombo
                            Layout.fillWidth: true
                            model: root.torrentAdapterOptions
                            currentIndex: root.indexOfTorrentAdapter(root.editTorrentBindInterface)
                            font.pixelSize: 12
                            background: Rectangle { color: "#2d2d2d"; border.color: "#4a4a4a"; radius: 3 }
                            contentItem: Text {
                                leftPadding: 8
                                text: {
                                    var option = torrentAdapterCombo.currentIndex >= 0 && torrentAdapterCombo.currentIndex < root.torrentAdapterOptions.length
                                        ? root.torrentAdapterOptions[torrentAdapterCombo.currentIndex]
                                        : null
                                    return option ? option.name : "Default route"
                                }
                                color: "#d0d0d0"
                                font: torrentAdapterCombo.font
                                verticalAlignment: Text.AlignVCenter
                                elide: Text.ElideRight
                            }
                            delegate: ItemDelegate {
                                required property int index
                                required property var modelData
                                width: torrentAdapterCombo.width
                                highlighted: torrentAdapterCombo.highlightedIndex === index
                                contentItem: Column {
                                    spacing: 2
                                    Text {
                                        text: modelData.name || ""
                                        color: "#d0d0d0"
                                        font.pixelSize: 12
                                        elide: Text.ElideRight
                                    }
                                    Text {
                                        text: modelData.details || ""
                                        color: "#808080"
                                        font.pixelSize: 11
                                        elide: Text.ElideRight
                                    }
                                }
                                onClicked: torrentAdapterCombo.currentIndex = index
                            }
                            onActivated: {
                                var option = root.torrentAdapterOptions[currentIndex]
                                root.editTorrentBindInterface = option ? (option.id || "") : ""
                            }
                        }

                        Text {
                            Layout.fillWidth: true
                            text: root.editTorrentBindInterface.length > 0 ? "This adapter is locked for torrent traffic. If your VPN disconnects or the adapter goes away, Stellar stops using the default route and your torrents lose network access instead of leaking onto another connection." : "No adapter binding. Torrent traffic follows the system route."
                            color: root.editTorrentBindInterface.length > 0 ? "#ffffff" : "#666666"
                            font.pixelSize: 11
                            wrapMode: Text.WordWrap
                        }

                        Text {
                            Layout.fillWidth: true
                            text: root.torrentAdapterDetails(root.editTorrentBindInterface)
                            color: "#666666"
                            font.pixelSize: 11
                            wrapMode: Text.WordWrap
                            visible: text.length > 0
                        }

                        Text {
                            Layout.fillWidth: true
                            text: "Network adapter binding tells Stellar to send and receive torrent traffic only through the selected adapter. This is especially useful for VPN users because it prevents accidental traffic leaks when the VPN is not connected."
                            color: "#666666"
                            font.pixelSize: 11
                            wrapMode: Text.WordWrap
                        }

                        Rectangle { Layout.fillWidth: true; height: 1; color: "#2a2a2a" }

                        Text { text: "Torrent Security"; color: "#ffffff"; font.pixelSize: 14; font.bold: true }

                        Text {
                            Layout.fillWidth: true
                            text: "Manual peer bans apply immediately. Blocked user-agent substrings, blocked countries, and auto-ban options apply when you click Apply or OK."
                            color: "#666666"
                            font.pixelSize: 11
                            wrapMode: Text.WordWrap
                        }

                        Text { text: "Encryption Mode"; color: "#c0c0c0"; font.pixelSize: 12 }

                        ComboBox {
                            id: encryptionModeCombo
                            implicitWidth: 220
                            model: ["Prefer encryption", "Require encryption", "Allow encryption"]
                            // model index maps: 0=Prefer, 1=Require, 2=Allow — matches torrentEncryptionMode values
                            currentIndex: root.editTorrentEncryptionMode
                            onActivated: root.editTorrentEncryptionMode = currentIndex
                            contentItem: Text {
                                leftPadding: 8
                                text: encryptionModeCombo.displayText
                                color: "#d0d0d0"
                                font.pixelSize: 13
                                verticalAlignment: Text.AlignVCenter
                            }
                            background: Rectangle {
                                color: "#1b1b1b"
                                border.color: encryptionModeCombo.activeFocus ? "#4488dd" : "#3a3a3a"
                                radius: 3
                            }
                            indicator: Text {
                                x: encryptionModeCombo.width - width - 8
                                anchors.verticalCenter: parent.verticalCenter
                                text: "▾"
                                color: "#888888"
                                font.pixelSize: 10
                            }
                            popup: Popup {
                                y: encryptionModeCombo.height
                                width: encryptionModeCombo.width
                                padding: 0
                                background: Rectangle { color: "#252525"; border.color: "#3a3a3a"; radius: 3 }
                                contentItem: ListView {
                                    implicitHeight: contentHeight
                                    model: encryptionModeCombo.delegateModel
                                    currentIndex: encryptionModeCombo.highlightedIndex
                                }
                            }
                            delegate: ItemDelegate {
                                width: encryptionModeCombo.width
                                contentItem: Text {
                                    text: modelData
                                    color: "#d0d0d0"
                                    font.pixelSize: 13
                                    verticalAlignment: Text.AlignVCenter
                                }
                                background: Rectangle {
                                    color: highlighted ? "#1a3a6a" : "transparent"
                                }
                                highlighted: encryptionModeCombo.highlightedIndex === index
                            }
                        }

                        Text { text: "Blocked user agents"; color: "#c0c0c0"; font.pixelSize: 12 }
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 96
                            color: "#1b1b1b"
                            border.color: blockedPeerAgentsInput.activeFocus ? "#4488dd" : "#3a3a3a"
                            radius: 3
                            clip: true

                            ScrollView {
                                anchors.fill: parent
                                TextArea {
                                    id: blockedPeerAgentsInput
                                    text: root.editTorrentBlockedPeerUserAgents
                                    color: "#d0d0d0"
                                    placeholderText: "One substring per line, for example:\naria2"
                                    wrapMode: TextEdit.Wrap
                                    selectByMouse: true
                                    background: null
                                    onTextChanged: root.editTorrentBlockedPeerUserAgents = text
                                }
                            }
                        }

                        Text {
                            Layout.fillWidth: true
                            text: "One substring per line. If a peer client string contains any line above, Stellar auto-bans that peer until the matching line is removed and the settings are applied."
                            color: "#666666"
                            font.pixelSize: 11
                            wrapMode: Text.WordWrap
                        }

                        Text { text: "Manually ban peer"; color: "#c0c0c0"; font.pixelSize: 12 }
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            TextField {
                                Layout.fillWidth: true
                                text: root.manualBanPeerText
                                placeholderText: "IP address, for example 203.0.113.42"
                                color: "#d0d0d0"
                                background: Rectangle {
                                    color: "#1b1b1b"
                                    border.color: parent.activeFocus ? "#4488dd" : "#3a3a3a"
                                    radius: 3
                                }
                                onTextChanged: root.manualBanPeerText = text
                            }

                            DlgButton {
                                text: "Ban"
                                enabled: root.manualBanPeerText.trim().length > 0
                                onClicked: {
                                    if (App.banTorrentPeer("", root.manualBanPeerText.trim(), 0, "", "")) {
                                        root.manualBanPeerText = ""
                                    }
                                }
                            }
                        }

                        Text {
                            Layout.fillWidth: true
                            text: "Manual bans are permanent until you remove them from the banned peers list below."
                            color: "#666666"
                            font.pixelSize: 11
                            wrapMode: Text.WordWrap
                        }

                        Text { text: "Block peers by country"; color: "#c0c0c0"; font.pixelSize: 12 }
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            ComboBox {
                                id: blockedCountryCombo
                                Layout.fillWidth: true
                                model: root.torrentCountryOptions
                                textRole: "name"
                                valueRole: "code"
                                currentIndex: {
                                    for (var i = 0; i < root.torrentCountryOptions.length; ++i) {
                                        if ((root.torrentCountryOptions[i].code || "") === root.selectedTorrentCountryCode)
                                            return i
                                    }
                                    return root.torrentCountryOptions.length > 0 ? 0 : -1
                                }
                                onActivated: {
                                    var option = root.torrentCountryOptions[currentIndex]
                                    root.selectedTorrentCountryCode = option ? (option.code || "") : ""
                                }
                                background: Rectangle { color: "#2d2d2d"; border.color: "#4a4a4a"; radius: 3 }
                                contentItem: Text {
                                    leftPadding: 8
                                    text: {
                                        var option = blockedCountryCombo.currentIndex >= 0 && blockedCountryCombo.currentIndex < root.torrentCountryOptions.length
                                            ? root.torrentCountryOptions[blockedCountryCombo.currentIndex]
                                            : null
                                        return option ? ((option.code || "") + " - " + (option.name || "")) : ""
                                    }
                                    color: "#d0d0d0"
                                    verticalAlignment: Text.AlignVCenter
                                    elide: Text.ElideRight
                                }
                                popup: Popup {
                                    parent: Overlay.overlay
                                    y: blockedCountryCombo.mapToItem(Overlay.overlay, 0, blockedCountryCombo.height).y
                                    x: blockedCountryCombo.mapToItem(Overlay.overlay, 0, 0).x
                                    width: blockedCountryCombo.width
                                    padding: 0
                                    clip: true
                                    z: 10000
                                    implicitHeight: Math.min(contentItem.implicitHeight, 280)
                                    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutsideParent

                                    background: Rectangle {
                                        color: "#252525"
                                        border.color: "#3a3a3a"
                                        radius: 3
                                    }

                                    contentItem: ListView {
                                        clip: true
                                        implicitHeight: contentHeight
                                        model: blockedCountryCombo.popup.visible ? blockedCountryCombo.delegateModel : null
                                        currentIndex: blockedCountryCombo.highlightedIndex
                                        ScrollBar.vertical: ScrollBar { }
                                    }
                                }
                                delegate: ItemDelegate {
                                    required property int index
                                    required property var modelData
                                    width: blockedCountryCombo.width
                                    onClicked: blockedCountryCombo.currentIndex = index
                                    contentItem: Text {
                                        text: (modelData.code || "") + " - " + (modelData.name || "")
                                        color: "#d0d0d0"
                                        font.pixelSize: 12
                                        elide: Text.ElideRight
                                    }
                                }
                            }

                            DlgButton {
                                text: "Add"
                                enabled: root.selectedTorrentCountryCode.length === 2
                                onClicked: root.addBlockedTorrentCountry(root.selectedTorrentCountryCode)
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 4

                            Repeater {
                                model: root.editTorrentBlockedPeerCountries
                                delegate: Rectangle {
                                    required property string modelData
                                    Layout.fillWidth: true
                                    implicitHeight: 34
                                    radius: 3
                                    color: "#252525"
                                    border.color: "#3a3a3a"
                                    clip: true

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 10
                                        anchors.rightMargin: 8
                                        anchors.topMargin: 2
                                        anchors.bottomMargin: 4
                                        spacing: 8

                                        Image {
                                            source: "qrc:/app/qml/flags/" + String(modelData || "").toLowerCase() + ".svg"
                                            width: 18
                                            height: 13
                                            sourceSize.width: 18
                                            sourceSize.height: 13
                                            fillMode: Image.PreserveAspectFit
                                            smooth: true
                                        }
                                        Text {
                                            Layout.fillWidth: true
                                            text: modelData + " - " + root.torrentCountryName(modelData)
                                            color: "#d0d0d0"
                                            font.pixelSize: 12
                                            elide: Text.ElideRight
                                        }
                                        DlgButton {
                                            text: "Remove"
                                            Layout.alignment: Qt.AlignVCenter
                                            Layout.preferredHeight: 28
                                            onClicked: root.removeBlockedTorrentCountry(modelData)
                                        }
                                    }
                                }
                            }

                            Text {
                                visible: root.editTorrentBlockedPeerCountries.length === 0
                                text: "No blocked countries."
                                color: "#666666"
                                font.pixelSize: 11
                            }
                        }

                        CheckBox {
                            text: "Auto Ban Xunlei, QQ, Baidu, Xfplay, DLBT and Offline downloader"
                            topPadding: 0
                            bottomPadding: 0
                            checked: root.editTorrentAutoBanAbusivePeers
                            onCheckedChanged: root.editTorrentAutoBanAbusivePeers = checked
                            contentItem: Text {
                                text: parent.text
                                color: "#d0d0d0"
                                font.pixelSize: 13
                                leftPadding: parent.indicator.width + 4
                                wrapMode: Text.WordWrap
                            }
                        }

                        CheckBox {
                            text: "Auto Ban BitTorrent Media Player Peer"
                            topPadding: 0
                            bottomPadding: 0
                            checked: root.editTorrentAutoBanMediaPlayerPeers
                            onCheckedChanged: root.editTorrentAutoBanMediaPlayerPeers = checked
                            contentItem: Text {
                                text: parent.text
                                color: "#d0d0d0"
                                font.pixelSize: 13
                                leftPadding: parent.indicator.width + 4
                                wrapMode: Text.WordWrap
                            }
                        }

                        Text { text: "Manually banned peers"; color: "#c0c0c0"; font.pixelSize: 12 }
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 160
                            color: "#171717"
                            border.color: "#303030"
                            radius: 3
                            clip: true

                            ListView {
                                id: bannedPeersList
                                anchors.fill: parent
                                anchors.margins: 6
                                model: root.visibleTorrentBannedPeers
                                spacing: 4

                                delegate: Rectangle {
                                    required property var modelData
                                    width: ListView.view.width
                                    implicitHeight: 42
                                    radius: 3
                                    color: "#222222"
                                    border.color: "#343434"

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 10
                                        anchors.rightMargin: 8
                                        spacing: 8

                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: 2

                                            Text {
                                                text: modelData.endpoint || ""
                                                color: "#e0e0e0"
                                                font.pixelSize: 12
                                                font.bold: true
                                                elide: Text.ElideRight
                                                Layout.fillWidth: true
                                            }
                                            Text {
                                                text: (modelData.reason || "")
                                                      + ((modelData.countryCode || "").length > 0 ? (" • " + modelData.countryCode) : "")
                                                      + ((modelData.client || "").length > 0 ? (" • " + modelData.client) : "")
                                                color: "#8ea1b5"
                                                font.pixelSize: 11
                                                elide: Text.ElideRight
                                                Layout.fillWidth: true
                                            }
                                        }

                                        DlgButton {
                                            text: modelData.permanent ? "Unban" : "Active"
                                            enabled: !!modelData.permanent
                                            onClicked: {
                                                var endpoint = String(modelData.endpoint || "")
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
                                    text: "No banned peers"
                                    color: "#666666"
                                    font.pixelSize: 12
                                }
                            }
                        }

                        Rectangle { Layout.fillWidth: true; height: 1; color: "#2a2a2a" }

                        Text { text: "IP-to-City Database"; color: "#ffffff"; font.pixelSize: 14; font.bold: true }

                        GridLayout {
                            Layout.fillWidth: true
                            columns: 2
                            columnSpacing: 10
                            rowSpacing: 6

                            Text { text: "Version"; color: "#a0a0a0"; font.pixelSize: 11 }
                            Text {
                                Layout.fillWidth: true
                                text: root.ipToCityDbInfo.versionStatus || "Unknown"
                                color: "#d0d0d0"
                                font.pixelSize: 11
                                wrapMode: Text.WordWrap
                            }

                            Text { text: "Path"; color: "#a0a0a0"; font.pixelSize: 11 }
                            Text {
                                Layout.fillWidth: true
                                text: root.ipToCityDbInfo.path || "Not found"
                                color: "#d0d0d0"
                                font.pixelSize: 11
                                wrapMode: Text.WrapAnywhere
                            }

                            Text { text: "Size"; color: "#a0a0a0"; font.pixelSize: 11 }
                            Text {
                                text: root.formatBytes(root.ipToCityDbInfo.sizeBytes || 0)
                                color: "#d0d0d0"
                                font.pixelSize: 11
                            }

                            Text { text: "Entries"; color: "#a0a0a0"; font.pixelSize: 11 }
                            Text {
                                text: root.ipToCityDbInfo.entryCountFormatted || "Unknown"
                                color: "#d0d0d0"
                                font.pixelSize: 11
                            }

                            Text { text: "Last Modified"; color: "#a0a0a0"; font.pixelSize: 11 }
                            Text {
                                text: root.ipToCityDbInfo.lastModified || "Unknown"
                                color: "#d0d0d0"
                                font.pixelSize: 11
                            }

                            Text { text: "Status"; color: "#a0a0a0"; font.pixelSize: 11 }
                            Text {
                                text: App.ipToCityDbUpdateStatus.length > 0
                                    ? App.ipToCityDbUpdateStatus
                                    : (root.ipToCityDbInfo.loaded ? "Loaded" : "Available but not loaded")
                                color: App.ipToCityDbUpdateStatus.length > 0 ? "#cccccc" : "#8ab4f8"
                                font.pixelSize: 11
                                wrapMode: Text.WordWrap
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            DlgButton {
                                text: App.ipToCityDbUpdating ? "Downloading..." : "Update IP-to-City DB"
                                enabled: !App.ipToCityDbUpdating
                                onClicked: App.updateIpToCityDbFromCachedUrl()
                            }
                            DlgButton {
                                text: "Refresh Info"
                                onClicked: root.refreshIpToCityDbInfo()
                            }
                        }

                        Text {
                            Layout.fillWidth: true
                            text: App.ipToCityDbUpdateUrl && App.ipToCityDbUpdateUrl.length > 0
                                ? ("Source: " + App.ipToCityDbUpdateUrl)
                                : "Source URL not cached yet. Use Check for updates to cache IPtoCityDB from update.json."
                            color: "#666666"
                            font.pixelSize: 11
                            wrapMode: Text.WordWrap
                        }

                        Rectangle { Layout.fillWidth: true; height: 1; color: "#2a2a2a" }

                        Text { text: "Statistics"; color: "#ffffff"; font.pixelSize: 14; font.bold: true }

                        Text {
                            Layout.fillWidth: true
                            text: "Cumulative transfer totals across all torrents, including removed ones."
                            color: "#666666"
                            font.pixelSize: 11
                            wrapMode: Text.WordWrap
                        }

                        GridLayout {
                            id: torrentStatsGrid
                            Layout.fillWidth: true
                            columns: 2
                            columnSpacing: 16
                            rowSpacing: 6

                            property var stats: ({})

                            function refresh() {
                                stats = App.torrentAllTimeStats()
                            }

                            Component.onCompleted: refresh()

                            Timer {
                                interval: 2000
                                running: torrentStatsGrid.visible
                                repeat: true
                                onTriggered: torrentStatsGrid.refresh()
                            }

                            Text { text: "Total Downloaded"; color: "#8899aa"; font.pixelSize: 12 }
                            Text {
                                text: root.formatBytes(torrentStatsGrid.stats.downloadedBytes || 0)
                                color: "#c8c8c8"; font.pixelSize: 12
                            }

                            Text { text: "Total Uploaded"; color: "#8899aa"; font.pixelSize: 12 }
                            Text {
                                text: root.formatBytes(torrentStatsGrid.stats.uploadedBytes || 0)
                                color: "#c8c8c8"; font.pixelSize: 12
                            }

                            Text { text: "All-time Share Ratio"; color: "#8899aa"; font.pixelSize: 12 }
                            Text {
                                text: {
                                    var r = torrentStatsGrid.stats.ratio || 0
                                    return r.toFixed(3)
                                }
                                color: {
                                    var r = torrentStatsGrid.stats.ratio || 0
                                    if (r >= 1.0) return "#7bd88f"
                                    if (r >= 0.5) return "#f0c060"
                                    return "#ff8a80"
                                }
                                font.pixelSize: 12
                            }
                        }

                        Item { height: 12 }
                    }
                    } // ScrollView
                }

                // RSS
                Item {
                    ScrollView {
                        anchors.fill: parent
                        contentWidth: availableWidth
                        clip: true

                    ColumnLayout {
                        width: parent.width
                        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
                        spacing: 10

                        Text { text: "RSS"; color: "#ffffff"; font.pixelSize: 16; font.bold: true }
                        Rectangle { Layout.fillWidth: true; height: 1; color: "#3a3a3a" }

                        Text {
                            Layout.fillWidth: true
                            text: "Configure RSS feed fetching and automatic torrent downloading rules."
                            color: "#909090"; font.pixelSize: 12
                            wrapMode: Text.WordWrap
                        }

                        // ── Feed fetching ──────────────────────────────────────────────
                        Rectangle { Layout.fillWidth: true; height: 1; color: "#2a2a2a" }
                        Text { text: "Feed Fetching"; color: "#ffffff"; font.pixelSize: 14; font.bold: true }

                        CheckBox {
                            text: "Enable fetching RSS feeds"
                            topPadding: 0; bottomPadding: 0
                            checked: root.editRssEnabled
                            onCheckedChanged: root.editRssEnabled = checked
                            contentItem: Text { text: parent.text; color: "#d0d0d0"; font.pixelSize: 13; leftPadding: parent.indicator.width + 4 }
                        }

                        GridLayout {
                            Layout.fillWidth: true
                            columns: 3
                            columnSpacing: 10
                            rowSpacing: 8
                            enabled: root.editRssEnabled

                            Text { text: "Feeds refresh interval"; color: "#c0c0c0"; font.pixelSize: 12 }
                            TextField {
                                Layout.preferredWidth: 80
                                text: String(root.editRssRefreshIntervalMins)
                                validator: IntValidator { bottom: 1; top: 1440 }
                                color: "#d0d0d0"; font.pixelSize: 12
                                leftPadding: 6; rightPadding: 6; selectByMouse: true
                                background: Rectangle {
                                    color: "#1b1b1b"
                                    border.color: parent.activeFocus ? "#4488dd" : "#3a3a3a"; radius: 3
                                }
                                onTextChanged: {
                                    var n = parseInt(text, 10)
                                    if (!isNaN(n) && n >= 1) root.editRssRefreshIntervalMins = n
                                }
                            }
                            Text { text: "minutes"; color: "#666666"; font.pixelSize: 12 }

                            Text { text: "Same host request delay"; color: "#c0c0c0"; font.pixelSize: 12 }
                            TextField {
                                Layout.preferredWidth: 80
                                text: String(Math.round(root.editRssSameHostDelayMs / 1000))
                                validator: IntValidator { bottom: 0; top: 60 }
                                color: "#d0d0d0"; font.pixelSize: 12
                                leftPadding: 6; rightPadding: 6; selectByMouse: true
                                background: Rectangle {
                                    color: "#1b1b1b"
                                    border.color: parent.activeFocus ? "#4488dd" : "#3a3a3a"; radius: 3
                                }
                                onTextChanged: {
                                    var n = parseInt(text, 10)
                                    if (!isNaN(n) && n >= 0) root.editRssSameHostDelayMs = n * 1000
                                }
                            }
                            Text { text: "seconds"; color: "#666666"; font.pixelSize: 12 }

                            Text { text: "Maximum articles per feed"; color: "#c0c0c0"; font.pixelSize: 12 }
                            TextField {
                                Layout.preferredWidth: 80
                                text: String(root.editRssMaxArticlesPerFeed)
                                validator: IntValidator { bottom: 1; top: 10000 }
                                color: "#d0d0d0"; font.pixelSize: 12
                                leftPadding: 6; rightPadding: 6; selectByMouse: true
                                background: Rectangle {
                                    color: "#1b1b1b"
                                    border.color: parent.activeFocus ? "#4488dd" : "#3a3a3a"; radius: 3
                                }
                                onTextChanged: {
                                    var n = parseInt(text, 10)
                                    if (!isNaN(n) && n >= 1) root.editRssMaxArticlesPerFeed = n
                                }
                            }
                            Item {}
                        }

                        // ── Auto downloader ────────────────────────────────────────────
                        Rectangle { Layout.fillWidth: true; height: 1; color: "#2a2a2a" }
                        Text { text: "Torrent Auto Downloader"; color: "#ffffff"; font.pixelSize: 14; font.bold: true }

                        CheckBox {
                            text: "Enable auto downloading of RSS torrents"
                            topPadding: 0; bottomPadding: 0
                            checked: root.editRssAutoDownloadEnabled
                            onCheckedChanged: root.editRssAutoDownloadEnabled = checked
                            contentItem: Text { text: parent.text; color: "#d0d0d0"; font.pixelSize: 13; leftPadding: parent.indicator.width + 4 }
                        }

                        DlgButton {
                            text: "Edit Auto Downloading Rules..."
                            onClicked: {
                                rssDownloadRulesDialog.show()
                                rssDownloadRulesDialog.raise()
                                rssDownloadRulesDialog.requestActivate()
                            }
                        }

                        // ── Smart episode filter ───────────────────────────────────────
                        Rectangle { Layout.fillWidth: true; height: 1; color: "#2a2a2a" }
                        Text { text: "Smart Episode Filter"; color: "#ffffff"; font.pixelSize: 14; font.bold: true }

                        CheckBox {
                            text: "Download REPACK/PROPER episodes"
                            topPadding: 0; bottomPadding: 0
                            checked: root.editRssSmartFilterRepack
                            onCheckedChanged: root.editRssSmartFilterRepack = checked
                            contentItem: Text { text: parent.text; color: "#d0d0d0"; font.pixelSize: 13; leftPadding: parent.indicator.width + 4 }
                        }

                        Text { text: "Episode detection patterns (one per line):"; color: "#c0c0c0"; font.pixelSize: 12 }

                        Rectangle {
                            Layout.fillWidth: true
                            height: 110
                            color: "#1b1b1b"
                            border.color: rssFiltersArea.activeFocus ? "#4488dd" : "#3a3a3a"
                            radius: 3

                            ScrollView {
                                anchors.fill: parent
                                anchors.margins: 4
                                clip: true
                                ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

                                TextArea {
                                    id: rssFiltersArea
                                    font.pixelSize: 12
                                    font.family: "Consolas, monospace"
                                    color: "#d0d0d0"
                                    background: null
                                    wrapMode: TextEdit.NoWrap
                                    selectByMouse: true
                                    text: {
                                        try {
                                            var arr = JSON.parse(root.editRssSmartFiltersJson || "[]")
                                            return Array.isArray(arr) ? arr.join("\n") : ""
                                        } catch(e) { return "" }
                                    }
                                    onTextChanged: {
                                        var lines = text.split("\n").map(function(s) { return s.trim() }).filter(function(s) { return s.length > 0 })
                                        root.editRssSmartFiltersJson = JSON.stringify(lines)
                                    }
                                }
                            }
                        }

                        Text {
                            Layout.fillWidth: true
                            text: "These regular expressions are used to extract season/episode numbers for smart duplicate detection."
                            color: "#666666"; font.pixelSize: 11
                            wrapMode: Text.WordWrap
                        }

                        Item { Layout.fillHeight: true }
                    }
                    }
                }

                // Associations
                Item {
                    ScrollView {
                        anchors.fill: parent
                        contentWidth: availableWidth
                        clip: true

                    ColumnLayout {
                        width: parent.width
                        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
                        spacing: 10

                        Text { text: "Associations"; color: "#ffffff"; font.pixelSize: 16; font.bold: true }
                        Rectangle { Layout.fillWidth: true; height: 1; color: "#3a3a3a" }

                        Text {
                            Layout.fillWidth: true
                            text: "Make Stellar the default app for .torrent files and magnet links. These buttons apply the OS association directly for the current user."
                            color: "#909090"
                            font.pixelSize: 12
                            wrapMode: Text.WordWrap
                        }

                        Rectangle { Layout.fillWidth: true; height: 1; color: "#2a2a2a" }

                        GridLayout {
                            Layout.fillWidth: true
                            columns: 2
                            columnSpacing: 16
                            rowSpacing: 8

                            Text { text: ".torrent files"; color: "#c0c0c0"; font.pixelSize: 13 }
                            Text {
                                Layout.fillWidth: true
                                text: root.torrentAssociationDefault ? "Currently handled by Stellar" : "Stellar is not the current default"
                                color: root.torrentAssociationDefault ? "#7bd88f" : "#d8a65f"
                                font.pixelSize: 12
                                wrapMode: Text.WordWrap
                            }

                            Item { Layout.columnSpan: 2; Layout.fillWidth: true; implicitHeight: torrentAssocButtons.implicitHeight
                                RowLayout {
                                    id: torrentAssocButtons
                                    anchors.left: parent.left
                                    spacing: 8
                                    DlgButton {
                                        text: "Set .torrent Default"
                                        onClicked: root.showAssociationResult(App.setTorrentFileAssociationDefault(), "Stellar is now the default app for .torrent files.")
                                    }
                                    DlgButton {
                                        text: "Refresh Status"
                                        onClicked: {
                                            root.associationStatusText = ""
                                            root.refreshAssociationStatus()
                                        }
                                    }
                                }
                            }
                        }

                        Rectangle { Layout.fillWidth: true; height: 1; color: "#2a2a2a" }

                        GridLayout {
                            Layout.fillWidth: true
                            columns: 2
                            columnSpacing: 16
                            rowSpacing: 8

                            Text { text: "magnet: links"; color: "#c0c0c0"; font.pixelSize: 13 }
                            Text {
                                Layout.fillWidth: true
                                text: root.magnetAssociationDefault ? "Currently handled by Stellar" : "Stellar is not the current default"
                                color: root.magnetAssociationDefault ? "#7bd88f" : "#d8a65f"
                                font.pixelSize: 12
                                wrapMode: Text.WordWrap
                            }

                            Item { Layout.columnSpan: 2; Layout.fillWidth: true; implicitHeight: magnetAssocButtons.implicitHeight
                                RowLayout {
                                    id: magnetAssocButtons
                                    anchors.left: parent.left
                                    spacing: 8
                                    DlgButton {
                                        text: "Set Magnet Default"
                                        onClicked: root.showAssociationResult(App.setMagnetAssociationDefault(), "Stellar is now the default app for magnet links.")
                                    }
                                    DlgButton {
                                        text: "Refresh Status"
                                        onClicked: {
                                            root.associationStatusText = ""
                                            root.refreshAssociationStatus()
                                        }
                                    }
                                }
                            }
                        }

                        Rectangle { Layout.fillWidth: true; height: 1; color: "#2a2a2a" }

                        Text {
                            Layout.fillWidth: true
                            text: root.associationStatusText.length > 0
                                ? root.associationStatusText
                                : "If your desktop environment overrides the app-level association, refresh the status after the system finishes applying the change."
                            color: root.associationStatusText.length > 0 && root.associationStatusText.indexOf("Failed") === 0 ? "#ff8a80" : "#808080"
                            font.pixelSize: 11
                            wrapMode: Text.WordWrap
                        }

                        Item { Layout.fillHeight: true }
                    }
                    }
                }

                // About
                Item {
                    ScrollView {
                        anchors.fill: parent
                        contentWidth: availableWidth
                        clip: true

                    ColumnLayout {
                        width: parent.width
                        anchors { left: parent.left; right: parent.right; top: parent.top; leftMargin: 16; rightMargin: 16; topMargin: 16 }
                        spacing: 0

                        // ── Identity block ────────────────────────────────────────────
                        RowLayout {
                            spacing: 16
                            Layout.bottomMargin: 14

                            Image {
                                Layout.preferredWidth: 64
                                Layout.preferredHeight: 64
                                source: "icons/milky-way.png"
                                fillMode: Image.PreserveAspectFit
                                smooth: true
                            }

                            ColumnLayout {
                                spacing: 3
                                Layout.fillWidth: true

                                Text {
                                    text: "Stellar Download Manager"
                                    color: "#ffffff"; font.pixelSize: 15; font.bold: true
                                }

                                // Version + update status on the same line
                                RowLayout {
                                    spacing: 10

                                    Text {
                                        text: "Version " + App.appVersion
                                        color: "#4488dd"; font.pixelSize: 12
                                    }

                                    // Separator dot — only visible when update info is shown
                                    Text {
                                        text: "\u00B7"
                                        color: "#444444"; font.pixelSize: 12
                                        visible: App.updateAvailable
                                    }

                                    Text {
                                        text: App.updateAvailable
                                              ? ("Update available: " + App.updateVersion)
                                              : ""
                                        color: "#55bb77"; font.pixelSize: 12
                                        visible: App.updateAvailable
                                    }
                                }

                                // Check for updates + What's New — inline, understated
                                RowLayout {
                                    spacing: 10
                                    Layout.topMargin: 1

                                    Text {
                                        text: "Check for updates"
                                        color: "#555555"; font.pixelSize: 11; font.underline: true
                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: App.checkForUpdates(true)
                                            onEntered: parent.color = "#4488dd"
                                            onExited:  parent.color = "#555555"
                                        }
                                    }
                                    Text { text: "\u00B7"; color: "#333333"; font.pixelSize: 11 }
                                    Text {
                                        text: "What's New"
                                        color: "#555555"; font.pixelSize: 11; font.underline: true
                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: root.whatsNewRequested()
                                            onEntered: parent.color = "#4488dd"
                                            onExited:  parent.color = "#555555"
                                        }
                                    }
                                }
                            }
                        }

                        Rectangle { Layout.fillWidth: true; height: 1; color: "#2a2a2a"; Layout.bottomMargin: 12 }

                        // ── Build info ────────────────────────────────────────────────
                        GridLayout {
                            columns: 2; columnSpacing: 20; rowSpacing: 5
                            Layout.bottomMargin: 14

                            Text { text: "Build date";  color: "#606060"; font.pixelSize: 12 }
                            Text { text: App.buildTimeFormatted; color: "#b0b0b0"; font.pixelSize: 12 }
                            Text { text: "Qt version";  color: "#606060"; font.pixelSize: 12 }
                            Text { text: App.qtVersion; color: "#b0b0b0"; font.pixelSize: 12 }
                            Text { text: "Platform";    color: "#606060"; font.pixelSize: 12 }
                            Text {
                                text: {
                                    const os = Qt.platform.os
                                    if (os === "windows") return "Windows"
                                    if (os === "linux")   return "Linux"
                                    if (os === "osx")     return "macOS"
                                    return os.charAt(0).toUpperCase() + os.slice(1)
                                }
                                color: "#b0b0b0"; font.pixelSize: 12
                            }
                        }

                        Rectangle { Layout.fillWidth: true; height: 1; color: "#2a2a2a"; Layout.bottomMargin: 12 }

                        // ── License + Links ───────────────────────────────────────────
                        RowLayout {
                            spacing: 16
                            Layout.bottomMargin: 16

                            Text {
                                text: "Copyright \u00A9 2026 Ninka_"
                                color: "#707070"; font.pixelSize: 11
                            }
                            Text { text: "\u00B7"; color: "#3a3a3a"; font.pixelSize: 11 }
                            Text {
                                text: "GNU GPL v3.0"
                                color: "#4488dd"; font.pixelSize: 11
                                font.underline: true
                                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                    onClicked: Qt.openUrlExternally("https://www.gnu.org/licenses/gpl-3.0.html") }
                            }
                            Text { text: "\u00B7"; color: "#3a3a3a"; font.pixelSize: 11 }
                            Text {
                                text: "stellar.moe"
                                color: "#4488dd"; font.pixelSize: 11
                                font.underline: true
                                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                    onClicked: Qt.openUrlExternally("https://stellar.moe/") }
                            }
                            Text { text: "\u00B7"; color: "#3a3a3a"; font.pixelSize: 11 }
                            Text {
                                text: "GitHub"
                                color: "#4488dd"; font.pixelSize: 11
                                font.underline: true
                                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                    onClicked: Qt.openUrlExternally("https://github.com/Ninka-Rex/Stellar") }
                            }
                            Text { text: "\u00B7"; color: "#3a3a3a"; font.pixelSize: 11 }
                            Text {
                                text: "Releases"
                                color: "#4488dd"; font.pixelSize: 11
                                font.underline: true
                                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                    onClicked: Qt.openUrlExternally("https://github.com/Ninka-Rex/Stellar/releases") }
                            }
                        }

                        Text {
                            Layout.fillWidth: true
                            text: "Stellar is free software: you may redistribute and/or modify it under the terms of the GNU General Public License, version 3 or later."
                            color: "#808080"
                            font.pixelSize: 11
                            wrapMode: Text.WordWrap
                            Layout.bottomMargin: 8
                        }

                        Rectangle { Layout.fillWidth: true; height: 1; color: "#2a2a2a"; Layout.topMargin: 4; Layout.bottomMargin: 14 }

                        // ── Third-party credits ───────────────────────────────────────
                        // FFmpeg is invoked as an external executable (not linked into Stellar).
                        // Attribution is required by its LGPL-2.1+ / GPL-2+ license.
                        // Full license texts are in THIRD-PARTY-NOTICES.txt.
                        Text {
                            text: "Third-party software"
                            color: "#909090"; font.pixelSize: 12; font.bold: true
                            Layout.bottomMargin: 10
                        }

                        // FFmpeg
                        ColumnLayout {
                            spacing: 3
                            Layout.fillWidth: true
                            Layout.bottomMargin: 10

                            RowLayout {
                                spacing: 8
                                Text { text: "FFmpeg"; color: "#d0d0d0"; font.pixelSize: 12; font.bold: true }
                                Text { text: "LGPL-2.1+ / GPL-2+"; color: "#555555"; font.pixelSize: 10 }
                            }
                            Text {
                                Layout.fillWidth: true
                                text: "Copyright \u00A9 2000\u2013present the FFmpeg developers. " +
                                      "Used for merging video and audio streams. " +
                                      "FFmpeg is a trademark of Fabrice Bellard."
                                color: "#666666"; font.pixelSize: 11
                                wrapMode: Text.WordWrap
                            }
                            RowLayout {
                                spacing: 12
                                Text {
                                    text: "ffmpeg.org"
                                    color: "#4488dd"; font.pixelSize: 11; font.underline: true
                                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                        onClicked: Qt.openUrlExternally("https://ffmpeg.org/") }
                                }
                                Text { text: "\u00B7"; color: "#3a3a3a"; font.pixelSize: 11 }
                                Text {
                                    text: "Git source"
                                    color: "#4488dd"; font.pixelSize: 11; font.underline: true
                                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                        onClicked: Qt.openUrlExternally("https://git.ffmpeg.org/ffmpeg.git") }
                                }
                            }
                        }

                        Rectangle { Layout.fillWidth: true; height: 1; color: "#222222"; Layout.bottomMargin: 10 }

                        // libtorrent
                        ColumnLayout {
                            spacing: 3
                            Layout.fillWidth: true
                            Layout.bottomMargin: 10

                            RowLayout {
                                spacing: 8
                                Text { text: "libtorrent"; color: "#d0d0d0"; font.pixelSize: 12; font.bold: true }
                                Text { text: "BSD-3-Clause"; color: "#555555"; font.pixelSize: 10 }
                            }
                            Text {
                                Layout.fillWidth: true
                                text: "Copyright \u00A9 Arvid Norberg and contributors. " +
                                      "Used for BitTorrent protocol support."
                                color: "#666666"; font.pixelSize: 11
                                wrapMode: Text.WordWrap
                            }
                            RowLayout {
                                spacing: 12
                                Text {
                                    text: "libtorrent.org"
                                    color: "#4488dd"; font.pixelSize: 11; font.underline: true
                                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                        onClicked: Qt.openUrlExternally("https://libtorrent.org/") }
                                }
                                Text { text: "\u00B7"; color: "#3a3a3a"; font.pixelSize: 11 }
                                Text {
                                    text: "GitHub"
                                    color: "#4488dd"; font.pixelSize: 11; font.underline: true
                                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                        onClicked: Qt.openUrlExternally("https://github.com/arvidn/libtorrent") }
                                }
                            }
                        }

                        Rectangle { Layout.fillWidth: true; height: 1; color: "#222222"; Layout.bottomMargin: 10 }

                        // yt-dlp
                        ColumnLayout {
                            spacing: 3
                            Layout.fillWidth: true
                            Layout.bottomMargin: 10

                            RowLayout {
                                spacing: 8
                                Text { text: "yt-dlp"; color: "#d0d0d0"; font.pixelSize: 12; font.bold: true }
                                Text { text: "The Unlicense"; color: "#555555"; font.pixelSize: 10 }
                            }
                            Text {
                                Layout.fillWidth: true
                                text: "yt-dlp contributors (The Unlicense, public-domain dedication). " +
                                      "Used for video metadata extraction and media downloading features."
                                color: "#666666"; font.pixelSize: 11
                                wrapMode: Text.WordWrap
                            }
                            RowLayout {
                                spacing: 12
                                Text {
                                    text: "yt-dlp on GitHub"
                                    color: "#4488dd"; font.pixelSize: 11; font.underline: true
                                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                        onClicked: Qt.openUrlExternally("https://github.com/yt-dlp/yt-dlp") }
                                }
                                Text { text: "\u00B7"; color: "#3a3a3a"; font.pixelSize: 11 }
                                Text {
                                    text: "Unlicense"
                                    color: "#4488dd"; font.pixelSize: 11; font.underline: true
                                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                        onClicked: Qt.openUrlExternally("http://unlicense.org/") }
                                }
                            }
                        }

                        Rectangle { Layout.fillWidth: true; height: 1; color: "#222222"; Layout.bottomMargin: 10 }

                        // Qt Framework
                        ColumnLayout {
                            spacing: 3
                            Layout.fillWidth: true
                            Layout.bottomMargin: 14

                            RowLayout {
                                spacing: 8
                                Text { text: "Qt " + App.qtVersion; color: "#d0d0d0"; font.pixelSize: 12; font.bold: true }
                                Text { text: "LGPL-3"; color: "#555555"; font.pixelSize: 10 }
                            }
                            Text {
                                Layout.fillWidth: true
                                text: "Copyright \u00A9 The Qt Company Ltd. Used under the LGPL-3 with the Qt LGPL exception."
                                color: "#666666"; font.pixelSize: 11
                                wrapMode: Text.WordWrap
                            }
                            Text {
                                text: "code.qt.io"
                                color: "#4488dd"; font.pixelSize: 11; font.underline: true
                                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                    onClicked: Qt.openUrlExternally("https://code.qt.io/") }
                            }
                        }

                        Rectangle { Layout.fillWidth: true; height: 1; color: "#222222"; Layout.bottomMargin: 10 }

                        // DB-IP
                        ColumnLayout {
                            spacing: 3
                            Layout.fillWidth: true
                            Layout.bottomMargin: 10

                            RowLayout {
                                spacing: 8
                                Text { text: "DB-IP City Lite"; color: "#d0d0d0"; font.pixelSize: 12; font.bold: true }
                                Text { text: "CC BY 4.0"; color: "#555555"; font.pixelSize: 10 }
                            }
                            Text {
                                Layout.fillWidth: true
                                text: "Stellar uses the DB-IP City Lite geolocation database, distributed under Creative Commons Attribution 4.0."
                                color: "#666666"; font.pixelSize: 11
                                wrapMode: Text.WordWrap
                            }
                            Text {
                                text: "db-ip.com"
                                color: "#4488dd"; font.pixelSize: 11; font.underline: true
                                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                    onClicked: Qt.openUrlExternally("https://db-ip.com/") }
                            }
                        }

                        Text {
                            Layout.fillWidth: true
                            text: "Full license texts are in THIRD-PARTY-NOTICES.txt, included with this installation."
                            color: "#484848"; font.pixelSize: 11
                            wrapMode: Text.WordWrap
                            Layout.bottomMargin: 16
                        }

                        Rectangle { Layout.fillWidth: true; height: 1; color: "#222222"; Layout.bottomMargin: 12 }

                        Text {
                            text: "Thanks for using Stellar \uD83D\uDC99"
                            color: "#505050"; font.pixelSize: 11
                            Layout.bottomMargin: 12
                        }

                        Item { height: 4 }
                    }
                    } // ScrollView
                }
            }
        }

        // Bottom buttons
        Rectangle {
            Layout.fillWidth: true
            height: 48
            color: "#252525"

            Row {
                anchors { right: parent.right; verticalCenter: parent.verticalCenter; rightMargin: 12 }
                spacing: 8

                DlgButton {
                    text: "Apply"
                    primary: root.hasChanges
                    enabled: root.hasChanges
                    opacity: enabled ? 1.0 : 0.5
                    onClicked: if (root.hasChanges) root.applySettings()
                }

                DlgButton {
                    text: "OK"
                    primary: false
                    onClicked: { root.applySettings(); root.close() }
                }
            }
        }
    }
}
