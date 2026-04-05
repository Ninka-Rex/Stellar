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

    // Set before showing.  deleteMode passed to confirmed():
    //   0 = remove from list only
    //   1 = delete file permanently
    //   2 = move file to trash
    property string downloadId: ""
    property string filename: ""
    property bool fileExists: false   // true when file is on disk (completed download)

    signal confirmed(int deleteMode)

    width: 420
    height: fileExists ? 230 : 160
    minimumWidth: 380
    maximumWidth: 560
    color: "#1e1e1e"
    title: "Confirm Delete"
    flags: Qt.Dialog | Qt.WindowTitleHint | Qt.WindowCloseButtonHint
    Material.theme: Material.Dark
    Material.background: "#1e1e1e"
    Material.accent: "#4488dd"
    modality: Qt.ApplicationModal

    onVisibleChanged: {
        if (visible) {
            deleteFileChk.checked = false
            permDeleteChk.checked = false
        }
    }

    ColumnLayout {
        anchors { fill: parent; margins: 20 }
        spacing: 14

        // Icon + message
        RowLayout {
            spacing: 12
            Text {
                text: "\u26A0"
                color: "#e0a040"
                font.pixelSize: 28
                Layout.alignment: Qt.AlignTop
            }
            ColumnLayout {
                spacing: 4
                Text {
                    text: "Remove download?"
                    color: "#ffffff"
                    font.pixelSize: 14
                    font.bold: true
                }
                Text {
                    text: root.filename
                    color: "#a0a0a0"
                    font.pixelSize: 12
                    elide: Text.ElideMiddle
                    Layout.maximumWidth: 310
                }
            }
        }

        // File-on-disk options (only shown for completed downloads)
        ColumnLayout {
            visible: root.fileExists
            spacing: 4

            Rectangle {
                Layout.fillWidth: true
                height: 1
                color: "#3a3a3a"
            }

            CheckBox {
                id: deleteFileChk
                text: "Also delete file from disk"
                checked: false
                topPadding: 4
                bottomPadding: 0
                onToggled: { if (!checked) permDeleteChk.checked = false }
                contentItem: Text {
                    text: parent.text
                    color: "#d0d0d0"
                    font.pixelSize: 12
                    leftPadding: parent.indicator.width + 6
                    verticalAlignment: Text.AlignVCenter
                }
            }

            CheckBox {
                id: permDeleteChk
                text: "Permanently delete (don't move to trash)"
                checked: false
                enabled: deleteFileChk.checked
                topPadding: 4
                bottomPadding: 0
                contentItem: Text {
                    text: parent.text
                    color: permDeleteChk.enabled ? "#d0d0d0" : "#666666"
                    font.pixelSize: 12
                    leftPadding: parent.indicator.width + 6
                    verticalAlignment: Text.AlignVCenter
                }
            }
        }

        Item { Layout.fillHeight: true }

        // Buttons
        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Item { Layout.fillWidth: true }

            Button {
                text: "Cancel"
                implicitWidth: 80
                background: Rectangle { color: "#3a3a3a"; radius: 3 }
                contentItem: Text { text: parent.text; color: "#d0d0d0"; font.pixelSize: 13; horizontalAlignment: Text.AlignHCenter }
                onClicked: root.close()
            }

            Button {
                text: "Delete"
                implicitWidth: 80
                background: Rectangle { color: "#8b2020"; radius: 3 }
                contentItem: Text { text: parent.text; color: "#ffffff"; font.bold: true; font.pixelSize: 13; horizontalAlignment: Text.AlignHCenter }
                onClicked: {
                    var mode = 0
                    if (root.fileExists && deleteFileChk.checked) {
                        mode = permDeleteChk.checked ? 1 : 2
                    }
                    root.confirmed(mode)
                    root.close()
                }
            }
        }
    }
}
