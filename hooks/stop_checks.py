#!/usr/bin/env python3
"""Stop hook for Claude Code and Codex: run the deterministic checks the skills otherwise rely on the model to remember.

- design_integrity.py: exception boundaries added since the session started (a locator, not proof),
  and changed acceptance surfaces (REVIEW.md `## Acceptance surfaces`, or the directory convention).
- project_map.py status: structural problems and stale living docs, when the repo has `.project-map/`.

Both harnesses call this script with the same JSON on stdin and read the same `{"decision": "block",
"reason": ...}` reply. Register it for SessionStart as well as Stop: on SessionStart it records HEAD in
`<git-dir>/agent-session-base/<session_id>` (only once, so a resume keeps the original base), and on Stop
it compares the working tree with that commit. Without a recorded base it falls back to HEAD, which cannot
see changes the session already committed.

Each finding blocks the stop once. Reported findings are remembered in `<git-dir>/claude-stop-checks.txt`,
keyed without line numbers, so a finding does not block again on later turns; the file is rewritten with
the current findings, so one that disappears and comes back blocks again. When the stop is already a
continuation forced by a Stop hook (`stop_hook_active`), nothing blocks, which rules out a loop.

Exit 0 always lets the harness act on stdout; exit 1 (bad input, missing helper) surfaces as a
non-blocking hook error so a broken setup is visible instead of silently passing.
Test: stop_checks_e2e.sh next to this file
"""
from __future__ import annotations

import json
import re
import subprocess
import sys
from pathlib import Path

SKILLS = Path.home() / ".claude" / "skills"
SCANNER = SKILLS / "design-integrity-review" / "scripts" / "design_integrity.py"
PROJECT_MAP = SKILLS / "project-map" / "scripts" / "project_map.py"
STATE_NAME = "claude-stop-checks.txt"
BASES_DIR = "agent-session-base"


def git(cwd: Path, *args: str) -> str | None:
    result = subprocess.run(["git", *args], cwd=cwd, capture_output=True, text=True)
    return result.stdout.strip() if result.returncode == 0 else None


def run_helper(script: Path, *args: str) -> subprocess.CompletedProcess[str]:
    if not script.is_file():
        raise FileNotFoundError(f"stop_checks: helper not found: {script}")
    return subprocess.run([sys.executable, str(script), *args], capture_output=True, text=True)


def base_file(git_dir: str, event: dict) -> Path | None:
    session_id = event.get("session_id")
    if not session_id:
        return None
    return Path(git_dir) / BASES_DIR / re.sub(r"[^A-Za-z0-9_-]", "_", session_id)


def record_base(root: Path, git_dir: str, event: dict) -> None:
    path = base_file(git_dir, event)
    head = git(root, "rev-parse", "--verify", "HEAD")
    if path is None or path.is_file() or not head:
        return
    path.parent.mkdir(exist_ok=True)
    path.write_text(head + "\n", encoding="utf-8")


def session_base(root: Path, git_dir: str, event: dict) -> str | None:
    """The commit this session started from, if it was recorded and still exists."""
    path = base_file(git_dir, event)
    if path is None or not path.is_file():
        return None
    sha = path.read_text(encoding="utf-8").strip()
    return sha if git(root, "cat-file", "-e", f"{sha}^{{commit}}") is not None else None


def scanner_findings(root: Path, base: str | None) -> tuple[dict[str, str], dict[str, str]]:
    """Map each finding's line-free key to its display line: (exception boundaries, acceptance changes)."""
    args = ["--cwd", str(root), "--format", "json"] + (["--base", base] if base else [])
    result = run_helper(SCANNER, *args)
    if result.returncode != 0:
        raise RuntimeError(f"stop_checks: design_integrity.py failed: {result.stderr.strip()}")
    data = json.loads(result.stdout)
    findings = {}
    for f in data["findings"]:
        key = "\t".join(("scan", f["path"], f["kind"], " ".join(f["text"].split())))
        findings[key] = f"{f['path']}:{f['line']}: {f['kind']}: {f['text']}"
    source = data["acceptance_source"]
    accepted = {"\t".join(("accept", path)): f"{path} ({source})" for path in data["acceptance_changes"]}
    return findings, accepted


def map_findings(root: Path) -> dict[str, str]:
    if not (root / ".project-map").is_dir():
        return {}
    result = run_helper(PROJECT_MAP, "status", "--root", str(root))
    if result.returncode == 0:
        return {}
    findings, section = {}, None
    for line in result.stdout.splitlines():
        if not line.startswith("  - "):
            section = line.split(" (")[0]
        elif section in ("Problems", "Stale living docs"):
            item = line[4:]
            findings["\t".join(("map", section, item))] = f"{section}: {item}"
    if not findings:
        raise RuntimeError(f"stop_checks: project_map.py status exited {result.returncode} "
                           f"without listing problems: {(result.stderr or result.stdout).strip()}")
    return findings


def reason(scan_new: list[str], accept_new: list[str], map_new: list[str]) -> str:
    parts = ["Stop checks found new items. Each is reported once and will not block again."]
    if accept_new:
        parts += ["", "Acceptance surfaces changed in this session:"]
        parts += [f"- {line}" for line in accept_new]
        parts += ["An acceptance test is frozen during implementation: changing it changes the requirement. "
                  "Revert the change, or say in the reply that the user asked for it or approved it. "
                  "Do not edit an acceptance test to make it pass."]
    if scan_new:
        parts += ["", "design_integrity.py (a locator, not proof; a hit is not a defect):"]
        parts += [f"- {line}" for line in scan_new]
        parts += ["For each, confirm a real caller or failure reaches it and that this layer owns the "
                  "recovery (design-integrity-review gates). Keep legitimate handling; never delete it "
                  "just to silence this check. State your conclusion in the reply."]
    if map_new:
        parts += ["", "project_map.py status:"]
        parts += [f"- {line}" for line in map_new]
        parts += ["Update each stale living doc to match the code, or set its Verified cell to the "
                  "current commit if the change does not affect it; fix structural problems."]
    return "\n".join(parts)


def main() -> int:
    try:
        event = json.load(sys.stdin)
    except json.JSONDecodeError as exc:
        print(f"stop_checks: stdin is not JSON: {exc}", file=sys.stderr)
        return 1
    cwd = Path(event.get("cwd") or ".")
    toplevel = git(cwd, "rev-parse", "--show-toplevel")
    git_dir = git(cwd, "rev-parse", "--absolute-git-dir")
    if not toplevel or not git_dir:
        return 0
    root = Path(toplevel)
    if event.get("hook_event_name") == "SessionStart":
        record_base(root, git_dir, event)
        return 0
    if event.get("stop_hook_active"):
        return 0
    try:
        scan, accepted = scanner_findings(root, session_base(root, git_dir, event))
        mapped = map_findings(root)
    except (FileNotFoundError, RuntimeError) as exc:
        print(exc, file=sys.stderr)
        return 1

    state = Path(git_dir) / STATE_NAME
    reported = set(state.read_text(encoding="utf-8").splitlines()) if state.is_file() else set()
    current = {**scan, **accepted, **mapped}
    state.write_text("".join(f"{key}\n" for key in sorted(current)), encoding="utf-8")

    scan_new = [line for key, line in scan.items() if key not in reported]
    accept_new = [line for key, line in accepted.items() if key not in reported]
    map_new = [line for key, line in mapped.items() if key not in reported]
    if scan_new or accept_new or map_new:
        print(json.dumps({"decision": "block", "reason": reason(scan_new, accept_new, map_new)},
                         ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main())
