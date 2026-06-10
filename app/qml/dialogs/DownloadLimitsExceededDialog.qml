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

    property string queueName:  ""
    property int    usedMB:     0
    property int    limitMB:    0
    property int    limitHours: 1
    property date   windowStart: new Date()
    property date   resumeAt:    new Date()

    width: 460
    minimumWidth: 460
    maximumWidth: 460
    height: mainCol.implicitHeight + 16
    minimumHeight: mainCol.implicitHeight + 16
    maximumHeight: mainCol.implicitHeight + 16
    title: qsTr("Download limits exceeded!")
    color: ColorPalette.cardBg
    flags: Qt.Dialog | Qt.WindowTitleHint | Qt.WindowCloseButtonHint | Qt.MSWindowsFixedSizeDialogHint
    modality: Qt.ApplicationModal

    Material.theme: ColorPalette.materialTheme
    Material.foreground: ColorPalette.textPrimary
    Material.background: ColorPalette.materialBg
    Material.accent: "#4488dd"

    onVisibleChanged: {
        if (visible) {
            raise()
            requestActivate()
            // Start the countdown timer when dialog opens.
            countdownTimer.restart()
        } else {
            countdownTimer.stop()
        }
    }

    // Refresh the "X minutes from now" text every 60 seconds.
    Timer {
        id: countdownTimer
        interval: 60000
        repeat: true
        running: false
        onTriggered: root.requestPaint()
    }

    function _fmt12(dt) {
        // Format a Date as "12:30 PM"
        var h = dt.getHours()
        var m = dt.getMinutes()
        var ampm = h >= 12 ? "PM" : "AM"
        h = h % 12
        if (h === 0) h = 12
        return h + ":" + (m < 10 ? "0" + m : m) + " " + ampm
    }

    function _humanDuration(fromDate, toDate) {
        var diffMs   = toDate - fromDate
        if (diffMs <= 0) return qsTr("now")
        var diffMins = Math.round(diffMs / 60000)
        var hours    = Math.floor(diffMins / 60)
        var mins     = diffMins % 60
        var parts    = []
        if (hours === 1)      parts.push(qsTr("1 hour"))
        else if (hours > 1)   parts.push(qsTr("%1 hours").arg(hours))
        if (mins === 1)       parts.push(qsTr("1 minute"))
        else if (mins > 0)    parts.push(qsTr("%1 minutes").arg(mins))
        if (parts.length === 0) return qsTr("less than a minute")
        return parts.join(" " + qsTr("and") + " ")
    }

    // Triggers a repaint of the dynamic text by invalidating bindings.
    function requestPaint() { countdownDummy.value++ }
    QtObject { id: countdownDummy; property int value: 0 }

    ColumnLayout {
        id: mainCol
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 18 }
        spacing: 14

        Text {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            color: ColorPalette.textPrimary
            font.pixelSize: 12 * App.fontScale
            text: {
                // Force re-evaluation when countdownDummy changes.
                var _tick = countdownDummy.value
                return qsTr("From %1 to %2 you downloaded %3 MB. All downloads in \"%4\" have been stopped because you exceeded the download limit of %5 MB every %6.")
                    .arg(root._fmt12(root.windowStart))
                    .arg(root._fmt12(new Date()))
                    .arg(root.usedMB)
                    .arg(root.queueName)
                    .arg(root.limitMB)
                    .arg(root.limitHours === 1
                         ? qsTr("1 hour")
                         : qsTr("%1 hours").arg(root.limitHours))
            }
        }

        Text {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            color: ColorPalette.textPrimary
            font.pixelSize: 12 * App.fontScale
            text: {
                var _tick = countdownDummy.value
                var now  = new Date()
                var timeStr     = root._fmt12(root.resumeAt)
                var untilStr    = root._humanDuration(now, root.resumeAt)
                return qsTr("All stopped downloads will be resumed automatically at %1 (%2 from now). To resume immediately, change the Download Limits setting and press Resume.")
                    .arg(timeStr)
                    .arg(untilStr)
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.bottomMargin: 2

            Item { Layout.fillWidth: true }
            DlgButton {
                primary: true
                text: qsTr("OK")
                Layout.preferredWidth: 80
                Layout.preferredHeight: 28
                onClicked: root.hide()
            }
        }
    }
}
