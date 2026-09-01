<div align="center">
  <h1>Quickshell Dotfiles</h1>
  <p>
    <img src="https://img.shields.io/github/last-commit/javiiervm/dotfiles" alt="Last Commit" />
    <img src="https://img.shields.io/badge/platform-CachyOS-blue" alt="Platform" />
    <img src="https://img.shields.io/github/issues/javiiervm/dotfiles" alt="Issues" />
    <img src="https://img.shields.io/github/stars/javiiervm/dotfiles" alt="Stars" />
    <br />
    <img src="https://img.shields.io/badge/CachyOS-1793D1?logo=archlinux&logoColor=white" />
    <img src="https://img.shields.io/badge/Hyprland-58E1FF?logo=wayland&logoColor=black" />
    <img src="https://img.shields.io/badge/Quickshell-QML-41CD52?logo=qt&logoColor=white" />
    <img src="https://img.shields.io/badge/Wayland-native-FFBC00?logo=wayland&logoColor=black" />
    <img src="https://img.shields.io/badge/Liquid%20Glass-inspired-8A7CFF" />
  </p>
</div>

My personal **Quickshell + Hyprland** desktop setup, built around a clean **Liquid Glass / macOS-inspired** aesthetic.

The goal is simple: keep everything I use every day integrated into a fast, minimal and consistent desktop shell without turning it into an unnecessarily heavy environment.

> Built and mainly tested on **CachyOS + Hyprland**.

## Preview

### Screenshot
<img width="2560" height="1600" alt="image" src="https://github.com/user-attachments/assets/6ad427f8-9e63-4fbc-bce2-eb3e819e0bbc" />

### Demo
https://github.com/user-attachments/assets/38efdcf1-5b04-43eb-ac96-614ef85c7471

## Features

### Dynamic Island

The centerpiece of the setup.

* Media controls and currently playing music
* System stats
* Timers
* Screen recording status and controls
* Application usage
* Contextual system indicators and alerts
* Touchpad gestures and mouse wheel navigation

The island stays compact when idle and expands only when needed.

### Control & Notification Center

A macOS-inspired panel with quick access to:

* Wi-Fi
* Bluetooth
* Airplane Mode
* Caffeine
* Night Light
* Power profiles
* Volume
* Brightness
* Notifications
* Calendar

### Launcher

A custom application launcher with:

* Application search
* Recent apps
* Keyboard navigation
* Quick actions and utilities
* Integrated clipboard history

### Desktop Shell

The setup also includes:

* Workspace indicator
* Custom battery indicator
* Volume and system status
* System tray
* Custom Alt+Tab switcher
* macOS-style dock
* Workspace overview
* Custom lock screen

## Liquid Glass

The UI uses custom translucent QML surfaces together with Hyprland blur to create a consistent glass-like appearance.

Colors are designed to integrate with the rest of the desktop and can be adapted through the theme configuration.

Main files:

```text
.config/quickshell/
├── shell.qml
├── Theme.qml
├── Glass.qml
├── DockConfig.qml
│
├── components/
│   ├── DynamicIsland.qml
│   ├── Launcher.qml
│   ├── NotificationCenter.qml
│   ├── AltTabOverlay.qml
│   └── ...
│
├── overview/
├── lock/
├── scripts/
└── assets/
```

## Efficient by design

Whenever possible, system information reacts to **native system events instead of constant polling**.

Volume, network, Bluetooth, battery and power-profile changes are handled by a lightweight backend using tools such as PipeWire, NetworkManager, D-Bus and udev.

This keeps the shell responsive without unnecessarily waking up the CPU all the time.

## Installation

These dotfiles are designed for **Hyprland on Arch-based distributions**, especially CachyOS.

First install Quickshell and the utilities required by the features you want to use.

At minimum you will need:

* Hyprland
* Quickshell
* PipeWire / WirePlumber
* NetworkManager
* BlueZ
* power-profiles-daemon
* Python
* `wl-clipboard`
* `cliphist`

Some features additionally use tools such as `playerctl`, `brightnessctl`, CAVA and Wayland screenshot / screen-recording utilities.

### 1. Clone the repository

```bash
git clone https://github.com/javiiervm/dotfiles.git
cd dotfiles
```

### 2. Copy the Quickshell configuration

```bash
cp -r .config/quickshell ~/.config/
```

If you want the full intended appearance and integration, also use the included Hyprland configuration:

```bash
cp -r .config/hypr ~/.config/
```

> **Warning**
>
> These are personal dotfiles, not a universal installer.
>
> Some files currently contain paths specific to my system, such as `/home/javier`. Search for these paths and replace them with your own home directory before using the configuration.

### 3. Make the helper scripts executable

```bash
chmod +x ~/.config/quickshell/scripts/*.sh
chmod +x ~/.config/quickshell/scripts/*.py
```

### 4. Start Quickshell

```bash
quickshell
```

The included Hyprland configuration already launches the main shell and overview automatically on login.

## Customization

Most visual settings live in:

```text
~/.config/quickshell/Theme.qml
~/.config/quickshell/Glass.qml
```

The shell is intentionally modular, so individual parts such as the Dynamic Island, launcher, dock or notification center can be modified independently.

## Note

This is my personal daily-driver configuration and is constantly evolving.

It is primarily designed around **my hardware, workflow and Hyprland setup**, so some tweaking may be necessary on other systems.

Feel free to use it as inspiration, copy parts of it or adapt the whole shell to your own setup.

## Credits

Built with:

* [Quickshell](https://quickshell.org/)
* [Hyprland](https://hypr.land/)
* QML / Qt

Inspired by macOS and the Liquid Glass design language.
