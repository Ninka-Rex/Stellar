#!/usr/bin/env bash
# Stellar Download Manager - Linux release script
# Usage: ./release.sh [--version 0.2.0] [--skip-build] [--skip-deb] [--skip-rpm] [--parallel]
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
PARALLEL=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --version)    VERSION="$2"; shift 2 ;;
        --skip-build) SKIP_BUILD=1; shift ;;
        --skip-deb)   SKIP_DEB=1; shift ;;
        --skip-rpm)   SKIP_RPM=1; shift ;;
        --parallel)   PARALLEL=1; shift ;;
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
# patchelf is mandatory: without RPATH on the bundled binaries the loader
# falls back to system Qt at runtime (breaks on any distro whose system Qt
# is older than the build host's, e.g. shipping Kubuntu builds to Fedora).
need_tool patchelf

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
            if [[ -L "$src" && "$(basename "$src")" != "$base" ]]; then
                ln -sf "$base" "$dst_dir/$(basename "$src")"
            fi
            soname="$(readelf -d "$resolved" 2>/dev/null | awk -F'[][]' '/SONAME/ {print $2; exit}')"
            if [[ -n "$soname" && "$soname" != "$base" ]]; then
                ln -sf "$base" "$dst_dir/$soname"
            fi
            return 0
        fi
    fi

    cp -L "$resolved" "$dest"

    if [[ -L "$src" && "$(basename "$src")" != "$base" ]]; then
        ln -sf "$base" "$dst_dir/$(basename "$src")"
    fi

    soname="$(readelf -d "$resolved" 2>/dev/null | awk -F'[][]' '/SONAME/ {print $2; exit}')"
    if [[ -n "$soname" && "$soname" != "$base" ]]; then
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

