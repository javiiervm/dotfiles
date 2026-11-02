<div align="center">
  <img width="850" height="300" alt="image" src="https://github.com/user-attachments/assets/0efa7b2c-cf6b-4069-8b5a-6b0af2b8530c" />
  <br /><br />
  <p>
    <a href="#installation">Installation</a> ·
    <a href="https://github.com/javiiervm/dotfiles/wiki">Wiki</a> ·
    <a href="#features">Features</a> ·
    <a href="#architecture">Architecture</a>
  </p>
  <p>
    <img src="https://img.shields.io/github/last-commit/javiiervm/dotfiles" alt="Last Commit" />
    <img src="https://img.shields.io/badge/platform-CachyOS%20%2F%20Arch-1793D1" alt="Platform" />
    <img src="https://img.shields.io/github/issues/javiiervm/dotfiles" alt="Issues" />
    <img src="https://img.shields.io/github/stars/javiiervm/dotfiles" alt="Stars" />
    <br />
    <img src="https://img.shields.io/badge/CachyOS-1793D1?logo=archlinux&logoColor=white" />
    <img src="https://img.shields.io/badge/Hyprland-58E1FF?logo=wayland&logoColor=black" />
    <img src="https://img.shields.io/badge/Quickshell-QML-41CD52?logo=qt&logoColor=white" />
    <img src="https://img.shields.io/badge/Wayland-native-FFBC00?logo=wayland&logoColor=black" />
    <br />
  </p>
</div>

My personal **Quickshell + Hyprland** desktop setup, built around a clean **Liquid Glass / macOS-inspired** aesthetic, in which I keep everything I use every day integrated into a fast, minimal and consistent desktop shell without turning it into an unnecessarily heavy environment.

> Built and mainly tested on **CachyOS + Hyprland**.

## Preview

<!-- ### Screenshot
<img width="2560" height="1600" alt="image" src="https://github.com/user-attachments/assets/6ad427f8-9e63-4fbc-bce2-eb3e819e0bbc" /> -->
<img width="2560" height="1600" alt="2026-09-02-093823_hyprshot" src="https://github.com/user-attachments/assets/df4e39ca-52d6-478b-971a-6162642bf5a3" />

<!-- ### Demo
https://github.com/user-attachments/assets/38efdcf1-5b04-43eb-ac96-614ef85c7471
-->

## Features

<table>
  <tbody>
    <tr>
      <td><strong>Dynamic Island</strong></td>
      <td>Media controls, notifications, timers, recording, app usage and contextual system indicators</td>
    </tr>
    <tr>
      <td><strong>Launcher</strong></td>
      <td>Application search, recent apps, keyboard navigation, clipboard, system actions and integrated <a href=https://github.com/javiiervm/Xavion-AI>Xavion AI</a> access</td>
    </tr>
    <tr>
      <td><strong>Control Center</strong></td>
      <td>Wi-Fi, Bluetooth, audio, brightness, profiles, caffeine, airplane mode, night light and calendar</td>
    </tr>
    <tr>
      <td><strong>Desktop</strong></td>
      <td>Floating dock, workspace indicator, custom Alt+Tab and overview, system tray and custom lock screen</td>
    </tr>
    <tr>
      <td><strong>Visuals</strong></td>
      <td>Shared QML Glass material, Hyprland blur, wallpaper-based colors via Pywal, optional HyprGlass effects</td>
    </tr>
    <tr>
      <td><strong>Utilities</strong></td>
      <td>AI Selection, custom screen recording, wallpaper carousel, Blip integration and helper scripts</td>
    </tr>
  </tbody>
</table>

## Efficient by design

Whenever possible, system information reacts to **native system events instead of constant polling**.

Volume, network, Bluetooth, battery and power-profile changes are handled by a lightweight backend using tools such as PipeWire, NetworkManager, D-Bus and udev.

This keeps the shell responsive without unnecessarily waking up the CPU all the time.

## Installation

**Recommended first step: review the plan before writing any files.**

