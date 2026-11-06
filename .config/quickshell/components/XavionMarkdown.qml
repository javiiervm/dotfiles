import QtQuick

// Markdown renderer shared by the Launcher chat. Fenced code is kept as
// selectable plain text, in dedicated blocks with language and copy controls.
// No external clipboard process or independent window is required.
Item {
    id: renderer

    property string markdown: ""
    property bool streaming: false
    property color textColor: "#f3f5fb"
    property color mutedColor: "#abb7ca"
    property color accentStart: "#F52765"
    property color accentMid: "#FF4A3D"
    property color accentEnd: "#FF8A18"
    property string bodyFont: "sans-serif"
    property string codeFont: "monospace"
    property int bodySize: 13

    implicitHeight: sectionsColumn.implicitHeight
    height: implicitHeight

    // Parse complete and in-progress fenced blocks. Streaming can stop
    // temporarily before the closing fence; keep displaying that code.
    function parseMarkdown(source) {
        const lines = String(source || "").split("\n")
        const result = []
        let normal = []
        let code = []
        let fence = ""
        let language = ""

        function flushText() {
            const value = normal.join("\n")
            if (value.trim().length)
                result.push({kind: "text", content: value})
            normal = []
        }
        function flushCode() {
            result.push({kind: "code", content: code.join("\n"), language: language})
            code = []
            fence = ""
            language = ""
        }

        for (let i = 0; i < lines.length; ++i) {
            const line = lines[i]
            if (!fence.length) {
                const start = line.match(/^[ \t]{0,3}(`{3,}|~{3,})[ \t]*([^ \t`~]*)[^\n]*$/)
                if (start) {
                    flushText()
                    fence = start[1]
                    language = start[2] || ""
                } else {
                    normal.push(line)
                }
            } else {
                const end = line.match(/^[ \t]{0,3}(`{3,}|~{3,})[ \t]*$/)
                if (end && end[1][0] === fence[0] && end[1].length >= fence.length)
                    flushCode()
                else
                    code.push(line)
            }
        }
        if (fence.length)
            flushCode()
        flushText()
        return result
    }

    readonly property var sections: parseMarkdown(markdown)

    Column {
        id: sectionsColumn
        width: renderer.width
        spacing: 10

        Repeater {
            model: renderer.sections

            Item {
                id: section
                required property var modelData
                readonly property bool isCode: modelData.kind === "code"

                width: sectionsColumn.width
                height: isCode ? codeBlock.height : prose.implicitHeight

                TextEdit {
                    id: prose
                    visible: !section.isCode
                    width: parent.width
                    height: implicitHeight
                    text: section.isCode ? "" : section.modelData.content
                    color: renderer.textColor
                    font.family: renderer.bodyFont
                    font.pixelSize: renderer.bodySize
                    wrapMode: TextEdit.Wrap
                    textFormat: TextEdit.MarkdownText
                    readOnly: true
                    selectByMouse: true
                    selectionColor: Qt.alpha(renderer.accentMid, 0.36)
                    // Keep markdown hyperlinks clickable without stealing scroll.
                    onLinkActivated: function(link) { Qt.openUrlExternally(link) }
                }

                Rectangle {
                    id: codeBlock
                    visible: section.isCode
                    width: section.width
                    height: codeHeader.height + codeViewport.height + 18
                    radius: 13
                    color: Qt.rgba(0.055, 0.082, 0.126, 0.90)
                    border.width: 1
                    border.color: Qt.alpha(renderer.accentMid, 0.30)
                    clip: true
                    property bool copied: false

                    Rectangle {
                        id: codeHeader
                        width: parent.width
                        height: 36
                        color: Qt.alpha(renderer.accentMid, 0.085)

                        Rectangle {
                            anchors.left: parent.left
                            anchors.leftMargin: 12
                            anchors.verticalCenter: parent.verticalCenter
                            width: 6
                            height: 6
                            radius: 3
                            color: renderer.accentStart
                        }
                        Text {
                            anchors.left: parent.left
                            anchors.leftMargin: 26
                            anchors.verticalCenter: parent.verticalCenter
                            text: section.modelData.language || "Code"
                            color: renderer.mutedColor
                            font.family: renderer.bodyFont
                            font.pixelSize: 11
                            font.bold: true
                        }
                        Rectangle {
                            id: copyButton
                            anchors.right: parent.right
                            anchors.rightMargin: 8
                            anchors.verticalCenter: parent.verticalCenter
                            width: 74
                            height: 25
                            radius: 8
                            color: copyArea.containsMouse
                                   ? Qt.alpha(renderer.accentMid, 0.22)
                                   : Qt.alpha("white", 0.07)
                            border.width: 1
                            border.color: Qt.alpha("white", 0.12)
                            Text {
                                anchors.centerIn: parent
                                text: codeBlock.copied ? "Copied!" : "Copy code"
                                color: codeBlock.copied ? renderer.accentEnd : renderer.textColor
                                font.family: renderer.bodyFont
                                font.pixelSize: 10
                            }
                            MouseArea {
                                id: copyArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    codeText.selectAll()
                                    codeText.copy()
                                    codeText.deselect()
                                    codeBlock.copied = true
                                    copiedTimer.restart()
                                }
                            }
                            Timer {
                                id: copiedTimer
                                interval: 1500
                                onTriggered: codeBlock.copied = false
                            }
                        }
                    }

                    Flickable {
                        id: codeViewport
                        x: 13
                        y: codeHeader.height + 9
                        width: Math.max(0, codeBlock.width - 26)
                        height: Math.max(19, codeText.implicitHeight + 2)
                        contentWidth: Math.max(width, codeText.implicitWidth + 6)
                        contentHeight: height
                        clip: true
                        flickableDirection: Flickable.HorizontalFlick
                        boundsBehavior: Flickable.StopAtBounds
                        interactive: contentWidth > width

                        TextEdit {
                            id: codeText
                            width: Math.max(codeViewport.width, implicitWidth)
                            height: implicitHeight
                            text: section.isCode ? section.modelData.content : ""
                            color: renderer.textColor
                            font.family: renderer.codeFont
                            font.pixelSize: 12
                            wrapMode: TextEdit.NoWrap
                            textFormat: TextEdit.PlainText
                            readOnly: true
                            selectByMouse: true
                            selectionColor: Qt.alpha(renderer.accentMid, 0.42)
                        }
                    }
                }
            }
        }

        Text {
            visible: renderer.streaming
            height: visible ? implicitHeight : 0
            text: "▌"
            color: renderer.accentMid
            font.family: renderer.bodyFont
            font.pixelSize: renderer.bodySize
            SequentialAnimation on opacity {
                running: renderer.streaming
                loops: Animation.Infinite
                NumberAnimation { from: 1; to: 0.32; duration: 500 }
                NumberAnimation { from: 0.32; to: 1; duration: 500 }
            }
        }
    }
}
