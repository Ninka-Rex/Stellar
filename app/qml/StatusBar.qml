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
    property string motdText: ""
    property bool motdVisible: false
    property int errorCount: App.recentErrorDownloads

    signal nextTip()
    signal closeTips()
    signal dismissMotd()
    signal statisticsRequested()

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
            id: onlineUsersText
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
                if (App.estimatedOnlineUsers > 0)
                    return "🟢 " + fmtUsers(App.estimatedOnlineUsers) + " online"
                return "🟡 Estimating… (" + App.estimatedOnlineUsersWarmupPercent + "%)"
            }
            color: onlineUsersHover.hovered ? "#ffffff" : "#b0b0b0"
            font.pixelSize: 11
            verticalAlignment: Text.AlignVCenter

            HoverHandler { id: onlineUsersHover }
            ToolTip.visible: onlineUsersHover.hovered
            ToolTip.delay: 250
            ToolTip.timeout: 10000
            ToolTip.text: App.estimatedOnlineUsersDebugText
                + (App.dhtCrawlInProgress ? "" : "\n\nClick to recrawl now.")

            MouseArea {
                anchors.fill: parent
                enabled: !App.dhtCrawlInProgress
                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                onClicked: App.startDhtCrawlNow()
            }
        }

        // All-time torrent ratio — clickable; opens Statistics dialog.
        Text {
            id: ratioText
            visible: App.settings.ratioInStatusBar
            text: "☯ " + App.allTimeRatio.toFixed(3)
            color: ratioHover.hovered ? "#ffffff" : "#b0b0b0"
            font.pixelSize: 11
            verticalAlignment: Text.AlignVCenter

            HoverHandler { id: ratioHover }
            ToolTip.visible: ratioHover.hovered
            ToolTip.delay: 250
            ToolTip.timeout: 6000
            ToolTip.text: "All-time share ratio\nClick to open Statistics"

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.statisticsRequested()
            }
        }

        // Public IP / network indicator. Click to copy IP.
        // Tooltip is built lazily via Q_INVOKABLE on hover so the per-tick
        // status-bar refresh stays cheap.
        Text {
            id: publicIpText
            visible: App.settings.showPublicIpInStatusBar
            // Cached interface type / WiFi info — refreshed on hover only.
            property int    _ifaceType: 0           // 0=None 1=Wifi 2=Ethernet 3=Other
            property string _wifiSsid:  ""
            property int    _wifiPct:   0
            property int    _wifiRssi:  0
            property bool   _wifiOk:    false

            function _refreshTooltipData() {
                _ifaceType = App.networkInfo.activeInterfaceType()
                if (_ifaceType === 1) {
                    var w = App.networkInfo.queryActiveWifi()
                    _wifiOk   = !!w.available
                    _wifiSsid = _wifiOk ? (w.ssid || "(unknown SSID)") : ""
                    _wifiPct  = _wifiOk ? (w.signalPercent | 0) : 0
                    _wifiRssi = _wifiOk ? (w.rssiDbm | 0) : 0
                } else {
                    _wifiOk = false
                }
            }

            text: {
                if (!App.settings.showPublicIpInStatusBar) return ""
                var ip = App.publicIp
                var prefix
                if (!App.hasIncomingConnections)
                    prefix = "❗"
                else {
                    // Use cached type if known; fall back to a neutral globe so the
                    // indicator never looks broken before the first hover.
                    var t = publicIpText._ifaceType
                    if (t === 0) t = App.networkInfo.activeInterfaceType()
                    prefix = (t === 1) ? "📶" : (t === 2 ? "🔌" : "🌐")
                }
                return prefix + " " + (ip && ip.length > 0 ? ip : "—")
            }
            color: ipHover.hovered ? "#ffffff" : "#b0b0b0"
            font.pixelSize: 11
            verticalAlignment: Text.AlignVCenter

            HoverHandler {
                id: ipHover
                onHoveredChanged: if (hovered) publicIpText._refreshTooltipData()
            }
            ToolTip.visible: ipHover.hovered
            ToolTip.delay: 250
            ToolTip.timeout: 10000
            ToolTip.text: {
                var lines = []
                var ip = App.publicIp
                lines.push("Public IP: " + (ip && ip.length > 0 ? ip : "(detecting…)"))
                if (!App.hasIncomingConnections) {
                    lines.push("")
                    lines.push("❗ No incoming connections, network may be misconfigured")
                }
                if (publicIpText._ifaceType === 1 && publicIpText._wifiOk) {
                    lines.push("")
                    lines.push("WiFi: " + publicIpText._wifiSsid)
                    lines.push("Signal: " + publicIpText._wifiPct + "%  ("
                               + publicIpText._wifiRssi + " dBm)")
                } else if (publicIpText._ifaceType === 2) {
                    lines.push("")
                    lines.push("Connection: Ethernet")
                }
                lines.push("")
                lines.push("Click to copy IP")
                return lines.join("\n")
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    if (App.publicIp && App.publicIp.length > 0)
                        App.copyToClipboard(App.publicIp)
                }
            }
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
            visible: motdVisible && motdText.length > 0
            spacing: 8

            Text {
                text: motdText
                color: "#b0b0b0"
                font.pixelSize: 11
                wrapMode: Text.NoWrap
                elide: Text.ElideRight
                horizontalAlignment: Text.AlignRight
            }

            Text {
                text: "✕"
                color: "#888888"
                font.pixelSize: 12
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    hoverEnabled: true
                    onClicked: root.dismissMotd()
                    onEntered: parent.color = "#b0b0b0"
                    onExited: parent.color = "#888888"
                }
            }
        }

        RowLayout {
            visible: !motdVisible && App.settings.showTips && tipsArray.length > 0
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
            visible: !motdVisible && (!App.settings.showTips || tipsArray.length === 0)
            text: App.minutesUntilNextQueue === 1
                ? "🟧 Queue runs in 1 minute"
                : (App.minutesUntilNextQueue > 0 ? "🟧 Queue runs in %1 minutes".arg(App.minutesUntilNextQueue) : "")
            color: "#a0a0a0"
            font.pixelSize: 11
        }
    }

}
