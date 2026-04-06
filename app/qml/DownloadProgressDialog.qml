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

    property string downloadId: ""
    property var    item: null
    property bool   detailsVisible: true

    width: 700
    height: 580
    minimumWidth: 420
    minimumHeight: 260

    property bool _updatingSpeedUI: false

    function applyPerDownloadSpeed() {
        if (_updatingSpeedUI || !root.item || !root.downloadId) return
        if (limitThisChk.checked) {
            var kbps = parseInt(speedInput.text) || 0
            if (kbps > 0)
                App.setDownloadSpeedLimit(root.downloadId, kbps)
        } else {
            App.setDownloadSpeedLimit(root.downloadId, 0)
        }
    }

    onItemChanged: {
        _updatingSpeedUI = true
        if (item && item.speedLimitKBps > 0) {
            speedInput.text = String(item.speedLimitKBps)
            limitThisChk.checked = true
        } else {
            speedInput.text = ""
            limitThisChk.checked = false
        }
        _updatingSpeedUI = false
    }

    onDetailsVisibleChanged: {
        if (detailsVisible) {
            maximumHeight = 16777215
            minimumHeight = 480
            height = 580
        } else {
            minimumHeight = 260
            maximumHeight = 300
            height = 300
        }
    }
    color: "#1e1e1e"

    title: {
        if (!item) return "Download"
        var pct = item.progress > 0 ? Math.round(item.progress * 100) + "% " : ""
        return pct + item.filename
    }

    Material.theme: Material.Dark
    Material.background: "#1e1e1e"
    Material.accent: "#4488dd"

    function fmtBytes(b) {
        if (b === undefined || b === null || b < 0) return "--"
        if (b < 1024)       return b + " B"
        if (b < 1048576)    return (b / 1024).toFixed(1) + " KB"
        if (b < 1073741824) return (b / 1048576).toFixed(2) + " MB"
        return (b / 1073741824).toFixed(2) + " GB"
    }

    function fmtSpeed(bps) {
        if (!bps || bps <= 0) return "--"
        if (bps < 1024)    return bps + " B/s"
        if (bps < 1048576) return (bps / 1024).toFixed(1) + " KB/s"
        return (bps / 1048576).toFixed(2) + " MB/s"
    }

    function statusColor(s) {
        if (s === "Downloading") return "#44bb44"
        if (s === "Paused")      return "#e0c040"
        if (s === "Completed")   return "#60c0e0"
        if (s === "Error")       return "#e06060"
        return "#b0b0b0"
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // ── Tab bar ──────────────────────────────────────────────────────────
        TabBar {
            id: tabBar
            Layout.fillWidth: true
            background: Rectangle { color: "#2d2d2d" }

            TabButton {
                text: "Download status"
                background: Rectangle {
                    color: tabBar.currentIndex === 0 ? "#1e1e1e" : "transparent"
                    Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 2; color: tabBar.currentIndex === 0 ? "#4488dd" : "transparent" }
                }
            }
            TabButton {
                text: "Speed Limiter"
                background: Rectangle {
                    color: tabBar.currentIndex === 1 ? "#1e1e1e" : "transparent"
                    Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 2; color: tabBar.currentIndex === 1 ? "#4488dd" : "transparent" }
                }
            }
            TabButton {
                text: "Options on completion"
                background: Rectangle {
                    color: tabBar.currentIndex === 2 ? "#1e1e1e" : "transparent"
                    Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 2; color: tabBar.currentIndex === 2 ? "#4488dd" : "transparent" }
                }
            }
        }

        // ── Tab pages ─────────────────────────────────────────────────────────
        StackLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            currentIndex: tabBar.currentIndex

            // ── Tab 0: Download status ────────────────────────────────────────
            Item {
                ColumnLayout {
                    anchors { fill: parent; margins: 8 }
                    spacing: 6

                    // Info box
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: infoCol.implicitHeight + 20
                        color: "#242424"
                        border.color: "#3a3a3a"
                        border.width: 1

                        Column {
                            id: infoCol
                            anchors { fill: parent; margins: 10 }
                            spacing: 5

                            Text {
                                width: parent.width
                                text: item ? item.url.toString() : ""
                                color: "#909090"
                                font.pixelSize: 11
                                elide: Text.ElideMiddle
                            }

                            Row {
                                spacing: 0
                                Text { text: "Status"; color: "#707070"; font.pixelSize: 12; width: 110 }
                                Text {
                                    text: item ? item.status : "--"
                                    color: item ? root.statusColor(item.status) : "#b0b0b0"
                                    font.pixelSize: 12; font.bold: true
                                }
                            }

                            Item { width: 1; height: 4 }

                            Row {
                                spacing: 0
                                Text { text: "File size"; color: "#707070"; font.pixelSize: 12; width: 110 }
                                Text { text: item ? root.fmtBytes(item.totalBytes) : "--"; color: "#d0d0d0"; font.pixelSize: 12 }
                            }
                            Row {
                                spacing: 0
                                Text { text: "Downloaded"; color: "#707070"; font.pixelSize: 12; width: 110 }
                                Text {
                                    text: item ? root.fmtBytes(item.doneBytes) + " ( " + Math.round(item.progress * 100) + "% )" : "--"
                                    color: "#d0d0d0"; font.pixelSize: 12
                                }
                            }
                            Row {
                                spacing: 0
                                Text { text: "Transfer rate"; color: "#707070"; font.pixelSize: 12; width: 110 }
                                Text { text: item ? root.fmtSpeed(item.speed) : "--"; color: "#80c080"; font.pixelSize: 12 }
                            }
                            Row {
                                spacing: 0
                                Text { text: "Time left"; color: "#707070"; font.pixelSize: 12; width: 110 }
                                Text { text: item ? item.timeLeft : "--"; color: "#d0d0d0"; font.pixelSize: 12 }
                            }
                            Row {
                                spacing: 0
                                Text { text: "Resume capability"; color: "#707070"; font.pixelSize: 12; width: 110 }
                                Text {
                                    text: (item && item.resumeCapable) ? "Yes" : "No"
                                    color: (item && item.resumeCapable) ? "#44bb44" : "#e06060"
                                    font.pixelSize: 12
                                }
                            }
                        }
                    }

                    // Progress bar
                    Rectangle {
                        Layout.fillWidth: true
                        height: 22
                        color: "#333333"

                        Rectangle {
                            width: item ? item.progress * parent.width : 0
                            height: parent.height
                            color: "#44bb44"
                            Behavior on width { NumberAnimation { duration: 300 } }
                        }

                        Text {
                            anchors.centerIn: parent
                            text: item ? Math.round(item.progress * 100) + "%" : "0%"
                            color: "white"; font.pixelSize: 11; font.bold: true
                        }
                    }

                    // Buttons
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6

                        Button {
                            text: root.detailsVisible ? "« Hide details" : "» Show details"
                            flat: true
                            onClicked: root.detailsVisible = !root.detailsVisible
                        }

                        Item { Layout.fillWidth: true }

                        Button {
                            text: (item && item.status === "Paused") ? "Start" : "Pause"
                            enabled: item !== null && (item.status === "Downloading" || item.status === "Paused" || item.status === "Queued")
                            background: Rectangle { color: "#3a5a3a"; radius: 3 }
                            contentItem: Text { text: parent.text; color: "#d0d0d0"; font: parent.font; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                            onClicked: {
                                if (!item) return
                                if (item.status === "Downloading")  App.pauseDownload(item.id)
                                else                                App.resumeDownload(item.id)
                            }
                        }

                        Button {
                            text: "Cancel"
                            enabled: item !== null
                            background: Rectangle { color: "#5a3a3a"; radius: 3 }
                            contentItem: Text { text: parent.text; color: "#d0d0d0"; font: parent.font; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                            onClicked: root.close()
                        }
                    }

                    // Segment section label
                    Rectangle { Layout.fillWidth: true; height: 1; color: "#3a3a3a"; visible: root.detailsVisible }

                    Text {
                        Layout.fillWidth: true
                        visible: root.detailsVisible
                        text: "Start positions and download progress by connections"
                        color: "#707070"; font.pixelSize: 11
                        horizontalAlignment: Text.AlignHCenter
                    }

                    // Segment visualizer bar
                    Rectangle {
                        Layout.fillWidth: true
                        visible: root.detailsVisible
                        height: 18
                        color: "#333333"
                        clip: true

                        Repeater {
                            model: (item && item.segmentData) ? item.segmentData : []
                            delegate: Item {
                                readonly property var   seg:      modelData
                                readonly property real  total:    (item && item.totalBytes > 0) ? item.totalBytes : 1
                                readonly property real  segW:     (seg.endByte - seg.startByte + 1) / total * parent.width
                                readonly property real  segX:     seg.startByte / total * parent.width
                                readonly property real  fillW:    seg.received / Math.max(1, seg.endByte - seg.startByte + 1) * segW

                                x: segX
                                width: Math.max(1, segW)
                                height: parent.height

                                Rectangle { width: Math.max(0, fillW); height: parent.height; color: "#4488dd" }
                                Rectangle { anchors.right: parent.right; width: 1; height: parent.height; color: "#ffffff"; opacity: 0.3 }
                            }
                        }
                    }

                    // Segment table
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        visible: root.detailsVisible
                        color: "#1c1c1c"
                        border.color: "#3a3a3a"

                        ColumnLayout {
                            anchors.fill: parent
                            spacing: 0

                            // Header
                            Rectangle {
                                Layout.fillWidth: true
                                height: 24
                                color: "#2d2d2d"
                                Row {
                                    anchors { fill: parent; leftMargin: 4 }
                                    spacing: 0
                                    Text { width: 36;  text: "N.";          color: "#b0b0b0"; font.pixelSize: 11; font.bold: true; anchors.verticalCenter: parent.verticalCenter }
                                    Text { width: 120; text: "Downloaded";  color: "#b0b0b0"; font.pixelSize: 11; font.bold: true; anchors.verticalCenter: parent.verticalCenter }
                                    Text {             text: "Info";        color: "#b0b0b0"; font.pixelSize: 11; font.bold: true; anchors.verticalCenter: parent.verticalCenter }
                                }
                            }

                            ListView {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                clip: true
                                model: (item && item.segmentData) ? item.segmentData : []

                                delegate: Rectangle {
                                    width: ListView.view.width
                                    height: 26
                                    color: index % 2 === 0 ? "#1c1c1c" : "#222222"
                                    Row {
                                        anchors { fill: parent; leftMargin: 4 }
                                        spacing: 0
                                        Text { width: 36;  text: (index + 1) + ".";            color: "#d0d0d0"; font.pixelSize: 11; anchors.verticalCenter: parent.verticalCenter }
                                        Text { width: 120; text: root.fmtBytes(modelData.received); color: "#d0d0d0"; font.pixelSize: 11; anchors.verticalCenter: parent.verticalCenter }
                                        Text {             text: modelData.info ?? "";          color: "#a0c0a0"; font.pixelSize: 11; anchors.verticalCenter: parent.verticalCenter }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // ── Tab 1: Speed Limiter ──────────────────────────────────────────
            Item {
                ColumnLayout {
                    anchors { fill: parent; margins: 16 }
                    spacing: 12

                    Text {
                        text: "Limit transfer rate for this download"
                        color: "#ffffff"
                        font.pixelSize: 12
                        font.bold: true
                    }

                    CheckBox {
                        id: limitThisChk
                        text: "Enable per-download limit"
                        enabled: App.settings.globalSpeedLimitKBps === 0
                        onCheckedChanged: root.applyPerDownloadSpeed()
                    }

                    RowLayout {
                        spacing: 8
                        opacity: (limitThisChk.checked && limitThisChk.enabled) ? 1.0 : 0.5
                        Label { text: "Maximum:" }
                        TextField {
                            id: speedInput
                            placeholderText: "e.g. 100"
                            implicitWidth: 80
                            enabled: limitThisChk.enabled
                            validator: IntValidator { bottom: 0; top: 999999 }
                            onTextEdited: root.applyPerDownloadSpeed()
                        }
                        Label { text: "KB/s" }
                    }

                    Rectangle { Layout.fillWidth: true; height: 1; color: "#3a3a3a" }

                    Text {
                        text: App.settings.globalSpeedLimitKBps > 0
                            ? ("Global limit active: " + App.settings.globalSpeedLimitKBps + " KB/s")
                            : "No global limit set"
                        color: App.settings.globalSpeedLimitKBps > 0 ? "#ffcc88" : "#888888"
                        font.pixelSize: 11
                        wrapMode: Text.WordWrap
                    }

                    Text {
                        visible: App.settings.globalSpeedLimitKBps > 0
                        text: "Click the link below to adjust the global limit in Settings > General"
                        color: "#888888"
                        font.pixelSize: 10
                        wrapMode: Text.WordWrap
                    }

                    Rectangle {
                        visible: App.settings.globalSpeedLimitKBps > 0
                        width: settingsLink.implicitWidth + 8
                        height: 24
                        color: settingsMA.containsMouse ? "#2a4a7a" : "transparent"
                        radius: 3

                        Text {
                            id: settingsLink
                            anchors.centerIn: parent
                            text: "Open Settings"
                            color: "#4488dd"
                            font.pixelSize: 11
                            font.underline: true
                        }

                        MouseArea {
                            id: settingsMA
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root.close()
                                // Signal to open settings on General tab
                                // This will be handled by Main.qml
                            }
                        }
                    }

                    Item { Layout.fillHeight: true }
                }
            }

            // ── Tab 2: Options on completion ──────────────────────────────────
            Item {
                ColumnLayout {
                    anchors { fill: parent; margins: 16 }
                    spacing: 12

                    CheckBox { text: "Open file when done" }
                    CheckBox { text: "Open folder when done" }
                    CheckBox { text: "Shutdown computer when queue is done" }
                    Item { Layout.fillHeight: true }
                }
            }
        }
    }
}
