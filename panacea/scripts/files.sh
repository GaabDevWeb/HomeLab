#!/bin/bash
# Бэкенд проводника пилюли.
#
#   list DIR              -> строки  тип|имя|размер|мтайм|mime
#                            тип: d (каталог) | f (файл)
#   apps PATH             -> чем можно открыть: desktop-файл|Название|Иконка
#                            первым идёт приложение по умолчанию
#   open PATH [DESKTOP]   -> открыть (без DESKTOP — приложением по умолчанию)
#   mkdir DIR NAME        -> создать папку
#   rename PATH NEWNAME   -> переименовать
#   trash PATH            -> в корзину (обратимо, в отличие от rm)
#   places                -> закладки: ключ|путь|подпись
#   copy DST SRC...       -> копировать в каталог
#   move DST SRC...       -> перенести в каталог
#
# copy и move печатают в stdout строки «PROGRESS <проценты>»: пилюля рисует
# по ним полоску. Копирование гигабайтов иначе выглядит как зависание —
# файл не появляется, и понять, идёт работа или нет, нельзя.

py() { python3 "$@"; }

# ---------------------------------------------------------------- прогресс
# Ни cp, ни mv не умеют сообщать, сколько уже сделано, поэтому смотрим со
# стороны: раз в четверть секунды меряем, насколько выросли цели. rsync
# показал бы то же самое сам, но он не входит в base, а тянуть зависимость
# ради полоски не хочется.
#
# Меряем именно цели, а не каталог назначения целиком: назначением может
# быть домашняя папка, и du по ней каждые 250 мс стоил бы дороже самого
# копирования.
PROGRESS_PID=""

progress_start() {   # $1 — суммарный размер источников, дальше пути целей
    local total=$1; shift
    [ "$total" -gt 0 ] 2>/dev/null || return 0
    local targets=("$@")
    (
        while :; do
            local cur
            cur=$(du -sbc "${targets[@]}" 2>/dev/null | tail -1 | cut -f1)
            if [ -n "$cur" ]; then
                local pct=$(( cur * 100 / total ))
                [ "$pct" -gt 99 ] && pct=99   # 100 печатает уже сам вызов
                printf 'PROGRESS %d\n' "$pct"
            fi
            sleep 0.25
        done
    ) &
    PROGRESS_PID=$!
}

progress_kill() {
    [ -n "$PROGRESS_PID" ] && kill "$PROGRESS_PID" 2>/dev/null
    PROGRESS_PID=""
}

progress_stop() {
    progress_kill
    printf 'PROGRESS 100\n'
}

# Имя, свободное в каталоге назначения: не затираем существующее молча,
# а дописываем номер. Слова тут нарочно нет — скрипт не знает язык
# интерфейса.
uniq_target() {   # $1 — каталог назначения, $2 — имя
    local dst=$1 name=$2
    local target="$dst/$name"
    [ -e "$target" ] || { printf '%s' "$target"; return; }
    local base="${name%.*}" ext="${name##*.}" n=2
    while [ -e "$target" ]; do
        if [ "$base" = "$name" ]; then target="$dst/$name-$n"
        else                           target="$dst/$base-$n.$ext"; fi
        n=$((n + 1))
    done
    printf '%s' "$target"
}

case "$1" in
    # list <каталог> [hidden]
    # hidden — показывать файлы с точки. В домашнем каталоге почти всё
    # интересное начинается именно с неё (.config, .local), и прятать их
    # значит прятать ровно то, ради чего сюда и заходят.
    list)
        DIR="${2:-$HOME}"
        DIR="${DIR/#\~/$HOME}"
        # $3 = hidden | "" ; soft-cap evita congelar UI em pastas enormes
        py - "$DIR" "${3:-}" <<'EOF'
import os, sys, mimetypes

d = sys.argv[1]
show_hidden = len(sys.argv) > 2 and sys.argv[2] == 'hidden'
LIMIT = 2500
try:
    entries = list(os.scandir(d))
