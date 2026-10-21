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

// Read-only, selectable single-line value in an input-style box (paths, hashes)
// so the user can select and copy part of it.
Rectangle {
    property alias fieldText: ti.text
    property color textColor: ColorPalette.textPrimary

    implicitHeight: 26
    color: ColorPalette.inputBg
    border.color: ti.activeFocus ? ColorPalette.borderFocus : ColorPalette.border
    radius: 2
    clip: true

    TextInput {
        id: ti
        anchors { fill: parent; leftMargin: 6; rightMargin: 6 }
        verticalAlignment: TextInput.AlignVCenter
        color: parent.textColor
        font.pixelSize: 12 * App.fontScale
        readOnly: true; selectByMouse: true; clip: true
    }
}
