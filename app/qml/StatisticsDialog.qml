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
import QtQuick.Controls.Material

Window {
    id: root
    title: "Statistics"
    // Height is driven by content — no filler space.
    width: 280
    height: mainCol.implicitHeight + 16
    minimumWidth: 280
    color: "#1e1e1e"
    flags: Qt.Window | Qt.WindowCloseButtonHint | Qt.WindowTitleHint | Qt.MSWindowsFixedSizeDialogHint

    Material.theme: Material.Dark
    Material.accent: "#4488dd"

    property var stats: ({})

    function refresh() { stats = App.appStatistics() }

    Component.onCompleted: refresh()

    Timer {
        interval: 2000
        running: root.visible
        repeat: true
        onTriggered: root.refresh()
    }

    function formatBytes(b) {
        b = b || 0
        if (b >= 1099511627776) return (b / 1099511627776).toFixed(2) + " TB"
        if (b >= 1073741824)    return (b / 1073741824).toFixed(2)    + " GB"
        if (b >= 1048576)       return (b / 1048576).toFixed(2)       + " MB"
        if (b >= 1024)          return (b / 1024).toFixed(1)          + " KB"
        return b + " B"
    }

    function formatUptime(secs) {
        secs = secs || 0
        const d = Math.floor(secs / 86400)
        const h = Math.floor((secs % 86400) / 3600)
        const m = Math.floor((secs % 3600)  / 60)
        var parts = []
        if (d > 0) parts.push(d + "d")
        if (h > 0) parts.push(h + "h")
        parts.push(m + "m")
        return parts.join(" ")
    }

    function ratioColor(r) {
        if (r >= 1.0) return "#7bd88f"
        if (r >= 0.5) return "#f0c060"
        return "#ff8a80"
    }

    // Stats row helper: label on left, value on right, value left-aligned after label.
    // Using a plain Row so the value sits immediately after the label with no column stretching.
    component StatRow: Item {
        property string label: ""
        property string value: ""
        property color valueColor: "#c8c8c8"
        property bool valueBold: false
        implicitHeight: 16
        Layout.fillWidth: true

        Text {
            id: lbl
            text: parent.label
            color: "#8899aa"
            font.pixelSize: 11
            anchors.left: parent.left
        }
        Text {
            text: parent.value
            color: parent.valueColor
            font.pixelSize: 11
            font.bold: parent.valueBold
            // Fixed offset so both panels align their value column identically.
            anchors.left: parent.left
            anchors.leftMargin: 90
        }
    }

    ColumnLayout {
        id: mainCol
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 8 }
        spacing: 6

        Text {
            text: "Stellar Statistics"
            color: "#d0d0d0"
            font.pixelSize: 13
            font.bold: true
        }

        Rectangle { Layout.fillWidth: true; height: 1; color: "#2d2d2d" }

        // ── All-time panel ───────────────────────────────────────────────────────
        Rectangle {
            Layout.fillWidth: true
            color: "#181818"
            border.color: "#2d2d2d"
            radius: 3
            implicitHeight: atCol.implicitHeight + 10

            ColumnLayout {
                id: atCol
                anchors { fill: parent; margins: 6 }
                spacing: 2

                Text { text: "ALL TIME"; color: "#445566"; font.pixelSize: 9; font.bold: true; font.letterSpacing: 1 }

                StatRow { label: "Downloaded";   value: root.formatBytes(root.stats.downloadedBytes) }
                StatRow { label: "Uploaded";     value: root.formatBytes(root.stats.uploadedBytes) }
                StatRow { label: "Share Ratio";  value: (root.stats.ratio || 0).toFixed(3); valueColor: root.ratioColor(root.stats.ratio || 0); valueBold: true }
                StatRow { label: "Uptime";       value: root.formatUptime(root.stats.totalUptimeSecs) }
                StatRow {
                    label: "Install Date"
                    value: {
                        var d = root.stats.installDate || ""
                        return d ? new Date(d).toLocaleDateString(Qt.locale(), "MMM d, yyyy") : "—"
                    }
                }
                StatRow { label: "Startups";     value: (root.stats.totalStartups || 0).toString() }
            }
        }

        // ── This session panel ───────────────────────────────────────────────────
        Rectangle {
            Layout.fillWidth: true
            color: "#181818"
            border.color: "#2d2d2d"
            radius: 3
            implicitHeight: sesCol.implicitHeight + 10

            ColumnLayout {
                id: sesCol
                anchors { fill: parent; margins: 6 }
                spacing: 2

                Text { text: "THIS SESSION"; color: "#445566"; font.pixelSize: 9; font.bold: true; font.letterSpacing: 1 }

                StatRow { label: "Downloaded";  value: root.formatBytes(root.stats.sessionDownloaded) }
                StatRow { label: "Uploaded";    value: root.formatBytes(root.stats.sessionUploaded) }
                StatRow { label: "Uptime";      value: root.formatUptime(root.stats.sessionUptimeSecs) }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Item { Layout.fillWidth: true }
            DlgButton { text: "Close"; onClicked: root.close() }
        }

        // Bottom breathing room so Close button isn't flush against the edge.
        Item { implicitHeight: 2 }
    }
}
