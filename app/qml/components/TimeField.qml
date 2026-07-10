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

// Clock-time editor storing minutes-since-midnight (matches
// Queue.startTimeMinutes / stopTimeMinutes). 12-hour display with AM/PM.
//
// Usage:
//   TimeField { minutes: queue.startTimeMinutes; onEdited: (m) => queue.startTimeMinutes = m }
Row {
    id: root

    property int minutes: 0
    signal edited(int newMinutes)

    // Guards the input handlers while minutes -> text sync runs.
    property bool _syncing: false

    spacing: 4

    function _hour12() {
        var h = Math.floor(minutes / 60) % 12
        return h === 0 ? 12 : h
    }

    function _commit() {
        if (_syncing) return
        var h = parseInt(hourInput.text, 10)
        var m = parseInt(minuteInput.text, 10)
        if (isNaN(h) || h < 1 || h > 12) h = 12
        if (isNaN(m) || m < 0 || m > 59) m = 0
        var h24 = h % 12 + (ampmCombo.currentIndex === 1 ? 12 : 0)
        root.edited(h24 * 60 + m)
    }

    function _sync() {
        _syncing = true
        hourInput.text = String(_hour12())
        var m = minutes % 60
        minuteInput.text = m < 10 ? "0" + m : String(m)
        ampmCombo.currentIndex = minutes >= 12 * 60 ? 1 : 0
        _syncing = false
    }

    onMinutesChanged: _sync()
    Component.onCompleted: _sync()

    Rectangle {
        width: 34; height: 24
        color: ColorPalette.inputBg
        border.color: hourInput.activeFocus ? ColorPalette.borderFocus : ColorPalette.border
        radius: 3
        TextInput {
            id: hourInput
            anchors.fill: parent
            horizontalAlignment: TextInput.AlignHCenter
            verticalAlignment: TextInput.AlignVCenter
            color: ColorPalette.textPrimary
            selectionColor: ColorPalette.accent
            font.pixelSize: 12 * App.fontScale
            maximumLength: 2
            validator: IntValidator { bottom: 1; top: 12 }
            onEditingFinished: root._commit()
        }
    }

    Text {
        text: ":"
        color: ColorPalette.textPrimary
        font.pixelSize: 12 * App.fontScale
        anchors.verticalCenter: parent.verticalCenter
    }

    Rectangle {
        width: 34; height: 24
        color: ColorPalette.inputBg
        border.color: minuteInput.activeFocus ? ColorPalette.borderFocus : ColorPalette.border
        radius: 3
        TextInput {
            id: minuteInput
            anchors.fill: parent
            horizontalAlignment: TextInput.AlignHCenter
            verticalAlignment: TextInput.AlignVCenter
            color: ColorPalette.textPrimary
            selectionColor: ColorPalette.accent
            font.pixelSize: 12 * App.fontScale
            maximumLength: 2
            validator: IntValidator { bottom: 0; top: 59 }
            onEditingFinished: root._commit()
        }
    }

    StyledComboBox {
        id: ampmCombo
        width: 62
        height: 24
        anchors.verticalCenter: parent.verticalCenter
        font.pixelSize: 12 * App.fontScale
        model: [qsTr("AM"), qsTr("PM")]
        onActivated: root._commit()
    }
}
