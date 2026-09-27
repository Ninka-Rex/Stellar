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

// Clickable text link. Opens `url` in the browser when set; otherwise the
// owner handles onClicked.
Text {
    id: link

    property string url
    signal clicked()

    color: linkArea.containsMouse ? ColorPalette.accentHover : ColorPalette.accent
    font.pixelSize: 12 * App.fontScale
    font.underline: linkArea.containsMouse

    MouseArea {
        id: linkArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            if (link.url.length > 0)
                App.openExternalUrl(link.url)
            link.clicked()
        }
    }
}
