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

// YtdlpDialog — format picker shown when a yt-dlp-compatible URL is submitted.
//
// Flow:
//   1. Caller sets `pendingUrl` and calls show()/raise()/requestActivate().
//   2. Dialog runs App.beginYtdlpInfo(url) to probe available formats.
//   3. On success the format list is shown; user selects quality + save location.
//   4. User clicks "Download" → `downloadRequested(url, formatId, ...)` emitted.
//      No DownloadItem is created until the user confirms — the entry only appears
//      in the download list once App.finalizeYtdlpDownload() is called by the handler.
//   5. Closing without confirming just closes the dialog; nothing to clean up.
Window {
    id: root

    // ── Public API ────────────────────────────────────────────────────────────
    // Set these before showing the dialog.
    property string pendingUrl: ""  // URL being probed

    // Set to true when opened from a "Add Numbered" duplicate action so yt-dlp
    // appends _2/_3/etc. to the filename to avoid collisions.
    property bool uniqueFilename: false

    // Emitted when the user confirms the download.  `url` is the original URL;
    // no DownloadItem exists yet — the handler must call App.finalizeYtdlpDownload()
    // which creates it and adds it to the list.
    signal downloadRequested(string url, string formatId,
                             string containerFormat, string savePath, string category,
                             bool uniqueFilename, string videoTitle)

    // ── Window appearance ─────────────────────────────────────────────────────
    width:       660
    height:      560
    minimumWidth:  520
    minimumHeight: 440
    title:       "Video Download"
    color:       "#1e1e1e"
    modality:    Qt.ApplicationModal
    flags:       Qt.Dialog | Qt.WindowTitleHint | Qt.WindowCloseButtonHint

    Material.theme:      Material.Dark
    Material.background: "#1e1e1e"
    Material.accent:     "#4488dd"

    // ── Private state ─────────────────────────────────────────────────────────
    property string  _probeId:    ""        // active beginYtdlpInfo probe ID
    property string  _title:      ""        // video title from yt-dlp metadata
    property var     _formats:    []        // QVariantList of format maps
    property bool    _probing:    false     // true while --dump-json is running
    property string  _probeError: ""        // non-empty when probing failed
    property bool    _accepted:   false     // true after user clicks Download

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
        // Cancel any existing probe first
        if (_probeId.length > 0)
            App.cancelYtdlpInfo(_probeId)
        _probeId    = ""
        _title      = ""
        _formats    = []
        _probeError = ""
        _probing    = true
        _probeId    = App.beginYtdlpInfo(pendingUrl)
    }

    function _formatSize(bytes) {
        if (!bytes || bytes <= 0) return ""
        if (bytes >= 1073741824) return (bytes / 1073741824).toFixed(1) + " GiB"
        if (bytes >= 1048576)    return (bytes / 1048576).toFixed(1) + " MiB"
        if (bytes >= 1024)       return (bytes / 1024).toFixed(0) + " KiB"
        return bytes + " B"
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
        // Auto-select a "Video" category if one exists; fall back to index 0.
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
            // Pre-select "Best quality" (index 0)
            formatList.currentIndex = 0
            // Initialise save path from auto-selected category
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

                // Play icon badge
                Rectangle {
                    width: 44; height: 44
                    radius: 6
                    color: "#1a2a1a"
                    border.color: "#3a6a3a"

                    Text {
                        anchors.centerIn: parent
                        text: "▶"
                        font.pixelSize: 20
                        color: "#5aaa5a"
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
                                 ? "Fetching video info…"
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
                    text: "Fetching available formats…"
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
                    text: "⚠"
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
                spacing: 12
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

                        delegate: ItemDelegate {
                            width:          formatList.width
                            height:         32
                            highlighted:    formatList.currentIndex === index
                            padding:        0

                            background: Rectangle {
                                color: formatList.currentIndex === index
                                       ? "#1a3a6a"
                                       : (hovered ? "#252535" : "transparent")
                                Rectangle {
                                    // Left accent bar shown when selected
                                    width:  3; height: parent.height
                                    color:  "#4488dd"
                                    visible: formatList.currentIndex === index
                                }
                            }

                            contentItem: RowLayout {
                                anchors {
                                    fill:        parent
                                    leftMargin:  12
                                    rightMargin: 12
                                }
                                spacing: 8

                                // Quality label ("Best quality", "1080p", "720p", "Audio only", …)
                                Text {
                                    text: modelData.label || ""
                                    color: formatList.currentIndex === index ? "#c0d8ff" : "#d0d0d0"
                                    font.pixelSize: 13
                                    font.weight: formatList.currentIndex === index ? Font.Medium : Font.Normal
                                    Layout.minimumWidth: 90
                                }

                                // Codec / extension badge — only when known and not the "Best" catch-all
                                Rectangle {
                                    property string _ext: (modelData.ext || "").toLowerCase()
                                    visible: _ext.length > 0 && modelData.id !== "best"
                                             && modelData.id !== "bestvideo+bestaudio/best"
                                    width:  extText.implicitWidth + 10
                                    height: 16
                                    radius: 3
                                    color: "#1e2a1e"
                                    border.color: "#2a4a2a"
                                    Text {
                                        id: extText
                                        anchors.centerIn: parent
                                        text: parent._ext
                                        color: "#6aaa6a"
                                        font.pixelSize: 10
                                    }
                                }

                                // FPS badge — only for video and when meaningful (not 30/null)
                                Rectangle {
                                    property int _fps: modelData.fps || 0
                                    visible: _fps > 0 && _fps !== 30 && modelData.height > 0
                                    width:  fpsText.implicitWidth + 10
                                    height: 16
                                    radius: 3
                                    color: "#1e1e2e"
                                    border.color: "#2a2a4e"
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
                                    color: "#8899bb"
                                    font.pixelSize: 12
                                    visible: modelData.filesize > 0
                                }
                            }

                            onClicked: formatList.currentIndex = index
                        }
                    }
                }

                // ── ffmpeg warning ────────────────────────────────────────────
                // Shown when the user picks a merging format but ffmpeg is absent.
                Rectangle {
                    Layout.fillWidth: true
                    height: ffmpegWarnText.implicitHeight + 12
                    radius: 3
                    color: "#2a1a0a"
                    border.color: "#6a3a0a"
                    visible: {
                        var fmt = root._formats[formatList.currentIndex]
                        if (!fmt) return false
                        // Audio-only uses --extract-audio which also needs ffmpeg for re-encoding
                        // webm selects a native yt-dlp stream so no merge needed
                        var needsMerge = containerCombo.currentText !== "webm"
                        return needsMerge && !App.ytdlpManager.ffmpegAvailable
                    }

                    Text {
                        id: ffmpegWarnText
                        anchors { fill: parent; margins: 6 }
                        text: "⚠  ffmpeg is not installed — this download will fall back to a pre-muxed stream (usually WebM ≤480p). " +
                              "Drop ffmpeg.exe next to yt-dlp.exe for HD MP4/MKV. See Settings → Video Downloader."
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
                        placeholderText:  "Save directory…"
                        placeholderTextColor: "#555555"
                        background: Rectangle {
                            color:        "#1b1b1b"
                            border.color: savePathField.activeFocus ? "#4488dd" : "#3a3a3a"
                            radius:       3
                        }
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

                // ── Container / format ────────────────────────────────────────
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

                        // Dynamic list: audio containers when "Audio only" is selected,
                        // video containers otherwise.
                        property bool _isAudioOnly: {
                            var fmt = root._formats[formatList.currentIndex]
                            return fmt ? (fmt.height === 0) : false
                        }
                        // Reset to index 0 whenever the model switches between audio/video
                        // to prevent a stale index pointing to the wrong format.
                        on_IsAudioOnlyChanged: currentIndex = 0
                        model: _isAudioOnly
                               ? ["mp3", "m4a", "opus", "flac", "wav", "aac"]
                               : ["mp4", "mkv", "webm", "mov"]
                        currentIndex: 0  // mp4 / mp3 are the sane defaults

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

                    Text {
                        text: {
                            var fmt = root._formats[formatList.currentIndex]
                            if (!fmt) return ""
                            if (fmt.height === 0)
                                return ""
                            var c = containerCombo.currentText
                            if (c === "mp4" || c === "mkv")
                                return ""
                            if (c === "webm")
                                return ""
                            return ""
                        }
                        color: "#555577"
                        font.pixelSize: 11
                        Layout.fillWidth: true
                        wrapMode: Text.NoWrap
                        elide: Text.ElideRight
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
                text:    "Download"
                primary: true
                enabled: !root._probing
                         && root._probeError.length === 0
                         && root._formats.length > 0
                         && savePathField.text.trim().length > 0

                onClicked: {
                    root._accepted = true
                    var fmt = root._formats[formatList.currentIndex]
                    var formatId = fmt ? (fmt.id || "bestvideo+bestaudio/best") : "bestvideo+bestaudio/best"
                    var container = containerCombo.currentText || "mp4"
                    var savePath = savePathField.text.trim()
                    // Strip trailing path separator — yt-dlp receives the directory
                    while (savePath.endsWith("/") || savePath.endsWith("\\"))
                        savePath = savePath.slice(0, -1)
                    var catId = root.categoryIds[catCombo.currentIndex] || ""
                    root.downloadRequested(root.pendingUrl, formatId, container, savePath, catId, root.uniqueFilename, root._title)
                    root.close()
                }
            }
        }
    }
}
