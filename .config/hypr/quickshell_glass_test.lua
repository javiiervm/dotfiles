if hl.plugin.hyprglass then
    local hg = hl.plugin.hyprglass

    hg.config({
        -- Nunca afectar a ventanas normales.
        enabled = false,

        layers = {
            enabled = true,

            -- Sin límite artificial de FPS.
            live_resample_fps = 0,

            -- Fuerza actualización del backdrop cada frame.
            force_live_resample = true
        }
    })

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
        -- Antes: 0xffffff08
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

    hg.layer("liquid-glass-test", {
        preset = "gnome_liquid_glass",

        mask_mode = "alpha",
        mask_threshold = 0.01,

        live_resample = true
    })
end