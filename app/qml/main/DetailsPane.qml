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

// Docked details under the table: the properties content
// (FilePropertiesDialog) following the table's current item. The torrent
// workspace gets every torrent tab; the downloads workspace gets General and
// Speed. Drag the top edge to resize; each workspace keeps its own height and
// tab.
Rectangle {
    id: root
    color: ColorPalette.cardBg

    // "downloads" | "torrents"
    property string workspace: "downloads"
    readonly property bool _torrents: workspace === "torrents"
    property var item: null
    // False while the main window is hidden/minimized or the pane is closed,
    // so the per-torrent live models stop polling libtorrent.
    property bool active: false
    // Set by the host so a drag can't squeeze the table to nothing.
    property real maxPaneHeight: 600
    readonly property int minPaneHeight: 120
    readonly property int defaultPaneHeight: 260

    readonly property int _savedHeight: _torrents ? App.settings.torrentDetailsPaneHeight
                                                  : App.settings.downloadDetailsPaneHeight
    function _saveHeight(h) {
        if (_torrents) App.settings.torrentDetailsPaneHeight = h
        else App.settings.downloadDetailsPaneHeight = h
    }

    height: Math.max(minPaneHeight, Math.min(_savedHeight, maxPaneHeight))

    // Restores the workspace's saved tab. Guarded so the restore itself isn't
    // written back as a user choice (onCurrentTabChanged fires mid-switch).
    property bool _restoringTab: false
    function _restoreTab() {
        _restoringTab = true
        var saved = _torrents ? App.settings.torrentDetailsPaneTab : App.settings.downloadDetailsPaneTab
        // Clamp in case the saved index predates a tab being removed.
        view.currentTab = Math.max(0, Math.min(saved, view.tabCount - 1))
        _restoringTab = false
    }
    onWorkspaceChanged: _restoreTab()

    Rectangle {
        id: splitter
        anchors { top: parent.top; left: parent.left; right: parent.right }
        height: 4
        color: splitterMa.containsMouse || splitterMa.pressed ? ColorPalette.accent : ColorPalette.border
        Behavior on color { ColorAnimation { duration: 80 } }

        MouseArea {
            id: splitterMa
            anchors.fill: parent
            // Extra hit area so the 4px handle is easy to grab.
            anchors.topMargin: -3
            anchors.bottomMargin: -3
            hoverEnabled: true
            cursorShape: Qt.SplitVCursor

            // Scene coordinates: the handle itself moves as the pane grows, so
            // local mouse positions would feed back into the drag.
            property real _startSceneY: 0
            property real _startHeight: 0

            onPressed: (mouse) => {
                _startSceneY = mapToItem(null, mouse.x, mouse.y).y
                _startHeight = root.height
            }
            onPositionChanged: (mouse) => {
                if (!pressed) return
                var delta = mapToItem(null, mouse.x, mouse.y).y - _startSceneY
                var h = Math.max(root.minPaneHeight, Math.min(_startHeight - delta, root.maxPaneHeight))
                root._saveHeight(Math.round(h))
            }
            onDoubleClicked: root._saveHeight(root.defaultPaneHeight)
        }
    }

    FilePropertiesDialog {
        id: view
        anchors { top: splitter.bottom; left: parent.left; right: parent.right; bottom: parent.bottom }
        visible: !!root.item
        embedded: true
        item: root.item
        active: root.active && !!root.item
        Component.onCompleted: root._restoreTab()
        // The tab count follows the item kind; re-clamp once the first item of
        // the workspace arrives (a torrent tab index is out of range for HTTP).
        onTabCountChanged: root._restoreTab()
        onCurrentTabChanged: {
            if (root._restoringTab) return
            if (root._torrents) App.settings.torrentDetailsPaneTab = currentTab
            else App.settings.downloadDetailsPaneTab = currentTab
        }
    }

    Text {
        anchors.centerIn: parent
        visible: !root.item
        text: root._torrents ? qsTr("Select a torrent to see its details.")
                             : qsTr("Select a download to see its details.")
        color: ColorPalette.textDisabled
        font.pixelSize: 13 * App.fontScale
    }
}
