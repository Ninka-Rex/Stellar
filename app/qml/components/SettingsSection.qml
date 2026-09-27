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

// A titled group of settings: title with a hairline rule, an optional
// one-paragraph description, then the settings themselves.
ColumnLayout {
    id: section

    property string title
    property string description
    default property alias content: body.data

    // A label wider than this share of the section stacks above its control
    // instead of squeezing it. Depends only on the section's own width, which the
    // page sets — never on the rows — so layout converges.
    function fitsBeside(labelWidth) {
        return labelWidth <= width * 0.45
    }

    // Shared label column for the SettingsRows inside this section (at any
    // depth, e.g. inside a conditional ColumnLayout or a rule card): the widest
    // label among the rows that fit beside their control. Deliberately reads
    // only label text widths and the section width, not row geometry or row
    // state, so it cannot feed back into itself.
    readonly property real rowLabelWidth: {
        function widest(item) {
            var w = 0
            for (var i = 0; i < item.children.length; ++i) {
                var c = item.children[i]
                if (c.labelImplicitWidth !== undefined) {
                    if (c.labelWidth < 0 && !c.stacked && fitsBeside(c.labelImplicitWidth))
                        w = Math.max(w, c.labelImplicitWidth)
                } else {
                    w = Math.max(w, widest(c))
                }
            }
            return w
        }
        return Math.ceil(widest(body))
    }

    Layout.fillWidth: true
    spacing: 8

    SectionHeader {
        visible: section.title.length > 0
        text: section.title
        color: ColorPalette.textHeader
        font.pixelSize: 13 * App.fontScale
        font.bold: true
    }

    Text {
        Layout.fillWidth: true
        visible: section.description.length > 0
        text: section.description
        color: ColorPalette.textSecond
        font.pixelSize: 12 * App.fontScale
        wrapMode: Text.WordWrap
    }

    ColumnLayout {
        id: body
        Layout.fillWidth: true
        Layout.topMargin: 2
        spacing: 8
    }
}
