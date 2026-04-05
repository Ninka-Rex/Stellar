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

    width: 600
    height: 620
    minimumWidth: 500
    minimumHeight: 500
    title: "Browser Integration - Firefox Extension"
    color: "#1e1e1e"
    flags: Qt.Dialog | Qt.WindowTitleHint | Qt.WindowCloseButtonHint

    Material.theme: Material.Dark
    Material.background: "#1e1e1e"
    Material.accent: "#4488dd"

    // Registration state: "idle" | "ok" | "error"
    property string regState:    "idle"
    property string regError:    ""
    property string manifestPath: ""
    property string diagnostics: ""

    function runRegister() {
        regState      = "idle"
        manifestPath  = App.nativeHostManifestPath()
        var err = App.registerNativeHost()
        regState      = err === "" ? "ok" : "error"
        regError      = err
        diagnostics   = App.nativeHostDiagnostics()
    }

    onVisibleChanged: {
        if (visible) {
            runRegister()
        }
    }

    // Reusable inline component: a monospace code line with a copy button.
    component CopyRow: Rectangle {
        id: cr
        property string value: ""
        property bool   wrap:  false

        Layout.fillWidth: true
        height: wrap ? (codeText.implicitHeight + 16) : 30
        color: "#141420"
        border.color: "#2e2e4a"
        radius: 3

        Text {
            id: codeText
            anchors {
                verticalCenter: wrap ? undefined : parent.verticalCenter
                top: wrap ? parent.top : undefined
                topMargin: wrap ? 8 : 0
                left: parent.left; leftMargin: 8
                right: copyBtn.left; rightMargin: 6
            }
            text: cr.value
            color: "#88bbff"
            font.pixelSize: 11
            font.family: "monospace"
            wrapMode: cr.wrap ? Text.WrapAnywhere : Text.NoWrap
            elide:    cr.wrap ? Text.ElideNone    : Text.ElideRight
        }

        Rectangle {
            id: copyBtn
            anchors { right: parent.right; rightMargin: 4; verticalCenter: parent.verticalCenter }
            width: 46; height: 22; radius: 3
            color: copyMa.containsMouse ? "#2a4a7a" : "#1e3a5a"

            Text {
                id: copyBtnLabel
                anchors.centerIn: parent
                text: "Copy"
                color: "#88bbff"
                font.pixelSize: 10
            }

            MouseArea {
                id: copyMa
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    App.copyToClipboard(cr.value)
                    copyBtnLabel.text = "Copied"
                    copyBtnLabel.color = "#55cc55"
                    copyResetTimer.restart()
                }
            }

            Timer {
                id: copyResetTimer
                interval: 1500
                onTriggered: { copyBtnLabel.text = "Copy"; copyBtnLabel.color = "#88bbff" }
            }
        }
    }

    ScrollView {
        anchors.fill: parent
        contentWidth: availableWidth
        clip: true

        ColumnLayout {
            width: parent.width
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 16 }
            spacing: 12

            Text {
                text: "Firefox Extension Setup"
                color: "#ffffff"
                font.pixelSize: 15
                font.bold: true
            }
            Rectangle { Layout.fillWidth: true; height: 1; color: "#333" }

            Text {
                Layout.fillWidth: true
                text: "The Stellar Firefox extension intercepts browser downloads and routes them to Stellar. Follow the steps below."
                color: "#b0b0b0"
                font.pixelSize: 12
                wrapMode: Text.WordWrap
            }

            // Step 1 - Open extension folder
            Rectangle {
                Layout.fillWidth: true
                height: s1col.implicitHeight + 20
                color: "#222"
                border.color: "#333"
                radius: 4

                ColumnLayout {
                    id: s1col
                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
                    spacing: 8

                    RowLayout {
                        spacing: 8
                        Rectangle { width: 22; height: 22; radius: 11; color: "#2255aa"
                            Text { anchors.centerIn: parent; text: "1"; color: "#fff"; font.pixelSize: 11; font.bold: true } }
                        Text { text: "Open the extension folder"; color: "#fff"; font.pixelSize: 13; font.bold: true }
                    }

                    RowLayout {
                        spacing: 8
                        Layout.leftMargin: 30

                        Rectangle {
                            width: 160; height: 28; radius: 3
                            color: openFolderMa.containsMouse ? "#3a5a9a" : "#2a4a7a"
                            Text { anchors.centerIn: parent; text: "Open Extension Folder"; color: "#fff"; font.pixelSize: 12 }
                            MouseArea {
                                id: openFolderMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: App.openExtensionFolder()
                            }
                        }

                        Text {
                            text: "Locate the extensions/firefox folder."
                            color: "#888"; font.pixelSize: 11
                        }
                    }
                }
            }

            // Step 2 - Navigate to about:debugging
            Rectangle {
                Layout.fillWidth: true
                height: s2col.implicitHeight + 20
                color: "#222"
                border.color: "#333"
                radius: 4

                ColumnLayout {
                    id: s2col
                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
                    spacing: 8

                    RowLayout {
                        spacing: 8
                        Rectangle { width: 22; height: 22; radius: 11; color: "#2255aa"
                            Text { anchors.centerIn: parent; text: "2"; color: "#fff"; font.pixelSize: 11; font.bold: true } }
                        Text { text: "Open Firefox debugging"; color: "#fff"; font.pixelSize: 13; font.bold: true }
                    }

                    Text {
                        Layout.leftMargin: 30
                        text: "In the Firefox address bar, navigate to this page:"
                        color: "#888"; font.pixelSize: 12
                    }

                    CopyRow {
                        Layout.leftMargin: 30
                        value: "about:debugging#/runtime/this-firefox"
                    }
                }
            }

            // Step 3 - Load add-on
            Rectangle {
                Layout.fillWidth: true
                height: s3col.implicitHeight + 20
                color: "#222"
                border.color: "#333"
                radius: 4

                ColumnLayout {
                    id: s3col
                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
                    spacing: 8

                    RowLayout {
                        spacing: 8
                        Rectangle { width: 22; height: 22; radius: 11; color: "#2255aa"
                            Text { anchors.centerIn: parent; text: "3"; color: "#fff"; font.pixelSize: 11; font.bold: true } }
                        Text { text: "Load the extension"; color: "#fff"; font.pixelSize: 13; font.bold: true }
                    }

                    Text {
                        Layout.fillWidth: true
                        Layout.leftMargin: 30
                        text: "Click \"Load Temporary Add-on...\" and select the manifest.json file inside the extension folder. The extension will stay loaded until Firefox restarts."
                        color: "#888"; font.pixelSize: 12; wrapMode: Text.WordWrap
                    }
                }
            }

            // Step 4 - Native messaging host registration
            Rectangle {
                Layout.fillWidth: true
                height: s4col.implicitHeight + 20
                color: "#222"
                border.color: root.regState === "error" ? "#6a2222"
                            : root.regState === "ok"    ? "#225522"
                            : "#333"
                radius: 4

                ColumnLayout {
                    id: s4col
                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
                    spacing: 8

                    RowLayout {
                        spacing: 8
                        Rectangle { width: 22; height: 22; radius: 11; color: "#2255aa"
                            Text { anchors.centerIn: parent; text: "4"; color: "#fff"; font.pixelSize: 11; font.bold: true } }
                        Text { text: "Register native messaging host"; color: "#fff"; font.pixelSize: 13; font.bold: true }
                    }

                    Text {
                        Layout.fillWidth: true
                        Layout.leftMargin: 30
                        text: "Stellar must be registered as a native messaging host so the extension can communicate with it."
                        color: "#888"; font.pixelSize: 12; wrapMode: Text.WordWrap
                    }

                    // Status row
                    RowLayout {
                        Layout.leftMargin: 30
                        spacing: 8

                        Rectangle {
                            width: 10; height: 10; radius: 5
                            color: root.regState === "ok"    ? "#44cc44"
                                 : root.regState === "error" ? "#cc4444"
                                 : "#888"
                        }

                        Text {
                            text: root.regState === "ok"    ? "Registered successfully."
                                : root.regState === "error" ? "Automatic registration failed."
                                : "Registering..."
                            color: root.regState === "ok"    ? "#55cc55"
                                 : root.regState === "error" ? "#cc5555"
                                 : "#888"
                            font.pixelSize: 12
                        }

                        Rectangle {
                            visible: root.regState !== "idle"
                            width: 70; height: 22; radius: 3
                            color: retryMa.containsMouse ? "#2a4a2a" : "#1e3a1e"
                            Text { anchors.centerIn: parent; text: "Try again"; color: "#77cc77"; font.pixelSize: 10 }
                            MouseArea {
                                id: retryMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: { root.runRegister() }
                            }
                        }
                    }

                    // Error detail
                    Rectangle {
                        visible: root.regState === "error" && root.regError !== ""
                        Layout.fillWidth: true
                        Layout.leftMargin: 30
                        height: errText.implicitHeight + 12
                        color: "#2a1515"
                        border.color: "#5a2222"
                        radius: 3

                        Text {
                            id: errText
                            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 6 }
                            text: root.regError
                            color: "#dd8888"; font.pixelSize: 11; wrapMode: Text.WordWrap
                        }
                    }

                    // Manual instructions (always visible so user can check the path,
                    // expanded automatically on error)
                    Item {
                        Layout.leftMargin: 30
                        Layout.fillWidth: true
                        height: manualToggleRow.height

                        RowLayout {
                            id: manualToggleRow
                            spacing: 6

                            Text {
                                text: manualSection.visible ? "Hide manual instructions" : "Show manual instructions"
                                color: "#4488dd"; font.pixelSize: 11
                                font.underline: true
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: manualSection.visible = !manualSection.visible
                                }
                            }
                        }
                    }

                    ColumnLayout {
                        id: manualSection
                        visible: root.regState === "error"
                        Layout.fillWidth: true
                        Layout.leftMargin: 30
                        spacing: 6

                        Text {
                            text: "Manifest file written to:"
                            color: "#888"; font.pixelSize: 11
                        }
                        CopyRow { value: root.manifestPath }

                        // Windows
                        Text {
                            visible: Qt.platform.os === "windows"
                            Layout.fillWidth: true
                            text: "Windows - run in Command Prompt (no admin required):"
                            color: "#888"; font.pixelSize: 11
                            wrapMode: Text.WordWrap
                        }
                        CopyRow {
                            visible: Qt.platform.os === "windows"
                            wrap: true
                            value: "reg add \"HKCU\\Software\\Mozilla\\NativeMessagingHosts\\com.stellar.downloadmanager\" /ve /t REG_SZ /d \"" + root.manifestPath + "\" /f"
                        }

                        // Linux
                        Text {
                            visible: Qt.platform.os !== "windows"
                            Layout.fillWidth: true
                            text: "Linux - run in a terminal:"
                            color: "#888"; font.pixelSize: 11
                        }
                        CopyRow {
                            visible: Qt.platform.os !== "windows"
                            value: "mkdir -p ~/.mozilla/native-messaging-hosts"
                        }
                        CopyRow {
                            visible: Qt.platform.os !== "windows"
                            wrap: true
                            value: "cp \"" + root.manifestPath + "\" ~/.mozilla/native-messaging-hosts/com.stellar.downloadmanager.json"
                        }
                    }
                }
            }

            // Diagnostics panel
            Rectangle {
                Layout.fillWidth: true
                height: diagCol.implicitHeight + 16
                color: "#1a1a1a"
                border.color: "#2e2e2e"
                radius: 4

                ColumnLayout {
                    id: diagCol
                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: 10 }
                    spacing: 6

                    RowLayout {
                        spacing: 6
                        Text { text: "Diagnostics"; color: "#888"; font.pixelSize: 12; font.bold: true }
                        Rectangle {
                            width: 50; height: 18; radius: 3
                            color: diagRefreshMa.containsMouse ? "#2a3a4a" : "#1e2e3a"
                            Text { anchors.centerIn: parent; text: "Refresh"; color: "#4488dd"; font.pixelSize: 10 }
                            MouseArea {
                                id: diagRefreshMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.runRegister()
                            }
                        }
                    }

                    TextArea {
                        Layout.fillWidth: true
                        readOnly: true
                        text: root.diagnostics
                        color: "#aaaaaa"
                        font.pixelSize: 10
                        font.family: "monospace"
                        background: null
                        wrapMode: Text.WrapAnywhere
                        selectByMouse: true
                    }
                }
            }

            Rectangle { Layout.fillWidth: true; height: 1; color: "#2a2a2a" }

            Text {
                Layout.fillWidth: true
                text: "Temporary add-ons are removed when Firefox restarts. To install permanently, the extension needs to be signed by Mozilla. See Help > Browser Integration for details on signing via addons.mozilla.org."
                color: "#555"; font.pixelSize: 11; wrapMode: Text.WordWrap
            }

            Item { height: 8 }
        }
    }
}
