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
import QtQuick.Window
import QtQuick.Layouts

// World map of a torrent's swarm: you, every geolocated peer (fanned out when
// several share a GeoIP point), optional tracker locations, and a line to each
// peer currently transferring. Wheel zooms at the cursor, drag pans,
// double-click resets. The view is the user's, not the torrent's: it is saved
// and carries over between torrents and sessions, and never moves on its own.
//
// Markers and lines are positioned in screen pixels from SVG-unit coordinates
// (not by scaling one big canvas), so they keep a constant size at any zoom.
Rectangle {
    id: map
    color: ColorPalette.mapCanvasBg

    // FilePropertiesDialog: owns the map projection and the shared formatters
    // (speeds, flags, client icons, place names).
    required property var view
    // Null while the tab isn't visible, which also stops the live updates.
    property var peerModel: null
    property var trackerModel: null
    property real torrentProgress: 0
    // Changes when a different torrent is shown.
    property string contentKey: ""

    readonly property bool showInactive: App.settings.swarmMapShowInactive
    readonly property bool showTrackers: App.settings.swarmMapShowTrackers
    readonly property bool hasLocal: !!peerModel && peerModel.hasLocalLocation

    // ── View geometry (SVG units) ────────────────────────────────────────
    readonly property real svgW: view.worldMap.width
    readonly property real svgH: view.worldMap.height
    // Antarctica is cropped: no peers there, and it costs a fifth of the height.
    readonly property real bandTop: view.worldMapY(90, svgH)
    readonly property real bandBottom: view.worldMapY(-58, svgH)
    readonly property real bandH: bandBottom - bandTop

    readonly property real minZoom: 1
    readonly property real maxZoom: 12
    // Restored from the saved view (centre stored as a fraction of the map, so
    // it survives map asset changes); clampView() fits it to the plot later.
    property real zoom: Math.max(minZoom, Math.min(maxZoom, App.settings.swarmMapZoom))
    property real cx: (App.settings.swarmMapCenterX >= 0 ? App.settings.swarmMapCenterX : 0.5) * svgW
    property real cy: App.settings.swarmMapCenterY >= 0 ? App.settings.swarmMapCenterY * svgH
                                                         : bandTop + bandH / 2
    // Bound once: the restore above must not follow later settings writes
    // (this instance's own saves, or another open map's).
    Component.onCompleted: { zoom = zoom; cx = cx; cy = cy }

    // Zoom 1 covers the plot with the cropped band (cropping the long axis
    // rather than letterboxing), so the map is never a small island in empty
    // space; pan to reach what's cut off.
    readonly property real baseScale: plot.width > 0 && plot.height > 0
                                      ? Math.max(plot.width / svgW, plot.height / bandH) : 1
    readonly property real s: baseScale * zoom
    readonly property real panX: plot.width / 2 - cx * s
    readonly property real panY: plot.height / 2 - cy * s

    function svgX(lon) { return view.worldMapX(lon, svgW) }
    function svgY(lat) { return view.worldMapY(lat, svgH) }
    function screenX(sx) { return panX + sx * s }
    function screenY(sy) { return panY + sy * s }

    function clampView() {
        var halfW = plot.width / 2 / s
        var halfH = plot.height / 2 / s
        cx = svgW <= 2 * halfW ? svgW / 2 : Math.max(halfW, Math.min(svgW - halfW, cx))
        cy = bandH <= 2 * halfH ? bandTop + bandH / 2
                                : Math.max(bandTop + halfH, Math.min(bandBottom - halfH, cy))
    }

    function zoomAt(px, py, factor) {
        var z = Math.max(minZoom, Math.min(maxZoom, zoom * factor))
        if (z === zoom) return
        // Keep the map point under the cursor fixed.
        var mx = (px - panX) / s
        var my = (py - panY) / s
        zoom = z
        cx = mx - (px - plot.width / 2) / s
        cy = my - (py - plot.height / 2) / s
        clampView()
    }

    function resetView() {
        zoom = 1
        cx = svgW / 2
        cy = bandTop + bandH / 2
        clampView()
        saveViewTimer.restart()
    }

    // Only user input saves the view: a resize clamps the centre to the plot,
    // and saving that would lose the user's centre for a larger window.
    // Debounced, since a drag or wheel spin moves the view every frame.
    Timer {
        id: saveViewTimer
        interval: 400
        onTriggered: {
            App.settings.swarmMapZoom = map.zoom
            App.settings.swarmMapCenterX = map.cx / map.svgW
            App.settings.swarmMapCenterY = map.cy / map.svgH
        }
    }
    // A torrent switch flushes a pending save first, so the next map opened
    // (another torrent's window) starts where this one was left.
    onContentKeyChanged: {
        hideHover()
        if (saveViewTimer.running) {
            saveViewTimer.stop()
            saveViewTimer.triggered()
        }
    }
    Component.onDestruction: {
        if (saveViewTimer.running)
            saveViewTimer.triggered()
    }

    // ── Hover tooltip state ──────────────────────────────────────────────
    // kind: "" | "peer" | "tracker" | "you". Peer data is re-read from the model
    // on every update so speeds/ping don't freeze while hovered.
    property string hoverKind: ""
    property string hoverPeerKey: ""
    property var hoverData: ({})
    property real hoverX: 0
    property real hoverY: 0

    function showHover(kind, data, key, x, y) {
        hoverKind = kind
        hoverData = data
        hoverPeerKey = key
        hoverX = x
        hoverY = y
    }
    function hideHover() {
        hoverKind = ""
        hoverPeerKey = ""
    }
    Connections {
        target: map.peerModel
        ignoreUnknownSignals: true
        function onDataChanged() {
            if (map.hoverKind !== "peer") return
            var live = map.peerModel.peerByKey(map.hoverPeerKey)
            if (live && live.endpoint !== undefined) map.hoverData = live
            else map.hideHover()
        }
    }

    // ── Style ────────────────────────────────────────────────────────────
    readonly property color peerColor: "#5f93c9"
    readonly property color seedColor: "#4caf7d"
    readonly property color youColor: "#9959e6"
    readonly property color trackerColor: "#e8d57a"

    function trafficOf(down, up) { return Math.max(down, up) }
    function lineColor(down, up) {
        var speed = trafficOf(down, up)
        var alpha = speed >= 5000000 ? 0.9 : speed >= 1000000 ? 0.75 : speed >= 250000 ? 0.58
                  : speed >= 30000 ? 0.42 : 0.28
        var c = down > 0 && up > 0 ? youColor : (up > 0 ? seedColor : peerColor)
        return Qt.rgba(c.r, c.g, c.b, alpha)
    }
    function lineWidth(down, up) {
        var speed = trafficOf(down, up)
        return speed >= 5000000 ? 3.5 : speed >= 1000000 ? 2.5 : speed >= 128 * 1024 ? 1.8 : 1.2
    }
    // Screen-pixel fan-out for peers sharing a GeoIP point
    // (TorrentPeerModel stackIndex/stackSize): a ring for a handful, a
    // sunflower spiral beyond that so big clusters stay readable.
    function stackOffset(index, size) {
        if (size <= 1) return { x: 0, y: 0 }
        var angle, radius
        if (size <= 6) {
            angle = index / size * 2 * Math.PI - Math.PI / 2
            radius = 7
        } else {
            angle = index * 2.39996
            radius = 5 * Math.sqrt(index + 0.5)
        }
        return { x: Math.cos(angle) * radius, y: Math.sin(angle) * radius }
    }

    // ── Components ───────────────────────────────────────────────────────
    component MapToggle: Item {
        id: toggle
        property string text
        property bool checked
        signal toggled(bool checked)
        implicitWidth: toggleRow.implicitWidth
        implicitHeight: toggleRow.implicitHeight
        Row {
            id: toggleRow
            spacing: 4
            Rectangle {
                width: 12; height: 12; radius: 2
                anchors.verticalCenter: parent.verticalCenter
                color: toggle.checked ? ColorPalette.accent : ColorPalette.inputBg
                border.color: toggle.checked ? ColorPalette.accent : ColorPalette.border
                Text {
                    anchors.centerIn: parent
                    visible: toggle.checked
                    text: "✓"; color: "#ffffff"
                    font.pixelSize: 9; font.bold: true
                }
            }
            Text {
                text: toggle.text
                color: ColorPalette.textPrimary
                font.pixelSize: 11 * App.fontScale
                anchors.verticalCenter: parent.verticalCenter
            }
        }
        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: toggle.toggled(!toggle.checked)
        }
    }
    component LegendDot: Row {
        property alias text: dotLabel.text
        property color dotColor
        property bool diamond: false
        spacing: 4
        Rectangle {
            width: 8; height: 8; radius: parent.diamond ? 1 : 4
            rotation: parent.diamond ? 45 : 0
            color: parent.dotColor
            anchors.verticalCenter: parent.verticalCenter
        }
        Text { id: dotLabel; color: ColorPalette.textSecond; font.pixelSize: 11 * App.fontScale; anchors.verticalCenter: parent.verticalCenter }
    }
    component LegendLine: Row {
        property alias text: lineLabel.text
        property color lineColor
        spacing: 4
        Rectangle { width: 14; height: 2; radius: 1; color: parent.lineColor; anchors.verticalCenter: parent.verticalCenter }
        Text { id: lineLabel; color: ColorPalette.textSecond; font.pixelSize: 11 * App.fontScale; anchors.verticalCenter: parent.verticalCenter }
    }
    component TipText: Text {
        color: ColorPalette.textPrimary
        font.pixelSize: 11 * App.fontScale
        textFormat: Text.PlainText   // peer/tracker strings are untrusted
        elide: Text.ElideRight
        Layout.fillWidth: true
    }
    component TipTitle: TipText {
        font.pixelSize: 12 * App.fontScale
        font.bold: true
    }
    component TipIconRow: RowLayout {
        property alias iconSource: tipIcon.source
        property alias text: tipLabel.text
        property alias bold: tipLabel.font.bold
        property real iconWidth: 14
        property real iconHeight: 14
        spacing: 5
        Layout.fillWidth: true
        Image {
            id: tipIcon
            visible: status === Image.Ready
            sourceSize.width: parent.iconWidth * 2; sourceSize.height: parent.iconHeight * 2
            Layout.preferredWidth: parent.iconWidth; Layout.preferredHeight: parent.iconHeight
            fillMode: Image.PreserveAspectFit; smooth: true
        }
        TipText { id: tipLabel }
    }

    // ── Plot ─────────────────────────────────────────────────────────────
    Item {
        id: plot
        anchors.fill: parent
        clip: true
        onWidthChanged: map.clampView()
        onHeightChanged: map.clampView()

        // Pan / zoom underneath the markers; markers only take hover, so
        // presses and wheel fall through to here.
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton
            cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
            property real lastX: 0
            property real lastY: 0
            onPressed: (mouse) => {
                lastX = mouse.x; lastY = mouse.y
                map.hideHover()
            }
            onPositionChanged: (mouse) => {
                if (!pressed) return
                map.cx -= (mouse.x - lastX) / map.s
                map.cy -= (mouse.y - lastY) / map.s
                map.clampView()
                lastX = mouse.x; lastY = mouse.y
                saveViewTimer.restart()
            }
            onWheel: (wheel) => {
                map.hideHover()
                map.zoomAt(wheel.x, wheel.y, wheel.angleDelta.y > 0 ? 1.2 : 1 / 1.2)
                saveViewTimer.restart()
            }
            onDoubleClicked: map.resetView()
        }

        // The map is drawn twice. The base layer is one fixed raster of the
        // whole world, stretched to follow every pan/zoom step instantly but
        // soft when magnified. Once the view rests, the crisp layer re-renders
        // just the visible part of the SVG at exact device resolution (the SVG
        // reader honours sourceClipRect, so a 20000 px wide zoom only rasterises
        // what's on screen) and covers the base until the view moves again.
        readonly property url mapSource: ColorPalette.dark ? "../icons/images/world-map-dark.svg"
                                                           : "../icons/images/world-map-light.svg"
        Image {
            id: baseImage
            x: map.panX
            y: map.panY
            width: map.svgW * map.s
            height: map.svgH * map.s
            source: plot.mapSource
            fillMode: Image.Stretch
            smooth: true
            sourceSize.width: 2400
            sourceSize.height: Math.round(2400 * map.svgH / map.svgW)
        }

        Image {
            id: crispImage
            // View this raster was rendered for; any change hides it until the
            // re-render below catches up.
            property real renderedScale: -1
            property real renderedPanX: 0
            property real renderedPanY: 0
            readonly property bool current: renderedScale === map.s
                                            && renderedPanX === map.panX && renderedPanY === map.panY
            visible: current && status === Image.Ready
            asynchronous: true
            cache: false
            smooth: false
            fillMode: Image.Stretch
            source: plot.mapSource

            function render() {
                if (plot.width <= 0 || plot.height <= 0) return
                var dpr = Screen.devicePixelRatio
                var fullW = map.svgW * map.s
                var fullH = map.svgH * map.s
                // Visible part of the full map, in map-local logical pixels,
                // snapped to whole device pixels so nothing gets resampled.
                var x0 = Math.max(0, -map.panX), y0 = Math.max(0, -map.panY)
                var x1 = Math.min(fullW, plot.width - map.panX), y1 = Math.min(fullH, plot.height - map.panY)
                var dx0 = Math.floor(x0 * dpr), dy0 = Math.floor(y0 * dpr)
                var dx1 = Math.ceil(x1 * dpr), dy1 = Math.ceil(y1 * dpr)
                if (dx1 <= dx0 || dy1 <= dy0) return
                renderedScale = map.s
                renderedPanX = map.panX
                renderedPanY = map.panY
                sourceSize = Qt.size(Math.round(fullW * dpr), Math.round(fullH * dpr))
                sourceClipRect = Qt.rect(dx0, dy0, dx1 - dx0, dy1 - dy0)
                x = map.panX + dx0 / dpr
                y = map.panY + dy0 / dpr
                width = (dx1 - dx0) / dpr
                height = (dy1 - dy0) / dpr
            }
            Timer {
                id: crispTimer
                interval: 150
                onTriggered: crispImage.render()
            }
            Connections {
                target: map
                function onSChanged() { crispTimer.restart() }
                function onPanXChanged() { crispTimer.restart() }
                function onPanYChanged() { crispTimer.restart() }
            }
            Component.onCompleted: crispTimer.restart()
        }

        // Connection lines (only peers currently transferring).
        Repeater {
            model: map.peerModel
            delegate: Rectangle {
                required property double latitude
                required property double longitude
                required property int downSpeed
                required property int upSpeed
                required property int stackIndex
                required property int stackSize

                readonly property var off: map.stackOffset(stackIndex, stackSize)
                readonly property bool located: isFinite(latitude) && isFinite(longitude) && !(latitude === 0 && longitude === 0)
                readonly property real x0: map.hasLocal ? map.screenX(map.svgX(map.peerModel.localLongitude)) : 0
                readonly property real y0: map.hasLocal ? map.screenY(map.svgY(map.peerModel.localLatitude)) : 0
                readonly property real x1: map.screenX(map.svgX(longitude)) + off.x
                readonly property real y1: map.screenY(map.svgY(latitude)) + off.y
                readonly property real dx: x1 - x0
                readonly property real dy: y1 - y0

                visible: located && map.hasLocal && map.trafficOf(downSpeed, upSpeed) > 0
                x: x0
                y: y0 - height / 2
                width: Math.sqrt(dx * dx + dy * dy)
                height: map.lineWidth(downSpeed, upSpeed)
                radius: height / 2
                rotation: Math.atan2(dy, dx) * 180 / Math.PI
                transformOrigin: Item.Left
                color: map.lineColor(downSpeed, upSpeed)
            }
        }

        // Tracker markers (diamonds).
        Repeater {
            id: trackerRepeater
            model: map.showTrackers ? map.trackerModel : null
            delegate: Item {
                required property double latitude
                required property double longitude
                required property string url
                required property string countryCode
                required property bool isSystemEntry
                required property string status
                required property int count
                required property int tier

                readonly property real sx: map.svgX(longitude)
                readonly property real sy: map.svgY(latitude)
                visible: !isSystemEntry && isFinite(latitude) && isFinite(longitude) && !(latitude === 0 && longitude === 0)
                x: map.screenX(sx) - width / 2
                y: map.screenY(sy) - height / 2
                width: 14; height: 14

                Rectangle {
                    anchors.centerIn: parent
                    width: 8; height: 8; radius: 1
                    rotation: 45
                    color: map.trackerColor
                    border.color: trackerMa.containsMouse ? ColorPalette.textPrimary : ColorPalette.mapBorder
                }
                MouseArea {
                    id: trackerMa
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.NoButton
                    onEntered: map.showHover("tracker", {
                        host: map.view.urlHost(url), countryCode: countryCode,
                        status: status, tier: tier, count: count
                    }, "", parent.x + parent.width / 2, parent.y + parent.height / 2)
                    onExited: map.hideHover()
                }
            }
        }

        // Peer markers.
        Repeater {
            id: markerRepeater
            model: map.peerModel
            delegate: Item {
                required property string endpoint
                required property int port
                required property double latitude
                required property double longitude
                required property int downSpeed
                required property int upSpeed
                required property bool isSeed
                required property int stackIndex
                required property int stackSize

                readonly property var off: map.stackOffset(stackIndex, stackSize)
                readonly property real sx: map.svgX(longitude)
                readonly property real sy: map.svgY(latitude)
                readonly property bool located: isFinite(latitude) && isFinite(longitude) && !(latitude === 0 && longitude === 0)
                visible: located && (map.showInactive || downSpeed > 0 || upSpeed > 0)
                x: map.screenX(sx) + off.x - width / 2
                y: map.screenY(sy) + off.y - height / 2
                width: 14; height: 14
                z: peerMa.containsMouse ? 2 : 1

                Rectangle {
                    anchors.centerIn: parent
                    width: peerMa.containsMouse ? 11 : 9
                    height: width
                    radius: width / 2
                    color: isSeed ? map.seedColor : map.peerColor
                    border.color: peerMa.containsMouse ? ColorPalette.textPrimary : ColorPalette.mapBorder
                }
                MouseArea {
                    id: peerMa
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.NoButton
                    onEntered: {
                        var key = endpoint + "|" + port
                        map.showHover("peer", map.peerModel.peerByKey(key), key,
                                      parent.x + parent.width / 2, parent.y + parent.height / 2)
                    }
                    onExited: map.hideHover()
                }
            }
        }

        // You.
        Item {
            visible: map.hasLocal
            x: map.hasLocal ? map.screenX(map.svgX(map.peerModel.localLongitude)) - width / 2 : 0
            y: map.hasLocal ? map.screenY(map.svgY(map.peerModel.localLatitude)) - height / 2 : 0
            width: 18; height: 18
            z: 3

            Rectangle {
                anchors.centerIn: parent
                width: 16; height: 16; radius: 8
                color: Qt.rgba(map.youColor.r, map.youColor.g, map.youColor.b, 0.25)
            }
            Rectangle {
                anchors.centerIn: parent
                width: 10; height: 10; radius: 5
                color: map.youColor
                border.color: youMa.containsMouse ? ColorPalette.textPrimary : ColorPalette.mapBorder
            }
            MouseArea {
                id: youMa
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.NoButton
                onEntered: map.showHover("you", {}, "", parent.x + parent.width / 2, parent.y + parent.height / 2)
                onExited: map.hideHover()
            }
        }

        // Empty / waiting states.
        Text {
            anchors.centerIn: parent
            z: 4
            visible: text.length > 0
            text: {
                if (!map.peerModel || map.peerModel.count === 0)
                    return qsTr("No connected peers to plot")
                if (map.peerModel.locatedCount === 0)
                    return qsTr("None of the connected peers have a known location")
                if (!map.hasLocal)
                    return qsTr("Waiting for your public IP so the local map position can be shown")
                return ""
            }
            color: ColorPalette.textSecond
            font.pixelSize: 12 * App.fontScale
            style: Text.Outline
            styleColor: ColorPalette.mapCanvasBg
        }

        // ── Tooltip ──────────────────────────────────────────────────────
        Rectangle {
            id: tip
            visible: map.hoverKind.length > 0
            z: 10
            width: Math.min(300, Math.max(180, tipLoader.implicitWidth + 16))
            height: tipLoader.implicitHeight + 12
            x: map.hoverX + 14 + width <= plot.width - 4 ? map.hoverX + 14 : Math.max(4, map.hoverX - 14 - width)
            y: Math.max(4, Math.min(plot.height - height - 4, map.hoverY - height / 2))
            radius: 4
            color: ColorPalette.mapTooltipBg
            border.color: ColorPalette.mapBorder

            Loader {
                id: tipLoader
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 6; leftMargin: 8; rightMargin: 8 }
                sourceComponent: map.hoverKind === "peer" ? peerTip
                               : map.hoverKind === "tracker" ? trackerTip
                               : map.hoverKind === "you" ? youTip : null
            }
        }

        Component {
            id: peerTip
            ColumnLayout {
                readonly property var p: map.hoverData || ({})
                readonly property string ep: map.view.safeStr(p.endpoint)
                spacing: 3
                TipTitle { text: (ep.indexOf(":") !== -1 ? "[" + ep + "]" : ep) + ":" + (p.port | 0) }
                TipIconRow {
                    visible: map.view.safeStr(p.client).length > 0
                    iconSource: map.view.torrentClientIconSource(map.view.baseClientName(map.view.safeStr(p.client)))
                    text: map.view.safeStr(p.client)
                }
                TipIconRow {
                    visible: map.view.safeStr(p.countryCode).length > 0
                    iconSource: map.view.countryFlagSource(map.view.safeStr(p.countryCode))
                    iconWidth: 16; iconHeight: 11
                    text: map.view.peerPlaceText(p)
                }
                Flow {
                    Layout.fillWidth: true
                    spacing: 3
                    visible: flagRepeater.count > 0
                    Repeater {
                        id: flagRepeater
                        model: map.view.peerFlagsList(p.flags)
                        delegate: PeerFlagBadge {
                            required property string modelData
                            flag: modelData
                        }
                    }
                }
                TipText {
                    text: qsTr("↓ %1  ↑ %2").arg(map.view.compactSpeed(p.downSpeed | 0)).arg(map.view.compactSpeed(p.upSpeed | 0))
                }
                TipText {
                    // libtorrent's rtt is the mean block-request response time, so
                    // it only exists for peers we download from.
                    text: {
                        var done = qsTr("%1% done").arg(Math.round((Number(p.progress) || 0) * 100))
                        return (p.rtt | 0) > 0 ? qsTr("Ping %1 ms").arg(p.rtt | 0) + "  ·  " + done : done
                    }
                }
            }
        }

        Component {
            id: trackerTip
            ColumnLayout {
                readonly property var t: map.hoverData || ({})
                spacing: 3
                TipIconRow {
                    iconSource: map.view.countryFlagSource(map.view.safeStr(t.countryCode))
                    iconWidth: 16; iconHeight: 11
                    text: map.view.safeStr(t.host)
                    bold: true
                }
                TipText {
                    readonly property string st: map.view.safeStr(t.status)
                    text: qsTr("Status") + ": " + (st.length > 0 ? st : qsTr("Unknown"))
                    color: st.toLowerCase() === "working" ? map.seedColor
                         : st.toLowerCase() === "not contacted" ? ColorPalette.textSecond : "#e8a35c"
                }
                TipText {
                    visible: (t.tier | 0) >= 0
                    text: qsTr("Tier") + ": " + (t.tier | 0)
                }
                TipText {
                    text: qsTr("Peers") + ": " + ((t.count | 0) > 0 ? (t.count | 0) : "-")
                }
            }
        }

        Component {
            id: youTip
            ColumnLayout {
                readonly property var pm: map.peerModel
                spacing: 3
                TipTitle {
                    text: pm ? (pm.localPort > 0 ? pm.localIp + ":" + pm.localPort : pm.localIp) : ""
                }
                TipIconRow {
                    // Empty client name = anonymous mode (libtorrent blanks the
                    // user-agent it broadcasts); match what the swarm sees.
                    visible: !!pm && pm.localClientName.length > 0
                    iconSource: "../icons/app/stellar.png"
                    text: pm ? pm.localClientName : ""
                }
                TipIconRow {
                    visible: !!pm && pm.localCountryCode.length > 0
                    iconSource: pm ? map.view.countryFlagSource(pm.localCountryCode) : ""
                    iconWidth: 16; iconHeight: 11
                    text: pm ? map.view.peerPlaceText({ countryCode: pm.localCountryCode,
                                                        regionName: pm.localRegionName,
                                                        cityName: pm.localCityName }) : ""
                }
                TipText {
                    text: qsTr("You (this client)") + "  ·  " + qsTr("%1% done").arg(Math.round(map.torrentProgress * 100))
                    color: ColorPalette.accentHover
                }
            }
        }
    }

    // ── Overlay: count (top-left), toggles + legend (top-right) ──────────
    // Floating chips instead of a header strip, so the map shows everywhere
    // there's no text over it.
    component OverlayChip: Rectangle {
        default property alias content: chipRow.data
        implicitWidth: chipRow.implicitWidth + 12
        implicitHeight: 20
        color: Qt.rgba(ColorPalette.mapCanvasBg.r, ColorPalette.mapCanvasBg.g, ColorPalette.mapCanvasBg.b, 0.82)
        Row {
            id: chipRow
            anchors.centerIn: parent
            spacing: 8
        }
    }

    OverlayChip {
        anchors { left: parent.left; top: parent.top; margins: 4 }
        z: 5
        Text {
            // Peers without a GeoIP location (LAN, private or link-local IPv6,
            // unknown ranges) can't be drawn; say so instead of silently
            // showing fewer dots.
            readonly property int total: map.peerModel ? map.peerModel.count : 0
            readonly property int located: map.peerModel ? map.peerModel.locatedCount : 0
            text: located < total ? qsTr("%1 peers, %2 on the map").arg(total).arg(located)
                                  : qsTr("%1 peers").arg(total)
            color: ColorPalette.textPrimary
            font.pixelSize: 11 * App.fontScale
        }
    }

    OverlayChip {
        anchors { right: parent.right; top: parent.top; margins: 4 }
        z: 5
        MapToggle {
            text: qsTr("Inactive")
            checked: map.showInactive
            onToggled: (checked) => App.settings.swarmMapShowInactive = checked
        }
        MapToggle {
            text: qsTr("Trackers")
            checked: map.showTrackers
            onToggled: (checked) => App.settings.swarmMapShowTrackers = checked
        }
        Rectangle { width: 1; height: 12; color: ColorPalette.border; anchors.verticalCenter: parent.verticalCenter }
        LegendDot { text: qsTr("Peer"); dotColor: map.peerColor }
        LegendDot { text: qsTr("Seed"); dotColor: map.seedColor }
        LegendDot { text: qsTr("You"); dotColor: map.youColor }
        LegendDot { text: qsTr("Tracker"); dotColor: map.trackerColor; diamond: true; visible: map.showTrackers }
        LegendLine { text: qsTr("DL"); lineColor: map.peerColor }
        LegendLine { text: qsTr("UL"); lineColor: map.seedColor }
        LegendLine { text: qsTr("Both"); lineColor: map.youColor }
    }
}
