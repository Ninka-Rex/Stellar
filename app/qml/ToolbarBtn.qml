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

// IDM-style toolbar button: large icon on top, label below
AbstractButton {
    id: root
    property string label: ""
    property string iconSrc: ""
    
    width: 70
    height: 56

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

    ToolTip.text: root.label
    ToolTip.visible: root.hovered
    ToolTip.delay: 600
}
