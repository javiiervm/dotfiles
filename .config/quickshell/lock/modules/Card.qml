import QtQuick
import "../../"

Rectangle {
    id: card
    default property alias content: contentItem.data

    color: Theme.bgGlass
    radius: 12
    border.width: 1
    border.color: Qt.alpha(Theme.white, 0.15)

    Item {
        id: contentItem
        anchors.fill: parent
        anchors.margins: 14
    }
}