except OSError:
    sys.exit(0)

dirs, files = [], []
for e in entries:
    if e.name.startswith('.') and not show_hidden:
        continue
    try:
        st = e.stat()
    except OSError:
        continue
    if e.is_dir():
        dirs.append((e.name, 0, int(st.st_mtime), 'inode/directory'))
    else:
        mime = mimetypes.guess_type(e.name)[0] or 'application/octet-stream'
        files.append((e.name, st.st_size, int(st.st_mtime), mime))

key = lambda t: t[0].lower()
dirs.sort(key=key)
files.sort(key=key)
all_rows = [("d",) + t for t in dirs] + [("f",) + t for t in files]
total = len(all_rows)
shown = min(total, LIMIT)
print(f"#meta|{total}|{shown}")
for kind, name, size, mtime, mime in all_rows[:LIMIT]:
    print(f"{kind}|{name}|{size}|{mtime}|{mime}")
EOF
        ;;

    apps)
        P="${2:?}"
        P="${P/#\~/$HOME}"
        MIME=$(xdg-mime query filetype "$P" 2>/dev/null)
        DEFAULT=$(xdg-mime query default "$MIME" 2>/dev/null)
        py - "$MIME" "$DEFAULT" <<'EOF'
import configparser, os, sys

mime, default = sys.argv[1], sys.argv[2]
dirs = [os.path.expanduser("~/.local/share/applications"),
        "/usr/local/share/applications", "/usr/share/applications"]

group = mime.split("/")[0] + "/" if "/" in mime else ""

exact, similar, rest = {}, {}, {}
for d in dirs:
    if not os.path.isdir(d):
        continue
    for fn in os.listdir(d):
        if not fn.endswith(".desktop"):
            continue
        if fn in exact or fn in similar or fn in rest:
            continue
        cp = configparser.RawConfigParser(strict=False)
        try:
            cp.read(os.path.join(d, fn), encoding="utf-8")
            e = cp["Desktop Entry"]
        except Exception:
            continue
        if e.get("NoDisplay", "false").lower() == "true":
            continue
        if e.get("Type", "Application") != "Application":
            continue

        item = (e.get("Name", fn), e.get("Icon", ""))
        mimes = [m for m in e.get("MimeType", "").split(";") if m]
        if mime and mime in mimes:
            exact[fn] = item
        elif group and any(m.startswith(group) for m in mimes):
            similar[fn] = item
        else:
            # Мало какая программа объявляет все типы, которые тянет.
            # Показываем и остальные — пусть выбор будет за человеком.
            rest[fn] = item

def emit(fn, table):
    name, icon = table[fn]
    print(f"{fn}|{name}|{icon}")

# приложение по умолчанию — первой строкой, в какой бы группе ни оказалось
for table in (exact, similar, rest):
    if default in table:
        emit(default, table)
        break

for table in (exact, similar, rest):
    for fn in sorted(table, key=lambda f: table[f][0].lower()):
        if fn != default:
            emit(fn, table)
