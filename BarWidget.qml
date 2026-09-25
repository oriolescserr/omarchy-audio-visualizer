import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import qs.Commons
import qs.Ui

// Spectrum bars driven by cava. Collapses to zero size and runs nothing
// unless an MPRIS player is playing. Colour follows the bar's own text
// colour, so themes and transparent-bar mode apply automatically.
//   hover : the bar's native tooltip with the current track
//   click : a card with artwork, track details, progress and controls
BarWidget {
    id: root
    moduleName: "oriolus.audio-visualizer"

    readonly property int barCount: {
        var n = Math.round(Number(setting("bars", 10)))
        return isFinite(n) ? Math.max(4, Math.min(32, n)) : 10
    }
    readonly property int barThickness: 3
    readonly property int barGap: 3
    readonly property int maxLength: Math.round(barSize * 0.5)
    // Outer padding so the gap to neighbouring icons matches the icon-to-icon gap.
    readonly property int margin: Math.max(0, Math.round((Style.bar.iconSlot - Style.bar.iconCanvas) / 2))
    readonly property int span: barCount * barThickness + (barCount - 1) * barGap

    // ---- Player state -----------------------------------------------------
    readonly property var playerList: Mpris.players ? Mpris.players.values : []
    readonly property var playingPlayer: {
        for (var i = 0; i < playerList.length; i++)
            if (playerList[i] && playerList[i].isPlaying) return playerList[i]
        return null
    }
    readonly property bool playing: playingPlayer !== null
    // While the card is open a paused player stays selected so it can be resumed.
    property var lastPlayer: null
    onPlayingPlayerChanged: if (playingPlayer) lastPlayer = playingPlayer
    readonly property var player: playingPlayer || (opened ? (lastPlayer || playerList[0] || null) : null)

    readonly property string trackTitle: player ? (player.trackTitle || "Unknown track") : ""
    readonly property string trackArtist: player ? (player.trackArtist || "") : ""
    readonly property string trackAlbum: player ? (player.trackAlbum || "") : ""
    readonly property string trackText: trackArtist ? trackTitle + " · " + trackArtist : trackTitle
    readonly property bool hasTrack: !!(player && (player.trackTitle || player.trackArtist))

    // ---- Card open state --------------------------------------------------
    property bool opened: false
    function close() { opened = false }
    function toggle() { opened = !opened }
    onPlayerChanged: if (!player) opened = false

    // ---- Playback actions -------------------------------------------------
    readonly property bool canSeek: !!(player && player.canSeek && player.positionSupported
                                       && player.lengthSupported && player.length > 0)

    function playPause() { if (player && player.canTogglePlaying) player.togglePlaying() }
    function nextTrack() { if (player && player.canGoNext) player.next() }
    function previousTrack() { if (player && player.canGoPrevious) player.previous() }

    function seekTo(seconds) {
        if (!canSeek) return
        player.position = Math.max(0, Math.min(player.length - 1, seconds))
        player.positionChanged()
    }
    function seekBy(seconds) { if (canSeek) seekTo(player.position + seconds) }

    function changeVolume(delta) {
        if (!player || !player.volumeSupported || !player.canControl) return
        player.volume = Math.max(0, Math.min(1, player.volume + delta))
    }

    // IPC: omarchy-shell oriolus.audio-visualizer <function>
    IpcHandler {
        target: "oriolus.audio-visualizer"
        function toggle(): void { root.toggle() }
        function open(): void { root.opened = true }
        function close(): void { root.close() }
        function playPause(): void { root.playPause() }
        function next(): void { root.nextTrack() }
        function previous(): void { root.previousTrack() }
        function forward(): void { root.seekBy(10) }
        function back(): void { root.seekBy(-10) }
    }

    // ---- Reveal animation -------------------------------------------------
    // 0 = hidden and zero-sized, 1 = fully shown. Drives size and opacity
    // together so the widget eases in and out without popping.
    property real reveal: (playing || opened) ? 1 : 0
    Behavior on reveal { NumberAnimation { duration: 320; easing.type: Easing.InOutCubic } }

    readonly property int fullWidth: vertical ? barSize : span + 2 * margin
    readonly property int fullHeight: vertical ? span + 2 * margin : barSize

    visible: reveal > 0.001
    opacity: reveal
    clip: true
    implicitWidth: vertical ? fullWidth : Math.round(fullWidth * reveal)
    implicitHeight: vertical ? Math.round(fullHeight * reveal) : fullHeight

    readonly property color tint: bar ? bar.barForeground : "#cacccc"
    property var levels: []

    // ---- cava ---------------------------------------------------------------
    // Programs run by absolute path with a minimal environment. cava needs HOME
    // to start and XDG_RUNTIME_DIR to reach PipeWire.
    readonly property string runtimeDir: Quickshell.env("XDG_RUNTIME_DIR") || ""
    function pluginFile(name) {
        return decodeURIComponent(Qt.resolvedUrl(name).toString().replace(/^file:\/\//, ""))
    }
    readonly property var helperEnvironment: ({
        PATH: "/usr/bin",
        HOME: Quickshell.env("HOME") || "",
        XDG_RUNTIME_DIR: runtimeDir
    })

    // cava.conf with the validated bar count, written to the user's private
    // runtime directory before cava starts.
    property bool cavaConfigReady: false
    FileView {
        id: cavaTemplate
        path: root.pluginFile("cava.conf")
        blockLoading: true
    }
    FileView {
        id: cavaConfig
        path: root.runtimeDir ? root.runtimeDir + "/oriolus-audio-visualizer-cava.conf" : ""
        blockWrites: true
        atomicWrites: true
        printErrors: false
        onSaveFailed: root.cavaConfigReady = false
    }
    // Writes are synchronous (blockWrites). Marking the config ready on the next
    // tick restarts a running cava so it picks up a new bar count.
    function writeCavaConfig() {
        cavaConfigReady = false
        if (!cavaConfig.path) return
        cavaConfig.setText(cavaTemplate.text().replace(/^\[general\]$/m, "[general]\nbars = " + barCount))
        Qt.callLater(function () { root.cavaConfigReady = true })
    }
    onBarCountChanged: writeCavaConfig()

    Process {
        id: cava
        running: root.playing && root.cavaConfigReady
        command: ["/usr/bin/cava", "-p", cavaConfig.path]
        clearEnvironment: true
        environment: root.helperEnvironment
        stdout: SplitParser {
            onRead: function (line) {
                if (line.length > 512) return
                var parts = line.split(";")
                var out = []
                for (var i = 0; i < root.barCount; i++)
                    out.push(Math.min(1, (Number(parts[i]) || 0) / 100))
                root.levels = out
            }
        }
        onRunningChanged: if (!running) root.levels = []
    }

    Repeater {
        model: root.barCount
        Rectangle {
            required property int index
            readonly property real level: root.levels.length > index ? root.levels[index] : 0
            readonly property real len: Math.max(root.barThickness, level * root.maxLength)

            radius: root.barThickness / 2
            color: root.tint
            opacity: 0.55 + 0.45 * level

            width: root.vertical ? len : root.barThickness
            height: root.vertical ? root.barThickness : len
            x: root.vertical ? (root.width - width) / 2 : root.margin + index * (root.barThickness + root.barGap)
            y: root.vertical ? root.margin + index * (root.barThickness + root.barGap) : (root.height - height) / 2

            Behavior on width { enabled: root.vertical; NumberAnimation { duration: 60 } }
            Behavior on height { enabled: !root.vertical; NumberAnimation { duration: 60 } }
        }
    }

    // ---- Hover (native bar tooltip) and click -----------------------------
    property bool tipWanted: false
    readonly property bool tipShown: tipWanted && playing && !opened && trackTitle !== ""
    property string shownTitle: ""
    property string shownArtist: ""
    onTrackTitleChanged: if (trackTitle) shownTitle = trackTitle
    onTrackArtistChanged: if (player) shownArtist = trackArtist
    Component.onCompleted: {
        shownTitle = trackTitle
        shownArtist = trackArtist
        writeCavaConfig()
    }

    Timer { id: tipDelay; interval: 400; onTriggered: root.tipWanted = true }

    MouseArea {
        id: hoverArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton
        onEntered: tipDelay.restart()
        onExited: { tipDelay.stop(); root.tipWanted = false }
        onClicked: function (mouse) {
            tipDelay.stop()
            root.tipWanted = false
            if (mouse.button === Qt.MiddleButton) {
                root.playPause()
            } else {
                root.toggle()
            }
        }
    }

    // Tooltip styled like the bar's native one: title above artist.
    PopupWindow {
        id: tip
        visible: root.tipShown || tipBubble.opacity > 0.01
        color: "transparent"
        implicitWidth: Math.ceil(tipBubble.implicitWidth)
        implicitHeight: Math.ceil(tipBubble.implicitHeight)

        anchor {
            id: tipAnchor
            window: root.QsWindow.window
            adjustment: PopupAdjustment.Slide
            edges: Edges.Top | Edges.Left
            gravity: Edges.Bottom | Edges.Right
            rect.width: 1
            rect.height: 1

            onAnchoring: {
                var win = root.QsWindow.window
                if (!win) return
                var pos = root.bar ? root.bar.position : "top"
                var x = root.width / 2 - tip.implicitWidth / 2
                var y = root.height + 6
                if (pos === "bottom") y = -tip.implicitHeight - 6
                else if (pos === "left") { x = root.width + 6; y = root.height / 2 - tip.implicitHeight / 2 }
                else if (pos === "right") { x = -tip.implicitWidth - 6; y = root.height / 2 - tip.implicitHeight / 2 }
                var point = win.contentItem.mapFromItem(root, x, y)
                tipAnchor.rect.x = Math.round(point.x)
                tipAnchor.rect.y = Math.round(point.y)
            }
        }

        BorderSurface {
            id: tipBubble
            implicitWidth: Math.max(tipTitle.implicitWidth, tipArtist.implicitWidth) + 28
            implicitHeight: tipColumn.implicitHeight + 14
            color: Color.tooltip.background
            borderSpec: Border.surfaceSpec("tooltip", "border", Color.tooltip.border, 1)
            radius: Style.cornerRadius
            opacity: root.tipShown ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

            Column {
                id: tipColumn
                anchors.centerIn: parent
                spacing: 2

                Marquee {
                    id: tipTitle
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: root.shownTitle
                    color: Color.tooltip.text
                    fontFamily: Style.font.family
                    pixelSize: Style.font.subtitle
                    bold: true
                    running: root.tipShown
                }
                Marquee {
                    id: tipArtist
                    anchors.horizontalCenter: parent.horizontalCenter
                    visible: text !== ""
                    text: root.shownArtist
                    color: Color.tooltip.text
                    opacity: 0.7
                    fontFamily: Style.font.family
                    pixelSize: Style.font.bodySmall
                    running: root.tipShown
                }
            }
        }
    }

    // ---- Artwork ------------------------------------------------------------
    // The player's artwork URL is never loaded directly: art-fetch.sh copies it
    // to the runtime directory after checking scheme, size, type and pixel
    // dimensions, and the card shows that copy. Only fetched while the card is open.
    readonly property string artRequest: opened && player && player.trackArtUrl ? player.trackArtUrl : ""
    property string artPath: ""
    onArtRequestChanged: {
        artPath = ""
        artDebounce.restart()
    }
    Timer {
        id: artDebounce
        interval: 150
        onTriggered: root.startArtFetch()
    }
    // A running fetch is stopped first; the new one starts once it has exited.
    function startArtFetch() {
        if (artFetch.running) {
            artFetch.pending = true
            artFetch.running = false
            return
        }
        if (!artRequest || !runtimeDir || artRequest.length > 6000000) return
        artFetch.request = artRequest
        artFetch.running = true
    }
    Process {
        id: artFetch
        property string request: ""
        property bool pending: false
        command: ["/usr/bin/timeout", "20", "/usr/bin/bash", root.pluginFile("art-fetch.sh")]
        clearEnvironment: true
        environment: root.helperEnvironment
        stdinEnabled: true
        onStarted: {
            write(request)
            stdinEnabled = false
        }
        onExited: {
            stdinEnabled = true
            if (pending) {
                pending = false
                root.startArtFetch()
            }
        }
        stdout: StdioCollector {
            onStreamFinished: {
                var path = text.trim()
                var dir = root.runtimeDir + "/oriolus-audio-visualizer/"
                if (artFetch.request === root.artRequest && path.indexOf(dir) === 0 && path.indexOf("\n") < 0)
                    root.artPath = path
            }
        }
    }

    // ---- Card -------------------------------------------------------------
    function formatTime(seconds) {
        var s = Math.max(0, Math.floor(Number(seconds) || 0))
        var m = Math.floor(s / 60)
        var h = Math.floor(m / 60)
        var ss = ("0" + (s % 60)).slice(-2)
        return h > 0 ? h + ":" + ("0" + (m % 60)).slice(-2) + ":" + ss : m + ":" + ss
    }

    // Keys: Space/Enter play/pause, ←/→ (h/l) seek 5 s, ↑/↓ (k/j) volume,
    // n/p next/previous, 0–9 jump to 0–90 %, Esc close.
    KeyboardPanel {
        id: card
        anchorItem: root
        owner: root
        bar: root.bar
        open: root.opened
        focusTarget: keys
        contentWidth: card.fittedContentWidth(Style.space(320))
        contentHeight: card.fittedContentHeight(column.implicitHeight)

        PanelKeyCatcher {
            id: keys
            anchors.fill: parent
            onActivateRequested: root.playPause()
            onCloseRequested: root.close()
            onMoveRequested: function (dx, dy) {
                if (dx !== 0) root.seekBy(dx * 5)
                if (dy !== 0) root.changeVolume(-dy * 0.05)
            }
            onTextKey: function (t) {
                var key = t.toLowerCase()
                if (key === "n") root.nextTrack()
                else if (key === "p") root.previousTrack()
                else if (key >= "0" && key <= "9" && root.canSeek) root.seekTo(root.player.length * Number(key) / 10)
            }

            Column {
                id: column
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                spacing: Style.space(14)

                // Shown instead of the player when there is no track.
                Column {
                    width: parent.width
                    visible: !root.hasTrack
                    topPadding: Style.space(10)
                    bottomPadding: Style.space(10)
                    spacing: Style.space(6)

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "󰎊"
                        color: root.bar ? root.bar.foreground : root.tint
                        opacity: 0.35
                        font.family: Style.font.family
                        font.pixelSize: Style.font.display
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "Nothing playing"
                        color: root.bar ? root.bar.foreground : root.tint
                        opacity: 0.8
                        font.family: Style.font.family
                        font.pixelSize: Style.font.body
                        font.bold: true
                    }
                    Text {
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.Wrap
                        text: "Start music in any player to see it here"
                        color: root.bar ? root.bar.foreground : root.tint
                        opacity: 0.45
                        font.family: Style.font.family
                        font.pixelSize: Style.font.caption
                    }
                }

                // Artwork + track details
                RowLayout {
                    width: parent.width
                    visible: root.hasTrack
                    spacing: Style.space(14)

                    Rectangle {
                        Layout.preferredWidth: Style.space(72)
                        Layout.preferredHeight: Style.space(72)
                        radius: Style.cornerRadius
                        color: Qt.rgba(root.tint.r, root.tint.g, root.tint.b, 0.08)
                        clip: true

                        Image {
                            id: art
                            anchors.fill: parent
                            source: root.artPath ? "file://" + root.artPath : ""
                            sourceSize.width: 256
                            sourceSize.height: 256
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            visible: status === Image.Ready
                        }
                        Text {
                            anchors.centerIn: parent
                            visible: art.status !== Image.Ready
                            text: "󰎆"
                            color: root.tint
                            opacity: 0.5
                            font.family: Style.font.family
                            font.pixelSize: Style.font.display
                        }
                    }

                    Column {
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignVCenter
                        spacing: Style.space(3)

                        Text {
                            width: parent.width
                            text: root.trackTitle
                            textFormat: Text.PlainText
                            color: root.bar ? root.bar.foreground : root.tint
                            font.family: Style.font.family
                            font.pixelSize: Style.font.title
                            font.bold: true
                            elide: Text.ElideRight
                            maximumLineCount: 2
                            wrapMode: Text.Wrap
                        }
                        Text {
                            width: parent.width
                            visible: text !== ""
                            text: root.trackArtist
                            textFormat: Text.PlainText
                            color: root.bar ? root.bar.foreground : root.tint
                            opacity: 0.8
                            font.family: Style.font.family
                            font.pixelSize: Style.font.body
                            elide: Text.ElideRight
                        }
                        Text {
                            width: parent.width
                            visible: text !== ""
                            text: root.trackAlbum
                            textFormat: Text.PlainText
                            color: root.bar ? root.bar.foreground : root.tint
                            opacity: 0.55
                            font.family: Style.font.family
                            font.pixelSize: Style.font.bodySmall
                            elide: Text.ElideRight
                        }
                    }
                }

                // Progress: elapsed time, seek bar and length. Click, drag or
                // scroll to seek; the knob shows only on hover or drag.
                RowLayout {
                    width: parent.width
                    spacing: Style.space(10)
                    visible: root.hasTrack && root.player.lengthSupported && root.player.length > 0

                    Text {
                        text: root.formatTime(seek.shown)
                        color: root.bar ? root.bar.foreground : root.tint
                        opacity: 0.6
                        font.family: Style.font.family
                        font.pixelSize: Style.font.caption
                    }

                    Item {
                        id: seek
                        Layout.fillWidth: true
                        Layout.preferredHeight: Style.space(14)

                        property bool dragging: false
                        property real dragValue: 0
                        readonly property real length: root.player ? Math.max(1, root.player.length) : 1
                        readonly property real shown: dragging ? dragValue : (root.player ? root.player.position : 0)
                        readonly property real progress: Math.max(0, Math.min(1, shown / length))
                        readonly property bool hot: root.canSeek && (seekMouse.containsMouse || dragging)
                        readonly property color fg: root.bar ? root.bar.foreground : root.tint

                        Rectangle {
                            id: track
                            y: Math.round((parent.height - height) / 2)
                            width: parent.width
                            height: 4
                            radius: height / 2
                            color: Qt.rgba(seek.fg.r, seek.fg.g, seek.fg.b, seek.hot ? 0.28 : 0.18)
                            Behavior on color { ColorAnimation { duration: 120 } }

                            Rectangle {
                                height: parent.height
                                radius: parent.radius
                                color: seek.fg
                                width: parent.width * seek.progress
                            }
                        }

                        Rectangle {
                            width: Style.space(11)
                            height: width
                            radius: width / 2
                            color: seek.fg
                            y: Math.round((parent.height - height) / 2)
                            x: Math.max(0, Math.min(seek.width - width, seek.width * seek.progress - width / 2))
                            opacity: seek.hot ? 1 : 0
                            scale: seek.hot ? 1 : 0.4
                            Behavior on opacity { NumberAnimation { duration: 120 } }
                            Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
                        }

                        MouseArea {
                            id: seekMouse
                            anchors.fill: parent
                            enabled: root.canSeek
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor

                            function valueAt(x) {
                                return Math.max(0, Math.min(1, x / width)) * seek.length
                            }
                            onPressed: function (mouse) {
                                seek.dragValue = valueAt(mouse.x)
                                seek.dragging = true
                            }
                            onPositionChanged: function (mouse) {
                                if (seek.dragging) seek.dragValue = valueAt(mouse.x)
                            }
                            onReleased: {
                                root.seekTo(seek.dragValue)
                                seek.dragging = false
                            }
                            onWheel: function (wheel) { root.seekBy(wheel.angleDelta.y > 0 ? 5 : -5) }
                        }
                    }

                    Text {
                        text: root.formatTime(root.player ? root.player.length : 0)
                        color: root.bar ? root.bar.foreground : root.tint
                        opacity: 0.6
                        font.family: Style.font.family
                        font.pixelSize: Style.font.caption
                    }
                }

                PanelSeparator {
                    visible: root.hasTrack
                    foreground: root.bar ? root.bar.foreground : root.tint
                }

                // Transport controls
                RowLayout {
                    width: parent.width
                    visible: root.hasTrack
                    spacing: Style.space(8)

                    Button {
                        Layout.fillWidth: true
                        iconText: "󰒮"
                        enabled: root.player && root.player.canGoPrevious
                        foreground: root.bar ? root.bar.foreground : root.tint
                        onClicked: root.previousTrack()
                    }
                    Button {
                        Layout.fillWidth: true
                        iconText: root.playing ? "󰏤" : "󰐊"
                        bordered: true
                        enabled: root.player && root.player.canTogglePlaying
                        foreground: root.bar ? root.bar.foreground : root.tint
                        onClicked: root.playPause()
                    }
                    Button {
                        Layout.fillWidth: true
                        iconText: "󰒭"
                        enabled: root.player && root.player.canGoNext
                        foreground: root.bar ? root.bar.foreground : root.tint
                        onClicked: root.nextTrack()
                    }
                }

                Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    text: root.player && root.player.identity ? "Playing on " + root.player.identity : ""
                    textFormat: Text.PlainText
                    visible: root.hasTrack && text !== ""
                    color: root.bar ? root.bar.foreground : root.tint
                    opacity: 0.45
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption
                }
            }
        }
    }

    // Keeps the progress bar moving while the card is open.
    Timer {
        interval: 1000
        repeat: true
        running: root.opened && root.playing
        onTriggered: if (root.player) root.player.positionChanged()
    }
}
