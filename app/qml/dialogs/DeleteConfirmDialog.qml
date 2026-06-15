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

    // Height set imperatively per open (not bound) — binding min/max to a live
    // content height fights the WM resize and oscillates ("Unable to set geometry"
    // spam). Two checkbox layouts: 157 with options, 104 without.
    readonly property int _dialogHeight: (fileExists || hasTorrentSelection) ? 157 : 104

    width: 400
    height: _dialogHeight
    minimumWidth: 360
    maximumWidth: 520
    color: ColorPalette.cardBg
    title: qsTr("Confirm Delete")
    flags: Qt.Dialog | Qt.WindowTitleHint | Qt.WindowCloseButtonHint
    Material.theme: ColorPalette.materialTheme
    Material.foreground: ColorPalette.textPrimary
    Material.background: ColorPalette.materialBg
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
            deleteFileChk.checked = false
            permDeleteChk.checked = false
            // Resize a reused Window to the current layout. Drop min to 0 first so
            // neither shrink (max<old-min) nor grow (max>old-min) makes min>max
            // transiently, then set max, height, min.
            minimumHeight = 0
            maximumHeight = _dialogHeight
            height = _dialogHeight
            minimumHeight = _dialogHeight
            _centerOnOwner()
        }
    }

    ColumnLayout {
        id: contentColumn
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
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
                    text: qsTr("Remove download?")
                    color: ColorPalette.textHeader
                    font.pixelSize: 13 * App.fontScale
                    font.bold: true
                }
                Text {
                    text: root.filename
                    color: "#a0a0a0"
                    font.pixelSize: 11 * App.fontScale
                    elide: Text.ElideMiddle
                    Layout.maximumWidth: 300
                }
            }
        }

        // File-on-disk options (only shown for completed downloads)
        ColumnLayout {
            visible: root.fileExists || root.hasTorrentSelection
            Layout.preferredHeight: visible ? implicitHeight : 0
            clip: true
            spacing: 2

            Rectangle {
                Layout.fillWidth: true
                height: 1
                color: ColorPalette.border
                Layout.topMargin: 2
            }

            StyledCheckBox {
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
                    color: ColorPalette.textPrimary
                    font.pixelSize: 12 * App.fontScale
                    leftPadding: parent.indicator.width + 6
                    verticalAlignment: Text.AlignVCenter
                }
            }

            StyledCheckBox {
                id: permDeleteChk
                text: qsTr("Permanently delete (don't move to trash)")
                checked: false
                enabled: deleteFileChk.checked
                topPadding: 2
                bottomPadding: 2
                contentItem: Text {
                    text: parent.text
                    color: permDeleteChk.enabled ? ColorPalette.textPrimary : ColorPalette.textDisabled
                    font.pixelSize: 12 * App.fontScale
                    leftPadding: parent.indicator.width + 6
                    verticalAlignment: Text.AlignVCenter
                }
            }
        }

        // Buttons
        RowLayout {
            Layout.topMargin: 4
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
