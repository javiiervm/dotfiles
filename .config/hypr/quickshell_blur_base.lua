-- =============================================================
-- QUICKSHELL CLASSIC BLUR BASE
-- =============================================================
--
-- Configuración base del blur normal de Hyprland.
--
-- Este archivo se carga tanto en modo Classic como en modo Liquid
-- mientras hacemos la migración gradual.
--
-- Motivo:
--
-- todavía existen componentes Quickshell que no han sido migrados
-- al sistema global y siguen usando el blur tradicional.
--
-- =============================================================


-- =============================================================
-- HYPRLAND BLUR
-- =============================================================

hl.config({
    decoration = {

        blur = {

            enabled = true,


            -- =================================================
            -- QUALITY
            -- =================================================

            size = 10,

            passes = 5,


            -- =================================================
            -- OPTIMIZATION
            -- =================================================

            new_optimizations = true,

            ignore_opacity = true,

            xray = false,


            -- =================================================
            -- COLOUR
            -- =================================================

            vibrancy = 0.1696
        },
    },
})


-- =============================================================
-- EXISTING NON-MIGRATED QUICKSHELL SURFACES
-- =============================================================


-- -------------------------------------------------------------
-- Wallpaper Carousel
-- -------------------------------------------------------------

hl.layer_rule({

    match = {
        namespace = "wall_carousel"
    },

    blur = true,

    ignore_alpha = 0.05
})


-- =============================================================
-- EXISTING GLASS SANDBOX NAMESPACES
-- =============================================================


hl.layer_rule({

    match = {
        namespace = "quickshell:glass-blur"
    },

    blur = true,

    ignore_alpha = 0.001
})


hl.layer_rule({

    match = {
        namespace = "quickshell:glass-material"
    },

    blur = true,

    ignore_alpha = 0.001
})