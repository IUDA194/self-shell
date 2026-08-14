import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

ShellRoot {
    id: shell

    Theme { id: theme }

    // Warm Obsidian palette used by the rest of this desktop.
    readonly property color background: theme.background
    readonly property color surface: theme.surface
    readonly property color surfaceAlt: theme.surfaceAlt
    readonly property color foreground: theme.foreground
    readonly property color muted: theme.muted
    readonly property color accent: theme.accent

    property var wallpapers: []
    property string statusText: ""
    property bool applying: false
    property bool closing: false
    property real revealProgress: 0.92

    function fileUrl(path) {
        return "file://" + encodeURI(path)
    }

    function displayName(name) {
        return name.replace(/\.[^.]+$/, "").replace(/[-_]+/g, " ")
    }

    function currentEntry() {
        if (carousel.currentIndex < 0 || carousel.currentIndex >= filteredModel.count)
            return null
        return filteredModel.get(carousel.currentIndex)
    }

    function refreshFilter() {
        const query = searchInput.text.trim().toLowerCase()
        const previous = currentEntry()
        const previousPath = previous ? previous.path : Quickshell.env("WALLPAPER_PICKER_CURRENT")
        filteredModel.clear()

        for (let i = 0; i < wallpapers.length; ++i) {
            const item = wallpapers[i]
            if (query.length === 0 || displayName(item.name).toLowerCase().indexOf(query) !== -1)
                filteredModel.append(item)
        }

        let nextIndex = filteredModel.count > 0 ? 0 : -1
        for (let j = 0; j < filteredModel.count; ++j) {
            if (filteredModel.get(j).path === previousPath) {
                nextIndex = j
                break
            }
        }
        carousel.currentIndex = nextIndex
        if (nextIndex >= 0)
            Qt.callLater(function() { carousel.positionViewAtIndex(nextIndex, ListView.Center) })

        statusText = query.length > 0
            ? filteredModel.count + " из " + wallpapers.length
            : wallpapers.length + " обоев"
    }

    function moveSelection(offset) {
        if (filteredModel.count === 0)
            return
        carousel.currentIndex = (carousel.currentIndex + offset + filteredModel.count) % filteredModel.count
        carousel.positionViewAtIndex(carousel.currentIndex, ListView.Center)
    }

    function closePicker() {
        if (!applying)
            beginClose()
    }

    function beginClose() {
        if (closing)
            return
        closing = true
        revealProgress = 0
        closeTimer.restart()
    }

    function applyAt(index) {
        if (applying || index < 0 || index >= filteredModel.count)
            return

        const entry = filteredModel.get(index)
        applying = true
        statusText = "Применяю «" + displayName(entry.name) + "»…"
        applyProcess.exec([Quickshell.env("WALLPAPER_PICKER_SCRIPT"), "--apply", entry.path])
    }

    FileView {
        id: manifestFile
        path: Quickshell.env("WALLPAPER_PICKER_MANIFEST")
        blockLoading: true
    }

    ListModel { id: filteredModel }

    Process {
        id: applyProcess
        onExited: function(exitCode, exitStatus) {
            if (exitCode === 0)
                shell.beginClose()
            else {
                shell.applying = false
                shell.statusText = "Не удалось применить обои"
            }
        }
    }

    Timer {
        id: closeTimer
        interval: 280
        onTriggered: Qt.quit()
    }

    Component.onCompleted: {
        try {
            wallpapers = JSON.parse(manifestFile.text())
            refreshFilter()
        } catch (error) {
            statusText = "Не удалось прочитать список обоев"
        }
        Qt.callLater(function() {
            searchInput.forceActiveFocus()
            shell.revealProgress = 1
        })
    }

    Behavior on revealProgress {
        NumberAnimation { duration: 280; easing.type: Easing.OutCubic }
    }

    PanelWindow {
        id: window

        visible: true
        anchors { top: true; right: true; bottom: true; left: true }
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
        WlrLayershell.namespace: "wallpaper-switcher"

        FocusScope {
            anchors.fill: parent
            focus: true

            Rectangle {
                anchors.fill: parent
                color: "#080706"
                opacity: shell.revealProgress

                Image {
                    id: fullPreview
                    anchors.fill: parent
                    source: shell.currentEntry() ? shell.fileUrl(shell.currentEntry().preview) : ""
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    cache: true
                    sourceSize.width: 2560
                    sourceSize.height: 1440

                    onSourceChanged: previewFade.restart()

                    NumberAnimation {
                        id: previewFade
                        target: fullPreview
                        property: "opacity"
                        from: 0.72
                        to: 1
                        duration: 180
                        easing.type: Easing.OutCubic
                    }
                }

                Rectangle {
                    anchors.fill: parent
                    color: "#240b0908"
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: shell.closePicker()
                }

                Rectangle {
                    id: picker
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: Math.max(34, parent.height * 0.055)
                    width: Math.min(parent.width - 72, 1120)
                    height: 188
                    radius: 19
                    color: "#ed26201d"
                    border.width: 1
                    border.color: "#806d5a4f"
                    opacity: shell.revealProgress
                    scale: 0.96 + shell.revealProgress * 0.04
                    clip: true

                    MouseArea {
                        anchors.fill: parent
                        acceptedButtons: Qt.LeftButton
                        onClicked: function(mouse) { mouse.accepted = true }
                    }

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 11
                        spacing: 9

                        ListView {
                            id: carousel
                            Layout.fillWidth: true
                            Layout.preferredHeight: 124
                            model: filteredModel
                            orientation: ListView.Horizontal
                            spacing: 6
                            clip: true
                            boundsBehavior: Flickable.StopAtBounds
                            keyNavigationWraps: true
                            highlightMoveDuration: 180
                            highlightRangeMode: ListView.StrictlyEnforceRange
                            preferredHighlightBegin: width / 2 - 101
                            preferredHighlightEnd: width / 2 + 101

                            delegate: Item {
                                id: cardContainer
                                required property int index
                                required property string path
                                required property string preview
                                required property string name
                                required property string kind

                                width: 202
                                height: carousel.height
                                scale: cardContainer.ListView.isCurrentItem ? 1 : 0.84
                                opacity: cardContainer.ListView.isCurrentItem ? 1 : 0.72
                                z: cardContainer.ListView.isCurrentItem ? 2 : 1

                                Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                                Behavior on opacity { NumberAnimation { duration: 150 } }

                                Rectangle {
                                    anchors.fill: parent
                                    anchors.margins: 4
                                    radius: 12
                                    color: shell.surface
                                    border.width: cardContainer.ListView.isCurrentItem ? 2 : 1
                                    border.color: cardContainer.ListView.isCurrentItem ? shell.accent : "#66564b44"
                                    clip: true

                                    Image {
                                        anchors.fill: parent
                                        source: shell.fileUrl(cardContainer.preview)
                                        fillMode: Image.PreserveAspectCrop
                                        asynchronous: true
                                        cache: true
                                        sourceSize.width: 404
                                        sourceSize.height: 228
                                    }

                                    Rectangle {
                                        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                                        height: 31
                                        color: "#c9221c19"
                                    }

                                    Text {
                                        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                                        anchors.leftMargin: 9
                                        anchors.rightMargin: 9
                                        height: 31
                                        verticalAlignment: Text.AlignVCenter
                                        horizontalAlignment: Text.AlignHCenter
                                        text: shell.displayName(cardContainer.name)
                                        color: shell.foreground
                                        elide: Text.ElideRight
                                        font.family: "JetBrainsMono Nerd Font"
                                        font.pixelSize: 10
                                    }

                                    Rectangle {
                                        visible: cardContainer.kind !== "image"
                                        anchors { top: parent.top; right: parent.right }
                                        anchors.margins: 8
                                        width: typeLabel.implicitWidth + 13
                                        height: 22
                                        radius: 7
                                        color: "#da211b18"
                                        border.width: 1
                                        border.color: shell.accent

                                        Text {
                                            id: typeLabel
                                            anchors.centerIn: parent
                                            text: cardContainer.kind === "gif" ? "GIF" : "▶ VIDEO"
                                            color: shell.foreground
                                            font.family: "JetBrainsMono Nerd Font"
                                            font.pixelSize: 8
                                            font.weight: Font.DemiBold
                                        }
                                    }
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onEntered: carousel.currentIndex = cardContainer.index
                                    onClicked: {
                                        carousel.currentIndex = cardContainer.index
                                        shell.applyAt(cardContainer.index)
                                    }
                                }
                            }
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 34
                            radius: 10
                            color: shell.surface
                            border.width: searchInput.activeFocus ? 1 : 0
                            border.color: shell.accent

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 11
                                anchors.rightMargin: 10
                                spacing: 9

                                Text {
                                    text: "󰍉"
                                    color: searchInput.activeFocus ? shell.accent : shell.muted
                                    font.family: "JetBrainsMono Nerd Font"
                                    font.pixelSize: 12
                                }

                                Item {
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true

                                    TextInput {
                                        id: searchInput
                                        anchors.fill: parent
                                        verticalAlignment: TextInput.AlignVCenter
                                        color: shell.foreground
                                        selectionColor: "#756054"
                                        selectedTextColor: shell.foreground
                                        font.family: "JetBrainsMono Nerd Font"
                                        font.pixelSize: 11
                                        clip: true
                                        onTextChanged: shell.refreshFilter()
                                        Keys.onUpPressed: shell.moveSelection(-1)
                                        Keys.onDownPressed: shell.moveSelection(1)
                                        Keys.onReturnPressed: shell.applyAt(carousel.currentIndex)
                                        Keys.onEnterPressed: shell.applyAt(carousel.currentIndex)
                                        Keys.onEscapePressed: {
                                            if (text.length > 0)
                                                text = ""
                                            else
                                                shell.closePicker()
                                        }
                                        Keys.onTabPressed: shell.moveSelection(1)
                                    }

                                    Text {
                                        anchors.fill: parent
                                        visible: searchInput.text.length === 0
                                        verticalAlignment: Text.AlignVCenter
                                        text: "поиск обоев…"
                                        color: shell.muted
                                        font.family: "JetBrainsMono Nerd Font"
                                        font.pixelSize: 11
                                    }
                                }

                                Text {
                                    text: shell.statusText
                                    color: shell.muted
                                    font.family: "JetBrainsMono Nerd Font"
                                    font.pixelSize: 9
                                }
                            }
                        }
                    }

                    Rectangle {
                        anchors.fill: parent
                        visible: shell.applying
                        radius: picker.radius
                        color: "#d826201d"

                        Row {
                            anchors.centerIn: parent
                            spacing: 11

                            Text {
                                text: "󰑐"
                                color: shell.accent
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 22
                                RotationAnimation on rotation {
                                    running: shell.applying
                                    from: 0
                                    to: 360
                                    duration: 850
                                    loops: Animation.Infinite
                                }
                            }

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: shell.statusText
                                color: shell.foreground
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 12
                            }
                        }
                    }
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: picker.top
                    anchors.bottomMargin: 13
                    text: shell.currentEntry() ? shell.displayName(shell.currentEntry().name) : "Ничего не найдено"
                    color: shell.foreground
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                    style: Text.Outline
                    styleColor: "#b0000000"
                    opacity: shell.revealProgress
                }
            }
        }
    }
}
