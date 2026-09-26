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
import QtQuick.Layouts

// Muted key label of a property-sheet row (torrent General / Settings tabs).
// One shared minimum width keeps the value column aligned across rows and
// groups; a longer translation widens only its own row instead of clipping.
Text {
    readonly property real sheetKeyWidth: 84 * App.fontScale

    color: ColorPalette.textSecond
    font.pixelSize: 12 * App.fontScale
    Layout.preferredWidth: Math.max(sheetKeyWidth, implicitWidth)
    Layout.alignment: Qt.AlignVCenter
}
