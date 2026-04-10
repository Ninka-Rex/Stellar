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

    width: 480
    height: 220
    minimumWidth: 380
    minimumHeight: 180
    title: "Add Address Exception"
    color: "#1e1e1e"
    flags: Qt.Dialog | Qt.WindowTitleHint | Qt.WindowCloseButtonHint

    Material.theme: Material.Dark
    Material.background: "#1e1e1e"
    Material.accent: "#4488dd"

    property string url: ""

    signal accepted()
    signal rejected()

    ColumnLayout {
        anchors { fill: parent; margins: 18 }
        spacing: 14

        Text {
            text: "Add to Address Exceptions?"
            color: "#ffffff"
            font.pixelSize: 15
            font.bold: true
        }

        Text {
            Layout.fillWidth: true
            text: "This address was cancelled twice. Do you want to add it to the list of exceptions so Stellar will never intercept it automatically?"
            color: "#c0c0c0"
            font.pixelSize: 12
            wrapMode: Text.WordWrap
        }

        Rectangle {
            Layout.fillWidth: true
            height: 32
            color: "#252525"
            border.color: "#3a3a3a"
            radius: 3

            Text {
                anchors { verticalCenter: parent.verticalCenter; left: parent.left; leftMargin: 8; right: parent.right; rightMargin: 8 }
                text: root.url
                color: "#4488dd"
                font.pixelSize: 11
                elide: Text.ElideMiddle
            }
        }

        Item { Layout.fillHeight: true }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Item { Layout.fillWidth: true }

            DlgButton {
                text: "No"
                onClicked: { root.rejected(); root.close() }
            }

            DlgButton {
                text: "Add Exception"
                primary: true
                implicitWidth: 120
                onClicked: {
                    App.addExcludedAddress(root.url)
                    root.accepted()
                    root.close()
                }
            }
        }
    }
}