# Sonames that must come from the system, never the bundle. Three classes:
#
#  1. glibc and its loader (libc, libm, libpthread, libdl, librt, libresolv,
#     libutil, libnsl, libBrokenLocale, ld-linux). glibc is tightly coupled to
#     the running kernel AND to the ld.so that maps the process. Bundling a
#     build-host glibc next to the system loader (or vice versa) makes symbol
#     resolution cross two incompatible glibc versions, which crashes *inside*
#     the dynamic loader (_dl_lookup_direct) before main() ever runs. This is a
#     hard rule of Linux app bundling: you ship everything EXCEPT glibc.
#
#  2. The GPU driver / GL stack. This is bigger than just libGL: the whole chain
#     from the GL entry points down to the kernel must match the user's installed
#     driver and running kernel:
#       - libGL/libGLX/libGLdispatch/libEGL/libGLES/libOpenGL — GL dispatch.
#       - libdrm  — Direct Rendering Manager; talks to the *kernel* GPU driver.
#       - libgbm  — Generic Buffer Management; driver/KMS coupled.
#       - libglapi — Mesa's GL API dispatch; must match the system Mesa.
#       - libxcb-glx — the GLX *wire protocol* over the X connection; must match
#         the running Xorg + driver, and must use the same libxcb as the server.
#       - libwayland-egl — EGL platform binding, driver coupled.
#     Bundling any of these makes Qt's xcb-glx integration probe a build-host GL
#     plumbing that can't talk to the user's actual driver (e.g. VirtualBox's
#     SVGA3D Mesa), so qglx_findConfig finds no FBConfig and Qt qFatals with
#     "Could not initialize GLX" — even though the *system* GL works fine
#     (glxinfo succeeds). Always use the system copies.
#
# All three classes are excluded from the recursive ldd walk and from the static
# xcb soname list, and come from the system via Depends/Requires instead.
is_system_only_soname() {
    case "$(basename "$1")" in
        # glibc + dynamic loader — never bundle.
        libc.so.*|libm.so.*|libpthread.so.*|libdl.so.*|librt.so.*|libresolv.so.*|\
        libutil.so.*|libnsl.so.*|libBrokenLocale.so.*|libanl.so.*|\
        ld-linux.so.*|ld-linux-x86-64.so.*|ld-linux-aarch64.so.*)
            return 0 ;;
        # GL dispatch + driver/kernel-coupled GL plumbing — must match the
        # user's driver, running Xorg and kernel. See note above.
        libGL.so.*|libGLX.so.*|libGLdispatch.so.*|libEGL.so.*|libGLESv2.so.*|libGLESv1_CM.so.*|libOpenGL.so.*|\
        libdrm.so.*|libgbm.so.*|libglapi.so.*|libwayland-egl.so.*)
            return 0 ;;
        # Core X11 protocol libs. libxcb-glx (GLX wire protocol) is loaded from
        # the system with the rest of the GL stack, and it MUST share the very
        # same libxcb.so.1 the X server side uses. If we bundle libxcb.so.1 (or
        # libX11) while libxcb-glx comes from the system, the two libxcb copies
        # disagree and qglx_findConfig returns no FBConfig -> "Could not
        # initialize GLX". So the whole core X-protocol layer must also come from
        # the system. These are present on every machine running an X server
        # (the user already has one, or they couldn't display anything), so they
        # are safe system Depends. Note: only the *core* libs here — the optional
        # xcb-util helpers (icccm/image/keysyms/render-util/cursor/...) stay
        # bundled, as minimal installs can lack them and they don't touch GLX.
        libxcb.so.*|libxcb-glx.so.*|libX11.so.*|libX11-xcb.so.*|libXau.so.*|libXdmcp.so.*)
            return 0 ;;
        # Wayland client/protocol libraries — the Wayland equivalent of the core
        # X-protocol libs above, and they fail the same way. libwayland-client is
        # the wire-protocol library that talks to the running compositor; the
        # system libEGL (Mesa) is built against the *system* libwayland-client and
        # creates the EGL-on-Wayland display through it. If we bundle our own
        # (older, build-host) libwayland-client, the process ends up with two
        # different libwayland-client copies — Qt's Wayland plugin uses the bundled
        # one while system libEGL uses its own — their wl_proxy objects are
        # incompatible, eglGetPlatformDisplay() fails, and Qt reports
        # "qt.qpa.wayland: EGL not available". RHI GLES2 then can't create a
        # context ("Failed to create RHI (backend 2)") and the app aborts on first
        # paint. So libwayland-client (and the cursor helper that shares its proxy
        # objects) must come from the system, matching the compositor + Mesa EGL.
        libwayland-client.so.*|libwayland-cursor.so.*|libwayland-server.so.*)
            return 0 ;;
        *) return 1 ;;
    esac
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
            # Never pull glibc or the GPU driver layer into the bundle (see note
            # above) — doing so crashes in the dynamic loader / GL init.
            if is_system_only_soname "$dep"; then
                continue
            fi
            copy_shared_object "$dep" "$dst_dir"
            queue+=("$dep")
        done < <(ldd "$target" 2>/dev/null | awk '/=> \// {print $3}' || true)
    done
}

qt_install_prefix() {
    # Prefer the Qt that actually linked the Stellar binary — qmake6 on PATH may
    # point at a different Qt (e.g. distro Qt vs. an online-installer Qt 6.10),
    # which would cause us to bundle libs from the wrong tree and miss any
    # 6.10-only modules (libQt6QuickControls2Material, etc.).
    local stellar_bin="$ROOT/build/linux-release/Stellar"
    if [[ -x "$stellar_bin" ]]; then
        local qtcore
        qtcore="$(ldd "$stellar_bin" 2>/dev/null | awk '/libQt6Core\.so/ {print $3; exit}')"
        if [[ -n "$qtcore" && -e "$qtcore" ]]; then
            qtcore="$(readlink -f "$qtcore")"
            # qtcore = <prefix>/lib[/<triplet>]/libQt6Core.so.6.X.Y
            local libdir prefix
            libdir="$(dirname "$qtcore")"
            prefix="$(dirname "$libdir")"
            # Strip x86_64-linux-gnu multiarch layer if present.
            if [[ "$(basename "$libdir")" == "x86_64-linux-gnu" ]]; then
                prefix="$(dirname "$prefix")"
            fi
            printf '%s\n' "$prefix"
            return
        fi
    fi
    if command -v qmake6 >/dev/null 2>&1; then
        qmake6 -query QT_INSTALL_PREFIX
        return
    fi
    if command -v qmake >/dev/null 2>&1; then
        qmake -query QT_INSTALL_PREFIX
        return
    fi
    echo "ERROR: Could not determine Qt install prefix." >&2
    exit 1
}

