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
// `torrentItem`; the Apply button commits all four groups.
//
// Visual language matches the properties General tab: SectionHeader groups,
// muted keys, 26px fields, the shared StyledCheckBox / StyledComboBox.
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

    readonly property bool _isPrivate: !!torrentItem && torrentItem.torrentIsPrivate

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
        downField.text = String(_editDown)
        upField.text   = String(_editUp)
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
        // Typing replaces a field's text binding, so re-seed the text directly.
        ratioRow.fieldText    = _ratioText
        seedRow.fieldText     = _seedText
        inactiveRow.fieldText = _inactiveText
    }

    component Unit: Text {
        color: ColorPalette.textMuted
        font.pixelSize: 12 * App.fontScale
        Layout.alignment: Qt.AlignVCenter
    }

    // 26px numeric field (same height and border as the General tab fields).
    // `edited` only fires for user input, never for _reset()'s writes.
    component NumField: Rectangle {
        id: nf
        property alias text: nfInput.text
        property alias validator: nfInput.validator
        signal edited(string text)
        implicitWidth: 80
        implicitHeight: 26
        radius: 2
        color: ColorPalette.inputBg
        border.color: nfInput.activeFocus ? ColorPalette.borderFocus : ColorPalette.border
        opacity: enabled ? 1.0 : 0.5
        TextInput {
            id: nfInput
            anchors { fill: parent; leftMargin: 6; rightMargin: 6 }
            verticalAlignment: TextInput.AlignVCenter
            color: nf.enabled ? ColorPalette.textPrimary : ColorPalette.textDisabled
            font.pixelSize: 12 * App.fontScale
            selectByMouse: true
            clip: true
            onTextEdited: nf.edited(text)
        }
    }

    // One share-limit row: key, Default / Unlimited / Set to, and the value
    // field (only editable for "Set to"; kept in place otherwise so the rows
    // don't reflow when the mode changes).
    component LimitRow: RowLayout {
        id: lr
        property string label
        property int mode
        property string unit
        property alias fieldText: lrField.text
        property alias validator: lrField.validator
        signal modePicked(int mode)
        signal valueEdited(string text)
        Layout.fillWidth: true
        spacing: 8

        SheetKey { text: lr.label }
        StyledComboBox {
            id: lrCombo
            Layout.preferredWidth: 104 * App.fontScale
            implicitHeight: 26
            font.pixelSize: 12 * App.fontScale
            model: [qsTr("Default"), qsTr("Unlimited"), qsTr("Set to")]
            currentIndex: lr.mode
            onActivated: function(index) {
                lr.modePicked(index)
                // Selecting replaced the binding; hand control back to `mode`
                // so a later _reset() still moves the combo.
                currentIndex = Qt.binding(function() { return lr.mode })
            }
        }
        NumField {
            id: lrField
            implicitWidth: 64
            enabled: lr.mode === 2
            onEdited: function(text) { lr.valueEdited(text) }
        }
        Unit { text: lr.unit; visible: lr.unit.length > 0 }
        Item { Layout.fillWidth: true }
    }

    // Checkbox with a one-line muted explanation under its label. The parent
    // owns the state: `checked` is re-bound after each click so _reset() keeps
    // driving it.
    component OptionCheck: ColumnLayout {
        id: oc
        property alias text: ocBox.text
        property string description
        property bool value
        signal picked(bool value)
        Layout.fillWidth: true
        spacing: 0

        StyledCheckBox {
            id: ocBox
            Layout.fillWidth: true
            checked: oc.value
            onToggled: {
                oc.picked(checked)
                checked = Qt.binding(function() { return oc.value })
            }
        }
        Text {
            Layout.fillWidth: true
            Layout.leftMargin: ocBox.leftPadding + ocBox.indicator.width + 6
            visible: oc.description.length > 0
            text: oc.description
            color: ColorPalette.textMuted
            font.pixelSize: 11 * App.fontScale
            wrapMode: Text.WordWrap
            opacity: ocBox.enabled ? 1.0 : 0.6
        }
    }

    RowLayout {
        id: columns
        anchors { left: parent.left; right: parent.right; top: parent.top
                  leftMargin: 14; rightMargin: 14; topMargin: 8 }
        spacing: 24

        // Left: bandwidth + share limits.
        ColumnLayout {
            Layout.fillWidth: true
            Layout.preferredWidth: 1
            Layout.alignment: Qt.AlignTop
            spacing: 4

            SectionHeader { text: qsTr("Speed limits") }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                SheetKey { id: downKey; text: qsTr("Download") }
                NumField {
                    id: downField
                    validator: IntValidator { bottom: 0; top: 1048576 }
                    onEdited: function(text) { var n = parseInt(text, 10); root._editDown = isNaN(n) ? 0 : Math.max(0, n) }
                }
                Unit { text: "KB/s" }
                Item { Layout.fillWidth: true }
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                SheetKey { text: qsTr("Upload") }
                NumField {
                    id: upField
                    validator: IntValidator { bottom: 0; top: 1048576 }
                    onEdited: function(text) { var n = parseInt(text, 10); root._editUp = isNaN(n) ? 0 : Math.max(0, n) }
                }
                Unit { text: "KB/s" }
                Item { Layout.fillWidth: true }
            }
            Text {
                Layout.leftMargin: downKey.width + 8
                text: qsTr("0 = unlimited")
                color: ColorPalette.textMuted
                font.pixelSize: 11 * App.fontScale
            }

            SectionHeader { text: qsTr("Share limits"); Layout.topMargin: 7 }

            LimitRow {
                id: ratioRow
                label: qsTr("Ratio")
                mode: root._ratioMode
                validator: DoubleValidator { bottom: 0.0; top: 9999.0; decimals: 2; notation: DoubleValidator.StandardNotation }
                onModePicked: function(m) { root._ratioMode = m }
                onValueEdited: function(t) { root._ratioText = t }
            }
            LimitRow {
                id: seedRow
                label: qsTr("Seeding time")
                unit: qsTr("min")
                mode: root._seedMode
                validator: IntValidator { bottom: 0; top: 999999 }
                onModePicked: function(m) { root._seedMode = m }
                onValueEdited: function(t) { root._seedText = t }
            }
            LimitRow {
                id: inactiveRow
                label: qsTr("Inactive time")
                unit: qsTr("min")
                mode: root._inactiveMode
                validator: IntValidator { bottom: 0; top: 999999 }
                onModePicked: function(m) { root._inactiveMode = m }
                onValueEdited: function(t) { root._inactiveText = t }
            }
        }

        // Right: peer discovery + download mode.
        ColumnLayout {
            Layout.fillWidth: true
            Layout.preferredWidth: 1
            Layout.alignment: Qt.AlignTop
            spacing: 4

            SectionHeader { text: qsTr("Peer discovery") }

            OptionCheck {
                text: qsTr("DHT")
                description: qsTr("Distributed Hash Table")
                value: !root._editDisableDht
                enabled: !root._isPrivate
                onPicked: function(v) { root._editDisableDht = !v }
            }
            OptionCheck {
                text: qsTr("PeX")
                description: qsTr("Peer Exchange")
                value: !root._editDisablePex
                enabled: !root._isPrivate
                onPicked: function(v) { root._editDisablePex = !v }
            }
            OptionCheck {
                text: qsTr("LSD")
                description: qsTr("Local Service Discovery")
                value: !root._editDisableLsd
                onPicked: function(v) { root._editDisableLsd = !v }
            }
            Text {
                Layout.fillWidth: true
                visible: root._isPrivate
                text: qsTr("Private torrent: DHT and PeX are turned off.")
                color: ColorPalette.textMuted
                font.pixelSize: 11 * App.fontScale
                wrapMode: Text.WordWrap
            }

            SectionHeader { text: qsTr("Download mode"); Layout.topMargin: 7 }

            OptionCheck {
                text: qsTr("Sequential download")
                description: qsTr("Pieces downloaded in order (piece 0 → last)")
                value: root._editSequential
                onPicked: function(v) { root._editSequential = v }
            }
            OptionCheck {
                text: qsTr("Prioritize first & last pieces")
                description: qsTr("Front-loads header/footer for early playback")
                value: root._editFirstLastPieces
                onPicked: function(v) { root._editFirstLastPieces = v }
            }
        }
    }

    DlgButton {
        anchors { right: parent.right; bottom: parent.bottom; rightMargin: 14; bottomMargin: 10 }
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
