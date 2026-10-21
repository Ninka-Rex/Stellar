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

// One tooltip for a whole live-updating list, instead of one per row. A model
// update can destroy, recycle or slide the hovered row away from a still cursor;
// a per-row tip dies with its row. Here rows just report hoverEnter()/hoverLeave()
// and the tip lives in the list, driven by the pointer rather than by which entry
// is under it:
//  - moving the mouse hides the tip;
//  - once the pointer rests for restDelay, the entry under it gets its tip;
//  - while the pointer stays still, the tip stays put even if a live update
//    slides other entries under the cursor, since the user didn't move.
//
// Place it as a child of the list and bind `pointer` (position in the list's
// frame, from a HoverHandler) and `viewHovered`.
ThemedToolTip {
    id: tip

    property point pointer
    property bool viewHovered: false
    // How long the pointer must rest before a tip shows (ThemedToolTip's delay).
    property int restDelay: 600

    // {key, text} for every hovered entry, innermost (most recent) last. A flag
    // badge is hovered together with its row; the badge wins while over it.
    property var _hovers: []
    property string _key: ""
    // Pointer when it last came to rest; compared against to tell a real mouse
    // move from sub-pixel jitter.
    property point _anchor
    property point _at

    // The rest timer below is the delay; the popup itself opens at once.
    delay: 0
    x: Math.max(0, Math.min(_at.x + 14, (parent ? parent.width : 0) - implicitWidth))
    y: parent && _at.y + 20 + implicitHeight > parent.height
       ? Math.max(0, _at.y - implicitHeight - 6)
       : _at.y + 20
    visible: _key !== ""

    // Not enter/leave: Popup already has an "enter" transition property, which
    // would shadow a function of that name.
    function hoverEnter(key, hoverText) {
        _hovers = _hovers.filter(h => h.key !== key).concat([{ key: key, text: hoverText }])
    }

    function hoverLeave(key) {
        _hovers = _hovers.filter(h => h.key !== key)
    }

    // Row data changed while hovered (e.g. client name resolved).
    function refresh(key, hoverText) {
        _hovers = _hovers.map(h => h.key === key ? { key: key, text: hoverText } : h)
        if (_key === key)
            text = hoverText
    }

    function _pointerMoved() {
        if (Math.abs(pointer.x - _anchor.x) <= 3 && Math.abs(pointer.y - _anchor.y) <= 3)
            return
        _anchor = pointer
        _key = ""
        restTimer.restart()
    }

    onPointerChanged: _pointerMoved()
    onViewHoveredChanged: {
        if (viewHovered)
            return
        restTimer.stop()
        _key = ""
    }

    Timer {
        id: restTimer
        interval: tip.restDelay
        onTriggered: {
            // Deferred a tick so hover changes from the same event burst are in.
            Qt.callLater(function() {
                const top = tip._hovers.length > 0 ? tip._hovers[tip._hovers.length - 1] : null
                if (!tip.viewHovered || !top)
                    return
                tip._at = tip.pointer
                tip.text = top.text
                tip._key = top.key
            })
        }
    }
}
