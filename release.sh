#!/usr/bin/env bash
# Stellar Download Manager - Linux .deb release script
# Usage: ./release.sh [--version 0.2.0] [--skip-build] [--skip-deb]
#
# Prerequisites:
#   cmake, ninja, dpkg-deb, gzip, sha256sum, ldd
#   Qt 6 Linux development packages
#   yt-dlp and ffmpeg available on PATH for packaging, or set YTDLP_PATH / FFMPEG_PATH
#
# Output:
#   dist/linux/stellar_<version>_amd64.deb
#   dist/linux/stellar_<version>_amd64.deb.sha256

set -euo pipefail

VERSION=""
SKIP_BUILD=0
SKIP_DEB=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --version)    VERSION="$2"; shift 2 ;;
        --skip-build) SKIP_BUILD=1; shift ;;
        --skip-deb)   SKIP_DEB=1; shift ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

ROOT="$(cd "$(dirname "$0")" && pwd)"
TODAY_UTC="$(date -u +%Y-%m-%d)"
ARCH="amd64"
PKG_NAME="stellar"
APP_NAME="Stellar"
APP_ID="io.github.stellar.Stellar"
DEB_DIR="$ROOT/build/linux-deb"
DEB_ROOT="$DEB_DIR/root"
DEB_DATA="$DEB_DIR/data"
DIST_DIR="$ROOT/dist/linux"
RELEASES_DIR="$ROOT/releases"

log()  { echo -e "\033[0;36m[release]\033[0m $*"; }
ok()   { echo -e "\033[0;32m[release]\033[0m $*"; }
warn() { echo -e "\033[0;33m[release]\033[0m $*"; }

if [[ -z "$VERSION" ]]; then
    VERSION=$(grep -oP 'project\s*\(\s*\w+\s+VERSION\s+\K[\d]+\.[\d]+\.[\d]+(?:\.[\d]+)?' "$ROOT/CMakeLists.txt" | head -1)
    if [[ -z "$VERSION" ]]; then
        echo "ERROR: Could not detect version from CMakeLists.txt. Pass --version explicitly." >&2
        exit 1
    fi
    log "Detected version: $VERSION"
fi

DEB_FILE="$DIST_DIR/${PKG_NAME}_${VERSION}_${ARCH}.deb"
DEB_SHA256="$DEB_FILE.sha256"

need_tool() {
    command -v "$1" >/dev/null 2>&1 || { echo "ERROR: '$1' not found on PATH" >&2; exit 1; }
}

need_tool cmake
need_tool sha256sum
need_tool dpkg-deb
need_tool ldd

resolve_binary() {
    local env_name="$1"
    local tool_name="$2"
    local value="${!env_name:-}"
    if [[ -n "$value" && -x "$value" ]]; then
        printf '%s\n' "$value"
        return
    fi
    if command -v "$tool_name" >/dev/null 2>&1; then
        command -v "$tool_name"
        return
    fi
    echo "ERROR: '$tool_name' not found. Set $env_name to an executable path or install it." >&2
    exit 1
}

copy_shared_object() {
    local src="$1"
    local dst_dir="$2"
    [[ -f "$src" ]] || return 0
    cp -L "$src" "$dst_dir/"
}

resolve_shared_library() {
    local soname="$1"
    local found=""
    if command -v ldconfig >/dev/null 2>&1; then
        found="$(ldconfig -p 2>/dev/null | awk -v n="$soname" '$1==n {print $NF; exit}')"
        if [[ -n "$found" && -f "$found" ]]; then
            printf '%s\n' "$found"
            return 0
        fi
    fi
    for d in /lib /lib64 /usr/lib /usr/lib64 /usr/lib/x86_64-linux-gnu /lib/x86_64-linux-gnu; do
        if [[ -f "$d/$soname" ]]; then
            printf '%s\n' "$d/$soname"
            return 0
        fi
    done
    return 1
}

qt_install_prefix() {
    if command -v qmake6 >/dev/null 2>&1; then
        qmake6 -query QT_INSTALL_PREFIX
        return
    fi
    if command -v qmake >/dev/null 2>&1; then
        qmake -query QT_INSTALL_PREFIX
        return
    fi
    local qtcore
    qtcore="$(ldd "$ROOT/build/linux-release/Stellar" | awk '/libQt6Core/ {print $3; exit}')"
    if [[ -n "$qtcore" ]]; then
        dirname "$(dirname "$qtcore")"
        return
    fi
    echo "ERROR: Could not determine Qt install prefix." >&2
    exit 1
}

