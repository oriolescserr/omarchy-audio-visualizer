import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import qs.Commons

// Progress row of the card (Card.qml): elapsed time, seek bar and length.
// Click, drag or scroll to seek; the knob shows only on hover or drag. On a
// live stream the times are hidden, the bar stays full and a LIVE marker
// takes the length's place; scroll and arrows still send relative seeks.
RowLayout {
    id: root

    // ---- Inputs -------------------------------------------------------------
    // The bar widget (BarWidget.qml): player, playback state and seek actions.
    required property Item widget
    property color foreground: "white"

    // ---- Layout -------------------------------------------------------------
    spacing: Style.space(10)

    // "m:ss", or "h:mm:ss" from one hour up.
    function formatTime(seconds) {
        var s = Math.max(0, Math.floor(Number(seconds) || 0))
        var m = Math.floor(s / 60)
        var h = Math.floor(m / 60)
        var ss = ("0" + (s % 60)).slice(-2)
        return h > 0 ? h + ":" + ("0" + (m % 60)).slice(-2) + ":" + ss : m + ":" + ss
    }

    Text {
        visible: !root.widget.isLive
        text: root.formatTime(seek.shown)
        textFormat: Text.PlainText
        color: root.foreground
        opacity: 0.6
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
    }

    // The seek bar itself: track, filled part, knob and the mouse handling.
    Item {
        id: seek
        Layout.fillWidth: true
        Layout.preferredHeight: Style.space(14)

        readonly property Item widget: root.widget
        property bool dragging: false
        property real dragValue: 0
        readonly property real length: widget.player ? Math.max(1, widget.player.length) : 1
        // The player only reports its position about once a second, so
        // between reports it is extrapolated on every frame. A report
        // that disagrees by more than 0.3 s (seek, new track) re-syncs it.
        property real anchorPos: 0
        property real anchorMs: Date.now()
        property real nowMs: Date.now()
        readonly property real predicted: widget.playing ? anchorPos + (nowMs - anchorMs) / 1000 : anchorPos
        readonly property real shown: dragging ? dragValue : Math.max(0, Math.min(length, predicted))
        readonly property real progress: widget.isLive ? 1 : Math.max(0, Math.min(1, shown / length))
        readonly property bool hot: widget.canSeek && (seekMouse.containsMouse || dragging)
        readonly property color fg: root.foreground

        function sync(force) {
            if (!widget.player) return
            var actual = Number(widget.player.position) || 0
            nowMs = Date.now()
            if (force || Math.abs(predicted - actual) > 0.3) {
                anchorPos = actual
                anchorMs = nowMs
            }
        }
        Component.onCompleted: sync(true)
        Connections {
            target: seek.widget.player
            function onPositionChanged() { seek.sync(false) }
        }
        Connections {
            target: seek.widget
            function onPlayerChanged() { seek.sync(true) }
            function onPlayingChanged() { seek.sync(true) }
            function onOpenedChanged() { if (seek.widget.opened) seek.sync(true) }
        }
        FrameAnimation {
            running: seek.widget.opened && seek.widget.playing && !seek.widget.isLive && seek.visible
            onTriggered: seek.nowMs = Date.now()
        }

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

        // Knob: even-sized like the track and placed from the
        // track's own position, so both share the same centre
        // line. Drawn as a true curve, since a rounded Rectangle
        // this small is tessellated into a visible polygon.
        Shape {
            id: knobCircle
            width: 2 * Math.round(Style.space(10) / 2)
            height: width
            y: track.y + (track.height - height) / 2
            x: Math.max(0, Math.min(seek.width - width, seek.width * seek.progress - width / 2))
            preferredRendererType: Shape.CurveRenderer
            antialiasing: true
            opacity: seek.hot ? 1 : 0
            scale: seek.hot ? 1 : 0.4
            Behavior on opacity { NumberAnimation { duration: 120 } }
            Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }

            ShapePath {
                fillColor: seek.fg
                strokeColor: "transparent"
                PathAngleArc {
                    centerX: knobCircle.width / 2
                    centerY: knobCircle.height / 2
                    radiusX: knobCircle.width / 2
                    radiusY: knobCircle.height / 2
                    startAngle: 0
                    sweepAngle: 360
                }
            }
        }

        MouseArea {
            id: seekMouse
            anchors.fill: parent
            enabled: seek.widget.canSeek || (seek.widget.isLive && seek.widget.canSeekRelative)
            hoverEnabled: true
            cursorShape: seek.widget.canSeek ? Qt.PointingHandCursor : Qt.ArrowCursor

            function valueAt(x) {
                return Math.max(0, Math.min(1, x / width)) * seek.length
            }
            onPressed: function (mouse) {
                if (!seek.widget.canSeek) return
                seek.dragValue = valueAt(mouse.x)
                seek.dragging = true
            }
            onPositionChanged: function (mouse) {
                if (seek.dragging) seek.dragValue = valueAt(mouse.x)
            }
            onReleased: {
                if (!seek.dragging) return
                seek.widget.seekTo(seek.dragValue)
                seek.dragging = false
            }
            onWheel: function (wheel) { seek.widget.seekBy(wheel.angleDelta.y > 0 ? 5 : -5) }
        }
    }

    Text {
        visible: !root.widget.isLive
        text: root.formatTime(root.widget.player ? root.widget.player.length : 0)
        textFormat: Text.PlainText
        color: root.foreground
        opacity: 0.6
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
    }
    // Takes the length's place on a live stream.
    Row {
        visible: root.widget.isLive
        spacing: Style.space(5)

        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: Style.space(6)
            height: width
            radius: width / 2
            color: Color.urgent
        }
        Text {
            text: "LIVE"
            textFormat: Text.PlainText
            color: root.foreground
            opacity: 0.6
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
        }
    }
}
