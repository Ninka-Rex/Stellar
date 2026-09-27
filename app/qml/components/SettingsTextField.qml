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

// Single-line text input in the settings style. Basic rather than Material:
// Material's floating placeholder and padding fight the custom background.
//
// `value` is one-way: bind it to the owner's state and write the state back in
// onEdited. Typing never touches `value`, so a reset (or any programmatic
// change) still reaches the field; the field only rewrites its text when the
// value actually differs, which keeps the cursor where it is while typing.
//
// Usage:
//   SettingsTextField { value: root.editX; onEdited: (t) => root.editX = t }
B.TextField {
    id: field

    property string value
    signal edited(string text)

    Layout.fillWidth: true
    implicitHeight: 28
    leftPadding: 8
    rightPadding: 8
    topPadding: 0
    bottomPadding: 0
    verticalAlignment: TextInput.AlignVCenter
    font.pixelSize: 13 * App.fontScale
    color: enabled && !readOnly ? ColorPalette.textPrimary : ColorPalette.textSecond
    placeholderTextColor: ColorPalette.textDisabled
    selectionColor: ColorPalette.accent
    selectedTextColor: "#ffffff"
    selectByMouse: true

    background: Rectangle {
        color: field.enabled && !field.readOnly ? ColorPalette.inputBg : ColorPalette.panelBg
        border.color: field.activeFocus ? ColorPalette.borderFocus : ColorPalette.border
        radius: 3
    }

    onTextEdited: edited(text)
    onValueChanged: if (text !== value) text = value
    // Forms that set `text` directly (the category editor) leave `value` empty;
    // completion order is unspecified, so an empty value must not wipe their text.
    Component.onCompleted: if (value.length > 0) text = value
}
