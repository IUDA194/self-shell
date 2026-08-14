import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets

Rectangle {
    id: root

    Theme { id: theme }

    required property var notification
    property double createdAt: Date.now()
    property bool compact: false
    property bool swipeEnabled: false
    property bool dismissing: false
    property real dragOffset: 0

    signal dismissRequested

    function ageText() {
        const seconds = Math.max(0, Math.floor((Date.now() - createdAt) / 1000))
        if (seconds < 60)
            return "сейчас"
        const minutes = Math.floor(seconds / 60)
        if (minutes < 60)
            return minutes + " мин"
        const hours = Math.floor(minutes / 60)
        if (hours < 24)
            return hours + " ч"
        return Math.floor(hours / 24) + " д"
    }

    implicitHeight: content.implicitHeight + 22
    radius: 16
    color: cardMouse.containsMouse ? theme.surface : theme.background
    border.width: 1
    border.color: notification.urgency === 2
        ? theme.accent : theme.outline

    Behavior on color { ColorAnimation { duration: 120 } }

    transform: Translate { x: root.dragOffset }
    opacity: swipeEnabled ? Math.max(0.18, 1 - Math.abs(dragOffset) / (width * 0.9)) : 1
    scale: swipeEnabled ? 1 - Math.min(0.035, Math.abs(dragOffset) / width * 0.035) : 1

    Behavior on dragOffset {
        enabled: !swipeMouse.drag.active
        NumberAnimation {
            duration: root.dismissing ? 260 : 420
            easing.type: Easing.BezierSpline
            easing.bezierCurve: [0.38, 1.21, 0.22, 1, 1, 1]
        }
    }

    Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
    Behavior on scale { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

    Timer {
        id: swipeDismissTimer
        interval: 250
        onTriggered: root.dismissRequested()
    }

    Timer {
        interval: 60000
        running: true
        repeat: true
        onTriggered: ageLabel.text = root.ageText()
    }

    MouseArea {
        id: cardMouse
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.NoButton
    }

    MouseArea {
        id: swipeMouse
        z: 0
        anchors.fill: parent
        enabled: root.swipeEnabled && !root.dismissing
        hoverEnabled: true
        cursorShape: drag.active ? Qt.ClosedHandCursor : Qt.OpenHandCursor
        drag.target: swipeHandle
        drag.axis: Drag.XAxis
        drag.minimumX: -root.width
        drag.maximumX: root.width
        preventStealing: true

        onPressed: swipeHandle.x = root.dragOffset
        onPositionChanged: root.dragOffset = swipeHandle.x
        onReleased: {
            if (Math.abs(root.dragOffset) >= root.width * 0.28) {
                root.dismissing = true
                root.dragOffset = root.dragOffset < 0 ? -root.width * 1.15 : root.width * 1.15
                swipeDismissTimer.restart()
            } else {
                root.dragOffset = 0
            }
        }

        Item { id: swipeHandle; width: 1; height: 1 }
    }

    ColumnLayout {
        id: content
        z: 1
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 11
        spacing: 7

        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            Rectangle {
                Layout.preferredWidth: 38
                Layout.preferredHeight: 38
                radius: 19
                color: notification.urgency === 2 ? theme.surfaceAlt : theme.surface

                IconImage {
                    anchors.centerIn: parent
                    width: 21
                    height: 21
                    source: notification.appIcon.length > 0
                        ? Quickshell.iconPath(notification.appIcon, true) : ""
                    visible: source.toString().length > 0
                }

                Text {
                    anchors.centerIn: parent
                    visible: !parent.children[0].visible
                    text: notification.urgency === 2 ? "󰀦" : "󰂚"
                    color: notification.urgency === 2 ? theme.accentHover : theme.accent
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 15
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1

                Text {
                    Layout.fillWidth: true
                    text: notification.summary || notification.appName || "Уведомление"
                    color: theme.foreground
                    wrapMode: root.compact ? Text.NoWrap : Text.Wrap
                    elide: root.compact ? Text.ElideRight : Text.ElideNone
                    font.family: "Noto Sans"
                    font.pixelSize: 13
                    font.weight: Font.Bold
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6

                    Text {
                        Layout.fillWidth: true
                        text: notification.appName || "Система"
                        color: theme.muted
                        elide: Text.ElideRight
                        font.family: "Noto Sans"
                        font.pixelSize: 9
                    }

                    Text {
                        id: ageLabel
                        text: root.ageText()
                        color: theme.selected
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 9
                    }
                }
            }

            Rectangle {
                Layout.preferredWidth: 28
                Layout.preferredHeight: 28
                radius: 9
                color: closeMouse.containsMouse ? theme.surfaceAlt : "transparent"

                Text {
                    anchors.centerIn: parent
                    text: "×"
                    color: theme.muted
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 16
                }

                MouseArea {
                    id: closeMouse
                    z: 10
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (!root.swipeEnabled) {
                            root.dismissRequested()
                            return
                        }
                        root.dismissing = true
                        root.dragOffset = root.width * 1.15
                        swipeDismissTimer.restart()
                    }
                }
            }
        }

        Text {
            visible: notification.body.length > 0
            Layout.fillWidth: true
            text: notification.body
            textFormat: Text.PlainText
            color: theme.foregroundSoft
            wrapMode: Text.Wrap
            elide: root.compact ? Text.ElideRight : Text.ElideNone
            maximumLineCount: root.compact ? 2 : 1000
            font.family: "Noto Sans"
            font.pixelSize: 11
            lineHeight: 1.25
        }

        Flow {
            visible: notification.actions.length > 0
            Layout.fillWidth: true
            spacing: 6

            Repeater {
                model: notification.actions

                delegate: Rectangle {
                    required property var modelData
                    width: actionText.implicitWidth + 22
                    height: 30
                    radius: 9
                    color: actionMouse.containsMouse ? theme.surfaceAlt : theme.surface

                    Text {
                        id: actionText
                        anchors.centerIn: parent
                        text: modelData.text
                        color: theme.foreground
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 9
                        font.weight: Font.DemiBold
                    }

                    MouseArea {
                        id: actionMouse
                        z: 10
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: modelData.invoke()
                    }
                }
            }
        }
    }
}
