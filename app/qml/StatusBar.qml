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
import QtQuick.Layouts

Rectangle {
    id: root
    height: 22
    color: "#1a1a1a"

    property int activeCount:    0
    property int completedCount: 0
    property int selectedCount:  0
    property var tipsArray:      []
    property int currentTipIndex: 0
    property bool showTips:      true

    signal nextTip()
    signal closeTips()

    // top border
    Rectangle { anchors.top: parent.top; width: parent.width; height: 1; color: "#3a3a3a" }

    RowLayout {
        anchors { fill: parent; leftMargin: 8; rightMargin: 8; topMargin: 1 }
        spacing: 20

        Text {
            text: {
                var base
                if (activeCount > 0)
                    base = "%1 file(s) downloading".arg(activeCount)
                else if (App.settings.showFinishedCount && completedCount > 0)
                    base = "Ready | %1 downloads".arg(completedCount)
                else
                    base = "Ready"

                // Append selection count when one or more rows are highlighted.
                if (selectedCount > 0)
                    base += " | %1 selected".arg(selectedCount)

                // Append speed limiter status if enabled
                if (App.settings.globalSpeedLimitKBps > 0) {
                    base += " | Speed limiter enabled (" + App.settings.globalSpeedLimitKBps + " KB/s)"
                }

                return base
            }
            color: "#a0a0a0"
            font.pixelSize: 11
            verticalAlignment: Text.AlignVCenter
        }

        Item { Layout.fillWidth: true }

        // Tips section (right-aligned)
        RowLayout {
            visible: App.settings.showTips && tipsArray.length > 0
            spacing: 8
            Layout.preferredWidth: 400

            Text {
                text: tipsArray.length > currentTipIndex ? "💡 " + tipsArray[currentTipIndex] : ""
                color: "#b0b0b0"
                font.pixelSize: 11
                wrapMode: Text.NoWrap
                elide: Text.ElideRight
                Layout.fillWidth: true
            }

            Row {
                spacing: 6

                Text {
                    text: "next >>"
                    color: "#5588cc"
                    font.pixelSize: 10
                    font.underline: true
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.nextTip()
                    }
                }

                Text {
                    text: "✕"
                    color: "#888888"
                    font.pixelSize: 12
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        hoverEnabled: true
                        onClicked: root.closeTips()
                        onEntered: parent.color = "#b0b0b0"
                        onExited: parent.color = "#888888"
                    }
                }
            }
        }

        Text {
            visible: !App.settings.showTips || tipsArray.length === 0
            text: App.minutesUntilNextQueue === 1
                ? "Queue runs in 1 minute"
                : (App.minutesUntilNextQueue > 0 ? "Queue runs in %1 minutes".arg(App.minutesUntilNextQueue) : "")
            color: "#a0a0a0"
            font.pixelSize: 11
        }
    }
}
