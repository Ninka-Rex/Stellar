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
//
// Flow:
//   1. Caller sets `pendingUrl` and calls show()/raise()/requestActivate().
//   2. Dialog runs App.beginYtdlpInfo(url) to probe available formats.
//   3. On success the format list is shown; user selects quality + save location.
//   4. User clicks "Download" → `downloadRequested(...)` emitted.
//      No DownloadItem is created until the user confirms — the entry only appears
//      in the download list once App.finalizeYtdlpDownload() is called by the handler.
//   5. Closing without confirming just closes the dialog; nothing to clean up.
Window {
    id: root

    // ── Public API ────────────────────────────────────────────────────────────
    property string pendingUrl: ""

    // Set to true when opened from a "Add Numbered" duplicate action.
    property bool uniqueFilename: false

    // Emitted when the user confirms the download.
    signal downloadRequested(string url, string formatId,
                             string containerFormat, string savePath, string category,
                             bool uniqueFilename, string videoTitle,
                             bool playlistMode, int maxItems)

    // ── Window appearance ─────────────────────────────────────────────────────
    width:       680
    height:      620
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
    property string  _probeId:    ""
    property string  _title:      ""
    property var     _formats:    []
    property bool    _probing:    false
    property string  _probeError: ""
    property bool    _accepted:   false

    // Whether the URL looks like a channel/playlist (not a single video).
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
        var isYoutube = (u.indexOf("youtube.com/") >= 0 || u.indexOf("youtu.be/") >= 0)
        if (!isYoutube) return false
        if (u.indexOf("list=") >= 0) return false
        return u.indexOf("/@") >= 0
            || u.indexOf("/channel/") >= 0
            || u.indexOf("/c/") >= 0
            || u.indexOf("/user/") >= 0
    }

    // ── Lifecycle ─────────────────────────────────────────────────────────────
    onVisibleChanged: {
        if (visible) {
            raise()
            requestActivate()
            if (pendingUrl.length > 0)
                _startProbe()
        } else {
            _reset()
        }
    }

    onPendingUrlChanged: {
        if (visible && pendingUrl.length > 0 && !_accepted)
            _startProbe()
    }

    // ── Private helpers ───────────────────────────────────────────────────────
    function _reset() {
        pendingUrl     = ""
        uniqueFilename = false
        _probeId    = ""
        _title      = ""
        _formats    = []
        _probing    = false
        _probeError = ""
        _accepted   = false
    }

    function _startProbe() {
        if (_probeId.length > 0)
            App.cancelYtdlpInfo(_probeId)
        _probeId    = ""
        _title      = ""
        _formats    = []
        _probeError = ""
        _probing    = true
        _probeId    = App.beginYtdlpInfo(pendingUrl)
    }

    function _channelScopedUrl(scope) {
        var raw = (pendingUrl || "").trim()
        if (!root._isYoutubeChannelRootUrl)
            return raw
        if (scope === "all")
            return raw

        var cut = raw.search(/[?#]/)
        var suffix = ""
        var base = raw
        if (cut >= 0) {
            base = raw.slice(0, cut)
            suffix = raw.slice(cut)
        }

        if (base.endsWith("/"))
            base = base.slice(0, -1)
        base = base.replace(/\/(videos|shorts|live|streams)$/i, "")

        var tab = scope === "shorts" ? "shorts" : (scope === "live" ? "streams" : "videos")
        return base + "/" + tab + suffix
    }

    function _formatSize(bytes) {
        if (!bytes || bytes <= 0) return ""
        if (bytes >= 1073741824) return (bytes / 1073741824).toFixed(1) + " GiB"
        if (bytes >= 1048576)    return (bytes / 1048576).toFixed(1) + " MiB"
        if (bytes >= 1024)       return (bytes / 1024).toFixed(0) + " KiB"
        return bytes + " B"
    }

    // Map a raw vcodec string from yt-dlp to a short human-readable codec name.
    // yt-dlp returns strings like "vp09.00.40.08", "avc1.640028", "av01.0.08M.08".
    function _codecLabel(vcodec) {
        if (!vcodec || vcodec === "none") return ""
        var v = vcodec.toLowerCase()
        if (v.indexOf("av01") >= 0 || v.indexOf("av1") >= 0)  return "AV1"
        if (v.indexOf("vp09") >= 0 || v.indexOf("vp9") >= 0)  return "VP9"
        if (v.indexOf("vp08") >= 0 || v.indexOf("vp8") >= 0)  return "VP8"
        if (v.indexOf("avc") >= 0  || v.indexOf("h264") >= 0) return "H.264"
        if (v.indexOf("hvc") >= 0  || v.indexOf("hevc") >= 0 || v.indexOf("h265") >= 0) return "H.265"
        if (v.indexOf("theora") >= 0) return "Theora"
        // Unknown codec — return a trimmed prefix (before first dot/space)
        var dot = v.indexOf(".")
        return dot > 0 ? vcodec.substring(0, dot).toUpperCase() : vcodec.toUpperCase()
    }

    // Map acodec to a short label.
    function _acodecLabel(acodec) {
        if (!acodec || acodec === "none") return ""
        var a = acodec.toLowerCase()
        if (a.indexOf("opus") >= 0)  return "Opus"
        if (a.indexOf("mp4a") >= 0 || a.indexOf("aac") >= 0) return "AAC"
        if (a.indexOf("mp3")  >= 0)  return "MP3"
        if (a.indexOf("vorbis") >= 0) return "Vorbis"
        if (a.indexOf("flac") >= 0)  return "FLAC"
        var dot = a.indexOf(".")
        return dot > 0 ? acodec.substring(0, dot).toUpperCase() : acodec.toUpperCase()
    }

    // ── Category helpers ──────────────────────────────────────────────────────
    function _categoryIds() {
        var ids = []
        for (var i = 0; i < App.categoryModel.rowCount(); i++)
            ids.push(App.categoryModel.categoryData(i).id)
        return ids
    }
    function _categoryLabels() {
        var labels = []
        for (var i = 0; i < App.categoryModel.rowCount(); i++)
            labels.push(App.categoryModel.categoryData(i).label)
        return labels
    }
    property var categoryIds:    _categoryIds()
    property var categoryLabels: _categoryLabels()
    Connections {
        target: App.categoryModel
        function onCategoriesChanged() {
            root.categoryIds    = root._categoryIds()
            root.categoryLabels = root._categoryLabels()
        }
    }
    function _catIndexForVideo() {
        for (var i = 0; i < categoryIds.length; i++) {
            var lbl = (categoryLabels[i] || "").toLowerCase()
            if (lbl === "video" || lbl === "videos") return i
        }
        return 0
    }
    function _savePathForCatIndex(idx) {
        return App.categoryModel.savePathForCategory(categoryIds[idx] || "all")
    }

    // ── yt-dlp response listener ──────────────────────────────────────────────
    Connections {
        target: App
        function onYtdlpInfoReady(probeId, url, title, formats) {
            if (probeId !== root._probeId) return
            root._probing    = false
            root._title      = title
            root._formats    = formats
            root._probeError = ""
            formatList.currentIndex = 0
            var catIdx = root._catIndexForVideo()
            catCombo.currentIndex = catIdx
            root._updateSavePath(catIdx)
        }
        function onYtdlpInfoFailed(probeId, url, reason) {
            if (probeId !== root._probeId) return
            root._probing    = false
            root._probeError = reason
        }
    }

    function _updateSavePath(catIdx) {
        var dir = _savePathForCatIndex(catIdx)
        if (!dir || dir.length === 0)
            dir = App.settings.defaultSavePath
        dir = dir.replace(/\//g, "\\")
        if (dir.length > 0 && !dir.endsWith("\\")) dir += "\\"
        savePathField.text = dir
    }

    FolderDialog {
        id: saveFolderDialog
        currentFolder: savePathField.text.trim().length > 0
                       ? ("file:///" + savePathField.text.trim().replace(/\\/g, "/"))
                       : ("file:///" + App.settings.defaultSavePath.replace(/\\/g, "/"))
        onAccepted: {
            var path = selectedFolder.toString()
                .replace(/^file:\/\/\//, "")
                .replace(/^file:\/\//, "")
            path = path.replace(/\//g, "\\")
            if (path.length > 0 && !path.endsWith("\\"))
                path += "\\"
            savePathField.text = path
        }
    }

    // ── UI ────────────────────────────────────────────────────────────────────
    ColumnLayout {
        anchors.fill:    parent
        anchors.margins: 0
        spacing:         0

        // ── Header ─────────────────────────────────────────────────────────────
        Rectangle {
            Layout.fillWidth: true
            height: 68
            color:  "#222228"

            RowLayout {
                anchors {
                    fill:        parent
                    leftMargin:  20; rightMargin: 20
                    topMargin:   12; bottomMargin: 12
                }
                spacing: 14

                Item {
                    width: 44
                    height: 44

                    Image {
                        anchors.centerIn: parent
                        source: "qrc:/qt/qml/com/stellar/app/app/qml/icons/wand.ico"
                        width: 28
                        height: 28
                        fillMode: Image.PreserveAspectFit
                        smooth: true
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 3

                    Text {
                        Layout.fillWidth: true
                        text: root._title.length > 0
                              ? root._title
                              : (root._probing
                                 ? "Fetching video info\u2026"
                                 : (root._probeError.length > 0 ? "Could not fetch video info" : "Video Download"))
                        color: "#e8e8e8"
                        font.pixelSize: 13
                        font.weight: Font.Medium
                        elide: Text.ElideRight
                    }
                    Text {
                        Layout.fillWidth: true
                        text: root.pendingUrl
                        color: "#5a7aaa"
                        font.pixelSize: 11
                        elide: Text.ElideMiddle
                    }
                }
            }
        }

        // ── Body ───────────────────────────────────────────────────────────────
        Item {
            Layout.fillWidth:  true
            Layout.fillHeight: true

            // ── Loading state ─────────────────────────────────────────────────
            ColumnLayout {
                anchors.centerIn: parent
                spacing: 16
                visible: root._probing

                BusyIndicator {
                    Layout.alignment: Qt.AlignHCenter
                    running: root._probing
                    width: 48; height: 48
                }
                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: "Fetching available formats\u2026"
                    color: "#aaaaaa"
                    font.pixelSize: 13
                }
                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: root.pendingUrl
                    color: "#555577"
                    font.pixelSize: 11
                    elide: Text.ElideMiddle
                    Layout.maximumWidth: 440
                }
            }

            // ── Error state ───────────────────────────────────────────────────
            ColumnLayout {
                anchors.centerIn: parent
                spacing: 12
                visible: !root._probing && root._probeError.length > 0

                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: "\u26A0"
                    font.pixelSize: 36
                    color: "#cc4444"
                }
                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: "Could not fetch video information"
                    color: "#e0e0e0"
                    font.pixelSize: 13
                    font.weight: Font.Medium
                }
                Text {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.maximumWidth: 480
                    text: root._probeError
                    color: "#aaaaaa"
                    font.pixelSize: 11
                    wrapMode: Text.Wrap
                    horizontalAlignment: Text.AlignHCenter
                }
                DlgButton {
                    Layout.alignment: Qt.AlignHCenter
                    text: "Retry"
                    onClicked: root._startProbe()
                }
            }

            // ── Format picker ─────────────────────────────────────────────────
            ColumnLayout {
                anchors {
                    fill:    parent
                    margins: 18
                }
                spacing: 10
                visible: !root._probing && root._probeError.length === 0 && root._formats.length > 0

                // Quality list label
                Text {
                    text: "Select quality:"
                    color: "#aaaaaa"
                    font.pixelSize: 12
                }

                // Format list
                Rectangle {
                    Layout.fillWidth:  true
                    Layout.fillHeight: true
                    color:  "#181818"
                    border.color: "#3a3a3a"
                    radius: 4
                    clip: true

                    ListView {
                        id: formatList
                        anchors {
                            fill:    parent
                            margins: 1
                        }
                        model:          root._formats
                        currentIndex:   0
                        clip:           true
                        boundsBehavior: Flickable.StopAtBounds

                        ScrollBar.vertical: ScrollBar {
                            policy: ScrollBar.AsNeeded
                        }

                        delegate: Rectangle {
                            id: fmtDelegate
                            width:  formatList.width
                            height: 34

                            readonly property bool isSelected: formatList.currentIndex === index
                            readonly property bool isHovered:  fmtMouse.containsMouse

                            color: isSelected ? "#1a3a6a"
                                              : (isHovered ? "#232333" : "transparent")

                            // Left accent bar when selected
                            Rectangle {
                                width: 3; height: parent.height
                                color: "#4488dd"
                                visible: fmtDelegate.isSelected
                            }

                            RowLayout {
                                anchors {
                                    fill:        parent
                                    leftMargin:  14
                                    rightMargin: 12
                                }
                                spacing: 8

                                // Quality label ("Best quality", "2160p", "1080p", "Audio only", …)
                                Text {
                                    text: modelData.label || ""
                                    color: fmtDelegate.isSelected ? "#c0d8ff" : "#d0d0d0"
                                    font.pixelSize: 13
                                    font.weight: fmtDelegate.isSelected ? Font.Medium : Font.Normal
                                    Layout.minimumWidth: 80
                                }

                                // Video codec badge — shown when we know the codec and it's a video format
                                Rectangle {
                                    property string _codec: root._codecLabel(modelData.vcodec || "")
                                    visible: _codec.length > 0 && modelData.id !== "best"
                                             && modelData.id !== "bestvideo+bestaudio/best"
                                    width:  codecText.implicitWidth + 10
                                    height: 17
                                    radius: 3
                                    color: {
                                        switch(_codec) {
                                        case "AV1":   return "#1a2020"
                                        case "VP9":   return "#1e1a20"
                                        case "H.264": return "#1a2030"
                                        case "H.265": return "#201a1a"
                                        default:      return "#1e1e1e"
                                        }
                                    }
                                    border.color: {
                                        switch(_codec) {
                                        case "AV1":   return "#2a5040"
                                        case "VP9":   return "#3a2a50"
                                        case "H.264": return "#2a4060"
                                        case "H.265": return "#502a2a"
                                        default:      return "#3a3a3a"
                                        }
                                    }
                                    Text {
                                        id: codecText
                                        anchors.centerIn: parent
                                        text: parent._codec
                                        color: {
                                            switch(parent._codec) {
                                            case "AV1":   return "#5abba0"
                                            case "VP9":   return "#9a70cc"
                                            case "H.264": return "#6a9acc"
                                            case "H.265": return "#cc7a7a"
                                            default:      return "#aaaaaa"
                                            }
                                        }
                                        font.pixelSize: 10
                                    }
                                }

                                // Audio codec badge — shown for audio-only formats
                                Rectangle {
                                    property string _acodec: root._acodecLabel(modelData.acodec || "")
                                    // Show for audio-only rows (height === 0) when we know the codec
                                    visible: _acodec.length > 0
                                             && (modelData.height === 0 || !modelData.vcodec || modelData.vcodec === "none")
                                             && modelData.id !== "best"
                                    width:  acodecText.implicitWidth + 10
                                    height: 17
                                    radius: 3
                                    color: "#1a1e20"
                                    border.color: "#2a4040"
                                    Text {
                                        id: acodecText
                                        anchors.centerIn: parent
                                        text: parent._acodec
                                        color: "#5a9aaa"
                                        font.pixelSize: 10
                                    }
                                }

                                // FPS badge — only for high-framerate (not 30/null)
                                Rectangle {
                                    property int _fps: modelData.fps || 0
                                    visible: _fps > 0 && _fps !== 30 && (modelData.height || 0) > 0
                                    width:  fpsText.implicitWidth + 10
                                    height: 17
                                    radius: 3
                                    color: "#1e1e2a"
                                    border.color: "#2a2a50"
                                    Text {
                                        id: fpsText
                                        anchors.centerIn: parent
                                        text: parent._fps + " fps"
                                        color: "#8888cc"
                                        font.pixelSize: 10
                                    }
                                }

                                Item { Layout.fillWidth: true }

                                // File size — right-aligned, only when known
                                Text {
                                    text: root._formatSize(modelData.filesize)
                                    color: fmtDelegate.isSelected ? "#8aaddd" : "#6a8aaa"
                                    font.pixelSize: 12
                                    visible: (modelData.filesize || 0) > 0
                                }
                            }

                            MouseArea {
                                id: fmtMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                onClicked: formatList.currentIndex = index
                            }
                        }
                    }
                }

                // ── Channel / playlist options ─────────────────────────────────
                // Shown whenever the URL looks like a channel or playlist.
                Rectangle {
                    Layout.fillWidth: true
                    visible: root._isChannelUrl
                    height: channelRow.implicitHeight + 20
                    radius: 3
                    color:  "#1a2030"
                    border.color: "#2a3a5a"

                    ColumnLayout {
                        id: channelRow
                        anchors { fill: parent; margins: 10 }
                        spacing: 8

                        // Header row
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            Text {
                                text: "Channel / Playlist"
                                color: "#8899bb"
                                font.pixelSize: 11
                                font.weight: Font.Medium
                            }

                            Item { Layout.fillWidth: true }

                            // "All videos" vs "Latest N" toggle
                            RowLayout {
                                spacing: 4

                                RadioButton {
                                    id: allVideosRadio
                                    checked: true
                                    text: "All videos"
                                    font.pixelSize: 11
                                    palette.windowText: "#c0c0c0"
                                    topPadding: 0
                                    bottomPadding: 0
                                    padding: 0
                                    leftPadding: 0
                                    Layout.alignment: Qt.AlignVCenter
                                    indicator: Rectangle {
                                        implicitWidth: 14; implicitHeight: 14
                                        radius: 7
                                        color: allVideosRadio.checked ? "#1a3a6a" : "#1b1b1b"
                                        border.color: allVideosRadio.checked ? "#4488dd" : "#555555"
                                        Rectangle {
                                            width: 6; height: 6; radius: 3
                                            anchors.centerIn: parent
                                            color: "#4488dd"
                                            visible: allVideosRadio.checked
                                        }
                                    }
                                    contentItem: Text {
                                        leftPadding: allVideosRadio.indicator.width + 6
                                        text: allVideosRadio.text
                                        color: "#c0c0c0"
                                        font: allVideosRadio.font
                                        verticalAlignment: Text.AlignVCenter
                                    }
                                }

                                RadioButton {
                                    id: latestNRadio
                                    text: "Latest"
                                    font.pixelSize: 11
                                    palette.windowText: "#c0c0c0"
                                    topPadding: 0
                                    bottomPadding: 0
                                    padding: 0
                                    leftPadding: 8
                                    Layout.alignment: Qt.AlignVCenter
                                    indicator: Rectangle {
                                        implicitWidth: 14; implicitHeight: 14
                                        radius: 7
                                        color: latestNRadio.checked ? "#1a3a6a" : "#1b1b1b"
                                        border.color: latestNRadio.checked ? "#4488dd" : "#555555"
                                        Rectangle {
                                            width: 6; height: 6; radius: 3
                                            anchors.centerIn: parent
                                            color: "#4488dd"
                                            visible: latestNRadio.checked
                                        }
                                    }
                                    contentItem: Text {
                                        leftPadding: latestNRadio.indicator.width + 6
                                        text: latestNRadio.text
                                        color: "#c0c0c0"
                                        font: latestNRadio.font
                                        verticalAlignment: Text.AlignVCenter
                                    }
                                }

                                // N spinner — active only when "Latest N" is chosen
                                Rectangle {
                                    width: 52; height: 22
                                    radius: 3
                                    color: "#1b1b1b"
                                    Layout.alignment: Qt.AlignVCenter
                                    border.color: latestNField.activeFocus ? "#4488dd"
                                                                           : (latestNRadio.checked ? "#3a3a5a" : "#2a2a2a")
                                    opacity: latestNRadio.checked ? 1.0 : 0.4

                                    TextInput {
                                        id: latestNField
                                        anchors { fill: parent; leftMargin: 6; rightMargin: 6 }
                                        text: "10"
                                        color: "#d0d0d0"
                                        font.pixelSize: 12
                                        verticalAlignment: Text.AlignVCenter
                                        inputMethodHints: Qt.ImhDigitsOnly
                                        validator: IntValidator { bottom: 1; top: 9999 }
                                        enabled: latestNRadio.checked
                                        selectByMouse: true
                                        onActiveFocusChanged: if (activeFocus) selectAll()
                                    }
                                }

                                Text {
                                    text: "videos"
                                    color: latestNRadio.checked ? "#8899bb" : "#444455"
                                    font.pixelSize: 11
                                    Layout.alignment: Qt.AlignVCenter
                                }
                            }
                        }

                        // Info note
                        Text {
                            Layout.fillWidth: true
                            text: root._isYoutubeChannelRootUrl
                                  ? "YouTube channel URLs include all uploads by default (videos, shorts, and live). Use Scope to target one tab."
                                  : "Videos will be saved in a subfolder named after the channel."
                            color: "#5a6a8a"
                            font.pixelSize: 10
                            wrapMode: Text.WordWrap
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            visible: root._isYoutubeChannelRootUrl
                            radius: 3
                            color: "#162236"
                            border.color: "#28456f"
                            height: scopeRow.implicitHeight + 14

                            RowLayout {
                                id: scopeRow
                                anchors { fill: parent; margins: 7 }
                                spacing: 8

                                Text {
                                    text: "Scope:"
                                    color: "#89a6d4"
                                    font.pixelSize: 11
                                    font.weight: Font.Medium
                                }

                                ButtonGroup { id: scopeGroup }

                                RadioButton {
                                    id: scopeAll
                                    checked: true
                                    text: "All uploads"
                                    ButtonGroup.group: scopeGroup
                                    topPadding: 0
                                    bottomPadding: 0
                                    padding: 0
                                    Layout.alignment: Qt.AlignVCenter
                                }
                                RadioButton {
                                    id: scopeVideos
                                    text: "Videos tab"
                                    ButtonGroup.group: scopeGroup
                                    topPadding: 0
                                    bottomPadding: 0
                                    padding: 0
                                    Layout.alignment: Qt.AlignVCenter
                                }
                                RadioButton {
                                    id: scopeShorts
                                    text: "Shorts tab"
                                    ButtonGroup.group: scopeGroup
                                    topPadding: 0
                                    bottomPadding: 0
                                    padding: 0
                                    Layout.alignment: Qt.AlignVCenter
                                }
                                RadioButton {
                                    id: scopeLive
                                    text: "Live tab"
                                    ButtonGroup.group: scopeGroup
                                    topPadding: 0
                                    bottomPadding: 0
                                    padding: 0
                                    Layout.alignment: Qt.AlignVCenter
                                }
                            }
                        }
                    }
                }

                // ── ffmpeg warning ────────────────────────────────────────────
                Rectangle {
                    Layout.fillWidth: true
                    height: ffmpegWarnText.implicitHeight + 12
                    radius: 3
                    color: "#2a1a0a"
                    border.color: "#6a3a0a"
                    visible: {
                        var needsMerge = containerCombo.currentText !== "webm"
                        return needsMerge && !App.ytdlpManager.ffmpegAvailable
                    }

                    Text {
                        id: ffmpegWarnText
                        anchors { fill: parent; margins: 6 }
                        text: "\u26A0  ffmpeg is not installed - this download will fall back to a pre-muxed stream (usually WebM <=480p). " +
                              "Drop ffmpeg.exe next to yt-dlp.exe for HD MP4/MKV. See Settings > Video Downloader."
                        color: "#ddaa55"; font.pixelSize: 11
                        wrapMode: Text.WordWrap
                    }
                }

                // ── Save location ─────────────────────────────────────────────
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Text {
                        text: "Save to:"
                        color: "#aaaaaa"
                        font.pixelSize: 12
                        Layout.minimumWidth: 62
                    }

                    TextField {
                        id: savePathField
                        Layout.fillWidth: true
                        font.pixelSize:   12
                        color:            "#d0d0d0"
                        leftPadding:      8
                        rightPadding:     8
                        placeholderText:  "Save directory\u2026"
                        placeholderTextColor: "#555555"
                        background: Rectangle {
                            color:        "#1b1b1b"
                            border.color: savePathField.activeFocus ? "#4488dd" : "#3a3a3a"
                            radius:       3
                        }
                    }

                    DlgButton {
                        text: "Save As..."
                        onClicked: saveFolderDialog.open()
                    }
                }

                // ── Category ──────────────────────────────────────────────────
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Text {
                        text: "Category:"
                        color: "#aaaaaa"
                        font.pixelSize: 12
                        Layout.minimumWidth: 62
                    }

                    ComboBox {
                        id: catCombo
                        Layout.fillWidth: true
                        font.pixelSize:   12
                        model:            root.categoryLabels

                        contentItem: Text {
                            leftPadding:  8
                            text:         catCombo.displayText
                            color:        "#d0d0d0"
                            font:         catCombo.font
                            verticalAlignment: Text.AlignVCenter
                        }
                        background: Rectangle {
                            color:        "#1b1b1b"
                            border.color: catCombo.activeFocus ? "#4488dd" : "#3a3a3a"
                            radius:       3
                        }
                        delegate: ItemDelegate {
                            width:  catCombo.width
                            height: 28
                            contentItem: Text {
                                text:  modelData
                                color: "#d0d0d0"
                                font.pixelSize: 12
                                verticalAlignment: Text.AlignVCenter
                                leftPadding: 8
                            }
                            background: Rectangle {
                                color: hovered ? "#2a3a5a" : "#1b1b1b"
                            }
                        }
                        popup: Popup {
                            y:      catCombo.height + 2
                            width:  catCombo.width
                            implicitHeight: contentItem.implicitHeight + 4
                            padding: 2
                            background: Rectangle { color: "#1b1b1b"; border.color: "#3a3a3a"; radius: 3 }
                            contentItem: ListView {
                                implicitHeight: contentHeight
                                clip:           true
                                model:          catCombo.delegateModel
                                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                            }
                        }

                        onCurrentIndexChanged: root._updateSavePath(currentIndex)
                    }
                }

                // ── Container / output format ─────────────────────────────────
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Text {
                        text: "Format:"
                        color: "#aaaaaa"
                        font.pixelSize: 12
                        Layout.minimumWidth: 62
                    }

                    ComboBox {
                        id: containerCombo
                        implicitWidth: 110
                        font.pixelSize: 12

                        property bool _isAudioOnly: {
                            var fmt = root._formats[formatList.currentIndex]
                            return fmt ? (fmt.height === 0) : false
                        }
                        on_IsAudioOnlyChanged: currentIndex = 0
                        model: _isAudioOnly
                               ? ["mp3", "m4a", "opus", "flac", "wav", "aac"]
                               : ["mp4", "mkv", "webm", "mov"]
                        currentIndex: 0

                        contentItem: Text {
                            leftPadding:  8
                            text:         containerCombo.displayText
                            color:        "#d0d0d0"
                            font:         containerCombo.font
                            verticalAlignment: Text.AlignVCenter
                        }
                        background: Rectangle {
                            color:        "#1b1b1b"
                            border.color: containerCombo.activeFocus ? "#4488dd" : "#3a3a3a"
                            radius:       3
                        }
                        delegate: ItemDelegate {
                            width:  containerCombo.width
                            height: 26
                            contentItem: Text {
                                text:  modelData
                                color: "#d0d0d0"
                                font.pixelSize: 12
                                verticalAlignment: Text.AlignVCenter
                                leftPadding: 8
                            }
                            background: Rectangle { color: hovered ? "#2a3a5a" : "#1b1b1b" }
                        }
                        popup: Popup {
                            y: containerCombo.height + 2
                            width: containerCombo.width
                            implicitHeight: contentItem.implicitHeight + 4
                            padding: 2
                            background: Rectangle { color: "#1b1b1b"; border.color: "#3a3a3a"; radius: 3 }
                            contentItem: ListView {
                                implicitHeight: contentHeight
                                clip: true
                                model: containerCombo.delegateModel
                            }
                        }
                    }
                }
            }
        }

        // ── Divider ────────────────────────────────────────────────────────────
        Rectangle {
            Layout.fillWidth: true
            height: 1
            color:  "#2e2e2e"
        }

        // ── Button row ─────────────────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth:    true
            Layout.topMargin:    12
            Layout.bottomMargin: 14
            Layout.leftMargin:   18
            Layout.rightMargin:  18
            spacing: 8

            Item { Layout.fillWidth: true }

            DlgButton {
                text: "Cancel"
                onClicked: root.close()
            }

            DlgButton {
                text:    root._isChannelUrl ? "Download Channel" : "Download"
                primary: true
                enabled: !root._probing
                         && root._probeError.length === 0
                         && root._formats.length > 0
                         && savePathField.text.trim().length > 0

                onClicked: {
                    root._accepted = true
                    var fmt = root._formats[formatList.currentIndex]
                    var formatId  = fmt ? (fmt.id || "bestvideo+bestaudio/best") : "bestvideo+bestaudio/best"
                    var container = containerCombo.currentText || "mp4"
                    var savePath  = savePathField.text.trim()
                    while (savePath.endsWith("/") || savePath.endsWith("\\"))
                        savePath = savePath.slice(0, -1)
                    var catId = root.categoryIds[catCombo.currentIndex] || ""
                    var isPlaylist = root._isChannelUrl
                    var nItems = (isPlaylist && latestNRadio.checked)
                                 ? (parseInt(latestNField.text) || 10) : 0
                    var scope = "all"
                    if (root._isYoutubeChannelRootUrl) {
                        if (scopeVideos.checked) scope = "videos"
                        else if (scopeShorts.checked) scope = "shorts"
                        else if (scopeLive.checked) scope = "live"
                    }
                    var effectiveUrl = root._channelScopedUrl(scope)
                    root.downloadRequested(effectiveUrl, formatId, container,
                                           savePath, catId, root.uniqueFilename,
                                           root._title, isPlaylist, nItems)
                    root.close()
                }
            }
        }
    }
}
