#!/usr/bin/env bash
# Stellar Download Manager — Linux / Flatpak release script
# Usage: ./release.sh [--version 0.2.0] [--skip-build] [--skip-flatpak] [--skip-archive]
#
# Prerequisites:
#   flatpak-builder   (sudo apt install flatpak-builder / dnf install flatpak-builder)
#   flatpak runtime   (org.kde.Platform//6.8 + org.kde.Sdk//6.8)
#   p7zip-full        (for 7z archive)
#
# Install runtimes once:
#   flatpak install flathub org.kde.Platform//6.8 org.kde.Sdk//6.8
#
# Output:
#   dist/linux/io.github.stellar.Stellar.flatpak
#   releases/Stellar-<version>-linux-flatpak.7z
#   releases/Stellar-<version>-source.7z

set -euo pipefail

VERSION=""
SKIP_BUILD=0
SKIP_FLATPAK=0
SKIP_ARCHIVE=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --version)       VERSION="$2";   shift 2 ;;
        --skip-build)    SKIP_BUILD=1;   shift ;;
        --skip-flatpak)  SKIP_FLATPAK=1; shift ;;
        --skip-archive)  SKIP_ARCHIVE=1; shift ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

ROOT="$(cd "$(dirname "$0")" && pwd)"

# ── Auto-detect version from CMakeLists.txt ──────────────────────────────────
if [[ -z "$VERSION" ]]; then
    VERSION=$(grep -oP 'project\s*\(\s*\w+\s+VERSION\s+\K[\d]+\.[\d]+\.[\d]+(?:\.[\d]+)?' "$ROOT/CMakeLists.txt" | head -1)
    if [[ -z "$VERSION" ]]; then
        echo "ERROR: Could not detect version from CMakeLists.txt. Pass --version explicitly." >&2
        exit 1
    fi
    echo "[release] Detected version: $VERSION"
fi

FLATPAK_MANIFEST="$ROOT/packaging/flatpak/io.github.stellar.Stellar.yml"
FLATPAK_BUILD_DIR="$ROOT/build/flatpak"
FLATPAK_REPO_DIR="$ROOT/build/flatpak-repo"
DIST_DIR="$ROOT/dist"
LINUX_DIST_DIR="$DIST_DIR/linux"
RELEASES_DIR="$ROOT/releases"
FLATPAK_FILE="$LINUX_DIST_DIR/io.github.stellar.Stellar.flatpak"

log()  { echo -e "\033[0;36m[release]\033[0m $*"; }
ok()   { echo -e "\033[0;32m[release]\033[0m $*"; }
warn() { echo -e "\033[0;33m[release]\033[0m $*"; }

# ── Direct CMake build (non-Flatpak, for testing/CI) ─────────────────────────
if [[ $SKIP_BUILD -eq 0 ]]; then
    log "Configuring (linux-release)..."
    cmake --preset linux-release -S "$ROOT" 2>&1
    log "Building..."
    cmake --build --preset linux-release
    ok "CMake build complete."
else
    warn "Skipping CMake build."
fi

# ── Flatpak build ─────────────────────────────────────────────────────────────
if [[ $SKIP_FLATPAK -eq 0 ]]; then
    log "Building Flatpak..."
    mkdir -p "$FLATPAK_BUILD_DIR" "$FLATPAK_REPO_DIR" "$LINUX_DIST_DIR"

    flatpak-builder \
        --force-clean \
        --repo="$FLATPAK_REPO_DIR" \
        "$FLATPAK_BUILD_DIR" \
        "$FLATPAK_MANIFEST"

    log "Bundling single-file .flatpak..."
    flatpak build-bundle \
        "$FLATPAK_REPO_DIR" \
        "$FLATPAK_FILE" \
        io.github.stellar.Stellar

    ok "Flatpak: $FLATPAK_FILE"
else
    warn "Skipping Flatpak build."
fi

# ── 7-Zip archives (all build steps done — archive everything now) ────────────
if [[ $SKIP_ARCHIVE -eq 0 ]]; then
    mkdir -p "$RELEASES_DIR"

    FLATPAK_ARCHIVE="$RELEASES_DIR/Stellar-${VERSION}-linux-flatpak.7z"
    SOURCE_ARCHIVE="$RELEASES_DIR/Stellar-${VERSION}-source.7z"

    # Archive 1: flatpak bundle
    if [[ -f "$FLATPAK_FILE" ]]; then
        log "Archiving flatpak -> $FLATPAK_ARCHIVE"
        7z a -t7z -mx=9 -mmt=on "$FLATPAK_ARCHIVE" "$FLATPAK_FILE"
        ok "Flatpak archive done."
    else
        warn "No .flatpak file found at $FLATPAK_FILE - skipping flatpak archive."
    fi

    # Archive 2: source code
    log "Archiving source -> $SOURCE_ARCHIVE"
    7z a -t7z -mx=9 -mmt=on \
        -xr\!build \
        -xr\!dist \
        -xr\!releases \
        -xr\!backups \
        -xr\!'.git/objects' \
        -xr\!'*.stellar-part-*' \
        -xr\!'*.stellar-meta' \
        "$SOURCE_ARCHIVE" \
        "$ROOT"
    ok "Source archive done."
else
    warn "Skipping archives."
fi

ok "=== Linux release $VERSION complete ==="
echo "  releases/ : $RELEASES_DIR"
