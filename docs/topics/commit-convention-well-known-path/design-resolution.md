# Design resolution — commit-convention well-known path + config-cascade rename

Locks the architecture decision for melodic handoff-inbox item
`20260723-163434-source-control-setup-convention-default-and-config-surface` (F1–F4), plus the two
adjacent concerns it surfaced (a seam rename and a fleet provenance question). Design-before-code
artifact; the implementation follows the phased plan at the end.

## Problem

`/source-control:setup`'s neutral commit-convention SSOT (`convention_source`, shipped in #1141 /
source-control 0.23.0) landed as an **opt-in pointer target with markdown-H2 still primary**. The
pointer lives as a `## convention_source` H2 *body line* inside `.claude/source-control.md` — a file
authored for a model, so:

- **F2 (config surface).** Every non-plugin consumer (commit-msg hook, CI, another agent) must
  markdown-parse `.claude/source-control.md` to discover the path — three reads across two files,
  one of them prose. No native config surface names the convention file (verified: 0.23.0 manifest
  has 29 userConfig keys, none names a convention file).
- **F3 (fragility).** Any agent tidying `.claude/source-control.md` (`revise-claude-md`, a `.claude/`
  tidier) can silently drop the H2 pointer. Resolution then fails **closed** (enforcement no-ops) or
  drafting falls back to markdown/CC — correct behavior, but with **no signal** until a commit is
  unexpectedly blocked or allowed. `setup check` surfaces no drift.
- **F1 (default steer).** Setup defaults to markdown-primary and positions the neutral SSOT as
  "offer when it earns its keep" — steering *away* from the tool-agnostic file exactly in the mature
  repos (a second enforcement consumer exists) that most benefit from it.
- **F4 (taste).** The neutral-YAML preamble template is heavier than it needs to be.

The pointer feeds **two** resolution surfaces, verified: enforcement
(`lib/resolve-convention-pattern.sh`, read by the guardrails gate) and drafting
(`plugins/source-control/reference/config-resolution.md`, read by `/commit` + `/pull-request` +
`/setup`). Any precedence change must land identically on both or they diverge.

## Decision

**Principled option (b): a well-known default neutral path, defaulting to the marketplace's own
dogfooded `docs/conventions/<concern>/` layout, with `convention_source` retained as a relocation
override.**

For commit-convention the well-known default is `docs/conventions/source-control/commit-convention.yml`
— the exact path the demanding consumer (SW2030) chose. Resolution precedence, **mirrored across
both surfaces**:

```
1. explicit convention_source pointer          (relocation override — path stays repo-owned)
2. well-known docs/conventions/source-control/commit-convention.yml   (the default — read ONE file)
3. markdown-H2 in .claude/source-control.md     (legacy / back-compat, per key)
```

Once a neutral file is resolved (via 1 or 2), the existing fail-closed contract applies unchanged —
a present-but-broken neutral file disables enforcement with a diagnostic rather than silently
re-reading markdown a migration may have retired. A key the neutral file omits still falls back to
the markdown H2 (per-key). Absent all three → today's behavior (inference / CC default), full
back-compat, zero action for existing consumers.

This keeps **both** values the earlier b′/b deliberation isolated:

- b′'s value — the pointer survives, so a repo that wants the file elsewhere keeps *path ownership*
  (precedence rung 1). The fragility F3 targets is closed for the common case because the default
  no longer requires a pointer at all.
- b's value — the common case reads **one** self-describing, tool-agnostic file with zero markdown
  parse and zero indirection (precedence rung 2).

### Why this passes the re-anchor disciplines

- **reuse-or-replace.** `docs/conventions/<concern>/` is *this marketplace's own* established layout
  for convention concerns. A consumer adopting it reuses the established shape rather than standing
  up a parallel one. The rejected alternatives — a bespoke pointer dotfile (b′) or a `.claude/`-scoped
  default — were both inventions of a *new* location.
- **recheck-against-upstream.** The consumer-config-layering seam currently mandates `.claude/<name>`,
  but `standards` already deviates to `docs/standards/` (precedence ratified #649; location observed,
  not yet ruled). A `docs/`-rooted config location has precedent — this generalizes it, not invents.
- **reason-dont-recite.** This reopens the commit-convention seam's V1 "no well-known search / path
  stays repo-owned" decision. Both recorded V1 reasons are engaged, not overridden by fiat: reason
  (i) "no consumer demanding it yet" is now void (163434 is the demanding consumer); reason (ii)
  probe-order/shadowing + path-ownership is bounded by a fixed 3-rung precedence and preserved by
  retaining the pointer as rung 1.
