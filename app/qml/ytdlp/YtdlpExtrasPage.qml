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

// "Subtitles & extras" page of the yt-dlp dialogs: subtitles, what ffmpeg
// does to the file afterwards, and side files.
SettingsScroll {
    id: page

    required property YtdlpOptions options
    // Output container, which decides whether subtitles can be embedded.
    property string container: "mp4"
    readonly property bool _ffmpeg: App.ytdlpManager.ffmpegAvailable

    SettingsSection {
        title: qsTr("Subtitles")

        SettingsCheck {
            text: qsTr("Download subtitles")
            checked: page.options.writeSubs
            onToggled: (on) => page.options.writeSubs = on
        }

        ColumnLayout {
            Layout.fillWidth: true
            visible: page.options.writeSubs
            spacing: 8

            SettingsRow {
                label: qsTr("Languages")
                hint: qsTr("Language codes separated by commas, e.g. en,ja. Patterns like en.* and \"all\" work too.")
                SettingsTextField {
                    Layout.maximumWidth: 200
                    value: page.options.subLangs
                    onEdited: (t) => page.options.subLangs = t
                }
            }
            SettingsCheck {
                text: qsTr("Include auto-generated captions")
                checked: page.options.writeAutoSubs
                onToggled: (on) => page.options.writeAutoSubs = on
            }
            SettingsCheck {
                enabled: page.options.containerSupportsSubs(page.container)
                text: qsTr("Embed in the video file")
                description: enabled ? "" : qsTr("Only mp4, mkv and webm files can hold subtitles.")
                checked: page.options.embedSubs
                onToggled: (on) => page.options.embedSubs = on
            }
        }
    }

    SettingsSection {
        title: qsTr("Processing")
        description: page._ffmpeg ? "" : qsTr("These need ffmpeg, which was not found. See Settings › Media.")

        SettingsCheck {
            enabled: page._ffmpeg
            text: qsTr("Embed thumbnail as cover art")
            checked: page.options.embedThumbnail
            onToggled: (on) => page.options.embedThumbnail = on
        }
        SettingsCheck {
            enabled: page._ffmpeg
            text: qsTr("Embed metadata")
            description: qsTr("Title, uploader, date and chapters are written into the file.")
            checked: page.options.embedMetadata
            onToggled: (on) => page.options.embedMetadata = on
        }
        SettingsCheck {
            enabled: page._ffmpeg
            text: qsTr("Remove sponsor segments")
            description: qsTr("Cuts sponsored segments, intros and self-promotion marked on SponsorBlock. YouTube only.")
            checked: page.options.sponsorBlock
            onToggled: (on) => page.options.sponsorBlock = on
        }
        SettingsCheck {
            enabled: page._ffmpeg
            text: qsTr("Split into one file per chapter")
            checked: page.options.splitChapters
            onToggled: (on) => page.options.splitChapters = on
        }
    }

    SettingsSection {
        title: qsTr("Extra files")

        SettingsCheck {
            text: qsTr("Save the description as a text file")
            checked: page.options.writeDescription
            onToggled: (on) => page.options.writeDescription = on
        }
        SettingsCheck {
            text: qsTr("Save the thumbnail as an image file")
            checked: page.options.writeThumbnailFile
            onToggled: (on) => page.options.writeThumbnailFile = on
        }
    }
}
