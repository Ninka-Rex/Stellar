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

Window {
    id: root
    width: 560
    height: 380
    minimumWidth: 500
    minimumHeight: 320
    title: "Search Plugins"
    color: "#1e1e1e"
    flags: Qt.Dialog | Qt.WindowTitleHint | Qt.WindowCloseButtonHint | Qt.WindowSystemMenuHint

    property int ctxRow: -1

    TorrentSearchInstallDialog { id: installDialog }

    Menu {
        id: pluginMenu
        property int targetRow: -1
        onAboutToShow: {
            if (targetRow < 0)
                return
            var plugin = App.torrentSearchManager.pluginData(targetRow)
            disableToggle.text = plugin.enabled ? "Disable Plugin" : "Enable Plugin"
        }
        Action {
            id: disableToggle
            text: "Disable Plugin"
            onTriggered: {
                if (root.ctxRow >= 0)
                    App.torrentSearchManager.togglePluginEnabled(root.ctxRow)
            }
        }
        Action {
            text: "Uninstall"
            onTriggered: {
                var plugin = App.torrentSearchManager.pluginData(root.ctxRow)
                if (plugin.fileName)
                    App.torrentSearchManager.uninstallPlugin(plugin.fileName)
            }
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 12
        spacing: 8

        RowLayout {
            Layout.fillWidth: true
            Text { text: "Installed Search Plugins"; color: "#fff"; font.pixelSize: 16; font.bold: true }
            Item { Layout.fillWidth: true }
            DlgButton { text: "Refresh"; onClicked: App.torrentSearchManager.refreshPlugins() }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            color: "#1a1a1a"
            border.color: "#2d2d2d"
            radius: 4

            ListView {
                id: pluginList
                anchors.fill: parent
                anchors.margins: 1
                clip: true
                model: App.torrentSearchManager.pluginModel
        delegate: Rectangle {
            required property int index
            required property string fileName
            required property string version
            required property string url
            required property bool pluginEnabled

                    width: ListView.view.width
                    height: 34
                    color: index % 2 === 0 ? "#1c1c1c" : "#222222"

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        spacing: 10
                        Text { text: fileName; color: pluginEnabled ? "#f0f0f0" : "#7f7f7f"; Layout.preferredWidth: 150; elide: Text.ElideRight; font.pixelSize: 12 }
                        Text { text: version.length > 0 ? version : "Unknown"; color: "#b9c3cd"; Layout.preferredWidth: 70; font.pixelSize: 12 }
                        Text { text: url.length > 0 ? url : "Unknown"; color: "#8ea1b5"; Layout.fillWidth: true; elide: Text.ElideRight; font.pixelSize: 12 }
                        Text { text: pluginEnabled ? "Enabled" : "Disabled"; color: pluginEnabled ? "#67bb7a" : "#c6a56d"; font.pixelSize: 12; font.bold: true }
                    }

                    MouseArea {
                        anchors.fill: parent
                        acceptedButtons: Qt.RightButton
                        onClicked: (mouse) => {
                            root.ctxRow = index
                            pluginMenu.targetRow = index
                            pluginMenu.popup()
                        }
                    }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            DlgButton { text: "Install a New One"; primary: true; onClicked: installDialog.show() }
            Item { Layout.fillWidth: true }
            DlgButton { text: "Close"; onClicked: root.close() }
        }
    }
}
