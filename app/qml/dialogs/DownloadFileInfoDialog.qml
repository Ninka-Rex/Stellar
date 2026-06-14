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

Window {
    id: root

    property string pendingUrl:        ""
    property string pendingFilename:   ""
    property string pendingSize:       ""
    property string pendingSavePath:   ""
    property string filenameOverride:  ""
    property string pendingDownloadId: ""
    property string pendingCookies:    ""
    property string pendingReferrer:   ""
    property bool   isIntercepted:     false
    property bool   _accepted:         false
    property bool   _probing:          false

    width:  560
    height: mainCol.implicitHeight + 24
    minimumWidth: 480
    title: qsTr("Download File Info")
    color: ColorPalette.cardBg

    // Detach from the main window so each new-download dialog gets its own
    // taskbar button (IDM-style). Non-modal so it behaves as an independent
    // window the user can select/minimise separately. Owner set to null at the
    // instantiation site in Main.qml.
    flags: Qt.Window | Qt.WindowTitleHint | Qt.WindowCloseButtonHint
           | Qt.WindowMinimizeButtonHint | Qt.MSWindowsFixedSizeDialogHint

    Material.theme: ColorPalette.materialTheme
    Material.foreground: ColorPalette.textPrimary
    Material.background: ColorPalette.materialBg
    Material.accent: "#4488dd"

    signal downloadNow(string downloadId, string url, string savePath, string category, string description)
    signal downloadLater(string downloadId, string url, string savePath, string category, string description)
    signal rejected(string downloadId, string url)

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

    function fileUrlFromPath(path) {
        var p = String(path || "").trim().replace(/\\/g, "/")
        if (p.length === 0 || p.indexOf("file://") === 0) return p
        return Qt.platform.os === "windows"
            ? ("file:///" + p)
            : (p.startsWith("/") ? ("file://" + p) : ("file:///" + p))
    }

    function pathFromFileUrl(url) {
        var p = String(url || "")
        if (Qt.platform.os === "windows") return p.replace(/^file:\/\/\//, "")
        return p.replace(/^file:\/\//, "")
    }

    onVisibleChanged: {
        if (visible) {
            _centerOnOwner()
            raise()
            requestActivate()
            // Non-modal + detached owner: Windows can re-raise the main window
            // right after show(), pushing this behind it. Re-assert z-order once
            // the event loop settles.
            Qt.callLater(function() { root.raise(); root.requestActivate() })
        }
        if (!visible) {
            if (!_accepted && pendingDownloadId.length > 0)
                rejected(pendingDownloadId, pendingUrl)
            _accepted     = false
            isIntercepted = false
        }
    }

    // ── Category helpers ─────────────────────────────────────────────────
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
            categoryIds    = _categoryIds()
            categoryLabels = _categoryLabels()
        }
    }

    Connections {
        target: App
        function onPendingDownloadFilenameChanged(downloadId, newFilename) {
            if (downloadId === root.pendingDownloadId && newFilename
                && newFilename !== root.pendingFilename) {
                root.pendingFilename = newFilename
            }
        }
    }

    function categoryIndexForUrl(url, name) {
        var catId = App.categoryModel.categoryForUrl(url, name)
        for (var i = 0; i < categoryIds.length; i++)
            if (categoryIds[i] === catId) return i
        return 0
    }

    function savePathForIndex(idx) {
        return App.categoryModel.savePathForCategory(categoryIds[idx] || "all")
    }

    onPendingUrlChanged:      _reset()
    onPendingFilenameChanged: _reset()

    function _reset() {
        var idx = categoryIndexForUrl(pendingUrl, pendingFilename)
        catCombo.currentIndex = idx
        _updateSavePath(idx)
        descField.text = ""
        _probing = false
        if (pendingUrl.length > 0)
            _probeMetadata()
    }

    function _probeMetadata() {
        _probing = true
        var url      = pendingUrl
        var cookies  = pendingCookies
        var referrer = pendingReferrer
        App.probeFileInfo(url, cookies, referrer, function(info) {
            _probing = false
            if (!info.ok) return
            var desc = _buildDescription(info)
            if (desc.length > 0 && descField.text.length === 0)
                descField.text = desc
            if (info.contentLength > 0 && root.pendingSize.length === 0)
                root.pendingSize = _formatSize(info.contentLength)
            // Server may have resolved a real filename from Content-Disposition
            // ── or the final redirect URL (e.g. "x64" "LM-Studio-0.4.14-4-x64.deb"). ──
            // But an explicit override (e.g. duplicate "Add numbered name") wins —
            // don't let the probe clobber it back to the un-numbered server name.
            if (root.filenameOverride.length === 0
                    && info.filename && info.filename !== root.pendingFilename) {
                root.pendingFilename = info.filename
            }
        })
    }

    function _formatSize(bytes) {
        if (bytes <= 0) return ""
        if (bytes < 1024) return bytes + " B"
        if (bytes < 1048576) return (bytes / 1024).toFixed(1) + " KB"
        if (bytes < 1073741824) return (bytes / 1048576).toFixed(1) + " MB"
        return (bytes / 1073741824).toFixed(2) + " GB"
    }

    function _fmtDuration(dur) {
        if (dur <= 0) return ""
        var h = Math.floor(dur / 3600)
        var m = Math.floor((dur % 3600) / 60)
        var s = dur % 60
        if (h > 0) return h + " hr " + m + " min"
        return m + " min" + (s > 0 ? " " + s + " sec" : "")
    }

    // Map a height to a friendly resolution label, else "WxH".
    function _resLabel(w, h) {
        if (w <= 0 || h <= 0) return ""
        if (h >= 2160 || w >= 3840) return w + "x" + h + " (4K)"
        if (h >= 1440) return w + "x" + h + " (1440p)"
        if (h >= 1080) return w + "x" + h + " (1080p)"
        if (h >= 720)  return w + "x" + h + " (720p)"
        return w + "x" + h
    }

    function _buildDescription(info) {
        var ct   = (info.contentType || "").toLowerCase()
        var name = root.pendingFilename.toLowerCase()
        var parts = []

        // ── Image ──────────────────────────────────────────────────────────────
        var iw = parseInt(info.imageWidth), ih = parseInt(info.imageHeight)
        if (iw > 0 && ih > 0) {
            var ifmt = ""
            if      (name.endsWith(".png"))  ifmt = "PNG"
            else if (/\.jpe?g$|\.jpe$/.test(name) || ct.indexOf("jpeg") >= 0) ifmt = "JPEG"
            else if (name.endsWith(".gif"))  ifmt = "GIF"
            else if (name.endsWith(".webp")) ifmt = "WebP"
            else if (name.endsWith(".bmp"))  ifmt = "BMP"
            else if (/\.tiff?$/.test(name))  ifmt = "TIFF"
            if (ifmt.length > 0) parts.push(ifmt)
            parts.push(iw + "x" + ih)
            var ict = info.imageColorType
            if (ict && ict.length > 0) parts.push(ict)
            var ibd = parseInt(info.imageBitDepth)
            if (ibd > 0) parts.push(ibd + "-bit")
            return parts.length > 1 ? parts.join(", ") : parts.join(", ")
        }

        // ── Raw photo ────────────────────────────────────────────────────────────
        if (/\.(cr2|cr3|nef|arw|dng|orf|rw2|pef|srw|raf)$/.test(name)) {
            parts.push("RAW")
            var rw = parseInt(info.imageWidth), rh = parseInt(info.imageHeight)
            if (rw > 0 && rh > 0) parts.push(rw + "x" + rh)
            var mk = info.cameraMake, md = info.cameraModel
            var cam = [mk, md].filter(function(x){ return x && x.length > 0 }).join(" ")
            if (cam.length > 0) parts.push(cam)
            return parts.length > 1 ? parts.join(", ") : ""
        }

        // ── Video ────────────────────────────────────────────────────────────────
        var vw = parseInt(info.videoWidth), vh = parseInt(info.videoHeight)
        var vcodec = info.videoCodec
        var isVideo = ct.indexOf("video/") === 0
            || /\.(mp4|mov|m4v|mkv|webm|avi|flv)$/.test(name)
            || vw > 0 || (vcodec && vcodec.length > 0)
        if (isVideo) {
            if (vcodec && vcodec.length > 0) parts.push(vcodec)
            var rl = _resLabel(vw, vh)
            if (rl.length > 0) parts.push(rl)
            var vfps = parseInt(info.videoFps)
            if (vfps > 0) parts.push(vfps + " fps")
            var vdur = parseInt(info.videoDurationSec)
            if (vdur > 0) parts.push(_fmtDuration(vdur))
            // Append embedded audio track summary when known.
            var akbps = parseInt(info.audioBitrateKbps)
            var ach = parseInt(info.audioChannels)
            if (akbps > 0) parts.push("Audio " + akbps + " kbps")
            else if (ach > 0) parts.push(ach === 1 ? "Audio Mono" : (ach === 2 ? "Audio Stereo" : "Audio " + ach + " ch"))
            return parts.length >= 1 && (vw > 0 || (vcodec && vcodec.length > 0)) ? parts.join(", ") : ""
        }

        // ── Audio ────────────────────────────────────────────────────────────────
        var isAudio = ct.indexOf("audio/") === 0 || ct.indexOf("mpeg") >= 0
            || ct.indexOf("flac") >= 0 || ct.indexOf("ogg") >= 0 || ct.indexOf("opus") >= 0
            || /\.(mp3|flac|ogg|opus|wav|aac|m4a|m4b|wma|asf|alac|ape|aiff|aif|aifc|mka)$/.test(name)
        if (!isAudio) return ""
        var fmt = ""
        if      (ct.indexOf("flac") >= 0 || name.endsWith(".flac")) fmt = "FLAC"
        else if (ct.indexOf("ogg")  >= 0 || name.endsWith(".ogg"))  fmt = "OGG Vorbis"
        else if (ct.indexOf("opus") >= 0 || name.endsWith(".opus")) fmt = "Opus"
        else if (ct.indexOf("mpeg") >= 0 || name.endsWith(".mp3"))  fmt = "MP3"
        else if (name.endsWith(".aac"))  fmt = "AAC"
        else if (name.endsWith(".m4a") || name.endsWith(".m4b")) fmt = "M4A"
        else if (name.endsWith(".wav"))  fmt = "WAV"
        else if (name.endsWith(".wma") || name.endsWith(".asf"))  fmt = "WMA"
        else if (name.endsWith(".alac")) fmt = "ALAC"
        else if (name.endsWith(".aiff") || name.endsWith(".aif") || name.endsWith(".aifc")) fmt = "AIFF"
        if (fmt.length > 0) parts.push(fmt)
        var kbps = parseInt(info.audioBitrateKbps)
        if (kbps > 0) parts.push(kbps + " kbps")
        var sr = parseInt(info.audioSampleRate)
        if (sr > 0) {
            var srStr = (sr % 1000 === 0) ? (sr / 1000) + " kHz" : (sr / 1000).toFixed(1) + " kHz"
            parts.push(srStr)
        }
        var ch = parseInt(info.audioChannels)
        if (ch === 1) parts.push("Mono")
        else if (ch === 2) parts.push("Stereo")
        else if (ch > 2)   parts.push(ch + " ch")
        var bps = parseInt(info.audioBitsPerSample)
        if (bps > 0 && bps !== 16) parts.push(bps + "-bit")
        var dur = parseInt(info.audioDurationSec)
        if (dur > 0) {
            var m = Math.floor(dur / 60), s = dur % 60
            parts.push(m + " min " + (s > 0 ? s + " sec" : "").trim())
        }
        return parts.length > 1 ? parts.join(", ") : ""
    }

    function _updateSavePath(catIdx) {
        var dir = savePathForIndex(catIdx)
        if (!dir || dir.length === 0) dir = pendingSavePath
        dir = dir.replace(/\\/g, "/")
        if (!dir.endsWith("/")) dir += "/"
        saveAsField.text = dir + pendingFilename
        dirOnlyField.text = dir
    }

    FileDialog {
        id: saveAsDlg
        fileMode: FileDialog.SaveFile
        defaultSuffix: {
            var parts = root.pendingFilename.split('.')
            return parts.length > 1 ? parts[parts.length - 1] : ""
        }
        nameFilters: {
            var parts = root.pendingFilename.split('.')
            var ext = parts.length > 1 ? parts[parts.length - 1].toLowerCase() : ""
            if (ext.length > 0)
                return [qsTr("%1 files (*.%2)").arg(ext.toUpperCase()).arg(ext), qsTr("All files (*)")]
            return [qsTr("All files (*)")]
        }
        onAccepted: {
            var path = pathFromFileUrl(file)
            if (path.length > 0) {
                saveAsField.text = path
                var sep = Math.max(path.lastIndexOf("/"), path.lastIndexOf("\\"))
                dirOnlyField.text = sep >= 0 ? path.substring(0, sep + 1) : path
            }
        }
    }

    // ── Add Category dialog ──────────────────────────────────────────────
    Window {
        id: addCatDialog
        width: 460
        height: addCatCol.implicitHeight + 24
        title: qsTr("Adding a category to Stellar categories list")
        color: ColorPalette.cardBg
        modality: Qt.ApplicationModal
        transientParent: root
        flags: Qt.Window | Qt.WindowTitleHint | Qt.WindowCloseButtonHint | Qt.MSWindowsFixedSizeDialogHint

        Material.theme: ColorPalette.materialTheme
    Material.foreground: ColorPalette.textPrimary
        Material.background: ColorPalette.materialBg
        Material.accent: "#4488dd"

        function openNew() {
            addCatNameField.text = ""
            addCatExtField.text  = ""
            addCatSitesChk.checked = false
            addCatSitesField.text = ""
            addCatFolderField.text = App.settings.defaultSavePath || ""
            addCatRememberChk.checked = false
            _editId = ""
            var owner = root
            x = owner.x + Math.round((owner.width  - width)  / 2)
            y = owner.y + Math.round((owner.height - height) / 2)
            show(); raise(); requestActivate()
            Qt.callLater(function() { addCatNameField.forceActiveFocus() })
        }

        property string _editId: ""

        FolderDialog {
            id: addCatFolderDlg
            onAccepted: {
                var p = String(folder)
                if (Qt.platform.os === "windows") p = p.replace(/^file:\/\/\//, "")
                else p = p.replace(/^file:\/\//, "")
                addCatFolderField.text = p
            }
        }

        ColumnLayout {
            id: addCatCol
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
            spacing: 10

            // Two-column layout: form on left, OK/Cancel on right
            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignTop
                    spacing: 8

                    // Category name
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 3
                        Text { text: qsTr("Category name"); color: ColorPalette.textSecond; font.pixelSize: 11 * App.fontScale }
                        Rectangle {
                            Layout.fillWidth: true; Layout.preferredHeight: 22
                            color: ColorPalette.inputBg
                            border.color: addCatNameField.activeFocus ? "#4488dd" : ColorPalette.border
                            border.width: 1; radius: 2
                            TextInput {
                                id: addCatNameField
                                anchors.fill: parent; anchors.leftMargin: 5; anchors.rightMargin: 5
                                verticalAlignment: TextInput.AlignVCenter
                                color: ColorPalette.textPrimary; font.pixelSize: 11 * App.fontScale
                                selectByMouse: true; clip: true
                                Keys.onReturnPressed: addCatDialog._doAdd()
                                Keys.onEnterPressed:  addCatDialog._doAdd()
                            }
                        }
                    }

                    // File types
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 3
                        Text {
                            text: qsTr("Automatically put in this category the following file types:")
                            color: ColorPalette.textSecond; font.pixelSize: 11 * App.fontScale; wrapMode: Text.WordWrap
                            Layout.fillWidth: true
                        }
                        Rectangle {
                            Layout.fillWidth: true; Layout.preferredHeight: 22
                            color: ColorPalette.inputBg
                            border.color: addCatExtField.activeFocus ? "#4488dd" : ColorPalette.border
                            border.width: 1; radius: 2
                            TextInput {
                                id: addCatExtField
                                anchors.fill: parent; anchors.leftMargin: 5; anchors.rightMargin: 5
                                verticalAlignment: TextInput.AlignVCenter
                                color: ColorPalette.textPrimary; font.pixelSize: 11 * App.fontScale
                                selectByMouse: true; clip: true
                            }
                        }
                        Text {
                            text: qsTr("Note: type file extensions separated by space (e.g. avi mpg mpeg)")
                            color: ColorPalette.textDisabled; font.pixelSize: 10 * App.fontScale; wrapMode: Text.WordWrap
                            Layout.fillWidth: true
                        }
                    }

                    // Sites checkbox + field
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 3
                        StyledCheckBox {
                            id: addCatSitesChk
                            topPadding: 0; bottomPadding: 0
                            text: qsTr("Automatically put in this category the files from the following sites only:")
                            contentItem: Text {
                                text: parent.text; color: ColorPalette.textSecond; font.pixelSize: 11 * App.fontScale
                                leftPadding: parent.indicator.width + 4
                                verticalAlignment: Text.AlignVCenter; wrapMode: Text.WordWrap
                                width: parent.width - parent.indicator.width - 8
                            }
                        }
                        Rectangle {
                            Layout.fillWidth: true; Layout.preferredHeight: 22
                            color: addCatSitesChk.checked ? ColorPalette.inputBg : ColorPalette.panelBg
                            border.color: addCatSitesField.activeFocus ? "#4488dd" : ColorPalette.border
                            border.width: 1; radius: 2
                            TextInput {
                                id: addCatSitesField
                                anchors.fill: parent; anchors.leftMargin: 5; anchors.rightMargin: 5
                                verticalAlignment: TextInput.AlignVCenter
                                color: addCatSitesChk.checked ? ColorPalette.textPrimary : ColorPalette.textDisabled
                                font.pixelSize: 11 * App.fontScale; selectByMouse: true; clip: true
                                enabled: addCatSitesChk.checked
                            }
                        }
                        Text {
                            text: qsTr("Separate sites by spaces. You may use asterisk as a wildcard pattern")
                            color: ColorPalette.textDisabled; font.pixelSize: 10 * App.fontScale; wrapMode: Text.WordWrap
                            Layout.fillWidth: true
                        }
                    }

                    // Save folder
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 3
                        Text {
                            text: qsTr("Save future downloads of this category to the following folder:")
                            color: "#5a9ad4"; font.pixelSize: 11 * App.fontScale; wrapMode: Text.WordWrap
                            Layout.fillWidth: true
                        }
                        Rectangle {
                            Layout.fillWidth: true; Layout.preferredHeight: 22
                            color: ColorPalette.inputBg
                            border.color: addCatFolderField.activeFocus ? "#4488dd" : ColorPalette.border
                            border.width: 1; radius: 2
                            TextInput {
                                id: addCatFolderField
                                anchors.fill: parent; anchors.leftMargin: 5; anchors.rightMargin: 5
                                verticalAlignment: TextInput.AlignVCenter
                                color: ColorPalette.textPrimary; font.pixelSize: 11 * App.fontScale
                                selectByMouse: true; clip: true
                            }
                        }
                    }

                    // Remember last save path
                    StyledCheckBox {
                        id: addCatRememberChk
                        topPadding: 0; bottomPadding: 0
                        text: qsTr("Remember last save path")
                        contentItem: Text {
                            text: parent.text; color: ColorPalette.textSecond; font.pixelSize: 11 * App.fontScale
                            leftPadding: parent.indicator.width + 4
                            verticalAlignment: Text.AlignVCenter
                        }
                    }

                    // Browse button (right-aligned under folder field)
                    RowLayout {
                        Layout.fillWidth: true
                        Item { Layout.fillWidth: true }
                        DlgButton {
                            text: qsTr("Browse...")
                            onClicked: addCatFolderDlg.open()
                        }
                    }
                }

                // OK / Cancel column
                ColumnLayout {
                    Layout.alignment: Qt.AlignTop
                    spacing: 6
                    Layout.preferredWidth: 80

                    DlgButton {
                        text: qsTr("OK")
                        primary: true
                        Layout.fillWidth: true
                        onClicked: addCatDialog._doAdd()
                    }
                    DlgButton {
                        text: qsTr("Cancel")
                        Layout.fillWidth: true
                        onClicked: addCatDialog.close()
                    }
                }
            }
        }

        function _doAdd() {
            var name = addCatNameField.text.trim()
            if (name.length === 0) return

            var exts = addCatExtField.text.trim().split(/\s+/).filter(function(s){ return s.length > 0 })
            var sites = addCatSitesChk.checked
                ? addCatSitesField.text.trim().split(/\s+/).filter(function(s){ return s.length > 0 })
                : []
            var folder = addCatFolderField.text.trim()

            if (_editId.length > 0) {
                App.categoryModel.updateCategory(_editId, name, exts, sites, folder)
            } else {
                var newId = App.categoryModel.addCategory(name)
                if (newId.length > 0)
                    App.categoryModel.updateCategory(newId, name, exts, sites, folder)
                Qt.callLater(function() {
                    catCombo.currentIndex = root.categoryIds.length - 1
                    root._updateSavePath(catCombo.currentIndex)
                })
            }
            addCatDialog.close()
        }
    }

    // ── Root layout ──────────────────────────────────────────────────────
    ColumnLayout {
        id: mainCol
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
        spacing: 8

        // Form rows + file icon side-by-side
        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            // Left: all form rows
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 8

                // URL
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6
                    Text { text: qsTr("URL"); color: ColorPalette.textSecond; font.pixelSize: 11 * App.fontScale; Layout.preferredWidth: 72; horizontalAlignment: Text.AlignRight }
                    Rectangle {
                        Layout.fillWidth: true; Layout.preferredHeight: 22
                        color: ColorPalette.inputBg; border.color: urlField.activeFocus ? "#4488dd" : ColorPalette.border; border.width: 1; radius: 2
                        TextInput {
                            id: urlField
                            anchors.fill: parent; anchors.leftMargin: 5; anchors.rightMargin: 5
                            verticalAlignment: TextInput.AlignVCenter
                            color: ColorPalette.textPrimary; font.pixelSize: 11 * App.fontScale
                            readOnly: true; selectByMouse: true; clip: true
                            text: root.pendingUrl
                        }
                    }
                }

                // Category
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6
                    Text { text: qsTr("Category"); color: ColorPalette.textSecond; font.pixelSize: 11 * App.fontScale; Layout.preferredWidth: 72; horizontalAlignment: Text.AlignRight }
                    Rectangle {
                        implicitWidth: 160; implicitHeight: 22
                        color: ColorPalette.inputBg; border.color: ColorPalette.border; border.width: 1; radius: 2
                        StyledComboBox {
                            id: catCombo
                            anchors.fill: parent
                            model: root.categoryLabels
                            font.pixelSize: 11 * App.fontScale
                            background: Item {}
                            contentItem: Text {
                                leftPadding: 6; text: catCombo.displayText
                                color: ColorPalette.textPrimary; font: catCombo.font
                                verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight
                            }
                            onCurrentIndexChanged: root._updateSavePath(currentIndex)
                        }
                    }
                    Rectangle {
                        id: addCatBtn
                        width: 22; height: 22; radius: 2
                        color: addCatMa.containsMouse ? "#2e2e2e" : ColorPalette.inputBg
                        border.color: ColorPalette.border; border.width: 1
                        Text { anchors.centerIn: parent; text: "+"; color: "#909090"; font.pixelSize: 15 * App.fontScale }
                        MouseArea {
                            id: addCatMa; anchors.fill: parent; hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: addCatDialog.openNew()
                        }
                    }
                    Item { Layout.fillWidth: true }
                }

                // Save As
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6
                    Text { text: qsTr("Save As"); color: ColorPalette.textSecond; font.pixelSize: 11 * App.fontScale; Layout.preferredWidth: 72; horizontalAlignment: Text.AlignRight }
                    Rectangle {
                        Layout.fillWidth: true; Layout.preferredHeight: 22
                        color: ColorPalette.inputBg; border.color: saveAsField.activeFocus ? "#4488dd" : ColorPalette.border; border.width: 1; radius: 2
                        TextInput {
                            id: saveAsField
                            anchors.fill: parent; anchors.leftMargin: 5; anchors.rightMargin: 5
                            verticalAlignment: TextInput.AlignVCenter
                            color: ColorPalette.textPrimary; font.pixelSize: 11 * App.fontScale
                            selectByMouse: true; clip: true
                            onTextEdited: {
                                var sep = Math.max(text.lastIndexOf("/"), text.lastIndexOf("\\"))
                                dirOnlyField.text = sep >= 0 ? text.substring(0, sep + 1) : ""
                            }
                        }
                    }
                    Rectangle {
                        width: 26; height: 22; radius: 2
                        color: browseMa.containsMouse ? "#2e2e2e" : ColorPalette.inputBg
                        border.color: ColorPalette.border; border.width: 1
                        Text { anchors.centerIn: parent; text: "…"; color: ColorPalette.textPrimary; font.pixelSize: 12 * App.fontScale }
                        MouseArea {
                            id: browseMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                var cur = saveAsField.text || (savePathForIndex(catCombo.currentIndex) + pendingFilename)
                                saveAsDlg.folder = fileUrlFromPath(cur.replace(/[\/\\][^\/\\]*$/, ""))
                                saveAsDlg.currentFile = fileUrlFromPath(cur)
                                saveAsDlg.open()
                            }
                        }
                    }
                }

                // Remember checkbox + dir sub-field
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6
                    Item { Layout.preferredWidth: 72 }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 4
                        StyledCheckBox {
                            id: rememberPathChk
                            topPadding: 0; bottomPadding: 0
                            text: qsTr("Remember this path for \"%1\" category").arg(root.categoryLabels[catCombo.currentIndex] || "")
                            contentItem: Text {
                                text: parent.text; color: ColorPalette.textSecond; font.pixelSize: 11 * App.fontScale
                                leftPadding: parent.indicator.width + 4
                                verticalAlignment: Text.AlignVCenter
                            }
                        }
                        Rectangle {
                            Layout.fillWidth: true; Layout.preferredHeight: 22
                            color: ColorPalette.panelBg; border.color: ColorPalette.border; border.width: 1; radius: 2
                            TextInput {
                                id: dirOnlyField
                                anchors.fill: parent; anchors.leftMargin: 5; anchors.rightMargin: 5
                                verticalAlignment: TextInput.AlignVCenter
                                color: ColorPalette.textDisabled; font.pixelSize: 11 * App.fontScale
                                readOnly: true; clip: true
                            }
                        }
                    }
                }

                // Description
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6
                    Text { text: qsTr("Description"); color: ColorPalette.textSecond; font.pixelSize: 11 * App.fontScale; Layout.preferredWidth: 72; horizontalAlignment: Text.AlignRight }
                    Rectangle {
                        Layout.fillWidth: true; Layout.preferredHeight: 22
                        color: ColorPalette.inputBg; border.color: descField.activeFocus ? "#4488dd" : ColorPalette.border; border.width: 1; radius: 2
                        TextInput {
                            id: descField
                            anchors.fill: parent; anchors.leftMargin: 5; anchors.rightMargin: 5
                            verticalAlignment: TextInput.AlignVCenter
                            color: ColorPalette.textPrimary; font.pixelSize: 11 * App.fontScale
                            selectByMouse: true; clip: true
                        }
                    }
                }
            }

            // Right: file icon + size, vertically centered
            Item {
                Layout.preferredWidth: 60
                Layout.fillHeight: true

                ColumnLayout {
                    anchors.centerIn: parent
                    spacing: 4

                    Image {
                        Layout.alignment: Qt.AlignHCenter
                        Layout.preferredWidth: 40; Layout.preferredHeight: 40
                        sourceSize.width: 40; sourceSize.height: 40
                        source: root.pendingFilename ? "image://fileicon/" + root.pendingFilename : ""
                        fillMode: Image.PreserveAspectFit; smooth: true
                    }
                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        text: root.pendingSize
                        color: ColorPalette.textMuted; font.pixelSize: 10 * App.fontScale
                        visible: root.pendingSize.length > 0
                        horizontalAlignment: Text.AlignHCenter
                    }
                }
            }
        }

        // Button row: Download Later | Start Download | spacer | Cancel
        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: 2
            spacing: 6

            DlgButton {
                text: qsTr("Download Later")
                onClicked: {
                    root._accepted = true
                    if (rememberPathChk.checked)
                        App.categoryModel.setSavePath(_catId(), _savePath())
                    root.downloadLater(root.pendingDownloadId, root.pendingUrl, saveAsField.text, _catId(), descField.text)
                    root.close()
                }
            }

            DlgButton {
                text: qsTr("Start Download")
                primary: true
                onClicked: {
                    root._accepted = true
                    if (rememberPathChk.checked)
                        App.categoryModel.setSavePath(_catId(), _savePath())
                    root.downloadNow(root.pendingDownloadId, root.pendingUrl, saveAsField.text, _catId(), descField.text)
                    root.close()
                }
            }

            Item { Layout.fillWidth: true }

            DlgButton {
                text: qsTr("Cancel")
                onClicked: root.close()
            }
        }
    }

    function _savePath() {
        var full = saveAsField.text
        var sep = full.lastIndexOf("\\")
        if (sep < 0) sep = full.lastIndexOf("/")
        return sep >= 0 ? full.substring(0, sep) : full
    }
    function _catId() { return root.categoryIds[catCombo.currentIndex] || "all" }
}
