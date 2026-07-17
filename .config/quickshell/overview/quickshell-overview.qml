import QtQuick
import "." // Importante: Asegura que reconozca tu Theme.qml en el mismo directorio

QtObject {
    id: m3

    // --- COLORES DE ACENTO ---
    // Usamos el azul y morado de tu Theme como colores principales y secundarios
    property color m3primary: Theme.blue
    property color m3onPrimary: Theme.bg0

    property color m3primaryContainer: Qt.alpha(Theme.blue, 0.2)
    property color m3onPrimaryContainer: Theme.blue

    property color m3secondary: Theme.purple
    property color m3onSecondary: Theme.bg0

    property color m3secondaryContainer: Qt.alpha(Theme.purple, 0.2)
    property color m3onSecondaryContainer: Theme.purple

    // --- FONDOS Y TRANSPARENCIA CRISTAL ---
    // Aquí aplicamos tu Theme.bgGlass para que el overview tenga la misma transparencia
    property color m3background: Theme.bgGlass
    property color m3onBackground: Theme.white

    property color m3surface: Theme.bgGlass

    // Variantes de contenedores usando la paleta oscura de tu Theme
    property color m3surfaceContainerLow: Theme.bg0
    property color m3surfaceContainer: Theme.bgGlass
    property color m3surfaceContainerHigh: Theme.bg1
    property color m3surfaceContainerHighest: Theme.notifBg

    property color m3onSurface: Theme.white

    property color m3surfaceVariant: Theme.notifBgBtn
    property color m3onSurfaceVariant: Theme.grey1

    property color m3inverseSurface: Theme.fg
    property color m3inverseOnSurface: Theme.bg0

    // --- BORDES ---
    // Aplicamos el borde translúcido sutil que usas en el Control Center y Notificaciones
    property color m3outline: Qt.alpha(Theme.white, 0.15)
    property color m3outlineVariant: Qt.alpha(Theme.white, 0.05)

    property color m3shadow: "#000000"
}