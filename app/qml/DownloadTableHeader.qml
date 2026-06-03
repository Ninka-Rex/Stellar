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

// Table header for DownloadTable. Handles column sort, resize (DragHandler),
// and column reorder via drag. Right-click opens the column-visibility context
// menu (owned by the parent DownloadTable).

Rectangle {
    id: header
    anchors { top: parent ? parent.top : undefined; left: parent ? parent.left : undefined; right: parent ? parent.right : undefined }
    height: 26
    color: ColorPalette.dividerBg
    clip: true

    required property var table        // DownloadTable root
    required property var tableView    // the ListView (for contentX)
    required property var colCtxMenu   // column-visibility context menu

    Row {
        id: headerRow
        x: -tableView.contentX
        width: table.visibleContentWidth
        height: parent.height

        Repeater {
            id: headerCellRepeater
            model: table.visibleCols
            delegate: Rectangle {
                id: headerCell
                width:  table.colWidth(modelData.key)
                height: parent.height
                readonly property bool isSortable: table._sortableKeys.indexOf(modelData.key) >= 0
                readonly property bool isActive:   table.sortKey === modelData.key
                color: (isSortable && headerCellMouse.containsMouse && !table._colDragging) ? ColorPalette.border : "transparent"
                opacity: (table._colDragging && table._colDragFromKey === modelData.key) ? 0.5 : 1.0

                // Drop insert-line LEFT of this column when it is the target
                Rectangle {
                    visible: table._colDragging && table._colDragInsertBeforeKey === modelData.key
                    width: 2; height: parent.height
                    anchors.left: parent.left
                    color: "#4488dd"
                    z: 20
                }

                // Insert-line at the very END of the header (right edge of last visible col)
                Rectangle {
                    visible: table._colDragging
                          && table._colDragInsertBeforeKey === "__end__"
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
                    color: headerCell.isActive ? ColorPalette.accent : ColorPalette.textPrimary
                    font.pixelSize: 12 * App.fontScale
                    font.bold: true
                    horizontalAlignment: modelData.key === "queue" ? Text.AlignHCenter : Text.AlignLeft
                    elide: Text.ElideRight
                }

                Text {
                    id: sortIndicator
                    anchors { verticalCenter: parent.verticalCenter; right: resizeHandle.left; rightMargin: 4 }
                    text: table.sortAscending ? "▲" : "▼"
                    color: "#88bbff"
                    font.pixelSize: 9 * App.fontScale
                    visible: headerCell.isActive
                }

                // ── Sort click + column reorder drag ─────────────────────
                MouseArea {
                    id: headerCellMouse
                    anchors { fill: parent; rightMargin: 10 }
                    hoverEnabled: true
                    preventStealing: true
                    cursorShape: table._colDragging ? Qt.ClosedHandCursor
                               : (headerCell.isSortable ? Qt.PointingHandCursor : Qt.ArrowCursor)

                    property real _pressX:  0
                    property bool _didDrag: false

                    onPressed:  { _pressX = mouseX; _didDrag = false }

                    onPositionChanged: {
                        if (!(pressedButtons & Qt.LeftButton)) return
                        if (!table._colDragging && Math.abs(mouseX - _pressX) > 8) {
                            table._colDragFromKey = modelData.key
                            table._colDragging = true
                            _didDrag = true
                        }
                        if (table._colDragging && table._colDragFromKey === modelData.key) {
                            var cursorX = headerCellMouse.mapToItem(headerRow, mouseX, 0).x
                            var insertBefore = "__end__"
                            var xAcc = 0
                            for (var i = 0; i < table.visibleCols.length; i++) {
                                var colW = table.colWidth(table.visibleCols[i].key)
                                if (cursorX < xAcc + colW / 2) {
                                    insertBefore = table.visibleCols[i].key
                                    break
                                }
                                xAcc += colW
                            }
                            table._colDragInsertBeforeKey = insertBefore
                        }
                    }

                    onReleased: {
                        var didDrag = _didDrag
                        var tbl = table

                        Qt.callLater(function() {
                            if (didDrag) tbl._applyColReorder()
                            tbl._colDragging = false
                            tbl._colDragFromKey = ""
                            tbl._colDragInsertBeforeKey = ""
                        })

                        _didDrag = false
                        _pressX = 0
                    }

                    onClicked: {
                        if (!_didDrag && headerCell.isSortable) table.applySort(modelData.key)
                        _didDrag = false
                    }
                }

                // ── Column separator ─────────────────────────────────────
                Rectangle {
                    anchors.right: parent.right
                    width: 1; height: parent.height
                    color: ColorPalette.border
                }

                // ── Column resize handle ─────────────────────────────────
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
                                table._resizingColumnKey = modelData.key
                                table._resizingColumnWidth = resizeHandle._startWidthPx
                                return
                            }

                            if (table._resizingColumnKey === modelData.key) {
                                var defs = table.columnDefs.slice()
                                for (var j = 0; j < defs.length; j++) {
                                    if (defs[j].key === modelData.key) {
                                        defs[j] = Object.assign({}, defs[j], { widthPx: table._resizingColumnWidth })
                                        break
                                    }
                                }
                                table._resizingColumnKey = ""
                                table._resizingColumnWidth = 0
                                table.columnDefs = defs
                            }
                        }

                        onTranslationChanged: {
                            if (!active) return
                            table._resizingColumnWidth = Math.max(table.minColWidth(modelData.key),
                                Math.round(resizeHandle._startWidthPx + translation.x))
                            table.visibleContentWidth = table.totalVisibleWidth()
                        }
                    }
                }
            }
        }
    }

    // Right-click opens column-visibility menu
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.RightButton
        onClicked: colCtxMenu.popup()
    }

    // Bottom border
    Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: ColorPalette.border }
}
