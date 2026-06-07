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
import com.stellar.app 1.0

Window {
    id: root

    width:        500
    height:       522
    minimumWidth: 460
    maximumWidth: 700
    title: qsTr("Create Torrent")
    color: ColorPalette.cardBg
    flags: Qt.Dialog | Qt.WindowTitleHint | Qt.WindowCloseButtonHint
    // ── Fixed height content doesn't scroll. ─────────────────────────────
    minimumHeight: height
    maximumHeight: height

    Material.theme:      ColorPalette.materialTheme
    Material.background: ColorPalette.materialBg
    Material.accent:     "#4488dd"

    // ── State ────────────────────────────────────────────────────────────
    property bool   _creating:   false
    property int    _progress:   0
    property bool   _done:       false
    property bool   _success:    false
    property string _resultPath: ""
    property string _errorText:  ""
    property int    _pieceCount: 0
    property int    _pieceSize:  0
    property double _totalInputBytes: 0

    // ── Piece sizes indexed by slider position: 0=Auto, 1=16KiB, , 11=16MiB ──
    property var _pieceSizes: [0, 16384, 32768, 65536, 131072, 262144, 524288, 1048576, 2097152, 4194304, 8388608, 16777216]
    property var _pieceSizeLabels: [qsTr("Auto"), "16K", "32K", "64K", "128K", "256K", "512K", "1M", "2M", "4M", "8M", "16M"]

    function _sliderPieceSizeBytes() {
        return _pieceSizes[pieceSizeSlider.value]
    }

    function _estimateAutoPieceSize(totalSize) {
        if (totalSize <= 0) return 0
        var s = 16384
        while (s * 1500 < totalSize && s < 16777216) s *= 2
        return s
    }

    function _effectivePieceSize() {
        var sel = _sliderPieceSizeBytes()
        if (sel === 0 && _totalInputBytes > 0)
            return _estimateAutoPieceSize(_totalInputBytes)
        return sel
    }

    function _estimatedPieceCount() {
        var sz = _effectivePieceSize()
        if (sz <= 0 || _totalInputBytes <= 0) return 0
        return Math.ceil(_totalInputBytes / sz)
    }

    function _refreshTotalSize() {
        var paths = []
        for (var i = 0; i < inputFilesModel.count; i++)
            paths.push(inputFilesModel.get(i).path)
        _totalInputBytes = paths.length > 0 ? App.totalInputSize(paths) : 0
    }

    // ── Helpers ──────────────────────────────────────────────────────────
    function _fmtBytes(b) {
        if (b <= 0)         return "0 B"
        if (b < 1024)       return b + " B"
        if (b < 1048576)    return (b / 1024).toFixed(1) + " KiB"
        if (b < 1073741824) return (b / 1048576).toFixed(1) + " MiB"
        return (b / 1073741824).toFixed(2) + " GiB"
    }

    function _defaultName() {
        if (inputFilesModel.count === 0) return ""
        var p = inputFilesModel.get(0).path.replace(/[/\\]+$/, "")
        var base = p.split(/[/\\]/).pop()
        return base.replace(/\.[^/.]+$/, "")
    }

    // Normalize path separators to the OS native direction.
    function _nativePath(p) {
        if (Qt.platform.os === "windows")
            return p.replace(/\//g, "\\")
        return p.replace(/\\/g, "/")
    }

    function _desktopPath() {
        var sp = _nativePath(App.settings.defaultSavePath)
        if (Qt.platform.os === "windows") {
            // Extract C:\Users\<name> and append \Desktop.
            var m = sp.match(/^([A-Za-z]:\\[^\\]+\\[^\\]+)/)
            if (m) return m[1] + "\\Desktop"
        }
        return sp
    }

    function _buildOutputPath() {
        var dir  = _nativePath(saveDirField.text.trim())
        var name = (nameField.text.trim() || _defaultName() || "output") + ".torrent"
        if (dir.length === 0) return ""
        var sep = (Qt.platform.os === "windows") ? "\\" : "/"
        if (!dir.endsWith("/") && !dir.endsWith("\\")) dir += sep
        return dir + name
    }

    function _canCreate() {
        return inputFilesModel.count > 0 && saveDirField.text.trim().length > 0
    }

    function _reset() {
        _creating = false; _progress = 0; _done = false
        _success = false; _resultPath = ""; _errorText = ""
        _pieceCount = 0; _pieceSize = 0
    }

    function _startCreation() {
        if (!_canCreate() || _creating) return
        _reset()
        _creating = true

        var paths = []
        for (var i = 0; i < inputFilesModel.count; i++)
            paths.push(inputFilesModel.get(i).path)

        var pieceSizeVal = _sliderPieceSizeBytes()

        var trackerLines = trackersField.text.split("\n")
            .map(function(l){return l.trim()}).filter(function(l){return l.length>0})
        var seedLines = webSeedsField.text.split("\n")
            .map(function(l){return l.trim()}).filter(function(l){return l.length>0})

        var params = {
            "inputPaths":  paths,
            "outputPath":  _buildOutputPath(),
            "name":        nameField.text.trim() || _defaultName(),
            "comment":     commentField.text.trim(),
            "description": "",
            "trackers":    trackerLines,
            "webSeeds":    seedLines,
            "isPrivate":   privateCheck.checked,
            "pieceSize":   pieceSizeVal,
            "creatorTag":  "Stellar/" + App.appVersion
        }

        var info = App.beginCreateTorrent(params)
        _pieceCount = info.pieceCount || 0
        _pieceSize  = info.pieceSize  || 0
    }

    onVisibleChanged: {
        if (visible && saveDirField.text.trim().length === 0)
            saveDirField.text = _desktopPath()
    }

    onClosing: {
        if (_creating) App.cancelCreateTorrent()
        _reset()
        inputFilesModel.clear()
        nameField.text = ""; commentField.text = ""
        trackersField.text = ""; webSeedsField.text = ""
        privateCheck.checked = false; openWhenDoneCheck.checked = false
        pieceSizeSlider.value = 0
    }

    // ── Connections ──────────────────────────────────────────────────────
    Connections {
        target: App
        function onTorrentCreationProgress(percent) { root._progress = percent }
        function onTorrentCreationFinished(success, errorOrPath) {
            root._creating = false; root._done = true; root._success = success
            if (success) {
                root._resultPath = errorOrPath
                if (openWhenDoneCheck.checked) root.openTorrentRequested(errorOrPath)
            } else if (errorOrPath !== "cancelled") {
                root._errorText = errorOrPath
            }
        }
    }

    // ── Models ───────────────────────────────────────────────────────────
    ListModel { id: inputFilesModel }

    // ── File dialogs ─────────────────────────────────────────────────────
    FileDialog {
        id: addFilesDialog
        title: qsTr("Add Files")
        fileMode: FileDialog.OpenFiles
        onAccepted: {
            for (var i = 0; i < files.length; i++) {
                var p = decodeURIComponent(files[i].toString()
                    .replace(/^file:\/\/\//, "").replace(/^file:\/\//, ""))
                var dup = false
                for (var j = 0; j < inputFilesModel.count; j++)
                    if (inputFilesModel.get(j).path === p) { dup = true; break }
                if (!dup) inputFilesModel.append({"path": p})
            }
            if (nameField.text.trim().length === 0)
                nameField.text = root._defaultName()
            root._refreshTotalSize()
        }
    }

    FolderDialog {
        id: addFolderDialog
        title: qsTr("Add Folder")
        onAccepted: {
            var p = decodeURIComponent(folder.toString()
                .replace(/^file:\/\/\//, "").replace(/^file:\/\//, ""))
            var dup = false
            for (var j = 0; j < inputFilesModel.count; j++)
                if (inputFilesModel.get(j).path === p) { dup = true; break }
            if (!dup) inputFilesModel.append({"path": p})
            if (nameField.text.trim().length === 0)
                nameField.text = root._defaultName()
            root._refreshTotalSize()
        }
    }

    FolderDialog {
        id: saveDirDialog
        title: qsTr("Choose Output Folder")
        onAccepted: {
            var p = decodeURIComponent(folder.toString()
                .replace(/^file:\/\/\//, "").replace(/^file:\/\//, ""))
            saveDirField.text = root._nativePath(p)
        }
    }

    // ── Layout ───────────────────────────────────────────────────────────
    // Constant row geometry so nothing shifts during interaction.
    readonly property int _lw: 80   // label column width
    readonly property int _lm: 14   // left margin
    readonly property int _rm: 14   // right margin
    readonly property int _rh: 26   // standard row height

    Column {
        anchors.fill: parent
        spacing: 0

        // ── Form body ────────────────────────────────────────────────────
        Item {
            width: parent.width
            // Fixed body height: total - footer
            height: parent.height - 48

            Column {
                anchors { fill: parent; topMargin: 10 }
                spacing: 0

                // ── Files ────────────────────────────────────────────────
                // Section header
                Item {
                    width: parent.width; height: 22
                    Text {
                        anchors { left: parent.left; leftMargin: root._lm; verticalCenter: parent.verticalCenter }
                        text: qsTr("Files"); color: ColorPalette.textPrimary; font.pixelSize: 11 * App.fontScale; font.weight: Font.Medium
                    }
                    Rectangle {
                        anchors { left: parent.left; right: parent.right
                                  leftMargin: root._lm; rightMargin: root._rm; bottom: parent.bottom }
                        height: 1; color: ColorPalette.border
                    }
                }

                // Source row
                Item {
                    width: parent.width; height: root._rh + 8

                    Text {
                        anchors { left: parent.left; leftMargin: root._lm; verticalCenter: parent.verticalCenter }
                        text: qsTr("Source:"); color: ColorPalette.textPrimary; font.pixelSize: 11 * App.fontScale; width: root._lw
                    }

                    // Source display box
                    Rectangle {
                        id: sourceDisplayRect
                        anchors {
                            left: parent.left; leftMargin: root._lm + root._lw
                            right: sourceButtonRow.left; rightMargin: 6
                            verticalCenter: parent.verticalCenter
                        }
                        height: root._rh; color: ColorPalette.inputBg; border.color: ColorPalette.border; radius: 2

                        Text {
                            anchors { fill: parent; leftMargin: 6; rightMargin: 6 }
                            verticalAlignment: Text.AlignVCenter
                            elide: Text.ElideLeft; font.pixelSize: 11 * App.fontScale
                            color: inputFilesModel.count > 0 ? ColorPalette.textPrimary : "#445566"
                            text: inputFilesModel.count > 0
                                ? (inputFilesModel.get(0).path +
                                   (inputFilesModel.count > 1 ? qsTr(" (+%1 more)").arg(inputFilesModel.count - 1) : ""))
                                : qsTr("No source selected")
                        }
                    }

                    Row {
                        id: sourceButtonRow
                        anchors { right: parent.right; rightMargin: root._rm; verticalCenter: parent.verticalCenter }
                        spacing: 4

                        // ── File button ──────────────────────────────────
                        Rectangle {
                            width: fileBtn.implicitWidth + 14; height: root._rh; radius: 2
                            color: fileBtnMa.containsMouse ? ColorPalette.border : ColorPalette.dividerBg
                            border.color: "#4a4a4a"
                            Text { id: fileBtn; anchors.centerIn: parent; text: qsTr("File…"); color: ColorPalette.textPrimary; font.pixelSize: 11 * App.fontScale }
                            MouseArea {
                                id: fileBtnMa; anchors.fill: parent; hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                enabled: !root._creating
                                onClicked: addFilesDialog.open()
                            }
                        }
                        // ── Folder button ────────────────────────────────
                        Rectangle {
                            width: folderBtn.implicitWidth + 14; height: root._rh; radius: 2
                            color: folderBtnMa.containsMouse ? ColorPalette.border : ColorPalette.dividerBg
                            border.color: "#4a4a4a"
                            Text { id: folderBtn; anchors.centerIn: parent; text: qsTr("Folder…"); color: ColorPalette.textPrimary; font.pixelSize: 11 * App.fontScale }
                            MouseArea {
                                id: folderBtnMa; anchors.fill: parent; hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                enabled: !root._creating
                                onClicked: addFolderDialog.open()
                            }
                        }
                        // Remove button
                        Rectangle {
                            width: removeBtn.implicitWidth + 14; height: root._rh; radius: 2
                            color: removeBtnMa.containsMouse && inputFilesModel.count > 0 ? "#3a2a2a" : ColorPalette.dividerBg
                            border.color: "#4a4a4a"
                            opacity: inputFilesModel.count > 0 ? 1.0 : 0.4
                            Text { id: removeBtn; anchors.centerIn: parent; text: qsTr("Remove"); color: ColorPalette.textPrimary; font.pixelSize: 11 * App.fontScale }
                            MouseArea {
                                id: removeBtnMa; anchors.fill: parent; hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                enabled: !root._creating && inputFilesModel.count > 0
                                onClicked: { inputFilesModel.remove(inputFilesModel.count - 1); root._refreshTotalSize() }
                            }
                        }
                    }
                }

                // Save to row
                Item {
                    width: parent.width; height: root._rh + 8
                    Text {
                        anchors { left: parent.left; leftMargin: root._lm; verticalCenter: parent.verticalCenter }
                        text: qsTr("Save to:"); color: ColorPalette.textPrimary; font.pixelSize: 11 * App.fontScale; width: root._lw
                    }
                    Rectangle {
                        anchors {
                            left: parent.left; leftMargin: root._lm + root._lw
                            right: browseDirBtn.left; rightMargin: 6
                            verticalCenter: parent.verticalCenter
                        }
                        height: root._rh; color: ColorPalette.inputBg
                        border.color: saveDirField.activeFocus ? "#4488dd" : ColorPalette.border; radius: 2

                        TextInput {
                            id: saveDirField
                            anchors { fill: parent; leftMargin: 6; rightMargin: 6 }
                            verticalAlignment: TextInput.AlignVCenter
                            color: ColorPalette.textPrimary; font.pixelSize: 11 * App.fontScale; clip: true
                            enabled: !root._creating
                            Text {
                                anchors.fill: parent; verticalAlignment: Text.AlignVCenter
                                text: qsTr("Output folder…"); color: "#445566"; font: parent.font
                                visible: parent.text.length === 0 && !parent.activeFocus
                            }
                        }
                    }
                    Rectangle {
                        id: browseDirBtn
                        anchors { right: parent.right; rightMargin: root._rm; verticalCenter: parent.verticalCenter }
                        width: browseDirLbl.implicitWidth + 14; height: root._rh; radius: 2
                        color: browseDirMa.containsMouse ? ColorPalette.border : ColorPalette.dividerBg
                        border.color: "#4a4a4a"
                        Text { id: browseDirLbl; anchors.centerIn: parent; text: qsTr("Browse…"); color: ColorPalette.textPrimary; font.pixelSize: 11 * App.fontScale }
                        MouseArea {
                            id: browseDirMa; anchors.fill: parent; hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            enabled: !root._creating
                            onClicked: saveDirDialog.open()
                        }
                    }
                }

                // Name row
                Item {
                    width: parent.width; height: root._rh + 8
                    Text {
                        anchors { left: parent.left; leftMargin: root._lm; verticalCenter: parent.verticalCenter }
                        text: qsTr("Name:"); color: ColorPalette.textPrimary; font.pixelSize: 11 * App.fontScale; width: root._lw
                    }
                    Rectangle {
                        anchors {
                            left: parent.left; leftMargin: root._lm + root._lw
                            right: parent.right; rightMargin: root._rm
                            verticalCenter: parent.verticalCenter
                        }
                        height: root._rh; color: ColorPalette.inputBg
                        border.color: nameField.activeFocus ? "#4488dd" : ColorPalette.border; radius: 2
                        TextInput {
                            id: nameField
                            anchors { fill: parent; leftMargin: 6; rightMargin: 6 }
                            verticalAlignment: TextInput.AlignVCenter
                            color: ColorPalette.textPrimary; font.pixelSize: 11 * App.fontScale; clip: true
                            enabled: !root._creating
                            Text {
                                anchors.fill: parent; verticalAlignment: Text.AlignVCenter
                                text: qsTr("Torrent name (optional)")
                                color: "#445566"; font: parent.font
                                visible: parent.text.length === 0 && !parent.activeFocus
                            }
                        }
                    }
                }

                // Piece size row
                Item {
                    width: parent.width; height: ((root._rh + 8) + 32)
                    Text {
                        anchors { left: parent.left; leftMargin: root._lm; top: parent.top; topMargin: 4 }
                        text: qsTr("Piece size:"); color: ColorPalette.textPrimary; font.pixelSize: 11 * App.fontScale; width: root._lw
                    }
                    Column {
                        anchors { left: parent.left; leftMargin: root._lm + root._lw
                                  right: parent.right; rightMargin: root._rm; top: parent.top; topMargin: 2 }
                        spacing: 1

                        // Slider + value label
                        Row {
                            width: parent.width
                            spacing: 6

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                width: 44
                                text: {
                                    var sel = root._sliderPieceSizeBytes()
                                    return sel === 0 ? qsTr("Auto") : root._fmtBytes(sel)
                                }
                                color: ColorPalette.textSecond; font.pixelSize: 10 * App.fontScale
                                horizontalAlignment: Text.AlignRight
                            }

                            Slider {
                                id: pieceSizeSlider
                                width: parent.width - 44 - 6  // minus label width and spacing
                                from: 0; to: 11; stepSize: 1
                                snapMode: Slider.SnapAlways
                                value: 0
                                enabled: !root._creating
                                background: Rectangle {
                                    x: pieceSizeSlider.leftPadding
                                    y: pieceSizeSlider.topPadding + pieceSizeSlider.availableHeight / 2 - 2
                                    implicitWidth: 200; implicitHeight: 4
                                    width: pieceSizeSlider.availableWidth; height: 4
                                    radius: 2
                                    color: ColorPalette.dividerBg
                                    Rectangle {
                                        width: pieceSizeSlider.visualPosition * parent.width
                                        height: parent.height
                                        color: ColorPalette.textDisabled
                                        radius: 2
                                    }
                                }
                                handle: Rectangle {
                                    x: pieceSizeSlider.leftPadding + pieceSizeSlider.visualPosition
                                       * (pieceSizeSlider.availableWidth - width)
                                    y: pieceSizeSlider.topPadding + pieceSizeSlider.availableHeight / 2 - height / 2
                                    implicitWidth: 14; implicitHeight: 14
                                    radius: 7
                                    color: pieceSizeSlider.enabled
                                        ? (pieceSizeSlider.pressed ? ColorPalette.textMuted : "#777777")
                                        : "#555555"
                                    border.color: pieceSizeSlider.enabled
                                        ? (pieceSizeSlider.hovered ? ColorPalette.textSecond : "#777777")
                                        : ColorPalette.textDisabled
                                    border.width: 2
                                }
                            }
                        }

                        // Legend + estimate, indented to align with slider
                        Item {
                            width: parent.width; height: legendCol.implicitHeight
                            Column {
                                id: legendCol
                                anchors { left: parent.left; leftMargin: 50; right: parent.right }
                                spacing: 1

                                // Size legend
                                Row {
                                    id: legendRow
                                    width: parent.width
                                    Repeater {
                                        model: root._pieceSizeLabels
                                        Text {
                                            width: legendRow.width / 12
                                            text: modelData
                                            horizontalAlignment: Text.AlignHCenter
                                            color: "#556677"; font.pixelSize: 7 * App.fontScale
                                        }
                                    }
                                }

                                // Estimate
                                Text {
                                    width: parent.width
                                    visible: root._totalInputBytes > 0
                                    text: {
                                        var est = root._estimatedPieceCount()
                                        var eff = root._effectivePieceSize()
                                        var sel = root._sliderPieceSizeBytes()
                                        if (sel === 0)
                                            return qsTr("~%1 pieces × %2").arg(est).arg(root._fmtBytes(eff))
                                        return qsTr("%1 pieces × %2").arg(est).arg(root._fmtBytes(eff))
                                    }
                                    color: "#778899"; font.pixelSize: 10 * App.fontScale; elide: Text.ElideRight
                                }
                            }
                        }
                    }
                }

                // ── Properties ───────────────────────────────────────────
                Item {
                    width: parent.width; height: 24
                    Text {
                        anchors { left: parent.left; leftMargin: root._lm; verticalCenter: parent.verticalCenter }
                        text: qsTr("Properties"); color: ColorPalette.textPrimary; font.pixelSize: 11 * App.fontScale; font.weight: Font.Medium
                    }
                    Rectangle {
                        anchors { left: parent.left; right: parent.right
                                  leftMargin: root._lm; rightMargin: root._rm; bottom: parent.bottom }
                        height: 1; color: ColorPalette.border
                    }
                }

                // Trackers row
                Item {
                    width: parent.width; height: 80
                    Text {
                        anchors { left: parent.left; leftMargin: root._lm; top: parent.top; topMargin: 6 }
                        text: qsTr("Trackers:"); color: ColorPalette.textPrimary; font.pixelSize: 11 * App.fontScale; width: root._lw
                    }
                    Rectangle {
                        anchors {
                            left: parent.left; leftMargin: root._lm + root._lw
                            right: parent.right; rightMargin: root._rm
                            top: parent.top; topMargin: 4; bottom: parent.bottom; bottomMargin: 4
                        }
                        color: ColorPalette.inputBg
                        border.color: trackersField.activeFocus ? "#4488dd" : ColorPalette.border; radius: 2

                        Flickable {
                            id: trackerFlick
                            anchors { fill: parent; margins: 5 }
                            contentWidth: width; contentHeight: Math.max(trackersField.implicitHeight, height)
                            clip: true; flickableDirection: Flickable.VerticalFlick

                            TextEdit {
                                id: trackersField
                                // Fill the full viewport so clicks anywhere in the box land on the editor.
                                width: trackerFlick.width
                                height: Math.max(implicitHeight, trackerFlick.height)
                                color: ColorPalette.textPrimary; font.pixelSize: 11 * App.fontScale; font.family: "Consolas"
                                wrapMode: TextEdit.Wrap; enabled: !root._creating; selectByMouse: true

                                Text {
                                    anchors.fill: parent
                                    text: "udp://tracker.opentrackr.org:1337/announce"
                                    color: "#445566"; font: parent.font
                                    visible: parent.text.length === 0 && !parent.activeFocus
                                }
                            }
                        }
                    }
                }

                // Comment row
                Item {
                    width: parent.width; height: root._rh + 8
                    Text {
                        anchors { left: parent.left; leftMargin: root._lm; verticalCenter: parent.verticalCenter }
                        text: qsTr("Comment:"); color: ColorPalette.textPrimary; font.pixelSize: 11 * App.fontScale; width: root._lw
                    }
                    Rectangle {
                        anchors {
                            left: parent.left; leftMargin: root._lm + root._lw
                            right: parent.right; rightMargin: root._rm
                            verticalCenter: parent.verticalCenter
                        }
                        height: root._rh; color: ColorPalette.inputBg
                        border.color: commentField.activeFocus ? "#4488dd" : ColorPalette.border; radius: 2
                        TextInput {
                            id: commentField
                            anchors { fill: parent; leftMargin: 6; rightMargin: 6 }
                            verticalAlignment: TextInput.AlignVCenter
                            color: ColorPalette.textPrimary; font.pixelSize: 11 * App.fontScale; clip: true
                            enabled: !root._creating
                            Text {
                                anchors.fill: parent; verticalAlignment: Text.AlignVCenter
                                text: qsTr("Optional"); color: "#445566"; font: parent.font
                                visible: parent.text.length === 0 && !parent.activeFocus
                            }
                        }
                    }
                }

                // Web seeds row
                Item {
                    width: parent.width; height: 60
                    Text {
                        anchors { left: parent.left; leftMargin: root._lm; top: parent.top; topMargin: 6 }
                        text: qsTr("Web seeds:"); color: ColorPalette.textPrimary; font.pixelSize: 11 * App.fontScale; width: root._lw
                    }
                    Rectangle {
                        anchors {
                            left: parent.left; leftMargin: root._lm + root._lw
                            right: parent.right; rightMargin: root._rm
                            top: parent.top; topMargin: 4; bottom: parent.bottom; bottomMargin: 4
                        }
                        color: ColorPalette.inputBg
                        border.color: webSeedsField.activeFocus ? "#4488dd" : ColorPalette.border; radius: 2

                        Flickable {
                            id: seedFlick
                            anchors { fill: parent; margins: 5 }
                            contentWidth: width; contentHeight: Math.max(webSeedsField.implicitHeight, height)
                            clip: true; flickableDirection: Flickable.VerticalFlick

                            TextEdit {
                                id: webSeedsField
                                width: seedFlick.width
                                height: Math.max(implicitHeight, seedFlick.height)
                                color: ColorPalette.textPrimary; font.pixelSize: 11 * App.fontScale; font.family: "Consolas"
                                wrapMode: TextEdit.Wrap; enabled: !root._creating; selectByMouse: true

                                Text {
                                    anchors.fill: parent
                                    text: qsTr("One URL per line (optional)")
                                    color: "#445566"; font: parent.font
                                    visible: parent.text.length === 0 && !parent.activeFocus
                                }
                            }
                        }
                    }
                }

                // Private checkbox
                Item {
                    width: parent.width; height: 30
                    StyledCheckBox {
                        id: privateCheck
                        anchors { left: parent.left; leftMargin: root._lm + root._lw; verticalCenter: parent.verticalCenter }
                        text: qsTr("Private torrent (disables DHT and PeX)")
                        topPadding: 0; bottomPadding: 0
                        enabled: !root._creating
                        contentItem: Text {
                            leftPadding: privateCheck.indicator.width + 5
                            text: privateCheck.text; color: ColorPalette.textPrimary; font.pixelSize: 11 * App.fontScale
                            verticalAlignment: Text.AlignVCenter
                        }
                    }
                }

                // ── Progress bar ─────────────────────────────────────────
                Item {
                    width: parent.width; height: 36
                    visible: root._creating || root._done

                    Rectangle {
                        anchors { fill: parent; leftMargin: root._lm; rightMargin: root._rm; topMargin: 4; bottomMargin: 4 }
                        color: root._done ? (root._success ? "#0d1f0d" : "#1f0d0d") : "#0d1826"
                        border.color: root._done ? (root._success ? "#1a4a1a" : "#4a1a1a") : "#1e3a58"
                        radius: 3

                        Text {
                            anchors { left: parent.left; right: parent.right; top: parent.top; leftMargin: 8; rightMargin: 8; topMargin: 4 }
                            text: {
                                if (root._done && root._success)   return qsTr("✓Done ▶€” %1").arg(root._resultPath)
                                if (root._done && root._errorText) return qsTr("✗ Error: %1").arg(root._errorText)
                                if (root._done)                    return qsTr("Cancelled")
                                return qsTr("Hashing… %1%  (%2 pieces × %3)")
                                    .arg(root._progress).arg(root._pieceCount).arg(root._fmtBytes(root._pieceSize))
                            }
                            color: root._done ? (root._success ? "#66cc66" : "#cc6666") : "#7aabcc"
                            font.pixelSize: 10 * App.fontScale; elide: Text.ElideRight
                        }

                        Rectangle {
                            anchors { left: parent.left; right: parent.right; bottom: parent.bottom
                                      leftMargin: 6; rightMargin: 6; bottomMargin: 4 }
                            height: 4; radius: 2; color: "#1e2e3e"
                            visible: root._creating

                            Rectangle {
                                width: parent.width * root._progress / 100
                                height: parent.height; radius: parent.radius; color: "#4488dd"
                                Behavior on width { NumberAnimation { duration: 100 } }
                            }
                        }
                    }
                }
            }
        }

        // ── Footer ───────────────────────────────────────────────────────
        Rectangle {
            width: parent.width; height: 48; color: ColorPalette.cardBg

            Rectangle { width: parent.width; height: 1; color: ColorPalette.dividerBg }

            // Left: open-when-done checkbox.
            StyledCheckBox {
                id: openWhenDoneCheck
                anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
                text: qsTr("Open when done")
                topPadding: 0; bottomPadding: 0
                contentItem: Text {
                    leftPadding: openWhenDoneCheck.indicator.width + 5
                    text: openWhenDoneCheck.text; color: ColorPalette.textSecond; font.pixelSize: 11 * App.fontScale
                    verticalAlignment: Text.AlignVCenter
                }
            }

            // Right: action buttons.
            Row {
                anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
                spacing: 8

                DlgButton {
                    text: root._creating ? qsTr("Cancel") : qsTr("Close")
                    onClicked: { if (root._creating) App.cancelCreateTorrent(); root.close() }
                }

                DlgButton {
                    primary: true
                    text: root._creating ? qsTr("Creating…")
                        : (root._done && root._success ? qsTr("Open Torrent") : qsTr("Create Torrent"))
                    enabled: !root._creating
                        && (root._done && root._success ? true
                            : inputFilesModel.count > 0 && saveDirField.text.trim().length > 0)
                    onClicked: {
                        if (root._done && root._success)
                            root.openTorrentRequested(root._resultPath)
                        else
                            root._startCreation()
                    }
                }
            }
        }
    }

    signal openTorrentRequested(string torrentFilePath)
}
