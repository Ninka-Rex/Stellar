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
import QtQuick.Window
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts

Window {
    id: root
    title: "Columns"
    width: 480
    height: 460
    minimumWidth: 420
    minimumHeight: 380
    color: "#1e1e1e"
    flags: Qt.Dialog | Qt.WindowTitleHint | Qt.WindowCloseButtonHint

    Material.theme: Material.Dark
    Material.background: "#1e1e1e"
    Material.accent: "#4488dd"

    // columnDefs is passed in from DownloadTable and mutated in place
    property var columnDefs: []
    property var localDefs: []

    signal columnsChanged(var defs)

    function syncLocal() {
        localDefs = (columnDefs && columnDefs.slice) ? columnDefs.slice() : []
    }

    onVisibleChanged: if (visible) syncLocal()
    onColumnDefsChanged: syncLocal()

    function swap(i, j) {
        // Save contentY before the model reassignment resets it to 0
        var savedY = colListView.contentY
        var defs = localDefs.slice()
        var tmp = defs[i]; defs[i] = defs[j]; defs[j] = tmp
        localDefs = defs
        Qt.callLater(function() { colListView.contentY = savedY })
    }

    ColumnLayout {
        anchors { fill: parent; margins: 16 }
        spacing: 10

        Text { text: "Columns"; color: "#ffffff"; font.pixelSize: 16; font.bold: true }
        Text {
            text: "Check the columns that you would like visible in this list. Use the Move Up and Move Down buttons to reorder the columns however you like."
            color: "#909090"; font.pixelSize: 12
            wrapMode: Text.WordWrap; Layout.fillWidth: true
        }
        Rectangle { Layout.fillWidth: true; height: 1; color: "#3a3a3a" }

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 12

            // Column list
            Rectangle {
                Layout.fillHeight: true
                Layout.preferredWidth: 240
                color: "#252525"
                border.color: "#3a3a3a"
                radius: 3
                clip: true

                ListView {
                    id: colListView
                    anchors { fill: parent; margins: 2 }
                    model: root.localDefs
                    currentIndex: 0

                    delegate: Rectangle {
                        width: colListView.width
                        height: 34
                        color: colListView.currentIndex === index ? "#1e3a6e" : (itemMa.containsMouse ? "#2a2a2a" : "transparent")

                        RowLayout {
                            anchors { fill: parent; leftMargin: 8; rightMargin: 8 }
                            spacing: 8

                            CheckBox {
                                checked: modelData.visible
                                topPadding: 0; bottomPadding: 0
                                onCheckedChanged: {
                                    var defs = root.localDefs.slice()
                                    defs[index] = Object.assign({}, defs[index], { visible: checked })
                                    root.localDefs = defs
                                }
                            }

                            Text {
                                text: modelData.title
                                color: colListView.currentIndex === index ? "#ffffff" : "#d0d0d0"
                                font.pixelSize: 13
                                Layout.fillWidth: true
                            }
                        }

                        MouseArea {
                            id: itemMa
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: colListView.currentIndex = index
                        }
                    }
                }
            }

            // Buttons
            ColumnLayout {
                spacing: 6

                Rectangle {
                    width: 100; height: 28; radius: 3
                    color: moveUpMa.containsMouse && colListView.currentIndex > 0 ? "#1e3a6e" : "#2d2d2d"
                    border.color: "#555"; border.width: 1
                    opacity: colListView.currentIndex > 0 ? 1.0 : 0.4
                    Text { anchors.centerIn: parent; text: "Move Up"; color: "#d0d0d0"; font.pixelSize: 12 }
                    MouseArea {
                        id: moveUpMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: colListView.currentIndex > 0 ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onClicked: {
                            const i = colListView.currentIndex
                            if (i > 0) { root.swap(i, i - 1); colListView.currentIndex = i - 1 }
                        }
                    }
                }

                Rectangle {
                    width: 100; height: 28; radius: 3
                    color: moveDownMa.containsMouse && colListView.currentIndex < root.localDefs.length - 1 ? "#1e3a6e" : "#2d2d2d"
                    border.color: "#555"; border.width: 1
                    opacity: colListView.currentIndex < root.localDefs.length - 1 ? 1.0 : 0.4
                    Text { anchors.centerIn: parent; text: "Move Down"; color: "#d0d0d0"; font.pixelSize: 12 }
                    MouseArea {
                        id: moveDownMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: colListView.currentIndex < root.localDefs.length - 1 ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onClicked: {
                            const i = colListView.currentIndex
                            if (i < root.localDefs.length - 1) { root.swap(i, i + 1); colListView.currentIndex = i + 1 }
                        }
                    }
                }

                Rectangle { width: 100; height: 1; color: "#3a3a3a" }

                Rectangle {
                    width: 100; height: 28; radius: 3
                    property bool canShow: colListView.currentIndex >= 0
                        && root.localDefs.length > colListView.currentIndex
                        && !root.localDefs[colListView.currentIndex].visible
                    color: showMa.containsMouse && canShow ? "#1e3a6e" : "#2d2d2d"
                    border.color: "#555"; border.width: 1
                    opacity: canShow ? 1.0 : 0.4
                    Text { anchors.centerIn: parent; text: "Show"; color: "#d0d0d0"; font.pixelSize: 12 }
                    MouseArea {
                        id: showMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: parent.canShow ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onClicked: {
                            if (parent.canShow) {
                                var defs = root.localDefs.slice()
                                defs[colListView.currentIndex] = Object.assign({}, defs[colListView.currentIndex], { visible: true })
                                root.localDefs = defs
                            }
                        }
                    }
                }

                Rectangle {
                    width: 100; height: 28; radius: 3
                    property bool canHide: colListView.currentIndex >= 0
                        && root.localDefs.length > colListView.currentIndex
                        && root.localDefs[colListView.currentIndex].visible
                    color: hideMa.containsMouse && canHide ? "#1e3a6e" : "#2d2d2d"
                    border.color: "#555"; border.width: 1
                    opacity: canHide ? 1.0 : 0.4
                    Text { anchors.centerIn: parent; text: "Hide"; color: "#d0d0d0"; font.pixelSize: 12 }
                    MouseArea {
                        id: hideMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: parent.canHide ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onClicked: {
                            if (parent.canHide) {
                                var defs = root.localDefs.slice()
                                defs[colListView.currentIndex] = Object.assign({}, defs[colListView.currentIndex], { visible: false })
                                root.localDefs = defs
                            }
                        }
                    }
                }

                Rectangle {
                    width: 100; height: 28; radius: 3
                    color: resetMa.containsMouse ? "#443020" : "#2d2d2d"
                    border.color: "#555"; border.width: 1
                    Text { anchors.centerIn: parent; text: "Reset"; color: "#e09060"; font.pixelSize: 12 }
                    MouseArea {
                        id: resetMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.columnsChanged(null)  // null = reset to default
                    }
                }

                Item { Layout.fillHeight: true }
            }
        }

        // Width editor
        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            Text {
                text: "The selected column should be"
                color: "#909090"; font.pixelSize: 12
            }
            TextField {
                implicitWidth: 60; implicitHeight: 26
                text: colListView.currentIndex >= 0 && root.localDefs.length > colListView.currentIndex
                      ? (root.localDefs[colListView.currentIndex].widthPx || 120).toString()
                      : "120"
                color: "#d0d0d0"; font.pixelSize: 12
                background: Rectangle { color: "#2d2d2d"; border.color: "#4a4a4a"; radius: 3 }
                leftPadding: 6
                validator: IntValidator { bottom: 30; top: 1200 }
                onEditingFinished: {
                    const v = parseInt(text)
                    if (!isNaN(v) && v >= 30 && colListView.currentIndex >= 0) {
                        var defs = root.localDefs.slice()
                        defs[colListView.currentIndex] = Object.assign({}, defs[colListView.currentIndex], { widthPx: v })
                        root.localDefs = defs
                    }
                }
            }
            Text { text: "pixels wide"; color: "#909090"; font.pixelSize: 12 }
        }

        Rectangle { Layout.fillWidth: true; height: 1; color: "#3a3a3a" }

        // OK / Cancel
        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            Item { Layout.fillWidth: true }
            DlgButton {
                text: "OK"
                primary: true
                onClicked: {
                    root.columnsChanged(root.localDefs)
                    root.close()
                }
            }
            DlgButton {
                text: "Cancel"
                onClicked: root.close()
            }
        }
    }
}
