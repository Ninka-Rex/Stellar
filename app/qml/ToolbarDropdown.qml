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

AbstractButton {
    id: root
    property string label: ""
    property string iconSrc: ""
    property var queueModel: null

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

    width: 84
    height: 72

    background: Rectangle {
        color: root.pressed ? "#3a3a4a"
             : root.hovered ? "#2d2d3d"
             : "transparent"
        radius: 0
    }

    // Fixed-position layout matching ToolbarBtn — icon and label anchored to
    // absolute slots so wrapping or locale changes don't shift the icon.
    // Center icon + label as a single group; label sizes to content height.
    contentItem: Item {
        anchors.fill: parent

        readonly property int _iconSize: 32
        readonly property int _gap: 4
        readonly property int _groupH: _iconSize + _gap + btnLabel.contentHeight
        readonly property int _topPad: Math.max(0, Math.round((root.height - _groupH) / 2))

        Image {
            id: btnIcon
            y: parent._topPad
            anchors.horizontalCenter: parent.horizontalCenter
            source: root.iconSrc
            width: parent._iconSize
            height: parent._iconSize
            sourceSize.width: parent._iconSize
            sourceSize.height: parent._iconSize
            fillMode: Image.PreserveAspectFit
            smooth: true
        }

        Text {
            id: btnLabel
            y: btnIcon.y + btnIcon.height + parent._gap
            anchors.horizontalCenter: parent.horizontalCenter
            width: root.width - 4
            text: root.label
            color: root.hovered ? "#ffffff" : "#d0d0d0"
            font.pixelSize: 11 * App.fontScale
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            maximumLineCount: 2
            elide: Text.ElideRight
        }
    }

    onClicked: menu.popup(0, height)

    ToolTip.text: root.label
    ToolTip.visible: root.hovered
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
