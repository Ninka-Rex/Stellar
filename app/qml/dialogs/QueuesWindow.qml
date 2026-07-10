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
import Qt.labs.platform
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts
import com.stellar.app 1.0

// The Queues window: queue list on the left, live-edited settings and the
// per-queue file list on the right. Every control writes its Queue property
// immediately; a single debounce timer persists to queues.json — there is no
// Apply/Cancel state machine.
Window {
    id: root
    title: qsTr("Queues")
    width: 920
    height: 500
    minimumWidth: 860
    minimumHeight: 460
    flags: Qt.Window | Qt.WindowTitleHint | Qt.WindowSystemMenuHint | Qt.WindowCloseButtonHint
    color: ColorPalette.windowBg

    Material.theme: ColorPalette.materialTheme
    Material.foreground: ColorPalette.textPrimary
    Material.background: ColorPalette.materialBg
    Material.primary: ColorPalette.accent
    Material.accent: ColorPalette.accent

    property var queueModel: App.queueModel
    property var selectedQueue: null
    property var _fileCtxItem: null

    // Debounced live-apply: any edit arms this; one flush writes every queue.
    Timer {
        id: saveDebounce
        interval: 500
        onTriggered: App.saveQueues()
    }
    function queueEdited() { saveDebounce.restart() }

    function selectQueueAt(index) {
        queueList.currentIndex = index
        root.selectedQueue = index >= 0 ? queueModel.queueAt(index) : null
    }

    function _ensureSelection() {
        if (root.selectedQueue !== null || queueModel.rowCount() === 0)
            return
        var mainIdx = 0
        for (var i = 0; i < queueModel.rowCount(); i++) {
            var q = queueModel.queueAt(i)
            if (q && q.id === "main-download") { mainIdx = i; break }
        }
        selectQueueAt(mainIdx)
    }

    // ── Drag proxy for file-list → queue-list drag-drop ─────────────────
    // Invisible 1×1 item that travels with the cursor; DropAreas on queue
    // rows read dragDownloadId / dragDownloadIds off drop.source.
    Item {
        id: queuesDragProxy
        width: 1; height: 1
        visible: false
        z: 9999
        parent: root.contentItem
        Drag.keys: ["text/downloadId"]
        Drag.hotSpot: Qt.point(0, 0)
        property string dragDownloadId: ""
        property var    dragDownloadIds: []
        property string dragFilename: ""

        Rectangle {
            visible: queuesDragProxy.visible && queuesDragProxy.dragFilename !== ""
            width: dragLabel.implicitWidth + 16; height: 22
            radius: 3
            color: ColorPalette.selectionBg
            border.color: ColorPalette.accent; border.width: 1
            x: 8; y: 8
            Text {
                id: dragLabel
                anchors.centerIn: parent
                text: queuesDragProxy.dragFilename
                color: ColorPalette.textPrimary
                font.pixelSize: 11 * App.fontScale
                elide: Text.ElideMiddle
                maximumLineCount: 1
            }
        }
    }

    RowLayout {
        anchors { fill: parent; margins: 12 }
        spacing: 12

        // ── Left: queue list ────────────────────────────────────────────
        ColumnLayout {
            Layout.preferredWidth: 190
            Layout.minimumWidth: 190
            Layout.maximumWidth: 190
            Layout.fillHeight: true
            spacing: 6

            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                color: ColorPalette.panelBg
                border.color: ColorPalette.border
                border.width: 1

                ListView {
                    id: queueList
                    anchors { fill: parent; margins: 4 }
                    model: root.queueModel
                    clip: true
                    spacing: 2
                    currentIndex: -1

                    delegate: Rectangle {
                        width: queueList.width
                        height: 30
                        radius: 3
                        color: queueList.currentIndex === index
                             ? ColorPalette.selectionBg
                             : (queueDropArea.containsDrag ? ColorPalette.hoverBg : "transparent")
                        border.color: (queueList.currentIndex === index || queueDropArea.containsDrag)
                                    ? ColorPalette.accent : "transparent"
                        border.width: 1

                        Row {
                            anchors { verticalCenter: parent.verticalCenter; left: parent.left; leftMargin: 8 }
                            spacing: 6

                            Image {
                                width: 16; height: 16
                                sourceSize.width: 16; sourceSize.height: 16
                                fillMode: Image.PreserveAspectFit
                                anchors.verticalCenter: parent.verticalCenter
                                source: model.queueId === "main-download"
                                      ? "../icons/main_queue.svg" : "../icons/custom_queue.svg"
                            }

                            Text {
                                text: model.queueName || ""
                                color: queueList.currentIndex === index
                                     ? ColorPalette.selectionText : ColorPalette.textPrimary
                                font.pixelSize: 12 * App.fontScale
                                elide: Text.ElideRight
                                width: queueList.width - 50
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            acceptedButtons: Qt.LeftButton
                            onClicked: root.selectQueueAt(index)
                        }

                        // Right-click menu (TapHandler — MouseArea would steal
                        // from the selection MouseArea above; see CLAUDE.md).
                        TapHandler {
                            acceptedButtons: Qt.RightButton
                            onTapped: {
                                root.selectQueueAt(index)
                                queueContextMenu.popup()
                            }
                        }

                        DropArea {
                            id: queueDropArea
                            anchors.fill: parent
                            keys: ["text/downloadId"]
                            onDropped: (drop) => {
                                if (!drop.source) return
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

            DlgButton {
                Layout.fillWidth: true
                Layout.preferredHeight: 30
                text: qsTr("New queue")
                onClicked: {
                    App.createQueue(qsTr("New queue"))
                    root.selectQueueAt(queueModel.rowCount() - 1)
                    nameField.forceActiveFocus()
                    nameField.selectAll()
                }
            }
        }

        // ── Right: selected queue ───────────────────────────────────────
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 8
            visible: root.selectedQueue !== null

            // Header: inline-editable name + Start/Stop
            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Rectangle {
                    Layout.fillWidth: true
                    height: 30
                    color: nameField.activeFocus ? ColorPalette.inputBg : "transparent"
                    border.color: nameField.activeFocus ? ColorPalette.borderFocus
                                : (nameHover.hovered ? ColorPalette.border : "transparent")
                    radius: 3

                    HoverHandler { id: nameHover }

                    TextInput {
                        id: nameField
                        anchors { fill: parent; leftMargin: 6; rightMargin: 6 }
                        verticalAlignment: TextInput.AlignVCenter
                        color: ColorPalette.textHeader
                        selectionColor: ColorPalette.accent
                        font.pixelSize: 15 * App.fontScale
                        font.bold: true
                        text: root.selectedQueue ? root.selectedQueue.name : ""
                        onEditingFinished: {
                            if (root.selectedQueue && text.trim().length > 0
                                && text.trim() !== root.selectedQueue.name) {
                                root.selectedQueue.name = text.trim()
                                root.queueEdited()
                            }
                        }
                    }

                    ThemedToolTip {
                        visible: nameHover.hovered && !nameField.activeFocus
                        text: qsTr("Click to rename")
                    }
                }

                DlgButton {
                    text: qsTr("Start")
                    primary: true
                    Layout.preferredHeight: 28
                    onClicked: if (root.selectedQueue) App.startQueue(root.selectedQueue.id)
                }
                DlgButton {
                    text: qsTr("Stop")
                    Layout.preferredHeight: 28
                    onClicked: if (root.selectedQueue) App.stopQueue(root.selectedQueue.id)
                }
            }

            // ── Settings: two compact columns ───────────────────────────
            RowLayout {
                Layout.fillWidth: true
                spacing: 24

                // Column A — Schedule
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    Layout.alignment: Qt.AlignTop
                    spacing: 6

                    SectionHeader { text: qsTr("Schedule") }

                    StyledCheckBox {
                        text: qsTr("Start this queue on a schedule")
                        checked: root.selectedQueue ? root.selectedQueue.scheduleMode !== 0 : false
                        onToggled: {
                            if (!root.selectedQueue) return
                            root.selectedQueue.scheduleMode = checked ? 1 + modeCombo.currentIndex : 0
                            root.queueEdited()
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.leftMargin: 22
                        spacing: 6
                        visible: root.selectedQueue ? root.selectedQueue.scheduleMode !== 0 : false

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8
                            StyledComboBox {
                                id: modeCombo
                                Layout.preferredWidth: 130
                                Layout.preferredHeight: 24
                                font.pixelSize: 12 * App.fontScale
                                model: [qsTr("One time"), qsTr("Daily"), qsTr("Repeat every…")]
                                currentIndex: root.selectedQueue
                                            ? Math.max(0, root.selectedQueue.scheduleMode - 1) : 0
                                onActivated: {
                                    if (!root.selectedQueue) return
                                    root.selectedQueue.scheduleMode = currentIndex + 1
                                    root.queueEdited()
                                }
                            }
                            Text {
                                text: qsTr("at")
                                color: ColorPalette.textPrimary
                                font.pixelSize: 12 * App.fontScale
                                visible: root.selectedQueue ? root.selectedQueue.scheduleMode !== 3 : false
                            }
                            TimeField {
                                visible: root.selectedQueue ? root.selectedQueue.scheduleMode !== 3 : false
                                minutes: root.selectedQueue ? root.selectedQueue.startTimeMinutes : 23 * 60
                                onEdited: (m) => {
                                    if (!root.selectedQueue) return
                                    root.selectedQueue.startTimeMinutes = m
                                    root.queueEdited()
                                }
                            }
                            Item { Layout.fillWidth: true }
                        }

                        DayOfWeekSelector {
                            visible: root.selectedQueue ? root.selectedQueue.scheduleMode === 2 : false
                            daysMask: root.selectedQueue ? root.selectedQueue.scheduleDaysMask : 0x7F
                            onToggled: (mask) => {
                                if (!root.selectedQueue) return
                                root.selectedQueue.scheduleDaysMask = mask
                                root.queueEdited()
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 6
                            visible: root.selectedQueue ? root.selectedQueue.scheduleMode === 3 : false
                            NumberField {
                                value: root.selectedQueue ? root.selectedQueue.intervalHours : 2
                                minValue: 0; maxValue: 999
                                onEdited: (v) => {
                                    if (!root.selectedQueue) return
                                    root.selectedQueue.intervalHours = v
                                    root.queueEdited()
                                }
                            }
                            Text { text: qsTr("hours"); color: ColorPalette.textPrimary; font.pixelSize: 12 * App.fontScale }
                            NumberField {
                                value: root.selectedQueue ? root.selectedQueue.intervalMinutes : 0
                                minValue: 0; maxValue: 59
                                onEdited: (v) => {
                                    if (!root.selectedQueue) return
                                    root.selectedQueue.intervalMinutes = v
                                    root.queueEdited()
                                }
                            }
                            Text { text: qsTr("minutes"); color: ColorPalette.textPrimary; font.pixelSize: 12 * App.fontScale }
                            Item { Layout.fillWidth: true }
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        StyledCheckBox {
                            id: stopAtCheck
                            Layout.fillWidth: false
                            text: qsTr("Stop the queue at")
                            checked: root.selectedQueue ? root.selectedQueue.hasStopTime : false
                            onToggled: {
                                if (!root.selectedQueue) return
                                root.selectedQueue.hasStopTime = checked
                                root.queueEdited()
                            }
                        }
                        TimeField {
                            enabled: stopAtCheck.checked
                            opacity: enabled ? 1.0 : 0.5
                            minutes: root.selectedQueue ? root.selectedQueue.stopTimeMinutes : 7 * 60 + 30
                            onEdited: (m) => {
                                if (!root.selectedQueue) return
                                root.selectedQueue.stopTimeMinutes = m
                                root.queueEdited()
                            }
                        }
                        Item { Layout.fillWidth: true }
                    }

                    StyledCheckBox {
                        text: qsTr("Start this queue when Stellar starts")
                        checked: root.selectedQueue ? root.selectedQueue.startOnAppStartup : false
                        onToggled: {
                            if (!root.selectedQueue) return
                            root.selectedQueue.startOnAppStartup = checked
                            root.queueEdited()
                        }
                    }

                    SectionHeader { text: qsTr("Limits"); Layout.topMargin: 4 }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6
                        Text { text: qsTr("Run at the same time:"); color: ColorPalette.textPrimary; font.pixelSize: 12 * App.fontScale }
                        NumberField {
                            value: root.selectedQueue ? root.selectedQueue.maxConcurrentDownloads : 3
                            minValue: 1; maxValue: 99
                            onEdited: (v) => {
                                if (!root.selectedQueue) return
                                root.selectedQueue.maxConcurrentDownloads = v
                                root.queueEdited()
                            }
                        }
                        Text { text: qsTr("downloads"); color: ColorPalette.textPrimary; font.pixelSize: 12 * App.fontScale }
                        NumberField {
                            value: root.selectedQueue ? root.selectedQueue.maxConcurrentTorrents : 2
                            minValue: 1; maxValue: 99
                            onEdited: (v) => {
                                if (!root.selectedQueue) return
                                root.selectedQueue.maxConcurrentTorrents = v
                                root.queueEdited()
                            }
                        }
                        Text { text: qsTr("torrents"); color: ColorPalette.textPrimary; font.pixelSize: 12 * App.fontScale }
                        Item { Layout.fillWidth: true }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 4
                        StyledCheckBox {
                            id: limitCheck
                            text: qsTr("Pause the queue after")
                            checked: root.selectedQueue ? root.selectedQueue.hasDownloadLimits : false
                            onToggled: {
                                if (!root.selectedQueue) return
                                root.selectedQueue.hasDownloadLimits = checked
                                root.queueEdited()
                            }
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            Layout.leftMargin: 22
                            spacing: 6
                            NumberField {
                                enabled: limitCheck.checked
                                opacity: enabled ? 1.0 : 0.5
                                fieldWidth: 62
                                value: root.selectedQueue ? root.selectedQueue.downloadLimitMBytes : 200
                                minValue: 1; maxValue: 9999999
                                onEdited: (v) => {
                                    if (!root.selectedQueue) return
                                    root.selectedQueue.downloadLimitMBytes = v
                                    root.queueEdited()
                                }
                            }
                            Text { text: qsTr("MB every"); color: ColorPalette.textPrimary; font.pixelSize: 12 * App.fontScale }
                            NumberField {
                                enabled: limitCheck.checked
                                opacity: enabled ? 1.0 : 0.5
                                value: root.selectedQueue ? root.selectedQueue.downloadLimitHours : 5
                                minValue: 1; maxValue: 999
                                onEdited: (v) => {
                                    if (!root.selectedQueue) return
                                    root.selectedQueue.downloadLimitHours = v
                                    root.queueEdited()
                                }
                            }
                            Text { text: qsTr("hours"); color: ColorPalette.textPrimary; font.pixelSize: 12 * App.fontScale }
                            Item { Layout.fillWidth: true }
                        }
                    }
                }

                // Column B — after the queue finishes
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    Layout.alignment: Qt.AlignTop
                    spacing: 6

                    SectionHeader { text: qsTr("When all downloads finish") }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6
                        StyledCheckBox {
                            id: retryCheck
                            Layout.fillWidth: false
                            text: qsTr("Retry failed downloads up to")
                            checked: root.selectedQueue ? root.selectedQueue.hasMaxRetries : false
                            onToggled: {
                                if (!root.selectedQueue) return
                                root.selectedQueue.hasMaxRetries = checked
                                root.queueEdited()
                            }
                        }
                        NumberField {
                            enabled: retryCheck.checked
                            opacity: enabled ? 1.0 : 0.5
                            value: root.selectedQueue ? root.selectedQueue.maxRetries : 10
                            minValue: 1; maxValue: 99
                            onEdited: (v) => {
                                if (!root.selectedQueue) return
                                root.selectedQueue.maxRetries = v
                                root.queueEdited()
                            }
                        }
                        Text { text: qsTr("times"); color: ColorPalette.textPrimary; font.pixelSize: 12 * App.fontScale }
                        Item { Layout.fillWidth: true }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6
                        StyledCheckBox {
                            id: openFileCheck
                            Layout.fillWidth: false
                            text: qsTr("Open")
                            checked: root.selectedQueue ? root.selectedQueue.openFileWhenDone : false
                            onToggled: {
                                if (!root.selectedQueue) return
                                root.selectedQueue.openFileWhenDone = checked
                                root.queueEdited()
                            }
                        }
                        Rectangle {
                            Layout.fillWidth: true
                            height: 24
                            color: ColorPalette.inputBg
                            border.color: openPathField.activeFocus ? ColorPalette.borderFocus : ColorPalette.border
                            radius: 3
                            enabled: openFileCheck.checked
                            opacity: enabled ? 1.0 : 0.5
                            TextInput {
                                id: openPathField
                                anchors { fill: parent; leftMargin: 6; rightMargin: 6 }
                                verticalAlignment: TextInput.AlignVCenter
                                color: ColorPalette.textPrimary
                                selectionColor: ColorPalette.accent
                                font.pixelSize: 12 * App.fontScale
                                clip: true
                                text: root.selectedQueue ? root.selectedQueue.openFilePath : ""
                                onEditingFinished: {
                                    if (!root.selectedQueue) return
                                    root.selectedQueue.openFilePath = text
                                    root.queueEdited()
                                }
                            }
                        }
                        DlgButton {
                            text: qsTr("Browse…")
                            Layout.preferredHeight: 24
                            enabled: openFileCheck.checked
                            onClicked: openFileDialog.open()
                        }
                    }

                    StyledCheckBox {
                        text: qsTr("Exit Stellar")
                        checked: root.selectedQueue ? root.selectedQueue.exitIDMWhenDone : false
                        onToggled: {
                            if (!root.selectedQueue) return
                            root.selectedQueue.exitIDMWhenDone = checked
                            root.queueEdited()
                        }
                    }
                    StyledCheckBox {
                        id: shutdownCheck
                        text: qsTr("Shut down the computer")
                        checked: root.selectedQueue ? root.selectedQueue.turnOffComputerWhenDone : false
                        onToggled: {
                            if (!root.selectedQueue) return
                            root.selectedQueue.turnOffComputerWhenDone = checked
                            root.queueEdited()
                        }
                    }
                    StyledCheckBox {
                        Layout.leftMargin: 22
                        enabled: shutdownCheck.checked
                        text: qsTr("Force programs to close")
                        checked: root.selectedQueue ? root.selectedQueue.forceProcessesToTerminate : false
                        onToggled: {
                            if (!root.selectedQueue) return
                            root.selectedQueue.forceProcessesToTerminate = checked
                            root.queueEdited()
                        }
                    }
                    StyledCheckBox {
                        Layout.leftMargin: 22
                        Layout.fillWidth: true
                        enabled: limitCheck.checked
                        text: qsTr("Show a warning when the limit pauses downloads")
                        checked: root.selectedQueue ? root.selectedQueue.warnBeforeStopping : true
                        visible: limitCheck.checked
                        onToggled: {
                            if (!root.selectedQueue) return
                            root.selectedQueue.warnBeforeStopping = checked
                            root.queueEdited()
                        }
                    }
                }
            }

            // ── Files in this queue ─────────────────────────────────────
            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: 2
                spacing: 8

                SectionHeader {
                    Layout.fillWidth: true
                    text: qsTr("Files in this queue (%1)").arg(queueItems.count)
                }
                DlgButton {
                    id: moveUpBtn
                    text: "↑"
                    Layout.preferredWidth: 30
                    Layout.preferredHeight: 22
                    enabled: filesList.currentItem !== null && filesList.currentIndex > 0
                    onClicked: {
                        var itm = filesList.currentItem ? filesList.currentItem.rowItem : null
                        if (itm) { App.moveUpInQueue(itm.id); filesList.currentIndex-- }
                    }
                    ThemedToolTip { visible: moveUpBtn.hovered; text: qsTr("Move up in the queue") }
                }
                DlgButton {
                    id: moveDownBtn
                    text: "↓"
                    Layout.preferredWidth: 30
                    Layout.preferredHeight: 22
                    enabled: filesList.currentItem !== null && filesList.currentIndex < filesList.count - 1
                    onClicked: {
                        var itm = filesList.currentItem ? filesList.currentItem.rowItem : null
                        if (itm) { App.moveDownInQueue(itm.id); filesList.currentIndex++ }
                    }
                    ThemedToolTip { visible: moveDownBtn.hovered; text: qsTr("Move down in the queue") }
                }
                DlgButton {
                    text: qsTr("Remove from queue")
                    Layout.preferredHeight: 22
                    enabled: filesList.currentItem !== null
                    onClicked: {
                        var itm = filesList.currentItem ? filesList.currentItem.rowItem : null
                        if (itm) App.setDownloadQueue(itm.id, "")
                    }
                }
            }

            // File table — mirrors the main window's download table styling:
            // 26 px dividerBg header, 26 px alternating rows.
            Rectangle {
                id: fileTable
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.minimumHeight: 90
                color: ColorPalette.windowBg
                border.color: ColorPalette.border
                border.width: 1

                // Proportional column widths (no per-column resize needed here)
                readonly property real wSize: 90
                readonly property real wStatus: 110
                readonly property real wTimeLeft: 90
                readonly property real wName: width - wSize - wStatus - wTimeLeft - 34

                QueueItemsModel {
                    id: queueItems
                    sourceModel: App.downloadModel
                    queueId: root.selectedQueue ? root.selectedQueue.id : " none"
                }

                ColumnLayout {
                    anchors { fill: parent; margins: 1 }
                    spacing: 0

                    Rectangle {
                        Layout.fillWidth: true
                        height: 26
                        color: ColorPalette.dividerBg

                        Row {
                            anchors.fill: parent
                            leftPadding: 34
                            Text {
                                width: fileTable.wName; height: parent.height
                                verticalAlignment: Text.AlignVCenter
                                text: qsTr("File Name")
                                color: ColorPalette.textPrimary
                                font.pixelSize: 12 * App.fontScale
                            }
                            Text {
                                width: fileTable.wSize; height: parent.height
                                verticalAlignment: Text.AlignVCenter
                                text: qsTr("Size")
                                color: ColorPalette.textPrimary
                                font.pixelSize: 12 * App.fontScale
                            }
                            Text {
                                width: fileTable.wStatus; height: parent.height
                                verticalAlignment: Text.AlignVCenter
                                text: qsTr("Status")
                                color: ColorPalette.textPrimary
                                font.pixelSize: 12 * App.fontScale
                            }
                            Text {
                                width: fileTable.wTimeLeft; height: parent.height
                                verticalAlignment: Text.AlignVCenter
                                text: qsTr("Time left")
                                color: ColorPalette.textPrimary
                                font.pixelSize: 12 * App.fontScale
                            }
                        }
                    }

                    Rectangle { Layout.fillWidth: true; height: 1; color: ColorPalette.border }

                    ListView {
                        id: filesList
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        model: queueItems
                        clip: true
                        currentIndex: -1
                        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                        delegate: Rectangle {
                            id: fileRow
                            required property var item
                            required property int index
                            readonly property var rowItem: item
                            readonly property bool _sel: filesList.currentIndex === index

                            width: filesList.width
                            height: 26
                            color: _sel ? ColorPalette.selectionBg
                                 : (fileRowMouse.containsMouse ? ColorPalette.hoverBg
                                 : (index % 2 === 0 ? ColorPalette.windowBg : ColorPalette.rowAltBg))

                            MouseArea {
                                id: fileRowMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                drag.target: queuesDragProxy
                                onClicked: filesList.currentIndex = fileRow.index
                                onPressed: {
                                    if (!fileRow.rowItem) return
                                    filesList.currentIndex = fileRow.index
                                    queuesDragProxy.dragDownloadId  = fileRow.rowItem.id
                                    queuesDragProxy.dragDownloadIds = [fileRow.rowItem.id]
                                    queuesDragProxy.dragFilename    = fileRow.rowItem.filename
                                    var pos = fileRowMouse.mapToItem(root.contentItem, mouseX, mouseY)
                                    queuesDragProxy.x = pos.x
                                    queuesDragProxy.y = pos.y
                                }
                                onPositionChanged: {
                                    if (drag.active && queuesDragProxy.dragDownloadId) {
                                        queuesDragProxy.visible = true
                                        queuesDragProxy.Drag.active = true
                                        var pos = fileRowMouse.mapToItem(root.contentItem, mouseX, mouseY)
                                        queuesDragProxy.x = pos.x
                                        queuesDragProxy.y = pos.y
                                    }
                                }
                                onReleased: {
                                    if (queuesDragProxy.visible) {
                                        queuesDragProxy.Drag.drop()
                                        queuesDragProxy.Drag.active = false
                                        queuesDragProxy.visible = false
                                        queuesDragProxy.dragDownloadId  = ""
                                        queuesDragProxy.dragDownloadIds = []
                                        queuesDragProxy.dragFilename    = ""
                                    }
                                }
                            }

                            // Right-click menu (TapHandler — MouseArea would steal
                            // from the drag/selection MouseArea above; see CLAUDE.md).
                            TapHandler {
                                acceptedButtons: Qt.RightButton
                                onTapped: {
                                    filesList.currentIndex = fileRow.index
                                    root._fileCtxItem = fileRow.rowItem
                                    fileContextMenu.popup()
                                }
                            }

                            Row {
                                anchors.fill: parent

                                Item {
                                    width: 34; height: parent.height
                                    Image {
                                        anchors.centerIn: parent
                                        width: 16; height: 16
                                        source: fileRow.rowItem
                                              ? "image://fileicon/" + (fileRow.rowItem.savePath + "/" + fileRow.rowItem.filename).replace(/\\/g, "/")
                                              : ""
                                        sourceSize: Qt.size(16, 16)
                                        fillMode: Image.PreserveAspectFit
                                        smooth: true
                                    }
                                }
                                Item {
                                    width: fileTable.wName; height: parent.height
                                    Text {
                                        anchors { left: parent.left; right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter }
                                        text: fileRow.rowItem ? fileRow.rowItem.filename : ""
                                        color: fileRow._sel ? ColorPalette.selectionText : ColorPalette.textPrimary
                                        font.pixelSize: 12 * App.fontScale
                                        elide: Text.ElideMiddle
                                    }
                                }
                                Item {
                                    width: fileTable.wSize; height: parent.height
                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: {
                                            if (!fileRow.rowItem || fileRow.rowItem.totalBytes <= 0) return ""
                                            var b = fileRow.rowItem.totalBytes
                                            if (b < 1048576) return (b / 1024).toFixed(1) + " KB"
                                            if (b < 1073741824) return (b / 1048576).toFixed(1) + " MB"
                                            return (b / 1073741824).toFixed(2) + " GB"
                                        }
                                        color: fileRow._sel ? ColorPalette.selectionText : ColorPalette.textPrimary
                                        font.pixelSize: 12 * App.fontScale
                                    }
                                }
                                Item {
                                    width: fileTable.wStatus; height: parent.height
                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: fileRow.rowItem ? fileRow.rowItem.status : ""
                                        color: fileRow._sel ? ColorPalette.selectionText : ColorPalette.textPrimary
                                        font.pixelSize: 12 * App.fontScale
                                    }
                                }
                                Item {
                                    width: fileTable.wTimeLeft; height: parent.height
                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: fileRow.rowItem ? fileRow.rowItem.timeLeft : ""
                                        color: fileRow._sel ? ColorPalette.selectionText : ColorPalette.textPrimary
                                        font.pixelSize: 12 * App.fontScale
                                    }
                                }
                            }
                        }

                        Text {
                            anchors.centerIn: parent
                            visible: filesList.count === 0
                            text: qsTr("No files in this queue.\nDrag downloads here or use “Move to Queue” in the download list.")
                            horizontalAlignment: Text.AlignHCenter
                            color: ColorPalette.textDisabled
                            font.pixelSize: 12 * App.fontScale
                        }
                    }
                }
            }
        }

        // Placeholder when nothing is selected (model empty edge case)
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: root.selectedQueue === null
            Text {
                anchors.centerIn: parent
                text: qsTr("Select a queue on the left, or create a new one.")
                color: ColorPalette.textDisabled
                font.pixelSize: 13 * App.fontScale
            }
        }
    }

    // ── Shared skinny context-menu item (matches DownloadTable.qml's
    // CtxMenuItem — 22px rows, 8/12 side padding, no default MenuItem margins).
    component CtxMenuItem: MenuItem {
        id: _ctxMi
        implicitHeight: 22
        height: 22
        topPadding: 0; bottomPadding: 0; verticalPadding: 0
        leftPadding: 8; rightPadding: 12
        spacing: 0
        font.pixelSize: 12 * App.fontScale
        property string iconSrc: ""
        indicator: Item { width: 0; height: 0 }
        arrow: Text {
            x: _ctxMi.width - width - 8
            anchors.verticalCenter: parent ? parent.verticalCenter : undefined
            text: "▶"; font.pixelSize: 8 * App.fontScale; color: ColorPalette.textMuted
            visible: _ctxMi.subMenu !== null
        }
        contentItem: Row {
            spacing: 6
            Image {
                visible: _ctxMi.iconSrc !== ""
                source: _ctxMi.iconSrc !== "" ? "../icons/" + _ctxMi.iconSrc : ""
                width: 14; height: 14
                sourceSize.width: 14; sourceSize.height: 14
                fillMode: Image.PreserveAspectFit
                smooth: true
                anchors.verticalCenter: parent.verticalCenter
            }
            Item { visible: _ctxMi.iconSrc === ""; width: 0; height: 14 }
            Text {
                text: _ctxMi.text
                font: _ctxMi.font
                color: _ctxMi.enabled ? ColorPalette.textPrimary : ColorPalette.textDisabled
                verticalAlignment: Text.AlignVCenter
                elide: Text.ElideRight
                anchors.verticalCenter: parent.verticalCenter
            }
        }
        background: Rectangle {
            implicitHeight: 22
            color: _ctxMi.highlighted ? ColorPalette.selectionBg : ColorPalette.menuBg
        }
    }

    // ── Queue context menu ───────────────────────────────────────────────
    Menu {
        id: queueContextMenu
        topPadding: 0; bottomPadding: 0
        CtxMenuItem {
            text: qsTr("Start queue")
            iconSrc: "start_queue.svg"
            onTriggered: if (root.selectedQueue) App.startQueue(root.selectedQueue.id)
        }
        CtxMenuItem {
            text: qsTr("Stop queue")
            iconSrc: "stop_queue.svg"
            onTriggered: if (root.selectedQueue) App.stopQueue(root.selectedQueue.id)
        }
        MenuSeparator {}
        CtxMenuItem {
            text: qsTr("Rename")
            iconSrc: "rename.svg"
            onTriggered: { nameField.forceActiveFocus(); nameField.selectAll() }
        }
        MenuSeparator {}
        CtxMenuItem {
            text: qsTr("Delete queue")
            iconSrc: "delete.svg"
            enabled: root.selectedQueue !== null && root.selectedQueue.id !== "main-download"
            onTriggered: {
                if (!root.selectedQueue) return
                App.deleteQueue(root.selectedQueue.id)
                root.selectQueueAt(queueModel.rowCount() > 0 ? 0 : -1)
            }
        }
    }

    // ── File-list context menu ───────────────────────────────────────────
    Menu {
        id: fileContextMenu
        topPadding: 0; bottomPadding: 0
        CtxMenuItem {
            text: qsTr("Properties")
            iconSrc: "properties.svg"
            onTriggered: { if (root._fileCtxItem) root.openPropertiesRequested(root._fileCtxItem) }
        }
        CtxMenuItem {
            text: qsTr("Open File")
            iconSrc: "page.svg"
            onTriggered: { if (root._fileCtxItem) App.openFile(root._fileCtxItem.id) }
        }
        CtxMenuItem {
            text: qsTr("Open Folder")
            iconSrc: "folder_view.svg"
            onTriggered: { if (root._fileCtxItem) App.openFolderSelectFile(root._fileCtxItem.id) }
        }
        MenuSeparator {}
        CtxMenuItem {
            text: qsTr("Copy Filename")
            iconSrc: "copy.svg"
            onTriggered: { if (root._fileCtxItem) App.copyDownloadFilename(root._fileCtxItem.id) }
        }
        CtxMenuItem {
            text: root._fileCtxItem && root._fileCtxItem.isTorrent ? qsTr("Copy Magnet Link") : qsTr("Copy URL")
            iconSrc: root._fileCtxItem && root._fileCtxItem.isTorrent ? "magnet.svg" : "link.svg"
            onTriggered: {
                if (!root._fileCtxItem) return
                var link = App.downloadShareLink(root._fileCtxItem.id)
                if (link && link.length > 0) App.copyToClipboard(link)
            }
        }
        MenuSeparator {}
        CtxMenuItem {
            text: qsTr("Resume")
            iconSrc: "resume.svg"
            onTriggered: { if (root._fileCtxItem) App.resumeDownload(root._fileCtxItem.id) }
        }
        CtxMenuItem {
            text: qsTr("Stop")
            iconSrc: "pause.svg"
            onTriggered: { if (root._fileCtxItem) App.pauseDownload(root._fileCtxItem.id) }
        }
        MenuSeparator {}
        CtxMenuItem {
            text: qsTr("Remove from Queue")
            onTriggered: { if (root._fileCtxItem) App.setDownloadQueue(root._fileCtxItem.id, "") }
        }
        MenuSeparator {}
        CtxMenuItem {
            text: qsTr("Redownload")
            iconSrc: "update.svg"
            onTriggered: { if (root._fileCtxItem) App.redownload(root._fileCtxItem.id) }
        }
        CtxMenuItem {
            text: qsTr("Delete")
            iconSrc: "delete.svg"
            onTriggered: {
                if (!root._fileCtxItem) return
                deleteDialog.downloadId = root._fileCtxItem.id
                deleteDialog.downloadIds = [root._fileCtxItem.id]
                deleteDialog.filename = root._fileCtxItem.filename
                deleteDialog.fileExists = root._fileCtxItem.status === "Completed"
                deleteDialog.hasTorrentSelection = !!root._fileCtxItem.isTorrent
                deleteDialog.show()
                deleteDialog.raise()
                deleteDialog.requestActivate()
            }
        }
    }

    DeleteConfirmDialog {
        id: deleteDialog
        transientParent: root
        property var downloadIds: []
        onConfirmed: (mode) => {
            if (downloadIds && downloadIds.length > 1)
                App.deleteDownloads(downloadIds, mode)
            else if (downloadId.length > 0)
                App.deleteDownload(downloadId, mode)
        }
    }

    signal openPropertiesRequested(var item)

    // ── File picker for "Open when done" ─────────────────────────────────
    FileDialog {
        id: openFileDialog
        title: qsTr("Select file to open when done")
        onAccepted: {
            if (root.selectedQueue) {
                root.selectedQueue.openFilePath = file.toString().replace("file:///", "")
                root.queueEdited()
            }
        }
    }

    // ── Inline sub-components ────────────────────────────────────────────
    component SectionHeader: RowLayout {
        property alias text: headerLabel.text
        Layout.fillWidth: true
        Layout.maximumWidth: parent ? parent.width : -1
        spacing: 8
        Text {
            id: headerLabel
            color: ColorPalette.textSecond
            font.bold: true
            font.pixelSize: 11 * App.fontScale
            font.capitalization: Font.AllUppercase
        }
        Rectangle { Layout.fillWidth: true; Layout.rightMargin: 4; height: 1; color: ColorPalette.dividerBg }
    }

    component NumberField: Rectangle {
        id: numRoot
        property int value: 0
        property int minValue: 0
        property int maxValue: 999
        property int fieldWidth: 44
        signal edited(int newValue)

        width: fieldWidth
        implicitWidth: fieldWidth
        height: 24
        color: ColorPalette.inputBg
        border.color: numInput.activeFocus ? ColorPalette.borderFocus : ColorPalette.border
        radius: 3

        TextInput {
            id: numInput
            anchors.fill: parent
            horizontalAlignment: TextInput.AlignHCenter
            verticalAlignment: TextInput.AlignVCenter
            color: ColorPalette.textPrimary
            selectionColor: ColorPalette.accent
            font.pixelSize: 12 * App.fontScale
            text: String(numRoot.value)
            validator: IntValidator { bottom: numRoot.minValue; top: numRoot.maxValue }
            onEditingFinished: {
                var v = parseInt(text, 10)
                if (isNaN(v)) v = numRoot.value
                v = Math.max(numRoot.minValue, Math.min(numRoot.maxValue, v))
                if (v !== numRoot.value) numRoot.edited(v)
                text = String(v)
            }
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

    Component.onCompleted: _ensureSelection()

    onVisibleChanged: {
        if (!visible) return
        _centerOnOwner()
        _ensureSelection()
    }
}
