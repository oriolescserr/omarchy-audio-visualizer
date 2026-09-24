import QtQuick

// Single-line label that sizes to its text up to `maxWidth`. Longer text
// scrolls like a ticker: a pause, then a continuous loop with a gap between
// repeats. Short text stays static.
Item {
    id: root

    property string text: ""
    property color color: "white"
    property string fontFamily: ""
    property int pixelSize: 12
    property bool bold: false
    property real maxWidth: 240
    property bool running: true
    property int gap: 40
    property real speed: 0.04      // px per ms
    property int pauseMs: 1400

    readonly property real textWidth: measure.implicitWidth
    readonly property bool overflowing: textWidth > maxWidth

    implicitWidth: Math.min(textWidth, maxWidth)
    implicitHeight: measure.implicitHeight
    clip: true

    Text {
        id: measure
        visible: false
        textFormat: Text.PlainText
        text: root.text
        font.family: root.fontFamily
        font.pixelSize: root.pixelSize
        font.bold: root.bold
    }

    Row {
        id: strip
        spacing: root.gap

        Repeater {
            model: root.overflowing ? 2 : 1
            Text {
                textFormat: Text.PlainText
                text: root.text
                color: root.color
                font.family: root.fontFamily
                font.pixelSize: root.pixelSize
                font.bold: root.bold
            }
        }
    }

    SequentialAnimation {
        id: ticker
        running: root.overflowing && root.running
        loops: Animation.Infinite
        onRunningChanged: if (!running) strip.x = 0

        PropertyAction { target: strip; property: "x"; value: 0 }
        PauseAnimation { duration: root.pauseMs }
        NumberAnimation {
            target: strip
            property: "x"
            to: -(root.textWidth + root.gap)
            duration: Math.max(1, (root.textWidth + root.gap) / root.speed)
        }
    }

    onTextChanged: strip.x = 0
}
