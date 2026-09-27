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

// Checkbox with an optional explanation under its label, aligned with the
// label text.
//
// `checked` is one-way: the owner binds it to its state and updates that state
// in onToggled. A click would normally break the box's binding (so a later
// reset would not show), and a handler may refuse the change (e.g. a
// confirmation it cancels), so the box re-binds after every click and always
// shows the owner's state.
//
// Usage:
//   SettingsCheck { text: qsTr("…"); checked: root.editX; onToggled: (on) => root.editX = on }
ColumnLayout {
    id: root

    property string text
    property string description
    property bool checked: false
    signal toggled(bool checked)

    Layout.fillWidth: true
    spacing: 2

    StyledCheckBox {
        id: box
        // Material's default left padding would indent the box past the labels
        // of the rows around it.
        leftPadding: 0
        text: root.text
        checked: root.checked
        onToggled: {
            root.toggled(checked)
            checked = Qt.binding(function() { return root.checked })
        }
    }

    Text {
        Layout.fillWidth: true
        // Indicator width + StyledCheckBox's label gap.
        Layout.leftMargin: 22
        visible: root.description.length > 0
        text: root.description
        color: root.enabled ? ColorPalette.textMuted : ColorPalette.textDisabled
        font.pixelSize: 11 * App.fontScale
        wrapMode: Text.WordWrap
    }
}
