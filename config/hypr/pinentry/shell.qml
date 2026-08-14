import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland

ShellRoot {
    id: root
    Theme { id: theme }
    property bool showPassword: false
    property bool submitted: false

    function finish(accepted) {
        if (submitted) return
        submitted = true
        if (!accepted) {
            Qt.quit()
            return
        }
        writer.running = true
    }

    Process {
        id: writer
        command: ["bash", "-c", "umask 077; IFS= read -r secret; printf '%s\\n' \"$secret\" > \"$SELF_SHELL_PINENTRY_RESPONSE\""]
        stdinEnabled: true
        onStarted: write(password.text + "\n")
        onExited: Qt.quit()
    }

    PanelWindow {
        screen: {
            const monitor = Hyprland.focusedMonitor
            return monitor ? Quickshell.screens.find(s => s.name === monitor.name) : Quickshell.screens[0]
        }
        visible: true
        anchors { top: true; right: true; bottom: true; left: true }
        color: theme.scrim
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
        WlrLayershell.namespace: "self-shell-pinentry"

        Shortcut { sequence: "Escape"; onActivated: root.finish(false) }

        Rectangle {
            anchors.centerIn: parent
            width: Math.min(parent.width - 40, 430)
            height: 190
            radius: 22
            color: theme.background
            border.width: 1
            border.color: theme.outline

            Column {
                anchors.fill: parent
                anchors.margins: 22
                spacing: 14

                Text {
                    text: "Разблокировать ключ"
                    color: theme.foreground
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 16
                    font.bold: true
                }
                Text {
                    width: parent.width
                    text: Quickshell.env("SELF_SHELL_PINENTRY_DESCRIPTION")
                    color: theme.muted
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 11
                    elide: Text.ElideRight
                }
                Rectangle {
                    width: parent.width
                    height: 46
                    radius: 13
                    color: theme.surface
                    border.width: password.activeFocus ? 1 : 0
                    border.color: theme.accent

                    TextField {
                        id: password
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 44
                        color: theme.foreground
                        placeholderText: Quickshell.env("SELF_SHELL_PINENTRY_PROMPT")
                        placeholderTextColor: theme.muted
                        echoMode: root.showPassword ? TextInput.Normal : TextInput.Password
                        background: null
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 13
                        Keys.onReturnPressed: root.finish(text.length > 0)
                        Component.onCompleted: forceActiveFocus()
                    }
                    Text {
                        anchors.right: parent.right
                        anchors.rightMargin: 13
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.showPassword ? "󰈈" : "󰈉"
                        color: eye.containsMouse ? theme.accent : theme.muted
                        font.family: "JetBrainsMono Nerd Font"
                        MouseArea { id: eye; anchors.fill: parent; hoverEnabled: true; onClicked: root.showPassword = !root.showPassword }
                    }
                }
                Row {
                    anchors.right: parent.right
                    spacing: 8
                    Repeater {
                        model: [{ label: "Отмена", accept: false }, { label: "Открыть", accept: true }]
                        Rectangle {
                            required property var modelData
                            width: 96; height: 36; radius: 11
                            color: modelData.accept ? theme.accent : theme.surface
                            Text { anchors.centerIn: parent; text: modelData.label; color: modelData.accept ? theme.background : theme.foreground; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 11 }
                            MouseArea { anchors.fill: parent; onClicked: root.finish(modelData.accept && password.text.length > 0) }
                        }
                    }
                }
            }
        }
    }
}
