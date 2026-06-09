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
    title: qsTr("Batch Download")
    width: 680
    height: mainCol.implicitHeight + 28
    minimumWidth: 560
    color: ColorPalette.cardBg
    flags: Qt.Dialog | Qt.WindowTitleHint | Qt.WindowCloseButtonHint | Qt.MSWindowsFixedSizeDialogHint
    modality: Qt.ApplicationModal

    Material.theme: ColorPalette.materialTheme
    Material.foreground: ColorPalette.textPrimary
    Material.background: ColorPalette.materialBg
    Material.accent: "#5a8ec8"

    property string generatedPattern: ""
    property string _firstLink: ""
    property string _secondLink: ""
    property string _lastLink: ""
    property int    _totalCount: 0
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

    // Shared input-field background so every TextField matches and shows a focus ring.
    component FieldBg: Rectangle {
        property bool focused: false
        color: ColorPalette.inputBg
        border.color: focused ? "#4488dd" : ColorPalette.border
        radius: 3
    }

    ColumnLayout {
        id: mainCol
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 14 }
        spacing: 12

        // ── Title ──────────────────────────────────────────────────────────
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 2
            Text { text: qsTr("Batch Download"); color: ColorPalette.textHeader; font.pixelSize: 16 * App.fontScale; font.bold: true }
            Text { text: qsTr("Generate a group of sequential links from one address, then review them before downloading."); color: ColorPalette.textSecond; font.pixelSize: 10 * App.fontScale; wrapMode: Text.WordWrap; Layout.fillWidth: true }
        }

        // ── Explainer (IDM-style how-to with an example) ───────────────────
        Rectangle {
            Layout.fillWidth: true
            color: ColorPalette.infoBoxBg
            border.color: ColorPalette.selectionBg
            radius: 4
            implicitHeight: explainCol.implicitHeight + 16

            ColumnLayout {
                id: explainCol
                anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; leftMargin: 10; rightMargin: 10 }
                spacing: 3
                Text {
                    Layout.fillWidth: true
                    text: qsTr("Add a group of sequential files like img001.jpg, img002.jpg, img100.jpg in one step. Put an asterisk (*) where the number or letter changes, and it becomes the file-name pattern.")
                    color: ColorPalette.infoBoxText
                    font.pixelSize: 10 * App.fontScale
                    wrapMode: Text.WordWrap
                }
                Text {
                    text: qsTr("Example:  https://www.example.com/pictures/img*.jpg")
                    color: ColorPalette.infoBoxText
                    font.pixelSize: 10 * App.fontScale
                    font.family: "Consolas, monospace"
                }
            }
        }

        // ── Address ────────────────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            Label { text: qsTr("Address:"); color: ColorPalette.textPrimary; font.pixelSize: 12 * App.fontScale; Layout.preferredWidth: 64 }
            TextField {
                id: addrField
                Layout.fillWidth: true
                font.pixelSize: 12 * App.fontScale
                color: ColorPalette.textPrimary
                placeholderText: qsTr("https://www.example.com/pictures/img*.jpg")
                background: FieldBg { focused: addrField.activeFocus }
                onTextChanged: root._refreshPreview()
            }
        }

        // ── Pattern options card ───────────────────────────────────────────
        Rectangle {
            Layout.fillWidth: true
            color: ColorPalette.panelBg
            border.color: ColorPalette.border
            radius: 4
            implicitHeight: patternCol.implicitHeight + 20

            ColumnLayout {
                id: patternCol
                anchors { left: parent.left; right: parent.right; top: parent.top; leftMargin: 10; rightMargin: 10; topMargin: 10 }
                spacing: 8

                Text { text: qsTr("Replace asterisk with"); color: ColorPalette.textPrimary; font.pixelSize: 11 * App.fontScale; font.bold: true }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 16
                    StyledRadioButton {
                        id: numBtn
                        text: qsTr("Numbers")
                        checked: true
                        font.pixelSize: 11 * App.fontScale
                        contentItem: Text { text: parent.text; color: ColorPalette.textPrimary; leftPadding: 20; font.pixelSize: 11 * App.fontScale; verticalAlignment: Text.AlignVCenter }
                        onCheckedChanged: root._refreshPreview()
                    }
                    StyledRadioButton {
                        id: letBtn
                        text: qsTr("Letters")
                        font.pixelSize: 11 * App.fontScale
                        contentItem: Text { text: parent.text; color: ColorPalette.textPrimary; leftPadding: 20; font.pixelSize: 11 * App.fontScale; verticalAlignment: Text.AlignVCenter }
                        onCheckedChanged: root._refreshPreview()
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6
                    Label { text: qsTr("From:"); color: ColorPalette.textPrimary; font.pixelSize: 11 * App.fontScale }
                    TextField {
                        id: fromField
                        text: numBtn.checked ? "0" : "a"
                        implicitWidth: 72
                        implicitHeight: 28
                        background: FieldBg { focused: fromField.activeFocus }
                        color: ColorPalette.textPrimary
                        onTextChanged: root._refreshPreview()
                    }
                    Label { text: qsTr("To:"); color: ColorPalette.textPrimary; font.pixelSize: 11 * App.fontScale; Layout.leftMargin: 6 }
                    TextField {
                        id: toField
                        text: numBtn.checked ? "100" : "z"
                        implicitWidth: 72
                        implicitHeight: 28
                        background: FieldBg { focused: toField.activeFocus }
                        color: ColorPalette.textPrimary
                        onTextChanged: root._refreshPreview()
                    }
                    Label { text: qsTr("Wildcard size:"); color: ColorPalette.textPrimary; font.pixelSize: 11 * App.fontScale; visible: numBtn.checked; Layout.leftMargin: 6 }
                    TextField {
                        id: sizeField
                        text: "2"
                        implicitWidth: 56
                        implicitHeight: 28
                        visible: numBtn.checked
                        background: FieldBg { focused: sizeField.activeFocus }
                        color: ColorPalette.textPrimary
                        onTextChanged: root._refreshPreview()
                    }
                    Item { Layout.fillWidth: true }
                }
            }
        }

        // ── Preview card ───────────────────────────────────────────────────
        Rectangle {
            Layout.fillWidth: true
            color: ColorPalette.panelBg
            border.color: ColorPalette.border
            radius: 4
            implicitHeight: previewCol.implicitHeight + 20

            ColumnLayout {
                id: previewCol
                anchors { left: parent.left; right: parent.right; top: parent.top; leftMargin: 10; rightMargin: 10; topMargin: 10 }
                spacing: 4

                RowLayout {
                    Layout.fillWidth: true
                    Text { text: qsTr("Preview"); color: ColorPalette.textHeader; font.pixelSize: 12 * App.fontScale; font.bold: true }
                    Item { Layout.fillWidth: true }
                    Text {
                        text: root._totalCount > 0 ? qsTr("%n link(s)", "", root._totalCount) : ""
                        color: ColorPalette.textSecond
                        font.pixelSize: 10 * App.fontScale
                    }
                }

                component PreviewRow: RowLayout {
                    property string label: ""
                    property string value: ""
                    Layout.fillWidth: true
                    spacing: 8
                    Text { text: label; color: ColorPalette.textSecond; font.pixelSize: 10 * App.fontScale; Layout.preferredWidth: 56 }
                    Text { text: value; color: ColorPalette.textPrimary; font.pixelSize: 10 * App.fontScale; font.family: "Consolas, monospace"; elide: Text.ElideMiddle; Layout.fillWidth: true }
                }

                PreviewRow { label: qsTr("First:");  value: root._firstLink }
                PreviewRow { label: qsTr("Second:"); value: root._secondLink }
                PreviewRow { label: qsTr("Last:");   value: root._lastLink }
            }
        }

        // ── Footer ─────────────────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            Text {
                Layout.fillWidth: true
                text: qsTr("After OK you can review each link, then optionally group them into a queue before they start.")
                color: ColorPalette.textSecond
                font.pixelSize: 9 * App.fontScale
                wrapMode: Text.WordWrap
            }
            DlgButton {
                text: qsTr("Cancel")
                onClicked: root.close()
            }
            DlgButton {
                text: qsTr("OK")
                primary: true
                enabled: root._totalCount > 0
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
        root._totalCount = files.length
        root._firstLink = files.length > 0 ? files[0] : ""
        root._secondLink = files.length > 1 ? files[1] : ""
        root._lastLink = files.length > 0 ? files[files.length - 1] : ""
    }
}
