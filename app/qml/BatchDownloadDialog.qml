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
    title: "Batch download"
    width: 480
    height: 480
    minimumWidth: 400
    color: "#1e1e1e"
    flags: Qt.Dialog | Qt.WindowTitleHint | Qt.WindowCloseButtonHint
    modality: Qt.ApplicationModal

    Material.theme: Material.Dark
    Material.background: "#1e1e1e"
    Material.accent: "#4488dd"

    property string generatedPattern: ""
    signal accepted(var files)

    ColumnLayout {
        anchors { fill: parent; margins: 16 }
        spacing: 12

        Text {
            Layout.fillWidth: true
            text: "It's possible to add a group of sequential file names like img001.jpg, img002.jpg, etc., to Stellar download queue. Use the asterisk wildcard for the file name pattern.\nFor example: http://www.internetdownloadmanager.com/pictures/img*.jpg"
            color: "#c0c0c0"
            font.pixelSize: 12
            wrapMode: Text.WordWrap
        }

        RowLayout {
            Layout.fillWidth: true
            Label { text: "Address:"; color: "#c0c0c0"; font.pixelSize: 12 }
            TextField {
                id: addrField
                Layout.fillWidth: true
                font.pixelSize: 12
            }
        }

        GroupBox {
            Layout.fillWidth: true
            title: "Replace asterisk to"
            label: Text { text: "Replace asterisk to"; color: "#c0c0c0"; font.pixelSize: 12; font.bold: true }

            ColumnLayout {
                RowLayout {
                    RadioButton { id: numBtn; text: "Numbers"; checked: true; font.pixelSize: 12; contentItem: Text { text: parent.text; color: "#d0d0d0"; leftPadding: 20; font.pixelSize: 12 } }
                    RadioButton { id: letBtn; text: "Letters"; font.pixelSize: 12; contentItem: Text { text: parent.text; color: "#d0d0d0"; leftPadding: 20; font.pixelSize: 12 } }
                }

                RowLayout {
                    Label { text: "From:"; color: "#d0d0d0"; font.pixelSize: 12 }
                    TextField { id: fromField; text: numBtn.checked ? "0" : "a"; implicitWidth: 100 }
                    Label { text: "To:"; color: "#d0d0d0"; font.pixelSize: 12 }
                    TextField { id: toField; text: numBtn.checked ? "100" : "z"; implicitWidth: 100 }
                    Label { text: "Wildcard size:"; color: "#d0d0d0"; font.pixelSize: 12; visible: numBtn.checked }
                    TextField { id: sizeField; text: "2"; implicitWidth: 100; visible: numBtn.checked }
                }
            }
        }

        // Auth
        CheckBox {
            id: authCheck
            text: "Use authorization"
            contentItem: Text { text: parent.text; color: "#d0d0d0"; font.pixelSize: 12; leftPadding: 20 }
        }
        RowLayout {
            visible: authCheck.checked
            Label { text: "Login:"; color: "#c0c0c0"; font.pixelSize: 12 }
            TextField { id: loginField; Layout.fillWidth: true; background: Rectangle { color: "#2d2d2d"; radius: 3 } }
            Label { text: "Password:"; color: "#c0c0c0"; font.pixelSize: 12 }
            TextField { id: passField; echoMode: TextInput.Password; Layout.fillWidth: true; background: Rectangle { color: "#2d2d2d"; radius: 3 } }
        }

        // Previews
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 2
            Text { text: "First file: " + _preview(0); color: "#888"; font.pixelSize: 11; Layout.fillWidth: true; elide: Text.ElideMiddle }
            Text { text: "Second file: " + _preview(1); color: "#888"; font.pixelSize: 11; Layout.fillWidth: true; elide: Text.ElideMiddle }
            Text { text: "..."; color: "#888"; font.pixelSize: 11 }
            Text { text: "Last file: " + _preview(numBtn.checked ? (parseInt(toField.text) - parseInt(fromField.text)) : (toField.text.charCodeAt(0) - fromField.text.charCodeAt(0))); color: "#888"; font.pixelSize: 11; Layout.fillWidth: true; elide: Text.ElideMiddle }
        }

        Item { Layout.fillHeight: true }

        RowLayout {
            Layout.fillWidth: true
            Item { Layout.fillWidth: true }
            Button { 
                text: "Cancel"; 
                onClicked: root.close(); 
                implicitWidth: 80; implicitHeight: 30;
                background: Rectangle { color: "#3a3a3a"; radius: 0; border.color: "#555555"; border.width: 1 } 
                contentItem: Text { text: parent.text; color: "#d0d0d0"; font.pixelSize: 13; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
            }
            Button { 
                text: "OK"; 
                onClicked: { _generate(); root.accepted(generatedPattern); root.close() }
                implicitWidth: 80; implicitHeight: 30;
                background: Rectangle { color: "#1e3a6e"; radius: 0; border.color: "#4488dd"; border.width: 1 } 
                contentItem: Text { text: parent.text; color: "#ffffff"; font.pixelSize: 13; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
            }
        }
    }

    function _preview(idx) {
        if (!addrField.text) return ""
        var base = addrField.text
        var start = numBtn.checked ? parseInt(fromField.text) : fromField.text.charCodeAt(0)
        var val = start + idx
        var str = ""
        if (numBtn.checked) {
            str = val.toString().padStart(parseInt(sizeField.text), '0')
        } else {
            str = String.fromCharCode(val)
        }
        return base.replace("*", str)
    }

    function _generate() {
        var files = []
        var base = addrField.text
        var start = numBtn.checked ? parseInt(fromField.text) : fromField.text.charCodeAt(0)
        var end = numBtn.checked ? parseInt(toField.text) : toField.text.charCodeAt(0)
        var size = numBtn.checked ? parseInt(sizeField.text) : 1
        
        for(var i = start; i <= end; i++) {
            var val = numBtn.checked ? i.toString().padStart(size, '0') : String.fromCharCode(i)
            files.push(base.replace("*", val))
        }
        generatedPattern = files.join("\n")
    }
}
