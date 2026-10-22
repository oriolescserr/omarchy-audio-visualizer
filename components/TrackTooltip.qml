import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

// Tooltip styled like the bar's native one: title above artist. Placed on the
// desktop side of `anchorItem`, whichever edge the bar is on. Shown by
// BarWidget.qml after a short hover; long titles scroll (Marquee.qml).
PopupWindow {
    id: tip

    // ---- Inputs -------------------------------------------------------------
    required property Item anchorItem
    // The bar's edge: "top", "bottom", "left" or "right".
    property string barPosition: "top"
    // Fades in when true and out when false; the window closes once faded.
    property bool shown: false
    property string title: ""
    property string artist: ""

    // ---- Window and placement -----------------------------------------------
    visible: shown || bubble.opacity > 0.01
    color: "transparent"
    implicitWidth: Math.ceil(bubble.implicitWidth)
    implicitHeight: Math.ceil(bubble.implicitHeight)

    anchor {
        id: tipAnchor
        window: tip.anchorItem.QsWindow.window
        adjustment: PopupAdjustment.Slide
        edges: Edges.Top | Edges.Left
        gravity: Edges.Bottom | Edges.Right
        rect.width: 1
        rect.height: 1

        onAnchoring: {
            var item = tip.anchorItem
            var win = item.QsWindow.window
            if (!win) return
            var pos = tip.barPosition
            var x = item.width / 2 - tip.implicitWidth / 2
            var y = item.height + 6
            if (pos === "bottom") y = -tip.implicitHeight - 6
            else if (pos === "left") { x = item.width + 6; y = item.height / 2 - tip.implicitHeight / 2 }
            else if (pos === "right") { x = -tip.implicitWidth - 6; y = item.height / 2 - tip.implicitHeight / 2 }
            var point = win.contentItem.mapFromItem(item, x, y)
            tipAnchor.rect.x = Math.round(point.x)
            tipAnchor.rect.y = Math.round(point.y)
        }
    }

    // ---- Bubble -------------------------------------------------------------
    BorderSurface {
        id: bubble
        implicitWidth: Math.max(titleLabel.implicitWidth, artistLabel.implicitWidth) + 28
        implicitHeight: column.implicitHeight + 14
        color: Color.tooltip.background
        borderSpec: Border.surfaceSpec("tooltip", "border", Color.tooltip.border, 1)
        radius: Style.cornerRadius
        opacity: tip.shown ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

        Column {
            id: column
            anchors.centerIn: parent
            spacing: 2

            Marquee {
                id: titleLabel
                anchors.horizontalCenter: parent.horizontalCenter
                text: tip.title
                color: Color.tooltip.text
                fontFamily: Style.font.family
                pixelSize: Style.font.subtitle
                bold: true
                running: tip.shown
            }
            Marquee {
                id: artistLabel
                anchors.horizontalCenter: parent.horizontalCenter
                visible: text !== ""
                text: tip.artist
                color: Color.tooltip.text
                opacity: 0.7
                fontFamily: Style.font.family
                pixelSize: Style.font.bodySmall
                running: tip.shown
            }
        }
    }
}
