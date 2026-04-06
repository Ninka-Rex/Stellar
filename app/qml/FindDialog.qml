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
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts

Window {
    id: root
    title: "Find"
    width: 380
    height: 305
    minimumWidth: 320
    minimumHeight: 305
    maximumHeight: 305
    color: "#1e1e1e"
    flags: Qt.Dialog | Qt.WindowTitleHint | Qt.WindowCloseButtonHint

    Material.theme: Material.Dark
    Material.background: "#1e1e1e"
    Material.accent: "#4488dd"

    // Search options
    property bool searchName:    true
    property bool searchDesc:    false
    property bool searchLinks:   false
    property bool matchCase:     false
    property bool matchWhole:    false
    property int  lastMatchRow:  -1
    property int  resultCount:   -1   // -1 = no search yet
    property bool _finding:      false

    Timer {
        id: flashTimer
        interval: 220
        onTriggered: root._finding = false
    }

    signal findRequested(string text, bool name, bool desc, bool links, bool matchCase, bool matchWhole)
    signal findNextRequested(string text, bool name, bool desc, bool links, bool matchCase, bool matchWhole)

    function doFind() {
        lastMatchRow = -1
        root._finding = true
        flashTimer.restart()
        findRequested(searchField.text, searchName, searchDesc, searchLinks, matchCase, matchWhole)
    }

    function doFindNext() {
        findNextRequested(searchField.text, searchName, searchDesc, searchLinks, matchCase, matchWhole)
    }

    onVisibleChanged: {
        if (visible) searchField.forceActiveFocus()
        else { resultCount = -1; _finding = false }
    }

    ColumnLayout {
        anchors { fill: parent; margins: 16 }
        spacing: 10

        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            Text { text: "Find:"; color: "#c0c0c0"; font.pixelSize: 13 }
            TextField {
                id: searchField
                Layout.fillWidth: true
                color: "#d0d0d0"; font.pixelSize: 13
                background: Rectangle { color: "#2d2d2d"; border.color: "#4a4a4a"; radius: 3 }
                leftPadding: 8
                Keys.onReturnPressed: root.doFind()
                Keys.onEnterPressed:  root.doFind()
            }
        }

        Rectangle { Layout.fillWidth: true; height: 1; color: "#2e2e2e" }

        Text { text: "Search in:"; color: "#909090"; font.pixelSize: 12 }

        CheckBox {
            text: "File name or part of the name"
            checked: root.searchName
            topPadding: 0; bottomPadding: 0
            onCheckedChanged: root.searchName = checked
            contentItem: Text { text: parent.text; color: "#d0d0d0"; font.pixelSize: 13; leftPadding: parent.indicator.width + 4 }
        }
        CheckBox {
            text: "Description or part of the description"
            checked: root.searchDesc
            topPadding: 0; bottomPadding: 0
            onCheckedChanged: root.searchDesc = checked
            contentItem: Text { text: parent.text; color: "#d0d0d0"; font.pixelSize: 13; leftPadding: parent.indicator.width + 4 }
        }
        CheckBox {
            text: "Site name / download link / parent web page / referrer"
            checked: root.searchLinks
            topPadding: 0; bottomPadding: 0
            onCheckedChanged: root.searchLinks = checked
            contentItem: Text {
                text: parent.text; color: "#d0d0d0"; font.pixelSize: 13
                leftPadding: parent.indicator.width + 4; wrapMode: Text.WordWrap
                Layout.fillWidth: true
            }
        }

        Rectangle { Layout.fillWidth: true; height: 1; color: "#2e2e2e" }

        CheckBox {
            text: "Match case"
            checked: root.matchCase
            topPadding: 0; bottomPadding: 0
            onCheckedChanged: root.matchCase = checked
            contentItem: Text { text: parent.text; color: "#d0d0d0"; font.pixelSize: 13; leftPadding: parent.indicator.width + 4 }
        }
        CheckBox {
            text: "Match whole string only"
            checked: root.matchWhole
            topPadding: 0; bottomPadding: 0
            onCheckedChanged: root.matchWhole = checked
            contentItem: Text { text: parent.text; color: "#d0d0d0"; font.pixelSize: 13; leftPadding: parent.indicator.width + 4 }
        }

        Item { Layout.fillHeight: true }

        // Result feedback
        Text {
            Layout.fillWidth: true
            text: root.resultCount < 0  ? "" :
                  root.resultCount === 0 ? "No results found." :
                  root.resultCount === 1 ? "Found 1 result." :
                                           "Found " + root.resultCount + " results."
            color: root.resultCount === 0 ? "#cc6666" : "#66bb66"
            font.pixelSize: 12
            horizontalAlignment: Text.AlignRight
            visible: root.resultCount >= 0
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            Item { Layout.fillWidth: true }
            Button {
                id: findBtn
                text: "Find"
                implicitWidth: 80
                background: Rectangle {
                    color: root._finding ? "#2a5faa" : "#1e3a6e"
                    radius: 3
                    border.color: root._finding ? "#66aaff" : "#4488dd"
                    border.width: 1
                    Behavior on color { ColorAnimation { duration: 80 } }
                    Behavior on border.color { ColorAnimation { duration: 80 } }
                }
                contentItem: Text { text: parent.text; color: "#ffffff"; font.pixelSize: 13; font.bold: true; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                onClicked: root.doFind()
            }
            Button {
                text: "Cancel"
                implicitWidth: 80
                background: Rectangle { color: "#3a3a3a"; radius: 3; border.color: "#555"; border.width: 1 }
                contentItem: Text { text: parent.text; color: "#d0d0d0"; font.pixelSize: 13; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                onClicked: root.close()
            }
        }
    }
}
