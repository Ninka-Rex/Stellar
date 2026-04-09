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

    // ── Multi-selection state ─────────────────────────────────────────────────
    // _selectedRows is a plain JS object used as a set (keys = row indices).
    // _selectionVersion bumps on every change so QML bindings that read it
    // know to re-evaluate.
    property var _selectedRows:     ({})
    property int _selectionVersion: 0

    function isRowSelected(row) { return !!_selectedRows[row] }

    function _setSelection(rows) {
        _selectedRows = rows
        _selectionVersion++
    }

    function _toggleRow(row) {
        var r = Object.assign({}, _selectedRows)
        if (r[row]) delete r[row]
        else r[row] = true
        _setSelection(r)
    }

    function _addRangeTo(anchorRow, row) {
        var r = Object.assign({}, _selectedRows)
        var lo = Math.min(anchorRow, row), hi = Math.max(anchorRow, row)
        for (var i = lo; i <= hi; i++) r[i] = true
        _setSelection(r)
    }

    function _clearAndSelect(row) {
        var r = {}
        if (row >= 0) r[row] = true
        _setSelection(r)
    }

    // Last single-click row — used as anchor for shift-click range selection
    property int _anchorRow: -1

    // Reactive property: the primary selected item (for dialogs / toolbar enablement).
    // Returns the DownloadItem at _anchorRow, or null.
    readonly property var currentSelectedItem: {
        _selectionVersion  // dependency trigger
        if (_anchorRow < 0) return null
        return App.downloadModel.data(App.downloadModel.index(_anchorRow, 0), Qt.UserRole + 2)
    }

    // String status of the focused item — a primitive that QML reliably tracks across
    // component boundaries. Reading currentSelectedItem.status works in local bindings
    // but the cross-component signal chain can break when the same object is returned
    // (no change emitted). A dedicated string property emits its own change signal.
    readonly property string selectedItemStatus: currentSelectedItem ? currentSelectedItem.status : ""

    // True when any item is selected
    readonly property bool hasSelection: { _selectionVersion; return Object.keys(_selectedRows).length > 0 }

    // Reactive properties for toolbar enabled-states.
    // As readonly property bindings (not functions) QML emits a change signal when
    // _selectionVersion bumps, so cross-component bindings like Toolbar's `enabled:`
    // re-evaluate automatically. A plain function call would NOT propagate changes.
    readonly property bool anyPausedSelected: {
        _selectionVersion
        for (var row in _selectedRows) {
            var item = App.downloadModel.data(App.downloadModel.index(parseInt(row), 0), Qt.UserRole + 2)
            if (item && item.status === "Paused") return true
        }
        return false
    }
    readonly property bool anyActiveSelected: {
        _selectionVersion
        for (var row in _selectedRows) {
            var item = App.downloadModel.data(App.downloadModel.index(parseInt(row), 0), Qt.UserRole + 2)
            if (item && (item.status === "Downloading" || item.status === "Queued")) return true
        }
        return false
    }

    // Kept for backward compatibility with any callers; internally delegates to reactive props.
    function anySelectedHasStatus(status) {
        if (status === "Paused")                             return anyPausedSelected
        if (status === "Downloading" || status === "Queued") return anyActiveSelected
        _selectionVersion
        for (var row in _selectedRows) {
            var item = App.downloadModel.data(App.downloadModel.index(parseInt(row), 0), Qt.UserRole + 2)
            if (item && item.status === status) return true
        }
        return false
    }

    // ── Public API called by Main.qml toolbar signals ─────────────────────────
    function resumeSelected() {
        _selectionVersion  // touch dependency
        for (var row in _selectedRows) {
            var item = App.downloadModel.data(App.downloadModel.index(parseInt(row), 0), Qt.UserRole + 2)
            if (item) App.resumeDownload(item.id)
        }
    }
    function stopSelected() {
        _selectionVersion
        for (var row in _selectedRows) {
            var item = App.downloadModel.data(App.downloadModel.index(parseInt(row), 0), Qt.UserRole + 2)
            if (item) App.pauseDownload(item.id)
        }
    }
    function pauseAll()        { App.pauseAllDownloads() }
    function deleteSelected()  {
        // For multi-select, delete all selected. For single, show dialog.
        var rows = Object.keys(_selectedRows)
        if (rows.length === 1) {
            var item = _selectedItem()
            if (item) _openDeleteDialog(item)
        } else if (rows.length > 1) {
            // Delete without dialog for multiple selection
            for (var i = 0; i < rows.length; i++) {
                var it = App.downloadModel.data(App.downloadModel.index(parseInt(rows[i]), 0), Qt.UserRole + 2)
                if (it) App.deleteDownload(it.id, 0)
            }
            _setSelection({})
            _anchorRow = -1
        }
    }
    function _selectedItem() {
        if (_anchorRow < 0) return null
        return App.downloadModel.data(
            App.downloadModel.index(_anchorRow, 0), Qt.UserRole + 2)
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

    // Bump _selectionVersion when any item's data changes (e.g. status transitions
    // from Downloading→Paused). Toolbar button enabled-states depend on
    // anySelectedHasStatus(), which reads _selectionVersion as a reactive trigger,
    // so without this the toolbar would stay stale after a stop/resume.
    Connections {
        target: App.downloadModel
        function onDataChanged(topLeft, bottomRight, roles) { root._selectionVersion++ }
    }

    // Default column definitions
    readonly property var _defaultColumnDefs: [
        { title: "Q",              key: "queue",      widthPx: 28,  visible: true  },
        { title: "File Name",      key: "name",       widthPx: 240, visible: true  },
        { title: "Size",           key: "size",       widthPx: 80,  visible: true  },
        { title: "Status",         key: "status",     widthPx: 90,  visible: true  },
        { title: "Time left",      key: "timeleft",   widthPx: 90,  visible: true  },
        { title: "Transfer rate",  key: "speed",      widthPx: 90,  visible: true  },
        { title: "Last try date",  key: "added",      widthPx: 130, visible: true  },
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

    // Cached column widths - only recalculate when width changes
    property real _lastRootWidth: 0
    property var _cachedColWidths: ({})

    function colWidth(key) {
        // Only recalculate if root width changed
        if (root.width !== _lastRootWidth || Object.keys(_cachedColWidths).length === 0) {
            _lastRootWidth = root.width
            var totalPx = 0
            for (var i = 0; i < visibleCols.length; i++) totalPx += (visibleCols[i].widthPx || 100)
            var newCache = {}
            for (var j = 0; j < visibleCols.length; j++) {
                var frac = (visibleCols[j].widthPx || 100) / Math.max(totalPx, 1)
                newCache[visibleCols[j].key] = root.width * frac
            }
            _cachedColWidths = newCache
        }
        return _cachedColWidths[key] || 0
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
                root._clearAndSelect(i)
                root._anchorRow = i
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
                root._clearAndSelect(row)
                root._anchorRow = row
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
                root._clearAndSelect(i)
                root._anchorRow = i
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
                root._clearAndSelect(row)
                root._anchorRow = row
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
        cacheBuffer: 650
        reuseItems: true
        interactive: true
        focus: true

        // Ctrl+A: select all rows currently visible in the model.
        // We build the selection set in one pass rather than calling _toggleRow
        // repeatedly to avoid emitting _selectionVersion for every row.
        Keys.onPressed: function(e) {
            if (e.key === Qt.Key_A && (e.modifiers & Qt.ControlModifier)) {
                var r = {}
                for (var i = 0; i < App.downloadModel.rowCount(); i++) r[i] = true
                root._setSelection(r)
                root._anchorRow = App.downloadModel.rowCount() - 1
                e.accepted = true
            }
        }

        ScrollBar.vertical: ScrollBar {}

        delegate: Rectangle {
            id: rowRect
            width: tableView.width
            height: 26

            readonly property var item: model.item
            // Capture the ListView row index as a named property so inner Repeater
            // delegates can reference it — inside a Repeater `index` is the column index.
            readonly property int rowIndex: index

            ListView.onReused: rowMouse.dragActive = false

            // Highlight selected rows; use _selectionVersion as a dependency so the
            // binding re-evaluates whenever the selection changes.
            color: {
                root._selectionVersion
                if (root.isRowSelected(rowIndex)) return "#1e3a6e"
                if (rowMouse.containsMouse)        return "#2a2a2a"
                return rowIndex % 2 === 0 ? "#1c1c1c" : "#222222"
            }

            clip: true

            Row {
                anchors.fill: parent

                Repeater {
                    model: root.visibleCols
                    delegate: Item {
                        width: root.colWidth(modelData.key)
                        height: rowRect.height
                        clip: true
                        visible: width > 0

                        // Use rowRect.rowIndex (the ListView row) not `index` (the Repeater column).
                        readonly property bool _sel: { root._selectionVersion; return root.isRowSelected(rowRect.rowIndex) }

                        Image {
                            visible: modelData.key === "queue" && rowRect.item && rowRect.item.queueId && rowRect.item.queueId.length > 0
                            anchors.centerIn: parent
                            source: {
                                const q = rowRect.item ? rowRect.item.queueId : ""
                                if (q === "main-download") return "qrc:/qt/qml/com/stellar/app/app/qml/icons/main_queue.png"
                                if (q === "main-sync") return "qrc:/qt/qml/com/stellar/app/app/qml/icons/synch_queue.png"
                                return "qrc:/qt/qml/com/stellar/app/app/qml/icons/custom_queue.png"
                            }
                            width: 14; height: 14
                            sourceSize: Qt.size(14, 14)
                            fillMode: Image.PreserveAspectFit
                            ToolTip.visible: ma.containsMouse
                            ToolTip.text: {
                                const qid = rowRect.item ? rowRect.item.queueId : ""
                                if (!qid) return ""
                                // Find queue name — Qt.UserRole is 32, so IdRole = 34, NameRole = 35
                                for (var i = 0; i < App.queueModel.rowCount(); i++) {
                                    var queueId = App.queueModel.data(App.queueModel.index(i, 0), 34)
                                    if (queueId === qid) {
                                        var queueName = App.queueModel.data(App.queueModel.index(i, 0), 35)
                                        return queueName || qid
                                    }
                                }
                                return qid
                            }
                            MouseArea {
                                id: ma
                                anchors.fill: parent
                                hoverEnabled: true
                            }
                        }

                        Row {
                            visible: modelData.key === "name"
                            anchors { verticalCenter: parent.verticalCenter; left: parent.left; leftMargin: 6 }
                            spacing: 6
                            width: parent.width - 12
                            Image {
                                width: 18; height: 18
                                anchors.verticalCenter: parent.verticalCenter
                                // cache:false forces a provider re-request when the source changes.
                                // The "?c=1" suffix flips once the download completes, causing the
                                // binding to re-evaluate and QML to fetch the real on-disk icon
                                // instead of the extension-based placeholder used during download.
                                source: rowRect.item ? "image://fileicon/" + (rowRect.item.savePath + "/" + rowRect.item.filename).replace(/\\/g, "/") + (rowRect.item.status === "Completed" ? "?c=1" : "") : ""
                                cache: false
                                sourceSize: Qt.size(18, 18)
                                fillMode: Image.PreserveAspectFit
                                asynchronous: true
                            }
                            Text {
                                text: rowRect.item ? rowRect.item.filename : ""
                                color: parent.parent.parent._sel ? "#ffffff" : "#d0d0d0"
                                font.pixelSize: 12
                                width: parent.parent.width - 42
                                elide: Text.ElideMiddle
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }

                        Text {
                            visible: modelData.key === "size"
                            anchors { fill: parent; leftMargin: 6 }
                            verticalAlignment: Text.AlignVCenter
                            text: rowRect.item ? (rowRect.item.totalBytes > 0 ? (rowRect.item.totalBytes / 1048576).toFixed(1) + " MB" : "") : ""
                            color: parent._sel ? "#ffffff" : "#b0b0b0"
                            font.pixelSize: 12
                        }

                        Text {
                            visible: modelData.key === "status"
                            anchors { fill: parent; leftMargin: 6 }
                            verticalAlignment: Text.AlignVCenter
                            text: rowRect.item ? (rowRect.item.status === "Downloading" ? (rowRect.item.progress * 100).toFixed(1) + "%" : rowRect.item.status) : ""
                            color: parent._sel ? "#ffffff" : "#b0b0b0"
                            font.pixelSize: 12
                        }

                        Text {
                            visible: modelData.key === "timeleft"
                            anchors { fill: parent; leftMargin: 6 }
                            verticalAlignment: Text.AlignVCenter
                            text: rowRect.item ? (rowRect.item.timeLeft || "") : ""
                            color: parent._sel ? "#ffffff" : "#b0b0b0"
                            font.pixelSize: 12
                        }

                        Text {
                            visible: modelData.key === "speed"
                            anchors { fill: parent; leftMargin: 6 }
                            verticalAlignment: Text.AlignVCenter
                            text: rowRect.item && rowRect.item.status === "Downloading" ? (rowRect.item.speed / 1024).toFixed(1) + " KB/s" : ""
                            color: parent._sel ? "#ffffff" : "#b0b0b0"
                            font.pixelSize: 12
                        }

                        Text {
                            // "Last try date" column — shows lastTryAt if a download was attempted,
                            // otherwise falls back to addedAt (so newly-added items always have a date).
                            visible: modelData.key === "added"
                            anchors { fill: parent; leftMargin: 6 }
                            verticalAlignment: Text.AlignVCenter
                            text: {
                                if (!rowRect.item) return ""
                                const d = (rowRect.item.lastTryAt && rowRect.item.lastTryAt.getTime() > 0)
                                          ? rowRect.item.lastTryAt
                                          : rowRect.item.addedAt
                                return d ? Qt.formatDateTime(d, "MMM dd yyyy HH:mm:ss") : ""
                            }
                            color: parent._sel ? "#ffffff" : "#b0b0b0"
                            font.pixelSize: 11
                        }

                        Text {
                            visible: modelData.key === "lasttry"
                            anchors { fill: parent; leftMargin: 6 }
                            verticalAlignment: Text.AlignVCenter
                            text: rowRect.item && rowRect.item.lastTryAt && rowRect.item.lastTryAt.getTime() > 0 ? Qt.formatDateTime(rowRect.item.lastTryAt, "MMM dd yyyy HH:mm:ss") : "--"
                            color: parent._sel ? "#ffffff" : "#b0b0b0"
                            font.pixelSize: 11
                        }

                        Text {
                            visible: modelData.key === "description"
                            anchors { fill: parent; leftMargin: 6 }
                            verticalAlignment: Text.AlignVCenter
                            text: rowRect.item ? (rowRect.item.description || "--") : "--"
                            color: parent._sel ? "#ffffff" : "#b0b0b0"
                            font.pixelSize: 11
                        }

                        Text {
                            visible: modelData.key === "saveto"
                            anchors { fill: parent; leftMargin: 6 }
                            verticalAlignment: Text.AlignVCenter
                            text: rowRect.item ? (rowRect.item.savePath || "--") : "--"
                            color: parent._sel ? "#ffffff" : "#b0b0b0"
                            font.pixelSize: 11
                        }

                        Text {
                            visible: modelData.key === "referrer"
                            anchors { fill: parent; leftMargin: 6 }
                            verticalAlignment: Text.AlignVCenter
                            text: rowRect.item ? (rowRect.item.referrer || "--") : "--"
                            color: parent._sel ? "#ffffff" : "#b0b0b0"
                            font.pixelSize: 11
                        }

                        Text {
                            visible: modelData.key === "parenturl"
                            anchors { fill: parent; leftMargin: 6 }
                            verticalAlignment: Text.AlignVCenter
                            text: rowRect.item ? (rowRect.item.parentUrl || "--") : "--"
                            color: parent._sel ? "#ffffff" : "#b0b0b0"
                            font.pixelSize: 11
                        }
                    }
                }
            }

            // Progress bar strip at the bottom of each active row
            Rectangle {
                anchors { bottom: parent.bottom; left: parent.left }
                width: rowRect.item ? rowRect.item.progress * rowRect.width : 0
                height: 3
                color: "#4488dd"
                visible: rowRect.item && rowRect.item.status === "Downloading"
            }

            // Bottom row border
            Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: "#2e2e2e" }

            MouseArea {
                id: rowMouse
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                preventStealing: true

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
                            // Collect all selected items for multi-select drag
                            var selectedIds = []
                            for (var idx in root._selectedRows) {
                                var rowIdx = parseInt(idx)
                                var selectedItem = App.downloadModel.itemAt(rowIdx)
                                if (selectedItem) selectedIds.push(selectedItem.id)
                            }
                            // If nothing is selected or the dragged item isn't in selection, use just that item
                            if (selectedIds.length === 0 || !root.isRowSelected(rowRect.rowIndex)) {
                                selectedIds = [rowRect.item.id]
                            }
                            root.categoryDragProxy.dragDownloadIds = selectedIds
                            root.categoryDragProxy.dragDownloadId  = rowRect.item.id
                            root.categoryDragProxy.dragFilename    = selectedIds.length > 1 ? selectedIds.length + " files" : rowRect.item.filename
                            root.categoryDragProxy.visible = true
                        }
                    }
                    if (dragActive && root.categoryDragProxy) {
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
                        root.categoryDragProxy.dragDownloadIds = []
                        root.categoryDragProxy.dragFilename   = ""
                        dragActive = false
                    }
                }

                onClicked: function(mouse) {
                    if (dragActive) return
                    // Return keyboard focus to the ListView so Ctrl+A works immediately
                    // after any click without the user needing a separate focus-click.
                    tableView.forceActiveFocus()
                    if (mouse.button === Qt.RightButton) {
                        // Right-click: select the item if not already selected, then show menu
                        if (!root.isRowSelected(rowRect.rowIndex)) {
                            root._clearAndSelect(rowRect.rowIndex)
                            root._anchorRow = rowRect.rowIndex
                        }
                        rowCtxMenu.popup()
                    } else if (mouse.modifiers & Qt.ControlModifier) {
                        // Ctrl+click: toggle this row in the selection
                        root._toggleRow(rowRect.rowIndex)
                        root._anchorRow = rowRect.rowIndex
                    } else if (mouse.modifiers & Qt.ShiftModifier) {
                        // Shift+click: extend selection from anchor to here
                        if (root._anchorRow >= 0)
                            root._addRangeTo(root._anchorRow, rowRect.rowIndex)
                        else {
                            root._clearAndSelect(rowRect.rowIndex)
                            root._anchorRow = rowRect.rowIndex
                        }
                    } else {
                        // Plain click: single-select
                        root._clearAndSelect(rowRect.rowIndex)
                        root._anchorRow = rowRect.rowIndex
                    }
                }

                onDoubleClicked: function(mouse) {
                    if (!rowRect.item) return
                    // Always open file properties on double-click regardless of status.
                    // The dialog shows live status (Downloading, Paused, % progress, etc.).
                    root.openPropertiesRequested(rowRect.item)
                }
            }

            Menu {
                id: rowCtxMenu
                Action {
                    text: "Properties"
                    onTriggered: {
                        if (!rowRect.item) return
                        root.openPropertiesRequested(rowRect.item)
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

                // Clears the queue assignment for all currently selected downloads.
                Action {
                    text: "Remove from Queue"
                    onTriggered: {
                        for (var row in root._selectedRows) {
                            var it = App.downloadModel.data(
                                App.downloadModel.index(parseInt(row), 0), Qt.UserRole + 2)
                            if (it) App.setDownloadQueue(it.id, "")
                        }
                    }
                }

                MenuSeparator {}
                Action { text: "Redownload"; onTriggered: { if (rowRect.item) App.redownload(rowRect.item.id) } }
                Action { text: "Delete";    onTriggered: { if (rowRect.item) root._openDeleteDialog(rowRect.item) } }
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
