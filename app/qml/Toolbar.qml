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
    color: ColorPalette.toolbarBg

    // ── Toolbar vertical layout (single source of truth) ─────────────────────
    // The bar height adapts to the CURRENT language: if no visible label wraps it's
    // sized for 1 line; if any label wraps it's sized for 2 lines. Within a language
    // every button is then centred, icons all share one Y (_iconTop) so they stay
    // level, and there is no wasted whitespace. Pixels above the *visible* top of
    // the SVG icon == pixels below the bottom of the text.
    //
    //   _pad ......... equal whitespace above icon and below text
    //   _svgBuffer ... transparent margin baked into the 32x32 icon viewBox;
    //                  subtracted so the *visible* top gap equals _pad
    //   _iconGap ..... space between icon and label
    readonly property int _pad: 8
    readonly property int _svgBuffer: 2
    readonly property int _iconGap: 4
    readonly property int _iconSizePx: 32
    readonly property int _labelWidth: 84 - 4   // button width minus label side margin

    FontMetrics {
        id: _labelFM
        font.pixelSize: 11 * App.fontScale
    }

    // True if any currently-visible label is wider than one button -> needs 2 lines.
    // Use FontMetrics.advanceWidth(string) (a pure function) instead of mutating a
    // shared TextMetrics inside the binding — the latter writes a property it also
    // reads, which Qt flags as a binding loop.
    readonly property bool _anyTwoLine: {
        var defs = root._visibleDefs
        if (!defs)
            return false
        for (var i = 0; i < defs.length; ++i) {
            var d = defs[i]
            if (!d || d.key === "separator" || !d.label)
                continue
            if (_labelFM.advanceWidth(d.label) > root._labelWidth)
                return true
        }
        return false
    }

    readonly property int _lineCount: _anyTwoLine ? 2 : 1
    readonly property int _iconTop: Math.max(0, _pad - _svgBuffer)
    readonly property int _textTop: _iconTop + _iconSizePx + _iconGap
    readonly property int _computedBarH: _textTop + Math.ceil(_labelFM.height * _lineCount) + _pad

    height: App.settings.toolbarSmallButtons ? 48 : _computedBarH

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
    // Per-key enabled state stored as a readonly property so QML's binding
    // engine can track the dependencies.  When anyPausedSelected, canPauseAll,
    // etc. change, this entire map re-evaluates, and each ToolbarBtn's enabled
    // binding (which reads this map) follows.  A plain function call in a binding
    // expression prevents the engine from seeing the property accesses inside the
    // switch statement — the binding never re-evaluates.

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

    // Dynamic enabled-state map for ToolbarBtn items.
    // Keys: toolbar button key string. Values: boolean enabled state that QML's
    // binding engine can track because this is a property, not a function.
    readonly property var _btnEnabledMap: ({
        "resume":   downloadTable ? (downloadTable.anyPausedSelected || downloadTable.anyErrorSelected) : false,
        "stop":     downloadTable ? downloadTable.anyStoppableSelected : false,
        "stop_all": App.canPauseAll,
        "delete":   downloadTable ? downloadTable.hasSelection : false
    })

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
                height: root.height

                ToolbarBtn {
                    anchors.fill: parent
                    visible: modelData.key !== "separator"
                             && modelData.key !== "start_queue"
                             && modelData.key !== "stop_queue"
                    label: modelData.label || ""
                    iconSrc: modelData.iconSrc || ""
                    smallMode: _sm
                    iconTop: root._iconTop
                    textTop: root._textTop
                    enabled: { var m = root._btnEnabledMap; return (modelData.key in m) ? m[modelData.key] : true }
                    onClicked: root._handleClick(modelData.key)
                }

                ToolbarDropdown {
                    anchors.fill: parent
                    visible: modelData.key === "start_queue" || modelData.key === "stop_queue"
                    label: modelData.label || ""
                    iconSrc: modelData.iconSrc || ""
                    smallMode: _sm
                    iconTop: root._iconTop
                    textTop: root._textTop
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
