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
import QtQuick.Controls.Material
import QtCore

Window {
    id: root
    title: view.windowTitle
    // Sizes are enforced via onItemChanged/onVisibleChanged so the window
    // always fits the content type, even when the user switches items.
    color: ColorPalette.cardBg
    // No transientParent — a transient/owned window is hidden from the Windows
    // taskbar. Null parent makes each properties window a top-level taskbar entry.
    transientParent: null
    // Qt.Window (not Qt.Dialog) so each properties window gets its own Windows
    // taskbar entry — Qt.Dialog windows group under the parent's taskbar button.
    flags: Qt.Window | Qt.WindowTitleHint | Qt.WindowCloseButtonHint | Qt.WindowSystemMenuHint | Qt.WindowMinimizeButtonHint

    Material.theme: ColorPalette.materialTheme
    Material.foreground: ColorPalette.textPrimary
    Material.background: ColorPalette.materialBg
    Material.accent: "#4488dd"

    property var item: null

    // ?? Window sizing ????????????????????????????????????????????????????????
    // Torrent variant remembers the user's last size (persisted via the Settings
    // block below); the non-torrent variant stays fixed. _sizeSaveReady gates the
    // resize-save handlers so our own programmatic sizing here doesn't echo back.
    property int savedTorrentWidth: 800
    property int savedTorrentHeight: 500
    property bool _sizeSaveReady: false

    function _applySize() {
        var torrent = !!(root.item && root.item.isTorrent)
        _sizeSaveReady = false
        minimumWidth  = 0
        minimumHeight = 0
        // Reset caps each time so a torrent's max doesn't leak onto a non-torrent
        // item when the same window is reused for a different download.
        maximumWidth  = 16777215
        maximumHeight = 16777215
        if (torrent) {
            minimumWidth  = 630
            minimumHeight = 420
            maximumWidth  = 800
            maximumHeight = 500
            width  = Math.min(maximumWidth,  Math.max(minimumWidth,  root.savedTorrentWidth))
            height = Math.min(maximumHeight, Math.max(minimumHeight, root.savedTorrentHeight))
        } else {
            minimumWidth  = 470
            minimumHeight = 420
            width  = 470
            height = 420
        }
        // Re-arm saving only after our own width/height writes have settled, so the
        // onWidthChanged/onHeightChanged they trigger aren't mistaken for a user drag.
        Qt.callLater(function() { root._sizeSaveReady = true })
    }

    Timer {
        id: sizeSaveTimer
        interval: 400; repeat: false
        onTriggered: {
            if (!root._sizeSaveReady || !root.visible) return
            if (!(root.item && root.item.isTorrent)) return   // only the torrent variant persists
            root.savedTorrentWidth  = root.width
            root.savedTorrentHeight = root.height
        }
    }
    onWidthChanged:  if (_sizeSaveReady && visible) sizeSaveTimer.restart()
    onHeightChanged: if (_sizeSaveReady && visible) sizeSaveTimer.restart()

    // Per-window cascade so stacked properties windows don't perfectly overlap.
    property int cascadeOffset: 0
    // Explicit owner for centering. transientParent is null (so the window gets
    // its own taskbar entry), so we can't read geometry from it — pass the main
    // window here instead.
    property var ownerWindow: null

    function _centerOnOwner() {
        var owner = root.ownerWindow || root.transientParent
        if (owner) {
            x = owner.x + Math.round((owner.width - width) / 2) + cascadeOffset
            y = owner.y + Math.round((owner.height - height) / 2) + cascadeOffset
            return
        }
        x = Math.round((Screen.width - width) / 2) + cascadeOffset
        y = Math.round((Screen.height - height) / 2) + cascadeOffset
    }

    // Works around a Qt layout invalidation bug when the Loader swaps between
    // regularLayout and torrentLayout.  The new component is created and sized
    // within the same event-loop tick as the old one is destroyed, but Qt
    // coalesces the relayout into that same frame - before the new component's
    // implicit sizes have fully propagated through the ColumnLayout chain.
    // Result: the footer buttons overlap the content or disappear entirely.
    // A zero-delay timer fires on the *next* tick and nudges the window width
    // by +1/-1, which is the same thing a manual drag does: it forces a clean,
    // full layout pass with the new content already in the tree.
    Timer {
        id: layoutNudgeTimer
        interval: 0
        repeat: false
        onTriggered: {
            root.width = root.width + 1
            root.width = root.width - 1
        }
    }

    Settings {
        category: "FilePropertiesDialog"
        property alias savedTorrentWidth: root.savedTorrentWidth
        property alias savedTorrentHeight: root.savedTorrentHeight
    }

    onItemChanged: {
        // Size + position synchronously here (item is set before show() for a
        // freshly created window) so the window appears already-placed — no
        // one-frame flicker at screen-center before _centerOnOwner moves it.
        root._applySize()
        // Only place the window before it's first shown; re-setting item on an
        // already-visible window (raise on re-open) must not yank it back to center.
        if (!visible)
            root._centerOnOwner()
    }
    onVisibleChanged: {
        if (visible) {
            raise()
            requestActivate()
        }
    }

    // All content and strings live in FilePropertiesDialog (its translation
    // context); this window only owns sizing, placement and the taskbar entry.
    FilePropertiesDialog {
        id: view
        anchors.fill: parent
        item: root.item
        active: root.visible
        onCloseRequested: root.close()
        onLayoutSwapped: {
            root._applySize()
            if (root.visible)
                root._centerOnOwner()
            // Nudge the window size in a later event-loop tick to force
            // Qt to run a full layout pass with the new Loader content.
            // The Loader swap invalidates geometry but Qt coalesces the
            // relayout into the current frame - which runs before the new
            // component's implicit sizes have fully propagated. A deferred
            // +1/-1 nudge triggers a second, clean layout pass.
            layoutNudgeTimer.restart()
        }
    }
}
