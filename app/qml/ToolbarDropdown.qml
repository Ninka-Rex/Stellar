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

// ── IDM-style split toolbar button: icon + label on left portion, small arrow ──
// on the right that opens a queue-picker menu. Clicking the main area fires
// queueSelected with an empty string (caller treats as "default queue").
Item {
    id: root
    property string label: ""
    property string iconSrc: ""
    property var queueModel: null
    property bool smallMode: false

    signal queueSelected(string queueId)

    function visibleQueues() {
        var queues = []
        if (!root.queueModel)
            return queues

        for (var row = 0; row < root.queueModel.rowCount(); ++row) {
            var queue = root.queueModel.queueAt(row)
            if (!queue || queue.id === "download-limits")
                continue
            queues.push({
                queueId: queue.id,
                queueName: queue.name || ""
            })
        }
        return queues
    }

    // ── Arrow chevron width fixed regardless of button size ──────────────
    readonly property int _arrowW: smallMode ? 14 : 18
    readonly property int _iconSize: smallMode ? 20 : 32

    // ── Main click area (left portion) ───────────────────────────────────
    Rectangle {
        id: mainArea
        anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
        width: parent.width - _arrowW - 1   // -1 for divider
        color: mainHover.pressed ? ColorPalette.toolbarPressBg
             : mainHover.containsMouse ? ColorPalette.toolbarHoverBg
             : "transparent"

        // Icon Y pinned to single-line group height (same as ToolbarBtn) so a
        // 2-line label extends downward instead of pushing the icon up.
        readonly property int _gap: 4
        // Fixed top padding (matches ToolbarBtn): icons level, label grows downward.
        readonly property int _topPad: root.smallMode ? Math.max(0, Math.round((root.height - root._iconSize) / 2)) : 6

        Image {
            id: btnIcon
            y: mainArea._topPad
            anchors.horizontalCenter: parent.horizontalCenter
            source: root.iconSrc
            width: root._iconSize; height: root._iconSize
            sourceSize.width: root._iconSize; sourceSize.height: root._iconSize
            fillMode: Image.PreserveAspectFit
            smooth: false; mipmap: false; asynchronous: false; cache: true
        }

        Text {
            id: lbl
            visible: !root.smallMode
            y: btnIcon.y + btnIcon.height + mainArea._gap
            anchors.horizontalCenter: parent.horizontalCenter
            width: parent.width - 4
            text: root.label
            color: mainHover.containsMouse ? ColorPalette.textHeader : ColorPalette.textPrimary
            font.pixelSize: 11 * App.fontScale
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            maximumLineCount: 2
            elide: Text.ElideRight
        }

        MouseArea {
            id: mainHover
            anchors.fill: parent
            hoverEnabled: true
            onClicked: menu.popup(0, root.height)
        }
    }

    // ── Divider between main area and arrow (only visible on hover) ──────
    Rectangle {
        anchors { top: parent.top; bottom: parent.bottom }
        anchors.topMargin: 8; anchors.bottomMargin: 8
        x: mainArea.width
        width: 1
        color: ColorPalette.border
        visible: mainHover.containsMouse || arrowHover.containsMouse
    }

    // ── Arrow drop zone (right portion) ──────────────────────────────────
    Rectangle {
        id: arrowArea
        anchors { right: parent.right; top: parent.top; bottom: parent.bottom }
        width: _arrowW
        color: arrowHover.pressed ? ColorPalette.toolbarPressBg
             : arrowHover.containsMouse ? ColorPalette.toolbarHoverBg
             : "transparent"

        Text {
            anchors.centerIn: parent
            text: "▾"
            color: arrowHover.containsMouse ? ColorPalette.textHeader : ColorPalette.textSecond
            font.pixelSize: smallMode ? 9 : 11
        }

        MouseArea {
            id: arrowHover
            anchors.fill: parent
            hoverEnabled: true
            onClicked: menu.popup(0, root.height)
        }
    }

    ToolTip.text: root.label
    ToolTip.visible: mainHover.containsMouse || arrowHover.containsMouse
    ToolTip.delay: 600

    Menu {
        id: menu
        y: root.height
        topPadding: 0
        bottomPadding: 0
        padding: 0

        Instantiator {
            model: root.visibleQueues()

            delegate: MenuItem {
                required property var modelData
                text: modelData.queueName
                onTriggered: root.queueSelected(modelData.queueId)
            }

            onObjectAdded: function(index, object) {
                menu.insertItem(index, object)
            }

            onObjectRemoved: function(index, object) {
                menu.removeItem(object)
                object.destroy()
            }
        }
    }
}
