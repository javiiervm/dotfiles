import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell.Services.Mpris
import Quickshell.Io
import "." as Local
import "../../"

Local.Card {
    id: root

    implicitWidth: 390 * Theme.scale
    implicitHeight: 110 * Theme.scale
    radius: 28 * Theme.scale

    // ============================================================
    // MPRIS BACKEND — MISMA LÓGICA QUE LA DYNAMIC ISLAND
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

            // Spotify tiene prioridad, igual que en la isla.
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
            || (
                activePlayer.metadata
                ? activePlayer.metadata["xesam:title"]
                : null
            )

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
            || (
                activePlayer.metadata
                ? activePlayer.metadata["xesam:artist"]
                : null
            )

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
            || (
                activePlayer.metadata
                ? activePlayer.metadata["mpris:artUrl"]
                : null
            )

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

    property bool isShuffle:
        activePlayer
        ? (activePlayer.shuffle || false)
        : false

    // ============================================================
    // LOOP STATUS — MISMO SISTEMA QUE LA DYNAMIC ISLAND
    // ============================================================

    property string liveLoopStatus: "None"

    function playerBusShort() {
        if (
            !root.activePlayer
            || !root.activePlayer.busName
        )
            return ""

        return root.activePlayer.busName.replace(
            "org.mpris.MediaPlayer2.",
            ""
        )
    }

    Process {
        id: loopStatusProc

        stdout: SplitParser {
            onRead: function(data) {
                var value = data.trim()

                if (
                    value === "Track"
                    || value === "Playlist"
                    || value === "None"
                ) {
                    root.liveLoopStatus = value
                }
            }
        }
    }

    function pollLoopStatus() {
        var bus = root.playerBusShort()

        if (bus === "")
            return

        loopStatusProc.command = [
            "bash",
            "-c",
            "playerctl -p "
                + bus
                + " loop 2>/dev/null"
        ]

        loopStatusProc.running = true
    }

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
            if (
                root.activePlayer
                && !root.isUserSeeking
            ) {
                root.trackPosition =
                    root.activePlayer.position || 0

                root.trackLength =
                    root.activePlayer.length || 1
            }

            root.pollLoopStatus()
        }
    }

    onActivePlayerChanged: {
        trackPosition = 0
        trackLength = 1
        liveLoopStatus = "None"

        if (activePlayer) {
            trackPosition =
                activePlayer.position || 0

            trackLength =
                activePlayer.length || 1
        }

        pollLoopStatus()
    }

    function formatTime(timeInSeconds) {
        if (
            !timeInSeconds
            || timeInSeconds <= 0
        )
            return "0:00"

        var totalSeconds =
            Math.floor(timeInSeconds)

        var minutes =
            Math.floor(totalSeconds / 60)

        var seconds =
            totalSeconds % 60

        return minutes
            + ":"
            + (
                seconds < 10
                ? "0"
                : ""
            )
            + seconds
    }

    // ============================================================
    // PALETA DINÁMICA DE LA CARÁTULA
    // ============================================================

    property color artworkPalettePrimary: "#d8d8d8"
    property color artworkPaletteSecondary: "#eeeeee"
    property color artworkPaletteAccent: "#ffffff"

    onSongArtChanged:
        updateArtworkPalette()

    Process {
        id: artworkPaletteProc
        property string requestedArt: ""

        stdout: SplitParser {
            onRead: function(data) {
                if (
                    artworkPaletteProc.requestedArt
                    !== root.songArt
                ) {
                    return
                }

                var colors =
                    data.trim().split(";")

                var hexRe =
                    /^#[0-9a-fA-F]{6}$/

                if (
                    colors.length < 3
                    || !hexRe.test(colors[0])
                    || !hexRe.test(colors[1])
                    || !hexRe.test(colors[2])
                ) {
                    return
                }

                root.artworkPalettePrimary =
                    colors[0]

                root.artworkPaletteSecondary =
                    colors[1]

                root.artworkPaletteAccent =
                    colors[2]

                progressWave.requestPaint()
            }
        }
    }

    function updateArtworkPalette() {
        var art = root.songArt

        if (
            !art
            || art === ""
        ) {
            artworkPalettePrimary = "#d8d8d8"
            artworkPaletteSecondary = "#eeeeee"
            artworkPaletteAccent = "#ffffff"
            return
        }

        if (artworkPaletteProc.running)
            artworkPaletteProc.running = false

        artworkPaletteProc.requestedArt = art

        artworkPaletteProc.command = [
            "python3",
            "/home/javier/.config/quickshell/scripts/cava_color.py",
            "--palette",
            art
        ]

        Qt.callLater(
            function() {
                if (
                    artworkPaletteProc.requestedArt
                    === root.songArt
                ) {
                    artworkPaletteProc.running = true
                }
            }
        )
    }

    // ============================================================
    // CONTENT — LAYOUT REAL ADAPTADO A Local.Card
    // ============================================================

    content: Item {
        id: cardContent
        anchors.fill: parent

        // Local.Card deja padding alrededor de `content`.
        // En vez de diseñar dentro de ese rectángulo reducido,
        // recuperamos casi todo el tamaño real de la tarjeta y dejamos
        // únicamente un borde de glass de ~2 px alrededor.
        Item {
            id: playerSurface

            width: root.width - 4 * Theme.scale
            height: root.height - 4 * Theme.scale

            anchors.centerIn: parent

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
                        color: Qt.alpha(Theme.white, 0.45)
                        font.family: Theme.fontIcons
                        font.pixelSize: 18 * Theme.scale
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Text {
                        text: "Nothing playing"
                        color: Qt.alpha(Theme.white, 0.58)
                        font.family: Theme.fontMain
                        font.pixelSize: 12 * Theme.scale
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
            }

            // ========================================================
            // ACTIVE PLAYER
            // ========================================================

            Item {
                id: activePlayerView
                anchors.fill: parent
                visible: root.isPlayerAvailable

                // ----------------------------------------------------
                // FULL-BLEED ARTWORK
                // ----------------------------------------------------

                Image {
                    id: backgroundArtworkSource
                    anchors.fill: parent

                    source: root.songArt
                    fillMode: Image.PreserveAspectCrop

                    asynchronous: true
                    cache: true
                    smooth: true
                    mipmap: true
                    retainWhileLoading: true

                    sourceSize.width: Math.ceil(playerSurface.width)
                    sourceSize.height: Math.ceil(playerSurface.height)

                    visible: false
                }

                Rectangle {
                    id: backgroundMask
                    anchors.fill: parent

                    radius: Math.max(
                        0,
                        root.radius - 2 * Theme.scale
                    )

                    color: "white"
                    visible: false
                }

                OpacityMask {
                    anchors.fill: parent
                    source: backgroundArtworkSource
                    maskSource: backgroundMask
                    cached: false

                    visible:
                        root.songArt !== ""
                        && backgroundArtworkSource.status === Image.Ready
                }

                // Oscurecimiento global.
                Rectangle {
                    anchors.fill: parent

                    radius: Math.max(
                        0,
                        root.radius - 2 * Theme.scale
                    )

                    color: "#000000"
                    opacity: root.songArt !== "" ? 0.47 : 0.22
                }

                // Metadata necesita algo más de contraste que los controles.
                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top

                    height: 42 * Theme.scale

                    radius: Math.max(
                        0,
                        root.radius - 2 * Theme.scale
                    )

                    gradient: Gradient {
                        GradientStop {
                            position: 0.0
                            color: Qt.rgba(0, 0, 0, 0.34)
                        }

                        GradientStop {
                            position: 1.0
                            color: Qt.rgba(0, 0, 0, 0.00)
                        }
                    }
                }

                // ----------------------------------------------------
                // ZONA 1 — METADATA
                // ----------------------------------------------------

                Column {
                    id: metadata

                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top

                    anchors.leftMargin: 17 * Theme.scale
                    anchors.rightMargin: 17 * Theme.scale
                    anchors.topMargin: 8 * Theme.scale

                    spacing: 1 * Theme.scale

                    Text {
                        width: parent.width

                        text: root.songTitle
                        color: Theme.white

                        font.family: Theme.fontMain
                        font.pixelSize: 14 * Theme.scale
                        font.weight: Font.Bold

                        elide: Text.ElideRight
                        maximumLineCount: 1

                        style: Text.Raised
                        styleColor: Qt.rgba(0, 0, 0, 0.38)
                    }

                    Text {
                        width: parent.width

                        text: root.songArtist
                        color: Qt.alpha(Theme.white, 0.74)

                        font.family: Theme.fontMain
                        font.pixelSize: 10.5 * Theme.scale

                        elide: Text.ElideRight
                        maximumLineCount: 1

                        style: Text.Raised
                        styleColor: Qt.rgba(0, 0, 0, 0.32)
                    }
                }

                // ----------------------------------------------------
                // ZONA 2 — CONTROLES
                // ----------------------------------------------------

                RowLayout {
                    id: playbackControls

                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.verticalCenterOffset: 4 * Theme.scale

                    height: 38 * Theme.scale
                    spacing: 10 * Theme.scale

                    // Shuffle
                    Item {
                        Layout.preferredWidth: 20 * Theme.scale
                        Layout.preferredHeight: 26 * Theme.scale
                        Layout.alignment: Qt.AlignVCenter

                        Text {
                            anchors.centerIn: parent

                            text: "󰒟"
                            font.family: Theme.fontIcons
                            font.pixelSize: 14 * Theme.scale

                            color:
                                root.isShuffle
                                ? Theme.white
                                : Qt.alpha(Theme.white, 0.48)

                            style: Text.Raised
                            styleColor: Qt.rgba(0, 0, 0, 0.30)
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor

                            onClicked: {
                                if (root.activePlayer)
                                    root.activePlayer.shuffle =
                                        !root.activePlayer.shuffle
                            }
                        }
                    }

                    // Previous
                    Item {
                        Layout.preferredWidth: 34 * Theme.scale
                        Layout.preferredHeight: 34 * Theme.scale
                        Layout.alignment: Qt.AlignVCenter

                        Rectangle {
                            anchors.centerIn: parent

                            width: 32 * Theme.scale
                            height: 32 * Theme.scale
                            radius: width / 2

                            color: Qt.rgba(0, 0, 0, 0.30)

                            Text {
                                anchors.centerIn: parent

                                text: "󰒮"
                                font.family: Theme.fontIcons
                                font.pixelSize: 17 * Theme.scale
                                color: Theme.white
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor

                            onClicked: {
                                if (root.activePlayer)
                                    root.activePlayer.previous()
                            }
                        }
                    }

                    // Play / Pause
                    Item {
                        Layout.preferredWidth: 40 * Theme.scale
                        Layout.preferredHeight: 40 * Theme.scale
                        Layout.alignment: Qt.AlignVCenter

                        Rectangle {
                            anchors.centerIn: parent

                            width: 38 * Theme.scale
                            height: 38 * Theme.scale
                            radius: width / 2

                            color: Qt.rgba(0, 0, 0, 0.33)

                            Text {
                                anchors.centerIn: parent

                                text:
                                    root.isPlaying
                                    ? "󰏤"
                                    : "󰐊"

                                font.family: Theme.fontIcons
                                font.pixelSize: 19 * Theme.scale
                                color: Theme.white
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor

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

                    // Next
                    Item {
                        Layout.preferredWidth: 34 * Theme.scale
                        Layout.preferredHeight: 34 * Theme.scale
                        Layout.alignment: Qt.AlignVCenter

                        Rectangle {
                            anchors.centerIn: parent

                            width: 32 * Theme.scale
                            height: 32 * Theme.scale
                            radius: width / 2

                            color: Qt.rgba(0, 0, 0, 0.30)

                            Text {
                                anchors.centerIn: parent

                                text: "󰒭"
                                font.family: Theme.fontIcons
                                font.pixelSize: 17 * Theme.scale
                                color: Theme.white
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor

                            onClicked: {
                                if (root.activePlayer)
                                    root.activePlayer.next()
                            }
                        }
                    }

                    // Repeat
                    Item {
                        Layout.preferredWidth: 20 * Theme.scale
                        Layout.preferredHeight: 26 * Theme.scale
                        Layout.alignment: Qt.AlignVCenter

                        Text {
                            anchors.centerIn: parent

                            text:
                                root.liveLoopStatus === "Track"
                                ? "󰑘"
                                : "󰑖"

                            font.family: Theme.fontIcons
                            font.pixelSize: 14 * Theme.scale

                            color:
                                root.liveLoopStatus !== "None"
                                ? Theme.white
                                : Qt.alpha(Theme.white, 0.48)

                            style: Text.Raised
                            styleColor: Qt.rgba(0, 0, 0, 0.30)
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor

                            onClicked: {
                                if (!root.activePlayer)
                                    return

                                var current = root.liveLoopStatus
                                var next = "None"

                                if (current === "None")
                                    next = "Playlist"
                                else if (current === "Playlist")
                                    next = "Track"
                                else
                                    next = "None"

                                root.liveLoopStatus = next
                                root.activePlayer.loopStatus = next
                            }
                        }
                    }
                }

                // ----------------------------------------------------
                // ZONA 3 — PROGRESO
                // ----------------------------------------------------

                RowLayout {
                    id: progressRow

                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom

                    anchors.leftMargin: 14 * Theme.scale
                    anchors.rightMargin: 14 * Theme.scale
                    anchors.bottomMargin: 6 * Theme.scale

                    spacing: 5 * Theme.scale

                    // Tiempo actual
                    Item {
                        Layout.preferredWidth: 31 * Theme.scale
                        Layout.preferredHeight: 27 * Theme.scale
                        Layout.alignment: Qt.AlignVCenter

                        Text {
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.verticalCenterOffset: 1 * Theme.scale

                            text: root.formatTime(root.trackPosition)

                            color: Qt.alpha(Theme.white, 0.82)

                            font.family: Theme.fontMain
                            font.pixelSize: 9 * Theme.scale
                            font.bold: true

                            style: Text.Raised
                            styleColor: Qt.rgba(0, 0, 0, 0.36)
                        }
                    }

                    // Barra + ondas + seek.
                    MouseArea {
                        id: progressArea

                        Layout.fillWidth: true
                        Layout.preferredHeight: 27 * Theme.scale
                        Layout.alignment: Qt.AlignVCenter

                        cursorShape: Qt.PointingHandCursor

                        property real wavePhase: 0
                        property real visualProgress: root.progress

                        property real thumbRadius:
                            root.isUserSeeking
                            ? 6.4 * Theme.scale
                            : 5.6 * Theme.scale

                        property real haloRadius:
                            root.isUserSeeking
                            ? 9.5 * Theme.scale
                            : 8.0 * Theme.scale

                        property real glowRadius:
                            haloRadius + 4.8 * Theme.scale

                        property real edgePadding:
                            glowRadius + 1.0 * Theme.scale

                        Behavior on visualProgress {
                            enabled: !root.isUserSeeking

                            NumberAnimation {
                                duration: 420
                                easing.type: Easing.Linear
                            }
                        }

                        Timer {
                            id: progressWaveTimer

                            interval: 50
                            repeat: true

                            running:
                                root.isPlayerAvailable
                                && root.isPlaying

                            onTriggered: {
                                progressArea.wavePhase += 0.085

                                if (progressArea.wavePhase > 1000000)
                                    progressArea.wavePhase = 0

                                progressWave.requestPaint()
                            }
                        }

                        Connections {
                            target: root

                            function onIsPlayingChanged() {
                                progressWave.requestPaint()
                            }

                            function onArtworkPalettePrimaryChanged() {
                                progressWave.requestPaint()
                            }

                            function onArtworkPaletteSecondaryChanged() {
                                progressWave.requestPaint()
                            }

                            function onArtworkPaletteAccentChanged() {
                                progressWave.requestPaint()
                            }
                        }

                        onVisualProgressChanged: progressWave.requestPaint()
                        onWidthChanged: progressWave.requestPaint()
                        onHeightChanged: progressWave.requestPaint()

                        function seekToMouse() {
                            if (!root.activePlayer || root.trackLength <= 0)
                                return

                            var left = edgePadding
                            var right = Math.max(
                                left + 1,
                                width - edgePadding
                            )

                            var percent =
                                (mouseX - left)
                                / (right - left)

                            percent = Math.max(
                                0,
                                Math.min(1, percent)
                            )

                            var newPosition =
                                percent * root.trackLength

                            root.trackPosition = newPosition
                            root.activePlayer.position = newPosition
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
                            if (root.activePlayer)
                                root.activePlayer.position =
                                    root.trackPosition

                            root.isUserSeeking = false
                        }

                        onCanceled:
                            root.isUserSeeking = false

                        Canvas {
                            id: progressWave
                            anchors.fill: parent

                            onPaint: {
                                var ctx = getContext("2d")
                                ctx.reset()

                                var w = width
                                var h = height

                                if (w <= 0 || h <= 0)
                                    return

                                var p = Math.max(
                                    0,
                                    Math.min(
                                        1,
                                        progressArea.visualProgress
                                    )
                                )

                                var phase = progressArea.wavePhase
                                var baseY = h / 2
                                var lineWidth = 3.1 * Theme.scale

                                var trackStart =
                                    progressArea.edgePadding

                                var trackEnd = Math.max(
                                    trackStart,
                                    w - progressArea.edgePadding
                                )

                                var trackWidth = Math.max(
                                    1,
                                    trackEnd - trackStart
                                )

                                var thumbX =
                                    trackStart
                                    + p * trackWidth

                                var playedWidth =
                                    Math.max(
                                        0,
                                        thumbX - trackStart
                                    )

                                // -------------------------------
                                // ONDAS
                                // -------------------------------

                                if (
                                    root.isPlaying
                                    && playedWidth > 2
                                ) {
                                    var waveStart = trackStart
                                    var waveEnd = thumbX
                                    var edgeFade = 13 * Theme.scale

                                    function drawWave(
                                        amplitude,
                                        periodPx,
                                        speedPx,
                                        alpha,
                                        verticalBias,
                                        waveColor
                                    ) {
                                        ctx.beginPath()
                                        ctx.moveTo(waveStart, baseY)

                                        var step = 2 * Theme.scale
                                        var omega =
                                            (Math.PI * 2)
                                            / Math.max(
                                                1,
                                                periodPx
                                            )

                                        var travel =
                                            phase * speedPx

                                        for (
                                            var x = waveStart;
                                            x <= waveEnd;
                                            x += step
                                        ) {
                                            var localX =
                                                x - trackStart

                                            var fadeIn =
                                                Math.min(
                                                    1,
                                                    Math.max(
                                                        0,
                                                        (
                                                            x
                                                            - waveStart
                                                        )
                                                        / edgeFade
                                                    )
                                                )

                                            var fadeOut =
                                                Math.min(
                                                    1,
                                                    Math.max(
                                                        0,
                                                        (
                                                            waveEnd
                                                            - x
                                                        )
                                                        / edgeFade
                                                    )
                                                )

                                            var envelope =
                                                fadeIn * fadeOut

                                            var s1 =
                                                0.5
                                                + 0.5
                                                * Math.sin(
                                                    (
                                                        localX
                                                        - travel
                                                    )
                                                    * omega
                                                )

                                            var s2 =
                                                0.5
                                                + 0.5
                                                * Math.sin(
                                                    (
                                                        localX
                                                        - travel * 0.62
                                                    )
                                                    * omega
                                                    * 0.58
                                                    + 1.15
                                                )

                                            var shape =
                                                s1 * 0.72
                                                + s2 * 0.28

                                            var y =
                                                baseY
                                                - verticalBias
                                                - shape
                                                * amplitude
                                                * envelope

                                            if (x === waveStart)
                                                ctx.moveTo(x, baseY)

                                            ctx.lineTo(x, y)
                                        }

                                        ctx.lineTo(waveEnd, baseY)
                                        ctx.closePath()

                                        ctx.fillStyle =
                                            Qt.alpha(
                                                waveColor,
                                                alpha
                                            )

                                        ctx.fill()
                                    }

                                    drawWave(
                                        7.4 * Theme.scale,
                                        86 * Theme.scale,
                                        22 * Theme.scale,
                                        0.34,
                                        0,
                                        root.artworkPalettePrimary
                                    )

                                    drawWave(
                                        5.6 * Theme.scale,
                                        66 * Theme.scale,
                                        -16 * Theme.scale,
                                        0.40,
                                        0.15 * Theme.scale,
                                        root.artworkPaletteSecondary
                                    )

                                    drawWave(
                                        4.1 * Theme.scale,
                                        50 * Theme.scale,
                                        12 * Theme.scale,
                                        0.46,
                                        0.30 * Theme.scale,
                                        root.artworkPaletteAccent
                                    )

                                    // Cresta superior
                                    ctx.beginPath()

                                    var crestStep =
                                        2 * Theme.scale

                                    var crestOmega =
                                        (Math.PI * 2)
                                        / (65 * Theme.scale)

                                    for (
                                        var cx = waveStart;
                                        cx <= waveEnd;
                                        cx += crestStep
                                    ) {
                                        var localCX =
                                            cx - trackStart

                                        var cFadeIn =
                                            Math.min(
                                                1,
                                                Math.max(
                                                    0,
                                                    (
                                                        cx
                                                        - waveStart
                                                    )
                                                    / edgeFade
                                                )
                                            )

                                        var cFadeOut =
                                            Math.min(
                                                1,
                                                Math.max(
                                                    0,
                                                    (
                                                        waveEnd
                                                        - cx
                                                    )
                                                    / edgeFade
                                                )
                                            )

                                        var cEnv =
                                            cFadeIn * cFadeOut

                                        var c1 =
                                            0.5
                                            + 0.5
                                            * Math.sin(
                                                (
                                                    localCX
                                                    - phase
                                                    * 16
                                                    * Theme.scale
                                                )
                                                * crestOmega
                                            )

                                        var c2 =
                                            0.5
                                            + 0.5
                                            * Math.sin(
                                                (
                                                    localCX
                                                    - phase
                                                    * 10
                                                    * Theme.scale
                                                )
                                                * crestOmega
                                                * 0.54
                                                + 0.9
                                            )

                                        var cShape =
                                            c1 * 0.72
                                            + c2 * 0.28

                                        var cy =
                                            baseY
                                            - 0.15 * Theme.scale
                                            - cShape
                                            * 4.8
                                            * Theme.scale
                                            * cEnv

                                        if (cx === waveStart)
                                            ctx.moveTo(cx, baseY)
                                        else
                                            ctx.lineTo(cx, cy)
                                    }

                                    ctx.lineTo(waveEnd, baseY)

                                    ctx.lineWidth =
                                        0.85 * Theme.scale

                                    ctx.lineJoin = "round"
                                    ctx.lineCap = "round"

                                    ctx.strokeStyle =
                                        Qt.alpha(
                                            root.artworkPaletteAccent,
                                            0.76
                                        )

                                    ctx.stroke()
                                }

                                // -------------------------------
                                // BARRA RECTA
                                // -------------------------------

                                ctx.beginPath()
                                ctx.moveTo(trackStart, baseY)
                                ctx.lineTo(trackEnd, baseY)

                                ctx.lineWidth = lineWidth
                                ctx.lineCap = "round"

                                ctx.strokeStyle =
                                    Qt.alpha(
                                        Theme.white,
                                        0.28
                                    )

                                ctx.stroke()

                                if (playedWidth > 0) {
                                    ctx.beginPath()
                                    ctx.moveTo(trackStart, baseY)
                                    ctx.lineTo(thumbX, baseY)

                                    ctx.lineWidth = lineWidth
                                    ctx.lineCap = "round"

                                    ctx.strokeStyle =
                                        Qt.alpha(
                                            Theme.white,
                                            0.96
                                        )

                                    ctx.stroke()
                                }

                                // -------------------------------
                                // THUMB + GLOW
                                // -------------------------------

                                var outerGlow =
                                    ctx.createRadialGradient(
                                        thumbX,
                                        baseY,
                                        progressArea.thumbRadius * 0.20,
                                        thumbX,
                                        baseY,
                                        progressArea.glowRadius
                                    )

                                outerGlow.addColorStop(
                                    0.0,
                                    Qt.alpha(
                                        root.artworkPalettePrimary,
                                        0.54
                                    )
                                )

                                outerGlow.addColorStop(
                                    0.42,
                                    Qt.alpha(
                                        root.artworkPalettePrimary,
                                        0.28
                                    )
                                )

                                outerGlow.addColorStop(
                                    0.76,
                                    Qt.alpha(
                                        root.artworkPalettePrimary,
                                        0.12
                                    )
                                )

                                outerGlow.addColorStop(
                                    1.0,
                                    Qt.rgba(0, 0, 0, 0)
                                )

                                ctx.beginPath()

                                ctx.arc(
                                    thumbX,
                                    baseY,
                                    progressArea.glowRadius,
                                    0,
                                    Math.PI * 2
                                )

                                ctx.fillStyle = outerGlow
                                ctx.fill()

                                ctx.beginPath()

                                ctx.arc(
                                    thumbX,
                                    baseY,
                                    progressArea.thumbRadius,
                                    0,
                                    Math.PI * 2
                                )

                                ctx.fillStyle =
                                    Qt.alpha(
                                        root.artworkPalettePrimary,
                                        0.98
                                    )

                                ctx.fill()

                                // brillo interior
                                ctx.beginPath()

                                ctx.arc(
                                    thumbX,
                                    baseY,
                                    Math.max(
                                        1.2 * Theme.scale,
                                        progressArea.thumbRadius
                                        - 2.0 * Theme.scale
                                    ),
                                    0,
                                    Math.PI * 2
                                )

                                ctx.fillStyle =
                                    Qt.alpha(
                                        Theme.white,
                                        0.22
                                    )

                                ctx.fill()

                                // aro blanco
                                ctx.beginPath()

                                ctx.arc(
                                    thumbX,
                                    baseY,
                                    progressArea.thumbRadius,
                                    0,
                                    Math.PI * 2
                                )

                                ctx.lineWidth =
                                    2.0 * Theme.scale

                                ctx.strokeStyle =
                                    Qt.alpha(
                                        Theme.white,
                                        0.99
                                    )

                                ctx.stroke()
                            }
                        }
                    }

                    // Duración total
                    Item {
                        Layout.preferredWidth: 31 * Theme.scale
                        Layout.preferredHeight: 27 * Theme.scale
                        Layout.alignment: Qt.AlignVCenter

                        Text {
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter

                            text: root.formatTime(root.trackLength)

                            color: Qt.alpha(Theme.white, 0.82)

                            font.family: Theme.fontMain
                            font.pixelSize: 9 * Theme.scale
                            font.bold: true

                            style: Text.Raised
                            styleColor: Qt.rgba(0, 0, 0, 0.36)
                        }
                    }
                }
            }
        }
    }
}
