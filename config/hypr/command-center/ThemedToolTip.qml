import QtQuick
import QtQuick.Controls

ToolTip {
    id: root

    required property Item target
    property string labelText: ""
    property bool shown: false
    property string placement: "right"
    property int gap: 12

    Theme { id: theme }

    parent: target
    x: placement === "left" ? -width - gap
        : placement === "right" ? target.width + gap
        : Math.round((target.width - width) / 2)
    y: placement === "top" ? -height - gap
        : placement === "bottom" ? target.height + gap
        : Math.round((target.height - height) / 2)
    visible: shown && labelText.length > 0
    delay: 280
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
            width: 5
            height: 5
            radius: 2.5
            color: theme.accent
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root.labelText
            color: theme.foreground
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: 11
            font.weight: Font.Medium
            renderType: Text.NativeRendering
        }
    }

    background: Item {
        Rectangle {
            anchors.fill: parent
            anchors.leftMargin: root.placement === "left" ? -2 : 2
            anchors.topMargin: 3
            color: theme.shadow
            radius: 9
        }

        Rectangle {
            anchors.fill: parent
            color: theme.overlayStrong
            border.width: 1
            border.color: theme.outline
            radius: 9
        }
    }

    enter: Transition {
        ParallelAnimation {
            NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 150; easing.type: Easing.OutCubic }
            NumberAnimation { property: "scale"; from: 0.94; to: 1; duration: 180; easing.type: Easing.OutBack }
        }
    }

    exit: Transition {
        ParallelAnimation {
            NumberAnimation { property: "opacity"; from: 1; to: 0; duration: 90; easing.type: Easing.InCubic }
            NumberAnimation { property: "scale"; from: 1; to: 0.97; duration: 90; easing.type: Easing.InCubic }
        }
    }
}
