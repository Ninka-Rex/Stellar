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
    property bool isQuitting:    false
    property bool findBarActive: false

    function closeFindBar() {
        findBarActive = false
        downloadTable.clearFilter()
    }

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
            TrayMenuItem { label: (App.settings.globalSpeedLimitKBps > 0 ? "✓ " : "") + "Speed Limiter: Turn On";  onClicked: { trayMenu.visible = false; App.enableSpeedLimiter() } }
            TrayMenuItem { label: (App.settings.globalSpeedLimitKBps === 0 ? "✓ " : "") + "Speed Limiter: Turn Off"; onClicked: { trayMenu.visible = false; App.disableSpeedLimiter() } }
            TrayMenuItem { label: "Speed Limiter Settings…"; onClicked: { trayMenu.visible = false; root.show(); root.raise(); settingsDialog.initialPage = 4; settingsDialog.show(); settingsDialog.raise() } }
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
            // Store auth credentials for step 2
            root._pendingUsername = useAuth ? username : ""
            root._pendingPassword = useAuth ? password : ""
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

    // Pending auth from AddUrlDialog step 1
    property string _pendingUsername: ""
    property string _pendingPassword: ""

    // ── Download File Info dialog (step 2) ────────────────────────────────────
    DownloadFileInfoDialog {
        id: fileInfoDialog
        onDownloadNow:   (url, savePath, category, desc) => App.addUrl(url, savePath, category, desc, true,  App.takePendingCookies(url), App.takePendingReferrer(url), App.takePendingPageUrl(url), root._pendingUsername, root._pendingPassword)
        onDownloadLater: (url, savePath, category, desc) => App.addUrl(url, savePath, category, desc, false, App.takePendingCookies(url), App.takePendingReferrer(url), App.takePendingPageUrl(url), root._pendingUsername, root._pendingPassword)
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

    // ── Delete Done Confirm Dialog ────────────────────────────────────────────
    DeleteDoneConfirmDialog {
        id: deleteDoneConfirmDialog
        onConfirmed: App.deleteAllCompleted(0)
    }

    // ── File Properties Dialog ────────────────────────────────────────────────
    FilePropertiesDialog { id: filePropertiesDialog }

// ── Columns Dialog ────────────────────────────────────────────────────────
    ColumnsDialog {
        id: columnsDialog
        onColumnsChanged: (defs) => {
            if (defs === null) {
                downloadTable.resetColumns()
            } else {
                downloadTable.columnDefs = defs
            }
        }
    }

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
            Action { text: qsTr("Pause all");  shortcut: "Ctrl+P"; onTriggered: downloadTable.pauseAll() }
            Action { text: qsTr("Stop all");   onTriggered: downloadTable.pauseAll() }
            MenuSeparator {}
            Action { text: qsTr("Delete all completed"); onTriggered: { deleteDoneConfirmDialog.show(); deleteDoneConfirmDialog.raise() } }
            MenuSeparator {}
            Action { text: qsTr("Find…");      shortcut: "Ctrl+F"; onTriggered: { root.findBarActive = true; findBarField.forceActiveFocus() } }
            Action { text: qsTr("Find Next");  shortcut: "F3";     onTriggered: downloadTable.findNextFiltered() }
            MenuSeparator {}
            Action { text: qsTr("Scheduler");  onTriggered: schedulerDialog.show() }
            Menu {
                title: qsTr("Start Queue")
                Repeater {
                    model: App.queueModel
                    delegate: Action { text: queueName || ""; onTriggered: App.startQueue(queueId) }
                }
            }
            Menu {
                title: qsTr("Stop Queue")
                Repeater {
                    model: App.queueModel
                    delegate: Action { text: queueName || ""; onTriggered: App.stopQueue(queueId) }
                }
            }
            MenuSeparator {}
            Menu {
                title: qsTr("Speed Limiter")
                Action { text: (App.settings.globalSpeedLimitKBps > 0 ? "✓ " : "    ") + qsTr("Turn On");  onTriggered: App.enableSpeedLimiter() }
                Action { text: (App.settings.globalSpeedLimitKBps === 0 ? "✓ " : "    ") + qsTr("Turn Off"); onTriggered: App.disableSpeedLimiter() }
                MenuSeparator {}
                Action { text: qsTr("Settings…"); onTriggered: { settingsDialog.initialPage = 4; settingsDialog.show() } }
            }
            MenuSeparator {}
            Action { text: qsTr("Options…"); shortcut: "Ctrl+,"; onTriggered: settingsDialog.show() }
        }
        Menu {
            title: qsTr("View")
            Action {
                text: sidebar.visible ? qsTr("Hide Categories") : qsTr("Show Categories")
                onTriggered: sidebar.visible = !sidebar.visible
            }
            MenuSeparator {}
            Menu {
                title: qsTr("Arrange Files")
                Action { text: qsTr("By Order Of Addition");  onTriggered: App.sortDownloads("added",      true) }
                Action { text: qsTr("By File Name");          onTriggered: App.sortDownloads("name",       true) }
                Action { text: qsTr("By Size");               onTriggered: App.sortDownloads("size",       true) }
                Action { text: qsTr("By Status");             onTriggered: App.sortDownloads("status",     true) }
                Action { text: qsTr("By Time Left");          onTriggered: App.sortDownloads("timeleft",   true) }
                Action { text: qsTr("By Transfer Rate");      onTriggered: App.sortDownloads("speed",      false) }
                Action { text: qsTr("By Last Try Date");      onTriggered: App.sortDownloads("lasttry",    false) }
                Action { text: qsTr("By Description");        onTriggered: App.sortDownloads("description",true) }
                Action { text: qsTr("By Save Path");          onTriggered: App.sortDownloads("saveto",     true) }
                Action { text: qsTr("By Referer");            onTriggered: App.sortDownloads("referrer",   true) }
                Action { text: qsTr("By Parent Web Page");    onTriggered: App.sortDownloads("parenturl",  true) }
            }
            MenuSeparator {}
            Action { text: qsTr("Columns…"); onTriggered: {
                columnsDialog.columnDefs = downloadTable.columnDefs.slice()
                columnsDialog.show()
                columnsDialog.raise()
            }}
        }
        Menu {
            title: qsTr("Options")
            Action { text: qsTr("Preferences…"); shortcut: "Ctrl+,"; onTriggered: settingsDialog.show() }
            Action { text: qsTr("Scheduler");    onTriggered: schedulerDialog.show() }
            Menu {
                title: qsTr("Speed Limiter")
                Action { text: (App.settings.globalSpeedLimitKBps > 0 ? "✓ " : "    ") + qsTr("Turn On");  onTriggered: App.enableSpeedLimiter() }
                Action { text: (App.settings.globalSpeedLimitKBps === 0 ? "✓ " : "    ") + qsTr("Turn Off"); onTriggered: App.disableSpeedLimiter() }
                MenuSeparator {}
                Action { text: qsTr("Settings…"); onTriggered: { settingsDialog.initialPage = 4; settingsDialog.show() } }
            }
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
            onStopAllClicked:         App.pauseAllDownloads()
            onDeleteClicked:          downloadTable.deleteSelected()
            onDeleteCompletedClicked: { deleteDoneConfirmDialog.show(); deleteDoneConfirmDialog.raise() }
            onOptionsClicked:         settingsDialog.show()
            onSchedulerClicked:       schedulerDialog.show()
            onStartQueueRequested:    (queueId) => App.startQueue(queueId)
            onStopQueueRequested:     (queueId) => App.stopQueue(queueId)
            onGrabberClicked:         {}
        }

        // ── Inline Find Bar ───────────────────────────────────────────────────
        Rectangle {
            id: findBar
            Layout.fillWidth: true
            height: 36
            visible: root.findBarActive
            color: "#1e2030"
            border.color: "#3a3a55"
            border.width: 0

            // Top separator line
            Rectangle { anchors.top: parent.top; width: parent.width; height: 1; color: "#3a3a55" }

            // Escape to close
            Keys.onEscapePressed: root.closeFindBar()

            RowLayout {
                anchors { fill: parent; leftMargin: 8; rightMargin: 6; topMargin: 0; bottomMargin: 0 }
                spacing: 6

                Text {
                    text: "Find:"
                    color: "#9090a0"
                    font.pixelSize: 12
                    verticalAlignment: Text.AlignVCenter
                    Layout.alignment: Qt.AlignVCenter
                }

                TextField {
                    id: findBarField
                    Layout.fillWidth: true
                    implicitHeight: 24
                    font.pixelSize: 12
                    color: "#d0d0d0"
                    background: Rectangle { color: "#2a2a3a"; border.color: "#4a4a6a"; radius: 3 }
                    leftPadding: 6

                    Keys.onEscapePressed: root.closeFindBar()
                    Keys.onReturnPressed: downloadTable.findNextFiltered()
                    Keys.onEnterPressed:  downloadTable.findNextFiltered()

                    onTextChanged: {
                        downloadTable.filterText = text
                        downloadTable._findRow = -1
                        if (text.length > 0) downloadTable.findFirstFiltered()
                    }
                }

                // Result count
                Text {
                    id: findCountLabel
                    readonly property int cnt: downloadTable.filterText.length > 0
                        ? downloadTable.countMatches(downloadTable.filterText, downloadTable.filterName,
                                                     downloadTable.filterDesc, downloadTable.filterLinks,
                                                     downloadTable.filterMatchCase, downloadTable.filterMatchWhole)
                        : -1
                    text: cnt < 0 ? "" : (cnt === 0 ? "No results" : cnt + " found")
                    color: cnt === 0 ? "#cc6666" : "#66bb88"
                    font.pixelSize: 11
                    Layout.alignment: Qt.AlignVCenter
                    visible: downloadTable.filterText.length > 0
                }

                // Find button
                Rectangle {
                    implicitWidth: 46; implicitHeight: 24; radius: 3
                    color: findBtnMa.containsMouse ? "#2a5faa" : "#1e3a6e"
                    border.color: "#4488dd"; border.width: 1
                    Layout.alignment: Qt.AlignVCenter
                    Text { anchors.centerIn: parent; text: "Find"; color: "#ffffff"; font.pixelSize: 12; font.bold: true }
                    MouseArea {
                        id: findBtnMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: downloadTable.findNextFiltered()
                    }
                }

                // Settings button
                Rectangle {
                    id: findSettingsBtn
                    implicitWidth: 68; implicitHeight: 24; radius: 3
                    color: findSettingsMa.containsMouse ? "#333345" : "#28283a"
                    border.color: "#4a4a6a"; border.width: 1
                    Layout.alignment: Qt.AlignVCenter
                    Text { anchors.centerIn: parent; text: "Settings ▾"; color: "#b0b0c0"; font.pixelSize: 11 }
                    MouseArea {
                        id: findSettingsMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: findSettingsPopup.open()
                    }

                    Popup {
                        id: findSettingsPopup
                        y: findSettingsBtn.height + 2
                        x: findSettingsBtn.width - width
                        width: 280
                        padding: 10
                        background: Rectangle { color: "#252535"; border.color: "#4a4a6a"; border.width: 1; radius: 4 }
                        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

                        ColumnLayout {
                            width: parent.width
                            spacing: 2

                            Text { text: "Search in:"; color: "#808090"; font.pixelSize: 11; bottomPadding: 2 }

                            CheckBox {
                                text: "File name or part of the name"
                                checked: downloadTable.filterName
                                topPadding: 0; bottomPadding: 0
                                onCheckedChanged: { downloadTable.filterName = checked; if (findBarField.text.length > 0) downloadTable.findFirstFiltered() }
                                contentItem: Text { text: parent.text; color: "#d0d0d0"; font.pixelSize: 12; leftPadding: parent.indicator.width + 4; verticalAlignment: Text.AlignVCenter }
                            }
                            CheckBox {
                                text: "Description"
                                checked: downloadTable.filterDesc
                                topPadding: 0; bottomPadding: 0
                                onCheckedChanged: { downloadTable.filterDesc = checked; if (findBarField.text.length > 0) downloadTable.findFirstFiltered() }
                                contentItem: Text { text: parent.text; color: "#d0d0d0"; font.pixelSize: 12; leftPadding: parent.indicator.width + 4; verticalAlignment: Text.AlignVCenter }
                            }
                            CheckBox {
                                text: "URL / referrer / parent web page"
                                checked: downloadTable.filterLinks
                                topPadding: 0; bottomPadding: 0
                                onCheckedChanged: { downloadTable.filterLinks = checked; if (findBarField.text.length > 0) downloadTable.findFirstFiltered() }
                                contentItem: Text { text: parent.text; color: "#d0d0d0"; font.pixelSize: 12; leftPadding: parent.indicator.width + 4; verticalAlignment: Text.AlignVCenter }
                            }

                            Rectangle { width: parent.width; height: 1; color: "#3a3a4a"; Layout.topMargin: 4; Layout.bottomMargin: 4 }

                            CheckBox {
                                text: "Match case"
                                checked: downloadTable.filterMatchCase
                                topPadding: 0; bottomPadding: 0
                                onCheckedChanged: { downloadTable.filterMatchCase = checked; if (findBarField.text.length > 0) downloadTable.findFirstFiltered() }
                                contentItem: Text { text: parent.text; color: "#d0d0d0"; font.pixelSize: 12; leftPadding: parent.indicator.width + 4; verticalAlignment: Text.AlignVCenter }
                            }
                            CheckBox {
                                text: "Match whole string only"
                                checked: downloadTable.filterMatchWhole
                                topPadding: 0; bottomPadding: 0
                                onCheckedChanged: { downloadTable.filterMatchWhole = checked; if (findBarField.text.length > 0) downloadTable.findFirstFiltered() }
                                contentItem: Text { text: parent.text; color: "#d0d0d0"; font.pixelSize: 12; leftPadding: parent.indicator.width + 4; verticalAlignment: Text.AlignVCenter }
                            }
                        }
                    }
                }

                // Close button
                Rectangle {
                    implicitWidth: 22; implicitHeight: 22; radius: 3
                    color: closeFindMa.containsMouse ? "#553333" : "transparent"
                    Layout.alignment: Qt.AlignVCenter
                    Text { anchors.centerIn: parent; text: "×"; color: "#a0a0a0"; font.pixelSize: 16 }
                    MouseArea {
                        id: closeFindMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.closeFindBar()
                    }
                }
            }
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
                onOpenPropertiesRequested: (item) => {
                    filePropertiesDialog.item = item
                    filePropertiesDialog.show()
                    filePropertiesDialog.raise()
                }
                onOpenColumnsSettingsRequested: {
                    columnsDialog.columnDefs = downloadTable.columnDefs.slice()
                    columnsDialog.show()
                    columnsDialog.raise()
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
