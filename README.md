# Hyprland Dotfiles

A comprehensive and meticulously configured collection of dotfiles for a modern Hyprland wayland compositor setup, featuring a custom-built shell environment with advanced integrations and a responsive graphical interface.

## Overview

This repository contains a fully-functional desktop environment configuration built around **Hyprland**, a dynamic tiling wayland compositor. The setup emphasizes performance, aesthetics, and developer productivity through:

- **Hyprland Wayland Compositor** - Modern, high-performance window management
- **Quickshell** - Custom QML-based panel and launcher system
- **Waybar** - Extensible status bar with system information
- **Kitty Terminal** - GPU-accelerated terminal emulator
- **pywal Integration** - Dynamic color generation and theming
- **Hypridle** - Lightweight idle management with suspend/lock capabilities

## Directory Structure

```
dotfiles/
├── .config/
│   ├── hypr/                    # Hyprland configuration and scripts
│   │   ├── hyprland.conf        # Main Hyprland configuration
│   │   ├── hyprland-gui.conf    # HyprMod managed settings
│   │   └── scripts/             # Custom shell scripts
│   ├── quickshell/              # QML-based panel and launcher
│   │   ├── shell.qml            # Main shell interface
│   │   ├── components/          # Reusable QML components
│   │   └── scripts/             # Backend daemons
│   ├── waybar/                  # Status bar configuration
│   ├── wal/                     # Color scheme templates
│   └── kitty/                   # Terminal emulator config
├── .scripts/                    # Utility and setup scripts
└── .zshrc                       # Zsh shell configuration
```

## Features

### Window Management
- **Dynamic Tiling**: Hyprland's efficient window layout algorithm
- **Multi-Monitor Support**: Automatic monitor detection and configuration
- **Workspace Management**: 5 dedicated workspaces with visual indicators
- **Smart Gaps**: Customizable inner and outer gaps (5px inner, 12px outer)
- **Border Configuration**: 2px borders with dynamic color theming

### Visual Customization
- **Dynamic Color Theming**: Integration with pywal for palette generation
- **QML-Based UI**: Quickshell custom panel with workspace indicators and system tray
- **Notification System**: Integrated notification daemon with slide animations
- **Cursor Management**: Bibata Modern cursor theme at 24px size

### Applications
- **Terminal**: Kitty (GPU-accelerated)
- **File Manager**: Nautilus (GNOME Files)
- **Browser**: Firefox
- **Editor**: Visual Studio Code
- **Media Control**: playerctl integration for multimedia keys

### System Integration
- **GTK Theme**: adw-gtk3-dark with GNOME Adwaita integration
- **Polkit Authentication**: GTK-based authentication agent
- **Idle Management**: Hypridle with customizable suspend/lock behavior
- **Bluetooth Support**: Full Bluetooth device management via Quickshell
- **Network Management**: WiFi connectivity through Quickshell interface

## Installation

### Prerequisites

Before installing these dotfiles, ensure you have the following packages installed:

```bash
# Core components
sudo pacman -S hyprland hyprctl wayland wayland-protocols

# Shell and terminal
sudo pacman -S zsh kitty

# UI and theming
sudo pacman -S qt5-wayland gtk3 adw-gtk3 bibata-cursor-theme

# System utilities
sudo pacman -S nautilus firefox code hypridle playerctl

# Additional packages
sudo pacman -S python pywal polkit-gnome

# AUR packages (if using yay or paru)
yay -S quickshell-git
```

### Installation Steps

1. **Clone the repository**
   ```bash
   git clone https://github.com/javiiervm/dotfiles.git ~/.dotfiles
   cd ~/.dotfiles
   ```

2. **Backup existing configurations** (optional but recommended)
   ```bash
   # Create a backup directory
   mkdir -p ~/.config_backup
   
   # Back up existing Hyprland config if present
   [ -d ~/.config/hypr ] && cp -r ~/.config/hypr ~/.config_backup/hypr
   [ -d ~/.config/quickshell ] && cp -r ~/.config/quickshell ~/.config_backup/quickshell
   ```

3. **Create symbolic links**
   ```bash
   # Copy or symlink the configuration directories
   cp -r .config/* ~/.config/
   
   # Or use symlinks (useful for development)
   ln -sf $(pwd)/.config/hypr ~/.config/hypr
   ln -sf $(pwd)/.config/quickshell ~/.config/quickshell
   ln -sf $(pwd)/.config/waybar ~/.config/waybar
   ln -sf $(pwd)/.config/wal ~/.config/wal
   ln -sf $(pwd)/.config/kitty ~/.config/kitty
   
   # Link shell configuration
   ln -sf $(pwd)/.zshrc ~/.zshrc
   ```

4. **Set Zsh as default shell** (optional)
   ```bash
   chsh -s /bin/zsh
   ```

5. **Create required directories**
   ```bash
   mkdir -p ~/.cache/wal
   mkdir -p ~/.config/hypr/scripts
   ```

6. **Set up pywal color generation**
   ```bash
   # Generate initial color palette
   wal -i /path/to/your/favorite/wallpaper.png
   ```

7. **Launch Hyprland**
   - Log out of your current session
   - Select "Hyprland" from your login manager
   - Start your session

## Configuration

### Basic Hyprland Settings

Edit `~/.config/hypr/hyprland.conf` to customize:

