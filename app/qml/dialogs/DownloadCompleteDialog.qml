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

    // Snapshot of the item's display data, captured in onItemChanged while the
    // DownloadItem is still alive. The dialog binds to these — NOT to item.* —
    // so a re-download (which deletes the old DownloadItem and creates a new one,
    // see AppController::redownload) can't blank out the already-shown fields.
    property string itemId: ""
    property string addressText: ""
    property string savedAsPath: ""
    property string displayName: ""
    property real   totalBytesSnap: 0
    property string iconSource: ""

    FileDragDropHelper {
        id: dragDropHelper
        onMoveCompleted: (success) => {
            // Trust the C++ side: it emits true whenever a drop target accepted
            // the drag (either Qt returned a non-Ignore action, or drag->target()
            // is non-null which catches Windows Explorer's OLE drop handler).
            root.fileMoved = success
        }
    }

    onItemChanged: {
        fileMoved = false
        itemId         = item ? (item.id || "") : ""
        addressText    = item ? item.url.toString() : ""
        savedAsPath    = item ? (item.savePath + "/" + item.filename).replace(/\//g, "\\") : ""
        displayName    = item ? String(item.filename || "") : ""
        totalBytesSnap = item ? (item.totalBytes || 0) : 0
        iconSource     = item ? ("image://fileicon/" + (item.savePath + "/" + item.filename).replace(/\\/g, "/")) : ""
    }

    width: 460
    height: rootCol.implicitHeight + 12
    color: ColorPalette.cardBg
    title: qsTr("Download complete")

    // Detach from the main window so each complete dialog gets its own taskbar
    // button (IDM-style). Owner set to null at the instantiation site in Main.qml.
    transientParent: null
    flags: Qt.Window | Qt.WindowCloseButtonHint | Qt.WindowTitleHint
           | Qt.WindowMinimizeButtonHint | Qt.MSWindowsFixedSizeDialogHint
    Material.theme: ColorPalette.materialTheme
    Material.foreground: ColorPalette.textPrimary
    Material.background: ColorPalette.materialBg
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
        id: rootCol
        anchors { left: parent.left; right: parent.right; top: parent.top }
        spacing: 0

        // ── Header strip (theme-aware, matches DownloadProgressDialog) ────────
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: hdrRow.implicitHeight + 16
            color: ColorPalette.headerStripBg
            radius: 0

            RowLayout {
                id: hdrRow
                anchors { fill: parent; leftMargin: 14; rightMargin: 14; topMargin: 8; bottomMargin: 8 }
                spacing: 10

                Image {
                    Layout.preferredWidth: 28
                    Layout.preferredHeight: 28
                    sourceSize: Qt.size(28, 28)
                    source: root.iconSource
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                    smooth: true
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 1
                    Text {
                        text: root.displayName.length > 0 ? root.displayName : qsTr("Download complete")
                        color: ColorPalette.textHeader
                        font.pixelSize: 13 * App.fontScale
                        font.bold: true
                        elide: Text.ElideMiddle
                        Layout.fillWidth: true
                    }
                    Text {
                        text: qsTr("Download complete — %1 (%2 Bytes)")
                              .arg(root.fmtBytes(root.totalBytesSnap))
                              .arg((root.totalBytesSnap || 0).toLocaleString(Qt.locale("en_US"), "f", 0))
                        color: ColorPalette.textSecond
                        font.pixelSize: 11 * App.fontScale
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }
                }
            }
        }

        // ── Body (margined) ──────────────────────────────────────────────────
        ColumnLayout {
            id: mainCol
            Layout.fillWidth: true
            Layout.leftMargin: 12
            Layout.rightMargin: 12
            Layout.topMargin: 8
            Layout.bottomMargin: 0
            spacing: 8

            // Address (URL) field
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2
                Text { text: qsTr("Address"); color: ColorPalette.textSecond; font.pixelSize: 11 * App.fontScale }
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 22
                    color: ColorPalette.inputBg
                    border.color: addressField.activeFocus ? "#4488dd" : ColorPalette.border
                    border.width: 1
                    radius: 2
                    TextInput {
                        id: addressField
                        anchors.fill: parent
                        anchors.leftMargin: 5
                        anchors.rightMargin: 5
                        verticalAlignment: TextInput.AlignVCenter
                        color: ColorPalette.textPrimary
                        font.pixelSize: 11 * App.fontScale
                        readOnly: true
                        selectByMouse: true
                        clip: true
                        text: root.addressText
                    }
                }
            }

            // The file saved as field (or "moved" message)
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2
                Text { text: qsTr("The file saved as"); color: ColorPalette.textSecond; font.pixelSize: 11 * App.fontScale }
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 22
                    color: ColorPalette.inputBg
                    border.color: pathField.activeFocus ? "#4488dd" : ColorPalette.border
                    border.width: 1
                    radius: 2
                    TextInput {
                        id: pathField
                        anchors.fill: parent
                        anchors.leftMargin: 5
                        anchors.rightMargin: 5
                        verticalAlignment: TextInput.AlignVCenter
                        color: root.fileMoved ? ColorPalette.textMuted : ColorPalette.textPrimary
                        font.pixelSize: 11 * App.fontScale
                        font.italic: root.fileMoved
                        readOnly: true
                        selectByMouse: !root.fileMoved
                        clip: true
                        text: root.fileMoved
                              ? qsTr("The file has been moved.")
                              : root.savedAsPath
                    }
                }
            }

            // Buttons row
            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: 2
                spacing: 6

                DlgButton {
                    text: qsTr("Open")
                    primary: true
                    implicitWidth: 80
                    enabled: !root.fileMoved && root.itemId.length > 0
                    onClicked: { if (root.itemId.length > 0) App.openFile(root.itemId); root.close() }
                }
                DlgButton {
                    text: qsTr("Open with...")
                    implicitWidth: 92
                    visible: Qt.platform.os === "windows"
                    enabled: !root.fileMoved && root.itemId.length > 0
                    onClicked: { if (root.itemId.length > 0) App.openFileWith(root.itemId); root.close() }
                }
                DlgButton {
                    text: qsTr("Open folder")
                    implicitWidth: 92
                    enabled: root.itemId.length > 0
                    onClicked: { if (root.itemId.length > 0) App.openFolderSelectFile(root.itemId); root.close() }
                }

                Item { Layout.fillWidth: true }

                DlgButton {
                    text: qsTr("Close")
                    implicitWidth: 80
                    onClicked: root.close()
                }
            }

            // Footer: "Don't show again" left, drag-out icon right
            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: 2
                Layout.bottomMargin: 4
                spacing: 6

                StyledCheckBox {
                    id: dontShowAgain
                    text: qsTr("Don't show this dialog again")
                    topPadding: 0; bottomPadding: 0
                    contentItem: Text {
                        text: parent.text
                        color: ColorPalette.textPrimary
                        font.pixelSize: 11 * App.fontScale
                        leftPadding: parent.indicator.width + 4
                        verticalAlignment: Text.AlignVCenter
                    }
                    ThemedToolTip {
                        visible: dontShowAgain.hovered
                        delay: 600
                        text: qsTr("You can re-enable this in Settings → General → Show download complete dialog")
                    }
                }

                Item { Layout.fillWidth: true }

                // Drag-to-move icon (IDM-style)
                Rectangle {
                    id: dragHandle
                    Layout.preferredWidth: 28
                    Layout.preferredHeight: 24
                    radius: 3
                    color: !dragArea.enabled ? ColorPalette.cardBg
                           : dragArea.containsMouse ? "#2d3a4a" : ColorPalette.panelBg
                    border.color: !dragArea.enabled ? "#2a2a2a"
                                : dragArea.pressed ? "#88bbff"
                                : dragArea.containsMouse ? "#4488dd" : ColorPalette.border
                    border.width: 1
                    opacity: dragArea.enabled ? 1.0 : 0.4

                    Image {
                        anchors.centerIn: parent
                        width: 16; height: 16
                        sourceSize.width: 16; sourceSize.height: 16
                        source: root.iconSource
                        fillMode: Image.PreserveAspectFit
                        smooth: true
                    }

                    MouseArea {
                        id: dragArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: enabled ? Qt.OpenHandCursor : Qt.ArrowCursor
                        enabled: root.savedAsPath.length > 0 && !root.fileMoved

                        property bool dragStarted: false
                        property real pressX: 0
                        property real pressY: 0

                        onPressed: { dragStarted = false; pressX = mouseX; pressY = mouseY }
                        onPositionChanged: {
                            if (root.savedAsPath.length > 0 && pressed && !dragStarted &&
                                (Math.abs(mouseX - pressX) > 4 || Math.abs(mouseY - pressY) > 4)) {
                                dragStarted = true
                                dragDropHelper.startMove(root.savedAsPath.replace(/\\/g, "/"))
                            }
                        }
                        onReleased: dragStarted = false

                        ThemedToolTip {
                            visible: dragArea.containsMouse && !dragArea.pressed && dragArea.enabled
                            delay: 600
                            text: qsTr("Drag the file to move it elsewhere")
                        }
                    }
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
