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

// State-aware torrent progress bar. Three visual modes:
//   * metadata-pending (magnet, no metadata yet): indeterminate ORANGE
//     sliver sweeping left<->right — there is no real percentage yet.
//   * seeding / completed: determinate GREEN fill.
//   * downloading / everything else: determinate BLUE fill.
// Consumers pass a DownloadItem via `item`; the bar reads progress/status
// /torrentHasMetadata reactively.
Rectangle {
    id: bar

    property var item: null

    // True while a magnet is still pulling metadata — no real % to show.
    readonly property bool metadataPending:
        !!item && !!item.isTorrent && !item.torrentHasMetadata

    readonly property real pct: {
        if (!item) return 0
        var p = item.progress
        if (isNaN(p) || p < 0) return 0
        return p > 1 ? 1 : p
    }

    readonly property color fillColor: {
        if (metadataPending) return ColorPalette.progressMetadata
        if (!item) return ColorPalette.progressDownloading
        var s = item.status
        if (s === "Seeding" || s === "Completed") return ColorPalette.progressSeeding
        return ColorPalette.progressDownloading
    }

    implicitHeight: 8
    radius: height / 2
    color: ColorPalette.progressTrack
    border.color: ColorPalette.progressTrackBorder
    clip: true

    // Determinate fill (downloading / seeding / completed).
    Rectangle {
        visible: !bar.metadataPending
        anchors { left: parent.left; verticalCenter: parent.verticalCenter; leftMargin: 1 }
        width: Math.max(0, (bar.width - 2) * bar.pct)
        height: bar.height - 2
        radius: Math.max(0, bar.radius - 1)
        color: bar.fillColor
    }

    // Indeterminate metadata-fetch bar: a sliver that squeezes thin against
    // one edge, fattens as it crosses the middle, then squeezes thin against
    // the far edge — and back. `_pos` runs 0->1->0; width is widest mid-travel
    // and narrowest at each edge (the "squeeze").
    property real _pos: 0
    readonly property real _avail: Math.max(1, bar.width - 2)
    readonly property real _sweepW: _avail * (0.16 + 0.42 * Math.sin(Math.PI * _pos))

    SequentialAnimation on _pos {
        running: bar.metadataPending && bar.visible
        loops: Animation.Infinite
        NumberAnimation { from: 0; to: 1; duration: 950; easing.type: Easing.InOutQuad }
        NumberAnimation { from: 1; to: 0; duration: 950; easing.type: Easing.InOutQuad }
    }

    Rectangle {
        visible: bar.metadataPending
        y: 1
        height: bar.height - 2
        radius: Math.max(0, bar.radius - 1)
        color: ColorPalette.progressMetadata
        width: bar._sweepW
        x: 1 + bar._pos * (bar._avail - bar._sweepW)
    }
}
