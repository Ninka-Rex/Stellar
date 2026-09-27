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

// Window shared by the yt-dlp dialogs: a header naming what is being
// downloaded, the dialog's body, and a footer with the primary action and
// Cancel laid out like the settings window's.
Window {
    id: frame

    property string heading
    property string subheading
    property string primaryText
    property bool primaryEnabled: true
    default property alias content: body.data

    signal accepted()

    color: ColorPalette.cardBg
    modality: Qt.NonModal
    flags: Qt.Dialog | Qt.WindowTitleHint | Qt.WindowCloseButtonHint

    Material.theme: ColorPalette.materialTheme
    Material.foreground: ColorPalette.textPrimary
    Material.background: ColorPalette.materialBg
    Material.accent: "#4488dd"

    function _centerOnOwner() {
        var owner = frame.transientParent
        if (owner) {
            x = owner.x + Math.round((owner.width - width) / 2)
            y = owner.y + Math.round((owner.height - height) / 2)
        } else {
            x = Math.round((Screen.width - width) / 2)
            y = Math.round((Screen.height - height) / 2)
        }
    }

    onVisibleChanged: {
        if (!visible)
            return
        _centerOnOwner()
        App.setWindowIcon(frame, ":/qt/qml/com/stellar/app/app/qml/icons/actions/magic-wand.svg")
        App.setWindowDarkTitleBar(frame, App.settings.darkMode)
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: headerText.implicitHeight + 20
            color: ColorPalette.headerStripBg

            ColumnLayout {
                id: headerText
                anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter
                          leftMargin: 16; rightMargin: 16 }
                spacing: 2

                Text {
                    Layout.fillWidth: true
                    // Titles and names come from the site.
                    text: frame.heading
                    textFormat: Text.PlainText
                    color: ColorPalette.textHeader
                    font.pixelSize: 14 * App.fontScale
                    font.bold: true
                    elide: Text.ElideRight
                }
                Text {
                    Layout.fillWidth: true
                    visible: frame.subheading.length > 0
                    text: frame.subheading
                    textFormat: Text.PlainText
                    color: ColorPalette.textMuted
                    font.pixelSize: 11 * App.fontScale
                    elide: Text.ElideMiddle
                }
            }
        }
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 1
            color: ColorPalette.border
        }

        Item {
            id: body
            Layout.fillWidth: true
            Layout.fillHeight: true
        }

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 1
            color: ColorPalette.border
        }
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 52
            color: ColorPalette.panelBg

            RowLayout {
                anchors { right: parent.right; verticalCenter: parent.verticalCenter; rightMargin: 12 }
                spacing: 8

                DlgButton {
                    text: frame.primaryText
                    primary: true
                    enabled: frame.primaryEnabled
                    onClicked: frame.accepted()
                }
                DlgButton {
                    text: qsTr("Cancel")
                    onClicked: frame.close()
                }
            }
        }
    }
}
