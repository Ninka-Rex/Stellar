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
    title: qsTr("Delete Completed Downloads")
    property bool includeSeedingTorrents: false
    width: 400
    height: 188
    minimumWidth: 360
    minimumHeight: 188
    maximumHeight: 188
    color: ColorPalette.cardBg
    flags: Qt.Dialog | Qt.WindowTitleHint | Qt.WindowCloseButtonHint | Qt.WindowSystemMenuHint
    modality: Qt.ApplicationModal

    Material.theme: ColorPalette.materialTheme
    Material.foreground: ColorPalette.textPrimary
    Material.background: ColorPalette.materialBg
    Material.accent: "#4488dd"

    signal confirmed(bool includeSeedingTorrents)

    onVisibleChanged: {
        if (visible)
            includeSeedingTorrents = false
    }

    ColumnLayout {
        anchors { fill: parent; margins: 12 }
        spacing: 6

        // Icon + message
        RowLayout {
            spacing: 10
            Image {
                source: "../icons/delete.svg"
                width: 22; height: 22
                Layout.alignment: Qt.AlignVCenter
                smooth: true
                mipmap: true
            }
            ColumnLayout {
                spacing: 2
                Text {
                    text: qsTr("Delete completed downloads?")
                    color: ColorPalette.textHeader
                    font.pixelSize: 13 * App.fontScale
                    font.bold: true
                }
                Text {
                    text: qsTr("Removes from list only. Files on disk are not deleted.")
                    color: "#a0a0a0"
                    font.pixelSize: 11 * App.fontScale
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            height: 1
            color: ColorPalette.border
            Layout.topMargin: 2
        }

        StyledCheckBox {
            text: qsTr("Delete completed and seeding torrents")
            checked: root.includeSeedingTorrents
            topPadding: 2
            bottomPadding: 2
            onToggled: root.includeSeedingTorrents = checked
            contentItem: Text {
                text: parent.text
                color: ColorPalette.textPrimary
                font.pixelSize: 12 * App.fontScale
                leftPadding: parent.indicator.width + 6
                verticalAlignment: Text.AlignVCenter
            }
        }

        Item { Layout.fillHeight: true }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            Item { Layout.fillWidth: true }
            DlgButton {
                text: qsTr("Cancel")
                onClicked: root.close()
            }
            DlgButton {
                text: qsTr("Delete")
                destructive: true
                onClicked: { root.confirmed(root.includeSeedingTorrents); root.close() }
            }
        }
    }
}
