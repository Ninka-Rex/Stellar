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
import QtQuick.Dialogs
import QtQuick.Layouts
import com.stellar.app 1.0

ApplicationWindow {
    id: root
    visible: true
    width: Math.max(minimumWidth, App.settings.mainWindowWidth > 0 ? App.settings.mainWindowWidth : 1100)
    height: Math.max(minimumHeight, App.settings.mainWindowHeight > 0 ? App.settings.mainWindowHeight : 680)
    // Restore saved position; -1 means first run — let the OS centre the window naturally.
    x: App.settings.mainWindowX >= 0 ? App.settings.mainWindowX : x
    y: App.settings.mainWindowY >= 0 ? App.settings.mainWindowY : y
    minimumWidth: 800
    minimumHeight: 500
    title: {
        if (!App.settings.speedInTitleBar)
            return "Stellar Download Manager " + App.appVersion
        function fmt(bps) {
            if (bps >= 1024 * 1024)
                return (bps / (1024 * 1024)).toFixed(1) + " MB/s"
            return Math.round(bps / 1024) + " KB/s"
        }
        return "Stellar  ↓ " + fmt(App.totalDownSpeed) + "  ↑ " + fmt(App.totalUpSpeed)
    }

    Material.theme: Material.Dark
    Material.background: "#1c1c1c"
    Material.primary: "#2d2d2d"
    Material.accent: "#5588cc"

    // Set to true after the window has been shown at least once so that early
    // geometry signals during window creation don't overwrite saved position.
    property bool _geometrySaveReady: false

    // ── Minimize to tray on close ─────────────────────────────────────────────
    property bool isQuitting:    false
    property bool findBarActive: false
    property bool speedScheduleOwnsDownLimit: false
    property bool speedScheduleOwnsUpLimit: false
    property var selectedDownloadItem: downloadTable ? downloadTable._selectedItem() : null
    property int selectedTorrentCount: downloadTable ? downloadTable.selectedTorrentCountValue : 0
    property var pendingTorrentExportIds: []

    function closeFindBar() {
        findBarActive = false
        downloadTable.clearFilter()
    }

    function showSettingsPage(page) {
        settingsDialog.initialPage = page
        settingsDialog.show()
        settingsDialog.raise()
        settingsDialog.requestActivate()
    }

    function showAndActivate(win) {
        if (!win)
            return
        win.show()
        win.raise()
        win.requestActivate()
        Qt.callLater(function() {
            if (win.visible) {
                win.raise()
                win.requestActivate()
            }
        })
    }

    function showTorrentSearchWindow() {
        torrentSearchWindow.show()
        torrentSearchWindow.raise()
        torrentSearchWindow.requestActivate()
    }

    function showRssWindow() {
        rssWindow.show()
        rssWindow.raise()
        rssWindow.requestActivate()
    }

    function normalizeTorrentInput(value) {
        var trimmed = (value || "").trim()
        if (/^[0-9a-fA-F]{40}$/.test(trimmed))
            return "magnet:?xt=urn:btih:" + trimmed.toLowerCase()
        return trimmed
    }

    function torrentSaveDirFromInputPath(pathText) {
        return App.normalizeTorrentSaveDirectory(pathText || "")
    }

    function showTorrentMetadataDialog(downloadId, startWhenReady) {
        if (!downloadId || downloadId.length === 0)
            return
        torrentMetadataDialog.pendingSourceLabel = ""
        torrentMetadataDialog.downloadId = downloadId
        torrentMetadataDialog.startWhenReady = startWhenReady
        torrentMetadataDialog.show()
        torrentMetadataDialog.raise()
        torrentMetadataDialog.requestActivate()
    }

    function showTorrentMetadataDialogForFile(torrentFilePath, saveDir, category, description, startWhenReady) {
        if (!torrentFilePath || torrentFilePath.length === 0)
            return
        torrentMetadataDialog.downloadId = ""
        torrentMetadataDialog.pendingSourceLabel = torrentFilePath.split(/[/\\]/).pop()
        torrentMetadataDialog.savePath = saveDir
        torrentMetadataDialog.category = category || ""
        torrentMetadataDialog.description = description || ""
        torrentMetadataDialog.startWhenReady = startWhenReady
        Qt.callLater(function() {
            var torrentFileId = App.addTorrentFile(torrentFilePath, saveDir, category || "", description || "", false, "")
            if (!torrentFileId || torrentFileId.length === 0)
                return // duplicate — torrentDuplicateDetected signal already fired
            torrentMetadataDialog.downloadId = torrentFileId
            torrentMetadataDialog.show()
            torrentMetadataDialog.raise()
            torrentMetadataDialog.requestActivate()
        })
    }

    MessageDialog {
        id: appErrorDialog
        title: "Stellar"
        text: ""
        buttons: MessageDialog.Ok
    }

    Window {
        id: ytdlpCookieRetryDialog
        transientParent: root
        width: 480
        minimumWidth: 420
        height: 260
        minimumHeight: 240
        title: "Browser Cookies Required"
        color: "#1e1e1e"
        modality: Qt.ApplicationModal
        flags: Qt.Dialog | Qt.WindowTitleHint | Qt.WindowCloseButtonHint

        property string downloadId: ""
        property string errorReason: ""

        function _browserIndex(name) {
            var key = (name || "").toLowerCase()
            for (var i = 0; i < cookieBrowserCombo.model.length; ++i) {
                if (cookieBrowserCombo.model[i].toLowerCase() === key)
                    return i
            }
            return 0
        }

        function _openFor(downloadIdValue, reason, suggestedBrowser) {
            downloadId = downloadIdValue || ""
            errorReason = reason || ""
            cookieBrowserCombo.currentIndex = _browserIndex(suggestedBrowser)
            show()
            raise()
            requestActivate()
        }

        onVisibleChanged: {
            if (visible) {
                x = root.x + Math.round((root.width  - width)  / 2)
                y = root.y + Math.round((root.height - height) / 2)
            } else {
                downloadId = ""
                errorReason = ""
                cookieBrowserCombo.currentIndex = 0
            }
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 16
            spacing: 10

            Text {
                Layout.fillWidth: true
                text: "This YouTube download looks like it needs login cookies."
                color: "#e0e0e0"
                font.pixelSize: 14
                font.weight: Font.Medium
                wrapMode: Text.WordWrap
            }

            Text {
                Layout.fillWidth: true
                text: ytdlpCookieRetryDialog.errorReason
                color: "#aaaaaa"
                font.pixelSize: 11
                wrapMode: Text.WordWrap
            }

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 64
                radius: 4
                color: "#1a2030"
                border.color: "#2a3050"

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 10
                    spacing: 6

                    Text {
                        text: "Cookies from browser:"
                        color: "#8899bb"
                        font.pixelSize: 11
                    }

                    ComboBox {
                        id: cookieBrowserCombo
                        Layout.preferredWidth: 130
                        implicitHeight: 26
                        model: ["Chrome","Firefox","Edge","Brave","Opera","Vivaldi","Safari"]
                        contentItem: Text {
                            leftPadding: 8
                            text: cookieBrowserCombo.displayText
                            color: "#d0d0d0"
                            font: cookieBrowserCombo.font
                            verticalAlignment: Text.AlignVCenter
                        }
                        background: Rectangle {
                            color: "#1b1b1b"
                            border.color: cookieBrowserCombo.activeFocus ? "#4488dd" : "#3a3a3a"
                            radius: 3
                        }
                        delegate: ItemDelegate {
                            id: cookieBrowserDelegate
                            width: cookieBrowserCombo.width
                            height: 24
                            contentItem: Text {
                                text: modelData
                                color: "#d0d0d0"
                                font.pixelSize: 11
                                verticalAlignment: Text.AlignVCenter
                                leftPadding: 8
                            }
                            background: Rectangle { color: cookieBrowserDelegate.hovered ? "#2a3a5a" : "#1b1b1b" }
                        }
                        popup: Popup {
                            y: cookieBrowserCombo.height + 2
                            width: cookieBrowserCombo.width
                            implicitHeight: contentItem.implicitHeight + 4
                            padding: 2
                            background: Rectangle { color: "#1b1b1b"; border.color: "#3a3a3a"; radius: 3 }
                            contentItem: ListView {
                                implicitHeight: contentHeight
                                clip: true
                                model: cookieBrowserCombo.delegateModel
                            }
                        }
                    }
                }
            }

            Text {
                Layout.fillWidth: true
                text: "Stellar will retry the same yt-dlp item with that browser's cookies."
                color: "#667788"
                font.pixelSize: 10
                wrapMode: Text.WordWrap
            }

            Item { Layout.fillHeight: true }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Item { Layout.fillWidth: true }

                DlgButton {
                    text: "Cancel"
                    onClicked: ytdlpCookieRetryDialog.close()
                }

                DlgButton {
                    text: "Retry Download"
                    primary: true
                    enabled: ytdlpCookieRetryDialog.downloadId.length > 0
                    onClicked: {
                        if (App.retryYtdlpWithBrowserCookies(ytdlpCookieRetryDialog.downloadId,
                                                             cookieBrowserCombo.currentText.toLowerCase())) {
                            ytdlpCookieRetryDialog.close()
                        }
                    }
                }
            }
        }
    }

    Connections {
        target: App
        function onErrorOccurred(message) {
            appErrorDialog.text = message && message.length > 0 ? message : "An unexpected error occurred."
            appErrorDialog.open()
        }
        function onYtdlpCookieRetryRequested(downloadId, reason, suggestedBrowser) {
            ytdlpCookieRetryDialog._openFor(downloadId, reason, suggestedBrowser)
        }
        function onFileDeletedWarningDetected(downloadId, filename) {
            fileDeletedWarningDialog._filename = filename
            fileDeletedWarningDialog.show()
            fileDeletedWarningDialog.raise()
            fileDeletedWarningDialog.requestActivate()
        }
    }

    // Debounce geometry saves — writing QSettings on every pixel of a drag
    // causes a disk write per event and makes resizing feel laggy.
    Timer {
        id: geometrySaveTimer
        interval: 500
        repeat: false
        onTriggered: {
            if (!root._geometrySaveReady) return
            if (root.visibility === Window.Windowed) {
                App.settings.mainWindowX      = root.x
                App.settings.mainWindowY      = root.y
                App.settings.mainWindowWidth  = root.width
                App.settings.mainWindowHeight = root.height
            }
        }
    }

    onXChanged:      { if (_geometrySaveReady && visibility === Window.Windowed)  geometrySaveTimer.restart() }
    onYChanged:      { if (_geometrySaveReady && visibility === Window.Windowed)  geometrySaveTimer.restart() }
    onWidthChanged:  { if (_geometrySaveReady && visibility !== Window.Minimized) geometrySaveTimer.restart() }
    onHeightChanged: { if (_geometrySaveReady && visibility !== Window.Minimized) geometrySaveTimer.restart() }

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
        transientParent: null
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
            TrayMenuItem { label: "About Stellar"; onClicked: { trayMenu.visible = false; root.show(); root.raise(); root.showSettingsPage(10) } }
            Rectangle { width: parent.width; height: 1; color: "#444" }
            TrayMenuItem { label: (App.settings.globalSpeedLimitKBps > 0 ? "✓ " : "") + "Speed Limiter: Turn On";  onClicked: { trayMenu.visible = false; App.enableSpeedLimiter() } }
            TrayMenuItem { label: (App.settings.globalSpeedLimitKBps === 0 ? "✓ " : "") + "Speed Limiter: Turn Off"; onClicked: { trayMenu.visible = false; App.disableSpeedLimiter() } }
            TrayMenuItem { label: "Speed Limiter Settings…"; onClicked: { trayMenu.visible = false; root.show(); root.raise(); root.showSettingsPage(4) } }
            Rectangle { width: parent.width; height: 1; color: "#444" }
            TrayMenuItem { label: "Exit Stellar";  onClicked: { trayMenu.visible = false; root.quitApp() } }
        }
    }

    // ── Controller signals ────────────────────────────────────────────────────
    Connections {
        target: App

        function onShowWindowRequested() {
            if (root.visibility === Window.Minimized)
                root.visibility = Window.Windowed
            root.show(); root.raise(); root.requestActivate()
        }
        function onTorrentMetadataRequested(downloadId, startWhenReady) {
            root.showTorrentMetadataDialog(downloadId, startWhenReady)
        }
        function onDownloadAdded(item) {
            // Don't show the progress popup for "Download Later" (Paused) or for
            // queue-managed downloads — queues run silently in the background.
            if (!item || item.status === "Paused") return
            if (item.isTorrent) return
            if (item.isYtdlp && item.ytdlpPlaylistMode) return
            if (item.queueId && item.queueId.length > 0) return
            if (item.category && App.isGrabberProjectId(item.category)) return
            progressDialog.item       = item
            progressDialog.downloadId = item.id
            progressDialog.show()
            progressDialog.raise()
        }
        function onDownloadCompleted(item) {
            if (progressDialog.visible && progressDialog.item === item)
                progressDialog.hide()
            // Torrents go Completed → Seeding; never show the complete dialog for them.
            if (!item || item.isTorrent)
                return
            // Don't show complete dialog for queue-assigned downloads or if disabled in settings
            if (item.queueId && item.queueId.length > 0)
                return
            if (item.isYtdlp && item.ytdlpPlaylistMode)
                return
            if (item.category && App.isGrabberProjectId(item.category))
                return
            if (!App.settings.showDownloadComplete)
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
            root.showSettingsPage(10)
        }
        function onTraySpeedLimiterRequested() {
            root.show(); root.raise()
            root.showSettingsPage(4)
        }
        function onContextMenuRequested(x, y) {
            trayMenu.popup(x, y)
        }
        function onUpdateDialogRequested() {
            updateAvailableDialog.show()
            updateAvailableDialog.raise()
            updateAvailableDialog.requestActivate()
        }
        function onUpdateUpToDate() {
            quickUpdateDialog.messageText = "You are using the latest version of Stellar Download Manager. Please check back again for updates at a later time."
            quickUpdateDialog.show()
            quickUpdateDialog.raise()
            quickUpdateDialog.requestActivate()
        }
        function onUpdateError(message) {
            quickUpdateDialog.messageText = message
            quickUpdateDialog.show()
            quickUpdateDialog.raise()
            quickUpdateDialog.requestActivate()
        }
        function onExceptionDialogRequested(url) {
            addExceptionDialog.url = url
            addExceptionDialog.show()
            addExceptionDialog.raise()
        }
        function onTorrentDuplicateDetected(existingId, newTrackers) {
            torrentDuplicateDialog.open(existingId, newTrackers)
        }
        function onInterceptedDownloadRequested(url, filename) {
            if (App.isTorrentUri(url)) {
                var magnetId = App.addMagnetLink(url, App.settings.defaultSavePath, "", "", false, "")
                if (magnetId && magnetId.length > 0) {
                    root.showTorrentMetadataDialog(magnetId, true)
                }
                return
            }

            if (App.isLikelyYtdlpUrl(url)) {
                _showYtdlpDialog(url)
                ytdlpDialog.uniqueFilename = false
                return
            }

            var existing = App.findDuplicateUrl(url)
            if (existing) {
                var action = App.settings.duplicateAction
                if (action === 0) {
                    // Ask — show duplicate dialog
                    duplicateDialog.existingItem = existing
                    duplicateDialog._pendingUrl  = url
                    showAndActivate(duplicateDialog)
                } else {
                    _handleDuplicateAction(action, false, existing, url)
                }
                return
            }
            // Firefox passes the full local save path as filename — extract basename only.
            var name = (filename.length > 0 ? filename.split(/[/\\]/).pop() : "") ||
                       url.split("/").pop().split("?")[0] || "download"
            var _cookies  = App.takePendingCookies(url)
            var _referrer = App.takePendingReferrer(url)
            var _pageUrl  = App.takePendingPageUrl(url)
            fileInfoDialog.pendingUrl      = url
            fileInfoDialog.pendingFilename = name
            fileInfoDialog.pendingSize     = ""
            fileInfoDialog.pendingSavePath = App.settings.defaultSavePath
            fileInfoDialog.pendingCookies  = _cookies
            fileInfoDialog.pendingReferrer = _referrer
            fileInfoDialog.pendingDownloadId = App.settings.startDownloadWhileFileInfo
                ? App.beginPendingDownload(url, name, _cookies, _referrer, _pageUrl, "", "")
                : ""
            fileInfoDialog.isIntercepted   = true
            showAndActivate(fileInfoDialog)
        }
    }

    // ── Grabber explore-finished: run completion actions ─────────────────────
    Connections {
        target: App
        function onGrabberExploreFinished(projectId) {
            var proj = App.grabberProjectData(projectId)
            var sched = proj.schedule || {}
            if (sched.exitApp) {
                root.quitApp()
                return
            }
            if (sched.turnOffComputer) {
                App.shutdownComputer()
            }
        }
    }

    // ── Grabber schedule checker (runs every 30 s) ────────────────────────────
    Timer {
        id: grabberScheduleTimer
        interval: 30000
        repeat: true
        running: true
        onTriggered: {
            var count = App.grabberProjectModel.rowCount()
            var now = new Date()
            for (var i = 0; i < count; ++i) {
                var proj = App.grabberProjectModel.projectData(i)
                if (!proj) continue
                var sched = proj.schedule || {}
                if (!sched.enabled) continue
                if (!sched.startAt) continue

                var h = parseInt(sched.startHour) || 12
                var m = parseInt(sched.startMinute) || 0
                var ampm = sched.startAmpm || "AM"
                var h24 = (ampm === "PM" ? (h < 12 ? h + 12 : 12) : (h === 12 ? 0 : h))

                var mode = sched.scheduleMode || "once"
                var shouldRun = false

                if (mode === "once") {
                    // Fire once at exact date/time (within the 30s window)
                    var mo = parseInt(sched.onceMonth) || 1
                    var da = parseInt(sched.onceDay) || 1
                    var yr = parseInt(sched.onceYear) || now.getFullYear()
                    var target = new Date(yr, mo - 1, da, h24, m, 0, 0)
                    var diff = now - target
                    if (diff >= 0 && diff < 30000) shouldRun = true
                } else if (mode === "daily") {
                    var days = sched.days || []
                    var dayIdx = now.getDay() // 0=Sun
                    var dayNames = ["Sun","Mon","Tue","Wed","Thu","Fri","Sat"]
                    if (days.indexOf(dayNames[dayIdx]) >= 0
                            && now.getHours() === h24 && now.getMinutes() === m
                            && now.getSeconds() < 30) {
                        shouldRun = true
                    }
                }

                if (shouldRun) App.runGrabber(proj)
            }
        }
    }

    // ── Clipboard URL monitoring — react to signal from AppController ────────────
    // When the user copies a URL matching a monitored extension, show the Add URL
    // dialog pre-filled with that URL and a friendly title explaining why it appeared.
    Connections {
        target: App
        function onClipboardUrlDetected(url) {
            // Pre-fill the URL field and override the dialog title
            addUrlDialog.url = url
            addUrlDialog.titleOverride = "Download link was found in clipboard. Do you want to download it?"
            addUrlDialog.show()
            addUrlDialog.raise()
            addUrlDialog.requestActivate()
        }
    }

    // ── Speed limiter scheduler ───────────────────────────────────────────────
    // Evaluated every 60 seconds AND immediately when settings are applied.
    // Each rule: days[], onHour (1-12), onMinute (0-59), onAmPm, offHour,
    // offMinute, offAmPm, downLimitKBps, upLimitKBps. First matching rule wins.

    // Named function so it can be called directly (e.g. from Apply button)
    // as well as from the recurring timer below.
    function runSpeedScheduleCheck() {
        if (!App.settings.speedScheduleEnabled) {
            if (speedScheduleOwnsDownLimit && App.settings.globalSpeedLimitKBps > 0)
                App.settings.globalSpeedLimitKBps = 0
            if (speedScheduleOwnsUpLimit && App.settings.globalUploadLimitKBps > 0)
                App.settings.globalUploadLimitKBps = 0
            speedScheduleOwnsDownLimit = false
            speedScheduleOwnsUpLimit = false
            return
        }

        var rules = []
        try { rules = JSON.parse(App.settings.speedScheduleJson || "[]") }
        catch (e) { return }
        if (!rules || rules.length === 0) {
            if (speedScheduleOwnsDownLimit && App.settings.globalSpeedLimitKBps > 0)
                App.settings.globalSpeedLimitKBps = 0
            if (speedScheduleOwnsUpLimit && App.settings.globalUploadLimitKBps > 0)
                App.settings.globalUploadLimitKBps = 0
            speedScheduleOwnsDownLimit = false
            speedScheduleOwnsUpLimit = false
            return
        }

        var now = new Date()
        var dayNames = ["Sun","Mon","Tue","Wed","Thu","Fri","Sat"]
        var todayName = dayNames[now.getDay()]
        var nowTotal = now.getHours() * 60 + now.getMinutes()

        var matchedRule = null
        for (var i = 0; i < rules.length; ++i) {
            var r = rules[i]
            if (!r.days || r.days.indexOf(todayName) < 0) continue

            // Convert 12-hour time to minutes-since-midnight
            var onH = parseInt(r.onHour) || 12
            var on24 = (r.onAmPm === "PM")
                ? (onH < 12 ? onH + 12 : 12) * 60 + (parseInt(r.onMinute) || 0)
                : (onH === 12 ? 0 : onH)    * 60 + (parseInt(r.onMinute) || 0)

            var offH = parseInt(r.offHour) || 5
            var off24 = (r.offAmPm === "PM")
                ? (offH < 12 ? offH + 12 : 12) * 60 + (parseInt(r.offMinute) || 0)
                : (offH === 12 ? 0 : offH)     * 60 + (parseInt(r.offMinute) || 0)

            // Handle same-day and overnight ranges
            var active = (on24 <= off24)
                ? (nowTotal >= on24 && nowTotal < off24)          // e.g. 9 AM – 5 PM
                : (nowTotal >= on24 || nowTotal < off24)           // e.g. 10 PM – 6 AM
            if (active) { matchedRule = r; break }
        }

        if (matchedRule !== null) {
            var downKbps = parseInt(matchedRule.downLimitKBps)
            if (isNaN(downKbps) || downKbps <= 0)
                downKbps = parseInt(matchedRule.limitKBps) || 500 // backward compatibility
            var upKbps = parseInt(matchedRule.upLimitKBps)
            if (isNaN(upKbps) || upKbps <= 0)
                upKbps = 500

            if (App.settings.globalSpeedLimitKBps !== downKbps)
                App.settings.globalSpeedLimitKBps = downKbps
            if (App.settings.globalUploadLimitKBps !== upKbps)
                App.settings.globalUploadLimitKBps = upKbps
            speedScheduleOwnsDownLimit = true
            speedScheduleOwnsUpLimit = true
        } else {
            if (speedScheduleOwnsDownLimit && App.settings.globalSpeedLimitKBps > 0)
                App.settings.globalSpeedLimitKBps = 0
            if (speedScheduleOwnsUpLimit && App.settings.globalUploadLimitKBps > 0)
                App.settings.globalUploadLimitKBps = 0
            speedScheduleOwnsDownLimit = false
            speedScheduleOwnsUpLimit = false
        }
    }

    // Re-evaluate immediately when the user applies scheduler settings
    Connections {
        target: App.settings
        function onSpeedScheduleEnabledChanged() { root.runSpeedScheduleCheck() }
        function onSpeedScheduleJsonChanged()    { root.runSpeedScheduleCheck() }
    }

    Timer {
        id: speedScheduleTimer
        interval: 60000
        repeat: true
        running: true   // always running; the function guards on speedScheduleEnabled
        triggeredOnStart: true
        onTriggered: root.runSpeedScheduleCheck()
    }

    // ── Add URL dialog (step 1) ───────────────────────────────────────────────
    AddUrlDialog {
        id: addUrlDialog
        transientParent: root
        onAccepted: {
            if (url.trim().length === 0) return
            var normalizedUrl = App.isTorrentUri(url) ? root.normalizeTorrentInput(url) : url
            // Store auth credentials for step 2
            root._pendingUsername = useAuth ? username : ""
            root._pendingPassword = useAuth ? password : ""
            if (App.isTorrentUri(normalizedUrl)) {
                // Torrent duplicate detection is done by info hash inside addMagnetLink;
                // it emits torrentDuplicateDetected and returns {} on duplicate.
                var torrentId = App.addMagnetLink(normalizedUrl, App.settings.defaultSavePath, "", "", false, "")
                if (torrentId && torrentId.length > 0)
                    root.showTorrentMetadataDialog(torrentId, true)
            } else {
                var existing = App.findDuplicateUrl(normalizedUrl)
                if (existing) {
                    var action = App.settings.duplicateAction
                    if (action === 0) {
                        duplicateDialog.existingItem = existing
                        duplicateDialog._pendingUrl  = normalizedUrl
                        duplicateDialog.show()
                        duplicateDialog.raise()
                    } else {
                        _handleDuplicateAction(action, false, existing, normalizedUrl)
                    }
                } else {
                    _showFileInfoDialog(normalizedUrl, "")
                }
            }
        }
    }

    FileDialog {
        id: addTorrentFileDialog
        title: "Add Torrent File"
        fileMode: FileDialog.OpenFile
        nameFilters: ["Torrent files (*.torrent)", "All files (*)"]
        onAccepted: {
            var path = selectedFile.toString()
                .replace(/^file:\/\/\//, "")
                .replace(/^file:\/\//, "")
            root._pendingTorrentFilePath = ""
            fileInfoDialog.pendingDownloadId = ""
            root.showTorrentMetadataDialogForFile(path, App.settings.defaultSavePath, "", "", true)
        }
    }

    FolderDialog {
        id: exportTorrentFolderDialog
        title: "Export .torrent Files"
        onAccepted: {
            if (!root.pendingTorrentExportIds || root.pendingTorrentExportIds.length === 0)
                return
            var dir = selectedFolder.toString()
                .replace(/^file:\/\/\//, "")
                .replace(/^file:\/\//, "")
            App.exportTorrentFilesToDirectory(root.pendingTorrentExportIds, dir)
            root.pendingTorrentExportIds = []
        }
        onRejected: root.pendingTorrentExportIds = []
    }

    // Open the yt-dlp format picker for a video site URL.
    // No DownloadItem is created here — it only appears in the list once the
    // user confirms a format and App.finalizeYtdlpDownload() runs.
    function _showYtdlpDialog(url) {
        ytdlpDialog.pendingUrl = url
        ytdlpDialog.show()
        ytdlpDialog.raise()
        ytdlpDialog.requestActivate()
    }

    function _showFileInfoDialog(url, filenameOverride) {
        // Route yt-dlp-compatible URLs to the video format picker instead.
        if (App.isLikelyYtdlpUrl(url)) {
            _showYtdlpDialog(url)
            return
        }
        if (App.isTorrentUri(url)) {
            var torrentId = App.addMagnetLink(url, App.settings.defaultSavePath, "", "", false, "")
            showTorrentMetadataDialog(torrentId, true)
            return
        }
        var filename = filenameOverride.length > 0
            ? filenameOverride
            : (App.isTorrentUri(url)
                ? "Magnetized Transfer"
                : (url.split("/").pop().split("?")[0] || "download"))
        var _cookies2  = App.takePendingCookies(url)
        var _referrer2 = App.takePendingReferrer(url)
        var _pageUrl2  = App.takePendingPageUrl(url)
        fileInfoDialog.pendingUrl      = url
        fileInfoDialog.pendingFilename = filename
        fileInfoDialog.pendingSize     = ""
        fileInfoDialog.pendingSavePath = App.settings.defaultSavePath
        fileInfoDialog.filenameOverride = filenameOverride
        fileInfoDialog.pendingCookies  = _cookies2
        fileInfoDialog.pendingReferrer = _referrer2
        fileInfoDialog.pendingDownloadId = App.settings.startDownloadWhileFileInfo
            ? App.beginPendingDownload(url, filename, _cookies2, _referrer2, _pageUrl2, root._pendingUsername, root._pendingPassword)
            : ""
        fileInfoDialog.show()
        fileInfoDialog.raise()
        fileInfoDialog.requestActivate()
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
            // AddNumbered: for yt-dlp URLs the filename is chosen by yt-dlp itself
            // (from video metadata), so generating a numbered name here has no effect —
            // just open the format picker as a fresh download.
            // For regular URLs, generate a unique filename as usual.
            if (App.isLikelyYtdlpUrl(url)) {
                _showYtdlpDialog(url)
                ytdlpDialog.uniqueFilename = true
            } else {
                var base = url.split("/").pop().split("?")[0] || "download"
                var numbered = App.generateNumberedFilename(base)
                _showFileInfoDialog(url, numbered)
            }
        }
    }

    // Pending auth from AddUrlDialog step 1
    property string _pendingUsername: ""
    property string _pendingPassword: ""
    property string _pendingTorrentFilePath: ""
    property var _pendingBatchUrls: []
    property var _pendingLaterRequest: null
    property string _pendingQueueContext: ""
    property var _afterDownloadLaterWarning: null

    // ── Download File Info dialog (step 2) ────────────────────────────────────
    DownloadFileInfoDialog {
        id: fileInfoDialog
        transientParent: root
        onDownloadNow: (downloadId, url, savePath, category, desc) => {
            if (root._pendingTorrentFilePath.length > 0) {
                var pendingTorrentPathNow = root._pendingTorrentFilePath
                var torrentFileDir = root.torrentSaveDirFromInputPath(savePath)
                root._pendingTorrentFilePath = ""
                fileInfoDialog.pendingDownloadId = ""
                root.showTorrentMetadataDialogForFile(pendingTorrentPathNow, torrentFileDir, category, desc, true)
                return
            }
            if (App.isTorrentUri(url)) {
                var torrentDir = root.torrentSaveDirFromInputPath(savePath)
                var magnetId = App.addMagnetLink(url, torrentDir, category, desc, false, "")
                fileInfoDialog.pendingDownloadId = ""
                root.showTorrentMetadataDialog(magnetId, true)
                return
            }
            if (downloadId && downloadId.length > 0) {
                App.finalizePendingDownload(downloadId, savePath, category, desc, true, "")
            } else {
                var sep = Math.max(savePath.lastIndexOf("/"), savePath.lastIndexOf("\\"))
                var dir   = sep >= 0 ? savePath.substring(0, sep) : savePath
                var fname = sep >= 0 ? savePath.substring(sep + 1) : fileInfoDialog.filenameOverride
                App.addUrl(url, dir, category, desc, true, App.takePendingCookies(url), App.takePendingReferrer(url), App.takePendingPageUrl(url), root._pendingUsername, root._pendingPassword, fname)
            }
            fileInfoDialog.pendingDownloadId = ""
        }
        onDownloadLater: (downloadId, url, savePath, category, desc) => {
            if (root._pendingTorrentFilePath.length > 0) {
                var pendingTorrentPath = root._pendingTorrentFilePath
                root._afterDownloadLaterWarning = function() {
                    var torrentFileDir = root.torrentSaveDirFromInputPath(savePath)
                    root._pendingTorrentFilePath = ""
                    fileInfoDialog.pendingDownloadId = ""
                    root.showTorrentMetadataDialogForFile(pendingTorrentPath, torrentFileDir, category, desc, false)
                }
                root._afterDownloadLaterWarning()
                return
            }
            if (App.isTorrentUri(url)) {
                root._afterDownloadLaterWarning = function() {
                    var torrentDir = root.torrentSaveDirFromInputPath(savePath)
                    var magnetId = App.addMagnetLink(url, torrentDir, category, desc, false, "")
                    fileInfoDialog.pendingDownloadId = ""
                    root.showTorrentMetadataDialog(magnetId, false)
                }
                root._afterDownloadLaterWarning()
                return
            }
            if (downloadId && downloadId.length > 0)
                App.pauseDownload(downloadId)
            root._afterDownloadLaterWarning = function() {
                if (App.settings.showQueueSelectionOnDownloadLater) {
                    queueSelectionDialog.initialQueueId = ""
                    queueSelectionDialog.initialStartProcessing = false
                    queueSelectionDialog.initialAskAgain = false
                    queueSelectionDialog.queueIds = App.queueIds()
                    queueSelectionDialog.queueNames = App.queueNames()
                    queueSelectionDialog.pendingContext = "later"
                    queueSelectionDialog.pendingLaterDownloadId = downloadId
                    queueSelectionDialog.pendingLaterUrl = url
                    queueSelectionDialog.pendingLaterSavePath = savePath
                    queueSelectionDialog.pendingLaterCategory = category
                    queueSelectionDialog.pendingLaterDesc = desc
                    queueSelectionDialog.pendingLaterFilename = fileInfoDialog.filenameOverride
                    queueSelectionDialog.pendingLaterUsername = root._pendingUsername
                    queueSelectionDialog.pendingLaterPassword = root._pendingPassword
                    queueSelectionDialog.noteText = "Note: These settings don't apply to queue processing for the Start Downloading Immediately setting and Show Download Complete dialog setting."
                    queueSelectionDialog.show()
                    queueSelectionDialog.raise()
                } else if (downloadId && downloadId.length > 0) {
                    App.finalizePendingDownload(downloadId, savePath, category, desc, false, "")
                } else {
                    var sep = Math.max(savePath.lastIndexOf("/"), savePath.lastIndexOf("\\"))
                    var dir   = sep >= 0 ? savePath.substring(0, sep) : savePath
                    var fname = sep >= 0 ? savePath.substring(sep + 1) : fileInfoDialog.filenameOverride
                    App.addUrl(url, dir, category, desc, false, App.takePendingCookies(url), App.takePendingReferrer(url), App.takePendingPageUrl(url), root._pendingUsername, root._pendingPassword, fname)
                }
                fileInfoDialog.pendingDownloadId = ""
            }
            if (downloadId && downloadId.length > 0) {
                downloadLaterWarningDialog.show()
                downloadLaterWarningDialog.raise()
                downloadLaterWarningDialog.requestActivate()
            } else {
                root._afterDownloadLaterWarning()
            }
        }
        onRejected: (downloadId, url) => {
            if (downloadId && downloadId.length > 0)
                App.discardPendingDownload(downloadId)
            root._pendingTorrentFilePath = ""
            if (fileInfoDialog.isIntercepted)
                App.notifyInterceptRejected(url)
            fileInfoDialog.pendingDownloadId = ""
        }
    }

    // ── yt-dlp format picker dialog ───────────────────────────────────────────
    // Shown when a yt-dlp-compatible URL is submitted via Add URL or clipboard.
    // The URL is probed with "yt-dlp --dump-json" so the user can choose quality
    // before the actual download starts.
    YtdlpDialog {
        id: ytdlpDialog
        transientParent: root

        onDownloadRequested: (url, formatId, containerFormat, savePath, category, uniqueFilename, videoTitle, playlistMode, maxItems, extraOptions) => {
            App.finalizeYtdlpDownload(url, savePath, category, formatId, containerFormat, uniqueFilename, videoTitle, playlistMode, maxItems, extraOptions)
        }
        onOpenSettingsRequested: (page) => showSettingsPage(page)
    }

    Window {
        id: ytdlpBatchWindow
        transientParent: root
        width: 760
        height: 520
        minimumWidth: 620
        minimumHeight: 420
        title: "Channel Download Progress"
        color: "#1e1e1e"
        modality: Qt.NonModal
        flags: Qt.Dialog | Qt.WindowTitleHint | Qt.WindowCloseButtonHint
        visible: false

        onVisibleChanged: {
            if (visible) {
                x = root.x + Math.round((root.width  - width)  / 2)
                y = root.y + Math.round((root.height - height) / 2)
            } else if (!visible && App.ytdlpBatchActive) {
                // keep it dockable; user can close while it continues in background
            }
        }

        Connections {
            target: App
            function onYtdlpBatchChanged() {
                if (App.ytdlpBatchActive) {
                    ytdlpBatchWindow.show()
                    ytdlpBatchWindow.raise()
                    ytdlpBatchWindow.requestActivate()
                }
            }
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 6
            spacing: 6

            Text {
                Layout.fillWidth: true
                text: App.ytdlpBatchLabel.length > 0 ? App.ytdlpBatchLabel : "Channel/Playlist"
                color: "#d8d8d8"
                font.pixelSize: 12
                elide: Text.ElideMiddle
            }

            Text {
                Layout.fillWidth: true
                property int totalCount: App.ytdlpBatchItems.length
                property int doneCount: {
                    var c = 0
                    for (var i = 0; i < App.ytdlpBatchItems.length; ++i)
                        if ((App.ytdlpBatchItems[i].status || "") === "Completed") c++
                    return c
                }
                property int activeCount: {
                    var c = 0
                    for (var i = 0; i < App.ytdlpBatchItems.length; ++i)
                        if ((App.ytdlpBatchItems[i].status || "") === "Downloading") c++
                    return c
                }
                property int queuedCount: Math.max(0, totalCount - doneCount - activeCount)
                property real avgProgress: {
                    if (App.ytdlpBatchItems.length === 0) return 0
                    var sum = 0
                    for (var i = 0; i < App.ytdlpBatchItems.length; ++i)
                        sum += (App.ytdlpBatchItems[i].progress || 0)
                    return sum / App.ytdlpBatchItems.length
                }
                text: "Total: " + totalCount
                      + "   Completed: " + doneCount
                      + "   Downloading: " + activeCount
                      + "   Queued: " + queuedCount
                      + "   Overall: " + Math.round(avgProgress) + "%"
                color: "#9fa9b8"
                font.pixelSize: 11
                elide: Text.ElideRight
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                color: "#181818"
                border.color: "#313131"
                radius: 4

                ListView {
                    anchors.fill: parent
                    anchors.margins: 1
                    clip: true
                    model: App.ytdlpBatchItems

                    delegate: Rectangle {
                        width: ListView.view.width
                        height: 34
                        color: index % 2 === 0 ? "#1d1d1d" : "#191919"

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 10
                            spacing: 8

                            Text {
                                text: (modelData.index || (index + 1)) + "."
                                color: "#8b8b8b"
                                font.pixelSize: 11
                                Layout.preferredWidth: 28
                            }
                            Text {
                                text: modelData.title || ("Item " + (index + 1))
                                color: "#d0d0d0"
                                font.pixelSize: 11
                                elide: Text.ElideMiddle
                                Layout.fillWidth: true
                            }
                            Text {
                                text: modelData.status || "Queued"
                                color: modelData.status === "Completed" ? "#7bc67b"
                                      : modelData.status === "Downloading" ? "#88b4ff" : "#999999"
                                font.pixelSize: 11
                                Layout.preferredWidth: 90
                                horizontalAlignment: Text.AlignRight
                            }
                            ProgressBar {
                                from: 0
                                to: 100
                                value: Math.max(0, Math.min(100, modelData.progress || 0))
                                Layout.preferredWidth: 140
                            }
                        }
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Item { Layout.fillWidth: true }
                DlgButton {
                    text: "Stop"
                    enabled: App.ytdlpBatchActive
                    onClicked: App.stopActiveYtdlpBatch()
                }
                DlgButton {
                    text: "Resume"
                    enabled: !App.ytdlpBatchActive && App.ytdlpBatchCanResume
                    onClicked: App.resumeLastYtdlpBatch()
                }
                DlgButton {
                    text: "Close"
                    onClicked: ytdlpBatchWindow.hide()
                }
            }
        }
    }

    TorrentMetadataDialog {
        id: torrentMetadataDialog
        transientParent: root
        onDownloadNowRequested: (downloadId, savePath, category, description) => {
            App.confirmTorrentDownload(downloadId, savePath, category, description, true, "")
        }
        onDownloadLaterRequested: (downloadId, savePath, category, description) => {
            if (App.settings.showQueueSelectionOnDownloadLater) {
                queueSelectionDialog.initialQueueId = ""
                queueSelectionDialog.initialStartProcessing = false
                queueSelectionDialog.initialAskAgain = false
                queueSelectionDialog.queueIds = App.queueIds()
                queueSelectionDialog.queueNames = App.queueNames()
                queueSelectionDialog.pendingContext = "torrentLater"
                queueSelectionDialog.pendingTorrentLaterDownloadId = downloadId
                queueSelectionDialog.pendingTorrentLaterSavePath = savePath
                queueSelectionDialog.pendingTorrentLaterCategory = category
                queueSelectionDialog.pendingTorrentLaterDesc = description
                queueSelectionDialog.noteText = "Note: These settings don't apply to queue processing for the Start Downloading Immediately setting and Show Download Complete dialog setting."
                queueSelectionDialog.show()
                queueSelectionDialog.raise()
                queueSelectionDialog.requestActivate()
            } else {
                App.confirmTorrentDownload(downloadId, savePath, category, description, false, "")
            }
        }
    }

    TorrentDuplicateDialog {
        id: torrentDuplicateDialog
        transientParent: root
        onMergeRequested: (downloadId, trackers) => {
            App.mergeTrackersInto(downloadId, trackers)
        }
    }

    TorrentSearchWindow {
        id: torrentSearchWindow
        transientParent: root
    }

    RssWindow {
        id: rssWindow
        transientParent: root
    }

    // React to ytdlp clipboard detection from AppController
    Connections {
        target: App
        function onYtdlpClipboardUrlDetected(url) {
            _showYtdlpDialog(url)
        }
    }

    Window {
        id: downloadLaterWarningDialog
        title: "Download Later"
        transientParent: root
        width: 480
        height: 220
        minimumWidth: 380
        minimumHeight: 200
        flags: Qt.Dialog | Qt.WindowTitleHint | Qt.WindowCloseButtonHint
        modality: Qt.ApplicationModal
        color: "#1e1e1e"

        Material.theme: Material.Dark
        Material.background: "#1e1e1e"
        Material.accent: "#4488dd"

        onVisibleChanged: {
            if (visible) {
                x = root.x + Math.round((root.width  - width)  / 2)
                y = root.y + Math.round((root.height - height) / 2)
            }
        }

        onClosing: {
            root._afterDownloadLaterWarning = null
        }

        ColumnLayout {
            anchors { fill: parent; margins: 20 }
            spacing: 16

            Text {
                Layout.fillWidth: true
                text: "You pressed the 'Download Later' button, but Stellar had already started downloading a part of the file. Stellar always starts downloading while displaying the \"Download File Info\" dialog.\n\nYou can turn this off in Settings → Downloads."
                color: "#d0d0d0"
                font.pixelSize: 13
                wrapMode: Text.WordWrap
                lineHeight: 1.3
            }

            Item { Layout.fillHeight: true }

            RowLayout {
                Layout.fillWidth: true
                Item { Layout.fillWidth: true }
                DlgButton {
                    text: "OK"
                    primary: true
                    onClicked: {
                        downloadLaterWarningDialog.close()
                        if (root._afterDownloadLaterWarning)
                            root._afterDownloadLaterWarning()
                        root._afterDownloadLaterWarning = null
                    }
                }
            }
        }
    }

    // ── File Deleted Warning Dialog ───────────────────────────────────────────
    Window {
        id: fileDeletedWarningDialog
        property string _filename: ""
        title: "File No Longer Available"
        transientParent: root
        width: 460
        height: 240
        minimumWidth: 400
        minimumHeight: 220
        flags: Qt.Dialog | Qt.WindowTitleHint | Qt.WindowCloseButtonHint
        modality: Qt.ApplicationModal
        color: "#1e1e1e"

        Material.theme: Material.Dark
        Material.background: "#1e1e1e"
        Material.accent: "#4488dd"

        onVisibleChanged: {
            if (visible) {
                x = root.x + Math.round((root.width  - width)  / 2)
                y = root.y + Math.round((root.height - height) / 2)
            }
        }

        ColumnLayout {
            anchors { fill: parent; margins: 16 }
            spacing: 10

            // Icon + title row
            RowLayout {
                Layout.fillWidth: true
                spacing: 12

                Image {
                    source: "icons/file_no_longer_available.png"
                    width: 36; height: 36
                    fillMode: Image.PreserveAspectFit
                    Layout.alignment: Qt.AlignTop
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 4

                    Text {
                        Layout.fillWidth: true
                        text: "The file \u201c" + fileDeletedWarningDialog._filename + "\u201d could not be downloaded."
                        color: "#e0e0e0"
                        font.pixelSize: 12
                        font.bold: true
                        wrapMode: Text.WordWrap
                    }

                    Text {
                        Layout.fillWidth: true
                        text: "The server returned a webpage instead of the expected file. Some sites delete files immediately after Stellar queries their metadata."
                        color: "#c8c8c8"
                        font.pixelSize: 11
                        wrapMode: Text.WordWrap
                        lineHeight: 1.3
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: fdwInfoText.implicitHeight + 16
                color: "#1a2030"
                border.color: "#2a3050"
                radius: 3

                Text {
                    id: fdwInfoText
                    anchors { fill: parent; margins: 8 }
                    text: "To let your browser download directly, hold a modifier key (Alt, Ctrl, or Shift) while clicking the link. Configure the key in:\nStellar Options \u2192 Browser \u2192 Bypass Download Interception"
                    color: "#8899bb"
                    font.pixelSize: 11
                    wrapMode: Text.WordWrap
                    lineHeight: 1.3
                }
            }

            Item { Layout.fillHeight: true }

            RowLayout {
                Layout.fillWidth: true
                Item { Layout.fillWidth: true }
                DlgButton {
                    text: "Open Browser Settings"
                    onClicked: {
                        fileDeletedWarningDialog.close()
                        settingsDialog.initialPage = 3  // Browser tab
                        settingsDialog.show()
                        settingsDialog.raise()
                        settingsDialog.requestActivate()
                    }
                }
                DlgButton {
                    text: "OK"
                    primary: true
                    onClicked: fileDeletedWarningDialog.close()
                }
            }
        }
    }

    // ── Duplicate Download Dialog ─────────────────────────────────────────────
    DuplicateDownloadDialog {
        id: duplicateDialog
        transientParent: root
        property string _pendingUrl: ""
        onResolved: (action, remember) => {
            _handleDuplicateAction(action, remember, existingItem, _pendingUrl)
        }
    }

    // ── Download Progress Dialog ──────────────────────────────────────────────
    DownloadProgressDialog { id: progressDialog; transientParent: root }

    // ── Download Complete Dialog ──────────────────────────────────────────────
    DownloadCompleteDialog { id: completeDialog; transientParent: root }

    // ── Settings / About Dialog ───────────────────────────────────────────────
    SettingsDialog {
        id: settingsDialog
        transientParent: root
        onWhatsNewRequested: {
            // Fetch changelog if we don't have it yet, then open the window
            if (!App.updateChangelog || App.updateChangelog.length === 0)
                App.fetchChangelog()
            whatsNewDialog.show()
            whatsNewDialog.raise()
            whatsNewDialog.requestActivate()
        }
    }
    Window {
        id: quickUpdateDialog
        title: "Quick Update"
        transientParent: root
        width: 440
        height: 170
        minimumWidth: 420
        minimumHeight: 160
        flags: Qt.Dialog | Qt.WindowTitleHint | Qt.WindowCloseButtonHint
        modality: Qt.ApplicationModal
        color: "#1e1e1e"
        property string messageText: ""

        onVisibleChanged: {
            if (visible) {
                x = root.x + Math.round((root.width  - width)  / 2)
                y = root.y + Math.round((root.height - height) / 2)
            }
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 16
            spacing: 12

            Text {
                Layout.fillWidth: true
                text: quickUpdateDialog.messageText
                wrapMode: Text.WordWrap
                color: "#d8d8d8"
                font.pixelSize: 13
            }

            Item { Layout.fillHeight: true }

            RowLayout {
                Layout.alignment: Qt.AlignRight
                DlgButton {
                    text: "OK"
                    onClicked: quickUpdateDialog.close()
                }
            }
        }
    }

    Window {
        id: updateAvailableDialog
        title: "New version of Stellar Download Manager is available"
        transientParent: root
        width: 500
        height: 375
        minimumWidth: 500
        minimumHeight: 375
        flags: Qt.Dialog | Qt.WindowTitleHint | Qt.WindowCloseButtonHint
        modality: Qt.ApplicationModal
        color: "#1e1e1e"
        property bool dismissOnClose: true

        onVisibleChanged: {
            if (visible) {
                x = root.x + Math.round((root.width  - width)  / 2)
                y = root.y + Math.round((root.height - height) / 2)
            }
        }

        onClosing: {
            if (dismissOnClose)
                App.dismissAvailableUpdate()
            dismissOnClose = true
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 16
            spacing: 12

            Text {
                text: "Version " + App.updateVersion + " is available."
                color: "#ffffff"
                font.pixelSize: 16
                font.bold: true
            }

            Rectangle { Layout.fillWidth: true; height: 1; color: "#3a3a3a" }

            ScrollView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true

                Text {
                    width: parent.width
                    text: App.updateChangelog && App.updateChangelog.length > 0
                        ? App.updateChangelog
                        : "No changelog is available for this update."
                    color: "#cfcfcf"
                    font.pixelSize: 12
                    wrapMode: Text.WordWrap
                    textFormat: Text.PlainText
                }
            }

            RowLayout {
                Layout.alignment: Qt.AlignRight
                spacing: 8

                DlgButton {
                    text: "Update Now"
                    primary: true
                    visible: Qt.platform.os === "windows"
                    onClicked: {
                        if (App.startUpdateInstall()) {
                            updateAvailableDialog.dismissOnClose = false
                            updateAvailableDialog.close()
                        } else {
                            quickUpdateDialog.messageText = "Stellar could not start the update installer download."
                            quickUpdateDialog.show()
                            quickUpdateDialog.raise()
                        }
                    }
                }

                DlgButton {
                    text: "Cancel"
                    onClicked: {
                        App.dismissAvailableUpdate()
                        updateAvailableDialog.close()
                    }
                }
            }
        }
    }

    // ── What's New / Changelog viewer ─────────────────────────────────────────
    Window {
        id: whatsNewDialog
        title: "What's New in Stellar"
        transientParent: root
        width: 500
        height: 375
        minimumWidth: 500
        minimumHeight: 375
        flags: Qt.Dialog | Qt.WindowTitleHint | Qt.WindowCloseButtonHint
        modality: Qt.ApplicationModal
        color: "#1e1e1e"

        onVisibleChanged: {
            if (visible) {
                x = root.x + Math.round((root.width  - width)  / 2)
                y = root.y + Math.round((root.height - height) / 2)
            }
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 16
            spacing: 12

            Text {
                text: App.updateChangelog && App.updateChangelog.length > 0
                    ? "Changelog"
                    : "What's New"
                color: "#ffffff"
                font.pixelSize: 16
                font.bold: true
            }

            Rectangle { Layout.fillWidth: true; height: 1; color: "#3a3a3a" }

            ScrollView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true

                Text {
                    width: parent.width
                    text: App.updateChangelog && App.updateChangelog.length > 0
                        ? App.updateChangelog
                        : "No changelog is available."
                    color: "#cfcfcf"
                    font.pixelSize: 12
                    wrapMode: Text.WordWrap
                    textFormat: Text.PlainText
                }
            }

            RowLayout {
                Layout.alignment: Qt.AlignRight
                DlgButton {
                    text: "Close"
                    onClicked: whatsNewDialog.close()
                }
            }
        }
    }

    // ── Scheduler Dialog ───────────────────────────────────────────────────────
    SchedulerDialog { id: schedulerDialog; transientParent: root }

    // ── Batch Download Dialogs ────────────────────────────────────────────────
    BatchDownloadDialog {
        id: batchDownloadDialog
        transientParent: root
        onAccepted: (files) => {
            var urlList = files.split('\n')
            var fileObjs = []
            for(var i=0; i<urlList.length; i++) {
                if(urlList[i].length > 0)
                    fileObjs.push({ name: urlList[i].split('/').pop(), url: urlList[i] })
            }
            batchDownloadListDialog.files = fileObjs
            batchDownloadListDialog.show()
            batchDownloadListDialog.raise()
        }
    }
    BatchDownloadListDialog {
        id: batchDownloadListDialog
        transientParent: root
        onBatchAccepted: (files) => {
            if (App.settings.showQueueSelectionOnBatchDownload) {
                queueSelectionDialog.initialQueueId = ""
                queueSelectionDialog.initialStartProcessing = false
                queueSelectionDialog.initialAskAgain = false
                queueSelectionDialog.queueIds = App.queueIds()
                queueSelectionDialog.queueNames = App.queueNames()
                queueSelectionDialog.pendingContext = "batch"
                queueSelectionDialog.pendingBatchUrls = files
                queueSelectionDialog.noteText = "Note: These settings don't apply to queue processing for the Start Downloading Immediately setting and Show Download Complete dialog setting."
                queueSelectionDialog.show()
                queueSelectionDialog.raise()
            } else {
                for (var i = 0; i < files.length; ++i) {
                    App.addUrl(files[i].url, "", "", "", true, "", "", "", "", "", files[i].filename)
                }
            }
        }
    }

    QueueSelectionDialog {
        id: queueSelectionDialog
        transientParent: root
        onAccepted: (queueId, startProcessing, askAgain) => {
            // After confirming a grabber queue selection, close the results dialog
            // and bring the main download list to the front so the user can see the
            // newly queued files immediately.
            if (queueSelectionDialog.pendingContext === "grabber") {
                grabberResultsDialog.close()
                root.show()
                root.raise()
                root.requestActivate()
            }
            if (queueId.length === 0)
                return
        }
        onCreateQueueRequested: (name) => {
            queueSelectionDialog.queueIds = App.queueIds()
            queueSelectionDialog.queueNames = App.queueNames()
            queueSelectionDialog.initialQueueId = queueSelectionDialog.queueIds.length > 0
                ? queueSelectionDialog.queueIds[queueSelectionDialog.queueIds.length - 1]
                : ""
            queueSelectionDialog.forceActiveFocus()
        }
    }

    GrabberDialog {
        id: grabberDialog
        transientParent: root
        onResultsRequested: (projectId) => {
            grabberResultsDialog.projectId = projectId
            grabberResultsDialog.show()
            grabberResultsDialog.raise()
            grabberResultsDialog.requestActivate()
        }
    }

    GrabberResultsDialog {
        id: grabberResultsDialog
        transientParent: root
        onFilesAddedToDownloadList: {
            grabberResultsDialog.close()
            root.show()
            root.raise()
            root.requestActivate()
        }
        onQueueAssignmentRequested: (projectId) => {
            grabberResultsDialog.actionTaken = true
            queueSelectionDialog.initialQueueId = ""
            queueSelectionDialog.initialStartProcessing = true
            queueSelectionDialog.initialAskAgain = false
            queueSelectionDialog.queueIds = App.queueIds()
            queueSelectionDialog.queueNames = App.queueNames()
            queueSelectionDialog.pendingContext = "grabber"
            queueSelectionDialog.pendingGrabberProjectId = projectId
            queueSelectionDialog.noteText = "Choose a queue for the checked Grabber files."
            queueSelectionDialog.show()
            queueSelectionDialog.raise()
            queueSelectionDialog.requestActivate()
        }
        onScheduleRequested: (projectId) => {
            grabberScheduleDialog.projectId = projectId
            grabberScheduleDialog.show()
            grabberScheduleDialog.raise()
            grabberScheduleDialog.requestActivate()
        }
        onStatisticsRequested: (projectId) => {
            grabberStatisticsDialog.projectId = projectId
            grabberStatisticsDialog.show()
            grabberStatisticsDialog.raise()
            grabberStatisticsDialog.requestActivate()
        }
        onEditProjectRequested: (projectId) => {
            grabberDialog.projectId = projectId
            grabberDialog.show()
            grabberDialog.raise()
            grabberDialog.requestActivate()
        }
    }

    GrabberScheduleDialog { id: grabberScheduleDialog; transientParent: root }

    GrabberStatisticsDialog { id: grabberStatisticsDialog; transientParent: root }

    // ── Statistics Dialog ─────────────────────────────────────────────────────
    StatisticsDialog { id: statisticsDialog; transientParent: root }

    // ── Browser Integration Dialog ────────────────────────────────────────────
    BrowserIntegrationDialog { id: browserIntegrationDialog; transientParent: root }


    // ── Add Exception Dialog ──────────────────────────────────────────────────
    AddExceptionDialog { id: addExceptionDialog; transientParent: root }

    // ── Delete Done Confirm Dialog ────────────────────────────────────────────
    DeleteDoneConfirmDialog {
        id: deleteDoneConfirmDialog
        transientParent: root
        onConfirmed: (includeSeedingTorrents) => App.deleteAllCompleted(0, includeSeedingTorrents)
    }

    // ── File Properties Dialog ────────────────────────────────────────────────
    FilePropertiesDialog { id: filePropertiesDialog; transientParent: root }

// ── Columns Dialog ────────────────────────────────────────────────────────
    ColumnsDialog {
        id: columnsDialog
        transientParent: root
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
        interval: 6 * 60 * 60 * 1000  // Change tip every 6 hours
        repeat: true
        running: App.settings.showTips && root.tipsArray.length > 0
        onTriggered: {
            if (root.tipsArray.length > 0) {
                root.currentTipIndex = (root.currentTipIndex + 1) % root.tipsArray.length
            }
        }
    }

    Component.onCompleted: {
        loadTips()
        // When launched by the OS at login, start hidden in the tray instead of
        // showing the main window.  The tray icon is always visible regardless.
        if (typeof StartMinimized !== "undefined" && StartMinimized) {
            root.visible = false
        }
        // Allow the window manager to finish placement before we start saving
        // geometry so early xChanged/yChanged signals don't overwrite saved pos.
        Qt.callLater(function() { root._geometrySaveReady = true })
    }

    function loadTips() {
        // Load tips from embedded Qt resources via C++ to avoid QML XHR file-read restrictions.
        var paths = [
            "qrc:/tips.txt",
            "qrc:/qt/qml/com/stellar/app/tips.txt",
            "qrc:/qt/qml/com/stellar/app/app/qml/tips.txt",
            "qrc:/com/stellar/app/tips.txt"
        ]

        for (var i = 0; i < paths.length; i++) {
            try {
                var text = App.readTextResource(paths[i]).trim()
                if (text.length > 0) {
                    root.tipsArray = text.split(/\n/).filter(function(line) { return line.trim().length > 0 })
                    root.currentTipIndex = Math.floor(Math.random() * root.tipsArray.length)
                    console.log("Tips loaded from " + paths[i] + ": " + root.tipsArray.length + " tips")
                    return
                }
            } catch (e) {
                // Try next path
            }
        }
        console.warn("Could not load tips.txt from any path")
    }

    Connections {
        target: App.settings
        function onShowTipsChanged() {
            if (App.settings.showTips && root.tipsArray.length > 0) {
                // Show a new tip immediately when enabled
                root.currentTipIndex = Math.floor(Math.random() * root.tipsArray.length)
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

        // Shared compact MenuItem delegate used by all drop-down menus.
        // Dense Material gives 24px items; we trim to 22px with smaller font.
        component CompactMenuItem: MenuItem {
            id: _cmi
            implicitHeight: 22
            height: 22
            topPadding: 0; bottomPadding: 0; verticalPadding: 0
            leftPadding: 12; rightPadding: 12
            spacing: 0
            font.pixelSize: 12
            indicator: Item { width: 0; height: 0 }
            arrow: Text {
                x: _cmi.width - width - 8
                anchors.verticalCenter: parent ? parent.verticalCenter : undefined
                text: "▶"
                font.pixelSize: 8
                color: "#888888"
                visible: _cmi.subMenu !== null
            }
            contentItem: Text {
                text: _cmi.text
                font: _cmi.font
                color: _cmi.enabled ? "#d0d0d0" : "#666666"
                verticalAlignment: Text.AlignVCenter
                elide: Text.ElideRight
            }
            background: Rectangle {
                implicitHeight: 22
                color: _cmi.highlighted ? "#1e3a6e" : "transparent"
            }
        }

        delegate: MenuBarItem {
            // Equal 12px side padding on every menu title for even spacing
            verticalPadding: 2
            leftPadding: 12
            rightPadding: 12
            contentItem: Text {
                text: parent.text
                font: parent.font
                color: "#d0d0d0"
                verticalAlignment: Text.AlignVCenter
            }
            background: Rectangle {
                implicitHeight: 24
                color: parent.highlighted ? "#1e3a6e" : "transparent"
            }
        }

        Menu {
            title: qsTr("Tasks")
            delegate: CompactMenuItem
            implicitWidth: 200
            topPadding: 0; bottomPadding: 0
            Action { text: qsTr("Add URL…");       shortcut: "Ctrl+N";       onTriggered: { addUrlDialog.show(); addUrlDialog.raise() } }
            Action { text: qsTr("Add Torrent File…"); shortcut: "Ctrl+Shift+T"; onTriggered: addTorrentFileDialog.open() }
            Action { text: qsTr("Add Batch URLs…"); shortcut: "Ctrl+Shift+N"; onTriggered: { batchDownloadDialog.show(); batchDownloadDialog.raise() } }
            MenuSeparator {}
            Action { text: qsTr("Exit");            shortcut: "Ctrl+Q";       onTriggered: root.quitApp() }
        }
        Menu {
            title: qsTr("File")
            delegate: CompactMenuItem
            implicitWidth: 200
            topPadding: 0; bottomPadding: 0
            Action {
                text: qsTr("Open Folder"); 
                onTriggered: { var item = root.selectedDownloadItem; if (item && item.status === "Completed") App.openFolder(item.id) }
                enabled: root.selectedDownloadItem && root.selectedDownloadItem.status === "Completed"
            }
            Action { 
                text: qsTr("Open File"); 
                onTriggered: { var item = root.selectedDownloadItem; if (item && item.status === "Completed") App.openFile(item.id) }
                enabled: root.selectedDownloadItem && root.selectedDownloadItem.status === "Completed"
            }
            MenuSeparator {}
            Action { 
                text: qsTr("Download Now"); 
                onTriggered: { var item = root.selectedDownloadItem; if (item && item.status === "Paused") App.resumeDownload(item.id) }
                enabled: root.selectedDownloadItem && root.selectedDownloadItem.status === "Paused"
            }
            Action { 
                text: qsTr("Stop Download"); 
                onTriggered: { var item = root.selectedDownloadItem; if (item && (item.status === "Downloading" || item.status === "Queued")) App.pauseDownload(item.id) }
                enabled: root.selectedDownloadItem && (root.selectedDownloadItem.status === "Downloading" || root.selectedDownloadItem.status === "Queued")
            }
            Action { 
                text: qsTr("Remove"); 
                onTriggered: root.selectedDownloadItem ? downloadTable.deleteSelected() : null
                enabled: root.selectedDownloadItem !== null
            }
            Action { 
                text: qsTr("Redownload"); 
                onTriggered: { var item = root.selectedDownloadItem; if (item) App.redownload(item.id) }
                enabled: root.selectedDownloadItem !== null
            }
            Action {
                text: qsTr("Export .torrent…")
                onTriggered: {
                    root.pendingTorrentExportIds = downloadTable.selectedTorrentIds()
                    if (root.pendingTorrentExportIds.length > 0)
                        exportTorrentFolderDialog.open()
                }
                enabled: root.selectedTorrentCount > 0
            }
        }
        Menu {
            title: qsTr("Downloads")
            delegate: CompactMenuItem
            implicitWidth: 200
            topPadding: 0; bottomPadding: 0
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
                    delegate: MenuItem {
                        visible: queueId !== "download-limits"
                        text: queueName || ""
                        onTriggered: App.startQueue(queueId)
                    }
                }
            }
            Menu {
                title: qsTr("Stop Queue")
                Repeater {
                    model: App.queueModel
                    delegate: MenuItem {
                        visible: queueId !== "download-limits"
                        text: queueName || ""
                        onTriggered: App.stopQueue(queueId)
                    }
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
            delegate: CompactMenuItem
            implicitWidth: 200
            topPadding: 0; bottomPadding: 0
            Action {
                text: (sidebar && sidebar.visible) ? qsTr("Hide Categories") : qsTr("Show Categories")
                onTriggered: if (sidebar) sidebar.visible = !sidebar.visible
            }
            MenuSeparator {}
            Action {
                text: qsTr("Statistics…")
                onTriggered: { statisticsDialog.show(); statisticsDialog.raise(); statisticsDialog.requestActivate() }
            }
            MenuSeparator {}
            Menu {
                title: qsTr("Arrange Files")
                Action { text: qsTr("By Order Of Addition");  onTriggered: App.sortDownloads("added", true) }
                Action { text: qsTr("By File Name");          onTriggered: App.sortDownloads("name", true) }
                Action { text: qsTr("By Size");               onTriggered: App.sortDownloads("size", true) }
                Action { text: qsTr("By Status");             onTriggered: App.sortDownloads("status", true) }
                Action { text: qsTr("By Time Left");          onTriggered: App.sortDownloads("timeleft", true) }
                Action { text: qsTr("By Transfer Rate");      onTriggered: App.sortDownloads("speed", false) }
                Action { text: qsTr("By Last Try Date");      onTriggered: App.sortDownloads("lasttry", false) }
                Action { text: qsTr("By Description");        onTriggered: App.sortDownloads("description", true) }
                Action { text: qsTr("By Save Path");          onTriggered: App.sortDownloads("saveto", true) }
                Action { text: qsTr("By Referer");            onTriggered: App.sortDownloads("referrer", true) }
                Action { text: qsTr("By Parent Web Page");    onTriggered: App.sortDownloads("parenturl", true) }
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
            delegate: CompactMenuItem
            implicitWidth: 200
            topPadding: 0; bottomPadding: 0
            Action { text: qsTr("Preferences…"); shortcut: "Ctrl+,"; onTriggered: settingsDialog.show() }
            Action { text: qsTr("Scheduler");    onTriggered: schedulerDialog.show() }
            Menu {
                title: qsTr("Speed Limiter")
                delegate: CompactMenuItem
                implicitWidth: 200
                Action { text: (App.settings.globalSpeedLimitKBps > 0 ? "✓ " : "    ") + qsTr("Turn On");  onTriggered: App.enableSpeedLimiter() }
                Action { text: (App.settings.globalSpeedLimitKBps === 0 ? "✓ " : "    ") + qsTr("Turn Off"); onTriggered: App.disableSpeedLimiter() }
                MenuSeparator {}
                Action { text: qsTr("Settings…"); onTriggered: { settingsDialog.initialPage = 4; settingsDialog.show() } }
            }
        }
        Menu {
            title: qsTr("RSS")
            delegate: CompactMenuItem
            implicitWidth: 210
            topPadding: 0; bottomPadding: 0
            Action { text: qsTr("Open RSS Reader"); onTriggered: root.showRssWindow() }
            Action { text: qsTr("Refresh All Feeds"); onTriggered: App.rssManager.refreshAll() }
            Action { text: qsTr("Mark All Items Read"); onTriggered: App.rssManager.markAllRead() }
        }
        Menu {
            title: qsTr("Help")
            delegate: CompactMenuItem
            implicitWidth: 200
            topPadding: 0; bottomPadding: 0
            Action { text: qsTr("Check for Updates"); onTriggered: App.checkForUpdates(true) }
            MenuSeparator {}
            Action { text: qsTr("About Stellar"); onTriggered: root.showSettingsPage(10) }
            MenuSeparator {}
            Menu {
                title: qsTr("Browser Integration")
                delegate: CompactMenuItem
                implicitWidth: 200
                Action { text: qsTr("Firefox Extension…"); onTriggered: { browserIntegrationDialog.show(); browserIntegrationDialog.raise() } }
                MenuSeparator {}
                Action { text: qsTr("Open Extension Folder"); onTriggered: App.openExtensionFolder() }
                Action { text: qsTr("Browser Settings…"); onTriggered: root.showSettingsPage(3) }
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
        property var dragDownloadIds: []
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
            downloadTable: downloadTable
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
            onGrabberClicked: {
                grabberDialog.projectId = ""
                grabberDialog.show()
                grabberDialog.raise()
                grabberDialog.requestActivate()
            }
            onSearchEngineClicked: {
                root.showTorrentSearchWindow()
            }
            onRssClicked: {
                root.showRssWindow()
            }
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
                onCategorySelected: (catId) => {
                    App.selectedCategory = catId
                    // Clear selection so toolbar enabled-states re-evaluate against
                    // the new (possibly empty) filtered view — otherwise Resume/Delete/etc.
                    // stay lit when the newly shown category has no items.
                    downloadTable._setSelection({})
                    downloadTable._anchorRow = -1
                }
                onQueueSelected: (queueId) => {
                    App.selectedQueue = queueId
                    downloadTable._setSelection({})
                    downloadTable._anchorRow = -1
                }
                onGrabberProjectSelected: (projectId) => {
                    App.selectedCategory = projectId
                    downloadTable._setSelection({})
                    downloadTable._anchorRow = -1
                }
                onEditGrabberProjectRequested: (projectId) => {
                    grabberDialog.projectId = projectId
                    grabberDialog.show()
                    grabberDialog.raise()
                    grabberDialog.requestActivate()
                }
                onDeleteGrabberProjectRequested: (projectId) => {
                    App.deleteGrabberProject(projectId)
                    if (App.selectedCategory === projectId)
                        App.selectedCategory = "all"
                    downloadTable._setSelection({})
                    downloadTable._anchorRow = -1
                }
            }

            DownloadTable {
                id: downloadTable
                Layout.fillWidth: true
                Layout.fillHeight: true
                categoryDragProxy: dragProxy
                onExportTorrentsRequested: (downloadIds) => {
                    root.pendingTorrentExportIds = downloadIds
                    if (downloadIds && downloadIds.length > 0)
                        exportTorrentFolderDialog.open()
                }
                onOpenProgressRequested: (item) => {
                    progressDialog.item       = item
                    progressDialog.downloadId = item ? item.id : ""
                    progressDialog.show()
                    progressDialog.raise()
                }
                onOpenPropertiesRequested: (item) => {
                    if (!item)
                        return
                    if (!item.isTorrent && (item.status === "Downloading" || item.status === "Assembling")) {
                        progressDialog.item       = item
                        progressDialog.downloadId = item.id
                        progressDialog.show()
                        progressDialog.raise()
                        return
                    }
                    var changingType = filePropertiesDialog.visible
                        && (!!filePropertiesDialog.item && !!filePropertiesDialog.item.isTorrent) !== !!item.isTorrent
                    if (changingType) {
                        // Close the window so Qt destroys the old layout state, then
                        // reopen next frame with the new item already set.
                        filePropertiesDialog.close()
                        var pendingItem = item
                        Qt.callLater(function() {
                            filePropertiesDialog.item = pendingItem
                            filePropertiesDialog.show()
                            filePropertiesDialog.raise()
                        })
                    } else {
                        filePropertiesDialog.item = item
                        filePropertiesDialog.show()
                        filePropertiesDialog.raise()
                    }
                }
                onOpenColumnsSettingsRequested: {
                    columnsDialog.columnDefs = downloadTable.columnDefs.slice()
                    columnsDialog.show()
                    columnsDialog.raise()
                }
            }
        }

        StatusBar {
            id: statusBar
            Layout.fillWidth: true
            activeCount:    App.activeDownloads
            completedCount: App.completedDownloads
            // _selectionVersion is the reactive trigger; Object.keys gives the live count.
            selectedCount: { downloadTable._selectionVersion; return Object.keys(downloadTable._selectedRows).length }
            tipsArray:      root.tipsArray
            currentTipIndex: root.currentTipIndex
            showTips:       App.settings.showTips
            onNextTip: {
                if (root.tipsArray.length > 0) {
                    root.currentTipIndex = (root.currentTipIndex + 1) % root.tipsArray.length
                }
            }
            onCloseTips: {
                App.settings.showTips = false
            }
            onStatisticsRequested: {
                statisticsDialog.show()
                statisticsDialog.raise()
                statisticsDialog.requestActivate()
            }
        }
    }
}