EOF
        ;;

    open)
        P="${2:?}"
        P="${P/#\~/$HOME}"
        DESKTOP="$3"
        if [ -n "$DESKTOP" ]; then
            for d in "$HOME/.local/share/applications" /usr/local/share/applications \
                     /usr/share/applications; do
                if [ -f "$d/$DESKTOP" ]; then
                    setsid gio launch "$d/$DESKTOP" "$P" >/dev/null 2>&1 &
                    exit 0
                fi
            done
        fi
        setsid xdg-open "$P" >/dev/null 2>&1 &
        ;;

    mkdir)
        D="${2:?}"; N="${3:?}"
        D="${D/#\~/$HOME}"
        mkdir -p "$D/$N"
        ;;

    touch)
        D="${2:?}"; N="${3:?}"
        D="${D/#\~/$HOME}"
        # não sobrescrever
        [ -e "$D/$N" ] && exit 1
        : > "$D/$N"
        ;;

    rename)
        P="${2:?}"; N="${3:?}"
        P="${P/#\~/$HOME}"
        mv -n "$P" "$(dirname "$P")/$N"
        ;;

    trash)
        shift
        for P; do
            P="${P/#\~/$HOME}"
            gio trash "$P" 2>/dev/null || rm -rf -- "$P"
        done
        ;;

    extract)
        SRC="${2:?}"
        DST="${3:-}"
        SRC="${SRC/#\~/$HOME}"
        [ -f "$SRC" ] || exit 1

        if [ -z "$DST" ]; then
            DST="$(dirname "$SRC")"
        fi
        DST="${DST/#\~/$HOME}"
        mkdir -p "$DST" || exit 1

        if command -v bsdtar >/dev/null 2>&1; then
            bsdtar -xf "$SRC" -C "$DST"
        elif [[ "$SRC" =~ \.zip$ ]] && command -v unzip >/dev/null 2>&1; then
            unzip -q -o "$SRC" -d "$DST"
        elif [[ "$SRC" =~ \.7z$ ]] && command -v 7z >/dev/null 2>&1; then
            7z x -y -o"$DST" "$SRC"
        elif [[ "$SRC" =~ \.rar$ ]] && command -v unrar >/dev/null 2>&1; then
            unrar x -y "$SRC" "$DST/"
        else
            tar -xf "$SRC" -C "$DST"
        fi
        ;;

    # Каталог назначения идёт первым, источники — списком: так один вызов
    # переносит хоть один файл, хоть выделение целиком, и полоска считает
    # общий объём, а не каждый файл заново.
    # Что из перетаскиваемого уже лежит в каталоге назначения. Печатает по
    # одному имени в строке; пусто — совпадений нет.
    #
    # Спрашиваем отдельно, а не разбираемся по ходу копирования: решение о
    # перезаписи принимает человек, и принять его надо ДО того, как первый файл
    # уже перезаписан. Заодно вопрос задаётся один раз на всю пачку, а не по
    # файлу.
    conflicts)
        DST="${2:?}"; shift 2
        DST="${DST/#\~/$HOME}"
        for src; do
            src="${src/#\~/$HOME}"
            name="$(basename "$src")"
            # Сам себя файл не перекрывает: источник и цель — одно и то же.
            [ "$src" = "$DST/$name" ] && continue
            [ -e "$DST/$name" ] && printf '%s\n' "$name"
        done
        ;;

    copy|move)
        op="$1"
        DST="${2:?}"
        # Что делать с уже существующими именами:
        #   keepboth  — рядом, с номером (как было всегда)
        #   overwrite — заменить
        #   skip      — не трогать, оставить как есть
        MODE="${3:-keepboth}"
        shift 3
        DST="${DST/#\~/$HOME}"
        [ "$#" -gt 0 ] || exit 0

        srcs=(); targets=()
        for src; do
            src="${src/#\~/$HOME}"
            [ -e "$src" ] || continue
            name="$(basename "$src")"
            case "$MODE" in
                overwrite) target="$DST/$name" ;;
                skip)
                    # Уже есть — просто пропускаем этот файл, остальные едут.
                    [ -e "$DST/$name" ] && [ "$src" != "$DST/$name" ] && continue
                    target="$DST/$name"
                    ;;
                *) target="$(uniq_target "$DST" "$name")" ;;
            esac
            srcs+=("$src")
            targets+=("$target")
        done
        [ "${#srcs[@]}" -gt 0 ] || exit 0

        # Оболочку могут убить вместе с панелью, и без этого счётчик остался бы
        # сиротой: крутиться вечно, раз в четверть секунды обходя каталог.
        trap progress_kill EXIT INT TERM

        total=$(du -sbc "${srcs[@]}" 2>/dev/null | tail -1 | cut -f1)
        progress_start "${total:-0}" "${targets[@]}"

        for i in "${!srcs[@]}"; do
            # При замене цель сносим заранее, а не полагаемся на -f.
            #
            # И cp, и mv, встретив на месте цели КАТАЛОГ, кладут источник
            # ВНУТРЬ него: вместо замены папки «Фото» получалась бы
            # «Фото/Фото». Для файлов -f сработал бы, для каталогов — нет,
            # поэтому убираем цель сами и в обоих случаях.
            if [ "$MODE" = "overwrite" ] && [ -e "${targets[$i]}" ] \
               && [ "${srcs[$i]}" != "${targets[$i]}" ]; then
                rm -rf -- "${targets[$i]}"
            fi

            if [ "$op" = "copy" ]; then
                cp -r --no-clobber "${srcs[$i]}" "${targets[$i]}"
            else
                mv -n "${srcs[$i]}" "${targets[$i]}"
            fi
        done

        progress_stop
        ;;

    copypath)
        P="${2:?}"
        P="${P/#\~/$HOME}"
        printf '%s' "$P" | wl-copy
        ;;

    places)
        # Подписи здесь черновые: интерфейс переводит их сам по ключу.
        printf 'home|%s|Home\n' "$HOME"
        for k in Downloads Documents Pictures Videos Music Desktop; do
            [ -d "$HOME/$k" ] && printf '%s|%s/%s|%s\n' "${k,,}" "$HOME" "$k" "$k"
        done
        printf 'root|/|System\n'
        # корзина — последней: это не место, куда ходят по делу
        printf 'trash|%s/Trash/files|Trash\n' "${XDG_DATA_HOME:-$HOME/.local/share}"
        ;;

