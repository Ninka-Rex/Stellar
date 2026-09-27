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

// Coloured status dot followed by a line of text ("yt-dlp 2025.01 found",
// "ffmpeg not found", …).
RowLayout {
    id: root

    enum Level { Ok, Busy, Error }

    property int level: SettingsStatus.Level.Ok
    property string text

    Layout.fillWidth: true
    spacing: 8

    Rectangle {
        Layout.alignment: Qt.AlignTop
        Layout.topMargin: 4
        implicitWidth: 9
        implicitHeight: 9
        radius: 4.5
        color: root.level === SettingsStatus.Level.Ok ? ColorPalette.successText
             : root.level === SettingsStatus.Level.Busy ? ColorPalette.warningText
             : ColorPalette.errorText
    }

    Text {
        Layout.fillWidth: true
        text: root.text
        color: ColorPalette.textPrimary
        font.pixelSize: 12 * App.fontScale
        wrapMode: Text.WrapAnywhere
    }
}
