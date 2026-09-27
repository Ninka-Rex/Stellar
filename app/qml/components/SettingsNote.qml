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

// Boxed note for things that need more attention than a hint: what to install,
// or a caveat about a risky option (`warning: true`).
Rectangle {
    id: root

    property string text
    property bool warning: false

    Layout.fillWidth: true
    implicitHeight: label.implicitHeight + 16
    color: ColorPalette.infoBoxBg
    border.color: ColorPalette.infoBoxBorder
    radius: 3

    Text {
        id: label
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 8 }
        text: root.text
        color: root.warning ? ColorPalette.warningText : ColorPalette.infoBoxText
        font.pixelSize: 11 * App.fontScale
        wrapMode: Text.WordWrap
    }
}