disks)
    # Смонтированные носители и съёмные накопители (включая неподключённые флешки).
    #   вид|путь|подпись|всего_байт|занято_байт|устройство
    # вид: disk (внутренний) | removable (флешка, карта, телефон)
    python3 -c '
import subprocess, json, sys, os, re

seen = set()
results = []

# 1. Смонтированные блочные устройства (через df)
try:
    df_p = subprocess.run(["df", "-B1", "--output=source,target,size,used", "-x", "tmpfs", "-x", "devtmpfs", "-x", "squashfs", "-x", "overlay", "-x", "efivarfs", "-x", "ramfs"], capture_output=True, text=True)
    for line in df_p.stdout.strip().split("\n")[1:]:
        parts = line.split()
        if len(parts) < 4: continue
        src, target, size, used = parts[0], parts[1], parts[2], parts[3]
        if not src.startswith("/dev/"): continue
        if any(target.startswith(p) for p in ["/boot", "/efi", "/var/lib/docker", "/snap"]): continue
        if src in seen: continue
        seen.add(src)
        
        lbl = subprocess.run(["lsblk", "-d", "-no", "LABEL", src], capture_output=True, text=True).stdout.strip()
        if not lbl:
            lbl = "System" if target == "/" else os.path.basename(target)
            
        info = subprocess.run(["lsblk", "-d", "-no", "RM,HOTPLUG,TRAN,SUBSYSTEMS", src], capture_output=True, text=True).stdout.lower()
        pk = subprocess.run(["lsblk", "-no", "PKNAME", src], capture_output=True, text=True).stdout.strip()
        p_info = subprocess.run(["lsblk", "-d", "-no", "RM,HOTPLUG,TRAN,SUBSYSTEMS", f"/dev/{pk}"], capture_output=True, text=True).stdout.lower() if pk else ""
        
        is_rem = target.startswith("/run/media/") or target.startswith("/media/") or "usb" in info or "usb" in p_info or "mmc" in info or "1" in info.split()[:2]
        kind = "removable" if is_rem else "disk"
        results.append(f"{kind}|{target}|{lbl}|{size}|{used}|{src}")
except Exception:
    pass

