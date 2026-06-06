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
import QtQuick.Controls.Material
import QtQuick.Layouts

Window {
    id: root
    title: qsTr("Settings of Stellar Grabber")
    // Content-driven width so long translations (e.g. French) aren't clipped.
    width: Math.max(520, mainCol.implicitWidth + 24)
    height: Math.max(320, mainCol.implicitHeight + 24)
    minimumWidth: 500
    minimumHeight: 300
    color: ColorPalette.cardBg
    flags: Qt.Dialog | Qt.WindowTitleHint | Qt.WindowCloseButtonHint
    modality: Qt.ApplicationModal

    Material.theme: ColorPalette.materialTheme
    Material.foreground: ColorPalette.textPrimary
    Material.background: ColorPalette.materialBg

    component ThemedSpin: SpinBox {
        id: _tspin
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
            color: _tspin.up.pressed ? ColorPalette.toolbarPressBg : _tspin.up.hovered ? ColorPalette.toolbarHoverBg : ColorPalette.panelBg
            Text { anchors.centerIn: parent; text: "+"; color: ColorPalette.textPrimary; font.pixelSize: 11 * App.fontScale }
        }
        down.indicator: Rectangle {
            x: _tspin.width - width; y: _tspin.height / 2
            width: 22; height: _tspin.height / 2
            color: _tspin.down.pressed ? ColorPalette.toolbarPressBg : _tspin.down.hovered ? ColorPalette.toolbarHoverBg : ColorPalette.panelBg
            Text { anchors.centerIn: parent; text: "−"; color: ColorPalette.textPrimary; font.pixelSize: 11 * App.fontScale }
        }
        background: Rectangle { color: ColorPalette.inputBg; border.color: ColorPalette.border; radius: 2 }
    }

    Rectangle {
        anchors.fill: parent
        color: ColorPalette.cardBg

        ColumnLayout {
            id: mainCol
            anchors.fill: parent
            anchors.margins: 12
            spacing: 10

            RowLayout {
                Layout.fillWidth: true
                ThemedSpin { id: exploreSpin; from: 1; to: 10; value: App.settings.grabberFilesToExploreAtOnce; editable: true }
                Text { Layout.fillWidth: true; text: qsTr("files to explore at the same time (1 to 10)"); color: ColorPalette.textPrimary; font.pixelSize: 12 * App.fontScale; wrapMode: Text.WordWrap }
            }

            RowLayout {
                Layout.fillWidth: true
                ThemedSpin { id: downloadSpin; from: 1; to: 10; value: App.settings.grabberFilesToDownloadAtOnce; editable: true }
                Text { Layout.fillWidth: true; text: qsTr("files to download at the same time (1 to 10)"); color: ColorPalette.textPrimary; font.pixelSize: 12 * App.fontScale; wrapMode: Text.WordWrap }
            }

            Text {
                Layout.fillWidth: true
                text: qsTr("Please note that a web server may reject requests if you set a large number of files to explore or download at the same time.")
                color: ColorPalette.textSecond
                font.pixelSize: 11 * App.fontScale
                wrapMode: Text.WordWrap
            }

            Rectangle { Layout.fillWidth: true; height: 1; color: ColorPalette.border }

            StyledCheckBox {
                id: descriptionChk
                text: qsTr("Use link texts as download descriptions when adding files to Stellar main list")
                checked: App.settings.grabberUseLinkTextAsDescription
                topPadding: 0
                bottomPadding: 0
            }

            Item { Layout.fillHeight: true }

            RowLayout {
                Layout.fillWidth: true
                Item { Layout.fillWidth: true }
                DlgButton { text: qsTr("Cancel"); onClicked: root.close() }
                DlgButton {
                    text: qsTr("OK")
                    primary: true
                    onClicked: {
                        App.settings.grabberFilesToExploreAtOnce = exploreSpin.value
                        App.settings.grabberFilesToDownloadAtOnce = downloadSpin.value
                        App.settings.grabberUseLinkTextAsDescription = descriptionChk.checked
                        root.close()
                    }
                }
            }
        }
    }
}
