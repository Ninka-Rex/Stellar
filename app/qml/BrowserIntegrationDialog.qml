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
    title: qsTr("Browser Extensions")
    color: "#1e1e1e"
    flags: Qt.Dialog | Qt.WindowTitleHint | Qt.WindowCloseButtonHint

    Material.theme: Material.Dark
    Material.background: "#1e1e1e"
    Material.accent: "#4488dd"

    property string regState:       "idle"
    property string regError:       ""
    property string manifestPath:   ""
    // sandboxedIssue: "" | "snap" | "flatpak_perm"
    property string sandboxedIssue: ""
    property string actionStatus:   ""    // "", "ok", "fail"
    property string actionMessage:  ""
    property string portalLaunchStatus: ""   // "" | "ok" | "fail"  (snap section)
    property string grantStatus:    ""       // "" | "ok" | "fail"  (flatpak perm section)

    // These are populated from update.json once the app fetches it;
    // fall back to known stable store URLs so the dialog is never empty.
    readonly property string chromeUrl:  App.chromeExtensionUrl  || "https://chromewebstore.google.com/detail/stellar-integration-modul/pppelmimeffdigknplngfmhefcbhfcbd"
    readonly property string firefoxUrl: App.firefoxExtensionUrl || "https://addons.mozilla.org/firefox/addon/stellar-download-manager/"

    function runRegister() {
        regState     = "idle"
        manifestPath = App.nativeHostManifestPath()
        var err      = App.registerNativeHost()
        regState     = err === "" ? "ok" : "error"
        regError     = err
        sandboxedIssue = (Qt.platform.os === "linux") ? App.sandboxedFirefoxIssue() : ""
        actionStatus      = ""
        actionMessage     = ""
        portalLaunchStatus = ""
        grantStatus       = ""
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
            font.pixelSize: 11 * App.fontScale
        }
        MouseArea {
            id: ibMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: App.openExternalUrl(ib.url)
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
                text: qsTr("Browser Extensions")
                color: "#ffffff"
                font.pixelSize: 15 * App.fontScale
                font.bold: true
            }
            Rectangle { Layout.fillWidth: true; height: 1; color: "#333" }

            Text {
                Layout.fillWidth: true
                text: qsTr("Install the Stellar extension in your browser to intercept downloads and route them to Stellar automatically.")
                color: "#b0b0b0"
                font.pixelSize: 12 * App.fontScale
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
                        Text { text: qsTr("Chrome / Edge / Brave"); color: "#fff"; font.pixelSize: 13 * App.fontScale; font.bold: true }
                    }
                    Text {
                        Layout.fillWidth: true
                        text: qsTr("Install directly from the Chrome Web Store")
                        color: "#999"; font.pixelSize: 12 * App.fontScale; wrapMode: Text.WordWrap
                    }
                    InstallButton {
                        label: qsTr("Open Link")
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

                    Text { text: qsTr("Firefox"); color: "#fff"; font.pixelSize: 13 * App.fontScale; font.bold: true }
                    Text {
                        Layout.fillWidth: true
                        text: qsTr("Install Firefox XPI, no automatic updates")
                        color: "#999"; font.pixelSize: 12 * App.fontScale; wrapMode: Text.WordWrap
                    }
                    InstallButton {
                        label: qsTr("Open Link")
                        url: root.firefoxUrl
                    }

                    // ── Snap-Firefox-on-KDE compatibility notice ─────────────
                    // Snap Firefox is confined and cannot launch the Stellar
                    // host binary directly. The clean fix is to use a
                    // non-snap Firefox (flatpak / Mozilla deb) or another
                    // Chromium-family browser. We never recommend installing
                    // xdg-desktop-portal-gnome — it pulls GNOME components
                    // that can break SDDM / switch-user on Plasma.
                    Rectangle {
                        visible: root.sandboxedIssue === "snap"
                        Layout.fillWidth: true
                        Layout.topMargin: 4
                        implicitHeight: snapCol.implicitHeight + 16
                        color: "#3a2a14"
                        border.color: "#6a4a22"
                        radius: 3

                        ColumnLayout {
                            id: snapCol
                            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 8 }
                            spacing: 6

                            RowLayout {
                                spacing: 6
                                Text { text: "⚠"; color: "#ddaa55"; font.pixelSize: 14 * App.fontScale }
                                Text {
                                    text: qsTr("Snap Firefox detected — won't work with Stellar")
                                    color: "#ddaa55"; font.pixelSize: 12 * App.fontScale; font.bold: true
                                }
                            }
                            Text {
                                Layout.fillWidth: true
                                text: qsTr("Snap Firefox runs in a confined sandbox and can't launch the Stellar host. Switch to the Firefox flatpak (recommended), Mozilla's official .deb, or use Chromium / Brave / Vivaldi instead.")
                                color: "#ddc8a0"; font.pixelSize: 11 * App.fontScale; wrapMode: Text.WordWrap
                            }

                            RowLayout {
                                spacing: 8
                                Rectangle {
                                    width: 220; height: 26; radius: 3
                                    color: discoverMa.containsMouse ? "#3a5a9a" : "#2a4a7a"

                                    Text {
                                        anchors.centerIn: parent
                                        text: qsTr("Open Firefox flatpak in Discover")
                                        color: "#fff"; font.pixelSize: 11 * App.fontScale
                                    }
                                    MouseArea {
                                        id: discoverMa
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            var ok = App.openFlatpakFirefoxInDiscover()
                                            root.portalLaunchStatus = ok ? "ok" : "fail"
                                        }
                                    }
                                }
                                Rectangle {
                                    width: 160; height: 26; radius: 3
                                    color: mozMa.containsMouse ? "#3a5a9a" : "#2a4a7a"
                                    Text {
                                        anchors.centerIn: parent
                                        text: qsTr("Mozilla download page")
                                        color: "#fff"; font.pixelSize: 11 * App.fontScale
                                    }
                                    MouseArea {
                                        id: mozMa
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: App.openExternalUrl("https://www.mozilla.org/firefox/download/thanks/")
                                    }
                                }
                            }
                            Text {
                                visible: root.portalLaunchStatus === "fail"
                                Layout.fillWidth: true
                                text: qsTr("Could not open Discover — search for \"Firefox\" manually in your store, or use the Mozilla download link.")
                                color: "#cc7777"; font.pixelSize: 11 * App.fontScale; wrapMode: Text.WordWrap
                            }
                            Text {
                                visible: root.portalLaunchStatus === "ok"
                                Layout.fillWidth: true
                                text: qsTr("Opened. Install Firefox, then uninstall the snap version (System Settings → Apps).")
                                color: "#88cc88"; font.pixelSize: 11 * App.fontScale; wrapMode: Text.WordWrap
                            }
                        }
                    }

                    // ── Flatpak Firefox needs org.freedesktop.Flatpak=talk ────────
                    Rectangle {
                        visible: root.sandboxedIssue === "flatpak_perm"
                        Layout.fillWidth: true
                        Layout.topMargin: 4
                        implicitHeight: flatpakPermCol.implicitHeight + 16
                        color: "#1a2a3a"
                        border.color: "#2a4a6a"
                        radius: 3

                        ColumnLayout {
                            id: flatpakPermCol
                            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 8 }
                            spacing: 6

                            RowLayout {
                                spacing: 6
                                Text { text: "⚠"; color: "#5599dd"; font.pixelSize: 14 * App.fontScale }
                                Text {
                                    text: qsTr("Flatpak Firefox needs an extra permission")
                                    color: "#5599dd"; font.pixelSize: 12 * App.fontScale; font.bold: true
                                }
                            }
                            Text {
                                Layout.fillWidth: true
                                text: qsTr("Firefox (Flatpak) runs in a sandbox and needs the org.freedesktop.Flatpak=talk permission to launch the Stellar native messaging host. Click the button below to grant it, then restart Firefox.")
                                color: "#aac8e8"; font.pixelSize: 11 * App.fontScale; wrapMode: Text.WordWrap
                            }

                            RowLayout {
                                spacing: 8

                                Rectangle {
                                    width: 200; height: 26; radius: 3
                                    color: grantMa.containsMouse ? "#2a5a8a" : "#1a4a7a"

                                    Text {
                                        anchors.centerIn: parent
                                        text: qsTr("Grant permission")
                                        color: "#fff"; font.pixelSize: 11 * App.fontScale
                                    }
                                    MouseArea {
                                        id: grantMa
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            var err = App.grantFlatpakFirefoxNativeMessagingPermission()
                                            if (err === "") {
                                                root.grantStatus = "ok"
                                            } else {
                                                root.grantStatus = "fail"
                                                root.actionMessage = err
                                            }
                                        }
                                    }
                                }
                            }

                            Text {
                                visible: root.grantStatus === "ok"
                                Layout.fillWidth: true
                                text: qsTr("Permission granted. Restart Firefox for the change to take effect.")
                                color: "#88cc88"; font.pixelSize: 11 * App.fontScale; wrapMode: Text.WordWrap
                            }
                            Text {
                                visible: root.grantStatus === "fail"
                                Layout.fillWidth: true
                                text: qsTr("Failed to grant permission: ") + root.actionMessage
                                      + qsTr("\n\nRun manually: flatpak override --user --talk-name=org.freedesktop.Flatpak org.mozilla.firefox")
                                color: "#cc7777"; font.pixelSize: 11 * App.fontScale; wrapMode: Text.WordWrap
                            }
                        }
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

                    Text { text: qsTr("Native Messaging Host"); color: "#fff"; font.pixelSize: 13 * App.fontScale; font.bold: true }
                    Text {
                        Layout.fillWidth: true
                        text: qsTr("Stellar registers itself automatically so the extension can communicate with it.")
                        color: "#999"; font.pixelSize: 12 * App.fontScale; wrapMode: Text.WordWrap
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
                            text: root.regState === "ok"    ? qsTr("Registered successfully.")
                                : root.regState === "error" ? qsTr("Registration failed — see details below.")
                                : qsTr("Registering…")
                            color: root.regState === "ok"    ? "#55cc55"
                                 : root.regState === "error" ? "#cc5555"
                                 : "#888"
                            font.pixelSize: 12 * App.fontScale
                        }

                        Rectangle {
                            visible: root.regState !== "idle"
                            width: 68; height: 22; radius: 3
                            color: retryMa.containsMouse ? "#2a4a2a" : "#1e3a1e"
                            Text { anchors.centerIn: parent; text: qsTr("Try again"); color: "#77cc77"; font.pixelSize: 10 * App.fontScale }
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
                            color: "#dd8888"; font.pixelSize: 11 * App.fontScale; wrapMode: Text.WordWrap
                        }
                    }

                    Text {
                        visible: root.regState === "error"
                        text: qsTr("Manual installation:")
                        color: "#888"; font.pixelSize: 11 * App.fontScale; font.bold: true
                    }

                    Text {
                        visible: root.regState === "error" && Qt.platform.os === "windows"
                        Layout.fillWidth: true
                        text: qsTr("Run in Command Prompt (no admin required):")
                        color: "#888"; font.pixelSize: 11 * App.fontScale
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
                            color: "#88bbff"; font.pixelSize: 11 * App.fontScale; font.family: "monospace"; wrapMode: Text.WrapAnywhere
                        }
                        Rectangle {
                            id: crWinBtn
                            anchors { right: parent.right; rightMargin: 4; verticalCenter: parent.verticalCenter }
                            width: 46; height: 20; radius: 3
                            color: crWinMa.containsMouse ? "#2a4a7a" : "#1e3a5a"
                            Text { id: crWinLabel; anchors.centerIn: parent; text: qsTr("Copy"); color: "#88bbff"; font.pixelSize: 10 * App.fontScale }
                            MouseArea {
                                id: crWinMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                onClicked: { App.copyToClipboard(crWinText.text); crWinLabel.text = qsTr("Copied"); crWinLabel.color = "#55cc55"; crWinReset.restart() }
                            }
                            Timer { id: crWinReset; interval: 1500; onTriggered: { crWinLabel.text = qsTr("Copy"); crWinLabel.color = "#88bbff" } }
                        }
                    }

                    Text {
                        visible: root.regState === "error" && Qt.platform.os !== "windows"
                        Layout.fillWidth: true
                        text: qsTr("Run in a terminal:")
                        color: "#888"; font.pixelSize: 11 * App.fontScale
                    }

                    Rectangle {
                        visible: root.regState === "error" && Qt.platform.os !== "windows"
                        Layout.fillWidth: true; height: 28; color: "#141420"; border.color: "#2e2e4a"; radius: 3
                        Text { anchors { verticalCenter: parent.verticalCenter; left: parent.left; leftMargin: 8; right: crMkBtn.left; rightMargin: 6 }
                               text: "mkdir -p ~/.mozilla/native-messaging-hosts"; color: "#88bbff"; font.pixelSize: 11 * App.fontScale; font.family: "monospace"; elide: Text.ElideRight }
                        Rectangle {
                            id: crMkBtn; anchors { right: parent.right; rightMargin: 4; verticalCenter: parent.verticalCenter }
                            width: 46; height: 20; radius: 3; color: crMkMa.containsMouse ? "#2a4a7a" : "#1e3a5a"
                            Text { id: crMkLabel; anchors.centerIn: parent; text: qsTr("Copy"); color: "#88bbff"; font.pixelSize: 10 * App.fontScale }
                            MouseArea { id: crMkMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                onClicked: { App.copyToClipboard("mkdir -p ~/.mozilla/native-messaging-hosts"); crMkLabel.text = qsTr("Copied"); crMkLabel.color = "#55cc55"; crMkReset.restart() } }
                            Timer { id: crMkReset; interval: 1500; onTriggered: { crMkLabel.text = qsTr("Copy"); crMkLabel.color = "#88bbff" } }
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
                            color: "#88bbff"; font.pixelSize: 11 * App.fontScale; font.family: "monospace"; wrapMode: Text.WrapAnywhere
                        }
                        Rectangle {
                            id: crCpBtn
                            anchors { right: parent.right; rightMargin: 4; verticalCenter: parent.verticalCenter }
                            width: 46; height: 20; radius: 3
                            color: crCpMa.containsMouse ? "#2a4a7a" : "#1e3a5a"
                            Text { id: crCpLabel; anchors.centerIn: parent; text: qsTr("Copy"); color: "#88bbff"; font.pixelSize: 10 * App.fontScale }
                            MouseArea {
                                id: crCpMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                onClicked: { App.copyToClipboard(crCpText.text); crCpLabel.text = qsTr("Copied"); crCpLabel.color = "#55cc55"; crCpReset.restart() }
                            }
                            Timer { id: crCpReset; interval: 1500; onTriggered: { crCpLabel.text = qsTr("Copy"); crCpLabel.color = "#88bbff" } }
                        }
                    }
                }
            }

            Item { height: 4 }
        }
    }
}
