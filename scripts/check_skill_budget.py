#!/usr/bin/env python3
"""Check Skill folders against an instruction budget and against their own links.

A long SKILL.md buries its rules, so each Skill keeps SKILL.md short, opens it with the
non-negotiable core, and loads phase-specific detail from references/. This checks the parts of
that contract a script can check:

  size         SKILL.md is at most --max-bytes, or the Skill's own `maxBytes` in skills.json
  frontmatter  SKILL.md opens with frontmatter whose `name` is the folder name and whose
               `description` is non-empty and at most 1024 characters
  orphan       every file under references/ is linked from SKILL.md itself, by a Markdown link
               or a code span holding its path
  link         every relative Markdown link (inline, image, or reference definition) resolves
  escape       no relative link leaves the Skill folder, the only thing an install copies
  anchor       a #fragment into a Markdown file names a heading there (GitHub slug) or an HTML id
  lost         with --since REV: every sentence, list item, table row, and code line that
               SKILL.md and references/*.md held at REV is still there as a whole unit (a finished
               sentence may only gain text after it). --allow FILE lists reviewed rewrites: each
               line is one reported unit, copied whole from the `lost:` line

Links are read from SKILL.md, references/**/*.md, and the Markdown files SKILL.md links to,
skipping fenced code, inline code, HTML comments, footnotes, and URLs with a scheme. With no
SKILL_DIR, every skills.json entry is checked at its checkout under --source-root. Exit 1 when any
Skill fails.
"""

from __future__ import annotations

import argparse
import html
import json
import re
import subprocess
import unicodedata
from pathlib import Path
from urllib.parse import unquote

from sync_skills import CATALOG, HOME, catalog_sources

MAX_BYTES = 8192  # files of 9 KB and up were the ones that needed restructuring; 3-5 KB were fine
MAX_DESCRIPTION = 1024  # Agent Skills frontmatter limit
FENCE = re.compile(r"^ {0,3}(`{3,}|~{3,})")
COMMENT = re.compile(r"<!--.*?-->", re.S)
CODE_SPAN = re.compile(r"(`+)((?:(?!\n[ \t]*\n).)+?)\1", re.S)
INLINE_LINK = re.compile(r"""!?\[(?:[^\[\]]|\[[^\]]*\])*\]\(\s*(<[^>]*>|[^)\s]+)(?:\s+(?:"[^"]*"|'[^']*'))?\s*\)""")
REF_DEFINITION = re.compile(r"^ {0,3}\[(?!\^)[^\]]+\]:\s*(<[^>]*>|\S+)")
SCHEME = re.compile(r"^(?:[A-Za-z][A-Za-z0-9+.-]*:|//)")
HEADING = re.compile(r"^ {0,3}#{1,6}\s+(.*?)(?:\s+#+)?\s*$")
HTML_ID = re.compile(r"""<[^>]*\b(?:id|name)\s*=\s*["']([^"']+)["']""")
SENTENCE_END = re.compile(r"(?<=[.!?])\s+(?=[A-Z`*\"(\u3000-\u9fff\uff00-\uffef])|(?<=[。！？；])")
TERMINAL = tuple(".!?;:。！？；：")


