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

// Value of a property-sheet row, paired with SheetKey. Plain text because torrent
// metadata is untrusted, so never rich text; elides instead of pushing the grid
// wider.
Text {
    color: ColorPalette.textPrimary
    font.pixelSize: 12 * App.fontScale
    textFormat: Text.PlainText
    elide: Text.ElideRight
    Layout.fillWidth: true
    // Equal preferred widths make the fill columns split evenly.
    Layout.preferredWidth: 100
}
