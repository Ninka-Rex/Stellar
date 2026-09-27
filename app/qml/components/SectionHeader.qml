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

// Group title followed by a hairline rule that runs to the right edge. Used to
// divide property sheets (torrent General / Settings tabs) without boxing each
// group in its own bordered card.
RowLayout {
    property alias text: label.text
    // Settings sections use the same title-plus-rule shape at a larger size.
    property alias font: label.font
    property alias color: label.color

    Layout.fillWidth: true
    spacing: 8

    Text {
        id: label
        color: ColorPalette.textSecond
        font.pixelSize: 11 * App.fontScale
        font.bold: true
    }
    Rectangle {
        Layout.fillWidth: true
        Layout.alignment: Qt.AlignVCenter
        implicitHeight: 1
        color: ColorPalette.border
    }
}
