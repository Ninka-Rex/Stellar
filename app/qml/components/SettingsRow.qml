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

// "Label  [control]" row with an optional hint under the control.
//
// The label column is as wide as the longest label among the rows of the
// enclosing SettingsSection (see SettingsSection.rowLabelWidth), so a group of
// rows lines up without a fixed column leaving a gap after short labels, and a
// longer translation widens it automatically. A label too long to sit beside
// its control (or `stacked: true`, for wide controls like paths) goes above
// the control instead of squeezing it.
ColumnLayout {
    id: row

    property string label
    property string hint
    // Wide controls (paths, free text) read better with the label above.
    property bool stacked: false
    // Fixed label width; -1 = share the enclosing section's column.
    property int labelWidth: -1
    default property alias content: controls.data

    // Read by SettingsSection to size the shared label column.
    readonly property real labelImplicitWidth: measure.implicitWidth

    // Nearest ancestor that provides a shared label column.
    readonly property Item labelColumnOwner: {
        for (var p = parent; p; p = p.parent)
            if (p.rowLabelWidth !== undefined)
                return p
        return null
    }

    // Measured against the section's width, never the row's own: the row's width
    // follows the label column this decision feeds, and deciding from it lets
    // stacking and the column chase each other forever (the window hangs).
    readonly property bool isStacked: stacked
        || (label.length > 0 && labelColumnOwner !== null
            && labelColumnOwner.fitsBeside !== undefined
            && !labelColumnOwner.fitsBeside(measure.implicitWidth))
    readonly property real effectiveLabelWidth: labelWidth >= 0 ? labelWidth
        : (labelColumnOwner ? labelColumnOwner.rowLabelWidth : measure.implicitWidth)

    Layout.fillWidth: true
    spacing: 3

    // Unwrapped label width; invisible items take no space in layouts.
    Text {
        id: measure
        visible: false
        text: row.label
        font.pixelSize: 13 * App.fontScale
    }

    Text {
        Layout.fillWidth: true
        visible: row.isStacked && row.label.length > 0
        text: row.label
        color: row.enabled ? ColorPalette.textPrimary : ColorPalette.textDisabled
        font.pixelSize: 13 * App.fontScale
        wrapMode: Text.WordWrap
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: 12

        // Also shown with an empty label, so label-less rows keep the column.
        Text {
            visible: !row.isStacked
            Layout.preferredWidth: row.effectiveLabelWidth
            Layout.maximumWidth: row.effectiveLabelWidth
            Layout.alignment: Qt.AlignVCenter
            text: row.label
            color: row.enabled ? ColorPalette.textPrimary : ColorPalette.textDisabled
            font.pixelSize: 13 * App.fontScale
            wrapMode: Text.WordWrap
        }

        RowLayout {
            id: controls
            Layout.fillWidth: true
            spacing: 8
        }
    }

    SettingsHint {
        Layout.leftMargin: row.isStacked ? 0 : row.effectiveLabelWidth + 12
        visible: row.hint.length > 0
        text: row.hint
    }
}
