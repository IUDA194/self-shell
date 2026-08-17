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

    property bool shown: false
    property bool closing: false
    property real revealProgress: 0
    property string requestedWallpaper: ""
    property string currentWallpaper: ""
    property var wallpapers: []
    property int selectedIndex: -1
    property int activeTab: 0
    property string systemTimezone: "Europe/Berlin"
    property bool systemNtp: false
    property bool systemSynchronized: false
    property string systemStatus: ""
    property var timezoneOptions: ["UTC"]
    property string updateMode: "off"
    property int updateDays: 7
    property string updateStatus: ""
    readonly property var schemes: [
        { id: "auto", name: "Автоматически", description: "Цвета из обоев", accent: selectedWallpaper() ? selectedWallpaper().accent : theme.accent,
          colors: [theme.background, theme.surfaceAlt, selectedWallpaper() ? selectedWallpaper().accent : theme.accent] },
        { id: "default", name: "Default", description: "Тёплая исходная", accent: "#b58e66", colors: ["#26201d", "#4f443e", "#b58e66"] },
        { id: "kanagawa", name: "Kanagawa", description: "Японская ночь", accent: "#c0a36e", colors: ["#1f1f28", "#54546d", "#c0a36e"] },
        { id: "gruvbox", name: "Gruvbox", description: "Тёплая ретро", accent: "#d79921", colors: ["#282828", "#504945", "#d79921"] },
        { id: "nord", name: "Nord", description: "Холодный север", accent: "#88c0d0", colors: ["#2e3440", "#434c5e", "#88c0d0"] }
    ]
    readonly property var textThemes: [
        { id: "obsidian", name: "Obsidian", description: "Текущая · по умолчанию", colors: ["#ccc2b7", "#ba945f", "#9f7d52"] },
        { id: "auto", name: "Автоматически", description: "Цвета из обоев", colors: [theme.foreground, theme.accent, theme.success] },
        { id: "kanagawa", name: "Kanagawa", description: "Мягкая японская", colors: ["#f2ecce", "#e6c384", "#98bb6c"] },
        { id: "gruvbox", name: "Gruvbox", description: "Тёплая ретро", colors: ["#fbf1c7", "#fabd2f", "#b8bb26"] },
        { id: "nord", name: "Nord", description: "Холодная северная", colors: ["#ffffff", "#8fdaec", "#b8d49c"] }
    ]

    function fileUrl(path) { return "file://" + encodeURI(path) }
    function displayName(name) { return name.replace(/\.[^.]+$/, "").replace(/[-_]+/g, " ") }
    function selectedWallpaper() {
        if (selectedIndex < 0 || selectedIndex >= wallpaperModel.count)
            return null
        return wallpaperModel.get(selectedIndex)
    }
    function selectWallpaper(path) {
        let next = wallpaperModel.count > 0 ? 0 : -1
        for (let i = 0; i < wallpaperModel.count; ++i) {
            if (wallpaperModel.get(i).path === path) { next = i; break }
        }
        selectedIndex = next
    }
    function loadWallpapers() {
        const selected = selectedWallpaper()
        const preservedPath = requestedWallpaper
            || (selected ? selected.path : "")
            || currentWallpaper
        try {
            wallpapers = JSON.parse(manifestFile.text())
        } catch (error) {
            wallpapers = []
        }
        wallpaperModel.clear()
        for (let i = 0; i < wallpapers.length; ++i)
            wallpaperModel.append(wallpapers[i])
        selectWallpaper(preservedPath)
    }
    function openFor(path) {
        requestedWallpaper = path || ""
        closing = false
        shown = true
        revealProgress = 0
        prepareProcess.running = true
        refreshSystemState()
        timezoneListProcess.running = true
        updateStatusProcess.running = true
        Qt.callLater(function() { revealProgress = 1 })
    }
    function close() {
        if (closing) return
        closing = true
        revealProgress = 0
        closeTimer.restart()
    }
    function chooseScheme(id) {
        const wall = selectedWallpaper()
        if (!wall || themeProcess.running) return
        requestedWallpaper = wall.path
        themeProcess.exec([Quickshell.env("HOME") + "/.config/hypr/rofi-wallpapers.sh", "--set-theme", wall.path, id])
    }
    function chooseTextTheme(id) {
        const wall = selectedWallpaper()
        if (!wall || textThemeProcess.running) return
        requestedWallpaper = wall.path
        textThemeProcess.exec([
            Quickshell.env("HOME") + "/.config/hypr/rofi-wallpapers.sh",
            "--set-text-theme", wall.path, id
        ])
    }
    function applySelected() {
        const wall = selectedWallpaper()
        if (!wall || applyProcess.running) return
        applyProcess.exec([Quickshell.env("HOME") + "/.config/hypr/rofi-wallpapers.sh", "--apply", wall.path])
    }
    function refreshSystemState() { systemStatusProcess.running = true }
    function runSystemAction(action, value) {
        if (systemActionProcess.running) return
        systemStatus = "Применение…"
        systemActionProcess.exec([
            Quickshell.env("HOME") + "/.config/hypr/settings-system.sh",
            action, value
        ])
    }
    function loadUpdateState(raw) {
        try {
            const state = JSON.parse(raw)
            updateMode = state.mode || "off"
            updateDays = Number(state.days || 7)
            updateStatus = state.message || ""
        } catch (error) {
            updateStatus = "Не удалось прочитать настройки обновлений"
        }
    }
    function configureUpdates(mode, days) {
        updateConfigureProcess.exec([
            Quickshell.env("HOME") + "/.config/hypr/self-shell-update.sh",
            "configure", mode, String(days)
        ])
    }

    FileView {
        id: manifestFile
        path: Quickshell.env("HOME") + "/.cache/hypr-wallpapers/manifest.json"
        blockLoading: true
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: root.loadWallpapers()
    }
    FileView {
        id: waypaperFile
        path: Quickshell.env("HOME") + "/.config/waypaper/config.ini"
        blockLoading: true
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            const match = text().match(/^wallpaper\s*=\s*(.+)$/m)
            if (match) root.currentWallpaper = match[1].trim().replace(/^~/, Quickshell.env("HOME"))
        }
    }
    ListModel { id: wallpaperModel }
    Process {
        id: prepareProcess
        command: [Quickshell.env("HOME") + "/.config/hypr/rofi-wallpapers.sh", "--prepare"]
        onExited: { manifestFile.reload(); root.loadWallpapers() }
    }
    Process {
        id: themeProcess
        onExited: { manifestFile.reload(); root.loadWallpapers() }
    }
    Process {
        id: textThemeProcess
        onExited: { manifestFile.reload(); root.loadWallpapers() }
    }
    Process {
        id: applyProcess
        onExited: if (exitCode === 0) { waypaperFile.reload(); root.currentWallpaper = root.selectedWallpaper().path }
    }
    Process {
        id: systemStatusProcess
        command: [Quickshell.env("HOME") + "/.config/hypr/settings-system.sh", "status"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const state = JSON.parse(text)
                    root.systemTimezone = state.timezone || "UTC"
                    root.systemNtp = Boolean(state.ntp)
                    root.systemSynchronized = Boolean(state.synchronized)
                    root.systemStatus = ""
                } catch (error) {
                    root.systemStatus = "Не удалось получить состояние времени"
                }
            }
        }
    }
    Process {
        id: timezoneListProcess
        command: [Quickshell.env("HOME") + "/.config/hypr/settings-system.sh", "list-timezones"]
        stdout: StdioCollector {
            onStreamFinished: {
                const zones = text.trim().split("\n").filter(zone => zone.length > 0)
                if (zones.length > 0) root.timezoneOptions = zones
            }
        }
    }
    Process {
        id: systemActionProcess
        onExited: function(exitCode, exitStatus) {
            root.systemStatus = exitCode === 0 ? "Готово" : "Изменение отменено или завершилось ошибкой"
            root.refreshSystemState()
        }
    }
    Process {
        id: updateStatusProcess
        command: [Quickshell.env("HOME") + "/.config/hypr/self-shell-update.sh", "status"]
        stdout: StdioCollector { onStreamFinished: root.loadUpdateState(text) }
    }
    Process {
        id: updateConfigureProcess
        stdout: StdioCollector { onStreamFinished: root.loadUpdateState(text) }
    }
    Process {
        id: updateCheckProcess
        onExited: updateStatusProcess.running = true
    }
    Timer { id: closeTimer; interval: 240; onTriggered: root.shown = false }

    IpcHandler {
        target: "settings"
        function open(): void { root.openFor("") }
        function appearance(path: string): void { root.openFor(path) }
        function close(): void { root.close() }
        function toggle(): void { root.shown ? root.close() : root.openFor("") }
    }

    Variants {
        model: Quickshell.screens
        PanelWindow {
            required property var modelData
            screen: modelData
            visible: root.shown && modelData === (Hyprland.focusedMonitor
                ? Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor.name)
                : Quickshell.screens[0])
            anchors { top: true; right: true; bottom: true; left: true }
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
            WlrLayershell.namespace: "self-shell-settings"

            FocusScope {
                anchors.fill: parent
                focus: true
                Keys.onEscapePressed: root.close()

                Rectangle { anchors.fill: parent; color: theme.scrim; opacity: root.revealProgress
                    MouseArea { anchors.fill: parent; onClicked: root.close() }
                }

                Rectangle {
                    id: dialog
                    anchors.centerIn: parent
                    width: Math.min(parent.width - 80, 920)
                    height: Math.min(parent.height - 80, 790)
                    radius: 26
                    color: theme.background
                    border.width: 1
                    border.color: theme.outline
                    opacity: root.revealProgress
                    scale: 0.94 + root.revealProgress * 0.06
                    Behavior on opacity { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }
                    Behavior on scale { NumberAnimation { duration: 320; easing.type: Easing.OutBack } }
                    MouseArea { anchors.fill: parent }

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 22
                        spacing: 18

                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            spacing: 18

                            RowLayout {
                                Layout.fillWidth: true
                                Text { text: "Настройки"; color: theme.foreground; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 22; font.weight: Font.Bold }
                                Item { Layout.fillWidth: true }
                                Rectangle { width: 34; height: 34; radius: 10; color: closeMouse.containsMouse ? theme.surfaceAlt : theme.surface
                                    Text { anchors.centerIn: parent; text: "󰅖"; color: theme.foreground; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 16 }
                                    MouseArea { id: closeMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.close() }
                                }
                            }

                            StackLayout {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                currentIndex: root.activeTab

                                ScrollView {
                                    id: appearanceScroll
                                    clip: true
                                    contentWidth: availableWidth
                                    ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
                                    ScrollBar.vertical.policy: ScrollBar.AsNeeded
                                    ScrollBar.vertical.contentItem: Rectangle {
                                        implicitWidth: 4
                                        radius: 2
                                        color: theme.accent
                                        opacity: appearanceScroll.ScrollBar.vertical.active ? 0.9 : 0.35
                                        Behavior on opacity { NumberAnimation { duration: 160 } }
                                    }

                                    ColumnLayout {
                                        width: appearanceScroll.availableWidth - 12
                                        spacing: 18

                            Text { text: "Обои"; color: theme.foreground; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 15; font.weight: Font.DemiBold }
                            ListView {
                                id: wallpaperList
                                Layout.fillWidth: true
                                Layout.preferredHeight: 154
                                model: wallpaperModel
                                currentIndex: root.selectedIndex
                                orientation: ListView.Horizontal
                                spacing: 10
                                clip: true
                                delegate: Rectangle {
                                    id: wallCard
                                    required property int index
                                    required property string path
                                    required property string preview
                                    required property string name
                                    required property string scheme
                                    required property string textTheme
                                    width: 180; height: 142; radius: 16; clip: true
                                    readonly property bool selected: wallCard.index === root.selectedIndex
                                    scale: selected ? 1 : 0.94
                                    opacity: selected ? 1 : 0.62
                                    color: theme.surface
                                    border.width: selected ? 3 : 1
                                    border.color: selected ? theme.accent : theme.outline
                                    Behavior on scale { NumberAnimation { duration: 220; easing.type: Easing.OutBack } }
                                    Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                                    Behavior on border.color { ColorAnimation { duration: 180 } }
                                    Image { anchors.fill: parent; source: root.fileUrl(wallCard.preview); fillMode: Image.PreserveAspectCrop; asynchronous: true }
                                    Rectangle {
                                        anchors.fill: parent
                                        color: "transparent"
                                        border.width: wallCard.selected ? 2 : 0
                                        border.color: theme.accentHover
                                        radius: parent.radius
                                    }
                                    Rectangle { anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom; height: 34; color: theme.overlayStrong }
                                    Text { anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom; height: 34; anchors.margins: 8; verticalAlignment: Text.AlignVCenter; text: root.displayName(wallCard.name); color: theme.foreground; elide: Text.ElideRight; font.family: "Noto Sans"; font.pixelSize: 11 }
                                    Rectangle {
                                        visible: wallCard.selected
                                        anchors.top: parent.top
                                        anchors.right: parent.right
                                        anchors.margins: 8
                                        width: 30
                                        height: 30
                                        radius: 10
                                        color: theme.accent
                                        border.width: 1
                                        border.color: theme.accentHover
                                        Text {
                                            anchors.centerIn: parent
                                            text: "󰏘"
                                            color: theme.accentForeground
                                            font.family: "JetBrainsMono Nerd Font"
                                            font.pixelSize: 15
                                        }
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            root.selectedIndex = wallCard.index
                                            root.requestedWallpaper = wallCard.path
                                        }
                                    }
                                }
                            }

                            RowLayout { Layout.fillWidth: true
                                Text { text: "Цветовая схема"; color: theme.foreground; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 15; font.weight: Font.DemiBold }
                                Item { Layout.fillWidth: true }
                                Text { text: root.selectedWallpaper() ? root.displayName(root.selectedWallpaper().name) : ""; color: theme.muted; font.family: "Noto Sans"; font.pixelSize: 11 }
                            }

                            GridLayout {
                                Layout.fillWidth: true
                                columns: 3
                                rowSpacing: 10
                                columnSpacing: 10
                                Repeater {
                                    model: root.schemes
                                    Rectangle {
                                        id: schemeCard
                                        required property var modelData
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: 88
                                        radius: 16
                                        color: schemeMouse.containsMouse ? theme.hover : theme.surface
                                        border.width: root.selectedWallpaper() && root.selectedWallpaper().scheme === modelData.id ? 2 : 1
                                        border.color: root.selectedWallpaper() && root.selectedWallpaper().scheme === modelData.id ? theme.accent : theme.outline
                                        RowLayout { anchors.fill: parent; anchors.margins: 13; spacing: 12
                                            Row { spacing: -7
                                                Repeater { model: schemeCard.modelData.colors
                                                    Rectangle { required property var modelData; width: 25; height: 43; radius: 9; color: modelData; border.width: 1; border.color: theme.outline }
                                                }
                                            }
                                            ColumnLayout { Layout.fillWidth: true; spacing: 2
                                                Text { text: schemeCard.modelData.name; color: theme.foreground; font.family: "Noto Sans"; font.pixelSize: 12; font.weight: Font.DemiBold }
                                                Text { text: schemeCard.modelData.description; color: theme.muted; font.family: "Noto Sans"; font.pixelSize: 9 }
                                            }
                                        }
                                        MouseArea { id: schemeMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.chooseScheme(schemeCard.modelData.id) }
                                    }
                                }
                            }

                            RowLayout { Layout.fillWidth: true
                                Text { text: "Тема текста"; color: theme.foreground; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 15; font.weight: Font.DemiBold }
                                Item { Layout.fillWidth: true }
                                Text { text: "Fish · Vim"; color: theme.muted; font.family: "Noto Sans"; font.pixelSize: 10 }
                            }

                            GridLayout {
                                Layout.fillWidth: true
                                columns: 3
                                rowSpacing: 10
                                columnSpacing: 10
                                Repeater {
                                    model: root.textThemes
                                    Rectangle {
                                        id: textThemeCard
                                        required property var modelData
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: 76
                                        radius: 16
                                        color: textThemeMouse.containsMouse ? theme.hover : theme.surface
                                        border.width: root.selectedWallpaper() && root.selectedWallpaper().textTheme === modelData.id ? 2 : 1
                                        border.color: root.selectedWallpaper() && root.selectedWallpaper().textTheme === modelData.id ? theme.accent : theme.outline
                                        RowLayout { anchors.fill: parent; anchors.margins: 13; spacing: 12
                                            Row { spacing: -7
                                                Repeater { model: textThemeCard.modelData.colors
                                                    Rectangle { required property var modelData; width: 25; height: 39; radius: 9; color: modelData; border.width: 1; border.color: theme.outline }
                                                }
                                            }
                                            ColumnLayout { Layout.fillWidth: true; spacing: 2
                                                Text { text: textThemeCard.modelData.name; color: theme.foreground; font.family: "Noto Sans"; font.pixelSize: 12; font.weight: Font.DemiBold }
                                                Text { text: textThemeCard.modelData.description; color: theme.muted; font.family: "Noto Sans"; font.pixelSize: 9 }
                                            }
                                        }
                                        MouseArea { id: textThemeMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.chooseTextTheme(textThemeCard.modelData.id) }
                                    }
                                }
                            }

                            Item { Layout.fillHeight: true }
                            RowLayout { Layout.fillWidth: true
                                Text { text: root.currentWallpaper === (root.selectedWallpaper() ? root.selectedWallpaper().path : "") ? "󰄬  Активные обои" : ""; color: theme.success; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 10 }
                                Item { Layout.fillWidth: true }
                                Rectangle { width: 168; height: 42; radius: 13; color: applyMouse.containsMouse ? theme.accentHover : theme.accent
                                    Text { anchors.centerIn: parent; text: "Применить"; color: theme.accentForeground; font.family: "Noto Sans"; font.pixelSize: 12; font.weight: Font.Bold }
                                    MouseArea { id: applyMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.applySelected() }
                                }
                            }
                                    Item { Layout.preferredHeight: 4 }
                                    }
                                }

                                ColumnLayout {
                                    spacing: 18

                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 14

                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: 3
                                            Text {
                                                text: "Интерфейс системы"
                                                color: theme.foreground
                                                font.family: "Noto Sans"
                                                font.pixelSize: 11
                                                font.weight: Font.DemiBold
                                            }
                                            Text {
                                                text: "Перезапустить оболочку и обновить все данные"
                                                color: theme.muted
                                                font.family: "Noto Sans"
                                                font.pixelSize: 9
                                            }
                                        }

                                        Rectangle {
                                            width: 148
                                            height: 38
                                            radius: 12
                                            color: hardReloadMouse.containsMouse ? theme.accentHover : theme.accent
                                            Text {
                                                anchors.centerIn: parent
                                                text: "󰑐  Hard reload"
                                                color: theme.accentForeground
                                                font.family: "JetBrainsMono Nerd Font"
                                                font.pixelSize: 10
                                                font.weight: Font.Bold
                                            }
                                            MouseArea {
                                                id: hardReloadMouse
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: root.runSystemAction("hard-reload", "")
                                            }
                                        }
                                    }

                                    Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: theme.outline }

                                    Text {
                                        text: "Часовой пояс"
                                        color: theme.foreground
                                        font.family: "Noto Sans"
                                        font.pixelSize: 11
                                        font.weight: Font.DemiBold
                                    }

                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 12

                                        ComboBox {
                                            id: timezonePicker
                                            Layout.fillWidth: true
                                            Layout.preferredHeight: 48
                                            model: root.timezoneOptions
                                            editable: false
                                            currentIndex: Math.max(0, root.timezoneOptions.indexOf(root.systemTimezone))
                                            font.family: "JetBrainsMono Nerd Font"
                                            font.pixelSize: 12
                                            onActivated: root.runSystemAction("set-timezone", currentText)

                                            contentItem: Text {
                                                leftPadding: 14
                                                rightPadding: 42
                                                text: timezonePicker.displayText
                                                color: theme.foreground
                                                verticalAlignment: Text.AlignVCenter
                                                font: timezonePicker.font
                                                elide: Text.ElideRight
                                            }
                                            indicator: Text {
                                                x: timezonePicker.width - width - 16
                                                anchors.verticalCenter: parent.verticalCenter
                                                text: timezonePicker.popup.visible ? "󰅀" : "󰅂"
                                                color: theme.accent
                                                font.family: "JetBrainsMono Nerd Font"
                                                font.pixelSize: 15
                                            }
                                            background: Rectangle {
                                                radius: 14
                                                color: theme.surface
                                                border.width: timezonePicker.activeFocus || timezonePicker.popup.visible ? 1 : 0
                                                border.color: theme.accent
                                            }
                                            popup: Popup {
                                                y: timezonePicker.height + 7
                                                width: timezonePicker.width
                                                height: 326
                                                padding: 8
                                                popupType: Popup.Item
                                                onOpened: {
                                                    timezoneSearch.text = ""
                                                    Qt.callLater(function() { timezoneSearch.forceActiveFocus() })
                                                }
                                                contentItem: ColumnLayout {
                                                    spacing: 7

                                                    TextField {
                                                        id: timezoneSearch
                                                        Layout.fillWidth: true
                                                        Layout.preferredHeight: 40
                                                        leftPadding: 35
                                                        rightPadding: 12
                                                        placeholderText: "Поиск часового пояса…"
                                                        color: theme.foreground
                                                        placeholderTextColor: theme.muted
                                                        selectionColor: theme.selected
                                                        selectedTextColor: theme.foreground
                                                        font.family: "JetBrainsMono Nerd Font"
                                                        font.pixelSize: 11
                                                        background: Rectangle {
                                                            radius: 10
                                                            color: theme.surface
                                                            border.width: timezoneSearch.activeFocus ? 1 : 0
                                                            border.color: theme.accent
                                                            Text {
                                                                anchors.left: parent.left
                                                                anchors.leftMargin: 12
                                                                anchors.verticalCenter: parent.verticalCenter
                                                                text: "󰍉"
                                                                color: theme.muted
                                                                font.family: "JetBrainsMono Nerd Font"
                                                                font.pixelSize: 12
                                                            }
                                                        }
                                                        Keys.onEscapePressed: timezonePicker.popup.close()
                                                    }

                                                    ListView {
                                                        id: timezoneResults
                                                        Layout.fillWidth: true
                                                        Layout.fillHeight: true
                                                        clip: true
                                                        spacing: 2
                                                        model: root.timezoneOptions.filter(function(zone) {
                                                            const query = timezoneSearch.text.trim().toLowerCase()
                                                            return query.length === 0 || zone.toLowerCase().indexOf(query) >= 0
                                                        })
                                                        ScrollIndicator.vertical: ScrollIndicator {}

                                                        delegate: Rectangle {
                                                            id: timezoneOption
                                                            required property int index
                                                            required property var modelData
                                                            width: timezoneResults.width
                                                            height: 38
                                                            radius: 9
                                                            color: optionMouse.containsMouse ? theme.accentSubtle : "transparent"
                                                            Text {
                                                                anchors.left: parent.left
                                                                anchors.right: parent.right
                                                                anchors.leftMargin: 11
                                                                anchors.rightMargin: 11
                                                                anchors.verticalCenter: parent.verticalCenter
                                                                text: timezoneOption.modelData
                                                                color: timezoneOption.modelData === root.systemTimezone ? theme.accent : theme.foreground
                                                                font.family: "JetBrainsMono Nerd Font"
                                                                font.pixelSize: 11
                                                                elide: Text.ElideRight
                                                            }
                                                            MouseArea {
                                                                id: optionMouse
                                                                anchors.fill: parent
                                                                hoverEnabled: true
                                                                cursorShape: Qt.PointingHandCursor
                                                                onClicked: {
                                                                    timezonePicker.popup.close()
                                                                    root.runSystemAction("set-timezone", timezoneOption.modelData)
                                                                }
                                                            }
                                                        }
                                                    }
                                                }
                                                background: Rectangle {
                                                    radius: 14
                                                    color: theme.overlayStrong
                                                    border.width: 1
                                                    border.color: theme.outline
                                                }
                                            }
                                        }
                                    }

                                    Text {
                                        Layout.fillWidth: true
                                        text: root.systemStatus
                                        visible: text.length > 0
                                        color: theme.muted
                                        font.family: "JetBrainsMono Nerd Font"
                                        font.pixelSize: 10
                                    }

                                    Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: theme.outline }

                                    RowLayout {
                                        Layout.fillWidth: true
                                        Text { text: "Автообновление"; color: theme.foreground; font.family: "Noto Sans"; font.pixelSize: 11; font.weight: Font.DemiBold }
                                        Item { Layout.fillWidth: true }
                                        Rectangle {
                                            width: 132; height: 34; radius: 11
                                            color: checkUpdateMouse.containsMouse ? theme.surfaceAlt : theme.surface
                                            border.width: 1; border.color: theme.outline
                                            Text { anchors.centerIn: parent; text: updateCheckProcess.running ? "Проверка…" : "Проверить сейчас"; color: theme.foreground; font.family: "Noto Sans"; font.pixelSize: 9 }
                                            MouseArea {
                                                id: checkUpdateMouse
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                enabled: !updateCheckProcess.running
                                                onClicked: {
                                                    root.updateStatus = "Проверка GitHub…"
                                                    updateCheckProcess.exec([Quickshell.env("HOME") + "/.config/hypr/self-shell-update.sh", "check"])
                                                }
                                            }
                                        }
                                    }

                                    ComboBox {
                                        id: updateModePicker
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: 44
                                        readonly property var modes: [
                                            { id: "off", title: "Выключено" },
                                            { id: "startup", title: "При старте" },
                                            { id: "interval", title: "Раз в N дней" }
                                        ]
                                        model: modes
                                        textRole: "title"
                                        currentIndex: Math.max(0, modes.findIndex(mode => mode.id === root.updateMode))
                                        font.family: "Noto Sans"
                                        font.pixelSize: 10
                                        onActivated: function(index) {
                                            root.configureUpdates(modes[index].id, root.updateDays)
                                        }
                                        contentItem: Text {
                                            leftPadding: 14
                                            rightPadding: 42
                                            text: updateModePicker.displayText
                                            color: theme.foreground
                                            verticalAlignment: Text.AlignVCenter
                                            font: updateModePicker.font
                                        }
                                        indicator: Text {
                                            x: updateModePicker.width - width - 16
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: updateModePicker.popup.visible ? "󰅀" : "󰅂"
                                            color: theme.accent
                                            font.family: "JetBrainsMono Nerd Font"
                                            font.pixelSize: 15
                                        }
                                        background: Rectangle {
                                            radius: 12
                                            color: theme.surface
                                            border.width: updateModePicker.popup.visible ? 1 : 0
                                            border.color: theme.accent
                                        }
                                        popup: Popup {
                                            y: updateModePicker.height + 6
                                            width: updateModePicker.width
                                            height: contentItem.implicitHeight + 12
                                            padding: 6
                                            popupType: Popup.Item
                                            contentItem: ListView {
                                                implicitHeight: contentHeight
                                                model: updateModePicker.popup.visible ? updateModePicker.delegateModel : null
                                                currentIndex: updateModePicker.highlightedIndex
                                            }
                                            background: Rectangle {
                                                radius: 12
                                                color: theme.overlayStrong
                                                border.width: 1
                                                border.color: theme.outline
                                            }
                                        }
                                        delegate: ItemDelegate {
                                            id: updateModeOption
                                            required property int index
                                            required property var modelData
                                            width: updateModePicker.width - 12
                                            height: 38
                                            highlighted: updateModePicker.highlightedIndex === index
                                            contentItem: Text {
                                                text: updateModeOption.modelData.title
                                                color: updateModeOption.highlighted ? theme.accent : theme.foreground
                                                font.family: "Noto Sans"
                                                font.pixelSize: 10
                                                verticalAlignment: Text.AlignVCenter
                                            }
                                            background: Rectangle {
                                                radius: 9
                                                color: updateModeOption.highlighted ? theme.accentSubtle : "transparent"
                                            }
                                        }
                                    }

                                    RowLayout {
                                        Layout.fillWidth: true
                                        visible: root.updateMode === "interval"
                                        Text { text: "Проверять каждые"; color: theme.muted; font.family: "Noto Sans"; font.pixelSize: 10 }
                                        Rectangle {
                                            width: 34; height: 30; radius: 9; color: daysMinusMouse.containsMouse ? theme.surfaceAlt : theme.surface
                                            Text { anchors.centerIn: parent; text: "−"; color: theme.foreground; font.pixelSize: 16 }
                                            MouseArea { id: daysMinusMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { const days = Math.max(1, root.updateDays - 1); root.configureUpdates("interval", days) } }
                                        }
                                        Text { text: String(root.updateDays); color: theme.accent; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 13; font.weight: Font.Bold }
                                        Rectangle {
                                            width: 34; height: 30; radius: 9; color: daysPlusMouse.containsMouse ? theme.surfaceAlt : theme.surface
                                            Text { anchors.centerIn: parent; text: "+"; color: theme.foreground; font.pixelSize: 15 }
                                            MouseArea { id: daysPlusMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { const days = Math.min(365, root.updateDays + 1); root.configureUpdates("interval", days) } }
                                        }
                                        Text { text: "дн."; color: theme.muted; font.family: "Noto Sans"; font.pixelSize: 10 }
                                        Item { Layout.fillWidth: true }
                                    }

                                    Text {
                                        Layout.fillWidth: true
                                        text: root.updateStatus
                                        visible: text.length > 0
                                        color: theme.muted
                                        font.family: "JetBrainsMono Nerd Font"
                                        font.pixelSize: 9
                                        elide: Text.ElideRight
                                    }
                                    Item { Layout.fillHeight: true }
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
                                    GradientStop { position: 0.50; color: Qt.alpha(theme.accent, 0.70) }
                                    GradientStop { position: 0.84; color: theme.outline }
                                    GradientStop { position: 1.0; color: "transparent" }
                                }
                            }

                            Repeater {
                                model: 2
                                delegate: Rectangle {
                                    required property int index
                                    anchors.horizontalCenter: decorativeDivider.horizontalCenter
                                    y: index * (tabRail.tabHeight + tabRail.tabSpacing)
                                        + tabRail.tabHeight / 2 - height / 2
                                    width: 7
                                    height: 7
                                    radius: 2
                                    rotation: 45
                                    color: root.activeTab === index ? theme.accent : theme.surfaceAlt
                                    border.width: 1
                                    border.color: root.activeTab === index ? theme.accentHover : theme.outline
                                    scale: root.activeTab === index ? 1.18 : 0.82
                                    Behavior on color { ColorAnimation { duration: 180; easing.type: Easing.OutCubic } }
                                    Behavior on scale { NumberAnimation { duration: 260; easing.type: Easing.OutBack } }
                                }
                            }
                        }

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
                                y: root.activeTab * (tabRail.tabHeight + tabRail.tabSpacing) + 10
                                color: theme.accent
                                Behavior on y {
                                    NumberAnimation {
                                        duration: 300
                                        easing.type: Easing.BezierSpline
                                        easing.bezierCurve: [0.38, 1.21, 0.22, 1, 1, 1]
                                    }
                                }
                            }

                            Repeater {
                                model: [{icon:"󰏘", title:"Внешний вид"}, {icon:"󰒓", title:"Система"}]
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
                                        color: root.activeTab === tabButton.index ? theme.accent : theme.muted
                                        font.family: "JetBrainsMono Nerd Font"
                                        font.pixelSize: 23
                                        scale: root.activeTab === tabButton.index ? 1.14
                                            : tabMouse.containsMouse ? 1.07 : 1
                                        Behavior on color { ColorAnimation { duration: 150 } }
                                        Behavior on scale { NumberAnimation { duration: 220; easing.type: Easing.OutBack } }
                                    }
                                    MouseArea {
                                        id: tabMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            root.activeTab = tabButton.index
                                            if (tabButton.index === 1) root.refreshSystemState()
                                        }
                                    }
                                    ThemedToolTip {
                                        // Shared tooltip used by the sidebar and other controls.
                                        target: tabButton
                                        labelText: tabButton.modelData.title
                                        shown: tabMouse.containsMouse
                                        placement: "top"
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
