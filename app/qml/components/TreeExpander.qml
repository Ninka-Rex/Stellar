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

// Expand/collapse arrow for tree rows (torrent file trees, channel rows).
// Solid triangles drawn for 16px; the text glyphs (▸ ▾) they replace rendered
// tiny and at mismatched sizes depending on the font.
Image {
    property bool expanded: false
    width: 16
    height: 16
    sourceSize: Qt.size(16, 16)
    source: expanded ? "../icons/status/tree-expander-open.svg" : "../icons/status/tree-expander-closed.svg"
    fillMode: Image.PreserveAspectFit
    smooth: true
}
