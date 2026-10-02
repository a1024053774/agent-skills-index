#!/bin/bash
# Acceptance run for scripts/check_skill_budget.py against throwaway Skill folders.
# Run: bash tests/check_skill_budget_e2e.sh
# Against another build of the checker (for example a deliberately broken copy):
#   CHECK="python3 /path/to/copy.py" bash tests/check_skill_budget_e2e.sh
#
# Ways the checker can fail, each covered below:
#   misses a fault  - each known-bad Skill must exit 1 and name its check:
#     size         SKILL.md over the default budget, and over --max-bytes
#     frontmatter  none at all, `name` not the folder name, empty description, a description of
#                  1025 characters
#     orphan       a file under references/ that SKILL.md never links
#     link         an inline link, a link whose text wraps onto the next line, a link between comment
#                  markers quoted in inline code, and a reference-style definition, each to a file
#                  that does not exist
#     escape       a link to an existing file outside the Skill folder
#     anchor       a fragment naming no heading (in another file, in the same file, and a third
#                  duplicate heading that does not exist)
#     lost         with --since: a deleted sentence, a deleted short CJK sentence, a deleted
#                  two-character CJK item, an unpunctuated list item weakened by an appended
#                  qualifier, a punctuated item negated by a prefix, a rewrite missing from the
#                  allow file, and an allow line that is only a fragment of the old text
#     checkout     a catalog Skill with no local checkout
#   false alarm     - the good Skill must exit 0 although it has: GitHub slugs for punctuation, inline
#                     code, CJK, duplicate headings, an HTML entity, and a superscript digit; a link
#                     title; an angle-bracket target; a link whose text wraps; a reference-style
#                     link; a footnote; a stale link inside an HTML comment; a reference mentioned as
#                     a code span; a directory link; URL and mailto links; a same-file anchor; links
#                     inside inline code and a fenced block that point nowhere. Also passing: the
#                     same Skill with CRLF line endings, a description of exactly 1024 characters,
#                     and with --since a sentence moved verbatim into references/ or behind a bold
#                     lead-in, and a rewrite listed in --allow
ROOT=$(cd "$(dirname "$0")/.." && pwd)
CHECK=${CHECK:-"python3 $ROOT/scripts/check_skill_budget.py"}
T=$(mktemp -d "${TMPDIR:-/tmp}/skillbudget.XXXX"); cd "$T" || exit 1
pass=0; fail=0
ok() { pass=$((pass+1)); echo "PASS $1"; }
no() { fail=$((fail+1)); echo "FAIL $1"; [ -n "$2" ] && echo "$2" | sed 's/^/    /'; }

# expect <label> <exit code> <text the output must contain, or empty> <checker args...>
expect() {
  local label=$1 code=$2 needle=$3; shift 3
  local out; out=$($CHECK "$@" 2>&1); local got=$?
  if [ "$got" = "$code" ] && { [ -z "$needle" ] || printf '%s' "$out" | grep -qF -- "$needle"; }; then ok "$label"
  else no "$label (exit $got, wanted $code${needle:+ with '$needle'})" "$out"; fi
}

mkdir -p good/demo/references good/demo/assets
cat > good/demo/SKILL.md <<'EOF'
---
name: demo
description: A fixture Skill for the budget check.
---

# Demo

Use when testing the budget check. The core comes first.

## Steps

