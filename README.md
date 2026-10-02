# Agent Skills Index

A catalog of reusable Skills maintained by `a1024053774`. Each Skill keeps its own canonical
repository and release history; this repository provides one stable discovery and installation
entry point without copying Skill code or creating synchronization drift.

## Catalog

### Reality and evidence

- [`reality-first-engineering`](https://github.com/a1024053774/reality-evidence-engineering/tree/main/reality-first-engineering)
  — establish a fact-backed direction gate before consequential implementation.
- [`evidence-first-testing`](https://github.com/a1024053774/reality-evidence-engineering/tree/main/evidence-first-testing)
  — preserve red-state evidence and prove that tests detect the intended behavior.

Source repository: [reality-evidence-engineering](https://github.com/a1024053774/reality-evidence-engineering)

### Design integrity and acceptance

- [`design-integrity-review`](https://github.com/a1024053774/design-integrity-guardrails/tree/main/design-integrity-review)
  — review one frozen change once for structural shortcuts, or route evaluation changes to acceptance review.
- [`behavioral-acceptance-review`](https://github.com/a1024053774/design-integrity-guardrails/tree/main/behavioral-acceptance-review)
  — audit whether tests, evals, and user-visible workflows provide independent evidence, including release verdicts for Agent products.

Source repository: [design-integrity-guardrails](https://github.com/a1024053774/design-integrity-guardrails)

### Decisions and project state

- [`grilling`](https://github.com/a1024053774/grilling-skill/tree/main/grilling)
  — stress-test a plan or decision in rounds until the way forward is clear, then hand off.
- [`project-map`](https://github.com/a1024053774/project-map-skill/tree/main/project-map)
  — keep a project's decisions, tickets, glossary, and living docs in a small local map; carry work from
  decisions to a spec, tracer-bullet build tickets, and one ticket per session; catch stale docs.

Source repositories: [grilling-skill](https://github.com/a1024053774/grilling-skill) · [project-map-skill](https://github.com/a1024053774/project-map-skill)

### Understanding a codebase

- [`architecture-flow-map`](https://github.com/a1024053774/architecture-flow-map-skill/tree/main/architecture-flow-map)
  — trace how an existing codebase actually runs into an interactive map: modules, business objects, and key
  scenarios replayed step by step, with every code reference verified against the repository.

Source repository: [architecture-flow-map-skill](https://github.com/a1024053774/architecture-flow-map-skill)

### Writing

- [`document-writing`](https://github.com/a1024053774/document-writing-skill/tree/main/document-writing)
  — draft, polish, or translate documents with natural target-language prose, semantic fidelity, and encoding protection.

Source repository: [document-writing-skill](https://github.com/a1024053774/document-writing-skill)

### Frontend

- [`frontend-less-ai-tone`](https://github.com/a1024053774/frontend-less-ai-tone-skill/tree/main/frontend-less-ai-tone)
  — make frontend work look and read like a specific product, not a generic AI landing page.
- [`same-visual-family`](https://github.com/a1024053774/same-visual-family-skill/tree/main/same-visual-family)
  — keep composed UI in one visual family; drop-in skinned blocks fail, restyled structure can pass.

Source repositories: [frontend-less-ai-tone-skill](https://github.com/a1024053774/frontend-less-ai-tone-skill) · [same-visual-family-skill](https://github.com/a1024053774/same-visual-family-skill)

## Install examples

Install one Skill globally:

```bash
npx skills add a1024053774/grilling-skill@grilling -g -y
```

Install a Skill from the other source repositories:

```bash
npx skills add a1024053774/reality-evidence-engineering@reality-first-engineering -g -y
npx skills add a1024053774/reality-evidence-engineering@evidence-first-testing -g -y
npx skills add a1024053774/design-integrity-guardrails@design-integrity-review -g -y
npx skills add a1024053774/design-integrity-guardrails@behavioral-acceptance-review -g -y
npx skills add a1024053774/project-map-skill@project-map -g -y
npx skills add a1024053774/architecture-flow-map-skill@architecture-flow-map -g -y
npx skills add a1024053774/document-writing-skill@document-writing -g -y
npx skills add a1024053774/frontend-less-ai-tone-skill@frontend-less-ai-tone -g -y
npx skills add a1024053774/same-visual-family-skill@same-visual-family -g -y
```

The machine-readable catalog is [`skills.json`](skills.json). Keep this index limited to links,
metadata, and install coordinates; changes to Skill behavior belong in the canonical source repo.

## Local checkouts and the skill hub

When you develop the Skills locally, keep one checkout per source repository under one folder
(default `~/Documents/SKILLS/<repository>`) and use `~/.agents/skills` as the hub. Codex, Cursor,
Gemini CLI, and Factory read the hub directly; Claude Code reads only `~/.claude/skills`, so it gets
links into the hub. [`scripts/sync_skills.py`](scripts/sync_skills.py) reconciles this layout from
`skills.json`:

```bash
python3 scripts/sync_skills.py            # dry run: print the link changes
python3 scripts/sync_skills.py --apply    # apply them
```

It links catalog Skills from your checkouts into the hub, mirrors the hub into `~/.claude/skills`,
and removes symlinks in hub-reading directories that would list a Skill twice or that are broken.
Real directories are only reported, never moved. Edit `MIRRORS` and `HUB_READERS` at the top of
the script if your harness set differs.

## Instruction budget check

A long `SKILL.md` buries its rules, so each Skill keeps `SKILL.md` short, opens it with the
non-negotiable core, and moves phase-specific detail into `references/` behind a one-line link.
[`scripts/check_skill_budget.py`](scripts/check_skill_budget.py) checks the parts of that contract a
script can check:

```bash
python3 scripts/check_skill_budget.py                         # every catalog Skill under ~/Documents/SKILLS
python3 scripts/check_skill_budget.py ../grilling-skill/grilling   # one Skill folder
python3 scripts/check_skill_budget.py --max-bytes 10240       # a different budget
python3 scripts/check_skill_budget.py --since HEAD --allow rewrites.txt   # also report text lost since HEAD
bash tests/check_skill_budget_e2e.sh                          # acceptance run against fixture Skills
```

| Check | Fails when |
| --- | --- |
| `size` | `SKILL.md` is over `--max-bytes` (default 8192: the files of 9 KB and up were the ones that needed restructuring, those of 3–5 KB were fine), or over the Skill's own `maxBytes` in `skills.json` when it has one. `grilling` has 11264: its question types, map format, and asking rules are used every round, so moving them to `references/` would only make each round reread them |
| `frontmatter` | there is no frontmatter, `name` is not the folder name, or `description` is empty or over 1024 characters |
| `orphan` | a file under `references/` is not linked from `SKILL.md` itself, by a Markdown link or a code span holding its path |
| `link` | a relative Markdown link (inline, image, or reference definition) points at nothing |
| `escape` | a relative link leaves the Skill folder, which is all an install copies |
| `anchor` | a `#fragment` into a Markdown file names no heading there (GitHub slugs, with `-1`, `-2` for duplicates) and no HTML `id` |
| `lost` | with `--since REV`: a sentence, list item, table row, or code line that `SKILL.md` and `references/*.md` held at `REV` no longer appears as a whole unit, so `Never push to main` turned into `Never push to main unless …`, or `run the tests.` into `never run the tests.`, is reported |

Links are read from `SKILL.md`, `references/**/*.md`, and the Markdown files `SKILL.md` links to;
link text may wrap across lines. Fenced code, inline code, HTML comments, footnotes, and URLs with a
scheme are skipped. Each Skill prints its size and the number of lines before its first `##`
heading, where the core should be. The exit code is 1 when any Skill fails or a catalog Skill has
no local checkout.

`lost` reports every rewrite, including deliberate ones. Review each line; when the rule now lives
elsewhere in other words, copy the reported text (everything after `lost: <file>: `) into the
`--allow` file as one line. A fragment of it does not count.

What it cannot tell you:

- **Misses.** Whether the opening lines really are the core, and whether moved detail is really
  phase-specific. Bytes are a proxy for tokens, and per byte CJK text costs more tokens than
  English, so the budget is lenient for Chinese Skills. HTML `<a href>` links, paths written only
  in backticks, and external URLs are not checked; only `references/` is checked for orphans.
  `lost` compares only `SKILL.md` and `references/`, matches text rather than meaning, and accepts
  a finished sentence that survives verbatim even if a new sentence after it weakens it. A code
  span opened in one list item and closed in the next can hide a link between them.
- **False alarms.** Anchors in setext headings, or in headings with `_emphasis_`, letter-like
  symbols (Ⅻ, Ⓐ), an entity inside inline code, or non-ASCII capitals, can slug differently from
  GitHub. Links in indented (four-space) code blocks are checked. A reference
  reached only through another reference counts as an orphan, because references stay one level
  deep. A link out of the Skill folder fails even when the Skill is only used inside its repository.
  Text moved out of `references/` into another file, or an unpunctuated item merged into a
  sentence, is reported by `lost` and needs an `--allow` line.

## Integration options

This index uses a catalog model: independent repositories plus one discovery layer. It is the
least coupled option and works well when Skills have different release cadences.

Use Git submodules when you need a pinned, checkoutable bundle for a specific project or workshop.
Use a monorepo only when the Skills share code, tests, or a release process and you are willing to
version them together. Do not mirror the same `SKILL.md` in both an index and a source repository;
that creates two competing sources of truth.

## License

MIT. See [LICENSE](LICENSE).
