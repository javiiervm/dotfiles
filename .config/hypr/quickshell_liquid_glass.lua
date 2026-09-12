-- =============================================================
-- QUICKSHELL REAL LIQUID GLASS
-- =============================================================
--
-- Configuración centralizada de HyprGlass para Quickshell.
--
-- Todas las superficies migradas utilizan el mismo preset.
--
-- Los namespaces activos se encuentran en:
--
--   ~/.config/hypr/quickshell_glass_surfaces.lua
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


-- =============================================================
-- HYPRGLASS AVAILABLE?
-- =============================================================

if not hl.plugin.hyprglass then
    return
end


local hg =
    hl.plugin.hyprglass


-- =============================================================
-- GLOBAL HYPRGLASS CONFIG
-- =============================================================

hg.config({

    -- Nunca aplicar el efecto automáticamente a ventanas normales.
    enabled = false,


    layers = {

        enabled = true,


        -- En Liquid Glass HyprGlass vuelve a hacerse cargo del blur
        -- de las layer surfaces que estén registradas.
        manage_blur = true,


        -- Sin límite artificial de FPS.
        live_resample_fps = 0,


        -- Actualizar el backdrop continuamente.
        force_live_resample = true
    }
})


-- =============================================================
-- CENTRAL LIQUID GLASS PRESET
-- =============================================================

hg.preset(
    "gnome_liquid_glass",
    {

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
    }
)


-- =============================================================
-- REGISTER MIGRATED SURFACES
-- =============================================================

local surfaces =
    dofile(
        home
        .. "/.config/hypr/quickshell_glass_surfaces.lua"
    )


for _, surface in ipairs(surfaces) do

    hg.layer(
        surface.namespace,
        {

            preset =
                surface.preset,


            -- Seguimos usando alpha en esta fase porque el QML actual
            -- desactiva BackgroundEffect.blurRegion en modo Liquid.
            mask_mode =
                surface.mask_mode
                or "alpha",

            mask_threshold =
                surface.mask_threshold
                or 0.01,


            live_resample =
                true
        }
    )

end
