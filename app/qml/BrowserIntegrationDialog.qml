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

    width: 500
    height: 400
    minimumWidth: 420
    minimumHeight: 400
    title: "Browser Extension Setup"
    color: "#1e1e1e"
    flags: Qt.Dialog | Qt.WindowTitleHint | Qt.WindowCloseButtonHint

    Material.theme: Material.Dark
    Material.background: "#1e1e1e"
    Material.accent: "#4488dd"

    property string regState:    "idle"
    property string regError:    ""
    property string manifestPath: ""

    function runRegister() {
        regState     = "idle"
        manifestPath = App.nativeHostManifestPath()
        var err      = App.registerNativeHost()
        regState     = err === "" ? "ok" : "error"
        regError     = err
    }

    onVisibleChanged: {
        if (visible) runRegister()
    }

    component StepBox: Rectangle {
        id: sb
        property int    num:     1
        property string heading: ""
        default property alias content: sbContent.data

        Layout.fillWidth: true
        implicitHeight: sbCol.implicitHeight + 14
        height: implicitHeight
        color: "#222"
        border.color: "#333"
        radius: 4

        ColumnLayout {
            id: sbCol
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 8 }
            spacing: 6

            RowLayout {
                spacing: 8
                Rectangle {
                    width: 22; height: 22; radius: 11; color: "#2255aa"
                    Text { anchors.centerIn: parent; text: sb.num; color: "#fff"; font.pixelSize: 11; font.bold: true }
                }
                Text { text: sb.heading; color: "#fff"; font.pixelSize: 13; font.bold: true }
            }

            ColumnLayout {
                id: sbContent
                Layout.fillWidth: true
                Layout.leftMargin: 26
                spacing: 6
            }
        }
    }

    component CopyRow: Rectangle {
        id: cr
        property string value: ""
        property bool   wrap:  false

        Layout.fillWidth: true
        height: wrap ? (codeText.implicitHeight + 16) : 28
        color: "#141420"
        border.color: "#2e2e4a"
        radius: 3

        Text {
            id: codeText
            anchors {
                verticalCenter: wrap ? undefined : parent.verticalCenter
                top:            wrap ? parent.top : undefined
                topMargin:      wrap ? 8 : 0
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
            width: 46; height: 20; radius: 3
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
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
            spacing: 6

            Text {
                text: "Firefox Extension Setup"
                color: "#ffffff"
                font.pixelSize: 15
                font.bold: true
            }
            Rectangle { Layout.fillWidth: true; height: 1; color: "#333" }

            Text {
                Layout.fillWidth: true
                text: "The Stellar Firefox extension intercepts browser downloads and routes them to Stellar. Follow the three steps below."
                color: "#b0b0b0"
                font.pixelSize: 12
                wrapMode: Text.WordWrap
            }

            // Step 1 — Get the extension file
            StepBox {
                num: 1
                heading: "Get the extension file"

                Text {
                    Layout.fillWidth: true
                    text: "Open the extension folder — it contains <b>stellar-firefox.xpi</b>."
                    color: "#999"
                    font.pixelSize: 12
                    wrapMode: Text.WordWrap
                    textFormat: Text.StyledText
                }

                Rectangle {
                    width: 160; height: 26; radius: 3
                    color: openFolderMa.containsMouse ? "#3a5a9a" : "#2a4a7a"
                    Text { anchors.centerIn: parent; text: "Open Extension Folder"; color: "#fff"; font.pixelSize: 11 }
                    MouseArea {
                        id: openFolderMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: App.openExtensionFolder()
                    }
                }
            }

            // Step 2 — Install in Firefox
            StepBox {
                num: 2
                heading: "Install the extension"

                Text {
                    Layout.fillWidth: true
                    text: "Open Firefox Add-ons Manager, click the gear icon ⚙, choose <b>Install Add-on From File…</b>, and select the .xpi file."
                    color: "#999"
                    font.pixelSize: 12
                    wrapMode: Text.WordWrap
                    textFormat: Text.StyledText
                }

                RowLayout {
                    spacing: 8

                    CopyRow {
                        value: "about:addons"
                        Layout.preferredWidth: 180
                    }

                    Text {
                        text: "paste in the Firefox address bar"
                        color: "#666"
                        font.pixelSize: 11
                    }
                }
            }

            // Step 3 — Native messaging host
            StepBox {
                num: 3
                heading: "Register native messaging host"

                Text {
                    Layout.fillWidth: true
                    text: "Stellar registers itself automatically so the extension can communicate with it."
                    color: "#999"
                    font.pixelSize: 12
                    wrapMode: Text.WordWrap
                }

                RowLayout {
                    spacing: 8

                    Rectangle {
                        width: 10; height: 10; radius: 5
                        color: root.regState === "ok"    ? "#44cc44"
                             : root.regState === "error" ? "#cc4444"
                             : "#888"
                    }

                    Text {
                        text: root.regState === "ok"    ? "Registered successfully."
                            : root.regState === "error" ? "Registration failed — see details below."
                            : "Registering…"
                        color: root.regState === "ok"    ? "#55cc55"
                             : root.regState === "error" ? "#cc5555"
                             : "#888"
                        font.pixelSize: 12
                    }

                    Rectangle {
                        visible: root.regState !== "idle"
                        width: 68; height: 22; radius: 3
                        color: retryMa.containsMouse ? "#2a4a2a" : "#1e3a1e"
                        Text { anchors.centerIn: parent; text: "Try again"; color: "#77cc77"; font.pixelSize: 10 }
                        MouseArea {
                            id: retryMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.runRegister()
                        }
                    }
                }

                // Error detail + manual fallback (only shown on error)
                Rectangle {
                    visible: root.regState === "error"
                    Layout.fillWidth: true
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

                Text {
                    visible: root.regState === "error"
                    text: "Manual installation:"
                    color: "#888"; font.pixelSize: 11; font.bold: true
                }

                Text {
                    visible: root.regState === "error" && Qt.platform.os === "windows"
                    Layout.fillWidth: true
                    text: "Run in Command Prompt (no admin required):"
                    color: "#888"; font.pixelSize: 11
                }
                CopyRow {
                    visible: root.regState === "error" && Qt.platform.os === "windows"
                    wrap: true
                    value: "reg add \"HKCU\\Software\\Mozilla\\NativeMessagingHosts\\com.stellar.downloadmanager\" /ve /t REG_SZ /d \"" + root.manifestPath + "\" /f"
                }

                Text {
                    visible: root.regState === "error" && Qt.platform.os !== "windows"
                    Layout.fillWidth: true
                    text: "Run in a terminal:"
                    color: "#888"; font.pixelSize: 11
                }
                CopyRow {
                    visible: root.regState === "error" && Qt.platform.os !== "windows"
                    value: "mkdir -p ~/.mozilla/native-messaging-hosts"
                }
                CopyRow {
                    visible: root.regState === "error" && Qt.platform.os !== "windows"
                    wrap: true
                    value: "cp \"" + root.manifestPath + "\" ~/.mozilla/native-messaging-hosts/com.stellar.downloadmanager.json"
                }
            }

            Item { height: 4 }
        }
    }
}
