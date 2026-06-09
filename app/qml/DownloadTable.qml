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
    color: ColorPalette.windowBg

    signal openProgressRequested(var item)
    signal openPropertiesRequested(var item)
    signal openColumnsSettingsRequested()
    signal exportTorrentsRequested(var downloadIds)

    property int modelRowCount: 0

    function refreshModelRowCount() {
        modelRowCount = App.downloadModel ? App.downloadModel.rowCount() : 0
    }

    property var categoryDragProxy: null

    // ── Multi-selection state ────────────────────────────────────────────
    // Selection is keyed by the stable DownloadItem.id, NOT row index. When
    // sorting by a volatile column the model live-reorders rows every tick; an
    // index-keyed set would leave the highlight on a position while a different
    // item slides under it. Id-keying makes selection follow the item.
    property var _selectedIds:      ({})
    property int _selectionVersion: 0

    function _idForRow(row) {
        var item = App.downloadModel.itemAt(row)
        return item ? item.id : ""
    }

    function isRowSelected(row) {
        var id = _idForRow(row)
        return id !== "" && !!_selectedIds[id]
    }

    function _setSelection(ids) {
        _selectedIds = ids
        _selectionVersion++
    }

    function _toggleRow(row) {
        var id = _idForRow(row)
        if (id === "") return
        var r = Object.assign({}, _selectedIds)
        if (r[id]) delete r[id]
        else r[id] = true
        _setSelection(r)
    }

    // Range is inherently positional: resolve the row span to ids at click time,
    // after which the selection is stable across any reorder.
    function _addRange(fromRow, toRow) {
        var r = Object.assign({}, _selectedIds)
        var lo = Math.min(fromRow, toRow), hi = Math.max(fromRow, toRow)
        for (var i = lo; i <= hi; i++) {
            var id = _idForRow(i)
            if (id !== "") r[id] = true
        }
        _setSelection(r)
    }

    function _clearAndSelect(row) {
        var r = {}
        var id = _idForRow(row)
        if (id !== "") r[id] = true
        _setSelection(r)
    }

    property string _anchorId: ""

    readonly property var currentSelectedItem: {
        _selectionVersion
        if (_anchorId === "") return null
        return App.downloadModel.itemById(_anchorId)
    }

    readonly property string selectedItemStatus: currentSelectedItem ? currentSelectedItem.status : ""

    readonly property bool hasSelection: { _selectionVersion; return Object.keys(_selectedIds).length > 0 }
    readonly property int selectedTorrentCountValue: {
        _selectionVersion
        var count = 0
        for (var id in _selectedIds) {
            var item = App.downloadModel.itemById(id)
            if (item && item.isTorrent)
                count++
        }
        return count
    }
    readonly property bool anyTorrentSelected: selectedTorrentCountValue > 0

    Connections {
        target: App.downloadModel
        function onRowsInserted() { root.refreshModelRowCount() }
        function onRowsRemoved() { root.refreshModelRowCount() }
        function onModelReset() { root.refreshModelRowCount() }
        function onLayoutChanged() { root.refreshModelRowCount() }
    }

    // ── Toolbar enabled-state bindings reactive via _selectionVersion ────
    readonly property bool anyPausedSelected: {
        _selectionVersion
        for (var id in _selectedIds) {
            var item = App.downloadModel.itemById(id)
            if (item && item.status === "Paused") return true
        }
        return false
    }
    readonly property bool anyActiveSelected: {
        _selectionVersion
        for (var id in _selectedIds) {
            var item = App.downloadModel.itemById(id)
            if (item && (item.status === "Downloading" || item.status === "Queued" || item.status === "Seeding")) return true
        }
        return false
    }
    // Stop is valid for any non-terminal, non-paused item. Includes Queued,
    // Checking, Assembling and Error so a stuck/errored download or torrent can
    // still be stopped — the previous gate only allowed Downloading/Queued/
    // Seeding, leaving Error/Checking items un-stoppable (greyed-out Stop).
    readonly property bool anyStoppableSelected: {
        _selectionVersion
        for (var id in _selectedIds) {
            var item = App.downloadModel.itemById(id)
            if (item && item.status !== "Completed" && item.status !== "Paused") return true
        }
        return false
    }
    readonly property bool anyErrorSelected: {
        _selectionVersion
        for (var id in _selectedIds) {
            var item = App.downloadModel.itemById(id)
            if (item && item.status === "Error") return true
        }
        return false
    }

    function anySelectedHasStatus(status) {
        if (status === "Paused")                             return anyPausedSelected
        if (status === "Downloading" || status === "Queued" || status === "Seeding") return anyActiveSelected
        _selectionVersion
        for (var id in _selectedIds) {
            var item = App.downloadModel.itemById(id)
            if (item && item.status === status) return true
        }
        return false
    }

    function resumeSelected() {
        _selectionVersion
        var ids = []
        for (var id in _selectedIds) {
            var item = App.downloadModel.itemById(id)
            if (item) ids.push(item.id)
        }
        if (ids.length === 1) App.resumeDownload(ids[0])
        else if (ids.length > 1) App.resumeDownloads(ids)
    }
    function stopSelected() {
        _selectionVersion
        for (var id in _selectedIds) {
            var item = App.downloadModel.itemById(id)
            if (item) App.pauseDownload(item.id)
        }
    }
    function pauseAll()        { App.pauseAllDownloads() }
    function deleteSelected()  {
        var selIds = Object.keys(_selectedIds)
        if (selIds.length === 1) {
            var item = _selectedItem()
            if (item) _openDeleteDialog(item)
        } else if (selIds.length > 1) {
            var ids = []
            var fileExists = false
            var hasTorrentSelection = false
            for (var i = 0; i < selIds.length; i++) {
                var it = App.downloadModel.itemById(selIds[i])
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
                _anchorId = ""
            }
        }
    }
    function _selectedItem() {
        if (_anchorId === "") return null
        return App.downloadModel.itemById(_anchorId)
    }
    function _selectedItems() {
        _selectionVersion
        var items = []
        for (var id in _selectedIds) {
            var item = App.downloadModel.itemById(id)
            if (item) items.push(item)
        }
        return items
    }
    function selectedTorrentIds() {
        var ids = []
        var items = _selectedItems()
        for (var i = 0; i < items.length; ++i)
            if (items[i].isTorrent) ids.push(items[i].id)
        return ids
    }
    function selectedTorrentCount() { return selectedTorrentCountValue }
    function hasAnyTorrentSelected() { return anyTorrentSelected }
    function copySelectedShareLinks() {
        var items = _selectedItems()
        if (items.length === 0 && _ctxItem) items = [_ctxItem]
        var links = []
        for (var i = 0; i < items.length; ++i) {
            var link = App.downloadShareLink(items[i].id)
            if (link && link.length > 0) links.push(link)
        }
        if (links.length > 0) App.copyToClipboard(links.join("\n"))
    }
    function requestExportSelectedTorrents() {
        var ids = selectedTorrentIds()
        if (ids.length > 0) exportTorrentsRequested(ids)
    }
    function _selectedId() {
        const item = _selectedItem()
        return item ? item.id : null
    }
    function _openDeleteDialog(item, ids, fileExists, hasTorrentSelection) {
        var torrentSelected = !!hasTorrentSelection
        if (!torrentSelected && item) torrentSelected = !!item.isTorrent
        deleteDialog.downloadId = item ? item.id : ""
        deleteDialog.downloadIds = ids || (item ? [item.id] : [])
        deleteDialog.filename   = item ? item.filename : (deleteDialog.downloadIds.length > 1 ? qsTr("%n selected downloads", "", deleteDialog.downloadIds.length) : "")
        deleteDialog.fileExists = typeof fileExists === "boolean" ? fileExists : (item && item.status === "Completed")
        deleteDialog.hasTorrentSelection = torrentSelected
        deleteDialog.show()
        deleteDialog.raise()
        deleteDialog.requestActivate()
    }

    DeleteConfirmDialog {
        id: deleteDialog
        transientParent: root.Window.window
        property var downloadIds: []
        onConfirmed: (mode) => {
            if (downloadIds && downloadIds.length > 1)
                App.deleteDownloads(downloadIds, mode)
            else if (downloadId.length > 0)
                App.deleteDownload(downloadId, mode)
        }
    }

    // ── Rename torrent root dialog ───────────────────────────────────────
    Window {
        id: renameTorrentRootDialog
        property var targetItem: null
        property string currentName: ""
        transientParent: root.Window.window

        title: qsTr("Rename")
        width: 360; height: 110
        minimumWidth: 280; minimumHeight: 110; maximumHeight: 110
        color: ColorPalette.cardBg
        flags: Qt.Dialog | Qt.WindowTitleHint | Qt.WindowCloseButtonHint

        function openFor(item) {
            targetItem = item
            currentName = item ? item.filename : ""
            nameInput.text = currentName
            var owner = renameTorrentRootDialog.transientParent
            if (owner) {
                renameTorrentRootDialog.x = owner.x + Math.round((owner.width  - renameTorrentRootDialog.width)  / 2)
                renameTorrentRootDialog.y = owner.y + Math.round((owner.height - renameTorrentRootDialog.height) / 2)
            }
            show(); raise(); requestActivate()
            nameInput.forceActiveFocus()
            nameInput.selectAll()
        }

        ColumnLayout {
            anchors { fill: parent; margins: 12 }
            spacing: 10
            TextField {
                id: nameInput
                Layout.fillWidth: true
                implicitHeight: 28
                color: ColorPalette.textPrimary; font.pixelSize: 12 * App.fontScale
                background: Rectangle { color: ColorPalette.inputBg; border.color: nameInput.activeFocus ? "#4488dd" : ColorPalette.border; radius: 2 }
                leftPadding: 6; topPadding: 0; bottomPadding: 0
                Keys.onReturnPressed: confirmBtn.clicked()
                Keys.onEnterPressed:  confirmBtn.clicked()
                Keys.onEscapePressed: renameTorrentRootDialog.close()
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: 6
                Item { Layout.fillWidth: true }
                DlgButton {
                    text: qsTr("Cancel")
                    onClicked: renameTorrentRootDialog.close()
                }
                DlgButton {
                    id: confirmBtn
                    text: qsTr("Rename"); primary: true
                    enabled: nameInput.text.trim().length > 0 && nameInput.text.trim() !== renameTorrentRootDialog.currentName
                    onClicked: {
                        var newName = nameInput.text.trim()
                        if (newName.length > 0 && renameTorrentRootDialog.targetItem)
                            App.setDownloadFilename(renameTorrentRootDialog.targetItem.id, newName)
                        renameTorrentRootDialog.close()
                    }
                }
            }
        }
    }

    // ── Context menu items ───────────────────────────────────────────────
    property var _ctxItem: null

    component CtxMenuItem: MenuItem {
        id: _ctxMi
        implicitHeight: 22
        height: 22
        topPadding: 0; bottomPadding: 0; verticalPadding: 0
        leftPadding: 8; rightPadding: 12
        spacing: 0
        font.pixelSize: 12 * App.fontScale
        property string iconSrc: ""
        indicator: Item { width: 0; height: 0 }
        arrow: Text {
            x: _ctxMi.width - width - 8
            anchors.verticalCenter: parent ? parent.verticalCenter : undefined
            text: "▶"; font.pixelSize: 8 * App.fontScale; color: ColorPalette.textMuted
            visible: _ctxMi.subMenu !== null
        }
        contentItem: Row {
            spacing: 6
            Image {
                visible: _ctxMi.iconSrc !== ""
                source: _ctxMi.iconSrc !== "" ? "icons/" + _ctxMi.iconSrc : ""
                width: 14; height: 14
                sourceSize.width: 14; sourceSize.height: 14
                fillMode: Image.PreserveAspectFit
                smooth: true
                anchors.verticalCenter: parent.verticalCenter
            }
            Item { visible: _ctxMi.iconSrc === ""; width: 0; height: 14 }
            Text {
                text: _ctxMi.text
                font: _ctxMi.font
                color: _ctxMi.enabled ? ColorPalette.textPrimary : ColorPalette.textDisabled
                verticalAlignment: Text.AlignVCenter
                elide: Text.ElideRight
                anchors.verticalCenter: parent.verticalCenter
            }
        }
        background: Rectangle {
            implicitHeight: 22
            // Opaque, never "transparent" — see ColorPalette.menuBg.
            color: _ctxMi.highlighted ? ColorPalette.selectionBg : ColorPalette.menuBg
        }
    }

    // Aliased so the row delegate can access it: table.rowCtxMenu.popup()
    property alias rowCtxMenu: rowCtxMenu

    Menu {
        id: rowCtxMenu
        topPadding: 0; bottomPadding: 0
        CtxMenuItem {
            text: qsTr("Properties")
            iconSrc: "properties.svg"
            onTriggered: { if (root._ctxItem) root.openPropertiesRequested(root._ctxItem) }
        }
        CtxMenuItem { text: qsTr("Open File");   iconSrc: "page.svg";        onTriggered: { if (root._ctxItem) App.openFile(root._ctxItem.id) } }
        CtxMenuItem { text: qsTr("Open Folder"); iconSrc: "folder_view.svg"; onTriggered: { if (root._ctxItem) App.openFolderSelectFile(root._ctxItem.id) } }
        MenuSeparator {}
        Repeater {
            model: (!!root._ctxItem && !!root._ctxItem.isTorrent) ? 1 : 0
            delegate: CtxMenuItem {
                text: qsTr("Rename...")
                iconSrc: "rename.svg"
                onTriggered: { if (root._ctxItem) renameTorrentRootDialog.openFor(root._ctxItem) }
            }
        }
        CtxMenuItem { text: qsTr("Copy Filename"); iconSrc: "copy.svg";   onTriggered: { if (root._ctxItem) App.copyDownloadFilename(root._ctxItem.id) } }
        CtxMenuItem {
            text: root._ctxItem && root._ctxItem.isTorrent ? qsTr("Copy Magnet Link") : qsTr("Copy URL")
            iconSrc: root._ctxItem && root._ctxItem.isTorrent ? "magnet.svg" : "link.svg"
            onTriggered: root.copySelectedShareLinks()
        }
        Repeater {
            model: (!!root._ctxItem && !!root._ctxItem.isTorrent) ? 1 : 0
            delegate: CtxMenuItem {
                text: qsTr("Export .torrent...")
                iconSrc: "export_torrent.svg"
                enabled: root.anyTorrentSelected
                onTriggered: root.requestExportSelectedTorrents()
            }
        }
        Repeater {
            model: (!!root._ctxItem && !!root._ctxItem.isTorrent) ? 1 : 0
            delegate: CtxMenuItem {
                text: qsTr("Verify Local Data")
                iconSrc: "torrent-categories/checking.svg"
                enabled: root._ctxItem && root._ctxItem.status !== "Checking" && root._ctxItem.status !== "Moving"
                onTriggered: { if (root._ctxItem) App.forceRecheckTorrent(root._ctxItem.id) }
            }
        }
        MenuSeparator {}
        CtxMenuItem { text: qsTr("Resume"); iconSrc: "resume.svg"; onTriggered: root.resumeSelected() }
        CtxMenuItem { text: qsTr("Stop");   iconSrc: "pause.svg";  onTriggered: root.stopSelected()   }
        MenuSeparator {}
        CtxMenuItem {
            id: _moveToQueueItem
            text: qsTr("Move to Queue") + "  ▶"
            onTriggered: _moveToQueueMenu.popup(_moveToQueueItem.width, 0)
            onHoveredChanged: {
                if (hovered) { _moveToQueueMenu.popup(_moveToQueueItem.width, 0) }
                else { _mtqCloseTimer.restart() }
            }
            Menu {
                id: _moveToQueueMenu
                delegate: CtxMenuItem; topPadding: 0; bottomPadding: 0
                onAboutToHide: _mtqCloseTimer.stop()
                Repeater {
                    model: App.queueModel
                    delegate: CtxMenuItem {
                        visible: queueId !== "download-limits"
                        height: visible ? 22 : 0
                        text: queueName || ""
                        onTriggered: { if (root._ctxItem) App.setDownloadQueue(root._ctxItem.id, queueId) }
                    }
                }
            }
            Timer { id: _mtqCloseTimer; interval: 300; onTriggered: { if (!_moveToQueueMenu.activeFocus) _moveToQueueMenu.close() } }
        }
        CtxMenuItem {
            text: qsTr("Remove from Queue")
            onTriggered: {
                for (var id in root._selectedIds) {
                    var it = App.downloadModel.itemById(id)
                    if (it) App.setDownloadQueue(it.id, "")
                }
            }
        }
        MenuSeparator {}
        CtxMenuItem { text: qsTr("Redownload"); iconSrc: "update.svg"; onTriggered: { if (root._ctxItem) App.redownload(root._ctxItem.id) } }
        CtxMenuItem { text: qsTr("Delete");     iconSrc: "delete.svg"; onTriggered: { if (root._ctxItem) root._openDeleteDialog(root._ctxItem) } }
    }

    Connections {
        target: App.downloadModel
        function onDataChanged(topLeft, bottomRight, roles) {
            const lo = topLeft.row, hi = bottomRight.row
            for (var r = lo; r <= hi; r++) {
                if (root.isRowSelected(r)) {
                    root._selectionVersion++
                    return
                }
            }
        }
    }

    // ── Column definitions ───────────────────────────────────────────────
    readonly property var _defaultColumnDefs: [
        { title: "Q",              key: "queue",      widthPx: 31,  visible: true  },
        { title: qsTr("File Name"),      key: "name",       widthPx: 240, visible: true  },
        { title: qsTr("Size"),           key: "size",       widthPx: 80,  visible: true  },
        { title: qsTr("Status"),         key: "status",     widthPx: 90,  visible: true  },
        { title: qsTr("Time left"),      key: "timeleft",   widthPx: 90,  visible: true  },
        { title: qsTr("Down Speed"),     key: "downspeed",  widthPx: 90,  visible: true  },
        { title: qsTr("Up Speed"),       key: "upspeed",    widthPx: 90,  visible: true  },
        { title: qsTr("Seeders"),        key: "seeders",    widthPx: 70,  visible: false },
        { title: qsTr("Peers"),          key: "peers",      widthPx: 70,  visible: false },
        { title: qsTr("Ratio"),          key: "ratio",      widthPx: 70,  visible: false },
        { title: qsTr("Uploaded"),       key: "uploaded",   widthPx: 90,  visible: false },
        { title: qsTr("Downloaded"),     key: "downloaded", widthPx: 90,  visible: false },
        { title: qsTr("Date added"),      key: "added",      widthPx: 130, visible: true  },
        { title: qsTr("Last try date"),  key: "lasttry",    widthPx: 110, visible: false },
        { title: qsTr("Description"),    key: "description",widthPx: 120, visible: false },
        { title: qsTr("Save to"),        key: "saveto",     widthPx: 140, visible: false },
        { title: qsTr("Referer"),        key: "referrer",   widthPx: 140, visible: false },
        { title: qsTr("Parent web page"),key: "parenturl",  widthPx: 140, visible: false },
    ]

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
                if (saved && saved.key === "speed") saved.key = "downspeed"
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
            if (seen[def.key]) continue
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
        if (_suppressColumnDefsSave) return
        var serialized = JSON.stringify(columnDefs)
        if (App.settings.downloadTableColumns !== serialized)
            App.settings.downloadTableColumns = serialized
    }

    property var columnDefs: _initialColumnDefs()

    function resetColumns() { columnDefs = _normalizeColumnDefs(_cloneDefaultColumnDefs()) }

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

    function _colVisible(key) {
        for (var i = 0; i < columnDefs.length; i++)
            if (columnDefs[i].key === key) return columnDefs[i].visible
        return false
    }

    function colWidth(key) {
        if (_resizingColumnKey === key) return _resizingColumnWidth
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
        if (key === "queue") return 31
        return 24
    }

    function formatBytesShort(bytes) {
        if (!bytes || bytes <= 0) return ""
        if (bytes >= 1073741824) return (bytes / 1073741824).toFixed(2) + " GB"
        if (bytes >= 1048576) return (bytes / 1048576).toFixed(1) + " MB"
        if (bytes >= 1024) return (bytes / 1024).toFixed(1) + " KB"
        return bytes + " B"
    }

    property real visibleContentWidth: totalVisibleWidth()
    onVisibleColsChanged: visibleContentWidth = totalVisibleWidth()

    property string _resizingColumnKey: ""
    property real _resizingColumnWidth: 0

    property var _colXMap: {
        visibleContentWidth
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
        refreshModelRowCount()
        _suppressColumnDefsSave = false
        App.downloadModel.sortBy(sortKey, sortAscending)
    }

    // ── Filter state ─────────────────────────────────────────────────────
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

    function deselectAll() {
        _setSelection({})
        _anchorId = ""
    }

    function openSelectedFile() {
        var item = _selectedItem()
        if (item && (item.status === "Completed" || item.status === "Seeding")) App.openFile(item.id)
    }

    function openFolderForSelected() {
        var item = _selectedItem()
        if (item && (item.status === "Completed" || item.status === "Seeding")) App.openFolder(item.id)
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
                root._anchorId = item.id
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
                root._anchorId = item.id
                tableView.positionViewAtIndex(row, ListView.Center)
                return
            }
        }
    }

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
                root._anchorId = item.id
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
                root._anchorId = item.id
                tableView.positionViewAtIndex(row, ListView.Center)
                return
            }
        }
    }

    // ── Sort state ───────────────────────────────────────────────────────
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

    readonly property var _sortableKeys: ["name","size","status","timeleft","downspeed","upspeed","seeders","peers","ratio","uploaded","downloaded","added","lasttry","description","saveto","referrer","parenturl","queue"]

    // ── Column visibility context menu ───────────────────────────────────
    component ColCheckMenuItem: MenuItem {
        id: _colChkMi
        implicitHeight: 22
        height: 22
        topPadding: 0; bottomPadding: 0; verticalPadding: 0
        leftPadding: 28; rightPadding: 12
        spacing: 0
        font.pixelSize: 12 * App.fontScale
        indicator: Text {
            x: 8
            anchors.verticalCenter: parent ? parent.verticalCenter : undefined
            text: _colChkMi.checked ? "✓" : ""
            color: "#88bbff"
            font.pixelSize: 11 * App.fontScale
        }
        arrow: Item { width: 0; height: 0 }
        contentItem: Text {
            text: _colChkMi.text
            font: _colChkMi.font
            color: _colChkMi.enabled ? ColorPalette.textPrimary : ColorPalette.textDisabled
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
        }
        background: Rectangle {
            implicitHeight: 22
            // Opaque, never "transparent" — see ColorPalette.menuBg.
            color: _colChkMi.highlighted ? ColorPalette.selectionBg : ColorPalette.menuBg
        }
    }

    Menu {
        id: colCtxMenu
        topPadding: 0; bottomPadding: 0
        Repeater {
            model: root.columnDefs.length
            delegate: ColCheckMenuItem {
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
        CtxMenuItem {
            text: qsTr("Columns Settings")
            onTriggered: root.openColumnsSettingsRequested()
        }
    }

    // ── Header (extracted component) ─────────────────────────────────────
    DownloadTableHeader {
        id: header
        table: root
        tableView: tableView
        colCtxMenu: colCtxMenu
    }

    // ── Rows ─────────────────────────────────────────────────────────────
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

        Keys.onPressed: function(e) {
            if (e.key === Qt.Key_A && (e.modifiers & Qt.ControlModifier)) {
                var r = {}
                var lastId = ""
                for (var i = 0; i < App.downloadModel.rowCount(); i++) {
                    var item = App.downloadModel.data(App.downloadModel.index(i, 0), Qt.UserRole + 2)
                    if (item && root.itemMatchesActiveFilter(item)) {
                        r[item.id] = true
                        lastId = item.id
                    }
                }
                root._setSelection(r)
                root._anchorId = lastId
                e.accepted = true
            } else if (e.key === Qt.Key_Delete) {
                root.deleteSelected()
                e.accepted = true
            } else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) {
                if (e.modifiers & Qt.ControlModifier)
                    root.openFolderForSelected()
                else
                    root.openSelectedFile()
                e.accepted = true
            } else if (e.key === Qt.Key_D && (e.modifiers & Qt.ControlModifier)) {
                root.deselectAll()
                e.accepted = true
            }
        }

        ScrollBar.vertical: ScrollBar {
            id: _tblSbV
            policy: ScrollBar.AsNeeded
            width: 12
            contentItem: Rectangle {
                implicitWidth: 12
                radius: 6
                color: _tblSbV.pressed ? ColorPalette.textSecond
                     : _tblSbV.hovered ? ColorPalette.border
                     : ColorPalette.dividerBg
            }
            background: Rectangle { color: ColorPalette.panelBg }
        }
        ScrollBar.horizontal: ScrollBar {
            id: _tblSbH
            policy: ScrollBar.AsNeeded
            height: 12
            contentItem: Rectangle {
                implicitHeight: 12
                radius: 6
                color: _tblSbH.pressed ? ColorPalette.textSecond
                     : _tblSbH.hovered ? ColorPalette.border
                     : ColorPalette.dividerBg
            }
            background: Rectangle { color: ColorPalette.panelBg }
        }

        WheelHandler {
            orientation: Qt.Vertical
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
            onWheel: function(e) {
                tableView.contentY = Math.max(0,
                    Math.min(tableView.contentY - e.angleDelta.y / 2,
                             Math.max(0, tableView.contentHeight - tableView.height)))
                e.accepted = true
            }
        }

        WheelHandler {
            orientation: Qt.Horizontal
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
            onWheel: function(e) {
                tableView.contentX = Math.max(0,
                    Math.min(tableView.contentX - e.angleDelta.x / 2,
                             Math.max(0, tableView.contentWidth - tableView.width)))
                e.accepted = true
            }
        }

        delegate: DownloadTableRow {
            required property int index
            required property var model
            table: root
            listView: tableView
            rowIndex: index
            rowItem: model.item
        }

        // ── Empty state ──────────────────────────────────────────────────
        Column {
            anchors.centerIn: parent
            spacing: 12
            readonly property bool searchActive: root.filterText.length > 0
            readonly property int filteredCount: searchActive
                ? root.countMatches(root.filterText, root.filterName, root.filterDesc,
                                    root.filterLinks, root.filterMatchCase, root.filterMatchWhole)
                : root.modelRowCount
            visible: filteredCount === 0 && !restoreOverlay.restoreOverlayVisible

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: {
                    if (parent.searchActive)
                        return qsTr("No matching downloads.")
                    return qsTr("No downloads yet.\nClick  Add URL  to start.")
                }
                horizontalAlignment: Text.AlignHCenter
                color: ColorPalette.textDisabled
                font.pixelSize: 14 * App.fontScale
                lineHeight: 1.6
            }
        }

        // Restore indicator
        Column {
            id: restoreOverlay
            anchors.centerIn: parent
            spacing: 12
            z: 2
            readonly property bool restoreOverlayVisible:
                App.selectedCategory === "all"
                && (!App.selectedQueue || App.selectedQueue.length === 0)
                && !root.filterText.length
                && root.filterName
                && !root.filterDesc
                && !root.filterLinks
                && !root.filterMatchCase
                && !root.filterMatchWhole
                && App.restoreTotalCount > 0
                && App.restoreInProgress
            visible: restoreOverlayVisible

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: qsTr("Loading %1 / %2 downloads…")
                      .arg(App.restoreDoneCount).arg(App.restoreTotalCount)
                horizontalAlignment: Text.AlignHCenter
                color: ColorPalette.textDisabled
                font.pixelSize: 14 * App.fontScale
                lineHeight: 1.6
            }

            // Thin progress bar that fills left→right as items drain from the DB.
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 220
                height: 4
                radius: 2
                color: ColorPalette.panelBg
                Rectangle {
                    height: parent.height
                    radius: 2
                    color: ColorPalette.accent
                    // No width Behavior: restore items drain every ~1 ms, far
                    // faster than any animation duration, so an animated bar
                    // perpetually chases a stale target and lags ~70% behind
                    // the actual count. Bind width directly for live state.
                    width: App.restoreTotalCount > 0
                           ? parent.width * (App.restoreDoneCount / App.restoreTotalCount)
                           : 0
                }
            }
        }
    }
}
