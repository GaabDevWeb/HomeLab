# Homelab Rice — Polish Pass Design

**Date:** 2026-09-14  
**Constraint:** No redesign. Recycle shell.qml + IPC `pill` + motion tokens + existing views.

## Decisions locked

| Topic | Choice |
|-------|--------|
| Command Palette shortcut | `SUPER + SHIFT + Space` |
| Play/pause | Keep `SUPER + Space` (custom/keybindings.lua) |
| floatCenter | **Disabled** (`bind_floatCenter: ""`); float stays on `SUPER + W` |
| Launcher vs Palette | **Separate** — apps vs rice actions |
| emptyWorkspace | Disabled in settings; regenerate `binds_data.lua` so stale `SUPER + Space` disappears |

## Architecture

```
SYSTEM STATE (shell.qml)
   ├── metricsHistory / cal* / navStatusHub / uiMemory
   ├── StatusGlyph + SmoothNumber (shared QML)
   ├── pages via contentLoader + existing fade (directional later)
   └── CommandPaletteView → runAction(id) → togglePage / openHomelab / gotoWorkspace / …
```

## Command Palette

- Page id: `commands`
- IPC: `pill commands`
- Bind: `bind_pillCommands` → `keybindings.lua` `B("pillCommands", …)`
- Actions call existing handlers only (no arbitrary shell)
- Categories: Calendar, Sound, Clipboard, System, Network, Docker, Services, Projects, Bonsai, Workspaces (+ Help)

## Transversal polish (phased)

1. Binds hygiene + Palette  
2. StatusGlyph / loading verbs / SmoothNumber / uiMemory  
3. Metrics tooltips + last-updated + What's Happening  
4. Clipboard keys + ✓ COPIED / PINNED  
5. Calendar memory + navbar NEXT  
6. Audio apply confirmation (already mostly there)  
7. Bonsai status language alignment  
8. Help cheatsheet (SUPER+/ remains SetKeys; palette has “Show Shortcuts”)  
9. Regression + performance  

## Non-goals

Glow, particles, redesign, mock data, duplicate collectors, arbitrary shell from palette.
