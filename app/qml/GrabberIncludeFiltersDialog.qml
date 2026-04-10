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
    title: dialogTitle
    width: 560
    height: 360
    minimumWidth: 520
    minimumHeight: 320
    color: "#1e1e1e"
    flags: Qt.Dialog | Qt.WindowTitleHint | Qt.WindowCloseButtonHint
    modality: Qt.ApplicationModal

    Material.theme: Material.Dark
    Material.background: "#1e1e1e"
    Material.accent: "#4488dd"

    property string dialogTitle: "Include filters"
    property var builtInFilters: []
    property string customFiltersJson: ""
    property bool categoryEnabled: true
    property int selectedRow: 0
    property int editingCustomIndex: -1
    property var categoryIdOptions: []
    property var categoryLabelOptions: []

    readonly property var customFilters: _parseCustomFilters(customFiltersJson)
    readonly property var rows: builtInFilters.concat(customFilters)

    signal filterChosen(string mask, string categoryId)
    signal customFiltersSaved(string json)

    function _parseCustomFilters(json) {
        if (!json || json.length === 0)
            return []
        try {
            var parsed = JSON.parse(json)
            if (!Array.isArray(parsed))
                return []
            return parsed
        } catch (e) {
            return []
        }
    }

    function _saveCustomFilters(rows) {
        var json = JSON.stringify(rows)
        customFiltersJson = json
        customFiltersSaved(json)
    }

    function _currentRow() {
        if (rows.length === 0)
            return null
        return rows[Math.max(0, filtersList.currentIndex)]
    }

    function _selectCurrent() {
        var row = _currentRow()
        if (!row)
            return
        filterChosen(row.mask || "", row.categoryId || "")
        close()
    }

    function _openEditor(customIndex) {
        editingCustomIndex = customIndex
        var row = customIndex >= 0 ? customFilters[customIndex] : null
        filterNameField.text = row ? (row.name || "") : ""
        filterMaskField.text = row ? (row.mask || "") : ""
        if (categoryEnabled) {
            var ids = categoryIdOptions
            var idx = row ? ids.indexOf(row.categoryId || "all") : ids.indexOf("all")
            categoryCombo.currentIndex = Math.max(0, idx)
        }
        editorPopup.open()
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 12
        spacing: 10

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 10

            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                color: "#1b1b1b"
                border.color: "#343434"

                Column {
                    anchors.fill: parent

                    Rectangle {
                        width: parent.width
                        height: 28
                        color: "#252525"

                        Row {
                            anchors.fill: parent
                            spacing: 0
                            Text {
                                width: 180
                                height: parent.height
                                leftPadding: 8
                                verticalAlignment: Text.AlignVCenter
                                text: "Filter name"
                                color: "#f0f0f0"
                                font.pixelSize: 12
                                font.bold: true
                            }
                            Text {
                                width: parent.width - 180
                                height: parent.height
                                leftPadding: 8
                                verticalAlignment: Text.AlignVCenter
                                text: "Mask"
                                color: "#f0f0f0"
                                font.pixelSize: 12
                                font.bold: true
                            }
                        }
                    }

                    ListView {
                        id: filtersList
                        width: parent.width
                        height: parent.height - 28
                        clip: true
                        model: root.rows
                        currentIndex: Math.min(root.selectedRow, Math.max(0, root.rows.length - 1))

                        delegate: Rectangle {
                            required property int index
                            required property var modelData
                            width: filtersList.width
                            height: 24
                            color: index === filtersList.currentIndex ? "#1e3a6e" : "transparent"

                            Row {
                                anchors.fill: parent
                                spacing: 0
                                Text {
                                    width: 180
                                    height: parent.height
                                    leftPadding: 8
                                    verticalAlignment: Text.AlignVCenter
                                    text: modelData.name || ""
                                    color: "#d8d8d8"
                                    font.pixelSize: 12
                                    elide: Text.ElideRight
                                }
                                Text {
                                    width: parent.width - 180
                                    height: parent.height
                                    leftPadding: 8
                                    verticalAlignment: Text.AlignVCenter
                                    text: modelData.mask || ""
                                    color: "#d8d8d8"
                                    font.pixelSize: 12
                                    elide: Text.ElideRight
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                onClicked: {
                                    filtersList.currentIndex = index
                                    root.selectedRow = index
                                }
                                onDoubleClicked: root._selectCurrent()
                            }
                        }
                    }
                }
            }

            ColumnLayout {
                Layout.preferredWidth: 92
                Layout.alignment: Qt.AlignTop
                spacing: 8

                DlgButton {
                    text: "Add"
                    Layout.preferredWidth: 92
                    primary: true
                    onClicked: root._openEditor(-1)
                }
                DlgButton {
                    text: "Edit"
                    Layout.preferredWidth: 92
                    enabled: filtersList.currentIndex >= builtInFilters.length
                    onClicked: root._openEditor(filtersList.currentIndex - builtInFilters.length)
                }
                DlgButton {
                    text: "Delete"
                    Layout.preferredWidth: 92
                    enabled: filtersList.currentIndex >= builtInFilters.length
                    onClicked: {
                        var customIndex = filtersList.currentIndex - builtInFilters.length
                        if (customIndex < 0)
                            return
                        var next = customFilters.slice()
                        next.splice(customIndex, 1)
                        _saveCustomFilters(next)
                        selectedRow = Math.max(0, Math.min(filtersList.currentIndex - 1, builtInFilters.length + next.length - 1))
                    }
                }

                Item { Layout.fillHeight: true }

                DlgButton {
                    text: "OK"
                    Layout.preferredWidth: 92
                    onClicked: root.close()
                }
            }
        }
    }

    Popup {
        id: editorPopup
        modal: true
        focus: true
        width: 420
        height: categoryEnabled ? 214 : 174
        x: (root.width - width) / 2
        y: (root.height - height) / 2
        background: Rectangle { color: "#1f1f1f"; border.color: "#343434"; radius: 0 }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 12
            spacing: 10

            Text { text: editingCustomIndex >= 0 ? "Edit filter" : "New filter"; color: "#f0f0f0"; font.pixelSize: 13; font.bold: true }

            Text { text: "Filter name"; color: "#d4d4d4"; font.pixelSize: 12 }
            TextField {
                id: filterNameField
                Layout.fillWidth: true
                color: "#eef2f7"
                leftPadding: 8
                rightPadding: 8
                background: Rectangle { color: "#1b1b1b"; border.color: "#3a3a3a"; radius: 0 }
            }

            Text { text: "Mask"; color: "#d4d4d4"; font.pixelSize: 12 }
            TextField {
                id: filterMaskField
                Layout.fillWidth: true
                color: "#eef2f7"
                leftPadding: 8
                rightPadding: 8
                background: Rectangle { color: "#1b1b1b"; border.color: "#3a3a3a"; radius: 0 }
            }

            ColumnLayout {
                Layout.fillWidth: true
                visible: categoryEnabled
                spacing: 6
                Text { text: "Category"; color: "#d4d4d4"; font.pixelSize: 12 }
                ComboBox {
                    id: categoryCombo
                    Layout.fillWidth: true
                    model: categoryLabelOptions
                    background: Rectangle { color: "#1b1b1b"; border.color: "#3a3a3a"; radius: 0 }
                    contentItem: Text {
                        leftPadding: 8
                        rightPadding: 24
                        text: parent.displayText
                        color: "#eef2f7"
                        font: parent.font
                        verticalAlignment: Text.AlignVCenter
                        elide: Text.ElideRight
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Item { Layout.fillWidth: true }
                DlgButton { text: "Cancel"; onClicked: editorPopup.close() }
                DlgButton {
                    text: "Save"
                    primary: true
                    onClicked: {
                        var name = filterNameField.text.trim()
                        var mask = filterMaskField.text.trim()
                        if (name.length === 0 || mask.length === 0)
                            return
                        var next = customFilters.slice()
                        var row = {
                            name: name,
                            mask: mask,
                            categoryId: categoryEnabled ? (categoryIdOptions[categoryCombo.currentIndex] || "all") : ""
                        }
                        if (editingCustomIndex >= 0)
                            next[editingCustomIndex] = row
                        else
                            next.push(row)
                        _saveCustomFilters(next)
                        selectedRow = builtInFilters.length + (editingCustomIndex >= 0 ? editingCustomIndex : next.length - 1)
                        editorPopup.close()
                    }
                }
            }
        }
    }
}
