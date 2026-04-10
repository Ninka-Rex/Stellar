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
import QtQuick.Controls.Material
import QtQuick.Layouts

Window {
    id: root
    title: "Load Grabber Project"
    width: 420
    height: 320
    minimumWidth: 380
    minimumHeight: 280
    color: "#1c1c1c"
    flags: Qt.Dialog | Qt.WindowTitleHint | Qt.WindowCloseButtonHint
    modality: Qt.ApplicationModal

    Material.theme: Material.Dark
    Material.background: "#1c1c1c"

    property string selectedProjectId: ""
    signal accepted(string projectId)

    function isTemplateRow(row) {
        var project = App.grabberProjectModel.projectData(row)
        return !!project.isTemplate
    }

    Rectangle {
        anchors.fill: parent
        color: "#1c1c1c"

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 12
            spacing: 10

            Text { text: "Saved projects"; color: "#f1f4f8"; font.pixelSize: 16; font.bold: true }

            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                color: "#1c1c1c"
                border.color: "#2e2e2e"

                ListView {
                    id: projectList
                    anchors.fill: parent
                    anchors.margins: 6
                    clip: true
                    model: App.grabberProjectModel
                    delegate: Rectangle {
                        required property int index
                        required property string projectId
                        required property string projectName
                        required property string projectStartUrl
                        required property string projectStatusText

                        visible: !root.isTemplateRow(index)
                        width: projectList.width
                        height: visible ? 42 : 0
                        color: root.selectedProjectId === projectId ? "#1e3a6e" : "transparent"
                        border.color: "transparent"

                        Column {
                            anchors.fill: parent
                            anchors.leftMargin: 8
                            anchors.rightMargin: 8
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 2
                            Text { text: projectName; color: "#eef2f7"; font.pixelSize: 13; font.bold: true }
                            Text { text: projectStartUrl; color: "#98a2b3"; font.pixelSize: 11; elide: Text.ElideRight; width: parent.width }
                        }

                        MouseArea {
                            anchors.fill: parent
                            onClicked: root.selectedProjectId = projectId
                            onDoubleClicked: {
                                root.selectedProjectId = projectId
                                root.accepted(projectId)
                                root.close()
                            }
                        }
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Item { Layout.fillWidth: true }
                DlgButton { text: "Cancel"; onClicked: root.close() }
                DlgButton {
                    text: "OK"
                    primary: true
                    enabled: root.selectedProjectId.length > 0
                    onClicked: {
                        root.accepted(root.selectedProjectId)
                        root.close()
                    }
                }
            }
        }
    }
}
