-- Custom Keybindings & Shortcuts (Lua)
-- Wrapped in pcall: must never take down the whole Hyprland session.
pcall(function()
    local home = os.getenv("HOME") or ""
    local QS = "qs -c " .. home .. "/.config/panacea ipc call pill "

    -- Homelab console
    hl.bind("SUPER + SHIFT + H", hl.dsp.exec_cmd(QS .. "homelab"), { description = "Homelab console" })

    -- Restart rice: Hyprland config + pill (same sequence as update.sh, without theme restore)
    hl.bind("SUPER + SHIFT + R", hl.dsp.exec_cmd(
        "bash -c 'hyprctl reload >/dev/null 2>&1; (pkill -x qs >/dev/null 2>&1; sleep 1; exec env QSG_RENDER_LOOP=threaded qs -c \""
            .. home .. "/.config/panacea\") &'"
    ), { description = "Restart rice" })

    -- Close app (same smart close as Super+Q)
    hl.bind("ALT + F4", hl.dsp.exec_cmd(home .. "/.config/panacea/scripts/smart_close.sh"), {
        description = "Close window",
    })

    -- Media (Gaab): play/pause + skip + volume
    -- Super+Space was empty-workspace; disabled via binds_data emptyWorkspace=""
    -- Super+arrows: left/right = skip, up/down = volume (replaces movefocus)
    hl.bind("SUPER + Space", hl.dsp.exec_cmd("playerctl play-pause"), {
        description = "Play / Pause",
        locked = true,
    })
    hl.bind("SUPER + left", hl.dsp.exec_cmd("playerctl previous"), {
        description = "Previous track",
        locked = true,
    })
    hl.bind("SUPER + right", hl.dsp.exec_cmd("playerctl next"), {
        description = "Next track",
        locked = true,
    })
    hl.bind("SUPER + up", hl.dsp.exec_cmd(home .. "/.local/bin/smart_volume.sh up"), {
        description = "Volume up",
        locked = true,
        repeating = true,
    })
    hl.bind("SUPER + down", hl.dsp.exec_cmd(home .. "/.local/bin/smart_volume.sh down"), {
        description = "Volume down",
        locked = true,
        repeating = true,
    })
end)
