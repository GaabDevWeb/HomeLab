#!/bin/bash
# Смена обоев — и только обоев.
#
#   switch_theme.sh --restore     вернуть последние обои (автозапуск)
#   switch_theme.sh <имя>         обои из ~/.config/hypr/wallpaper (без .jpg)
#   switch_theme.sh <путь>        любой файл
#
# Без аргументов ничего не спрашивает: выбор обоев живёт в самой пилюле
# (Super + Shift + T), и держать ради того же самого второе меню на tofi
# значило бы держать и tofi.
#
# Цвета здесь не участвуют: палитра одна и лежит в palette.conf, её
# раскладывает palette.sh. Так смена картинки больше не перекрашивает
# терминалы и не трогает ни один файл, который читает сам Hyprland, —
# раньше из-за этого рабочие столы перетряхивались на каждой теме.

WALL_DIR="$HOME/.config/hypr/wallpaper"
# Отдельный файл, а не theme.conf: его никто не подключает через source,
# поэтому Hyprland при смене обоев остаётся в покое.
STATE="$HOME/.config/hypr/wallpaper.conf"

# Путь к обоям: либо готовый файл, либо имя без расширения. Ищем по всему
# каталогу обоев, а не только в его корне: скачанные наборы лежат в
# подкаталогах (shell, custom), и раньше выбор такой картинки молча
# заканчивался ничем.
resolve() {
    local n="$1"
    n="${n/#\~/$HOME}"
    if [ -f "$n" ]; then printf '%s\n' "$n"; return 0; fi
    find "$WALL_DIR" -maxdepth 2 -type f \
         \( -iname "$n.jpg" -o -iname "$n.jpeg" -o -iname "$n.png" -o -iname "$n.webp" \) \
         -print -quit 2>/dev/null | grep . && return 0
    return 1
}

current() {
    grep -m1 '^\$wallpaper' "$STATE" 2>/dev/null \
        | cut -d= -f2- | sed 's/^ *//; s/ *$//'
}

