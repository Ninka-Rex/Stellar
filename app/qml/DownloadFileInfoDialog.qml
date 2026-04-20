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
import QtQuick.Dialogs

Window {
    id: root

    property string pendingUrl:      ""
    property string pendingFilename: ""
    property string pendingSize:     ""
    property string pendingSavePath: ""
    property string filenameOverride: ""
    property string pendingDownloadId: ""
    property bool   isIntercepted:   false
    property bool   _accepted:       false

    width:  700
    height: 325
    minimumWidth: 460
    minimumHeight: 325
    title: "New Download"
    color: "#1a1a1a"
    modality: Qt.ApplicationModal
    flags: Qt.Dialog | Qt.WindowTitleHint | Qt.WindowCloseButtonHint

    Material.theme: Material.Dark
    Material.background: "#1a1a1a"
    Material.accent: "#4488dd"

    signal downloadNow(string downloadId, string url, string savePath, string category, string description)
    signal downloadLater(string downloadId, string url, string savePath, string category, string description)
    signal rejected(string downloadId, string url)

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
            raise()
            requestActivate()
        }
        if (!visible) {
            if (!_accepted && pendingDownloadId.length > 0)
                rejected(pendingDownloadId, pendingUrl)
            _accepted     = false
            isIntercepted = false
        }
    }

    // ── Category helpers ───────────────────────────────────────────────────────
    function _categoryIds() {
        var ids = []
        for (var i = 0; i < App.categoryModel.rowCount(); i++)
            ids.push(App.categoryModel.categoryData(i).id)
        return ids
    }
    function _categoryLabels() {
        var labels = []
        for (var i = 0; i < App.categoryModel.rowCount(); i++)
            labels.push(App.categoryModel.categoryData(i).label)
        return labels
    }
    property var categoryIds:    _categoryIds()
    property var categoryLabels: _categoryLabels()

    Connections {
        target: App.categoryModel
        function onCategoriesChanged() {
            categoryIds    = _categoryIds()
            categoryLabels = _categoryLabels()
        }
    }

    function categoryIndexForUrl(url, name) {
        var catId = App.categoryModel.categoryForUrl(url, name)
        for (var i = 0; i < categoryIds.length; i++)
            if (categoryIds[i] === catId) return i
        return 0
    }

    function savePathForIndex(idx) {
        return App.categoryModel.savePathForCategory(categoryIds[idx] || "all")
    }

    onPendingUrlChanged:      _reset()
    onPendingFilenameChanged: _reset()

    function _reset() {
        var idx = categoryIndexForUrl(pendingUrl, pendingFilename)
        catCombo.currentIndex = idx
        _updateSavePath(idx)
        descField.text = ""
    }

    function _updateSavePath(catIdx) {
        var dir = savePathForIndex(catIdx)
        if (!dir || dir.length === 0) dir = pendingSavePath
        // Normalise to forward slashes internally; Windows displays them fine
        // and on Linux backslashes are treated as literal filename characters.
        dir = dir.replace(/\\/g, "/")
        if (!dir.endsWith("/")) dir += "/"
        saveAsField.editText = dir + pendingFilename
    }

    function _iconColor() {
        var n = root.pendingFilename.toLowerCase()
        if (/\.(mp4|mkv|avi|mov|wmv|flv|webm|m4v|3gp|mpeg|mpg)$/.test(n)) return "#c04040"
        if (/\.(mp3|flac|wav|aac|ogg|m4a|wma)$/.test(n))                   return "#3a96b8"
        if (/\.(zip|rar|7z|tar|gz|bz2|xz)$/.test(n))                       return "#c09030"
        if (/\.(exe|msi|apk)$/.test(n))                                     return "#5858b8"
        if (/\.(pdf|doc|docx|epub)$/.test(n))                               return "#b85030"
        if (/\.(safetensors|gguf)$/.test(n))                                return "#7a38a0"
        if (/\.(iso|img|bin)$/.test(n))                                     return "#3a7a3a"
        return "#4a4a5a"
    }

    function _iconExt() {
        var ext = root.pendingFilename.split('.').pop().toUpperCase()
        return ext.length <= 4 ? ext : ext.substring(0, 4)
    }

    FileDialog {
        id: saveAsDlg
        fileMode: FileDialog.SaveFile
        // Ensure the OS dialog appends the original file extension when the user
        // doesn't type one — otherwise files are saved without an extension.
        defaultSuffix: {
            var parts = root.pendingFilename.split('.')
            return parts.length > 1 ? parts[parts.length - 1] : ""
        }
        onAccepted: {
            var path = selectedFile.toString()
                .replace(/^file:\/\/\//, "").replace(/^file:\/\//, "")
            if (path.length > 0) {
                saveAsField.editText = path
            }
        }
    }

    Popup {
        id: addCatPopup
        width: 240; height: 88
        modal: false
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        background: Rectangle { color: "#262626"; border.color: "#404040"; border.width: 1; radius: 4 }
        x: addCatBtn.mapToItem(root.contentItem, 0, 0).x
        y: addCatBtn.mapToItem(root.contentItem, 0, 0).y + addCatBtn.height + 4

        onOpened: { newCatField.text = ""; newCatField.forceActiveFocus() }

        ColumnLayout {
            anchors { fill: parent; margins: 10 }
            spacing: 8
            Text { text: "New category name:"; color: "#909090"; font.pixelSize: 11 }
            RowLayout {
                spacing: 6; Layout.fillWidth: true
                TextField {
                    id: newCatField
                    Layout.fillWidth: true; font.pixelSize: 11; color: "#d0d0d0"
                    background: Rectangle { color: "#1a1a1a"; border.color: "#404040"; radius: 3 }
                    leftPadding: 6
                    Keys.onReturnPressed: _addCategory()
                    Keys.onEnterPressed:  _addCategory()
                }
                Button {
                    text: "Add"; implicitWidth: 46; implicitHeight: 26; font.pixelSize: 11
                    background: Rectangle { color: "#1e3a6e"; border.color: "#4488dd"; border.width: 1; radius: 3 }
                    contentItem: Text { text: parent.text; color: "#fff"; font: parent.font; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                    onClicked: _addCategory()
                }
            }
        }
        function _addCategory() {
            var name = newCatField.text.trim()
            if (name.length === 0) return
            App.categoryModel.addCategory(name)
            Qt.callLater(function() {
                catCombo.currentIndex = root.categoryIds.length - 1
                root._updateSavePath(catCombo.currentIndex)
            })
            addCatPopup.close()
        }
    }

    // ── Root layout ────────────────────────────────────────────────────────────
    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // ── Header ─────────────────────────────────────────────────────────────
        Rectangle {
            Layout.fillWidth: true
            height: 72
            color: "#222228"

            RowLayout {
                anchors { fill: parent; leftMargin: 20; rightMargin: 20; topMargin: 12; bottomMargin: 12 }
                spacing: 16

                // File type icon (system icon)
                Image {
                    width: 48; height: 48
                    source: root.pendingFilename ? "image://fileicon/" + root.pendingFilename : ""
                    sourceSize: Qt.size(48, 48)
                    fillMode: Image.PreserveAspectFit
                    smooth: true
                }

                // Filename + URL
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 3

                    Text {
                        Layout.fillWidth: true
                        // Show the filename portion of the current save-as path so it
                        // updates live as the user edits the field — not just the original URL filename.
                        text: {
                            var p = saveAsField.editText
                            var sep = Math.max(p.lastIndexOf("/"), p.lastIndexOf("\\"))
                            return sep >= 0 ? p.substring(sep + 1) : (root.pendingFilename || "download")
                        }
                        color: "#e8e8e8"
                        font.pixelSize: 14
                        font.weight: Font.Medium
                        elide: Text.ElideMiddle
                    }

                    Text {
                        Layout.fillWidth: true
                        text: root.pendingUrl
                        color: "#5a7aaa"
                        font.pixelSize: 11
                        elide: Text.ElideMiddle
                    }
                }

                // File size
                Text {
                    text: root.pendingSize
                    color: "#707080"
                    font.pixelSize: 12
                    visible: root.pendingSize.length > 0
                    Layout.alignment: Qt.AlignVCenter
                }
            }
        }

        // Divider
        Rectangle { Layout.fillWidth: true; height: 1; color: "#2e2e38" }

        // ── Form body ──────────────────────────────────────────────────────────
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.margins: 20
            spacing: 12

            // Category
            RowLayout {
                spacing: 10
                Text {
                    text: "Category"
                    color: "#707070"; font.pixelSize: 12
                    Layout.preferredWidth: 72
                    horizontalAlignment: Text.AlignRight
                }
                ComboBox {
                    id: catCombo
                    model: root.categoryLabels
                    implicitWidth: 170; implicitHeight: 30
                    font.pixelSize: 12
                    background: Rectangle { color: "#252525"; border.color: "#3c3c3c"; radius: 4 }
                    contentItem: Text {
                        leftPadding: 10; text: catCombo.displayText
                        color: "#d0d0d0"; font: catCombo.font
                        verticalAlignment: Text.AlignVCenter
                    }
                    onCurrentIndexChanged: root._updateSavePath(currentIndex)
                }
                Button {
                    id: addCatBtn
                    text: "+"
                    implicitWidth: 30; implicitHeight: 30
                    font.pixelSize: 18
                    background: Rectangle {
                        color: addCatBtn.pressed ? "#383838" : (addCatBtn.hovered ? "#2e2e2e" : "#252525")
                        border.color: "#3c3c3c"; radius: 4
                    }
                    contentItem: Text {
                        text: parent.text; color: "#909090"; font: parent.font
                        horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                    }
                    ToolTip.visible: hovered; ToolTip.text: "Add new category"
                    onClicked: addCatPopup.open()
                }
                Item { Layout.fillWidth: true }
            }

            // Save As
            RowLayout {
                spacing: 10
                Text {
                    text: "Save As"
                    color: "#707070"; font.pixelSize: 12
                    Layout.preferredWidth: 72
                    horizontalAlignment: Text.AlignRight
                }
                ComboBox {
                    id: saveAsField
                    Layout.fillWidth: true
                    editable: true
                    model: [editText]
                    implicitHeight: 30
                    font.pixelSize: 11
                    background: Rectangle { color: "#252525"; border.color: "#3c3c3c"; radius: 4 }
                    contentItem: TextInput {
                        leftPadding: 10; text: saveAsField.editText; font: saveAsField.font
                        color: "#d0d0d0"; verticalAlignment: TextInput.AlignVCenter
                        selectByMouse: true; onTextEdited: saveAsField.editText = text
                        clip: true
                    }
                    property string text: editText
                }
                Button {
                    text: "…"
                    implicitWidth: 30; implicitHeight: 30
                    font.pixelSize: 13
                    background: Rectangle {
                        color: parent.pressed ? "#383838" : (parent.hovered ? "#2e2e2e" : "#252525")
                        border.color: "#3c3c3c"; radius: 4
                    }
                    contentItem: Text {
                        text: parent.text; color: "#909090"; font: parent.font
                        horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                    }
                    onClicked: {
                        var currentPath = saveAsField.editText || (savePathForIndex(catCombo.currentIndex) + pendingFilename)
                        saveAsDlg.currentFolder = "file:///" + currentPath.replace(/[\/\\][^\/\\]*$/, "").replace(/\\/g, "/")
                        saveAsDlg.selectedFile = "file:///" + currentPath.replace(/\\/g, "/")
                        saveAsDlg.open()
                    }
                }
            }

            // Remember path
            RowLayout {
                spacing: 10
                Item { Layout.preferredWidth: 72 }
                CheckBox {
                    id: rememberPathChk
                    font.pixelSize: 11
                    topPadding: 0
                    bottomPadding: 0
                    text: "Remember this path for \"" + (root.categoryLabels[catCombo.currentIndex] || "") + "\""
                    contentItem: Text {
                        text: rememberPathChk.text; color: "#707070"; font: rememberPathChk.font
                        leftPadding: rememberPathChk.indicator.width + 6
                        verticalAlignment: Text.AlignVCenter
                    }
                }
            }

            // Description
            RowLayout {
                spacing: 10
                Text {
                    text: "Comment"
                    color: "#707070"; font.pixelSize: 12
                    Layout.preferredWidth: 72
                    horizontalAlignment: Text.AlignRight
                }
                TextField {
                    id: descField
                    Layout.fillWidth: true; implicitHeight: 30
                    font.pixelSize: 11; color: "#d0d0d0"
                    placeholderText: "Optional"
                    background: Rectangle { color: "#252525"; border.color: "#3c3c3c"; radius: 4 }
                    leftPadding: 10
                }
            }

            Item { Layout.fillHeight: true }
        }

        // Divider
        Rectangle { Layout.fillWidth: true; height: 1; color: "#2a2a2a" }

        // ── Button row ─────────────────────────────────────────────────────────
        Rectangle {
            Layout.fillWidth: true
            height: 56
            color: "#1e1e1e"

            RowLayout {
                anchors { fill: parent; leftMargin: 20; rightMargin: 20 }
                spacing: 8

                // Cancel — far left, understated
                DlgButton {
                    text: "Cancel"
                    onClicked: root.close()
                }

                Item { Layout.fillWidth: true }

                // Download Later
                DlgButton {
                    text: "Download Later"
                    implicitWidth: 130
                    onClicked: {
                        root._accepted = true
                        root.downloadLater(root.pendingDownloadId, root.pendingUrl, saveAsField.editText, _catId(), descField.text)
                        root.close()
                    }
                }

                // Start Download — primary action
                DlgButton {
                    text: "Start Download"
                    primary: true
                    implicitWidth: 130
                    onClicked: {
                        root._accepted = true
                        root.downloadNow(root.pendingDownloadId, root.pendingUrl, saveAsField.editText, _catId(), descField.text)
                        root.close()
                    }
                }
            }
        }
    }

    function _savePath() {
        var full = saveAsField.editText
        var sep = full.lastIndexOf("\\")
        if (sep < 0) sep = full.lastIndexOf("/")
        return sep >= 0 ? full.substring(0, sep) : full
    }
    function _catId() { return root.categoryIds[catCombo.currentIndex] || "all" }
}
