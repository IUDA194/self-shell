import QtQuick
import Quickshell
import Quickshell.Io

QtObject {
    id: root
    property var fallback: ({})
    property var strings: ({})
    readonly property string language: {
        const raw = Quickshell.env("SELF_SHELL_LANG") || Quickshell.env("LC_ALL")
            || Quickshell.env("LC_MESSAGES") || Quickshell.env("LANG") || "ru"
        return raw.split(".")[0].split("_")[0].split("-")[0].toLowerCase()
    }

    function format(value, args) {
        let result = value
        for (let index = 0; index < args.length; ++index)
            result = result.replace(new RegExp("\\\\{" + index + "\\\\}", "g"), String(args[index]))
        return result
    }
    function tr(key, args) {
        const value = strings[key] !== undefined ? strings[key]
            : fallback[key] !== undefined ? fallback[key] : key
        return format(value, args || [])
    }
    function parse(view, target) {
        try { root[target] = JSON.parse(view.text()) } catch (error) { root[target] = ({}) }
    }

    property FileView fallbackFile: FileView {
        path: Quickshell.env("HOME") + "/.config/self-shell/config/locales/ru.json"
        blockLoading: true; watchChanges: true; printErrors: false
        onLoaded: root.parse(this, "fallback")
        onFileChanged: reload()
    }
    property FileView languageFile: FileView {
        path: Quickshell.env("HOME") + "/.config/self-shell/config/locales/" + root.language + ".json"
        blockLoading: true; watchChanges: true; printErrors: false
        onLoaded: root.parse(this, "strings")
        onFileChanged: reload()
    }
}
