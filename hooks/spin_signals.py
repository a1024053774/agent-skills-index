#!/usr/bin/env python3
"""Claude Code hook: remind the model when a session shows spinning signals.

Spinning means patching a failure that does not go away, not editing a lot: building a feature takes many
edits and no test run, and that is normal. Signals, tracked per session:
  PostToolUseFailure on a test command, with edits since that command last ran -> one more failed fix
      attempt for that command; three in a row is a signal. A rerun without edits is not an attempt, and
      a passing run of the command clears its streak.
  PostToolUse / PostToolUseFailure on Bash -> a test command that fails after a test passed is a regression
  PostCompact                               -> compactions
When a signal first crosses its limit, the hook returns hookSpecificOutput.additionalContext, which Claude
Code places next to the tool result for the model; the user is not shown it. PostCompact cannot inject
context, so a compaction alert is delivered with the next tool event. Subagent events (agent_id) are ignored.

State: one JSON file per session under $SPIN_STATE_DIR (default ~/.claude/state/spin), updated under a lock.
Test: spin_signals_e2e.sh next to this file
"""
from __future__ import annotations

import fcntl
import json
import os
import re
import sys
import tempfile
from pathlib import Path

STATE_DIR = Path(os.environ.get("SPIN_STATE_DIR") or Path.home() / ".claude" / "state" / "spin")
FAIL_LIMIT = 3
REGRESSION_LIMIT = 2
COMPACTION_LIMIT = 2
EDIT_TOOLS = {"Edit", "Write", "MultiEdit", "NotebookEdit"}
TOOL_EVENTS = ("PostToolUse", "PostToolUseFailure")
TEST_COMMAND = re.compile(
    r"\b(pytest|unittest|jest|vitest|mocha|rspec|phpunit|ctest)\b"
    r"|\b(go|cargo|make) test\b|\b(npm|pnpm|yarn|bun)( run)? test\b"
    r"|_e2e\.sh\b|\btests?/\S+\.sh\b"
)
REMINDER = (
    "Spinning signal (automated hook, not from the user): {signals}. Stop patching. Re-read the latest "
    "failure and state the root-cause hypothesis before the next change. If you cannot state one, stop and "
    "report INCOMPLETE with a handoff (what was tried, what failed, the next hypothesis) so the work can "
    "resume in a fresh session."
)


def new_state() -> dict:
    # `edit_count` and `fails` replace the old per-file `edits` map; a state file written by the old
    # version keeps its `edits` key, which nothing reads any more.
    return {"edit_count": 0, "fails": {}, "last_test": None, "regressions": 0, "compactions": 0, "alerted": []}


def signals(state: dict) -> dict[str, str]:
    """Signal key -> description, for every signal at or over its limit."""
    found = {}
    for command, (streak, _seen) in sorted(state["fails"].items()):
        if streak >= FAIL_LIMIT:
            found[f"fail:{command}"] = f"`{command}` failed {streak} times in a row with edits in between"
    if state["regressions"] >= REGRESSION_LIMIT:
        found["regressions"] = f"tests regressed {state['regressions']} times (pass then fail)"
    if state["compactions"] >= COMPACTION_LIMIT:
        found["compactions"] = f"context compacted {state['compactions']} times"
    return found


def apply(state: dict, event: dict) -> None:
    name = event.get("hook_event_name")
    tool = event.get("tool_name")
    command = " ".join(((event.get("tool_input") or {}).get("command") or "").split())
    if name == "PostCompact":
        state["compactions"] += 1
    elif name == "PostToolUse" and tool in EDIT_TOOLS:
        state["edit_count"] += 1
    elif name in TOOL_EVENTS and tool == "Bash" and TEST_COMMAND.search(command):
        if name == "PostToolUse":
            state["fails"].pop(command, None)
            state["last_test"] = "pass"
            return
        if state["last_test"] == "pass":
            state["regressions"] += 1
        state["last_test"] = "fail"
        streak, seen = state["fails"].get(command, (0, -1))
        if streak == 0 or state["edit_count"] > seen:
            streak += 1
        state["fails"][command] = (streak, state["edit_count"])


def handle(event: dict) -> str | None:
    """Update the session state; return the reminder to inject, if any."""
    session_id = event.get("session_id")
    if not session_id or event.get("agent_id"):
        return None
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    path = STATE_DIR / (re.sub(r"[^A-Za-z0-9_-]", "_", session_id) + ".json")
    with open(path.with_suffix(".lock"), "w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        state = new_state()
        if path.is_file():
            state.update(json.loads(path.read_text(encoding="utf-8")))
        apply(state, event)
        new = []
        if event.get("hook_event_name") in TOOL_EVENTS:
            current = signals(state)
            new = [text for key, text in current.items() if key not in state["alerted"]]
            state["alerted"] = sorted(current)
        with tempfile.NamedTemporaryFile("w", dir=STATE_DIR, delete=False, encoding="utf-8") as tmp:
            json.dump(state, tmp, ensure_ascii=False)
        os.replace(tmp.name, path)
    return REMINDER.format(signals="; ".join(new)) if new else None


def main() -> int:
    try:
        event = json.load(sys.stdin)
    except json.JSONDecodeError as exc:
        print(f"spin_signals: stdin is not JSON: {exc}", file=sys.stderr)
        return 1
    reminder = handle(event)
    if reminder:
        output = {"hookEventName": event["hook_event_name"], "additionalContext": reminder}
        print(json.dumps({"hookSpecificOutput": output}, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main())