Read [the handoff](references/handoff.md#stage-gates-finish-and-handoff) before finishing.
See [the format](references/format.md#mapjson-format), [来源](references/format.md#来源), [the second notes](references/format.md#notes-1), and [起草](references/format.md#一起草先确定要表达什么).
Check [the Q&A](references/format.md#qa) and [the footnote heading](references/format.md#note).
Ask [with a title](references/handoff.md "Handoff") or [in angle brackets](<references/handoff.md>).
Read [the format notes when the
layout matters](references/format.md#notes) first.
Read [the example][ex] when needed, and `references/mentioned.md` when asked.
Templates live in [assets](assets/). Upstream: [site](https://example.com/missing.md), [mail](mailto:someone@example.com). Back to [steps](#steps).
Code is not a link: `[x](nowhere.md)`. The limit comes from upstream.[^1]

<!-- Moved: [old notes](references/old-notes.md) -->

```text
[not a link either](missing.md)
```

[ex]: references/example.md
[^1]: See the upstream note.
EOF
cat > good/demo/references/handoff.md <<'EOF'
# Handoff

## Stage gates, finish, and handoff

Close the session only when the owner confirms. 保存后回读实际文件。

- Never push to main
- run the tests before you push.
- 勿删
EOF
cat > good/demo/references/format.md <<'EOF'
# Format

Back to [the steps](../SKILL.md#steps).

## `map.json` format

## 来源

## Notes

## Notes

## 一、起草：先确定要表达什么

## Q&amp;A

## Note²
EOF
echo "# Example" > good/demo/references/example.md
echo "# Mentioned" > good/demo/references/mentioned.md
echo "template" > good/demo/assets/template.txt

expect "good Skill passes" 0 "1 passed, 0 failed" good/demo
expect "budget flag: good Skill over --max-bytes 100" 1 "size:" good/demo --max-bytes 100

# variant <dir> <name> <python that edits files in <dir>/<name>/demo; s holds SKILL.md and is written back>
variant() {
  rm -rf "$1/$2"; mkdir -p "$1/$2"; cp -R good/demo "$1/$2/demo"
  (cd "$1/$2/demo" && python3 - "$3" <<'EOF'
import sys
from pathlib import Path
p = Path("SKILL.md"); s = p.read_text(encoding="utf-8")
exec(sys.argv[1])
p.write_bytes(s.encode("utf-8"))
EOF
  )
}

variant ok crlf 's = s.replace("\n", "\r\n"); [f.write_bytes(f.read_bytes().replace(b"\n", b"\r\n")) for f in Path("references").glob("*.md")]'
expect "CRLF line endings pass" 0 "1 passed" ok/crlf/demo
variant ok desc1024 's = s.replace("description: A fixture Skill for the budget check.", "description: " + "x" * 1024)'
expect "description of exactly 1024 characters passes" 0 "1 passed" ok/desc1024/demo

variant bad size 's += "padding " * 1200'
expect "size: SKILL.md over the default budget" 1 "size:" bad/size/demo
variant bad nofm 's = s.split("---\n", 2)[2]'
expect "frontmatter: missing" 1 "frontmatter:" bad/nofm/demo
variant bad name 's = s.replace("name: demo", "name: demo2")'
expect "frontmatter: name differs from the folder" 1 "frontmatter: name" bad/name/demo
variant bad nodesc 's = s.replace("description: A fixture Skill for the budget check.", "description:")'
expect "frontmatter: empty description" 1 "frontmatter: description" bad/nodesc/demo
variant bad desc1025 's = s.replace("description: A fixture Skill for the budget check.", "description: " + "x" * 1025)'
expect "frontmatter: description of 1025 characters" 1 "frontmatter: description" bad/desc1025/demo
variant bad orphan 'Path("references/unlinked.md").write_text("# Unlinked\n", encoding="utf-8")'
expect "orphan: reference not linked from SKILL.md" 1 "orphan: references/unlinked.md" bad/orphan/demo
variant bad inline 's = s.replace("(references/handoff.md \"Handoff\")", "(references/gone.md)")'
expect "link: inline link to a missing file" 1 "link: SKILL.md: references/gone.md" bad/inline/demo
variant bad wrapped 's = s.replace("layout matters](references/format.md#notes)", "layout matters](references/gone.md)")'
expect "link: wrapped link text to a missing file" 1 "link: SKILL.md: references/gone.md" bad/wrapped/demo
variant bad quotedcomment 's += "\nOpen a note with `<!--`.\nSee [between](references/missing-between.md).\nClose it with `-->`.\n"'
expect "link: comment markers quoted in code hide no link" 1 "link: SKILL.md: references/missing-between.md" bad/quotedcomment/demo
variant bad refdef 's = s.replace("[ex]: references/example.md", "[ex]: references/missing.md"); Path("references/example.md").unlink()'
expect "link: reference definition to a missing file" 1 "link: SKILL.md: references/missing.md" bad/refdef/demo
variant bad escape 'Path("../outside.md").write_text("# Outside\n", encoding="utf-8"); s += "\nSee [outside](../outside.md).\n"'
expect "escape: link leaves the Skill folder" 1 "escape:" bad/escape/demo
variant bad anchor 's = s.replace("handoff.md#stage-gates-finish-and-handoff", "handoff.md#no-such-heading")'
expect "anchor: fragment names no heading in another file" 1 "anchor: SKILL.md: references/handoff.md#no-such-heading" bad/anchor/demo
variant bad selfanchor 's = s.replace("(#steps)", "(#nope)")'
expect "anchor: same-file fragment names no heading" 1 "anchor: SKILL.md: #nope" bad/selfanchor/demo
variant bad dupanchor 's = s.replace("#notes-1", "#notes-2")'
expect "anchor: third duplicate heading does not exist" 1 "anchor:" bad/dupanchor/demo

# --since: each case copies a git repository holding the good Skill, edits it, and compares with HEAD
mkdir base; cp -R good/demo base/demo
git -C base init -q && git -C base add -A \
  && git -C base -c user.name=t -c user.email=t@example.com -c commit.gpgsign=false commit -qm base
since() {
  rm -rf "since/$1"; mkdir -p since; cp -R base "since/$1"
  (cd "since/$1/demo" && python3 - "$2" <<'EOF'
import sys
from pathlib import Path
s, h = Path("SKILL.md"), Path("references/handoff.md")
exec(sys.argv[1])
EOF
  )
}
edit='def sub(p, a, b): t = p.read_text(encoding="utf-8"); assert a in t, a; p.write_text(t.replace(a, b), encoding="utf-8")'

since same ''
expect "lost: unchanged Skill passes" 0 "1 passed" since/same/demo --since HEAD
since moved "$edit"'
sub(s, "Use when testing the budget check. ", "")
sub(h, "# Handoff\n", "# Handoff\n\nUse when testing the budget check.\n")'
expect "lost: sentence moved verbatim into references passes" 0 "1 passed" since/moved/demo --since HEAD
since boldlead "$edit"'
sub(h, "Close the session only when the owner confirms. ", "")
sub(s, "## Steps\n", "## Steps\n\n- **Owner first.** Close the session only when the owner confirms.\n")'
expect "lost: sentence moved verbatim behind a bold lead-in passes" 0 "1 passed" since/boldlead/demo --since HEAD
since deleted "$edit"'
sub(h, "Close the session only when the owner confirms. ", "")'
expect "lost: deleted sentence is reported" 1 "lost: references/handoff.md: Close the session only when the owner confirms." since/deleted/demo --since HEAD
since cjk "$edit"'
sub(h, " 保存后回读实际文件。", "")'
expect "lost: deleted short CJK sentence is reported" 1 "lost: references/handoff.md: 保存后回读实际文件。" since/cjk/demo --since HEAD
since weakened "$edit"'
sub(h, "- Never push to main", "- Never push to main unless you are in a hurry")'
expect "lost: unpunctuated item weakened by a qualifier is reported" 1 "lost: references/handoff.md: Never push to main" since/weakened/demo --since HEAD
since negated "$edit"'
sub(h, "- run the tests before you push.", "- never run the tests before you push.")'
expect "lost: punctuated item negated by a prefix is reported" 1 "lost: references/handoff.md: run the tests before you push." since/negated/demo --since HEAD
since tinycjk "$edit"'
sub(h, "\n- 勿删", "")'
expect "lost: deleted two-character CJK item is reported" 1 "lost: references/handoff.md: 勿删" since/tinycjk/demo --since HEAD
since rewritten "$edit"'
sub(h, "Close the session only when the owner confirms.", "Close the session once the owner confirms.")'
expect "lost: rewrite not in the allow file is reported" 1 "lost:" since/rewritten/demo --since HEAD
echo "Close the session only when the owner confirms." > allow-unit.txt
expect "lost: rewrite listed in --allow passes" 0 "1 passed" since/rewritten/demo --since HEAD --allow allow-unit.txt
echo "the" > allow-fragment.txt
expect "lost: an allow line that is only a fragment does not hide the rewrite" 1 "lost:" since/rewritten/demo --since HEAD --allow allow-fragment.txt

# per-Skill budget: a skills.json entry's maxBytes replaces the default for that Skill only
# (grilling carries maxBytes 11264 in the catalog; project-map does not)
sized() { # sized <dir> <name> <bytes>
  mkdir -p "$1"
  python3 - "$1/SKILL.md" "$2" "$3" <<'PY'
import sys
path, name, size = sys.argv[1], sys.argv[2], int(sys.argv[3])
head = f"---\nname: {name}\ndescription: Fixture sized for the budget check.\n---\n\n# Fixture\n\n"
open(path, "w", encoding="utf-8").write(head + "x" * (size - len(head) - 1) + "\n")
PY
}
sized budget-ok/grilling grilling 10752
sized budget-over/grilling grilling 11500
sized budget-other/project-map project-map 10752
expect "budget: catalog maxBytes lets grilling pass above the default" 0 "" budget-ok/grilling
expect "budget: catalog maxBytes still caps grilling" 1 "over the 11264-byte budget" budget-over/grilling
expect "budget: a Skill without maxBytes keeps the default" 1 "over the 8192-byte budget" budget-other/project-map

# catalog mode: every skills.json entry, at its checkout under --source-root
mkdir -p empty-root
expect "checkout: catalog Skill without a local checkout fails" 1 "no SKILL.md" --source-root empty-root

echo
echo "== $pass passed, $fail failed  (fixtures: $T)"
[ "$fail" = 0 ]
