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

// Indeterminate "working" overlay for a header strip, after the Vista copy
// dialog's living header but in Stellar's own colours: the strip breathes a faint
// tint of the logo purple while a soft glow drifts across it, then rests before the next
// pass. Used where there is no real percentage for a progress bar. Lay it over
// the normal header background; it draws nothing opaque, so the header's text
// colours stay as they are.
Item {
    id: fx

    property bool running: true
    property color tint: ColorPalette.brandPurple

    readonly property bool _animating: running && visible
    readonly property real _glowW: Math.max(160, width * 0.45)
    property real _glow: 0

    clip: true

    // Slow breathing wash over the whole strip.
    Rectangle {
        anchors.fill: parent
        color: fx.tint
        opacity: 0.04
        SequentialAnimation on opacity {
            running: fx._animating
            loops: Animation.Infinite
            NumberAnimation { to: 0.16; duration: 2200; easing.type: Easing.InOutSine }
            NumberAnimation { to: 0.04; duration: 2200; easing.type: Easing.InOutSine }
        }
    }

    // Drifting glow: eases across, then pauses off-screen so it reads as a calm
    // pulse rather than a spinner.
    Rectangle {
        width: fx._glowW
        height: parent.height
        x: -width + fx._glow * (fx.width + width)
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0; color: Qt.rgba(fx.tint.r, fx.tint.g, fx.tint.b, 0) }
            GradientStop { position: 0.5; color: Qt.rgba(fx.tint.r, fx.tint.g, fx.tint.b, 0.30) }
            GradientStop { position: 1.0; color: Qt.rgba(fx.tint.r, fx.tint.g, fx.tint.b, 0) }
        }
    }

    // Bottom edge lights up under the glow, like the rim of the Vista strip.
    Rectangle {
        anchors.bottom: parent.bottom
        height: 2
        width: fx._glowW * 0.8
        x: -width + fx._glow * (fx.width + width)
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0; color: Qt.rgba(fx.tint.r, fx.tint.g, fx.tint.b, 0) }
            GradientStop { position: 0.5; color: fx.tint }
            GradientStop { position: 1.0; color: Qt.rgba(fx.tint.r, fx.tint.g, fx.tint.b, 0) }
        }
    }

    SequentialAnimation on _glow {
        running: fx._animating
        loops: Animation.Infinite
        NumberAnimation { from: 0; to: 1; duration: 2600; easing.type: Easing.InOutQuad }
        PauseAnimation { duration: 900 }
    }
}
