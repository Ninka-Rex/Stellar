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
        if (kbps >= 1000)
            return (kbps / 1000).toFixed(kbps >= 10000 ? 0 : 1) + " MB/s"
        return kbps + " KB/s"
    }

    readonly property bool _hasVisibleCounts: App.totalDownloads > 0 || App.activeDownloads > 0
        || App.seedingCount > 0 || App.pausedCount > 0 || App.checkingCount > 0
        || errorCount > 0 || selectedCount > 0

    readonly property bool _hasSysStatus: App.settings.speedLimiterEnabled || App.proxyActive
        || App.checkingForUpdates
        || (App.updateStatusText && App.updateStatusText.length > 0 && !App.checkingForUpdates)
        || (App.torrentBindingStatusText && App.torrentBindingStatusText.length > 0)

    component StatusIcon: Image {
        width: 12; height: 12
        fillMode: Image.PreserveAspectFit
        smooth: true
        sourceSize: Qt.size(12, 12)
        anchors.verticalCenter: parent.verticalCenter
    }

    Rectangle { anchors.top: parent.top; width: parent.width; height: 1; color: "#3a3a3a" }

    RowLayout {
        anchors { fill: parent; leftMargin: 8; rightMargin: 8; topMargin: 1 }
        spacing: 8

        // ── Left cluster: download counts ────────────────────────────

        Row {
            visible: App.totalDownloads > 0
            spacing: 4
            Layout.alignment: Qt.AlignVCenter
            StatusIcon { source: "icons/floppy_disk.svg" }
            Text {
                text: App.totalDownloads
                color: "#a0a0a0"
                font.pixelSize: 11 * App.fontScale
            }
        }

        Row {
            visible: App.activeDownloads > 0
            spacing: 4
            Layout.alignment: Qt.AlignVCenter
            StatusIcon { source: "icons/resume.svg" }
            Text {
                text: App.activeDownloads
                color: "#a0a0a0"
                font.pixelSize: 11 * App.fontScale
            }
        }

        Row {
            visible: App.seedingCount > 0
            spacing: 4
            Layout.alignment: Qt.AlignVCenter
            StatusIcon { source: "icons/torrent-categories/seeding.svg" }
            Text {
                text: App.activeSeedingCount + (App.activeSeedingCount !== App.seedingCount ? " (" + App.seedingCount + ")" : "")
                color: "#a0a0a0"
                font.pixelSize: 11 * App.fontScale
            }
        }

        Row {
            visible: App.pausedCount > 0
            spacing: 4
            Layout.alignment: Qt.AlignVCenter
            StatusIcon { source: "icons/pause.svg" }
            Text {
                text: App.pausedCount
                color: "#a0a0a0"
                font.pixelSize: 11 * App.fontScale
            }
        }

        Row {
            visible: App.checkingCount > 0
            spacing: 4
            Layout.alignment: Qt.AlignVCenter
            StatusIcon { source: "icons/torrent-categories/checking.svg" }
            Text {
                text: App.checkingCount
                color: "#a0a0a0"
                font.pixelSize: 11 * App.fontScale
            }
        }

        Row {
            visible: errorCount > 0
            spacing: 4
            Layout.alignment: Qt.AlignVCenter
            StatusIcon { source: "icons/warning.svg" }
            Text {
                text: errorCount
                color: "#a0a0a0"
                font.pixelSize: 11 * App.fontScale
            }
        }

        Row {
            visible: selectedCount > 0
            spacing: 4
            Layout.alignment: Qt.AlignVCenter
            StatusIcon { source: "icons/magnifying_glass.svg" }
            Text {
                text: selectedCount
                color: "#a0a0a0"
                font.pixelSize: 11 * App.fontScale
            }
        }

        // ── Separator ─────────────────────────────────────────────────

        Text {
            visible: _hasVisibleCounts && _hasSysStatus
            text: "|"
            color: "#666666"
            font.pixelSize: 11 * App.fontScale
            Layout.alignment: Qt.AlignVCenter
        }

        // ── System status items ───────────────────────────────────────

        Row {
            visible: App.settings.speedLimiterEnabled
            spacing: 4
            Layout.alignment: Qt.AlignVCenter
            StatusIcon { source: "icons/snail.svg" }
            Text {
                text: {
                    var limitParts = []
                    if (App.settings.globalSpeedLimitKBps > 0)
                        limitParts.push("↓ " + formatKBps(App.settings.globalSpeedLimitKBps))
                    if (App.settings.globalUploadLimitKBps > 0)
                        limitParts.push("↑ " + formatKBps(App.settings.globalUploadLimitKBps))
                    var limStr = limitParts.length > 0 ? limitParts.join(" / ") : qsTr("unlimited")
                    return qsTr("Speed limiter ") + limStr
                }
                color: "#a0a0a0"
                font.pixelSize: 11 * App.fontScale
            }
        }

        Row {
            visible: App.proxyActive
            spacing: 4
            Layout.alignment: Qt.AlignVCenter
            StatusIcon { source: "icons/globe.svg" }
            Text {
                text: qsTr("Proxy on")
                color: "#a0a0a0"
                font.pixelSize: 11 * App.fontScale
            }
        }

        Row {
            visible: App.checkingForUpdates
            spacing: 4
            Layout.alignment: Qt.AlignVCenter
            StatusIcon { source: "icons/update.svg" }
            Text {
                text: qsTr("Checking for updates")
                color: "#a0a0a0"
                font.pixelSize: 11 * App.fontScale
            }
        }

        // Raw status texts from C++ — these may include their own formatting
        Text {
            visible: App.updateStatusText && App.updateStatusText.length > 0 && !App.checkingForUpdates
            text: App.updateStatusText
            color: "#a0a0a0"
            font.pixelSize: 11 * App.fontScale
            Layout.alignment: Qt.AlignVCenter
        }

        Text {
            visible: App.torrentBindingStatusText && App.torrentBindingStatusText.length > 0
            text: App.torrentBindingStatusText
            color: "#a0a0a0"
            font.pixelSize: 11 * App.fontScale
            Layout.alignment: Qt.AlignVCenter
        }

        Item { Layout.fillWidth: true }

        // ── Right cluster: online users ───────────────────────────────

        Item {
            id: onlineUsersRow
            Layout.leftMargin: 12
            Layout.fillHeight: true
            visible: App.settings.estimatedOnlineUsersInStatusBar
            implicitWidth: onlineUsersInner.width

            Row {
                id: onlineUsersInner
                spacing: 4
                anchors.verticalCenter: parent.verticalCenter
                StatusIcon {
                    visible: App.settings.torrentEnableDht && App.estimatedOnlineUsers > 0
                        && App.estimatedOnlineUsers <= 25000000
                    source: "icons/person.svg"
                }
                Text {
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
                            return qsTr("DHT off")
                        if (App.estimatedOnlineUsers > 0) {
                            if (App.estimatedOnlineUsers > 25000000)
                                return fmtUsers(App.estimatedOnlineUsers) + qsTr(" online (low confidence)")
                            return fmtUsers(App.estimatedOnlineUsers) + qsTr(" online")
                        }
                        return qsTr("Estimating… (%1%)").arg(App.estimatedOnlineUsersWarmupPercent)
                    }
                    color: onlineUsersHover.hovered ? "#ffffff" : "#b0b0b0"
                    font.pixelSize: 11 * App.fontScale
                }
            }

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

        // ── All-time torrent ratio ────────────────────────────────────

        Item {
            id: ratioRow
            Layout.leftMargin: 12
            Layout.fillHeight: true
            visible: App.settings.ratioInStatusBar
            implicitWidth: ratioInner.width

            Row {
                id: ratioInner
                spacing: 4
                anchors.verticalCenter: parent.verticalCenter
                StatusIcon { source: "icons/yin_yang.svg" }
                Text {
                    text: App.allTimeRatio.toFixed(3)
                    color: ratioHover.hovered ? "#ffffff" : "#b0b0b0"
                    font.pixelSize: 11 * App.fontScale
                }
            }

            HoverHandler { id: ratioHover }
            ToolTip.visible: ratioHover.hovered
            ToolTip.delay: 250
            ToolTip.timeout: 6000
            ToolTip.text: qsTr("All-time share ratio\nClick to open Statistics")

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.statisticsRequested()
            }
        }

        // ── Public IP / network indicator ─────────────────────────────

        Item {
            id: publicIpRow
            Layout.leftMargin: 12
            Layout.fillHeight: true
            visible: App.settings.showPublicIpInStatusBar
            implicitWidth: publicIpInner.width

            property int    _ifaceType: 0
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

            Row {
                id: publicIpInner
                spacing: 4
                anchors.verticalCenter: parent.verticalCenter
                StatusIcon {
                    source: {
                        if (!App.publicIp || App.publicIp.length === 0) return "icons/red_circle.svg"
                        if (!App.hasIncomingConnections) return "icons/fire.svg"
                        return "icons/globe_showing_americas.svg"
                    }
                }
                Text {
                    text: {
                        if (!App.publicIp || App.publicIp.length === 0) return "—"
                        return App.publicIp
                    }
                    color: ipHover.hovered ? "#ffffff" : "#b0b0b0"
                    font.pixelSize: 11 * App.fontScale
                }
            }

            HoverHandler {
                id: ipHover
                onHoveredChanged: if (hovered) publicIpRow._refreshTooltipData()
            }
            ToolTip.visible: ipHover.hovered
            ToolTip.delay: 250
            ToolTip.timeout: 10000
            ToolTip.text: {
                var lines = []
                var ip = App.publicIp
                if (!ip || ip.length === 0) {
                    lines.push(qsTr("No network connectivity detected"))
                } else {
                    lines.push(qsTr("Public IP: ") + ip)
                    if (App.publicIpListenPort > 0)
                        lines.push(qsTr("Listening port: ") + App.publicIpListenPort)
                    if (!App.hasIncomingConnections) {
                        lines.push("")
                        lines.push(qsTr("No incoming connections, network may be misconfigured"))
                    }
                    if (publicIpRow._ifaceType === 1 && publicIpRow._wifiOk) {
                        lines.push("")
                        lines.push(qsTr("WiFi: ") + publicIpRow._wifiSsid)
                        lines.push(qsTr("Signal: ") + publicIpRow._wifiPct + "%  ("
                                   + publicIpRow._wifiRssi + " dBm)")
                    } else if (publicIpRow._ifaceType === 2) {
                        lines.push("")
                        lines.push(qsTr("Connection: Ethernet"))
                    }
                }
                lines.push("")
                lines.push(qsTr("Click to copy IP"))
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

        // ── Live speed indicator ──────────────────────────────────────

        Text {
            id: speedText
            Layout.leftMargin: 12
            visible: App.settings.speedInStatusBar
            text: {
                function fmt(bps) {
                    if (bps >= 1000000)
                        return (bps / 1000000).toFixed(1) + " MB/s"
                    return Math.round(bps / 1000) + " KB/s"
                }
                return "↓ " + fmt(App.totalDownSpeed) + "  ↑ " + fmt(App.totalUpSpeed)
            }
            color: "#b0b0b0"
            font.pixelSize: 11 * App.fontScale
            Layout.fillHeight: true
            verticalAlignment: Text.AlignVCenter
        }

        // ── MOTD ──────────────────────────────────────────────────────

        RowLayout {
            visible: motdVisible && motdText.length > 0
            spacing: 8

            Text {
                text: motdText
                color: "#b0b0b0"
                font.pixelSize: 11 * App.fontScale
                wrapMode: Text.NoWrap
                elide: Text.ElideRight
                horizontalAlignment: Text.AlignRight
            }

            Text {
                text: "✕"
                color: "#888888"
                font.pixelSize: 12 * App.fontScale
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

        // ── Tips ──────────────────────────────────────────────────────

        RowLayout {
            visible: !motdVisible && App.settings.showTips && tipsArray.length > 0
            spacing: 8

            Row {
                spacing: 4
                Layout.alignment: Qt.AlignVCenter
                StatusIcon { source: "icons/light_bulb.svg" }
                Text {
                    text: "Tip: " + (tipsArray.length > currentTipIndex ? tipsArray[currentTipIndex] : "")
                    color: "#b0b0b0"
                    font.pixelSize: 11 * App.fontScale
                    wrapMode: Text.NoWrap
                    elide: Text.ElideRight
                    horizontalAlignment: Text.AlignRight
                }
            }

            Row {
                spacing: 6

                Text {
                    text: qsTr("next >>")
                    color: "#5588cc"
                    font.pixelSize: 10 * App.fontScale
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
                    font.pixelSize: 12 * App.fontScale
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

        // ── Queue timer ───────────────────────────────────────────────

        Item {
            visible: !motdVisible && (!App.settings.showTips || tipsArray.length === 0)
                && App.minutesUntilNextQueue > 0
            Layout.fillHeight: true
            implicitWidth: queueTimerInner.width

            Row {
                id: queueTimerInner
                spacing: 4
                anchors.verticalCenter: parent.verticalCenter
                StatusIcon { source: "icons/hourglass_not_done.svg" }
                Text {
                    text: App.minutesUntilNextQueue === 1
                        ? qsTr("Queue runs in 1 minute")
                        : qsTr("Queue runs in %1 minutes").arg(App.minutesUntilNextQueue)
                    color: "#a0a0a0"
                    font.pixelSize: 11 * App.fontScale
                }
            }
        }
    }

}
