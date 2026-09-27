#!/usr/bin/env python3
# Stellar Download Manager — shared extension code sync
# Copyright (C) 2026 Ninka_
# GNU GPL v3.0 — https://www.gnu.org/licenses/gpl-3.0.html
"""Copy extensions/shared/ into every browser package.

Browsers load an extension from one self-contained directory and refuse paths
outside it, and the app points users at extensions/<browser>/ to load unpacked.
So extensions/shared/ is the single source of truth and each package carries a
generated copy in <browser>/shared/. Edit only extensions/shared/, then run:

    python extensions/sync_shared.py          # update the copies
    python extensions/sync_shared.py --check  # exit 1 if a copy is stale
"""

import filecmp
import shutil
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent
SOURCE = ROOT / "shared"
PACKAGES = ("chrome", "firefox")


def relative_files(directory: Path) -> set:
    if not directory.is_dir():
        return set()
    return {p.relative_to(directory) for p in directory.rglob("*") if p.is_file()}


def sync(check_only: bool) -> int:
    wanted = relative_files(SOURCE)
    if not wanted:
        print(f"error: {SOURCE} is empty or missing", file=sys.stderr)
        return 2
    stale = []
    for package in PACKAGES:
        target = ROOT / package / "shared"
        for rel in sorted(relative_files(target) - wanted):
            stale.append(target / rel)
            if not check_only:
                (target / rel).unlink()
        for rel in sorted(wanted):
            src, dst = SOURCE / rel, target / rel
            if dst.is_file() and filecmp.cmp(src, dst, shallow=False):
                continue
            stale.append(dst)
            if not check_only:
                dst.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(src, dst)
        if not check_only:
            # Directories emptied by removed files would otherwise ship as clutter.
            for d in sorted((p for p in target.rglob("*") if p.is_dir()), reverse=True):
                if not any(d.iterdir()):
                    d.rmdir()
    if check_only and stale:
        print("Out-of-date shared copies (run extensions/sync_shared.py):", file=sys.stderr)
        for path in stale:
            print(f"  {path.relative_to(ROOT)}", file=sys.stderr)
        return 1
    if not check_only:
        print(f"Synced {len(wanted)} shared file(s) into {', '.join(PACKAGES)}"
              + (f" ({len(stale)} updated)" if stale else " (already current)"))
    return 0


if __name__ == "__main__":
    sys.exit(sync("--check" in sys.argv[1:]))
