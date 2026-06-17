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
    // While still fetching metadata the dialog collapses to a small cozy window
    // (just name + a slow indeterminate bar); it expands to the full file-picker
    // size once metadata arrives. _applyMetaSize() drives the swap + re-center.
    width: 800
    height: 500
    minimumWidth: 360
    minimumHeight: 150
    title: !metadataArrived ? qsTr("Fetching metadata")
           : (item && item.filename ? item.filename : qsTr("Torrent Metadata"))
    color: ColorPalette.cardBg
    // Qt.Window (not Qt.Dialog) so each metadata window gets its own Windows
    // taskbar button, independent of the main window. Not transient-parented for
    // the same reason — see ownerWindow (used only for centering).
    flags: Qt.Window | Qt.WindowTitleHint | Qt.WindowCloseButtonHint
           | Qt.WindowSystemMenuHint | Qt.WindowMinimizeButtonHint
    // Owner used purely to center this dialog over the main window. NOT
    // transientParent — that would demote this to a tool window with no taskbar entry.
    property var ownerWindow: null

    Material.theme: ColorPalette.materialTheme
    Material.foreground: ColorPalette.textPrimary
    Material.background: ColorPalette.materialBg
    Material.accent: "#4488dd"

    property string downloadId: ""
    property bool startWhenReady: true
    // 0 = Files, 1 = Settings
    property int metaTab: 0

    // Thin context-menu row, matching DownloadTable.qml's CtxMenuItem (22px,
    // opaque bg, icon+text, ✓ for checkable rows, ▶ for submenus).
    component MetaCtxMenuItem: MenuItem {
        id: _mcmi
        implicitHeight: 22
        height: 22
        topPadding: 0; bottomPadding: 0; verticalPadding: 0
        leftPadding: 8; rightPadding: 12
        spacing: 0
        font.pixelSize: 12 * App.fontScale
        property string iconSrc: ""
        // Blank default indicator/arrow — submenu arrow (▶) is appended to the
        // title text instead (matches DownloadTable's "Move to Queue ▶").
        indicator: Item { width: 0; height: 0 }
        arrow: Item { width: 0; height: 0 }
        contentItem: Row {
            spacing: 6
            Item {
                visible: _mcmi.checkable
                width: visible ? 14 : 0
                height: 14
                anchors.verticalCenter: parent.verticalCenter
                Text {
                    visible: _mcmi.checked
                    anchors.centerIn: parent
                    text: "✓"; font.pixelSize: 10 * App.fontScale; font.bold: true
                    color: ColorPalette.textPrimary
                }
            }
            Image {
                visible: _mcmi.iconSrc !== ""
                source: _mcmi.iconSrc !== "" ? "../icons/" + _mcmi.iconSrc : ""
                width: 14; height: 14
                sourceSize.width: 14; sourceSize.height: 14
                fillMode: Image.PreserveAspectFit
                smooth: true
                anchors.verticalCenter: parent.verticalCenter
            }
            Text {
                text: _mcmi.text
                font: _mcmi.font
                color: _mcmi.enabled ? ColorPalette.textPrimary : ColorPalette.textDisabled
                verticalAlignment: Text.AlignVCenter
                elide: Text.ElideRight
                anchors.verticalCenter: parent.verticalCenter
            }
            Item { visible: _mcmi.subMenu !== null; width: visible ? 8 : 0; height: 1 }
            Text {
                visible: _mcmi.subMenu !== null
                anchors.verticalCenter: parent.verticalCenter
                text: "▶"; font.pixelSize: 8 * App.fontScale; color: ColorPalette.textMuted
            }
        }
        background: Rectangle {
            implicitHeight: 22
            // Opaque, never "transparent" — see CLAUDE.md "Linux Software-Backend Menus".
            color: _mcmi.highlighted ? ColorPalette.selectionBg : ColorPalette.menuBg
        }
    }
    readonly property var item: downloadId.length > 0 ? App.downloadById(downloadId) : null
    readonly property var fileModel: downloadId.length > 0 ? App.torrentFileModel(downloadId) : null
    // Latched true once metadata arrives; never flips back. Prevents the Loader
    // from swapping sourceComponent on every libtorrent tick (which resets scroll).
    property bool metadataArrived: false
    // True while a magnet/infohash is still pulling its metadata. The dialog
    // collapses to a small cozy "fetching" window in this state.
    readonly property bool _fetchingMeta: !!item && item.isTorrent && !item.torrentHasMetadata
    // True while the torrent is actually transferring (or being verified/moved).
    // Header progress bar + status word only show in these states or while
    // fetching — never during pre-download file selection (e.g. a lone "Paused").
    readonly property bool _torrentActive: !!item
        && (item.status === "Downloading" || item.status === "Seeding"
            || item.status === "Assembling" || item.status === "Checking"
            || item.status === "Moving")
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
    property real fileColPriority: 90
    signal downloadNowRequested(string downloadId, string savePath, string category, string description)
    signal downloadLaterRequested(string downloadId, string savePath, string category, string description)

    function fileTableWidth() {
        return fileColName + fileColProgress + fileColSize + fileColPriority
    }

    function maxNameColWidth(viewportWidth) {
        var viewport = Number(viewportWidth || width)
        var reserved = fileColProgress + fileColSize + fileColPriority + 28
        return Math.max(180, viewport - reserved)
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
        // Theme-aware: primary text (white on dark, black on light); Mixed dimmed.
        return p === -1 ? ColorPalette.textDisabled : ColorPalette.textPrimary
    }

    function _centerOnOwner() {
        var owner = root.ownerWindow
        if (owner) {
            x = owner.x + Math.round((owner.width  - width)  / 2)
            y = owner.y + Math.round((owner.height - height) / 2)
            return
        }
        x = Math.round((Screen.width  - width)  / 2)
        y = Math.round((Screen.height - height) / 2)
    }

    // Collapse to a small cozy window while fetching metadata; expand to the full
    // file-picker once metadata arrives. Re-center after the size change.
    function _applyMetaSize() {
        if (root.metadataArrived) {
            root.minimumWidth = 800; root.minimumHeight = 460
            root.width = 800;        root.height = 500
        } else {
            root.minimumWidth = 460; root.minimumHeight = 170
            root.width = 480;        root.height = 170
        }
        _centerOnOwner()
    }

    // Expand the moment metadata lands. Deferred so the Loader swap to filesView
    // completes before the window resizes (matches FilePropertiesDialog idiom).
    // A property starting with "_" can't form an on<Prop>Changed handler, so watch
    // it via Connections on self.
    onMetadataArrivedChanged: Qt.callLater(_applyMetaSize)

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
        // Never clear the flag when the user has explicitly opted in to custom paths.
        if (App.settings.torrentUseCustomSavePathByDefault)
            return
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
            root.metadataArrived = !!(root.item && root.item.torrentHasMetadata)
            _applyMetaSize()
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
            }
        }
    }

    // Latch metadata state when item is assigned. (Window title is a declarative
    // binding on `title:` above — don't assign it imperatively or the binding breaks.)
    onItemChanged: {
        if (root.item && root.item.torrentHasMetadata)
            root.metadataArrived = true
    }

    Connections {
        target: root.item
        function onTorrentHasMetadataChanged() {
            if (root.item && root.item.torrentHasMetadata)
                root.metadataArrived = true
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


    function metadataPeerCount() {
        if (!root.item)
            return 0
        return Math.max(root.item.torrentPeers | 0, root.item.torrentListPeers | 0)
    }

    function metadataPeerStatusText() {
        if (!root.item)
            return qsTr("Opening torrent and reading metadata...")
        var peers = metadataPeerCount()
        if (peers <= 0)
            return qsTr("Looking for peers to download metadata...")
        return qsTr("Downloading metadata from %n peer(s)", "", peers)
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
            var path = pathFromFileUrl(folder)
            if (path.length > 0)
                root.setCustomSavePath(path)
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // ?? Fancy header — icon + filename + status + progress ?????????????
        // Mirrors FilePropertiesDialog's torrent header. While a magnet is
        // still fetching metadata the bar shows an orange indeterminate sweep.
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: metaHeaderCol.implicitHeight + 12
            color: ColorPalette.headerStripBg

            ColumnLayout {
                id: metaHeaderCol
                anchors { fill: parent; leftMargin: 14; rightMargin: 14; topMargin: 6; bottomMargin: 6 }
                spacing: 4

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Image {
                        Layout.preferredWidth: 22; Layout.preferredHeight: 22
                        source: {
                            if (!root.item) return "../icons/magnet.svg"
                            var p = String(root.item.savePath || "").replace(/\\/g, "/")
                            var f = String(root.item.filename || "")
                            return (p && f) ? ("image://fileicon/" + p + "/" + f) : "../icons/magnet.svg"
                        }
                        sourceSize: Qt.size(22, 22)
                        fillMode: Image.PreserveAspectFit
                        smooth: true
                        asynchronous: true
                        Layout.alignment: Qt.AlignVCenter
                    }

                    Text {
                        text: root.item && root.item.filename && root.item.filename.length > 0
                              ? root.item.filename
                              : (root.pendingSourceLabel.length > 0 ? root.pendingSourceLabel : qsTr("Torrent Metadata"))
                        color: ColorPalette.textHeader
                        font.pixelSize: 14 * App.fontScale
                        font.bold: true
                        Layout.fillWidth: true
                        elide: Text.ElideMiddle
                    }

                    Text {
                        visible: !!root.item && root.item.status === "Error"
                        text: root.item ? root.item.errorString : ""
                        color: "#e07b7b"
                        font.pixelSize: 12 * App.fontScale
                        elide: Text.ElideRight
                        Layout.maximumWidth: 260
                    }

                    Text {
                        // Only show the status word while actively transferring — not
                        // the lone "Paused"/"Queued" during file selection, and not
                        // "Fetching metadata" (that's the window title now).
                        visible: !!root.item && root.item.status !== "Error"
                                 && root._torrentActive && root.metadataArrived
                        text: root.item ? (root.item.statusText || "") : ""
                        color: ColorPalette.textHeader
                        font.pixelSize: 11 * App.fontScale
                        font.bold: true
                    }
                }

                TorrentProgressBar {
                    Layout.fillWidth: true
                    // Collapse to zero height when not transferring/fetching so the
                    // header stays clean during file selection.
                    visible: root._torrentActive || root._fetchingMeta
                    implicitHeight: visible ? 5 : 0
                    item: root.item
                }
            }
        }

        // Body padding container — the original 12px margins applied per-region
        // so the header/tab strip can span full-width.
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.margins: 12
            spacing: 6

        // ── Cozy fetching panel: shown only while metadata is still downloading.
        // The header already carries the torrent name, the "Fetching metadata…"
        // label and the slow indeterminate progress sweep — here we just add a
        // hint line + a Cancel button so the small window feels complete.
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: !root.metadataArrived
            spacing: 12

            Item { Layout.fillHeight: true }

            Text {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                text: root.item ? root.metadataPeerStatusText() : qsTr("Opening torrent...")
                color: ColorPalette.textSecond
                font.pixelSize: 12 * App.fontScale
                wrapMode: Text.WordWrap
            }

            Item { Layout.fillHeight: true }

            RowLayout {
                Layout.fillWidth: true
                Item { Layout.fillWidth: true }
                DlgButton {
                    text: qsTr("Cancel")
                    onClicked: {
                        if (root.downloadId.length > 0)
                            App.discardTorrentDownload(root.downloadId)
                        root.close()
                    }
                }
            }
        }

        // Tab strip directly below the header: Files | Settings.
        Rectangle {
            Layout.fillWidth: true
            visible: root.metadataArrived
            height: visible ? 30 : 0
            color: ColorPalette.panelBg

            Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: ColorPalette.border }

            Row {
                anchors.fill: parent; spacing: 0
                Repeater {
                    model: [qsTr("Files"), qsTr("Settings")]
                    delegate: Rectangle {
                        required property int index
                        required property string modelData
                        width: metaTabLbl.implicitWidth + 28; height: parent.height
                        color: root.metaTab === index
                               ? ColorPalette.cardBg
                               : (metaTabHov.containsMouse ? ColorPalette.hoverBg : "transparent")
                        Text {
                            id: metaTabLbl; anchors.centerIn: parent
                            text: modelData
                            color: root.metaTab === index ? ColorPalette.textHeader : ColorPalette.textSecond
                            font.pixelSize: 12 * App.fontScale
                        }
                        MouseArea {
                            id: metaTabHov; anchors.fill: parent; hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.metaTab = index
                        }
                    }
                }
            }
        }

        StackLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: root.metadataArrived
            currentIndex: root.metaTab

            // ?? Files page — save options + description + file list ???????????
            ColumnLayout {
                spacing: 6

                // Save path + category
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6

                    Text { text: qsTr("Save to"); color: ColorPalette.textSecond; font.pixelSize: 12 * App.fontScale }

                    TextField {
                        id: savePathField
                        Layout.fillWidth: true
                        Layout.preferredHeight: 32
                        text: root.savePath
                        color: ColorPalette.textPrimary
                        background: Rectangle { color: ColorPalette.inputBg; border.color: ColorPalette.border; radius: 3 }
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
                        text: qsTr("Save As...")
                        Layout.preferredHeight: 32
                        onClicked: saveFolderDialog.open()
                    }

                    Rectangle { width: 1; height: 22; color: ColorPalette.border }

                    Text { text: qsTr("Category"); color: ColorPalette.textSecond; font.pixelSize: 12 * App.fontScale }

                    StyledComboBox {
                        id: categoryCombo
                        implicitWidth: 140
                        model: root.categoryLabels
                        currentIndex: root.categoryIndex()
                        onActivated: {
                            root.category = root.categoryIds[currentIndex] || "all"
                            root.applyCategorySavePath(false)
                        }
                        contentItem: Text {
                            text: categoryCombo.displayText
                            color: ColorPalette.textPrimary
                            verticalAlignment: Text.AlignVCenter
                            leftPadding: 6
                            elide: Text.ElideRight
                            font.pixelSize: 12 * App.fontScale
                        }
                        background: Rectangle { color: ColorPalette.inputBg; border.color: ColorPalette.border; radius: 3 }
                    }
                }

                // Checkboxes
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    visible: !!root.item

                    StyledCheckBox {
                        id: customSavePathCheck
                        text: qsTr("Custom save folder")
                        checked: root.useCustomSavePath
                        Layout.fillWidth: false
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
                            text: parent.text; color: ColorPalette.textPrimary; font.pixelSize: 12 * App.fontScale
                            leftPadding: parent.indicator.width + 4; verticalAlignment: Text.AlignVCenter
                        }
                    }

                    StyledCheckBox {
                        text: qsTr("Remember")
                        checked: root.rememberCustomSavePath
                        enabled: root.useCustomSavePath
                        Layout.fillWidth: false
                        topPadding: 0; bottomPadding: 0
                        onToggled: root.rememberCustomSavePath = checked
                        contentItem: Text {
                            text: parent.text
                            color: parent.enabled ? ColorPalette.textPrimary : "#6f6f6f"; font.pixelSize: 12 * App.fontScale
                            leftPadding: parent.indicator.width + 4; verticalAlignment: Text.AlignVCenter
                        }
                    }

                    Text {
                        text: qsTr("Use category folder")
                        color: root.useCustomSavePath ? "#66aaff" : "#5f5f5f"
                        font.pixelSize: 12 * App.fontScale; font.underline: root.useCustomSavePath
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

                    Item { Layout.fillWidth: true }
                }

                // Description
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6
                    visible: !!root.item

                    Text {
                        text: qsTr("Description")
                        color: ColorPalette.textSecond
                        font.pixelSize: 12 * App.fontScale
                        Layout.alignment: Qt.AlignVCenter
                    }
                    TextField {
                        Layout.fillWidth: true
                        implicitHeight: 26
                        horizontalAlignment: TextInput.AlignLeft
                        text: root.description
                        color: ColorPalette.textPrimary
                        background: Rectangle { color: ColorPalette.inputBg; border.color: ColorPalette.border; radius: 3 }
                        leftPadding: 6; rightPadding: 6; topPadding: 0; bottomPadding: 0
                        verticalAlignment: TextInput.AlignVCenter
                        font.pixelSize: 12 * App.fontScale
                        onTextChanged: root.description = text
                    }
                }

                // File list
                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    color: ColorPalette.inputBg
                    border.color: ColorPalette.border
                    radius: 6
                    clip: true

                    Loader {
                        id: contentLoader
                        anchors.fill: parent
                        // The whole Files page is hidden until metadata arrives (the
                        // cozy fetching panel handles the wait), so this only ever
                        // shows the file list.
                        active: !!root.item && root.metadataArrived
                        sourceComponent: filesView
                    }
                }
            }

            // Settings page
            Item {
                TorrentSettingsPanel {
                    anchors.fill: parent
                    torrentItem: root.metaTab === 1 ? root.item : null
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            // Full action buttons only after metadata arrives — the fetching panel
            // has its own Cancel.
            visible: root.metadataArrived

            Item { Layout.fillWidth: true }

            DlgButton {
                text: qsTr("Cancel")
                onClicked: {
                    if (root.downloadId.length > 0)
                        App.discardTorrentDownload(root.downloadId)
                    root.close()
                }
            }

            DlgButton {
                text: qsTr("Download Later")
                enabled: !!root.item && root.item.status !== "Error"
                onClicked: {
                    root.persistRememberedSavePathIfNeeded()
                    if (root.downloadId.length > 0)
                        root.downloadLaterRequested(root.downloadId, root.savePath, root.category, root.description)
                    root.close()
                }
            }

            DlgButton {
                text: qsTr("Download")
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
        } // body ColumnLayout
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
                Text { text: qsTr("Files"); color: ColorPalette.textPrimary; font.pixelSize: 14 * App.fontScale; font.bold: true }
                Item { Layout.fillWidth: true }
                Text {
                    text: metaFileList ? qsTr("%n item(s)", "", metaFileList.count) : ""
                    color: "#808080"
                    font.pixelSize: 11 * App.fontScale
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.leftMargin: 10
                Layout.rightMargin: 10
                height: 1
                color: ColorPalette.dividerBg
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
                        color: ColorPalette.panelBg
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
                                    text: qsTr("Name")
                                    color: ColorPalette.textPrimary
                                    font.pixelSize: 12 * App.fontScale
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
                                    text: qsTr("Progress")
                                    color: ColorPalette.textPrimary
                                    font.pixelSize: 12 * App.fontScale
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
                                    text: qsTr("Size")
                                    color: ColorPalette.textPrimary
                                    font.pixelSize: 12 * App.fontScale
                                    font.bold: true
                                    elide: Text.ElideRight
                                }
                            }

                            Rectangle {
                                width: root.fileColPriority
                                height: parent.height
                                color: "transparent"
                                Text {
                                    anchors { verticalCenter: parent.verticalCenter; left: parent.left; leftMargin: 6; right: parent.right; rightMargin: 12 }
                                    text: qsTr("Priority")
                                    color: ColorPalette.textPrimary
                                    font.pixelSize: 12 * App.fontScale
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
                        cacheBuffer: 520
                        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                        ScrollBar.horizontal: ScrollBar { policy: ScrollBar.AlwaysOn }

                        Text {
                            anchors.centerIn: parent
                            visible: parent.count === 0
                            text: qsTr("No file information available")
                            color: ColorPalette.textDisabled
                            font.pixelSize: 12 * App.fontScale
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
                    required property int    priority

                    width: Math.max(metaFileList.width, metaFileList.contentWidth)
                    height: 26
                    color: isFolder ? ColorPalette.toolbarBg : (index % 2 === 0 ? ColorPalette.windowBg : ColorPalette.rowAltBg)

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
                                font.pixelSize: 11 * App.fontScale
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
                                color: wanted ? "#4488dd" : ColorPalette.inputBg
                                border.color: wanted ? "#4488dd" : ColorPalette.border
                                Text {
                                    visible: wanted
                                    anchors.centerIn: parent
                                    text: "✓"
                                    color: ColorPalette.textPrimary
                                    font.pixelSize: 10 * App.fontScale
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
                            color: !wanted ? ColorPalette.textDisabled : (isFolder ? ColorPalette.textPrimary : ColorPalette.textPrimary)
                            font.pixelSize: 12 * App.fontScale
                            font.bold: isFolder
                            elide: Text.ElideMiddle
                        }

                        Item {
                            width: Math.max(60, root.fileColProgress)
                            height: parent.height
                            readonly property bool showProgress: !!root.item && (root.item.status === "Seeding" || root.item.status === "Completed" || (root.item.status === "Downloading" && root.item.doneBytes > 0))

                            Text {
                                anchors { left: parent.left; leftMargin: 6; verticalCenter: parent.verticalCenter }
                                text: parent.showProgress ? (Math.round(root.clampPct(progress) * 100) + "%") : qsTr("Pending")
                                color: wanted ? ColorPalette.textPrimary : ColorPalette.textDisabled
                                font.pixelSize: 11 * App.fontScale
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
                            leftPadding: 6   // align with header cell's leftMargin:6
                            text: root.formatBytes(size)
                            color: wanted ? ColorPalette.textPrimary : ColorPalette.textDisabled
                            font.pixelSize: 11 * App.fontScale
                            horizontalAlignment: Text.AlignLeft
                            elide: Text.ElideRight
                        }

                        Text {
                            width: Math.max(40, root.fileColPriority)
                            anchors.verticalCenter: parent.verticalCenter
                            leftPadding: 6   // align with header cell's leftMargin:6
                            text: wanted ? root.priorityLabel(priority) : "—"
                            color: wanted ? root.priorityColor(priority) : ColorPalette.textDisabled
                            font.pixelSize: 11 * App.fontScale
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
                            metaFileCtxMenu._fileIndex = metaFd.fileIndex
                            metaFileCtxMenu._path = metaFd.path
                            metaFileCtxMenu._name = metaFd.name
                            metaFileCtxMenu._wanted = metaFd.wanted
                            metaFileCtxMenu._isFolder = metaFd.isFolder
                            metaFileCtxMenu._priority = metaFd.priority
                            metaFileCtxMenu.popup()
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
                title: qsTr("Rename")
                color: ColorPalette.cardBg
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
                            source: "../icons/rename.svg"
                            sourceSize: Qt.size(16, 16)
                            fillMode: Image.PreserveAspectFit
                            asynchronous: true
                        }
                        Text { text: qsTr("Rename item"); color: ColorPalette.textPrimary; font.pixelSize: 14 * App.fontScale; font.bold: true }
                    }
                    Text { text: qsTr("Enter a new file or folder name:"); color: ColorPalette.textSecond; font.pixelSize: 12 * App.fontScale }
                    TextField {
                        id: metaRenameInput
                        Layout.fillWidth: true
                        color: ColorPalette.textPrimary; font.pixelSize: 12 * App.fontScale
                        selectByMouse: true; leftPadding: 8
                        background: Rectangle {
                            color: ColorPalette.inputBg
                            border.color: parent.activeFocus ? "#4488dd" : ColorPalette.border; radius: 3
                        }
                        Keys.onReturnPressed: metaRenameConfirmBtn.clicked()
                        Keys.onEnterPressed:  metaRenameConfirmBtn.clicked()
                    }
                    RowLayout {
                        Layout.fillWidth: true; spacing: 8
                        Item { Layout.fillWidth: true }
                        DlgButton {
                            text: qsTr("Cancel")
                            onClicked: metaRenameDialog.close()
                        }
                        DlgButton {
                            id: metaRenameConfirmBtn
                            text: qsTr("Rename"); primary: true
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

            // Thin right-click menu — mirrors the main download table's
            // CtxMenuItem style (22px rows, opaque bg). See DownloadTable.qml.
            Menu {
                id: metaFileCtxMenu
                topPadding: 0; bottomPadding: 0
                delegate: MetaCtxMenuItem {}
                property int _fileIndex: -1
                property string _path: ""
                property string _name: ""
                property bool _wanted: true
                property bool _isFolder: false
                property int _priority: 4

                function _applyPriority(level) {
                    if (root.downloadId.length > 0) {
                        if (metaFileCtxMenu._fileIndex >= 0)
                            App.setTorrentFilePriorityByIndex(root.downloadId, metaFileCtxMenu._fileIndex, level)
                        else
                            App.setTorrentFilePriorityByPath(root.downloadId, metaFileCtxMenu._path, level)
                    }
                }

                MetaCtxMenuItem {
                    text: qsTr("Download")
                    checkable: true
                    checked: metaFileCtxMenu._wanted
                    onTriggered: {
                        if (root.downloadId.length > 0) {
                            // Stable identifiers — visible row number shifts on expand/collapse.
                            if (metaFileCtxMenu._fileIndex >= 0)
                                App.setTorrentFileWantedByIndex(root.downloadId, metaFileCtxMenu._fileIndex, !metaFileCtxMenu._wanted)
                            else
                                App.setTorrentFileWantedByPath(root.downloadId, metaFileCtxMenu._path, !metaFileCtxMenu._wanted)
                        }
                    }
                }
                MenuSeparator {}
                // Submenu rendered DownloadTable-style: a plain item with an inline
                // ▶ that pops a child Menu manually on hover. A real Menu{title}
                // subMenu would render the style file's tiny PNG arrow far-right.
                MetaCtxMenuItem {
                    id: _priorityItem
                    text: qsTr("Priority") + "  ▶"
                    enabled: metaFileCtxMenu._wanted
                    onTriggered: _priorityMenu.popup(_priorityItem.width, 0)
                    onHoveredChanged: {
                        if (hovered) { _priorityMenu.popup(_priorityItem.width, 0) }
                        else { _priorityCloseTimer.restart() }
                    }
                    Menu {
                        id: _priorityMenu
                        delegate: MetaCtxMenuItem {}
                        topPadding: 0; bottomPadding: 0
                        onAboutToHide: _priorityCloseTimer.stop()
                        MetaCtxMenuItem { text: qsTr("Low");     checkable: true; checked: metaFileCtxMenu._priority === 1; onTriggered: metaFileCtxMenu._applyPriority(1) }
                        MetaCtxMenuItem { text: qsTr("Normal");  checkable: true; checked: metaFileCtxMenu._priority === 4; onTriggered: metaFileCtxMenu._applyPriority(4) }
                        MetaCtxMenuItem { text: qsTr("High");    checkable: true; checked: metaFileCtxMenu._priority === 6; onTriggered: metaFileCtxMenu._applyPriority(6) }
                        MetaCtxMenuItem { text: qsTr("Maximum"); checkable: true; checked: metaFileCtxMenu._priority === 7; onTriggered: metaFileCtxMenu._applyPriority(7) }
                    }
                    Timer { id: _priorityCloseTimer; interval: 300; onTriggered: { if (!_priorityMenu.activeFocus) _priorityMenu.close() } }
                }
                MenuSeparator {}
                MetaCtxMenuItem {
                    text: qsTr("Rename...")
                    iconSrc: "rename.svg"
                    onTriggered: metaRenameDialog.openForRename(metaFileCtxMenu._path, metaFileCtxMenu._name, metaFileCtxMenu._fileIndex, metaFileCtxMenu._isFolder)
                }
            }
        }
    }
    }
}