if [ "$1" = "--restore" ]; then
    # последними стояли живые обои — отдаём их своему скрипту и выходим
    LIVE=$(grep -m1 '^\$live' "$STATE" 2>/dev/null | cut -d= -f2- | sed 's/^ *//; s/ *$//')
    LIVE="${LIVE/#\~/$HOME}"
    if [ -n "$LIVE" ] && [ -f "$LIVE" ]; then
        exec "$(dirname "$0")/live_wallpaper.sh" set "$LIVE"
    fi
    WALL=$(current)
    [ -n "$WALL" ] || WALL=$(ls "$WALL_DIR"/*.jpg "$WALL_DIR"/*.png 2>/dev/null | head -1)
elif [ -n "$1" ]; then
    WALL=$(resolve "$1")
else
    echo "usage: switch_theme.sh --restore | <имя> | <путь>" >&2
    exit 1
fi

WALL="${WALL/#\~/$HOME}"
[ -n "$WALL" ] && [ -f "$WALL" ] || { echo "не нашёл обои: $1" >&2; exit 1; }

# Живые обои и статичные — один и тот же фон, поэтому включение картинки
# выключает видео. Иначе mpvpaper остался бы крутиться под ней.
if grep -q '^\$live' "$STATE" 2>/dev/null || pgrep -x mpvpaper >/dev/null 2>&1; then
    pkill -x mpvpaper >/dev/null 2>&1
fi

# запоминаем выбор: отсюда его читают пилюля, экран блокировки и автозапуск
mkdir -p "$(dirname "$STATE")"
{
    printf '# Файл создаётся автоматически при смене обоев.\n'
    printf '# Hyprland его не подключает: смена картинки не должна трогать конфиг.\n'
    printf '$wallpaper = %s\n' "$WALL"
} > "$STATE"

# ------------------------------------------------------------- hyprpaper
# В 0.8 у hyprpaper сменился формат конфига: вместо пары preload/wallpaper
# теперь блок wallpaper { monitor, path, fit_mode }.
#
# Коварство в том, что на старый формат он не ругается — он его просто не
# видит: «Monitor eDP-1 has no target, no wp will be created». Картинка при
# этом ставилась, но только через IPC, то есть пока сидишь в системе. После
# перезагрузки hyprpaper поднимался с пустым конфигом, и стол оставался
# чёрным, пока обои не выберешь заново.
#
# Пустой monitor в новом формате означает «все экраны» — это заодно снимает
# зависимость от списка мониторов на момент записи: подключённый позже
# экран получит те же обои.
hyprpaper_new_format() {
    local v maj min
    v=$(hyprpaper --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
    [ -n "$v" ] || return 1
    maj=${v%%.*}
    min=$(printf '%s' "$v" | cut -d. -f2)
    [ "$maj" -gt 0 ] || [ "$min" -ge 8 ]
}

{
    if hyprpaper_new_format; then
        printf 'wallpaper {\n'
        printf '    monitor =\n'
        printf '    path = %s\n' "$WALL"
        printf '    fit_mode = cover\n'
        printf '}\n'
    else
        printf 'preload = %s\n' "$WALL"
        # одна строка на каждый монитор: ",path" на этой версии не работает
        hyprctl monitors -j | jq -r '.[].name' | while read -r M; do
            printf 'wallpaper = %s,%s\n' "$M" "$WALL"
        done
    fi
    printf 'splash = false\nipc = on\n'
} > "$HOME/.config/hypr/hyprpaper.conf"

# hyprpaper 0.8: preload IPC foi removido; hyprctl sem daemon trava a 100% CPU.
# Estratégia fiável: reescrever conf + reiniciar o daemon (lê o bloco wallpaper).
# Fallback IPC com timeout curto se o restart falhar.
apply_hyprpaper() {
    # Não usar `pkill -f 'hyprctl hyprpaper'`: mata shells cujo cmdline contém
    # essa string (ex. wrappers/CI). Só processos hyprctl de verdade.
    local pid cmd
    for pid in $(pgrep -x hyprctl 2>/dev/null || true); do
        cmd=$(tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null || true)
        case "$cmd" in
            *hyprpaper*) kill "$pid" 2>/dev/null || true ;;
        esac
    done
    pkill -x hyprpaper >/dev/null 2>&1 || true
    sleep 0.2
    setsid hyprpaper >/dev/null 2>&1 &
    sleep 0.45
    if pgrep -x hyprpaper >/dev/null 2>&1; then
        return 0
    fi
    # fallback: IPC (man: wallpaper 'mon, path[, fit_mode]')
    local m
    while read -r m; do
        [ -n "$m" ] || continue
        timeout 2 hyprctl hyprpaper wallpaper "${m},${WALL},cover" >/dev/null 2>&1 || true
    done < <(hyprctl monitors -j 2>/dev/null | jq -r '.[].name')
}

apply_hyprpaper

# --------------------------------------------------------- фон экрана входа
# Greeter работает от пользователя sddm и в ~/ заглянуть не может: домашний
# каталог закрыт. Кладём готовую размытую копию в общий каталог, который
# создал install.sh. Размываем заранее: QML-блюр на greeter'е стоит кадров.
#
# Em background: ffmpeg não pode bloquear a troca de wallpaper (senão o
# Overlay/fade do Panacea fica preso e as janelas “somem”).
SDDM_DIR=/var/lib/panacea
if [ -d "$SDDM_DIR" ] && [ -w "$SDDM_DIR" ] && command -v ffmpeg >/dev/null; then
    (
        ffmpeg -y -loglevel error -i "$WALL" \
            -vf "scale=1280:-1,gblur=sigma=28,eq=saturation=0.9" \
            -frames:v 1 "$SDDM_DIR/sddm-bg.jpg" 2>/dev/null \
            && chmod 644 "$SDDM_DIR/sddm-bg.jpg"
    ) >/dev/null 2>&1 &
fi
