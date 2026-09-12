# Gaab Homelab ↔ Panacea

Bridge scripts and UI for using Panacea as a local operational console.

## Open

- Launcher: type `homelab` (or `Homelab`)
- IPC: `qs ipc -c panacea call pill homelab` (config path may vary)

## Config (separate from Panacea core)

```text
~/.config/gaab-homelab/
  services/     # YAML service defs → systemd --user units gaab-*.service
  projects/     # optional project pointers
  config/
  scripts/
```

## Service YAML example

```yaml
name: ascii-engine
directory: ~/dev/projects/ascii-engine
command: npm run dev
port: 3000
persistent: true
start_on_boot: true
restart: on-failure
```

Create via UI (`RUN` → `+ NEW SERVICE`) or:

```bash
~/.config/panacea/scripts/homelab.sh service-create "ascii-engine" "$HOME/dev/projects/ascii-engine" "npm run dev" 3000 true on-failure
~/.config/panacea/scripts/homelab.sh service-start ascii-engine
```

Process ownership: **systemd --user**. Closing Terminal or Panacea does not stop the service.

## Rules

- No `ollama pull` from Panacea
- No custom process manager — only `systemctl --user` / `journalctl --user` / Docker CLI
- Preserve Panacea visuals; extend, do not redesign