# 2. Несмонтированные съёмные накопители (флешки, карты памяти, внешние диски)
try:
    res = subprocess.run(["lsblk", "-J", "-b", "-o", "PATH,KNAME,TYPE,RM,HOTPLUG,TRAN,SUBSYSTEMS,SIZE,FSTYPE,LABEL,MOUNTPOINT,PKNAME,MODEL"], capture_output=True, text=True)
    devs = json.loads(res.stdout).get("blockdevices", [])
    
    def flatten(nodes):
        out = []
        for n in nodes:
            out.append(n)
            if "children" in n:
                out.extend(flatten(n["children"]))
        return out

    all_devs = flatten(devs)
    dev_map = {d.get("kname") or d.get("path", "").replace("/dev/", ""): d for d in all_devs}

    for d in all_devs:
        p = d.get("path", "")
        if not p.startswith("/dev/") or p.startswith(("/dev/zram", "/dev/loop", "/dev/sr")): continue
        fstype = d.get("fstype")
        if not fstype or fstype == "swap": continue
        mp = d.get("mountpoint")
        if mp or p in seen: continue
        
        tran = (d.get("tran") or "").lower()
        subs = (d.get("subsystems") or "").lower()
        rm = d.get("rm")
        hp = d.get("hotplug")
        
        pk = d.get("pkname")
        p_dev = dev_map.get(pk, {})
        p_tran = (p_dev.get("tran") or "").lower()
        p_subs = (p_dev.get("subsystems") or "").lower()
        p_rm = p_dev.get("rm")
        
        is_rem = (tran == "usb" or p_tran == "usb" or "usb" in subs or "usb" in p_subs or rm or hp or p_rm)
        if is_rem:
            seen.add(p)
            lbl = d.get("label") or d.get("model") or p_dev.get("model") or os.path.basename(p)
            size = d.get("size") or 0
            results.append(f"removable||{lbl}|{size}|0|{p}")
except Exception:
    pass

# 3. MTP устройства (Android телефоны) и GVFS
try:
    if os.path.isfile("/proc/mounts"):
        with open("/proc/mounts", "r") as f:
            for line in f:
                parts = line.strip().split()
                if len(parts) < 3: continue
                fs_src, fs_target, fs_type = parts[0], parts[1], parts[2]
                if fs_type in ["fuse.mtpfs", "mtpfs", "jmtpfs", "simple-mtpfs"]:
                    if os.path.isdir(fs_target):
                        results.append(f"removable|{fs_target}|{os.path.basename(fs_target)}|0|0|mtp")
                elif fs_type == "fuse.gvfsd-fuse":
                    if os.path.isdir(fs_target):
                        for dev_name in os.listdir(fs_target):
                            dev_path = os.path.join(fs_target, dev_name)
                            if os.path.isdir(dev_path):
                                pretty = re.sub(r"^[a-zA-Z0-9+.-]*:host=", "", dev_name)
                                pretty = re.sub(r"%2C.*$", "", pretty).replace("%20", " ").replace("_", " ")
                                if not pretty: pretty = dev_name
                                results.append(f"removable|{dev_path}|{pretty}|0|0|gvfs")
except Exception:
    pass

for r in results:
    print(r)
'
    ;;

mountdisk)
    dev="$2"
    [ -n "$dev" ] || exit 1
    # Сначала проверяем, не смонтирован ли уже
    mp=$(findmnt -n -o TARGET "$dev" 2>/dev/null | head -1)
    if [ -n "$mp" ] && [ -d "$mp" ]; then
        printf '%s\n' "$mp"
        exit 0
    fi
    out=$(udisksctl mount -b "$dev" 2>&1)
    if [ $? -eq 0 ]; then
        mp=$(printf '%s' "$out" | sed -n 's/^Mounted .* at \(.*\)\./\1/p' | sed 's/\.$//')
        if [ -n "$mp" ] && [ -d "$mp" ]; then
            printf '%s\n' "$mp"
            exit 0
        fi
    fi
    gio mount -d "$dev" 2>/dev/null
    mp=$(findmnt -n -o TARGET "$dev" 2>/dev/null | head -1)
    if [ -n "$mp" ] && [ -d "$mp" ]; then
        printf '%s\n' "$mp"
        exit 0
    fi
    ;;

