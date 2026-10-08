import QtQuick

// A lightweight Settings row; no additional processes, timers or effects.
Rectangle {
    id: row

    property var spec: ({})
    property var values: ({})
    property var paletteTheme: ({ white: "#ffffff", bg0: "#050505", blue: "#61afef", grey1: "#828997", fontMain: "Adwaita Sans" })
    property var paletteGlass: ({ radiusSmall: 10 })
    signal valueEdited(string settingKey, var newValue)

    readonly property bool isToggle: spec.kind === "toggle"
    readonly property bool isColor: spec.kind === "color"
    readonly property bool checkedValue: values && spec.key ? values[spec.key] === true : false

    width: 650
    height: 77
    radius: row.paletteGlass.radiusSmall
    color: Qt.alpha(row.paletteTheme.white, 0.055)
    border.color: Qt.alpha(row.paletteTheme.white, 0.10)
    border.width: 1

    Column {
        anchors.left: parent.left
        anchors.leftMargin: 18
        anchors.right: control.left
        anchors.rightMargin: 14
        anchors.verticalCenter: parent.verticalCenter
        spacing: 5

        Text {
            width: parent.width
            text: row.spec.title || "Setting"
            color: row.paletteTheme.white
            font.family: row.paletteTheme.fontMain
            font.pixelSize: 14
            font.weight: Font.DemiBold
            elide: Text.ElideRight
        }
        Text {
            width: parent.width
            text: row.spec.description || ""
            color: Qt.alpha(row.paletteTheme.white, 0.58)
            font.family: row.paletteTheme.fontMain
            font.pixelSize: 11
            wrapMode: Text.WordWrap
            maximumLineCount: 2
            elide: Text.ElideRight
        }
    }

    Item {
        id: control
        width: row.isToggle ? 62 : 164
        height: 42
        anchors.right: parent.right
        anchors.rightMargin: 17
        anchors.verticalCenter: parent.verticalCenter

        Rectangle {
            id: toggleTrack
            visible: row.isToggle
            width: 51
            height: 29
            radius: height / 2
            anchors.centerIn: parent
            color: row.checkedValue ? row.paletteTheme.blue : Qt.alpha(row.paletteTheme.white, 0.13)
            border.width: 1
            border.color: row.checkedValue ? Qt.lighter(row.paletteTheme.blue, 1.1) : Qt.alpha(row.paletteTheme.white, 0.20)

            Rectangle {
                width: 23
                height: 23
                radius: height / 2
                y: 3
                x: row.checkedValue ? 25 : 3
                color: row.paletteTheme.white
                Behavior on x { NumberAnimation { duration: 120; easing.type: Easing.OutQuad } }
            }
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: row.valueEdited(row.spec.key, !row.checkedValue)
            }
        }

        Rectangle {
            visible: !row.isToggle
            anchors.fill: parent
            radius: row.paletteGlass.radiusSmall
            color: Qt.alpha(row.paletteTheme.white, 0.075)
            border.width: editor.activeFocus ? 2 : 1
            border.color: editor.activeFocus ? row.paletteTheme.blue : Qt.alpha(row.paletteTheme.white, 0.18)

            Rectangle {
                id: preview
                visible: row.isColor
                x: 10
                y: 11
                height: 20
                width: 20
                radius: 6
                border.color: Qt.alpha(row.paletteTheme.white, 0.35)
                border.width: 1
                color: /^#[0-9a-fA-F]{6}$/.test(editor.text) ? editor.text : row.paletteTheme.grey1
            }

            TextInput {
                id: editor
                visible: !row.isToggle
                x: row.isColor ? 39 : 12
                width: parent.width - x - 10
                anchors.verticalCenter: parent.verticalCenter
                color: row.paletteTheme.white
                selectionColor: row.paletteTheme.blue
                selectedTextColor: row.paletteTheme.bg0
                font.pixelSize: 14
                font.family: row.paletteTheme.fontMain
                activeFocusOnTab: true
                clip: true
                selectByMouse: true
                horizontalAlignment: TextInput.AlignHCenter
                text: row.values && row.spec.key && row.values[row.spec.key] !== undefined
                    ? String(row.values[row.spec.key]) : ""
                onTextEdited: row.valueEdited(row.spec.key, text)
            }
        }
    }
}
