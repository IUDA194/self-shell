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

    property string interfaceStyle: "modern"
    property string panelPosition: "left"
    property string notificationPosition: "bottom-right"
    property string notificationCenterPosition: "right"
    readonly property bool minimum: interfaceStyle === "minimum"
    // SELF_SHELL_COMPOSITOR is optional; use the active Wayland session too so
    // a manually restarted panel still controls Niri rather than Hyprland.
    readonly property bool isNiri: Quickshell.env("SELF_SHELL_COMPOSITOR") === "niri"
        || Quickshell.env("NIRI_SOCKET").length > 0
        || Quickshell.env("XDG_CURRENT_DESKTOP").toLowerCase().indexOf("niri") >= 0
    property var niriWorkspaces: []

    FileView {
        id: interfaceStyleFile
        path: Quickshell.env("HOME") + "/.config/self-shell/interface-style.json"
        blockLoading: true
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            try {
                const state = JSON.parse(text())
                root.interfaceStyle = state.style || "modern"
                root.panelPosition = state.panelPosition || "left"
                root.notificationPosition = state.notificationPosition || "bottom-right"
                root.notificationCenterPosition = state.notificationCenterPosition || "right"
            }
            catch (error) { root.interfaceStyle = "modern" }
        }
    }

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
        if (isNiri)
            return Quickshell.screens[0]
        const monitor = Hyprland.focusedMonitor
        if (!monitor)
            return Quickshell.screens[0]
        return Quickshell.screens.find(screen => screen.name === monitor.name)
            || Quickshell.screens[0]
    }

    function weekdayShort(date) {
        return ["SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"][date.getDay()]
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

    IpcHandler {
        target: "panel"

        function ai(): void {
            root.connectivityPage = "ai"
            root.connectivityMenuScreen = null
            root.connectivityMenuOpen = true
        }

        function refreshKeyboardLayout(): void {
            layoutProcess.running = true
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
        command: ["bash", "-lc", root.isNiri
            ? "niri msg -j keyboard-layouts | jq -r '.names[.current_idx] // .current_layout // empty'"
            : "hyprctl devices -j | jq -r '.keyboards[] | select(.main == true) | .active_keymap' | head -1"]
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
        id: niriWorkspacesProcess
        command: ["niri", "msg", "-j", "workspaces"]
        running: root.isNiri
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.niriWorkspaces = JSON.parse(text) }
                catch (error) { root.niriWorkspaces = [] }
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
        // Niri's Win+Space binding sends a direct IPC refresh. This remains a
        // fallback for changes initiated outside the self-shell controls.
        interval: 1000
        running: true
        repeat: true
        onTriggered: {
            layoutProcess.running = true
            if (root.isNiri)
                niriWorkspacesProcess.running = true
        }
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
        enabled: !root.isNiri

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
            visible: true
            color: "transparent"
            readonly property bool connectivityActive: root.connectivityMenuOpen
                && (root.connectivityMenuScreen === null || root.connectivityMenuScreen === modelData)
            // Keep the layer-shell surface stable. Resizing this window makes
            // the compositor expose a travelling edge during close.
            implicitWidth: root.minimum && root.panelPosition === "top" ? screen.width
                : root.minimum ? 550 : 460
            implicitHeight: root.minimum ? screen.height : 900
            anchors.top: root.minimum
            anchors.bottom: root.minimum
            anchors.left: true
            exclusiveZone: root.minimum && root.panelPosition === "top" ? 0
                : root.minimum ? 38 : 55
            mask: sidebarInputRegion
            WlrLayershell.keyboardFocus: connectivityActive
                ? WlrKeyboardFocus.OnDemand
                : WlrKeyboardFocus.None

            Region {
                id: sidebarInputRegion
                x: 0
                y: 0
                width: root.minimum && root.panelPosition === "top" ? 0
                    : root.minimum ? 38 : 55
                height: panel.height

                Region {
                    x: connectivityPanel.surfaceLeft
                    y: connectivityPanel.surfaceTop
                    width: panel.connectivityActive
                        ? connectivityPanel.surfaceRight - connectivityPanel.surfaceLeft
                        : 0
                    height: panel.connectivityActive
                        ? Math.max(0, connectivityPanel.surfaceBottom - connectivityPanel.surfaceTop)
                        : 0
                }
            }

            Canvas {
                id: sidebarSurface
                visible: !root.minimum || root.panelPosition === "left"
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
                    const railRight = root.minimum ? 38 : 55
                    if (root.minimum && root.panelPosition === "top") {
                        ctx.reset()
                        ctx.clearRect(0, 0, width, height)
                        ctx.fillStyle = theme.surface
                        ctx.fillRect(0, 0, railRight, h)
                        ctx.lineWidth = 1.5
                        ctx.strokeStyle = theme.accent
                        ctx.beginPath()
                        ctx.moveTo(railRight - 0.5, 0)
                        ctx.lineTo(railRight - 0.5, h)
                        ctx.stroke()
                        return
                    }
                    const p = panel.connectivityActive
                        ? connectivityPanel.revealProgress
                        : 0
                    const top = connectivityPanel.surfaceTop
                    const bottom = connectivityPanel.surfaceBottom
                    const right = railRight + (connectivityPanel.surfaceRight - railRight) * p
                    const extensionWidth = Math.max(0, right - railRight)
                    if (root.minimum) {
                        ctx.reset()
                        ctx.clearRect(0, 0, width, height)
                        ctx.beginPath()
                        ctx.moveTo(0, 0)
                        ctx.lineTo(railRight, 0)
                        ctx.lineTo(railRight, top)
                        if (p > 0.001) {
                            ctx.lineTo(right, top)
                            ctx.lineTo(right, bottom)
                            ctx.lineTo(railRight, bottom)
                        }
                        ctx.lineTo(railRight, h)
                        ctx.lineTo(0, h)
                        ctx.closePath()
                        ctx.fillStyle = theme.background
                        ctx.fill()
                        ctx.lineWidth = 1
                        ctx.strokeStyle = theme.accent
                        ctx.beginPath()
                        ctx.moveTo(railRight - 0.5, 0)
                        ctx.lineTo(railRight - 0.5, top)
                        if (p > 0.001) {
                            ctx.lineTo(right - 0.5, top)
                            ctx.lineTo(right - 0.5, bottom)
                            ctx.lineTo(railRight - 0.5, bottom)
                        }
                        ctx.lineTo(railRight - 0.5, h)
                        ctx.stroke()
                        return
                    }
                    // Preserve a capsule-like leading edge while collapsing;
                    // only reduce the radius when the remaining width itself
                    // becomes narrower than the full corner diameter.
                    const radius = root.minimum ? Math.min(6, extensionWidth / 2)
                        : Math.min(22, extensionWidth / 2)
                    const shoulder = root.minimum ? Math.min(6, extensionWidth / 2)
                        : Math.min(18, extensionWidth / 2)
                    const lowerShoulder = Math.min(shoulder, Math.max(0, h - 9 - bottom))

                    ctx.reset()
                    ctx.clearRect(0, 0, width, height)
                    ctx.beginPath()
                    ctx.moveTo(0, 0)
                    ctx.lineTo(root.minimum ? 31 : 46, 0)
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
                    ctx.quadraticCurveTo(railRight, h, root.minimum ? 31 : 46, h)
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
                        ctx.lineTo(root.minimum ? 31 : 46, 0)
                        ctx.quadraticCurveTo(railRight, 0, railRight, 9)
                        ctx.lineTo(railRight, h - 9)
                        ctx.quadraticCurveTo(railRight, h, root.minimum ? 31 : 46, h)
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
                visible: !root.minimum || root.panelPosition === "left"
                z: 2
                x: root.minimum ? 0 : -9
                // The layer window grows to host popouts, but the visible rail
                // must always retain its compact width.
                width: root.minimum ? 38 : 64
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
                    anchors.topMargin: root.minimum ? 5 : 18
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 2

                    Repeater {
                        model: root.isNiri ? root.niriWorkspaces : Hyprland.workspaces

                        delegate: Item {
                            required property var modelData
                            width: root.minimum ? 38 : 44
                            height: root.minimum ? 27 : 34

                            Rectangle {
                                anchors.centerIn: parent
                                width: root.minimum ? 30 : 32
                                height: root.minimum ? 23 : 28
                                radius: root.minimum ? 4 : 6
                                color: (root.isNiri ? modelData.is_focused : modelData.focused) && root.minimum ? theme.selected
                                    : workspaceMouse.containsMouse ? theme.hover : "transparent"
                            }

                            Text {
                                anchors.centerIn: parent
                                text: root.isNiri ? (modelData.name || modelData.idx) : modelData.name
                                color: (root.isNiri ? modelData.is_focused : modelData.focused) && root.minimum ? theme.accentForeground
                                    : (root.isNiri ? modelData.is_focused : modelData.focused) ? root.foreground : root.muted
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: root.minimum ? 9 : 11
                                font.weight: modelData.focused ? Font.Bold : Font.Medium
                            }

                            MouseArea {
                                id: workspaceMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (root.isNiri)
                                        Quickshell.execDetached(["niri", "msg", "action", "focus-workspace", String(modelData.idx)])
                                    else
                                        modelData.activate()
                                }
                            }
                        }
                    }
                }

                Column {
                    anchors.centerIn: parent
                    spacing: root.minimum ? 6 : 12

                    Text {
                        width: root.minimum ? 38 : 44
                        horizontalAlignment: Text.AlignHCenter
                        text: Qt.formatDateTime(clock.date, "HH\nmm")
                        color: root.foreground
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: root.minimum ? 12 : 17
                        font.weight: Font.Bold
                        lineHeight: 1.15
                    }

                    Text {
                        width: root.minimum ? 38 : 44
                        horizontalAlignment: Text.AlignHCenter
                        text: root.weekdayShort(clock.date)
                        color: root.accent
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: root.minimum ? 9 : 11
                        font.weight: Font.Bold
                    }

                    Text {
                        width: root.minimum ? 38 : 44
                        horizontalAlignment: Text.AlignHCenter
                        text: Qt.formatDateTime(clock.date, "dd\nMM")
                        color: root.muted
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: root.minimum ? 9 : 10
                        font.weight: Font.DemiBold
                        lineHeight: 1.25
                    }
                }

                Column {
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: root.minimum ? 4 : 14
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
                        text: "󰚩"
                        tooltip: "Лимиты AI"
                        active: root.connectivityMenuOpen && root.connectivityPage === "ai"
                        onClicked: {
                            if (root.connectivityMenuOpen && root.connectivityPage === "ai") {
                                connectivityPanel.close()
                                return
                            }
                            root.connectivityPage = "ai"
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
                railWidth: root.minimum ? 38 : 55
                fromTop: root.minimum && root.panelPosition === "top"
                standaloneSurface: root.minimum && root.panelPosition === "top"
                compactMode: root.minimum
                keyboardLayout: root.keyboardLayout
                isNiri: root.isNiri
                visible: panel.connectivityActive
                onCloseRequested: root.connectivityMenuOpen = false
            }
        }
    }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: topPanel
            required property var modelData
            screen: modelData
            visible: root.minimum && root.panelPosition === "top"
            anchors.top: true
            anchors.left: true
            anchors.right: true
            implicitHeight: 38
            exclusiveZone: 38
            color: theme.surface
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

            Rectangle {
                anchors.fill: parent
                color: theme.surface
                border.width: 1
                border.color: theme.accent
            }

            Row {
                anchors.left: parent.left
                anchors.leftMargin: 7
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2
                Repeater {
                    model: root.isNiri ? root.niriWorkspaces : Hyprland.workspaces
                    delegate: Rectangle {
                        id: topWorkspace
                        required property var modelData
                        width: 28; height: 25; radius: 4
                        color: (root.isNiri ? modelData.is_focused : modelData.focused) ? theme.selected
                            : topWorkspaceMouse.containsMouse ? theme.hover : "transparent"
                        Text {
                            anchors.centerIn: parent
                            text: root.isNiri ? (topWorkspace.modelData.name || topWorkspace.modelData.idx) : topWorkspace.modelData.name
                            color: (root.isNiri ? topWorkspace.modelData.is_focused : topWorkspace.modelData.focused) ? theme.accentForeground : root.muted
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 9
                            font.weight: Font.Bold
                        }
                        MouseArea {
                            id: topWorkspaceMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (root.isNiri)
                                    Quickshell.execDetached(["niri", "msg", "action", "focus-workspace", String(topWorkspace.modelData.idx)])
                                else
                                    topWorkspace.modelData.activate()
                            }
                        }
                    }
                }
            }

            Text {
                anchors.centerIn: parent
                text: root.weekdayShort(clock.date) + "  " + Qt.formatDateTime(clock.date, "dd.MM  HH:mm")
                color: root.foreground
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: 10
                font.weight: Font.DemiBold
            }

            Row {
                anchors.right: parent.right
                anchors.rightMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                spacing: 12
                Text {
                    id: topLayoutButton
                    text: {
                        const map = {"English (US)":"EN", "English":"EN", "Russian":"RU", "Ukrainian":"UA", "German":"DE"}
                        return map[root.keyboardLayout] || root.keyboardLayout.slice(0, 2).toUpperCase()
                    }
                    color: root.muted
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 9
                    MouseArea {
                        anchors.fill: parent; anchors.margins: -7
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            root.connectivityPage = "keyboard"
                            root.connectivityMenuScreen = topPanel.screen
                            root.connectivityMenuOpen = true
                        }
                    }
                }
                Text {
                    text: "󰚩"
                    color: root.foreground
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 11
                    MouseArea {
                        anchors.fill: parent
                        anchors.margins: -7
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            const wasOpen = root.connectivityMenuOpen && root.connectivityPage === "ai"
                            root.connectivityPage = "ai"
                            root.connectivityMenuScreen = topPanel.screen
                            root.connectivityMenuOpen = !wasOpen
                        }
                    }
                }
                Text {
                    text: Networking.wifiEnabled ? "" : "󰤮"
                    color: Networking.wifiEnabled ? root.foreground : root.accent
                    font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 11
                    MouseArea {
                        anchors.fill: parent; anchors.margins: -7
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            root.connectivityPage = "wifi"
                            root.connectivityMenuScreen = topPanel.screen
                            root.connectivityMenuOpen = true
                        }
                    }
                }
                Text {
                    readonly property var adapter: Bluetooth.defaultAdapter
                    readonly property bool connected: Bluetooth.devices.values.some(device => device.connected)
                    text: connected ? "󰂱" : (adapter && adapter.enabled ? "󰂯" : "󰂲")
                    color: adapter && adapter.enabled ? root.foreground : root.accent
                    font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 11
                    MouseArea {
                        anchors.fill: parent; anchors.margins: -7
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            root.connectivityPage = "bluetooth"
                            root.connectivityMenuScreen = topPanel.screen
                            root.connectivityMenuOpen = true
                        }
                    }
                }
                Text {
                    readonly property var sink: Pipewire.defaultAudioSink
                    readonly property var audio: sink ? sink.audio : null
                    text: !audio || audio.muted ? "󰝟" : (audio.volume < 0.5 ? "" : "")
                    color: audio && audio.muted ? root.accent : root.foreground
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 11
                    MouseArea {
                        anchors.fill: parent; anchors.margins: -7
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            root.connectivityPage = "audio"
                            root.connectivityMenuScreen = topPanel.screen
                            root.connectivityMenuOpen = true
                        }
                    }
                }
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
            minimal: root.minimum
            placement: root.notificationCenterPosition
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
            minimal: root.minimum
            placement: root.notificationPosition
            onDismissRequested: notification => root.dismissNotification(notification)
        }
    }
}
