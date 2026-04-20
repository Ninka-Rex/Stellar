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
import QtQuick.Layouts
import QtCore

Window {
    id: root
    width: 980
    height: 620
    minimumWidth: 860
    minimumHeight: 480
    title: "RSS Feeds"
    color: "#1b1b1b"
    flags: Qt.Dialog | Qt.WindowTitleHint | Qt.WindowCloseButtonHint | Qt.WindowSystemMenuHint

    property int selectedFeedRow: -1
    property int selectedArticleRow: -1
    property real leftPaneWidth: 220
    property real previewPaneHeight: 210
    property string editingFeedId: ""
    property string articleSortKey: "published"
    property bool articleSortAscending: false
    property var columnDefs: [
        { title: "Title",  key: "title",     widthPx: 420, visible: true },
        { title: "Feed",   key: "feed",      widthPx: 150, visible: true },
        { title: "Date",   key: "published", widthPx: 120, visible: true }
    ]
    property bool _colDragging: false
    property string _colDragFromKey: ""
    property string _colDragInsertBeforeKey: ""
    property string _resizingColumnKey: ""
    property real _resizingColumnWidth: 0
    property int _feedDragFrom: -1
    property int _feedDropTarget: -1
    property bool _feedDragging: false

    readonly property var selectedFeed: App.rssManager.feedModel.feedData(selectedFeedRow)
    readonly property var allArticles: {
        var items = []
        for (var i = 0; i < App.rssManager.articleCount; ++i)
            items.push(App.rssManager.articleModel.articleData(i))
        return items
    }
    readonly property var sortedArticles: {
        var items = allArticles.slice()
        items.sort(function(a, b) {
            var av, bv
            if (root.articleSortKey === "feed") {
                av = (a.feedTitle || "").toLowerCase()
                bv = (b.feedTitle || "").toLowerCase()
            } else if (root.articleSortKey === "published") {
                av = new Date(a.published || 0).getTime()
                bv = new Date(b.published || 0).getTime()
            } else {
                av = (a.title || "").toLowerCase()
                bv = (b.title || "").toLowerCase()
            }
            if (av === bv) {
                var at = (a.title || "").toLowerCase()
                var bt = (b.title || "").toLowerCase()
                return at < bt ? -1 : (at > bt ? 1 : 0)
            }
            return root.articleSortAscending ? (av < bv ? -1 : 1) : (av > bv ? -1 : 1)
        })
        return items
    }
    readonly property var selectedArticle: (selectedArticleRow >= 0 && selectedArticleRow < sortedArticles.length)
        ? sortedArticles[selectedArticleRow] : ({})
    readonly property bool selectedArticleHasDownload: !!selectedArticle.isTorrent || !!selectedArticle.downloadUrl
    readonly property string selectedArticleImageUrl: {
        if (selectedArticle.imageUrl && selectedArticle.imageUrl.length > 0)
            return selectedArticle.imageUrl
        var html = selectedArticle.descriptionHtml || ""
        var match = /<img\b[^>]*\bsrc\s*=\s*['"]([^'"]+)['"][^>]*>/i.exec(html)
        return match ? match[1] : ""
    }
    readonly property var visibleCols: {
        var cols = []
        for (var i = 0; i < columnDefs.length; ++i)
            if (columnDefs[i].visible) cols.push(columnDefs[i])
        return cols
    }
    readonly property real visibleContentWidth: {
        var total = 0
        for (var i = 0; i < visibleCols.length; ++i)
            total += colWidth(visibleCols[i].key)
        return total
    }

    function syncFeedSelection() {
        var currentFeedId = App.rssManager.currentFeedId || ""
        if (currentFeedId.length === 0) { selectedFeedRow = -1; return }
        for (var i = 0; i < App.rssManager.feedCount; ++i) {
            var feed = App.rssManager.feedModel.feedData(i)
            if (feed.feedId === currentFeedId) { selectedFeedRow = i; return }
        }
        selectedFeedRow = -1
    }

    function ensureArticleSelection() {
        if (sortedArticles.length <= 0) selectedArticleRow = -1
        else if (selectedArticleRow < 0 || selectedArticleRow >= sortedArticles.length)
            selectedArticleRow = 0
    }

    function colWidth(key) {
        if (_resizingColumnKey === key) return _resizingColumnWidth
        for (var i = 0; i < columnDefs.length; ++i)
            if (columnDefs[i].key === key) return columnDefs[i].widthPx || 100
        return 100
    }

    function applyArticleSort(key) {
        if (articleSortKey === key) articleSortAscending = !articleSortAscending
        else { articleSortKey = key; articleSortAscending = key === "feed" }
        ensureArticleSelection()
    }

    function addSubscription() {
        var url = addFeedField.text.trim()
        if (url.length === 0) return
        if (App.rssManager.addSubscription(url)) addFeedField.clear()
        syncFeedSelection(); ensureArticleSelection()
    }

    function selectFeed(row) {
        selectedFeedRow = row
        var feed = App.rssManager.feedModel.feedData(row)
        App.rssManager.currentFeedId = feed.feedId || ""
        ensureArticleSelection()
    }

    function refreshCurrentFeed() {
        if (selectedFeed.feedId) App.rssManager.refreshFeed(selectedFeed.feedId)
        else App.rssManager.refreshAll()
    }

    function removeCurrentFeed() {
        if (!selectedFeed.feedId) return
        App.rssManager.removeSubscription(selectedFeed.feedId)
        syncFeedSelection(); ensureArticleSelection()
    }

    function editCurrentFeed() {
        if (!selectedFeed.feedId) return
        editingFeedId = selectedFeed.feedId
        editFeedNameField.text = selectedFeed.customTitle || ""
        editFeedUrlField.text  = selectedFeed.url || ""
        editFeedDialog.show(); editFeedDialog.raise(); editFeedDialog.requestActivate()
    }

    function saveEditedFeed() {
        if (!editingFeedId) return
        if (App.rssManager.updateSubscription(editingFeedId, editFeedUrlField.text, editFeedNameField.text)) {
            editFeedDialog.close(); syncFeedSelection()
        }
    }

    function markSelectedArticleRead(read) {
        if (!selectedArticle.feedId || !selectedArticle.guid) return
        App.rssManager.markArticleReadByGuid(selectedArticle.feedId, selectedArticle.guid, read)
    }

    function openSelectedArticle() {
        if (!selectedArticle.link) return
        markSelectedArticleRead(true)
        Qt.openUrlExternally(selectedArticle.link)
    }

    function triggerSelectedDownload() {
        if (!selectedArticleHasDownload) return openSelectedArticle()
        var url = selectedArticle.downloadUrl && selectedArticle.downloadUrl.length > 0
            ? selectedArticle.downloadUrl : selectedArticle.link
        markSelectedArticleRead(true)
        if (selectedArticle.isTorrent)
            App.beginTorrentMetadataDownload(url, App.settings.defaultSavePath, "", selectedArticle.title || "", true)
        else
            App.addUrl(url, App.settings.defaultSavePath, "", selectedArticle.title || "", true)
    }

    function copySelectedLink() {
        var url = selectedArticle.downloadUrl || selectedArticle.link || ""
        if (url.length > 0) App.copyToClipboard(url)
    }

    function applyColReorder() {
        if (!_colDragFromKey) return
        var defs = columnDefs.slice()
        var fromIdx = -1
        for (var i = 0; i < defs.length; ++i) { if (defs[i].key === _colDragFromKey) { fromIdx = i; break } }
        if (fromIdx < 0) return
        var toIdx = defs.length
        if (_colDragInsertBeforeKey !== "__end__") {
            for (var j = 0; j < defs.length; ++j) { if (defs[j].key === _colDragInsertBeforeKey) { toIdx = j; break } }
        }
        if (toIdx === fromIdx) return
        var moved = defs.splice(fromIdx, 1)[0]
        if (toIdx > fromIdx) toIdx--
        defs.splice(toIdx, 0, moved)
        columnDefs = defs
    }

    function applyFeedReorder() {
        if (!_feedDragging || _feedDragFrom < 0 || _feedDropTarget < 0) return
        if (_feedDragFrom === _feedDropTarget) return
        var to = (_feedDragFrom < _feedDropTarget) ? _feedDropTarget - 1 : _feedDropTarget
        if (to === _feedDragFrom) return
        App.rssManager.moveSubscription(_feedDragFrom, to)
        syncFeedSelection()
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
        if (visible) _centerOnOwner()
    }

    Component.onCompleted: {
        App.setWindowIcon(root, "qrc:/qt/qml/com/stellar/app/app/qml/icons/rss.png")
        syncFeedSelection(); ensureArticleSelection()
    }

    Connections {
        target: App.rssManager
        function onCurrentFeedIdChanged() { root.syncFeedSelection(); root.ensureArticleSelection() }
        function onArticleModelChanged()  { root.ensureArticleSelection() }
    }

    Settings {
        category: "RssWindow"
        property alias leftPaneWidth:    root.leftPaneWidth
        property alias previewPaneHeight: root.previewPaneHeight
    }

    // ── Feed context menu ────────────────────────────────────────────────────
    Menu {
        id: feedContextMenu
        property int row: -1
        delegate: MenuItem {
            implicitWidth: 180
            implicitHeight: 24
            leftPadding: 12
            contentItem: Text { text: parent.text; color: "#d0d0d0"; font.pixelSize: 12; verticalAlignment: Text.AlignVCenter }
            background: Rectangle { color: parent.highlighted ? "#2a3f6a" : "transparent" }
        }
        implicitWidth: 180
        topPadding: 0; bottomPadding: 0
        Action {
            text: "Open Feed"
            onTriggered: if (feedContextMenu.row >= 0) root.selectFeed(feedContextMenu.row)
        }
        Action {
            text: "Refresh"
            onTriggered: {
                var feed = App.rssManager.feedModel.feedData(feedContextMenu.row)
                if (feed.feedId) App.rssManager.refreshFeed(feed.feedId)
            }
        }
        MenuSeparator {}
        Action {
            text: "Rename / Edit..."
            onTriggered: { root.selectedFeedRow = feedContextMenu.row; root.editCurrentFeed() }
        }
        Action {
            text: "Remove Subscription"
            onTriggered: {
                var feed = App.rssManager.feedModel.feedData(feedContextMenu.row)
                if (feed.feedId) App.rssManager.removeSubscription(feed.feedId)
                root.syncFeedSelection(); root.ensureArticleSelection()
            }
        }
    }

    // ── Article context menu ─────────────────────────────────────────────────
    Menu {
        id: articleContextMenu
        delegate: MenuItem {
            implicitWidth: 190
            implicitHeight: 24
            leftPadding: 12
            contentItem: Text { text: parent.text; color: parent.enabled ? "#d0d0d0" : "#555"; font.pixelSize: 12; verticalAlignment: Text.AlignVCenter }
            background: Rectangle { color: parent.highlighted ? "#2a3f6a" : "transparent" }
        }
        implicitWidth: 190
        topPadding: 0; bottomPadding: 0
        Action {
            text: selectedArticle.isTorrent ? "Download Torrent" : "Download"
            enabled: root.selectedArticleHasDownload
            onTriggered: root.triggerSelectedDownload()
        }
        Action {
            text: "Open in Browser"
            enabled: !!root.selectedArticle.link
            onTriggered: root.openSelectedArticle()
        }
        Action {
            text: "Copy Link"
            enabled: root.selectedArticleRow >= 0
            onTriggered: root.copySelectedLink()
        }
        MenuSeparator {}
        Action {
            text: root.selectedArticle.unread ? "Mark as Read" : "Mark as Unread"
            enabled: root.selectedArticleRow >= 0
            onTriggered: root.markSelectedArticleRead(!!root.selectedArticle.unread)
        }
        Action {
            text: "Mark All Read"
            onTriggered: App.rssManager.markAllRead(root.selectedFeed.feedId || "")
        }
    }

    // ── Edit subscription dialog ─────────────────────────────────────────────
    Window {
        id: editFeedDialog
        width: 440
        height: 170
        minimumWidth: 400
        minimumHeight: 160
        title: "Edit Subscription"
        color: "#1e1e1e"
        modality: Qt.ApplicationModal
        flags: Qt.Dialog | Qt.WindowTitleHint | Qt.WindowCloseButtonHint

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 14
            spacing: 10

            GridLayout {
                columns: 2
                columnSpacing: 10
                rowSpacing: 8
                Layout.fillWidth: true

                Text { text: "Name"; color: "#a0a0a0"; font.pixelSize: 12 }
                TextField {
                    id: editFeedNameField
                    Layout.fillWidth: true
                    placeholderText: "Custom name (optional)"
                    font.pixelSize: 12
                    color: "#d0d0d0"
                    background: Rectangle { color: "#2d2d2d"; border.color: activeFocus ? "#4488dd" : "#4a4a4a"; radius: 3 }
                }

                Text { text: "URL"; color: "#a0a0a0"; font.pixelSize: 12 }
                TextField {
                    id: editFeedUrlField
                    Layout.fillWidth: true
                    placeholderText: "https://..."
                    font.pixelSize: 12
                    color: "#d0d0d0"
                    onAccepted: root.saveEditedFeed()
                    background: Rectangle { color: "#2d2d2d"; border.color: activeFocus ? "#4488dd" : "#4a4a4a"; radius: 3 }
                }
            }

            Item { Layout.fillHeight: true }

            RowLayout {
                Layout.fillWidth: true
                Item { Layout.fillWidth: true }
                DlgButton { text: "Cancel"; onClicked: editFeedDialog.close() }
                DlgButton {
                    text: "Save"
                    primary: true
                    enabled: editFeedUrlField.text.trim().length > 0
                    onClicked: root.saveEditedFeed()
                }
            }
        }
    }

    // ── Main layout ──────────────────────────────────────────────────────────
    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // Toolbar strip
        Rectangle {
            Layout.fillWidth: true
            height: 42
            color: "#252525"

            Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: "#333333" }

            RowLayout {
                anchors { fill: parent; leftMargin: 8; rightMargin: 8 }
                spacing: 4

                // URL input
                Rectangle {
                    Layout.fillWidth: true
                    height: 26
                    color: "#2d2d2d"
                    border.color: addFeedField.activeFocus ? "#4488dd" : "#4a4a4a"
                    radius: 3

                    TextInput {
                        id: addFeedField
                        anchors { fill: parent; leftMargin: 8; rightMargin: 8 }
                        verticalAlignment: Text.AlignVCenter
                        font.pixelSize: 12
                        color: "#d0d0d0"
                        clip: true
                        onAccepted: root.addSubscription()

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Add RSS or Atom feed URL..."
                            color: "#555"
                            font.pixelSize: 12
                            visible: !parent.text && !parent.activeFocus
                        }
                    }
                }

                DlgButton {
                    text: "Add"
                    primary: true
                    enabled: addFeedField.text.trim().length > 0
                    onClicked: root.addSubscription()
                }

                // Separator
                Rectangle { width: 1; height: 22; color: "#383838" }

                DlgButton {
                    text: App.rssManager.refreshInProgress ? "Refreshing…" : "Refresh"
                    enabled: !App.rssManager.refreshInProgress
                    onClicked: root.refreshCurrentFeed()
                }
                DlgButton {
                    text: "Edit"
                    enabled: !!selectedFeed.feedId
                    onClicked: root.editCurrentFeed()
                }
                DlgButton {
                    text: "Remove"
                    enabled: !!selectedFeed.feedId
                    onClicked: root.removeCurrentFeed()
                }

                // Separator
                Rectangle { width: 1; height: 22; color: "#383838" }

                DlgButton {
                    text: "Download Rules"
                    onClicked: {
                        rssRulesDialog.show(); rssRulesDialog.raise(); rssRulesDialog.requestActivate()
                    }
                }
            }
        }

        // Body: feed list + article area
        SplitView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            orientation: Qt.Horizontal

            handle: Rectangle {
                implicitWidth: 4
                color: SplitHandle.hovered || SplitHandle.pressed ? "#3a5a8a" : "#2a2a2a"
            }

            // ── Left: feed list ──────────────────────────────────────────────
            Rectangle {
                SplitView.preferredWidth: root.leftPaneWidth
                SplitView.minimumWidth: 170
                color: "#1f1f1f"

                ColumnLayout {
                    anchors.fill: parent
                    spacing: 0

                    // Header
                    Rectangle {
                        Layout.fillWidth: true
                        height: 26
                        color: "#2d2d2d"

                        Rectangle { width: 3; height: parent.height; color: "#5588cc" }
                        Text {
                            anchors { verticalCenter: parent.verticalCenter; left: parent.left; leftMargin: 10 }
                            text: "Subscriptions"
                            color: "#d0d0d0"
                            font.pixelSize: 12
                            font.bold: true
                        }
                        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: "#3a3a3a" }
                    }

                    // Feed list
                    ListView {
                        id: feedList
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        model: App.rssManager.feedModel
                        boundsBehavior: Flickable.StopAtBounds
                        ScrollBar.vertical: ScrollBar {}

                        // Drop indicator at the end of the list
                        footer: Item {
                            width: feedList.width
                            height: 2
                            visible: root._feedDragging
                                  && root._feedDropTarget === App.rssManager.feedCount
                                  && root._feedDragFrom !== App.rssManager.feedCount - 1
                            Rectangle { anchors.fill: parent; color: "#4488dd" }
                        }

                        delegate: Item {
                            id: feedDelegate
                            required property string title
                            required property string url
                            required property string errorText
                            required property int unreadCount
                            required property int totalCount
                            required property string feedId
                            required property bool updating
                            required property int index
                            readonly property int rowIndex: index
                            width: feedList.width
                            height: 28

                            // Drag insert line
                            Rectangle {
                                visible: root._feedDragging
                                      && root._feedDropTarget === feedDelegate.rowIndex
                                      && root._feedDragFrom !== root._feedDropTarget
                                      && root._feedDragFrom !== root._feedDropTarget - 1
                                anchors { top: parent.top; left: parent.left; right: parent.right }
                                height: 2; color: "#4488dd"; z: 10
                            }

                            Rectangle {
                                anchors.fill: parent
                                color: root.selectedFeedRow === rowIndex ? "#1e3a6e"
                                     : (feedMouse.containsMouse && !root._feedDragging ? "#2a2a3a" : "transparent")
                                border.color: root.selectedFeedRow === rowIndex ? "#4488dd" : "transparent"
                                border.width: 1
                                opacity: (root._feedDragging && root._feedDragFrom === rowIndex) ? 0.4 : 1.0

                                RowLayout {
                                    anchors { fill: parent; leftMargin: 10; rightMargin: 6 }
                                    spacing: 0

                                    // Feed name — fills available space
                                    Text {
                                        Layout.fillWidth: true
                                        text: title || url
                                        color: root.selectedFeedRow === rowIndex ? "#88bbff" : "#cccccc"
                                        font.pixelSize: 12
                                        font.bold: unreadCount > 0
                                        elide: Text.ElideRight
                                    }

                                    // Updating spinner placeholder
                                    Text {
                                        visible: feedDelegate.updating
                                        text: "↻"
                                        color: "#5588cc"
                                        font.pixelSize: 12
                                    }

                                    // Unread badge
                                    Rectangle {
                                        visible: unreadCount > 0 && !feedDelegate.updating
                                        width: unreadLabel.implicitWidth + 8
                                        height: 16
                                        radius: 8
                                        color: root.selectedFeedRow === rowIndex ? "#2a4a8a" : "#1a3060"
                                        border.color: root.selectedFeedRow === rowIndex ? "#5588cc" : "#3a5080"

                                        Text {
                                            id: unreadLabel
                                            anchors.centerIn: parent
                                            text: unreadCount
                                            color: "#88bbff"
                                            font.pixelSize: 10
                                            font.bold: true
                                        }
                                    }

                                    Item { width: 2 }
                                }
                            }

                            // Error indicator line at bottom
                            Rectangle {
                                visible: feedDelegate.errorText.length > 0
                                anchors { bottom: parent.bottom; left: parent.left; right: parent.right }
                                height: 2
                                color: "#883333"
                            }

                            MouseArea {
                                id: feedMouse
                                anchors.fill: parent
                                acceptedButtons: Qt.LeftButton | Qt.RightButton
                                hoverEnabled: true
                                preventStealing: true
                                property real _pressY: 0
                                property bool _didDrag: false

                                onPressed: { _pressY = mouseY; _didDrag = false }

                                onPositionChanged: {
                                    if (!(pressedButtons & Qt.LeftButton)) return
                                    if (!root._feedDragging && Math.abs(mouseY - _pressY) > 6) {
                                        root._feedDragFrom = rowIndex
                                        root._feedDragging = true
                                        _didDrag = true
                                    }
                                    if (root._feedDragging) {
                                        var cursorY = feedMouse.mapToItem(feedList.contentItem, mouseX, mouseY).y
                                        var target = App.rssManager.feedCount
                                        for (var r = 0; r < App.rssManager.feedCount; ++r) {
                                            if (cursorY < r * 28 + 14) { target = r; break }
                                        }
                                        root._feedDropTarget = target
                                    }
                                }

                                onReleased: {
                                    var dragFrom  = root._feedDragFrom
                                    var dragging  = root._feedDragging
                                    var dropTarget = root._feedDropTarget
                                    Qt.callLater(function() {
                                        if (dragging && dragFrom === rowIndex && dropTarget >= 0)
                                            root.applyFeedReorder()
                                        root._feedDragging = false
                                        root._feedDragFrom = -1
                                        root._feedDropTarget = -1
                                    })
                                }

                                onClicked: function(mouse) {
                                    if (_didDrag) { _didDrag = false; return }
                                    if (mouse.button === Qt.RightButton) {
                                        root.selectedFeedRow = rowIndex
                                        feedContextMenu.row = rowIndex
                                        feedContextMenu.popup()
                                    } else {
                                        root.selectFeed(rowIndex)
                                    }
                                }
                            }
                        }
                    }

                    // Mark all read button at the bottom of the feed pane
                    Rectangle {
                        Layout.fillWidth: true
                        height: 30
                        color: "#252525"
                        Rectangle { anchors.top: parent.top; width: parent.width; height: 1; color: "#333333" }

                        Text {
                            anchors.centerIn: parent
                            text: "Mark All Read"
                            color: markAllReadMouse.containsMouse ? "#88bbff" : "#7a8a9a"
                            font.pixelSize: 11

                            MouseArea {
                                id: markAllReadMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: App.rssManager.markAllRead(root.selectedFeed.feedId || "")
                            }
                        }
                    }
                }
            }

            // ── Right: article list + preview ────────────────────────────────
            Rectangle {
                SplitView.fillWidth: true
                color: "#1c1c1c"

                ColumnLayout {
                    anchors.fill: parent
                    spacing: 0

                    // Column header
                    Rectangle {
                        Layout.fillWidth: true
                        height: 26
                        color: "#2d2d2d"
                        clip: true

                        Row {
                            id: headerRow
                            width: root.visibleContentWidth
                            height: parent.height

                            Repeater {
                                id: headerCellRepeater
                                model: root.visibleCols
                                delegate: Rectangle {
                                    id: headerCell
                                    width: root.colWidth(modelData.key)
                                    height: parent.height
                                    readonly property bool isActive: root.articleSortKey === modelData.key
                                    color: headerCellMouse.containsMouse && !root._colDragging ? "#383838" : "transparent"
                                    opacity: (root._colDragging && root._colDragFromKey === modelData.key) ? 0.5 : 1.0

                                    Rectangle {
                                        visible: root._colDragging && root._colDragInsertBeforeKey === modelData.key
                                        width: 2; height: parent.height; anchors.left: parent.left
                                        color: "#4488dd"; z: 20
                                    }
                                    Rectangle {
                                        visible: root._colDragging && root._colDragInsertBeforeKey === "__end__"
                                              && index === headerCellRepeater.count - 1
                                        width: 2; height: parent.height; anchors.right: parent.right
                                        color: "#4488dd"; z: 20
                                    }

                                    Text {
                                        anchors { verticalCenter: parent.verticalCenter; left: parent.left; leftMargin: 6; right: sortInd.left; rightMargin: 4 }
                                        text: modelData.title
                                        color: headerCell.isActive ? "#88bbff" : "#b0b0b0"
                                        font.pixelSize: 12; font.bold: true
                                        elide: Text.ElideRight
                                    }
                                    Text {
                                        id: sortInd
                                        anchors { verticalCenter: parent.verticalCenter; right: resizeHandle.left; rightMargin: 4 }
                                        text: root.articleSortAscending ? "▲" : "▼"
                                        color: "#88bbff"; font.pixelSize: 9
                                        visible: headerCell.isActive
                                    }

                                    MouseArea {
                                        id: headerCellMouse
                                        anchors { fill: parent; rightMargin: 10 }
                                        hoverEnabled: true; preventStealing: true
                                        property real _pressX: 0
                                        property bool _didDrag: false
                                        onPressed: { _pressX = mouseX; _didDrag = false }
                                        onPositionChanged: {
                                            if (!(pressedButtons & Qt.LeftButton)) return
                                            if (!root._colDragging && Math.abs(mouseX - _pressX) > 8) {
                                                root._colDragFromKey = modelData.key
                                                root._colDragging = true; _didDrag = true
                                            }
                                            if (root._colDragging && root._colDragFromKey === modelData.key) {
                                                var cursorX = headerCellMouse.mapToItem(headerRow, mouseX, 0).x
                                                var insertBefore = "__end__"
                                                var xAcc = 0
                                                for (var i = 0; i < root.visibleCols.length; ++i) {
                                                    var w = root.colWidth(root.visibleCols[i].key)
                                                    if (cursorX < xAcc + w / 2) { insertBefore = root.visibleCols[i].key; break }
                                                    xAcc += w
                                                }
                                                root._colDragInsertBeforeKey = insertBefore
                                            }
                                        }
                                        onReleased: {
                                            var didDrag = _didDrag
                                            Qt.callLater(function() {
                                                if (didDrag) root.applyColReorder()
                                                root._colDragging = false
                                                root._colDragFromKey = ""
                                                root._colDragInsertBeforeKey = ""
                                            })
                                            _didDrag = false
                                        }
                                        onClicked: { if (!_didDrag) root.applyArticleSort(modelData.key) }
                                    }

                                    Rectangle { anchors.right: parent.right; width: 1; height: parent.height; color: "#3a3a3a" }

                                    Item {
                                        id: resizeHandle
                                        width: 10; height: parent.height
                                        anchors.right: parent.right; z: 10
                                        property real _startWidthPx: 0
                                        HoverHandler { cursorShape: Qt.SizeHorCursor }
                                        DragHandler {
                                            target: null; xAxis.enabled: true; yAxis.enabled: false
                                            cursorShape: Qt.SizeHorCursor
                                            onActiveChanged: {
                                                if (active) {
                                                    resizeHandle._startWidthPx = modelData.widthPx || 100
                                                    root._resizingColumnKey = modelData.key
                                                    root._resizingColumnWidth = resizeHandle._startWidthPx
                                                    return
                                                }
                                                if (root._resizingColumnKey === modelData.key) {
                                                    var defs = root.columnDefs.slice()
                                                    for (var j = 0; j < defs.length; ++j) {
                                                        if (defs[j].key === modelData.key) {
                                                            defs[j] = Object.assign({}, defs[j], { widthPx: root._resizingColumnWidth })
                                                            break
                                                        }
                                                    }
                                                    root._resizingColumnKey = ""; root._resizingColumnWidth = 0
                                                    root.columnDefs = defs
                                                }
                                            }
                                            onTranslationChanged: {
                                                if (!active) return
                                                root._resizingColumnWidth = Math.max(60, Math.round(resizeHandle._startWidthPx + translation.x))
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: "#3a3a3a" }
                    }

                    // Article list + preview split
                    SplitView {
                        id: articleSplitView
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        orientation: Qt.Vertical
                        clip: true

                        handle: Rectangle {
                            implicitHeight: 4
                            color: SplitHandle.hovered || SplitHandle.pressed ? "#3a5a8a" : "#252525"
                            Rectangle {
                                anchors.centerIn: parent
                                width: 28; height: 1
                                color: SplitHandle.hovered || SplitHandle.pressed ? "#88bbff" : "#383838"
                            }
                        }

                        ListView {
                            id: articleList
                            SplitView.fillWidth: true
                            SplitView.fillHeight: true
                            SplitView.minimumHeight: 60
                            model: root.sortedArticles
                            clip: true
                            boundsBehavior: Flickable.StopAtBounds
                            ScrollBar.vertical: ScrollBar {}

                            delegate: Rectangle {
                                id: articleDelegate
                                required property var modelData
                                required property int index
                                width: articleList.width
                                height: 26
                                color: root.selectedArticleRow === index
                                     ? "#1e3a6e"
                                     : (articleMouse.containsMouse ? "#242434" : (index % 2 === 0 ? "#1c1c1c" : "#1e1e1e"))

                                // Unread indicator bar on the left edge
                                Rectangle {
                                    visible: !!articleDelegate.modelData.unread
                                    width: 2; height: parent.height
                                    color: root.selectedArticleRow === index ? "#88bbff" : "#4488dd"
                                }

                                Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: "#262626" }

                                // Columns — hardcoded to avoid Repeater/QQmlContext overhead
                                Item {
                                    id: col0
                                    x: 0
                                    width: root.visibleCols.length > 0 ? root.colWidth(root.visibleCols[0].key) : 0
                                    height: parent.height
                                    visible: root.visibleCols.length > 0
                                    Text {
                                        anchors { fill: parent; leftMargin: 8; rightMargin: 6 }
                                        verticalAlignment: Text.AlignVCenter
                                        text: {
                                            if (!root.visibleCols.length) return ""
                                            var k = root.visibleCols[0].key
                                            if (k === "feed")      return articleDelegate.modelData.feedTitle || ""
                                            if (k === "published") return articleDelegate.modelData.publishedDisplay || ""
                                            return articleDelegate.modelData.title || "Untitled"
                                        }
                                        color: {
                                            if (root.visibleCols.length > 0 && root.visibleCols[0].key === "title") {
                                                if (root.selectedArticleRow === index) return "#ffffff"
                                                return !!articleDelegate.modelData.unread ? "#e8e8e8" : "#b0b0b0"
                                            }
                                            return root.selectedArticleRow === index ? "#ffffff" : "#c0c0c0"
                                        }
                                        font.pixelSize: 12
                                        font.bold: root.visibleCols.length > 0 && root.visibleCols[0].key === "title"
                                               && !!articleDelegate.modelData.unread
                                        elide: Text.ElideRight
                                    }
                                }
                                Item {
                                    id: col1
                                    x: col0.width
                                    width: root.visibleCols.length > 1 ? root.colWidth(root.visibleCols[1].key) : 0
                                    height: parent.height
                                    visible: root.visibleCols.length > 1
                                    Text {
                                        anchors { fill: parent; leftMargin: 8; rightMargin: 6 }
                                        verticalAlignment: Text.AlignVCenter
                                        text: {
                                            if (root.visibleCols.length < 2) return ""
                                            var k = root.visibleCols[1].key
                                            if (k === "feed")      return articleDelegate.modelData.feedTitle || ""
                                            if (k === "published") return articleDelegate.modelData.publishedDisplay || ""
                                            return articleDelegate.modelData.title || "Untitled"
                                        }
                                        color: {
                                            if (root.visibleCols.length > 1 && root.visibleCols[1].key === "title") {
                                                if (root.selectedArticleRow === index) return "#ffffff"
                                                return !!articleDelegate.modelData.unread ? "#e8e8e8" : "#b0b0b0"
                                            }
                                            return root.selectedArticleRow === index ? "#ffffff" : "#888888"
                                        }
                                        font.pixelSize: 12
                                        font.bold: root.visibleCols.length > 1 && root.visibleCols[1].key === "title"
                                               && !!articleDelegate.modelData.unread
                                        elide: Text.ElideRight
                                    }
                                }
                                Item {
                                    id: col2
                                    x: col0.width + col1.width
                                    width: root.visibleCols.length > 2 ? root.colWidth(root.visibleCols[2].key) : 0
                                    height: parent.height
                                    visible: root.visibleCols.length > 2
                                    Text {
                                        anchors { fill: parent; leftMargin: 8; rightMargin: 6 }
                                        verticalAlignment: Text.AlignVCenter
                                        text: {
                                            if (root.visibleCols.length < 3) return ""
                                            var k = root.visibleCols[2].key
                                            if (k === "feed")      return articleDelegate.modelData.feedTitle || ""
                                            if (k === "published") return articleDelegate.modelData.publishedDisplay || ""
                                            return articleDelegate.modelData.title || "Untitled"
                                        }
                                        color: {
                                            if (root.visibleCols.length > 2 && root.visibleCols[2].key === "title") {
                                                if (root.selectedArticleRow === index) return "#ffffff"
                                                return !!articleDelegate.modelData.unread ? "#e8e8e8" : "#b0b0b0"
                                            }
                                            return root.selectedArticleRow === index ? "#ffffff" : "#888888"
                                        }
                                        font.pixelSize: 12
                                        font.bold: root.visibleCols.length > 2 && root.visibleCols[2].key === "title"
                                               && !!articleDelegate.modelData.unread
                                        elide: Text.ElideRight
                                    }
                                }

                                MouseArea {
                                    id: articleMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                                    onClicked: function(mouse) {
                                        root.selectedArticleRow = articleDelegate.index
                                        if (mouse.button === Qt.RightButton)
                                            articleContextMenu.popup()
                                    }
                                    onDoubleClicked: {
                                        root.selectedArticleRow = articleDelegate.index
                                        if (root.selectedArticleHasDownload) root.triggerSelectedDownload()
                                        else root.openSelectedArticle()
                                    }
                                }
                            }
                        }

                        // ── Preview pane ─────────────────────────────────────
                        Rectangle {
                            SplitView.preferredHeight: root.previewPaneHeight
                            SplitView.minimumHeight: 90
                            SplitView.maximumHeight: root.height * 0.6
                            onHeightChanged: root.previewPaneHeight = height
                            color: "#191919"

                            Rectangle { anchors.top: parent.top; width: parent.width; height: 1; color: "#2e2e2e" }

                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: 10
                                spacing: 6

                                // Title row + action buttons
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 6

                                    Text {
                                        Layout.fillWidth: true
                                        text: selectedArticle.title || "Select an article"
                                        color: selectedArticle.title ? "#f0f0f0" : "#555"
                                        font.pixelSize: 13
                                        font.bold: true
                                        elide: Text.ElideRight
                                    }

                                    DlgButton {
                                        text: "Open in Browser"
                                        enabled: !!selectedArticle.link
                                        onClicked: root.openSelectedArticle()
                                    }
                                    DlgButton {
                                        text: root.selectedArticleHasDownload ? "Download" : "Open"
                                        primary: root.selectedArticleHasDownload
                                        enabled: selectedArticleRow >= 0
                                        onClicked: root.triggerSelectedDownload()
                                    }
                                    DlgButton {
                                        text: selectedArticle.unread ? "Mark Read" : "Mark Unread"
                                        enabled: selectedArticleRow >= 0
                                        onClicked: root.markSelectedArticleRead(!!selectedArticle.unread)
                                    }
                                    DlgButton {
                                        text: "Copy Link"
                                        enabled: selectedArticleRow >= 0
                                        onClicked: root.copySelectedLink()
                                    }
                                }

                                // Feed • date meta line
                                Text {
                                    Layout.fillWidth: true
                                    text: selectedArticle.feedTitle
                                        ? selectedArticle.feedTitle + "  ·  " + (selectedArticle.publishedDisplay || "")
                                        : "Choose an article to view its summary."
                                    color: "#5f7080"
                                    font.pixelSize: 11
                                    elide: Text.ElideRight
                                }

                                Rectangle { Layout.fillWidth: true; height: 1; color: "#272727" }

                                // Body: thumbnail + text
                                RowLayout {
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    spacing: 10

                                    Rectangle {
                                        visible: !!root.selectedArticleImageUrl
                                        Layout.preferredWidth: 150
                                        Layout.fillHeight: true
                                        color: "#111"
                                        border.color: "#2a2a2a"
                                        radius: 2

                                        Image {
                                            anchors.fill: parent; anchors.margins: 4
                                            source: root.selectedArticleImageUrl || ""
                                            fillMode: Image.PreserveAspectFit
                                            asynchronous: true; cache: true
                                        }
                                    }

                                    ScrollView {
                                        Layout.fillWidth: true
                                        Layout.fillHeight: true
                                        clip: true
                                        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

                                        Column {
                                            width: Math.max(200, parent.width - 14)
                                            spacing: 4

                                            Text {
                                                width: parent.width
                                                text: selectedArticle.summary && selectedArticle.summary.length > 0
                                                    ? selectedArticle.summary
                                                    : ((!selectedArticle.descriptionHtml || selectedArticle.descriptionHtml.length === 0)
                                                       ? (selectedArticle.title ? "No summary available." : "") : "")
                                                color: "#c0c0c0"
                                                font.pixelSize: 11
                                                wrapMode: Text.WordWrap
                                                visible: text.length > 0
                                            }

                                            Text {
                                                width: parent.width
                                                visible: !!selectedArticle.descriptionHtml && selectedArticle.descriptionHtml.length > 0
                                                text: selectedArticle.descriptionHtml || ""
                                                textFormat: Text.RichText
                                                color: "#c0c0c0"
                                                linkColor: "#7fb4ff"
                                                font.pixelSize: 11
                                                wrapMode: Text.WordWrap
                                                onLinkActivated: function(link) { Qt.openUrlExternally(link) }
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

        // ── Status bar ───────────────────────────────────────────────────────
        Rectangle {
            Layout.fillWidth: true
            height: 22
            color: "#222222"
            Rectangle { anchors.top: parent.top; width: parent.width; height: 1; color: "#2e2e2e" }

            RowLayout {
                anchors { fill: parent; leftMargin: 8; rightMargin: 8 }
                spacing: 10

                Text {
                    text: App.rssManager.statusText || ""
                    color: "#6a7a8a"
                    font.pixelSize: 11
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }

                Text {
                    visible: App.rssManager.refreshInProgress
                    text: "Refreshing…"
                    color: "#5588cc"
                    font.pixelSize: 11
                }

                Text {
                    text: {
                        var total   = App.rssManager.articleCount
                        var unread  = 0
                        for (var i = 0; i < App.rssManager.feedCount; ++i) {
                            var f = App.rssManager.feedModel.feedData(i)
                            unread += f.unreadCount || 0
                        }
                        if (total === 0) return ""
                        return unread > 0 ? unread + " unread  ·  " + total + " items" : total + " items"
                    }
                    color: "#4a5a6a"
                    font.pixelSize: 11
                }
            }
        }
    }

    RssDownloadRulesDialog { id: rssRulesDialog }
}
