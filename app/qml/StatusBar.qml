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

Rectangle {
    id: root
    height: 22
    color: "#1a1a1a"

    property int activeCount: 0

    // top border
    Rectangle { anchors.top: parent.top; width: parent.width; height: 1; color: "#3a3a3a" }

    RowLayout {
        anchors { fill: parent; leftMargin: 8; rightMargin: 8; topMargin: 1 }
        spacing: 20

        Text {
            text: activeCount > 0 ? "%1 file(s) downloading".arg(activeCount) : "Ready"
            color: "#a0a0a0"
            font.pixelSize: 11
        }

        Item { Layout.fillWidth: true }

        Text {
            visible: App.minutesUntilNextQueue > 0
            text: App.minutesUntilNextQueue === 1
                ? "Queue runs in 1 minute"
                : "Queue runs in %1 minutes".arg(App.minutesUntilNextQueue)
            color: "#a0a0a0"
            font.pixelSize: 11
        }
    }
}