# Lib directory of the Qt that actually linked Stellar. Used directly so we
# never scan a different Qt's lib dir for the libQt6*.so.* glob.
qt_install_libdir() {
    local stellar_bin="$ROOT/build/linux-release/Stellar"
    if [[ -x "$stellar_bin" ]]; then
        local qtcore
        qtcore="$(ldd "$stellar_bin" 2>/dev/null | awk '/libQt6Core\.so/ {print $3; exit}')"
        if [[ -n "$qtcore" && -e "$qtcore" ]]; then
            dirname "$(readlink -f "$qtcore")"
            return
        fi
    fi
    local prefix
    prefix="$(qt_install_prefix)"
    for d in "$prefix/lib/x86_64-linux-gnu" "$prefix/lib"; do
        if [[ -d "$d" ]]; then
            printf '%s\n' "$d"
            return
        fi
    done
    echo "ERROR: Could not determine Qt lib directory." >&2
    exit 1
}

qt_install_plugins() {
    # Pin to the prefix of the Qt that actually linked Stellar.
    local prefix
    prefix="$(qt_install_prefix)"
    for d in \
        "$prefix/plugins" \
        "$prefix/lib/x86_64-linux-gnu/qt6/plugins" \
        "$prefix/lib/qt6/plugins" \
        "$prefix/lib64/qt6/plugins"; do
        if [[ -d "$d/platforms" ]]; then
            printf '%s\n' "$d"
            return
        fi
    done
    if command -v qmake6 >/dev/null 2>&1; then
        qmake6 -query QT_INSTALL_PLUGINS
        return
    fi
    echo "ERROR: Could not determine Qt plugin directory under $prefix." >&2
    exit 1
}

