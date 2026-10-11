import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland

ShellRoot {
    id: root

    readonly property bool isNiri: Quickshell.env("NIRI_SOCKET").length > 0

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
    property real revealProgress: 0
    property string interfaceStyle: "modern"
    property string clipboardPosition: "center"
    readonly property bool minimum: interfaceStyle === "minimum"

    FileView {
        path: Quickshell.env("HOME") + "/.config/self-shell/interface-style.json"
        blockLoading: true
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            try {
                const state = JSON.parse(text())
                root.interfaceStyle = state.style || "modern"
                root.clipboardPosition = state.clipboardPosition || "center"
            }
            catch (error) { root.interfaceStyle = "modern" }
        }
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
        interval: root.minimum ? 100 : 270
        onTriggered: Qt.quit()
    }

    Component.onCompleted: Qt.callLater(function() {
        searchField.forceActiveFocus()
        root.revealProgress = 1
    })

    Behavior on revealProgress {
        NumberAnimation {
            duration: root.minimum ? 90 : 260
            easing.type: Easing.BezierSpline
            easing.bezierCurve: [0.38, 1.21, 0.22, 1, 1, 1]
        }
    }

    PanelWindow {
        screen: {
            if (root.isNiri)
                return Quickshell.screens[0]
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
            color: "transparent"
            opacity: 1

            MouseArea {
                anchors.fill: parent
                onClicked: root.closeClipboard()
            }

            Rectangle {
                id: clipboardPanel
                readonly property int visibleRows: Math.min(root.minimum ? 8 : 7, root.results.length)
                readonly property real listContentHeight: visibleRows > 0
                    ? visibleRows * (root.minimum ? 36 : 57)
                        + Math.max(0, visibleRows - 1) * (root.minimum ? 1 : 8)
                    : 96
                readonly property real contentHeight: listContentHeight + (root.minimum ? 44 : 48)
                    + (root.minimum ? 24 : 44)
                readonly property real expandedHeight: Math.min(parent.height - 48, contentHeight)
                property real animatedHeight: expandedHeight

                onExpandedHeightChanged: animatedHeight = expandedHeight

                Behavior on animatedHeight {
                    enabled: !root.closing && root.revealProgress > 0.98
                    NumberAnimation {
                        duration: root.minimum ? 100 : 320
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: [0.38, 1.21, 0.22, 1, 1, 1]
                    }
                }

                width: Math.min(parent.width - 48, root.minimum ? 620 : 632)
                height: animatedHeight * root.revealProgress
                x: root.minimum
                    ? (root.clipboardPosition.endsWith("left") || root.clipboardPosition === "left" ? 1
                        : root.clipboardPosition.endsWith("right") || root.clipboardPosition === "right" ? parent.width - width - 1
                        : Math.round((parent.width - width) / 2))
                    : Math.round((parent.width - width) / 2 + 28)
                y: root.minimum
                    ? (root.clipboardPosition.startsWith("top") ? 42
                        : root.clipboardPosition.startsWith("bottom") ? parent.height - height - 1
                        : Math.round((parent.height - height) / 2))
                    : parent.height - height
                radius: root.minimum ? 4 : Math.min(28, height / 2)
                color: Qt.alpha(root.background, root.minimum ? 0.97 : 1)
                border.width: 1
                border.color: theme.outline
                opacity: 1
                clip: true

                Behavior on width {
                    enabled: !root.closing
                    NumberAnimation {
                        duration: root.minimum ? 100 : 500
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: [0.38, 1.21, 0.22, 1, 1, 1]
                    }
                }

                Rectangle {
                    visible: !root.minimum
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.leftMargin: clipboardPanel.border.width
                    anchors.rightMargin: clipboardPanel.border.width
                    height: clipboardPanel.radius
                    color: parent.color
                }

                Rectangle {
                    visible: !root.minimum
                    anchors.left: parent.left
                    anchors.bottom: parent.bottom
                    width: clipboardPanel.border.width
                    height: clipboardPanel.radius
                    color: clipboardPanel.border.color
                }

                Rectangle {
                    visible: !root.minimum
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    width: clipboardPanel.border.width
                    height: clipboardPanel.radius
                    color: clipboardPanel.border.color
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: function(mouse) { mouse.accepted = true }
                }

                GridLayout {
                    anchors.fill: parent
                    anchors.margins: 8
                    columns: 1
                    rowSpacing: root.minimum ? 6 : 5

                    Rectangle {
                        Layout.row: root.minimum ? 0 : 1
                        Layout.fillWidth: true
                        Layout.preferredHeight: 44
                        radius: root.minimum ? 2 : 24
                        color: root.minimum ? Qt.darker(root.surfaceAlt, 1.12) : root.surfaceAlt
                        border.width: root.minimum ? 1 : 0
                        border.color: root.minimum ? root.accent : theme.outline

                        Rectangle {
                            visible: root.minimum
                            anchors.left: parent.left
                            anchors.top: parent.top
                            anchors.bottom: parent.bottom
                            width: 3
                            color: root.accent
                        }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 13
                            anchors.rightMargin: 13
                            spacing: 9

                            Text {
                                text: root.minimum ? ">" : "󰍉"
                                color: root.foreground
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: root.minimum ? 16 : 17
                                font.weight: root.minimum ? Font.Bold : Font.Normal
                            }

                            TextField {
                                id: searchField

                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                verticalAlignment: TextInput.AlignVCenter
                                color: root.foreground
                                placeholderText: root.minimum ? "Search clipboard..." : "Поиск в буфере обмена…"
                                placeholderTextColor: root.muted
                                selectionColor: root.selected
                                selectedTextColor: root.foreground
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: root.minimum ? 15 : 14
                                font.weight: root.minimum ? Font.Bold : Font.Normal
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
                        Layout.row: root.minimum ? 1 : 0
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

                        Layout.row: root.minimum ? 1 : 0
                        visible: root.allItems.length > 0
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        model: root.results
                        currentIndex: root.results.length > 0 ? 0 : -1
                        spacing: root.minimum ? 1 : 8
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds
                        highlightFollowsCurrentItem: false

                        displaced: Transition {
                            NumberAnimation {
                                property: "y"
                                duration: root.minimum ? 70 : 220
                                easing.type: Easing.OutCubic
                            }
                        }

                        highlight: Rectangle {
                            y: resultList.currentItem ? resultList.currentItem.y : 0
                            width: resultList.width
                            height: resultList.currentItem ? resultList.currentItem.height : 0
                            radius: root.minimum ? 2 : 16
                            color: root.minimum ? theme.selected : root.surfaceAlt

                            Behavior on y {
                                NumberAnimation {
                                    duration: root.minimum ? 70 : 500
                                    easing.type: Easing.BezierSpline
                                    easing.bezierCurve: [0.38, 1.21, 0.22, 1, 1, 1]
                                }
                            }
                        }

                        add: Transition {
                            NumberAnimation {
                                property: "opacity"
                                from: 0; to: 1
                                duration: root.minimum ? 60 : 200
                                easing.type: Easing.BezierSpline
                                easing.bezierCurve: [0.34, 0.8, 0.34, 1, 1, 1]
                            }
                        }

                        remove: Transition {
                            NumberAnimation {
                                property: "opacity"
                                from: 1; to: 0
                                duration: root.minimum ? 60 : 200
                                easing.type: Easing.BezierSpline
                                easing.bezierCurve: [0.34, 0.8, 0.34, 1, 1, 1]
                            }
                        }

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

                        delegate: Item {
                            id: resultRow

                            required property int index
                            required property var modelData
                            width: resultList.width
                            height: root.minimum ? 36 : 57

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: root.minimum ? 8 : 12
                                anchors.rightMargin: root.minimum ? 8 : 12

                                Text {
                                    Layout.fillWidth: true
                                    text: modelData.preview
                                    color: root.foreground
                                    elide: Text.ElideRight
                                    maximumLineCount: 1
                                    font.family: "JetBrainsMono Nerd Font"
                                    font.pixelSize: root.minimum ? 11 : 13
                                    verticalAlignment: Text.AlignVCenter
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