unmountdisk)
    target="$2"
    [ -n "$target" ] || exit 1
    if [ -b "$target" ]; then
        udisksctl unmount -b "$target" 2>/dev/null || gio mount -u "$target" 2>/dev/null
    else
        udisksctl unmount -p "$target" 2>/dev/null || udisksctl unmount -b "$(findmnt -n -o SOURCE "$target" 2>/dev/null)" 2>/dev/null || gio mount -u "$target" 2>/dev/null
    fi
    ;;

ejectdisk)
    target="$2"
    [ -n "$target" ] || exit 1
    if [ -b "$target" ]; then
        dev="$target"
    else
        dev=$(findmnt -n -o SOURCE "$target" 2>/dev/null)
    fi
    if [ -n "$dev" ] && [ -b "$dev" ]; then
        udisksctl unmount -b "$dev" 2>/dev/null || gio mount -u "$dev" 2>/dev/null
        parent=$(lsblk -no PKNAME "$dev" 2>/dev/null | head -1)
        if [ -n "$parent" ]; then
            udisksctl power-off -b "/dev/$parent" 2>/dev/null
        else
            udisksctl power-off -b "$dev" 2>/dev/null
        fi
    elif [ -n "$target" ]; then
        gio mount -e "$target" 2>/dev/null || gio mount -u "$target" 2>/dev/null
    fi
    ;;

    emptytrash)
        # gio trash --empty ходит через gvfs, а его в системе может не быть
        # («Operation not supported»). Чистим корзину сами — она устроена
        # ровно по freedesktop-спецификации: files, info и expunged.
        base="${XDG_DATA_HOME:-$HOME/.local/share}/Trash"
        case "$base" in
            */Trash) ;;
            *) exit 1 ;;          # подстраховка: мало ли что в переменной
        esac
        for d in files info expunged; do
            [ -d "$base/$d" ] || continue
            find "$base/$d" -mindepth 1 -maxdepth 1 -exec rm -rf {} +
        done
        ;;

    trashcount)
        d="${XDG_DATA_HOME:-$HOME/.local/share}/Trash/files"
        [ -d "$d" ] || { echo 0; exit 0; }
        find "$d" -mindepth 1 -maxdepth 1 | wc -l
        ;;

    # FM 2.0 — helpers partilhados (UI + futuro Bonsai)
    # Nota: $1 é sempre o subcomando; paths começam em $2.
    exists)
        if [ -d "$2" ]; then echo dir
        elif [ -e "$2" ]; then echo file
        else echo missing
        fi
        ;;

    resolve)
        py - "$2" "$3" <<'PY'
import os, sys
base, raw = sys.argv[1], sys.argv[2].strip()
home = os.path.expanduser("~")
if raw == "~":
    path = home
elif raw.startswith("~/"):
    path = os.path.join(home, raw[2:])
elif raw.startswith("/"):
    path = raw
else:
    path = os.path.join(base or home, raw)
print(os.path.abspath(path))
PY
        ;;

    favorites-list|recent-list|favorites-add|favorites-remove|recent-push)
        META="${XDG_CONFIG_HOME:-$HOME/.config}/panacea/files_meta.json"
        mkdir -p "$(dirname "$META")"
        py - "$META" "$1" "${2:-}" "${3:-}" <<'PY'
import json, os, sys, time
path, op = sys.argv[1], sys.argv[2]
arg = sys.argv[3] if len(sys.argv) > 3 else ""
label = sys.argv[4] if len(sys.argv) > 4 else ""
data = {"favorites": [], "recent": []}
if os.path.isfile(path):
    try:
        with open(path) as f:
            data.update(json.load(f) or {})
    except Exception:
        pass
favs = list(data.get("favorites") or [])
rec = list(data.get("recent") or [])

def save():
    data["favorites"] = favs
    data["recent"] = rec
    with open(path, "w") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)

if op == "favorites-list":
    for e in favs:
        p = e.get("path") if isinstance(e, dict) else e
        n = (e.get("label") if isinstance(e, dict) else "") or os.path.basename(p.rstrip("/")) or p
        print(f"{p}|{n}")
