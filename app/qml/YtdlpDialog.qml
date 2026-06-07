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

// YtdlpDialog - format picker shown when a yt-dlp-compatible URL is submitted.
Window {
    id: root

    // ?? Public API ????????????????????????????????????????????????????????????
    property string pendingUrl: ""
    property bool   uniqueFilename: false

    signal openSettingsRequested(int page)
    signal downloadRequested(string url, string formatId,
                             string containerFormat, string savePath, string category,
                             bool uniqueFilename, string videoTitle,
                             bool playlistMode, int maxItems,
                             var extraOptions)

    // ?? Window ????????????????????????????????????????????????????????????????
    width:        620
    // Height follows content; clamp so it never overflows the screen.
    height:       Math.min(rootCol.implicitHeight, Screen.height - 80)
    minimumWidth: 520
    title:       qsTr("Video Download")
    color:       ColorPalette.cardBg
    modality:    Qt.NonModal
    flags:       Qt.Dialog | Qt.WindowTitleHint | Qt.WindowCloseButtonHint

    Material.theme:      ColorPalette.materialTheme
    Material.background: ColorPalette.materialBg
    Material.accent:     "#4488dd"

    // ?? Private state ?????????????????????????????????????????????????????????
    property string _probeId:    ""
    property string _title:      ""
    property var    _formats:    []
    property bool   _probing:    false
    property string _probeError: ""
    property bool   _accepted:   false
    property bool   advancedExpanded: false

    // Channel/playlist detection is host-aware so single-item pages on sites
    // that use "/@" in their URL structure (TikTok, Odysee, Instagram) are not
    // misidentified as channels.
    //
    // TikTok: /@username/video/ID and /@username/photo/ID are single items.
    //         /@username alone is the channel/profile page.
    // YouTube/Odysee/Instagram/Rumble/Bitchute: /@ or /channel/ or /c/ or
    //         /user/ in path reliably indicates a channel or profile page.
    readonly property bool _isChannelUrl: {
        var u = (pendingUrl || "").trim()
        if (!u) return false

        // --------------- parse host and path from the URL string ---------------
        var schemeEnd = u.indexOf("://")
        var hostStart = schemeEnd >= 0 ? schemeEnd + 3 : 0
        var pathStart = u.indexOf("/", hostStart)
        if (pathStart < 0) {
            // No path at all, e.g. "https://example.com"
            pathStart = u.length
        }
        var host = u.substring(hostStart, pathStart).toLowerCase()
        if (host.startsWith("www."))
            host = host.substring(4)

        var queryPart = u.substring(pathStart).toLowerCase()

        // --------- generic playlist indicators (site-agnostic) ---------
        // "list=" is used by YouTube, SoundCloud, and many other sites to
        // identify a playlist.  It is never present in single-item URLs.
        if (queryPart.indexOf("list=") >= 0)
            return true

        // Extract the path (everything between the first slash and ? or #)
        var qs = queryPart.indexOf("?")
        var hs = queryPart.indexOf("#")
        var end = queryPart.length
        if (qs >= 0 && qs < end) end = qs
        if (hs >= 0 && hs < end) end = hs
        var path = queryPart.substring(0, end)

        // --------- host-specific channel patterns ---------

        // TikTok: /@username alone = channel.  /@username/video/ID and
        // /@username/photo/ID are single-item pages, not channels.
        if (host === "tiktok.com" || host.endsWith(".tiktok.com")) {
            var hasTkHandle = path.indexOf("/@") >= 0
            if (!hasTkHandle)
                return false
            var isTkSingle = path.indexOf("/video/") >= 0
                          || path.indexOf("/photo/") >= 0
            return !isTkSingle
        }

        // YouTube, Odysee, Instagram, Twitter/X, and most other sites: /@ in
        // the path reliably indicates a channel or profile page.  Individual
        // content pages on these sites use distinct path patterns
        // (/watch, /p/, /status/, /reel/, etc.) that do not contain /@.
        if (path.indexOf("/@") >= 0)
            return true

        // Other common channel/profile-indicating path segments.  These are
        // never present in single-video pages on any site in kYtdlpDomains.
        if (path.indexOf("/channel/") >= 0)
            return true
        if (path.indexOf("/c/") >= 0)
            return true
        if (path.indexOf("/user/") >= 0)
            return true

        return false
    }
    // YouTube-specific channel-root check: only true for raw channel landing
    // pages (e.g. youtube.com/@channel), not for sub-tabs (videos/shorts/live)
    // and not for playlist URLs.  This gates the Scope picker in the UI.
    readonly property bool _isYoutubeChannelRootUrl: {
        var u = pendingUrl.toLowerCase()
        var isYt = (u.indexOf("youtube.com/") >= 0 || u.indexOf("youtu.be/") >= 0)
        if (!isYt) return false
        if (u.indexOf("list=") >= 0) return false
        return u.indexOf("/@") >= 0 || u.indexOf("/channel/") >= 0
            || u.indexOf("/c/") >= 0 || u.indexOf("/user/") >= 0
    }

    function fileUrlFromPath(path) {
        var p = String(path || "").trim().replace(/\\/g, "/")
        if (p.length === 0 || p.indexOf("file://") === 0)
            return p
        return Qt.platform.os === "windows"
            ? ("file:///" + p)
            : (p.startsWith("/") ? ("file://" + p) : ("file:///" + p))
    }

    function pathFromFileUrl(url) {
        var p = String(url || "")
        if (Qt.platform.os === "windows")
            return p.replace(/^file:\/\/\//, "")
        return p.replace(/^file:\/\//, "")
    }
    readonly property bool _containerSupportsSubs: {
        var c = containerCombo.currentText
        return c === "mp4" || c === "mkv" || c === "webm"
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

    // ?? Lifecycle ?????????????????????????????????????????????????????????????
    onVisibleChanged: {
        if (visible) {
            _centerOnOwner()
            App.setWindowIcon(root, ":/qt/qml/com/stellar/app/app/qml/icons/wand.svg")
            App.setWindowDarkTitleBar(root, App.settings.darkMode)
            raise(); requestActivate()
            if (pendingUrl.length > 0) _startProbe()
        } else {
            _reset()
        }
    }
    onPendingUrlChanged: { if (visible && pendingUrl.length > 0 && !_accepted) _startProbe() }

    function _reset() {
        pendingUrl = ""; uniqueFilename = false
        _probeId = ""; _title = ""; _formats = []
        _probing = false; _probeError = ""; _accepted = false
        subsCheck.checked = false; autoSubsCheck.checked = false
        subLangsField.text = "en"; embedSubsCheck.checked = false
        embedThumbCheck.checked = false; embedMetaCheck.checked = false
        sponsorBlockCheck.checked = false
        dateAfterField.text = ""
        // Pre-select default cookie browser from settings; stays at 0 (None) if unset
        var _defBrowser = (App.settings.ytdlpDefaultCookieBrowser || "").toLowerCase()
        cookiesBrowserCombo.currentIndex = 0
        if (_defBrowser.length > 0 && _defBrowser !== "none") {
            for (var _bi = 1; _bi < cookiesBrowserCombo.model.length; ++_bi)
                if (cookiesBrowserCombo.model[_bi].toLowerCase() === _defBrowser) { cookiesBrowserCombo.currentIndex = _bi; break }
        }
        writeDescCheck.checked = false; writeThumbnailCheck.checked = false
        splitChaptersCheck.checked = false; sectionsField.text = ""
        playlistRandomCheck.checked = false; playlistReverseCheck.checked = false
        liveFromStartCheck.checked = false; useArchiveCheck.checked = false
        ignoreErrorsCheck.checked = false; waitForVideoCheck.checked = false
        waitForVideoField.text = "60"; concFragField.text = ""
        rateLimitField.text = ""
        advancedExpanded = false
    }

    function _startProbe() {
        if (_probeId.length > 0) App.cancelYtdlpInfo(_probeId)
        _probeId = ""; _title = ""; _formats = []; _probeError = ""
        _probing = true
        var browser = (cookiesBrowserCombo.currentIndex > 0) ? cookiesBrowserCombo.currentText.toLowerCase() : ""
        _probeId = App.beginYtdlpInfo(pendingUrl, browser)
    }

    function _channelScopedUrl(scope) {
        var raw = (pendingUrl || "").trim()
        if (!root._isYoutubeChannelRootUrl || scope === "all") return raw
        var cut = raw.search(/[?#]/); var suffix = ""; var base = raw
        if (cut >= 0) { base = raw.slice(0, cut); suffix = raw.slice(cut) }
        if (base.endsWith("/")) base = base.slice(0, -1)
        base = base.replace(/\/(videos|shorts|live|streams)$/i, "")
        var tab = scope === "shorts" ? "shorts" : (scope === "live" ? "streams" : "videos")
        return base + "/" + tab + suffix
    }

    function _formatSize(bytes) {
        if (!bytes || bytes <= 0) return ""
        if (bytes >= 1073741824) return (bytes / 1073741824).toFixed(1) + " GiB"
        if (bytes >= 1048576)    return (bytes / 1048576).toFixed(1)    + " MiB"
        if (bytes >= 1024)       return (bytes / 1024).toFixed(0)       + " KiB"
        return bytes + " B"
    }

    function _codecLabel(v) {
        if (!v || v === "none") return ""
        var s = v.toLowerCase()
        if (s.indexOf("av01") >= 0 || s.indexOf("av1") >= 0)  return "AV1"
        if (s.indexOf("vp09") >= 0 || s.indexOf("vp9") >= 0)  return "VP9"
        if (s.indexOf("vp08") >= 0 || s.indexOf("vp8") >= 0)  return "VP8"
        if (s.indexOf("avc")  >= 0 || s.indexOf("h264") >= 0) return "H.264"
        if (s.indexOf("hvc")  >= 0 || s.indexOf("hevc") >= 0 || s.indexOf("h265") >= 0) return "H.265"
        if (s.indexOf("theora") >= 0) return "Theora"
        var d = s.indexOf("."); return d > 0 ? v.substring(0, d).toUpperCase() : v.toUpperCase()
    }
    function _acodecLabel(a) {
        if (!a || a === "none") return ""
        var s = a.toLowerCase()
        if (s.indexOf("opus") >= 0)   return "Opus"
        if (s.indexOf("mp4a") >= 0 || s.indexOf("aac") >= 0) return "AAC"
        if (s.indexOf("mp3")  >= 0)   return "MP3"
        if (s.indexOf("vorbis") >= 0) return "Vorbis"
        if (s.indexOf("flac") >= 0)   return "FLAC"
        var d = s.indexOf("."); return d > 0 ? a.substring(0, d).toUpperCase() : a.toUpperCase()
    }

    // ?? Category helpers ??????????????????????????????????????????????????????
    function _categoryIds()    { var r=[]; for(var i=0;i<App.categoryModel.rowCount();i++) r.push(App.categoryModel.categoryData(i).id);    return r }
    function _categoryLabels() { var r=[]; for(var i=0;i<App.categoryModel.rowCount();i++) r.push(App.categoryModel.categoryData(i).label); return r }
    property var categoryIds:    _categoryIds()
    property var categoryLabels: _categoryLabels()
    Connections { target: App.categoryModel; function onCategoriesChanged() { root.categoryIds=root._categoryIds(); root.categoryLabels=root._categoryLabels() } }

    function _catIndexForVideo() {
        for (var i=0; i<categoryIds.length; i++) { var l=(categoryLabels[i]||"").toLowerCase(); if(l==="video"||l==="videos") return i }
        return 0
    }
    function _savePathForCatIndex(idx) { return App.categoryModel.savePathForCategory(categoryIds[idx]||"all") }
    function _updateSavePath(idx) {
        var d = _savePathForCatIndex(idx); if(!d||d.length===0) d=App.settings.defaultSavePath
        d=d.replace(/\//g,"\\"); if(d.length>0&&!d.endsWith("\\")) d+="\\"; savePathField.text=d
    }

    // ?? yt-dlp response listener ??????????????????????????????????????????????
    Connections {
        target: App
        function onYtdlpInfoReady(probeId, url, title, formats) {
            if (probeId !== root._probeId) return
            root._probing = false
            root._title = title
            root._probeError = ""
            // When probe returns no format info (e.g. channel URLs where yt-dlp
            // returns flat entries without formats), provide fallback entries so
            // the user can still pick container and download.  Empty id means
            // YtdlpTransfer omits -f and lets yt-dlp use its default selector.
            root._formats = (formats && formats.length > 0) ? formats : [
                { id: "",                    label: qsTr("Best quality"), ext: "mp4", width: 0, height: 480, fps: 0, tbr: 0, vcodec: "", acodec: "", filesize: 0 },
                { id: "bestaudio/best",       label: qsTr("Audio only"),   ext: "mp3", width: 0, height: 0,   fps: 0, tbr: 0, vcodec: "", acodec: "", filesize: 0 }
            ]
            var idx = 0
            for (var i = 0; i < root._formats.length; ++i) {
                var fid = (root._formats[i] && root._formats[i].id) ? String(root._formats[i].id) : ""
                if (fid.length > 0 && fid !== "best") {
                    idx = i
                    break
                }
            }
            formatList.currentIndex = idx
            var ci=root._catIndexForVideo(); catCombo.currentIndex=ci; root._updateSavePath(ci)
        }
        function onYtdlpInfoFailed(probeId, url, reason) {
            if (probeId !== root._probeId) return
            root._probing=false; root._probeError=reason
        }
    }

    // Build the extraOptions map sent to C++.
    function _buildExtraOptions() {
        var o = {}
        if (subsCheck.checked) {
            o["writeSubs"] = true
            if (autoSubsCheck.checked) o["writeAutoSubs"] = true
            var l = subLangsField.text.trim(); if (l.length>0&&l!=="en") o["subLangs"]=l
            if (embedSubsCheck.checked && root._containerSupportsSubs) o["embedSubs"]=true
        }
        if (embedThumbCheck.checked)   o["embedThumbnail"]    = true
        if (embedMetaCheck.checked)    o["embedMetadata"]     = true
        if (sponsorBlockCheck.checked) o["sponsorBlock"]      = true
        var da = dateAfterField.text.replace(/-/g,"").trim(); if(da.length===8) o["dateAfter"]=da
        var cb = cookiesBrowserCombo.currentIndex>0 ? cookiesBrowserCombo.currentText.toLowerCase() : ""
        if (cb.length>0) o["cookiesFromBrowser"]=cb
        if (writeDescCheck.checked)      o["writeDescription"]  = true
        if (writeThumbnailCheck.checked) o["writeThumbnailFile"] = true
        if (splitChaptersCheck.checked)  o["splitChapters"]     = true
        var sec = sectionsField.text.trim(); if(sec.length>0) o["downloadSections"]=sec
        if (playlistRandomCheck.checked)  o["playlistRandom"]        = true
        if (playlistReverseCheck.checked) o["playlistReverse"]       = true
        if (liveFromStartCheck.checked)   o["liveFromStart"]         = true
        if (useArchiveCheck.checked)      o["useArchive"]            = true
        if (ignoreErrorsCheck.checked)    o["ignoreErrors"]          = true
        if (waitForVideoCheck.checked) {
            var wv = parseInt(waitForVideoField.text.trim(), 10)
            if (!isNaN(wv) && wv > 0) o["waitForVideoSecs"] = wv
        }
        var cf = parseInt(concFragField.text.trim(), 10); if(!isNaN(cf)&&cf>1) o["concurrentFragments"]=cf
        var rl = parseInt(rateLimitField.text.trim(), 10); if(!isNaN(rl)&&rl>0) o["rateLimitKBps"]=rl
        return o
    }

    // ?? Reusable inline checkbox component ????????????????????????????????????
    // Using a plain component avoids Material CheckBox padding/layout quirks.
    component InlineCheck: Item {
        id: _chk
        property bool   checked:  false
        property string label:    ""
        property string tip:      ""
        property bool   enabled_: true
        property color  accentColor: "#4488dd"
        property color  accentBg:    ColorPalette.selectionBg

        implicitWidth:  _chkRow.implicitWidth
        implicitHeight: _chkRow.implicitHeight
        opacity: enabled_ ? 1.0 : 0.38

        RowLayout {
            id: _chkRow
            anchors.verticalCenter: parent.verticalCenter
            spacing: 6

            Rectangle {
                width: 13; height: 13; radius: 2
                color:        _chk.checked ? _chk.accentBg : ColorPalette.inputBg
                border.color: _chk.checked ? _chk.accentColor : "#555555"
                Layout.alignment: Qt.AlignVCenter
                Text {
                    anchors.centerIn: parent
                    text: "✓"; font.pixelSize: 9 * App.fontScale
                    color: _chk.accentColor
                    visible: _chk.checked
                }
            }
            Text {
                text: _chk.label
                color: _chk.checked ? Qt.lighter(_chk.accentColor, 1.15) : ColorPalette.textSecond
                font.pixelSize: 11 * App.fontScale
                Layout.alignment: Qt.AlignVCenter
            }
        }

        MouseArea {
            id: chkTipMa
            anchors.fill: parent
            enabled: _chk.enabled_
            cursorShape: Qt.PointingHandCursor
            onClicked: _chk.checked = !_chk.checked
            hoverEnabled: _chk.tip.length > 0
            ThemedToolTip {
                visible: chkTipMa.containsMouse && _chk.tip.length > 0
                text: _chk.tip
                delay: 600
            }
        }
    }

    FolderDialog {
        id: saveFolderDialog
        currentFolder: savePathField.text.trim().length > 0
                       ? fileUrlFromPath(savePathField.text.trim())
                       : fileUrlFromPath(App.settings.defaultSavePath)
        onAccepted: {
            var p = pathFromFileUrl(folder)
            p = p.replace(/\//g,"\\")
            if (p.length > 0 && !p.endsWith("\\")) p += "\\"
            savePathField.text = p
        }
    }

    // ?? Root layout ???????????????????????????????????????????????????????????
    // Content-driven: window height = implicitHeight of this column (clamped above).
    ColumnLayout {
        id: rootCol
        anchors { left: parent.left; right: parent.right; top: parent.top }
        spacing: 0

        // ?? Header ????????????????????????????????????????????????????????????
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 52
            color: ColorPalette.headerStripBg

            // Left accent stripe
            Rectangle {
                anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
                width: 3; color: "#4488dd"
            }

            Item {
                anchors { fill: parent; leftMargin: 19; rightMargin: 16; topMargin: 8; bottomMargin: 8 }

                Image {
                    id: headerIcon
                    anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                    source: "icons/wand.svg"
                    sourceSize: Qt.size(22, 22)
                    width: 22; height: 22
                    fillMode: Image.PreserveAspectFit
                    smooth: true
                    opacity: 0.9
                }

                Column {
                    anchors {
                        left: headerIcon.right; leftMargin: 10
                        right: parent.right
                        verticalCenter: parent.verticalCenter
                    }
                    spacing: 2

                    Text {
                        width: parent.width
                        text: root._title.length > 0 ? root._title
                              : (root._probing ? qsTr("Fetching video info.")
                              : (root._probeError.length > 0 ? qsTr("Could not fetch video info")
                              : qsTr("Video Download")))
                        color: ColorPalette.textHeader; font.pixelSize: 13 * App.fontScale; font.weight: Font.Medium
                        elide: Text.ElideRight
                    }
                    Text {
                        width: parent.width
                        text: root.pendingUrl
                        color: ColorPalette.textMuted; font.pixelSize: 11 * App.fontScale
                        elide: Text.ElideMiddle
                    }
                }
            }
        }

        // separator under header
        Rectangle { Layout.fillWidth: true; height: 1; color: ColorPalette.dividerBg }

        // ?? Body ?????????????????????????????????????????????????????????????
        Item {
            id: bodyItem
            Layout.fillWidth: true
            // When probing/error, give a fixed height for the centered states.
            // When showing content, implicitHeight tracks the inner ColumnLayout.
            implicitHeight: root._probing || root._probeError.length > 0
                            ? 160
                            : bodyContent.implicitHeight

            // Loading
            ColumnLayout {
                anchors.centerIn: parent
                spacing: 14
                visible: root._probing
                BusyIndicator { Layout.alignment: Qt.AlignHCenter; running: root._probing; width: 44; height: 44 }
                Text { Layout.alignment: Qt.AlignHCenter; text: qsTr("Fetching available formats."); color: ColorPalette.textSecond; font.pixelSize: 13 * App.fontScale }
            }

            // Error
            ColumnLayout {
                anchors.centerIn: parent
                width: Math.min(parent.width - 48, 480)
                spacing: 12
                visible: !root._probing && root._probeError.length > 0

                Text { Layout.alignment: Qt.AlignHCenter; text: "\u26A0"; font.pixelSize: 34 * App.fontScale; color: "#cc8800" }
                Text { Layout.alignment: Qt.AlignHCenter; text: qsTr("Could not fetch video information"); color: ColorPalette.textPrimary; font.pixelSize: 13 * App.fontScale; font.weight: Font.Medium }

                Text {
                    Layout.fillWidth: true
                    text: root._probeError.replace(/(\r?\n)+null\s*$/g, "").trim()
                    color: ColorPalette.textSecond; font.pixelSize: 11 * App.fontScale; wrapMode: Text.Wrap; horizontalAlignment: Text.AlignHCenter
                }

                // n-challenge specific help box - shown when yt-dlp reports JS runtime missing
                Rectangle {
                    Layout.fillWidth: true
                    height: nChallengeText.implicitHeight + 16
                    radius: 4
                    color: "#1a1a10"
                    border.color: "#3a3010"
                    visible: root._probeError.indexOf("n challenge") >= 0 ||
                             root._probeError.indexOf("EJS") >= 0 ||
                             root._probeError.indexOf("js-runtimes") >= 0 ||
                             root._probeError.indexOf("JavaScript runtime") >= 0

                    ColumnLayout {
                        id: nChallengeText
                        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 8 }
                        spacing: 4

                        Text {
                            Layout.fillWidth: true
                            text: qsTr("YouTube n-challenge solving failed")
                            color: "#ddaa44"; font.pixelSize: 12 * App.fontScale; font.bold: true
                            wrapMode: Text.Wrap
                        }
                        Text {
                            Layout.fillWidth: true
                            text: qsTr("yt-dlp requires a JavaScript runtime (Deno, Node.js, Bun, or QuickJS) to bypass YouTube's URL throttling challenge. Install one and place it next to yt-dlp.exe or in your system PATH.") + "\n\n" +
                                  (!App.ytdlpManager.jsRuntimeAvailable
                                   ? qsTr("No runtime detected. Install Deno (recommended) from deno.com, then re-check in Settings ? Video Downloader.")
                                   : qsTr("Runtime detected: %1 (%2)").arg(App.ytdlpManager.jsRuntimeName).arg(App.ytdlpManager.jsRuntimePath))
                            color: "#aa9966"; font.pixelSize: 11 * App.fontScale
                            wrapMode: Text.Wrap
                        }
                        RowLayout {
                            spacing: 6
                            DlgButton {
                                text: qsTr("Get Deno")
                                visible: !App.ytdlpManager.jsRuntimeAvailable
                                onClicked: App.openExternalUrl("https://deno.com")
                            }
                            DlgButton {
                                text: qsTr("Open Settings")
                                visible: !App.ytdlpManager.jsRuntimeAvailable
                                onClicked: root.openSettingsRequested(7)  // Media tab
                            }
                        }
                    }
                }

                // Cookies selector - lets the user authenticate and retry without reopening settings
                Rectangle {
                    Layout.alignment: Qt.AlignHCenter
                    implicitWidth: errCookiesRow.implicitWidth + 20
                    implicitHeight: errCookiesRow.implicitHeight + 14
                    color: "#1a1a22"; border.color: "#2e2e44"; radius: 4

                    RowLayout {
                        id: errCookiesRow
                        anchors.centerIn: parent
                        spacing: 8

                        Text { text: qsTr("Cookies from browser:"); color: ColorPalette.textSecond; font.pixelSize: 11 * App.fontScale }

                        ComboBox {
                            id: errCookieCombo
                            implicitWidth: 110; implicitHeight: 24; font.pixelSize: 11 * App.fontScale
                            model: ["None","Chrome","Firefox","Edge","Brave","Opera","Vivaldi","Safari"]
                            // Sync with the advanced-tab cookies combo so they share state
                            currentIndex: cookiesBrowserCombo.currentIndex
                            onCurrentIndexChanged: cookiesBrowserCombo.currentIndex = currentIndex
                            contentItem: Text { leftPadding: 7; text: errCookieCombo.displayText; color: ColorPalette.textPrimary; font: errCookieCombo.font; verticalAlignment: Text.AlignVCenter }
                            background: Rectangle { color: ColorPalette.inputBg; border.color: errCookieCombo.activeFocus ? "#4488dd" : ColorPalette.border; radius: 3 }
                            delegate: ItemDelegate {
                                id: _ecDel; width: errCookieCombo.width; height: 24
                                contentItem: Text { text: modelData; color: ColorPalette.textPrimary; font.pixelSize: 11 * App.fontScale; verticalAlignment: Text.AlignVCenter; leftPadding: 7 }
                                background: Rectangle { color: _ecDel.hovered ? "#2a3a5a" : ColorPalette.inputBg }
                            }
                            popup: Popup {
                                y: errCookieCombo.height + 2; width: errCookieCombo.width
                                implicitHeight: contentItem.implicitHeight + 4; padding: 2
                                background: Rectangle { color: ColorPalette.inputBg; border.color: ColorPalette.border; radius: 3 }
                                contentItem: ListView { implicitHeight: contentHeight; clip: true; model: errCookieCombo.delegateModel }
                            }
                        }
                    }
                }

                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: qsTr("Select a browser to pass its cookies to yt-dlp, then retry.")
                    color: "#556677"; font.pixelSize: 10 * App.fontScale
                    visible: errCookieCombo.currentIndex === 0
                }

                DlgButton { Layout.alignment: Qt.AlignHCenter; text: qsTr("Retry"); onClicked: root._startProbe() }
            }

            // Format picker + options
            ColumnLayout {
                id: bodyContent
                anchors { left: parent.left; right: parent.right; top: parent.top; topMargin: 10; leftMargin: 16; rightMargin: 16 }
                spacing: 6
                visible: !root._probing && root._probeError.length === 0 && root._formats.length > 0

                // ?? Quality dropdown ??????????????????????????????????????????
                RowLayout {
                    Layout.fillWidth: true; spacing: 8
                    Text { text: qsTr("Quality:"); color: ColorPalette.textMuted; font.pixelSize: 11 * App.fontScale; Layout.preferredWidth: 58 }

                    Item {
                        id: fmtDropWrapper
                        Layout.fillWidth: true
                        implicitHeight: 30

                        Rectangle {
                            id: fmtTrigger
                            anchors.fill: parent; radius: 3
                            color: fmtDropPopup.opened ? ColorPalette.selectionBg
                                   : (fmtHover.containsMouse ? ColorPalette.hoverBg : ColorPalette.inputBg)
                            border.color: fmtDropPopup.opened ? "#4488dd"
                                          : (fmtHover.containsMouse ? ColorPalette.borderFocus : ColorPalette.border)

                            RowLayout {
                                anchors { fill: parent; leftMargin: 9; rightMargin: 8 }
                                spacing: 6
                                Text {
                                    id: fmtSelLabel
                                    readonly property var _fmt: root._formats[formatList.currentIndex] || null
                                    text: _fmt ? (_fmt.label || "") : ""
                                    font.pixelSize: 12 * App.fontScale; font.weight: Font.Medium; color: ColorPalette.textPrimary
                                    Layout.minimumWidth: 70
                                }
                                Rectangle {
                                    readonly property string c: fmtSelLabel._fmt ? root._codecLabel(fmtSelLabel._fmt.vcodec || "") : ""
                                    visible: c.length > 0 && fmtSelLabel._fmt && fmtSelLabel._fmt.id !== "best" && fmtSelLabel._fmt.id !== "bestvideo+bestaudio/best"
                                    width: _sct.implicitWidth + 10; height: 15; radius: 3
                                    color: ColorPalette.panelBg
                                    border.color: c==="AV1"?"#2a5040":c==="VP9"?"#3a2a50":c==="H.264"?"#2a4060":c==="H.265"?"#502a2a":ColorPalette.border
                                    Text { id: _sct; anchors.centerIn: parent; text: parent.c; font.pixelSize: 9 * App.fontScale
                                        color: parent.c==="AV1"?(ColorPalette.dark?"#5abba0":"#1f7a5e"):parent.c==="VP9"?(ColorPalette.dark?"#9a70cc":"#6a3aa0"):parent.c==="H.264"?(ColorPalette.dark?"#6a9acc":"#2a5e9a"):parent.c==="H.265"?(ColorPalette.dark?"#cc7a7a":"#a83a3a"):ColorPalette.textSecond }
                                }
                                Rectangle {
                                    readonly property string a: fmtSelLabel._fmt ? root._acodecLabel(fmtSelLabel._fmt.acodec || "") : ""
                                    visible: a.length > 0 && fmtSelLabel._fmt && (fmtSelLabel._fmt.height === 0 || !fmtSelLabel._fmt.vcodec || fmtSelLabel._fmt.vcodec === "none") && fmtSelLabel._fmt.id !== "best"
                                    width: _sat.implicitWidth + 10; height: 15; radius: 3
                                    color: ColorPalette.panelBg; border.color: "#2a4040"
                                    Text { id: _sat; anchors.centerIn: parent; text: parent.a; font.pixelSize: 9 * App.fontScale; color: "#5a9aaa" }
                                }
                                Rectangle {
                                    readonly property int f: fmtSelLabel._fmt ? (fmtSelLabel._fmt.fps || 0) : 0
                                    visible: f > 0 && f !== 30 && fmtSelLabel._fmt && (fmtSelLabel._fmt.height || 0) > 0
                                    width: _sft.implicitWidth + 10; height: 15; radius: 3
                                    color: ColorPalette.panelBg; border.color: "#2a2a50"
                                    Text { id: _sft; anchors.centerIn: parent; text: parent.f + " fps"; font.pixelSize: 9 * App.fontScale; color: "#8888cc" }
                                }
                                Item { Layout.fillWidth: true }
                                Text {
                                    readonly property bool hasSize: fmtSelLabel._fmt && (fmtSelLabel._fmt.filesize || 0) > 0
                                    text: hasSize ? root._formatSize(fmtSelLabel._fmt.filesize) : ""
                                    color: "#6a8aaa"; font.pixelSize: 11 * App.fontScale; visible: hasSize
                                }
                                Text { text: fmtDropPopup.opened ? "▾" : "▸"; color: "#4a5a7a"; font.pixelSize: 8 * App.fontScale; Layout.alignment: Qt.AlignVCenter }
                            }

                            HoverHandler { id: fmtHover }
                            MouseArea {
                                anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                onClicked: fmtDropPopup.opened ? fmtDropPopup.close() : fmtDropPopup.open()
                            }
                        }

                        Popup {
                            id: fmtDropPopup
                            y: fmtTrigger.height + 2; x: 0
                            width: fmtDropWrapper.width
                            implicitHeight: Math.min(fmtPopupList.contentHeight + 4, 220)
                            padding: 2; z: 100
                            closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
                            background: Rectangle { color: ColorPalette.inputBg; border.color: "#4488dd"; radius: 3 }

                            ListView {
                                id: fmtPopupList
                                anchors { fill: parent; margins: 1 }
                                model: root._formats; currentIndex: formatList.currentIndex
                                clip: true; boundsBehavior: Flickable.StopAtBounds
                                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                                delegate: Rectangle {
                                    id: pfd
                                    width: fmtPopupList.width; height: 28
                                    readonly property bool sel: fmtPopupList.currentIndex === index
                                    readonly property bool hov: pfMouse.containsMouse
                                    color: sel ? ColorPalette.selectionBg : (hov ? ColorPalette.hoverBg : "transparent")
                                    Rectangle { width: 3; height: parent.height; color: "#4488dd"; visible: pfd.sel }

                                    RowLayout {
                                        anchors { fill: parent; leftMargin: 10; rightMargin: 8 }
                                        spacing: 6
                                        Text {
                                            text: modelData.label || ""; font.pixelSize: 12 * App.fontScale
                                            color: pfd.sel ? ColorPalette.selectionText : ColorPalette.textPrimary
                                            font.weight: pfd.sel ? Font.Medium : Font.Normal
                                            Layout.minimumWidth: 70
                                        }
                                        Rectangle {
                                            property string c: root._codecLabel(modelData.vcodec || "")
                                            visible: c.length > 0 && modelData.id !== "best" && modelData.id !== "bestvideo+bestaudio/best"
                                            width: _pct.implicitWidth + 10; height: 15; radius: 3
                                            color: ColorPalette.panelBg
                                            border.color: c==="AV1"?"#2a5040":c==="VP9"?"#3a2a50":c==="H.264"?"#2a4060":c==="H.265"?"#502a2a":ColorPalette.border
                                            Text { id: _pct; anchors.centerIn: parent; text: parent.c; font.pixelSize: 9 * App.fontScale
                                                color: parent.c==="AV1"?(ColorPalette.dark?"#5abba0":"#1f7a5e"):parent.c==="VP9"?(ColorPalette.dark?"#9a70cc":"#6a3aa0"):parent.c==="H.264"?(ColorPalette.dark?"#6a9acc":"#2a5e9a"):parent.c==="H.265"?(ColorPalette.dark?"#cc7a7a":"#a83a3a"):ColorPalette.textSecond }
                                        }
                                        Rectangle {
                                            property string a: root._acodecLabel(modelData.acodec || "")
                                            visible: a.length > 0 && (modelData.height === 0 || !modelData.vcodec || modelData.vcodec === "none") && modelData.id !== "best"
                                            width: _pat.implicitWidth + 10; height: 15; radius: 3
                                            color: ColorPalette.panelBg; border.color: "#2a4040"
                                            Text { id: _pat; anchors.centerIn: parent; text: parent.a; font.pixelSize: 9 * App.fontScale; color: "#5a9aaa" }
                                        }
                                        Rectangle {
                                            property int f: modelData.fps || 0
                                            visible: f > 0 && f !== 30 && (modelData.height || 0) > 0
                                            width: _pft.implicitWidth + 10; height: 15; radius: 3
                                            color: ColorPalette.panelBg; border.color: "#2a2a50"
                                            Text { id: _pft; anchors.centerIn: parent; text: parent.f + " fps"; font.pixelSize: 9 * App.fontScale; color: "#8888cc" }
                                        }
                                        Item { Layout.fillWidth: true }
                                        Text {
                                            readonly property bool hasSize: (modelData.filesize || 0) > 0
                                            readonly property bool isSplit: (modelData.height || 0) >= 480 && modelData.id !== "best" && modelData.id !== "bv*+ba/b"
                                            text: hasSize ? root._formatSize(modelData.filesize) : ""
                                            color: pfd.sel ? "#8aaddd" : "#6a8aaa"; font.pixelSize: 11 * App.fontScale; visible: hasSize
                                            HoverHandler { id: _pszHover }
                                            ThemedToolTip {
                                                visible: !parent.hasSize && parent.isSplit && _pszHover.hovered
                                                delay: 500
                                                text: qsTr("Size unavailable - this quality uses separate video\nand audio streams merged by ffmpeg after download.")
                                            }
                                        }
                                    }
                                    MouseArea { id: pfMouse; anchors.fill: parent; hoverEnabled: true
                                        onClicked: { formatList.currentIndex = index; fmtDropPopup.close() }
                                    }
                                }
                            }
                        }
                    }
                }

                // Hidden ListView keeps formatList.currentIndex as source of truth
                ListView {
                    id: formatList
                    visible: false; width: 0; height: 0
                    model: root._formats; currentIndex: 0
                }

            // ?? Options scroll ????????????????????????????????????????????????
            ScrollView {
                id: optScroll
                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(optCol.implicitHeight + 2, 320)
                Layout.maximumHeight: 320
                clip: true
                ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
                ScrollBar.vertical.policy: ScrollBar.AsNeeded

            ColumnLayout {
                id: optCol
                width: optScroll.availableWidth
                spacing: 5

                // ?? Channel / playlist ?????????????????????????????????????????
                Rectangle {
                    Layout.fillWidth: true
                    visible: root._isChannelUrl
                    implicitHeight: chRow.implicitHeight + 18
                    radius: 3; color: ColorPalette.panelBg; border.color: ColorPalette.border

                    ColumnLayout {
                        id: chRow
                        anchors { fill: parent; margins: 9 }
                        spacing: 6

                        RowLayout {
                            Layout.fillWidth: true; spacing: 8
                            Text { text: qsTr("Channel / Playlist"); color: ColorPalette.textSecond; font.pixelSize: 11 * App.fontScale; font.weight: Font.Medium }
                            Item { Layout.fillWidth: true }

                            RowLayout {
                                spacing: 4
                                Repeater {
                                    model: [{id:"allV",t:qsTr("All videos")},{id:"latN",t:qsTr("Latest")}]
                                    StyledRadioButton {
                                        id: _rb
                                        required property var modelData
                                        ButtonGroup.group: allVideosGroup
                                        checked: modelData.id === "allV"
                                        text: modelData.t; font.pixelSize: 11 * App.fontScale
                                        topPadding: 0; bottomPadding: 0
                                        padding: 0; leftPadding: indicator.width + 4
                                        Layout.alignment: Qt.AlignVCenter
                                        indicator: Rectangle {
                                            implicitWidth: 13; implicitHeight: 13; radius: 7
                                            color: _rb.checked ? ColorPalette.selectionBg : ColorPalette.inputBg
                                            border.color: _rb.checked ? "#4488dd" : "#555555"
                                            Rectangle { width: 5; height: 5; radius: 3; anchors.centerIn: parent; color: "#4488dd"; visible: _rb.checked }
                                        }
                                        contentItem: Text {
                                            leftPadding: 4; text: _rb.text; color: ColorPalette.textPrimary
                                            font: _rb.font; verticalAlignment: Text.AlignVCenter
                                        }
                                    }
                                }

                                Rectangle {
                                    id: latestNBox
                                    width: 44; height: 20; radius: 2; color: ColorPalette.inputBg
                                    Layout.alignment: Qt.AlignVCenter
                                    border.color: latestNField.activeFocus ? "#4488dd" : ColorPalette.border
                                    property bool latestMode: !allVideosGroup.checkedButton || allVideosGroup.checkedButton.text !== qsTr("All videos")
                                    opacity: latestMode ? 1.0 : 0.38
                                    TextInput {
                                        id: latestNField
                                        anchors { fill: parent; leftMargin: 5; rightMargin: 5 }
                                        text: "10"; color: ColorPalette.textPrimary; font.pixelSize: 11 * App.fontScale
                                        verticalAlignment: Text.AlignVCenter
                                        inputMethodHints: Qt.ImhDigitsOnly
                                        validator: IntValidator { bottom: 1; top: 9999 }
                                        enabled: latestNBox.latestMode
                                        selectByMouse: true
                                        onActiveFocusChanged: if (activeFocus) selectAll()
                                    }
                                }
                                Text { text: qsTr("videos"); color: ColorPalette.textMuted; font.pixelSize: 11 * App.fontScale; Layout.alignment: Qt.AlignVCenter }
                            }
                        }

                        Text {
                            Layout.fillWidth: true
                            text: root._isYoutubeChannelRootUrl
                                  ? qsTr("YouTube channel URLs include all uploads by default. Use Scope to target one tab.")
                                  : qsTr("Videos will be saved in a subfolder named after the channel.")
                            color: ColorPalette.textSecond; font.pixelSize: 10 * App.fontScale; wrapMode: Text.WordWrap
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            visible: root._isYoutubeChannelRootUrl
                            radius: 3; color: ColorPalette.cardBg; border.color: "#333333"
                            implicitHeight: scopeRow.implicitHeight + 12

                            RowLayout {
                                id: scopeRow
                                anchors { fill: parent; margins: 6 }
                                spacing: 6
                                Text { text: qsTr("Scope:"); color: ColorPalette.textSecond; font.pixelSize: 11 * App.fontScale; font.weight: Font.Medium }
                                ButtonGroup { id: scopeGroup }
                                Repeater {
                                    model: [{id:"scopeAll",t:qsTr("All uploads"),chk:true},{id:"scopeVid",t:qsTr("Videos")},{id:"scopeSho",t:qsTr("Shorts")},{id:"scopeLiv",t:qsTr("Live")}]
                                    StyledRadioButton {
                                        required property var modelData
                                        id: scopeRb
                                        objectName: modelData.id
                                        checked: modelData.chk || false
                                        text: modelData.t
                                        ButtonGroup.group: scopeGroup
                                        topPadding: 0; bottomPadding: 0
                                        padding: 0; leftPadding: indicator.width + 4
                                        Layout.alignment: Qt.AlignVCenter
                                        font.pixelSize: 11 * App.fontScale
                                        indicator: Rectangle {
                                            implicitWidth: 13; implicitHeight: 13; radius: 7
                                            color: scopeRb.checked ? ColorPalette.selectionBg : ColorPalette.inputBg
                                            border.color: scopeRb.checked ? "#4488dd" : "#555555"
                                            Rectangle { width: 5; height: 5; radius: 3; anchors.centerIn: parent; color: "#4488dd"; visible: scopeRb.checked }
                                        }
                                        contentItem: Text {
                                            leftPadding: 4; text: scopeRb.text; color: ColorPalette.textPrimary
                                            font: scopeRb.font; verticalAlignment: Text.AlignVCenter
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // ?? Subtitles ??????????????????????????????????????????????????
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: subsInner.implicitHeight + 12
                    radius: 3
                    color: ColorPalette.panelBg
                    border.color: ColorPalette.border

                    ColumnLayout {
                        id: subsInner
                        anchors { fill: parent; margins: 6 }
                        spacing: 5

                        RowLayout {
                            Layout.fillWidth: true; spacing: 10
                            InlineCheck {
                                id: subsCheck
                                label: qsTr("Subtitles")
                                tip: qsTr("Download subtitle files alongside the video")
                            }
                            Item { Layout.fillWidth: true }
                            RowLayout {
                                visible: subsCheck.checked; spacing: 5
                                Text { text: qsTr("Language:"); color: ColorPalette.textSecond; font.pixelSize: 11 * App.fontScale; Layout.alignment: Qt.AlignVCenter }
                                Rectangle {
                                    width: 68; height: 20; radius: 2; color: ColorPalette.inputBg
                                    border.color: subLangsField.activeFocus ? "#4488dd" : ColorPalette.border
                                    Layout.alignment: Qt.AlignVCenter
                                    TextInput {
                                        id: subLangsField
                                        anchors { fill: parent; leftMargin: 5; rightMargin: 5 }
                                        text: "en"; color: ColorPalette.textPrimary; font.pixelSize: 11 * App.fontScale
                                        verticalAlignment: Text.AlignVCenter; selectByMouse: true
                                        ThemedToolTip {
                                            visible: subLangsField.activeFocus
                                            delay: 600
                                            text: qsTr("Language code(s), e.g. en  ?  en.*,ja  ?  all")
                                        }
                                    }
                                }
                            }
                        }

                        RowLayout {
                            visible: subsCheck.checked
                            Layout.fillWidth: true; spacing: 18
                            InlineCheck { id: autoSubsCheck; label: qsTr("Auto-generated"); tip: qsTr("Include auto-generated captions when available") }
                            InlineCheck {
                                id: embedSubsCheck; label: qsTr("Embed in video")
                                enabled_: root._containerSupportsSubs
                                tip: root._containerSupportsSubs ? qsTr("Embed subtitles into the video container") : qsTr("Embedding requires mp4, mkv, or webm")
                            }
                            Item { Layout.fillWidth: true }
                        }
                    }
                }

                // ?? Post-processing ????????????????????????????????????????????
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: ppRow.implicitHeight + 12
                    radius: 3; color: ColorPalette.panelBg; border.color: ColorPalette.border

                    RowLayout {
                        id: ppRow
                        anchors { fill: parent; margins: 6 }
                        spacing: 16
                        InlineCheck { id: embedThumbCheck;  label: qsTr("Embed thumbnail"); tip: qsTr("Embed cover art thumbnail into the video file (requires ffmpeg)") }
                        InlineCheck { id: embedMetaCheck;   label: qsTr("Embed metadata");  tip: qsTr("Write title, uploader, chapters etc. into the container metadata") }
                        InlineCheck {
                            id: sponsorBlockCheck; label: qsTr("SponsorBlock")
                            tip: qsTr("Remove sponsored segments, intros, outros and self-promotion\n(YouTube only ? requires ffmpeg)")
                        }
                        Item { Layout.fillWidth: true }
                    }
                }

                // ?? ffmpeg warning ?????????????????????????????????????????????
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: ffWarn.implicitHeight + 10
                    radius: 3; color: "#2a1a0a"; border.color: "#6a3a0a"
                    visible: containerCombo.currentText !== "webm" && !App.ytdlpManager.ffmpegAvailable
                    Text {
                        id: ffWarn
                        anchors { fill: parent; margins: 5 }
                        text: "\u26A0  ffmpeg not found \u2014 will fall back to a pre-muxed stream (\u2264480p WebM). " +
                              "Drop ffmpeg.exe next to yt-dlp.exe for HD output. See Settings \u203a Video Downloader."
                        color: "#ddaa55"; font.pixelSize: 11 * App.fontScale; wrapMode: Text.WordWrap
                    }
                }

                // ?? Advanced (collapsible) ?????????????????????????????????????
                ColumnLayout {
                    Layout.fillWidth: true; spacing: 0

                    Rectangle {
                        Layout.fillWidth: true; implicitHeight: 28; radius: 3
                        color: advMouse.containsMouse ? ColorPalette.hoverBg : ColorPalette.panelBg
                        border.color: ColorPalette.border

                        RowLayout {
                            anchors { fill: parent; leftMargin: 9; rightMargin: 9 }
                            spacing: 6
                            Text { text: root.advancedExpanded ? "▼" : "▶"; color: ColorPalette.textMuted; font.pixelSize: 9 * App.fontScale; Layout.alignment: Qt.AlignVCenter }
                            Text { text: qsTr("Advanced"); color: ColorPalette.textSecond; font.pixelSize: 11 * App.fontScale; font.weight: Font.Medium; Layout.alignment: Qt.AlignVCenter }
                            Item { Layout.fillWidth: true }
                            Text {
                                visible: !root.advancedExpanded
                                property string s: {
                                    var p = []
                                    if (dateAfterField.text.trim().length > 0) p.push(qsTr("date filter"))
                                    if (cookiesBrowserCombo.currentIndex > 0) p.push(qsTr("cookies"))
                                    if (useArchiveCheck.checked)               p.push(qsTr("archive"))
                                    if (splitChaptersCheck.checked)            p.push(qsTr("split chapters"))
                                    if (sectionsField.text.trim().length > 0)  p.push(qsTr("time range"))
                                    if (writeDescCheck.checked || writeThumbnailCheck.checked) p.push(qsTr("extra files"))
                                    if (playlistRandomCheck.checked)           p.push(qsTr("random"))
                                    if (playlistReverseCheck.checked)          p.push(qsTr("reversed"))
                                    if (liveFromStartCheck.checked)            p.push(qsTr("live start"))
                                    if (ignoreErrorsCheck.checked)             p.push(qsTr("skip errors"))
                                    if (waitForVideoCheck.checked)             p.push(qsTr("wait for stream"))
                                    if (concFragField.text.trim().length > 0)  p.push(qsTr("parallel frags"))
                                    if (rateLimitField.text.trim().length > 0) p.push(qsTr("rate limit"))
                                    return p.join(" ? ")
                                }
                                text: s; color: ColorPalette.textMuted; font.pixelSize: 10 * App.fontScale; Layout.alignment: Qt.AlignVCenter
                            }
                        }
                        MouseArea { id: advMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.advancedExpanded = !root.advancedExpanded }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        visible: root.advancedExpanded
                        implicitHeight: advGrid.implicitHeight + 18
                        radius: 3; color: ColorPalette.panelBg; border.color: ColorPalette.border

                        GridLayout {
                            id: advGrid
                            anchors { fill: parent; margins: 10 }
                            columns: 2; rowSpacing: 8; columnSpacing: 10

                            Text { text: qsTr("After date:"); color: ColorPalette.textSecond; font.pixelSize: 11 * App.fontScale; horizontalAlignment: Text.AlignRight; Layout.alignment: Qt.AlignVCenter | Qt.AlignRight }
                            RowLayout { spacing: 6
                                Rectangle { width: 100; height: 20; radius: 2; color: ColorPalette.inputBg; border.color: dateAfterField.activeFocus ? "#4488dd" : ColorPalette.border
                                    Text { anchors.left: parent.left; anchors.leftMargin: 5; anchors.verticalCenter: parent.verticalCenter; text: "YYYY-MM-DD"; color: "#555555"; font.pixelSize: 11 * App.fontScale; visible: dateAfterField.text.length === 0 }
                                    TextInput { id: dateAfterField; anchors.fill: parent; anchors.leftMargin: 5; anchors.rightMargin: 5; color: ColorPalette.textPrimary; font.pixelSize: 11 * App.fontScale; verticalAlignment: Text.AlignVCenter; selectByMouse: true }
                                }
                                Text { text: qsTr("Only videos uploaded on or after this date"); color: ColorPalette.textMuted; font.pixelSize: 10 * App.fontScale; Layout.alignment: Qt.AlignVCenter }
                            }

                            Text { text: qsTr("Cookies:"); color: ColorPalette.textSecond; font.pixelSize: 11 * App.fontScale; horizontalAlignment: Text.AlignRight; Layout.alignment: Qt.AlignVCenter | Qt.AlignRight }
                            RowLayout { spacing: 6
                                ComboBox {
                                    id: cookiesBrowserCombo; implicitWidth: 100; implicitHeight: 24; font.pixelSize: 11 * App.fontScale; currentIndex: 0
                                    model: ["None","Chrome","Firefox","Edge","Brave","Opera","Vivaldi","Safari"]
                                    Component.onCompleted: {
                                        var v = (App.settings.ytdlpDefaultCookieBrowser || "").toLowerCase()
                                        if (v.length > 0 && v !== "none") {
                                            for (var i = 1; i < model.length; ++i)
                                                if (model[i].toLowerCase() === v) { currentIndex = i; break }
                                        }
                                    }
                                    contentItem: Text { leftPadding: 7; text: cookiesBrowserCombo.displayText; color: ColorPalette.textPrimary; font: cookiesBrowserCombo.font; verticalAlignment: Text.AlignVCenter }
                                    background: Rectangle { color: ColorPalette.inputBg; border.color: cookiesBrowserCombo.activeFocus ? "#4488dd" : ColorPalette.border; radius: 2 }
                                    delegate: ItemDelegate {
                                        id: _ckDel; width: cookiesBrowserCombo.width; height: 22
                                        contentItem: Text { text: modelData; color: ColorPalette.textPrimary; font.pixelSize: 11 * App.fontScale; verticalAlignment: Text.AlignVCenter; leftPadding: 7 }
                                        background: Rectangle { color: _ckDel.hovered ? "#2a3a5a" : ColorPalette.inputBg }
                                    }
                                    popup: Popup {
                                        y: cookiesBrowserCombo.height + 2; width: cookiesBrowserCombo.width
                                        implicitHeight: contentItem.implicitHeight + 4; padding: 2
                                        background: Rectangle { color: ColorPalette.inputBg; border.color: ColorPalette.border; radius: 3 }
                                        contentItem: ListView { implicitHeight: contentHeight; clip: true; model: cookiesBrowserCombo.delegateModel }
                                    }
                                }
                                Text { text: qsTr("Load cookies for members-only / age-restricted content"); color: ColorPalette.textMuted; font.pixelSize: 10 * App.fontScale; Layout.alignment: Qt.AlignVCenter }
                            }

                            Text { text: qsTr("Rate limit:"); color: ColorPalette.textSecond; font.pixelSize: 11 * App.fontScale; horizontalAlignment: Text.AlignRight; Layout.alignment: Qt.AlignVCenter | Qt.AlignRight }
                            RowLayout { spacing: 6
                                Rectangle { width: 68; height: 20; radius: 2; color: ColorPalette.inputBg; border.color: rateLimitField.activeFocus ? "#4488dd" : ColorPalette.border
                                    TextInput {
                                        id: rateLimitField
                                        anchors { fill: parent; leftMargin: 5; rightMargin: 5 }
                                        color: ColorPalette.textPrimary; font.pixelSize: 11 * App.fontScale; verticalAlignment: Text.AlignVCenter
                                        inputMethodHints: Qt.ImhDigitsOnly; selectByMouse: true
                                        validator: IntValidator { bottom: 1; top: 999999 }
                                        onActiveFocusChanged: if (activeFocus) selectAll()
                                    }
                                }
                                Text { text: qsTr("KB/s  (blank = use global speed limit)"); color: ColorPalette.textMuted; font.pixelSize: 10 * App.fontScale; Layout.alignment: Qt.AlignVCenter }
                            }

                            Text { text: qsTr("Time range:"); color: ColorPalette.textSecond; font.pixelSize: 11 * App.fontScale; horizontalAlignment: Text.AlignRight; Layout.alignment: Qt.AlignVCenter | Qt.AlignRight }
                            RowLayout { spacing: 6
                                Rectangle { width: 128; height: 20; radius: 2; color: ColorPalette.inputBg; border.color: sectionsField.activeFocus ? "#4488dd" : ColorPalette.border
                                    Text { anchors.left: parent.left; anchors.leftMargin: 5; anchors.verticalCenter: parent.verticalCenter; text: "*00:30-02:45"; color: "#555555"; font.pixelSize: 11 * App.fontScale; visible: sectionsField.text.length === 0 }
                                    TextInput { id: sectionsField; anchors.fill: parent; anchors.leftMargin: 5; anchors.rightMargin: 5; color: ColorPalette.textPrimary; font.pixelSize: 11 * App.fontScale; verticalAlignment: Text.AlignVCenter; selectByMouse: true }
                                }
                                Text { text: qsTr("Download only this section, e.g. *01:30-03:00"); color: ColorPalette.textMuted; font.pixelSize: 10 * App.fontScale; Layout.alignment: Qt.AlignVCenter }
                            }

                            Item { Layout.columnSpan: 2; implicitHeight: 2 }
                            Item {}
                            RowLayout { spacing: 18
                                InlineCheck { id: useArchiveCheck;    label: qsTr("Skip already downloaded"); tip: "Keep a yt-dlp-archive.txt in the save folder; future runs skip already-downloaded videos" }
                                InlineCheck { id: splitChaptersCheck; label: qsTr("Split by chapters");       tip: "Create one file per chapter marker (requires ffmpeg)" }
                            }
                            Item {}
                            RowLayout { spacing: 18
                                InlineCheck { id: writeDescCheck;      label: qsTr("Save description"); tip: "Write a .description text file alongside the video" }
                                InlineCheck { id: writeThumbnailCheck; label: qsTr("Save thumbnail");   tip: "Write the thumbnail as a separate image file" }
                            }
                            Item {}
                            RowLayout { spacing: 18
                                InlineCheck { id: playlistRandomCheck;  label: qsTr("Shuffle playlist");  enabled_: root._isChannelUrl; tip: qsTr("Download playlist in random order") }
                                InlineCheck { id: playlistReverseCheck; label: qsTr("Reverse order");     enabled_: root._isChannelUrl; tip: qsTr("Download newest videos first (reverses playlist order)") }
                            }
                            Item {}
                            RowLayout { spacing: 18
                                InlineCheck { id: liveFromStartCheck;  label: qsTr("Live: from start"); tip: qsTr("Download a livestream from the beginning (YouTube, Twitch, TVer)") }
                                InlineCheck { id: ignoreErrorsCheck;   label: qsTr("Skip errors");      tip: qsTr("Continue downloading the rest of a playlist when one video fails (unavailable, geo-blocked, etc.)") }
                            }

                            // ?? Wait for scheduled stream ??????????????????????
                            Text { text: qsTr("Wait for stream:"); color: ColorPalette.textSecond; font.pixelSize: 11 * App.fontScale; horizontalAlignment: Text.AlignRight; Layout.alignment: Qt.AlignVCenter | Qt.AlignRight }
                            RowLayout { spacing: 6
                                InlineCheck {
                                    id: waitForVideoCheck
                                    label: ""
                                    tip: qsTr("Wait for a scheduled/upcoming stream to start, retrying every N seconds")
                                }
                                Rectangle {
                                    width: 52; height: 20; radius: 2; color: ColorPalette.inputBg
                                    border.color: waitForVideoField.activeFocus ? "#4488dd" : ColorPalette.border
                                    opacity: waitForVideoCheck.checked ? 1.0 : 0.38
                                    TextInput {
                                        id: waitForVideoField
                                        anchors { fill: parent; leftMargin: 5; rightMargin: 5 }
                                        text: "60"; color: ColorPalette.textPrimary; font.pixelSize: 11 * App.fontScale
                                        verticalAlignment: Text.AlignVCenter
                                        inputMethodHints: Qt.ImhDigitsOnly
                                        validator: IntValidator { bottom: 1; top: 86400 }
                                        enabled: waitForVideoCheck.checked
                                        selectByMouse: true
                                        onActiveFocusChanged: if (activeFocus) selectAll()
                                    }
                                }
                                Text { text: qsTr("s retry interval  (for scheduled/upcoming streams)"); color: ColorPalette.textMuted; font.pixelSize: 10 * App.fontScale; Layout.alignment: Qt.AlignVCenter }
                            }

                            // ?? Concurrent DASH/HLS fragments ?????????????????
                            Text { text: qsTr("Parallel frags:"); color: ColorPalette.textSecond; font.pixelSize: 11 * App.fontScale; horizontalAlignment: Text.AlignRight; Layout.alignment: Qt.AlignVCenter | Qt.AlignRight }
                            RowLayout { spacing: 6
                                Rectangle { width: 44; height: 20; radius: 2; color: ColorPalette.inputBg; border.color: concFragField.activeFocus ? "#4488dd" : ColorPalette.border
                                    Text { anchors.left: parent.left; anchors.leftMargin: 5; anchors.verticalCenter: parent.verticalCenter; text: "1"; color: "#555555"; font.pixelSize: 11 * App.fontScale; visible: concFragField.text.length === 0 }
                                    TextInput {
                                        id: concFragField
                                        anchors { fill: parent; leftMargin: 5; rightMargin: 5 }
                                        color: ColorPalette.textPrimary; font.pixelSize: 11 * App.fontScale; verticalAlignment: Text.AlignVCenter
                                        inputMethodHints: Qt.ImhDigitsOnly; selectByMouse: true
                                        validator: IntValidator { bottom: 1; top: 16 }
                                        onActiveFocusChanged: if (activeFocus) selectAll()
                                    }
                                }
                                Text { text: qsTr("Concurrent DASH/HLS fragments (blank = 1, max 16)"); color: ColorPalette.textMuted; font.pixelSize: 10 * App.fontScale; Layout.alignment: Qt.AlignVCenter }
                            }
                        }
                    }
                }

                // ?? Save location ??????????????????????????????????????????????
                RowLayout {
                    Layout.fillWidth: true; spacing: 8
                    Text { text: qsTr("Save to:"); color: ColorPalette.textMuted; font.pixelSize: 11 * App.fontScale; Layout.preferredWidth: 58 }
                    TextField {
                        id: savePathField
                        Layout.fillWidth: true; font.pixelSize: 12 * App.fontScale; color: ColorPalette.textPrimary
                        leftPadding: 8; rightPadding: 8
                        placeholderText: "Save directory\u2026"; placeholderTextColor: "#555555"
                        background: Rectangle { color: ColorPalette.inputBg; border.color: savePathField.activeFocus ? "#4488dd" : ColorPalette.border; radius: 3 }
                    }
                    DlgButton { text: "Browse\u2026"; onClicked: saveFolderDialog.open() }
                }

                // ?? Category + Container on same row ???????????????????????????
                RowLayout {
                    Layout.fillWidth: true; spacing: 8
                    Text { text: qsTr("Category:"); color: ColorPalette.textMuted; font.pixelSize: 11 * App.fontScale; Layout.preferredWidth: 58 }
                    ComboBox {
                        id: catCombo; Layout.fillWidth: true; font.pixelSize: 12 * App.fontScale; model: root.categoryLabels
                        contentItem: Text { leftPadding: 8; text: catCombo.displayText; color: ColorPalette.textPrimary; font: catCombo.font; verticalAlignment: Text.AlignVCenter }
                        background: Rectangle { color: ColorPalette.inputBg; border.color: catCombo.activeFocus ? "#4488dd" : ColorPalette.border; radius: 3 }
                        delegate: ItemDelegate {
                            id: _catDel; width: catCombo.width; height: 26
                            contentItem: Text { text: modelData; color: ColorPalette.textPrimary; font.pixelSize: 12 * App.fontScale; verticalAlignment: Text.AlignVCenter; leftPadding: 8 }
                            background: Rectangle { color: _catDel.hovered ? "#2a3a5a" : ColorPalette.inputBg }
                        }
                        popup: Popup {
                            y: catCombo.height + 2; width: catCombo.width
                            implicitHeight: contentItem.implicitHeight + 4; padding: 2
                            background: Rectangle { color: ColorPalette.inputBg; border.color: ColorPalette.border; radius: 3 }
                            contentItem: ListView { implicitHeight: contentHeight; clip: true; model: catCombo.delegateModel; ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded } }
                        }
                        onCurrentIndexChanged: root._updateSavePath(currentIndex)
                    }

                    Text { text: qsTr("Format:"); color: ColorPalette.textMuted; font.pixelSize: 11 * App.fontScale }
                    ComboBox {
                        id: containerCombo; implicitWidth: 90; font.pixelSize: 12 * App.fontScale
                        property bool _audioOnly: { var f = root._formats[formatList.currentIndex]; return f ? (f.height === 0) : false }
                        on_AudioOnlyChanged: currentIndex = 0
                        model: _audioOnly ? ["mp3","m4a","opus","flac","wav","aac"] : ["mp4","mkv","webm","mov"]
                        currentIndex: 0
                        contentItem: Text { leftPadding: 8; text: containerCombo.displayText; color: ColorPalette.textPrimary; font: containerCombo.font; verticalAlignment: Text.AlignVCenter }
                        background: Rectangle { color: ColorPalette.inputBg; border.color: containerCombo.activeFocus ? "#4488dd" : ColorPalette.border; radius: 3 }
                        delegate: ItemDelegate {
                            id: _ctnDel; width: containerCombo.width; height: 24
                            contentItem: Text { text: modelData; color: ColorPalette.textPrimary; font.pixelSize: 12 * App.fontScale; verticalAlignment: Text.AlignVCenter; leftPadding: 8 }
                            background: Rectangle { color: _ctnDel.hovered ? "#2a3a5a" : ColorPalette.inputBg }
                        }
                        popup: Popup {
                            y: containerCombo.height + 2; width: containerCombo.width
                            implicitHeight: contentItem.implicitHeight + 4; padding: 2
                            background: Rectangle { color: ColorPalette.inputBg; border.color: ColorPalette.border; radius: 3 }
                            contentItem: ListView { implicitHeight: contentHeight; clip: true; model: containerCombo.delegateModel }
                        }
                    }
                }

                Item { implicitHeight: 4 }
            }       // closes optCol ColumnLayout
            }       // closes optScroll ScrollView
            }       // closes format picker + quality dropdown ColumnLayout
        }           // closes body Item

        // separator above buttons
        Rectangle { Layout.fillWidth: true; height: 1; color: ColorPalette.dividerBg }

        // ?? Buttons ???????????????????????????????????????????????????????????
        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: 8; Layout.bottomMargin: 10
            Layout.leftMargin: 16; Layout.rightMargin: 16
            spacing: 8

            ButtonGroup { id: allVideosGroup }

            Item { Layout.fillWidth: true }

            DlgButton { text: qsTr("Cancel"); onClicked: root.close() }

            DlgButton {
                text: root._isChannelUrl ? qsTr("Download Channel") : qsTr("Download")
                primary: true
                enabled: !root._probing && root._probeError.length === 0
                         && root._formats.length > 0 && savePathField.text.trim().length > 0

                onClicked: {
                    root._accepted = true
                    var fmt      = root._formats[formatList.currentIndex]
                    var formatId = (fmt && fmt.id) ? String(fmt.id) : ""
                    if (formatId.length === 0) {
                        // Empty = no format selector - YtdlpTransfer skips -f,
                        // yt-dlp uses default (bestvideo+bestaudio/best).
                        // Used for fallback entries when probe returned no formats.
                    } else if (formatId === "best") {
                        formatId = "bv*+ba/b"
                    }
                    var container= containerCombo.currentText || "mp4"
                    var savePath = savePathField.text.trim()
                    while (savePath.endsWith("/") || savePath.endsWith("\\")) savePath = savePath.slice(0, -1)
                    var catId    = root.categoryIds[catCombo.currentIndex] || ""
                    var isPl     = root._isChannelUrl
                    var nItems   = (isPl && allVideosGroup.checkedButton && allVideosGroup.checkedButton.text !== qsTr("All videos"))
                                   ? (parseInt(latestNField.text) || 10) : 0
                    var scope    = "all"
                    if (root._isYoutubeChannelRootUrl && scopeGroup.checkedButton) {
                        var sn = scopeGroup.checkedButton.objectName
                        if (sn === "scopeVid") scope = "videos"
                        else if (sn === "scopeSho") scope = "shorts"
                        else if (sn === "scopeLiv") scope = "live"
                    }
                    root.downloadRequested(root._channelScopedUrl(scope), formatId, container,
                                           savePath, catId, root.uniqueFilename, root._title,
                                           isPl, nItems, root._buildExtraOptions())
                    root.close()
                }
            }
        }
    }
}
