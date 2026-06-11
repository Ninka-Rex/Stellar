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

// Theme-aware CheckBox with an explicit indicator so the box is always
// visible in both light and dark mode (Material's default unchecked box
// renders as a near-invisible faint outline in light mode).
CheckBox {
    id: root
    topPadding: 0
    bottomPadding: 0
    // Fill the parent layout so long (translated) labels wrap instead of
    // overflowing the dialog. Harmlessly ignored when not in a Layout.
    Layout.fillWidth: true
    indicator: Rectangle {
        implicitWidth: 16
        implicitHeight: 16
        x: root.leftPadding
        y: parent.height / 2 - height / 2
        radius: 3
        color: root.checked ? ColorPalette.accent : ColorPalette.inputBg
        border.color: root.checked ? ColorPalette.accent : ColorPalette.border
        border.width: 1
        Text {
            anchors.centerIn: parent
            text: "✓"
            visible: root.checked
            color: "#ffffff"
            font.pixelSize: 11
            font.bold: true
        }
    }
    contentItem: Text {
        text: root.text
        color: root.enabled ? ColorPalette.textPrimary : ColorPalette.textDisabled
        font.pixelSize: 13 * App.fontScale
        verticalAlignment: Text.AlignVCenter
        wrapMode: Text.WordWrap
        leftPadding: root.indicator.width + 6
    }
}
