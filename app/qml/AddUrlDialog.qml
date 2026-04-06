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
    title: "Add Download"
    width: 420
    height: authCheck.checked ? 230 : 160
    minimumWidth: 360
    color: "#1e1e1e"
    flags: Qt.Dialog | Qt.WindowTitleHint | Qt.WindowCloseButtonHint
    modality: Qt.ApplicationModal

    Material.theme: Material.Dark
    Material.background: "#1e1e1e"
    Material.accent: "#4488dd"

    property alias url:      urlField.text
    property alias username: usernameField.text
    property alias password: passwordField.text
    property alias useAuth:  authCheck.checked

    signal accepted()

    onVisibleChanged: {
        if (visible) {
            var clip = App.clipboardUrl()
            urlField.text = clip ? clip : ""
            urlField.forceActiveFocus()
            if (clip) urlField.selectAll()
        }
    }

    function _submit() {
        if (urlField.text.trim().length === 0) return
        root.accepted()
        root.close()
    }

    ColumnLayout {
        anchors { fill: parent; margins: 16 }
        spacing: 10

        // URL row
        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            Label { text: "URL:"; color: "#c0c0c0"; font.pixelSize: 12; Layout.preferredWidth: 70 }
            TextField {
                id: urlField
                Layout.fillWidth: true
                placeholderText: "https://example.com/file.zip"
                selectByMouse: true
                font.pixelSize: 12
                background: Rectangle { color: "#2d2d2d"; border.color: "#4a4a4a"; radius: 3 }
                color: "#d0d0d0"
                Keys.onReturnPressed: root._submit()
                Keys.onEnterPressed:  root._submit()
            }
        }

        // Auth checkbox
        CheckBox {
            id: authCheck
            text: "Use Authorization"
            topPadding: 0; bottomPadding: 0
            contentItem: Text {
                text: parent.text; color: "#d0d0d0"; font.pixelSize: 12
                leftPadding: parent.indicator.width + 4
                verticalAlignment: Text.AlignVCenter
            }
        }

        // Auth fields (only when auth is checked)
        ColumnLayout {
            visible: authCheck.checked
            Layout.fillWidth: true
            spacing: 6

            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                Label { text: "Login:"; color: "#c0c0c0"; font.pixelSize: 12; Layout.preferredWidth: 70 }
                TextField {
                    id: usernameField
                    Layout.fillWidth: true
                    placeholderText: "Username"
                    selectByMouse: true
                    font.pixelSize: 12
                    background: Rectangle { color: "#2d2d2d"; border.color: "#4a4a4a"; radius: 3 }
                    color: "#d0d0d0"
                    Keys.onReturnPressed: root._submit()
                    Keys.onEnterPressed:  root._submit()
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                Label { text: "Password:"; color: "#c0c0c0"; font.pixelSize: 12; Layout.preferredWidth: 70 }
                TextField {
                    id: passwordField
                    Layout.fillWidth: true
                    placeholderText: "Password"
                    echoMode: TextInput.Password
                    selectByMouse: true
                    font.pixelSize: 12
                    background: Rectangle { color: "#2d2d2d"; border.color: "#4a4a4a"; radius: 3 }
                    color: "#d0d0d0"
                    Keys.onReturnPressed: root._submit()
                    Keys.onEnterPressed:  root._submit()
                }
            }
        }

        Item { Layout.fillHeight: true }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            Item { Layout.fillWidth: true }
            Button {
                text: "Cancel"
                implicitWidth: 80
                background: Rectangle { color: "#3a3a3a"; radius: 3; border.color: "#555555"; border.width: 1 }
                contentItem: Text { text: parent.text; color: "#d0d0d0"; font.pixelSize: 13; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                onClicked: root.close()
            }
            Button {
                text: "OK"
                implicitWidth: 80
                background: Rectangle { color: "#1e3a6e"; radius: 3; border.color: "#4488dd"; border.width: 1 }
                contentItem: Text { text: parent.text; color: "#ffffff"; font.pixelSize: 13; font.bold: true; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                onClicked: root._submit()
            }
        }
    }
}
