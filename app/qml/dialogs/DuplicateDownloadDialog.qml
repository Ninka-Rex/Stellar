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

    property var existingItem: null   // the DownloadItem* that already exists

    signal resolved(int action, bool remember)  // 1=AddNumbered, 2=Overwrite, 3=Resume

    width: 480
    height: 300
    minimumWidth: 480
    minimumHeight: 300
    title: qsTr("Duplicate Download Link")
    color: ColorPalette.cardBg
    flags: Qt.Dialog | Qt.WindowTitleHint | Qt.WindowCloseButtonHint
    modality: Qt.ApplicationModal

    Material.theme: ColorPalette.materialTheme
    Material.foreground: ColorPalette.textPrimary
    Material.background: ColorPalette.materialBg
    Material.accent: "#4488dd"

    property int selectedAction: 3

    onVisibleChanged: {
        if (visible) {
            var isComplete = existingItem && existingItem.status === "Completed"
            selectedAction = isComplete ? 1 : 3
            rememberChk.checked = false
            // No transient parent — centre on the screen ourselves.
            if (Screen) {
                x = Math.round((Screen.width  - width)  / 2) + Screen.virtualX
                y = Math.round((Screen.height - height) / 2) + Screen.virtualY
            }
            raise()
            requestActivate()
        }
    }

    ColumnLayout {
        anchors { fill: parent; margins: 18 }
        spacing: 0

        Text {
            text: qsTr("This file already exists in your download list.")
            color: ColorPalette.textPrimary; font.pixelSize: 13 * App.fontScale; font.bold: true
            wrapMode: Text.WordWrap; Layout.fillWidth: true
        }

        Item { Layout.preferredHeight: 4 }

        Text {
            text: root.existingItem ? root.existingItem.filename : ""
            color: "#4488dd"; font.pixelSize: 12 * App.fontScale
            elide: Text.ElideMiddle; Layout.fillWidth: true
        }

        Item { Layout.preferredHeight: 8 }
        Rectangle { Layout.fillWidth: true; height: 1; color: ColorPalette.border }
        Item { Layout.preferredHeight: 8 }

        Text {
            text: qsTr("You may choose one of the following options, or press Cancel to skip the download.")
            color: "#a0a0a0"; font.pixelSize: 11 * App.fontScale
            wrapMode: Text.WordWrap; Layout.fillWidth: true
        }

        Item { Layout.preferredHeight: 12 }

        OptionRow {
            Layout.fillWidth: true
            selected: root.selectedAction === 1
            label: qsTr("Add the duplicate with a numbered file name")
            onChosen: root.selectedAction = 1
        }

        Item { Layout.preferredHeight: 6 }

        OptionRow {
            Layout.fillWidth: true
            selected: root.selectedAction === 2
            label: qsTr("Add the duplicate and overwrite the existing file")
            onChosen: root.selectedAction = 2
        }

        Item { Layout.preferredHeight: 6 }

        OptionRow {
            Layout.fillWidth: true
            selected: root.selectedAction === 3
            label: (root.existingItem && root.existingItem.status === "Completed")
                       ? qsTr("The existing file is complete - show the download complete dialog")
                       : qsTr("Resume the existing download")
            onChosen: root.selectedAction = 3
        }

        Item { Layout.preferredHeight: 12 }
        Rectangle { Layout.fillWidth: true; height: 1; color: ColorPalette.border }
        Item { Layout.preferredHeight: 8 }

        StyledCheckBox {
            id: rememberChk
            text: qsTr("Remember my selection and don't show this dialog again.\nYou may change it in Options ? Downloads at a later time.")
            font.pixelSize: 11 * App.fontScale
            contentItem: Text {
                text: rememberChk.text; color: "#909090"; font: rememberChk.font
                leftPadding: rememberChk.indicator.width + 6
                verticalAlignment: Text.AlignVCenter; wrapMode: Text.WordWrap
            }
        }

        Item { Layout.fillHeight: true }

        RowLayout {
            Layout.fillWidth: true; spacing: 8
            Item { Layout.fillWidth: true }

            DlgButton {
                text: qsTr("Cancel")
                onClicked: root.close()
            }

            DlgButton {
                text: qsTr("OK")
                primary: true
                onClicked: {
                    root.resolved(root.selectedAction, rememberChk.checked)
                    root.close()
                }
            }
        }
    }

    component OptionRow: Item {
        property bool   selected: false
        property string label: ""
        signal chosen()
        implicitHeight: 22

        RowLayout {
            anchors.fill: parent; spacing: 10

            Rectangle {
                width: 16; height: 16; radius: 8
                color: "transparent"
                border.color: parent.parent.selected ? "#4488dd" : ColorPalette.textDisabled
                border.width: 2
                Rectangle {
                    anchors.centerIn: parent; width: 8; height: 8; radius: 4
                    color: "#4488dd"; visible: parent.parent.parent.selected
                }
            }

            Text {
                text: parent.parent.label
                color: parent.parent.selected ? ColorPalette.textPrimary : "#a0a0a0"
                font.pixelSize: 12 * App.fontScale; Layout.fillWidth: true; wrapMode: Text.WordWrap
            }
        }

        MouseArea {
            anchors.fill: parent; cursorShape: Qt.PointingHandCursor
            onClicked: parent.chosen()
        }
    }
}
