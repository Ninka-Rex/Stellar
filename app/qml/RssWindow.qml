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
import QtQuick.Controls
import QtQuick.Layouts
import QtCore

Window {
    id: root
    width: 980
    height: 620
    minimumWidth: 860
    minimumHeight: 520
    title: "RSS Reader"
    color: "#1b1b1b"
    flags: Qt.Dialog | Qt.WindowTitleHint | Qt.WindowCloseButtonHint | Qt.WindowSystemMenuHint

    property int selectedFeedRow: -1
    property int selectedArticleRow: -1
    property real leftPaneWidth: 255
    property real previewPaneHeight: 220
    property string editingFeedId: ""
    property string articleSortKey: "published"
    property bool articleSortAscending: false
    property var columnDefs: [
        { title: "Title", key: "title", widthPx: 420, visible: true },
        { title: "Feed", key: "feed", widthPx: 150, visible: true },
        { title: "Date", key: "published", widthPx: 120, visible: true }
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
            var av = ""
            var bv = ""
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
    readonly property var selectedArticle: (selectedArticleRow >= 0 && selectedArticleRow < sortedArticles.length) ? sortedArticles[selectedArticleRow] : ({})
    readonly property bool selectedArticleHasDownload: !!selectedArticle.isTorrent
        || !!selectedArticle.downloadUrl
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
            if (columnDefs[i].visible)
                cols.push(columnDefs[i])
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
        if (currentFeedId.length === 0) {
            selectedFeedRow = -1
            return
        }
        for (var i = 0; i < App.rssManager.feedCount; ++i) {
            var feed = App.rssManager.feedModel.feedData(i)
            if (feed.feedId === currentFeedId) {
                selectedFeedRow = i
                return
            }
        }
        selectedFeedRow = -1
    }

    function ensureArticleSelection() {
        if (sortedArticles.length <= 0)
            selectedArticleRow = -1
        else if (selectedArticleRow < 0 || selectedArticleRow >= sortedArticles.length)
            selectedArticleRow = 0
    }

    function colWidth(key) {
        if (_resizingColumnKey === key)
            return _resizingColumnWidth
        for (var i = 0; i < columnDefs.length; ++i) {
            if (columnDefs[i].key === key)
                return columnDefs[i].widthPx || 100
        }
        return 100
    }

    function applyArticleSort(key) {
        if (articleSortKey === key)
            articleSortAscending = !articleSortAscending
        else {
            articleSortKey = key
            articleSortAscending = key === "feed"
        }
        ensureArticleSelection()
    }

    function addSubscription() {
        var url = addFeedField.text.trim()
        if (url.length === 0)
            return
        if (App.rssManager.addSubscription(url))
            addFeedField.clear()
        syncFeedSelection()
        ensureArticleSelection()
    }

    function selectFeed(row) {
        selectedFeedRow = row
        var feed = App.rssManager.feedModel.feedData(row)
        App.rssManager.currentFeedId = feed.feedId || ""
        ensureArticleSelection()
    }

    function refreshCurrentFeed() {
        if (selectedFeed.feedId)
            App.rssManager.refreshFeed(selectedFeed.feedId)
        else
            App.rssManager.refreshAll()
    }

    function removeCurrentFeed() {
        if (!selectedFeed.feedId)
            return
        App.rssManager.removeSubscription(selectedFeed.feedId)
        syncFeedSelection()
        ensureArticleSelection()
    }

    function editCurrentFeed() {
        if (!selectedFeed.feedId)
            return
        editingFeedId = selectedFeed.feedId
        editFeedNameField.text = selectedFeed.customTitle || ""
        editFeedUrlField.text = selectedFeed.url || ""
        editFeedDialog.show()
        editFeedDialog.raise()
        editFeedDialog.requestActivate()
    }

    function saveEditedFeed() {
        if (!editingFeedId)
            return
        if (App.rssManager.updateSubscription(editingFeedId, editFeedUrlField.text, editFeedNameField.text)) {
            editFeedDialog.close()
            syncFeedSelection()
        }
    }

    function markSelectedArticleRead(read) {
        if (!selectedArticle.feedId || !selectedArticle.guid)
            return
        App.rssManager.markArticleReadByGuid(selectedArticle.feedId, selectedArticle.guid, read)
    }

    function openSelectedArticle() {
        if (!selectedArticle.link)
            return
        markSelectedArticleRead(true)
        Qt.openUrlExternally(selectedArticle.link)
    }

    function triggerSelectedDownload() {
        if (!selectedArticleHasDownload)
            return openSelectedArticle()
        var url = selectedArticle.downloadUrl && selectedArticle.downloadUrl.length > 0 ? selectedArticle.downloadUrl : selectedArticle.link
        markSelectedArticleRead(true)
        if (selectedArticle.isTorrent) {
            App.beginTorrentMetadataDownload(url, App.settings.defaultSavePath, "", selectedArticle.title || "", true)
        } else {
            App.addUrl(url, App.settings.defaultSavePath, "", selectedArticle.title || "", true)
        }
    }

    function copySelectedLink() {
        var url = selectedArticle.downloadUrl || selectedArticle.link || ""
        if (url.length > 0)
            App.copyToClipboard(url)
    }

    function applyColReorder() {
        if (!_colDragFromKey)
            return
        var defs = columnDefs.slice()
        var fromIdx = -1
        for (var i = 0; i < defs.length; ++i) {
            if (defs[i].key === _colDragFromKey) {
                fromIdx = i
                break
            }
        }
        if (fromIdx < 0)
            return
        var toIdx = defs.length
        if (_colDragInsertBeforeKey !== "__end__") {
            for (var j = 0; j < defs.length; ++j) {
                if (defs[j].key === _colDragInsertBeforeKey) {
                    toIdx = j
                    break
                }
            }
        }
        if (toIdx === fromIdx)
            return
        var moved = defs.splice(fromIdx, 1)[0]
        if (toIdx > fromIdx)
            toIdx--
        defs.splice(toIdx, 0, moved)
        columnDefs = defs
    }

    function applyFeedReorder() {
        if (!_feedDragging || _feedDragFrom < 0 || _feedDropTarget < 0)
            return
        if (_feedDragFrom === _feedDropTarget)
            return
        var to = (_feedDragFrom < _feedDropTarget) ? _feedDropTarget - 1 : _feedDropTarget
        if (to === _feedDragFrom)
            return
        App.rssManager.moveSubscription(_feedDragFrom, to)
        syncFeedSelection()
    }

    Component.onCompleted: {
        App.setWindowIcon(root, "qrc:/qt/qml/com/stellar/app/app/qml/icons/rss.png")
        syncFeedSelection()
        ensureArticleSelection()
    }

    Connections {
        target: App.rssManager
        function onCurrentFeedIdChanged() {
            root.syncFeedSelection()
            root.ensureArticleSelection()
        }
        function onArticleModelChanged() {
            root.ensureArticleSelection()
        }
    }

    Settings {
        category: "RssWindow"
        property alias leftPaneWidth: root.leftPaneWidth
        property alias previewPaneHeight: root.previewPaneHeight
    }

    Menu {
        id: feedContextMenu
        property int row: -1
        Action { text: "Open Feed"; onTriggered: if (feedContextMenu.row >= 0) root.selectFeed(feedContextMenu.row) }
        Action {
            text: "Refresh"
            onTriggered: {
                var feed = App.rssManager.feedModel.feedData(feedContextMenu.row)
                if (feed.feedId)
                    App.rssManager.refreshFeed(feed.feedId)
            }
        }
        MenuSeparator {}
        Action {
            text: "Rename / Edit..."
            onTriggered: {
                root.selectedFeedRow = feedContextMenu.row
                root.editCurrentFeed()
            }
        }
        Action {
            text: "Remove Subscription"
            onTriggered: {
                var feed = App.rssManager.feedModel.feedData(feedContextMenu.row)
                if (feed.feedId)
                    App.rssManager.removeSubscription(feed.feedId)
                root.syncFeedSelection()
                root.ensureArticleSelection()
            }
        }
    }

    RssDownloadRulesDialog {
        id: rssRulesDialog
    }

    Window {
        id: editFeedDialog
        width: 430
        height: 180
        minimumWidth: 410
        minimumHeight: 170
        title: "Edit Subscription"
        color: "#1b1b1b"
        modality: Qt.ApplicationModal
        flags: Qt.Dialog | Qt.WindowTitleHint | Qt.WindowCloseButtonHint

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 12
            spacing: 8

            TextField {
                id: editFeedNameField
                Layout.fillWidth: true
                placeholderText: "Custom name (optional)"
                color: "#d0d0d0"
                background: Rectangle { color: "#101010"; border.color: "#383838" }
            }

            TextField {
                id: editFeedUrlField
                Layout.fillWidth: true
                placeholderText: "Feed URL"
                color: "#d0d0d0"
                onAccepted: root.saveEditedFeed()
                background: Rectangle { color: "#101010"; border.color: "#383838" }
            }

            Item { Layout.fillHeight: true }

            RowLayout {
                Layout.fillWidth: true
                Item { Layout.fillWidth: true }
                DlgButton { text: "Cancel"; onClicked: editFeedDialog.close() }
                DlgButton { text: "Save"; primary: true; enabled: editFeedUrlField.text.trim().length > 0; onClicked: root.saveEditedFeed() }
            }
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 8
        spacing: 6

        RowLayout {
            Layout.fillWidth: true
            spacing: 6

            TextField {
                id: addFeedField
                Layout.fillWidth: true
                placeholderText: "Add RSS / Atom feed URL"
                color: "#d0d0d0"
                onAccepted: root.addSubscription()
                background: Rectangle { color: "#101010"; border.color: "#383838" }
            }

            DlgButton { text: "Add"; primary: true; enabled: addFeedField.text.trim().length > 0; onClicked: root.addSubscription() }
            DlgButton { text: App.rssManager.refreshInProgress ? "Refreshing..." : "Refresh"; enabled: !App.rssManager.refreshInProgress; onClicked: root.refreshCurrentFeed() }
            DlgButton { text: "Remove"; enabled: !!selectedFeed.feedId; onClicked: root.removeCurrentFeed() }
            DlgButton {
                text: "Download Rules"
                onClicked: {
                    rssRulesDialog.show()
                    rssRulesDialog.raise()
                    rssRulesDialog.requestActivate()
                }
            }
        }

        SplitView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            orientation: Qt.Horizontal

            Rectangle {
                SplitView.preferredWidth: root.leftPaneWidth
                SplitView.minimumWidth: 210
                color: "#1f1f1f"

                Rectangle {
                    id: catHeader
                    anchors { top: parent.top; left: parent.left; right: parent.right }
                    height: 26
                    color: "#2d2d2d"
                    Rectangle { width: 3; height: parent.height; color: "#5588cc" }
                    Text {
                        anchors { verticalCenter: parent.verticalCenter; left: parent.left; leftMargin: 8 }
                        text: "Subscriptions"
                        color: "#d0d0d0"
                        font.pixelSize: 12
                        font.bold: true
                    }
                    Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: "#3a3a3a" }
                }

                ScrollView {
                    anchors { top: catHeader.bottom; left: parent.left; right: parent.right; bottom: parent.bottom }
                    clip: true

                    Column {
                        width: parent.width
                        spacing: 0

                        Repeater {
                            model: App.rssManager.feedModel

                            delegate: Item {
                                id: feedDelegate
                                required property string title
                                required property string url
                                required property string errorText
                                required property int unreadCount
                                required property int totalCount
                                required property string feedId
                                required property int index
                                readonly property int rowIndex: index
                                width: parent.width
                                height: 28

                                Rectangle {
                                    visible: root._feedDragging
                                          && root._feedDropTarget === feedDelegate.rowIndex
                                          && root._feedDragFrom !== root._feedDropTarget
                                          && root._feedDragFrom !== root._feedDropTarget - 1
                                    anchors { top: parent.top; left: parent.left; right: parent.right }
                                    height: 2
                                    color: "#4488dd"
                                    z: 10
                                }

                                Rectangle {
                                    anchors.fill: parent
                                    color: root.selectedFeedRow === rowIndex ? "#1e3a6e"
                                         : (feedMouse.containsMouse && !root._feedDragging ? "#2a2a3a" : "transparent")
                                    border.color: root.selectedFeedRow === rowIndex ? "#4488dd" : "transparent"
                                    border.width: 1
                                    opacity: (root._feedDragging && root._feedDragFrom === rowIndex) ? 0.4 : 1.0

                                    Row {
                                        anchors { fill: parent; leftMargin: 10; rightMargin: 8 }
                                        spacing: 6

                                        Text {
                                            width: 150
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: title || url
                                            color: root.selectedFeedRow === rowIndex ? "#88bbff" : "#cccccc"
                                            font.pixelSize: 12
                                            font.bold: root.selectedFeedRow === rowIndex || unreadCount > 0
                                            elide: Text.ElideRight
                                        }
                                        Text {
                                            width: 30
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: unreadCount > 0 ? unreadCount : ""
                                            color: "#88bbff"
                                            font.pixelSize: 11
                                            horizontalAlignment: Text.AlignRight
                                        }
                                        Text {
                                            width: 36
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: totalCount
                                            color: "#999999"
                                            font.pixelSize: 11
                                            horizontalAlignment: Text.AlignRight
                                        }
                                    }
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
                                        if (!(pressedButtons & Qt.LeftButton))
                                            return
                                        if (!root._feedDragging && Math.abs(mouseY - _pressY) > 6) {
                                            root._feedDragFrom = rowIndex
                                            root._feedDragging = true
                                            _didDrag = true
                                        }
                                        if (root._feedDragging) {
                                            var cursorY = feedMouse.mapToItem(parent.parent, mouseX, mouseY).y
                                            var target = App.rssManager.feedCount
                                            for (var r = 0; r < App.rssManager.feedCount; ++r) {
                                                var del = parent.children[r]
                                                if (!del || del.height === 0)
                                                    continue
                                                if (cursorY < del.y + del.height / 2) {
                                                    target = r
                                                    break
                                                }
                                            }
                                            root._feedDropTarget = target
                                        }
                                    }

                                    onReleased: {
                                        var dragFrom = root._feedDragFrom
                                        var dragging = root._feedDragging
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
                                        if (_didDrag) {
                                            _didDrag = false
                                            return
                                        }
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
                    }
                }
            }

            Rectangle {
                SplitView.fillWidth: true
                color: "#1c1c1c"

                Rectangle {
                    id: header
                    anchors { top: parent.top; left: parent.left; right: parent.right }
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
                                    width: 2
                                    height: parent.height
                                    anchors.left: parent.left
                                    color: "#4488dd"
                                    z: 20
                                }
                                Rectangle {
                                    visible: root._colDragging && root._colDragInsertBeforeKey === "__end__" && index === headerCellRepeater.count - 1
                                    width: 2
                                    height: parent.height
                                    anchors.right: parent.right
                                    color: "#4488dd"
                                    z: 20
                                }

                                Text {
                                    anchors { verticalCenter: parent.verticalCenter; left: parent.left; leftMargin: 6; right: sortIndicator.left; rightMargin: 4 }
                                    text: modelData.title
                                    color: headerCell.isActive ? "#88bbff" : "#b0b0b0"
                                    font.pixelSize: 12
                                    font.bold: true
                                    elide: Text.ElideRight
                                }

                                Text {
                                    id: sortIndicator
                                    anchors { verticalCenter: parent.verticalCenter; right: resizeHandle.left; rightMargin: 4 }
                                    text: root.articleSortAscending ? "▲" : "▼"
                                    color: "#88bbff"
                                    font.pixelSize: 9
                                    visible: headerCell.isActive
                                }

                                MouseArea {
                                    id: headerCellMouse
                                    anchors { fill: parent; rightMargin: 10 }
                                    hoverEnabled: true
                                    preventStealing: true
                                    property real _pressX: 0
                                    property bool _didDrag: false

                                    onPressed: { _pressX = mouseX; _didDrag = false }

                                    onPositionChanged: {
                                        if (!(pressedButtons & Qt.LeftButton))
                                            return
                                        if (!root._colDragging && Math.abs(mouseX - _pressX) > 8) {
                                            root._colDragFromKey = modelData.key
                                            root._colDragging = true
                                            _didDrag = true
                                        }
                                        if (root._colDragging && root._colDragFromKey === modelData.key) {
                                            var cursorX = headerCellMouse.mapToItem(headerRow, mouseX, 0).x
                                            var insertBefore = "__end__"
                                            var xAcc = 0
                                            for (var i = 0; i < root.visibleCols.length; ++i) {
                                                var w = root.colWidth(root.visibleCols[i].key)
                                                if (cursorX < xAcc + w / 2) {
                                                    insertBefore = root.visibleCols[i].key
                                                    break
                                                }
                                                xAcc += w
                                            }
                                            root._colDragInsertBeforeKey = insertBefore
                                        }
                                    }

                                    onReleased: {
                                        var didDrag = _didDrag
                                        Qt.callLater(function() {
                                            if (didDrag)
                                                root.applyColReorder()
                                            root._colDragging = false
                                            root._colDragFromKey = ""
                                            root._colDragInsertBeforeKey = ""
                                        })
                                        _didDrag = false
                                    }

                                    onClicked: {
                                        if (!_didDrag)
                                            root.applyArticleSort(modelData.key)
                                    }
                                }

                                Rectangle { anchors.right: parent.right; width: 1; height: parent.height; color: "#3a3a3a" }

                                Item {
                                    id: resizeHandle
                                    width: 10
                                    height: parent.height
                                    anchors.right: parent.right
                                    z: 10
                                    property real _startWidthPx: 0

                                    HoverHandler { id: resizeHover; cursorShape: Qt.SizeHorCursor }
                                    DragHandler {
                                        id: resizeDrag
                                        target: null
                                        xAxis.enabled: true
                                        yAxis.enabled: false
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
                                                root._resizingColumnKey = ""
                                                root._resizingColumnWidth = 0
                                                root.columnDefs = defs
                                            }
                                        }

                                        onTranslationChanged: {
                                            if (!active)
                                                return
                                            root._resizingColumnWidth = Math.max(60, Math.round(resizeHandle._startWidthPx + translation.x))
                                        }
                                    }
                                }
                            }
                        }
                    }

                    Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: "#3a3a3a" }
                }

                SplitView {
                    id: articleSplitView
                    anchors { top: header.bottom; left: parent.left; right: parent.right; bottom: parent.bottom }
                    orientation: Qt.Vertical
                    clip: true

                    handle: Rectangle {
                        implicitHeight: 5
                        color: SplitHandle.hovered || SplitHandle.pressed ? "#3a5a8a" : "#2a2a2a"
                        Rectangle {
                            anchors.centerIn: parent
                            width: 32
                            height: 1
                            color: SplitHandle.hovered || SplitHandle.pressed ? "#88bbff" : "#3a3a3a"
                        }
                    }

                    ListView {
                        id: articleList
                        SplitView.fillWidth: true
                        SplitView.fillHeight: true
                        SplitView.minimumHeight: 80
                        model: root.sortedArticles
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds

                        delegate: Rectangle {
                            id: articleDelegate
                            required property var modelData
                            required property int index
                            width: articleList.width
                            height: 24
                            color: root.selectedArticleRow === index ? "#1e3a6e" : (articleMouse.containsMouse ? "#2a2a3a" : "transparent")

                            Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: "#262626" }

                            MouseArea {
                                id: articleMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                onClicked: root.selectedArticleRow = articleDelegate.index
                                onDoubleClicked: {
                                    root.selectedArticleRow = articleDelegate.index
                                    if (root.selectedArticleHasDownload)
                                        root.triggerSelectedDownload()
                                    else
                                        root.openSelectedArticle()
                                }
                            }

                            // Hardcoded columns instead of nested Repeater to avoid QQmlContext overhead
                            Item {
                                id: col0
                                x: 0
                                width: root.colWidth(root.visibleCols.length > 0 ? root.visibleCols[0].key : "title")
                                height: parent.height
                                visible: root.visibleCols.length > 0
                                Text {
                                    anchors { fill: parent; leftMargin: 6; rightMargin: 6 }
                                    text: {
                                        if (!root.visibleCols.length) return ""
                                        var k = root.visibleCols[0].key
                                        if (k === "feed") return articleDelegate.modelData.feedTitle || ""
                                        if (k === "published") return articleDelegate.modelData.publishedDisplay || ""
                                        return articleDelegate.modelData.title || "Untitled item"
                                    }
                                    color: root.visibleCols.length > 0 && root.visibleCols[0].key === "title" && !!articleDelegate.modelData.unread ? "#ffffff" : "#d0d0d0"
                                    font.pixelSize: 10
                                    font.bold: root.visibleCols.length > 0 && root.visibleCols[0].key === "title" && !!articleDelegate.modelData.unread
                                    elide: Text.ElideRight
                                    verticalAlignment: Text.AlignVCenter
                                }
                            }
                            Item {
                                id: col1
                                x: col0.width
                                width: root.visibleCols.length > 1 ? root.colWidth(root.visibleCols[1].key) : 0
                                height: parent.height
                                visible: root.visibleCols.length > 1
                                Text {
                                    anchors { fill: parent; leftMargin: 6; rightMargin: 6 }
                                    text: {
                                        if (root.visibleCols.length < 2) return ""
                                        var k = root.visibleCols[1].key
                                        if (k === "feed") return articleDelegate.modelData.feedTitle || ""
                                        if (k === "published") return articleDelegate.modelData.publishedDisplay || ""
                                        return articleDelegate.modelData.title || "Untitled item"
                                    }
                                    color: root.visibleCols.length > 1 && root.visibleCols[1].key === "title" && !!articleDelegate.modelData.unread ? "#ffffff" : "#d0d0d0"
                                    font.pixelSize: 10
                                    font.bold: root.visibleCols.length > 1 && root.visibleCols[1].key === "title" && !!articleDelegate.modelData.unread
                                    elide: Text.ElideRight
                                    verticalAlignment: Text.AlignVCenter
                                }
                            }
                            Item {
                                id: col2
                                x: col0.width + col1.width
                                width: root.visibleCols.length > 2 ? root.colWidth(root.visibleCols[2].key) : 0
                                height: parent.height
                                visible: root.visibleCols.length > 2
                                Text {
                                    anchors { fill: parent; leftMargin: 6; rightMargin: 6 }
                                    text: {
                                        if (root.visibleCols.length < 3) return ""
                                        var k = root.visibleCols[2].key
                                        if (k === "feed") return articleDelegate.modelData.feedTitle || ""
                                        if (k === "published") return articleDelegate.modelData.publishedDisplay || ""
                                        return articleDelegate.modelData.title || "Untitled item"
                                    }
                                    color: root.visibleCols.length > 2 && root.visibleCols[2].key === "title" && !!articleDelegate.modelData.unread ? "#ffffff" : "#d0d0d0"
                                    font.pixelSize: 10
                                    font.bold: root.visibleCols.length > 2 && root.visibleCols[2].key === "title" && !!articleDelegate.modelData.unread
                                    elide: Text.ElideRight
                                    verticalAlignment: Text.AlignVCenter
                                }
                            }
                        }
                    }

                    // Preview / description pane
                    Rectangle {
                        id: previewPane
                        SplitView.preferredHeight: root.previewPaneHeight
                        SplitView.minimumHeight: 100
                        SplitView.maximumHeight: root.height * 0.65
                        onHeightChanged: root.previewPaneHeight = height
                        color: "#141414"
                        border.color: "#2b2b2b"

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 8
                            spacing: 4

                            // Title + action buttons row
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 6

                                Text {
                                    Layout.fillWidth: true
                                    text: selectedArticle.title || "Select an item"
                                    color: "#f0f0f0"
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

                            // Feed name + date subtitle
                            Text {
                                Layout.fillWidth: true
                                text: selectedArticle.feedTitle
                                    ? selectedArticle.feedTitle + "  •  " + (selectedArticle.publishedDisplay || "Unknown date")
                                    : "Choose an item to view its details."
                                color: "#8fa0b3"
                                font.pixelSize: 10
                                elide: Text.ElideRight
                            }

                            // Divider
                            Rectangle {
                                Layout.fillWidth: true
                                height: 1
                                color: "#2a2a2a"
                            }

                            // Article body area: optional thumbnail + scrollable text
                            RowLayout {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                spacing: 8

                                // Thumbnail (only when image is available)
                                Rectangle {
                                    visible: !!root.selectedArticleImageUrl
                                    width: visible ? 160 : 0
                                    Layout.preferredWidth: 160
                                    Layout.fillHeight: true
                                    color: "#101010"
                                    border.color: "#252525"
                                    radius: 2

                                    Image {
                                        anchors.fill: parent
                                        anchors.margins: 4
                                        source: root.selectedArticleImageUrl || ""
                                        fillMode: Image.PreserveAspectFit
                                        asynchronous: true
                                        cache: true
                                    }
                                }

                                ScrollView {
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    clip: true
                                    ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

                                    Column {
                                        width: Math.max(260, parent.width - 14)
                                        spacing: 6

                                        Text {
                                            width: parent.width
                                            text: selectedArticle.summary && selectedArticle.summary.length > 0
                                                ? selectedArticle.summary
                                                : ((!selectedArticle.descriptionHtml || selectedArticle.descriptionHtml.length === 0) ? "No summary available." : "")
                                            color: "#c8c8c8"
                                            font.pixelSize: 11
                                            wrapMode: Text.WordWrap
                                            visible: text.length > 0
                                        }

                                        Text {
                                            width: parent.width
                                            visible: selectedArticle.descriptionHtml && selectedArticle.descriptionHtml.length > 0
                                            text: selectedArticle.descriptionHtml || ""
                                            textFormat: Text.RichText
                                            color: "#c8c8c8"
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
}
