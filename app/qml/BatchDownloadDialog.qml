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
    title: "Batch Download"
    width: 680
    height: 360
    minimumWidth: 560
    minimumHeight: 300
    color: "#232323"
    flags: Qt.Dialog | Qt.WindowTitleHint | Qt.WindowCloseButtonHint
    modality: Qt.ApplicationModal

    Material.theme: Material.Dark
    Material.background: "#232323"
    Material.accent: "#5a8ec8"

    property string generatedPattern: ""
    property string _firstLink: ""
    property string _secondLink: ""
    property string _lastLink: ""
    signal accepted(var files)

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
        if (visible) _centerOnOwner()
    }

    Component.onCompleted: _refreshPreview()

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 14
        spacing: 10

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4
            Text { text: "Batch Download"; color: "#ffffff"; font.pixelSize: 16; font.bold: true }
            Text { text: "Generate the links here, then continue to the review step."; color: "#a9a9a9"; font.pixelSize: 10; wrapMode: Text.WordWrap; Layout.fillWidth: true }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            Label { text: "Address:"; color: "#d0d0d0"; font.pixelSize: 12 }
            TextField {
                id: addrField
                Layout.fillWidth: true
                font.pixelSize: 12
                color: "#e8edf5"
                background: Rectangle { color: "#232323"; border.color: "#4a4a4a"; radius: 0 }
                onTextChanged: root._refreshPreview()
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 6
            Text { text: "Replace asterisk with"; color: "#d6dbe4"; font.pixelSize: 11; font.bold: true }

            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                RadioButton {
                    id: numBtn
                    text: "Numbers"
                    checked: true
                    font.pixelSize: 11
                    contentItem: Text { text: parent.text; color: "#d0d0d0"; leftPadding: 20; font.pixelSize: 11; verticalAlignment: Text.AlignVCenter }
                    onCheckedChanged: root._refreshPreview()
                }
                RadioButton {
                    id: letBtn
                    text: "Letters"
                    font.pixelSize: 11
                    contentItem: Text { text: parent.text; color: "#d0d0d0"; leftPadding: 20; font.pixelSize: 11; verticalAlignment: Text.AlignVCenter }
                    onCheckedChanged: root._refreshPreview()
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 6
                Label { text: "From:"; color: "#d0d0d0"; font.pixelSize: 11 }
                TextField {
                    id: fromField
                    text: numBtn.checked ? "0" : "a"
                    implicitWidth: 72
                    background: Rectangle { color: "#232323"; border.color: "#4a4a4a"; radius: 0 }
                    color: "#e8edf5"
                    onTextChanged: root._refreshPreview()
                }
                Label { text: "To:"; color: "#d0d0d0"; font.pixelSize: 11 }
                TextField {
                    id: toField
                    text: numBtn.checked ? "100" : "z"
                    implicitWidth: 72
                    background: Rectangle { color: "#232323"; border.color: "#4a4a4a"; radius: 0 }
                    color: "#e8edf5"
                    onTextChanged: root._refreshPreview()
                }
                Label { text: "Wildcard size:"; color: "#d0d0d0"; font.pixelSize: 11; visible: numBtn.checked }
                TextField {
                    id: sizeField
                    text: "2"
                    implicitWidth: 56
                    visible: numBtn.checked
                    background: Rectangle { color: "#232323"; border.color: "#4a4a4a"; radius: 0 }
                    color: "#e8edf5"
                    onTextChanged: root._refreshPreview()
                }
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4
            Text { text: "Preview"; color: "#ffffff"; font.pixelSize: 12; font.bold: true }
            Text { text: "First: " + (root._firstLink.length ? root._firstLink : "--"); color: "#e0e0e0"; font.pixelSize: 10; elide: Text.ElideMiddle; Layout.fillWidth: true }
            Text { text: "Second: " + (root._secondLink.length ? root._secondLink : "--"); color: "#e0e0e0"; font.pixelSize: 10; elide: Text.ElideMiddle; Layout.fillWidth: true }
            Text { text: "Last: " + (root._lastLink.length ? root._lastLink : "--"); color: "#e0e0e0"; font.pixelSize: 10; elide: Text.ElideMiddle; Layout.fillWidth: true }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            Text {
                Layout.fillWidth: true
                text: "Use the queue step after OK if you want these downloads grouped before they start."
                color: "#9a9a9a"
                font.pixelSize: 9
            }
            DlgButton {
                text: "Cancel"
                onClicked: root.close()
            }
            DlgButton {
                text: "OK"
                primary: true
                onClicked: { _generate(); root.accepted(generatedPattern); root.close() }
            }
        }
    }

    function _generate() {
        var files = []
        var base = addrField.text
        var start = numBtn.checked ? parseInt(fromField.text) : fromField.text.charCodeAt(0)
        var end = numBtn.checked ? parseInt(toField.text) : toField.text.charCodeAt(0)
        var size = numBtn.checked ? parseInt(sizeField.text) : 1
        if (base.length === 0 || base.indexOf("*") === -1 || isNaN(start) || isNaN(end) || (numBtn.checked && isNaN(size)))
            return []
        for (var i = start; i <= end; i++) {
            var val = numBtn.checked ? i.toString().padStart(size, '0') : String.fromCharCode(i)
            files.push(base.replace("*", val))
        }
        generatedPattern = files.join("\n")
        return files
    }

    function _refreshPreview() {
        var files = _generate()
        root._firstLink = files.length > 0 ? files[0] : ""
        root._secondLink = files.length > 1 ? files[1] : ""
        root._lastLink = files.length > 0 ? files[files.length - 1] : ""
    }
}
