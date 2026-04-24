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
    title: "Batch download review"
    width: 980
    height: 620
    minimumWidth: 820
    minimumHeight: 480
    color: "#1e1e1e"
    flags: Qt.Dialog | Qt.WindowTitleHint | Qt.WindowCloseButtonHint
    modality: Qt.ApplicationModal

    Material.theme: Material.Dark
    Material.background: "#1e1e1e"
    Material.accent: "#4488dd"

    property var files: []
    property var reviewRows: []
    property string sortColumn: "name"
    property bool sortAscending: true
    property string resizingColumnKey: ""
    property real resizingColumnWidth: 0
    property bool colDragging: false
    property string colDragFromKey: ""
    property string colDragInsertBeforeKey: ""
    property int probeGeneration: 0

    signal batchAccepted(var files)

    property var columnDefs: [
        { title: "", key: "check", widthPx: 36, minWidth: 36, sortable: false, resizable: false, reorderable: false },
        { title: "", key: "icon", widthPx: 34, minWidth: 30, sortable: false, resizable: true, reorderable: true },
        { title: "File name", key: "name", widthPx: 250, minWidth: 120, sortable: true, resizable: true, reorderable: true },
        { title: "Size", key: "size", widthPx: 110, minWidth: 80, sortable: true, resizable: true, reorderable: true },
        { title: "Status", key: "status", widthPx: 110, minWidth: 90, sortable: true, resizable: true, reorderable: true },
        { title: "URL", key: "url", widthPx: 520, minWidth: 180, sortable: true, resizable: true, reorderable: true }
    ]

    function safeString(v) {
        return (v === undefined || v === null) ? "" : String(v)
    }

    function baseName(url) {
        var tail = safeString(url).split("/").pop()
        return tail.split("?")[0]
    }

    function centerOnOwner() {
        var owner = root.transientParent
        if (owner) {
            x = owner.x + Math.round((owner.width - width) / 2)
            y = owner.y + Math.round((owner.height - height) / 2)
            return
        }
        x = Math.round((Screen.width - width) / 2)
        y = Math.round((Screen.height - height) / 2)
    }

    function patternHint() {
        if (!files || files.length === 0)
            return "e.g. file*.zip"
        var first = files[0]
        var base = first && first.url ? baseName(first.url) : safeString(first && first.name)
        if (base.length === 0)
            return "e.g. file*.zip"
        var dot = base.lastIndexOf(".")
        if (dot < 0)
            return "e.g. " + base
        return "e.g. " + base.substring(0, dot) + "*" + base.substring(dot)
    }

    function applyPattern(name) {
        var pattern = batchPatternField.text.trim()
        if (pattern.length === 0)
            return name
        if (pattern.indexOf("*") < 0)
            return pattern
        return pattern.replace("*", name)
    }

    function iconSourceForName(name) {
        var finalName = safeString(name)
        return finalName.length > 0 ? "image://fileicon/" + finalName : ""
    }

    function formatBytes(bytes) {
        if (bytes < 0)
            return ""
        if (bytes < 1024)
            return bytes + " B"
        if (bytes < 1024 * 1024)
            return (bytes / 1024).toFixed(bytes >= 1024 * 100 ? 0 : 1) + " KB"
        if (bytes < 1024 * 1024 * 1024)
            return (bytes / (1024 * 1024)).toFixed(bytes >= 1024 * 1024 * 100 ? 0 : 1) + " MB"
        return (bytes / (1024 * 1024 * 1024)).toFixed(2) + " GB"
    }

    function statusRank(status) {
        if (status === "Found")
            return 0
        if (status === "Checking...")
            return 1
        return 2
    }

    function rowCount() {
        return reviewRows ? reviewRows.length : 0
    }

    function rowAt(index) {
        return (reviewRows && index >= 0 && index < reviewRows.length) ? reviewRows[index] : null
    }

    function setRowProperty(index, key, value) {
        if (!reviewRows || index < 0 || index >= reviewRows.length)
            return
        var rows = reviewRows.slice()
        rows[index] = Object.assign({}, rows[index], { [key]: value })
        reviewRows = rows
    }

    function sortValue(row, key) {
        if (key === "name")
            return safeString(row.displayName).toLowerCase()
        if (key === "size")
            return row.sizeBytes >= 0 ? row.sizeBytes : Number.MAX_SAFE_INTEGER
        if (key === "status")
            return row.statusRank
        if (key === "url")
            return safeString(row.sourceUrl).toLowerCase()
        return 0
    }

    function sortRows() {
        var rows = reviewRows.slice()
        for (var i = 0; i < rows.length; ++i)
            rows[i]._stableIdx = i
        rows.sort(function(a, b) {
            var va = sortValue(a, sortColumn)
            var vb = sortValue(b, sortColumn)
            if (va < vb)
                return sortAscending ? -1 : 1
            if (va > vb)
                return sortAscending ? 1 : -1
            return a._stableIdx - b._stableIdx
        })
        for (var j = 0; j < rows.length; ++j) {
            delete rows[j]._stableIdx
            rows[j].rowIndex = j
        }
        reviewRows = rows
    }

    function refreshNames() {
        var rows = reviewRows.slice()
        var seen = {}
        for (var i = 0; i < rows.length; ++i) {
            var base = safeString(rows[i].baseName || rows[i].displayName)
            var name = applyPattern(base)
            if (name.length === 0)
                name = base
            var dot = name.lastIndexOf(".")
            var stem = dot >= 0 ? name.substring(0, dot) : name
            var ext = dot >= 0 ? name.substring(dot) : ""
            var finalName = name
            var n = 1
            while (seen[finalName.toLowerCase()]) {
                ++n
                finalName = stem + "_" + n + ext
            }
            seen[finalName.toLowerCase()] = true
            rows[i] = Object.assign({}, rows[i], {
                displayName: finalName,
                iconSource: iconSourceForName(finalName)
            })
        }
        reviewRows = rows
        sortRows()
    }

    function rebuildRows() {
        probeGeneration += 1
        var generation = probeGeneration
        var rows = []
        for (var i = 0; i < files.length; ++i) {
            var f = files[i]
            var initialName = safeString(f && f.filename)
            if (initialName.length === 0)
                initialName = safeString(f && f.name)
            if (initialName.length === 0)
                initialName = baseName(f && f.url)
            if (initialName.length === 0)
                initialName = "download"
            rows.push({
                rowIndex: i,
                baseName: initialName,
                displayName: initialName,
                sourceUrl: safeString(f && f.url),
                rowStatus: "Checking...",
                statusRank: statusRank("Checking..."),
                selected: true,
                sizeBytes: -1,
                sizeText: "",
                iconSource: iconSourceForName(initialName)
            })
        }
        reviewRows = rows
        if (batchPatternField.text.length === 0)
            batchPatternField.placeholderText = patternHint()
        refreshNames()
        probeRows(generation)
    }

    function probeRows(generation) {
        for (var i = 0; i < rowCount(); ++i) {
            (function(idx) {
                var row = rowAt(idx)
                var url = row ? row.sourceUrl : ""
                App.probeFileInfo(url, "", "", function(info) {
                    if (generation !== probeGeneration || idx >= rowCount())
                        return
                    var ok = !!(info && info.ok)
                    var nextStatus = ok ? "Found" : "Not Found"
                    var bytes = (ok && info.contentLength && info.contentLength > 0) ? info.contentLength : -1
                    var rows = reviewRows.slice()
                    if (idx >= rows.length)
                        return
                    rows[idx] = Object.assign({}, rows[idx], {
                        rowStatus: nextStatus,
                        statusRank: statusRank(nextStatus),
                        sizeBytes: bytes,
                        sizeText: formatBytes(bytes),
                        selected: ok ? rows[idx].selected : false
                    })
                    reviewRows = rows
                    sortRows()
                })
            })(i)
        }
    }

    function allFoundSelected() {
        var foundCount = 0
        var selectedFoundCount = 0
        for (var i = 0; i < rowCount(); ++i) {
            var row = rowAt(i)
            if (!row || row.rowStatus !== "Found")
                continue
            foundCount += 1
            if (row.selected)
                selectedFoundCount += 1
        }
        return foundCount > 0 && foundCount === selectedFoundCount
    }

    function setAllSelected(selected) {
        var rows = reviewRows.slice()
        for (var i = 0; i < rows.length; ++i) {
            if (rows[i].rowStatus === "Found")
                rows[i] = Object.assign({}, rows[i], { selected: selected })
        }
        reviewRows = rows
    }

    function acceptRows() {
        var accepted = []
        for (var i = 0; i < rowCount(); ++i) {
            var row = rowAt(i)
            if (row && row.selected && row.rowStatus === "Found")
                accepted.push({ url: row.sourceUrl, filename: row.displayName })
        }
        root.batchAccepted(accepted)
        root.close()
    }

    function columnWidth(key) {
        if (resizingColumnKey === key)
            return resizingColumnWidth
        for (var i = 0; i < columnDefs.length; ++i)
            if (columnDefs[i].key === key)
                return columnDefs[i].widthPx
        return 100
    }

    function totalColumnWidth() {
        var total = 0
        for (var i = 0; i < columnDefs.length; ++i)
            total += columnWidth(columnDefs[i].key)
        return total
    }

    function setColumnWidth(key, width) {
        var defs = []
        for (var i = 0; i < columnDefs.length; ++i) {
            var def = Object.assign({}, columnDefs[i])
            if (def.key === key)
                def.widthPx = Math.max(def.minWidth || 60, Math.round(width))
            defs.push(def)
        }
        columnDefs = defs
    }

    function sortBy(key) {
        if (sortColumn === key)
            sortAscending = !sortAscending
        else {
            sortColumn = key
            sortAscending = true
        }
        sortRows()
    }

    function sortIndicator(key) {
        if (sortColumn !== key)
            return ""
        return sortAscending ? " ^" : " v"
    }

    function applyColumnReorder() {
        if (!colDragFromKey || !colDragInsertBeforeKey)
            return
        var defs = columnDefs.slice()
        var src = -1
        for (var i = 0; i < defs.length; ++i) {
            if (defs[i].key === colDragFromKey) {
                src = i
                break
            }
        }
        if (src < 0 || !defs[src].reorderable)
            return
        var moved = defs[src]
        defs.splice(src, 1)
        var dst = defs.length
        if (colDragInsertBeforeKey !== "__end__") {
            for (var j = 0; j < defs.length; ++j) {
                if (defs[j].key === colDragInsertBeforeKey) {
                    dst = j
                    break
                }
            }
        }
        while (dst < defs.length && !defs[dst].reorderable)
            dst += 1
        defs.splice(dst, 0, moved)
        columnDefs = defs
    }

    onVisibleChanged: {
        if (visible)
            centerOnOwner()
    }

    Component.onCompleted: rebuildRows()
    onFilesChanged: rebuildRows()

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 14
        spacing: 10

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4
            Text { text: "Batch download review"; color: "#f0f0f0"; font.pixelSize: 16; font.bold: true }
            Text {
                text: "Review links before adding them. Columns can be sorted, resized, and dragged to reorder."
                color: "#aeb7c0"
                font.pixelSize: 11
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
            }
        }

        Rectangle {
            Layout.fillWidth: true
            color: "#1a2030"
            border.color: "#2a3a5a"
            radius: 4
            implicitHeight: 66

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 10
                spacing: 6

                Text {
                    text: "Replace filenames with wildcard pattern (*)"
                    color: "#d0d0d0"
                    font.pixelSize: 11
                    font.weight: Font.Medium
                    Layout.fillWidth: true
                }
                TextField {
                    id: batchPatternField
                    Layout.fillWidth: true
                    placeholderText: patternHint()
                    color: "#d0d0d0"
                    background: Rectangle {
                        color: "#1b1b1b"
                        border.color: batchPatternField.activeFocus ? "#4488dd" : "#3a3a3a"
                        radius: 3
                    }
                    onTextChanged: refreshNames()
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            Text { text: "Files"; color: "#d0d0d0"; font.pixelSize: 12; font.bold: true }
            Item { Layout.fillWidth: true }
            DlgButton { text: "Check all"; onClicked: setAllSelected(true) }
            DlgButton { text: "Uncheck all"; onClicked: setAllSelected(false) }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            color: "#1a1a1a"
            border.color: "#2d2d2d"
            radius: 4
            clip: true

            Flickable {
                id: tableFlick
                anchors.fill: parent
                contentWidth: Math.max(width, totalColumnWidth())
                contentHeight: height
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                flickableDirection: Flickable.HorizontalFlick
                ScrollBar.horizontal: ScrollBar { policy: ScrollBar.AsNeeded }
                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AlwaysOff }

                Rectangle {
                    id: headerBar
                    width: tableFlick.contentWidth
                    height: 26
                    color: "#2d2d2d"

                    Row {
                        anchors.fill: parent
                        spacing: 0

                        Repeater {
                            id: headerRepeater
                            model: root.columnDefs
                            delegate: Rectangle {
                                required property var modelData
                                width: root.columnWidth(modelData.key)
                                height: parent.height
                                readonly property bool isSortable: !!modelData.sortable
                                color: (isSortable && headerMouse.containsMouse && !root.colDragging) ? "#383838" : "transparent"
                                opacity: (root.colDragging && root.colDragFromKey === modelData.key) ? 0.55 : 1.0

                                Rectangle {
                                    visible: root.colDragging && root.colDragInsertBeforeKey === modelData.key
                                    anchors.left: parent.left
                                    width: 2
                                    height: parent.height
                                    color: "#4488dd"
                                }

                                Rectangle {
                                    visible: root.colDragging && root.colDragInsertBeforeKey === "__end__" && index === headerRepeater.count - 1
                                    anchors.right: parent.right
                                    width: 2
                                    height: parent.height
                                    color: "#4488dd"
                                }

                                CheckBox {
                                    visible: modelData.key === "check"
                                    anchors.centerIn: parent
                                    topPadding: 0
                                    bottomPadding: 0
                                    checked: root.allFoundSelected()
                                    onToggled: root.setAllSelected(checked)
                                }

                                Text {
                                    visible: modelData.key !== "check" && modelData.key !== "icon"
                                    anchors.left: parent.left
                                    anchors.leftMargin: 8
                                    anchors.verticalCenter: parent.verticalCenter
                                    anchors.right: sortText.left
                                    anchors.rightMargin: 4
                                    text: modelData.title
                                    color: root.sortColumn === modelData.key ? "#88bbff" : "#b0b0b0"
                                    font.pixelSize: 11
                                    font.bold: true
                                    elide: Text.ElideRight
                                }

                                Text {
                                    id: sortText
                                    visible: modelData.key !== "check"
                                    anchors.verticalCenter: parent.verticalCenter
                                    anchors.right: resizeHandle.left
                                    anchors.rightMargin: 5
                                    text: root.sortIndicator(modelData.key)
                                    color: "#88bbff"
                                    font.pixelSize: 9
                                }

                                MouseArea {
                                    id: headerMouse
                                    anchors.fill: parent
                                    anchors.rightMargin: modelData.resizable ? 10 : 0
                                    enabled: modelData.key !== "check"
                                    hoverEnabled: true
                                    preventStealing: true
                                    cursorShape: root.colDragging ? Qt.ClosedHandCursor : (isSortable ? Qt.PointingHandCursor : Qt.ArrowCursor)
                                    property real pressX: 0
                                    property bool didDrag: false

                                    onPressed: {
                                        pressX = mouseX
                                        didDrag = false
                                    }

                                    onPositionChanged: {
                                        if (!(pressedButtons & Qt.LeftButton) || !modelData.reorderable)
                                            return
                                        if (!root.colDragging && Math.abs(mouseX - pressX) > 8) {
                                            root.colDragFromKey = modelData.key
                                            root.colDragging = true
                                            didDrag = true
                                        }
                                        if (root.colDragging && root.colDragFromKey === modelData.key) {
                                            var cursorX = mapToItem(headerBar, mouseX, 0).x
                                            var insertBefore = "__end__"
                                            var xAcc = 0
                                            for (var i = 0; i < root.columnDefs.length; ++i) {
                                                var key = root.columnDefs[i].key
                                                var w = root.columnWidth(key)
                                                if (cursorX < xAcc + w / 2 && root.columnDefs[i].reorderable) {
                                                    insertBefore = key
                                                    break
                                                }
                                                xAcc += w
                                            }
                                            root.colDragInsertBeforeKey = insertBefore
                                        }
                                    }

                                    onReleased: {
                                        var wasDrag = didDrag
                                        Qt.callLater(function() {
                                            if (wasDrag)
                                                root.applyColumnReorder()
                                            root.colDragging = false
                                            root.colDragFromKey = ""
                                            root.colDragInsertBeforeKey = ""
                                        })
                                        didDrag = false
                                    }

                                    onClicked: {
                                        if (!didDrag && isSortable)
                                            root.sortBy(modelData.key)
                                        didDrag = false
                                    }
                                }

                                Rectangle {
                                    anchors.right: parent.right
                                    width: 1
                                    height: parent.height
                                    color: "#3a3a3a"
                                }

                                Item {
                                    id: resizeHandle
                                    visible: !!modelData.resizable
                                    width: 10
                                    height: parent.height
                                    anchors.right: parent.right

                                    Rectangle {
                                        anchors.right: parent.right
                                        width: 2
                                        height: parent.height
                                        color: (resizeDrag.active || resizeHover.hovered) ? "#6aa0ff" : "transparent"
                                    }

                                    HoverHandler { id: resizeHover; cursorShape: Qt.SizeHorCursor }

                                    DragHandler {
                                        id: resizeDrag
                                        target: null
                                        xAxis.enabled: true
                                        yAxis.enabled: false
                                        cursorShape: Qt.SizeHorCursor

                                        property real startWidthPx: 0

                                        onActiveChanged: {
                                            if (active) {
                                                startWidthPx = root.columnWidth(modelData.key)
                                                root.resizingColumnKey = modelData.key
                                                root.resizingColumnWidth = startWidthPx
                                                return
                                            }
                                            if (root.resizingColumnKey === modelData.key) {
                                                root.setColumnWidth(modelData.key, root.resizingColumnWidth)
                                                root.resizingColumnKey = ""
                                                root.resizingColumnWidth = 0
                                            }
                                        }

                                        onTranslationChanged: {
                                            if (!active)
                                                return
                                            root.resizingColumnWidth = Math.max(modelData.minWidth || 60, startWidthPx + translation.x)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                ListView {
                    id: fileList
                    y: headerBar.height
                    width: tableFlick.contentWidth
                    height: Math.max(0, tableFlick.height - headerBar.height)
                    model: root.rowCount()
                    clip: true
                    spacing: 0
                    boundsBehavior: Flickable.StopAtBounds
                    ScrollBar.vertical: ScrollBar {}

                    delegate: Rectangle {
                        required property int index
                        readonly property var modelData: root.rowAt(index)
                        readonly property int rowIndex: modelData && modelData.rowIndex !== undefined ? modelData.rowIndex : 0
                        width: tableFlick.contentWidth
                        height: 28
                        color: rowIndex % 2 === 0 ? "#1c1c1c" : "#222222"

                        Row {
                            anchors.fill: parent
                            spacing: 0

                            Item {
                                width: root.columnWidth("check")
                                height: parent.height
                                CheckBox {
                                    anchors.centerIn: parent
                                    topPadding: 0
                                    bottomPadding: 0
                                    enabled: !!(modelData && modelData.rowStatus === "Found")
                                    checked: !!(modelData && modelData.selected)
                                    onCheckedChanged: root.setRowProperty(rowIndex, "selected", checked)
                                }
                            }

                            Item {
                                width: root.columnWidth("icon")
                                height: parent.height
                                Image {
                                    anchors.centerIn: parent
                                    source: modelData ? modelData.iconSource : ""
                                    width: 16
                                    height: 16
                                    smooth: true
                                    fillMode: Image.PreserveAspectFit
                                }
                            }

                            Text {
                                width: root.columnWidth("name")
                                height: parent.height
                                leftPadding: 8
                                verticalAlignment: Text.AlignVCenter
                                text: modelData ? safeString(modelData.displayName) : ""
                                color: "#e0e0e0"
                                font.pixelSize: 12
                                elide: Text.ElideRight
                            }

                            Text {
                                width: root.columnWidth("size")
                                height: parent.height
                                leftPadding: 8
                                verticalAlignment: Text.AlignVCenter
                                text: modelData ? safeString(modelData.sizeText) : ""
                                color: "#b8c4d0"
                                font.pixelSize: 11
                                elide: Text.ElideRight
                            }

                            Text {
                                width: root.columnWidth("status")
                                height: parent.height
                                leftPadding: 8
                                verticalAlignment: Text.AlignVCenter
                                text: modelData ? safeString(modelData.rowStatus) : ""
                                color: modelData && modelData.rowStatus === "Found" ? "#78c28b"
                                    : (modelData && modelData.rowStatus === "Checking..." ? "#aeb7c0" : "#d08f8f")
                                font.pixelSize: 11
                                elide: Text.ElideRight
                            }

                            Text {
                                width: root.columnWidth("url")
                                height: parent.height
                                leftPadding: 8
                                verticalAlignment: Text.AlignVCenter
                                text: modelData ? safeString(modelData.sourceUrl) : ""
                                color: "#9aa6b2"
                                font.pixelSize: 11
                                elide: Text.ElideMiddle
                            }
                        }

                        Rectangle {
                            anchors.bottom: parent.bottom
                            width: parent.width
                            height: 1
                            color: "#2d2d2d"
                        }
                    }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            Text {
                Layout.fillWidth: true
                text: "Only links marked Found are selectable. Queue assignment still happens after OK."
                color: "#8899bb"
                font.pixelSize: 10
                wrapMode: Text.WordWrap
            }
            DlgButton { text: "Cancel"; onClicked: root.close() }
            DlgButton { text: "OK"; primary: true; onClicked: root.acceptRows() }
        }
    }
}
