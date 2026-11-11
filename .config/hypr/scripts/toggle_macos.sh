#!/usr/bin/env bash

# ============================================================
# Hyprland macOS mode toggle
#
# Normal mode:
#   - Hyprland tiling (dwindle)
#
# macOS mode:
#   - regular windows become floating, centered and resizable
#   - new windows start at 1280x800 logical pixels
#   - extra bottom gap leaves space for the Quickshell Dock
#   - Hyprbars provides macOS-style traffic-light controls
#
# The last selected window-manager mode is saved across sessions.
# A new Hyprland session can restore the saved preference by calling
# this script with --restore-session after hyprpm finishes loading.
# Hyprbars must remain disabled in `hyprpm list` so it is loaded
# only when the saved or selected mode is macOS.
# ============================================================

set -u

# ============================================================
# Configuration
# ============================================================

STATE_FILE="/tmp/hypr_macos_mode"
BACKUP_FILE="/tmp/hypr_macos_backup.json"
RULES_FILE="$HOME/.config/hypr/macos_rules.lua"
MAXIMIZE_STATE_DIR="/tmp/hypr_macos_maximize"
HYPRBARS_PATH_FILE="/tmp/hypr_macos_hyprbars_path"

# Durable preference (macos or tiling), not the ephemeral session marker.
PREFERENCE_FILE="${XDG_STATE_HOME:-$HOME/.local/state}/hypr/window_manager_mode"
LOCK_FILE="${XDG_RUNTIME_DIR:-/tmp}/hypr_macos_toggle_${UID}.lock"

DEFAULT_WIDTH=1280
DEFAULT_HEIGHT=800

# Verified on this machine. The lookup below also handles a future
# hyprpm cache relocation, so the entire script need not be edited.
HYPRBARS_LIBRARY="/var/cache/hyprpm/${USER:-$(id -un)}/hyprland-plugins/hyprbars.so"

CURRENT_INSTANCE="${HYPRLAND_INSTANCE_SIGNATURE:-}"

# ============================================================
# Persistent preference helpers
# ============================================================

# Serialize toggle and session-restore operations. A user shortcut
# during startup must not overwrite an in-progress mode change.
exec 9>"$LOCK_FILE"
flock -x 9

remember_mode() {
    local mode="$1"
    local directory temporary

    directory=$(dirname "$PREFERENCE_FILE")
    mkdir -p "$directory" || return 1

    temporary="$PREFERENCE_FILE.tmp.$$"
    if printf '%s\n' "$mode" > "$temporary" && mv -f "$temporary" "$PREFERENCE_FILE"; then
        return 0
    fi
    rm -f "$temporary"
    return 1
}

preferred_mode() {
    local mode
    mode=$(head -n 1 "$PREFERENCE_FILE" 2>/dev/null || true)
    case "$mode" in
        macos|tiling) printf '%s\n' "$mode" ;;
        *) return 1 ;;
    esac
}

# ============================================================
# Window and plugin helpers
# ============================================================

dispatch() {
    hyprctl dispatch "$1" >/dev/null 2>&1
}

window_exists() {
    local addr="$1"

    hyprctl clients -j 2>/dev/null |
        jq -e --arg addr "$addr" \
            '.[] | select(.address == $addr)' \
            >/dev/null 2>&1
}

macos_mode_active() {
    [ -n "$CURRENT_INSTANCE" ] || return 1
    [ -f "$STATE_FILE" ] || return 1

    local saved_instance
    saved_instance=$(head -n 1 "$STATE_FILE" 2>/dev/null || true)
    [ "$saved_instance" = "$CURRENT_INSTANCE" ]
}

backup_contains_window() {
    local addr="$1"
    [ -f "$BACKUP_FILE" ] || return 1

    jq -e --arg addr "$addr" \
        '.[] | select(.address == $addr)' \
        "$BACKUP_FILE" >/dev/null 2>&1
}

hyprbars_is_loaded() {
    hyprctl plugin list 2>/dev/null | grep -qi 'Plugin hyprbars'
}

