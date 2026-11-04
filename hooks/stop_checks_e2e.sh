#!/bin/bash
# End-to-end run of the Stop hook against throwaway git repositories.
# Usage: stop_checks_e2e.sh [hook-command]   (default: python3 stop_checks.py next to this script)
#
# Failure modes this run covers (written before the hook):
#  F1  non-git cwd blocks or errors              -> must pass silently
#  F2  clean repo blocks                         -> must pass
#  F3  new swallowed exception is not reported   -> must block and name it
#  F4  same finding blocks again next turn       -> must not block
#  F5  finding re-blocks after its line shifts   -> must not block
#  F6  old findings repeated with a new one      -> block lists only the new one
#  F7  stop_hook_active=true still blocks (loop) -> must pass, and not swallow the finding
#  F8  a removed finding is remembered forever   -> re-adding it must block again
#  F9  cwd in a subdirectory is missed           -> must still scan the repo
#  F10 stale living doc in a project map ignored -> must block with status output
#  F11 same stale doc blocks every turn          -> must not block again
#  F12 missing helper script passes silently     -> must exit 1 with an error
#  F13 malformed stdin passes silently           -> must exit 1
#  F14 crashing project_map.py is reported once  -> must exit 1 on every turn, never go quiet
# Added 2026-11-04 (session base and acceptance surfaces), written before the code:
#  F15 a finding committed during the session is invisible    -> SessionStart records the base; Stop blocks
#  F16 SessionStart on resume moves the base forward          -> a commit made before the resume still blocks
#  F17 a changed conventional eval file passes                -> blocks and names it as an acceptance surface
#  F18 REVIEW.md globs are ignored                            -> a declared path blocks, naming REVIEW.md
#  F19 REVIEW.md keeps the convention for unlisted eval dirs  -> an unlisted eval/ change is not listed
#  F20 an ordinary unit-test change blocks                    -> passes
#  F21 the same acceptance change blocks every turn           -> blocks once
#  F22 editing REVIEW.md itself passes                        -> blocks (dropping a glob is a requirement change)
#  F23 a recorded base that no longer exists crashes the hook -> falls back to HEAD, exit 0, still scans
#  F24 a Codex-style Stop payload is not understood           -> same block reply
HOOK=${1:-"python3 $(cd "$(dirname "$0")" && pwd)/stop_checks.py"}
T=$(mktemp -d "${TMPDIR:-/tmp}/stopchk.XXXX")
pass=0; fail=0

