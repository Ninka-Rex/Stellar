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
    title: qsTr("Grabber Statistics")
    width: 270
    height: mainCol.implicitHeight + 16
    minimumWidth: 270
    color: ColorPalette.cardBg
    flags: Qt.Window | Qt.WindowCloseButtonHint | Qt.WindowTitleHint | Qt.MSWindowsFixedSizeDialogHint

    Material.theme: ColorPalette.materialTheme
    Material.foreground: ColorPalette.textPrimary
    Material.accent: "#4488dd"

    property string projectId: ""
    property var stats: ({})

    function refreshStats() { stats = App.grabberStatistics(projectId) }

    onVisibleChanged: if (visible) refreshStats()

    Timer {
        interval: 1000
        running: root.visible
        repeat: true
        onTriggered: root.refreshStats()
    }

    component StatRow: Item {
        property string label: ""
        property string value: ""
        property color valueColor: ColorPalette.textPrimary
        property bool valueBold: false
        implicitHeight: 16
        Layout.fillWidth: true

        Text {
            id: lbl
            text: parent.label
            color: ColorPalette.infoBoxText
            font.pixelSize: 11 * App.fontScale
            anchors.left: parent.left
        }
        Text {
            text: parent.value
            color: parent.valueColor
            font.pixelSize: 11 * App.fontScale
            font.bold: parent.valueBold
            anchors.left: lbl.right
            anchors.leftMargin: 6
        }
    }

    ColumnLayout {
        id: mainCol
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 8 }
        spacing: 6

        Text {
            text: qsTr("Grabber Statistics")
            color: ColorPalette.textPrimary
            font.pixelSize: 13 * App.fontScale
            font.bold: true
        }

        Rectangle { Layout.fillWidth: true; height: 1; color: ColorPalette.dividerBg }

        // ── All stats in one card ────────────────────────────────────────
        Rectangle {
            Layout.fillWidth: true
            color: ColorPalette.inputBg
            border.color: ColorPalette.dividerBg
            radius: 3
            implicitHeight: panelRow.implicitHeight + 10

            RowLayout {
                id: panelRow
                anchors { fill: parent; margins: 6 }
                spacing: 64

                // Status + Web pages column
                ColumnLayout {
                    Layout.fillWidth: false
                    Layout.alignment: Qt.AlignTop
                    spacing: 2

                    Text { text: qsTr("STATUS"); color: "#445566"; font.pixelSize: 9 * App.fontScale; font.bold: true; font.letterSpacing: 1 }
                    StatRow { label: qsTr("State"); value: stats.status || qsTr("Idle") }

                    Item { implicitHeight: 4 }

                    Text { text: qsTr("WEB PAGES"); color: "#445566"; font.pixelSize: 9 * App.fontScale; font.bold: true; font.letterSpacing: 1 }
                    StatRow { label: qsTr("Simple");   value: String(stats.webPagesProcessed || 0) }
                    StatRow { label: qsTr("Advanced"); value: String(stats.advancedPagesProcessed || 0) }
                }

                // Files column
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignTop
                    spacing: 2

                    Text { text: qsTr("FILES"); color: "#445566"; font.pixelSize: 9 * App.fontScale; font.bold: true; font.letterSpacing: 1 }
                    StatRow { label: qsTr("Total");      value: String(stats.filesTotal || 0) }
                    StatRow { label: qsTr("Explored");   value: String(stats.filesExplored || 0) }
                    StatRow { label: qsTr("Matched");    value: String(stats.filesMatched || 0) }
                    StatRow { label: qsTr("Downloaded"); value: String(stats.filesDownloaded || 0) }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Item { Layout.fillWidth: true }
            DlgButton { text: qsTr("Close"); onClicked: root.close() }
        }

        Item { implicitHeight: 2 }
    }
}
