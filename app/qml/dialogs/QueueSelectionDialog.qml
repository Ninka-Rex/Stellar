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
    title: qsTr("Queue Selection")
    width: 420
    height: 250
    minimumWidth: 380
    minimumHeight: 250
    color: ColorPalette.cardBg
    flags: Qt.Dialog | Qt.WindowTitleHint | Qt.WindowCloseButtonHint
    modality: Qt.ApplicationModal

    Material.theme: ColorPalette.materialTheme
    Material.foreground: ColorPalette.textPrimary
    Material.background: ColorPalette.materialBg
    Material.accent: "#4488dd"

    property var queueIds: []
    property var queueNames: []
    property string initialQueueId: ""
    property bool initialStartProcessing: false
    property bool initialAskAgain: false
    property string noteText: ""
    property string pendingContext: ""
    property string pendingGrabberProjectId: ""
    property var pendingBatchUrls: []
    property string pendingLaterDownloadId: ""
    property string pendingLaterUrl: ""
    property string pendingLaterSavePath: ""
    property string pendingLaterCategory: ""
    property string pendingLaterDesc: ""
    property string pendingLaterFilename: ""
    property string pendingLaterUsername: ""
    property string pendingLaterPassword: ""
    property string pendingTorrentLaterDownloadId: ""
    property string pendingTorrentLaterSavePath: ""
    property string pendingTorrentLaterCategory: ""
    property string pendingTorrentLaterDesc: ""

    signal accepted(string queueId, bool startProcessing, bool askAgain)
    signal createQueueRequested(string name)

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

    onVisibleChanged: {
        if (visible) {
            _centerOnOwner()
            queueCombo.currentIndex = Math.max(0, queueIds.indexOf(initialQueueId))
            startChk.checked = initialStartProcessing
            askChk.checked = initialAskAgain
            newQueueField.text = ""
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 16
        spacing: 10

        Text { text: qsTr("Put files into a queue?"); color: ColorPalette.textHeader; font.pixelSize: 16 * App.fontScale; font.bold: true }
        Text { text: qsTr("Choose an existing queue or create a new one."); color: "#aab3c2"; font.pixelSize: 11 * App.fontScale; wrapMode: Text.WordWrap; Layout.fillWidth: true }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            Text { text: qsTr("Queue"); color: "#c7cfdb"; font.pixelSize: 12 * App.fontScale; Layout.preferredWidth: 44 }
            StyledComboBox {
                id: queueCombo
                Layout.fillWidth: true
                model: queueNames
                background: Rectangle { color: "#252b35"; border.color: "#3d4a5d"; radius: 4 }
                contentItem: Text { leftPadding: 10; text: queueCombo.displayText; color: "#e8edf5"; font: queueCombo.font; verticalAlignment: Text.AlignVCenter }
            }
            Button {
                text: "+"
                implicitWidth: 32
                background: Rectangle { color: "#2d3440"; border.color: "#4a5a72"; radius: 4 }
                contentItem: Text { text: parent.text; color: ColorPalette.textHeader; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter; font.pixelSize: 16 * App.fontScale; font.bold: true }
                onClicked: createQueuePopup.open()
            }
        }

        StyledCheckBox {
            id: startChk
            text: qsTr("Start queue processing")
            topPadding: 0; bottomPadding: 0
            contentItem: Text { text: parent.text; color: "#d6dbe4"; font.pixelSize: 12 * App.fontScale; leftPadding: parent.indicator.width + 4 }
        }

        StyledCheckBox {
            id: askChk
            text: qsTr("Don't ask me again")
            topPadding: 0; bottomPadding: 0
            contentItem: Text { text: parent.text; color: "#d6dbe4"; font.pixelSize: 12 * App.fontScale; leftPadding: parent.indicator.width + 4 }
        }

        Text { Layout.fillWidth: true; text: root.noteText; color: "#8e97a8"; font.pixelSize: 10 * App.fontScale; wrapMode: Text.WordWrap }

        Item { Layout.fillHeight: true }

        RowLayout {
            Layout.fillWidth: true
            Item { Layout.fillWidth: true }
            DlgButton {
                text: qsTr("Don't add to queue")
                implicitWidth: 150
                onClicked: _addWithoutQueue()
            }
            DlgButton {
                text: qsTr("OK")
                primary: true
                onClicked: _acceptSelection()
            }
        }
    }

    Popup {
        id: createQueuePopup
        modal: true
        focus: true
        width: 300
        height: 124
        x: (root.width - width) / 2
        y: (root.height - height) / 2
        background: Rectangle { color: "#2a2a2a"; border.color: "#525252"; radius: 8 }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 12
            spacing: 8
            Text { text: qsTr("Enter queue name"); color: ColorPalette.textHeader; font.pixelSize: 12 * App.fontScale; font.bold: true }
            TextField {
                id: newQueueField
                Layout.fillWidth: true
                background: Rectangle { color: "#171b22"; border.color: "#3d4a5d"; radius: 4 }
                color: "#e8edf5"
                leftPadding: 8
                Keys.onReturnPressed: _createQueue()
                Keys.onEnterPressed: _createQueue()
            }
            RowLayout {
                Layout.fillWidth: true
                Item { Layout.fillWidth: true }
                DlgButton {
                    text: qsTr("Cancel")
                    onClicked: createQueuePopup.close()
                }
                DlgButton {
                    text: qsTr("Create")
                    primary: true
                    onClicked: createQueuePopup._createQueue()
                }
            }
        }

        function _createQueue() {
            var name = newQueueField.text.trim()
            if (name.length === 0) return
            App.createQueue(name)
            root.createQueueRequested(name)
            root.queueIds = App.queueIds()
            root.queueNames = App.queueNames()
            queueCombo.currentIndex = Math.max(0, root.queueIds.length - 1)
            createQueuePopup.visible = false
        }
    }

    function _acceptSelection() {
        var queueId = queueIds[queueCombo.currentIndex] || ""
        if (pendingContext === "batch") {
            App.settings.showQueueSelectionOnBatchDownload = !askChk.checked
            for (var i = 0; i < pendingBatchUrls.length; ++i) {
                var _qb = pendingBatchUrls[i]
                var _qburl = _qb.url
                var _qbl = _qburl.toLowerCase()
                var sp = _qb.savePath || ""
                var cat = _qb.category || ""
                var desc = _qb.description || ""
                var ref = _qb.referer || ""
                var uname = _qb.username || ""
                var pword = _qb.password || ""
                if (_qbl.startsWith("magnet:?") || _qbl.endsWith(".torrent"))
                    App.silentlyAddTorrent(_qburl, sp, cat, desc, true, queueId)
                else
                    App.addUrl(_qburl, sp, cat, desc, true, "", ref, "", uname, pword, _qb.filename, queueId)
            }
            if (queueId.length > 0 && startChk.checked)
                App.startQueue(queueId)
        } else if (pendingContext === "grabber" && pendingGrabberProjectId.length > 0) {
            App.downloadGrabberResults(pendingGrabberProjectId, false, queueId)
            if (queueId.length > 0 && startChk.checked)
                App.startQueue(queueId)
        } else if (pendingContext === "later" && pendingLaterUrl.length > 0) {
            App.settings.showQueueSelectionOnDownloadLater = !askChk.checked
            if (pendingLaterDownloadId.length > 0) {
                App.finalizePendingDownload(pendingLaterDownloadId, pendingLaterSavePath, pendingLaterCategory, pendingLaterDesc, false, queueId)
            } else {
                var sep = Math.max(pendingLaterSavePath.lastIndexOf("/"), pendingLaterSavePath.lastIndexOf("\\"))
                var dir = sep >= 0 ? pendingLaterSavePath.substring(0, sep) : pendingLaterSavePath
                var fname = sep >= 0 ? pendingLaterSavePath.substring(sep + 1) : pendingLaterFilename
                App.addUrl(pendingLaterUrl, dir, pendingLaterCategory, pendingLaterDesc, false,
                           App.takePendingCookies(pendingLaterUrl), App.takePendingReferrer(pendingLaterUrl),
                           App.takePendingPageUrl(pendingLaterUrl), pendingLaterUsername, pendingLaterPassword, fname, queueId)
            }
            if (queueId.length > 0 && startChk.checked)
                App.startQueue(queueId)
        } else if (pendingContext === "torrentLater" && pendingTorrentLaterDownloadId.length > 0) {
            App.settings.showQueueSelectionOnDownloadLater = !askChk.checked
            App.confirmTorrentDownload(pendingTorrentLaterDownloadId,
                                       pendingTorrentLaterSavePath,
                                       pendingTorrentLaterCategory,
                                       pendingTorrentLaterDesc,
                                       false,
                                       queueId)
            if (queueId.length > 0 && startChk.checked)
                App.startQueue(queueId)
        }
        root.accepted(queueId, startChk.checked, askChk.checked)
        root.pendingContext = ""
        root.pendingGrabberProjectId = ""
        root.pendingBatchUrls = []
        root.pendingLaterDownloadId = ""
        root.pendingLaterUrl = ""
        root.pendingLaterSavePath = ""
        root.pendingLaterCategory = ""
        root.pendingLaterDesc = ""
        root.pendingLaterFilename = ""
        root.pendingLaterUsername = ""
        root.pendingLaterPassword = ""
        root.pendingTorrentLaterDownloadId = ""
        root.pendingTorrentLaterSavePath = ""
        root.pendingTorrentLaterCategory = ""
        root.pendingTorrentLaterDesc = ""
        root.close()
    }

    function _addWithoutQueue() {
        if (pendingContext === "batch") {
            App.settings.showQueueSelectionOnBatchDownload = !askChk.checked
            for (var i = 0; i < pendingBatchUrls.length; ++i) {
                var _qb2 = pendingBatchUrls[i]
                var _qburl2 = _qb2.url
                var _qbl2 = _qburl2.toLowerCase()
                var sp2 = _qb2.savePath || ""
                var cat2 = _qb2.category || ""
                var desc2 = _qb2.description || ""
                var ref2 = _qb2.referer || ""
                var uname2 = _qb2.username || ""
                var pword2 = _qb2.password || ""
                if (_qbl2.startsWith("magnet:?") || _qbl2.endsWith(".torrent"))
                    App.silentlyAddTorrent(_qburl2, sp2, cat2, desc2, startChk.checked)
                else
                    App.addUrl(_qburl2, sp2, cat2, desc2, startChk.checked, "", ref2, "", uname2, pword2, _qb2.filename)
            }
        } else if (pendingContext === "grabber" && pendingGrabberProjectId.length > 0) {
            App.downloadGrabberResults(pendingGrabberProjectId, startChk.checked)
        } else if (pendingContext === "later" && pendingLaterUrl.length > 0) {
            App.settings.showQueueSelectionOnDownloadLater = !askChk.checked
            if (pendingLaterDownloadId.length > 0) {
                App.finalizePendingDownload(pendingLaterDownloadId, pendingLaterSavePath, pendingLaterCategory, pendingLaterDesc, startChk.checked, "")
            } else {
                var sep = Math.max(pendingLaterSavePath.lastIndexOf("/"), pendingLaterSavePath.lastIndexOf("\\"))
                var dir = sep >= 0 ? pendingLaterSavePath.substring(0, sep) : pendingLaterSavePath
                var fname = sep >= 0 ? pendingLaterSavePath.substring(sep + 1) : pendingLaterFilename
                App.addUrl(pendingLaterUrl, dir, pendingLaterCategory, pendingLaterDesc, startChk.checked,
                           App.takePendingCookies(pendingLaterUrl), App.takePendingReferrer(pendingLaterUrl),
                           App.takePendingPageUrl(pendingLaterUrl), pendingLaterUsername, pendingLaterPassword, fname)
            }
        } else if (pendingContext === "torrentLater" && pendingTorrentLaterDownloadId.length > 0) {
            App.settings.showQueueSelectionOnDownloadLater = !askChk.checked
            App.confirmTorrentDownload(pendingTorrentLaterDownloadId,
                                       pendingTorrentLaterSavePath,
                                       pendingTorrentLaterCategory,
                                       pendingTorrentLaterDesc,
                                       startChk.checked,
                                       "")
        }
        root.pendingContext = ""
        root.pendingGrabberProjectId = ""
        root.pendingBatchUrls = []
        root.pendingLaterDownloadId = ""
        root.pendingLaterUrl = ""
        root.pendingLaterSavePath = ""
        root.pendingLaterCategory = ""
        root.pendingLaterDesc = ""
        root.pendingLaterFilename = ""
        root.pendingLaterUsername = ""
        root.pendingLaterPassword = ""
        root.pendingTorrentLaterDownloadId = ""
        root.pendingTorrentLaterSavePath = ""
        root.pendingTorrentLaterCategory = ""
        root.pendingTorrentLaterDesc = ""
        root.close()
    }
}
