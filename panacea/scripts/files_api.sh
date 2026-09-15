#!/usr/bin/env bash
# Bonsai-ready filesystem façade — wraps files.sh without duplicating logic.
# Future: open_project / get_directory_info / get_file_info / search_files / get_git_status
set -euo pipefail
SH="$(cd "$(dirname "$0")" && pwd)/files.sh"
cmd="${1:-}"; shift || true
case "$cmd" in
  open_project|open-project)
    # $1 path — open FM at project (caller uses IPC); here just resolve+exists
    p=$(bash "$SH" resolve "$HOME" "${1:-.}")
    kind=$(bash "$SH" exists "$p")
    [[ "$kind" == dir ]] && printf '%s\n' "$p" || { echo "missing"; exit 1; }
    ;;
  get_directory_info|dir-info)
    p=$(bash "$SH" resolve "$HOME" "${1:-.}")
    [[ "$(bash "$SH" exists "$p")" == dir ]] || { echo '{"ok":false}'; exit 1; }
    n=$(find "$p" -mindepth 1 -maxdepth 1 2>/dev/null | wc -l | tr -d ' ')
    sz=$(du -sb "$p" 2>/dev/null | cut -f1)
    git=$(bash "$SH" git-brief "$p")
    python3 -c "import json; print(json.dumps({'ok':True,'path':'$p','items':int('$n'),'bytes':int('${sz:-0}'),'git':'$git'}))"
    ;;
  get_file_info|file-info)
    p=$(bash "$SH" resolve "$HOME" "${1:-}")
    bash "$SH" exists "$p" >/dev/null
    python3 - <<PY
import json, os, stat, time
p = """$p"""
st = os.stat(p)
print(json.dumps({
  "ok": True, "path": p, "name": os.path.basename(p),
  "size": st.st_size, "mtime": int(st.st_mtime),
  "mode": oct(st.st_mode & 0o777), "is_dir": os.path.isdir(p)
}))
PY
    ;;
  search_files|search)
    # current-dir only by default — never recursive scan unless depth given
    root=$(bash "$SH" resolve "$HOME" "${1:-.}"); q="${2:-}"; depth="${3:-1}"
    find "$root" -maxdepth "$depth" -iname "*${q}*" 2>/dev/null | head -200
    ;;
  get_git_status|git-status)
    bash "$SH" git-brief "${1:-.}"
    ;;
  *)
    echo "usage: files_api.sh open_project|dir-info|file-info|search|git-status" >&2
    exit 1
    ;;
esac
