import QtQuick
import Quickshell
import Quickshell.Io

QtObject {
    id: root

    // Единственный источник цветов оболочки. Компоненты используют только эти
    // базовые и семантические токены, поэтому смена схемы не потребует их правки.
    property var palette: ({})
    property color background: palette.background || "#26201d"
    property color surface: palette.surface || "#372d29"
    property color surfaceAlt: palette.surfaceAlt || "#4f443e"
    property color selected: palette.selected || "#756054"
    property color foreground: palette.foreground || "#ddd3c6"
    property color foregroundSoft: palette.foregroundSoft || "#cfc5ba"
    property color muted: palette.muted || "#9a8b80"
    property color accent: palette.accent || "#b58e66"
    property color accentHover: palette.accentHover || "#c29a6a"
    property color accentForeground: palette.accentForeground || "#26201d"
    property color critical: palette.critical || "#c4746e"
    property color success: palette.success || "#8aa08a"
    property color outline: palette.outline || Qt.rgba(0.46, 0.38, 0.33, 0.72)
    property color scrim: palette.scrim || Qt.rgba(0.043, 0.035, 0.031, 0.70)

    property FileView paletteFile: FileView {
        path: Quickshell.env("HOME") + "/.cache/self-shell/active-palette.json"
        blockLoading: true
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            try {
                const parsed = JSON.parse(text())
                root.palette = parsed.colors || parsed
            } catch (error) {
                root.palette = ({})
            }
        }
    }

    readonly property color hover: Qt.lighter(surface, 1.12)
    readonly property color pressed: Qt.darker(surface, 1.06)
    readonly property color disabled: Qt.alpha(muted, 0.58)
    readonly property color subtle: Qt.alpha(foreground, 0.72)
    readonly property color faint: Qt.alpha(foreground, 0.52)
    readonly property color accentSubtle: Qt.alpha(accent, 0.20)
    readonly property color accentHoverSubtle: Qt.alpha(accent, 0.34)
    readonly property color criticalSubtle: Qt.alpha(critical, 0.28)
    readonly property color shadow: Qt.alpha("#000000", 0.35)
    readonly property color overlay: Qt.alpha(background, 0.86)
    readonly property color overlayStrong: Qt.alpha(background, 0.94)

    // Palette changes should feel like one continuous ambient transition.
    // Every Theme instance reads the same file and starts these animations
    // together, including the Canvas-backed sidebar surface.
    Behavior on background { ColorAnimation { duration: 520; easing.type: Easing.InOutCubic } }
    Behavior on surface { ColorAnimation { duration: 520; easing.type: Easing.InOutCubic } }
    Behavior on surfaceAlt { ColorAnimation { duration: 520; easing.type: Easing.InOutCubic } }
    Behavior on selected { ColorAnimation { duration: 560; easing.type: Easing.InOutCubic } }
    Behavior on foreground { ColorAnimation { duration: 440; easing.type: Easing.InOutCubic } }
    Behavior on foregroundSoft { ColorAnimation { duration: 440; easing.type: Easing.InOutCubic } }
    Behavior on muted { ColorAnimation { duration: 480; easing.type: Easing.InOutCubic } }
    Behavior on accent { ColorAnimation { duration: 620; easing.type: Easing.InOutCubic } }
    Behavior on accentHover { ColorAnimation { duration: 620; easing.type: Easing.InOutCubic } }
    Behavior on accentForeground { ColorAnimation { duration: 520; easing.type: Easing.InOutCubic } }
    Behavior on critical { ColorAnimation { duration: 480; easing.type: Easing.InOutCubic } }
    Behavior on success { ColorAnimation { duration: 480; easing.type: Easing.InOutCubic } }
    Behavior on outline { ColorAnimation { duration: 560; easing.type: Easing.InOutCubic } }
    Behavior on scrim { ColorAnimation { duration: 420; easing.type: Easing.InOutCubic } }
}