```conf
# Monitor configuration
monitor=eDP-1,2560x1600@60,0x0,1.33

# Define default applications
$terminal = kitty
$fileManager = nautilus
$browser = firefox
$editor = code

# Window gaps
general {
    gaps_in = 5
    gaps_out = 2, 12, 12, 12
    border_size = 2
}
```

### Quickshell Panel Customization

Edit `~/.config/quickshell/shell.qml` to modify:
- Panel height and styling
- Workspace indicator appearance
- Notification behavior
- System tray items

### Color Scheme

Colors are dynamically generated by pywal and sourced in Hyprland:

```bash
# Generate new colors from an image
wal -i ~/Pictures/wallpaper.jpg

# Colors will be automatically applied to:
# - Hyprland (via colors-hyprland.conf)
# - Quickshell panel
# - Waybar status bar
# - All GTK applications
```

### Keyboard Bindings

Key bindings are defined in `hyprland.conf` under the `bind` sections. Common bindings:

```conf
# Program launching
$mainMod = SUPER
bind = $mainMod, RETURN, exec, $terminal
bind = $mainMod, SPACE, exec, quickshell_launcher

# Window management
bind = $mainMod, Q, killactive,
bind = $mainMod, V, togglefloating,
bind = $mainMod, F, fullscreen,

# Workspace switching
bind = $mainMod, 1, workspace, 1
bind = $mainMod, 2, workspace, 2
```

## Troubleshooting

### Quickshell Not Starting

```bash
# Verify QML compilation
python3 -m compileall -q ~/.config/quickshell/scripts/

# Check for errors
quickshell 2>&1 | head -20

# Ensure XDG_RUNTIME_DIR is set
echo $XDG_RUNTIME_DIR
```

### Colors Not Updating

```bash
# Regenerate color palette
wal -i ~/Pictures/wallpaper.jpg

# Verify colors were generated
cat ~/.cache/wal/colors-hyprland.conf

# Restart Hyprland or source the config
hyprctl reload
```

### Monitor Not Detected

```bash
# List connected monitors
hyprctl monitors

# Check Wayland output detection
wlr-randr
```

### Theme Not Applied

```bash
# Force GTK theme refresh
gsettings set org.gnome.desktop.interface gtk-theme 'adw-gtk3-dark'
gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark'

# Restart GTK applications
pkill -f "gnome-shell|nautilus"
```

## Customization Guide

### Adding Custom Scripts

Place scripts in `~/.config/hypr/scripts/` and source them in `hyprland.conf`:

```conf
# In hyprland.conf
exec-once = ~/.config/hypr/scripts/my-custom-script.sh
```

### Modifying Waybar Configuration

Edit `~/.config/waybar/themes/OneDark/config.jsonc`:

```jsonc
{
    "position": "top",
    "modules-left": ["custom/arch", "cpu", "temperature"],
    "modules-right": ["battery", "clock"]
}
```

### Creating Custom QML Components

Add new QML files to `~/.config/quickshell/components/` and import them:

```qml
import QtQuick
import ".."

// Your custom component
Rectangle {
    // Component implementation
}
```

## Performance Optimization

This configuration is optimized for:

- **Low Memory Footprint**: Hyprland uses minimal system resources
- **Efficient Rendering**: GPU-accelerated compositing via Wayland
- **Fast Application Launch**: Quickshell launcher with backend caching
- **Responsive UI**: QML-based interface with smooth animations

## Key Bindings Reference

| Action | Binding |
|--------|---------|
| Terminal | `Super + Return` |
| Launcher | `Super + Space` |
| Kill Window | `Super + Q` |
| Toggle Float | `Super + V` |
| Fullscreen | `Super + F` |
| Workspace 1-5 | `Super + 1-5` |
| Move Window | `Super + Shift + Arrow Keys` |

## Dependencies

### Arch Linux (Pacman)

```bash
hyprland hyprctl wayland wayland-protocols zsh kitty qt5-wayland gtk3 \
adw-gtk3 bibata-cursor-theme nautilus firefox code hypridle playerctl \
python pywal polkit-gnome
```

### AUR (Yay/Paru)

```bash
quickshell-git
```

### Other Distributions

Refer to your package manager's repository for equivalent packages.

## License

This repository is provided as-is for personal and educational use. Feel free to modify and adapt configurations to suit your workflow.

## Contributing

While this is a personal configuration repository, suggestions and improvements are welcome. Feel free to open issues or discussions for:

- Bug reports
- Performance improvements
- Feature suggestions
- Configuration optimizations

## Resources

- [Hyprland Official Wiki](https://wiki.hypr.land/)
- [Wayland Development](https://wayland.freedesktop.org/)
- [QML Documentation](https://doc.qt.io/qt-6/qmlapplications.html)
- [pywal Documentation](https://github.com/dylanaraps/wal)
- [GTK Adwaita](https://gitlab.gnome.org/GNOME/adwaita)

## Acknowledgments

Configuration built with:
- **Hyprland** - Modern wayland compositor
- **Quickshell** - QML shell framework
- **pywal** - Color scheme generator
- **GTK Adwaita** - Native GNOME theming

---

**Last Updated**: April 2026

For issues and questions, refer to the [Hyprland community](https://hyprland.org/) and configuration documentation.
