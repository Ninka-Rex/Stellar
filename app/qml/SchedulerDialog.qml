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
    title: "Scheduler"
    modality: Qt.ApplicationModal
    width: 820
    height: 620
    minimumWidth: 700
    minimumHeight: 520
    flags: Qt.Dialog | Qt.WindowCloseButtonHint
    color: "#1c1c1c"

    Material.primary: "#4488dd"
    Material.accent: "#4488dd"

    property var queueModel: App.queueModel
    property var selectedQueue: null
    property bool hasChanges: false

    function captureQueueState() {
        if (root.selectedQueue) {
            root.selectedQueue._appliedState = {
                name: root.selectedQueue.name,
                isDownloadQueue: root.selectedQueue.isDownloadQueue,
                startOnIDMStartup: root.selectedQueue.startOnIDMStartup,
                hasStartTime: root.selectedQueue.hasStartTime,
                startTime: root.selectedQueue.startTime,
                startOnce: root.selectedQueue.startOnce,
                startDaily: root.selectedQueue.startDaily,
                startDays: root.selectedQueue.startDays.slice(),
                hasStartAgainEvery: root.selectedQueue.hasStartAgainEvery,
                startAgainEveryHours: root.selectedQueue.startAgainEveryHours,
                startAgainEveryMins: root.selectedQueue.startAgainEveryMins,
                hasStopTime: root.selectedQueue.hasStopTime,
                stopTime: root.selectedQueue.stopTime,
                hasMaxRetries: root.selectedQueue.hasMaxRetries,
                maxRetries: root.selectedQueue.maxRetries,
                maxConcurrentDownloads: root.selectedQueue.maxConcurrentDownloads,
                openFileWhenDone: root.selectedQueue.openFileWhenDone,
                openFilePath: root.selectedQueue.openFilePath,
                exitIDMWhenDone: root.selectedQueue.exitIDMWhenDone,
                turnOffComputerWhenDone: root.selectedQueue.turnOffComputerWhenDone,
                forceProcessesToTerminate: root.selectedQueue.forceProcessesToTerminate,
                hasDownloadLimits: root.selectedQueue.hasDownloadLimits,
                downloadLimitMBytes: root.selectedQueue.downloadLimitMBytes,
                downloadLimitHours: root.selectedQueue.downloadLimitHours,
                warnBeforeStopping: root.selectedQueue.warnBeforeStopping
            }
        }
    }

    function arraysEqual(arr1, arr2) {
        if (arr1.length !== arr2.length) return false
        for (var i = 0; i < arr1.length; i++) {
            if (arr1[i] !== arr2[i]) return false
        }
        return true
    }

    function checkForChanges() {
        if (!root.selectedQueue || !root.selectedQueue._appliedState) {
            root.hasChanges = false
            return
        }

        var state = root.selectedQueue._appliedState
        root.hasChanges =
            state.name !== root.selectedQueue.name ||
            state.isDownloadQueue !== root.selectedQueue.isDownloadQueue ||
            state.startOnIDMStartup !== root.selectedQueue.startOnIDMStartup ||
            state.hasStartTime !== root.selectedQueue.hasStartTime ||
            state.startTime !== root.selectedQueue.startTime ||
            state.startOnce !== root.selectedQueue.startOnce ||
            state.startDaily !== root.selectedQueue.startDaily ||
            !arraysEqual(state.startDays, root.selectedQueue.startDays) ||
            state.hasStartAgainEvery !== root.selectedQueue.hasStartAgainEvery ||
            state.startAgainEveryHours !== root.selectedQueue.startAgainEveryHours ||
            state.startAgainEveryMins !== root.selectedQueue.startAgainEveryMins ||
            state.hasStopTime !== root.selectedQueue.hasStopTime ||
            state.stopTime !== root.selectedQueue.stopTime ||
            state.hasMaxRetries !== root.selectedQueue.hasMaxRetries ||
            state.maxRetries !== root.selectedQueue.maxRetries ||
            state.maxConcurrentDownloads !== root.selectedQueue.maxConcurrentDownloads ||
            state.openFileWhenDone !== root.selectedQueue.openFileWhenDone ||
            state.openFilePath !== root.selectedQueue.openFilePath ||
            state.exitIDMWhenDone !== root.selectedQueue.exitIDMWhenDone ||
            state.turnOffComputerWhenDone !== root.selectedQueue.turnOffComputerWhenDone ||
            state.forceProcessesToTerminate !== root.selectedQueue.forceProcessesToTerminate ||
            state.hasDownloadLimits !== root.selectedQueue.hasDownloadLimits ||
            state.downloadLimitMBytes !== root.selectedQueue.downloadLimitMBytes ||
            state.downloadLimitHours !== root.selectedQueue.downloadLimitHours ||
            state.warnBeforeStopping !== root.selectedQueue.warnBeforeStopping
    }

    // ── Root layout ───────────────────────────────────────────────────────────
    RowLayout {
        anchors { fill: parent; margins: 12 }
        spacing: 12

        // ── Left sidebar ──────────────────────────────────────────────────────
        ColumnLayout {
            Layout.preferredWidth: 180
            Layout.fillHeight: true
            spacing: 6

            Text {
                text: "Queues"
                color: "#d0d0d0"
                font.bold: true
                font.pixelSize: 12
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                color: "#252525"
                border.color: "#3a3a3a"
                border.width: 1
                radius: 0

                ListView {
                    id: queueList
                    anchors { fill: parent; margins: 4 }
                    model: root.queueModel
                    clip: true
                    spacing: 2

                    delegate: Rectangle {
                        width: queueList.width
                        height: 28
                        radius: 0
                        color: queueList.currentIndex === index ? "#1e3a6e" : "transparent"
                        border.color: queueList.currentIndex === index ? "#4488dd" : "transparent"
                        border.width: 1

                        Row {
                            anchors { verticalCenter: parent.verticalCenter; left: parent.left; leftMargin: 8 }
                            spacing: 6

                            Image {
                                width: 16; height: 16
                                sourceSize.width: 16; sourceSize.height: 16
                                fillMode: Image.PreserveAspectFit
                                anchors.verticalCenter: parent.verticalCenter
                                source: {
                                    if (model.queueId === "main-download") return "qrc:/qt/qml/com/stellar/app/app/qml/icons/main_queue.png"
                                    if (model.queueId === "main-sync") return "qrc:/qt/qml/com/stellar/app/app/qml/icons/synch_queue.png"
                                    return "qrc:/qt/qml/com/stellar/app/app/qml/icons/custom_queue.png"
                                }
                            }

                            Text {
                                text: model.queueName || ""
                                color: queueList.currentIndex === index ? "#88bbff" : "#d0d0d0"
                                font.pixelSize: 12
                                elide: Text.ElideRight
                                width: queueList.width - 50
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            onClicked: {
                                queueList.currentIndex = index
                                root.selectedQueue = queueModel.queueAt(index)
                                root.captureQueueState()
                                root.checkForChanges()
                            }
                        }
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 4

                Button {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 32
                    text: "New queue"
                    font.pixelSize: 11
                    background: Rectangle { color: parent.pressed ? "#2a2a3a" : parent.hovered ? "#2d2d3d" : "#252525"; radius: 0; border.color: "#3a3a3a"; border.width: 1 }
                    onClicked: newQueueDialog.open()
                }
                Button {
                    Layout.preferredWidth: 60
                    Layout.preferredHeight: 32
                    text: "Delete"
                    font.pixelSize: 11
                    background: Rectangle { color: parent.pressed ? "#2a2a3a" : parent.hovered ? "#2d2d3d" : "#252525"; radius: 0; border.color: "#3a3a3a"; border.width: 1 }
                    enabled: root.selectedQueue !== null && (root.selectedQueue ? root.selectedQueue.id !== "main-download" : false)
                    onClicked: {
                        if (root.selectedQueue) {
                            App.deleteQueue(root.selectedQueue.id)
                            root.selectedQueue = null
                            queueList.currentIndex = queueModel.rowCount() > 0 ? 0 : -1
                            if (queueList.currentIndex >= 0)
                                root.selectedQueue = queueModel.queueAt(0)
                        }
                    }
                }
            }
        }

        // ── Right pane ────────────────────────────────────────────────────────
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 0

            // Queue title
            Text {
                Layout.fillWidth: true
                Layout.preferredHeight: 32
                text: root.selectedQueue ? root.selectedQueue.name : ""
                color: "#4488dd"
                font.pixelSize: 15
                font.bold: true
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }

            // Tab bar (hidden for download-limits queue)
            RowLayout {
                Layout.fillWidth: true
                spacing: 0
                visible: root.selectedQueue ? root.selectedQueue.id !== "download-limits" : true

                Repeater {
                    id: tabRep
                    model: ["Schedule", "Files in the queue"]
                    delegate: Button {
                        Layout.preferredWidth: 160
                        text: modelData
                        font.pixelSize: 11
                        checkable: true
                        checked: tabView.currentIndex === index
                        background: Rectangle { color: parent.checked ? "#1e3a6e" : (parent.pressed ? "#2a2a3a" : parent.hovered ? "#2d2d3d" : "#252525"); radius: 0; border.color: parent.checked ? "#4488dd" : "#3a3a3a"; border.width: 1 }
                        onClicked: tabView.currentIndex = index
                    }
                }
                Item { Layout.fillWidth: true }
            }

            // Separator
            Rectangle {
                Layout.fillWidth: true
                height: 1
                color: "#3a3a3a"
                visible: root.selectedQueue ? root.selectedQueue.id !== "download-limits" : true
            }

            // Tab content (hidden for download-limits queue)
            StackLayout {
                id: tabView
                Layout.fillWidth: true
                Layout.fillHeight: true
                currentIndex: 0
                visible: root.selectedQueue ? root.selectedQueue.id !== "download-limits" : true

                // ── SCHEDULE TAB ──────────────────────────────────────────────
                ScrollView {
                    clip: true
                    ScrollBar.vertical.policy: ScrollBar.AsNeeded

                    ColumnLayout {
                        width: tabView.width
                        spacing: 10

                        // padding spacer
                        Item { height: 8 }

                        // Queue type
                        RowLayout {
                            Layout.leftMargin: 12
                            Layout.rightMargin: 12
                            spacing: 24

                            RadioButton {
                                text: "One-time downloading"
                                topPadding: 0
                                bottomPadding: 0
                                checked: root.selectedQueue ? root.selectedQueue.isDownloadQueue : true
                                onToggled: { if (checked && root.selectedQueue) { root.selectedQueue.isDownloadQueue = true; root.checkForChanges() } }
                            }
                            RadioButton {
                                text: "Periodic synchronization"
                                topPadding: 0
                                bottomPadding: 0
                                checked: root.selectedQueue ? !root.selectedQueue.isDownloadQueue : false
                                onToggled: { if (checked && root.selectedQueue) { root.selectedQueue.isDownloadQueue = false; root.checkForChanges() } }
                            }
                        }

                        CheckBox {
                            Layout.leftMargin: 12
                            text: "Start download on Stellar startup"
                            topPadding: 0
                            bottomPadding: 0
                            checked: root.selectedQueue ? root.selectedQueue.startOnIDMStartup : false
                            onToggled: { if (root.selectedQueue) { root.selectedQueue.startOnIDMStartup = checked; root.checkForChanges() } }
                        }

                        // Separator
                        Rectangle { Layout.fillWidth: true; Layout.leftMargin: 12; Layout.rightMargin: 12; height: 1; color: "#3a3a3a" }

                        // Start time row
                        RowLayout {
                            Layout.leftMargin: 12
                            spacing: 8

                            CheckBox {
                                id: hasStartTimeCb
                                text: "Start download at"
                                topPadding: 0
                                bottomPadding: 0
                                checked: root.selectedQueue ? root.selectedQueue.hasStartTime : false
                                onToggled: { if (root.selectedQueue) { root.selectedQueue.hasStartTime = checked; root.checkForChanges() } }
                            }
                            TextField {
                                id: startTimeField
                                Layout.preferredWidth: 130
                                placeholderText: "HH:MM:SS AM/PM"
                                text: root.selectedQueue ? root.selectedQueue.startTime : "11:00:00 PM"
                                enabled: hasStartTimeCb.checked && root.selectedQueue !== null
                                color: isValidTime(text) ? "#d0d0d0" : "#ff6666"

                                function isValidTime(t) {
                                    if (!t || t.length === 0) return false
                                    // Match HH:MM:SS AM/PM or HH:MM format
                                    var regex = /^([0-9]{1,2}):([0-9]{2})(:([0-9]{2}))?\s*(AM|PM|am|pm)?$/
                                    return regex.test(t.trim())
                                }

                                onTextChanged: {
                                    if (!root.selectedQueue) return
                                    // Update queue immediately if valid
                                    if (isValidTime(text)) {
                                        root.selectedQueue.startTime = text
                                    }
                                    // Always trigger change detection
                                    root.checkForChanges()
                                }
                            }
                            Text {
                                visible: !startTimeField.isValidTime(startTimeField.text) && startTimeField.text.length > 0
                                text: "Invalid format"
                                color: "#ff6666"
                                font.pixelSize: 10
                            }
                        }

                        // Once at / Daily radios (download queues only)
                        RowLayout {
                            Layout.leftMargin: 28
                            spacing: 24
                            visible: root.selectedQueue ? root.selectedQueue.isDownloadQueue : true
                            enabled: hasStartTimeCb.checked
                            opacity: enabled ? 1.0 : 0.5

                            RadioButton {
                                text: "Once at"
                                topPadding: 0
                                bottomPadding: 0
                                checked: root.selectedQueue ? root.selectedQueue.startOnce : true
                                onToggled: { if (checked && root.selectedQueue) { root.selectedQueue.startOnce = true; root.selectedQueue.startDaily = false; root.checkForChanges() } }
                            }
                            RadioButton {
                                id: dailyRadio
                                text: "Daily"
                                topPadding: 0
                                bottomPadding: 0
                                checked: root.selectedQueue ? root.selectedQueue.startDaily : false
                                onToggled: { if (checked && root.selectedQueue) { root.selectedQueue.startDaily = true; root.selectedQueue.startOnce = false; root.checkForChanges() } }
                            }
                        }

                        // Day checkboxes (download queues only)
                        GridLayout {
                            Layout.leftMargin: 40
                            columns: 3
                            columnSpacing: 4
                            rowSpacing: 2
                            visible: root.selectedQueue ? root.selectedQueue.isDownloadQueue : true
                            enabled: hasStartTimeCb.checked && dailyRadio.checked
                            opacity: enabled ? 1.0 : 0.4

                            Repeater {
                                model: ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
                                delegate: CheckBox {
                                    text: modelData
                                    topPadding: 0
                                    bottomPadding: 0
                                    font.pixelSize: 11
                                    checked: root.selectedQueue ? root.selectedQueue.startDays.indexOf(modelData) >= 0 : true
                                    onToggled: {
                                        if (!root.selectedQueue) return
                                        var days = root.selectedQueue.startDays.slice()
                                        if (checked && days.indexOf(modelData) < 0) days.push(modelData)
                                        else if (!checked) days = days.filter(function(d){ return d !== modelData })
                                        root.selectedQueue.startDays = days
                                        root.checkForChanges()
                                    }
                                }
                            }
                        }

                        // Start again every (sync only)
                        RowLayout {
                            Layout.leftMargin: 12
                            spacing: 8
                            visible: root.selectedQueue ? !root.selectedQueue.isDownloadQueue : false

                            CheckBox {
                                id: startAgainCb
                                text: "Start again every"
                                topPadding: 0
                                bottomPadding: 0
                                checked: root.selectedQueue ? root.selectedQueue.hasStartAgainEvery : false
                                onToggled: { if (root.selectedQueue) { root.selectedQueue.hasStartAgainEvery = checked; root.checkForChanges() } }
                            }
                            SpinBox {
                                from: 0; to: 23
                                value: root.selectedQueue ? root.selectedQueue.startAgainEveryHours : 2
                                enabled: startAgainCb.checked
                                onValueModified: { if (root.selectedQueue) { root.selectedQueue.startAgainEveryHours = value; root.checkForChanges() } }
                            }
                            Text { text: "hours"; color: "#d0d0d0" }
                            SpinBox {
                                from: 0; to: 59
                                value: root.selectedQueue ? root.selectedQueue.startAgainEveryMins : 0
                                enabled: startAgainCb.checked
                                onValueModified: { if (root.selectedQueue) { root.selectedQueue.startAgainEveryMins = value; root.checkForChanges() } }
                            }
                            Text { text: "min"; color: "#d0d0d0" }
                        }

                        // Day checkboxes for sync queues
                        GridLayout {
                            Layout.leftMargin: 40
                            columns: 3
                            columnSpacing: 4
                            rowSpacing: 2
                            visible: root.selectedQueue ? !root.selectedQueue.isDownloadQueue : false
                            enabled: startAgainCb.checked
                            opacity: enabled ? 1.0 : 0.4

                            Repeater {
                                model: ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
                                delegate: CheckBox {
                                    text: modelData
                                    topPadding: 0
                                    bottomPadding: 0
                                    font.pixelSize: 11
                                    checked: root.selectedQueue ? root.selectedQueue.startDays.indexOf(modelData) >= 0 : true
                                    onToggled: {
                                        if (!root.selectedQueue) return
                                        var days = root.selectedQueue.startDays.slice()
                                        if (checked && days.indexOf(modelData) < 0) days.push(modelData)
                                        else if (!checked) days = days.filter(function(d){ return d !== modelData })
                                        root.selectedQueue.startDays = days
                                        root.checkForChanges()
                                    }
                                }
                            }
                        }

                        Rectangle { Layout.fillWidth: true; Layout.leftMargin: 12; Layout.rightMargin: 12; height: 1; color: "#3a3a3a" }

                        // Stop time
                        RowLayout {
                            Layout.leftMargin: 12
                            spacing: 8

                            CheckBox {
                                id: hasStopTimeCb
                                text: "Stop download at"
                                topPadding: 0
                                bottomPadding: 0
                                checked: root.selectedQueue ? root.selectedQueue.hasStopTime : false
                                onToggled: { if (root.selectedQueue) { root.selectedQueue.hasStopTime = checked; root.checkForChanges() } }
                            }
                            TextField {
                                id: stopTimeField
                                Layout.preferredWidth: 130
                                placeholderText: "HH:MM:SS AM/PM"
                                text: root.selectedQueue ? root.selectedQueue.stopTime : "7:30:00 AM"
                                enabled: hasStopTimeCb.checked && root.selectedQueue !== null
                                color: isValidTime(text) ? "#d0d0d0" : "#ff6666"

                                function isValidTime(t) {
                                    if (!t || t.length === 0) return false
                                    // Match HH:MM:SS AM/PM or HH:MM format
                                    var regex = /^([0-9]{1,2}):([0-9]{2})(:([0-9]{2}))?\s*(AM|PM|am|pm)?$/
                                    return regex.test(t.trim())
                                }

                                onTextChanged: {
                                    if (!root.selectedQueue) return
                                    // Update queue immediately if valid
                                    if (isValidTime(text)) {
                                        root.selectedQueue.stopTime = text
                                    }
                                    // Always trigger change detection
                                    root.checkForChanges()
                                }
                            }
                            Text {
                                visible: !stopTimeField.isValidTime(stopTimeField.text) && stopTimeField.text.length > 0
                                text: "Invalid format"
                                color: "#ff6666"
                                font.pixelSize: 10
                            }
                        }

                        // Retries
                        RowLayout {
                            Layout.leftMargin: 12
                            spacing: 8

                            CheckBox {
                                id: retriesCb
                                text: "Number of retries for each file if downloading failed :"
                                topPadding: 0
                                bottomPadding: 0
                                checked: root.selectedQueue ? root.selectedQueue.hasMaxRetries : false
                                onToggled: { if (root.selectedQueue) { root.selectedQueue.hasMaxRetries = checked; root.checkForChanges() } }
                            }
                            SpinBox {
                                from: 1; to: 100
                                value: root.selectedQueue ? root.selectedQueue.maxRetries : 10
                                enabled: retriesCb.checked
                                onValueModified: { if (root.selectedQueue) { root.selectedQueue.maxRetries = value; root.checkForChanges() } }
                            }
                        }

                        Rectangle { Layout.fillWidth: true; Layout.leftMargin: 12; Layout.rightMargin: 12; height: 1; color: "#3a3a3a" }

                        // Open file when done
                        CheckBox {
                            id: openFileCb
                            Layout.leftMargin: 12
                            text: "Open the following file when done:"
                            topPadding: 0
                            bottomPadding: 0
                            checked: root.selectedQueue ? root.selectedQueue.openFileWhenDone : false
                            onToggled: { if (root.selectedQueue) { root.selectedQueue.openFileWhenDone = checked; root.checkForChanges() } }
                        }
                        RowLayout {
                            Layout.leftMargin: 28
                            Layout.rightMargin: 12
                            spacing: 6
                            enabled: openFileCb.checked
                            opacity: enabled ? 1.0 : 0.5

                            TextField {
                                Layout.fillWidth: true
                                text: root.selectedQueue ? root.selectedQueue.openFilePath : ""
                                onTextChanged: {
                                    if (root.selectedQueue) {
                                        root.selectedQueue.openFilePath = text
                                        root.checkForChanges()
                                    }
                                }
                            }
                            Button {
                                Layout.preferredWidth: 36
                                Layout.preferredHeight: 32
                                text: "..."
                                background: Rectangle { color: parent.pressed ? "#2a2a3a" : (parent.hovered ? "#2d2d3d" : "#252525"); radius: 0; border.color: "#3a3a3a"; border.width: 1 }
                                onClicked: fileDialog.open()
                            }
                        }

                        // Post-completion actions
                        CheckBox {
                            Layout.leftMargin: 12
                            text: "Exit Stellar when done"
                            topPadding: 0
                            bottomPadding: 0
                            checked: root.selectedQueue ? root.selectedQueue.exitIDMWhenDone : false
                            onToggled: { if (root.selectedQueue) { root.selectedQueue.exitIDMWhenDone = checked; root.checkForChanges() } }
                        }

                        ColumnLayout {
                            Layout.leftMargin: 12
                            spacing: 4

                            CheckBox {
                                id: turnOffCb
                                text: "Turn off computer when done"
                                topPadding: 0
                                bottomPadding: 0
                                checked: root.selectedQueue ? root.selectedQueue.turnOffComputerWhenDone : false
                                onToggled: { if (root.selectedQueue) { root.selectedQueue.turnOffComputerWhenDone = checked; root.checkForChanges() } }
                            }
                            CheckBox {
                                Layout.leftMargin: 20
                                text: "Force processes to terminate"
                                topPadding: 0
                                bottomPadding: 0
                                enabled: turnOffCb.checked
                                opacity: enabled ? 1.0 : 0.5
                                checked: root.selectedQueue ? root.selectedQueue.forceProcessesToTerminate : false
                                onToggled: { if (root.selectedQueue) { root.selectedQueue.forceProcessesToTerminate = checked; root.checkForChanges() } }
                            }
                        }

                        Item { height: 8 }
                    }
                }

                // ── FILES IN QUEUE TAB ────────────────────────────────────────
                ColumnLayout {
                    spacing: 8

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.topMargin: 8
                        Layout.leftMargin: 8
                        spacing: 8

                        Text { text: "Download"; color: "#d0d0d0" }
                        SpinBox {
                            from: 1; to: 10
                            value: root.selectedQueue ? root.selectedQueue.maxConcurrentDownloads : 1
                            onValueModified: { if (root.selectedQueue) { root.selectedQueue.maxConcurrentDownloads = value; root.checkForChanges() } }
                        }
                        Text { text: "files at the same time"; color: "#d0d0d0" }
                        Item { Layout.fillWidth: true }
                    }

                    // File table
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.leftMargin: 8
                        Layout.rightMargin: 8
                        color: "#1c1c1c"
                        border.color: "#3a3a3a"
                        border.width: 1
                        radius: 0

                        ColumnLayout {
                            anchors { fill: parent; margins: 0 }
                            spacing: 0

                            // Header
                            Rectangle {
                                Layout.fillWidth: true
                                height: 26
                                color: "#2d2d2d"

                                RowLayout {
                                    anchors { fill: parent; leftMargin: 8; rightMargin: 8 }
                                    spacing: 0

                                    Text { Layout.fillWidth: true; text: "File Name"; color: "#999"; font.pixelSize: 11; font.bold: true }
                                    Text { Layout.preferredWidth: 90; text: "Size"; color: "#999"; font.pixelSize: 11; font.bold: true }
                                    Text { Layout.preferredWidth: 80; text: "Status"; color: "#999"; font.pixelSize: 11; font.bold: true }
                                    Text { Layout.preferredWidth: 80; text: "Time Left"; color: "#999"; font.pixelSize: 11; font.bold: true }
                                }
                            }

                            Rectangle { Layout.fillWidth: true; height: 1; color: "#3a3a3a" }

                            // File list (filtered by queue)
                            ListView {
                                id: filesListView
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                model: App.downloadModel
                                clip: true
                                currentIndex: -1

                                delegate: Rectangle {
                                    width: ListView.view.width
                                    height: model.item && model.item.queueId === root.selectedQueue.id ? 40 : 0
                                    visible: model.item && model.item.queueId === root.selectedQueue.id
                                    color: filesListView.currentIndex === index ? "#1e3a6e" : (fileMouseArea.containsMouse ? "#2a2a3a" : (index % 2 === 0 ? "#1c1c1c" : "#202020"))
                                    border.color: filesListView.currentIndex === index ? "#4488dd" : "transparent"
                                    border.width: 1

                                    MouseArea {
                                        id: fileMouseArea
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        onClicked: filesListView.currentIndex = index
                                    }

                                    ColumnLayout {
                                        anchors { fill: parent; margins: 8 }
                                        spacing: 4

                                        Row {
                                            Layout.fillWidth: true
                                            spacing: 8

                                            Text {
                                                width: parent.width * 0.5
                                                text: model.item ? model.item.filename : ""
                                                color: filesListView.currentIndex === index ? "#88bbff" : "#d0d0d0"
                                                font.pixelSize: 11
                                                font.bold: filesListView.currentIndex === index
                                                elide: Text.ElideMiddle
                                                verticalAlignment: Text.AlignVCenter
                                            }

                                            Text {
                                                width: parent.width * 0.15
                                                text: {
                                                    if (!model.item || model.item.totalBytes <= 0) return "--"
                                                    var b = model.item.totalBytes
                                                    if (b < 1048576) return (b / 1024).toFixed(1) + " KB"
                                                    if (b < 1073741824) return (b / 1048576).toFixed(1) + " MB"
                                                    return (b / 1073741824).toFixed(2) + " GB"
                                                }
                                                color: filesListView.currentIndex === index ? "#aaccff" : "#b0b0b0"
                                                font.pixelSize: 10
                                                verticalAlignment: Text.AlignVCenter
                                            }

                                            Text {
                                                width: parent.width * 0.2
                                                text: model.item ? model.item.status : "--"
                                                color: model.item ? (model.item.status === "Downloading" ? "#66cc66" : model.item.status === "Completed" ? "#60c0e0" : filesListView.currentIndex === index ? "#aaccff" : "#b0b0b0") : "#b0b0b0"
                                                font.pixelSize: 10
                                                verticalAlignment: Text.AlignVCenter
                                            }

                                            Text {
                                                width: parent.width * 0.15
                                                text: model.item ? model.item.timeLeft : "--"
                                                color: filesListView.currentIndex === index ? "#aaccff" : "#b0b0b0"
                                                font.pixelSize: 10
                                                verticalAlignment: Text.AlignVCenter
                                            }
                                        }
                                    }
                                }
                            }

                            // Empty state message
                            Text {
                                Layout.alignment: Qt.AlignCenter
                                Layout.topMargin: 50
                                text: {
                                    if (!root.selectedQueue) return "No queue selected"
                                    var hasFiles = false
                                    for (var i = 0; i < App.downloadModel.rowCount(); i++) {
                                        var item = App.downloadModel.data(App.downloadModel.index(i, 0), Qt.UserRole + 2)
                                        if (item && item.queueId === root.selectedQueue.id) {
                                            hasFiles = true
                                            break
                                        }
                                    }
                                    return hasFiles ? "" : "No files in queue"
                                }
                                color: "#555"
                                font.pixelSize: 12
                                visible: text.length > 0
                            }
                        }
                    }

                    // Move buttons
                    RowLayout {
                        Layout.leftMargin: 8
                        Layout.bottomMargin: 8
                        spacing: 4

                        Button {
                            Layout.preferredWidth: 32
                            Layout.preferredHeight: 32
                            text: "↑"
                            enabled: filesListView.currentIndex > 0
                            background: Rectangle { color: parent.pressed ? "#2a2a3a" : (parent.hovered ? "#2d2d3d" : "#252525"); radius: 0; border.color: parent.enabled ? "#4488dd" : "#3a3a3a"; border.width: 1; opacity: parent.enabled ? 1.0 : 0.5 }
                            onClicked: {
                                if (filesListView.currentIndex > 0) {
                                    var item = App.downloadModel.data(App.downloadModel.index(filesListView.currentIndex, 0), Qt.UserRole + 2)
                                    if (item) App.moveUpInQueue(item.id)
                                    filesListView.currentIndex = filesListView.currentIndex - 1
                                }
                            }
                        }
                        Button {
                            Layout.preferredWidth: 32
                            Layout.preferredHeight: 32
                            text: "↓"
                            enabled: filesListView.currentIndex >= 0 && filesListView.currentIndex < App.downloadModel.rowCount() - 1
                            background: Rectangle { color: parent.pressed ? "#2a2a3a" : (parent.hovered ? "#2d2d3d" : "#252525"); radius: 0; border.color: parent.enabled ? "#4488dd" : "#3a3a3a"; border.width: 1; opacity: parent.enabled ? 1.0 : 0.5 }
                            onClicked: {
                                if (filesListView.currentIndex >= 0) {
                                    var item = App.downloadModel.data(App.downloadModel.index(filesListView.currentIndex, 0), Qt.UserRole + 2)
                                    if (item) App.moveDownInQueue(item.id)
                                    filesListView.currentIndex = filesListView.currentIndex + 1
                                }
                            }
                        }
                        Button {
                            Layout.preferredWidth: 70
                            Layout.preferredHeight: 32
                            text: "Delete"
                            enabled: filesListView.currentIndex >= 0
                            background: Rectangle { color: parent.pressed ? "#2a2a3a" : (parent.hovered ? "#2d2d3d" : "#252525"); radius: 0; border.color: parent.enabled ? "#ff6666" : "#3a3a3a"; border.width: 1; opacity: parent.enabled ? 1.0 : 0.5 }
                            onClicked: {
                                if (filesListView.currentIndex >= 0) {
                                    var item = App.downloadModel.data(App.downloadModel.index(filesListView.currentIndex, 0), Qt.UserRole + 2)
                                    if (item) App.setDownloadQueue(item.id, "")
                                    filesListView.currentIndex = -1
                                }
                            }
                        }
                        Item { Layout.fillWidth: true }
                    }
                }

                // ── DOWNLOAD LIMITS TAB ───────────────────────────────────────
                ColumnLayout {
                    spacing: 12

                    Item { height: 4 }

                    CheckBox {
                        id: limitsEnabledCb
                        Layout.leftMargin: 12
                        text: "Download limits"
                        topPadding: 0
                        bottomPadding: 0
                        checked: root.selectedQueue ? root.selectedQueue.hasDownloadLimits : false
                        onToggled: { if (root.selectedQueue) { root.selectedQueue.hasDownloadLimits = checked; root.checkForChanges() } }
                    }

                    RowLayout {
                        Layout.leftMargin: 28
                        spacing: 8
                        enabled: limitsEnabledCb.checked
                        opacity: enabled ? 1.0 : 0.5

                        Text { text: "Download no more than"; color: "#d0d0d0" }
                        SpinBox {
                            from: 1; to: 100000
                            value: root.selectedQueue ? root.selectedQueue.downloadLimitMBytes : 200
                            onValueModified: { if (root.selectedQueue) { root.selectedQueue.downloadLimitMBytes = value; root.checkForChanges() } }
                        }
                        Text { text: "MBytes"; color: "#d0d0d0" }
                        Text { text: "every"; color: "#d0d0d0" }
                        SpinBox {
                            from: 1; to: 24
                            value: root.selectedQueue ? root.selectedQueue.downloadLimitHours : 5
                            onValueModified: { if (root.selectedQueue) { root.selectedQueue.downloadLimitHours = value; root.checkForChanges() } }
                        }
                        Text { text: "hours"; color: "#d0d0d0" }
                        Item { Layout.fillWidth: true }
                    }

                    CheckBox {
                        Layout.leftMargin: 12
                        text: "Show warning before stopping downloads"
                        topPadding: 0
                        bottomPadding: 0
                        checked: root.selectedQueue ? root.selectedQueue.warnBeforeStopping : true
                        onToggled: { if (root.selectedQueue) { root.selectedQueue.warnBeforeStopping = checked; root.checkForChanges() } }
                    }

                    Item { Layout.fillHeight: true }
                }
            }

            // Download Limits view (for download-limits queue)
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 12
                visible: root.selectedQueue ? root.selectedQueue.id === "download-limits" : false

                Item { height: 4 }

                CheckBox {
                    id: dlLimitsEnabledCb
                    Layout.leftMargin: 12
                    text: "Download limits"
                    topPadding: 0
                    bottomPadding: 0
                    checked: root.selectedQueue ? root.selectedQueue.hasDownloadLimits : false
                    onToggled: { if (root.selectedQueue) root.selectedQueue.hasDownloadLimits = checked }
                }

                RowLayout {
                    Layout.leftMargin: 28
                    spacing: 8
                    enabled: dlLimitsEnabledCb.checked
                    opacity: enabled ? 1.0 : 0.5

                    Text { text: "Download no more than"; color: "#d0d0d0" }
                    SpinBox {
                        from: 1; to: 100000
                        value: root.selectedQueue ? root.selectedQueue.downloadLimitMBytes : 200
                        onValueModified: { if (root.selectedQueue) root.selectedQueue.downloadLimitMBytes = value }
                    }
                    Text { text: "MBytes"; color: "#d0d0d0" }
                    Text { text: "every"; color: "#d0d0d0" }
                    SpinBox {
                        from: 1; to: 24
                        value: root.selectedQueue ? root.selectedQueue.downloadLimitHours : 5
                        onValueModified: { if (root.selectedQueue) root.selectedQueue.downloadLimitHours = value }
                    }
                    Text { text: "hours"; color: "#d0d0d0" }
                    Item { Layout.fillWidth: true }
                }

                CheckBox {
                    Layout.leftMargin: 12
                    text: "Show warning before stopping downloads"
                    topPadding: 0
                    bottomPadding: 0
                    checked: root.selectedQueue ? root.selectedQueue.warnBeforeStopping : true
                    onToggled: { if (root.selectedQueue) root.selectedQueue.warnBeforeStopping = checked }
                }

                Item { Layout.fillHeight: true }
            }

            // Separator
            Rectangle { Layout.fillWidth: true; height: 1; color: "#3a3a3a"; Layout.topMargin: 4 }

            // Bottom buttons
            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: 8
                spacing: 8

                Button {
                    text: "Start now"
                    Layout.preferredWidth: 90
                    Layout.preferredHeight: 32
                    background: Rectangle { color: parent.pressed ? "#2a2a3a" : (parent.hovered ? "#2d2d3d" : "#252525"); radius: 0; border.color: "#3a3a3a"; border.width: 1 }
                    enabled: root.selectedQueue !== null
                    onClicked: { if (root.selectedQueue) App.startQueue(root.selectedQueue.id) }
                }
                Button {
                    text: "Stop"
                    Layout.preferredWidth: 90
                    Layout.preferredHeight: 32
                    background: Rectangle { color: parent.pressed ? "#2a2a3a" : (parent.hovered ? "#2d2d3d" : "#252525"); radius: 0; border.color: "#3a3a3a"; border.width: 1 }
                    enabled: root.selectedQueue !== null
                    onClicked: { if (root.selectedQueue) App.stopQueue(root.selectedQueue.id) }
                }

                Item { Layout.fillWidth: true }

                Button {
                    text: "Apply"
                    Layout.preferredWidth: 80
                    Layout.preferredHeight: 32
                    enabled: root.hasChanges
                    opacity: enabled ? 1.0 : 0.5
                    background: Rectangle { color: parent.pressed ? "#2a2a3a" : (parent.hovered ? "#2d2d3d" : "#252525"); radius: 0; border.color: parent.enabled ? "#3a3a3a" : "#666666"; border.width: 1 }
                    onClicked: {
                        App.saveQueues()
                        root.captureQueueState()
                        root.hasChanges = false
                    }
                }
                Button {
                    text: "Close"
                    Layout.preferredWidth: 80
                    Layout.preferredHeight: 32
                    background: Rectangle { color: parent.pressed ? "#2a2a3a" : (parent.hovered ? "#2d2d3d" : "#252525"); radius: 0; border.color: "#3a3a3a"; border.width: 1 }
                    onClicked: root.close()
                }
            }
        }
    }

    function confirmNewQueue() {
        var name = newQueueNameField.text.trim()
        if (name.length > 0) {
            App.createQueue(name)
            newQueueNameField.text = ""
            newQueueDialog.close()
            var last = queueModel.rowCount() - 1
            if (last >= 0) {
                queueList.currentIndex = last
                root.selectedQueue = queueModel.queueAt(last)
            }
        }
    }

    // Monitor selectedQueue for changes
    Connections {
        target: root.selectedQueue
        function onNameChanged() { root.checkForChanges() }
        function onIsDownloadQueueChanged() { root.checkForChanges() }
        function onStartOnIDMStartupChanged() { root.checkForChanges() }
        function onHasStartTimeChanged() { root.checkForChanges() }
        function onStartTimeChanged() { root.checkForChanges() }
        function onStartOnceChanged() { root.checkForChanges() }
        function onStartDailyChanged() { root.checkForChanges() }
        function onStartDaysChanged() { root.checkForChanges() }
        function onHasStartAgainEveryChanged() { root.checkForChanges() }
        function onStartAgainEveryHoursChanged() { root.checkForChanges() }
        function onStartAgainEveryMinsChanged() { root.checkForChanges() }
        function onHasStopTimeChanged() { root.checkForChanges() }
        function onStopTimeChanged() { root.checkForChanges() }
        function onHasMaxRetriesChanged() { root.checkForChanges() }
        function onMaxRetriesChanged() { root.checkForChanges() }
        function onMaxConcurrentDownloadsChanged() { root.checkForChanges() }
        function onOpenFileWhenDoneChanged() { root.checkForChanges() }
        function onOpenFilePathChanged() { root.checkForChanges() }
        function onExitIDMWhenDoneChanged() { root.checkForChanges() }
        function onTurnOffComputerWhenDoneChanged() { root.checkForChanges() }
        function onForceProcessesToTerminateChanged() { root.checkForChanges() }
        function onHasDownloadLimitsChanged() { root.checkForChanges() }
        function onDownloadLimitMBytesChanged() { root.checkForChanges() }
        function onDownloadLimitHoursChanged() { root.checkForChanges() }
        function onWarnBeforeStoppingChanged() { root.checkForChanges() }
    }

    // ── New Queue Dialog ──────────────────────────────────────────────────────
    Dialog {
        id: newQueueDialog
        title: "New Queue"
        modal: true
        anchors.centerIn: Overlay.overlay
        width: 420

        Material.primary: "#4488dd"
        Material.accent: "#4488dd"

        background: Rectangle {
            color: "#1c1c1c"
            border.color: "#3a3a3a"
            border.width: 1
            radius: 0
        }

        contentItem: Rectangle {
            color: "#1c1c1c"
            ColumnLayout {
                anchors { fill: parent; margins: 16 }
                spacing: 12

                Text {
                    Layout.fillWidth: true
                    text: "Enter a name for the new queue that will be displayed in the list of queues"
                    color: "#d0d0d0"
                    wrapMode: Text.Wrap
                    font.pixelSize: 12
                }

                Rectangle {
                    Layout.fillWidth: true
                    height: 32
                    color: "#252525"
                    border.color: "#3a3a3a"
                    border.width: 1
                    radius: 0

                    TextInput {
                        id: newQueueNameField
                        anchors { fill: parent; leftMargin: 8; rightMargin: 8 }
                        verticalAlignment: TextInput.AlignVCenter
                        color: "#d0d0d0"
                        selectionColor: "#4488dd"
                        Keys.onReturnPressed: confirmNewQueue()

                        Text {
                            text: "Queue name"
                            color: "#666"
                            anchors { left: parent.left; leftMargin: 2; verticalCenter: parent.verticalCenter }
                            visible: newQueueNameField.length === 0
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    Item { Layout.fillWidth: true }
                    Button {
                        text: "OK"
                        Layout.preferredWidth: 80
                        Layout.preferredHeight: 32
                        background: Rectangle { color: parent.pressed ? "#2a2a3a" : (parent.hovered ? "#2d2d3d" : "#252525"); radius: 0; border.color: "#3a3a3a"; border.width: 1 }
                        onClicked: confirmNewQueue()
                    }
                    Button {
                        text: "Cancel"
                        Layout.preferredWidth: 80
                        Layout.preferredHeight: 32
                        background: Rectangle { color: parent.pressed ? "#2a2a3a" : (parent.hovered ? "#2d2d3d" : "#252525"); radius: 0; border.color: "#3a3a3a"; border.width: 1 }
                        onClicked: { newQueueNameField.text = ""; newQueueDialog.close() }
                    }
                }
            }
        }
    }

    // ── File picker ───────────────────────────────────────────────────────────
    FileDialog {
        id: fileDialog
        title: "Select file to open when done"
        onAccepted: {
            if (root.selectedQueue)
                root.selectedQueue.openFilePath = selectedFile.toString().replace("file:///", "")
        }
    }

    Component.onCompleted: {
        if (queueModel) {
            // Default to main-download queue
            var mainIdx = -1
            for (var i = 0; i < queueModel.rowCount(); i++) {
                var q = queueModel.queueAt(i)
                if (q && q.id === "main-download") {
                    mainIdx = i
                    break
                }
            }
            if (mainIdx >= 0) {
                queueList.currentIndex = mainIdx
                root.selectedQueue = queueModel.queueAt(mainIdx)
            } else if (queueModel.rowCount() > 0) {
                queueList.currentIndex = 0
                root.selectedQueue = queueModel.queueAt(0)
            }
        }
        root.captureQueueState()
        root.hasChanges = false
    }
}
