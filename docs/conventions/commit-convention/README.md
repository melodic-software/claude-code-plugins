# Commit-convention enforcement seam

Owner doc for the machine-readable **enforcement** read of a consumer's commit-subject /
PR-title convention. This concern is consumed by **more than one plugin** — `source-control`
authors and drafts against the convention, `guardrails` gates against it — so its ownership lives
here at marketplace level, not inside either plugin, per
[`docs/MIGRATION-PLAYBOOK.md`](../../MIGRATION-PLAYBOOK.md) "concern-named config consumed by >1
plugin". A guardrails hook cites **this** doc, never `plugins/source-control/reference/`.

## Two reads of one file

The convention lives in the consumer's tracked `.claude/source-control.md` (H2-per-key markdown),
resolved across three layers by the model per
[`source-control/reference/config-resolution.md`](../../../plugins/source-control/reference/config-resolution.md).
That document owns **drafting** resolution — how `/source-control:commit` and `/pull-request`
compose a compliant subject/title. This seam owns the **enforcement** resolution — how a
zero-dependency hook decides whether an *already-formed* subject/title is allowed.

The two reads are deliberately not identical:

| | Drafting (config-resolution.md) | Enforcement (this seam) |
|---|---|---|
| Reader | the model | a bash hook (`[[ =~ ]]` / `grep -E`) |
| Layers read | all three (user-global, team, local), per-key merge | **team-tracked only** (`${REPO_ROOT}/.claude/source-control.md`) |
| Fallthrough | CLAUDE.md/rules/hook, then bundled CC default | **none** — unresolved means no enforcement |
| Dialect | any (the model interprets PCRE) | POSIX ERE only (normalized/rejected) |

## The parse contract

`lib/resolve-convention-pattern.sh` is the single source of truth. Given a repo root and a key
(`subject_pattern` or `pr_title_pattern`) it emits an ERE regex on stdout, or nothing.

1. **Value grammar.** The value is the **first non-empty body line** under the `## <key>` H2 in the
   team-tracked file. (The surface already constrains machine-relevant keys to exactly one value —
   never a list.)
2. **`Conventional Commits` keyword** expands to the one canonical ERE the resolver owns —
   `^(feat|fix|docs|style|refactor|perf|test|build|ci|chore|revert)(\(.+\))?!?: .+` — so the model's
   interpretation and every hook's regex cannot drift.
3. **`pr_title_pattern` deferral** — the literal `` Same as `subject_pattern`. `` resolves the
   effective subject pattern instead.
4. **Regex dialect = POSIX ERE — accepted or rejected, never translated.** The enforcement value
   must already be POSIX ERE (write `[0-9]`, not `\d`). Translating PCRE→ERE by string rewriting is
   unsound — bracket expressions, POSIX classes, and escaped backslashes all break naive
   substitution — so the resolver does not attempt it. Any PCRE-only construct — a `(?...)` group
   (non-capturing, lookaround, named), or any backslash-letter/digit escape (`\d \w \s \D \A \t \1`
   …) — makes the pattern **non-enforceable**: the resolver emits nothing, writes a one-line
   diagnostic to stderr, and the gate no-ops. A value that does not compile as ERE is likewise
   non-enforceable. This keeps enforcement predictable and impossible to mistranslate; the model's
   *drafting* side may still author PCRE-shaped patterns, but a team that wants a pattern *enforced*
   writes it in ERE.

## Two load-bearing contracts

- **Unresolved = no enforcement.** No team-tracked pattern (or a non-enforceable one) → the gate does
  nothing. A gate never blocks against the bundled Conventional Commits default: CC is not a
  lane-1-eligible default (see [`docs/PLUGIN-PHILOSOPHY.md`](../../PLUGIN-PHILOSOPHY.md) "Two-lane
  convention posture"), so gating an un-opted-in repo against it would impose a convention the
  consumer never chose. **Enforcement strength = strength of explicit team config.**
- **Policy-floor via team-only reads.** Enforcement reads the **tracked** team layer only; the
  user-global and gitignored `*.local.md` overlays are drafting inputs a blocking gate never
  consults. This is the floor *by construction* — a personal/gitignored file cannot weaken what the
  gate enforces because the gate never looks at it, and "is regex A stricter than B" is undecidable,
  so no merge could honor a "tighten-only" rule anyway. A user wanting a stricter personal gate
  tightens team policy via PR; a looser personal preference is a drafting choice, never an
  enforcement bypass.

## Consumers

- `guardrails` CC-layer content gate (#914) and opt-in `commit-msg` hook (#919) source the vendored
  copy of the resolver; each registers its path in `scripts/sync-resolve-convention-pattern.sh` and
  bumps the guardrails manifest so consumers receive the change.

Naming coincidence recorded per the seam rules: the convention file is `.claude/source-control.md`
after the concern (delivery workflow), not the plugin. The plugin-name collision is incidental; the
file is not renamed.
