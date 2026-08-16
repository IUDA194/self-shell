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
        { name: "Система", description: "Сеанс и питание", keywords: "system power session система питание сеанс", category: "Система", icon: "system-shutdown", symbol: "", mode: "system", command: "" }
    ]
    readonly property var customApplications: [
        { id: "local-telegram", name: "Telegram", description: "Мессенджер", keywords: "telegram телеграм messenger мессенджер", icon: "telegram", command: Quickshell.env("HOME") + "/Apps/Telegram" }
    ]
    readonly property var systemActions: [
        { name: "Заблокировать", description: "Заблокировать текущий сеанс", category: "Сеанс", icon: "system-lock-screen", symbol: "", command: "hyprlock" },
        { name: "Выйти", description: "Завершить сеанс Hyprland", category: "Сеанс", icon: "system-log-out", symbol: "󰗼", command: "hyprctl dispatch exit" },
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
        const query = searchField.text.replace(/^!wallpaper\s*/i, "").trim().toLowerCase()
        const previous = wallpaperCarousel.currentIndex >= 0
            && wallpaperCarousel.currentIndex < wallpaperModel.count
            ? wallpaperModel.get(wallpaperCarousel.currentIndex).path : currentWallpaper
        wallpaperModel.clear()
        for (let i = 0; i < wallpapers.length; ++i) {
            const wall = wallpapers[i]
            if (!query || wallpaperName(wall.name).toLowerCase().indexOf(query) >= 0)
                wallpaperModel.append(wall)
        }
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
        systemMode = false
        notificationsMode = false
        searchField.text = "!wallpaper "
        refreshWallpapers()
        wallpaperPrepareProcess.running = true
        Qt.callLater(function() {
            searchField.forceActiveFocus()
        })
    }

    function enterSystemMode() {
        wallpaperMode = false
        systemMode = true
        notificationsMode = false
        searchField.text = "!system "
        refreshResults(false)
        Qt.callLater(function() {
            searchField.forceActiveFocus()
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
            searchField.forceActiveFocus()
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
            searchField.forceActiveFocus()
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
        interval: 270
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
            duration: 260
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
                : Math.min(7, root.results.length)
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
                ? visibleRows * (root.notificationsMode ? 78 : 57) + Math.max(0, visibleRows - 1) * 8
                : root.wallpaperMode ? 166
                    : root.notificationsMode ? notificationContentHeight
                    : 96
            readonly property real contentHeight: listContentHeight + 48 + 16 + 16 + 12
            readonly property real expandedHeight: Math.min(parent.height - 48, contentHeight)
            property real animatedHeight: expandedHeight

            onExpandedHeightChanged: animatedHeight = expandedHeight

            Behavior on animatedHeight {
                enabled: root.windowShown && !root.closing && root.revealProgress > 0.98
                NumberAnimation {
                    duration: 320
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: [0.38, 1.21, 0.22, 1, 1, 1]
                }
            }

            anchors.bottom: parent.bottom
            anchors.bottomMargin: 0
            anchors.horizontalCenter: parent.horizontalCenter
            // Integer logical coordinate avoids half-pixel sampling at 1.25 scale.
            anchors.horizontalCenterOffset: 28

            width: Math.min(parent.width - 48, root.wallpaperMode ? 1050 : 632)
            height: animatedHeight * root.revealProgress
            radius: Math.min(28, height / 2)
            color: root.background
            border.width: 1
            border.color: theme.outline
            opacity: 1
            clip: true

            Behavior on width {
                enabled: !root.closing
                NumberAnimation {
                    duration: 500
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: [0.38, 1.21, 0.22, 1, 1, 1]
                }
            }

            // Continue the panel through the screen edge while preserving the
            // one-pixel side borders all the way down.
            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.leftMargin: launcherPanel.border.width
                anchors.rightMargin: launcherPanel.border.width
                height: launcherPanel.radius
                color: parent.color
            }

            Rectangle {
                anchors.left: parent.left
                anchors.bottom: parent.bottom
                width: launcherPanel.border.width
                height: launcherPanel.radius
                color: launcherPanel.border.color
            }

            Rectangle {
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
                anchors.leftMargin: 16
                anchors.rightMargin: 16
                anchors.topMargin: 16
                anchors.bottomMargin: 12

                Item {
                    id: listArea

                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: searchBackground.top
                    anchors.bottomMargin: 16
                    clip: true

                    ListView {
                        id: resultList

                        anchors.fill: parent
                        model: root.results
                        currentIndex: root.results.length > 0 ? 0 : -1
                        spacing: 8
                        clip: true
                        visible: !root.wallpaperMode && !root.notificationsMode && count > 0
                        boundsBehavior: Flickable.StopAtBounds
                        keyNavigationWraps: true
                        highlightFollowsCurrentItem: false

                        displaced: Transition {
                            NumberAnimation {
                                property: "y"
                                duration: 220
                                easing.type: Easing.OutCubic
                            }
                        }

                        highlight: Rectangle {
                            y: resultList.currentItem ? resultList.currentItem.y : 0
                            width: resultList.width
                            height: resultList.currentItem ? resultList.currentItem.height : 0
                            radius: 16
                            color: root.surfaceAlt

                            Behavior on y {
                                NumberAnimation {
                                    duration: 500
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
                                duration: 200
                                easing.type: Easing.BezierSpline
                                easing.bezierCurve: [0.34, 0.8, 0.34, 1, 1, 1]
                            }
                        }

                        remove: Transition {
                            NumberAnimation {
                                property: "opacity"
                                from: 1
                                to: 0
                                duration: 200
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
                            height: 57

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 12
                                anchors.rightMargin: 12
                                anchors.topMargin: 8
                                anchors.bottomMargin: 8
                                spacing: 12

                                Image {
                                    Layout.preferredWidth: 32
                                    Layout.preferredHeight: 32
                                    source: Quickshell.iconPath(
                                        String(resultRow.modelData.icon), "image-missing")
                                    sourceSize.width: 64
                                    sourceSize.height: 64
                                    fillMode: Image.PreserveAspectFit
                                    smooth: true
                                    mipmap: true
                                    asynchronous: false
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 0

                                    Text {
                                        Layout.fillWidth: true
                                        text: resultRow.modelData.name
                                        color: root.foreground
                                        elide: Text.ElideRight
                                        font.family: "Noto Sans"
                                        font.pixelSize: 14
                                        font.weight: Font.Medium
                                    }

                                    Text {
                                        Layout.fillWidth: true
                                        text: resultRow.modelData.description
                                        color: root.muted
                                        elide: Text.ElideRight
                                        font.family: "Noto Sans"
                                        font.pixelSize: 12
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

                            MouseArea {
                                anchors.fill: parent
                                z: 1
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onEntered: wallpaperCarousel.currentIndex = wallpaperCard.index
                                onClicked: {
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
                    anchors.bottom: parent.bottom
                    height: 48
                    z: 1
                    radius: 24
                    color: root.surfaceAlt

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 16
                        anchors.rightMargin: 12
                        spacing: 12

                        Text {
                            text: "󰍉"
                            color: root.foreground
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 17
                        }

                        Item {
                            Layout.fillWidth: true
                            Layout.fillHeight: true

                            Text {
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                text: root.wallpaperMode ? "поиск обоев…"
                                    : root.notificationsMode ? "поиск уведомлений…"
                                    : "Введите «!» для команд"
                                color: root.muted
                                opacity: searchField.text.length === 0 ? 1 : 0
                                font.family: "Noto Sans"
                                font.pixelSize: 14

                                Behavior on opacity {
                                    NumberAnimation {
                                        duration: 200
                                        easing.type: Easing.BezierSpline
                                        easing.bezierCurve: [0.34, 0.8, 0.34, 1, 1, 1]
                                    }
                                }
                            }

                            TextField {
                                id: searchField

                                anchors.fill: parent
                                leftPadding: 0
                                rightPadding: 0
                                color: root.foreground
                                placeholderText: ""
                                selectionColor: root.selected
                                selectedTextColor: root.foreground
                                font.family: "Noto Sans"
                                font.pixelSize: 14
                                background: null

                                onTextChanged: {
                                    root.keyboardNavigating = false
                                    root.refreshResults(false)
                                }

                                Keys.onDownPressed: function(event) {
                                    root.keyboardNavigating = true
                                    if (root.notificationsMode && root.notificationGroups.length > 0) {
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
                                    if (root.notificationsMode && root.notificationGroups.length > 0) {
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
                }
            }
        }
    }
}
