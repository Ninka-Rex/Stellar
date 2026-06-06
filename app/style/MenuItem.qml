// Stellar custom Controls style — MenuItem.
//
// Based on Qt's Material MenuItem (Copyright (C) 2017 The Qt Company Ltd.,
// SPDX-License-Identifier: LicenseRef-Qt-Commercial OR LGPL-3.0-only OR
// GPL-2.0-only OR GPL-3.0-only), with reduced item height/padding for a
// compact menu. Part of the "Stellar" custom style (FallbackStyle=Material).

import QtQuick
import QtQuick.Templates as T
import QtQuick.Controls.impl
import QtQuick.Controls.Material
import QtQuick.Controls.Material.impl

T.MenuItem {
    id: control

    implicitWidth: Math.max(implicitBackgroundWidth + leftInset + rightInset,
                            implicitContentWidth + leftPadding + rightPadding)
    implicitHeight: Math.max(implicitBackgroundHeight + topInset + bottomInset,
                             implicitContentHeight + topPadding + bottomPadding,
                             implicitIndicatorHeight + topPadding + bottomPadding)

    padding: 0
    verticalPadding: -2
    spacing: 16

    icon.width: 24
    icon.height: 24
    icon.color: enabled ? Material.foreground : Material.hintTextColor

    indicator: CheckIndicator {
        x: control.text ? (control.mirrored ? control.width - width - control.rightPadding : control.leftPadding) : control.leftPadding + (control.availableWidth - width) / 2
        y: control.topPadding + (control.availableHeight - height) / 2
        visible: control.checkable
        control: control
        checkState: control.checked ? Qt.Checked : Qt.Unchecked
    }

    arrow: ColorImage {
        x: control.mirrored ? control.padding : control.width - width - control.padding
        y: control.topPadding + (control.availableHeight - height) / 2

        visible: control.subMenu
        mirror: control.mirrored
        color: control.enabled ? control.Material.foreground : control.Material.hintTextColor
        source: "qrc:/qt-project.org/imports/QtQuick/Controls/Material/images/arrow-indicator.png"
    }

    contentItem: IconLabel {
        readonly property real arrowPadding: control.subMenu && control.arrow ? control.arrow.width + control.spacing : 0
        readonly property real indicatorPadding: control.checkable && control.indicator ? control.indicator.width + control.spacing : 0
        leftPadding: !control.mirrored ? indicatorPadding : arrowPadding
        rightPadding: control.mirrored ? indicatorPadding : arrowPadding

        spacing: control.spacing
        mirrored: control.mirrored
        display: control.display
        alignment: Qt.AlignLeft

        icon: control.icon
        text: control.text
        font: control.font
        color: control.enabled ? control.Material.foreground : control.Material.hintTextColor
    }

    // Each row paints an OPAQUE background (the menu's dialog colour when not
    // highlighted, the highlight colour when it is). This is deliberate: under
    // the Qt Quick software scene graph — our forced backend on machines without
    // usable hardware OpenGL (VirtualBox/SVGA3D, where GLX has no FBConfig) — the
    // Menu's own background Rectangle does not composite, so a menu whose rows are
    // "transparent" shows the window straight through. Making every row opaque
    // means the stacked rows themselves form the solid menu panel regardless of
    // whether the popup background node paints. On a hardware backend it looks
    // identical (the rows simply match the dialog colour behind them).
    //
    // Ripple is intentionally omitted: it is a ShaderEffect, which the software
    // adaptation ignores entirely, and it added nothing on the hardware path here.
    background: Rectangle {
        implicitWidth: 200
        implicitHeight: 24
        color: control.highlighted ? control.Material.listHighlightColor
                                    : control.Material.dialogColor
    }
}
