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
    height: 72
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
        anchors { fill: parent; leftMargin: 2 }
        spacing: 0

        ToolbarBtn { label: qsTr("Add URL");        iconSrc: "icons/link.svg";        onClicked: root.addClicked() }
        // selectedItemStatus is a string Q_PROPERTY on DownloadTable — it emits
        // selectedItemStatusChanged whenever the focused item's status changes,
        // making cross-component enabled bindings reliably reactive.
        ToolbarBtn {
            label: qsTr("Resume"); iconSrc: "icons/resume.svg"
            enabled: downloadTable ? (downloadTable.selectedItemStatus === "Paused" || downloadTable.selectedItemStatus === "Error") : false
            onClicked: root.resumeClicked()
        }
        ToolbarBtn {
            label: qsTr("Stop"); iconSrc: "icons/pause.svg"
            enabled: downloadTable ? (downloadTable.selectedItemStatus === "Downloading"
                                   || downloadTable.selectedItemStatus === "Queued"
                                   || downloadTable.selectedItemStatus === "Seeding") : false
            onClicked: root.stopClicked()
        }
        ToolbarBtn { label: qsTr("Stop All"); iconSrc: "icons/stop_all.svg"; enabled: App.activeDownloads > 0;                          onClicked: root.stopAllClicked() }
        ToolbarBtn { label: qsTr("Delete");      iconSrc: "icons/wastebasket.svg"; enabled: downloadTable ? downloadTable.hasSelection : false; onClicked: root.deleteClicked() }
        ToolbarBtn { label: qsTr("Delete Done"); iconSrc: "icons/delete_done.svg"; onClicked: root.deleteCompletedClicked() }
        ToolbarBtn { label: qsTr("Options");        iconSrc: "icons/tools.svg";     onClicked: root.optionsClicked() }
        ToolbarBtn { label: qsTr("Scheduler");      iconSrc: "icons/scheduler.svg";     onClicked: root.schedulerClicked() }

        // Start Queue dropdown
        ToolbarDropdown {
            label: qsTr("Start Queue")
            iconSrc: "icons/start_queue.svg"
            queueModel: root.queueModel
            onQueueSelected: (queueId) => root.startQueueRequested(queueId)
        }

        // Stop Queue dropdown
        ToolbarDropdown {
            label: qsTr("Stop Queue")
            iconSrc: "icons/stop_queue.svg"
            queueModel: root.queueModel
            onQueueSelected: (queueId) => root.stopQueueRequested(queueId)
        }

        ToolbarBtn { label: qsTr("Grabber");        iconSrc: "icons/grabber.svg";         onClicked: root.grabberClicked() }
        ToolbarBtn {
            label: qsTr("Search Engine"); iconSrc: "icons/magnifying_glass.svg"
            visible: App.settings.showSearchEngine
            onClicked: root.searchEngineClicked()
        }
        ToolbarBtn {
            label: qsTr("RSS"); iconSrc: "icons/rss.svg"
            visible: App.settings.showRssReader
            onClicked: root.rssClicked()
        }
    }
}
