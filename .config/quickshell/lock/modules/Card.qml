import QtQuick
import QtQuick.Effects

// Tarjeta base: fondo oscuro translúcido, esquinas redondeadas, borde sutil.
// Todas las demás tarjetas (Weather, SystemInfo, MediaPlayer, Notifications)
// envuelven su contenido dentro de esto para mantener la estética consistente.
Rectangle {
    id: card

    default property alias content: contentItem.data

    color: "#1a1f2eCC"          // navy oscuro translúcido (CC = ~80% alpha)
    radius: 20
    border.width: 1
    border.color: "#ffffff1a"   // blanco al 10% de opacidad

    // Sombra suave para dar profundidad, como en el mockup de referencia
    layer.enabled: true
    layer.effect: MultiEffect {
        shadowEnabled: true
        shadowColor: "#00000066"
        shadowBlur: 0.6
        shadowVerticalOffset: 4
    }

    Item {
        id: contentItem
        anchors.fill: parent
        anchors.margins: 16
    }
}
