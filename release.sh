#!/usr/bin/env bash
# Stellar Download Manager - Linux release script
# Usage: ./release.sh [--version 0.2.0] [--skip-build] [--skip-deb] [--skip-rpm]
#
# Prerequisites:
#   cmake, ninja, dpkg-deb, rpmbuild, gzip, sha256sum, ldd, readelf, patchelf
#   Qt 6 Linux development packages
#   yt-dlp, ffmpeg, and ffprobe available on PATH for packaging, or set YTDLP_PATH / FFMPEG_PATH / FFPROBE_PATH
#
# Output:
#   dist/linux/stellar_<version>_amd64.deb
#   dist/linux/stellar_<version>_amd64.deb.sha256
#   dist/linux/stellar-<version>-1.x86_64.rpm
#   dist/linux/stellar-<version>-1.x86_64.rpm.sha256

set -euo pipefail

VERSION=""
SKIP_BUILD=0
SKIP_DEB=0
SKIP_RPM=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --version)    VERSION="$2"; shift 2 ;;
        --skip-build) SKIP_BUILD=1; shift ;;
        --skip-deb)   SKIP_DEB=1; shift ;;
        --skip-rpm)   SKIP_RPM=1; shift ;;
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
RPM_DIR="$ROOT/build/linux-rpm"
DIST_DIR="$ROOT/dist/linux"

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
RPM_FILE="$DIST_DIR/${PKG_NAME}-${VERSION}-1.x86_64.rpm"
RPM_SHA256="$RPM_FILE.sha256"

need_tool() {
    command -v "$1" >/dev/null 2>&1 || { echo "ERROR: '$1' not found on PATH" >&2; exit 1; }
}

need_tool cmake
need_tool sha256sum
need_tool ldd
need_tool readelf

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
    [[ -e "$src" ]] || return 0
    mkdir -p "$dst_dir"

    local resolved base soname dest
    resolved="$(readlink -f "$src")"
    base="$(basename "$resolved")"
    dest="$dst_dir/$base"

    if [[ -e "$dest" ]]; then
        local dest_resolved
        dest_resolved="$(readlink -f "$dest")"
        if [[ "$dest_resolved" == "$resolved" ]]; then
            if [[ -L "$src" ]]; then
                ln -sf "$base" "$dst_dir/$(basename "$src")"
            fi
            soname="$(readelf -d "$resolved" 2>/dev/null | awk -F'[][]' '/SONAME/ {print $2; exit}')"
            if [[ -n "$soname" ]]; then
                ln -sf "$base" "$dst_dir/$soname"
            fi
            return 0
        fi
    fi

    cp -L "$resolved" "$dest"

    if [[ -L "$src" ]]; then
        ln -sf "$base" "$dst_dir/$(basename "$src")"
    fi

    soname="$(readelf -d "$resolved" 2>/dev/null | awk -F'[][]' '/SONAME/ {print $2; exit}')"
    if [[ -n "$soname" ]]; then
        ln -sf "$base" "$dst_dir/$soname"
    fi
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

