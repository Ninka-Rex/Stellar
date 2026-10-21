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

// Flat text action at the right end of a tab strip (">> Send to Tray",
// "Details"): muted label, accent on hover. A `checkable` action shows its on
// state like a selected tab — primary text with the accent underline.
Item {
    id: action

    property alias text: label.text
    property string toolTip: ""
    property bool checkable: false
    property bool checked: false
    signal clicked()

    implicitWidth: label.implicitWidth + 20
    implicitHeight: parent ? parent.height : 30

    readonly property bool _on: checkable && checked

    Text {
        id: label
        anchors.centerIn: parent
        color: actionMa.containsMouse ? ColorPalette.accent
             : (action._on ? ColorPalette.textHeader : ColorPalette.textMuted)
        font.pixelSize: 12 * App.fontScale
    }

    Rectangle {
        visible: action._on
        anchors { bottom: parent.bottom; horizontalCenter: parent.horizontalCenter }
        width: label.implicitWidth + 8
        height: 2
        color: ColorPalette.accent
    }

    MouseArea {
        id: actionMa
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: action.clicked()
    }

    ThemedToolTip {
        visible: actionMa.containsMouse && action.toolTip.length > 0
        text: action.toolTip
        delay: 400
    }
}
