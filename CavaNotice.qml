import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Ui

// Shown in the card (Card.qml) when cava is missing: the bars cannot be
// drawn without it. Offers the install command for copying; it is never run
// from here.
Rectangle {
    id: root

    // ---- Inputs -------------------------------------------------------------
    // The command shown in the code box and copied by the button.
    property string command: ""
    // Text colour, and the accent used for the box's fill and border.
    property color foreground: "white"
    property color tint: foreground

    // ---- Layout -------------------------------------------------------------
    implicitHeight: notice.implicitHeight + Style.space(20)
    color: Qt.rgba(tint.r, tint.g, tint.b, 0.06)
    border.width: 1
    border.color: Qt.rgba(tint.r, tint.g, tint.b, 0.25)
    radius: Style.cornerRadius

    Column {
        id: notice
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.margins: Style.space(12)
        spacing: Style.space(6)

        Text {
            text: "cava is not installed"
            color: root.foreground
            font.family: Style.font.family
            font.pixelSize: Style.font.body
            font.bold: true
        }
        Text {
            width: parent.width
            wrapMode: Text.Wrap
            text: "The spectrum bars need it. Install it with:"
            color: root.foreground
            opacity: 0.7
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
        }
        // Code box for the command, with the copy button inside it.
        Rectangle {
            width: parent.width
            implicitHeight: commandRow.implicitHeight + Style.space(8)
            color: Qt.rgba(0, 0, 0, 0.35)
            border.width: 1
            border.color: Qt.rgba(root.tint.r, root.tint.g, root.tint.b, 0.18)
            radius: Style.cornerRadius

            RowLayout {
                id: commandRow
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: Style.space(12)
                anchors.rightMargin: Style.space(4)
                spacing: Style.space(8)

                Text {
                    text: "$"
                    color: root.foreground
                    opacity: 0.4
                    font.family: Style.font.family
                    font.pixelSize: Style.font.body
                }
                Text {
                    Layout.fillWidth: true
                    text: root.command
                    textFormat: Text.PlainText
                    color: root.foreground
                    font.family: Style.font.family
                    font.pixelSize: Style.font.body
                }
                Button {
                    iconText: copiedTimer.running ? "󰄬" : "󰆏"
                    tooltipText: copiedTimer.running ? "Copied" : "Copy"
                    foreground: root.foreground
                    onClicked: {
                        Quickshell.clipboardText = root.command
                        copiedTimer.restart()
                    }
                    Timer { id: copiedTimer; interval: 1500 }
                }
            }
        }
    }
}
