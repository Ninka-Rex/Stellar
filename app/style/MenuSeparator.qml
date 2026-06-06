// Stellar custom Controls style — MenuSeparator.
//
// Based on Qt's Material MenuSeparator (Copyright (C) 2017 The Qt Company Ltd.,
// SPDX-License-Identifier: LicenseRef-Qt-Commercial OR LGPL-3.0-only OR
// GPL-2.0-only OR GPL-3.0-only). Part of the "Stellar" custom style
// (FallbackStyle=Material).
//
// Stellar change: opaque background (Material.dialogColor) instead of the stock
// transparent, so the separator's padding gap doesn't show through under the
// software scene graph. See CLAUDE.md "Linux Software-Backend Menus".

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
