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

import QtQml

// The yt-dlp options shared by the single-video and channel dialogs: their
// state, the reset to defaults, and the extraOptions map the backend reads
// (YtdlpOptions::fromJson). The option pages (YtdlpExtrasPage,
// YtdlpAdvancedPage) edit this object; the dialogs only reset and read it.
QtObject {
    id: options

    // Subtitles
    property bool   writeSubs: false
    property bool   writeAutoSubs: false
    property string subLangs: "en"
    property bool   embedSubs: false
    // Post-processing
    property bool   embedThumbnail: false
    property bool   embedMetadata: false
    property bool   sponsorBlock: false
    property bool   splitChapters: false
    // Extra files
    property bool   writeDescription: false
    property bool   writeThumbnailFile: false
    // Access and speed
    property string cookiesBrowser: ""
    property int    rateLimitKBps: 0
    property int    concurrentFragments: 1
    // Live streams
    property bool   liveFromStart: false
    property bool   waitForVideo: false
    property int    waitForVideoSecs: 60
    property bool   useArchive: false
    // Single video only
    property string downloadSections: ""

    // yt-dlp's --cookies-from-browser names, with "" for none. Labels are
    // product names, except "None".
    readonly property var browsers: ["", "chrome", "firefox", "edge", "brave", "opera", "vivaldi", "safari"]
    readonly property var browserLabels: [qsTr("None"), "Chrome", "Firefox", "Edge", "Brave", "Opera", "Vivaldi", "Safari"]
    function browserIndex(name) {
        var i = browsers.indexOf((name || "").toLowerCase())
        return i < 0 ? 0 : i
    }

    function containerSupportsSubs(container) {
        return container === "mp4" || container === "mkv" || container === "webm"
    }

    function reset() {
        writeSubs = false; writeAutoSubs = false; subLangs = "en"; embedSubs = false
        embedThumbnail = false; embedMetadata = false; sponsorBlock = false; splitChapters = false
        writeDescription = false; writeThumbnailFile = false
        cookiesBrowser = browsers[browserIndex(App.settings.ytdlpDefaultCookieBrowser)]
        rateLimitKBps = 0; concurrentFragments = 1
        liveFromStart = false; waitForVideo = false; waitForVideoSecs = 60
        downloadSections = ""; useArchive = false
    }

    // `container` decides whether subtitles can be embedded; `singleVideo`
    // whether the time range applies (it names a part of one video).
    function buildExtraOptions(container, singleVideo) {
        var o = {}
        if (writeSubs) {
            o.writeSubs = true
            if (writeAutoSubs) o.writeAutoSubs = true
            var langs = subLangs.trim()
            if (langs.length > 0 && langs !== "en") o.subLangs = langs
            if (embedSubs && containerSupportsSubs(container)) o.embedSubs = true
        }
        if (embedThumbnail)     o.embedThumbnail = true
        if (embedMetadata)      o.embedMetadata = true
        if (sponsorBlock)       o.sponsorBlock = true
        if (splitChapters)      o.splitChapters = true
        if (writeDescription)   o.writeDescription = true
        if (writeThumbnailFile) o.writeThumbnailFile = true
        if (cookiesBrowser.length > 0) o.cookiesFromBrowser = cookiesBrowser
        if (rateLimitKBps > 0)       o.rateLimitKBps = rateLimitKBps
        if (concurrentFragments > 1) o.concurrentFragments = concurrentFragments
        if (liveFromStart)      o.liveFromStart = true
        if (waitForVideo && waitForVideoSecs > 0) o.waitForVideoSecs = waitForVideoSecs
        if (singleVideo && downloadSections.trim().length > 0) o.downloadSections = downloadSections.trim()
        if (useArchive)         o.useArchive = true
        return o
    }
}
