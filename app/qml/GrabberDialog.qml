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
    title: qsTr("Stellar Grabber - Step %1 of %2: %3").arg(stepIndex + 1).arg(stepTitles.length).arg(stepTitles[stepIndex])
    width: 700
    height: 540
    minimumWidth: 700
    minimumHeight: 540
    color: ColorPalette.cardBg
    flags: Qt.Dialog | Qt.WindowTitleHint | Qt.WindowCloseButtonHint | Qt.WindowMinimizeButtonHint
    modality: Qt.ApplicationModal

    Material.theme: ColorPalette.materialTheme
    Material.foreground: ColorPalette.textPrimary
    Material.background: ColorPalette.materialBg
    Material.accent: "#4488dd"

    property string projectId: ""
    property int stepIndex: 0
    property bool startAdvancedVisible: false
    property bool explorerAdvancedVisible: true
    property bool fileAdvancedVisible: true
    property string selectedTemplateProjectId: ""
    property var recentProjectRows: []
    readonly property var stepTitles: [qsTr("Set start page"), qsTr("Save files to"), qsTr("Set explorer filters"), qsTr("Set file filters")]
    readonly property var templateValues: ["custom", "images", "video", "audio", "website"]
    readonly property var saveModeValues: ["byCategory", "selectedCategory", "directory"]
    readonly property int stepOneContentWidth: 700
    readonly property int laterStepContentWidth: 640
    readonly property var builtInIncludeFilters: [
        { name: "All Files  (*.*)", mask: "*.*", categoryId: "all" },
        { name: "Images Files", mask: "*.gif,*.jpg,*.jpeg,*.jpe,*.bmp,*.png,*.tif,*.tiff,*.webp,*.svg", categoryId: "all" },
        { name: "Video Files", mask: "*.mpg,*.mp4,*.mpeg,*.avi,*.mov,*.qt,*.mkv,*.wmv,*.flv,*.webm", categoryId: "video" },
        { name: "Audio Files", mask: "*.mp3,*.wma,*.wav,*.aac,*.ogg,*.flac,*.m4a", categoryId: "music" },
        { name: "PDF Document Files", mask: "*.pdf", categoryId: "documents" },
        { name: "Executable Files", mask: "*.exe,*.msi,*.msu,*.deb,*.rpm,*.appimage,*.dmg,*.pkg,*.apk", categoryId: "programs" },
        { name: "Compressed Files", mask: "*.zip,*.rar,*.7z,*.tar,*.gz,*.tgz,*.bz2,*.xz,*.zst", categoryId: "compressed" },
        { name: "Complete start page", mask: "<start page>,*.js,*.css,*.gif,*.jpg,*.jpeg,*.png,*.webp,*.svg,*.html,*.htm", categoryId: "documents" }
    ]
    readonly property var builtInExcludeFilters: [
        { name: "Don't use exclude filter", mask: "", categoryId: "" },
        { name: "Images Files", mask: "*.gif,*.jpg,*.jpeg,*.jpe,*.bmp,*.png,*.tif,*.tiff,*.webp,*.svg", categoryId: "" },
        { name: "Web content", mask: "*.html,*.htm,*.js,*.css,*.gif,*.jpg,*.jpeg,*.png,*.webp,*.svg", categoryId: "" },
        { name: "Video Files", mask: "*.mpg,*.mp4,*.mpeg,*.avi,*.mov,*.qt,*.mkv,*.wmv,*.flv,*.webm", categoryId: "" },
        { name: "Audio Files", mask: "*.mp3,*.wma,*.wav,*.aac,*.ogg,*.flac,*.m4a", categoryId: "" }
    ]

    signal resultsRequested(string projectId)

    ButtonGroup { id: exploreModeGroup }

    component StepLabel: Text {
        color: ColorPalette.textPrimary
        font.pixelSize: 13 * App.fontScale
        verticalAlignment: Text.AlignVCenter
    }

    component HintText: Text {
        color: ColorPalette.textSecond
        font.pixelSize: 11 * App.fontScale
        wrapMode: Text.WordWrap
    }

    component FieldBox: Rectangle {
        color: ColorPalette.dividerBg
        border.color: ColorPalette.border
        border.width: 1
        radius: 3
    }

    component WizardTextField: TextField {
        color: ColorPalette.textPrimary
        font.pixelSize: 13 * App.fontScale
        selectionColor: "#4f5560"
        selectedTextColor: ColorPalette.textHeader
        leftPadding: 8
        rightPadding: 8
        topPadding: 6
        bottomPadding: 6
        background: FieldBox {}
    }

    component WizardTextArea: TextArea {
        color: ColorPalette.textPrimary
        font.pixelSize: 12 * App.fontScale
        selectionColor: "#4f5560"
        selectedTextColor: ColorPalette.textHeader
        leftPadding: 8
        rightPadding: 8
        topPadding: 8
        bottomPadding: 8
        wrapMode: TextArea.Wrap
        background: FieldBox {}
    }

    component WizardCombo: ComboBox {
        font.pixelSize: 13 * App.fontScale
        background: FieldBox {}
        contentItem: Text {
            leftPadding: 8
            rightPadding: 24
            text: parent.displayText
            color: ColorPalette.textPrimary
            font: parent.font
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
        }
        popup.background: Rectangle {
            color: ColorPalette.dividerBg
            border.color: ColorPalette.border
            radius: 3
        }
    }

    component WizardCheckBox: CheckBox {
        spacing: 6
        topPadding: 0
        bottomPadding: 0
        leftPadding: 0
        rightPadding: 0
        indicator: Rectangle {
            implicitWidth: 14
            implicitHeight: 14
            x: 0
            y: (parent.height - height) / 2
            radius: 3
            color: parent.checked ? ColorPalette.accent : ColorPalette.inputBg
            border.color: parent.checked ? ColorPalette.accent : ColorPalette.border
            border.width: 1
            Text {
                anchors.centerIn: parent
                text: "✓"
                color: "#ffffff"
                font.pixelSize: 10; font.bold: true
                visible: parent.parent.checked
            }
        }
        contentItem: Text {
            text: parent.text
            color: parent.enabled ? ColorPalette.textPrimary : ColorPalette.textDisabled
            font.pixelSize: 13 * App.fontScale
            leftPadding: parent.indicator.width + parent.spacing
            verticalAlignment: Text.AlignVCenter
        }
    }

    component WizardRadioButton: RadioButton {
        spacing: 6
        topPadding: 0
        bottomPadding: 0
        leftPadding: 0
        rightPadding: 0
        indicator: Rectangle {
            implicitWidth: 14
            implicitHeight: 14
            radius: 7
            x: 0
            y: (parent.height - height) / 2
            color: ColorPalette.inputBg
            border.color: parent.checked ? ColorPalette.accent : ColorPalette.border
            border.width: 1
            Rectangle {
                anchors.centerIn: parent
                width: 7
                height: 7
                radius: 4
                color: ColorPalette.accent
                visible: parent.parent.checked
            }
        }
        contentItem: Text {
            text: parent.text
            color: parent.enabled ? ColorPalette.textPrimary : ColorPalette.textDisabled
            font.pixelSize: 13 * App.fontScale
            leftPadding: parent.indicator.width + parent.spacing
            verticalAlignment: Text.AlignVCenter
        }
    }

    function splitLines(text) {
        if (!text || text.trim().length === 0)
            return []
        return text.split(/\r?\n/).map(function(line) { return line.trim() }).filter(function(line) { return line.length > 0 })
    }

    function categoryIds() {
        var ids = []
        for (var i = 0; i < App.categoryModel.rowCount(); ++i)
            ids.push(App.categoryModel.categoryData(i).id)
        return ids
    }

    function categoryLabels() {
        var labels = []
        for (var i = 0; i < App.categoryModel.rowCount(); ++i)
            labels.push(App.categoryModel.categoryData(i).label)
        return labels
    }

    function recentProjects() {
        var rows = []
        for (var i = 0; i < App.grabberProjectModel.rowCount(); ++i) {
            var project = App.grabberProjectModel.projectData(i)
            if (!project.isTemplate)
                rows.push(project)
        }
        rows.sort(function(a, b) {
            var av = a.lastRunAt ? new Date(a.lastRunAt).getTime() : 0
            var bv = b.lastRunAt ? new Date(b.lastRunAt).getTime() : 0
            return bv - av
        })
        return rows.slice(0, 8)
    }

    function refreshRecentProjects() {
        recentProjectRows = recentProjects()
    }

    function templateOptions() {
        var options = [
            { text: qsTr("Custom settings"), value: "custom", templateId: "" },
            { text: qsTr("All images from a web site"), value: "images", templateId: "" },
            { text: qsTr("All video from a web site"), value: "video", templateId: "" },
            { text: qsTr("All audio from a web site"), value: "audio", templateId: "" },
            { text: qsTr("Complete web site"), value: "website", templateId: "" }
        ]
        for (var i = 0; i < App.grabberProjectModel.rowCount(); ++i) {
            var project = App.grabberProjectModel.projectData(i)
            if (project.isTemplate)
                options.push({ text: project.name, value: "saved-template", templateId: project.id })
        }
        return options
    }

    function loadProjectById(projectId) {
        if (!projectId || projectId.length === 0)
            return
        loadProject(App.grabberProjectData(projectId))
    }

    function applyTemplate(templateId) {
        if (templateId === "images") {
            fileIncludeField.text = "*.jpg\n*.jpeg\n*.png\n*.gif\n*.webp\n*.bmp\n*.svg"
            _setTemplateCategory("all")
        } else if (templateId === "video") {
            fileIncludeField.text = "*.mp4\n*.mkv\n*.avi\n*.mov\n*.webm\n*.mpeg\n*.mpg"
            _setTemplateCategory("video")
        } else if (templateId === "audio") {
            fileIncludeField.text = "*.mp3\n*.flac\n*.aac\n*.ogg\n*.wav\n*.m4a"
            _setTemplateCategory("music")
        } else if (templateId === "website") {
            fileIncludeField.text = "*.html\n*.htm\n*.css\n*.js\n*.jpg\n*.jpeg\n*.png\n*.gif"
            useRelativeFolders.checked = true
            convertLinksChk.checked = true
            _setTemplateCategory("documents")
        }
    }

    function _setTemplateCategory(categoryId) {
        saveModeCombo.currentIndex = 1
        var ids = categoryIds()
        var idx = ids.indexOf(categoryId)
        if (idx >= 0)
            saveCategoryCombo.currentIndex = idx
    }

    function applyIncludeFilter(mask, categoryId) {
        fileIncludeField.text = mask.replace(/,/g, "\n")
        if (categoryId && categoryId.length > 0)
            _setTemplateCategory(categoryId)
    }

    function applyExcludeFilter(mask) {
        fileExcludeField.text = mask && mask.length > 0 ? mask.replace(/,/g, "\n") : ""
    }

    function filterLabels(rows) {
        return rows.map(function(row) { return row.name })
    }

    function parseCustomFilters(json) {
        if (!json || json.length === 0)
            return []
        try {
            var parsed = JSON.parse(json)
            return Array.isArray(parsed) ? parsed : []
        } catch (e) {
            return []
        }
    }

    function includeFilterRows() {
        return builtInIncludeFilters.concat(parseCustomFilters(App.settings.grabberIncludeFiltersJson))
    }

    function excludeFilterRows() {
        return builtInExcludeFilters.concat(parseCustomFilters(App.settings.grabberExcludeFiltersJson))
    }

    function projectMap() {
        return {
            id: root.projectId,
            name: projectNameField.text.trim(),
            startUrl: startUrlField.text.trim(),
            username: useAuthorizationChk.checked ? usernameField.text.trim() : "",
            password: useAuthorizationChk.checked ? passwordField.text : "",
            loginUrl: manualLoginChk.checked ? loginUrlField.text.trim() : "",
            logoutPatterns: dontOpenLogoutChk.checked ? splitLines(logoutField.text) : [],
            templateId: templateValues[templateCombo.currentIndex] || "custom",
            isTemplate: false,
            saveMode: saveModeValues[saveModeCombo.currentIndex] || "byCategory",
            selectedCategoryId: categoryIds()[saveCategoryCombo.currentIndex] || "all",
            projectCategoryId: root.projectId.length > 0 ? root.projectId : "",
            savePath: savePathField.text.trim(),
            useRelativeSubfolders: useRelativeFolders.checked,
            convertLinksToLocal: convertLinksChk.checked,
            overwriteExistingFiles: overwriteExistingChk.checked,
            addCheckedFilesToIdm: addCheckedFilesChk.checked,
            exploreWholeSite: exploreWholeSiteRadio.checked,
            exploreThisLevels: exploreWholeSiteRadio.checked ? 20 : thisSiteSpin.value,
            exploreOtherLevels: exploreWholeSiteRadio.checked ? 20 : otherSitesSpin.value,
            ignorePopupWindows: ignorePopupChk.checked,
            dontExploreParentDirectories: dontExploreParentsChk.checked,
            exploreMainDomain: exploreMainDomainChk.checked,
            processJavaScript: processJsChk.checked,
            filesToExploreAtOnce: App.settings.grabberFilesToExploreAtOnce,
            filesToDownloadAtOnce: App.settings.grabberFilesToDownloadAtOnce,
            useLinkTextAsDescription: App.settings.grabberUseLinkTextAsDescription,
            exploreIncludePatterns: includeExploreChk.checked ? splitLines(exploreIncludeField.text) : [],
            exploreExcludePatterns: excludeExploreChk.checked ? splitLines(exploreExcludeField.text) : [],
            fileIncludePatterns: splitLines(fileIncludeField.text),
            fileExcludePatterns: splitLines(fileExcludeField.text),
            filePathIncludePatterns: includeFilePathChk.checked ? splitLines(filePathIncludeField.text) : [],
            filePathExcludePatterns: excludeFilePathChk.checked ? splitLines(filePathExcludeField.text) : [],
            searchFilesOnThisSiteOnly: searchThisSiteOnlyChk.checked,
            hideDuplicateFiles: hideDuplicateChk.checked,
            startDownloadingImmediately: startNowChk.checked,
            minSizeBytes: minSizeEnabled.checked ? Math.max(-1, Number(minSizeField.text || "0")) : -1,
            maxSizeBytes: maxSizeEnabled.checked ? Math.max(-1, Number(maxSizeField.text || "0")) : -1,
            comment: commentField.text
        }
    }

    function loadProject(project) {
        root.projectId = project.id || ""
        stepIndex = 0
        projectNameField.text = project.name || ""
        startUrlField.text = project.startUrl || ""
        useAuthorizationChk.checked = (project.username || "").length > 0 || (project.password || "").length > 0
        usernameField.text = project.username || ""
        passwordField.text = project.password || ""
        manualLoginChk.checked = (project.loginUrl || "").length > 0
        loginUrlField.text = project.loginUrl || ""
        dontOpenLogoutChk.checked = (project.logoutPatterns || []).length > 0
        logoutField.text = (project.logoutPatterns || []).join("\n")
        selectedTemplateProjectId = project.isTemplate ? (project.id || "") : ""
        var options = templateOptions()
        var templateIndex = 0
        if (selectedTemplateProjectId.length > 0) {
            for (var i = 0; i < options.length; ++i) {
                if (options[i].templateId === selectedTemplateProjectId) {
                    templateIndex = i
                    break
                }
            }
        } else {
            templateIndex = Math.max(0, templateValues.indexOf(project.templateId || "custom"))
        }
        templateCombo.model = options
        templateCombo.currentIndex = templateIndex
        saveModeCombo.currentIndex = Math.max(0, saveModeValues.indexOf(project.saveMode || "byCategory"))
        saveCategoryCombo.currentIndex = Math.max(0, categoryIds().indexOf(project.selectedCategoryId || "all"))
        savePathField.text = project.savePath || App.settings.defaultSavePath
        useRelativeFolders.checked = !!project.useRelativeSubfolders
        convertLinksChk.checked = !!project.convertLinksToLocal
        overwriteExistingChk.checked = !!project.overwriteExistingFiles
        addCheckedFilesChk.checked = !!project.addCheckedFilesToIdm
        exploreWholeSiteRadio.checked = !!project.exploreWholeSite
        exploreLevelsRadio.checked = !exploreWholeSiteRadio.checked
        thisSiteSpin.value = project.exploreThisLevels !== undefined ? project.exploreThisLevels : 2
        otherSitesSpin.value = project.exploreOtherLevels !== undefined ? project.exploreOtherLevels : 0
        ignorePopupChk.checked = project.ignorePopupWindows !== undefined ? project.ignorePopupWindows : true
        dontExploreParentsChk.checked = !!project.dontExploreParentDirectories
        exploreMainDomainChk.checked = !!project.exploreMainDomain
        processJsChk.checked = !!project.processJavaScript
        includeExploreChk.checked = (project.exploreIncludePatterns || []).length > 0
        excludeExploreChk.checked = (project.exploreExcludePatterns || []).length > 0
        exploreIncludeField.text = (project.exploreIncludePatterns || []).join("\n")
        exploreExcludeField.text = (project.exploreExcludePatterns || []).join("\n")
        fileIncludeField.text = (project.fileIncludePatterns || []).join("\n")
        fileExcludeField.text = (project.fileExcludePatterns || []).join("\n")
        includeFilePathChk.checked = (project.filePathIncludePatterns || []).length > 0
        excludeFilePathChk.checked = (project.filePathExcludePatterns || []).length > 0
        filePathIncludeField.text = (project.filePathIncludePatterns || []).join("\n")
        filePathExcludeField.text = (project.filePathExcludePatterns || []).join("\n")
        searchThisSiteOnlyChk.checked = !!project.searchFilesOnThisSiteOnly
        hideDuplicateChk.checked = project.hideDuplicateFiles !== undefined ? !!project.hideDuplicateFiles : true
        startNowChk.checked = !!project.startDownloadingImmediately
        minSizeEnabled.checked = project.minSizeBytes > 0
        maxSizeEnabled.checked = project.maxSizeBytes > 0
        minSizeField.text = project.minSizeBytes > 0 ? String(project.minSizeBytes) : "1"
        maxSizeField.text = project.maxSizeBytes > 0 ? String(project.maxSizeBytes) : "10"
        commentField.text = project.comment || ""
        errorLabel.text = project.statusText || ""
    }

    function saveProjectOnly() {
        var map = projectMap()
        if (map.name.length === 0 || map.startUrl.length === 0) {
            errorLabel.text = qsTr("Project name and start page are required.")
            return false
        }
        root.projectId = App.saveGrabberProject(map)
        errorLabel.text = qsTr("Project saved.")
        return true
    }

    function runProject() {
        var map = projectMap()
        if (map.name.length === 0 || map.startUrl.length === 0) {
            errorLabel.text = qsTr("Project name and start page are required.")
            return
        }
        root.projectId = App.saveGrabberProject(map)
        map.id = root.projectId
        App.runGrabber(map)
        root.close()
        root.resultsRequested(root.projectId)
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

    Component.onCompleted: {
        App.setWindowIcon(root, ":/qt/qml/com/stellar/app/app/qml/icons/grabber.svg")
        refreshRecentProjects()
        loadProject(root.projectId.length > 0
            ? App.grabberProjectData(root.projectId)
            : { savePath: App.settings.defaultSavePath, ignorePopupWindows: true, exploreThisLevels: 2, hideDuplicateFiles: true })
    }

    onVisibleChanged: {
        if (visible) {
            _centerOnOwner()
            refreshRecentProjects()
            loadProject(root.projectId.length > 0
                ? App.grabberProjectData(root.projectId)
                : { savePath: App.settings.defaultSavePath, ignorePopupWindows: true, exploreThisLevels: 2, hideDuplicateFiles: true })
        }
    }

    Connections {
        target: App
        function onGrabberExploreFinished(projectId) {
            if (!root.visible)
                return
            if (projectId !== root.projectId)
                return
            var project = App.grabberProjectData(projectId)
            if (project.startDownloadingImmediately) {
                App.downloadGrabberResults(projectId, true)
                root.close()
                return
            }
            root.close()
            root.resultsRequested(projectId)
        }
        function onGrabberError(message) { errorLabel.text = message }
    }

    Connections {
        target: App.grabberProjectModel
        function onRowsInserted() { root.refreshRecentProjects() }
        function onRowsRemoved() { root.refreshRecentProjects() }
        function onModelReset() { root.refreshRecentProjects() }
        function onDataChanged() { root.refreshRecentProjects() }
    }

    GrabberProjectPickerDialog {
        id: projectPickerDialog
        onAccepted: (projectId) => loadProjectById(projectId)
    }

    GrabberSettingsDialog { id: grabberSettingsDialog }
    GrabberIncludeFiltersDialog {
        id: includeFiltersDialog
        dialogTitle: qsTr("Include filters")
        builtInFilters: root.builtInIncludeFilters
        customFiltersJson: App.settings.grabberIncludeFiltersJson
        categoryEnabled: true
        categoryIdOptions: root.categoryIds()
        categoryLabelOptions: root.categoryLabels()
        onFilterChosen: (mask, categoryId) => root.applyIncludeFilter(mask, categoryId)
        onCustomFiltersSaved: (json) => {
            App.settings.grabberIncludeFiltersJson = json
            includeFilterCombo.model = root.filterLabels(root.includeFilterRows())
        }
    }
    GrabberIncludeFiltersDialog {
        id: excludeFiltersDialog
        dialogTitle: qsTr("Exclude filters")
        builtInFilters: root.builtInExcludeFilters
        customFiltersJson: App.settings.grabberExcludeFiltersJson
        categoryEnabled: false
        categoryIdOptions: []
        categoryLabelOptions: []
        onFilterChosen: (mask) => root.applyExcludeFilter(mask)
        onCustomFiltersSaved: (json) => {
            App.settings.grabberExcludeFiltersJson = json
            excludeFilterCombo.model = root.filterLabels(root.excludeFilterRows())
        }
    }

    Popup {
        id: saveTemplatePopup
        modal: true
        focus: true
        width: 360
        height: 150
        x: (root.width - width) / 2
        y: (root.height - height) / 2
        background: Rectangle { color: ColorPalette.cardBg; border.color: ColorPalette.border; radius: 0 }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 12
            spacing: 10
            Text { text: qsTr("Template name"); color: ColorPalette.textPrimary; font.pixelSize: 14 * App.fontScale; font.bold: true }
            WizardTextField { id: templateNameField; Layout.fillWidth: true }
            RowLayout {
                Layout.fillWidth: true
                Item { Layout.fillWidth: true }
                DlgButton { text: qsTr("Cancel"); onClicked: saveTemplatePopup.close() }
                DlgButton {
                    text: qsTr("Save")
                    primary: true
                    onClicked: {
                        var map = projectMap()
                        map.id = ""
                        map.isTemplate = true
                        map.name = templateNameField.text.trim().length > 0 ? templateNameField.text.trim() : "Template"
                        App.saveGrabberProject(map)
                        templateCombo.model = templateOptions()
                        saveTemplatePopup.close()
                    }
                }
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        color: ColorPalette.cardBg

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 0
            spacing: 0

            // Menu bar - real MenuBar (not ApplicationWindow, but works standalone)
            MenuBar {
                Layout.fillWidth: true

                background: Rectangle {
                    color: ColorPalette.panelBg
                    Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: ColorPalette.border }
                }

                component CompactMenuItem: MenuItem {
                    id: _cmi
                    implicitHeight: 22; height: 22
                    topPadding: 0; bottomPadding: 0; verticalPadding: 0
                    leftPadding: 8; rightPadding: 12; spacing: 0
                    font.pixelSize: 12 * App.fontScale
                    indicator: Item {
                        width: _cmi.checkable ? 16 : 0; height: _cmi.checkable ? 16 : 0
                        Text {
                            text: "✓"; visible: _cmi.checkable && _cmi.checked
                            color: "#4488dd"; font.pixelSize: 12 * App.fontScale
                            anchors.centerIn: parent
                        }
                    }
                    arrow: Text {
                        x: _cmi.width - width - 8
                        anchors.verticalCenter: parent ? parent.verticalCenter : undefined
                        text: "▾"; font.pixelSize: 8 * App.fontScale; color: ColorPalette.textMuted
                        visible: _cmi.subMenu !== null
                    }
                    contentItem: RowLayout {
                        spacing: 6
                        anchors.verticalCenter: parent ? parent.verticalCenter : undefined
                        Item { Layout.preferredWidth: 0; Layout.preferredHeight: 14 }
                        Text {
                            text: _cmi.text; font: _cmi.font
                            color: _cmi.enabled ? ColorPalette.textPrimary : ColorPalette.textDisabled
                            verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight
                            Layout.fillWidth: true
                        }
                    }
                    background: Rectangle {
                        implicitHeight: 22
                        color: _cmi.highlighted ? ColorPalette.selectionBg : "transparent"
                    }
                }

                delegate: MenuBarItem {
                    verticalPadding: 0; leftPadding: 12; rightPadding: 12
                    contentItem: Text {
                        text: parent.text; font: parent.font
                        color: ColorPalette.textPrimary; verticalAlignment: Text.AlignVCenter
                    }
                    background: Rectangle {
                        implicitHeight: 20
                        color: parent.highlighted ? ColorPalette.selectionBg : "transparent"
                    }
                }

                Menu {
                    title: qsTr("Project")
                    delegate: CompactMenuItem
                    implicitWidth: 240; padding: 0
                    CompactMenuItem { text: qsTr("New");  onTriggered: { root.projectId = ""; loadProject({ savePath: App.settings.defaultSavePath, ignorePopupWindows: true, exploreThisLevels: 2, hideDuplicateFiles: true }) } }
                    CompactMenuItem { text: qsTr("Load"); onTriggered: { projectPickerDialog.selectedProjectId = ""; projectPickerDialog.show(); projectPickerDialog.raise() } }
                    CompactMenuItem { text: qsTr("Save"); onTriggered: saveProjectOnly() }
                    CompactMenuItem { text: qsTr("Save current settings as a template"); onTriggered: saveTemplatePopup.open() }
                    MenuSeparator {}
                    CompactMenuItem {
                        id: _recentProjectsItem
                        text: qsTr("Recent Projects") + "  ▶"
                        onTriggered: _recentProjectsMenu.popup(_recentProjectsItem.width, 0)
                        onHoveredChanged: {
                            if (hovered) _recentProjectsMenu.popup(_recentProjectsItem.width, 0)
                            else _recentProjectsCloseTimer.restart()
                        }
                        Menu {
                            id: _recentProjectsMenu
                            delegate: CompactMenuItem
                            implicitWidth: 220; padding: 0
                            onAboutToHide: _recentProjectsCloseTimer.stop()
                            Instantiator {
                                model: root.recentProjectRows
                                delegate: CompactMenuItem {
                                    text: modelData.name || "Project"
                                    onTriggered: loadProjectById(modelData.id)
                                }
                                onObjectAdded:   function(index, object) { _recentProjectsMenu.insertItem(index, object) }
                                onObjectRemoved: function(index, object) { _recentProjectsMenu.removeItem(object) }
                            }
                        }
                        Timer { id: _recentProjectsCloseTimer; interval: 300; onTriggered: { if (!_recentProjectsMenu.activeFocus) _recentProjectsMenu.close() } }
                    }
                    MenuSeparator {}
                    CompactMenuItem { text: qsTr("Close"); onTriggered: root.close() }
                }
                Menu {
                    title: qsTr("Options")
                    delegate: CompactMenuItem
                    implicitWidth: 200; padding: 0
                    CompactMenuItem { text: qsTr("Grabber settings"); onTriggered: { grabberSettingsDialog.show(); grabberSettingsDialog.raise() } }
                }

            }

            // Step header - icon + title + breadcrumb pill
            Rectangle {
                Layout.fillWidth: true
                height: 46
                color: ColorPalette.rowAltBg

                Rectangle {
                    anchors.bottom: parent.bottom
                    width: parent.width; height: 1
                    color: ColorPalette.border
                }

                Row {
                    anchors { verticalCenter: parent.verticalCenter; left: parent.left; leftMargin: 14 }
                    spacing: 10

                    Image {
                        source: "icons/grabber.svg"
                        width: 20; height: 20
                        sourceSize: Qt.size(20, 20)
                        fillMode: Image.PreserveAspectFit
                        smooth: true
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Text {
                        text: stepTitles[stepIndex]
                        color: ColorPalette.textPrimary
                        font.pixelSize: 14 * App.fontScale
                        font.bold: true
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                // Step breadcrumb - right side
                Row {
                    anchors { verticalCenter: parent.verticalCenter; right: parent.right; rightMargin: 14 }
                    spacing: 4

                    Repeater {
                        model: stepTitles.length
                        delegate: Row {
                            spacing: 4
                            anchors.verticalCenter: parent.verticalCenter

                            // Chevron separator (not before first)
                            Text {
                                visible: index > 0
                                text: ">"
                                color: ColorPalette.textDisabled
                                font.pixelSize: 14 * App.fontScale
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            Rectangle {
                                width: stepPillText.implicitWidth + 14
                                height: 20
                                radius: 10
                                color: index === stepIndex ? ColorPalette.selectionBg : "transparent"
                                border.color: index === stepIndex ? "#4488dd" : (index < stepIndex ? "#336622" : ColorPalette.border)
                                border.width: 1
                                anchors.verticalCenter: parent.verticalCenter

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: stepIndex = index
                                }

                                Text {
                                    id: stepPillText
                                    anchors.centerIn: parent
                                    text: (index + 1) + ""
                                    color: index === stepIndex ? ColorPalette.accent
                                         : index < stepIndex  ? "#66aa44"
                                         : ColorPalette.textSecond
                                    font.pixelSize: 11 * App.fontScale
                                    font.bold: index === stepIndex
                                }
                            }
                        }
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 0
                Layout.bottomMargin: 0

                Rectangle {
                    Layout.preferredWidth: 160
                    Layout.fillHeight: true
                    color: ColorPalette.panelBg

                    Column {
                        anchors.fill: parent
                        anchors.topMargin: 8
                        spacing: 0

                        Repeater {
                            model: stepTitles
                            delegate: Rectangle {
                                width: parent.width
                                height: 36
                                color: index === stepIndex ? ColorPalette.selectionBg : (ma.containsMouse ? ColorPalette.hoverBg : "transparent")
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    anchors.left: parent.left
                                    anchors.leftMargin: 16
                                    text: (index + 1) + ". " + modelData
                                    color: index === stepIndex ? "#ffffff" : ColorPalette.textPrimary
                                    font.pixelSize: 13 * App.fontScale
                                    font.bold: index === stepIndex
                                }
                                MouseArea {
                                    id: ma
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    onClicked: stepIndex = index
                                }
                            }
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    color: ColorPalette.cardBg

                    StackLayout {
                        anchors.fill: parent
                        anchors.margins: 16
                        currentIndex: stepIndex

                        ScrollView {
                            id: stepOneScroll
                            clip: true
                            ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
                            ColumnLayout {
                                width: Math.min(stepOneContentWidth, Math.max(0, stepOneScroll.availableWidth - 8))
                                spacing: 10

                                StepLabel { text: qsTr("Grabber Project Name"); font.bold: true }
                                WizardTextField { id: projectNameField; Layout.fillWidth: true }

                                StepLabel { text: qsTr("Start page/address"); font.bold: true }
                                WizardTextField {
                                    id: startUrlField
                                    Layout.fillWidth: true
                                }

                                StepLabel { text: qsTr("Project template"); font.bold: true }
                                WizardCombo {
                                    id: templateCombo
                                    Layout.fillWidth: true
                                    model: templateOptions()
                                    textRole: "text"
                                    valueRole: "value"
                                    onActivated: {
                                        var row = templateCombo.model[currentIndex]
                                        if (row && row.templateId && row.templateId.length > 0)
                                            loadProjectById(row.templateId)
                                        else
                                            applyTemplate(templateValues[currentIndex] || "custom")
                                    }
                                }

                                HintText {
                                    Layout.fillWidth: true
                                    text: qsTr("If you select a project template, the wizard will make the required project settings for the selected template on the next steps. You may always change the settings manually.")
                                }

                                Rectangle { Layout.fillWidth: true; height: 1; color: ColorPalette.border }

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 10
                                    WizardCheckBox { id: useAuthorizationChk; text: qsTr("Use authorization") }
                                    Item { Layout.fillWidth: true }
                                    DlgButton {
                                        text: startAdvancedVisible ? qsTr("Advanced <<") : qsTr("Advanced >>")
                                        implicitWidth: 124
                                        onClicked: startAdvancedVisible = !startAdvancedVisible
                                    }
                                }

                                GridLayout {
                                    Layout.fillWidth: true
                                    columns: 2
                                    Layout.columnSpan: 2
                                    columnSpacing: 12
                                    rowSpacing: 8

                                    StepLabel { text: qsTr("Login") }
                                    WizardTextField {
                                        id: usernameField
                                        Layout.fillWidth: true
                                        enabled: useAuthorizationChk.checked
                                    }

                                    StepLabel { text: qsTr("Password") }
                                    WizardTextField {
                                        id: passwordField
                                        Layout.fillWidth: true
                                        enabled: useAuthorizationChk.checked
                                        echoMode: TextInput.Password
                                    }
                                }

                                HintText {
                                    Layout.fillWidth: true
                                    text: qsTr("Press Advanced to enable manual login or to disable a logout page.")
                                }

                                Rectangle { Layout.fillWidth: true; height: 1; color: ColorPalette.border }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    visible: startAdvancedVisible
                                    spacing: 10

                                    WizardCheckBox {
                                        id: manualLoginChk
                                        text: qsTr("Enter login and password manually at the following web page:")
                                    }
                                    WizardTextField {
                                        id: loginUrlField
                                        Layout.fillWidth: true
                                        enabled: manualLoginChk.checked
                                    }

                                    WizardCheckBox {
                                        id: dontOpenLogoutChk
                                        text: qsTr("Don't open the logout page:")
                                    }
                                    WizardTextArea {
                                        id: logoutField
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: 88
                                        enabled: dontOpenLogoutChk.checked
                                    }

                                    HintText {
                                        Layout.fillWidth: true
                                        text: qsTr("Many sites have a logout page that the Grabber should not open. You may use an asterisk wildcard here to specify a pattern for different logout pages.")
                                    }
                                }
                            }
                        }

                        ScrollView {
                            id: stepTwoScroll
                            clip: true
                            ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
                            ColumnLayout {
                                width: Math.min(laterStepContentWidth, Math.max(0, stepTwoScroll.availableWidth - 8))
                                spacing: 10

                                StepLabel { text: qsTr("Save To"); font.bold: true }
                                WizardRadioButton {
                                    id: saveByCategoryRadio
                                    checked: saveModeCombo.currentIndex === 0
                                    text: qsTr("Every file to a folder according to Stellar category of the file")
                                    onClicked: saveModeCombo.currentIndex = 0
                                }
                                WizardRadioButton {
                                    id: saveSelectedCategoryRadio
                                    checked: saveModeCombo.currentIndex === 1
                                    text: qsTr("All files to the folder associated with the following Stellar category:")
                                    onClicked: saveModeCombo.currentIndex = 1
                                }
                                WizardCombo {
                                    id: saveCategoryCombo
                                    Layout.fillWidth: true
                                    Layout.leftMargin: 24
                                    model: categoryLabels()
                                    enabled: saveSelectedCategoryRadio.checked
                                }
                                WizardRadioButton {
                                    id: saveSpecificFolderRadio
                                    checked: saveModeCombo.currentIndex === 2
                                    text: qsTr("All files to the following folder")
                                    onClicked: saveModeCombo.currentIndex = 2
                                }
                                WizardTextField {
                                    id: savePathField
                                    Layout.fillWidth: true
                                    Layout.leftMargin: 24
                                    enabled: saveSpecificFolderRadio.checked
                                }
                                WizardCheckBox {
                                    id: useRelativeFolders
                                    Layout.leftMargin: 24
                                    text: qsTr("Use original relative subfolders")
                                    enabled: saveSpecificFolderRadio.checked || saveSelectedCategoryRadio.checked
                                }

                                WizardCombo {
                                    id: saveModeCombo
                                    visible: false
                                    model: [
                                        { text: qsTr("Save Each File By Category"), value: "byCategory" },
                                        { text: qsTr("Save All Files To Selected Category"), value: "selectedCategory" },
                                        { text: qsTr("Save All Files To This Folder"), value: "directory" }
                                    ]
                                }

                                WizardCheckBox { id: convertLinksChk; text: qsTr("Convert the links in downloaded html files to local files for offline browsing") }
                                WizardCheckBox { id: overwriteExistingChk; text: qsTr("Overwrite existing files") }
                                WizardCheckBox { id: addCheckedFilesChk; text: qsTr("Add checked files to Stellar main list and download queue on closing the grabber") }
                            }
                        }

                        ScrollView {
                            id: stepThreeScroll
                            clip: true
                            ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
                            ColumnLayout {
                                width: Math.min(laterStepContentWidth, Math.max(0, stepThreeScroll.availableWidth - 8))
                                spacing: 10

                                HintText {
                                    Layout.fillWidth: true
                                    text: qsTr("At this step you should specify what web pages to explore to find the required files. At the next step, you will be able to set file types, location, and other filters.")
                                }

                                WizardRadioButton {
                                    id: exploreWholeSiteRadio
                                    text: qsTr("Explore the whole site")
                                    ButtonGroup.group: exploreModeGroup
                                }
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 6
                                    WizardRadioButton {
                                        id: exploreLevelsRadio
                                        text: qsTr("Explore the specified number of link levels:")
                                        ButtonGroup.group: exploreModeGroup
                                        checked: !exploreWholeSiteRadio.checked
                                        onClicked: exploreWholeSiteRadio.checked = false
                                    }
                                    GridLayout {
                                        Layout.leftMargin: 24
                                        Layout.fillWidth: true
                                        columns: 1
                                        columnSpacing: 0
                                        rowSpacing: 6

                                        RowLayout {
                                            spacing: 8
                                            SpinBox { id: thisSiteSpin; from: 0; to: 20; value: 2; editable: true; enabled: exploreLevelsRadio.checked }
                                            Text {
                                                text: qsTr("levels within the base site")
                                                color: ColorPalette.textPrimary
                                                font.pixelSize: 12 * App.fontScale
                                                wrapMode: Text.WordWrap
                                                Layout.preferredWidth: 140
                                            }
                                        }
                                        RowLayout {
                                            spacing: 8
                                            SpinBox { id: otherSitesSpin; from: 0; to: 20; value: 0; editable: true; enabled: exploreLevelsRadio.checked }
                                            Text {
                                                text: qsTr("levels on other sites")
                                                color: ColorPalette.textPrimary
                                                font.pixelSize: 12 * App.fontScale
                                                wrapMode: Text.WordWrap
                                                Layout.preferredWidth: 180
                                            }
                                        }
                                    }
                                }

                                Text { text: qsTr("What is the number of link levels?"); color: ColorPalette.textSecond; font.pixelSize: 12 * App.fontScale }
                                WizardCheckBox { id: ignorePopupChk; text: qsTr("Ignore popup windows"); checked: true }
                                WizardCheckBox { id: dontExploreParentsChk; text: qsTr("Don't explore parent directories") }
                                WizardCheckBox { id: exploreMainDomainChk; text: qsTr("Explore all sites within the main domain") }
                                WizardCheckBox { id: processJsChk; text: qsTr("Process JavaScript") }
                                DlgButton {
                                    text: explorerAdvancedVisible ? qsTr("Advanced <<") : qsTr("Advanced >>")
                                    implicitWidth: 124
                                    onClicked: explorerAdvancedVisible = !explorerAdvancedVisible
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    visible: explorerAdvancedVisible
                                    spacing: 8
                                    WizardCheckBox { id: includeExploreChk; text: qsTr("Explore web pages within the following paths/domains only:") }
                                    HintText {
                                        Layout.fillWidth: true
                                        text: qsTr("Enter one path or domain per line, or separate entries with semicolons. Use * as a wildcard. Examples: *.google.com ; cdn.example.com ; /images/* ; /gallery")
                                    }
                                    WizardTextArea {
                                        id: exploreIncludeField
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: 92
                                        enabled: includeExploreChk.checked
                                    }
                                    WizardCheckBox { id: excludeExploreChk; text: qsTr("Don't explore web pages within the following paths/domains:") }
                                    HintText {
                                        Layout.fillWidth: true
                                        text: qsTr("Enter one path or domain per line, or separate entries with semicolons. Use * as a wildcard. Examples: *.doubleclick.net ; tracking.example.com ; /ads/* ; /private")
                                    }
                                    WizardTextArea {
                                        id: exploreExcludeField
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: 92
                                        enabled: excludeExploreChk.checked
                                    }
                                }
                            }
                        }

                        ScrollView {
                            id: stepFourScroll
                            clip: true
                            ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
                            ColumnLayout {
                                width: Math.min(laterStepContentWidth, Math.max(0, stepFourScroll.availableWidth - 8))
                                spacing: 10

                                StepLabel { text: qsTr("Download the following files (file types)"); font.bold: true }
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 8
                                    ComboBox {
                                        id: includeFilterCombo
                                        Layout.fillWidth: true
                                        model: root.filterLabels(root.includeFilterRows())
                                        onActivated: {
                                            var row = root.includeFilterRows()[currentIndex]
                                            if (row)
                                                root.applyIncludeFilter(row.mask || "", row.categoryId || "")
                                        }
                                        background: FieldBox {}
                                        contentItem: Text {
                                            leftPadding: 8
                                            rightPadding: 24
                                            text: parent.displayText
                                            color: ColorPalette.textPrimary
                                            font: parent.font
                                            verticalAlignment: Text.AlignVCenter
                                            elide: Text.ElideRight
                                        }
                                    }
                                    DlgButton {
                                        text: qsTr("Include Filters...")
                                        onClicked: {
                                            includeFiltersDialog.show()
                                            includeFiltersDialog.raise()
                                            includeFiltersDialog.requestActivate()
                                        }
                                    }
                                }
                                WizardTextArea {
                                    id: fileIncludeField
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 88
                                }

                                StepLabel { text: qsTr("Don't download the following files (file types)"); font.bold: true }
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 8
                                    ComboBox {
                                        id: excludeFilterCombo
                                        Layout.fillWidth: true
                                        model: root.filterLabels(root.excludeFilterRows())
                                        onActivated: {
                                            var row = root.excludeFilterRows()[currentIndex]
                                            if (row)
                                                root.applyExcludeFilter(row.mask || "")
                                        }
                                        background: FieldBox {}
                                        contentItem: Text {
                                            leftPadding: 8
                                            rightPadding: 24
                                            text: parent.displayText
                                            color: ColorPalette.textPrimary
                                            font: parent.font
                                            verticalAlignment: Text.AlignVCenter
                                            elide: Text.ElideRight
                                        }
                                    }
                                    DlgButton {
                                        text: qsTr("Exclude Filters...")
                                        onClicked: {
                                            excludeFiltersDialog.show()
                                            excludeFiltersDialog.raise()
                                            excludeFiltersDialog.requestActivate()
                                        }
                                    }
                                }
                                WizardTextArea {
                                    id: fileExcludeField
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 72
                                }

                                WizardCheckBox { id: searchThisSiteOnlyChk; text: qsTr("Search files on this site only") }
                                WizardCheckBox { id: hideDuplicateChk; text: qsTr("Hide duplicate files found in different locations"); checked: true }
                                WizardCheckBox { id: startNowChk; text: qsTr("Start downloading all matched files at once") }

                                DlgButton {
                                    text: fileAdvancedVisible ? qsTr("Advanced <<") : qsTr("Advanced >>")
                                    implicitWidth: 124
                                    onClicked: fileAdvancedVisible = !fileAdvancedVisible
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    visible: fileAdvancedVisible
                                    spacing: 10

                                    StepLabel { text: qsTr("Download if file size is"); font.bold: true }
                                    RowLayout {
                                        spacing: 8
                                        WizardCheckBox { id: minSizeEnabled; text: qsTr("Not less than") }
                                        WizardTextField { id: minSizeField; Layout.preferredWidth: 76; enabled: minSizeEnabled.checked; text: "1" }
                                        StepLabel { text: qsTr("Bytes") }
                                    }
                                    RowLayout {
                                        spacing: 8
                                        WizardCheckBox { id: maxSizeEnabled; text: qsTr("Not more than") }
                                        WizardTextField { id: maxSizeField; Layout.preferredWidth: 76; enabled: maxSizeEnabled.checked; text: "10" }
                                        StepLabel { text: qsTr("Bytes") }
                                    }

                                    Rectangle { Layout.fillWidth: true; height: 1; color: ColorPalette.border }

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 8
                                        WizardCheckBox { id: includeFilePathChk; text: qsTr("Download the files located within the following paths/domains only:") }
                                        HintText {
                                            Layout.fillWidth: true
                                            text: qsTr("Use * as a wildcard. Enter one path or domain per line, or separate entries with semicolons. Examples: *.google.com ; cdn.example.com ; /downloads/*")
                                        }
                                        WizardTextArea {
                                            id: filePathIncludeField
                                            Layout.fillWidth: true
                                            Layout.preferredHeight: 86
                                            enabled: includeFilePathChk.checked
                                        }
                                        WizardCheckBox { id: excludeFilePathChk; text: qsTr("Don't download the files located within the following paths/domains:") }
                                        HintText {
                                            Layout.fillWidth: true
                                            text: qsTr("Use * as a wildcard. Enter one path or domain per line, or separate entries with semicolons. Examples: *.doubleclick.net ; /ads/* ; /tracking")
                                        }
                                        WizardTextArea {
                                            id: filePathExcludeField
                                            Layout.fillWidth: true
                                            Layout.preferredHeight: 86
                                            enabled: excludeFilePathChk.checked
                                        }
                                    }
                                }

                                StepLabel { text: qsTr("Comment"); font.bold: true }
                                WizardTextField { id: commentField; Layout.fillWidth: true }
                            }
                        }
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                height: 54
                color: ColorPalette.panelBg

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    anchors.topMargin: 0
                    anchors.bottomMargin: 0
                    spacing: 8

                    Text {
                        id: errorLabel
                        Layout.fillWidth: true
                        text: App.grabberStatusText
                        color: App.grabberBusy ? ColorPalette.textPrimary : ColorPalette.textPrimary
                        font.pixelSize: 11 * App.fontScale
                        elide: Text.ElideRight
                    }

                    ProgressBar {
                        Layout.preferredWidth: 180
                        Layout.alignment: Qt.AlignVCenter
                        visible: App.grabberBusy
                        indeterminate: true
                        from: 0
                        to: 1
                        value: 0.4
                    }

                    DlgButton {
                        text: qsTr("Save Project")
                        enabled: !App.grabberBusy
                        onClicked: saveProjectOnly()
                    }
                    DlgButton {
                        visible: root.projectId.length > 0
                        text: qsTr("Delete Project")
                        enabled: !App.grabberBusy
                        onClicked: {
                            App.deleteGrabberProject(root.projectId)
                            root.close()
                        }
                    }
                    DlgButton {
                        text: stepIndex > 0 ? qsTr("< Back") : qsTr("Close")
                        enabled: !App.grabberBusy
                        onClicked: {
                            if (stepIndex > 0)
                                stepIndex -= 1
                            else
                                root.close()
                        }
                    }
                    DlgButton {
                        text: stepIndex < 3 ? qsTr("Next >") : qsTr("Start Exploring")
                        primary: true
                        enabled: !App.grabberBusy
                        onClicked: {
                            if (stepIndex < 3) {
                                stepIndex += 1
                                return
                            }
                            runProject()
                        }
                    }
                }
            }
        }
    }
}

