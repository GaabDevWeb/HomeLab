# Ubuntu / Debian compatibility notes for Panacea

*Note: parts of this write-up were drafted with AI assistance while working through the setup.*

Panacea targets and is tested on Arch Linux. This document collects the adjustments needed to run
it on an Ubuntu/Debian base. The installer (`install.sh`) auto-detects `apt` and installs what it
can; the notes below cover what still differs by release.

---

## Debian 13 (trixie) — recommended apt path

Tested against Debian 13 with Hyprland from **trixie-backports** (e.g. Hyprland 0.55.x).

| Component | Status on Debian 13 |
|---|---|
| Hyprland Lua config | Supported (0.55+ prefers `~/.config/hypr/hyprland.lua`) |
| Qt | System Qt **6.8.x** — enough for Quickshell; **no** `~/Qt` / aqtinstall needed |
| foot | **1.21** in main — use `[colors]` (Debian build has no `[colors-dark]` yet); `cursor.blink-rate` OK |
| fish | **4.x** in main |
| hyprpaper / hyprsunset | **trixie-backports** (installer pulls them with `-t trixie-backports`) |
| Quickshell | Not packaged; build from source **or** use a prebuilt `/usr/local/bin/qs` |
| mpvpaper | Not packaged; installer builds from source when `meson` + `libmpv-dev` are present |
| voxtype | Not in Debian repos — voice-to-text stays optional / manual |
| QML module paths | Multiarch: `/usr/lib/x86_64-linux-gnu/qt6/qml/...` (installer checks both Arch and Debian paths) |

Enable backports if missing:

```bash
# /etc/apt/sources.list — example
deb http://deb.debian.org/debian trixie-backports main non-free-firmware
sudo apt update
```

Then:

```bash
cd Panacea
./install.sh
```

Networking: the installer keeps **NetworkManager** and points Wi‑Fi at the **iwd** backend
(`wifi.backend=iwd`) instead of tearing NM down. That matches typical Debian desktops better than
the older “disable NM entirely” approach below.

Fish abbreviations switch to `apt` automatically when `pacman` is absent (`upd`, `ins`, …).

---

## 1. Quickshell isn't packaged

Ubuntu/Debian don't have Quickshell in their official repos. Building from source is required
unless you already have `qs` / `quickshell` on `PATH` (the installer skips the build in that case).

### Dependencies

```bash
sudo apt install -y \
  cmake ninja-build pkg-config clang \
  qt6-base-dev qt6-declarative-dev qt6-shadertools-dev \
  qt6-wayland-dev libqt6svg6-dev \
  qt6-declarative-private-dev qt6-base-private-dev qt6-wayland-private-dev \
  libdrm-dev libwayland-dev wayland-protocols libwayland-bin \
  libxkbcommon-dev libpipewire-0.3-dev \
  spirv-tools libcli11-dev libjemalloc-dev \
  libpam0g-dev libpolkit-agent-1-dev libglib2.0-dev libgbm-dev
```

The `-private-dev` packages are needed because Debian/Ubuntu split Qt's private headers into
separate packages (official Qt builds include them by default). Without them, the build fails
with `Imported target "Qt::QuickPrivate" includes non-existent path`.

### System Qt: Debian 13 vs older Ubuntu

**Debian 13:** system Qt 6.8 is fine. Build against it (what `install.sh` does).

**Ubuntu 24.04** ships Qt 6.4.2. Quickshell declares Qt 6.6 as the minimum, but in practice some moc
constructs used in the code (`Q_PROPERTY(... READ default ...)`) require a newer version. With
6.4.2 the build fails with `Parse error at "READ"`.