```bash
git clone https://github.com/javiiervm/dotfiles.git
cd dotfiles
./install.sh --dry-run
```

Install **only the Quickshell configuration** (the default, safest option):

```bash
./install.sh --profile shell
```

Install the integrated Hyprland desktop and selected application configs (with portable monitor defaults):

```bash
./install.sh --profile desktop --dry-run
./install.sh --profile desktop
```

To also install missing packages from configured Arch/CachyOS repositories:

```bash
./install.sh --profile desktop --packages
```

Install remaining user themes and shell settings (including replacing `~/.zshrc`):

```bash
./install.sh --profile all
```

The installer **copies** configurations, substitutes `/home/javier` paths in copied text files, and backs up existing targets under `~/.local/state/dotfiles-installer/backups/`. It does not install the system-wide SDDM theme, third-party plugins, AUR packages, GPU drivers, or enable services. Nothing is restarted automatically. The repository checkout remains untouched.

**Read before logging into a newly installed desktop:** [Getting started](wiki/Getting-Started.md) · [Installation](wiki/Installation.md) · [Dependencies](wiki/Dependencies.md).

## Architecture

```text
Hyprland (Wayland compositor / Lua configuration)
  ├── shortcuts, monitor rules, blur and window management
  └── session startup
         ├── Quickshell main shell (shell.qml)
         │     ├── Dynamic Island / Launcher / Control Center / Dock
         │     ├── Xavion service and panels
         │     ├── system backend (event driven)
         │     └── notification service (D-Bus)
         ├── AI Selection (separate Quickshell instance)
         └── Workspace Overview (separate Quickshell instance)

Pywal + awww → wallpaper and color integrations
Theme.qml + Glass.qml + Hyprland → visual surfaces and blur
```

See [Architecture](wiki/Architecture.md), [Components](wiki/Components.md), and [Backends and IPC](wiki/Backends-and-IPC.md) for file-level details.

## Customize

| File | Purpose |
| --- | --- |
| `.config/quickshell/Theme.qml` | Shared colors and typography |
| `.config/quickshell/Glass.qml` | Tint, opacity, border, shadow and radius tokens |
| `.config/quickshell/components/GlassSurface.qml` | Reusable material surface |
| `.config/hypr/hyprland.lua` | Monitors, input, keybinds, session startup |
| `.config/hypr/quickshell_glass_test.lua` | HyprGlass/classic blur test rules |
| `.config/hypr/scripts/set_wallpaper.sh` | Wallpaper and Pywal integration |

See [Appearance and Theming](wiki/Appearance-and-Theming.md) and [Configuration](wiki/Configuration.md).

## Compatibility and limitations

- **Best supported:** CachyOS/Arch-like distributions, Hyprland with Lua support, Quickshell and Wayland.
- **Machine-specific:** monitor names, DRM device ordering, installed apps, battery/lid handling and custom plugin integration.
- **Optional:** HyprGlass and Xavion backend require separate setup; they are not provided by the installer.
- **System configuration:** SDDM theme requires deliberate system-level installation; this script never writes to `/etc` or `/usr/share`.
- **No guarantee:** installer passes local script tests, but the graphical session must be validated on actual target hardware.

## Documentation

The `wiki/` directory is the source for the long-form documentation. GitHub's **Wiki** tab is a **separate Git repository**: the pages are not published automatically by placing them in `wiki/`. See [Publishing the Wiki](wiki/Publishing-the-Wiki.md).

## Contributing and licenses

Issues with reproduction steps and relevant logs are welcome. See [Development](wiki/Development.md) and [Security and Limitations](wiki/Security-and-Limitations.md). No top-level open-source license is bundled in this draft: the repository owner should review third-party code and choose an appropriate license before inviting unrestricted reuse.

### Acknowledgements

[Quickshell](https://quickshell.org/) · [Hyprland](https://hypr.land/) · [Pywal](https://github.com/dylanaraps/pywal) · [awww](https://codeberg.org/LGFae/awww)
