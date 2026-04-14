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

// Per-torrent settings dialog.
//
// Set `torrentItem` before showing. Tracks clean/dirty state for speed limits,
// share limits, and peer-discovery flags so the Apply button reflects all edits.
Window {
    id: root

    width:         760
    height:        540
    minimumWidth:  700
    minimumHeight: 500
    title:         "Torrent Settings"
    color:         "#1e1e1e"
    flags: Qt.Dialog | Qt.WindowTitleHint | Qt.WindowCloseButtonHint | Qt.WindowSystemMenuHint
    modality: Qt.NonModal

    Material.theme:      Material.Dark
    Material.background: "#1e1e1e"
    Material.accent:     "#4488dd"

    // ── Public API ────────────────────────────────────────────────────────────
    property var torrentItem: null

    // ── Private edit state — speed limits ─────────────────────────────────────
    property int _editDown: 0
    property int _editUp:   0

    // ── Private edit state — share limits ────────────────────────────────────
    // mode: 0 = Default (use global), 1 = Unlimited, 2 = Set To
    property int    _ratioMode:    0
    property string _ratioText:    ""
    property int    _seedMode:     0
    property string _seedText:     ""
    property int    _inactiveMode: 0
    property string _inactiveText: ""
    property bool   _editDisableDht: false
    property bool   _editDisablePex: false
    property bool   _editDisableLsd: false

    // ── Dirty tracking ────────────────────────────────────────────────────────
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

    readonly property bool dirty: _speedDirty || _shareDirty || _flagsDirty

    // ── Helpers ───────────────────────────────────────────────────────────────
    // -1 = Default, -2 = Unlimited, >=0 = explicit value
    function _modeFromItem(v, type) {
        if (v < -1.5) return 1          // -2 = Unlimited
        if (v < 0)    return 0          // -1 = Default
        return 2                        // >=0 = Set To
    }
    function _textFromItem(v, type) {
        if (v < 0) return ""
        if (type === "ratio") return Number(v).toFixed(2)
        return String(Math.round(v))
    }

    // ── Lifecycle ─────────────────────────────────────────────────────────────
    onVisibleChanged:     if (visible) _reset()
    onTorrentItemChanged: _reset()

    Connections {
        target: root.torrentItem
        function onTorrentLimitsChanged() { if (!root.dirty) root._reset() }
        function onTorrentFlagsChanged() { if (!root.dirty) root._reset() }
    }

    function _reset() {
        if (!torrentItem) return

        // Speed limits
        _editDown = torrentItem.perTorrentDownLimitKBps | 0
        _editUp   = torrentItem.perTorrentUpLimitKBps   | 0
        downInput.text = String(_editDown)
        upInput.text   = String(_editUp)

        // Share limits
        _ratioMode    = _modeFromItem(torrentItem.torrentShareRatioLimit, "ratio")
        _ratioText    = _textFromItem(torrentItem.torrentShareRatioLimit, "ratio")
        _seedMode     = _modeFromItem(torrentItem.torrentSeedingTimeLimitMins, "seed")
        _seedText     = _textFromItem(torrentItem.torrentSeedingTimeLimitMins, "seed")
        _inactiveMode = _modeFromItem(torrentItem.torrentInactiveSeedingTimeLimitMins, "inactive")
        _inactiveText = _textFromItem(torrentItem.torrentInactiveSeedingTimeLimitMins, "inactive")
        _editDisableDht = !!torrentItem.torrentDisableDht
        _editDisablePex = !!torrentItem.torrentDisablePex
        _editDisableLsd = !!torrentItem.torrentDisableLsd

        if (ratioInput)    ratioInput.text    = _ratioText
        if (seedInput)     seedInput.text     = _seedText
        if (inactiveInput) inactiveInput.text = _inactiveText
    }

    // ── UI ────────────────────────────────────────────────────────────────────
    Rectangle {
        anchors { left: parent.left; right: parent.right; top: parent.top }
        height: 72
        color: "#222228"

        RowLayout {
            anchors {
                fill: parent
                leftMargin: 20; rightMargin: 20
                topMargin: 12; bottomMargin: 12
            }
            spacing: 14

            Item {
                width: 44
                height: 44

                Image {
                    anchors.centerIn: parent
                    width: 28
                    height: 28
                    source: {
                        if (!root.torrentItem) return ""
                        var p = String(root.torrentItem.savePath || "").replace(/\\/g, "/")
                        var f = String(root.torrentItem.filename || "")
                        return (p && f) ? ("image://fileicon/" + p + "/" + f) : ""
                    }
                    sourceSize: Qt.size(28, 28)
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 3

                Text {
                    Layout.fillWidth: true
                    text: root.torrentItem ? root.torrentItem.filename : ""
                    color: "#e8e8e8"
                    font.pixelSize: 15
                    font.weight: Font.Medium
                    elide: Text.ElideMiddle
                }
                Text {
                    Layout.fillWidth: true
                    text: "Per-torrent limits, share rules, and peer discovery"
                    color: "#8899aa"
                    font.pixelSize: 11
                    elide: Text.ElideRight
                }
            }
        }
    }

    ScrollView {
        anchors.fill: parent
        anchors.topMargin: 72
        contentWidth: availableWidth
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

        ColumnLayout {
            width: parent.width
            spacing: 0

            ColumnLayout {
                Layout.fillWidth: true
                Layout.margins: 14
                spacing: 10

                // Header — torrent name
                Rectangle {
                    visible: false
                    Layout.fillWidth: true
                    Layout.leftMargin: -14
                    Layout.rightMargin: -14
                    height: 0
                    color: "#222228"; border.color: "#2d2d2d"; radius: 0

                    RowLayout {
                        anchors {
                            fill: parent
                            leftMargin: 18; rightMargin: 18
                            topMargin: 12; bottomMargin: 12
                        }
                        spacing: 14

                        Rectangle {
                            visible: false
                            width: 0; height: 0; radius: 0
                            color: "#1c2430"; border.color: "#33455a"
                            Text {
                                anchors.centerIn: parent
                                text: "⚙"; font.pixelSize: 16; color: "#4488dd"
                            }
                        }
                        Item {
                            width: 44
                            height: 44

                            Image {
                                anchors.centerIn: parent
                                width: 28
                                height: 28
                                source: {
                                    if (!root.torrentItem) return ""
                                    var p = String(root.torrentItem.savePath || "").replace(/\\/g, "/")
                                    var f = String(root.torrentItem.filename || "")
                                    return (p && f) ? ("image://fileicon/" + p + "/" + f) : ""
                                }
                                sourceSize: Qt.size(28, 28)
                                fillMode: Image.PreserveAspectFit
                                asynchronous: true
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true; spacing: 3
                            Text {
                                Layout.fillWidth: true
                                text: root.torrentItem ? root.torrentItem.filename : ""
                                color: "#e8e8e8"; font.pixelSize: 15; font.weight: Font.Medium
                                elide: Text.ElideMiddle
                            }
                            Text {
                                Layout.fillWidth: true
                                text: "Per-torrent limits, share rules, and peer discovery"
                                color: "#8899aa"; font.pixelSize: 11
                                elide: Text.ElideRight
                            }
                        }
                    }
                }

                // ── Speed limits ─────────────────────────────────────────────
                Rectangle {
                    Layout.fillWidth: true
                    color: "#1e1e1e"; border.color: "#2d2d2d"; radius: 4
                    implicitHeight: limitsCol.implicitHeight + 20

                    ColumnLayout {
                        id: limitsCol
                        anchors { fill: parent; margins: 10 }
                        spacing: 10

                        Text {
                            text: "BANDWIDTH LIMITS"
                            color: "#8899aa"; font.pixelSize: 10; font.bold: true
                        }

                        GridLayout {
                            Layout.fillWidth: true
                            columns: 6
                            columnSpacing: 10
                            rowSpacing: 8

                            Text { text: "Download"; color: "#8899aa"; font.pixelSize: 12 }
                            TextField {
                                id: downInput
                                Layout.preferredWidth: 110
                                validator: IntValidator { bottom: 0; top: 1048576 }
                                text: String(root._editDown)
                                color: "#d0d0d0"; font.pixelSize: 12
                                leftPadding: 6; rightPadding: 6; selectByMouse: true
                                background: Rectangle {
                                    color: "#1b1b1b"
                                    border.color: parent.activeFocus ? "#4488dd" : "#3a3a3a"; radius: 2
                                }
                                onTextChanged: {
                                    var n = parseInt(text, 10)
                                    root._editDown = isNaN(n) ? 0 : Math.max(0, n)
                                }
                            }
                            Text { text: "KB/s"; color: "#666"; font.pixelSize: 12 }
                            Text { text: "Upload"; color: "#8899aa"; font.pixelSize: 12 }
                            TextField {
                                id: upInput
                                Layout.preferredWidth: 110
                                validator: IntValidator { bottom: 0; top: 1048576 }
                                text: String(root._editUp)
                                color: "#d0d0d0"; font.pixelSize: 12
                                leftPadding: 6; rightPadding: 6; selectByMouse: true
                                background: Rectangle {
                                    color: "#1b1b1b"
                                    border.color: parent.activeFocus ? "#4488dd" : "#3a3a3a"; radius: 2
                                }
                                onTextChanged: {
                                    var n = parseInt(text, 10)
                                    root._editUp = isNaN(n) ? 0 : Math.max(0, n)
                                }
                            }
                            Text { text: "KB/s"; color: "#666"; font.pixelSize: 12 }
                        }

                        Text {
                            text: "Set to 0 for no individual limit (global limit still applies)"
                            color: "#7f8a94"; font.pixelSize: 10
                            wrapMode: Text.WordWrap; Layout.fillWidth: true
                        }
                    }
                }

                // ── Share limits ─────────────────────────────────────────────
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    color: "#1e1e1e"; border.color: "#2d2d2d"; radius: 4
                    implicitHeight: shareCol.implicitHeight + 20

                    ColumnLayout {
                        id: shareCol
                        anchors { fill: parent; margins: 10 }
                        spacing: 10

                        Text {
                            text: "SHARE LIMITS"
                            color: "#8899aa"; font.pixelSize: 10; font.bold: true
                        }

                        // Ratio
                        ColumnLayout {
                            Layout.fillWidth: true; spacing: 6

                            Text { text: "Ratio limit"; color: "#c0c0c0"; font.pixelSize: 12 }

                            RowLayout {
                                Layout.fillWidth: true; spacing: 6

                                Repeater {
                                    model: ["Default", "Unlimited", "Set to"]
                                    delegate: Rectangle {
                                        required property int    index
                                        required property string modelData
                                        height: 24
                                        implicitWidth: modeLabel.implicitWidth + 16
                                        radius: 3
                                        color: root._ratioMode === index ? "#1a3a6a" : "#252525"
                                        border.color: root._ratioMode === index ? "#4488dd" : "#3a3a3a"
                                        Text {
                                            id: modeLabel
                                            anchors.centerIn: parent
                                            text: modelData
                                            color: root._ratioMode === index ? "#88aaee" : "#888888"
                                            font.pixelSize: 11
                                        }
                                        MouseArea {
                                            anchors.fill: parent
                                            onClicked: root._ratioMode = index
                                        }
                                    }
                                }

                                TextField {
                                    id: ratioInput
                                    visible: root._ratioMode === 2
                                    Layout.preferredWidth: 80
                                    text: root._ratioText
                                    color: "#d0d0d0"; font.pixelSize: 12
                                    leftPadding: 6; rightPadding: 6; selectByMouse: true
                                    validator: DoubleValidator { bottom: 0.0; top: 9999.0; decimals: 2; notation: DoubleValidator.StandardNotation }
                                    background: Rectangle {
                                        color: "#1b1b1b"
                                        border.color: parent.activeFocus ? "#4488dd" : "#3a3a3a"; radius: 2
                                    }
                                    onTextChanged: root._ratioText = text
                                }
                                Item { Layout.fillWidth: true }
                            }
                        }

                        Rectangle { Layout.fillWidth: true; height: 1; color: "#2a2a2a" }

                        // Seeding time
                        ColumnLayout {
                            Layout.fillWidth: true; spacing: 6

                            Text { text: "Seeding time limit"; color: "#c0c0c0"; font.pixelSize: 12 }

                            RowLayout {
                                Layout.fillWidth: true; spacing: 6

                                Repeater {
                                    model: ["Default", "Unlimited", "Set to"]
                                    delegate: Rectangle {
                                        required property int    index
                                        required property string modelData
                                        height: 24
                                        implicitWidth: seedModeLabel.implicitWidth + 16
                                        radius: 3
                                        color: root._seedMode === index ? "#1a3a6a" : "#252525"
                                        border.color: root._seedMode === index ? "#4488dd" : "#3a3a3a"
                                        Text {
                                            id: seedModeLabel
                                            anchors.centerIn: parent
                                            text: modelData
                                            color: root._seedMode === index ? "#88aaee" : "#888888"
                                            font.pixelSize: 11
                                        }
                                        MouseArea {
                                            anchors.fill: parent
                                            onClicked: root._seedMode = index
                                        }
                                    }
                                }

                                TextField {
                                    id: seedInput
                                    visible: root._seedMode === 2
                                    Layout.preferredWidth: 80
                                    text: root._seedText
                                    color: "#d0d0d0"; font.pixelSize: 12
                                    leftPadding: 6; rightPadding: 6; selectByMouse: true
                                    validator: IntValidator { bottom: 0; top: 999999 }
                                    background: Rectangle {
                                        color: "#1b1b1b"
                                        border.color: parent.activeFocus ? "#4488dd" : "#3a3a3a"; radius: 2
                                    }
                                    onTextChanged: root._seedText = text
                                }
                                Text {
                                    visible: root._seedMode === 2
                                    text: "min"; color: "#666"; font.pixelSize: 12
                                }
                                Item { Layout.fillWidth: true }
                            }
                        }

                        Rectangle { Layout.fillWidth: true; height: 1; color: "#2a2a2a" }

                        // Inactive seeding time
                        ColumnLayout {
                            Layout.fillWidth: true; spacing: 6

                            Text { text: "Inactive seeding time limit"; color: "#c0c0c0"; font.pixelSize: 12 }

                            RowLayout {
                                Layout.fillWidth: true; spacing: 6

                                Repeater {
                                    model: ["Default", "Unlimited", "Set to"]
                                    delegate: Rectangle {
                                        required property int    index
                                        required property string modelData
                                        height: 24
                                        implicitWidth: inactModeLabel.implicitWidth + 16
                                        radius: 3
                                        color: root._inactiveMode === index ? "#1a3a6a" : "#252525"
                                        border.color: root._inactiveMode === index ? "#4488dd" : "#3a3a3a"
                                        Text {
                                            id: inactModeLabel
                                            anchors.centerIn: parent
                                            text: modelData
                                            color: root._inactiveMode === index ? "#88aaee" : "#888888"
                                            font.pixelSize: 11
                                        }
                                        MouseArea {
                                            anchors.fill: parent
                                            onClicked: root._inactiveMode = index
                                        }
                                    }
                                }

                                TextField {
                                    id: inactiveInput
                                    visible: root._inactiveMode === 2
                                    Layout.preferredWidth: 80
                                    text: root._inactiveText
                                    color: "#d0d0d0"; font.pixelSize: 12
                                    leftPadding: 6; rightPadding: 6; selectByMouse: true
                                    validator: IntValidator { bottom: 0; top: 999999 }
                                    background: Rectangle {
                                        color: "#1b1b1b"
                                        border.color: parent.activeFocus ? "#4488dd" : "#3a3a3a"; radius: 2
                                    }
                                    onTextChanged: root._inactiveText = text
                                }
                                Text {
                                    visible: root._inactiveMode === 2
                                    text: "min"; color: "#666"; font.pixelSize: 12
                                }
                                Item { Layout.fillWidth: true }
                            }
                        }

                        Text {
                            text: "\"Default\" uses the global defaults set in Settings → Torrent."
                            color: "#7f8a94"; font.pixelSize: 10
                            wrapMode: Text.WordWrap; Layout.fillWidth: true
                        }
                    }
                }

                // ── Peer discovery flags ──────────────────────────────────────
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    color: "#1e1e1e"; border.color: "#2d2d2d"; radius: 4
                    implicitHeight: flagsCol.implicitHeight + 20

                    ColumnLayout {
                        id: flagsCol
                        anchors { fill: parent; margins: 10 }
                        spacing: 8

                        Text {
                            text: "PEER DISCOVERY"
                            color: "#8899aa"; font.pixelSize: 10; font.bold: true
                        }

                        // DHT
                        RowLayout {
                            Layout.fillWidth: true; spacing: 8
                            CheckBox {
                                id: dhtCheck
                                checked: !root._editDisableDht
                                enabled: !root.torrentItem || !root.torrentItem.torrentIsPrivate
                                onToggled: root._editDisableDht = !checked
                                contentItem: Item {}
                                indicator: Rectangle {
                                    implicitWidth: 16; implicitHeight: 16; radius: 3
                                    color: dhtCheck.checked ? "#4488dd" : "#1b1b1b"
                                    border.color: dhtCheck.checked ? "#4488dd" : "#3a3a3a"
                                    Text {
                                        visible: dhtCheck.checked
                                        anchors.centerIn: parent
                                        text: "✓"; color: "#fff"; font.pixelSize: 11; font.bold: true
                                    }
                                }
                            }
                            ColumnLayout {
                                Layout.fillWidth: true; spacing: 1
                                Text { text: "DHT (Distributed Hash Table)"; color: "#d0d0d0"; font.pixelSize: 12 }
                                Text { text: "Find peers via the distributed hash table network"; color: "#7a8a9a"; font.pixelSize: 10 }
                            }
                        }

                        // PeX
                        RowLayout {
                            Layout.fillWidth: true; spacing: 8
                            CheckBox {
                                id: pexCheck
                                checked: !root._editDisablePex
                                enabled: !root.torrentItem || !root.torrentItem.torrentIsPrivate
                                onToggled: root._editDisablePex = !checked
                                contentItem: Item {}
                                indicator: Rectangle {
                                    implicitWidth: 16; implicitHeight: 16; radius: 3
                                    color: pexCheck.checked ? "#4488dd" : "#1b1b1b"
                                    border.color: pexCheck.checked ? "#4488dd" : "#3a3a3a"
                                    Text {
                                        visible: pexCheck.checked
                                        anchors.centerIn: parent
                                        text: "✓"; color: "#fff"; font.pixelSize: 11; font.bold: true
                                    }
                                }
                            }
                            ColumnLayout {
                                Layout.fillWidth: true; spacing: 1
                                Text { text: "PeX (Peer Exchange)"; color: "#d0d0d0"; font.pixelSize: 12 }
                                Text { text: "Share peer lists with connected peers"; color: "#7a8a9a"; font.pixelSize: 10 }
                            }
                        }

                        // LSD
                        RowLayout {
                            Layout.fillWidth: true; spacing: 8
                            CheckBox {
                                id: lsdCheck
                                checked: !root._editDisableLsd
                                onToggled: root._editDisableLsd = !checked
                                contentItem: Item {}
                                indicator: Rectangle {
                                    implicitWidth: 16; implicitHeight: 16; radius: 3
                                    color: lsdCheck.checked ? "#4488dd" : "#1b1b1b"
                                    border.color: lsdCheck.checked ? "#4488dd" : "#3a3a3a"
                                    Text {
                                        visible: lsdCheck.checked
                                        anchors.centerIn: parent
                                        text: "✓"; color: "#fff"; font.pixelSize: 11; font.bold: true
                                    }
                                }
                            }
                            ColumnLayout {
                                Layout.fillWidth: true; spacing: 1
                                Text { text: "LSD (Local Service Discovery)"; color: "#d0d0d0"; font.pixelSize: 12 }
                                Text { text: "Find peers on your local network"; color: "#7a8a9a"; font.pixelSize: 10 }
                            }
                        }

                        // Private torrent notice
                        Rectangle {
                            Layout.fillWidth: true
                            visible: !!root.torrentItem && root.torrentItem.torrentIsPrivate
                            color: "#1a1208"; border.color: "#6a4a00"; radius: 4
                            implicitHeight: privateCol.implicitHeight + 12

                            ColumnLayout {
                                id: privateCol
                                anchors { fill: parent; margins: 8 }
                                spacing: 3

                                Text {
                                    text: "🔒 Private torrent"
                                    color: "#cc9955"; font.pixelSize: 12; font.bold: true
                                }
                                Text {
                                    Layout.fillWidth: true
                                    text: "This torrent was created with the private flag set by its tracker. "
                                        + "DHT and PeX are disabled automatically by libtorrent for private torrents, "
                                        + "regardless of the checkboxes above. Only the tracker's announced peers are used."
                                    color: "#a08040"; font.pixelSize: 10
                                    wrapMode: Text.WordWrap
                                }
                            }
                        }
                    }
                }

                // ── Buttons ───────────────────────────────────────────────────
                }
                RowLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: 14
                    Layout.rightMargin: 14
                    Layout.bottomMargin: 14
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

                            // Speed limits
                            App.setTorrentSpeedLimits(root.torrentItem.id,
                                                      Math.max(0, root._editDown),
                                                      Math.max(0, root._editUp))

                            // Share limits: convert mode back to storage values
                            // -1 = Default (inherit global), -2 = Unlimited, >=0 = explicit
                            var ratio    = root._ratioMode === 0 ? -1.0
                                         : root._ratioMode === 1 ? -2.0
                                         : Math.max(0, parseFloat(root._ratioText) || 0.0)
                            var seedMins = root._seedMode === 0 ? -1
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
                        }
                    }
                }
            }
        }
    }
}
