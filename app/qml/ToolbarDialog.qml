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
    title: qsTr("Toolbar")
    width: 520
    height: 460
    minimumWidth: 460
    minimumHeight: 380
    color: ColorPalette.cardBg
    flags: Qt.Dialog | Qt.WindowTitleHint | Qt.WindowCloseButtonHint

    Material.theme: ColorPalette.materialTheme
    Material.foreground: ColorPalette.textPrimary
    Material.background: ColorPalette.materialBg
    Material.accent: "#4488dd"

    property var buttonDefs: []
    property var localDefs: []

    signal toolbarChanged(var defs)

    function syncLocal() {
        var defs = (buttonDefs && buttonDefs.slice) ? buttonDefs.slice() : _defaultDefs()
        // ── Sync with View menu toggles single source of truth for search/rss ──
        if (App.settings) {
            for (var i = 0; i < defs.length; i++) {
                if (defs[i].key === "search_engine")
                    defs[i] = Object.assign({}, defs[i], { enabled: App.settings.showSearchEngine })
                if (defs[i].key === "rss")
                    defs[i] = Object.assign({}, defs[i], { enabled: App.settings.showRssReader })
            }
        }
        localDefs = defs
    }

    function _defaultDefs() {
        return [
            {key:"add",          label: qsTr("Add URL"),        iconSrc:"icons/link.svg",           enabled:true},
            {key:"resume",       label: qsTr("Resume"),         iconSrc:"icons/resume.svg",         enabled:true},
            {key:"stop",         label: qsTr("Stop"),           iconSrc:"icons/pause.svg",          enabled:true},
            {key:"stop_all",     label: qsTr("Stop All"),       iconSrc:"icons/stop_all.svg",       enabled:true},
            {key:"delete",       label: qsTr("Delete"),         iconSrc:"icons/wastebasket.svg",    enabled:true},
            {key:"delete_done",  label: qsTr("Delete Done"),    iconSrc:"icons/delete_done.svg",    enabled:true},
            {key:"options",      label: qsTr("Options"),        iconSrc:"icons/tools.svg",          enabled:true},
            {key:"scheduler",    label: qsTr("Scheduler"),      iconSrc:"icons/scheduler.svg",      enabled:true},
            {key:"start_queue",  label: qsTr("Start Queue"),    iconSrc:"icons/start_queue.svg",    enabled:true},
            {key:"stop_queue",   label: qsTr("Stop Queue"),     iconSrc:"icons/stop_queue.svg",     enabled:true},
            {key:"grabber",      label: qsTr("Grabber"),        iconSrc:"icons/grabber.svg",        enabled:true},
            {key:"search_engine",label: qsTr("Search Engine"),  iconSrc:"icons/magnifying_glass.svg",enabled:true},
            {key:"rss",          label: qsTr("RSS"),            iconSrc:"icons/rss.svg",            enabled:true}
        ]
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

    onVisibleChanged: if (visible) { _centerOnOwner(); syncLocal() }

    function swap(i, j) {
        var savedY = btnListView.contentY
        var defs = localDefs.slice()
        var tmp = defs[i]; defs[i] = defs[j]; defs[j] = tmp
        localDefs = defs
        Qt.callLater(function() { btnListView.contentY = savedY })
    }

    function _isSeparator(idx) {
        return idx >= 0 && idx < localDefs.length && localDefs[idx].key === "separator"
    }

    function _selectedIsSeparator() {
        return _isSeparator(btnListView.currentIndex)
    }

    function _buttonEnabled(idx) {
        return idx >= 0 && idx < localDefs.length && localDefs[idx].key !== "separator" && localDefs[idx].enabled
    }

    function _buttonDisabled(idx) {
        return idx >= 0 && idx < localDefs.length && localDefs[idx].key !== "separator" && !localDefs[idx].enabled
    }

    ColumnLayout {
        anchors { fill: parent; margins: 16 }
        spacing: 10

        Text { text: qsTr("Toolbar"); color: ColorPalette.textHeader; font.pixelSize: 16 * App.fontScale; font.bold: true }
        Text {
            text: qsTr("Customize toolbar buttons. Use Move Up and Move Down to reorder. Check to enable, uncheck to disable.")
            color: "#909090"; font.pixelSize: 12 * App.fontScale
            wrapMode: Text.WordWrap; Layout.fillWidth: true
        }
        Rectangle { Layout.fillWidth: true; height: 1; color: ColorPalette.border }

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 12

            // Button list
            Rectangle {
                Layout.fillHeight: true
                Layout.preferredWidth: 280
                color: ColorPalette.panelBg
                border.color: ColorPalette.border
                radius: 3
                clip: true

                ListView {
                    id: btnListView
                    anchors { fill: parent; margins: 2 }
                    model: root.localDefs
                    currentIndex: 0

                    delegate: Rectangle {
                        width: btnListView.width
                        height: root._isSeparator(index) ? 20 : 34
                        color: btnListView.currentIndex === index ? ColorPalette.selectionBg :
                                 (itemMa.containsMouse ? ColorPalette.hoverBg : "transparent")

                        // ── Separator item draw horizontal line ──────────
                        Rectangle {
                            visible: root._isSeparator(index)
                            anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; leftMargin: 12; rightMargin: 12 }
                            height: 1
                            color: "#555"
                        }

                        RowLayout {
                            visible: !root._isSeparator(index)
                            anchors { fill: parent; leftMargin: 8; rightMargin: 8 }
                            spacing: 8

                            StyledCheckBox {
                                id: chkBox
                                checked: modelData.enabled !== false
                                topPadding: 0; bottomPadding: 0
                                onCheckedChanged: {
                                    var idx = index
                                    var val = checked
                                    var savedY = btnListView.contentY
                                    Qt.callLater(function() {
                                        var defs = root.localDefs.slice()
                                        defs[idx] = Object.assign({}, defs[idx], { enabled: val })
                                        root.localDefs = defs
                                        btnListView.contentY = savedY
                                    })
                                }
                            }

                            Image {
                                source: modelData.iconSrc || ""
                                sourceSize: Qt.size(18, 18)
                                smooth: true
                                Layout.preferredWidth: 18
                                Layout.preferredHeight: 18
                                fillMode: Image.PreserveAspectFit
                                visible: modelData.iconSrc !== undefined
                            }

                            Text {
                                text: modelData.label || ""
                                color: btnListView.currentIndex === index ? "#ffffff" : ColorPalette.textPrimary
                                font.pixelSize: 13 * App.fontScale
                                Layout.fillWidth: true
                            }
                        }

                        MouseArea {
                            id: itemMa
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: btnListView.currentIndex = index
                        }
                    }
                }
            }

            // Buttons
            ColumnLayout {
                spacing: 6

                Rectangle {
                    width: 110; height: 28; radius: 3
                    color: moveUpMa.containsMouse && btnListView.currentIndex > 0 ? ColorPalette.selectionBg : ColorPalette.dividerBg
                    border.color: "#555"; border.width: 1
                    opacity: btnListView.currentIndex > 0 ? 1.0 : 0.4
                    Text { anchors.centerIn: parent; text: qsTr("Move Up"); color: ColorPalette.textPrimary; font.pixelSize: 12 * App.fontScale }
                    MouseArea {
                        id: moveUpMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: btnListView.currentIndex > 0 ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onClicked: {
                            const i = btnListView.currentIndex
                            if (i > 0) { root.swap(i, i - 1); btnListView.currentIndex = i - 1 }
                        }
                    }
                }

                Rectangle {
                    width: 110; height: 28; radius: 3
                    color: moveDownMa.containsMouse && btnListView.currentIndex < root.localDefs.length - 1 ? ColorPalette.selectionBg : ColorPalette.dividerBg
                    border.color: "#555"; border.width: 1
                    opacity: btnListView.currentIndex < root.localDefs.length - 1 ? 1.0 : 0.4
                    Text { anchors.centerIn: parent; text: qsTr("Move Down"); color: ColorPalette.textPrimary; font.pixelSize: 12 * App.fontScale }
                    MouseArea {
                        id: moveDownMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: btnListView.currentIndex < root.localDefs.length - 1 ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onClicked: {
                            const i = btnListView.currentIndex
                            if (i < root.localDefs.length - 1) { root.swap(i, i + 1); btnListView.currentIndex = i + 1 }
                        }
                    }
                }

                Rectangle { width: 110; height: 1; color: ColorPalette.border }

                Rectangle {
                    width: 110; height: 28; radius: 3
                    property bool canEnable: !root._selectedIsSeparator() && root._buttonDisabled(btnListView.currentIndex)
                    color: enableMa.containsMouse && canEnable ? ColorPalette.selectionBg : ColorPalette.dividerBg
                    border.color: "#555"; border.width: 1
                    opacity: canEnable ? 1.0 : 0.4
                    Text { anchors.centerIn: parent; text: qsTr("Enable"); color: ColorPalette.textPrimary; font.pixelSize: 12 * App.fontScale }
                    MouseArea {
                        id: enableMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: parent.canEnable ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onClicked: {
                            if (parent.canEnable) {
                                var savedY = btnListView.contentY
                                var defs = root.localDefs.slice()
                                defs[btnListView.currentIndex] = Object.assign({}, defs[btnListView.currentIndex], { enabled: true })
                                root.localDefs = defs
                                btnListView.contentY = savedY
                            }
                        }
                    }
                }

                Rectangle {
                    width: 110; height: 28; radius: 3
                    property bool canDisable: !root._selectedIsSeparator() && root._buttonEnabled(btnListView.currentIndex)
                    color: disableMa.containsMouse && canDisable ? ColorPalette.selectionBg : ColorPalette.dividerBg
                    border.color: "#555"; border.width: 1
                    opacity: canDisable ? 1.0 : 0.4
                    Text { anchors.centerIn: parent; text: qsTr("Disable"); color: ColorPalette.textPrimary; font.pixelSize: 12 * App.fontScale }
                    MouseArea {
                        id: disableMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: parent.canDisable ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onClicked: {
                            if (parent.canDisable) {
                                var savedY = btnListView.contentY
                                var defs = root.localDefs.slice()
                                defs[btnListView.currentIndex] = Object.assign({}, defs[btnListView.currentIndex], { enabled: false })
                                root.localDefs = defs
                                btnListView.contentY = savedY
                            }
                        }
                    }
                }

                Rectangle { width: 110; height: 1; color: ColorPalette.border }

                Rectangle {
                    width: 110; height: 28; radius: 3
                    color: addSepMa.containsMouse ? ColorPalette.selectionBg : ColorPalette.dividerBg
                    border.color: "#555"; border.width: 1
                    Text { anchors.centerIn: parent; text: qsTr("Add Separator"); color: ColorPalette.textPrimary; font.pixelSize: 12 * App.fontScale }
                    MouseArea {
                        id: addSepMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            var savedY = btnListView.contentY
                            const i = btnListView.currentIndex >= 0 ? btnListView.currentIndex + 1 : root.localDefs.length
                            var defs = root.localDefs.slice()
                            defs.splice(i, 0, { key: "separator" })
                            root.localDefs = defs
                            btnListView.currentIndex = i
                            Qt.callLater(function() { btnListView.contentY = savedY })
                        }
                    }
                }

                Rectangle {
                    width: 110; height: 28; radius: 3
                    color: removeSepMa.containsMouse && root._selectedIsSeparator() ? "#442020" : ColorPalette.dividerBg
                    border.color: "#555"; border.width: 1
                    opacity: root._selectedIsSeparator() ? 1.0 : 0.4
                    Text { anchors.centerIn: parent; text: qsTr("Remove"); color: ColorPalette.textHeader; font.pixelSize: 12 * App.fontScale }
                    MouseArea {
                        id: removeSepMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: root._selectedIsSeparator() ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onClicked: {
                            if (root._selectedIsSeparator()) {
                                var savedY = btnListView.contentY
                                var defs = root.localDefs.slice()
                                defs.splice(btnListView.currentIndex, 1)
                                root.localDefs = defs
                                btnListView.currentIndex = Math.min(btnListView.currentIndex, defs.length - 1)
                                btnListView.contentY = savedY
                            }
                        }
                    }
                }

                Rectangle {
                    width: 110; height: 28; radius: 3
                    color: resetMa.containsMouse ? "#443020" : ColorPalette.dividerBg
                    border.color: "#555"; border.width: 1
                    Text { anchors.centerIn: parent; text: qsTr("Reset"); color: ColorPalette.textHeader; font.pixelSize: 12 * App.fontScale }
                    MouseArea {
                        id: resetMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.toolbarChanged(null)  // null = reset to defaults
                    }
                }

                Item { Layout.fillHeight: true }
            }
        }

        Rectangle { Layout.fillWidth: true; height: 1; color: ColorPalette.border }

        // OK / Cancel
        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            Item { Layout.fillWidth: true }
            DlgButton {
                text: qsTr("OK")
                primary: true
                onClicked: {
                    root.toolbarChanged(root.localDefs)
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
