import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets

Rectangle {
    id: root

    Theme { id: theme }

    required property var group
    property bool expanded: group.entries.length === 1

    signal dismissRequested(var notification)

    implicitHeight: header.height + (expanded ? cards.implicitHeight + 12 : 0)
    radius: 22
    color: theme.background
    border.width: 1
    border.color: expanded ? theme.accent : theme.outline
    clip: true

    Behavior on implicitHeight {
        NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
    }

    Item {
        id: header
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: 68

        Rectangle {
            anchors.fill: parent
            color: headerMouse.containsMouse ? theme.surface : "transparent"
            Behavior on color { ColorAnimation { duration: 110 } }
        }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 12
            anchors.rightMargin: 12
            spacing: 10

            Rectangle {
                Layout.preferredWidth: 44
                Layout.preferredHeight: 44
                radius: 22
                color: theme.surface

                IconImage {
                    id: appIcon
                    anchors.centerIn: parent
                    width: 25
                    height: 25
                    source: root.group.icon.length > 0
                        ? Quickshell.iconPath(root.group.icon, true) : ""
                    visible: source.toString().length > 0
                }

                Text {
                    anchors.centerIn: parent
                    visible: !appIcon.visible
                    text: "󰏖"
                    color: theme.accent
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 14
                }
            }

            Text {
                Layout.fillWidth: true
                text: root.group.name
                color: theme.foreground
                elide: Text.ElideRight
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: 13
                font.weight: Font.Bold
            }

            Rectangle {
                Layout.preferredWidth: 34
                Layout.preferredHeight: 26
                radius: 13
                color: theme.surfaceAlt

                Text {
                    anchors.centerIn: parent
                    text: root.group.entries.length.toString()
                    color: theme.foreground
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 9
                    font.weight: Font.Bold
                }
            }

            Text {
                text: "󰅀"
                color: theme.muted
                rotation: root.expanded ? 180 : 0
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: 16
                Behavior on rotation { NumberAnimation { duration: 160 } }
            }
        }

        MouseArea {
            id: headerMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.expanded = !root.expanded
        }
    }

    Column {
        id: cards
        anchors.top: header.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: 10
        anchors.rightMargin: 10
        anchors.bottomMargin: 10
        spacing: 8
        visible: root.expanded

        Repeater {
            model: root.group.entries

            delegate: NotificationCard {
                required property var modelData
                width: cards.width
                notification: modelData.notification
                createdAt: modelData.createdAt
                onDismissRequested: root.dismissRequested(notification)
            }
        }
    }
}
