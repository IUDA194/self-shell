import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets

Rectangle {
    id: root

    required property var group
    property bool expanded: group.entries.length === 1

    signal dismissRequested(var notification)

    implicitHeight: header.height + (expanded ? cards.implicitHeight + 12 : 0)
    radius: 22
    color: "#d9362e2a"
    border.width: 1
    border.color: expanded ? "#7060554c" : "#4f443e"
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
            color: headerMouse.containsMouse ? "#554a403a" : "transparent"
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
                color: "#59483d36"

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
                    color: "#c9a06d"
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 14
                }
            }

            Text {
                Layout.fillWidth: true
                text: root.group.name
                color: "#ddd3c6"
                elide: Text.ElideRight
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: 13
                font.weight: Font.Bold
            }

            Rectangle {
                Layout.preferredWidth: 34
                Layout.preferredHeight: 26
                radius: 13
                color: "#594b423c"

                Text {
                    anchors.centerIn: parent
                    text: root.group.entries.length.toString()
                    color: "#c5b8ac"
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 9
                    font.weight: Font.Bold
                }
            }

            Text {
                text: "󰅀"
                color: "#978a80"
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
