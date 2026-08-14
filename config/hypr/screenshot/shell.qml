pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland

ShellRoot {
    id: root

    Theme { id: theme }

    property bool active: false
    property bool selecting: false
    property bool closing: false
    property var owner: null
    property int captureSerial: 0

    function open() {
        selecting = false
        closing = false
        owner = null
        captureSerial++
        active = true
    }

    IpcHandler {
        target: "screenshot"

        function open(): void {
            root.open()
        }

        function cancel(): void {
            root.cancel()
        }
    }

    function selectWindowAt(panel, targetSelection, x, y) {
        const globalX = panel.screen.x + x
        const globalY = panel.screen.y + y
        const clients = Hyprland.toplevels.values
        const monitor = Hyprland.monitors.values.find(item => item.name === panel.screen.name)
        const activeWorkspaceId = monitor && monitor.activeWorkspace
            ? monitor.activeWorkspace.id : -1

        // Reverse traversal favours the top-most recently exposed client.
        for (let i = clients.length - 1; i >= 0; --i) {
            const client = clients[i]
            if (!client || !client.lastIpcObject)
                continue
            if (client.monitor && client.monitor.name !== panel.screen.name)
                continue
            if (activeWorkspaceId >= 0
                    && client.workspace && client.workspace.id !== activeWorkspaceId)
                continue
            const data = client.lastIpcObject
            if (data["hidden"] === true || data["mapped"] === false)
                continue
            const at = data["at"]
            const size = data["size"]
            if (!at || !size || size[0] < 2 || size[1] < 2)
                continue
            if (globalX < at[0] || globalY < at[1]
                    || globalX > at[0] + size[0] || globalY > at[1] + size[1])
                continue

            targetSelection.x = Math.max(0, at[0] - panel.screen.x)
            targetSelection.y = Math.max(0, at[1] - panel.screen.y)
            targetSelection.width = Math.min(panel.width - targetSelection.x, size[0])
            targetSelection.height = Math.min(panel.height - targetSelection.y, size[1])
            targetSelection.windowHover = true
            targetSelection.hasSelection = true
            return true
        }
        targetSelection.windowHover = false
        targetSelection.hasSelection = false
        return false
    }

    function finish(panel, x, y, width, height) {
        if (closing || width < 2 || height < 2)
            return

        closing = true
        const gx = Math.round(panel.screen.x + x)
        const gy = Math.round(panel.screen.y + y)
        const gw = Math.round(width)
        const gh = Math.round(height)
        const geometry = gx + "," + gy + " " + gw + "x" + gh
        const command = "mkdir -p \"$HOME/Pictures\"; file=\"$HOME/Pictures/$(date +'%Y-%m-%d_%H-%M-%S').png\"; grim -l 1 -g "
            + JSON.stringify(geometry)
            + " - | tee \"$file\" | wl-copy --type image/png; rm -f \"$SELF_SHELL_SCREENSHOT_FREEZE\"; notify-send -i \"$file\" 'Снимок экрана' 'Скопирован в буфер обмена'"

        // Hide every layer-shell surface immediately. Quitting in the same
        // event handler can leave the last committed frame on screen.
        active = false
        owner = null
        closeTimer.command = command
        closeTimer.start()
    }

    function cancel() {
        closing = true
        active = false
        Quickshell.execDetached(["bash", "-lc", "rm -f \"$SELF_SHELL_SCREENSHOT_FREEZE\""])
    }

    Timer {
        id: closeTimer
        property string command: ""
        interval: 16
        onTriggered: {
            Quickshell.execDetached(["bash", "-lc", command])
        }
    }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: panel
            required property var modelData

            screen: modelData
            visible: root.active && !root.closing
            anchors.top: true
            anchors.bottom: true
            anchors.left: true
            anchors.right: true
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
            WlrLayershell.namespace: "self-shell-screenshot"

            Shortcut { sequence: "Escape"; onActivated: root.cancel() }

            Image {
                id: frozenScreen
                anchors.fill: parent
                source: root.active
                    ? "file://" + Quickshell.env("SELF_SHELL_SCREENSHOT_FREEZE")
                        + "?capture=" + root.captureSerial
                    : ""
                fillMode: Image.PreserveAspectCrop
                cache: false
                asynchronous: false
            }

            Canvas {
                id: shade
                anchors.fill: parent

                onPaint: {
                    const ctx = getContext("2d")
                    ctx.reset()
                    ctx.clearRect(0, 0, width, height)
                    ctx.fillStyle = Qt.alpha(theme.background, 0.30)
                    ctx.fillRect(0, 0, width, height)
                    ctx.clearRect(selection.x, selection.y, selection.width, selection.height)
                }

                Connections {
                    target: selection
                    function onXChanged() { shade.requestPaint() }
                    function onYChanged() { shade.requestPaint() }
                    function onWidthChanged() { shade.requestPaint() }
                    function onHeightChanged() { shade.requestPaint() }
                }
            }

            Rectangle {
                id: selection
                property real startX: 0
                property real startY: 0
                property bool windowHover: false
                property bool hasSelection: false

                Connections {
                    target: root
                    function onCaptureSerialChanged() {
                        selection.x = 0
                        selection.y = 0
                        selection.width = 0
                        selection.height = 0
                        selection.windowHover = false
                        selection.hasSelection = false
                        shade.requestPaint()
                    }
                }

                x: 0
                y: 0
                width: 0
                height: 0
                visible: hasSelection
                color: "transparent"
                border.width: 2
                border.color: theme.accent
                radius: windowHover ? 12 : 6

                Behavior on x { enabled: selection.windowHover && !root.selecting; NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                Behavior on y { enabled: selection.windowHover && !root.selecting; NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                Behavior on width { enabled: selection.windowHover && !root.selecting; NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                Behavior on height { enabled: selection.windowHover && !root.selecting; NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                Behavior on radius { NumberAnimation { duration: 140 } }

                Rectangle {
                    id: sizeBadge
                    anchors.left: parent.left
                    anchors.leftMargin: 8
                    y: selection.y > height + 12 ? -height - 8 : 8
                    width: sizeLabel.implicitWidth + 16
                    height: 28
                    radius: 9
                    color: theme.background
                    border.width: 1
                    border.color: theme.outline

                    Text {
                        id: sizeLabel
                        anchors.centerIn: parent
                        text: Math.round(selection.width) + " × " + Math.round(selection.height)
                        color: theme.foreground
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 10
                    }
                }
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 28
                text: "Выберите область  ·  Esc — отмена"
                color: theme.foreground
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: 11
                padding: 10

                Rectangle {
                    z: -1
                    anchors.fill: parent
                    radius: 12
                    color: Qt.alpha(theme.background, 0.9)
                    border.width: 1
                    border.color: theme.outline
                }
            }

            MouseArea {
                id: pickerMouse
                property real pressX: 0
                property real pressY: 0
                property bool draggingSelection: false

                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.CrossCursor

                onPressed: event => {
                    root.owner = panel
                    pressX = event.x
                    pressY = event.y
                    draggingSelection = false
                    root.selecting = false
                    selection.startX = event.x
                    selection.startY = event.y
                }

                onPositionChanged: event => {
                    if (!pressed) {
                        root.selectWindowAt(panel, selection, event.x, event.y)
                        return
                    }
                    if (root.owner !== panel)
                        return
                    if (!draggingSelection && Math.hypot(event.x - pressX, event.y - pressY) > 7) {
                        draggingSelection = true
                        root.selecting = true
                        selection.windowHover = false
                        selection.hasSelection = true
                    }
                    if (!draggingSelection)
                        return
                    selection.x = Math.min(selection.startX, event.x)
                    selection.y = Math.min(selection.startY, event.y)
                    selection.width = Math.abs(event.x - selection.startX)
                    selection.height = Math.abs(event.y - selection.startY)
                }

                onReleased: event => {
                    root.selecting = false
                    if (root.owner !== panel)
                        return
                    if (!draggingSelection)
                        root.selectWindowAt(panel, selection, event.x, event.y)
                    if (selection.width >= 2 && selection.height >= 2)
                        root.finish(panel, selection.x, selection.y, selection.width, selection.height)
                }
            }

            Process {
                running: true
                command: ["hyprctl", "cursorpos", "-j"]
                stdout: StdioCollector {
                    onStreamFinished: {
                        try {
                            const pos = JSON.parse(text)
                            root.selectWindowAt(panel, selection, pos.x - panel.screen.x, pos.y - panel.screen.y)
                        } catch (error) {}
                    }
                }
            }
        }
    }
}
