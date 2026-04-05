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

    width: 70
    height: 70

    background: Rectangle {
        color: root.pressed ? "#3a3a4a"
             : root.hovered ? "#2d2d3d"
             : "transparent"
        radius: 0
    }

    contentItem: Column {
        anchors.centerIn: parent
        spacing: 4

        Image {
            anchors.horizontalCenter: parent.horizontalCenter
            source: root.iconSrc
            width: 32
            height: 32
            fillMode: Image.PreserveAspectFit
            smooth: true
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.label
            color: root.hovered ? "#ffffff" : "#d0d0d0"
            font.pixelSize: 11
            horizontalAlignment: Text.AlignHCenter
        }
    }

    onClicked: menu.popup(0, height)

    ToolTip.text: root.label
    ToolTip.visible: root.hovered
    ToolTip.delay: 600

    Menu {
        id: menu
        y: root.height

        Repeater {
            model: root.queueModel
            delegate: MenuItem {
                visible: queueId !== "download-limits"
                text: queueName || ""
                onTriggered: root.queueSelected(queueId)
            }
        }
    }
}
