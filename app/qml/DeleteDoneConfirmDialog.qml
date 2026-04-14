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
import QtQuick.Window
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts

Window {
    id: root
    title: "Delete Completed Downloads"
    property bool includeSeedingTorrents: false
    width: 440
    height: 236
    minimumWidth: 360
    minimumHeight: 216
    maximumHeight: 236
    color: "#1e1e1e"
    flags: Qt.Dialog | Qt.WindowTitleHint | Qt.WindowCloseButtonHint | Qt.WindowSystemMenuHint
    modality: Qt.ApplicationModal

    Material.theme: Material.Dark
    Material.background: "#1e1e1e"
    Material.accent: "#4488dd"

    signal confirmed(bool includeSeedingTorrents)

    onVisibleChanged: {
        if (visible)
            includeSeedingTorrents = false
    }

    ColumnLayout {
        anchors { fill: parent; margins: 20 }
        spacing: 16

        Text {
            text: "Are you sure you want to delete all completed downloads from Stellar's list of downloads?"
            color: "#d0d0d0"; font.pixelSize: 13
            wrapMode: Text.WordWrap; Layout.fillWidth: true
        }

        Text {
            text: "Note: This will only remove them from the list. Files on disk will not be deleted."
            color: "#909090"; font.pixelSize: 12
            wrapMode: Text.WordWrap; Layout.fillWidth: true
        }

        CheckBox {
            text: "Delete completed and seeding torrents"
            checked: root.includeSeedingTorrents
            topPadding: 0
            bottomPadding: 0
            onToggled: root.includeSeedingTorrents = checked
            contentItem: Text {
                text: parent.text
                color: "#d0d0d0"
                font.pixelSize: 12
                leftPadding: parent.indicator.width + 6
                verticalAlignment: Text.AlignVCenter
            }
        }

        Item { Layout.fillHeight: true }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            Item { Layout.fillWidth: true }
            Button {
                text: "Yes"
                implicitWidth: 80
                background: Rectangle { color: "#1e3a6e"; radius: 3; border.color: "#4488dd"; border.width: 1 }
                contentItem: Text { text: parent.text; color: "#ffffff"; font.pixelSize: 13; font.bold: true; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                onClicked: { root.confirmed(root.includeSeedingTorrents); root.close() }
            }
            Button {
                text: "No"
                implicitWidth: 80
                background: Rectangle { color: "#3a3a3a"; radius: 3; border.color: "#555"; border.width: 1 }
                contentItem: Text { text: parent.text; color: "#d0d0d0"; font.pixelSize: 13; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                onClicked: root.close()
            }
        }
    }
}
