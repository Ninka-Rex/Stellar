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

// Shared dialog button — single source of truth for button style across all dialogs.
// Master style taken from AddUrlDialog.qml.
//
// Usage:
//   DlgButton { text: "Cancel" }                    // secondary (grey)
//   DlgButton { text: "OK";      primary: true }    // primary   (blue)
//   DlgButton { text: "Delete";  destructive: true } // destructive (red)
Button {
    // Visual variant — at most one should be true; both false = secondary style.
    property bool primary:     false
    property bool destructive: false

    implicitWidth:  Math.max(80, contentItem.implicitWidth + 24)
    implicitHeight: 36
    opacity: enabled ? 1.0 : 0.55

    background: Rectangle {
        radius: 3
        border.width: 1
        color: {
            if (!parent.enabled) return "#2a2a2a"
            if (destructive) return parent.pressed ? "#a02828" : (parent.hovered ? "#9a2525" : "#8b2020")
            if (primary)     return parent.pressed ? "#254a8a" : (parent.hovered ? "#22429e" : "#1e3a6e")
            return parent.pressed ? "#484848" : (parent.hovered ? "#424242" : "#3a3a3a")
        }
        border.color: {
            if (!parent.enabled) return "#444444"
            if (destructive) return "#cc3333"
            if (primary)     return "#4488dd"
            return "#555555"
        }
    }

    contentItem: Text {
        text:               parent.text
        color:              !parent.enabled ? "#8e8e8e" : ((primary || destructive) ? "#ffffff" : "#d0d0d0")
        font.pixelSize:     13
        font.bold:          primary || destructive
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment:   Text.AlignVCenter
    }
}
