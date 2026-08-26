import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell.Services.Mpris
import "." as Local
import "../../"

Local.Card {
    id: root

    implicitWidth: 390 * Theme.scale
    implicitHeight: 110 * Theme.scale

    radius: 28 * Theme.scale

    // ============================================================
    // MPRIS BACKEND
    // ============================================================

    property var playerList:
        (Mpris.players && Mpris.players.values)
        ? Mpris.players.values
        : []

    property var blacklist: [
        "firefox",
        "chromium",
        "brave",
        "mpv",
        "playerctl",
        "kdeconnect"
    ]

    property var activePlayer: {
        if (playerList.length === 0)
            return null

        var fallbackPlayer = null

        for (var i = 0; i < playerList.length; i++) {
            var p = playerList[i]

            if (!p)
                continue

            var fullName =
                (p.identity ? p.identity.toLowerCase() : "")
                + " "
                + (p.busName ? p.busName.toLowerCase() : "")

            // Spotify tiene prioridad
            if (fullName.indexOf("spotify") !== -1)
                return p

            var isBlacklisted = false

            for (var j = 0; j < blacklist.length; j++) {
                if (fullName.indexOf(blacklist[j]) !== -1) {
                    isBlacklisted = true
                    break
                }
            }

            if (!isBlacklisted && fallbackPlayer === null)
                fallbackPlayer = p
        }

        return fallbackPlayer
    }

    property bool isPlayerAvailable:
        activePlayer !== null

    // ============================================================
    // TRACK METADATA
    // ============================================================

    property string songTitle: {
        if (!activePlayer)
            return "Nothing playing"

        var title =
            activePlayer.trackTitle
            || (activePlayer.metadata
                ? activePlayer.metadata["xesam:title"]
                : null)

        return title
            ? String(title)
            : "Unknown track"
    }

    property string songArtist: {
        if (!activePlayer)
            return ""

        var artist =
            activePlayer.trackArtists
            || activePlayer.trackArtist
            || (activePlayer.metadata
                ? activePlayer.metadata["xesam:artist"]
                : null)

        if (Array.isArray(artist))
            return artist.join(", ")

        return artist
            ? String(artist)
            : "Unknown artist"
    }

    property string songArt: {
        if (!activePlayer)
            return ""

        var art =
            activePlayer.trackArtUrl
            || (activePlayer.metadata
                ? activePlayer.metadata["mpris:artUrl"]
                : null)

        return art
            ? String(art)
            : ""
    }

    property bool isPlaying:
        activePlayer
        ? (
            activePlayer.playbackState === 1
            || activePlayer.playbackStatus === "Playing"
        )
        : false

    // ============================================================
    // TRACK PROGRESS
    // ============================================================

    property real trackPosition: 0
    property real trackLength: 1

    property bool isUserSeeking: false

    property real progress:
        trackLength > 0
        ? Math.max(
            0,
            Math.min(
                1,
                trackPosition / trackLength
            )
        )
        : 0

    Timer {
        id: positionPoller

        interval: 500
        repeat: true
        running: root.isPlayerAvailable
        triggeredOnStart: true

        onTriggered: {
            if (!root.activePlayer || root.isUserSeeking)
                return

            root.trackPosition =
                root.activePlayer.position || 0

            root.trackLength =
                root.activePlayer.length || 1
        }
    }

    onActivePlayerChanged: {
        trackPosition = 0
        trackLength = 1

        if (activePlayer) {
            trackPosition =
                activePlayer.position || 0

            trackLength =
                activePlayer.length || 1
        }
    }

    // ============================================================
    // CONTENT
    // ============================================================

    content: Item {
        anchors.fill: parent

        // ========================================================
        // NOTHING PLAYING
        // ========================================================

        Item {
            anchors.fill: parent
            visible: !root.isPlayerAvailable

            Row {
                anchors.centerIn: parent

                spacing: 10 * Theme.scale

                Text {
                    text: "󰎆"

                    color:
                        Qt.alpha(
                            Theme.white,
                            0.45
                        )

                    font.family:
                        Theme.fontIcons

                    font.pixelSize:
                        18 * Theme.scale

                    anchors.verticalCenter:
                        parent.verticalCenter
                }

                Text {
                    text: "Nothing playing"

                    color:
                        Qt.alpha(
                            Theme.white,
                            0.55
                        )

                    font.family:
                        Theme.fontMain

                    font.pixelSize:
                        12 * Theme.scale

                    anchors.verticalCenter:
                        parent.verticalCenter
                }
            }
        }

        // ========================================================
        // ACTIVE PLAYER
        // ========================================================

        Item {
            anchors.fill: parent
            visible: root.isPlayerAvailable

            // ====================================================
            // ALBUM ART
            // ====================================================

            Rectangle {
                id: artwork

                width: 76 * Theme.scale
                height: 76 * Theme.scale

                radius: width / 2

                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter

                color: Qt.alpha(Theme.white, 0.10)

                border.width: 1
                border.color: Qt.alpha(Theme.white, 0.12)

                Image {
                    id: albumImageSource

                    anchors.fill: parent

                    source: root.songArt
                    fillMode: Image.PreserveAspectCrop

                    asynchronous: true
                    cache: true

                    visible: false
                }

                Rectangle {
                    id: albumMask

                    anchors.fill: parent
                    radius: width / 2

                    visible: false
                }

                OpacityMask {
                    anchors.fill: parent

                    source: albumImageSource
                    maskSource: albumMask

                    visible:
                        root.songArt !== ""
                        && albumImageSource.status === Image.Ready
                }

                Text {
                    anchors.centerIn: parent

                    visible:
                        root.songArt === ""
                        || albumImageSource.status !== Image.Ready

                    text: "󰎆"

                    font.family: Theme.fontIcons
                    font.pixelSize: 28 * Theme.scale

                    color: Theme.white
                }
            }

            // ====================================================
            // RIGHT SIDE
            // ====================================================

            Item {
                id: playerContent

                anchors.left: artwork.right
                anchors.leftMargin: 16 * Theme.scale

                anchors.right: parent.right

                anchors.top: parent.top
                anchors.bottom: parent.bottom

                // ================================================
                // METADATA
                // ================================================

                Column {
                    id: metadata

                    anchors.left: parent.left
                    anchors.right: parent.right

                    anchors.top: parent.top
                    anchors.topMargin: 8 * Theme.scale

                    spacing: 2 * Theme.scale

                    Text {
                        width: parent.width

                        text: root.songTitle

                        color: Theme.white

                        font.family:
                            Theme.fontMain

                        font.pixelSize:
                            14 * Theme.scale

                        font.weight:
                            Font.Bold

                        elide:
                            Text.ElideRight
                    }

                    Text {
                        width: parent.width

                        text: root.songArtist

                        color:
                            Qt.alpha(
                                Theme.white,
                                0.58
                            )

                        font.family:
                            Theme.fontMain

                        font.pixelSize:
                            11 * Theme.scale

                        elide:
                            Text.ElideRight
                    }
                }

                // ================================================
                // CONTROLS + PROGRESS
                // ================================================

                RowLayout {
                    id: bottomRow

                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.rightMargin: 14 * Theme.scale

                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 9 * Theme.scale

                    spacing: 10 * Theme.scale

                    // --------------------------------------------
                    // PREVIOUS
                    // --------------------------------------------

                    Item {
                        Layout.preferredWidth:
                            24 * Theme.scale

                        Layout.preferredHeight:
                            24 * Theme.scale

                        Layout.alignment:
                            Qt.AlignVCenter

                        Text {
                            anchors.centerIn: parent

                            text: "󰒮"

                            font.family:
                                Theme.fontIcons

                            font.pixelSize:
                                16 * Theme.scale

                            color:
                                Qt.alpha(
                                    Theme.white,
                                    0.85
                                )
                        }

                        MouseArea {
                            anchors.fill: parent

                            cursorShape:
                                Qt.PointingHandCursor

                            onClicked: {
                                if (root.activePlayer)
                                    root.activePlayer.previous()
                            }
                        }
                    }

                    // --------------------------------------------
                    // PLAY / PAUSE
                    // --------------------------------------------

                    Item {
                        Layout.preferredWidth:
                            24 * Theme.scale

                        Layout.preferredHeight:
                            24 * Theme.scale

                        Layout.alignment:
                            Qt.AlignVCenter

                        Text {
                            anchors.centerIn: parent

                            text:
                                root.isPlaying
                                ? "󰏤"
                                : "󰐊"

                            font.family:
                                Theme.fontIcons

                            font.pixelSize:
                                17 * Theme.scale

                            color:
                                Theme.white
                        }

                        MouseArea {
                            anchors.fill: parent

                            cursorShape:
                                Qt.PointingHandCursor

                            onClicked: {
                                if (!root.activePlayer)
                                    return

                                if (root.isPlaying)
                                    root.activePlayer.pause()
                                else
                                    root.activePlayer.play()
                            }
                        }
                    }

                    // --------------------------------------------
                    // NEXT
                    // --------------------------------------------

                    Item {
                        Layout.preferredWidth:
                            24 * Theme.scale

                        Layout.preferredHeight:
                            24 * Theme.scale

                        Layout.alignment:
                            Qt.AlignVCenter

                        Text {
                            anchors.centerIn: parent

                            text: "󰒭"

                            font.family:
                                Theme.fontIcons

                            font.pixelSize:
                                16 * Theme.scale

                            color:
                                Qt.alpha(
                                    Theme.white,
                                    0.85
                                )
                        }

                        MouseArea {
                            anchors.fill: parent

                            cursorShape:
                                Qt.PointingHandCursor

                            onClicked: {
                                if (root.activePlayer)
                                    root.activePlayer.next()
                            }
                        }
                    }

                    // Pequeño espacio extra entre controles y barra
                    Item {
                        Layout.preferredWidth: 4 * Theme.scale
                        Layout.preferredHeight: 1
                    }

                    // ============================================
                    // REAL MPRIS PROGRESS BAR
                    // ============================================

                    MouseArea {
                        id: progressArea

                        Layout.preferredWidth: 160 * Theme.scale
                        Layout.minimumWidth: 160 * Theme.scale
                        Layout.maximumWidth: 160 * Theme.scale

                        Layout.preferredHeight:
                            24 * Theme.scale

                        Layout.alignment:
                            Qt.AlignVCenter

                        cursorShape:
                            Qt.PointingHandCursor

                        function seekToMouse() {
                            if (
                                !root.activePlayer
                                || root.trackLength <= 0
                            )
                                return

                            var percent =
                                Math.max(
                                    0,
                                    Math.min(
                                        1,
                                        mouseX / width
                                    )
                                )

                            var newPosition =
                                percent
                                * root.trackLength

                            root.trackPosition =
                                newPosition

                            root.activePlayer.position =
                                newPosition
                        }

                        onPressed: {
                            root.isUserSeeking = true
                            seekToMouse()
                        }

                        onPositionChanged: {
                            if (pressed)
                                seekToMouse()
                        }

                        onReleased: {
                            if (root.activePlayer) {
                                root.activePlayer.position =
                                    root.trackPosition
                            }

                            root.isUserSeeking = false
                        }

                        onCanceled:
                            root.isUserSeeking = false

                        Rectangle {
                            anchors.left: parent.left
                            anchors.right: parent.right

                            anchors.verticalCenter:
                                parent.verticalCenter

                            height: 3 * Theme.scale

                            radius:
                                height / 2

                            color:
                                Qt.alpha(
                                    Theme.white,
                                    0.18
                                )

                            Rectangle {
                                height:
                                    parent.height

                                width:
                                    parent.width
                                    * root.progress

                                radius:
                                    parent.radius

                                color:
                                    Qt.alpha(
                                        Theme.white,
                                        0.90
                                    )

                                Behavior on width {
                                    enabled:
                                        !root.isUserSeeking

                                    NumberAnimation {
                                        duration: 500
                                        easing.type:
                                            Easing.Linear
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}