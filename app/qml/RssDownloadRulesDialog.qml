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
import QtQuick.Dialogs

Window {
    id: root
    width: 860
    height: 600
    minimumWidth: 720
    minimumHeight: 480
    title: "RSS Auto Download Rules"
    color: "#1e1e1e"
    flags: Qt.Dialog | Qt.WindowTitleHint | Qt.WindowCloseButtonHint | Qt.WindowSystemMenuHint

    property var rules: []
    property int selectedRule: -1

    // Category and queue lists populated from the app models
    property var categoryIds: []
    property var categoryLabels: []
    property var queueIds: []
    property var queueNames: []

    function _refreshCategoryModel() {
        var ids = [""], labels = ["(Default)"]
        var n = App.categoryModel.rowCount()
        for (var i = 0; i < n; i++) {
            var d = App.categoryModel.categoryData(i)
            ids.push(d.id); labels.push(d.label)
        }
        categoryIds = ids; categoryLabels = labels
    }

    function _refreshQueueModel() {
        var ids = App.queueIds()
        var names = App.queueNames()
        var allIds = [""].concat(ids)
        var allNames = ["(Default)"].concat(names)
        queueIds = allIds; queueNames = allNames
    }

    readonly property var currentRule: (selectedRule >= 0 && selectedRule < rules.length)
        ? rules[selectedRule] : null
    readonly property bool hasSelection: selectedRule >= 0 && selectedRule < rules.length

    // ── Share-limit pill state (kept separately so pills don't flicker on keystrokes) ──
    property int ratioMode: 0
    property int seedMode:  0
    property int inactMode: 0

    function load() {
        try {
            var parsed = JSON.parse(App.settings.rssDownloadRulesJson || "[]")
            rules = Array.isArray(parsed) ? parsed : []
        } catch (e) {
            rules = []
        }
        selectedRule = rules.length > 0 ? 0 : -1
        loadRuleIntoForm()
    }

    function save() {
        commitCurrentRuleToModel()
        App.settings.rssDownloadRulesJson = JSON.stringify(rules)
    }

    function makeBlankRule() {
        return {
            name: "New Rule",
            enabled: true,
            useRegex: false,
            mustContain: "",
            mustNotContain: "",
            episodeFilter: "",
            useSmartEpisodeFilter: false,
            ignoreDays: 0,
            savePath: "",
            category: "",
            queue: "",
            shareRatioLimit: -1.0,
            seedingTimeLimitMins: -1,
            inactiveSeedingTimeLimitMins: -1
        }
    }

    function commitCurrentRuleToModel() {
        if (!hasSelection) return
        var r = Object.assign({}, rules[selectedRule])
        r.name                         = ruleNameField.text.trim() || "Unnamed"
        r.enabled                      = enabledCheck.checked
        r.useRegex                     = useRegexCheck.checked
        r.mustContain                  = mustContainField.text
        r.mustNotContain               = mustNotContainField.text
        r.episodeFilter                = episodeFilterField.text
        r.useSmartEpisodeFilter        = smartEpisodeCheck.checked
        r.ignoreDays                   = parseInt(ignoreDaysField.text) || 0
        r.savePath                     = savePathField.text
        r.category                     = (catCombo.currentIndex > 0 && catCombo.currentIndex < root.categoryIds.length)
                                             ? root.categoryIds[catCombo.currentIndex] : ""
        r.queue                        = (queueCombo.currentIndex > 0 && queueCombo.currentIndex < root.queueIds.length)
                                             ? root.queueIds[queueCombo.currentIndex] : ""
        r.shareRatioLimit              = _modeToLimit(ratioMode,  parseFloat(ratioInput.text))
        r.seedingTimeLimitMins         = _modeToLimit(seedMode,   parseInt(seedInput.text))
        r.inactiveSeedingTimeLimitMins = _modeToLimit(inactMode,  parseInt(inactInput.text))
        var arr = rules.slice()
        arr[selectedRule] = r
        rules = arr
    }

    function loadRuleIntoForm() {
        var r = currentRule
        if (!r) {
            ruleNameField.text       = ""
            enabledCheck.checked     = true
            useRegexCheck.checked    = false
            mustContainField.text    = ""
            mustNotContainField.text = ""
            episodeFilterField.text  = ""
            smartEpisodeCheck.checked = false
            ignoreDaysField.text     = "0"
            savePathField.text       = ""
            catCombo.currentIndex    = 0
            queueCombo.currentIndex  = 0
            ratioMode = 0; ratioInput.text = ""
            seedMode  = 0; seedInput.text  = ""
            inactMode = 0; inactInput.text = ""
            return
        }
        ruleNameField.text           = r.name || ""
        enabledCheck.checked         = r.enabled !== false
        useRegexCheck.checked        = !!r.useRegex
        mustContainField.text        = r.mustContain || ""
        mustNotContainField.text     = r.mustNotContain || ""
        episodeFilterField.text      = r.episodeFilter || ""
        smartEpisodeCheck.checked    = !!r.useSmartEpisodeFilter
        ignoreDaysField.text         = String(r.ignoreDays || 0)
        savePathField.text           = r.savePath || ""
        var catIdx = r.category ? root.categoryIds.indexOf(r.category) : 0
        catCombo.currentIndex        = catIdx >= 0 ? catIdx : 0
        var qIdx = r.queue ? root.queueIds.indexOf(r.queue) : 0
        queueCombo.currentIndex      = qIdx >= 0 ? qIdx : 0
        ratioMode = _limitToMode(r.shareRatioLimit)
        ratioInput.text = ratioMode === 2 ? Number(r.shareRatioLimit).toFixed(2) : ""
        seedMode  = _limitToMode(r.seedingTimeLimitMins)
        seedInput.text  = seedMode  === 2 ? String(Math.round(r.seedingTimeLimitMins)) : ""
        inactMode = _limitToMode(r.inactiveSeedingTimeLimitMins)
        inactInput.text = inactMode === 2 ? String(Math.round(r.inactiveSeedingTimeLimitMins)) : ""
    }

    function _limitToMode(v) {
        if (v === undefined || v === null || v < -1.5) return 1
        if (v < 0) return 0
        return 2
    }
    function _modeToLimit(mode, value) {
        if (mode === 0) return -1.0
        if (mode === 1) return -2.0
        return isNaN(value) ? 0 : Math.max(0, value)
    }

    // Inline checkbox component: an Item containing a RowLayout + a full-size MouseArea overlay.
    // Must be an Item (not RowLayout) so anchors.fill works on the MouseArea without layout warnings.
    component ChkRow: Item {
        id: chkRow
        implicitHeight: chkInner.implicitHeight
        implicitWidth:  chkInner.implicitWidth
        property bool checked: false
        property alias label: chkLabel.text
        property alias subLabel: chkSub.text
        property bool enabled: true

        signal toggled()

        RowLayout {
            id: chkInner
            anchors { left: parent.left; top: parent.top }
            spacing: 8

            Rectangle {
                width: 16; height: 16; radius: 3
                color: chkRow.checked ? "#4488dd" : "#1b1b1b"
                border.color: chkRow.checked ? "#4488dd" : "#3a3a3a"
                Text {
                    visible: chkRow.checked
                    anchors.centerIn: parent
                    text: "✓"; color: "#fff"; font.pixelSize: 11; font.bold: true
                }
            }
            ColumnLayout {
                spacing: 1
                Text { id: chkLabel; color: chkRow.enabled ? "#c0c0c0" : "#666"; font.pixelSize: 12 }
                Text {
                    id: chkSub
                    visible: text.length > 0
                    color: "#7a8a9a"; font.pixelSize: 10
                }
            }
        }
        // Overlay covers the whole item — safe because this MouseArea is a direct child of an Item
        MouseArea {
            anchors.fill: parent
            enabled: chkRow.enabled
            cursorShape: Qt.PointingHandCursor
            onClicked: { chkRow.checked = !chkRow.checked; chkRow.toggled() }
        }
    }

    Connections {
        target: App.categoryModel
        function onModelReset() { root._refreshCategoryModel() }
        function onDataChanged() { root._refreshCategoryModel() }
        function onRowsInserted() { root._refreshCategoryModel() }
        function onRowsRemoved()  { root._refreshCategoryModel() }
    }

    Component.onCompleted: {
        App.setWindowIcon(root, "qrc:/qt/qml/com/stellar/app/app/qml/icons/rss.png")
        _refreshCategoryModel()
        _refreshQueueModel()
        load()
    }
    onVisibleChanged: {
        if (visible) {
            _refreshCategoryModel()
            _refreshQueueModel()
            load()
        }
    }

    // ─── Root layout: vertical — content row + footer ─────────────────────────
    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // ── Main content row ─────────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 0

            // ── Left panel: rule list ─────────────────────────────────────────
            Rectangle {
                Layout.fillHeight: true
                width: 210
                color: "#1b1b1b"

                ColumnLayout {
                    anchors.fill: parent
                    spacing: 0

                    Rectangle {
                        Layout.fillWidth: true
                        height: 30
                        color: "#252525"
                        Text {
                            anchors { verticalCenter: parent.verticalCenter; left: parent.left; leftMargin: 10 }
                            text: "Download Rules"
                            color: "#c0c0c0"; font.pixelSize: 11; font.bold: true
                        }
                        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: "#333" }
                    }

                    ListView {
                        id: ruleList
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        model: rules
                        currentIndex: root.selectedRule
                        boundsBehavior: Flickable.StopAtBounds

                        delegate: Rectangle {
                            required property var modelData
                            required property int index
                            width: ruleList.width
                            height: 28
                            color: root.selectedRule === index ? "#1e3a6e"
                                 : (ruleMa.containsMouse ? "#2a2a3a" : "transparent")

                            RowLayout {
                                anchors { fill: parent; leftMargin: 8; rightMargin: 6 }
                                spacing: 4
                                Rectangle {
                                    width: 6; height: 6; radius: 3
                                    color: modelData.enabled !== false ? "#4dbb6d" : "#666"
                                }
                                Text {
                                    Layout.fillWidth: true
                                    text: modelData.name || "Unnamed"
                                    color: root.selectedRule === index ? "#ffffff" : "#cccccc"
                                    font.pixelSize: 12
                                    elide: Text.ElideRight
                                }
                            }

                            MouseArea {
                                id: ruleMa
                                anchors.fill: parent
                                hoverEnabled: true
                                onClicked: {
                                    root.commitCurrentRuleToModel()
                                    root.selectedRule = index
                                    root.loadRuleIntoForm()
                                }
                            }
                        }
                    }

                    Rectangle { Layout.fillWidth: true; height: 1; color: "#333" }

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.margins: 6
                        spacing: 4

                        DlgButton {
                            text: "Add"
                            Layout.fillWidth: true
                            onClicked: {
                                root.commitCurrentRuleToModel()
                                var arr = root.rules.slice()
                                arr.push(root.makeBlankRule())
                                root.rules = arr
                                root.selectedRule = arr.length - 1
                                root.loadRuleIntoForm()
                            }
                        }
                        DlgButton {
                            text: "Remove"
                            destructive: true
                            enabled: root.hasSelection
                            Layout.fillWidth: true
                            onClicked: {
                                if (!root.hasSelection) return
                                var arr = root.rules.slice()
                                arr.splice(root.selectedRule, 1)
                                root.rules = arr
                                root.selectedRule = Math.min(root.selectedRule, arr.length - 1)
                                root.loadRuleIntoForm()
                            }
                        }
                    }
                }
            }

            // Divider
            Rectangle { width: 1; Layout.fillHeight: true; color: "#2d2d2d" }

            // ── Right panel: rule editor ──────────────────────────────────────
            ScrollView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                contentWidth: availableWidth
                ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
                // Note: ScrollView itself is always enabled — we disable individual
                // controls inside when no rule is selected.

                ColumnLayout {
                    width: parent.width
                    spacing: 0

                    // Placeholder shown when no rule is selected
                    Item {
                        Layout.fillWidth: true
                        height: 80
                        visible: !root.hasSelection
                        Text {
                            anchors.centerIn: parent
                            text: "Click \"Add\" to create a download rule"
                            color: "#555"; font.pixelSize: 13
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.margins: 14
                        spacing: 10
                        visible: root.hasSelection

                        // ── Rule name + enabled ───────────────────────────────
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8
                            TextField {
                                id: ruleNameField
                                Layout.fillWidth: true
                                placeholderText: "Rule name"
                                color: "#d0d0d0"; font.pixelSize: 13
                                leftPadding: 8; selectByMouse: true
                                background: Rectangle {
                                    color: "#1b1b1b"
                                    border.color: parent.activeFocus ? "#4488dd" : "#3a3a3a"; radius: 3
                                }
                            }
                            ChkRow {
                                id: enabledCheck
                                label: "Enabled"
                                checked: true
                            }
                        }

                        // ── Filter rules card ─────────────────────────────────
                        Rectangle {
                            Layout.fillWidth: true
                            color: "#1e1e1e"; border.color: "#2d2d2d"; radius: 4
                            implicitHeight: filterCol.implicitHeight + 20

                            ColumnLayout {
                                id: filterCol
                                anchors { fill: parent; margins: 10 }
                                spacing: 10

                                Text { text: "FILTER RULES"; color: "#8899aa"; font.pixelSize: 10; font.bold: true }

                                ChkRow {
                                    id: useRegexCheck
                                    label: "Use regular expressions"
                                }

                                GridLayout {
                                    Layout.fillWidth: true
                                    columns: 2
                                    columnSpacing: 10
                                    rowSpacing: 8

                                    Text { text: "Must contain:"; color: "#8899aa"; font.pixelSize: 12 }
                                    TextField {
                                        id: mustContainField
                                        Layout.fillWidth: true
                                        placeholderText: useRegexCheck.checked ? "regex pattern" : "keyword1 keyword2 | keyword3"
                                        color: "#d0d0d0"; font.pixelSize: 12
                                        leftPadding: 6; selectByMouse: true
                                        background: Rectangle {
                                            color: "#1b1b1b"
                                            border.color: parent.activeFocus ? "#4488dd" : "#3a3a3a"; radius: 2
                                        }
                                    }

                                    Text { text: "Must not contain:"; color: "#8899aa"; font.pixelSize: 12 }
                                    TextField {
                                        id: mustNotContainField
                                        Layout.fillWidth: true
                                        placeholderText: useRegexCheck.checked ? "regex pattern" : "keyword1 keyword2"
                                        color: "#d0d0d0"; font.pixelSize: 12
                                        leftPadding: 6; selectByMouse: true
                                        background: Rectangle {
                                            color: "#1b1b1b"
                                            border.color: parent.activeFocus ? "#4488dd" : "#3a3a3a"; radius: 2
                                        }
                                    }

                                    Text { text: "Episode filter:"; color: "#8899aa"; font.pixelSize: 12 }
                                    TextField {
                                        id: episodeFilterField
                                        Layout.fillWidth: true
                                        placeholderText: "e.g. 1x01-1x24  or  2x01;"
                                        color: "#d0d0d0"; font.pixelSize: 12
                                        leftPadding: 6; selectByMouse: true
                                        background: Rectangle {
                                            color: "#1b1b1b"
                                            border.color: parent.activeFocus ? "#4488dd" : "#3a3a3a"; radius: 2
                                        }
                                    }
                                }

                                ChkRow {
                                    id: smartEpisodeCheck
                                    label: "Use Smart Episode Filter"
                                    subLabel: "Skips episodes already matched by previous rule triggers"
                                }

                                RowLayout {
                                    Layout.fillWidth: true; spacing: 8
                                    Text { text: "Ignore subsequent matches for"; color: "#8899aa"; font.pixelSize: 12 }
                                    TextField {
                                        id: ignoreDaysField
                                        implicitWidth: 64
                                        text: "0"
                                        validator: IntValidator { bottom: 0; top: 9999 }
                                        color: "#d0d0d0"; font.pixelSize: 12
                                        leftPadding: 6; rightPadding: 6; selectByMouse: true
                                        background: Rectangle {
                                            color: "#1b1b1b"
                                            border.color: parent.activeFocus ? "#4488dd" : "#3a3a3a"; radius: 2
                                        }
                                    }
                                    Text { text: "days  (0 = disabled)"; color: "#8899aa"; font.pixelSize: 12 }
                                    Item { Layout.fillWidth: true }
                                }
                            }
                        }

                        // ── Download settings card ────────────────────────────
                        Rectangle {
                            Layout.fillWidth: true
                            color: "#1e1e1e"; border.color: "#2d2d2d"; radius: 4
                            implicitHeight: saveCol.implicitHeight + 20

                            ColumnLayout {
                                id: saveCol
                                anchors { fill: parent; margins: 10 }
                                spacing: 10

                                Text { text: "DOWNLOAD SETTINGS"; color: "#8899aa"; font.pixelSize: 10; font.bold: true }

                                GridLayout {
                                    Layout.fillWidth: true
                                    columns: 2
                                    columnSpacing: 10
                                    rowSpacing: 8

                                    Text { text: "Save at:"; color: "#8899aa"; font.pixelSize: 12 }
                                    RowLayout {
                                        Layout.fillWidth: true; spacing: 6
                                        TextField {
                                            id: savePathField
                                            Layout.fillWidth: true
                                            placeholderText: "Leave empty to use default save path"
                                            color: "#d0d0d0"; font.pixelSize: 12
                                            leftPadding: 6; selectByMouse: true
                                            background: Rectangle {
                                                color: "#1b1b1b"
                                                border.color: parent.activeFocus ? "#4488dd" : "#3a3a3a"; radius: 2
                                            }
                                        }
                                        DlgButton { text: "Browse..."; onClicked: folderDialog.open() }
                                    }

                                    Text { text: "Category:"; color: "#8899aa"; font.pixelSize: 12 }
                                    ComboBox {
                                        id: catCombo
                                        Layout.fillWidth: true
                                        model: root.categoryLabels
                                        contentItem: Text {
                                            leftPadding: 10
                                            text: catCombo.displayText
                                            color: "#d0d0d0"; font.pixelSize: 12
                                            verticalAlignment: Text.AlignVCenter
                                            elide: Text.ElideRight
                                        }
                                        background: Rectangle {
                                            color: "#252525"
                                            border.color: catCombo.activeFocus ? "#4488dd" : "#3c3c3c"
                                            radius: 4
                                        }
                                        popup.background: Rectangle { color: "#252525"; border.color: "#3c3c3c"; radius: 4 }
                                        delegate: ItemDelegate {
                                            required property string modelData
                                            required property int index
                                            width: catCombo.width
                                            contentItem: Text {
                                                text: modelData
                                                color: catCombo.currentIndex === index ? "#4488dd" : "#d0d0d0"
                                                font.pixelSize: 12; leftPadding: 10
                                                verticalAlignment: Text.AlignVCenter
                                            }
                                            background: Rectangle {
                                                color: hovered ? "#2a2a3a" : "transparent"
                                            }
                                        }
                                    }

                                    Text { text: "Queue:"; color: "#8899aa"; font.pixelSize: 12 }
                                    ComboBox {
                                        id: queueCombo
                                        Layout.fillWidth: true
                                        model: root.queueNames
                                        contentItem: Text {
                                            leftPadding: 10
                                            text: queueCombo.displayText
                                            color: "#d0d0d0"; font.pixelSize: 12
                                            verticalAlignment: Text.AlignVCenter
                                            elide: Text.ElideRight
                                        }
                                        background: Rectangle {
                                            color: "#252525"
                                            border.color: queueCombo.activeFocus ? "#4488dd" : "#3c3c3c"
                                            radius: 4
                                        }
                                        popup.background: Rectangle { color: "#252525"; border.color: "#3c3c3c"; radius: 4 }
                                        delegate: ItemDelegate {
                                            required property string modelData
                                            required property int index
                                            width: queueCombo.width
                                            contentItem: Text {
                                                text: modelData
                                                color: queueCombo.currentIndex === index ? "#4488dd" : "#d0d0d0"
                                                font.pixelSize: 12; leftPadding: 10
                                                verticalAlignment: Text.AlignVCenter
                                            }
                                            background: Rectangle {
                                                color: hovered ? "#2a2a3a" : "transparent"
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // ── Share limits card ─────────────────────────────────
                        Rectangle {
                            Layout.fillWidth: true
                            color: "#1e1e1e"; border.color: "#2d2d2d"; radius: 4
                            implicitHeight: shareCol.implicitHeight + 20

                            ColumnLayout {
                                id: shareCol
                                anchors { fill: parent; margins: 10 }
                                spacing: 10

                                Text { text: "TORRENT SHARE LIMITS"; color: "#8899aa"; font.pixelSize: 10; font.bold: true }

                                // ── Ratio ─────────────────────────────────────
                                ColumnLayout {
                                    Layout.fillWidth: true; spacing: 6
                                    Text { text: "Ratio"; color: "#c0c0c0"; font.pixelSize: 12 }
                                    RowLayout {
                                        Layout.fillWidth: true; spacing: 6
                                        Repeater {
                                            model: ["Default", "Unlimited", "Set to"]
                                            delegate: Rectangle {
                                                required property int    index
                                                required property string modelData
                                                height: 24
                                                implicitWidth: ratPillLbl.implicitWidth + 16
                                                radius: 3
                                                color: root.ratioMode === index ? "#1a3a6a" : "#252525"
                                                border.color: root.ratioMode === index ? "#4488dd" : "#3a3a3a"
                                                Text {
                                                    id: ratPillLbl
                                                    anchors.centerIn: parent
                                                    text: modelData
                                                    color: root.ratioMode === index ? "#88aaee" : "#888888"
                                                    font.pixelSize: 11
                                                }
                                                MouseArea {
                                                    anchors.fill: parent
                                                    onClicked: root.ratioMode = index
                                                }
                                            }
                                        }
                                        TextField {
                                            id: ratioInput
                                            visible: root.ratioMode === 2
                                            implicitWidth: 80
                                            color: "#d0d0d0"; font.pixelSize: 12
                                            leftPadding: 6; rightPadding: 6; selectByMouse: true
                                            validator: DoubleValidator { bottom: 0.0; top: 9999.0; decimals: 2; notation: DoubleValidator.StandardNotation }
                                            background: Rectangle {
                                                color: "#1b1b1b"
                                                border.color: parent.activeFocus ? "#4488dd" : "#3a3a3a"; radius: 2
                                            }
                                        }
                                        Item { Layout.fillWidth: true }
                                    }
                                }

                                Rectangle { Layout.fillWidth: true; height: 1; color: "#2a2a2a" }

                                // ── Seeding time ──────────────────────────────
                                ColumnLayout {
                                    Layout.fillWidth: true; spacing: 6
                                    Text { text: "Seeding time"; color: "#c0c0c0"; font.pixelSize: 12 }
                                    RowLayout {
                                        Layout.fillWidth: true; spacing: 6
                                        Repeater {
                                            model: ["Default", "Unlimited", "Set to"]
                                            delegate: Rectangle {
                                                required property int    index
                                                required property string modelData
                                                height: 24
                                                implicitWidth: seedPillLbl.implicitWidth + 16
                                                radius: 3
                                                color: root.seedMode === index ? "#1a3a6a" : "#252525"
                                                border.color: root.seedMode === index ? "#4488dd" : "#3a3a3a"
                                                Text {
                                                    id: seedPillLbl
                                                    anchors.centerIn: parent
                                                    text: modelData
                                                    color: root.seedMode === index ? "#88aaee" : "#888888"
                                                    font.pixelSize: 11
                                                }
                                                MouseArea {
                                                    anchors.fill: parent
                                                    onClicked: root.seedMode = index
                                                }
                                            }
                                        }
                                        TextField {
                                            id: seedInput
                                            visible: root.seedMode === 2
                                            implicitWidth: 80
                                            color: "#d0d0d0"; font.pixelSize: 12
                                            leftPadding: 6; rightPadding: 6; selectByMouse: true
                                            validator: IntValidator { bottom: 0; top: 999999 }
                                            background: Rectangle {
                                                color: "#1b1b1b"
                                                border.color: parent.activeFocus ? "#4488dd" : "#3a3a3a"; radius: 2
                                            }
                                        }
                                        Text { visible: root.seedMode === 2; text: "min"; color: "#666"; font.pixelSize: 12 }
                                        Item { Layout.fillWidth: true }
                                    }
                                }

                                Rectangle { Layout.fillWidth: true; height: 1; color: "#2a2a2a" }

                                // ── Inactive seeding time ─────────────────────
                                ColumnLayout {
                                    Layout.fillWidth: true; spacing: 6
                                    Text { text: "Inactive seeding time"; color: "#c0c0c0"; font.pixelSize: 12 }
                                    RowLayout {
                                        Layout.fillWidth: true; spacing: 6
                                        Repeater {
                                            model: ["Default", "Unlimited", "Set to"]
                                            delegate: Rectangle {
                                                required property int    index
                                                required property string modelData
                                                height: 24
                                                implicitWidth: inactPillLbl.implicitWidth + 16
                                                radius: 3
                                                color: root.inactMode === index ? "#1a3a6a" : "#252525"
                                                border.color: root.inactMode === index ? "#4488dd" : "#3a3a3a"
                                                Text {
                                                    id: inactPillLbl
                                                    anchors.centerIn: parent
                                                    text: modelData
                                                    color: root.inactMode === index ? "#88aaee" : "#888888"
                                                    font.pixelSize: 11
                                                }
                                                MouseArea {
                                                    anchors.fill: parent
                                                    onClicked: root.inactMode = index
                                                }
                                            }
                                        }
                                        TextField {
                                            id: inactInput
                                            visible: root.inactMode === 2
                                            implicitWidth: 80
                                            color: "#d0d0d0"; font.pixelSize: 12
                                            leftPadding: 6; rightPadding: 6; selectByMouse: true
                                            validator: IntValidator { bottom: 0; top: 999999 }
                                            background: Rectangle {
                                                color: "#1b1b1b"
                                                border.color: parent.activeFocus ? "#4488dd" : "#3a3a3a"; radius: 2
                                            }
                                        }
                                        Text { visible: root.inactMode === 2; text: "min"; color: "#666"; font.pixelSize: 12 }
                                        Item { Layout.fillWidth: true }
                                    }
                                }

                                Text {
                                    text: "\"Default\" uses the global share limits set in Settings → Torrents."
                                    color: "#7f8a94"; font.pixelSize: 10
                                    wrapMode: Text.WordWrap; Layout.fillWidth: true
                                }
                            }
                        }

                        Item { height: 4 }
                    }
                }
            }
        }

        // ── Footer ───────────────────────────────────────────────────────────
        Rectangle {
            Layout.fillWidth: true
            height: 48
            color: "#252525"

            Row {
                anchors { right: parent.right; verticalCenter: parent.verticalCenter; rightMargin: 12 }
                spacing: 8
                DlgButton {
                    text: "Cancel"
                    onClicked: root.close()
                }
                DlgButton {
                    text: "OK"
                    primary: true
                    onClicked: { root.save(); root.close() }
                }
            }
        }
    }

    FolderDialog {
        id: folderDialog
        onAccepted: savePathField.text = selectedFolder.toString().replace(/^file:\/\/\//, "").replace(/^file:\/\//, "")
    }
}
