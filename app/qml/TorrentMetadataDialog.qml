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
    width: 780
    height: 520
    minimumWidth: 720
    minimumHeight: 460
    title: "Torrent Metadata"
    color: "#1e1e1e"
    flags: Qt.Dialog | Qt.WindowTitleHint | Qt.WindowCloseButtonHint

    Material.theme: Material.Dark
    Material.background: "#1e1e1e"
    Material.accent: "#4488dd"

    property string downloadId: ""
    property bool startWhenReady: true
    readonly property var item: downloadId.length > 0 ? App.downloadById(downloadId) : null
    readonly property var fileModel: downloadId.length > 0 ? App.torrentFileModel(downloadId) : null
    // Latched true once metadata arrives; never flips back. Prevents the Loader
    // from swapping sourceComponent on every libtorrent tick (which resets scroll).
    property bool _metadataArrived: false
    // Suppress per-tick file_progress() walks while this dialog is hidden.
    // FilePropertiesDialog also gates on its Files tab; here the entire dialog
    // is a file picker so visibility alone is the right signal.
    readonly property bool fileUpdatesActive: visible && fileModel !== null
    onFileUpdatesActiveChanged: {
        if (fileModel)
            fileModel.setLiveUpdatesEnabled(fileUpdatesActive)
    }
    property string pendingSourceLabel: ""
    property string savePath: ""
    property string category: ""
    property string description: ""
    property bool useCustomSavePath: false
    property bool rememberCustomSavePath: false
    property var categoryIds: []
    property var categoryLabels: []
    property real fileColName: 300
    property real fileColProgress: 120
    property real fileColSize: 90
    signal downloadNowRequested(string downloadId, string savePath, string category, string description)
    signal downloadLaterRequested(string downloadId, string savePath, string category, string description)

    function fileTableWidth() {
        return fileColName + fileColProgress + fileColSize
    }

    function maxNameColWidth(viewportWidth) {
        var viewport = Number(viewportWidth || width)
        var reserved = fileColProgress + fileColSize + 28
        return Math.max(180, viewport - reserved)
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

    function defaultSavePathForCategory(categoryId) {
        var catId = safeStr(categoryId)
        var path = catId.length > 0 ? safeStr(App.categoryModel.savePathForCategory(catId)) : ""
        if (path.length === 0)
            path = safeStr(App.settings.defaultSavePath)
        if (path.length === 0)
            return ""
        return safeStr(App.normalizeTorrentSaveDirectory(path))
    }

    function refreshSavePathMode() {
        var currentPath = safeStr(savePath).trim()
        var categoryPath = defaultSavePathForCategory(category)
        useCustomSavePath = currentPath.length > 0
            && categoryPath.length > 0
            && currentPath !== categoryPath
    }

    function applyCategorySavePath(force) {
        if (!force && useCustomSavePath)
            return
        var categoryPath = defaultSavePathForCategory(category)
        if (categoryPath.length > 0)
            savePath = categoryPath
    }

    function rememberedCustomSavePath() {
        return safeStr(App.normalizeTorrentSaveDirectory(App.settings.torrentCustomSavePath))
    }

    function setCustomSavePath(path) {
        var normalized = safeStr(App.normalizeTorrentSaveDirectory(path))
        if (normalized.length === 0)
            return
        savePath = normalized
        useCustomSavePath = true
        App.settings.torrentUseCustomSavePathByDefault = true
    }

    function syncPersistentCustomSaveState() {
        App.settings.torrentUseCustomSavePathByDefault = useCustomSavePath
    }

    function persistRememberedSavePathIfNeeded() {
        if (!rememberCustomSavePath || !useCustomSavePath)
            return
        var normalized = safeStr(App.normalizeTorrentSaveDirectory(savePath))
        if (normalized.length > 0)
            App.settings.torrentCustomSavePath = normalized
    }

    onVisibleChanged: {
        if (visible) {
            App.setWindowIcon(root, ":/qt/qml/com/stellar/app/app/qml/icons/milky-way.png")
            root._userInteracted = false
            root._metadataArrived = !!(root.item && root.item.torrentHasMetadata)
            root.metaMapZoom = 1.0
            root.metaMapPanX = 0
            root.metaMapPanY = 0
            _centerOnOwner()
            if (item) {
                category = item.category || ""
                description = item.description || ""
                rememberCustomSavePath = false
                useCustomSavePath = App.settings.torrentUseCustomSavePathByDefault
                refreshCategories()
                if (useCustomSavePath) {
                    var rememberedPath = rememberedCustomSavePath()
                    savePath = rememberedPath.length > 0 ? rememberedPath : (item.savePath || App.settings.defaultSavePath)
                } else {
                    savePath = item.savePath || App.settings.defaultSavePath
                    applyCategorySavePath(true)
                }
                refreshSavePathMode()
                if (App.settings.torrentUseCustomSavePathByDefault)
                    useCustomSavePath = true
            }
        }
    }

    // Update window title and latch metadata state when item is assigned.
    onItemChanged: {
        // Reset to default first so a stale name from a previous torrent never persists.
        root.title = "Torrent Metadata"
        if (root.item && root.item.filename && root.item.filename.length > 0)
            root.title = root.item.filename
        if (root.item && root.item.torrentHasMetadata)
            root._metadataArrived = true
    }

    Connections {
        target: root.item
        function onFilenameChanged() {
            if (root.item && root.item.filename && root.item.filename.length > 0)
                root.title = root.item.filename
        }
        function onTorrentHasMetadataChanged() {
            if (root.item && root.item.torrentHasMetadata) {
                if (root.item.filename && root.item.filename.length > 0)
                    root.title = root.item.filename
                root._metadataArrived = true
            }
        }
    }

    function refreshCategories() {
        var ids = []
        var labels = []
        for (var i = 0; i < App.categoryModel.rowCount(); ++i) {
            var data = App.categoryModel.categoryData(i)
            ids.push(data.id)
            labels.push(data.label)
        }
        categoryIds = ids
        categoryLabels = labels
        if (category.length === 0 && ids.length > 0)
            category = ids[0]
    }

    function categoryIndex() {
        for (var i = 0; i < categoryIds.length; ++i)
            if (categoryIds[i] === category)
                return i
        return 0
    }

    // ── Swarm map properties (mirrored from FilePropertiesDialog peer map) ──
    readonly property var metaPeerModel: downloadId.length > 0 ? App.torrentPeerModel(downloadId) : null
    readonly property bool metaMapActive: visible && !!(item) && !item.torrentHasMetadata && metaPeerModel !== null

    // Pan drag state helpers
    property real _metaLastPanX: 0
    property real _metaLastPanY: 0

    // Auto-fit: animate zoom+pan to bound all plotted peers
    property bool _userInteracted: false   // set true when user manually zooms/pans; suppresses auto-fit

    // Query peer model rows directly for coordinates — avoids depending on
    // Repeater delegate instantiation timing (itemAt() is unreliable during
    // the Loader/Component lifecycle).
    function metaAutoFit(mapW, mapH) {
        var pm = root.metaPeerModel
        if (!pm || mapW <= 0 || mapH <= 0) return

        var minX = Infinity, minY = Infinity, maxX = -Infinity, maxY = -Infinity
        var found = false

        // Include the local "You" dot if available
        if (pm.hasLocalLocation) {
            var lpx = root.metaMapX(pm.localLongitude, mapW)
            var lpy = root.metaMapY(pm.localLatitude, mapW, mapH)
            minX = lpx; maxX = lpx; minY = lpy; maxY = lpy
            found = true
        }

        var count = pm.rowCount()
        for (var i = 0; i < count; i++) {
            var lat = pm.data(pm.index(i, 0), 271)   // LatitudeRole  = Qt::UserRole+15
            var lon = pm.data(pm.index(i, 0), 272)   // LongitudeRole = Qt::UserRole+16
            var flat = Number(lat), flon = Number(lon)
            if (!isFinite(flat) || !isFinite(flon) || (flat === 0 && flon === 0)) continue
            var px = root.metaMapX(flon, mapW)
            var py = root.metaMapY(flat, mapW, mapH)
            if (px < minX) minX = px
            if (px > maxX) maxX = px
            if (py < minY) minY = py
            if (py > maxY) maxY = py
            found = true
        }
        if (!found) return

        var pad = 64
        var spanX = Math.max(1, maxX - minX) + pad * 2
        var spanY = Math.max(1, maxY - minY) + pad * 2
        var fitZoom = Math.min(mapW / spanX, mapH / spanY)
        fitZoom = Math.max(1.0, Math.min(6.0, fitZoom))

        var cx = (minX + maxX) / 2
        var cy = (minY + maxY) / 2
        root.metaMapZoom = fitZoom
        root.metaMapPanX = mapW / 2 - cx * fitZoom
        root.metaMapPanY = mapH / 2 - cy * fitZoom
    }

    function compactSpeed(bps) {
        var n = Number(bps) || 0
        if (n <= 0) return "0 B/s"
        if (n >= 1024 * 1024 * 1024) return (n / (1024 * 1024 * 1024)).toFixed(2) + " GB/s"
        if (n >= 1024 * 1024) return (n / (1024 * 1024)).toFixed(1) + " MB/s"
        if (n >= 1024) return (n / 1024).toFixed(1) + " KB/s"
        return Math.round(n) + " B/s"
    }

    property real   metaMapZoom: 1.0
    property real   metaMapPanX: 0
    property real   metaMapPanY: 0

    Behavior on metaMapZoom { enabled: !root._userInteracted; NumberAnimation { duration: 1400; easing.type: Easing.InOutQuart } }
    Behavior on metaMapPanX { enabled: !root._userInteracted; NumberAnimation { duration: 1400; easing.type: Easing.InOutQuart } }
    Behavior on metaMapPanY { enabled: !root._userInteracted; NumberAnimation { duration: 1400; easing.type: Easing.InOutQuart } }
    property real   metaMapLonOffset: 0.5
    property real   metaMapLatOffset: 4.5
    readonly property real metaMapSvgMinX: 1.0
    readonly property real metaMapSvgMaxX: 799.0
    readonly property real metaMapSvgMinY: 1.0
    readonly property real metaMapSvgMaxY: 385.91

    property bool   metaMapHoverVisible: false
    property real   metaMapHoverX: 0
    property real   metaMapHoverY: 0
    property string metaMapHoverEndpoint: ""
    property int    metaMapHoverPort: 0
    property string metaMapHoverClient: ""
    property string metaMapHoverCountryCode: ""
    property string metaMapHoverRegionCode: ""
    property string metaMapHoverRegionName: ""
    property string metaMapHoverCityName: ""
    property int    metaMapHoverRtt: 0
    property int    metaMapHoverDownSpeed: 0
    property int    metaMapHoverUpSpeed: 0
    property bool   metaMapHoverIsSeed: false
    property string metaMapHoverSource: ""
    property string metaMapHoverFlags: ""
    property real   metaMapHoverProgress: 0.0

    function metaMapX(longitude, mapWidth) {
        var lon = Number(longitude) + metaMapLonOffset
        if (!isFinite(lon)) lon = 0
        var normalized = (lon + 180.0) / 360.0
        var drawableWidth = metaMapSvgMaxX - metaMapSvgMinX
        return ((metaMapSvgMinX + normalized * drawableWidth) / 800.0) * mapWidth
    }
    function metaMapY(latitude, mapWidth, mapHeight) {
        var lat = Number(latitude) + metaMapLatOffset
        if (!isFinite(lat)) lat = 0
        lat = Math.max(-90, Math.min(90, lat))
        var normalized = (90 - lat) / 180
        var drawableHeight = metaMapSvgMaxY - metaMapSvgMinY
        return ((metaMapSvgMinY + normalized * drawableHeight) / 387.0) * mapHeight
    }
    function metaPeerMapColor(isSeed) {
        return isSeed ? "#4caf7d" : "#5f93c9"
    }
    function metaPeerPlaceText(countryCode, regionCode, regionName, cityName) {
        var cc = safeStr(countryCode)
        var city = safeStr(cityName)
        var region = safeStr(regionCode)
        var rname = safeStr(regionName)
        var parts = []
        if (city) parts.push(city)
        if (region && (cc === "US" || cc === "CA")) parts.push(region)
        else if (rname) parts.push(rname)
        if (cc) parts.push(cc)
        return parts.join(", ")
    }
    function metaFlagColor(flag) {
        switch (flag) {
        case "IN":  return "#e8c84a"
        case "OUT": return "#7a8899"
        case "TRK": return "#5f93c9"
        case "DHT": return "#4db8ff"
        case "PEX": return "#a06de8"
        case "LSD": return "#4caf7d"
        case "UTP": return "#5ecfe8"
        case "ENC": return "#7dd87d"
        case "SNB": return "#e86a5c"
        case "UPO": return "#c97de8"
        case "OPT": return "#e8a35c"
        case "HPX": return "#ff8ab4"
        case "I2P": return "#a8ff78"
        default:    return "#708396"
        }
    }
    function metaShowPeerHover(peer, x, y) {
        metaMapHoverVisible = !!peer
        if (!peer) return
        metaMapHoverEndpoint = safeStr(peer.endpoint)
        metaMapHoverPort = peer.port | 0
        metaMapHoverClient = safeStr(peer.client)
        metaMapHoverCountryCode = safeStr(peer.countryCode)
        metaMapHoverRegionCode = safeStr(peer.regionCode)
        metaMapHoverRegionName = safeStr(peer.regionName)
        metaMapHoverCityName = safeStr(peer.cityName)
        metaMapHoverRtt = peer.rtt | 0
        metaMapHoverDownSpeed = peer.downSpeed | 0
        metaMapHoverUpSpeed = peer.upSpeed | 0
        metaMapHoverIsSeed = !!peer.isSeed
        metaMapHoverSource = safeStr(peer.source)
        metaMapHoverFlags = safeStr(peer.flags)
        metaMapHoverProgress = Number(peer.progress) || 0
        metaMapHoverX = Number(x) || 0
        metaMapHoverY = Number(y) || 0
    }

    function metadataPeerCount() {
        if (!root.item)
            return 0
        return Math.max(root.item.torrentPeers | 0, root.item.torrentListPeers | 0)
    }

    function metadataPeerStatusText() {
        if (!root.item)
            return "Opening torrent and reading metadata..."
        var peers = metadataPeerCount()
        if (peers <= 0)
            return "Looking for peers to download metadata..."
        return "Downloading metadata from " + peers + (peers === 1 ? " peer" : " peers")
    }

    function formatBytes(bytes) {
        var value = Number(bytes || 0)
        if (value <= 0) return ""
        var kb = value / 1024.0
        var mb = kb / 1024.0
        var gb = mb / 1024.0
        if (gb >= 0.95) return gb.toFixed(2) + " GB"
        if (mb >= 0.95) return mb.toFixed(1) + " MB"
        if (kb >= 0.95) return kb.toFixed(1) + " KB"
        return Math.round(value) + " B"
    }

    function safeStr(value) {
        return value === undefined || value === null ? "" : String(value)
    }

    function clampPct(v) {
        var n = Number(v)
        if (isNaN(n))
            return 0
        if (n < 0)
            return 0
        if (n > 1)
            return 1
        return n
    }

    Connections {
        target: App.categoryModel
        function onCategoriesChanged() {
            root.refreshCategories()
            if (!root.useCustomSavePath)
                root.applyCategorySavePath(true)
        }
    }

    FolderDialog {
        id: saveFolderDialog
        currentFolder: root.savePath.length > 0
                       ? fileUrlFromPath(root.savePath)
                       : ""
        onAccepted: {
            var path = pathFromFileUrl(selectedFolder)
            if (path.length > 0)
                root.setCustomSavePath(path)
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 12
        spacing: 6

        // Title + status on one line
        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Image {
                source: "icons/magnet.png"
                width: 12; height: 12
                sourceSize.width: 24; sourceSize.height: 24
                fillMode: Image.PreserveAspectFit
                smooth: true
                Layout.alignment: Qt.AlignVCenter
            }

            Text {
                text: root.item && root.item.filename && root.item.filename.length > 0
                      ? root.item.filename
                      : (root.pendingSourceLabel.length > 0 ? root.pendingSourceLabel : "Torrent Metadata")
                color: "#ffffff"
                font.pixelSize: 15
                font.bold: true
                Layout.fillWidth: true
                elide: Text.ElideRight
            }

            Text {
                visible: !!root.item && root.item.status === "Error"
                text: root.item ? root.item.errorString : ""
                color: "#e07b7b"
                font.pixelSize: 12
                elide: Text.ElideRight
                Layout.maximumWidth: 260
            }
        }

        // Compact form: save path + category + description on two rows
        RowLayout {
            Layout.fillWidth: true
            spacing: 6

            Text { text: "Save to"; color: "#a5a5a5"; font.pixelSize: 12 }

            TextField {
                id: savePathField
                Layout.fillWidth: true
                Layout.preferredHeight: 32
                text: root.savePath
                color: "#d7d7d7"
                background: Rectangle { color: "#171717"; border.color: "#303030"; radius: 3 }
                leftPadding: 6
                rightPadding: 6
                topPadding: 0; bottomPadding: 0
                verticalAlignment: TextInput.AlignVCenter
                onTextChanged: {
                    root.savePath = text
                    root.refreshSavePathMode()
                    root.syncPersistentCustomSaveState()
                }
            }

            DlgButton {
                text: "Save As..."
                Layout.preferredHeight: 32
                onClicked: saveFolderDialog.open()
            }

            // Separator
            Rectangle { width: 1; height: 22; color: "#343434" }

            Text { text: "Category"; color: "#a5a5a5"; font.pixelSize: 12 }

            ComboBox {
                id: categoryCombo
                implicitWidth: 140
                implicitHeight: 32
                model: root.categoryLabels
                currentIndex: root.categoryIndex()
                onActivated: {
                    root.category = root.categoryIds[currentIndex] || "all"
                    root.applyCategorySavePath(false)
                }
                contentItem: Text {
                    text: categoryCombo.displayText
                    color: "#d7d7d7"
                    verticalAlignment: Text.AlignVCenter
                    leftPadding: 6
                    elide: Text.ElideRight
                    font.pixelSize: 12
                }
                background: Rectangle { color: "#171717"; border.color: "#303030"; radius: 3 }
            }
        }

        // Second row: checkboxes + description (hidden while waiting for metadata)
        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            visible: !!root.item && root.item.torrentHasMetadata

            CheckBox {
                id: customSavePathCheck
                text: "Custom save folder"
                checked: root.useCustomSavePath
                topPadding: 0; bottomPadding: 0
                onToggled: {
                    root.useCustomSavePath = checked
                    root.syncPersistentCustomSaveState()
                    if (!checked)
                        root.applyCategorySavePath(true)
                    else {
                        var rememberedPath = root.rememberedCustomSavePath()
                        if (rememberedPath.length > 0)
                            root.savePath = rememberedPath
                    }
                }
                contentItem: Text {
                    text: parent.text; color: "#d0d0d0"; font.pixelSize: 12
                    leftPadding: parent.indicator.width + 4; verticalAlignment: Text.AlignVCenter
                }
            }

            CheckBox {
                text: "Remember"
                checked: root.rememberCustomSavePath
                enabled: root.useCustomSavePath
                topPadding: 0; bottomPadding: 0
                onToggled: root.rememberCustomSavePath = checked
                contentItem: Text {
                    text: parent.text
                    color: parent.enabled ? "#d0d0d0" : "#6f6f6f"; font.pixelSize: 12
                    leftPadding: parent.indicator.width + 4; verticalAlignment: Text.AlignVCenter
                }
            }

            Text {
                text: "Use category folder"
                color: root.useCustomSavePath ? "#66aaff" : "#5f5f5f"
                font.pixelSize: 12; font.underline: root.useCustomSavePath
                MouseArea {
                    anchors.fill: parent
                    enabled: root.useCustomSavePath
                    cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onClicked: {
                        root.useCustomSavePath = false
                        root.syncPersistentCustomSaveState()
                        root.applyCategorySavePath(true)
                    }
                }
            }

            Rectangle { width: 1; height: 18; color: "#343434" }

            Text { text: "Description"; color: "#a5a5a5"; font.pixelSize: 12 }
            TextField {
                Layout.fillWidth: true
                implicitHeight: 26
                text: root.description
                color: "#d7d7d7"
                background: Rectangle { color: "#171717"; border.color: "#303030"; radius: 3 }
                leftPadding: 6; rightPadding: 6; topPadding: 0; bottomPadding: 0
                verticalAlignment: TextInput.AlignVCenter
                font.pixelSize: 12
                onTextChanged: root.description = text
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            color: "#171717"
            border.color: "#303030"
            radius: 6
            clip: true

            Loader {
                id: contentLoader
                anchors.fill: parent
                active: !!root.item
                sourceComponent: root._metadataArrived ? filesView : waitingView
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Item { Layout.fillWidth: true }

            DlgButton {
                text: "Cancel"
                onClicked: {
                    if (root.downloadId.length > 0)
                        App.discardTorrentDownload(root.downloadId)
                    root.close()
                }
            }

            DlgButton {
                text: "Download Later"
                enabled: !!root.item && root.item.status !== "Error"
                onClicked: {
                    root.persistRememberedSavePathIfNeeded()
                    if (root.downloadId.length > 0)
                        root.downloadLaterRequested(root.downloadId, root.savePath, root.category, root.description)
                    root.close()
                }
            }

            DlgButton {
                text: "Download"
                primary: true
                enabled: !!root.item && root.item.status !== "Error"
                onClicked: {
                    root.persistRememberedSavePathIfNeeded()
                    if (root.downloadId.length > 0)
                        root.downloadNowRequested(root.downloadId, root.savePath, root.category, root.description)
                    root.close()
                }
            }
        }
    }

    Component {
        id: waitingView

        Item {
            anchors.fill: parent

            // ── World swarm map ───────────────────────────────────────────────
            Rectangle {
                anchors.fill: parent
                color: "#0d141c"
                radius: 3
                clip: true

                // Overlay status row at the top
                Rectangle {
                    id: metaStatusBar
                    anchors { top: parent.top; left: parent.left; right: parent.right }
                    height: 34
                    color: "#111923"
                    z: 10

                    Row {
                        anchors { verticalCenter: parent.verticalCenter; left: parent.left; leftMargin: 10 }
                        spacing: 10

                        BusyIndicator {
                            running: true
                            width: 18
                            height: 18
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.item ? root.metadataPeerStatusText() : "Opening torrent..."
                            color: "#8ea1b5"
                            font.pixelSize: 12
                        }
                    }

                    // Peer/seed legend top-right
                    Row {
                        anchors { verticalCenter: parent.verticalCenter; right: parent.right; rightMargin: 10 }
                        spacing: 10

                        Rectangle { width: 10; height: 10; radius: 5; color: "#5f93c9"; anchors.verticalCenter: parent.verticalCenter }
                        Text { text: "Peer"; color: "#b8c5d3"; font.pixelSize: 11; anchors.verticalCenter: parent.verticalCenter }
                        Rectangle { width: 10; height: 10; radius: 5; color: "#4caf7d"; anchors.verticalCenter: parent.verticalCenter }
                        Text { text: "Seed"; color: "#b8c5d3"; font.pixelSize: 11; anchors.verticalCenter: parent.verticalCenter }
                        Rectangle { width: 10; height: 10; radius: 5; color: "#9959e6"; anchors.verticalCenter: parent.verticalCenter }
                        Text { text: "You"; color: "#b8c5d3"; font.pixelSize: 11; anchors.verticalCenter: parent.verticalCenter }
                    }
                }

                // Map area
                Item {
                    id: metaMapRoot
                    anchors { top: metaStatusBar.bottom; left: parent.left; right: parent.right; bottom: parent.bottom }
                    anchors.margins: 8
                    clip: true

                    // Auto-fit state
                    property bool _hasFitOnce: false
                    property bool _pendingFit: false

                    function tryFit() {
                        if (root._userInteracted) return
                        if (metaMapRoot.width <= 0 || metaMapRoot.height <= 0) {
                            metaMapRoot._pendingFit = true
                            return
                        }
                        var pm = root.metaPeerModel
                        if (!pm || pm.rowCount() === 0) {
                            metaMapRoot._pendingFit = true
                            return
                        }
                        // Check at least one peer has real geo coordinates
                        var hasAny = false
                        var n = pm.rowCount()
                        for (var i = 0; i < n; i++) {
                            var lat = Number(pm.data(pm.index(i, 0), 271))
                            var lon = Number(pm.data(pm.index(i, 0), 272))
                            if (isFinite(lat) && isFinite(lon) && !(lat === 0 && lon === 0)) {
                                hasAny = true; break
                            }
                        }
                        if (!hasAny) {
                            metaMapRoot._pendingFit = true
                            return
                        }
                        metaMapRoot._pendingFit = false
                        metaMapRoot._hasFitOnce = true
                        root.metaAutoFit(metaMapRoot.width, metaMapRoot.height)
                    }

                    // Fire pending fit once we have real dimensions
                    onWidthChanged:  { if (metaMapRoot._pendingFit && width  > 0) metaMapRoot.tryFit() }
                    onHeightChanged: { if (metaMapRoot._pendingFit && height > 0) metaMapRoot.tryFit() }

                    // Short delay on first-peer fit so delegates finish constructing
                    // before metaAutoFit iterates itemAt() for coordinates.
                    Timer {
                        id: metaFirstFitTimer
                        interval: 50
                        repeat: false
                        onTriggered: metaMapRoot.tryFit()
                    }

                    // Debounce timer for subsequent peer changes (2s)
                    Timer {
                        id: metaFitTimer
                        interval: 2000
                        repeat: false
                        onTriggered: {
                            if (!root._userInteracted)
                                root.metaAutoFit(metaMapRoot.width, metaMapRoot.height)
                        }
                    }

                    Connections {
                        target: root.metaPeerModel
                        function onRowsInserted() {
                            if (root._userInteracted) return
                            if (!metaMapRoot._hasFitOnce) {
                                if (!metaFirstFitTimer.running)
                                    metaFirstFitTimer.start()
                            } else {
                                metaFitTimer.restart()
                            }
                        }
                        // Geo-IP resolves asynchronously: peer is inserted with lat/lon=0,
                        // then dataChanged fires once the coordinates are populated.
                        function onDataChanged() {
                            if (root._userInteracted) return
                            if (!metaMapRoot._hasFitOnce && !metaFirstFitTimer.running)
                                metaFirstFitTimer.start()
                        }
                        function onRowsRemoved() { metaFitTimer.restart() }
                        function onModelReset()  {
                            metaMapRoot._hasFitOnce = false
                            metaMapRoot._pendingFit = false
                            metaFirstFitTimer.stop()
                            metaFitTimer.stop()
                        }
                    }

                    // Zoom/pan gestures — suppress auto-fit once user interacts
                    WheelHandler {
                        target: null
                        onWheel: function(event) {
                            root._userInteracted = true
                            var factor = event.angleDelta.y > 0 ? 1.15 : (1.0 / 1.15)
                            var newZoom = Math.max(1.0, Math.min(8.0, root.metaMapZoom * factor))
                            var mouseX = event.x - root.metaMapPanX
                            var mouseY = event.y - root.metaMapPanY
                            root.metaMapPanX = event.x - mouseX * (newZoom / root.metaMapZoom)
                            root.metaMapPanY = event.y - mouseY * (newZoom / root.metaMapZoom)
                            root.metaMapZoom = newZoom
                        }
                    }

                    DragHandler {
                        id: metaMapPanDrag
                        target: null
                        onTranslationChanged: {
                            root._userInteracted = true
                            root.metaMapPanX += translation.x - (root._metaLastPanX || 0)
                            root.metaMapPanY += translation.y - (root._metaLastPanY || 0)
                            root._metaLastPanX = translation.x
                            root._metaLastPanY = translation.y
                        }
                        onActiveChanged: {
                            if (!active) { root._metaLastPanX = 0; root._metaLastPanY = 0 }
                        }
                        acceptedButtons: Qt.LeftButton
                    }

                    Item {
                        id: metaMapCanvas
                        x: root.metaMapPanX
                        y: root.metaMapPanY
                        width: metaMapRoot.width
                        height: metaMapRoot.height
                        scale: root.metaMapZoom
                        transformOrigin: Item.TopLeft

                        readonly property real mapX: metaWorldImg.x + (metaWorldImg.width - metaWorldImg.paintedWidth) / 2
                        readonly property real mapY: metaWorldImg.y + (metaWorldImg.height - metaWorldImg.paintedHeight) / 2
                        readonly property real mapWidth: metaWorldImg.paintedWidth
                        readonly property real mapHeight: metaWorldImg.paintedHeight

                        Image {
                            id: metaWorldImg
                            anchors.fill: parent
                            source: "icons/world-map.svg"
                            fillMode: Image.PreserveAspectFit
                            smooth: true
                            sourceSize.width: 2400
                            sourceSize.height: 1161
                        }

                        // Peer dots with pop-in animation
                        Repeater {
                            id: metaPeerRepeater
                            model: root.metaMapActive ? root.metaPeerModel : null
                            Component.onCompleted: {
                                if (!metaMapRoot._hasFitOnce && !root._userInteracted)
                                    metaFirstFitTimer.restart()
                            }

                            delegate: Item {
                                required property string endpoint
                                required property int    port
                                required property string client
                                required property string countryCode
                                required property string regionCode
                                required property string regionName
                                required property string cityName
                                required property double latitude
                                required property double longitude
                                required property int    rtt
                                required property int    downSpeed
                                required property int    upSpeed
                                required property bool   isSeed
                                required property string source
                                required property string flags
                                required property double progress

                                readonly property bool hasCoordinates: isFinite(latitude) && isFinite(longitude) && !(latitude === 0 && longitude === 0)

                                visible: hasCoordinates
                                x: metaMapCanvas.mapX + root.metaMapX(longitude, metaMapCanvas.mapWidth) - width / 2
                                y: metaMapCanvas.mapY + root.metaMapY(latitude, metaMapCanvas.mapWidth, metaMapCanvas.mapHeight) - height / 2
                                width: 16
                                height: 16
                                scale: 1.0 / root.metaMapZoom
                                transformOrigin: Item.Center

                                // Peer is actively helping fetch metadata
                                readonly property bool isActive: downSpeed > 0 || upSpeed > 0

                                // Pop-in when first plotted
                                Component.onCompleted: {
                                    if (hasCoordinates) dotScale.restart()
                                }

                                ScaleAnimator {
                                    id: dotScale
                                    target: dotCircle
                                    from: 0
                                    to: 1
                                    duration: 350
                                    easing.type: Easing.OutBack
                                }

                                // Ripple only on peers actively sending data
                                SequentialAnimation {
                                    running: hasCoordinates && isActive
                                    loops: Animation.Infinite
                                    NumberAnimation { target: dotRipple; property: "scale"; from: 0.8; to: 2.4; duration: 1000; easing.type: Easing.OutQuad }
                                    NumberAnimation { target: dotRipple; property: "opacity"; from: 0.6; to: 0; duration: 350 }
                                    PropertyAction  { target: dotRipple; property: "scale"; value: 0.8 }
                                    PropertyAction  { target: dotRipple; property: "opacity"; value: 0.6 }
                                }

                                // Ripple ring (hidden when peer is idle)
                                Rectangle {
                                    id: dotRipple
                                    anchors.centerIn: parent
                                    width: 10; height: 10
                                    radius: 5
                                    color: "transparent"
                                    border.color: isSeed ? "#4caf7d" : "#5f93c9"
                                    border.width: 1.5
                                    transformOrigin: Item.Center
                                    opacity: 0
                                    visible: parent.isActive
                                }

                                Rectangle {
                                    id: dotCircle
                                    anchors.centerIn: parent
                                    width: 10; height: 10; radius: 5
                                    color: root.metaPeerMapColor(isSeed)
                                    border.color: metaMarkerMouse.containsMouse ? "#edf3f8" : "#081018"
                                    border.width: 1
                                    transformOrigin: Item.Center
                                }

                                MouseArea {
                                    id: metaMarkerMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    acceptedButtons: Qt.NoButton
                                    onEntered: {
                                        var p = parent.mapToItem(metaMapRoot, parent.width / 2, 0)
                                        root.metaShowPeerHover(parent, p.x, p.y)
                                    }
                                    onPositionChanged: {
                                        var p = parent.mapToItem(metaMapRoot, parent.width / 2, 0)
                                        root.metaShowPeerHover(parent, p.x, p.y)
                                    }
                                    onExited: root.metaMapHoverVisible = false
                                }
                            }
                        }

                        // "You" dot
                        Item {
                            id: metaYouDot
                            visible: !!root.metaPeerModel && root.metaPeerModel.hasLocalLocation
                            x: metaMapCanvas.mapX + root.metaMapX(root.metaPeerModel ? root.metaPeerModel.localLongitude : 0, metaMapCanvas.mapWidth) - width / 2
                            y: metaMapCanvas.mapY + root.metaMapY(root.metaPeerModel ? root.metaPeerModel.localLatitude : 0, metaMapCanvas.mapWidth, metaMapCanvas.mapHeight) - height / 2
                            width: 16; height: 16
                            scale: 1.0 / root.metaMapZoom
                            transformOrigin: Item.Center

                            Rectangle {
                                anchors.centerIn: parent
                                width: 10; height: 10; radius: 5
                                color: "#9959e6"
                                border.color: "#081018"; border.width: 1
                            }
                        }
                    }

                    // Hover tooltip
                    Rectangle {
                        visible: root.metaMapHoverVisible
                        x: Math.max(10, Math.min(metaMapRoot.width - width - 10, root.metaMapHoverX + 14))
                        y: Math.max(10, Math.min(metaMapRoot.height - height - 10, root.metaMapHoverY - height / 2))
                        width: 200
                        implicitHeight: metaTooltipCol.implicitHeight + 10
                        color: "#101821"
                        border.color: "#314252"
                        radius: 4
                        z: 20

                        Column {
                            id: metaTooltipCol
                            anchors.fill: parent
                            anchors.margins: 7
                            spacing: 4

                            Row {
                                spacing: 5; width: parent.width
                                Text {
                                    text: root.metaMapHoverEndpoint
                                    color: "#f0f5fb"; font.pixelSize: 13; font.bold: true
                                    elide: Text.ElideRight
                                    width: Math.min(implicitWidth, parent.width - metaTipPort.implicitWidth - 5)
                                }
                                Text {
                                    id: metaTipPort
                                    text: root.metaMapHoverPort
                                    color: "#6a8099"; font.pixelSize: 13; font.bold: true
                                    anchors.baseline: parent.children[0].baseline
                                }
                            }

                            Text {
                                visible: root.metaMapHoverClient.length > 0
                                text: root.metaMapHoverClient
                                color: "#c5d2de"; font.pixelSize: 12
                                elide: Text.ElideRight; width: parent.width
                            }

                            Text {
                                visible: root.metaMapHoverCountryCode.length > 0
                                text: root.metaPeerPlaceText(root.metaMapHoverCountryCode, root.metaMapHoverRegionCode, root.metaMapHoverRegionName, root.metaMapHoverCityName)
                                color: "#95a9bb"; font.pixelSize: 11
                                elide: Text.ElideRight; width: parent.width
                            }

                            // Flags
                            Flow {
                                width: parent.width; spacing: 2
                                Repeater {
                                    model: root.metaMapHoverFlags
                                        ? root.metaMapHoverFlags.split(" ").filter(function(f){ return f.length > 0 })
                                        : []
                                    delegate: Rectangle {
                                        required property string modelData
                                        height: 14; width: tipBadge.implicitWidth + 6
                                        radius: 2; color: Qt.rgba(0, 0, 0, 0.3)
                                        border.color: root.metaFlagColor(modelData); border.width: 1
                                        Text {
                                            id: tipBadge
                                            anchors.centerIn: parent
                                            text: modelData; color: "white"
                                            font.pixelSize: 9; font.bold: true
                                        }
                                    }
                                }
                            }

                            Text {
                                text: "↓ " + root.compactSpeed(root.metaMapHoverDownSpeed) + "  ↑ " + root.compactSpeed(root.metaMapHoverUpSpeed)
                                color: "#9fb6c8"; font.pixelSize: 11; width: parent.width
                            }

                            Text {
                                text: "RTT " + (root.metaMapHoverRtt > 0 ? (root.metaMapHoverRtt + " ms") : "—")
                                    + "  " + Math.round(root.metaMapHoverProgress * 100) + "% done"
                                color: "#9fb6c8"; font.pixelSize: 11; width: parent.width
                            }
                        }
                    }
                }
            }
        }
    }

    Component {
        id: filesView

        ColumnLayout {
            anchors.fill: parent
            spacing: 0

            // Header row with explicit left/right padding
            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: 10
                Layout.rightMargin: 10
                Layout.topMargin: 8
                Layout.bottomMargin: 4
                Text { text: "Files"; color: "#f0f0f0"; font.pixelSize: 14; font.bold: true }
                Item { Layout.fillWidth: true }
                Text {
                    text: metaFileList ? (metaFileList.count + " items") : ""
                    color: "#808080"
                    font.pixelSize: 11
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.leftMargin: 10
                Layout.rightMargin: 10
                height: 1
                color: "#2d2d2d"
            }

            Item {
                id: metaFileViewport
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.leftMargin: 10
                Layout.rightMargin: 10
                Layout.bottomMargin: 8
                clip: true

                ColumnLayout {
                    anchors.fill: parent
                    spacing: 0

                    Rectangle {
                        id: metaHeader
                        Layout.fillWidth: true
                        height: 26
                        color: "#252525"
                        clip: true

                        Row {
                            // Match the delegate Row's leftMargin:6 / rightMargin:8 so
                            // the header has consistent margins regardless of whether
                            // the vertical ScrollBar is visible.
                            x: 6 - (metaFileList ? metaFileList.contentX : 0)
                            width: parent.width - 14
                            height: parent.height
                            spacing: 0

                            Rectangle {
                                width: root.fileColName
                                height: parent.height
                                color: "transparent"
                                Text {
                                    anchors { verticalCenter: parent.verticalCenter; left: parent.left; leftMargin: 6; right: parent.right; rightMargin: 12 }
                                    text: "Name"
                                    color: "#b0b0b0"
                                    font.pixelSize: 12
                                    font.bold: true
                                    elide: Text.ElideRight
                                }
                                Item {
                                    anchors.right: parent.right
                                    width: 10
                                    height: parent.height
                                    property real _startW: 0
                                    HoverHandler { id: metaNameHover; cursorShape: Qt.SizeHorCursor }
                                    DragHandler {
                                        id: metaNameDrag
                                        target: null
                                        xAxis.enabled: true
                                        yAxis.enabled: false
                                        cursorShape: Qt.SizeHorCursor
                                        onActiveChanged: if (active) parent._startW = root.fileColName
                                        onTranslationChanged: if (active) {
                                            var nextWidth = Math.round(parent._startW + translation.x)
                                            root.fileColName = Math.max(180, Math.min(nextWidth, root.maxNameColWidth(metaFileList.width)))
                                        }
                                    }
                                }
                            }

                            Rectangle {
                                width: root.fileColProgress
                                height: parent.height
                                color: "transparent"
                                Text {
                                    anchors { verticalCenter: parent.verticalCenter; left: parent.left; leftMargin: 6; right: parent.right; rightMargin: 12 }
                                    text: "Progress"
                                    color: "#b0b0b0"
                                    font.pixelSize: 12
                                    font.bold: true
                                    elide: Text.ElideRight
                                }
                                Item {
                                    anchors.right: parent.right
                                    width: 10
                                    height: parent.height
                                    property real _startW: 0
                                    HoverHandler { id: metaProgHover; cursorShape: Qt.SizeHorCursor }
                                    DragHandler {
                                        id: metaProgDrag
                                        target: null
                                        xAxis.enabled: true
                                        yAxis.enabled: false
                                        cursorShape: Qt.SizeHorCursor
                                        onActiveChanged: if (active) parent._startW = root.fileColProgress
                                        onTranslationChanged: if (active) root.fileColProgress = Math.max(90, Math.round(parent._startW + translation.x))
                                    }
                                }
                            }

                            Rectangle {
                                width: root.fileColSize
                                height: parent.height
                                color: "transparent"
                                Text {
                                    anchors { verticalCenter: parent.verticalCenter; left: parent.left; leftMargin: 6; right: parent.right; rightMargin: 12 }
                                    text: "Size"
                                    color: "#b0b0b0"
                                    font.pixelSize: 12
                                    font.bold: true
                                    elide: Text.ElideRight
                                }
                            }
                        }
                    }

                    ListView {
                        id: metaFileList
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        spacing: 0
                        model: root.fileModel
                        contentWidth: root.fileTableWidth()
                        flickableDirection: Flickable.HorizontalAndVerticalFlick
                        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                        ScrollBar.horizontal: ScrollBar { policy: ScrollBar.AlwaysOn }

                        Text {
                            anchors.centerIn: parent
                            visible: parent.count === 0
                            text: "No file information available"
                            color: "#666666"
                            font.pixelSize: 12
                        }

                delegate: Rectangle {
                    id: metaFd
                    required property int    index
                    required property string name
                    required property string path
                    required property real   progress
                    required property bool   wanted
                    required property double size
                    required property bool   isFolder
                    required property int    depth
                    required property bool   expanded
                    required property int    fileIndex

                    width: Math.max(ListView.view.width, metaFileList.contentWidth)
                    height: 26
                    color: isFolder ? "#1f1f1f" : (index % 2 === 0 ? "#1c1c1c" : "#222222")

                    Rectangle {
                        visible: isFolder
                        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                        height: 1
                        color: "#2e2e2e"
                    }

                    Row {
                        anchors.fill: parent
                        anchors.leftMargin: 6
                        anchors.rightMargin: 8
                        spacing: 0

                        Item { width: Math.max(0, depth) * 14; height: parent.height }

                        Item {
                            width: 16
                            height: parent.height
                            Text {
                                visible: isFolder
                                anchors.centerIn: parent
                                text: expanded ? "▾" : "▸"
                                color: "#888"
                                font.pixelSize: 11
                            }
                            MouseArea {
                                visible: isFolder
                                anchors.fill: parent
                                acceptedButtons: Qt.LeftButton
                                onClicked: root.fileModel.toggleExpanded(index)
                            }
                        }

                        Item {
                            width: 22
                            height: parent.height
                            Rectangle {
                                anchors.centerIn: parent
                                width: 14
                                height: 14
                                radius: 2
                                color: wanted ? "#4488dd" : "#1b1b1b"
                                border.color: wanted ? "#4488dd" : "#3a3a3a"
                                Text {
                                    visible: wanted
                                    anchors.centerIn: parent
                                    text: "✓"
                                    color: "#fff"
                                    font.pixelSize: 10
                                    font.bold: true
                                }
                            }
                            MouseArea {
                                anchors.fill: parent
                                acceptedButtons: Qt.LeftButton
                                onClicked: App.setTorrentFileWanted(root.downloadId, index, !wanted)
                            }
                        }

                        Image {
                            width: 16
                            height: 16
                            anchors.verticalCenter: parent.verticalCenter
                            source: root.item
                                    ? ("image://fileicon/"
                                       + root.safeStr(root.item.savePath).replace(/\\/g, "/")
                                       + "/" + root.safeStr(path)
                                       + (isFolder ? "/" : ""))
                                    : ""
                            sourceSize: Qt.size(16, 16)
                            fillMode: Image.PreserveAspectFit
                            asynchronous: true
                        }

                        Text {
                            width: Math.max(40, root.fileColName - Math.max(0, depth) * 14 - 16 - 22 - 16)
                            anchors.verticalCenter: parent.verticalCenter
                            text: name
                            color: !wanted ? "#555" : (isFolder ? "#e0e0e0" : "#d0d0d0")
                            font.pixelSize: 12
                            font.bold: isFolder
                            elide: Text.ElideMiddle
                        }

                        Item {
                            width: Math.max(60, root.fileColProgress)
                            height: parent.height
                            readonly property bool showProgress: !!root.item && (root.item.status === "Seeding" || root.item.status === "Completed" || (root.item.status === "Downloading" && root.item.doneBytes > 0))

                            Text {
                                anchors { left: parent.left; leftMargin: 6; verticalCenter: parent.verticalCenter }
                                text: parent.showProgress ? (Math.round(root.clampPct(progress) * 100) + "%") : "Pending"
                                color: wanted ? "#b0b0b0" : "#555"
                                font.pixelSize: 11
                                width: 46
                            }

                            Rectangle {
                                visible: parent.showProgress
                                anchors { left: parent.left; leftMargin: 46; verticalCenter: parent.verticalCenter }
                                width: Math.max(20, parent.width - 56)
                                height: 8
                                radius: 4
                                color: "#111"
                                border.color: "#2f2f2f"
                                Rectangle {
                                    width: Math.max(0, (parent.width - 2) * root.clampPct(progress))
                                    height: parent.height - 2
                                    radius: 3
                                    anchors.left: parent.left
                                    anchors.leftMargin: 1
                                    anchors.verticalCenter: parent.verticalCenter
                                    color: wanted ? "#4488dd" : "#444"
                                }
                            }
                        }

                        Text {
                            width: Math.max(40, root.fileColSize)
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.formatBytes(size)
                            color: wanted ? "#b0b0b0" : "#555"
                            font.pixelSize: 11
                            horizontalAlignment: Text.AlignLeft
                            elide: Text.ElideRight
                        }

                        Item {
                            width: Math.max(0, metaFileList.contentWidth - root.fileTableWidth())
                            height: parent.height
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
                            metaFileCtxPopup._row = metaFd.index
                            metaFileCtxPopup._fileIndex = metaFd.fileIndex
                            metaFileCtxPopup._path = metaFd.path
                            metaFileCtxPopup._name = metaFd.name
                            metaFileCtxPopup._wanted = metaFd.wanted
                            metaFileCtxPopup._isFolder = metaFd.isFolder
                            var pos = mapToItem(Overlay.overlay, mouse.x, mouse.y)
                            metaFileCtxPopup.x = pos.x
                            metaFileCtxPopup.y = pos.y
                            metaFileCtxPopup.open()
                        }
                    }
                    }
                }
            }

            Window {
                id: metaRenameDialog
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
                flags: Qt.Dialog | Qt.WindowTitleHint | Qt.WindowCloseButtonHint
                property string _path: ""
                property string _currentName: ""
                property int _fileIndex: -1
                property bool _isFolder: false

                function openForRename(path, name, fileIndex, isFolder) {
                    _path = path
                    _currentName = name
                    _fileIndex = fileIndex
                    _isFolder = isFolder
                    metaRenameInput.text = name
                    show()
                    raise()
                    requestActivate()
                }

                onVisibleChanged: {
                    if (!visible)
                        return
                    Qt.callLater(function() {
                        metaRenameInput.forceActiveFocus()
                        metaRenameInput.selectAll()
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
                        Text { text: "Rename item"; color: "#e0e0e0"; font.pixelSize: 14; font.bold: true }
                    }
                    Text { text: "Enter a new file or folder name:"; color: "#aaaaaa"; font.pixelSize: 12 }
                    TextField {
                        id: metaRenameInput
                        Layout.fillWidth: true
                        color: "#d0d0d0"; font.pixelSize: 12
                        selectByMouse: true; leftPadding: 8
                        background: Rectangle {
                            color: "#1b1b1b"
                            border.color: parent.activeFocus ? "#4488dd" : "#3a3a3a"; radius: 3
                        }
                        Keys.onReturnPressed: metaRenameConfirmBtn.clicked()
                        Keys.onEnterPressed:  metaRenameConfirmBtn.clicked()
                    }
                    RowLayout {
                        Layout.fillWidth: true; spacing: 8
                        Item { Layout.fillWidth: true }
                        DlgButton {
                            text: "Cancel"
                            onClicked: metaRenameDialog.close()
                        }
                        DlgButton {
                            id: metaRenameConfirmBtn
                            text: "Rename"; primary: true
                            enabled: {
                                var t = metaRenameInput.text.trim()
                                return t.length > 0
                                    && t !== metaRenameDialog._currentName
                                    && t !== "." && t !== ".."
                                    && t.indexOf("/") === -1
                                    && t.indexOf("\\") === -1
                            }
                            onClicked: {
                                var newName = metaRenameInput.text.trim()
                                if (newName.length > 0 && root.downloadId.length > 0) {
                                    if (metaRenameDialog._isFolder)
                                        App.renameTorrentPath(root.downloadId, metaRenameDialog._path, newName)
                                    else
                                        App.renameTorrentFile(root.downloadId, metaRenameDialog._fileIndex, newName)
                                }
                                metaRenameDialog.close()
                            }
                        }
                    }
                }
            }

            Popup {
                id: metaFileCtxPopup
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
                        color: metaDownloadCtxHover.containsMouse ? "#303030" : "transparent"

                        Row {
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.left: parent.left
                            anchors.leftMargin: 10
                            spacing: 8

                            Rectangle {
                                width: 14
                                height: 14
                                radius: 2
                                color: metaFileCtxPopup._wanted ? "#4488dd" : "#1b1b1b"
                                border.color: metaFileCtxPopup._wanted ? "#4488dd" : "#3a3a3a"
                                Text {
                                    visible: metaFileCtxPopup._wanted
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
                            id: metaDownloadCtxHover
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: {
                                if (root.downloadId.length > 0) {
                                    // Use stable identifiers instead of the visible row
                                    // number, which changes when folders expand/collapse.
                                    if (metaFileCtxPopup._fileIndex >= 0)
                                        App.setTorrentFileWantedByIndex(root.downloadId, metaFileCtxPopup._fileIndex, !metaFileCtxPopup._wanted)
                                    else
                                        App.setTorrentFileWantedByPath(root.downloadId, metaFileCtxPopup._path, !metaFileCtxPopup._wanted)
                                }
                                metaFileCtxPopup.close()
                            }
                        }
                    }

                    Rectangle { width: 180; height: 1; color: "#3a3a3a" }

                    Rectangle {
                        width: 180
                        height: 34
                        color: metaRenameCtxHover.containsMouse ? "#303030" : "transparent"

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
                            id: metaRenameCtxHover
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: {
                                metaFileCtxPopup.close()
                                metaRenameDialog.openForRename(metaFileCtxPopup._path, metaFileCtxPopup._name, metaFileCtxPopup._fileIndex, metaFileCtxPopup._isFolder)
                            }
                        }
                    }
                }
            }
        }
    }
    }
}