run() { # run <cwd> <active> [stdin-override]
  local input=${3:-"{\"hook_event_name\":\"Stop\",\"cwd\":\"$1\",\"stop_hook_active\":$2}"}
  out=$(printf '%s' "$input" | $HOOK 2>"$T/err"); code=$?
  err=$(cat "$T/err")
  blocked=$(printf '%s' "$out" | python3 -c 'import json,sys
d=sys.stdin.read().strip()
print("yes" if d and json.loads(d).get("decision")=="block" else "no")' 2>/dev/null || echo "bad-json")
}
check() { # check <label> <condition...>
  local label=$1; shift
  if "$@"; then pass=$((pass+1)); echo "PASS $label"
  else fail=$((fail+1)); echo "FAIL $label (exit $code, blocked=$blocked)"
    printf '%s\n' "$out" "$err" | sed 's/^/    /'; fi
}
has() { grep -q -- "$1" <<<"$out"; }
lacks() { ! grep -q -- "$1" <<<"$out"; }
swallow() { printf 'def %s():\n    try:\n        work()\n    except Exception:\n        pass\n' "$1"; }

# F1
mkdir -p "$T/plain"
run "$T/plain" false
check "F1 non-git dir passes silently" test "$code" = 0 -a "$blocked" = no

# F2
R="$T/repo"; mkdir -p "$R/src"; cd "$R" && git init -q && git config user.email t@t && git config user.name t
echo 'print("hi")' > src/main.py && git add -A && git commit -qm init
run "$R" false
check "F2 clean repo passes" test "$code" = 0 -a "$blocked" = no

# F3
swallow a > src/a.py
run "$R" false
check "F3 new swallowed exception blocks" test "$code" = 0 -a "$blocked" = yes
check "F3 reason names the file and kind" eval 'has src/a.py && has swallowed-exception'

# F4
run "$R" false
check "F4 same finding does not block again" test "$code" = 0 -a "$blocked" = no

# F5
{ printf '# header\n# header\n# header\n'; swallow a; } > src/a.py
run "$R" false
check "F5 shifted line does not block" test "$code" = 0 -a "$blocked" = no

# F6 + F9
swallow b > src/b.py
run "$R/src" false
check "F6/F9 new finding from a subdirectory blocks" test "$code" = 0 -a "$blocked" = yes
check "F6 only the new finding is listed" eval 'has src/b.py && lacks src/a.py'

# F7
swallow c > src/c.py
run "$R" true
check "F7 stop_hook_active passes" test "$code" = 0 -a "$blocked" = no
run "$R" false
check "F7 skipped finding is still reported later" eval 'test "$blocked" = yes && has src/c.py'

# F8
mv src/c.py "$T/c.py.saved"
run "$R" false
check "F8 removal passes" test "$code" = 0 -a "$blocked" = no
mv "$T/c.py.saved" src/c.py
run "$R" false
check "F8 re-added finding blocks again" eval 'test "$blocked" = yes && has src/c.py'

# F10 + F11
P="$T/mapped"; mkdir -p "$P/src"; cd "$P" && git init -q && git config user.email t@t && git config user.name t
python3 "$HOME/.claude/skills/project-map/scripts/project_map.py" init --root "$P" >/dev/null
echo 'v1' > src/app.txt && echo '# App' > README.md
python3 - <<'EOF'
p='.project-map/MAP.md'; s=open(p).read()
s=s.replace('<!-- One or two lines: what reaching the end of the current effort looks like. Every session orients to it. -->','Ship v1.')
s=s.rstrip('\n')+'\n| [README.md](../README.md) | `src/**` | |\n'
open(p,'w').write(s)
EOF
git add -A && git commit -qm init
run "$P" false
check "F10 healthy map passes" test "$code" = 0 -a "$blocked" = no
echo 'v2' > src/app.txt
run "$P" false
check "F10 stale living doc blocks" eval 'test "$blocked" = yes && has README.md'
run "$P" false
check "F11 same stale doc does not block again" test "$code" = 0 -a "$blocked" = no

# F12
mkdir -p "$T/emptyhome"
code=0; out=$(printf '{"cwd":"%s","stop_hook_active":false}' "$R" | HOME="$T/emptyhome" $HOOK 2>"$T/err") || code=$?
err=$(cat "$T/err")
check "F12 missing helper exits 1 with an error" eval 'test "$code" = 1 && grep -q design_integrity.py <<<"$err"'

# F14
FH="$T/crashhome/.claude/skills"; mkdir -p "$FH/project-map/scripts"
ln -s "$HOME/.claude/skills/design-integrity-review" "$FH/design-integrity-review"
printf 'import sys\nsys.exit("Traceback: boom")\n' > "$FH/project-map/scripts/project_map.py"
for turn in 1 2; do
  code=0; out=$(printf '{"cwd":"%s","stop_hook_active":false}' "$P" | HOME="$T/crashhome" $HOOK 2>"$T/err") || code=$?
  err=$(cat "$T/err"); blocked=n/a
  check "F14 crashing project_map.py exits 1 (turn $turn)" eval 'test "$code" = 1 && grep -q boom <<<"$err"'
done

# F13
run "$R" false 'not json'
check "F13 malformed stdin exits 1" test "$code" = 1

# F15-F24
ev_s() { printf '{"hook_event_name":"%s","cwd":"%s","session_id":"%s","stop_hook_active":false}' "$1" "$2" "$3"; }
run_s() { run "$2" false "$(ev_s "$1" "$2" "$3")"; }
A="$T/accept"; mkdir -p "$A/src" "$A/eval" "$A/tests/e2e" "$A/tests/unit"
cd "$A" && git init -q && git config user.email t@t && git config user.name t
echo 'print(1)' > src/app.py; echo 's = 1' > eval/score.py; echo 'flow' > tests/e2e/flow.spec.ts
echo 'def test_a(): pass' > tests/unit/test_a.py; git add -A && git commit -qm init
run_s SessionStart "$A" sess-1
check "F15 SessionStart prints nothing" test "$code" = 0 -a -z "$out"
swallow d > src/d.py && git add -A && git commit -qm "commit inside the session"
run_s Stop "$A" sess-1
check "F15 finding committed during the session blocks" eval 'test "$blocked" = yes && has src/d.py'
swallow f > src/f.py && git add -A && git commit -qm "commit before resume"
run_s SessionStart "$A" sess-1
run_s Stop "$A" sess-1
check "F16 resume keeps the first base" eval 'test "$blocked" = yes && has src/f.py'
echo 'def test_b(): pass' >> tests/unit/test_a.py
run_s Stop "$A" sess-1
check "F20 unit-test change passes" test "$code" = 0 -a "$blocked" = no
echo 's = 2' > eval/score.py
run_s Stop "$A" sess-1
check "F17 conventional eval change blocks as an acceptance surface" eval 'test "$blocked" = yes && has "eval/score.py (directory convention)" && has "Acceptance surfaces changed"'
run_s Stop "$A" sess-1
check "F21 same acceptance change does not block again" test "$code" = 0 -a "$blocked" = no
printf '# REVIEW.md\n\n## Acceptance surfaces\n\n- `tests/e2e/**`\n' > REVIEW.md
run_s Stop "$A" sess-1
check "F22 creating REVIEW.md blocks" eval 'test "$blocked" = yes && has "REVIEW.md (REVIEW.md)"'
check "F19 unlisted eval change is no longer an acceptance surface" eval 'lacks eval/score.py'
echo 'flow changed' > tests/e2e/flow.spec.ts
run_s Stop "$A" sess-1
check "F18 declared path blocks" eval 'test "$blocked" = yes && has "tests/e2e/flow.spec.ts (REVIEW.md)"'
mkdir -p "$A/.git/agent-session-base" && echo 0123456789abcdef0123456789abcdef01234567 > "$A/.git/agent-session-base/sess-2"
swallow g > src/g.py
run_s Stop "$A" sess-2
check "F23 missing base falls back to HEAD and still scans" eval 'test "$code" = 0 -a "$blocked" = yes && has src/g.py'
swallow h > src/h.py
codex_stop=$(printf '{"session_id":"019a-codex","turn_id":"t1","transcript_path":null,"cwd":"%s","hook_event_name":"Stop","model":"m","permission_mode":"default","stop_hook_active":false,"last_assistant_message":"done"}' "$A")
run "$A" false "$codex_stop"
check "F24 Codex Stop payload blocks the same way" eval 'test "$blocked" = yes && has src/h.py'

echo "---"; echo "passed $pass, failed $fail  (scratch: $T)"
[ "$fail" = 0 ]
