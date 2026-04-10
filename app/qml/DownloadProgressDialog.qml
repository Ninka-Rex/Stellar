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
    property bool   openFileWhenDone: false
    property bool   openFolderWhenDone: false
    property bool   shutdownWhenDone: false
    property bool   completionHandled: false

    width: 620
    height: 520
    minimumWidth: 440
    minimumHeight: 240

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

    onVisibleChanged: {
        if (visible) {
            raise()
            requestActivate()
        }
    }

    onItemChanged: {
        _updatingSpeedUI = true
        openFileWhenDone = false
        openFolderWhenDone = false
        shutdownWhenDone = false
        completionHandled = item && item.status === "Completed"
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
            minimumHeight = 360
            height = 520
        } else {
            minimumHeight = 240
            maximumHeight = 270
            height = 270
        }
    }

    color: "#1a1a1a"

    title: {
        if (!item) return "Download"
        var pct = item.progress > 0 ? Math.round(item.progress * 100) + "% " : ""
        return pct + item.filename
    }

    Material.theme: Material.Dark
    Material.background: "#1a1a1a"
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
        if (s === "Downloading") return "#44cc55"
        if (s === "Paused")      return "#ddbb44"
        if (s === "Completed")   return "#44aadd"
        if (s === "Error")       return "#dd5555"
        return "#909090"
    }

    function statusLabel() {
        if (!item)
            return "--"
        if (item.status === "Paused" && item.progress > 0)
            return Math.round(item.progress * 100) + "%"
        return item.status
    }

    function handleCompletion() {
        if (!item || completionHandled || item.status !== "Completed")
            return
        completionHandled = true
        if (openFileWhenDone)
            App.openFile(item.id)
        if (openFolderWhenDone)
            App.openFolderSelectFile(item.id)
        if (shutdownWhenDone)
            App.shutdownComputer()
    }

    Connections {
        target: item
        function onStatusChanged() { root.handleCompletion() }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // ── Tab bar ──────────────────────────────────────────────────────────
        Rectangle {
            Layout.fillWidth: true
            height: 34
            color: "#252525"

            // Bottom separator
            Rectangle {
                anchors.bottom: parent.bottom
                width: parent.width; height: 1
                color: "#111"
            }

            Row {
                anchors.fill: parent
                spacing: 0

                Repeater {
                    model: ["Download status", "Speed Limiter", "Options on completion"]
                    delegate: Rectangle {
                        width: tabLbl.implicitWidth + 28
                        height: parent.height
                        color: tabStack.currentIndex === index
                               ? "#1a1a1a"
                               : (tabHover.containsMouse ? "#2e2e2e" : "transparent")

                        Text {
                            id: tabLbl
                            anchors.centerIn: parent
                            text: modelData
                            color: tabStack.currentIndex === index ? "#ffffff" : "#909090"
                            font.pixelSize: 12
                        }

                        // Active underline
                        Rectangle {
                            anchors.bottom: parent.bottom
                            width: parent.width; height: 2
                            color: tabStack.currentIndex === index ? "#4488dd" : "transparent"
                        }

                        MouseArea {
                            id: tabHover
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: tabStack.currentIndex = index
                        }
                    }
                }
            }
        }

        // ── Tab pages ─────────────────────────────────────────────────────────
        StackLayout {
            id: tabStack
            Layout.fillWidth: true
            Layout.fillHeight: true

            // ── Tab 0: Download status ────────────────────────────────────────
            Item {
                ColumnLayout {
                    anchors { fill: parent; margins: 10; bottomMargin: 8 }
                    spacing: 7

                    // ── Info box ─────────────────────────────────────────────
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: infoCol.implicitHeight + 16
                        color: "#212121"
                        border.color: "#303030"
                        radius: 3

                        Column {
                            id: infoCol
                            anchors { fill: parent; margins: 10 }
                            spacing: 0

                            // URL row
                            Text {
                                width: parent.width
                                text: item ? item.url.toString() : ""
                                color: "#6688bb"
                                font.pixelSize: 13
                                elide: Text.ElideMiddle
                                bottomPadding: 7
                            }

                            // Separator
                            Item { width: 1; height: 5 }
                            Rectangle { width: parent.width; height: 1; color: "#2e2e2e" }
                            Item { width: 1; height: 6 }

                            // Status row (with colored dot)
                            Row {
                                spacing: 0
                                width: parent.width
                                height: 22

                                Text {
                                    text: "Status"
                                    color: "#666"
                                    font.pixelSize: 12
                                    width: 120
                                    anchors.verticalCenter: parent.verticalCenter
                                }

                                Text {
                                    text: root.statusLabel()
                                    color: item ? root.statusColor(item.status) : "#b0b0b0"
                                    font.pixelSize: 12
                                    font.bold: true
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                            }

                            Item { width: 1; height: 4 }

                            // Data rows — individual bindings so they react to item changes
                            Row {
                                spacing: 0; width: parent.width; height: 20
                                Text { text: "File size";  color: "#666"; font.pixelSize: 12; width: 120 }
                                Text { text: item ? root.fmtBytes(item.totalBytes) : "--"; color: "#c8c8c8"; font.pixelSize: 12 }
                            }
                            Row {
                                spacing: 0; width: parent.width; height: 20
                                Text { text: "Downloaded"; color: "#666"; font.pixelSize: 12; width: 120 }
                                Text {
                                    text: item ? root.fmtBytes(item.doneBytes) + "  ( " + Math.round(item.progress * 100) + "% )" : "--"
                                    color: "#c8c8c8"; font.pixelSize: 12
                                }
                            }
                            Row {
                                spacing: 0; width: parent.width; height: 20
                                Text { text: "Transfer rate"; color: "#666"; font.pixelSize: 12; width: 120 }
                                Text {
                                    text: {
                                        if (!item) return "--"
                                        var speed = root.fmtSpeed(item.speed)
                                        if (App.settings.globalSpeedLimitKBps > 0) {
                                            speed += " [" + App.settings.globalSpeedLimitKBps + " KBps limit]"
                                        }
                                        return speed
                                    }
                                    color: "#55cc66"
                                    font.pixelSize: 12
                                }
                            }
                            Row {
                                spacing: 0; width: parent.width; height: 20
                                Text { text: "Time left";  color: "#666"; font.pixelSize: 12; width: 120 }
                                Text { text: item ? item.timeLeft : "--"; color: "#c8c8c8"; font.pixelSize: 12 }
                            }
                            Row {
                                spacing: 0; width: parent.width; height: 20
                                Text { text: "Resume capability"; color: "#666"; font.pixelSize: 12; width: 120 }
                                Text {
                                    text: (item && item.resumeCapable) ? "Yes" : "No"
                                    color: (item && item.resumeCapable) ? "#55cc66" : "#dd5555"
                                    font.pixelSize: 12
                                }
                            }
                        }
                    }

                    // ── Progress bar ─────────────────────────────────────────
                    Rectangle {
                        Layout.fillWidth: true
                        height: 24
                        color: "#2a2a2a"
                        radius: 3
                        clip: true

                        // Fill
                        Rectangle {
                            width: item ? Math.max(0, item.progress * parent.width) : 0
                            height: parent.height
                            color: "#33bb44"
                            radius: 3
                            Behavior on width { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
                        }

                        Text {
                            anchors.centerIn: parent
                            text: item ? Math.round(item.progress * 100) + "%" : "0%"
                            color: "white"
                            font.pixelSize: 11
                            font.bold: true
                        }
                    }

                    // ── Buttons row ───────────────────────────────────────────
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        // Hide/Show details
                        Rectangle {
                            height: 26
                            width: hideDetailsLabel.implicitWidth + 20
                            color: hideDetailsMa.containsMouse ? "#303030" : "transparent"
                            border.color: hideDetailsMa.containsMouse ? "#484848" : "#383838"
                            radius: 3

                            Text {
                                id: hideDetailsLabel
                                anchors.centerIn: parent
                                text: root.detailsVisible ? "« Hide details" : "» Show details"
                                color: "#aaaaaa"
                                font.pixelSize: 12
                            }

                            MouseArea {
                                id: hideDetailsMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.detailsVisible = !root.detailsVisible
                            }
                        }

                        Item { Layout.fillWidth: true }

                        // Pause / Start
                        DlgButton {
                            text: (item && item.status === "Paused") ? "Start" : "Pause"
                            enabled: item !== null && (item.status === "Downloading" || item.status === "Paused" || item.status === "Queued")
                            opacity: enabled ? 1.0 : 0.4
                            onClicked: {
                                if (!item) return
                                if (item.status === "Downloading") App.pauseDownload(item.id)
                                else App.resumeDownload(item.id)
                            }
                        }

                        // Cancel
                        DlgButton {
                            text: "Cancel"
                            onClicked: root.close()
                        }
                    }

                    // ── Details section ───────────────────────────────────────
                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        visible: root.detailsVisible
                        spacing: 4

                        // Label
                        Rectangle {
                            Layout.fillWidth: true
                            height: 20
                            color: "#1e1e1e"

                            Rectangle { width: parent.width; height: 1; color: "#2e2e2e" }

                            Text {
                                anchors.centerIn: parent
                                text: "Start positions and download progress by connections"
                                color: "#606060"
                                font.pixelSize: 11
                            }
                        }

                        // Segment visualizer
                        Rectangle {
                            Layout.fillWidth: true
                            height: 20
                            color: "#252525"
                            border.color: "#303030"
                            radius: 2
                            clip: true

                            Repeater {
                                model: (item && item.segmentData) ? item.segmentData : []
                                delegate: Item {
                                    readonly property var  seg:   modelData
                                    readonly property real total: (item && item.totalBytes > 0) ? item.totalBytes : 1
                                    readonly property real segW:  (seg.endByte - seg.startByte + 1) / total * parent.width
                                    readonly property real segX:  seg.startByte / total * parent.width
                                    readonly property real fillW: seg.received / Math.max(1, seg.endByte - seg.startByte + 1) * segW

                                    x: segX
                                    width: Math.max(1, segW)
                                    height: parent.height

                                    Rectangle {
                                        width: Math.max(0, fillW); height: parent.height
                                        gradient: Gradient {
                                            orientation: Gradient.Vertical
                                            GradientStop { position: 0.0; color: "#4499dd" }
                                            GradientStop { position: 1.0; color: "#2266aa" }
                                        }
                                    }
                                    // Segment divider
                                    Rectangle {
                                        anchors.right: parent.right
                                        width: 1; height: parent.height
                                        color: "#ffffff"; opacity: 0.15
                                    }
                                }
                            }
                        }

                        // Segment table
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            color: "#1c1c1c"
                            border.color: "#303030"
                            radius: 2
                            clip: true

                            ColumnLayout {
                                anchors.fill: parent
                                spacing: 0

                                // Table header
                                Rectangle {
                                    Layout.fillWidth: true
                                    height: 22
                                    color: "#272727"

                                    Rectangle {
                                        anchors.bottom: parent.bottom
                                        width: parent.width; height: 1
                                        color: "#333"
                                    }

                                    Row {
                                        anchors { fill: parent; leftMargin: 8 }
                                        spacing: 0
                                        Text { width: 34;  text: "N.";         color: "#888"; font.pixelSize: 11; font.bold: true; anchors.verticalCenter: parent.verticalCenter }
                                        Text { width: 110; text: "Downloaded"; color: "#888"; font.pixelSize: 11; font.bold: true; anchors.verticalCenter: parent.verticalCenter }
                                        Text {             text: "Info";       color: "#888"; font.pixelSize: 11; font.bold: true; anchors.verticalCenter: parent.verticalCenter }
                                    }
                                }

                                ListView {
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    clip: true
                                    model: (item && item.segmentData) ? item.segmentData : []
                                    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                                    delegate: Rectangle {
                                        width: ListView.view.width
                                        height: 24
                                        color: index % 2 === 0 ? "#1c1c1c" : "#202020"

                                        Row {
                                            anchors { fill: parent; leftMargin: 8 }
                                            spacing: 0
                                            Text { width: 34;  text: (index + 1) + ".";               color: "#999"; font.pixelSize: 11; anchors.verticalCenter: parent.verticalCenter }
                                            Text { width: 110; text: root.fmtBytes(modelData.received); color: "#cccccc"; font.pixelSize: 11; anchors.verticalCenter: parent.verticalCenter }
                                            Text {             text: modelData.info ?? "";              color: "#6aaa6a"; font.pixelSize: 11; anchors.verticalCenter: parent.verticalCenter }
                                        }
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
                        color: "#cccccc"
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

                    Rectangle { Layout.fillWidth: true; height: 1; color: "#303030" }

                    Text {
                        text: App.settings.globalSpeedLimitKBps > 0
                            ? ("Global limit active: " + App.settings.globalSpeedLimitKBps + " KB/s")
                            : "No global limit set"
                        color: App.settings.globalSpeedLimitKBps > 0 ? "#ffcc88" : "#666"
                        font.pixelSize: 11
                        wrapMode: Text.WordWrap
                    }

                    Item { Layout.fillHeight: true }
                }
            }

            // ── Tab 2: Options on completion ──────────────────────────────────
            Item {
                ColumnLayout {
                    anchors { fill: parent; margins: 16 }
                    spacing: 12
                    Text {
                        text: "Options On Completion"
                        color: "#cccccc"
                        font.pixelSize: 12
                        font.bold: true
                    }
                    CheckBox {
                        text: "Open file when done"
                        checked: root.openFileWhenDone
                        topPadding: 0
                        bottomPadding: 0
                        onToggled: root.openFileWhenDone = checked
                    }
                    CheckBox {
                        text: "Open folder when done"
                        checked: root.openFolderWhenDone
                        topPadding: 0
                        bottomPadding: 0
                        onToggled: root.openFolderWhenDone = checked
                    }
                    CheckBox {
                        text: "Shutdown computer when done"
                        checked: root.shutdownWhenDone
                        topPadding: 0
                        bottomPadding: 0
                        onToggled: root.shutdownWhenDone = checked
                    }
                    Text {
                        Layout.fillWidth: true
                        text: "These options are temporary for this download only and start unchecked each time."
                        color: "#909090"
                        font.pixelSize: 11
                        wrapMode: Text.WordWrap
                    }
                    Item { Layout.fillHeight: true }
                }
            }
        }
    }
}
