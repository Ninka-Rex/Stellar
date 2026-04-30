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
    property bool fileMoved: false

    FileDragDropHelper {
        id: dragDropHelper
        onMoveCompleted: (success) => {
            // Trust the C++ side: it emits true whenever a drop target accepted
            // the drag (either Qt returned a non-Ignore action, or drag->target()
            // is non-null which catches Windows Explorer's OLE drop handler).
            root.fileMoved = success
        }
    }

    onItemChanged: fileMoved = false

    width: 460
    height: mainCol.implicitHeight + 24
    color: "#1e1e1e"
    title: "Download complete"
    flags: Qt.Window | Qt.WindowCloseButtonHint | Qt.WindowTitleHint | Qt.MSWindowsFixedSizeDialogHint | Qt.WindowStaysOnTopHint
    Material.theme: Material.Dark
    Material.background: "#1e1e1e"
    Material.accent: "#4488dd"

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
    }

    function fmtBytes(b) {
        if (!b || b < 0) return "--"
        if (b < 1048576)    return (b / 1024).toFixed(2) + " KB"
        if (b < 1073741824) return (b / 1048576).toFixed(2) + " MB"
        return (b / 1073741824).toFixed(2) + " GB"
    }

    ColumnLayout {
        id: mainCol
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
        spacing: 8

        // Header: icon + "Download complete" + size summary
        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            Image {
                Layout.preferredWidth: 28
                Layout.preferredHeight: 28
                sourceSize.width: 28
                sourceSize.height: 28
                source: "qrc:/qt/qml/com/stellar/app/app/qml/icons/checkmark.png"
                fillMode: Image.PreserveAspectFit
                smooth: true
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1
                Text {
                    text: "Download complete"
                    color: "#e0e0e0"
                    font.pixelSize: 13
                    font.bold: true
                }
                Text {
                    text: item ? ("Downloaded " + root.fmtBytes(item.totalBytes) +
                                  " (" + (item.totalBytes || 0) + " Bytes)") : ""
                    color: "#aaaaaa"
                    font.pixelSize: 11
                }
            }
        }

        // Address (URL) field
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 2
            Text { text: "Address"; color: "#aaaaaa"; font.pixelSize: 11 }
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 22
                color: "#1b1b1b"
                border.color: addressField.activeFocus ? "#4488dd" : "#3a3a3a"
                border.width: 1
                radius: 2
                TextInput {
                    id: addressField
                    anchors.fill: parent
                    anchors.leftMargin: 5
                    anchors.rightMargin: 5
                    verticalAlignment: TextInput.AlignVCenter
                    color: "#d0d0d0"
                    font.pixelSize: 11
                    readOnly: true
                    selectByMouse: true
                    clip: true
                    text: item ? item.url.toString() : ""
                }
            }
        }

        // The file saved as field (or "moved" message)
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 2
            Text { text: "The file saved as"; color: "#aaaaaa"; font.pixelSize: 11 }
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 22
                color: "#1b1b1b"
                border.color: pathField.activeFocus ? "#4488dd" : "#3a3a3a"
                border.width: 1
                radius: 2
                TextInput {
                    id: pathField
                    anchors.fill: parent
                    anchors.leftMargin: 5
                    anchors.rightMargin: 5
                    verticalAlignment: TextInput.AlignVCenter
                    color: root.fileMoved ? "#888888" : "#d0d0d0"
                    font.pixelSize: 11
                    font.italic: root.fileMoved
                    readOnly: true
                    selectByMouse: !root.fileMoved
                    clip: true
                    text: root.fileMoved
                          ? "The file has been moved."
                          : (item ? (item.savePath + "/" + item.filename).replace(/\//g, "\\") : "")
                }
            }
        }

        // Buttons row
        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: 2
            spacing: 6

            DlgButton {
                text: "Open"
                primary: true
                implicitWidth: 80
                enabled: !root.fileMoved
                onClicked: { if (item) App.openFile(item.id); root.close() }
            }
            DlgButton {
                text: "Open with..."
                implicitWidth: 92
                visible: Qt.platform.os === "windows"
                enabled: !root.fileMoved
                onClicked: { if (item) App.openFileWith(item.id); root.close() }
            }
            DlgButton {
                text: "Open folder"
                implicitWidth: 92
                onClicked: { if (item) App.openFolderSelectFile(item.id); root.close() }
            }

            Item { Layout.fillWidth: true }

            DlgButton {
                text: "Close"
                implicitWidth: 80
                onClicked: root.close()
            }
        }

        // Footer: "Don't show again" left, drag-out icon right
        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: 2
            spacing: 6

            CheckBox {
                id: dontShowAgain
                text: "Don't show this dialog again"
                topPadding: 0; bottomPadding: 0
                contentItem: Text {
                    text: parent.text
                    color: "#c0c0c0"
                    font.pixelSize: 11
                    leftPadding: parent.indicator.width + 4
                    verticalAlignment: Text.AlignVCenter
                }
                ToolTip.visible: hovered
                ToolTip.delay: 600
                ToolTip.text: "You can re-enable this in Settings → General → Show download complete dialog"
            }

            Item { Layout.fillWidth: true }

            // Drag-to-move icon (IDM-style)
            Rectangle {
                id: dragHandle
                Layout.preferredWidth: 28
                Layout.preferredHeight: 24
                radius: 3
                color: !dragArea.enabled ? "#1a1a1a"
                       : dragArea.containsMouse ? "#2d3a4a" : "#252525"
                border.color: !dragArea.enabled ? "#2a2a2a"
                            : dragArea.pressed ? "#88bbff"
                            : dragArea.containsMouse ? "#4488dd" : "#3a3a3a"
                border.width: 1
                opacity: dragArea.enabled ? 1.0 : 0.4

                Image {
                    anchors.centerIn: parent
                    width: 16; height: 16
                    sourceSize.width: 16; sourceSize.height: 16
                    source: item ? "image://fileicon/" + (item.savePath + "/" + item.filename).replace(/\\/g, "/") : ""
                    fillMode: Image.PreserveAspectFit
                    smooth: true
                }

                MouseArea {
                    id: dragArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: enabled ? Qt.OpenHandCursor : Qt.ArrowCursor
                    enabled: item !== null && !root.fileMoved

                    property bool dragStarted: false
                    property real pressX: 0
                    property real pressY: 0

                    onPressed: { dragStarted = false; pressX = mouseX; pressY = mouseY }
                    onPositionChanged: {
                        if (item && pressed && !dragStarted &&
                            (Math.abs(mouseX - pressX) > 4 || Math.abs(mouseY - pressY) > 4)) {
                            dragStarted = true
                            const filePath = item.savePath + "/" + item.filename
                            dragDropHelper.startMove(filePath)
                        }
                    }
                    onReleased: dragStarted = false

                    ToolTip.visible: containsMouse && !pressed && enabled
                    ToolTip.delay: 600
                    ToolTip.text: "Drag the file to move it elsewhere"
                }
            }
        }
    }

    onClosing: {
        if (dontShowAgain.checked) {
            App.settings.showDownloadComplete = false
        }
    }
}
