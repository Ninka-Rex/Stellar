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

// One page of the Preferences window: a title that stays put above a body.
// No rule under the title: each section header already draws one.
// The body is a ColumnLayout, so children size themselves with Layout.*:
// a SettingsScroll for ordinary pages, or a custom layout (Categories list +
// form, Torrents' tab bar + stack) that fills the remaining space.
//
// Usage:
//   SettingsPage { title: qsTr("Connection"); SettingsScroll { SettingsSection { ... } } }
Item {
    id: page

    property string title
    default property alias content: body.data

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        Text {
            Layout.fillWidth: true
            Layout.leftMargin: 16
            Layout.rightMargin: 16
            Layout.topMargin: 14
            Layout.bottomMargin: 4
            text: page.title
            color: ColorPalette.textHeader
            font.pixelSize: 16 * App.fontScale
            font.bold: true
            elide: Text.ElideRight
        }

        ColumnLayout {
            id: body
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 0
        }
    }
}
