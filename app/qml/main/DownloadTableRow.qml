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

// Row delegate for DownloadTable's ListView.
// Qt 6 does not inject ListView context properties (`index`, model roles)
// into separately-compiled QML component types. Caller (the inline delegate
// in DownloadTable.qml) reads `index` from the delegate context and forwards
// it via the `rowIndex` required property.

Rectangle {
    id: rowRect

    required property var table         // DownloadTable root
    required property var listView      // parent ListView
    required property int rowIndex      // forwarded from delegate's context `index`
    required property var rowItem       // forwarded from delegate's context `item` role

    // Alias kept so existing references (`rowRect.item`) continue to work and,
    // ── more importantly, so the binding tracks the role-based `rowItem` not ──
    // a non-reactive `App.downloadModel.itemAt(rowIndex)` call that QML can't
    // invalidate on model dataChanged/move signals.
    readonly property var item: rowItem

    width: table.visibleContentWidth
    visible: table.itemMatchesActiveFilter(item)
    height: visible ? 26 : 0
    clip: true

    readonly property string addedDateStr:   item ? item.addedDateStr   : ""
    readonly property string lastTryDateStr: item ? item.lastTryDateStr : ""

    readonly property bool _sel: { table._selectionVersion; return table.isRowSelected(rowIndex) }

    ListView.onReused: rowMouse.dragActive = false

    color: {
        table._selectionVersion
        if (table.isRowSelected(rowIndex)) return ColorPalette.selectionBg
        if (rowMouse.containsMouse)        return ColorPalette.hoverBg
        return rowIndex % 2 === 0 ? ColorPalette.windowBg : ColorPalette.rowAltBg
    }

    Item {
        anchors { top: parent.top; left: parent.left; right: parent.right; bottom: parent.bottom }

        Item {
            visible: table._colVisible("queue")
            x:       table._colXMap["queue"] || 0
            width:   table.colWidth("queue")
            height:  rowRect.height - 1
            clip: true
            Image {
                visible: rowRect.item && rowRect.item.queueId && rowRect.item.queueId.length > 0
                anchors.centerIn: parent
                source: {
                    const q = rowRect.item ? rowRect.item.queueId : ""
                    if (q === "main-download") return "../icons/main_queue.svg"
                    if (q === "main-sync")     return "../icons/synch_queue.svg"
                    return "../icons/custom_queue.svg"
                }
                width: 14; height: 14
                sourceSize: Qt.size(14, 14)
                fillMode: Image.PreserveAspectFit
                ThemedToolTip {
                    visible: queueIconMouse.containsMouse
                    text: {
                        const qid = rowRect.item ? rowRect.item.queueId : ""
                        if (!qid) return ""
                        for (var i = 0; i < App.queueModel.rowCount(); i++) {
                            var queueId = App.queueModel.data(App.queueModel.index(i, 0), 34)
                            if (queueId === qid)
                                return App.queueModel.data(App.queueModel.index(i, 0), 35) || qid
                        }
                        return qid
                    }
                }
                MouseArea { id: queueIconMouse; anchors.fill: parent; hoverEnabled: true }
            }
        }

        Item {
            visible: table._colVisible("name")
            x:       table._colXMap["name"] || 0
            width:   table.colWidth("name")
            height:  rowRect.height - 1
            clip: true
            Row {
                anchors { verticalCenter: parent.verticalCenter; left: parent.left; leftMargin: 6 }
                spacing: 6
                width: parent.width - 12
                Image {
                    width: 18; height: 18
                    anchors.verticalCenter: parent.verticalCenter
                    source: {
                        if (!rowRect.item) return ""
                        var basePath = (rowRect.item.savePath + "/" + rowRect.item.filename).replace(/\\/g, "/")
                        if (rowRect.item.isTorrent && !rowRect.item.torrentIsSingleFile)
                            basePath += "/"
                        return "image://fileicon/" + basePath + (rowRect.item.status === "Completed" ? "?c=1" : "")
                    }
                    sourceSize: Qt.size(18, 18)
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                }
                Text {
                    text: rowRect.item ? rowRect.item.filename : ""
                    color: rowRect._sel ? ColorPalette.selectionText : ColorPalette.textPrimary
                    font.pixelSize: 12 * App.fontScale
                    width: parent.parent.width - 42
                    elide: Text.ElideMiddle
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
        }

        Item {
            visible: table._colVisible("size")
            x:       table._colXMap["size"] || 0
            width:   table.colWidth("size")
            height:  rowRect.height - 1
            clip: true
            Text {
                anchors { fill: parent; leftMargin: 6 }
                verticalAlignment: Text.AlignVCenter
                text: rowRect.item ? table.formatBytesShort(rowRect.item.totalBytes) : ""
                color: rowRect._sel ? ColorPalette.selectionText : ColorPalette.textPrimary
                font.pixelSize: 12 * App.fontScale
            }
        }

        Item {
            visible: table._colVisible("status")
            x:       table._colXMap["status"] || 0
            width:   table.colWidth("status")
            height:  rowRect.height - 1
            clip: true
            Text {
                anchors { fill: parent; leftMargin: 6 }
                verticalAlignment: Text.AlignVCenter
                text: {
                    if (!rowRect.item) return ""
                    if (rowRect.item.isTorrent && !rowRect.item.torrentHasMetadata)
                        return qsTr("Pending")
                    if (rowRect.item.status === "Downloading")
                        return (rowRect.item.progress * 100).toFixed(1) + "%"
                    if (rowRect.item.status === "Paused" && rowRect.item.progress > 0)
                        return qsTr("%1% (Stopped)").arg((rowRect.item.progress * 100).toFixed(1))
                    if (rowRect.item.status === "Checking" && rowRect.item.progress > 0)
                        return qsTr("Checking (%1%)").arg((rowRect.item.progress * 100).toFixed(1))
                    return rowRect.item.statusText
                }
                color: rowRect._sel ? ColorPalette.selectionText : ColorPalette.textPrimary
                font.pixelSize: 12 * App.fontScale
            }
        }

        Item {
            visible: table._colVisible("timeleft")
            x:       table._colXMap["timeleft"] || 0
            width:   table.colWidth("timeleft")
            height:  rowRect.height - 1
            clip: true
            Text {
                anchors { fill: parent; leftMargin: 6 }
                verticalAlignment: Text.AlignVCenter
                text: rowRect.item ? (rowRect.item.timeLeft || "") : ""
                color: rowRect._sel ? ColorPalette.selectionText : ColorPalette.textPrimary
                font.pixelSize: 12 * App.fontScale
            }
        }

        Item {
            visible: table._colVisible("downspeed")
            x:       table._colXMap["downspeed"] || 0
            width:   table.colWidth("downspeed")
            height:  rowRect.height - 1
            clip: true
            Text {
                anchors { fill: parent; leftMargin: 6 }
                verticalAlignment: Text.AlignVCenter
                text: {
                    if (!rowRect.item) return ""
                    var st = rowRect.item.status
                    if (st !== "Downloading" && st !== "Seeding") return ""
                    var bps = rowRect.item.speed
                    if (bps <= 0) return ""
                    var limited = rowRect.item.speedLimitKBps > 0 || rowRect.item.perTorrentDownLimitKBps > 0
                    var suffix = limited ? "*" : ""
                    if (bps >= 1000000000) return (bps / 1000000000).toFixed(2) + " GB/s" + suffix
                    if (bps >= 1000000)    return (bps / 1000000).toFixed(2) + " MB/s" + suffix
                    if (bps >= 1000)       return (bps / 1000).toFixed(1) + " KB/s" + suffix
                    return bps + " B/s" + suffix
                }
                color: rowRect._sel ? ColorPalette.selectionText : ColorPalette.textPrimary
                font.pixelSize: 12 * App.fontScale
            }
        }

        Item {
            visible: table._colVisible("upspeed")
            x:       table._colXMap["upspeed"] || 0
            width:   table.colWidth("upspeed")
            height:  rowRect.height - 1
            clip: true
            Text {
                anchors { fill: parent; leftMargin: 6 }
                verticalAlignment: Text.AlignVCenter
                text: {
                    if (!rowRect.item || !rowRect.item.isTorrent) return ""
                    if (rowRect.item.status !== "Downloading" && rowRect.item.status !== "Seeding") return ""
                    var bps = rowRect.item.torrentUploadSpeed
                    var limited = rowRect.item.perTorrentUpLimitKBps > 0
                    var suffix = limited ? "*" : ""
                    if (bps >= 1000000000) return (bps / 1000000000).toFixed(2) + " GB/s" + suffix
                    if (bps >= 1000000)    return (bps / 1000000).toFixed(2) + " MB/s" + suffix
                    if (bps >= 1000)       return (bps / 1000).toFixed(1) + " KB/s" + suffix
                    return bps > 0 ? (bps + " B/s" + suffix) : ""
                }
                color: rowRect._sel ? ColorPalette.selectionText : ColorPalette.textPrimary
                font.pixelSize: 12 * App.fontScale
            }
        }

        Item {
            visible: table._colVisible("seeders")
            x:       table._colXMap["seeders"] || 0
            width:   table.colWidth("seeders")
            height:  rowRect.height - 1
            clip: true
            Text {
                anchors { fill: parent; leftMargin: 6 }
                verticalAlignment: Text.AlignVCenter
                text: {
                    if (!rowRect.item || !rowRect.item.isTorrent) return ""
                    var st = rowRect.item.status
                    if (st === "Paused" || st === "Stopped") return ""
                    return rowRect.item.torrentSeeders + " (" + rowRect.item.torrentListSeeders + ")"
                }
                color: rowRect._sel ? ColorPalette.selectionText : ColorPalette.textPrimary
                font.pixelSize: 12 * App.fontScale
            }
        }

        Item {
            visible: table._colVisible("peers")
            x:       table._colXMap["peers"] || 0
            width:   table.colWidth("peers")
            height:  rowRect.height - 1
            clip: true
            Text {
                anchors { fill: parent; leftMargin: 6 }
                verticalAlignment: Text.AlignVCenter
                text: {
                    if (!rowRect.item || !rowRect.item.isTorrent) return ""
                    var st = rowRect.item.status
                    if (st === "Paused" || st === "Stopped") return ""
                    return rowRect.item.torrentPeers + " (" + rowRect.item.torrentListPeers + ")"
                }
                color: rowRect._sel ? ColorPalette.selectionText : ColorPalette.textPrimary
                font.pixelSize: 12 * App.fontScale
            }
        }

        Item {
            visible: table._colVisible("ratio")
            x:       table._colXMap["ratio"] || 0
            width:   table.colWidth("ratio")
            height:  rowRect.height - 1
            clip: true
            Text {
                anchors { fill: parent; leftMargin: 6 }
                verticalAlignment: Text.AlignVCenter
                text: rowRect.item && rowRect.item.isTorrent ? rowRect.item.torrentRatio.toFixed(2) : ""
                color: rowRect._sel ? ColorPalette.selectionText : ColorPalette.textPrimary
                font.pixelSize: 12 * App.fontScale
            }
        }

        Item {
            visible: table._colVisible("uploaded")
            x:       table._colXMap["uploaded"] || 0
            width:   table.colWidth("uploaded")
            height:  rowRect.height - 1
            clip: true
            Text {
                anchors { fill: parent; leftMargin: 6 }
                verticalAlignment: Text.AlignVCenter
                text: rowRect.item && rowRect.item.isTorrent ? table.formatBytesShort(rowRect.item.torrentUploaded) : ""
                color: rowRect._sel ? ColorPalette.selectionText : ColorPalette.textPrimary
                font.pixelSize: 12 * App.fontScale
            }
        }

        Item {
            visible: table._colVisible("downloaded")
            x:       table._colXMap["downloaded"] || 0
            width:   table.colWidth("downloaded")
            height:  rowRect.height - 1
            clip: true
            Text {
                anchors { fill: parent; leftMargin: 6 }
                verticalAlignment: Text.AlignVCenter
                text: rowRect.item && rowRect.item.isTorrent ? table.formatBytesShort(rowRect.item.torrentDownloaded) : ""
                color: rowRect._sel ? ColorPalette.selectionText : ColorPalette.textPrimary
                font.pixelSize: 12 * App.fontScale
            }
        }

        Item {
            visible: table._colVisible("added")
            x:       table._colXMap["added"] || 0
            width:   table.colWidth("added")
            height:  rowRect.height - 1
            clip: true
            Text {
                anchors { fill: parent; leftMargin: 6 }
                verticalAlignment: Text.AlignVCenter
                text: rowRect.addedDateStr
                color: rowRect._sel ? ColorPalette.selectionText : ColorPalette.textPrimary
                font.pixelSize: 11 * App.fontScale
            }
        }

        Item {
            visible: table._colVisible("lasttry")
            x:       table._colXMap["lasttry"] || 0
            width:   table.colWidth("lasttry")
            height:  rowRect.height - 1
            clip: true
            Text {
                anchors { fill: parent; leftMargin: 6 }
                verticalAlignment: Text.AlignVCenter
                text: rowRect.lastTryDateStr
                color: rowRect._sel ? ColorPalette.selectionText : ColorPalette.textPrimary
                font.pixelSize: 11 * App.fontScale
            }
        }

        Item {
            visible: table._colVisible("description")
            x:       table._colXMap["description"] || 0
            width:   table.colWidth("description")
            height:  rowRect.height - 1
            clip: true
            Text {
                anchors { fill: parent; leftMargin: 6 }
                verticalAlignment: Text.AlignVCenter
                text: rowRect.item ? (rowRect.item.description || "") : ""
                color: rowRect._sel ? ColorPalette.selectionText : ColorPalette.textPrimary
                font.pixelSize: 11 * App.fontScale
            }
        }

        Item {
            visible: table._colVisible("saveto")
            x:       table._colXMap["saveto"] || 0
            width:   table.colWidth("saveto")
            height:  rowRect.height - 1
            clip: true
            Text {
                anchors { fill: parent; leftMargin: 6 }
                verticalAlignment: Text.AlignVCenter
                text: rowRect.item ? (rowRect.item.savePath || "") : ""
                color: rowRect._sel ? ColorPalette.selectionText : ColorPalette.textPrimary
                font.pixelSize: 11 * App.fontScale
            }
        }

        Item {
            visible: table._colVisible("referrer")
            x:       table._colXMap["referrer"] || 0
            width:   table.colWidth("referrer")
            height:  rowRect.height - 1
            clip: true
            Text {
                anchors { fill: parent; leftMargin: 6 }
                verticalAlignment: Text.AlignVCenter
                text: rowRect.item ? (rowRect.item.referrer || "") : ""
                color: rowRect._sel ? ColorPalette.selectionText : ColorPalette.textPrimary
                font.pixelSize: 11 * App.fontScale
            }
        }

        Item {
            visible: table._colVisible("parenturl")
            x:       table._colXMap["parenturl"] || 0
            width:   table.colWidth("parenturl")
            height:  rowRect.height - 1
            clip: true
            Text {
                anchors { fill: parent; leftMargin: 6 }
                verticalAlignment: Text.AlignVCenter
                text: rowRect.item ? (rowRect.item.parentUrl || "") : ""
                color: rowRect._sel ? ColorPalette.selectionText : ColorPalette.textPrimary
                font.pixelSize: 11 * App.fontScale
            }
        }
    }

    // Progress strip along the row bottom. Blue while downloading; an orange
    // sweeping sliver while a magnet is still fetching metadata. Hidden while
    // seeding (a full-width strip there is just noise) and otherwise.
    Item {
        id: progStrip
        anchors { bottom: parent.bottom; bottomMargin: 1 }
        x: listView.contentX
        height: 3
        readonly property real _viewportWidth: Math.max(0, Math.min(listView.width, rowRect.width - listView.contentX))
        width: _viewportWidth
        readonly property bool _metadataPending: rowRect.item && rowRect.item.isTorrent && !rowRect.item.torrentHasMetadata
        visible: rowRect.item && (rowRect.item.status === "Downloading" || _metadataPending)

        // Determinate blue fill (active download).
        Rectangle {
            visible: !progStrip._metadataPending
            anchors { left: parent.left; bottom: parent.bottom }
            width: rowRect.item ? rowRect.item.progress * progStrip._viewportWidth : 0
            height: parent.height
            color: ColorPalette.progressDownloading
        }

        // Orange sliver that squeezes thin against each edge, fattens crossing
        // the middle, then back (matches TorrentProgressBar).
        property real _pos: 0
        readonly property real _sweepW: progStrip.width * (0.16 + 0.42 * Math.sin(Math.PI * _pos))
        SequentialAnimation on _pos {
            running: progStrip._metadataPending && progStrip.visible
            loops: Animation.Infinite
            NumberAnimation { from: 0; to: 1; duration: 950; easing.type: Easing.InOutQuad }
            NumberAnimation { from: 1; to: 0; duration: 950; easing.type: Easing.InOutQuad }
        }
        Rectangle {
            visible: progStrip._metadataPending
            y: 0
            height: parent.height
            color: ColorPalette.progressMetadata
            width: progStrip._sweepW
            x: progStrip._pos * (progStrip.width - progStrip._sweepW)
        }
    }

    MouseArea {
        id: rowMouse
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        preventStealing: true

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
                if (table.categoryDragProxy && rowRect.item) {
                    dragActive = true
                    var selectedIds = []
                    for (var selId in table._selectedIds) {
                        if (App.downloadModel.itemById(selId)) selectedIds.push(selId)
                    }
                    if (selectedIds.length === 0 || !table.isRowSelected(rowRect.rowIndex))
                        selectedIds = [rowRect.item.id]
                    table.categoryDragProxy.dragDownloadIds = selectedIds
                    table.categoryDragProxy.dragDownloadId  = rowRect.item.id
                    table.categoryDragProxy.dragFilename    = selectedIds.length > 1 ? qsTr("%n file(s)", "", selectedIds.length) : rowRect.item.filename
                    table.categoryDragProxy.visible = true
                }
            }
            if (dragActive && table.categoryDragProxy) {
                var winPos = mapToItem(null, mouse.x, mouse.y)
                table.categoryDragProxy.x = winPos.x
                table.categoryDragProxy.y = winPos.y
            }
        }

        onReleased: function(mouse) {
            if (dragActive && table.categoryDragProxy) {
                table.categoryDragProxy.Drag.drop()
                table.categoryDragProxy.visible = false
                table.categoryDragProxy.dragDownloadId = ""
                table.categoryDragProxy.dragDownloadIds = []
                table.categoryDragProxy.dragFilename   = ""
                dragActive = false
            }
        }

        onClicked: function(mouse) {
            if (dragActive) return
            listView.forceActiveFocus()
            if (mouse.button === Qt.RightButton) {
                if (!table.isRowSelected(rowRect.rowIndex)) {
                    table._clearAndSelect(rowRect.rowIndex)
                    table._anchorId = rowRect.item ? rowRect.item.id : ""
                }
                table._ctxItem = rowRect.item
                table.rowCtxMenu.popup()
            } else if (mouse.modifiers & Qt.ControlModifier) {
                table._toggleRow(rowRect.rowIndex)
                table._anchorId = rowRect.item ? rowRect.item.id : ""
            } else if (mouse.modifiers & Qt.ShiftModifier) {
                var anchorRow = table._anchorId !== "" ? App.downloadModel.rowForId(table._anchorId) : -1
                if (anchorRow >= 0)
                    table._addRange(anchorRow, rowRect.rowIndex)
                else {
                    table._clearAndSelect(rowRect.rowIndex)
                    table._anchorId = rowRect.item ? rowRect.item.id : ""
                }
            } else {
                table._clearAndSelect(rowRect.rowIndex)
                table._anchorId = rowRect.item ? rowRect.item.id : ""
            }
        }

        onDoubleClicked: function(mouse) {
            if (!rowRect.item) return
            if (rowRect.item.isTorrent) {
                table.openPropertiesRequested(rowRect.item)
                return
            }
            if (rowRect.item.status === "Downloading" || rowRect.item.status === "Assembling") {
                table.openProgressRequested(rowRect.item)
                return
            }
            var action = App.settings.doubleClickAction
            if (action === 1)
                App.openFile(rowRect.item.id)
            else if (action === 2)
                App.openFolderSelectFile(rowRect.item.id)
            else
                table.openPropertiesRequested(rowRect.item)
        }
    }
}
