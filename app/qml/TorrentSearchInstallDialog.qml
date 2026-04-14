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
import QtQuick.Layouts
import QtQuick.Dialogs

Window {
    id: root
    width: 420
    height: 220
    minimumWidth: 380
    minimumHeight: 200
    title: "Install Search Plugin"
    color: "#1e1e1e"
    flags: Qt.Dialog | Qt.WindowTitleHint | Qt.WindowCloseButtonHint | Qt.WindowSystemMenuHint

    property bool webMode: false
    property string urlText: ""

    FileDialog {
        id: fileDialog
        nameFilters: ["Python plugin (*.py)"]
        onAccepted: App.torrentSearchManager.installPluginFromFile(selectedFile.toString().replace(/^file:\/\/\//, "").replace(/^file:\/\//, ""))
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 14
        spacing: 10

        Text {
            text: "Install a new search plugin"
            color: "#ffffff"
            font.pixelSize: 16
            font.bold: true
        }

        RowLayout {
            spacing: 8
            DlgButton { text: "Local File"; primary: !root.webMode; onClicked: root.webMode = false }
            DlgButton { text: "Web Link"; primary: root.webMode; onClicked: root.webMode = true }
        }

        Loader {
            Layout.fillWidth: true
            sourceComponent: root.webMode ? webPane : filePane
        }

        Item { Layout.fillHeight: true }

        RowLayout {
            Layout.fillWidth: true
            Item { Layout.fillWidth: true }
            DlgButton { text: "Cancel"; onClicked: root.close() }
            DlgButton {
                text: "OK"
                primary: true
                enabled: root.webMode ? urlText.trim().length > 0 : true
                onClicked: {
                    if (root.webMode) {
                        App.torrentSearchManager.installPluginFromUrl(root.urlText.trim())
                    } else {
                        fileDialog.open()
                    }
                }
            }
        }
    }

    Component {
        id: filePane
        Rectangle {
            color: "#1a1a1a"
            border.color: "#2d2d2d"
            radius: 4
            implicitHeight: 72
            Layout.fillWidth: true
            Text {
                anchors.fill: parent
                anchors.margins: 12
                text: "Choose a local .py search plugin file to copy into the search_plugins folder."
                color: "#aeb7c0"
                wrapMode: Text.WordWrap
                font.pixelSize: 12
            }
        }
    }

    Component {
        id: webPane
        ColumnLayout {
            spacing: 6
            Text {
                text: "Paste a direct URL to a .py plugin file."
                color: "#aeb7c0"
                font.pixelSize: 12
            }
            TextField {
                Layout.fillWidth: true
                text: root.urlText
                onTextChanged: root.urlText = text
                color: "#d0d0d0"
                selectByMouse: true
                background: Rectangle {
                    color: "#1b1b1b"
                    border.color: parent.activeFocus ? "#4488dd" : "#3a3a3a"
                    radius: 2
                }
            }
        }
    }

    Connections {
        target: App.torrentSearchManager
        function onPluginInstallFinished(ok, message) {
            if (!root.visible)
                return
            root.close()
        }
    }
}
