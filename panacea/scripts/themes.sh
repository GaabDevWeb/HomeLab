#!/bin/bash
# Обои для страницы выбора.
#
#   list              -> строки  имя|миниатюра|активны(yes|no)|своя(yes|no)|полный_путь
#   set NAME|PATH     -> применить
#   add <путь>        -> скопировать файл в свои обои и применить
#   del NAME          -> удалить свои обои
#   library           -> путь к связанной папке (или пусто)
#   library set <dir> -> связать одну папку (без копирования; заменяет прежнюю)
#   library clear     -> отвязать папку
#
# Тем как наборов цветов больше нет: палитра одна (hypr/palette.conf), и
# «тема» — это просто картинка. Поэтому список берётся прямо из каталога
# обоев, а не из themes/*.conf.

WALL_DIR="$HOME/.config/hypr/wallpaper"
CUSTOM="$WALL_DIR/custom"
STATE="$HOME/.config/hypr/wallpaper.conf"
# Путь к папке — отдельный файл: switch_theme.sh переписывает wallpaper.conf
# целиком и иначе затирал бы связь при каждой смене картинки.
LIB_FILE="$WALL_DIR/library.path"
SWITCH="$HOME/.config/hypr/scripts/switch_theme.sh"
THUMBS="$(dirname "$0")/thumbs.sh"
THUMB_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/panacea/thumbs"

current() {
    grep -m1 '^\$wallpaper' "$STATE" 2>/dev/null \
        | cut -d= -f2- | sed 's/^ *//; s/ *$//'
}

library_path() {
    [ -f "$LIB_FILE" ] || return 0
    local p
    p=$(head -n1 "$LIB_FILE" 2>/dev/null | sed 's/^ *//; s/ *$//')
    p="${p/#\~/$HOME}"
    [ -n "$p" ] && [ -d "$p" ] && printf '%s\n' "$p"
}

thumb_for() {
    local w="$1" base name thumb_id
    base=${w##*/}
    name=${base%.*}
    case "$w" in
        "$WALL_DIR"/*)
            printf '%s\n' "$THUMB_DIR/$name.jpg"
            ;;
        *)
            # Хэш пути: иначе foo.png из папки и foo.jpg из wallpaper
            # делили бы один файл в кеше.
            thumb_id=$(printf '%s' "$w" | md5sum | awk '{print $1}' | cut -c1-16)
            printf '%s\n' "$THUMB_DIR/lib_${thumb_id}.jpg"
            ;;
    esac
}

emit_wall() {
    local w="$1" base name act own thumb
    base=${w##*/}
    name=${base%.*}
    [ "$w" = "$cur_now" ] && act=yes || act=no
    case "$w" in "$CUSTOM"/*) own=yes ;; *) own=no ;; esac
    thumb=$(thumb_for "$w")
    [ -f "$thumb" ] && [ ! "$w" -nt "$thumb" ] || thumb="$w"
    printf '%s|%s|%s|%s|%s\n' "$name" "$thumb" "$act" "$own" "$w"
}

list_images() {
    local dir="$1" depth="$2"
    [ -d "$dir" ] || return 0
    find "$dir" -maxdepth "$depth" -type f \
         \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' \) \
         | sort | while read -r w; do
        emit_wall "$w"
    done
}

case "$1" in
list)
    # Всё в одном цикле на встроенных командах: обоев сотни, и подпроцессы
    # (basename, thumbs.sh) на каждую превращали список в пять секунд —
    # карусель успевала открыться пустой.
    cur_now=$(current)
    cur_now="${cur_now/#\~/$HOME}"
    export cur_now
    list_images "$WALL_DIR" 2
    lib=$(library_path)
    if [ -n "$lib" ]; then
        # Только корень папки (без подкаталогов) — как в дизайне.
        list_images "$lib" 1
    fi
    ;;

warm)
    # Догоняем миниатюры для новых обоев. Зовётся из карусели после открытия,
    # поэтому первое открытие быстрое, а второе — уже с миниатюрами.
    exec "$THUMBS" all
    ;;

set)
    [ -z "$2" ] && exit 1
    exec "$SWITCH" "$2"
    ;;

add)
    src="$2"
    [ -f "$src" ] || { echo "error" >&2; exit 1; }
    mkdir -p "$CUSTOM"

    # Если такой же файл уже добавлен в свои обои — используем его без дубликатов
    for existing in "$CUSTOM"/*; do
        if [ -f "$existing" ] && cmp -s "$src" "$existing"; then
            "$SWITCH" "$existing" >/dev/null 2>&1
            basename "$existing" | sed 's/\.[^.]*$//'
            exit 0
        fi
    done

    base=$(basename "$src")
    slug=$(printf '%s' "${base%.*}" | tr '[:upper:]' '[:lower:]' | tr ' ' '_' \
           | tr -cd '[:alnum:]_-')
    [ -z "$slug" ] && slug="wall_$(date +%s)"
    ext="${base##*.}"
    dest="$CUSTOM/$slug.$ext"
    # имя занято — не затираем чужую картинку молча
    [ -e "$dest" ] && dest="$CUSTOM/${slug}_$(date +%s).$ext"
    cp -f "$src" "$dest" || exit 1
    "$SWITCH" "$dest" >/dev/null 2>&1
    basename "$dest" | sed 's/\.[^.]*$//'
    ;;

del)
    [ -z "$2" ] && exit 1
    rm -f "$CUSTOM/$2".* 2>/dev/null
    ;;

library)
    case "${2:-}" in
        ""|get)
            library_path
            ;;
        set)
            dir="$3"
            dir="${dir/#\~/$HOME}"
            [ -n "$dir" ] && [ -d "$dir" ] || { echo "error: not a directory" >&2; exit 1; }
            # Канонический путь: иначе ~/foo и /home/... считались бы разными.
            dir=$(readlink -f "$dir" 2>/dev/null || printf '%s' "$dir")
            mkdir -p "$WALL_DIR"
            printf '%s\n' "$dir" > "$LIB_FILE"
            printf '%s\n' "$dir"
            ;;
        clear)
            rm -f "$LIB_FILE"
            ;;
        *)
            echo "usage: themes.sh library [get|set <dir>|clear]" >&2
            exit 1
            ;;
    esac
    ;;

*)
    echo "usage: themes.sh list | set <name> | add <file> | del <name> | library ..." >&2
    exit 1
    ;;
esac
