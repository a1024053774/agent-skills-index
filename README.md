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
  — route structural risk findings through a bounded review.
- [`behavioral-acceptance-review`](https://github.com/a1024053774/design-integrity-guardrails/tree/main/behavioral-acceptance-review)
  — audit whether tests, evals, and user-visible workflows provide independent evidence.

Source repository: [design-integrity-guardrails](https://github.com/a1024053774/design-integrity-guardrails)

### Agent acceptance

- [`agent-acceptance-testing`](https://github.com/a1024053774/agent-acceptance-testing-skill/tree/main/agent-acceptance-testing)
  — plan, execute, and judge evidence-backed acceptance cycles for any model-driven Agent product.

Source repository: [agent-acceptance-testing-skill](https://github.com/a1024053774/agent-acceptance-testing-skill)

### Decision grilling

- [`grilling`](https://github.com/a1024053774/grilling-skill/tree/main/grilling)
  — stress-test a plan or decision in rounds while persisting the decision tree and current frontier.

Source repository: [grilling-skill](https://github.com/a1024053774/grilling-skill)

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
npx skills add a1024053774/agent-acceptance-testing-skill@agent-acceptance-testing -g -y
npx skills add a1024053774/frontend-less-ai-tone-skill@frontend-less-ai-tone -g -y
npx skills add a1024053774/same-visual-family-skill@same-visual-family -g -y
```

The machine-readable catalog is [`skills.json`](skills.json). Keep this index limited to links,
metadata, and install coordinates; changes to Skill behavior belong in the canonical source repo.

## Integration options

This index uses a catalog model: independent repositories plus one discovery layer. It is the
least coupled option and works well when Skills have different release cadences.

Use Git submodules when you need a pinned, checkoutable bundle for a specific project or workshop.
Use a monorepo only when the Skills share code, tests, or a release process and you are willing to
version them together. Do not mirror the same `SKILL.md` in both an index and a source repository;
that creates two competing sources of truth.

## License

MIT. See [LICENSE](LICENSE).