qt_install_qml() {
    local prefix
    prefix="$(qt_install_prefix)"
    for d in \
        "$prefix/qml" \
        "$prefix/lib/x86_64-linux-gnu/qt6/qml" \
        "$prefix/lib/qt6/qml" \
        "$prefix/lib64/qt6/qml"; do
        if [[ -d "$d/QtQuick" ]]; then
            printf '%s\n' "$d"
            return
        fi
    done
    if command -v qmake6 >/dev/null 2>&1; then
        qmake6 -query QT_INSTALL_QML
        return
    fi
    echo "ERROR: Could not determine Qt QML directory under $prefix." >&2
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
    qt_lib="$(qt_install_libdir)"

    mkdir -p "$lib_dir" "$plugin_dir" "$qml_dir"
    log "Bundling Qt runtime from: $qt_prefix"

    while read -r qt_so; do
        [[ -n "$qt_so" ]] || continue
        copy_shared_object "$qt_so" "$lib_dir"
    done < <(find "$qt_lib" -maxdepth 1 -type f \( -name 'libQt6*.so.*' -o -name 'libicu*.so.*' -o -name 'libdouble-conversion.so.*' -o -name 'libpcre2-16.so.*' \) 2>/dev/null || true)

    # NOTE: the GTK3 platform theme (libqgtk3) is deliberately NOT bundled. It
    # drags in the entire host GTK stack (libgtk-3, libgdk-3, pango, cairo, atk,
    # atspi, epoxy — ~40 libs) and then mismatches the user's system GTK theme
    # engine, producing transparent menus and a mis-themed title bar (the bundled
    # GTK != the distro's GTK theme). Stellar fully themes itself via QML (Material
    # dark/light), so it needs no native GTK integration.
    #
    # However, the xdg-desktop-portal platform theme (libqxdgdesktopportal.so) is
    # bundled when available. It gives native KDE/GNOME file dialogs via D-Bus IPC
    # without pulling in GTK — it talks to the portal daemon, not to GTK directly.
    if [[ -f "$qt_plugins/platformthemes/libqxdgdesktopportal.so" ]]; then
        mkdir -p "$plugin_dir/platformthemes"
        cp "$qt_plugins/platformthemes/libqxdgdesktopportal.so" "$plugin_dir/platformthemes/"
    fi
    for sub in platforms imageformats iconengines styles tls xcbglintegrations wayland-decoration-client wayland-graphics-integration-client wayland-shell-integration; do
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
        # NOTE: libGL/libGLX/libGLdispatch are intentionally NOT bundled. GL is
        # the driver layer (Mesa / NVIDIA) and must match the user's installed
        # GPU driver — a bundled libGL.so.1 mismatches it and causes black
        # windows or crashes. Pull it from the system instead (Depends: libgl1).
    )
    local so resolved
    for so in "${xcb_sonames[@]}"; do
        # Never copy a driver/GL-coupled lib here either (e.g. if libxcb-glx ever
        # gets added to the list) — those must come from the system.
        if is_system_only_soname "$so"; then
            continue
        fi
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

    # Module dirs are given as relative paths under the Qt qml/ root. Most are a
    # single dir (QtQuick.Controls is literally a dir of that name); the Qt.labs.*
    # modules are nested (Qt/labs/<name>). The non-native QtQuick.Dialogs
    # FileDialog fallback — used whenever no native/portal file dialog backend is
    # present (common on minimal Linux installs) — imports Qt.labs.folderlistmodel;
    # without it the FileDialog fails to load and the app segfaults on open().
    for mod in QtCore QtQml QtQuick QtQuick.2 QtQuick.Controls QtQuick.Controls.Material \
               QtQuick.Dialogs QtQuick.Layouts QtQuick.Shapes Qt5Compat \
               Qt/labs/folderlistmodel Qt/labs/platform Qt/labs/qmlmodels; do
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

    # Verify every libQt6*/libqt* DT_NEEDED referenced by the bundled binary,
    # plugins, and QML modules has a copy in lib/. Without this, the system
    # loader silently falls back to the host distro's Qt at runtime — which
    # produces "version 'Qt_6_PRIVATE_API' not found" when the host Qt is
    # older than the build Qt (e.g. Fedora /lib64 vs. Kubuntu-built 6.10).
    local missing=""
    local scan_targets=("$app_dir/Stellar")
    while read -r sofile; do
        [[ -n "$sofile" ]] || continue
        scan_targets+=("$sofile")
    done < <(find "$plugin_dir" "$qml_dir" -type f -name '*.so' 2>/dev/null || true)

    for target in "${scan_targets[@]}"; do
        while read -r needed; do
            [[ -n "$needed" ]] || continue
            case "$needed" in
                libQt6*|libqt*) ;;
                *) continue ;;
            esac
            if [[ ! -e "$lib_dir/$needed" ]]; then
                # Try to copy from qt_lib if present.
                if [[ -e "$qt_lib/$needed" ]]; then
                    copy_shared_object "$qt_lib/$needed" "$lib_dir"
                fi
                if [[ ! -e "$lib_dir/$needed" ]]; then
                    missing="${missing}  $needed  (needed by $(basename "$target"))"$'\n'
                fi
            fi
        done < <(readelf -d "$target" 2>/dev/null | awk -F'[][]' '/NEEDED/ {print $2}')
    done

    if [[ -n "$missing" ]]; then
        echo "ERROR: Missing Qt libraries in bundle (would fall back to system Qt at runtime):" >&2
        printf '%s' "$missing" >&2
        echo "       Scanned Qt lib dir: $qt_lib" >&2
        exit 1
    fi
}

