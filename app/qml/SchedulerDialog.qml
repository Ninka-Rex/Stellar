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
import Qt.labs.platform

Window {
    id: root
    title: qsTr("Scheduler")
    modality: Qt.ApplicationModal
    width: 700
    height: 500
    minimumWidth: 700
    minimumHeight: 500
    flags: Qt.Window | Qt.WindowTitleHint | Qt.WindowSystemMenuHint | Qt.WindowCloseButtonHint
    color: ColorPalette.windowBg

    Material.theme: ColorPalette.materialTheme
    Material.foreground: ColorPalette.textPrimary
    Material.background: ColorPalette.materialBg
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

    // ── Drag proxy for file-list → queue-list drag-drop ─────────────────
    // Invisible 1×1 item that travels with the cursor; DropAreas on queue
    // rows read dragDownloadId / dragDownloadIds off drop.source.
    Item {
        id: schedulerDragProxy
        width: 1; height: 1
        visible: false
        z: 9999
        parent: root.contentItem   // float above all children
        Drag.keys: ["text/downloadId"]
        Drag.hotSpot: Qt.point(0, 0)
        property string dragDownloadId: ""
        property var    dragDownloadIds: []
        property string dragFilename: ""

        // Tooltip-style label that follows the cursor
        Rectangle {
            visible: schedulerDragProxy.visible && schedulerDragProxy.dragFilename !== ""
            width: dragLabel.implicitWidth + 16; height: 22
            radius: 3
            color: ColorPalette.selectionBg
            border.color: "#4488dd"; border.width: 1
            x: 8; y: 8
            Text {
                id: dragLabel
                anchors.centerIn: parent
                text: schedulerDragProxy.dragFilename
                color: ColorPalette.textPrimary
                font.pixelSize: 11 * App.fontScale
                elide: Text.ElideMiddle
                maximumLineCount: 1
            }
        }
    }

    // ── Root layout ──────────────────────────────────────────────────────
    RowLayout {
        anchors { fill: parent; margins: 12 }
        spacing: 12

        // ── Left sidebar ─────────────────────────────────────────────────
        ColumnLayout {
            Layout.preferredWidth: 180
            Layout.fillHeight: true
            spacing: 6

            Text {
                text: qsTr("Queues")
                color: ColorPalette.textPrimary
                font.bold: true
                font.pixelSize: 12 * App.fontScale
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                color: ColorPalette.panelBg
                border.color: ColorPalette.border
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
                        color: queueList.currentIndex === index
                             ? ColorPalette.selectionBg
                             : (queueDropArea.containsDrag ? ColorPalette.hoverBg : "transparent")
                        border.color: queueList.currentIndex === index
                                    ? "#4488dd"
                                    : (queueDropArea.containsDrag ? "#4488dd" : "transparent")
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
                                    if (model.queueId === "main-download") return "icons/main_queue.svg"
                                    if (model.queueId === "main-sync") return "icons/synch_queue.svg"
                                    return "icons/custom_queue.svg"
                                }
                            }

                            Text {
                                text: model.queueName || ""
                                color: ColorPalette.textPrimary
                                font.pixelSize: 12 * App.fontScale
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

                        // Accept drags from the file list to move items into this queue.
                        DropArea {
                            id: queueDropArea
                            anchors.fill: parent
                            keys: ["text/downloadId"]
                            enabled: model.queueId !== "download-limits"
                            onDropped: (drop) => {
                                if (!drop.source || model.queueId === "download-limits") return
                                var ids = drop.source.dragDownloadIds && drop.source.dragDownloadIds.length > 0
                                        ? drop.source.dragDownloadIds
                                        : (drop.source.dragDownloadId ? [drop.source.dragDownloadId] : [])
                                for (var i = 0; i < ids.length; i++)
                                    App.setDownloadQueue(ids[i], model.queueId)
                                if (ids.length > 0) drop.accept()
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
                    text: qsTr("New queue")
                    onClicked: newQueueDialog.open()
                }
                DlgButton {
                    Layout.preferredWidth: 60
                    Layout.preferredHeight: 32
                    text: qsTr("Delete")
                    enabled: root.selectedQueue !== null && (root.selectedQueue ? (root.selectedQueue.id !== "main-download" && root.selectedQueue.id !== "main-sync" && root.selectedQueue.id !== "download-limits") : false)
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

        // ── Right pane ───────────────────────────────────────────────────
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 0

            // Queue title
            Text {
                Layout.fillWidth: true
                Layout.preferredHeight: 32
                text: root.selectedQueue ? root.selectedQueue.name : ""
                color: ColorPalette.textHeader
                font.pixelSize: 15 * App.fontScale
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
                    model: [qsTr("Schedule"), qsTr("Files in the queue")]
                    delegate: Button {
                        Layout.preferredWidth: 160
                        text: modelData
                        font.pixelSize: 11 * App.fontScale
                        checkable: true
                        checked: tabView.currentIndex === index
                        background: Rectangle { color: parent.checked ? ColorPalette.selectionBg : (parent.pressed ? ColorPalette.toolbarPressBg : parent.hovered ? ColorPalette.toolbarHoverBg : ColorPalette.panelBg); radius: 0; border.color: parent.checked ? "#4488dd" : ColorPalette.border; border.width: 1 }
                        onClicked: tabView.currentIndex = index
                    }
                }
                Item { Layout.fillWidth: true }
            }

            // Separator
            Rectangle {
                Layout.fillWidth: true
                height: 1
                color: ColorPalette.border
                visible: root.selectedQueue ? root.selectedQueue.id !== "download-limits" : true
            }

            // Tab content (hidden for download-limits queue)
            StackLayout {
                id: tabView
                Layout.fillWidth: true
                Layout.fillHeight: true
                currentIndex: 0
                visible: root.selectedQueue ? root.selectedQueue.id !== "download-limits" : true

                // ── SCHEDULE TAB ─────────────────────────────────────────
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

                            StyledRadioButton {
                                text: qsTr("One-time downloading")
                                topPadding: 0
                                bottomPadding: 0
                                checked: root.selectedQueue ? root.selectedQueue.isDownloadQueue : true
                                onToggled: { if (checked && root.selectedQueue) { root.selectedQueue.isDownloadQueue = true; root.checkForChanges() } }
                            }
                            StyledRadioButton {
                                text: qsTr("Periodic synchronization")
                                topPadding: 0
                                bottomPadding: 0
                                checked: root.selectedQueue ? !root.selectedQueue.isDownloadQueue : false
                                onToggled: { if (checked && root.selectedQueue) { root.selectedQueue.isDownloadQueue = false; root.checkForChanges() } }
                            }
                        }

                        StyledCheckBox {
                            Layout.leftMargin: 12
                            text: qsTr("Start download on Stellar startup")
                            topPadding: 0
                            bottomPadding: 0
                            checked: root.selectedQueue ? root.selectedQueue.startOnIDMStartup : false
                            onToggled: { if (root.selectedQueue) { root.selectedQueue.startOnIDMStartup = checked; root.checkForChanges() } }
                        }

                        // Separator
                        Rectangle { Layout.fillWidth: true; Layout.leftMargin: 12; Layout.rightMargin: 12; height: 1; color: ColorPalette.border }

                        // Start time row
                        RowLayout {
                            Layout.leftMargin: 12
                            spacing: 8

                            property var startParts: root.parseScheduleTime(root.selectedQueue ? root.selectedQueue.startTime : "11:00:00 PM", 11, 0, "PM")

                            StyledCheckBox {
                                id: hasStartTimeCb
                                text: qsTr("Start download at")
                                topPadding: 0
                                bottomPadding: 0
                                checked: root.selectedQueue ? root.selectedQueue.hasStartTime : false
                                onToggled: { if (root.selectedQueue) { root.selectedQueue.hasStartTime = checked; root.checkForChanges() } }
                            }
                            Rectangle {
                                width: 50; height: 26; radius: 2
                                color: ColorPalette.inputBg
                                border.color: startHourInput.activeFocus ? "#4488dd" : ColorPalette.border
                                opacity: (hasStartTimeCb.checked && root.selectedQueue !== null) ? 1.0 : 0.4
                                TextInput {
                                    id: startHourInput
                                    anchors { fill: parent; leftMargin: 6; rightMargin: 6 }
                                    text: parent.parent.startParts.hour
                                    color: ColorPalette.textPrimary
                                    font.pixelSize: 12 * App.fontScale
                                    horizontalAlignment: TextInput.AlignHCenter
                                    verticalAlignment: TextInput.AlignVCenter
                                    enabled: hasStartTimeCb.checked && root.selectedQueue !== null
                                    validator: IntValidator { bottom: 1; top: 12 }
                                    onTextEdited: root.updateSelectedQueueTime("startTime", text, startMinuteInput.text, startAmPmCombo.currentText)
                                }
                            }
                            Text { text: ":"; color: ColorPalette.textSecond; font.pixelSize: 13 * App.fontScale }
                            Rectangle {
                                width: 50; height: 26; radius: 2
                                color: ColorPalette.inputBg
                                border.color: startMinuteInput.activeFocus ? "#4488dd" : ColorPalette.border
                                opacity: (hasStartTimeCb.checked && root.selectedQueue !== null) ? 1.0 : 0.4
                                TextInput {
                                    id: startMinuteInput
                                    anchors { fill: parent; leftMargin: 6; rightMargin: 6 }
                                    text: parent.parent.startParts.minute
                                    color: ColorPalette.textPrimary
                                    font.pixelSize: 12 * App.fontScale
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
                                font.pixelSize: 12 * App.fontScale
                                contentItem: Text {
                                    leftPadding: 8
                                    rightPadding: 20
                                    text: parent.displayText
                                    color: ColorPalette.textPrimary
                                    font: parent.font
                                    verticalAlignment: Text.AlignVCenter
                                    elide: Text.ElideRight
                                }
                                background: Rectangle { color: ColorPalette.inputBg; border.color: ColorPalette.border; radius: 2 }
                                indicator: Text { x: parent.width - width - 6; y: (parent.height - height) / 2; text: "▾"; color: ColorPalette.textSecond; font.pixelSize: 8 * App.fontScale }
                                popup.background: Rectangle { color: ColorPalette.inputBg; border.color: ColorPalette.border; radius: 3 }
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

                            StyledRadioButton {
                                text: qsTr("Once at")
                                topPadding: 0
                                bottomPadding: 0
                                checked: root.selectedQueue ? root.selectedQueue.startOnce : true
                                onToggled: { if (checked && root.selectedQueue) { root.selectedQueue.startOnce = true; root.selectedQueue.startDaily = false; root.checkForChanges() } }
                            }
                            StyledRadioButton {
                                id: dailyRadio
                                text: qsTr("Daily")
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
                                    color: on ? ColorPalette.selectionBg : ColorPalette.panelBg
                                    border.color: on ? "#4488dd" : ColorPalette.border
                                    Text {
                                        anchors.centerIn: parent
                                        text: root.shortDayName(parent.modelData)
                                        color: parent.on ? ColorPalette.accent : ColorPalette.textDisabled
                                        font.pixelSize: 11 * App.fontScale
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

                            StyledCheckBox {
                                id: startAgainCb
                                text: qsTr("Start again every")
                                topPadding: 0
                                bottomPadding: 0
                                checked: root.selectedQueue ? root.selectedQueue.hasStartAgainEvery : false
                                onToggled: { if (root.selectedQueue) { root.selectedQueue.hasStartAgainEvery = checked; root.checkForChanges() } }
                            }
                            Rectangle {
                                width: 46; height: 26; radius: 2
                                color: ColorPalette.inputBg
                                border.color: startAgainHoursInput.activeFocus ? "#4488dd" : ColorPalette.border
                                opacity: startAgainCb.checked ? 1.0 : 0.4
                                TextInput {
                                    id: startAgainHoursInput
                                    anchors { fill: parent; leftMargin: 6; rightMargin: 6 }
                                    text: root.selectedQueue ? String(root.selectedQueue.startAgainEveryHours) : "2"
                                    color: ColorPalette.textPrimary; font.pixelSize: 12 * App.fontScale
                                    horizontalAlignment: TextInput.AlignHCenter
                                    verticalAlignment: TextInput.AlignVCenter
                                    enabled: startAgainCb.checked
                                    validator: IntValidator { bottom: 0; top: 23 }
                                    onTextEdited: { if (root.selectedQueue) { var v = parseInt(text, 10); if (!isNaN(v)) { root.selectedQueue.startAgainEveryHours = v; root.checkForChanges() } } }
                                }
                            }
                            Text { text: qsTr("hours"); color: ColorPalette.textPrimary; font.pixelSize: 12 * App.fontScale }
                            Rectangle {
                                width: 46; height: 26; radius: 2
                                color: ColorPalette.inputBg
                                border.color: startAgainMinsInput.activeFocus ? "#4488dd" : ColorPalette.border
                                opacity: startAgainCb.checked ? 1.0 : 0.4
                                TextInput {
                                    id: startAgainMinsInput
                                    anchors { fill: parent; leftMargin: 6; rightMargin: 6 }
                                    text: root.selectedQueue ? String(root.selectedQueue.startAgainEveryMins) : "0"
                                    color: ColorPalette.textPrimary; font.pixelSize: 12 * App.fontScale
                                    horizontalAlignment: TextInput.AlignHCenter
                                    verticalAlignment: TextInput.AlignVCenter
                                    enabled: startAgainCb.checked
                                    validator: IntValidator { bottom: 0; top: 59 }
                                    onTextEdited: { if (root.selectedQueue) { var v = parseInt(text, 10); if (!isNaN(v)) { root.selectedQueue.startAgainEveryMins = v; root.checkForChanges() } } }
                                }
                            }
                            Text { text: qsTr("min"); color: ColorPalette.textPrimary; font.pixelSize: 12 * App.fontScale }
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
                                    color: on ? ColorPalette.selectionBg : ColorPalette.panelBg
                                    border.color: on ? "#4488dd" : ColorPalette.border
                                    Text {
                                        anchors.centerIn: parent
                                        text: root.shortDayName(parent.modelData)
                                        color: parent.on ? ColorPalette.accent : ColorPalette.textDisabled
                                        font.pixelSize: 11 * App.fontScale
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

                        Rectangle { Layout.fillWidth: true; Layout.leftMargin: 12; Layout.rightMargin: 12; height: 1; color: ColorPalette.border }

                        // Stop time
                        RowLayout {
                            Layout.leftMargin: 12
                            spacing: 8

                            property var stopParts: root.parseScheduleTime(root.selectedQueue ? root.selectedQueue.stopTime : "7:30:00 AM", 7, 30, "AM")

                            StyledCheckBox {
                                id: hasStopTimeCb
                                text: qsTr("Stop download at")
                                topPadding: 0
                                bottomPadding: 0
                                checked: root.selectedQueue ? root.selectedQueue.hasStopTime : false
                                onToggled: { if (root.selectedQueue) { root.selectedQueue.hasStopTime = checked; root.checkForChanges() } }
                            }
                            Rectangle {
                                width: 50; height: 26; radius: 2
                                color: ColorPalette.inputBg
                                border.color: stopHourInput.activeFocus ? "#4488dd" : ColorPalette.border
                                opacity: (hasStopTimeCb.checked && root.selectedQueue !== null) ? 1.0 : 0.4
                                TextInput {
                                    id: stopHourInput
                                    anchors { fill: parent; leftMargin: 6; rightMargin: 6 }
                                    text: parent.parent.stopParts.hour
                                    color: ColorPalette.textPrimary
                                    font.pixelSize: 12 * App.fontScale
                                    horizontalAlignment: TextInput.AlignHCenter
                                    verticalAlignment: TextInput.AlignVCenter
                                    enabled: hasStopTimeCb.checked && root.selectedQueue !== null
                                    validator: IntValidator { bottom: 1; top: 12 }
                                    onTextEdited: root.updateSelectedQueueTime("stopTime", text, stopMinuteInput.text, stopAmPmCombo.currentText)
                                }
                            }
                            Text { text: ":"; color: ColorPalette.textSecond; font.pixelSize: 13 * App.fontScale }
                            Rectangle {
                                width: 50; height: 26; radius: 2
                                color: ColorPalette.inputBg
                                border.color: stopMinuteInput.activeFocus ? "#4488dd" : ColorPalette.border
                                opacity: (hasStopTimeCb.checked && root.selectedQueue !== null) ? 1.0 : 0.4
                                TextInput {
                                    id: stopMinuteInput
                                    anchors { fill: parent; leftMargin: 6; rightMargin: 6 }
                                    text: parent.parent.stopParts.minute
                                    color: ColorPalette.textPrimary
                                    font.pixelSize: 12 * App.fontScale
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
                                font.pixelSize: 12 * App.fontScale
                                contentItem: Text {
                                    leftPadding: 8
                                    rightPadding: 20
                                    text: parent.displayText
                                    color: ColorPalette.textPrimary
                                    font: parent.font
                                    verticalAlignment: Text.AlignVCenter
                                    elide: Text.ElideRight
                                }
                                background: Rectangle { color: ColorPalette.inputBg; border.color: ColorPalette.border; radius: 2 }
                                indicator: Text { x: parent.width - width - 6; y: (parent.height - height) / 2; text: "▾"; color: ColorPalette.textSecond; font.pixelSize: 8 * App.fontScale }
                                popup.background: Rectangle { color: ColorPalette.inputBg; border.color: ColorPalette.border; radius: 3 }
                                onCurrentTextChanged: root.updateSelectedQueueTime("stopTime", stopHourInput.text, stopMinuteInput.text, currentText)
                            }
                        }

                        // Retries
                        RowLayout {
                            Layout.leftMargin: 12
                            spacing: 8

                            StyledCheckBox {
                                id: retriesCb
                                text: qsTr("Number of retries for each file if downloading failed :")
                                topPadding: 0
                                bottomPadding: 0
                                checked: root.selectedQueue ? root.selectedQueue.hasMaxRetries : false
                                onToggled: { if (root.selectedQueue) { root.selectedQueue.hasMaxRetries = checked; root.checkForChanges() } }
                            }
                            Rectangle {
                                width: 46; height: 26; radius: 2
                                color: ColorPalette.inputBg
                                border.color: retriesInput.activeFocus ? "#4488dd" : ColorPalette.border
                                opacity: retriesCb.checked ? 1.0 : 0.4
                                TextInput {
                                    id: retriesInput
                                    anchors { fill: parent; leftMargin: 6; rightMargin: 6 }
                                    text: root.selectedQueue ? String(root.selectedQueue.maxRetries) : "10"
                                    color: ColorPalette.textPrimary; font.pixelSize: 12 * App.fontScale
                                    horizontalAlignment: TextInput.AlignHCenter
                                    verticalAlignment: TextInput.AlignVCenter
                                    enabled: retriesCb.checked
                                    validator: IntValidator { bottom: 1; top: 100 }
                                    onTextEdited: { if (root.selectedQueue) { var v = parseInt(text, 10); if (!isNaN(v) && v >= 1) { root.selectedQueue.maxRetries = v; root.checkForChanges() } } }
                                }
                            }
                        }

                        Rectangle { Layout.fillWidth: true; Layout.leftMargin: 12; Layout.rightMargin: 12; height: 1; color: ColorPalette.border }

                        // ── Open file when done checkbox + inline path field on one row ──
                        RowLayout {
                            Layout.leftMargin: 12
                            Layout.rightMargin: 12
                            spacing: 8

                            StyledCheckBox {
                                id: openFileCb
                                text: qsTr("Open the following file when done:")
                                topPadding: 0
                                bottomPadding: 0
                                checked: root.selectedQueue ? root.selectedQueue.openFileWhenDone : false
                                onToggled: { if (root.selectedQueue) { root.selectedQueue.openFileWhenDone = checked; root.checkForChanges() } }
                            }
                            Rectangle {
                                Layout.fillWidth: true
                                height: 26; radius: 2
                                color: ColorPalette.inputBg
                                border.color: openFileInput.activeFocus ? "#4488dd" : ColorPalette.border
                                opacity: openFileCb.checked ? 1.0 : 0.4
                                TextInput {
                                    id: openFileInput
                                    anchors { fill: parent; leftMargin: 7; rightMargin: 7 }
                                    text: root.selectedQueue ? root.selectedQueue.openFilePath : ""
                                    color: ColorPalette.textPrimary; font.pixelSize: 12 * App.fontScale
                                    verticalAlignment: TextInput.AlignVCenter
                                    enabled: openFileCb.checked
                                    clip: true
                                    onTextEdited: { if (root.selectedQueue) { root.selectedQueue.openFilePath = text; root.checkForChanges() } }
                                }
                            }
                            DlgButton {
                                text: "..."
                                Layout.preferredWidth: 36
                                Layout.preferredHeight: 26
                                enabled: openFileCb.checked
                                opacity: enabled ? 1.0 : 0.4
                                onClicked: fileDialog.open()
                            }
                        }

                        // Post-completion actions
                        StyledCheckBox {
                            Layout.leftMargin: 12
                            text: qsTr("Exit Stellar when done")
                            topPadding: 0
                            bottomPadding: 0
                            checked: root.selectedQueue ? root.selectedQueue.exitIDMWhenDone : false
                            onToggled: { if (root.selectedQueue) { root.selectedQueue.exitIDMWhenDone = checked; root.checkForChanges() } }
                        }

                        ColumnLayout {
                            Layout.leftMargin: 12
                            spacing: 4

                            StyledCheckBox {
                                id: turnOffCb
                                text: qsTr("Turn off computer when done")
                                topPadding: 0
                                bottomPadding: 0
                                checked: root.selectedQueue ? root.selectedQueue.turnOffComputerWhenDone : false
                                onToggled: { if (root.selectedQueue) { root.selectedQueue.turnOffComputerWhenDone = checked; root.checkForChanges() } }
                            }
                            StyledCheckBox {
                                Layout.leftMargin: 20
                                text: qsTr("Force processes to terminate")
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

                // ── FILES IN QUEUE TAB ───────────────────────────────────
                ColumnLayout {
                    spacing: 8

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.topMargin: 8
                        Layout.leftMargin: 8
                        spacing: 8

                        Text { text: qsTr("Download"); color: ColorPalette.textPrimary; font.pixelSize: 12 * App.fontScale }
                        SpinBox {
                            id: concurrentSpin
                            from: 1; to: 10
                            implicitWidth: 80
                            implicitHeight: 26
                            value: root.selectedQueue ? root.selectedQueue.maxConcurrentDownloads : 3
                            editable: true
                            contentItem: TextInput {
                                text: concurrentSpin.textFromValue(concurrentSpin.value, concurrentSpin.locale)
                                color: ColorPalette.textPrimary
                                font.pixelSize: 12 * App.fontScale
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                                readOnly: !concurrentSpin.editable
                                validator: concurrentSpin.validator
                            }
                            up.indicator: Rectangle {
                                x: concurrentSpin.width - width; y: 0
                                width: 22; height: concurrentSpin.height / 2
                                color: concurrentSpin.up.pressed ? ColorPalette.toolbarPressBg
                                     : concurrentSpin.up.hovered ? ColorPalette.toolbarHoverBg
                                     : ColorPalette.panelBg
                                Text { anchors.centerIn: parent; text: "+"; color: ColorPalette.textPrimary; font.pixelSize: 11 * App.fontScale }
                            }
                            down.indicator: Rectangle {
                                x: concurrentSpin.width - width; y: concurrentSpin.height / 2
                                width: 22; height: concurrentSpin.height / 2
                                color: concurrentSpin.down.pressed ? ColorPalette.toolbarPressBg
                                     : concurrentSpin.down.hovered ? ColorPalette.toolbarHoverBg
                                     : ColorPalette.panelBg
                                Text { anchors.centerIn: parent; text: "–"; color: ColorPalette.textPrimary; font.pixelSize: 11 * App.fontScale }
                            }
                            background: Rectangle { color: ColorPalette.inputBg; border.color: ColorPalette.border; radius: 2 }
                            onValueModified: {
                                if (root.selectedQueue) {
                                    root.selectedQueue.maxConcurrentDownloads = value
                                    root.checkForChanges()
                                }
                            }
                        }
                        Text { text: qsTr("files at the same time"); color: ColorPalette.textPrimary; font.pixelSize: 12 * App.fontScale }
                        Item { Layout.fillWidth: true }
                    }

                    // File table
                    Rectangle {
                        id: fileTableRect
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.leftMargin: 8
                        Layout.rightMargin: 8
                        color: ColorPalette.windowBg
                        border.color: ColorPalette.border
                        border.width: 1
                        radius: 0

                        // ── Resizable column widths dragged via header separators. ──
                        // All columns are fixed width; File Name has its own min width.
                        // Total content width = margins + icon + fileName + size + status + timeLeft.
                        // When total exceeds viewport, header and list scroll in sync.
                        property real colIconWidth: 26
                        property real colFileNameWidth: 200
                        property real colSizeWidth: 90
                        property real colStatusWidth: 80
                        property real colTimeLeftWidth: 80
                        // Total row content width (8px left margin + 8px right margin)
                        readonly property real totalRowWidth: 16 + colIconWidth + colFileNameWidth + colSizeWidth + colStatusWidth + colTimeLeftWidth

                        ColumnLayout {
                            anchors { fill: parent; margins: 0 }
                            spacing: 0

                            // ── Header sits in a Flickable synced to hScroll ──
                            Rectangle {
                                Layout.fillWidth: true
                                height: 26
                                color: ColorPalette.dividerBg
                                clip: true

                                Flickable {
                                    id: headerFlick
                                    anchors.fill: parent
                                    contentWidth: fileTableRect.totalRowWidth
                                    contentX: hScroll.position * (contentWidth - width)
                                    interactive: false
                                    clip: true

                                    Row {
                                        x: 8; spacing: 0
                                        height: headerFlick.height

                                        Item { width: fileTableRect.colIconWidth; height: parent.height }

                                        // File Name with drag handle on right edge
                                        Item {
                                            width: fileTableRect.colFileNameWidth; height: parent.height
                                            Text { anchors.verticalCenter: parent.verticalCenter; text: qsTr("File Name"); color: ColorPalette.textPrimary; font.pixelSize: 11 * App.fontScale; font.bold: true }
                                            Rectangle {
                                                anchors { right: parent.right; top: parent.top; bottom: parent.bottom }
                                                width: 4; color: "transparent"
                                                MouseArea {
                                                    anchors.fill: parent; cursorShape: Qt.SizeHorCursor
                                                    property real _sx: 0; property real _sw: 0
                                                    onPressed: { _sx = mapToItem(null, mouseX, 0).x; _sw = fileTableRect.colFileNameWidth }
                                                    onMouseXChanged: if (pressed) { var dx = mapToItem(null, mouseX, 0).x - _sx; fileTableRect.colFileNameWidth = Math.max(80, _sw + dx) }
                                                }
                                            }
                                        }

                                        // Size with drag handle
                                        Item {
                                            width: fileTableRect.colSizeWidth; height: parent.height
                                            Text { anchors.verticalCenter: parent.verticalCenter; text: qsTr("Size"); color: ColorPalette.textPrimary; font.pixelSize: 11 * App.fontScale; font.bold: true }
                                            Rectangle {
                                                anchors { right: parent.right; top: parent.top; bottom: parent.bottom }
                                                width: 4; color: "transparent"
                                                MouseArea {
                                                    anchors.fill: parent; cursorShape: Qt.SizeHorCursor
                                                    property real _sx: 0; property real _sw: 0
                                                    onPressed: { _sx = mapToItem(null, mouseX, 0).x; _sw = fileTableRect.colSizeWidth }
                                                    onMouseXChanged: if (pressed) { var dx = mapToItem(null, mouseX, 0).x - _sx; fileTableRect.colSizeWidth = Math.max(50, _sw + dx) }
                                                }
                                            }
                                        }

                                        // Status with drag handle
                                        Item {
                                            width: fileTableRect.colStatusWidth; height: parent.height
                                            Text { anchors.verticalCenter: parent.verticalCenter; text: qsTr("Status"); color: ColorPalette.textPrimary; font.pixelSize: 11 * App.fontScale; font.bold: true }
                                            Rectangle {
                                                anchors { right: parent.right; top: parent.top; bottom: parent.bottom }
                                                width: 4; color: "transparent"
                                                MouseArea {
                                                    anchors.fill: parent; cursorShape: Qt.SizeHorCursor
                                                    property real _sx: 0; property real _sw: 0
                                                    onPressed: { _sx = mapToItem(null, mouseX, 0).x; _sw = fileTableRect.colStatusWidth }
                                                    onMouseXChanged: if (pressed) { var dx = mapToItem(null, mouseX, 0).x - _sx; fileTableRect.colStatusWidth = Math.max(50, _sw + dx) }
                                                }
                                            }
                                        }

                                        // ── Time Left (no handle needed last column) ──
                                        Item {
                                            width: fileTableRect.colTimeLeftWidth; height: parent.height
                                            Text { anchors.verticalCenter: parent.verticalCenter; text: qsTr("Time Left"); color: ColorPalette.textPrimary; font.pixelSize: 11 * App.fontScale; font.bold: true }
                                            Rectangle {
                                                anchors { right: parent.right; top: parent.top; bottom: parent.bottom }
                                                width: 4; color: "transparent"
                                                MouseArea {
                                                    anchors.fill: parent; cursorShape: Qt.SizeHorCursor
                                                    property real _sx: 0; property real _sw: 0
                                                    onPressed: { _sx = mapToItem(null, mouseX, 0).x; _sw = fileTableRect.colTimeLeftWidth }
                                                    onMouseXChanged: if (pressed) { var dx = mapToItem(null, mouseX, 0).x - _sx; fileTableRect.colTimeLeftWidth = Math.max(50, _sw + dx) }
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            Rectangle { Layout.fillWidth: true; height: 1; color: ColorPalette.border }

                            // Wrapper item lets the empty-state text overlay the list area
                            // instead of appearing below it (ListView has fillHeight so a
                            // sibling Text would have zero space in the ColumnLayout).
                            Item {
                                Layout.fillWidth: true
                                Layout.fillHeight: true

                                ListView {
                                    id: filesListView
                                    anchors { top: parent.top; bottom: hScroll.visible ? hScroll.top : parent.bottom; left: parent.left; right: parent.right }
                                    model: root.visible ? App.downloadModel : null
                                    clip: true
                                    currentIndex: -1

                                    delegate: Rectangle {
                                        id: delegateContainer
                                        // Row is wider than the viewport when columns are resized out
                                        width: Math.max(filesListView.width, fileTableRect.totalRowWidth)
                                        readonly property bool _inQueue: model.item !== null && root.selectedQueue !== null && model.item.queueId === root.selectedQueue.id
                                        visible: _inQueue
                                        height: _inQueue ? 26 : 0
                                        color: filesListView.currentIndex === index ? ColorPalette.selectionBg : (fileMouseArea.containsMouse ? ColorPalette.hoverBg : (index % 2 === 0 ? ColorPalette.windowBg : ColorPalette.rowAltBg))
                                        border.color: filesListView.currentIndex === index ? "#4488dd" : "transparent"
                                        border.width: 1

                                        MouseArea {
                                            id: fileMouseArea
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            drag.target: schedulerDragProxy
                                            onClicked: filesListView.currentIndex = index
                                            onPressed: {
                                                if (model.item) {
                                                    schedulerDragProxy.dragDownloadId  = model.item.id
                                                    schedulerDragProxy.dragDownloadIds = [model.item.id]
                                                    schedulerDragProxy.dragFilename    = model.item.filename
                                                    // Map delegate-local coords to root.contentItem space so the
                                                    // proxy (parented to contentItem) follows the cursor exactly.
                                                    var pos = fileMouseArea.mapToItem(root.contentItem, mouseX, mouseY)
                                                    schedulerDragProxy.x = pos.x
                                                    schedulerDragProxy.y = pos.y
                                                }
                                            }
                                            onPositionChanged: {
                                                if (drag.active && schedulerDragProxy.dragDownloadId) {
                                                    schedulerDragProxy.visible = true
                                                    schedulerDragProxy.Drag.active = true
                                                    var pos = fileMouseArea.mapToItem(root.contentItem, mouseX, mouseY)
                                                    schedulerDragProxy.x = pos.x
                                                    schedulerDragProxy.y = pos.y
                                                }
                                            }
                                            onReleased: {
                                                if (schedulerDragProxy.visible) {
                                                    schedulerDragProxy.Drag.drop()
                                                    schedulerDragProxy.Drag.active = false
                                                    schedulerDragProxy.visible = false
                                                    schedulerDragProxy.dragDownloadId  = ""
                                                    schedulerDragProxy.dragDownloadIds = []
                                                    schedulerDragProxy.dragFilename    = ""
                                                }
                                            }
                                        }

                                        Row {
                                            x: 8; spacing: 0
                                            height: parent.height

                                            Item {
                                                width: fileTableRect.colIconWidth; height: parent.height
                                                Image {
                                                    anchors.centerIn: parent
                                                    width: 18; height: 18
                                                    source: model.item ? "image://fileicon/" + (model.item.savePath + "/" + model.item.filename).replace(/\\/g, "/") : ""
                                                    sourceSize: Qt.size(18, 18)
                                                    fillMode: Image.PreserveAspectFit
                                                    smooth: true
                                                }
                                            }

                                            Item {
                                                width: fileTableRect.colFileNameWidth; height: parent.height
                                                Text {
                                                    anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; rightMargin: 4 }
                                                    text: model.item ? model.item.filename : ""
                                                    color: filesListView.currentIndex === index ? ColorPalette.selectionText : ColorPalette.textPrimary
                                                    font.pixelSize: 12 * App.fontScale
                                                    font.bold: filesListView.currentIndex === index
                                                    elide: Text.ElideMiddle
                                                }
                                            }

                                            Item {
                                                width: fileTableRect.colSizeWidth; height: parent.height
                                                Text {
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    text: {
                                                        if (!model.item || model.item.totalBytes <= 0) return "--"
                                                        var b = model.item.totalBytes
                                                        if (b < 1048576) return (b / 1024).toFixed(1) + " KB"
                                                        if (b < 1073741824) return (b / 1048576).toFixed(1) + " MB"
                                                        return (b / 1073741824).toFixed(2) + " GB"
                                                    }
                                                    color: filesListView.currentIndex === index ? ColorPalette.selectionText : ColorPalette.textPrimary
                                                    font.pixelSize: 12 * App.fontScale
                                                }
                                            }

                                            Item {
                                                width: fileTableRect.colStatusWidth; height: parent.height
                                                Text {
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    text: model.item ? model.item.status : "--"
                                                    color: filesListView.currentIndex === index ? ColorPalette.selectionText : ColorPalette.textPrimary
                                                    font.pixelSize: 12 * App.fontScale
                                                }
                                            }

                                            Item {
                                                width: fileTableRect.colTimeLeftWidth; height: parent.height
                                                Text {
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    text: model.item ? model.item.timeLeft : "--"
                                                    color: filesListView.currentIndex === index ? ColorPalette.selectionText : ColorPalette.textPrimary
                                                    font.pixelSize: 12 * App.fontScale
                                                }
                                            }
                                        }
                                    }

                                    // Sync horizontal scroll: when delegate width > listview width, ListView
                                    // ── itself doesn't scroll horizontally the delegate Row is just clipped. ──
                                    // Mirror hScroll offset into contentX of a horizontal Flickable instead.
                                    // Actually we clip via the outer approach: translate the Row by -hScroll.
                                    // Simpler: use contentX on the ListView (it IS a Flickable).
                                    contentX: hScroll.position * Math.max(0, fileTableRect.totalRowWidth - filesListView.width)
                                }

                                ScrollBar {
                                    id: hScroll
                                    anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                                    orientation: Qt.Horizontal
                                    visible: fileTableRect.totalRowWidth > fileTableRect.width
                                    policy: ScrollBar.AsNeeded
                                }

                            // Empty-state overlay
                            Text {
                                anchors.centerIn: parent
                                text: {
                                    if (!root.selectedQueue) return qsTr("No queue selected")
                                    for (var i = 0; i < App.downloadModel.rowCount(); i++) {
                                        var item = App.downloadModel.data(App.downloadModel.index(i, 0), Qt.UserRole + 2) // ItemRole
                                        if (item && item.queueId === root.selectedQueue.id) {
                                            return ""
                                        }
                                    }
                                    return qsTr("No files in queue")
                                }
                                color: ColorPalette.textDisabled
                                font.pixelSize: 12 * App.fontScale
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
                            background: Rectangle { color: parent.pressed ? ColorPalette.toolbarPressBg : (parent.hovered ? ColorPalette.toolbarHoverBg : ColorPalette.panelBg); radius: 0; border.color: ColorPalette.border; border.width: 1; opacity: parent.enabled ? 1.0 : 0.5 }
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
                            background: Rectangle { color: parent.pressed ? ColorPalette.toolbarPressBg : (parent.hovered ? ColorPalette.toolbarHoverBg : ColorPalette.panelBg); radius: 0; border.color: ColorPalette.border; border.width: 1; opacity: parent.enabled ? 1.0 : 0.5 }
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
                            text: qsTr("Delete")
                            enabled: filesListView.currentIndex >= 0
                            background: Rectangle { color: parent.pressed ? ColorPalette.toolbarPressBg : (parent.hovered ? ColorPalette.toolbarHoverBg : ColorPalette.panelBg); radius: 0; border.color: ColorPalette.border; border.width: 1; opacity: parent.enabled ? 1.0 : 0.5 }
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

                // ── DOWNLOAD LIMITS TAB ──────────────────────────────────
                ColumnLayout {
                    spacing: 12

                    Item { height: 4 }

                    StyledCheckBox {
                        id: limitsEnabledCb
                        Layout.leftMargin: 12
                        text: qsTr("Download limits")
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

                        Text { text: qsTr("Download no more than"); color: ColorPalette.textPrimary; font.pixelSize: 12 * App.fontScale }
                        Rectangle {
                            width: 60; height: 26; radius: 2
                            color: ColorPalette.inputBg; border.color: limitMbInput.activeFocus ? "#4488dd" : ColorPalette.border
                            TextInput {
                                id: limitMbInput
                                anchors { fill: parent; leftMargin: 6; rightMargin: 6 }
                                text: root.selectedQueue ? String(root.selectedQueue.downloadLimitMBytes) : "200"
                                color: ColorPalette.textPrimary; font.pixelSize: 12 * App.fontScale
                                horizontalAlignment: TextInput.AlignHCenter; verticalAlignment: TextInput.AlignVCenter
                                validator: IntValidator { bottom: 1; top: 100000 }
                                onTextEdited: { if (root.selectedQueue) { var v = parseInt(text, 10); if (!isNaN(v) && v >= 1) { root.selectedQueue.downloadLimitMBytes = v; root.checkForChanges() } } }
                            }
                        }
                        Text { text: qsTr("MBytes"); color: ColorPalette.textPrimary; font.pixelSize: 12 * App.fontScale }
                        Text { text: qsTr("every"); color: ColorPalette.textPrimary; font.pixelSize: 12 * App.fontScale }
                        Rectangle {
                            width: 46; height: 26; radius: 2
                            color: ColorPalette.inputBg; border.color: limitHrInput.activeFocus ? "#4488dd" : ColorPalette.border
                            TextInput {
                                id: limitHrInput
                                anchors { fill: parent; leftMargin: 6; rightMargin: 6 }
                                text: root.selectedQueue ? String(root.selectedQueue.downloadLimitHours) : "5"
                                color: ColorPalette.textPrimary; font.pixelSize: 12 * App.fontScale
                                horizontalAlignment: TextInput.AlignHCenter; verticalAlignment: TextInput.AlignVCenter
                                validator: IntValidator { bottom: 1; top: 24 }
                                onTextEdited: { if (root.selectedQueue) { var v = parseInt(text, 10); if (!isNaN(v) && v >= 1) { root.selectedQueue.downloadLimitHours = v; root.checkForChanges() } } }
                            }
                        }
                        Text { text: qsTr("hours"); color: ColorPalette.textPrimary; font.pixelSize: 12 * App.fontScale }
                        Item { Layout.fillWidth: true }
                    }

                    StyledCheckBox {
                        Layout.leftMargin: 12
                        text: qsTr("Show warning before stopping downloads")
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

                StyledCheckBox {
                    id: dlLimitsEnabledCb
                    Layout.leftMargin: 12
                    text: qsTr("Download limits")
                    topPadding: 0
                    bottomPadding: 0
                    checked: root.selectedQueue ? root.selectedQueue.hasDownloadLimits : false
                    onToggled: { if (root.selectedQueue) { root.selectedQueue.hasDownloadLimits = checked; App.saveQueues() } }
                }

                RowLayout {
                    Layout.leftMargin: 28
                    spacing: 8
                    enabled: dlLimitsEnabledCb.checked
                    opacity: enabled ? 1.0 : 0.5

                    Text { text: qsTr("Download no more than"); color: ColorPalette.textPrimary; font.pixelSize: 12 * App.fontScale }
                    Rectangle {
                        width: 60; height: 26; radius: 2
                        color: ColorPalette.inputBg; border.color: dlLimitMbInput.activeFocus ? "#4488dd" : ColorPalette.border
                        TextInput {
                            id: dlLimitMbInput
                            anchors { fill: parent; leftMargin: 6; rightMargin: 6 }
                            text: root.selectedQueue ? String(root.selectedQueue.downloadLimitMBytes) : "200"
                            color: ColorPalette.textPrimary; font.pixelSize: 12 * App.fontScale
                            horizontalAlignment: TextInput.AlignHCenter; verticalAlignment: TextInput.AlignVCenter
                            validator: IntValidator { bottom: 1; top: 100000 }
                            onTextEdited: { if (root.selectedQueue) { var v = parseInt(text, 10); if (!isNaN(v) && v >= 1) { root.selectedQueue.downloadLimitMBytes = v; App.saveQueues() } } }
                        }
                    }
                    Text { text: qsTr("MBytes"); color: ColorPalette.textPrimary; font.pixelSize: 12 * App.fontScale }
                    Text { text: qsTr("every"); color: ColorPalette.textPrimary; font.pixelSize: 12 * App.fontScale }
                    Rectangle {
                        width: 46; height: 26; radius: 2
                        color: ColorPalette.inputBg; border.color: dlLimitHrInput.activeFocus ? "#4488dd" : ColorPalette.border
                        TextInput {
                            id: dlLimitHrInput
                            anchors { fill: parent; leftMargin: 6; rightMargin: 6 }
                            text: root.selectedQueue ? String(root.selectedQueue.downloadLimitHours) : "5"
                            color: ColorPalette.textPrimary; font.pixelSize: 12 * App.fontScale
                            horizontalAlignment: TextInput.AlignHCenter; verticalAlignment: TextInput.AlignVCenter
                            validator: IntValidator { bottom: 1; top: 24 }
                            onTextEdited: { if (root.selectedQueue) { var v = parseInt(text, 10); if (!isNaN(v) && v >= 1) { root.selectedQueue.downloadLimitHours = v; App.saveQueues() } } }
                        }
                    }
                    Text { text: qsTr("hours"); color: ColorPalette.textPrimary; font.pixelSize: 12 * App.fontScale }
                    Item { Layout.fillWidth: true }
                }

                StyledCheckBox {
                    Layout.leftMargin: 12
                    text: qsTr("Show warning before stopping downloads")
                    topPadding: 0
                    bottomPadding: 0
                    checked: root.selectedQueue ? root.selectedQueue.warnBeforeStopping : true
                    onToggled: { if (root.selectedQueue) { root.selectedQueue.warnBeforeStopping = checked; App.saveQueues() } }
                }

                Item { Layout.fillHeight: true }
            }

            // Separator
            Rectangle { Layout.fillWidth: true; height: 1; color: ColorPalette.border; Layout.topMargin: 4 }

            // Bottom buttons
            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: 8
                spacing: 8

                DlgButton {
                    text: qsTr("Start now")
                    Layout.preferredWidth: 130
                    Layout.preferredHeight: 32
                    enabled: root.selectedQueue !== null
                    primary: true
                    onClicked: { if (root.selectedQueue) App.startQueue(root.selectedQueue.id) }
                }
                DlgButton {
                    text: qsTr("Stop")
                    Layout.preferredWidth: 90
                    Layout.preferredHeight: 32
                    enabled: root.selectedQueue !== null
                    opacity: enabled ? 1.0 : 0.5
                    onClicked: { if (root.selectedQueue) App.stopQueue(root.selectedQueue.id) }
                }

                Item { Layout.fillWidth: true }

                DlgButton {
                    text: qsTr("Apply")
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
                    text: qsTr("Close")
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

    // ── New Queue Dialog ─────────────────────────────────────────────────
    Dialog {
        id: newQueueDialog
        title: qsTr("New Queue")
        modal: true
        anchors.centerIn: Overlay.overlay
        width: 420

        Material.primary: "#4488dd"
        Material.accent: "#4488dd"

        background: Rectangle {
            color: ColorPalette.windowBg
            border.color: ColorPalette.border
            border.width: 1
            radius: 0
        }

        contentItem: Rectangle {
            color: ColorPalette.windowBg
            ColumnLayout {
                anchors { fill: parent; margins: 16 }
                spacing: 12

                Text {
                    Layout.fillWidth: true
                    text: qsTr("Enter a name for the new queue that will be displayed in the list of queues")
                    color: ColorPalette.textPrimary
                    wrapMode: Text.Wrap
                    font.pixelSize: 12 * App.fontScale
                }

                Rectangle {
                    Layout.fillWidth: true
                    height: 32
                    color: ColorPalette.panelBg
                    border.color: ColorPalette.border
                    border.width: 1
                    radius: 0

                    TextInput {
                        id: newQueueNameField
                        anchors { fill: parent; leftMargin: 8; rightMargin: 8 }
                        verticalAlignment: TextInput.AlignVCenter
                        color: ColorPalette.textPrimary
                        selectionColor: "#4488dd"
                        Keys.onReturnPressed: confirmNewQueue()

                        Text {
                            text: qsTr("Queue name")
                            color: ColorPalette.textDisabled
                            anchors { left: parent.left; leftMargin: 2; verticalCenter: parent.verticalCenter }
                            visible: newQueueNameField.length === 0
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    Item { Layout.fillWidth: true }
                    DlgButton {
                        text: qsTr("OK")
                        primary: true
                        onClicked: confirmNewQueue()
                    }
                    DlgButton {
                        text: qsTr("Cancel")
                        onClicked: { newQueueNameField.text = ""; newQueueDialog.close() }
                    }
                }
            }
        }
    }

    // ── File picker ──────────────────────────────────────────────────────
    FileDialog {
        id: fileDialog
        title: qsTr("Select file to open when done")
        onAccepted: {
            if (root.selectedQueue)
                root.selectedQueue.openFilePath = file.toString().replace("file:///", "")
        }
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
        if (visible) _centerOnOwner()
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
