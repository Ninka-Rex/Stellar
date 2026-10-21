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

// "Add trackers" / "Add web seeds" for one torrent: paste URLs one per line.
// The tracker variant can also pull a µTorrent-compatible list from a URL and
// append it to the box for review before adding.
Window {
    id: root

    // "trackers" or "webSeeds"; set through openFor().
    property string mode: "trackers"
    property string downloadId: ""
    readonly property bool trackerMode: mode === "trackers"

    // Fired after Add with how many URLs the torrent accepted.
    signal added(string mode, int count)

    title: trackerMode ? qsTr("Add trackers") : qsTr("Add web seeds")
    width: 460
    height: trackerMode ? 340 : 280
    minimumWidth: 360
    minimumHeight: 220
    color: ColorPalette.cardBg
    flags: Qt.Dialog | Qt.WindowTitleHint | Qt.WindowCloseButtonHint
    modality: Qt.ApplicationModal

    Material.theme: ColorPalette.materialTheme
    Material.foreground: ColorPalette.textPrimary
    Material.background: ColorPalette.materialBg
    Material.accent: ColorPalette.accent

    property bool _fetching: false
    property string _status: ""
    property bool _statusIsError: false

    function openFor(newMode, id) {
        mode = newMode
        downloadId = id
        urlsInput.clear()
        listUrlField.clear()
        _fetching = false
        _status = ""
        var owner = transientParent
        if (owner) {
            x = owner.x + Math.round((owner.width - width) / 2)
            y = owner.y + Math.round((owner.height - height) / 2)
        }
        show()
        raise()
        requestActivate()
        urlsInput.forceActiveFocus()
    }

    function _lines() {
        var out = []
        var raw = urlsInput.text.split(/\r?\n/)
        for (var i = 0; i < raw.length; ++i) {
            var u = raw[i].trim()
            if (u.length > 0 && u[0] !== "#")
                out.push(u)
        }
        return out
    }

    function _add() {
        if (downloadId.length === 0) return
        var lines = _lines()
        var ok = 0, failed = 0
        for (var i = 0; i < lines.length; ++i) {
            var accepted = trackerMode ? App.addTorrentTracker(downloadId, lines[i])
                                       : App.addTorrentWebSeed(downloadId, lines[i])
            accepted ? ok++ : failed++
        }
        if (ok > 0) root.added(mode, ok)
        if (failed === 0) {
            close()
            return
        }
        _statusIsError = true
        _status = qsTr("%1 added, %2 rejected").arg(ok).arg(failed)
    }

    Connections {
        target: App
        function onTrackerListFetched(url, trackers, error) {
            if (!root._fetching || url !== listUrlField.text) return
            root._fetching = false
            if (error.length > 0) {
                root._statusIsError = true
                root._status = error
                return
            }
            // Append below what's already there, skipping duplicates.
            var existing = {}
            var current = root._lines()
            for (var i = 0; i < current.length; ++i) existing[current[i]] = true
            var fresh = trackers.filter(function(t) { return !existing[t] })
            if (fresh.length > 0) {
                var text = urlsInput.text.replace(/\s+$/, "")
                urlsInput.text = (text.length > 0 ? text + "\n" : "") + fresh.join("\n")
            }
            root._statusIsError = false
            root._status = qsTr("Trackers loaded: %1").arg(fresh.length)
        }
    }

    Shortcut { sequence: "Escape"; onActivated: root.close() }

    ColumnLayout {
        anchors { fill: parent; margins: 12 }
        spacing: 6

        Text {
            text: root.trackerMode ? qsTr("List of trackers to add (one per line):")
                                   : qsTr("List of web seeds to add (one per line):")
            color: ColorPalette.textPrimary
            font.pixelSize: 12 * App.fontScale
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            color: ColorPalette.inputBg
            border.color: urlsInput.activeFocus ? ColorPalette.borderFocus : ColorPalette.border
            radius: 2
            clip: true

            ScrollView {
                anchors.fill: parent
                TextArea {
                    id: urlsInput
                    placeholderText: root.trackerMode
                        ? "udp://tracker.opentrackr.org:1337/announce"
                        : "https://example.com/files/"
                    placeholderTextColor: ColorPalette.textDisabled
                    color: ColorPalette.textPrimary
                    font.pixelSize: 12 * App.fontScale
                    font.family: "Consolas, monospace"
                    wrapMode: TextArea.NoWrap
                    selectByMouse: true
                    background: null
                    padding: 6
                }
            }
        }

        Text {
            visible: root.trackerMode
            Layout.topMargin: 4
            text: qsTr("µTorrent compatible list URL:")
            color: ColorPalette.textPrimary
            font.pixelSize: 12 * App.fontScale
        }

        RowLayout {
            visible: root.trackerMode
            Layout.fillWidth: true
            spacing: 6

            TextField {
                id: listUrlField
                Layout.fillWidth: true
                implicitHeight: 30
                leftPadding: 6; topPadding: 0; bottomPadding: 0
                placeholderText: "https://"
                placeholderTextColor: ColorPalette.textDisabled
                color: ColorPalette.textPrimary
                font.pixelSize: 12 * App.fontScale
                selectByMouse: true
                enabled: !root._fetching
                background: Rectangle {
                    color: ColorPalette.inputBg
                    border.color: listUrlField.activeFocus ? ColorPalette.borderFocus : ColorPalette.border
                    radius: 2
                }
                Keys.onReturnPressed: fetchButton.clicked()
                Keys.onEnterPressed: fetchButton.clicked()
            }
            DlgButton {
                id: fetchButton
                implicitHeight: listUrlField.height
                text: qsTr("Download")
                enabled: !root._fetching && listUrlField.text.trim().length > 0
                onClicked: {
                    root._fetching = true
                    root._statusIsError = false
                    root._status = qsTr("Downloading list...")
                    App.fetchTrackerList(listUrlField.text)
                }
                ThemedToolTip {
                    visible: fetchButton.hovered
                    text: qsTr("Download the list and add its trackers to the box above")
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: 4
            spacing: 6

            Text {
                Layout.fillWidth: true
                text: root._status
                color: root._statusIsError ? ColorPalette.warningText : ColorPalette.textSecond
                font.pixelSize: 11 * App.fontScale
                elide: Text.ElideRight
            }
            DlgButton {
                text: qsTr("Add")
                primary: true
                enabled: urlsInput.text.trim().length > 0
                onClicked: root._add()
            }
            DlgButton {
                text: qsTr("Cancel")
                onClicked: root.close()
            }
        }
    }
}
