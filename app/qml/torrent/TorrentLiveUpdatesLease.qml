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

import QtQml

// Holds at most one live-updates retain on a torrent file/peer/tracker model
// while `wanted` is true. Releases on model swap (the details pane following
// the selection), on `wanted` dropping, and on destruction, so the model's
// viewer count can never leak or underflow.
QtObject {
    id: lease

    property var model: null
    property bool wanted: false

    // A model just started receiving live updates; hosts use it to pull a
    // fresh snapshot instead of waiting for the next alert tick.
    signal acquired()

    property var _held: null

    function _sync() {
        var next = (wanted && model) ? model : null
        if (next === _held)
            return
        // A model destroyed with its torrent reads back as null here, so a
        // dead object is never released.
        if (_held)
            _held.releaseLiveUpdates()
        _held = next
        if (_held) {
            _held.retainLiveUpdates()
            lease.acquired()
        }
    }

    onModelChanged: _sync()
    onWantedChanged: _sync()
    Component.onCompleted: _sync()
    Component.onDestruction: {
        if (_held)
            _held.releaseLiveUpdates()
        _held = null
    }
}
