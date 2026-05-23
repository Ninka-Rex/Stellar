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
    color: "#1f1f1f"

    signal categorySelected(string catId)
    signal queueSelected(string queueId)
    signal grabberProjectSelected(string projectId)
    signal editGrabberProjectRequested(string projectId)
    signal deleteGrabberProjectRequested(string projectId)

    function _applySectionReorder() {
        if (!_secDragging || _secDragFrom < 0 || _secDropTarget < 0) return
        if (_secDragFrom === _secDropTarget) return
        var to = (_secDragFrom < _secDropTarget) ? _secDropTarget - 1 : _secDropTarget
        if (_secDragFrom === to) return
        var order = App.settings.sidebarOrder.slice()
        order.splice(to, 0, order.splice(_secDragFrom, 1)[0])
        App.settings.sidebarOrder = order
    }

    property int selectedIndex: 0

    // ── Section/category expand state ─────────────────────────────────────────
    property bool allDownloadsExpanded: true
    property bool queuesExpanded: true
    property bool grabberExpanded: true
    property bool torrentsExpanded: true

    // ── Torrent subcategory drag-and-drop state ───────────────────────────────
    QtObject {
        id: _torrentSubcatDragState
        property bool dragging: false
        property int  dragFrom: -1
        property int  dropTarget: -1
    }

    function _applyTorrentSubcatReorder() {
        if (!_torrentSubcatDragState.dragging || _torrentSubcatDragState.dragFrom < 0 || _torrentSubcatDragState.dropTarget < 0) return
        if (_torrentSubcatDragState.dragFrom === _torrentSubcatDragState.dropTarget) return
        var to = (_torrentSubcatDragState.dragFrom < _torrentSubcatDragState.dropTarget) ? _torrentSubcatDragState.dropTarget - 1 : _torrentSubcatDragState.dropTarget
        if (_torrentSubcatDragState.dragFrom === to) return
        var order = App.settings.torrentSubcatOrder.slice()
        order.splice(to, 0, order.splice(_torrentSubcatDragState.dragFrom, 1)[0])
        App.settings.torrentSubcatOrder = order
    }

    // ── Category / grabber project drag state ─────────────────────────────────
    QtObject {
        id: _catDragState
        property bool dragging: false
        property int  dragFrom: -1
        property int  dropTarget: -1
    }

    QtObject {
        id: _grabberDragState
        property bool dragging: false
        property int  dragFrom: -1
        property int  dropTarget: -1
    }

    // ── Section drag-and-drop state ───────────────────────────────────────────
    property int  _secDragFrom:   -1
    property int  _secDropTarget: -1
    property bool _secDragging:   false

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

    // ── "Categories" label bar ────────────────────────────────────────────────
    Rectangle {
        id: catHeader
        anchors { top: parent.top; left: parent.left; right: parent.right }
        height: 26; color: "#2d2d2d"
        Rectangle { width: 3; height: parent.height; color: "#5588cc" }
        Text {
            anchors { verticalCenter: parent.verticalCenter; left: parent.left; leftMargin: 8 }
            text: qsTr("Categories"); color: "#d0d0d0"; font.pixelSize: 12 * App.fontScale; font.bold: true
        }
        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: "#3a3a3a" }
    }

    // ── Main scrollable area ──────────────────────────────────────────────────
    ScrollView {
        id: mainScroll
        anchors { top: catHeader.bottom; left: parent.left; right: parent.right; bottom: parent.bottom }
        clip: true

        Column {
            id: sidebarColumn
            width: mainScroll.width
            spacing: 0

            Repeater {
                id: sectionRepeater
                model: App.settings.sidebarOrder

                delegate: Item {
                    id: sectionDelegate
                    readonly property string secId:  modelData
                    readonly property int    secIdx: index
                    width: mainScroll.width

                    height: {
                        if (secId === "downloads")  return dlCol.height
                        if (secId === "unfinished") return 28
                        if (secId === "finished")   return 28
                        if (secId === "grabber")    return grabberCol.height
                        if (secId === "queues")     return queuesCol.height
                        if (secId === "torrents")   return torrentsCol.height
                        return 0
                    }

                    // Blue insert-line shown above this section while dragging
                    Rectangle {
                        visible: {
                            if (!root._secDragging || root._secDropTarget !== sectionDelegate.secIdx) return false
                            var to = (root._secDragFrom < root._secDropTarget) ? root._secDropTarget - 1 : root._secDropTarget
                            return to !== root._secDragFrom
                        }
                        anchors { top: parent.top; left: parent.left; right: parent.right }
                        height: 2; color: "#5588cc"; z: 20
                    }

                    // ── "All Downloads" + categories ─────────────────────────
                    Column {
                        id: dlCol
                        visible: sectionDelegate.secId === "downloads"
                        width: parent.width
                        spacing: 0

                        Rectangle {
                            width: parent.width; height: 28
                            color: root.selectedIndex === 999 ? "#1e3a6e"
                                 : (allDlMouse.containsMouse ? "#2a2a3a" : "transparent")
                            border.color: root.selectedIndex === 999 ? "#4488dd" : "transparent"
                            border.width: 1

                            Row {
                                anchors { verticalCenter: parent.verticalCenter
                                          left: parent.left; leftMargin: 4 }
                                spacing: 2
                                Text {
                                    text: root.allDownloadsExpanded ? "▼" : "▶"
                                    color: "#999"; font.pixelSize: 12 * App.fontScale; width: 16
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                                Image { source: "icons/categories/all_downloads.svg"; width: 16; height: 16; sourceSize.width: 16; sourceSize.height: 16; fillMode: Image.PreserveAspectFit; smooth: true; mipmap: true; anchors.verticalCenter: parent.verticalCenter }
                                Text {
                                    text: qsTr("All Downloads")
                                    color: root.selectedIndex === 999 ? "#88bbff" : "#cccccc"
                                    font.pixelSize: 12 * App.fontScale; font.bold: root.selectedIndex === 999
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                            }

                            // Section reorder + click/expand (replaces inline MouseArea copy)
                            SidebarSectionDragHandler {
                                id: allDlMouse
                                sectionIndex: sectionDelegate.secIdx
                                sidebarRoot: root
                                sidebarColumn: sidebarColumn
                                sectionRepeater: sectionRepeater
                                onClicked:       { root.selectedIndex = 999; root.categorySelected("all") }
                                onDoubleClicked: { root.allDownloadsExpanded = !root.allDownloadsExpanded }
                            }

                            DropArea {
                                anchors.fill: parent; keys: ["text/downloadId"]
                                onDropped: (drop) => {
                                    if (drop.source) {
                                        var ids = drop.source.dragDownloadIds && drop.source.dragDownloadIds.length > 0
                                                ? drop.source.dragDownloadIds
                                                : (drop.source.dragDownloadId ? [drop.source.dragDownloadId] : [])
                                        for (var i = 0; i < ids.length; i++)
                                            App.setDownloadCategory(ids[i], "all")
                                        if (ids.length > 0) drop.accept()
                                    }
                                }
                            }
                        }

                        Repeater {
                            id: catRepeater
                            model: root.allDownloadsExpanded ? App.categoryModel : null

                            delegate: Item {
                                id: catDelegate
                                readonly property int modelRow: index
                                width: mainScroll.width
                                visible: categoryId !== "all"
                                height: visible ? 26 : 0
                                clip: true

                                // Insert line above this row during drag
                                Rectangle {
                                    visible: _catDragState.dragging
                                          && _catDragState.dropTarget === catDelegate.modelRow
                                          && _catDragState.dragFrom !== _catDragState.dropTarget
                                          && _catDragState.dragFrom !== _catDragState.dropTarget - 1
                                    anchors { top: parent.top; left: parent.left; right: parent.right }
                                    height: 2; color: "#4488dd"; z: 10
                                }

                                Rectangle {
                                    id: catBg
                                    anchors.fill: parent
                                    color: root.selectedIndex === index ? "#1e3a6e"
                                         : (catMa.containsMouse && !_catDragState.dragging ? "#2a2a3a"
                                         : (catDrop.containsDrag ? "#2a3a2a" : "transparent"))
                                    border.color: root.selectedIndex === index ? "#4488dd" : "transparent"
                                    border.width: 1
                                    opacity: (_catDragState.dragging && _catDragState.dragFrom === catDelegate.modelRow) ? 0.4 : 1.0

                                    Row {
                                        anchors { verticalCenter: parent.verticalCenter
                                                  left: parent.left; leftMargin: 22 }
                                        spacing: 5
                                        Image {
                                            source: categoryIcon; width: 16; height: 16
                                            sourceSize.width: 16; sourceSize.height: 16
                                            fillMode: Image.PreserveAspectFit; smooth: true; mipmap: true
                                            anchors.verticalCenter: parent.verticalCenter
                                        }
                                        Text {
                                            text: categoryLabel
                                            color: root.selectedIndex === index ? "#88bbff" : "#cccccc"
                                            font.pixelSize: 12 * App.fontScale; anchors.verticalCenter: parent.verticalCenter
                                        }
                                    }
                                }

                                SidebarItemDragHandler {
                                    id: catMa
                                    rowIndex: catDelegate.modelRow
                                    dragState: _catDragState
                                    repeater: catRepeater
                                    rowCount: App.categoryModel.rowCount()
                                    sidebarColumn: sidebarColumn
                                    applyReorder: function(from, target) {
                                        var toRow = (from < target) ? target - 1 : target
                                        if (toRow !== from && toRow >= 1)
                                            App.categoryModel.moveCategory(from, toRow)
                                    }
                                    onClicked: function(mouse) {
                                        root.selectedIndex = index
                                        root.categorySelected(categoryId)
                                    }
                                }

                                DropArea {
                                    id: catDrop
                                    anchors.fill: parent; keys: ["text/downloadId"]
                                    onDropped: (drop) => {
                                        if (drop.source) {
                                            var ids = drop.source.dragDownloadIds && drop.source.dragDownloadIds.length > 0
                                                    ? drop.source.dragDownloadIds
                                                    : (drop.source.dragDownloadId ? [drop.source.dragDownloadId] : [])
                                            for (var i = 0; i < ids.length; i++)
                                                App.setDownloadCategory(ids[i], categoryId)
                                            if (ids.length > 0) drop.accept()
                                        }
                                    }
                                }
                            }
                        }

                        // Insert line at bottom of category list
                        Rectangle {
                            visible: _catDragState.dragging
                                  && _catDragState.dropTarget >= App.categoryModel.rowCount()
                                  && _catDragState.dragFrom !== App.categoryModel.rowCount() - 1
                            width: parent.width; height: 2; color: "#4488dd"; z: 10
                        }
                    }

                    // ── "Unfinished" filter row ───────────────────────────────
                    Rectangle {
                        id: unfinishedRow
                        visible: sectionDelegate.secId === "unfinished"
                        width: parent.width; height: 28
                        color: root.selectedIndex === -1 ? "#1e3a6e" : (unfinMa.containsMouse ? "#2a2a3a" : "transparent")
                        border.color: root.selectedIndex === -1 ? "#4488dd" : "transparent"; border.width: 1

                        Row {
                            anchors { verticalCenter: parent.verticalCenter; left: parent.left; leftMargin: 0 }
                            spacing: 5
                            Item { width: 3; height: 1 }
                            Image { source: "icons/folder.svg"; width: 16; height: 16; sourceSize.width: 16; sourceSize.height: 16; fillMode: Image.PreserveAspectFit; smooth: true; mipmap: true; anchors.verticalCenter: parent.verticalCenter }
                            Text { text: qsTr("Unfinished"); color: root.selectedIndex === -1 ? "#88bbff" : "#cccccc"; font.pixelSize: 12 * App.fontScale; anchors.verticalCenter: parent.verticalCenter }
                        }

                        SidebarSectionDragHandler {
                            id: unfinMa
                            sectionIndex: sectionDelegate.secIdx
                            sidebarRoot: root
                            sidebarColumn: sidebarColumn
                            sectionRepeater: sectionRepeater
                            onClicked: { root.selectedIndex = -1; root.categorySelected("status_active") }
                        }
                    }

                    // ── "Finished" filter row ─────────────────────────────────
                    Rectangle {
                        id: finishedRow
                        visible: sectionDelegate.secId === "finished"
                        width: parent.width; height: 28
                        color: root.selectedIndex === -2 ? "#1e3a6e" : (finMa.containsMouse ? "#2a2a3a" : "transparent")
                        border.color: root.selectedIndex === -2 ? "#4488dd" : "transparent"; border.width: 1

                        Row {
                            anchors { verticalCenter: parent.verticalCenter; left: parent.left; leftMargin: 0 }
                            spacing: 5
                            Item { width: 3; height: 1 }
                            Image { source: "icons/folder.svg"; width: 16; height: 16; sourceSize.width: 16; sourceSize.height: 16; fillMode: Image.PreserveAspectFit; smooth: true; mipmap: true; anchors.verticalCenter: parent.verticalCenter }
                            Text { text: qsTr("Finished"); color: root.selectedIndex === -2 ? "#88bbff" : "#cccccc"; font.pixelSize: 12 * App.fontScale; anchors.verticalCenter: parent.verticalCenter }
                        }

                        SidebarSectionDragHandler {
                            id: finMa
                            sectionIndex: sectionDelegate.secIdx
                            sidebarRoot: root
                            sidebarColumn: sidebarColumn
                            sectionRepeater: sectionRepeater
                            onClicked: { root.selectedIndex = -2; root.categorySelected("status_completed") }
                        }
                    }

                    // ── Grabber projects section ──────────────────────────────
                    Column {
                        id: grabberCol
                        visible: sectionDelegate.secId === "grabber"
                        width: parent.width
                        spacing: 0

                        Rectangle {
                            width: parent.width; height: 28
                            color: grabberHeaderMa.containsMouse ? "#2a2a3a" : "transparent"

                            Row {
                                anchors { verticalCenter: parent.verticalCenter; left: parent.left; leftMargin: 4 }
                                spacing: 2
                                Text { text: root.grabberExpanded ? "▼" : "▶"; color: "#999"; font.pixelSize: 12 * App.fontScale; width: 16; anchors.verticalCenter: parent.verticalCenter }
                                Image { source: "icons/grabber.svg"; width: 16; height: 16; sourceSize.width: 16; sourceSize.height: 16; fillMode: Image.PreserveAspectFit; anchors.verticalCenter: parent.verticalCenter }
                                Text { text: qsTr("Grabber Projects"); color: "#cccccc"; font.pixelSize: 12 * App.fontScale; anchors.verticalCenter: parent.verticalCenter }
                            }

                            SidebarSectionDragHandler {
                                id: grabberHeaderMa
                                sectionIndex: sectionDelegate.secIdx
                                sidebarRoot: root
                                sidebarColumn: sidebarColumn
                                sectionRepeater: sectionRepeater
                                onClicked: { root.grabberExpanded = !root.grabberExpanded }
                            }
                        }

                        Repeater {
                            id: grabberRepeater
                            model: root.grabberExpanded ? App.grabberProjectModel : 0
                            delegate: Rectangle {
                                id: grabberProjectDelegate
                                readonly property int modelRow: index
                                width: mainScroll.width
                                height: 26
                                color: root.selectedIndex === -500 - index ? "#1e3a6e"
                                     : (grabberMa.containsMouse ? "#2a2a3a" : "transparent")
                                border.color: root.selectedIndex === -500 - index ? "#4488dd" : "transparent"
                                border.width: 1
                                opacity: (_grabberDragState.dragging && _grabberDragState.dragFrom === grabberProjectDelegate.modelRow) ? 0.4 : 1.0

                                Rectangle {
                                    visible: _grabberDragState.dragging
                                          && _grabberDragState.dropTarget === grabberProjectDelegate.modelRow
                                          && _grabberDragState.dragFrom !== _grabberDragState.dropTarget
                                          && _grabberDragState.dragFrom !== _grabberDragState.dropTarget - 1
                                    anchors { top: parent.top; left: parent.left; right: parent.right }
                                    height: 2; color: "#4488dd"; z: 10
                                }

                                Row {
                                    anchors { verticalCenter: parent.verticalCenter; left: parent.left; leftMargin: 22 }
                                    spacing: 5
                                    Image { source: "icons/folder.svg"; width: 16; height: 16; sourceSize.width: 16; sourceSize.height: 16; fillMode: Image.PreserveAspectFit }
                                    Text {
                                        text: projectName || ""
                                        color: root.selectedIndex === -500 - index ? "#88bbff" : "#cccccc"
                                        font.pixelSize: 12 * App.fontScale; anchors.verticalCenter: parent.verticalCenter
                                        elide: Text.ElideRight; width: 126
                                    }
                                }

                                SidebarItemDragHandler {
                                    id: grabberMa
                                    rowIndex: grabberProjectDelegate.modelRow
                                    dragState: _grabberDragState
                                    repeater: grabberRepeater
                                    rowCount: App.grabberProjectModel.rowCount()
                                    sidebarColumn: sidebarColumn
                                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                                    applyReorder: function(from, target) {
                                        var toRow = (from < target) ? target - 1 : target
                                        if (target >= App.grabberProjectModel.rowCount())
                                            toRow = App.grabberProjectModel.rowCount() - 1
                                        if (toRow !== from && toRow >= 0)
                                            App.grabberProjectModel.moveProject(from, toRow)
                                    }
                                    onClicked: function(mouse) {
                                        if (mouse.button === Qt.RightButton) {
                                            root.selectedIndex = -500 - index
                                            root.grabberProjectSelected(projectId)
                                            grabberProjectContextMenu.projectId = projectId
                                            grabberProjectContextMenu.popup()
                                            return
                                        }
                                        root.selectedIndex = -500 - index
                                        root.grabberProjectSelected(projectId)
                                    }
                                    onDoubleClicked: root.editGrabberProjectRequested(projectId)
                                }
                            }
                        }

                        Rectangle {
                            visible: _grabberDragState.dragging
                                  && _grabberDragState.dropTarget >= App.grabberProjectModel.rowCount()
                                  && _grabberDragState.dragFrom !== App.grabberProjectModel.rowCount() - 1
                            width: parent.width; height: 2; color: "#4488dd"; z: 10
                        }
                    }

                    // ── Torrents section ──────────────────────────────────────
                    Column {
                        id: torrentsCol
                        visible: sectionDelegate.secId === "torrents"
                        width: parent.width; spacing: 0

                        Rectangle {
                            width: parent.width; height: 28
                            color: root.selectedIndex === -200 ? "#1e3a6e" : (torrentHeaderMa.containsMouse ? "#2a2a3a" : "transparent")
                            border.color: root.selectedIndex === -200 ? "#4488dd" : "transparent"; border.width: 1

                            Row {
                                anchors { verticalCenter: parent.verticalCenter; left: parent.left; leftMargin: 4 }
                                spacing: 2
                                Text { text: root.torrentsExpanded ? "▼" : "▶"; color: "#999"; font.pixelSize: 12 * App.fontScale; width: 16; anchors.verticalCenter: parent.verticalCenter }
                                Image { source: "icons/torrent-categories/all_torrents.svg"; width: 16; height: 16; sourceSize.width: 16; sourceSize.height: 16; fillMode: Image.PreserveAspectFit; smooth: true; mipmap: true; anchors.verticalCenter: parent.verticalCenter }
                                Text { text: qsTr("Torrents"); color: root.selectedIndex === -200 ? "#88bbff" : "#cccccc"; font.pixelSize: 12 * App.fontScale; font.bold: root.selectedIndex === -200; anchors.verticalCenter: parent.verticalCenter }
                            }

                            SidebarSectionDragHandler {
                                id: torrentHeaderMa
                                sectionIndex: sectionDelegate.secIdx
                                sidebarRoot: root
                                sidebarColumn: sidebarColumn
                                sectionRepeater: sectionRepeater
                                onClicked:       { root.selectedIndex = -200; root.categorySelected("torrent_all") }
                                onDoubleClicked: { root.torrentsExpanded = !root.torrentsExpanded }
                            }
                        }

                        Repeater {
                            id: torrentSubcatRepeater
                            model: root.torrentsExpanded ? App.settings.torrentSubcatOrder : null

                            delegate: Item {
                                id: torrentSubcatDelegate
                                readonly property int    modelRow: index
                                readonly property string subcatId: modelData
                                readonly property string subcatLabel: {
                                    switch (subcatId) {
                                    case "torrent_downloading": return qsTr("Downloading")
                                    case "torrent_seeding":     return qsTr("Seeding")
                                    case "torrent_stopped":     return qsTr("Stopped")
                                    case "torrent_active":      return qsTr("Active")
                                    case "torrent_inactive":    return qsTr("Inactive")
                                    case "torrent_checking":    return qsTr("Checking")
                                    case "torrent_moving":      return qsTr("Moving")
                                    default:                    return subcatId
                                    }
                                }
                                readonly property string subcatIcon: {
                                    switch (subcatId) {
                                    case "torrent_downloading": return "icons/torrent-categories/downloading.svg"
                                    case "torrent_seeding":     return "icons/torrent-categories/seeding.svg"
                                    case "torrent_stopped":     return "icons/torrent-categories/stopped.svg"
                                    case "torrent_active":      return "icons/torrent-categories/active.svg"
                                    case "torrent_inactive":    return "icons/torrent-categories/inactive.svg"
                                    case "torrent_checking":    return "icons/torrent-categories/checking.svg"
                                    case "torrent_moving":      return "icons/torrent-categories/moving.svg"
                                    default:                    return "icons/folder.svg"
                                    }
                                }
                                readonly property int selIdx: -201 - index
                                width: mainScroll.width
                                height: 26

                                Rectangle {
                                    visible: _torrentSubcatDragState.dragging
                                          && _torrentSubcatDragState.dropTarget === torrentSubcatDelegate.modelRow
                                          && _torrentSubcatDragState.dragFrom !== _torrentSubcatDragState.dropTarget
                                          && _torrentSubcatDragState.dragFrom !== _torrentSubcatDragState.dropTarget - 1
                                    anchors { top: parent.top; left: parent.left; right: parent.right }
                                    height: 2; color: "#4488dd"; z: 10
                                }

                                Rectangle {
                                    id: torrentSubcatBg
                                    anchors.fill: parent
                                    color: root.selectedIndex === torrentSubcatDelegate.selIdx ? "#1e3a6e"
                                         : (torrentSubcatMa.containsMouse && !_torrentSubcatDragState.dragging ? "#2a2a3a"
                                         : (torrentSubcatDrop.containsDrag ? "#2a3a2a" : "transparent"))
                                    border.color: root.selectedIndex === torrentSubcatDelegate.selIdx ? "#4488dd" : "transparent"
                                    border.width: 1
                                    opacity: (_torrentSubcatDragState.dragging && _torrentSubcatDragState.dragFrom === torrentSubcatDelegate.modelRow) ? 0.4 : 1.0

                                    Row {
                                        anchors { verticalCenter: parent.verticalCenter; left: parent.left; leftMargin: 22 }
                                        spacing: 5
                                        Image {
                                            source: torrentSubcatDelegate.subcatIcon; width: 16; height: 16
                                            sourceSize.width: 16; sourceSize.height: 16
                                            fillMode: Image.PreserveAspectFit; smooth: true; mipmap: true
                                            anchors.verticalCenter: parent.verticalCenter
                                        }
                                        Text {
                                            text: torrentSubcatDelegate.subcatLabel
                                            color: root.selectedIndex === torrentSubcatDelegate.selIdx ? "#88bbff" : "#cccccc"
                                            font.pixelSize: 12 * App.fontScale; anchors.verticalCenter: parent.verticalCenter
                                        }
                                    }
                                }

                                SidebarItemDragHandler {
                                    id: torrentSubcatMa
                                    rowIndex: torrentSubcatDelegate.modelRow
                                    dragState: _torrentSubcatDragState
                                    repeater: torrentSubcatRepeater
                                    rowCount: App.settings.torrentSubcatOrder.length
                                    sidebarColumn: sidebarColumn
                                    applyReorder: function(from, target) {
                                        root._applyTorrentSubcatReorder()
                                    }
                                    onClicked: function(mouse) {
                                        root.selectedIndex = torrentSubcatDelegate.selIdx
                                        root.categorySelected(torrentSubcatDelegate.subcatId)
                                    }
                                }

                                DropArea {
                                    id: torrentSubcatDrop
                                    anchors.fill: parent; keys: ["text/downloadId"]
                                    onDropped: (drop) => { drop.accept() }
                                }
                            }
                        }

                        Rectangle {
                            visible: _torrentSubcatDragState.dragging
                                  && _torrentSubcatDragState.dropTarget >= App.settings.torrentSubcatOrder.length
                                  && _torrentSubcatDragState.dragFrom !== App.settings.torrentSubcatOrder.length - 1
                            width: parent.width; height: 2; color: "#4488dd"; z: 10
                        }
                    }

                    // ── Queues section ────────────────────────────────────────
                    Column {
                        id: queuesCol
                        visible: sectionDelegate.secId === "queues"
                        width: parent.width; spacing: 0

                        Rectangle {
                            width: parent.width; height: 28
                            color: root.selectedIndex === -999 ? "#1e3a6e" : (queueHeaderMa.containsMouse ? "#2a2a3a" : "transparent")
                            border.color: root.selectedIndex === -999 ? "#4488dd" : "transparent"; border.width: 1

                            Row {
                                anchors { verticalCenter: parent.verticalCenter; left: parent.left; leftMargin: 4 }
                                spacing: 2
                                Text { text: root.queuesExpanded ? "▼" : "▶"; color: "#999"; font.pixelSize: 12 * App.fontScale; width: 16; anchors.verticalCenter: parent.verticalCenter }
                                Image { width: 16; height: 16; sourceSize.width: 16; sourceSize.height: 16; fillMode: Image.PreserveAspectFit; source: "qrc:/qt/qml/com/stellar/app/app/qml/icons/queues.svg"; anchors.verticalCenter: parent.verticalCenter }
                                Text { text: qsTr("Queues"); color: root.selectedIndex === -999 ? "#88bbff" : "#cccccc"; font.pixelSize: 12 * App.fontScale; anchors.verticalCenter: parent.verticalCenter }
                            }

                            SidebarSectionDragHandler {
                                id: queueHeaderMa
                                sectionIndex: sectionDelegate.secIdx
                                sidebarRoot: root
                                sidebarColumn: sidebarColumn
                                sectionRepeater: sectionRepeater
                                onClicked:       { root.selectedIndex = -999; root.queueSelected("queue_any") }
                                onDoubleClicked: { root.queuesExpanded = !root.queuesExpanded }
                            }
                        }

                        Repeater {
                            model: root.queuesExpanded ? App.queueModel : 0
                            delegate: Rectangle {
                                visible: queueId !== "download-limits"
                                width: mainScroll.width; height: visible ? 26 : 0
                                color: root.selectedIndex === -100 - index ? "#1e3a6e"
                                     : (qMa.containsMouse ? "#2a2a3a" : (qDrop.containsDrag ? "#2a3a2a" : "transparent"))
                                border.color: root.selectedIndex === -100 - index ? "#4488dd" : "transparent"; border.width: 1
                                Row {
                                    anchors { verticalCenter: parent.verticalCenter; left: parent.left; leftMargin: 22 }
                                    spacing: 5
                                    Image {
                                        width: 16; height: 16; sourceSize.width: 16; sourceSize.height: 16; fillMode: Image.PreserveAspectFit
                                        source: queueId === "main-download" ? "qrc:/qt/qml/com/stellar/app/app/qml/icons/main_queue.svg"
                                              : queueId === "main-sync"     ? "qrc:/qt/qml/com/stellar/app/app/qml/icons/synch_queue.svg"
                                              :                               "qrc:/qt/qml/com/stellar/app/app/qml/icons/custom_queue.svg"
                                    }
                                    Text { text: queueName || ""; color: root.selectedIndex === -100 - index ? "#88bbff" : "#cccccc"; font.pixelSize: 12 * App.fontScale; anchors.verticalCenter: parent.verticalCenter }
                                }
                                MouseArea {
                                    id: qMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    onClicked: { root.selectedIndex = -100 - index; root.queueSelected(queueId) }
                                }
                                DropArea {
                                    id: qDrop; anchors.fill: parent; keys: ["text/downloadId"]
                                    onDropped: (drop) => {
                                        if (drop.source) {
                                            var ids = drop.source.dragDownloadIds && drop.source.dragDownloadIds.length > 0
                                                    ? drop.source.dragDownloadIds
                                                    : (drop.source.dragDownloadId ? [drop.source.dragDownloadId] : [])
                                            for (var i = 0; i < ids.length; i++)
                                                App.setDownloadQueue(ids[i], queueId)
                                            if (ids.length > 0) drop.accept()
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // Insert line below all sections (drop at very end)
            Rectangle {
                visible: root._secDragging
                      && root._secDropTarget === App.settings.sidebarOrder.length
                      && root._secDragFrom !== App.settings.sidebarOrder.length - 1
                width: parent.width; height: 2; color: "#5588cc"; z: 20
            }
        }
    }

    // Right border
    Rectangle {
        anchors { top: parent.top; bottom: parent.bottom; right: parent.right }
        width: 1; color: "#3a3a3a"
    }
}
