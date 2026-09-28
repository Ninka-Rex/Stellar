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

// Read-only readout laid out like a Preferences page (SettingsSection /
// SettingsRow), so it shares the About page's look and its handling of long
// translations: the label column widens to the longest label, and a label too
// long to sit beside its value stacks above it instead of clipping.
Window {
    id: root
    title: qsTr("Statistics")
    // Width is fixed and height follows the content. Rows reflow against the
    // width, so a long translation adds height; deriving the width from the
    // content as well would let stacking and width chase each other.
    // minimumHeight is deliberately not bound to the content: before the
    // section has a width every row stacks, and the native frame would clamp
    // to that transient height and stay there.
    width: Math.round(440 * App.fontScale)
    height: layout.implicitHeight
    minimumWidth: Math.round(340 * App.fontScale)
    minimumHeight: Math.round(200 * App.fontScale)
    color: ColorPalette.cardBg
    flags: Qt.Window | Qt.WindowCloseButtonHint | Qt.WindowTitleHint

    Material.theme: ColorPalette.materialTheme
    Material.foreground: ColorPalette.textPrimary
    Material.accent: "#4488dd"

    property var stats: ({})

    // Numbers and dates follow the chosen UI language rather than the OS
    // locale, so a German UI shows "1,50 GB" and a localized month name even
    // on an English system. No UI language means English strings, so the OS
    // locale is the best guess for formatting.
    readonly property var displayLocale: App.settings.uiLanguage.length > 0
                                         ? Qt.locale(App.settings.uiLanguage)
                                         : Qt.locale()

    function refresh() { stats = App.appStatistics() }

    Component.onCompleted: refresh()
    onVisibleChanged: { if (visible) refresh() }

    Timer {
        interval: 2000
        running: root.visible
        repeat: true
        onTriggered: root.refresh()
    }

    function formatNumber(n, decimals) {
        return Number(n).toLocaleString(displayLocale, "f", decimals)
    }

    // Units are whole translatable templates so a language can use its own
    // abbreviations and placement (French "%1 Go", Russian "%1 ГБ").
    function formatBytes(bytes) {
        var n = Math.max(0, Number(bytes) || 0)
        if (n < 1024)
            return qsTr("%1 B").arg(formatNumber(n, 0))
        var units = [qsTr("%1 KB"), qsTr("%1 MB"), qsTr("%1 GB"), qsTr("%1 TB")]
        var i = -1
        do {
            n /= 1024
            ++i
        } while (n >= 1024 && i < units.length - 1)
        return units[i].arg(formatNumber(n, 2))
    }

    // One template per shape instead of concatenated unit suffixes, so a
    // translation can reorder, re-space or pick its own abbreviations.
    function formatUptime(secs) {
        var s = Math.max(0, Math.floor(Number(secs) || 0))
        var d = Math.floor(s / 86400)
        var h = Math.floor((s % 86400) / 3600)
        var m = Math.floor((s % 3600) / 60)
        if (d > 0)
            return qsTr("%1 d %2 h %3 min").arg(formatNumber(d, 0)).arg(formatNumber(h, 0)).arg(formatNumber(m, 0))
        if (h > 0)
            return qsTr("%1 h %2 min").arg(formatNumber(h, 0)).arg(formatNumber(m, 0))
        return qsTr("%1 min").arg(formatNumber(m, 0))
    }

    // The locale's long date format carries the month name in the right order
    // for each language, but also the weekday, which is noise for an install
    // date. Drop the weekday token and the separator that joins it (Latin or
    // Arabic comma) rather than hand-writing a pattern that fixes one order.
    // The date arrives as a bare ISO "yyyy-MM-dd". Built from its parts because
    // new Date("yyyy-MM-dd") means UTC midnight, which shows the previous day
    // anywhere west of UTC.
    function formatDate(iso) {
        var parts = /^(\d{4})-(\d{2})-(\d{2})$/.exec(iso || "")
        if (!parts)
            return "–"
        var d = new Date(Number(parts[1]), Number(parts[2]) - 1, Number(parts[3]))
        if (isNaN(d.getTime()))
            return "–"
        var fmt = displayLocale.dateFormat(Locale.LongFormat)
            .replace(/dddd[,،]?\s*/, "")
            .replace(/[,،]?\s*dddd/, "")
            .trim()
        return d.toLocaleDateString(displayLocale, fmt)
    }

    component StatRow: SettingsRow {
        id: statRow
        property string value
        property color valueColor: ColorPalette.textPrimary
        property bool valueBold: false

        Text {
            Layout.fillWidth: true
            text: statRow.value
            color: statRow.valueColor
            font.pixelSize: 13 * App.fontScale
            font.bold: statRow.valueBold
            wrapMode: Text.WordWrap
        }
    }

    ColumnLayout {
        id: layout
        anchors { left: parent.left; right: parent.right; top: parent.top }
        spacing: 0

        // Same padding and section spacing as a Preferences page body.
        ColumnLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 16
            Layout.rightMargin: 16
            Layout.topMargin: 14
            Layout.bottomMargin: 16
            spacing: 20

            SettingsSection {
                title: qsTr("All time")

                StatRow { label: qsTr("Downloaded"); value: root.formatBytes(root.stats.downloadedBytes) }
                StatRow { label: qsTr("Uploaded");   value: root.formatBytes(root.stats.uploadedBytes) }
                StatRow {
                    label: qsTr("Share ratio")
                    value: root.formatNumber(root.stats.ratio || 0, 2)
                    valueColor: ColorPalette.ratioColor(root.stats.ratio || 0)
                    valueBold: true
                }
                StatRow { label: qsTr("Uptime");         value: root.formatUptime(root.stats.totalUptimeSecs) }
                StatRow { label: qsTr("Install date");   value: root.formatDate(root.stats.installDate) }
                StatRow { label: qsTr("Times launched"); value: root.formatNumber(root.stats.totalStartups || 0, 0) }
            }

            SettingsSection {
                title: qsTr("This session")

                StatRow { label: qsTr("Downloaded"); value: root.formatBytes(root.stats.sessionDownloaded) }
                StatRow { label: qsTr("Uploaded");   value: root.formatBytes(root.stats.sessionUploaded) }
                StatRow { label: qsTr("Uptime");     value: root.formatUptime(root.stats.sessionUptimeSecs) }
            }

            // appStatistics() sums torrent transfer counters only; say so, or
            // "Downloaded" reads as every HTTP download too.
            SettingsHint {
                text: qsTr("Downloaded, uploaded and share ratio count torrent traffic only.")
            }
        }

        // Footer matches the Preferences window's button strip.
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 1
            color: ColorPalette.border
        }
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 52
            color: ColorPalette.panelBg

            DlgButton {
                anchors { right: parent.right; verticalCenter: parent.verticalCenter; rightMargin: 12 }
                text: qsTr("Close")
                onClicked: root.close()
            }
        }
    }
}