find_hyprbars_library() {
    # First try the exact path confirmed with `find /`.
    if [ -f "$HYPRBARS_LIBRARY" ]; then
        printf '%s\n' "$HYPRBARS_LIBRARY"
        return 0
    fi

    # hyprpm may relocate the cache when the plugin is updated.
    local base
    for base in "/var/cache/hyprpm/${USER:-$(id -un)}" \
                "$HOME/.cache/hyprpm"; do
        if [ -d "$base" ]; then
            local found
            found=$(find -L "$base" -type f -name 'hyprbars.so' -print -quit 2>/dev/null)
            if [ -n "$found" ]; then
                printf '%s\n' "$found"
                return 0
            fi
        fi
    done

    return 1
}

load_hyprbars() {
    # A previous manual `hyprctl plugin load` is fine: avoid loading twice.
    if hyprbars_is_loaded; then
        return 0
    fi

    local library output
    if ! library=$(find_hyprbars_library); then
        printf '%s\n' \
            'macOS mode: hyprbars.so was not found; floating mode will still work.' \
            'Check the installation with: hyprpm list' >&2
        return 1
    fi

    if ! output=$(hyprctl plugin load "$library" 2>&1); then
        printf 'macOS mode: could not load Hyprbars: %s\n' "$output" >&2
        return 1
    fi

    # Always retain the exact path used so unload continues to work
    # even if hyprpm later changes the cache location.
    printf '%s\n' "$library" > "$HYPRBARS_PATH_FILE"
    return 0
}

unload_hyprbars() {
    if ! hyprbars_is_loaded; then
        rm -f "$HYPRBARS_PATH_FILE"
        return 0
    fi

    local library output
    library=$(head -n 1 "$HYPRBARS_PATH_FILE" 2>/dev/null || true)
    if [ -z "$library" ]; then
        library=$(find_hyprbars_library 2>/dev/null || true)
    fi

    if [ -n "$library" ]; then
        if ! output=$(hyprctl plugin unload "$library" 2>&1); then
            printf 'macOS mode: could not unload Hyprbars: %s\n' "$output" >&2
        fi
    else
        printf '%s\n' 'macOS mode: Hyprbars is loaded, but its library was not found.' >&2
    fi

    rm -f "$HYPRBARS_PATH_FILE"

    # If unloading failed, at least hide the bars immediately.
    # Hyprbars normally should be fully unloaded outside macOS mode.
    if hyprbars_is_loaded; then
        hyprctl eval \
            'if hl.plugin.hyprbars then hl.config({ plugin = { hyprbars = { enabled = false } } }) end' \
            >/dev/null 2>&1 || true
    fi
}

write_inactive_rules() {
    cat > "$RULES_FILE" <<'EOF'
-- macOS mode inactive
-- Auto-generated by toggle_macos.sh
EOF
}

