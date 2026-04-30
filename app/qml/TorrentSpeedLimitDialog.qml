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

    width:         560
    height:        460
    minimumWidth:  520
    minimumHeight: 420
    title:         "Torrent Settings"
    color:         "#1e1e1e"
    flags: Qt.Dialog | Qt.WindowTitleHint | Qt.WindowCloseButtonHint | Qt.WindowSystemMenuHint
    modality: Qt.NonModal

    Material.theme:      Material.Dark
    Material.background: "#1e1e1e"
    Material.accent:     "#4488dd"

    property var torrentItem: null

    property int    _editDown: 0
    property int    _editUp:   0
    property int    _ratioMode:    0
    property string _ratioText:    ""
    property int    _seedMode:     0
    property string _seedText:     ""
    property int    _inactiveMode: 0
    property string _inactiveText: ""
    property bool   _editDisableDht: false
    property bool   _editDisablePex: false
    property bool   _editDisableLsd: false
    property bool   _editSequential:      false
    property bool   _editFirstLastPieces: false

    readonly property bool _speedDirty:
        !!torrentItem && (
            (torrentItem.perTorrentDownLimitKBps | 0) !== _editDown ||
            (torrentItem.perTorrentUpLimitKBps   | 0) !== _editUp
        )
    readonly property bool _shareDirty:
        !!torrentItem && (
            _modeFromItem(torrentItem.torrentShareRatioLimit, "ratio")         !== _ratioMode    ||
            (_ratioMode === 2 && _textFromItem(torrentItem.torrentShareRatioLimit, "ratio") !== _ratioText) ||
            _modeFromItem(torrentItem.torrentSeedingTimeLimitMins, "seed")     !== _seedMode     ||
            (_seedMode === 2 && _textFromItem(torrentItem.torrentSeedingTimeLimitMins, "seed") !== _seedText) ||
            _modeFromItem(torrentItem.torrentInactiveSeedingTimeLimitMins, "inactive") !== _inactiveMode ||
            (_inactiveMode === 2 && _textFromItem(torrentItem.torrentInactiveSeedingTimeLimitMins, "inactive") !== _inactiveText)
        )
    readonly property bool _flagsDirty:
        !!torrentItem && (
            !!torrentItem.torrentDisableDht !== _editDisableDht ||
            !!torrentItem.torrentDisablePex !== _editDisablePex ||
            !!torrentItem.torrentDisableLsd !== _editDisableLsd
        )
    readonly property bool _modeDirty:
        !!torrentItem && (
            !!torrentItem.torrentSequential      !== _editSequential ||
            !!torrentItem.torrentFirstLastPieces !== _editFirstLastPieces
        )
    readonly property bool dirty: _speedDirty || _shareDirty || _flagsDirty || _modeDirty

    function _modeFromItem(v, type) {
        if (v < -1.5) return 1
        if (v < 0)    return 0
        return 2
    }
    function _textFromItem(v, type) {
        if (v < 0) return ""
        if (type === "ratio") return Number(v).toFixed(2)
        return String(Math.round(v))
    }

    onVisibleChanged:     if (visible) _reset()
    onTorrentItemChanged: _reset()

    Connections {
        target: root.torrentItem
        function onTorrentLimitsChanged() { if (!root.dirty) root._reset() }
        function onTorrentFlagsChanged()  { if (!root.dirty) root._reset() }
    }

    function _reset() {
        if (!torrentItem) return
        _editDown = torrentItem.perTorrentDownLimitKBps | 0
        _editUp   = torrentItem.perTorrentUpLimitKBps   | 0
        downInput.text = String(_editDown)
        upInput.text   = String(_editUp)
        _ratioMode    = _modeFromItem(torrentItem.torrentShareRatioLimit, "ratio")
        _ratioText    = _textFromItem(torrentItem.torrentShareRatioLimit, "ratio")
        _seedMode     = _modeFromItem(torrentItem.torrentSeedingTimeLimitMins, "seed")
        _seedText     = _textFromItem(torrentItem.torrentSeedingTimeLimitMins, "seed")
        _inactiveMode = _modeFromItem(torrentItem.torrentInactiveSeedingTimeLimitMins, "inactive")
        _inactiveText = _textFromItem(torrentItem.torrentInactiveSeedingTimeLimitMins, "inactive")
        _editDisableDht      = !!torrentItem.torrentDisableDht
        _editDisablePex      = !!torrentItem.torrentDisablePex
        _editDisableLsd      = !!torrentItem.torrentDisableLsd
        _editSequential      = !!torrentItem.torrentSequential
        _editFirstLastPieces = !!torrentItem.torrentFirstLastPieces
        if (ratioInput)    ratioInput.text    = _ratioText
        if (seedInput)     seedInput.text     = _seedText
        if (inactiveInput) inactiveInput.text = _inactiveText
    }

    component InlineCheck: RowLayout {
        id: chkRoot
        property alias checked: chk.checked
        property alias enabled: chk.enabled
        property string label: ""
        property string subtext: ""
        signal toggled()
        spacing: 7
        CheckBox {
            id: chk
            topPadding: 0; bottomPadding: 0
            onToggled: chkRoot.toggled()
            contentItem: Item {}
            indicator: Rectangle {
                implicitWidth: 14; implicitHeight: 14; radius: 2
                color: chk.checked ? "#4488dd" : "#1b1b1b"
                border.color: chk.checked ? "#4488dd" : (chk.enabled ? "#3a3a3a" : "#2a2a2a")
                opacity: chk.enabled ? 1.0 : 0.5
                Text {
                    visible: chk.checked
                    anchors.centerIn: parent
                    text: "✓"; color: "#fff"; font.pixelSize: 9; font.bold: true
                }
            }
        }
        ColumnLayout {
            Layout.fillWidth: true; spacing: 0
            Text { text: chkRoot.label; color: chk.enabled ? "#d0d0d0" : "#666666"; font.pixelSize: 12 }
            Text {
                visible: chkRoot.subtext.length > 0
                text: chkRoot.subtext; color: "#7a8a9a"; font.pixelSize: 10
            }
        }
    }

    // Header strip
    Rectangle {
        id: headerStrip
        anchors { left: parent.left; right: parent.right; top: parent.top }
        height: 44
        color: "#222228"

        RowLayout {
            anchors { fill: parent; leftMargin: 12; rightMargin: 12; topMargin: 7; bottomMargin: 7 }
            spacing: 10

            Image {
                Layout.preferredWidth: 26; Layout.preferredHeight: 26
                source: {
                    if (!root.torrentItem) return ""
                    var p = String(root.torrentItem.savePath || "").replace(/\\/g, "/")
                    var f = String(root.torrentItem.filename || "")
                    return (p && f) ? ("image://fileicon/" + p + "/" + f) : ""
                }
                sourceSize: Qt.size(26, 26); fillMode: Image.PreserveAspectFit; asynchronous: true
            }
            ColumnLayout {
                Layout.fillWidth: true; spacing: 1
                Text {
                    Layout.fillWidth: true
                    text: root.torrentItem ? root.torrentItem.filename : ""
                    color: "#e8e8e8"; font.pixelSize: 13; font.weight: Font.Medium; elide: Text.ElideMiddle
                }
                Text {
                    text: "Per-torrent speed, share limits, peer discovery, and download mode"
                    color: "#8899aa"; font.pixelSize: 10
                }
            }
        }
    }

    // Button bar — anchored to bottom so it is never clipped
    Rectangle {
        id: buttonBar
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
        height: 48
        color: "#1e1e1e"

        Rectangle {
            anchors { left: parent.left; right: parent.right; top: parent.top }
            height: 1; color: "#2d2d2d"
        }

        RowLayout {
            anchors { fill: parent; leftMargin: 12; rightMargin: 12; topMargin: 8; bottomMargin: 8 }
            spacing: 8
            Item { Layout.fillWidth: true }
            DlgButton {
                text: "Close"
                onClicked: root.close()
            }
            DlgButton {
                text: "Apply"
                primary: true
                enabled: root.dirty
                onClicked: {
                    if (!root.torrentItem) return
                    App.setTorrentSpeedLimits(root.torrentItem.id,
                                              Math.max(0, root._editDown),
                                              Math.max(0, root._editUp))
                    var ratio     = root._ratioMode === 0 ? -1.0
                                  : root._ratioMode === 1 ? -2.0
                                  : Math.max(0, parseFloat(root._ratioText) || 0.0)
                    var seedMins  = root._seedMode === 0 ? -1
                                  : root._seedMode === 1 ? -2
                                  : Math.max(0, parseInt(root._seedText, 10) || 0)
                    var inactMins = root._inactiveMode === 0 ? -1
                                  : root._inactiveMode === 1 ? -2
                                  : Math.max(0, parseInt(root._inactiveText, 10) || 0)
                    App.setTorrentShareLimits(root.torrentItem.id, ratio, seedMins, inactMins, -1)
                    App.setTorrentFlags(root.torrentItem.id,
                                        root._editDisableDht,
                                        root._editDisablePex,
                                        root._editDisableLsd)
                    App.setTorrentDownloadMode(root.torrentItem.id,
                                               root._editSequential,
                                               root._editFirstLastPieces)
                }
            }
        }
    }

    // Scrollable content area — sits between header and button bar
    ScrollView {
        anchors { left: parent.left; right: parent.right; top: headerStrip.bottom; bottom: buttonBar.top }
        contentWidth: availableWidth
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

        ColumnLayout {
            width: parent.width
            spacing: 0

            ColumnLayout {
                Layout.fillWidth: true
                Layout.margins: 10
                spacing: 8

                // ── Bandwidth limits ──────────────────────────────────────────
                Rectangle {
                    Layout.fillWidth: true
                    color: "#1a1a1a"; border.color: "#2d2d2d"; radius: 3
                    implicitHeight: bwCol.implicitHeight + 14

                    ColumnLayout {
                        id: bwCol
                        anchors { fill: parent; margins: 7 }
                        spacing: 7

                        Text { text: "BANDWIDTH LIMITS"; color: "#8899aa"; font.pixelSize: 10; font.bold: true }

                        RowLayout {
                            Layout.fillWidth: true; spacing: 8
                            Text { text: "Download:"; color: "#aaaaaa"; font.pixelSize: 12; Layout.preferredWidth: 66 }
                            Rectangle {
                                Layout.preferredWidth: 86; height: 22; radius: 2
                                color: "#1b1b1b"; border.color: downInput.activeFocus ? "#4488dd" : "#3a3a3a"
                                TextInput {
                                    id: downInput
                                    anchors { fill: parent; leftMargin: 6; rightMargin: 6 }
                                    verticalAlignment: TextInput.AlignVCenter
                                    validator: IntValidator { bottom: 0; top: 1048576 }
                                    color: "#d0d0d0"; font.pixelSize: 12; selectByMouse: true
                                    onTextChanged: { var n = parseInt(text, 10); root._editDown = isNaN(n) ? 0 : Math.max(0, n) }
                                }
                            }
                            Text { text: "KB/s"; color: "#666"; font.pixelSize: 12 }
                            Item { Layout.preferredWidth: 8 }
                            Text { text: "Upload:"; color: "#aaaaaa"; font.pixelSize: 12; Layout.preferredWidth: 50 }
                            Rectangle {
                                Layout.preferredWidth: 86; height: 22; radius: 2
                                color: "#1b1b1b"; border.color: upInput.activeFocus ? "#4488dd" : "#3a3a3a"
                                TextInput {
                                    id: upInput
                                    anchors { fill: parent; leftMargin: 6; rightMargin: 6 }
                                    verticalAlignment: TextInput.AlignVCenter
                                    validator: IntValidator { bottom: 0; top: 1048576 }
                                    color: "#d0d0d0"; font.pixelSize: 12; selectByMouse: true
                                    onTextChanged: { var n = parseInt(text, 10); root._editUp = isNaN(n) ? 0 : Math.max(0, n) }
                                }
                            }
                            Text { text: "KB/s"; color: "#666"; font.pixelSize: 12 }
                            Item { Layout.fillWidth: true }
                        }
                    }
                }

                // ── Share limits ──────────────────────────────────────────────
                Rectangle {
                    Layout.fillWidth: true
                    color: "#1a1a1a"; border.color: "#2d2d2d"; radius: 3
                    implicitHeight: shareCol.implicitHeight + 14

                    ColumnLayout {
                        id: shareCol
                        anchors { fill: parent; margins: 7 }
                        spacing: 7

                        Text { text: "SHARE LIMITS"; color: "#8899aa"; font.pixelSize: 10; font.bold: true }

                        RowLayout {
                            Layout.fillWidth: true; spacing: 6
                            Text { text: "Ratio:"; color: "#aaaaaa"; font.pixelSize: 12; Layout.preferredWidth: 100 }
                            Repeater {
                                model: ["Default", "Unlimited", "Set to"]
                                delegate: Rectangle {
                                    required property int index; required property string modelData
                                    height: 21; implicitWidth: rl.implicitWidth + 12; radius: 2
                                    color: root._ratioMode === index ? "#1a3a6a" : "#252525"
                                    border.color: root._ratioMode === index ? "#4488dd" : "#3a3a3a"
                                    Text { id: rl; anchors.centerIn: parent; text: modelData; font.pixelSize: 11
                                           color: root._ratioMode === index ? "#88aaee" : "#888888" }
                                    MouseArea { anchors.fill: parent; onClicked: root._ratioMode = index }
                                }
                            }
                            Rectangle {
                                visible: root._ratioMode === 2
                                Layout.preferredWidth: 64; height: 21; radius: 2
                                color: "#1b1b1b"; border.color: ratioInput.activeFocus ? "#4488dd" : "#3a3a3a"
                                TextInput {
                                    id: ratioInput
                                    anchors { fill: parent; leftMargin: 6; rightMargin: 6 }
                                    verticalAlignment: TextInput.AlignVCenter
                                    text: root._ratioText
                                    validator: DoubleValidator { bottom: 0.0; top: 9999.0; decimals: 2; notation: DoubleValidator.StandardNotation }
                                    color: "#d0d0d0"; font.pixelSize: 12; selectByMouse: true
                                    onTextChanged: root._ratioText = text
                                }
                            }
                            Item { Layout.fillWidth: true }
                        }

                        RowLayout {
                            Layout.fillWidth: true; spacing: 6
                            Text { text: "Seeding time:"; color: "#aaaaaa"; font.pixelSize: 12; Layout.preferredWidth: 100 }
                            Repeater {
                                model: ["Default", "Unlimited", "Set to"]
                                delegate: Rectangle {
                                    required property int index; required property string modelData
                                    height: 21; implicitWidth: sl.implicitWidth + 12; radius: 2
                                    color: root._seedMode === index ? "#1a3a6a" : "#252525"
                                    border.color: root._seedMode === index ? "#4488dd" : "#3a3a3a"
                                    Text { id: sl; anchors.centerIn: parent; text: modelData; font.pixelSize: 11
                                           color: root._seedMode === index ? "#88aaee" : "#888888" }
                                    MouseArea { anchors.fill: parent; onClicked: root._seedMode = index }
                                }
                            }
                            Rectangle {
                                visible: root._seedMode === 2
                                Layout.preferredWidth: 64; height: 21; radius: 2
                                color: "#1b1b1b"; border.color: seedInput.activeFocus ? "#4488dd" : "#3a3a3a"
                                TextInput {
                                    id: seedInput
                                    anchors { fill: parent; leftMargin: 6; rightMargin: 6 }
                                    verticalAlignment: TextInput.AlignVCenter; text: root._seedText
                                    validator: IntValidator { bottom: 0; top: 999999 }
                                    color: "#d0d0d0"; font.pixelSize: 12; selectByMouse: true
                                    onTextChanged: root._seedText = text
                                }
                            }
                            Text { visible: root._seedMode === 2; text: "min"; color: "#666"; font.pixelSize: 12 }
                            Item { Layout.fillWidth: true }
                        }

                        RowLayout {
                            Layout.fillWidth: true; spacing: 6
                            Text { text: "Inactive time:"; color: "#aaaaaa"; font.pixelSize: 12; Layout.preferredWidth: 100 }
                            Repeater {
                                model: ["Default", "Unlimited", "Set to"]
                                delegate: Rectangle {
                                    required property int index; required property string modelData
                                    height: 21; implicitWidth: il.implicitWidth + 12; radius: 2
                                    color: root._inactiveMode === index ? "#1a3a6a" : "#252525"
                                    border.color: root._inactiveMode === index ? "#4488dd" : "#3a3a3a"
                                    Text { id: il; anchors.centerIn: parent; text: modelData; font.pixelSize: 11
                                           color: root._inactiveMode === index ? "#88aaee" : "#888888" }
                                    MouseArea { anchors.fill: parent; onClicked: root._inactiveMode = index }
                                }
                            }
                            Rectangle {
                                visible: root._inactiveMode === 2
                                Layout.preferredWidth: 64; height: 21; radius: 2
                                color: "#1b1b1b"; border.color: inactiveInput.activeFocus ? "#4488dd" : "#3a3a3a"
                                TextInput {
                                    id: inactiveInput
                                    anchors { fill: parent; leftMargin: 6; rightMargin: 6 }
                                    verticalAlignment: TextInput.AlignVCenter; text: root._inactiveText
                                    validator: IntValidator { bottom: 0; top: 999999 }
                                    color: "#d0d0d0"; font.pixelSize: 12; selectByMouse: true
                                    onTextChanged: root._inactiveText = text
                                }
                            }
                            Text { visible: root._inactiveMode === 2; text: "min"; color: "#666"; font.pixelSize: 12 }
                            Item { Layout.fillWidth: true }
                        }
                    }
                }

                // ── Peer discovery + Download mode (side by side, equal height) ──
                // Height driven by the taller column; both rects share that height.
                Item {
                    Layout.fillWidth: true
                    implicitHeight: Math.max(pdCol.implicitHeight, dmCol.implicitHeight) + 14

                    Rectangle {
                        anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
                        width: (parent.width - 8) / 2
                        color: "#1a1a1a"; border.color: "#2d2d2d"; radius: 3

                        ColumnLayout {
                            id: pdCol
                            anchors { fill: parent; margins: 7 }
                            spacing: 7

                            Text { text: "PEER DISCOVERY"; color: "#8899aa"; font.pixelSize: 10; font.bold: true }

                            InlineCheck {
                                Layout.fillWidth: true
                                label: "DHT"; subtext: "Distributed Hash Table"
                                checked: !root._editDisableDht
                                enabled: !root.torrentItem || !root.torrentItem.torrentIsPrivate
                                onToggled: root._editDisableDht = !checked
                            }
                            InlineCheck {
                                Layout.fillWidth: true
                                label: "PeX"; subtext: "Peer Exchange"
                                checked: !root._editDisablePex
                                enabled: !root.torrentItem || !root.torrentItem.torrentIsPrivate
                                onToggled: root._editDisablePex = !checked
                            }
                            InlineCheck {
                                Layout.fillWidth: true
                                label: "LSD"; subtext: "Local Service Discovery"
                                checked: !root._editDisableLsd
                                onToggled: root._editDisableLsd = !checked
                            }

                            Rectangle {
                                Layout.fillWidth: true
                                visible: !!root.torrentItem && root.torrentItem.torrentIsPrivate
                                color: "#1a1208"; border.color: "#6a4a00"; radius: 3
                                implicitHeight: pvtNote.implicitHeight + 10
                                ColumnLayout {
                                    id: pvtNote
                                    anchors { fill: parent; margins: 6 }
                                    spacing: 2
                                    Text { text: "🔒 Private torrent"; color: "#cc9955"; font.pixelSize: 11; font.bold: true }
                                    Text {
                                        Layout.fillWidth: true
                                        text: "DHT and PeX disabled by libtorrent."
                                        color: "#a08040"; font.pixelSize: 10; wrapMode: Text.WordWrap
                                    }
                                }
                            }
                        }
                    }

                    Rectangle {
                        anchors { right: parent.right; top: parent.top; bottom: parent.bottom }
                        width: (parent.width - 8) / 2
                        color: "#1a1a1a"; border.color: "#2d2d2d"; radius: 3

                        ColumnLayout {
                            id: dmCol
                            anchors { fill: parent; margins: 7 }
                            spacing: 7

                            Text { text: "DOWNLOAD MODE"; color: "#8899aa"; font.pixelSize: 10; font.bold: true }

                            InlineCheck {
                                Layout.fillWidth: true
                                label: "Sequential download"
                                subtext: "Pieces downloaded in order (piece 0 → last)"
                                checked: root._editSequential
                                onToggled: root._editSequential = checked
                            }
                            InlineCheck {
                                Layout.fillWidth: true
                                label: "Prioritize first & last pieces"
                                subtext: "Front-loads header/footer for early playback"
                                checked: root._editFirstLastPieces
                                onToggled: root._editFirstLastPieces = checked
                            }
                        }
                    }
                }
            }
        }
    }
}