Fix on old Ubuntu: install a newer Qt in a separate directory via
[aqtinstall](https://github.com/miurahr/aqtinstall):

```bash
pip install aqtinstall --break-system-packages
python3 -m aqt install-qt linux desktop 6.7.3 linux_gcc_64 -O ~/Qt -m qtshadertools qtmultimedia
```

### Build (custom Qt — Ubuntu 24.04 path)

```bash
git clone https://github.com/quickshell-mirror/quickshell.git
cd quickshell

cmake -GNinja -B build -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_PREFIX_PATH=$HOME/Qt/6.7.3/gcc_64 \
  -DCMAKE_CXX_COMPILER=clang++ \
  -DCRASH_HANDLER=OFF -DX11=OFF -DI3=OFF -DI3_IPC=OFF \
  -DSERVICE_PAM=ON -DSERVICE_POLKIT=ON -DSCREENCOPY=ON \
  -DNO_PCH=ON \
  -DINSTALL_QMLDIR=$HOME/Qt/6.7.3/gcc_64/qml

cmake --build build
sudo cmake --install build
```

Things to note:
- `CMAKE_PREFIX_PATH` must point to the downloaded Qt, not the system one (Ubuntu 24.04 only).
- `-DNO_PCH=ON` is required with `SERVICE_POLKIT=ON`.
- On low-RAM hardware, limit parallel jobs (`cmake --build build -j2`) and consider adding
  temporary swap.

### Runtime (custom Qt only)

```bash
export LD_LIBRARY_PATH="$HOME/Qt/6.7.3/gcc_64/lib:$LD_LIBRARY_PATH"
export QML2_IMPORT_PATH="$HOME/Qt/6.7.3/gcc_64/qml:$QML2_IMPORT_PATH"
export QT_PLUGIN_PATH="$HOME/Qt/6.7.3/gcc_64/plugins:$QT_PLUGIN_PATH"
```

On Hyprland, set these as session env (`hl.env` / `env =`) rather than in a global shell rc so
other system Qt apps do not pick up the private tree.

---

## 2. foot on older Ubuntu

Panacea's theme uses `[colors-dark]` and `cursor.blink-rate`. Ubuntu 24.04's foot 1.16.2 is too
old; Debian 13's 1.21 is fine from the repos.

Build from source only if your distro foot is &lt; ~1.18:

```bash
sudo apt install -y meson ninja-build scdoc \
  libwayland-dev wayland-protocols \
  libxkbcommon-dev libfontconfig1-dev libfreetype-dev \
  libpixman-1-dev libutf8proc-dev

git clone --recursive https://codeberg.org/dnkl/foot.git
cd foot
meson setup build --buildtype=release -Db_lto=true
ninja -C build
sudo ninja -C build install
```

---

## 3. Packages with no direct equivalent

| Arch/AUR package | Ubuntu/Debian alternative |
|---|---|
| `bat` | package is called `bat`, but the binary may be `batcat` — installer links `~/.local/bin/bat` |
| `yazi` | binary release via installer (`ensure_yazi`) or `cargo install --force yazi-build` |
| `mpvpaper` | built from source by the installer (`ensure_mpvpaper`) |
| `voxtype` / `voxtype-bin` | not packaged — install manually if you want Right-Alt dictation |
| `bibata-cursor-theme-bin` | installer downloads Bibata into `~/.local/share/icons` |

---

## 4. NetworkManager / iwd

Panacea's Wi-Fi script talks to `iwd` via `iwctl`. On Debian/Ubuntu, NetworkManager usually owns
Wi-Fi. The installer configures:

```ini
# /etc/NetworkManager/conf.d/wifi_backend.conf
[device]
wifi.backend=iwd
```

If you still see auth/DHCP races, the older hard cutover (disable NM, iwd + systemd-networkd) is
documented historically below — use only if the backend switch is not enough.

```bash
sudo systemctl stop wpa_supplicant
sudo systemctl disable wpa_supplicant
sudo systemctl disable --now NetworkManager

sudo mkdir -p /etc/iwd
printf '[General]\nEnableNetworkConfiguration=true\n' | sudo tee /etc/iwd/main.conf
sudo systemctl restart iwd

sudo mkdir -p /etc/systemd/network
printf '[Match]\nName=en*\n\n[Network]\nDHCP=yes\n' | sudo tee /etc/systemd/network/20-wired.network
sudo systemctl enable --now systemd-networkd
sudo systemctl enable --now systemd-resolved
```

---

## 5. `install.sh` behavior on Debian/Ubuntu

- Detects `apt`, skips AUR helper prompts.
- Installs Hyprland-related packages from **trixie-backports** when that suite exists.
- Builds Quickshell only if `qs`/`quickshell` is missing; on Debian 13 uses system Qt.
- Builds mpvpaper from source when missing.
- `--print-obsolete` is Arch-only (exits cleanly without pacman).
- GRUB/SDDM themes are optional prompts; safe to decline.

---

## Possibly distro-independent bug

`hypr/lua/programs.lua` and some binds historically contained `/home/ensi/...`.
`personalize_paths()` in `install.sh` rewrites those to `$HOME` after copy. After install, verify:

```bash
grep -rn "/home/ensi" ~/.config/hypr ~/.config/panacea || echo "ok"
```
