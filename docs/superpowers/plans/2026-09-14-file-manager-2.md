# File Manager 2.0 — Implementation Report

## Auditoria (resumo)

| | |
|--|--|
| **EXISTENTE** | FilesView monolito, places/disks, list/grid, multi-select, DnD, Ctrl+C/X/V interno, trash, props, filter, sort, `runFileOp` |
| **REUTILIZAR** | `files.sh`, shell drag/op queue, sidebar, clipboard interno, props panel |
| **MODIFICAR** | `go()`+estado → tabs; header → breadcrumb; menu; keys |
| **CRIAR** | tabs, hist, path edit, favorites/recent, terminal/code, `files_api.sh` |

## Entregue (Fases 1–3 + stubs)

1. **Tabs** — `fileTabs` modelo; `+` / Ctrl+T; close × / Ctrl+W / middle-click; Ctrl+Shift+T reopen; menu CLOSE/OTHERS/TO RIGHT/REOPEN
2. **Middle-click pasta** → nova aba (obrigatório)
3. **Histórico** por aba — Alt+Left / Alt+Right
4. **Breadcrumb** clicável + Ctrl+L path edit (~ / relativo / absoluto) + PATH NOT FOUND
5. **Copy path** botão + Ctrl+Shift+C (seleção ou cwd)
6. **Paste into folder** se 1 pasta selecionada
7. **Favorites / Recent** sidebar + `files_meta.json`
8. **Context** — Open in New Tab, Terminal Here, VS Code, Add to Favorites, New File
9. **Git badge** discreto `GIT · CLEAN|N CHANGED`
10. **Empty trash** confirmação em 2 cliques
11. **Bonsai prep** — `scripts/files_api.sh` (`open_project`, `dir-info`, `file-info`, `search`, `git-status`)

## Entregue Fases 6–7

18. **FS watcher** — `inotifywait -m` com debounce 480ms; fallback poll mtime 2.5s
19. **Pastas enormes** — soft-cap 2500 entries + banner `SHOWING N / M · type to filter` (ListView já virtualiza render)
20. **Path autocomplete** — Ctrl+L + Tab/↑↓; `files.sh path-complete`
21. **Git por pasta** — menu: Status / Log --oneline / Init; badge GIT; Ctrl+G / Ctrl+Shift+G

## Limitações conscientes

- Cap 2500: filtrar localmente nos carregados; não indexa disco inteiro
- Watcher: eventos no dir atual (não recursivo) — leve e previsível
- Virtualização = ListView + cap de carga (não windowing custom no modelo)

## Entregue Fases 4–5

12. **Preview** — Space / menu Preview; texto ≤256KB; imagem via `Image`; meta size/lines/mime
13. **Trash** — Restore · Delete Permanently (Shift+Delete) · Empty com diálogo CANCEL/EMPTY
14. **Git panel** — clique no badge → status porcelain + TERMINAL / VS CODE
15. **Cut/copy visual** — opacity 0.42 cut / 0.78 copy
16. **DROP HERE** — label no drop target
17. **`files.sh preview` + `git-status-list` + restore melhorado**

## Arquivos

- `panacea/FilesView.qml`
- `panacea/scripts/files.sh`
- `panacea/scripts/files_api.sh` (novo)
- `docs/superpowers/specs/2026-09-14-file-manager-2-design.md`

## Atalhos

| Atalho | Ação |
|--------|------|
| Ctrl+T | Nova aba (Home) |
| Ctrl+W | Fechar aba |
| Ctrl+Shift+T | Reabrir |
| Ctrl+L | Editar path |
| Ctrl+Shift+C | Copy path |
| Ctrl+C/X/V | Copy/Cut/Paste ficheiros |
| F2 / F5 | Rename / Refresh |
| Alt+←/→ | Back / Forward |
| Middle folder | Nova aba |
| Middle tab | Fechar aba |

## Design

Sem redesign — tab bar + breadcrumb no idioma visual existente (radius 9–14, mono, grayscale accents).
