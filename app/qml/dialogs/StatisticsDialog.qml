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
    title: qsTr("Statistics")
    // ?? Height is driven by content no filler space. ?????????????????????
    // Width driven by content too so longer translations (e.g. French) don't clip.
    // Content-driven size. No fixed-size hint: it freezes the native frame at
    // show-time dimensions, ignoring late content growth (long French labels,
    // large byte values that arrive on first async refresh()).
    width: Math.max(320, mainCol.implicitWidth + 16)
    height: Math.max(180, mainCol.implicitHeight + 16)
    minimumWidth: 320
    minimumHeight: 180
    color: ColorPalette.cardBg
    flags: Qt.Window | Qt.WindowCloseButtonHint | Qt.WindowTitleHint

    Material.theme: ColorPalette.materialTheme
    Material.foreground: ColorPalette.textPrimary
    Material.accent: "#4488dd"

    property var stats: ({})

    function refresh() { stats = App.appStatistics() }

    Component.onCompleted: refresh()
    onVisibleChanged: { if (visible) refresh() }

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

    // Ratio colour ramp:
    // ?? 0.0 red (#ff5555) ????????????????????????????????????????????????
    // ?? 0.5 orange (#ff9944) ?????????????????????????????????????????????
    // ?? 1.0 green (#55cc66) ??????????????????????????????????????????????
    // ?? 2.0 lime (#99ee55) ???????????????????????????????????????????????
    // ?? 4.0 cyan (#44ddcc) ???????????????????????????????????????????????
    // ?? 6.0 blue (#4499ff) ???????????????????????????????????????????????
    // ?? 8.0 purple (#aa55ff) ?????????????????????????????????????????????
    // ?? 10.0+ magenta (#ff44cc) ??????????????????????????????????????????
    function ratioColor(r) {
        r = r || 0
        function lerp(a, b, t) {
            return Math.round(a + (b - a) * Math.max(0, Math.min(1, t)))
        }
        function rgb(hr, hg, hb) {
            return "#" + ("0" + hr.toString(16)).slice(-2)
                       + ("0" + hg.toString(16)).slice(-2)
                       + ("0" + hb.toString(16)).slice(-2)
        }
        // stops: [ratio, r, g, b]
        var stops = [
            [0.0,  255, 85,  85],
            [0.5,  255, 153, 68],
            [1.0,  85,  204, 102],
            [2.0,  153, 238, 85],
            [4.0,  68,  221, 204],
            [6.0,  68,  153, 255],
            [8.0,  170, 85,  255],
            [10.0, 255, 68,  204]
        ]
        if (r <= stops[0][0]) return rgb(stops[0][1], stops[0][2], stops[0][3])
        if (r >= stops[stops.length-1][0]) return rgb(stops[stops.length-1][1], stops[stops.length-1][2], stops[stops.length-1][3])
        for (var i = 1; i < stops.length; i++) {
            if (r <= stops[i][0]) {
                var t = (r - stops[i-1][0]) / (stops[i][0] - stops[i-1][0])
                return rgb(lerp(stops[i-1][1], stops[i][1], t),
                           lerp(stops[i-1][2], stops[i][2], t),
                           lerp(stops[i-1][3], stops[i][3], t))
            }
        }
        return "#ff44cc"
    }

    // Stats row helper: label on left, value on right, value left-aligned after label.
    // Using a plain Row so the value sits immediately after the label with no column stretching.
    component StatRow: Row {
        property string label: ""
        property string value: ""
        property color valueColor: ColorPalette.textPrimary
        property bool valueBold: false
        spacing: 6

        Text {
            text: parent.label
            color: ColorPalette.infoBoxText
            font.pixelSize: 11 * App.fontScale
        }
        Text {
            text: parent.value
            color: parent.valueColor
            font.pixelSize: 11 * App.fontScale
            font.bold: parent.valueBold
        }
    }

    ColumnLayout {
        id: mainCol
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 8 }
        spacing: 6

        Text {
            text: qsTr("Stellar Statistics")
            color: ColorPalette.textPrimary
            font.pixelSize: 13 * App.fontScale
            font.bold: true
        }

        Rectangle { Layout.fillWidth: true; height: 1; color: ColorPalette.dividerBg }

        // ?? All-time + This session in one card ??????????????????????????
        Rectangle {
            Layout.fillWidth: true
            color: ColorPalette.inputBg
            border.color: ColorPalette.dividerBg
            radius: 3
            // Both implicit dims required: the card uses anchored fill for its
            // RowLayout, so without implicitWidth it reports 0 width to mainCol
            // and the window never widens to fit the columns (clips session col).
            implicitWidth: panelRow.implicitWidth + 12
            implicitHeight: panelRow.implicitHeight + 10

            RowLayout {
                id: panelRow
                anchors { fill: parent; margins: 6 }
                spacing: 40

                // All-time column — sized to its content so labels never clip.
                ColumnLayout {
                    id: atCol
                    Layout.alignment: Qt.AlignTop
                    spacing: 2

                    Text { text: qsTr("ALL TIME"); color: "#445566"; font.pixelSize: 9 * App.fontScale; font.bold: true; font.letterSpacing: 1 }

                    StatRow { label: qsTr("Downloaded");   value: root.formatBytes(root.stats.downloadedBytes) }
                    StatRow { label: qsTr("Uploaded");     value: root.formatBytes(root.stats.uploadedBytes) }
                    StatRow { label: qsTr("Share Ratio");  value: (root.stats.ratio || 0).toFixed(3); valueColor: root.ratioColor(root.stats.ratio || 0); valueBold: true }
                    StatRow { label: qsTr("Uptime");       value: root.formatUptime(root.stats.totalUptimeSecs) }
                    StatRow {
                        label: qsTr("Install Date")
                        value: {
                            var d = root.stats.installDate || ""
                            return d ? new Date(d).toLocaleDateString(Qt.locale(), "MMM d, yyyy") : "–"
                        }
                    }
                    StatRow { label: qsTr("Startups");     value: (root.stats.totalStartups || 0).toString() }
                }

                // This session column
                ColumnLayout {
                    id: sesCol
                    Layout.fillWidth: true
                    Layout.minimumWidth: implicitWidth
                    Layout.alignment: Qt.AlignTop
                    spacing: 2

                    Text { text: qsTr("THIS SESSION"); color: "#445566"; font.pixelSize: 9 * App.fontScale; font.bold: true; font.letterSpacing: 1 }

                    StatRow { label: qsTr("Downloaded");  value: root.formatBytes(root.stats.sessionDownloaded) }
                    StatRow { label: qsTr("Uploaded");    value: root.formatBytes(root.stats.sessionUploaded) }
                    StatRow { label: qsTr("Uptime");      value: root.formatUptime(root.stats.sessionUptimeSecs) }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Item { Layout.fillWidth: true }
            DlgButton { text: qsTr("Close"); onClicked: root.close() }
        }

        // Bottom breathing room so Close button isn't flush against the edge.
        Item { implicitHeight: 2 }
    }
}
