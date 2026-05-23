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

// Reusable MouseArea for section reorder drag in Sidebar.
// Encapsulates the 50-line pattern that was duplicated 6 times
// (All Downloads, Unfinished, Finished, Grabber, Torrents, Queues headers).

MouseArea {
    id: handler
    anchors.fill: parent
    hoverEnabled: true
    preventStealing: true

    // Index of this section within the sectionRepeater
    required property int sectionIndex
    // References to enclosing-scope objects in Sidebar.qml
    required property var sidebarRoot
    required property var sidebarColumn
    required property var sectionRepeater

    // MouseArea provides `clicked` / `doubleClicked` natively. Do NOT redeclare —
    // redeclaring shadows the built-ins so external `onClicked:` handlers in
    // Sidebar.qml never receive any event.

    property real _pressY: 0
    property bool _didDrag: false

    onPressed: { _pressY = mouseY; _didDrag = false }

    onPositionChanged: {
        if (!(pressedButtons & Qt.LeftButton)) return
        if (!sidebarRoot._secDragging && Math.abs(mouseY - _pressY) > 12) {
            sidebarRoot._secDragFrom = sectionIndex
            sidebarRoot._secDragging = true
            _didDrag = true
        }
        if (sidebarRoot._secDragging) {
            // Map cursor into sidebarColumn space and find the section whose
            // midpoint the cursor is above. Default to past-the-end (repeater.count)
            // when the cursor is below all sections.
            var posY = handler.mapToItem(sidebarColumn, mouseX, mouseY).y
            var tgt = sectionRepeater.count
            for (var i = 0; i < sectionRepeater.count; i++) {
                var si = sectionRepeater.itemAt(i)
                if (si && posY < si.y + si.height / 2) { tgt = i; break }
            }
            sidebarRoot._secDropTarget = tgt
        }
    }

    onReleased: {
        var dragFrom = sidebarRoot._secDragFrom
        var dragging = sidebarRoot._secDragging
        var dropTarget = sidebarRoot._secDropTarget
        var thisIdx = sectionIndex
        var rootRef = sidebarRoot
        var handlerRef = handler

        handler.preventStealing = false

        Qt.callLater(function() {
            if (thisIdx === dragFrom && dragging && dropTarget >= 0)
                rootRef._applySectionReorder()
            rootRef._secDragging = false
            rootRef._secDragFrom = -1
            rootRef._secDropTarget = -1
            handlerRef.preventStealing = true
        })

        _didDrag = false
        _pressY = 0
    }
}
