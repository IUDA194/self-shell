import QtQuick
import QtQuick.Controls

Item {
    id: root

    Theme { id: theme }

    property alias text: label.text
    property alias color: label.color
    property alias fontPixelSize: label.font.pixelSize
    property string tooltip: ""
    property string command: ""
    property bool active: false
    property bool accent: false

    signal clicked
    signal wheelUp
    signal wheelDown

    implicitWidth: 44
    implicitHeight: 32

    Rectangle {
        anchors.centerIn: parent
        width: 34
        height: 28
        radius: 6
        color: mouse.containsMouse ? theme.hover : (root.active ? theme.surface : "transparent")

        Behavior on color {
            ColorAnimation { duration: 120 }
        }
    }

    Text {
        id: label
        anchors.centerIn: parent
        color: root.accent ? theme.accent : theme.foregroundSoft
        font.family: "JetBrainsMono Nerd Font"
        font.pixelSize: 13
        font.weight: Font.DemiBold
        renderType: Text.NativeRendering
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
        onWheel: event => {
            if (event.angleDelta.y > 0)
                root.wheelUp()
            else if (event.angleDelta.y < 0)
                root.wheelDown()
        }
    }

    ThemedToolTip {
        target: root
        labelText: root.tooltip
        shown: mouse.containsMouse
    }
}
