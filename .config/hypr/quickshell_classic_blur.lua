-- =============================================================
-- QUICKSHELL CLASSIC BLUR MODE
-- =============================================================
--
-- Modo global:
--
--   classic
--
-- Las superficies Quickshell vuelven a utilizar exclusivamente el
-- blur normal de Hyprland.
--
-- IMPORTANTE:
--
-- HyprGlass puede conservar opciones de layer surfaces aplicadas por
-- el modo Liquid entre recargas de Hyprland. Por eso no basta con
-- desactivar `layers.enabled`: también devolvemos explícitamente la
-- gestión del blur a Hyprland mediante `manage_blur = false`.
--
-- Esto evita que HyprGlass intercepte la región
-- ext-background-effect-v1 solicitada por el dock y la renderice como
-- una superficie/material separado.
-- =============================================================


if hl.plugin.hyprglass then

    local hg =
        hl.plugin.hyprglass


    hg.config({

        -- Nunca aplicar HyprGlass automáticamente a ventanas normales.
        enabled = false,


        layers = {

            -- Desactivar completamente Liquid Glass en layer surfaces.
            enabled = false,


            -- En Classic el blur vuelve a pertenecer a Hyprland.
            --
            -- El dock ya publica su región redondeada exacta mediante
            -- BackgroundEffect.blurRegion, por lo que Hyprland puede
            -- renderizar el blur clásico directamente en esa geometría.
            manage_blur = false,


            -- No conservar el refresco forzado del modo Liquid.
            force_live_resample = false
        }
    })

end
