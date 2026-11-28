---
standards-contract: 1.2.0
---

# standards

Prose standards that tooling cannot enforce: the reasoning-only tier of this catalog. Where `components/` owns executable policy and its contract tests, `standards/` holds judgments a human or agent makes: engineering conventions, code-review criteria, and operational process standards. The split between the two is itself a convention. See [engineering/enforceability-tiers.md](engineering/enforceability-tiers.md).

Three concerns live here:

- **[engineering/](engineering/)**: the standards a contributor follows while writing: philosophy, architecture and design, domain modeling, naming, simplicity, code organization, and the source-of-truth disciplines.
- **[review/](review/)**: the criteria a reviewer applies to a change: code quality, architecture, error handling, concurrency, performance, security, cross-platform, observability, testing, AI-generated code, and thin per-stack overlays.
- **[process/](process/)**: the operational standards for how work is tracked and moved; [process/README.md](process/README.md) lists them.

## How this is consumed

Prose is read, not executed. A reviewer or an authoring agent reads these files; no tool walks the directory tree to find them, apart from the standards index below. That makes the distribution model deliberately simple and decoupled:

- **Adopt by copy or by pointer.** `engineering/` and `process/` are copy-or-pointer only: a consuming repo either copies the files it adopts into its own tree, or points its contributor and review guides at this directory, and either way there is **no runtime coupling** to this repo: nothing there is fetched or imported at build time. The one read at review or authoring time is the org layer below. A copy carries the back-link and drift-check requirement in [`../distribution/governance-process.md`](../distribution/governance-process.md).
- **The indexed files are read from `main`.** The files the [standards index](#standards-index) lists are the org layer of the standards contract that planning, review and filing skills read; a repository keeps only its own additions in its `docs/standards/`. Those files use absolute URLs for every link, since a consumer reads them outside this tree.
- **`review/` additionally supports native reference.** A consuming repo's `REVIEW.md` can cite a heading in this tree, and a self-hosted or local review running the `review` plugin follows that citation into a pinned `standards` checkout mounted via `--add-dir`, depth that genuinely is fetched at review time. While `standards` is public that mount is an anonymous checkout open to any consumer, public or private; what stays forbidden is mounting *private* content into a repo whose review output is more widely readable than that content ([`../distribution/REVIEW-CREDENTIAL.md`](../distribution/REVIEW-CREDENTIAL.md)). `REVIEW.md` itself (`../REVIEW.md`) states the mechanism and its severity crosswalk in full; this is a pointer, not a restatement of it.
- **Curate on adoption.** These are agent-agnostic standards. A consumer wires them into whatever harness it uses (a contributor guide, a review checklist, an agent's instructions) without this catalog dictating that harness. Adopt the files that fit; the standards do not assume a particular toolchain, repository layout, or agent.
- **Single owner, no double-statement.** Where a component config or hook lane already enforces a convention, prose references that enforcement rather than restating the rule, keeping executable policy the one source of truth.

## Standards index

This file is the team-layer index of the standards contract in
`melodic-software/claude-code-plugins` (`docs/contracts/standards/`), found through
[`../.claude/standards.yaml`](../.claude/standards.yaml). A repository whose
`docs/conventions/source-control.yaml` names `standards_repository: melodic-software/standards`
reads it from `main` as its org layer, beneath its own `docs/standards/`. Each `File` resolves
relative to this directory.

| Surface | Applies when | File |
|---|---|---|
| bulk-mutation | a command or sweep that creates, deletes, or changes many objects; background or unattended runs; work spanning several targets | engineering/bulk-mutation.md |
| concise-prose | writing or reviewing any prose: docs, comments, commit messages, PR bodies, replies | engineering/concise-prose.md |
| configuration-switch-naming | naming or reading an environment variable, CI, organization or repository variable, or settings key that turns a behavior on or off | engineering/configuration-switch-naming.md |
| design-for-change | designing or reviewing a module boundary, an extension point, configuration, dependency wiring, or a design pattern; any change whose reversal would edit many files | engineering/design-for-change.md |
| deterministic-work-execution | counts, diffs, sorting, arithmetic, inventories; composing shell commands an agent runs | engineering/deterministic-work-execution.md |
| documentation-and-citations | citing upstream docs; recording an external default or version; labeling the basis of a recommendation | engineering/documentation-and-citations.md |
| filing-prs-and-issues | opening a pull request or filing an issue: the title rule, body sections, linkage line, issue fields per type, and the routing labels | process/filing-prs-and-issues.md |
| issue-tracker | filing, titling, triaging or closing an issue; adding, renaming or deleting a label, issue field or milestone; choosing labels versus fields | process/issue-tracker.md |
| reference-dont-duplicate | a fact, value, or rule appearing in more than one place; origin or history notes in code or docs | engineering/reference-dont-duplicate.md |
| simpler-code | writing or reviewing code; proposing a new check, process, document, or dependency; serializing work; keeping an existing mechanism | engineering/simpler-code.md |
| source-authority-tiers | grounding a recommendation, option, or decision; judging how much a source is worth | engineering/source-authority-tiers.md |

## Changing a normative file

A change to a rule another file cites or assumes needs the cross-doc
reconciliation step in
[`../distribution/governance-process.md`](../distribution/governance-process.md)
before it merges, not after.

## On testing this directory

These files carry no fixtures or unit tests, by nature: a reasoning-only standard has no pass/fail a script can assert. What *is* mechanically verified is that the prose itself passes the repository's Markdown, spelling, EditorConfig, and link-integrity policies.
