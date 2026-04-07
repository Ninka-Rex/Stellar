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

Rectangle {
    id: root
    color: "#1c1c1c"

    signal openProgressRequested(var item)
    signal openPropertiesRequested(var item)
    signal openColumnsSettingsRequested()

    // Window-level drag proxy injected from Main.qml
    property var categoryDragProxy: null

    // Public API called by Main.qml toolbar signals
    function resumeSelected()  { const id = _selectedId(); if (id) App.resumeDownload(id) }
    function stopSelected()    { const id = _selectedId(); if (id) App.pauseDownload(id)  }
    function pauseAll()        { App.pauseAllDownloads() }
    function deleteSelected()  {
        const item = _selectedItem()
        if (item) _openDeleteDialog(item)
    }
    function _selectedItem() {
        if (tableView.currentRow < 0) return null
        return App.downloadModel.data(
            App.downloadModel.index(tableView.currentRow, 0), Qt.UserRole + 2)
    }
    function _selectedId() {
        const item = _selectedItem()
        return item ? item.id : null
    }
    function _openDeleteDialog(item) {
        deleteDialog.downloadId = item.id
        deleteDialog.filename   = item.filename
        deleteDialog.fileExists = item.status === "Completed"
        deleteDialog.show()
        deleteDialog.raise()
        deleteDialog.requestActivate()
    }

    // ── Delete confirmation dialog ────────────────────────────────────────────
    DeleteConfirmDialog {
        id: deleteDialog
        onConfirmed: (mode) => App.deleteDownload(downloadId, mode)
    }

    // Default column definitions
    readonly property var _defaultColumnDefs: [
        { title: "Q",              key: "queue",      widthPx: 28,  visible: true  },
        { title: "File Name",      key: "name",       widthPx: 240, visible: true  },
        { title: "Size",           key: "size",       widthPx: 80,  visible: true  },
        { title: "Status",         key: "status",     widthPx: 90,  visible: true  },
        { title: "Time left",      key: "timeleft",   widthPx: 90,  visible: true  },
        { title: "Transfer rate",  key: "speed",      widthPx: 90,  visible: true  },
        { title: "Date added",     key: "added",      widthPx: 110, visible: true  },
        { title: "Last try date",  key: "lasttry",    widthPx: 110, visible: false },
        { title: "Description",    key: "description",widthPx: 120, visible: false },
        { title: "Save to",        key: "saveto",     widthPx: 140, visible: false },
        { title: "Referer",        key: "referrer",   widthPx: 140, visible: false },
        { title: "Parent web page",key: "parenturl",  widthPx: 140, visible: false },
    ]

    // Column definitions – visibility toggled from context menu / ColumnsDialog
    property var columnDefs: _defaultColumnDefs.slice()

    function resetColumns() { columnDefs = _defaultColumnDefs.slice() }

    // Compute visible columns only
    function makeVisibleCols() {
        var r = []
        for (var i = 0; i < columnDefs.length; i++)
            if (columnDefs[i].visible) r.push(columnDefs[i])
        return r
    }
    property var visibleCols: makeVisibleCols()
    onColumnDefsChanged: visibleCols = makeVisibleCols()

    function colWidth(key) {
        // Scale pixel widths proportionally to fill available width
        var totalPx = 0
        for (var i = 0; i < visibleCols.length; i++) totalPx += (visibleCols[i].widthPx || 100)
        for (var j = 0; j < visibleCols.length; j++) {
            if (visibleCols[j].key === key) {
                var frac = (visibleCols[j].widthPx || 100) / Math.max(totalPx, 1)
                return root.width * frac
            }
        }
        return 0
    }

    // ── Active filter (driven by inline find bar in Main.qml) ─────────────────
    property string filterText:       ""
    property bool   filterName:       true
    property bool   filterDesc:       false
    property bool   filterLinks:      false
    property bool   filterMatchCase:  false
    property bool   filterMatchWhole: false

    function clearFilter() {
        filterText = ""
        _findRow   = -1
    }

    function findFirstFiltered() {
        _findRow = -1
        const model = App.downloadModel
        for (var i = 0; i < model.rowCount(); i++) {
            const item = model.data(model.index(i, 0), Qt.UserRole + 2)
            if (_itemMatchesFind(item, filterText, filterName, filterDesc, filterLinks, filterMatchCase, filterMatchWhole)) {
                _findRow = i
                tableView.currentRow = i
                tableView.positionViewAtIndex(i, ListView.Center)
                return
            }
        }
    }

    function findNextFiltered() {
        if (filterText.length === 0) return
        const model = App.downloadModel
        const start = _findRow < 0 ? 0 : (_findRow + 1) % Math.max(model.rowCount(), 1)
        for (var i = 0; i < model.rowCount(); i++) {
            const row = (start + i) % model.rowCount()
            const item = model.data(model.index(row, 0), Qt.UserRole + 2)
            if (_itemMatchesFind(item, filterText, filterName, filterDesc, filterLinks, filterMatchCase, filterMatchWhole)) {
                _findRow = row
                tableView.currentRow = row
                tableView.positionViewAtIndex(row, ListView.Center)
                return
            }
        }
    }

    // Find support
    property int _findRow: -1

    function _itemMatchesFind(item, text, name, desc, links, mc, mw) {
        if (!item || text.length === 0) return false
        const t = mc ? text : text.toLowerCase()
        function check(s) {
            const v = mc ? s : s.toLowerCase()
            return mw ? v === t : v.includes(t)
        }
        if (name  && check(item.filename))    return true
        if (desc  && check(item.description)) return true
        if (links && (check(item.url.toString()) || check(item.referrer) || check(item.parentUrl))) return true
        return false
    }

    function countMatches(text, name, desc, links, mc, mw) {
        if (text.length === 0) return 0
        var count = 0
        const model = App.downloadModel
        for (var i = 0; i < model.rowCount(); i++) {
            const item = model.data(model.index(i, 0), Qt.UserRole + 2)
            if (_itemMatchesFind(item, text, name, desc, links, mc, mw)) count++
        }
        return count
    }

    function findFirst(text, name, desc, links, mc, mw) {
        _findRow = -1
        const model = App.downloadModel
        for (var i = 0; i < model.rowCount(); i++) {
            const item = model.data(model.index(i, 0), Qt.UserRole + 2)
            if (_itemMatchesFind(item, text, name, desc, links, mc, mw)) {
                _findRow = i
                tableView.currentRow = i
                tableView.positionViewAtIndex(i, ListView.Center)
                return
            }
        }
    }

    function findNext(text, name, desc, links, mc, mw) {
        const model = App.downloadModel
        const start = (_findRow + 1) % Math.max(model.rowCount(), 1)
        for (var i = 0; i < model.rowCount(); i++) {
            const row = (start + i) % model.rowCount()
            const item = model.data(model.index(row, 0), Qt.UserRole + 2)
            if (_itemMatchesFind(item, text, name, desc, links, mc, mw)) {
                _findRow = row
                tableView.currentRow = row
                tableView.positionViewAtIndex(row, ListView.Center)
                return
            }
        }
    }

    // ── Sort state ────────────────────────────────────────────────────────────
    property string sortKey:       "added"
    property bool   sortAscending: false

    function applySort(key) {
        if (sortKey === key) {
            sortAscending = !sortAscending
        } else {
            sortKey = key
            sortAscending = true
        }
        App.downloadModel.sortBy(sortKey, sortAscending)
    }

    // Sortable column keys (queue and progress columns are not sortable)
    readonly property var _sortableKeys: ["name","size","status","timeleft","speed","added","lasttry","description","saveto","referrer","parenturl"]

    // ── Column visibility context menu ────────────────────────────────────────
    Menu {
        id: colCtxMenu
        Repeater {
            model: root.columnDefs.length
            delegate: MenuItem {
                text: root.columnDefs[index].title
                checkable: true
                checked: root.columnDefs[index].visible
                onToggled: {
                    var defs = root.columnDefs.slice()
                    defs[index] = Object.assign({}, defs[index], { visible: checked })
                    root.columnDefs = defs
                }
            }
        }
        MenuSeparator {}
        MenuItem {
            text: "Columns Settings"
            onTriggered: root.openColumnsSettingsRequested()
        }
    }

    // ── Header ────────────────────────────────────────────────────────────────
    Rectangle {
        id: header
        anchors { top: parent.top; left: parent.left; right: parent.right }
        height: 26
        color: "#2d2d2d"

        Row {
            anchors.fill: parent

            Repeater {
                model: root.visibleCols
                delegate: Rectangle {
                    id: headerCell
                    width:  root.colWidth(modelData.key)
                    height: parent.height
                    readonly property bool isSortable: root._sortableKeys.indexOf(modelData.key) >= 0
                    readonly property bool isActive:   root.sortKey === modelData.key
                    color: (isSortable && headerCellMouse.containsMouse) ? "#383838" : "transparent"

                    Text {
                        anchors { verticalCenter: parent.verticalCenter; left: parent.left; leftMargin: 6; right: sortIndicator.left; rightMargin: 2 }
                        text: modelData.title
                        color: headerCell.isActive ? "#88bbff" : "#b0b0b0"
                        font.pixelSize: 12
                        font.bold: true
                        elide: Text.ElideRight
                    }

                    Text {
                        id: sortIndicator
                        anchors { verticalCenter: parent.verticalCenter; right: resizeHandle.left; rightMargin: 4 }
                        text: root.sortAscending ? "▲" : "▼"
                        color: "#88bbff"
                        font.pixelSize: 9
                        visible: headerCell.isActive
                    }

                    MouseArea {
                        id: headerCellMouse
                        anchors { fill: parent; rightMargin: 6 }
                        hoverEnabled: true
                        cursorShape: headerCell.isSortable ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onClicked: if (headerCell.isSortable) root.applySort(modelData.key)
                    }

                    Rectangle {
                        anchors.right: parent.right
                        width: 1; height: parent.height
                        color: "#3a3a3a"
                    }

                    // ── Column resize handle ──────────────────────────────
                    MouseArea {
                        id: resizeHandle
                        width: 6
                        height: parent.height
                        anchors.right: parent.right
                        z: 10
                        cursorShape: Qt.SizeHorCursor

                        property real _startMouseX:  0
                        property real _startWidthPx: 0

                        onPressed: function(mouse) {
                            _startMouseX  = mouse.x
                            _startWidthPx = modelData.widthPx || 100
                        }

                        onPositionChanged: function(mouse) {
                            if (!(pressedButtons & Qt.LeftButton)) return
                            var delta = mouse.x - _startMouseX
                            var totalPx = 0
                            for (var i = 0; i < root.visibleCols.length; i++)
                                totalPx += (root.visibleCols[i].widthPx || 100)
                            var newWidthPx = Math.max(24, Math.round(_startWidthPx + delta * totalPx / Math.max(root.width, 1)))
                            var defs = root.columnDefs.slice()
                            for (var j = 0; j < defs.length; j++) {
                                if (defs[j].key === modelData.key) {
                                    defs[j] = Object.assign({}, defs[j], { widthPx: newWidthPx })
                                    break
                                }
                            }
                            root.columnDefs = defs
                        }
                    }
                }
            }
        }

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.RightButton
            onClicked: colCtxMenu.popup()
        }

        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: "#3a3a3a" }
    }

    // ── Rows ──────────────────────────────────────────────────────────────────
    ListView {
        id: tableView
        anchors { top: header.bottom; left: parent.left; right: parent.right; bottom: parent.bottom }
        model: App.downloadModel
        clip: true
        property int currentRow: -1

        ScrollBar.vertical: ScrollBar {}

        delegate: Rectangle {
            id: rowRect
            width: tableView.width

            // Grab the DownloadItem* from the model — this binding IS reactive
            // because Qt model delegates re-evaluate when dataChanged fires for this row
            readonly property var item: model.item

            readonly property bool _matchesFilter:
                root.filterText.length === 0 ||
                root._itemMatchesFind(item, root.filterText, root.filterName, root.filterDesc,
                                      root.filterLinks, root.filterMatchCase, root.filterMatchWhole)

            height:  _matchesFilter ? 26 : 0
            visible: _matchesFilter
            clip: true

            color: tableView.currentRow === index
                   ? "#1e3a6e"
                   : (rowMouse.containsMouse
                      ? "#2a2a2a"
                      : (index % 2 === 0 ? "#1c1c1c" : "#222222"))

            // Dynamic column rendering
            Row {
                anchors.fill: parent

                Repeater {
                    model: root.visibleCols
                    delegate: Item {
                        width: root.colWidth(modelData.key)
                        height: rowRect.height
                        clip: true
                        visible: width > 0

                        // ── Q (queue icon) ────────────────────────────────
                        Loader {
                            active: modelData.key === "queue"
                            anchors.fill: parent
                            sourceComponent: Component {
                                Item {
                                    anchors.fill: parent
                                    Rectangle {
                                        anchors.centerIn: parent
                                        width: 14; height: 14; radius: 2
                                        visible: rowRect.item && rowRect.item.queueId.length > 0
                                        color: {
                                            if (!rowRect.item) return "transparent"
                                            const q = rowRect.item.queueId
                                            if (q === "main-sync") return "#40a060"
                                            if (q === "main-download") return "#4060c0"
                                            if (q === "download-limits") return "#a06020"
                                            return "#6060a0"
                                        }
                                        Text {
                                            anchors.centerIn: parent
                                            text: "Q"; color: "white"
                                            font.pixelSize: 8; font.bold: true
                                        }
                                    }
                                }
                            }
                        }

                        // ── File Name ─────────────────────────────────────
                        Loader {
                            active: modelData.key === "name"
                            anchors.fill: parent
                            sourceComponent: Component {
                                Item {
                                    anchors.fill: parent
                                    Row {
                                        anchors { verticalCenter: parent.verticalCenter; left: parent.left; leftMargin: 6 }
                                        spacing: 6
                                        Image {
                                            width: 18; height: 18
                                            anchors.verticalCenter: parent.verticalCenter
                                            source: rowRect.item ? "image://fileicon/" + (rowRect.item.savePath + "/" + rowRect.item.filename).replace(/\\/g, "/") : ""
                                            sourceSize: Qt.size(18, 18)
                                            fillMode: Image.PreserveAspectFit
                                            smooth: true
                                        }
                                        Text {
                                            text: rowRect.item ? rowRect.item.filename : ""
                                            color: tableView.currentRow === index ? "#ffffff" : "#d0d0d0"
                                            font.pixelSize: 12
                                            width: root.colWidth("name") - 42
                                            elide: Text.ElideMiddle
                                            anchors.verticalCenter: parent.verticalCenter
                                        }
                                    }
                                }
                            }
                        }

                        // ── Size ─────────────────────────────────────────
                        Loader {
                            active: modelData.key === "size"
                            anchors.fill: parent
                            sourceComponent: Component {
                                Text {
                                    anchors { fill: parent; leftMargin: 6 }
                                    verticalAlignment: Text.AlignVCenter
                                    text: {
                                        if (!rowRect.item || rowRect.item.totalBytes <= 0) return "--"
                                        const b = rowRect.item.totalBytes
                                        if (b < 1048576)    return (b / 1024).toFixed(1) + " KB"
                                        if (b < 1073741824) return (b / 1048576).toFixed(1) + " MB"
                                        return (b / 1073741824).toFixed(2) + " GB"
                                    }
                                    color: tableView.currentRow === index ? "#ffffff" : "#b0b0b0"
                                    font.pixelSize: 12
                                }
                            }
                        }

                        // ── Status ───────────────────────────────────────
                        Loader {
                            active: modelData.key === "status"
                            anchors.fill: parent
                            sourceComponent: Component {
                                Text {
                                    anchors { fill: parent; leftMargin: 6 }
                                    verticalAlignment: Text.AlignVCenter
                                    text: {
                                        if (!rowRect.item) return "--"
                                        const s = rowRect.item.status
                                        if (s === "Downloading") return (rowRect.item.progress * 100).toFixed(1) + "%"
                                        return s
                                    }
                                    color: {
                                        if (tableView.currentRow === index) return "#ffffff"
                                        if (!rowRect.item) return "#b0b0b0"
                                        const s = rowRect.item.status
                                        if (s === "Downloading") return "#66cc66"
                                        if (s === "Paused")      return "#e0c040"
                                        if (s === "Error")       return "#e06060"
                                        if (s === "Completed")   return "#60c0e0"
                                        return "#b0b0b0"
                                    }
                                    font.pixelSize: 12
                                }
                            }
                        }

                        // ── Time left ────────────────────────────────────
                        Loader {
                            active: modelData.key === "timeleft"
                            anchors.fill: parent
                            sourceComponent: Component {
                                Text {
                                    anchors { fill: parent; leftMargin: 6 }
                                    verticalAlignment: Text.AlignVCenter
                                    text: rowRect.item ? rowRect.item.timeLeft : ""
                                    color: tableView.currentRow === index ? "#ffffff" : "#b0b0b0"
                                    font.pixelSize: 12
                                }
                            }
                        }

                        // ── Transfer rate ────────────────────────────────
                        Loader {
                            active: modelData.key === "speed"
                            anchors.fill: parent
                            sourceComponent: Component {
                                Text {
                                    anchors { fill: parent; leftMargin: 6 }
                                    verticalAlignment: Text.AlignVCenter
                                    text: {
                                        if (!rowRect.item || rowRect.item.status !== "Downloading") return ""
                                        const bps = rowRect.item.speed
                                        if (bps <= 0)      return ""
                                        if (bps < 1048576) return (bps / 1024).toFixed(1) + " KB/s"
                                        return (bps / 1048576).toFixed(2) + " MB/s"
                                    }
                                    color: tableView.currentRow === index ? "#ffffff" : "#80c080"
                                    font.pixelSize: 12
                                }
                            }
                        }

                        // ── Date added ───────────────────────────────────
                        Loader {
                            active: modelData.key === "added"
                            anchors.fill: parent
                            sourceComponent: Component {
                                Text {
                                    anchors { fill: parent; leftMargin: 6 }
                                    verticalAlignment: Text.AlignVCenter
                                    text: rowRect.item ? Qt.formatDateTime(rowRect.item.addedAt, "MMM dd yyyy h:mm:ss AP") : ""
                                    color: tableView.currentRow === index ? "#ffffff" : "#b0b0b0"
                                    font.pixelSize: 11
                                }
                            }
                        }

                        // ── Last try date ────────────────────────────────
                        Loader {
                            active: modelData.key === "lasttry"
                            anchors.fill: parent
                            sourceComponent: Component {
                                Text {
                                    anchors { fill: parent; leftMargin: 6 }
                                    verticalAlignment: Text.AlignVCenter
                                    text: rowRect.item && rowRect.item.lastTryAt.getTime() > 0
                                          ? Qt.formatDateTime(rowRect.item.lastTryAt, "MM/dd/yy hh:mm")
                                          : "--"
                                    color: tableView.currentRow === index ? "#ffffff" : "#b0b0b0"
                                    font.pixelSize: 11
                                }
                            }
                        }

                        // ── Description ──────────────────────────────────
                        Loader {
                            active: modelData.key === "description"
                            anchors.fill: parent
                            sourceComponent: Component {
                                Text {
                                    anchors { fill: parent; leftMargin: 6 }
                                    verticalAlignment: Text.AlignVCenter
                                    text: rowRect.item ? (rowRect.item.description || "--") : "--"
                                    color: tableView.currentRow === index ? "#ffffff" : "#b0b0b0"
                                    font.pixelSize: 11; elide: Text.ElideRight; width: parent.width - 8
                                }
                            }
                        }

                        // ── Save to ──────────────────────────────────────
                        Loader {
                            active: modelData.key === "saveto"
                            anchors.fill: parent
                            sourceComponent: Component {
                                Text {
                                    anchors { fill: parent; leftMargin: 6 }
                                    verticalAlignment: Text.AlignVCenter
                                    text: rowRect.item ? rowRect.item.savePath : "--"
                                    color: tableView.currentRow === index ? "#ffffff" : "#b0b0b0"
                                    font.pixelSize: 11; elide: Text.ElideMiddle; width: parent.width - 8
                                }
                            }
                        }

                        // ── Referer ──────────────────────────────────────
                        Loader {
                            active: modelData.key === "referrer"
                            anchors.fill: parent
                            sourceComponent: Component {
                                Text {
                                    anchors { fill: parent; leftMargin: 6 }
                                    verticalAlignment: Text.AlignVCenter
                                    text: rowRect.item ? (rowRect.item.referrer || "--") : "--"
                                    color: tableView.currentRow === index ? "#ffffff" : "#b0b0b0"
                                    font.pixelSize: 11; elide: Text.ElideRight; width: parent.width - 8
                                }
                            }
                        }

                        // ── Parent web page ──────────────────────────────
                        Loader {
                            active: modelData.key === "parenturl"
                            anchors.fill: parent
                            sourceComponent: Component {
                                Text {
                                    anchors { fill: parent; leftMargin: 6 }
                                    verticalAlignment: Text.AlignVCenter
                                    text: rowRect.item ? (rowRect.item.parentUrl || "--") : "--"
                                    color: tableView.currentRow === index ? "#ffffff" : "#b0b0b0"
                                    font.pixelSize: 11; elide: Text.ElideRight; width: parent.width - 8
                                }
                            }
                        }
                    }
                }
            }

            // progress bar strip at the bottom of each active row
            Rectangle {
                anchors { bottom: parent.bottom; left: parent.left }
                width: rowRect.item ? rowRect.item.progress * rowRect.width : 0
                height: 3
                color: "#4488dd"
                visible: rowRect.item !== null && rowRect.item.status === "Downloading"
                Behavior on width { NumberAnimation { duration: 400 } }
            }

            // bottom row border
            Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: "#2e2e2e" }

            MouseArea {
                id: rowMouse
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                preventStealing: true   // stops ListView from taking the grab mid-drag

                property point pressPos
                property bool dragActive: false

                onPressed: function(mouse) {
                    pressPos = Qt.point(mouse.x, mouse.y)
                    dragActive = false
                }

                onPositionChanged: function(mouse) {
                    if (!(pressedButtons & Qt.LeftButton)) return
                    var dx = mouse.x - pressPos.x
                    var dy = mouse.y - pressPos.y
                    if (!dragActive && (Math.abs(dx) > 8 || Math.abs(dy) > 8)) {
                        if (root.categoryDragProxy && rowRect.item) {
                            dragActive = true
                            root.categoryDragProxy.dragDownloadId = rowRect.item.id
                            root.categoryDragProxy.dragFilename   = rowRect.item.filename
                            root.categoryDragProxy.visible = true
                        }
                    }
                    if (dragActive && root.categoryDragProxy) {
                        // Move proxy to cursor in window coordinates
                        var winPos = mapToItem(null, mouse.x, mouse.y)
                        root.categoryDragProxy.x = winPos.x
                        root.categoryDragProxy.y = winPos.y
                    }
                }

                onReleased: function(mouse) {
                    if (dragActive && root.categoryDragProxy) {
                        root.categoryDragProxy.Drag.drop()
                        root.categoryDragProxy.visible = false
                        root.categoryDragProxy.dragDownloadId = ""
                        root.categoryDragProxy.dragFilename   = ""
                        dragActive = false
                    }
                }

                onClicked: function(mouse) {
                    if (!dragActive) {
                        tableView.currentRow = index
                        if (mouse.button === Qt.RightButton) rowCtxMenu.popup()
                    }
                }

                onDoubleClicked: function(mouse) {
                    if (!rowRect.item) return
                    if (rowRect.item.status === "Completed") {
                        root.openPropertiesRequested(rowRect.item)
                    } else {
                        root.openProgressRequested(rowRect.item)
                    }
                }
            }

            Menu {
                id: rowCtxMenu
                Action {
                    text: "Properties"
                    onTriggered: {
                        if (!rowRect.item) return
                        if (rowRect.item.status === "Completed") root.openPropertiesRequested(rowRect.item)
                        else root.openProgressRequested(rowRect.item)
                    }
                }
                Action { text: "Open File";   onTriggered: { if (rowRect.item) App.openFile(rowRect.item.id)   } }
                Action { text: "Open Folder"; onTriggered: { if (rowRect.item) App.openFolderSelectFile(rowRect.item.id) } }
                MenuSeparator {}
                Action { text: "Copy Filename"; onTriggered: { if (rowRect.item) App.copyDownloadFilename(rowRect.item.id) } }
                Action { text: "Copy URL"; onTriggered: { if (rowRect.item) App.copyToClipboard(rowRect.item.url.toString()) } }
                MenuSeparator {}
                Action { text: "Resume";  onTriggered: root.resumeSelected() }
                Action { text: "Stop";    onTriggered: root.stopSelected()   }
                MenuSeparator {}

                Menu {
                    title: "Move to Queue"
                    Repeater {
                        model: App.queueModel
                        delegate: MenuItem {
                            visible: queueId !== "download-limits"
                            text: queueName || ""
                            onTriggered: {
                                if (rowRect.item)
                                    App.setDownloadQueue(rowRect.item.id, queueId)
                            }
                        }
                    }
                }

                MenuSeparator {}
                Action { text: "Delete";  onTriggered: { if (rowRect.item) root._openDeleteDialog(rowRect.item) } }
            }
        }

        // empty state
        Text {
            anchors.centerIn: parent
            visible: tableView.count === 0
            text: "No downloads yet.\nClick  Add URL  to start."
            horizontalAlignment: Text.AlignHCenter
            color: "#444444"
            font.pixelSize: 14
            lineHeight: 1.6
        }
    }
}
