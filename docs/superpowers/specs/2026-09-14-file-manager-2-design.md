# File Manager 2.0 — Design (no redesign)

**image_attachment:** referência do visual existente (preservar identidade). Sem geração de redesign.

## Auditoria

### EXISTENTE
- `FilesView.qml` (~2959 L): sidebar places/disks, list/grid, multi-select, rubber band, DnD, filter typing, sort, hidden files
- Clipboard interno `clipPaths`/`clipMode` + Ctrl+C/X/V
- `doCopyPath` → wl-copy; F2 rename; Ctrl+N mkdir; Delete → trash
- Context menu: open/open-with/copy/cut/paste/rename/copy-path/props/mkdir/refresh/empty trash
- `props.sh` + props panel; `files.sh` backend + `shell.runFileOp` progress
- Multi-window via `filesWindows` (não tabs)
- Super+E → files; Super+Shift+E → yazi

### REUTILIZAR
- `files.sh`, `runFileOp`, `filesChanged`, `startFileDrag`, `openFileWith`
- Sidebar, list/grid, selection, DnD, props panel, clipPaths, dialog rename/mkdir

### MODIFICAR
- `go()`/`dir` → estado por aba + histórico
- Header → tab bar + breadcrumb/path edit
- Context menu → terminal/code/favorites
- Keys → Ctrl+T/W/L, Alt+←/→, Ctrl+Shift+C/T
- Middle-click em pasta → nova aba

### CRIAR
- Modelo de abas + closed-tab stack
- Breadcrumb clicável + path edit (Ctrl+L)
- Favorites persistidos + Recent locations
- Preview texto (fase 4); Git badge (fase 5); Bonsai stubs (fase 6)
- Trash restore / permanent delete

## Fases
1. Tabs + middle-click + hist back/forward
2. Path bar + copy path + paste into folder
3. Favorites/Recent + context menu (terminal/code)
4–7. Preview, ops polish, Git, Bonsai, regression
