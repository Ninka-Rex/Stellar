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

// Small explanatory text under a setting. The one style for all such notes,
// so they read the same on every page and in both themes.
Text {
    Layout.fillWidth: true
    color: enabled ? ColorPalette.textMuted : ColorPalette.textDisabled
    font.pixelSize: 11 * App.fontScale
    wrapMode: Text.WordWrap
}
