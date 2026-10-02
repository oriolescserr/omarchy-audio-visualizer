import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import qs.Commons
import qs.Ui

// Spectrum bars driven by cava. Collapses to zero size and runs nothing
// unless an MPRIS player is playing. Colour follows the bar's own text
// colour, so themes and transparent-bar mode apply automatically.
//   hover        : a tooltip with the current track (TrackTooltip.qml)
//   click        : a card with artwork, track details, progress and controls
//                  (Card.qml)
//   middle click : play/pause
// This file holds the player state and the actions every part shares, and
// wires up the parts that live in their own files: Cava.qml runs cava,
// ArtworkFetcher.qml copies the artwork, and Card.qml builds the card.
BarWidget {
    id: root
    moduleName: "oriolus.audio-visualizer"

    // ---- Bar geometry and colour --------------------------------------------
    // The bar count comes from the widget settings ("Number of bars"),
    // clamped to the 4-32 range the manifest allows.
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
    // Bar text colour, used for the bars and as the card's accent tint.
    readonly property color tint: bar ? bar.barForeground : "#cacccc"

    // ---- Player state -------------------------------------------------------
    // The first MPRIS player that is playing drives the bars, the tooltip and
    // the card. Everything else reads `player` and the track fields below.
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

    // Player metadata is capped so an oversized title cannot stall text layout.
    function clipText(value) {
        var s = String(value || "")
        return s.length > 300 ? s.slice(0, 300) + "…" : s
    }
    readonly property string trackTitle: player ? (clipText(player.trackTitle) || "Unknown track") : ""
    readonly property string trackArtist: player ? clipText(player.trackArtist) : ""
    readonly property string trackAlbum: player ? clipText(player.trackAlbum) : ""
    readonly property bool hasTrack: !!(player && (player.trackTitle || player.trackArtist))

    // ---- Card open state ----------------------------------------------------
    // Fillet recognises a widget with a panel by these three properties
    // (ipcTarget, opened, controller) and joins its corners to the open card.
    property string ipcTarget: "oriolus.audio-visualizer"
    property var controller: ({})
    property bool opened: false
    function close() { opened = false }
    function open() { opened = true }
    function toggle() { opened = !opened }
    onPlayerChanged: if (!player) opened = false

    // ---- Playback actions ---------------------------------------------------
    // Live streams report an effectively infinite length (browsers send the
    // largest 64-bit value), so anything over a week is treated as live. Players
    // send no stream start time, and browsers report a position that restarts
    // every few seconds, so a live stream shows no times.
    readonly property bool isLive: !!(player && player.lengthSupported
                                      && (!isFinite(player.length) || player.length > 7 * 24 * 3600))
    // Absolute seeks need a real length; live streams seek relative to where
    // they are, which works when the stream keeps a buffer behind the live edge.
    readonly property bool canSeekRelative: !!(player && player.canSeek && player.positionSupported)
    readonly property bool canSeek: canSeekRelative && player.lengthSupported && player.length > 0 && !isLive

    function playPause() { if (player && player.canTogglePlaying) player.togglePlaying() }
    function nextTrack() { if (player && player.canGoNext) player.next() }
    function previousTrack() { if (player && player.canGoPrevious) player.previous() }

    function seekTo(seconds) {
        if (!canSeek || !isFinite(seconds)) return
        player.position = Math.max(0, Math.min(player.length - 1, seconds))
        player.positionChanged()
    }
    function seekBy(seconds) {
        if (!isFinite(seconds)) return
        if (isLive) {
            // Passed on for players that keep a buffer; browsers ignore it.
            if (canSeekRelative) player.seek(seconds)
            return
        }
        if (canSeek) seekTo(player.position + seconds)
    }

    function changeVolume(delta) {
        if (!player || !player.volumeSupported || !player.canControl) return
        player.volume = Math.max(0, Math.min(1, player.volume + delta))
    }

    // ---- IPC ----------------------------------------------------------------
    // omarchy-shell oriolus.audio-visualizer <function>
    IpcHandler {
        target: "oriolus.audio-visualizer"
        function toggle(): void { root.toggle() }
        function open(): void { root.open() }
        function close(): void { root.close() }
        function playPause(): void { root.playPause() }
        function next(): void { root.nextTrack() }
        function previous(): void { root.previousTrack() }
        function forward(): void { root.seekBy(10) }
        function back(): void { root.seekBy(-10) }
    }

    // ---- Reveal animation ---------------------------------------------------
    // 0 = hidden and zero-sized, 1 = fully shown. Drives size and opacity
    // together so the widget eases in and out without popping.
    property real reveal: (playing || opened) ? 1 : 0
    Behavior on reveal { NumberAnimation { duration: 320; easing.type: Easing.InOutCubic } }

    // Size once fully shown; the real size grows towards it with `reveal`.
    readonly property int fullWidth: vertical ? barSize : span + 2 * margin
    readonly property int fullHeight: vertical ? span + 2 * margin : barSize

    visible: reveal > 0.001
    opacity: reveal
    clip: true
    implicitWidth: vertical ? fullWidth : Math.round(fullWidth * reveal)
    implicitHeight: vertical ? Math.round(fullHeight * reveal) : fullHeight

    // ---- Card anchor and open-panel line ------------------------------------
    // Where the widget ends up once fully shown. The card is centred on this
    // instead of on the widget, so opening it while nothing plays does not
    // slide it along as the widget grows. The edge that stays put depends on
    // the bar section: left/top keeps its start, right/bottom its end, and
    // center its middle.
    readonly property var barSlot: {
        for (var p = parent; p; p = p.parent)
            if (typeof p.region === "string" && p.region && "activeItem" in p) return p
        return null
    }
    readonly property string barRegion: barSlot ? barSlot.region : "left"
    readonly property real growShift: barRegion === "right" ? 1 : barRegion === "center" ? 0.5 : 0
    Item {
        id: cardAnchor
        x: root.vertical ? 0 : root.growShift * (root.width - root.fullWidth)
        y: root.vertical ? root.growShift * (root.height - root.fullHeight) : 0
        width: root.fullWidth
        height: root.fullHeight
    }

    // The bar centres its open-panel line on the slot, which grows with the
    // widget, so the line would slide too. A sub-pixel length hint hides the
    // bar's line, and this one, styled the same, is centred on cardAnchor. It
    // lives in the slot so the widget's clip cannot cut it while it grows.
    readonly property real openPanelIndicatorWidth: 0.001
    readonly property real openPanelIndicatorHeight: 0.001
    Rectangle {
        readonly property int inset: Style.space(2)
        readonly property int extent: Math.max(Style.space(10), Math.round((root.vertical ? root.fullHeight : root.fullWidth) * 0.55))
        readonly property string barPosition: root.bar ? root.bar.position : "top"

        parent: root.barSlot || root
        visible: opacity > 0
        opacity: root.barSlot && root.barSlot.panelOpen && !root.barSlot.dragSource ? 0.9 : 0
        color: Color.accent
        radius: Math.min(width, height) / 2
        width: root.vertical ? Style.space(2) : extent
        height: root.vertical ? extent : Style.space(2)
        x: root.vertical
            ? (barPosition === "left" ? root.width - width - inset : inset)
            : Math.round(cardAnchor.x + (cardAnchor.width - width) / 2)
        y: root.vertical
            ? Math.round(cardAnchor.y + (cardAnchor.height - height) / 2)
            : (barPosition === "top" ? root.height - height - inset : inset)
        z: 50

        Behavior on opacity { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
    }

    // ---- Helpers and environment check --------------------------------------
    // Programs run by absolute path with a minimal environment. cava needs HOME
    // to start and XDG_RUNTIME_DIR to reach PipeWire.
    readonly property string runtimeDir: Quickshell.env("XDG_RUNTIME_DIR") || ""
    // Absolute path of a file shipped with the plugin (scripts, cava.conf).
    function pluginFile(name) {
        return decodeURIComponent(Qt.resolvedUrl(name).toString().replace(/^file:\/\//, ""))
    }
    readonly property var helperEnvironment: ({
        PATH: "/usr/bin",
        HOME: Quickshell.env("HOME") || "",
        XDG_RUNTIME_DIR: runtimeDir
    })

    // Private runtime directory, prepared and checked by check.sh (owned by this
    // user, mode 0700, not a symlink). Nothing is written until it is ready.
    readonly property string privateDir: runtimeDir ? runtimeDir + "/oriolus-audio-visualizer" : ""
    property bool runtimeReady: false

    // check.sh runs on load and whenever the card opens, so installing cava
    // later clears the notice without restarting the shell. cava only starts
    // once the check has confirmed it exists. Its output is two short lines.
    property bool cavaChecked: false
    property bool cavaInstalled: false
    readonly property string cavaInstallCommand: "omarchy pkg add cava"
    Process {
        id: envCheck
        command: ["/usr/bin/timeout", "-k", "2", "5", "/usr/bin/bash", root.pluginFile("check.sh")]
        clearEnvironment: true
        environment: root.helperEnvironment
        stdout: StdioCollector {
            onStreamFinished: {
                var lines = text.split("\n")
                root.runtimeReady = lines.indexOf("runtime=ok") >= 0
                root.cavaInstalled = lines.indexOf("cava=yes") >= 0
                root.cavaChecked = true
            }
        }
    }
    // On load: check the environment, register for clicks with the bar and
    // seed the tooltip text.
    Component.onCompleted: {
        envCheck.running = true
        syncClickRegistration()
        shownTitle = trackTitle
        shownArtist = trackArtist
    }
    onOpenedChanged: {
        if (!opened) return
        envCheck.running = true
        artwork.retry()
        // The player's position is only re-read when positionChanged is sent,
        // so without this the card opens where it was last left.
        if (player) player.positionChanged()
    }

    // ---- Bars ---------------------------------------------------------------
    // Cava.qml turns the audio into one level per bar; the bars just draw them.
    Cava {
        id: cava
        barCount: root.barCount
        playing: root.playing
        runtimeReady: root.runtimeReady
        installed: root.cavaInstalled
        privateDir: root.privateDir
        environment: root.helperEnvironment
        templatePath: root.pluginFile("cava.conf")
    }

    Repeater {
        model: root.barCount
        Rectangle {
            required property int index
            readonly property real level: cava.levels.length > index ? cava.levels[index] : 0
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

    // ---- Hover (tooltip) and click ------------------------------------------
    // The tooltip appears after a short hover and keeps the last title and
    // artist while it fades out, so it never blanks mid-fade.
    property bool tipWanted: false
    readonly property bool tipShown: tipWanted && playing && !opened && trackTitle !== ""
    property string shownTitle: ""
    property string shownArtist: ""
    onTrackTitleChanged: if (trackTitle) shownTitle = trackTitle
    onTrackArtistChanged: if (player) shownArtist = trackArtist

    Timer { id: tipDelay; interval: 400; onTriggered: root.tipWanted = true }

    // The bar wraps every module in a slot whose own MouseArea sets the cursor
    // and handles left clicks, but only for registered click targets with a
    // triggerPress(). Registering also lets an open panel forward a click on
    // this widget, as it does for the shell's own buttons.
    function triggerPress(button) {
        tipDelay.stop()
        tipWanted = false
        if (button === Qt.MiddleButton) playPause()
        else toggle()
    }
    property var registeredBar: null
    function syncClickRegistration() {
        if (registeredBar && registeredBar.unregisterClickTarget) registeredBar.unregisterClickTarget(root)
        registeredBar = bar
        if (registeredBar && registeredBar.registerClickTarget) registeredBar.registerClickTarget(root)
    }
    onBarChanged: syncClickRegistration()
    Component.onDestruction: if (registeredBar && registeredBar.unregisterClickTarget) registeredBar.unregisterClickTarget(root)

    MouseArea {
        id: hoverArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton
        onEntered: tipDelay.restart()
        onExited: { tipDelay.stop(); root.tipWanted = false }
        onClicked: function (mouse) { root.triggerPress(mouse.button) }
    }

    TrackTooltip {
        anchorItem: root
        barPosition: root.bar ? root.bar.position : "top"
        shown: root.tipShown
        title: root.shownTitle
        artist: root.shownArtist
    }

    // ---- Card ---------------------------------------------------------------
    // The artwork is fetched in the background even while the card is closed,
    // so it is already there when the card opens.
    ArtworkFetcher {
        id: artwork
        url: root.player && root.player.trackArtUrl ? root.player.trackArtUrl : ""
        runtimeReady: root.runtimeReady
        privateDir: root.privateDir
        environment: root.helperEnvironment
        scriptPath: root.pluginFile("art-fetch.sh")
    }

    Card {
        widget: root
        anchorItem: cardAnchor
        artPath: artwork.path
        cavaChecked: root.cavaChecked
        cavaInstalled: root.cavaInstalled
        cavaInstallCommand: root.cavaInstallCommand
        onArtLoadFailed: artwork.loadFailed()
    }
}
