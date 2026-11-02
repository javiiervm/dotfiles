#!/usr/bin/env bash
# Dotfiles installer for javiiervm/dotfiles
# Safely installs an isolated copy of selected configurations; never edits the source checkout.
set -Eeuo pipefail

PROJECT='javiiervm/dotfiles'
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
PROFILE='shell'
DRY_RUN=false
ASSUME_YES=false
INSTALL_PACKAGES=false
KEEP_HARDWARE=false
BACKUP_ROOT="${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles-installer/backups"
RUN_ID="$(date +%Y%m%d-%H%M%S)-$$"
BACKUP_DIR="$BACKUP_ROOT/$RUN_ID"
declare -a SOURCES=()
declare -a DESTS=()
declare -a NEW_TARGETS=()
declare -a OLD_TARGETS=()
declare -a OLD_BACKUPS=()
STAGE=''
COMMITTED=false

say() { printf '\n\033[1;34m[dotfiles]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[warning]\033[0m %s\n' "$*" >&2; }
die() { printf '\033[1;31m[error]\033[0m %s\n' "$*" >&2; exit 1; }
usage() {
    cat <<'HELP'
Usage: ./install.sh [options]

Options:
  --profile shell|desktop|all  shell (default): Quickshell only
                               desktop: Quickshell + Hyprland + common tools
                               all: desktop + optional theme configs + .zshrc
  --packages                   Install missing pacman packages (with sudo)
  --dry-run                    Show intended actions, without writing anything
  --yes, -y                    Skip the interactive confirmation
  --keep-hardware              Retain author's monitor and DRM device rules
                               (default: neutralize these in installed Hyprland)
  --help, -h                   Display this help

No root execution, no system-wide SDDM edits, no plugin/AUR installs,
no automatic service enablement, and no automatic shell/Hyprland restart.
Original user configs are moved to timestamped backup directories.
HELP
}

while (($#)); do
    case "$1" in
        --profile) (($# >= 2)) || die '--profile needs a value'; PROFILE="$2"; shift 2 ;;
        --packages) INSTALL_PACKAGES=true; shift ;;
        --dry-run) DRY_RUN=true; shift ;;
        --yes|-y) ASSUME_YES=true; shift ;;
        --keep-hardware) KEEP_HARDWARE=true; shift ;;
        --help|-h) usage; exit 0 ;;
        *) die "Unknown argument: $1 (see --help)" ;;
    esac
done
case "$PROFILE" in shell|desktop|all) ;; *) die "Unknown profile: $PROFILE";; esac
[[ $EUID -ne 0 ]] || die 'Do not run as root. The installer writes into your own home directory.'
[[ -d "$ROOT/.config/quickshell" ]] || die "Run this script from the cloned $PROJECT checkout (missing .config/quickshell)."
[[ -d "$HOME" ]] || die 'HOME does not exist.'
command -v python3 >/dev/null || die 'python3 is required for safe text-path substitutions.'

add_component() {
    local relative="$1" destination="$2"
    [[ -e "$ROOT/$relative" ]] || die "Source component not found: $relative"
    SOURCES+=("$ROOT/$relative")
    DESTS+=("$destination")
}
add_component '.config/quickshell' "$HOME/.config/quickshell"
if [[ "$PROFILE" != 'shell' ]]; then
    add_component '.config/hypr' "$HOME/.config/hypr"
    add_component '.config/wal' "$HOME/.config/wal"
    add_component '.config/kitty' "$HOME/.config/kitty"
    add_component '.config/rofi' "$HOME/.config/rofi"
    add_component '.config/fastfetch' "$HOME/.config/fastfetch"
    add_component '.config/starship.toml' "$HOME/.config/starship.toml"
fi
if [[ "$PROFILE" == 'all' ]]; then
    add_component '.config/gtk-3.0' "$HOME/.config/gtk-3.0"
    add_component '.config/swaync' "$HOME/.config/swaync"
    add_component '.config/swayosd' "$HOME/.config/swayosd"
    add_component '.config/waybar' "$HOME/.config/waybar"
    add_component '.zshrc' "$HOME/.zshrc"
fi