bundle_qt_runtime() {
    local app_dir="$DEB_ROOT/opt/stellar"
    local lib_dir="$app_dir/lib"
    local plugin_dir="$app_dir/plugins"
    local qml_dir="$app_dir/qml"
    local qt_prefix qt_plugins qt_qml

    qt_prefix="$(qt_install_prefix)"
    qt_plugins="$qt_prefix/plugins"
    qt_qml="$qt_prefix/qml"

    mkdir -p "$lib_dir" "$plugin_dir" "$qml_dir"
    log "Bundling Qt runtime from: $qt_prefix"

    while read -r so; do
        [[ -n "$so" ]] || continue
        copy_shared_object "$so" "$lib_dir"
    done < <(ldd "$app_dir/Stellar" \
        | awk '/=> \// {print $3}' \
        | grep -E 'libQt6|libicu|libdouble-conversion|libpcre2-16' || true)

    for sub in platforms platformthemes imageformats iconengines styles tls xcbglintegrations wayland-decoration-client wayland-graphics-integration-client wayland-shell-integration; do
        if [[ -d "$qt_plugins/$sub" ]]; then
            mkdir -p "$plugin_dir/$sub"
            cp -a "$qt_plugins/$sub/." "$plugin_dir/$sub/"
        fi
    done

    # Copy transitive native deps required by Qt platform plugins (not just Qt libs).
    # This is what prevents "could not load xcb plugin" on mixed Debian/Ubuntu variants.
    if [[ -d "$plugin_dir/platforms" ]]; then
        while read -r dep; do
            [[ -n "$dep" ]] || continue
            copy_shared_object "$dep" "$lib_dir"
        done < <(
            find "$plugin_dir/platforms" "$plugin_dir/xcbglintegrations" -type f -name '*.so' 2>/dev/null \
                | while read -r plugin_so; do
                    ldd "$plugin_so" \
                        | awk '/=> \// {print $3}'
                  done \
                | sort -u \
                | grep -E '/lib(xcb|xkbcommon|X11|Xext|Xrender|Xi|SM|ICE|fontconfig|freetype|glib|dbus|EGL|GL|drm|wayland|xshmfence|xcb-cursor|xcb-util|xcb-render-util|xcb-image|xcb-icccm|xcb-keysyms|xcb-xinerama)' \
                || true
        )
    fi

    # Hard-pin critical xcb chain required by Qt's xcb platform plugin on Debian/Ubuntu.
    local xcb_sonames=(
        "libxcb-cursor.so.0"
        "libxcb.so.1"
        "libxcb-render.so.0"
        "libxcb-render-util.so.0"
        "libxcb-image.so.0"
        "libxcb-icccm.so.4"
        "libxcb-keysyms.so.1"
        "libxcb-xinerama.so.0"
        "libxcb-xkb.so.1"
        "libxkbcommon.so.0"
        "libxkbcommon-x11.so.0"
        "libX11.so.6"
        "libX11-xcb.so.1"
        "libXrender.so.1"
        "libXext.so.6"
        "libXi.so.6"
        "libxshmfence.so.1"
    )
    local so resolved
    for so in "${xcb_sonames[@]}"; do
        if resolved="$(resolve_shared_library "$so")"; then
            copy_shared_object "$resolved" "$lib_dir"
        fi
    done

    for mod in QtQml QtQuick QtQuick.2 QtQuick.Controls QtQuick.Controls.Material QtQuick.Dialogs QtQuick.Layouts QtQuick.Shapes Qt5Compat; do
        if [[ -d "$qt_qml/$mod" ]]; then
            mkdir -p "$qml_dir/$mod"
            cp -a "$qt_qml/$mod/." "$qml_dir/$mod/"
        fi
    done

    cat > "$app_dir/qt.conf" <<'EOF'
[Paths]
Prefix=.
Libraries=lib
Plugins=plugins
QmlImports=qml
EOF
}

update_deb_manifest() {
    mkdir -p "$DEB_DIR"
    cat > "$DEB_DIR/control" <<EOF
Package: stellar
Version: $VERSION
Section: utils
Priority: optional
Architecture: $ARCH
Maintainer: Ninka_
Installed-Size: 1
Depends: libc6, libstdc++6, libgcc-s1, zlib1g, libx11-6, libxcb1, libxkbcommon0, libxcb-cursor0, libxkbcommon-x11-0, libxcb-icccm4, libxcb-image0, libxcb-keysyms1, libxcb-render-util0, libxcb-xinerama0
Homepage: https://stellar.moe/
Description: Stellar Download Manager
 Fast, segmented, IDM-style download manager.
EOF

    cat > "$DEB_DIR/postinst" <<'EOF'
#!/bin/sh
set -e
if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database /usr/share/applications >/dev/null 2>&1 || true
fi
if command -v update-mime-database >/dev/null 2>&1; then
    update-mime-database /usr/share/mime >/dev/null 2>&1 || true
fi
exit 0
EOF
    chmod 0755 "$DEB_DIR/postinst"
}

build_app() {
    log "Configuring (linux-release)..."
    cmake --preset linux-release -S "$ROOT"
    log "Building..."
    cmake --build --preset linux-release
    ok "CMake build complete."
}

