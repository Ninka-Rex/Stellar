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

Window {
    id: root
    title: "Duplicate Torrent"
    width: 440
    height: root.newTrackers.length > 0 ? 300 : 160
    minimumWidth: 380
    minimumHeight: root.newTrackers.length > 0 ? 260 : 140
    flags: Qt.Dialog | Qt.WindowTitleHint | Qt.WindowCloseButtonHint
    color: "#1e1e1e"
    modality: Qt.ApplicationModal

    property string existingDownloadId: ""
    property var newTrackers: []

    signal mergeRequested(string downloadId, var trackers)
    signal dismissed()

    function open(downloadId, trackers) {
        root.existingDownloadId = downloadId
        root.newTrackers = trackers || []
        root.show()
        root.raise()
        root.requestActivate()
    }

    onClosing: root.dismissed()

    ColumnLayout {
        anchors { fill: parent; margins: 20 }
        spacing: 14

        // Header row
        RowLayout {
            spacing: 12
            Layout.fillWidth: true

            Image {
                source: "icons/information.png"
                width: 16; height: 16
                sourceSize.width: 32; sourceSize.height: 32
                fillMode: Image.PreserveAspectFit
                smooth: true
            }

            ColumnLayout {
                spacing: 3
                Layout.fillWidth: true

                Text {
                    text: "Torrent already exists"
                    color: "#e0e0e0"
                    font.pixelSize: 15
                    font.bold: true
                }

                Text {
                    text: root.newTrackers.length > 0
                        ? "This torrent is already in your list. " + root.newTrackers.length + " new tracker" + (root.newTrackers.length === 1 ? "" : "s") + " found."
                        : "This torrent is already in your list with the same trackers."
                    color: "#aaaaaa"
                    font.pixelSize: 12
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                }
            }
        }

        // Tracker list — only shown when there are new trackers
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: trackerContent.implicitHeight + 16
            color: "#1a2030"
            border.color: "#2a3050"
            radius: 4
            visible: root.newTrackers.length > 0

            ColumnLayout {
                id: trackerContent
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 10 }
                spacing: 5

                RowLayout {
                    spacing: 6

                    Image {
                        source: "icons/link.png"
                        width: 12; height: 12
                        sourceSize.width: 24; sourceSize.height: 24
                        fillMode: Image.PreserveAspectFit
                        smooth: true
                    }

                    Text {
                        text: root.newTrackers.length === 1 ? "1 new tracker" : root.newTrackers.length + " new trackers"
                        color: "#8899bb"
                        font.pixelSize: 12
                        font.bold: true
                    }
                }

                Repeater {
                    model: Math.min(root.newTrackers.length, 4)
                    Text {
                        text: root.newTrackers[index]
                        color: "#7799cc"
                        font.pixelSize: 11
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }
                }

                Text {
                    visible: root.newTrackers.length > 4
                    text: "… and " + (root.newTrackers.length - 4) + " more"
                    color: "#667799"
                    font.pixelSize: 11
                }
            }
        }

        Item { Layout.fillHeight: true }

        // Buttons
        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Item { Layout.fillWidth: true }

            DlgButton {
                text: "Dismiss"
                onClicked: { root.dismissed(); root.close() }
            }

            DlgButton {
                primary: true
                visible: root.newTrackers.length > 0
                text: "Merge Trackers"
                onClicked: {
                    root.mergeRequested(root.existingDownloadId, root.newTrackers)
                    root.dismissed()
                    root.close()
                }
            }
        }
    }
}