patch_bundled_rpaths() {
    local app_dir="$1"

    patchelf --set-rpath '$ORIGIN/lib' "$app_dir/Stellar"

    # Bundled Qt libraries must find each other first, before any system Qt.
    # Without this, a build-machine Qt that exports Qt_6_PRIVATE_API symbols
    # will produce libs whose inter-dependencies leak out to /lib64 at runtime.
    while read -r sofile; do
        [[ -n "$sofile" ]] || continue
        patchelf --set-rpath '$ORIGIN' "$sofile" || true
    done < <(find "$app_dir/lib" -maxdepth 1 -type f -name '*.so*' 2>/dev/null || true)

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

# Graphics backend selection is done IN-PROCESS by Stellar itself
# (selectWorkingGraphicsBackend() in main.cpp): it probes for a usable OpenGL
# context before creating any window and falls back to the software scene graph
# when hardware GL is unavailable (VMs, Wayland-without-EGL, headless, broken
# drivers). There is therefore no crash to catch and no need for a relaunch
# wrapper here — the app just opens. Do not reintroduce a "run, detect crash,
# relaunch with software env" loop: that made a failed first launch the normal
# startup path (flickering tray icon, spurious crash notifications).
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
    for geo_db in "$ROOT"/app/data/dbip-city-lite-*.mmdb; do
        [[ -f "$geo_db" ]] || continue
        cp "$geo_db" "$app_dir/"
        break
    done
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
    prune_unused_qml "$app_dir"
    strip_bundle "$app_dir"
}

# Remove Qt Quick Controls styles we don't ship. Stellar uses the Material style
# (with Basic as its mandatory fallback); windeployqt/our bundler copy every style
# QtQuick.Controls can fall back to — FluentWinUI3 alone is ~7.5 MB of PNGs. None
# of the others are referenced, so dropping them is pure dead-weight removal.
prune_unused_qml() {
    local app_dir="$1"
    local ctrl="$app_dir/qml/QtQuick/Controls"
    [[ -d "$ctrl" ]] || return 0
    # Keep: Material (our style), Basic (Material's required fallback), and the
    # support modules Templates/impl pull in. Drop the rest.
    local style
    for style in FluentWinUI3 Universal Fusion Imagine designer; do
        rm -rf "$ctrl/$style"
    done
    # NativeStyle is the desktop "native look" backend — unused with Material.
    rm -rf "$app_dir/qml/QtQuick/NativeStyle"
}

