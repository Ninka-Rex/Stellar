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
    flags: Qt.Window | Qt.WindowTitleHint | Qt.WindowSystemMenuHint | Qt.WindowCloseButtonHint
    color: "#1c1c1c"

    Material.primary: "#4488dd"
    Material.accent: "#4488dd"

    property var queueModel: App.queueModel
    property var selectedQueue: null
    property bool hasChanges: false

    function parseScheduleTime(value, fallbackHour, fallbackMinute, fallbackAmPm) {
        var match = /^([0-9]{1,2}):([0-9]{2})(?::([0-9]{2}))?\s*(AM|PM|am|pm)?$/.exec((value || "").trim())
        if (!match) {
            return {
                hour: String(fallbackHour),
                minute: fallbackMinute < 10 ? "0" + fallbackMinute : String(fallbackMinute),
                amPm: fallbackAmPm
            }
        }
        return {
            hour: String(parseInt(match[1], 10) || fallbackHour),
            minute: match[2],
            amPm: (match[4] || fallbackAmPm).toUpperCase()
        }
    }

    function buildScheduleTime(hourText, minuteText, amPm) {
        var hour = parseInt(hourText, 10)
        var minute = parseInt(minuteText, 10)
        if (isNaN(hour) || hour < 1 || hour > 12)
            hour = 12
        if (isNaN(minute) || minute < 0 || minute > 59)
            minute = 0
        return String(hour) + ":" + (minute < 10 ? "0" + minute : String(minute)) + ":00 " + amPm
    }

    function updateSelectedQueueTime(which, hourText, minuteText, amPm) {
        if (!root.selectedQueue)
            return
        root.selectedQueue[which] = buildScheduleTime(hourText, minuteText, amPm)
        root.checkForChanges()
    }

    function shortDayName(dayName) {
        return dayName.slice(0, 3)
    }

    function toggleSelectedDay(dayName, enabled) {
        if (!root.selectedQueue)
            return
        var days = root.selectedQueue.startDays.slice()
        var index = days.indexOf(dayName)
        if (enabled && index < 0)
            days.push(dayName)
        else if (!enabled && index >= 0)
            days.splice(index, 1)
        root.selectedQueue.startDays = days
        root.checkForChanges()
    }

    function captureQueueState(force) {
        if (root.selectedQueue) {
            if (!force && root.selectedQueue._appliedState)
                return
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
                                root.captureQueueState(false)
                                root.checkForChanges()
                            }
                        }
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 4

                DlgButton {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 32
                    text: "New queue"
                    onClicked: newQueueDialog.open()
                }
                DlgButton {
                    Layout.preferredWidth: 60
                    Layout.preferredHeight: 32
                    text: "Delete"
                    enabled: root.selectedQueue !== null && (root.selectedQueue ? root.selectedQueue.id !== "main-download" : false)
                    opacity: enabled ? 1.0 : 0.5
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
                color: "#ffffff"
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

                            property var startParts: root.parseScheduleTime(root.selectedQueue ? root.selectedQueue.startTime : "11:00:00 PM", 11, 0, "PM")

                            CheckBox {
                                id: hasStartTimeCb
                                text: "Start download at"
                                topPadding: 0
                                bottomPadding: 0
                                checked: root.selectedQueue ? root.selectedQueue.hasStartTime : false
                                onToggled: { if (root.selectedQueue) { root.selectedQueue.hasStartTime = checked; root.checkForChanges() } }
                            }
                            Rectangle {
                                width: 50; height: 26; radius: 2
                                color: "#1b1b1b"
                                border.color: startHourInput.activeFocus ? "#4488dd" : "#3a3a3a"
                                opacity: (hasStartTimeCb.checked && root.selectedQueue !== null) ? 1.0 : 0.4
                                TextInput {
                                    id: startHourInput
                                    anchors { fill: parent; leftMargin: 6; rightMargin: 6 }
                                    text: parent.parent.startParts.hour
                                    color: "#e0e0e0"
                                    font.pixelSize: 12
                                    horizontalAlignment: TextInput.AlignHCenter
                                    verticalAlignment: TextInput.AlignVCenter
                                    enabled: hasStartTimeCb.checked && root.selectedQueue !== null
                                    validator: IntValidator { bottom: 1; top: 12 }
                                    onTextEdited: root.updateSelectedQueueTime("startTime", text, startMinuteInput.text, startAmPmCombo.currentText)
                                }
                            }
                            Text { text: ":"; color: "#aaaaaa"; font.pixelSize: 13 }
                            Rectangle {
                                width: 50; height: 26; radius: 2
                                color: "#1b1b1b"
                                border.color: startMinuteInput.activeFocus ? "#4488dd" : "#3a3a3a"
                                opacity: (hasStartTimeCb.checked && root.selectedQueue !== null) ? 1.0 : 0.4
                                TextInput {
                                    id: startMinuteInput
                                    anchors { fill: parent; leftMargin: 6; rightMargin: 6 }
                                    text: parent.parent.startParts.minute
                                    color: "#e0e0e0"
                                    font.pixelSize: 12
                                    horizontalAlignment: TextInput.AlignHCenter
                                    verticalAlignment: TextInput.AlignVCenter
                                    enabled: hasStartTimeCb.checked && root.selectedQueue !== null
                                    validator: IntValidator { bottom: 0; top: 59 }
                                    onTextEdited: root.updateSelectedQueueTime("startTime", startHourInput.text, text, startAmPmCombo.currentText)
                                }
                            }
                            ComboBox {
                                id: startAmPmCombo
                                model: ["AM", "PM"]
                                currentIndex: parent.startParts.amPm === "PM" ? 1 : 0
                                enabled: hasStartTimeCb.checked && root.selectedQueue !== null
                                implicitWidth: 62
                                implicitHeight: 26
                                font.pixelSize: 12
                                contentItem: Text {
                                    leftPadding: 8
                                    rightPadding: 20
                                    text: parent.displayText
                                    color: "#e0e0e0"
                                    font: parent.font
                                    verticalAlignment: Text.AlignVCenter
                                    elide: Text.ElideRight
                                }
                                background: Rectangle { color: "#1b1b1b"; border.color: "#3a3a3a"; radius: 2 }
                                indicator: Text { x: parent.width - width - 6; y: (parent.height - height) / 2; text: "▼"; color: "#888"; font.pixelSize: 8 }
                                popup.background: Rectangle { color: "#2a2a2a"; border.color: "#444"; radius: 3 }
                                onCurrentTextChanged: root.updateSelectedQueueTime("startTime", startHourInput.text, startMinuteInput.text, currentText)
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
                        RowLayout {
                            Layout.leftMargin: 40
                            spacing: 3
                            visible: root.selectedQueue ? root.selectedQueue.isDownloadQueue : true
                            enabled: hasStartTimeCb.checked && dailyRadio.checked
                            opacity: enabled ? 1.0 : 0.4

                            Repeater {
                                model: ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
                                delegate: Rectangle {
                                    required property var modelData
                                    property bool on: root.selectedQueue ? root.selectedQueue.startDays.indexOf(modelData) >= 0 : true
                                    width: 36
                                    height: 22
                                    radius: 2
                                    color: on ? "#1a3a6a" : "#252525"
                                    border.color: on ? "#4488dd" : "#3a3a3a"
                                    Text {
                                        anchors.centerIn: parent
                                        text: root.shortDayName(parent.modelData)
                                        color: parent.on ? "#aaccff" : "#666666"
                                        font.pixelSize: 11
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        enabled: hasStartTimeCb.checked && dailyRadio.checked
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.toggleSelectedDay(parent.modelData, !parent.on)
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
                        RowLayout {
                            Layout.leftMargin: 40
                            spacing: 3
                            visible: root.selectedQueue ? !root.selectedQueue.isDownloadQueue : false
                            enabled: startAgainCb.checked
                            opacity: enabled ? 1.0 : 0.4

                            Repeater {
                                model: ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
                                delegate: Rectangle {
                                    required property var modelData
                                    property bool on: root.selectedQueue ? root.selectedQueue.startDays.indexOf(modelData) >= 0 : true
                                    width: 36
                                    height: 22
                                    radius: 2
                                    color: on ? "#1a3a6a" : "#252525"
                                    border.color: on ? "#4488dd" : "#3a3a3a"
                                    Text {
                                        anchors.centerIn: parent
                                        text: root.shortDayName(parent.modelData)
                                        color: parent.on ? "#aaccff" : "#666666"
                                        font.pixelSize: 11
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        enabled: startAgainCb.checked
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.toggleSelectedDay(parent.modelData, !parent.on)
                                    }
                                }
                            }
                        }

                        Rectangle { Layout.fillWidth: true; Layout.leftMargin: 12; Layout.rightMargin: 12; height: 1; color: "#3a3a3a" }

                        // Stop time
                        RowLayout {
                            Layout.leftMargin: 12
                            spacing: 8

                            property var stopParts: root.parseScheduleTime(root.selectedQueue ? root.selectedQueue.stopTime : "7:30:00 AM", 7, 30, "AM")

                            CheckBox {
                                id: hasStopTimeCb
                                text: "Stop download at"
                                topPadding: 0
                                bottomPadding: 0
                                checked: root.selectedQueue ? root.selectedQueue.hasStopTime : false
                                onToggled: { if (root.selectedQueue) { root.selectedQueue.hasStopTime = checked; root.checkForChanges() } }
                            }
                            Rectangle {
                                width: 50; height: 26; radius: 2
                                color: "#1b1b1b"
                                border.color: stopHourInput.activeFocus ? "#4488dd" : "#3a3a3a"
                                opacity: (hasStopTimeCb.checked && root.selectedQueue !== null) ? 1.0 : 0.4
                                TextInput {
                                    id: stopHourInput
                                    anchors { fill: parent; leftMargin: 6; rightMargin: 6 }
                                    text: parent.parent.stopParts.hour
                                    color: "#e0e0e0"
                                    font.pixelSize: 12
                                    horizontalAlignment: TextInput.AlignHCenter
                                    verticalAlignment: TextInput.AlignVCenter
                                    enabled: hasStopTimeCb.checked && root.selectedQueue !== null
                                    validator: IntValidator { bottom: 1; top: 12 }
                                    onTextEdited: root.updateSelectedQueueTime("stopTime", text, stopMinuteInput.text, stopAmPmCombo.currentText)
                                }
                            }
                            Text { text: ":"; color: "#aaaaaa"; font.pixelSize: 13 }
                            Rectangle {
                                width: 50; height: 26; radius: 2
                                color: "#1b1b1b"
                                border.color: stopMinuteInput.activeFocus ? "#4488dd" : "#3a3a3a"
                                opacity: (hasStopTimeCb.checked && root.selectedQueue !== null) ? 1.0 : 0.4
                                TextInput {
                                    id: stopMinuteInput
                                    anchors { fill: parent; leftMargin: 6; rightMargin: 6 }
                                    text: parent.parent.stopParts.minute
                                    color: "#e0e0e0"
                                    font.pixelSize: 12
                                    horizontalAlignment: TextInput.AlignHCenter
                                    verticalAlignment: TextInput.AlignVCenter
                                    enabled: hasStopTimeCb.checked && root.selectedQueue !== null
                                    validator: IntValidator { bottom: 0; top: 59 }
                                    onTextEdited: root.updateSelectedQueueTime("stopTime", stopHourInput.text, text, stopAmPmCombo.currentText)
                                }
                            }
                            ComboBox {
                                id: stopAmPmCombo
                                model: ["AM", "PM"]
                                currentIndex: parent.stopParts.amPm === "PM" ? 1 : 0
                                enabled: hasStopTimeCb.checked && root.selectedQueue !== null
                                implicitWidth: 62
                                implicitHeight: 26
                                font.pixelSize: 12
                                contentItem: Text {
                                    leftPadding: 8
                                    rightPadding: 20
                                    text: parent.displayText
                                    color: "#e0e0e0"
                                    font: parent.font
                                    verticalAlignment: Text.AlignVCenter
                                    elide: Text.ElideRight
                                }
                                background: Rectangle { color: "#1b1b1b"; border.color: "#3a3a3a"; radius: 2 }
                                indicator: Text { x: parent.width - width - 6; y: (parent.height - height) / 2; text: "▼"; color: "#888"; font.pixelSize: 8 }
                                popup.background: Rectangle { color: "#2a2a2a"; border.color: "#444"; radius: 3 }
                                onCurrentTextChanged: root.updateSelectedQueueTime("stopTime", stopHourInput.text, stopMinuteInput.text, currentText)
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
                            value: root.selectedQueue ? root.selectedQueue.maxConcurrentDownloads : 3
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

                            // Wrapper item lets the empty-state text overlay the list area
                            // instead of appearing below it (ListView has fillHeight so a
                            // sibling Text would have zero space in the ColumnLayout).
                            Item {
                                Layout.fillWidth: true
                                Layout.fillHeight: true

                            ListView {
                                    id: filesListView
                                    anchors.fill: parent
                                    model: root.visible ? App.downloadModel : null
                                    clip: true
                                    currentIndex: -1

                                    delegate: Rectangle {
                                        id: delegateContainer
                                        width: ListView.view.width
                                        // Collapse height to zero for items not belonging to the selected queue
                                        // so they don't create invisible gaps in the list.
                                        readonly property bool _inQueue: model.item !== null && root.selectedQueue !== null && model.item.queueId === root.selectedQueue.id
                                        visible: _inQueue
                                        height: _inQueue ? 26 : 0
                                        color: filesListView.currentIndex === index ? "#1e3a6e" : (fileMouseArea.containsMouse ? "#2a2a3a" : (index % 2 === 0 ? "#1c1c1c" : "#202020"))
                                        border.color: filesListView.currentIndex === index ? "#4488dd" : "transparent"
                                        border.width: 1

                                        MouseArea {
                                            id: fileMouseArea
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            onClicked: filesListView.currentIndex = index
                                        }

                                        RowLayout {
                                            anchors.fill: parent
                                            spacing: 8
                                            anchors.leftMargin: 6

                                            Image {
                                                Layout.preferredWidth: 18; Layout.preferredHeight: 18
                                                source: model.item ? "image://fileicon/" + (model.item.savePath + "/" + model.item.filename).replace(/\\/g, "/") : ""
                                                sourceSize: Qt.size(18, 18)
                                                fillMode: Image.PreserveAspectFit
                                                smooth: true
                                            }

                                            Text {
                                                Layout.fillWidth: true
                                                text: model.item ? model.item.filename : ""
                                                color: filesListView.currentIndex === index ? "#88bbff" : "#d0d0d0"
                                                font.pixelSize: 12
                                                font.bold: filesListView.currentIndex === index
                                                elide: Text.ElideMiddle
                                            }

                                            Text {
                                                Layout.preferredWidth: parent.width * 0.15
                                                text: {
                                                    if (!model.item || model.item.totalBytes <= 0) return "--"
                                                    var b = model.item.totalBytes
                                                    if (b < 1048576) return (b / 1024).toFixed(1) + " KB"
                                                    if (b < 1073741824) return (b / 1048576).toFixed(1) + " MB"
                                                    return (b / 1073741824).toFixed(2) + " GB"
                                                }
                                                color: filesListView.currentIndex === index ? "#aaccff" : "#b0b0b0"
                                                font.pixelSize: 12
                                            }

                                            Text {
                                                Layout.preferredWidth: parent.width * 0.15
                                                text: model.item ? model.item.status : "--"
                                                color: "#ffffff"
                                                font.pixelSize: 12
                                            }

                                            Text {
                                                Layout.preferredWidth: parent.width * 0.15
                                                text: model.item ? model.item.timeLeft : "--"
                                                color: filesListView.currentIndex === index ? "#aaccff" : "#b0b0b0"
                                                font.pixelSize: 12
                                            }
                                        }
                                     }
                                }

                            // Empty-state overlay: centered in the list area.
                            // Anchored inside the wrapper Item, not in the ColumnLayout,
                            // so it sits in the middle of the list regardless of the
                            // ListView consuming all available height.
                            Text {
                                anchors.centerIn: parent
                                text: {
                                    if (!root.selectedQueue) return "No queue selected"
                                    // Check if any item in the model belongs to this queue
                                    for (var i = 0; i < App.downloadModel.rowCount(); i++) {
                                        var item = App.downloadModel.data(App.downloadModel.index(i, 0), Qt.UserRole + 2) // ItemRole
                                        if (item && item.queueId === root.selectedQueue.id) {
                                            return "" // Has files, don't show placeholder
                                        }
                                    }
                                    return "No files in queue"
                                }
                                color: "#555"
                                font.pixelSize: 12
                                visible: text.length > 0
                            }
                            } // end wrapper Item
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

                DlgButton {
                    text: "Start now"
                    Layout.preferredWidth: 90
                    Layout.preferredHeight: 32
                    enabled: root.selectedQueue !== null
                    primary: true
                    onClicked: { if (root.selectedQueue) App.startQueue(root.selectedQueue.id) }
                }
                DlgButton {
                    text: "Stop"
                    Layout.preferredWidth: 90
                    Layout.preferredHeight: 32
                    enabled: root.selectedQueue !== null
                    opacity: enabled ? 1.0 : 0.5
                    onClicked: { if (root.selectedQueue) App.stopQueue(root.selectedQueue.id) }
                }

                Item { Layout.fillWidth: true }

                DlgButton {
                    text: "Apply"
                    Layout.preferredWidth: 80
                    Layout.preferredHeight: 32
                    primary: root.hasChanges
                    enabled: root.hasChanges
                    opacity: enabled ? 1.0 : 0.5
                    onClicked: {
                        App.saveQueues()
                        root.captureQueueState(true)
                        root.hasChanges = false
                    }
                }
                DlgButton {
                    text: "Close"
                    Layout.preferredWidth: 80
                    Layout.preferredHeight: 32
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
                    DlgButton {
                        text: "OK"
                        primary: true
                        onClicked: confirmNewQueue()
                    }
                    DlgButton {
                        text: "Cancel"
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
        root.captureQueueState(false)
        root.hasChanges = false
    }
}
