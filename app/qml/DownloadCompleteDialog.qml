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
import com.stellar.app

Window {
    id: root

    property var item: null

    FileDragDropHelper {
        id: dragDropHelper
        onDragCompleted: (success) => {
            if (success) {
                fileBoxMoved = true
            }
        }
    }

    property bool fileBoxMoved: false

    width: 480
    height: 280
    minimumWidth: 420
    minimumHeight: 280
    maximumWidth: 700
    maximumHeight: 400
    color: "#1e1e1e"
    title: "Download Complete"
    Material.theme: Material.Dark
    Material.background: "#1e1e1e"
    Material.accent: "#4488dd"

    function fmtBytes(b) {
        if (!b || b < 0) return "--"
        if (b < 1048576)    return (b / 1024).toFixed(1) + " KB"
        if (b < 1073741824) return (b / 1048576).toFixed(2) + " MB"
        return (b / 1073741824).toFixed(2) + " GB"
    }

    ColumnLayout {
        anchors { fill: parent; margins: 20 }
        spacing: 8

        // Icon + title row
        RowLayout {
            spacing: 10

            // Checkmark icon
            Image {
                width: 46
                height: 46
                source: "qrc:/qt/qml/com/stellar/app/app/qml/icons/checkmark_download_complete.ico"
                smooth: true
            }

            ColumnLayout {
                spacing: 0
                Text {
                    text: "Download Complete"
                    color: "#44bb44"
                    font.pixelSize: 14
                    font.bold: true
                }
                Text {
                    text: item ? item.filename : ""
                    color: "#d0d0d0"
                    font.pixelSize: 12
                    width: 300
                    elide: Text.ElideMiddle
                    Layout.maximumWidth: 300
                }
            }
        }

        // Draggable file preview box with drag-drop support
        Rectangle {
            id: fileBox
            Layout.fillWidth: true
            Layout.preferredHeight: 60
            color: fileBoxMoved ? "#1a1a1a" : "#252525"
            border.color: fileBoxMoved ? "#555555" : (fileDragArea.pressed ? "#88bbff" : fileDragArea.containsMouse ? "#4488dd" : "#3a3a3a")
            border.width: 2
            radius: 4
            opacity: fileBoxMoved ? 0.6 : 1.0

            ColumnLayout {
                anchors { fill: parent; margins: 8 }
                spacing: 4

                Row {
                    spacing: 8
                    Image {
                        id: fileIcon
                        width: 24; height: 24
                        source: !fileBoxMoved && item ? "image://fileicon/" + (item.savePath + "/" + item.filename).replace(/\\/g, "/") : ""
                        sourceSize: Qt.size(24, 24)
                        fillMode: Image.PreserveAspectFit
                        smooth: true
                        visible: !fileBoxMoved
                    }
                    Text {
                        text: "✓"
                        font.pixelSize: 24
                        color: "#88aa88"
                        visible: fileBoxMoved
                    }
                    ColumnLayout {
                        spacing: 0
                        Text {
                            text: fileBoxMoved ? "(File moved)" : ((item ? item.filename : "") + " (Drag to move)")
                            color: fileBoxMoved ? "#888888" : (fileDragArea.pressed ? "#88bbff" : fileDragArea.containsMouse ? "#88bbff" : "#d0d0d0")
                            font.pixelSize: 11
                            font.bold: true
                            elide: Text.ElideRight
                            Layout.maximumWidth: 350
                        }
                        Text {
                            text: fileBoxMoved ? "" : ("Size: " + root.fmtBytes(item ? item.totalBytes : 0) + " | Location: " + (item ? item.savePath : ""))
                            color: "#888"
                            font.pixelSize: 10
                            elide: Text.ElideRight
                            Layout.maximumWidth: 350
                            visible: !fileBoxMoved
                        }
                    }
                }
            }

            MouseArea {
                id: fileDragArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: fileBoxMoved ? Qt.ArrowCursor : Qt.OpenHandCursor
                enabled: !fileBoxMoved

                property bool dragStarted: false
                property real pressX: 0
                property real pressY: 0

                onPressed: {
                    if (item && !fileBoxMoved) {
                        dragProxy.visible = true
                        dragProxy.opacity = 0.9
                        dragStarted = false
                        pressX = mouseX
                        pressY = mouseY
                    }
                }

                onPositionChanged: {
                    if (item && pressed && !dragStarted && !fileBoxMoved && (Math.abs(mouseX - pressX) > 5 || Math.abs(mouseY - pressY) > 5)) {
                        // User has dragged far enough — initiate native drag
                        dragStarted = true
                        const filePath = item.savePath + "/" + item.filename
                        dragDropHelper.startDrag(filePath)
                        dragProxy.visible = false
                    }
                }

                onReleased: {
                    dragProxy.visible = false
                    dragStarted = false
                }
            }

            // Visual drag proxy
            Rectangle {
                id: dragProxy
                visible: false
                width: 220
                height: 40
                radius: 4
                color: "#4488dd"
                z: 1000

                Row {
                    anchors { fill: parent; margins: 8 }
                    spacing: 8
                    Text {
                        text: "📦"
                        font.pixelSize: 18
                    }
                    ColumnLayout {
                        spacing: 0
                        Text {
                            text: item ? item.filename : ""
                            color: "#ffffff"
                            font.pixelSize: 11
                            elide: Text.ElideRight
                            font.bold: true
                        }
                        Text {
                            text: "Release to copy"
                            color: "#ccddff"
                            font.pixelSize: 9
                        }
                    }
                }
            }
        }

        // Info grid
        GridLayout {
            columns: 2
            columnSpacing: 10
            rowSpacing: 2
            Layout.fillWidth: true
            Layout.topMargin: 0

            Text { text: "Completed:";  color: "#808080"; font.pixelSize: 11 }
            Text {
                text: Qt.formatDateTime(new Date(), "MM/dd/yyyy hh:mm:ss AP")
                color: "#c0c0c0"; font.pixelSize: 11
            }
        }

        // Buttons (no spacer - minimize dialog height)
        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            DlgButton {
                text: "Open File"
                primary: true
                onClicked: { if (item) App.openFile(item.id); root.close() }
            }

            DlgButton {
                text: "Show in Folder"
                implicitWidth: 130
                onClicked: { if (item) App.openFolderSelectFile(item.id); root.close() }
            }

            Item { Layout.fillWidth: true }

            DlgButton {
                text: "Close"
                onClicked: root.close()
            }
        }
    }
}
