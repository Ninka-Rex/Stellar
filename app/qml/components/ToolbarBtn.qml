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
    // Horizontal mode: icon on the left, text on the right (used by the grabber
    // toolbar). Mutually exclusive with the default stacked (icon-top) layout.
    property bool horizontalMode: false
    readonly property int iconSize: smallMode ? 20 : (horizontalMode ? 24 : 32)

    // Vertical layout is computed by the parent Toolbar (single source of truth so
    // the bar height and every button agree). iconTop = y of the icon box top;
    // textTop = y where the label starts. In small mode these are ignored and the
    // icon is simply centered.
    property int iconTop: 8
    property int textTop: 44

    implicitWidth: smallMode ? 48 : 84
    implicitHeight: smallMode ? 48 : (horizontalMode ? 40 : 90)

    // Track hover across the entire button bounds (not just where a child paints),
    // so the highlight fills the whole hitbox in every layout mode.
    hoverEnabled: true

    // Dim the whole button when disabled so the user can see it won't respond.
    // AbstractButton has no built-in disabled appearance; we apply it here.
    opacity: root.enabled ? 1.0 : 0.35

    // Full-bounds hover region. AbstractButton's built-in `hovered` only flips
    // where the contentItem actually paints, so in horizontal mode (a top-anchored
    // Row shorter than the button) the highlight band collapsed to text height.
    // This handler covers the whole button, giving a uniform hitbox.
    HoverHandler { id: _hover }

    background: Rectangle {
        color: root.pressed ? ColorPalette.toolbarPressBg
             : (root.hovered || _hover.hovered) ? ColorPalette.toolbarHoverBg
             : "transparent"
        radius: 0
    }

    contentItem: Item {
        anchors.fill: parent

        // ── Horizontal layout: icon left, label right ───────────────────────
        Row {
            visible: root.horizontalMode
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.leftMargin: 10
            spacing: 8

            Image {
                anchors.verticalCenter: parent.verticalCenter
                source: root.iconSrc
                width: root.iconSize
                height: root.iconSize
                sourceSize.width: root.iconSize
                sourceSize.height: root.iconSize
                fillMode: Image.PreserveAspectFit
                smooth: false
                mipmap: false
                cache: true
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                // Strip stacked-mode "\n" so the label reads on one logical line.
                text: root.label.replace("\n", " ")
                color: (root.hovered || _hover.hovered) ? ColorPalette.textHeader : ColorPalette.textPrimary
                font.pixelSize: 12 * App.fontScale
                verticalAlignment: Text.AlignVCenter
                wrapMode: Text.NoWrap
            }
        }

        // ── Stacked layout: icon top, label below ───────────────────────────
        Image {
            id: btnIcon
            visible: !root.horizontalMode
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
            visible: !root.smallMode && !root.horizontalMode
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
