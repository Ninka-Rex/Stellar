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
import QtQuick.Layouts

Rectangle {
    id: root
    color: "#1f1f1f"

    signal categorySelected(string catId)

    property int selectedIndex: 0

    // ── "Categories" header bar ──────────────────────────────────────────────
    Rectangle {
        id: catHeader
        anchors { top: parent.top; left: parent.left; right: parent.right }
        height: 26
        color: "#2d2d2d"

        Rectangle { width: 3; height: parent.height; color: "#5588cc" }

        Text {
            anchors { verticalCenter: parent.verticalCenter; left: parent.left; leftMargin: 8 }
            text: "Categories"
            color: "#d0d0d0"
            font.pixelSize: 12
            font.bold: true
        }

        Text {
            anchors { verticalCenter: parent.verticalCenter; right: parent.right; rightMargin: 6 }
            text: "✕"
            color: "#888"
            font.pixelSize: 10
        }

        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: "#3a3a3a" }
    }

    property bool allDownloadsExpanded: true
    property bool queuesExpanded: true

    // ── Unified list with expandable sections ─────────────────────────────────
    ScrollView {
        id: mainScroll
        anchors { top: catHeader.bottom; left: parent.left; right: parent.right; bottom: statusCats.top }
        clip: true

        Column {
            width: mainScroll.width
            spacing: 0

            // ── All Downloads section ────────────────────────────────────────
            Rectangle {
                width: parent.width
                height: 28
                color: root.selectedIndex === 999 ? "#1e3a6e" : (allDlMouse.containsMouse ? "#2a2a3a" : "transparent")
                border.color: root.selectedIndex === 999 ? "#4488dd" : "transparent"
                border.width: 1

                Row {
                    anchors { verticalCenter: parent.verticalCenter; left: parent.left; leftMargin: 6 }
                    spacing: 5

                    Text {
                        text: root.allDownloadsExpanded ? "▼" : "▶"
                        color: "#999"
                        font.pixelSize: 12
                        width: 16
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Text {
                        text: "All Downloads"
                        color: root.selectedIndex === 999 ? "#88bbff" : "#cccccc"
                        font.pixelSize: 12
                        font.bold: root.selectedIndex === 999
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                MouseArea {
                    id: allDlMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: {
                        root.selectedIndex = 999
                        root.categorySelected("all")
                    }
                    onDoubleClicked: root.allDownloadsExpanded = !root.allDownloadsExpanded
                }
            }

            // Categories list (shown when All Downloads expanded, exclude "All Downloads")
            Repeater {
                model: root.allDownloadsExpanded ? App.categoryModel : 0

                delegate: Rectangle {
                    visible: categoryId !== "all"
                    width: mainScroll.width
                    height: visible ? 26 : 0
                    color: root.selectedIndex === index ? "#1e3a6e" : (catMouse.containsMouse ? "#2a2a3a" : (dropArea.containsDrag ? "#2a3a2a" : "transparent"))
                    border.color: root.selectedIndex === index ? "#4488dd" : "transparent"
                    border.width: 1

                    Row {
                        anchors { verticalCenter: parent.verticalCenter; left: parent.left; leftMargin: 6 + 16 }
                        spacing: 5

                        Image {
                            source: categoryIcon
                            width: 16; height: 16
                            sourceSize.width: 16; sourceSize.height: 16
                            fillMode: Image.PreserveAspectFit
                            smooth: true
                            mipmap: true
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        Text {
                            text: categoryLabel
                            color: root.selectedIndex === index ? "#88bbff" : "#cccccc"
                            font.pixelSize: 12
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }

                    MouseArea {
                        id: catMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: {
                            root.selectedIndex = index
                            root.categorySelected(categoryId)
                        }
                    }

                    DropArea {
                        id: dropArea
                        anchors.fill: parent
                        keys: ["text/downloadId"]

                        onDropped: (drop) => {
                            var downloadId = drop.source ? drop.source.dragDownloadId : ""
                            if (downloadId && downloadId.length > 0) {
                                App.setDownloadCategory(downloadId, categoryId)
                                drop.accept()
                            }
                        }
                    }
                }
            }


            // ── Queues section ──────────────────────────────────────────────────────
            Rectangle {
                width: parent.width
                height: 28
                color: "transparent"

                Row {
                    anchors { verticalCenter: parent.verticalCenter; left: parent.left; leftMargin: 6 }
                    spacing: 5

                    Text {
                        text: root.queuesExpanded ? "▼" : "▶"
                        color: "#999"
                        font.pixelSize: 12
                        width: 16
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Image {
                        width: 16; height: 16
                        sourceSize.width: 16; sourceSize.height: 16
                        fillMode: Image.PreserveAspectFit
                        source: "qrc:/qt/qml/com/stellar/app/app/qml/icons/queues.png"
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Text {
                        text: "Queues"
                        color: "#cccccc"
                        font.pixelSize: 12
                        font.bold: true
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    onDoubleClicked: root.queuesExpanded = !root.queuesExpanded
                }
            }

            // Queues list (shown when Queues expanded, exclude download-limits)
            Repeater {
                model: root.queuesExpanded ? App.queueModel : 0

                delegate: Rectangle {
                    visible: queueId !== "download-limits"
                    width: mainScroll.width
                    height: visible ? 26 : 0
                    color: queueMouse.containsMouse ? "#2a2a3a" : (queueDropArea.containsDrag ? "#2a3a2a" : "transparent")
                    border.color: queueMouse.containsMouse ? "#4488dd" : "transparent"
                    border.width: 1

                    Row {
                        anchors { verticalCenter: parent.verticalCenter; left: parent.left; leftMargin: 22 }
                        spacing: 5

                        Image {
                            width: 16; height: 16
                            sourceSize.width: 16; sourceSize.height: 16
                            fillMode: Image.PreserveAspectFit
                            source: {
                                if (queueId === "main-download") return "qrc:/qt/qml/com/stellar/app/app/qml/icons/main_queue.png"
                                if (queueId === "main-sync") return "qrc:/qt/qml/com/stellar/app/app/qml/icons/synch_queue.png"
                                return "qrc:/qt/qml/com/stellar/app/app/qml/icons/custom_queue.png"
                            }
                        }

                        Text {
                            text: queueName || ""
                            color: "#cccccc"
                            font.pixelSize: 12
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }

                    MouseArea {
                        id: queueMouse
                        anchors.fill: parent
                        hoverEnabled: true
                    }

                    DropArea {
                        id: queueDropArea
                        anchors.fill: parent
                        keys: ["text/downloadId"]

                        onDropped: (drop) => {
                            var downloadId = drop.source ? drop.source.dragDownloadId : ""
                            if (downloadId && downloadId.length > 0) {
                                App.setDownloadQueue(downloadId, queueId)
                                drop.accept()
                            }
                        }
                    }
                }
            }
        }
    }

    // ── Static "Unfinished" / "Finished" section ─────────────────────────────
    Column {
        id: statusCats
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }

        Rectangle {
            width: parent.width; height: 1; color: "#3a3a3a"
        }

        Repeater {
            id: statusRepeater
            model: [
                { label: "Unfinished", catId: "status_active",    iconSrc: "icons/folder.ico" },
                { label: "Finished",   catId: "status_completed", iconSrc: "icons/folder.ico" }
            ]

            delegate: Rectangle {
                width: statusCats.width
                height: 26
                // selectedIndex uses negative values for status entries: -1 = Unfinished, -2 = Finished
                color: root.selectedIndex === -(index + 1)
                       ? "#1e3a6e"
                       : (statusMa.containsMouse ? "#2a2a3a" : "transparent")

                Row {
                    anchors { verticalCenter: parent.verticalCenter; left: parent.left; leftMargin: 6 }
                    spacing: 5
                    Image {
                        source: modelData.iconSrc
                        width: 16; height: 16
                        sourceSize.width: 16; sourceSize.height: 16
                        fillMode: Image.PreserveAspectFit
                        smooth: true; mipmap: true
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Text {
                        text: modelData.label
                        color: root.selectedIndex === -(index + 1) ? "#ffffff" : "#cccccc"
                        font.pixelSize: 12
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                MouseArea {
                    id: statusMa
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: {
                        root.selectedIndex = -(index + 1)
                        root.categorySelected(modelData.catId)
                    }
                }
            }
        }
    }

    // Right border divider
    Rectangle {
        anchors { top: parent.top; bottom: parent.bottom; right: parent.right }
        width: 1
        color: "#3a3a3a"
    }
}
