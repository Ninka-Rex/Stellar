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
    // Path relative to the icons folder ("actions/help-about.svg"), resolved
    // here like FileCtxMenuItem does: Qt 6 resolves a relative url against the
    // component that uses it (this file, in components/), not the one that set it.
    property string iconSrc: ""
    readonly property bool hasIcon: iconSrc.length > 0
    // Right-aligned muted state ("On") for toggle rows, instead of a check mark.
    property string statusText: ""
    signal clicked()

    width: parent ? parent.width : 180
    height: 28
    color: ma.containsMouse && root.enabled ? ColorPalette.hoverBg : "transparent"

    Image {
        id: icon
        anchors { verticalCenter: parent.verticalCenter; left: parent.left; leftMargin: 10 }
        source: root.hasIcon ? "../icons/" + root.iconSrc : ""
        sourceSize: Qt.size(14, 14)
        opacity: root.enabled ? 1.0 : 0.4
        width: 14; height: 14
        visible: root.hasIcon
        fillMode: Image.PreserveAspectFit
    }

    Text {
        anchors { verticalCenter: parent.verticalCenter; left: parent.left; leftMargin: root.hasIcon ? 30 : 12
                  right: status.left; rightMargin: 8 }
        text: root.label
        color: root.enabled ? ColorPalette.textPrimary : ColorPalette.textDisabled
        font.pixelSize: 12 * App.fontScale
        font.bold: root.bold
        elide: Text.ElideRight
    }

    Text {
        id: status
        anchors { verticalCenter: parent.verticalCenter; right: parent.right; rightMargin: 12 }
        text: root.statusText
        color: ColorPalette.textMuted
        font.pixelSize: 11 * App.fontScale
    }

    MouseArea {
        id: ma
        anchors.fill: parent
        hoverEnabled: true
        enabled: root.enabled
        onClicked: root.clicked()
    }
}
