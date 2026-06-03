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
    width: 460
    height: mainCol.implicitHeight + 24
    color: ColorPalette.cardBg
    flags: Qt.Window | Qt.WindowTitleHint | Qt.WindowCloseButtonHint | Qt.MSWindowsFixedSizeDialogHint
    modality: Qt.ApplicationModal

    Material.theme: ColorPalette.materialTheme
    Material.foreground: ColorPalette.textPrimary
    Material.background: ColorPalette.materialBg
    Material.accent: "#4488dd"

    property alias url:      urlField.text
    property alias username: usernameField.text
    property alias password: passwordField.text
    property alias useAuth:  authCheck.checked
    property string titleOverride: ""

    title: titleOverride.length > 0 ? titleOverride : qsTr("Add URL")

    signal accepted()

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
            if (titleOverride.length === 0) {
                var clip = App.clipboardUrl()
                urlField.text = clip ? clip : ""
                if (clip) urlField.selectAll()
            }
            urlField.forceActiveFocus()
        } else {
            titleOverride = ""
        }
    }

    function _submit() {
        if (urlField.text.trim().length === 0) return
        var trimmed = urlField.text.trim()
        if (/^[0-9a-fA-F]{40}$/.test(trimmed)) {
            urlField.text = "magnet:?xt=urn:btih:" + trimmed.toLowerCase()
        } else if (!/^[a-zA-Z][a-zA-Z0-9+\-.]*:/.test(trimmed)) {
            // ── No scheme assume https so isLikelyYtdlpUrl and QUrl parse correctly ──
            urlField.text = "https://" + trimmed
        }
        root.accepted()
        root.close()
    }

    ColumnLayout {
        id: mainCol
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
        spacing: 8

        // URL row
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 2
            Text { text: qsTr("URL"); color: ColorPalette.textSecond; font.pixelSize: 11 * App.fontScale }
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 22
                color: ColorPalette.inputBg
                border.color: urlField.activeFocus ? "#4488dd" : ColorPalette.border
                border.width: 1
                radius: 2
                TextInput {
                    id: urlField
                    anchors.fill: parent
                    anchors.leftMargin: 5
                    anchors.rightMargin: 5
                    verticalAlignment: TextInput.AlignVCenter
                    color: ColorPalette.textPrimary
                    font.pixelSize: 11 * App.fontScale
                    selectByMouse: true
                    clip: true
                    Keys.onReturnPressed: root._submit()
                    Keys.onEnterPressed:  root._submit()
                }
            }
        }

        // Auth checkbox
        StyledCheckBox {
            id: authCheck
            text: qsTr("Use Authorization")
            topPadding: 0; bottomPadding: 0
            contentItem: Text {
                text: parent.text; color: ColorPalette.textPrimary; font.pixelSize: 11 * App.fontScale
                leftPadding: parent.indicator.width + 4
                verticalAlignment: Text.AlignVCenter
            }
        }

        // Auth fields
        ColumnLayout {
            visible: authCheck.checked
            Layout.fillWidth: true
            spacing: 6

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2
                Text { text: qsTr("Login"); color: ColorPalette.textSecond; font.pixelSize: 11 * App.fontScale }
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 22
                    color: ColorPalette.inputBg
                    border.color: usernameField.activeFocus ? "#4488dd" : ColorPalette.border
                    border.width: 1
                    radius: 2
                    TextInput {
                        id: usernameField
                        anchors.fill: parent
                        anchors.leftMargin: 5
                        anchors.rightMargin: 5
                        verticalAlignment: TextInput.AlignVCenter
                        color: ColorPalette.textPrimary
                        font.pixelSize: 11 * App.fontScale
                        selectByMouse: true
                        clip: true
                        Keys.onReturnPressed: root._submit()
                        Keys.onEnterPressed:  root._submit()
                    }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2
                Text { text: qsTr("Password"); color: ColorPalette.textSecond; font.pixelSize: 11 * App.fontScale }
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 22
                    color: ColorPalette.inputBg
                    border.color: passwordField.activeFocus ? "#4488dd" : ColorPalette.border
                    border.width: 1
                    radius: 2
                    TextInput {
                        id: passwordField
                        anchors.fill: parent
                        anchors.leftMargin: 5
                        anchors.rightMargin: 5
                        verticalAlignment: TextInput.AlignVCenter
                        color: ColorPalette.textPrimary
                        font.pixelSize: 11 * App.fontScale
                        echoMode: TextInput.Password
                        selectByMouse: true
                        clip: true
                        Keys.onReturnPressed: root._submit()
                        Keys.onEnterPressed:  root._submit()
                    }
                }
            }
        }

        // Buttons
        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: 2
            spacing: 6
            Item { Layout.fillWidth: true }
            DlgButton { text: qsTr("Cancel"); onClicked: root.close() }
            DlgButton { text: qsTr("OK"); primary: true; onClicked: root._submit() }
        }
    }
}
