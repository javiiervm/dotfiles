-- =============================================================
-- QUICKSHELL LIQUID GLASS SURFACES
-- =============================================================
--
-- Lista central de superficies Quickshell que ya soportan
-- Liquid Glass real.
--
-- Cada componente migrado debe tener un namespace Wayland único.
--
-- Para añadir un nuevo componente:
--
-- {
--     namespace = "quickshell:component-name",
--     preset = "gnome_liquid_glass"
-- }
--
-- =============================================================


return {


    -- =========================================================
    -- LIQUID GLASS TEST
    -- =========================================================

    {
        namespace =
            "liquid-glass-test",

        preset =
            "gnome_liquid_glass"
    },


    -- =========================================================
    -- DOCK
    -- =========================================================

    {
        namespace =
            "quickshell:dock",

        preset =
            "gnome_liquid_glass"
    }

}