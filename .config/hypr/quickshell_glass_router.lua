-- =============================================================
-- QUICKSHELL GLASS MODE ROUTER
-- =============================================================
--
-- This is the single compositor-side entry point for the global
-- Classic Blur / Liquid Glass mode.
--
-- Runtime state:
--   $XDG_STATE_HOME/quickshell/glass-mode
--   fallback: ~/.local/state/quickshell/glass-mode
--
-- Legacy migration source:
--   ~/.config/quickshell/state/glass-mode
-- =============================================================

local home = os.getenv("HOME")
local state_home = os.getenv("XDG_STATE_HOME")

if not home then
    return
end

if not state_home or state_home == "" then
    state_home = home .. "/.local/state"
end

local state_file = state_home .. "/quickshell/glass-mode"
local legacy_state_file = home .. "/.config/quickshell/state/glass-mode"

local function read_first_line(path)
    local file = io.open(path, "r")

    if not file then
        return nil
    end

    local value = file:read("*l")
    file:close()

    return value
end

local function read_glass_mode()
    local value = read_first_line(state_file)

    if value ~= "classic" and value ~= "liquid" then
        value = read_first_line(legacy_state_file)
    end

    if value == "classic" then
        return "classic"
    end

    return "liquid"
end

local mode = read_glass_mode()
local config_dir = home .. "/.config/hypr"

-- Keep the normal Hyprland blur engine configured because components that
-- have not been migrated yet still depend on it during the gradual rollout.
dofile(config_dir .. "/quickshell_blur_base.lua")

if mode == "liquid" then
    dofile(config_dir .. "/quickshell_liquid_glass.lua")
else
    dofile(config_dir .. "/quickshell_classic_blur.lua")
end
