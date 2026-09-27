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

// Path text field with a compact browse button. The owner opens its own file
// or folder dialog in onBrowse, since those need per-field filters and titles.
//
// Usage:
//   SettingsPathField { value: root.editPath; onEdited: (t) => root.editPath = t; onBrowse: folderDlg.open() }
RowLayout {
    id: root

    property string value
    // Live text, for forms that load and read the field directly.
    property alias text: field.text
    property string placeholderText
    signal edited(string text)
    signal browse()

    Layout.fillWidth: true
    spacing: 6

    SettingsTextField {
        id: field
        value: root.value
        placeholderText: root.placeholderText
        onEdited: (text) => root.edited(text)
    }

    SettingsIconButton {
        iconSource: "../icons/actions/folder-open.svg"
        toolTip: qsTr("Browse…")
        onClicked: root.browse()
    }
}
