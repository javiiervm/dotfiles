import QtQuick
import Quickshell

Item {
    id: root

    required property var app

    signal activated(var app)

    implicitWidth: 50
    implicitHeight: 50
    width: 50
    height: 50

    property bool hovered: mouseArea.containsMouse

    readonly property url resolvedIconSource: {
        // iconPath may be a QUrl (for example, Qt.resolvedUrl(...)),
        // so don't test .length directly on it.
        if (root.app.iconPath !== undefined &&
            root.app.iconPath !== null &&
            root.app.iconPath.toString() !== "") {

            const p = root.app.iconPath.toString()

            if (p.startsWith("file://") ||
                p.startsWith("qrc:/") ||
                p.startsWith("image://")) {
                return p
            }

            if (p.startsWith("/"))
                return "file://" + p

            return p
        }

        if (root.app.iconName !== undefined &&
            root.app.iconName !== null &&
            root.app.iconName.toString() !== "") {
            return Quickshell.iconPath(
                root.app.iconName.toString(),
                "application-x-executable"
            )
        }

        return Quickshell.iconPath(
            "application-x-executable",
            "image-missing"
        )
    }

    Image {
        id: appIcon
        anchors.centerIn: parent

        width: root.hovered ? 46 : 42
        height: width

        source: root.resolvedIconSource
        sourceSize: Qt.size(96, 96)
        fillMode: Image.PreserveAspectFit
        smooth: true
        mipmap: true
        cache: false

        Behavior on width {
            NumberAnimation {
                duration: 120
                easing.type: Easing.OutCubic
            }
        }
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor

        onClicked: root.activated(root.app)
    }
}
