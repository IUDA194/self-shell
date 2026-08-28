import QtQuick
import Quickshell
import Quickshell.Wayland

PanelWindow {
    id: window

    property var entries: []
    property bool closing: false
    property real exitProgress: 0
    property real revealProgress: 0
    property bool animateReveal: false
    property bool minimal: false
    property string placement: "bottom-right"
    readonly property bool topAligned: placement.startsWith("top")
    readonly property bool bottomAligned: placement.startsWith("bottom")
    readonly property bool leftAligned: placement.endsWith("left") || placement === "left"
    readonly property bool rightAligned: placement.endsWith("right") || placement === "right"
    signal dismissRequested(var notification)

    onClosingChanged: exitProgress = closing ? 1 : 0

    Behavior on exitProgress {
        NumberAnimation {
            duration: window.minimal ? 90 : 320
            easing.type: Easing.BezierSpline
            easing.bezierCurve: [0.4, 0, 0.2, 1, 1, 1]
        }
    }

    anchors.top: topAligned || (!topAligned && !bottomAligned)
    anchors.bottom: bottomAligned
    anchors.left: leftAligned || (!leftAligned && !rightAligned)
    anchors.right: rightAligned
    margins.left: !leftAligned && !rightAligned ? Math.max(1, (screen.width - implicitWidth) / 2) : (minimal ? 1 : 18)
    margins.top: !topAligned && !bottomAligned ? Math.max(1, (screen.height - implicitHeight) / 2) : (minimal ? 1 : 18)
    margins.bottom: window.minimal ? 1 : 18
    margins.right: window.minimal ? 1 : 18
    implicitWidth: window.minimal ? 420 : 380
    implicitHeight: toastStack.implicitHeight
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell-notification-toast"

    onVisibleChanged: {
        if (!visible) {
            animateReveal = false
            revealProgress = 0
            return
        }
        animateReveal = false
        revealProgress = 0
        Qt.callLater(function() {
            if (window.visible) {
                window.animateReveal = true
                window.revealProgress = 1
            }
        })
    }

    Behavior on revealProgress {
        enabled: window.animateReveal
        NumberAnimation {
            duration: window.minimal ? 100 : 500
            easing.type: Easing.BezierSpline
            easing.bezierCurve: [0.38, 1.21, 0.22, 1, 1, 1]
        }
    }

    Column {
        id: toastStack
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: window.topAligned ? parent.top : undefined
        anchors.bottom: window.bottomAligned ? parent.bottom : undefined
        anchors.verticalCenter: !window.topAligned && !window.bottomAligned ? parent.verticalCenter : undefined
        spacing: window.minimal ? 2 : 10
        opacity: window.revealProgress * (1 - window.exitProgress)
        scale: window.minimal
            ? (0.98 + 0.02 * window.revealProgress)
            : (0.84 + 0.16 * window.revealProgress) * (1 - 0.08 * window.exitProgress)
        transformOrigin: window.topAligned
            ? (window.leftAligned ? Item.TopLeft : Item.TopRight)
            : (window.leftAligned ? Item.BottomLeft : Item.BottomRight)
        transform: Translate {
            x: (window.placement.endsWith("-left") ? -1 : 1)
                * (window.width + (window.minimal ? 4 : 28)) * (1 - window.revealProgress)
                + (window.width + 36) * window.exitProgress
            y: (window.minimal ? 4 : 30) * (1 - window.revealProgress) + 24 * window.exitProgress
        }

        move: Transition {
            NumberAnimation {
                property: "y"
                duration: window.minimal ? 90 : 420
                easing.type: Easing.BezierSpline
                easing.bezierCurve: [0.38, 1.21, 0.22, 1, 1, 1]
            }
        }

        add: Transition {
            ParallelAnimation {
                NumberAnimation { property: "opacity"; from: 0; to: 1; duration: window.minimal ? 70 : 220; easing.type: Easing.OutCubic }
                NumberAnimation { property: "scale"; from: window.minimal ? 0.98 : 0.88; to: 1; duration: window.minimal ? 90 : 360; easing.type: Easing.OutBack }
            }
        }

        Repeater {
            model: window.entries.slice().reverse()

            NotificationCard {
                required property var modelData
                width: window.width
                notification: modelData.notification
                createdAt: modelData.createdAt
                compact: true
                minimal: window.minimal
                swipeEnabled: true
                onDismissRequested: window.dismissRequested(notification)
            }
        }
    }
}
