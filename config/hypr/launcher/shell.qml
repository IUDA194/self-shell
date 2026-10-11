import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland

ShellRoot {
    id: root

    Theme { id: theme }
    readonly property bool isNiri: Quickshell.env("NIRI_SOCKET").length > 0

    property string interfaceStyle: "modern"
    property string launcherPosition: "center"
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
                root.launcherPosition = state.launcherPosition || "center"
            }
            catch (error) { root.interfaceStyle = "modern" }
        }
    }

    readonly property color background: theme.background
    readonly property color surface: theme.surface
    readonly property color surfaceAlt: theme.surfaceAlt
    readonly property color selected: theme.selected
    readonly property color foreground: theme.foreground
    readonly property color muted: theme.muted
    readonly property color accent: theme.accent

    property var results: []
    property var launchHistory: ({})
    readonly property var launcherActions: [
        { name: "Обои", description: "!wallpaper — выбрать обои", keywords: "wallpaper wall walls обои", category: "Оформление", icon: "preferences-desktop-wallpaper", symbol: "󰸉", mode: "wallpaper", command: "" },
        { name: "Настройки", description: "!settings · !настройки — внешний вид и темы", keywords: "settings настройки appearance theme оформление тема", category: "Оформление", icon: "preferences-system", symbol: "󰒓", mode: "settings", command: Quickshell.env("HOME") + "/.config/hypr/settings.sh" },
        { name: "Уведомления", description: "!notifications — последние события", keywords: "notifications notification notif уведомления уведомление увед", category: "Уведомления", icon: "preferences-system-notifications", symbol: "󰂚", mode: "notifications", command: "" },
        { name: "Система", description: "Сеанс и питание", keywords: "system power session система питание сеанс", category: "Система", icon: "system-shutdown", symbol: "", mode: "system", command: "" },
        { name: "Игровой режим", description: "Включить или выключить эффекты и тайлинг", keywords: "gaming game performance игры игровой режим производительность", category: "Система", icon: "applications-games", symbol: "󰊴", mode: "", command: Quickshell.env("HOME") + "/.config/hypr/gaming-mode.sh toggle" }
    ]
    readonly property var customApplications: [
        { id: "local-telegram", name: "Telegram", description: "Мессенджер", keywords: "telegram телеграм messenger мессенджер", icon: "telegram", command: Quickshell.env("HOME") + "/Apps/Telegram" }
    ]
    readonly property var systemActions: [
        { name: "Заблокировать", description: "Заблокировать текущий сеанс", category: "Сеанс", icon: "system-lock-screen", symbol: "", command: Quickshell.env("HOME") + "/.config/hypr/hyprlock-current.sh" },
        { name: "Выйти", description: "Завершить текущий сеанс", category: "Сеанс", icon: "system-log-out", symbol: "󰗼", command: root.isNiri ? "niri msg action quit" : "hyprctl dispatch exit" },
        { name: "Сон", description: "Перевести компьютер в спящий режим", category: "Питание", icon: "system-suspend", symbol: "󰒲", command: "systemctl suspend" },
        { name: "Перезагрузить", description: "Перезагрузить компьютер", category: "Питание", icon: "system-reboot", symbol: "", command: "systemctl reboot" },
        { name: "Выключить", description: "Выключить компьютер", category: "Питание", icon: "system-shutdown", symbol: "", command: "systemctl poweroff" }
    ]
    property bool closing: false
    property bool keyboardNavigating: false
    property bool windowShown: false
    property var wallpapers: []
    property string currentWallpaper: ""
    property bool wallpaperMode: false
    property bool liveWallpaperMode: false
    property string staticWallpaperSelection: ""
    property string liveWallpaperSelection: ""
    property string wallpaperSortMode: "name"
    readonly property string wallpaperSortLabel: wallpaperSortMode === "color" ? "Цвет"
        : wallpaperSortMode === "date" ? "Новые" : "Название"
    property bool systemMode: false
    property bool notificationsMode: false
    property var notifications: []
    property var notificationGroups: []
    property string expandedNotificationGroup: ""
    // Caelestia's Material 3 expressive motion tokens.
    property real revealProgress: 0

    FileView {
        id: historyFile
        path: Quickshell.env("HOME") + "/.local/state/quickshell-launcher/history.json"
        blockLoading: true
        atomicWrites: true
    }

    FileView {
        id: wallpaperManifest
        path: Quickshell.env("HOME") + "/.cache/hypr-wallpapers/manifest.json"
        blockLoading: true
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: root.loadWallpapers()
    }

    FileView {
        id: waypaperConfig
        path: Quickshell.env("HOME") + "/.config/waypaper/config.ini"
        blockLoading: true
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            const match = text().match(/^wallpaper\s*=\s*(.+)$/m)
            if (match) {
                let value = match[1].trim()
                if (value.startsWith("~/"))
                    value = Quickshell.env("HOME") + "/" + value.slice(2)
                root.currentWallpaper = value
                if (root.wallpaperMode) {
                    root.liveWallpaperMode = root.isLiveWallpaperPath(value)
                    wallpaperCarousel.currentIndex = -1
                    root.setWallpaperPrompt()
                }
            }
        }
    }

    ListModel { id: wallpaperModel }

    Process {
        id: notificationListProcess
        command: ["quickshell", "ipc", "call", "notifications", "listJson"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.notifications = text.trim().length > 0 ? JSON.parse(text.trim()) : []
                } catch (error) {
                    root.notifications = []
                }
                root.refreshNotifications()
            }
        }
    }

    Process {
        id: notificationDismissProcess
        onExited: notificationListProcess.running = true
    }

    Process {
        id: notificationClearProcess
        command: ["quickshell", "ipc", "call", "notifications", "clear"]
        onExited: {
            root.notifications = []
            root.refreshNotifications()
        }
    }

    Process {
        id: wallpaperPrepareProcess
        command: [Quickshell.env("HOME") + "/.config/hypr/rofi-wallpapers.sh", "--prepare"]
        onExited: {
            wallpaperManifest.reload()
            root.loadWallpapers()
        }
    }

    Process {
        id: wallpaperApplyProcess
        onExited: function(exitCode, exitStatus) {
            if (exitCode === 0)
                root.closeLauncher()
        }
    }

    function wallpaperName(name) {
        return name.replace(/\.[^.]+$/, "").replace(/[-_]+/g, " ")
    }

    function wallpaperColorKey(value) {
        const hex = String(value || "#808080").replace("#", "").slice(-6)
        const red = parseInt(hex.slice(0, 2), 16) / 255
        const green = parseInt(hex.slice(2, 4), 16) / 255
        const blue = parseInt(hex.slice(4, 6), 16) / 255
        const maximum = Math.max(red, green, blue)
        const minimumValue = Math.min(red, green, blue)
        const delta = maximum - minimumValue
        let hue = 0
        if (delta > 0) {
            if (maximum === red)
                hue = ((green - blue) / delta + (green < blue ? 6 : 0)) / 6
            else if (maximum === green)
                hue = ((blue - red) / delta + 2) / 6
            else
                hue = ((red - green) / delta + 4) / 6
        }
        const saturation = maximum === 0 ? 0 : delta / maximum
        return (saturation < 0.08 ? 2 : hue) * 1000000 + saturation * 1000 + maximum
    }

    function compareWallpapers(left, right) {
        if (wallpaperSortMode === "date") {
            const difference = Number(right.addedAt || 0) - Number(left.addedAt || 0)
            if (difference !== 0)
                return difference
        } else if (wallpaperSortMode === "color") {
            const difference = wallpaperColorKey(left.accent) - wallpaperColorKey(right.accent)
            if (Math.abs(difference) > 0.001)
                return difference
        }
        return wallpaperName(left.name).localeCompare(wallpaperName(right.name), undefined,
                                                       { sensitivity: "base", numeric: true })
    }

    function cycleWallpaperSort() {
        wallpaperSortMode = wallpaperSortMode === "name" ? "color"
            : wallpaperSortMode === "color" ? "date" : "name"
        refreshWallpapers()
    }

    function isLiveWallpaperPath(path) {
        return path.startsWith(Quickshell.env("HOME") + "/Documents/Wallpapers/live/")
    }

    function wallpaperQuery() {
        return searchField.text
            .replace(/^!wallpaper(?:\s+(?:static|live))?\s*/i, "")
    }

    function setWallpaperPrompt() {
        const query = wallpaperQuery()
        searchField.text = "!wallpaper " + (liveWallpaperMode ? "live " : "static ") + query
        searchField.cursorPosition = searchField.text.length
    }
    function focusSearchInput() {
        if (minimum)
            minimumSearchInput.forceActiveFocus()
        else
            searchField.forceActiveFocus()
    }

    function showLiveWallpapers(live) {
        if (!wallpaperMode || liveWallpaperMode === live)
            return
        if (wallpaperCarousel.currentIndex >= 0
                && wallpaperCarousel.currentIndex < wallpaperModel.count) {
            const selectedPath = wallpaperModel.get(wallpaperCarousel.currentIndex).path
            if (liveWallpaperMode)
                liveWallpaperSelection = selectedPath
            else
                staticWallpaperSelection = selectedPath
        }
        liveWallpaperMode = live
        wallpaperModel.clear()
        wallpaperCarousel.currentIndex = -1
        setWallpaperPrompt()
    }

    function loadWallpapers() {
        try {
            const text = wallpaperManifest.text().trim()
            wallpapers = text.length > 0 ? JSON.parse(text) : []
        } catch (error) {
            wallpapers = []
        }
        refreshWallpapers()
    }

    function refreshWallpapers() {
        if (!wallpaperMode)
            return
        const query = wallpaperQuery().trim().toLowerCase()
        let previous = wallpaperCarousel.currentIndex >= 0
            && wallpaperCarousel.currentIndex < wallpaperModel.count
            ? wallpaperModel.get(wallpaperCarousel.currentIndex).path : currentWallpaper
        const wantedGroup = liveWallpaperMode ? "live" : "static"
        const previousIsLive = isLiveWallpaperPath(previous)
        if ((wantedGroup === "live") !== previousIsLive) {
            const remembered = liveWallpaperMode ? liveWallpaperSelection : staticWallpaperSelection
            previous = remembered || (isLiveWallpaperPath(currentWallpaper) === liveWallpaperMode
                ? currentWallpaper : "")
        }
        const visibleWallpapers = []
        for (let i = 0; i < wallpapers.length; ++i) {
            const wall = wallpapers[i]
            if ((wall.group || "static") === wantedGroup
                    && (!query || wallpaperName(wall.name).toLowerCase().indexOf(query) >= 0))
                visibleWallpapers.push(wall)
        }
        visibleWallpapers.sort(compareWallpapers)
        wallpaperModel.clear()
        for (let i = 0; i < visibleWallpapers.length; ++i)
            wallpaperModel.append(visibleWallpapers[i])
        let next = wallpaperModel.count > 0 ? 0 : -1
        for (let j = 0; j < wallpaperModel.count; ++j) {
            if (wallpaperModel.get(j).path === previous) {
                next = j
                break
            }
        }
        wallpaperCarousel.currentIndex = next
        if (next >= 0)
            Qt.callLater(function() { wallpaperCarousel.positionViewAtIndex(next, ListView.Center) })
    }

    function enterWallpaperMode() {
        wallpaperMode = true
        liveWallpaperMode = isLiveWallpaperPath(currentWallpaper)
        systemMode = false
        notificationsMode = false
        wallpaperCarousel.currentIndex = -1
        searchField.text = "!wallpaper " + (liveWallpaperMode ? "live " : "static ")
        refreshWallpapers()
        wallpaperPrepareProcess.running = true
        Qt.callLater(function() {
            root.focusSearchInput()
        })
    }

    function enterSystemMode() {
        wallpaperMode = false
        systemMode = true
        notificationsMode = false
        searchField.text = "!system "
        refreshResults(false)
        Qt.callLater(function() {
            root.focusSearchInput()
            searchField.cursorPosition = searchField.text.length
        })
    }

    function enterNotificationsMode() {
        wallpaperMode = false
        systemMode = false
        notificationsMode = true
        searchField.text = "!notifications "
        notificationListProcess.running = false
        notificationListProcess.running = true
        Qt.callLater(function() {
            root.focusSearchInput()
            searchField.cursorPosition = searchField.text.length
        })
    }

    function notificationAge(createdAt) {
        const minutes = Math.floor(Math.max(0, Date.now() - Number(createdAt)) / 60000)
        if (minutes < 1) return "сейчас"
        if (minutes < 60) return minutes + " мин"
        const hours = Math.floor(minutes / 60)
        if (hours < 24) return hours + " ч"
        return Math.floor(hours / 24) + " д"
    }

    function notificationLine(value) {
        // Notification bodies often contain explicit line breaks. The launcher
        // uses compact one-line previews, so collapse all whitespace first.
        return String(value || "").replace(/\s+/g, " ").trim()
    }

    function refreshNotifications() {
        if (!notificationsMode)
            return
        const enteredQuery = searchField.text.replace(/^!notifications\s*/i, "").trim().toLowerCase()
        // `clear` is a command awaiting Enter, not a live search filter.
        const query = enteredQuery === "clear" ? "" : enteredQuery
        const groups = []
        const positions = ({})
        for (let i = 0; i < notifications.length; ++i) {
            const item = notifications[i]
            const haystack = (item.appName + " " + item.summary + " " + item.body).toLowerCase()
            if (query && haystack.indexOf(query) < 0)
                continue
            const key = String(item.appName || "Система").toLowerCase()
            let position = positions[key]
            if (position === undefined) {
                position = groups.length
                positions[key] = position
                groups.push({
                    key: key,
                    appName: item.appName || "Система",
                    appIcon: item.appIcon,
                    urgency: item.urgency,
                    latest: item,
                    entries: []
                })
            }
            groups[position].entries.push(item)
            groups[position].urgency = Math.max(groups[position].urgency, item.urgency)
        }
        notificationGroups = groups
        if (expandedNotificationGroup.length > 0
                && groups.findIndex(group => group.key === expandedNotificationGroup) < 0)
            expandedNotificationGroup = ""
        notificationList.currentIndex = notificationGroups.length > 0 ? 0 : -1
    }

    function toggleNotificationGroup(index) {
        if (index < 0 || index >= notificationGroups.length)
            return
        const key = notificationGroups[index].key
        expandedNotificationGroup = expandedNotificationGroup === key ? "" : key
        // ListView may keep positions calculated for the old delegate heights
        // until the next scroll. Re-layout immediately after expanding/collapsing.
        Qt.callLater(function() { notificationList.forceLayout() })
    }

    function dismissNotification(id) {
        notificationDismissProcess.exec(["quickshell", "ipc", "call", "notifications", "dismiss", String(id)])
    }

    function clearNotifications() {
        if (notificationClearProcess.running)
            return
        notificationClearProcess.running = true
        searchField.text = "!notifications "
        searchField.cursorPosition = searchField.text.length
    }

    function submitNotificationInput() {
        if (searchField.text.trim().toLowerCase() === "!notifications clear")
            clearNotifications()
        else
            toggleNotificationGroup(notificationList.currentIndex)
    }

    function activateWallpaper() {
        if (wallpaperCarousel.currentIndex < 0 || wallpaperCarousel.currentIndex >= wallpaperModel.count)
            return
        const wall = wallpaperModel.get(wallpaperCarousel.currentIndex)
        wallpaperApplyProcess.exec([Quickshell.env("HOME") + "/.config/hypr/rofi-wallpapers.sh", "--apply", wall.path])
    }

    function historyFor(applicationId) {
        return launchHistory[applicationId] || { count: 0, last: 0 }
    }

    function recordLaunch(applicationId) {
        const previous = historyFor(applicationId)
        launchHistory[applicationId] = {
            count: Number(previous.count || 0) + 1,
            last: Date.now()
        }
        historyFile.setText(JSON.stringify(launchHistory))
        historyFile.waitForJob()
    }

    function fuzzyScore(value, query) {
        const text = value.toLowerCase()
        const needle = query.toLowerCase().trim()
        if (needle.length === 0)
            return 1
        if (text.startsWith(needle))
            return 1200 - text.length

        const direct = text.indexOf(needle)
        if (direct >= 0)
            return 900 - direct * 4 - text.length

        let position = 0
        let gap = 0
        for (let i = 0; i < needle.length; ++i) {
            const found = text.indexOf(needle[i], position)
            if (found < 0)
                return -1
            gap += found - position
            position = found + 1
        }
        return 500 - gap * 5 - text.length
    }

    function launcherIconSource(result) {
        const name = String(result.name || "").toLowerCase()
        if (name === "telegram")
            return "file:///usr/share/icons/Papirus/48x48/apps/telegram.svg"
        if (name === "firefox")
            return "file:///usr/share/icons/Papirus/48x48/apps/firefox.svg"
        return Quickshell.iconPath(String(result.icon), "image-missing")
    }

    function refreshResults(preserveSelection) {
        if (wallpaperMode) {
            refreshWallpapers()
            return
        }
        if (notificationsMode) {
            refreshNotifications()
            return
        }
        const selectedId = preserveSelection
            && resultList.currentIndex >= 0
            && resultList.currentIndex < results.length
            && results[resultList.currentIndex].entry
            ? results[resultList.currentIndex].entry.id : ""
        const query = searchField.text.trim()
        const matches = []

        if (query.startsWith("!") || systemMode) {
            const actionQuery = systemMode
                ? query.replace(/^!system\s*/i, "").trim()
                : query.slice(1).trim()
            const settingsAlias = /^(settings|настройки)$/i.test(actionQuery)
            const availableActions = systemMode ? systemActions
                : settingsAlias ? launcherActions.filter(action => action.mode === "settings")
                : launcherActions
            for (let i = 0; i < availableActions.length; ++i) {
                const action = availableActions[i]
                const match = fuzzyScore(action.name + " " + action.description
                    + " " + (action.keywords || ""), actionQuery)
                if (match >= 0) {
                    matches.push({
                        kind: "action",
                        entry: null,
                        name: action.name,
                        description: action.description,
                        icon: action.icon,
                        symbol: action.symbol,
                        command: action.command,
                        mode: action.mode || "",
                        category: action.category || "",
                        score: match * 1000 - i
                    })
                }
            }
            matches.sort(function(left, right) { return right.score - left.score })
            results = matches
            resultList.currentIndex = results.length > 0 ? 0 : -1
            return
        }

        const applications = DesktopEntries.applications.values

        for (let i = 0; i < customApplications.length; ++i) {
            const application = customApplications[i]
            const searchable = application.name + " " + application.description
                + " " + application.keywords + " " + application.command
            const match = fuzzyScore(searchable, query)
            if (match >= 0) {
                const usage = historyFor(application.id)
                const count = Number(usage.count || 0)
                const lastUsed = Number(usage.last || 0)
                const score = query.length === 0
                    ? count * 10000 + lastUsed / 10000000000000
                    : match * 10000 + Math.min(count, 999)
                matches.push({
                    kind: "customApp",
                    entry: application,
                    name: application.name,
                    description: application.description,
                    icon: application.icon,
                    command: application.command,
                    score: score
                })
            }
        }

        for (let i = 0; i < applications.length; ++i) {
            const application = applications[i]
            if (!application || application.noDisplay)
                continue

            const searchable = application.name + " " + application.genericName
                + " " + application.comment + " " + application.execString
            const match = fuzzyScore(searchable, query)
            if (match >= 0) {
                const usage = historyFor(application.id)
                const count = Number(usage.count || 0)
                const lastUsed = Number(usage.last || 0)
                const score = query.length === 0
                    ? count * 10000 + lastUsed / 10000000000000
                    : match * 10000 + Math.min(count, 999)
                matches.push({
                    kind: "app",
                    entry: application,
                    name: application.name,
                    description: application.genericName || application.comment || "Приложение",
                    icon: application.icon,
                    score: score
                })
            }
        }

        matches.sort(function(left, right) {
            if (left.score !== right.score)
                return right.score - left.score
            return left.name.localeCompare(right.name)
        })

        results = matches.slice(0, query.length === 0 ? 24 : 40)
        let nextIndex = results.length > 0 ? 0 : -1
        if (selectedId.length > 0) {
            const preservedIndex = results.findIndex(result =>
                result.entry && result.entry.id === selectedId)
            if (preservedIndex >= 0)
                nextIndex = preservedIndex
        }
        resultList.currentIndex = nextIndex
    }

    function activate(index) {
        if (index < 0 || index >= results.length)
            return

        const result = results[index]
        if (result.kind === "action" && result.mode === "wallpaper") {
            enterWallpaperMode()
            return
        } else if (result.kind === "action" && result.mode === "system") {
            enterSystemMode()
            return
        } else if (result.kind === "action" && result.mode === "notifications") {
            enterNotificationsMode()
            return
        } else if (result.kind === "action")
            Quickshell.execDetached(["bash", "-lc", result.command])
        else if (result.kind === "customApp") {
            recordLaunch(result.entry.id)
            Quickshell.execDetached([result.command])
        }
        else {
            recordLaunch(result.entry.id)
            result.entry.execute()
        }
        closeLauncher()
    }

    function openLauncher() {
        closeTimer.stop()
        closing = false
        // Reveal the complete surface from the bottom screen edge.
        if (!windowShown)
            revealProgress = 0
        windowShown = true
        wallpaperMode = false
        systemMode = false
        notificationsMode = false
        searchField.clear()
        refreshResults(false)
        Qt.callLater(function() {
            root.focusSearchInput()
            root.revealProgress = 1
        })
    }

    function closeLauncher() {
        if (closing || !windowShown)
            return
        closing = true
        revealProgress = 0
        closeTimer.restart()
    }

    IpcHandler {
        target: "launcher"

        function open(): void {
            root.openLauncher()
        }

        function close(): void {
            root.closeLauncher()
        }

        function toggle(): void {
            if (root.windowShown && !root.closing)
                root.closeLauncher()
            else
                root.openLauncher()
        }

        function wallpaper(): void {
            if (!root.windowShown || root.closing)
                root.openLauncher()
            root.enterWallpaperMode()
        }

        function notifications(): void {
            if (!root.windowShown || root.closing)
                root.openLauncher()
            root.enterNotificationsMode()
        }

        function isOpen(): bool {
            return root.windowShown && !root.closing
        }

    }

    GlobalShortcut {
        appid: "quickshell-launcher"
        name: "launcher"
        description: "Toggle the application launcher"
        onPressed: {
            if (root.windowShown && !root.closing)
                root.closeLauncher()
            else
                root.openLauncher()
        }
    }

    Timer {
        id: closeTimer
        // Keep the layer alive until the spatial animation finishes.
        interval: root.minimum ? 100 : 270
        onTriggered: {
            root.windowShown = false
            root.closing = false
        }
    }

    Component.onCompleted: {
        try {
            const stored = historyFile.text().trim()
            launchHistory = stored.length > 0 ? JSON.parse(stored) : ({})
        } catch (error) {
            launchHistory = ({})
        }
        refreshResults(false)
    }

    Behavior on revealProgress {
        enabled: root.windowShown

        NumberAnimation {
            duration: root.minimum ? 90 : 260
            easing.type: Easing.BezierSpline
            easing.bezierCurve: [0.38, 1.21, 0.22, 1, 1, 1]
        }
    }

    Connections {
        target: DesktopEntries.applications
        function onValuesChanged() { root.refreshResults(true) }
    }

    PanelWindow {
        id: window

        screen: {
            if (root.isNiri)
                return Quickshell.screens[0]
            const monitor = Hyprland.focusedMonitor
            if (!monitor)
                return Quickshell.screens[0]
            return Quickshell.screens.find(screen => screen.name === monitor.name)
                || Quickshell.screens[0]
        }
        visible: root.windowShown
        anchors.top: true
        anchors.right: true
        anchors.bottom: true
        anchors.left: true
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: root.windowShown
            ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

        Shortcut {
            sequence: "Escape"
            onActivated: root.closeLauncher()
        }

        MouseArea {
            anchors.fill: parent
            onClicked: root.closeLauncher()
        }

        Rectangle {
            id: launcherPanel

            readonly property int visibleRows: root.wallpaperMode ? 0
                : root.notificationsMode ? 0
                : Math.min(root.minimum ? 8 : 7, root.results.length)
            readonly property real notificationContentHeight: {
                if (root.notificationGroups.length === 0)
                    return 112

                let total = 0
                for (let i = 0; i < root.notificationGroups.length; ++i) {
                    const group = root.notificationGroups[i]
                    total += 58
                    if (group.key === root.expandedNotificationGroup)
                        total += (group.entries ? group.entries.length : 0) * 54 + 4
                }
                total += Math.max(0, root.notificationGroups.length - 1) * 8
                return Math.min(420, total)
            }
            readonly property real listContentHeight: visibleRows > 0
                ? visibleRows * (root.notificationsMode ? 78 : (root.minimum ? 36 : 57))
                    + Math.max(0, visibleRows - 1) * (root.minimum ? 1 : 8)
                : root.wallpaperMode ? 166
                    : root.notificationsMode ? notificationContentHeight
                    : 96
            readonly property real contentHeight: listContentHeight + (root.minimum ? 44 : 48)
                + (root.minimum ? 24 : 44)
            readonly property real expandedHeight: Math.min(parent.height - 48, contentHeight)
            property real animatedHeight: expandedHeight

            onExpandedHeightChanged: animatedHeight = expandedHeight

            Behavior on animatedHeight {
                enabled: root.windowShown && !root.closing && root.revealProgress > 0.98
                NumberAnimation {
                    duration: root.minimum ? 100 : 320
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: [0.38, 1.21, 0.22, 1, 1, 1]
                }
            }

            width: Math.min(parent.width - 48, root.wallpaperMode ? 1050 : (root.minimum ? 620 : 632))
            height: animatedHeight * root.revealProgress
            x: root.minimum
                ? (root.launcherPosition.endsWith("left") || root.launcherPosition === "left" ? 1
                    : root.launcherPosition.endsWith("right") || root.launcherPosition === "right" ? parent.width - width - 1
                    : Math.round((parent.width - width) / 2))
                : Math.round((parent.width - width) / 2 + 28)
            y: root.minimum
                ? (root.launcherPosition.startsWith("top") ? 42
                    : root.launcherPosition.startsWith("bottom") ? parent.height - height - 1
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

            // Continue the panel through the screen edge while preserving the
            // one-pixel side borders all the way down.
            Rectangle {
                visible: !root.minimum
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.leftMargin: launcherPanel.border.width
                anchors.rightMargin: launcherPanel.border.width
                height: launcherPanel.radius
                color: parent.color
            }

            Rectangle {
                visible: !root.minimum
                anchors.left: parent.left
                anchors.bottom: parent.bottom
                width: launcherPanel.border.width
                height: launcherPanel.radius
                color: launcherPanel.border.color
            }

            Rectangle {
                visible: !root.minimum
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                width: launcherPanel.border.width
                height: launcherPanel.radius
                color: launcherPanel.border.color
            }

            MouseArea {
                anchors.fill: parent
                onClicked: function(mouse) { mouse.accepted = true }
            }

            Item {
                anchors.fill: parent
                anchors.leftMargin: root.minimum ? 8 : 16
                anchors.rightMargin: root.minimum ? 8 : 16
                anchors.topMargin: root.minimum ? 8 : 16
                anchors.bottomMargin: root.minimum ? 8 : 12

                Item {
                    id: listArea

                    anchors.top: parent.top
                    anchors.topMargin: root.minimum ? 50 : 0
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: root.minimum ? 0 : 64
                    clip: true

                    ListView {
                        id: resultList

                        anchors.fill: parent
                        model: root.results
                        currentIndex: root.results.length > 0 ? 0 : -1
                        spacing: root.minimum ? 1 : 8
                        clip: true
                        visible: !root.wallpaperMode && !root.notificationsMode && count > 0
                        boundsBehavior: Flickable.StopAtBounds
                        keyNavigationWraps: true
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
                                from: 0
                                to: 1
                                duration: root.minimum ? 60 : 200
                                easing.type: Easing.BezierSpline
                                easing.bezierCurve: [0.34, 0.8, 0.34, 1, 1, 1]
                            }
                        }

                        remove: Transition {
                            NumberAnimation {
                                property: "opacity"
                                from: 1
                                to: 0
                                duration: root.minimum ? 60 : 200
                                easing.type: Easing.BezierSpline
                                easing.bezierCurve: [0.34, 0.8, 0.34, 1, 1, 1]
                            }
                        }

                        ScrollBar.vertical: ScrollBar {
                            policy: ScrollBar.AsNeeded
                            width: 3
                            contentItem: Rectangle {
                                implicitWidth: 3
                                radius: 2
                                color: root.accent
                                opacity: 0.5
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
                                    anchors.topMargin: root.minimum ? 5 : 8
                                    anchors.bottomMargin: root.minimum ? 5 : 8
                                    spacing: root.minimum ? 8 : 12

                                Item {
                                    Layout.preferredWidth: root.minimum ? 20 : 32
                                    Layout.preferredHeight: root.minimum ? 20 : 32
                                    Layout.alignment: Qt.AlignVCenter

                                    // Built-in launcher actions have a stable Nerd Font
                                    // glyph. Avoid Qt's magenta image-missing placeholder
                                    // when an icon theme cannot resolve their legacy name.
                                    Text {
                                        anchors.centerIn: parent
                                        visible: resultRow.modelData.kind === "action"
                                        text: resultRow.modelData.symbol || "󰣇"
                                        color: root.foreground
                                        font.family: "JetBrainsMono Nerd Font"
                                        font.pixelSize: root.minimum ? 16 : 25
                                    }

                                    Image {
                                        anchors.fill: parent
                                        visible: resultRow.modelData.kind !== "action"
                                        source: root.launcherIconSource(resultRow.modelData)
                                        sourceSize.width: 64
                                        sourceSize.height: 64
                                        fillMode: Image.PreserveAspectFit
                                        smooth: true
                                        mipmap: true
                                        asynchronous: false
                                    }
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    Layout.alignment: Qt.AlignVCenter
                                    spacing: 0

                                    Text {
                                        Layout.fillWidth: true
                                        text: resultRow.modelData.name
                                        color: root.foreground
                                        elide: Text.ElideRight
                                        font.family: root.minimum ? "JetBrainsMono Nerd Font" : "Noto Sans"
                                        font.pixelSize: root.minimum ? 11 : 14
                                        font.weight: Font.Medium
                                        verticalAlignment: Text.AlignVCenter
                                    }

                                    Text {
                                        visible: !root.minimum
                                        Layout.fillWidth: true
                                        text: resultRow.modelData.description
                                        color: root.muted
                                        elide: Text.ElideRight
                                        font.family: "Noto Sans"
                                        font.pixelSize: root.minimum ? 10 : 12
                                    }
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

                    ListView {
                        id: notificationList
                        anchors.fill: parent
                        model: root.notificationGroups
                        spacing: 8
                        clip: true
                        visible: root.notificationsMode && count > 0
                        boundsBehavior: Flickable.StopAtBounds
                        keyNavigationWraps: true
                        highlightFollowsCurrentItem: false

                        displaced: Transition {
                            NumberAnimation {
                                property: "y"
                                duration: 180
                                easing.type: Easing.OutCubic
                            }
                        }

                        highlight: Rectangle {
                            y: notificationList.currentItem ? notificationList.currentItem.y : 0
                            width: notificationList.width
                            height: notificationList.currentItem ? notificationList.currentItem.height : 0
                            radius: 18
                            color: root.surfaceAlt
                            Behavior on y { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                        }

                        delegate: Item {
                            id: notificationGroup
                            required property int index
                            required property var modelData
                            readonly property bool expanded: root.expandedNotificationGroup === modelData.key
                            readonly property var groupEntries: modelData.entries || []
                            width: notificationList.width
                            height: 58 + (expanded ? groupEntries.length * 54 + 4 : 0)
                            clip: true

                            Rectangle {
                                anchors.fill: parent
                                radius: 18
                                color: notificationGroup.expanded ? root.surface : "transparent"
                                border.width: notificationGroup.expanded ? 1 : 0
                                border.color: theme.outline
                            }

                            RowLayout {
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.top: parent.top
                                height: 58
                                anchors.leftMargin: 10
                                anchors.rightMargin: 10
                                spacing: 10

                                Rectangle {
                                    Layout.preferredWidth: 36
                                    Layout.preferredHeight: 36
                                    radius: 18
                                    color: notificationGroup.modelData.urgency === 2
                                        ? Qt.tint(root.surfaceAlt, Qt.alpha(theme.critical, 0.22))
                                        : root.surfaceAlt

                                    Image {
                                        anchors.centerIn: parent
                                        width: 21
                                        height: 21
                                        source: Quickshell.iconPath(String(notificationGroup.modelData.appIcon), "preferences-system-notifications")
                                        fillMode: Image.PreserveAspectFit
                                    }
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 1

                                    Text {
                                        Layout.fillWidth: true
                                        text: notificationGroup.modelData.appName
                                        color: root.foreground
                                        elide: Text.ElideRight
                                        font.family: "Noto Sans"
                                        font.pixelSize: 13
                                        font.weight: Font.DemiBold
                                    }

                                    Text {
                                        Layout.fillWidth: true
                                        text: notificationGroup.modelData.latest
                                            ? root.notificationLine(notificationGroup.modelData.latest.summary)
                                                + (notificationGroup.modelData.latest.body
                                                    ? " · " + root.notificationLine(notificationGroup.modelData.latest.body) : "")
                                            : ""
                                        color: root.muted
                                        elide: Text.ElideRight
                                        font.family: "Noto Sans"
                                        font.pixelSize: 11
                                    }
                                }

                                Rectangle {
                                    Layout.preferredWidth: 38
                                    Layout.preferredHeight: 24
                                    radius: 12
                                    color: root.selected

                                    Row {
                                        anchors.centerIn: parent
                                        spacing: 3
                                        Text {
                                            text: notificationGroup.groupEntries.length.toString()
                                            color: root.foreground
                                            font.family: "Noto Sans"
                                            font.pixelSize: 10
                                            font.weight: Font.DemiBold
                                        }
                                        Text {
                                            text: "󰅀"
                                            rotation: notificationGroup.expanded ? 180 : 0
                                            color: root.muted
                                            font.family: "JetBrainsMono Nerd Font"
                                            font.pixelSize: 11
                                            Behavior on rotation { NumberAnimation { duration: 180 } }
                                        }
                                    }
                                }
                            }

                            MouseArea {
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.top: parent.top
                                height: 58
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onEntered: notificationList.currentIndex = notificationGroup.index
                                onClicked: root.toggleNotificationGroup(notificationGroup.index)
                            }

                            Column {
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.top: parent.top
                                anchors.topMargin: 58
                                anchors.leftMargin: 8
                                anchors.rightMargin: 8
                                spacing: 4
                                visible: notificationGroup.expanded

                                Repeater {
                                    model: notificationGroup.groupEntries

                                    delegate: Rectangle {
                                        id: nestedNotification
                                        required property var modelData
                                        width: parent.width
                                        height: 50
                                        radius: 13
                                        clip: true
                                        color: nestedMouse.containsMouse ? root.surfaceAlt : root.surface

                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.leftMargin: 12
                                            anchors.rightMargin: 9
                                            spacing: 10

                                            ColumnLayout {
                                                Layout.fillWidth: true
                                                spacing: 1
                                                Text {
                                                    Layout.fillWidth: true
                                                    text: root.notificationLine(nestedNotification.modelData.summary)
                                                    color: root.foreground
                                                    elide: Text.ElideRight
                                                    font.family: "Noto Sans"
                                                    font.pixelSize: 12
                                                    font.weight: Font.Medium
                                                }
                                                Text {
                                                    Layout.fillWidth: true
                                                    text: root.notificationLine(nestedNotification.modelData.body)
                                                        || "Без дополнительного текста"
                                                    color: root.muted
                                                    elide: Text.ElideRight
                                                    font.family: "Noto Sans"
                                                    font.pixelSize: 10
                                                }
                                            }
                                            Text {
                                                text: root.notificationAge(nestedNotification.modelData.createdAt)
                                                color: root.muted
                                                font.family: "Noto Sans"
                                                font.pixelSize: 9
                                            }
                                            Text {
                                                text: "󰅖"
                                                color: root.muted
                                                font.family: "JetBrainsMono Nerd Font"
                                                font.pixelSize: 12
                                                MouseArea {
                                                    id: nestedMouse
                                                    anchors.fill: parent
                                                    anchors.margins: -9
                                                    hoverEnabled: true
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: root.dismissNotification(nestedNotification.modelData.id)
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    ListView {
                        id: wallpaperCarousel

                        anchors.fill: parent
                        model: wallpaperModel
                        orientation: ListView.Horizontal
                        spacing: 6
                        clip: true
                        visible: root.wallpaperMode && count > 0
                        boundsBehavior: Flickable.StopAtBounds
                        keyNavigationWraps: true
                        highlightMoveDuration: 180
                        highlightRangeMode: ListView.StrictlyEnforceRange
                        preferredHighlightBegin: width / 2 - 100
                        preferredHighlightEnd: width / 2 + 100

                        WheelHandler {
                            target: null
                            onWheel: function(event) {
                                if (wallpaperCarousel.count === 0)
                                    return
                                const direction = event.angleDelta.y < 0 || event.angleDelta.x < 0 ? 1 : -1
                                wallpaperCarousel.currentIndex = (wallpaperCarousel.currentIndex
                                    + direction + wallpaperCarousel.count) % wallpaperCarousel.count
                                wallpaperCarousel.positionViewAtIndex(
                                    wallpaperCarousel.currentIndex, ListView.Center)
                                event.accepted = true
                            }
                        }

                        delegate: Item {
                            id: wallpaperCard
                            required property int index
                            required property string path
                            required property string preview
                            required property string name
                            required property string kind
                            required property string scheme
                            required property string accent

                            width: 200
                            height: wallpaperCarousel.height
                            scale: wallpaperCard.ListView.isCurrentItem ? 1 : 0.88
                            opacity: wallpaperCard.ListView.isCurrentItem ? 1 : 0.66
                            z: wallpaperCard.ListView.isCurrentItem ? 2 : 1

                            Behavior on scale {
                                NumberAnimation {
                                    duration: 500
                                    easing.type: Easing.BezierSpline
                                    easing.bezierCurve: [0.38, 1.21, 0.22, 1, 1, 1]
                                }
                            }
                            Behavior on opacity { NumberAnimation { duration: 200 } }

                            Rectangle {
                                id: wallpaperFrame
                                anchors.centerIn: parent
                                width: 192
                                height: 140
                                radius: 16
                                color: root.surface
                                border.width: wallpaperCard.ListView.isCurrentItem ? 2 : 1
                                border.color: wallpaperCard.ListView.isCurrentItem
                                    ? root.accent : theme.outline
                                clip: true
                                z: 2
                                layer.enabled: true
                                layer.effect: MultiEffect {
                                    maskEnabled: true
                                    maskSource: wallpaperRoundMask
                                }

                                Image {
                                    id: wallpaperImage
                                    anchors.top: parent.top
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    height: 108
                                    source: "file://" + encodeURI(wallpaperCard.preview)
                                    fillMode: Image.PreserveAspectCrop
                                    asynchronous: true
                                    cache: true
                                    sourceSize.width: 400
                                    sourceSize.height: 225
                                }

                                Rectangle {
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.bottom: parent.bottom
                                    height: 32
                                    color: root.surface
                                }

                                Text {
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.bottom: parent.bottom
                                    anchors.leftMargin: 9
                                    anchors.rightMargin: 9
                                    height: 32
                                    verticalAlignment: Text.AlignVCenter
                                    horizontalAlignment: Text.AlignHCenter
                                    text: root.wallpaperName(wallpaperCard.name)
                                    color: root.foreground
                                    elide: Text.ElideRight
                                    font.family: "Noto Sans"
                                    font.pixelSize: 11
                                }

                                Rectangle {
                                    visible: wallpaperCard.kind !== "image"
                                    anchors.top: parent.top
                                    anchors.right: parent.right
                                    anchors.margins: 7
                                    width: wallpaperType.implicitWidth + 12
                                    height: 21
                                    radius: 7
                                    color: root.background

                                    Text {
                                        id: wallpaperType
                                        anchors.centerIn: parent
                                        text: wallpaperCard.kind === "gif" ? "GIF" : "▶"
                                        color: root.accent
                                        font.family: "JetBrainsMono Nerd Font"
                                        font.pixelSize: 9
                                        font.weight: Font.Bold
                                    }
                                }

                                Rectangle {
                                    id: themeButton
                                    anchors.top: parent.top
                                    anchors.left: parent.left
                                    anchors.margins: 8
                                    width: 20
                                    height: 20
                                    radius: 10
                                    color: wallpaperCard.accent
                                    border.width: 2
                                    border.color: theme.foreground
                                    z: 5

                                    MouseArea {
                                        anchors.fill: parent
                                        anchors.margins: -5
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: function(mouse) {
                                            mouse.accepted = true
                                            Quickshell.execDetached([
                                                Quickshell.env("HOME") + "/.config/hypr/settings.sh",
                                                wallpaperCard.path
                                            ])
                                            root.closeLauncher()
                                        }
                                    }
                                }
                            }

                            Item {
                                id: wallpaperRoundMask
                                width: wallpaperFrame.width
                                height: wallpaperFrame.height
                                visible: false
                                layer.enabled: true

                                Rectangle {
                                    anchors.fill: parent
                                    radius: 16
                                    color: "white"
                                }
                            }

                            HoverHandler {
                                onHoveredChanged: {
                                    if (hovered)
                                        wallpaperCarousel.currentIndex = wallpaperCard.index
                                }
                            }

                            TapHandler {
                                acceptedButtons: Qt.LeftButton
                                cursorShape: Qt.PointingHandCursor
                                onTapped: {
                                    wallpaperCarousel.currentIndex = wallpaperCard.index
                                    root.activateWallpaper()
                                }
                            }
                        }
                    }

                    Column {
                        anchors.centerIn: parent
                        spacing: 4
                        visible: root.wallpaperMode
                            ? wallpaperModel.count === 0
                            : root.notificationsMode
                                ? root.notificationGroups.length === 0
                            : root.results.length === 0

                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: "󰍉"
                            color: root.muted
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 24
                        }

                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: root.wallpaperMode ? "Обои не найдены"
                                : root.notificationsMode ? "Нет уведомлений"
                                : "Ничего не найдено"
                            color: root.muted
                            font.family: "Noto Sans"
                            font.pixelSize: 14
                            font.weight: Font.Medium
                        }

                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: root.wallpaperMode
                                ? "Добавьте изображения в ~/Documents/Wallpapers"
                                : root.notificationsMode
                                    ? "Здесь пока всё спокойно"
                                : "Попробуйте другой запрос"
                            color: root.muted
                            opacity: 0.75
                            font.family: "Noto Sans"
                            font.pixelSize: 12
                        }
                    }
                }

                Rectangle {
                    id: searchBackground

                    anchors.left: parent.left
                    anchors.right: parent.right
                    height: root.minimum ? 44 : 48
                    y: root.minimum ? 0 : parent.height - height
                    z: 1
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

                    Text {
                        visible: root.minimum
                        anchors.left: parent.left
                        anchors.leftMargin: 12
                        anchors.verticalCenter: parent.verticalCenter
                        text: ">"
                        color: root.foreground
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 16
                        font.weight: Font.Bold
                    }

                    TextInput {
                        id: minimumSearchInput
                        visible: root.minimum
                        z: 3
                        anchors.left: parent.left
                        anchors.leftMargin: 34
                        anchors.right: parent.right
                        anchors.rightMargin: root.wallpaperMode ? 132 : 12
                        anchors.verticalCenter: parent.verticalCenter
                        height: parent.height
                        verticalAlignment: TextInput.AlignVCenter
                        color: "#ffffff"
                        selectionColor: root.selected
                        selectedTextColor: root.foreground
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 15
                        font.weight: Font.Bold
                        cursorDelegate: Rectangle { width: 2; color: root.accent }
                        onTextChanged: {
                            if (searchField.text !== text)
                                searchField.text = text
                        }
                        Keys.onDownPressed: function(event) {
                            if (root.wallpaperMode) {
                                root.showLiveWallpapers(false)
                                event.accepted = true
                                return
                            }
                            if (root.results.length > 0) {
                                resultList.currentIndex = (resultList.currentIndex + 1) % root.results.length
                                resultList.positionViewAtIndex(resultList.currentIndex, ListView.Contain)
                            }
                            event.accepted = true
                        }
                        Keys.onUpPressed: function(event) {
                            if (root.wallpaperMode) {
                                root.showLiveWallpapers(true)
                                event.accepted = true
                                return
                            }
                            if (root.results.length > 0) {
                                resultList.currentIndex = (resultList.currentIndex - 1 + root.results.length) % root.results.length
                                resultList.positionViewAtIndex(resultList.currentIndex, ListView.Contain)
                            }
                            event.accepted = true
                        }
                        Keys.onLeftPressed: function(event) {
                            if (!root.wallpaperMode || wallpaperModel.count === 0)
                                return
                            wallpaperCarousel.currentIndex = (wallpaperCarousel.currentIndex - 1
                                + wallpaperModel.count) % wallpaperModel.count
                            wallpaperCarousel.positionViewAtIndex(
                                wallpaperCarousel.currentIndex, ListView.Center)
                            event.accepted = true
                        }
                        Keys.onRightPressed: function(event) {
                            if (!root.wallpaperMode || wallpaperModel.count === 0)
                                return
                            wallpaperCarousel.currentIndex = (wallpaperCarousel.currentIndex + 1)
                                % wallpaperModel.count
                            wallpaperCarousel.positionViewAtIndex(
                                wallpaperCarousel.currentIndex, ListView.Center)
                            event.accepted = true
                        }
                        Keys.onReturnPressed: function(event) {
                            if (root.wallpaperMode)
                                root.activateWallpaper()
                            else
                                root.activate(resultList.currentIndex)
                            event.accepted = true
                        }
                        Keys.onEnterPressed: function(event) {
                            if (root.wallpaperMode)
                                root.activateWallpaper()
                            else
                                root.activate(resultList.currentIndex)
                            event.accepted = true
                        }
                    }

                    Text {
                        visible: root.minimum && minimumSearchInput.text.length === 0
                        z: 2
                        anchors.left: parent.left
                        anchors.leftMargin: 34
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Search applications..."
                        color: theme.foregroundSoft
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 13
                    }

                    Connections {
                        target: searchField
                        function onTextChanged() {
                            if (minimumSearchInput.text !== searchField.text)
                                minimumSearchInput.text = searchField.text
                        }
                    }

                    RowLayout {
                        visible: !root.minimum
                        anchors.fill: parent
                        anchors.leftMargin: root.minimum ? 12 : 16
                        anchors.rightMargin: root.wallpaperMode ? 132 : 12
                        spacing: root.minimum ? 9 : 12

                        Text {
                            text: root.minimum ? ">" : "󰍉"
                            color: root.minimum ? root.foreground : root.foreground
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: root.minimum ? 16 : 17
                            font.weight: root.minimum ? Font.Bold : Font.Normal
                        }

                        Item {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            Layout.minimumHeight: root.minimum ? searchBackground.height : 0
                            Layout.alignment: Qt.AlignVCenter

                            Text {
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                text: root.minimum ? "search applications..."
                                    : root.wallpaperMode ? "поиск обоев…"
                                    : root.notificationsMode ? "поиск уведомлений…"
                                    : "Введите «!» для команд"
                                color: root.minimum ? theme.foregroundSoft : root.muted
                                opacity: searchField.text.length === 0 ? 1 : 0
                                font.family: root.minimum ? "JetBrainsMono Nerd Font" : "Noto Sans"
                                font.pixelSize: root.minimum ? 13 : 14

                                Behavior on opacity {
                                    NumberAnimation {
                                        duration: 200
                                        easing.type: Easing.BezierSpline
                                        easing.bezierCurve: [0.34, 0.8, 0.34, 1, 1, 1]
                                    }
                                }
                            }

                            TextInput {
                                id: searchField

                                anchors.fill: parent
                                z: 2
                                verticalAlignment: TextInput.AlignVCenter
                                color: root.minimum ? "#ffffff" : root.foreground
                                opacity: 1
                                selectionColor: root.selected
                                selectedTextColor: root.foreground
                                font.family: root.minimum ? "JetBrainsMono Nerd Font" : "Noto Sans"
                                font.pixelSize: root.minimum ? 15 : 14
                                font.weight: root.minimum ? Font.Bold : Font.Normal
                                cursorDelegate: Rectangle {
                                    width: 2
                                    color: root.accent
                                    opacity: searchField.activeFocus ? 1 : 0
                                }

                                onTextChanged: {
                                    root.keyboardNavigating = false
                                    root.refreshResults(false)
                                }

                                Keys.onDownPressed: function(event) {
                                    root.keyboardNavigating = true
                                    if (root.wallpaperMode) {
                                        root.showLiveWallpapers(false)
                                    } else if (root.notificationsMode && root.notificationGroups.length > 0) {
                                        notificationList.currentIndex = (notificationList.currentIndex + 1) % root.notificationGroups.length
                                        notificationList.positionViewAtIndex(notificationList.currentIndex, ListView.Contain)
                                    } else if (!root.wallpaperMode && root.results.length > 0) {
                                        resultList.currentIndex = (resultList.currentIndex + 1) % root.results.length
                                        resultList.positionViewAtIndex(resultList.currentIndex, ListView.Contain)
                                    }
                                    event.accepted = true
                                }
                                Keys.onUpPressed: function(event) {
                                    root.keyboardNavigating = true
                                    if (root.wallpaperMode) {
                                        root.showLiveWallpapers(true)
                                    } else if (root.notificationsMode && root.notificationGroups.length > 0) {
                                        notificationList.currentIndex = (notificationList.currentIndex - 1 + root.notificationGroups.length) % root.notificationGroups.length
                                        notificationList.positionViewAtIndex(notificationList.currentIndex, ListView.Contain)
                                    } else if (!root.wallpaperMode && root.results.length > 0) {
                                        resultList.currentIndex = (resultList.currentIndex - 1 + root.results.length) % root.results.length
                                        resultList.positionViewAtIndex(resultList.currentIndex, ListView.Contain)
                                    }
                                    event.accepted = true
                                }
                                Keys.onRightPressed: function(event) {
                                    if (root.wallpaperMode && wallpaperModel.count > 0) {
                                        wallpaperCarousel.currentIndex = (wallpaperCarousel.currentIndex + 1) % wallpaperModel.count
                                        wallpaperCarousel.positionViewAtIndex(wallpaperCarousel.currentIndex, ListView.Center)
                                        event.accepted = true
                                    }
                                }
                                Keys.onLeftPressed: function(event) {
                                    if (root.wallpaperMode && wallpaperModel.count > 0) {
                                        wallpaperCarousel.currentIndex = (wallpaperCarousel.currentIndex - 1 + wallpaperModel.count) % wallpaperModel.count
                                        wallpaperCarousel.positionViewAtIndex(wallpaperCarousel.currentIndex, ListView.Center)
                                        event.accepted = true
                                    }
                                }
                                Keys.onReturnPressed: function(event) {
                                    if (root.wallpaperMode)
                                        root.activateWallpaper()
                                    else if (root.notificationsMode)
                                        root.submitNotificationInput()
                                    else
                                        root.activate(resultList.currentIndex)
                                    event.accepted = true
                                }
                                Keys.onEnterPressed: function(event) {
                                    if (root.wallpaperMode)
                                        root.activateWallpaper()
                                    else if (root.notificationsMode)
                                        root.submitNotificationInput()
                                    else
                                        root.activate(resultList.currentIndex)
                                    event.accepted = true
                                }
                            }

                        }

                        Text {
                            visible: !root.minimum
                            text: "󰅖"
                            color: root.foreground
                            opacity: searchField.text.length > 0 ? 1 : 0
                            enabled: opacity > 0
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 17

                            Behavior on opacity {
                                NumberAnimation {
                                    duration: 200
                                    easing.type: Easing.BezierSpline
                                    easing.bezierCurve: [0.34, 0.8, 0.34, 1, 1, 1]
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                anchors.margins: -10
                                cursorShape: Qt.PointingHandCursor
                                enabled: parent.enabled
                                onClicked: searchField.clear()
                            }
                        }

                        Rectangle {
                            id: clearNotificationsButton
                            visible: root.notificationsMode && root.notificationGroups.length > 0
                            Layout.preferredWidth: 92
                            Layout.preferredHeight: 32
                            radius: 16
                            color: clearNotificationsMouse.containsMouse
                                ? Qt.lighter(theme.critical, 1.08)
                                : theme.critical
                            border.width: 1
                            border.color: clearNotificationsMouse.containsMouse
                                ? Qt.lighter(theme.critical, 1.25)
                                : Qt.darker(theme.critical, 1.2)

                            Behavior on color { ColorAnimation { duration: 120 } }

                            Row {
                                anchors.centerIn: parent
                                spacing: 7

                                Text {
                                    text: "󰆴"
                                    color: root.foreground
                                    font.family: "JetBrainsMono Nerd Font"
                                    font.pixelSize: 14
                                }

                                Text {
                                    text: "Очистить"
                                    color: root.foreground
                                    font.family: "Noto Sans"
                                    font.pixelSize: 11
                                    font.weight: Font.DemiBold
                                }
                            }

                            MouseArea {
                                id: clearNotificationsMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.clearNotifications()
                            }
                        }
                    }

                    Rectangle {
                        id: wallpaperSortButton
                        visible: root.wallpaperMode
                        z: 8
                        anchors.right: parent.right
                        anchors.rightMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        width: 116
                        height: parent.height - 12
                        radius: root.minimum ? 2 : height / 2
                        color: wallpaperSortMouse.containsMouse ? root.selected : root.surface
                        border.width: 1
                        border.color: wallpaperSortMouse.containsMouse ? root.accent : theme.outline

                        Text {
                            anchors.centerIn: parent
                            text: "󰒺  " + root.wallpaperSortLabel
                            color: root.foreground
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 10
                            font.weight: Font.DemiBold
                        }

                        MouseArea {
                            id: wallpaperSortMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.cycleWallpaperSort()
                        }
                    }
                }
            }
        }
    }
}
