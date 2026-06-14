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
import Qt.labs.platform
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts

Window {
    id: root
    title: root.isImport ? qsTr("Import links to SDM") : qsTr("Batch download review")
    width: 980
    height: 500
    minimumWidth: 820
    minimumHeight: 400
    color: ColorPalette.cardBg
    flags: Qt.Dialog | Qt.WindowTitleHint | Qt.WindowCloseButtonHint
    modality: Qt.ApplicationModal

    Material.theme: ColorPalette.materialTheme
    Material.foreground: ColorPalette.textPrimary
    Material.background: ColorPalette.materialBg
    Material.accent: "#4488dd"

    property var files: []
    property var reviewRows: []
    onReviewRowsChanged: _applyFilters()
    property string sortColumn: "name"
    property bool sortAscending: true
    property string resizingColumnKey: ""
    property real resizingColumnWidth: 0
    property bool colDragging: false
    property string colDragFromKey: ""
    property string colDragInsertBeforeKey: ""
    property int probeGeneration: 0
    property bool isImport: false
    property string saveMode: "perCategory"
    property string selectedCategoryId: ""
    property string selectedDirectory: ""
    property bool hideHtmlFiles: false
    property bool hideRepeatedFiles: false
    property bool hideWebpageImages: false
    property bool useLinkTextAsDescription: true
    property var fileOverrides: ({})
    property int selectedRowIndex: -1
    property var _filteredIndices: []
    property int _rowCount: 0

    ButtonGroup { id: saveModeGroup }

    signal batchAccepted(var files)

    property var columnDefs: [
        { title: "", key: "check", widthPx: 36, minWidth: 36, sortable: false, resizable: false, reorderable: false },
        { title: qsTr("File name"), key: "name", widthPx: 240, minWidth: 140, sortable: true, resizable: true, reorderable: true },
        { title: qsTr("Size"), key: "size", widthPx: 100, minWidth: 80, sortable: true, resizable: true, reorderable: true },
        { title: qsTr("Status"), key: "status", widthPx: 100, minWidth: 90, sortable: true, resizable: true, reorderable: true },
        { title: qsTr("Download from"), key: "url", widthPx: 300, minWidth: 160, sortable: true, resizable: true, reorderable: true },
        { title: qsTr("Link Text"), key: "linkText", widthPx: 180, minWidth: 100, sortable: true, resizable: true, reorderable: true },
        { title: qsTr("Save to"), key: "saveto", widthPx: 220, minWidth: 120, sortable: true, resizable: true, reorderable: true }
    ]

    function safeString(v) {
        return (v === undefined || v === null) ? "" : String(v)
    }

    function extractMagnetDisplayName(url) {
        var s = safeString(url)
        if (!s.toLowerCase().startsWith("magnet:?"))
            return ""
        var q = s.indexOf("?")
        if (q < 0) return ""
        var params = s.substring(q + 1).split("&")
        for (var i = 0; i < params.length; i++) {
            var eq = params[i].indexOf("=")
            if (eq > 0 && params[i].substring(0, eq).toLowerCase() === "dn") {
                var raw = params[i].substring(eq + 1)
                try { return decodeURIComponent(raw.replace(/\+/g, " ")) } catch(e) { return raw }
            }
        }
        return ""
    }

    function baseName(url) {
        var s = safeString(url)
        if (s.toLowerCase().startsWith("magnet:?")) {
            var dn = extractMagnetDisplayName(s)
            if (dn.length > 0) return dn
        }
        var tail = s.split("/").pop()
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

    // Match the main download list (DownloadTable.formatBytesShort) exactly so
    // sizes read the same in both places: GB .2f, MB/KB .1f.
    function formatBytes(bytes) {
        if (!bytes || bytes <= 0)
            return ""
        if (bytes >= 1073741824)
            return (bytes / 1073741824).toFixed(2) + " GB"
        if (bytes >= 1048576)
            return (bytes / 1048576).toFixed(1) + " MB"
        if (bytes >= 1024)
            return (bytes / 1024).toFixed(1) + " KB"
        return bytes + " B"
    }

    function statusRank(status) {
        if (status === "Found")
            return 0
        if (status === "Checking...")
            return 1
        return 2
    }

    function _applyFilters() {
        var indices = []
        var seenUrls = {}
        for (var i = 0; i < reviewRows.length; ++i) {
            var row = reviewRows[i]
            if (!row) continue
            if (root.hideHtmlFiles) {
                var u = (row.sourceUrl || "").toLowerCase()
                if (u.endsWith(".html") || u.endsWith(".htm"))
                    continue
            }
            if (root.hideWebpageImages) {
                var ui = (row.sourceUrl || "").toLowerCase().split("?")[0]
                if (ui.endsWith(".jpg") || ui.endsWith(".jpeg") || ui.endsWith(".png")
                    || ui.endsWith(".gif") || ui.endsWith(".webp") || ui.endsWith(".bmp")
                    || ui.endsWith(".svg") || ui.endsWith(".ico"))
                    continue
            }
            if (root.hideRepeatedFiles) {
                var key = (row.sourceUrl || "").toLowerCase()
                if (seenUrls[key] !== undefined)
                    continue
                seenUrls[key] = true
            }
            indices.push(i)
        }
        _filteredIndices = indices
        _rowCount = indices.length
        if (root.selectedRowIndex >= 0 && indices.indexOf(root.selectedRowIndex) < 0)
            root.selectedRowIndex = -1
    }

    function rowCount() {
        return _filteredIndices.length
    }

    function rowAt(index) {
        if (index < 0 || index >= _filteredIndices.length)
            return null
        return reviewRows[_filteredIndices[index]]
    }

    function setRowProperty(index, key, value) {
        if (!reviewRows || index < 0 || index >= reviewRows.length)
            return
        var rows = reviewRows.slice()
        rows[index] = Object.assign({}, rows[index], { [key]: value })
        reviewRows = rows
    }

    function effectiveSavePath(row) {
        if (!row)
            return ""
        var ov = root.fileOverrides[row.rowIndex] || {}
        if (ov.savePath)
            return safeString(ov.savePath)
        if (root.saveMode === "oneDirectory")
            return safeString(root.selectedDirectory)
        if (root.saveMode === "oneCategory")
            return safeString(App.categoryModel.savePathForCategory(root.selectedCategoryId || "all"))
        // perCategory: show the chosen directory if any, else the default path.
        if (root.selectedDirectory)
            return safeString(root.selectedDirectory)
        return safeString(App.categoryModel.savePathForCategory("all"))
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
        if (key === "linkText")
            return safeString(row.linkText).toLowerCase()
        if (key === "saveto")
            return effectiveSavePath(row).toLowerCase()
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
            var _url = safeString(f && f.url).toLowerCase()
            var _isMagnet = _url.startsWith("magnet:?")
            var _isTorrent = _url.endsWith(".torrent")
            rows.push({
                rowIndex: i,
                baseName: initialName,
                displayName: initialName,
                sourceUrl: safeString(f && f.url),
                linkText: safeString(f && f.linkText),
                rowStatus: (_isMagnet || _isTorrent) ? "Found" : "Checking...",
                statusRank: statusRank((_isMagnet || _isTorrent) ? "Found" : "Checking..."),
                selected: true,
                sizeBytes: _isMagnet ? -1 : (_isTorrent ? -1 : -1),
                sizeText: _isMagnet ? "" : (_isTorrent ? "" : ""),
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
                if (!row || row.rowStatus !== "Checking...")
                    return
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
        for (var i = 0; i < rowCount(); ++i) {
            var row = rowAt(i)
            if (row && row.rowStatus === "Found")
                rows[row.rowIndex] = Object.assign({}, rows[row.rowIndex], { selected: selected })
        }
        reviewRows = rows
    }

    function acceptRows() {
        var accepted = []
        for (var i = 0; i < rowCount(); ++i) {
            var row = rowAt(i)
            if (!row || !row.selected || row.rowStatus !== "Found")
                continue
            var ov = root.fileOverrides[row.rowIndex] || {}
            var url = ov.customUrl || row.sourceUrl
            var sp = ov.savePath || ""
            var cat = ""
            if (root.saveMode === "oneCategory") {
                cat = root.selectedCategoryId
                if (!sp)
                    sp = App.categoryModel.savePathForCategory(cat)
            } else if (root.saveMode === "oneDirectory") {
                sp = root.selectedDirectory
            }
            var desc = ov.description || ""
            if (!desc && root.useLinkTextAsDescription)
                desc = safeString(row.linkText)
            accepted.push({
                url: url,
                filename: row.displayName,
                savePath: sp,
                category: cat,
                description: desc,
                referer: ov.referer || "",
                username: ov.username || "",
                password: ov.password || ""
            })
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
        anchors.margins: 10
        spacing: 6

        RowLayout {
            Layout.fillWidth: true
            spacing: 10
            Text {
                text: root.isImport ? qsTr("Import links to SDM") : qsTr("Batch download review")
                color: ColorPalette.textPrimary
                font.pixelSize: 16 * App.fontScale
                font.bold: true
            }
            Text {
                visible: root.isImport
                Layout.fillWidth: true
                text: qsTr("Check the links you want to add to the download list and click OK.")
                color: ColorPalette.textSecond
                font.pixelSize: 10 * App.fontScale
                wrapMode: Text.NoWrap
                elide: Text.ElideRight
                verticalAlignment: Text.AlignVCenter
            }
        }

        Rectangle {
            visible: !root.isImport
            Layout.fillWidth: true
            color: ColorPalette.infoBoxBg
            border.color: ColorPalette.selectionBg
            radius: 4
            implicitHeight: 66

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 6
                spacing: 4

                Text {
                    text: qsTr("Replace filenames with wildcard pattern (*)")
                    color: ColorPalette.textPrimary
                    font.pixelSize: 10 * App.fontScale
                    font.weight: Font.Medium
                    Layout.fillWidth: true
                }
                TextField {
                    id: batchPatternField
                    Layout.fillWidth: true
                    placeholderText: patternHint()
                    color: ColorPalette.textPrimary
                    background: Rectangle {
                        color: ColorPalette.inputBg
                        border.color: batchPatternField.activeFocus ? "#4488dd" : ColorPalette.border
                        radius: 3
                    }
                    onTextChanged: refreshNames()
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            color: ColorPalette.cardBg
            border.color: ColorPalette.dividerBg
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
                    color: ColorPalette.dividerBg

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
                                color: (isSortable && headerMouse.containsMouse && !root.colDragging) ? ColorPalette.border : "transparent"
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

                                StyledCheckBox {
                                    visible: modelData.key === "check"
                                    anchors.centerIn: parent
                                    topPadding: 0
                                    bottomPadding: 0
                                    checked: root.allFoundSelected()
                                    onToggled: root.setAllSelected(!root.allFoundSelected())
                                }

                                Text {
                                    visible: modelData.key !== "check"
                                    anchors.left: parent.left
                                    anchors.leftMargin: 8
                                    anchors.verticalCenter: parent.verticalCenter
                                    anchors.right: sortText.left
                                    anchors.rightMargin: 4
                                    text: modelData.title
                                    color: root.sortColumn === modelData.key ? ColorPalette.accent : ColorPalette.textPrimary
                                    font.pixelSize: 12 * App.fontScale
                                    font.bold: true
                                    elide: Text.ElideRight
                                }

                                Text {
                                    id: sortText
                                    anchors.verticalCenter: parent.verticalCenter
                                    anchors.right: resizeHandle.left
                                    anchors.rightMargin: 4
                                    text: root.sortAscending ? "▲" : "▼"
                                    color: "#88bbff"
                                    font.pixelSize: 9 * App.fontScale
                                    visible: root.sortColumn === modelData.key
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
                                    color: ColorPalette.border
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
                    model: root._rowCount
                    clip: true
                    spacing: 0
                    boundsBehavior: Flickable.StopAtBounds
                    ScrollBar.vertical: ScrollBar {}

                    delegate: Rectangle {
                        required property int index
                        readonly property var modelData: root.rowAt(index)
                        readonly property int rowIndex: modelData && modelData.rowIndex !== undefined ? modelData.rowIndex : 0
                        readonly property bool isSelected: root.selectedRowIndex === rowIndex
                        width: tableFlick.contentWidth
                        height: 26
                        color: isSelected ? ColorPalette.selectionBg
                            : (rowHover.hovered ? ColorPalette.hoverBg
                            : (rowIndex % 2 === 0 ? ColorPalette.windowBg : ColorPalette.rowAltBg))

                        HoverHandler { id: rowHover }

                        Row {
                            anchors.fill: parent
                            spacing: 0

                            Item {
                                width: root.columnWidth("check")
                                height: parent.height
                                StyledCheckBox {
                                    anchors.centerIn: parent
                                    topPadding: 0
                                    bottomPadding: 0
                                    enabled: !!(modelData && modelData.rowStatus === "Found")
                                    checked: !!(modelData && modelData.selected)
                                    onToggled: root.setRowProperty(rowIndex, "selected", checked)
                                }
                            }

                            Item {
                                width: root.columnWidth("name")
                                height: parent.height
                                Image {
                                    id: nameIcon
                                    anchors.left: parent.left
                                    anchors.leftMargin: 6
                                    anchors.verticalCenter: parent.verticalCenter
                                    source: modelData ? modelData.iconSource : ""
                                    width: 18
                                    height: 18
                                    sourceSize: Qt.size(18, 18)
                                    smooth: true
                                    fillMode: Image.PreserveAspectFit
                                }
                                Text {
                                    anchors.left: nameIcon.right
                                    anchors.leftMargin: 6
                                    anchors.right: parent.right
                                    anchors.rightMargin: 4
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: modelData ? safeString(modelData.displayName) : ""
                                    color: isSelected ? ColorPalette.selectionText : ColorPalette.textPrimary
                                    font.pixelSize: 12 * App.fontScale
                                    elide: Text.ElideMiddle
                                }
                            }

                            Text {
                                width: root.columnWidth("size")
                                height: parent.height
                                leftPadding: 6
                                verticalAlignment: Text.AlignVCenter
                                text: modelData ? safeString(modelData.sizeText) : ""
                                color: isSelected ? ColorPalette.selectionText : ColorPalette.textPrimary
                                font.pixelSize: 12 * App.fontScale
                                elide: Text.ElideRight
                            }

                            Text {
                                width: root.columnWidth("status")
                                height: parent.height
                                leftPadding: 6
                                verticalAlignment: Text.AlignVCenter
                                text: modelData ? safeString(modelData.rowStatus) : ""
                                color: isSelected ? ColorPalette.selectionText : ColorPalette.textPrimary
                                font.pixelSize: 12 * App.fontScale
                                elide: Text.ElideRight
                            }

                            Text {
                                width: root.columnWidth("url")
                                height: parent.height
                                leftPadding: 6
                                verticalAlignment: Text.AlignVCenter
                                text: modelData ? safeString(modelData.sourceUrl) : ""
                                color: isSelected ? ColorPalette.selectionText : ColorPalette.textPrimary
                                font.pixelSize: 12 * App.fontScale
                                elide: Text.ElideMiddle
                            }

                            Text {
                                width: root.columnWidth("linkText")
                                height: parent.height
                                leftPadding: 6
                                verticalAlignment: Text.AlignVCenter
                                text: modelData ? safeString(modelData.linkText) : ""
                                color: isSelected ? ColorPalette.selectionText : ColorPalette.textPrimary
                                font.pixelSize: 12 * App.fontScale
                                elide: Text.ElideRight
                            }

                            Text {
                                width: root.columnWidth("saveto")
                                height: parent.height
                                leftPadding: 6
                                verticalAlignment: Text.AlignVCenter
                                text: modelData ? root.effectiveSavePath(modelData) : ""
                                color: isSelected ? ColorPalette.selectionText : ColorPalette.textPrimary
                                font.pixelSize: 12 * App.fontScale
                                elide: Text.ElideMiddle
                            }
                        }

                        TapHandler {
                            onTapped: {
                                root.selectedRowIndex = rowIndex
                                fileList.currentIndex = index
                            }
                        }

                        Rectangle {
                            anchors.bottom: parent.bottom
                            width: parent.width
                            height: 1
                            color: ColorPalette.dividerBg
                        }
                    }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            Rectangle {
                Layout.fillWidth: true
                Layout.maximumWidth: 560
                Layout.minimumWidth: 300
                color: ColorPalette.cardBg
                border.color: ColorPalette.border
                radius: 4
                height: saveModeCol.height + 16

                Column {
                    id: saveModeCol
                    x: 8; y: 8
                    width: parent.width - 16
                    spacing: 6

                    Text {
                        text: qsTr("Save to:")
                        color: ColorPalette.textPrimary
                        font.pixelSize: 11 * App.fontScale
                        font.weight: Font.Medium
                    }

                    StyledRadioButton {
                        id: perCategoryRadio
                        ButtonGroup.group: saveModeGroup
                        width: parent.width
                        text: qsTr("Every file to the directory according to the category of the file")
                        checked: root.saveMode === "perCategory"
                        font.pixelSize: 11 * App.fontScale
                        padding: 0
                        spacing: 8
                        topPadding: 2; bottomPadding: 2
                        contentItem: Text {
                            text: parent.text
                            font: parent.font
                            color: ColorPalette.textPrimary
                            verticalAlignment: Text.AlignVCenter
                            wrapMode: Text.WordWrap
                            leftPadding: parent.indicator.width + parent.spacing
                        }
                        onCheckedChanged: if (checked) root.saveMode = "perCategory"
                    }

                    StyledRadioButton {
                        id: oneCategoryRadio
                        ButtonGroup.group: saveModeGroup
                        width: parent.width
                        text: qsTr("All files to one category")
                        checked: root.saveMode === "oneCategory"
                        font.pixelSize: 11 * App.fontScale
                        padding: 0
                        spacing: 8
                        topPadding: 2; bottomPadding: 2
                        contentItem: Text {
                            text: parent.text
                            font: parent.font
                            color: ColorPalette.textPrimary
                            verticalAlignment: Text.AlignVCenter
                            wrapMode: Text.WordWrap
                            leftPadding: parent.indicator.width + parent.spacing
                        }
                        onCheckedChanged: {
                            if (checked) {
                                root.saveMode = "oneCategory"
                                if (!root.selectedCategoryId)
                                    root.selectedCategoryId = (categoryCombo.currentIndex >= 0 ? categoryCombo.currentValue : "") || "all"
                            }
                        }
                    }

                    Item {
                        width: parent.width
                        height: visible ? categoryCombo.implicitHeight : 0
                        visible: root.saveMode === "oneCategory"
                        StyledComboBox {
                            id: categoryCombo
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.leftMargin: 28
                            model: App.categoryModel
                            textRole: "categoryLabel"
                            valueRole: "categoryId"
                            background: Rectangle { color: ColorPalette.inputBg; border.color: ColorPalette.border; radius: 4 }
                            contentItem: Text { leftPadding: 8; text: categoryCombo.displayText; color: ColorPalette.textPrimary; font: categoryCombo.font; verticalAlignment: Text.AlignVCenter }
                            onActivated: root.selectedCategoryId = currentValue
                            Component.onCompleted: currentIndex = indexOfValue(root.selectedCategoryId)
                        }
                    }

                    StyledRadioButton {
                        id: oneDirRadio
                        ButtonGroup.group: saveModeGroup
                        width: parent.width
                        text: qsTr("All files to one directory")
                        checked: root.saveMode === "oneDirectory"
                        font.pixelSize: 11 * App.fontScale
                        padding: 0
                        spacing: 8
                        topPadding: 2; bottomPadding: 2
                        contentItem: Text {
                            text: parent.text
                            font: parent.font
                            color: ColorPalette.textPrimary
                            verticalAlignment: Text.AlignVCenter
                            wrapMode: Text.WordWrap
                            leftPadding: parent.indicator.width + parent.spacing
                        }
                        onCheckedChanged: if (checked) root.saveMode = "oneDirectory"
                    }

                    Item {
                        width: parent.width
                        height: visible ? dirRow.implicitHeight : 0
                        visible: root.saveMode === "oneDirectory"
                        RowLayout {
                            id: dirRow
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.leftMargin: 28
                            spacing: 6
                            TextField {
                                id: dirField
                                Layout.fillWidth: true
                                readOnly: true
                                text: root.selectedDirectory
                                color: ColorPalette.textPrimary
                                font.pixelSize: 11 * App.fontScale
                                implicitHeight: 28
                                background: Rectangle { color: ColorPalette.inputBg; border.color: ColorPalette.border; radius: 4 }
                            }
                            DlgButton {
                                text: qsTr("Browse...")
                                onClicked: saveDirDialog.open()
                            }
                        }
                    }
                }
            }

            ColumnLayout {
                spacing: 6
                Layout.preferredWidth: 300
                Layout.minimumWidth: 280

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6
                    DlgButton {
                        text: qsTr("Edit...")
                        enabled: root.selectedRowIndex >= 0 && root._filteredIndices.indexOf(root.selectedRowIndex) >= 0
                        onClicked: editWindow.open(root.selectedRowIndex)
                    }
                    Item { Layout.fillWidth: true }
                    DlgButton { text: qsTr("Check all"); onClicked: setAllSelected(true) }
                    DlgButton { text: qsTr("Uncheck all"); onClicked: setAllSelected(false) }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    StyledCheckBox {
                        id: useLinkTextChk
                        text: qsTr("Use link texts as download descriptions")
                        topPadding: 0; bottomPadding: 0
                        checked: root.useLinkTextAsDescription
                        contentItem: Text { text: parent.text; color: ColorPalette.textPrimary; font.pixelSize: 11 * App.fontScale; leftPadding: parent.indicator.width + 4 }
                        onToggled: root.useLinkTextAsDescription = checked
                    }
                    StyledCheckBox {
                        id: hideHtmlChk
                        text: qsTr("Hide HTML files")
                        topPadding: 0; bottomPadding: 0
                        checked: root.hideHtmlFiles
                        contentItem: Text { text: parent.text; color: ColorPalette.textPrimary; font.pixelSize: 11 * App.fontScale; leftPadding: parent.indicator.width + 4 }
                        onToggled: { root.hideHtmlFiles = checked; root._applyFilters() }
                    }
                    StyledCheckBox {
                        id: hideImagesChk
                        text: qsTr("Hide images located on this web page")
                        topPadding: 0; bottomPadding: 0
                        checked: root.hideWebpageImages
                        contentItem: Text { text: parent.text; color: ColorPalette.textPrimary; font.pixelSize: 11 * App.fontScale; leftPadding: parent.indicator.width + 4 }
                        onToggled: { root.hideWebpageImages = checked; root._applyFilters() }
                    }
                    StyledCheckBox {
                        id: hideRepeatChk
                        text: qsTr("Hide repeated files")
                        topPadding: 0; bottomPadding: 0
                        checked: root.hideRepeatedFiles
                        contentItem: Text { text: parent.text; color: ColorPalette.textPrimary; font.pixelSize: 11 * App.fontScale; leftPadding: parent.indicator.width + 4 }
                        onToggled: { root.hideRepeatedFiles = checked; root._applyFilters() }
                    }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            Item { Layout.fillWidth: true }
            DlgButton { text: qsTr("Cancel"); onClicked: root.close() }
            DlgButton { text: qsTr("OK"); primary: true; onClicked: root.acceptRows() }
        }
    }

    FolderDialog {
        id: saveDirDialog
        title: qsTr("Select save directory")
        onAccepted: {
            var path = folder.toString()
                .replace(/^file:\/\/\//, "")
                .replace(/^file:\/\//, "")
            root.selectedDirectory = path
            dirField.text = path
        }
    }

    FileDialog {
        id: editSaveFileDialog
        title: qsTr("Select save path")
        fileMode: FileDialog.SaveFile
        onAccepted: {
            var path = file.toString()
                .replace(/^file:\/\/\//, "")
                .replace(/^file:\/\//, "")
            editSaveField.text = path
        }
    }

    Window {
        id: editWindow
        title: qsTr("Edit File")
        width: 500
        height: editWindowCol.implicitHeight + 32
        minimumWidth: 420
        color: ColorPalette.cardBg
        flags: Qt.Dialog | Qt.WindowTitleHint | Qt.WindowCloseButtonHint
        modality: Qt.ApplicationModal
        transientParent: root

        Material.theme: ColorPalette.materialTheme
    Material.foreground: ColorPalette.textPrimary
        Material.background: ColorPalette.materialBg
        Material.accent: "#4488dd"

        property int rowIndex: -1
        property var rowData: null

        function open(rowIdx) {
            editWindow.rowIndex = rowIdx
            editWindow.rowData = (root.reviewRows && rowIdx >= 0 && rowIdx < root.reviewRows.length) ? root.reviewRows[rowIdx] : null
            var ov = root.fileOverrides[rowIdx] || {}
            editSaveField.text = ov.savePath || ""
            editUrlField.text = ov.customUrl || (editWindow.rowData ? editWindow.rowData.sourceUrl : "")
            editDescField.text = ov.description || ""
            editRefererField.text = ov.referer || ""
            editLoginField.text = ov.username || ""
            editPassField.text = ov.password || ""
            editWindow.show()
            editWindow.raise()
            editWindow.requestActivate()
        }

        ColumnLayout {
            id: editWindowCol
            anchors.fill: parent
            anchors.margins: 12
            spacing: 8

            Text { text: qsTr("Edit File"); color: ColorPalette.textHeader; font.pixelSize: 13 * App.fontScale; font.bold: true }

            RowLayout {
                Layout.fillWidth: true
                spacing: 6
                Text { text: qsTr("Save to:"); color: ColorPalette.textPrimary; font.pixelSize: 11 * App.fontScale; Layout.preferredWidth: 72 }
                TextField {
                    id: editSaveField
                    Layout.fillWidth: true
                    color: ColorPalette.textPrimary
                    font.pixelSize: 11 * App.fontScale
                    background: Rectangle { color: ColorPalette.inputBg; border.color: ColorPalette.border; radius: 4 }
                }
                DlgButton {
                    text: qsTr("Browse...")
                    implicitWidth: 72
                    onClicked: editSaveFileDialog.open()
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 6
                Text { text: qsTr("URL:"); color: ColorPalette.textPrimary; font.pixelSize: 11 * App.fontScale; Layout.preferredWidth: 72 }
                TextField {
                    id: editUrlField
                    Layout.fillWidth: true
                    color: ColorPalette.textPrimary
                    font.pixelSize: 11 * App.fontScale
                    background: Rectangle { color: ColorPalette.inputBg; border.color: ColorPalette.border; radius: 4 }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 6
                Text { text: qsTr("Description:"); color: ColorPalette.textPrimary; font.pixelSize: 11 * App.fontScale; Layout.preferredWidth: 72 }
                TextField {
                    id: editDescField
                    Layout.fillWidth: true
                    color: ColorPalette.textPrimary
                    font.pixelSize: 11 * App.fontScale
                    background: Rectangle { color: ColorPalette.inputBg; border.color: ColorPalette.border; radius: 4 }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 6
                Text { text: qsTr("Referer:"); color: ColorPalette.textPrimary; font.pixelSize: 11 * App.fontScale; Layout.preferredWidth: 72 }
                TextField {
                    id: editRefererField
                    Layout.fillWidth: true
                    color: ColorPalette.textPrimary
                    font.pixelSize: 11 * App.fontScale
                    background: Rectangle { color: ColorPalette.inputBg; border.color: ColorPalette.border; radius: 4 }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 6
                Text { text: qsTr("Login:"); color: ColorPalette.textPrimary; font.pixelSize: 11 * App.fontScale; Layout.preferredWidth: 72 }
                TextField {
                    id: editLoginField
                    Layout.fillWidth: true
                    color: ColorPalette.textPrimary
                    font.pixelSize: 11 * App.fontScale
                    background: Rectangle { color: ColorPalette.inputBg; border.color: ColorPalette.border; radius: 4 }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 6
                Text { text: qsTr("Password:"); color: ColorPalette.textPrimary; font.pixelSize: 11 * App.fontScale; Layout.preferredWidth: 72 }
                TextField {
                    id: editPassField
                    Layout.fillWidth: true
                    echoMode: TextInput.Password
                    color: ColorPalette.textPrimary
                    font.pixelSize: 11 * App.fontScale
                    background: Rectangle { color: ColorPalette.inputBg; border.color: ColorPalette.border; radius: 4 }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Item { Layout.fillWidth: true }
                DlgButton { text: qsTr("Cancel"); onClicked: editWindow.close() }
                DlgButton {
                    text: qsTr("Save")
                    primary: true
                    onClicked: {
                        var ov = root.fileOverrides[editWindow.rowIndex] || {}
                        ov.savePath = editSaveField.text
                        ov.customUrl = editUrlField.text
                        ov.description = editDescField.text
                        ov.referer = editRefererField.text
                        ov.username = editLoginField.text
                        ov.password = editPassField.text
                        root.fileOverrides[editWindow.rowIndex] = ov
                        editWindow.close()
                    }
                }
            }
        }
    }
}
