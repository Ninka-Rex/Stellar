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

// Embeddable per-torrent settings panel: bandwidth limits, share limits,
// peer discovery and download mode. Lives as a "Settings" tab inside the
// torrent properties / metadata dialogs (replaces the old standalone
// TorrentSpeedLimitDialog window). Host passes the DownloadItem via
// `torrentItem`; an "Apply" bar at the bottom commits all four groups.
Item {
    id: root

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

    // Self-contained checkbox row: box + label sit tight together. Built from
    // a Row + box Rectangle (NOT StyledCheckBox) so there's no Material content
    // spacing flinging the label across the panel.
    component InlineCheck: Item {
        id: chkRoot
        property bool checked: false
        property bool enabled: true
        property string label: ""
        property string subtext: ""
        signal toggled()
        implicitHeight: chkRow.implicitHeight

        Row {
            id: chkRow
            anchors.verticalCenter: parent.verticalCenter
            spacing: 7

            Rectangle {
                width: 14; height: 14; radius: 2
                anchors.verticalCenter: parent.verticalCenter
                color: chkRoot.checked ? "#4488dd" : ColorPalette.inputBg
                border.color: chkRoot.checked ? "#4488dd" : (chkRoot.enabled ? ColorPalette.border : "#2a2a2a")
                opacity: chkRoot.enabled ? 1.0 : 0.5
                Text {
                    visible: chkRoot.checked
                    anchors.centerIn: parent
                    text: "✓"; color: "#fff"; font.pixelSize: 9 * App.fontScale; font.bold: true
                }
            }
            Column {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 0
                Text { text: chkRoot.label; color: chkRoot.enabled ? ColorPalette.textPrimary : ColorPalette.textDisabled; font.pixelSize: 12 * App.fontScale }
                Text {
                    visible: chkRoot.subtext.length > 0
                    text: chkRoot.subtext; color: "#7a8a9a"; font.pixelSize: 10 * App.fontScale
                }
            }
        }

        // Parent owns the state: emit toggled with the would-be new value via
        // the `checked` arg pattern used by callers (onToggled reads `checked`,
        // which is still the OLD value here, matching the old StyledCheckBox
        // semantics where callers do `= !checked`).
        MouseArea {
            anchors.fill: parent
            enabled: chkRoot.enabled
            cursorShape: Qt.PointingHandCursor
            onClicked: chkRoot.toggled()
        }
    }

    // Apply bar anchored to bottom so it is never clipped.
    Rectangle {
        id: buttonBar
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
        height: 42
        color: ColorPalette.cardBg

        Rectangle {
            anchors { left: parent.left; right: parent.right; top: parent.top }
            height: 1; color: ColorPalette.dividerBg
        }

        RowLayout {
            anchors { fill: parent; leftMargin: 12; rightMargin: 12; topMargin: 8; bottomMargin: 8 }
            spacing: 8
            Item { Layout.fillWidth: true }
            DlgButton {
                text: qsTr("Apply")
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

    // Content sits above the Apply bar. No ScrollView — everything fits in the
    // tab height; sections size to content and the last row absorbs slack so
    // there's no dead whitespace and nothing to scroll.
    ColumnLayout {
        anchors { left: parent.left; right: parent.right; top: parent.top; bottom: buttonBar.top; margins: 8 }
        spacing: 6

            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 6

                // Bandwidth limits
                Rectangle {
                    Layout.fillWidth: true
                    color: ColorPalette.cardBg; border.color: ColorPalette.dividerBg; radius: 3
                    implicitHeight: bwCol.implicitHeight + 12

                    ColumnLayout {
                        id: bwCol
                        anchors { fill: parent; margins: 6 }
                        spacing: 6

                        Text { text: qsTr("BANDWIDTH LIMITS"); color: ColorPalette.infoBoxText; font.pixelSize: 10 * App.fontScale; font.bold: true }

                        RowLayout {
                            Layout.fillWidth: true; spacing: 8
                            Text { text: qsTr("Download:"); color: ColorPalette.textSecond; font.pixelSize: 12 * App.fontScale; Layout.preferredWidth: 66 }
                            Rectangle {
                                Layout.preferredWidth: 86; height: 22; radius: 2
                                color: ColorPalette.inputBg; border.color: downInput.activeFocus ? "#4488dd" : ColorPalette.border
                                TextInput {
                                    id: downInput
                                    anchors { fill: parent; leftMargin: 6; rightMargin: 6 }
                                    verticalAlignment: TextInput.AlignVCenter
                                    validator: IntValidator { bottom: 0; top: 1048576 }
                                    color: ColorPalette.textPrimary; font.pixelSize: 12 * App.fontScale; selectByMouse: true
                                    onTextChanged: { var n = parseInt(text, 10); root._editDown = isNaN(n) ? 0 : Math.max(0, n) }
                                }
                            }
                            Text { text: "KB/s"; color: "#666"; font.pixelSize: 12 * App.fontScale }
                            Item { Layout.preferredWidth: 8 }
                            Text { text: qsTr("Upload:"); color: ColorPalette.textSecond; font.pixelSize: 12 * App.fontScale; Layout.preferredWidth: 50 }
                            Rectangle {
                                Layout.preferredWidth: 86; height: 22; radius: 2
                                color: ColorPalette.inputBg; border.color: upInput.activeFocus ? "#4488dd" : ColorPalette.border
                                TextInput {
                                    id: upInput
                                    anchors { fill: parent; leftMargin: 6; rightMargin: 6 }
                                    verticalAlignment: TextInput.AlignVCenter
                                    validator: IntValidator { bottom: 0; top: 1048576 }
                                    color: ColorPalette.textPrimary; font.pixelSize: 12 * App.fontScale; selectByMouse: true
                                    onTextChanged: { var n = parseInt(text, 10); root._editUp = isNaN(n) ? 0 : Math.max(0, n) }
                                }
                            }
                            Text { text: "KB/s"; color: "#666"; font.pixelSize: 12 * App.fontScale }
                            Item { Layout.fillWidth: true }
                        }
                    }
                }

                // Share limits
                Rectangle {
                    Layout.fillWidth: true
                    color: ColorPalette.cardBg; border.color: ColorPalette.dividerBg; radius: 3
                    implicitHeight: shareCol.implicitHeight + 12

                    ColumnLayout {
                        id: shareCol
                        anchors { fill: parent; margins: 6 }
                        spacing: 5

                        Text { text: qsTr("SHARE LIMITS"); color: ColorPalette.infoBoxText; font.pixelSize: 10 * App.fontScale; font.bold: true }

                        RowLayout {
                            Layout.fillWidth: true; spacing: 6
                            Text { text: qsTr("Ratio:"); color: ColorPalette.textSecond; font.pixelSize: 12 * App.fontScale; Layout.preferredWidth: 82 }
                            Repeater {
                                model: [qsTr("Default"), qsTr("Unlimited"), qsTr("Set to")]
                                delegate: Rectangle {
                                    required property int index; required property string modelData
                                    height: 21; implicitWidth: rl.implicitWidth + 12; radius: 2
                                    color: root._ratioMode === index ? ColorPalette.selectionBg : ColorPalette.panelBg
                                    border.color: root._ratioMode === index ? "#4488dd" : ColorPalette.border
                                    Text { id: rl; anchors.centerIn: parent; text: modelData; font.pixelSize: 11 * App.fontScale
                                           color: root._ratioMode === index ? "#88aaee" : ColorPalette.textMuted }
                                    MouseArea { anchors.fill: parent; onClicked: root._ratioMode = index }
                                }
                            }
                            Rectangle {
                                visible: root._ratioMode === 2
                                Layout.preferredWidth: 64; height: 21; radius: 2
                                color: ColorPalette.inputBg; border.color: ratioInput.activeFocus ? "#4488dd" : ColorPalette.border
                                TextInput {
                                    id: ratioInput
                                    anchors { fill: parent; leftMargin: 6; rightMargin: 6 }
                                    verticalAlignment: TextInput.AlignVCenter
                                    text: root._ratioText
                                    validator: DoubleValidator { bottom: 0.0; top: 9999.0; decimals: 2; notation: DoubleValidator.StandardNotation }
                                    color: ColorPalette.textPrimary; font.pixelSize: 12 * App.fontScale; selectByMouse: true
                                    onTextChanged: root._ratioText = text
                                }
                            }
                            Item { Layout.fillWidth: true }
                        }

                        RowLayout {
                            Layout.fillWidth: true; spacing: 6
                            Text { text: qsTr("Seeding time:"); color: ColorPalette.textSecond; font.pixelSize: 12 * App.fontScale; Layout.preferredWidth: 82 }
                            Repeater {
                                model: [qsTr("Default"), qsTr("Unlimited"), qsTr("Set to")]
                                delegate: Rectangle {
                                    required property int index; required property string modelData
                                    height: 21; implicitWidth: sl.implicitWidth + 12; radius: 2
                                    color: root._seedMode === index ? ColorPalette.selectionBg : ColorPalette.panelBg
                                    border.color: root._seedMode === index ? "#4488dd" : ColorPalette.border
                                    Text { id: sl; anchors.centerIn: parent; text: modelData; font.pixelSize: 11 * App.fontScale
                                           color: root._seedMode === index ? "#88aaee" : ColorPalette.textMuted }
                                    MouseArea { anchors.fill: parent; onClicked: root._seedMode = index }
                                }
                            }
                            Rectangle {
                                visible: root._seedMode === 2
                                Layout.preferredWidth: 64; height: 21; radius: 2
                                color: ColorPalette.inputBg; border.color: seedInput.activeFocus ? "#4488dd" : ColorPalette.border
                                TextInput {
                                    id: seedInput
                                    anchors { fill: parent; leftMargin: 6; rightMargin: 6 }
                                    verticalAlignment: TextInput.AlignVCenter; text: root._seedText
                                    validator: IntValidator { bottom: 0; top: 999999 }
                                    color: ColorPalette.textPrimary; font.pixelSize: 12 * App.fontScale; selectByMouse: true
                                    onTextChanged: root._seedText = text
                                }
                            }
                            Text { visible: root._seedMode === 2; text: qsTr("min"); color: "#666"; font.pixelSize: 12 * App.fontScale }
                            Item { Layout.fillWidth: true }
                        }

                        RowLayout {
                            Layout.fillWidth: true; spacing: 6
                            Text { text: qsTr("Inactive time:"); color: ColorPalette.textSecond; font.pixelSize: 12 * App.fontScale; Layout.preferredWidth: 82 }
                            Repeater {
                                model: [qsTr("Default"), qsTr("Unlimited"), qsTr("Set to")]
                                delegate: Rectangle {
                                    required property int index; required property string modelData
                                    height: 21; implicitWidth: il.implicitWidth + 12; radius: 2
                                    color: root._inactiveMode === index ? ColorPalette.selectionBg : ColorPalette.panelBg
                                    border.color: root._inactiveMode === index ? "#4488dd" : ColorPalette.border
                                    Text { id: il; anchors.centerIn: parent; text: modelData; font.pixelSize: 11 * App.fontScale
                                           color: root._inactiveMode === index ? "#88aaee" : ColorPalette.textMuted }
                                    MouseArea { anchors.fill: parent; onClicked: root._inactiveMode = index }
                                }
                            }
                            Rectangle {
                                visible: root._inactiveMode === 2
                                Layout.preferredWidth: 64; height: 21; radius: 2
                                color: ColorPalette.inputBg; border.color: inactiveInput.activeFocus ? "#4488dd" : ColorPalette.border
                                TextInput {
                                    id: inactiveInput
                                    anchors { fill: parent; leftMargin: 6; rightMargin: 6 }
                                    verticalAlignment: TextInput.AlignVCenter; text: root._inactiveText
                                    validator: IntValidator { bottom: 0; top: 999999 }
                                    color: ColorPalette.textPrimary; font.pixelSize: 12 * App.fontScale; selectByMouse: true
                                    onTextChanged: root._inactiveText = text
                                }
                            }
                            Text { visible: root._inactiveMode === 2; text: qsTr("min"); color: "#666"; font.pixelSize: 12 * App.fontScale }
                            Item { Layout.fillWidth: true }
                        }
                    }
                }

                // Peer discovery + Download mode (side by side, equal height).
                Item {
                    Layout.fillWidth: true
                    implicitHeight: Math.max(pdCol.implicitHeight, dmCol.implicitHeight) + 12

                    Rectangle {
                        anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
                        width: (parent.width - 6) / 2
                        color: ColorPalette.cardBg; border.color: ColorPalette.dividerBg; radius: 3

                        ColumnLayout {
                            id: pdCol
                            anchors { fill: parent; margins: 6 }
                            spacing: 5

                            Text { text: qsTr("PEER DISCOVERY"); color: ColorPalette.infoBoxText; font.pixelSize: 10 * App.fontScale; font.bold: true }

                            InlineCheck {
                                Layout.fillWidth: true
                                label: qsTr("DHT"); subtext: qsTr("Distributed Hash Table")
                                checked: !root._editDisableDht
                                enabled: !root.torrentItem || !root.torrentItem.torrentIsPrivate
                                onToggled: root._editDisableDht = !root._editDisableDht
                            }
                            InlineCheck {
                                Layout.fillWidth: true
                                label: qsTr("PeX"); subtext: qsTr("Peer Exchange")
                                checked: !root._editDisablePex
                                enabled: !root.torrentItem || !root.torrentItem.torrentIsPrivate
                                onToggled: root._editDisablePex = !root._editDisablePex
                            }
                            InlineCheck {
                                Layout.fillWidth: true
                                label: qsTr("LSD"); subtext: qsTr("Local Service Discovery")
                                checked: !root._editDisableLsd
                                onToggled: root._editDisableLsd = !root._editDisableLsd
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
                                    Text { text: qsTr("⚠ Private torrent"); color: "#cc9955"; font.pixelSize: 11 * App.fontScale; font.bold: true }
                                    Text {
                                        Layout.fillWidth: true
                                        text: qsTr("DHT and PeX disabled by libtorrent.")
                                        color: "#a08040"; font.pixelSize: 10 * App.fontScale; wrapMode: Text.WordWrap
                                    }
                                }
                            }
                        }
                    }

                    Rectangle {
                        anchors { right: parent.right; top: parent.top; bottom: parent.bottom }
                        width: (parent.width - 6) / 2
                        color: ColorPalette.cardBg; border.color: ColorPalette.dividerBg; radius: 3

                        ColumnLayout {
                            id: dmCol
                            anchors { fill: parent; margins: 6 }
                            spacing: 5

                            Text { text: qsTr("DOWNLOAD MODE"); color: ColorPalette.infoBoxText; font.pixelSize: 10 * App.fontScale; font.bold: true }

                            InlineCheck {
                                Layout.fillWidth: true
                                label: qsTr("Sequential download")
                                subtext: qsTr("Pieces downloaded in order (piece 0 → last)")
                                checked: root._editSequential
                                onToggled: root._editSequential = !root._editSequential
                            }
                            InlineCheck {
                                Layout.fillWidth: true
                                label: qsTr("Prioritize first & last pieces")
                                subtext: qsTr("Front-loads header/footer for early playback")
                                checked: root._editFirstLastPieces
                                onToggled: root._editFirstLastPieces = !root._editFirstLastPieces
                            }
                        }
                    }
                }

                // Absorb leftover vertical space so sections stay top-packed
                // (no gaps stretched between them) in tall dialogs.
                Item { Layout.fillWidth: true; Layout.fillHeight: true }
            }
        }
}
