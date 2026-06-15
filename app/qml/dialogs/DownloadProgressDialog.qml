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

Window {
    id: root

    // Detach from the main window so Windows gives each progress dialog its own
    // taskbar button (IDM-style), instead of treating it as a transient child.
    transientParent: null

    flags: Qt.Window | Qt.WindowCloseButtonHint | Qt.WindowTitleHint | Qt.WindowMinimizeButtonHint

    signal minimizedToTray(string downloadId)
    signal openSettingsRequested(int page)

    property string downloadId: ""
    property var    item: null
    property bool   detailsVisible: true
    property bool   openFileWhenDone: false
    property bool   openFolderWhenDone: false
    property bool   shutdownWhenDone: false
    property bool   completionHandled: false
    // Latch the error detail so per-segment retries (which flip status
    // Error→Queued→Error repeatedly) don't show/hide the row each cycle,
    // bouncing the window up and down. Cleared once the download actually
    // resumes downloading or completes. `_latchedErrorString` keeps the text
    // stable while latched even if the live errorString momentarily clears.
    property bool   _errorLatched: false
    property string _latchedErrorString: ""
    // doneBytes snapshot taken when the error latched. The latch clears only
    // when bytes advance past this mark — i.e. the download genuinely resumed
    // receiving data — not on the transient Downloading flicker a retry emits
    // before failing again.
    property var    _errorBytesMark: 0
    property var    _pendingSegmentData: null
    property int    segmentRowLimit: Math.max(1, App.settings ? App.settings.perHostConnectionLimit : 8)

    width: 620
    minimumWidth: 440
    // Height is content-driven: window wraps the active layout exactly, so the
    // segment table never leaves empty space and tabs are never clipped.
    // Keep min/max loose so Qt doesn't fight transient mismatches while the
    // implicit height changes (was causing setGeometry warnings).
    minimumHeight: 150
    maximumHeight: 16777215
    height: rootCol.implicitHeight

    property bool _updatingSpeedUI: false

    function applyPerDownloadSpeed() {
        if (_updatingSpeedUI || !root.item || !root.downloadId) return
        if (limitThisChk.checked) {
            var kbps = parseInt(speedInput.text) || 0
            if (kbps > 0)
                App.setDownloadSpeedLimit(root.downloadId, kbps)
        } else {
            App.setDownloadSpeedLimit(root.downloadId, 0)
        }
    }

    function _normalizeSegmentData(data) {
        return data ? data : []
    }

    function _segmentRows(data) {
        var rows = _normalizeSegmentData(data)
        if (rows.length <= segmentRowLimit)
            return rows
        return rows.slice(rows.length - segmentRowLimit)
    }

    function syncSegmentList(data) {
        var next = _segmentRows(data)
        var oldCount = segmentListModel.count
        var newCount = next.length
        var shared = Math.min(oldCount, newCount)

        for (var i = 0; i < shared; ++i) {
            segmentListModel.set(i, next[i])
        }
        for (var j = oldCount - 1; j >= newCount; --j) {
            segmentListModel.remove(j)
        }
        for (var k = shared; k < newCount; ++k) {
            segmentListModel.append(next[k])
        }
    }

    function _centerOnOwner() {
        x = Math.round((Screen.width  - width)  / 2)
        y = Math.round((Screen.height - height) / 2)
    }

    onVisibleChanged: {
        if (visible) {
            _centerOnOwner()
            raise()
            requestActivate()
            _updateTaskbar()
        } else {
            App.setWindowTaskbarProgress(root, 0, 0)
        }
    }

    onItemChanged: {
        _updatingSpeedUI = true
        openFileWhenDone = false
        openFolderWhenDone = false
        shutdownWhenDone = false
        completionHandled = item && item.status === "Completed"
        _errorLatched = false
        _latchedErrorString = ""
        _updateErrorLatch()
        syncSegmentList(item ? item.segmentData : [])
        _pendingSegmentData = null
        if (item && item.speedLimitKBps > 0) {
            speedInput.text = String(item.speedLimitKBps)
            limitThisChk.checked = true
        } else {
            speedInput.text = ""
            limitThisChk.checked = false
        }
        _updatingSpeedUI = false
    }

    color: ColorPalette.cardBg

    title: {
        if (!item) return qsTr("Download")
        var pct = item.progress > 0 ? Math.round(item.progress * 100) + "% " : ""
        return pct + item.filename
    }

    Material.theme: ColorPalette.materialTheme
    Material.foreground: ColorPalette.textPrimary
    Material.background: ColorPalette.materialBg
    Material.accent: ColorPalette.accent

    function fmtBytes(b) {
        if (b === undefined || b === null || b < 0) return "--"
        if (b < 1024)       return b + " B"
        if (b < 1048576)    return (b / 1024).toFixed(1) + " KB"
        if (b < 1073741824) return (b / 1048576).toFixed(2) + " MB"
        return (b / 1073741824).toFixed(2) + " GB"
    }

    function fmtSpeed(bps) {
        if (!bps || bps <= 0) return "--"
        if (bps >= 1000000000) return (bps / 1000000000).toFixed(2) + " GB/s"
        if (bps >= 1000000)    return (bps / 1000000).toFixed(2) + " MB/s"
        if (bps >= 1000)       return (bps / 1000).toFixed(1) + " KB/s"
        return bps + " B/s"
    }

    // Shared status palette — matches FilePropertiesDialog header so both
    // dialogs read identically and stay legible in light + dark mode.
    function statusColor(s) {
        if (s === "Downloading") return ColorPalette.accent
        if (s === "Assembling")  return ColorPalette.accent
        if (s === "Paused")      return ColorPalette.dark ? "#b7b7b7" : "#666666"
        if (s === "Completed")   return ColorPalette.dark ? "#67bb7a" : "#2e7d32"
        if (s === "Error")       return ColorPalette.dark ? "#d97b7b" : "#c62828"
        return ColorPalette.textPrimary
    }

    function statusLabel() {
        if (!item)
            return "--"
        if (item.status === "Downloading")
            return qsTr("Receiving data...")
        if (item.status === "Assembling")
            return qsTr("Assembling...")
        if (item.status === "Paused" && item.progress > 0)
            return Math.round(item.progress * 100) + "%"
        return item.statusText
    }

    function handleCompletion() {
        if (!item || completionHandled || item.status !== "Completed")
            return
        completionHandled = true
        if (openFileWhenDone)
            App.openFile(item.id)
        if (openFolderWhenDone)
            App.openFolderSelectFile(item.id)
        if (shutdownWhenDone)
            App.shutdownComputer()
    }

    // Maintain the error-detail latch across retry status churn. Latch on
    // when an error is surfaced; clear only when the download genuinely makes
    // forward progress (Downloading) or finishes. Transient retry states
    // (Queued/Connecting/Paused) leave it untouched so the row stays put.
    function _clearErrorLatch() {
        _errorLatched = false
        _latchedErrorString = ""
    }

    function _updateErrorLatch() {
        if (!item) { _clearErrorLatch(); return }
        var s = item.status
        if (s === "Error") {
            // Latch on any Error — many failure paths set the status without an
            // errorString. Capture the message if present; a later
            // errorStringChanged refreshes it. Fall back to a generic line so
            // the row is never blank while showing the Error header.
            // Snapshot doneBytes: the latch only clears once bytes advance past
            // this, so the transient Downloading flicker during a retry (which
            // emits no new bytes before failing again) won't clear the row.
            _errorLatched = true
            _errorBytesMark = item.doneBytes
            _latchedErrorString = item.errorString !== ""
                ? item.errorString
                : qsTr("Download failed. The server may be unreachable or refusing the request.")
        } else if (s === "Completed") {
            _clearErrorLatch()
        }
        // Note: Downloading does NOT clear here — only real byte progress does
        // (see onDoneBytesChanged), so retries that briefly flip to Downloading
        // don't bounce the row.
    }

    // Push the download's progress + state onto this window's Windows taskbar
    // button (IDM-style). state: 0 none, 1 normal(green), 2 paused(yellow),
    // 3 error(red), 4 indeterminate.
    function _updateTaskbar() {
        if (!visible || !item) { App.setWindowTaskbarProgress(root, 0, 0); return }
        var s = item.status
        var state = 0
        if (s === "Downloading")      state = 1
        else if (s === "Assembling")  state = 4
        else if (s === "Paused")      state = 2
        else if (s === "Queued")      state = 2
        else if (s === "Error")       state = 3
        else                          state = 0   // Completed / other -> clear
        App.setWindowTaskbarProgress(root, item.progress, state)
    }

    Connections {
        target: item
        function onStatusChanged() {
            root.handleCompletion()
            root._updateTaskbar()
            root._updateErrorLatch()
        }
        function onDoneBytesChanged() {
            root._updateTaskbar()
            // Genuine resume: bytes advanced past the error mark → drop the row.
            if (root._errorLatched && item && item.doneBytes > root._errorBytesMark)
                root._clearErrorLatch()
        }
        function onErrorStringChanged() {
            // A real message arriving after the Error status replaces the
            // generic fallback while latched.
            if (root._errorLatched && item && item.errorString !== "")
                root._latchedErrorString = item.errorString
        }
        function onSegmentDataChanged() {
            var nextData = item ? item.segmentData : []
            if (segmentList.moving || segmentList.flicking || segmentList.dragging) {
                root._pendingSegmentData = nextData
            } else {
                root.syncSegmentList(nextData)
                root._pendingSegmentData = null
            }
        }
    }

    ListModel { id: segmentListModel }

    // Read-only selectable field (mirrors FilePropertiesDialog's inline component)
    component ReadOnlyField: Rectangle {
        property alias fieldText: ti.text
        property color textColor: ColorPalette.textPrimary
        implicitHeight: 26
        color: ColorPalette.inputBg
        border.color: ti.activeFocus ? ColorPalette.borderFocus : ColorPalette.border
        radius: 2
        clip: true
        TextInput {
            id: ti
            anchors { fill: parent; leftMargin: 6; rightMargin: 6 }
            verticalAlignment: TextInput.AlignVCenter
            color: parent.textColor
            font.pixelSize: 12 * App.fontScale
            readOnly: true; selectByMouse: true; clip: true
        }
    }

    ColumnLayout {
        id: rootCol
        anchors { left: parent.left; right: parent.right; top: parent.top }
        spacing: 0

        // ── Header bar (icon + name + status + live progress) ─────────────
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: hdrCol.implicitHeight + 8
            color: ColorPalette.headerStripBg
            border.width: 0
            radius: 0

            ColumnLayout {
                id: hdrCol
                anchors { fill: parent; leftMargin: 14; rightMargin: 14; topMargin: 4; bottomMargin: 4 }
                spacing: 4

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Image {
                        Layout.preferredWidth: 22; Layout.preferredHeight: 22
                        source: {
                            if (!root.item) return ""
                            var p = String(root.item.savePath || "").replace(/\\/g, "/")
                            var f = String(root.item.filename || "")
                            return (p && f) ? ("image://fileicon/" + p + "/" + f) : ""
                        }
                        sourceSize: Qt.size(22, 22)
                        fillMode: Image.PreserveAspectFit
                        asynchronous: true
                    }

                    Text {
                        text: root.item ? String(root.item.filename || "") : ""
                        color: ColorPalette.textHeader; font.pixelSize: 13 * App.fontScale; font.bold: true
                        elide: Text.ElideMiddle; Layout.fillWidth: true
                    }

                    Text {
                        text: root.statusLabel()
                        color: root.item ? root.statusColor(root.item.status) : ColorPalette.textHeader
                        font.pixelSize: 11 * App.fontScale; font.bold: true
                    }

                    Text {
                        readonly property string _eta: root.item ? String(root.item.timeLeft || "") : ""
                        visible: root.item && root.item.status === "Downloading" && _eta.length > 0
                        text: qsTr("ETA: %1").arg(_eta)
                        color: ColorPalette.textPrimary; font.pixelSize: 11 * App.fontScale
                        elide: Text.ElideRight
                    }
                }

                // Progress bar + live transfer
                RowLayout {
                    Layout.fillWidth: true; spacing: 8

                    Text {
                        text: {
                            if (!item) return "0%"
                            var pct = Math.round(item.progress * 100)
                            if (item.status === "Assembling") return qsTr("Assembling %1%").arg(pct)
                            return pct + "%"
                        }
                        color: ColorPalette.textHeader; font.pixelSize: 12 * App.fontScale; font.bold: true
                    }

                    Text {
                        visible: root.item && root.item.totalBytes > 0
                        text: root.item
                            ? root.fmtBytes(root.item.doneBytes) + " / " + root.fmtBytes(root.item.totalBytes)
                            : ""
                        color: ColorPalette.textHeader; font.pixelSize: 11 * App.fontScale
                    }

                    Rectangle {
                        id: progressBarRect
                        Layout.fillWidth: true; height: 5; radius: 2
                        color: ColorPalette.cardBg; border.color: ColorPalette.dividerBg
                        clip: true
                        Rectangle {
                            width: Math.max(0, parent.width * (item ? item.progress : 0))
                            height: parent.height; radius: parent.radius
                            color: (item && item.status === "Assembling") ? ColorPalette.progressGreen : ColorPalette.accent
                            Behavior on width { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                        }
                    }

                    Text {
                        text: "↓ " + (root.item ? root.fmtSpeed(root.item.speed) : "0 B/s")
                        color: ColorPalette.textHeader; font.pixelSize: 11 * App.fontScale
                    }

                    Text {
                        readonly property int _limit: {
                            if (!item) return 0
                            if (item.speedLimitKBps > 0) return item.speedLimitKBps
                            if (App.settings.speedLimiterEnabled && App.settings.globalSpeedLimitKBps > 0) return App.settings.globalSpeedLimitKBps
                            return 0
                        }
                        visible: _limit > 0
                        text: qsTr("(Limited %1)").arg(root.fmtSpeed(_limit * 1024))
                        color: ColorPalette.speedLimitText; font.pixelSize: 11 * App.fontScale
                    }
                }
            }
        }

        // ── Tab bar ──────────────────────────────────────────────────────
        Rectangle {
            Layout.fillWidth: true
            height: 34
            color: ColorPalette.panelBg

            // Bottom separator
            Rectangle {
                anchors.bottom: parent.bottom
                width: parent.width; height: 1
                color: ColorPalette.border
            }

            Row {
                anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
                spacing: 0

                Repeater {
                    model: [qsTr("Download status"), qsTr("Speed Limiter"), qsTr("Options on completion")]
                    delegate: Rectangle {
                        width: tabLbl.implicitWidth + 28
                        height: parent.height
                        color: tabStack.currentIndex === index
                               ? ColorPalette.cardBg
                               : (tabHover.containsMouse ? ColorPalette.hoverBg : "transparent")

                        Text {
                            id: tabLbl
                            anchors.centerIn: parent
                            text: modelData
                            color: tabStack.currentIndex === index ? ColorPalette.textHeader : ColorPalette.textSecond
                            font.pixelSize: 12 * App.fontScale
                            font.bold: tabStack.currentIndex === index
                        }

                        MouseArea {
                            id: tabHover
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: tabStack.currentIndex = index
                        }
                    }
                }
            }

            // ── Minimize-to-tray button flat, right-aligned in the tab bar ──
            Item {
                anchors { right: parent.right; top: parent.top; bottom: parent.bottom; rightMargin: 6 }
                width: minTrayLbl.implicitWidth + 20

                Text {
                    id: minTrayLbl
                    anchors.centerIn: parent
                    text: qsTr(">>  Send to Tray")
                    color: minTrayMa.containsMouse ? ColorPalette.accent : ColorPalette.textMuted
                    font.pixelSize: 12 * App.fontScale
                }

                ThemedToolTip {
                    visible: minTrayMa.containsMouse
                    text: qsTr("Minimize to system tray")
                    delay: 400
                }

                MouseArea {
                    id: minTrayMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        root.hide()
                        // Emit after hide so _updateDownloadsTray sees visible === false
                        Qt.callLater(function() { root.minimizedToTray(root.downloadId) })
                    }
                }
            }
        }

        // ── Tab pages ────────────────────────────────────────────────────
        StackLayout {
            id: tabStack
            Layout.fillWidth: true
            // Size to the ACTIVE tab (not the tallest) so the window wraps the
            // current page exactly — no slack below the Download-status buttons.
            Layout.preferredHeight: currentIndex === 0 ? tab0Col.implicitHeight + 14
                                  : currentIndex === 1 ? tab1Col.implicitHeight + 20
                                  : tab2Col.implicitHeight + 20

            // ── Tab 0: Download status ───────────────────────────────────
            Item {
                implicitHeight: tab0Col.implicitHeight
                ColumnLayout {
                    id: tab0Col
                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: 8; bottomMargin: 6 }
                    spacing: 5

                    // ── Details (plain selectable rows) ──────────────────
                    GridLayout {
                        id: infoGrid
                        Layout.fillWidth: true
                        Layout.topMargin: 2
                        columns: 2
                        columnSpacing: 14
                        rowSpacing: 7

                        Text {
                            text: qsTr("Address"); color: ColorPalette.textSecond
                            font.pixelSize: 12 * App.fontScale; font.bold: true
                            Layout.preferredWidth: 110; Layout.alignment: Qt.AlignTop
                        }
                        Text {
                            id: addrText
                            Layout.fillWidth: true
                            // preferredWidth:1 stops the (enormous) implicit text width
                            // from widening the grid column past the dialog; fillWidth
                            // then stretches it back to the available cell width, which
                            // is what elide measures against. These signed blob/CDN URLs
                            // are huge — show one line with a trailing ellipsis.
                            Layout.preferredWidth: 1
                            text: item ? item.url.toString() : "--"
                            color: addrMa.containsMouse ? ColorPalette.accentHover : ColorPalette.accent
                            font.pixelSize: 12 * App.fontScale
                            elide: Text.ElideRight
                            maximumLineCount: 1

                            MouseArea {
                                id: addrMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                acceptedButtons: Qt.LeftButton
                                onClicked: if (item) App.copyToClipboard(addrText.text)
                            }
                            ThemedToolTip {
                                visible: addrMa.containsMouse && addrText.text.length > 0 && addrText.text !== "--"
                                text: addrText.text + "\n\n" + qsTr("Click to copy")
                            }
                        }

                        Text {
                            text: qsTr("Save to"); color: ColorPalette.textSecond
                            font.pixelSize: 12 * App.fontScale; font.bold: true
                            Layout.preferredWidth: 110; Layout.alignment: Qt.AlignTop
                        }
                        Text {
                            id: saveText
                            Layout.fillWidth: true
                            Layout.preferredWidth: 1
                            text: {
                                if (!item) return "--"
                                var p = String(item.savePath || "").replace(/\//g, "\\")
                                var f = String(item.filename || "")
                                return p + ((p && f) ? "\\" : "") + f
                            }
                            color: saveMa.containsMouse ? ColorPalette.accent : ColorPalette.textPrimary
                            font.pixelSize: 12 * App.fontScale
                            elide: Text.ElideMiddle
                            maximumLineCount: 1

                            MouseArea {
                                id: saveMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                acceptedButtons: Qt.LeftButton
                                onClicked: if (item) App.copyToClipboard(saveText.text)
                            }
                            ThemedToolTip {
                                visible: saveMa.containsMouse && saveText.text.length > 0 && saveText.text !== "--"
                                text: saveText.text + "\n\n" + qsTr("Click to copy")
                            }
                        }

                        Text {
                            text: qsTr("Resume capability"); color: ColorPalette.textSecond
                            font.pixelSize: 12 * App.fontScale; font.bold: true
                            Layout.preferredWidth: 110
                        }
                        Text {
                            text: (item && item.resumeCapable) ? qsTr("Yes") : qsTr("No")
                            color: ColorPalette.textPrimary; font.pixelSize: 12 * App.fontScale; Layout.fillWidth: true
                        }

                        // ── Error detail row — latched across retries so the
                        //    row doesn't flicker (and bounce the window) while
                        //    status churns Error→Queued→Error during retries.
                        Text {
                            text: qsTr("Error detail")
                            color: ColorPalette.textSecond; font.pixelSize: 12 * App.fontScale; font.bold: true
                            visible: root._errorLatched
                            Layout.preferredWidth: 110; Layout.alignment: Qt.AlignTop
                        }
                        Text {
                            text: root._latchedErrorString
                            color: root.statusColor("Error")
                            font.pixelSize: 11 * App.fontScale
                            wrapMode: Text.WrapAnywhere
                            visible: root._errorLatched
                            Layout.fillWidth: true
                        }
                    }

                    // ── Buttons row ──────────────────────────────────────
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        // Hide/Show details
                        DlgButton {
                            text: root.detailsVisible ? qsTr("« Hide details") : qsTr("» Show details")
                            onClicked: root.detailsVisible = !root.detailsVisible
                        }

                        Item { Layout.fillWidth: true }

                        // Pause / Start
                        DlgButton {
                            text: (item && item.status === "Paused") ? qsTr("Start") : qsTr("Pause")
                            enabled: item !== null && (item.status === "Downloading" || item.status === "Paused" || item.status === "Queued")
                            opacity: enabled ? 1.0 : 0.4
                            onClicked: {
                                if (!item) return
                                if (item.status === "Downloading") App.pauseDownload(item.id)
                                else App.resumeDownload(item.id)
                            }
                        }

                        // Cancel
                        DlgButton {
                            text: qsTr("Cancel")
                            onClicked: root.close()
                        }
                    }

                    // ── Details section ──────────────────────────────────
                    ColumnLayout {
                        Layout.fillWidth: true
                        visible: root.detailsVisible
                        spacing: 4

                        // Label
                        Rectangle {
                            Layout.fillWidth: true
                            height: 16
                            color: ColorPalette.cardBg

                            Rectangle { width: parent.width; height: 1; color: ColorPalette.border }

                            Text {
                                anchors.centerIn: parent
                                text: qsTr("Start positions and download progress by connections")
                                color: ColorPalette.textDisabled
                                font.pixelSize: 11 * App.fontScale
                            }
                        }

                        // Segment visualizer
                        Rectangle {
                            Layout.fillWidth: true
                            height: 10
                            color: ColorPalette.panelBg
                            border.color: ColorPalette.border
                            radius: 3
                            clip: true

                            Repeater {
                                model: (item && item.segmentData) ? item.segmentData : []
                                delegate: Item {
                                    readonly property var  seg:   modelData
                                    readonly property real total: (item && item.totalBytes > 0) ? item.totalBytes : 1
                                    readonly property real segW:  (seg.endByte - seg.startByte + 1) / total * parent.width
                                    readonly property real segX:  seg.startByte / total * parent.width
                                    readonly property real fillW: seg.info === "Complete"
                                                                  ? segW
                                                                  : seg.received / Math.max(1, seg.endByte - seg.startByte + 1) * segW

                                    x: segX
                                    width: Math.max(1, segW)
                                    height: parent.height

                                    // Faint full-extent track so segments read as one
                                    // continuous bar (no gaps from unfilled regions)
                                    Rectangle {
                                        anchors.fill: parent
                                        color: ColorPalette.accent
                                        opacity: 0.22
                                    }
                                    // Downloaded portion
                                    Rectangle {
                                        width: Math.max(0, fillW); height: parent.height
                                        color: ColorPalette.accent
                                    }
                                    // Segment boundary tick
                                    Rectangle {
                                        anchors.right: parent.right
                                        width: 1; height: parent.height
                                        color: ColorPalette.panelBg; opacity: 0.6
                                    }
                                }
                            }
                        }

                        // Segment table — height reserved up front for the full
                        // per-host connection count so the window opens at its
                        // final size and never "pops out" as connections arrive.
                        // Real rows beyond this (dynamic segmentation) scroll
                        // inside the fixed area rather than resizing the window.
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 22 + Math.max(segmentRowLimit, segmentListModel.count) * 24 + 1
                            color: ColorPalette.windowBg
                            border.color: ColorPalette.border
                            radius: 3
                            clip: true

                            ColumnLayout {
                                anchors.fill: parent
                                spacing: 0

                                // Table header
                                Rectangle {
                                    Layout.fillWidth: true
                                    height: 22
                                    color: ColorPalette.panelBg

                                    Rectangle {
                                        anchors.bottom: parent.bottom
                                        width: parent.width; height: 1
                                        color: ColorPalette.border
                                    }

                                    Row {
                                        anchors { fill: parent; leftMargin: 8 }
                                        spacing: 0
                                        Text { width: 34;  text: qsTr("N.");         color: ColorPalette.textSecond; font.pixelSize: 11 * App.fontScale; font.bold: true; anchors.verticalCenter: parent.verticalCenter }
                                        Text { width: 110; text: qsTr("Downloaded"); color: ColorPalette.textSecond; font.pixelSize: 11 * App.fontScale; font.bold: true; anchors.verticalCenter: parent.verticalCenter }
                                        Text {             text: qsTr("Info");       color: ColorPalette.textSecond; font.pixelSize: 11 * App.fontScale; font.bold: true; anchors.verticalCenter: parent.verticalCenter }
                                    }
                                }

                                ListView {
                                    id: segmentList
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    clip: true
                                    model: segmentListModel
                                    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                                    onMovementEnded: {
                                        if (root._pendingSegmentData !== null) {
                                            root.syncSegmentList(root._pendingSegmentData)
                                            root._pendingSegmentData = null
                                        }
                                    }

                                    delegate: Rectangle {
                                        width: ListView.view.width
                                        height: 24
                                        color: index % 2 === 0 ? ColorPalette.windowBg : ColorPalette.rowAltBg

                                        Row {
                                            anchors { fill: parent; leftMargin: 8 }
                                            spacing: 0
                                            Text { width: 34;  text: (index + 1) + ".";       color: ColorPalette.textSecond;    font.pixelSize: 11 * App.fontScale; anchors.verticalCenter: parent.verticalCenter }
                                            Text { width: 110; text: root.fmtBytes(received); color: ColorPalette.textPrimary; font.pixelSize: 11 * App.fontScale; anchors.verticalCenter: parent.verticalCenter }
                                            Text {             text: info ?? "";              color: ColorPalette.textPrimary; font.pixelSize: 11 * App.fontScale; anchors.verticalCenter: parent.verticalCenter }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // ── Tab 1: Speed Limiter ─────────────────────────────────────
            Item {
                implicitHeight: tab1Col.implicitHeight + 20
                ColumnLayout {
                    id: tab1Col
                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: 10 }
                    spacing: 8

                    Text {
                        text: qsTr("Limit transfer rate for this download")
                        color: ColorPalette.textPrimary
                        font.pixelSize: 12 * App.fontScale
                        font.bold: true
                    }

                    StyledCheckBox {
                        id: limitThisChk
                        text: qsTr("Enable per-download limit")
                        enabled: !App.settings.speedLimiterEnabled
                        topPadding: 0
                        bottomPadding: 0
                        onCheckedChanged: root.applyPerDownloadSpeed()
                    }

                    RowLayout {
                        spacing: 8
                        opacity: (limitThisChk.checked && limitThisChk.enabled) ? 1.0 : 0.5
                        Label { text: qsTr("Maximum:") }
                        TextField {
                            id: speedInput
                            placeholderText: qsTr("e.g. 100")
                            implicitWidth: 90
                            implicitHeight: 26
                            enabled: limitThisChk.enabled
                            validator: IntValidator { bottom: 0; top: 999999 }
                            onTextEdited: root.applyPerDownloadSpeed()
                            color: ColorPalette.textPrimary
                            placeholderTextColor: ColorPalette.textDisabled
                            font.pixelSize: 12 * App.fontScale
                            leftPadding: 6; topPadding: 0; bottomPadding: 0
                            verticalAlignment: TextInput.AlignVCenter
                            background: Rectangle {
                                color: ColorPalette.inputBg
                                border.color: speedInput.activeFocus ? ColorPalette.borderFocus : ColorPalette.border
                                radius: 2
                            }
                        }
                        Label { text: qsTr("KB/s") }
                    }

                    Rectangle { Layout.fillWidth: true; height: 1; color: ColorPalette.border }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 12

                        Text {
                            text: App.settings.speedLimiterEnabled
                                ? (App.settings.globalSpeedLimitKBps > 0 ? qsTr("Global limit active: %1 KB/s").arg(App.settings.globalSpeedLimitKBps) : qsTr("Global limit active: unlimited"))
                                : qsTr("No global limit set")
                            color: App.settings.speedLimiterEnabled ? ColorPalette.speedLimitText : ColorPalette.textDisabled
                            font.pixelSize: 11 * App.fontScale
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }

                        Text {
                            text: qsTr("Global speed limiter settings…")
                            color: ColorPalette.accent
                            font.pixelSize: 11 * App.fontScale
                            font.underline: true

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.openSettingsRequested(4)  // Speed Limiter tab
                            }
                        }
                    }
                }
            }

            // ── Tab 2: Options on completion ─────────────────────────────
            Item {
                implicitHeight: tab2Col.implicitHeight + 20
                ColumnLayout {
                    id: tab2Col
                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: 10 }
                    spacing: 8
                    Text {
                        text: qsTr("Options On Completion")
                        color: ColorPalette.textPrimary
                        font.pixelSize: 12 * App.fontScale
                        font.bold: true
                    }
                    StyledCheckBox {
                        text: qsTr("Open file when done")
                        checked: root.openFileWhenDone
                        topPadding: 0
                        bottomPadding: 0
                        onToggled: root.openFileWhenDone = checked
                    }
                    StyledCheckBox {
                        text: qsTr("Open folder when done")
                        checked: root.openFolderWhenDone
                        topPadding: 0
                        bottomPadding: 0
                        onToggled: root.openFolderWhenDone = checked
                    }
                    StyledCheckBox {
                        text: qsTr("Shutdown computer when done")
                        checked: root.shutdownWhenDone
                        topPadding: 0
                        bottomPadding: 0
                        onToggled: root.shutdownWhenDone = checked
                    }
                    Text {
                        Layout.fillWidth: true
                        text: qsTr("These options are temporary for this download only and start unchecked each time.")
                        color: ColorPalette.textSecond
                        font.pixelSize: 11 * App.fontScale
                        wrapMode: Text.WordWrap
                    }
                }
            }
        }
    }
}
