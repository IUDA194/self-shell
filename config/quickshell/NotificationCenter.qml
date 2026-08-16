import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland

PanelWindow {
    id: window

    Theme { id: theme }

    property var entries: []
    property bool dnd: false
    property bool grouped: true
    property real revealProgress: 0
    property bool animateReveal: false
    readonly property var groups: buildGroups(entries)
    readonly property color background: theme.background
    readonly property color surface: theme.surface
    readonly property color surfaceHigh: theme.surfaceAlt
    readonly property color foreground: theme.foreground
    readonly property color muted: theme.muted
    readonly property color accent: theme.accent

    signal closeRequested
    signal clearRequested
    signal dndToggleRequested
    signal groupingToggleRequested
    signal dismissRequested(var notification)

    function buildGroups(source) {
        const groups = []
        const positions = ({})
        for (let i = 0; i < source.length; ++i) {
            const entry = source[i]
            const notification = entry.notification
            const rawName = notification.appName || notification.desktopEntry || ""
            const normalized = rawName.toLowerCase()
            const systemSenders = ["", "notify-send", "system", "systemd", "quickshell"]
            const isSystem = systemSenders.indexOf(normalized) >= 0
            const name = isSystem ? "Системные" : rawName
            const key = name.toLowerCase()
            let position = positions[key]
            if (position === undefined) {
                position = groups.length
                positions[key] = position
                groups.push({
                    name: name,
                    icon: isSystem
                        ? "preferences-system-notifications"
                        : (notification.appIcon || notification.desktopEntry || ""),
                    entries: []
                })
            }
            groups[position].entries.push(entry)
        }
        return groups
    }

    function countText(count) {
        const mod10 = count % 10
        const mod100 = count % 100
        if (mod10 === 1 && mod100 !== 11)
            return count + " уведомление"
        if (mod10 >= 2 && mod10 <= 4 && (mod100 < 12 || mod100 > 14))
            return count + " уведомления"
        return count + " уведомлений"
    }

    anchors.top: true
    anchors.bottom: true
    anchors.left: true
    anchors.right: true
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
    WlrLayershell.namespace: "quickshell-notification-center"

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

    Shortcut {
        sequence: "Escape"
        onActivated: window.closeRequested()
    }

    Rectangle {
        anchors.fill: parent
        color: theme.scrim
        opacity: window.revealProgress

        MouseArea {
            anchors.fill: parent
            onClicked: window.closeRequested()
        }

        Rectangle {
            id: drawer
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.margins: 16
            width: Math.min(454, parent.width - 32)
            radius: 28
            color: window.background
            border.width: 1
            border.color: theme.outline
            opacity: window.revealProgress
            transform: Translate { x: 32 * (1 - window.revealProgress) }

            MouseArea { anchors.fill: parent }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 18
                spacing: 14

                RowLayout {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 48
                    spacing: 10

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0

                        Text {
                            text: entries.length > 0
                                ? window.countText(entries.length)
                                : "Уведомления"
                            color: window.foreground
                            font.family: "Noto Sans"
                            font.pixelSize: 18
                            font.weight: Font.DemiBold
                        }

                        Text {
                            text: window.dnd ? "Не беспокоить включено" : "Последние события"
                            color: window.muted
                            font.family: "Noto Sans"
                            font.pixelSize: 11
                        }
                    }

                    Rectangle {
                        Layout.preferredWidth: 38
                        Layout.preferredHeight: 38
                        radius: 19
                        color: window.grouped
                            ? theme.selected
                            : (groupMouse.containsMouse ? theme.hover : theme.surface)

                        Behavior on color { ColorAnimation { duration: 120 } }

                        Text {
                            anchors.centerIn: parent
                            text: "󰘸"
                            color: window.grouped ? window.foreground : window.muted
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 14
                        }

                        MouseArea {
                            id: groupMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: window.groupingToggleRequested()
                        }
                    }

                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 52
                    radius: 18
                    color: theme.overlay
                    border.width: 1
                    border.color: theme.outline

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 15
                        anchors.rightMargin: 12

                        Text {
                            Layout.fillWidth: true
                            text: window.dnd ? "Уведомления приглушены" : "Не беспокоить"
                            color: theme.foreground
                            font.family: "Noto Sans"
                            font.pixelSize: 12
                            font.weight: Font.DemiBold
                        }

                        Rectangle {
                            width: 46
                            height: 26
                            radius: 13
                            color: window.dnd ? window.accent : theme.surfaceAlt

                            Behavior on color { ColorAnimation { duration: 140 } }

                            Rectangle {
                                x: window.dnd ? parent.width - width - 4 : 4
                                anchors.verticalCenter: parent.verticalCenter
                                width: 18
                                height: 18
                                radius: 9
                                color: theme.foreground

                                Behavior on x {
                                    NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: window.dndToggleRequested()
                            }
                        }
                    }
                }

                ListView {
                    id: list
                    visible: entries.length > 0 && !window.grouped
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    model: entries
                    spacing: 9
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds

                    ScrollBar.vertical: ScrollBar {
                        policy: ScrollBar.AsNeeded
                        width: 4
                        contentItem: Rectangle {
                            implicitWidth: 4
                            radius: 2
                            color: theme.accent
                            opacity: 0.65
                        }
                    }

                    delegate: NotificationCard {
                        required property var modelData
                        width: list.width
                        notification: modelData.notification
                        createdAt: modelData.createdAt
                        onDismissRequested: window.dismissRequested(notification)
                    }
                }

                ListView {
                    id: groupedList
                    visible: entries.length > 0 && window.grouped
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    model: window.groups
                    spacing: 9
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds

                    ScrollBar.vertical: ScrollBar {
                        policy: ScrollBar.AsNeeded
                        width: 4
                        contentItem: Rectangle {
                            implicitWidth: 4
                            radius: 2
                            color: theme.accent
                            opacity: 0.65
                        }
                    }

                    delegate: NotificationGroup {
                        required property var modelData
                        width: groupedList.width
                        group: modelData
                        onDismissRequested: notification => window.dismissRequested(notification)
                    }
                }

                Item {
                    visible: entries.length === 0
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    Column {
                        anchors.centerIn: parent
                        spacing: 12

                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: "󰂛"
                            color: theme.surfaceAlt
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 40
                        }

                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: "Всё спокойно"
                            color: window.muted
                            font.family: "Noto Sans"
                            font.pixelSize: 14
                            font.weight: Font.DemiBold
                        }

                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: "Новые уведомления появятся здесь"
                            color: theme.outline
                            font.family: "Noto Sans"
                            font.pixelSize: 11
                        }
                    }
                }
            }

            Rectangle {
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.margins: 24
                width: 46
                height: 46
                radius: 23
                visible: entries.length > 0
                color: floatingClearMouse.containsMouse ? theme.accentHover : window.accent
                border.width: 1
                border.color: theme.foregroundSoft

                Behavior on color { ColorAnimation { duration: 120 } }
                Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
                scale: floatingClearMouse.pressed ? 0.92 : 1

                Text {
                    anchors.centerIn: parent
                    text: "󰆴"
                    color: window.background
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 16
                }

                MouseArea {
                    id: floatingClearMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: window.clearRequested()
                }
            }
        }
    }
}
