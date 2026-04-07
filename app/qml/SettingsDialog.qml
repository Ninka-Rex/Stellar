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
import QtQuick.Dialogs

Window {
    id: root

    width: 620
    height: 500
    minimumWidth: 400
    minimumHeight: 400
    flags: Qt.Window | Qt.WindowTitleHint | Qt.WindowCloseButtonHint | Qt.WindowSystemMenuHint
    title: "Stellar Preferences"
    color: "#1e1e1e"

    Material.theme: Material.Dark
    Material.background: "#1e1e1e"
    Material.accent: "#4488dd"

    property int    initialPage: 0   // set to 5 to jump to About

    // Plain var properties — no live binding to App.settings so that
    // settingsChanged can detect when the user has made changes.
    property int    editMaxConcurrent:         0
    property int    editSegmentsPerDownload:   0
    property string editDefaultSavePath:       ""
    property int    editGlobalSpeedLimitKBps:  0
    property bool   editMinimizeToTray:        false
    property bool   editCloseToTray:           false
    property bool   editShowTips:              true
    property int    editMaxRetries:            0
    property int    editConnectionTimeoutSecs: 0
    property int    editDuplicateAction:       0
    property bool   editStartImmediately:      false
    property bool   editSpeedLimiterOnStartup: false
    property bool   editShowDownloadComplete:  true
    property int    editSavedSpeedLimitKBps:   500

    Component.onCompleted: resetEdits()
    onVisibleChanged: { if (visible) resetEdits() }

    // Track whether anything has been changed
    readonly property bool settingsChanged:
        editMaxConcurrent         !== App.settings.maxConcurrent        ||
        editSegmentsPerDownload   !== App.settings.segmentsPerDownload  ||
        editDefaultSavePath       !== App.settings.defaultSavePath      ||
        editGlobalSpeedLimitKBps  !== App.settings.globalSpeedLimitKBps ||
        editMinimizeToTray        !== App.settings.minimizeToTray       ||
        editCloseToTray           !== App.settings.closeToTray          ||
        editShowTips              !== App.settings.showTips             ||
        editMaxRetries            !== App.settings.maxRetries           ||
        editConnectionTimeoutSecs !== App.settings.connectionTimeoutSecs ||
        editDuplicateAction       !== App.settings.duplicateAction  ||
        editStartImmediately      !== App.settings.startImmediately ||
        editSpeedLimiterOnStartup !== App.settings.speedLimiterOnStartup ||
        editSavedSpeedLimitKBps   !== App.settings.savedSpeedLimitKBps ||
        editShowDownloadComplete  !== App.settings.showDownloadComplete

    property bool catDirty:       false
    property bool loadingCategory: false   // suppresses onTextChanged during programmatic load
    property bool browserDirty:   false

    readonly property bool hasChanges: settingsChanged || catDirty || browserDirty

    FolderDialog {
        id: saveFolderDlg
        currentFolder: root.editDefaultSavePath.length > 0
                       ? ("file:///" + root.editDefaultSavePath.replace(/\\/g, "/")) : ""
        onAccepted: {
            var path = selectedFolder.toString()
                           .replace(/^file:\/\/\//, "").replace(/^file:\/\//, "")
            root.editDefaultSavePath = path
        }
    }

    function applySettings() {
        // Always flush the current category form
        if (catPage.catEditId !== "") {
            var exts = catEditExts.text.split(",").map(function(s) {
                return s.trim().replace(/^\./, "").toLowerCase()
            }).filter(function(s) { return s.length > 0 })
            var sites = catEditSites.text.split(/\s+/).filter(function(s) { return s.length > 0 })
            App.categoryModel.updateCategory(catPage.catEditId, catEditName.text.trim(), exts, sites, catEditPath.text.trim())
            catDirty = false
        }

        // Flush browser integration settings
        if (browserDirty) {
            var monExts = monitoredExtsArea.text.split(/[\s,]+/).map(function(s) {
                return s.trim().toLowerCase().replace(/^\./, "")
            }).filter(function(s) { return s.length > 0 })
            App.settings.monitoredExtensions = monExts

            var excSites = excludedSitesArea.text.split(/\s+/).filter(function(s) { return s.length > 0 })
            App.settings.excludedSites = excSites

            var excAddrs = excludedAddrsArea.text.split("\n").map(function(s) {
                return s.trim()
            }).filter(function(s) { return s.length > 0 })
            App.settings.excludedAddresses = excAddrs

            App.settings.showExceptionsDialog = showExceptDlgChk.checked

            browserDirty = false
        }

        App.settings.maxConcurrent         = editMaxConcurrent
        App.settings.segmentsPerDownload   = editSegmentsPerDownload
        App.settings.defaultSavePath       = editDefaultSavePath
        App.settings.globalSpeedLimitKBps  = editGlobalSpeedLimitKBps
        App.settings.minimizeToTray        = editMinimizeToTray
        App.settings.closeToTray           = editCloseToTray
        App.settings.showTips              = editShowTips
        App.settings.maxRetries            = editMaxRetries
        App.settings.connectionTimeoutSecs = editConnectionTimeoutSecs
        App.settings.duplicateAction       = editDuplicateAction
        App.settings.startImmediately       = editStartImmediately
        App.settings.speedLimiterOnStartup  = editSpeedLimiterOnStartup
        App.settings.savedSpeedLimitKBps    = editSavedSpeedLimitKBps
        App.settings.showDownloadComplete   = editShowDownloadComplete
        App.settings.save()
        // Sync edit properties so settingsChanged resets to false
        resetEdits()
    }

    function resetEdits() {
        editMaxConcurrent         = App.settings.maxConcurrent
        editSegmentsPerDownload   = App.settings.segmentsPerDownload
        editDefaultSavePath       = App.settings.defaultSavePath
        editGlobalSpeedLimitKBps  = App.settings.globalSpeedLimitKBps
        editMinimizeToTray        = App.settings.minimizeToTray
        editCloseToTray           = App.settings.closeToTray
        editShowTips              = App.settings.showTips
        editMaxRetries            = App.settings.maxRetries
        editConnectionTimeoutSecs = App.settings.connectionTimeoutSecs
        editDuplicateAction       = App.settings.duplicateAction
        editStartImmediately      = App.settings.startImmediately
        editSpeedLimiterOnStartup = App.settings.speedLimiterOnStartup
        editSavedSpeedLimitKBps   = App.settings.savedSpeedLimitKBps
        editShowDownloadComplete  = App.settings.showDownloadComplete
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 0

            // Sidebar
            Rectangle {
                Layout.fillHeight: true
                width: 160
                color: "#252525"

                ListView {
                    id: catList
                    anchors.fill: parent
                    anchors.topMargin: 8
                    model: ["Connection", "Categories", "Downloads", "Browser", "Speed Limiter", "Notifications", "General", "About"]
                    currentIndex: root.initialPage

                    delegate: Rectangle {
                        width: ListView.view.width
                        height: 36
                        color: catList.currentIndex === index ? "#1e3a6e" : (ma.containsMouse ? "#2a2a2a" : "transparent")

                        Text {
                            anchors { verticalCenter: parent.verticalCenter; left: parent.left; leftMargin: 16 }
                            text: modelData
                            color: catList.currentIndex === index ? "#ffffff" : "#c0c0c0"
                            font.pixelSize: 13
                        }

                        MouseArea {
                            id: ma
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: catList.currentIndex = index
                        }
                    }
                }
            }

            // Content pages
            StackLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                currentIndex: catList.currentIndex

                // Connection
                Item {
                    ColumnLayout {
                        anchors { fill: parent; margins: 12 }
                        spacing: 10

                        Text { text: "Connection"; color: "#ffffff"; font.pixelSize: 16; font.bold: true }
                        Rectangle { Layout.fillWidth: true; height: 1; color: "#3a3a3a" }

                        GridLayout {
                            columns: 3; columnSpacing: 10; rowSpacing: 10

                            Text { text: "Maximum simultaneous downloads:"; color: "#c0c0c0"; font.pixelSize: 13 }
                            SpinBox { from: 1; to: 16; value: root.editMaxConcurrent; onValueModified: root.editMaxConcurrent = value; padding: 0 }
                            Item {}

                            Text { text: "Segments per download:"; color: "#c0c0c0"; font.pixelSize: 13 }
                            SpinBox { from: 1; to: 16; value: root.editSegmentsPerDownload; onValueModified: root.editSegmentsPerDownload = value; padding: 0 }
                            Item {}

                            Text { text: "Connection timeout (seconds):"; color: "#c0c0c0"; font.pixelSize: 13 }
                            SpinBox { from: 5; to: 120; value: root.editConnectionTimeoutSecs; onValueModified: root.editConnectionTimeoutSecs = value; padding: 0 }
                            Item {}

                            Text { text: "Retry failed downloads:"; color: "#c0c0c0"; font.pixelSize: 13 }
                            SpinBox { from: 0; to: 10; value: root.editMaxRetries; onValueModified: root.editMaxRetries = value; padding: 0 }
                            Text { text: "times"; color: "#a0a0a0"; font.pixelSize: 13 }
                        }

                        Item { Layout.fillHeight: true }
                    }
                }

                // Categories
                Item {
                    id: catPage
                    property bool catEditBuiltIn: false
                    property string catEditId: ""

                    FolderDialog {
                        id: catSaveFolderDlg
                        onAccepted: {
                            var path = selectedFolder.toString()
                                .replace(/^file:\/\/\//, "").replace(/^file:\/\//, "")
                                .replace(/\//g, "\\")
                            catEditPath.text = path
                        }
                    }

                    ColumnLayout {
                        anchors { fill: parent; margins: 12 }
                        spacing: 10

                        Text { text: "Categories"; color: "#ffffff"; font.pixelSize: 16; font.bold: true }
                        Rectangle { Layout.fillWidth: true; height: 1; color: "#3a3a3a" }

                        RowLayout {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            spacing: 12

                            // ── Left: category list ──────────────────────────
                            ColumnLayout {
                                Layout.fillHeight: true
                                Layout.preferredWidth: 170
                                spacing: 4

                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    color: "#252525"
                                    border.color: "#3a3a3a"
                                    radius: 2
                                    clip: true

                                    ListView {
                                        id: catEditList
                                        anchors.fill: parent
                                        clip: true
                                        model: App.categoryModel
                                        currentIndex: 1
                                        ScrollBar.vertical: ScrollBar {}

                                        Component.onCompleted: {
                                            var d = App.categoryModel.categoryData(currentIndex)
                                            if (!d || !d.id) return
                                            root.loadingCategory = true
                                            catEditName.text  = d.label || ""
                                            catEditExts.text  = (d.extensions || []).join(", ")
                                            catEditSites.text = (d.sitePatterns || []).join(" ")
                                            catEditPath.text  = d.savePath || ""
                                            catPage.catEditBuiltIn = !!d.builtIn
                                            catPage.catEditId = d.id || ""
                                            root.loadingCategory = false
                                        }

                                        onCurrentIndexChanged: {
                                            // Always save the previous category before switching
                                            if (catPage.catEditId !== "") {
                                                var exts = catEditExts.text.split(",").map(function(s) {
                                                    return s.trim().replace(/^\./, "").toLowerCase()
                                                }).filter(function(s) { return s.length > 0 })
                                                var sites = catEditSites.text.split(/\s+/).filter(function(s) { return s.length > 0 })
                                                App.categoryModel.updateCategory(catPage.catEditId, catEditName.text.trim(), exts, sites, catEditPath.text.trim())
                                            }

                                            var d = App.categoryModel.categoryData(currentIndex)
                                            if (!d || !d.id) return
                                            root.loadingCategory = true
                                            catEditName.text  = d.label || ""
                                            catEditExts.text  = (d.extensions || []).join(", ")
                                            catEditSites.text = (d.sitePatterns || []).join(" ")
                                            catEditPath.text  = d.savePath || ""
                                            catPage.catEditBuiltIn = !!d.builtIn
                                            catPage.catEditId = d.id || ""
                                            root.loadingCategory = false
                                        }

                                        delegate: Rectangle {
                                            width: ListView.view.width
                                            // Hide the built-in "All Downloads" category (id = "all")
                                            visible: categoryId !== "all"
                                            height: visible ? 32 : 0
                                            color: catEditList.currentIndex === index
                                                   ? "#1e3a6e"
                                                   : (catItemMa.containsMouse ? "#2a2a2a" : "transparent")

                                            Text {
                                                anchors { verticalCenter: parent.verticalCenter; left: parent.left; leftMargin: 10; right: parent.right; rightMargin: 6 }
                                                text: categoryLabel
                                                color: catEditList.currentIndex === index ? "#ffffff" : "#c0c0c0"
                                                font.pixelSize: 12
                                                elide: Text.ElideRight
                                            }
                                            MouseArea {
                                                id: catItemMa
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                enabled: visible
                                                onClicked: catEditList.currentIndex = index
                                            }
                                        }
                                    }
                                }

                                // Add / Remove buttons below the list
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 6

                                    Rectangle {
                                        width: 32; height: 26; radius: 3
                                        color: addCatMa.containsMouse ? "#445544" : "#333"
                                        border.color: "#555"
                                        Text {
                                            anchors.centerIn: parent
                                            text: "+"
                                            color: "#c0c0c0"
                                            font.pixelSize: 16
                                            font.bold: true
                                        }
                                        MouseArea {
                                            id: addCatMa
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                App.categoryModel.addCategory("New Category")
                                                catEditList.currentIndex = App.categoryModel.categoryCount() - 1
                                            }
                                        }
                                    }

                                    Rectangle {
                                        width: 32; height: 26; radius: 3
                                        enabled: !catPage.catEditBuiltIn && catPage.catEditId !== ""
                                        color: delCatMa.containsMouse && enabled ? "#554444" : "#333"
                                        border.color: "#555"
                                        opacity: enabled ? 1.0 : 0.4
                                        Text {
                                            anchors.centerIn: parent
                                            text: "−"
                                            color: "#e0a0a0"
                                            font.pixelSize: 18
                                            font.bold: true
                                        }
                                        MouseArea {
                                            id: delCatMa
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: parent.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                                            onClicked: {
                                                if (!catPage.catEditBuiltIn) {
                                                    App.categoryModel.removeCategory(catPage.catEditId)
                                                    catEditList.currentIndex = 0
                                                }
                                            }
                                        }
                                    }

                                    Item { Layout.fillWidth: true }
                                }
                            }

                            // ── Right: edit form ─────────────────────────────
                            ColumnLayout {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                spacing: 12

                                // Name
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 4
                                    Text { text: "Name"; color: "#909090"; font.pixelSize: 11 }
                                    TextField {
                                        id: catEditName
                                        Layout.fillWidth: true
                                        implicitHeight: 30
                                        font.pixelSize: 12; color: "#d0d0d0"
                                        background: Rectangle { color: "#2d2d2d"; border.color: "#4a4a4a"; radius: 3 }
                                        leftPadding: 8
                                        onTextChanged: if (!root.loadingCategory) root.catDirty = true
                                    }
                                }

                                // File types
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 4
                                    Text { text: "File types  (comma-separated, e.g.  mp4, mkv, avi)"; color: "#909090"; font.pixelSize: 11 }
                                    ScrollView {
                                        Layout.fillWidth: true
                                        implicitHeight: 52
                                        clip: true
                                        background: Rectangle { color: "#2d2d2d"; border.color: "#4a4a4a"; radius: 3 }
                                        TextArea {
                                            id: catEditExts
                                            wrapMode: TextArea.Wrap
                                            font.pixelSize: 12; color: "#d0d0d0"
                                            background: null
                                            padding: 6
                                            placeholderText: "mp4, mkv, avi, mov"
                                            onTextChanged: if (!root.loadingCategory) root.catDirty = true
                                        }
                                    }
                                }

                                // Sites
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 4
                                    Text { text: "Auto-assign from sites  (space-separated, * wildcard)"; color: "#909090"; font.pixelSize: 11 }
                                    TextField {
                                        id: catEditSites
                                        Layout.fillWidth: true
                                        implicitHeight: 30
                                        placeholderText: "*.youtube.com *.vimeo.com"
                                        font.pixelSize: 12; color: "#d0d0d0"
                                        background: Rectangle { color: "#2d2d2d"; border.color: "#4a4a4a"; radius: 3 }
                                        leftPadding: 8
                                        onTextChanged: if (!root.loadingCategory) root.catDirty = true
                                    }
                                    Text {
                                        text: "Downloads from matching sites will automatically go into this category."
                                        color: "#555"; font.pixelSize: 10
                                        wrapMode: Text.WordWrap
                                        Layout.fillWidth: true
                                    }
                                }

                                // Save to
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 4
                                    Text { text: "Save to folder"; color: "#909090"; font.pixelSize: 11 }
                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 6
                                        TextField {
                                            id: catEditPath
                                            Layout.fillWidth: true
                                            implicitHeight: 30
                                            font.pixelSize: 12; color: "#d0d0d0"
                                            background: Rectangle { color: "#2d2d2d"; border.color: "#4a4a4a"; radius: 3 }
                                            leftPadding: 8
                                            onTextChanged: if (!root.loadingCategory) root.catDirty = true
                                        }
                                        Rectangle {
                                            width: 32; height: 30; radius: 3
                                            color: browseMa.containsMouse ? "#445" : "#333"
                                            border.color: "#555"
                                            Text { anchors.centerIn: parent; text: "…"; color: "#c0c0c0"; font.pixelSize: 13 }
                                            MouseArea {
                                                id: browseMa
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: catSaveFolderDlg.open()
                                            }
                                        }
                                    }
                                }

                                Item { Layout.fillHeight: true }
                            }
                        }
                    }
                }

                // Downloads
                Item {
                    ColumnLayout {
                        anchors { fill: parent; margins: 12 }
                        spacing: 10

                        Text { text: "Downloads"; color: "#ffffff"; font.pixelSize: 16; font.bold: true }
                        Rectangle { Layout.fillWidth: true; height: 1; color: "#3a3a3a" }

                        Text { text: "Default save folder:"; color: "#c0c0c0"; font.pixelSize: 13 }
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8
                            TextField {
                                Layout.fillWidth: true
                                text: root.editDefaultSavePath
                                onTextChanged: root.editDefaultSavePath = text
                                color: "#d0d0d0"; font.pixelSize: 13
                                background: Rectangle { color: "#2d2d2d"; border.color: "#4a4a4a"; radius: 3 }
                            }
                            Button {
                                text: "Browse…"; font.pixelSize: 12
                                background: Rectangle { color: "#3a3a3a"; radius: 3 }
                                contentItem: Text { text: parent.text; color: "#d0d0d0"; font: parent.font; horizontalAlignment: Text.AlignHCenter }
                                onClicked: saveFolderDlg.open()
                            }
                        }

                        CheckBox {
                            text: "Start downloading immediately (skip file info dialog)"
                            topPadding: 0; bottomPadding: 0
                            checked: root.editStartImmediately
                            onCheckedChanged: root.editStartImmediately = checked
                            contentItem: Text { text: parent.text; color: "#d0d0d0"; font.pixelSize: 13; leftPadding: parent.indicator.width + 4 }
                        }

                        CheckBox {
                            text: "Show download complete dialog"
                            topPadding: 0; bottomPadding: 0
                            checked: root.editShowDownloadComplete
                            onCheckedChanged: root.editShowDownloadComplete = checked
                            contentItem: Text { text: parent.text; color: "#d0d0d0"; font.pixelSize: 13; leftPadding: parent.indicator.width + 4 }
                        }

                        Rectangle { Layout.fillWidth: true; height: 1; color: "#2e2e2e" }

                        Text { text: "If a duplicate URL is added:"; color: "#c0c0c0"; font.pixelSize: 13 }
                        ComboBox {
                            id: duplicateActionCombo
                            model: [
                                "Ask me what to do",
                                "Add with a numbered file name",
                                "Overwrite the existing download",
                                "Resume / show complete dialog"
                            ]
                            currentIndex: App.settings.duplicateAction
                            implicitWidth: 260
                            font.pixelSize: 12
                            background: Rectangle { color: "#2d2d2d"; border.color: "#4a4a4a"; radius: 3 }
                            contentItem: Text {
                                leftPadding: 8
                                text: duplicateActionCombo.displayText
                                color: "#d0d0d0"; font: duplicateActionCombo.font
                                verticalAlignment: Text.AlignVCenter
                            }
                            onCurrentIndexChanged: root.editDuplicateAction = currentIndex
                        }

                        Item { Layout.fillHeight: true }
                    }
                }

                // Browser Integration
                Item {
                    id: browserPage

                    ScrollView {
                        anchors.fill: parent
                        contentWidth: availableWidth
                        clip: true

                        ColumnLayout {
                            width: browserPage.width - 24
                            x: 12; y: 12
                            spacing: 10

                            Text { text: "Browser Integration"; color: "#ffffff"; font.pixelSize: 16; font.bold: true }
                            Rectangle { Layout.fillWidth: true; height: 1; color: "#3a3a3a" }

                            // ── Monitored file types ──────────────────────────────
                            Text {
                                text: "Automatically start downloading the following file types:"
                                color: "#c0c0c0"; font.pixelSize: 13
                                wrapMode: Text.WordWrap
                                Layout.fillWidth: true
                            }

                            ScrollView {
                                Layout.fillWidth: true
                                implicitHeight: 72
                                clip: true
                                background: Rectangle { color: "#2d2d2d"; border.color: "#4a4a4a"; radius: 3 }
                                TextArea {
                                    id: monitoredExtsArea
                                    wrapMode: TextArea.Wrap
                                    font.pixelSize: 11
                                    font.family: "monospace"
                                    color: "#d0d0d0"
                                    background: null
                                    padding: 6
                                    text: App.settings.monitoredExtensions.join(" ").toUpperCase()
                                    onTextChanged: if (!root.loadingCategory) root.browserDirty = true
                                }
                            }

                            Text {
                                text: "Space or comma-separated. Case-insensitive."
                                color: "#555"; font.pixelSize: 10
                            }

                            Rectangle { Layout.fillWidth: true; height: 1; color: "#2e2e2e" }

                            // ── Excluded sites ────────────────────────────────────
                            Text {
                                text: "Don't start downloading automatically from the following sites:"
                                color: "#c0c0c0"; font.pixelSize: 13
                                wrapMode: Text.WordWrap
                                Layout.fillWidth: true
                            }

                            ScrollView {
                                Layout.fillWidth: true
                                implicitHeight: 60
                                clip: true
                                background: Rectangle { color: "#2d2d2d"; border.color: "#4a4a4a"; radius: 3 }
                                TextArea {
                                    id: excludedSitesArea
                                    wrapMode: TextArea.Wrap
                                    font.pixelSize: 11
                                    font.family: "monospace"
                                    color: "#d0d0d0"
                                    background: null
                                    padding: 6
                                    text: App.settings.excludedSites.join(" ")
                                    onTextChanged: if (!root.loadingCategory) root.browserDirty = true
                                }
                            }

                            Text {
                                text: "Space-separated host patterns. Wildcards (*) supported, e.g. *.update.microsoft.com"
                                color: "#555"; font.pixelSize: 10
                                wrapMode: Text.WordWrap
                                Layout.fillWidth: true
                            }

                            Rectangle { Layout.fillWidth: true; height: 1; color: "#2e2e2e" }

                            // ── Address Exceptions ────────────────────────────────
                            Text {
                                text: "Address Exceptions"
                                color: "#ffffff"; font.pixelSize: 14; font.bold: true
                            }

                            CheckBox {
                                id: showExceptDlgChk
                                text: "Show the dialog to add an address to the list of exceptions for a twice cancelled download"
                                topPadding: 0; bottomPadding: 0
                                Layout.fillWidth: true
                                checked: App.settings.showExceptionsDialog
                                onCheckedChanged: root.browserDirty = true
                                contentItem: Text {
                                    text: parent.text
                                    color: "#d0d0d0"; font.pixelSize: 12
                                    leftPadding: parent.indicator.width + 4
                                    wrapMode: Text.WordWrap
                                    width: parent.width
                                }
                            }

                            Text {
                                text: "Don't start downloading from the following addresses:"
                                color: "#c0c0c0"; font.pixelSize: 13
                                wrapMode: Text.WordWrap
                                Layout.fillWidth: true
                            }

                            ScrollView {
                                Layout.fillWidth: true
                                implicitHeight: 160
                                clip: true
                                background: Rectangle { color: "#2d2d2d"; border.color: "#4a4a4a"; radius: 3 }
                                TextArea {
                                    id: excludedAddrsArea
                                    wrapMode: TextArea.NoWrap
                                    font.pixelSize: 11
                                    font.family: "monospace"
                                    color: "#d0d0d0"
                                    background: null
                                    padding: 6
                                    text: App.settings.excludedAddresses.join("\n")
                                    onTextChanged: if (!root.loadingCategory) root.browserDirty = true
                                }
                            }

                            Text {
                                text: "One URL pattern per line. Wildcards (*) supported."
                                color: "#555"; font.pixelSize: 10
                            }

                            Item { height: 10 }
                        }
                    }
                }

                // Speed Limiter
                Item {
                    ColumnLayout {
                        anchors { fill: parent; margins: 12 }
                        spacing: 10

                        Text { text: "Speed Limiter"; color: "#ffffff"; font.pixelSize: 16; font.bold: true }
                        Rectangle { Layout.fillWidth: true; height: 1; color: "#3a3a3a" }

                            CheckBox {
                                id: globalLimitChk
                                text: "Enable global speed limit"
                                topPadding: 0; bottomPadding: 0
                                checked: root.editGlobalSpeedLimitKBps > 0
                                onToggled: { 
                                    if (!checked) {
                                        root.editGlobalSpeedLimitKBps = 0
                                    } else {
                                        root.editGlobalSpeedLimitKBps = root.editSavedSpeedLimitKBps
                                    }
                                }
                                contentItem: Text { text: parent.text; color: "#d0d0d0"; font.pixelSize: 13; leftPadding: parent.indicator.width + 4 }
                            }

                            RowLayout {
                                spacing: 8
                                enabled: globalLimitChk.checked
                                Text { text: "Maximum speed:"; color: "#a0a0a0"; font.pixelSize: 13 }
                                TextField {
                                    implicitWidth: 90
                                    text: root.editGlobalSpeedLimitKBps > 0 ? root.editGlobalSpeedLimitKBps.toString() : root.editSavedSpeedLimitKBps.toString()
                                    placeholderText: "0"
                                    onTextChanged: { 
                                        var v = parseInt(text); 
                                        if (!isNaN(v)) {
                                            root.editGlobalSpeedLimitKBps = v
                                            root.editSavedSpeedLimitKBps = v
                                        } 
                                    }
                                    color: "#d0d0d0"; font.pixelSize: 13
                                    background: Rectangle { color: "#2d2d2d"; border.color: "#4a4a4a"; radius: 3 }
                                }
                                Text { text: "KB/s"; color: "#a0a0a0"; font.pixelSize: 13 }
                            }

                        CheckBox {
                            text: "Always turn on speed limiter on Stellar startup"
                            topPadding: 0; bottomPadding: 0
                            checked: root.editSpeedLimiterOnStartup
                            onCheckedChanged: root.editSpeedLimiterOnStartup = checked
                            contentItem: Text { text: parent.text; color: "#d0d0d0"; font.pixelSize: 13; leftPadding: parent.indicator.width + 4; wrapMode: Text.WordWrap; Layout.fillWidth: true }
                        }

                        Item { Layout.fillHeight: true }
                    }
                }

                // Notifications
                Item {
                    ColumnLayout {
                        anchors { fill: parent; margins: 12 }
                        spacing: 10

                        Text { text: "Notifications"; color: "#ffffff"; font.pixelSize: 16; font.bold: true }
                        Rectangle { Layout.fillWidth: true; height: 1; color: "#3a3a3a" }

                        CheckBox {
                            text: "Show notification when download completes"
                            topPadding: 0; bottomPadding: 0
                            checked: true
                            contentItem: Text { text: parent.text; color: "#d0d0d0"; font.pixelSize: 13; leftPadding: parent.indicator.width + 4 }
                        }
                        CheckBox {
                            text: "Show notification on download error"
                            topPadding: 0; bottomPadding: 0
                            checked: true
                            contentItem: Text { text: parent.text; color: "#d0d0d0"; font.pixelSize: 13; leftPadding: parent.indicator.width + 4 }
                        }

                        Item { Layout.fillHeight: true }
                    }
                }

                // General
                Item {
                    ColumnLayout {
                        anchors { fill: parent; margins: 12 }
                        spacing: 10

                        Text { text: "General"; color: "#ffffff"; font.pixelSize: 16; font.bold: true }
                        Rectangle { Layout.fillWidth: true; height: 1; color: "#3a3a3a" }

                        CheckBox {
                            text: "Minimize to system tray"
                            topPadding: 0; bottomPadding: 0
                            checked: root.editMinimizeToTray
                            onCheckedChanged: root.editMinimizeToTray = checked
                            contentItem: Text { text: parent.text; color: "#d0d0d0"; font.pixelSize: 13; leftPadding: parent.indicator.width + 4 }
                        }
                        CheckBox {
                            text: "Close to system tray"
                            topPadding: 0; bottomPadding: 0
                            checked: root.editCloseToTray
                            onCheckedChanged: root.editCloseToTray = checked
                            contentItem: Text { text: parent.text; color: "#d0d0d0"; font.pixelSize: 13; leftPadding: parent.indicator.width + 4 }
                        }
                        CheckBox {
                            text: "Show tips in bottom bar"
                            topPadding: 0; bottomPadding: 0
                            checked: root.editShowTips
                            onCheckedChanged: root.editShowTips = checked
                            contentItem: Text { text: parent.text; color: "#d0d0d0"; font.pixelSize: 13; leftPadding: parent.indicator.width + 4 }
                        }

                        Item { Layout.fillHeight: true }
                    }
                }

                // About
                Item {
                    ScrollView {
                        anchors.fill: parent
                        contentWidth: availableWidth
                        clip: true

                    ColumnLayout {
                        width: parent.width
                        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
                        spacing: 10

                        Text { text: "About"; color: "#ffffff"; font.pixelSize: 16; font.bold: true }
                        Rectangle { Layout.fillWidth: true; height: 1; color: "#3a3a3a" }

                        RowLayout {
                            spacing: 16
                            Image {
                                Layout.preferredWidth: 75
                                Layout.preferredHeight: 75
                                source: "icons/milky-way.png"
                                fillMode: Image.PreserveAspectFit
                                smooth: true
                            }
                            ColumnLayout {
                                spacing: 2
                                Text { text: "Stellar Download Manager"; color: "#ffffff"; font.pixelSize: 15; font.bold: true }
                                Text { text: "Version " + App.appVersion; color: "#4488dd"; font.pixelSize: 13 }
                            }
                        }

                        Rectangle { Layout.fillWidth: true; height: 1; color: "#2a2a2a" }

                        GridLayout {
                            columns: 2; columnSpacing: 16; rowSpacing: 6
                            Text { text: "Build time:"; color: "#808080"; font.pixelSize: 12 }
                            Text { text: App.buildTime;  color: "#c0c0c0"; font.pixelSize: 12 }
                            Text { text: "Qt version:";  color: "#808080"; font.pixelSize: 12 }
                            Text { text: App.qtVersion;   color: "#c0c0c0"; font.pixelSize: 12 }
                            Text { text: "Platform:";    color: "#808080"; font.pixelSize: 12 }
                            Text { text: Qt.platform.os; color: "#c0c0c0"; font.pixelSize: 12 }
                        }

                        Rectangle { Layout.fillWidth: true; height: 1; color: "#2a2a2a" }

                        Text {
                            text: "A fast, multi-segment download manager with browser integration support."
                            color: "#909090"; font.pixelSize: 12
                            wrapMode: Text.WordWrap
                            Layout.fillWidth: true
                        }

                        Rectangle { Layout.fillWidth: true; height: 1; color: "#2a2a2a" }

                        // License
                        Text {
                            text: "Copyright \u00A9 2026 Ninka_"
                            color: "#808080"; font.pixelSize: 12
                        }
                        Text {
                            Layout.fillWidth: true
                            text: "This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 3."
                            color: "#606060"; font.pixelSize: 11
                            wrapMode: Text.WordWrap
                        }
                        Text {
                            text: "GNU General Public License v3.0"
                            color: "#4488dd"; font.pixelSize: 12
                            font.underline: true
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: Qt.openUrlExternally("https://www.gnu.org/licenses/gpl-3.0.html")
                            }
                        }

                        Rectangle { Layout.fillWidth: true; height: 1; color: "#2a2a2a" }

                        // Links
                        RowLayout {
                            spacing: 20

                            Column {
                                spacing: 2
                                Text { text: "Website"; color: "#606060"; font.pixelSize: 11 }
                                Text {
                                    text: "stellar.moe"
                                    color: "#4488dd"; font.pixelSize: 12
                                    font.underline: true
                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: Qt.openUrlExternally("https://stellar.moe/")
                                    }
                                }
                            }

                            Column {
                                spacing: 2
                                Text { text: "Source code"; color: "#606060"; font.pixelSize: 11 }
                                Text {
                                    text: "github.com/Ninka-Rex/Stellar"
                                    color: "#4488dd"; font.pixelSize: 12
                                    font.underline: true
                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: Qt.openUrlExternally("https://github.com/Ninka-Rex/Stellar")
                                    }
                                }
                            }
                        }

                        Item { height: 12 }
                    }
                    } // ScrollView
                }
            }
        }

        // Bottom buttons
        Rectangle {
            Layout.fillWidth: true
            height: 48
            color: "#252525"

            Row {
                anchors { right: parent.right; verticalCenter: parent.verticalCenter; rightMargin: 12 }
                spacing: 8

                Rectangle {
                    width: 80; height: 30; radius: 3
                    enabled: root.hasChanges
                    color: enabled ? (applyMa.containsMouse ? "#4a4a7a" : "#3a3a5a") : "#2a2a2a"
                    border.color: enabled ? "#5555aa" : "transparent"

                    Text {
                        anchors.centerIn: parent
                        text: "Apply"
                        color: parent.enabled ? "#ffffff" : "#555555"
                        font.pixelSize: 13
                    }
                    MouseArea {
                        id: applyMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: parent.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onClicked: if (root.hasChanges) root.applySettings()
                    }
                }

                Rectangle {
                    width: 80; height: 30; radius: 3
                    color: okMa.containsMouse ? "#4a6aaa" : "#3a5a8a"

                    Text {
                        anchors.centerIn: parent
                        text: "OK"
                        color: "#ffffff"
                        font.pixelSize: 13
                    }
                    MouseArea {
                        id: okMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: { root.applySettings(); root.close() }
                    }
                }
            }
        }
    }
}
