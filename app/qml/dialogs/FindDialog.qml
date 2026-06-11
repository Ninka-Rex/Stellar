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
    title: qsTr("Find")
    width: 380
    height: 305
    minimumWidth: 320
    minimumHeight: 305
    maximumHeight: 305
    color: ColorPalette.cardBg
    flags: Qt.Dialog | Qt.WindowTitleHint | Qt.WindowCloseButtonHint

    Material.theme: ColorPalette.materialTheme
    Material.foreground: ColorPalette.textPrimary
    Material.background: ColorPalette.materialBg
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
            Text { text: qsTr("Find:"); color: ColorPalette.textPrimary; font.pixelSize: 13 * App.fontScale }
            TextField {
                id: searchField
                Layout.fillWidth: true
                color: ColorPalette.textPrimary; font.pixelSize: 13 * App.fontScale
                background: Rectangle { color: ColorPalette.inputBg; border.color: searchField.activeFocus ? ColorPalette.borderFocus : ColorPalette.border; radius: 3 }
                leftPadding: 8
                Keys.onReturnPressed: root.doFind()
                Keys.onEnterPressed:  root.doFind()
            }
        }

        Rectangle { Layout.fillWidth: true; height: 1; color: ColorPalette.border }

        Text { text: qsTr("Search in:"); color: ColorPalette.textSecond; font.pixelSize: 12 * App.fontScale }

        StyledCheckBox {
            text: qsTr("File name or part of the name")
            checked: root.searchName
            topPadding: 0; bottomPadding: 0
            onCheckedChanged: root.searchName = checked
            contentItem: Text { text: parent.text; color: ColorPalette.textPrimary; font.pixelSize: 13 * App.fontScale; leftPadding: parent.indicator.width + 4 }
        }
        StyledCheckBox {
            text: qsTr("Description or part of the description")
            checked: root.searchDesc
            topPadding: 0; bottomPadding: 0
            onCheckedChanged: root.searchDesc = checked
            contentItem: Text { text: parent.text; color: ColorPalette.textPrimary; font.pixelSize: 13 * App.fontScale; leftPadding: parent.indicator.width + 4 }
        }
        StyledCheckBox {
            text: qsTr("Site name / download link / parent web page / referrer")
            checked: root.searchLinks
            topPadding: 0; bottomPadding: 0
            onCheckedChanged: root.searchLinks = checked
            contentItem: Text {
                text: parent.text; color: ColorPalette.textPrimary; font.pixelSize: 13 * App.fontScale
                leftPadding: parent.indicator.width + 4; wrapMode: Text.WordWrap
                Layout.fillWidth: true
            }
        }

        Rectangle { Layout.fillWidth: true; height: 1; color: ColorPalette.border }

        StyledCheckBox {
            text: qsTr("Match case")
            checked: root.matchCase
            topPadding: 0; bottomPadding: 0
            onCheckedChanged: root.matchCase = checked
            contentItem: Text { text: parent.text; color: ColorPalette.textPrimary; font.pixelSize: 13 * App.fontScale; leftPadding: parent.indicator.width + 4 }
        }
        StyledCheckBox {
            text: qsTr("Match whole string only")
            checked: root.matchWhole
            topPadding: 0; bottomPadding: 0
            onCheckedChanged: root.matchWhole = checked
            contentItem: Text { text: parent.text; color: ColorPalette.textPrimary; font.pixelSize: 13 * App.fontScale; leftPadding: parent.indicator.width + 4 }
        }

        Item { Layout.fillHeight: true }

        // Result feedback
        Text {
            Layout.fillWidth: true
            text: root.resultCount < 0  ? "" :
                  root.resultCount === 0 ? qsTr("No results found.") :
                  root.resultCount === 1 ? qsTr("Found 1 result.") :
                                           qsTr("Found %1 results.").arg(root.resultCount)
            color: root.resultCount === 0 ? "#cc6666" : "#66bb66"
            font.pixelSize: 12 * App.fontScale
            horizontalAlignment: Text.AlignRight
            visible: root.resultCount >= 0
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            Item { Layout.fillWidth: true }
            Button {
                id: findBtn
                text: qsTr("Find")
                implicitWidth: 80
                background: Rectangle {
                    color: root._finding ? "#2a5faa" : ColorPalette.selectionBg
                    radius: 3
                    border.color: root._finding ? "#66aaff" : "#4488dd"
                    border.width: 1
                    Behavior on color { ColorAnimation { duration: 80 } }
                    Behavior on border.color { ColorAnimation { duration: 80 } }
                }
                contentItem: Text { text: parent.text; color: root._finding ? "#ffffff" : ColorPalette.selectionText; font.pixelSize: 13 * App.fontScale; font.bold: true; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                onClicked: root.doFind()
            }
            Button {
                text: qsTr("Cancel")
                implicitWidth: 80
                background: Rectangle { color: ColorPalette.buttonSecondaryBg; radius: 3; border.color: ColorPalette.border; border.width: 1 }
                contentItem: Text { text: parent.text; color: ColorPalette.textPrimary; font.pixelSize: 13 * App.fontScale; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                onClicked: root.close()
            }
        }
    }
}
