import QtQuick
import Quickshell
import ".."

FocusScope {
    id: selector

    signal selected(string capture, string output)
    signal canceled()

    property int availableHeight: 420
    property int currentIndex: 0
    readonly property var options: {
        var screens = Quickshell.screens
        var rows = []
        if (screens.length > 1)
            rows.push({ capture: "all", output: "", title: "All monitors", subtitle: "Record all connected displays", icon: "󰍺" })
        for (var i = 0; i < screens.length; i++) {
            var s = screens[i]
            rows.push({ capture: "screen", output: s.name,
                title: s.name, subtitle: s.width + " × " + s.height + " · Logical resolution",
                icon: s.name.startsWith("eDP") ? "󰌢" : "󰍹" })
        }
        return rows
    }

    implicitHeight: body.implicitHeight
    height: implicitHeight

    function activate() {
        currentIndex = 0
        list.positionViewAtBeginning()
        forceActiveFocus()
    }

    function select(index) {
        if (index === options.length) {
            canceled()
        } else if (index >= 0 && index < options.length) {
            var target = options[index]
            selected(target.capture, target.output)
        }
    }

    function navigate(delta) {
        currentIndex = Math.max(0, Math.min(options.length, currentIndex + delta))
        if (currentIndex < options.length)
            list.positionViewAtIndex(currentIndex, ListView.Contain)
    }

    onOptionsChanged: currentIndex = Math.min(currentIndex, options.length)

    Keys.onPressed: function(event) {
        switch (event.key) {
        case Qt.Key_Escape:
        case Qt.Key_Backspace:
            canceled(); break
        case Qt.Key_Up:
            navigate(-1); break
        case Qt.Key_Down:
            navigate(1); break
        case Qt.Key_Return:
        case Qt.Key_Enter:
        case Qt.Key_Space:
            select(currentIndex); break
        default:
            // Don't pass text entry/navigation back to the Launcher search.
            break
        }
        event.accepted = true
    }

    Column {
        id: body
        width: parent.width
        spacing: 12

        Text {
            width: parent.width
            text: selector.options.length > 0 ? "Choose which display to record." : "No connected monitors found."
            font.family: Theme.fontMain
            font.pixelSize: 12
            color: Qt.alpha(Theme.white, 0.60)
            wrapMode: Text.WordWrap
        }

        ListView {
            id: list
            width: parent.width
            height: Math.min(count * 58 + Math.max(0, count - 1) * spacing,
                             Math.max(58, selector.availableHeight - 100))
            visible: count > 0
            model: selector.options
            spacing: 8
            clip: true
            interactive: contentHeight > height
            boundsBehavior: Flickable.StopAtBounds
            delegate: Rectangle {
                required property var modelData
                required property int index
                readonly property bool highlighted: selector.currentIndex === index
                width: ListView.view.width
                height: 58
                radius: 14
                color: Qt.alpha(Theme.white, highlighted ? 0.16 : 0.06)
                border.color: highlighted ? Theme.blue : Qt.alpha(Theme.white, 0.12)
                border.width: highlighted ? 2 : 1

                Text {
                    id: monitorIcon
                    anchors.left: parent.left
                    anchors.leftMargin: 15
                    anchors.verticalCenter: parent.verticalCenter
                    text: modelData.icon
                    color: Theme.white
                    font.family: Theme.fontIcons
                    font.pixelSize: 23
                }
                Column {
                    anchors.left: monitorIcon.right
                    anchors.leftMargin: 12
                    anchors.right: parent.right
                    anchors.rightMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 3
                    Text {
                        width: parent.width
                        text: modelData.title
                        color: Theme.white
                        font.family: Theme.fontMain
                        font.pixelSize: 13
                        font.bold: true
                        elide: Text.ElideRight
                    }
                    Text {
                        width: parent.width
                        text: modelData.subtitle
                        color: Qt.alpha(Theme.white, 0.55)
                        font.family: Theme.fontMain
                        font.pixelSize: 11
                        elide: Text.ElideRight
                    }
                }
                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onEntered: selector.currentIndex = index
                    onClicked: selector.select(index)
                }
            }
        }

        Rectangle {
            width: parent.width
            height: 42
            radius: 13
            readonly property bool highlighted: selector.currentIndex === selector.options.length
            color: Qt.alpha(Theme.white, highlighted ? 0.16 : 0.06)
            border.color: highlighted ? Theme.blue : Qt.alpha(Theme.white, 0.12)
            border.width: highlighted ? 2 : 1
            Text {
                anchors.centerIn: parent
                text: "Cancel"
                color: Theme.white
                font.family: Theme.fontMain
                font.pixelSize: 13
                font.bold: true
            }
            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onEntered: selector.currentIndex = selector.options.length
                onClicked: selector.canceled()
            }
        }
    }
}
