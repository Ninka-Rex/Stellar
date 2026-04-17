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
    signal exportTorrentsRequested(var downloadIds)

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
    readonly property int selectedTorrentCountValue: {
        _selectionVersion
        var count = 0
        for (var row in _selectedRows) {
            var item = App.downloadModel.data(App.downloadModel.index(parseInt(row), 0), Qt.UserRole + 2)
            if (item && item.isTorrent)
                count++
        }
        return count
    }
    readonly property bool anyTorrentSelected: selectedTorrentCountValue > 0

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
            if (item && (item.status === "Downloading" || item.status === "Queued" || item.status === "Seeding")) return true
        }
        return false
    }

    // Kept for backward compatibility with any callers; internally delegates to reactive props.
    function anySelectedHasStatus(status) {
        if (status === "Paused")                             return anyPausedSelected
        if (status === "Downloading" || status === "Queued" || status === "Seeding") return anyActiveSelected
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
            var ids = []
            var fileExists = false
            var hasTorrentSelection = false
            for (var i = 0; i < rows.length; i++) {
                var it = App.downloadModel.data(App.downloadModel.index(parseInt(rows[i]), 0), Qt.UserRole + 2)
                if (!it) continue
                ids.push(it.id)
                if (it.isTorrent)
                    hasTorrentSelection = true
                if (it.status === "Completed")
                    fileExists = true
            }
            if (ids.length > 0) {
                _openDeleteDialog(null, ids, fileExists, hasTorrentSelection)
                _setSelection({})
                _anchorRow = -1
            }
        }
    }
    function _selectedItem() {
        if (_anchorRow < 0) return null
        return App.downloadModel.data(
            App.downloadModel.index(_anchorRow, 0), Qt.UserRole + 2)
    }
    function _selectedItems() {
        _selectionVersion
        var items = []
        for (var row in _selectedRows) {
            var item = App.downloadModel.data(App.downloadModel.index(parseInt(row), 0), Qt.UserRole + 2)
            if (item)
                items.push(item)
        }
        return items
    }
    function selectedTorrentIds() {
        var ids = []
        var items = _selectedItems()
        for (var i = 0; i < items.length; ++i) {
            if (items[i].isTorrent)
                ids.push(items[i].id)
        }
        return ids
    }
    function selectedTorrentCount() {
        return selectedTorrentCountValue
    }
    function hasAnyTorrentSelected() {
        return anyTorrentSelected
    }
    function copySelectedShareLinks() {
        var items = _selectedItems()
        if (items.length === 0 && _ctxItem)
            items = [_ctxItem]
        var links = []
        for (var i = 0; i < items.length; ++i) {
            var link = App.downloadShareLink(items[i].id)
            if (link && link.length > 0)
                links.push(link)
        }
        if (links.length > 0)
            App.copyToClipboard(links.join("\n"))
    }
    function requestExportSelectedTorrents() {
        var ids = selectedTorrentIds()
        if (ids.length > 0)
            exportTorrentsRequested(ids)
    }
    function _selectedId() {
        const item = _selectedItem()
        return item ? item.id : null
    }
    function _openDeleteDialog(item, ids, fileExists, hasTorrentSelection) {
        var torrentSelected = !!hasTorrentSelection
        if (!torrentSelected && item)
            torrentSelected = !!item.isTorrent
        deleteDialog.downloadId = item ? item.id : ""
        deleteDialog.downloadIds = ids || (item ? [item.id] : [])
        deleteDialog.filename   = item ? item.filename : (deleteDialog.downloadIds.length > 1 ? deleteDialog.downloadIds.length + " selected downloads" : "")
        deleteDialog.fileExists = typeof fileExists === "boolean"
                                 ? fileExists
                                 : (item && item.status === "Completed")
        deleteDialog.hasTorrentSelection = torrentSelected
        deleteDialog.show()
        deleteDialog.raise()
        deleteDialog.requestActivate()
    }

    // ── Delete confirmation dialog ────────────────────────────────────────────
    DeleteConfirmDialog {
        id: deleteDialog
        property var downloadIds: []
        onConfirmed: (mode) => {
            if (downloadIds && downloadIds.length > 1) {
                App.deleteDownloads(downloadIds, mode)
            } else if (downloadId.length > 0) {
                App.deleteDownload(downloadId, mode)
            }
        }
    }

    // The item that was right-clicked — set by the row MouseArea before showing the
    // shared context menu. Avoids creating one Menu+Repeater per delegate row.
    property var _ctxItem: null

    // Single shared context menu for all rows. Previously each delegate had its own
    // Menu containing a Repeater over App.queueModel — that created K*N QQmlContexts
    // (queues × rows) which was the O(N) scaling bottleneck on category switch.
    Menu {
        id: rowCtxMenu
        Action {
            text: "Properties"
            onTriggered: { if (root._ctxItem) root.openPropertiesRequested(root._ctxItem) }
        }
        Action { text: "Open File";   onTriggered: { if (root._ctxItem) App.openFile(root._ctxItem.id) } }
        Action { text: "Open Folder"; onTriggered: { if (root._ctxItem) App.openFolderSelectFile(root._ctxItem.id) } }
        MenuSeparator {}
        Action { text: "Copy Filename"; onTriggered: { if (root._ctxItem) App.copyDownloadFilename(root._ctxItem.id) } }
        Action {
            text: root._ctxItem && root._ctxItem.isTorrent ? "Copy Magnet Link" : "Copy URL"
            onTriggered: root.copySelectedShareLinks()
        }
        Repeater {
            model: (!!root._ctxItem && !!root._ctxItem.isTorrent) ? 1 : 0
            delegate: MenuItem {
                text: "Export .torrent…"
                enabled: root.anyTorrentSelected
                onTriggered: root.requestExportSelectedTorrents()
            }
        }
        MenuSeparator {}
        Action { text: "Resume"; onTriggered: root.resumeSelected() }
        Action { text: "Stop";   onTriggered: root.stopSelected()   }
        MenuSeparator {}
        Menu {
            title: "Move to Queue"
            Repeater {
                model: App.queueModel
                delegate: MenuItem {
                    visible: queueId !== "download-limits"
                    text: queueName || ""
                    onTriggered: { if (root._ctxItem) App.setDownloadQueue(root._ctxItem.id, queueId) }
                }
            }
        }
        Action {
            text: "Remove from Queue"
            onTriggered: {
                for (var row in root._selectedRows) {
                    var it = App.downloadModel.data(App.downloadModel.index(parseInt(row), 0), Qt.UserRole + 2)
                    if (it) App.setDownloadQueue(it.id, "")
                }
            }
        }
        MenuSeparator {}
        Action { text: "Redownload"; onTriggered: { if (root._ctxItem) App.redownload(root._ctxItem.id) } }
        Action { text: "Delete";     onTriggered: { if (root._ctxItem) root._openDeleteDialog(root._ctxItem) } }
    }

    // Bump _selectionVersion only when a SELECTED row's data changes so toolbar
    // enabled-states (anyPausedSelected, anyActiveSelected) stay accurate after
    // stop/resume. Firing on every dataChanged (speed, progress, bytes) caused
    // O(rows × cols) JS re-evaluations on every progress tick — major CPU churn.
    Connections {
        target: App.downloadModel
        function onDataChanged(topLeft, bottomRight, roles) {
            const lo = topLeft.row, hi = bottomRight.row
            for (var r = lo; r <= hi; r++) {
                if (root._selectedRows[r]) {
                    root._selectionVersion++
                    return
                }
            }
        }
    }

    // Default column definitions
    readonly property var _defaultColumnDefs: [
        { title: "Q",              key: "queue",      widthPx: 31,  visible: true  },
        { title: "File Name",      key: "name",       widthPx: 240, visible: true  },
        { title: "Size",           key: "size",       widthPx: 80,  visible: true  },
        { title: "Status",         key: "status",     widthPx: 90,  visible: true  },
        { title: "Time left",      key: "timeleft",   widthPx: 90,  visible: true  },
        { title: "Down Speed",     key: "downspeed",  widthPx: 90,  visible: true  },
        { title: "Up Speed",       key: "upspeed",    widthPx: 90,  visible: true  },
        { title: "Seeders",        key: "seeders",    widthPx: 70,  visible: false },
        { title: "Peers",          key: "peers",      widthPx: 70,  visible: false },
        { title: "Ratio",          key: "ratio",      widthPx: 70,  visible: false },
        { title: "Uploaded",       key: "uploaded",   widthPx: 90,  visible: false },
        { title: "Downloaded",     key: "downloaded", widthPx: 90,  visible: false },
        { title: "Last try date",  key: "added",      widthPx: 130, visible: true  },
        { title: "Last try date",  key: "lasttry",    widthPx: 110, visible: false },
        { title: "Description",    key: "description",widthPx: 120, visible: false },
        { title: "Save to",        key: "saveto",     widthPx: 140, visible: false },
        { title: "Referer",        key: "referrer",   widthPx: 140, visible: false },
        { title: "Parent web page",key: "parenturl",  widthPx: 140, visible: false },
    ]

    // Column definitions — visibility toggled from context menu / ColumnsDialog
    property bool _suppressColumnDefsSave: true

    function _cloneDefaultColumnDefs() {
        var defs = []
        for (var i = 0; i < _defaultColumnDefs.length; i++)
            defs.push(Object.assign({}, _defaultColumnDefs[i]))
        return defs
    }

    function _normalizeColumnDefs(defs) {
        var normalized = []
        var defaultsByKey = {}
        var seen = {}

        for (var i = 0; i < _defaultColumnDefs.length; i++)
            defaultsByKey[_defaultColumnDefs[i].key] = _defaultColumnDefs[i]

        if (defs && defs.length) {
            for (var j = 0; j < defs.length; j++) {
                var saved = defs[j]
                if (saved && saved.key === "speed")
                    saved.key = "downspeed"
                if (!saved || !saved.key || seen[saved.key] || !defaultsByKey[saved.key])
                    continue

                var base = defaultsByKey[saved.key]
                normalized.push({
                    title: base.title,
                    key: base.key,
                    widthPx: Math.max(minColWidth(base.key), Math.round(Number(saved.widthPx) || base.widthPx)),
                    visible: saved.visible !== undefined ? !!saved.visible : base.visible
                })
                seen[saved.key] = true
            }
        }

        for (var k = 0; k < _defaultColumnDefs.length; k++) {
            var def = _defaultColumnDefs[k]
            if (seen[def.key])
                continue
            normalized.push({
                title: def.title,
                key: def.key,
                widthPx: Math.max(minColWidth(def.key), def.widthPx),
                visible: def.visible
            })
        }

        return normalized
    }

    function _initialColumnDefs() {
        var saved = App.settings.downloadTableColumns
        if (!saved || saved.length === 0)
            return _normalizeColumnDefs(_cloneDefaultColumnDefs())

        try {
            return _normalizeColumnDefs(JSON.parse(saved))
        } catch (e) {
            console.warn("Failed to parse saved download table columns:", e)
            return _normalizeColumnDefs(_cloneDefaultColumnDefs())
        }
    }

    function _saveColumnDefs() {
        if (_suppressColumnDefsSave)
            return
        var serialized = JSON.stringify(columnDefs)
        if (App.settings.downloadTableColumns !== serialized)
            App.settings.downloadTableColumns = serialized
    }

    property var columnDefs: _initialColumnDefs()

    function resetColumns() { columnDefs = _normalizeColumnDefs(_cloneDefaultColumnDefs()) }

    // Compute visible columns only
    function makeVisibleCols() {
        var r = []
        for (var i = 0; i < columnDefs.length; i++)
            if (columnDefs[i].visible) r.push(columnDefs[i])
        return r
    }
    property var visibleCols: makeVisibleCols()
    onColumnDefsChanged: {
        visibleCols = makeVisibleCols()
        visibleContentWidth = totalVisibleWidth()
        _saveColumnDefs()
    }

    // Fast column visibility lookup used by fixed-column delegate rows.
    // Avoids the Repeater's per-slot QQmlContext overhead.
    function _colVisible(key) {
        for (var i = 0; i < columnDefs.length; i++)
            if (columnDefs[i].key === key) return columnDefs[i].visible
        return false
    }

    function colWidth(key) {
        if (_resizingColumnKey === key)
            return _resizingColumnWidth
        for (var i = 0; i < columnDefs.length; i++) {
            if (columnDefs[i].key === key)
                return columnDefs[i].widthPx || 100
        }
        return 0
    }

    function totalVisibleWidth() {
        var total = 0
        for (var i = 0; i < visibleCols.length; i++)
            total += colWidth(visibleCols[i].key)
        return total
    }

    function minColWidth(key) {
        if (key === "queue")
            return 31
        return 24
    }

    function formatBytesShort(bytes) {
        if (!bytes || bytes <= 0)
            return ""
        if (bytes >= 1073741824) return (bytes / 1073741824).toFixed(2) + " GB"
        if (bytes >= 1048576) return (bytes / 1048576).toFixed(1) + " MB"
        if (bytes >= 1024) return (bytes / 1024).toFixed(1) + " KB"
        return bytes + " B"
    }

    property real visibleContentWidth: totalVisibleWidth()
    onVisibleColsChanged: visibleContentWidth = totalVisibleWidth()

    // Keep live drag state outside the repeater delegates so resizing does not
    // recreate the header cell mid-drag.
    property string _resizingColumnKey: ""
    property real _resizingColumnWidth: 0

    // Maps column key → x offset in the row. Recomputed whenever visibleContentWidth
    // changes (resize, reorder, visibility toggle all flow through it).
    property var _colXMap: {
        visibleContentWidth   // reactive dependency
        return _buildColXMap()
    }
    function _buildColXMap() {
        var map = {}
        var x = 0
        for (var i = 0; i < visibleCols.length; i++) {
            var col = visibleCols[i]
            map[col.key] = x
            x += colWidth(col.key)
        }
        return map
    }

    // Column reorder drag state
    property string _colDragFromKey:          ""
    property string _colDragInsertBeforeKey:  ""
    property bool   _colDragging:             false

    function _applyColReorder() {
        if (!_colDragFromKey) return
        var defs = columnDefs.slice()
        var fromIdx = -1
        for (var i = 0; i < defs.length; i++) { if (defs[i].key === _colDragFromKey) { fromIdx = i; break } }
        if (fromIdx < 0) return
        var toIdx
        if (_colDragInsertBeforeKey === "__end__") {
            toIdx = defs.length
        } else {
            toIdx = -1
            for (var j = 0; j < defs.length; j++) { if (defs[j].key === _colDragInsertBeforeKey) { toIdx = j; break } }
        }
        if (toIdx < 0 || toIdx === fromIdx) return
        var moved = defs.splice(fromIdx, 1)[0]
        if (toIdx > fromIdx) toIdx--
        defs.splice(toIdx, 0, moved)
        columnDefs = defs
    }

    Component.onCompleted: {
        _suppressColumnDefsSave = false
        // Keep model ordering in sync with the visible sort indicator at startup.
        App.downloadModel.sortBy(sortKey, sortAscending)
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

    function itemMatchesActiveFilter(item) {
        return filterText.length === 0
            || _itemMatchesFind(item, filterText, filterName, filterDesc,
                                filterLinks, filterMatchCase, filterMatchWhole)
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
    readonly property var _sortableKeys: ["name","size","status","timeleft","downspeed","upspeed","seeders","peers","ratio","uploaded","downloaded","added","lasttry","description","saveto","referrer","parenturl","queue"]

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
        clip: true

        Row {
            id: headerRow
            x: -tableView.contentX
            width: root.visibleContentWidth
            height: parent.height

            Repeater {
                id: headerCellRepeater
                model: root.visibleCols
                delegate: Rectangle {
                    id: headerCell
                    width:  root.colWidth(modelData.key)
                    height: parent.height
                    readonly property bool isSortable: root._sortableKeys.indexOf(modelData.key) >= 0
                    readonly property bool isActive:   root.sortKey === modelData.key
                    color: (isSortable && headerCellMouse.containsMouse && !root._colDragging) ? "#383838" : "transparent"
                    opacity: (root._colDragging && root._colDragFromKey === modelData.key) ? 0.5 : 1.0

                    // Drop insert-line: shown to the LEFT of this column when it's the insert target
                    Rectangle {
                        visible: root._colDragging && root._colDragInsertBeforeKey === modelData.key
                        width: 2; height: parent.height
                        anchors.left: parent.left
                        color: "#4488dd"
                        z: 20
                    }

                    // Insert-line at the very END of the header (shown on last visible col's right edge)
                    Rectangle {
                        visible: root._colDragging
                              && root._colDragInsertBeforeKey === "__end__"
                              && index === headerCellRepeater.count - 1
                        width: 2; height: parent.height
                        anchors.right: parent.right
                        color: "#4488dd"
                        z: 20
                    }

                    Text {
                        anchors {
                            verticalCenter: parent.verticalCenter
                            left: parent.left
                            leftMargin: modelData.key === "queue" ? 0 : 6
                            right: modelData.key === "queue" ? parent.right : sortIndicator.left
                            rightMargin: modelData.key === "queue" ? resizeHandle.width : 2
                        }
                        text: modelData.title
                        color: headerCell.isActive ? "#88bbff" : "#b0b0b0"
                        font.pixelSize: 12
                        font.bold: true
                        horizontalAlignment: modelData.key === "queue" ? Text.AlignHCenter : Text.AlignLeft
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
                        anchors { fill: parent; rightMargin: 10 }
                        hoverEnabled: true
                        preventStealing: true
                        cursorShape: root._colDragging ? Qt.ClosedHandCursor
                                   : (headerCell.isSortable ? Qt.PointingHandCursor : Qt.ArrowCursor)

                        property real _pressX:  0
                        property bool _didDrag: false

                        onPressed:  { _pressX = mouseX; _didDrag = false }

                        onPositionChanged: {
                            if (!(pressedButtons & Qt.LeftButton)) return
                            if (!root._colDragging && Math.abs(mouseX - _pressX) > 8) {
                                root._colDragFromKey = modelData.key
                                root._colDragging = true
                                _didDrag = true
                            }
                            if (root._colDragging && root._colDragFromKey === modelData.key) {
                                // Map cursor X to the header Row's coordinate space (accounts for scroll)
                                var cursorX = headerCellMouse.mapToItem(headerRow, mouseX, 0).x
                                var insertBefore = "__end__"
                                var xAcc = 0
                                for (var i = 0; i < root.visibleCols.length; i++) {
                                    var colW = root.colWidth(root.visibleCols[i].key)
                                    if (cursorX < xAcc + colW / 2) {
                                        insertBefore = root.visibleCols[i].key
                                        break
                                    }
                                    xAcc += colW
                                }
                                root._colDragInsertBeforeKey = insertBefore
                            }
                        }

                        onReleased: {
                            var didDrag = _didDrag
                            var rootRef = root

                            Qt.callLater(function() {
                                if (didDrag) rootRef._applyColReorder()
                                rootRef._colDragging = false
                                rootRef._colDragFromKey = ""
                                rootRef._colDragInsertBeforeKey = ""
                            })

                            _didDrag = false
                            _pressX = 0
                        }

                        onClicked: {
                            if (!_didDrag && headerCell.isSortable) root.applySort(modelData.key)
                            _didDrag = false
                        }
                    }

                    Rectangle {
                        anchors.right: parent.right
                        width: 1; height: parent.height
                        color: "#3a3a3a"
                    }

                    // ── Column resize handle ──────────────────────────────
                    Item {
                        id: resizeHandle
                        width: 10
                        height: parent.height
                        anchors.right: parent.right
                        z: 10

                        property real _startWidthPx: 0

                        Rectangle {
                            anchors.right: parent.right
                            width: 2
                            height: parent.height
                            color: (resizeDrag.active || resizeHover.hovered) ? "#6aa0ff" : "transparent"
                            opacity: resizeDrag.active ? 1.0 : 0.75
                        }

                        HoverHandler {
                            id: resizeHover
                            cursorShape: Qt.SizeHorCursor
                        }

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
                                    for (var j = 0; j < defs.length; j++) {
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
                                root._resizingColumnWidth = Math.max(root.minColWidth(modelData.key), Math.round(resizeHandle._startWidthPx + translation.x))
                                root.visibleContentWidth = root.totalVisibleWidth()
                            }
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
        contentWidth: root.visibleContentWidth
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
                for (var i = 0; i < App.downloadModel.rowCount(); i++) {
                    var item = App.downloadModel.data(App.downloadModel.index(i, 0), Qt.UserRole + 2)
                    if (root.itemMatchesActiveFilter(item))
                        r[i] = true
                }
                root._setSelection(r)
                root._anchorRow = Object.keys(r).length > 0 ? parseInt(Object.keys(r).pop()) : -1
                e.accepted = true
            }
        }

        ScrollBar.vertical: ScrollBar {}
        ScrollBar.horizontal: ScrollBar {}

        delegate: Rectangle {
            id: rowRect
            width: root.visibleContentWidth
            visible: root.itemMatchesActiveFilter(item)
            height: visible ? 26 : 0

            readonly property var item: model.item
            readonly property int rowIndex: index

            readonly property string addedDateStr:   item ? item.addedDateStr   : ""
            readonly property string lastTryDateStr: item ? item.lastTryDateStr : "--"

            // Shared selection state — read once per row, referenced by each column cell.
            // All cells share this property rather than each computing their own binding
            // against _selectionVersion, keeping the binding fan-out flat.
            readonly property bool _sel: { root._selectionVersion; return root.isRowSelected(rowIndex) }

            ListView.onReused: rowMouse.dragActive = false

            color: {
                root._selectionVersion
                if (root.isRowSelected(rowIndex)) return "#1e3a6e"
                if (rowMouse.containsMouse)        return "#2a2a2a"
                return rowIndex % 2 === 0 ? "#1c1c1c" : "#222222"
            }

            clip: true

            // Fixed column layout — NO Repeater. The Repeater created one QQmlContext per
            // column slot per row (~7 contexts × 20 rows = 140 contexts, each ~10ms = 1400ms).
            // Hardcoded Items have zero per-slot context overhead; visibility and width are
            // just property bindings on pre-existing objects.
            // Each cell uses explicit x from _colXMap so column order always matches the
            // header regardless of how the user has reordered columnDefs.
            Item {
                anchors { top: parent.top; left: parent.left; right: parent.right; bottom: parent.bottom }

                // ── Queue ─────────────────────────────────────────────────────
                Item {
                    visible: root._colVisible("queue")
                    x:       root._colXMap["queue"] || 0
                    width:   root.colWidth("queue")
                    height:  rowRect.height - 1
                    clip: true
                    Image {
                        visible: rowRect.item && rowRect.item.queueId && rowRect.item.queueId.length > 0
                        anchors.centerIn: parent
                        source: {
                            const q = rowRect.item ? rowRect.item.queueId : ""
                            if (q === "main-download") return "qrc:/qt/qml/com/stellar/app/app/qml/icons/main_queue.png"
                            if (q === "main-sync")     return "qrc:/qt/qml/com/stellar/app/app/qml/icons/synch_queue.png"
                            return "qrc:/qt/qml/com/stellar/app/app/qml/icons/custom_queue.png"
                        }
                        width: 14; height: 14
                        sourceSize: Qt.size(14, 14)
                        fillMode: Image.PreserveAspectFit
                        ToolTip.visible: queueIconMouse.containsMouse
                        ToolTip.text: {
                            const qid = rowRect.item ? rowRect.item.queueId : ""
                            if (!qid) return ""
                            for (var i = 0; i < App.queueModel.rowCount(); i++) {
                                var queueId = App.queueModel.data(App.queueModel.index(i, 0), 34)
                                if (queueId === qid)
                                    return App.queueModel.data(App.queueModel.index(i, 0), 35) || qid
                            }
                            return qid
                        }
                        MouseArea { id: queueIconMouse; anchors.fill: parent; hoverEnabled: true }
                    }
                }

                // ── File Name ─────────────────────────────────────────────────
                Item {
                    visible: root._colVisible("name")
                    x:       root._colXMap["name"] || 0
                    width:   root.colWidth("name")
                    height:  rowRect.height - 1
                    clip: true
                    Row {
                        anchors { verticalCenter: parent.verticalCenter; left: parent.left; leftMargin: 6 }
                        spacing: 6
                        width: parent.width - 12
                        Image {
                            width: 18; height: 18
                            anchors.verticalCenter: parent.verticalCenter
                            source: {
                                if (!rowRect.item)
                                    return ""
                                var basePath = (rowRect.item.savePath + "/" + rowRect.item.filename).replace(/\\/g, "/")
                                if (rowRect.item.isTorrent && !rowRect.item.torrentIsSingleFile)
                                    basePath += "/"
                                return "image://fileicon/" + basePath + (rowRect.item.status === "Completed" ? "?c=1" : "")
                            }
                            sourceSize: Qt.size(18, 18)
                            fillMode: Image.PreserveAspectFit
                            asynchronous: true
                        }
                        Text {
                            text: rowRect.item ? rowRect.item.filename : ""
                            color: rowRect._sel ? "#ffffff" : "#d0d0d0"
                            font.pixelSize: 12
                            width: parent.parent.width - 42
                            elide: Text.ElideMiddle
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }
                }

                // ── Size ──────────────────────────────────────────────────────
                Item {
                    visible: root._colVisible("size")
                    x:       root._colXMap["size"] || 0
                    width:   root.colWidth("size")
                    height:  rowRect.height - 1
                    clip: true
                    Text {
                        anchors { fill: parent; leftMargin: 6 }
                        verticalAlignment: Text.AlignVCenter
                        text: rowRect.item ? formatBytesShort(rowRect.item.totalBytes) : ""
                        color: rowRect._sel ? "#ffffff" : "#b0b0b0"
                        font.pixelSize: 12
                    }
                }

                // ── Status / Progress ─────────────────────────────────────────
                Item {
                    visible: root._colVisible("status")
                    x:       root._colXMap["status"] || 0
                    width:   root.colWidth("status")
                    height:  rowRect.height - 1
                    clip: true
                    Text {
                        anchors { fill: parent; leftMargin: 6 }
                        verticalAlignment: Text.AlignVCenter
                        text: {
                            if (!rowRect.item) return ""
                            if (rowRect.item.isTorrent && !rowRect.item.torrentHasMetadata)
                                return "Pending"
                            if (rowRect.item.status === "Downloading")
                                return (rowRect.item.progress * 100).toFixed(1) + "%"
                            if (rowRect.item.status === "Paused" && rowRect.item.progress > 0)
                                return (rowRect.item.progress * 100).toFixed(1) + "% (Stopped)"
                            return rowRect.item.status
                        }
                        color: rowRect._sel ? "#ffffff" : "#b0b0b0"
                        font.pixelSize: 12
                    }
                }

                // ── Time Left ─────────────────────────────────────────────────
                Item {
                    visible: root._colVisible("timeleft")
                    x:       root._colXMap["timeleft"] || 0
                    width:   root.colWidth("timeleft")
                    height:  rowRect.height - 1
                    clip: true
                    Text {
                        anchors { fill: parent; leftMargin: 6 }
                        verticalAlignment: Text.AlignVCenter
                        text: rowRect.item ? (rowRect.item.timeLeft || "") : ""
                        color: rowRect._sel ? "#ffffff" : "#b0b0b0"
                        font.pixelSize: 12
                    }
                }

                // ── Down Speed ─────────────────────────────────────────────
                Item {
                    visible: root._colVisible("downspeed")
                    x:       root._colXMap["downspeed"] || 0
                    width:   root.colWidth("downspeed")
                    height:  rowRect.height - 1
                    clip: true
                    Text {
                        anchors { fill: parent; leftMargin: 6 }
                        verticalAlignment: Text.AlignVCenter
                        text: {
                            if (!rowRect.item) return ""
                            // Show download speed for both regular and torrent downloads
                            var st = rowRect.item.status
                            if (st !== "Downloading" && st !== "Seeding") return ""
                            var bps = rowRect.item.speed
                            if (bps <= 0) return ""
                            if (bps >= 1073741824) return (bps / 1073741824).toFixed(2) + " GB/s"
                            if (bps >= 1048576)    return (bps / 1048576).toFixed(2) + " MB/s"
                            if (bps >= 1024)       return (bps / 1024).toFixed(1) + " KB/s"
                            return bps + " B/s"
                        }
                        color: rowRect._sel ? "#ffffff" : "#b0b0b0"
                        font.pixelSize: 12
                    }
                }

                // ── Up Speed ─────────────────────────────────────────────
                Item {
                    visible: root._colVisible("upspeed")
                    x:       root._colXMap["upspeed"] || 0
                    width:   root.colWidth("upspeed")
                    height:  rowRect.height - 1
                    clip: true
                    Text {
                        anchors { fill: parent; leftMargin: 6 }
                        verticalAlignment: Text.AlignVCenter
                        text: {
                            if (!rowRect.item || !rowRect.item.isTorrent) return ""
                            if (rowRect.item.status !== "Downloading" && rowRect.item.status !== "Seeding") return ""
                            var bps = rowRect.item.torrentUploadSpeed
                            if (bps >= 1073741824) return (bps / 1073741824).toFixed(2) + " GB/s"
                            if (bps >= 1048576)    return (bps / 1048576).toFixed(2) + " MB/s"
                            if (bps >= 1024)       return (bps / 1024).toFixed(1) + " KB/s"
                            return bps > 0 ? (bps + " B/s") : ""
                        }
                        color: rowRect._sel ? "#ffffff" : "#b0b0b0"
                        font.pixelSize: 12
                    }
                }

                // ── Seeders ───────────────────────────────────────────────────
                Item {
                    visible: root._colVisible("seeders")
                    x:       root._colXMap["seeders"] || 0
                    width:   root.colWidth("seeders")
                    height:  rowRect.height - 1
                    clip: true
                    Text {
                        anchors { fill: parent; leftMargin: 6 }
                        verticalAlignment: Text.AlignVCenter
                        text: {
                            if (!rowRect.item || !rowRect.item.isTorrent) return ""
                            return rowRect.item.torrentSeeders + " (" + rowRect.item.torrentListSeeders + ")"
                        }
                        color: rowRect._sel ? "#ffffff" : "#b0b0b0"
                        font.pixelSize: 12
                    }
                }

                Item {
                    visible: root._colVisible("peers")
                    x:       root._colXMap["peers"] || 0
                    width:   root.colWidth("peers")
                    height:  rowRect.height - 1
                    clip: true
                    Text {
                        anchors { fill: parent; leftMargin: 6 }
                        verticalAlignment: Text.AlignVCenter
                        text: {
                            if (!rowRect.item || !rowRect.item.isTorrent) return ""
                            return rowRect.item.torrentPeers + " (" + rowRect.item.torrentListPeers + ")"
                        }
                        color: rowRect._sel ? "#ffffff" : "#b0b0b0"
                        font.pixelSize: 12
                    }
                }

                Item {
                    visible: root._colVisible("ratio")
                    x:       root._colXMap["ratio"] || 0
                    width:   root.colWidth("ratio")
                    height:  rowRect.height - 1
                    clip: true
                    Text {
                        anchors { fill: parent; leftMargin: 6 }
                        verticalAlignment: Text.AlignVCenter
                        text: rowRect.item && rowRect.item.isTorrent ? rowRect.item.torrentRatio.toFixed(2) : ""
                        color: rowRect._sel ? "#ffffff" : "#b0b0b0"
                        font.pixelSize: 12
                    }
                }

                Item {
                    visible: root._colVisible("uploaded")
                    x:       root._colXMap["uploaded"] || 0
                    width:   root.colWidth("uploaded")
                    height:  rowRect.height - 1
                    clip: true
                    Text {
                        anchors { fill: parent; leftMargin: 6 }
                        verticalAlignment: Text.AlignVCenter
                        text: rowRect.item && rowRect.item.isTorrent ? root.formatBytesShort(rowRect.item.torrentUploaded) : ""
                        color: rowRect._sel ? "#ffffff" : "#b0b0b0"
                        font.pixelSize: 12
                    }
                }

                Item {
                    visible: root._colVisible("downloaded")
                    x:       root._colXMap["downloaded"] || 0
                    width:   root.colWidth("downloaded")
                    height:  rowRect.height - 1
                    clip: true
                    Text {
                        anchors { fill: parent; leftMargin: 6 }
                        verticalAlignment: Text.AlignVCenter
                        text: rowRect.item && rowRect.item.isTorrent ? root.formatBytesShort(rowRect.item.torrentDownloaded) : ""
                        color: rowRect._sel ? "#ffffff" : "#b0b0b0"
                        font.pixelSize: 12
                    }
                }

                // ── Last Try Date ─────────────────────────────────────────────
                Item {
                    visible: root._colVisible("added")
                    x:       root._colXMap["added"] || 0
                    width:   root.colWidth("added")
                    height:  rowRect.height - 1
                    clip: true
                    Text {
                        anchors { fill: parent; leftMargin: 6 }
                        verticalAlignment: Text.AlignVCenter
                        text: rowRect.addedDateStr
                        color: rowRect._sel ? "#ffffff" : "#b0b0b0"
                        font.pixelSize: 11
                    }
                }

                // ── Last Try Date (alt column) ────────────────────────────────
                Item {
                    visible: root._colVisible("lasttry")
                    x:       root._colXMap["lasttry"] || 0
                    width:   root.colWidth("lasttry")
                    height:  rowRect.height - 1
                    clip: true
                    Text {
                        anchors { fill: parent; leftMargin: 6 }
                        verticalAlignment: Text.AlignVCenter
                        text: rowRect.lastTryDateStr
                        color: rowRect._sel ? "#ffffff" : "#b0b0b0"
                        font.pixelSize: 11
                    }
                }

                // ── Description ───────────────────────────────────────────────
                Item {
                    visible: root._colVisible("description")
                    x:       root._colXMap["description"] || 0
                    width:   root.colWidth("description")
                    height:  rowRect.height - 1
                    clip: true
                    Text {
                        anchors { fill: parent; leftMargin: 6 }
                        verticalAlignment: Text.AlignVCenter
                        text: rowRect.item ? (rowRect.item.description || "--") : "--"
                        color: rowRect._sel ? "#ffffff" : "#b0b0b0"
                        font.pixelSize: 11
                    }
                }

                // ── Save To ───────────────────────────────────────────────────
                Item {
                    visible: root._colVisible("saveto")
                    x:       root._colXMap["saveto"] || 0
                    width:   root.colWidth("saveto")
                    height:  rowRect.height - 1
                    clip: true
                    Text {
                        anchors { fill: parent; leftMargin: 6 }
                        verticalAlignment: Text.AlignVCenter
                        text: rowRect.item ? (rowRect.item.savePath || "--") : "--"
                        color: rowRect._sel ? "#ffffff" : "#b0b0b0"
                        font.pixelSize: 11
                    }
                }

                // ── Referrer ──────────────────────────────────────────────────
                Item {
                    visible: root._colVisible("referrer")
                    x:       root._colXMap["referrer"] || 0
                    width:   root.colWidth("referrer")
                    height:  rowRect.height - 1
                    clip: true
                    Text {
                        anchors { fill: parent; leftMargin: 6 }
                        verticalAlignment: Text.AlignVCenter
                        text: rowRect.item ? (rowRect.item.referrer || "--") : "--"
                        color: rowRect._sel ? "#ffffff" : "#b0b0b0"
                        font.pixelSize: 11
                    }
                }

                // ── Parent URL ────────────────────────────────────────────────
                Item {
                    visible: root._colVisible("parenturl")
                    x:       root._colXMap["parenturl","queue"] || 0
                    width:   root.colWidth("parenturl")
                    height:  rowRect.height - 1
                    clip: true
                    Text {
                        anchors { fill: parent; leftMargin: 6 }
                        verticalAlignment: Text.AlignVCenter
                        text: rowRect.item ? (rowRect.item.parentUrl || "--") : "--"
                        color: rowRect._sel ? "#ffffff" : "#b0b0b0"
                        font.pixelSize: 11
                    }
                }
            } // Item (column layout)

            // Progress bar strip at the bottom of each active row
            Rectangle {
                anchors { bottom: parent.bottom; left: parent.left; bottomMargin: 1 }
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
                        root._ctxItem = rowRect.item
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
                    if (rowRect.item.isTorrent) {
                        root.openPropertiesRequested(rowRect.item)
                        return
                    }
                    if (rowRect.item.status === "Downloading" || rowRect.item.status === "Assembling") {
                        root.openProgressRequested(rowRect.item)
                        return
                    }
                    // Dispatch based on the user's double-click action preference.
                    // 0 = Open file properties dialog (default)
                    // 1 = Open file directly
                    // 2 = Open containing folder with the file selected
                    var action = App.settings.doubleClickAction
                    if (action === 1) {
                        App.openFile(rowRect.item.id)
                    } else if (action === 2) {
                        App.openFolderSelectFile(rowRect.item.id)
                    } else {
                        root.openPropertiesRequested(rowRect.item)
                    }
                }
            }

        }

        // empty state
        Text {
            anchors.centerIn: parent
            readonly property bool searchActive: root.filterText.length > 0
            readonly property int filteredCount: searchActive
                ? root.countMatches(root.filterText, root.filterName, root.filterDesc,
                                    root.filterLinks, root.filterMatchCase, root.filterMatchWhole)
                : tableView.count
            visible: filteredCount === 0
            text: searchActive ? "No matching downloads."
                               : "No downloads yet.\nClick  Add URL  to start."
            horizontalAlignment: Text.AlignHCenter
            color: "#444444"
            font.pixelSize: 14
            lineHeight: 1.6
        }
    }
}
