import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Networking
import Quickshell.Services.Notifications
import Quickshell.Services.Pipewire
import Quickshell.Wayland

ShellRoot {
    id: root

    // Compact left rail and its native power overlay.

    property color foreground: "#ccc2b7"
    property color muted: "#746961"
    property color accent: "#a67c49"
    property string keyboardLayout: "English (US)"
    property bool vpnConnected: false
    property string vpnTooltip: "Проверка состояния V2RayA…"
    property bool powerMenuOpen: false
    property var powerMenuScreen: null
    property var notificationEntries: []
    property var activeToast: null
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
        if (activeToast && activeToast.notification.id === id) {
            activeToast = null
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
            root.notificationCenterScreen = root.focusedScreen()
            root.notificationCenterOpen = !root.notificationCenterOpen
            if (root.notificationCenterOpen) {
                root.activeToast = null
                toastTimer.stop()
            }
        }

        function close(): void {
            root.notificationCenterOpen = false
        }

        function clear(): void {
            root.clearNotifications()
        }
    }

    Timer {
        id: toastTimer
        interval: 5000
        onTriggered: root.activeToast = null
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
            implicitWidth: 55
            implicitHeight: 900
            anchors.left: true
            exclusiveZone: 55

            Rectangle {
                id: rail
                x: -9
                width: parent.width + 9
                height: parent.height
                radius: 9
                color: "#d923211f"
                border.width: 1
                border.color: "#8f685f57"

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
                                color: workspaceMouse.containsMouse ? "#403934" : "transparent"
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
                        onClicked: root.run("${XDG_CONFIG_HOME:-$HOME/.config}/quickshell/scripts/switch-keyboard-layout.sh")
                    }

                    BarButton {
                        text: Networking.wifiEnabled ? "" : "󰤮"
                        color: Networking.wifiEnabled ? root.foreground : root.accent
                        tooltip: Networking.wifiEnabled ? "Wi-Fi включён" : "Wi-Fi выключен"
                        onClicked: root.run("${XDG_CONFIG_HOME:-$HOME/.config}/quickshell/scripts/wifi-menu.sh")
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
                        onClicked: if (audio) audio.muted = !audio.muted
                        onWheelUp: if (audio) audio.volume = Math.min(1.0, audio.volume + 0.05)
                        onWheelDown: if (audio) audio.volume = Math.max(0.0, audio.volume - 0.05)
                    }

                    BarButton {
                        text: ""
                        color: root.accent
                        fontPixelSize: 14
                        tooltip: "Питание"
                        onClicked: {
                            root.powerMenuScreen = panel.screen
                            root.powerMenuOpen = true
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
            onLockRequested: root.run("hyprlock")
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
            visible: root.activeToast !== null && root.toastScreen === modelData
            entry: root.activeToast
            onDismissRequested: notification => root.dismissNotification(notification)
        }
    }
}
