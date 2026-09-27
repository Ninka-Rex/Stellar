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
import QtQuick.Layouts

// "Advanced" page of the yt-dlp dialogs: sign-in, speed, live streams and
// (for one video) the part to download.
SettingsScroll {
    id: page

    required property YtdlpOptions options
    // The time range names a part of one video, so it is hidden for channels.
    property bool singleVideo: true

    SettingsSection {
        title: qsTr("Access")

        SettingsRow {
            label: qsTr("Cookies from browser")
            hint: qsTr("Signs in as you for members-only, age-restricted or private videos.")
            SettingsCombo {
                model: page.options.browserLabels
                value: page.options.browserIndex(page.options.cookiesBrowser)
                onEdited: (i) => page.options.cookiesBrowser = page.options.browsers[i]
            }
        }
    }

    SettingsSection {
        title: qsTr("Speed")

        SettingsRow {
            label: qsTr("Speed limit")
            hint: qsTr("0 uses the global speed limit.")
            SettingsNumber {
                from: 0; to: 1000000; stepSize: 100
                suffix: qsTr("KB/s")
                value: page.options.rateLimitKBps
                onEdited: (v) => page.options.rateLimitKBps = v
            }
        }
        SettingsRow {
            label: qsTr("Parallel fragments")
            hint: qsTr("For streams delivered in fragments (DASH/HLS).")
            SettingsNumber {
                from: 1; to: 16
                value: page.options.concurrentFragments
                onEdited: (v) => page.options.concurrentFragments = v
            }
        }
    }

    SettingsSection {
        title: qsTr("Live streams")

        SettingsCheck {
            text: qsTr("Record from the start")
            description: qsTr("Downloads a stream that is already live from its beginning (YouTube, Twitch).")
            checked: page.options.liveFromStart
            onToggled: (on) => page.options.liveFromStart = on
        }
        SettingsCheck {
            text: qsTr("Wait for scheduled streams to start")
            checked: page.options.waitForVideo
            onToggled: (on) => page.options.waitForVideo = on
        }
        SettingsRow {
            visible: page.options.waitForVideo
            label: qsTr("Check every")
            SettingsNumber {
                from: 1; to: 86400
                suffix: qsTr("seconds")
                value: page.options.waitForVideoSecs
                onEdited: (v) => page.options.waitForVideoSecs = v
            }
        }
    }

    SettingsSection {
        visible: page.singleVideo
        title: qsTr("Part of the video")

        SettingsRow {
            label: qsTr("Time range")
            hint: qsTr("e.g. *01:30-03:00, or a chapter name. Leave blank for the whole video.")
            SettingsTextField {
                Layout.maximumWidth: 200
                value: page.options.downloadSections
                onEdited: (t) => page.options.downloadSections = t
            }
        }
    }

    SettingsSection {
        title: qsTr("Archive")

        SettingsCheck {
            text: qsTr("Skip videos already in the download archive")
            description: qsTr("Keeps yt-dlp-archive.txt in the save folder and skips any video listed in it.")
            checked: page.options.useArchive
            onToggled: (on) => page.options.useArchive = on
        }
    }
}
