import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Ui

// Now playing card, opened from the bar widget (BarWidget.qml): artwork,
// track details, progress (SeekBar.qml) and controls, plus a notice when
// cava is missing (CavaNotice.qml).
// Keys: Space/Enter play/pause, ←/→ (h/l) seek 5 s, ↑/↓ (k/j) volume,
// n/p next/previous, 0–9 jump to 0–90 %, Esc close.
KeyboardPanel {
    id: card

    // ---- Inputs -------------------------------------------------------------
    // The bar widget: player, track details, playback actions and open state.
    required property Item widget
    // Local artwork copy from ArtworkFetcher.qml, or empty for the placeholder.
    property string artPath: ""
    property bool cavaChecked: false
    property bool cavaInstalled: false
    property string cavaInstallCommand: ""

    // ---- Outputs ------------------------------------------------------------
    // The artwork copy could not be decoded; the widget asks for a fresh one.
    signal artLoadFailed()

    // ---- Colours ------------------------------------------------------------
    // tint: the bar text colour, for accents. fg: the bar's foreground, for text.
    readonly property color tint: widget.tint
    readonly property color fg: widget.bar ? widget.bar.foreground : tint

    // ---- Panel --------------------------------------------------------------
    owner: widget
    bar: widget.bar
    open: widget.opened
    focusTarget: keys
    contentWidth: card.fittedContentWidth(Style.space(320))
    contentHeight: card.fittedContentHeight(column.implicitHeight)

    // ---- Content ------------------------------------------------------------
    PanelKeyCatcher {
        id: keys
        anchors.fill: parent
        onActivateRequested: card.widget.playPause()
        onCloseRequested: card.widget.close()
        onMoveRequested: function (dx, dy) {
            if (dx !== 0) card.widget.seekBy(dx * 5)
            if (dy !== 0) card.widget.changeVolume(-dy * 0.05)
        }
        onTextKey: function (t) {
            var key = t.toLowerCase()
            if (key === "n") card.widget.nextTrack()
            else if (key === "p") card.widget.previousTrack()
            else if (key >= "0" && key <= "9" && card.widget.canSeek) card.widget.seekTo(card.widget.player.length * Number(key) / 10)
        }

        // Keeps the progress bar moving while the card is open, starting at
        // once when it opens or playback resumes. Lives here because the
        // panel itself only takes visual items.
        Timer {
            interval: 1000
            repeat: true
            triggeredOnStart: true
            running: card.widget.opened && card.widget.playing && !card.widget.isLive
            onTriggered: if (card.widget.player) card.widget.player.positionChanged()
        }

        Column {
            id: column
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            spacing: Style.space(14)

            CavaNotice {
                width: parent.width
                visible: card.cavaChecked && !card.cavaInstalled
                command: card.cavaInstallCommand
                foreground: card.fg
                tint: card.tint
            }

            // Shown instead of the player when there is no track.
            Column {
                width: parent.width
                visible: !card.widget.hasTrack
                topPadding: Style.space(10)
                bottomPadding: Style.space(10)
                spacing: Style.space(6)

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "󰎊"
                    color: card.fg
                    opacity: 0.35
                    font.family: Style.font.family
                    font.pixelSize: Style.font.display
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "Nothing playing"
                    color: card.fg
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
                    color: card.fg
                    opacity: 0.45
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption
                }
            }

            // Artwork + track details
            RowLayout {
                width: parent.width
                height: Style.space(72)
                visible: card.widget.hasTrack
                spacing: Style.space(14)

                Rectangle {
                    Layout.preferredWidth: Style.space(72)
                    Layout.preferredHeight: Style.space(72)
                    Layout.alignment: Qt.AlignTop
                    radius: Style.cornerRadius
                    color: Qt.rgba(card.tint.r, card.tint.g, card.tint.b, 0.08)
                    clip: true

                    Image {
                        id: art
                        anchors.fill: parent
                        source: card.artPath ? "file://" + card.artPath : ""
                        sourceSize.width: 256
                        sourceSize.height: 256
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        visible: status === Image.Ready
                        onStatusChanged: if (status === Image.Error) card.artLoadFailed()
                    }
                    Text {
                        anchors.centerIn: parent
                        visible: art.status !== Image.Ready
                        text: "󰎆"
                        color: card.tint
                        opacity: 0.5
                        font.family: Style.font.family
                        font.pixelSize: Style.font.display
                    }
                }

                // A fixed-height, clipped frame so a two-line title never
                // grows the row (and pushes the progress bar down)
                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true

                    Column {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Style.space(3)

                        Text {
                            width: parent.width
                            text: card.widget.trackTitle
                            textFormat: Text.PlainText
                            color: card.fg
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
                            text: card.widget.trackArtist
                            textFormat: Text.PlainText
                            color: card.fg
                            opacity: 0.8
                            font.family: Style.font.family
                            font.pixelSize: Style.font.body
                            elide: Text.ElideRight
                        }
                        Text {
                            width: parent.width
                            visible: text !== ""
                            text: card.widget.trackAlbum
                            textFormat: Text.PlainText
                            color: card.fg
                            opacity: 0.55
                            font.family: Style.font.family
                            font.pixelSize: Style.font.bodySmall
                            elide: Text.ElideRight
                        }
                    }
                }
            }

            SeekBar {
                width: parent.width
                visible: card.widget.hasTrack && card.widget.player.lengthSupported && card.widget.player.length > 0
                widget: card.widget
                foreground: card.fg
            }

            PanelSeparator {
                visible: card.widget.hasTrack
                foreground: card.fg
            }

            // Transport controls
            RowLayout {
                width: parent.width
                visible: card.widget.hasTrack
                spacing: Style.space(8)

                Button {
                    Layout.fillWidth: true
                    iconText: "󰒮"
                    enabled: card.widget.player && card.widget.player.canGoPrevious
                    foreground: card.fg
                    onClicked: card.widget.previousTrack()
                }
                Button {
                    Layout.fillWidth: true
                    iconText: card.widget.playing ? "󰏤" : "󰐊"
                    bordered: true
                    enabled: card.widget.player && card.widget.player.canTogglePlaying
                    foreground: card.fg
                    onClicked: card.widget.playPause()
                }
                Button {
                    Layout.fillWidth: true
                    iconText: "󰒭"
                    enabled: card.widget.player && card.widget.player.canGoNext
                    foreground: card.fg
                    onClicked: card.widget.nextTrack()
                }
            }

            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: card.widget.player && card.widget.player.identity ? "Playing on " + card.widget.clipText(card.widget.player.identity) : ""
                textFormat: Text.PlainText
                visible: card.widget.hasTrack && text !== ""
                color: card.fg
                opacity: 0.45
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
            }
        }
    }
}
