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

// Square 28px button showing an icon or a single glyph, with a tooltip naming
// the action. Keeps secondary actions (browse, add, remove) from eating row
// width that a text button's 80px minimum would take.
AbstractButton {
    id: control

    property url iconSource
    property string glyph
    property string toolTip

    implicitWidth: 28
    implicitHeight: 28
    hoverEnabled: true
    opacity: enabled ? 1.0 : 0.45

    background: Rectangle {
        radius: 3
        color: control.pressed ? ColorPalette.dividerBg
             : control.hovered ? ColorPalette.buttonSecondaryHoverBg
             : ColorPalette.buttonSecondaryBg
        border.color: ColorPalette.border
    }

    contentItem: Item {
        Image {
            anchors.centerIn: parent
            visible: control.iconSource.toString().length > 0
            source: control.iconSource
            sourceSize.width: 16
            sourceSize.height: 16
            width: 16
            height: 16
        }
        Text {
            anchors.centerIn: parent
            visible: control.glyph.length > 0
            text: control.glyph
            color: ColorPalette.textPrimary
            font.pixelSize: 15 * App.fontScale
            font.bold: true
        }
    }

    ThemedToolTip {
        visible: control.hovered && control.toolTip.length > 0
        text: control.toolTip
    }
}
