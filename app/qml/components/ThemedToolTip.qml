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

// Theme-aware tooltip. Qt's default ToolTip ignores ColorPalette and is always
// dark, which looks wrong in light mode. Use this anywhere a plain ToolTip would
// otherwise leak the built-in dark style.
ToolTip {
    id: control
    delay: 600
    padding: 6

    contentItem: Text {
        text: control.text
        color: ColorPalette.tooltipText
        font.pixelSize: 12 * App.fontScale
        wrapMode: Text.WordWrap
    }

    background: Rectangle {
        color: ColorPalette.tooltipBg
        border.color: ColorPalette.tooltipBorder
        border.width: 1
        radius: 3
    }
}
