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
    minimumHeight: 360
    title: "Browser Extensions"
    color: "#1e1e1e"
    flags: Qt.Dialog | Qt.WindowTitleHint | Qt.WindowCloseButtonHint

    Material.theme: Material.Dark
    Material.background: "#1e1e1e"
    Material.accent: "#4488dd"

    property string regState:    "idle"
    property string regError:    ""
    property string manifestPath: ""

    // These are populated from update.json once the app fetches it;
    // fall back to known stable store URLs so the dialog is never empty.
    readonly property string chromeUrl:  App.chromeExtensionUrl  || "https://chromewebstore.google.com/detail/stellar-download-manager/TODO"
    readonly property string firefoxUrl: App.firefoxExtensionUrl || "https://addons.mozilla.org/firefox/addon/stellar-download-manager/"

    function runRegister() {
        regState     = "idle"
        manifestPath = App.nativeHostManifestPath()
        var err      = App.registerNativeHost()
        regState     = err === "" ? "ok" : "error"
        regError     = err
    }

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
        if (visible) { _centerOnOwner(); runRegister() }
    }

    // ── Install button ─────────────────────────────────────────────────────────
    component InstallButton: Rectangle {
        id: ib
        property string label: ""
        property string url:   ""

        width: 160; height: 28; radius: 3
        color: ibMa.containsMouse ? "#3a5a9a" : "#2a4a7a"

        Text {
            anchors.centerIn: parent
            text: ib.label
            color: "#fff"
            font.pixelSize: 11
        }
        MouseArea {
            id: ibMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: Qt.openUrlExternally(ib.url)
        }
    }

    ScrollView {
        anchors.fill: parent
        contentWidth: availableWidth
        clip: true

        ColumnLayout {
            width: parent.width
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
            spacing: 10

            Text {
                text: "Browser Extensions"
                color: "#ffffff"
                font.pixelSize: 15
                font.bold: true
            }
            Rectangle { Layout.fillWidth: true; height: 1; color: "#333" }

            Text {
                Layout.fillWidth: true
                text: "Install the Stellar extension in your browser to intercept downloads and route them to Stellar automatically."
                color: "#b0b0b0"
                font.pixelSize: 12
                wrapMode: Text.WordWrap
            }

            // ── Chrome ────────────────────────────────────────────────────────
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: chromeCol.implicitHeight + 16
                color: "#222"
                border.color: "#333"
                radius: 4

                ColumnLayout {
                    id: chromeCol
                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: 8 }
                    spacing: 6

                    RowLayout {
                        spacing: 8
                        Text { text: "Chrome / Edge / Brave"; color: "#fff"; font.pixelSize: 13; font.bold: true }
                    }
                    Text {
                        Layout.fillWidth: true
                        text: "Install directly from the Chrome Web Store — no manual steps required."
                        color: "#999"; font.pixelSize: 12; wrapMode: Text.WordWrap
                    }
                    InstallButton {
                        label: "Open Chrome Web Store"
                        url: root.chromeUrl
                    }
                }
            }

            // ── Firefox ───────────────────────────────────────────────────────
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: firefoxCol.implicitHeight + 16
                color: "#222"
                border.color: "#333"
                radius: 4

                ColumnLayout {
                    id: firefoxCol
                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: 8 }
                    spacing: 6

                    Text { text: "Firefox"; color: "#fff"; font.pixelSize: 13; font.bold: true }
                    Text {
                        Layout.fillWidth: true
                        text: "Install from Mozilla Add-ons (AMO) — one click, automatic updates."
                        color: "#999"; font.pixelSize: 12; wrapMode: Text.WordWrap
                    }
                    InstallButton {
                        label: "Open Firefox Add-ons"
                        url: root.firefoxUrl
                    }
                }
            }

            // ── Native messaging host ─────────────────────────────────────────
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: hostCol.implicitHeight + 16
                color: "#222"
                border.color: "#333"
                radius: 4

                ColumnLayout {
                    id: hostCol
                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: 8 }
                    spacing: 6

                    Text { text: "Native Messaging Host"; color: "#fff"; font.pixelSize: 13; font.bold: true }
                    Text {
                        Layout.fillWidth: true
                        text: "Stellar registers itself automatically so the extension can communicate with it."
                        color: "#999"; font.pixelSize: 12; wrapMode: Text.WordWrap
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

                    // Error detail + manual fallback
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

                    // Inline copy row — reused twice; extracted as component here
                    // to avoid importing the CopyRow from the old dialog.
                    Rectangle {
                        visible: root.regState === "error" && Qt.platform.os === "windows"
                        Layout.fillWidth: true
                        height: crWinText.implicitHeight + 16
                        color: "#141420"; border.color: "#2e2e4a"; radius: 3

                        Text {
                            id: crWinText
                            anchors { top: parent.top; topMargin: 8; left: parent.left; leftMargin: 8; right: crWinBtn.left; rightMargin: 6 }
                            text: "reg add \"HKCU\\Software\\Mozilla\\NativeMessagingHosts\\com.stellar.downloadmanager\" /ve /t REG_SZ /d \"" + root.manifestPath + "\" /f"
                            color: "#88bbff"; font.pixelSize: 11; font.family: "monospace"; wrapMode: Text.WrapAnywhere
                        }
                        Rectangle {
                            id: crWinBtn
                            anchors { right: parent.right; rightMargin: 4; verticalCenter: parent.verticalCenter }
                            width: 46; height: 20; radius: 3
                            color: crWinMa.containsMouse ? "#2a4a7a" : "#1e3a5a"
                            Text { id: crWinLabel; anchors.centerIn: parent; text: "Copy"; color: "#88bbff"; font.pixelSize: 10 }
                            MouseArea {
                                id: crWinMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                onClicked: { App.copyToClipboard(crWinText.text); crWinLabel.text = "Copied"; crWinLabel.color = "#55cc55"; crWinReset.restart() }
                            }
                            Timer { id: crWinReset; interval: 1500; onTriggered: { crWinLabel.text = "Copy"; crWinLabel.color = "#88bbff" } }
                        }
                    }

                    Text {
                        visible: root.regState === "error" && Qt.platform.os !== "windows"
                        Layout.fillWidth: true
                        text: "Run in a terminal:"
                        color: "#888"; font.pixelSize: 11
                    }

                    Rectangle {
                        visible: root.regState === "error" && Qt.platform.os !== "windows"
                        Layout.fillWidth: true; height: 28; color: "#141420"; border.color: "#2e2e4a"; radius: 3
                        Text { anchors { verticalCenter: parent.verticalCenter; left: parent.left; leftMargin: 8; right: crMkBtn.left; rightMargin: 6 }
                               text: "mkdir -p ~/.mozilla/native-messaging-hosts"; color: "#88bbff"; font.pixelSize: 11; font.family: "monospace"; elide: Text.ElideRight }
                        Rectangle {
                            id: crMkBtn; anchors { right: parent.right; rightMargin: 4; verticalCenter: parent.verticalCenter }
                            width: 46; height: 20; radius: 3; color: crMkMa.containsMouse ? "#2a4a7a" : "#1e3a5a"
                            Text { id: crMkLabel; anchors.centerIn: parent; text: "Copy"; color: "#88bbff"; font.pixelSize: 10 }
                            MouseArea { id: crMkMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                onClicked: { App.copyToClipboard("mkdir -p ~/.mozilla/native-messaging-hosts"); crMkLabel.text = "Copied"; crMkLabel.color = "#55cc55"; crMkReset.restart() } }
                            Timer { id: crMkReset; interval: 1500; onTriggered: { crMkLabel.text = "Copy"; crMkLabel.color = "#88bbff" } }
                        }
                    }

                    Rectangle {
                        visible: root.regState === "error" && Qt.platform.os !== "windows"
                        Layout.fillWidth: true
                        height: crCpText.implicitHeight + 16
                        color: "#141420"; border.color: "#2e2e4a"; radius: 3

                        Text {
                            id: crCpText
                            anchors { top: parent.top; topMargin: 8; left: parent.left; leftMargin: 8; right: crCpBtn.left; rightMargin: 6 }
                            text: "cp \"" + root.manifestPath + "\" ~/.mozilla/native-messaging-hosts/com.stellar.downloadmanager.json"
                            color: "#88bbff"; font.pixelSize: 11; font.family: "monospace"; wrapMode: Text.WrapAnywhere
                        }
                        Rectangle {
                            id: crCpBtn
                            anchors { right: parent.right; rightMargin: 4; verticalCenter: parent.verticalCenter }
                            width: 46; height: 20; radius: 3
                            color: crCpMa.containsMouse ? "#2a4a7a" : "#1e3a5a"
                            Text { id: crCpLabel; anchors.centerIn: parent; text: "Copy"; color: "#88bbff"; font.pixelSize: 10 }
                            MouseArea {
                                id: crCpMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                onClicked: { App.copyToClipboard(crCpText.text); crCpLabel.text = "Copied"; crCpLabel.color = "#55cc55"; crCpReset.restart() }
                            }
                            Timer { id: crCpReset; interval: 1500; onTriggered: { crCpLabel.text = "Copy"; crCpLabel.color = "#88bbff" } }
                        }
                    }
                }
            }

            Item { height: 4 }
        }
    }
}
