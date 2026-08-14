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
    signal dismissRequested(var notification)

    onClosingChanged: exitProgress = closing ? 1 : 0

    Behavior on exitProgress {
        NumberAnimation {
            duration: 320
            easing.type: Easing.BezierSpline
            easing.bezierCurve: [0.4, 0, 0.2, 1, 1, 1]
        }
    }

    anchors.bottom: true
    anchors.right: true
    margins.bottom: 18
    margins.right: 18
    implicitWidth: 380
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
            duration: 500
            easing.type: Easing.BezierSpline
            easing.bezierCurve: [0.38, 1.21, 0.22, 1, 1, 1]
        }
    }

    Column {
        id: toastStack
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        spacing: 10
        opacity: window.revealProgress * (1 - window.exitProgress)
        scale: (0.84 + 0.16 * window.revealProgress) * (1 - 0.08 * window.exitProgress)
        transformOrigin: Item.BottomRight
        transform: Translate {
            x: (window.width + 28) * (1 - window.revealProgress)
                + (window.width + 36) * window.exitProgress
            y: 30 * (1 - window.revealProgress) + 24 * window.exitProgress
        }

        move: Transition {
            NumberAnimation {
                property: "y"
                duration: 420
                easing.type: Easing.BezierSpline
                easing.bezierCurve: [0.38, 1.21, 0.22, 1, 1, 1]
            }
        }

        add: Transition {
            ParallelAnimation {
                NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 220; easing.type: Easing.OutCubic }
                NumberAnimation { property: "scale"; from: 0.88; to: 1; duration: 360; easing.type: Easing.OutBack }
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
                swipeEnabled: true
                onDismissRequested: window.dismissRequested(notification)
            }
        }
    }
}
