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
import QtQuick.Templates as T

T.MenuItem {
    implicitHeight: 22
    implicitWidth:  Math.max(contentItem.implicitWidth + leftPadding + rightPadding, 140)
    leftPadding:    0
    rightPadding:   8
    topPadding:     0
    bottomPadding:  0

    contentItem: Text {
        text:    parent.text
        color:   parent.enabled ? (parent.highlighted ? "#ffffff" : "#d0d0d0") : "#666666"
        font.pixelSize: 12
        verticalAlignment: Text.AlignVCenter
        leftPadding: 12
    }

    background: Rectangle {
        implicitHeight: 22
        implicitWidth:  140
        color: parent.highlighted ? "#1e3a6e" : "transparent"
    }
}
