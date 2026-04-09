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
    width: 800
    height: 600
    minimumWidth: 600
    minimumHeight: 400
    color: "#1e1e1e"
    flags: Qt.Dialog | Qt.WindowTitleHint | Qt.WindowCloseButtonHint
    modality: Qt.ApplicationModal

    Material.theme: Material.Dark
    Material.background: "#1e1e1e"
    Material.accent: "#4488dd"

    property var files: []
    signal batchAccepted(var files)

    function _accept() {
        var filesToAdd = []
        for (var i = 0; i < fileModel.count; ++i) {
            var item = fileModel.get(i)
            if (item.selected && item.status === "Found") {
                filesToAdd.push(item.url)
            }
        }
        root.batchAccepted(filesToAdd)
        root.close()
    }

    onFilesChanged: {
        fileModel.clear()
        console.log("Files changed, total files: " + files.length)
        for (var i = 0; i < files.length; i++) {
            var f = files[i]
            console.log("Adding file to model: " + f.url)
            fileModel.append({ name: f.name, url: f.url, status: "Checking...", selected: true })
        }
        
        // Trigger checks separately to ensure UI is ready
        for (var j = 0; j < fileModel.count; ++j) {
            (function(idx) {
                var url = fileModel.get(idx).url
                App.checkUrl(url, function(ok) {
                    fileModel.setProperty(idx, "status", ok ? "Found" : "Not Found")
                    if (!ok) {
                        fileModel.setProperty(idx, "selected", false)
                    }
                })
            })(j)
        }
    }

    ListModel { id: fileModel }

    ColumnLayout {
        anchors { fill: parent; margins: 16 }
        spacing: 12

        Text {
            text: "Please check the links, which you want to add to the download list of IDM, and click OK button.\nYou may wait until IDM checks and fills all file types."
            color: "#c0c0c0"
            font.pixelSize: 12
        }

        // Table
        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            color: "#252525"
            border.color: "#3a3a3a"

            ListView {
                id: fileList
                anchors.fill: parent
                model: fileModel
                clip: true
                header: Rectangle {
                    width: fileList.width; height: 30; color: "#2d2d2d"
                    Row {
                        anchors.fill: parent; spacing: 4
                        Text { text: "File Name"; color: "#aaa"; width: 150; verticalAlignment: Text.AlignVCenter }
                        Text { text: "File Type"; color: "#aaa"; width: 80; verticalAlignment: Text.AlignVCenter }
                        Text { text: "Size"; color: "#aaa"; width: 60; verticalAlignment: Text.AlignVCenter }
                        Text { text: "Download from"; color: "#aaa"; width: 200; verticalAlignment: Text.AlignVCenter }
                        Text { text: "Save to"; color: "#aaa"; width: 200; verticalAlignment: Text.AlignVCenter }
                    }
                }
                delegate: Rectangle {
                    width: fileList.width; height: 26
                    color: index % 2 === 0 ? "#1c1c1c" : "#202020"
                    Row {
                        anchors.fill: parent; spacing: 4
                        CheckBox { 
                            checked: model.selected; 
                            onCheckedChanged: {
                                console.log("Checkbox changed for: " + name + " to: " + checked);
                                fileModel.setProperty(index, "selected", checked);
                            }
                        }
                        Text { text: name; color: "#d0d0d0"; width: 150; elide: Text.ElideRight; verticalAlignment: Text.AlignVCenter }
                        Text { text: status; color: status === "Not Found" ? "#cc6666" : (status === "Found" ? "#66bb88" : "#888"); width: 80; verticalAlignment: Text.AlignVCenter }
                        Text { text: ""; color: "#d0d0d0"; width: 60; verticalAlignment: Text.AlignVCenter }
                        Text { text: url; color: "#d0d0d0"; width: 200; elide: Text.ElideRight; verticalAlignment: Text.AlignVCenter }
                        Text { text: "Downloads/" + name; color: "#d0d0d0"; width: 200; elide: Text.ElideRight; verticalAlignment: Text.AlignVCenter }
                    }
                }
            }
        }

        // Bottom settings
        RowLayout {
            Layout.fillWidth: true
            
            GroupBox {
                Layout.fillWidth: true
                title: "Save to directory/category"
                ColumnLayout {
                    RadioButton { text: "Every file to the directory according to the category of the file"; checked: true; font.pixelSize: 12 }
                    RowLayout {
                        RadioButton { text: "All files to one category"; font.pixelSize: 12 }
                        ComboBox { model: ["General"]; Layout.preferredWidth: 150 }
                    }
                    RowLayout {
                        RadioButton { text: "All files to one directory"; font.pixelSize: 12 }
                        TextField { Layout.fillWidth: true; text: "C:\\Users\\User\\Downloads" }
                        Button { text: "Browse..." }
                    }
                }
            }
            
            ColumnLayout {
                Text { text: "Replace file names using asterisk wildcard for the file name pattern:"; color: "#c0c0c0"; font.pixelSize: 12 }
                TextField { Layout.fillWidth: true; text: "idman*build63.exe" }
                
                RowLayout {
                    Layout.topMargin: 20
                    Item { Layout.fillWidth: true }
                        Button { 
                        text: "OK"; 
                        onClicked: _accept()
                        implicitWidth: 80; implicitHeight: 30;
                        background: Rectangle { color: "#1e3a6e"; radius: 0; border.color: "#4488dd"; border.width: 1 } 
                        contentItem: Text { text: parent.text; color: "#ffffff"; font.pixelSize: 13; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                    }
                    Button { 
                        text: "Cancel"; 
                        onClicked: root.close();
                        implicitWidth: 80; implicitHeight: 30;
                        background: Rectangle { color: "#3a3a3a"; radius: 0; border.color: "#555555"; border.width: 1 } 
                        contentItem: Text { text: parent.text; color: "#d0d0d0"; font.pixelSize: 13; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                    }
                }
            }
        }
    }
}
