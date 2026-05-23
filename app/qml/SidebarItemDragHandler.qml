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

// Reusable MouseArea for item reorder drag within a sidebar section
// (categories, grabber projects, torrent subcategories).
// Encapsulates the ~75-line pattern duplicated 3 times.
//
// Drag state lives in a QtObject on the Sidebar root so insert-line
// indicators in delegates can bind to it. This component reads/writes
// that state.

MouseArea {
    id: handler
    anchors.fill: parent
    hoverEnabled: true
    preventStealing: true

    // ── Required properties ────────────────────────────────────────────────
    required property int    rowIndex
    required property var   dragState     // QtObject { dragging, dragFrom, dropTarget }
    required property var   repeater      // Repeater whose children we iterate
    required property int    rowCount     // total number of rows
    required property var   sidebarColumn // column for coordinate mapping

    // applyReorder(fromRow, dropTarget): called on successful drop.
    // Parent implements the model-specific move logic.
    required property var   applyReorder

    // ── Optional overrides ──────────────────────────────────────────────────
    property int acceptedButtons: Qt.LeftButton
    property int dragThreshold: 6

    // cursor shape while dragging (read from dragState)
    cursorShape: dragState.dragging ? Qt.ClosedHandCursor : Qt.PointingHandCursor

    // NOTE: do NOT redeclare `clicked` / `doubleClicked` — MouseArea provides
    // them. Redeclaring shadows the built-ins and silently breaks external
    // `onClicked:` handlers.

    // ── Internal state ──────────────────────────────────────────────────────
    property real _pressY: 0
    property bool _didDrag: false

    onPressed: function(mouse) {
        _pressY = mouseY || mouse.y
        _didDrag = false
    }

    onPositionChanged: function(mouse) {
        if (!(pressedButtons & Qt.LeftButton)) return
        if (!dragState.dragging && Math.abs(mouseY - _pressY) > dragThreshold) {
            dragState.dragFrom = rowIndex
            dragState.dragging = true
            _didDrag = true
            handler.preventStealing = true
        }
        if (dragState.dragging) {
            var cursorY = handler.mapToItem(sidebarColumn, mouseX, mouseY).y
            var target = rowCount
            for (var r = 0; r < rowCount; r++) {
                var del = repeater.itemAt(r)
                if (!del || del.height === 0) continue
                var delTop = del.mapToItem(sidebarColumn, 0, 0).y
                if (cursorY < delTop + del.height / 2) { target = r; break }
            }
            dragState.dropTarget = target
        }
    }

    onReleased: {
        var dragFrom = dragState.dragFrom
        var dragging = dragState.dragging
        var dropTarget = dragState.dropTarget
        var thisRow = rowIndex
        var stateRef = dragState
        var handlerRef = handler
        var applyFn = applyReorder

        handler.preventStealing = false

        Qt.callLater(function() {
            if (thisRow === dragFrom && dragging && dropTarget >= 0)
                applyFn(dragFrom, dropTarget)
            stateRef.dragging = false
            stateRef.dragFrom = -1
            stateRef.dropTarget = -1
            handlerRef.preventStealing = true
        })

        _didDrag = false
        _pressY = 0
    }
}
