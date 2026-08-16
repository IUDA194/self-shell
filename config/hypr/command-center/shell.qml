pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire
import Quickshell.Wayland

ShellRoot {
    id: root

    Theme { id: theme }

    readonly property color background: theme.background
    readonly property color surface: theme.surface
    readonly property color surfaceAlt: theme.surfaceAlt
    readonly property color foreground: theme.foreground
    readonly property color muted: theme.muted
    readonly property color accent: theme.accent
    readonly property color critical: theme.critical
    readonly property var outputStreams: Pipewire.nodes.values.filter(node =>
        node && node.type === PwNodeType.AudioOutStream && node.audio !== null)
    readonly property var inputStreams: Pipewire.nodes.values.filter(node =>
        node && node.type === PwNodeType.AudioInStream && node.audio !== null)
    readonly property var trackedAudio: [Pipewire.defaultAudioSink, Pipewire.defaultAudioSource]
        .concat(outputStreams).concat(inputStreams).filter(node => node)
    property int brightness: 0
    property bool brightnessAvailable: false
    property string brightnessBackend: ""
    property string brightnessDevice: ""
    property bool nightLight: false
    property bool recording: false
    property string recordingStarted: ""
    property string recordingElapsed: "00:00"
    property string recordingSize: "0 Б"
    property string recordingFile: ""
    property var recentFiles: []
    property var notifications: []
    property bool notificationDnd: false
    property string phoneId: ""
    property string phoneName: "iPhone"
    property bool phoneOnline: false
    property int phoneCharge: -1
    property bool phoneCharging: false
    signal openRequested(int tab)

    PwObjectTracker { objects: root.trackedAudio }

    function refreshState() {
        if (!brightnessRead.running) brightnessRead.running = true
        if (!stateRead.running) stateRead.running = true
        if (!recentRead.running) recentRead.running = true
        if (!notificationList.running) notificationList.running = true
        if (!dndRead.running) dndRead.running = true
    }

    IpcHandler {
        target: "commandCenter"
        function notifications(): void { root.openRequested(3) }
    }

    Process {
        id: brightnessRead
        command: ["bash", Quickshell.env("HOME") + "/.config/hypr/brightness.sh", "read"]
        stdout: StdioCollector {
            onStreamFinished: {
                const fields = text.trim().split("\t")
                const value = Number(fields[2])
                root.brightnessAvailable = fields.length === 3 && Number.isFinite(value)
                if (root.brightnessAvailable) {
                    root.brightnessBackend = fields[0]
                    root.brightnessDevice = fields[1]
                    root.brightness = value
                }
            }
        }
    }

    Process {
        id: brightnessWrite
        onExited: brightnessRead.running = true
    }

    Process {
        id: stateRead
        command: ["bash", "-lc", "test -e \"${XDG_RUNTIME_DIR:-/tmp}/self-shell-command-center/night-light\" && n=1 || n=0; pgrep -x wf-recorder >/dev/null && r=1 || r=0; printf '%s %s' \"$n\" \"$r\""]
        stdout: StdioCollector {
            onStreamFinished: {
                const fields = text.trim().split(/\s+/)
                root.nightLight = fields[0] === "1"
                root.recording = fields[1] === "1"
            }
        }
    }

    Process { id: actionProcess; onExited: root.refreshState() }

    Process {
        id: phoneStatus
        command: [Quickshell.env("HOME") + "/.config/hypr/kdeconnect-status.sh"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                const fields = text.trim().split("\t")
                root.phoneId = fields[0] || ""
                root.phoneName = fields[1] || "iPhone"
                root.phoneOnline = fields[2] === "1"
                root.phoneCharge = Number(fields[3])
                root.phoneCharging = fields[4] === "1"
            }
        }
    }

    Process { id: phoneAction; onExited: phoneStatus.running = true }

    Process {
        id: recorderStatus
        command: [Quickshell.env("HOME") + "/.config/hypr/command-center-action.sh", "record-status"]
        stdout: StdioCollector {
            onStreamFinished: {
                const fields = text.trim().split("\t")
                root.recording = fields[0] === "1"
                const seconds = Number(fields[1]) || 0
                root.recordingElapsed = String(Math.floor(seconds / 60)).padStart(2, "0")
                    + ":" + String(seconds % 60).padStart(2, "0")
                const bytes = Number(fields[2]) || 0
                root.recordingSize = bytes >= 1048576
                    ? (bytes / 1048576).toFixed(1) + " МБ"
                    : Math.round(bytes / 1024) + " КБ"
                root.recordingFile = fields[3] || ""
            }
        }
    }

    Process {
        id: notificationList
        command: ["quickshell", "ipc", "call", "notifications", "listJson"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.notifications = JSON.parse(text.trim() || "[]") }
                catch (error) { root.notifications = [] }
            }
        }
    }

    Process {
        id: dndRead
        command: ["quickshell", "ipc", "call", "notifications", "dndState"]
        stdout: StdioCollector { onStreamFinished: root.notificationDnd = text.trim() === "true" }
    }

    Process {
        id: notificationAction
        onExited: {
            notificationList.running = true
            dndRead.running = true
        }
    }

    Process {
        id: recentRead
        command: [Quickshell.env("HOME") + "/.config/hypr/command-center-thumbnails.sh"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.trim().length > 0 ? text.trim().split("\n") : []
                root.recentFiles = lines.map(function(line) {
                    const separator = line.indexOf("\t")
                    return {
                        path: separator >= 0 ? line.slice(0, separator) : line,
                        thumbnail: separator >= 0 ? line.slice(separator + 1) : ""
                    }
                })
            }
        }
    }

    Process {
        id: pickerProcess
        command: ["bash", "-lc", "sleep 0.55; color=$(hyprpicker -a 2>/dev/null) && notify-send 'Цвет скопирован' \"$color\""]
    }

    Timer { interval: 2500; repeat: true; running: true; onTriggered: stateRead.running = true }
    Timer { interval: 1000; repeat: true; running: true; onTriggered: if (!recorderStatus.running) recorderStatus.running = true }
    Timer { interval: 5000; repeat: true; running: true; onTriggered: if (!phoneStatus.running) phoneStatus.running = true }

    component StyledSlider: Slider {
        id: styledSlider
        implicitHeight: 32
        background: Rectangle {
            x: styledSlider.leftPadding
            y: styledSlider.topPadding + styledSlider.availableHeight / 2 - height / 2
            width: styledSlider.availableWidth
            height: 6
            radius: 3
            color: root.surfaceAlt
            Rectangle {
                width: styledSlider.visualPosition * parent.width
                height: parent.height
                radius: parent.radius
                color: root.accent
                Behavior on width { NumberAnimation { duration: 90; easing.type: Easing.OutCubic } }
            }
        }
        handle: Rectangle {
            x: styledSlider.leftPadding + styledSlider.visualPosition * (styledSlider.availableWidth - width)
            y: styledSlider.topPadding + styledSlider.availableHeight / 2 - height / 2
            width: 18
            height: 18
            radius: 9
            color: styledSlider.hovered || styledSlider.pressed ? theme.foreground : theme.foregroundSoft
            border.width: 3
            border.color: root.accent
            Behavior on color { ColorAnimation { duration: 150 } }
        }
    }

    component DragSlider: Item {
        id: dragSlider
        property real from: 0
        property real to: 1
        property real value: 0
        property real dragValue: value
        readonly property bool dragging: dragMouse.pressed
        readonly property real effectiveValue: dragging ? dragValue : value
        signal moved(real value)
        implicitHeight: 40

        function updateFromX(mouseX) {
            const ratio = Math.max(0, Math.min(1, mouseX / Math.max(1, width)))
            const next = from + ratio * (to - from)
            dragValue = next
            moved(next)
        }

        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            height: 9
            radius: 5
            color: Qt.alpha(theme.foreground, 0.16)
            border.width: 1
            border.color: theme.outline
            Rectangle {
                width: Math.max(0, Math.min(1, (dragSlider.effectiveValue - dragSlider.from)
                    / (dragSlider.to - dragSlider.from))) * parent.width
                height: parent.height
                radius: parent.radius
                color: root.accent
                border.width: 1
                border.color: theme.accentHover
            }
        }

        Rectangle {
            x: Math.max(0, Math.min(1, (dragSlider.effectiveValue - dragSlider.from)
                / (dragSlider.to - dragSlider.from))) * (parent.width - width)
            anchors.verticalCenter: parent.verticalCenter
            width: 22
            height: 22
            radius: 11
            color: dragMouse.pressed || dragMouse.containsMouse ? theme.foreground : theme.foregroundSoft
            border.width: 4
            border.color: root.accent
            scale: dragMouse.pressed ? 1.16 : 1
            Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutBack } }
            Behavior on color { ColorAnimation { duration: 140 } }

            Rectangle {
                anchors.centerIn: parent
                width: 4
                height: 4
                radius: 2
                color: root.accent
            }
        }

        MouseArea {
            id: dragMouse
            anchors.fill: parent
            hoverEnabled: true
            preventStealing: true
            cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
            onPressed: mouse => {
                dragSlider.dragValue = dragSlider.value
                dragSlider.updateFromX(mouse.x)
            }
            onPositionChanged: mouse => { if (pressed) dragSlider.updateFromX(mouse.x) }
        }
    }

    component MixerRow: Rectangle {
        id: mixerRow
        required property var node
        property bool interacting: false
        property bool master: false
        height: 58
        radius: 14
        color: master ? root.surface : root.background
        border.width: 1
        border.color: theme.outline

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 12
            anchors.rightMargin: 10
            spacing: 10

            Text {
                text: mixerRow.node && mixerRow.node.audio && mixerRow.node.audio.muted ? "󰖁" : "󰕾"
                color: mixerRow.node && mixerRow.node.audio && mixerRow.node.audio.muted ? root.critical : root.accent
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: 16
            }
            Text {
                Layout.preferredWidth: 170
                text: mixerRow.node ? (mixerRow.node.description || mixerRow.node.nickname || mixerRow.node.name || "Аудиопоток") : "Аудиопоток"
                elide: Text.ElideRight
                color: root.foreground
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: 11
            }
            Text {
                text: "−"
                color: minusMouse.containsMouse ? root.accent : root.muted
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: 16
                MouseArea {
                    id: minusMouse
                    anchors.fill: parent
                    anchors.margins: -7
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: if (mixerRow.node && mixerRow.node.audio)
                        mixerRow.node.audio.volume = Math.max(0, mixerRow.node.audio.volume - 0.05)
                }
            }
            DragSlider {
                Layout.fillWidth: true
                from: 0
                to: 1.5
                value: mixerRow.node && mixerRow.node.audio ? mixerRow.node.audio.volume : 0
                onMoved: value => { if (mixerRow.node && mixerRow.node.audio) mixerRow.node.audio.volume = value }
                onDraggingChanged: mixerRow.interacting = dragging
            }
            Text {
                text: "+"
                color: plusMouse.containsMouse ? root.accent : root.muted
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: 15
                MouseArea {
                    id: plusMouse
                    anchors.fill: parent
                    anchors.margins: -7
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: if (mixerRow.node && mixerRow.node.audio)
                        mixerRow.node.audio.volume = Math.min(1.5, mixerRow.node.audio.volume + 0.05)
                }
            }
            Text {
                Layout.preferredWidth: 38
                horizontalAlignment: Text.AlignRight
                text: mixerRow.node && mixerRow.node.audio ? Math.round(mixerRow.node.audio.volume * 100) + "%" : "—"
                color: root.muted
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: 10
            }
            Rectangle {
                id: muteButton
                readonly property bool muted: mixerRow.node && mixerRow.node.audio
                    ? mixerRow.node.audio.muted : false
                Layout.preferredWidth: 34
                Layout.preferredHeight: 34
                radius: 11
                color: muted
                    ? (muteMouse.containsMouse ? Qt.alpha(root.critical, 0.30) : Qt.alpha(root.critical, 0.20))
                    : (muteMouse.containsMouse ? root.surfaceAlt : "transparent")
                border.width: 1
                border.color: muted
                    ? Qt.alpha(root.critical, 0.85)
                    : (muteMouse.containsMouse ? root.accent : theme.outline)

                Behavior on color { ColorAnimation { duration: 150; easing.type: Easing.OutCubic } }
                Behavior on border.color { ColorAnimation { duration: 150 } }

                Text {
                    anchors.centerIn: parent
                    text: muteButton.muted ? "󰖁" : "󰕾"
                    color: muteButton.muted ? root.critical : (muteMouse.containsMouse ? root.accent : root.foreground)
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 16
                    scale: muteMouse.pressed ? 0.88 : (muteMouse.containsMouse ? 1.10 : 1)
                    Behavior on color { ColorAnimation { duration: 150 } }
                    Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutBack } }
                }

                MouseArea {
                    id: muteMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: if (mixerRow.node && mixerRow.node.audio)
                        mixerRow.node.audio.muted = !mixerRow.node.audio.muted
                }
            }
        }
    }

    Variants {
        model: Quickshell.screens

        delegate: Component {
            PanelWindow {
                id: window
                required property var modelData
                property int revealStage: 0
                property int activeTab: 0
                property bool controlActive: false
                readonly property real targetWidth: Math.min(860, screen.width - 36)
                readonly property int mixerRows: (Pipewire.defaultAudioSink ? 1 : 0)
                    + root.outputStreams.length + (Pipewire.defaultAudioSource ? 1 : 0)
                    + root.inputStreams.length
                readonly property int galleryRows: Math.max(1, Math.ceil(root.recentFiles.length / 2))
                readonly property real desiredHeight: activeTab === 0
                    ? Math.max(480, Math.min(680, 150 + mixerRows * 66))
                    : activeTab === 1 ? 480
                    : activeTab === 2 ? Math.max(480, Math.min(680, 72 + galleryRows * 150))
                    : Math.max(480, Math.min(680, 150 + root.notifications.length * 86))
                readonly property real targetHeight: Math.min(desiredHeight, screen.height - 48)

                screen: modelData
                anchors.right: true
                implicitWidth: targetWidth
                implicitHeight: screen.height
                color: "transparent"
                exclusionMode: ExclusionMode.Ignore
                mask: Region { item: hoverRegion }
                WlrLayershell.layer: WlrLayer.Overlay
                WlrLayershell.margins.right: 0
                WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

                Connections {
                    target: root
                    function onOpenRequested(tab) {
                        window.activeTab = tab
                        window.revealStage = 2
                        root.refreshState()
                    }
                }

                Item {
                    id: hoverRegion
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    width: window.revealStage === 2 ? window.targetWidth : window.revealStage === 1 ? 102 : 8
                    height: window.revealStage === 2 ? window.targetHeight : window.revealStage === 1 ? 380 : 160
                    Behavior on width { NumberAnimation { duration: 360; easing.type: Easing.BezierSpline; easing.bezierCurve: [0.38, 1.21, 0.22, 1, 1, 1] } }
                    Behavior on height { NumberAnimation { duration: 360; easing.type: Easing.BezierSpline; easing.bezierCurve: [0.38, 1.21, 0.22, 1, 1, 1] } }

                    HoverHandler {
                        id: edgeHover
                        enabled: window.revealStage < 2
                        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                        onHoveredChanged: {
                            if (!hovered)
                                return
                            closeTimer.stop()
                            edgeCloseTimer.stop()
                            if (window.revealStage === 0)
                                window.revealStage = 1
                            openTimer.restart()
                        }
                    }
                }

                Timer { id: openTimer; interval: 450; onTriggered: { window.revealStage = 2; root.refreshState() } }
                Timer {
                    id: closeTimer
                    interval: 420
                    onTriggered: {
                        if (!window.controlActive && !panelHover.hovered) {
                            window.revealStage = 1
                            edgeCloseTimer.restart()
                        }
                    }
                }

                Timer {
                    id: edgeCloseTimer
                    interval: 360
                    onTriggered: {
                        if (!panelHover.hovered)
                            window.revealStage = 0
                    }
                }

                HoverHandler {
                    id: panelHover
                    parent: reveal
                    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                    onHoveredChanged: {
                        if (hovered) {
                            closeTimer.stop()
                            edgeCloseTimer.stop()
                            if (window.revealStage === 0)
                                window.revealStage = 1
                            if (window.revealStage === 1)
                                openTimer.restart()
                            return
                        }
                        openTimer.stop()
                        if (window.controlActive)
                            return
                        closeTimer.interval = window.revealStage === 1 ? 180 : 420
                        closeTimer.restart()
                    }
                    onActiveChanged: {
                        if (!active)
                            return
                        closeTimer.stop()
                    }
                }

                Item {
                    id: reveal
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    width: window.revealStage === 2 ? window.targetWidth
                        : window.revealStage === 1 ? 102 : 0
                    height: window.revealStage === 2 ? window.targetHeight
                        : window.revealStage === 1 ? 380 : 160
                    clip: true
                    Behavior on width { NumberAnimation { duration: 360; easing.type: Easing.BezierSpline; easing.bezierCurve: [0.38, 1.21, 0.22, 1, 1, 1] } }
                    Behavior on height { NumberAnimation { duration: 360; easing.type: Easing.BezierSpline; easing.bezierCurve: [0.38, 1.21, 0.22, 1, 1, 1] } }

                    Rectangle {
                        anchors.right: parent.right
                        anchors.rightMargin: -1
                        anchors.verticalCenter: parent.verticalCenter
                        // Extend through the clip edge so the right border is
                        // removed and the surface meets the screen exactly.
                        width: window.targetWidth + 1
                        height: window.revealStage === 2 ? window.targetHeight : 380
                        topLeftRadius: 24
                        bottomLeftRadius: 24
                        color: "transparent"
                        border.width: 0
                        antialiasing: true

                        Behavior on width {
                            NumberAnimation {
                                duration: 360
                                easing.type: Easing.BezierSpline
                                easing.bezierCurve: [0.38, 1.21, 0.22, 1, 1, 1]
                            }
                        }

                        Behavior on height {
                            NumberAnimation {
                                duration: 360
                                easing.type: Easing.BezierSpline
                                easing.bezierCurve: [0.38, 1.21, 0.22, 1, 1, 1]
                            }
                        }

                        Canvas {
                            id: commandSurface
                            z: 0
                            anchors.fill: parent
                            antialiasing: true

                            readonly property real railWidth: 102
                            readonly property real railHeight: 380
                            readonly property real shoulder: 24

                            onWidthChanged: requestPaint()
                            onHeightChanged: requestPaint()

                            Connections {
                                target: theme
                                function onBackgroundChanged() { commandSurface.requestPaint() }
                                function onOutlineChanged() { commandSurface.requestPaint() }
                            }

                            onPaint: {
                                const ctx = getContext("2d")
                                const w = width
                                const h = height
                                const r = 24
                                const seamX = w - railWidth
                                const railTop = (h - railHeight) / 2
                                const railBottom = railTop + railHeight
                                const shoulderSize = Math.min(shoulder, railTop, h - railBottom)

                                ctx.reset()
                                ctx.clearRect(0, 0, w, h)
                                ctx.beginPath()
                                ctx.moveTo(r, 0)
                                ctx.lineTo(seamX - r, 0)
                                ctx.quadraticCurveTo(seamX, 0, seamX, r)
                                ctx.lineTo(seamX, railTop - shoulderSize)
                                ctx.bezierCurveTo(seamX, railTop - 9,
                                                  seamX + 9, railTop,
                                                  seamX + shoulderSize, railTop)
                                ctx.lineTo(w + 1, railTop)
                                ctx.lineTo(w + 1, railBottom)
                                ctx.lineTo(seamX + shoulderSize, railBottom)
                                ctx.bezierCurveTo(seamX + 9, railBottom,
                                                  seamX, railBottom + 9,
                                                  seamX, railBottom + shoulderSize)
                                ctx.lineTo(seamX, h - r)
                                ctx.quadraticCurveTo(seamX, h, seamX - r, h)
                                ctx.lineTo(r, h)
                                ctx.quadraticCurveTo(0, h, 0, h - r)
                                ctx.lineTo(0, r)
                                ctx.quadraticCurveTo(0, 0, r, 0)
                                ctx.closePath()
                                ctx.fillStyle = root.background
                                ctx.fill()
                                ctx.lineWidth = 1.2
                                ctx.strokeStyle = theme.outline
                                ctx.stroke()
                            }
                        }

                        Rectangle {
                            z: 0.5
                            anchors.right: parent.right
                            anchors.rightMargin: -1
                            anchors.verticalCenter: parent.verticalCenter
                            width: 103
                            height: 380
                            topLeftRadius: 24
                            bottomLeftRadius: 24
                            color: root.background
                            border.width: 1
                            border.color: theme.outline
                            opacity: window.revealStage === 1 ? 1 : 0
                            Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                        }

                        ColumnLayout {
                            z: 1
                            anchors.fill: parent
                            anchors.margins: 22
                            spacing: 16

                            RowLayout {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                layoutDirection: Qt.RightToLeft
                                spacing: 16

                                Item {
                                    id: tabRail
                                    Layout.preferredWidth: 58
                                    Layout.maximumWidth: 58
                                    Layout.preferredHeight: 336
                                    Layout.maximumHeight: 336
                                    Layout.alignment: Qt.AlignVCenter

                                    readonly property real tabSpacing: 10
                                    readonly property real tabHeight: (height - tabSpacing * 3) / 4

                                    Rectangle {
                                        z: 2
                                        anchors.right: parent.right
                                        width: 4
                                        height: tabRail.tabHeight - 20
                                        radius: 2
                                        y: window.activeTab * (tabRail.tabHeight + tabRail.tabSpacing) + 10
                                        color: root.accent

                                        Behavior on y {
                                            NumberAnimation {
                                                duration: 300
                                                easing.type: Easing.BezierSpline
                                                easing.bezierCurve: [0.38, 1.21, 0.22, 1, 1, 1]
                                            }
                                        }
                                        Behavior on height { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                                    }

                                    Repeater {
                                        model: [{icon:"󰕾", title:"Эквалайзер"}, {icon:"󰃠", title:"Управление"}, {icon:"󰋩", title:"Последние"}, {icon:"󰂚", title:"Уведомления"}]
                                        delegate: Item {
                                            id: tabButton
                                            required property int index
                                            required property var modelData
                                            x: 0
                                            y: index * (tabRail.tabHeight + tabRail.tabSpacing)
                                            width: tabRail.width
                                            height: tabRail.tabHeight

                                            Text {
                                                anchors.centerIn: parent
                                                text: tabButton.modelData.icon
                                                color: window.activeTab === tabButton.index ? root.accent : root.muted
                                                font.family: "JetBrainsMono Nerd Font"
                                                font.pixelSize: 23
                                                scale: window.activeTab === tabButton.index ? 1.14
                                                    : tabMouse.containsMouse ? 1.07 : 1
                                                Behavior on color { ColorAnimation { duration: 150 } }
                                                Behavior on scale { NumberAnimation { duration: 220; easing.type: Easing.OutBack } }
                                            }
                                            MouseArea { id: tabMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { window.activeTab = tabButton.index; if (tabButton.index === 2) recentRead.running = true; if (tabButton.index === 3) root.refreshState() } }
                                        }
                                    }

                                }

                                Item {
                                    id: decorativeDivider
                                    Layout.preferredWidth: 12
                                    Layout.preferredHeight: 336
                                    Layout.maximumHeight: 336
                                    Layout.alignment: Qt.AlignVCenter

                                    Rectangle {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        anchors.top: parent.top
                                        anchors.bottom: parent.bottom
                                        anchors.topMargin: 12
                                        anchors.bottomMargin: 12
                                        width: 2
                                        radius: 1
                                        gradient: Gradient {
                                            orientation: Gradient.Vertical
                                            GradientStop { position: 0.0; color: "transparent" }
                                            GradientStop { position: 0.16; color: theme.outline }
                                            GradientStop { position: 0.50; color: Qt.alpha(root.accent, 0.70) }
                                            GradientStop { position: 0.84; color: theme.outline }
                                            GradientStop { position: 1.0; color: "transparent" }
                                        }
                                    }

                                    Repeater {
                                        model: 4
                                        delegate: Rectangle {
                                            required property int index
                                            anchors.horizontalCenter: decorativeDivider.horizontalCenter
                                            y: (index + 0.5) * decorativeDivider.height / 4 - height / 2
                                            width: 7
                                            height: 7
                                            radius: 2
                                            rotation: 45
                                            color: window.activeTab === index ? root.accent : root.surfaceAlt
                                            border.width: 1
                                            border.color: window.activeTab === index ? theme.accentHover : theme.outline
                                            scale: window.activeTab === index ? 1.18 : 0.82

                                            Behavior on color { ColorAnimation { duration: 180; easing.type: Easing.OutCubic } }
                                            Behavior on border.color { ColorAnimation { duration: 180 } }
                                            Behavior on scale { NumberAnimation { duration: 260; easing.type: Easing.OutBack } }
                                        }
                                    }
                                }

                                StackLayout {
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    currentIndex: window.activeTab

                                ScrollView {
                                    id: equalizerScroll
                                    clip: true
                                    opacity: StackLayout.isCurrentItem ? 1 : 0
                                    scale: StackLayout.isCurrentItem ? 1 : 0.985
                                    Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                                    Behavior on scale { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
                                    ColumnLayout {
                                        width: equalizerScroll.availableWidth
                                        spacing: 9
                                        RowLayout { Layout.fillWidth: true
                                            Text { text: "Выход"; color: root.foreground; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 15; font.weight: Font.DemiBold }
                                            Item { Layout.fillWidth: true }
                                            Text { visible: root.outputStreams.length > 0; text: root.outputStreams.length + " прил."; color: root.muted; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 9 }
                                        }
                                        MixerRow { Layout.fillWidth: true; node: Pipewire.defaultAudioSink; master: true; visible: node !== null; onInteractingChanged: window.controlActive = interacting }
                                        Repeater { model: root.outputStreams; MixerRow { required property var modelData; Layout.fillWidth: true; node: modelData; onInteractingChanged: window.controlActive = interacting } }
                                        Text { visible: root.outputStreams.length === 0; text: "Приложения не воспроизводят звук"; color: root.muted; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 9 }
                                        Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; Layout.topMargin: 6; Layout.bottomMargin: 6; color: Qt.alpha(theme.outline, 0.65) }
                                        RowLayout { Layout.fillWidth: true
                                            Text { text: "Вход"; color: root.foreground; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 15; font.weight: Font.DemiBold }
                                            Item { Layout.fillWidth: true }
                                            Text { visible: root.inputStreams.length > 0; text: root.inputStreams.length + " прил."; color: root.muted; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 9 }
                                        }
                                        MixerRow { Layout.fillWidth: true; node: Pipewire.defaultAudioSource; master: true; visible: node !== null; onInteractingChanged: window.controlActive = interacting }
                                        Repeater { model: root.inputStreams; MixerRow { required property var modelData; Layout.fillWidth: true; node: modelData; onInteractingChanged: window.controlActive = interacting } }
                                        Text { visible: root.inputStreams.length === 0; text: "Приложения не используют микрофон"; color: root.muted; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 10 }
                                    }
                                }

                                ColumnLayout {
                                    spacing: 14
                                    opacity: StackLayout.isCurrentItem ? 1 : 0
                                    scale: StackLayout.isCurrentItem ? 1 : 0.985
                                    Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                                    Behavior on scale { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
                                    Rectangle {
                                        Layout.fillWidth: true; Layout.preferredHeight: 100; radius: 18; color: root.surface
                                        ColumnLayout { anchors.fill: parent; anchors.margins: 15
                                            RowLayout { Layout.fillWidth: true; Text { text: "󰃠  Яркость"; color: root.foreground; font.family: "JetBrainsMono Nerd Font" } Item { Layout.fillWidth: true } Text { text: root.brightnessAvailable ? root.brightness + "%" : "Недоступно"; color: root.brightnessAvailable ? root.accent : root.muted; font.family: "JetBrainsMono Nerd Font" } }
                                            StyledSlider {
                                                Layout.fillWidth: true
                                                enabled: root.brightnessAvailable
                                                from: 1
                                                to: 100
                                                value: root.brightnessAvailable ? root.brightness : 1
                                                onPressedChanged: {
                                                    window.controlActive = pressed
                                                    if (!pressed) {
                                                        brightnessWrite.exec(["bash", Quickshell.env("HOME") + "/.config/hypr/brightness.sh", "set", root.brightnessBackend, root.brightnessDevice, String(root.brightness)])
                                                    }
                                                }
                                                onMoved: {
                                                    root.brightness = Math.round(value)
                                                    if (root.brightnessBackend === "gamma") {
                                                        Quickshell.execDetached(["hyprctl", "hyprsunset", "gamma", String(root.brightness)])
                                                    }
                                                }
                                            }
                                        }
                                    }
                                    GridLayout {
                                        Layout.fillWidth: true
                                        columns: 4
                                        columnSpacing: 6
                                        rowSpacing: 6
                                        Repeater {
                                            model: [
                                                {icon:"󰖔", title:"Night Light", status:root.nightLight ? "Включён" : "Выключен", active:root.nightLight, action:"night"},
                                                {icon:"󰑋", title:root.recording ? root.recordingElapsed : "Запись", status:root.recording ? root.recordingSize + " · нажмите для остановки" : "Не активна", active:root.recording, action:"record"},
                                                {icon:"󰹑", title:"Область", status:"Выбрать область", active:false, action:"region"},
                                                {icon:"󰈊", title:"Пипетка", status:"Копирует HEX", active:false, action:"color"},
                                                {icon:"󰐕", title:"OCR", status:"Распознать текст", active:false, action:"ocr"},
                                                {icon:"󰅶", title:"Кофеин", status:"Не давать экрану гаснуть", active:false, action:"caffeine"},
                                                {icon:"󰺵", title:"Игровой режим", status:"Gamemode", active:false, action:"gamemode"}
                                            ]
                                            delegate: Rectangle {
                                                id: actionButton
                                                required property var modelData
                                                readonly property bool recordingExpanded: modelData.action === "record" && root.recording
                                                Layout.fillWidth: true
                                                Layout.columnSpan: recordingExpanded ? 2 : 1
                                                Layout.preferredHeight: recordingExpanded ? 112 : 100
                                                Behavior on Layout.preferredHeight {
                                                    NumberAnimation { duration: 320; easing.type: Easing.OutBack }
                                                }
                                                radius: 11
                                                color: modelData.active
                                                    ? (actionMouse.containsMouse ? Qt.alpha(root.accent, 0.30) : Qt.alpha(root.accent, 0.20))
                                                    : (actionMouse.containsMouse ? root.surfaceAlt : "transparent")
                                                border.width: 1
                                                border.color: modelData.active
                                                    ? Qt.alpha(root.accent, 0.85)
                                                    : (actionMouse.containsMouse ? root.accent : theme.outline)
                                                Behavior on color { ColorAnimation { duration: 150; easing.type: Easing.OutCubic } }
                                                Behavior on border.color { ColorAnimation { duration: 150 } }
                                                Text {
                                                    visible: !actionButton.recordingExpanded
                                                    opacity: actionButton.recordingExpanded ? 0 : 1
                                                    anchors.centerIn: parent
                                                    text: modelData.icon
                                                    color: modelData.active ? root.accent : (actionMouse.containsMouse ? root.accent : root.foreground)
                                                    font.family: "JetBrainsMono Nerd Font"
                                                    font.pixelSize: 32
                                                    font.weight: Font.Bold
                                                    scale: actionMouse.pressed ? 0.88 : (actionMouse.containsMouse ? 1.10 : 1)
                                                    Behavior on color { ColorAnimation { duration: 150 } }
                                                    Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutBack } }
                                                    Behavior on opacity { NumberAnimation { duration: 140 } }
                                                }
                                                RowLayout {
                                                    visible: opacity > 0
                                                    opacity: actionButton.recordingExpanded ? 1 : 0
                                                    scale: actionButton.recordingExpanded ? 1 : 0.94
                                                    anchors.fill: parent
                                                    anchors.leftMargin: 18
                                                    anchors.rightMargin: 18
                                                    spacing: 14
                                                    Behavior on opacity { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }
                                                    Behavior on scale { NumberAnimation { duration: 340; easing.type: Easing.OutBack } }

                                                    Rectangle {
                                                        Layout.preferredWidth: 48
                                                        Layout.preferredHeight: 48
                                                        radius: 24
                                                        color: Qt.alpha(root.accent, 0.18)
                                                        Text {
                                                            anchors.centerIn: parent
                                                            text: "󰑋"
                                                            color: root.accent
                                                            font.family: "JetBrainsMono Nerd Font"
                                                            font.pixelSize: 25
                                                        }
                                                    }

                                                    ColumnLayout {
                                                        Layout.fillWidth: true
                                                        spacing: 3
                                                        RowLayout {
                                                            Layout.fillWidth: true
                                                            spacing: 7
                                                            Rectangle {
                                                                width: 8
                                                                height: 8
                                                                radius: 4
                                                                color: root.critical
                                                                SequentialAnimation on opacity {
                                                                    running: actionButton.recordingExpanded
                                                                    loops: Animation.Infinite
                                                                    NumberAnimation { to: 0.35; duration: 650 }
                                                                    NumberAnimation { to: 1; duration: 650 }
                                                                }
                                                            }
                                                            Text {
                                                                text: "ИДЁТ ЗАПИСЬ"
                                                                color: root.critical
                                                                font.family: "JetBrainsMono Nerd Font"
                                                                font.pixelSize: 10
                                                                font.weight: Font.Bold
                                                            }
                                                            Item { Layout.fillWidth: true }
                                                            Text {
                                                                text: root.recordingElapsed
                                                                color: root.foreground
                                                                font.family: "JetBrainsMono Nerd Font"
                                                                font.pixelSize: 20
                                                                font.weight: Font.Bold
                                                            }
                                                        }
                                                        Text {
                                                            Layout.fillWidth: true
                                                            text: "MP4  ·  " + root.recordingSize
                                                            color: root.foreground
                                                            font.family: "JetBrainsMono Nerd Font"
                                                            font.pixelSize: 11
                                                        }
                                                        Text {
                                                            Layout.fillWidth: true
                                                            text: root.recordingFile ? root.recordingFile.split("/").pop() : "Файл подготавливается…"
                                                            color: root.muted
                                                            font.family: "JetBrainsMono Nerd Font"
                                                            font.pixelSize: 9
                                                            elide: Text.ElideMiddle
                                                        }
                                                        Text {
                                                            text: "Нажмите, чтобы остановить и сохранить"
                                                            color: root.accent
                                                            font.family: "JetBrainsMono Nerd Font"
                                                            font.pixelSize: 9
                                                        }
                                                    }
                                                }
                                                ThemedToolTip {
                                                    target: actionButton
                                                    labelText: actionButton.modelData.title + " — " + actionButton.modelData.status
                                                    shown: actionMouse.containsMouse
                                                    placement: "bottom"
                                                }
                                                MouseArea { id: actionMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: {
                                                    if (modelData.action === "night") actionProcess.exec([Quickshell.env("HOME") + "/.config/hypr/command-center-action.sh", "night-light"])
                                                    else if (modelData.action === "record") actionProcess.exec([Quickshell.env("HOME") + "/.config/hypr/command-center-action.sh", root.recording ? "stop-record" : "record"])
                                                    else if (modelData.action === "region") { window.revealStage = 0; actionProcess.exec([Quickshell.env("HOME") + "/.config/hypr/command-center-action.sh", "record-region"]) }
                                                    else if (modelData.action === "color") { window.revealStage = 0; pickerProcess.running = true }
                                                    else if (modelData.action === "ocr") {
                                                        window.revealStage = 0
                                                        Quickshell.execDetached([
                                                            Quickshell.env("HOME") + "/.config/hypr/command-center-action.sh",
                                                            "ocr"
                                                        ])
                                                    }
                                                } }
                                            }
                                        }
                                    }
                                    Rectangle {
                                        visible: root.phoneOnline
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: 96
                                        radius: 18
                                        color: root.surface
                                        border.width: 1
                                        border.color: root.phoneOnline ? theme.outline : Qt.alpha(root.critical, 0.65)

                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.margins: 14
                                            spacing: 12
                                            Text { text: root.phoneOnline ? "󰄜" : "󰄧"; color: root.phoneOnline ? root.accent : root.muted; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 28 }
                                            ColumnLayout {
                                                Layout.fillWidth: true
                                                spacing: 3
                                                Text { text: root.phoneName; color: root.foreground; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 12; font.weight: Font.DemiBold }
                                                Text { text: root.phoneOnline ? "Подключён по Wi‑Fi" : "Не в сети"; color: root.phoneOnline ? theme.success : root.muted; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 9 }
                                            }
                                            ColumnLayout {
                                                visible: root.phoneOnline
                                                spacing: 2
                                                Text { Layout.alignment: Qt.AlignHCenter; text: root.phoneCharge >= 0 ? root.phoneCharge + "%" : "—"; color: root.phoneCharge >= 0 && root.phoneCharge < 20 ? root.critical : root.foreground; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 16; font.weight: Font.Bold }
                                                Text { text: root.phoneCharge >= 0 ? (root.phoneCharging ? "󰂄 зарядка" : "󰁹 батарея") : "заряд недоступен"; color: root.muted; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 8 }
                                            }
                                            Rectangle {
                                                visible: root.phoneOnline
                                                Layout.preferredWidth: 38; Layout.preferredHeight: 38; radius: 13
                                                color: ringMouse.containsMouse ? root.surfaceAlt : root.background
                                                Text { anchors.centerIn: parent; text: "󰋙"; color: root.accent; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 17 }
                                                MouseArea { id: ringMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: phoneAction.exec(["kdeconnect-cli", "--device", root.phoneId, "--ring"]) }
                                            }
                                            Rectangle {
                                                visible: root.phoneOnline
                                                Layout.preferredWidth: 38; Layout.preferredHeight: 38; radius: 13
                                                color: sendMouse.containsMouse ? root.surfaceAlt : root.background
                                                Text { anchors.centerIn: parent; text: "󰆏"; color: root.foreground; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 17 }
                                                MouseArea { id: sendMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: phoneAction.exec(["kdeconnect-cli", "--device", root.phoneId, "--send-clipboard"]) }
                                            }
                                        }
                                    }
                                    Item { Layout.fillHeight: true }
                                }

                                GridView {
                                    id: gallery
                                    clip: true
                                    opacity: StackLayout.isCurrentItem ? 1 : 0
                                    scale: StackLayout.isCurrentItem ? 1 : 0.985
                                    Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                                    Behavior on scale { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
                                    cellWidth: width / 2
                                    cellHeight: 150
                                    model: root.recentFiles
                                    delegate: Item {
                                        required property var modelData
                                        width: gallery.cellWidth; height: gallery.cellHeight
                                        Rectangle { anchors.fill: parent; anchors.margins: 5; radius: 16; color: root.surface; clip: true
                                            Image { anchors.fill: parent; source: modelData.thumbnail.length > 0 ? "file://" + modelData.thumbnail : ""; fillMode: Image.PreserveAspectCrop; asynchronous: false; cache: true }
                                            Rectangle { anchors.left: parent.left; anchors.top: parent.top; anchors.margins: 9; width: 28; height: 24; radius: 8; color: Qt.rgba(0.08,0.07,0.06,0.78); visible: modelData.path.match(/\\.(mp4|mkv)$/i) !== null
                                                Text { anchors.centerIn: parent; text: "󰕧"; color: root.foreground; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 12 }
                                            }
                                            Rectangle { anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom; height: 38; color: Qt.rgba(0.08,0.07,0.06,0.86)
                                                Text { anchors.fill: parent; anchors.margins: 9; text: modelData.path.split("/").pop(); elide: Text.ElideMiddle; color: root.foreground; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 9 }
                                            }
                                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: Quickshell.execDetached(["xdg-open", modelData.path]) }
                                        }
                                    }
                                }

                                ColumnLayout {
                                    spacing: 12
                                    opacity: StackLayout.isCurrentItem ? 1 : 0
                                    scale: StackLayout.isCurrentItem ? 1 : 0.985
                                    Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                                    Behavior on scale { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }

                                    RowLayout {
                                        Layout.fillWidth: true
                                        Text { text: "Уведомления"; color: root.foreground; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 16; font.weight: Font.DemiBold }
                                        Item { Layout.fillWidth: true }
                                        Rectangle {
                                            id: dndButton
                                            Layout.preferredWidth: 40; Layout.preferredHeight: 40; radius: 20
                                            color: root.notificationDnd
                                                ? (dndMouse.containsMouse ? theme.selected : root.surfaceAlt)
                                                : (dndMouse.containsMouse ? root.surfaceAlt : root.surface)
                                            border.width: 1; border.color: root.notificationDnd ? root.accent : theme.outline
                                            Behavior on color { ColorAnimation { duration: 150; easing.type: Easing.OutCubic } }
                                            Behavior on border.color { ColorAnimation { duration: 150 } }
                                            Text { anchors.centerIn: parent; text: root.notificationDnd ? "󰂛" : "󰂚"; color: root.notificationDnd ? root.accent : root.foreground; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 19; scale: dndMouse.containsMouse ? 1.10 : 1; Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutBack } } }
                                            MouseArea { id: dndMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: notificationAction.exec(["quickshell", "ipc", "call", "notifications", "toggleDnd"]) }
                                        }
                                        Rectangle {
                                            Layout.preferredWidth: 40; Layout.preferredHeight: 40; radius: 20
                                            color: clearMouse.containsMouse ? Qt.alpha(root.critical, 0.22) : root.surface
                                            border.width: 1; border.color: clearMouse.containsMouse ? root.critical : theme.outline
                                            Behavior on color { ColorAnimation { duration: 150; easing.type: Easing.OutCubic } }
                                            Behavior on border.color { ColorAnimation { duration: 150 } }
                                            Text { anchors.centerIn: parent; text: "󰩹"; color: clearMouse.containsMouse ? root.critical : root.muted; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 18; scale: clearMouse.containsMouse ? 1.10 : 1; Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutBack } } }
                                            MouseArea { id: clearMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: notificationAction.exec(["quickshell", "ipc", "call", "notifications", "clear"]) }
                                        }
                                    }

                                    Text {
                                        visible: root.notifications.length === 0
                                        Layout.alignment: Qt.AlignCenter
                                        text: "Новых уведомлений нет"
                                        color: root.muted
                                        font.family: "JetBrainsMono Nerd Font"
                                        font.pixelSize: 11
                                    }

                                    ListView {
                                        Layout.fillWidth: true
                                        Layout.fillHeight: true
                                        clip: true
                                        spacing: 8
                                        model: root.notifications

                                        delegate: Rectangle {
                                            id: notificationRow
                                            required property var modelData
                                            property bool expanded: false
                                            width: ListView.view.width
                                            height: expanded ? Math.max(78, contentRow.implicitHeight + 24) : 78
                                            radius: 16
                                            clip: true
                                            color: root.surface
                                            border.width: 1
                                            border.color: modelData.urgency === 2 ? root.critical : theme.outline
                                            Behavior on height { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

                                            MouseArea {
                                                anchors.fill: parent
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: notificationRow.expanded = !notificationRow.expanded
                                            }

                                            RowLayout {
                                                id: contentRow
                                                anchors.fill: parent
                                                anchors.margins: 12
                                                spacing: 10
                                                Rectangle {
                                                    Layout.preferredWidth: 42; Layout.preferredHeight: 42; radius: 14
                                                    Layout.alignment: Qt.AlignTop
                                                    color: root.surfaceAlt
                                                    border.width: 1; border.color: theme.outline
                                                    Image { anchors.centerIn: parent; width: 26; height: 26; source: Quickshell.iconPath(notificationRow.modelData.appIcon, true); fillMode: Image.PreserveAspectFit }
                                                }
                                                ColumnLayout {
                                                    Layout.fillWidth: true
                                                    spacing: 3
                                                    Text { Layout.fillWidth: true; text: notificationRow.modelData.summary; elide: Text.ElideRight; color: root.foreground; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 11; font.weight: Font.DemiBold }
                                                    Text {
                                                        Layout.fillWidth: true
                                                        text: notificationRow.modelData.body || notificationRow.modelData.appName
                                                        wrapMode: notificationRow.expanded ? Text.Wrap : Text.NoWrap
                                                        elide: notificationRow.expanded ? Text.ElideNone : Text.ElideRight
                                                        color: root.muted
                                                        font.family: "JetBrainsMono Nerd Font"
                                                        font.pixelSize: 9
                                                    }
                                                }
                                                Rectangle {
                                                    Layout.preferredWidth: 30; Layout.preferredHeight: 30; radius: 15
                                                    Layout.alignment: Qt.AlignTop
                                                    color: dismissMouse.containsMouse ? root.surfaceAlt : "transparent"
                                                    Behavior on color { ColorAnimation { duration: 140 } }
                                                    Text { anchors.centerIn: parent; text: "󰅖"; color: dismissMouse.containsMouse ? root.foreground : root.muted; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 14; rotation: dismissMouse.containsMouse ? 90 : 0; Behavior on rotation { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } } }
                                                    MouseArea { id: dismissMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: notificationAction.exec(["quickshell", "ipc", "call", "notifications", "dismiss", String(notificationRow.modelData.id)]) }
                                                }
                                            }
                                        }
                                    }
                                }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    Variants {
        model: Quickshell.screens

        delegate: Component {
            PanelWindow {
                id: recordingIndicatorWindow
                required property var modelData

                screen: modelData
                anchors.top: true
                anchors.left: true
                anchors.right: true
                implicitHeight: 52
                color: "transparent"
                exclusionMode: ExclusionMode.Ignore
                mask: Region {}
                WlrLayershell.layer: WlrLayer.Overlay

                Item {
                    anchors.right: parent.right
                    anchors.rightMargin: -6
                    y: root.recording ? -6 : -30
                    width: 30
                    height: 30
                    opacity: root.recording ? 1 : 0
                    scale: root.recording ? 1 : 0.65

                    Behavior on y { NumberAnimation { duration: 360; easing.type: Easing.OutBack } }
                    Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                    Behavior on scale { NumberAnimation { duration: 380; easing.type: Easing.OutBack } }

                    Rectangle {
                        anchors.centerIn: parent
                        width: 24
                        height: 24
                        radius: 12
                        color: Qt.alpha(theme.accent, 0.18)
                        border.width: 1
                        border.color: Qt.alpha(theme.accent, 0.42)

                        SequentialAnimation on scale {
                            running: root.recording
                            loops: Animation.Infinite
                            NumberAnimation { to: 1.28; duration: 760; easing.type: Easing.OutCubic }
                            NumberAnimation { to: 1; duration: 760; easing.type: Easing.InCubic }
                        }
                        SequentialAnimation on opacity {
                            running: root.recording
                            loops: Animation.Infinite
                            NumberAnimation { to: 0.35; duration: 760; easing.type: Easing.OutCubic }
                            NumberAnimation { to: 1; duration: 760; easing.type: Easing.InCubic }
                        }
                    }

                    Rectangle {
                        anchors.centerIn: parent
                        width: 9
                        height: 9
                        radius: 4.5
                        color: theme.accent
                        border.width: 1
                        border.color: Qt.lighter(theme.accent, 1.35)
                    }
                }
            }
        }
    }
}
