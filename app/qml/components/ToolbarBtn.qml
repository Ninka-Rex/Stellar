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
    property bool smallMode: false
    readonly property int iconSize: smallMode ? 20 : 32

    // Vertical layout is computed by the parent Toolbar (single source of truth so
    // the bar height and every button agree). iconTop = y of the icon box top;
    // textTop = y where the label starts. In small mode these are ignored and the
    // icon is simply centered.
    property int iconTop: 8
    property int textTop: 44

    implicitWidth: smallMode ? 48 : 84
    implicitHeight: smallMode ? 48 : 90

    // Dim the whole button when disabled so the user can see it won't respond.
    // AbstractButton has no built-in disabled appearance; we apply it here.
    opacity: root.enabled ? 1.0 : 0.35

    background: Rectangle {
        color: root.pressed ? ColorPalette.toolbarPressBg
             : root.hovered ? ColorPalette.toolbarHoverBg
             : "transparent"
        radius: 0
    }

    contentItem: Item {
        anchors.fill: parent

        Image {
            id: btnIcon
            // Small mode: icon centered. Otherwise icon top is the parent-supplied
            // iconTop, so every icon in the bar sits at the same Y (perfectly level).
            y: root.smallMode ? Math.round((root.height - root.iconSize) / 2) : root.iconTop
            anchors.horizontalCenter: parent.horizontalCenter
            source: root.iconSrc
            width: root.iconSize
            height: root.iconSize
            sourceSize.width: root.iconSize
            sourceSize.height: root.iconSize
            fillMode: Image.PreserveAspectFit
            smooth: false
            mipmap: false
            asynchronous: false
            cache: true
        }

        Text {
            id: btnLabel
            visible: !root.smallMode
            y: root.textTop
            anchors.horizontalCenter: parent.horizontalCenter
            width: root.width - 4
            text: root.label
            color: root.hovered ? ColorPalette.textHeader : ColorPalette.textPrimary
            font.pixelSize: 11 * App.fontScale
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            maximumLineCount: 2
            elide: Text.ElideRight
        }
    }

    ThemedToolTip {
        text: root.label
        visible: root.hovered
        delay: 600
    }
}
