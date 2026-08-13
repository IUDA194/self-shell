import QtQuick
import Quickshell
import Quickshell.Wayland

PanelWindow {
    id: window

    property var entry: null
    property real revealProgress: 0
    property bool animateReveal: false
    signal dismissRequested(var notification)

    anchors.top: true
    anchors.right: true
    margins.top: 18
    margins.right: 18
    implicitWidth: 380
    implicitHeight: cardLoader.item ? cardLoader.item.implicitHeight : 1
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
        revealProgress = 0.92
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

    Loader {
        id: cardLoader
        anchors.left: parent.left
        anchors.right: parent.right
        active: window.entry !== null
        opacity: window.revealProgress
        scale: 0.985 + 0.015 * window.revealProgress
        transform: Translate { x: 24 * (1 - window.revealProgress) }

        sourceComponent: Component {
            NotificationCard {
                width: window.width
                notification: window.entry.notification
                createdAt: window.entry.createdAt
                compact: true
                onDismissRequested: window.dismissRequested(notification)
            }
        }
    }
}
