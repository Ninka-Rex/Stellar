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

// Downloads | Torrents workspace switcher shown under the toolbar. Each
// workspace owns its own sidebar sections, columns, sort, selection and scroll
// (Main.qml swaps them in switchWorkspace()).
Rectangle {
    id: root
    implicitHeight: 30
    color: ColorPalette.panelBg

    property string workspace: "downloads"
    property int downloadCount: 0
    property int torrentCount: 0
    // The current workspace's docked details pane.
    property bool detailsPaneVisible: true

    signal workspaceRequested(string workspace)
    signal detailsPaneToggled()

    component WorkspaceTab: Rectangle {
        id: tab
        required property string workspaceId
        required property string label
        required property string iconSource
        required property int count
        required property string shortcutText
        readonly property bool current: root.workspace === workspaceId

        width: tabRow.implicitWidth + 28
        height: root.height
        color: current ? ColorPalette.cardBg : (tabMa.containsMouse ? ColorPalette.hoverBg : "transparent")

        // Accent underline marks the active workspace.
        Rectangle {
            anchors.bottom: parent.bottom
            width: parent.width; height: 2
            color: tab.current ? ColorPalette.accent : "transparent"
        }

        Row {
            id: tabRow
            anchors.centerIn: parent
            spacing: 6
            Image {
                source: tab.iconSource
                width: 16; height: 16
                sourceSize.width: 16; sourceSize.height: 16
                fillMode: Image.PreserveAspectFit; smooth: true; mipmap: true
                anchors.verticalCenter: parent.verticalCenter
            }
            Text {
                text: tab.label
                color: tab.current ? ColorPalette.textHeader : ColorPalette.textSecond
                font.pixelSize: 12 * App.fontScale
                font.bold: tab.current
                anchors.verticalCenter: parent.verticalCenter
            }
            Rectangle {
                visible: tab.count > 0
                implicitWidth: Math.max(18, countText.implicitWidth + 10)
                implicitHeight: 16
                radius: 8
                color: tab.current ? ColorPalette.selectionBg : ColorPalette.dividerBg
                anchors.verticalCenter: parent.verticalCenter
                Text {
                    id: countText
                    anchors.centerIn: parent
                    text: tab.count
                    color: tab.current ? ColorPalette.selectionText : ColorPalette.textSecond
                    font.pixelSize: 10 * App.fontScale
                }
            }
        }

        MouseArea {
            id: tabMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.workspaceRequested(tab.workspaceId)
        }

        ThemedToolTip {
            visible: tabMa.containsMouse
            text: tab.shortcutText
        }
    }

    Row {
        anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
        spacing: 0

        WorkspaceTab {
            workspaceId: "downloads"
            label: qsTr("Downloads")
            iconSource: "../icons/places/network-server.svg"
            count: root.downloadCount
            shortcutText: qsTr("Downloads (Ctrl+1)")
        }
        WorkspaceTab {
            workspaceId: "torrents"
            label: qsTr("Torrents")
            iconSource: "../icons/torrent-states/all-torrents.svg"
            count: root.torrentCount
            shortcutText: qsTr("Torrents (Ctrl+2)")
        }
    }

    // Details pane toggle for the current workspace.
    TabBarAction {
        anchors { right: parent.right; top: parent.top; bottom: parent.bottom; rightMargin: 6 }
        text: qsTr("Details")
        toolTip: qsTr("Show or hide the details pane (Ctrl+Shift+D)")
        checkable: true
        checked: root.detailsPaneVisible
        onClicked: root.detailsPaneToggled()
    }

    // Under the tabs (z -1) so the active tab's fill and underline cover it.
    Rectangle { z: -1; anchors.bottom: parent.bottom; width: parent.width; height: 1; color: ColorPalette.border }
}
