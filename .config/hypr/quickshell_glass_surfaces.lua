-- =============================================================
-- QUICKSHELL LIQUID GLASS SURFACES
-- =============================================================
--
-- Central list of Quickshell layer surfaces already migrated to
-- real HyprGlass Liquid Glass.
-- =============================================================

return {

    -- Liquid Glass sandbox
    {
        namespace = "liquid-glass-test",
        preset = "gnome_liquid_glass"
    },

    -- Dock
    {
        namespace = "quickshell:dock",
        preset = "gnome_liquid_glass"
    },

    -- Fullscreen clock + battery ghost island
    {
        namespace = "quickshell:fullscreen-ghost",
        preset = "gnome_liquid_glass"
    },

    -- System status popup menu
    {
        namespace = "quickshell:sysmenu",
        preset = "gnome_liquid_glass"
    },

    -- Top bar left/right capsules
    {
        namespace = "quickshell:topbar",
        preset = "gnome_liquid_glass"
    },

    -- Clipboard popup
    {
        namespace = "quickshell:clipboard",
        preset = "gnome_liquid_glass"
    }

}
