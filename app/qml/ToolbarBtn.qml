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

    implicitWidth: smallMode ? 48 : 84
    implicitHeight: smallMode ? 48 : 86

    // Dim the whole button when disabled so the user can see it won't respond.
    // AbstractButton has no built-in disabled appearance; we apply it here.
    opacity: root.enabled ? 1.0 : 0.35

    background: Rectangle {
        color: root.pressed ? ColorPalette.toolbarPressBg
             : root.hovered ? ColorPalette.toolbarHoverBg
             : "transparent"
        radius: 0
    }

    // Icon Y is pinned using the SINGLE-LINE group height, so it sits at the
    // ── same vertical spot whether the label is 1 or 2 lines. A wrapped (2-line) ──
    // label just extends downward instead of shoving the icon up. This keeps every
    // ── toolbar icon level across languages with longer translated labels. ──
    contentItem: Item {
        anchors.fill: parent

        readonly property int _gap: 4
        // Fixed top padding: every icon sits the same distance below the menubar,
        // so all icons are level. The label hangs below the icon and grows downward
        // when it wraps to 2 lines -- the bar is tall enough to hold 2 lines with
        // matching bottom padding (see Toolbar.qml height). Not centered, because
        // centering a 2-line-reserve group makes 1-line buttons float high while
        // 2-line text touches the bottom edge.
        readonly property int _topPad: root.smallMode ? Math.max(0, Math.round((root.height - root.iconSize) / 2)) : 6

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
            visible: !root.smallMode
            y: btnIcon.y + btnIcon.height + parent._gap
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

    ToolTip.text: root.label
    ToolTip.visible: root.hovered
    ToolTip.delay: 600
}
