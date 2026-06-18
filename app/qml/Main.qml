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
import Qt.labs.platform
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts
import com.stellar.app 1.0

ApplicationWindow {
    id: root
    // Start hidden when launched at login (--minimized) or cold-started by the
    // native host purely to service an intercepted download (LaunchedForDownload).
    // Setting the initial value here — rather than flipping visible=false in
    // Component.onCompleted — avoids a one-frame flash where the window paints
    // then immediately hides.
    visible: !((typeof StartMinimized !== "undefined" && StartMinimized)
               || (typeof LaunchedForDownload !== "undefined" && LaunchedForDownload))
    width: Math.max(minimumWidth, App.settings.mainWindowWidth > 0 ? App.settings.mainWindowWidth : 1100)
    height: Math.max(minimumHeight, App.settings.mainWindowHeight > 0 ? App.settings.mainWindowHeight : 680)
    // ── Restore saved position; -1 means first run let the OS centre the window naturally. ──
    x: App.settings.mainWindowX >= 0 ? App.settings.mainWindowX : x
    y: App.settings.mainWindowY >= 0 ? App.settings.mainWindowY : y
    minimumWidth: 100
    minimumHeight: 100
    title: {
        const prefix = App.sessionPaused ? "[" + qsTr("PAUSED") + "] " : ""
        const base = qsTr("Stellar Download Manager") + " " + App.appVersion + " Beta"
        if (!App.settings.speedInTitleBar)
            return prefix + base
        function fmt(bps) {
            if (bps >= 1000000)
                return (bps / 1000000).toFixed(1) + " MB/s"
            if (bps >= 1000)
                return Math.round(bps / 1000) + " KB/s"
            return bps + " B/s"
        }
        return prefix + "[↓ " + fmt(App.totalDownSpeed) + "  ↑ " + fmt(App.totalUpSpeed) + "] " + base
    }

    Material.theme: ColorPalette.materialTheme
    Material.foreground: ColorPalette.textPrimary
    Material.background: ColorPalette.materialWindowBg
    Material.primary: ColorPalette.dividerBg
    Material.accent: "#5588cc"

    // Keep the native Windows caption (title bar) in sync with the app theme.
    // Dark caption when dark mode, light caption otherwise.
    onVisibleChanged: {
        if (visible) App.setWindowDarkTitleBar(root, App.settings.darkMode)
        _syncTableActive()
    }

    // Suspend per-tick download-table repaints while the window is hidden
    // (close-to-tray) or minimized. Without this the dataChanged churn from many
    // seeding torrents queues up and floods the scene on restore, freezing the
    // GUI for several seconds. Re-activating repaints the whole table once.
    function _syncTableActive() {
        if (!App.downloadModel) return
        var active = visible && visibility !== Window.Minimized
        // Reactivation triggers one full-table catch-up repaint. Defer it one
        // frame (Qt.callLater) so the window maps first and feels instant on a
        // tray restore; the table repaint lands the following frame. Deactivation
        // must stay synchronous so no repaints leak through while hiding.
        if (active)
            Qt.callLater(function() { App.downloadModel.setUiActive(true) })
        else
            App.downloadModel.setUiActive(false)
    }
    onVisibilityChanged: _syncTableActive()

    Connections {
        target: App.settings
        ignoreUnknownSignals: true
        function onDarkModeChanged() { App.applyDarkTitleBarToAllWindows(App.settings.darkMode) }
    }

    // Set to true after the window has been shown at least once so that early
    // geometry signals during window creation don't overwrite saved position.
    property bool _geometrySaveReady: false
    property bool _torrentFileDragActive: false
    readonly property int settingsPageBrowser: 3
    readonly property int settingsPageSpeedLimiter: 4
    readonly property int settingsPageGeneral: 6
    readonly property int settingsPageAbout: 12

    // ── Minimize to tray on close ────────────────────────────────────────
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

    function toggleSessionPause() {
        if (App.sessionPaused)
            App.resumeSession()
        else
            App.pauseSession()
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
    }

    // ── Map of downloadId DownloadProgressDialog instances ───────────────
    property var _progressDialogs: ({})

    function _getOrCreateProgressDialog(item) {
        if (!item) return null
        var id = item.id || ""
        if (_progressDialogs[id]) return _progressDialogs[id]
        var dlg = progressDialogComponent.createObject(root, { downloadId: id, item: item })
        dlg.minimizedToTray.connect(function(dlgId) {
            _updateDownloadsTray()
        })
        dlg.openSettingsRequested.connect(function(page) {
            root.showSettingsPage(page)
        })
        dlg.closing.connect(function(close) {
            // Closing (X button) destroys and removes from map
            Qt.callLater(function() {
                if (_progressDialogs[id]) {
                    _progressDialogs[id].destroy()
                    delete _progressDialogs[id]
                    _progressDialogs = _progressDialogs  // trigger binding refresh
                    _updateDownloadsTray()
                }
            })
        })
        _progressDialogs[id] = dlg
        _progressDialogs = _progressDialogs
        return dlg
    }

    function showDownloadProgressForItem(item) {
        if (!item) return
        // yt-dlp channel/playlist downloads (the container row OR any of its child
        // video rows) have no HTTP segmented-progress; their multi-item batch
        // window is the only meaningful progress view. Redirect here so no caller
        // path (double-click, properties, open-progress) can leak the HTTP dialog.
        if (item.isYtdlp && (item.ytdlpPlaylistMode
                || (item.parentId && item.parentId.length > 0))) {
            var batchId = item.ytdlpPlaylistMode ? item.id : item.parentId
            App.showYtdlpBatchForItem(batchId)
            showAndActivate(ytdlpBatchWindow)
            return
        }
        // Never open the progress window for an already-finished download — the
        // complete dialog handles those. Guards a race where a fast (e.g. numbered
        // duplicate) download completes before the deferred show() runs, leaving an
        // orphan progress window that onDownloadCompleted already passed by.
        if (item.status === "Completed") return
        var dlg = _getOrCreateProgressDialog(item)
        if (dlg) {
            dlg.item = item
            showAndActivate(dlg)
            _updateDownloadsTray()
        }
    }

    function _updateDownloadsTray() {
        var ids = Object.keys(_progressDialogs)
        var anyMinimized = false
        for (var i = 0; i < ids.length; i++) {
            var d = _progressDialogs[ids[i]]
            // Only count dialogs that are hidden AND still actively downloading.
            // A dialog hidden because the download completed is not "minimized to tray".
            if (d && !d.visible && d.item) {
                var s = d.item.status
                if (s === "Downloading" || s === "Queued" || s === "Assembling" || s === "Paused")
                    anyMinimized = true
            }
            if (anyMinimized) break
        }
        if (anyMinimized) {
            App.showDownloadsTray()
            App.setDownloadsTrayToolTip(qsTr("SDM downloads"))
        } else {
            App.hideDownloadsTray()
        }
        downloadsTrayMenu.updateEntries()
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

    function extractMagnetDisplayName(url) {
        var s = (url === undefined || url === null) ? "" : String(url)
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

    // ── Map of downloadId → TorrentMetadataDialog instances ──────────────
    // One window per torrent so several can be open at once (mirrors the
    // _progressDialogs pattern). Each is a top-level Window; closing destroys it.
    property var _torrentMetaDialogs: ({})

    function _getOrCreateTorrentMetaDialog(downloadId) {
        if (!downloadId || downloadId.length === 0)
            return null
        if (_torrentMetaDialogs[downloadId])
            return _torrentMetaDialogs[downloadId]
        var dlg = torrentMetadataDialogComponent.createObject(root, { downloadId: downloadId, ownerWindow: root })
        if (!dlg)
            return null
        dlg.closing.connect(function(close) {
            Qt.callLater(function() {
                if (_torrentMetaDialogs[downloadId]) {
                    _torrentMetaDialogs[downloadId].destroy()
                    delete _torrentMetaDialogs[downloadId]
                    _torrentMetaDialogs = _torrentMetaDialogs
                }
            })
        })
        _torrentMetaDialogs[downloadId] = dlg
        _torrentMetaDialogs = _torrentMetaDialogs
        return dlg
    }

    function showTorrentMetadataDialog(downloadId, startWhenReady) {
        if (!downloadId || downloadId.length === 0)
            return
        var dlg = _getOrCreateTorrentMetaDialog(downloadId)
        if (!dlg)
            return
        dlg.pendingSourceLabel = ""
        dlg.startWhenReady = startWhenReady
        dlg.show()
        dlg.raise()
        dlg.requestActivate()
    }

    function showTorrentMetadataDialogForFile(torrentFilePath, saveDir, category, description, startWhenReady) {
        if (!torrentFilePath || torrentFilePath.length === 0)
            return
        var pendingLabel = torrentFilePath.split(/[/\\]/).pop()
        Qt.callLater(function() {
            var torrentFileId = App.addTorrentFile(torrentFilePath, saveDir, category || "", description || "", false, "")
            if (!torrentFileId || torrentFileId.length === 0)
                return // duplicate — torrentDuplicateDetected signal already fired
            var dlg = _getOrCreateTorrentMetaDialog(torrentFileId)
            if (!dlg)
                return
            dlg.pendingSourceLabel = pendingLabel
            dlg.savePath = saveDir
            dlg.category = category || ""
            dlg.description = description || ""
            dlg.startWhenReady = startWhenReady
            dlg.show()
            dlg.raise()
            dlg.requestActivate()
        })
    }

    function localPathFromDroppedUrl(urlValue) {
        var text = (urlValue || "").toString()
        if (text.length === 0 || !/^file:/i.test(text))
            return ""

        var isUncPath = /^file:\/\/[^/]/i.test(text)
        var path = decodeURIComponent(text).replace(/^file:\/\//i, "")
        if (isUncPath)
            path = "//" + path
        else if (Qt.platform.os === "windows" && /^\/[A-Za-z]:/.test(path))
            path = path.substring(1)
        return path
    }

    function isTorrentFilePath(path) {
        return /\.torrent$/i.test((path || "").trim())
    }

    function firstDroppedTorrentPath(drop) {
        if (!drop)
            return ""
        if (drop.source)
            return ""

        var urls = drop.urls || []
        for (var i = 0; i < urls.length; ++i) {
            var localPath = root.localPathFromDroppedUrl(urls[i])
            if (root.isTorrentFilePath(localPath))
                return localPath
        }

        var textPath = root.localPathFromDroppedUrl(drop.text || "")
        if (root.isTorrentFilePath(textPath))
            return textPath
        return ""
    }

    function updateTorrentDropState(drag) {
        root._torrentFileDragActive = root.firstDroppedTorrentPath(drag).length > 0
    }

    function handleTorrentFileDrop(drop) {
        var torrentPath = root.firstDroppedTorrentPath(drop)
        root._torrentFileDragActive = false
        if (torrentPath.length === 0)
            return
        root.showTorrentMetadataDialogForFile(torrentPath, root.torrentSaveDirFromInputPath(App.settings.defaultSavePath), "", "", true)
        if (drop.acceptProposedAction)
            drop.acceptProposedAction()
    }

    MessageDialog {
        id: appErrorDialog
    title: qsTr("Stellar")
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
        title: qsTr("Browser Cookies Required")
        color: ColorPalette.cardBg
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
                text: qsTr("This YouTube download looks like it needs login cookies.")
                color: ColorPalette.textPrimary
                font.pixelSize: 14 * App.fontScale
                font.weight: Font.Medium
                wrapMode: Text.WordWrap
            }

            Text {
                Layout.fillWidth: true
                text: ytdlpCookieRetryDialog.errorReason
                color: ColorPalette.textSecond
                font.pixelSize: 11 * App.fontScale
                wrapMode: Text.WordWrap
            }

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 64
                radius: 4
                color: ColorPalette.infoBoxBg
                border.color: ColorPalette.infoBoxBorder

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 10
                    spacing: 6

                    Text {
                        text: qsTr("Cookies from browser:")
                        color: ColorPalette.infoBoxText
                        font.pixelSize: 11 * App.fontScale
                    }

                    StyledComboBox {
                        id: cookieBrowserCombo
                        Layout.preferredWidth: 130
                        model: ["Chrome","Firefox","Edge","Brave","Opera","Vivaldi","Safari"]
                        contentItem: Text {
                            leftPadding: 8
                            text: cookieBrowserCombo.displayText
                            color: ColorPalette.textPrimary
                            font: cookieBrowserCombo.font
                            verticalAlignment: Text.AlignVCenter
                        }
                        background: Rectangle {
                            color: ColorPalette.inputBg
                            border.color: cookieBrowserCombo.activeFocus ? "#4488dd" : ColorPalette.border
                            radius: 3
                        }
                        delegate: ItemDelegate {
                            id: cookieBrowserDelegate
                            width: cookieBrowserCombo.width
                            height: 24
                            contentItem: Text {
                                text: modelData
                                color: ColorPalette.textPrimary
                                font.pixelSize: 11 * App.fontScale
                                verticalAlignment: Text.AlignVCenter
                                leftPadding: 8
                            }
                            background: Rectangle { color: cookieBrowserDelegate.hovered ? "#2a3a5a" : ColorPalette.inputBg }
                        }
                        popup: Popup {
                            y: cookieBrowserCombo.height + 2
                            width: cookieBrowserCombo.width
                            implicitHeight: contentItem.implicitHeight + 4
                            padding: 2
                            background: Rectangle { color: ColorPalette.inputBg; border.color: ColorPalette.border; radius: 3 }
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
                text: qsTr("Stellar will retry the same yt-dlp item with that browser's cookies.")
                color: "#667788"
                font.pixelSize: 10 * App.fontScale
                wrapMode: Text.WordWrap
            }

            Item { Layout.fillHeight: true }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Item { Layout.fillWidth: true }

                DlgButton {
                    text: qsTr("Cancel")
                    onClicked: ytdlpCookieRetryDialog.close()
                }

                DlgButton {
                    text: qsTr("Retry Download")
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
        function onRestartRequested() { root.quitApp() }
        function onErrorOccurred(message) {
            appErrorDialog.text = message && message.length > 0 ? message : "An unexpected error occurred."
            appErrorDialog.open()
        }
        function onYtdlpCookieRetryRequested(downloadId, reason, suggestedBrowser) {
            var configured = App.settings.ytdlpDefaultCookieBrowser.toLowerCase()
            if (configured.length > 0 && configured !== "none") {
                App.retryYtdlpWithBrowserCookies(downloadId, configured)
            } else {
                ytdlpCookieRetryDialog._openFor(downloadId, reason, suggestedBrowser)
            }
        }
        function onFileDeletedWarningDetected(downloadId, filename) {
            fileDeletedWarningDialog._filename = filename
            fileDeletedWarningDialog.show()
            fileDeletedWarningDialog.raise()
            fileDeletedWarningDialog.requestActivate()
        }
    }

    // ── Debounce geometry saves writing QSettings on every pixel of a drag ──
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
        if (isQuitting)
            return
        if (App.settings.closeToTray) {
            close.accepted = false
            root.hide()
            return
        }
        // closeToTray off: closing the main window quits the app. Done
        // explicitly because quitOnLastWindowClosed is disabled (so that
        // closing a transient dialog — e.g. the cold-start New Download
        // dialog while the main window is hidden — never quits Stellar).
        close.accepted = false
        root.quitApp()
    }

    function quitApp() {
        isQuitting = true
        root.hide()
        App.requestQuit()
    }

    // ── Tray context menu (standalone window so it works when main window is hidden) ──
    Window {
        id: trayMenu
        transientParent: null
        flags: Qt.Tool | Qt.FramelessWindowHint | Qt.WindowStaysOnTopHint
        width: 180
        height: menuCol.implicitHeight + 2
        color: ColorPalette.cardBg
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
            border.color: ColorPalette.border
            border.width: 1
        }

        Column {
            id: menuCol
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 1 }

            TrayMenuItem { label: qsTr("Open Stellar"); bold: true; onClicked: { trayMenu.visible = false; root.show(); root.raise(); root.requestActivate() } }
            TrayMenuItem { label: qsTr("Add URL…");     onClicked: { trayMenu.visible = false; root.show(); root.raise(); addUrlDialog.show(); addUrlDialog.raise() } }
            Rectangle { width: parent.width; height: 1; color: ColorPalette.border }
            TrayMenuItem { label: qsTr("GitHub");        onClicked: { trayMenu.visible = false; App.openExternalUrl("https://github.com/Ninka-Rex/Stellar") } }
            TrayMenuItem { label: qsTr("About Stellar"); onClicked: { trayMenu.visible = false; root.show(); root.raise(); root.showSettingsPage(root.settingsPageAbout) } }
            Rectangle { width: parent.width; height: 1; color: ColorPalette.border }
            TrayMenuItem { label: ((App.settings.globalSpeedLimitKBps > 0 || App.settings.globalUploadLimitKBps > 0) ? "✓" : "") + qsTr("Speed Limiter"); onClicked: { trayMenu.visible = false; if (App.settings.globalSpeedLimitKBps > 0 || App.settings.globalUploadLimitKBps > 0) App.disableSpeedLimiter(); else App.enableSpeedLimiter() } }
            TrayMenuItem { label: qsTr("Speed Limiter Settings…"); onClicked: { trayMenu.visible = false; root.show(); root.raise(); root.showSettingsPage(root.settingsPageSpeedLimiter) } }
            Rectangle { width: parent.width; height: 1; color: ColorPalette.border }
            TrayMenuItem { label: (App.sessionPaused ? "✓" : "") + qsTr("Pause Session"); onClicked: { trayMenu.visible = false; if (App.sessionPaused) App.resumeSession(); else App.pauseSession() } }
            TrayMenuItem { label: qsTr("Exit Stellar");  onClicked: { trayMenu.visible = false; root.quitApp() } }
        }
    }

    // ── Downloads tray context menu ──────────────────────────────────────
    Window {
        id: downloadsTrayMenu
        transientParent: null
        flags: Qt.Tool | Qt.FramelessWindowHint | Qt.WindowStaysOnTopHint
        width: 220
        height: downloadsTrayCol.implicitHeight + 2
        color: ColorPalette.cardBg
        visible: false

        function popup(screenX, screenY) {
            updateEntries()
            x = screenX
            y = screenY - height
            visible = true
            raise()
            requestActivate()
        }

        function updateEntries() {
            var ids = Object.keys(root._progressDialogs)
            // Rebuild the per-download repeater model
            perDownloadModel.clear()
            for (var i = 0; i < ids.length; i++) {
                var d = root._progressDialogs[ids[i]]
                if (d && d.item) {
                    perDownloadModel.append({ dlId: ids[i], dlName: d.item.filename })
                }
            }
        }

        onActiveChanged: {
            if (!active && visible) visible = false
        }

        Rectangle {
            anchors.fill: parent
            color: "transparent"
            border.color: ColorPalette.border
            border.width: 1
        }

        Column {
            id: downloadsTrayCol
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 1 }

            TrayMenuItem {
                label: "Restore all download windows"
                bold: true
                onClicked: {
                    downloadsTrayMenu.visible = false
                    var ids = Object.keys(root._progressDialogs)
                    for (var i = 0; i < ids.length; i++) {
                        var d = root._progressDialogs[ids[i]]
                        if (d) { d.show(); d.raise(); d.requestActivate() }
                    }
                    root._updateDownloadsTray()
                }
            }

            Rectangle { width: parent.width; height: 1; color: ColorPalette.border }

            ListModel { id: perDownloadModel }

            Repeater {
                model: perDownloadModel
                delegate: TrayMenuItem {
                    label: dlName
                    onClicked: {
                        downloadsTrayMenu.visible = false
                        var d = root._progressDialogs[dlId]
                        if (d) { d.show(); d.raise(); d.requestActivate() }
                        root._updateDownloadsTray()
                    }
                }
            }
        }
    }

    // ── Component for creating per-download progress dialogs ─────────────
    Component {
        id: progressDialogComponent
        DownloadProgressDialog {}
    }

    // ── Controller signals ───────────────────────────────────────────────
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
            // ── queue-managed downloads queues run silently in the background. ──
            if (!item || item.status === "Paused") return
            if (item.isTorrent) return
            if (item.isYtdlp && item.ytdlpPlaylistMode) return
            if (item.queueId && item.queueId.length > 0) return
            if (item.category && App.isGrabberProjectId(item.category)) return
            // Defer show() by one event-loop cycle so any dialog that triggered
            // the download (e.g. DownloadFileInfoDialog) finishes closing first.
            // Without this, Windows brings the main window to the front when the
            // triggering dialog closes, pushing progressDialog behind it.
            Qt.callLater(function() {
                root.showDownloadProgressForItem(item)
            })
        }
        function onDownloadCompleted(item) {
            if (item) {
                var dlg = root._progressDialogs[item.id]
                if (dlg && dlg.visible) dlg.hide()
                root._updateDownloadsTray()
            }
            // ── Torrents go Completed Seeding; never show the complete dialog for them. ──
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
            App.openExternalUrl("https://github.com/Ninka-Rex/Stellar")
        }
        function onTrayAboutRequested() {
            root.show(); root.raise()
            root.showSettingsPage(root.settingsPageAbout)
        }
        function onTraySpeedLimiterRequested() {
            root.show(); root.raise()
            root.showSettingsPage(root.settingsPageSpeedLimiter)
        }
        function onContextMenuRequested(x, y) {
            trayMenu.popup(x, y)
        }
        function onDownloadsContextMenuRequested(x, y) {
            downloadsTrayMenu.popup(x, y)
        }
        function onDownloadsShowAllRequested() {
            var ids = Object.keys(root._progressDialogs)
            for (var i = 0; i < ids.length; i++) {
                var d = root._progressDialogs[ids[i]]
                if (d) { d.show(); d.raise(); d.requestActivate() }
            }
            root._updateDownloadsTray()
        }
        function onUpdateDialogRequested() {
            updateAvailableDialog.showFromChangelog()
        }
        function onUpdateUpToDate() {
            quickUpdateDialog.messageText = "You are using the latest version of Stellar Download Manager. Please check back again for updates at a later time."
            quickUpdateDialog.show()
            quickUpdateDialog.raise()
            quickUpdateDialog.requestActivate()
        }
        function onUpdateError(message) {
            // The update dialog shows the error inline when it's open; avoid a
            // duplicate modal popup in that case.
            if (updateAvailableDialog.visible)
                return
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
        function onTorrentSupportDisabled(pendingUri) {
            torrentEnableNotice._pendingUri = pendingUri
            torrentEnableNotice.open()
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
                    // ── Ask show duplicate dialog ────────────────────────
                    duplicateDialog.existingItem = existing
                    duplicateDialog._pendingUrl  = url
                    showAndActivate(duplicateDialog)
                } else {
                    _handleDuplicateAction(action, false, existing, url)
                }
                return
            }
            // ── Firefox passes the full local save path as filename extract basename only. ──
            var urlName = url.split("/").pop().split("?")[0] || "download"
            var hasExt = urlName.indexOf('.') > 0
            var name = (filename.length > 0 ? filename.split(/[/\\]/).pop() : "")
                    || (hasExt ? urlName : "")
            // ── Display placeholder even when URL guess is bad dialog needs a label. ──
            var displayName = name || urlName
            var _cookies  = App.takePendingCookies(url)
            // ── No cookies from extension read from browser profiles on disk. ──
            if (_cookies.length === 0)
                _cookies = App.cookiesForUrl(url)
            // Store back so takePendingCookies() works at confirm time (addUrl path).
            if (_cookies.length > 0)
                App.setPendingCookies(url, _cookies)
            var _referrer = App.takePendingReferrer(url)
            var _pageUrl  = App.takePendingPageUrl(url)
            fileInfoDialog.pendingUrl      = url
            fileInfoDialog.pendingFilename = displayName
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

        // Multi-link selection from the browser extension → batch review dialog.
        function onImportLinksRequested(links) {
            var fileObjs = []
            for (var i = 0; i < links.length; ++i) {
                var l = links[i]
                if (!l || !l.url)
                    continue
                var _name = (l.name && l.name.length > 0)
                        ? l.name
                        : (l.url.split('/').pop().split('?')[0] || "")
                fileObjs.push({ name: _name, url: l.url, linkText: l.linkText || "" })
            }
            if (fileObjs.length === 0)
                return
            batchDownloadListDialog.files = fileObjs
            batchDownloadListDialog.isImport = true
            batchDownloadListDialog.show()
            batchDownloadListDialog.raise()
        }
    }

    // ── Grabber explore-finished: run completion actions ─────────────────
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

    // ── Grabber schedule checker (runs every 30 s) ───────────────────────
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

    // ── Clipboard URL monitoring react to signal from AppController ──────
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

    // ── Queue download limit exceeded ────────────────────────────────────
    Connections {
        target: App
        function onQueueDownloadLimitExceeded(queueId, queueName, usedMB, limitMB, limitHours, windowStart, resumeAt) {
            downloadLimitsExceededDialog.queueName   = queueName
            downloadLimitsExceededDialog.usedMB      = usedMB
            downloadLimitsExceededDialog.limitMB     = limitMB
            downloadLimitsExceededDialog.limitHours  = limitHours
            downloadLimitsExceededDialog.windowStart = windowStart
            downloadLimitsExceededDialog.resumeAt    = resumeAt
            downloadLimitsExceededDialog.show()
            downloadLimitsExceededDialog.raise()
            downloadLimitsExceededDialog.requestActivate()
        }
    }

    DownloadLimitsExceededDialog { id: downloadLimitsExceededDialog }

    // ── Speed limiter scheduler ──────────────────────────────────────────
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
                ? (nowTotal >= on24 && nowTotal < off24)          // e.g. 9 AM ▶€“ 5 PM
                : (nowTotal >= on24 || nowTotal < off24)           // e.g. 10 PM ▶€“ 6 AM
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

    // ── Add URL dialog (step 1) ──────────────────────────────────────────
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
                        showAndActivate(duplicateDialog)
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
        title: qsTr("Add Torrent File")
        fileMode: FileDialog.OpenFile
        nameFilters: [qsTr("Torrent files (*.torrent)"), qsTr("All files (*)")]
        onAccepted: {
            var path = file.toString()
                .replace(/^file:\/\/\//, "")
                .replace(/^file:\/\//, "")
            root._pendingTorrentFilePath = ""
            fileInfoDialog.pendingDownloadId = ""
            root.showTorrentMetadataDialogForFile(path, App.settings.defaultSavePath, "", "", true)
        }
    }

    FolderDialog {
        id: exportTorrentFolderDialog
        title: qsTr("Export .torrent Files")
        onAccepted: {
            if (!root.pendingTorrentExportIds || root.pendingTorrentExportIds.length === 0)
                return
            var dir = folder.toString()
                .replace(/^file:\/\/\//, "")
                .replace(/^file:\/\//, "")
            App.exportTorrentFilesToDirectory(root.pendingTorrentExportIds, dir)
            root.pendingTorrentExportIds = []
        }
        onRejected: root.pendingTorrentExportIds = []
    }

    // ── Import / Export file dialogs ─────────────────────────────────────

    FileDialog {
        id: exportEf2Dialog
        title: qsTr("Export Downloads")
        fileMode: FileDialog.SaveFile
        nameFilters: [qsTr("SDM Export File (*.ef2)")]
        defaultSuffix: "ef2"
        onAccepted: {
            var rawPath = file.toString()
                .replace(/^file:\/\/\//, "")
                .replace(/^file:\/\//, "")
            var items = root._pendingExportItems || []
            var content = ""
            for (var ei = 0; ei < items.length; ei++) {
                var it = items[ei]
                var url = it.url ? it.url.toString() : ""
                if (url.length === 0) continue
                content += "<\r\n" + url + "\r\n"
                var ref = it.referrer || ""
                if (ref.length > 0) content += "referer: " + ref + "\r\n"
                content += "User-Agent: Stellar/1.0\r\n>\r\n"
            }
            if (content.length > 0)
                App.writeTextFile(rawPath, content)
        }
    }

    FileDialog {
        id: exportTxtDialog
        title: qsTr("Export Downloads")
        fileMode: FileDialog.SaveFile
        nameFilters: [qsTr("Text file (*.txt)")]
        defaultSuffix: "txt"
        onAccepted: {
            var rawPath = file.toString()
                .replace(/^file:\/\/\//, "")
                .replace(/^file:\/\//, "")
            var items = root._pendingExportItems || []
            var content = ""
            for (var ei = 0; ei < items.length; ei++) {
                var it = items[ei]
                var url = it.url ? it.url.toString() : ""
                if (url.length === 0) continue
                content += url + "\r\n"
            }
            if (content.length > 0)
                App.writeTextFile(rawPath, content)
        }
    }

    FileDialog {
        id: importEf2Dialog
        title: qsTr("Import Downloads")
        fileMode: FileDialog.OpenFile
        nameFilters: [qsTr("SDM Export File (*.ef2)")]
        onAccepted: {
            var rawPath = file.toString()
                .replace(/^file:\/\/\//, "")
                .replace(/^file:\/\//, "")
            var text = App.readTextFile(rawPath)
            if (text.length === 0)
                return
            var urls = []
            // Parse .ef2: entries delimited by < ... >
            var entries = text.split('\n')
            var inEntry = false
            for (var ei = 0; ei < entries.length; ei++) {
                var line = entries[ei].replace(/\r$/, '').trim()
                if (line === '<') {
                    inEntry = true
                    continue
                }
                if (line === '>') {
                    inEntry = false
                    continue
                }
                if (inEntry && line.length > 0
                    && line.indexOf('referer:') !== 0
                    && line.indexOf('User-Agent:') !== 0) {
                    urls.push(line)
                    inEntry = false
                }
            }
            if (urls.length === 0)
                return
            var fileObjs = []
            for (var ui = 0; ui < urls.length; ui++) {
                var _url = urls[ui]
                var _name = ""
                if (_url.toLowerCase().startsWith("magnet:?"))
                    _name = extractMagnetDisplayName(_url)
                if (_name.length === 0)
                    _name = _url.split('/').pop().split('?')[0]
                fileObjs.push({ name: _name, url: _url })
            }
            batchDownloadListDialog.files = fileObjs
            batchDownloadListDialog.isImport = true
            batchDownloadListDialog.show()
            batchDownloadListDialog.raise()
        }
    }

    FileDialog {
        id: importTxtDialog
        title: qsTr("Import Downloads")
        fileMode: FileDialog.OpenFile
        nameFilters: [qsTr("Text file (*.txt)")]
        onAccepted: {
            var rawPath = file.toString()
                .replace(/^file:\/\/\//, "")
                .replace(/^file:\/\//, "")
            var text = App.readTextFile(rawPath)
            if (text.length === 0)
                return
            var urls = []
            // Parse .txt: one URL per line
            var lines = text.split(/\r?\n/)
            for (var ti = 0; ti < lines.length; ti++) {
                var trimmed = lines[ti].trim()
                if (trimmed.length > 0 && trimmed.indexOf('referer:') !== 0 && trimmed.indexOf('User-Agent:') !== 0)
                    urls.push(trimmed)
            }
            if (urls.length === 0)
                return
            var fileObjs = []
            for (var ui = 0; ui < urls.length; ui++) {
                var _url2 = urls[ui]
                var _name2 = ""
                if (_url2.toLowerCase().startsWith("magnet:?"))
                    _name2 = extractMagnetDisplayName(_url2)
                if (_name2.length === 0)
                    _name2 = _url2.split('/').pop().split('?')[0]
                fileObjs.push({ name: _name2, url: _url2 })
            }
            batchDownloadListDialog.files = fileObjs
            batchDownloadListDialog.isImport = true
            batchDownloadListDialog.show()
            batchDownloadListDialog.raise()
        }
    }

    // Open the yt-dlp format picker for a video site URL.
    // ── No DownloadItem is created here it only appears in the list once the ──
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
        var urlName2 = url.split("/").pop().split("?")[0] || "download"
        var hasExt2 = urlName2.indexOf('.') > 0
        var filename = filenameOverride.length > 0
            ? filenameOverride
            : (App.isTorrentUri(url)
                ? "Magnetized Transfer"
                : (hasExt2 ? urlName2 : ""))
        var displayFilename = filename || urlName2
        // Discard any pre-fetch that was started by a previous _showFileInfoDialog
        // call for this same URL (e.g. when the user picks "Add Numbered" after a
        // ── duplicate warning we'd otherwise leak a running download in temp). ──
        if (fileInfoDialog.pendingDownloadId.length > 0) {
            App.discardPendingDownload(fileInfoDialog.pendingDownloadId)
            fileInfoDialog.pendingDownloadId = ""
        }

        var _cookies2  = App.takePendingCookies(url)
        // ── No cookies from extension read from browser profiles on disk. ──
        if (_cookies2.length === 0)
            _cookies2 = App.cookiesForUrl(url)
        // Store back so takePendingCookies() works at confirm time (addUrl path).
        if (_cookies2.length > 0)
            App.setPendingCookies(url, _cookies2)
        var _referrer2 = App.takePendingReferrer(url)
        var _pageUrl2  = App.takePendingPageUrl(url)
        fileInfoDialog.pendingUrl      = url
        fileInfoDialog.pendingFilename = displayFilename
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
            // ── Resume or show complete no file info dialog ──────────────
            if (existing.status === "Completed") {
                completeDialog.item = existing
                completeDialog.show(); completeDialog.raise()
            } else {
                App.resumeDownload(existing.id)
            }
        } else if (action === 2) {
            // Overwrite: re-add the download.
            if (App.isLikelyYtdlpUrl(url)) {
                // yt-dlp names the file from video metadata, so the collision
                // scan would otherwise append _2. overwriteExisting tells the
                // backend to skip that rename and force yt-dlp to overwrite.
                // Defer removing the existing entry until the user actually starts
                // the download in the format picker — stash its id and delete it
                // in onDownloadRequested. Cancelling the picker leaves it intact.
                _showYtdlpDialog(url)
                ytdlpDialog.overwriteExisting = true
                _ytdlpOverwriteExistingId = existing.id
            } else {
                // Non-yt-dlp goes straight to the file-info dialog; remove now.
                App.deleteDownload(existing.id, 0)
                _showFileInfoDialog(url, "")
            }
        } else {
            // AddNumbered: for yt-dlp URLs the filename is chosen by yt-dlp itself
            // ── (from video metadata), so generating a numbered name here has no effect ──
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

    // Id of an existing download to remove when the user confirms an "Overwrite"
    // yt-dlp download. Deleted in onDownloadRequested (not on dialog open), so
    // cancelling the format picker leaves the existing entry untouched.
    property string _ytdlpOverwriteExistingId: ""

    // Pending auth from AddUrlDialog step 1
    property string _pendingUsername: ""
    property string _pendingPassword: ""
    property string _pendingTorrentFilePath: ""
    property var _pendingBatchUrls: []
    property var _pendingLaterRequest: null
    property string _pendingQueueContext: ""
    property string _pendingExportPath: ""
    property string _pendingExportFormat: ""
    property var _pendingExportItems: []
    property var _afterDownloadLaterWarning: null

    // ── Download File Info dialog (step 2) ───────────────────────────────
    DownloadFileInfoDialog {
        id: fileInfoDialog
        // Detach from main window so it gets its own taskbar button, IDM-style.
        transientParent: null
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
                if (App.finalizePendingDownload(downloadId, savePath, category, desc, true, "")) {
                    // Pending file-info downloads can still briefly report
                    // "Paused" when the UI signal arrives; open the progress
                    // window directly for the item the user just started.
                    // Skip the progress dialog if the download already finished
                    // ── while the user was reviewing the file info dialog the ──
                    // complete dialog will have been (or will be) shown instead.
                    Qt.callLater(function() {
                        var dlItem = App.downloadById(downloadId)
                        if (dlItem && dlItem.status !== "Completed")
                            root.showDownloadProgressForItem(dlItem)
                    })
                }
            } else {
                var sep = Math.max(savePath.lastIndexOf("/"), savePath.lastIndexOf("\\"))
                var dir   = sep >= 0 ? savePath.substring(0, sep) : savePath
                var fname = sep >= 0 ? savePath.substring(sep + 1) : fileInfoDialog.filenameOverride
                App.addUrl(url, dir, category, desc, true, App.takePendingCookies(url), App.takePendingReferrer(url), App.takePendingPageUrl(url), root._pendingUsername, root._pendingPassword, fname)
                Qt.callLater(function() {
                    root.showDownloadProgressForItem(App.findDuplicateUrl(url))
                })
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

    // ── yt-dlp format picker dialog ──────────────────────────────────────
    // Shown when a yt-dlp-compatible URL is submitted via Add URL or clipboard.
    // The URL is probed with "yt-dlp --dump-json" so the user can choose quality
    // before the actual download starts.
    YtdlpDialog {
        id: ytdlpDialog
        transientParent: root

        onDownloadRequested: (url, formatId, containerFormat, savePath, category, uniqueFilename, videoTitle, playlistMode, maxItems, extraOptions, overwriteExisting) => {
            // Now that the user has committed, remove the entry being overwritten.
            if (overwriteExisting && root._ytdlpOverwriteExistingId.length > 0) {
                App.deleteDownload(root._ytdlpOverwriteExistingId, 0)
                root._ytdlpOverwriteExistingId = ""
            }
            App.finalizeYtdlpDownload(url, savePath, category, formatId, containerFormat, uniqueFilename, videoTitle, playlistMode, maxItems, extraOptions, overwriteExisting)
        }
        onClosing: root._ytdlpOverwriteExistingId = ""  // cancelled — keep existing entry
        onOpenSettingsRequested: (page) => showSettingsPage(page)
    }

    Window {
        id: ytdlpBatchWindow
        transientParent: root
        width: 760
        height: 500
        minimumWidth: 520
        minimumHeight: 360
        maximumHeight: 500
        title: qsTr("Channel Download Progress")
        color: ColorPalette.cardBg
        modality: Qt.NonModal
        flags: Qt.Dialog | Qt.WindowTitleHint | Qt.WindowCloseButtonHint
        visible: false

        onVisibleChanged: {
            if (visible) {
                x = root.x + Math.round((root.width  - width)  / 2)
                y = root.y + Math.round((root.height - height) / 2)
            }
        }

        // Auto-open only once when a NEW batch starts — keyed on the active batch
        // id. ytdlpBatchChanged fires on every progress tick (and every video
        // finish), so re-showing unconditionally yanked the window back to the
        // foreground constantly. The user can close it; it must stay closed until
        // a different batch begins.
        property string _autoShownBatchId: ""
        Connections {
            target: App
            function onYtdlpBatchChanged() {
                if (App.ytdlpBatchActive
                        && App.ytdlpBatchId !== ytdlpBatchWindow._autoShownBatchId) {
                    ytdlpBatchWindow._autoShownBatchId = App.ytdlpBatchId
                    ytdlpBatchWindow.show()
                    ytdlpBatchWindow.raise()
                    ytdlpBatchWindow.requestActivate()
                }
            }
        }

        // ── Column definitions ───────────────────────────────────────────
        readonly property var _defaultCols: [
            { title: "#",           key: "index",    widthPx: 40,  visible: true },
            { title: qsTr("File Name"), key: "filename", widthPx: 320, visible: true },
            { title: qsTr("Size"),      key: "size",     widthPx: 80,  visible: true },
            { title: qsTr("Status"),    key: "status",   widthPx: 110, visible: true },
            { title: qsTr("Time left"), key: "timeleft", widthPx: 90,  visible: true }
        ]
        property var columnDefs: {
            var defs = []
            for (var i = 0; i < _defaultCols.length; i++)
                defs.push(Object.assign({}, _defaultCols[i]))
            return defs
        }

        function makeVisibleCols() {
            var r = []
            for (var i = 0; i < columnDefs.length; i++)
                if (columnDefs[i].visible) r.push(columnDefs[i])
            return r
        }
        property var visibleCols: makeVisibleCols()
        onColumnDefsChanged: {
            visibleCols = makeVisibleCols()
            visibleContentWidth = totalVisibleWidth()
        }

        function colWidth(key) {
            if (_resizingColumnKey === key) return _resizingColumnWidth
            for (var i = 0; i < columnDefs.length; i++) {
                if (columnDefs[i].key === key)
                    return columnDefs[i].widthPx || 100
            }
            return 0
        }

        function _colVisible(key) {
            for (var i = 0; i < columnDefs.length; i++)
                if (columnDefs[i].key === key) return columnDefs[i].visible
            return false
        }

        function totalVisibleWidth() {
            var total = 0
            for (var i = 0; i < visibleCols.length; i++)
                total += colWidth(visibleCols[i].key)
            return total
        }

        function minColWidth(key) {
            if (key === "index") return 30
            return 24
        }

        function formatBytesShort(bytes) {
            // Guard against absurd/garbled values from yt-dlp (NaN, Infinity, huge):
            // never let the UI render "388548235 MB".
            if (!isFinite(bytes) || bytes <= 0 || bytes > 1e15) return ""
            if (bytes >= 1073741824) return (bytes / 1073741824).toFixed(2) + " GB"
            if (bytes >= 1048576) return (bytes / 1048576).toFixed(1) + " MB"
            if (bytes >= 1024) return (bytes / 1024).toFixed(1) + " KB"
            return bytes + " B"
        }

        function formatTimeLeft(etaStr) {
            if (!etaStr || etaStr === "") return ""
            // yt-dlp ETA: "HH:MM:SS" or "MM:SS"
            var parts = etaStr.split(":")
            var seconds = 0
            if (parts.length === 3)
                seconds = parseInt(parts[0]) * 3600 + parseInt(parts[1]) * 60 + parseInt(parts[2])
            else if (parts.length === 2)
                seconds = parseInt(parts[0]) * 60 + parseInt(parts[1])
            else
                seconds = parseInt(parts[0]) || 0
            if (seconds <= 0) return ""
            if (seconds < 60) return seconds + " sec"
            var units = [
                [31557600, "year", "years"],
                [2629800, "month", "months"],
                [86400, "day", "days"],
                [3600, "hour", "hours"],
                [60, "min", "min"]
            ]
            var partsOut = []
            var rem = seconds
            for (var i = 0; i < units.length; i++) {
                if (rem < units[i][0]) continue
                var count = Math.floor(rem / units[i][0])
                rem %= units[i][0]
                partsOut.push(count + " " + (count === 1 ? units[i][1] : units[i][2]))
                if (partsOut.length === 2) break
            }
            if (partsOut.length === 0)
                return Math.ceil(seconds / 60) + " min"
            return partsOut.join(" ")
        }

        property real visibleContentWidth: totalVisibleWidth()
        onVisibleColsChanged: visibleContentWidth = totalVisibleWidth()

        property string _resizingColumnKey: ""
        property real _resizingColumnWidth: 0

        property var _colXMap: {
            visibleContentWidth
            return _buildColXMap()
        }
        function _buildColXMap() {
            var map = {}
            var x = 0
            for (var i = 0; i < visibleCols.length; i++) {
                var col = visibleCols[i]
                map[col.key] = x
                x += colWidth(col.key)
            }
            return map
        }

        property string _colDragFromKey:          ""
        property string _colDragInsertBeforeKey:  ""
        property bool   _colDragging:             false

        function _applyColReorder() {
            if (!_colDragFromKey) return
            var defs = columnDefs.slice()
            var fromIdx = -1
            for (var i = 0; i < defs.length; i++) { if (defs[i].key === _colDragFromKey) { fromIdx = i; break } }
            if (fromIdx < 0) return
            var toIdx
            if (_colDragInsertBeforeKey === "__end__") {
                toIdx = defs.length
            } else {
                toIdx = -1
                for (var j = 0; j < defs.length; j++) { if (defs[j].key === _colDragInsertBeforeKey) { toIdx = j; break } }
            }
            if (toIdx < 0 || toIdx === fromIdx) return
            var moved = defs.splice(fromIdx, 1)[0]
            if (toIdx > fromIdx) toIdx--
            defs.splice(toIdx, 0, moved)
            columnDefs = defs
        }

        // ── Aggregate stats ──────────────────────────────────────────────
        property int _statsTotal: {
            return App.ytdlpBatchItems.length
        }
        property int _statsDone: {
            var c = 0
            for (var i = 0; i < App.ytdlpBatchItems.length; ++i)
                if ((App.ytdlpBatchItems[i].status || "") === "Completed") c++
            return c
        }
        property int _statsActive: {
            var c = 0
            for (var i = 0; i < App.ytdlpBatchItems.length; ++i)
                if ((App.ytdlpBatchItems[i].status || "") === "Downloading") c++
            return c
        }
        property int _statsQueued: Math.max(0, _statsTotal - _statsDone - _statsActive)
        // Single source of truth, computed in C++ (recomputeChannelAggregate) so the
        // header bar and the main-table parent row always agree.
        property int _statsAvgProgress: {
            App.ytdlpBatchChanged   // re-evaluate on every batch tick
            return Math.round(Math.max(0, Math.min(100, App.ytdlpBatchProgress)))
        }
        // Combined download speed of the currently-active video(s). yt-dlp runs a
        // single worker, but video+audio phases and quick item hand-off mean more
        // than one row can read "Downloading" for a tick — sum to be safe.
        property real _statsSpeed: {
            App.ytdlpBatchChanged   // re-evaluate on every batch tick
            var bps = 0
            for (var i = 0; i < App.ytdlpBatchItems.length; ++i) {
                var it = App.ytdlpBatchItems[i]
                if ((it.status || "") === "Downloading")
                    bps += (it.speedBps || 0)
            }
            return bps
        }

        function _fmtSpeed(bps) {
            // Guard absurd/garbled speeds (NaN, Infinity, > ~50 GB/s) so the header
            // can never read "388548235 MB/s".
            if (!isFinite(bps) || bps <= 0 || bps > 5e10) return "0 B/s"
            if (bps >= 1000000000) return (bps / 1000000000).toFixed(2) + " GB/s"
            if (bps >= 1000000)    return (bps / 1000000).toFixed(2) + " MB/s"
            if (bps >= 1000)       return (bps / 1000).toFixed(1) + " KB/s"
            return Math.round(bps) + " B/s"
        }

        ColumnLayout {
            anchors.fill: parent
            spacing: 0

            // ── Themed progress header (mirrors the HTTP progress dialog) ──
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: headerCol.implicitHeight + 8
                color: ColorPalette.headerStripBg
                border.width: 0
                radius: 0

                ColumnLayout {
                    id: headerCol
                    anchors { left: parent.left; right: parent.right
                              verticalCenter: parent.verticalCenter
                              leftMargin: 14; rightMargin: 14 }
                    spacing: 4

                    Text {
                        Layout.fillWidth: true
                        text: App.ytdlpBatchLabel.length > 0 ? App.ytdlpBatchLabel : qsTr("Channel/Playlist")
                        color: ColorPalette.textHeader
                        font.pixelSize: 13 * App.fontScale
                        font.bold: true
                        elide: Text.ElideMiddle
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        Text {
                            text: ytdlpBatchWindow._statsAvgProgress + "%"
                            color: ColorPalette.textHeader
                            font.pixelSize: 12 * App.fontScale
                            font.bold: true
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            height: 5; radius: 2
                            color: ColorPalette.windowBg
                            border.color: ColorPalette.dividerBg
                            clip: true
                            Rectangle {
                                width: Math.max(0, parent.width * ytdlpBatchWindow._statsAvgProgress / 100)
                                height: parent.height; radius: parent.radius
                                color: ColorPalette.accent
                                Behavior on width { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                            }
                        }

                        Text {
                            visible: ytdlpBatchWindow._statsSpeed > 0
                            text: "↓ " + ytdlpBatchWindow._fmtSpeed(ytdlpBatchWindow._statsSpeed)
                            color: ColorPalette.textHeader
                            font.pixelSize: 11 * App.fontScale
                        }
                    }

                    Text {
                        Layout.fillWidth: true
                        text: qsTr("Total: %1").arg(ytdlpBatchWindow._statsTotal)
                              + "   " + qsTr("Completed: %1").arg(ytdlpBatchWindow._statsDone)
                              + "   " + qsTr("Downloading: %1").arg(ytdlpBatchWindow._statsActive)
                              + "   " + qsTr("Queued: %1").arg(ytdlpBatchWindow._statsQueued)
                        color: ColorPalette.textSecond
                        font.pixelSize: 11 * App.fontScale
                        elide: Text.ElideRight
                    }
                }
            }

            // ── Table ────────────────────────────────────────────────────
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.leftMargin: 8
                Layout.rightMargin: 8
                Layout.topMargin: 8
                color: ColorPalette.inputBg
                border.color: ColorPalette.border
                radius: 4
                clip: true

                // ── Header ───────────────────────────────────────────────
                Rectangle {
                    id: batchHeader
                    anchors { top: parent.top; left: parent.left; right: parent.right }
                    height: 26
                    color: ColorPalette.dividerBg
                    clip: true

                    Row {
                        x: -batchListView.contentX
                        width: ytdlpBatchWindow.visibleContentWidth
                        height: parent.height

                        Repeater {
                            id: hdrRepeater
                            model: ytdlpBatchWindow.visibleCols
                            delegate: Rectangle {
                                id: hdrCell
                                width: ytdlpBatchWindow.colWidth(modelData.key)
                                height: parent.height
                                color: (hdrMouse.containsMouse && !ytdlpBatchWindow._colDragging) ? ColorPalette.border : "transparent"
                                opacity: (ytdlpBatchWindow._colDragging && ytdlpBatchWindow._colDragFromKey === modelData.key) ? 0.5 : 1.0

                                // Drop insert-line LEFT of this column
                                Rectangle {
                                    visible: ytdlpBatchWindow._colDragging && ytdlpBatchWindow._colDragInsertBeforeKey === modelData.key
                                    width: 2; height: parent.height
                                    anchors.left: parent.left
                                    color: ColorPalette.accent
                                    z: 20
                                }

                                // Insert-line at END of header
                                Rectangle {
                                    visible: ytdlpBatchWindow._colDragging
                                          && ytdlpBatchWindow._colDragInsertBeforeKey === "__end__"
                                          && index === hdrRepeater.count - 1
                                    width: 2; height: parent.height
                                    anchors.right: parent.right
                                    color: ColorPalette.accent
                                    z: 20
                                }

                                Text {
                                    anchors {
                                        verticalCenter: parent.verticalCenter
                                        left: parent.left
                                        leftMargin: modelData.key === "index" ? 0 : 6
                                        right: parent.right
                                        rightMargin: 12
                                    }
                                    text: modelData.title
                                    color: ColorPalette.textSecond
                                    font.pixelSize: 12 * App.fontScale
                                    font.bold: true
                                    horizontalAlignment: modelData.key === "index" ? Text.AlignHCenter : Text.AlignLeft
                                    elide: Text.ElideRight
                                }

                                // Column reorder drag
                                MouseArea {
                                    id: hdrMouse
                                    anchors { fill: parent; rightMargin: 10 }
                                    hoverEnabled: true
                                    preventStealing: true
                                    cursorShape: ytdlpBatchWindow._colDragging ? Qt.ClosedHandCursor : Qt.ArrowCursor

                                    property real _pressX:  0
                                    property bool _didDrag: false

                                    onPressed:  { _pressX = mouseX; _didDrag = false }

                                    onPositionChanged: {
                                        if (!(pressedButtons & Qt.LeftButton)) return
                                        if (!ytdlpBatchWindow._colDragging && Math.abs(mouseX - _pressX) > 8) {
                                            ytdlpBatchWindow._colDragFromKey = modelData.key
                                            ytdlpBatchWindow._colDragging = true
                                            _didDrag = true
                                        }
                                        if (ytdlpBatchWindow._colDragging && ytdlpBatchWindow._colDragFromKey === modelData.key) {
                                            var cursorX = hdrMouse.mapToItem(batchHeaderRow, mouseX, 0).x
                                            var insertBefore = "__end__"
                                            var xAcc = 0
                                            for (var k = 0; k < ytdlpBatchWindow.visibleCols.length; k++) {
                                                var colW = ytdlpBatchWindow.colWidth(ytdlpBatchWindow.visibleCols[k].key)
                                                if (cursorX < xAcc + colW / 2) {
                                                    insertBefore = ytdlpBatchWindow.visibleCols[k].key
                                                    break
                                                }
                                                xAcc += colW
                                            }
                                            ytdlpBatchWindow._colDragInsertBeforeKey = insertBefore
                                        }
                                    }

                                    onReleased: {
                                        var didDrag = _didDrag
                                        var win = ytdlpBatchWindow
                                        Qt.callLater(function() {
                                            if (didDrag) win._applyColReorder()
                                            win._colDragging = false
                                            win._colDragFromKey = ""
                                            win._colDragInsertBeforeKey = ""
                                        })
                                        _didDrag = false
                                        _pressX = 0
                                    }
                                }

                                // Column separator
                                Rectangle {
                                    anchors.right: parent.right
                                    width: 1; height: parent.height
                                    color: ColorPalette.border
                                }

                                // Column resize handle
                                Item {
                                    id: batchResizeHandle
                                    width: 10
                                    height: parent.height
                                    anchors.right: parent.right
                                    z: 10

                                    property real _startWidthPx: 0

                                    Rectangle {
                                        anchors.right: parent.right
                                        width: 2
                                        height: parent.height
                                        color: (batchResizeDrag.active || batchResizeHover.hovered) ? "#6aa0ff" : "transparent"
                                        opacity: batchResizeDrag.active ? 1.0 : 0.75
                                    }

                                    HoverHandler {
                                        id: batchResizeHover
                                        cursorShape: Qt.SizeHorCursor
                                    }

                                    DragHandler {
                                        id: batchResizeDrag
                                        target: null
                                        xAxis.enabled: true
                                        yAxis.enabled: false
                                        cursorShape: Qt.SizeHorCursor

                                        onActiveChanged: {
                                            if (active) {
                                                batchResizeHandle._startWidthPx = modelData.widthPx || 100
                                                ytdlpBatchWindow._resizingColumnKey = modelData.key
                                                ytdlpBatchWindow._resizingColumnWidth = batchResizeHandle._startWidthPx
                                                return
                                            }
                                            if (ytdlpBatchWindow._resizingColumnKey === modelData.key) {
                                                var defs = ytdlpBatchWindow.columnDefs.slice()
                                                for (var j = 0; j < defs.length; j++) {
                                                    if (defs[j].key === modelData.key) {
                                                        defs[j] = Object.assign({}, defs[j], { widthPx: ytdlpBatchWindow._resizingColumnWidth })
                                                        break
                                                    }
                                                }
                                                ytdlpBatchWindow._resizingColumnKey = ""
                                                ytdlpBatchWindow._resizingColumnWidth = 0
                                                ytdlpBatchWindow.columnDefs = defs
                                            }
                                        }

                                        onTranslationChanged: {
                                            if (!active) return
                                            ytdlpBatchWindow._resizingColumnWidth = Math.max(ytdlpBatchWindow.minColWidth(modelData.key),
                                                Math.round(batchResizeHandle._startWidthPx + translation.x))
                                            ytdlpBatchWindow.visibleContentWidth = ytdlpBatchWindow.totalVisibleWidth()
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Bottom border
                    Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: ColorPalette.border }
                }

                Item {
                    id: batchHeaderRow
                    visible: false
                }

                // ── Rows ─────────────────────────────────────────────────
                ListView {
                    id: batchListView
                    anchors { top: batchHeader.bottom; left: parent.left; right: parent.right; bottom: parent.bottom }
                    model: App.ytdlpBatchItems
                    clip: true
                    contentWidth: ytdlpBatchWindow.visibleContentWidth
                    cacheBuffer: 300
                    reuseItems: true

                    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                    ScrollBar.horizontal: ScrollBar { policy: ScrollBar.AsNeeded }

                    WheelHandler {
                        orientation: Qt.Vertical
                        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                        onWheel: function(e) {
                            batchListView.contentY = Math.max(0,
                                Math.min(batchListView.contentY - e.angleDelta.y / 2,
                                         Math.max(0, batchListView.contentHeight - batchListView.height)))
                            e.accepted = true
                        }
                    }

                    WheelHandler {
                        orientation: Qt.Horizontal
                        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                        onWheel: function(e) {
                            batchListView.contentX = Math.max(0,
                                Math.min(batchListView.contentX - e.angleDelta.x / 2,
                                         Math.max(0, batchListView.contentWidth - batchListView.width)))
                            e.accepted = true
                        }
                    }

                    delegate: Rectangle {
                        id: batchRow
                        required property int index
                        required property var modelData
                        // Stretch the stripe across the full viewport even when the
                        // columns are narrower than the list, so alternating row
                        // colors reach the right edge.
                        width: Math.max(batchListView.contentWidth, batchListView.width)
                        height: 28
                        color: batchRowIndex % 2 === 0 ? ColorPalette.windowBg : ColorPalette.rowAltBg
                        clip: true

                        readonly property int batchRowIndex: index
                        readonly property var itemData: modelData

                        Row {
                            // ── # column ─────────────────────────────────
                            Item {
                                visible: ytdlpBatchWindow._colVisible("index")
                                x: ytdlpBatchWindow._colXMap["index"] || 0
                                width: ytdlpBatchWindow.colWidth("index")
                                height: batchRow.height - 1
                                clip: true
                                Text {
                                    anchors { fill: parent; leftMargin: 0 }
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                    text: batchRow.itemData.index || (batchRow.batchRowIndex + 1)
                                    color: ColorPalette.textMuted
                                    font.pixelSize: 11 * App.fontScale
                                }
                            }

                            // ── Filename column ──────────────────────────
                            Item {
                                visible: ytdlpBatchWindow._colVisible("filename")
                                x: ytdlpBatchWindow._colXMap["filename"] || 0
                                width: ytdlpBatchWindow.colWidth("filename")
                                height: batchRow.height - 1
                                clip: true
                                Text {
                                    anchors { fill: parent; leftMargin: 6 }
                                    verticalAlignment: Text.AlignVCenter
                                    text: {
                                        var t = batchRow.itemData.title
                                        if (t === undefined || t === null || t === "") return qsTr("Pending…")
                                        return t
                                    }
                                    color: ColorPalette.textPrimary
                                    font.pixelSize: 12 * App.fontScale
                                    elide: Text.ElideMiddle
                                }
                            }

                            // ── Size column ──────────────────────────────
                            Item {
                                visible: ytdlpBatchWindow._colVisible("size")
                                x: ytdlpBatchWindow._colXMap["size"] || 0
                                width: ytdlpBatchWindow.colWidth("size")
                                height: batchRow.height - 1
                                clip: true
                                Text {
                                    anchors { fill: parent; leftMargin: 6 }
                                    verticalAlignment: Text.AlignVCenter
                                    text: {
                                        var tb = batchRow.itemData.totalBytes
                                        if (!tb || tb <= 0) return ""
                                        return ytdlpBatchWindow.formatBytesShort(tb)
                                    }
                                    color: ColorPalette.textSecond
                                    font.pixelSize: 12 * App.fontScale
                                }
                            }

                            // ── Status column ────────────────────────────
                            Item {
                                visible: ytdlpBatchWindow._colVisible("status")
                                x: ytdlpBatchWindow._colXMap["status"] || 0
                                width: ytdlpBatchWindow.colWidth("status")
                                height: batchRow.height - 1
                                clip: true
                                Text {
                                    anchors { fill: parent; leftMargin: 6 }
                                    verticalAlignment: Text.AlignVCenter
                                    text: {
                                        var st = batchRow.itemData.status || "Queued"
                                        var pct = batchRow.itemData.progress || 0
                                        if (st === "Completed")
                                            return qsTr("Completed")
                                        if (st === "Downloading")
                                            // Cap at 99: a running item must never read 100%.
                                            return qsTr("Downloading %1%").arg(Math.min(99, Math.round(pct)))
                                        return st
                                    }
                                    color: ColorPalette.textSecond
                                    font.pixelSize: 12 * App.fontScale
                                }
                            }

                            // ── Time left column ─────────────────────────
                            Item {
                                visible: ytdlpBatchWindow._colVisible("timeleft")
                                x: ytdlpBatchWindow._colXMap["timeleft"] || 0
                                width: ytdlpBatchWindow.colWidth("timeleft")
                                height: batchRow.height - 1
                                clip: true
                                Text {
                                    anchors { fill: parent; leftMargin: 6 }
                                    verticalAlignment: Text.AlignVCenter
                                    text: {
                                        var st = batchRow.itemData.status || ""
                                        if (st !== "Downloading") return ""
                                        var eta = batchRow.itemData.timeLeft || ""
                                        if (eta === "") return ""
                                        return ytdlpBatchWindow.formatTimeLeft(eta)
                                    }
                                    color: ColorPalette.textSecond
                                    font.pixelSize: 12 * App.fontScale
                                }
                            }
                        }

                        // Progress bar
                        Rectangle {
                            anchors { bottom: parent.bottom; bottomMargin: 1 }
                            width: {
                                var pct = Math.max(0, Math.min(100, batchRow.itemData.progress || 0))
                                return pct / 100 * Math.max(0, Math.min(batchListView.width, batchRow.width - batchListView.contentX))
                            }
                            height: 2
                            color: ColorPalette.accent
                            visible: (batchRow.itemData.status || "") === "Downloading"
                        }

                        // Row separator
                        Rectangle {
                            anchors.bottom: parent.bottom
                            width: parent.width
                            height: 1
                            color: ColorPalette.dividerBg
                        }
                    }
                }
            }

            // ── Buttons ──────────────────────────────────────────────────
            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: 8
                Layout.rightMargin: 8
                Layout.topMargin: 6
                Layout.bottomMargin: 8
                Item { Layout.fillWidth: true }
                DlgButton {
                    text: qsTr("Stop")
                    enabled: App.ytdlpBatchActive
                    onClicked: App.stopActiveYtdlpBatch()
                }
                DlgButton {
                    text: qsTr("Resume")
                    enabled: !App.ytdlpBatchActive && App.ytdlpBatchCanResume
                    onClicked: App.resumeLastYtdlpBatch()
                }
                DlgButton {
                    text: qsTr("Close")
                    onClicked: ytdlpBatchWindow.hide()
                }
            }
        }
    }

    TorrentCreatorDialog {
        id: torrentCreatorDialog
        transientParent: root
        onOpenTorrentRequested: (torrentFilePath) => {
            root.showTorrentMetadataDialogForFile(
                torrentFilePath,
                root.torrentSaveDirFromInputPath(App.settings.defaultSavePath),
                "", "", true)
        }
    }

    // One TorrentMetadataDialog window is created per torrent on demand via
    // _getOrCreateTorrentMetaDialog (see _torrentMetaDialogs map above).
    Component {
        id: torrentMetadataDialogComponent
        TorrentMetadataDialog {
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
    }

    TorrentDuplicateDialog {
        id: torrentDuplicateDialog
        transientParent: root
        onMergeRequested: (downloadId, trackers) => {
            App.mergeTrackersInto(downloadId, trackers)
        }
    }

    // Shown when user tries to add a torrent/magnet with BitTorrent support disabled.
    Popup {
        id: torrentEnableNotice
        property string _pendingUri: ""
        parent: Overlay.overlay
        anchors.centerIn: parent
        width: 480
        modal: true
        closePolicy: Popup.NoAutoClose
        padding: 0
        background: Rectangle { color: ColorPalette.cardBg; border.color: ColorPalette.border; radius: 6 }
        contentItem: ColumnLayout {
            spacing: 0
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 12
                Layout.margins: 20
                Text {
                    text: qsTr("Enable BitTorrent Support?")
                    color: ColorPalette.textHeader
                    font.pixelSize: 15 * App.fontScale
                    font.bold: true
                }
                Rectangle { Layout.fillWidth: true; height: 1; color: ColorPalette.border }
                Text {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    color: ColorPalette.textPrimary
                    font.pixelSize: 12 * App.fontScale
                    lineHeight: 1.4
                    text: qsTr("BitTorrent support is currently disabled.\n\nWhen you download a torrent, your IP address becomes visible to other peers in the swarm and you simultaneously upload (seed) data to others.\n\nAnything you share via BitTorrent is your sole responsibility. Ensure you have the right to distribute the content.\n\nIt is strongly recommended to bind Stellar to a VPN network interface and verify that your VPN is active before using torrents, to protect your IP address from exposure.")
                }
                Rectangle { Layout.fillWidth: true; height: 1; color: ColorPalette.border }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    Item { Layout.fillWidth: true }
                    DlgButton {
                        text: qsTr("Cancel")
                        onClicked: {
                            torrentEnableNotice._pendingUri = ""
                            torrentEnableNotice.close()
                        }
                    }
                    DlgButton {
                        text: qsTr("I Understand, Enable")
                        primary: true
                        onClicked: {
                            var uri = torrentEnableNotice._pendingUri
                            torrentEnableNotice._pendingUri = ""
                            torrentEnableNotice.close()
                            App.settings.torrentEnabled = true
                            // Retry the pending add now that the session is enabled
                            if (uri.length > 0) {
                                if (root.isTorrentFilePath(uri)) {
                                    root.showTorrentMetadataDialogForFile(uri, root.torrentSaveDirFromInputPath(App.settings.defaultSavePath), "", "", true)
                                } else {
                                    var id = App.addMagnetLink(uri, App.settings.defaultSavePath, "", "", false, "")
                                    if (id && id.length > 0)
                                        root.showTorrentMetadataDialog(id, true)
                                }
                            }
                        }
                    }
                }
            }
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
        title: qsTr("Download Later")
        transientParent: root
        width: 480
        height: 220
        minimumWidth: 380
        minimumHeight: 200
        flags: Qt.Dialog | Qt.WindowTitleHint | Qt.WindowCloseButtonHint
        modality: Qt.ApplicationModal
        color: ColorPalette.cardBg

        Material.theme: ColorPalette.materialTheme
    Material.foreground: ColorPalette.textPrimary
        Material.background: ColorPalette.materialBg
        Material.accent: "#4488dd"

        onVisibleChanged: {
            if (visible) {
                x = root.x + Math.round((root.width  - width)  / 2)
                y = root.y + Math.round((root.height - height) / 2)
            }
        }

        // Note: do NOT null out _afterDownloadLaterWarning here. The OK button
        // handler calls close() *before* invoking the callback; clearing it on
        // close would destroy the callback before it ever runs (the user's
        // "Download Later" choice would silently no-op).

        ColumnLayout {
            anchors { fill: parent; margins: 20 }
            spacing: 16

            Text {
                Layout.fillWidth: true
                text: qsTr("You pressed the 'Download Later' button, but Stellar had already started downloading a part of the file. Stellar always starts downloading while displaying the \"Download File Info\" dialog.\n\nYou can turn this off in Settings → Downloads.")
                color: ColorPalette.textPrimary
                font.pixelSize: 13 * App.fontScale
                wrapMode: Text.WordWrap
                lineHeight: 1.3
            }

            Item { Layout.fillHeight: true }

            RowLayout {
                Layout.fillWidth: true
                Item { Layout.fillWidth: true }
                DlgButton {
                    text: qsTr("OK")
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

    // ── File Deleted Warning Dialog ──────────────────────────────────────
    Window {
        id: fileDeletedWarningDialog
        property string _filename: ""
        title: qsTr("File No Longer Available")
        transientParent: root
        width: 460
        height: 240
        minimumWidth: 400
        minimumHeight: 220
        flags: Qt.Dialog | Qt.WindowTitleHint | Qt.WindowCloseButtonHint
        modality: Qt.ApplicationModal
        color: ColorPalette.cardBg

        Material.theme: ColorPalette.materialTheme
    Material.foreground: ColorPalette.textPrimary
        Material.background: ColorPalette.materialBg
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
                    source: "icons/file_no_longer_available.svg"
                    width: 24; height: 24
                    sourceSize.width: 24; sourceSize.height: 24
                    fillMode: Image.PreserveAspectFit
                    Layout.alignment: Qt.AlignTop
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 4

                    Text {
                        Layout.fillWidth: true
                        text: qsTr("The file \u201c%1\u201d could not be downloaded.").arg(fileDeletedWarningDialog._filename)
                        color: ColorPalette.textPrimary
                        font.pixelSize: 12 * App.fontScale
                        font.bold: true
                        wrapMode: Text.WordWrap
                    }

                    Text {
                        Layout.fillWidth: true
                        text: qsTr("The server returned a webpage instead of the expected file. Some sites delete files immediately after Stellar queries their metadata.")
                        color: ColorPalette.textPrimary
                        font.pixelSize: 11 * App.fontScale
                        wrapMode: Text.WordWrap
                        lineHeight: 1.3
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: fdwInfoText.implicitHeight + 16
                color: ColorPalette.infoBoxBg
                border.color: ColorPalette.infoBoxBorder
                radius: 3

                Text {
                    id: fdwInfoText
                    anchors { fill: parent; margins: 8 }
                    text: qsTr("To let your browser download directly, hold a modifier key (Alt, Ctrl, or Shift) while clicking the link. Configure the key in:\nStellar Options \u2192 Browser \u2192 Bypass Download Interception")
                    color: ColorPalette.infoBoxText
                    font.pixelSize: 11 * App.fontScale
                    wrapMode: Text.WordWrap
                    lineHeight: 1.3
                }
            }

            Item { Layout.fillHeight: true }

            RowLayout {
                Layout.fillWidth: true
                Item { Layout.fillWidth: true }
                DlgButton {
                    text: qsTr("Open Browser Settings")
                    onClicked: {
                        fileDeletedWarningDialog.close()
                settingsDialog.initialPage = root.settingsPageBrowser
                        settingsDialog.show()
                        settingsDialog.raise()
                        settingsDialog.requestActivate()
                    }
                }
                DlgButton {
                    text: qsTr("OK")
                    primary: true
                    onClicked: fileDeletedWarningDialog.close()
                }
            }
        }
    }

    // ── Duplicate Download Dialog ────────────────────────────────────────
    DuplicateDownloadDialog {
        id: duplicateDialog
        // Detached from main window so showing it doesn't surface the main window too.
        transientParent: null
        property string _pendingUrl: ""
        onResolved: (action, remember) => {
            _handleDuplicateAction(action, remember, existingItem, _pendingUrl)
        }
    }

    // ── Download Complete Dialog ─────────────────────────────────────────
    // Detach from main window so each gets its own taskbar button, IDM-style.
    DownloadCompleteDialog { id: completeDialog; transientParent: null }

    // ── Settings / About Dialog ──────────────────────────────────────────
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
        title: qsTr("Quick Update")
        transientParent: root
        width: 440
        height: 170
        minimumWidth: 420
        minimumHeight: 160
        flags: Qt.Dialog | Qt.WindowTitleHint | Qt.WindowCloseButtonHint
        modality: Qt.ApplicationModal
        color: ColorPalette.cardBg
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
                color: ColorPalette.textPrimary
                font.pixelSize: 13 * App.fontScale
            }

            Item { Layout.fillHeight: true }

            RowLayout {
                Layout.alignment: Qt.AlignRight
                DlgButton {
                    text: qsTr("OK")
                    onClicked: quickUpdateDialog.close()
                }
            }
        }
    }

    // Restart prompt shown when the UI language is changed from the View menu.
    Window {
        id: languageRestartPrompt
        title: qsTr("Restart Required")
        width: 360
        height: langPromptCol.implicitHeight + 24
        flags: Qt.Dialog | Qt.WindowTitleHint | Qt.WindowCloseButtonHint | Qt.MSWindowsFixedSizeDialogHint
        modality: Qt.WindowModal
        transientParent: root
        color: ColorPalette.cardBg
        Material.theme: ColorPalette.materialTheme
        Material.foreground: ColorPalette.textPrimary
        Material.background: ColorPalette.materialBg
        Material.accent: "#4488dd"

        function open() {
            x = root.x + Math.round((root.width  - width)  / 2)
            y = root.y + Math.round((root.height - height) / 2)
            show()
            raise()
            requestActivate()
        }

        ColumnLayout {
            id: langPromptCol
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 16 }
            spacing: 16

            Text {
                Layout.fillWidth: true
                text: qsTr("The interface language has been changed. Stellar must restart to apply it.")
                color: ColorPalette.textPrimary
                font.pixelSize: 12 * App.fontScale
                wrapMode: Text.WordWrap
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                Item { Layout.fillWidth: true }
                DlgButton {
                    text: qsTr("Restart Now")
                    primary: true
                    onClicked: App.restartApp()
                }
                DlgButton {
                    text: qsTr("Later")
                    onClicked: languageRestartPrompt.close()
                }
            }
        }
    }

    Window {
        id: updateAvailableDialog
        title: qsTr("New version of Stellar Download Manager is available")
        transientParent: root
        width: 500
        height: 375
        minimumWidth: 500
        minimumHeight: 375
        flags: Qt.Dialog | Qt.WindowTitleHint | Qt.WindowCloseButtonHint
        modality: Qt.ApplicationModal
        color: ColorPalette.cardBg
        property bool dismissOnClose: true
        // "changelog" → "downloading" → ("installing" on Win | "downloaded" on Linux).
        property string mode: "changelog"
        property string downloadedPath: ""
        property string downloadedId: ""
        property string errorText: ""
        readonly property bool isWindows: Qt.platform.os === "windows"

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

        // Reset to the changelog view each time the dialog is (re)shown.
        function showFromChangelog() {
            mode = "changelog"
            downloadedPath = ""
            downloadedId = ""
            errorText = ""
            show(); raise(); requestActivate()
        }

        Connections {
            target: App
            function onUpdateError(message) {
                if (!updateAvailableDialog.visible)
                    return
                updateAvailableDialog.errorText = message
                updateAvailableDialog.mode = "changelog"
            }
            function onUpdateInstallStarting() {
                updateAvailableDialog.mode = "installing"
            }
            function onUpdateDownloadFinished(id, path) {
                // Windows transitions via onUpdateInstallStarting instead.
                if (updateAvailableDialog.isWindows)
                    return
                updateAvailableDialog.downloadedPath = path
                updateAvailableDialog.downloadedId = id
                updateAvailableDialog.mode = "downloaded"
            }
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 16
            spacing: 12

            Text {
                text: qsTr("Version %1 is available.").arg(App.updateVersion)
                color: ColorPalette.textHeader
                font.pixelSize: 16 * App.fontScale
                font.bold: true
            }

            Rectangle { Layout.fillWidth: true; height: 1; color: ColorPalette.border }

            // ── Changelog (default) ──────────────────────────────────────
            ScrollView {
                id: updateChangelogScroll
                visible: updateAvailableDialog.mode === "changelog"
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                contentWidth: availableWidth

                Text {
                    width: updateChangelogScroll.availableWidth
                    text: App.updateChangelog && App.updateChangelog.length > 0
                        ? App.updateChangelog
                        : "No changelog is available for this update."
                    color: "#cfcfcf"
                    font.pixelSize: 12 * App.fontScale
                    wrapMode: Text.WordWrap
                    textFormat: Text.MarkdownText
                }
            }

            // ── Downloading the installer ────────────────────────────────
            ColumnLayout {
                visible: updateAvailableDialog.mode === "downloading"
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.alignment: Qt.AlignTop
                spacing: 8

                Text {
                    Layout.fillWidth: true
                    text: qsTr("Downloading update %1…").arg(App.updateVersion)
                    color: ColorPalette.textPrimary
                    font.pixelSize: 13 * App.fontScale
                    wrapMode: Text.WordWrap
                }

                // Themed bar — accent fill on a panel track (default Material
                // ProgressBar renders red and ignores the app palette).
                Rectangle {
                    Layout.fillWidth: true
                    height: 8
                    radius: 4
                    color: ColorPalette.panelBg
                    border.color: ColorPalette.border

                    Rectangle {
                        id: dlFill
                        height: parent.height
                        radius: parent.radius
                        color: ColorPalette.accent
                        // Latch monotonically: doneBytes resets to 0 during the
                        // Assembling/merge phase, which would otherwise drop the
                        // bar back to 0. Never let the fill shrink while downloading.
                        property real frac: 0
                        Connections {
                            target: App
                            function onUpdateDownloadProgressChanged() {
                                if (App.updateDownloadTotal > 0) {
                                    var f = Math.max(0, Math.min(1, App.updateDownloadReceived / App.updateDownloadTotal))
                                    if (f > dlFill.frac)
                                        dlFill.frac = f
                                }
                            }
                        }
                        // Reset when (re)entering the downloading state.
                        Connections {
                            target: updateAvailableDialog
                            function onModeChanged() {
                                if (updateAvailableDialog.mode === "downloading")
                                    dlFill.frac = 0
                            }
                        }
                        width: frac * parent.width
                        Behavior on width { NumberAnimation { duration: 120 } }
                    }
                }

                Text {
                    Layout.fillWidth: true
                    visible: App.updateDownloadTotal > 0
                    // Mirror the latched bar: once full, show total/total instead
                    // of the doneBytes dip during Assembling.
                    text: ((dlFill.frac >= 1 ? App.updateDownloadTotal : App.updateDownloadReceived) / 1048576).toFixed(1)
                        + " / " + (App.updateDownloadTotal / 1048576).toFixed(1) + " MB"
                    color: ColorPalette.textSecond
                    font.pixelSize: 11 * App.fontScale
                }

                Item { Layout.fillHeight: true }
            }

            // ── Installing (Windows shutdown notice) ─────────────────────
            ColumnLayout {
                visible: updateAvailableDialog.mode === "installing"
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.alignment: Qt.AlignTop
                spacing: 8

                Text {
                    Layout.fillWidth: true
                    text: qsTr("Stellar is updating to %1.").arg(App.updateVersion)
                    color: ColorPalette.textHeader
                    font.pixelSize: 14 * App.fontScale
                    font.bold: true
                    wrapMode: Text.WordWrap
                }
                Text {
                    Layout.fillWidth: true
                    text: qsTr("The app will now close and reopen automatically. This can take a minute — please wait.")
                    color: ColorPalette.textPrimary
                    font.pixelSize: 13 * App.fontScale
                    wrapMode: Text.WordWrap
                }
                // Themed indeterminate bar: a sliding accent chip on a track.
                Rectangle {
                    Layout.fillWidth: true
                    height: 8
                    radius: 4
                    color: ColorPalette.panelBg
                    border.color: ColorPalette.border
                    clip: true

                    Rectangle {
                        id: installChip
                        height: parent.height
                        radius: parent.radius
                        color: ColorPalette.accent
                        width: parent.width * 0.3
                        x: 0
                        SequentialAnimation on x {
                            running: updateAvailableDialog.mode === "installing"
                            loops: Animation.Infinite
                            NumberAnimation { from: -installChip.width; to: installChip.parent.width; duration: 1100; easing.type: Easing.InOutQuad }
                        }
                    }
                }

                Item { Layout.fillHeight: true }
            }

            // ── Downloaded (Linux reveal) ────────────────────────────────
            ColumnLayout {
                visible: updateAvailableDialog.mode === "downloaded"
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 10

                Item { Layout.fillHeight: true }

                Text {
                    Layout.fillWidth: true
                    text: qsTr("Update package downloaded.")
                    color: ColorPalette.textHeader
                    font.pixelSize: 14 * App.fontScale
                    font.bold: true
                }
                Text {
                    Layout.fillWidth: true
                    text: qsTr("Install it with your package manager to finish updating:")
                    color: ColorPalette.textPrimary
                    font.pixelSize: 13 * App.fontScale
                    wrapMode: Text.WordWrap
                }
                Text {
                    Layout.fillWidth: true
                    text: updateAvailableDialog.downloadedPath
                    color: ColorPalette.textSecond
                    font.pixelSize: 11 * App.fontScale
                    wrapMode: Text.WrapAnywhere
                }

                Item { Layout.fillHeight: true }
            }

            // ── Error banner (shared) ────────────────────────────────────
            Text {
                Layout.fillWidth: true
                visible: updateAvailableDialog.errorText.length > 0
                text: updateAvailableDialog.errorText
                color: "#e06666"
                font.pixelSize: 12 * App.fontScale
                wrapMode: Text.WordWrap
            }

            RowLayout {
                Layout.alignment: Qt.AlignRight
                spacing: 8

                DlgButton {
                    text: updateAvailableDialog.isWindows ? qsTr("Update Now") : qsTr("Download")
                    primary: true
                    visible: updateAvailableDialog.mode === "changelog"
                    onClicked: {
                        updateAvailableDialog.errorText = ""
                        if (App.startUpdateInstall()) {
                            updateAvailableDialog.dismissOnClose = false
                            updateAvailableDialog.mode = "downloading"
                        } else {
                            updateAvailableDialog.errorText =
                                qsTr("Stellar could not start the update installer download.")
                        }
                    }
                }

                DlgButton {
                    text: qsTr("Reveal in Folder")
                    primary: true
                    visible: updateAvailableDialog.mode === "downloaded"
                    onClicked: App.openFolderSelectFile(updateAvailableDialog.downloadedId)
                }

                DlgButton {
                    text: updateAvailableDialog.mode === "downloaded" ? qsTr("Close") : qsTr("Cancel")
                    // No cancelling once the Windows installer is launching.
                    visible: updateAvailableDialog.mode !== "installing"
                    onClicked: {
                        App.dismissAvailableUpdate()
                        updateAvailableDialog.dismissOnClose = false
                        updateAvailableDialog.close()
                    }
                }
            }
        }
    }

    // ── What's New / Changelog viewer ────────────────────────────────────
    Window {
        id: whatsNewDialog
        title: qsTr("What's New in Stellar")
        transientParent: root
        width: 500
        height: 375
        minimumWidth: 500
        minimumHeight: 375
        flags: Qt.Dialog | Qt.WindowTitleHint | Qt.WindowCloseButtonHint
        modality: Qt.ApplicationModal
        color: ColorPalette.cardBg

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
                color: ColorPalette.textHeader
                font.pixelSize: 16 * App.fontScale
                font.bold: true
            }

            Rectangle { Layout.fillWidth: true; height: 1; color: ColorPalette.border }

            ScrollView {
                id: whatsNewScroll
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                contentWidth: availableWidth

                Text {
                    width: whatsNewScroll.availableWidth
                    text: App.updateChangelog && App.updateChangelog.length > 0
                        ? App.updateChangelog
                        : "No changelog is available."
                    color: "#cfcfcf"
                    font.pixelSize: 12 * App.fontScale
                    wrapMode: Text.WordWrap
                    textFormat: Text.MarkdownText
                }
            }

            RowLayout {
                Layout.alignment: Qt.AlignRight
                DlgButton {
                    text: qsTr("Close")
                    onClicked: whatsNewDialog.close()
                }
            }
        }
    }

    // ── Scheduler Dialog ─────────────────────────────────────────────────
    SchedulerDialog { id: schedulerDialog; transientParent: root }

    // ── Batch Download Dialogs ───────────────────────────────────────────
    BatchDownloadDialog {
        id: batchDownloadDialog
        transientParent: root
        onAccepted: (files) => {
            var urlList = []
            if (Array.isArray(files)) {
                urlList = files
            } else {
                var textPayload = (files === undefined || files === null) ? "" : String(files)
                urlList = textPayload.split('\n')
            }
            var fileObjs = []
            for(var i=0; i<urlList.length; i++) {
                var rawUrl = (urlList[i] === undefined || urlList[i] === null) ? "" : String(urlList[i]).trim()
                if(rawUrl.length > 0) {
                    var _name3 = ""
                    if (rawUrl.toLowerCase().startsWith("magnet:?"))
                        _name3 = extractMagnetDisplayName(rawUrl)
                    if (_name3.length === 0)
                        _name3 = rawUrl.split('/').pop()
                    fileObjs.push({ name: _name3, url: rawUrl })
                }
            }
            batchDownloadListDialog.files = fileObjs
            batchDownloadListDialog.isImport = false
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
                    var f = files[i]
                    var _burl = f.url
                    var _bl = _burl.toLowerCase()
                    var sp = f.savePath || ""
                    var cat = f.category || ""
                    var desc = f.description || ""
                    var ref = f.referer || ""
                    var uname = f.username || ""
                    var pword = f.password || ""
                    if (_bl.startsWith("magnet:?") || _bl.endsWith(".torrent"))
                        App.silentlyAddTorrent(_burl, sp, cat, desc, true)
                    else
                        App.addUrl(_burl, sp, cat, desc, true, "", ref, "", uname, pword, f.filename)
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
        onResultsRequested: (projectId) => {
            grabberResultsDialog.projectId = projectId
            grabberResultsDialog.show()
            grabberResultsDialog.raise()
            grabberResultsDialog.requestActivate()
        }
    }

    GrabberResultsDialog {
        id: grabberResultsDialog
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

    GrabberStatisticsDialog { id: grabberStatisticsDialog }

    // ── Statistics Dialog ────────────────────────────────────────────────
    StatisticsDialog { id: statisticsDialog }
    ExportDialog {
        id: exportDialog
        transientParent: root
        downloadTableRef: downloadTable
        onAccepted: (mode) => {
            var items = []
            if (mode === "selected") {
                items = downloadTable._selectedItems()
            } else if (mode === "queue") {
                var queueId = App.selectedQueue || ""
                for (var qi = 0; qi < App.downloadModel.rowCount(); qi++) {
                    var qitem = App.downloadModel.itemAt(qi)
                    if (qitem && qitem.queueId === queueId)
                        items.push(qitem)
                }
            } else {
                for (var ai = 0; ai < App.downloadModel.rowCount(); ai++) {
                    var aitem = App.downloadModel.itemAt(ai)
                    if (aitem)
                        items.push(aitem)
                }
            }
            if (items.length === 0)
                return
            root._pendingExportItems = items
            if (root._pendingExportFormat === "txt")
                exportTxtDialog.open()
            else
                exportEf2Dialog.open()
        }
    }

    // ── Browser Integration Dialog ───────────────────────────────────────
    BrowserIntegrationDialog { id: browserIntegrationDialog; transientParent: root }


    // ── Add Exception Dialog ─────────────────────────────────────────────
    AddExceptionDialog { id: addExceptionDialog; transientParent: root }

    // ── Delete Done Confirm Dialog ───────────────────────────────────────
    DeleteDoneConfirmDialog {
        id: deleteDoneConfirmDialog
        transientParent: root
        onConfirmed: (includeSeedingTorrents) => App.deleteAllCompleted(0, includeSeedingTorrents)
    }

    // ── File Properties Dialog ───────────────────────────────────────────
    FilePropertiesDialog { id: filePropertiesDialog; transientParent: root }

// ── Columns Dialog ───────────────────────────────────────────────────────
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

    // ── Toolbar Dialog ───────────────────────────────────────────────────
    ToolbarDialog {
        id: toolbarDialog
        transientParent: root
        onLocalDefsChanged: {
            // Real-time preview: update toolbar immediately without saving
            toolbar.buttonDefs = toolbarDialog.localDefs.slice()
        }
        onToolbarChanged: (defs) => {
            if (defs === null) {
                var defaults = toolbarDialog._defaultDefs()
                toolbar.buttonDefs = defaults
                toolbarDialog.buttonDefs = defaults
                toolbarDialog.localDefs = defaults.slice()
                App.settings.toolbarButtonDefs = ""
            } else {
                toolbar.buttonDefs = defs
                App.settings.toolbarButtonDefs = JSON.stringify(defs)
                // Sync View menu toggles with toolbar dialog state for search/rss
                var foundSearch = false, foundRss = false
                for (var ti = 0; ti < defs.length; ti++) {
                    if (defs[ti].key === "search_engine") {
                        foundSearch = true
                        App.settings.showSearchEngine = !!defs[ti].enabled
                    }
                    if (defs[ti].key === "rss") {
                        foundRss = true
                        App.settings.showRssReader = !!defs[ti].enabled
                    }
                }
                // If entry removed from defs entirely, keep View menu toggle as-is
            }
        }
    }

    // ── Tips timer and display ───────────────────────────────────────────
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
        _syncTableActive()
        App.setWindowDarkTitleBar(root, App.settings.darkMode)
        // Initial hidden state (login --minimized / cold-start intercept) is set
        // by the `visible` binding above to avoid a startup flash. Nothing to do
        // here — the tray icon is always visible regardless.
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

    // ── Menu bar ─────────────────────────────────────────────────────────
    menuBar: MenuBar {
        id: appMenuBar
        background: Rectangle {
            color: ColorPalette.panelBg
            Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: ColorPalette.border }
        }

        // Shared compact MenuItem delegate used by all drop-down menus.
        // Dense Material gives 24px items; we trim to 22px with smaller font.
        component CompactMenuItem: MenuItem {
            id: _cmi
            implicitHeight: 22
            height: 22
            topPadding: 0; bottomPadding: 0; verticalPadding: 0
            leftPadding: 8; rightPadding: 12
            spacing: 0
            font.pixelSize: 12 * App.fontScale
            property string iconSrc: ""
            property string shortcutDisplay: ""
            indicator: Item {
                width: _cmi.checkable ? 16 : 0
                height: _cmi.checkable ? 16 : 0
                Text {
                    text: "✓"
                    visible: _cmi.checkable && _cmi.checked
                    color: "#4488dd"
                    font.pixelSize: 12 * App.fontScale
                    anchors.centerIn: parent
                }
            }
            arrow: Text {
                x: _cmi.width - width - 8
                anchors.verticalCenter: parent ? parent.verticalCenter : undefined
                text: "▶"
                font.pixelSize: 8 * App.fontScale
                color: ColorPalette.textMuted
                visible: _cmi.subMenu !== null
            }
            contentItem: RowLayout {
                spacing: 6
                anchors.verticalCenter: parent ? parent.verticalCenter : undefined
                Image {
                    visible: _cmi.iconSrc !== ""
                    source: _cmi.iconSrc
                    width: 14; height: 14
                    sourceSize.width: 14; sourceSize.height: 14
                    fillMode: Image.PreserveAspectFit
                    smooth: true
                    Layout.preferredWidth: visible ? 14 : 0
                    Layout.preferredHeight: 14
                }
                Item { visible: _cmi.iconSrc === ""; Layout.preferredWidth: 0; Layout.preferredHeight: 14 }
                Text {
                    text: _cmi.text
                    font: _cmi.font
                    color: _cmi.enabled ? ColorPalette.textPrimary : ColorPalette.textDisabled
                    verticalAlignment: Text.AlignVCenter
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }
                Text {
                    text: _cmi.shortcutDisplay
                    color: ColorPalette.textMuted
                    font.pixelSize: 11 * App.fontScale
                    visible: text !== ""
                    verticalAlignment: Text.AlignVCenter
                    Layout.leftMargin: 12
                }
            }
            background: Rectangle {
                implicitHeight: 22
                // Opaque, never "transparent" — see ColorPalette.menuBg.
                color: _cmi.highlighted ? ColorPalette.selectionBg : ColorPalette.menuBg
            }
        }

        // Themed menu separator -- the default Material MenuSeparator draws a
        // near-invisible line in light mode. Force a visible divider colour.
        component CompactSep: MenuSeparator {
            padding: 0
            topPadding: 3; bottomPadding: 3
            // Opaque, never "transparent" — see ColorPalette.menuBg.
            background: Rectangle { color: ColorPalette.menuBg }
            contentItem: Rectangle {
                implicitWidth: 180
                implicitHeight: 1
                color: ColorPalette.border
            }
        }

        delegate: MenuBarItem {
            verticalPadding: 0
            leftPadding: 12
            rightPadding: 12
            contentItem: Text {
                text: parent.text
                font: parent.font
                color: ColorPalette.textPrimary
                verticalAlignment: Text.AlignVCenter
            }
            background: Rectangle {
                implicitHeight: 20
                color: parent.highlighted ? ColorPalette.selectionBg : "transparent"
            }
        }

        // ── Keyboard shortcuts for menu actions Action.shortcut works at window scope. ──
        Action { shortcut: "Ctrl+N";       onTriggered: { addUrlDialog.show(); addUrlDialog.raise() } }
        Action { shortcut: "Ctrl+Shift+T"; onTriggered: addTorrentFileDialog.open() }
        Action { shortcut: "Ctrl+Shift+N"; onTriggered: { batchDownloadDialog.show(); batchDownloadDialog.raise() } }
        Action { shortcut: "Ctrl+Q";       onTriggered: root.quitApp() }
        Action { shortcut: "Ctrl+F";       onTriggered: { root.findBarActive = true; findBarField.forceActiveFocus() } }

        Action { shortcut: "F3";           onTriggered: downloadTable.findNextFiltered() }
        Action { shortcut: "Ctrl+,";       onTriggered: root.showSettingsPage(root.settingsPageGeneral) }
        Action { shortcut: "Ctrl+S";       onTriggered: downloadTable.resumeSelected() }
        Action { shortcut: "Ctrl+Shift+P"; onTriggered: root.toggleSessionPause() }
        Action { shortcut: "Ctrl+I";       onTriggered: { statisticsDialog.show(); statisticsDialog.raise(); statisticsDialog.requestActivate() } }
        Action { shortcut: "Ctrl+Shift+C"; onTriggered: { torrentCreatorDialog.show(); torrentCreatorDialog.raise(); torrentCreatorDialog.requestActivate() } }
        Action { shortcut: "Ctrl+D";       onTriggered: downloadTable.deselectAll() }
        Action { shortcut: "Alt+O";        onTriggered: root.showSettingsPage(root.settingsPageGeneral) }
        Action { shortcut: "Ctrl+K";       onTriggered: downloadTable.pauseAll() }
        Action { shortcut: "Ctrl+Shift+W"; onTriggered: { deleteDoneConfirmDialog.show(); deleteDoneConfirmDialog.raise() } }
        Action { shortcut: "Ctrl+P";       onTriggered: { var item = root.selectedDownloadItem; if (item && (item.status === "Downloading" || item.status === "Queued" || item.status === "Seeding")) App.pauseDownload(item.id) } }
        Action { shortcut: "Ctrl+R";       onTriggered: { var item = root.selectedDownloadItem; if (item) App.redownload(item.id) } }
        Action { shortcut: "Ctrl+/";       onTriggered: root.showSettingsPage(root.settingsPageAbout) }
        Action { shortcut: "Ctrl+Shift+L"; onTriggered: { if (App.settings.speedLimiterEnabled) App.disableSpeedLimiter(); else App.enableSpeedLimiter() } }

        Menu {
            id: _tasksMenu
            title: qsTr("Tasks")
            delegate: CompactMenuItem
            implicitWidth: 260; padding: 0
            CompactMenuItem { text: qsTr("Add URL…"); shortcutDisplay: "Ctrl+N"; iconSrc: "icons/add_url.svg";  onTriggered: { addUrlDialog.show(); addUrlDialog.raise() } }
            CompactMenuItem { text: qsTr("Add Torrent File…"); iconSrc: "icons/torrent_file.svg";   onTriggered: addTorrentFileDialog.open() }
            CompactMenuItem { text: qsTr("Add Batch URLs…");   iconSrc: "icons/add.svg";      onTriggered: { batchDownloadDialog.show(); batchDownloadDialog.raise() } }
            CompactMenuItem {
                text: qsTr("Add Batch URLs from Clipboard…")
                iconSrc: "icons/clipboard.svg"
                onTriggered: {
                    var urls = App.clipboardUrls()
                    if (!urls || urls.length === 0)
                        return
                    var fileObjs = []
                    for (var i = 0; i < urls.length; ++i) {
                        var _u = urls[i]
                        var _n = _u.split('/').pop().split('?')[0] || ""
                        fileObjs.push({ name: _n, url: _u })
                    }
                    batchDownloadListDialog.files = fileObjs
                    batchDownloadListDialog.isImport = true
                    batchDownloadListDialog.show()
                    batchDownloadListDialog.raise()
                }
            }
            CompactSep {}
            CompactMenuItem {
                id: _exportMenuItem
                text: qsTr("Export") + "  ▶"
                onTriggered: _exportMenu.popup(_exportMenuItem.width, 0)
                onHoveredChanged: {
                    if (hovered) { _exportMenu.popup(_exportMenuItem.width, 0) }
                    else { _exportCloseTimer.restart() }
                }
                Menu {
                    id: _exportMenu
                    delegate: CompactMenuItem; implicitWidth: 260; topPadding: 0; bottomPadding: 0
                    onAboutToHide: _exportCloseTimer.stop()
                    CompactMenuItem {
                        text: qsTr("To SDM Export File (.ef2)…")
                        onTriggered: {
                            root._pendingExportFormat = "ef2"
                            exportDialog.show()
                            exportDialog.raise()
                            _tasksMenu.dismiss()
                        }
                    }
                    CompactMenuItem {
                        text: qsTr("To Text File…")
                        onTriggered: {
                            root._pendingExportFormat = "txt"
                            exportDialog.show()
                            exportDialog.raise()
                            _tasksMenu.dismiss()
                        }
                    }
                }
                Timer { id: _exportCloseTimer; interval: 300; onTriggered: { if (!_exportMenu.activeFocus) _exportMenu.close() } }
            }
            CompactMenuItem {
                id: _importMenuItem
                text: qsTr("Import") + "  ▶"
                onTriggered: _importMenu.popup(_importMenuItem.width, 0)
                onHoveredChanged: {
                    if (hovered) { _importMenu.popup(_importMenuItem.width, 0) }
                    else { _importCloseTimer.restart() }
                }
                Menu {
                    id: _importMenu
                    delegate: CompactMenuItem; implicitWidth: 260; topPadding: 0; bottomPadding: 0
                    onAboutToHide: _importCloseTimer.stop()
                    CompactMenuItem {
                        text: qsTr("From SDM Export File (.ef2)…")
                        onTriggered: { importEf2Dialog.open(); _tasksMenu.dismiss() }
                    }
                    CompactMenuItem {
                        text: qsTr("From Text File…")
                        onTriggered: { importTxtDialog.open(); _tasksMenu.dismiss() }
                    }
                }
                Timer { id: _importCloseTimer; interval: 300; onTriggered: { if (!_importMenu.activeFocus) _importMenu.close() } }
            }
            CompactSep {}
            CompactMenuItem { text: qsTr("Exit"); shortcutDisplay: "Ctrl+Q"; iconSrc: "icons/exit.svg"; onTriggered: root.quitApp() }
        }
        Menu {
            title: qsTr("File")
            delegate: CompactMenuItem
            implicitWidth: 260; padding: 0
            CompactMenuItem {
                text: qsTr("Open Folder")
                shortcutDisplay: "Ctrl+Enter"
                iconSrc: "icons/folder_view.svg"
                enabled: root.selectedDownloadItem && (root.selectedDownloadItem.status === "Completed" || root.selectedDownloadItem.status === "Seeding")
                onTriggered: { var item = root.selectedDownloadItem; if (item && (item.status === "Completed" || item.status === "Seeding")) App.openFolder(item.id) }
            }
            CompactMenuItem {
                text: qsTr("Open File")
                shortcutDisplay: "Enter"
                iconSrc: "icons/page.svg"
                enabled: root.selectedDownloadItem && (root.selectedDownloadItem.status === "Completed" || root.selectedDownloadItem.status === "Seeding")
                onTriggered: { var item = root.selectedDownloadItem; if (item && (item.status === "Completed" || item.status === "Seeding")) App.openFile(item.id) }
            }
            CompactSep {}
            CompactMenuItem {
                text: qsTr("Download Now")
                shortcutDisplay: "Ctrl+S"
                iconSrc: "icons/resume.svg"
                enabled: root.selectedDownloadItem && root.selectedDownloadItem.status === "Paused"
                onTriggered: { var item = root.selectedDownloadItem; if (item && item.status === "Paused") App.resumeDownload(item.id) }
            }
            CompactMenuItem {
                text: qsTr("Stop Download")
                shortcutDisplay: "Ctrl+P"
                iconSrc: "icons/pause.svg"
                enabled: root.selectedDownloadItem && (root.selectedDownloadItem.status === "Downloading" || root.selectedDownloadItem.status === "Queued" || root.selectedDownloadItem.status === "Seeding")
                onTriggered: { var item = root.selectedDownloadItem; if (item && (item.status === "Downloading" || item.status === "Queued" || item.status === "Seeding")) App.pauseDownload(item.id) }
            }
            CompactMenuItem {
                text: qsTr("Remove")
                shortcutDisplay: "Del"
                iconSrc: "icons/delete.svg"
                enabled: root.selectedDownloadItem !== null
                onTriggered: root.selectedDownloadItem ? downloadTable.deleteSelected() : null
            }
            CompactMenuItem {
                text: qsTr("Redownload")
                shortcutDisplay: "Ctrl+R"
                iconSrc: "icons/update.svg"
                enabled: root.selectedDownloadItem !== null
                onTriggered: { var item = root.selectedDownloadItem; if (item) App.redownload(item.id) }
            }
            CompactMenuItem {
                text: qsTr("Export .torrent…")
                iconSrc: "icons/export_torrent.svg"
                enabled: root.selectedTorrentCount > 0
                onTriggered: {
                    root.pendingTorrentExportIds = downloadTable.selectedTorrentIds()
                    if (root.pendingTorrentExportIds.length > 0)
                        exportTorrentFolderDialog.open()
                }
            }
            CompactMenuItem {
                text: qsTr("Create Torrent…")
                shortcutDisplay: "Ctrl+Shift+C"
                iconSrc: "icons/new_file.svg"
                onTriggered: {
                    torrentCreatorDialog.show()
                    torrentCreatorDialog.raise()
                    torrentCreatorDialog.requestActivate()
                }
            }
        }
        Menu {
            id: _downloadsMenu
            title: qsTr("Downloads")
            delegate: CompactMenuItem
            implicitWidth: 260; padding: 0
            CompactMenuItem { text: qsTr("Stop all"); shortcutDisplay: "Ctrl+K"; iconSrc: "icons/stop_all.svg";  onTriggered: downloadTable.pauseAll() }
            CompactSep {}
            CompactMenuItem { text: qsTr("Delete all completed"); shortcutDisplay: "Ctrl+Shift+W"; iconSrc: "icons/delete.svg";        onTriggered: { deleteDoneConfirmDialog.show(); deleteDoneConfirmDialog.raise() } }
            CompactSep {}
            CompactMenuItem { text: qsTr("Find…"); shortcutDisplay: "Ctrl+F"; iconSrc: "icons/magnifying_glass.svg"; onTriggered: { root.findBarActive = true; findBarField.forceActiveFocus() } }
            CompactMenuItem { text: qsTr("Find Next"); shortcutDisplay: "F3"; iconSrc: "icons/magnifying_glass.svg"; onTriggered: downloadTable.findNextFiltered() }
            CompactSep {}
            CompactMenuItem { text: qsTr("Scheduler"); iconSrc: "icons/scheduler.svg"; onTriggered: schedulerDialog.show() }
            CompactMenuItem {
                id: _startQueueItem
                text: qsTr("Start Queue") + "  ▶"
                onTriggered: _startQueueMenu.popup(_startQueueItem.width, 0)
                onHoveredChanged: {
                    if (hovered) { _startQueueMenu.popup(_startQueueItem.width, 0) }
                    else { _sqCloseTimer.restart() }
                }
                Menu {
                    id: _startQueueMenu
                    delegate: CompactMenuItem; implicitWidth: 260; topPadding: 0; bottomPadding: 0
                    onAboutToHide: _sqCloseTimer.stop()
                    Repeater {
                        model: App.queueModel
                        delegate: CompactMenuItem {
                            visible: queueId !== "download-limits"; height: visible ? 22 : 0
                            text: queueName || ""; onTriggered: { App.startQueue(queueId); _downloadsMenu.dismiss() }
                        }
                    }
                }
                Timer { id: _sqCloseTimer; interval: 300; onTriggered: { if (!_startQueueMenu.activeFocus) _startQueueMenu.close() } }
            }
            CompactMenuItem {
                id: _stopQueueItem
                text: qsTr("Stop Queue") + "  ▶"
                onTriggered: _stopQueueMenu.popup(_stopQueueItem.width, 0)
                onHoveredChanged: {
                    if (hovered) { _stopQueueMenu.popup(_stopQueueItem.width, 0) }
                    else { _stqCloseTimer.restart() }
                }
                Menu {
                    id: _stopQueueMenu
                    delegate: CompactMenuItem; implicitWidth: 260; topPadding: 0; bottomPadding: 0
                    onAboutToHide: _stqCloseTimer.stop()
                    Repeater {
                        model: App.queueModel
                        delegate: CompactMenuItem {
                            visible: queueId !== "download-limits"; height: visible ? 22 : 0
                            text: queueName || ""; onTriggered: { App.stopQueue(queueId); _downloadsMenu.dismiss() }
                        }
                    }
                }
                Timer { id: _stqCloseTimer; interval: 300; onTriggered: { if (!_stopQueueMenu.activeFocus) _stopQueueMenu.close() } }
            }
            CompactSep {}
            CompactMenuItem {
                id: _speedLimiterItem1
                iconSrc: "icons/snail.svg"
                text: qsTr("Speed Limiter") + "  ▶"
                shortcutDisplay: "Ctrl+Shift+L"
                onTriggered: _speedLimiterMenu1.popup(_speedLimiterItem1.width, 0)
                onHoveredChanged: {
                    if (hovered) { _speedLimiterMenu1.popup(_speedLimiterItem1.width, 0) }
                    else { _sl1CloseTimer.restart() }
                }
                Menu {
                    id: _speedLimiterMenu1
                    delegate: CompactMenuItem; implicitWidth: 260; topPadding: 0; bottomPadding: 0
                    onAboutToHide: _sl1CloseTimer.stop()
                    CompactMenuItem { text: (App.settings.speedLimiterEnabled ? "✓" : "    ") + qsTr("Turn On");  onTriggered: { App.enableSpeedLimiter(); _downloadsMenu.dismiss() } }
                    CompactMenuItem { text: (!App.settings.speedLimiterEnabled ? "✓" : "    ") + qsTr("Turn Off"); onTriggered: { App.disableSpeedLimiter(); _downloadsMenu.dismiss() } }
                    CompactSep {}
                    CompactMenuItem { text: qsTr("Settings…"); onTriggered: { settingsDialog.initialPage = root.settingsPageSpeedLimiter; settingsDialog.show(); _downloadsMenu.dismiss() } }
                }
                Timer { id: _sl1CloseTimer; interval: 300; onTriggered: { if (!_speedLimiterMenu1.activeFocus) _speedLimiterMenu1.close() } }
            }
            CompactMenuItem {
                iconSrc: "icons/pause.svg"
                text: qsTr("Pause Session")
                shortcutDisplay: "Ctrl+Shift+P"
                checkable: true
                checked: App.sessionPaused
                onTriggered: App.sessionPaused ? App.resumeSession() : App.pauseSession()
            }
            CompactSep {}
            CompactMenuItem { text: qsTr("Options…"); shortcutDisplay: "Alt+O"; iconSrc: "icons/gear.svg"; onTriggered: root.showSettingsPage(root.settingsPageGeneral) }
        }
        Menu {
            id: _viewMenu
            title: qsTr("View")
            delegate: CompactMenuItem
            implicitWidth: 260; padding: 0
            CompactMenuItem {
                text: (sidebar && sidebar.visible) ? qsTr("Hide Categories") : qsTr("Show Categories")
                iconSrc: "icons/categories.svg"
                onTriggered: if (sidebar) sidebar.visible = !sidebar.visible
            }
            CompactMenuItem {
                text: App.settings.showStatusBar ? qsTr("Hide Status Bar") : qsTr("Show Status Bar")
                iconSrc: "icons/statusbar.svg"
                onTriggered: Qt.callLater(function() { App.settings.showStatusBar = !App.settings.showStatusBar })
            }
            CompactMenuItem {
                id: _trayIconStyleItem
                text: qsTr("SDM Tray Icon") + "  ▶"
                iconSrc: "icons/milky-way.png"
                onTriggered: _trayIconStyleMenu.popup(_trayIconStyleItem.width, 0)
                onHoveredChanged: {
                    if (hovered) _trayIconStyleMenu.popup(_trayIconStyleItem.width, 0)
                    else _trayIconStyleCloseTimer.restart()
                }
                Menu {
                    id: _trayIconStyleMenu
                    delegate: CompactMenuItem; implicitWidth: 200; topPadding: 0; bottomPadding: 0
                    onAboutToHide: _trayIconStyleCloseTimer.stop()
                    CompactMenuItem {
                        text: (App.settings.trayIconStyle === 0 ? "✓ " : "    ") + qsTr("Colored")
                        onTriggered: { App.settings.trayIconStyle = 0; _viewMenu.dismiss() }
                    }
                    CompactMenuItem {
                        text: (App.settings.trayIconStyle === 1 ? "✓ " : "    ") + qsTr("Light")
                        onTriggered: { App.settings.trayIconStyle = 1; _viewMenu.dismiss() }
                    }
                    CompactMenuItem {
                        text: (App.settings.trayIconStyle === 2 ? "✓ " : "    ") + qsTr("Dark")
                        onTriggered: { App.settings.trayIconStyle = 2; _viewMenu.dismiss() }
                    }
                }
                Timer { id: _trayIconStyleCloseTimer; interval: 300; onTriggered: { if (!_trayIconStyleMenu.activeFocus) _trayIconStyleMenu.close() } }
            }
            CompactSep {}
            CompactMenuItem {
                text: App.settings.darkMode ? qsTr("Switch to Light Mode") : qsTr("Switch to Dark Mode")
                iconSrc: App.settings.darkMode ? "icons/lightmode.svg" : "icons/darkmode.svg"
                onTriggered: { App.settings.darkMode = !App.settings.darkMode; _viewMenu.dismiss() }
            }
            CompactSep {}
            CompactMenuItem {
                text: (App.settings.showSearchEngine ? "✓ " : "    ") + qsTr("Show Search Engine")
                // Defer the toggle so the View menu fully dismisses before the
                // menu-bar layout changes; otherwise the menu-bar focus chain
                // can jump to a newly-revealed neighbor and open it.
                onTriggered: Qt.callLater(function() { App.settings.showSearchEngine = !App.settings.showSearchEngine })
            }
            CompactMenuItem {
                text: (App.settings.showRssReader ? "✓ " : "    ") + qsTr("Show RSS Reader")
                onTriggered: Qt.callLater(function() { App.settings.showRssReader = !App.settings.showRssReader })
            }
            CompactSep {}
            CompactMenuItem {
                text: qsTr("Statistics…")
                shortcutDisplay: "Ctrl+I"
                iconSrc: "icons/bar_chart.svg"
                onTriggered: { statisticsDialog.show(); statisticsDialog.raise(); statisticsDialog.requestActivate() }
            }
            CompactSep {}
            CompactMenuItem {
                id: _arrangeFilesItem
                text: qsTr("Arrange Files") + "  ▶"
                onTriggered: _arrangeFilesMenu.popup(_arrangeFilesItem.width, 0)
                onHoveredChanged: {
                    if (hovered) { _arrangeFilesMenu.popup(_arrangeFilesItem.width, 0) }
                    else { _arrangeFilesCloseTimer.restart() }
                }
                Menu {
                    id: _arrangeFilesMenu
                    delegate: CompactMenuItem; implicitWidth: 260; topPadding: 0; bottomPadding: 0
                    onAboutToHide: _arrangeFilesCloseTimer.stop()
                    CompactMenuItem { text: qsTr("By Order Of Addition");  onTriggered: { App.sortDownloads("added", true);       _viewMenu.dismiss() } }
                    CompactMenuItem { text: qsTr("By File Name");          onTriggered: { App.sortDownloads("name", true);        _viewMenu.dismiss() } }
                    CompactMenuItem { text: qsTr("By Size");               onTriggered: { App.sortDownloads("size", true);        _viewMenu.dismiss() } }
                    CompactMenuItem { text: qsTr("By Status");             onTriggered: { App.sortDownloads("status", true);      _viewMenu.dismiss() } }
                    CompactMenuItem { text: qsTr("By Time Left");          onTriggered: { App.sortDownloads("timeleft", true);    _viewMenu.dismiss() } }
                    CompactMenuItem { text: qsTr("By Transfer Rate");      onTriggered: { App.sortDownloads("speed", false);      _viewMenu.dismiss() } }
                    CompactMenuItem { text: qsTr("By Last Try Date");      onTriggered: { App.sortDownloads("lasttry", false);    _viewMenu.dismiss() } }
                    CompactMenuItem { text: qsTr("By Description");        onTriggered: { App.sortDownloads("description", true); _viewMenu.dismiss() } }
                    CompactMenuItem { text: qsTr("By Save Path");          onTriggered: { App.sortDownloads("saveto", true);      _viewMenu.dismiss() } }
                    CompactMenuItem { text: qsTr("By Referer");            onTriggered: { App.sortDownloads("referrer", true);    _viewMenu.dismiss() } }
                    CompactMenuItem { text: qsTr("By Parent Web Page");    onTriggered: { App.sortDownloads("parenturl", true);   _viewMenu.dismiss() } }
                }
                Timer { id: _arrangeFilesCloseTimer; interval: 300; onTriggered: { if (!_arrangeFilesMenu.activeFocus) _arrangeFilesMenu.close() } }
            }
            CompactSep {}
            CompactMenuItem { text: qsTr("Columns…"); iconSrc: "icons/columns.svg"; onTriggered: {
                columnsDialog.columnDefs = downloadTable.columnDefs.slice()
                columnsDialog.show()
                columnsDialog.raise()
            }}
            CompactMenuItem {
                id: _toolbarItem
                iconSrc: "icons/toolbar.svg"
                text: qsTr("Toolbar") + "  ▶"
                onTriggered: _toolbarMenu.popup(_toolbarItem.width, 0)
                onHoveredChanged: {
                    if (hovered) _toolbarMenu.popup(_toolbarItem.width, 0)
                    else _toolbarMenuCloseTimer.restart()
                }
                Menu {
                    id: _toolbarMenu
                    delegate: CompactMenuItem; implicitWidth: 220; topPadding: 0; bottomPadding: 0
                    onAboutToHide: _toolbarMenuCloseTimer.stop()
                    CompactMenuItem {
                        text: qsTr("Toolbar Settings…")
                        // Rehydrate via Toolbar so saved labels are replaced with fresh
                        // translated ones (saved JSON holds stale English labels).
                        onTriggered: {
                            toolbarDialog.buttonDefs = toolbar._loadButtonDefs()
                            toolbarDialog.show()
                            toolbarDialog.raise()
                            _viewMenu.dismiss()
                        }
                    }
                    CompactSep {}
                    CompactMenuItem {
                        text: (!App.settings.toolbarSmallButtons ? "✓" : "    ") + qsTr("Large Buttons")
                        onTriggered: { App.settings.toolbarSmallButtons = false; _viewMenu.dismiss() }
                    }
                    CompactMenuItem {
                        text: (App.settings.toolbarSmallButtons ? "✓" : "    ") + qsTr("Small Buttons")
                        onTriggered: { App.settings.toolbarSmallButtons = true; _viewMenu.dismiss() }
                    }
                }
                Timer { id: _toolbarMenuCloseTimer; interval: 300; onTriggered: { if (!_toolbarMenu.activeFocus) _toolbarMenu.close() } }
            }
            CompactSep {}
            CompactMenuItem {
                id: _languageItem
                iconSrc: "icons/language.svg"
                text: qsTr("Language") + "  ▶"
                onTriggered: _languageMenu.popup(_languageItem.width, 0)
                onHoveredChanged: {
                    if (hovered) _languageMenu.popup(_languageItem.width, 0)
                    else _languageMenuCloseTimer.restart()
                }
                Menu {
                    id: _languageMenu
                    delegate: CompactMenuItem
                    implicitWidth: 240
                    topPadding: 0; bottomPadding: 0
                    // Cap height so the list scrolls instead of running off-screen.
                    height: Math.min(implicitHeight, 460)
                    onAboutToHide: _languageMenuCloseTimer.stop()

                    Repeater {
                        model: LanguageList.entries
                        delegate: CompactMenuItem {
                            required property var modelData
                            text: (App.settings.uiLanguage === modelData.code ? "✓ " : "    ") + modelData.display
                            onTriggered: {
                                var changed = App.settings.uiLanguage !== modelData.code
                                App.settings.uiLanguage = modelData.code
                                App.applyUiLanguage(modelData.code)
                                _viewMenu.dismiss()
                                if (changed)
                                    languageRestartPrompt.open()
                            }
                        }
                    }
                }
                Timer { id: _languageMenuCloseTimer; interval: 300; onTriggered: { if (!_languageMenu.activeFocus) _languageMenu.close() } }
            }
        }
        Menu {
            id: _optionsMenu
            title: qsTr("Options")
            delegate: CompactMenuItem
            implicitWidth: 260; padding: 0
            CompactMenuItem { text: qsTr("Preferences…"); shortcutDisplay: "Ctrl+,"; iconSrc: "icons/gear.svg";      onTriggered: root.showSettingsPage(root.settingsPageGeneral) }
            CompactMenuItem { text: qsTr("Scheduler");    iconSrc: "icons/scheduler.svg"; onTriggered: schedulerDialog.show() }
            CompactMenuItem {
                id: _speedLimiterItem2
                iconSrc: "icons/snail.svg"
                text: qsTr("Speed Limiter") + "  ▶"
                shortcutDisplay: "Ctrl+Shift+L"
                onTriggered: _speedLimiterMenu2.popup(_speedLimiterItem2.width, 0)
                onHoveredChanged: {
                    if (hovered) { _speedLimiterMenu2.popup(_speedLimiterItem2.width, 0) }
                    else { _sl2CloseTimer.restart() }
                }
                Menu {
                    id: _speedLimiterMenu2
                    delegate: CompactMenuItem; implicitWidth: 260; topPadding: 0; bottomPadding: 0
                    onAboutToHide: _sl2CloseTimer.stop()
                    CompactMenuItem { text: (App.settings.speedLimiterEnabled ? "✓" : "    ") + qsTr("Turn On");  onTriggered: { App.enableSpeedLimiter(); _optionsMenu.dismiss() } }
                    CompactMenuItem { text: (!App.settings.speedLimiterEnabled ? "✓" : "    ") + qsTr("Turn Off"); onTriggered: { App.disableSpeedLimiter(); _optionsMenu.dismiss() } }
                    CompactSep {}
                    CompactMenuItem { text: qsTr("Settings…"); onTriggered: { settingsDialog.initialPage = root.settingsPageSpeedLimiter; settingsDialog.show(); _optionsMenu.dismiss() } }
                }
                Timer { id: _sl2CloseTimer; interval: 300; onTriggered: { if (!_speedLimiterMenu2.activeFocus) _speedLimiterMenu2.close() } }
            }
        }
        // The RSS menu is added/removed from the MenuBar via addMenu/removeMenu
        // rather than `visible:` because toggling `Menu.visible` while the menu
        // bar is in active-navigation mode (which it enters after the user
        // clicks an item in another menu) causes Qt to immediately pop the
        // newly-visible menu open. Adding it on a deferred tick avoids that.
        Menu {
            id: rssMenuBarMenu
            title: qsTr("RSS")
            delegate: CompactMenuItem
            implicitWidth: 260; padding: 0
            CompactMenuItem { text: qsTr("Open RSS Reader");      iconSrc: "icons/rss.svg";    onTriggered: root.showRssWindow() }
            CompactMenuItem { text: qsTr("Refresh All Feeds");    iconSrc: "icons/update.svg"; onTriggered: App.rssManager.refreshAll() }
            CompactMenuItem { text: qsTr("Mark All Items Read");  iconSrc: "icons/checkmark.svg"; onTriggered: App.rssManager.markAllRead() }

            // Track membership ourselves so we know whether to add or remove.
            property bool _inMenuBar: true
        }
        Connections {
            target: App.settings
            function onShowRssReaderChanged() {
                if (App.settings.showRssReader && !rssMenuBarMenu._inMenuBar) {
                    appMenuBar.addMenu(rssMenuBarMenu)
                    rssMenuBarMenu._inMenuBar = true
                } else if (!App.settings.showRssReader && rssMenuBarMenu._inMenuBar) {
                    appMenuBar.removeMenu(rssMenuBarMenu)
                    rssMenuBarMenu._inMenuBar = false
                }
            }
        }
        Component.onCompleted: {
            if (!App.settings.showRssReader && rssMenuBarMenu._inMenuBar) {
                appMenuBar.removeMenu(rssMenuBarMenu)
                rssMenuBarMenu._inMenuBar = false
            }
        }
        Menu {
            id: _helpMenu
            title: qsTr("Help")
            delegate: CompactMenuItem
            implicitWidth: 260; padding: 0
            CompactMenuItem { text: qsTr("Check for Updates"); iconSrc: "icons/satellite_antenna.svg"; onTriggered: App.checkForUpdates(true) }
            // CompactMenuItem { text: qsTr("Debug: Simulate Update Available"); onTriggered: App.simulateUpdateAvailable() }
            CompactSep {}
            CompactMenuItem { text: qsTr("About Stellar"); shortcutDisplay: "Ctrl+/"; iconSrc: "icons/information.svg"; onTriggered: root.showSettingsPage(root.settingsPageAbout) }
            CompactSep {}
            CompactMenuItem {
                id: _browserIntItem
                text: qsTr("Browser Integration") + "  ▶"
                onTriggered: _browserIntMenu.popup(_browserIntItem.width, 0)
                onHoveredChanged: {
                    if (hovered) { _browserIntMenu.popup(_browserIntItem.width, 0) }
                    else { _browserIntCloseTimer.restart() }
                }
                Menu {
                    id: _browserIntMenu
                    delegate: CompactMenuItem; implicitWidth: 260; topPadding: 0; bottomPadding: 0
                    onAboutToHide: _browserIntCloseTimer.stop()
                    CompactMenuItem { text: qsTr("Browser Extensions…"); onTriggered: { browserIntegrationDialog.show(); browserIntegrationDialog.raise(); browserIntegrationDialog.requestActivate(); _helpMenu.dismiss() } }
                    CompactSep {}
                    CompactMenuItem { text: qsTr("Browser Settings…"); onTriggered: { root.showSettingsPage(root.settingsPageBrowser); _helpMenu.dismiss() } }
                }
                Timer { id: _browserIntCloseTimer; interval: 300; onTriggered: { if (!_browserIntMenu.activeFocus) _browserIntMenu.close() } }
            }
        }
    }

    // ── Window-level drag proxy for category drag-and-drop ───────────────
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

    // ── Visual drag label purely cosmetic, follows the proxy ─────────────
    Rectangle {
        visible: dragProxy.visible
        z: 9998
        x: dragProxy.x + 10
        y: dragProxy.y + 10
        width: Math.min(dragLabelText.implicitWidth + 20, 220)
        height: 22
        radius: 3
        color: ColorPalette.selectionBg
        border.color: "#4488dd"
        border.width: 1

        Text {
            id: dragLabelText
            anchors { verticalCenter: parent.verticalCenter; left: parent.left; leftMargin: 8; right: parent.right; rightMargin: 8 }
            text: dragProxy.dragFilename
            color: ColorPalette.textHeader
            font.pixelSize: 11 * App.fontScale
            elide: Text.ElideMiddle
        }
    }

    // ── Root layout ──────────────────────────────────────────────────────
    DropArea {
        anchors.fill: parent
        z: 9997
        // Only accept external file drops (URLs/files from OS). Without this,
        // the unfiltered DropArea intercepts in-app drags too (text/downloadId
        // from the category drag proxy), breaking drop into sidebar categories
        // and queues.
        keys: ["text/uri-list"]
        onEntered: function(drag) {
            root.updateTorrentDropState(drag)
            if (root._torrentFileDragActive && drag.acceptProposedAction)
                drag.acceptProposedAction()
        }
        onPositionChanged: function(drag) {
            root.updateTorrentDropState(drag)
            if (root._torrentFileDragActive && drag.acceptProposedAction)
                drag.acceptProposedAction()
        }
        onExited: root._torrentFileDragActive = false
        onDropped: function(drop) {
            root.handleTorrentFileDrop(drop)
        }

        Rectangle {
            anchors.fill: parent
            visible: root._torrentFileDragActive
            color: "#102744"
            opacity: 0.72
            border.color: "#6aa0ff"
            border.width: 2

            Text {
                anchors.centerIn: parent
                text: qsTr("Drop .torrent file to open torrent metadata")
                color: "#f0f6ff"
                font.pixelSize: 18 * App.fontScale
                font.weight: Font.Medium
            }
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        Toolbar {
            id: toolbar
            Layout.fillWidth: true
            // Toolbar computes its own height from font metrics; mirror it here.
            Layout.preferredHeight: implicitHeight
            implicitHeight: height
            queueModel: App.queueModel
            downloadTable: downloadTable
            onAddClicked:             { addUrlDialog.show(); addUrlDialog.raise() }
            onResumeClicked:          downloadTable.resumeSelected()
            onStopClicked:            downloadTable.stopSelected()
            onStopAllClicked:         App.pauseAllDownloads()
            onDeleteClicked:          downloadTable.deleteSelected()
            onDeleteCompletedClicked: { deleteDoneConfirmDialog.show(); deleteDoneConfirmDialog.raise() }
            onOptionsClicked:         root.showSettingsPage(root.settingsPageGeneral)
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

        // ── Inline Find Bar ──────────────────────────────────────────────
        Rectangle {
            id: findBar
            Layout.fillWidth: true
            height: 36
            visible: root.findBarActive
            color: ColorPalette.headerStripBg
            border.width: 0

            // Top separator line
            Rectangle { anchors.top: parent.top; width: parent.width; height: 1; color: ColorPalette.border }

            // Escape to close
            Keys.onEscapePressed: root.closeFindBar()

            RowLayout {
                anchors { fill: parent; leftMargin: 8; rightMargin: 6; topMargin: 0; bottomMargin: 0 }
                spacing: 6

                Text {
                    text: qsTr("Find:")
                    color: ColorPalette.textSecond
                    font.pixelSize: 12 * App.fontScale
                    verticalAlignment: Text.AlignVCenter
                    Layout.alignment: Qt.AlignVCenter
                }

                TextField {
                    id: findBarField
                    Layout.fillWidth: true
                    implicitHeight: 24
                    font.pixelSize: 12 * App.fontScale
                    color: ColorPalette.textPrimary
                    background: Rectangle { color: ColorPalette.inputBg; border.color: findBarField.activeFocus ? ColorPalette.borderFocus : ColorPalette.border; radius: 3 }
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
                    font.pixelSize: 11 * App.fontScale
                    Layout.alignment: Qt.AlignVCenter
                    visible: downloadTable.filterText.length > 0
                }

                // Find button
                Rectangle {
                    implicitWidth: 46; implicitHeight: 24; radius: 3
                    color: findBtnMa.containsMouse ? "#2a5faa" : ColorPalette.selectionBg
                    border.color: ColorPalette.selectionBorder; border.width: 1
                    Layout.alignment: Qt.AlignVCenter
                    Text { anchors.centerIn: parent; text: qsTr("Find"); color: findBtnMa.containsMouse ? "#ffffff" : ColorPalette.selectionText; font.pixelSize: 12 * App.fontScale; font.bold: true }
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
                    color: findSettingsMa.containsMouse ? ColorPalette.buttonSecondaryHoverBg : ColorPalette.buttonSecondaryBg
                    border.color: ColorPalette.border; border.width: 1
                    Layout.alignment: Qt.AlignVCenter
                    Text { anchors.centerIn: parent; text: qsTr("Settings ▾"); color: ColorPalette.textPrimary; font.pixelSize: 11 * App.fontScale }
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
                        background: Rectangle { color: ColorPalette.panelBg; border.color: ColorPalette.border; border.width: 1; radius: 4 }
                        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

                        ColumnLayout {
                            width: parent.width
                            spacing: 2

                            Text { text: qsTr("Search in:"); color: ColorPalette.textSecond; font.pixelSize: 11 * App.fontScale; bottomPadding: 2 }

                            StyledCheckBox {
                                text: qsTr("File name or part of the name")
                                checked: downloadTable.filterName
                                topPadding: 0; bottomPadding: 0
                                onCheckedChanged: { downloadTable.filterName = checked; if (findBarField.text.length > 0) downloadTable.findFirstFiltered() }
                                contentItem: Text { text: parent.text; color: ColorPalette.textPrimary; font.pixelSize: 12 * App.fontScale; leftPadding: parent.indicator.width + 4; verticalAlignment: Text.AlignVCenter }
                            }
                            StyledCheckBox {
                                text: qsTr("Description")
                                checked: downloadTable.filterDesc
                                topPadding: 0; bottomPadding: 0
                                onCheckedChanged: { downloadTable.filterDesc = checked; if (findBarField.text.length > 0) downloadTable.findFirstFiltered() }
                                contentItem: Text { text: parent.text; color: ColorPalette.textPrimary; font.pixelSize: 12 * App.fontScale; leftPadding: parent.indicator.width + 4; verticalAlignment: Text.AlignVCenter }
                            }
                            StyledCheckBox {
                                text: qsTr("URL / referrer / parent web page")
                                checked: downloadTable.filterLinks
                                topPadding: 0; bottomPadding: 0
                                onCheckedChanged: { downloadTable.filterLinks = checked; if (findBarField.text.length > 0) downloadTable.findFirstFiltered() }
                                contentItem: Text { text: parent.text; color: ColorPalette.textPrimary; font.pixelSize: 12 * App.fontScale; leftPadding: parent.indicator.width + 4; verticalAlignment: Text.AlignVCenter }
                            }

                            Rectangle { width: parent.width; height: 1; color: ColorPalette.border; Layout.topMargin: 4; Layout.bottomMargin: 4 }

                            StyledCheckBox {
                                text: qsTr("Match case")
                                checked: downloadTable.filterMatchCase
                                topPadding: 0; bottomPadding: 0
                                onCheckedChanged: { downloadTable.filterMatchCase = checked; if (findBarField.text.length > 0) downloadTable.findFirstFiltered() }
                                contentItem: Text { text: parent.text; color: ColorPalette.textPrimary; font.pixelSize: 12 * App.fontScale; leftPadding: parent.indicator.width + 4; verticalAlignment: Text.AlignVCenter }
                            }
                            StyledCheckBox {
                                text: qsTr("Match whole string only")
                                checked: downloadTable.filterMatchWhole
                                topPadding: 0; bottomPadding: 0
                                onCheckedChanged: { downloadTable.filterMatchWhole = checked; if (findBarField.text.length > 0) downloadTable.findFirstFiltered() }
                                contentItem: Text { text: parent.text; color: ColorPalette.textPrimary; font.pixelSize: 12 * App.fontScale; leftPadding: parent.indicator.width + 4; verticalAlignment: Text.AlignVCenter }
                            }
                        }
                    }
                }

                // Close button
                Rectangle {
                    implicitWidth: 22; implicitHeight: 22; radius: 3
                    color: closeFindMa.containsMouse ? "#553333" : "transparent"
                    Layout.alignment: Qt.AlignVCenter
                    Text { anchors.centerIn: parent; text: "✕"; color: closeFindMa.containsMouse ? "#ffffff" : ColorPalette.textSecond; font.pixelSize: 16 * App.fontScale }
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

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            // Tracks whether the user is actively dragging the divider so we
            // can apply a highlight without flickering on mouse-move.
            property bool _dividerDragging: false

            // Clamp helper used by both drag updates and context-menu resets.
            function _clampSidebarWidth(w) {
                return Math.max(140, Math.min(w, parent.width - 300))
            }

            // Sidebar placed absolutely so it can appear on either side.
            Sidebar {
                id: sidebar
                height: parent.height
                x: App.settings.sidebarOnRight ? parent.width - width : 0
                width: App.settings.sidebarWidth
                onCategorySelected: (catId) => {
                    App.selectedCategory = catId
                    // Clear selection so toolbar enabled-states re-evaluate against
                    // ── the new (possibly empty) filtered view otherwise Resume/Delete/etc. ──
                    // stay lit when the newly shown category has no items.
                    downloadTable._setSelection({})
                    downloadTable._anchorId = ""
                }
                onQueueSelected: (queueId) => {
                    App.selectedQueue = queueId
                    downloadTable._setSelection({})
                    downloadTable._anchorId = ""
                }
                onGrabberProjectSelected: (projectId) => {
                    App.selectedCategory = projectId
                    downloadTable._setSelection({})
                    downloadTable._anchorId = ""
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
                    downloadTable._anchorId = ""
                }
            }

            // Drag handle between sidebar and table.
            Rectangle {
                id: sidebarDivider
                width: 4
                height: parent.height
                visible: sidebar.visible
                // On the right side of the sidebar when sidebar is on the left,
                // on the left side when sidebar is on the right.
                x: App.settings.sidebarOnRight
                   ? parent.width - App.settings.sidebarWidth - width
                   : App.settings.sidebarWidth
                color: dividerDragArea.containsMouse || parent._dividerDragging
                       ? "#4488dd" : ColorPalette.border

                Behavior on color { ColorAnimation { duration: 80 } }

                MouseArea {
                    id: dividerDragArea
                    anchors.fill: parent
                    // Extra hit area so the 4px handle is easy to grab.
                    anchors.leftMargin: -3
                    anchors.rightMargin: -3
                    hoverEnabled: true
                    cursorShape: Qt.SplitHCursor
                    acceptedButtons: Qt.LeftButton | Qt.RightButton

                    property int _startX: 0
                    property int _startWidth: 0

                    onPressed: (mouse) => {
                        if (mouse.button === Qt.RightButton) return
                        _startX     = mouse.x + sidebarDivider.x
                        _startWidth = App.settings.sidebarWidth
                        sidebarDivider.parent._dividerDragging = true
                    }
                    onReleased: (mouse) => {
                        if (mouse.button === Qt.RightButton) return
                        sidebarDivider.parent._dividerDragging = false
                    }
                    onPositionChanged: (mouse) => {
                        if (!pressed || pressedButtons & Qt.RightButton) return
                        var globalX  = mouse.x + sidebarDivider.x
                        var delta    = globalX - _startX
                        var newWidth = App.settings.sidebarOnRight
                                       ? _startWidth - delta
                                       : _startWidth + delta
                        App.settings.sidebarWidth = sidebarDivider.parent._clampSidebarWidth(newWidth)
                    }
                    onClicked: (mouse) => {
                        if (mouse.button !== Qt.RightButton) return
                        sidebarPositionMenu.popup()
                    }

                    Menu {
                        id: sidebarPositionMenu
                        implicitWidth: 260
                        topPadding: 0
                        bottomPadding: 0
                        delegate: CompactMenuItem {}

                        MenuItem {
                            text: App.settings.sidebarOnRight ? qsTr("Move sidebar to left") : qsTr("Move sidebar to right")
                            onTriggered: App.settings.sidebarOnRight = !App.settings.sidebarOnRight
                        }
                        MenuItem {
                            text: qsTr("Reset sidebar width")
                            onTriggered: App.settings.sidebarWidth = sidebarDivider.parent._clampSidebarWidth(188)
                        }
                    }
                }
            }

            DownloadTable {
                id: downloadTable
                height: parent.height
                x: sidebar.visible && !App.settings.sidebarOnRight ? App.settings.sidebarWidth + sidebarDivider.width : 0
                width: parent.width - (sidebar.visible ? App.settings.sidebarWidth + sidebarDivider.width : 0)
                categoryDragProxy: dragProxy
                onExportTorrentsRequested: (downloadIds) => {
                    root.pendingTorrentExportIds = downloadIds
                    if (downloadIds && downloadIds.length > 0)
                        exportTorrentFolderDialog.open()
                }
                onOpenProgressRequested: (item) => {
                    root.showDownloadProgressForItem(item)
                }
                onOpenChannelProgressRequested: (item) => {
                    if (!item) return
                    App.showYtdlpBatchForItem(item.id)
                    ytdlpBatchWindow.show()
                    ytdlpBatchWindow.raise()
                    ytdlpBatchWindow.requestActivate()
                }
                onOpenPropertiesRequested: (item) => {
                    if (!item)
                        return
                    // yt-dlp channel container: properties = the channel batch progress
                    // dialog, not the HTTP file-properties dialog (no single file).
                    if (item.isChannelContainer) {
                        App.showYtdlpBatchForItem(item.id)
                        ytdlpBatchWindow.show()
                        ytdlpBatchWindow.raise()
                        ytdlpBatchWindow.requestActivate()
                        return
                    }
                    // yt-dlp items (children + singles) use the download progress dialog
                    // regardless of state — the file-properties dialog is HTTP/torrent only.
                    if (item.isYtdlp) {
                        root.showDownloadProgressForItem(item)
                        return
                    }
                    if (!item.isTorrent && (item.status === "Downloading" || item.status === "Assembling")) {
                        root.showDownloadProgressForItem(item)
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
            visible: App.settings.showStatusBar
            activeCount:    App.activeDownloads
            completedCount: App.completedDownloads
            // _selectionVersion is the reactive trigger; Object.keys gives the live count.
            selectedCount: { downloadTable._selectionVersion; return Object.keys(downloadTable._selectedIds).length }
            tipsArray:      root.tipsArray
            currentTipIndex: root.currentTipIndex
            showTips:       App.settings.showTips
            motdText:       App.motd
            motdVisible:    App.motdVisible
            onNextTip: {
                if (root.tipsArray.length > 0) {
                    root.currentTipIndex = (root.currentTipIndex + 1) % root.tipsArray.length
                }
            }
            onCloseTips: {
                App.settings.showTips = false
            }
            onDismissMotd: {
                App.dismissMotd()
            }
            onStatisticsRequested: {
                statisticsDialog.show()
                statisticsDialog.raise()
                statisticsDialog.requestActivate()
            }
            onSpeedLimiterRequested: {
                settingsDialog.initialPage = root.settingsPageSpeedLimiter
                settingsDialog.show()
                settingsDialog.raise()
                settingsDialog.requestActivate()
            }
        }
    }
}
