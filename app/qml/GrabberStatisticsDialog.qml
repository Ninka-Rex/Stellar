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
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts

Window {
    id: root
    title: "Grabber Statistics"
    width: 320
    height: 260
    minimumWidth: 300
    minimumHeight: 240
    color: "#1e1e1e"
    flags: Qt.Dialog | Qt.WindowTitleHint | Qt.WindowCloseButtonHint
    modality: Qt.ApplicationModal

    Material.theme: Material.Dark
    Material.background: "#1e1e1e"
    Material.accent: "#4488dd"

    property string projectId: ""
    property var stats: ({})

    function refreshStats() {
        stats = App.grabberStatistics(projectId)
    }

    onVisibleChanged: if (visible) refreshStats()

    Timer {
        interval: 1000
        running: root.visible
        repeat: true
        onTriggered: root.refreshStats()
    }

    Rectangle {
        anchors.fill: parent
        color: "#1e1e1e"
        border.color: "#343434"

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 12
            spacing: 10

            Text {
                text: "Status: " + (stats.status || "Idle")
                color: "#eef2f7"
                font.pixelSize: 14
                font.bold: true
                Layout.fillWidth: true
            }
            Rectangle { Layout.fillWidth: true; height: 1; color: "#343434" }

            Text { text: "Web pages processed"; color: "#aab3c2"; font.pixelSize: 12; font.bold: true }
            GridLayout {
                columns: 2
                columnSpacing: 20
                rowSpacing: 6
                Text { text: "Simple"; color: "#dce2eb"; font.pixelSize: 12 }
                Text { text: String(stats.webPagesProcessed || 0); color: "#f4f7fb"; font.pixelSize: 12 }
                Text { text: "Advanced"; color: "#dce2eb"; font.pixelSize: 12 }
                Text { text: String(stats.advancedPagesProcessed || 0); color: "#f4f7fb"; font.pixelSize: 12 }
            }

            Rectangle { Layout.fillWidth: true; height: 1; color: "#343434" }

            Text { text: "Files"; color: "#aab3c2"; font.pixelSize: 12; font.bold: true }
            GridLayout {
                columns: 2
                columnSpacing: 20
                rowSpacing: 6
                Text { text: "Total"; color: "#dce2eb"; font.pixelSize: 12 }
                Text { text: String(stats.filesTotal || 0); color: "#f4f7fb"; font.pixelSize: 12 }
                Text { text: "Explored"; color: "#dce2eb"; font.pixelSize: 12 }
                Text { text: String(stats.filesExplored || 0); color: "#f4f7fb"; font.pixelSize: 12 }
                Text { text: "Matched"; color: "#dce2eb"; font.pixelSize: 12 }
                Text { text: String(stats.filesMatched || 0); color: "#f4f7fb"; font.pixelSize: 12 }
                Text { text: "Downloaded"; color: "#dce2eb"; font.pixelSize: 12 }
                Text { text: String(stats.filesDownloaded || 0); color: "#f4f7fb"; font.pixelSize: 12 }
            }

            Item { Layout.fillHeight: true }

            RowLayout {
                Layout.fillWidth: true
                Item { Layout.fillWidth: true }
                DlgButton { text: "Close"; primary: true; onClicked: root.close() }
            }
        }
    }
}
