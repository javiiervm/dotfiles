import QtQuick
import QtQuick.Layouts
import Quickshell.Services.Mpris
import "." as Local
import "../../"

Local.Card {
    id: root
    
    implicitWidth: 260 * Theme.scale
    implicitHeight: 95 * Theme.scale // Reducida a casi la mitad de altura

    property var player: {
        for (const p of Mpris.players.values) {
            if (p.playbackState !== MprisPlaybackState.Stopped) return p
        }
        return Mpris.players.values.length > 0 ? Mpris.players.values[0] : null
    }

    property string songTitle: player ? (player.trackTitle || "No media") : "No media"
    property string songArtist: player ? (player.trackArtist || "") : ""
    property bool isPlaying: player ? (player.playbackState === MprisPlaybackState.Playing) : false

    content: Item {
        anchors.fill: parent
        anchors.margins: 10 * Theme.scale 

        ColumnLayout {
            anchors.centerIn: parent
            spacing: 8 * Theme.scale
            width: parent.width
            visible: root.player !== null

            // Textos centrados (sin carátula)
            ColumnLayout {
                Layout.alignment: Qt.AlignHCenter
                spacing: 2 * Theme.scale
                
                Text { 
                    text: root.songTitle
                    color: Theme.white
                    font.family: Theme.fontMain
                    font.pixelSize: 13 * Theme.scale
                    font.bold: true
                    elide: Text.ElideRight
                    horizontalAlignment: Text.AlignHCenter
                    Layout.alignment: Qt.AlignHCenter
                    Layout.maximumWidth: 230 * Theme.scale
                }
                Text { 
                    text: root.songArtist
                    color: Theme.grey1
                    font.family: Theme.fontMain
                    font.pixelSize: 11 * Theme.scale
                    elide: Text.ElideRight
                    horizontalAlignment: Text.AlignHCenter
                    Layout.alignment: Qt.AlignHCenter
                    Layout.maximumWidth: 230 * Theme.scale
                }
            }

            // Controles de reproducción compactos y centrados
            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                spacing: 20 * Theme.scale

                Text { 
                    text: "󰒮"
                    font.family: Theme.fontIcons
                    font.pixelSize: 16 * Theme.scale
                    color: Theme.white
                    MouseArea { 
                        anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                        onClicked: if (root.player) root.player.previous() 
                    } 
                }
                Rectangle {
                    width: 28 * Theme.scale
                    height: 28 * Theme.scale
                    radius: width / 2
                    color: Theme.white
                    Text { 
                        anchors.centerIn: parent
                        text: root.isPlaying ? "󰏤" : "󰐊"
                        font.family: Theme.fontIcons
                        font.pixelSize: 14 * Theme.scale
                        color: Theme.bg0 
                    }
                    MouseArea { 
                        anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                        onClicked: if (root.player) root.player.togglePlaying()
                    }
                }
                Text { 
                    text: "󰒭"
                    font.family: Theme.fontIcons
                    font.pixelSize: 16 * Theme.scale
                    color: Theme.white
                    MouseArea { 
                        anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                        onClicked: if (root.player) root.player.next() 
                    } 
                }
            }
        }

        // Estado sin reproducción
        Text {
            anchors.centerIn: parent
            visible: root.player === null
            text: "Nothing playing"
            color: Theme.grey1
            font.pixelSize: 12 * Theme.scale
            font.family: Theme.fontMain
        }
    }
}