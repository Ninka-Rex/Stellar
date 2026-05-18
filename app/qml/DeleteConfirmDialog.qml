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
    property var downloadIds: []
    property string filename: ""
    property bool fileExists: false   // true when file is on disk (completed download)
    property bool hasTorrentSelection: false

    signal confirmed(int deleteMode)

    readonly property int _dialogHeight: (fileExists || hasTorrentSelection) ? 188 : 130

    width: 400
    height: _dialogHeight
    minimumWidth: 360
    maximumWidth: 520
    minimumHeight: _dialogHeight
    maximumHeight: _dialogHeight
    color: "#1e1e1e"
    title: qsTr("Confirm Delete")
    flags: Qt.Dialog | Qt.WindowTitleHint | Qt.WindowCloseButtonHint
    Material.theme: Material.Dark
    Material.background: "#1e1e1e"
    Material.accent: "#4488dd"
    modality: Qt.ApplicationModal

    function _centerOnOwner() {
        var owner = root.transientParent
        if (owner) {
            x = owner.x + Math.round((owner.width  - width)  / 2)
            y = owner.y + Math.round((owner.height - height) / 2)
            return
        }
        x = Math.round((Screen.width  - width)  / 2)
        y = Math.round((Screen.height - height) / 2)
    }

    onVisibleChanged: {
        if (visible) {
            _centerOnOwner()
            deleteFileChk.checked = false
            permDeleteChk.checked = false
        }
    }

    ColumnLayout {
        id: contentColumn
        anchors { fill: parent; margins: 12 }
        spacing: 6

        // Icon + message
        RowLayout {
            spacing: 10
            Image {
                source: "icons/delete.svg"
                width: 22; height: 22
                Layout.alignment: Qt.AlignVCenter
                smooth: true
                mipmap: true
            }
            ColumnLayout {
                spacing: 2
                Text {
                    text: qsTr("Remove download?")
                    color: "#ffffff"
                    font.pixelSize: 13
                    font.bold: true
                }
                Text {
                    text: root.filename
                    color: "#a0a0a0"
                    font.pixelSize: 11
                    elide: Text.ElideMiddle
                    Layout.maximumWidth: 300
                }
            }
        }

        // File-on-disk options (only shown for completed downloads)
        ColumnLayout {
            visible: root.fileExists || root.hasTorrentSelection
            spacing: 2

            Rectangle {
                Layout.fillWidth: true
                height: 1
                color: "#3a3a3a"
                Layout.topMargin: 2
            }

            CheckBox {
                id: deleteFileChk
                text: root.hasTorrentSelection
                    ? qsTr("Also delete torrent files from disk")
                    : qsTr("Also delete file from disk")
                checked: false
                topPadding: 2
                bottomPadding: 2
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
                text: qsTr("Permanently delete (don't move to trash)")
                checked: false
                enabled: deleteFileChk.checked
                topPadding: 2
                bottomPadding: 2
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

            DlgButton {
                text: qsTr("Cancel")
                onClicked: root.close()
            }

            DlgButton {
                text: qsTr("Delete")
                destructive: true
                onClicked: {
                    var mode = 0
                    if ((root.fileExists || root.hasTorrentSelection) && deleteFileChk.checked) {
                        mode = permDeleteChk.checked ? 1 : 2
                    }
                    root.confirmed(mode)
                    root.close()
                }
            }
        }
    }
}
