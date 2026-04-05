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
    color: "#1c1c1c"

    signal openProgressRequested(var item)

    // Window-level drag proxy injected from Main.qml
    property var categoryDragProxy: null

    // Public API called by Main.qml toolbar signals
    function resumeSelected()  { const id = _selectedId(); if (id) App.resumeDownload(id) }
    function stopSelected()    { const id = _selectedId(); if (id) App.pauseDownload(id)  }
    function deleteSelected()  {
        const item = _selectedItem()
        if (item) _openDeleteDialog(item)
    }
    function _selectedItem() {
        if (tableView.currentRow < 0) return null
        return App.downloadModel.data(
            App.downloadModel.index(tableView.currentRow, 0), Qt.UserRole + 2)
    }
    function _selectedId() {
        const item = _selectedItem()
        return item ? item.id : null
    }
    function _openDeleteDialog(item) {
        deleteDialog.downloadId = item.id
        deleteDialog.filename   = item.filename
        deleteDialog.fileExists = item.status === "Completed"
        deleteDialog.show()
        deleteDialog.raise()
        deleteDialog.requestActivate()
    }

    // ── Delete confirmation dialog ────────────────────────────────────────────
    DeleteConfirmDialog {
        id: deleteDialog
        onConfirmed: (mode) => App.deleteDownload(downloadId, mode)
    }

    // Column definitions – visibility toggled from context menu
    property var columnDefs: [
        { title: "File Name",      key: "name",       widthFrac: 0.30, visible: true  },
        { title: "Size",           key: "size",       widthFrac: 0.09, visible: true  },
        { title: "Status",         key: "status",     widthFrac: 0.10, visible: true  },
        { title: "Time left",      key: "timeleft",   widthFrac: 0.10, visible: true  },
        { title: "Transfer rate",  key: "speed",      widthFrac: 0.11, visible: true  },
        { title: "Date added",     key: "added",      widthFrac: 0.13, visible: true  },
        { title: "Save to",        key: "saveto",     widthFrac: 0.17, visible: false },
    ]

    // Compute visible columns only
    function makeVisibleCols() {
        var r = []
        for (var i = 0; i < columnDefs.length; i++)
            if (columnDefs[i].visible) r.push(columnDefs[i])
        return r
    }
    readonly property var visibleCols: makeVisibleCols()

    function colWidth(key) {
        // Redistribute fractions across visible columns
        var total = 0
        for (var i = 0; i < visibleCols.length; i++) total += visibleCols[i].widthFrac
        for (var j = 0; j < visibleCols.length; j++)
            if (visibleCols[j].key === key) return root.width * visibleCols[j].widthFrac / total
        return 0
    }

    // ── Column visibility context menu ────────────────────────────────────────
    Menu {
        id: colCtxMenu
        Repeater {
            model: root.columnDefs.length
            delegate: MenuItem {
                text: root.columnDefs[index].title
                checkable: true
                checked: root.columnDefs[index].visible
                onTriggered: {
                    var defs = root.columnDefs
                    defs[index].visible = checked
                    root.columnDefs = defs
                }
            }
        }
    }

    // ── Header ────────────────────────────────────────────────────────────────
    Rectangle {
        id: header
        anchors { top: parent.top; left: parent.left; right: parent.right }
        height: 26
        color: "#2d2d2d"

        Row {
            anchors.fill: parent

            Repeater {
                model: root.visibleCols
                delegate: Rectangle {
                    width:  root.colWidth(modelData.key)
                    height: parent.height
                    color: "transparent"

                    Text {
                        anchors { verticalCenter: parent.verticalCenter; left: parent.left; leftMargin: 6 }
                        text: modelData.title
                        color: "#b0b0b0"
                        font.pixelSize: 12
                        font.bold: true
                    }

                    Rectangle {
                        anchors.right: parent.right
                        width: 1; height: parent.height
                        color: "#3a3a3a"
                    }
                }
            }
        }

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.RightButton
            onClicked: colCtxMenu.popup()
        }

        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: "#3a3a3a" }
    }

    // ── Rows ──────────────────────────────────────────────────────────────────
    ListView {
        id: tableView
        anchors { top: header.bottom; left: parent.left; right: parent.right; bottom: parent.bottom }
        model: App.downloadModel
        clip: true
        property int currentRow: -1

        ScrollBar.vertical: ScrollBar {}

        delegate: Rectangle {
            id: rowRect
            width: tableView.width
            height: 34

            // Grab the DownloadItem* from the model — this binding IS reactive
            // because Qt model delegates re-evaluate when dataChanged fires for this row
            readonly property var item: model.item


            color: tableView.currentRow === index
                   ? "#1e3a6e"
                   : (rowMouse.containsMouse
                      ? "#2a2a2a"
                      : (index % 2 === 0 ? "#1c1c1c" : "#222222"))

            Row {
                anchors.fill: parent

                // File Name
                Item {
                    visible: root.colWidth("name") > 0
                    width: root.colWidth("name"); height: parent.height
                    clip: true
                    Row {
                        anchors { verticalCenter: parent.verticalCenter; left: parent.left; leftMargin: 6 }
                        spacing: 6

                        Rectangle {
                            width: 18; height: 18; radius: 2
                            anchors.verticalCenter: parent.verticalCenter
                            color: {
                                if (!rowRect.item) return "#606060"
                                const name = rowRect.item.filename.toLowerCase()
                                if (/\.(mp4|mkv|avi|mov|wmv|flv|webm|m4v|3gp|mpeg|mpg|ogv|rmvb|rm)$/.test(name)) return "#c04040"
                                if (/\.(mp3|flac|wav|aac|ogg|m4a|wma|aif|ra|opus)$/.test(name))                   return "#40a0c0"
                                if (/\.(zip|rar|7z|tar|gz|bz2|xz|zst|ace|sitx|unitypackage|sit|sea|r\d+)$/.test(name))        return "#c09030"
                                if (/\.(exe|msi|msu|deb|rpm|pkg|apk)$/.test(name))                   return "#6060c0"
                                if (/\.(pdf|doc|docx|ppt|pptx|xls|xlsx|epub|azw3)$/.test(name))                   return "#c06040"
                                if (/\.(safetensors|gguf)$/.test(name))                                            return "#8040a0"
                                if (/\.(iso|img|bin)$/.test(name))                                                 return "#408040"
                                return "#606060"
                            }
                            Text {
                                anchors.centerIn: parent
                                text: {
                                    if (!rowRect.item) return "•"
                                    const name = rowRect.item.filename.toLowerCase()
                                    if (/\.(mp4|mkv|avi|mov|wmv|flv|webm|m4v|3gp|mpeg|mpg|ogv|rmvb|rm)$/.test(name)) return "▶"
                                    if (/\.(mp3|flac|wav|aac|ogg|m4a|wma|aif|ra|opus)$/.test(name))                   return "♪"
                                    if (/\.(zip|rar|7z|tar|gz|bz2|xz|zst|ace|sitx|unitypackage|sit|sea|r\d+)$/.test(name))        return "Z"
                                    if (/\.(exe|msi|msu|deb|rpm|pkg|apk)$/.test(name))                   return "⚙"
                                    if (/\.(pdf|doc|docx|ppt|pptx)$/.test(name))                                      return "D"
                                    if (/\.(safetensors|gguf)$/.test(name))                                            return "AI"
                                    return "•"
                                }
                                color: "white"; font.pixelSize: 9; font.bold: true
                            }
                        }

                        Text {
                            text: rowRect.item ? rowRect.item.filename : ""
                            color: tableView.currentRow === index ? "#ffffff" : "#d0d0d0"
                            font.pixelSize: 12
                            width: root.colWidth("name") - 42
                            elide: Text.ElideMiddle
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }
                }

                // Size
                Item {
                    visible: root.colWidth("size") > 0
                    width: root.colWidth("size"); height: parent.height
                    Text {
                        anchors { verticalCenter: parent.verticalCenter; left: parent.left; leftMargin: 6 }
                        text: {
                            if (!rowRect.item || rowRect.item.totalBytes <= 0) return "--"
                            const b = rowRect.item.totalBytes
                            if (b < 1048576)    return (b / 1024).toFixed(1) + " KB"
                            if (b < 1073741824) return (b / 1048576).toFixed(1) + " MB"
                            return (b / 1073741824).toFixed(2) + " GB"
                        }
                        color: tableView.currentRow === index ? "#ffffff" : "#b0b0b0"
                        font.pixelSize: 12
                    }
                }

                // Status (with inline progress %)
                Item {
                    visible: root.colWidth("status") > 0
                    width: root.colWidth("status"); height: parent.height
                    Text {
                        anchors { verticalCenter: parent.verticalCenter; left: parent.left; leftMargin: 6 }
                        text: {
                            if (!rowRect.item) return "--"
                            const s = rowRect.item.status
                            if (s === "Downloading") return (rowRect.item.progress * 100).toFixed(1) + "%"
                            return s
                        }
                        color: {
                            if (tableView.currentRow === index) return "#ffffff"
                            if (!rowRect.item) return "#b0b0b0"
                            const s = rowRect.item.status
                            if (s === "Downloading") return "#66cc66"
                            if (s === "Paused")      return "#e0c040"
                            if (s === "Error")       return "#e06060"
                            if (s === "Completed")   return "#60c0e0"
                            return "#b0b0b0"
                        }
                        font.pixelSize: 12
                    }
                }

                // Time left
                Item {
                    visible: root.colWidth("timeleft") > 0
                    width: root.colWidth("timeleft"); height: parent.height
                    Text {
                        anchors { verticalCenter: parent.verticalCenter; left: parent.left; leftMargin: 6 }
                        text: rowRect.item ? rowRect.item.timeLeft : "--"
                        color: tableView.currentRow === index ? "#ffffff" : "#b0b0b0"
                        font.pixelSize: 12
                    }
                }

                // Transfer rate
                Item {
                    visible: root.colWidth("speed") > 0
                    width: root.colWidth("speed"); height: parent.height
                    Text {
                        anchors { verticalCenter: parent.verticalCenter; left: parent.left; leftMargin: 6 }
                        text: {
                            if (!rowRect.item || rowRect.item.status !== "Downloading") return "--"
                            const bps = rowRect.item.speed
                            if (bps <= 0)       return "--"
                            if (bps < 1048576)  return (bps / 1024).toFixed(1) + " KB/s"
                            return (bps / 1048576).toFixed(2) + " MB/s"
                        }
                        color: tableView.currentRow === index ? "#ffffff" : "#80c080"
                        font.pixelSize: 12
                    }
                }

                // Date added
                Item {
                    visible: root.colWidth("added") > 0
                    width: root.colWidth("added"); height: parent.height
                    Text {
                        anchors { verticalCenter: parent.verticalCenter; left: parent.left; leftMargin: 6 }
                        text: {
                            if (!rowRect.item) return "--"
                            const d = rowRect.item.addedAt
                            return Qt.formatDateTime(d, "MM/dd/yy hh:mm")
                        }
                        color: tableView.currentRow === index ? "#ffffff" : "#b0b0b0"
                        font.pixelSize: 11
                    }
                }

                // Save to
                Item {
                    visible: root.colWidth("saveto") > 0
                    width: root.colWidth("saveto"); height: parent.height
                    clip: true
                    Text {
                        anchors { verticalCenter: parent.verticalCenter; left: parent.left; leftMargin: 6 }
                        text: rowRect.item ? rowRect.item.savePath : "--"
                        color: tableView.currentRow === index ? "#ffffff" : "#b0b0b0"
                        font.pixelSize: 11
                        width: parent.width - 8
                        elide: Text.ElideMiddle
                    }
                }
            }

            // progress bar strip at the bottom of each active row
            Rectangle {
                anchors { bottom: parent.bottom; left: parent.left }
                width: rowRect.item ? rowRect.item.progress * rowRect.width : 0
                height: 3
                color: "#4488dd"
                visible: rowRect.item !== null && rowRect.item.status === "Downloading"
                Behavior on width { NumberAnimation { duration: 400 } }
            }

            // bottom row border
            Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: "#2e2e2e" }

            MouseArea {
                id: rowMouse
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                preventStealing: true   // stops ListView from taking the grab mid-drag

                property point pressPos
                property bool dragActive: false

                onPressed: function(mouse) {
                    pressPos = Qt.point(mouse.x, mouse.y)
                    dragActive = false
                }

                onPositionChanged: function(mouse) {
                    if (!(pressedButtons & Qt.LeftButton)) return
                    var dx = mouse.x - pressPos.x
                    var dy = mouse.y - pressPos.y
                    if (!dragActive && (Math.abs(dx) > 8 || Math.abs(dy) > 8)) {
                        if (root.categoryDragProxy && rowRect.item) {
                            dragActive = true
                            root.categoryDragProxy.dragDownloadId = rowRect.item.id
                            root.categoryDragProxy.dragFilename   = rowRect.item.filename
                            root.categoryDragProxy.visible = true
                        }
                    }
                    if (dragActive && root.categoryDragProxy) {
                        // Move proxy to cursor in window coordinates
                        var winPos = mapToItem(null, mouse.x, mouse.y)
                        root.categoryDragProxy.x = winPos.x
                        root.categoryDragProxy.y = winPos.y
                    }
                }

                onReleased: function(mouse) {
                    if (dragActive && root.categoryDragProxy) {
                        root.categoryDragProxy.Drag.drop()
                        root.categoryDragProxy.visible = false
                        root.categoryDragProxy.dragDownloadId = ""
                        root.categoryDragProxy.dragFilename   = ""
                        dragActive = false
                    }
                }

                onClicked: function(mouse) {
                    if (!dragActive) {
                        tableView.currentRow = index
                        if (mouse.button === Qt.RightButton) rowCtxMenu.popup()
                    }
                }

                onDoubleClicked: function(mouse) {
                    if (rowRect.item) root.openProgressRequested(rowRect.item)
                }
            }

            Menu {
                id: rowCtxMenu
                Action { text: "Properties"; onTriggered: { if (rowRect.item) root.openProgressRequested(rowRect.item) } }
                Action { text: "Open File";   onTriggered: { if (rowRect.item) App.openFile(rowRect.item.id)   } }
                Action { text: "Open Folder"; onTriggered: { if (rowRect.item) App.openFolder(rowRect.item.id) } }
                MenuSeparator {}
                Action { text: "Copy Filename"; onTriggered: { if (rowRect.item) App.copyDownloadFilename(rowRect.item.id) } }
                Action { text: "Copy URL"; onTriggered: { if (rowRect.item) App.copyToClipboard(rowRect.item.url.toString()) } }
                MenuSeparator {}
                Action { text: "Resume";  onTriggered: root.resumeSelected() }
                Action { text: "Stop";    onTriggered: root.stopSelected()   }
                MenuSeparator {}

                Menu {
                    title: "Move to Queue"
                    Repeater {
                        model: App.queueModel
                        delegate: MenuItem {
                            visible: queueId !== "download-limits"
                            text: queueName || ""
                            onTriggered: {
                                if (rowRect.item)
                                    App.setDownloadQueue(rowRect.item.id, queueId)
                            }
                        }
                    }
                }

                MenuSeparator {}
                Action { text: "Delete";  onTriggered: { if (rowRect.item) root._openDeleteDialog(rowRect.item) } }
            }
        }

        // empty state
        Text {
            anchors.centerIn: parent
            visible: tableView.count === 0
            text: "No downloads yet.\nClick  Add URL  to start."
            horizontalAlignment: Text.AlignHCenter
            color: "#444444"
            font.pixelSize: 14
            lineHeight: 1.6
        }
    }
}
