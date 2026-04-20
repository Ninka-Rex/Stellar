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
    title: "Batch download review"
    width: 940
    height: 600
    minimumWidth: 780
    minimumHeight: 460
    color: "#232323"
    flags: Qt.Dialog | Qt.WindowTitleHint | Qt.WindowCloseButtonHint
    modality: Qt.ApplicationModal

    Material.theme: Material.Dark
    Material.background: "#232323"
    Material.accent: "#5a8ec8"

    property var files: []
    signal batchAccepted(var files)

    ListModel { id: fileModel }

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

    Component.onCompleted: _rebuild()
    onFilesChanged: _rebuild()

    function _baseName(url) {
        var tail = url.split("/").pop()
        return tail.split("?")[0]
    }

    function _patternHint() {
        if (files.length === 0)
            return "e.g. file*.zip"
        var first = files[0]
        var base = first && first.url ? _baseName(first.url) : (first && first.name ? first.name : "")
        if (base.length === 0)
            return "e.g. file*.zip"
        var dot = base.lastIndexOf(".")
        if (dot < 0)
            return "e.g. " + base
        return "e.g. " + base.substring(0, dot) + "*" + base.substring(dot)
    }

    function _applyPattern(baseName) {
        var pattern = batchPatternField.text.trim()
        if (pattern.length === 0)
            return baseName
        if (pattern.indexOf("*") < 0)
            return pattern
        return pattern.replace("*", baseName)
    }

    function _refreshNames() {
        var seen = {}
        for (var i = 0; i < fileModel.count; ++i) {
            var item = fileModel.get(i)
            var baseName = item.baseName || item.name
            var name = _applyPattern(baseName)
            if (name.length === 0)
                name = baseName
            var dot = name.lastIndexOf(".")
            var stem = dot >= 0 ? name.substring(0, dot) : name
            var ext = dot >= 0 ? name.substring(dot) : ""
            var finalName = name
            var n = 1
            while (seen[finalName.toLowerCase()]) {
                ++n
                finalName = stem + "_" + n + ext
            }
            seen[finalName.toLowerCase()] = true
            fileModel.setProperty(i, "name", finalName)
        }
    }

    function _rebuild() {
        fileModel.clear()
        for (var i = 0; i < files.length; ++i) {
            var f = files[i]
            fileModel.append({
                baseName: f.name || _baseName(f.url),
                name: f.filename && f.filename.length ? f.filename : (f.name || _baseName(f.url)),
                url: f.url,
                status: "Checking...",
                selected: true
            })
        }
        if (batchPatternField.text.length === 0)
            batchPatternField.placeholderText = _patternHint()
        _refreshNames()
        _recheck()
    }

    function _recheck() {
        for (var i = 0; i < fileModel.count; ++i) {
            (function(idx) {
                var url = fileModel.get(idx).url
                App.checkUrl(url, function(ok) {
                    fileModel.setProperty(idx, "status", ok ? "Found" : "Not Found")
                    if (!ok)
                        fileModel.setProperty(idx, "selected", false)
                })
            })(i)
        }
    }

    function _accept() {
        var filesToAdd = []
        for (var i = 0; i < fileModel.count; ++i) {
            var item = fileModel.get(i)
            if (item.selected && item.status === "Found")
                filesToAdd.push({ url: item.url, filename: item.name })
        }
        root.batchAccepted(filesToAdd)
        root.close()
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 14
        spacing: 10

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 3
            Text { text: "Batch download review"; color: "#ffffff"; font.pixelSize: 16; font.bold: true }
            Text { text: "Choose the files to add, and optionally replace the names with a wildcard pattern."; color: "#a9a9a9"; font.pixelSize: 10; wrapMode: Text.WordWrap; Layout.fillWidth: true }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4
            Text {
                text: "Replace file names using asterisk wildcard for the filename pattern"
                color: "#d0d0d0"
                font.pixelSize: 11
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
            }
            TextField {
                id: batchPatternField
                Layout.fillWidth: true
                placeholderText: _patternHint()
                color: "#e8edf5"
                background: Rectangle { color: "#232323"; border.color: "#4a4a4a"; radius: 0 }
                onTextChanged: _refreshNames()
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            Text { text: "Files"; color: "#d0d0d0"; font.pixelSize: 12 }
            Item { Layout.fillWidth: true }
            DlgButton {
                text: "Check all"
                onClicked: _setAllSelected(true)
            }
            DlgButton {
                text: "Uncheck all"
                onClicked: _setAllSelected(false)
            }
        }

        ListView {
            id: fileList
            Layout.fillWidth: true
            Layout.fillHeight: true
            model: fileModel
            clip: true
            spacing: 1
            delegate: Rectangle {
                width: fileList.width
                height: 30
                color: index % 2 === 0 ? "#303030" : "#2d2d2d"
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 8
                    anchors.rightMargin: 8
                    spacing: 10
                    Item {
                        Layout.preferredWidth: 28
                        Layout.fillHeight: true
                        CheckBox {
                            anchors.centerIn: parent
                            checked: model.selected
                            onCheckedChanged: fileModel.setProperty(index, "selected", checked)
                        }
                    }
                    Text {
                        text: name
                        color: "#e0e0e0"
                        font.pixelSize: 10
                        Layout.preferredWidth: 260
                        elide: Text.ElideRight
                        verticalAlignment: Text.AlignVCenter
                    }
                    Text {
                        text: status
                        color: "#c0c0c0"
                        font.pixelSize: 10
                        Layout.preferredWidth: 90
                        verticalAlignment: Text.AlignVCenter
                    }
                    Text {
                        text: url
                        color: "#c8c8c8"
                        font.pixelSize: 10
                        elide: Text.ElideMiddle
                        Layout.fillWidth: true
                        verticalAlignment: Text.AlignVCenter
                    }
                }
            }
            ScrollBar.vertical: ScrollBar {}
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            Text {
                Layout.fillWidth: true
                text: "The queue step comes after OK if you want these grouped before they start."
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
                onClicked: _accept()
            }
        }
    }

    function _setAllSelected(selected) {
        for (var i = 0; i < fileModel.count; ++i) {
            fileModel.setProperty(i, "selected", selected)
        }
    }
}
