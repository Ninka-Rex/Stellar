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
    width: 440
    height: mainCol.implicitHeight + 24
    color: ColorPalette.cardBg
    flags: Qt.Window | Qt.WindowTitleHint | Qt.WindowCloseButtonHint | Qt.MSWindowsFixedSizeDialogHint
    modality: Qt.ApplicationModal
    title: qsTr("Max. connections number for a server")

    Material.theme: ColorPalette.materialTheme
    Material.foreground: ColorPalette.textPrimary
    Material.background: ColorPalette.materialBg
    Material.accent: "#4488dd"

    // Caller sets these before show(); accepted() reads them back.
    property int    editIndex:   -1
    property string serverValue: ""
    property int    connsValue:  1

    signal accepted()

    component ThemedSpin: SpinBox {
        id: _tspin
        editable: true
        implicitWidth: 80
        contentItem: TextInput {
            text: _tspin.textFromValue(_tspin.value, _tspin.locale)
            color: ColorPalette.textPrimary
            font.pixelSize: 13 * App.fontScale
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            readOnly: !_tspin.editable
            validator: _tspin.validator
        }
        up.indicator: Rectangle {
            x: _tspin.width - width; y: 0
            width: 22; height: _tspin.height / 2
            color: _tspin.up.pressed ? ColorPalette.toolbarPressBg
                 : _tspin.up.hovered ? ColorPalette.toolbarHoverBg
                 : ColorPalette.panelBg
            Text { anchors.centerIn: parent; text: "+"; color: ColorPalette.textPrimary; font.pixelSize: 11 * App.fontScale }
        }
        down.indicator: Rectangle {
            x: _tspin.width - width; y: _tspin.height / 2
            width: 22; height: _tspin.height / 2
            color: _tspin.down.pressed ? ColorPalette.toolbarPressBg
                 : _tspin.down.hovered ? ColorPalette.toolbarHoverBg
                 : ColorPalette.panelBg
            Text { anchors.centerIn: parent; text: "–"; color: ColorPalette.textPrimary; font.pixelSize: 11 * App.fontScale }
        }
        background: Rectangle { color: ColorPalette.inputBg; border.color: ColorPalette.border; radius: 2 }
    }

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
            serverField.text = serverValue
            connsSpin.value = Math.max(1, Math.min(32, connsValue))
            serverField.forceActiveFocus()
        }
    }

    ColumnLayout {
        id: mainCol
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
        spacing: 10

        Text { text: qsTr("Server"); color: ColorPalette.textHeader; font.pixelSize: 14 * App.fontScale; font.bold: true }

        TextField {
            id: serverField
            Layout.fillWidth: true
            selectByMouse: true
            placeholderText: "http://*.example.com"
            font.pixelSize: 13 * App.fontScale
            color: ColorPalette.textPrimary
            background: Rectangle {
                color: ColorPalette.dividerBg
                border.color: parent.activeFocus ? "#4488dd" : ColorPalette.border
                radius: 3
            }
        }

        Text {
            text: qsTr("You may use asterisk as a wildcard pattern")
            color: ColorPalette.textSecond; font.pixelSize: 12 * App.fontScale
            wrapMode: Text.WordWrap; Layout.fillWidth: true
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            Text { text: qsTr("Max. connections number:"); color: ColorPalette.textPrimary; font.pixelSize: 13 * App.fontScale; Layout.fillWidth: true }
            ThemedSpin { id: connsSpin; from: 1; to: 32; value: 1 }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: 4
            spacing: 8
            Item { Layout.fillWidth: true }
            DlgButton { text: qsTr("Cancel"); onClicked: root.close() }
            DlgButton {
                text: qsTr("OK"); primary: true
                enabled: serverField.text.trim().length > 0
                onClicked: {
                    root.serverValue = serverField.text.trim()
                    root.connsValue  = connsSpin.value
                    root.accepted()
                    root.close()
                }
            }
        }
    }
}
