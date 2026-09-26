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

## Integration options

This index uses a catalog model: independent repositories plus one discovery layer. It is the
least coupled option and works well when Skills have different release cadences.

Use Git submodules when you need a pinned, checkoutable bundle for a specific project or workshop.
Use a monorepo only when the Skills share code, tests, or a release process and you are willing to
version them together. Do not mirror the same `SKILL.md` in both an index and a source repository;
that creates two competing sources of truth.

## License

MIT. See [LICENSE](LICENSE).
