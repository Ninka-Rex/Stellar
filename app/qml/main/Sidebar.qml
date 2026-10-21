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

// One tree for both workspaces. Each workspace is a top-level row that *is*
// its unfiltered view ("Downloads" = every download, "Torrents" = every
// torrent); its filters sit one level in, and sub-groups (torrent categories,
// grabber projects, queues) one level deeper. Clicking any row switches to
// that row's workspace and applies its filter; only the arrows collapse.
//
//   ▼ Downloads              167
//       Music / Video / …          categories
//       Unfinished / Finished
//     ▶ Grabber Projects
//     ▼ Queues                     (selectable: every queued download)
//         Main download queue
//   ▼ Torrents                56
//       Downloading / Seeding / …  torrent states
//     ▼ Categories
//         Music / Video / …
//
// Everything reorders by drag: the two workspaces, the sections inside each
// (a section without a header row, like the category list, moves by dragging
// the sections around it), categories, torrent states, grabber projects.
Rectangle {
    id: root
    color: ColorPalette.toolbarBg

    signal categorySelected(string catId)
    signal queueSelected(string queueId)
    signal grabberProjectSelected(string projectId)
    signal editGrabberProjectRequested(string projectId)
    signal deleteGrabberProjectRequested(string projectId)
    // The host switches workspaces (it saves/restores each one's view).
    signal workspaceRequested(string workspace)

    // ── Section drag-and-drop (SidebarSectionDragHandler) ────────────────
    // _secDragOrder names the list being reordered: "workspaces" (the two
    // groups), "downloads" (Downloads sections) or "torrents" (Torrents
    // sections); only that list draws drop lines.
    property int    _secDragFrom:   -1
    property int    _secDropTarget: -1
    property bool   _secDragging:   false
    property string _secDragOrder:  ""

    function _orderFor(key) {
        if (key === "workspaces") return App.settings.sidebarWorkspaceOrder
        if (key === "torrents")   return App.settings.sidebarTorrentOrder
        return App.settings.sidebarOrder
    }
    function _applySectionReorder() {
        if (!_secDragging || _secDragFrom < 0 || _secDropTarget < 0) return
        if (_secDragFrom === _secDropTarget) return
        var to = (_secDragFrom < _secDropTarget) ? _secDropTarget - 1 : _secDropTarget
        if (_secDragFrom === to) return
        var order = _orderFor(_secDragOrder).slice()
        order.splice(to, 0, order.splice(_secDragFrom, 1)[0])
        if (_secDragOrder === "workspaces") App.settings.sidebarWorkspaceOrder = order
        else if (_secDragOrder === "torrents") App.settings.sidebarTorrentOrder = order
        else App.settings.sidebarOrder = order
    }
    // Drop line above section `index` of list `key`.
    function _secDropLineAt(key, index) {
        if (!_secDragging || _secDragOrder !== key || _secDropTarget !== index) return false
        var to = (_secDragFrom < _secDropTarget) ? _secDropTarget - 1 : _secDropTarget
        return to !== _secDragFrom
    }
    // Drop line after the last section of list `key`.
    function _secDropLineAtEnd(key) {
        var n = _orderFor(key).length
        return _secDragging && _secDragOrder === key && _secDropTarget === n && _secDragFrom !== n - 1
    }

    // Selected row within the current workspace (see the index scheme below).
    property int selectedIndex: 0

    // Main-window workspace ("downloads" | "torrents"): which group's row is
    // selected, and whose filter the table shows.
    property string workspace: "downloads"

    // Row indices. Each workspace has its own index space; a row is selected
    // only while its workspace is the current one.
    //   downloads: 999 all · category row = model row · -1 unfinished ·
    //              -2 finished · -500-i grabber project · -999 any queue ·
    //              -100-i queue
    //   torrents:  -200 all · -201-i state · category row = model row
    readonly property int allDownloadsIndex: 999
    readonly property int allTorrentsIndex: -200

    // Selects a row of `group`, switching workspace first when it isn't the
    // current one (the switch restores that workspace's last view, which the
    // new selection then replaces).
    function _pick(group, index) {
        if (workspace !== group)
            workspaceRequested(group)
        selectedIndex = index
    }
    function pickCategory(group, index, catId)      { _pick(group, index); categorySelected(catId) }
    function pickQueue(group, index, queueId)       { _pick(group, index); queueSelected(queueId) }
    function pickGrabber(group, index, projectId)   { _pick(group, index); grabberProjectSelected(projectId) }
    function isSelected(group, index) { return workspace === group && selectedIndex === index }

    // ── Expand state ─────────────────────────────────────────────────────
    property bool downloadsExpanded: true
    property bool torrentsExpanded: true
    property bool torrentCategoriesExpanded: true
    property bool queuesExpanded: true
    property bool grabberExpanded: true

    // ── Row drag-and-drop states ─────────────────────────────────────────
    // One per reorderable list, so a drag never draws drop lines in another.
    QtObject {
        id: _torrentStateDragState
        property bool dragging: false
        property int  dragFrom: -1
        property int  dropTarget: -1
    }
    function _applyTorrentStateReorder() {
        var st = _torrentStateDragState
        if (!st.dragging || st.dragFrom < 0 || st.dropTarget < 0) return
        if (st.dragFrom === st.dropTarget) return
        var to = (st.dragFrom < st.dropTarget) ? st.dropTarget - 1 : st.dropTarget
        if (st.dragFrom === to) return
        var order = App.settings.torrentSubcatOrder.slice()
        order.splice(to, 0, order.splice(st.dragFrom, 1)[0])
        App.settings.torrentSubcatOrder = order
    }
    QtObject {
        id: _grabberDragState
        property bool dragging: false
        property int  dragFrom: -1
        property int  dropTarget: -1
    }

    Menu {
        id: grabberProjectContextMenu
        property string projectId: ""
        MenuItem {
            text: qsTr("Edit Project")
            enabled: grabberProjectContextMenu.projectId.length > 0
            onTriggered: root.editGrabberProjectRequested(grabberProjectContextMenu.projectId)
        }
        MenuItem {
            text: qsTr("Delete Project")
            enabled: grabberProjectContextMenu.projectId.length > 0
            onTriggered: root.deleteGrabberProjectRequested(grabberProjectContextMenu.projectId)
        }
    }

    // Dragged table rows, for dropping onto a category or queue.
    function _droppedIds(drop) {
        if (!drop.source)
            return []
        return drop.source.dragDownloadIds && drop.source.dragDownloadIds.length > 0
                ? drop.source.dragDownloadIds
                : (drop.source.dragDownloadId ? [drop.source.dragDownloadId] : [])
    }

    // Icon x of a row at `level`. Arrows hang in the gutter left of the icon,
    // so a level only steps in by the arrow's width.
    function iconX(level) { return 20 + level * 14 }

    // Insert line drawn while dragging a list entry.
    component DropLine: Rectangle {
        width: parent ? parent.width : 0
        height: 2
        color: ColorPalette.accent
        z: 20
    }

    // ── Tree row ─────────────────────────────────────────────────────────
    // Every row of the tree: arrow in the gutter, icon, label, and the live
    // count on the right. The row's mouse handling is supplied by its user as
    // a child (drag handlers differ per list); `hovered` feeds the hover colour
    // back in.
    component TreeRow: Rectangle {
        id: row
        property int level: 1
        property bool expandable: false
        property bool expanded: false
        property string iconSource: ""
        property string label: ""
        property bool selected: false
        property bool hovered: false
        // Workspace and filter id of the count; empty filter = no count.
        property string countGroup: ""
        property string countFilter: ""
        // A workspace row: larger, bold, with the current-workspace bar.
        readonly property bool workspaceRow: level === 0
        property bool currentWorkspace: false
        signal toggled()

        readonly property real _iconX: root.iconX(level)

        width: mainScroll.width
        height: workspaceRow ? 30 : 26
        color: selected ? ColorPalette.selectionBg : (hovered ? ColorPalette.hoverBg : "transparent")
        border.color: selected ? ColorPalette.accent : "transparent"
        border.width: 1

        Rectangle {
            visible: row.workspaceRow && row.currentWorkspace
            width: 3; height: parent.height
            color: ColorPalette.accent
        }

        TreeExpander {
            visible: row.expandable
            expanded: row.expanded
            x: row._iconX - 18
            anchors.verticalCenter: parent.verticalCenter
        }
        Image {
            id: rowIcon
            source: row.iconSource
            visible: row.iconSource.length > 0
            x: row._iconX
            width: 16; height: 16; sourceSize.width: 16; sourceSize.height: 16
            fillMode: Image.PreserveAspectFit; smooth: true; mipmap: true
            anchors.verticalCenter: parent.verticalCenter
        }
        Text {
            x: rowIcon.visible ? row._iconX + 21 : row._iconX
            // Everything up to the count is the label's.
            width: Math.max(0, (rowCount.visible ? rowCount.x - 6 : row.width - 6) - x)
            anchors.verticalCenter: parent.verticalCenter
            text: row.label
            color: row.selected ? ColorPalette.selectionText
                 : row.workspaceRow && row.currentWorkspace ? ColorPalette.textHeader : ColorPalette.textPrimary
            font.pixelSize: (row.workspaceRow ? 13 : 12) * App.fontScale
            font.bold: row.workspaceRow
            elide: Text.ElideRight
        }
        Text {
            id: rowCount
            visible: row.countFilter.length > 0
            anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
            text: App.downloadModel.sidebarCounts[row.countGroup + "/" + row.countFilter] || 0
            color: row.selected ? ColorPalette.selectionText : ColorPalette.textMuted
            font.pixelSize: (row.workspaceRow ? 12 : 11) * App.fontScale
            font.bold: row.workspaceRow
        }

        // Above the row's own handler, so the arrow always toggles.
        MouseArea {
            visible: row.expandable
            z: 10
            x: row._iconX - 20
            width: 20; height: parent.height
            cursorShape: Qt.PointingHandCursor
            onClicked: row.toggled()
        }
    }

    // Plain click handler for rows that don't reorder.
    component RowMouse: MouseArea {
        anchors.fill: parent
        hoverEnabled: true
    }

    // ── Category rows of one workspace ───────────────────────────────────
    component CategoryList: Column {
        id: catList
        required property string group
        required property int level
        width: mainScroll.width
        spacing: 0

        // Per list, so a reorder drag in one workspace's copy doesn't draw
        // drop lines in the other's.
        QtObject {
            id: catDragState
            property bool dragging: false
            property int  dragFrom: -1
            property int  dropTarget: -1
        }

        Repeater {
            id: catRepeater
            model: catList.visible ? App.categoryModel : null

            delegate: TreeRow {
                id: catRow
                readonly property int modelRow: index
                // The "all" model row is the workspace row itself.
                visible: categoryId !== "all"
                height: visible ? 26 : 0
                clip: true
                level: catList.level
                // Model stores qml-root-relative paths ("icons/…"); this file
                // lives in qml/main/, so resolve up one level.
                iconSource: categoryIcon ? "../" + categoryIcon : ""
                label: categoryLabel
                selected: root.isSelected(catList.group, index)
                hovered: (catMa.containsMouse && !catDragState.dragging) || catDrop.containsDrag
                countGroup: catList.group; countFilter: categoryId
                opacity: (catDragState.dragging && catDragState.dragFrom === catRow.modelRow) ? 0.4 : 1.0

                DropLine {
                    visible: catDragState.dragging
                          && catDragState.dropTarget === catRow.modelRow
                          && catDragState.dragFrom !== catDragState.dropTarget
                          && catDragState.dragFrom !== catDragState.dropTarget - 1
                }

                SidebarItemDragHandler {
                    id: catMa
                    rowIndex: catRow.modelRow
                    dragState: catDragState
                    repeater: catRepeater
                    rowCount: App.categoryModel.rowCount()
                    sidebarColumn: _sidebarCol
                    applyReorder: function(from, target) {
                        var toRow = (from < target) ? target - 1 : target
                        if (toRow !== from && toRow >= 1)
                            App.categoryModel.moveCategory(from, toRow)
                    }
                    onClicked: function(mouse) {
                        root.pickCategory(catList.group, index, categoryId)
                    }
                }

                DropArea {
                    id: catDrop
                    anchors.fill: parent; keys: ["text/downloadId"]
                    onDropped: (drop) => {
                        var ids = root._droppedIds(drop)
                        for (var i = 0; i < ids.length; i++)
                            App.setDownloadCategory(ids[i], categoryId)
                        if (ids.length > 0) drop.accept()
                    }
                }
            }
        }

        DropLine {
            visible: catDragState.dragging
                  && catDragState.dropTarget >= App.categoryModel.rowCount()
                  && catDragState.dragFrom !== App.categoryModel.rowCount() - 1
        }
    }

    // ── Downloads sections (ordered by sidebarOrder) ─────────────────────
    component DownloadsSection: Item {
        id: sec
        required property string secId
        required property int    secIdx
        required property var    sectionRepeater
        required property var    sectionColumn
        readonly property string group: "downloads"

        width: mainScroll.width
        // "torrents" is a legacy sidebarOrder id; the Torrents group has its
        // own order.
        visible: secId !== "torrents"
        height: !visible ? 0
              : secId === "downloads" ? catCol.height
              : secId === "grabber"   ? grabberCol.height
              : secId === "queues"    ? queuesCol.height
              : 26

        DropLine { visible: root._secDropLineAt("downloads", sec.secIdx) }

        // Categories, straight under "Downloads".
        CategoryList {
            id: catCol
            visible: sec.secId === "downloads"
            group: sec.group
            level: 1
        }

        TreeRow {
            visible: sec.secId === "unfinished"
            iconSource: "../icons/places/folder.svg"
            label: qsTr("Unfinished")
            selected: root.isSelected(sec.group, -1)
            hovered: unfinMa.containsMouse
            countGroup: sec.group; countFilter: "status_active"
            SidebarSectionDragHandler {
                id: unfinMa
                orderKey: "downloads"
                sectionIndex: sec.secIdx
                sidebarRoot: root
                sidebarColumn: sec.sectionColumn
                sectionRepeater: sec.sectionRepeater
                onClicked: root.pickCategory(sec.group, -1, "status_active")
            }
        }

        TreeRow {
            visible: sec.secId === "finished"
            iconSource: "../icons/places/folder.svg"
            label: qsTr("Finished")
            selected: root.isSelected(sec.group, -2)
            hovered: finMa.containsMouse
            countGroup: sec.group; countFilter: "status_completed"
            SidebarSectionDragHandler {
                id: finMa
                orderKey: "downloads"
                sectionIndex: sec.secIdx
                sidebarRoot: root
                sidebarColumn: sec.sectionColumn
                sectionRepeater: sec.sectionRepeater
                onClicked: root.pickCategory(sec.group, -2, "status_completed")
            }
        }

        // ── Grabber projects ─────────────────────────────────────────────
        Column {
            id: grabberCol
            visible: sec.secId === "grabber"
            width: parent.width
            spacing: 0

            TreeRow {
                expandable: true
                expanded: root.grabberExpanded
                iconSource: "../icons/actions/grabber.svg"
                label: qsTr("Grabber Projects")
                hovered: grabberHeaderMa.containsMouse
                onToggled: root.grabberExpanded = !root.grabberExpanded
                SidebarSectionDragHandler {
                    id: grabberHeaderMa
                    orderKey: "downloads"
                    sectionIndex: sec.secIdx
                    sidebarRoot: root
                    sidebarColumn: sec.sectionColumn
                    sectionRepeater: sec.sectionRepeater
                    onClicked: root.grabberExpanded = !root.grabberExpanded
                }
            }

            Repeater {
                id: grabberRepeater
                model: root.grabberExpanded && grabberCol.visible ? App.grabberProjectModel : 0
                delegate: TreeRow {
                    id: projectRow
                    readonly property int modelRow: index
                    level: 2
                    iconSource: "../icons/places/folder.svg"
                    label: projectName || ""
                    selected: root.isSelected(sec.group, -500 - index)
                    hovered: grabberMa.containsMouse
                    // A project's downloads carry its id as their category.
                    countGroup: sec.group; countFilter: projectId
                    opacity: (_grabberDragState.dragging && _grabberDragState.dragFrom === projectRow.modelRow) ? 0.4 : 1.0

                    DropLine {
                        visible: _grabberDragState.dragging
                              && _grabberDragState.dropTarget === projectRow.modelRow
                              && _grabberDragState.dragFrom !== _grabberDragState.dropTarget
                              && _grabberDragState.dragFrom !== _grabberDragState.dropTarget - 1
                    }

                    SidebarItemDragHandler {
                        id: grabberMa
                        rowIndex: projectRow.modelRow
                        dragState: _grabberDragState
                        repeater: grabberRepeater
                        rowCount: App.grabberProjectModel.rowCount()
                        sidebarColumn: _sidebarCol
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        applyReorder: function(from, target) {
                            var toRow = (from < target) ? target - 1 : target
                            if (target >= App.grabberProjectModel.rowCount())
                                toRow = App.grabberProjectModel.rowCount() - 1
                            if (toRow !== from && toRow >= 0)
                                App.grabberProjectModel.moveProject(from, toRow)
                        }
                        onClicked: function(mouse) {
                            root.pickGrabber(sec.group, -500 - index, projectId)
                            if (mouse.button === Qt.RightButton) {
                                grabberProjectContextMenu.projectId = projectId
                                grabberProjectContextMenu.popup()
                            }
                        }
                        onDoubleClicked: root.editGrabberProjectRequested(projectId)
                    }
                }
            }

            DropLine {
                visible: _grabberDragState.dragging
                      && _grabberDragState.dropTarget >= App.grabberProjectModel.rowCount()
                      && _grabberDragState.dragFrom !== App.grabberProjectModel.rowCount() - 1
            }
        }

        // ── Queues ───────────────────────────────────────────────────────
        Column {
            id: queuesCol
            visible: sec.secId === "queues"
            width: parent.width
            spacing: 0

            TreeRow {
                expandable: true
                expanded: root.queuesExpanded
                iconSource: "../icons/queues/queues.svg"
                label: qsTr("Queues")
                selected: root.isSelected(sec.group, -999)
                hovered: queueHeaderMa.containsMouse
                countGroup: sec.group; countFilter: "queue_any"
                onToggled: root.queuesExpanded = !root.queuesExpanded
                SidebarSectionDragHandler {
                    id: queueHeaderMa
                    orderKey: "downloads"
                    sectionIndex: sec.secIdx
                    sidebarRoot: root
                    sidebarColumn: sec.sectionColumn
                    sectionRepeater: sec.sectionRepeater
                    onClicked: root.pickQueue(sec.group, -999, "queue_any")
                }
            }

            Repeater {
                model: root.queuesExpanded && queuesCol.visible ? App.queueModel : 0
                delegate: TreeRow {
                    level: 2
                    iconSource: queueId === "main-download" ? "../icons/queues/queue-main.svg"
                                                            : "../icons/queues/queue-custom.svg"
                    label: queueName || ""
                    selected: root.isSelected(sec.group, -100 - index)
                    hovered: qMa.containsMouse || qDrop.containsDrag
                    countGroup: sec.group; countFilter: "queue:" + queueId
                    RowMouse {
                        id: qMa
                        onClicked: root.pickQueue(sec.group, -100 - index, queueId)
                    }
                    DropArea {
                        id: qDrop; anchors.fill: parent; keys: ["text/downloadId"]
                        onDropped: (drop) => {
                            var ids = root._droppedIds(drop)
                            for (var i = 0; i < ids.length; i++)
                                App.setDownloadQueue(ids[i], queueId)
                            if (ids.length > 0) drop.accept()
                        }
                    }
                }
            }
        }
    }

    // ── Torrents sections (ordered by sidebarTorrentOrder) ───────────────
    component TorrentsSection: Item {
        id: tsec
        required property string secId
        required property int    secIdx
        required property var    sectionRepeater
        required property var    sectionColumn
        readonly property string group: "torrents"

        width: mainScroll.width
        height: secId === "states" ? statesCol.height : torrentCatsCol.height

        DropLine { visible: root._secDropLineAt("torrents", tsec.secIdx) }

        // Torrent states, straight under "Torrents".
        Column {
            id: statesCol
            visible: tsec.secId === "states"
            width: parent.width
            spacing: 0

            Repeater {
                id: torrentStateRepeater
                model: statesCol.visible ? App.settings.torrentSubcatOrder : null

                delegate: TreeRow {
                    id: stateRow
                    readonly property int    modelRow: index
                    readonly property string stateId: modelData
                    readonly property int    selIdx: -201 - index
                    iconSource: {
                        switch (stateId) {
                        case "torrent_downloading": return "../icons/torrent-states/downloading.svg"
                        case "torrent_seeding":     return "../icons/torrent-states/seeding.svg"
                        case "torrent_stopped":     return "../icons/torrent-states/stopped.svg"
                        case "torrent_active":      return "../icons/torrent-states/active.svg"
                        case "torrent_inactive":    return "../icons/torrent-states/inactive.svg"
                        case "torrent_checking":    return "../icons/torrent-states/checking.svg"
                        case "torrent_moving":      return "../icons/torrent-states/moving.svg"
                        default:                    return "../icons/places/folder.svg"
                        }
                    }
                    label: {
                        switch (stateId) {
                        case "torrent_downloading": return qsTr("Downloading")
                        case "torrent_seeding":     return qsTr("Seeding")
                        case "torrent_stopped":     return qsTr("Stopped")
                        case "torrent_active":      return qsTr("Active")
                        case "torrent_inactive":    return qsTr("Inactive")
                        case "torrent_checking":    return qsTr("Checking")
                        case "torrent_moving":      return qsTr("Moving")
                        default:                    return stateId
                        }
                    }
                    selected: root.isSelected(tsec.group, selIdx)
                    hovered: stateMa.containsMouse && !_torrentStateDragState.dragging
                    countGroup: tsec.group; countFilter: stateId
                    opacity: (_torrentStateDragState.dragging && _torrentStateDragState.dragFrom === stateRow.modelRow) ? 0.4 : 1.0

                    DropLine {
                        visible: _torrentStateDragState.dragging
                              && _torrentStateDragState.dropTarget === stateRow.modelRow
                              && _torrentStateDragState.dragFrom !== _torrentStateDragState.dropTarget
                              && _torrentStateDragState.dragFrom !== _torrentStateDragState.dropTarget - 1
                    }

                    SidebarItemDragHandler {
                        id: stateMa
                        rowIndex: stateRow.modelRow
                        dragState: _torrentStateDragState
                        repeater: torrentStateRepeater
                        rowCount: App.settings.torrentSubcatOrder.length
                        sidebarColumn: _sidebarCol
                        applyReorder: function(from, target) { root._applyTorrentStateReorder() }
                        onClicked: function(mouse) {
                            root.pickCategory(tsec.group, stateRow.selIdx, stateRow.stateId)
                        }
                    }
                }
            }

            DropLine {
                visible: _torrentStateDragState.dragging
                      && _torrentStateDragState.dropTarget >= App.settings.torrentSubcatOrder.length
                      && _torrentStateDragState.dragFrom !== App.settings.torrentSubcatOrder.length - 1
            }
        }

        // Torrent categories, one level deeper.
        Column {
            id: torrentCatsCol
            visible: tsec.secId === "categories"
            width: parent.width
            spacing: 0

            TreeRow {
                expandable: true
                expanded: root.torrentCategoriesExpanded
                iconSource: "../icons/categories/all-downloads.svg"
                label: qsTr("Categories")
                hovered: torrentCatsMa.containsMouse
                onToggled: root.torrentCategoriesExpanded = !root.torrentCategoriesExpanded
                SidebarSectionDragHandler {
                    id: torrentCatsMa
                    orderKey: "torrents"
                    sectionIndex: tsec.secIdx
                    sidebarRoot: root
                    sidebarColumn: tsec.sectionColumn
                    sectionRepeater: tsec.sectionRepeater
                    onClicked: root.torrentCategoriesExpanded = !root.torrentCategoriesExpanded
                }
            }

            CategoryList {
                visible: root.torrentCategoriesExpanded && torrentCatsCol.visible
                group: tsec.group
                level: 2
            }
        }
    }

    // ── One workspace: its row and its sections ──────────────────────────
    component WorkspaceGroup: Column {
        id: wsGroup
        required property string ws
        required property int    wsIdx
        required property var    groupRepeater
        readonly property bool torrents: ws === "torrents"
        readonly property bool expanded: torrents ? root.torrentsExpanded : root.downloadsExpanded
        width: mainScroll.width
        spacing: 0

        DropLine { visible: root._secDropLineAt("workspaces", wsGroup.wsIdx) }

        TreeRow {
            level: 0
            expandable: true
            expanded: wsGroup.expanded
            iconSource: wsGroup.torrents ? "../icons/torrent-states/all-torrents.svg"
                                         : "../icons/places/network-server.svg"
            label: wsGroup.torrents ? qsTr("Torrents") : qsTr("Downloads")
            currentWorkspace: root.workspace === wsGroup.ws
            selected: root.isSelected(wsGroup.ws, wsGroup.torrents ? root.allTorrentsIndex : root.allDownloadsIndex)
            hovered: wsMa.containsMouse || wsDrop.containsDrag
            countGroup: wsGroup.ws; countFilter: "all"
            onToggled: {
                if (wsGroup.torrents) root.torrentsExpanded = !root.torrentsExpanded
                else root.downloadsExpanded = !root.downloadsExpanded
            }
            SidebarSectionDragHandler {
                id: wsMa
                orderKey: "workspaces"
                sectionIndex: wsGroup.wsIdx
                sidebarRoot: root
                sidebarColumn: _sidebarCol
                sectionRepeater: wsGroup.groupRepeater
                onClicked: {
                    if (wsGroup.torrents) root.pickCategory("torrents", root.allTorrentsIndex, "torrent_all")
                    else root.pickCategory("downloads", root.allDownloadsIndex, "all")
                }
            }
            ThemedToolTip {
                visible: wsMa.containsMouse && !root._secDragging
                text: wsGroup.torrents ? qsTr("Torrents (Ctrl+2)") : qsTr("Downloads (Ctrl+1)")
                delay: 600
            }
            // Dropping downloads on "Downloads" clears their category.
            DropArea {
                id: wsDrop
                enabled: !wsGroup.torrents
                anchors.fill: parent; keys: ["text/downloadId"]
                onDropped: (drop) => {
                    var ids = root._droppedIds(drop)
                    for (var i = 0; i < ids.length; i++)
                        App.setDownloadCategory(ids[i], "all")
                    if (ids.length > 0) drop.accept()
                }
            }
        }

        Column {
            id: downloadsSections
            visible: !wsGroup.torrents && wsGroup.expanded
            width: parent.width
            spacing: 0
            Repeater {
                id: downloadsRepeater
                model: downloadsSections.visible ? App.settings.sidebarOrder : null
                delegate: DownloadsSection {
                    required property string modelData
                    required property int index
                    secId: modelData
                    secIdx: index
                    sectionRepeater: downloadsRepeater
                    sectionColumn: downloadsSections
                }
            }
            DropLine { visible: root._secDropLineAtEnd("downloads") }
        }

        Column {
            id: torrentsSections
            visible: wsGroup.torrents && wsGroup.expanded
            width: parent.width
            spacing: 0
            Repeater {
                id: torrentsRepeater
                model: torrentsSections.visible ? App.settings.sidebarTorrentOrder : null
                delegate: TorrentsSection {
                    required property string modelData
                    required property int index
                    secId: modelData
                    secIdx: index
                    sectionRepeater: torrentsRepeater
                    sectionColumn: torrentsSections
                }
            }
            DropLine { visible: root._secDropLineAtEnd("torrents") }
        }
    }

    // ── Main scrollable area ─────────────────────────────────────────────
    ScrollView {
        id: mainScroll
        anchors.fill: parent
        clip: true
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
        ScrollBar.vertical: ScrollBar {
            id: _sbVert
            policy: ScrollBar.AsNeeded
            width: 10
            contentItem: Rectangle {
                implicitWidth: 10
                radius: 5
                color: _sbVert.pressed ? ColorPalette.textSecond
                     : _sbVert.hovered ? ColorPalette.border
                     : ColorPalette.dividerBg
            }
            background: Rectangle { color: "transparent" }
        }

        Column {
            id: _sidebarCol
            width: mainScroll.width
            spacing: 0

            Repeater {
                id: workspaceRepeater
                model: App.settings.sidebarWorkspaceOrder
                delegate: WorkspaceGroup {
                    required property string modelData
                    required property int index
                    ws: modelData
                    wsIdx: index
                    groupRepeater: workspaceRepeater
                }
            }
            DropLine { visible: root._secDropLineAtEnd("workspaces") }
        }
    }

    // Right border
    Rectangle {
        anchors { top: parent.top; bottom: parent.bottom; right: parent.right }
        width: 1; color: ColorPalette.border
    }
}
