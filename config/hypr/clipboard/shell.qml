import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland

ShellRoot {
    id: root

    readonly property color background: "#26201d"
    readonly property color surface: "#372d29"
    readonly property color surfaceAlt: "#4f443e"
    readonly property color selected: "#756054"
    readonly property color foreground: "#ddd3c6"
    readonly property color muted: "#9a8b80"
    readonly property color accent: "#b58e66"

    property var allItems: []
    property var results: []
    property bool keyboardNavigating: false
    property bool closing: false
    property real revealProgress: 0.92

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
        for (let i = 0; i < allItems.length; ++i) {
            const item = allItems[i]
            const score = fuzzyScore(item.preview, query)
            if (score >= 0)
                matches.push({ hash: item.hash, preview: item.preview, order: i, score: score })
        }
        matches.sort(function(left, right) {
            return left.score === right.score ? left.order - right.order : right.score - left.score
        })
        results = matches
        resultList.currentIndex = results.length > 0 ? 0 : -1
    }

    function activate(index) {
        if (index < 0 || index >= results.length)
            return
        Quickshell.execDetached([
            Quickshell.env("HOME") + "/.config/hypr/quickshell-clipboard-backend.sh",
            "--copy",
            results[index].hash
        ])
        closeClipboard()
    }

    function closeClipboard() {
        if (closing)
            return
        closing = true
        revealProgress = 0
        closeTimer.restart()
    }

    Process {
        id: historyProcess
        command: [
            Quickshell.env("HOME") + "/.config/hypr/quickshell-clipboard-backend.sh",
            "--list"
        ]
        running: true

        stdout: StdioCollector {
            onStreamFinished: {
                const parsed = []
                const lines = text.split("\n")
                for (let i = 0; i < lines.length; ++i) {
                    const separator = lines[i].indexOf("\t")
                    if (separator > 0) {
                        parsed.push({
                            hash: lines[i].slice(0, separator),
                            preview: lines[i].slice(separator + 1)
                        })
                    }
                }
                root.allItems = parsed
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

        Shortcut {
            sequence: "Escape"
            onActivated: root.closeClipboard()
        }

        Rectangle {
            anchors.fill: parent
            color: Qt.rgba(0.055, 0.047, 0.043, 0.42)
            opacity: root.revealProgress

            MouseArea {
                anchors.fill: parent
                onClicked: root.closeClipboard()
            }

            Rectangle {
                anchors.top: parent.top
                anchors.topMargin: 14
                anchors.horizontalCenter: parent.horizontalCenter
                width: Math.min(parent.width - 48, 680)
                height: Math.min(parent.height - 64, 420)
                radius: 14
                color: root.background
                border.width: 1
                border.color: Qt.rgba(0.46, 0.38, 0.33, 0.8)
                opacity: root.revealProgress
                scale: 0.985 + 0.015 * root.revealProgress

                MouseArea {
                    anchors.fill: parent
                    onClicked: function(mouse) { mouse.accepted = true }
                }

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 10
                    spacing: 8

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 42
                        radius: 9
                        color: root.surfaceAlt
                        border.width: searchField.activeFocus ? 1 : 0
                        border.color: root.accent

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 13
                            anchors.rightMargin: 13
                            spacing: 10

                            TextField {
                                id: searchField

                                Layout.fillWidth: true
                                color: root.foreground
                                placeholderText: "Поиск в истории буфера обмена"
                                placeholderTextColor: root.muted
                                selectionColor: root.selected
                                selectedTextColor: root.foreground
                                font.family: "Noto Sans"
                                font.pixelSize: 16
                                background: null
                                onTextChanged: {
                                    root.keyboardNavigating = false
                                    root.refreshResults()
                                }

                                Keys.onDownPressed: function(event) {
                                    root.keyboardNavigating = true
                                    if (root.results.length > 0) {
                                        resultList.currentIndex = (resultList.currentIndex + 1) % root.results.length
                                        resultList.positionViewAtIndex(resultList.currentIndex, ListView.Contain)
                                    }
                                    event.accepted = true
                                }
                                Keys.onUpPressed: function(event) {
                                    root.keyboardNavigating = true
                                    if (root.results.length > 0) {
                                        resultList.currentIndex = (resultList.currentIndex - 1 + root.results.length) % root.results.length
                                        resultList.positionViewAtIndex(resultList.currentIndex, ListView.Contain)
                                    }
                                    event.accepted = true
                                }
                                Keys.onReturnPressed: function(event) {
                                    root.activate(resultList.currentIndex)
                                    event.accepted = true
                                }
                                Keys.onEnterPressed: function(event) {
                                    root.activate(resultList.currentIndex)
                                    event.accepted = true
                                }
                            }

                            Text {
                                text: root.results.length + " / " + root.allItems.length
                                color: root.muted
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 9
                            }
                        }
                    }

                    Item {
                        visible: root.allItems.length === 0
                        Layout.fillWidth: true
                        Layout.fillHeight: true

                        Column {
                            anchors.centerIn: parent
                            spacing: 10

                            Text {
                                text: "История буфера пуста"
                                color: root.muted
                                font.family: "Noto Sans"
                                font.pixelSize: 14
                            }
                        }
                    }

                    ListView {
                        id: resultList

                        visible: root.allItems.length > 0
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        model: root.results
                        currentIndex: root.results.length > 0 ? 0 : -1
                        spacing: 5
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds
                        highlightMoveDuration: 90

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
                            id: resultRow

                            required property int index
                            required property var modelData
                            width: resultList.width
                            height: 44
                            radius: 9
                            color: resultRow.ListView.isCurrentItem || resultMouse.containsMouse
                                ? root.selected : root.surface
                            border.width: resultRow.ListView.isCurrentItem ? 1 : 0
                            border.color: root.accent

                            Behavior on color { ColorAnimation { duration: 90 } }

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 13
                                anchors.rightMargin: 13
                                spacing: 11

                                Text {
                                    Layout.fillWidth: true
                                    text: modelData.preview
                                    color: root.foreground
                                    elide: Text.ElideRight
                                    font.family: "Noto Sans"
                                    font.pixelSize: 14
                                }
                            }

                            MouseArea {
                                id: resultMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onEntered: {
                                    if (!root.keyboardNavigating)
                                        resultList.currentIndex = resultRow.index
                                }
                                onPositionChanged: {
                                    root.keyboardNavigating = false
                                    resultList.currentIndex = resultRow.index
                                }
                                onClicked: {
                                    root.keyboardNavigating = false
                                    root.activate(resultRow.index)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
