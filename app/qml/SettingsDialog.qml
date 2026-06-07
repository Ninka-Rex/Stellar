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

    // Plain var properties - no live binding to App.settings so that
    // settingsChanged can detect when the user has made changes.
    property int    editMaxConcurrent:         0
    property int    editSegmentsPerDownload:   0
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
    property bool   editShowSwarmMapWhileFetchingMetadata: true
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
    property bool   editTorrentEnableLsd:      true
    property bool   editTorrentEnableUpnp:     true
    property bool   editTorrentEnableNatPmp:   true
    property bool   editTorrentEnablePex:      true
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

    component ThemedSpin: SpinBox {
        id: _tspin
        implicitWidth: 80
        contentItem: TextInput {
            text: _tspin.textFromValue(_tspin.value, _tspin.locale)
            color: ColorPalette.textPrimary
            font.pixelSize: 13 * App.fontScale
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            readOnly: !_tspin.editable
            validator: _tspin.validator
        }
        up.indicator: Rectangle {
            x: _tspin.width - width; y: 0
            width: 22; height: _tspin.height / 2
            color: _tspin.up.pressed ? ColorPalette.toolbarPressBg
                 : _tspin.up.hovered ? ColorPalette.toolbarHoverBg
                 : ColorPalette.panelBg
            Text { anchors.centerIn: parent; text: "+"; color: ColorPalette.textPrimary; font.pixelSize: 11 * App.fontScale }
        }
        down.indicator: Rectangle {
            x: _tspin.width - width; y: _tspin.height / 2
            width: 22; height: _tspin.height / 2
            color: _tspin.down.pressed ? ColorPalette.toolbarPressBg
                 : _tspin.down.hovered ? ColorPalette.toolbarHoverBg
                 : ColorPalette.panelBg
            Text { anchors.centerIn: parent; text: "–"; color: ColorPalette.textPrimary; font.pixelSize: 11 * App.fontScale }
        }
        background: Rectangle { color: ColorPalette.inputBg; border.color: ColorPalette.border; radius: 2 }
    }

    component ProxyRadioButton: RadioButton {
        id: _prb
        topPadding: 0
        bottomPadding: 0
        indicator: Rectangle {
            implicitWidth: 16; implicitHeight: 16
            x: _prb.leftPadding; y: parent.height / 2 - height / 2
            radius: 8
            color: ColorPalette.inputBg
            border.color: _prb.checked ? ColorPalette.accent : ColorPalette.border
            border.width: 1
            Rectangle { anchors.centerIn: parent; width: 8; height: 8; radius: 4; color: ColorPalette.accent; visible: _prb.checked }
        }
        contentItem: Text {
            text: parent.text
            color: ColorPalette.textPrimary
            font.pixelSize: 13 * App.fontScale
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

    Connections {
        target: App
        function onIpToCityDbInfoChanged() {
            root.ipToCityDbInfo = App.ipToCityDbInfo
        }
    }

    // Track whether anything has been changed
    readonly property bool settingsChanged:
        editMaxConcurrent         !== App.settings.maxConcurrent        ||
        editSegmentsPerDownload   !== App.settings.segmentsPerDownload  ||
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
        editShowSwarmMapWhileFetchingMetadata !== App.settings.showSwarmMapWhileFetchingMetadata ||
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
        editTorrentEnableLsd      !== App.settings.torrentEnableLsd      ||
        editTorrentEnableUpnp     !== App.settings.torrentEnableUpnp     ||
        editTorrentEnableNatPmp   !== App.settings.torrentEnableNatPmp   ||
        editTorrentEnablePex      !== App.settings.torrentEnablePex      ||
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
            var path = pathFromFileUrl(selectedFolder)
            root.editDefaultSavePath = path
        }
    }

    FolderDialog {
        id: tempFolderDlg
        currentFolder: root.editTemporaryDirectory.length > 0
                       ? fileUrlFromPath(root.editTemporaryDirectory) : ""
        onAccepted: {
            var path = pathFromFileUrl(selectedFolder)
            root.editTemporaryDirectory = path
        }
    }

    FolderDialog {
        id: torrentCustomSaveFolderDlg
        currentFolder: root.editTorrentCustomSavePath.length > 0
                       ? fileUrlFromPath(root.editTorrentCustomSavePath) : ""
        onAccepted: {
            var path = pathFromFileUrl(selectedFolder)
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
            var path = selectedFile.toString()
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
            var path = selectedFile.toString()
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
        onAccepted: App.exportAllData(root.pathFromFileUrl(selectedFile))
    }

    FileDialog {
        id: importBackupDlg
        title: qsTr("Import Stellar Backup")
        fileMode: FileDialog.OpenFile
        nameFilters: ["Stellar backup (*.stellarbackup)", "All files (*)"]
        onAccepted: App.importAllData(root.pathFromFileUrl(selectedFile), true)
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

    function applySettings() {
        // Always flush the current category form
        if (catPage.catEditId !== "") {
            var exts = catEditExts.text.split(/[\s,]+/).map(function(s) {
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
        App.settings.showSwarmMapWhileFetchingMetadata = editShowSwarmMapWhileFetchingMetadata
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
        App.settings.torrentEnableLsd       = editTorrentEnableLsd
        App.settings.torrentEnableUpnp      = editTorrentEnableUpnp
        App.settings.torrentEnableNatPmp    = editTorrentEnableNatPmp
        App.settings.torrentEnablePex       = editTorrentEnablePex
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
        editSegmentsPerDownload   = App.settings.segmentsPerDownload
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
        globalLimitChk.checked = editGlobalSpeedLimitEnabled
        editStartDownloadWhileFileInfo = App.settings.startDownloadWhileFileInfo
        editFillDescriptionMetadata = App.settings.fillDescriptionMetadata
        editShowSwarmMapWhileFetchingMetadata = App.settings.showSwarmMapWhileFetchingMetadata
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
        editTorrentEnableLsd      = App.settings.torrentEnableLsd
        editTorrentEnableUpnp     = App.settings.torrentEnableUpnp
        editTorrentEnableNatPmp   = App.settings.torrentEnableNatPmp
        editTorrentEnablePex      = App.settings.torrentEnablePex
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
                color: ColorPalette.panelBg

                ListView {
                    id: catList
                    anchors.fill: parent
                    anchors.topMargin: 8
                    model: [qsTr("Connection"), qsTr("Categories"), qsTr("Downloads"), qsTr("Browser"), qsTr("Speed Limiter"), qsTr("Notifications"), qsTr("General"), qsTr("Media"), qsTr("Torrents"), qsTr("RSS"), qsTr("Associations"), qsTr("Language"), qsTr("About")]
                    currentIndex: root.initialPage

                    delegate: Rectangle {
                        width: ListView.view.width
                        height: 28
                        color: catList.currentIndex === index ? ColorPalette.selectionBg : (ma.containsMouse ? ColorPalette.hoverBg : "transparent")

                        Text {
                            anchors { verticalCenter: parent.verticalCenter; left: parent.left; leftMargin: 16 }
                            text: modelData
                            color: catList.currentIndex === index ? ColorPalette.selectionText : ColorPalette.textPrimary
                            font.pixelSize: 12 * App.fontScale
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

                        Text { text: qsTr("Connection"); color: ColorPalette.textHeader; font.pixelSize: 16 * App.fontScale; font.bold: true }
                        Rectangle { Layout.fillWidth: true; height: 1; color: ColorPalette.border }

                        GridLayout {
                            columns: 3; columnSpacing: 10; rowSpacing: 10

                            Text { text: qsTr("Maximum simultaneous downloads:"); color: ColorPalette.textPrimary; font.pixelSize: 13 * App.fontScale }
                            ThemedSpin { from: 1; to: 16; value: root.editMaxConcurrent; onValueModified: root.editMaxConcurrent = value }
                            Item {}

                            Text { text: qsTr("Segments per download:"); color: ColorPalette.textPrimary; font.pixelSize: 13 * App.fontScale }
                            ThemedSpin { from: 1; to: 16; value: root.editSegmentsPerDownload; onValueModified: root.editSegmentsPerDownload = value }
                            Item {}

                            Text { text: qsTr("Connection timeout (seconds):"); color: ColorPalette.textPrimary; font.pixelSize: 13 * App.fontScale }
                            ThemedSpin { from: 5; to: 120; value: root.editConnectionTimeoutSecs; onValueModified: root.editConnectionTimeoutSecs = value }
                            Item {}

                            Text { text: qsTr("Retry failed downloads:"); color: ColorPalette.textPrimary; font.pixelSize: 13 * App.fontScale }
                            ThemedSpin { from: 0; to: 10; value: root.editMaxRetries; onValueModified: root.editMaxRetries = value }
                            Text { text: qsTr("times"); color: ColorPalette.textSecond; font.pixelSize: 13 * App.fontScale }
                        }

                        Rectangle { Layout.fillWidth: true; height: 1; color: ColorPalette.border }

                        Text {
                            text: qsTr("User Agent")
                            color: ColorPalette.textHeader; font.pixelSize: 14 * App.fontScale; font.bold: true
                        }

                        Text {
                            text: qsTr("When custom mode is off, Stellar uses its built-in User-Agent with the current version.")
                            color: ColorPalette.textPrimary; font.pixelSize: 13 * App.fontScale
                            wrapMode: Text.WordWrap
                            Layout.fillWidth: true
                        }

                        StyledCheckBox {
                            text: qsTr("Use custom user agent")
                            topPadding: 0; bottomPadding: 0
                            checked: root.editUseCustomUserAgent
                            onCheckedChanged: root.editUseCustomUserAgent = checked
                            contentItem: Text {
                                text: parent.text
                                color: ColorPalette.textPrimary; font.pixelSize: 13 * App.fontScale
                                leftPadding: parent.indicator.width + 4
                            }
                        }

                        TextField {
                            Layout.fillWidth: true
                            text: root.displayedUserAgent
                            readOnly: !root.editUseCustomUserAgent
                            selectByMouse: true
                            onTextEdited: root.editCustomUserAgent = text
                            color: root.editUseCustomUserAgent ? ColorPalette.textPrimary : "#7a7a7a"
                            font.pixelSize: 13 * App.fontScale
                            background: Rectangle {
                                color: root.editUseCustomUserAgent ? ColorPalette.dividerBg : ColorPalette.panelBg
                                border.color: root.editUseCustomUserAgent ? "#4a4a4a" : ColorPalette.border
                                radius: 3
                            }
                        }

                        Text {
                            text: root.editUseCustomUserAgent
                                  ? qsTr("This value will be sent exactly as entered.")
                                  : qsTr("Built-in default shown above. Enable the checkbox to edit and override it.")
                            color: "#555"; font.pixelSize: 10 * App.fontScale
                            wrapMode: Text.WordWrap
                            Layout.fillWidth: true
                        }

                        Rectangle { Layout.fillWidth: true; height: 1; color: ColorPalette.border; Layout.topMargin: 4 }

                        Text {
                            text: qsTr("Proxy")
                            color: ColorPalette.textHeader; font.pixelSize: 14 * App.fontScale; font.bold: true
                        }

                        // Type selector
                        ColumnLayout {
                            spacing: 6

                            ProxyRadioButton {
                                id: proxyNoneRadio
                                text: qsTr("No proxy")
                                checked: root.editProxyType === 0
                                onClicked: root.editProxyType = 0
                            }
                            ProxyRadioButton {
                                text: qsTr("Use system proxy")
                                checked: root.editProxyType === 1
                                onClicked: root.editProxyType = 1
                            }
                            ProxyRadioButton {
                                text: qsTr("HTTP / HTTPS proxy")
                                checked: root.editProxyType === 2
                                onClicked: root.editProxyType = 2
                            }
                            ProxyRadioButton {
                                text: qsTr("SOCKS5 proxy")
                                checked: root.editProxyType === 3
                                onClicked: root.editProxyType = 3
                            }
                        }

                        // Host / port / auth - only shown for custom proxy types
                        ColumnLayout {
                            visible: root.editProxyType === 2 || root.editProxyType === 3
                            spacing: 8
                            Layout.fillWidth: true

                            // Host + port row
                            RowLayout {
                                spacing: 8
                                Layout.fillWidth: true

                                Text { text: qsTr("Host:"); color: ColorPalette.textPrimary; font.pixelSize: 13 * App.fontScale }
                                TextField {
                                    Layout.fillWidth: true
                                    text: root.editProxyHost
                                    selectByMouse: true
                                    font.pixelSize: 13 * App.fontScale
                                    onTextEdited: root.editProxyHost = text
                                    background: Rectangle {
                                        color: ColorPalette.dividerBg; border.color: parent.activeFocus ? "#4488dd" : "#4a4a4a"; radius: 3
                                    }
                                    color: ColorPalette.textPrimary
                                }
                                Text { text: qsTr("Port:"); color: ColorPalette.textPrimary; font.pixelSize: 13 * App.fontScale }
                                TextField {
                                    implicitWidth: 120
                                    text: root.editProxyPort.toString()
                                    selectByMouse: true
                                    font.pixelSize: 13 * App.fontScale
                                    inputMethodHints: Qt.ImhDigitsOnly
                                    validator: IntValidator { bottom: 1; top: 65535 }
                                    onTextEdited: {
                                        var v = parseInt(text)
                                        if (!isNaN(v) && v >= 1 && v <= 65535)
                                            root.editProxyPort = v
                                    }
                                    background: Rectangle {
                                        color: ColorPalette.dividerBg; border.color: parent.activeFocus ? "#4488dd" : "#4a4a4a"; radius: 3
                                    }
                                    color: ColorPalette.textPrimary
                                }
                            }

                            // Auth (optional)
                            GridLayout {
                                columns: 2; columnSpacing: 8; rowSpacing: 6
                                Layout.fillWidth: true

                                Text { text: qsTr("Username:"); color: ColorPalette.textPrimary; font.pixelSize: 13 * App.fontScale }
                                TextField {
                                    Layout.fillWidth: true
                                    placeholderText: qsTr("Optional")
                                    text: root.editProxyUsername
                                    selectByMouse: true
                                    font.pixelSize: 13 * App.fontScale
                                    onTextEdited: root.editProxyUsername = text
                                    background: Rectangle {
                                        color: ColorPalette.dividerBg; border.color: parent.activeFocus ? "#4488dd" : "#4a4a4a"; radius: 3
                                    }
                                    color: ColorPalette.textPrimary
                                }

                                Text { text: qsTr("Password:"); color: ColorPalette.textPrimary; font.pixelSize: 13 * App.fontScale }
                                TextField {
                                    Layout.fillWidth: true
                                    placeholderText: qsTr("Optional")
                                    text: root.editProxyPassword
                                    echoMode: TextInput.Password
                                    selectByMouse: true
                                    font.pixelSize: 13 * App.fontScale
                                    onTextEdited: root.editProxyPassword = text
                                    background: Rectangle {
                                        color: ColorPalette.dividerBg; border.color: parent.activeFocus ? "#4488dd" : "#4a4a4a"; radius: 3
                                    }
                                    color: ColorPalette.textPrimary
                                }
                            }

                            Text {
                                text: qsTr("All downloads, video downloads, update checks, and torrent peer/tracker connections are routed through this proxy.")
                                color: "#555"; font.pixelSize: 10 * App.fontScale
                                wrapMode: Text.WordWrap
                                Layout.fillWidth: true
                            }
                        }

                        Text {
                            visible: root.editProxyType === 1
                            text: qsTr("Stellar will use the proxy configured in your operating system network settings.")
                            color: "#555"; font.pixelSize: 10 * App.fontScale
                            wrapMode: Text.WordWrap
                            Layout.fillWidth: true
                        }

                        // ?? Proxy test ????????????????????????????????????????
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
                                text: proxyTestRow._testing ? qsTr("Testing.") : qsTr("Test Proxy")
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
                                font.pixelSize: 11 * App.fontScale
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
                            var path = pathFromFileUrl(selectedFolder).replace(/\\/g, "/")
                            catEditPath.text = path
                        }
                    }

                    ColumnLayout {
                        anchors { fill: parent; margins: 12 }
                        spacing: 10

                        Text { text: qsTr("Categories"); color: ColorPalette.textHeader; font.pixelSize: 16 * App.fontScale; font.bold: true }
                        Rectangle { Layout.fillWidth: true; height: 1; color: ColorPalette.border }

                        RowLayout {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            spacing: 12

                            // ?? Left: category list ??????????????????????????
                            ColumnLayout {
                                Layout.fillHeight: true
                                Layout.preferredWidth: 170
                                spacing: 4

                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    color: ColorPalette.panelBg
                                    border.color: ColorPalette.border
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
                                            catEditExts.text  = (d.extensions || []).join(" ").toUpperCase()
                                            catEditSites.text = (d.sitePatterns || []).join(" ")
                                            catEditPath.text  = (d.savePath || "").replace(/\\/g, "/")
                                            catPage.catEditBuiltIn = !!d.builtIn
                                            catPage.catEditId = d.id || ""
                                            root.loadingCategory = false
                                        }

                                        onCurrentIndexChanged: {
                                            // Always save the previous category before switching
                                            if (catPage.catEditId !== "") {
                                                var exts = catEditExts.text.split(/[\s,]+/).map(function(s) {
                                                    return s.trim().replace(/^\./, "").toLowerCase()
                                                }).filter(function(s) { return s.length > 0 })
                                                var sites = catEditSites.text.split(/\s+/).filter(function(s) { return s.length > 0 })
                                                App.categoryModel.updateCategory(catPage.catEditId, catEditName.text.trim(), exts, sites, catEditPath.text.trim())
                                            }

                                            var d = App.categoryModel.categoryData(currentIndex)
                                            if (!d || !d.id) return
                                            root.loadingCategory = true
                                            catEditName.text  = d.label || ""
                                            catEditExts.text  = (d.extensions || []).join(" ").toUpperCase()
                                            catEditSites.text = (d.sitePatterns || []).join(" ")
                                            catEditPath.text  = (d.savePath || "").replace(/\\/g, "/")
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
                                                   ? ColorPalette.selectionBg
                                                   : (catItemMa.containsMouse ? ColorPalette.hoverBg : "transparent")

                                            Text {
                                                anchors { verticalCenter: parent.verticalCenter; left: parent.left; leftMargin: 10; right: parent.right; rightMargin: 6 }
                                                text: categoryLabel
                                                color: catEditList.currentIndex === index ? ColorPalette.selectionText : ColorPalette.textPrimary
                                                font.pixelSize: 12 * App.fontScale
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
                                        color: addCatMa.containsMouse ? ColorPalette.hoverBg : ColorPalette.panelBg
                                        border.color: ColorPalette.border
                                        Text {
                                            anchors.centerIn: parent
                                            text: "+"
                                            color: ColorPalette.textPrimary
                                            font.pixelSize: 16 * App.fontScale
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
                                        color: delCatMa.containsMouse && enabled ? ColorPalette.hoverBg : ColorPalette.panelBg
                                        border.color: ColorPalette.border
                                        opacity: enabled ? 1.0 : 0.4
                                        Text {
                                            anchors.centerIn: parent
                                            text: "−"
                                            color: ColorPalette.textPrimary
                                            font.pixelSize: 18 * App.fontScale
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

                            // ?? Right: edit form ?????????????????????????????
                            ColumnLayout {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                spacing: 12

                                // Name
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 4
                                    Text { text: qsTr("Name"); color: "#909090"; font.pixelSize: 11 * App.fontScale }
                                    TextField {
                                        id: catEditName
                                        Layout.fillWidth: true
                                        implicitHeight: 30
                                        font.pixelSize: 12 * App.fontScale; color: ColorPalette.textPrimary
                                        background: Rectangle { color: ColorPalette.dividerBg; border.color: "#4a4a4a"; radius: 3 }
                                        leftPadding: 8
                                        onTextChanged: if (!root.loadingCategory) root.catDirty = true
                                    }
                                }

                                // File types
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 4
                                    Text { text: qsTr("Space or comma-separated. Case-insensitive."); color: "#909090"; font.pixelSize: 11 * App.fontScale }
                                    ScrollView {
                                        Layout.fillWidth: true
                                        implicitHeight: 52
                                        clip: true
                                        background: Rectangle { color: ColorPalette.dividerBg; border.color: "#4a4a4a"; radius: 3 }
                                        TextArea {
                                            id: catEditExts
                                            wrapMode: TextArea.Wrap
                                            font.pixelSize: 12 * App.fontScale; color: ColorPalette.textPrimary
                                            background: null
                                            leftPadding: 6; rightPadding: 6; bottomPadding: 6; topPadding: 8
                                            placeholderText: "MP4 MKV AVI MOV"
                                            onTextChanged: if (!root.loadingCategory) root.catDirty = true
                                        }
                                    }
                                    // Warn when a category extension isn't in the browser auto-download list
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
                                                ? qsTr("✕ Not in browser auto-download list: %1").arg(missing.join(", "))
                                                : ""
                                        }
                                    }
                                }

                                // Sites
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 4
                                    Text { text: qsTr("Auto-assign from sites  (space-separated, * wildcard)"); color: "#909090"; font.pixelSize: 11 * App.fontScale }
                                    TextField {
                                        id: catEditSites
                                        Layout.fillWidth: true
                                        implicitHeight: 30
                                        placeholderText: "*.youtube.com *.vimeo.com"
                                        placeholderTextColor: "#888888"
                                        font.pixelSize: 12 * App.fontScale; color: ColorPalette.textPrimary
                                        background: Rectangle { color: ColorPalette.inputBg; border.color: parent.activeFocus ? "#4488dd" : ColorPalette.border; radius: 3 }
                                        leftPadding: 8
                                        onTextChanged: if (!root.loadingCategory) root.catDirty = true
                                    }
                                    Text {
                                        text: qsTr("Downloads from matching sites will automatically go into this category.")
                                        color: "#555"; font.pixelSize: 10 * App.fontScale
                                        wrapMode: Text.WordWrap
                                        Layout.fillWidth: true
                                    }
                                }

                                // Save to
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 4
                                    Text { text: qsTr("Save to folder"); color: ColorPalette.textSecond; font.pixelSize: 11 * App.fontScale }
                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 6
                                        TextField {
                                            id: catEditPath
                                            Layout.fillWidth: true
                                            implicitHeight: 30
                                            font.pixelSize: 12 * App.fontScale; color: ColorPalette.textPrimary
                                            background: Rectangle { color: ColorPalette.dividerBg; border.color: ColorPalette.border; radius: 3 }
                                            leftPadding: 8
                                            onTextChanged: if (!root.loadingCategory) root.catDirty = true
                                        }
                                        Rectangle {
                                            width: 32; height: 30; radius: 3
                                            color: browseMa.containsMouse ? ColorPalette.hoverBg : ColorPalette.panelBg
                                            border.color: ColorPalette.border
                                            Text { anchors.centerIn: parent; text: "…"; color: ColorPalette.textPrimary; font.pixelSize: 13 * App.fontScale }
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

                        Text { text: qsTr("Downloads"); color: ColorPalette.textHeader; font.pixelSize: 16 * App.fontScale; font.bold: true }
                        Rectangle { Layout.fillWidth: true; height: 1; color: ColorPalette.border }

                        Text { text: qsTr("Default save folder:"); color: ColorPalette.textPrimary; font.pixelSize: 13 * App.fontScale }
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8
                            TextField {
                                Layout.fillWidth: true
                                text: root.editDefaultSavePath
                                onTextChanged: root.editDefaultSavePath = text
                                color: ColorPalette.textPrimary; font.pixelSize: 13 * App.fontScale
                                background: Rectangle { color: ColorPalette.dividerBg; border.color: "#4a4a4a"; radius: 3 }
                            }
                            DlgButton {
                                text: qsTr("Browse…")
                                onClicked: saveFolderDlg.open()
                            }
                        }

                        Rectangle { Layout.fillWidth: true; height: 1; color: ColorPalette.border }

                        Text { text: qsTr("Custom save folder for torrents:"); color: ColorPalette.textPrimary; font.pixelSize: 13 * App.fontScale }
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8
                            TextField {
                                Layout.fillWidth: true
                                text: root.editTorrentCustomSavePath
                                onTextChanged: root.editTorrentCustomSavePath = text
                                color: ColorPalette.textPrimary; font.pixelSize: 13 * App.fontScale
                                background: Rectangle { color: ColorPalette.dividerBg; border.color: "#4a4a4a"; radius: 3 }
                            }
                            DlgButton {
                                text: qsTr("Browse…")
                                onClicked: torrentCustomSaveFolderDlg.open()
                            }
                        }

                        Text {
                            text: qsTr("This is the remembered custom torrent folder used when the torrent metadata dialog is set to use a custom save folder by default.")
                            color: "#7a7a7a"; font.pixelSize: 11 * App.fontScale
                            wrapMode: Text.WordWrap
                            Layout.fillWidth: true
                        }

                        Rectangle { Layout.fillWidth: true; height: 1; color: ColorPalette.border }

                        Text { text: qsTr("Stellar temporary directory:"); color: ColorPalette.textPrimary; font.pixelSize: 13 * App.fontScale }
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8
                            TextField {
                                Layout.fillWidth: true
                                text: root.editTemporaryDirectory
                                onTextChanged: root.editTemporaryDirectory = text
                                color: ColorPalette.textPrimary; font.pixelSize: 13 * App.fontScale
                                background: Rectangle { color: ColorPalette.dividerBg; border.color: "#4a4a4a"; radius: 3 }
                            }
                            DlgButton {
                                text: qsTr("Browse…")
                                onClicked: tempFolderDlg.open()
                            }
                        }

                        Text {
                            text: qsTr("Stellar stores partially downloaded file parts and metadata here while downloading and assembling files.")
                            color: "#7a7a7a"; font.pixelSize: 11 * App.fontScale
                            wrapMode: Text.WordWrap
                            Layout.fillWidth: true
                        }

                        StyledCheckBox {
                            text: qsTr("Start downloading immediately (skip file info dialog)")
                            topPadding: 0; bottomPadding: 0
                            checked: root.editStartImmediately
                            onCheckedChanged: root.editStartImmediately = checked
                            contentItem: Text { text: parent.text; color: ColorPalette.textPrimary; font.pixelSize: 13 * App.fontScale; leftPadding: parent.indicator.width + 4 }
                        }

                        StyledCheckBox {
                            text: qsTr("Show download complete dialog")
                            topPadding: 0; bottomPadding: 0
                            checked: root.editShowDownloadComplete
                            onCheckedChanged: root.editShowDownloadComplete = checked
                            contentItem: Text { text: parent.text; color: ColorPalette.textPrimary; font.pixelSize: 13 * App.fontScale; leftPadding: parent.indicator.width + 4 }
                        }

                        StyledCheckBox {
                            text: qsTr("Start downloading immediately while displaying \"Download File Info\" dialog")
                            topPadding: 0; bottomPadding: 0
                            checked: root.editStartDownloadWhileFileInfo
                            onCheckedChanged: root.editStartDownloadWhileFileInfo = checked
                            contentItem: Text { text: parent.text; color: ColorPalette.textPrimary; font.pixelSize: 13 * App.fontScale; leftPadding: parent.indicator.width + 4; wrapMode: Text.WordWrap; Layout.fillWidth: true }
                        }

                        StyledCheckBox {
                            text: qsTr("Auto-fill the description field with file metadata (bitrate, resolution, codec, etc.)")
                            topPadding: 0; bottomPadding: 0
                            checked: root.editFillDescriptionMetadata
                            onCheckedChanged: root.editFillDescriptionMetadata = checked
                            contentItem: Text { text: parent.text; color: ColorPalette.textPrimary; font.pixelSize: 13 * App.fontScale; leftPadding: parent.indicator.width + 4; wrapMode: Text.WordWrap; Layout.fillWidth: true }
                        }

                        StyledCheckBox {
                            text: qsTr("Show swarm map when downloading torrent metadata")
                            topPadding: 0; bottomPadding: 0
                            checked: root.editShowSwarmMapWhileFetchingMetadata
                            onCheckedChanged: root.editShowSwarmMapWhileFetchingMetadata = checked
                            contentItem: Text { text: parent.text; color: ColorPalette.textPrimary; font.pixelSize: 13 * App.fontScale; leftPadding: parent.indicator.width + 4; wrapMode: Text.WordWrap; Layout.fillWidth: true }
                        }

                        StyledCheckBox {
                            text: qsTr("Show queue selection panel on pressing Download Later")
                            topPadding: 0; bottomPadding: 0
                            checked: root.editShowQueueSelectionOnDownloadLater
                            onCheckedChanged: root.editShowQueueSelectionOnDownloadLater = checked
                            contentItem: Text { text: parent.text; color: ColorPalette.textPrimary; font.pixelSize: 13 * App.fontScale; leftPadding: parent.indicator.width + 4; wrapMode: Text.WordWrap; Layout.fillWidth: true }
                        }
                        StyledCheckBox {
                            text: qsTr("Show queue selection panel on closing batch downloads dialog")
                            topPadding: 0; bottomPadding: 0
                            checked: root.editShowQueueSelectionOnBatchDownload
                            onCheckedChanged: root.editShowQueueSelectionOnBatchDownload = checked
                            contentItem: Text { text: parent.text; color: ColorPalette.textPrimary; font.pixelSize: 13 * App.fontScale; leftPadding: parent.indicator.width + 4; wrapMode: Text.WordWrap; Layout.fillWidth: true }
                        }
                        Text {
                            text: qsTr("Note: These settings don't apply to queue processing for the Start Downloading Immediately setting and Show Download Complete dialog setting.")
                            color: "#7a7a7a"; font.pixelSize: 10 * App.fontScale
                            wrapMode: Text.WordWrap
                            Layout.fillWidth: true
                        }

                        Rectangle { Layout.fillWidth: true; height: 1; color: ColorPalette.border }

                        Text { text: qsTr("If a duplicate URL is added:"); color: ColorPalette.textPrimary; font.pixelSize: 13 * App.fontScale }
                        ComboBox {
                            id: duplicateActionCombo
                            model: [
                                qsTr("Ask me what to do"),
                                qsTr("Add with a numbered file name"),
                                qsTr("Overwrite the existing download"),
                                qsTr("Resume / show complete dialog")
                            ]
                            currentIndex: root.editDuplicateAction
                            implicitWidth: 260
                            font.pixelSize: 12 * App.fontScale
                            background: Rectangle { color: ColorPalette.dividerBg; border.color: "#4a4a4a"; radius: 3 }
                            contentItem: Text {
                                leftPadding: 8
                                text: duplicateActionCombo.displayText
                                color: ColorPalette.textPrimary; font: duplicateActionCombo.font
                                verticalAlignment: Text.AlignVCenter
                            }
                            onCurrentIndexChanged: root.editDuplicateAction = currentIndex
                        }

                        Rectangle { Layout.fillWidth: true; height: 1; color: ColorPalette.border }

                        Text { text: qsTr("Double-clicking on a download in the file list:"); color: ColorPalette.textPrimary; font.pixelSize: 13 * App.fontScale }
                        ComboBox {
                            id: doubleClickActionCombo
                            model: [
                                qsTr("Open file properties dialog"),
                                qsTr("Open file"),
                                qsTr("Open folder")
                            ]
                            currentIndex: root.editDoubleClickAction
                            implicitWidth: 260
                            font.pixelSize: 12 * App.fontScale
                            background: Rectangle { color: ColorPalette.dividerBg; border.color: "#4a4a4a"; radius: 3 }
                            contentItem: Text {
                                leftPadding: 8
                                text: doubleClickActionCombo.displayText
                                color: ColorPalette.textPrimary; font: doubleClickActionCombo.font
                                verticalAlignment: Text.AlignVCenter
                            }
                            onCurrentIndexChanged: root.editDoubleClickAction = currentIndex
                        }

                        Rectangle { Layout.fillWidth: true; height: 1; color: ColorPalette.border }

                        Text { text: qsTr("Last try date format:"); color: ColorPalette.textPrimary; font.pixelSize: 13 * App.fontScale }
                        ComboBox {
                            id: lastTryDateStyleCombo
                            model: [
                                root._previewDatePart(0),
                                root._previewDatePart(1),
                                root._previewDatePart(2),
                                root._previewDatePart(3)
                            ]
                            currentIndex: root.editLastTryDateStyle
                            implicitWidth: 220
                            font.pixelSize: 12 * App.fontScale
                            background: Rectangle { color: ColorPalette.dividerBg; border.color: "#4a4a4a"; radius: 3 }
                            contentItem: Text {
                                leftPadding: 8
                                text: lastTryDateStyleCombo.displayText
                                color: ColorPalette.textPrimary; font: lastTryDateStyleCombo.font
                                verticalAlignment: Text.AlignVCenter
                            }
                            onCurrentIndexChanged: root.editLastTryDateStyle = currentIndex
                        }

                        Text { text: qsTr("Time format:"); color: ColorPalette.textPrimary; font.pixelSize: 13 * App.fontScale }
                        ComboBox {
                            id: lastTryTimeModeCombo
                            model: [
                                qsTr("24-hour time"),
                                qsTr("12-hour time")
                            ]
                            currentIndex: root.editLastTryUse24Hour ? 0 : 1
                            implicitWidth: 220
                            font.pixelSize: 12 * App.fontScale
                            background: Rectangle { color: ColorPalette.dividerBg; border.color: "#4a4a4a"; radius: 3 }
                            contentItem: Text {
                                leftPadding: 8
                                text: lastTryTimeModeCombo.displayText
                                color: ColorPalette.textPrimary; font: lastTryTimeModeCombo.font
                                verticalAlignment: Text.AlignVCenter
                            }
                            onCurrentIndexChanged: root.editLastTryUse24Hour = currentIndex === 0
                        }

                        StyledCheckBox {
                            text: qsTr("Show seconds")
                            topPadding: 0; bottomPadding: 0
                            checked: root.editLastTryShowSeconds
                            onCheckedChanged: root.editLastTryShowSeconds = checked
                            contentItem: Text { text: parent.text; color: ColorPalette.textPrimary; font.pixelSize: 13 * App.fontScale; leftPadding: parent.indicator.width + 4 }
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: previewColumn.implicitHeight + 16
                            radius: 4
                            color: ColorPalette.rowAltBg
                            border.color: ColorPalette.border

                            ColumnLayout {
                                id: previewColumn
                                anchors.fill: parent
                                anchors.margins: 8
                                spacing: 4

                                Text { text: qsTr("Preview"); color: "#909090"; font.pixelSize: 11 * App.fontScale }
                                Text { text: root.lastTryPreview; color: ColorPalette.textPrimary; font.pixelSize: 13 * App.fontScale; font.family: "Consolas" }
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

                            Text { text: qsTr("Browser Integration"); color: ColorPalette.textHeader; font.pixelSize: 16 * App.fontScale; font.bold: true }
                            Rectangle { Layout.fillWidth: true; height: 1; color: ColorPalette.border }

                            // ?? Monitored file types ??????????????????????????????
                            Text {
                                text: qsTr("Automatically start downloading the following file types:")
                                color: ColorPalette.textPrimary; font.pixelSize: 13 * App.fontScale
                                wrapMode: Text.WordWrap
                                Layout.fillWidth: true
                            }

                            ScrollView {
                                Layout.fillWidth: true
                                implicitHeight: 72
                                clip: true
                                background: Rectangle { color: ColorPalette.dividerBg; border.color: "#4a4a4a"; radius: 3 }
                                TextArea {
                                    id: monitoredExtsArea
                                    wrapMode: TextArea.Wrap
                                    font.pixelSize: 11 * App.fontScale
                                    font.family: "monospace"
                                    color: ColorPalette.textPrimary
                                    background: null
                                    leftPadding: 6; rightPadding: 6; bottomPadding: 6; topPadding: 8
                                    text: App.settings.monitoredExtensions.join(" ").toUpperCase()
                                }
                            }

                            Text {
                                text: qsTr("Space or comma-separated. Case-insensitive.")
                                color: "#555"; font.pixelSize: 10 * App.fontScale
                            }

                            Rectangle { Layout.fillWidth: true; height: 1; color: ColorPalette.border }

                            // ?? Excluded sites ????????????????????????????????????
                            Text {
                                text: qsTr("Don't start downloading automatically from the following sites:")
                                color: ColorPalette.textPrimary; font.pixelSize: 13 * App.fontScale
                                wrapMode: Text.WordWrap
                                Layout.fillWidth: true
                            }

                            ScrollView {
                                Layout.fillWidth: true
                                implicitHeight: 60
                                clip: true
                                background: Rectangle { color: ColorPalette.dividerBg; border.color: "#4a4a4a"; radius: 3 }
                                TextArea {
                                    id: excludedSitesArea
                                    wrapMode: TextArea.Wrap
                                    font.pixelSize: 11 * App.fontScale
                                    font.family: "monospace"
                                    color: ColorPalette.textPrimary
                                    background: null
                                    leftPadding: 6; rightPadding: 6; bottomPadding: 6; topPadding: 8
                                    text: App.settings.excludedSites.join(" ")
                                }
                            }

                            Text {
                                text: qsTr("Space-separated host patterns. Wildcards (*) supported, e.g. *.update.microsoft.com")
                                color: "#555"; font.pixelSize: 10 * App.fontScale
                                wrapMode: Text.WordWrap
                                Layout.fillWidth: true
                            }

                            Rectangle { Layout.fillWidth: true; height: 1; color: ColorPalette.border }

                            // ?? Address Exceptions ????????????????????????????????
                            Text {
                                text: qsTr("Address Exceptions")
                                color: ColorPalette.textHeader; font.pixelSize: 14 * App.fontScale; font.bold: true
                            }

                            StyledCheckBox {
                                id: showExceptDlgChk
                                text: qsTr("Show the dialog to add an address to the list of exceptions for a twice cancelled download")
                                topPadding: 0; bottomPadding: 0
                                Layout.fillWidth: true
                                checked: root.editShowExceptionsDialog
                                onCheckedChanged: root.editShowExceptionsDialog = checked
                                contentItem: Text {
                                    text: parent.text
                                    color: ColorPalette.textPrimary; font.pixelSize: 12 * App.fontScale
                                    leftPadding: parent.indicator.width + 4
                                    wrapMode: Text.WordWrap
                                    width: parent.width
                                }
                            }

                            Text {
                                text: qsTr("Don't start downloading from the following addresses:")
                                color: ColorPalette.textPrimary; font.pixelSize: 13 * App.fontScale
                                wrapMode: Text.WordWrap
                                Layout.fillWidth: true
                            }

                            ScrollView {
                                Layout.fillWidth: true
                                implicitHeight: 160
                                clip: true
                                background: Rectangle { color: ColorPalette.dividerBg; border.color: "#4a4a4a"; radius: 3 }
                                TextArea {
                                    id: excludedAddrsArea
                                    wrapMode: TextArea.NoWrap
                                    font.pixelSize: 11 * App.fontScale
                                    font.family: "monospace"
                                    color: ColorPalette.textPrimary
                                    background: null
                                    leftPadding: 6; rightPadding: 6; bottomPadding: 6; topPadding: 8
                                    text: App.settings.excludedAddresses.join("\n")
                                }
                            }

                            Text {
                                text: qsTr("One URL pattern per line. Wildcards (*) supported.")
                                color: "#555"; font.pixelSize: 10 * App.fontScale
                            }

                            Rectangle { Layout.fillWidth: true; height: 1; color: ColorPalette.border }

                            // ?? Bypass interception key ????????????????????????????
                            Text {
                                text: qsTr("Bypass Download Interception")
                                color: ColorPalette.textHeader; font.pixelSize: 14 * App.fontScale; font.bold: true
                            }

                            Text {
                                text: qsTr("Hold this key while clicking a download link to skip interception and let the browser download:")
                                color: ColorPalette.textPrimary; font.pixelSize: 13 * App.fontScale
                                wrapMode: Text.WordWrap
                                Layout.fillWidth: true
                            }

                            Row {
                                spacing: 12
                                ComboBox {
                                    id: bypassKeyCombo
                                    model: [qsTr("None"), "Alt", "Ctrl", "Shift"]
                                    currentIndex: root.editBypassInterceptKey
                                    implicitWidth: 120
                                    font.pixelSize: 12 * App.fontScale
                                    background: Rectangle { color: ColorPalette.dividerBg; border.color: "#4a4a4a"; radius: 3 }
                                    contentItem: Text {
                                        leftPadding: 8
                                        text: bypassKeyCombo.displayText
                                        color: ColorPalette.textPrimary; font: bypassKeyCombo.font
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

                        Text { text: qsTr("Speed Limiter"); color: ColorPalette.textHeader; font.pixelSize: 16 * App.fontScale; font.bold: true }
                        Rectangle { Layout.fillWidth: true; height: 1; color: ColorPalette.border }

                            StyledCheckBox {
                                id: globalLimitChk
                                text: qsTr("Enable speed limiter")
                                topPadding: 0; bottomPadding: 0
                                onCheckedChanged: root.editGlobalSpeedLimitEnabled = checked
                                contentItem: Text { text: parent.text; color: ColorPalette.textPrimary; font.pixelSize: 13 * App.fontScale; leftPadding: parent.indicator.width + 4 }
                            }

                            RowLayout {
                                spacing: 8
                                Text { text: qsTr("Maximum download:"); color: "#a0a0a0"; font.pixelSize: 13 * App.fontScale }
                                TextField {
                                    id: speedLimitField
                                    implicitWidth: 90
                                    color: ColorPalette.textPrimary
                                    font.pixelSize: 13 * App.fontScale
                                    background: Rectangle { color: ColorPalette.dividerBg; border.color: "#4a4a4a"; radius: 3 }

                                    function syncFromModel() {
                                        var val = root.editSavedSpeedLimitKBps
                                        if (parseInt(text) !== val)
                                            text = val.toString()
                                    }
                                    Component.onCompleted: syncFromModel()
                                    Connections {
                                        target: root
                                        function onEditSavedSpeedLimitKBpsChanged() {
                                            if (!speedLimitField.activeFocus)
                                                speedLimitField.syncFromModel()
                                        }
                                    }

                                    onTextEdited: {
                                        var v = parseInt(text)
                                        if (!isNaN(v) && v >= 0)
                                            root.editSavedSpeedLimitKBps = v
                                    }
                                }
                                Text { text: qsTr("KB/s"); color: "#a0a0a0"; font.pixelSize: 13 * App.fontScale }
                            }

                            RowLayout {
                                spacing: 8
                                Text { text: qsTr("Maximum upload:"); color: "#a0a0a0"; font.pixelSize: 13 * App.fontScale }
                                TextField {
                                    id: uploadLimitField
                                    implicitWidth: 90
                                    color: ColorPalette.textPrimary
                                    font.pixelSize: 13 * App.fontScale
                                    background: Rectangle { color: ColorPalette.dividerBg; border.color: "#4a4a4a"; radius: 3 }

                                    function syncFromModel() {
                                        var val = root.editGlobalUploadLimitKBps
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
                                        if (!isNaN(v) && v >= 0)
                                            root.editGlobalUploadLimitKBps = v
                                    }
                                }
                                Text { text: qsTr("KB/s"); color: "#a0a0a0"; font.pixelSize: 13 * App.fontScale }
                            }

                        StyledCheckBox {
                            text: qsTr("Always turn on speed limiter on Stellar startup")
                            topPadding: 0; bottomPadding: 0
                            checked: root.editSpeedLimiterOnStartup
                            onCheckedChanged: root.editSpeedLimiterOnStartup = checked
                            contentItem: Text { text: parent.text; color: ColorPalette.textPrimary; font.pixelSize: 13 * App.fontScale; leftPadding: parent.indicator.width + 4; wrapMode: Text.WordWrap; Layout.fillWidth: true }
                        }

                        Rectangle { Layout.fillWidth: true; height: 1; color: ColorPalette.border }

                        // ?? Speed Limiter Scheduler ???????????????????????????????????????????????
                        // Each rule: days[], onHour (1-12), onMinute (0-59), onAmPm, offHour,
                        // offMinute, offAmPm, downLimitKBps, upLimitKBps. Stored in editSpeedScheduleJson.
                        StyledCheckBox {
                            text: qsTr("Enable speed limiter scheduler")
                            topPadding: 0; bottomPadding: 0
                            checked: root.editSpeedScheduleEnabled
                            onCheckedChanged: root.editSpeedScheduleEnabled = checked
                            contentItem: Text { text: parent.text; color: ColorPalette.textPrimary; font.pixelSize: 13 * App.fontScale; leftPadding: parent.indicator.width + 4 }
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

                            // ?? Per-rule cards ???????????????????????????????????????????????????
                            // Style matches GrabberScheduleDialog: #1b1b1b panels, #333 borders,
                            // #e0e0e0 text, 12px font, 26px tall inputs with small ?? arrows.
                            Repeater {
                                model: scheduleCol.rules.length
                                delegate: Rectangle {
                                    id: ruleCard
                                    required property int index
                                    Layout.fillWidth: true
                                    implicitHeight: cardCol.implicitHeight + 18
                                    color: ColorPalette.inputBg
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

                                        // ?? Header ???????????????????????????????????????????????
                                        RowLayout {
                                            Layout.fillWidth: true
                                            Text {
                                                text: qsTr("Rule %1").arg(ruleCard.index + 1)
                                                color: ColorPalette.textMuted; font.pixelSize: 11 * App.fontScale; font.bold: true
                                            }
                                            Item { Layout.fillWidth: true }
                                            Text {
                                                text: qsTr("Remove")
                                                color: removeHov.containsMouse ? "#ff7777" : "#aa3333"
                                                font.pixelSize: 11 * App.fontScale
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

                                        // ?? Day pills - clickable, blue when active ???????????????
                                        RowLayout {
                                            spacing: 3
                                            Repeater {
                                                model: ["Mon","Tue","Wed","Thu","Fri","Sat","Sun"]
                                                delegate: Rectangle {
                                                    required property int index
                                                    required property var modelData
                                                    property bool on: ruleCard.rule.days && ruleCard.rule.days.indexOf(modelData) >= 0
                                                    width: 36; height: 22; radius: 2
                                                    color: on ? ColorPalette.selectionBg : ColorPalette.panelBg
                                                    border.color: on ? "#4488dd" : ColorPalette.border
                                                    Text {
                                                        anchors.centerIn: parent
                                                        text: modelData
                                                        color: on ? "#aaccff" : ColorPalette.textDisabled
                                                        font.pixelSize: 11 * App.fontScale
                                                    }
                                                    MouseArea {
                                                        anchors.fill: parent
                                                        cursorShape: Qt.PointingHandCursor
                                                        onClicked: ruleCard.patchDay(modelData, !on)
                                                    }
                                                }
                                            }
                                        }

                                        // ?? On ? Off / Limit row ??????????????????????????????????
                                        // Uses the same compact input style as GrabberScheduleDialog:
                                        // TextInput in a 50?26 Rectangle, colon separator, DarkCombo for AM/PM.
                                        RowLayout {
                                            spacing: 4
                                            Layout.fillWidth: true

                                            Text { text: qsTr("On"); color: ColorPalette.textSecond; font.pixelSize: 12 * App.fontScale }

                                            // On-hour input (1-12)
                                            Rectangle {
                                                width: 50; height: 26; radius: 2
                                                color: ColorPalette.inputBg; border.color: onHourFld.activeFocus ? "#4488dd" : ColorPalette.border
                                                TextInput {
                                                    id: onHourFld
                                                    anchors { fill: parent; leftMargin: 6; rightMargin: 6 }
                                                    text: String(ruleCard.rule.onHour || "9")
                                                    color: ColorPalette.textPrimary; font.pixelSize: 12 * App.fontScale
                                                    horizontalAlignment: TextInput.AlignHCenter
                                                    verticalAlignment: TextInput.AlignVCenter
                                                    validator: IntValidator { bottom: 1; top: 12 }
                                                    onTextEdited: ruleCard.patch("onHour", text)
                                                }
                                            }
                                            Text { text: ":"; color: ColorPalette.textSecond; font.pixelSize: 13 * App.fontScale }
                                            // On-minute input (00-59), zero-padded
                                            Rectangle {
                                                width: 50; height: 26; radius: 2
                                                color: ColorPalette.inputBg; border.color: onMinFld.activeFocus ? "#4488dd" : ColorPalette.border
                                                TextInput {
                                                    id: onMinFld
                                                    anchors { fill: parent; leftMargin: 6; rightMargin: 6 }
                                                    text: {
                                                        var m = parseInt(ruleCard.rule.onMinute)
                                                        return isNaN(m) ? "00" : (m < 10 ? "0" + m : String(m))
                                                    }
                                                    color: ColorPalette.textPrimary; font.pixelSize: 12 * App.fontScale
                                                    horizontalAlignment: TextInput.AlignHCenter
                                                    verticalAlignment: TextInput.AlignVCenter
                                                    validator: IntValidator { bottom: 0; top: 59 }
                                                    onTextEdited: ruleCard.patch("onMinute", text)
                                                }
                                            }
                                            // AM/PM combo for On time - same style as DarkCombo
                                            ComboBox {
                                                model: ["AM","PM"]
                                                currentIndex: (ruleCard.rule.onAmPm || "AM") === "PM" ? 1 : 0
                                                implicitWidth: 62; implicitHeight: 26
                                                font.pixelSize: 12 * App.fontScale
                                                contentItem: Text {
                                                    leftPadding: 8; rightPadding: 20
                                                    text: parent.displayText; color: ColorPalette.textPrimary; font: parent.font
                                                    verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight
                                                }
                                                background: Rectangle { color: ColorPalette.inputBg; border.color: ColorPalette.border; radius: 2 }
                                                indicator: Text { x: parent.width-width-6; y: (parent.height-height)/2; text: "▾"; color: "#888"; font.pixelSize: 8 * App.fontScale }
                                                popup.background: Rectangle { color: ColorPalette.inputBg; border.color: "#444"; radius: 3 }
                                                onCurrentIndexChanged: ruleCard.patch("onAmPm", currentIndex === 1 ? "PM" : "AM")
                                            }

                                            Text { text: "–"; color: "#555555"; font.pixelSize: 13 * App.fontScale; leftPadding: 2; rightPadding: 2 }
                                            Text { text: "Off"; color: ColorPalette.textSecond; font.pixelSize: 12 * App.fontScale }

                                            // Off-hour input (1-12)
                                            Rectangle {
                                                width: 50; height: 26; radius: 2
                                                color: ColorPalette.inputBg; border.color: offHourFld.activeFocus ? "#4488dd" : ColorPalette.border
                                                TextInput {
                                                    id: offHourFld
                                                    anchors { fill: parent; leftMargin: 6; rightMargin: 6 }
                                                    text: String(ruleCard.rule.offHour || "5")
                                                    color: ColorPalette.textPrimary; font.pixelSize: 12 * App.fontScale
                                                    horizontalAlignment: TextInput.AlignHCenter
                                                    verticalAlignment: TextInput.AlignVCenter
                                                    validator: IntValidator { bottom: 1; top: 12 }
                                                    onTextEdited: ruleCard.patch("offHour", text)
                                                }
                                            }
                                            Text { text: ":"; color: ColorPalette.textSecond; font.pixelSize: 13 * App.fontScale }
                                            // Off-minute input (00-59)
                                            Rectangle {
                                                width: 50; height: 26; radius: 2
                                                color: ColorPalette.inputBg; border.color: offMinFld.activeFocus ? "#4488dd" : ColorPalette.border
                                                TextInput {
                                                    id: offMinFld
                                                    anchors { fill: parent; leftMargin: 6; rightMargin: 6 }
                                                    text: {
                                                        var m = parseInt(ruleCard.rule.offMinute)
                                                        return isNaN(m) ? "00" : (m < 10 ? "0" + m : String(m))
                                                    }
                                                    color: ColorPalette.textPrimary; font.pixelSize: 12 * App.fontScale
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
                                                font.pixelSize: 12 * App.fontScale
                                                contentItem: Text {
                                                    leftPadding: 8; rightPadding: 20
                                                    text: parent.displayText; color: ColorPalette.textPrimary; font: parent.font
                                                    verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight
                                                }
                                                background: Rectangle { color: ColorPalette.inputBg; border.color: ColorPalette.border; radius: 2 }
                                                indicator: Text { x: parent.width-width-6; y: (parent.height-height)/2; text: "▾"; color: "#888"; font.pixelSize: 8 * App.fontScale }
                                                popup.background: Rectangle { color: ColorPalette.inputBg; border.color: "#444"; radius: 3 }
                                                onCurrentIndexChanged: ruleCard.patch("offAmPm", currentIndex === 1 ? "PM" : "AM")
                                            }

                                        }

                                        // ?? Speed limit row ???????????????????????????????????????
                                        RowLayout {
                                            spacing: 6
                                            Text { text: qsTr("Download"); color: ColorPalette.textSecond; font.pixelSize: 12 * App.fontScale }
                                            Rectangle {
                                                width: 70; height: 26; radius: 2
                                                color: ColorPalette.inputBg; border.color: downLimitFld.activeFocus ? "#4488dd" : ColorPalette.border
                                                TextInput {
                                                    id: downLimitFld
                                                    anchors { fill: parent; leftMargin: 6; rightMargin: 6 }
                                                    text: String(ruleCard.rule.downLimitKBps || 500)
                                                    color: ColorPalette.textPrimary; font.pixelSize: 12 * App.fontScale
                                                    horizontalAlignment: TextInput.AlignHCenter
                                                    verticalAlignment: TextInput.AlignVCenter
                                                    validator: IntValidator { bottom: 1; top: 999999 }
                                                    onTextEdited: {
                                                        var v = parseInt(text)
                                                        if (!isNaN(v) && v > 0) ruleCard.patch("downLimitKBps", v)
                                                    }
                                                }
                                            }
                                            Text { text: qsTr("KB/s"); color: ColorPalette.textSecond; font.pixelSize: 12 * App.fontScale }
                                            Item { Layout.preferredWidth: 10 }
                                            Text { text: qsTr("Upload"); color: ColorPalette.textSecond; font.pixelSize: 12 * App.fontScale }
                                            Rectangle {
                                                width: 70; height: 26; radius: 2
                                                color: ColorPalette.inputBg; border.color: upLimitFld.activeFocus ? "#4488dd" : ColorPalette.border
                                                TextInput {
                                                    id: upLimitFld
                                                    anchors { fill: parent; leftMargin: 6; rightMargin: 6 }
                                                    text: String(ruleCard.rule.upLimitKBps || 500)
                                                    color: ColorPalette.textPrimary; font.pixelSize: 12 * App.fontScale
                                                    horizontalAlignment: TextInput.AlignHCenter
                                                    verticalAlignment: TextInput.AlignVCenter
                                                    validator: IntValidator { bottom: 1; top: 999999 }
                                                    onTextEdited: {
                                                        var v = parseInt(text)
                                                        if (!isNaN(v) && v > 0) ruleCard.patch("upLimitKBps", v)
                                                    }
                                                }
                                            }
                                            Text { text: qsTr("KB/s"); color: ColorPalette.textSecond; font.pixelSize: 12 * App.fontScale }
                                        }
                                    }
                                }
                            } // Repeater

                            // ?? Add Rule button ??????????????????????????????????????????????????
                            DlgButton {
                                text: qsTr("+ Add Rule")
                                onClicked: {
                                    var arr = JSON.parse(root.editSpeedScheduleJson || "[]")
                                    arr.push(scheduleCol.blankRule())
                                    scheduleCol.saveRules(arr)
                                }
                            }

                            // Informational note - same blue-tinted style as GrabberScheduleDialog
                            Rectangle {
                                Layout.fillWidth: true
                                implicitHeight: scheduleNote.implicitHeight + 16
                                color: ColorPalette.infoBoxBg; border.color: ColorPalette.infoBoxBorder; radius: 3
                                Text {
                                    id: scheduleNote
                                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: 8 }
                                    text: qsTr("Click a day pill to toggle it. Rules are evaluated every minute; first matching rule wins. Scheduled download and upload limits are cleared automatically when no rule is active.")
                                    color: ColorPalette.infoBoxText; font.pixelSize: 11 * App.fontScale; wrapMode: Text.WordWrap
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

                        Text { text: qsTr("Notifications"); color: ColorPalette.textHeader; font.pixelSize: 16 * App.fontScale; font.bold: true }
                        Rectangle { Layout.fillWidth: true; height: 1; color: ColorPalette.border }

                        StyledCheckBox {
                            text: qsTr("Show notification when download completes")
                            topPadding: 0; bottomPadding: 0
                            checked: root.editShowCompletionNotification
                            onCheckedChanged: root.editShowCompletionNotification = checked
                            contentItem: Text { text: parent.text; color: ColorPalette.textPrimary; font.pixelSize: 13 * App.fontScale; leftPadding: parent.indicator.width + 4 }
                        }
                        StyledCheckBox {
                            text: qsTr("Show notification on download error")
                            topPadding: 0; bottomPadding: 0
                            checked: root.editShowErrorNotification
                            onCheckedChanged: root.editShowErrorNotification = checked
                            contentItem: Text { text: parent.text; color: ColorPalette.textPrimary; font.pixelSize: 13 * App.fontScale; leftPadding: parent.indicator.width + 4 }
                        }

                        Item { Layout.fillHeight: true }
                    }
                }

                // General
                Item {
                    ScrollView {
                        id: generalScroll
                        anchors.fill: parent
                        contentWidth: availableWidth
                        contentHeight: generalCol.implicitHeight + 24
                        clip: true

                    ColumnLayout {
                        id: generalCol
                        width: generalScroll.availableWidth - 24
                        x: 12; y: 12
                        spacing: 10

                        Text { text: qsTr("General"); color: ColorPalette.textHeader; font.pixelSize: 16 * App.fontScale; font.bold: true }
                        Rectangle { Layout.fillWidth: true; height: 1; color: ColorPalette.border }

                        StyledCheckBox {
                            text: qsTr("Minimize to system tray")
                            topPadding: 0; bottomPadding: 0
                            checked: root.editMinimizeToTray
                            onCheckedChanged: root.editMinimizeToTray = checked
                            contentItem: Text { text: parent.text; color: ColorPalette.textPrimary; font.pixelSize: 13 * App.fontScale; leftPadding: parent.indicator.width + 4 }
                        }
                        StyledCheckBox {
                            text: qsTr("Close to system tray")
                            topPadding: 0; bottomPadding: 0
                            checked: root.editCloseToTray
                            onCheckedChanged: root.editCloseToTray = checked
                            contentItem: Text { text: parent.text; color: ColorPalette.textPrimary; font.pixelSize: 13 * App.fontScale; leftPadding: parent.indicator.width + 4 }
                        }
                        StyledCheckBox {
                            text: qsTr("Launch Stellar on startup")
                            topPadding: 0; bottomPadding: 0
                            checked: root.editLaunchOnStartup
                            onCheckedChanged: root.editLaunchOnStartup = checked
                            contentItem: Text { text: parent.text; color: ColorPalette.textPrimary; font.pixelSize: 13 * App.fontScale; leftPadding: parent.indicator.width + 4 }
                        }
                        StyledCheckBox {
                            text: qsTr("Pause torrents on startup")
                            topPadding: 0; bottomPadding: 0
                            checked: root.editTorrentStopOnStartup
                            onCheckedChanged: root.editTorrentStopOnStartup = checked
                            contentItem: Text { text: parent.text; color: ColorPalette.textPrimary; font.pixelSize: 13 * App.fontScale; leftPadding: parent.indicator.width + 4 }
                        }
                        StyledCheckBox {
                            text: qsTr("Show tips in bottom bar")
                            topPadding: 0; bottomPadding: 0
                            checked: root.editShowTips
                            onCheckedChanged: root.editShowTips = checked
                            contentItem: Text { text: parent.text; color: ColorPalette.textPrimary; font.pixelSize: 13 * App.fontScale; leftPadding: parent.indicator.width + 4 }
                        }
                        Rectangle { Layout.fillWidth: true; height: 1; color: ColorPalette.border }
                        Text { text: qsTr("Appearance"); color: ColorPalette.textHeader; font.pixelSize: 14 * App.fontScale; font.bold: true }

                        RowLayout {
                            spacing: 10
                            Text {
                                text: qsTr("UI scale:")
                                color: ColorPalette.textPrimary
                                font.pixelSize: 13 * App.fontScale
                                Layout.alignment: Qt.AlignVCenter
                            }
                            ComboBox {
                                id: uiScaleCombo
                                implicitWidth: 150
                                implicitHeight: 26
                                readonly property var scaleValues: [0.0, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0, 2.5, 3.0]
                                model: [qsTr("System default"), "75%", "100%", "125%", "150%", "175%", "200%", "250%", "300%"]
                                currentIndex: {
                                    var idx = scaleValues.indexOf(root.editUiScaleFactor)
                                    return idx >= 0 ? idx : 0
                                }
                                onActivated: root.editUiScaleFactor = scaleValues[currentIndex]
                                contentItem: Text {
                                    leftPadding: 8
                                    text: uiScaleCombo.displayText
                                    color: ColorPalette.textPrimary
                                    font.pixelSize: 13 * App.fontScale
                                    verticalAlignment: Text.AlignVCenter
                                }
                                background: Rectangle {
                                    color: ColorPalette.inputBg
                                    border.color: uiScaleCombo.activeFocus ? "#4488dd" : ColorPalette.border
                                    radius: 2
                                }
                            }
                        }

                        RowLayout {
                            spacing: 10
                            Text {
                                text: qsTr("Font size:")
                                color: ColorPalette.textPrimary
                                font.pixelSize: 13 * App.fontScale
                                Layout.alignment: Qt.AlignVCenter
                            }
                            ComboBox {
                                id: fontSizeCombo
                                implicitWidth: 150
                                implicitHeight: 26
                                readonly property var fontValues: [0, 8, 9, 10, 11, 12, 13, 14, 16, 18, 20]
                                model: [qsTr("System default"), "8pt", "9pt", "10pt", "11pt", "12pt", "13pt", "14pt", "16pt", "18pt", "20pt"]
                                currentIndex: {
                                    var idx = fontValues.indexOf(root.editUiFontPointSize)
                                    return idx >= 0 ? idx : 0
                                }
                                onActivated: root.editUiFontPointSize = fontValues[currentIndex]
                                contentItem: Text {
                                    leftPadding: 8
                                    text: fontSizeCombo.displayText
                                    color: ColorPalette.textPrimary
                                    font.pixelSize: 13 * App.fontScale
                                    verticalAlignment: Text.AlignVCenter
                                }
                                background: Rectangle {
                                    color: ColorPalette.inputBg
                                    border.color: fontSizeCombo.activeFocus ? "#4488dd" : ColorPalette.border
                                    radius: 2
                                }
                            }
                        }

                        RowLayout {
                            spacing: 10
                            Text {
                                text: qsTr("Tray icon style:")
                                color: ColorPalette.textPrimary
                                font.pixelSize: 13 * App.fontScale
                                Layout.alignment: Qt.AlignVCenter
                            }
                            ComboBox {
                                id: trayIconStyleCombo
                                implicitWidth: 130
                                implicitHeight: 26
                                model: [qsTr("Colored"), qsTr("White"), qsTr("Black")]
                                currentIndex: root.editTrayIconStyle
                                onActivated: root.editTrayIconStyle = currentIndex
                                contentItem: Text {
                                    leftPadding: 8
                                    text: trayIconStyleCombo.displayText
                                    color: ColorPalette.textPrimary
                                    font.pixelSize: 13 * App.fontScale
                                    verticalAlignment: Text.AlignVCenter
                                }
                                background: Rectangle {
                                    color: ColorPalette.inputBg
                                    border.color: trayIconStyleCombo.activeFocus ? "#4488dd" : ColorPalette.border
                                    radius: 2
                                }
                            }
                        }

                        RowLayout {
                            spacing: 10
                            Text {
                                text: qsTr("Theme:")
                                color: ColorPalette.textPrimary
                                font.pixelSize: 13 * App.fontScale
                                Layout.alignment: Qt.AlignVCenter
                            }
                            ComboBox {
                                id: themeCombo
                                implicitWidth: 130
                                implicitHeight: 26
                                model: [qsTr("Dark"), qsTr("Light")]
                                currentIndex: root.editDarkMode ? 0 : 1
                                onActivated: root.editDarkMode = (currentIndex === 0)
                                contentItem: Text {
                                    leftPadding: 8
                                    text: themeCombo.displayText
                                    color: ColorPalette.textPrimary
                                    font.pixelSize: 13 * App.fontScale
                                    verticalAlignment: Text.AlignVCenter
                                }
                                background: Rectangle {
                                    color: ColorPalette.inputBg
                                    border.color: themeCombo.activeFocus ? "#4488dd" : ColorPalette.border
                                    radius: 2
                                }
                            }
                        }

                        Rectangle { Layout.fillWidth: true; height: 1; color: ColorPalette.border }
                        Text { text: qsTr("Utilities"); color: ColorPalette.textHeader; font.pixelSize: 14 * App.fontScale; font.bold: true }

                        StyledCheckBox {
                            text: qsTr("Show speed in tray icon tooltip")
                            topPadding: 0; bottomPadding: 0
                            checked: root.editSpeedInTrayTooltip
                            onCheckedChanged: root.editSpeedInTrayTooltip = checked
                            contentItem: Text { text: parent.text; color: ColorPalette.textPrimary; font.pixelSize: 13 * App.fontScale; leftPadding: parent.indicator.width + 4 }
                        }
                        StyledCheckBox {
                            text: qsTr("Show speed in title bar")
                            topPadding: 0; bottomPadding: 0
                            checked: root.editSpeedInTitleBar
                            onCheckedChanged: root.editSpeedInTitleBar = checked
                            contentItem: Text { text: parent.text; color: ColorPalette.textPrimary; font.pixelSize: 13 * App.fontScale; leftPadding: parent.indicator.width + 4 }
                        }
                        StyledCheckBox {
                            text: qsTr("Show speed in status bar")
                            topPadding: 0; bottomPadding: 0
                            checked: root.editSpeedInStatusBar
                            onCheckedChanged: root.editSpeedInStatusBar = checked
                            contentItem: Text { text: parent.text; color: ColorPalette.textPrimary; font.pixelSize: 13 * App.fontScale; leftPadding: parent.indicator.width + 4 }
                        }
                        StyledCheckBox {
                            text: qsTr("Show ratio in status bar")
                            topPadding: 0; bottomPadding: 0
                            checked: root.editRatioInStatusBar
                            onCheckedChanged: root.editRatioInStatusBar = checked
                            contentItem: Text { text: parent.text; color: ColorPalette.textPrimary; font.pixelSize: 13 * App.fontScale; leftPadding: parent.indicator.width + 4 }
                        }
                        StyledCheckBox {
                            text: qsTr("Show torrent connections in status bar")
                            topPadding: 0; bottomPadding: 0
                            checked: root.editConnectionsInStatusBar
                            onCheckedChanged: root.editConnectionsInStatusBar = checked
                            contentItem: Text { text: parent.text; color: ColorPalette.textPrimary; font.pixelSize: 13 * App.fontScale; leftPadding: parent.indicator.width + 4 }
                        }
                        StyledCheckBox {
                            text: qsTr("Show DHT nodes in status bar")
                            topPadding: 0; bottomPadding: 0
                            checked: root.editDhtNodesInStatusBar
                            onCheckedChanged: root.editDhtNodesInStatusBar = checked
                            contentItem: Text { text: parent.text; color: ColorPalette.textPrimary; font.pixelSize: 13 * App.fontScale; leftPadding: parent.indicator.width + 4 }
                        }
                        StyledCheckBox {
                            text: qsTr("Show Public IP in Status Bar")
                            topPadding: 0; bottomPadding: 0
                            checked: root.editShowPublicIpInStatusBar
                            onCheckedChanged: root.editShowPublicIpInStatusBar = checked
                            contentItem: Text { text: parent.text; color: ColorPalette.textPrimary; font.pixelSize: 13 * App.fontScale; leftPadding: parent.indicator.width + 4 }
                        }
                        Text {
                            text: qsTr("Detects your public IP via libtorrent and your active connection type. Hover the indicator to see WiFi SSID/signal or warnings about incoming connections.")
                            color: "#7a7a7a"
                            font.pixelSize: 11 * App.fontScale
                            wrapMode: Text.WordWrap
                            Layout.fillWidth: true
                            visible: root.editShowPublicIpInStatusBar
                        }

                        Rectangle { Layout.fillWidth: true; height: 1; color: ColorPalette.border }

                        Text { text: qsTr("Updates"); color: ColorPalette.textHeader; font.pixelSize: 14 * App.fontScale; font.bold: true }

                        StyledCheckBox {
                            text: qsTr("Automatically check for updates")
                            topPadding: 0; bottomPadding: 0
                            checked: root.editAutoCheckUpdates
                            onCheckedChanged: root.editAutoCheckUpdates = checked
                            contentItem: Text { text: parent.text; color: ColorPalette.textPrimary; font.pixelSize: 13 * App.fontScale; leftPadding: parent.indicator.width + 4 }
                        }

                        Rectangle { Layout.fillWidth: true; height: 1; color: ColorPalette.border }

                        Text { text: qsTr("Clipboard Monitoring"); color: ColorPalette.textHeader; font.pixelSize: 14 * App.fontScale; font.bold: true }

                        StyledCheckBox {
                            text: qsTr("Automatically start downloading URLs placed in the clipboard")
                            topPadding: 0; bottomPadding: 0
                            checked: root.editClipboardMonitorEnabled
                            onCheckedChanged: root.editClipboardMonitorEnabled = checked
                            contentItem: Text { text: parent.text; color: ColorPalette.textPrimary; font.pixelSize: 13 * App.fontScale; leftPadding: parent.indicator.width + 4; wrapMode: Text.WordWrap; Layout.fillWidth: true }
                        }

                        Text {
                            text: qsTr("When a URL matching a monitored file type is copied to the clipboard, Stellar will ask if you want to download it. Only file types listed under Browser \u203a Automatically start downloading the following file types are picked up.")
                            color: "#7a7a7a"; font.pixelSize: 11 * App.fontScale
                            wrapMode: Text.WordWrap
                            Layout.fillWidth: true
                            visible: root.editClipboardMonitorEnabled
                        }

                        Rectangle { Layout.fillWidth: true; height: 1; color: ColorPalette.border }

                        Text { text: qsTr("Backup & Restore"); color: ColorPalette.textHeader; font.pixelSize: 14 * App.fontScale; font.bold: true }

                        Text {
                            text: qsTr("Export everything - settings, downloads, torrents (with their share ratios), queues, categories and statistics - to a single backup file. Import it later into a fresh Stellar install to restore it all. Importing replaces the current data (a timestamped backup is kept) and restarts Stellar.")
                            color: "#909090"; font.pixelSize: 12 * App.fontScale
                            wrapMode: Text.WordWrap
                            Layout.fillWidth: true
                        }

                        RowLayout {
                            spacing: 8
                            DlgButton {
                                text: qsTr("Export All Data…")
                                primary: true
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

                        Text { text: qsTr("Video Downloader"); color: ColorPalette.textHeader; font.pixelSize: 16 * App.fontScale; font.bold: true }
                        Rectangle { Layout.fillWidth: true; height: 1; color: ColorPalette.border }

                        Text {
                            Layout.fillWidth: true
                            text: qsTr("Stellar uses yt-dlp to download videos from YouTube, Vimeo, Twitter/X, Instagram and hundreds of other sites. When you paste a video URL into Add URL, a format picker will appear.")
                            color: "#909090"; font.pixelSize: 12 * App.fontScale
                            wrapMode: Text.WordWrap
                        }

                        Rectangle { Layout.fillWidth: true; height: 1; color: "#2a2a2a" }

                        // ?? Status indicator ??????????????????????????????????????????
                        Text { text: qsTr("Binary status"); color: ColorPalette.textPrimary; font.pixelSize: 13 * App.fontScale; font.bold: true }

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
                                color: ColorPalette.textPrimary
                                font.pixelSize: 12 * App.fontScale
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

                        Rectangle { Layout.fillWidth: true; height: 1; color: "#2a2a2a" }

                        // ?? ffmpeg status ?????????????????????????????????????????????
                        Text { text: qsTr("ffmpeg status"); color: ColorPalette.textPrimary; font.pixelSize: 13 * App.fontScale; font.bold: true }

                        RowLayout {
                            spacing: 10
                            Rectangle {
                                width: 10; height: 10; radius: 5
                                color: App.ytdlpManager.ffmpegAvailable ? "#44cc44" : "#cc4444"
                            }
                            Text {
                                Layout.fillWidth: true
                                text: App.ytdlpManager.ffmpegAvailable
                                      ? (qsTr("ffmpeg found: %1").arg(App.ytdlpManager.ffmpegPath))
                                      : qsTr("ffmpeg not found - HD downloads will be limited to pre-muxed formats (max ~480p)")
                                color: App.ytdlpManager.ffmpegAvailable ? ColorPalette.textPrimary : "#dd8844"
                                font.pixelSize: 12 * App.fontScale
                                wrapMode: Text.WordWrap
                            }
                        }

                        Text {
                            Layout.fillWidth: true
                            visible: App.ffmpegUpdateStatus.length > 0
                            text: App.ffmpegUpdateStatus
                            color: App.ffmpegUpdating ? "#9ab8ff" : "#9a9a9a"
                            font.pixelSize: 11 * App.fontScale
                            wrapMode: Text.WordWrap
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

                        // Info box explaining what to do
                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: ffmpegNote.height + 16
                            radius: 4
                            color: ColorPalette.infoBoxBg
                            border.color: ColorPalette.infoBoxBorder
                            visible: !App.ytdlpManager.ffmpegAvailable

                            Text {
                                id: ffmpegNote
                                anchors { left: parent.left; right: parent.right; top: parent.top; leftMargin: 8; rightMargin: 8; topMargin: 8 }
                                text: qsTr("ffmpeg is required to merge separate video and audio streams into MP4/MKV. Without it, YouTube downloads fall back to a single pre-muxed stream (usually WebM, max 480p).\n\nTo fix: download ffmpeg from gyan.dev/ffmpeg/builds (Essentials build), extract ffmpeg.exe from the bin/ folder, and place it in the same folder as yt-dlp.exe. Then click Re-check above.")
                                color: ColorPalette.infoBoxText; font.pixelSize: 11 * App.fontScale
                                wrapMode: Text.WordWrap
                            }
                        }

                        DlgButton {
                            visible: false
                        }

                        Rectangle { Layout.fillWidth: true; height: 1; color: "#2a2a2a" }

                        // ?? Custom binary path ????????????????????????????????????????
                        Text { text: qsTr("Custom binary path"); color: ColorPalette.textPrimary; font.pixelSize: 13 * App.fontScale; font.bold: true }

                        Text {
                            Layout.fillWidth: true
                            text: qsTr("Leave blank to use the bundled binary (recommended). Set to the absolute path of your own yt-dlp executable if you want to use a specific version.")
                            color: "#808080"; font.pixelSize: 11 * App.fontScale
                            wrapMode: Text.WordWrap
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 6

                            TextField {
                                id: ytdlpPathField
                                Layout.fillWidth: true
                                font.pixelSize: 12 * App.fontScale
                                color:            ColorPalette.textPrimary
                                leftPadding:      8
                                rightPadding:     8
                                placeholderText:  qsTr("(auto - use bundled or system yt-dlp)")
                                placeholderTextColor: "#555555"
                                text: root.editYtdlpCustomBinaryPath
                                onTextChanged: root.editYtdlpCustomBinaryPath = text
                                background: Rectangle {
                                    color:        ColorPalette.inputBg
                                    border.color: ytdlpPathField.activeFocus ? "#4488dd" : ColorPalette.border
                                    radius: 3
                                }
                            }

                            DlgButton {
                                text: qsTr("Browse…")
                                onClicked: ytdlpFileDlg.open()
                            }
                        }

                        Rectangle { Layout.fillWidth: true; height: 1; color: "#2a2a2a" }

                        // ?? JavaScript runtime (EJS n-challenge solver) ???????????????
                        Text { text: qsTr("JavaScript runtime"); color: ColorPalette.textPrimary; font.pixelSize: 13 * App.fontScale; font.bold: true }

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
                                      ? qsTr("%1 found: %2").arg(App.ytdlpManager.jsRuntimeName).arg(App.ytdlpManager.jsRuntimePath)
                                      : qsTr("No JS runtime found - YouTube n-challenge solving disabled")
                                color: App.ytdlpManager.jsRuntimeAvailable ? ColorPalette.textPrimary : "#dd8844"
                                font.pixelSize: 12 * App.fontScale
                                elide: Text.ElideRight
                            }
                        }

                        // Info box shown when no runtime is detected
                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: jsRuntimeNote.height + 16
                            radius: 4
                            color: ColorPalette.infoBoxBg
                            border.color: ColorPalette.infoBoxBorder
                            visible: !App.ytdlpManager.jsRuntimeAvailable

                            Text {
                                id: jsRuntimeNote
                                anchors { left: parent.left; right: parent.right; top: parent.top; leftMargin: 8; rightMargin: 8; topMargin: 8 }
                                text: qsTr("yt-dlp requires an external JavaScript runtime to solve YouTube's n-challenge (URL throttling). Without it, YouTube downloads may fail or return only low-quality storyboard formats.\n\nInstall one of: Deno (deno.com), Node.js (nodejs.org), Bun (bun.sh), or QuickJS. Place it in the same folder as yt-dlp.exe or add it to your system PATH, then click Re-check in the yt-dlp status section above.")
                                color: ColorPalette.infoBoxText; font.pixelSize: 11 * App.fontScale
                                wrapMode: Text.WordWrap
                            }
                        }

                        Text {
                            Layout.fillWidth: true
                            text: qsTr("Override the auto-detected runtime path. Leave blank to use auto-detection (searches yt-dlp folder, app folder, and system PATH).")
                            color: "#808080"; font.pixelSize: 11 * App.fontScale
                            wrapMode: Text.WordWrap
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 6

                            TextField {
                                id: jsRuntimePathField
                                Layout.fillWidth: true
                                font.pixelSize: 12 * App.fontScale
                                color:            ColorPalette.textPrimary
                                leftPadding:      8
                                rightPadding:     8
                                placeholderText:  qsTr("(auto-detect from PATH and yt-dlp folder)")
                                placeholderTextColor: "#555555"
                                text: root.editYtdlpJsRuntimePath
                                onTextChanged: root.editYtdlpJsRuntimePath = text
                                background: Rectangle {
                                    color:        ColorPalette.inputBg
                                    border.color: jsRuntimePathField.activeFocus ? "#4488dd" : ColorPalette.border
                                    radius: 3
                                }
                            }

                            DlgButton {
                                text: qsTr("Browse…")
                                onClicked: jsRuntimeFileDlg.open()
                            }
                        }

                        Rectangle { Layout.fillWidth: true; height: 1; color: "#2a2a2a" }

                        // ?? Auto-update option ????????????????????????????????????????
                        StyledCheckBox {
                            id: ytdlpAutoUpdateCheck
                            text: qsTr("Automatically update yt-dlp at startup")
                            font.pixelSize: 12 * App.fontScale
                            topPadding: 0
                            bottomPadding: 0
                            checked: root.editYtdlpAutoUpdate
                            onCheckedChanged: root.editYtdlpAutoUpdate = checked
                            contentItem: Text {
                                text: parent.text
                                color: ColorPalette.textPrimary
                                font: parent.font
                                leftPadding: parent.indicator.width + parent.spacing
                                verticalAlignment: Text.AlignVCenter
                            }
                        }

                        Text {
                            Layout.fillWidth: true
                            text: qsTr("When enabled, Stellar will run \"yt-dlp -U\" at startup to keep the binary up to date. Requires an active internet connection.")
                            color: ColorPalette.textDisabled; font.pixelSize: 11 * App.fontScale
                            wrapMode: Text.WordWrap
                        }

                        Rectangle { Layout.fillWidth: true; height: 1; color: "#2a2a2a" }

                        // ?? Default cookie browser ????????????????????????????????????
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 6

                            Text {
                                text: qsTr("Default cookie browser:")
                                color: ColorPalette.textPrimary; font.pixelSize: 12 * App.fontScale
                                wrapMode: Text.WordWrap
                                Layout.fillWidth: true
                            }

                            ComboBox {
                                id: ytdlpCookieBrowserCombo
                                Layout.preferredWidth: 140
                                implicitHeight: 26
                                font.pixelSize: 11 * App.fontScale
                                model: ["None","Chrome","Firefox","Edge","Brave","Opera","Vivaldi","Safari"]

                                function _indexForBrowser(v) {
                                    v = (v || "").toLowerCase()
                                    if (v.length === 0 || v === "none") return 0
                                    for (var i = 1; i < model.length; ++i)
                                        if (model[i].toLowerCase() === v) return i
                                    return 0
                                }

                                Component.onCompleted: currentIndex = _indexForBrowser(root.editYtdlpDefaultCookieBrowser)

                                onActivated: {
                                    root.editYtdlpDefaultCookieBrowser = currentIndex === 0 ? "" : model[currentIndex].toLowerCase()
                                }
                                contentItem: Text {
                                    leftPadding: 8
                                    text: ytdlpCookieBrowserCombo.displayText
                                    color: ColorPalette.textPrimary; font: ytdlpCookieBrowserCombo.font
                                    verticalAlignment: Text.AlignVCenter
                                }
                                background: Rectangle {
                                    color: ColorPalette.inputBg
                                    border.color: ytdlpCookieBrowserCombo.activeFocus ? "#4488dd" : ColorPalette.border
                                    radius: 3
                                }
                                delegate: ItemDelegate {
                                    id: _ycbDel; width: ytdlpCookieBrowserCombo.width; height: 24
                                    contentItem: Text {
                                        text: modelData; color: ColorPalette.textPrimary
                                        font.pixelSize: 11 * App.fontScale
                                        verticalAlignment: Text.AlignVCenter; leftPadding: 8
                                    }
                                    background: Rectangle { color: _ycbDel.hovered ? "#2a3a5a" : ColorPalette.inputBg }
                                }
                                popup: Popup {
                                    y: ytdlpCookieBrowserCombo.height + 2
                                    width: ytdlpCookieBrowserCombo.width
                                    implicitHeight: contentItem.implicitHeight + 4; padding: 2
                                    background: Rectangle { color: ColorPalette.inputBg; border.color: ColorPalette.border; radius: 3 }
                                    contentItem: ListView {
                                        implicitHeight: contentHeight; clip: true
                                        model: ytdlpCookieBrowserCombo.delegateModel
                                    }
                                }
                            }
                        }

                        Text {
                            Layout.fillWidth: true
                            text: qsTr("When set, Stellar will automatically retry yt-dlp downloads that require login using this browser's cookies, without prompting.")
                            color: ColorPalette.textDisabled; font.pixelSize: 11 * App.fontScale
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

                        Text { text: qsTr("Torrent Downloads"); color: ColorPalette.textHeader; font.pixelSize: 16 * App.fontScale; font.bold: true }
                        Rectangle { Layout.fillWidth: true; height: 1; color: ColorPalette.border }

                        // Enable BitTorrent support toggle + legal notice
                        StyledCheckBox {
                            id: torrentEnabledCheck
                            text: qsTr("Enable BitTorrent support")
                            checked: root.editTorrentEnabled
                            topPadding: 0
                            bottomPadding: 0
                            onToggled: {
                                if (checked) {
                                    torrentLegalNotice.open()
                                } else {
                                    root.editTorrentEnabled = false
                                }
                            }
                            contentItem: Text { text: parent.text; color: ColorPalette.textPrimary; font.pixelSize: 13 * App.fontScale; leftPadding: parent.indicator.width + 4 }
                        }

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
                                spacing: 0
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 12
                                    Layout.margins: 20
                                    Text {
                                        text: qsTr("BitTorrent - Legal Notice")
                                        color: ColorPalette.textHeader
                                        font.pixelSize: 15 * App.fontScale
                                        font.bold: true
                                    }
                                    Rectangle { Layout.fillWidth: true; height: 1; color: ColorPalette.border }
                                    Text {
                                        Layout.fillWidth: true
                                        wrapMode: Text.WordWrap
                                        color: ColorPalette.textPrimary
                                        font.pixelSize: 12 * App.fontScale
                                        lineHeight: 1.4
                                        text: qsTr("Stellar is a file-sharing program. When you download a torrent, your IP address becomes visible to other peers in the swarm and you simultaneously upload (seed) data to others.\n\nAnything you share via BitTorrent is your sole responsibility. Ensure you have the right to distribute the content.\n\nIt is strongly recommended to bind Stellar to a VPN network interface and verify that your VPN is active before using torrents, to protect your IP address from exposure.")
                                    }
                                    Rectangle {
                                        Layout.fillWidth: true
                                        height: 1
                                        color: ColorPalette.border
                                    }
                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 8
                                        Item { Layout.fillWidth: true }
                                        DlgButton {
                                            text: qsTr("Cancel")
                                            onClicked: {
                                                torrentLegalNotice.close()
                                                torrentEnabledCheck.checked = false
                                            }
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
                        }

                        // Bind checkbox to editTorrentEnabled (separate from the toggle handler above)
                        Binding { target: torrentEnabledCheck; property: "checked"; value: root.editTorrentEnabled }

                        Text {
                            Layout.fillWidth: true
                            text: qsTr("These settings apply to .torrent files and magnet links.")
                            color: "#909090"; font.pixelSize: 12 * App.fontScale
                            wrapMode: Text.WordWrap
                        }

                        GridLayout {
                            Layout.fillWidth: true
                            columns: 2
                            columnSpacing: 10
                            rowSpacing: 8

                            Text { text: qsTr("Listen port"); color: ColorPalette.textPrimary; font.pixelSize: 12 * App.fontScale }
                            TextField {
                                Layout.preferredWidth: 120
                                text: String(root.editTorrentListenPort)
                                validator: IntValidator { bottom: 1; top: 65535 }
                                color: ColorPalette.textPrimary
                                background: Rectangle { color: ColorPalette.inputBg; border.color: parent.activeFocus ? "#4488dd" : ColorPalette.border; radius: 3 }
                                onTextEdited: { var n = parseInt(text, 10); if (!isNaN(n)) root.editTorrentListenPort = n }
                            }

                            Text { text: qsTr("Global max connections"); color: ColorPalette.textPrimary; font.pixelSize: 12 * App.fontScale }
                            TextField {
                                Layout.preferredWidth: 120
                                text: String(root.editTorrentConnectionsLimit)
                                validator: IntValidator { bottom: 1; top: 100000 }
                                color: ColorPalette.textPrimary
                                background: Rectangle { color: ColorPalette.inputBg; border.color: parent.activeFocus ? "#4488dd" : ColorPalette.border; radius: 3 }
                                onTextEdited: { var n = parseInt(text, 10); if (!isNaN(n) && n >= 1) root.editTorrentConnectionsLimit = n }
                            }

                            Text { text: qsTr("Max connections per torrent"); color: ColorPalette.textPrimary; font.pixelSize: 12 * App.fontScale }
                            TextField {
                                Layout.preferredWidth: 120
                                text: String(root.editTorrentConnectionsLimitPerTorrent)
                                validator: IntValidator { bottom: 0; top: 100000 }
                                color: ColorPalette.textPrimary
                                background: Rectangle { color: ColorPalette.inputBg; border.color: parent.activeFocus ? "#4488dd" : ColorPalette.border; radius: 3 }
                                onTextEdited: { var n = parseInt(text, 10); if (!isNaN(n) && n >= 0) root.editTorrentConnectionsLimitPerTorrent = n }
                            }

                            Text { text: qsTr("Global max upload slots"); color: ColorPalette.textPrimary; font.pixelSize: 12 * App.fontScale }
                            TextField {
                                Layout.preferredWidth: 120
                                text: String(root.editTorrentUploadSlotsLimit)
                                validator: IntValidator { bottom: 0; top: 100000 }
                                color: ColorPalette.textPrimary
                                background: Rectangle { color: ColorPalette.inputBg; border.color: parent.activeFocus ? "#4488dd" : ColorPalette.border; radius: 3 }
                                onTextEdited: { var n = parseInt(text, 10); if (!isNaN(n) && n >= 0) root.editTorrentUploadSlotsLimit = n }
                            }

                            Text { text: qsTr("Max upload slots per torrent"); color: ColorPalette.textPrimary; font.pixelSize: 12 * App.fontScale }
                            TextField {
                                Layout.preferredWidth: 120
                                text: String(root.editTorrentUploadSlotsLimitPerTorrent)
                                validator: IntValidator { bottom: 0; top: 100000 }
                                color: ColorPalette.textPrimary
                                background: Rectangle { color: ColorPalette.inputBg; border.color: parent.activeFocus ? "#4488dd" : ColorPalette.border; radius: 3 }
                                onTextEdited: { var n = parseInt(text, 10); if (!isNaN(n) && n >= 0) root.editTorrentUploadSlotsLimitPerTorrent = n }
                            }

                            Item {}
                            Text { text: qsTr("0 = unlimited (per-torrent fields and global upload slots)"); color: ColorPalette.textDisabled; font.pixelSize: 10 * App.fontScale }

                            Text { text: qsTr("Protocol"); color: ColorPalette.textPrimary; font.pixelSize: 12 * App.fontScale }
                            ComboBox {
                                id: torrentProtocolCombo
                                Layout.preferredWidth: 160
                                model: [qsTr("TCP and µTP"), qsTr("µTP only"), qsTr("TCP only")]
                                currentIndex: root.editTorrentProtocol
                                font.pixelSize: 12 * App.fontScale
                                background: Rectangle { color: ColorPalette.dividerBg; border.color: torrentProtocolCombo.activeFocus ? "#4488dd" : ColorPalette.border; radius: 3 }
                                contentItem: Text {
                                    leftPadding: 8
                                    text: torrentProtocolCombo.displayText
                                    color: ColorPalette.textPrimary; font: torrentProtocolCombo.font
                                    verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight
                                }
                                onActivated: root.editTorrentProtocol = currentIndex
                            }
                        }

                        Rectangle { Layout.fillWidth: true; height: 1; color: "#2a2a2a" }

                        Text { text: qsTr("Port Test"); color: ColorPalette.textHeader; font.pixelSize: 14 * App.fontScale; font.bold: true }

                        Text {
                            Layout.fillWidth: true
                            text: qsTr("Test whether your current torrent listen port is reachable from the public internet. This helps confirm whether your VPN port forwarding, router forwarding, and firewall rules are actually allowing inbound torrent connections.")
                            color: ColorPalette.textDisabled
                            font.pixelSize: 11 * App.fontScale
                            wrapMode: Text.WordWrap
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 10

                            DlgButton {
                                text: App.torrentPortTestInProgress ? qsTr("Testing...") : qsTr("Test Port")
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
                                        return ColorPalette.textPrimary
                                    return "#a0a0a0"
                                }
                                font.pixelSize: 11 * App.fontScale
                                wrapMode: Text.WordWrap
                            }
                        }

                        Rectangle { Layout.fillWidth: true; height: 1; color: "#2a2a2a" }

                        Text { text: qsTr("Networking"); color: ColorPalette.textHeader; font.pixelSize: 14 * App.fontScale; font.bold: true }

                        component NetCheckRow: RowLayout {
                            property alias cbChecked: cb.checked
                            property alias label: labelText.text
                            property alias description: descText.text
                            signal toggled(bool checked)
                            spacing: 8
                            StyledCheckBox {
                                id: cb
                                topPadding: 0; bottomPadding: 0
                                Layout.alignment: Qt.AlignTop
                                onCheckedChanged: parent.toggled(checked)
                            }
                            ColumnLayout {
                                spacing: 1
                                Layout.fillWidth: true
                                Text { id: labelText; color: ColorPalette.textPrimary; font.pixelSize: 13 * App.fontScale }
                                Text {
                                    id: descText
                                    color: "#777777"; font.pixelSize: 11 * App.fontScale
                                    Layout.fillWidth: true
                                    wrapMode: Text.WordWrap
                                }
                            }
                        }

                        NetCheckRow {
                            label: "DHT"
                            description: qsTr("Find peers without a tracker using a distributed hash table.")
                            cbChecked: root.editTorrentEnableDht
                            onToggled: (v) => root.editTorrentEnableDht = v
                        }
                        NetCheckRow {
                            label: "LSD"
                            description: qsTr("Discover peers on your local network without going through the internet.")
                            cbChecked: root.editTorrentEnableLsd
                            onToggled: (v) => root.editTorrentEnableLsd = v
                        }
                        NetCheckRow {
                            label: "UPnP"
                            description: qsTr("Automatically open a port on your router so peers can connect to you.")
                            cbChecked: root.editTorrentEnableUpnp
                            onToggled: (v) => root.editTorrentEnableUpnp = v
                        }
                        NetCheckRow {
                            label: "NAT-PMP"
                            description: qsTr("Like UPnP but for Apple routers - enable both and whichever your router supports will be used.")
                            cbChecked: root.editTorrentEnableNatPmp
                            onToggled: (v) => root.editTorrentEnableNatPmp = v
                        }
                        NetCheckRow {
                            label: "PeX (Peer Exchange)"
                            description: qsTr("Share peer lists between connected peers so you find more sources without hitting the tracker.")
                            cbChecked: root.editTorrentEnablePex
                            onToggled: (v) => root.editTorrentEnablePex = v
                        }

                        Rectangle { Layout.fillWidth: true; height: 1; color: "#2a2a2a" }

                        Text { text: qsTr("Advanced"); color: ColorPalette.textHeader; font.pixelSize: 14 * App.fontScale; font.bold: true }

                        Text { text: qsTr("Custom bittorrent user agent"); color: ColorPalette.textPrimary; font.pixelSize: 12 * App.fontScale }
                        TextField {
                            Layout.fillWidth: true
                            text: root.editTorrentCustomUserAgent
                            placeholderText: qsTr("Default: Stellar/%1").arg(App.appVersion)
                            onTextChanged: root.editTorrentCustomUserAgent = text
                            color: ColorPalette.textPrimary
                            background: Rectangle { color: ColorPalette.inputBg; border.color: parent.activeFocus ? "#4488dd" : ColorPalette.border; radius: 3 }
                        }

                        Text { text: qsTr("Network interface"); color: ColorPalette.textPrimary; font.pixelSize: 12 * App.fontScale }

                        ComboBox {
                            id: torrentAdapterCombo
                            Layout.fillWidth: true
                            model: root.torrentAdapterOptions
                            currentIndex: root.indexOfTorrentAdapter(root.editTorrentBindInterface)
                            font.pixelSize: 12 * App.fontScale
                            background: Rectangle { color: ColorPalette.dividerBg; border.color: "#4a4a4a"; radius: 3 }
                            contentItem: Text {
                                leftPadding: 8
                                text: {
                                    var option = torrentAdapterCombo.currentIndex >= 0 && torrentAdapterCombo.currentIndex < root.torrentAdapterOptions.length
                                        ? root.torrentAdapterOptions[torrentAdapterCombo.currentIndex]
                                        : null
                                    return option ? option.name : qsTr("Any interface")
                                }
                                color: ColorPalette.textPrimary
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
                                        color: ColorPalette.textPrimary
                                        font.pixelSize: 12 * App.fontScale
                                        elide: Text.ElideRight
                                    }
                                    Text {
                                        text: modelData.details || ""
                                        color: "#808080"
                                        font.pixelSize: 11 * App.fontScale
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

                        // Honest explainer: empty = follow system route; named = hard bind + fail-closed.
                        Text {
                            Layout.fillWidth: true
                            text: root.editTorrentBindInterface.length > 0
                                  ? qsTr("Torrent traffic is locked to this interface. If your VPN disconnects or the interface goes away, Stellar pauses torrents instead of leaking onto another connection. Bind to your VPN adapter to route all torrent traffic, including IPv6, through the VPN.")
                                  : qsTr("Any interface: torrent traffic follows the system route, just like your other apps. If a VPN is your active connection it goes through the VPN; if the VPN drops, traffic continues on the normal connection. Pick a specific adapter for strict VPN-only binding.")
                            color: ColorPalette.textPrimary
                            font.pixelSize: 11 * App.fontScale
                            wrapMode: Text.WordWrap
                        }

                        // Allow LAN discovery while bound (advanced). Default off = harden.
                        StyledCheckBox {
                            visible: root.editTorrentBindInterface.length > 0
                            text: qsTr("Allow UPnP, NAT-PMP and Local Service Discovery while bound")
                            topPadding: 0; bottomPadding: 0
                            checked: root.editTorrentAllowDiscoveryWhenBound
                            onCheckedChanged: root.editTorrentAllowDiscoveryWhenBound = checked
                            contentItem: Text {
                                text: parent.text
                                color: ColorPalette.textPrimary
                                font.pixelSize: 13 * App.fontScale
                                leftPadding: parent.indicator.width + 4
                                verticalAlignment: Text.AlignVCenter
                                wrapMode: Text.WordWrap
                            }
                        }

                        Text {
                            Layout.fillWidth: true
                            visible: root.editTorrentBindInterface.length > 0
                            text: root.editTorrentAllowDiscoveryWhenBound
                                  ? qsTr("These talk to your local router and can expose your listen port around the tunnel. Only enable this when binding to a trusted LAN adapter, not a VPN.")
                                  : qsTr("UPnP, NAT-PMP and Local Service Discovery are disabled while bound, since they talk to the local router and would expose your listen port around the tunnel.")
                            color: "#8899bb"
                            font.pixelSize: 11 * App.fontScale
                            wrapMode: Text.WordWrap
                        }

                        Text {
                            Layout.fillWidth: true
                            visible: root.editTorrentBindInterface.length > 0
                            text: root.torrentAdapterDetails(root.editTorrentBindInterface)
                            color: ColorPalette.textDisabled
                            font.pixelSize: 11 * App.fontScale
                            wrapMode: Text.WordWrap
                        }

                        Rectangle { Layout.fillWidth: true; height: 1; color: "#2a2a2a" }

                        Text { text: qsTr("Storage"); color: ColorPalette.textHeader; font.pixelSize: 14 * App.fontScale; font.bold: true }

                        // Allocation mode radio group
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 4

                            Text { text: qsTr("Allocation mode"); color: "#a0a0a0"; font.pixelSize: 11 * App.fontScale }

                            RowLayout {
                                spacing: 16

                                StyledRadioButton {
                                    id: storageSparseRadio
                                    text: qsTr("Sparse")
                                    checked: root.editTorrentStorageMode === 0
                                    onToggled: if (checked) root.editTorrentStorageMode = 0
                                    topPadding: 0; bottomPadding: 0
                                    contentItem: Text {
                                        text: parent.text
                                        color: ColorPalette.textPrimary
                                        font.pixelSize: 13 * App.fontScale
                                        leftPadding: parent.indicator.width + 4
                                    }
                                }

                                StyledRadioButton {
                                    text: qsTr("Pre-allocate")
                                    checked: root.editTorrentStorageMode === 1
                                    onToggled: if (checked) root.editTorrentStorageMode = 1
                                    topPadding: 0; bottomPadding: 0
                                    contentItem: Text {
                                        text: parent.text
                                        color: ColorPalette.textPrimary
                                        font.pixelSize: 13 * App.fontScale
                                        leftPadding: parent.indicator.width + 4
                                    }
                                }
                            }

                            Text {
                                Layout.fillWidth: true
                                text: qsTr("Applies to new torrents only. Pre-allocate reserves full disk space immediately; sparse allocates on demand.")
                                color: ColorPalette.textDisabled
                                font.pixelSize: 11 * App.fontScale
                                wrapMode: Text.WordWrap
                            }
                        }

                        StyledCheckBox {
                            text: qsTr("Piece extent affinity")
                            checked: root.editTorrentPieceExtentAffinity
                            onToggled: root.editTorrentPieceExtentAffinity = checked
                            topPadding: 0; bottomPadding: 0
                            contentItem: Text { text: parent.text; color: ColorPalette.textPrimary; font.pixelSize: 13 * App.fontScale; leftPadding: parent.indicator.width + 4 }
                        }
                        Text {
                            Layout.fillWidth: true
                            text: qsTr("Download pieces in 4 MiB adjacent extents. Reduces fragmentation on torrents with small piece sizes.")
                            color: ColorPalette.textDisabled
                            font.pixelSize: 11 * App.fontScale
                            wrapMode: Text.WordWrap
                        }

                        StyledCheckBox {
                            text: qsTr("Coalesce disk reads")
                            checked: root.editTorrentCoalesceReads
                            onToggled: root.editTorrentCoalesceReads = checked
                            topPadding: 0; bottomPadding: 0
                            contentItem: Text { text: parent.text; color: ColorPalette.textPrimary; font.pixelSize: 13 * App.fontScale; leftPadding: parent.indicator.width + 4 }
                        }

                        StyledCheckBox {
                            text: qsTr("Coalesce disk writes")
                            checked: root.editTorrentCoalesceWrites
                            onToggled: root.editTorrentCoalesceWrites = checked
                            topPadding: 0; bottomPadding: 0
                            contentItem: Text { text: parent.text; color: ColorPalette.textPrimary; font.pixelSize: 13 * App.fontScale; leftPadding: parent.indicator.width + 4 }
                        }

                        Text {
                            Layout.fillWidth: true
                            text: qsTr("Coalescing merges small I/O operations into larger buffers before writing to disk. May improve throughput on fragmented torrents.")
                            color: ColorPalette.textDisabled
                            font.pixelSize: 11 * App.fontScale
                            wrapMode: Text.WordWrap
                        }

                        // Disk I/O type
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            Text { text: qsTr("Disk I/O type"); color: "#a0a0a0"; font.pixelSize: 11 * App.fontScale; Layout.alignment: Qt.AlignVCenter }

                            ComboBox {
                                id: diskIoTypeCombo
                                implicitWidth: 140
                                model: [qsTr("Default"), qsTr("Memory-mapped"), qsTr("POSIX")]
                                currentIndex: root.editTorrentDiskIoType
                                onActivated: root.editTorrentDiskIoType = currentIndex
                                contentItem: Text {
                                    leftPadding: 8
                                    text: diskIoTypeCombo.displayText
                                    color: ColorPalette.textPrimary
                                    font.pixelSize: 12 * App.fontScale
                                    verticalAlignment: Text.AlignVCenter
                                }
                                background: Rectangle {
                                    color: ColorPalette.inputBg
                                    border.color: diskIoTypeCombo.activeFocus ? "#4488dd" : ColorPalette.border
                                    radius: 3
                                }
                            }
                        }

                        Text {
                            Layout.fillWidth: true
                            text: {
                                switch (root.editTorrentDiskIoType) {
                                case 1: return qsTr("Memory-mapped: files are mapped directly into memory. Windows and Linux read and write torrent data through the page cache with minimal CPU usage. Recommended for most users.")
                                case 2: return qsTr("POSIX: reads and writes go through standard file calls without memory-mapping. Uses less address space than memory-mapped, which can help on 32-bit systems or when seeding many large torrents simultaneously.")
                                default: return qsTr("Default: Stellar picks the best mode for your platform automatically.")
                                }
                            }
                            color: ColorPalette.textDisabled
                            font.pixelSize: 11 * App.fontScale
                            wrapMode: Text.WordWrap
                        }

                        // Disk write queue
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            Text { text: qsTr("Disk write queue"); color: "#a0a0a0"; font.pixelSize: 11 * App.fontScale; Layout.alignment: Qt.AlignVCenter }

                            Rectangle {
                                width: 60; height: 26; radius: 2
                                color: ColorPalette.inputBg
                                border.color: diskQueueField.activeFocus ? "#4488dd" : ColorPalette.border
                                TextInput {
                                    id: diskQueueField
                                    anchors { fill: parent; leftMargin: 6; rightMargin: 6 }
                                    verticalAlignment: TextInput.AlignVCenter
                                    color: ColorPalette.textPrimary
                                    font.pixelSize: 12 * App.fontScale
                                    text: root.editTorrentDiskWriteQueueMiB.toString()
                                    validator: IntValidator { bottom: 1; top: 65536 }
                                    onEditingFinished: {
                                        var v = parseInt(text)
                                        if (!isNaN(v) && v >= 1) root.editTorrentDiskWriteQueueMiB = v
                                    }
                                    Connections {
                                        target: root
                                        function onEditTorrentDiskWriteQueueMiBChanged() {
                                            if (!diskQueueField.activeFocus)
                                                diskQueueField.text = root.editTorrentDiskWriteQueueMiB.toString()
                                        }
                                    }
                                }
                            }

                            Text { text: qsTr("MiB"); color: ColorPalette.textDisabled; font.pixelSize: 11 * App.fontScale; Layout.alignment: Qt.AlignVCenter }
                        }

                        Rectangle { Layout.fillWidth: true; height: 1; color: "#2a2a2a" }

                        Text { text: qsTr("Torrent Security"); color: ColorPalette.textHeader; font.pixelSize: 14 * App.fontScale; font.bold: true }

                        Text {
                            Layout.fillWidth: true
                            text: qsTr("Manual peer bans apply immediately. Blocked user-agent substrings, blocked countries, and auto-ban options apply when you click Apply or OK.")
                            color: ColorPalette.textDisabled
                            font.pixelSize: 11 * App.fontScale
                            wrapMode: Text.WordWrap
                        }

                        Text { text: qsTr("Encryption Mode"); color: ColorPalette.textPrimary; font.pixelSize: 12 * App.fontScale }

                        ComboBox {
                            id: encryptionModeCombo
                            implicitWidth: 220
                            model: [qsTr("Prefer encryption"), qsTr("Require encryption"), qsTr("Allow encryption")]
                            // model index maps: 0=Prefer, 1=Require, 2=Allow - matches torrentEncryptionMode values
                            currentIndex: root.editTorrentEncryptionMode
                            onActivated: root.editTorrentEncryptionMode = currentIndex
                            contentItem: Text {
                                leftPadding: 8
                                text: encryptionModeCombo.displayText
                                color: ColorPalette.textPrimary
                                font.pixelSize: 13 * App.fontScale
                                verticalAlignment: Text.AlignVCenter
                            }
                            background: Rectangle {
                                color: ColorPalette.inputBg
                                border.color: encryptionModeCombo.activeFocus ? "#4488dd" : ColorPalette.border
                                radius: 3
                            }
                            indicator: Text {
                                x: encryptionModeCombo.width - width - 8
                                anchors.verticalCenter: parent.verticalCenter
                                 text: "▾"
                                color: ColorPalette.textMuted
                                font.pixelSize: 10 * App.fontScale
                            }
                            popup: Popup {
                                y: encryptionModeCombo.height
                                width: encryptionModeCombo.width
                                padding: 0
                                background: Rectangle { color: ColorPalette.panelBg; border.color: ColorPalette.border; radius: 3 }
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
                                    color: ColorPalette.textPrimary
                                    font.pixelSize: 13 * App.fontScale
                                    verticalAlignment: Text.AlignVCenter
                                }
                                background: Rectangle {
                                    color: highlighted ? ColorPalette.selectionBg : "transparent"
                                }
                                highlighted: encryptionModeCombo.highlightedIndex === index
                            }
                        }

                        Text { text: qsTr("Blocked user agents"); color: ColorPalette.textPrimary; font.pixelSize: 12 * App.fontScale }
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 96
                            color: ColorPalette.inputBg
                            border.color: blockedPeerAgentsInput.activeFocus ? "#4488dd" : ColorPalette.border
                            radius: 3
                            clip: true

                            ScrollView {
                                anchors.fill: parent
                                TextArea {
                                    id: blockedPeerAgentsInput
                                    text: root.editTorrentBlockedPeerUserAgents
                                    color: ColorPalette.textPrimary
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
                            text: qsTr("One substring per line. If a peer client string contains any line above, Stellar auto-bans that peer until the matching line is removed and the settings are applied.")
                            color: ColorPalette.textDisabled
                            font.pixelSize: 11 * App.fontScale
                            wrapMode: Text.WordWrap
                        }

                        Text { text: qsTr("Manually ban peer"); color: ColorPalette.textPrimary; font.pixelSize: 12 * App.fontScale }
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            TextField {
                                Layout.fillWidth: true
                                text: root.manualBanPeerText
                                placeholderText: qsTr("IP address, for example 203.0.113.42")
                                color: ColorPalette.textPrimary
                                background: Rectangle {
                                    color: ColorPalette.inputBg
                                    border.color: parent.activeFocus ? "#4488dd" : ColorPalette.border
                                    radius: 3
                                }
                                onTextChanged: root.manualBanPeerText = text
                            }

                            DlgButton {
                                text: qsTr("Ban")
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
                            text: qsTr("Manual bans are permanent until you remove them from the banned peers list below.")
                            color: ColorPalette.textDisabled
                            font.pixelSize: 11 * App.fontScale
                            wrapMode: Text.WordWrap
                        }

                        Text { text: qsTr("Block peers by country"); color: ColorPalette.textPrimary; font.pixelSize: 12 * App.fontScale }
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
                                background: Rectangle { color: ColorPalette.dividerBg; border.color: "#4a4a4a"; radius: 3 }
                                contentItem: Text {
                                    leftPadding: 8
                                    text: {
                                        var option = blockedCountryCombo.currentIndex >= 0 && blockedCountryCombo.currentIndex < root.torrentCountryOptions.length
                                            ? root.torrentCountryOptions[blockedCountryCombo.currentIndex]
                                            : null
                                        return option ? ((option.code || "") + " - " + (option.name || "")) : ""
                                    }
                                    color: ColorPalette.textPrimary
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
                                        color: ColorPalette.panelBg
                                        border.color: ColorPalette.border
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
                                        color: ColorPalette.textPrimary
                                        font.pixelSize: 12 * App.fontScale
                                        elide: Text.ElideRight
                                    }
                                }
                            }

                            DlgButton {
                                text: qsTr("Add")
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
                                    color: ColorPalette.panelBg
                                    border.color: ColorPalette.border
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
                                            color: ColorPalette.textPrimary
                                            font.pixelSize: 12 * App.fontScale
                                            elide: Text.ElideRight
                                        }
                                        DlgButton {
                                            text: qsTr("Remove")
                                            Layout.alignment: Qt.AlignVCenter
                                            Layout.preferredHeight: 28
                                            onClicked: root.removeBlockedTorrentCountry(modelData)
                                        }
                                    }
                                }
                            }

                            Text {
                                visible: root.editTorrentBlockedPeerCountries.length === 0
                                text: qsTr("No blocked countries.")
                                color: ColorPalette.textDisabled
                                font.pixelSize: 11 * App.fontScale
                            }
                        }

                        StyledCheckBox {
                            text: qsTr("Auto Ban Xunlei, QQ, Baidu, Xfplay, DLBT and Offline downloader")
                            topPadding: 0
                            bottomPadding: 0
                            checked: root.editTorrentAutoBanAbusivePeers
                            onCheckedChanged: root.editTorrentAutoBanAbusivePeers = checked
                            contentItem: Text {
                                text: parent.text
                                color: ColorPalette.textPrimary
                                font.pixelSize: 13 * App.fontScale
                                leftPadding: parent.indicator.width + 4
                                wrapMode: Text.WordWrap
                            }
                        }

                        StyledCheckBox {
                            text: qsTr("Auto Ban BitTorrent Media Player Peer")
                            topPadding: 0
                            bottomPadding: 0
                            checked: root.editTorrentAutoBanMediaPlayerPeers
                            onCheckedChanged: root.editTorrentAutoBanMediaPlayerPeers = checked
                            contentItem: Text {
                                text: parent.text
                                color: ColorPalette.textPrimary
                                font.pixelSize: 13 * App.fontScale
                                leftPadding: parent.indicator.width + 4
                                wrapMode: Text.WordWrap
                            }
                        }

                        Text { text: qsTr("Manually banned peers"); color: ColorPalette.textPrimary; font.pixelSize: 12 * App.fontScale }
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 160
                            color: ColorPalette.inputBg
                            border.color: ColorPalette.border
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
                                    color: ColorPalette.rowAltBg
                                    border.color: ColorPalette.border

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
                                                color: ColorPalette.textPrimary
                                                font.pixelSize: 12 * App.fontScale
                                                font.bold: true
                                                elide: Text.ElideRight
                                                Layout.fillWidth: true
                                            }
                                            Text {
                                                text: (modelData.reason || "")
                                                      + ((modelData.countryCode || "").length > 0 ? (" . " + modelData.countryCode) : "")
                                                      + ((modelData.client || "").length > 0 ? (" . " + modelData.client) : "")
                                                color: "#8ea1b5"
                                                font.pixelSize: 11 * App.fontScale
                                                elide: Text.ElideRight
                                                Layout.fillWidth: true
                                            }
                                        }

                                        DlgButton {
                                            text: modelData.permanent ? qsTr("Unban") : qsTr("Active")
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
                                    text: qsTr("No banned peers")
                                    color: ColorPalette.textDisabled
                                    font.pixelSize: 12 * App.fontScale
                                }
                            }
                        }

                        Rectangle { Layout.fillWidth: true; height: 1; color: "#2a2a2a" }

                        Text { text: qsTr("IP-to-City Database"); color: ColorPalette.textHeader; font.pixelSize: 14 * App.fontScale; font.bold: true }

                        GridLayout {
                            Layout.fillWidth: true
                            columns: 2
                            columnSpacing: 10
                            rowSpacing: 6

                            Text { text: qsTr("Version"); color: "#a0a0a0"; font.pixelSize: 11 * App.fontScale }
                            Text {
                                Layout.fillWidth: true
                                text: root.ipToCityDbInfo.versionStatus || qsTr("Unknown")
                                color: ColorPalette.textPrimary
                                font.pixelSize: 11 * App.fontScale
                                wrapMode: Text.WordWrap
                            }

                            Text { text: qsTr("Path"); color: "#a0a0a0"; font.pixelSize: 11 * App.fontScale }
                            Text {
                                Layout.fillWidth: true
                                text: root.ipToCityDbInfo.path || qsTr("Not found")
                                color: ColorPalette.textPrimary
                                font.pixelSize: 11 * App.fontScale
                                wrapMode: Text.WrapAnywhere
                            }

                            Text { text: qsTr("Size"); color: "#a0a0a0"; font.pixelSize: 11 * App.fontScale }
                            Text {
                                text: root.formatBytes(root.ipToCityDbInfo.sizeBytes || 0)
                                color: ColorPalette.textPrimary
                                font.pixelSize: 11 * App.fontScale
                            }

                            Text { text: qsTr("Entries"); color: "#a0a0a0"; font.pixelSize: 11 * App.fontScale }
                            Text {
                                text: root.ipToCityDbInfo.entryCountFormatted || qsTr("Unknown")
                                color: ColorPalette.textPrimary
                                font.pixelSize: 11 * App.fontScale
                            }

                            Text { text: qsTr("Last Modified"); color: "#a0a0a0"; font.pixelSize: 11 * App.fontScale }
                            Text {
                                text: root.ipToCityDbInfo.lastModified || qsTr("Unknown")
                                color: ColorPalette.textPrimary
                                font.pixelSize: 11 * App.fontScale
                            }

                            Text { text: qsTr("Status"); color: "#a0a0a0"; font.pixelSize: 11 * App.fontScale }
                            Text {
                                text: App.ipToCityDbUpdateStatus.length > 0
                                    ? App.ipToCityDbUpdateStatus
                                    : (root.ipToCityDbInfo.loaded ? qsTr("Loaded") : qsTr("Available but not loaded"))
                                color: App.ipToCityDbUpdateStatus.length > 0 ? "#cccccc" : "#8ab4f8"
                                font.pixelSize: 11 * App.fontScale
                                wrapMode: Text.WordWrap
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
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

                        Text {
                            Layout.fillWidth: true
                            text: App.ipToCityDbUpdateUrl && App.ipToCityDbUpdateUrl.length > 0
                                ? qsTr("Source: %1").arg(App.ipToCityDbUpdateUrl)
                                : qsTr("Resolved automatically from db-ip.com when you update.")
                            color: ColorPalette.textDisabled
                            font.pixelSize: 11 * App.fontScale
                            wrapMode: Text.WordWrap
                        }

                        Rectangle { Layout.fillWidth: true; height: 1; color: "#2a2a2a" }

                        Text { text: qsTr("Statistics"); color: ColorPalette.textHeader; font.pixelSize: 14 * App.fontScale; font.bold: true }

                        Text {
                            Layout.fillWidth: true
                            text: qsTr("Cumulative transfer totals across all torrents, including removed ones.")
                            color: ColorPalette.textDisabled
                            font.pixelSize: 11 * App.fontScale
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

                            Text { text: qsTr("Total Downloaded"); color: ColorPalette.infoBoxText; font.pixelSize: 12 * App.fontScale }
                            Text {
                                text: root.formatBytes(torrentStatsGrid.stats.downloadedBytes || 0)
                                color: ColorPalette.textPrimary; font.pixelSize: 12 * App.fontScale
                            }

                            Text { text: qsTr("Total Uploaded"); color: ColorPalette.infoBoxText; font.pixelSize: 12 * App.fontScale }
                            Text {
                                text: root.formatBytes(torrentStatsGrid.stats.uploadedBytes || 0)
                                color: ColorPalette.textPrimary; font.pixelSize: 12 * App.fontScale
                            }

                            Text { text: qsTr("All-time Share Ratio"); color: ColorPalette.infoBoxText; font.pixelSize: 12 * App.fontScale }
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
                                font.pixelSize: 12 * App.fontScale
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

                        Text { text: qsTr("RSS"); color: ColorPalette.textHeader; font.pixelSize: 16 * App.fontScale; font.bold: true }
                        Rectangle { Layout.fillWidth: true; height: 1; color: ColorPalette.border }

                        Text {
                            Layout.fillWidth: true
                            text: qsTr("Configure RSS feed fetching and automatic torrent downloading rules.")
                            color: "#909090"; font.pixelSize: 12 * App.fontScale
                            wrapMode: Text.WordWrap
                        }

                        // ?? Feed fetching ??????????????????????????????????????????????
                        Rectangle { Layout.fillWidth: true; height: 1; color: "#2a2a2a" }
                        Text { text: qsTr("Feed Fetching"); color: ColorPalette.textHeader; font.pixelSize: 14 * App.fontScale; font.bold: true }

                        StyledCheckBox {
                            text: qsTr("Enable fetching RSS feeds")
                            topPadding: 0; bottomPadding: 0
                            checked: root.editRssEnabled
                            onCheckedChanged: root.editRssEnabled = checked
                            contentItem: Text { text: parent.text; color: ColorPalette.textPrimary; font.pixelSize: 13 * App.fontScale; leftPadding: parent.indicator.width + 4 }
                        }

                        GridLayout {
                            Layout.fillWidth: true
                            columns: 3
                            columnSpacing: 10
                            rowSpacing: 8
                            enabled: root.editRssEnabled

                            Text { text: qsTr("Feeds refresh interval"); color: ColorPalette.textPrimary; font.pixelSize: 12 * App.fontScale }
                            TextField {
                                Layout.preferredWidth: 80
                                text: String(root.editRssRefreshIntervalMins)
                                validator: IntValidator { bottom: 1; top: 1440 }
                                color: ColorPalette.textPrimary; font.pixelSize: 12 * App.fontScale
                                leftPadding: 6; rightPadding: 6; selectByMouse: true
                                background: Rectangle {
                                    color: ColorPalette.inputBg
                                    border.color: parent.activeFocus ? "#4488dd" : ColorPalette.border; radius: 3
                                }
                                onTextChanged: {
                                    var n = parseInt(text, 10)
                                    if (!isNaN(n) && n >= 1) root.editRssRefreshIntervalMins = n
                                }
                            }
                            Text { text: qsTr("minutes"); color: ColorPalette.textDisabled; font.pixelSize: 12 * App.fontScale }

                            Text { text: qsTr("Same host request delay"); color: ColorPalette.textPrimary; font.pixelSize: 12 * App.fontScale }
                            TextField {
                                Layout.preferredWidth: 80
                                text: String(Math.round(root.editRssSameHostDelayMs / 1000))
                                validator: IntValidator { bottom: 0; top: 60 }
                                color: ColorPalette.textPrimary; font.pixelSize: 12 * App.fontScale
                                leftPadding: 6; rightPadding: 6; selectByMouse: true
                                background: Rectangle {
                                    color: ColorPalette.inputBg
                                    border.color: parent.activeFocus ? "#4488dd" : ColorPalette.border; radius: 3
                                }
                                onTextChanged: {
                                    var n = parseInt(text, 10)
                                    if (!isNaN(n) && n >= 0) root.editRssSameHostDelayMs = n * 1000
                                }
                            }
                            Text { text: qsTr("seconds"); color: ColorPalette.textDisabled; font.pixelSize: 12 * App.fontScale }

                            Text { text: qsTr("Maximum articles per feed"); color: ColorPalette.textPrimary; font.pixelSize: 12 * App.fontScale }
                            TextField {
                                Layout.preferredWidth: 80
                                text: String(root.editRssMaxArticlesPerFeed)
                                validator: IntValidator { bottom: 1; top: 10000 }
                                color: ColorPalette.textPrimary; font.pixelSize: 12 * App.fontScale
                                leftPadding: 6; rightPadding: 6; selectByMouse: true
                                background: Rectangle {
                                    color: ColorPalette.inputBg
                                    border.color: parent.activeFocus ? "#4488dd" : ColorPalette.border; radius: 3
                                }
                                onTextChanged: {
                                    var n = parseInt(text, 10)
                                    if (!isNaN(n) && n >= 1) root.editRssMaxArticlesPerFeed = n
                                }
                            }
                            Item {}
                        }

                        // ?? Auto downloader ????????????????????????????????????????????
                        Rectangle { Layout.fillWidth: true; height: 1; color: "#2a2a2a" }
                        Text { text: qsTr("Torrent Auto Downloader"); color: ColorPalette.textHeader; font.pixelSize: 14 * App.fontScale; font.bold: true }

                        StyledCheckBox {
                            text: qsTr("Enable auto downloading of RSS torrents")
                            topPadding: 0; bottomPadding: 0
                            checked: root.editRssAutoDownloadEnabled
                            onCheckedChanged: root.editRssAutoDownloadEnabled = checked
                            contentItem: Text { text: parent.text; color: ColorPalette.textPrimary; font.pixelSize: 13 * App.fontScale; leftPadding: parent.indicator.width + 4 }
                        }

                        DlgButton {
                            text: qsTr("Edit Auto Downloading Rules...")
                            onClicked: {
                                rssDownloadRulesDialog.show()
                                rssDownloadRulesDialog.raise()
                                rssDownloadRulesDialog.requestActivate()
                            }
                        }

                        // ?? Smart episode filter ???????????????????????????????????????
                        Rectangle { Layout.fillWidth: true; height: 1; color: "#2a2a2a" }
                        Text { text: qsTr("Smart Episode Filter"); color: ColorPalette.textHeader; font.pixelSize: 14 * App.fontScale; font.bold: true }

                        StyledCheckBox {
                            text: qsTr("Download REPACK/PROPER episodes")
                            topPadding: 0; bottomPadding: 0
                            checked: root.editRssSmartFilterRepack
                            onCheckedChanged: root.editRssSmartFilterRepack = checked
                            contentItem: Text { text: parent.text; color: ColorPalette.textPrimary; font.pixelSize: 13 * App.fontScale; leftPadding: parent.indicator.width + 4 }
                        }

                        Text { text: qsTr("Episode detection patterns (one per line):"); color: ColorPalette.textPrimary; font.pixelSize: 12 * App.fontScale }

                        Rectangle {
                            Layout.fillWidth: true
                            height: 110
                            color: ColorPalette.inputBg
                            border.color: rssFiltersArea.activeFocus ? "#4488dd" : ColorPalette.border
                            radius: 3

                            ScrollView {
                                anchors.fill: parent
                                anchors.margins: 4
                                clip: true
                                ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

                                TextArea {
                                    id: rssFiltersArea
                                    font.pixelSize: 12 * App.fontScale
                                    font.family: "Consolas, monospace"
                                    color: ColorPalette.textPrimary
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
                            text: qsTr("These regular expressions are used to extract season/episode numbers for smart duplicate detection.")
                            color: ColorPalette.textDisabled; font.pixelSize: 11 * App.fontScale
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

                        Text { text: qsTr("Associations"); color: ColorPalette.textHeader; font.pixelSize: 16 * App.fontScale; font.bold: true }
                        Rectangle { Layout.fillWidth: true; height: 1; color: ColorPalette.border }

                        Text {
                            Layout.fillWidth: true
                            text: qsTr("Make Stellar the default app for .torrent files and magnet links. On Windows 10/11, click the button then confirm the change in the Windows Default Apps settings page that opens.")
                            color: "#909090"
                            font.pixelSize: 12 * App.fontScale
                            wrapMode: Text.WordWrap
                        }

                        Rectangle { Layout.fillWidth: true; height: 1; color: "#2a2a2a" }

                        GridLayout {
                            Layout.fillWidth: true
                            columns: 2
                            columnSpacing: 16
                            rowSpacing: 8

                            Text { text: qsTr(".torrent files"); color: ColorPalette.textPrimary; font.pixelSize: 13 * App.fontScale }
                            Text {
                                Layout.fillWidth: true
                                text: root.torrentAssociationDefault ? qsTr("Currently handled by Stellar") : qsTr("Stellar is not the current default")
                                color: root.torrentAssociationDefault ? "#3a9d52" : ColorPalette.warningText
                                font.pixelSize: 12 * App.fontScale
                                wrapMode: Text.WordWrap
                            }

                            Item { Layout.columnSpan: 2; Layout.fillWidth: true; implicitHeight: torrentAssocButtons.implicitHeight
                                RowLayout {
                                    id: torrentAssocButtons
                                    anchors.left: parent.left
                                    spacing: 8
                                    DlgButton {
                                        text: qsTr("Set .torrent Default")
                                        onClicked: root.showAssociationResult(App.setTorrentFileAssociationDefault(), qsTr("Stellar is now the default app for .torrent files."))
                                    }
                                    DlgButton {
                                        text: qsTr("Refresh Status")
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

                            Text { text: qsTr("magnet: links"); color: ColorPalette.textPrimary; font.pixelSize: 13 * App.fontScale }
                            Text {
                                Layout.fillWidth: true
                                text: root.magnetAssociationDefault ? qsTr("Currently handled by Stellar") : qsTr("Stellar is not the current default")
                                color: root.magnetAssociationDefault ? "#3a9d52" : ColorPalette.warningText
                                font.pixelSize: 12 * App.fontScale
                                wrapMode: Text.WordWrap
                            }

                            Item { Layout.columnSpan: 2; Layout.fillWidth: true; implicitHeight: magnetAssocButtons.implicitHeight
                                RowLayout {
                                    id: magnetAssocButtons
                                    anchors.left: parent.left
                                    spacing: 8
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
                            }
                        }

                        Rectangle { Layout.fillWidth: true; height: 1; color: "#2a2a2a" }

                        Text {
                            Layout.fillWidth: true
                            text: root.associationStatusText.length > 0
                                ? root.associationStatusText
                                : qsTr("If your desktop environment overrides the app-level association, refresh the status after the system finishes applying the change.")
                            color: root.associationStatusText.length > 0 && root.associationStatusText.indexOf("Failed") === 0 ? "#ff8a80" : "#808080"
                            font.pixelSize: 11 * App.fontScale
                            wrapMode: Text.WordWrap
                        }

                        Item { Layout.fillHeight: true }
                    }
                    }
                }

                // Language
                Item {
                    ColumnLayout {
                        width: parent.width
                        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
                        spacing: 10

                        Text { text: qsTr("Interface Language"); color: ColorPalette.textHeader; font.pixelSize: 16 * App.fontScale; font.bold: true }
                        Rectangle { Layout.fillWidth: true; height: 1; color: ColorPalette.border }

                        Text {
                            text: qsTr("Select the language used throughout the Stellar interface. A restart is required for all text to update.")
                            color: ColorPalette.textSecond
                            font.pixelSize: 12 * App.fontScale
                            wrapMode: Text.WordWrap
                            Layout.fillWidth: true
                        }

                        Rectangle { Layout.fillWidth: true; height: 1; color: "#2a2a2a" }

                        RowLayout {
                            spacing: 10

                            Text {
                                text: qsTr("Language:")
                                color: ColorPalette.textPrimary
                                font.pixelSize: 13 * App.fontScale
                            }

                            ComboBox {
                                id: languageCombo
                                implicitWidth: 220
                                implicitHeight: 28

                                // Shared list (UTF-8 native names) from the LanguageList singleton.
                                readonly property var langEntries: LanguageList.entries

                                model: langEntries.map(function(e) { return e.display })

                                // Sync combo selection ? editUiLanguage
                                onActivated: function(idx) {
                                    root.editUiLanguage = langEntries[idx].code
                                }

                                // Sync editUiLanguage ? combo selection on open / reset
                                function syncFromSetting() {
                                    for (var i = 0; i < langEntries.length; ++i) {
                                        if (langEntries[i].code === root.editUiLanguage) {
                                            currentIndex = i
                                            return
                                        }
                                    }
                                    currentIndex = 0
                                }

                                Component.onCompleted: syncFromSetting()

                                Connections {
                                    target: root
                                    function onEditUiLanguageChanged() { languageCombo.syncFromSetting() }
                                }

                                background: Rectangle {
                                    color: ColorPalette.inputBg
                                    border.color: languageCombo.activeFocus ? "#4488dd" : ColorPalette.border
                                    border.width: 1
                                    radius: 2
                                }

                                contentItem: Text {
                                    leftPadding: 8
                                    rightPadding: languageCombo.indicator.width + 4
                                    text: languageCombo.displayText
                                    color: ColorPalette.textPrimary
                                    font.pixelSize: 12 * App.fontScale
                                    verticalAlignment: Text.AlignVCenter
                                    elide: Text.ElideRight
                                }

                                indicator: Text {
                                    x: languageCombo.width - width - 8
                                    y: (languageCombo.height - height) / 2
                                     text: "▾"
                                    font.pixelSize: 8 * App.fontScale
                                    color: ColorPalette.textSecond
                                }

                                popup: Popup {
                                    parent: Overlay.overlay
                                    x: languageCombo.mapToItem(Overlay.overlay, 0, 0).x
                                    y: languageCombo.mapToItem(Overlay.overlay, 0, languageCombo.height + 2).y
                                    width: languageCombo.width
                                    padding: 1
                                    clip: true
                                    z: 10000
                                    implicitHeight: Math.min(contentItem.implicitHeight + 2, 280)
                                    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutsideParent

                                    background: Rectangle {
                                        color: ColorPalette.panelBg
                                        border.color: ColorPalette.border
                                        border.width: 1
                                        radius: 2
                                    }

                                    contentItem: ListView {
                                        clip: true
                                        implicitHeight: contentHeight
                                        model: languageCombo.popup.visible ? languageCombo.delegateModel : null
                                        currentIndex: languageCombo.highlightedIndex

                                        ScrollBar.vertical: ScrollBar { }
                                    }
                                }

                                delegate: ItemDelegate {
                                    width: languageCombo.width
                                    highlighted: languageCombo.highlightedIndex === index

                                    contentItem: Text {
                                        text: modelData
                                        color: ColorPalette.textPrimary
                                        font.pixelSize: 12 * App.fontScale
                                        verticalAlignment: Text.AlignVCenter
                                        leftPadding: 8
                                    }

                                    background: Rectangle {
                                        color: highlighted ? ColorPalette.selectionBg : "transparent"
                                    }
                                }
                            }
                        }

                        Rectangle { Layout.fillWidth: true; height: 1; color: ColorPalette.border; Layout.topMargin: 4 }

                        Text {
                            text: qsTr("A restart is required after changing the language.")
                            color: ColorPalette.infoBoxText
                            font.pixelSize: 11 * App.fontScale
                            Layout.bottomMargin: 8
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

                        // ?? Identity block ????????????????????????????????????????????
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
                                    color: ColorPalette.textHeader; font.pixelSize: 15 * App.fontScale; font.bold: true
                                }

                                // Version + update status on the same line
                                RowLayout {
                                    spacing: 10

                                    Text {
                                        text: qsTr("Version %1 Beta").arg(App.appVersion)
                                        color: "#4488dd"; font.pixelSize: 12 * App.fontScale
                                    }

                                    // Separator dot - only visible when update info is shown
                                    Text {
                                        text: "\u00B7"
                                        color: "#444444"; font.pixelSize: 12 * App.fontScale
                                        visible: App.updateAvailable
                                    }

                                    Text {
                                        text: App.updateAvailable
                                              ? qsTr("Update available: %1").arg(App.updateVersion)
                                              : ""
                                        color: "#55bb77"; font.pixelSize: 12 * App.fontScale
                                        visible: App.updateAvailable
                                    }
                                }

                                // Check for updates + What's New - inline, understated
                                RowLayout {
                                    spacing: 10
                                    Layout.topMargin: 1

                                    Text {
                                        text: qsTr("Check for updates")
                                        color: "#555555"; font.pixelSize: 11 * App.fontScale; font.underline: true
                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: App.checkForUpdates(true)
                                            onEntered: parent.color = "#4488dd"
                                            onExited:  parent.color = "#555555"
                                        }
                                    }
                                    Text { text: "\u00B7"; color: "#333333"; font.pixelSize: 11 * App.fontScale }
                                    Text {
                                        text: qsTr("What's New")
                                        color: "#555555"; font.pixelSize: 11 * App.fontScale; font.underline: true
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

                        Rectangle { Layout.fillWidth: true; height: 1; color: ColorPalette.border; Layout.bottomMargin: 12 }

                        // ?? Build info ????????????????????????????????????????????????
                        GridLayout {
                            columns: 2; columnSpacing: 20; rowSpacing: 5
                            Layout.bottomMargin: 14

                            Text { text: qsTr("Build date");  color: ColorPalette.textSecond; font.pixelSize: 12 * App.fontScale }
                            Text { text: App.buildTimeFormatted; color: ColorPalette.textPrimary; font.pixelSize: 12 * App.fontScale }
                            Text { text: qsTr("Qt version");  color: ColorPalette.textSecond; font.pixelSize: 12 * App.fontScale }
                            Text { text: App.qtVersion; color: ColorPalette.textPrimary; font.pixelSize: 12 * App.fontScale }
                            Text { text: qsTr("Platform");    color: ColorPalette.textSecond; font.pixelSize: 12 * App.fontScale }
                            Text {
                                text: {
                                    const os = Qt.platform.os
                                    if (os === "windows") return qsTr("Windows")
                                    if (os === "linux")   return qsTr("Linux")
                                    if (os === "osx")     return qsTr("macOS")
                                    return os.charAt(0).toUpperCase() + os.slice(1)
                                }
                                color: ColorPalette.textPrimary; font.pixelSize: 12 * App.fontScale
                            }
                        }

                        Rectangle { Layout.fillWidth: true; height: 1; color: ColorPalette.border; Layout.bottomMargin: 12 }

                        // ?? License + Links ???????????????????????????????????????????
                        Flow {
                            spacing: 6
                            Layout.fillWidth: true
                            Layout.bottomMargin: 16

                            Text {
                                text: "Copyright \u00A9 2026 Ninka_"
                                color: "#707070"; font.pixelSize: 11 * App.fontScale
                            }
                            Text { text: "\u00B7"; color: ColorPalette.border; font.pixelSize: 11 * App.fontScale }
                            Text {
                                text: qsTr("GNU GPL v3.0")
                                color: "#4488dd"; font.pixelSize: 11 * App.fontScale
                                font.underline: true
                                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                    onClicked: App.openExternalUrl("https://www.gnu.org/licenses/gpl-3.0.html") }
                            }
                            Text { text: "\u00B7"; color: ColorPalette.border; font.pixelSize: 11 * App.fontScale }
                            Text {
                                text: qsTr("Stellar Website")
                                color: "#4488dd"; font.pixelSize: 11 * App.fontScale
                                font.underline: true
                                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                    onClicked: App.openExternalUrl("https://stellardownloadmanager.org/") }
                            }
                            Text { text: "\u00B7"; color: ColorPalette.border; font.pixelSize: 11 * App.fontScale }
                            Text {
                                text: qsTr("GitHub")
                                color: "#4488dd"; font.pixelSize: 11 * App.fontScale
                                font.underline: true
                                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                    onClicked: App.openExternalUrl("https://github.com/Ninka-Rex/Stellar") }
                            }
                            Text { text: "\u00B7"; color: ColorPalette.border; font.pixelSize: 11 * App.fontScale }
                            Text {
                                text: qsTr("Releases")
                                color: "#4488dd"; font.pixelSize: 11 * App.fontScale
                                font.underline: true
                                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                    onClicked: App.openExternalUrl("https://github.com/Ninka-Rex/Stellar/releases") }
                            }
                        }

                        Text {
                            Layout.fillWidth: true
                            text: qsTr("Stellar is free software: you may redistribute and/or modify it under the terms of the GNU General Public License, version 3.")
                            color: "#808080"
                            font.pixelSize: 11 * App.fontScale
                            wrapMode: Text.WordWrap
                            Layout.bottomMargin: 6
                        }

                        Text {
                            Layout.fillWidth: true
                            text: qsTr("This program is distributed in the hope that it will be useful, but without any warranty; without even the implied warranty of merchantability or fitness for a particular purpose.")
                            color: "#808080"
                            font.pixelSize: 11 * App.fontScale
                            wrapMode: Text.WordWrap
                            Layout.bottomMargin: 8
                        }

                        Rectangle { Layout.fillWidth: true; height: 1; color: "#2a2a2a"; Layout.topMargin: 4; Layout.bottomMargin: 14 }

                        // ?? Third-party credits ???????????????????????????????????????
                        // FFmpeg is invoked as an external executable (not linked into Stellar).
                        // Attribution is required by its LGPL-2.1+ / GPL-2+ license.
                        // Full license texts are in THIRD-PARTY-NOTICES.txt.
                        Text {
                            text: qsTr("Third-party software")
                            color: "#909090"; font.pixelSize: 12 * App.fontScale; font.bold: true
                            Layout.bottomMargin: 10
                        }

                        // FFmpeg
                        ColumnLayout {
                            spacing: 3
                            Layout.fillWidth: true
                            Layout.bottomMargin: 10

                            RowLayout {
                                spacing: 8
                                Text { text: "FFmpeg"; color: ColorPalette.textPrimary; font.pixelSize: 12 * App.fontScale; font.bold: true }
                                Text { text: "LGPL-2.1+ / GPL-2+"; color: "#555555"; font.pixelSize: 10 * App.fontScale }
                            }
                            Text {
                                Layout.fillWidth: true
                                text: "Copyright \u00A9 2000\u2013present the FFmpeg developers. " +
                                      "Used for merging video and audio streams. " +
                                      "FFmpeg is a trademark of Fabrice Bellard."
                                color: ColorPalette.textDisabled; font.pixelSize: 11 * App.fontScale
                                wrapMode: Text.WordWrap
                            }
                            RowLayout {
                                spacing: 12
                                Text {
                                    text: "ffmpeg.org"
                                    color: "#4488dd"; font.pixelSize: 11 * App.fontScale; font.underline: true
                                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                        onClicked: App.openExternalUrl("https://ffmpeg.org/") }
                                }
                                Text { text: "\u00B7"; color: ColorPalette.border; font.pixelSize: 11 * App.fontScale }
                                Text {
                                    text: qsTr("Git source")
                                    color: "#4488dd"; font.pixelSize: 11 * App.fontScale; font.underline: true
                                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                        onClicked: App.openExternalUrl("https://git.ffmpeg.org/ffmpeg.git") }
                                }
                            }
                        }

                        Rectangle { Layout.fillWidth: true; height: 1; color: ColorPalette.rowAltBg; Layout.bottomMargin: 10 }

                        // libtorrent
                        ColumnLayout {
                            spacing: 3
                            Layout.fillWidth: true
                            Layout.bottomMargin: 10

                            RowLayout {
                                spacing: 8
                                Text { text: "libtorrent"; color: ColorPalette.textPrimary; font.pixelSize: 12 * App.fontScale; font.bold: true }
                                Text { text: "BSD-3-Clause"; color: "#555555"; font.pixelSize: 10 * App.fontScale }
                            }
                            Text {
                                Layout.fillWidth: true
                                text: "Copyright \u00A9 Arvid Norberg and contributors. " +
                                      "Used for BitTorrent protocol support."
                                color: ColorPalette.textDisabled; font.pixelSize: 11 * App.fontScale
                                wrapMode: Text.WordWrap
                            }
                            RowLayout {
                                spacing: 12
                                Text {
                                    text: "libtorrent.org"
                                    color: "#4488dd"; font.pixelSize: 11 * App.fontScale; font.underline: true
                                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                        onClicked: App.openExternalUrl("https://libtorrent.org/") }
                                }
                                Text { text: "\u00B7"; color: ColorPalette.border; font.pixelSize: 11 * App.fontScale }
                                Text {
                                    text: "GitHub"
                                    color: "#4488dd"; font.pixelSize: 11 * App.fontScale; font.underline: true
                                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                        onClicked: App.openExternalUrl("https://github.com/arvidn/libtorrent") }
                                }
                            }
                        }

                        Rectangle { Layout.fillWidth: true; height: 1; color: ColorPalette.rowAltBg; Layout.bottomMargin: 10 }

                        // yt-dlp
                        ColumnLayout {
                            spacing: 3
                            Layout.fillWidth: true
                            Layout.bottomMargin: 10

                            RowLayout {
                                spacing: 8
                                Text { text: "yt-dlp"; color: ColorPalette.textPrimary; font.pixelSize: 12 * App.fontScale; font.bold: true }
                                Text { text: "The Unlicense"; color: "#555555"; font.pixelSize: 10 * App.fontScale }
                            }
                            Text {
                                Layout.fillWidth: true
                                text: "yt-dlp contributors (The Unlicense, public-domain dedication). " +
                                      "Used for video metadata extraction and media downloading features."
                                color: ColorPalette.textDisabled; font.pixelSize: 11 * App.fontScale
                                wrapMode: Text.WordWrap
                            }
                            RowLayout {
                                spacing: 12
                                Text {
                                    text: qsTr("yt-dlp on GitHub")
                                    color: "#4488dd"; font.pixelSize: 11 * App.fontScale; font.underline: true
                                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                        onClicked: App.openExternalUrl("https://github.com/yt-dlp/yt-dlp") }
                                }
                                Text { text: "\u00B7"; color: ColorPalette.border; font.pixelSize: 11 * App.fontScale }
                                Text {
                                    text: qsTr("Unlicense")
                                    color: "#4488dd"; font.pixelSize: 11 * App.fontScale; font.underline: true
                                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                        onClicked: App.openExternalUrl("http://unlicense.org/") }
                                }
                            }
                        }

                        Rectangle { Layout.fillWidth: true; height: 1; color: ColorPalette.rowAltBg; Layout.bottomMargin: 10 }

                        // Qt Framework
                        ColumnLayout {
                            spacing: 3
                            Layout.fillWidth: true
                            Layout.bottomMargin: 14

                            RowLayout {
                                spacing: 8
                                Text { text: "Qt " + App.qtVersion; color: ColorPalette.textPrimary; font.pixelSize: 12 * App.fontScale; font.bold: true }
                                Text { text: "LGPL-3"; color: "#555555"; font.pixelSize: 10 * App.fontScale }
                            }
                            Text {
                                Layout.fillWidth: true
                                text: "Copyright \u00A9 The Qt Company Ltd. Used under the LGPL-3 with the Qt LGPL exception."
                                color: ColorPalette.textDisabled; font.pixelSize: 11 * App.fontScale
                                wrapMode: Text.WordWrap
                            }
                            Text {
                                text: "code.qt.io"
                                color: "#4488dd"; font.pixelSize: 11 * App.fontScale; font.underline: true
                                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                    onClicked: App.openExternalUrl("https://code.qt.io/") }
                            }
                        }

                        Rectangle { Layout.fillWidth: true; height: 1; color: ColorPalette.rowAltBg; Layout.bottomMargin: 10 }

                        // DB-IP
                        ColumnLayout {
                            spacing: 3
                            Layout.fillWidth: true
                            Layout.bottomMargin: 10

                            RowLayout {
                                spacing: 8
                                Text { text: "DB-IP City Lite"; color: ColorPalette.textPrimary; font.pixelSize: 12 * App.fontScale; font.bold: true }
                                Text { text: "CC BY 4.0"; color: "#555555"; font.pixelSize: 10 * App.fontScale }
                            }
                            Text {
                                Layout.fillWidth: true
                                text: "Stellar uses the DB-IP City Lite geolocation database, distributed under Creative Commons Attribution 4.0."
                                color: ColorPalette.textDisabled; font.pixelSize: 11 * App.fontScale
                                wrapMode: Text.WordWrap
                            }
                            Text {
                                text: "db-ip.com"
                                color: "#4488dd"; font.pixelSize: 11 * App.fontScale; font.underline: true
                                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                    onClicked: App.openExternalUrl("https://db-ip.com/") }
                            }
                        }

                        Text {
                            Layout.fillWidth: true
                            text: qsTr("Full license texts are in THIRD-PARTY-NOTICES.txt, included with this installation.")
                            color: "#484848"; font.pixelSize: 11 * App.fontScale
                            wrapMode: Text.WordWrap
                            Layout.bottomMargin: 16
                        }

                        Rectangle { Layout.fillWidth: true; height: 1; color: ColorPalette.rowAltBg; Layout.bottomMargin: 12 }

                        Text {
                            text: "Thanks for using Stellar \uD83D\uDC99"
                            color: "#505050"; font.pixelSize: 11 * App.fontScale
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
            color: ColorPalette.panelBg

            Row {
                anchors { right: parent.right; verticalCenter: parent.verticalCenter; rightMargin: 12 }
                spacing: 8

                DlgButton {
                    text: qsTr("Apply")
                    primary: root.hasChanges
                    enabled: root.hasChanges
                    opacity: enabled ? 1.0 : 0.5
                    onClicked: if (root.hasChanges) root.applySettings()
                }

                DlgButton {
                    text: qsTr("OK")
                    primary: false
                    onClicked: { root.applySettings(); root.close() }
                }
            }
        }
    }
}
