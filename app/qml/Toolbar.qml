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

Rectangle {
    id: root
    height: App.settings.toolbarSmallButtons ? 48 : 72
    color: ColorPalette.toolbarBg

    property var queueModel: null
    property var downloadTable: null
    property var buttonDefs: []

    // Default toolbar button definitions
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

    // Canonical (translated) def for a key. Labels are never trusted from saved
    // JSON -- only the user's order/enabled state is persisted by key. A saved
    // English label baked into settings would otherwise bypass qsTr() forever.
    function _defForKey(key) {
        var defs = _defaultDefs()
        for (var i = 0; i < defs.length; ++i)
            if (defs[i].key === key) return defs[i]
        return null
    }

    // Merge persisted defs (order + enabled, by key) with fresh translated
    // label/icon. Shared by Toolbar and ToolbarDialog.
    function _rehydrateDefs(saved) {
        if (!saved || !saved.map) return _defaultDefs()
        return saved.map(function(s) {
            if (s.key === "separator") return {key:"separator"}
            var def = _defForKey(s.key)
            if (!def) return null  // unknown/removed key
            return {key: s.key, label: def.label, iconSrc: def.iconSrc,
                    enabled: s.enabled !== false}
        }).filter(function(d) { return d !== null })
    }

    function _loadButtonDefs() {
        if (App && App.settings && App.settings.toolbarButtonDefs) {
            try { return _rehydrateDefs(JSON.parse(App.settings.toolbarButtonDefs)) } catch(e) {}
        }
        return _defaultDefs()
    }

    // Compute visible items: filter to buttons with enabled !== false plus separators.
    // Also respects App.settings.showSearchEngine and showRssReader toggles from View menu.
    readonly property var _visibleDefs: {
        // Touch reactive dependencies so binding re-evaluates on change
        var _showSearch = App.settings ? App.settings.showSearchEngine : false
        var _showRss = App.settings ? App.settings.showRssReader : false
        if (!buttonDefs || !buttonDefs.filter) return []
        return buttonDefs.filter(function(d) {
            if (d.key === "search_engine" && !_showSearch) return false
            if (d.key === "rss" && !_showRss) return false
            // ── View menu toggle sufficient for search/rss bypass per-button enabled ──
            if (d.key === "search_engine" || d.key === "rss") return true
            return d.key === "separator" || d.enabled !== false
        })
    }

    // Reactive enabled-state helpers.
    // Bind directly to readonly properties on DownloadTable rather than calling
    // functions -- QML only re-evaluates an `enabled:` binding when a *property*
    // it accessed changes, not when a function's internal state changes.  The
    // anyPausedSelected / anyActiveSelected properties on DownloadTable emit
    // change signals (via _selectionVersion) and propagate correctly here.

    signal addClicked()
    signal resumeClicked()
    signal stopClicked()
    signal stopAllClicked()
    signal deleteClicked()
    signal deleteCompletedClicked()
    signal optionsClicked()
    signal schedulerClicked()
    signal startQueueRequested(string queueId)
    signal stopQueueRequested(string queueId)
    signal grabberClicked()
    signal searchEngineClicked()
    signal rssClicked()

    // Central dispatch for button clicks from the Repeater
    function _handleClick(key) {
        switch (key) {
            case "add":           root.addClicked(); break
            case "resume":        root.resumeClicked(); break
            case "stop":          root.stopClicked(); break
            case "stop_all":      root.stopAllClicked(); break
            case "delete":        root.deleteClicked(); break
            case "delete_done":   root.deleteCompletedClicked(); break
            case "options":       root.optionsClicked(); break
            case "scheduler":     root.schedulerClicked(); break
            case "grabber":       root.grabberClicked(); break
            case "search_engine": root.searchEngineClicked(); break
            case "rss":           root.rssClicked(); break
        }
    }

    function _handleQueueClick(key, queueId) {
        if (key === "start_queue") root.startQueueRequested(queueId)
        else root.stopQueueRequested(queueId)
    }

    // Dynamic enabled state for ToolbarBtn items
    function _btnEnabled(key) {
        switch (key) {
            case "resume":    return downloadTable ? (downloadTable.selectedItemStatus === "Paused" || downloadTable.selectedItemStatus === "Error") : false
            case "stop":      return downloadTable ? (downloadTable.selectedItemStatus === "Downloading" || downloadTable.selectedItemStatus === "Queued" || downloadTable.selectedItemStatus === "Seeding") : false
            case "stop_all":  return App.canPauseAll
            case "delete":    return downloadTable ? downloadTable.hasSelection : false
            default:          return true
        }
    }

    // bottom border
    Rectangle {
        anchors.bottom: parent.bottom
        width: parent.width
        height: 0
        color: ColorPalette.border
    }

    Row {
        anchors { fill: parent; leftMargin: 2 }
        spacing: 0

        Repeater {
            model: root._visibleDefs

            delegate: Item {
                readonly property bool _sm: App.settings.toolbarSmallButtons
                width: modelData.key === "separator" ? (_sm ? 10 : 16) : (_sm ? 48 : 84)
                height: _sm ? 48 : 72

                ToolbarBtn {
                    anchors.fill: parent
                    visible: modelData.key !== "separator"
                             && modelData.key !== "start_queue"
                             && modelData.key !== "stop_queue"
                    label: modelData.label || ""
                    iconSrc: modelData.iconSrc || ""
                    smallMode: _sm
                    enabled: root._btnEnabled(modelData.key)
                    onClicked: root._handleClick(modelData.key)
                }

                ToolbarDropdown {
                    anchors.fill: parent
                    visible: modelData.key === "start_queue" || modelData.key === "stop_queue"
                    label: modelData.label || ""
                    iconSrc: modelData.iconSrc || ""
                    smallMode: _sm
                    queueModel: root.queueModel
                    onQueueSelected: (queueId) => root._handleQueueClick(modelData.key, queueId)
                }

                // ── Separator vertical line centered in the 16px slot ────
                Rectangle {
                    anchors.centerIn: parent
                    width: 1; height: _sm ? 24 : 36
                    color: ColorPalette.border
                    visible: modelData.key === "separator"
                }
            }
        }
    }

    Component.onCompleted: {
        buttonDefs = _loadButtonDefs()
    }

    // Re-pull translated labels when UI language changes so a live switch
    // re-localises the toolbar without a customize round-trip.
    Connections {
        target: App.settings
        ignoreUnknownSignals: true
        function onUiLanguageChanged() { root.buttonDefs = root._loadButtonDefs() }
    }
}
