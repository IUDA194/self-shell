import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Services.Mpris
import Quickshell.Services.Pipewire
import Quickshell.Wayland
import Quickshell.Widgets

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
    readonly property color critical: theme.critical
    readonly property color green: theme.success

    property real cpuUsage: 0
    property real memoryUsage: 0
    property real diskUsage: 0
    property string uptimeText: "—"
    property real networkDown: 0
    property real networkUp: 0
    property real previousNetworkRx: -1
    property real previousNetworkTx: -1
    property real previousNetworkTime: 0
    property var networkDownHistory: []
    property var networkUpHistory: []
    property string networkInterfaces: "подключение определяется"
    property var calendarEvents: []
    property string calendarStatus: "Загрузка Google Calendar"
    property string activeWindowAddress: ""
    property string dockSelectedAddress: ""
    property var dockSelectedWindow: null
    property bool dockCycleActive: false
    signal dockSwitcherRequested(string address)
    property var player: Mpris.players.values.length > 0 ? Mpris.players.values[0] : null
    readonly property var applicationStreams: Pipewire.nodes.values.filter(node =>
        node && node.type === PwNodeType.AudioOutStream && node.audio !== null)

    function windowsForScreen(screen) {
        return Hyprland.toplevels.values.filter(toplevel =>
            toplevel && toplevel.wayland
                && (!toplevel.monitor || toplevel.monitor.name === screen.name))
    }

    function activateWindow(toplevel) {
        Quickshell.execDetached([
            Quickshell.env("HOME") + "/.config/hypr/dashboard-focus-window.sh",
            toplevel.address
        ])
    }

    function windowAppId(toplevel) {
        if (toplevel.wayland && toplevel.wayland.appId.length > 0)
            return toplevel.wayland.appId
        const ipcClass = toplevel.lastIpcObject["class"]
        return ipcClass || "application-x-executable"
    }

    function windowName(toplevel) {
        const appId = windowAppId(toplevel)
        const parts = appId.split(".")
        return parts[parts.length - 1].replace(/[-_]/g, " ")
    }

    function windowIcon(toplevel) {
        const appId = windowAppId(toplevel)
        const aliases = {
            "org.mozilla.firefox": "firefox",
            "org.gnome.Nautilus": "org.gnome.Nautilus",
            "org.telegram.desktop": "org.telegram.desktop",
            "com.valvesoftware.Steam": "steam"
        }
        return aliases[appId] || appId
    }

    function normalizedAddress(address) {
        const value = String(address || "")
        return value.startsWith("0x") ? value.slice(2) : value
    }

    function cycleDockWindow() {
        const windows = Hyprland.toplevels.values.filter(toplevel =>
            toplevel && toplevel.wayland)
        if (windows.length === 0)
            return false

        const currentAddress = dockCycleActive
            ? dockSelectedAddress : activeWindowAddress
        let currentIndex = -1
        for (let i = 0; i < windows.length; ++i) {
            if (normalizedAddress(windows[i].address) === currentAddress) {
                currentIndex = i
                break
            }
        }

        const nextWindow = windows[(currentIndex + 1) % windows.length]
        dockSelectedWindow = nextWindow
        dockSelectedAddress = normalizedAddress(nextWindow.address)
        dockCycleActive = true
        dockSwitcherRequested(dockSelectedAddress)
        dockCommitTimer.restart()
        return true
    }

    Timer {
        id: dockCommitTimer
        interval: 550
        onTriggered: {
            if (root.dockSelectedWindow)
                root.activateWindow(root.dockSelectedWindow)
            root.dockCycleActive = false
        }
    }

    Process {
        id: activeWindowProcess
        command: ["bash", "-lc", "hyprctl activewindow -j | jq -r '.address // empty'"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: root.activeWindowAddress = root.normalizedAddress(text.trim())
        }
    }

    Connections {
        target: Hyprland

        function onRawEvent(event) {
            if (event.name === "activewindowv2")
                root.activeWindowAddress = root.normalizedAddress(event.data.trim())
        }
    }

    IpcHandler {
        target: "dock"

        function activeAddress(): string {
            return root.activeWindowAddress
        }

        function cycle(): bool {
            return root.cycleDockWindow()
        }
    }

    function formatRate(bytesPerSecond) {
        if (bytesPerSecond >= 1073741824)
            return (bytesPerSecond / 1073741824).toFixed(1) + " ГБ/с"
        if (bytesPerSecond >= 1048576)
            return (bytesPerSecond / 1048576).toFixed(1) + " МБ/с"
        if (bytesPerSecond >= 1024)
            return (bytesPerSecond / 1024).toFixed(0) + " КБ/с"
        return Math.round(bytesPerSecond) + " Б/с"
    }

    function networkGraphMaximum() {
        let maximum = 65536
        for (let i = 0; i < networkDownHistory.length; ++i)
            maximum = Math.max(maximum, networkDownHistory[i])
        for (let i = 0; i < networkUpHistory.length; ++i)
            maximum = Math.max(maximum, networkUpHistory[i])
        return Math.pow(2, Math.ceil(Math.log(maximum) / Math.log(2)))
    }

    function dateIso(date) {
        const month = String(date.getMonth() + 1).padStart(2, "0")
        const day = String(date.getDate()).padStart(2, "0")
        return date.getFullYear() + "-" + month + "-" + day
    }

    function hasCalendarEvent(year, month, day) {
        const iso = year + "-" + String(month + 1).padStart(2, "0")
            + "-" + String(day).padStart(2, "0")
        return calendarEvents.some(event => event.date === iso)
    }

    function upcomingCalendarEvents(limit) {
        const today = dateIso(clock.date)
        return calendarEvents.filter(event => event.date >= today).slice(0, limit)
    }

    function todayCalendarEvents(limit) {
        const today = dateIso(clock.date)
        return calendarEvents.filter(event => event.date === today).slice(0, limit)
    }

    function formatCalendarEvent(event) {
        if (!event)
            return ""
        const today = dateIso(clock.date)
        const prefix = event.date === today ? (event.time || "весь день")
            : event.date.slice(8, 10) + "." + event.date.slice(5, 7)
                + (event.time ? " " + event.time : "")
        return prefix + "  " + event.title
    }

    PwObjectTracker {
        objects: root.applicationStreams
    }

    SystemClock {
        id: clock
        precision: SystemClock.Seconds
    }

    Process {
        id: statsProcess
        command: ["bash", "-lc", "LC_ALL=C top -bn1 | awk '/Cpu\\(s\\)/ {printf \"%.0f\", 100-$8}'; printf '|'; free | awk '/Mem:/ {printf \"%.0f\", $3/$2*100}'; printf '|'; df -P / | awk 'NR==2 {gsub(/%/,\"\",$5); printf \"%s\",$5}'; printf '|'; uptime -p | sed 's/^up //' "]
        running: true

        stdout: StdioCollector {
            onStreamFinished: {
                const parts = text.trim().split("|")
                if (parts.length >= 4) {
                    root.cpuUsage = Number(parts[0])
                    root.memoryUsage = Number(parts[1])
                    root.diskUsage = Number(parts[2])
                    root.uptimeText = parts[3]
                }
            }
        }
    }

    Timer {
        interval: 3000
        running: true
        repeat: true
        onTriggered: statsProcess.running = true
    }

    Process {
        id: networkProcess
        command: ["bash", "-lc", "awk 'NR > 2 && $1 !~ /^lo:/ {name=$1; gsub(/:/, \"\", name); rx+=$2; tx+=$10; interfaces=(interfaces ? interfaces \", \" : \"\") name} END {printf \"%.0f|%.0f|%s\", rx, tx, interfaces}' /proc/net/dev"]
        running: true

        stdout: StdioCollector {
            onStreamFinished: {
                const parts = text.trim().split("|")
                if (parts.length >= 2) {
                    const rx = Number(parts[0])
                    const tx = Number(parts[1])
                    const now = Date.now()
                    if (root.previousNetworkRx >= 0 && now > root.previousNetworkTime) {
                        const seconds = (now - root.previousNetworkTime) / 1000
                        root.networkDown = Math.max(0, (rx - root.previousNetworkRx) / seconds)
                        root.networkUp = Math.max(0, (tx - root.previousNetworkTx) / seconds)
                        root.networkDownHistory = root.networkDownHistory.concat([root.networkDown]).slice(-60)
                        root.networkUpHistory = root.networkUpHistory.concat([root.networkUp]).slice(-60)
                    }
                    root.previousNetworkRx = rx
                    root.previousNetworkTx = tx
                    root.previousNetworkTime = now
                    root.networkInterfaces = parts[2] || "нет активных интерфейсов"
                }
            }
        }
    }

    Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: {
            if (!networkProcess.running)
                networkProcess.running = true
        }
    }

    Process {
        id: calendarProcess
        command: [Quickshell.env("HOME") + "/.config/hypr/dashboard/google-calendar-events.sh"]
        running: true

        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.trim().split("\n")
                if (lines[0] === "AUTH_REQUIRED") {
                    root.calendarStatus = "Нужен вход в Google"
                    root.calendarEvents = []
                    return
                }
                if (lines[0] !== "OK") {
                    root.calendarStatus = "Ошибка синхронизации"
                    return
                }

                const events = lines.length > 1 ? JSON.parse(lines.slice(1).join("\n")) : []
                root.calendarEvents = events
                root.calendarStatus = events.length > 0 ? "Google Calendar · только чтение"
                    : "Нет событий в этом месяце"
            }
        }
    }

    Timer {
        interval: 300000
        running: true
        repeat: true
        onTriggered: {
            if (!calendarProcess.running)
                calendarProcess.running = true
        }
    }

    Component {
        id: networkGraphComponent

        Canvas {
            id: networkGraph

            antialiasing: true

            function drawSeries(context, values, maximum, color, fill) {
                if (values.length < 2)
                    return

                const step = width / 59
                const startX = width - (values.length - 1) * step
                context.beginPath()
                context.moveTo(startX, height - Math.min(values[0] / maximum, 1) * height)
                for (let i = 1; i < values.length; ++i)
                    context.lineTo(startX + i * step,
                        height - Math.min(values[i] / maximum, 1) * height)

                if (fill) {
                    context.lineTo(width, height)
                    context.lineTo(startX, height)
                    context.closePath()
                    context.fillStyle = theme.accentSubtle
                    context.fill()

                    context.beginPath()
                    context.moveTo(startX, height - Math.min(values[0] / maximum, 1) * height)
                    for (let j = 1; j < values.length; ++j)
                        context.lineTo(startX + j * step,
                            height - Math.min(values[j] / maximum, 1) * height)
                }

                context.lineWidth = 2
                context.strokeStyle = color
                context.stroke()
            }

            onPaint: {
                const context = getContext("2d")
                context.clearRect(0, 0, width, height)
                context.lineWidth = 1
                context.strokeStyle = theme.faint
                for (let i = 1; i < 4; ++i) {
                    context.beginPath()
                    context.moveTo(0, height * i / 4)
                    context.lineTo(width, height * i / 4)
                    context.stroke()
                }
                const maximum = root.networkGraphMaximum()
                drawSeries(context, root.networkDownHistory, maximum, root.accent, true)
                drawSeries(context, root.networkUpHistory, maximum, root.green, false)
            }

            onWidthChanged: requestPaint()
            onHeightChanged: requestPaint()

            Connections {
                target: root
                function onNetworkDownHistoryChanged() { networkGraph.requestPaint() }
                function onNetworkUpHistoryChanged() { networkGraph.requestPaint() }
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
                property bool volumeAdjusting: false
                readonly property bool expanded: revealStage === 2
                property int activeTab: 0
                readonly property real panelTargetWidth: Math.min(
                    [900, 820, 760, 580][activeTab], screen.width - 48)
                readonly property real panelTargetHeight: Math.min(
                    [650, 315 + Math.min(Math.max(root.applicationStreams.length, 1), 3) * 72, 520, 390][activeTab],
                    screen.height - 64)

                screen: modelData
                anchors.top: true
                implicitWidth: Math.min(1000, screen.width - 48)
                implicitHeight: Math.min(650, screen.height - 64)
                color: "transparent"
                exclusionMode: ExclusionMode.Ignore
                mask: Region { item: hoverRegion }
                WlrLayershell.layer: WlrLayer.Overlay
                WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

                Item {
                    id: hoverRegion
                    anchors.top: parent.top
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: window.revealStage === 2 ? window.panelTargetWidth
                        : window.revealStage === 1 ? 440 : 160
                    height: window.revealStage === 2 ? window.panelTargetHeight
                        : window.revealStage === 1 ? 26 : 8

                    Behavior on width {
                        NumberAnimation {
                            duration: 500
                            easing.type: Easing.BezierSpline
                            easing.bezierCurve: [0.38, 1.21, 0.22, 1, 1, 1]
                        }
                    }

                    Behavior on height {
                        NumberAnimation {
                            duration: 500
                            easing.type: Easing.BezierSpline
                            easing.bezierCurve: [0.38, 1.21, 0.22, 1, 1, 1]
                        }
                    }
                }

                Timer {
                    id: openTimer
                    interval: 450
                    onTriggered: window.revealStage = 2
                }

                Timer {
                    id: closeTimer
                    interval: 420
                    onTriggered: {
                        if (!window.volumeAdjusting)
                            window.revealStage = 0
                    }
                }

                MouseArea {
                    id: dashboardHoverArea
                    anchors.fill: hoverRegion
                    hoverEnabled: true
                    acceptedButtons: Qt.NoButton
                    onEntered: {
                        closeTimer.stop()
                        if (window.revealStage === 0) {
                            window.revealStage = 1
                        }
                        if (window.revealStage === 1)
                            openTimer.restart()
                    }
                    onExited: {
                        openTimer.stop()
                        if (window.volumeAdjusting)
                            return
                        closeTimer.interval = window.revealStage === 1 ? 180 : 420
                        closeTimer.restart()
                    }
                }

                Rectangle {
                    id: stageIndicator

                    anchors.top: parent.top
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 150
                    height: 5
                    radius: 3
                    color: root.accent
                    border.width: 0
                    opacity: window.revealStage === 1 ? 1 : 0
                    clip: true

                    Behavior on opacity { NumberAnimation { duration: 140 } }
                }

                Item {
                    id: dashboardReveal

                    anchors.top: parent.top
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: window.revealStage === 2 ? window.panelTargetWidth : 430
                    height: window.revealStage === 2 ? window.panelTargetHeight : 0
                    clip: true

                    Behavior on width {
                        NumberAnimation {
                            duration: 500
                            easing.type: Easing.BezierSpline
                            easing.bezierCurve: [0.38, 1.21, 0.22, 1, 1, 1]
                        }
                    }

                    Behavior on height {
                        NumberAnimation {
                            duration: 500
                            easing.type: Easing.BezierSpline
                            easing.bezierCurve: [0.38, 1.21, 0.22, 1, 1, 1]
                        }
                    }
                }

                Rectangle {
                    id: dashboardPanel

                    parent: dashboardReveal
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: window.panelTargetWidth
                    height: window.panelTargetHeight
                    radius: 26
                    topLeftRadius: 0
                    topRightRadius: 0
                    bottomLeftRadius: 26
                    bottomRightRadius: 26
                    color: root.background
                    border.width: 1
                    border.color: theme.outline
                    clip: true
                    opacity: 1
                    scale: 1
                    y: 0
                    layer.enabled: true
                    layer.smooth: true

                    Rectangle {
                        anchors.top: parent.top
                        width: parent.width
                        height: 2
                        color: parent.color
                        z: 50
                    }

                    Behavior on width {
                        NumberAnimation {
                            duration: 500
                            easing.type: Easing.BezierSpline
                            easing.bezierCurve: [0.38, 1.21, 0.22, 1, 1, 1]
                        }
                    }

                    Behavior on height {
                        NumberAnimation {
                            duration: 500
                            easing.type: Easing.BezierSpline
                            easing.bezierCurve: [0.38, 1.21, 0.22, 1, 1, 1]
                        }
                    }

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 24
                        spacing: 18
                        opacity: 1

                        Item {
                            id: tabBar
                            readonly property real tabGap: 7
                            readonly property real tabWidth: (width - tabGap * 3) / 4
                            Layout.fillWidth: true
                            Layout.preferredHeight: 55
                            Layout.maximumHeight: 55

                            Rectangle {
                                x: window.activeTab * (tabBar.tabWidth + tabBar.tabGap)
                                width: tabBar.tabWidth
                                height: tabBar.height
                                radius: 14
                                color: root.surfaceAlt

                                Behavior on x {
                                    NumberAnimation {
                                        duration: 180
                                        easing.type: Easing.OutCubic
                                    }
                                }
                            }

                            RowLayout {
                                anchors.fill: parent
                                spacing: tabBar.tabGap

                                Repeater {
                                    model: [
                                        { icon: "󰕮", title: "Обзор" },
                                        { icon: "󰝚", title: "Эквалайзер" },
                                        { icon: "󰄧", title: "Система" },
                                        { icon: "󰛳", title: "Сеть" }
                                    ]

                                    delegate: Item {
                                        required property int index
                                        required property var modelData

                                        Layout.fillWidth: true
                                        Layout.fillHeight: true

                                        Row {
                                            anchors.centerIn: parent
                                            spacing: 9

                                            Text {
                                                text: modelData.icon
                                                color: window.activeTab === index ? root.accent : root.muted
                                                font.family: "JetBrainsMono Nerd Font"
                                                font.pixelSize: 17

                                                Behavior on color { ColorAnimation { duration: 180 } }
                                            }

                                            Text {
                                                text: modelData.title
                                                color: window.activeTab === index ? root.foreground : root.muted
                                                font.family: "JetBrainsMono Nerd Font"
                                                font.pixelSize: 12
                                                font.weight: Font.DemiBold

                                                Behavior on color { ColorAnimation { duration: 180 } }
                                            }
                                        }

                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: window.activeTab = index
                                        }
                                    }
                                }
                            }
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 1
                            color: theme.outline
                        }

                        Item {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            clip: true

                            RowLayout {
                                id: overviewTab
                                readonly property int tabIndex: 0
                                readonly property bool tabActive: window.activeTab === tabIndex
                                anchors.fill: parent
                                spacing: 16
                                visible: tabActive || opacity > 0.001
                                enabled: tabActive
                                opacity: tabActive ? 1 : 0
                                Behavior on opacity {
                                    NumberAnimation { duration: 170; easing.type: Easing.OutCubic }
                                }

                                ColumnLayout {
                                    Layout.preferredWidth: 285
                                    Layout.minimumWidth: 285
                                    Layout.maximumWidth: 285
                                    Layout.fillHeight: true
                                    spacing: 16

                                    Rectangle {
                                        Layout.fillWidth: true
                                        Layout.fillHeight: true
                                        radius: 20
                                        color: root.surface
                                        border.width: 1
                                        border.color: theme.outline

                                        ColumnLayout {
                                            anchors.fill: parent
                                            anchors.margins: 22
                                            spacing: 10

                                        Text {
                                            text: Qt.formatDateTime(clock.date, "HH:mm")
                                            color: root.foreground
                                            font.family: "JetBrainsMono Nerd Font"
                                            font.pixelSize: 46
                                            font.weight: Font.DemiBold
                                        }

                                        Text {
                                            text: clock.date.toLocaleString(Qt.locale("ru_RU"), "dddd, d MMMM")
                                            color: root.accent
                                            font.family: "JetBrainsMono Nerd Font"
                                            font.pixelSize: 13
                                        }

                                        Item { Layout.preferredHeight: 5 }

                                        RowLayout {
                                            Layout.fillWidth: true

                                            Text {
                                                text: clock.date.toLocaleString(Qt.locale("ru_RU"), "MMMM yyyy")
                                                color: root.foreground
                                                font.family: "JetBrainsMono Nerd Font"
                                                font.pixelSize: 14
                                                font.weight: Font.DemiBold
                                            }

                                            Item { Layout.fillWidth: true }

                                            Text {
                                                text: "󰊭"
                                                color: root.calendarStatus.indexOf("Google Calendar") === 0
                                                    ? root.green : root.muted
                                                font.family: "JetBrainsMono Nerd Font"
                                                font.pixelSize: 17
                                            }
                                        }

                                        GridLayout {
                                            Layout.fillWidth: true
                                            columns: 7
                                            columnSpacing: 4
                                            rowSpacing: 6

                                            Repeater {
                                                model: ["Пн", "Вт", "Ср", "Чт", "Пт", "Сб", "Вс"]
                                                Text {
                                                    required property string modelData
                                                    Layout.fillWidth: true
                                                    text: modelData
                                                    horizontalAlignment: Text.AlignHCenter
                                                    color: root.muted
                                                    font.family: "JetBrainsMono Nerd Font"
                                                    font.pixelSize: 10
                                                }
                                            }

                                            Repeater {
                                                model: 42

                                                Rectangle {
                                                    required property int index
                                                    readonly property date firstDay: new Date(clock.date.getFullYear(), clock.date.getMonth(), 1)
                                                    readonly property int offset: (firstDay.getDay() + 6) % 7
                                                    readonly property int dayNumber: index - offset + 1
                                                    readonly property int daysInMonth: new Date(clock.date.getFullYear(), clock.date.getMonth() + 1, 0).getDate()
                                                    readonly property bool validDay: dayNumber > 0 && dayNumber <= daysInMonth
                                                    readonly property bool today: validDay && dayNumber === clock.date.getDate()
                                                    readonly property bool hasEvent: validDay && root.hasCalendarEvent(
                                                        clock.date.getFullYear(), clock.date.getMonth(), dayNumber)

                                                    Layout.fillWidth: true
                                                    implicitHeight: 27
                                                    radius: 9
                                                    color: today ? root.accent : "transparent"

                                                    Text {
                                                        anchors.centerIn: parent
                                                        anchors.verticalCenterOffset: parent.hasEvent ? -2 : 0
                                                        text: parent.validDay ? parent.dayNumber : ""
                                                        color: parent.today ? root.background : root.foreground
                                                        font.family: "JetBrainsMono Nerd Font"
                                                        font.pixelSize: 10
                                                        font.weight: parent.today ? Font.Bold : Font.Normal
                                                    }

                                                    Rectangle {
                                                        visible: parent.hasEvent
                                                        anchors.horizontalCenter: parent.horizontalCenter
                                                        anchors.bottom: parent.bottom
                                                        anchors.bottomMargin: 2
                                                        width: 3
                                                        height: 3
                                                        radius: 2
                                                        color: parent.today ? root.background : root.accent
                                                    }
                                                }
                                            }
                                        }

                                        Item { Layout.fillHeight: true }

                                        Text {
                                            text: "Работает: " + root.uptimeText
                                            color: root.muted
                                            font.family: "JetBrainsMono Nerd Font"
                                            font.pixelSize: 11
                                        }

                                        }
                                    }

                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    spacing: 16

                                    RowLayout {
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: 306
                                        Layout.maximumHeight: 306
                                        spacing: 16

                                        Rectangle {
                                            Layout.preferredWidth: 220
                                            Layout.minimumWidth: 220
                                            Layout.maximumWidth: 220
                                            Layout.fillHeight: true
                                            radius: 20
                                            color: root.surface
                                            border.width: 1
                                            border.color: theme.outline
                                            clip: true

                                            ColumnLayout {
                                                anchors.fill: parent
                                                anchors.margins: 18
                                                spacing: 10

                                                RowLayout {
                                                    Layout.fillWidth: true

                                                    Text {
                                                        text: "󰃭  Сегодня"
                                                        color: root.foreground
                                                        font.family: "JetBrainsMono Nerd Font"
                                                        font.pixelSize: 13
                                                        font.weight: Font.DemiBold
                                                    }

                                                    Item { Layout.fillWidth: true }

                                                    Text {
                                                        text: "G"
                                                        color: root.calendarStatus.indexOf("Google Calendar") === 0
                                                            ? root.green : root.muted
                                                        font.family: "JetBrainsMono Nerd Font"
                                                        font.pixelSize: 12
                                                        font.weight: Font.Bold
                                                    }
                                                }

                                                Rectangle {
                                                    Layout.fillWidth: true
                                                    Layout.preferredHeight: 1
                                                    color: theme.faint
                                                }

                                                Text {
                                                    visible: root.todayCalendarEvents(6).length === 0
                                                    Layout.fillWidth: true
                                                    text: root.calendarStatus.indexOf("Google Calendar") === 0
                                                        ? "На сегодня событий нет" : root.calendarStatus
                                                    color: root.muted
                                                    wrapMode: Text.WordWrap
                                                    font.family: "JetBrainsMono Nerd Font"
                                                    font.pixelSize: 10
                                                }

                                                Repeater {
                                                    model: root.todayCalendarEvents(6)

                                                    ColumnLayout {
                                                        required property var modelData
                                                        Layout.fillWidth: true
                                                        spacing: 2

                                                        Text {
                                                            Layout.fillWidth: true
                                                            text: modelData.time || "Весь день"
                                                            color: root.accent
                                                            font.family: "JetBrainsMono Nerd Font"
                                                            font.pixelSize: 9
                                                        }

                                                        Text {
                                                            Layout.fillWidth: true
                                                            text: modelData.title
                                                            color: root.foreground
                                                            elide: Text.ElideRight
                                                            font.family: "JetBrainsMono Nerd Font"
                                                            font.pixelSize: 10
                                                        }
                                                    }
                                                }

                                                Item { Layout.fillHeight: true }
                                            }
                                        }

                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            Layout.fillHeight: true
                                            spacing: 16

                                            Rectangle {
                                                Layout.fillWidth: true
                                                Layout.preferredHeight: 155
                                                Layout.maximumHeight: 155
                                                radius: 20
                                                color: root.surface
                                                border.width: 1
                                                border.color: theme.outline

                                                ColumnLayout {
                                                    anchors.fill: parent
                                                    anchors.margins: 18
                                                    spacing: 6

                                                    RowLayout {
                                                        Layout.fillWidth: true

                                                        Text {
                                                            text: "󰇚 " + root.formatRate(root.networkDown)
                                                            color: root.foreground
                                                            font.family: "JetBrainsMono Nerd Font"
                                                            font.pixelSize: 11
                                                            font.weight: Font.DemiBold
                                                        }

                                                        Item { Layout.fillWidth: true }

                                                        Text {
                                                            text: "󰕒 " + root.formatRate(root.networkUp)
                                                            color: root.green
                                                            font.family: "JetBrainsMono Nerd Font"
                                                            font.pixelSize: 11
                                                        }
                                                    }

                                                    Loader {
                                                        Layout.fillWidth: true
                                                        Layout.fillHeight: true
                                                        sourceComponent: networkGraphComponent
                                                    }

                                                    Text {
                                                        Layout.fillWidth: true
                                                        text: root.networkInterfaces
                                                        color: root.accent
                                                        elide: Text.ElideRight
                                                        font.family: "JetBrainsMono Nerd Font"
                                                        font.pixelSize: 9
                                                    }
                                                }
                                            }

                                            RowLayout {
                                                Layout.fillWidth: true
                                                Layout.fillHeight: true
                                                spacing: 12

                                                Repeater {
                                                    model: [
                                                        { title: "CPU", value: root.cpuUsage, icon: "󰍛" },
                                                        { title: "RAM", value: root.memoryUsage, icon: "󰘚" },
                                                        { title: "ДИСК", value: root.diskUsage, icon: "󰋊" }
                                                    ]

                                                    delegate: Rectangle {
                                                        required property var modelData
                                                        Layout.fillWidth: true
                                                        Layout.fillHeight: true
                                                        radius: 18
                                                        color: root.surface
                                                        border.width: 1
                                                        border.color: theme.outline

                                                        Column {
                                                            anchors.centerIn: parent
                                                            spacing: 6

                                                            Text {
                                                                anchors.horizontalCenter: parent.horizontalCenter
                                                                text: modelData.icon
                                                                color: modelData.value > 85 ? root.critical : root.accent
                                                                font.family: "JetBrainsMono Nerd Font"
                                                                font.pixelSize: 20
                                                            }

                                                            Text {
                                                                anchors.horizontalCenter: parent.horizontalCenter
                                                                text: Math.round(modelData.value) + "%"
                                                                color: root.foreground
                                                                font.family: "JetBrainsMono Nerd Font"
                                                                font.pixelSize: 16
                                                                font.weight: Font.DemiBold
                                                            }

                                                            Text {
                                                                anchors.horizontalCenter: parent.horizontalCenter
                                                                text: modelData.title
                                                                color: root.muted
                                                                font.family: "JetBrainsMono Nerd Font"
                                                                font.pixelSize: 8
                                                            }
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }

                                    Rectangle {
                                        Layout.fillWidth: true
                                        Layout.fillHeight: true
                                        radius: 20
                                        color: root.surface
                                        border.width: 1
                                        border.color: theme.outline

                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.margins: 16
                                            spacing: 16

                                            Rectangle {
                                                Layout.preferredWidth: 102
                                                Layout.fillHeight: true
                                                radius: 15
                                                color: root.surfaceAlt
                                                clip: true

                                                Image {
                                                    anchors.fill: parent
                                                    source: root.player ? root.player.trackArtUrl : ""
                                                    fillMode: Image.PreserveAspectFit
                                                    asynchronous: true
                                                    visible: status === Image.Ready
                                                }

                                                Text {
                                                    anchors.centerIn: parent
                                                    text: "󰝚"
                                                    color: root.accent
                                                    font.family: "JetBrainsMono Nerd Font"
                                                    font.pixelSize: 32
                                                    z: -1
                                                }
                                            }

                                            ColumnLayout {
                                                Layout.fillWidth: true

                                                Text {
                                                    Layout.fillWidth: true
                                                    text: root.player && root.player.trackTitle ? root.player.trackTitle : "Ничего не играет"
                                                    color: root.foreground
                                                    elide: Text.ElideRight
                                                    font.family: "JetBrainsMono Nerd Font"
                                                    font.pixelSize: 14
                                                    font.weight: Font.DemiBold
                                                }

                                                Text {
                                                    Layout.fillWidth: true
                                                    text: root.player && root.player.trackArtist ? root.player.trackArtist : "Откройте музыкальный плеер"
                                                    color: root.muted
                                                    elide: Text.ElideRight
                                                    font.family: "JetBrainsMono Nerd Font"
                                                    font.pixelSize: 11
                                                }

                                                RowLayout {
                                                    spacing: 10

                                                    Repeater {
                                                        model: ["󰒮", root.player && root.player.isPlaying ? "󰏤" : "󰐊", "󰒭"]

                                                        Rectangle {
                                                            required property int index
                                                            required property string modelData
                                                            width: index === 1 ? 48 : 38
                                                            height: index === 1 ? 38 : 34
                                                            radius: 12
                                                            color: index === 1 ? root.accent : root.surfaceAlt

                                                            Text {
                                                                anchors.centerIn: parent
                                                                text: modelData
                                                                color: index === 1 ? root.background : root.foreground
                                                                font.family: "JetBrainsMono Nerd Font"
                                                                font.pixelSize: 16
                                                            }

                                                            MouseArea {
                                                                anchors.fill: parent
                                                                enabled: root.player !== null
                                                                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                                                                onClicked: {
                                                                    if (index === 0) root.player.previous()
                                                                    else if (index === 1) root.player.togglePlaying()
                                                                    else root.player.next()
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

                            ColumnLayout {
                                id: equalizerTab
                                readonly property int tabIndex: 1
                                readonly property bool tabActive: window.activeTab === tabIndex
                                anchors.fill: parent
                                spacing: 18
                                visible: tabActive || opacity > 0.001
                                enabled: tabActive
                                opacity: tabActive ? 1 : 0
                                Behavior on opacity {
                                    NumberAnimation { duration: 170; easing.type: Easing.OutCubic }
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 10

                                    Text {
                                        text: "Микшер приложений"
                                        color: root.foreground
                                        font.family: "JetBrainsMono Nerd Font"
                                        font.pixelSize: 15
                                        font.weight: Font.DemiBold
                                    }

                                    Text {
                                        text: root.applicationStreams.length
                                        color: root.accent
                                        font.family: "JetBrainsMono Nerd Font"
                                        font.pixelSize: 12
                                    }

                                    Item { Layout.fillWidth: true }

                                    Text {
                                        text: "до 150%"
                                        color: root.muted
                                        font.family: "JetBrainsMono Nerd Font"
                                        font.pixelSize: 10
                                    }
                                }

                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    Layout.minimumHeight: 105
                                    radius: 20
                                    color: root.surface
                                    border.width: 1
                                    border.color: theme.outline
                                    clip: true

                                    Text {
                                        anchors.centerIn: parent
                                        visible: root.applicationStreams.length === 0
                                        text: "Запустите приложение со звуком"
                                        color: root.muted
                                        font.family: "JetBrainsMono Nerd Font"
                                        font.pixelSize: 12
                                    }

                                    ListView {
                                        id: applicationMixer
                                        anchors.fill: parent
                                        anchors.margins: 10
                                        visible: root.applicationStreams.length > 0
                                        model: root.applicationStreams
                                        spacing: 6
                                        clip: true
                                        boundsBehavior: Flickable.StopAtBounds
                                        flickDeceleration: 5000

                                        ScrollBar.vertical: ScrollBar {
                                            policy: applicationMixer.contentHeight > applicationMixer.height
                                                ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
                                        }

                                        delegate: Rectangle {
                                            id: streamRow

                                            required property var modelData
                                            readonly property var streamNode: modelData
                                            width: applicationMixer.width
                                            height: 66
                                            radius: 14
                                            color: root.background

                                            PwNodePeakMonitor {
                                                id: streamPeak
                                                node: streamRow.streamNode
                                                enabled: window.activeTab === 1 && window.expanded
                                            }

                                            RowLayout {
                                                anchors.fill: parent
                                                anchors.leftMargin: 14
                                                anchors.rightMargin: 12
                                                spacing: 12

                                                Item {
                                                    Layout.preferredWidth: 32
                                                    Layout.preferredHeight: 32

                                                    Row {
                                                        anchors.centerIn: parent
                                                        spacing: 2

                                                        Repeater {
                                                            model: [0.48, 0.72, 1.0, 0.62]

                                                            Rectangle {
                                                                required property real modelData
                                                                width: 4
                                                                height: 6 + 19 * Math.min(1, streamPeak.peak * 3.2 * modelData)
                                                                anchors.verticalCenter: parent.verticalCenter
                                                                radius: 2
                                                                color: streamRow.streamNode.audio && streamRow.streamNode.audio.muted
                                                                    ? root.muted : root.accent

                                                                Behavior on height {
                                                                    NumberAnimation { duration: 55 }
                                                                }
                                                            }
                                                        }
                                                    }
                                                }

                                                ColumnLayout {
                                                    Layout.preferredWidth: 160
                                                    Layout.maximumWidth: 160
                                                    spacing: 1

                                                    Text {
                                                        Layout.fillWidth: true
                                                        text: streamRow.streamNode.description
                                                            || streamRow.streamNode.nickname
                                                            || streamRow.streamNode.name
                                                            || "Приложение"
                                                        elide: Text.ElideRight
                                                        color: root.foreground
                                                        font.family: "JetBrainsMono Nerd Font"
                                                        font.pixelSize: 12
                                                        font.weight: Font.DemiBold
                                                    }

                                                    Text {
                                                        Layout.fillWidth: true
                                                        text: streamRow.streamNode.name || "Аудиопоток"
                                                        elide: Text.ElideRight
                                                        color: root.muted
                                                        font.family: "JetBrainsMono Nerd Font"
                                                        font.pixelSize: 9
                                                    }
                                                }

                                                Item {
                                                    id: streamVolume
                                                    Layout.fillWidth: true
                                                    Layout.preferredHeight: 36
                                                    property real value: streamRow.streamNode.audio
                                                        ? streamRow.streamNode.audio.volume : 0
                                                    readonly property real maximumValue: 1.5

                                                    function setVolumeFromX(mouseX) {
                                                        if (!streamRow.streamNode.audio)
                                                            return

                                                        const nextVolume = Math.max(0, Math.min(
                                                            maximumValue, mouseX / width * maximumValue))
                                                        value = nextVolume
                                                        streamRow.streamNode.audio.volume = nextVolume
                                                    }

                                                    Rectangle {
                                                        anchors.left: parent.left
                                                        anchors.right: parent.right
                                                        anchors.verticalCenter: parent.verticalCenter
                                                        height: 6
                                                        radius: 3
                                                        color: root.surfaceAlt

                                                        Rectangle {
                                                            width: Math.min(1, streamVolume.value
                                                                / streamVolume.maximumValue) * parent.width
                                                            height: parent.height
                                                            radius: parent.radius
                                                            color: root.accent
                                                        }
                                                    }

                                                    Rectangle {
                                                        x: Math.min(1, streamVolume.value
                                                            / streamVolume.maximumValue)
                                                            * (parent.width - width)
                                                        anchors.verticalCenter: parent.verticalCenter
                                                        width: 16
                                                        height: 16
                                                        radius: 8
                                                        color: root.foreground
                                                        border.width: 3
                                                        border.color: root.accent
                                                    }

                                                    MouseArea {
                                                        id: volumeMouse
                                                        anchors.fill: parent
                                                        hoverEnabled: true
                                                        preventStealing: true
                                                        cursorShape: Qt.PointingHandCursor
                                                        enabled: streamRow.streamNode.audio !== null

                                                        onPressed: mouse => {
                                                            closeTimer.stop()
                                                            window.volumeAdjusting = true
                                                            streamVolume.setVolumeFromX(mouse.x)
                                                        }
                                                        onPositionChanged: mouse => {
                                                            if (pressed)
                                                                streamVolume.setVolumeFromX(mouse.x)
                                                        }
                                                        onReleased: {
                                                            window.volumeAdjusting = false
                                                            Qt.callLater(() => {
                                                                if (!dashboardHoverArea.containsMouse) {
                                                                    closeTimer.interval = 420
                                                                    closeTimer.restart()
                                                                }
                                                            })
                                                        }
                                                        onCanceled: {
                                                            window.volumeAdjusting = false
                                                            Qt.callLater(() => {
                                                                if (!dashboardHoverArea.containsMouse) {
                                                                    closeTimer.interval = 420
                                                                    closeTimer.restart()
                                                                }
                                                            })
                                                        }
                                                    }

                                                    Connections {
                                                        target: streamRow.streamNode.audio

                                                        function onVolumesChanged() {
                                                            if (!volumeMouse.pressed)
                                                                streamVolume.value = streamRow.streamNode.audio.volume
                                                        }
                                                    }
                                                }

                                                Text {
                                                    Layout.preferredWidth: 38
                                                    horizontalAlignment: Text.AlignRight
                                                    text: streamRow.streamNode.audio
                                                        ? Math.round(streamRow.streamNode.audio.volume * 100) + "%"
                                                        : "—"
                                                    color: root.foreground
                                                    font.family: "JetBrainsMono Nerd Font"
                                                    font.pixelSize: 11
                                                }

                                                Rectangle {
                                                    Layout.preferredWidth: 36
                                                    Layout.preferredHeight: 36
                                                    radius: 11
                                                    color: streamRow.streamNode.audio && streamRow.streamNode.audio.muted
                                                        ? theme.criticalSubtle : root.surfaceAlt

                                                    Text {
                                                        anchors.centerIn: parent
                                                        text: streamRow.streamNode.audio && streamRow.streamNode.audio.muted
                                                            ? "󰖁" : "󰕾"
                                                        color: streamRow.streamNode.audio && streamRow.streamNode.audio.muted
                                                            ? root.critical : root.foreground
                                                        font.family: "JetBrainsMono Nerd Font"
                                                        font.pixelSize: 16
                                                    }

                                                    MouseArea {
                                                        anchors.fill: parent
                                                        enabled: streamRow.streamNode.audio !== null
                                                        cursorShape: Qt.PointingHandCursor
                                                        onClicked: streamRow.streamNode.audio.muted
                                                            = !streamRow.streamNode.audio.muted
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            ColumnLayout {
                                id: systemTab
                                readonly property int tabIndex: 2
                                readonly property bool tabActive: window.activeTab === tabIndex
                                anchors.fill: parent
                                spacing: 18
                                visible: tabActive || opacity > 0.001
                                enabled: tabActive
                                opacity: tabActive ? 1 : 0
                                Behavior on opacity {
                                    NumberAnimation { duration: 170; easing.type: Easing.OutCubic }
                                }

                                Text {
                                    text: "Состояние системы"
                                    color: root.foreground
                                    font.family: "JetBrainsMono Nerd Font"
                                    font.pixelSize: 24
                                    font.weight: Font.DemiBold
                                }

                                Repeater {
                                    model: [
                                        { title: "Процессор", value: root.cpuUsage, icon: "󰍛" },
                                        { title: "Оперативная память", value: root.memoryUsage, icon: "󰘚" },
                                        { title: "Системный диск", value: root.diskUsage, icon: "󰋊" }
                                    ]

                                    delegate: Rectangle {
                                        required property var modelData
                                        Layout.fillWidth: true
                                        Layout.fillHeight: true
                                        radius: 20
                                        color: root.surface

                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.margins: 24
                                            spacing: 20

                                            Text {
                                                text: modelData.icon
                                                color: modelData.value > 85 ? root.critical : root.accent
                                                font.family: "JetBrainsMono Nerd Font"
                                                font.pixelSize: 30
                                            }

                                            ColumnLayout {
                                                Layout.fillWidth: true

                                                RowLayout {
                                                    Layout.fillWidth: true

                                                    Text {
                                                        text: modelData.title
                                                        color: root.foreground
                                                        font.family: "JetBrainsMono Nerd Font"
                                                        font.pixelSize: 14
                                                    }

                                                    Item { Layout.fillWidth: true }

                                                    Text {
                                                        text: Math.round(modelData.value) + "%"
                                                        color: root.foreground
                                                        font.family: "JetBrainsMono Nerd Font"
                                                        font.pixelSize: 16
                                                        font.weight: Font.DemiBold
                                                    }
                                                }

                                                Rectangle {
                                                    Layout.fillWidth: true
                                                    Layout.preferredHeight: 10
                                                    radius: 5
                                                    color: root.background

                                                    Rectangle {
                                                        width: parent.width * Math.min(100, modelData.value) / 100
                                                        height: parent.height
                                                        radius: parent.radius
                                                        color: modelData.value > 85 ? root.critical : root.accent

                                                        Behavior on width { NumberAnimation { duration: 350; easing.type: Easing.OutCubic } }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            Rectangle {
                                id: networkTab
                                readonly property int tabIndex: 3
                                readonly property bool tabActive: window.activeTab === tabIndex
                                anchors.fill: parent
                                visible: tabActive || opacity > 0.001
                                enabled: tabActive
                                opacity: tabActive ? 1 : 0
                                radius: 22
                                color: root.surface
                                Behavior on opacity {
                                    NumberAnimation { duration: 170; easing.type: Easing.OutCubic }
                                }

                                ColumnLayout {
                                    anchors.fill: parent
                                    anchors.margins: 28
                                    spacing: 18

                                    RowLayout {
                                        Layout.fillWidth: true

                                        ColumnLayout {
                                            Layout.fillWidth: true

                                            Text {
                                                text: "Сетевая активность"
                                                color: root.foreground
                                                font.family: "JetBrainsMono Nerd Font"
                                                font.pixelSize: 20
                                                font.weight: Font.DemiBold
                                            }

                                            Text {
                                                text: root.networkInterfaces + " · последние 60 секунд"
                                                color: root.muted
                                                font.family: "JetBrainsMono Nerd Font"
                                                font.pixelSize: 11
                                            }
                                        }

                                        Text {
                                            text: "󰇚 " + root.formatRate(root.networkDown)
                                                + "   󰕒 " + root.formatRate(root.networkUp)
                                            color: root.foreground
                                            font.family: "JetBrainsMono Nerd Font"
                                            font.pixelSize: 14
                                            font.weight: Font.DemiBold
                                        }
                                    }

                                    Loader {
                                        Layout.fillWidth: true
                                        Layout.fillHeight: true
                                        sourceComponent: networkGraphComponent
                                    }

                                    RowLayout {
                                        Layout.alignment: Qt.AlignHCenter
                                        spacing: 22

                                        Text {
                                            text: "● загрузка"
                                            color: root.accent
                                            font.family: "JetBrainsMono Nerd Font"
                                            font.pixelSize: 11
                                        }

                                        Text {
                                            text: "● отдача"
                                            color: root.green
                                            font.family: "JetBrainsMono Nerd Font"
                                            font.pixelSize: 11
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
                id: dockWindow

                required property var modelData
                property int revealStage: 0
                property int hoveredIndex: -1
                property double keepOpenUntil: 0
                readonly property bool expanded: revealStage === 2
                readonly property var windows: root.windowsForScreen(screen)
                readonly property int contentWidth: Math.min(
                    screen.width - 48, Math.max(116, windows.length * 68 + 22))

                screen: modelData
                anchors.bottom: true
                implicitWidth: Math.max(contentWidth, 160)
                implicitHeight: 104
                color: "transparent"
                exclusionMode: ExclusionMode.Ignore
                mask: Region { item: dockHoverRegion }
                WlrLayershell.layer: WlrLayer.Overlay
                WlrLayershell.namespace: "quickshell-running-apps"

                function scheduleClose(delay) {
                    dockOpenTimer.stop()
                    if (Date.now() < keepOpenUntil)
                        return
                    dockCloseTimer.interval = delay
                    dockCloseTimer.restart()
                }

                function holdAfterActivation() {
                    keepOpenUntil = Date.now() + 1200
                    hoveredIndex = -1
                    revealStage = 2
                    dockOpenTimer.stop()
                    dockCloseTimer.stop()
                    dockReleaseTimer.restart()
                }


                Connections {
                    target: root

                    function onDockSwitcherRequested(address) {
                        const belongsToThisScreen = dockWindow.windows.some(toplevel =>
                            root.normalizedAddress(toplevel.address) === address)
                        if (!belongsToThisScreen)
                            return

                        dockWindow.hoveredIndex = -1
                        dockWindow.keepOpenUntil = 0
                        dockWindow.revealStage = 2
                        dockOpenTimer.stop()
                        dockCloseTimer.stop()
                        dockTransientTimer.restart()
                    }
                }

                Item {
                    id: dockHoverRegion
                    anchors.bottom: parent.bottom
                    anchors.horizontalCenter: parent.horizontalCenter
                    z: 10
                    width: dockWindow.revealStage === 2
                        ? dockWindow.contentWidth
                        : dockWindow.revealStage === 1 ? 150 : 160
                    height: dockWindow.revealStage === 2 ? 98 : 8

                    Behavior on width {
                        NumberAnimation {
                            duration: 500
                            easing.type: Easing.BezierSpline
                            easing.bezierCurve: [0.38, 1.21, 0.22, 1, 1, 1]
                        }
                    }
                    Behavior on height {
                        NumberAnimation {
                            duration: 500
                            easing.type: Easing.BezierSpline
                            easing.bezierCurve: [0.38, 1.21, 0.22, 1, 1, 1]
                        }
                    }

                    MouseArea {
                        id: dockEdgeMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        acceptedButtons: Qt.NoButton

                        onEntered: {
                            dockCloseTimer.stop()
                            if (dockWindow.revealStage === 0)
                                dockWindow.revealStage = 1
                            if (dockWindow.revealStage === 1)
                                dockOpenTimer.restart()
                        }
                        onExited: {
                            if (!dockSurfaceHover.hovered)
                                dockWindow.scheduleClose(dockWindow.revealStage === 1 ? 120 : 280)
                        }
                    }

                    HoverHandler {
                        id: dockEdgeHover
                        onHoveredChanged: {
                            if (hovered) {
                                dockCloseTimer.stop()
                                if (dockWindow.revealStage === 0)
                                    dockWindow.revealStage = 1
                                if (dockWindow.revealStage === 1)
                                    dockOpenTimer.restart()
                            } else if (!dockSurfaceHover.hovered) {
                                dockWindow.scheduleClose(dockWindow.revealStage === 1 ? 120 : 280)
                            }
                        }
                    }
                }

                Timer {
                    id: dockOpenTimer
                    interval: 80
                    onTriggered: dockWindow.revealStage = 2
                }

                Timer {
                    id: dockCloseTimer
                    interval: 280
                    onTriggered: {
                        dockWindow.hoveredIndex = -1
                        dockWindow.revealStage = 0
                    }
                }

                Timer {
                    id: dockReleaseTimer
                    interval: 1250
                    onTriggered: {
                        if (!dockEdgeMouse.containsMouse
                                && !dockEdgeHover.hovered
                                && !dockSurfaceHover.hovered)
                            dockWindow.scheduleClose(280)
                    }
                }

                Timer {
                    id: dockTransientTimer
                    interval: 900
                    onTriggered: {
                        if (!dockEdgeMouse.containsMouse
                                && !dockEdgeHover.hovered
                                && !dockSurfaceHover.hovered)
                            dockWindow.scheduleClose(0)
                    }
                }

                Rectangle {
                    id: dockSurface
                    anchors.bottom: parent.bottom
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 150
                    height: 5
                    radius: 3
                    color: root.accent
                    opacity: dockWindow.revealStage === 1 ? 1 : 0

                    Behavior on opacity { NumberAnimation { duration: 140 } }
                }

                Rectangle {
                    anchors.bottom: parent.bottom
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: dockWindow.expanded ? dockWindow.contentWidth : 180
                    height: dockWindow.expanded ? 88 : 0
                    radius: 22
                    color: root.background
                    border.width: 1
                    border.color: theme.outline
                    clip: true

                    Behavior on width {
                        NumberAnimation {
                            duration: 500
                            easing.type: Easing.BezierSpline
                            easing.bezierCurve: [0.38, 1.21, 0.22, 1, 1, 1]
                        }
                    }
                    Behavior on height {
                        NumberAnimation {
                            duration: 500
                            easing.type: Easing.BezierSpline
                            easing.bezierCurve: [0.38, 1.21, 0.22, 1, 1, 1]
                        }
                    }

                    HoverHandler {
                        id: dockSurfaceHover
                        enabled: dockWindow.expanded

                        onHoveredChanged: {
                            if (hovered) {
                                dockCloseTimer.stop()
                            } else if (!dockEdgeHover.hovered) {
                                dockWindow.scheduleClose(280)
                            }
                        }
                    }

                    Row {
                        anchors.centerIn: parent
                        spacing: 4
                        opacity: dockWindow.expanded ? 1 : 0
                        enabled: dockWindow.expanded

                        Behavior on opacity { NumberAnimation { duration: 130 } }

                        Repeater {
                            model: dockWindow.windows

                            delegate: Item {
                                id: appItem
                                required property int index
                                required property var modelData
                                readonly property bool activeWindow:
                                    root.activeWindowAddress === root.normalizedAddress(modelData.address)
                                readonly property bool selectedWindow:
                                    root.dockCycleActive
                                        && root.dockSelectedAddress === root.normalizedAddress(modelData.address)
                                width: 64
                                height: 70
                                scale: dockWindow.hoveredIndex === index ? 1.06 : 1

                                Behavior on scale {
                                    NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
                                }

                                Rectangle {
                                    anchors.fill: parent
                                    radius: 15
                                    color: appItem.selectedWindow
                                        ? root.selected
                                        : appItem.activeWindow
                                        ? root.surface
                                        : (dockWindow.hoveredIndex === index ? root.surfaceAlt : "transparent")

                                    Behavior on color { ColorAnimation { duration: 120 } }
                                }

                                IconImage {
                                    id: dockIcon
                                    anchors.top: parent.top
                                    anchors.topMargin: 9
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    width: 34
                                    height: 34
                                    source: Quickshell.iconPath(root.windowIcon(modelData), true)
                                    visible: source.toString().length > 0
                                }

                                Rectangle {
                                    anchors.top: parent.top
                                    anchors.topMargin: 9
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    width: 34
                                    height: 34
                                    radius: 11
                                    visible: !dockIcon.visible
                                    color: root.surfaceAlt

                                    Text {
                                        anchors.centerIn: parent
                                        text: root.windowName(modelData).slice(0, 1).toUpperCase()
                                        color: root.foreground
                                        font.family: "JetBrainsMono Nerd Font"
                                        font.pixelSize: 14
                                        font.weight: Font.Bold
                                    }
                                }

                                Text {
                                    anchors.bottom: parent.bottom
                                    anchors.bottomMargin: 7
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    width: parent.width - 8
                                    text: root.windowName(modelData)
                                    color: appItem.selectedWindow || appItem.activeWindow
                                        ? root.foreground : root.muted
                                    horizontalAlignment: Text.AlignHCenter
                                    elide: Text.ElideRight
                                    font.family: "JetBrainsMono Nerd Font"
                                    font.pixelSize: 8
                                    font.weight: Font.DemiBold
                                }

                                Rectangle {
                                    anchors.bottom: parent.bottom
                                    anchors.bottomMargin: 1
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    width: appItem.selectedWindow ? 26 : (appItem.activeWindow ? 18 : 5)
                                    height: 3
                                    radius: 2
                                    color: modelData.urgent ? root.critical : root.accent

                                    Behavior on width { NumberAnimation { duration: 150 } }
                                }

                                MouseArea {
                                    id: appMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onEntered: {
                                        dockWindow.hoveredIndex = index
                                        dockCloseTimer.stop()
                                    }
                                    onExited: {
                                        if (dockWindow.hoveredIndex === index)
                                            dockWindow.hoveredIndex = -1
                                        if (!dockEdgeHover.hovered && !dockSurfaceHover.hovered)
                                            dockWindow.scheduleClose(280)
                                    }
                                    onClicked: {
                                        dockWindow.holdAfterActivation()
                                        root.activateWindow(modelData)
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
