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

    // ── Category drag-and-drop state ──────────────────────────────────────────
    property int  _catDragFrom:   -1
    property int  _catDropTarget: -1
    property bool _catDragging:   false
    property int  _grabberDragFrom:   -1
    property int  _grabberDropTarget: -1
    property bool _grabberDragging:   false

    function _applyGrabberProjectReorder() {
        if (!_grabberDragging || _grabberDragFrom < 0 || _grabberDropTarget < 0) return
        if (_grabberDragFrom === _grabberDropTarget) return
        var to = (_grabberDragFrom < _grabberDropTarget) ? _grabberDropTarget - 1 : _grabberDropTarget
        if (_grabberDropTarget >= App.grabberProjectModel.rowCount())
            to = App.grabberProjectModel.rowCount() - 1
        if (_grabberDragFrom === to || to < 0) return
        App.grabberProjectModel.moveProject(_grabberDragFrom, to)
    }

    Menu {
        id: grabberProjectContextMenu
        property string projectId: ""
        MenuItem {
            text: "Edit Project"
            enabled: grabberProjectContextMenu.projectId.length > 0
            onTriggered: root.editGrabberProjectRequested(grabberProjectContextMenu.projectId)
        }
        MenuItem {
            text: "Delete Project"
            enabled: grabberProjectContextMenu.projectId.length > 0
            onTriggered: root.deleteGrabberProjectRequested(grabberProjectContextMenu.projectId)
        }
    }

    // ── Section drag-and-drop state ───────────────────────────────────────────
    // Sections are the top-level groups; order persisted in App.settings.sidebarOrder.
    property int  _secDragFrom:   -1
    property int  _secDropTarget: -1
    property bool _secDragging:   false

    // ── "Categories" label bar ────────────────────────────────────────────────
    Rectangle {
        id: catHeader
        anchors { top: parent.top; left: parent.left; right: parent.right }
        height: 26; color: "#2d2d2d"
        Rectangle { width: 3; height: parent.height; color: "#5588cc" }
        Text {
            anchors { verticalCenter: parent.verticalCenter; left: parent.left; leftMargin: 8 }
            text: "Categories"; color: "#d0d0d0"; font.pixelSize: 12; font.bold: true
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

            // Sections rendered in the order stored in sidebarOrder.
            // Each delegate inlines ALL four section types (only the matching one
            // is visible) so every expression has access to `root` and outer ids.
            // Using Component+Loader would isolate the scope and break those references.
            Repeater {
                id: sectionRepeater
                model: App.settings.sidebarOrder

                delegate: Item {
                    id: sectionDelegate
                    readonly property string secId:  modelData
                    readonly property int    secIdx: index
                    width: mainScroll.width

                    // Section height equals whichever child is visible
                    height: {
                        if (secId === "downloads")  return dlCol.height
                        if (secId === "unfinished") return 28
                        if (secId === "finished")   return 28
                        if (secId === "grabber")    return grabberCol.height
                        if (secId === "queues")     return queuesCol.height
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

                        // Header row
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
                                    color: "#999"; font.pixelSize: 12; width: 16
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                                Image { source: "icons/downloads.ico"; width: 16; height: 16; sourceSize.width: 16; sourceSize.height: 16; fillMode: Image.PreserveAspectFit; smooth: true; mipmap: true; anchors.verticalCenter: parent.verticalCenter }
                                Text {
                                    text: "All Downloads"
                                    color: root.selectedIndex === 999 ? "#88bbff" : "#cccccc"
                                    font.pixelSize: 12; font.bold: root.selectedIndex === 999
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                            }

                            // Full-row MouseArea handles both section reorder (drag) and
                            // selection/expand (click/double-click).
                            // IMPORTANT: use shorthand handler syntax (not function(m){}) so
                            // that QML ids like `root` remain in scope. In Qt 6, function()
                            // handlers create true JS closures that don't inherit the QML
                            // context, causing "ReferenceError: root is not defined".
                            // Use mouseX/mouseY/pressedButtons (MouseArea properties) instead
                            // of the event parameter.
                            MouseArea {
                                id: allDlMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                preventStealing: true

                                property real _pressY:  0
                                property bool _didDrag: false

                                onPressed:  { _pressY = mouseY; _didDrag = false }

                                onPositionChanged: {
                                    if (!(pressedButtons & Qt.LeftButton)) return
                                    if (!root._secDragging && Math.abs(mouseY - _pressY) > 12) {
                                        root._secDragFrom = sectionDelegate.secIdx
                                        root._secDragging = true; _didDrag = true
                                    }
                                    if (root._secDragging) {
                                        var posY = allDlMouse.mapToItem(sidebarColumn, mouseX, mouseY).y
                                        var tgt = sectionRepeater.count
                                        for (var i = 0; i < sectionRepeater.count; i++) {
                                            var si = sectionRepeater.itemAt(i)
                                            if (si && posY < si.y + si.height / 2) { tgt = i; break }
                                        }
                                        root._secDropTarget = tgt
                                    }
                                }

                                onReleased: {
                                    var dragFrom = root._secDragFrom
                                    var dragging = root._secDragging
                                    var dropTarget = root._secDropTarget
                                    var thisIdx = sectionDelegate.secIdx
                                    var rootRef = root
                                    var allRef = allDlMouse

                                    allDlMouse.preventStealing = false

                                    Qt.callLater(function() {
                                        if (thisIdx === dragFrom && dragging && dropTarget >= 0) {
                                            rootRef._applySectionReorder()
                                        }
                                        rootRef._secDragging = false
                                        rootRef._secDragFrom = -1
                                        rootRef._secDropTarget = -1
                                        allRef.preventStealing = true
                                    })

                                    _didDrag = false
                                    _pressY = 0
                                }

                                onClicked:       { root.selectedIndex = 999; root.categorySelected("all") }
                                onDoubleClicked: {
                                    root.allDownloadsExpanded = !root.allDownloadsExpanded
                                }
                            }
                        }

                        // User categories (skip "all" placeholder at row 0)
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

                                // Insert line above this row during a category drag.
                                // Hide when the drop would be a no-op:
                                //   same position: fromRow == dropTarget
                                //   moving down by 1: fromRow == dropTarget-1 (toRow = dropTarget-1 == fromRow)
                                Rectangle {
                                    visible: root._catDragging
                                          && root._catDropTarget === catDelegate.modelRow
                                          && root._catDragFrom !== root._catDropTarget
                                          && root._catDragFrom !== root._catDropTarget - 1
                                    anchors { top: parent.top; left: parent.left; right: parent.right }
                                    height: 2; color: "#4488dd"; z: 10
                                }

                                Rectangle {
                                    id: catBg
                                    anchors.fill: parent
                                    color: root.selectedIndex === index ? "#1e3a6e"
                                         : (catMa.containsMouse && !root._catDragging ? "#2a2a3a"
                                         : (catDrop.containsDrag ? "#2a3a2a" : "transparent"))
                                    border.color: root.selectedIndex === index ? "#4488dd" : "transparent"
                                    border.width: 1
                                    opacity: (root._catDragging && root._catDragFrom === catDelegate.modelRow) ? 0.4 : 1.0

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
                                            font.pixelSize: 12; anchors.verticalCenter: parent.verticalCenter
                                        }
                                    }
                                }

                                MouseArea {
                                    id: catMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: root._catDragging ? Qt.ClosedHandCursor : Qt.PointingHandCursor
                                    preventStealing: true

                                    property real _pressY:  0
                                    property bool _didDrag: false

                                    onPressed:  { _pressY = mouseY; _didDrag = false }

                                    onPositionChanged: {
                                        if (!(pressedButtons & Qt.LeftButton)) return
                                        if (!root._catDragging && Math.abs(mouseY - _pressY) > 6) {
                                            root._catDragFrom = catDelegate.modelRow
                                            root._catDragging = true; _didDrag = true
                                            catMa.preventStealing = true  // Hold mouse events during drag
                                        }
                                        if (root._catDragging) {
                                            // Map the cursor into sidebarColumn space and walk each
                                            // delegate to find which insert slot the cursor is over.
                                            // This is correct regardless of which row initiated the
                                            // drag — the old relY approach computed different offsets
                                            // depending on the pressed row, causing wrong targets.
                                            var cursorY = catMa.mapToItem(sidebarColumn, mouseX, mouseY).y
                                            // Default: cursor is below all delegates → append at end.
                                            var target = App.categoryModel.rowCount()
                                            for (var r = 1; r < App.categoryModel.rowCount(); r++) {
                                                var del = catRepeater.itemAt(r)
                                                // Skip the hidden "all" row (height 0) and any missing delegates.
                                                if (!del || del.height === 0) continue
                                                var delTop = del.mapToItem(sidebarColumn, 0, 0).y
                                                // Insert above this delegate when the cursor is above its midpoint.
                                                if (cursorY < delTop + del.height / 2) {
                                                    target = r
                                                    break
                                                }
                                            }
                                            root._catDropTarget = target
                                        }
                                    }

                                    onReleased: {
                                        var dragFrom = root._catDragFrom
                                        var dragging = root._catDragging
                                        var dropTarget = root._catDropTarget
                                        var thisRow = catDelegate.modelRow
                                        var rootRef = root
                                        var catRef = catMa

                                        // Release mouse control immediately
                                        catMa.preventStealing = false

                                        // Defer move and cleanup to next event cycle to ensure proper context
                                        Qt.callLater(function() {
                                            // Only the category that initiated drag should perform the move
                                            if (thisRow === dragFrom && dragging && dropTarget >= 1) {
                                                var toRow = (dragFrom < dropTarget) ? dropTarget - 1 : dropTarget
                                                if (toRow !== dragFrom && toRow >= 1) {
                                                    App.categoryModel.moveCategory(dragFrom, toRow)
                                                }
                                            }
                                            // Clean up drag state
                                            rootRef._catDragging = false
                                            rootRef._catDragFrom = -1
                                            rootRef._catDropTarget = -1
                                            catRef.preventStealing = true
                                        })

                                        root._secDragging = false
                                        root._secDragFrom = -1
                                        root._secDropTarget = -1
                                        _didDrag = false
                                        _pressY = 0
                                    }

                                    onClicked: {
                                        if (!_didDrag) { root.selectedIndex = index; root.categorySelected(categoryId) }
                                        _didDrag = false
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
                                            for (var i = 0; i < ids.length; i++) {
                                                App.setDownloadCategory(ids[i], categoryId)
                                            }
                                            if (ids.length > 0) drop.accept()
                                        }
                                    }
                                }
                            }
                        }

                        // Insert line at bottom of category list (drop after last category)
                        // Hide when fromRow is already the last item (no-op).
                        Rectangle {
                            visible: root._catDragging
                                  && root._catDropTarget >= App.categoryModel.rowCount()
                                  && root._catDragFrom !== App.categoryModel.rowCount() - 1
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
                            Image { source: "icons/folder.ico"; width: 16; height: 16; sourceSize.width: 16; sourceSize.height: 16; fillMode: Image.PreserveAspectFit; smooth: true; mipmap: true; anchors.verticalCenter: parent.verticalCenter }
                            Text { text: "Unfinished"; color: root.selectedIndex === -1 ? "#88bbff" : "#cccccc"; font.pixelSize: 12; anchors.verticalCenter: parent.verticalCenter }
                        }
                        MouseArea {
                            id: unfinMa
                            anchors.fill: parent
                            hoverEnabled: true
                            preventStealing: true

                            property real _pressY:  0
                            property bool _didDrag: false

                            onPressed:  { _pressY = mouseY; _didDrag = false }

                            onPositionChanged: {
                                if (!(pressedButtons & Qt.LeftButton)) return
                                if (!root._secDragging && Math.abs(mouseY - _pressY) > 12) {
                                    root._secDragFrom = sectionDelegate.secIdx; root._secDragging = true; _didDrag = true
                                }
                                if (root._secDragging) {
                                    var posY = unfinMa.mapToItem(sidebarColumn, mouseX, mouseY).y
                                    var tgt = sectionRepeater.count
                                    for (var i = 0; i < sectionRepeater.count; i++) {
                                        var si = sectionRepeater.itemAt(i)
                                        if (si && posY < si.y + si.height / 2) { tgt = i; break }
                                    }
                                    root._secDropTarget = tgt
                                }
                            }

                            onReleased: {
                                var dragFrom = root._secDragFrom
                                var dragging = root._secDragging
                                var dropTarget = root._secDropTarget
                                var thisIdx = sectionDelegate.secIdx
                                var rootRef = root
                                var unfinRef = unfinMa

                                unfinMa.preventStealing = false

                                Qt.callLater(function() {
                                    if (thisIdx === dragFrom && dragging && dropTarget >= 0) {
                                        rootRef._applySectionReorder()
                                    }
                                    rootRef._secDragging = false
                                    rootRef._secDragFrom = -1
                                    rootRef._secDropTarget = -1
                                    unfinRef.preventStealing = true
                                })

                                _didDrag = false
                                _pressY = 0
                            }

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
                            Image { source: "icons/folder.ico"; width: 16; height: 16; sourceSize.width: 16; sourceSize.height: 16; fillMode: Image.PreserveAspectFit; smooth: true; mipmap: true; anchors.verticalCenter: parent.verticalCenter }
                            Text { text: "Finished"; color: root.selectedIndex === -2 ? "#88bbff" : "#cccccc"; font.pixelSize: 12; anchors.verticalCenter: parent.verticalCenter }
                        }
                        MouseArea {
                            id: finMa
                            anchors.fill: parent
                            hoverEnabled: true
                            preventStealing: true

                            property real _pressY:  0
                            property bool _didDrag: false

                            onPressed:  { _pressY = mouseY; _didDrag = false }

                            onPositionChanged: {
                                if (!(pressedButtons & Qt.LeftButton)) return
                                if (!root._secDragging && Math.abs(mouseY - _pressY) > 12) {
                                    root._secDragFrom = sectionDelegate.secIdx; root._secDragging = true; _didDrag = true
                                }
                                if (root._secDragging) {
                                    var posY = finMa.mapToItem(sidebarColumn, mouseX, mouseY).y
                                    var tgt = sectionRepeater.count
                                    for (var i = 0; i < sectionRepeater.count; i++) {
                                        var si = sectionRepeater.itemAt(i)
                                        if (si && posY < si.y + si.height / 2) { tgt = i; break }
                                    }
                                    root._secDropTarget = tgt
                                }
                            }

                            onReleased: {
                                var dragFrom = root._secDragFrom
                                var dragging = root._secDragging
                                var dropTarget = root._secDropTarget
                                var thisIdx = sectionDelegate.secIdx
                                var rootRef = root
                                var finRef = finMa

                                finMa.preventStealing = false

                                Qt.callLater(function() {
                                    if (thisIdx === dragFrom && dragging && dropTarget >= 0) {
                                        rootRef._applySectionReorder()
                                    }
                                    rootRef._secDragging = false
                                    rootRef._secDragFrom = -1
                                    rootRef._secDropTarget = -1
                                    finRef.preventStealing = true
                                })

                                _didDrag = false
                                _pressY = 0
                            }

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
                            width: parent.width
                            height: 28
                            color: grabberHeaderMa.containsMouse ? "#2a2a3a" : "transparent"

                            Row {
                                anchors { verticalCenter: parent.verticalCenter; left: parent.left; leftMargin: 4 }
                                spacing: 2
                                Text {
                                    text: root.grabberExpanded ? "▼" : "▶"
                                    color: "#999"
                                    font.pixelSize: 12
                                    width: 16
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                                Image {
                                    source: "icons/wand.ico"
                                    width: 16
                                    height: 16
                                    sourceSize.width: 16
                                    sourceSize.height: 16
                                    fillMode: Image.PreserveAspectFit
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                                Text {
                                    text: "Grabber Projects"
                                    color: "#cccccc"
                                    font.pixelSize: 12
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                            }

                            MouseArea {
                                id: grabberHeaderMa
                                anchors.fill: parent
                                hoverEnabled: true
                                preventStealing: true

                                property real _pressY: 0
                                property bool _didDrag: false

                                onPressed: { _pressY = mouseY; _didDrag = false }

                                onPositionChanged: {
                                    if (!(pressedButtons & Qt.LeftButton)) return
                                    if (!root._secDragging && Math.abs(mouseY - _pressY) > 12) {
                                        root._secDragFrom = sectionDelegate.secIdx
                                        root._secDragging = true
                                        _didDrag = true
                                    }
                                    if (root._secDragging) {
                                        var posY = grabberHeaderMa.mapToItem(sidebarColumn, mouseX, mouseY).y
                                        var tgt = sectionRepeater.count
                                        for (var i = 0; i < sectionRepeater.count; i++) {
                                            var si = sectionRepeater.itemAt(i)
                                            if (si && posY < si.y + si.height / 2) { tgt = i; break }
                                        }
                                        root._secDropTarget = tgt
                                    }
                                }

                                onReleased: {
                                    var dragFrom = root._secDragFrom
                                    var dragging = root._secDragging
                                    var dropTarget = root._secDropTarget
                                    var thisIdx = sectionDelegate.secIdx
                                    var rootRef = root
                                    var grabberRef = grabberHeaderMa

                                    grabberHeaderMa.preventStealing = false

                                    Qt.callLater(function() {
                                        if (thisIdx === dragFrom && dragging && dropTarget >= 0) {
                                            rootRef._applySectionReorder()
                                        }
                                        rootRef._secDragging = false
                                        rootRef._secDragFrom = -1
                                        rootRef._secDropTarget = -1
                                        grabberRef.preventStealing = true
                                    })

                                    _didDrag = false
                                    _pressY = 0
                                }

                                onClicked: {
                                    if (_didDrag) {
                                        _didDrag = false
                                        return
                                    }
                                    root.grabberExpanded = !root.grabberExpanded
                                }
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
                                     : (grabberProjectMa.containsMouse ? "#2a2a3a" : "transparent")
                                border.color: root.selectedIndex === -500 - index ? "#4488dd" : "transparent"
                                border.width: 1
                                opacity: (root._grabberDragging && root._grabberDragFrom === grabberProjectDelegate.modelRow) ? 0.4 : 1.0

                                Rectangle {
                                    visible: root._grabberDragging
                                          && root._grabberDropTarget === grabberProjectDelegate.modelRow
                                          && root._grabberDragFrom !== root._grabberDropTarget
                                          && root._grabberDragFrom !== root._grabberDropTarget - 1
                                    anchors { top: parent.top; left: parent.left; right: parent.right }
                                    height: 2
                                    color: "#4488dd"
                                    z: 10
                                }

                                Row {
                                    anchors { verticalCenter: parent.verticalCenter; left: parent.left; leftMargin: 22 }
                                    spacing: 5
                                    Image {
                                        source: "icons/folder.ico"
                                        width: 16
                                        height: 16
                                        sourceSize.width: 16
                                        sourceSize.height: 16
                                        fillMode: Image.PreserveAspectFit
                                    }
                                    Text {
                                        text: projectName || ""
                                        color: root.selectedIndex === -500 - index ? "#88bbff" : "#cccccc"
                                        font.pixelSize: 12
                                        anchors.verticalCenter: parent.verticalCenter
                                        elide: Text.ElideRight
                                        width: 126
                                    }
                                }

                                MouseArea {
                                    id: grabberProjectMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                                    cursorShape: root._grabberDragging ? Qt.ClosedHandCursor : Qt.PointingHandCursor
                                    preventStealing: true

                                    property real _pressY:  0
                                    property bool _didDrag: false

                                    onPressed:  { _pressY = mouseY; _didDrag = false }

                                    onPositionChanged: {
                                        if (!(pressedButtons & Qt.LeftButton)) return
                                        if (!root._grabberDragging && Math.abs(mouseY - _pressY) > 6) {
                                            root._grabberDragFrom = grabberProjectDelegate.modelRow
                                            root._grabberDragging = true; _didDrag = true
                                            grabberProjectMa.preventStealing = true
                                        }
                                        if (root._grabberDragging) {
                                            var cursorY = grabberProjectMa.mapToItem(sidebarColumn, mouseX, mouseY).y
                                            var target = App.grabberProjectModel.rowCount()
                                            for (var r = 0; r < App.grabberProjectModel.rowCount(); r++) {
                                                var del = grabberRepeater.itemAt(r)
                                                if (!del || del.height === 0) continue
                                                var delTop = del.mapToItem(sidebarColumn, 0, 0).y
                                                if (cursorY < delTop + del.height / 2) {
                                                    target = r
                                                    break
                                                }
                                            }
                                            root._grabberDropTarget = target
                                        }
                                    }

                                    onReleased: {
                                        var dragFrom = root._grabberDragFrom
                                        var dragging = root._grabberDragging
                                        var dropTarget = root._grabberDropTarget
                                        var thisRow = grabberProjectDelegate.modelRow
                                        var rootRef = root
                                        var maRef = grabberProjectMa

                                        grabberProjectMa.preventStealing = false

                                        Qt.callLater(function() {
                                            if (thisRow === dragFrom && dragging && dropTarget >= 0) {
                                                var toRow = (dragFrom < dropTarget) ? dropTarget - 1 : dropTarget
                                                if (dropTarget >= App.grabberProjectModel.rowCount())
                                                    toRow = App.grabberProjectModel.rowCount() - 1
                                                if (toRow !== dragFrom && toRow >= 0)
                                                    App.grabberProjectModel.moveProject(dragFrom, toRow)
                                            }
                                            rootRef._grabberDragging = false
                                            rootRef._grabberDragFrom = -1
                                            rootRef._grabberDropTarget = -1
                                            maRef.preventStealing = true
                                        })

                                        _didDrag = false
                                        _pressY = 0
                                    }

                                    onClicked: {
                                        if (mouse.button === Qt.RightButton) {
                                            root.selectedIndex = -500 - index
                                            root.grabberProjectSelected(projectId)
                                            grabberProjectContextMenu.projectId = projectId
                                            grabberProjectContextMenu.popup()
                                            _didDrag = false
                                            return
                                        }
                                        if (!_didDrag) {
                                            root.selectedIndex = -500 - index
                                            root.grabberProjectSelected(projectId)
                                        }
                                        _didDrag = false
                                    }
                                    onDoubleClicked: root.editGrabberProjectRequested(projectId)
                                }
                            }
                        }

                        Rectangle {
                            visible: root._grabberDragging
                                  && root._grabberDropTarget >= App.grabberProjectModel.rowCount()
                                  && root._grabberDragFrom !== App.grabberProjectModel.rowCount() - 1
                            width: parent.width
                            height: 2
                            color: "#4488dd"
                            z: 10
                        }
                    }

                    // ── Queues section ────────────────────────────────────────
                    Column {
                        id: queuesCol
                        visible: sectionDelegate.secId === "queues"
                        width: parent.width; spacing: 0

                        // Queues header
                        Rectangle {
                            width: parent.width; height: 28
                            color: root.selectedIndex === -999 ? "#1e3a6e" : (queueHeaderMa.containsMouse ? "#2a2a3a" : "transparent")
                            border.color: root.selectedIndex === -999 ? "#4488dd" : "transparent"; border.width: 1

                            Row {
                                anchors { verticalCenter: parent.verticalCenter; left: parent.left; leftMargin: 4 }
                                spacing: 2
                                Text { text: root.queuesExpanded ? "▼" : "▶"; color: "#999"; font.pixelSize: 12; width: 16; anchors.verticalCenter: parent.verticalCenter }
                                Image { width: 16; height: 16; sourceSize.width: 16; sourceSize.height: 16; fillMode: Image.PreserveAspectFit; source: "qrc:/qt/qml/com/stellar/app/app/qml/icons/queues.png"; anchors.verticalCenter: parent.verticalCenter }
                                Text { text: "Queues"; color: root.selectedIndex === -999 ? "#88bbff" : "#cccccc"; font.pixelSize: 12; anchors.verticalCenter: parent.verticalCenter }
                            }
                            MouseArea {
                                id: queueHeaderMa
                                anchors.fill: parent
                                hoverEnabled: true
                                preventStealing: true

                                property real _pressY:  0
                                property bool _didDrag: false

                                onPressed:  { _pressY = mouseY; _didDrag = false }

                                onPositionChanged: {
                                    if (!(pressedButtons & Qt.LeftButton)) return
                                    if (!root._secDragging && Math.abs(mouseY - _pressY) > 12) {
                                        root._secDragFrom = sectionDelegate.secIdx; root._secDragging = true; _didDrag = true
                                    }
                                    if (root._secDragging) {
                                        var posY = queueHeaderMa.mapToItem(sidebarColumn, mouseX, mouseY).y
                                        var tgt = sectionRepeater.count
                                        for (var i = 0; i < sectionRepeater.count; i++) {
                                            var si = sectionRepeater.itemAt(i)
                                            if (si && posY < si.y + si.height / 2) { tgt = i; break }
                                        }
                                        root._secDropTarget = tgt
                                    }
                                }

                                onReleased: {
                                    var dragFrom = root._secDragFrom
                                    var dragging = root._secDragging
                                    var dropTarget = root._secDropTarget
                                    var thisIdx = sectionDelegate.secIdx
                                    var rootRef = root
                                    var queueRef = queueHeaderMa

                                    queueHeaderMa.preventStealing = false

                                    Qt.callLater(function() {
                                        if (thisIdx === dragFrom && dragging && dropTarget >= 0) {
                                            rootRef._applySectionReorder()
                                        }
                                        rootRef._secDragging = false
                                        rootRef._secDragFrom = -1
                                        rootRef._secDropTarget = -1
                                        queueRef.preventStealing = true
                                    })

                                    _didDrag = false
                                    _pressY = 0
                                }

                                onClicked:       { root.selectedIndex = -999; root.queueSelected("queue_any") }
                                onDoubleClicked: root.queuesExpanded = !root.queuesExpanded
                            }
                        }

                        // Individual queue rows
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
                                        source: queueId === "main-download" ? "qrc:/qt/qml/com/stellar/app/app/qml/icons/main_queue.png"
                                              : queueId === "main-sync"     ? "qrc:/qt/qml/com/stellar/app/app/qml/icons/synch_queue.png"
                                              :                               "qrc:/qt/qml/com/stellar/app/app/qml/icons/custom_queue.png"
                                    }
                                    Text { text: queueName || ""; color: root.selectedIndex === -100 - index ? "#88bbff" : "#cccccc"; font.pixelSize: 12; anchors.verticalCenter: parent.verticalCenter }
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
                                            for (var i = 0; i < ids.length; i++) {
                                                App.setDownloadQueue(ids[i], queueId)
                                            }
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
