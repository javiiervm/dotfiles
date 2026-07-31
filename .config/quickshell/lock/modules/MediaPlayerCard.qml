import QtQuick
import Quickshell.Services.Mpris
import "." as Local
import "../../"

Local.Card {
    id: root
    implicitWidth: 260
    implicitHeight: 150

    property var player: {
        for (const p of Mpris.players.values) {
            if (p.playbackState !== MprisPlaybackState.Stopped) return p
        }
        return Mpris.players.values.length > 0 ? Mpris.players.values[0] : null //[cite: 18]
    }

    content: Column {
        anchors.fill: parent
        spacing: 8
        visible: root.player !== null

        Text {
            text: root.player ? (root.player.trackTitle || "No media") : "" //[cite: 18]
            color: Theme.white
            font.pixelSize: 14
            font.weight: Font.Bold
            font.family: Theme.fontMain
            elide: Text.ElideRight
            width: parent.width
        }
        Text {
            text: root.player ? (root.player.trackArtist || "") : "" //[cite: 18]
            color: Theme.grey1
            font.pixelSize: 12
            font.family: Theme.fontMain
            elide: Text.ElideRight
            width: parent.width
        }

        Row {
            spacing: 18
            anchors.horizontalCenter: parent.horizontalCenter
            topPadding: 8

            Text {
                text: "󰒮"
                color: Theme.white; font.pixelSize: 18; font.family: Theme.fontIcons //[cite: 18]
                MouseArea { anchors.fill: parent; onClicked: root.player && root.player.previous() }
            }
            Text {
                text: root.player && root.player.isPlaying ? "󰏤" : "󰐊"
                color: Theme.white; font.pixelSize: 22; font.family: Theme.fontIcons //[cite: 18]
                MouseArea { anchors.fill: parent; onClicked: root.player && root.player.togglePlaying() }
            }
            Text {
                text: "󰒭"
                color: Theme.white; font.pixelSize: 18; font.family: Theme.fontIcons //[cite: 18]
                MouseArea { anchors.fill: parent; onClicked: root.player && root.player.next() }
            }
        }
    }

    Text {
        anchors.centerIn: parent
        visible: root.player === null
        text: "Nothing playing"
        color: Theme.grey1
        font.pixelSize: 13
        font.family: Theme.fontMain
    }
}