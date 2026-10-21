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

// Show/hide, reorder and size the download table's columns. Edits a local
// copy; nothing reaches the table until OK (Reset included, so Cancel undoes it).
Window {
    id: root
    title: qsTr("Columns")
    width: 520
    height: 500
    minimumWidth: 440
    minimumHeight: 400
    color: ColorPalette.cardBg
    flags: Qt.Dialog | Qt.WindowTitleHint | Qt.WindowCloseButtonHint

    Material.theme: ColorPalette.materialTheme
    Material.foreground: ColorPalette.textPrimary
    Material.background: ColorPalette.materialBg
    Material.accent: ColorPalette.accent

    // Set by the opener before show(): the active workspace's current layout
    // and its defaults (Reset). Arrays of { key, title, widthPx, visible }.
    property var columnDefs: []
    property var defaultDefs: []

    signal columnsChanged(var defs)

    readonly property int minColumnWidth: 24
    readonly property int maxColumnWidth: 1200
    readonly property int rowHeight: 26

    ListModel { id: colModel }
    // ListModel.get() isn't reactive; bindings that read row data through
    // _current() depend on this instead, bumped on every edit.
    property int _revision: 0
    Connections {
        target: colModel
        function onDataChanged() { root._revision++ }
        function onRowsMoved()   { root._revision++ }
        function onModelReset()  { root._revision++ }
        function onRowsInserted() { root._revision++ }
    }

    function _load(defs) {
        colModel.clear()
        for (var i = 0; i < defs.length; i++) {
            colModel.append({
                key: defs[i].key,
                title: defs[i].title,
                widthPx: defs[i].widthPx,
                shown: defs[i].visible !== false
            })
        }
        colList.currentIndex = colModel.count > 0 ? 0 : -1
        colList.positionViewAtBeginning()
    }

    function _result() {
        var out = []
        for (var i = 0; i < colModel.count; i++) {
            var row = colModel.get(i)
            out.push({ key: row.key, title: row.title, widthPx: row.widthPx, visible: row.shown })
        }
        return out
    }

    readonly property bool _hasCurrent: colList.currentIndex >= 0 && colList.currentIndex < colModel.count
    function _current(role, fallback) {
        _revision
        return _hasCurrent ? colModel.get(colList.currentIndex)[role] : fallback
    }

    function _setShown(row, shown) {
        if (row >= 0 && row < colModel.count)
            colModel.setProperty(row, "shown", shown)
    }

    function _moveCurrent(delta) {
        var from = colList.currentIndex
        var to = from + delta
        if (from < 0 || to < 0 || to >= colModel.count)
            return
        colModel.move(from, to, 1)
        colList.currentIndex = to
        colList.positionViewAtIndex(to, ListView.Contain)
    }

    function _centerOnOwner() {
        var owner = root.transientParent
        if (owner) {
            x = owner.x + Math.round((owner.width  - width)  / 2)
            y = owner.y + Math.round((owner.height - height) / 2)
            return
        }
        x = Math.round((Screen.width  - width)  / 2)
        y = Math.round((Screen.height - height) / 2)
    }

    Shortcut { sequence: "Escape"; onActivated: root.close() }

    onVisibleChanged: {
        if (!visible) return
        _centerOnOwner()
        _load(columnDefs)
        colList.forceActiveFocus()
    }

    ColumnLayout {
        anchors { fill: parent; margins: 16 }
        spacing: 10

        Text {
            text: qsTr("Columns")
            color: ColorPalette.textHeader
            font.pixelSize: 16 * App.fontScale
            font.bold: true
        }
        Text {
            Layout.fillWidth: true
            text: qsTr("Check the columns that you would like visible in this list. Use the Move Up and Move Down buttons to reorder the columns however you like.")
            color: ColorPalette.textSecond
            font.pixelSize: 12 * App.fontScale
            wrapMode: Text.WordWrap
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 10

            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.minimumWidth: 220
                color: ColorPalette.inputBg
                border.color: colList.activeFocus ? ColorPalette.borderFocus : ColorPalette.border
                radius: 3

                ListView {
                    id: colList
                    anchors { fill: parent; margins: 1 }
                    clip: true
                    model: colModel
                    boundsBehavior: Flickable.StopAtBounds
                    keyNavigationEnabled: true
                    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                    Keys.onSpacePressed: root._setShown(currentIndex, !root._current("shown", true))
                    Keys.onPressed: (event) => {
                        if (!(event.modifiers & Qt.ControlModifier)) return
                        if (event.key === Qt.Key_Up)        { root._moveCurrent(-1); event.accepted = true }
                        else if (event.key === Qt.Key_Down) { root._moveCurrent(1);  event.accepted = true }
                    }

                    delegate: Rectangle {
                        id: rowItem
                        required property int index
                        required property string title
                        required property bool shown
                        readonly property bool current: ListView.isCurrentItem

                        width: ListView.view.width
                        height: root.rowHeight
                        color: current ? ColorPalette.selectionBg
                             : (rowMa.containsMouse ? ColorPalette.hoverBg : "transparent")

                        Row {
                            anchors { left: parent.left; leftMargin: 8; right: parent.right; rightMargin: 8
                                      verticalCenter: parent.verticalCenter }
                            spacing: 8

                            Rectangle {
                                id: box
                                width: 16; height: 16; radius: 3
                                anchors.verticalCenter: parent.verticalCenter
                                color: rowItem.shown ? ColorPalette.accent : ColorPalette.inputBg
                                border.color: rowItem.shown ? ColorPalette.accent : ColorPalette.border
                                Text {
                                    anchors.centerIn: parent
                                    visible: rowItem.shown
                                    text: "✓"
                                    color: "#ffffff"
                                    font.pixelSize: 11
                                    font.bold: true
                                }
                            }
                            Text {
                                width: parent.width - box.width - parent.spacing
                                anchors.verticalCenter: parent.verticalCenter
                                text: rowItem.title
                                color: rowItem.current ? ColorPalette.selectionText
                                     : (rowItem.shown ? ColorPalette.textPrimary : ColorPalette.textSecond)
                                font.pixelSize: 12 * App.fontScale
                                elide: Text.ElideRight
                            }
                        }

                        MouseArea {
                            id: rowMa
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: (mouse) => {
                                colList.currentIndex = rowItem.index
                                colList.forceActiveFocus()
                                // The checkbox (plus a little slack) toggles; the
                                // rest of the row only selects.
                                if (mouse.x < box.x + box.width + 16)
                                    root._setShown(rowItem.index, !rowItem.shown)
                            }
                            onDoubleClicked: root._setShown(rowItem.index, !rowItem.shown)
                        }
                    }
                }
            }

            ColumnLayout {
                Layout.alignment: Qt.AlignTop
                // Layouts fill by default; without this the buttons take the
                // whole row and squeeze the list to nothing.
                Layout.fillWidth: false
                Layout.preferredWidth: 120 * App.fontScale
                spacing: 6

                DlgButton {
                    Layout.fillWidth: true
                    implicitHeight: 30
                    text: qsTr("Move Up")
                    enabled: root._hasCurrent && colList.currentIndex > 0
                    onClicked: root._moveCurrent(-1)
                }
                DlgButton {
                    Layout.fillWidth: true
                    implicitHeight: 30
                    text: qsTr("Move Down")
                    enabled: root._hasCurrent && colList.currentIndex < colModel.count - 1
                    onClicked: root._moveCurrent(1)
                }
                Item { Layout.preferredHeight: 6 }
                DlgButton {
                    Layout.fillWidth: true
                    implicitHeight: 30
                    text: qsTr("Show")
                    enabled: root._hasCurrent && !root._current("shown", true)
                    onClicked: root._setShown(colList.currentIndex, true)
                }
                DlgButton {
                    Layout.fillWidth: true
                    implicitHeight: 30
                    text: qsTr("Hide")
                    enabled: root._hasCurrent && root._current("shown", false)
                    onClicked: root._setShown(colList.currentIndex, false)
                }
                Item { Layout.preferredHeight: 6 }
                DlgButton {
                    Layout.fillWidth: true
                    implicitHeight: 30
                    text: qsTr("Reset")
                    onClicked: root._load(root.defaultDefs)
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            enabled: root._hasCurrent

            Text {
                text: qsTr("The selected column should be")
                color: ColorPalette.textSecond
                font.pixelSize: 12 * App.fontScale
            }
            TextField {
                id: widthField
                implicitWidth: 64
                implicitHeight: 26
                leftPadding: 6; rightPadding: 6; topPadding: 0; bottomPadding: 0
                horizontalAlignment: TextInput.AlignRight
                color: ColorPalette.textPrimary
                font.pixelSize: 12 * App.fontScale
                selectByMouse: true
                validator: IntValidator { bottom: root.minColumnWidth; top: root.maxColumnWidth }
                background: Rectangle {
                    color: ColorPalette.inputBg
                    border.color: widthField.activeFocus ? ColorPalette.borderFocus : ColorPalette.border
                    radius: 3
                }

                // Re-seeded on every selection change (a text binding would be
                // broken by the first keystroke).
                function reload() { text = root._hasCurrent ? String(root._current("widthPx", 0)) : "" }
                Connections {
                    target: colList
                    function onCurrentIndexChanged() { widthField.reload() }
                }
                onEditingFinished: {
                    var v = parseInt(text, 10)
                    if (root._hasCurrent && !isNaN(v))
                        colModel.setProperty(colList.currentIndex, "widthPx",
                                             Math.max(root.minColumnWidth, Math.min(v, root.maxColumnWidth)))
                    reload()
                }
            }
            Text {
                text: qsTr("pixels wide")
                color: ColorPalette.textSecond
                font.pixelSize: 12 * App.fontScale
            }
            Item { Layout.fillWidth: true }
        }

        Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: ColorPalette.border }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            Item { Layout.fillWidth: true }
            DlgButton {
                text: qsTr("OK")
                primary: true
                onClicked: {
                    // Commit a width typed without leaving the field first.
                    widthField.editingFinished()
                    root.columnsChanged(root._result())
                    root.close()
                }
            }
            DlgButton {
                text: qsTr("Cancel")
                onClicked: root.close()
            }
        }
    }
}
