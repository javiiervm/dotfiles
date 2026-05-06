# Hyprland Dotfiles

A professionally configured collection of dotfiles for a modern Hyprland Wayland desktop environment, featuring **Quickshell** as the primary UI framework with support for rofi-based applications.

## Overview

This repository contains a fully-functional desktop environment configuration built around **Hyprland**, a dynamic tiling Wayland compositor. The setup emphasizes performance, aesthetics, and developer experience through a modern QML-based interface.

### Core Components

- **Hyprland** - Dynamic tiling Wayland compositor with advanced window management
- **Quickshell** - QML-based shell framework providing custom panel, launcher, and system integration
- **Waybar** - Status bar with system information and modularity
- **Kitty Terminal** - GPU-accelerated terminal emulator
- **pywal** - Dynamic color generation and unified theming
- **Hypridle** - Lightweight idle management with suspend/lock capabilities
- **rofi** - Application launcher and utility tool (complementary to Quickshell)

## Directory Structure

```
dotfiles/
├── .config/
│   ├── hypr/                    # Hyprland configuration and scripts
│   │   ├── hyprland.conf        # Main Hyprland configuration
│   │   ├── hyprland-gui.conf    # HyprMod managed settings
│   │   └── scripts/             # Custom shell scripts
│   ├── quickshell/              # QML-based panel, launcher, and modules
│   │   ├── shell.qml            # Main shell interface
│   │   ├── components/          # Reusable QML components
│   │   ├── overview/            # Workspace overview module
│   │   └── scripts/             # Backend daemons
│   ├── waybar/                  # Status bar configuration
│   ├── wal/                     # Color scheme templates
│   ├── kitty/                   # Terminal emulator config
│   └── rofi/                    # Customizable app launcher
├── .scripts/                    # Utility and setup scripts
└── .zshrc                       # Zsh shell configuration
```

## Features

### Window Management
- **Dynamic Tiling**: Hyprland's efficient window layout algorithm
- **Multi-Monitor Support**: Automatic monitor detection and configuration
- **Workspace Management**: Workspace organization with visual indicators
- **Smart Gaps**: Customizable inner and outer gaps
- **Border Configuration**: Dynamic color-based window decorations

### Quickshell Interface
- **Custom QML Panel**: Workspace indicators and system information display
- **QML-Based Launcher**: Fast application launcher with backend caching
- **System Tray Integration**: Application status icons and system controls
- **Workspace Overview**: Visual workspace grid with live window previews and drag-and-drop
- **System Integration**: Bluetooth, network, and audio controls via QML modules
- **Dynamic Theming**: Automatic color synchronization with pywal
- **Workspace Hot Keys**: Keyboard navigation and window management

### Additional Features
- **rofi Integration**: Lightweight fallback launcher and utility tool
- **Notification System**: Integrated notification daemon with animations
- **Color Theming**: Dynamic palette generation from wallpapers
- **GTK Integration**: Native GNOME Adwaita theme support
- **Media Control**: playerctl integration for multimedia keys

## Installation

### Prerequisites

Ensure you have the following packages installed:

```bash
# Core components
sudo pacman -S hyprland hyprctl wayland wayland-protocols

# Shell and terminal
sudo pacman -S zsh kitty

# UI and theming
sudo pacman -S qt5-wayland qt6-wayland gtk3 adw-gtk3 bibata-cursor-theme

# System utilities
sudo pacman -S nautilus firefox hypridle playerctl

# Additional packages
sudo pacman -S python pywal polkit-gnome rofi

# AUR packages (using yay or paru)
yay -S quickshell-git
```

### Installation Steps

1. **Clone the repository**
   ```bash
   git clone https://github.com/javiiervm/dotfiles.git ~/.dotfiles
   cd ~/.dotfiles
   ```

2. **Backup existing configurations** (recommended)
   ```bash
   mkdir -p ~/.config_backup
   [ -d ~/.config/hypr ] && cp -r ~/.config/hypr ~/.config_backup/hypr
   [ -d ~/.config/quickshell ] && cp -r ~/.config/quickshell ~/.config_backup/quickshell
   ```

3. **Create symbolic links**
   ```bash
   ln -sf $(pwd)/.config/hypr ~/.config/hypr
   ln -sf $(pwd)/.config/quickshell ~/.config/quickshell
   ln -sf $(pwd)/.config/waybar ~/.config/waybar
   ln -sf $(pwd)/.config/wal ~/.config/wal
   ln -sf $(pwd)/.config/kitty ~/.config/kitty
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

6. **Generate initial color palette**
   ```bash
   wal -i /path/to/your/wallpaper.png
   ```

7. **Launch Hyprland**
   - Log out of your current session
   - Select "Hyprland" from your login manager
   - Start your session

## Configuration

### Hyprland Configuration

Edit `~/.config/hypr/hyprland.conf` to customize window management, keyboard bindings, and startup behaviors.

Key sections:
- `monitor=` - Display configuration
- `env=` - Environment variables
- `general {}` - Window gaps, borders, and layout
- `bind=` - Keyboard bindings

### Quickshell Panel Customization

The Quickshell interface is configured via QML files in `~/.config/quickshell/`.

**Main configuration file**: `~/.config/quickshell/shell.qml`

Common customizations:
- Panel size and position
- Workspace indicator style
- System tray icons
- Module visibility

For the workspace overview module, see `.config/quickshell/overview/README.md` for detailed configuration options.

### Dynamic Color Theming

Colors are generated by pywal and automatically applied to all components:

```bash
# Generate new colors from an image
wal -i ~/Pictures/wallpaper.jpg