# Strip debug symbols from the app binary and every bundled shared object. Qt's
# release libs and our own binary ship with symbol tables that bloat the install
# 2–4x (lib/ ~137 MB, Stellar ~38 MB) for no runtime benefit. ffmpeg/ffprobe are
# the worst offenders — BtbN's static GPL builds are ~196 MB each unstripped and
# drop to well under half that stripped. Use --strip-unneeded on shared objects
# (preserves dynamic symbols needed for linking) and a full strip on executables.
strip_bundle() {
    local app_dir="$1"
    command -v strip >/dev/null 2>&1 || { warn "strip not found — skipping symbol strip (install binutils to shrink the package)."; return 0; }

    # Executables: full strip.
    local exe
    for exe in Stellar ffmpeg ffprobe yt-dlp; do
        [[ -f "$app_dir/$exe" ]] || continue
        # yt-dlp is a self-contained PyInstaller binary, not an ELF we can strip
        # safely — stripping it corrupts the embedded archive. Skip it.
        [[ "$exe" == "yt-dlp" ]] && continue
        strip --strip-all "$app_dir/$exe" 2>/dev/null || true
    done

    # Shared objects: strip unneeded only (keep dynamic symbol table).
    while read -r sofile; do
        [[ -n "$sofile" ]] || continue
        strip --strip-unneeded "$sofile" 2>/dev/null || true
    done < <(find "$app_dir/lib" "$app_dir/plugins" "$app_dir/qml" -type f -name '*.so*' 2>/dev/null || true)
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
Depends: libc6, libstdc++6, libgcc-s1, libgl1, libglx0, libegl1, libdrm2, libgbm1, libxcb-glx0, libxcb1, libx11-6, libx11-xcb1, libxau6, libxdmcp6, libwayland-client0, libwayland-cursor0
Homepage: https://stellardownloadmanager.org/
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

    # Build the %files list from the staged tree (paths relative to the buildroot,
    # one per line). Every regular file/symlink is listed, plus a %dir entry for
    # each directory we create under /opt/stellar so rpm OWNS them and removes them
    # on erase (otherwise the bundle's dir tree is left orphaned). Shared system
    # dirs (/usr/bin, /usr/share/{applications,icons,metainfo}) are deliberately
    # NOT owned — they belong to filesystem/other packages — so only their files
    # are listed there, never the dirs themselves.
    local files_list="$RPM_DIR/stellar.files"
    {
        find "$rpm_root" -not -type d -printf "/%P\n"
        echo "%dir /opt/stellar"
        find "$rpm_root/opt/stellar" -mindepth 1 -type d -printf "%%dir /opt/stellar/%P\n"
    } | sort > "$files_list"

    local spec_file="$RPM_DIR/SPECS/stellar.spec"
    cat > "$spec_file" <<SPEC
Name:           stellar
Version:        $VERSION
Release:        1%{?dist}
Summary:        Manage, accelerate, and schedule downloads
License:        GPL-3.0-or-later
URL:            https://stellardownloadmanager.org/
BuildArch:      x86_64

# All content is pre-staged in BUILDROOT — nothing to build here.
# Qt runtime and xcb/X11 libs are bundled in /opt/stellar/lib — don't auto-scan
# for library deps (would pull the whole Qt/X stack the bundle already carries).
AutoReqProv:    no
# Explicit runtime deps for the few things we deliberately do NOT bundle:
#   - libc / libstdc++ / libgcc: core toolchain, never safe to bundle
#   - libGL.so.1: the GPU driver layer (Mesa/NVIDIA) — must match the user's
#     installed driver, so it comes from the system, not the bundle.
# Soname form keeps this distro-agnostic (Fedora mesa-libGL, openSUSE Mesa-libGL,
# etc. all provide libGL.so.1()(64bit)).
Requires:       libc.so.6()(64bit), libstdc++.so.6()(64bit), libgcc_s.so.1()(64bit), libGL.so.1()(64bit), libGLX.so.0()(64bit), libEGL.so.1()(64bit), libdrm.so.2()(64bit), libgbm.so.1()(64bit), libxcb-glx.so.0()(64bit), libxcb.so.1()(64bit), libX11.so.6()(64bit), libX11-xcb.so.1()(64bit), libXau.so.6()(64bit), libXdmcp.so.6()(64bit), libwayland-client.so.0()(64bit), libwayland-cursor.so.0()(64bit)
%global debug_package %{nil}
# Default __spec_install_pre wipes the buildroot before running %install.
# Our files are already staged, so disable that wipe (keep env setup only).
%global __spec_install_pre %{___build_pre}

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
        --define "dist %{nil}" \
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

if [[ $PARALLEL -eq 1 ]]; then
    # Run deb and rpm packaging concurrently; each writes to its own build dir.
    declare -a pids=()
    declare -a jobs=()

    if [[ $SKIP_DEB -eq 0 ]]; then
        build_deb &
        pids+=($!)
        jobs+=(deb)
    else
        warn "Skipping .deb build."
    fi

    if [[ $SKIP_RPM -eq 0 ]]; then
        build_rpm &
        pids+=($!)
        jobs+=(rpm)
    else
        warn "Skipping .rpm build."
    fi

    failed=0
    for i in "${!pids[@]}"; do
        if ! wait "${pids[$i]}"; then
            echo "ERROR: ${jobs[$i]} packaging failed." >&2
            failed=1
        fi
    done
    [[ $failed -eq 0 ]] || exit 1
else
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
fi

ok "=== Linux release $VERSION complete ==="
[[ $SKIP_DEB -eq 0 ]] && echo "  deb      : $DEB_FILE" && echo "  sha256   : $DEB_SHA256"
[[ $SKIP_RPM -eq 0 ]] && echo "  rpm      : $RPM_FILE" && echo "  sha256   : $RPM_SHA256"
