-- Quickshell Liquid Glass compositor integration.
--
-- NOTE: decoration.blur is still a global Hyprland compositor setting. It
-- lives here only to keep the Liquid Glass experiment organized with the
-- Quickshell blur routing below; Hyprland does not make size, passes, or
-- vibrancy per namespace.

hl.config({
    decoration = {
        blur = {
            enabled = true,
            -- size = 8,
            size = 10,
            -- passes = 2,
            passes = 5,
            new_optimizations = true,
            ignore_opacity = true,
            xray = false,
            -- vibrancy = 0.06,
            vibrancy = 0.1696
        },
    },
})

-- Existing explicit Quickshell surface.
hl.layer_rule({ match = { namespace = "wall_carousel" }, blur = true, ignore_alpha = 0.05 })

-- Isolated Liquid Glass sandbox.
-- quickshell:glass-raw intentionally has no blur rule.
hl.layer_rule({ match = { namespace = "quickshell:glass-blur" }, blur = true, ignore_alpha = 0.001 })
hl.layer_rule({ match = { namespace = "quickshell:glass-material" }, blur = true, ignore_alpha = 0.001 })

-- Future production namespaces should be added explicitly here when their
-- QML surfaces opt into Liquid Glass. Avoid a broad "quickshell" rule.
-- Examples:
-- hl.layer_rule({ match = { namespace = "quickshell:launcher" }, blur = true, ignore_alpha = 0.001 })
-- hl.layer_rule({ match = { namespace = "quickshell:notification-center" }, blur = true, ignore_alpha = 0.001 })
-- hl.layer_rule({ match = { namespace = "quickshell:island" }, blur = true, ignore_alpha = 0.001 })
-- hl.layer_rule({ match = { namespace = "quickshell:dock" }, blur = true, ignore_alpha = 0.001 })
-- hl.layer_rule({ match = { namespace = "quickshell:sysmenu" }, blur = true, ignore_alpha = 0.001 })