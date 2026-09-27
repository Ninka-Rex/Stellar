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
import QtQuick.Layouts
import Qt.labs.platform

// Where a yt-dlp download goes and in what file format: Format, Category and
// Save-to rows for a SettingsSection (they share its label column), shared by
// the single-video and channel dialogs.
//
// The save folder follows the category (plus `subfolder`, e.g. the channel's
// name) until the user types or browses a folder of their own.
ColumnLayout {
    id: fields

    // Picks the audio formats instead of the video containers.
    property bool audioOnly: false
    // Appended to the category's folder (a single, already sanitised name).
    property string subfolder: ""

    readonly property string container: (audioOnly ? _audioFormats : _videoFormats)[_formatIndex] || ""
    readonly property string categoryId: _categoryIds[_categoryIndex] || ""
    readonly property string savePath: _stripTrailingSeparators(_savePath.trim())

    readonly property var _videoFormats: ["mp4", "mkv", "webm", "mov"]
    readonly property var _audioFormats: ["mp3", "m4a", "opus", "flac", "wav", "aac"]
    readonly property string _sep: Qt.platform.os === "windows" ? "\\" : "/"

    property int _formatIndex: 0
    property int _categoryIndex: 0
    property string _savePath: ""
    property bool _pathEdited: false
    property var _categoryIds: []
    property var _categoryLabels: []

    Layout.fillWidth: true
    spacing: 8

    onAudioOnlyChanged: _formatIndex = 0
    onSubfolderChanged: _followCategory()

    // Back to the defaults: first container, the Video category (when there is
    // one) and its folder.
    function reset() {
        _loadCategories()
        _formatIndex = 0
        _categoryIndex = 0
        for (var i = 0; i < _categoryLabels.length; ++i) {
            var l = (_categoryLabels[i] || "").toLowerCase()
            if (l === "video" || l === "videos") { _categoryIndex = i; break }
        }
        _pathEdited = false
        _followCategory()
    }

    function _loadCategories() {
        var ids = [], labels = []
        for (var i = 0; i < App.categoryModel.rowCount(); ++i) {
            var c = App.categoryModel.categoryData(i)
            ids.push(c.id)
            labels.push(c.label)
        }
        _categoryIds = ids
        _categoryLabels = labels
    }

    function _stripTrailingSeparators(p) {
        while (p.length > 1 && (p.endsWith("/") || p.endsWith("\\")) && !/^[A-Za-z]:[\\/]$/.test(p))
            p = p.slice(0, -1)
        return p
    }

    function _followCategory() {
        if (_pathEdited)
            return
        var base = App.categoryModel.savePathForCategory(_categoryIds[_categoryIndex] || "all")
        if (!base || base.length === 0)
            base = App.settings.defaultSavePath
        base = _stripTrailingSeparators(String(base))
        if (Qt.platform.os === "windows")
            base = base.replace(/\//g, "\\")
        _savePath = subfolder.length > 0 ? base + _sep + subfolder : base
    }

    function _fileUrlFromPath(path) {
        var p = String(path || "").trim().replace(/\\/g, "/")
        if (p.length === 0)
            return ""
        return p.startsWith("/") ? "file://" + p : "file:///" + p
    }

    Connections {
        target: App.categoryModel
        function onCategoriesChanged() {
            var keep = fields.categoryId
            fields._loadCategories()
            fields._categoryIndex = Math.max(0, fields._categoryIds.indexOf(keep))
        }
    }

    FolderDialog {
        id: folderDialog
        onAccepted: {
            var p = String(folder)
            p = Qt.platform.os === "windows" ? p.replace(/^file:\/\/\//, "").replace(/\//g, "\\")
                                              : p.replace(/^file:\/\//, "")
            fields._pathEdited = true
            fields._savePath = p
        }
    }

    SettingsRow {
        label: qsTr("Format")
        SettingsCombo {
            Layout.maximumWidth: 120
            model: fields.audioOnly ? fields._audioFormats : fields._videoFormats
            value: fields._formatIndex
            onEdited: (i) => fields._formatIndex = i
        }
    }

    SettingsRow {
        label: qsTr("Category")
        SettingsCombo {
            model: fields._categoryLabels
            value: fields._categoryIndex
            onEdited: (i) => {
                fields._categoryIndex = i
                fields._followCategory()
            }
        }
    }

    SettingsRow {
        label: qsTr("Save to")
        stacked: true
        SettingsPathField {
            value: fields._savePath
            onEdited: (t) => {
                fields._pathEdited = true
                fields._savePath = t
            }
            onBrowse: {
                folderDialog.currentFolder = fields._fileUrlFromPath(fields.savePath)
                folderDialog.open()
            }
        }
    }

    SettingsNote {
        visible: !App.ytdlpManager.ffmpegAvailable && fields.container !== "webm"
        warning: true
        text: qsTr("ffmpeg was not found, so yt-dlp can only download a single pre-merged stream, usually 480p or lower, and cannot convert formats. Place ffmpeg next to yt-dlp for full quality (Settings › Media).")
    }
}
