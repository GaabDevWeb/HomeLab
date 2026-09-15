# Homelab Polish — Implementation Plan (in progress)

> Execute phase-by-phase. No redesign.

**Goal:** Cohesive microinteractions + Command Palette on existing architecture.

**Stack:** Quickshell QML, Hyprland lua binds, shell.qml shared state.

## Done

- [x] Disable `bind_floatCenter`, keep SUPER+W float + SUPER+Space play-pause
- [x] `bind_pillCommands` = SUPER+SHIFT+Space via settings → genbinds → keybindings.lua
- [x] Fix stale `emptyWorkspace` in binds_data
- [x] CommandPaletteView + IPC `pill commands`
- [x] StatusGlyph / SmoothNumber helpers
- [x] uiMemory + SysLoad NOW tab + Calendar memory
- [x] Clipboard: selection, Ctrl+P, Delete, ✓ COPIED/PINNED

## Next

- [ ] Network sparkline micro in Homelab/Nav
- [ ] Docker status language + confirm destroy
- [ ] Directional page transitions
- [ ] Help cheatsheet entry
- [ ] Audio apply edge polish
- [ ] Regression + idle CPU/RAM check