write_active_rules() {
    cat > "$RULES_FILE" <<EOF
-- ============================================================
-- macOS mode
-- Auto-generated by toggle_macos.sh; do not edit manually.
-- ============================================================

hl.window_rule({
    name = "macos-mode-global",
    match = { class = ".*" },
    float = true,
    center = true,
    size = { "$DEFAULT_WIDTH", "$DEFAULT_HEIGHT" },
    persistent_size = true,
})

hl.config({
    general = {
        gaps_out = {
            top = 2,
            right = 12,
            bottom = 80,
            left = 12,
        },
    },
})

-- The whole floating mode remains functional even if Hyprbars
-- is unavailable. The plugin must be loaded before reloading
-- Hyprland for this block to run.
if hl.plugin.hyprbars then
    hl.config({
        plugin = {
            hyprbars = {
                enabled = true,
                bar_height = 34,
                bar_color = "rgba(253341e8)",
                bar_blur = true,
                bar_part_of_window = true,
                bar_precedence_over_border = true,
                bar_title_enabled = true,
                bar_text_align = "center",
                bar_text_size = 12,
                bar_text_weight = 500,
                bar_text_font = "Noto Sans",
                bar_buttons_alignment = "left",
                bar_padding = 14,
                bar_button_padding = 7,
                -- No glyphs; stock Hyprbars has no per-button hover
                -- background/tint setting (requires a custom plugin).
                icon_on_hover = false,
                buttons_on_hover = false,
                inactive_button_color = "rgb(777777)",
                on_double_click = "$HOME/.config/hypr/scripts/macos_maximize.sh",
            },
        },
    })

    -- Mac order (left to right): close, minimize, maximize.
    -- Keep the circles clean, with no glyphs even on hover.
    hl.plugin.hyprbars.add_button({
        bg_color = "rgb(ff5f57)",
        fg_color = "rgb(471a18)",
        size = 13,
        icon = "",
        action = "hyprctl dispatch 'hl.dsp.window.close()'",
    })

    hl.plugin.hyprbars.add_button({
        bg_color = "rgb(febc2e)",
        fg_color = "rgb(654b10)",
        size = 13,
        icon = "",
        action = "$HOME/.config/hypr/scripts/macos_minimize.sh",
    })

    hl.plugin.hyprbars.add_button({
        bg_color = "rgb(28c840)",
        fg_color = "rgb(124d20)",
        size = 13,
        icon = "",
        action = "$HOME/.config/hypr/scripts/macos_maximize.sh",
    })
end
EOF
}

# ============================================================
# Return to normal tiling
# ============================================================

disable_macos_mode() {
    rm -f "$STATE_FILE"

    # Remove the plugin's decoration before retiling windows.
    # Unlike the earlier version, this also handles a plugin that
    # was manually loaded before entering macOS mode.
    unload_hyprbars
    write_inactive_rules
    hyprctl reload >/dev/null 2>&1

    # Restore windows that existed before macOS mode.
    if [ -f "$BACKUP_FILE" ]; then
        while IFS= read -r win; do
            local addr was_floating x y w h
            addr=$(jq -r '.address // empty' <<< "$win")
            [ -n "$addr" ] || continue
            window_exists "$addr" || continue

            was_floating=$(jq -r '.floating' <<< "$win")

            if [ "$was_floating" = "false" ]; then
                dispatch \
                    "hl.dsp.window.float({
                        action = 'off',
                        window = 'address:$addr'
                    })"
            else
                x=$(jq -r '.at[0]' <<< "$win")
                y=$(jq -r '.at[1]' <<< "$win")
                w=$(jq -r '.size[0]' <<< "$win")
                h=$(jq -r '.size[1]' <<< "$win")

                dispatch \
                    "hl.dsp.window.float({
                        action = 'on',
                        window = 'address:$addr'
                    })"

                dispatch \
                    "hl.dsp.window.resize({
                        x = $w,
                        y = $h,
                        relative = false,
                        window = 'address:$addr'
                    })"

                dispatch \
                    "hl.dsp.window.move({
                        x = $x,
                        y = $y,
                        relative = false,
                        window = 'address:$addr'
                    })"
            fi
        done < <(jq -c '.[]' "$BACKUP_FILE" 2>/dev/null)
    fi

    # Windows created while macOS mode was active do not appear
    # in the backup. Tile them, excluding special workspaces.
    while IFS= read -r win; do
        local addr workspace
        addr=$(jq -r '.address // empty' <<< "$win")
        workspace=$(jq -r '.workspace.name // empty' <<< "$win")

        [ -n "$addr" ] || continue
        case "$workspace" in
            special:*) continue ;;
        esac

        if ! backup_contains_window "$addr"; then
            dispatch \
                "hl.dsp.window.float({
                    action = 'off',
                    window = 'address:$addr'
                })"
        fi
    done < <(hyprctl clients -j 2>/dev/null | jq -c '.[]')

    hyprctl reload >/dev/null 2>&1
    rm -f "$BACKUP_FILE"
    rm -rf "$MAXIMIZE_STATE_DIR"
}

