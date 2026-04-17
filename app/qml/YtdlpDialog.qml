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
import QtQuick.Dialogs

// YtdlpDialog — format picker shown when a yt-dlp-compatible URL is submitted.
Window {
    id: root

    // ── Public API ────────────────────────────────────────────────────────────
    property string pendingUrl: ""
    property bool   uniqueFilename: false

    signal openSettingsRequested(int page)
    signal downloadRequested(string url, string formatId,
                             string containerFormat, string savePath, string category,
                             bool uniqueFilename, string videoTitle,
                             bool playlistMode, int maxItems,
                             var extraOptions)

    // ── Window ────────────────────────────────────────────────────────────────
    width:       660
    height:      640
    minimumWidth:  540
    minimumHeight: 480
    title:       "Video Download"
    color:       "#1e1e1e"
    modality:    Qt.ApplicationModal
    flags:       Qt.Dialog | Qt.WindowTitleHint | Qt.WindowCloseButtonHint

    Material.theme:      Material.Dark
    Material.background: "#1e1e1e"
    Material.accent:     "#4488dd"

    // ── Private state ─────────────────────────────────────────────────────────
    property string _probeId:    ""
    property string _title:      ""
    property var    _formats:    []
    property bool   _probing:    false
    property string _probeError: ""
    property bool   _accepted:   false
    property bool   advancedExpanded: false

    readonly property bool _isChannelUrl: {
        var u = pendingUrl.toLowerCase()
        return u.indexOf("/@") >= 0
            || u.indexOf("/channel/") >= 0
            || u.indexOf("/c/") >= 0
            || u.indexOf("/user/") >= 0
            || u.indexOf("playlist?list=") >= 0
            || u.indexOf("&list=") >= 0
    }
    readonly property bool _isYoutubeChannelRootUrl: {
        var u = pendingUrl.toLowerCase()
        var isYt = (u.indexOf("youtube.com/") >= 0 || u.indexOf("youtu.be/") >= 0)
        if (!isYt) return false
        if (u.indexOf("list=") >= 0) return false
        return u.indexOf("/@") >= 0 || u.indexOf("/channel/") >= 0
            || u.indexOf("/c/") >= 0 || u.indexOf("/user/") >= 0
    }
    readonly property bool _containerSupportsSubs: {
        var c = containerCombo.currentText
        return c === "mp4" || c === "mkv" || c === "webm"
    }

    // ── Lifecycle ─────────────────────────────────────────────────────────────
    onVisibleChanged: {
        if (visible) { raise(); requestActivate(); if (pendingUrl.length > 0) _startProbe() }
        else _reset()
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
        dateAfterField.text = ""; cookiesBrowserCombo.currentIndex = 0
        writeDescCheck.checked = false; writeThumbnailCheck.checked = false
        splitChaptersCheck.checked = false; sectionsField.text = ""
        playlistRandomCheck.checked = false; liveFromStartCheck.checked = false
        useArchiveCheck.checked = false; rateLimitField.text = ""
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

    // ── Category helpers ──────────────────────────────────────────────────────
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

    // ── yt-dlp response listener ──────────────────────────────────────────────
    Connections {
        target: App
        function onYtdlpInfoReady(probeId, url, title, formats) {
            if (probeId !== root._probeId) return
            root._probing = false
            root._title = title
            root._probeError = ""
            root._formats = (formats && formats.length > 0) ? formats : [{
                id: "bv*+ba/b",
                label: "Best quality",
                ext: "mp4",
                width: 0,
                height: 1,
                fps: 0,
                tbr: 0,
                vcodec: "",
                acodec: "",
                filesize: 0
            }]
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
        if (playlistRandomCheck.checked) o["playlistRandom"]    = true
        if (liveFromStartCheck.checked)  o["liveFromStart"]     = true
        if (useArchiveCheck.checked)     o["useArchive"]        = true
        var rl = parseInt(rateLimitField.text.trim(), 10); if(!isNaN(rl)&&rl>0) o["rateLimitKBps"]=rl
        return o
    }

    // ── Reusable inline checkbox component ────────────────────────────────────
    // Using a plain component avoids Material CheckBox padding/layout quirks.
    component InlineCheck: Item {
        id: _chk
        property bool   checked:  false
        property string label:    ""
        property string tip:      ""
        property bool   enabled_: true
        property color  accentColor: "#4488dd"
        property color  accentBg:    "#1a3a6a"

        implicitWidth:  _chkRow.implicitWidth
        implicitHeight: _chkRow.implicitHeight
        opacity: enabled_ ? 1.0 : 0.38

        RowLayout {
            id: _chkRow
            anchors.verticalCenter: parent.verticalCenter
            spacing: 6

            Rectangle {
                width: 13; height: 13; radius: 2
                color:        _chk.checked ? _chk.accentBg : "#1b1b1b"
                border.color: _chk.checked ? _chk.accentColor : "#555555"
                Layout.alignment: Qt.AlignVCenter
                Text {
                    anchors.centerIn: parent
                    text: "✓"; font.pixelSize: 9
                    color: _chk.accentColor
                    visible: _chk.checked
                }
            }
            Text {
                text: _chk.label
                color: _chk.checked ? Qt.lighter(_chk.accentColor, 1.15) : "#aaaaaa"
                font.pixelSize: 11
                Layout.alignment: Qt.AlignVCenter
            }
        }

        MouseArea {
            anchors.fill: parent
            enabled: _chk.enabled_
            cursorShape: Qt.PointingHandCursor
            onClicked: _chk.checked = !_chk.checked
            hoverEnabled: _chk.tip.length > 0
            ToolTip.visible: containsMouse && _chk.tip.length > 0
            ToolTip.text: _chk.tip
            ToolTip.delay: 600
        }
    }

    FolderDialog {
        id: saveFolderDialog
        currentFolder: savePathField.text.trim().length > 0
                       ? ("file:///" + savePathField.text.trim().replace(/\\/g, "/"))
                       : ("file:///" + App.settings.defaultSavePath.replace(/\\/g, "/"))
        onAccepted: {
            var p = selectedFolder.toString().replace(/^file:\/\/\//,"").replace(/^file:\/\//,"")
            p = p.replace(/\//g,"\\")
            if (p.length > 0 && !p.endsWith("\\")) p += "\\"
            savePathField.text = p
        }
    }

    // ── Root layout ───────────────────────────────────────────────────────────
    // Structure: header (fixed) / format list (stretches) / options scroll (fixed max) / buttons (fixed)
    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // ── Header ────────────────────────────────────────────────────────────
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 54
            color: "#222228"

            // Use a plain Row + anchors — no RowLayout so text width is simply
            // "total width minus icon minus spacing minus margins".
            Item {
                anchors { fill: parent; leftMargin: 16; rightMargin: 16; topMargin: 9; bottomMargin: 9 }

                Image {
                    id: headerIcon
                    anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                    source: "qrc:/qt/qml/com/stellar/app/app/qml/icons/wand.ico"
                    sourceSize: Qt.size(20, 20)
                    width: 20; height: 20
                    fillMode: Image.PreserveAspectFit
                    smooth: true
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
                              : (root._probing ? "Fetching video info\u2026"
                              : (root._probeError.length > 0 ? "Could not fetch video info"
                              : "Video Download"))
                        color: "#e8e8e8"; font.pixelSize: 13; font.weight: Font.Medium
                        elide: Text.ElideRight
                    }
                    Text {
                        width: parent.width
                        text: root.pendingUrl
                        color: "#5a7aaa"; font.pixelSize: 11
                        elide: Text.ElideMiddle
                    }
                }
            }
        }

        // thin separator under header
        Rectangle { Layout.fillWidth: true; height: 1; color: "#2a2a2a" }

        // ── Body — stretches to fill remaining space; all states use anchors ──
        // Plain Item so all children position themselves with anchors, not Layout.
        Item {
            id: bodyItem
            Layout.fillWidth: true
            Layout.fillHeight: true

            // Loading
            ColumnLayout {
                anchors.centerIn: parent
                spacing: 14
                visible: root._probing
                BusyIndicator { Layout.alignment: Qt.AlignHCenter; running: root._probing; width: 44; height: 44 }
                Text { Layout.alignment: Qt.AlignHCenter; text: "Fetching available formats\u2026"; color: "#aaaaaa"; font.pixelSize: 13 }
            }

            // Error
            ColumnLayout {
                anchors.centerIn: parent
                width: Math.min(parent.width - 48, 480)
                spacing: 12
                visible: !root._probing && root._probeError.length > 0

                Text { Layout.alignment: Qt.AlignHCenter; text: "\u26A0"; font.pixelSize: 34; color: "#cc8800" }
                Text { Layout.alignment: Qt.AlignHCenter; text: "Could not fetch video information"; color: "#e0e0e0"; font.pixelSize: 13; font.weight: Font.Medium }

                Text {
                    Layout.fillWidth: true
                    text: root._probeError.replace(/(\r?\n)+null\s*$/g, "").trim()
                    color: "#aaaaaa"; font.pixelSize: 11; wrapMode: Text.Wrap; horizontalAlignment: Text.AlignHCenter
                }

                // n-challenge specific help box — shown when yt-dlp reports JS runtime missing
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
                            text: "YouTube n-challenge solving failed"
                            color: "#ddaa44"; font.pixelSize: 12; font.bold: true
                            wrapMode: Text.Wrap
                        }
                        Text {
                            Layout.fillWidth: true
                            text: "yt-dlp requires a JavaScript runtime (Deno, Node.js, Bun, or QuickJS) to bypass YouTube's " +
                                  "URL throttling challenge. Install one and place it next to yt-dlp.exe or in your system PATH.\n\n" +
                                  (!App.ytdlpManager.jsRuntimeAvailable
                                   ? "No runtime detected. Install Deno (recommended) from deno.com, then re-check in Settings → Video Downloader."
                                   : "Runtime detected: " + App.ytdlpManager.jsRuntimeName + " (" + App.ytdlpManager.jsRuntimePath + ")")
                            color: "#aa9966"; font.pixelSize: 11
                            wrapMode: Text.Wrap
                        }
                        RowLayout {
                            spacing: 6
                            DlgButton {
                                text: "Get Deno"
                                visible: !App.ytdlpManager.jsRuntimeAvailable
                                onClicked: Qt.openUrlExternally("https://deno.com")
                            }
                            DlgButton {
                                text: "Open Settings"
                                visible: !App.ytdlpManager.jsRuntimeAvailable
                                onClicked: root.openSettingsRequested(7)  // Media tab
                            }
                        }
                    }
                }

                // Cookies selector — lets the user authenticate and retry without reopening settings
                Rectangle {
                    Layout.alignment: Qt.AlignHCenter
                    implicitWidth: errCookiesRow.implicitWidth + 20
                    implicitHeight: errCookiesRow.implicitHeight + 14
                    color: "#1a1a22"; border.color: "#2e2e44"; radius: 4

                    RowLayout {
                        id: errCookiesRow
                        anchors.centerIn: parent
                        spacing: 8

                        Text { text: "Cookies from browser:"; color: "#8899bb"; font.pixelSize: 11 }

                        ComboBox {
                            id: errCookieCombo
                            implicitWidth: 110; implicitHeight: 24; font.pixelSize: 11
                            model: ["None","Chrome","Firefox","Edge","Brave","Opera","Vivaldi","Safari"]
                            // Sync with the advanced-tab cookies combo so they share state
                            currentIndex: cookiesBrowserCombo.currentIndex
                            onCurrentIndexChanged: cookiesBrowserCombo.currentIndex = currentIndex
                            contentItem: Text { leftPadding: 7; text: errCookieCombo.displayText; color: "#d0d0d0"; font: errCookieCombo.font; verticalAlignment: Text.AlignVCenter }
                            background: Rectangle { color: "#1b1b1b"; border.color: errCookieCombo.activeFocus ? "#4488dd" : "#3a3a3a"; radius: 3 }
                            delegate: ItemDelegate {
                                id: _ecDel; width: errCookieCombo.width; height: 24
                                contentItem: Text { text: modelData; color: "#d0d0d0"; font.pixelSize: 11; verticalAlignment: Text.AlignVCenter; leftPadding: 7 }
                                background: Rectangle { color: _ecDel.hovered ? "#2a3a5a" : "#1b1b1b" }
                            }
                            popup: Popup {
                                y: errCookieCombo.height + 2; width: errCookieCombo.width
                                implicitHeight: contentItem.implicitHeight + 4; padding: 2
                                background: Rectangle { color: "#1b1b1b"; border.color: "#3a3a3a"; radius: 3 }
                                contentItem: ListView { implicitHeight: contentHeight; clip: true; model: errCookieCombo.delegateModel }
                            }
                        }
                    }
                }

                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: "Select a browser to pass its cookies to yt-dlp, then retry."
                    color: "#556677"; font.pixelSize: 10
                    visible: errCookieCombo.currentIndex === 0
                }

                DlgButton { Layout.alignment: Qt.AlignHCenter; text: "Retry"; onClicked: root._startProbe() }
            }

            // Format picker — fills the whole body, options scroll is capped below it
            ColumnLayout {
                anchors { fill: parent; topMargin: 12; leftMargin: 16; rightMargin: 16; bottomMargin: 0 }
                spacing: 5
                visible: !root._probing && root._probeError.length === 0 && root._formats.length > 0

                Text { text: "Select quality:"; color: "#888888"; font.pixelSize: 11 }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    color: "#181818"; border.color: "#383838"; radius: 4; clip: true

                    ListView {
                        id: formatList
                        anchors { fill: parent; margins: 1 }
                        model: root._formats; currentIndex: 0
                        clip: true; boundsBehavior: Flickable.StopAtBounds
                        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                    delegate: Rectangle {
                        id: fd
                        width: formatList.width; height: 32
                        readonly property bool sel: formatList.currentIndex === index
                        readonly property bool hov: fmMouse.containsMouse
                        color: sel ? "#1a3a6a" : (hov ? "#232333" : "transparent")
                        Rectangle { width: 3; height: parent.height; color: "#4488dd"; visible: fd.sel }

                        RowLayout {
                            anchors { fill: parent; leftMargin: 10; rightMargin: 8 }
                            spacing: 6

                            Text {
                                text: modelData.label || ""
                                font.pixelSize: 12
                                color: fd.sel ? "#c0d8ff" : "#d0d0d0"
                                font.weight: fd.sel ? Font.Medium : Font.Normal
                                Layout.minimumWidth: 70
                            }

                            Rectangle {
                                property string c: root._codecLabel(modelData.vcodec || "")
                                visible: c.length > 0 && modelData.id !== "best" && modelData.id !== "bestvideo+bestaudio/best"
                                width: _ct.implicitWidth + 10; height: 15; radius: 3
                                color: c==="AV1"?"#1a2020":c==="VP9"?"#1e1a20":c==="H.264"?"#1a2030":c==="H.265"?"#201a1a":"#1e1e1e"
                                border.color: c==="AV1"?"#2a5040":c==="VP9"?"#3a2a50":c==="H.264"?"#2a4060":c==="H.265"?"#502a2a":"#3a3a3a"
                                Text { id: _ct; anchors.centerIn: parent; text: parent.c; font.pixelSize: 9
                                    color: parent.c==="AV1"?"#5abba0":parent.c==="VP9"?"#9a70cc":parent.c==="H.264"?"#6a9acc":parent.c==="H.265"?"#cc7a7a":"#aaaaaa" }
                            }

                            Rectangle {
                                property string a: root._acodecLabel(modelData.acodec || "")
                                visible: a.length > 0 && (modelData.height === 0 || !modelData.vcodec || modelData.vcodec === "none") && modelData.id !== "best"
                                width: _at.implicitWidth + 10; height: 15; radius: 3
                                color: "#1a1e20"; border.color: "#2a4040"
                                Text { id: _at; anchors.centerIn: parent; text: parent.a; font.pixelSize: 9; color: "#5a9aaa" }
                            }

                            Rectangle {
                                property int f: modelData.fps || 0
                                visible: f > 0 && f !== 30 && (modelData.height || 0) > 0
                                width: _ft.implicitWidth + 10; height: 15; radius: 3
                                color: "#1e1e2a"; border.color: "#2a2a50"
                                Text { id: _ft; anchors.centerIn: parent; text: parent.f + " fps"; font.pixelSize: 9; color: "#8888cc" }
                            }

                            Item { Layout.fillWidth: true }

                            Text {
                                text: root._formatSize(modelData.filesize)
                                color: fd.sel ? "#8aaddd" : "#6a8aaa"; font.pixelSize: 11
                                visible: (modelData.filesize || 0) > 0
                            }
                        }

                        MouseArea { id: fmMouse; anchors.fill: parent; hoverEnabled: true; onClicked: formatList.currentIndex = index }
                    }
                }
            }

            // ── Options scroll (capped height — always below format list) ─────
            ScrollView {
                id: optScroll
                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(optCol.implicitHeight + 2, 280)
                Layout.maximumHeight: 280
                Layout.leftMargin: 0
                Layout.rightMargin: 0
                Layout.topMargin: 6
                clip: true
                ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
                ScrollBar.vertical.policy: ScrollBar.AsNeeded

            ColumnLayout {
                id: optCol
                // ScrollView's content width equals the viewport width set by ScrollBar.horizontal.policy=AlwaysOff
                width: optScroll.availableWidth
                spacing: 6

                // ── Channel / playlist ─────────────────────────────────────────
                Rectangle {
                    Layout.fillWidth: true
                    visible: root._isChannelUrl
                    implicitHeight: chRow.implicitHeight + 18
                    radius: 3; color: "#1a2030"; border.color: "#2a3a5a"

                    ColumnLayout {
                        id: chRow
                        anchors { fill: parent; margins: 9 }
                        spacing: 6

                        RowLayout {
                            Layout.fillWidth: true; spacing: 8
                            Text { text: "Channel / Playlist"; color: "#8899bb"; font.pixelSize: 11; font.weight: Font.Medium }
                            Item { Layout.fillWidth: true }

                            RowLayout {
                                spacing: 4
                                Repeater {
                                    model: [{id:"allV",t:"All videos"},{id:"latN",t:"Latest"}]
                                    RadioButton {
                                        id: _rb
                                        required property var modelData
                                        checked: modelData.id === "allV"
                                        text: modelData.t; font.pixelSize: 11
                                        topPadding: 0; bottomPadding: 0; padding: 0
                                        leftPadding: modelData.id === "allV" ? 0 : 6
                                        Layout.alignment: Qt.AlignVCenter
                                        indicator: Rectangle {
                                            implicitWidth: 13; implicitHeight: 13; radius: 7
                                            color: _rb.checked ? "#1a3a6a" : "#1b1b1b"
                                            border.color: _rb.checked ? "#4488dd" : "#555555"
                                            Rectangle { width: 5; height: 5; radius: 3; anchors.centerIn: parent; color: "#4488dd"; visible: _rb.checked }
                                        }
                                        contentItem: Text {
                                            leftPadding: 4; text: _rb.text; color: "#c0c0c0"
                                            font: _rb.font; verticalAlignment: Text.AlignVCenter
                                        }
                                    }
                                }

                                Rectangle {
                                    id: latestNBox
                                    width: 44; height: 20; radius: 2; color: "#1b1b1b"
                                    Layout.alignment: Qt.AlignVCenter
                                    border.color: latestNField.activeFocus ? "#4488dd" : "#3a3a3a"
                                    property bool latestMode: !allVideosGroup.checkedButton || allVideosGroup.checkedButton.text !== "All videos"
                                    opacity: latestMode ? 1.0 : 0.38
                                    TextInput {
                                        id: latestNField
                                        anchors { fill: parent; leftMargin: 5; rightMargin: 5 }
                                        text: "10"; color: "#d0d0d0"; font.pixelSize: 11
                                        verticalAlignment: Text.AlignVCenter
                                        inputMethodHints: Qt.ImhDigitsOnly
                                        validator: IntValidator { bottom: 1; top: 9999 }
                                        enabled: latestNBox.latestMode
                                        selectByMouse: true
                                        onActiveFocusChanged: if (activeFocus) selectAll()
                                    }
                                }
                                Text { text: "videos"; color: "#667788"; font.pixelSize: 11; Layout.alignment: Qt.AlignVCenter }
                            }
                        }

                        Text {
                            Layout.fillWidth: true
                            text: root._isYoutubeChannelRootUrl
                                  ? "YouTube channel URLs include all uploads by default. Use Scope to target one tab."
                                  : "Videos will be saved in a subfolder named after the channel."
                            color: "#5a6a8a"; font.pixelSize: 10; wrapMode: Text.WordWrap
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            visible: root._isYoutubeChannelRootUrl
                            radius: 3; color: "#162236"; border.color: "#28456f"
                            implicitHeight: scopeRow.implicitHeight + 12

                            RowLayout {
                                id: scopeRow
                                anchors { fill: parent; margins: 6 }
                                spacing: 6
                                Text { text: "Scope:"; color: "#89a6d4"; font.pixelSize: 11; font.weight: Font.Medium }
                                ButtonGroup { id: scopeGroup }
                                Repeater {
                                    model: [{id:"scopeAll",t:"All uploads",chk:true},{id:"scopeVid",t:"Videos"},{id:"scopeSho",t:"Shorts"},{id:"scopeLiv",t:"Live"}]
                                    RadioButton {
                                        required property var modelData
                                        id: scopeRb
                                        objectName: modelData.id
                                        checked: modelData.chk || false
                                        text: modelData.t
                                        ButtonGroup.group: scopeGroup
                                        topPadding: 0; bottomPadding: 0; padding: 0
                                        Layout.alignment: Qt.AlignVCenter
                                        font.pixelSize: 11
                                        contentItem: Text {
                                            leftPadding: 4; text: scopeRb.text; color: "#c0c0d8"
                                            font: scopeRb.font; verticalAlignment: Text.AlignVCenter
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // ── Subtitles ──────────────────────────────────────────────────
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: subsInner.implicitHeight + 16
                    radius: 3
                    color: "#181e18"
                    border.color: subsCheck.checked ? "#336633" : "#2a2a2a"

                    ColumnLayout {
                        id: subsInner
                        anchors { fill: parent; margins: 8 }
                        spacing: 6

                        RowLayout {
                            Layout.fillWidth: true; spacing: 10
                            InlineCheck {
                                id: subsCheck
                                label: "Subtitles"
                                accentColor: "#55cc55"; accentBg: "#1a3a1a"
                                tip: "Download subtitle files alongside the video"
                            }
                            Item { Layout.fillWidth: true }
                            RowLayout {
                                visible: subsCheck.checked; spacing: 5
                                Text { text: "Language:"; color: "#778877"; font.pixelSize: 11; Layout.alignment: Qt.AlignVCenter }
                                Rectangle {
                                    width: 68; height: 20; radius: 2; color: "#1b1b1b"
                                    border.color: subLangsField.activeFocus ? "#4488dd" : "#3a3a3a"
                                    Layout.alignment: Qt.AlignVCenter
                                    TextInput {
                                        id: subLangsField
                                        anchors { fill: parent; leftMargin: 5; rightMargin: 5 }
                                        text: "en"; color: "#d0d0d0"; font.pixelSize: 11
                                        verticalAlignment: Text.AlignVCenter; selectByMouse: true
                                        ToolTip.visible: activeFocus; ToolTip.delay: 600
                                        ToolTip.text: "Language code(s), e.g. en  ·  en.*,ja  ·  all"
                                    }
                                }
                            }
                        }

                        RowLayout {
                            visible: subsCheck.checked
                            Layout.fillWidth: true; spacing: 18
                            InlineCheck { id: autoSubsCheck; label: "Auto-generated"; tip: "Include auto-generated captions when available" }
                            InlineCheck {
                                id: embedSubsCheck; label: "Embed in video"
                                enabled_: root._containerSupportsSubs
                                tip: root._containerSupportsSubs ? "Embed subtitles into the video container" : "Embedding requires mp4, mkv, or webm"
                            }
                            Item { Layout.fillWidth: true }
                        }
                    }
                }

                // ── Post-processing ────────────────────────────────────────────
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: ppRow.implicitHeight + 14
                    radius: 3; color: "#1a1a22"; border.color: "#2a2a2a"

                    RowLayout {
                        id: ppRow
                        anchors { fill: parent; margins: 8 }
                        spacing: 16
                        InlineCheck { id: embedThumbCheck;  label: "Embed thumbnail"; tip: "Embed cover art thumbnail into the video file (requires ffmpeg)" }
                        InlineCheck { id: embedMetaCheck;   label: "Embed metadata";  tip: "Write title, uploader, chapters etc. into the container metadata" }
                        InlineCheck {
                            id: sponsorBlockCheck; label: "SponsorBlock"
                            accentColor: "#aa77ee"; accentBg: "#2a1a40"
                            tip: "Remove sponsored segments, intros, outros and self-promotion\n(YouTube only · requires ffmpeg)"
                        }
                        Item { Layout.fillWidth: true }
                    }
                }

                // ── ffmpeg warning ─────────────────────────────────────────────
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
                        color: "#ddaa55"; font.pixelSize: 11; wrapMode: Text.WordWrap
                    }
                }

                // ── Advanced (collapsible) ─────────────────────────────────────
                ColumnLayout {
                    Layout.fillWidth: true; spacing: 0

                    Rectangle {
                        Layout.fillWidth: true; implicitHeight: 28; radius: 3
                        color: advMouse.containsMouse ? "#23232e" : "#1d1d28"
                        border.color: "#2e2e44"

                        RowLayout {
                            anchors { fill: parent; leftMargin: 9; rightMargin: 9 }
                            spacing: 6
                            Text { text: root.advancedExpanded ? "▼" : "▶"; color: "#6677aa"; font.pixelSize: 9; Layout.alignment: Qt.AlignVCenter }
                            Text { text: "Advanced"; color: "#8899bb"; font.pixelSize: 11; font.weight: Font.Medium; Layout.alignment: Qt.AlignVCenter }
                            Item { Layout.fillWidth: true }
                            Text {
                                visible: !root.advancedExpanded
                                property string s: {
                                    var p = []
                                    if (dateAfterField.text.trim().length > 0) p.push("date filter")
                                    if (cookiesBrowserCombo.currentIndex > 0) p.push("cookies")
                                    if (useArchiveCheck.checked)               p.push("archive")
                                    if (splitChaptersCheck.checked)            p.push("split chapters")
                                    if (sectionsField.text.trim().length > 0)  p.push("time range")
                                    if (writeDescCheck.checked || writeThumbnailCheck.checked) p.push("extra files")
                                    if (playlistRandomCheck.checked)           p.push("random")
                                    if (liveFromStartCheck.checked)            p.push("live start")
                                    if (rateLimitField.text.trim().length > 0) p.push("rate limit")
                                    return p.join(" · ")
                                }
                                text: s; color: "#445577"; font.pixelSize: 10; Layout.alignment: Qt.AlignVCenter
                            }
                        }
                        MouseArea { id: advMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.advancedExpanded = !root.advancedExpanded }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        visible: root.advancedExpanded
                        implicitHeight: advGrid.implicitHeight + 18
                        radius: 3; color: "#181820"; border.color: "#28283c"

                        GridLayout {
                            id: advGrid
                            anchors { fill: parent; margins: 10 }
                            columns: 2; rowSpacing: 8; columnSpacing: 10

                            Text { text: "After date:"; color: "#7788aa"; font.pixelSize: 11; horizontalAlignment: Text.AlignRight; Layout.alignment: Qt.AlignVCenter | Qt.AlignRight }
                            RowLayout { spacing: 6
                                Rectangle { width: 100; height: 20; radius: 2; color: "#1b1b1b"; border.color: dateAfterField.activeFocus ? "#4488dd" : "#3a3a3a"
                                    Text { anchors.left: parent.left; anchors.leftMargin: 5; anchors.verticalCenter: parent.verticalCenter; text: "YYYY-MM-DD"; color: "#383848"; font.pixelSize: 11; visible: dateAfterField.text.length === 0 }
                                    TextInput { id: dateAfterField; anchors.fill: parent; anchors.leftMargin: 5; anchors.rightMargin: 5; color: "#d0d0d0"; font.pixelSize: 11; verticalAlignment: Text.AlignVCenter; selectByMouse: true }
                                }
                                Text { text: "Only videos uploaded on or after this date"; color: "#445566"; font.pixelSize: 10; Layout.alignment: Qt.AlignVCenter }
                            }

                            Text { text: "Cookies:"; color: "#7788aa"; font.pixelSize: 11; horizontalAlignment: Text.AlignRight; Layout.alignment: Qt.AlignVCenter | Qt.AlignRight }
                            RowLayout { spacing: 6
                                ComboBox {
                                    id: cookiesBrowserCombo; implicitWidth: 100; implicitHeight: 24; font.pixelSize: 11; currentIndex: 0
                                    model: ["None","Chrome","Firefox","Edge","Brave","Opera","Vivaldi","Safari"]
                                    contentItem: Text { leftPadding: 7; text: cookiesBrowserCombo.displayText; color: "#d0d0d0"; font: cookiesBrowserCombo.font; verticalAlignment: Text.AlignVCenter }
                                    background: Rectangle { color: "#1b1b1b"; border.color: cookiesBrowserCombo.activeFocus ? "#4488dd" : "#3a3a3a"; radius: 2 }
                                    delegate: ItemDelegate {
                                        id: _ckDel; width: cookiesBrowserCombo.width; height: 22
                                        contentItem: Text { text: modelData; color: "#d0d0d0"; font.pixelSize: 11; verticalAlignment: Text.AlignVCenter; leftPadding: 7 }
                                        background: Rectangle { color: _ckDel.hovered ? "#2a3a5a" : "#1b1b1b" }
                                    }
                                    popup: Popup {
                                        y: cookiesBrowserCombo.height + 2; width: cookiesBrowserCombo.width
                                        implicitHeight: contentItem.implicitHeight + 4; padding: 2
                                        background: Rectangle { color: "#1b1b1b"; border.color: "#3a3a3a"; radius: 3 }
                                        contentItem: ListView { implicitHeight: contentHeight; clip: true; model: cookiesBrowserCombo.delegateModel }
                                    }
                                }
                                Text { text: "Load cookies for members-only / age-restricted content"; color: "#445566"; font.pixelSize: 10; Layout.alignment: Qt.AlignVCenter }
                            }

                            Text { text: "Rate limit:"; color: "#7788aa"; font.pixelSize: 11; horizontalAlignment: Text.AlignRight; Layout.alignment: Qt.AlignVCenter | Qt.AlignRight }
                            RowLayout { spacing: 6
                                Rectangle { width: 68; height: 20; radius: 2; color: "#1b1b1b"; border.color: rateLimitField.activeFocus ? "#4488dd" : "#3a3a3a"
                                    TextInput {
                                        id: rateLimitField
                                        anchors { fill: parent; leftMargin: 5; rightMargin: 5 }
                                        color: "#d0d0d0"; font.pixelSize: 11; verticalAlignment: Text.AlignVCenter
                                        inputMethodHints: Qt.ImhDigitsOnly; selectByMouse: true
                                        validator: IntValidator { bottom: 1; top: 999999 }
                                        onActiveFocusChanged: if (activeFocus) selectAll()
                                    }
                                }
                                Text { text: "KB/s  (blank = use global speed limit)"; color: "#445566"; font.pixelSize: 10; Layout.alignment: Qt.AlignVCenter }
                            }

                            Text { text: "Time range:"; color: "#7788aa"; font.pixelSize: 11; horizontalAlignment: Text.AlignRight; Layout.alignment: Qt.AlignVCenter | Qt.AlignRight }
                            RowLayout { spacing: 6
                                Rectangle { width: 128; height: 20; radius: 2; color: "#1b1b1b"; border.color: sectionsField.activeFocus ? "#4488dd" : "#3a3a3a"
                                    Text { anchors.left: parent.left; anchors.leftMargin: 5; anchors.verticalCenter: parent.verticalCenter; text: "*00:30-02:45"; color: "#383848"; font.pixelSize: 11; visible: sectionsField.text.length === 0 }
                                    TextInput { id: sectionsField; anchors.fill: parent; anchors.leftMargin: 5; anchors.rightMargin: 5; color: "#d0d0d0"; font.pixelSize: 11; verticalAlignment: Text.AlignVCenter; selectByMouse: true }
                                }
                                Text { text: "Download only this section, e.g. *01:30-03:00"; color: "#445566"; font.pixelSize: 10; Layout.alignment: Qt.AlignVCenter }
                            }

                            Item { Layout.columnSpan: 2; implicitHeight: 2 }
                            Item {}
                            RowLayout { spacing: 18
                                InlineCheck { id: useArchiveCheck;    label: "Skip already downloaded"; tip: "Keep a yt-dlp-archive.txt in the save folder; future runs skip already-downloaded videos" }
                                InlineCheck { id: splitChaptersCheck; label: "Split by chapters";       tip: "Create one file per chapter marker (requires ffmpeg)" }
                            }
                            Item {}
                            RowLayout { spacing: 18
                                InlineCheck { id: writeDescCheck;      label: "Save description"; tip: "Write a .description text file alongside the video" }
                                InlineCheck { id: writeThumbnailCheck; label: "Save thumbnail";   tip: "Write the thumbnail as a separate image file" }
                            }
                            Item {}
                            RowLayout { spacing: 18
                                InlineCheck { id: playlistRandomCheck; label: "Shuffle playlist"; enabled_: root._isChannelUrl; tip: "Download playlist in random order" }
                                InlineCheck { id: liveFromStartCheck;  label: "Live: from start"; tip: "Download a livestream from the beginning (YouTube, Twitch)" }
                            }
                        }
                    }
                }

                // ── Divider before save/cat/format ─────────────────────────────
                Rectangle { Layout.fillWidth: true; height: 1; color: "#2a2a2a" }

                // ── Save location ──────────────────────────────────────────────
                RowLayout {
                    Layout.fillWidth: true; spacing: 8
                    Text { text: "Save to:"; color: "#aaaaaa"; font.pixelSize: 12; Layout.preferredWidth: 62 }
                    TextField {
                        id: savePathField
                        Layout.fillWidth: true; font.pixelSize: 12; color: "#d0d0d0"
                        leftPadding: 8; rightPadding: 8
                        placeholderText: "Save directory\u2026"; placeholderTextColor: "#555555"
                        background: Rectangle { color: "#1b1b1b"; border.color: savePathField.activeFocus ? "#4488dd" : "#3a3a3a"; radius: 3 }
                    }
                    DlgButton { text: "Browse\u2026"; onClicked: saveFolderDialog.open() }
                }

                // ── Category + Container on same row ───────────────────────────
                RowLayout {
                    Layout.fillWidth: true; spacing: 8
                    Text { text: "Category:"; color: "#aaaaaa"; font.pixelSize: 12; Layout.preferredWidth: 62 }
                    ComboBox {
                        id: catCombo; Layout.fillWidth: true; font.pixelSize: 12; model: root.categoryLabels
                        contentItem: Text { leftPadding: 8; text: catCombo.displayText; color: "#d0d0d0"; font: catCombo.font; verticalAlignment: Text.AlignVCenter }
                        background: Rectangle { color: "#1b1b1b"; border.color: catCombo.activeFocus ? "#4488dd" : "#3a3a3a"; radius: 3 }
                        delegate: ItemDelegate {
                            id: _catDel; width: catCombo.width; height: 26
                            contentItem: Text { text: modelData; color: "#d0d0d0"; font.pixelSize: 12; verticalAlignment: Text.AlignVCenter; leftPadding: 8 }
                            background: Rectangle { color: _catDel.hovered ? "#2a3a5a" : "#1b1b1b" }
                        }
                        popup: Popup {
                            y: catCombo.height + 2; width: catCombo.width
                            implicitHeight: contentItem.implicitHeight + 4; padding: 2
                            background: Rectangle { color: "#1b1b1b"; border.color: "#3a3a3a"; radius: 3 }
                            contentItem: ListView { implicitHeight: contentHeight; clip: true; model: catCombo.delegateModel; ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded } }
                        }
                        onCurrentIndexChanged: root._updateSavePath(currentIndex)
                    }

                    Text { text: "Format:"; color: "#aaaaaa"; font.pixelSize: 12 }
                    ComboBox {
                        id: containerCombo; implicitWidth: 90; font.pixelSize: 12
                        property bool _audioOnly: { var f = root._formats[formatList.currentIndex]; return f ? (f.height === 0) : false }
                        on_AudioOnlyChanged: currentIndex = 0
                        model: _audioOnly ? ["mp3","m4a","opus","flac","wav","aac"] : ["mp4","mkv","webm","mov"]
                        currentIndex: 0
                        contentItem: Text { leftPadding: 8; text: containerCombo.displayText; color: "#d0d0d0"; font: containerCombo.font; verticalAlignment: Text.AlignVCenter }
                        background: Rectangle { color: "#1b1b1b"; border.color: containerCombo.activeFocus ? "#4488dd" : "#3a3a3a"; radius: 3 }
                        delegate: ItemDelegate {
                            id: _ctnDel; width: containerCombo.width; height: 24
                            contentItem: Text { text: modelData; color: "#d0d0d0"; font.pixelSize: 12; verticalAlignment: Text.AlignVCenter; leftPadding: 8 }
                            background: Rectangle { color: _ctnDel.hovered ? "#2a3a5a" : "#1b1b1b" }
                        }
                        popup: Popup {
                            y: containerCombo.height + 2; width: containerCombo.width
                            implicitHeight: contentItem.implicitHeight + 4; padding: 2
                            background: Rectangle { color: "#1b1b1b"; border.color: "#3a3a3a"; radius: 3 }
                            contentItem: ListView { implicitHeight: contentHeight; clip: true; model: containerCombo.delegateModel }
                        }
                    }
                }

                Item { implicitHeight: 4 }
            }       // closes optCol ColumnLayout
            }       // closes optScroll ScrollView
            }       // closes format picker ColumnLayout
        }           // closes body Item

        // ── Divider + buttons ─────────────────────────────────────────────────
        Rectangle { Layout.fillWidth: true; height: 1; color: "#2a2a2a" }

        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: 10; Layout.bottomMargin: 12
            Layout.leftMargin: 16; Layout.rightMargin: 16
            spacing: 8

            ButtonGroup { id: allVideosGroup }

            Item { Layout.fillWidth: true }

            DlgButton { text: "Cancel"; onClicked: root.close() }

            DlgButton {
                text: root._isChannelUrl ? "Download Channel" : "Download"
                primary: true
                enabled: !root._probing && root._probeError.length === 0
                         && root._formats.length > 0 && savePathField.text.trim().length > 0

                onClicked: {
                    root._accepted = true
                    var fmt      = root._formats[formatList.currentIndex]
                    var formatId = (fmt && fmt.id) ? String(fmt.id) : ""
                    if (formatId.length === 0 || formatId === "best")
                        formatId = "bv*+ba/b"
                    var container= containerCombo.currentText || "mp4"
                    var savePath = savePathField.text.trim()
                    while (savePath.endsWith("/") || savePath.endsWith("\\")) savePath = savePath.slice(0, -1)
                    var catId    = root.categoryIds[catCombo.currentIndex] || ""
                    var isPl     = root._isChannelUrl
                    var nItems   = (isPl && allVideosGroup.checkedButton && allVideosGroup.checkedButton.text !== "All videos")
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
