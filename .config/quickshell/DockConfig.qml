import QtQuick

pragma Singleton

QtObject {
    // Dock apps are intentionally data-only. To add/remove/reorder an item,
    // edit this list; DockItem.qml handles how it is drawn.
    //
    // Supported fields:
    //   name      : display/debug name
    //   iconName  : icon-theme name resolved by Quickshell
    //   iconPath  : optional absolute path or resolved URL; takes precedence over iconName
    //   command   : shell command for normal apps
    //   action    : special action handled by shell.qml (e.g. "launcher")

    readonly property var apps: [
        {
            name: "Files",
            iconName: "org.kde.dolphin",
            command: "nautilus"
        },
        {
            name: "Launcher",
            iconPath: Qt.resolvedUrl("assets/dock/launcher.png"),
            action: "launcher"
        },
        {
            name: "Firefox",
            iconName: "firefox",
            command: "firefox"
        },
        {
            name: "Kitty",
            iconName: "kitty",
            command: "kitty"
        },
        {
            name: "Visual Studio Code",
            iconName: "vscode",
            command: "code"
        },
        {
            name: "Discord",
            iconName: "discord",
            command: "discord"
        },
        {
            name: "Spotify",
            iconPath: Qt.resolvedUrl("assets/dock/spotify.png"),
            iconName: "spotify-launcher",
            command: "spotify"
        },
        {
            name: "WhatsApp",
            iconPath: Qt.resolvedUrl("assets/dock/whatsapp.png"),
            iconName: "whatsapp",
            command: "firefox --new-window https://web.whatsapp.com"
        },
        {
            name: "Obsidian",
            iconName: "obsidian",
            command: "obsidian"
        },
        {
            name: "Notion",
            iconPath: Qt.resolvedUrl("assets/dock/notion.png"),
            iconName: "notion",
            command: "firefox --new-window https://www.notion.so"
        }
    ]
}
