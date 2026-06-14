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

// Shared slim dark ComboBox.
//
// Why a component instead of the Stellar Controls style (app/style/ComboBox.qml):
// every dialog imports QtQuick.Controls.Material explicitly (for Material.*
// attached props), and in Qt 6 the *last imported style* resolves bare control
// types — so a plain `ComboBox` in those files is the Material ComboBox, NOT the
// Stellar style. Its default popup uses Material.menuItemHeight (~36-48px) rows,
// which is the "thick dropdown" complaint. Rather than fight style resolution,
// this component bakes the slim look (30px closed box, 24px rows) into an inline
// delegate + popup — the pattern already proven on Main.qml's cookieBrowserCombo.
// Backgrounds are opaque for the software scene graph (see CLAUDE.md
// "Linux Software-Backend Menus").

import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material

ComboBox {
    id: control

    implicitHeight: 24

    // Material adds large default padding; zero it so the text uses the full box
    // width (otherwise long entries like "System default" truncate to "System ...").
    padding: 0
    leftPadding: 0
    rightPadding: 0

    // Compact 16px-wide arrow, tight to the right edge.
    indicator: Canvas {
        id: arrow
        x: control.width - width - 6
        y: (control.height - height) / 2
        width: 10
        height: 6
        readonly property color arrowColor: control.enabled ? ColorPalette.textPrimary : ColorPalette.border
        onArrowColorChanged: requestPaint()
        onPaint: {
            var ctx = getContext("2d")
            ctx.reset()
            ctx.fillStyle = arrow.arrowColor
            ctx.beginPath()
            ctx.moveTo(0, 0)
            ctx.lineTo(width, 0)
            ctx.lineTo(width / 2, height)
            ctx.closePath()
            ctx.fill()
        }
    }

    // Slim closed box.
    contentItem: Text {
        leftPadding: 8
        rightPadding: 20
        text: control.displayText
        color: ColorPalette.textPrimary
        font: control.font
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
    }

    background: Rectangle {
        color: ColorPalette.inputBg
        border.color: control.activeFocus ? ColorPalette.borderFocus : ColorPalette.border
        radius: 3
    }

    // Slim 24px rows, no Material inflation.
    delegate: ItemDelegate {
        id: comboItem
        required property var model
        required property int index

        width: ListView.view ? ListView.view.width : control.width
        height: 24
        padding: 0

        highlighted: control.highlightedIndex === index

        contentItem: Text {
            text: comboItem.model[control.textRole !== undefined && control.textRole.length > 0
                                  ? control.textRole : "modelData"]
            leftPadding: 8
            rightPadding: 8
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
            font: control.font
            color: control.currentIndex === comboItem.index
                   ? ColorPalette.accent : ColorPalette.textPrimary
        }

        background: Rectangle {
            color: comboItem.highlighted ? ColorPalette.selectionBg : ColorPalette.inputBg
        }
    }

    popup: Popup {
        y: control.height + 2
        width: control.width
        implicitHeight: Math.min(contentItem.implicitHeight + 4,
                                 control.Window ? control.Window.height - 24 : 400)
        padding: 2

        background: Rectangle {
            color: ColorPalette.inputBg
            border.color: ColorPalette.border
            radius: 3
        }

        contentItem: ListView {
            clip: true
            implicitHeight: contentHeight
            model: control.delegateModel
            currentIndex: control.highlightedIndex
            ScrollIndicator.vertical: ScrollIndicator { }
        }
    }
}