elif op == "recent-list":
    for e in rec[:16]:
        p = e.get("path") if isinstance(e, dict) else e
        print(p)
elif op == "favorites-add":
    if not arg: raise SystemExit(0)
    favs = [e for e in favs if (e.get("path") if isinstance(e, dict) else e) != arg]
    favs.insert(0, {"path": arg, "label": label or os.path.basename(arg.rstrip("/")) or arg})
    favs = favs[:24]
    save()
elif op == "favorites-remove":
    favs = [e for e in favs if (e.get("path") if isinstance(e, dict) else e) != arg]
    save()
elif op == "recent-push":
    if not arg or not os.path.isdir(arg): raise SystemExit(0)
    arg = os.path.abspath(arg)
    rec = [e for e in rec if (e.get("path") if isinstance(e, dict) else e) != arg]
    rec.insert(0, {"path": arg, "at": int(time.time())})
    rec = rec[:16]
    save()
PY
        ;;

    restore)
        shift
        for p in "$@"; do
            p="${p/#\~/$HOME}"
            [ -e "$p" ] || continue
            if gio trash --restore "$p" 2>/dev/null; then
                continue
            fi
            base=$(basename -- "$p")
            trash_root=$(dirname "$(dirname -- "$p")")
            info="$trash_root/info/${base}.trashinfo"
            dest=""
            if [ -f "$info" ]; then
                dest=$(grep -m1 '^Path=' "$info" 2>/dev/null | cut -d= -f2-)
                dest=$(python3 -c "import sys,urllib.parse; print(urllib.parse.unquote(sys.argv[1]))" "$dest" 2>/dev/null || echo "$dest")
            fi
            if [ -n "$dest" ]; then
                mkdir -p "$(dirname -- "$dest")" 2>/dev/null || true
                mv -n -- "$p" "$dest" 2>/dev/null || mv -- "$p" "$dest"
                rm -f -- "$info"
            else
                mkdir -p "$HOME/Restored"
                mv -n -- "$p" "$HOME/Restored/" 2>/dev/null || mv -- "$p" "$HOME/Restored/"
            fi
        done
        ;;

    delete-permanent)
        shift
        for p in "$@"; do
            p="${p/#\~/$HOME}"
            base=$(basename -- "$p")
            trash_root=$(dirname "$(dirname -- "$p")")
            case "$trash_root" in
                */Trash)
                    rm -f -- "$trash_root/info/${base}.trashinfo"
                    ;;
            esac
            rm -rf -- "$p"
        done
        ;;

    which-code)
        command -v code >/dev/null 2>&1 && echo code || echo ""
        ;;

    git-brief)
        d="${2:-}"
        [ -d "$d" ] || { echo NONE; exit 0; }
        if ! git -C "$d" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
            echo NONE; exit 0
        fi
        n=$(git -C "$d" status --porcelain 2>/dev/null | wc -l | tr -d ' ')
        if [ "${n:-0}" -eq 0 ]; then echo CLEAN
        else echo "$n CHANGED"
        fi
        ;;

    git-status-list)
        d="${2:-}"
        [ -d "$d" ] || exit 0
        git -C "$d" rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0
        git -C "$d" status --porcelain -u 2>/dev/null | head -80
        ;;

    git-log)
        d="${2:-}"
        [ -d "$d" ] || exit 0
        git -C "$d" rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0
        git -C "$d" log --oneline -40 2>/dev/null
        ;;

    git-init)
        d="${2:-}"
        [ -d "$d" ] || exit 1
        git -C "$d" init >/dev/null 2>&1
        echo OK
        ;;

    path-complete)
        # $2 cwd  $3 typed — até 12 sugestões
        py - "$2" "$3" <<'PY'
import os, sys
cwd, raw = sys.argv[1], (sys.argv[2] if len(sys.argv) > 2 else "").strip()
home = os.path.expanduser("~")

