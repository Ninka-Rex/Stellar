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
import QtQuick.Controls.Material
import QtQuick.Layouts

Window {
    id: root
    title: "Settings of Stellar Grabber"
    width: 520
    height: 320
    minimumWidth: 500
    minimumHeight: 300
    color: "#1e1e1e"
    flags: Qt.Dialog | Qt.WindowTitleHint | Qt.WindowCloseButtonHint
    modality: Qt.ApplicationModal

    Material.theme: Material.Dark
    Material.background: "#1e1e1e"

    Rectangle {
        anchors.fill: parent
        color: "#1e1e1e"

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 12
            spacing: 10

            RowLayout {
                Layout.fillWidth: true
                SpinBox { id: exploreSpin; from: 1; to: 10; value: App.settings.grabberFilesToExploreAtOnce; editable: true }
                Text { text: "files to explore at the same time (1 to 10)"; color: "#eef2f7"; font.pixelSize: 12 }
            }

            RowLayout {
                Layout.fillWidth: true
                SpinBox { id: downloadSpin; from: 1; to: 10; value: App.settings.grabberFilesToDownloadAtOnce; editable: true }
                Text { text: "files to download at the same time (1 to 10)"; color: "#eef2f7"; font.pixelSize: 12 }
            }

            Text {
                Layout.fillWidth: true
                text: "Please note that a web server may reject requests if you set a large number of files to explore or download at the same time."
                color: "#a4adbb"
                font.pixelSize: 11
                wrapMode: Text.WordWrap
            }

            Rectangle { Layout.fillWidth: true; height: 1; color: "#3d434c" }

            CheckBox {
                id: descriptionChk
                text: "Use link texts as download descriptions when adding files to Stellar main list"
                checked: App.settings.grabberUseLinkTextAsDescription
                topPadding: 0
                bottomPadding: 0
            }

            Item { Layout.fillHeight: true }

            RowLayout {
                Layout.fillWidth: true
                Item { Layout.fillWidth: true }
                DlgButton { text: "Cancel"; onClicked: root.close() }
                DlgButton {
                    text: "OK"
                    primary: true
                    onClicked: {
                        App.settings.grabberFilesToExploreAtOnce = exploreSpin.value
                        App.settings.grabberFilesToDownloadAtOnce = downloadSpin.value
                        App.settings.grabberUseLinkTextAsDescription = descriptionChk.checked
                        root.close()
                    }
                }
            }
        }
    }
}
