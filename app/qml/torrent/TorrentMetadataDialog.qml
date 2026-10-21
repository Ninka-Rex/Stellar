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
    Material.accent: ColorPalette.accent

    property string downloadId: ""
    property bool startWhenReady: true
    // 0 = Files, 1 = Settings
    property int metaTab: 0

    readonly property var item: downloadId.length > 0 ? App.downloadById(downloadId) : null
    readonly property var fileModel: downloadId.length > 0 ? App.torrentFileModel(downloadId) : null
    // Latched true once metadata arrives; never flips back. Prevents the Loader
    // from swapping sourceComponent on every libtorrent tick (which resets scroll).
    property bool metadataArrived: false
    // Wall-clock bookkeeping for "how long did the swarm take to hand over the
    // metadata". _fetchStartMs stays 0 for .torrent files (metadata already there),
    // so the stat is only shown for magnets / info hashes.
    property double _fetchStartMs: 0
    property double _fetchElapsedMs: 0
    property int _fetchPeers: 0
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
    TorrentLiveUpdatesLease {
        model: root.fileModel
        wanted: root.fileUpdatesActive
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
            App.setWindowIcon(root, ":/qt/qml/com/stellar/app/app/qml/icons/app/stellar.png")
            root._fetchStartMs = (root.item && !root.item.torrentHasMetadata) ? Date.now() : 0
            root._fetchElapsedMs = 0
            root._fetchPeers = 0
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
            root._latchMetadata()
    }

    Connections {
        target: root.item
        function onTorrentHasMetadataChanged() {
            if (root.item && root.item.torrentHasMetadata)
                root._latchMetadata()
        }
    }

    // Single place that flips metadataArrived so the fetch duration is captured
    // exactly once, at the moment of arrival.
    function _latchMetadata() {
        if (metadataArrived)
            return
        if (_fetchStartMs > 0) {
            _fetchElapsedMs = Math.max(1, Date.now() - _fetchStartMs)
            _fetchPeers = metadataPeerCount()
        }
        metadataArrived = true
    }

    // Ticks the live "elapsed" readout in the fetching panel.
    Timer {
        interval: 250
        repeat: true
        running: root.visible && !root.metadataArrived && root._fetchStartMs > 0
        onTriggered: root._fetchElapsedMs = Date.now() - root._fetchStartMs
    }

    // wholeSeconds: live counters tick in whole seconds; the final fetch time
    // keeps one decimal since it is usually only a few seconds.
    function formatDuration(ms, wholeSeconds) {
        var secs = Math.max(0, Number(ms || 0)) / 1000
        if (wholeSeconds)
            secs = Math.floor(secs)
        if (secs < 60)
            return qsTr("%1 s").arg(wholeSeconds ? secs : secs.toFixed(1))
        var mins = Math.floor(secs / 60)
        return qsTr("%1 min %2 s").arg(mins).arg(Math.round(secs - mins * 60))
    }

    // How the torrent was handed to us, for the info strip.
    function sourceKindLabel() {
        var src = item ? safeStr(item.torrentSource).trim() : ""
        if (/^magnet:/i.test(src))
            return qsTr("Magnet link")
        if (/^[0-9a-f]{40}$|^[0-9a-f]{64}$/i.test(src))
            return qsTr("Info hash")
        return qsTr(".torrent file")
    }

    // Facts shown in the info strip once metadata is known. Re-evaluated whenever
    // the item's torrent properties change.
    readonly property var infoFacts: {
        var f = []
        if (!item)
            return f
        if (item.totalBytes > 0)
            f.push({ label: qsTr("Total size"), value: formatBytes(item.totalBytes) })
        if (item.torrentPiecesTotal > 0)
            f.push({ label: qsTr("Pieces"), value: String(item.torrentPiecesTotal) })
        var trackerCount = item.torrentTrackers ? item.torrentTrackers.length : 0
        f.push({ label: qsTr("Trackers"), value: trackerCount > 0 ? String(trackerCount) : qsTr("None (DHT / PEX only)") })
        f.push({ label: qsTr("Type"), value: item.torrentIsPrivate ? qsTr("Private") : qsTr("Public") })
        f.push({ label: qsTr("Source"), value: sourceKindLabel() })
        if (safeStr(item.torrentCreator).length > 0)
            f.push({ label: qsTr("Created by"), value: safeStr(item.torrentCreator) })
        if (safeStr(item.torrentCreatedOn).length > 0)
            f.push({ label: qsTr("Created on"), value: safeStr(item.torrentCreatedOn) })
        if (_fetchElapsedMs > 0 && metadataArrived)
            f.push({ label: qsTr("Metadata retrieved"),
                     value: _fetchPeers > 0
                            ? qsTr("in %1 from %n peer(s)", "", _fetchPeers).arg(formatDuration(_fetchElapsedMs))
                            : qsTr("in %1").arg(formatDuration(_fetchElapsedMs)) })
        return f
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

    // Fetching panel, line 1: is the DHT usable for this torrent, and is it
    // searching for it right now.
    function dhtStatusText() {
        if (!root.item)
            return ""
        if (root.item.torrentIsPrivate)
            return qsTr("DHT: not used (private torrent)")
        if (!App.settings.torrentEnableDht || root.item.torrentDisableDht)
            return qsTr("DHT: disabled")
        var nodes = App.dhtNodes | 0
        if (nodes <= 0)
            return qsTr("DHT: connecting to the network...")
        var lookups = root.item.torrentDhtLookups | 0
        var activity = lookups > 0
                ? qsTr("%n lookup(s) running", "", lookups)
                  + " (" + qsTr("%n reply(s)", "", root.item.torrentDhtReplies | 0) + ")"
                : qsTr("waiting for the next lookup")
        return qsTr("DHT: %n node(s)", "", nodes) + " · " + activity
    }

    // Fetching panel, line 2: libtorrent's peer list for this torrent, and where
    // the connected peers came from.
    function peerDiscoveryText() {
        if (!root.item)
            return ""
        var it = root.item
        var connected = it.torrentConnectedPeers | 0
        var text = qsTr("Peers: %1 found · %2 to try · %3 connected")
                .arg(it.torrentKnownPeers | 0)
                .arg(it.torrentConnectCandidates | 0)
                .arg(connected)
        var sources = []
        if ((it.torrentDhtSourcePeers | 0) > 0) sources.push(qsTr("%1 via DHT").arg(it.torrentDhtSourcePeers))
        if ((it.torrentPexSourcePeers | 0) > 0) sources.push(qsTr("%1 via PEX").arg(it.torrentPexSourcePeers))
        if ((it.torrentLsdSourcePeers | 0) > 0) sources.push(qsTr("%1 via LSD").arg(it.torrentLsdSourcePeers))
        if ((it.torrentTrackerSourcePeers | 0) > 0) sources.push(qsTr("%1 via tracker").arg(it.torrentTrackerSourcePeers))
        if (connected > 0 && sources.length > 0)
            text += " (" + sources.join(" · ") + ")"
        return text
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

            // While the swarm is still handing over the metadata there is no real
            // percentage, so the header itself pulses instead of showing a bar.
            ShiftingHeaderBg {
                anchors.fill: parent
                tint: ColorPalette.brandPurple
                opacity: root.metadataArrived ? 0 : 1
                visible: opacity > 0
                running: !root.metadataArrived
                Behavior on opacity { NumberAnimation { duration: 400 } }
            }

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
                            if (!root.item) return "../icons/actions/copy-magnet-link.svg"
                            var p = String(root.item.savePath || "").replace(/\\/g, "/")
                            var f = String(root.item.filename || "")
                            return (p && f) ? ("image://fileicon/" + p + "/" + f) : "../icons/actions/copy-magnet-link.svg"
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
                        color: ColorPalette.errorText
                        font.pixelSize: 12 * App.fontScale
                        elide: Text.ElideRight
                        Layout.maximumWidth: 260
                    }

                    Text {
                        visible: !root.metadataArrived
                        text: qsTr("Fetching metadata…")
                        color: ColorPalette.textHeader
                        font.pixelSize: 11 * App.fontScale
                        font.bold: true
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
                    visible: root._torrentActive && root.metadataArrived
                    implicitHeight: visible ? 5 : 0
                    item: root.item
                }
            }
        }

        // Tab strip directly below the header: Files | Settings.
        SettingsTabBar {
            visible: root.metadataArrived
            model: [qsTr("Files"), qsTr("Settings")]
            currentIndex: root.metaTab
            onCurrentIndexChanged: root.metaTab = currentIndex
        }

        // Body. No blanket margins: each region pads itself so the file list can
        // run edge to edge like the properties window's Files page.
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 6

        // ── Cozy fetching panel: shown only while metadata is still downloading.
        // The header already carries the torrent name, the "Fetching metadata…"
        // label and the slow indeterminate progress sweep — here we just add a
        // hint line + a Cancel button so the small window feels complete.
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.margins: 12
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

            ColumnLayout {
                Layout.fillWidth: true
                visible: !!root.item
                spacing: 2

                Text {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    text: root.dhtStatusText()
                    color: ColorPalette.textMuted
                    font.pixelSize: 11 * App.fontScale
                    elide: Text.ElideRight
                }
                Text {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    text: root.peerDiscoveryText()
                    color: ColorPalette.textMuted
                    font.pixelSize: 11 * App.fontScale
                    wrapMode: Text.WordWrap
                }
            }

            Text {
                Layout.fillWidth: true
                visible: root._fetchStartMs > 0 && root._fetchElapsedMs > 0
                horizontalAlignment: Text.AlignHCenter
                text: qsTr("Elapsed: %1").arg(root.formatDuration(root._fetchElapsedMs, true))
                color: ColorPalette.textMuted
                font.pixelSize: 11 * App.fontScale
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
                    Layout.topMargin: 12
                    Layout.leftMargin: 12
                    Layout.rightMargin: 12
                    spacing: 6

                    Text { text: qsTr("Save to"); color: ColorPalette.textSecond; font.pixelSize: 12 * App.fontScale }

                    SettingsTextField {
                        id: savePathField
                        implicitHeight: 26
                        text: root.savePath
                        onTextChanged: {
                            root.savePath = text
                            root.refreshSavePathMode()
                            root.syncPersistentCustomSaveState()
                        }
                    }

                    // Same height as the path box beside it. The style's default
                    // insets would draw the button shorter than its item.
                    DlgButton {
                        text: qsTr("Save As...")
                        implicitHeight: savePathField.implicitHeight
                        topInset: 0; bottomInset: 0
                        onClicked: saveFolderDialog.open()
                    }

                    Rectangle { width: 1; Layout.preferredHeight: 20; color: ColorPalette.border }

                    Text { text: qsTr("Category"); color: ColorPalette.textSecond; font.pixelSize: 12 * App.fontScale }

                    StyledComboBox {
                        id: categoryCombo
                        implicitWidth: 140
                        implicitHeight: savePathField.implicitHeight
                        model: root.categoryLabels
                        currentIndex: root.categoryIndex()
                        font.pixelSize: 12 * App.fontScale
                        onActivated: {
                            root.category = root.categoryIds[currentIndex] || "all"
                            root.applyCategorySavePath(false)
                        }
                    }
                }

                // Checkboxes
                RowLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: 12
                    Layout.rightMargin: 12
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
                            color: parent.enabled ? ColorPalette.textPrimary : ColorPalette.textDisabled; font.pixelSize: 12 * App.fontScale
                            leftPadding: parent.indicator.width + 4; verticalAlignment: Text.AlignVCenter
                        }
                    }

                    Text {
                        text: qsTr("Use category folder")
                        color: root.useCustomSavePath ? ColorPalette.accentHover : ColorPalette.textDisabled
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
                    Layout.leftMargin: 12
                    Layout.rightMargin: 12
                    spacing: 6
                    visible: !!root.item

                    Text {
                        text: qsTr("Description")
                        color: ColorPalette.textSecond
                        font.pixelSize: 12 * App.fontScale
                        Layout.alignment: Qt.AlignVCenter
                    }
                    SettingsTextField {
                        implicitHeight: savePathField.implicitHeight
                        text: root.description
                        font.pixelSize: 12 * App.fontScale
                        onTextChanged: root.description = text
                    }
                }

                // Torrent facts as a plain property sheet, styled like the
                // properties window's General tab.
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: 4
                    Layout.leftMargin: 12
                    Layout.rightMargin: 12
                    visible: !!root.item
                    spacing: 4

                    SectionHeader { text: qsTr("Torrent") }

                    GridLayout {
                        Layout.fillWidth: true
                        columns: 3; columnSpacing: 10; rowSpacing: 2

                        Repeater {
                            model: root.infoFacts
                            delegate: RowLayout {
                                required property var modelData
                                Layout.fillWidth: true
                                Layout.preferredWidth: 100
                                spacing: 10
                                SheetKey { text: modelData.label }
                                SheetValue { text: modelData.value }
                            }
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        visible: root.safeStr(root.item ? root.item.torrentInfoHash : "").length > 0
                        spacing: 10
                        SheetKey { text: qsTr("Info hash") }
                        ReadOnlyField {
                            Layout.fillWidth: true
                            fieldText: root.item ? root.safeStr(root.item.torrentInfoHash) : ""
                        }
                        SettingsLink {
                            Layout.alignment: Qt.AlignVCenter
                            text: qsTr("Copy")
                            onClicked: App.copyToClipboard(root.safeStr(root.item.torrentInfoHash))
                        }
                    }
                }

                // File list, edge to edge.
                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.topMargin: 4
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
                    anchors { fill: parent; topMargin: 12; leftMargin: 12; rightMargin: 12 }
                    torrentItem: root.metaTab === 1 ? root.item : null
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 12
            Layout.rightMargin: 12
            Layout.bottomMargin: 12
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

            Item {
                id: metaFileViewport
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true

                ColumnLayout {
                    anchors.fill: parent
                    spacing: 0

                    Rectangle {
                        id: metaHeader
                        Layout.fillWidth: true
                        height: 26
                        color: ColorPalette.dividerBg
                        clip: true
                        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: ColorPalette.border }

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
                        color: ColorPalette.dividerBg
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
                            TreeExpander {
                                visible: isFolder
                                anchors.centerIn: parent
                                expanded: metaFd.expanded
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
                                color: wanted ? ColorPalette.accent : ColorPalette.inputBg
                                border.color: wanted ? ColorPalette.accent : ColorPalette.border
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
                                color: ColorPalette.progressTrack
                                border.color: ColorPalette.progressTrackBorder
                                Rectangle {
                                    width: Math.max(0, (parent.width - 2) * root.clampPct(progress))
                                    height: parent.height - 2
                                    anchors.left: parent.left
                                    anchors.leftMargin: 1
                                    anchors.verticalCenter: parent.verticalCenter
                                    color: wanted ? ColorPalette.progressDownloading : ColorPalette.textDisabled
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
                            source: "../icons/actions/edit-rename.svg"
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
                            border.color: parent.activeFocus ? ColorPalette.borderFocus : ColorPalette.border
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
                delegate: FileCtxMenuItem {}
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

                FileCtxMenuItem {
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
                FileCtxMenuItem {
                    id: _priorityItem
                    text: qsTr("Priority") + "  ▶"
                    iconSrc: "status/priority.svg"
                    enabled: metaFileCtxMenu._wanted
                    onTriggered: _priorityMenu.popup(_priorityItem.width, 0)
                    onHoveredChanged: {
                        if (hovered) { _priorityMenu.popup(_priorityItem.width, 0) }
                        else { _priorityCloseTimer.restart() }
                    }
                    Menu {
                        id: _priorityMenu
                        delegate: FileCtxMenuItem {}
                        topPadding: 0; bottomPadding: 0
                        onAboutToHide: _priorityCloseTimer.stop()
                        FileCtxMenuItem { text: qsTr("Low");     iconSrc: "status/priority-low.svg";     checkable: true; checked: metaFileCtxMenu._priority === 1; onTriggered: metaFileCtxMenu._applyPriority(1) }
                        FileCtxMenuItem { text: qsTr("Normal");  iconSrc: "status/priority-normal.svg";  checkable: true; checked: metaFileCtxMenu._priority === 4; onTriggered: metaFileCtxMenu._applyPriority(4) }
                        FileCtxMenuItem { text: qsTr("High");    iconSrc: "status/priority-high.svg";    checkable: true; checked: metaFileCtxMenu._priority === 6; onTriggered: metaFileCtxMenu._applyPriority(6) }
                        FileCtxMenuItem { text: qsTr("Maximum"); iconSrc: "status/priority-maximum.svg"; checkable: true; checked: metaFileCtxMenu._priority === 7; onTriggered: metaFileCtxMenu._applyPriority(7) }
                    }
                    Timer { id: _priorityCloseTimer; interval: 300; onTriggered: { if (!_priorityMenu.activeFocus) _priorityMenu.close() } }
                }
                MenuSeparator {}
                FileCtxMenuItem {
                    text: qsTr("Copy Name")
                    iconSrc: "actions/copy-name.svg"
                    onTriggered: App.copyToClipboard(metaFileCtxMenu._name)
                }
                FileCtxMenuItem {
                    text: qsTr("Rename...")
                    iconSrc: "actions/edit-rename.svg"
                    onTriggered: metaRenameDialog.openForRename(metaFileCtxMenu._path, metaFileCtxMenu._name, metaFileCtxMenu._fileIndex, metaFileCtxMenu._isFolder)
                }
            }
        }
    }
    }
}
