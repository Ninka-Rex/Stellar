pragma Singleton
import QtQuick

QtObject {
    readonly property bool dark: App.settings.darkMode

    // Backgrounds
    readonly property color windowBg:     dark ? "#1c1c1c" : "#f0f0f0"
    readonly property color cardBg:       dark ? "#1e1e1e" : "#f7f7f7"
    readonly property color panelBg:      dark ? "#252525" : "#e8e8e8"
    readonly property color inputBg:      dark ? "#1b1b1b" : "#ffffff"
    readonly property color rowAltBg:     dark ? "#222222" : "#e6e6e6"
    readonly property color toolbarBg:      dark ? "#1f1f1f" : "#dcdcdc"
    readonly property color toolbarHoverBg: dark ? "#3a3a55" : "#c8d4e8"
    readonly property color toolbarPressBg: dark ? "#4a4a66" : "#b0c0dc"
    readonly property color dividerBg:    dark ? "#2d2d2d" : "#d8d8d8"

    // Borders
    readonly property color border:       dark ? "#3a3a3a" : "#c8c8c8"
    readonly property color borderFocus:  "#4488dd"
    readonly property color borderCard:   dark ? "#2d2d2d" : "#e0e0e0"

    // Text
    readonly property color textPrimary:  dark ? "#e0e0e0" : "#1a1a1a"
    readonly property color textSecond:   dark ? "#aaaaaa" : "#555555"
    readonly property color textDisabled: dark ? "#666666" : "#aaaaaa"
    readonly property color textHeader:   dark ? "#ffffff" : "#111111"
    readonly property color textMuted:    dark ? "#888888" : "#888888"

    // Accent / selection
    readonly property color accent:            "#4488dd"
    readonly property color accentHover:       "#66a3f0"  // brighter accent on hover (clickable links)
    readonly property color selectionBg:       dark ? "#1a3a6a" : "#cce0ff"
    readonly property color selectionBorder:   "#4488dd"
    readonly property color selectionText:     dark ? "#ffffff" : "#003070"  // text on selectionBg
    readonly property color buttonSecondaryBg:      dark ? "#3a3a3a" : "#d0d4da"  // secondary button fill
    readonly property color buttonSecondaryHoverBg: dark ? "#484848" : "#c0c6ce"  // secondary button hover
    readonly property color hoverBg:           dark ? "#2a2a2a" : "#e0e8f5"
    // Opaque fill for dropdown-menu rows — must never be "transparent". Under the
    // software scene graph the Menu panel node may not composite, so transparent
    // rows show the window through; opaque rows form the solid menu panel
    // themselves. See CLAUDE.md "Linux Software-Backend Menus".
    readonly property color menuBg:            dark ? "#1e1e1e" : "#f7f7f7"

    // Info / note boxes
    readonly property color infoBoxBg:     dark ? "#1a2030" : "#e8f0ff"
    readonly property color infoBoxBorder: dark ? "#2a3050" : "#aabbdd"
    readonly property color infoBoxText:   dark ? "#8899bb" : "#445577"

    // Header strips (dark accent bars at top of dialogs)
    readonly property color headerStripBg: dark ? "#222228" : "#dde4f0"

    // Progress-bar fill by download state. Blue = actively downloading,
    // green = seeding/complete, orange = magnet still fetching metadata
    // (shown as an indeterminate sliver, see TorrentProgressBar.qml).
    readonly property color progressDownloading: "#4488dd"
    readonly property color progressGreen:       dark ? "#3fae5a" : "#2f9d4a"
    readonly property color progressMetadata:    "#e08a2b"
    readonly property color progressTrack:       dark ? "#111111" : "#d2d2d2"
    readonly property color progressTrackBorder: dark ? "#2f2f2f" : "#bcbcbc"

    // Swarm / piece map (data-viz canvas + panels). Light repaint in light mode.
    readonly property color mapCanvasBg:  dark ? "#0d141c" : "#eef3f8"
    readonly property color mapPanelBg:   dark ? "#101821" : "#f4f7fb"
    readonly property color mapGrid:      dark ? "#1a2a3a" : "#cdd9e6"
    readonly property color mapBorder:    dark ? "#314252" : "#c2cedb"
    readonly property color mapTooltipBg: dark ? "#13202d" : "#ffffff"

    // Peer-info client / user-agent string (was a hard light-blue, illegible in light mode)
    readonly property color clientText: dark ? "#8fb4d9" : "#2a5a8a"
    // Map node labels ("You"/"Peer") — pill bg + readable text in both modes
    readonly property color mapLabelBg:   dark ? "#000000" : "#ffffff"
    readonly property color mapLabelText: dark ? "#f6f6f6" : "#1a1a1a"

    // Generic tooltip (ThemedToolTip)
    readonly property color tooltipBg:     dark ? "#2a2a2a" : "#ffffff"
    readonly property color tooltipBorder: dark ? "#3a3a3a" : "#c2c2c2"
    readonly property color tooltipText:   dark ? "#e0e0e0" : "#202020"

    // Status text: success (green) and error (red). Darker in light mode for legibility.
    readonly property color successText: dark ? "#55bb77" : "#2f8a4a"
    readonly property color errorText:   dark ? "#e06a60" : "#b3261e"

    // Warning / caution text (amber). Darker in light mode for legibility.
    readonly property color warningText: dark ? "#e8c840" : "#9a6a00"
    // Speed-limit / throttle accent. Cleaner orange in light mode (warningText
    // reads too brown for inline "(Limited …)" labels).
    readonly property color speedLimitText: dark ? "#e8a34a" : "#c2591b"

    // Material theme integer (2=Dark, 1=Light) - avoids importing Material in non-Window files
    readonly property int materialTheme: dark ? 2 : 1
    readonly property color materialBg:  dark ? "#1e1e1e" : "#f7f7f7"
    readonly property color materialWindowBg: dark ? "#1c1c1c" : "#f0f0f0"

    // Share-ratio colour ramp (Statistics window, Torrents preferences):
    // red → orange → green → lime → cyan → blue → purple → magenta as the ratio
    // climbs from 0 to 10+, interpolated between stops.
    function ratioColor(r) {
        r = r || 0
        function lerp(a, b, t) {
            return Math.round(a + (b - a) * Math.max(0, Math.min(1, t)))
        }
        function rgb(hr, hg, hb) {
            return "#" + ("0" + hr.toString(16)).slice(-2)
                       + ("0" + hg.toString(16)).slice(-2)
                       + ("0" + hb.toString(16)).slice(-2)
        }
        // stops: [ratio, r, g, b]
        var stops = [
            [0.0,  255, 85,  85],
            [0.5,  255, 153, 68],
            [1.0,  85,  204, 102],
            [2.0,  153, 238, 85],
            [4.0,  68,  221, 204],
            [6.0,  68,  153, 255],
            [8.0,  170, 85,  255],
            [10.0, 255, 68,  204]
        ]
        var last = stops[stops.length - 1]
        if (r <= stops[0][0]) return rgb(stops[0][1], stops[0][2], stops[0][3])
        if (r >= last[0]) return rgb(last[1], last[2], last[3])
        for (var i = 1; i < stops.length; i++) {
            if (r <= stops[i][0]) {
                var t = (r - stops[i-1][0]) / (stops[i][0] - stops[i-1][0])
                return rgb(lerp(stops[i-1][1], stops[i][1], t),
                           lerp(stops[i-1][2], stops[i][2], t),
                           lerp(stops[i-1][3], stops[i][3], t))
            }
        }
        return rgb(last[1], last[2], last[3])
    }
}
