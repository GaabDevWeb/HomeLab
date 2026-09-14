#!/usr/bin/env bash
# Filtro local antes de cliphist store — NÃO envia nada à rede.
# Uso: wl-paste --type text --watch ~/.config/panacea/scripts/clip_store.sh
set -euo pipefail

IGNORE_SENSITIVE="${PANACEA_CLIP_IGNORE_SENSITIVE:-1}"
MAX_BYTES="${PANACEA_CLIP_MAX_BYTES:-262144}"  # 256 KiB

content=$(cat)
# vazio / enorme
[ -z "$content" ] && exit 0
bytes=$(printf '%s' "$content" | wc -c)
[ "$bytes" -gt "$MAX_BYTES" ] && exit 0

if [ "$IGNORE_SENSITIVE" = "1" ]; then
  # heurística conservadora — preferir omitir a expor
  if printf '%s' "$content" | grep -Eqi \
    -e 'BEGIN (OPENSSH |RSA |EC |DSA )?PRIVATE KEY' \
    -e '-----BEGIN .*PRIVATE KEY-----' \
    -e '^(password|passwd|secret|token|api[_-]?key)\s*[:=]' \
    -e 'eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+' \
    -e 'ghp_[A-Za-z0-9]{20,}' \
    -e 'sk-[A-Za-z0-9]{20,}' \
    -e 'xox[baprs]-[A-Za-z0-9-]{10,}'; then
    exit 0
  fi
fi

printf '%s' "$content" | cliphist store