def read(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def body_lines(text: str) -> list[str]:
    """Lines outside the frontmatter and outside fenced code."""
    if text.startswith("---\n") and "\n---\n" in text[3:]:
        text = text[3:].split("\n---\n", 1)[1]
    lines, fence = [], None
    for line in text.splitlines():
        m = FENCE.match(line)
        if m and (fence is None or m.group(1)[0] == fence):
            fence = None if fence else m.group(1)[0]
        elif fence is None:
            lines.append(line)
    return lines


def prose(text: str) -> str:
    """Body text without fenced code, then code spans, then HTML comments: in that order, a comment
    marker quoted in code hides nothing."""
    return COMMENT.sub("", CODE_SPAN.sub(" ", "\n".join(body_lines(text))))


def link_targets(text: str) -> list[str]:
    body = prose(text)
    # Join each paragraph into one line so link text may wrap; reference definitions stay line-based.
    blocks = (" ".join(line.strip() for line in block.splitlines()) for block in re.split(r"\n[ \t]*\n", body))
    targets = [t for block in blocks for t in INLINE_LINK.findall(block)]
    targets += [t for line in body.splitlines() for t in REF_DEFINITION.findall(line)]
    return [t[1:-1] if t.startswith("<") else t for t in targets]


def code_spans(text: str) -> set[str]:
    return {m.group(2).strip() for m in CODE_SPAN.finditer("\n".join(body_lines(text)))}


def slug(heading: str) -> str:
    """GitHub's heading id: rendered text, lowercased, keeping letters, marks, decimal digits,
    underscores, hyphens, and spaces, with spaces turned into hyphens."""
    text = re.sub(r"!?\[([^\]]*)\]\([^)]*\)", r"\1", heading)
    text = html.unescape(re.sub(r"<[^>]+>", "", text).replace("`", "").replace("*", ""))
    kept = (c for c in text.lower() if c in " -" or unicodedata.category(c)[0] in "LM" or unicodedata.category(c) in ("Nd", "Pc"))
    return "".join(kept).replace(" ", "-")


def anchors(text: str) -> set[str]:
    found, seen = set(HTML_ID.findall(text)), {}
    for line in body_lines(text):
        m = HEADING.match(line)
        if m:
            base = slug(m.group(1))
            found.add(f"{base}-{seen[base]}" if base in seen else base)
            seen[base] = seen.get(base, 0) + 1
    return found


def frontmatter(text: str) -> dict[str, str] | None:
    if not text.startswith("---\n") or "\n---\n" not in text[3:]:
        return None
    fields: dict[str, str] = {}
    key = None
    for line in text[4:].split("\n---\n", 1)[0].splitlines():
        m = re.match(r"([A-Za-z_][\w-]*):\s*(.*)$", line)
        if m:
            key, value = m.group(1), m.group(2).strip()
            fields[key] = "" if value in (">", "|", ">-", "|-") else value.strip("\"'")
        elif key and line[:1] in (" ", "\t"):
            fields[key] = f"{fields[key]} {line.strip()}".strip()
    return fields


def references(skill: Path) -> list[Path]:
    folder = skill / "references"
    return sorted(p for p in folder.rglob("*") if p.is_file() and not p.name.startswith(".")) if folder.is_dir() else []


def check(skill: Path, max_bytes: int) -> list[str]:
    problems = []
    skill = skill.resolve()
    entry = skill / "SKILL.md"
    text = read(entry)
    size = entry.stat().st_size
    if size > max_bytes:
        problems.append(f"size: SKILL.md is {size} bytes, over the {max_bytes}-byte budget")
    fields = frontmatter(text)
    if fields is None:
        problems.append("frontmatter: SKILL.md does not open with --- frontmatter ---")
    else:
        if fields.get("name") != skill.name:
            problems.append(f"frontmatter: name {fields.get('name')!r} is not the folder name {skill.name!r}")
        description = fields.get("description", "")
        if not description or len(description) > MAX_DESCRIPTION:
            problems.append(f"frontmatter: description has {len(description)} characters (1-{MAX_DESCRIPTION})")

    root = skill
    linked: set[Path] = set()
    docs = [entry] + [p for p in references(skill) if p.suffix == ".md"]
    for doc in docs:
        doc_text = read(doc)
        for target in link_targets(doc_text):
            if SCHEME.match(target):
                continue
            path_part, _, fragment = target.partition("#")
            dest = (doc.parent / unquote(path_part)).resolve() if path_part else doc.resolve()
            where = f"{doc.relative_to(skill)}: {target}"
            if dest != root and root not in dest.parents:
                problems.append(f"escape: {where} leaves the Skill folder")
                continue
            if not dest.exists():
                problems.append(f"link: {where} does not exist")
                continue
            if doc == entry:
                linked.add(dest)
                if dest.suffix == ".md" and dest not in docs:
                    docs.append(dest)
            if fragment and dest.suffix == ".md" and unquote(fragment) not in anchors(read(dest)):
                problems.append(f"anchor: {where} names no heading in {dest.name}")

    spans = code_spans(text)
    for ref in references(skill):
        if ref.resolve() not in linked and ref.relative_to(skill).as_posix() not in spans:
            problems.append(f"orphan: {ref.relative_to(skill).as_posix()} is not linked from SKILL.md")
    return problems


def norm(text: str) -> str:
    return re.sub(r"\s+", " ", text.replace("**", "").replace("`", "")).strip()


def units(text: str) -> list[str]:
    """Checkable pieces of Markdown: code lines, table rows, and the sentences of prose."""
    out: list[str] = []
    para: list[str] = []

    def flush() -> None:
        # Drop bold markers first, or "**Lead.** Sentence." would not split after "Lead.".
        for piece in SENTENCE_END.split(" ".join(para).replace("**", "")):
            if any(c.isalpha() for c in piece):
                out.append(piece.strip())
        para.clear()

    if text.startswith("---\n") and "\n---\n" in text[3:]:
        text = text[3:].split("\n---\n", 1)[1]
    in_code = False
    for line in text.splitlines():
        if FENCE.match(line):
            flush()
            in_code = not in_code
        elif in_code or line.lstrip().startswith("|"):
            flush()
            if any(c.isalnum() for c in line):
                out.append(line.strip())
        elif not line.strip() or line.lstrip().startswith("#"):
            flush()
        else:
            m = re.match(r"\s*(?:[-*]|\d+\.)\s+(.*)", line)
            if m:
                flush()
            para.append(m.group(1) if m else line.strip())
    flush()
    return out


def lost(skill: Path, rev: str, allow: list[str]) -> list[str]:
    skill = skill.resolve()
    top = subprocess.run(["git", "-C", str(skill), "rev-parse", "--show-toplevel"], capture_output=True, text=True)
    if top.returncode != 0:
        return [f"lost: cannot compare with {rev}: not in a git repository"]
    root = Path(top.stdout.strip()).resolve()

    def git(*args: str) -> subprocess.CompletedProcess[str]:
        # Run from the repository root: ls-tree reads pathspecs relative to the working directory.
        return subprocess.run(["git", "-C", str(root), *args], capture_output=True, text=True)

    prefix = skill.relative_to(root)
    listed = git("ls-tree", "-r", "--name-only", rev, "--",
                 (prefix / "SKILL.md").as_posix(), (prefix / "references").as_posix())
    if listed.returncode != 0:
        return [f"lost: cannot read {rev}: {listed.stderr.strip()}"]
    current = [read(p) for p in [skill / "SKILL.md", *references(skill)] if p.suffix == ".md"]
    whole = {norm(unit) for text in current for unit in units(text)}

    def kept(unit: str) -> bool:
        # Whole units only: "Never push to main" must not pass as part of "... unless you are in a
        # hurry", nor "run the tests." as part of "never run the tests.". A finished sentence may
        # be followed by more text that the sentence split did not separate.
        return unit in whole or (unit.endswith(TERMINAL) and any(w.startswith(unit + " ") for w in whole))

    problems = []
    for name in listed.stdout.splitlines():
        if name.endswith(".md"):
            for unit in units(git("show", f"{rev}:{name}").stdout):
                if not kept(norm(unit)) and norm(unit) not in allow:
                    problems.append(f"lost: {Path(name).relative_to(prefix).as_posix()}: {unit}")
    return problems


def opening_lines(text: str) -> int:
    """Non-empty lines between the title and the first ## heading: where the core should be."""
    count = 0
    for line in body_lines(text):
        if line.startswith("## "):
            break
        count += bool(line.strip()) and not line.startswith("# ")
    return count


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("skills", nargs="*", type=Path, metavar="SKILL_DIR",
                        help="Skill folders to check (default: every catalog Skill)")
    parser.add_argument("--source-root", type=Path, default=HOME / "Documents/SKILLS",
                        help="directory holding one checkout per skill repository")
    parser.add_argument("--max-bytes", type=int, default=MAX_BYTES, help=f"SKILL.md budget for Skills without their own maxBytes (default {MAX_BYTES})")
    parser.add_argument("--since", metavar="REV", help="also report text lost since this git revision")
    parser.add_argument("--allow", type=Path, metavar="FILE",
                        help="reviewed rewrites for --since: one reported unit per line, copied whole")
    args = parser.parse_args()
    if args.allow and not args.since:
        parser.error("--allow needs --since")
    allow = [norm(line) for line in read(args.allow).splitlines() if line.strip()] if args.allow else []

    if args.skills:
        targets = [(path.resolve().name, path) for path in args.skills]
    else:
        targets = [(skill["name"], path) for skill, path in catalog_sources(args.source_root.expanduser().resolve())]
    budgets = {s["name"]: s["maxBytes"] for s in json.loads(read(CATALOG))["skills"] if "maxBytes" in s}
    failed = 0
    for name, skill in targets:
        budget = budgets.get(name, args.max_bytes)
        if not (skill / "SKILL.md").is_file():
            failed += 1
            print(f"FAIL {name}: no SKILL.md at {skill}")
            continue
        problems = check(skill, budget) + (lost(skill, args.since, allow) if args.since else [])
        failed += bool(problems)
        text = read(skill / "SKILL.md")
        print(f"{'FAIL' if problems else 'OK  '} {name}: SKILL.md {len(text.encode('utf-8'))} bytes, "
              f"{opening_lines(text)} opening lines, references: {len(references(skill))}"
              + (f", budget {budget}" if budget != args.max_bytes else ""))
        for problem in problems:
            print(f"  - {problem}")
    print(f"{len(targets) - failed} passed, {failed} failed (budget {args.max_bytes} bytes)")
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
