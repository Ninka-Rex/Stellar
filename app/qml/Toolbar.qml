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
import QtQuick.Layouts

Rectangle {
    id: root
    height: 64
    color: "#1f1f1f"

    property var queueModel: null
    property var downloadTable: null

    // Reactive enabled-state helpers.
    // Bind directly to readonly properties on DownloadTable rather than calling
    // functions — QML only re-evaluates an `enabled:` binding when a *property*
    // it accessed changes, not when a function's internal state changes.  The
    // anyPausedSelected / anyActiveSelected properties on DownloadTable emit
    // change signals (via _selectionVersion) and propagate correctly here.

    signal addClicked()
    signal resumeClicked()
    signal stopClicked()
    signal stopAllClicked()
    signal deleteClicked()
    signal deleteCompletedClicked()
    signal optionsClicked()
    signal schedulerClicked()
    signal startQueueRequested(string queueId)
    signal stopQueueRequested(string queueId)
    signal grabberClicked()
    signal searchEngineClicked()
    signal rssClicked()

    // bottom border
    Rectangle {
        anchors.bottom: parent.bottom
        width: parent.width
        height: 0
        color: "#3a3a3a"
    }

    Row {
        anchors { fill: parent; topMargin: 4; bottomMargin: 4; leftMargin: 2 }
        spacing: 0

        ToolbarBtn { label: "Add URL";        iconSrc: "icons/link.png";        onClicked: root.addClicked() }
        // selectedItemStatus is a string Q_PROPERTY on DownloadTable — it emits
        // selectedItemStatusChanged whenever the focused item's status changes,
        // making cross-component enabled bindings reliably reactive.
        ToolbarBtn {
            label: "Resume"; iconSrc: "icons/resume.png"
            enabled: downloadTable ? downloadTable.selectedItemStatus === "Paused" : false
            onClicked: root.resumeClicked()
        }
        ToolbarBtn {
            label: "Stop"; iconSrc: "icons/pause.png"
            enabled: downloadTable ? (downloadTable.selectedItemStatus === "Downloading"
                                   || downloadTable.selectedItemStatus === "Queued"
                                   || downloadTable.selectedItemStatus === "Seeding") : false
            onClicked: root.stopClicked()
        }
        ToolbarBtn { label: "Stop All"; iconSrc: "icons/pause_orange.png"; enabled: App.activeDownloads > 0;                          onClicked: root.stopAllClicked() }
        ToolbarBtn { label: "Delete";      iconSrc: "icons/trash.png"; enabled: downloadTable ? downloadTable.hasSelection : false; onClicked: root.deleteClicked() }
        ToolbarBtn { label: "Delete Done"; iconSrc: "icons/trash.png";      onClicked: root.deleteCompletedClicked() }
        ToolbarBtn { label: "Options";        iconSrc: "icons/tools.png";     onClicked: root.optionsClicked() }
        ToolbarBtn { label: "Scheduler";      iconSrc: "icons/clock.png";     onClicked: root.schedulerClicked() }

        // Start Queue dropdown
        ToolbarDropdown {
            label: "Start Queue"
            iconSrc: "icons/resume_purple.png"
            queueModel: root.queueModel
            onQueueSelected: (queueId) => root.startQueueRequested(queueId)
        }

        // Stop Queue dropdown
        ToolbarDropdown {
            label: "Stop Queue"
            iconSrc: "icons/pause_purple.png"
            queueModel: root.queueModel
            onQueueSelected: (queueId) => root.stopQueueRequested(queueId)
        }

        ToolbarBtn { label: "Grabber";        iconSrc: "icons/spider.png";         onClicked: root.grabberClicked() }
        ToolbarBtn {
            label: "Search Engine"; iconSrc: "icons/magnifying_glass.png"
            visible: App.settings.showSearchEngine
            onClicked: root.searchEngineClicked()
        }
        ToolbarBtn {
            label: "RSS"; iconSrc: "icons/rss.png"
            visible: App.settings.showRssReader
            onClicked: root.rssClicked()
        }
    }
}
