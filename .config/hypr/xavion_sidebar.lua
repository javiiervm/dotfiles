local M = {}

-- Xavion's expanded panel must not use a layer-shell exclusive zone, because
-- that would also move Quickshell surfaces such as the dock and Dynamic Island.
-- Instead, this helper changes only Hyprland workspace gaps.

local function gap_profile(monitor_name)
    if monitor_name == "HDMI-A-1" then
        return {
            top = 10,
            right = 10,
            bottom = 10,
            left = 10,
            inner = 4,
        }
    end

    -- Laptop/default profile from hyprland.lua.
    return {
        top = 2,
        right = 12,
        bottom = 12,
        left = 12,
        inner = 5,
    }
end

function M.set(monitor_name, expanded, panel_width, panel_left)
    if not monitor_name or monitor_name == "" then
        return
    end

    local gaps = gap_profile(monitor_name)

    panel_width = tonumber(panel_width) or 450
    panel_left = tonumber(panel_left) or gaps.left

    local left_gap = gaps.left

    if expanded then
        left_gap = panel_left + panel_width + gaps.inner
    end

    hl.workspace_rule({
        workspace = "m[" .. monitor_name .. "]",
        gaps_out = {
            top = gaps.top,
            right = gaps.right,
            bottom = gaps.bottom,
            left = left_gap,
        },
    })

    hl.exec_scheduled_prop_refresh_immediately()
end

return M
