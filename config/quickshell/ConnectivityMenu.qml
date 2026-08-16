pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Bluetooth
import Quickshell.Io
import Quickshell.Networking
import Quickshell.Services.Pipewire

Item {
    id: window

    Theme { id: theme }

    property string page: "wifi"
    property string keyboardLayout: "English (US)"
    property var networks: []
    property string activeSsid: ""
    property string connectingSsid: ""
    property string passwordSsid: ""
    property string errorText: ""
    property bool scanning: false
    property bool closing: false
    property real revealProgress: 0
    property string displayedPage: page
    property real contentOpacity: 1
    readonly property var audioSinks: Pipewire.nodes.values.filter(node => !node.isStream && node.isSink && node.audio)
    readonly property var audioStreams: Pipewire.nodes.values.filter(node => node.isStream && node.audio)
    readonly property var audioTrackedNodes: [Pipewire.defaultAudioSink].concat(audioSinks).concat(audioStreams).filter(node => node)
    readonly property real surfaceTop: card.y
    readonly property real surfaceBottom: surfaceTop + card.fullHeight
    readonly property real surfaceRight: card.x + card.fullWidth

    signal closeRequested

    PwObjectTracker { objects: window.audioTrackedNodes }

    onPageChanged: {
        if (!visible || closing) {
            displayedPage = page
            contentOpacity = 1
            return
        }
        contentOpacity = 0
        pageSwitchTimer.restart()
    }

    function close() {
        if (closing)
            return
        passwordSsid = ""
        errorText = ""
        closing = true
        revealProgress = 0
        closeTimer.restart()
    }

    function refreshNetworks() {
        if (!scanProcess.running) {
            scanning = true
            scanProcess.running = true
        }
    }

    function connectNetwork(ssid, password) {
        connectingSsid = ssid
        errorText = ""
        const args = ["nmcli", "--wait", "20", "device", "wifi", "connect", ssid]
        if (password.length > 0)
            args.push("password", password)
        connectProcess.command = args
        connectProcess.running = true
    }

    onVisibleChanged: {
        if (!visible) {
            closing = false
            revealProgress = 0
            return
        }
        closing = false
        keyboardScope.forceActiveFocus()
        revealProgress = 0
        Qt.callLater(function() {
            revealProgress = 1
            if (window.page === "wifi")
                window.refreshNetworks()
        })
    }

    Behavior on revealProgress {
        NumberAnimation {
            duration: window.closing ? 500 : 240
            easing.type: Easing.BezierSpline
            // Same expressive curve used by the launcher reveal.
            easing.bezierCurve: [0.38, 1.21, 0.22, 1, 1, 1]
        }
    }

    Timer {
        id: closeTimer
        interval: 500
        onTriggered: window.closeRequested()
    }

    Timer {
        id: pageSwitchTimer
        interval: 150
        onTriggered: {
            window.displayedPage = window.page
            window.contentOpacity = 1
            if (window.page === "wifi")
                window.refreshNetworks()
        }
    }

    Behavior on contentOpacity {
        NumberAnimation {
            duration: 150
            easing.type: Easing.OutCubic
        }
    }

    Process {
        id: scanProcess
        command: ["bash", "-lc", "nmcli device wifi rescan >/dev/null 2>&1 || true; nmcli -t --escape no -f ACTIVE,SECURITY,SIGNAL,SSID device wifi list"]
        stdout: StdioCollector {
            onStreamFinished: {
                const seen = ({})
                const result = []
                let active = ""
                const lines = text.split("\n")
                for (let i = 0; i < lines.length; ++i) {
                    const fields = lines[i].split(":")
                    if (fields.length < 4)
                        continue
                    const ssid = fields.slice(3).join(":").trim()
                    if (!ssid || seen[ssid])
                        continue
                    seen[ssid] = true
                    const isActive = fields[0] === "yes"
                    if (isActive)
                        active = ssid
                    result.push({
                        ssid: ssid,
                        secure: fields[1] !== "--" && fields[1].length > 0,
                        strength: Number(fields[2]) || 0,
                        active: isActive
                    })
                }
                result.sort((a, b) => Number(b.active) - Number(a.active) || b.strength - a.strength)
                window.networks = result.slice(0, 8)
                window.activeSsid = active
                window.scanning = false
            }
        }
    }

    Process {
        id: connectProcess
        stdout: StdioCollector {}
        stderr: StdioCollector {
            onStreamFinished: if (text.trim().length > 0) window.errorText = text.trim()
        }
        onExited: exitCode => {
            if (exitCode === 0) {
                window.passwordSsid = ""
                window.refreshNetworks()
            } else if (window.passwordSsid.length === 0) {
                window.passwordSsid = window.connectingSsid
                passwordInput.text = ""
                Qt.callLater(() => passwordInput.forceActiveFocus())
            }
            window.connectingSsid = ""
        }
    }

    Process {
        id: disconnectProcess
        command: ["nmcli", "device", "disconnect", ""]
        onExited: exitCode => window.refreshNetworks()
    }

    FocusScope {
        id: keyboardScope
        anchors.fill: parent
        focus: true
        Keys.onEscapePressed: window.close()

        Rectangle {
            id: card
            readonly property real fullWidth: window.passwordSsid.length > 0 ? 400 : (window.page === "bluetooth" ? 340 : (window.page === "audio" ? 380 : (window.page === "keyboard" ? 120 : 360)))
            readonly property real fullHeight: content.implicitHeight + (window.page === "keyboard" ? 24 : 40)
            readonly property real closeProgress: window.closing ? window.revealProgress : 1
            // Each surface is centred exactly on its corresponding rail button.
            readonly property real buttonCenterFromBottom: window.page === "keyboard" ? 158 : (window.page === "wifi" ? 126 : (window.page === "bluetooth" ? 94 : 30))
            // Prefer button alignment, but lift tall surfaces enough to keep
            // their complete content inside the screen.
            readonly property real baseBottomMargin: Math.max(28, buttonCenterFromBottom - fullHeight / 2)

            anchors.left: parent.left
            anchors.leftMargin: 55
            anchors.bottom: parent.bottom
            anchors.bottomMargin: baseBottomMargin
            width: fullWidth * closeProgress
            implicitHeight: fullHeight
            height: fullHeight
            radius: 9 + window.revealProgress * 13
            color: "transparent"
            border.width: 0
            clip: true

            Behavior on width {
                enabled: !window.closing
                NumberAnimation {
                    duration: 500
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: [0.38, 1.21, 0.22, 1, 1, 1]
                }
            }

            Behavior on height {
                enabled: !window.closing
                NumberAnimation {
                    duration: 500
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: [0.38, 1.21, 0.22, 1, 1, 1]
                }
            }

            Behavior on anchors.bottomMargin {
                enabled: !window.closing
                NumberAnimation {
                    duration: 500
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: [0.38, 1.21, 0.22, 1, 1, 1]
                }
            }

            MouseArea { anchors.fill: parent }

            ColumnLayout {
                id: content
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.leftMargin: window.page === "keyboard" ? 12 : 20
                anchors.topMargin: window.page === "keyboard" ? 12 : 20
                width: card.fullWidth - (window.page === "keyboard" ? 24 : 40)
                spacing: 12

                ColumnLayout {
                    visible: window.passwordSsid.length === 0 && window.displayedPage === "wifi"
                    opacity: window.contentOpacity
                    Layout.fillWidth: true
                    spacing: 6

                    SectionTitle { title: "Беспроводная сеть" }
                    ToggleRow {
                        title: "Включено"
                        checked: Networking.wifiEnabled
                        onToggled: enabled => {
                            Quickshell.execDetached(["nmcli", "radio", "wifi", enabled ? "on" : "off"])
                            Qt.callLater(() => window.refreshNetworks())
                        }
                    }
                    Text {
                        text: window.networks.length + " сетей доступно"
                        color: theme.muted
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 11
                    }
                    Repeater {
                        model: window.networks
                        delegate: ConnectionRow {
                            required property var modelData
                            name: modelData.ssid
                            icon: modelData.strength >= 75 ? "󰤨" : (modelData.strength >= 50 ? "󰤥" : (modelData.strength >= 25 ? "󰤢" : "󰤟"))
                            detailIcon: modelData.secure ? "" : ""
                            connected: modelData.active
                            busy: window.connectingSsid === modelData.ssid
                            showSettings: false
                            onClicked: {
                                if (modelData.active) {
                                    Quickshell.execDetached(["bash", "-lc", "nmcli connection down id " + JSON.stringify(modelData.ssid)])
                                    Qt.callLater(() => window.refreshNetworks())
                                } else {
                                    window.connectNetwork(modelData.ssid, "")
                                }
                            }
                        }
                    }
                    ActionButton {
                        text: window.scanning ? "Сканирование…" : "Обновить список"
                        busy: window.scanning
                        enabled: Networking.wifiEnabled
                        onClicked: if (!window.scanning) window.refreshNetworks()
                    }
                }

                ColumnLayout {
                    visible: window.passwordSsid.length === 0 && window.displayedPage === "bluetooth"
                    opacity: window.contentOpacity
                    Layout.fillWidth: true
                    spacing: 6

                    SectionTitle { title: "Bluetooth" }
                    ToggleRow {
                        title: "Включено"
                        checked: Bluetooth.defaultAdapter?.enabled ?? false
                        onToggled: enabled => { if (Bluetooth.defaultAdapter) Bluetooth.defaultAdapter.enabled = enabled }
                    }
                    ToggleRow {
                        title: "Поиск устройств"
                        checked: Bluetooth.defaultAdapter?.discovering ?? false
                        onToggled: enabled => { if (Bluetooth.defaultAdapter) Bluetooth.defaultAdapter.discovering = enabled }
                    }
                    Text {
                        readonly property int connectedCount: Bluetooth.devices.values.filter(device => device.connected).length
                        text: Bluetooth.devices.values.length + " устройств доступно" + (connectedCount > 0 ? " (" + connectedCount + " подключено)" : "")
                        color: theme.muted
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 11
                    }
                    Repeater {
                        model: ScriptModel { values: [...Bluetooth.devices.values].sort((a, b) => Number(b.connected) - Number(a.connected) || Number(b.paired) - Number(a.paired) || a.name.localeCompare(b.name)).slice(0, 7) }
                        delegate: ConnectionRow {
                            required property BluetoothDevice modelData
                            name: modelData.name || modelData.address
                            icon: modelData.icon && modelData.icon.indexOf("head") >= 0 ? "󰋋" : "󰂯"
                            detailIcon: modelData.batteryAvailable ? Math.round(modelData.battery * 100) + "%" : ""
                            connected: modelData.connected
                            busy: modelData.state === BluetoothDeviceState.Connecting || modelData.state === BluetoothDeviceState.Disconnecting
                            onClicked: modelData.connected = !modelData.connected
                            onSettingsClicked: Quickshell.execDetached(["bash", "-lc", "command -v blueman-manager >/dev/null && blueman-manager || bluetoothctl info " + JSON.stringify(modelData.address)])
                        }
                    }
                    ActionButton { text: "󰒓  Открыть системные настройки"; onClicked: Quickshell.execDetached(["bash", "-lc", "command -v blueman-manager >/dev/null && blueman-manager || bluetoothctl"])}
                }

                ColumnLayout {
                    id: audioPage
                    readonly property var sink: Pipewire.defaultAudioSink
                    readonly property var sinkAudio: sink ? sink.audio : null

                    visible: window.passwordSsid.length === 0 && window.displayedPage === "audio"
                    opacity: window.contentOpacity
                    Layout.fillWidth: true
                    spacing: 8

                    SectionTitle { title: "Микшер звука" }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 10
                        Text {
                            text: !audioPage.sinkAudio || audioPage.sinkAudio.muted ? "󰝟" : ""
                            color: audioPage.sinkAudio && audioPage.sinkAudio.muted ? theme.accent : theme.foreground
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 17
                        }
                        Text {
                            Layout.fillWidth: true
                            text: audioPage.sink ? (audioPage.sink.description || audioPage.sink.name || "Выход") : "Аудиовыход не найден"
                            elide: Text.ElideRight
                            color: theme.foregroundSoft
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 11
                        }
                        Text {
                            text: audioPage.sinkAudio ? Math.round(audioPage.sinkAudio.volume * 100) + "%" : "—"
                            color: theme.muted
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 11
                        }
                    }

                    VolumeSlider {
                        Layout.fillWidth: true
                        value: audioPage.sinkAudio ? audioPage.sinkAudio.volume : 0
                        muted: !audioPage.sinkAudio || audioPage.sinkAudio.muted
                        onMovedTo: value => {
                            if (audioPage.sinkAudio) {
                                audioPage.sinkAudio.muted = false
                                audioPage.sinkAudio.volume = value
                            }
                        }
                    }

                    ToggleRow {
                        title: "Без звука"
                        checked: audioPage.sinkAudio ? audioPage.sinkAudio.muted : true
                        onToggled: enabled => { if (audioPage.sinkAudio) audioPage.sinkAudio.muted = enabled }
                    }

                    Text {
                        visible: window.audioSinks.length > 0
                        text: "Устройства вывода"
                        color: theme.muted
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 10
                    }

                    Repeater {
                        model: ScriptModel { values: window.audioSinks.slice(0, 4) }
                        delegate: ConnectionRow {
                            required property PwNode modelData
                            name: modelData.description || modelData.name || "Аудиовыход"
                            icon: "󰓃"
                            connected: Pipewire.defaultAudioSink === modelData
                            onClicked: Pipewire.preferredDefaultAudioSink = modelData
                            onSettingsClicked: Quickshell.execDetached(["bash", "-lc", "command -v pwvucontrol >/dev/null && pwvucontrol || command -v pavucontrol >/dev/null && pavucontrol || wpctl status"])
                        }
                    }

                    Text {
                        visible: window.audioStreams.length > 0
                        text: "Приложения"
                        color: theme.muted
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 10
                    }

                    Repeater {
                        model: ScriptModel { values: window.audioStreams.slice(0, 5) }
                        delegate: ColumnLayout {
                            required property PwNode modelData
                            Layout.fillWidth: true
                            spacing: 3
                            RowLayout {
                                Layout.fillWidth: true
                                Text { text: "󰎆"; color: theme.subtle; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 13 }
                                Text {
                                    Layout.fillWidth: true
                                    text: modelData.properties["application.name"] || modelData.description || modelData.name || "Приложение"
                                    elide: Text.ElideRight
                                    color: theme.foreground
                                    font.family: "JetBrainsMono Nerd Font"
                                    font.pixelSize: 11
                                }
                                Text { text: Math.round(modelData.audio.volume * 100) + "%"; color: theme.muted; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 10 }
                            }
                            VolumeSlider {
                                Layout.fillWidth: true
                                value: modelData.audio.volume
                                muted: modelData.audio.muted
                                onMovedTo: value => {
                                    modelData.audio.muted = false
                                    modelData.audio.volume = value
                                }
                            }
                        }
                    }

                    ActionButton { text: "󰒓  Открыть настройки звука"; onClicked: Quickshell.execDetached(["bash", "-lc", "command -v pwvucontrol >/dev/null && pwvucontrol || command -v pavucontrol >/dev/null && pavucontrol || wpctl status"])}
                }

                ColumnLayout {
                    visible: window.passwordSsid.length === 0 && window.displayedPage === "keyboard"
                    opacity: window.contentOpacity
                    Layout.fillWidth: true
                    spacing: 4

                    LayoutRow {
                        shortName: "EN"
                        selected: window.keyboardLayout.indexOf("English") >= 0
                        onClicked: Quickshell.execDetached(["hyprctl", "switchxkblayout", "all", "0"])
                    }
                    LayoutRow {
                        shortName: "RU"
                        selected: window.keyboardLayout.indexOf("Russian") >= 0
                        onClicked: Quickshell.execDetached(["hyprctl", "switchxkblayout", "all", "1"])
                    }
                }

                ColumnLayout {
                    visible: window.passwordSsid.length > 0
                    Layout.fillWidth: true
                    spacing: 14

                    Text { Layout.alignment: Qt.AlignHCenter; text: ""; color: theme.foregroundSoft; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 38 }
                    SectionTitle { Layout.alignment: Qt.AlignHCenter; title: "Введите пароль" }
                    Text { Layout.alignment: Qt.AlignHCenter; text: "Сеть: " + window.passwordSsid; color: theme.muted; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 11 }
                    TextField {
                        id: passwordInput
                        Layout.fillWidth: true
                        echoMode: TextInput.Password
                        placeholderText: "Пароль"
                        color: theme.foreground
                        font.family: "JetBrainsMono Nerd Font"
                        background: Rectangle { color: theme.surface; radius: 12; border.width: 1; border.color: passwordInput.activeFocus ? theme.accent : theme.outline }
                        Keys.onReturnPressed: if (text.length > 0) window.connectNetwork(window.passwordSsid, text)
                    }
                    Text { visible: window.errorText.length > 0; Layout.fillWidth: true; wrapMode: Text.Wrap; text: window.errorText; color: theme.critical; font.pixelSize: 10 }
                    RowLayout {
                        Layout.fillWidth: true
                        ActionButton { Layout.fillWidth: true; text: "Отмена"; onClicked: { window.passwordSsid = ""; window.errorText = "" } }
                        ActionButton { Layout.fillWidth: true; text: "Подключиться"; enabled: passwordInput.text.length > 0; onClicked: window.connectNetwork(window.passwordSsid, passwordInput.text) }
                    }
                }
            }
        }
    }

    component SectionTitle: Text {
        required property string title
        text: title
        color: theme.foreground
        font.family: "JetBrainsMono Nerd Font"
        font.pixelSize: 14
        font.weight: Font.DemiBold
    }

    component ToggleRow: RowLayout {
        id: toggleRow
        required property string title
        property bool checked: false
        signal toggled(bool enabled)
        Layout.fillWidth: true
        Text { Layout.fillWidth: true; text: toggleRow.title; color: theme.foregroundSoft; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 12 }
        Rectangle {
            id: toggleTrack

            implicitWidth: 46
            implicitHeight: 26
            radius: height / 2
            color: toggleRow.checked
                ? (toggleMouse.containsMouse ? theme.accentHover : theme.accent)
                : (toggleMouse.containsMouse ? theme.surfaceAlt : theme.surface)
            border.width: 1
            border.color: toggleRow.checked ? theme.accentHover : theme.outline

            Behavior on color {
                ColorAnimation { duration: 150; easing.type: Easing.OutCubic }
            }

            Behavior on border.color {
                ColorAnimation { duration: 150; easing.type: Easing.OutCubic }
            }

            Rectangle {
                width: 20
                height: 20
                radius: 10
                x: toggleRow.checked ? toggleTrack.width - width - 3 : 3
                anchors.verticalCenter: parent.verticalCenter
                color: toggleRow.checked ? theme.accentForeground : theme.foregroundSoft
                border.width: 1
                border.color: toggleRow.checked ? theme.accent : theme.foregroundSoft

                Behavior on x {
                    NumberAnimation {
                        duration: 180
                        easing.type: Easing.OutCubic
                    }
                }

                Behavior on color {
                    ColorAnimation { duration: 150 }
                }
            }

            MouseArea {
                id: toggleMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: toggleRow.toggled(!toggleRow.checked)
            }
        }
    }

    component VolumeSlider: Slider {
        id: volumeSlider
        property bool muted: false
        signal movedTo(real value)
        from: 0
        to: 1
        implicitHeight: 26
        onMoved: movedTo(value)

        background: Rectangle {
            x: volumeSlider.leftPadding
            y: volumeSlider.topPadding + volumeSlider.availableHeight / 2 - height / 2
            width: volumeSlider.availableWidth
            height: 6
            radius: 3
            color: theme.surfaceAlt
            Rectangle {
                width: volumeSlider.visualPosition * parent.width
                height: parent.height
                radius: parent.radius
                color: volumeSlider.muted ? theme.selected : theme.accent
            }
        }

        handle: Rectangle {
            x: volumeSlider.leftPadding + volumeSlider.visualPosition * (volumeSlider.availableWidth - width)
            y: volumeSlider.topPadding + volumeSlider.availableHeight / 2 - height / 2
            width: 16
            height: 16
            radius: 8
            color: volumeSlider.muted ? theme.muted : theme.foreground
            border.width: 2
            border.color: volumeSlider.muted ? theme.selected : theme.accent
        }
    }

    component LayoutRow: Rectangle {
        id: layoutRow
        required property string shortName
        property bool selected: false
        signal clicked

        Layout.fillWidth: true
        implicitHeight: 36
        radius: 10
        color: selected ? theme.surface : (layoutMouse.containsMouse ? theme.hover : "transparent")
        scale: selected ? 1 : 0.985

        Behavior on color {
            ColorAnimation { duration: 220; easing.type: Easing.OutCubic }
        }

        Behavior on scale {
            NumberAnimation {
                duration: 320
                easing.type: Easing.BezierSpline
                easing.bezierCurve: [0.38, 1.21, 0.22, 1, 1, 1]
            }
        }

        Rectangle {
            anchors.left: parent.left
            anchors.leftMargin: 3
            anchors.verticalCenter: parent.verticalCenter
            width: 3
            height: layoutRow.selected ? 18 : 0
            radius: 2
            color: theme.accent
            opacity: layoutRow.selected ? 0.8 : 0

            Behavior on height {
                NumberAnimation { duration: 260; easing.type: Easing.OutCubic }
            }
            Behavior on opacity { NumberAnimation { duration: 180 } }
        }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 8
            anchors.rightMargin: 8
            spacing: 6

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 24
                radius: 7
                color: layoutRow.selected ? theme.surfaceAlt : theme.surface

                Behavior on color { ColorAnimation { duration: 220 } }

                Text {
                    anchors.centerIn: parent
                    text: layoutRow.shortName
                    color: layoutRow.selected ? theme.foreground : theme.subtle
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 10
                    font.weight: Font.Bold

                    Behavior on color { ColorAnimation { duration: 220 } }
                }
            }
            Text {
                text: layoutRow.selected ? "" : ""
                color: theme.accent
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: 12
                opacity: layoutRow.selected ? 0.8 : 0
                scale: layoutRow.selected ? 1 : 0.5

                Behavior on opacity { NumberAnimation { duration: 180 } }
                Behavior on scale {
                    NumberAnimation {
                        duration: 280
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: [0.38, 1.21, 0.22, 1, 1, 1]
                    }
                }
            }
        }

        MouseArea {
            id: layoutMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: layoutRow.clicked()
        }
    }

    component ConnectionRow: Rectangle {
        id: connection
        required property string name
        required property string icon
        property string detailIcon: ""
        property bool connected: false
        property bool busy: false
        property bool showSettings: true
        signal clicked
        signal settingsClicked
        Layout.fillWidth: true
        implicitHeight: 34
        radius: 12
        color: connection.busy ? theme.pressed : (containerMouse.containsMouse ? theme.hover : "transparent")

        Behavior on color { ColorAnimation { duration: 120 } }

        MouseArea {
            id: containerMouse
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.rightMargin: connection.showSettings ? 46 : 0
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            enabled: !connection.busy
            onClicked: connection.clicked()
        }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 10
            spacing: 10

            Text {
                text: connection.icon
                color: connection.busy || connection.connected ? theme.accentHover : theme.subtle
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: 17

                SequentialAnimation on scale {
                    running: connection.busy
                    loops: Animation.Infinite
                    NumberAnimation { to: 1.12; duration: 520; easing.type: Easing.InOutSine }
                    NumberAnimation { to: 0.92; duration: 520; easing.type: Easing.InOutSine }
                }
            }
            Text { Layout.fillWidth: true; text: connection.name; elide: Text.ElideRight; color: connection.connected ? theme.accentHover : theme.foreground; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 12; font.weight: connection.connected ? Font.DemiBold : Font.Normal }
            Text {
                visible: connection.detailIcon.length > 0 && !connection.busy
                Layout.rightMargin: connection.showSettings ? 0 : 10
                text: connection.detailIcon
                color: theme.muted
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: 10
            }

            Item {
                visible: connection.busy
                Layout.rightMargin: connection.showSettings ? 0 : 10
                implicitWidth: connection.busy ? 14 : 0
                implicitHeight: 14

                Text {
                    anchors.centerIn: parent
                    text: "󰔟"
                    color: theme.accentHover
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 12

                    RotationAnimation on rotation {
                        running: connection.busy
                        from: 0
                        to: 360
                        duration: 850
                        loops: Animation.Infinite
                        direction: RotationAnimation.Clockwise
                    }
                }
            }

            Rectangle {
                id: settingsButton
                visible: connection.showSettings
                Layout.rightMargin: 5
                implicitWidth: connection.showSettings ? 30 : 0
                implicitHeight: 30
                radius: 8
                color: settingsMouse.containsMouse ? theme.surfaceAlt : "transparent"

                Behavior on color { ColorAnimation { duration: 120 } }

                Text {
                    anchors.centerIn: parent
                    text: connection.busy ? "󰔟" : ""
                    color: settingsMouse.containsMouse ? theme.accentHover : theme.muted
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 11

                    Behavior on color { ColorAnimation { duration: 120 } }
                }

                MouseArea {
                    id: settingsMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: connection.settingsClicked()
                }
            }
        }
    }

    component ActionButton: Button {
        id: action
        property bool busy: false
        Layout.fillWidth: true
        implicitHeight: 38
        contentItem: Item {
            Row {
                anchors.centerIn: parent
                spacing: 9

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: action.busy ? "󰔟" : "󰑐"
                    visible: action.busy || action.text === "Обновить список"
                    color: action.enabled ? theme.accentForeground : theme.disabled
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 11

                    RotationAnimation on rotation {
                        running: action.busy
                        from: 0
                        to: 360
                        duration: 900
                        loops: Animation.Infinite
                        direction: RotationAnimation.Clockwise
                    }
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: action.text
                    color: action.enabled ? theme.accentForeground : theme.disabled
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 11
                    font.weight: Font.DemiBold
                }
            }
        }
        background: Rectangle {
            radius: 19
            color: action.enabled ? (action.busy ? theme.accent : (action.hovered ? theme.accentHover : theme.accent)) : theme.disabled

            Behavior on color { ColorAnimation { duration: 180 } }

            SequentialAnimation on opacity {
                running: action.busy
                loops: Animation.Infinite
                NumberAnimation { to: 0.78; duration: 650; easing.type: Easing.InOutSine }
                NumberAnimation { to: 1; duration: 650; easing.type: Easing.InOutSine }
            }
        }
    }
}
