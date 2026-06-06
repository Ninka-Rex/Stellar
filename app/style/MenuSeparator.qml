// Stellar custom Controls style — MenuSeparator.
//
// Based on Qt's Material MenuSeparator (Copyright (C) 2017 The Qt Company Ltd.,
// SPDX-License-Identifier: LicenseRef-Qt-Commercial OR LGPL-3.0-only OR
// GPL-2.0-only OR GPL-3.0-only). Part of the "Stellar" custom style
// (FallbackStyle=Material).
//
// The one Stellar change: the background is OPAQUE (Material.dialogColor), not
// the stock implicit transparent. Under the Qt Quick software scene graph — our
// fallback on machines without usable hardware OpenGL (e.g. VirtualBox/SVGA3D,
// where GLX has no usable FBConfig) — the Menu's own background node does not
// reliably composite. A separator whose padding region is transparent then
// punches a hole through the menu, showing the window behind it. Painting the
// separator's full background opaque keeps the menu panel solid. On a hardware
// backend it is identical (the fill matches the menu colour behind it).

import QtQuick
import QtQuick.Templates as T
import QtQuick.Controls.Material

T.MenuSeparator {
    id: control

    implicitWidth: Math.max(implicitBackgroundWidth + leftInset + rightInset,
                            implicitContentWidth + leftPadding + rightPadding)
    implicitHeight: Math.max(implicitBackgroundHeight + topInset + bottomInset,
                             implicitContentHeight + topPadding + bottomPadding)

    leftPadding: 8
    rightPadding: 8
    topPadding: 4
    bottomPadding: 4

    contentItem: Rectangle {
        implicitWidth: 200
        implicitHeight: 1
        color: control.Material.dividerColor
    }

    background: Rectangle {
        color: control.Material.dialogColor
    }
}
