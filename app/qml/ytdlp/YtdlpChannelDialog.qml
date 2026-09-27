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

// Pick videos from a channel or playlist. The link is listed without
// downloading anything; each chosen video then becomes an ordinary download
// (pause, retry and delete work per video) in a queue named after the channel
// or playlist, saved in a folder of the same name.
YtdlpDialogFrame {
    id: root

    property string pendingUrl: ""

    signal openSettingsRequested(int page)
    // videos = [{ url, title }]
    signal videosRequested(var videos, string savePath, string category, string formatId,
                           string containerFormat, var extraOptions, string queueName)

    width: 640
    height: 600
    minimumWidth: 520
    minimumHeight: 480
    title: _isPlaylist ? qsTr("Playlist Download") : qsTr("Channel Download")
    heading: _collectionName.length > 0 ? _collectionName
             : _listing ? qsTr("Listing videos…") : pendingUrl
    subheading: pendingUrl
    // The count is shown above the list ("12 of 340 selected").
    primaryText: qsTr("Download selected")
    primaryEnabled: _listError.length === 0 && _checkedCount > 0 && output.savePath.length > 0

    // Listing everything can take minutes on a large channel, so the first
    // pass lists only the newest videos; "Load all" lists the rest.
    readonly property int kInitialLimit: 100

    readonly property bool _isPlaylist: App.ytdlpUrlKind(pendingUrl) === "playlist"
    readonly property bool _hasTabs: App.ytdlpHasChannelTabs(pendingUrl)
    readonly property var _tabKeys: ["videos", "shorts", "streams"]
    readonly property var _presets: App.ytdlpQualityPresets()
    readonly property var _preset: _presets[_qualityIndex] || _presets[0]

    property int    _tabIndex: 0
    property int    _limit: kInitialLimit
    property string _probeId: ""
    property bool   _listing: false
    property int    _found: 0
    property bool   _complete: true
    property bool   _hasDates: false
    property string _listError: ""
    property string _listTitle: ""
    property string _owner: ""
    property int    _checkedCount: 0
    property int    _anchorIndex: -1
    property int    _qualityIndex: 0

    // A playlist is named by its title, a channel by its owner; the site's
    // host when the listing names neither.
    readonly property string _collectionName: (_isPlaylist ? (_listTitle || _owner) : (_owner || _listTitle))
                                              || (_listing ? "" : _hostOf(pendingUrl))
    // Queue and folder name: the backend sanitises the queue name the same way.
    readonly property string _folderName: _collectionName.length > 0 ? App.safeFolderName(_collectionName) : ""

    YtdlpOptions { id: ytdlpOptions }

    // Rows: url, title, duration (s), uploadDate ("YYYYMMDD" or ""), alreadyAdded, checked.
    ListModel { id: videoModel }

    onVisibleChanged: {
        if (visible) {
            ytdlpOptions.reset()
            output.reset()
            tabs.currentIndex = 0
            _qualityIndex = 0
            _tabIndex = _tabIndexFromUrl(pendingUrl)
            _limit = kInitialLimit
            if (pendingUrl.length > 0)
                _startListing(false)
        } else {
            if (_probeId.length > 0)
                App.cancelYtdlpInfo(_probeId)
            _probeId = ""; _listing = false; _listError = ""
            _listTitle = ""; _owner = ""; _found = 0
            videoModel.clear()
            _checkedCount = 0; _anchorIndex = -1
            pendingUrl = ""
        }
    }
    onPendingUrlChanged: {
        if (visible && pendingUrl.length > 0) {
            _tabIndex = _tabIndexFromUrl(pendingUrl)
            _limit = kInitialLimit
            _startListing(false)
        }
    }

    onAccepted: {
        var videos = []
        for (var i = 0; i < videoModel.count; ++i) {
            var row = videoModel.get(i)
            if (row.checked)
                videos.push({ url: row.url, title: row.title })
        }
        videosRequested(videos, output.savePath, output.categoryId, _preset.id, output.container,
                        ytdlpOptions.buildExtraOptions(output.container, false), _folderName)
        close()
    }

    function _hostOf(url) {
        var m = /^[a-z][a-z0-9+.-]*:\/\/([^\/?#:]+)/i.exec(String(url).trim())
        return m ? m[1].replace(/^www\./i, "") : ""
    }

    function _tabIndexFromUrl(url) {
        var path = String(url).split(/[?#]/)[0].toLowerCase().replace(/\/+$/, "")
        if (path.endsWith("/shorts")) return 1
        if (path.endsWith("/streams") || path.endsWith("/live")) return 2
        return 0
    }

    // keepChecks: a relist of the same collection (Load all, Retry) keeps what
    // the user already ticked.
    function _startListing(keepChecks) {
        if (_probeId.length > 0)
            App.cancelYtdlpInfo(_probeId)
        var kept = null
        if (keepChecks && videoModel.count > 0) {
            kept = {}
            for (var i = 0; i < videoModel.count; ++i)
                kept[videoModel.get(i).url] = videoModel.get(i).checked
        } else {
            videoModel.clear()
            _checkedCount = 0
            _anchorIndex = -1
        }
        _keptChecks = kept
        _listError = ""
        _found = 0
        _listing = true
        var url = _hasTabs ? App.ytdlpChannelTabUrl(pendingUrl, _tabKeys[_tabIndex]) : pendingUrl
        _probeId = App.beginYtdlpListing(url, _limit, ytdlpOptions.cookiesBrowser)
    }
    // url -> checked for the rows shown before a relist, or null.
    property var _keptChecks: null

    function _setChecked(i, on) {
        if (videoModel.get(i).checked === on)
            return
        videoModel.setProperty(i, "checked", on)
        _checkedCount += on ? 1 : -1
    }

    function _selectAll(on) {
        for (var i = 0; i < videoModel.count; ++i)
            _setChecked(i, on)
    }

    // Selection helpers pick new videos only: ones already in the download
    // list stay unticked unless ticked by hand.
    function _selectFirst(n) {
        var picked = 0
        for (var i = 0; i < videoModel.count; ++i) {
            var take = picked < n && !videoModel.get(i).alreadyAdded
            _setChecked(i, take)
            if (take) ++picked
        }
    }

    function _selectSince(isoDate) {
        var since = isoDate.replace(/-/g, "")
        for (var i = 0; i < videoModel.count; ++i) {
            var row = videoModel.get(i)
            _setChecked(i, !row.alreadyAdded && row.uploadDate.length === 8 && row.uploadDate >= since)
        }
    }

    // Click toggles one row; shift-click applies that row's new state to the
    // whole range from the previous click.
    function _clickRow(i, shift) {
        var on = !videoModel.get(i).checked
        if (shift && _anchorIndex >= 0 && _anchorIndex < videoModel.count) {
            for (var j = Math.min(i, _anchorIndex); j <= Math.max(i, _anchorIndex); ++j)
                _setChecked(j, on)
        } else {
            _setChecked(i, on)
        }
        _anchorIndex = i
    }

    function _formatDuration(secs) {
        if (!secs || secs <= 0) return ""
        var h = Math.floor(secs / 3600), m = Math.floor(secs % 3600 / 60), s = secs % 60
        var mm = h > 0 && m < 10 ? "0" + m : String(m)
        return (h > 0 ? h + ":" : "") + mm + ":" + (s < 10 ? "0" + s : s)
    }

    function _formatDate(yyyymmdd) {
        return yyyymmdd.length === 8
            ? yyyymmdd.substring(0, 4) + "-" + yyyymmdd.substring(4, 6) + "-" + yyyymmdd.substring(6, 8)
            : ""
    }

    Connections {
        target: App
        function onYtdlpListingProgress(probeId, found) {
            if (probeId === root._probeId) root._found = found
        }
        function onYtdlpListingReady(probeId, url, title, owner, entries, complete) {
            if (probeId !== root._probeId) return
            root._probeId = ""
            root._listing = false
            root._listTitle = title
            root._owner = owner
            root._complete = complete
            var hasDates = false, checkedCount = 0
            var rows = []
            for (var i = 0; i < entries.length; ++i) {
                var e = entries[i]
                // Rows seen before keep their tick. New rows: a playlist is
                // usually wanted whole, a channel is picked from.
                var kept = root._keptChecks
                var on = kept && kept.hasOwnProperty(e.url) ? kept[e.url]
                                                           : root._isPlaylist && !e.alreadyAdded
                if (on) ++checkedCount
                if (e.uploadDate.length === 8) hasDates = true
                rows.push({ url: e.url, title: e.title, duration: e.duration, uploadDate: e.uploadDate,
                            alreadyAdded: e.alreadyAdded, checked: on })
            }
            videoModel.clear()
            videoModel.append(rows)
            root._checkedCount = checkedCount
            root._anchorIndex = -1
            root._hasDates = hasDates
            root._keptChecks = null
        }
        function onYtdlpInfoFailed(probeId, url, reason) {
            if (probeId !== root._probeId) return
            root._probeId = ""
            root._listing = false
            root._listError = reason
        }
    }

    Item {
        anchors.fill: parent

        YtdlpErrorPanel {
            anchors.fill: parent
            visible: root._listError.length > 0
            options: ytdlpOptions
            title: root._isPlaylist ? qsTr("Could not list this playlist") : qsTr("Could not list this channel")
            message: root._listError
            onRetry: root._startListing(true)
            onOpenSettingsRequested: (page) => root.openSettingsRequested(page)
        }

        ColumnLayout {
            anchors.fill: parent
            visible: root._listError.length === 0
            spacing: 0

            SettingsTabBar {
                id: tabs
                model: [qsTr("Videos"), qsTr("Download"), qsTr("Subtitles & extras"), qsTr("Advanced")]
            }

            StackLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                currentIndex: tabs.currentIndex

                // ── Videos ───────────────────────────────────────────────────
                ColumnLayout {
                    spacing: 8

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.topMargin: 12
                        Layout.leftMargin: 16
                        Layout.rightMargin: 16
                        spacing: 8

                        Text {
                            visible: root._hasTabs
                            text: qsTr("Show")
                            color: ColorPalette.textPrimary
                            font.pixelSize: 13 * App.fontScale
                        }
                        SettingsCombo {
                            visible: root._hasTabs
                            Layout.maximumWidth: 160
                            model: [qsTr("Videos"), qsTr("Shorts"), qsTr("Live streams")]
                            value: root._tabIndex
                            onEdited: (i) => {
                                if (i === root._tabIndex) return
                                root._tabIndex = i
                                root._limit = root.kInitialLimit
                                root._startListing(false)
                            }
                        }
                        Item { Layout.fillWidth: true }
                        Text {
                            text: qsTr("%1 of %2 selected").arg(root._checkedCount).arg(videoModel.count)
                            color: ColorPalette.textSecond
                            font.pixelSize: 12 * App.fontScale
                        }
                    }

                    // Selection helpers.
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.leftMargin: 16
                        Layout.rightMargin: 16
                        spacing: 8
                        enabled: videoModel.count > 0

                        StyledCheckBox {
                            Layout.fillWidth: false
                            leftPadding: 0
                            text: qsTr("All")
                            checked: videoModel.count > 0 && root._checkedCount === videoModel.count
                            onToggled: {
                                root._selectAll(checked)
                                checked = Qt.binding(function() {
                                    return videoModel.count > 0 && root._checkedCount === videoModel.count
                                })
                            }
                        }
                        Rectangle { implicitWidth: 1; implicitHeight: 18; color: ColorPalette.border }
                        Text {
                            text: root._isPlaylist ? qsTr("First") : qsTr("Latest")
                            color: ColorPalette.textPrimary
                            font.pixelSize: 13 * App.fontScale
                        }
                        SettingsNumber {
                            id: latestCount
                            // A fixed range: bound to the row count, the value would be
                            // clamped to 1 while the list is still loading.
                            from: 1
                            to: 99999
                            value: 10
                            onEdited: (v) => value = v
                        }
                        SettingsLink {
                            text: qsTr("Select")
                            onClicked: root._selectFirst(latestCount.value)
                        }
                        Rectangle {
                            visible: root._hasDates
                            implicitWidth: 1; implicitHeight: 18
                            color: ColorPalette.border
                        }
                        Text {
                            visible: root._hasDates
                            text: qsTr("Since")
                            color: ColorPalette.textPrimary
                            font.pixelSize: 13 * App.fontScale
                        }
                        SettingsTextField {
                            id: sinceField
                            visible: root._hasDates
                            Layout.fillWidth: false
                            implicitWidth: 100
                            placeholderText: "YYYY-MM-DD"
                            validator: RegularExpressionValidator { regularExpression: /\d{0,4}-?\d{0,2}-?\d{0,2}/ }
                            readonly property bool valid: /^\d{4}-?\d{2}-?\d{2}$/.test(text)
                        }
                        SettingsLink {
                            visible: root._hasDates
                            enabled: sinceField.valid
                            opacity: enabled ? 1 : 0.5
                            text: qsTr("Select")
                            onClicked: root._selectSince(sinceField.text)
                        }
                        Item { Layout.fillWidth: true }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.leftMargin: 16
                        Layout.rightMargin: 16
                        color: ColorPalette.inputBg
                        border.color: ColorPalette.border
                        radius: 3

                        ListView {
                            id: videoList
                            anchors { fill: parent; margins: 1 }
                            clip: true
                            model: videoModel
                            boundsBehavior: Flickable.StopAtBounds
                            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                            delegate: Rectangle {
                                id: videoRow
                                required property int index
                                required property string url
                                required property string title
                                required property int duration
                                required property string uploadDate
                                required property bool alreadyAdded
                                required property bool checked

                                width: ListView.view.width
                                height: 26
                                color: rowMouse.containsMouse ? ColorPalette.hoverBg
                                     : index % 2 ? ColorPalette.rowAltBg : "transparent"

                                RowLayout {
                                    anchors { fill: parent; leftMargin: 8; rightMargin: 12 }
                                    spacing: 8

                                    // Same box as StyledCheckBox; a real control per
                                    // row would cost far more on a long channel.
                                    Rectangle {
                                        implicitWidth: 16
                                        implicitHeight: 16
                                        radius: 3
                                        color: videoRow.checked ? ColorPalette.accent : ColorPalette.inputBg
                                        border.color: videoRow.checked ? ColorPalette.accent : ColorPalette.border
                                        Text {
                                            anchors.centerIn: parent
                                            visible: videoRow.checked
                                            text: "✓"
                                            color: "#ffffff"
                                            font.pixelSize: 11
                                            font.bold: true
                                        }
                                    }
                                    Text {
                                        // Takes only the width left over, so a long title
                                        // elides instead of pushing the columns out.
                                        Layout.fillWidth: true
                                        Layout.preferredWidth: 1
                                        text: videoRow.title.length > 0 ? videoRow.title : videoRow.url
                                        textFormat: Text.PlainText
                                        color: videoRow.alreadyAdded ? ColorPalette.textMuted : ColorPalette.textPrimary
                                        font.pixelSize: 12 * App.fontScale
                                        elide: Text.ElideRight
                                    }
                                    Text {
                                        visible: videoRow.alreadyAdded
                                        text: qsTr("In list")
                                        color: ColorPalette.textMuted
                                        font.pixelSize: 11 * App.fontScale
                                    }
                                    Text {
                                        visible: root._hasDates
                                        Layout.preferredWidth: 72
                                        horizontalAlignment: Text.AlignRight
                                        text: root._formatDate(videoRow.uploadDate)
                                        color: ColorPalette.textSecond
                                        font.pixelSize: 11 * App.fontScale
                                    }
                                    Text {
                                        Layout.preferredWidth: 52
                                        horizontalAlignment: Text.AlignRight
                                        text: root._formatDuration(videoRow.duration)
                                        color: ColorPalette.textSecond
                                        font.pixelSize: 11 * App.fontScale
                                    }
                                }

                                MouseArea {
                                    id: rowMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    onClicked: (mouse) => root._clickRow(videoRow.index, mouse.modifiers & Qt.ShiftModifier)
                                }
                            }
                        }

                        SettingsStatus {
                            anchors.centerIn: parent
                            width: Math.min(implicitWidth, parent.width - 32)
                            visible: videoModel.count === 0 && (root._listing || root._complete)
                            level: root._listing ? SettingsStatus.Level.Busy : SettingsStatus.Level.Error
                            text: root._listing ? root._listingText : qsTr("No videos found.")
                        }
                    }

                    // Listing progress / partial-list notice.
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.leftMargin: 16
                        Layout.rightMargin: 16
                        visible: (root._listing && videoModel.count > 0) || (!root._listing && !root._complete)
                        spacing: 8

                        SettingsHint {
                            Layout.fillWidth: false
                            text: root._listing ? root._listingText
                                                // Only shown for a list cut at its limit, so always plural.
                                                : qsTr("Showing the first %1 videos.").arg(videoModel.count)
                        }
                        SettingsLink {
                            visible: !root._listing
                            text: qsTr("Load all")
                            onClicked: {
                                root._limit = 0
                                root._startListing(true)
                            }
                        }
                        Item { Layout.fillWidth: true }
                    }

                    // What the chosen videos become, with a way to change it.
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.leftMargin: 16
                        Layout.rightMargin: 16
                        Layout.bottomMargin: 12
                        spacing: 8

                        Text {
                            Layout.fillWidth: true
                            text: root._preset.label + " · " + output.container + " · " + output.savePath
                            textFormat: Text.PlainText
                            color: ColorPalette.textSecond
                            font.pixelSize: 12 * App.fontScale
                            elide: Text.ElideMiddle
                        }
                        SettingsLink {
                            text: qsTr("Change…")
                            onClicked: tabs.currentIndex = 1
                        }
                    }
                }

                // ── Download ─────────────────────────────────────────────────
                SettingsScroll {
                    SettingsSection {
                        SettingsRow {
                            label: qsTr("Quality")
                            hint: qsTr("Videos below the chosen quality download at their best.")
                            SettingsCombo {
                                model: root._presets
                                textRole: "label"
                                value: root._qualityIndex
                                onEdited: (i) => root._qualityIndex = i
                            }
                        }

                        YtdlpOutputFields {
                            id: output
                            audioOnly: !!root._preset.audioOnly
                            subfolder: root._folderName
                        }
                    }

                    SettingsSection {
                        title: qsTr("Queue")
                        SettingsHint {
                            textFormat: Text.PlainText
                            text: root._folderName.length > 0
                                  ? qsTr("Each video becomes its own download in the queue “%1”, so it can be paused, retried or removed on its own.").arg(root._folderName)
                                  : qsTr("Each video becomes its own download in a queue named after the channel, so it can be paused, retried or removed on its own.")
                        }
                    }
                }

                YtdlpExtrasPage {
                    options: ytdlpOptions
                    container: output.container
                }

                YtdlpAdvancedPage {
                    options: ytdlpOptions
                    singleVideo: false
                }
            }
        }
    }

    readonly property string _listingText: _found > 0
        ? qsTr("Listing videos… %1 found").arg(_found)
        : qsTr("Listing videos…")
}
