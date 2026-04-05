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
import com.stellar.app 1.0

ApplicationWindow {
    id: root
    visible: true
    width: 1100
    height: 680
    minimumWidth: 800
    minimumHeight: 500
    title: "Stellar Download Manager " + App.appVersion

    Material.theme: Material.Dark
    Material.background: "#1c1c1c"
    Material.primary: "#2d2d2d"
    Material.accent: "#5588cc"

    // ── Minimize to tray on close ─────────────────────────────────────────────
    property bool isQuitting: false

    onClosing: (close) => {
        if (!isQuitting && App.settings.closeToTray) {
            close.accepted = false
            root.hide()
        }
    }

    function quitApp() {
        isQuitting = true
        Qt.quit()
    }

    // ── Tray context menu (standalone window so it works when main window is hidden) ──
    Window {
        id: trayMenu
        flags: Qt.Tool | Qt.FramelessWindowHint | Qt.WindowStaysOnTopHint
        width: 180
        height: menuCol.implicitHeight + 2
        color: "#2b2b2b"
        visible: false

        function popup(screenX, screenY) {
            x = screenX
            y = screenY - height
            visible = true
            raise()
            requestActivate()
        }

        onActiveChanged: {
            if (!active && visible) visible = false
        }

        Rectangle {
            anchors.fill: parent
            color: "transparent"
            border.color: "#555"
            border.width: 1
        }

        Column {
            id: menuCol
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 1 }

            TrayMenuItem { label: "Open Stellar"; bold: true; onClicked: { trayMenu.visible = false; root.show(); root.raise(); root.requestActivate() } }
            TrayMenuItem { label: "Add URL…";     onClicked: { trayMenu.visible = false; root.show(); root.raise(); addUrlDialog.show(); addUrlDialog.raise() } }
            Rectangle { width: parent.width; height: 1; color: "#444" }
            TrayMenuItem { label: "GitHub";        onClicked: { trayMenu.visible = false; Qt.openUrlExternally("https://github.com/Ninka-Rex/Stellar") } }
            TrayMenuItem { label: "About Stellar"; onClicked: { trayMenu.visible = false; root.show(); root.raise(); settingsDialog.initialPage = 7; settingsDialog.show(); settingsDialog.raise() } }
            Rectangle { width: parent.width; height: 1; color: "#444" }
            TrayMenuItem { label: "Speed Limiter"; onClicked: { trayMenu.visible = false; root.show(); root.raise(); settingsDialog.initialPage = 4; settingsDialog.show(); settingsDialog.raise() } }
            Rectangle { width: parent.width; height: 1; color: "#444" }
            TrayMenuItem { label: "Exit Stellar";  onClicked: { trayMenu.visible = false; root.quitApp() } }
        }
    }

    // ── Controller signals ────────────────────────────────────────────────────
    Connections {
        target: App

        function onShowWindowRequested() {
            root.show(); root.raise(); root.requestActivate()
        }
        function onDownloadAdded(item) {
            // Don't show progress dialog for "Download Later" items (status = Paused)
            if (!item || item.status === "Paused") return
            progressDialog.item       = item
            progressDialog.downloadId = item.id
            progressDialog.show()
            progressDialog.raise()
        }
        function onDownloadCompleted(item) {
            if (progressDialog.visible && progressDialog.item === item)
                progressDialog.hide()
            // Don't show complete dialog for queue-assigned downloads
            if (!item || (item.queueId && item.queueId.length > 0))
                return
            completeDialog.item = item
            completeDialog.show()
            completeDialog.raise()
        }
        function onTrayGithubRequested() {
            Qt.openUrlExternally("https://github.com/Ninka-Rex/Stellar")
        }
        function onTrayAboutRequested() {
            root.show(); root.raise()
            settingsDialog.initialPage = 7
            settingsDialog.show(); settingsDialog.raise()
        }
        function onTraySpeedLimiterRequested() {
            root.show(); root.raise()
            settingsDialog.initialPage = 4
            settingsDialog.show(); settingsDialog.raise()
        }
        function onContextMenuRequested(x, y) {
            trayMenu.popup(x, y)
        }
        function onExceptionDialogRequested(url) {
            addExceptionDialog.url = url
            addExceptionDialog.show()
            addExceptionDialog.raise()
        }
        function onInterceptedDownloadRequested(url, filename) {
            var existing = App.findDuplicateUrl(url)
            if (existing) {
                // Already queued — just show progress or bring window forward
                if (existing.status !== "Completed" && existing.status !== "Paused") {
                    progressDialog.item       = existing
                    progressDialog.downloadId = existing.id
                    progressDialog.show(); progressDialog.raise()
                }
                return
            }
            // Firefox passes the full local save path as filename — extract basename only.
            var name = (filename.length > 0 ? filename.split(/[/\\]/).pop() : "") ||
                       url.split("/").pop().split("?")[0] || "download"
            fileInfoDialog.pendingUrl      = url
            fileInfoDialog.pendingFilename = name
            fileInfoDialog.pendingSize     = ""
            fileInfoDialog.pendingSavePath = App.settings.defaultSavePath
            fileInfoDialog.isIntercepted   = true
            fileInfoDialog.show()
            fileInfoDialog.raise()
        }
    }

    // ── Add URL dialog (step 1) ───────────────────────────────────────────────
    AddUrlDialog {
        id: addUrlDialog
        onAccepted: {
            if (url.trim().length === 0) return
            var existing = App.findDuplicateUrl(url)
            if (existing) {
                var action = App.settings.duplicateAction
                if (action === 0) {
                    // Ask the user
                    duplicateDialog.existingItem = existing
                    duplicateDialog._pendingUrl  = url
                    duplicateDialog.show()
                    duplicateDialog.raise()
                } else {
                    _handleDuplicateAction(action, false, existing, url)
                }
            } else {
                _showFileInfoDialog(url, "")
            }
        }
    }

    function _showFileInfoDialog(url, filenameOverride) {
        var filename = filenameOverride.length > 0
            ? filenameOverride
            : (url.split("/").pop().split("?")[0] || "download")
        fileInfoDialog.pendingUrl      = url
        fileInfoDialog.pendingFilename = filename
        fileInfoDialog.pendingSize     = ""
        fileInfoDialog.pendingSavePath = App.settings.defaultSavePath
        fileInfoDialog.show()
        fileInfoDialog.raise()
    }

    function _handleDuplicateAction(action, remember, existing, url) {
        if (remember) App.settings.duplicateAction = action
        if (action === 3) {
            // Resume or show complete — no file info dialog
            if (existing.status === "Completed") {
                completeDialog.item = existing
                completeDialog.show(); completeDialog.raise()
            } else {
                App.resumeDownload(existing.id)
            }
        } else if (action === 2) {
            // Overwrite: remove existing entry, then proceed to file info dialog
            App.deleteDownload(existing.id, 0)
            _showFileInfoDialog(url, "")
        } else {
            // AddNumbered: generate a unique filename, proceed to file info dialog
            var base = url.split("/").pop().split("?")[0] || "download"
            var numbered = App.generateNumberedFilename(base)
            _showFileInfoDialog(url, numbered)
        }
    }

    // ── Download File Info dialog (step 2) ────────────────────────────────────
    DownloadFileInfoDialog {
        id: fileInfoDialog
        onDownloadNow:   (url, savePath, category, desc) => App.addUrl(url, savePath, category, desc, true,  App.takePendingCookies(url))
        onDownloadLater: (url, savePath, category, desc) => App.addUrl(url, savePath, category, desc, false, App.takePendingCookies(url))
        onRejected:      (url) => App.notifyInterceptRejected(url)
    }

    // ── Duplicate Download Dialog ─────────────────────────────────────────────
    DuplicateDownloadDialog {
        id: duplicateDialog
        property string _pendingUrl: ""
        onResolved: (action, remember) => {
            _handleDuplicateAction(action, remember, existingItem, _pendingUrl)
        }
    }

    // ── Download Progress Dialog ──────────────────────────────────────────────
    DownloadProgressDialog { id: progressDialog }

    // ── Download Complete Dialog ──────────────────────────────────────────────
    DownloadCompleteDialog { id: completeDialog }

    // ── Settings / About Dialog ───────────────────────────────────────────────
    SettingsDialog { id: settingsDialog }

    // ── Scheduler Dialog ───────────────────────────────────────────────────────
    SchedulerDialog { id: schedulerDialog }

    // ── Browser Integration Dialog ────────────────────────────────────────────
    BrowserIntegrationDialog { id: browserIntegrationDialog }

    // ── Add Exception Dialog ──────────────────────────────────────────────────
    AddExceptionDialog { id: addExceptionDialog }

    // ── Tips timer and display ────────────────────────────────────────────────
    property var tipsArray: []
    property int currentTipIndex: 0

    Timer {
        id: tipsTimer
        interval: 6 * 60 * 60 * 1000  // 6 hours
        repeat: true
        onTriggered: {
            if (root.tipsArray.length > 0) {
                root.currentTipIndex = (root.currentTipIndex + 1) % root.tipsArray.length
            }
        }
    }

    Component.onCompleted: {
        // Load tips from embedded resource
        var xhr = new XMLHttpRequest()
        xhr.open("GET", "qrc:/qt/qml/com/stellar/app/tips.txt", true)
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE) {
                var text = xhr.responseText.trim()
                root.tipsArray = text.split(/\n/).filter(function(line) { return line.length > 0 })
                if (root.tipsArray.length > 0 && App.settings.showTips) {
                    tipsTimer.start()
                }
            }
        }
        xhr.send()
    }

    Connections {
        target: App.settings
        function onShowTipsChanged() {
            if (App.settings.showTips && root.tipsArray.length > 0) {
                tipsTimer.start()
            } else {
                tipsTimer.stop()
            }
        }
    }

    // ── Menu bar ──────────────────────────────────────────────────────────────
    menuBar: MenuBar {
        background: Rectangle {
            color: "#252525"
            Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: "#383838" }
        }

        delegate: MenuBarItem {
            verticalPadding: 2
            leftPadding: 8
            rightPadding: 8
            contentItem: Text {
                text: parent.text
                font: parent.font
                color: "#d0d0d0"
                verticalAlignment: Text.AlignVCenter
            }
            background: Rectangle {
                implicitHeight: 24
                implicitWidth: 40
                color: parent.highlighted ? "#1e3a6e" : "transparent"
            }
        }

        Menu {
            title: qsTr("Tasks")
            Action { text: qsTr("Add URL…");       shortcut: "Ctrl+N";       onTriggered: { addUrlDialog.show(); addUrlDialog.raise() } }
            Action { text: qsTr("Add Batch URLs…"); shortcut: "Ctrl+Shift+N" }
            MenuSeparator {}
            Action { text: qsTr("Exit");            shortcut: "Ctrl+Q";       onTriggered: root.quitApp() }
        }
        Menu {
            title: qsTr("File")
            Action { text: qsTr("Open Folder") }
            Action { text: qsTr("Open File") }
        }
        Menu {
            title: qsTr("Downloads")
            Action { text: qsTr("Resume");    shortcut: "Ctrl+R" }
            Action { text: qsTr("Pause");     shortcut: "Ctrl+P" }
            Action { text: qsTr("Stop All") }
            Action { text: qsTr("Delete");    shortcut: "Delete" }
            MenuSeparator {}

            Menu {
                title: qsTr("Start Queue")
                Repeater {
                    model: App.queueModel
                    delegate: Action {
                        text: queueName || ""
                        onTriggered: App.startQueue(queueId)
                    }
                }
            }

            Menu {
                title: qsTr("Stop Queue")
                Repeater {
                    model: App.queueModel
                    delegate: Action {
                        text: queueName || ""
                        onTriggered: App.stopQueue(queueId)
                    }
                }
            }

            MenuSeparator {}
            Action { text: qsTr("Move Up");   shortcut: "Alt+Up" }
            Action { text: qsTr("Move Down"); shortcut: "Alt+Down" }
        }
        Menu {
            title: qsTr("View")
            Action { text: qsTr("Toolbar") }
            Action { text: qsTr("Status Bar") }
            Action { text: qsTr("Categories Panel") }
        }
        Menu {
            title: qsTr("Options")
            Action { text: qsTr("Preferences…"); shortcut: "Ctrl+,"; onTriggered: settingsDialog.show() }
            Action { text: qsTr("Scheduler"); onTriggered: schedulerDialog.show() }
            Action { text: qsTr("Speed Limiter"); onTriggered: { settingsDialog.initialPage = 4; settingsDialog.show() } }
        }
        Menu {
            title: qsTr("Help")
            Action { text: qsTr("About Stellar"); onTriggered: { settingsDialog.initialPage = 7; settingsDialog.show(); settingsDialog.raise() } }
            MenuSeparator {}
            Menu {
                title: qsTr("Browser Integration")
                Action { text: qsTr("Firefox Extension…"); onTriggered: { browserIntegrationDialog.show(); browserIntegrationDialog.raise() } }
                MenuSeparator {}
                Action { text: qsTr("Open Extension Folder"); onTriggered: App.openExtensionFolder() }
                Action { text: qsTr("Browser Settings…"); onTriggered: { settingsDialog.initialPage = 3; settingsDialog.show(); settingsDialog.raise() } }
            }
        }
    }

    // ── Window-level drag proxy for category drag-and-drop ───────────────────
    // Lives outside every layout/clip so DropAreas in the sidebar can see it.
    Item {
        id: dragProxy
        width: 1; height: 1
        visible: false
        z: 9999
        Drag.active: visible
        Drag.keys: ["text/downloadId"]
        Drag.hotSpot: Qt.point(0, 0)
        property string dragDownloadId: ""
        property string dragFilename: ""
    }

    // Visual drag label — purely cosmetic, follows the proxy
    Rectangle {
        visible: dragProxy.visible
        z: 9998
        x: dragProxy.x + 10
        y: dragProxy.y + 10
        width: Math.min(dragLabelText.implicitWidth + 20, 220)
        height: 22
        radius: 3
        color: "#1e3a6e"
        border.color: "#4488dd"
        border.width: 1

        Text {
            id: dragLabelText
            anchors { verticalCenter: parent.verticalCenter; left: parent.left; leftMargin: 8; right: parent.right; rightMargin: 8 }
            text: dragProxy.dragFilename
            color: "#ffffff"
            font.pixelSize: 11
            elide: Text.ElideMiddle
        }
    }

    // ── Root layout ───────────────────────────────────────────────────────────
    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        Toolbar {
            id: toolbar
            Layout.fillWidth: true
            queueModel: App.queueModel
            onAddClicked:             { addUrlDialog.show(); addUrlDialog.raise() }
            onResumeClicked:          downloadTable.resumeSelected()
            onStopClicked:            downloadTable.stopSelected()
            onStopAllClicked:         {}
            onDeleteClicked:          downloadTable.deleteSelected()
            onDeleteCompletedClicked: {}
            onOptionsClicked:         settingsDialog.show()
            onSchedulerClicked:       schedulerDialog.show()
            onStartQueueRequested:    (queueId) => App.startQueue(queueId)
            onStopQueueRequested:     (queueId) => App.stopQueue(queueId)
            onGrabberClicked:         {}
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 0

            Sidebar {
                id: sidebar
                Layout.fillHeight: true
                Layout.preferredWidth: 188
                onCategorySelected: (catId) => App.selectedCategory = catId
            }

            DownloadTable {
                id: downloadTable
                Layout.fillWidth: true
                Layout.fillHeight: true
                categoryDragProxy: dragProxy
                onOpenProgressRequested: (item) => {
                    progressDialog.item       = item
                    progressDialog.downloadId = item ? item.id : ""
                    progressDialog.show()
                    progressDialog.raise()
                }
            }
        }

        StatusBar {
            Layout.fillWidth: true
            activeCount: App.activeDownloads
        }
    }

    // ── Tip of the day (bottom right) ──────────────────────────────────────────
    Rectangle {
        visible: App.settings.showTips && root.tipsArray.length > 0
        anchors { bottom: parent.bottom; right: parent.right; margins: 12 }
        width: Math.min(280, root.width - 40)
        height: tipText.implicitHeight + 12
        color: "transparent"

        Text {
            id: tipText
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 6 }
            text: root.tipsArray.length > root.currentTipIndex ? root.tipsArray[root.currentTipIndex] : ""
            color: "#666666"
            font.pixelSize: 10
            wrapMode: Text.WordWrap
        }
    }
}
