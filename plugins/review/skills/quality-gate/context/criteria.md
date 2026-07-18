# Criteria reference mode

Loads review criteria as contextual reference. Reference mode, not action mode — it provides criteria; you apply them.

## When to use

- Before starting any review mode, to refresh on what matters
- When unsure what to check for a specific type of change
- Combined with `self` mode for a thorough, informed self-review

## How to use

1. **Resolve the project's standards index first.** Criteria resolution goes through the standards convention: jump to the "Resolution ladder" section of the plugin's contract binding [`${CLAUDE_PLUGIN_ROOT}/reference/standards-contract.md`](${CLAUDE_PLUGIN_ROOT}/reference/standards-contract.md) and follow it — the ladder is not restated here. Match the change's surfaces against the index's `Applies when` clues and read the matched standards files selectively (the sections relevant to this change). The project's other review documentation — a `REVIEW.md` at the repo root, a `review/` or `docs/review*` directory, review sections in `CLAUDE.md` or contributing guides — is an **inference source inside that ladder** when no index exists, not the primary. Tolerant reader: a version-skewed index degrades to best-effort routing per the binding; a broken index row is surfaced with an offered fix (Boy Scout) — never skipped silently.
2. **Baseline when the ladder yields nothing.** Use `${CLAUDE_PLUGIN_ROOT}/context/severity.md` for severity vocabulary, plus the universal checklist baked into this plugin's `code-reviewer`, `security-reviewer`, and `architecture-guardian` agent definitions (completeness, consistency, convention compliance, security, dependency direction).

## Applying criteria to changes

1. **Identify changed file types** — languages, config, docs
2. **Identify the change's nature** — new feature, refactor, bug fix, config
3. **Select applicable criteria** — not every concern applies to every change
4. **Check each applicable item** against the actual changes
5. **Report findings** using the severity vocabulary in effect (project's, else baseline)

Respect the project's documented skip list when one exists (generated code, lock files, build-enforced style rules) — do not re-review what tooling already enforces.
