import QtQuick
import Quickshell
import Quickshell.Wayland

PanelWindow {
    id: window

    property string pendingAction: ""
    property real revealProgress: 0
    property bool animateReveal: false
    readonly property bool confirming: pendingAction.length > 0

    signal closeRequested
    signal lockRequested
    signal suspendRequested
    signal rebootRequested
    signal poweroffRequested

    anchors.top: true
    anchors.bottom: true
    anchors.left: true
    anchors.right: true
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    WlrLayershell.namespace: "quickshell-power-menu"

    function close() {
        pendingAction = ""
        closeRequested()
    }

    function confirm() {
        const action = pendingAction
        close()
        if (action === "reboot")
            rebootRequested()
        else if (action === "poweroff")
            poweroffRequested()
    }

    onVisibleChanged: {
        if (!visible) {
            animateReveal = false
            revealProgress = 0
            return
        }
        pendingAction = ""
        keyboardScope.forceActiveFocus()
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

    FocusScope {
        id: keyboardScope
        anchors.fill: parent
        focus: true
        Keys.onEscapePressed: window.close()
        Keys.onReturnPressed: if (window.confirming) window.confirm()

        Rectangle {
            anchors.fill: parent
            color: "#b50b0908"
            opacity: window.revealProgress

            MouseArea {
                anchors.fill: parent
                onClicked: window.close()
            }
        }

        Item {
            id: menu
            anchors.centerIn: parent
            width: 408
            height: window.confirming ? 190 : 236
            opacity: window.revealProgress
            scale: 0.985 + 0.015 * window.revealProgress

            MouseArea { anchors.fill: parent }

            Item {
                anchors.fill: parent
                visible: !window.confirming

                Grid {
                    anchors.centerIn: parent
                    columns: 2
                    columnSpacing: 12
                    rowSpacing: 12

                    PowerAction {
                        icon: ""
                        title: "Заблокировать"
                        onClicked: {
                            window.close()
                            window.lockRequested()
                        }
                    }

                    PowerAction {
                        icon: ""
                        title: "Сон"
                        onClicked: {
                            window.close()
                            window.suspendRequested()
                        }
                    }

                    PowerAction {
                        icon: ""
                        title: "Перезагрузить"
                        destructive: true
                        onClicked: window.pendingAction = "reboot"
                    }

                    PowerAction {
                        icon: ""
                        title: "Выключить"
                        destructive: true
                        onClicked: window.pendingAction = "poweroff"
                    }
                }
            }

            Item {
                anchors.fill: parent
                visible: window.confirming

                Text {
                    anchors.top: parent.top
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: window.pendingAction === "reboot"
                        ? "Перезагрузить компьютер?"
                        : "Выключить компьютер?"
                    color: "#e3d9cd"
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 18
                    font.weight: Font.Bold
                }

                Row {
                    anchors.bottom: parent.bottom
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 12

                    PowerAction {
                        width: 170
                        height: 112
                        icon: "󰜺"
                        title: "Отмена"
                        onClicked: window.pendingAction = ""
                    }

                    PowerAction {
                        width: 170
                        height: 112
                        icon: window.pendingAction === "reboot" ? "" : ""
                        title: window.pendingAction === "reboot" ? "Перезагрузить" : "Выключить"
                        destructive: true
                        onClicked: window.confirm()
                    }
                }
            }
        }
    }

}
