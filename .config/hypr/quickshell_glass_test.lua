-- =============================================================
-- QUICKSHELL GLASS TEST
-- =============================================================
--
-- Persistent modes:
--
--   liquid
--       HyprGlass handles the real Liquid Glass effect.
--
--   classic
--       HyprGlass is disabled for the test surface and the
--       normal Hyprland layer blur is used instead.
--
-- Persistent state:
--
--   ~/.config/quickshell/state/glass-mode
--
-- If the state file does not exist yet, Liquid Glass is used.
-- =============================================================


-- =============================================================
-- READ PERSISTENT MODE
-- =============================================================

local function read_glass_mode()
    local home = os.getenv("HOME")

    if not home then
        return "liquid"
    end

    local path =
        home .. "/.config/quickshell/state/glass-mode"

    local file = io.open(path, "r")

    if not file then
        return "liquid"
    end

    local value = file:read("*l")

    file:close()

    if value == "classic" then
        return "classic"
    end

    return "liquid"
end


local glass_mode = read_glass_mode()

local liquid_enabled =
    glass_mode == "liquid"


-- =============================================================
-- HYPRGLASS
-- =============================================================

if hl.plugin.hyprglass then
    local hg = hl.plugin.hyprglass


    -- =========================================================
    -- GLOBAL HYPRGLASS CONFIG
    -- =========================================================

    hg.config({
        -- Nunca afectar a ventanas normales.
        enabled = false,

        layers = {
            -- HyprGlass para layer surfaces solo está activo
            -- cuando el modo persistente es "liquid".
            enabled = liquid_enabled,

            -- Sin límite artificial de FPS.
            live_resample_fps = 0,

            -- Fuerza actualización del backdrop cada frame.
            force_live_resample = true
        }
    })


    -- =========================================================
    -- LIQUID GLASS PRESET
    -- =========================================================

    hg.preset("gnome_liquid_glass", {
        -- =====================================================
        -- BLUR
        -- =====================================================

        blur_strength = 0.55,
        blur_iterations = 2,

        -- =====================================================
        -- REFRACTION
        -- =====================================================

        refraction_strength = 0.52,
        edge_thickness = 0.050,
        lens_distortion = 0.02,

        -- =====================================================
        -- CHROMATIC ABERRATION
        -- =====================================================

        chromatic_aberration = 0.018,

        -- =====================================================
        -- SURFACE LIGHT
        -- =====================================================

        fresnel_strength = 0.24,
        specular_strength = 0.0,

        -- =====================================================
        -- BODY
        -- =====================================================

        glass_opacity = 1.0,

        -- Tint ligeramente oscuro y azulado.
        tint_color = 0x0b121810,

        -- =====================================================
        -- COLOUR
        -- =====================================================

        dark = {
            brightness = 0.8,
            contrast = 1.0,
            saturation = 1.0,

            vibrancy = 0.0,
            vibrancy_darkness = 0.0,

            adaptive_dim = 0.0,
            adaptive_boost = 0.0
        }
    })


    -- =========================================================
    -- LIQUID GLASS LAYER
    -- =========================================================

    hg.layer("liquid-glass-test", {
        preset = "gnome_liquid_glass",

        mask_mode = "alpha",
        mask_threshold = 0.01,

        live_resample = true
    })
end


-- =============================================================
-- CLASSIC HYPRLAND BLUR
-- =============================================================

if not liquid_enabled then
    hl.layer_rule({
        match = {
            namespace = "liquid-glass-test"
        },

        blur = true,
        ignore_alpha = 0.001
    })
end