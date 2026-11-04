#!/bin/bash
# End-to-end run of the spinning-signal hook. Payloads follow the documented hook input.
# Usage: spin_signals_e2e.sh [hook-cmd]
# The reminder goes to the model only: hookSpecificOutput.additionalContext on PostToolUse /
# PostToolUseFailure. PostCompact cannot inject context, so compaction alerts ride on the next tool event.
#
# Spinning means patching a failure that does not go away, not editing a lot. Failure modes this run
# covers (rewritten 2026-11-04 before the code; the old edit-count signal punished normal multi-edit work):
#  F1  many edits with no test run raise a reminder           -> quiet: building a feature is not spinning
#  F2  a test failing 3 times in a row with edits in between  -> remind with the command and the count,
#       goes unnoticed                                            on PostToolUseFailure
#  F3  the reminder is shown to the user or repeats           -> additionalContext only, once per streak
#  F4  rerunning a failing test without edits counts          -> not a fix attempt: the streak does not grow
#  F5  a pass does not clear the streak, or a new streak      -> pass clears it; re-crossing reminds again
#       after a pass is never reported
#  F6  a different failing command continues the streak       -> each command has its own streak
#  F7  one regression reminds, or non-test failures count     -> two test regressions remind; others ignored
#  F8  PostCompact prints output it cannot deliver, or        -> silent on PostCompact; the next tool
#       compactions are never reported                           event carries the reminder
#  F9  one session's signals leak into another                -> isolated
#  F10 subagent tool calls change the main session            -> events with agent_id are ignored
#  F11 parallel hook runs duplicate the reminder              -> 20 concurrent failures remind exactly once
#  F12 malformed stdin passes silently                        -> exit 1
HOOK=${1:-"python3 $(cd "$(dirname "$0")" && pwd)/spin_signals.py"}
T=$(mktemp -d "${TMPDIR:-/tmp}/spin.XXXX")
export SPIN_STATE_DIR="$T/state"
pass=0; fail=0

ev() { printf '%s' "$1" | $HOOK 2>>"$T/err"; }
edit() { ev "{\"session_id\":\"$1\",\"hook_event_name\":\"PostToolUse\",\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$2\"},\"tool_response\":{}}"; }
bash_ok() { ev "{\"session_id\":\"$1\",\"hook_event_name\":\"PostToolUse\",\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"$2\"},\"tool_response\":\"ok\"}"; }
bash_fail() { ev "{\"session_id\":\"$1\",\"hook_event_name\":\"PostToolUseFailure\",\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"$2\"},\"error\":\"exit 1\"}"; }
compact() { ev "{\"session_id\":\"$1\",\"hook_event_name\":\"PostCompact\",\"trigger\":\"auto\"}"; }
ctx() { python3 -c 'import json,sys
d=sys.stdin.read().strip()
if d:
    o=json.loads(d); h=o.get("hookSpecificOutput",{})
    print(h.get("hookEventName",""), "|", h.get("additionalContext",""), "|", "systemMessage" in o)'; }
check() { local label=$1; shift
  if "$@"; then pass=$((pass+1)); echo "PASS $label"
  else fail=$((fail+1)); echo "FAIL $label"; echo "    out=[$o]"; sed 's/^/    err: /' "$T/err" 2>/dev/null; fi; }
PT="python3 -m pytest -q tests/test_cart.py"

# F1
o=$(for i in $(seq 1 12); do edit s1 /repo/src/cart.py; done)
check "F1 twelve edits without a test stay quiet" test -z "$o"

# F2, F3
o=$( { bash_fail s1 "$PT"; edit s1 /repo/src/cart.py; bash_fail s1 "$PT"; edit s1 /repo/src/cart.py; } )
check "F2 two failing fix attempts stay quiet" test -z "$o"
o=$(bash_fail s1 "$PT" | ctx)
check "F2 third failure after edits reminds with command and count" eval 'grep -q "tests/test_cart.py. failed 3 times in a row" <<<"$o"'
check "F3 reminder is model context on PostToolUseFailure, not shown to the user" eval 'grep -q "^PostToolUseFailure |" <<<"$o" && grep -q "| False$" <<<"$o"'
edit s1 /repo/src/cart.py >/dev/null
o=$(bash_fail s1 "$PT")
check "F3 fourth failure does not remind again" test -z "$o"

# F4
o=$( { bash_fail s2 "$PT"; bash_fail s2 "$PT"; bash_fail s2 "$PT"; bash_fail s2 "$PT"; } )
check "F4 reruns without edits do not grow the streak" test -z "$o"

# F5
o=$(bash_ok s1 "$PT")
check "F5 passing test is silent" test -z "$o"
o=$( { bash_fail s1 "$PT"; edit s1 /repo/a.py; bash_fail s1 "$PT"; edit s1 /repo/a.py; } )
o=$(bash_fail s1 "$PT" | ctx)
check "F5 new streak after a pass reminds again" eval 'grep -q "failed 3 times in a row" <<<"$o"'

# F6
o=$( { bash_fail s3 "npm test"; edit s3 /repo/a.js; bash_fail s3 "$PT"; edit s3 /repo/a.js; bash_fail s3 "npm test"; } )
check "F6 alternating commands keep separate streaks" test -z "$o"

# F7
o=$( { bash_ok s6 "$PT"; bash_fail s6 "$PT"; } )
check "F7 one regression stays quiet" test -z "$o"
o=$( { bash_fail s6 "ls /nonexistent"; bash_ok s6 "ls"; bash_fail s6 "git push"; } )
check "F7 non-test failures are ignored" test -z "$o"
bash_ok s6 "bash tests/stale_check_e2e.sh" >/dev/null
o=$(bash_fail s6 "npm test" | ctx)
check "F7 second regression reminds on PostToolUseFailure" eval 'grep -q "^PostToolUseFailure |" <<<"$o" && grep -q "regressed 2 times" <<<"$o"'

# F8
o=$( { compact s7; compact s7; } )
check "F8 PostCompact prints nothing" test -z "$o"
o=$(bash_ok s7 "ls" | ctx)
check "F8 next tool event carries the compaction reminder" eval 'grep -q "compacted 2 times" <<<"$o"'

# F9
o=$( { edit s8 /repo/a.py; bash_fail s8 "$PT"; } )
check "F9 other session is not reminded" test -z "$o"

# F10
o=$(for i in 1 2 3; do
  ev "{\"session_id\":\"s9\",\"agent_id\":\"sub1\",\"hook_event_name\":\"PostToolUse\",\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"/repo/b.py\"},\"tool_response\":{}}"
  ev "{\"session_id\":\"s9\",\"agent_id\":\"sub1\",\"hook_event_name\":\"PostToolUseFailure\",\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"$PT\"},\"error\":\"exit 1\"}"
done)
check "F10 subagent events are ignored" test -z "$o"

# F11
{ bash_fail s10 "$PT"; edit s10 /repo/r.py; bash_fail s10 "$PT"; edit s10 /repo/r.py; } >/dev/null
for i in $(seq 1 20); do bash_fail s10 "$PT" > "$T/race.$i" & done; wait
o=$(cat "$T"/race.* | grep -c additionalContext)
check "F11 twenty concurrent failures remind exactly once" test "$o" = 1

# F12
printf 'not json' | $HOOK >/dev/null 2>&1; code=$?; o=$code
check "F12 malformed stdin exits 1" test "$code" = 1

echo "---"; echo "passed $pass, failed $fail  (scratch: $T)"
[ "$fail" = 0 ]