say "Profile: $PROFILE | Source: $ROOT"
if [[ "$PROFILE" != 'shell' ]]; then
    if "$KEEP_HARDWARE"; then
        warn 'Keeping author-specific display and GPU rules. Verify hardware before starting Hyprland.'
    else
        say 'Portable mode: installed Hyprland uses generic monitor layout; author DRM overrides are disabled.'
    fi
fi
say 'Install plan:'
for i in "${!SOURCES[@]}"; do
    source="${SOURCES[i]}"; destination="${DESTS[i]}"
    if [[ -e "$destination" || -L "$destination" ]]; then
        printf '  BACKUP + REPLACE  %s\n' "$destination"
    else
        printf '  CREATE            %s\n' "$destination"
    fi
done
printf '  Backup directory: %s\n' "$BACKUP_DIR"

if "$INSTALL_PACKAGES"; then
    command -v pacman >/dev/null || die '--packages requires an Arch-based distro with pacman.'
    packages=(quickshell python python-dbus python-gobject python-pillow
              networkmanager bluez bluez-utils power-profiles-daemon
              pipewire wireplumber libpulse wl-clipboard cliphist
              playerctl brightnessctl grim slurp awww python-pywal
              cava inotify-tools jq)
    if [[ "$PROFILE" != 'shell' ]]; then
        packages+=(hyprland kitty rofi-wayland nautilus hypridle hyprlock polkit-gnome)
    fi
    missing=()
    for pkg in "${packages[@]}"; do
        pacman -Qq "$pkg" &>/dev/null || missing+=("$pkg")
    done
    if ((${#missing[@]})); then
        say "Missing pacman packages: ${missing[*]}"
    else
        say 'All proposed pacman packages are installed.'
    fi
fi

if "$DRY_RUN"; then
    say 'Dry run: no configuration, packages, backups, or services were changed.'
    exit 0
fi

if ! "$ASSUME_YES"; then
    if [[ ! -t 0 ]]; then
        die 'Interactive confirmation required; rerun in a terminal or add --yes.'
    fi
    printf '\nApply the plan above? [y/N] '
    read -r answer || true
    [[ "$answer" == [Yy] || "$answer" == [Yy][Ee][Ss] ]] || die 'Installation cancelled.'
fi

if "$INSTALL_PACKAGES" && ((${#missing[@]})); then
    say 'Installing missing official repository packages using pacman...'
    sudo pacman -S --needed -- "${missing[@]}"
fi

# Rewrites are applied exclusively to a temporary, copied tree. The checkout is never altered.
portable_copy() {
    local staged="$1" is_hypr="$2"
    DOTFILES_INSTALL_HOME="$HOME" DOTFILES_INSTALL_HYPR="$is_hypr" python3 - "$staged" <<'PY'
from pathlib import Path
import os, re, sys
root = Path(sys.argv[1])
home = os.environ['DOTFILES_INSTALL_HOME']
extensions = {'.qml','.lua','.sh','.py','.json','.jsonc','.toml','.ini',
              '.conf','.rasi','.css','.xml','.desktop','.md','.txt','.zsh'}
files = [root] if root.is_file() else root.rglob('*')
for path in files:
    if not path.is_file() or path.is_symlink():
        continue
    if path.suffix.lower() not in extensions and path.name not in {'.zshrc','qmldir'}:
        continue
    try:
        before = path.read_text(encoding='utf-8')
    except (UnicodeDecodeError, OSError):
        continue
    after = before.replace('/home/javier', home)
    if after != before:
        path.write_text(after, encoding='utf-8')

if os.environ['DOTFILES_INSTALL_HYPR'] == '1':
    hypr = root / 'hyprland.lua'
    if not hypr.exists():
        sys.exit('Expected hyprland.lua not found in copied config')
    lines = hypr.read_text(encoding='utf-8').splitlines(keepends=True)
    result = []
    seen_monitor = False
    changed = False
    for line in lines:
        if re.match(r'^\s*hl\.monitor\(\{\s*output\s*=\s*"(?:eDP-1|HDMI-A-1)"', line):
            result.append('-- Installer: disabled hardware-specific monitor rule\n')
            result.append('-- ' + line)
            seen_monitor = True
            changed = True
        elif re.match(r'^\s*hl\.env\("(?:AQ_DRM_DEVICES|WLR_DRM_DEVICES)"', line):
            result.append('-- Installer: disabled machine-specific GPU device order\n')
            result.append('-- ' + line)
            changed = True
        elif re.match(r'^\s*hl\.exec_cmd\("~/.config/quickshell/scripts/backend_daemon\.sh"\)', line):
            # shell.qml already owns this daemon; avoid two processes replacing one FIFO.
            result.append('-- Installer: shell.qml owns the backend daemon; do not start a duplicate\n')
            result.append('-- ' + line)
            changed = True
        else:
            result.append(line)
    if seen_monitor:
        # Fallback rule from the Hyprland Lua monitor documentation.
        result.append('\n-- Portable display fallback inserted by install.sh\n')
        result.append('hl.monitor({ output = "", mode = "preferred", position = "auto", scale = 1 })\n')
    if not changed:
        print('WARNING: No known hardware rules were found; review monitor/GPU settings.',file=sys.stderr)
    hypr.write_text(''.join(result), encoding='utf-8')
PY
}

rollback() {
    local i
    warn 'Install did not complete; restoring previous configuration where possible.'
    for ((i=${#NEW_TARGETS[@]}-1; i>=0; --i)); do
        rm -rf -- "${NEW_TARGETS[i]}" || warn "Could not remove ${NEW_TARGETS[i]}"
    done
    for ((i=${#OLD_TARGETS[@]}-1; i>=0; --i)); do
        if [[ -e "${OLD_BACKUPS[i]}" || -L "${OLD_BACKUPS[i]}" ]]; then
            mv -- "${OLD_BACKUPS[i]}" "${OLD_TARGETS[i]}" || warn "Restore manually: ${OLD_BACKUPS[i]}"
        fi
    done
}
on_exit() {
    local status="$1"
    if [[ -n "$STAGE" && -d "$STAGE" ]]; then rm -rf -- "$STAGE"; fi
    if ((status != 0)) && ! "$COMMITTED"; then rollback; fi
}
trap 'on_exit $?' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

for i in "${!SOURCES[@]}"; do
    src="${SOURCES[i]}"; dest="${DESTS[i]}"; parent="$(dirname -- "$dest")"
    mkdir -p -- "$parent"
    STAGE="$(mktemp -d -- "$parent/.dotfiles-stage.XXXXXXXX")"
    cp -a -- "$src" "$STAGE/new"
    is_hypr=0
    if [[ "$dest" == "$HOME/.config/hypr" ]] && ! "$KEEP_HARDWARE"; then is_hypr=1; fi
    portable_copy "$STAGE/new" "$is_hypr"
    if [[ ! -L "$dest" && -e "$dest" ]] && diff -qr -- "$STAGE/new" "$dest" >/dev/null 2>&1; then
        say "Already up to date: $dest"
        rm -rf -- "$STAGE"; STAGE=''
        continue
    fi
    if [[ -e "$dest" || -L "$dest" ]]; then
        backup="$BACKUP_DIR/${dest#"$HOME"/}"
        mkdir -p -- "$(dirname -- "$backup")"
        mv -- "$dest" "$backup"
        OLD_TARGETS+=("$dest"); OLD_BACKUPS+=("$backup")
    fi
    mv -- "$STAGE/new" "$dest"
    NEW_TARGETS+=("$dest")
    rm -rf -- "$STAGE"; STAGE=''
    say "Installed $dest"
done

# A fresh Pywal cache is needed because hyprland.lua reads it at startup.
# Only create a conservative fallback when the file does not already exist.
if [[ "$PROFILE" != 'shell' && ! -e "$HOME/.cache/wal/colors-hyprland.lua" ]]; then
    mkdir -p -- "$HOME/.cache/wal"
    printf 'return { background = "rgb(121212)", color1 = "rgb(61afef)", color2 = "rgb(c678dd)" }\n' \
        > "$HOME/.cache/wal/colors-hyprland.lua"
    say 'Created initial Pywal Lua fallback (replaced when you choose a wallpaper).'
fi
COMMITTED=true
say 'Installation complete. Existing configurations were backed up (when present).'
if ((${#OLD_TARGETS[@]})); then printf 'Backup location: %s\n' "$BACKUP_DIR"; fi
say 'No session was restarted. Review installed configs and read wiki/Getting-Started.md before logging in.'
if [[ "$PROFILE" != 'shell' ]]; then
    warn 'Hyprland extras and GPU-specific plugins may require manual setup. The SDDM theme is intentionally not installed.'
fi