def expand(s):
    if s == "~":
        return home
    if s.startswith("~/"):
        return os.path.join(home, s[2:])
    if s.startswith("/"):
        return s
    return os.path.join(cwd, s)

if not raw:
    raw = cwd.rstrip("/") + "/"

listing = raw.endswith("/")
path = expand(raw)
if listing:
    directory = os.path.abspath(path)
    prefix = ""
else:
    directory = os.path.dirname(os.path.abspath(path)) or "/"
    prefix = os.path.basename(path)

try:
    names = sorted(os.listdir(directory))
except OSError:
    sys.exit(0)

nout = 0
for n in names:
    if prefix and not n.lower().startswith(prefix.lower()):
        continue
    if n.startswith(".") and not (prefix.startswith(".") if prefix else False):
        continue
    full = os.path.join(directory, n)
    is_dir = os.path.isdir(full)
    print(("dir|" if is_dir else "file|") + full + ("/" if is_dir else ""))
    nout += 1
    if nout >= 12:
        break
PY
        ;;

    preview)
        # $2 path — texto até 256KB; imagem só meta
        f="${2:?}"
        f="${f/#\~/$HOME}"
        [ -f "$f" ] || { echo "error	not a file"; exit 1; }
        bytes=$(stat -c '%s' "$f" 2>/dev/null || echo 0)
        mime=$(file -b --mime-type "$f" 2>/dev/null || echo unknown)
        emit() { printf '%s\t%s\n' "$1" "$2"; }
        emit name "$(basename -- "$f")"
        emit path "$f"
        emit kind "$mime"
        emit size_bytes "$bytes"
        emit size_human "$(numfmt --to=iec --suffix=B "$bytes" 2>/dev/null || echo "$bytes")"
        case "$mime" in
            image/*)
                emit preview_kind image
                if command -v ffprobe >/dev/null 2>&1; then
                    wh=$(ffprobe -v error -select_streams v:0 \
                         -show_entries stream=width,height -of csv=p=0:s=x "$f" 2>/dev/null)
                    [ -n "$wh" ] && emit resolution "$wh"
                fi
                exit 0
                ;;
        esac
        ext="${f##*.}"
        ext_lc=$(printf '%s' "$ext" | tr 'A-Z' 'a-z')
        case "$ext_lc" in
            txt|md|json|yaml|yml|toml|py|js|ts|tsx|jsx|sh|bash|zsh|css|html|htm|xml|ini|conf|cfg|rs|go|c|h|cpp|hpp|java|qml|lua|rb|php|sql|env|log|csv)
                ;;
            *)
                case "$mime" in
                    text/*|application/json|application/xml|application/x-sh|application/javascript) ;;
                    *) emit preview_kind none; emit error "not previewable"; exit 0 ;;
                esac
                ;;
        esac
        if [ "${bytes:-0}" -gt 262144 ]; then
            emit preview_kind too_large
            emit error "file too large for preview (>256KB)"
            exit 0
        fi
        emit preview_kind text
        lines=$(wc -l < "$f" 2>/dev/null | tr -d ' ')
        emit lines "${lines:-0}"
        printf 'content_begin\t—\n'
        head -c 262144 "$f" 2>/dev/null | tr -d '\0'
        printf '\ncontent_end\t—\n'
        ;;

    terminal-here)
        d="${2:-$HOME}"
        [ -d "$d" ] || d="$(dirname "$d")"
        [ -d "$d" ] || d="$HOME"
        if command -v footclient >/dev/null 2>&1; then
            setsid -f footclient --working-directory="$d" >/dev/null 2>&1
        else
            setsid -f foot --working-directory="$d" >/dev/null 2>&1
        fi
        ;;

    open-code)
        d="${2:-}"
        command -v code >/dev/null 2>&1 || exit 1
        setsid -f code -- "$d" >/dev/null 2>&1
        ;;

    *)
        echo "usage: files.sh … preview | git-status-list | restore | delete-permanent | …" >&2
        exit 1
        ;;
esac
