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
import QtQuick.Layouts

// Download one video with yt-dlp: probes the link for its title and
// qualities, then lets the user pick quality, format, folder and options.
// Channels and playlists go to YtdlpChannelDialog instead.
YtdlpDialogFrame {
    id: root

    property string pendingUrl: ""
    // Set when the user picked "Overwrite" in the duplicate dialog: the backend
    // then keeps the existing file name and lets yt-dlp overwrite the file.
    property bool overwriteExisting: false

    signal openSettingsRequested(int page)
    // The link resolved to a plain file yt-dlp cannot handle (e.g. a reddit gif
    // post); Main.qml hands it to the regular download flow.
    signal directDownloadRequested(string directUrl)
    // The user chose to pick videos from the playlist this video belongs to.
    signal playlistRequested(string playlistUrl)
    signal downloadRequested(string url, string formatId, string containerFormat,
                             string savePath, string category, string videoTitle,
                             var extraOptions, bool overwriteExisting)

    width: 560
    height: 480
    minimumWidth: 460
    minimumHeight: 400
    title: qsTr("Video Download")
    heading: _title.length > 0 ? _title
             : _probing ? qsTr("Reading video information…") : pendingUrl
    subheading: _title.length > 0 || _probing ? pendingUrl : ""
    primaryText: qsTr("Download")
    primaryEnabled: _ready && output.savePath.length > 0

    property string _probeId: ""
    property string _title: ""
    property var    _formats: []
    property int    _formatIndex: 0
    property bool   _probing: false
    property string _probeError: ""
    readonly property bool _ready: !_probing && _probeError.length === 0 && _formats.length > 0
    readonly property var _format: _formats[_formatIndex] || null
    readonly property string _playlistUrl: App.ytdlpPlaylistUrlFor(pendingUrl)

    YtdlpOptions { id: ytdlpOptions }

    onVisibleChanged: {
        if (visible) {
            ytdlpOptions.reset()
            output.reset()
            tabs.currentIndex = 0
            if (pendingUrl.length > 0)
                _startProbe()
        } else {
            // A probe nobody listens to would keep running (or start later,
            // after the cold-start availability check).
            if (_probeId.length > 0)
                App.cancelYtdlpInfo(_probeId)
            _probeId = ""; _title = ""; _formats = []; _formatIndex = 0
            _probing = false; _probeError = ""
            pendingUrl = ""; overwriteExisting = false
        }
    }
    onPendingUrlChanged: if (visible && pendingUrl.length > 0) _startProbe()

    onAccepted: {
        var formatId = _format && _format.id ? String(_format.id) : ""
        downloadRequested(pendingUrl, formatId, output.container, output.savePath, output.categoryId,
                          _title, ytdlpOptions.buildExtraOptions(output.container, true), overwriteExisting)
        close()
    }

    function _startProbe() {
        if (_probeId.length > 0)
            App.cancelYtdlpInfo(_probeId)
        _title = ""; _formats = []; _formatIndex = 0; _probeError = ""
        _probing = true
        _probeId = App.beginYtdlpInfo(pendingUrl, ytdlpOptions.cookiesBrowser)
    }

    function _formatSize(bytes) {
        if (!bytes || bytes <= 0) return ""
        if (bytes >= 1073741824) return (bytes / 1073741824).toFixed(1) + " GiB"
        if (bytes >= 1048576)    return (bytes / 1048576).toFixed(1) + " MiB"
        return Math.max(1, Math.round(bytes / 1024)) + " KiB"
    }

    function _videoCodec(v) {
        var s = (v || "").toLowerCase()
        if (!s || s === "none") return ""
        if (s.indexOf("av01") >= 0 || s.indexOf("av1") >= 0) return "AV1"
        if (s.indexOf("vp09") >= 0 || s.indexOf("vp9") >= 0) return "VP9"
        if (s.indexOf("vp08") >= 0 || s.indexOf("vp8") >= 0) return "VP8"
        if (s.indexOf("avc") >= 0 || s.indexOf("h264") >= 0) return "H.264"
        if (s.indexOf("hvc") >= 0 || s.indexOf("hev") >= 0 || s.indexOf("h265") >= 0) return "H.265"
        var d = s.indexOf(".")
        return (d > 0 ? s.substring(0, d) : s).toUpperCase()
    }

    function _audioCodec(a) {
        var s = (a || "").toLowerCase()
        if (!s || s === "none") return ""
        if (s.indexOf("opus") >= 0) return "Opus"
        if (s.indexOf("mp4a") >= 0 || s.indexOf("aac") >= 0) return "AAC"
        if (s.indexOf("mp3") >= 0) return "MP3"
        if (s.indexOf("vorbis") >= 0) return "Vorbis"
        if (s.indexOf("flac") >= 0) return "FLAC"
        var d = s.indexOf(".")
        return (d > 0 ? s.substring(0, d) : s).toUpperCase()
    }

    // "VP9 · 60 fps · 212.4 MiB": what distinguishes one quality from another.
    function _formatDetail(f) {
        if (!f)
            return ""
        var parts = []
        var codec = f.audioOnly ? _audioCodec(f.acodec) : _videoCodec(f.vcodec)
        if (codec.length > 0) parts.push(codec)
        if (!f.audioOnly && (f.fps || 0) > 30) parts.push(qsTr("%1 fps").arg(f.fps))
        var size = _formatSize(f.filesize)
        if (size.length > 0) parts.push(size)
        return parts.join(" · ")
    }

    Connections {
        target: App
        function onYtdlpInfoReady(probeId, url, title, formats) {
            if (probeId !== root._probeId) return
            root._probing = false
            root._title = title
            // Some sites report no format list; the generic selectors still work.
            root._formats = formats && formats.length > 0 ? formats : App.ytdlpQualityPresets()
            root._formatIndex = 0
        }
        function onYtdlpInfoFailed(probeId, url, reason) {
            if (probeId !== root._probeId) return
            root._probing = false
            root._probeError = reason
        }
        function onYtdlpProbeDiverted(probeId, url, directUrl) {
            if (probeId !== root._probeId) return
            root._probing = false
            root.directDownloadRequested(directUrl)
            root.close()
        }
    }

    Item {
        anchors.fill: parent

        SettingsStatus {
            anchors.centerIn: parent
            width: Math.min(implicitWidth, parent.width - 32)
            visible: root._probing
            level: SettingsStatus.Level.Busy
            text: qsTr("Reading video information…")
        }

        YtdlpErrorPanel {
            anchors.fill: parent
            visible: !root._probing && root._probeError.length > 0
            options: ytdlpOptions
            title: qsTr("Could not read this video")
            message: root._probeError
            onRetry: root._startProbe()
            onOpenSettingsRequested: (page) => root.openSettingsRequested(page)
        }

        ColumnLayout {
            anchors.fill: parent
            visible: root._ready
            spacing: 0

            SettingsTabBar {
                id: tabs
                model: [qsTr("Download"), qsTr("Subtitles & extras"), qsTr("Advanced")]
            }

            StackLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                currentIndex: tabs.currentIndex

                SettingsScroll {
                    SettingsSection {
                        SettingsRow {
                            label: qsTr("Quality")
                            SettingsCombo {
                                id: qualityCombo
                                Layout.maximumWidth: 360
                                model: root._formats
                                textRole: "label"
                                value: root._formatIndex
                                onEdited: (i) => root._formatIndex = i

                                contentItem: RowLayout {
                                    spacing: 8
                                    Text {
                                        Layout.leftMargin: 8
                                        text: root._format ? root._format.label : ""
                                        color: ColorPalette.textPrimary
                                        font: qualityCombo.font
                                    }
                                    Text {
                                        Layout.fillWidth: true
                                        Layout.rightMargin: 22
                                        horizontalAlignment: Text.AlignRight
                                        text: root._formatDetail(root._format)
                                        color: ColorPalette.textMuted
                                        font.pixelSize: 11 * App.fontScale
                                        elide: Text.ElideRight
                                    }
                                }

                                delegate: ItemDelegate {
                                    id: qualityItem
                                    required property var modelData
                                    required property int index
                                    width: ListView.view ? ListView.view.width : qualityCombo.width
                                    height: 26
                                    padding: 0
                                    highlighted: qualityCombo.highlightedIndex === index

                                    contentItem: RowLayout {
                                        spacing: 8
                                        Text {
                                            Layout.leftMargin: 8
                                            text: qualityItem.modelData.label
                                            color: qualityCombo.currentIndex === qualityItem.index
                                                   ? ColorPalette.accent : ColorPalette.textPrimary
                                            font: qualityCombo.font
                                        }
                                        Text {
                                            Layout.fillWidth: true
                                            Layout.rightMargin: 8
                                            horizontalAlignment: Text.AlignRight
                                            text: root._formatDetail(qualityItem.modelData)
                                            color: ColorPalette.textMuted
                                            font.pixelSize: 11 * App.fontScale
                                            elide: Text.ElideRight
                                        }
                                    }
                                    background: Rectangle {
                                        color: qualityItem.highlighted ? ColorPalette.selectionBg : ColorPalette.inputBg
                                    }
                                }
                            }
                        }

                        YtdlpOutputFields {
                            id: output
                            audioOnly: root._format ? !!root._format.audioOnly : false
                        }
                    }

                    SettingsSection {
                        visible: root._playlistUrl.length > 0
                        title: qsTr("Playlist")

                        SettingsHint { text: qsTr("This video is part of a playlist.") }
                        SettingsLink {
                            text: qsTr("Choose videos from the playlist instead…")
                            onClicked: {
                                root.playlistRequested(root._playlistUrl)
                                root.close()
                            }
                        }
                    }
                }

                YtdlpExtrasPage {
                    options: ytdlpOptions
                    container: output.container
                }

                YtdlpAdvancedPage {
                    options: ytdlpOptions
                    singleVideo: true
                }
            }
        }
    }
}