# Colors apply to:
# - Hyprland window decorations
# - Quickshell QML interface
# - Waybar status bar
# - GTK applications
```

### Keyboard Bindings

Key bindings are defined in `hyprland.conf`. Common bindings:

```conf
$mainMod = SUPER

# Terminal
bind = $mainMod, RETURN, exec, $terminal

# Quickshell launcher
bind = $mainMod, SPACE, exec, quickshell_launcher

# Workspace navigation
bind = $mainMod, 1-5, workspace, 1-5

# Window management
bind = $mainMod, Q, killactive
bind = $mainMod, V, togglefloating
bind = $mainMod, F, fullscreen
```

## Troubleshooting

### Quickshell Not Starting

```bash
# Check for compilation errors
quickshell 2>&1 | head -20

# Verify environment variables
echo $XDG_RUNTIME_DIR
echo $QML_IMPORT_PATH
```

### Colors Not Updating

```bash
# Regenerate palette
wal -i ~/Pictures/wallpaper.jpg

# Verify colors were generated
cat ~/.cache/wal/colors-hyprland.conf

# Reload Hyprland
hyprctl reload
```

### Monitor Not Detected

```bash
# List monitors
hyprctl monitors

# Check Wayland output detection
wlr-randr
```

## Customization

### Adding Custom Scripts

Place scripts in `~/.config/hypr/scripts/` and execute in `hyprland.conf`:

```conf
exec-once = ~/.config/hypr/scripts/my-script.sh
```

### Creating Custom QML Components

Add QML files to `~/.config/quickshell/components/` and import them in other modules:

```qml
import QtQuick
import ".."

Rectangle {
    // Component implementation
}
```

### Modifying Waybar

Edit `~/.config/waybar/config.jsonc` to customize:
- Module order and visibility
- Display formatting
- Click/scroll actions

## Performance

This configuration is optimized for:

- **Low Memory Footprint**: Hyprland minimizes resource usage
- **Efficient Rendering**: GPU-accelerated Wayland compositing
- **Fast Application Launch**: QML-based Quickshell launcher with caching
- **Responsive UI**: Smooth animations and transitions

## Key Bindings Reference

| Action | Binding |
|--------|---------|
| Terminal | `Super + T` |
| Launcher | `Super + Space` |
| Overview | `Super + Tab` |
| Kill Window | `Super + Q` |
| Toggle Float | `Super + V` |
| Fullscreen | `Super + F` |
| Workspace 1-5 | `Super + 1-5` |

## Contributors & Acknowledgments

This configuration builds upon various community projects and scripts:

- **[Hyprland](https://github.com/hyprwm/Hyprland)** - The compositor itself
- **[Quickshell](https://github.com/outfoxxed/quickshell)** - QML shell framework
- **[illogical-impulse](https://github.com/end-4/dots-hyprland)** - Workspace overview module (adapted from)
- **[pywal](https://github.com/dylanaraps/wal)** - Dynamic color generation
- **[GTK Adwaita](https://gitlab.gnome.org/GNOME/adwaita)** - GNOME theming

Special thanks to the Hyprland and Quickshell communities for inspiration and support.

Also, special mention to the following people:
- **[adi1090x](https://github.com/adi1090x)**: Author of the [Rofi themes repo](https://github.com/adi1090x/rofi) used for Rofi's customization.
- **[iikerm](https://github.com/iikerm)**: Author of the [cex script](https://github.com/javiiervm/dotfiles/blob/main/.scripts/cex.py).

## License

This repository is provided as-is for personal and educational use. Feel free to modify and adapt configurations to suit your workflow.

## Contributing

Suggestions and improvements are welcome. Feel free to open issues or discussions for:

- Bug reports
- Performance improvements
- Feature suggestions
- Configuration optimizations

## Resources

- [Hyprland Wiki](https://wiki.hypr.land/)
- [Quickshell Documentation](https://quickshell.org/)
- [Wayland Documentation](https://wayland.freedesktop.org/)
- [Qt QML Documentation](https://doc.qt.io/qt-6/qmlapplications.html)
- [pywal Documentation](https://github.com/dylanaraps/wal)