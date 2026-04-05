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

Rectangle {
    id: root
    property string label: ""
    property bool bold: false
    signal clicked()

    width: parent ? parent.width : 180
    height: 28
    color: ma.containsMouse ? "#3a3a5a" : "transparent"

    Text {
        anchors { verticalCenter: parent.verticalCenter; left: parent.left; leftMargin: 12 }
        text: root.label
        color: "#e0e0e0"
        font.pixelSize: 12
        font.bold: root.bold
    }

    MouseArea {
        id: ma
        anchors.fill: parent
        hoverEnabled: true
        onClicked: root.clicked()
    }
}
