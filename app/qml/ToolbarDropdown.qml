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

    // Supplied by parent Toolbar so this matches ToolbarBtn's icon/text Y exactly.
    property int iconTop: 8
    property int textTop: 44

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

    // ── Single highlight spanning the whole button ──────────────────────
    // One background behind both click zones so hover/press is one continuous
    // blue box (no internal gap or divider line).
    Rectangle {
        anchors.fill: parent
        color: (mainHover.pressed || arrowHover.pressed) ? ColorPalette.toolbarPressBg
             : (mainHover.containsMouse || arrowHover.containsMouse) ? ColorPalette.toolbarHoverBg
             : "transparent"
    }

    // ── Main click area (left portion) ───────────────────────────────────
    Item {
        id: mainArea
        anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
        width: parent.width - _arrowW

        MouseArea {
            id: mainHover
            anchors.fill: parent
            hoverEnabled: true
            onClicked: menu.popup(0, root.height)
        }
    }

    // Icon + label centered on the WHOLE button (not the narrower main click
    // area) so they match a plain ToolbarBtn. Kept outside mainArea — they are
    // purely visual; mainArea/arrowArea own the click handling. Using the full
    // button width gives the label the same room as ToolbarBtn, so wider fonts
    // (Linux) don't wrap "Start Queue" onto a clipped second line.
    Image {
        id: btnIcon
        y: root.smallMode ? Math.round((root.height - root._iconSize) / 2) : root.iconTop
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
        // Above the arrow zone so its hover background never paints over the
        // right end of the label (was clipping "...ue" on "Start Queue").
        z: 1
        y: root.textTop
        anchors.horizontalCenter: parent.horizontalCenter
        width: root.width - 4
        text: root.label
        color: mainHover.containsMouse ? ColorPalette.textHeader : ColorPalette.textPrimary
        font.pixelSize: 11 * App.fontScale
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
        maximumLineCount: 2
        elide: Text.ElideRight
    }

    // ── Arrow drop zone (right portion) ──────────────────────────────────
    // Transparent — the single full-width highlight behind it supplies the
    // background; no divider line so the box reads as one continuous blue box.
    Item {
        id: arrowArea
        anchors { right: parent.right; top: parent.top; bottom: parent.bottom }
        width: _arrowW

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

    ThemedToolTip {
        text: root.label
        visible: mainHover.containsMouse || arrowHover.containsMouse
        delay: 600
    }

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
