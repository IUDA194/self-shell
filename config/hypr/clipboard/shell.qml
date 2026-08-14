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

    readonly property color background: theme.background
    readonly property color surface: theme.surface
    readonly property color surfaceAlt: theme.surfaceAlt
    readonly property color selected: theme.selected
    readonly property color foreground: theme.foreground
    readonly property color muted: theme.muted
    readonly property color accent: theme.accent

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
            color: theme.scrim
            opacity: root.revealProgress

            MouseArea {
                anchors.fill: parent
                onClicked: root.closeClipboard()
            }

            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                anchors.horizontalCenter: parent.horizontalCenter
                width: Math.min(parent.width - 32, 520)
                height: Math.min(parent.height - 40,
                    62 + Math.max(1, Math.min(root.results.length, 7)) * 41)
                radius: 20
                color: root.background
                border.width: 1
                border.color: theme.outline
                opacity: root.revealProgress
                scale: 0.97 + 0.03 * root.revealProgress

                Behavior on height {
                    NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: function(mouse) { mouse.accepted = true }
                }

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 8
                    spacing: 5

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 44
                        radius: 13
                        color: searchField.activeFocus ? root.surfaceAlt : root.surface

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 13
                            anchors.rightMargin: 13
                            spacing: 9

                            Text {
                                text: "⌕"
                                color: searchField.activeFocus ? root.accent : root.muted
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 18
                            }

                            TextField {
                                id: searchField

                                Layout.fillWidth: true
                                color: root.foreground
                                placeholderText: "Поиск"
                                placeholderTextColor: root.muted
                                selectionColor: root.selected
                                selectedTextColor: root.foreground
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 13
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

                        }
                    }

                    Item {
                        visible: root.allItems.length === 0
                        Layout.fillWidth: true
                        Layout.fillHeight: true

                        Column {
                            anchors.centerIn: parent
                            Text {
                                text: "Пусто"
                                color: root.muted
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 12
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
                        spacing: 1
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
                            height: 40
                            radius: 11
                            color: resultRow.ListView.isCurrentItem || resultMouse.containsMouse
                                ? root.surfaceAlt : "transparent"

                            Behavior on color { ColorAnimation { duration: 90 } }

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 12
                                anchors.rightMargin: 12

                                Text {
                                    Layout.fillWidth: true
                                    text: modelData.preview
                                    color: root.foreground
                                    elide: Text.ElideRight
                                    maximumLineCount: 1
                                    font.family: "JetBrainsMono Nerd Font"
                                    font.pixelSize: 12
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
