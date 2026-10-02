import QtQuick
import Quickshell.Io

// Gives the card a safe local copy of the player's artwork. The artwork URL
// is never loaded directly: art-fetch.sh copies it to the runtime directory
// after checking scheme, size, type and pixel dimensions, and the card shows
// that copy (`path`). Fetched once per track in the background, so the card
// opens with the artwork already there. Draws nothing itself.
Item {
    id: root

    // ---- Inputs -------------------------------------------------------------
    // The player's artwork URL (https, file or data URL), as reported.
    property string url: ""
    // Set by the widget once check.sh has confirmed the runtime directory.
    // Nothing is fetched before that.
    property bool runtimeReady: false
    property string privateDir: ""
    // Minimal environment for the helper: PATH, HOME and XDG_RUNTIME_DIR only.
    property var environment: ({})
    property string scriptPath: ""

    // ---- Outputs ------------------------------------------------------------
    // Only the copy made for the current URL is shown, never a previous track's.
    readonly property string path: url && url === fetchedFor ? fetchedPath : ""

    // ---- Cache --------------------------------------------------------------
    // The last copy received and the URL it was made for.
    property string fetchedPath: ""
    property string fetchedFor: ""
    // Tags this instance's files; the bar creates one widget per monitor.
    readonly property string tag: "w" + Math.floor(Math.random() * 1e12).toString(36)
    // The last 10 copies are remembered (keyed by a hash, since data URLs can be
    // megabytes), so going back to a recent track shows its artwork at once.
    readonly property int cacheSize: 10
    property var cache: ({})
    property var cacheOrder: []
    function remember(forUrl, copyPath) {
        var key = Qt.md5(forUrl)
        if (!(key in cache)) {
            cacheOrder.push(key)
            if (cacheOrder.length > cacheSize) delete cache[cacheOrder.shift()]
        }
        cache[key] = copyPath
    }
    function forget(forUrl) {
        var key = Qt.md5(forUrl)
        delete cache[key]
        cacheOrder = cacheOrder.filter(function (k) { return k !== key })
    }
    onUrlChanged: {
        if (!url || url === fetchedFor) return
        var cached = cache[Qt.md5(url)]
        if (cached) {
            fetchedPath = cached
            fetchedFor = url
            return
        }
        debounce.restart()
    }
    // ---- Fetching -----------------------------------------------------------
    // A copy that cannot be decoded is fetched again once; if the fresh copy
    // fails too, the placeholder stays instead of refetching in a loop.
    property string retriedFor: ""
    function loadFailed() {
        if (!url) return
        forget(url)
        if (retriedFor === url) {
            fetchedPath = ""
            return
        }
        retriedFor = url
        fetchedFor = ""
        debounce.restart()
    }
    // A fetch that failed (for example offline) is retried when the card opens.
    function retry() {
        if (url && !path && !fetch.running) debounce.restart()
    }
    onRuntimeReadyChanged: retry()
    Timer {
        id: debounce
        interval: 80
        onTriggered: root.start()
    }
    // A running fetch is stopped first; the new one starts once it has exited.
    // Fetches start at most every 500 ms, so a player that keeps changing its
    // artwork URL cannot make the widget spawn processes continuously.
    property real lastStart: 0
    Timer {
        id: throttle
        onTriggered: root.start()
    }
    function start() {
        if (fetch.running) {
            fetch.pending = true
            fetch.running = false
            return
        }
        if (!url || !runtimeReady || url.length > 6000000) return
        var wait = lastStart + 500 - Date.now()
        if (wait > 0) {
            throttle.interval = wait
            throttle.restart()
            return
        }
        lastStart = Date.now()
        fetch.request = url
        fetch.running = true
    }
    Process {
        id: fetch
        property string request: ""
        property bool pending: false
        command: ["/usr/bin/timeout", "-k", "2", "20", "/usr/bin/bash", root.scriptPath]
        clearEnvironment: true
        environment: Object.assign({ ART_TAG: root.tag }, root.environment)
        stdinEnabled: true
        onStarted: {
            write(request)
            stdinEnabled = false
        }
        onExited: {
            stdinEnabled = true
            if (pending) {
                pending = false
                root.start()
            }
        }
        stdout: StdioCollector {
            onStreamFinished: {
                var copy = text.trim()
                var dir = root.privateDir + "/"
                var valid = copy.indexOf(dir) === 0 && copy.indexOf("\n") < 0
                if (valid) root.remember(fetch.request, copy)
                if (fetch.request !== root.url) return
                root.fetchedPath = valid ? copy : ""
                root.fetchedFor = fetch.request
            }
        }
    }
}
