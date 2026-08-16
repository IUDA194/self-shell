import QtQuick
import "../../quickshell" as Shared

// Pinentry запускается отдельным процессом, поэтому ему нужен локальный тип,
// но сама палитра всё равно наследуется из единого Theme.qml оболочки.
Shared.Theme {}
