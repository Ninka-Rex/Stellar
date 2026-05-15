"""
Copy Papirus-Dark SVG icons into the app's icon directories.
Run from repo root: python scripts/apply_papirus_icons.py <papirus_dir>
  where <papirus_dir> = path to papirus-icon-theme-master/
"""
import os
import sys
import shutil
import re

def main():
    if len(sys.argv) < 2:
        print("Usage: python apply_papirus_icons.py <papirus-icon-theme-master-dir>")
        sys.exit(1)

    papirus_root = sys.argv[1]
    # Papirus-Dark SVGs; fall back to Papirus base if not overridden
    dark_base = os.path.join(papirus_root, "Papirus-Dark", "16x16")
    light_base = os.path.join(papirus_root, "Papirus", "16x16")

    def src(subdir, name):
        """Return path to SVG, preferring Papirus-Dark over Papirus."""
        dark = os.path.join(dark_base, subdir, name)
        light = os.path.join(light_base, subdir, name)
        if os.path.isfile(dark):
            return dark
        if os.path.isfile(light):
            return light
        return None

    icons_dir = os.path.join("app", "qml", "icons")
    cats_dir  = os.path.join(icons_dir, "categories")
    tcats_dir = os.path.join(icons_dir, "torrent-categories")

    # (dest_filename_without_ext, papirus_subdir, papirus_filename)
    # All outputs will be .svg
    mappings = [
        # ── root icons ──────────────────────────────────────────────────────
        ("add_url",                  "actions",   "add.svg"),
        ("add",                      "actions",   "add.svg"),
        ("arrow_down",               "actions",   "arrow-down.svg"),
        ("arrow_up",                 "actions",   "arrow-up.svg"),
        ("arrow_left",               "actions",   "arrow-left.svg"),
        ("arrow_right",              "actions",   "arrow-right.svg"),
        ("arrow_download",           "actions",   "browser-download.svg"),
        ("cancel",                   "actions",   "dialog-cancel.svg"),
        ("checkmark",                "actions",   "dialog-ok-apply.svg"),
        ("clock",                    "actions",   "clock.svg"),
        ("cloud_copylink",           "actions",   "url-copy.svg"),
        ("copy",                     "actions",   "edit-copy.svg"),
        ("copy_file",                "actions",   "edit-copy.svg"),
        ("custom_queue",             "actions",   "kt-queue-manager.svg"),
        ("delete",                   "actions",   "edit-delete.svg"),
        ("download",                 "actions",   "download.svg"),
        ("exit",                     "actions",   "application-exit.svg"),
        ("file_no_longer_available", "actions",   "action-unavailable.svg"),
        ("files_x",                  "actions",   "edit-delete.svg"),
        ("folder",                   "places",    "folder.svg"),
        ("folder_view",              "places",    "folder-open.svg"),
        ("folderdocuments",          "places",    "folder-documents.svg"),
        ("gear",                     "actions",   "configure.svg"),
        ("globe",                    "actions",   "globe.svg"),
        ("help",                     "actions",   "help-contents.svg"),
        ("information",              "actions",   "dialog-information.svg"),
        ("link",                     "actions",   "insert-link.svg"),
        ("magnet",                   "actions",   "kt-magnet.svg"),
        ("magnifying_glass",         "actions",   "search.svg"),
        ("main_queue",               "actions",   "kt-queue-manager.svg"),
        ("move_file",                "actions",   "edit-move.svg"),
        ("music",                    "mimetypes", "audio-x-generic.svg"),
        ("new_file",                 "actions",   "document-new.svg"),
        ("page",                     "mimetypes", "text-x-generic.svg"),
        ("paste",                    "actions",   "edit-paste.svg"),
        ("pause",                    "actions",   "media-playback-pause.svg"),
        ("pause_orange",             "actions",   "kt-stop-all.svg"),
        ("pause_purple",             "actions",   "kt-stop.svg"),
        ("properties",               "actions",   "document-properties.svg"),
        ("queues",                   "actions",   "view-media-queue.svg"),
        ("remove",                   "actions",   "list-remove.svg"),
        ("rename",                   "actions",   "edit-rename.svg"),
        ("resume",                   "actions",   "media-playback-start.svg"),
        ("resume_purple",            "actions",   "media-playback-start.svg"),
        ("rss",                      "actions",   "application-rss+xml.svg"),
        ("scheduler",                "actions",   "view-time-schedule.svg"),
        ("scheduler2",               "actions",   "view-time-schedule.svg"),
        ("search",                   "actions",   "search.svg"),
        ("settings",                 "actions",   "configure.svg"),
        ("spider",                   "apps",      "archivemanager.svg"),
        ("star",                     "actions",   "bookmark-add.svg"),
        ("stop",                     "actions",   "media-playback-stop.svg"),
        ("synch_queue",              "actions",   "folder-sync.svg"),
        ("tools",                    "actions",   "configure.svg"),
        ("trash",                    "actions",   "user-trash.svg"),
        ("update",                   "actions",   "system-upgrade.svg"),
        ("wand",                     "actions",   "tools-wizard.svg"),
        ("x_square",                 "actions",   "window-close.svg"),
        # ── categories/ ─────────────────────────────────────────────────────
        ("categories/all_downloads", "places",    "folder-downloads.svg"),
        ("categories/compressed",    "mimetypes", "application-x-7z-compressed.svg"),
        ("categories/documents",     "places",    "folder-documents.svg"),
        ("categories/note",          "mimetypes", "text-x-generic.svg"),
        ("categories/programs",      "mimetypes", "application-x-executable.svg"),
        ("categories/video",         "places",    "folder-videos.svg"),
        # ── torrent-categories/ ─────────────────────────────────────────────
        ("torrent-categories/all_torrents",  "apps",    "application-x-bittorrent.svg"),
        ("torrent-categories/active",        "actions", "media-playback-playing.svg"),
        ("torrent-categories/alarm-clock",   "actions", "clock.svg"),
        ("torrent-categories/checking",      "actions", "kt-check-data.svg"),
        ("torrent-categories/downloading",   "actions", "download.svg"),
        ("torrent-categories/inactive",      "actions", "media-playback-paused.svg"),
        ("torrent-categories/moving",        "actions", "transform-move.svg"),
        ("torrent-categories/seeding",       "actions", "kt-start-all.svg"),
        ("torrent-categories/stopped",       "actions", "kt-stop.svg"),
    ]

    # Fallback chains for icons that may not exist
    fallbacks = {
        "configure.svg":            [("actions", "preferences-system.svg"), ("actions", "gtk-preferences.svg")],
        "insert-link.svg":          [("actions", "add-link.svg"), ("actions", "link.svg")],
        "view-time-schedule.svg":   [("actions", "appointment-new.svg"), ("actions", "clock.svg")],
        "tools-wizard.svg":         [("actions", "tools-report-bug.svg"), ("actions", "run-build.svg")],
        "system-upgrade.svg":       [("actions", "update-none.svg"), ("actions", "view-refresh.svg")],
        "window-close.svg":         [("actions", "process-stop.svg"), ("actions", "cancel.svg")],
        "kt-check-data.svg":        [("actions", "kt-check-data.svg"), ("actions", "view-task.svg"), ("actions", "checkbox.svg")],
        "kt-start-all.svg":         [("actions", "kt-start-all.svg"), ("actions", "media-playback-start.svg")],
        "application-x-bittorrent.svg": [("mimetypes", "application-x-bittorrent.svg")],
    }

    copied = 0
    skipped = []

    for dest_stem, subdir, papirus_name in mappings:
        path = src(subdir, papirus_name)

        # Try fallbacks
        if not path and papirus_name in fallbacks:
            for fb_sub, fb_name in fallbacks[papirus_name]:
                path = src(fb_sub, fb_name)
                if path:
                    break

        if not path:
            skipped.append(f"  MISSING: {dest_stem} <- {subdir}/{papirus_name}")
            continue

        # Build dest path as .svg
        dest_path = os.path.join(icons_dir, dest_stem + ".svg")
        os.makedirs(os.path.dirname(dest_path), exist_ok=True)
        shutil.copy2(path, dest_path)
        print(f"  OK: {dest_stem}.svg <- {os.path.relpath(path, papirus_root)}")
        copied += 1

    print(f"\nCopied {copied} icons.")
    if skipped:
        print(f"Skipped {len(skipped)} (not found in Papirus):")
        print("\n".join(skipped))

    # Now update QML references: replace "icons/foo.png" with "icons/foo.svg"
    # and "icons/foo.ico" with "icons/foo.svg"
    # Skip world-map.svg (already SVG, keep), milky-way.* (excluded), torrent-client-logos/
    print("\nUpdating QML references...")
    qml_dir = os.path.join("app", "qml")
    updated_files = 0
    total_replacements = 0

    # Build set of dest stems we actually created
    created_stems = set()
    for dest_stem, _, _ in mappings:
        dest_path = os.path.join(icons_dir, dest_stem + ".svg")
        if os.path.isfile(dest_path):
            created_stems.add(dest_stem)

    for dirpath, _, filenames in os.walk(qml_dir):
        for fname in filenames:
            if not fname.endswith(".qml"):
                continue
            fpath = os.path.join(dirpath, fname)
            with open(fpath, "r", encoding="utf-8") as f:
                content = f.read()

            new_content = content
            # Match: "icons/foo.png", "icons/foo.ico", "icons/sub/foo.png", etc.
            # Don't touch: milky-way, torrent-client-logos, world-map.svg
            def replace_icon_ref(m):
                prefix = m.group(1)   # e.g. "icons/" or qrc path prefix
                stem   = m.group(2)   # e.g. "pause" or "categories/video"
                ext    = m.group(3)   # e.g. ".png" or ".ico"
                quote  = m.group(4)   # closing quote char

                # Skip excluded
                if "milky-way" in stem or "torrent-client-logos" in stem:
                    return m.group(0)
                if ext == ".svg":
                    return m.group(0)  # already svg

                # Normalise stem (strip leading icons/ if present in qrc paths)
                norm = stem
                if norm in created_stems or any(norm == s for s in created_stems):
                    return prefix + norm + ".svg" + quote
                return m.group(0)

            # Pattern covers both short ("icons/foo.png") and qrc long paths
            # Short: "icons/stem.ext"
            short = re.compile(r'("icons/)([^"]+?)\.(png|ico)(")')
            def repl_short(m):
                stem = m.group(2)
                if "milky-way" in stem or "torrent-client-logos" in stem:
                    return m.group(0)
                if stem in created_stems:
                    return m.group(1) + stem + ".svg" + m.group(4)
                return m.group(0)

            new_content, n = short.subn(repl_short, new_content)
            total_replacements += n

            # QRC long path variant: qrc:/qt/qml/com/stellar/app/app/qml/icons/stem.ext
            qrc = re.compile(r'("qrc:/[^"]*?/icons/)([^"]+?)\.(png|ico)(")')
            def repl_qrc(m):
                stem = m.group(2)
                if "milky-way" in stem or "torrent-client-logos" in stem:
                    return m.group(0)
                if stem in created_stems:
                    return m.group(1) + stem + ".svg" + m.group(4)
                return m.group(0)

            new_content, n = qrc.subn(repl_qrc, new_content)
            total_replacements += n

            if new_content != content:
                with open(fpath, "w", encoding="utf-8") as f:
                    f.write(new_content)
                print(f"  Updated QML: {fname}")
                updated_files += 1

    print(f"\nUpdated {updated_files} QML files, {total_replacements} icon references.")

    # Update CMakeLists.txt RESOURCES: replace listed .png/.ico with .svg for affected icons
    print("\nUpdating CMakeLists.txt...")
    cmake_path = "CMakeLists.txt"
    with open(cmake_path, "r", encoding="utf-8") as f:
        cmake = f.read()

    new_cmake = cmake
    cmake_replacements = 0

    def repl_cmake(m):
        stem = m.group(1)
        ext  = m.group(2)
        if "milky-way" in stem or "torrent-client-logos" in stem:
            return m.group(0)
        # normalise: strip leading path to get stem relative to icons/
        icon_stem = re.sub(r'^app/qml/icons/', '', stem)
        if icon_stem in created_stems:
            return "app/qml/icons/" + icon_stem + ".svg"
        return m.group(0)

    new_cmake, n = re.subn(
        r'(app/qml/icons/[^\s"]+?)\.(png|ico)',
        repl_cmake,
        new_cmake
    )
    cmake_replacements += n

    if new_cmake != cmake:
        with open(cmake_path, "w", encoding="utf-8") as f:
            f.write(new_cmake)
        print(f"  Updated CMakeLists.txt ({cmake_replacements} replacements)")
    else:
        print("  CMakeLists.txt unchanged")


if __name__ == "__main__":
    main()
