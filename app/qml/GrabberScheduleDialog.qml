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
    title: "Schedule the grabber project"
    width: 780
    height: 490
    minimumWidth: 740
    minimumHeight: 460
    color: "#1e1e1e"
    flags: Qt.Dialog | Qt.WindowTitleHint | Qt.WindowCloseButtonHint
    modality: Qt.ApplicationModal

    Material.theme: Material.Dark
    Material.background: "#1e1e1e"
    Material.accent: "#4488dd"

    property string projectId: ""
    property string projectName: ""

    // ── Shared sub-component styles ───────────────────────────────────────────
    component SLabel: Text {
        color: "#d0d0d0"
        font.pixelSize: 12
        verticalAlignment: Text.AlignVCenter
    }

    component SCheck: CheckBox {
        topPadding: 3; bottomPadding: 3
        contentItem: Text {
            text: parent.text
            color: parent.enabled ? "#d0d0d0" : "#666666"
            font.pixelSize: 12
            leftPadding: parent.indicator.width + 6
            verticalAlignment: Text.AlignVCenter
        }
    }

    component SRadio: RadioButton {
        topPadding: 3; bottomPadding: 3
        contentItem: Text {
            text: parent.text
            color: parent.enabled ? "#d0d0d0" : "#666666"
            font.pixelSize: 12
            leftPadding: parent.indicator.width + 6
            verticalAlignment: Text.AlignVCenter
        }
    }

    // Compact dark-styled SpinBox
    component DarkSpin: SpinBox {
        id: _spin
        property int minVal: 0
        property int maxVal: 99
        property bool zeroPad: false
        from: minVal; to: maxVal
        editable: true
        implicitWidth: 54
        implicitHeight: 26

        textFromValue: function(v) {
            return zeroPad ? ("0" + v).slice(-2) : String(v)
        }
        valueFromText: function(t) { return parseInt(t) || 0 }

        contentItem: TextInput {
            text: _spin.textFromValue(_spin.value)
            color: "#e0e0e0"
            font.pixelSize: 12
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            readOnly: !_spin.editable
            validator: IntValidator { bottom: _spin.from; top: _spin.to }
            onEditingFinished: _spin.value = parseInt(text) || _spin.from
        }
        up.indicator: Rectangle {
            x: _spin.width - width; y: 0
            width: 18; height: _spin.height / 2
            color: _spin.up.pressed ? "#3a3a4a" : (_spin.up.hovered ? "#2d2d3a" : "#2a2a2a")
            Text { anchors.centerIn: parent; text: "▲"; color: "#aaa"; font.pixelSize: 7 }
        }
        down.indicator: Rectangle {
            x: _spin.width - width; y: _spin.height / 2
            width: 18; height: _spin.height / 2
            color: _spin.down.pressed ? "#3a3a4a" : (_spin.down.hovered ? "#2d2d3a" : "#2a2a2a")
            Text { anchors.centerIn: parent; text: "▼"; color: "#aaa"; font.pixelSize: 7 }
        }
        background: Rectangle { color: "#1b1b1b"; border.color: "#3a3a3a"; radius: 2 }
    }

    // Dark-styled ComboBox
    component DarkCombo: ComboBox {
        implicitHeight: 26
        font.pixelSize: 12
        contentItem: Text {
            leftPadding: 8
            rightPadding: 24
            text: parent.displayText
            color: parent.enabled ? "#e0e0e0" : "#666666"
            font: parent.font
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
        }
        background: Rectangle {
            color: "#1b1b1b"
            border.color: "#3a3a3a"
            radius: 2
        }
        indicator: Text {
            x: parent.width - width - 6
            y: (parent.height - height) / 2
            text: "▼"
            color: "#888"
            font.pixelSize: 8
        }
        popup.background: Rectangle { color: "#2a2a2a"; border.color: "#444"; radius: 3 }
    }

    // ── Computed day-of-week for the "Once at" date ────────────────────────────
    function dayOfWeekName() {
        var mo = onceDateMonthCombo.currentIndex
        var da = onceDateDaySpinbox.value
        var yr = onceDateYearSpinbox.value
        var d = new Date(yr, mo, da)
        if (isNaN(d.getTime())) return ""
        return d.toLocaleDateString(Qt.locale(), "dddd")
    }

    // ── Load / save ────────────────────────────────────────────────────────────
    function loadProjectSchedule() {
        var project = App.grabberProjectData(projectId)
        projectName = project.name || "Grabber Project"
        var s = project.schedule || {}

        enabledChk.checked        = !!s.enabled
        periodicRadio.checked     = s.exploringMode === "periodic"
        onceTimeRadio.checked     = !periodicRadio.checked

        actionExploreRadio.checked         = (s.action || "exploreOnly") === "exploreOnly"
        actionExploreDownloadRadio.checked = s.action === "exploreAndDownload"
        actionDownloadCheckedRadio.checked = s.action === "downloadChecked"

        // Start time
        startAtChk.checked          = s.startEnabled !== false
        startHourSpin.value         = s.startHour   !== undefined ? s.startHour   : 11
        startMinuteSpin.value       = s.startMinute !== undefined ? s.startMinute : 0
        startAmpmCombo.currentIndex = (s.startAmPm || "PM") === "PM" ? 1 : 0

        // Once-at vs Daily
        var schMode = s.scheduleMode || "once"
        onceDateRadio.checked = schMode === "once"
        dailyRadio.checked    = schMode === "daily"

        // Date picker
        var now = new Date()
        var mo = (s.onceMonth !== undefined) ? s.onceMonth - 1 : now.getMonth()
        onceDateMonthCombo.currentIndex = Math.max(0, Math.min(11, mo))
        onceDateDaySpinbox.value        = s.onceDay  !== undefined ? s.onceDay  : now.getDate()
        onceDateYearSpinbox.value       = s.onceYear !== undefined ? s.onceYear : now.getFullYear()

        // Day checkboxes
        var days = s.days || []
        sundayChk.checked    = days.indexOf("Sunday")    >= 0
        mondayChk.checked    = days.indexOf("Monday")    >= 0
        tuesdayChk.checked   = days.indexOf("Tuesday")   >= 0
        wednesdayChk.checked = days.indexOf("Wednesday") >= 0
        thursdayChk.checked  = days.indexOf("Thursday")  >= 0
        fridayChk.checked    = days.indexOf("Friday")    >= 0
        saturdayChk.checked  = days.indexOf("Saturday")  >= 0

        // Stop time
        stopEnabledChk.checked      = !!s.stopEnabled
        stopHourSpin.value          = s.stopHour   !== undefined ? s.stopHour   : 7
        stopMinuteSpin.value        = s.stopMinute !== undefined ? s.stopMinute : 30
        stopAmpmCombo.currentIndex  = (s.stopAmPm || "AM") === "AM" ? 0 : 1

        // Periodic
        everyHoursField.text   = String(s.everyHours   !== undefined ? s.everyHours   : 2)
        everyMinutesField.text = String(s.everyMinutes !== undefined ? s.everyMinutes : 0)

        // Completion
        exitAppChk.checked     = !!s.exitApp
        turnOffChk.checked     = !!s.turnOffComputer
        var modeIdx = ["Shut down","Restart","Sleep","Hibernate"].indexOf(s.shutdownMode || "Shut down")
        shutdownCombo.currentIndex = Math.max(0, modeIdx)
        forceChk.checked = !!s.forceProcesses
    }

    function selectedDays() {
        var days = []
        if (sundayChk.checked)    days.push("Sunday")
        if (mondayChk.checked)    days.push("Monday")
        if (tuesdayChk.checked)   days.push("Tuesday")
        if (wednesdayChk.checked) days.push("Wednesday")
        if (thursdayChk.checked)  days.push("Thursday")
        if (fridayChk.checked)    days.push("Friday")
        if (saturdayChk.checked)  days.push("Saturday")
        return days
    }

    function saveSchedule() {
        App.saveGrabberProjectSchedule(projectId, {
            enabled:         enabledChk.checked,
            exploringMode:   periodicRadio.checked ? "periodic" : "once",
            scheduleMode:    dailyRadio.checked ? "daily" : "once",
            action:          actionExploreDownloadRadio.checked ? "exploreAndDownload"
                           : actionDownloadCheckedRadio.checked ? "downloadChecked"
                           : "exploreOnly",
            startEnabled:    startAtChk.checked,
            startHour:       startHourSpin.value,
            startMinute:     startMinuteSpin.value,
            startAmPm:       startAmpmCombo.currentText,
            onceMonth:       onceDateMonthCombo.currentIndex + 1,
            onceDay:         onceDateDaySpinbox.value,
            onceYear:        onceDateYearSpinbox.value,
            days:            selectedDays(),
            stopEnabled:     stopEnabledChk.checked,
            stopHour:        stopHourSpin.value,
            stopMinute:      stopMinuteSpin.value,
            stopAmPm:        stopAmpmCombo.currentText,
            everyHours:      Number(everyHoursField.text  || "2"),
            everyMinutes:    Number(everyMinutesField.text || "0"),
            exitApp:         exitAppChk.checked,
            turnOffComputer: turnOffChk.checked,
            shutdownMode:    shutdownCombo.currentText,
            forceProcesses:  forceChk.checked
        })
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

    onVisibleChanged: { if (visible) { _centerOnOwner(); loadProjectSchedule() } }

    // ── Layout ─────────────────────────────────────────────────────────────────
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 12
        spacing: 10

        // ── Header ────────────────────────────────────────────────────────────
        Row {
            spacing: 10
            Image {
                source: "icons/milky-way.png"
                width: 40; height: 40
                sourceSize.width: 64; sourceSize.height: 64
                fillMode: Image.PreserveAspectFit
                smooth: true; mipmap: true
                anchors.verticalCenter: parent.verticalCenter
            }
            Column {
                spacing: 2
                anchors.verticalCenter: parent.verticalCenter
                Text { text: "Project:"; color: "#888888"; font.pixelSize: 11 }
                Text { text: projectName; color: "#f0f0f0"; font.pixelSize: 14; font.bold: true }
            }
        }

        SCheck { id: enabledChk; text: "Enable project schedule" }

        // ── Two-panel main area ───────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 10

            // ── Left panel: Steps 1 + 2 + After completion ────────────────────
            Rectangle {
                Layout.preferredWidth: 286
                Layout.fillHeight: true
                color: "#1b1b1b"
                border.color: "#333333"
                radius: 3

                ColumnLayout {
                    anchors { fill: parent; margins: 12 }
                    spacing: 0

                    SLabel { text: "Step 1.  Select type"; font.bold: true; bottomPadding: 4 }

                    ButtonGroup { id: exploringModeGroup }
                    SRadio { id: onceTimeRadio;  text: "One-time exploring/downloading"; checked: true; ButtonGroup.group: exploringModeGroup }
                    SRadio { id: periodicRadio;  text: "Periodic synchronization"; ButtonGroup.group: exploringModeGroup }

                    Rectangle { Layout.fillWidth: true; height: 1; color: "#333333"; Layout.topMargin: 8; Layout.bottomMargin: 8 }

                    SLabel { text: "Step 2.  Select action"; font.bold: true; bottomPadding: 4 }

                    ButtonGroup { id: actionGroup }
                    SRadio { id: actionExploreRadio;         text: "Explore only"; checked: true; ButtonGroup.group: actionGroup }
                    SRadio { id: actionExploreDownloadRadio; text: "Explore site and download matched files"; ButtonGroup.group: actionGroup }
                    SRadio { id: actionDownloadCheckedRadio; text: "Download checked files"; ButtonGroup.group: actionGroup }

                    Rectangle { Layout.fillWidth: true; height: 1; color: "#333333"; Layout.topMargin: 8; Layout.bottomMargin: 8 }

                    SLabel { text: "After completion"; font.bold: true; bottomPadding: 4 }

                    SCheck { id: exitAppChk;  text: "Exit Stellar when done" }
                    SCheck { id: turnOffChk;  text: "Turn off computer when done" }

                    RowLayout {
                        Layout.leftMargin: 22
                        visible: turnOffChk.checked
                        spacing: 6
                        DarkCombo {
                            id: shutdownCombo
                            model: ["Shut down", "Restart", "Sleep", "Hibernate"]
                            implicitWidth: 140
                        }
                    }

                    SCheck {
                        id: forceChk
                        Layout.leftMargin: 22
                        visible: turnOffChk.checked
                        text: "Force processes to terminate"
                        enabled: false
                    }

                    Item { Layout.fillHeight: true }
                }
            }

            // ── Right panel: Step 3 Schedule ──────────────────────────────────
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                color: "#1b1b1b"
                border.color: "#333333"
                radius: 3

                ColumnLayout {
                    anchors { fill: parent; margins: 12 }
                    spacing: 8

                    SLabel { text: "Step 3.  Schedule"; font.bold: true }

                    // ── Start time ────────────────────────────────────────────
                    RowLayout {
                        spacing: 6
                        SCheck { id: startAtChk; text: "Start download at"; checked: true }
                        Item { Layout.fillWidth: true }
                        Row {
                            spacing: 2
                            enabled: startAtChk.checked
                            opacity: enabled ? 1.0 : 0.45
                            DarkSpin { id: startHourSpin;   minVal: 1; maxVal: 12; value: 11; implicitWidth: 50 }
                            Text { text: ":"; color: "#aaa"; font.pixelSize: 13; anchors.verticalCenter: parent.verticalCenter; leftPadding: 1; rightPadding: 1 }
                            DarkSpin { id: startMinuteSpin; minVal: 0; maxVal: 59; value: 0; zeroPad: true; implicitWidth: 50 }
                            Item { width: 4 }
                            DarkCombo { id: startAmpmCombo; model: ["AM","PM"]; currentIndex: 1; implicitWidth: 62 }
                        }
                    }

                    // ── Once at / Daily ───────────────────────────────────────
                    ColumnLayout {
                        visible: onceTimeRadio.checked
                        enabled: startAtChk.checked
                        spacing: 4
                        Layout.fillWidth: true

                        ButtonGroup { id: schedModeGroup }

                        // Once at row
                        RowLayout {
                            spacing: 6
                            Layout.fillWidth: true
                            SRadio {
                                id: onceDateRadio
                                text: "Once at"
                                checked: true
                                ButtonGroup.group: schedModeGroup
                            }
                            Item { Layout.fillWidth: true }
                            Row {
                                spacing: 3
                                enabled: onceDateRadio.checked && startAtChk.checked
                                opacity: enabled ? 1.0 : 0.45
                                Text {
                                    text: dayOfWeekName()
                                    color: "#aaaaaa"; font.pixelSize: 11
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 68; elide: Text.ElideRight
                                }
                                Text { text: ","; color: "#888"; font.pixelSize: 12; anchors.verticalCenter: parent.verticalCenter }
                                DarkCombo {
                                    id: onceDateMonthCombo
                                    model: ["January","February","March","April","May","June",
                                            "July","August","September","October","November","December"]
                                    currentIndex: new Date().getMonth()
                                    implicitWidth: 96
                                }
                                DarkSpin {
                                    id: onceDateDaySpinbox
                                    minVal: 1; maxVal: 31
                                    value: new Date().getDate()
                                    implicitWidth: 50
                                }
                                Text { text: ","; color: "#888"; font.pixelSize: 12; anchors.verticalCenter: parent.verticalCenter }
                                DarkSpin {
                                    id: onceDateYearSpinbox
                                    minVal: 2025; maxVal: 2040
                                    value: new Date().getFullYear()
                                    implicitWidth: 64
                                }
                            }
                        }

                        // Daily row
                        RowLayout {
                            SRadio { id: dailyRadio; text: "Daily"; ButtonGroup.group: schedModeGroup }
                        }
                        GridLayout {
                            visible: dailyRadio.checked
                            enabled: startAtChk.checked
                            columns: 2
                            columnSpacing: 20
                            rowSpacing: 0
                            Layout.leftMargin: 24

                            SCheck { id: sundayChk;    text: "Sunday" }
                            SCheck { id: thursdayChk;  text: "Thursday" }
                            SCheck { id: mondayChk;    text: "Monday" }
                            SCheck { id: fridayChk;    text: "Friday" }
                            SCheck { id: tuesdayChk;   text: "Tuesday" }
                            SCheck { id: saturdayChk;  text: "Saturday" }
                            SCheck { id: wednesdayChk; text: "Wednesday" }
                        }
                    }

                    // ── Periodic repeat interval ──────────────────────────────
                    RowLayout {
                        visible: periodicRadio.checked
                        spacing: 8
                        SLabel { text: "Repeat every" }
                        TextField {
                            id: everyHoursField
                            implicitWidth: 52; implicitHeight: 26
                            text: "2"; color: "#e0e0e0"; font.pixelSize: 12; leftPadding: 8
                            validator: IntValidator { bottom: 0; top: 999 }
                            background: Rectangle { color: "#1b1b1b"; border.color: "#3a3a3a"; radius: 2 }
                        }
                        SLabel { text: "hours" }
                        TextField {
                            id: everyMinutesField
                            implicitWidth: 52; implicitHeight: 26
                            text: "0"; color: "#e0e0e0"; font.pixelSize: 12; leftPadding: 8
                            validator: IntValidator { bottom: 0; top: 59 }
                            background: Rectangle { color: "#1b1b1b"; border.color: "#3a3a3a"; radius: 2 }
                        }
                        SLabel { text: "minutes" }
                    }

                    // ── Stop time ─────────────────────────────────────────────
                    RowLayout {
                        spacing: 6
                        SCheck { id: stopEnabledChk; text: "Stop download at" }
                        Item { Layout.fillWidth: true }
                        Row {
                            spacing: 2
                            enabled: stopEnabledChk.checked
                            opacity: enabled ? 1.0 : 0.45
                            DarkSpin { id: stopHourSpin;   minVal: 1; maxVal: 12; value: 7;  implicitWidth: 50 }
                            Text { text: ":"; color: "#aaa"; font.pixelSize: 13; anchors.verticalCenter: parent.verticalCenter; leftPadding: 1; rightPadding: 1 }
                            DarkSpin { id: stopMinuteSpin; minVal: 0; maxVal: 59; value: 30; zeroPad: true; implicitWidth: 50 }
                            Item { width: 4 }
                            DarkCombo { id: stopAmpmCombo; model: ["AM","PM"]; currentIndex: 0; implicitWidth: 62 }
                        }
                    }

                    // ── Note ──────────────────────────────────────────────────
                    Rectangle {
                        Layout.fillWidth: true
                        height: noteText.implicitHeight + 16
                        color: "#1a2030"
                        border.color: "#2a3050"
                        radius: 3
                        Text {
                            id: noteText
                            anchors { fill: parent; margins: 8 }
                            text: "Note: Stellar should be running in the system tray at the specified time to start a scheduled project."
                            color: "#8899bb"
                            font.pixelSize: 11
                            wrapMode: Text.WordWrap
                        }
                    }

                    Item { Layout.fillHeight: true }
                }
            }
        }

        // ── Buttons ───────────────────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            Item { Layout.fillWidth: true }
            DlgButton {
                text: "Cancel"
                onClicked: root.close()
            }
            DlgButton {
                text: "OK"
                primary: true
                onClicked: { saveSchedule(); root.close() }
            }
        }
    }
}
