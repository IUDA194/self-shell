import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Networking
import Quickshell.Bluetooth
import Quickshell.Services.Notifications
import Quickshell.Services.Pipewire
import Quickshell.Wayland

ShellRoot {
    id: root

    Theme { id: theme }

    // Compact left rail and its native power overlay.

    property color foreground: theme.foreground
    property color muted: theme.muted
    property color accent: theme.accent
    property string keyboardLayout: "English (US)"
    property bool vpnConnected: false
    property string vpnTooltip: "Проверка состояния V2RayA…"
    property bool powerMenuOpen: false
    property var powerMenuScreen: null
    property bool connectivityMenuOpen: false
    property string connectivityPage: "wifi"
    property var connectivityMenuScreen: null
    property var notificationEntries: []
    property var activeToast: null
    property var toastEntries: []
    property bool toastClosing: false
    property var toastScreen: null
    property bool notificationCenterOpen: false
    property var notificationCenterScreen: null
    property bool notificationDnd: false
    property bool notificationGrouping: true

    function run(command) {
        Quickshell.execDetached(["bash", "-lc", command])
    }

    function focusedScreen() {
        const monitor = Hyprland.focusedMonitor
        if (!monitor)
            return Quickshell.screens[0]
        return Quickshell.screens.find(screen => screen.name === monitor.name)
            || Quickshell.screens[0]
    }

    function removeNotification(id) {
        notificationEntries = notificationEntries.filter(entry => entry.notification.id !== id)
        toastEntries = toastEntries.filter(entry => entry.notification.id !== id)
        if (activeToast && activeToast.notification.id === id) {
            activeToast = toastEntries.length > 0 ? toastEntries[0] : null
            if (toastEntries.length > 0)
                toastTimer.restart()
            else
                toastTimer.stop()
        }
    }

    function dismissNotification(notification) {
        removeNotification(notification.id)
        notification.dismiss()
    }

    function clearNotifications() {
        const current = notificationEntries.slice()
        notificationEntries = []
        toastEntries = []
        activeToast = null
        toastTimer.stop()
        for (let i = 0; i < current.length; ++i)
            current[i].notification.dismiss()
    }

    function showNotification(notification) {
        notification.tracked = true
        removeNotification(notification.id)
        const entry = { notification: notification, createdAt: Date.now() }
        notificationEntries = [entry].concat(notificationEntries)
        notification.closed.connect(function() { root.removeNotification(notification.id) })

        if (!notificationDnd && !notificationCenterOpen) {
            activeToast = entry
            toastClosing = false
            toastEntries = [entry].concat(toastEntries).slice(0, 3)
            toastScreen = focusedScreen()
            const requested = Number(notification.expireTimeout)
            toastTimer.interval = requested > 0 ? Math.max(2500, requested) : 5000
            toastTimer.restart()
        }
    }

    NotificationServer {
        keepOnReload: true
        persistenceSupported: true
        bodySupported: true
        bodyMarkupSupported: false
        actionsSupported: true
        actionIconsSupported: false
        imageSupported: true
        onNotification: notification => root.showNotification(notification)
    }

    IpcHandler {
        target: "notifications"

        function listJson(): string {
            return JSON.stringify(root.notificationEntries.map(function(entry) {
                const notification = entry.notification
                return {
                    id: String(notification.id),
                    appName: notification.appName || notification.desktopEntry || "Система",
                    appIcon: notification.appIcon || notification.desktopEntry || "preferences-system-notifications",
                    summary: notification.summary || "Уведомление",
                    body: notification.body || "",
                    urgency: Number(notification.urgency),
                    createdAt: Number(entry.createdAt)
                }
            }))
        }

        function dismiss(id: string): void {
            const entry = root.notificationEntries.find(item => String(item.notification.id) === id)
            if (entry)
                root.dismissNotification(entry.notification)
        }

        function toggle(): void {
            root.notificationCenterOpen = false
            root.activeToast = null
            root.toastEntries = []
            toastTimer.stop()
            Quickshell.execDetached([
                "quickshell", "ipc", "--path",
                Quickshell.env("HOME") + "/.config/hypr/command-center",
                "call", "commandCenter", "notifications"
            ])
        }

        function close(): void {
            root.notificationCenterOpen = false
        }

        function clear(): void {
            root.clearNotifications()
        }

        function dndState(): bool {
            return root.notificationDnd
        }

        function toggleDnd(): bool {
            root.notificationDnd = !root.notificationDnd
            return root.notificationDnd
        }
    }

    Timer {
        id: toastTimer
        interval: 5000
        onTriggered: {
            root.toastClosing = true
            toastCloseTimer.restart()
        }
    }

    Timer {
        id: toastCloseTimer
        interval: 340
        onTriggered: {
            root.activeToast = null
            root.toastEntries = []
            root.toastClosing = false
        }
    }

    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }

    PwObjectTracker {
        objects: [Pipewire.defaultAudioSink]
    }

    Process {
        id: layoutProcess
        command: ["bash", "-lc", "hyprctl devices -j | jq -r '.keyboards[] | select(.main == true) | .active_keymap' | head -1"]
        running: true
        stdout: StdioCollector {
            id: layoutOutput
            onStreamFinished: {
                const value = text.trim()
                if (value.length > 0)
                    root.keyboardLayout = value
                layoutTimer.restart()
            }
        }
    }

    Process {
        id: vpnProcess
        command: ["bash", "-lc", "env WAYBAR_COMPACT=1 ${XDG_CONFIG_HOME:-$HOME/.config}/quickshell/scripts/vpn-status.sh"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const status = JSON.parse(text)
                    root.vpnConnected = status.class === "online"
                    root.vpnTooltip = status.tooltip || "V2RayA"
                } catch (error) {
                    root.vpnConnected = false
                    root.vpnTooltip = "Не удалось получить статус V2RayA"
                }
                vpnTimer.restart()
            }
        }
    }

    Timer {
        id: layoutTimer
        // Fallback only; normal updates arrive immediately through Hyprland IPC.
        interval: 10000
        running: true
        repeat: true
        onTriggered: layoutProcess.running = true
    }

    Timer {
        id: vpnTimer
        interval: 5000
        running: true
        repeat: true
        onTriggered: vpnProcess.running = true
    }

    Connections {
        target: Hyprland

        function onRawEvent(event) {
            if (event.name !== "activelayout")
                return

            const separator = event.data.lastIndexOf(",")
            root.keyboardLayout = separator >= 0
                ? event.data.slice(separator + 1).trim()
                : event.data.trim()
        }
    }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: panel
            required property var modelData

            screen: modelData
            color: "transparent"
            readonly property bool connectivityActive: root.connectivityMenuOpen
                && (root.connectivityMenuScreen === null || root.connectivityMenuScreen === modelData)
            // Keep the layer-shell surface stable. Resizing this window makes
            // the compositor expose a travelling edge during close.
            implicitWidth: 460
            implicitHeight: 900
            anchors.left: true
            exclusiveZone: 55
            mask: sidebarInputRegion
            WlrLayershell.keyboardFocus: connectivityActive
                ? WlrKeyboardFocus.OnDemand
                : WlrKeyboardFocus.None

            Region {
                id: sidebarInputRegion
                x: 0
                y: 0
                width: 55
                height: panel.height

                Region {
                    x: 55
                    y: connectivityPanel.surfaceTop
                    width: panel.connectivityActive
                        ? Math.max(0, connectivityPanel.surfaceRight - 55)
                        : 0
                    height: panel.connectivityActive
                        ? Math.max(0, connectivityPanel.surfaceBottom - connectivityPanel.surfaceTop)
                        : 0
                }
            }

            Canvas {
                id: sidebarSurface
                z: 0
                anchors.fill: parent
                antialiasing: true

                onWidthChanged: requestPaint()
                onHeightChanged: requestPaint()

                Connections {
                    target: connectivityPanel
                    function onRevealProgressChanged() { sidebarSurface.requestPaint() }
                    function onSurfaceTopChanged() { sidebarSurface.requestPaint() }
                    function onSurfaceBottomChanged() { sidebarSurface.requestPaint() }
                    function onSurfaceRightChanged() { sidebarSurface.requestPaint() }
                    function onPageChanged() { sidebarSurface.requestPaint() }
                }

                Connections {
                    target: panel
                    function onConnectivityActiveChanged() {
                        // The menu becomes invisible in the same update that
                        // ends closing, so force one final compact-frame paint.
                        sidebarSurface.requestPaint()
                        Qt.callLater(() => sidebarSurface.requestPaint())
                    }
                }

                Connections {
                    target: theme
                    function onBackgroundChanged() { sidebarSurface.requestPaint() }
                    function onOutlineChanged() { sidebarSurface.requestPaint() }
                }

                onPaint: {
                    const ctx = getContext("2d")
                    const h = height
                    const railRight = 55
                    const p = panel.connectivityActive
                        ? connectivityPanel.revealProgress
                        : 0
                    const top = connectivityPanel.surfaceTop
                    const bottom = connectivityPanel.surfaceBottom
                    const right = railRight + (connectivityPanel.surfaceRight - railRight) * p
                    const extensionWidth = Math.max(0, right - railRight)
                    // Preserve a capsule-like leading edge while collapsing;
                    // only reduce the radius when the remaining width itself
                    // becomes narrower than the full corner diameter.
                    const radius = Math.min(22, extensionWidth / 2)
                    const shoulder = Math.min(18, extensionWidth / 2)
                    const lowerShoulder = Math.min(shoulder, Math.max(0, h - 9 - bottom))

                    ctx.reset()
                    ctx.clearRect(0, 0, width, height)
                    ctx.beginPath()
                    ctx.moveTo(0, 0)
                    ctx.lineTo(46, 0)
                    ctx.quadraticCurveTo(railRight, 0, railRight, 9)
                    ctx.lineTo(railRight, top - shoulder)

                    if (p > 0.001) {
                        ctx.bezierCurveTo(railRight, top - 7 * p,
                                          railRight + 7 * p, top,
                                          railRight + radius, top)
                        ctx.lineTo(right - radius, top)
                        ctx.quadraticCurveTo(right, top, right, top + radius)
                        ctx.lineTo(right, bottom - radius)
                        ctx.quadraticCurveTo(right, bottom, right - radius, bottom)
                        ctx.lineTo(railRight + radius, bottom)
                        ctx.bezierCurveTo(railRight + 7 * p, bottom,
                                          railRight, bottom + Math.min(7 * p, lowerShoulder),
                                          railRight, bottom + lowerShoulder)
                    }

                    ctx.lineTo(railRight, h - 9)
                    ctx.quadraticCurveTo(railRight, h, 46, h)
                    ctx.lineTo(0, h)
                    ctx.closePath()
                    // Exact launcher surface and outline colours.
                    ctx.fillStyle = theme.background
                    ctx.fill()
                    ctx.lineWidth = 1.25
                    ctx.strokeStyle = theme.outline

                    if (connectivityPanel.closing) {
                        // Crossfade from the expanded outline to the static
                        // rail outline, avoiding both a travelling hard line
                        // and a one-frame border flash at the end.
                        const borderProgress = Math.max(0, Math.min(1, p))
                        // Reveal the compact outline only at the very end,
                        // once the expanded surface is almost fully collapsed.
                        const compactAlpha = Math.max(0, Math.min(1, (0.12 - borderProgress) / 0.12))
                        ctx.globalAlpha = 1 - compactAlpha
                        ctx.stroke()

                        ctx.globalAlpha = compactAlpha
                        ctx.beginPath()
                        ctx.moveTo(0, 0)
                        ctx.lineTo(46, 0)
                        ctx.quadraticCurveTo(railRight, 0, railRight, 9)
                        ctx.lineTo(railRight, h - 9)
                        ctx.quadraticCurveTo(railRight, h, 46, h)
                        ctx.lineTo(0, h)
                        ctx.closePath()
                        ctx.stroke()
                        ctx.globalAlpha = 1
                    } else {
                        ctx.stroke()
                    }
                }
            }

            Rectangle {
                id: rail
                z: 2
                x: -9
                // The layer window grows to host popouts, but the visible rail
                // must always retain its compact width.
                width: 64
                height: parent.height
                radius: 9
                // Content-only rail: sidebarSurface owns the one shared shape.
                color: "transparent"
                border.width: 0
                border.color: theme.outline

                // Workspaces stay compact: Quickshell only exposes workspaces that exist.
                Column {
                    id: workspaces
                    anchors.top: parent.top
                    anchors.topMargin: 18
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 2

                    Repeater {
                        model: Hyprland.workspaces

                        delegate: Item {
                            required property var modelData
                            width: 44
                            height: 34

                            Rectangle {
                                anchors.centerIn: parent
                                width: 32
                                height: 28
                                radius: 6
                                color: workspaceMouse.containsMouse ? theme.hover : "transparent"
                            }

                            Text {
                                anchors.centerIn: parent
                                text: modelData.name
                                color: modelData.focused ? root.foreground : root.muted
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 11
                                font.weight: modelData.focused ? Font.Bold : Font.Medium
                            }

                            MouseArea {
                                id: workspaceMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: modelData.activate()
                            }
                        }
                    }
                }

                Column {
                    anchors.centerIn: parent
                    spacing: 20

                    Text {
                        width: 44
                        horizontalAlignment: Text.AlignHCenter
                        text: Qt.formatDateTime(clock.date, "HH\nmm")
                        color: root.foreground
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 15
                        font.weight: Font.Bold
                        lineHeight: 1.15
                    }

                    Text {
                        width: 44
                        horizontalAlignment: Text.AlignHCenter
                        text: Qt.formatDateTime(clock.date, "dd\nMM")
                        color: root.muted
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 9
                        font.weight: Font.DemiBold
                        lineHeight: 1.3
                    }
                }

                Column {
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 14
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 0

                    BarButton {
                        text: {
                            const map = {"English (US)": "EN", "English": "EN", "Russian": "RU", "Ukrainian": "UA", "German": "DE"}
                            const keymap = root.keyboardLayout
                            return map[keymap] || (keymap.length >= 2 ? keymap.slice(0, 2).toUpperCase() : "EN")
                        }
                        fontPixelSize: 11
                        tooltip: "Раскладка клавиатуры"
                        onClicked: {
                            if (root.connectivityMenuOpen && root.connectivityPage === "keyboard") {
                                connectivityPanel.close()
                                return
                            }
                            root.connectivityPage = "keyboard"
                            root.connectivityMenuScreen = panel.screen
                            root.connectivityMenuOpen = true
                        }
                    }

                    BarButton {
                        text: Networking.wifiEnabled ? "" : "󰤮"
                        color: Networking.wifiEnabled ? root.foreground : root.accent
                        tooltip: Networking.wifiEnabled ? "Wi-Fi включён" : "Wi-Fi выключен"
                        onClicked: {
                            if (root.connectivityMenuOpen && root.connectivityPage === "wifi") {
                                connectivityPanel.close()
                                return
                            }
                            root.connectivityPage = "wifi"
                            root.connectivityMenuScreen = panel.screen
                            root.connectivityMenuOpen = true
                        }
                    }

                    BarButton {
                        readonly property var adapter: Bluetooth.defaultAdapter
                        readonly property bool connected: Bluetooth.devices.values.some(device => device.connected)
                        text: connected ? "󰂱" : (adapter && adapter.enabled ? "󰂯" : "󰂲")
                        color: adapter && adapter.enabled ? root.foreground : root.accent
                        tooltip: connected ? "Bluetooth подключён" : (adapter && adapter.enabled ? "Bluetooth включён" : "Bluetooth выключен")
                        onClicked: {
                            if (root.connectivityMenuOpen && root.connectivityPage === "bluetooth") {
                                connectivityPanel.close()
                                return
                            }
                            root.connectivityPage = "bluetooth"
                            root.connectivityMenuScreen = panel.screen
                            root.connectivityMenuOpen = true
                        }
                    }

                    BarButton {
                        text: root.vpnConnected ? "" : ""
                        color: root.vpnConnected ? root.foreground : root.accent
                        tooltip: root.vpnTooltip
                        onClicked: root.run("xdg-open http://localhost:2017/")
                    }

                    BarButton {
                        id: volumeButton
                        readonly property var sink: Pipewire.defaultAudioSink
                        readonly property var audio: sink ? sink.audio : null
                        text: !audio || audio.muted ? "󰝟" : (audio.volume < 0.34 ? "" : (audio.volume < 0.67 ? "" : ""))
                        color: audio && audio.muted ? root.accent : root.foreground
                        tooltip: audio ? "Громкость: " + Math.round(audio.volume * 100) + "%" : "Звук"
                        onClicked: {
                            if (root.connectivityMenuOpen && root.connectivityPage === "audio") {
                                connectivityPanel.close()
                                return
                            }
                            root.connectivityPage = "audio"
                            root.connectivityMenuScreen = panel.screen
                            root.connectivityMenuOpen = true
                        }
                        onWheelUp: if (audio) audio.volume = Math.min(1.0, audio.volume + 0.05)
                        onWheelDown: if (audio) audio.volume = Math.max(0.0, audio.volume - 0.05)
                    }

                }
            }

            ConnectivityMenu {
                id: connectivityPanel
                z: 3
                anchors.fill: parent
                page: root.connectivityPage
                keyboardLayout: root.keyboardLayout
                visible: panel.connectivityActive
                onCloseRequested: root.connectivityMenuOpen = false
            }
        }
    }

    Variants {
        model: Quickshell.screens

        PowerMenu {
            required property var modelData

            screen: modelData
            visible: root.powerMenuOpen
                && (root.powerMenuScreen === null || root.powerMenuScreen === modelData)
            onCloseRequested: root.powerMenuOpen = false
            onLockRequested: root.run(Quickshell.env("HOME") + "/.config/hypr/hyprlock-current.sh")
            onSuspendRequested: root.run("systemctl suspend")
            onRebootRequested: root.run("systemctl reboot")
            onPoweroffRequested: root.run("systemctl poweroff")
        }
    }

    Variants {
        model: Quickshell.screens

        NotificationCenter {
            required property var modelData

            screen: modelData
            visible: root.notificationCenterOpen
                && root.notificationCenterScreen === modelData
            entries: root.notificationEntries
            dnd: root.notificationDnd
            grouped: root.notificationGrouping
            onCloseRequested: root.notificationCenterOpen = false
            onClearRequested: root.clearNotifications()
            onDndToggleRequested: root.notificationDnd = !root.notificationDnd
            onGroupingToggleRequested: root.notificationGrouping = !root.notificationGrouping
            onDismissRequested: notification => root.dismissNotification(notification)
        }
    }

    Variants {
        model: Quickshell.screens

        NotificationToast {
            required property var modelData

            screen: modelData
            visible: root.toastEntries.length > 0 && root.toastScreen === modelData
            entries: root.toastEntries
            closing: root.toastClosing
            onDismissRequested: notification => root.dismissNotification(notification)
        }
    }
}