collect_binary_dependencies_recursive() {
    local dst_dir="$1"
    shift

    local queue=("$@")
    local seen=""

    while [[ ${#queue[@]} -gt 0 ]]; do
        local target="${queue[0]}"
        queue=("${queue[@]:1}")
        [[ -e "$target" ]] || continue

        while read -r dep; do
            [[ -n "$dep" ]] || continue
            if grep -Fqx "$dep" <<<"$seen"; then
                continue
            fi
            seen="${seen}${dep}"$'\n'
            copy_shared_object "$dep" "$dst_dir"
            queue+=("$dep")
        done < <(ldd "$target" 2>/dev/null | awk '/=> \// {print $3}' || true)
    done
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

qt_install_plugins() {
    if command -v qmake6 >/dev/null 2>&1; then
        qmake6 -query QT_INSTALL_PLUGINS
        return
    fi
    if command -v qmake >/dev/null 2>&1; then
        qmake -query QT_INSTALL_PLUGINS
        return
    fi
    for d in \
        /usr/lib/x86_64-linux-gnu/qt6/plugins \
        /usr/lib/qt6/plugins \
        /usr/lib64/qt6/plugins \
        "$(qt_install_prefix)/plugins"; do
        if [[ -d "$d/platforms" ]]; then
            printf '%s\n' "$d"
            return
        fi
    done
    echo "ERROR: Could not determine Qt plugin directory." >&2
    exit 1
}

qt_install_qml() {
    if command -v qmake6 >/dev/null 2>&1; then
        qmake6 -query QT_INSTALL_QML
        return
    fi
    if command -v qmake >/dev/null 2>&1; then
        qmake -query QT_INSTALL_QML
        return
    fi
    for d in \
        /usr/lib/x86_64-linux-gnu/qt6/qml \
        /usr/lib/qt6/qml \
        /usr/lib64/qt6/qml \
        "$(qt_install_prefix)/qml"; do
        if [[ -d "$d" ]]; then
            printf '%s\n' "$d"
            return
        fi
    done
    echo "ERROR: Could not determine Qt QML directory." >&2
    exit 1
}

bundle_qt_runtime() {
    local app_dir="$1"
    local lib_dir="$app_dir/lib"
    local plugin_dir="$app_dir/plugins"
    local qml_dir="$app_dir/qml"
    local qt_prefix qt_plugins qt_qml qt_lib

    qt_prefix="$(qt_install_prefix)"
    qt_plugins="$(qt_install_plugins)"
    qt_qml="$(qt_install_qml)"
    qt_lib="$(dirname "$qt_plugins")/../../lib/x86_64-linux-gnu"
    [[ -d "$qt_lib" ]] || qt_lib="$qt_prefix/lib"

    mkdir -p "$lib_dir" "$plugin_dir" "$qml_dir"
    log "Bundling Qt runtime from: $qt_prefix"

    while read -r qt_so; do
        [[ -n "$qt_so" ]] || continue
        copy_shared_object "$qt_so" "$lib_dir"
    done < <(find "$qt_lib" -maxdepth 1 -type f \( -name 'libQt6*.so.*' -o -name 'libicu*.so.*' -o -name 'libdouble-conversion.so.*' -o -name 'libpcre2-16.so.*' \) 2>/dev/null || true)

    for sub in platforms platformthemes imageformats iconengines styles tls xcbglintegrations wayland-decoration-client wayland-graphics-integration-client wayland-shell-integration; do
        if [[ -d "$qt_plugins/$sub" ]]; then
            mkdir -p "$plugin_dir/$sub"
            cp -a "$qt_plugins/$sub/." "$plugin_dir/$sub/"
        fi
    done

    local dep_roots=("$app_dir/Stellar")
    while read -r sofile; do
        [[ -n "$sofile" ]] || continue
        dep_roots+=("$sofile")
    done < <(find "$plugin_dir" "$qml_dir" -type f -name '*.so' 2>/dev/null || true)
    collect_binary_dependencies_recursive "$lib_dir" "${dep_roots[@]}"

    local xcb_sonames=(
        "libxcb-cursor.so.0"
        "libxcb-util.so.1"
        "libxcb-util.so.0"
        "libxcb.so.1"
        "libxcb-render.so.0"
        "libxcb-render-util.so.0"
        "libxcb-image.so.0"
        "libxcb-icccm.so.4"
        "libxcb-keysyms.so.1"
        "libxcb-xinerama.so.0"
        "libxcb-xkb.so.1"
        "libxcb-randr.so.0"
        "libxcb-shape.so.0"
        "libxcb-shm.so.0"
        "libxcb-sync.so.1"
        "libxkbcommon.so.0"
        "libxkbcommon-x11.so.0"
        "libX11.so.6"
        "libX11-xcb.so.1"
        "libXrender.so.1"
        "libXext.so.6"
        "libXi.so.6"
        "libxshmfence.so.1"
        "libGL.so.1"
        "libGLX.so.0"
        "libGLdispatch.so.0"
    )
    local so resolved
    for so in "${xcb_sonames[@]}"; do
        if resolved="$(resolve_shared_library "$so")"; then
            copy_shared_object "$resolved" "$lib_dir"
        fi
    done

    if [[ ! -e "$lib_dir/libxcb-cursor.so.0" ]]; then
        warn "libxcb-cursor.so.0 not found — install libxcb-cursor0 on the build machine (required by Qt xcb platform plugin)."
    fi

    if [[ ! -e "$plugin_dir/platforms/libqxcb.so" ]]; then
        echo "ERROR: Qt xcb platform plugin (libqxcb.so) not found in $qt_plugins/platforms." >&2
        echo "       Install qt6-base-dev or libqt6gui6 on the build machine." >&2
        exit 1
    fi

    for mod in QtCore QtQml QtQuick QtQuick.2 QtQuick.Controls QtQuick.Controls.Material QtQuick.Dialogs QtQuick.Layouts QtQuick.Shapes Qt5Compat; do
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

patch_bundled_rpaths() {
    local app_dir="$1"

    if ! command -v patchelf >/dev/null 2>&1; then
        warn "patchelf not found; skipping RPATH patching."
        return
    fi

    patchelf --set-rpath '$ORIGIN/lib' "$app_dir/Stellar"

    while read -r sofile; do
        [[ -n "$sofile" ]] || continue
        patchelf --set-rpath '$ORIGIN/../../lib:$ORIGIN/../../../lib:$ORIGIN/../../../../lib' "$sofile" || true
    done < <(find "$app_dir/plugins" -type f -name '*.so' 2>/dev/null || true)

    while read -r sofile; do
        [[ -n "$sofile" ]] || continue
        patchelf --set-rpath '$ORIGIN:$ORIGIN/../lib:$ORIGIN/../../lib:$ORIGIN/../../../lib:$ORIGIN/../../../../lib' "$sofile" || true
    done < <(find "$app_dir/qml" -type f -name '*.so' 2>/dev/null || true)
}

# Writes the launcher script to $1 (path) for install root $2 (e.g. /opt/stellar).
write_launcher() {
    local dest="$1"
    local appdir="$2"
    cat > "$dest" <<EOF
#!/bin/sh
set -e
APPDIR="$appdir"
export LD_LIBRARY_PATH="\$APPDIR/lib\${LD_LIBRARY_PATH:+:\$LD_LIBRARY_PATH}"
export QT_PLUGIN_PATH="\$APPDIR/plugins"
export QT_QPA_PLATFORM_PLUGIN_PATH="\$APPDIR/plugins/platforms"
export QML2_IMPORT_PATH="\$APPDIR/qml"
export QT_QML_IMPORT_PATH="\$APPDIR/qml"
if [ -n "\$WAYLAND_DISPLAY" ] && [ -f "\$APPDIR/plugins/platforms/libqwayland-generic.so" ]; then
    export QT_QPA_PLATFORM="\${QT_QPA_PLATFORM:-wayland;xcb}"
else
    export QT_QPA_PLATFORM="\${QT_QPA_PLATFORM:-xcb}"
fi
exec "\$APPDIR/Stellar" "\$@"
EOF
    chmod 0755 "$dest"
}

# Populate /opt/stellar subtree under $1 (the package root).
stage_app() {
    local pkg_root="$1"
    local app_dir="$pkg_root/opt/stellar"
    local ytdlp_path ffmpeg_path ffprobe_path

    ytdlp_path="$(resolve_binary YTDLP_PATH yt-dlp)"
    ffmpeg_path="$(resolve_binary FFMPEG_PATH ffmpeg)"
    ffprobe_path="$(resolve_binary FFPROBE_PATH ffprobe)"

    mkdir -p \
        "$app_dir" \
        "$pkg_root/usr/bin" \
        "$pkg_root/usr/share/applications" \
        "$pkg_root/usr/share/icons/hicolor/256x256/apps" \
        "$pkg_root/usr/share/icons/hicolor/128x128/apps" \
        "$pkg_root/usr/lib/mozilla/native-messaging-hosts" \
        "$pkg_root/usr/share/metainfo"

    cp "$ROOT/build/linux-release/Stellar"                     "$app_dir/Stellar"
    cp "$ytdlp_path"                                           "$app_dir/yt-dlp"
    cp "$ffmpeg_path"                                          "$app_dir/ffmpeg"
    cp "$ffprobe_path"                                         "$app_dir/ffprobe"
    cp "$ROOT/app/data/dbip-city-lite-2026-04.mmdb"           "$app_dir/dbip-city-lite-2026-04.mmdb"
    cp "$ROOT/tips.txt"                                        "$app_dir/tips.txt"
    cp -R "$ROOT/extensions"                                   "$app_dir/extensions"

    cp "$ROOT/packaging/linux/com.stellar.downloadmanager.json" \
        "$pkg_root/usr/lib/mozilla/native-messaging-hosts/com.stellar.downloadmanager.json"
    cp "$ROOT/packaging/linux/io.github.stellar.Stellar.desktop" \
        "$pkg_root/usr/share/applications/io.github.stellar.Stellar.desktop"
    cp "$ROOT/packaging/linux/io.github.stellar.Stellar.metainfo.xml" \
        "$pkg_root/usr/share/metainfo/io.github.stellar.Stellar.metainfo.xml"
    cp "$ROOT/app/qml/icons/milky-way.png" \
        "$pkg_root/usr/share/icons/hicolor/256x256/apps/io.github.stellar.Stellar.png"
    cp "$ROOT/app/qml/icons/milky-way.png" \
        "$pkg_root/usr/share/icons/hicolor/128x128/apps/io.github.stellar.Stellar.png"

    write_launcher "$pkg_root/usr/bin/stellar" "/opt/stellar"

    python3 - "$pkg_root/usr/lib/mozilla/native-messaging-hosts/com.stellar.downloadmanager.json" <<'PY'
import json, sys
from pathlib import Path

path = Path(sys.argv[1])
data = json.loads(path.read_text(encoding="utf-8"))
data["path"] = "/usr/bin/stellar"
path.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
PY

    sed -i "s|^Exec=.*|Exec=/usr/bin/stellar|; s|^Icon=.*|Icon=io.github.stellar.Stellar|" \
        "$pkg_root/usr/share/applications/io.github.stellar.Stellar.desktop"

    bundle_qt_runtime "$app_dir"
    patch_bundled_rpaths "$app_dir"
}

build_app() {
    log "Configuring (linux-release)..."
    cmake --preset linux-release -S "$ROOT"
    log "Building..."
    cmake --build --preset linux-release
    ok "CMake build complete."
}

# ── .deb ──────────────────────────────────────────────────────────────────────

build_deb() {
    need_tool dpkg-deb

    log "Staging .deb filesystem..."
    rm -rf "$DEB_ROOT"
    mkdir -p "$DEB_ROOT/DEBIAN"

    stage_app "$DEB_ROOT"

    local installed_size_kib
    installed_size_kib="$(du -sk "$DEB_ROOT" | awk '{print $1}')"
    [[ -n "$installed_size_kib" ]] || installed_size_kib=1

    cat > "$DEB_ROOT/DEBIAN/control" <<EOF
Package: stellar
Version: $VERSION
Section: utils
Priority: optional
Architecture: $ARCH
Maintainer: Ninka_
Installed-Size: $installed_size_kib
Depends: libc6, libstdc++6, libgcc-s1, zlib1g, libx11-6, libxcb1, libxkbcommon0, libxcb-cursor0, libxkbcommon-x11-0, libxcb-icccm4, libxcb-image0, libxcb-keysyms1, libxcb-render-util0, libxcb-xinerama0
Homepage: https://stellar.moe/
Description: Stellar Download Manager
 Manage, accelerate, and schedule downloads.
EOF

    cat > "$DEB_ROOT/DEBIAN/postinst" <<'EOF'
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
    chmod 0755 "$DEB_ROOT/DEBIAN/postinst"

    mkdir -p "$DIST_DIR"
    log "Building .deb..."
    dpkg-deb --root-owner-group --build "$DEB_ROOT" "$DEB_FILE"
    sha256sum "$DEB_FILE" > "$DEB_SHA256"
    ok "Debian package: $DEB_FILE"
}

# ── .rpm ──────────────────────────────────────────────────────────────────────

build_rpm() {
    need_tool rpmbuild

    log "Staging RPM build tree..."
    rm -rf "$RPM_DIR"
    local rpm_root="$RPM_DIR/BUILDROOT/stellar-${VERSION}-1.x86_64"
    mkdir -p "$RPM_DIR"/{BUILD,RPMS,SOURCES,SPECS,SRPMS} "$rpm_root"

    stage_app "$rpm_root"

    # Build a file list from the staged tree for %files — rpmbuild needs paths
    # relative to the buildroot, one per line, with directory entries omitted.
    local files_list="$RPM_DIR/stellar.files"
    find "$rpm_root" -not -type d -printf "/%P\n" | sort > "$files_list"

    local spec_file="$RPM_DIR/SPECS/stellar.spec"
    cat > "$spec_file" <<SPEC
Name:           stellar
Version:        $VERSION
Release:        1%{?dist}
Summary:        Manage, accelerate, and schedule downloads
License:        GPL-3.0-or-later
URL:            https://stellar.moe/
BuildArch:      x86_64

# All content is pre-staged in BUILDROOT — nothing to build here.
%global debug_package %{nil}

%description
Stellar is a cross-platform download manager written in Qt6/C++.

%install
# Files already staged; rpmbuild picks them up from BUILDROOT automatically.

%post
if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database /usr/share/applications >/dev/null 2>&1 || true
fi
if command -v update-mime-database >/dev/null 2>&1; then
    update-mime-database /usr/share/mime >/dev/null 2>&1 || true
fi

%files
$(cat "$files_list")

%changelog
* $(date -u '+%a %b %d %Y') Ninka_ <admin@stellar.moe> - $VERSION-1
- Release $VERSION
SPEC

    log "Building .rpm..."
    rpmbuild \
        --define "_topdir $RPM_DIR" \
        --define "_rpmdir $RPM_DIR/RPMS" \
        --buildroot "$rpm_root" \
        -bb "$spec_file"

    local built_rpm
    built_rpm="$(find "$RPM_DIR/RPMS" -name '*.rpm' | head -1)"
    if [[ -z "$built_rpm" ]]; then
        echo "ERROR: rpmbuild produced no .rpm file." >&2
        exit 1
    fi

    mkdir -p "$DIST_DIR"
    cp "$built_rpm" "$RPM_FILE"
    sha256sum "$RPM_FILE" > "$RPM_SHA256"
    ok "RPM package: $RPM_FILE"
}

# ── Main ──────────────────────────────────────────────────────────────────────

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

if [[ $SKIP_RPM -eq 0 ]]; then
    build_rpm
else
    warn "Skipping .rpm build."
fi

ok "=== Linux release $VERSION complete ==="
[[ $SKIP_DEB -eq 0 ]] && echo "  deb      : $DEB_FILE" && echo "  sha256   : $DEB_SHA256"
[[ $SKIP_RPM -eq 0 ]] && echo "  rpm      : $RPM_FILE" && echo "  sha256   : $RPM_SHA256"
