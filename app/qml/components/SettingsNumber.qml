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
import QtQuick.Controls.Basic as B
import QtQuick.Layouts

// Number box: type a value or use the +/− buttons, with an optional unit after
// it ("seconds", "KB/s"). Typed text is committed on Enter or when focus
// leaves the box, and clamped to [from, to].
//
// `value` is one-way like SettingsCheck.checked: bind it to the owner's state
// and write that state back in onEdited; the box re-binds after each edit so a
// reset, or a handler that adjusts the value, always shows.
//
// Usage:
//   SettingsNumber { from: 1; to: 16; value: root.editX; onEdited: (v) => root.editX = v }
RowLayout {
    id: root

    property int value: 0
    property int from: 0
    property int to: 100
    property int stepSize: 1
    property string suffix
    signal edited(int value)

    spacing: 6

    B.SpinBox {
        id: spin

        from: root.from
        to: root.to
        stepSize: root.stepSize
        value: root.value
        editable: true

        // Wide enough for the largest value plus the buttons.
        implicitWidth: Math.max(78, String(Math.max(Math.abs(root.from), Math.abs(root.to))).length * 8 + 48)
        implicitHeight: 28
        leftPadding: 6
        rightPadding: 26
        topPadding: 0
        bottomPadding: 0

        // Plain digits: a regional locale adds thousands separators, which reads
        // oddly for ports and counts ("6,881"). The C locale omits them. (A custom
        // textFromValue would do the same but trips a binding loop in SpinBox's
        // displayText during initialisation.) SpinBox's built-in IntValidator and
        // range clamping handle typed input.
        locale: Qt.locale("C")

        onValueModified: {
            root.edited(value)
            value = Qt.binding(function() { return root.value })
        }

        contentItem: TextInput {
            text: spin.displayText
            color: spin.enabled ? ColorPalette.textPrimary : ColorPalette.textDisabled
            selectionColor: ColorPalette.accent
            selectedTextColor: "#ffffff"
            font.pixelSize: 13 * App.fontScale
            horizontalAlignment: Qt.AlignHCenter
            verticalAlignment: Qt.AlignVCenter
            readOnly: !spin.editable
            validator: spin.validator
            inputMethodHints: Qt.ImhFormattedNumbersOnly
            selectByMouse: true
        }

        up.indicator: Rectangle {
            x: spin.width - width - 1
            y: 1
            width: 22
            height: spin.height / 2 - 1
            color: spin.up.pressed ? ColorPalette.toolbarPressBg
                 : spin.up.hovered ? ColorPalette.toolbarHoverBg
                 : ColorPalette.panelBg
            Text {
                anchors.centerIn: parent
                text: "+"
                color: spin.enabled ? ColorPalette.textPrimary : ColorPalette.textDisabled
                font.pixelSize: 11 * App.fontScale
            }
        }

        down.indicator: Rectangle {
            x: spin.width - width - 1
            y: spin.height / 2
            width: 22
            height: spin.height / 2 - 1
            color: spin.down.pressed ? ColorPalette.toolbarPressBg
                 : spin.down.hovered ? ColorPalette.toolbarHoverBg
                 : ColorPalette.panelBg
            Text {
                anchors.centerIn: parent
                text: "–"
                color: spin.enabled ? ColorPalette.textPrimary : ColorPalette.textDisabled
                font.pixelSize: 11 * App.fontScale
            }
        }

        background: Rectangle {
            color: spin.enabled ? ColorPalette.inputBg : ColorPalette.panelBg
            border.color: spin.activeFocus ? ColorPalette.borderFocus : ColorPalette.border
            radius: 3
        }
    }

    Text {
        visible: root.suffix.length > 0
        text: root.suffix
        color: root.enabled ? ColorPalette.textSecond : ColorPalette.textDisabled
        font.pixelSize: 13 * App.fontScale
    }
}
