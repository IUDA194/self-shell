import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland

ShellRoot {
    id: root

    Theme { id: theme }

    // Native password-store picker.

    readonly property color background: theme.background
    readonly property color surface: theme.surface
    readonly property color surfaceHover: theme.surfaceAlt
    readonly property color foreground: theme.foreground
    readonly property color muted: theme.muted
    readonly property color accent: theme.accent

    property var entries: []
    property var results: []
    property bool closing: false
    property real revealProgress: 0.92

    function entryName(path) {
        const parts = path.split("/")
        return parts[parts.length - 1]
    }

    function entryGroup(path) {
        const separator = path.lastIndexOf("/")
        return separator < 0 ? "Личное" : path.slice(0, separator).split("/").join("  ›  ")
    }

    function fuzzyScore(value, query) {
        const text = value.toLowerCase()
        const needle = query.toLowerCase().trim()
        if (needle.length === 0)
            return 1
        if (text.startsWith(needle))
            return 1000 - text.length
        const direct = text.indexOf(needle)
        if (direct >= 0)
            return 750 - direct * 4

        let position = 0
        let gap = 0
        for (let i = 0; i < needle.length; ++i) {
            const found = text.indexOf(needle[i], position)
            if (found < 0)
                return -1
            gap += found - position
            position = found + 1
        }
        return 400 - gap * 5
    }

    function refreshResults() {
        const query = searchField.text.trim()
        const matches = []
        for (let i = 0; i < entries.length; ++i) {
            const score = fuzzyScore(entries[i], query)
            if (score >= 0)
                matches.push({ path: entries[i], score: score, order: i })
        }
        matches.sort(function(left, right) {
            return left.score === right.score ? left.order - right.order : right.score - left.score
        })
        results = matches
        resultList.currentIndex = results.length > 0 ? 0 : -1
    }

    function copyEntry(index) {
        if (index < 0 || index >= results.length)
            return
        Quickshell.execDetached([
            Quickshell.env("HOME") + "/.config/hypr/quickshell-password-backend.sh",
            "--copy",
            results[index].path
        ])
        closeMenu()
    }

    function autotypeEntry(index) {
        if (index < 0 || index >= results.length)
            return
        Quickshell.execDetached([
            Quickshell.env("HOME") + "/.config/hypr/quickshell-password-backend.sh",
            "--autotype",
            results[index].path
        ])
        closeMenu()
    }

    function closeMenu() {
        if (closing)
            return
        closing = true
        revealProgress = 0
        closeTimer.restart()
    }

    Process {
        command: [
            Quickshell.env("HOME") + "/.config/hypr/quickshell-password-backend.sh",
            "--list"
        ]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                root.entries = text.split("\n").map(value => value.trim()).filter(value => value.length > 0)
                root.refreshResults()
            }
        }
    }

    Timer {
        id: closeTimer
        interval: 510
        onTriggered: Qt.quit()
    }

    Component.onCompleted: Qt.callLater(function() {
        searchField.forceActiveFocus()
        root.revealProgress = 1
    })

    Behavior on revealProgress {
        NumberAnimation {
            duration: 500
            easing.type: Easing.BezierSpline
            easing.bezierCurve: [0.38, 1.21, 0.22, 1, 1, 1]
        }
    }

    PanelWindow {
        screen: {
            const monitor = Hyprland.focusedMonitor
            if (!monitor)
                return Quickshell.screens[0]
            return Quickshell.screens.find(screen => screen.name === monitor.name)
                || Quickshell.screens[0]
        }
        visible: true
        anchors.top: true
        anchors.right: true
        anchors.bottom: true
        anchors.left: true
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
        WlrLayershell.namespace: "quickshell-passwords"

        Shortcut {
            sequence: "Escape"
            onActivated: root.closeMenu()
        }

        Rectangle {
            anchors.fill: parent
            color: "#a80b0908"
            opacity: root.revealProgress

            MouseArea {
                anchors.fill: parent
                onClicked: root.closeMenu()
            }

            Rectangle {
                id: panel
                anchors.centerIn: parent
                width: Math.min(parent.width - 64, 720)
                height: Math.min(parent.height - 80, 510)
                radius: 18
                color: root.background
                border.width: 1
                border.color: "#82746961"
                opacity: root.revealProgress
                scale: 0.975 + 0.025 * root.revealProgress

                MouseArea { anchors.fill: parent }

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 14
                    spacing: 10

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 44
                        spacing: 12

                        Rectangle {
                            Layout.preferredWidth: 40
                            Layout.preferredHeight: 40
                            radius: 12
                            color: "#35b58e66"

                            Text {
                                anchors.centerIn: parent
                                text: "󰌆"
                                color: root.accent
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 18
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 1

                            Text {
                                text: "Пароли"
                                color: root.foreground
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 16
                                font.weight: Font.Bold
                            }

                            Text {
                                text: root.entries.length + " записей в хранилище"
                                color: root.muted
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 9
                            }
                        }

                        Text {
                            text: "Enter  автоввод    Клик  копировать"
                            color: root.muted
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 9
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 48
                        radius: 12
                        color: "#b1423832"
                        border.width: searchField.activeFocus ? 1 : 0
                        border.color: root.accent

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 15
                            anchors.rightMargin: 15
                            spacing: 11

                            Text {
                                text: "󰍉"
                                color: root.accent
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 15
                            }

                            TextField {
                                id: searchField
                                Layout.fillWidth: true
                                color: root.foreground
                                placeholderText: "Найти запись"
                                placeholderTextColor: root.muted
                                selectionColor: "#756054"
                                selectedTextColor: root.foreground
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 13
                                background: null
                                onTextChanged: root.refreshResults()

                                Keys.onDownPressed: function(event) {
                                    if (root.results.length > 0) {
                                        resultList.currentIndex = (resultList.currentIndex + 1) % root.results.length
                                        resultList.positionViewAtIndex(resultList.currentIndex, ListView.Contain)
                                    }
                                    event.accepted = true
                                }
                                Keys.onUpPressed: function(event) {
                                    if (root.results.length > 0) {
                                        resultList.currentIndex = (resultList.currentIndex - 1 + root.results.length) % root.results.length
                                        resultList.positionViewAtIndex(resultList.currentIndex, ListView.Contain)
                                    }
                                    event.accepted = true
                                }
                                Keys.onReturnPressed: function(event) {
                                    root.autotypeEntry(resultList.currentIndex)
                                    event.accepted = true
                                }
                                Keys.onEnterPressed: function(event) {
                                    root.autotypeEntry(resultList.currentIndex)
                                    event.accepted = true
                                }
                            }

                            Text {
                                text: root.results.length.toString()
                                color: root.muted
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 10
                            }
                        }
                    }

                    ListView {
                        id: resultList
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        model: root.results
                        currentIndex: root.results.length > 0 ? 0 : -1
                        spacing: 6
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds
                        highlightMoveDuration: 100

                        ScrollBar.vertical: ScrollBar {
                            policy: ScrollBar.AsNeeded
                            width: 4
                            contentItem: Rectangle {
                                implicitWidth: 4
                                radius: 2
                                color: root.accent
                                opacity: 0.65
                            }
                        }

                        delegate: Rectangle {
                            id: row
                            required property int index
                            required property var modelData
                            width: resultList.width
                            height: 55
                            radius: 12
                            color: row.ListView.isCurrentItem || rowMouse.containsMouse
                                ? root.surfaceHover : root.surface

                            Behavior on color { ColorAnimation { duration: 100 } }

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 14
                                anchors.rightMargin: 55
                                spacing: 12

                                Rectangle {
                                    Layout.preferredWidth: 34
                                    Layout.preferredHeight: 34
                                    radius: 10
                                    color: "#2eb58e66"

                                    Text {
                                        anchors.centerIn: parent
                                        text: ""
                                        color: root.accent
                                        font.family: "JetBrainsMono Nerd Font"
                                        font.pixelSize: 13
                                    }
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 1

                                    Text {
                                        Layout.fillWidth: true
                                        text: root.entryName(modelData.path)
                                        color: root.foreground
                                        elide: Text.ElideRight
                                        font.family: "JetBrainsMono Nerd Font"
                                        font.pixelSize: 12
                                        font.weight: Font.DemiBold
                                    }

                                    Text {
                                        Layout.fillWidth: true
                                        text: root.entryGroup(modelData.path)
                                        color: root.muted
                                        elide: Text.ElideMiddle
                                        font.family: "JetBrainsMono Nerd Font"
                                        font.pixelSize: 9
                                    }
                                }

                                Text {
                                    text: "󰆏"
                                    color: row.ListView.isCurrentItem || rowMouse.containsMouse
                                        ? root.accent : root.muted
                                    font.family: "JetBrainsMono Nerd Font"
                                    font.pixelSize: 14
                                }
                            }

                            MouseArea {
                                id: rowMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onEntered: resultList.currentIndex = index
                                onClicked: root.copyEntry(index)
                            }

                            Rectangle {
                                anchors.right: parent.right
                                anchors.rightMargin: 10
                                anchors.verticalCenter: parent.verticalCenter
                                width: 34
                                height: 34
                                radius: 10
                                color: autotypeMouse.containsMouse ? "#55b58e66" : "transparent"
                                z: 2

                                Behavior on color { ColorAnimation { duration: 100 } }

                                Text {
                                    anchors.centerIn: parent
                                    text: "󰌌"
                                    color: autotypeMouse.containsMouse ? root.accent : root.muted
                                    font.family: "JetBrainsMono Nerd Font"
                                    font.pixelSize: 14
                                }

                                MouseArea {
                                    id: autotypeMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onEntered: resultList.currentIndex = index
                                    onClicked: root.autotypeEntry(index)
                                }
                            }
                        }
                    }

                    Item {
                        visible: root.results.length === 0
                        Layout.fillWidth: true
                        Layout.fillHeight: true

                        Text {
                            anchors.centerIn: parent
                            text: root.entries.length === 0 ? "Хранилище пусто" : "Ничего не найдено"
                            color: root.muted
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 13
                        }
                    }
                }
            }
        }
    }
}
