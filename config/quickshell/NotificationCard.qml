import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets

Rectangle {
    id: root

    required property var notification
    property double createdAt: Date.now()
    property bool compact: false

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
    color: cardMouse.containsMouse ? "#f04f443e" : "#b5473d37"
    border.width: notification.urgency === 2 ? 1 : 0
    border.color: "#c4746e"

    Behavior on color { ColorAnimation { duration: 120 } }

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

    ColumnLayout {
        id: content
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
                color: notification.urgency === 2 ? "#3ec4746e" : "#35b58e66"

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
                    color: notification.urgency === 2 ? "#dc948c" : "#c9a06d"
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
                    color: "#e0d6ca"
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
                        color: "#8f8278"
                        elide: Text.ElideRight
                        font.family: "Noto Sans"
                        font.pixelSize: 9
                    }

                    Text {
                        id: ageLabel
                        text: root.ageText()
                        color: "#746961"
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 9
                    }
                }
            }

            Rectangle {
                Layout.preferredWidth: 28
                Layout.preferredHeight: 28
                radius: 9
                color: closeMouse.containsMouse ? "#62514843" : "transparent"

                Text {
                    anchors.centerIn: parent
                    text: "×"
                    color: "#a99c91"
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 16
                }

                MouseArea {
                    id: closeMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.dismissRequested()
                }
            }
        }

        Text {
            visible: notification.body.length > 0
            Layout.fillWidth: true
            text: notification.body
            textFormat: Text.PlainText
            color: "#c8bdb1"
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
                    color: actionMouse.containsMouse ? "#735d4c40" : "#59463b35"

                    Text {
                        id: actionText
                        anchors.centerIn: parent
                        text: modelData.text
                        color: "#d6cabe"
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 9
                        font.weight: Font.DemiBold
                    }

                    MouseArea {
                        id: actionMouse
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
