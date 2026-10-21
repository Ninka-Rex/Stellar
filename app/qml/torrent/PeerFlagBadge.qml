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

// One peer flag (IN, TRK, ENC, Seed, ...): the flag's colour as text on a
// solid tint of the same hue. Used by the Peers list, its legend and the swarm
// map tooltip so they always match.
Rectangle {
    id: badge
    required property string flag
    // Hover explanation (FilePropertiesDialog.flagTip); empty = no tooltip.
    property string tip: ""
    // Optional LiveHoverTip of the list this badge sits in, and the owning
    // entry's identity. With one, the tip survives live list updates; without
    // (legend, swarm map) the badge shows its own tooltip.
    property var hoverTip: null
    property string hoverKey: ""

    readonly property color hue: {
        switch (flag) {
        case "IN":   return "#e8c84a"   // incoming
        case "OUT":  return "#9aa3ad"   // outgoing
        case "TRK":  return "#5f93c9"   // tracker
        case "DHT":  return "#4db8ff"   // DHT
        case "PEX":  return "#a06de8"   // peer exchange
        case "LSD":  return "#4caf7d"   // local discovery
        case "UTP":  return "#7dd87d"   // uTP
        case "ENC":  return "#5ecfe8"   // encrypted
        case "SNB":  return "#e86a5c"   // snubbed
        case "UPO":  return "#c97de8"   // upload-only
        case "OPT":  return "#e8a35c"   // optimistic unchoke
        case "HPX":  return "#ff8ab4"   // holepunched
        case "I2P":  return "#a8ff78"   // I2P
        case "Seed": return "#c0a54a"
        default:     return "#9aa3ad"
        }
    }

    implicitWidth: label.implicitWidth + 6
    implicitHeight: 13
    radius: 0
    // Solid (pre-blended) so the tint reads the same over any row colour.
    color: Qt.tint(ColorPalette.cardBg, Qt.rgba(hue.r, hue.g, hue.b, ColorPalette.dark ? 0.24 : 0.28))

    Text {
        id: label
        anchors.centerIn: parent
        text: badge.flag
        // The bright hue loses contrast on a light tint; deepen it there.
        color: ColorPalette.dark ? badge.hue : Qt.darker(badge.hue, 1.6)
        font.pixelSize: 9 * App.fontScale
        font.bold: true
    }

    HoverHandler {
        id: hover
        enabled: badge.tip.length > 0
        onHoveredChanged: {
            if (!badge.hoverTip)
                return
            const key = badge.hoverKey + "/" + badge.flag
            if (hovered)
                badge.hoverTip.hoverEnter(key, badge.tip)
            else
                badge.hoverTip.hoverLeave(key)
        }
    }
    // A destroyed badge never gets its hover-exit; drop its entry from the list tip.
    Component.onDestruction: if (hoverTip) hoverTip.hoverLeave(hoverKey + "/" + flag)
    ThemedToolTip {
        visible: !badge.hoverTip && hover.hovered && badge.tip.length > 0
        text: badge.tip
    }
}