stage_deb() {
    local ytdlp_path ffmpeg_path
    ytdlp_path="$(resolve_binary YTDLP_PATH yt-dlp)"
    ffmpeg_path="$(resolve_binary FFMPEG_PATH ffmpeg)"

    log "Staging .deb filesystem..."
    rm -rf "$DEB_ROOT"
    mkdir -p \
        "$DEB_ROOT/opt/stellar" \
        "$DEB_ROOT/usr/bin" \
        "$DEB_ROOT/usr/share/applications" \
        "$DEB_ROOT/usr/share/icons/hicolor/256x256/apps" \
        "$DEB_ROOT/usr/share/icons/hicolor/128x128/apps" \
        "$DEB_ROOT/usr/lib/mozilla/native-messaging-hosts" \
        "$DEB_ROOT/usr/share/metainfo" \
        "$DEB_ROOT/DEBIAN"

    cp "$ROOT/build/linux-release/Stellar" "$DEB_ROOT/opt/stellar/Stellar"
    cp "$ytdlp_path" "$DEB_ROOT/opt/stellar/yt-dlp"
    cp "$ffmpeg_path" "$DEB_ROOT/opt/stellar/ffmpeg"
    cp "$ROOT/app/data/dbip-city-lite-2026-04.mmdb" "$DEB_ROOT/opt/stellar/dbip-city-lite-2026-04.mmdb"
    cp "$ROOT/tips.txt" "$DEB_ROOT/opt/stellar/tips.txt"
    cp -R "$ROOT/extensions" "$DEB_ROOT/opt/stellar/extensions"
    cp "$ROOT/packaging/linux/com.stellar.downloadmanager.json" \
        "$DEB_ROOT/usr/lib/mozilla/native-messaging-hosts/com.stellar.downloadmanager.json"
    cp "$ROOT/packaging/flatpak/io.github.stellar.Stellar.desktop" \
        "$DEB_ROOT/usr/share/applications/io.github.stellar.Stellar.desktop"
    cp "$ROOT/packaging/flatpak/io.github.stellar.Stellar.metainfo.xml" \
        "$DEB_ROOT/usr/share/metainfo/io.github.stellar.Stellar.metainfo.xml"
    cp "$ROOT/app/qml/icons/milky-way.png" \
        "$DEB_ROOT/usr/share/icons/hicolor/256x256/apps/io.github.stellar.Stellar.png"
    cp "$ROOT/app/qml/icons/milky-way.png" \
        "$DEB_ROOT/usr/share/icons/hicolor/128x128/apps/io.github.stellar.Stellar.png"

    cat > "$DEB_ROOT/usr/bin/stellar" <<'EOF'
#!/bin/sh
set -e
APPDIR="/opt/stellar"
export LD_LIBRARY_PATH="$APPDIR/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export QT_PLUGIN_PATH="$APPDIR/plugins"
export QT_QPA_PLATFORM_PLUGIN_PATH="$APPDIR/plugins/platforms"
export QML2_IMPORT_PATH="$APPDIR/qml"
exec "$APPDIR/Stellar" "$@"
EOF
    chmod 0755 "$DEB_ROOT/usr/bin/stellar"

    python3 - "$DEB_ROOT/usr/lib/mozilla/native-messaging-hosts/com.stellar.downloadmanager.json" <<'PY'
import json, sys
from pathlib import Path

path = Path(sys.argv[1])
data = json.loads(path.read_text(encoding="utf-8"))
data["path"] = "/usr/bin/stellar"
path.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
PY

    sed -i "s|^Exec=.*|Exec=/usr/bin/stellar|; s|^Icon=.*|Icon=io.github.stellar.Stellar|" \
        "$DEB_ROOT/usr/share/applications/io.github.stellar.Stellar.desktop"

    bundle_qt_runtime

    install -m 0755 "$DEB_DIR/postinst" "$DEB_ROOT/DEBIAN/postinst"
    install -m 0644 "$DEB_DIR/control" "$DEB_ROOT/DEBIAN/control"
}

build_deb() {
    update_deb_manifest
    stage_deb
    mkdir -p "$DIST_DIR"
    log "Building .deb..."
    dpkg-deb --root-owner-group --build "$DEB_ROOT" "$DEB_FILE"
    sha256sum "$DEB_FILE" > "$DEB_SHA256"
    ok "Debian package: $DEB_FILE"
}

if [[ $SKIP_BUILD -eq 0 ]]; then
    build_app
else
    warn "Skipping CMake build."
fi

if [[ $SKIP_DEB -eq 0 ]]; then
    build_deb
else
    warn "Skipping .deb build."
fi

ok "=== Linux release $VERSION complete ==="
echo "  deb      : $DEB_FILE"
echo "  sha256   : $DEB_SHA256"
