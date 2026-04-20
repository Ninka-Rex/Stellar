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
    height: 560
    minimumWidth: 760
    minimumHeight: 520
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
    property string pendingSourceLabel: ""
    property string savePath: ""
    property string category: ""
    property string description: ""
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

    onVisibleChanged: {
        if (visible) {
            _centerOnOwner()
            if (item) {
                savePath = item.savePath || App.settings.defaultSavePath
                category = item.category || ""
                description = item.description || ""
                refreshCategories()
            }
        }
    }

    // Update window title as soon as the torrent name is known.
    Connections {
        target: root.item
        function onFilenameChanged() {
            if (root.item && root.item.filename && root.item.filename.length > 0)
                root.title = root.item.filename
        }
        function onTorrentHasMetadataChanged() {
            if (root.item && root.item.torrentHasMetadata
                    && root.item.filename && root.item.filename.length > 0)
                root.title = root.item.filename
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
        }
    }

    FolderDialog {
        id: saveFolderDialog
        currentFolder: root.savePath.length > 0
                       ? ("file:///" + root.savePath.replace(/\\/g, "/"))
                       : ""
        onAccepted: {
            var path = selectedFolder.toString()
                .replace(/^file:\/\/\//, "").replace(/^file:\/\//, "")
            if (path.length > 0)
                root.savePath = path
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 16
        spacing: 10

        Text {
            text: root.item && root.item.filename && root.item.filename.length > 0
                  ? root.item.filename
                  : (root.pendingSourceLabel.length > 0 ? root.pendingSourceLabel : "")
            color: "#ffffff"
            font.pixelSize: 18
            font.bold: true
            Layout.fillWidth: true
            elide: Text.ElideRight
        }

        Text {
            text: root.item && root.item.status === "Error"
                  ? root.item.errorString
                  : (root.item && root.item.torrentHasMetadata
                     ? "Choose the files you want before adding the torrent."
                     : root.metadataPeerStatusText())
            color: root.item && root.item.status === "Error" ? "#e07b7b" : "#8e8e8e"
            font.pixelSize: 12
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
        }

        Rectangle { Layout.fillWidth: true; height: 1; color: "#343434" }

        GridLayout {
            Layout.fillWidth: true
            columns: 2
            columnSpacing: 10
            rowSpacing: 8

            Text { text: "Save to"; color: "#a5a5a5"; font.pixelSize: 12 }
            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                TextField {
                    Layout.fillWidth: true
                    text: root.savePath
                    color: "#d7d7d7"
                    background: Rectangle { color: "#171717"; border.color: "#303030"; radius: 4 }
                    leftPadding: 8
                    onTextChanged: root.savePath = text
                }

                DlgButton {
                    text: "Save As..."
                    onClicked: saveFolderDialog.open()
                }
            }

            Text { text: "Category"; color: "#a5a5a5"; font.pixelSize: 12 }
            ComboBox {
                id: categoryCombo
                Layout.fillWidth: true
                model: root.categoryLabels
                currentIndex: root.categoryIndex()
                onActivated: {
                    root.category = root.categoryIds[currentIndex] || "all"
                }
                contentItem: Text {
                    text: categoryCombo.displayText
                    color: "#d7d7d7"
                    verticalAlignment: Text.AlignVCenter
                    leftPadding: 8
                    elide: Text.ElideRight
                }
                background: Rectangle { color: "#171717"; border.color: "#303030"; radius: 4 }
            }

            Text { text: "Description"; color: "#a5a5a5"; font.pixelSize: 12 }
            TextField {
                Layout.fillWidth: true
                text: root.description
                color: "#d7d7d7"
                background: Rectangle { color: "#171717"; border.color: "#303030"; radius: 4 }
                leftPadding: 8
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
                anchors { fill: parent; margins: 12 }
                active: !!root.item
                sourceComponent: root.item && root.item.torrentHasMetadata ? filesView : waitingView
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
                    if (root.downloadId.length > 0)
                        root.downloadNowRequested(root.downloadId, root.savePath, root.category, root.description)
                    root.close()
                }
            }
        }
    }

    Component {
        id: waitingView

        ColumnLayout {
            anchors.centerIn: parent
            spacing: 14

            BusyIndicator {
                running: true
                width: 42
                height: 42
                Layout.alignment: Qt.AlignHCenter
            }

            Text {
                text: root.item ? "Waiting for torrent metadata" : "Opening torrent"
                color: "#d8d8d8"
                font.pixelSize: 14
                font.bold: true
                Layout.alignment: Qt.AlignHCenter
            }

            Text {
                text: {
                    if (!root.item)
                        return "Reading the torrent file and preparing the metadata view."
                    return root.metadataPeerStatusText() + "."
                }
                color: "#8e8e8e"
                font.pixelSize: 11
                wrapMode: Text.WordWrap
                horizontalAlignment: Text.AlignHCenter
                Layout.alignment: Qt.AlignHCenter
                Layout.maximumWidth: 420
            }
        }
    }

    Component {
        id: filesView

        ColumnLayout {
            anchors.fill: parent
            spacing: 8

            RowLayout {
                Layout.fillWidth: true
                Layout.rightMargin: 6
                Text { text: "Files"; color: "#f0f0f0"; font.pixelSize: 14; font.bold: true }
                Item { Layout.fillWidth: true }
                Text {
                    text: metaFileList ? (metaFileList.count + " items") : ""
                    color: "#808080"
                    font.pixelSize: 11
                }
            }

            Rectangle { Layout.fillWidth: true; height: 1; color: "#2d2d2d" }

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
                        contentWidth: width
                        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                        ScrollBar.horizontal: ScrollBar { policy: ScrollBar.AlwaysOff }

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

                    width: ListView.view.width
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
                            readonly property bool showProgress: !!root.item && (root.item.doneBytes > 0 || root.item.status === "Downloading" || root.item.status === "Seeding")

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
                            width: Math.max(0, metaFileList.width - root.fileTableWidth() - 14)
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
