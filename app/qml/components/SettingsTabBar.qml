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

// Text tabs with an accent underline, for splitting a long settings page into
// sub-pages. Pair with a StackLayout bound to currentIndex. When translated
// labels are wider than the page, the strip scrolls sideways instead of
// clipping tabs.
Item {
    id: root

    property var model: []
    property int currentIndex: 0

    Layout.fillWidth: true
    implicitHeight: 34

    Rectangle {
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
        height: 1
        color: ColorPalette.border
    }

    Flickable {
        anchors.fill: parent
        contentWidth: tabs.width + 20
        contentHeight: height
        clip: true
        flickableDirection: Flickable.HorizontalFlick
        interactive: contentWidth > width
        boundsBehavior: Flickable.StopAtBounds

        Row {
            id: tabs
            x: 10
            height: parent.height
            spacing: 2

            Repeater {
                model: root.model
                delegate: Item {
                    required property int index
                    required property string modelData
                    readonly property bool selected: root.currentIndex === index

                    width: tabLabel.implicitWidth + 20
                    height: tabs.height

                    Text {
                        id: tabLabel
                        anchors.centerIn: parent
                        text: parent.modelData
                        color: parent.selected ? ColorPalette.textHeader
                             : tabArea.containsMouse ? ColorPalette.textPrimary
                             : ColorPalette.textSecond
                        font.pixelSize: 12 * App.fontScale
                        font.bold: parent.selected
                    }

                    Rectangle {
                        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                        height: 2
                        color: ColorPalette.accent
                        visible: parent.selected
                    }

                    MouseArea {
                        id: tabArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.currentIndex = parent.index
                    }
                }
            }
        }
    }
}
