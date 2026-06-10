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
    title: qsTr("Export Downloads")
    width: 420
    height: 220
    color: ColorPalette.cardBg
    flags: Qt.Dialog | Qt.WindowTitleHint | Qt.WindowCloseButtonHint | Qt.MSWindowsFixedSizeDialogHint
    modality: Qt.ApplicationModal

    Material.theme: ColorPalette.materialTheme
    Material.foreground: ColorPalette.textPrimary
    Material.background: ColorPalette.materialBg
    Material.accent: "#4488dd"

    property var downloadTableRef: null

    signal accepted(string mode)

    function centerOnOwner() {
        var owner = root.transientParent
        if (owner) {
            x = owner.x + Math.round((owner.width - width) / 2)
            y = owner.y + Math.round((owner.height - height) / 2)
            return
        }
        x = Math.round((Screen.width - width) / 2)
        y = Math.round((Screen.height - height) / 2)
    }

    onVisibleChanged: {
        if (visible)
            centerOnOwner()
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 16
        spacing: 10

        Text {
            text: qsTr("Select items to export:")
            color: ColorPalette.textPrimary
            font.pixelSize: 13 * App.fontScale
            font.bold: true
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0

            StyledRadioButton {
                id: queueRadio
                text: qsTr("Export downloads in the selected queue")
                font.pixelSize: 12 * App.fontScale
                checked: true
                topPadding: 1; bottomPadding: 1
                contentItem: Text {
                    text: queueRadio.text
                    color: ColorPalette.textPrimary
                    font: queueRadio.font
                    verticalAlignment: Text.AlignVCenter
                    leftPadding: queueRadio.indicator.width + queueRadio.spacing
                }
            }

            StyledRadioButton {
                id: selectedRadio
                text: qsTr("Export selected downloads")
                font.pixelSize: 12 * App.fontScale
                enabled: root.downloadTableRef && root.downloadTableRef.hasSelection
                topPadding: 1; bottomPadding: 1
                contentItem: Text {
                    text: selectedRadio.text
                    color: selectedRadio.enabled ? ColorPalette.textPrimary : ColorPalette.textDisabled
                    font: selectedRadio.font
                    verticalAlignment: Text.AlignVCenter
                    leftPadding: selectedRadio.indicator.width + selectedRadio.spacing
                }
            }

            StyledRadioButton {
                id: allRadio
                text: qsTr("Export all downloads")
                font.pixelSize: 12 * App.fontScale
                topPadding: 1; bottomPadding: 1
                contentItem: Text {
                    text: allRadio.text
                    color: ColorPalette.textPrimary
                    font: allRadio.font
                    verticalAlignment: Text.AlignVCenter
                    leftPadding: allRadio.indicator.width + allRadio.spacing
                }
            }
        }

        Item { Layout.fillHeight: true }

        RowLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignRight
            spacing: 8

            Item { Layout.fillWidth: true }

            DlgButton {
                text: qsTr("Cancel")
                onClicked: root.close()
            }

            DlgButton {
                text: qsTr("OK")
                primary: true
                onClicked: {
                    var mode = "all"
                    if (queueRadio.checked)
                        mode = "queue"
                    else if (selectedRadio.checked)
                        mode = "selected"
                    root.accepted(mode)
                    root.close()
                }
            }
        }
    }
}
