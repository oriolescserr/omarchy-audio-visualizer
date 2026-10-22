import QtQuick
import Quickshell.Io

// Runs cava while something plays and exposes its output as `levels`: one
// value from 0 to 1 per bar. Draws nothing itself; BarWidget.qml draws the
// bars from `levels`.
Item {
    id: root

    // ---- Inputs -------------------------------------------------------------
    property int barCount: 10
    property bool playing: false
    // Set by the widget once check.sh has confirmed the runtime directory and
    // the cava binary. Nothing is written or started before that.
    property bool runtimeReady: false
    property bool installed: false
    property string privateDir: ""
    // Minimal environment for cava: PATH, HOME and XDG_RUNTIME_DIR only.
    property var environment: ({})
    // The fixed cava.conf template shipped with the plugin.
    property string templatePath: ""

    // ---- Outputs ------------------------------------------------------------
    // One value from 0 to 1 per bar, or empty while cava is not running.
    property var levels: []

    // ---- Config -------------------------------------------------------------
    // cava.conf with the validated bar count, written to the private runtime
    // directory before cava starts.
    property bool configReady: false
    property bool configFailed: false
    FileView {
        id: template
        path: root.templatePath
        blockLoading: true
    }
    FileView {
        id: config
        path: root.privateDir ? root.privateDir + "/cava.conf" : ""
        blockWrites: true
        atomicWrites: true
        printErrors: false
        onSaveFailed: root.configFailed = true
    }
    // Writes are synchronous (blockWrites). Marking the config ready on the next
    // tick restarts a running cava so it picks up a new bar count.
    function writeConfig() {
        configReady = false
        configFailed = false
        if (!runtimeReady || !config.path) return
        config.setText(template.text().replace(/^\[general\]$/m, "[general]\nbars = " + barCount))
        Qt.callLater(function () { root.configReady = !root.configFailed })
    }
    onBarCountChanged: writeConfig()
    onRuntimeReadyChanged: writeConfig()
    Component.onCompleted: writeConfig()

    // ---- Process ------------------------------------------------------------
    // cava keeps running for a moment after playback stops, so a quick pause or
    // a track change does not restart it.
    property bool linger: false
    onPlayingChanged: {
        if (playing) return
        linger = true
        lingerTimer.restart()
    }
    Timer {
        id: lingerTimer
        interval: 2000
        onTriggered: root.linger = false
    }

    // cava's stderr goes to /dev/null through a fixed wrapper (the config path
    // is a separate argument, never part of the shell text). Its stdout format
    // is set by cava.conf: at most 32 numbers of 0-100 separated by ';' per
    // line, so every line is bounded by construction.
    Process {
        running: (root.playing || root.linger) && root.configReady && root.installed
        command: ["/usr/bin/bash", "-c", "exec /usr/bin/cava -p \"$1\" 2>/dev/null", "cava", config.path]
        clearEnvironment: true
        environment: root.environment
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
}
