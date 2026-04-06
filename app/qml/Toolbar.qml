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

    property var queueModel: null

    // bottom border
    Rectangle {
        anchors.bottom: parent.bottom
        width: parent.width
        height: 0
        color: "#3a3a3a"
    }

    Row {
        anchors { fill: parent; topMargin: 4; bottomMargin: 4; leftMargin: 2 }
        spacing: 2

        ToolbarBtn { label: "Add URL";        iconSrc: "icons/new_file.ico";    onClicked: root.addClicked() }
        ToolbarBtn { label: "Resume";         iconSrc: "icons/resume.png";     onClicked: root.resumeClicked() }
        ToolbarBtn { label: "Stop";           iconSrc: "icons/pause.png";      onClicked: root.stopClicked() }
        ToolbarBtn { label: "Stop All";       iconSrc: "icons/pause_orange.png";      onClicked: root.stopAllClicked() }
        ToolbarBtn { label: "Delete";         iconSrc: "icons/remove.png";     onClicked: root.deleteClicked() }
        ToolbarBtn { label: "Delete Done";    iconSrc: "icons/files_x.png";     onClicked: root.deleteCompletedClicked() }
        ToolbarBtn { label: "Options";        iconSrc: "icons/Tools.ico";       onClicked: root.optionsClicked() }
        ToolbarBtn { label: "Scheduler";      iconSrc: "icons/scheduler.ico"; onClicked: root.schedulerClicked() }

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

        ToolbarBtn { label: "Grabber";        iconSrc: "icons/wand.ico";   onClicked: root.grabberClicked() }
    }
}
