# Criteria reference mode

Loads review criteria as contextual reference. Reference mode, not action mode — it provides criteria; you apply them.

## When to use

- Before starting any review mode, to refresh on what matters
- When unsure what to check for a specific type of change
- Combined with `self` mode for a thorough, informed self-review

## How to use

1. **Project criteria first.** Look for the project's own review documentation — a `REVIEW.md` at the repo root, a `review/` or `docs/review*` directory of per-concern criteria, review sections in `CLAUDE.md` or contributing guides. Read the hub file, then the per-concern files relevant to the change.
2. **Baseline when the project has none.** Use `${CLAUDE_PLUGIN_ROOT}/context/severity.md` for severity vocabulary, plus the universal checklist baked into this plugin's `code-reviewer`, `security-reviewer`, and `architecture-guardian` agent definitions (completeness, consistency, convention compliance, security, dependency direction).

## Applying criteria to changes

1. **Identify changed file types** — languages, config, docs
2. **Identify the change's nature** — new feature, refactor, bug fix, config
3. **Select applicable criteria** — not every concern applies to every change
4. **Check each applicable item** against the actual changes
5. **Report findings** using the severity vocabulary in effect (project's, else baseline)

Respect the project's documented skip list when one exists (generated code, lock files, build-enforced style rules) — do not re-review what tooling already enforces.
