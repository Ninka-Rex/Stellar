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
    title: "Stellar Grabber"
    width: 1060
    height: 570
    minimumWidth: 1060
    minimumHeight: 570
    color: "#1e1e1e"
    flags: Qt.Dialog | Qt.WindowTitleHint | Qt.WindowCloseButtonHint | Qt.WindowMinimizeButtonHint
    modality: Qt.ApplicationModal

    Material.theme: Material.Dark
    Material.background: "#1e1e1e"
    Material.accent: "#4488dd"

    property string projectId: ""
    property string projectName: ""
    property bool actionTaken: false
    property int checkedCount: 0
    property int totalCount: 0
    // sideMode: "all" | "link" | "folder"
    property string sideMode: "all"
    property string sideFilterValue: ""
    property string sortColumn: "filename"
    property bool sortAscending: true
    property string resizingColumnKey: ""
    property real resizingColumnWidth: 0
    property var selectedRows: ({})
    property int selectionVersion: 0
    property int anchorRow: -1
    property var expandedFolderNodes: ({})
    property var expandedLinkNodes: ({})
    property var expandedSections: ({ "link": true, "folder": true })
    // Cached sidebar tree lists — rebuilt explicitly rather than reactively so that
    // rapid row inserts during a crawl don't trigger O(n) rebuilds per insert.
    property var _linkItems: []
    property var _folderItems: []
    property var columnDefs: [
        { title: "", key: "check", widthPx: 34 },
        { title: "File Name", key: "filename", widthPx: 210 },
        { title: "File Type", key: "filetype", widthPx: 100 },
        { title: "Size", key: "size", widthPx: 86 },
        { title: "Status", key: "status", widthPx: 110 },
        { title: "Link Text", key: "linktext", widthPx: 140 },
        { title: "Download from", key: "downloadfrom", widthPx: 250 },
        { title: "Save to", key: "saveto", widthPx: 260 }
    ]

    signal queueAssignmentRequested(string projectId)
    signal scheduleRequested(string projectId)
    signal statisticsRequested(string projectId)
    signal editProjectRequested(string projectId)
    // Emitted after the user triggers a download action so the caller can bring
    // the main window to the front and close this dialog.
    signal filesAddedToDownloadList()

    function isRowSelected(row) { return !!selectedRows[row] }
    function setSelection(rows) { selectedRows = rows; selectionVersion += 1 }
    function clearAndSelect(row) {
        var rows = {}
        if (row >= 0) rows[row] = true
        setSelection(rows)
    }
    function toggleRow(row) {
        var rows = Object.assign({}, selectedRows)
        if (rows[row]) delete rows[row]
        else rows[row] = true
        setSelection(rows)
    }
    function addRangeTo(anchor, row) {
        var rows = Object.assign({}, selectedRows)
        var lo = Math.min(anchor, row), hi = Math.max(anchor, row)
        for (var i = lo; i <= hi; ++i) rows[i] = true
        setSelection(rows)
    }
    function selectedRowIndexes() {
        selectionVersion
        var rows = Object.keys(selectedRows).map(function(v) { return parseInt(v) })
        rows.sort(function(a, b) { return a - b })
        return rows
    }
    function setSelectedChecked(checked) {
        var rows = selectedRowIndexes()
        for (var i = 0; i < rows.length; ++i) App.setGrabberResultChecked(rows[i], checked)
    }
    function allRowsChecked() {
        // O(1): compare maintained counters instead of iterating every row.
        return totalCount > 0 && checkedCount === totalCount
    }
    function toggleAllChecked(checked) { App.setAllGrabberResultsChecked(checked) }

    function openGrabberSettings() {
        if (!grabberSettingsLoader.item) grabberSettingsLoader.active = true
        if (grabberSettingsLoader.item) {
            grabberSettingsLoader.item.show()
            grabberSettingsLoader.item.raise()
            grabberSettingsLoader.item.requestActivate()
        }
    }

    function projectData() { return App.grabberProjectData(projectId) }
    function refreshState() {
        var project = projectData()
        projectName = project.name || "Grabber Project"
        checkedCount = App.checkedGrabberResultCount()
        totalCount = App.grabberResultModel.rowCount()
    }
    function fileTypeLabel(name, url) {
        var source = name && name.length > 0 ? name : url
        var idx = source.lastIndexOf(".")
        if (idx < 0 || idx === source.length - 1) return "Unknown"
        return source.substring(idx + 1).toUpperCase() + " File"
    }
    function hostFromUrl(url) {
        var match = /^https?:\/\/([^\/]+)/i.exec(url)
        return match ? match[1].toLowerCase() : ""
    }
    function baseHost(url) {
        var host = hostFromUrl(url)
        return host.length > 0 ? host : "(other)"
    }
    function sourcePagePath(url) {
        var match = /^https?:\/\/[^\/]+(\/.*)$/i.exec(url || "")
        return match ? match[1] : "/"
    }
    function pathSegments(url) {
        var path = sourcePagePath(url)
        if (!path || path === "/") return []
        return path.split("/").filter(function(part) { return part.length > 0 })
    }
    function folderNodeId(host, path) { return host + "|" + path }
    function isFolderExpanded(nodeId) { return !!expandedFolderNodes[nodeId] }
    function setFolderExpanded(nodeId, expanded) {
        var next = Object.assign({}, expandedFolderNodes)
        if (expanded) next[nodeId] = true
        else delete next[nodeId]
        expandedFolderNodes = next
    }
    function isSectionExpanded(section) { return !!expandedSections[section] }
    function setSectionExpanded(section, expanded) {
        var next = Object.assign({}, expandedSections)
        if (expanded) next[section] = true
        else delete next[section]
        expandedSections = next
    }
    function isLinkNodeExpanded(nodeId) { return !!expandedLinkNodes[nodeId] }
    function setLinkNodeExpanded(nodeId, expanded) {
        var next = Object.assign({}, expandedLinkNodes)
        if (expanded) next[nodeId] = true
        else delete next[nodeId]
        expandedLinkNodes = next
    }

    function linkTreeItems() {
        var domains = {}
        var count = totalCount
        for (var i = 0; i < count; ++i) {
            var row = App.grabberResultModel.resultData(i)
            var host = baseHost(row.sourcePage && row.sourcePage.length > 0 ? row.sourcePage : row.url)
            var pageKey = (row.sourcePage && row.sourcePage.length > 0) ? row.sourcePage : (host !== "(other)" ? "https://" + host + "/" : row.url)
            if (!domains[host]) domains[host] = {}
            domains[host][pageKey] = true
        }
        var items = []
        var hostKeys = Object.keys(domains).sort()
        for (var h = 0; h < hostKeys.length; ++h) {
            var host = hostKeys[h]
            var pages = Object.keys(domains[host]).sort()
            var isExp = isLinkNodeExpanded(host)
            items.push({ id: host, label: host, host: host, page: "", depth: 0,
                         hasChildren: pages.length > 0, isExpanded: isExp, isDomain: true })
            if (isExp) {
                for (var p = 0; p < pages.length; ++p) {
                    var pageUrl = pages[p]
                    var pageLabel = sourcePagePath(pageUrl) || "/"
                    items.push({ id: host + "|" + pageUrl, label: pageLabel, host: host,
                                 page: pageUrl, depth: 1, hasChildren: false,
                                 isExpanded: false, isDomain: false })
                }
            }
        }
        return items
    }

    function folderTreeItems() {
        var roots = {}
        var count = totalCount
        for (var i = 0; i < count; ++i) {
            var row = App.grabberResultModel.resultData(i)
            var host = baseHost(row.sourcePage && row.sourcePage.length > 0 ? row.sourcePage : row.url)
            var source = (row.sourcePage && row.sourcePage.length > 0) ? row.sourcePage : (host !== "(other)" ? "https://" + host + "/" : row.url)
            if (!roots[host])
                roots[host] = { id: folderNodeId(host, ""), label: host, path: "", children: {} }
            var cursor = roots[host]
            var cumulative = ""
            var segments = pathSegments(source)
            for (var j = 0; j < segments.length; ++j) {
                cumulative += "/" + segments[j]
                if (!cursor.children[cumulative])
                    cursor.children[cumulative] = { id: folderNodeId(host, cumulative),
                        label: segments[j], path: cumulative, children: {} }
                cursor = cursor.children[cumulative]
            }
        }
        function flattenNode(node, depth, out) {
            out.push({ id: node.id, label: node.label, path: node.path,
                       host: node.id.split("|")[0], depth: depth,
                       hasChildren: Object.keys(node.children).length > 0 })
            if (!isFolderExpanded(node.id)) return
            var childKeys = Object.keys(node.children).sort(function(a, b) {
                return node.children[a].label.localeCompare(node.children[b].label)
            })
            for (var k = 0; k < childKeys.length; ++k)
                flattenNode(node.children[childKeys[k]], depth + 1, out)
        }
        var items = []
        var hostKeys = Object.keys(roots).sort()
        for (var h = 0; h < hostKeys.length; ++h)
            flattenNode(roots[hostKeys[h]], 0, items)
        return items
    }

    function rowMatchesSideFilter(rowUrl, rowSourcePage) {
        if (sideMode === "all") return true
        var source = rowSourcePage && rowSourcePage.length > 0 ? rowSourcePage : rowUrl
        if (sideMode === "link") {
            if (sideFilterValue.length === 0) return true
            var sep = sideFilterValue.indexOf("|")
            if (sep < 0)
                return baseHost(source) === sideFilterValue
            return (rowSourcePage || rowUrl) === sideFilterValue.substring(sep + 1)
        }
        // folder mode
        if (sideFilterValue.length === 0) return true
        var pieces = sideFilterValue.split("|")
        var fHost = pieces[0] || ""
        var folderPath = pieces.length > 1 ? pieces.slice(1).join("|") : ""
        if (baseHost(source) !== fHost) return false
        if (folderPath.length === 0) return true
        var rowPath = sourcePagePath(source)
        return rowPath === folderPath || rowPath.indexOf(folderPath + "/") === 0
    }

    function computeStatus(url) {
        // Skip the C++ lookup for every visible row while the crawler is running —
        // the answer is always "Exploring" and the call is expensive at scale.
        if (App.grabberBusy) return "Exploring"
        var existing = App.findDuplicateUrl(url)
        if (existing && existing.category === projectId) return existing.status
        if (existing) return "Already in list"
        return "Ready"
    }
    function saveToText(filename) {
        var project = projectData()
        var path = project.savePath || App.settings.defaultSavePath
        return path + "/" + filename
    }
    function columnWidth(key) {
        if (resizingColumnKey === key) return resizingColumnWidth
        for (var i = 0; i < columnDefs.length; ++i)
            if (columnDefs[i].key === key) return columnDefs[i].widthPx
        return 100
    }
    function setColumnWidth(key, width) {
        var defs = []
        for (var i = 0; i < columnDefs.length; ++i) {
            var def = Object.assign({}, columnDefs[i])
            if (def.key === key) def.widthPx = Math.max(key === "check" ? 34 : 60, Math.round(width))
            defs.push(def)
        }
        columnDefs = defs
    }
    function totalColumnWidth() {
        var total = 0
        for (var i = 0; i < columnDefs.length; ++i) total += columnWidth(columnDefs[i].key)
        return total
    }
    function sortBy(column) {
        if (sortColumn === column) sortAscending = !sortAscending
        else { sortColumn = column; sortAscending = true }
        App.sortGrabberResults(sortColumn, sortAscending)
    }
    function sortIndicator(column) {
        if (sortColumn !== column) return ""
        return sortAscending ? " ▲" : " ▼"
    }
    function rebuildSidebarTrees() {
        _linkItems   = isSectionExpanded("link")   ? linkTreeItems()   : []
        _folderItems = isSectionExpanded("folder") ? folderTreeItems() : []
    }

    // Debounce sidebar rebuilds during crawling so rapid row inserts don't
    // queue thousands of O(n) tree reconstructions.
    Timer {
        id: sidebarRebuildTimer
        interval: 350
        repeat: false
        onTriggered: root.rebuildSidebarTrees()
    }

    function visibleRowCount() {
        if (sideMode === "all") return totalCount
        var visible = 0
        for (var i = 0; i < totalCount; ++i) {
            var row = App.grabberResultModel.resultData(i)
            if (rowMatchesSideFilter(row.url, row.sourcePage)) visible++
        }
        return visible
    }

    function _centerOnOwner() {
        var owner = root.transientParent
        if (owner) {
            x = owner.x + Math.round((owner.width  - width)  / 2)
            y = owner.y + Math.round((owner.height - height) / 2)
            return
        }
        x = Math.round((Screen.width  - width)  / 2)
        y = Math.round((Screen.height - height) / 2)
    }

    onVisibleChanged: {
        if (visible) {
            _centerOnOwner()
            actionTaken = false
            sideMode = "all"
            sideFilterValue = ""
            expandedFolderNodes = {}
            expandedLinkNodes = {}
            expandedSections = { "link": true, "folder": true }
            App.loadGrabberProjectResults(projectId)
            refreshState()
            rebuildSidebarTrees()
        }
    }

    Component.onCompleted: {
        App.setWindowIcon(root, ":/qt/qml/com/stellar/app/app/qml/icons/wand.ico")
    }

    onClosing: (close) => {
        if (actionTaken || !projectId.length) return
        var project = projectData()
        if (project.addCheckedFilesToIdm) {
            App.downloadGrabberResults(projectId, false)
            actionTaken = true
        }
    }

    Connections {
        target: App.grabberResultModel
        function onDataChanged() {
            root.checkedCount = App.checkedGrabberResultCount()
            root.totalCount = App.grabberResultModel.rowCount()
            // No sidebar rebuild — data-only changes (checked state, size) don't affect the tree
        }
        function onModelReset() {
            root.checkedCount = App.checkedGrabberResultCount()
            root.totalCount = App.grabberResultModel.rowCount()
            root.rebuildSidebarTrees()
        }
        function onRowsInserted() {
            root.checkedCount = App.checkedGrabberResultCount()
            root.totalCount = App.grabberResultModel.rowCount()
            // Debounce: avoid rebuilding the O(n) sidebar tree on every single result found
            sidebarRebuildTimer.restart()
        }
        function onRowsRemoved() {
            root.checkedCount = App.checkedGrabberResultCount()
            root.totalCount = App.grabberResultModel.rowCount()
            root.setSelection({})
            root.anchorRow = -1
            root.rebuildSidebarTrees()
        }
    }

    Loader {
        id: grabberSettingsLoader
        active: false
        source: "GrabberSettingsDialog.qml"
    }

    Menu {
        id: resultsContextMenu
        MenuItem {
            text: "Check selected"
            enabled: root.selectedRowIndexes().length > 0
            onTriggered: root.setSelectedChecked(true)
        }
        MenuItem {
            text: "Uncheck selected"
            enabled: root.selectedRowIndexes().length > 0
            onTriggered: root.setSelectedChecked(false)
        }
    }

    Rectangle {
        anchors.fill: parent
        color: "#1e1e1e"

        ColumnLayout {
            anchors.fill: parent
            spacing: 0

            // ── Menu bar ──────────────────────────────────────────────────────
            Rectangle {
                Layout.fillWidth: true
                height: 28
                color: "#222228"

                Menu {
                    id: mbProjectMenu
                    Action { text: "Edit current project"; onTriggered: root.editProjectRequested(root.projectId) }
                    Action { text: "Close"; onTriggered: root.close() }
                }
                Menu {
                    id: mbOptionsMenu
                    Action { text: "Grabber settings"; onTriggered: root.openGrabberSettings() }
                }

                Row {
                    anchors.fill: parent

                    Repeater {
                        model: [
                            { label: "Project", menu: mbProjectMenu },
                            { label: "Options", menu: mbOptionsMenu }
                        ]
                        delegate: Rectangle {
                            required property var modelData
                            width: mbLabel.implicitWidth + 20
                            height: 28
                            color: mbMa.containsMouse || modelData.menu.visible ? "#1e3a6e" : "transparent"

                            Text {
                                id: mbLabel
                                anchors.centerIn: parent
                                text: modelData.label
                                color: "#d0d0d0"
                                font.pixelSize: 12
                            }
                            MouseArea {
                                id: mbMa
                                anchors.fill: parent
                                hoverEnabled: true
                                onClicked: modelData.menu.popup(0, parent.height)
                            }
                        }
                    }
                }

                Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: "#333333" }
            }

            // ── Project info / status strip ───────────────────────────────────
            Rectangle {
                Layout.fillWidth: true
                height: 46
                color: "#222222"

                // Left accent bar
                Rectangle {
                    anchors { top: parent.top; bottom: parent.bottom; left: parent.left }
                    width: 3
                    color: "#4488dd"
                }

                RowLayout {
                    anchors {
                        verticalCenter: parent.verticalCenter
                        left: parent.left; leftMargin: 14
                        right: parent.right; rightMargin: 12
                    }
                    spacing: 16

                    // Project name + status
                    Column {
                        spacing: 3
                        Layout.fillWidth: true

                        Text {
                            text: projectName
                            color: "#e0e0e0"
                            font.pixelSize: 13
                            font.bold: true
                        }

                        Row {
                            spacing: 12

                            // Animated status dot
                            Row {
                                spacing: 5
                                anchors.verticalCenter: parent.verticalCenter

                                Rectangle {
                                    id: statusDot
                                    width: 7; height: 7; radius: 4
                                    anchors.verticalCenter: parent.verticalCenter
                                    color: App.grabberBusy ? "#55cc88" : "#444455"

                                    SequentialAnimation on opacity {
                                        id: dotAnim
                                        running: App.grabberBusy
                                        loops: Animation.Infinite
                                        NumberAnimation { to: 0.35; duration: 600; easing.type: Easing.InOutSine }
                                        NumberAnimation { to: 1.0;  duration: 600; easing.type: Easing.InOutSine }
                                        onRunningChanged: if (!running) statusDot.opacity = 1.0
                                    }
                                }

                                Text {
                                    text: App.grabberBusy ? "Running" : "Idle"
                                    color: App.grabberBusy ? "#55cc88" : "#555566"
                                    font.pixelSize: 11
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                            }

                            // Divider
                            Rectangle { width: 1; height: 12; color: "#363636"; anchors.verticalCenter: parent.verticalCenter }

                            Text {
                                text: totalCount + " files found"
                                color: "#777788"
                                font.pixelSize: 11
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            Rectangle { width: 1; height: 12; color: "#363636"; anchors.verticalCenter: parent.verticalCenter }

                            Text {
                                text: checkedCount + " checked"
                                color: checkedCount > 0 ? "#88bbff" : "#555566"
                                font.pixelSize: 11
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            Text {
                                visible: App.grabberStatusText.length > 0
                                text: "— " + App.grabberStatusText
                                color: "#556677"
                                font.pixelSize: 11
                                elide: Text.ElideRight
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }
                    }

                    // Slim progress bar, only visible while crawling
                    Rectangle {
                        visible: App.grabberBusy
                        width: 160; height: 4; radius: 2
                        color: "#2a2a3a"
                        Layout.alignment: Qt.AlignVCenter

                        Rectangle {
                            id: progressPulse
                            height: parent.height; radius: parent.radius
                            color: "#4488dd"

                            SequentialAnimation on x {
                                running: App.grabberBusy
                                loops: Animation.Infinite
                                NumberAnimation { from: -60; to: 160; duration: 1100; easing.type: Easing.InOutSine }
                            }
                            width: 60
                            clip: false

                            layer.enabled: true
                            layer.effect: null
                        }

                        // Clip the moving bar inside the track
                        clip: true
                    }
                }

                Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: "#2d2d2d" }
            }

            // ── Toolbar ───────────────────────────────────────────────────────
            Rectangle {
                Layout.fillWidth: true
                height: 64
                color: "#252525"

                Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: "#2d2d2d" }

                Flickable {
                    anchors.fill: parent
                    anchors.topMargin: 2; anchors.bottomMargin: 2
                    clip: true
                    contentWidth: toolbarRow.implicitWidth
                    contentHeight: toolbarRow.implicitHeight
                    ScrollBar.horizontal: ScrollBar { policy: ScrollBar.AsNeeded }
                    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AlwaysOff }

                    Row {
                        id: toolbarRow
                        spacing: 1
                        Repeater {
                            model: [
                                { label: "Start\nExploring",   action: "start",         icon: "resume.png",         btnWidth: 88 },
                                { label: "Stop\nExploring",    action: "stop",          icon: "pause.png",          btnWidth: 88 },
                                { label: "Start\nDownloading", action: "download",      icon: "arrow_down.png",     btnWidth: 96 },
                                { label: "Stop\nDownloads",    action: "stopDownloads", icon: "pause_orange.png",   btnWidth: 88 },
                                { label: "Update\nAll",        action: "update",        icon: "update.png",         btnWidth: 80 },
                                { label: "Schedule\nProject",  action: "schedule",      icon: "clock.png",          btnWidth: 88 },
                                { label: "Statistics",         action: "stats",         icon: "about.ico",          btnWidth: 84 }
                            ]
                            delegate: ToolbarBtn {
                                label: modelData.label
                                iconSrc: "icons/" + modelData.icon
                                iconSize: 26
                                width: modelData.btnWidth
                                height: 60
                                enabled: {
                                    if (modelData.action === "stop") return App.grabberBusy
                                    if (modelData.action === "schedule" || modelData.action === "stats" || modelData.action === "update")
                                        return root.projectId.length > 0
                                    return true
                                }
                                background: Rectangle {
                                    color: parent.pressed ? "#1e3a6e"
                                         : parent.hovered ? "#2a2a3a"
                                         : "transparent"
                                    radius: 2
                                    // Bottom accent line on hover
                                    Rectangle {
                                        visible: parent.parent.hovered || parent.parent.pressed
                                        anchors.bottom: parent.bottom
                                        anchors.left: parent.left; anchors.right: parent.right
                                        height: 2
                                        color: parent.parent.pressed ? "#4488dd" : "#334466"
                                        radius: 0
                                    }
                                }
                                onClicked: {
                                    var project = root.projectData()
                                    if (modelData.action === "start" || modelData.action === "update")
                                        App.runGrabber(project)
                                    else if (modelData.action === "stop")
                                        App.cancelGrabber()
                                    else if (modelData.action === "download") {
                                        root.actionTaken = true
                                        App.downloadGrabberResults(root.projectId, true)
                                        root.filesAddedToDownloadList()
                                    } else if (modelData.action === "stopDownloads")
                                        App.stopGrabberResultDownloads(root.projectId)
                                    else if (modelData.action === "queue")
                                        root.queueAssignmentRequested(root.projectId)
                                    else if (modelData.action === "schedule")
                                        root.scheduleRequested(root.projectId)
                                    else if (modelData.action === "stats")
                                        root.statisticsRequested(root.projectId)
                                }
                            }
                        }
                    }
                }
            }

            // ── Main content: sidebar + file list ────────────────────────────
            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 0

                // ── Sidebar ───────────────────────────────────────────────────
                Rectangle {
                    Layout.preferredWidth: 198
                    Layout.fillHeight: true
                    color: "#1b1b1b"

                    // "Categories" header bar
                    Rectangle {
                        id: sideHeader
                        anchors { top: parent.top; left: parent.left; right: parent.right }
                        height: 26
                        color: "#252525"

                        // Left accent
                        Rectangle { width: 3; height: parent.height; color: "#4488dd" }

                        Text {
                            anchors { verticalCenter: parent.verticalCenter; left: parent.left; leftMargin: 10 }
                            text: "Categories"
                            color: "#c8c8c8"
                            font.pixelSize: 11
                            font.bold: true
                        }
                        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: "#333333" }
                    }

                    Rectangle {
                        anchors { top: sideHeader.bottom; left: parent.left; right: parent.right; bottom: parent.bottom }
                        color: "#1b1b1b"

                        ScrollView {
                            anchors.fill: parent
                            clip: true
                            ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
                            ScrollBar.vertical.policy: ScrollBar.AsNeeded

                            Column {
                                id: sidebarColumn
                                width: 198
                                spacing: 0

                                // ── All Files ─────────────────────────────────
                                Rectangle {
                                    width: sidebarColumn.width
                                    height: 26
                                    color: sideMode === "all" ? "#1e3a6e" : (allFilesHover.containsMouse ? "#232330" : "transparent")

                                    // Selected left indicator
                                    Rectangle {
                                        visible: sideMode === "all"
                                        anchors { top: parent.top; bottom: parent.bottom; left: parent.left }
                                        width: 2; color: "#4488dd"
                                    }

                                    Row {
                                        anchors { verticalCenter: parent.verticalCenter; left: parent.left; leftMargin: 8 }
                                        spacing: 5

                                        Image {
                                            source: "icons/downloads.ico"
                                            width: 14; height: 14
                                            sourceSize.width: 14; sourceSize.height: 14
                                            fillMode: Image.PreserveAspectFit
                                            smooth: true; mipmap: true
                                            anchors.verticalCenter: parent.verticalCenter
                                        }
                                        Text {
                                            text: "All Files"
                                            color: sideMode === "all" ? "#88bbff" : "#b8b8b8"
                                            font.pixelSize: 12
                                            font.bold: sideMode === "all"
                                            anchors.verticalCenter: parent.verticalCenter
                                        }
                                    }

                                    HoverHandler { id: allFilesHover }
                                    MouseArea {
                                        anchors.fill: parent
                                        onClicked: { root.sideMode = "all"; root.sideFilterValue = "" }
                                    }
                                }

                                // ── Link View section header ──────────────────
                                Rectangle {
                                    width: sidebarColumn.width
                                    height: 24
                                    color: "#212126"

                                    Row {
                                        anchors { verticalCenter: parent.verticalCenter; left: parent.left; leftMargin: 8 }
                                        spacing: 5
                                        Text {
                                            text: isSectionExpanded("link") ? "▾" : "▸"
                                            color: "#6677aa"; font.pixelSize: 11; width: 12
                                            anchors.verticalCenter: parent.verticalCenter
                                        }
                                        Image {
                                            source: "icons/cloud_copylink.ico"
                                            width: 14; height: 14
                                            sourceSize.width: 14; sourceSize.height: 14
                                            fillMode: Image.PreserveAspectFit
                                            smooth: true; mipmap: true
                                            anchors.verticalCenter: parent.verticalCenter
                                        }
                                        Text {
                                            text: "Link View"
                                            color: "#8899aa"
                                            font.pixelSize: 10
                                            font.bold: true
                                            font.capitalization: Font.AllUppercase
                                            anchors.verticalCenter: parent.verticalCenter
                                        }
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        onClicked: {
                                            setSectionExpanded("link", !isSectionExpanded("link"))
                                            root.rebuildSidebarTrees()
                                        }
                                    }
                                    Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: "#2a2a2a" }
                                }

                                // ── Link View items ───────────────────────────
                                Repeater {
                                    model: root._linkItems
                                    delegate: Rectangle {
                                        required property var modelData
                                        property bool isSelected: sideMode === "link" && sideFilterValue === modelData.id
                                        width: sidebarColumn.width
                                        height: 25
                                        color: isSelected ? "#1e3a6e" : (linkItemHover.containsMouse ? "#232330" : "transparent")

                                        Rectangle {
                                            visible: isSelected
                                            anchors { top: parent.top; bottom: parent.bottom; left: parent.left }
                                            width: 2; color: "#4488dd"
                                        }

                                        Row {
                                            anchors { verticalCenter: parent.verticalCenter; left: parent.left; leftMargin: 10 + modelData.depth * 14 }
                                            spacing: 4
                                            Text {
                                                width: 12
                                                text: modelData.isDomain && modelData.hasChildren
                                                      ? (modelData.isExpanded ? "▾" : "▸") : ""
                                                color: "#6677aa"; font.pixelSize: 11
                                                horizontalAlignment: Text.AlignHCenter
                                                anchors.verticalCenter: parent.verticalCenter
                                            }
                                            Image {
                                                source: modelData.isDomain ? "icons/globe.png" : "icons/page.ico"
                                                width: 14; height: 14
                                                sourceSize.width: 14; sourceSize.height: 14
                                                fillMode: Image.PreserveAspectFit
                                                smooth: true; mipmap: true
                                                anchors.verticalCenter: parent.verticalCenter
                                            }
                                            Text {
                                                text: modelData.label
                                                color: isSelected ? "#88bbff" : "#b0b8c4"
                                                font.pixelSize: 11
                                                font.bold: modelData.isDomain
                                                elide: Text.ElideRight
                                                width: sidebarColumn.width - (10 + modelData.depth * 14 + 12 + 14 + 12)
                                                anchors.verticalCenter: parent.verticalCenter
                                            }
                                        }

                                        HoverHandler { id: linkItemHover }
                                        MouseArea {
                                            anchors.fill: parent
                                            onClicked: {
                                                root.sideMode = "link"
                                                root.sideFilterValue = modelData.id
                                            }
                                            onDoubleClicked: {
                                                if (modelData.isDomain && modelData.hasChildren) {
                                                    root.setLinkNodeExpanded(modelData.id, !modelData.isExpanded)
                                                    root.rebuildSidebarTrees()
                                                }
                                            }
                                        }
                                    }
                                }

                                // ── Folder View section header ─────────────────
                                Rectangle {
                                    width: sidebarColumn.width
                                    height: 24
                                    color: "#212126"

                                    Row {
                                        anchors { verticalCenter: parent.verticalCenter; left: parent.left; leftMargin: 8 }
                                        spacing: 5
                                        Text {
                                            text: isSectionExpanded("folder") ? "▾" : "▸"
                                            color: "#6677aa"; font.pixelSize: 11; width: 12
                                            anchors.verticalCenter: parent.verticalCenter
                                        }
                                        Image {
                                            source: "icons/folder_view.ico"
                                            width: 14; height: 14
                                            sourceSize.width: 14; sourceSize.height: 14
                                            fillMode: Image.PreserveAspectFit
                                            smooth: true; mipmap: true
                                            anchors.verticalCenter: parent.verticalCenter
                                        }
                                        Text {
                                            text: "Folder View"
                                            color: "#8899aa"
                                            font.pixelSize: 10
                                            font.bold: true
                                            font.capitalization: Font.AllUppercase
                                            anchors.verticalCenter: parent.verticalCenter
                                        }
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        onClicked: {
                                            setSectionExpanded("folder", !isSectionExpanded("folder"))
                                            root.rebuildSidebarTrees()
                                        }
                                    }
                                    Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: "#2a2a2a" }
                                }

                                // ── Folder View items ─────────────────────────
                                Repeater {
                                    model: root._folderItems
                                    delegate: Rectangle {
                                        required property var modelData
                                        property bool isSelected: sideMode === "folder" && sideFilterValue === modelData.id
                                        width: sidebarColumn.width
                                        height: 25
                                        color: isSelected ? "#1e3a6e" : (folderItemHover.containsMouse ? "#232330" : "transparent")

                                        Rectangle {
                                            visible: isSelected
                                            anchors { top: parent.top; bottom: parent.bottom; left: parent.left }
                                            width: 2; color: "#4488dd"
                                        }

                                        Row {
                                            anchors { verticalCenter: parent.verticalCenter; left: parent.left; leftMargin: 10 + modelData.depth * 14 }
                                            spacing: 4
                                            Text {
                                                width: 12
                                                text: modelData.hasChildren
                                                      ? (root.isFolderExpanded(modelData.id) ? "▾" : "▸") : ""
                                                color: "#6677aa"; font.pixelSize: 11
                                                horizontalAlignment: Text.AlignHCenter
                                                anchors.verticalCenter: parent.verticalCenter
                                            }
                                            Image {
                                                source: "icons/folder.ico"
                                                width: 14; height: 14
                                                sourceSize.width: 14; sourceSize.height: 14
                                                fillMode: Image.PreserveAspectFit
                                                smooth: true; mipmap: true
                                                anchors.verticalCenter: parent.verticalCenter
                                            }
                                            Text {
                                                text: modelData.label
                                                color: isSelected ? "#88bbff" : "#b0b8c4"
                                                font.pixelSize: 11
                                                font.bold: modelData.depth === 0
                                                elide: Text.ElideRight
                                                width: sidebarColumn.width - (10 + modelData.depth * 14 + 12 + 14 + 12)
                                                anchors.verticalCenter: parent.verticalCenter
                                            }
                                        }

                                        HoverHandler { id: folderItemHover }
                                        MouseArea {
                                            anchors.fill: parent
                                            onClicked: {
                                                root.sideMode = "folder"
                                                root.sideFilterValue = modelData.id
                                            }
                                            onDoubleClicked: {
                                                if (modelData.hasChildren) {
                                                    root.setFolderExpanded(modelData.id, !root.isFolderExpanded(modelData.id))
                                                    root.rebuildSidebarTrees()
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Right border separator
                    Rectangle {
                        anchors { top: parent.top; bottom: parent.bottom; right: parent.right }
                        width: 1
                        color: "#2d2d2d"
                    }
                }

                // ── File list ─────────────────────────────────────────────────
                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    Flickable {
                        id: tableFlick
                        anchors.fill: parent
                        clip: true
                        contentWidth: Math.max(width, totalColumnWidth())
                        contentHeight: height
                        boundsBehavior: Flickable.StopAtBounds
                        flickableDirection: Flickable.HorizontalFlick

                        ScrollBar.horizontal: ScrollBar { policy: ScrollBar.AsNeeded }
                        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AlwaysOff }

                        // ── Column headers ────────────────────────────────────
                        Rectangle {
                            id: headerRow
                            x: 0; y: 0
                            width: tableFlick.contentWidth
                            height: 26
                            color: "#252525"

                            Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: "#333333" }

                            Row {
                                anchors.fill: parent
                                spacing: 0

                                Repeater {
                                    model: root.columnDefs
                                    delegate: Rectangle {
                                        required property var modelData
                                        property real dragStartWidth: 0
                                        width: root.columnWidth(modelData.key)
                                        height: parent.height
                                        readonly property bool isSortable: modelData.key !== "check"
                                        color: (isSortable && headerCellMouse.containsMouse) ? "#2a2a36" : "transparent"

                                        Item {
                                            anchors.fill: parent
                                            visible: modelData.key === "check"
                                            CheckBox {
                                                anchors.centerIn: parent
                                                checked: root.allRowsChecked()
                                                topPadding: 0; bottomPadding: 0
                                                onToggled: root.toggleAllChecked(checked)
                                            }
                                        }

                                        Text {
                                            anchors.verticalCenter: parent.verticalCenter
                                            anchors.left: parent.left; anchors.leftMargin: 8
                                            visible: modelData.key !== "check"
                                            text: modelData.title + root.sortIndicator(modelData.key)
                                            color: root.sortColumn === modelData.key ? "#6699cc" : "#888899"
                                            font.bold: true; font.pixelSize: 11
                                        }

                                        MouseArea {
                                            id: headerCellMouse
                                            anchors.fill: parent
                                            anchors.rightMargin: modelData.key === "check" ? 0 : 10
                                            enabled: modelData.key !== "check"
                                            hoverEnabled: true
                                            cursorShape: modelData.key !== "check" ? Qt.PointingHandCursor : Qt.ArrowCursor
                                            onClicked: root.sortBy(modelData.key)
                                        }

                                        Rectangle {
                                            anchors.top: parent.top; anchors.bottom: parent.bottom; anchors.right: parent.right
                                            width: 1
                                            color: resizeHover.hovered || resizeDrag.active || root.resizingColumnKey === modelData.key
                                                   ? "#4488dd" : "#323232"
                                        }

                                        HoverHandler { id: resizeHover; cursorShape: modelData.key === "check" ? Qt.ArrowCursor : Qt.SizeHorCursor }

                                        DragHandler {
                                            id: resizeDrag
                                            enabled: modelData.key !== "check"
                                            target: null; xAxis.enabled: true; yAxis.enabled: false
                                            onActiveChanged: {
                                                if (active) {
                                                    dragStartWidth = root.columnWidth(modelData.key)
                                                    root.resizingColumnKey = modelData.key
                                                    root.resizingColumnWidth = dragStartWidth
                                                } else if (root.resizingColumnKey === modelData.key) {
                                                    root.setColumnWidth(modelData.key, root.resizingColumnWidth)
                                                    root.resizingColumnKey = ""
                                                }
                                            }
                                            onTranslationChanged: {
                                                if (!active) return
                                                root.resizingColumnWidth = Math.max(
                                                    modelData.key === "check" ? 34 : 60, dragStartWidth + translation.x)
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // ── Rows ──────────────────────────────────────────────
                        ListView {
                            id: resultsList
                            x: 0
                            y: headerRow.height
                            width: tableFlick.contentWidth
                            height: Math.max(0, tableFlick.height - headerRow.height)
                            clip: true
                            interactive: true
                            model: App.grabberResultModel
                            boundsBehavior: Flickable.StopAtBounds
                            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                            delegate: Rectangle {
                                required property int index
                                required property bool resultChecked
                                required property string filename
                                required property string url
                                required property string sizeText
                                required property string sourcePage

                                property bool rowVisible: rowMatchesSideFilter(url, sourcePage)
                                width: tableFlick.contentWidth
                                height: rowVisible ? 26 : 0
                                visible: height > 0
                                color: root.isRowSelected(index) ? "#1e3250"
                                     : rowMouse.containsMouse ? "#222230"
                                     : index % 2 === 0 ? "#1c1c1c" : "#202024"

                                // Selected left indicator
                                Rectangle {
                                    visible: root.isRowSelected(index)
                                    anchors { top: parent.top; bottom: parent.bottom; left: parent.left }
                                    width: 2; color: "#4488dd"
                                }

                                // rowMouse is declared before Row so it has lower z-order.
                                // This allows the CheckBox and other Row children (higher z)
                                // to receive clicks first; unhandled clicks fall through to rowMouse.
                                MouseArea {
                                    id: rowMouse
                                    anchors.fill: parent
                                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                                    hoverEnabled: true
                                    onClicked: function(mouse) {
                                        if (mouse.button === Qt.RightButton) {
                                            if (!root.isRowSelected(index)) { root.clearAndSelect(index); root.anchorRow = index }
                                            resultsContextMenu.popup()
                                            return
                                        }
                                        if (mouse.modifiers & Qt.ControlModifier) {
                                            root.toggleRow(index); root.anchorRow = index
                                        } else if (mouse.modifiers & Qt.ShiftModifier) {
                                            if (root.anchorRow >= 0) root.addRangeTo(root.anchorRow, index)
                                            else { root.clearAndSelect(index); root.anchorRow = index }
                                        } else {
                                            root.clearAndSelect(index); root.anchorRow = index
                                        }
                                    }
                                }

                                Row {
                                    anchors.fill: parent
                                    spacing: 0

                                    Item {
                                        width: root.columnWidth("check"); height: parent.height
                                        CheckBox {
                                            anchors.centerIn: parent
                                            checked: resultChecked
                                            topPadding: 0; bottomPadding: 0
                                            onToggled: App.setGrabberResultChecked(index, checked)
                                        }
                                    }
                                    Text { width: root.columnWidth("filename"); height: parent.height; leftPadding: 8; verticalAlignment: Text.AlignVCenter; text: filename; color: root.isRowSelected(index) ? "#e8e8ff" : "#d0d0d0"; elide: Text.ElideRight; font.pixelSize: 12 }
                                    Text { width: root.columnWidth("filetype"); height: parent.height; leftPadding: 8; verticalAlignment: Text.AlignVCenter; text: fileTypeLabel(filename, url); color: root.isRowSelected(index) ? "#aabbcc" : "#6e7a88"; elide: Text.ElideRight; font.pixelSize: 11 }
                                    Text { width: root.columnWidth("size"); height: parent.height; leftPadding: 8; verticalAlignment: Text.AlignVCenter; text: sizeText; color: root.isRowSelected(index) ? "#c8d8e8" : "#7a8898"; font.pixelSize: 11 }
                                    Text {
                                        width: root.columnWidth("status"); height: parent.height; leftPadding: 8; verticalAlignment: Text.AlignVCenter
                                        property string statusVal: computeStatus(url)
                                        text: statusVal
                                        color: root.isRowSelected(index) ? "#e0e8ff"
                                             : statusVal === "Ready" ? "#55bb77"
                                             : statusVal === "Already in list" ? "#bb9944" : "#667788"
                                        elide: Text.ElideRight; font.pixelSize: 11
                                    }
                                    Text { width: root.columnWidth("linktext"); height: parent.height; leftPadding: 8; verticalAlignment: Text.AlignVCenter; text: baseHost(sourcePage.length > 0 ? sourcePage : url); color: root.isRowSelected(index) ? "#aabbcc" : "#6e7a88"; elide: Text.ElideRight; font.pixelSize: 11 }
                                    Text { width: root.columnWidth("downloadfrom"); height: parent.height; leftPadding: 8; verticalAlignment: Text.AlignVCenter; text: url; color: root.isRowSelected(index) ? "#88aadd" : "#445577"; elide: Text.ElideMiddle; font.pixelSize: 11 }
                                    Text { width: root.columnWidth("saveto"); height: parent.height; leftPadding: 8; verticalAlignment: Text.AlignVCenter; text: saveToText(filename); color: root.isRowSelected(index) ? "#aabbcc" : "#556677"; elide: Text.ElideMiddle; font.pixelSize: 11 }
                                }

                                Rectangle {
                                    anchors.bottom: parent.bottom; width: parent.width; height: 1; color: "#252525"
                                }
                            }
                        }

                        // ── Empty state ───────────────────────────────────────
                        Column {
                            x: (tableFlick.width - width) / 2
                            y: headerRow.height + (tableFlick.height - headerRow.height - height) / 2
                            spacing: 6
                            visible: root.totalCount === 0

                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: "No files found yet"
                                color: "#4a4a5a"; font.pixelSize: 14; font.bold: true
                            }
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: App.grabberBusy ? "Exploring…" : "Press Start Exploring to scan the URL."
                                color: "#3a3a4a"; font.pixelSize: 11
                            }
                        }
                    }
                }
            }

            // ── Bottom bar ────────────────────────────────────────────────────
            Rectangle {
                Layout.fillWidth: true
                height: 42
                color: "#222228"

                Rectangle { anchors.top: parent.top; width: parent.width; height: 1; color: "#2d2d36" }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 10
                    spacing: 8

                    DlgButton {
                        text: "← Back"
                        onClicked: root.editProjectRequested(root.projectId)
                    }

                    // Subtle file count pill
                    Rectangle {
                        visible: totalCount > 0
                        height: 18; radius: 3
                        color: "#1a1a28"
                        border.color: "#2a2a40"
                        width: countLabel.implicitWidth + 14

                        Text {
                            id: countLabel
                            anchors.centerIn: parent
                            color: "#556677"
                            font.pixelSize: 10
                            text: {
                                var visible = visibleRowCount()
                                return visible === totalCount
                                    ? totalCount + " files"
                                    : visible + " / " + totalCount + " (filtered)"
                            }
                        }
                    }

                    Item { Layout.fillWidth: true }

                    DlgButton {
                        text: "Add checked to download list"
                        enabled: checkedCount > 0
                        onClicked: root.queueAssignmentRequested(root.projectId)
                    }
                    DlgButton {
                        text: "Close"
                        primary: true
                        onClicked: root.close()
                    }
                }
            }
        }
    }
}
