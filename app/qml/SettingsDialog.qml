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

    width: 665
    height: 500
    minimumWidth: 665
    minimumHeight: 500
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
    property string editTemporaryDirectory:    ""
    property int    editGlobalSpeedLimitKBps:  0
    property bool   editMinimizeToTray:        false
    property bool   editCloseToTray:           false
    property bool   editShowTips:              true
    property bool   editShowExceptionsDialog:  true
    property int    editMaxRetries:            0
    property int    editConnectionTimeoutSecs: 0
    property int    editDuplicateAction:       0
    property bool   editStartImmediately:      false
    property bool   editSpeedLimiterOnStartup: false
    property bool   editShowDownloadComplete:  true
    property bool   editShowCompletionNotification: true
    property bool   editShowErrorNotification: true
    property bool   editShowFinishedCount:     true
    property bool   editStartDownloadWhileFileInfo: true
    property bool   editShowQueueSelectionOnDownloadLater: true
    property bool   editShowQueueSelectionOnBatchDownload: true
    property bool   editUseCustomUserAgent:    false
    property string editCustomUserAgent:       ""
    property int    editSavedSpeedLimitKBps:   500
    property int    editBypassInterceptKey:    0
    property bool   editLaunchOnStartup:       false
    property bool   editClipboardMonitorEnabled: false
    property int    editDoubleClickAction:     0
    property bool   editSpeedScheduleEnabled:  false
    property string editSpeedScheduleJson:     "[]"
    property bool   editAutoCheckUpdates:      true
    property int    editLastTryDateStyle:      0
    property bool   editLastTryUse24Hour:      true
    property bool   editLastTryShowSeconds:    true

    readonly property string defaultUserAgent: "Stellar/" + App.appVersion
    readonly property string displayedUserAgent: editUseCustomUserAgent
        ? editCustomUserAgent
        : defaultUserAgent
    readonly property string lastTryPreview: {
        var datePart
        switch (editLastTryDateStyle) {
        case 1:
            datePart = "4/10/2026"
            break
        case 2:
            datePart = "10/4/2026"
            break
        case 3:
            datePart = "2026-04-10"
            break
        default:
            datePart = "Apr 10 2026"
            break
        }

        var timePart
        if (editLastTryUse24Hour)
            timePart = editLastTryShowSeconds ? "15:49:22" : "15:49"
        else
            timePart = editLastTryShowSeconds ? "3:49:22 PM" : "3:49 PM"

        return datePart + " " + timePart
    }

    function _normalizedMonitoredExtensionsText() {
        return monitoredExtsArea
            ? monitoredExtsArea.text.split(/[\s,]+/).map(function(s) {
                return s.trim().toLowerCase().replace(/^\./, "")
            }).filter(function(s) { return s.length > 0 }).join("|")
            : App.settings.monitoredExtensions.join("|")
    }

    function _normalizedExcludedSitesText() {
        return excludedSitesArea
            ? excludedSitesArea.text.split(/\s+/).map(function(s) {
                return s.trim()
            }).filter(function(s) { return s.length > 0 }).join("|")
            : App.settings.excludedSites.join("|")
    }

    function _normalizedExcludedAddressesText() {
        return excludedAddrsArea
            ? excludedAddrsArea.text.split("\n").map(function(s) {
                return s.trim()
            }).filter(function(s) { return s.length > 0 }).join("|")
            : App.settings.excludedAddresses.join("|")
    }

    Component.onCompleted: resetEdits()
    onVisibleChanged: { if (visible) resetEdits() }

    Connections {
        target: App.settings
        function onGlobalSpeedLimitKBpsChanged() {
            root.editGlobalSpeedLimitKBps = App.settings.globalSpeedLimitKBps
            if (root.editGlobalSpeedLimitKBps > 0 && root.editSavedSpeedLimitKBps === 0) {
                root.editSavedSpeedLimitKBps = root.editGlobalSpeedLimitKBps
            }
        }
    }

    // Track whether anything has been changed
    readonly property bool settingsChanged:
        editMaxConcurrent         !== App.settings.maxConcurrent        ||
        editSegmentsPerDownload   !== App.settings.segmentsPerDownload  ||
        editDefaultSavePath       !== App.settings.defaultSavePath      ||
        editTemporaryDirectory    !== App.settings.temporaryDirectory   ||
        editGlobalSpeedLimitKBps  !== App.settings.globalSpeedLimitKBps ||
        editMinimizeToTray        !== App.settings.minimizeToTray       ||
        editCloseToTray           !== App.settings.closeToTray          ||
        editShowTips              !== App.settings.showTips             ||
        editMaxRetries            !== App.settings.maxRetries           ||
        editConnectionTimeoutSecs !== App.settings.connectionTimeoutSecs ||
        editDuplicateAction       !== App.settings.duplicateAction  ||
        editStartImmediately      !== App.settings.startImmediately ||
        editSpeedLimiterOnStartup !== App.settings.speedLimiterOnStartup ||
        editStartDownloadWhileFileInfo !== App.settings.startDownloadWhileFileInfo ||
        editUseCustomUserAgent    !== App.settings.useCustomUserAgent ||
        editCustomUserAgent       !== App.settings.customUserAgent ||
        editShowQueueSelectionOnDownloadLater !== App.settings.showQueueSelectionOnDownloadLater ||
        editShowQueueSelectionOnBatchDownload  !== App.settings.showQueueSelectionOnBatchDownload ||
        editBypassInterceptKey    !== App.settings.bypassInterceptKey ||
        editSavedSpeedLimitKBps   !== App.settings.savedSpeedLimitKBps ||
        editShowDownloadComplete  !== App.settings.showDownloadComplete ||
        editShowCompletionNotification !== App.settings.showCompletionNotification ||
        editShowErrorNotification !== App.settings.showErrorNotification ||
        editShowFinishedCount     !== App.settings.showFinishedCount ||
        editLaunchOnStartup       !== App.settings.launchOnStartup ||
        editClipboardMonitorEnabled !== App.settings.clipboardMonitorEnabled ||
        editDoubleClickAction     !== App.settings.doubleClickAction ||
        editSpeedScheduleEnabled  !== App.settings.speedScheduleEnabled ||
        editSpeedScheduleJson     !== App.settings.speedScheduleJson ||
        editAutoCheckUpdates      !== App.settings.autoCheckUpdates ||
        editLastTryDateStyle      !== App.settings.lastTryDateStyle ||
        editLastTryUse24Hour      !== App.settings.lastTryUse24Hour ||
        editLastTryShowSeconds    !== App.settings.lastTryShowSeconds

    property bool catDirty:       false
    property bool loadingCategory: false   // suppresses onTextChanged during programmatic load
    readonly property bool browserChanged:
        _normalizedMonitoredExtensionsText() !== App.settings.monitoredExtensions.join("|") ||
        _normalizedExcludedSitesText() !== App.settings.excludedSites.join("|") ||
        _normalizedExcludedAddressesText() !== App.settings.excludedAddresses.join("|") ||
        editShowExceptionsDialog !== App.settings.showExceptionsDialog

    readonly property bool hasChanges: settingsChanged || catDirty || browserChanged

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

    FolderDialog {
        id: tempFolderDlg
        currentFolder: root.editTemporaryDirectory.length > 0
                       ? ("file:///" + root.editTemporaryDirectory.replace(/\\/g, "/")) : ""
        onAccepted: {
            var path = selectedFolder.toString()
                           .replace(/^file:\/\/\//, "").replace(/^file:\/\//, "")
            root.editTemporaryDirectory = path
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
        if (browserChanged) {
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

            App.settings.showExceptionsDialog = editShowExceptionsDialog
        }

        App.settings.maxConcurrent         = editMaxConcurrent
        App.settings.segmentsPerDownload   = editSegmentsPerDownload
        App.settings.defaultSavePath       = editDefaultSavePath
        App.settings.temporaryDirectory    = editTemporaryDirectory
        App.settings.globalSpeedLimitKBps  = editGlobalSpeedLimitKBps
        App.settings.minimizeToTray        = editMinimizeToTray
        App.settings.closeToTray           = editCloseToTray
        App.settings.showTips              = editShowTips
        App.settings.maxRetries            = editMaxRetries
        App.settings.connectionTimeoutSecs = editConnectionTimeoutSecs
        App.settings.duplicateAction       = editDuplicateAction
        App.settings.startImmediately       = editStartImmediately
        App.settings.speedLimiterOnStartup  = editSpeedLimiterOnStartup
        App.settings.startDownloadWhileFileInfo = editStartDownloadWhileFileInfo
        App.settings.showQueueSelectionOnDownloadLater = editShowQueueSelectionOnDownloadLater
        App.settings.showQueueSelectionOnBatchDownload  = editShowQueueSelectionOnBatchDownload
        App.settings.useCustomUserAgent    = editUseCustomUserAgent
        App.settings.customUserAgent       = editCustomUserAgent
        App.settings.bypassInterceptKey    = editBypassInterceptKey
        App.settings.savedSpeedLimitKBps    = editSavedSpeedLimitKBps
        App.settings.showDownloadComplete   = editShowDownloadComplete
        App.settings.showCompletionNotification = editShowCompletionNotification
        App.settings.showErrorNotification  = editShowErrorNotification
        App.settings.showFinishedCount      = editShowFinishedCount
        App.settings.launchOnStartup        = editLaunchOnStartup
        App.settings.clipboardMonitorEnabled = editClipboardMonitorEnabled
        App.settings.doubleClickAction      = editDoubleClickAction
        App.settings.speedScheduleEnabled   = editSpeedScheduleEnabled
        App.settings.speedScheduleJson      = editSpeedScheduleJson
        App.settings.autoCheckUpdates       = editAutoCheckUpdates
        App.settings.lastTryDateStyle       = editLastTryDateStyle
        App.settings.lastTryUse24Hour       = editLastTryUse24Hour
        App.settings.lastTryShowSeconds     = editLastTryShowSeconds
        App.settings.save()
        // Sync edit properties so settingsChanged resets to false
        resetEdits()
    }

    function resetEdits() {
        editMaxConcurrent         = App.settings.maxConcurrent
        editSegmentsPerDownload   = App.settings.segmentsPerDownload
        editDefaultSavePath       = App.settings.defaultSavePath
        editTemporaryDirectory    = App.settings.temporaryDirectory
        editGlobalSpeedLimitKBps  = App.settings.globalSpeedLimitKBps
        editMinimizeToTray        = App.settings.minimizeToTray
        editCloseToTray           = App.settings.closeToTray
        editShowTips              = App.settings.showTips
        editShowExceptionsDialog  = App.settings.showExceptionsDialog
        editMaxRetries            = App.settings.maxRetries
        editConnectionTimeoutSecs = App.settings.connectionTimeoutSecs
        editDuplicateAction       = App.settings.duplicateAction
        editStartImmediately      = App.settings.startImmediately
        editSpeedLimiterOnStartup = App.settings.speedLimiterOnStartup
        editStartDownloadWhileFileInfo = App.settings.startDownloadWhileFileInfo
        editShowQueueSelectionOnDownloadLater = App.settings.showQueueSelectionOnDownloadLater
        editShowQueueSelectionOnBatchDownload  = App.settings.showQueueSelectionOnBatchDownload
        editUseCustomUserAgent    = App.settings.useCustomUserAgent
        editCustomUserAgent       = App.settings.customUserAgent
        editBypassInterceptKey    = App.settings.bypassInterceptKey
        editSavedSpeedLimitKBps   = App.settings.savedSpeedLimitKBps
        editShowDownloadComplete  = App.settings.showDownloadComplete
        editShowCompletionNotification = App.settings.showCompletionNotification
        editShowErrorNotification = App.settings.showErrorNotification
        editShowFinishedCount     = App.settings.showFinishedCount
        editLaunchOnStartup       = App.settings.launchOnStartup
        editClipboardMonitorEnabled = App.settings.clipboardMonitorEnabled
        editDoubleClickAction     = App.settings.doubleClickAction
        editSpeedScheduleEnabled  = App.settings.speedScheduleEnabled
        editSpeedScheduleJson     = App.settings.speedScheduleJson || "[]"
        editAutoCheckUpdates      = App.settings.autoCheckUpdates
        editLastTryDateStyle      = App.settings.lastTryDateStyle
        editLastTryUse24Hour      = App.settings.lastTryUse24Hour
        editLastTryShowSeconds    = App.settings.lastTryShowSeconds
        // Reset dirty flags so Apply button is disabled until user actually changes something
        catDirty = false
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
                    ScrollView {
                        anchors.fill: parent
                        contentWidth: availableWidth
                        clip: true

                    ColumnLayout {
                        width: parent.width
                        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
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

                        Rectangle { Layout.fillWidth: true; height: 1; color: "#2e2e2e" }

                        Text {
                            text: "User Agent"
                            color: "#ffffff"; font.pixelSize: 14; font.bold: true
                        }

                        Text {
                            text: "When custom mode is off, Stellar uses its built-in User-Agent with the current version."
                            color: "#c0c0c0"; font.pixelSize: 13
                            wrapMode: Text.WordWrap
                            Layout.fillWidth: true
                        }

                        CheckBox {
                            text: "Use custom user agent"
                            topPadding: 0; bottomPadding: 0
                            checked: root.editUseCustomUserAgent
                            onCheckedChanged: root.editUseCustomUserAgent = checked
                            contentItem: Text {
                                text: parent.text
                                color: "#d0d0d0"; font.pixelSize: 13
                                leftPadding: parent.indicator.width + 4
                            }
                        }

                        TextField {
                            Layout.fillWidth: true
                            text: root.displayedUserAgent
                            readOnly: !root.editUseCustomUserAgent
                            selectByMouse: true
                            onTextEdited: root.editCustomUserAgent = text
                            color: root.editUseCustomUserAgent ? "#d0d0d0" : "#7a7a7a"
                            font.pixelSize: 13
                            background: Rectangle {
                                color: root.editUseCustomUserAgent ? "#2d2d2d" : "#252525"
                                border.color: root.editUseCustomUserAgent ? "#4a4a4a" : "#3a3a3a"
                                radius: 3
                            }
                        }

                        Text {
                            text: root.editUseCustomUserAgent
                                  ? "This value will be sent exactly as entered."
                                  : "Built-in default shown above. Enable the checkbox to edit and override it."
                            color: "#555"; font.pixelSize: 10
                            wrapMode: Text.WordWrap
                            Layout.fillWidth: true
                        }

                        Item { height: 12 }
                    }
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
                                    // Warn when a category extension isn't in the browser auto-download list
                                    Text {
                                        Layout.fillWidth: true
                                        wrapMode: Text.WordWrap
                                        font.pixelSize: 11
                                        color: "#e8c840"
                                        visible: text.length > 0
                                        text: {
                                            var typed = catEditExts.text.split(/[\s,]+/).map(function(s) {
                                                return s.trim().toLowerCase().replace(/^\./, "")
                                            }).filter(function(s) { return s.length > 0 })

                                            // Use the live browser tab field if available, else fall back to saved setting
                                            var monitored = monitoredExtsArea
                                                ? monitoredExtsArea.text.split(/[\s,]+/).map(function(s) {
                                                    return s.trim().toLowerCase().replace(/^\./, "")
                                                }).filter(function(s) { return s.length > 0 })
                                                : App.settings.monitoredExtensions.slice()

                                            var missing = typed.filter(function(e) {
                                                return e.length > 0 && monitored.indexOf(e) < 0
                                            })
                                            return missing.length > 0
                                                ? "⚠ Not in browser auto-download list: " + missing.join(", ")
                                                : ""
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
                    ScrollView {
                        anchors.fill: parent
                        contentWidth: availableWidth
                        clip: true

                        ColumnLayout {
                            width: parent.width - 24
                            x: 12
                            y: 12
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

                        Rectangle { Layout.fillWidth: true; height: 1; color: "#2e2e2e" }

                        Text { text: "Stellar temporary directory:"; color: "#c0c0c0"; font.pixelSize: 13 }
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8
                            TextField {
                                Layout.fillWidth: true
                                text: root.editTemporaryDirectory
                                onTextChanged: root.editTemporaryDirectory = text
                                color: "#d0d0d0"; font.pixelSize: 13
                                background: Rectangle { color: "#2d2d2d"; border.color: "#4a4a4a"; radius: 3 }
                            }
                            DlgButton {
                                text: "Browse"
                                onClicked: tempFolderDlg.open()
                            }
                        }

                        Text {
                            text: "Stellar stores partially downloaded file parts and metadata here while downloading and assembling files."
                            color: "#7a7a7a"; font.pixelSize: 11
                            wrapMode: Text.WordWrap
                            Layout.fillWidth: true
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

                        CheckBox {
                            text: "Start downloading immediately while displaying \"Download File Info\" dialog"
                            topPadding: 0; bottomPadding: 0
                            checked: root.editStartDownloadWhileFileInfo
                            onCheckedChanged: root.editStartDownloadWhileFileInfo = checked
                            contentItem: Text { text: parent.text; color: "#d0d0d0"; font.pixelSize: 13; leftPadding: parent.indicator.width + 4; wrapMode: Text.WordWrap; Layout.fillWidth: true }
                        }

                        CheckBox {
                            text: "Show queue selection panel on pressing Download Later"
                            topPadding: 0; bottomPadding: 0
                            checked: root.editShowQueueSelectionOnDownloadLater
                            onCheckedChanged: root.editShowQueueSelectionOnDownloadLater = checked
                            contentItem: Text { text: parent.text; color: "#d0d0d0"; font.pixelSize: 13; leftPadding: parent.indicator.width + 4; wrapMode: Text.WordWrap; Layout.fillWidth: true }
                        }
                        CheckBox {
                            text: "Show queue selection panel on closing batch downloads dialog"
                            topPadding: 0; bottomPadding: 0
                            checked: root.editShowQueueSelectionOnBatchDownload
                            onCheckedChanged: root.editShowQueueSelectionOnBatchDownload = checked
                            contentItem: Text { text: parent.text; color: "#d0d0d0"; font.pixelSize: 13; leftPadding: parent.indicator.width + 4; wrapMode: Text.WordWrap; Layout.fillWidth: true }
                        }
                        Text {
                            text: "Note: These settings don't apply to queue processing for the Start Downloading Immediately setting and Show Download Complete dialog setting."
                            color: "#7a7a7a"; font.pixelSize: 10
                            wrapMode: Text.WordWrap
                            Layout.fillWidth: true
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
                            currentIndex: root.editDuplicateAction
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

                        Rectangle { Layout.fillWidth: true; height: 1; color: "#2e2e2e" }

                        Text { text: "Double-clicking on a download in the file list:"; color: "#c0c0c0"; font.pixelSize: 13 }
                        ComboBox {
                            id: doubleClickActionCombo
                            model: [
                                "Open file properties dialog",
                                "Open file",
                                "Open folder"
                            ]
                            currentIndex: root.editDoubleClickAction
                            implicitWidth: 260
                            font.pixelSize: 12
                            background: Rectangle { color: "#2d2d2d"; border.color: "#4a4a4a"; radius: 3 }
                            contentItem: Text {
                                leftPadding: 8
                                text: doubleClickActionCombo.displayText
                                color: "#d0d0d0"; font: doubleClickActionCombo.font
                                verticalAlignment: Text.AlignVCenter
                            }
                            onCurrentIndexChanged: root.editDoubleClickAction = currentIndex
                        }

                        Rectangle { Layout.fillWidth: true; height: 1; color: "#2e2e2e" }

                        Text { text: "Last try date format:"; color: "#c0c0c0"; font.pixelSize: 13 }
                        ComboBox {
                            id: lastTryDateStyleCombo
                            model: [
                                "Apr 10 2026",
                                "4/10/2026",
                                "10/4/2026",
                                "2026-04-10"
                            ]
                            currentIndex: root.editLastTryDateStyle
                            implicitWidth: 220
                            font.pixelSize: 12
                            background: Rectangle { color: "#2d2d2d"; border.color: "#4a4a4a"; radius: 3 }
                            contentItem: Text {
                                leftPadding: 8
                                text: lastTryDateStyleCombo.displayText
                                color: "#d0d0d0"; font: lastTryDateStyleCombo.font
                                verticalAlignment: Text.AlignVCenter
                            }
                            onCurrentIndexChanged: root.editLastTryDateStyle = currentIndex
                        }

                        Text { text: "Time format:"; color: "#c0c0c0"; font.pixelSize: 13 }
                        ComboBox {
                            id: lastTryTimeModeCombo
                            model: [
                                "24-hour time",
                                "12-hour time"
                            ]
                            currentIndex: root.editLastTryUse24Hour ? 0 : 1
                            implicitWidth: 220
                            font.pixelSize: 12
                            background: Rectangle { color: "#2d2d2d"; border.color: "#4a4a4a"; radius: 3 }
                            contentItem: Text {
                                leftPadding: 8
                                text: lastTryTimeModeCombo.displayText
                                color: "#d0d0d0"; font: lastTryTimeModeCombo.font
                                verticalAlignment: Text.AlignVCenter
                            }
                            onCurrentIndexChanged: root.editLastTryUse24Hour = currentIndex === 0
                        }

                        CheckBox {
                            text: "Show seconds"
                            topPadding: 0; bottomPadding: 0
                            checked: root.editLastTryShowSeconds
                            onCheckedChanged: root.editLastTryShowSeconds = checked
                            contentItem: Text { text: parent.text; color: "#d0d0d0"; font.pixelSize: 13; leftPadding: parent.indicator.width + 4 }
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: previewColumn.implicitHeight + 16
                            radius: 4
                            color: "#242424"
                            border.color: "#3a3a3a"

                            ColumnLayout {
                                id: previewColumn
                                anchors.fill: parent
                                anchors.margins: 8
                                spacing: 4

                                Text { text: "Preview"; color: "#909090"; font.pixelSize: 11 }
                                Text { text: root.lastTryPreview; color: "#f0f0f0"; font.pixelSize: 13; font.family: "Consolas" }
                            }
                        }

                            Item { height: 12 }
                        }
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
                                checked: root.editShowExceptionsDialog
                                onCheckedChanged: root.editShowExceptionsDialog = checked
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
                                }
                            }

                            Text {
                                text: "One URL pattern per line. Wildcards (*) supported."
                                color: "#555"; font.pixelSize: 10
                            }

                            Rectangle { Layout.fillWidth: true; height: 1; color: "#2e2e2e" }

                            // ── Bypass interception key ────────────────────────────
                            Text {
                                text: "Bypass Download Interception"
                                color: "#ffffff"; font.pixelSize: 14; font.bold: true
                            }

                            Text {
                                text: "Hold this key while clicking a download link to skip interception and let the browser download:"
                                color: "#c0c0c0"; font.pixelSize: 13
                                wrapMode: Text.WordWrap
                                Layout.fillWidth: true
                            }

                            Row {
                                spacing: 12
                                ComboBox {
                                    id: bypassKeyCombo
                                    model: ["None", "Alt", "Ctrl", "Shift"]
                                    currentIndex: root.editBypassInterceptKey
                                    implicitWidth: 120
                                    font.pixelSize: 12
                                    background: Rectangle { color: "#2d2d2d"; border.color: "#4a4a4a"; radius: 3 }
                                    contentItem: Text {
                                        leftPadding: 8
                                        text: bypassKeyCombo.displayText
                                        color: "#d0d0d0"; font: bypassKeyCombo.font
                                        verticalAlignment: Text.AlignVCenter
                                    }
                                    onCurrentIndexChanged: root.editBypassInterceptKey = currentIndex
                                }
                            }

                            Item { height: 10 }
                        }
                    }
                }

                // Speed Limiter
                Item {
                    id: speedLimiterPage
                    ScrollView {
                        anchors.fill: parent
                        contentWidth: availableWidth
                        clip: true

                    ColumnLayout {
                        width: speedLimiterPage.width - 24
                        x: 12; y: 12
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
                                Text { text: "Maximum speed:"; color: "#a0a0a0"; font.pixelSize: 13 }
                                TextField {
                                    id: speedLimitField
                                    implicitWidth: 90
                                    color: "#d0d0d0"; font.pixelSize: 13
                                    background: Rectangle { color: "#2d2d2d"; border.color: "#4a4a4a"; radius: 3 }

                                    // Populate once on load and whenever the settings are reset
                                    function syncFromModel() {
                                        var val = root.editGlobalSpeedLimitKBps > 0
                                            ? root.editGlobalSpeedLimitKBps
                                            : root.editSavedSpeedLimitKBps
                                        if (parseInt(text) !== val)
                                            text = val.toString()
                                    }
                                    Component.onCompleted: syncFromModel()
                                    Connections {
                                        target: root
                                        function onEditGlobalSpeedLimitKBpsChanged() { speedLimitField.syncFromModel() }
                                        function onEditSavedSpeedLimitKBpsChanged()  {
                                            // Only sync when the field isn't the one driving the change
                                            if (!speedLimitField.activeFocus)
                                                speedLimitField.syncFromModel()
                                        }
                                    }

                                    onTextEdited: {
                                        var v = parseInt(text)
                                        if (!isNaN(v) && v > 0) {
                                            if (globalLimitChk.checked)
                                                root.editGlobalSpeedLimitKBps = v
                                            root.editSavedSpeedLimitKBps = v
                                        }
                                    }
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

                        Rectangle { Layout.fillWidth: true; height: 1; color: "#3a3a3a" }

                        // ── Speed Limiter Scheduler ───────────────────────────────────────────────
                        // Each rule: days[], onHour (1-12), onMinute (0-59), onAmPm, offHour,
                        // offMinute, offAmPm, limitKBps. Stored as JSON string in editSpeedScheduleJson.
                        CheckBox {
                            text: "Enable speed limiter scheduler"
                            topPadding: 0; bottomPadding: 0
                            checked: root.editSpeedScheduleEnabled
                            onCheckedChanged: root.editSpeedScheduleEnabled = checked
                            contentItem: Text { text: parent.text; color: "#d0d0d0"; font.pixelSize: 13; leftPadding: parent.indicator.width + 4 }
                        }

                        ColumnLayout {
                            id: scheduleCol
                            visible: root.editSpeedScheduleEnabled
                            Layout.fillWidth: true
                            spacing: 8

                            property var rules: {
                                try { return JSON.parse(root.editSpeedScheduleJson || "[]") }
                                catch(e) { return [] }
                            }
                            function saveRules(arr) { root.editSpeedScheduleJson = JSON.stringify(arr) }
                            function blankRule() {
                                return { days: ["Mon","Tue","Wed","Thu","Fri"],
                                         onHour: "9", onMinute: "00", onAmPm: "AM",
                                         offHour: "5", offMinute: "00", offAmPm: "PM",
                                         limitKBps: 500 }
                            }

                            // ── Per-rule cards ───────────────────────────────────────────────────
                            // Style matches GrabberScheduleDialog: #1b1b1b panels, #333 borders,
                            // #e0e0e0 text, 12px font, 26px tall inputs with small ▲▼ arrows.
                            Repeater {
                                model: scheduleCol.rules.length
                                delegate: Rectangle {
                                    id: ruleCard
                                    required property int index
                                    Layout.fillWidth: true
                                    implicitHeight: cardCol.implicitHeight + 18
                                    color: "#1b1b1b"
                                    radius: 3
                                    border.color: "#333333"

                                    property var rule: scheduleCol.rules[ruleCard.index] || scheduleCol.blankRule()

                                    // Clone this rule's field k to value v and persist to JSON
                                    function patch(k, v) {
                                        var arr = JSON.parse(root.editSpeedScheduleJson || "[]")
                                        var r = JSON.parse(JSON.stringify(arr[ruleCard.index]))
                                        r[k] = v
                                        arr[ruleCard.index] = r
                                        scheduleCol.saveRules(arr)
                                    }
                                    // Toggle a day in/out of this rule's days array
                                    function patchDay(day, on) {
                                        var arr = JSON.parse(root.editSpeedScheduleJson || "[]")
                                        var r = JSON.parse(JSON.stringify(arr[ruleCard.index]))
                                        var idx = r.days.indexOf(day)
                                        if (on && idx < 0) r.days.push(day)
                                        else if (!on && idx >= 0) r.days.splice(idx, 1)
                                        arr[ruleCard.index] = r
                                        scheduleCol.saveRules(arr)
                                    }

                                    ColumnLayout {
                                        id: cardCol
                                        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 10 }
                                        spacing: 8

                                        // ── Header ───────────────────────────────────────────────
                                        RowLayout {
                                            Layout.fillWidth: true
                                            Text {
                                                text: "Rule " + (ruleCard.index + 1)
                                                color: "#888888"; font.pixelSize: 11; font.bold: true
                                            }
                                            Item { Layout.fillWidth: true }
                                            Text {
                                                text: "Remove"
                                                color: removeHov.containsMouse ? "#ff7777" : "#aa3333"
                                                font.pixelSize: 11
                                                MouseArea {
                                                    id: removeHov
                                                    anchors.fill: parent
                                                    hoverEnabled: true
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: {
                                                        var arr = JSON.parse(root.editSpeedScheduleJson || "[]")
                                                        arr.splice(ruleCard.index, 1)
                                                        scheduleCol.saveRules(arr)
                                                    }
                                                }
                                            }
                                        }

                                        // ── Day pills — clickable, blue when active ───────────────
                                        RowLayout {
                                            spacing: 3
                                            Repeater {
                                                model: ["Mon","Tue","Wed","Thu","Fri","Sat","Sun"]
                                                delegate: Rectangle {
                                                    required property int index
                                                    required property var modelData
                                                    property bool on: ruleCard.rule.days && ruleCard.rule.days.indexOf(modelData) >= 0
                                                    width: 36; height: 22; radius: 2
                                                    color: on ? "#1a3a6a" : "#252525"
                                                    border.color: on ? "#4488dd" : "#3a3a3a"
                                                    Text {
                                                        anchors.centerIn: parent
                                                        text: modelData
                                                        color: on ? "#aaccff" : "#666666"
                                                        font.pixelSize: 11
                                                    }
                                                    MouseArea {
                                                        anchors.fill: parent
                                                        cursorShape: Qt.PointingHandCursor
                                                        onClicked: ruleCard.patchDay(modelData, !on)
                                                    }
                                                }
                                            }
                                        }

                                        // ── On → Off / Limit row ──────────────────────────────────
                                        // Uses the same compact input style as GrabberScheduleDialog:
                                        // TextInput in a 50×26 Rectangle, colon separator, DarkCombo for AM/PM.
                                        RowLayout {
                                            spacing: 4
                                            Layout.fillWidth: true

                                            Text { text: "On"; color: "#aaaaaa"; font.pixelSize: 12 }

                                            // On-hour input (1–12)
                                            Rectangle {
                                                width: 50; height: 26; radius: 2
                                                color: "#1b1b1b"; border.color: onHourFld.activeFocus ? "#4488dd" : "#3a3a3a"
                                                TextInput {
                                                    id: onHourFld
                                                    anchors { fill: parent; leftMargin: 6; rightMargin: 6 }
                                                    text: String(ruleCard.rule.onHour || "9")
                                                    color: "#e0e0e0"; font.pixelSize: 12
                                                    horizontalAlignment: TextInput.AlignHCenter
                                                    verticalAlignment: TextInput.AlignVCenter
                                                    validator: IntValidator { bottom: 1; top: 12 }
                                                    onTextEdited: ruleCard.patch("onHour", text)
                                                }
                                            }
                                            Text { text: ":"; color: "#aaaaaa"; font.pixelSize: 13 }
                                            // On-minute input (00–59), zero-padded
                                            Rectangle {
                                                width: 50; height: 26; radius: 2
                                                color: "#1b1b1b"; border.color: onMinFld.activeFocus ? "#4488dd" : "#3a3a3a"
                                                TextInput {
                                                    id: onMinFld
                                                    anchors { fill: parent; leftMargin: 6; rightMargin: 6 }
                                                    text: {
                                                        var m = parseInt(ruleCard.rule.onMinute)
                                                        return isNaN(m) ? "00" : (m < 10 ? "0" + m : String(m))
                                                    }
                                                    color: "#e0e0e0"; font.pixelSize: 12
                                                    horizontalAlignment: TextInput.AlignHCenter
                                                    verticalAlignment: TextInput.AlignVCenter
                                                    validator: IntValidator { bottom: 0; top: 59 }
                                                    onTextEdited: ruleCard.patch("onMinute", text)
                                                }
                                            }
                                            // AM/PM combo for On time — same style as DarkCombo
                                            ComboBox {
                                                model: ["AM","PM"]
                                                currentIndex: (ruleCard.rule.onAmPm || "AM") === "PM" ? 1 : 0
                                                implicitWidth: 62; implicitHeight: 26
                                                font.pixelSize: 12
                                                contentItem: Text {
                                                    leftPadding: 8; rightPadding: 20
                                                    text: parent.displayText; color: "#e0e0e0"; font: parent.font
                                                    verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight
                                                }
                                                background: Rectangle { color: "#1b1b1b"; border.color: "#3a3a3a"; radius: 2 }
                                                indicator: Text { x: parent.width-width-6; y: (parent.height-height)/2; text: "▼"; color: "#888"; font.pixelSize: 8 }
                                                popup.background: Rectangle { color: "#2a2a2a"; border.color: "#444"; radius: 3 }
                                                onCurrentIndexChanged: ruleCard.patch("onAmPm", currentIndex === 1 ? "PM" : "AM")
                                            }

                                            Text { text: "→"; color: "#555555"; font.pixelSize: 13; leftPadding: 2; rightPadding: 2 }
                                            Text { text: "Off"; color: "#aaaaaa"; font.pixelSize: 12 }

                                            // Off-hour input (1–12)
                                            Rectangle {
                                                width: 50; height: 26; radius: 2
                                                color: "#1b1b1b"; border.color: offHourFld.activeFocus ? "#4488dd" : "#3a3a3a"
                                                TextInput {
                                                    id: offHourFld
                                                    anchors { fill: parent; leftMargin: 6; rightMargin: 6 }
                                                    text: String(ruleCard.rule.offHour || "5")
                                                    color: "#e0e0e0"; font.pixelSize: 12
                                                    horizontalAlignment: TextInput.AlignHCenter
                                                    verticalAlignment: TextInput.AlignVCenter
                                                    validator: IntValidator { bottom: 1; top: 12 }
                                                    onTextEdited: ruleCard.patch("offHour", text)
                                                }
                                            }
                                            Text { text: ":"; color: "#aaaaaa"; font.pixelSize: 13 }
                                            // Off-minute input (00–59)
                                            Rectangle {
                                                width: 50; height: 26; radius: 2
                                                color: "#1b1b1b"; border.color: offMinFld.activeFocus ? "#4488dd" : "#3a3a3a"
                                                TextInput {
                                                    id: offMinFld
                                                    anchors { fill: parent; leftMargin: 6; rightMargin: 6 }
                                                    text: {
                                                        var m = parseInt(ruleCard.rule.offMinute)
                                                        return isNaN(m) ? "00" : (m < 10 ? "0" + m : String(m))
                                                    }
                                                    color: "#e0e0e0"; font.pixelSize: 12
                                                    horizontalAlignment: TextInput.AlignHCenter
                                                    verticalAlignment: TextInput.AlignVCenter
                                                    validator: IntValidator { bottom: 0; top: 59 }
                                                    onTextEdited: ruleCard.patch("offMinute", text)
                                                }
                                            }
                                            // AM/PM combo for Off time
                                            ComboBox {
                                                model: ["AM","PM"]
                                                currentIndex: (ruleCard.rule.offAmPm || "PM") === "PM" ? 1 : 0
                                                implicitWidth: 62; implicitHeight: 26
                                                font.pixelSize: 12
                                                contentItem: Text {
                                                    leftPadding: 8; rightPadding: 20
                                                    text: parent.displayText; color: "#e0e0e0"; font: parent.font
                                                    verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight
                                                }
                                                background: Rectangle { color: "#1b1b1b"; border.color: "#3a3a3a"; radius: 2 }
                                                indicator: Text { x: parent.width-width-6; y: (parent.height-height)/2; text: "▼"; color: "#888"; font.pixelSize: 8 }
                                                popup.background: Rectangle { color: "#2a2a2a"; border.color: "#444"; radius: 3 }
                                                onCurrentIndexChanged: ruleCard.patch("offAmPm", currentIndex === 1 ? "PM" : "AM")
                                            }

                                        }

                                        // ── Speed limit row ───────────────────────────────────────
                                        RowLayout {
                                            spacing: 6
                                            Text { text: "Limit"; color: "#aaaaaa"; font.pixelSize: 12 }
                                            Rectangle {
                                                width: 70; height: 26; radius: 2
                                                color: "#1b1b1b"; border.color: limitFld.activeFocus ? "#4488dd" : "#3a3a3a"
                                                TextInput {
                                                    id: limitFld
                                                    anchors { fill: parent; leftMargin: 6; rightMargin: 6 }
                                                    text: String(ruleCard.rule.limitKBps || 500)
                                                    color: "#e0e0e0"; font.pixelSize: 12
                                                    horizontalAlignment: TextInput.AlignHCenter
                                                    verticalAlignment: TextInput.AlignVCenter
                                                    validator: IntValidator { bottom: 1; top: 999999 }
                                                    onTextEdited: {
                                                        var v = parseInt(text)
                                                        if (!isNaN(v) && v > 0) ruleCard.patch("limitKBps", v)
                                                    }
                                                }
                                            }
                                            Text { text: "KB/s"; color: "#aaaaaa"; font.pixelSize: 12 }
                                        }
                                    }
                                }
                            } // Repeater

                            // ── Add Rule button ──────────────────────────────────────────────────
                            DlgButton {
                                text: "+ Add Rule"
                                onClicked: {
                                    var arr = JSON.parse(root.editSpeedScheduleJson || "[]")
                                    arr.push(scheduleCol.blankRule())
                                    scheduleCol.saveRules(arr)
                                }
                            }

                            // Informational note — same blue-tinted style as GrabberScheduleDialog
                            Rectangle {
                                Layout.fillWidth: true
                                implicitHeight: scheduleNote.implicitHeight + 16
                                color: "#1a2030"; border.color: "#2a3050"; radius: 3
                                Text {
                                    id: scheduleNote
                                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: 8 }
                                    text: "Click a day pill to toggle it. Rules are evaluated every minute; first matching rule wins. The limiter is cleared automatically when no rule is active."
                                    color: "#8899bb"; font.pixelSize: 11; wrapMode: Text.WordWrap
                                }
                            }
                        } // scheduleCol

                        Item { height: 12 }
                    }
                    } // ScrollView
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
                            checked: root.editShowCompletionNotification
                            onCheckedChanged: root.editShowCompletionNotification = checked
                            contentItem: Text { text: parent.text; color: "#d0d0d0"; font.pixelSize: 13; leftPadding: parent.indicator.width + 4 }
                        }
                        CheckBox {
                            text: "Show notification on download error"
                            topPadding: 0; bottomPadding: 0
                            checked: root.editShowErrorNotification
                            onCheckedChanged: root.editShowErrorNotification = checked
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
                        CheckBox {
                            text: "Show finished download count in status bar"
                            topPadding: 0; bottomPadding: 0
                            checked: root.editShowFinishedCount
                            onCheckedChanged: root.editShowFinishedCount = checked
                            contentItem: Text { text: parent.text; color: "#d0d0d0"; font.pixelSize: 13; leftPadding: parent.indicator.width + 4 }
                        }

                        CheckBox {
                            text: "Launch Stellar on startup"
                            topPadding: 0; bottomPadding: 0
                            checked: root.editLaunchOnStartup
                            onCheckedChanged: root.editLaunchOnStartup = checked
                            contentItem: Text { text: parent.text; color: "#d0d0d0"; font.pixelSize: 13; leftPadding: parent.indicator.width + 4 }
                        }

                        Rectangle { Layout.fillWidth: true; height: 1; color: "#3a3a3a" }

                        Text { text: "Updates"; color: "#ffffff"; font.pixelSize: 14; font.bold: true }

                        CheckBox {
                            text: "Automatically check for updates"
                            topPadding: 0; bottomPadding: 0
                            checked: root.editAutoCheckUpdates
                            onCheckedChanged: root.editAutoCheckUpdates = checked
                            contentItem: Text { text: parent.text; color: "#d0d0d0"; font.pixelSize: 13; leftPadding: parent.indicator.width + 4 }
                        }

                        Rectangle { Layout.fillWidth: true; height: 1; color: "#3a3a3a" }

                        Text { text: "Clipboard Monitoring"; color: "#ffffff"; font.pixelSize: 14; font.bold: true }

                        CheckBox {
                            text: "Automatically start downloading URLs placed in the clipboard"
                            topPadding: 0; bottomPadding: 0
                            checked: root.editClipboardMonitorEnabled
                            onCheckedChanged: root.editClipboardMonitorEnabled = checked
                            contentItem: Text { text: parent.text; color: "#d0d0d0"; font.pixelSize: 13; leftPadding: parent.indicator.width + 4; wrapMode: Text.WordWrap; Layout.fillWidth: true }
                        }

                        Text {
                            text: "When a URL matching a monitored file type is copied to the clipboard, Stellar will ask if you want to download it. Only file types listed under Browser \u203a Automatically start downloading the following file types are picked up."
                            color: "#7a7a7a"; font.pixelSize: 11
                            wrapMode: Text.WordWrap
                            Layout.fillWidth: true
                            visible: root.editClipboardMonitorEnabled
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
                            Text { text: "Build date:"; color: "#808080"; font.pixelSize: 12 }
                            Text { text: App.buildTimeFormatted;  color: "#c0c0c0"; font.pixelSize: 12 }
                            Text { text: "Qt version:";  color: "#808080"; font.pixelSize: 12 }
                            Text { text: App.qtVersion;   color: "#c0c0c0"; font.pixelSize: 12 }
                            Text { text: "Platform:";    color: "#808080"; font.pixelSize: 12 }
                            Text {
                                text: {
                                    const os = Qt.platform.os
                                    if (os === "windows") return "Windows"
                                    if (os === "linux") return "Linux"
                                    if (os === "osx") return "macOS"
                                    return os.charAt(0).toUpperCase() + os.slice(1)
                                }
                                color: "#c0c0c0"; font.pixelSize: 12
                            }
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

                        RowLayout {
                            spacing: 8

                            DlgButton {
                                text: "Check for Updates"
                                onClicked: App.checkForUpdates(true)
                            }

                            Text {
                                text: App.updateAvailable ? ("Latest available: " + App.updateVersion) : ""
                                color: "#7a7a7a"
                                font.pixelSize: 11
                                visible: App.updateAvailable
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

                DlgButton {
                    text: "Apply"
                    primary: root.hasChanges
                    enabled: root.hasChanges
                    opacity: enabled ? 1.0 : 0.5
                    onClicked: if (root.hasChanges) root.applySettings()
                }

                DlgButton {
                    text: "OK"
                    primary: false
                    onClicked: { root.applySettings(); root.close() }
                }
            }
        }
    }
}
