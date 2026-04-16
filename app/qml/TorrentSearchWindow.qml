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
    width: 860
    height: 620
    minimumWidth: 760
    minimumHeight: 500
    title: "Torrent Search Engine"
    color: "#1e1e1e"
    flags: Qt.Dialog | Qt.WindowTitleHint | Qt.WindowCloseButtonHint | Qt.WindowSystemMenuHint

    property string queryText: ""
    property string sortKey: "seeders"
    property bool sortAscending: false
    property string colOrderJson: '["name","size","seeders","leechers","engine","publishedOn"]'
    property real colName: 330
    property real colSize: 100
    property real colSeeders: 70
    property real colLeechers: 70
    property real colEngine: 110
    property real colPublished: 120
    property int ctxRow: -1
    property int selectedRow: -1
    property string dragColumnKey: ""
    property string colDragFromKey: ""
    property string colDragInsertBeforeKey: ""
    property bool colDragging: false
    readonly property var colDefs: [
        { title: "Name", key: "name" },
        { title: "Size", key: "size" },
        { title: "Seeders", key: "seeders" },
        { title: "Leechers", key: "leechers" },
        { title: "Engine", key: "engine" },
        { title: "Published On", key: "publishedOn" }
    ]
    property var colsOrdered: {
        try {
            var keys = JSON.parse(colOrderJson)
            if (Array.isArray(keys) && keys.length === colDefs.length) {
                var mapped = keys.map(function(k){ return colDefs.find(function(c){ return c.key === k }) }).filter(Boolean)
                if (mapped.length === colDefs.length)
                    return mapped
            }
        } catch (e) {}
        return colDefs.slice()
    }
    property var colXMap: {
        var map = {}
        var x = 0
        for (var i = 0; i < colsOrdered.length; ++i) {
            map[colsOrdered[i].key] = x
            x += colW(colsOrdered[i].key)
        }
        return map
    }

    function colW(key) {
        var width = colPublished
        if (key === "name") width = colName
        else if (key === "size") width = colSize
        else if (key === "seeders") width = colSeeders
        else if (key === "leechers") width = colLeechers
        else if (key === "engine") width = colEngine
        width = Number(width)
        if (!isFinite(width))
            width = key === "name" ? 330 : (key === "engine" ? 110 : (key === "publishedOn" ? 120 : 100))
        return Math.max(key === "name" ? 180 : 60, Math.round(width))
    }

    function applyColReorder(fromKey, beforeKey) {
        if (!fromKey || !beforeKey || fromKey === beforeKey)
            return
        var keys = colsOrdered.map(function(c){ return c.key })
        var from = keys.indexOf(fromKey)
        var to = keys.indexOf(beforeKey)
        if (from < 0 || to < 0)
            return
        keys.splice(from, 1)
        if (from < to) to--
        keys.splice(to, 0, fromKey)
        colOrderJson = JSON.stringify(keys)
    }

    function commitColReorder() {
        if (!colDragFromKey || !colDragInsertBeforeKey || colDragFromKey === colDragInsertBeforeKey)
            return
        applyColReorder(colDragFromKey, colDragInsertBeforeKey)
    }

    function setColumnWidth(key, value) {
        var width = Math.max(key === "name" ? 180 : 60, Math.round(Number(value)))
        if (!isFinite(width))
            return
        if (key === "name") colName = width
        else if (key === "size") colSize = width
        else if (key === "seeders") colSeeders = width
        else if (key === "leechers") colLeechers = width
        else if (key === "engine") colEngine = width
        else colPublished = width
    }

    function totalColumnWidth() {
        var total = 0
        for (var i = 0; i < colsOrdered.length; ++i)
            total += colW(colsOrdered[i].key)
        return total
    }

    function sanitizeColumnState() {
        var validKeys = colDefs.map(function(c) { return c.key }).sort().join("|")
        var orderedKeys = colsOrdered.map(function(c) { return c.key }).sort().join("|")
        if (orderedKeys !== validKeys)
            colOrderJson = JSON.stringify(colDefs.map(function(c) { return c.key }))
        setColumnWidth("name", colName)
        setColumnWidth("size", colSize)
        setColumnWidth("seeders", colSeeders)
        setColumnWidth("leechers", colLeechers)
        setColumnWidth("engine", colEngine)
        setColumnWidth("publishedOn", colPublished)
    }

    function sortBy(key) {
        if (sortKey === key)
            sortAscending = !sortAscending
        else {
            sortKey = key
            sortAscending = key === "name" || key === "engine" || key === "publishedOn"
        }
        App.torrentSearchManager.resultModel.sortBy(key, sortAscending)
    }

    function startSearch() {
        App.torrentSearchManager.refreshRuntimeState()
        // Push the active sort into the model before results start arriving so
        // appendEntry() positions each row correctly from the first result.
        // Without this, searches always insert in arrival order regardless of
        // what the column headers advertise.
        App.torrentSearchManager.resultModel.sortBy(sortKey, sortAscending)
        App.torrentSearchManager.search(queryText)
    }

    function currentRowData() {
        return App.torrentSearchManager.resultData(root.ctxRow)
    }

    function triggerDownload(row) {
        if (!row)
            return
        var resolved = App.torrentSearchManager.resolveResultLink(root.ctxRow, true)
        if (!resolved || resolved.length === 0)
            resolved = App.torrentSearchManager.resolveResultLink(root.ctxRow, false)
        if (!resolved || resolved.length === 0)
            return
        if (resolved.toLowerCase().indexOf("magnet:") === 0)
            App.beginTorrentMetadataDownload(resolved, App.settings.defaultSavePath, "", row.name || "", true)
        else
            App.addUrl(resolved, App.settings.defaultSavePath, "", row.name || "", true)
    }

    Component.onCompleted: {
        sanitizeColumnState()
        App.torrentSearchManager.refreshRuntimeState()
    }
    onVisibleChanged: if (visible) {
        sanitizeColumnState()
        App.torrentSearchManager.refreshRuntimeState()
    }

    Settings {
        category: "TorrentSearchWindow"
        property alias colOrderJson: root.colOrderJson
        property alias colName: root.colName
        property alias colSize: root.colSize
        property alias colSeeders: root.colSeeders
        property alias colLeechers: root.colLeechers
        property alias colEngine: root.colEngine
        property alias colPublished: root.colPublished
    }

    TorrentSearchPluginsDialog { id: pluginsDialog }

    Menu {
        id: resultMenu
        Action {
            text: "Open Description Page"
            onTriggered: {
                var row = root.currentRowData()
                if (row.descriptionUrl) Qt.openUrlExternally(row.descriptionUrl)
            }
        }
        Action {
            text: "Download Torrent"
            onTriggered: {
                root.triggerDownload(root.currentRowData())
            }
        }
        MenuSeparator {}
        Action { text: "Copy Name"; onTriggered: { var row = root.currentRowData(); App.copyToClipboard(row.name || "") } }
        Action { text: "Copy Magnet Link"; onTriggered: { var resolved = App.torrentSearchManager.resolveResultLink(root.ctxRow, true); if (resolved) App.copyToClipboard(resolved) } }
        Action { text: "Copy Description Page URL"; onTriggered: { var row = root.currentRowData(); App.copyToClipboard(row.descriptionUrl || "") } }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 12
        spacing: 8

        RowLayout {
            Layout.fillWidth: true
            TextField {
                Layout.fillWidth: true
                text: root.queryText
                placeholderText: ""
                color: "#d0d0d0"
                selectByMouse: true
                onTextChanged: root.queryText = text
                onAccepted: root.startSearch()
                background: Rectangle {
                    color: "#1b1b1b"
                    border.color: parent.activeFocus ? "#4488dd" : "#3a3a3a"
                    radius: 2
                }
            }
            DlgButton {
                text: App.torrentSearchManager.searchInProgress ? "Searching..." : "Search"
                primary: true
                enabled: !App.torrentSearchManager.searchInProgress
                         && App.torrentSearchManager.pythonAvailable
                         && root.queryText.trim().length > 0
                onClicked: root.startSearch()
            }
        }

        Text {
            Layout.fillWidth: true
            Layout.preferredHeight: text.length > 0 ? implicitHeight : 0
            visible: text.length > 0
            text: App.torrentSearchManager.statusText
            color: "#9aa6b2"
            font.pixelSize: 11
            elide: Text.ElideRight
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            color: "#1a1a1a"
            border.color: "#2d2d2d"
            radius: 4

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 1
                spacing: 0

                Rectangle {
                    id: headerBar
                    Layout.fillWidth: true
                    height: 26
                    color: "#2d2d2d"
                    clip: true
                    Repeater {
                        model: root.colsOrdered
                        delegate: Rectangle {
                            required property var modelData
                            x: root.colXMap[modelData.key] || 0
                            width: root.colW(modelData.key)
                            height: parent.height
                            color: "transparent"

                            Text {
                                anchors { left: parent.left; leftMargin: 6; right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
                                text: modelData.title + (root.sortKey === modelData.key ? (root.sortAscending ? " ▲" : " ▼") : "")
                                color: "#d7d7d7"
                                font.pixelSize: 12
                                font.bold: true
                                elide: Text.ElideRight
                            }

                            MouseArea {
                                id: headerCellMouse
                                anchors { fill: parent; rightMargin: 12 }
                                cursorShape: Qt.PointingHandCursor
                                preventStealing: true
                                property real pressX: 0
                                property bool didDrag: false
                                onPressed: function(mouse) {
                                    pressX = mouse.x
                                    didDrag = false
                                }
                                onPositionChanged: function(mouse) {
                                    if (!(mouse.buttons & Qt.LeftButton))
                                        return
                                    if (!didDrag && Math.abs(mouse.x - pressX) > 8) {
                                        root.dragColumnKey = modelData.key
                                        root.colDragFromKey = modelData.key
                                        root.colDragInsertBeforeKey = ""
                                        root.colDragging = true
                                        didDrag = true
                                    }
                                    if (root.colDragging && root.dragColumnKey === modelData.key) {
                                        var cursorX = headerCellMouse.mapToItem(headerBar, mouse.x, 0).x
                                        var insertBefore = "__end__"
                                        var xAcc = 0
                                        for (var i = 0; i < root.colsOrdered.length; ++i) {
                                            var key = root.colsOrdered[i].key
                                            var w = root.colW(key)
                                            if (cursorX < xAcc + w / 2) {
                                                insertBefore = key
                                                break
                                            }
                                            xAcc += w
                                        }
                                        root.colDragInsertBeforeKey = insertBefore
                                    }
                                }
                                onReleased: function(mouse) {
                                    var wasDrag = didDrag
                                    var rootRef = root
                                    Qt.callLater(function() {
                                        if (wasDrag)
                                            rootRef.commitColReorder()
                                        rootRef.dragColumnKey = ""
                                        rootRef.colDragFromKey = ""
                                        rootRef.colDragInsertBeforeKey = ""
                                        rootRef.colDragging = false
                                    })
                                    didDrag = false
                                    pressX = 0
                                }
                                onClicked: function(mouse) {
                                    if (!didDrag && mouse.button === Qt.LeftButton)
                                        root.sortBy(modelData.key)
                                    didDrag = false
                                }
                            }

                            Item {
                                anchors.right: parent.right
                                z: 2
                                width: 12
                                height: parent.height
                                property real _startW: 0
                                MouseArea {
                                    id: resizeMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    acceptedButtons: Qt.LeftButton
                                    preventStealing: true
                                    cursorShape: Qt.SizeHorCursor
                                    property real startWidth: 0
                                    property real startGlobalX: 0
                                    onPressed: function(mouse) {
                                        startWidth = root.colW(modelData.key)
                                        startGlobalX = resizeMouse.mapToItem(headerBar, mouse.x, 0).x
                                        root.dragColumnKey = modelData.key
                                    }
                                    onPositionChanged: function(mouse) {
                                        if (!(mouse.buttons & Qt.LeftButton))
                                            return
                                        var currentGlobalX = resizeMouse.mapToItem(headerBar, mouse.x, 0).x
                                        root.setColumnWidth(modelData.key, startWidth + (currentGlobalX - startGlobalX))
                                    }
                                    onReleased: {
                                        if (root.dragColumnKey === modelData.key)
                                            root.dragColumnKey = ""
                                    }
                                    onCanceled: {
                                        if (root.dragColumnKey === modelData.key)
                                            root.dragColumnKey = ""
                                    }
                                }
                            }

                        }
                    }
                }

                ListView {
                    id: resultList
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    model: App.torrentSearchManager.resultModel
                    contentWidth: root.totalColumnWidth()
                    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                    ScrollBar.horizontal: ScrollBar { policy: ScrollBar.AsNeeded }

                    delegate: Rectangle {
                        required property int index
                        required property string name
                        required property string sizeText
                        required property int seeders
                        required property int leechers
                        required property string engine
                        required property string publishedOn

                        width: Math.max(ListView.view.width, ListView.view.contentWidth)
                        height: 28
                        color: root.selectedRow === index ? "#2a3d59"
                              : (index % 2 === 0 ? "#1c1c1c" : "#222222")

                        Rectangle { anchors.left: parent.left; width: 1; height: parent.height; color: "#2a2a2a"; visible: false }

                        Text {
                            x: root.colXMap["name"] || 0
                            width: root.colName - 12
                            anchors.verticalCenter: parent.verticalCenter
                            leftPadding: 6
                            text: name
                            color: "#f0f0f0"
                            font.pixelSize: 12
                            elide: Text.ElideMiddle
                        }
                        Text {
                            x: root.colXMap["size"] || 0
                            width: root.colSize - 12
                            anchors.verticalCenter: parent.verticalCenter
                            leftPadding: 6
                            text: sizeText.length > 0 ? sizeText : "Unknown"
                            color: "#b6c0ca"
                            font.pixelSize: 12
                            elide: Text.ElideRight
                        }
                        Text {
                            x: root.colXMap["seeders"] || 0
                            width: root.colSeeders - 12
                            anchors.verticalCenter: parent.verticalCenter
                            leftPadding: 6
                            text: seeders >= 0 ? String(seeders) : "—"
                            color: "#f0f0f0"
                            font.pixelSize: 12
                        }
                        Text {
                            x: root.colXMap["leechers"] || 0
                            width: root.colLeechers - 12
                            anchors.verticalCenter: parent.verticalCenter
                            leftPadding: 6
                            text: leechers >= 0 ? String(leechers) : "—"
                            color: "#f0f0f0"
                            font.pixelSize: 12
                        }
                        Text {
                            x: root.colXMap["engine"] || 0
                            width: root.colEngine - 12
                            anchors.verticalCenter: parent.verticalCenter
                            leftPadding: 6
                            text: engine
                            color: "#9ab3cb"
                            font.pixelSize: 12
                            elide: Text.ElideRight
                        }
                        Text {
                            x: root.colXMap["publishedOn"] || 0
                            width: root.colPublished - 12
                            anchors.verticalCenter: parent.verticalCenter
                            leftPadding: 6
                            text: publishedOn.length > 0 ? publishedOn : "—"
                            color: "#a6adb6"
                            font.pixelSize: 12
                            elide: Text.ElideRight
                        }

                        MouseArea {
                            anchors.fill: parent
                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                            onClicked: function(mouse) {
                                root.selectedRow = index
                                root.ctxRow = index
                                if (mouse.button === Qt.RightButton)
                                    resultMenu.popup()
                            }
                            onDoubleClicked: function(mouse) {
                                if (mouse.button !== Qt.LeftButton)
                                    return
                                root.selectedRow = index
                                root.ctxRow = index
                                root.triggerDownload(root.currentRowData())
                            }
                        }
                    }

                    Text {
                        anchors.centerIn: parent
                        visible: resultList.count === 0 && !App.torrentSearchManager.searchInProgress
                        text: "No search results yet"
                        color: "#666"
                        font.pixelSize: 13
                    }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Item { Layout.fillWidth: true }
            DlgButton { text: "Search Plugins"; onClicked: { pluginsDialog.show(); pluginsDialog.raise(); pluginsDialog.requestActivate() } }
        }
    }
}
