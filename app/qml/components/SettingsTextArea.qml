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
import QtQuick.Controls.Basic as B
import QtQuick.Layouts

// Multi-line text box with its own scrollbar, for lists edited as text
// (file types, excluded sites, blocked user agents, …).
//
// The inner scroller only takes mouse-wheel events while the box has keyboard
// focus AND its text overflows. Otherwise the wheel passes through to the
// settings page, so scrolling the page never stalls just because the pointer
// crossed the box. (A non-interactive Flickable ignores wheel events, which
// lets them propagate to the page's scroller.)
//
// `value` is one-way like SettingsTextField. `text` exposes the live text for
// owners that read it directly (e.g. to compare against saved settings).
//
// Usage:
//   SettingsTextArea { value: root.editX; onEdited: (t) => root.editX = t }
Rectangle {
    id: root

    property string value
    property alias text: area.text
    property alias placeholderText: area.placeholderText
    property bool wrap: true
    property bool monospace: false
    signal edited(string text)

    Layout.fillWidth: true
    implicitHeight: 84
    color: enabled ? ColorPalette.inputBg : ColorPalette.panelBg
    border.color: area.activeFocus ? ColorPalette.borderFocus : ColorPalette.border
    radius: 3
    clip: true

    ScrollView {
        id: scroller
        anchors.fill: parent
        anchors.margins: 1
        ScrollBar.horizontal.policy: root.wrap ? ScrollBar.AlwaysOff : ScrollBar.AsNeeded

        B.TextArea {
            id: area
            wrapMode: root.wrap ? TextEdit.Wrap : TextEdit.NoWrap
            font.pixelSize: 12 * App.fontScale
            // An empty family makes Qt pick an unrelated fallback font; use the app's.
            font.family: root.monospace ? "Consolas" : Qt.application.font.family
            color: ColorPalette.textPrimary
            placeholderTextColor: ColorPalette.textDisabled
            selectionColor: ColorPalette.accent
            selectedTextColor: "#ffffff"
            selectByMouse: true
            leftPadding: 7
            rightPadding: 7
            topPadding: 6
            bottomPadding: 6
            background: null
            onTextChanged: if (activeFocus) root.edited(text)
        }
    }

    Binding {
        target: scroller.contentItem
        property: "interactive"
        value: area.activeFocus && scroller.contentItem.contentHeight > scroller.height
    }

    onValueChanged: if (area.text !== value) area.text = value
    // Owners that set `text` directly leave `value` empty; completion order is
    // unspecified, so an empty value must not wipe their text.
    Component.onCompleted: if (value.length > 0) area.text = value
}
