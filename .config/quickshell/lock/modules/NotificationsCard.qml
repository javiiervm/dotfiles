import QtQuick
import "." as Local
import "../../"

Local.Card {
    id: root
    implicitWidth: 260
    implicitHeight: 220

    // ELIMINADO NotificationServer para prevenir conflictos críticos de Wayland/DBus.
    // Dependemos de un modelo inyectado o mostramos 0 por defecto.
    property var notifModel: typeof sharedNotifModel !== "undefined" ? sharedNotifModel : null

    content: Column {
        anchors.fill: parent
        spacing: 4

        Text {
            text: (root.notifModel ? root.notifModel.count : 0) + " notifications"
            color: Theme.grey1
            font.pixelSize: 12
            font.family: Theme.fontMain
            bottomPadding: 6
        }

        Repeater {
            model: root.notifModel ? 4 : 0 //[cite: 17]
            delegate: Column {
                width: root.width - 32
                spacing: 1
                bottomPadding: 8

                Text {
                    text: model.title !== undefined ? model.title : (model.summary || "")
                    color: Theme.white
                    font.pixelSize: 12
                    font.weight: Font.Bold
                    font.family: Theme.fontMain
                    elide: Text.ElideRight
                    width: parent.width
                }
                Text {
                    text: model.body || ""
                    color: Theme.grey1
                    font.pixelSize: 11
                    font.family: Theme.fontMain
                    elide: Text.ElideRight
                    width: parent.width
                    maximumLineCount: 1
                }
            }
        }

        Text {
            visible: !root.notifModel || root.notifModel.count === 0
            text: "No notifications"
            color: Theme.grey1
            font.pixelSize: 12
            font.family: Theme.fontMain
        }
    }
}