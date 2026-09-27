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

// StyledComboBox sized for settings rows. `value` is the selected index and is
// one-way like SettingsCheck.checked: bind it to the owner's state and write
// the state back in onEdited. Picking an item would otherwise break the
// currentIndex binding, so a later reset would leave the old choice showing.
//
// Usage:
//   SettingsCombo { model: [...]; value: root.editX; onEdited: (i) => root.editX = i }
StyledComboBox {
    id: combo

    property int value: 0
    signal edited(int index)

    // Fill the row instead of leaving a gap after a fixed width, but stop short
    // of stretching a short list of choices across a wide window.
    Layout.fillWidth: true
    Layout.maximumWidth: 280
    implicitHeight: 28
    font.pixelSize: 13 * App.fontScale
    currentIndex: value

    onActivated: (index) => {
        combo.edited(index)
        currentIndex = Qt.binding(function() { return combo.value })
    }
}
