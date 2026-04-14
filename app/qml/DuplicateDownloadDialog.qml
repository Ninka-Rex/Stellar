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
    title: "Duplicate Download Link"
    color: "#1e1e1e"
    flags: Qt.Dialog | Qt.WindowTitleHint | Qt.WindowCloseButtonHint
    modality: Qt.ApplicationModal

    Material.theme: Material.Dark
    Material.background: "#1e1e1e"
    Material.accent: "#4488dd"

    property int selectedAction: 3

    onVisibleChanged: {
        if (visible) {
            var isComplete = existingItem && existingItem.status === "Completed"
            selectedAction = isComplete ? 1 : 3
            rememberChk.checked = false
            raise()
            requestActivate()
        }
    }

    ColumnLayout {
        anchors { fill: parent; margins: 18 }
        spacing: 0

        Text {
            text: "This file already exists in your download list."
            color: "#e0e0e0"; font.pixelSize: 13; font.bold: true
            wrapMode: Text.WordWrap; Layout.fillWidth: true
        }

        Item { Layout.preferredHeight: 4 }

        Text {
            text: root.existingItem ? root.existingItem.filename : ""
            color: "#4488dd"; font.pixelSize: 12
            elide: Text.ElideMiddle; Layout.fillWidth: true
        }

        Item { Layout.preferredHeight: 8 }
        Rectangle { Layout.fillWidth: true; height: 1; color: "#2e2e2e" }
        Item { Layout.preferredHeight: 8 }

        Text {
            text: "You may choose one of the following options, or press Cancel to skip the download."
            color: "#a0a0a0"; font.pixelSize: 11
            wrapMode: Text.WordWrap; Layout.fillWidth: true
        }

        Item { Layout.preferredHeight: 12 }

        OptionRow {
            Layout.fillWidth: true
            selected: root.selectedAction === 1
            label: "Add the duplicate with a numbered file name"
            onChosen: root.selectedAction = 1
        }

        Item { Layout.preferredHeight: 6 }

        OptionRow {
            Layout.fillWidth: true
            selected: root.selectedAction === 2
            label: "Add the duplicate and overwrite the existing file"
            onChosen: root.selectedAction = 2
        }

        Item { Layout.preferredHeight: 6 }

        OptionRow {
            Layout.fillWidth: true
            selected: root.selectedAction === 3
            label: (root.existingItem && root.existingItem.status === "Completed")
                       ? "The existing file is complete - show the download complete dialog"
                       : "Resume the existing download"
            onChosen: root.selectedAction = 3
        }

        Item { Layout.preferredHeight: 12 }
        Rectangle { Layout.fillWidth: true; height: 1; color: "#2e2e2e" }
        Item { Layout.preferredHeight: 8 }

        CheckBox {
            id: rememberChk
            text: "Remember my selection and don't show this dialog again.\nYou may change it in Options → Downloads at a later time."
            font.pixelSize: 11
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
                text: "Cancel"
                onClicked: root.close()
            }

            DlgButton {
                text: "OK"
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
                border.color: parent.parent.selected ? "#4488dd" : "#666666"
                border.width: 2
                Rectangle {
                    anchors.centerIn: parent; width: 8; height: 8; radius: 4
                    color: "#4488dd"; visible: parent.parent.parent.selected
                }
            }

            Text {
                text: parent.parent.label
                color: parent.parent.selected ? "#e0e0e0" : "#a0a0a0"
                font.pixelSize: 12; Layout.fillWidth: true; wrapMode: Text.WordWrap
            }
        }

        MouseArea {
            anchors.fill: parent; cursorShape: Qt.PointingHandCursor
            onClicked: parent.chosen()
        }
    }
}
