import QtQuick
import Quickshell.Services.Notifications
import "." as Local

// IMPORTANTE: solo puede haber UN NotificationServer activo en tu sesión
// (ocupa el nombre org.freedesktop.Notifications en DBus). Si tu barra
// principal de Quickshell ya corre uno, NO instancies otro aquí: en vez de
// eso, expón la lista de notificaciones desde tu shell principal como una
// propiedad global (singleton) y consúmela aquí. Dejo el server activo
// como fallback para que el lockscreen funcione standalone durante pruebas.
Local.Card {
    id: root
    implicitWidth: 260
    implicitHeight: 220

    NotificationServer {
        id: server
        keepOnReload: true
        onNotification: notif => {
            notif.tracked = true
        }
    }

    content: Column {
        anchors.fill: parent
        spacing: 4

        Text {
            text: server.trackedNotifications.values.length + " notifications"
            color: "#9fb3c8"
            font.pixelSize: 12
            font.family: "JetBrains Mono Nerd Font"
            bottomPadding: 6
        }

        Repeater {
            model: server.trackedNotifications.values.slice(0, 4)
            delegate: Column {
                width: root.width - 32
                spacing: 1
                bottomPadding: 8

                Text {
                    text: modelData.summary
                    color: "#eef4fb"
                    font.pixelSize: 12
                    font.weight: Font.Bold
                    font.family: "JetBrains Mono Nerd Font"
                    elide: Text.ElideRight
                    width: parent.width
                }
                Text {
                    text: modelData.body
                    color: "#7f93a8"
                    font.pixelSize: 11
                    font.family: "JetBrains Mono Nerd Font"
                    elide: Text.ElideRight
                    width: parent.width
                    maximumLineCount: 1
                }
            }
        }

        Text {
            visible: server.trackedNotifications.values.length === 0
            text: "Sin notificaciones"
            color: "#7f93a8"
            font.pixelSize: 12
            font.family: "JetBrains Mono Nerd Font"
        }
    }
}
