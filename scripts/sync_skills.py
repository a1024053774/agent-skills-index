#!/usr/bin/env python3
"""Reconcile local agent skill directories around one hub, ~/.agents/skills.

- Catalog skills (skills.json) are linked into the hub from local checkouts under --source-root,
  where each repository is checked out as <source-root>/<repository name>.
- Harnesses that cannot read the hub get links into it (MIRRORS).
- Harnesses that already read the hub lose symlinks that duplicate a hub skill (HUB_READERS).

Dry run by default; pass --apply to change links. Real directories are never moved or deleted,
only reported.
"""

from __future__ import annotations

import argparse
import json
import os
from pathlib import Path

HOME = Path.home()
HUB = HOME / ".agents/skills"
# Harness skill dirs that do not read the hub: dir -> skill names to link (None = every hub skill).
MIRRORS: dict[Path, list[str] | None] = {
    HOME / ".claude/skills": None,
    HOME / ".workbuddy/skills": ["document-writing"],
}
# Harness skill dirs that read the hub themselves (Codex, Cursor, Gemini CLI, Factory Droid).
HUB_READERS = [HOME / ".codex/skills", HOME / ".cursor/skills", HOME / ".gemini/skills", HOME / ".factory/skills"]
CATALOG = Path(__file__).resolve().parent.parent / "skills.json"


def target_of(link: Path) -> Path:
    return (link.parent / os.readlink(link)).resolve()


def entries(directory: Path) -> list[Path]:
    return sorted(p for p in directory.iterdir() if not p.name.startswith(".")) if directory.is_dir() else []


def plan(source_root: Path) -> tuple[list[tuple[str, Path, Path | None]], list[str]]:
    """Return (actions, notes). An action is ("link", path, target) or ("remove", path, None)."""
    actions: list[tuple[str, Path, Path | None]] = []
    notes: list[str] = []

    def ensure_link(path: Path, target: Path) -> None:
        if path.is_symlink():
            if target_of(path) != target.resolve():
                actions.extend([("remove", path, None), ("link", path, target)])
        elif path.exists():
            notes.append(f"{path}: real directory, expected a link to {target}; left as is")
        else:
            actions.append(("link", path, target))

    hub_names = {p.name for p in entries(HUB)}
    for skill in json.loads(CATALOG.read_text(encoding="utf-8"))["skills"]:
        source = source_root / skill["repository"].rstrip("/").split("/")[-1] / skill["path"]
        if not (source / "SKILL.md").is_file():
            notes.append(f"{skill['name']}: no local checkout at {source}; not linked")
            continue
        ensure_link(HUB / skill["name"], source)
        hub_names.add(skill["name"])
    for name in sorted(hub_names):
        if (HUB / name).is_symlink() and not (HUB / name).exists():
            notes.append(f"{HUB / name}: broken hub link")

    for directory, wanted in MIRRORS.items():
        names = sorted(hub_names) if wanted is None else wanted
        for name in names:
            ensure_link(directory / name, HUB / name)
        for path in entries(directory):
            if path.name not in names and path.is_symlink() and not path.exists():
                actions.append(("remove", path, None))

    for directory in HUB_READERS:
        for path in entries(directory):
            if path.is_symlink() and (path.name in hub_names or not path.exists()):
                actions.append(("remove", path, None))
            elif path.name in hub_names:
                notes.append(f"{path}: real directory duplicates hub skill {path.name}; left as is")
    return actions, notes


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--source-root", type=Path, default=HOME / "Documents/SKILLS",
                        help="directory holding one checkout per skill repository")
    parser.add_argument("--apply", action="store_true", help="change links (default: dry run)")
    args = parser.parse_args()
    actions, notes = plan(args.source_root.expanduser().resolve())
    for kind, path, target in actions:
        print(f"{'' if args.apply else '[dry run] '}{kind} {path}" + (f" -> {target}" if target else ""))
        if args.apply:
            if kind == "remove":
                path.unlink()
            else:
                path.parent.mkdir(parents=True, exist_ok=True)
                path.symlink_to(target)
    for note in notes:
        print(f"note: {note}")
    print(f"{len(actions)} change(s), {len(notes)} note(s){'' if args.apply else '; rerun with --apply'}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
