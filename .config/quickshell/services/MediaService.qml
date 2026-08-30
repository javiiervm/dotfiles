pragma Singleton

import QtQuick
import Quickshell.Services.Mpris

QtObject {
    id: mediaService

    // ============================================================
    // MPRIS PLAYERS
    // ============================================================

    readonly property var playerList:
        (Mpris.players && Mpris.players.values)
            ? Mpris.players.values
            : []

    readonly property var blacklist: [
        "firefox",
        "chromium",
        "brave",
        "mpv",
        "playerctl",
        "kdeconnect"
    ]

    // Spotify keeps the same priority used by both the Dynamic Island
    // and the lockscreen. If Spotify is not available, use the first
    // non-blacklisted MPRIS player.
    readonly property var activePlayer: {
        if (playerList.length === 0)
            return null

        var fallbackPlayer = null

        for (var i = 0; i < playerList.length; ++i) {
            var player = playerList[i]

            if (!player)
                continue

            var fullName =
                (player.identity ? player.identity.toLowerCase() : "")
                + " "
                + (player.busName ? player.busName.toLowerCase() : "")

            if (fullName.indexOf("spotify") !== -1)
                return player

            var blacklisted = false

            for (var j = 0; j < blacklist.length; ++j) {
                if (fullName.indexOf(blacklist[j]) !== -1) {
                    blacklisted = true
                    break
                }
            }

            if (!blacklisted && fallbackPlayer === null)
                fallbackPlayer = player
        }

        return fallbackPlayer
    }

    readonly property bool isPlayerAvailable:
        activePlayer !== null

    // ============================================================
    // RAW TRACK METADATA
    //
    // Deliberately no UI-specific fallback strings here.
    // "No music playing", "Nothing playing", etc. belong to the
    // component displaying the information, not to the service.
    // ============================================================

    readonly property string trackTitle: {
        if (!activePlayer)
            return ""

        var title =
            activePlayer.trackTitle
            || (
                activePlayer.metadata
                    ? activePlayer.metadata["xesam:title"]
                    : null
            )

        return title ? String(title) : ""
    }

    readonly property string trackArtist: {
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

        return artist ? String(artist) : ""
    }

    readonly property string trackArtUrl: {
        if (!activePlayer)
            return ""

        var art =
            activePlayer.trackArtUrl
            || (
                activePlayer.metadata
                    ? activePlayer.metadata["mpris:artUrl"]
                    : null
            )

        return art ? String(art) : ""
    }

    // ============================================================
    // BASIC PLAYBACK STATE
    // ============================================================

    readonly property bool isPlaying:
        activePlayer
            ? (
                activePlayer.playbackState === 1
                || activePlayer.playbackStatus === "Playing"
            )
            : false

    readonly property bool isShuffle:
        activePlayer
            ? (activePlayer.shuffle || false)
            : false
}