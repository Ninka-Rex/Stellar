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

// Scrolling body of a settings page. Children stack vertically at full width
// with the page's standard padding; the scrollbar sits at the window edge,
// outside that padding.
ScrollView {
    id: scroll

    default property alias content: column.data

    Layout.fillWidth: true
    Layout.fillHeight: true
    clip: true
    contentWidth: availableWidth
    // The column is offset by the top padding, so the ScrollView cannot infer
    // the full height from its implicit size.
    contentHeight: column.implicitHeight + 30

    // Width from the viewport, not availableWidth: availableWidth shrinks while
    // the scrollbar shows, and rows reflow (stack) with width, which changes
    // the height and so whether the scrollbar shows. The right margin leaves
    // room for the scrollbar either way.
    ColumnLayout {
        id: column
        x: 16
        y: 14
        width: scroll.width - 32
        spacing: 20
    }
}
