import QtQuick
import Quickshell.Services.Mpris
import "." as Local

// Reproductor de música real vía MPRIS (Spotify, mpv, browsers, etc.)
// Toma el primer player activo de Mpris.players. Si quieres priorizar uno
// concreto (p.ej. siempre Spotify si está abierto), filtra por
// player.identity === "Spotify" antes del find().
Local.Card {
    id: root
    implicitWidth: 260
    implicitHeight: 150

    property var player: {
        for (const p of Mpris.players.values) {
            if (p.playbackState !== MprisPlaybackState.Stopped) return p
        }
        return Mpris.players.values.length > 0 ? Mpris.players.values[0] : null
    }

    content: Column {
        anchors.fill: parent
        spacing: 8
        visible: root.player !== null

        Text {
            text: root.player ? (root.player.trackTitle || "Sin reproducción") : ""
            color: "#eef4fb"
            font.pixelSize: 14
            font.weight: Font.Bold
            font.family: "JetBrains Mono Nerd Font"
            elide: Text.ElideRight
            width: parent.width
        }
        Text {
            text: root.player ? (root.player.trackArtist || "") : ""
            color: "#9fb3c8"
            font.pixelSize: 12
            font.family: "JetBrains Mono Nerd Font"
            elide: Text.ElideRight
            width: parent.width
        }

        Row {
            spacing: 18
            anchors.horizontalCenter: parent.horizontalCenter
            topPadding: 8

            Text {
                text: ""
                color: "#eef4fb"; font.pixelSize: 18
                MouseArea { anchors.fill: parent; onClicked: root.player && root.player.previous() }
            }
            Text {
                text: root.player && root.player.isPlaying ? "" : ""
                color: "#eef4fb"; font.pixelSize: 22
                MouseArea { anchors.fill: parent; onClicked: root.player && root.player.togglePlaying() }
            }
            Text {
                text: ""
                color: "#eef4fb"; font.pixelSize: 18
                MouseArea { anchors.fill: parent; onClicked: root.player && root.player.next() }
            }
        }
    }

    // Placeholder cuando no hay ningún reproductor activo
    Text {
        anchors.centerIn: parent
        visible: root.player === null
        text: "Nada sonando"
        color: "#7f93a8"
        font.pixelSize: 13
        font.family: "JetBrains Mono Nerd Font"
    }
}
