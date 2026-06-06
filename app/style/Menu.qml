// Stellar custom Controls style — Menu.
//
// Based on Qt's Material Menu (Copyright (C) 2017 The Qt Company Ltd.,
// SPDX-License-Identifier: LicenseRef-Qt-Commercial OR LGPL-3.0-only OR
// GPL-2.0-only OR GPL-3.0-only), with two Stellar changes:
//   1. Reduced vertical padding for a compact menu.
//   2. The Material elevation shadow is drawn by RoundedElevationEffect, a
//      ShaderEffect. Qt's *software* scene graph (QSGSoftwareRenderContext,
//      selected via QT_QUICK_BACKEND=software when there is no usable hardware
//      OpenGL — VMs, RDP, broken drivers) cannot execute ShaderEffects: an
//      enabled layer there produces an empty texture, so the menu background
//      never paints and the whole menu renders transparent. Under the software
//      backend we skip the shader layer and draw a plain bordered rectangle so
//      the menu is solid and readable (just without the soft drop shadow).
//
// This file lives in the "Stellar" custom style (FallbackStyle=Material), so it
// is compiled into the binary via qt_add_qml_module and actually ships — unlike
// the old, never-wired app/style-overrides/ tree it replaces.

import QtQuick
import QtQuick.Templates as T
import QtQuick.Controls.Material
import QtQuick.Controls.Material.impl
import QtQuick.Window

T.Menu {
    id: control

    implicitWidth: Math.max(implicitBackgroundWidth + leftInset + rightInset,
                            contentWidth + leftPadding + rightPadding)
    implicitHeight: Math.max(implicitBackgroundHeight + topInset + bottomInset,
                             contentHeight + topPadding + bottomPadding)

    margins: 0
    verticalPadding: -2

    // Render the menu INSIDE the parent window's overlay, not as a separate
    // top-level popup window. Qt 6.8 introduced Popup.popupType and made
    // Popup.Window a common default: the menu then lives in its own native
    // top-level surface. Under the Qt Quick *software* backend (our fallback when
    // hardware OpenGL is unavailable — VMs, headless, broken drivers) that
    // separate popup surface is not given an opaque background, so the menu
    // composites as transparent and you see the window behind it — regardless of
    // the background Rectangle's color. Popup.Item draws the menu as an item in
    // the already-opaque main scene's overlay (the pre-6.8 behavior), which is
    // solid on every backend. This is the actual fix for the transparent menus;
    // the shader-shadow change above only mattered on top of this.
    popupType: T.Popup.Item

    transformOrigin: !cascade ? Item.Top : (mirrored ? Item.TopRight : Item.TopLeft)

    Material.elevation: 1
    Material.roundedScale: Material.ExtraSmallScale

    delegate: MenuItem { }

    enter: Transition {
        NumberAnimation { property: "scale"; from: 0.9; to: 1.0; easing.type: Easing.OutQuint; duration: 220 }
        NumberAnimation { property: "opacity"; from: 0.0; to: 1.0; easing.type: Easing.OutCubic; duration: 150 }
    }

    exit: Transition {
        NumberAnimation { property: "scale"; from: 1.0; to: 0.9; easing.type: Easing.OutQuint; duration: 220 }
        NumberAnimation { property: "opacity"; from: 1.0; to: 0.0; easing.type: Easing.OutCubic; duration: 150 }
    }

    contentItem: ListView {
        implicitHeight: contentHeight

        model: control.contentModel
        interactive: Window.window
                     ? contentHeight + control.topPadding + control.bottomPadding > control.height
                     : false
        clip: true
        currentIndex: control.currentIndex

        ScrollIndicator.vertical: ScrollIndicator {}
    }

    background: Rectangle {
        implicitWidth: 200
        implicitHeight: control.Material.menuItemHeight
        radius: control.Material.roundedScale
        color: control.Material.dialogColor

        // The stock Material menu draws its drop shadow with RoundedElevationEffect,
        // a ShaderEffect captured via layer.enabled. The Qt Quick *software* scene
        // graph (our fallback when hardware OpenGL is unavailable — VMs, headless,
        // broken drivers) cannot execute ShaderEffects: the layer renders an empty
        // texture and the entire background — color included — disappears, so the
        // menu is fully transparent. Detecting the backend via GraphicsInfo.api is
        // unreliable here (the software backend does not report
        // GraphicsInfo.Software consistently), so we simply do NOT use a layer at
        // all. A plain bordered rectangle is solid on every backend; the only thing
        // lost is the soft drop shadow, which the software backend could never draw
        // anyway. The border gives the menu a crisp edge in place of the shadow.
        border.width: 1
        border.color: control.Material.dividerColor
    }

    T.Overlay.modal: Rectangle {
        color: control.Material.backgroundDimColor
        Behavior on opacity { NumberAnimation { duration: 150 } }
    }

    T.Overlay.modeless: Rectangle {
        color: control.Material.backgroundDimColor
        Behavior on opacity { NumberAnimation { duration: 150 } }
    }
}
