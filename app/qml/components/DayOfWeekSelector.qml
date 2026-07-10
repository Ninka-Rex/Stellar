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

// Row of seven weekday toggle pills bound to a bitmask where bit
// (Qt::DayOfWeek - 1) is set: bit 0 = Monday … bit 6 = Sunday
// (matches Queue.scheduleDaysMask).
//
// Usage:
//   DayOfWeekSelector { daysMask: queue.scheduleDaysMask; onToggled: (m) => queue.scheduleDaysMask = m }
Row {
    id: root

    property int daysMask: 0x7F
    signal toggled(int newMask)

    spacing: 4

    Repeater {
        model: 7
        delegate: Rectangle {
            required property int index
            readonly property bool dayChecked: (root.daysMask & (1 << index)) !== 0

            width: Math.max(34, pillLabel.implicitWidth + 12)
            height: 24
            radius: 12
            color: dayChecked ? ColorPalette.accent
                              : (pillMouse.containsMouse ? ColorPalette.hoverBg : ColorPalette.inputBg)
            border.color: dayChecked ? ColorPalette.accent : ColorPalette.border
            border.width: 1

            Text {
                id: pillLabel
                anchors.centerIn: parent
                // Qt.locale().dayName takes Qt::DayOfWeek (1 = Monday) — same
                // numbering as the mask bits shifted by one.
                text: Qt.locale().dayName(index + 1, Locale.ShortFormat)
                color: dayChecked ? "#ffffff" : ColorPalette.textPrimary
                font.pixelSize: 11 * App.fontScale
            }

            MouseArea {
                id: pillMouse
                anchors.fill: parent
                hoverEnabled: true
                onClicked: root.toggled(root.daysMask ^ (1 << index))
            }
        }
    }
}
