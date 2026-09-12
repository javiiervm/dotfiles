-- =============================================================
-- QUICKSHELL GLASS MODE ROUTER
-- =============================================================
--
-- Punto de entrada global para el sistema de cristal de Quickshell.
--
-- Modos persistentes:
--
--   classic
--       Blur normal de Hyprland.
--
--   liquid
--       HyprGlass Liquid Glass real.
--
-- Estado:
--
--   $XDG_STATE_HOME/quickshell/glass-mode
--
-- normalmente:
--
--   ~/.local/state/quickshell/glass-mode
--
-- Durante la migración también se acepta:
--
--   ~/.config/quickshell/state/glass-mode
--
-- =============================================================


-- =============================================================
-- ENVIRONMENT
-- =============================================================

local home =
    os.getenv("HOME")

if not home then
    return
end


local state_home =
    os.getenv("XDG_STATE_HOME")

if not state_home or state_home == "" then
    state_home =
        home .. "/.local/state"
end


local config_dir =
    home .. "/.config/hypr"

local state_file =
    state_home
    .. "/quickshell/glass-mode"

local legacy_state_file =
    home
    .. "/.config/quickshell/state/glass-mode"


-- =============================================================
-- HELPERS
-- =============================================================

local function read_first_line(path)
    local file =
        io.open(path, "r")

    if not file then
        return nil
    end


    local value =
        file:read("*l")

    file:close()

    return value
end


local function read_glass_mode()
    local value =
        read_first_line(state_file)


    -- ---------------------------------------------------------
    -- Legacy fallback
    -- ---------------------------------------------------------

    if value ~= "classic"
        and value ~= "liquid"
    then
        value =
            read_first_line(
                legacy_state_file
            )
    end


    -- ---------------------------------------------------------
    -- Validation
    -- ---------------------------------------------------------

    if value == "classic" then
        return "classic"
    end

    return "liquid"
end


-- =============================================================
-- CURRENT MODE
-- =============================================================

local glass_mode =
    read_glass_mode()


-- =============================================================
-- NORMAL HYPRLAND BLUR BASE
-- =============================================================
--
-- Se carga siempre.
--
-- Esto es importante durante la migración gradual porque todavía
-- existen componentes Quickshell que no han sido migrados al nuevo
-- sistema y siguen dependiendo del blur normal.
-- =============================================================

dofile(
    config_dir
    .. "/quickshell_blur_base.lua"
)


-- =============================================================
-- ACTIVE GLASS BACKEND
-- =============================================================

if glass_mode == "liquid" then

    dofile(
        config_dir
        .. "/quickshell_liquid_glass.lua"
    )

else

    dofile(
        config_dir
        .. "/quickshell_classic_blur.lua"
    )

end