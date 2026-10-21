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
import QtQuick.Controls

// Thin context-menu row, matching DownloadTable.qml's CtxMenuItem (22px,
// opaque bg, icon+text, ✓ for checkable rows, ▶ for submenus).
MenuItem {
    id: _mi
    implicitHeight: 22
    height: 22
    topPadding: 0; bottomPadding: 0; verticalPadding: 0
    leftPadding: 8; rightPadding: 12
    spacing: 0
    font.pixelSize: 12 * App.fontScale
    property string iconSrc: ""
    // Blank out the default indicator/arrow — the check (✓) and submenu
    // arrow (▶) are rendered inside contentItem so they never overlap the
    // label (a separate indicator isn't shifted past by MenuItem).
    indicator: Item { width: 0; height: 0 }
    arrow: Item { width: 0; height: 0 }
    contentItem: Row {
        spacing: 6
        // Check slot — fixed gutter only for checkable rows.
        Item {
            visible: _mi.checkable
            width: visible ? 14 : 0
            height: 14
            anchors.verticalCenter: parent.verticalCenter
            Text {
                visible: _mi.checked
                anchors.centerIn: parent
                text: "✓"; font.pixelSize: 10 * App.fontScale; font.bold: true
                color: ColorPalette.textPrimary
            }
        }
        Image {
            visible: _mi.iconSrc !== ""
            source: _mi.iconSrc !== "" ? "../icons/" + _mi.iconSrc : ""
            width: 14; height: 14
            sourceSize.width: 14; sourceSize.height: 14
            fillMode: Image.PreserveAspectFit
            smooth: true
            anchors.verticalCenter: parent.verticalCenter
        }
        Text {
            text: _mi.text
            font: _mi.font
            color: _mi.enabled ? ColorPalette.textPrimary : ColorPalette.textDisabled
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
            anchors.verticalCenter: parent.verticalCenter
        }
        // Submenu arrow trails the label with a small gap.
        Item { visible: _mi.subMenu !== null; width: visible ? 24 : 0; height: 1 }
        Text {
            visible: _mi.subMenu !== null
            anchors.verticalCenter: parent.verticalCenter
            text: "▶"; font.pixelSize: 8 * App.fontScale; color: ColorPalette.textMuted
        }
    }
    background: Rectangle {
        implicitHeight: 22
        // Opaque, never "transparent" — see CLAUDE.md "Linux Software-Backend Menus".
        color: _mi.highlighted ? ColorPalette.selectionBg : ColorPalette.menuBg
    }
}
