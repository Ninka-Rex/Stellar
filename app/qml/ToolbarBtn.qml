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
    property int iconSize: 32
    
    width: 84
    height: 72

    // Dim the whole button when disabled so the user can see it won't respond.
    // AbstractButton has no built-in disabled appearance; we apply it here.
    opacity: root.enabled ? 1.0 : 0.35

    background: Rectangle {
        color: root.pressed ? "#3a3a4a"
             : root.hovered ? "#2d2d3d"
             : "transparent"
        radius: 0
    }

    // Center icon + label as a single group. Label sizes to its actual content
    // height (1 or 2 lines), so padding above icon ≈ padding below text. When
    // a label wraps to 2 lines (e.g. long translations), the whole group is
    // still centered — the icon shifts up by half the extra line height,
    // which is the only way to keep top/bottom whitespace equal.
    contentItem: Item {
        anchors.fill: parent

        readonly property int _gap: 4
        readonly property int _groupH: root.iconSize + _gap + btnLabel.contentHeight
        readonly property int _topPad: Math.max(0, Math.round((root.height - _groupH) / 2))

        Image {
            id: btnIcon
            y: parent._topPad
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

    ToolTip.text: root.label
    ToolTip.visible: root.hovered
    ToolTip.delay: 600
}
