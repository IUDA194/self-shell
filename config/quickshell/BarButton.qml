import QtQuick
import QtQuick.Controls

Item {
    id: root

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
        color: mouse.containsMouse ? "#3e3834" : (root.active ? "#352f2b" : "transparent")

        Behavior on color {
            ColorAnimation { duration: 120 }
        }
    }

    Text {
        id: label
        anchors.centerIn: parent
        color: root.accent ? "#a67c49" : "#ccc2b7"
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

    ToolTip {
        id: tip
        parent: root
        x: root.width + 14
        y: Math.round((root.height - height) / 2)
        visible: mouse.containsMouse && root.tooltip.length > 0
        delay: 320
        timeout: 5000
        padding: 0
        margins: 0
        popupType: Popup.Window
        closePolicy: Popup.NoAutoClose

        contentItem: Row {
            spacing: 8
            leftPadding: 11
            rightPadding: 12
            topPadding: 8
            bottomPadding: 8

            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: 4
                height: 4
                radius: 2
                color: "#a67c49"
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: root.tooltip
                color: "#d4c9bd"
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: 11
                font.weight: Font.Medium
                renderType: Text.NativeRendering
            }
        }

        background: Item {
            Rectangle {
                anchors.fill: parent
                anchors.leftMargin: 2
                anchors.topMargin: 3
                color: "#59000000"
                radius: 8
            }

            Rectangle {
                anchors.fill: parent
                color: "#f23a332f"
                border.width: 1
                border.color: "#9a746961"
                radius: 8
            }
        }

        enter: Transition {
            ParallelAnimation {
                NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 130; easing.type: Easing.OutCubic }
                NumberAnimation { property: "scale"; from: 0.96; to: 1; duration: 130; easing.type: Easing.OutCubic }
            }
        }

        exit: Transition {
            ParallelAnimation {
                NumberAnimation { property: "opacity"; from: 1; to: 0; duration: 90; easing.type: Easing.InCubic }
                NumberAnimation { property: "scale"; from: 1; to: 0.98; duration: 90; easing.type: Easing.InCubic }
            }
        }
    }
}