# ============================================================
# Activate macOS floating mode
# ============================================================

enable_macos_mode() {
    if [ -z "$CURRENT_INSTANCE" ]; then
        printf '%s\n' 'toggle_macos.sh: HYPRLAND_INSTANCE_SIGNATURE is not set' >&2
        return 1
    fi

    # Back up the geometry and original floating states BEFORE
    # installing the plugin or changing window configuration.
    if ! hyprctl clients -j > "$BACKUP_FILE"; then
        printf '%s\n' 'toggle_macos.sh: could not read the windows state' >&2
        return 1
    fi

    # If Hyprbars cannot load, tiling/floating still works.
    load_hyprbars || true

    printf '%s\n' "$CURRENT_INSTANCE" > "$STATE_FILE"
    write_active_rules

    # hyprland.lua loads macos_rules.lua only if this state belongs
    # to its own HYPRLAND_INSTANCE_SIGNATURE.
    hyprctl reload >/dev/null 2>&1

    # Convert existing windows; leave special workspaces alone.
    while IFS= read -r win; do
        local addr workspace
        addr=$(jq -r '.address // empty' <<< "$win")
        workspace=$(jq -r '.workspace.name // empty' <<< "$win")

        [ -n "$addr" ] || continue
        window_exists "$addr" || continue

        case "$workspace" in
            special:*) continue ;;
        esac

        dispatch \
            "hl.dsp.window.float({
                action = 'on',
                window = 'address:$addr'
            })"

        dispatch \
            "hl.dsp.window.resize({
                x = $DEFAULT_WIDTH,
                y = $DEFAULT_HEIGHT,
                relative = false,
                window = 'address:$addr'
            })"

        dispatch \
            "hl.dsp.window.center({
                window = 'address:$addr'
            })"
    done < <(jq -c '.[]' "$BACKUP_FILE" 2>/dev/null)

    rm -rf "$MAXIMIZE_STATE_DIR"
}

# ============================================================
# Entry point
# ============================================================

# Save the currently active mode without switching it. Run this
# once after upgrading if macOS mode is ALREADY active and you
# want that mode restored on the next login.
if [ "${1:-}" = "--remember-current" ]; then
    if macos_mode_active; then
        remember_mode "macos" || exit 1
        printf '%s\n' 'Saved window-manager mode: macos'
    else
        remember_mode "tiling" || exit 1
        printf '%s\n' 'Saved window-manager mode: tiling'
    fi
    exit 0
fi

# Idempotent session restoration. Called after hyprpm reload at
# Hyprland startup. Unlike a toggle, running it more than once
# never accidentally flips the selected mode.
if [ "${1:-}" = "--restore-session" ]; then
    wanted=$(preferred_mode || true)
    case "$wanted" in
        macos)
            if ! macos_mode_active; then
                # Clear stale temporary state from another session.
                rm -f "$STATE_FILE" "$BACKUP_FILE" "$HYPRBARS_PATH_FILE"
                rm -rf "$MAXIMIZE_STATE_DIR"
                write_inactive_rules
                enable_macos_mode
            fi
            ;;
        tiling)
            if macos_mode_active; then
                disable_macos_mode
            fi
            ;;
        *)
            # First run: keep Hyprland's normal startup behavior.
            ;;
    esac
    exit $?
fi

if [ "$#" -gt 0 ]; then
    printf 'Usage: %s [--remember-current|--restore-session]\n' "$0" >&2
    exit 2
fi

# Normal user toggle: switch AND persist the new preference.
if macos_mode_active; then
    if disable_macos_mode; then
        remember_mode "tiling"
    else
        exit 1
    fi
else
    # Stale state from an older session must never survive.
    rm -f "$STATE_FILE" "$BACKUP_FILE" "$HYPRBARS_PATH_FILE"
    rm -rf "$MAXIMIZE_STATE_DIR"

    write_inactive_rules
    if enable_macos_mode; then
        remember_mode "macos"
    else
        exit 1
    fi
fi