- **point-dont-copy.** The neutral file stays the single SSOT; the well-known path is a *probe*, not
  a copy. Tool-agnosticism is preserved because `docs/conventions/` is a plain docs path a non-Claude
  CI check or hook reads directly (unlike a `.claude/`-scoped default).

### Rejected alternatives

- **b′ alone (relocate pointer to a bespoke dotfile).** Invents a new location; keeps the indirection
  and a 3rd tracked file; addresses fragility but not read-burden. Superseded by principled-b, which
  keeps the pointer (b′'s only durable win) *and* removes the indirection for the common case.
- **(a) a userConfig key naming the file.** Per-user/per-machine, invisible to CI and a fresh-checkout
  hook — cannot be the team-tracked source. Not pursued even as a supplement (no demand).
- **Defer F2 structurally (detection-only).** Cheapest, but leaves the silent-severance window open
  and does not deliver the read-one-file consistency the operator asked for.

## Scope and sequencing

Cross-cutting; delivered PR-by-PR, source-control first. codebase-health (the only other markdown-H2
config surface) and the provenance audit are tracked follow-ups, not folded in — cramming them would
violate the clean/well-thought bar.

### Phase 1 — source-control well-known path + F1/F3/F4 (closes 163434)

- `docs/conventions/commit-convention/README.md` — record the well-known default + 3-rung precedence;
  update the V1 "no well-known search" note to the reopened decision with both reasons engaged.
- `lib/resolve-convention-pattern.sh` — pointer resolution gains rung 2 (well-known default) between
  the explicit pointer and the markdown fallback. Safety + fail-closed contract unchanged.
- `plugins/guardrails/hooks/resolve-convention-pattern.sh` — synced byte-identical via
  `scripts/sync-resolve-convention-pattern.sh`; guardrails manifest version bumped (forced by the
  `--check-bump` CI gate at `ci.yml:296`).
- `plugins/source-control/reference/config-resolution.md` — drafting side gains the same 3-rung
  precedence (identical to enforcement).
- `plugins/source-control/skills/setup/reference/apply-convention.md` — F1: recommend the neutral
  SSOT as the default when a second enforcement consumer is detected; default the neutral file's path
  to the well-known location (write `convention_source` only on relocation). F4: trim the YAML
  preamble to a 1–2 line header.
- `plugins/source-control/skills/setup/SKILL.md` — F3: `check` gains drift probes (explicit pointer
  target missing; well-known file present but markdown-H2 also sets keys → shadow warning).
- Tests: `lib/resolve-convention-pattern.test.sh` — well-known-default resolution, precedence order,
  fail-closed on broken well-known file, back-compat (no neutral → markdown).
- Version bumps + CHANGELOG for source-control and guardrails.

### Phase 2 — rename `consumer-config-layering` → `config-cascade`

Mechanical docs rename (~15 citations) via `docs-hygiene:rename-references`; record the `docs/`-location
pattern the standards deviation already set. Name chosen via `naming:name-it-better` (blind 3-lens
fan-out): `config-cascade` — "cascade" is the one established term of art that natively carries both
per-key override and a ratified precedence-inversion (CSS `@layer`/`!important`), matching the
user→team→local + policy-floor model.

### Tracked follow-ups (own issues, not this effort)

- **codebase-health** — migrate the second markdown-H2 config surface to the same structured
  first-class layered shape.
- **Provenance audit** — the operator does not recall ratifying `consumer-config-layering`; it and
  its sibling `docs/conventions/*` seams accreted through agent-authored auto-merged PRs (#692, #649,
  #925…). Audit which seams were human-ratified vs agent-accreted before further building on them.

## Risks and mitigations

- **Shadowing (well-known file present + markdown-H2 also set).** Bounded by the fixed 3-rung
  precedence; surfaced by the F3 `setup check` shadow-warning probe.
- **Two-surface drift.** Enforcement and drafting must implement identical precedence — covered by
  a resolver test asserting the order and a config-resolution.md doc that states the same 3 rungs.
- **Unintended enforcement from a stray well-known file.** The path is specific enough
  (`docs/conventions/source-control/commit-convention.yml`) that its presence is intentional; and
  enforcement only fires when the resolved neutral file carries `subject_pattern` (opt-in by
  construction).
- **Fresh-docs mandate.** WebFetch the plugins-reference / skills / hooks pages and cite before the
  plugin edits; version bumps are plain semver.
