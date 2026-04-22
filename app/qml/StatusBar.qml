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
import QtQuick.Layouts
import QtQuick.Controls

Rectangle {
    id: root
    height: 22
    color: "#1a1a1a"

    property int activeCount: 0
    property int completedCount: 0
    property int selectedCount: 0
    property var tipsArray: []
    property int currentTipIndex: 0
    property bool showTips: true
    property int errorCount: App.recentErrorDownloads

    signal nextTip()
    signal closeTips()

    function formatKBps(kbps) {
        if (kbps >= 1024)
            return (kbps / 1024).toFixed(kbps >= 10240 ? 0 : 1) + " MB/s"
        return kbps + " KB/s"
    }

    Rectangle { anchors.top: parent.top; width: parent.width; height: 1; color: "#3a3a3a" }

    RowLayout {
        anchors { fill: parent; leftMargin: 8; rightMargin: 8; topMargin: 1 }
        spacing: 8

        Text {
            text: {
                var parts = []

                if (errorCount > 0)
                    parts.push(errorCount === 1 ? "🟨 1 error" : "🟨 %1 errors".arg(errorCount))
                else if (activeCount > 0)
                    parts.push(activeCount === 1 ? "🟦 1 active" : "🟦 %1 active".arg(activeCount))
                else
                    parts.push("🟩 Ready")

                if (activeCount > 0 && errorCount > 0)
                    parts.push(activeCount === 1 ? "🟦 1 active" : "🟦 %1 active".arg(activeCount))

                if (App.settings.showFinishedCount && completedCount > 0)
                    parts.push(completedCount === 1 ? "📄 1 download" : "📄 %1 downloads".arg(completedCount))

                if (selectedCount > 0)
                    parts.push(selectedCount === 1 ? "🔍 1 selected" : "🔍 %1 selected".arg(selectedCount))

                if (App.settings.globalSpeedLimitKBps > 0 || App.settings.globalUploadLimitKBps > 0) {
                    var limitParts = []
                    if (App.settings.globalSpeedLimitKBps > 0)
                        limitParts.push("↓ " + formatKBps(App.settings.globalSpeedLimitKBps))
                    if (App.settings.globalUploadLimitKBps > 0)
                        limitParts.push("↑ " + formatKBps(App.settings.globalUploadLimitKBps))
                    parts.push("🛑 Speed limiter " + limitParts.join(" / "))
                }

                if (App.proxyActive)
                    parts.push("🌐 Proxy on")

                if (App.checkingForUpdates)
                    parts.push("📡 Checking for updates")

                if (App.updateStatusText && App.updateStatusText.length > 0 && !App.checkingForUpdates)
                    parts.push(App.updateStatusText)

                if (App.torrentBindingStatusText && App.torrentBindingStatusText.length > 0)
                    parts.push(App.torrentBindingStatusText)

                return parts.join("  | ")
            }
            color: "#a0a0a0"
            font.pixelSize: 11
            verticalAlignment: Text.AlignVCenter
        }

        Item { Layout.fillWidth: true }

        Text {
            visible: App.settings.estimatedOnlineUsersInStatusBar
            text: {
                function fmtUsers(value) {
                    if (value >= 1000000000)
                        return "~" + (value / 1000000000).toFixed(value >= 10000000000 ? 0 : 1) + "B"
                    if (value >= 1000000)
                        return "~" + (value / 1000000).toFixed(value >= 10000000 ? 0 : 1) + "M"
                    if (value >= 1000)
                        return "~" + (value / 1000).toFixed(value >= 10000 ? 0 : 1) + "K"
                    return "~" + Math.round(value)
                }
                if (!App.settings.torrentEnableDht)
                    return "🔴 DHT off"
                if (App.estimatedOnlineUsers > 0) {
                    const lowConfidence = App.estimatedOnlineUsersWarmupPercent < 70
                    return "🟢 " + fmtUsers(App.estimatedOnlineUsers) + " online" + (lowConfidence ? "*" : "")
                }
                return "🟡 estimating... (" + App.estimatedOnlineUsersWarmupPercent + "%)"
            }
            color: "#b0b0b0"
            font.pixelSize: 11
            verticalAlignment: Text.AlignVCenter

            HoverHandler { id: onlineUsersHover }
            ToolTip.visible: onlineUsersHover.hovered
            ToolTip.delay: 250
            ToolTip.timeout: 10000
            ToolTip.text: App.estimatedOnlineUsersDebugText
        }

        // All-time torrent ratio — right-aligned, left of speed.
        Text {
            visible: App.settings.ratioInStatusBar
            text: "☯ " + App.allTimeRatio.toFixed(3)
            color: "#b0b0b0"
            font.pixelSize: 11
            verticalAlignment: Text.AlignVCenter
        }

        // Live speed indicator — right-aligned, only shown when enabled.
        Text {
            visible: App.settings.speedInStatusBar
            text: {
                function fmt(bps) {
                    if (bps >= 1024 * 1024)
                        return (bps / (1024 * 1024)).toFixed(1) + " MB/s"
                    return Math.round(bps / 1024) + " KB/s"
                }
                return "↓ " + fmt(App.totalDownSpeed) + "  ↑ " + fmt(App.totalUpSpeed)
            }
            color: "#b0b0b0"
            font.pixelSize: 11
            verticalAlignment: Text.AlignVCenter
        }

        RowLayout {
            visible: App.settings.showTips && tipsArray.length > 0
            spacing: 8

            Text {
                text: tipsArray.length > currentTipIndex ? "💡 Tip: " + tipsArray[currentTipIndex] : ""
                color: "#b0b0b0"
                font.pixelSize: 11
                wrapMode: Text.NoWrap
                elide: Text.ElideRight
                horizontalAlignment: Text.AlignRight
            }

            Row {
                spacing: 6

                Text {
                    text: "next >>"
                    color: "#5588cc"
                    font.pixelSize: 10
                    font.underline: true
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.nextTip()
                    }
                }

                Text {
                    text: "✕"
                    color: "#888888"
                    font.pixelSize: 12
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        hoverEnabled: true
                        onClicked: root.closeTips()
                        onEntered: parent.color = "#b0b0b0"
                        onExited: parent.color = "#888888"
                    }
                }
            }
        }

        Text {
            visible: !App.settings.showTips || tipsArray.length === 0
            text: App.minutesUntilNextQueue === 1
                ? "🟧 Queue runs in 1 minute"
                : (App.minutesUntilNextQueue > 0 ? "🟧 Queue runs in %1 minutes".arg(App.minutesUntilNextQueue) : "")
            color: "#a0a0a0"
            font.pixelSize: 11
        }
    }
}
