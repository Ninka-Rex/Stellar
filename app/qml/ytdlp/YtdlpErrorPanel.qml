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
import QtQuick.Controls.Basic as B
import QtQuick.Layouts

// Why yt-dlp could not read a link, with the usual fixes at hand: a
// JavaScript runtime for YouTube's challenge, and browser cookies for videos
// that need a sign-in. Shared by the single-video and channel dialogs.
SettingsScroll {
    id: panel

    required property YtdlpOptions options
    property string title
    property string message
    signal retry()
    signal openSettingsRequested(int page)

    // yt-dlp's wording when YouTube's "n" challenge could not be solved.
    readonly property bool _needsJsRuntime: /n challenge|EJS|js-runtimes|JavaScript runtime/.test(message)

    SettingsSection {
        SettingsStatus {
            level: SettingsStatus.Level.Error
            text: panel.title
        }

        // Selectable so the message can be copied into a bug report.
        B.TextArea {
            Layout.fillWidth: true
            readOnly: true
            selectByMouse: true
            wrapMode: TextEdit.Wrap
            padding: 0
            background: null
            text: panel.message.replace(/(\r?\n)+null\s*$/g, "").trim()
            textFormat: TextEdit.PlainText
            color: ColorPalette.textSecond
            selectionColor: ColorPalette.accent
            selectedTextColor: "#ffffff"
            font.pixelSize: 12 * App.fontScale
        }
    }

    SettingsSection {
        visible: panel._needsJsRuntime
        title: qsTr("JavaScript runtime")

        SettingsNote {
            warning: !App.ytdlpManager.jsRuntimeAvailable
            text: App.ytdlpManager.jsRuntimeAvailable
                  ? qsTr("yt-dlp could not solve YouTube's download challenge even though a runtime was found (%1). Updating yt-dlp usually fixes this.").arg(App.ytdlpManager.jsRuntimeName)
                  : qsTr("YouTube requires yt-dlp to solve a challenge with a JavaScript runtime (Deno, Node.js, Bun or QuickJS). Install one, e.g. Deno, then retry.")
        }
        RowLayout {
            visible: !App.ytdlpManager.jsRuntimeAvailable
            spacing: 16
            SettingsLink {
                text: qsTr("Get Deno")
                url: "https://deno.com"
            }
            SettingsLink {
                text: qsTr("Open Media settings")
                onClicked: panel.openSettingsRequested(7)
            }
        }
    }

    SettingsSection {
        title: qsTr("Sign-in")

        SettingsRow {
            label: qsTr("Cookies from browser")
            hint: qsTr("Age-restricted, members-only and private videos need the cookies of a browser where you are signed in.")
            SettingsCombo {
                model: panel.options.browserLabels
                value: panel.options.browserIndex(panel.options.cookiesBrowser)
                onEdited: (i) => panel.options.cookiesBrowser = panel.options.browsers[i]
            }
        }

        DlgButton {
            text: qsTr("Retry")
            onClicked: panel.retry()
        }
    }
}
