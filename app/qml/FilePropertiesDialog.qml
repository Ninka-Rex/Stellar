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
    title: "File Properties"
    width: 500
    height: 530
    minimumWidth: 500
    maximumWidth: 500
    minimumHeight: 530
    maximumHeight: 530
    color: "#1e1e1e"
    flags: Qt.Dialog | Qt.WindowTitleHint | Qt.WindowCloseButtonHint | Qt.MSWindowsFixedSizeDialogHint

    Material.theme: Material.Dark
    Material.background: "#1e1e1e"
    Material.accent: "#4488dd"

    property var item: null

    // File type detection helpers
    function fileType(name) {
        if (!name) return "Unknown"
        const n = name.toLowerCase()
        if (/\.(mp4|mkv|avi|mov|wmv|flv|webm|m4v|3gp|mpeg|mpg|ogv|rmvb|rm)$/.test(n)) return "Video File"
        if (/\.(mp3|flac|wav|aac|ogg|m4a|wma|aif|ra|opus)$/.test(n))                   return "Audio File"
        if (/\.(zip)$/.test(n))         return "WinZip Archive"
        if (/\.(rar|r\d+)$/.test(n))    return "WinRAR Archive"
        if (/\.(7z)$/.test(n))          return "7-Zip Archive"
        if (/\.(tar)$/.test(n))         return "TAR Archive"
        if (/\.(gz|bz2|xz|zst)$/.test(n)) return "Compressed Archive"
        if (/\.(exe)$/.test(n))         return "Windows Executable"
        if (/\.(msi|msu)$/.test(n))     return "Windows Installer"
        if (/\.(deb)$/.test(n))         return "Debian Package"
        if (/\.(rpm)$/.test(n))         return "RPM Package"
        if (/\.(apk)$/.test(n))         return "Android Package"
        if (/\.(pdf)$/.test(n))         return "PDF Document"
        if (/\.(doc|docx)$/.test(n))    return "Word Document"
        if (/\.(xls|xlsx)$/.test(n))    return "Excel Spreadsheet"
        if (/\.(ppt|pptx)$/.test(n))    return "PowerPoint Presentation"
        if (/\.(epub|azw3)$/.test(n))   return "eBook"
        if (/\.(iso|img|bin)$/.test(n)) return "Disk Image"
        if (/\.(safetensors|gguf)$/.test(n)) return "AI Model"
        return "File"
    }

    function fileColor(name) {
        if (!name) return "#606060"
        const n = name.toLowerCase()
        if (/\.(mp4|mkv|avi|mov|wmv|flv|webm|m4v|3gp|mpeg|mpg|ogv|rmvb|rm)$/.test(n)) return "#c04040"
        if (/\.(mp3|flac|wav|aac|ogg|m4a|wma|aif|ra|opus)$/.test(n))                   return "#40a0c0"
        if (/\.(zip|rar|7z|tar|gz|bz2|xz|zst|r\d+)$/.test(n))                          return "#c09030"
        if (/\.(exe|msi|msu|deb|rpm|pkg|apk)$/.test(n))                                 return "#6060c0"
        if (/\.(pdf|doc|docx|ppt|pptx|xls|xlsx|epub|azw3)$/.test(n))                   return "#c06040"
        if (/\.(safetensors|gguf)$/.test(n))                                             return "#8040a0"
        if (/\.(iso|img|bin)$/.test(n))                                                  return "#408040"
        return "#606060"
    }

    function fileIcon(name) {
        if (!name) return "•"
        const n = name.toLowerCase()
        if (/\.(mp4|mkv|avi|mov|wmv|flv|webm|m4v|3gp|mpeg|mpg|ogv|rmvb|rm)$/.test(n)) return "▶"
        if (/\.(mp3|flac|wav|aac|ogg|m4a|wma|aif|ra|opus)$/.test(n))                   return "♪"
        if (/\.(zip|rar|7z|tar|gz|bz2|xz|zst|r\d+)$/.test(n))                          return "Z"
        if (/\.(exe|msi|msu|deb|rpm|pkg|apk)$/.test(n))                                 return "⚙"
        if (/\.(pdf|doc|docx|ppt|pptx)$/.test(n))                                       return "D"
        if (/\.(safetensors|gguf)$/.test(n))                                             return "AI"
        return "•"
    }

    function formatBytes(b) {
        if (b <= 0) return "--"
        const kb = (b / 1024).toFixed(2)
        if (b < 1048576)    return (b / 1024).toFixed(2) + " KB (" + b + " Bytes)"
        if (b < 1073741824) return (b / 1048576).toFixed(2) + " MB (" + b + " Bytes)"
        return (b / 1073741824).toFixed(2) + " GB (" + b + " Bytes)"
    }

    FileDialog {
        id: moveFileDialog
        title: "Move File To…"
        fileMode: FileDialog.SaveFile
        currentFolder: root.item ? ("file:///" + root.item.savePath.replace(/\\/g, "/")) : ""
        currentFile: root.item ? ("file:///" + root.item.savePath.replace(/\\/g, "/") + "/" + root.item.filename) : ""
        onAccepted: {
            if (root.item) {
                const newPath = selectedFile.toString()
                    .replace(/^file:\/\/\//, "")
                    .replace(/^file:\/\//, "")
                App.moveDownloadFile(root.item.id, newPath)
            }
        }
    }

    ColumnLayout {
        anchors { fill: parent; margins: 16 }
        spacing: 10

        // Header: file icon + name
        RowLayout {
            spacing: 12
            Image {
                width: 48; height: 48
                source: root.item ? "image://fileicon/" + (root.item.savePath + "/" + root.item.filename).replace(/\\/g, "/") : ""
                sourceSize: Qt.size(48, 48)
                fillMode: Image.PreserveAspectFit
                smooth: true
            }
            Text {
                text: root.item ? root.item.filename : ""
                color: "#ffffff"
                font.pixelSize: 14
                font.bold: true
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
            }
        }

        Rectangle { Layout.fillWidth: true; height: 1; color: "#3a3a3a" }

        // Properties grid
        GridLayout {
            Layout.fillWidth: true
            columns: 2
            columnSpacing: 12
            rowSpacing: 6

            Text { text: "Type:";   color: "#909090"; font.pixelSize: 12 }
            Text { text: root.item ? root.fileType(root.item.filename) : "--"; color: "#d0d0d0"; font.pixelSize: 12 }

            Text { text: "Status:"; color: "#909090"; font.pixelSize: 12 }
            Text {
                text: root.item ? root.item.status : "--"
                color: {
                    if (!root.item) return "#d0d0d0"
                    const s = root.item.status
                    if (s === "Completed")   return "#60c0e0"
                    if (s === "Downloading") return "#66cc66"
                    if (s === "Error")       return "#e06060"
                    return "#d0d0d0"
                }
                font.pixelSize: 12
            }

            Text { text: "Size:";   color: "#909090"; font.pixelSize: 12 }
            Text { text: root.item ? root.formatBytes(root.item.totalBytes) : "--"; color: "#d0d0d0"; font.pixelSize: 12 }

            Text { text: "Save to:"; color: "#909090"; font.pixelSize: 12 }
            RowLayout {
                spacing: 6
                // Scrollable single-line path — parent clips, TextInput scrolls horizontally.
                Rectangle {
                    Layout.fillWidth: true
                    height: 24
                    color: "#1a1a1a"
                    border.color: "#3c3c3c"
                    radius: 3
                    clip: true

                    TextInput {
                        id: pathInput
                        anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; leftMargin: 6; rightMargin: 6 }
                        text: root.item ? (root.item.savePath.replace(/\//g, "\\") + "\\" + root.item.filename) : "--"
                        color: "#d0d0d0"; font.pixelSize: 12
                        readOnly: true
                        selectByMouse: true
                        clip: false
                    }
                }
                Rectangle {
                    width: 50; height: 22; radius: 3
                    color: moveMa.containsMouse ? "#4a4a4a" : "#3a3a3a"
                    border.color: "#555"; border.width: 1
                    Behavior on color { ColorAnimation { duration: 80 } }
                    Text { anchors.centerIn: parent; text: "Move"; color: "#d0d0d0"; font.pixelSize: 11 }
                    MouseArea {
                        id: moveMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: moveFileDialog.open()
                    }
                }
            }
        }

        Rectangle { Layout.fillWidth: true; height: 1; color: "#3a3a3a" }

        // Address — read-only, horizontally scrollable, link-colored
        ColumnLayout { spacing: 3; Layout.fillWidth: true
            Text { text: "Address:"; color: "#909090"; font.pixelSize: 12 }
            Rectangle {
                Layout.fillWidth: true; height: 24
                color: "#1a1a1a"; border.color: "#3c3c3c"; radius: 3; clip: true
                TextInput {
                    anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; leftMargin: 6; rightMargin: 6 }
                    text: root.item ? root.item.url.toString() : "--"
                    color: "#4488dd"; font.pixelSize: 12; font.underline: true
                    readOnly: true; selectByMouse: true; clip: false
                    selectionColor: "#4488dd"; selectedTextColor: "#ffffff"
                }
            }
        }

        // Description — editable; changes are saved immediately via App.setDownloadDescription
        ColumnLayout { spacing: 3; Layout.fillWidth: true
            Text { text: "Description:"; color: "#909090"; font.pixelSize: 12 }
            Rectangle {
                Layout.fillWidth: true; height: 24
                color: "#1a1a1a"; border.color: "#3c3c3c"; radius: 3; clip: true
                TextInput {
                    id: descInput
                    anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; leftMargin: 6; rightMargin: 6 }
                    text: root.item ? root.item.description : ""
                    color: "#d0d0d0"; font.pixelSize: 12; clip: false
                    selectByMouse: true
                    selectionColor: "#4488dd"; selectedTextColor: "#ffffff"
                    onTextChanged: {
                        if (root.item && text !== root.item.description)
                            App.setDownloadDescription(root.item.id, text)
                    }
                }
            }
        }

        Rectangle { Layout.fillWidth: true; height: 1; color: "#3a3a3a" }

        // Parent web page — read-only, horizontally scrollable, link-colored
        ColumnLayout { spacing: 3; Layout.fillWidth: true
            Text { text: "Web page this file was obtained from:"; color: "#909090"; font.pixelSize: 12 }
            Rectangle {
                Layout.fillWidth: true; height: 24
                color: "#1a1a1a"; border.color: "#3c3c3c"; radius: 3; clip: true
                TextInput {
                    anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; leftMargin: 6; rightMargin: 6 }
                    text: root.item && root.item.parentUrl.length > 0 ? root.item.parentUrl : "(unknown)"
                    color: root.item && root.item.parentUrl.length > 0 ? "#4488dd" : "#555555"
                    font.pixelSize: 12
                    font.underline: root.item && root.item.parentUrl.length > 0
                    readOnly: true; selectByMouse: true; clip: false
                    selectionColor: "#4488dd"; selectedTextColor: "#ffffff"
                }
            }
        }

        Rectangle { Layout.fillWidth: true; height: 1; color: "#3a3a3a" }

        // Referrer, Login, Password
        GridLayout {
            Layout.fillWidth: true
            columns: 2
            columnSpacing: 12
            rowSpacing: 6

            Text { text: "Referer:"; color: "#909090"; font.pixelSize: 12 }
            Rectangle {
                Layout.fillWidth: true; height: 24
                color: "#1a1a1a"; border.color: "#3c3c3c"; radius: 3; clip: true
                TextInput {
                    anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; leftMargin: 6; rightMargin: 6 }
                    text: root.item && root.item.referrer.length > 0 ? root.item.referrer : "(none)"
                    color: root.item && root.item.referrer.length > 0 ? "#d0d0d0" : "#555555"
                    font.pixelSize: 12; readOnly: true; selectByMouse: true; clip: false
                    selectionColor: "#4488dd"; selectedTextColor: "#ffffff"
                }
            }

            Text { text: "Login:"; color: "#909090"; font.pixelSize: 12 }
            TextField {
                Layout.fillWidth: true
                implicitHeight: 26
                text: root.item ? root.item.username : ""
                color: "#d0d0d0"; font.pixelSize: 12
                background: Rectangle { color: "#2d2d2d"; border.color: "#4a4a4a"; radius: 3 }
                leftPadding: 6
                onTextChanged: if (root.item) root.item.username !== text && App.setDownloadUsername(root.item.id, text)
            }

            Text { text: "Password:"; color: "#909090"; font.pixelSize: 12 }
            TextField {
                Layout.fillWidth: true
                implicitHeight: 26
                text: root.item ? root.item.password : ""
                echoMode: TextInput.Password
                color: "#d0d0d0"; font.pixelSize: 12
                background: Rectangle { color: "#2d2d2d"; border.color: "#4a4a4a"; radius: 3 }
                leftPadding: 6
                onTextChanged: if (root.item) root.item.password !== text && App.setDownloadPassword(root.item.id, text)
            }
        }

        Item { Layout.fillHeight: true }

        // Button row: spacer pushes both buttons to the right, Open sits left of Close.
        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Item { Layout.fillWidth: true }

            // Plain Rectangle avoids Material Button's implicit insets that would
            // make it render taller than its stated implicitHeight.
            Rectangle {
                width: 80; height: 32; radius: 3
                color: openMa.containsMouse ? "#4a4a4a" : "#3a3a3a"
                border.color: "#555"; border.width: 1
                Behavior on color { ColorAnimation { duration: 80 } }
                Text { anchors.centerIn: parent; text: "Open"; color: "#d0d0d0"; font.pixelSize: 13 }
                MouseArea {
                    id: openMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: if (root.item) Qt.openUrlExternally("file:///" + (root.item.savePath + "/" + root.item.filename).replace(/\\/g, "/"))
                }
            }

            Rectangle {
                width: 80; height: 32; radius: 3
                color: closeMa.containsMouse ? "#4a4a4a" : "#3a3a3a"
                border.color: "#555"; border.width: 1
                Behavior on color { ColorAnimation { duration: 80 } }
                Text { anchors.centerIn: parent; text: "Close"; color: "#d0d0d0"; font.pixelSize: 13 }
                MouseArea {
                    id: closeMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.close()
                }
            }
        }
    }
}
