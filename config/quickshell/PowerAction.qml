import QtQuick

Item {
    id: root

    Theme { id: theme }

    property string icon: ""
    property string title: ""
    property bool destructive: false

    signal clicked

    implicitWidth: 198
    implicitHeight: 112
    scale: mouse.containsMouse ? 1.025 : 1

    Behavior on scale {
        NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
    }

    Rectangle {
        anchors.fill: parent
        radius: 16
        color: mouse.containsMouse ? theme.accentHoverSubtle : theme.accentSubtle

        Behavior on color { ColorAnimation { duration: 140 } }
    }

    Column {
        anchors.centerIn: parent
        spacing: 11

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.icon
            color: root.destructive ? theme.critical : theme.accentHover
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: 24
            font.weight: Font.DemiBold
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.title
            color: theme.foreground
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: 13
            font.weight: Font.Bold
        }
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
