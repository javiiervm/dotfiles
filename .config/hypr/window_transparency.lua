-- Normal application window transparency.
-- This is intentionally separate from Quickshell Liquid Glass routing so it
-- can be disabled or tuned without touching shell surfaces.

hl.config({
    decoration = {
        -- active_opacity = 0.85,
        -- inactive_opacity = 0.75,
        active_opacity = 0.95,
        inactive_opacity = 0.9,
    },
})