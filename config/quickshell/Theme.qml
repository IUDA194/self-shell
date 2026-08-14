import QtQuick

QtObject {
    // Единая палитра всей оболочки — меняйте цвета только здесь.
    readonly property color background: "#26201d"
    readonly property color surface: "#372d29"
    readonly property color surfaceAlt: "#4f443e"
    readonly property color selected: "#756054"
    readonly property color foreground: "#ddd3c6"
    readonly property color foregroundSoft: "#cfc5ba"
    readonly property color muted: "#9a8b80"
    readonly property color accent: "#b58e66"
    readonly property color accentHover: "#c29a6a"
    readonly property color accentForeground: "#26201d"
    readonly property color critical: "#c4746e"
    readonly property color success: "#8aa08a"
    readonly property color outline: Qt.rgba(0.46, 0.38, 0.33, 0.72)
    readonly property color scrim: Qt.rgba(0.043, 0.035, 0.031, 0.70)
}
