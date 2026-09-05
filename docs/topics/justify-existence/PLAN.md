# justification

Topic slug: `justify-existence`. Branch: `claude/justify-existence-skill-interview-lsgmkq`.
Contract written by `/planning:interview` on 2026-09-05; the ledger is `.work/justify-existence/interview-checklist.md`.

## Brief

### TLDR

- New single-skill plugin **`justification`**, category `quality`, handle **`/justification:audit <target>`**.
- Points at any artifact at any granularity (repo, folder, file, CI pipeline, feature or design, ADR, comment, one line) and asks: was there a stated reason for this, and is that reason still valid today?
- Read-only. Reports first, then discusses with the operator; hands the discussion to `/planning:interview` when it needs structure. Never applies a remedy; remedies route to the skills that already own them.
- Verdicts use the `overengineering` §6 ladder verbatim (KEEP / RETIRE / DOWNGRADE / CONSOLIDATE / UNPROVEN, FLAG-FOR-HUMAN cap) plus one delta: every row carries an evidentiary-basis tag (`measured` / `class-inferred` / `unexamined`).
- Evidence is tiered and auto-escalating (git, then forge, then consumer-specific sources); unreachable tiers are named in the verdict, never silently skipped; when not sure, it asks the operator for external context.

### Goal

Give the operator a pointed, portable instrument that makes any artifact justify its existence against the two-part test the operator stated: a reason existed when it was built, and that reason still holds today. The failure it exists to reverse is accreted output approved as a wall of text and now carried at cost (the operator's term: AI slop). The outcome is a report the operator can act on with confidence, where a retirement claim has paid for itself with evidence and a retention claim is visibly labelled by how much evidence actually supports it. The remedy is refactor or remove, decided by the operator after discussion; the skill's job ends at the report and the conversation it opens.

### Constraints

- **ADR 0018 clause 2.** No cross-plugin path citation into `overengineering`'s private files. The shared scrutiny method is vendored into `plugins/justification/` and registered in `scripts/cross-plugin-source-registry.txt` so `check-cross-plugin-source-drift.sh --check` gates drift (ADR 0019).
- **Enforcement-layer targets route, presence-gated.** When the target is a hook, gate script, CI lane, branch protection or similar, the finding routes to `/overengineering:audit` if that plugin is installed; the inline fallback is recorded in the finding, not silent.
- **Two gates, reported separately.** The ablation rubric (`docs/PLUGIN-PHILOSOPHY.md` "Classifying a hook", durable tier exempt) and the ADR 0003 precision bar (no class exemption) are independent. A verdict row states which gate it answers. A fused verdict is a defect.
- **Retire costs more than keep.** A RETIRE row names where the search looked and what a counterexample would look like, and is refused when the search was a single document or a single query form.
- **Absence checks vary the query form** (line wrap, hyphenation, casing, synonyms) before "not found" becomes a finding. A single-form grep is not a search.
- **Check for a sanctioning ADR and a maintaining gate before calling any pattern debt.** The canonical negative case is `lib/hook-utils.sh`: 17 byte-identical copies sanctioned by ADR 0019 and actively maintained by a CI drift gate.
- **Read-only on the target.** Writes go to the memory tier (`.work/`) or a findings artifact per the repo's detector-findings convention; never to the audited artifact.
- **No repo-wide sweep.** A bare invocation follows the fallback ladder in the acceptance criteria; it never enumerates the repository.
- **Portable.** Satisfies `docs/PLUGIN-PHILOSOPHY.md` "Design boundary": no dependence on this organization's paths, names, forge, or MCP servers. Consumer-specific evidence tiers are discovered from the consumer's own CLAUDE.md, installed MCP servers, and tool search.
- **One skill.** The no-target discovery behaviour is a mode of `audit`, not a sibling. Listing entry must survive `skill-quality:check listing-budget`.
- **House prose style.** No em dashes in SKILL.md, README, or plugin manifests; `/ai-slop:audit` clean.
- **Repo process.** `scripts/affected-tests.sh --run` before push; PR opened as draft; PR body satisfies `.claude/rules/pr-body-contract.md`; announce to the five sibling sessions before opening the PR (coordination protocol in the ledger).
- **Files this lane does not touch:** `docs/PLUGIN-PHILOSOPHY.md`, `lib/hook-utils.sh` and its copies, `plugins/*/hooks/**`, `docs/conventions/hook-*`, `scripts/check-*.sh`, `docs/adr/**` without prior announcement.

### Acceptance criteria

- `plugins/justification/` exists with `.claude-plugin/plugin.json`, `skills/audit/SKILL.md`, `README.md`, `CHANGELOG.md`, and `skills/audit/evals/evals.json`; `.claude-plugin/marketplace.json` carries the entry with `"category": "quality"`; `docs/CATALOG.md` is regenerated with the repo's own tooling.
- `skill-quality:check justification` passes; `skill-quality:check listing-budget` does not regress.
- `/justification:audit <file>` on a named artifact produces a report in which every verdict row carries: one of the six §6 tokens; an evidentiary-basis tag from `measured` / `class-inferred` / `unexamined`; the evidence tiers consulted with each marked reachable or unreachable; and, for RETIRE, the search locations and the counterexample shape.
- `/justification:audit` with no target does not sweep. It uses conversation context if any exists; otherwise offers git-history discovery of old, low-churn candidates; otherwise asks the operator. The chosen branch is stated in the output.
- With `overengineering` installed, an enforcement-layer target produces a finding whose `Routed-to` names `/overengineering:audit`; with it absent, the same target produces an inline finding that records the absence.
- The vendored method file is listed in `scripts/cross-plugin-source-registry.txt` and `scripts/check-cross-plugin-source-drift.sh --check` passes.
- SKILL.md carries a Boundary section naming, by slash handle, the incumbents it defers to: `overengineering:audit`, `code-tidying:audit-dead-code`, `code-tidying:dissolve-comments`, `code-tidying:audit-comment-residue`, `docs-hygiene:audit-derivability`, `docs-hygiene:audit-noise`, `claude-config:audit-instructions`, `claude-config:unhobble`, `claude-ops:audit-native-overlap`, `improvement:find`; and the scrutiny pairing `discipline:reason-dont-recite`, `discipline:recheck-against-upstream`, `discipline:scrutinize-dont-coast`.
- `evals/evals.json` includes at least these cases: (a) the `lib/hook-utils.sh` 17-copy vendoring is NOT reported as debt; (b) the 20-of-20 hook-bearing-plugins case is NOT reported as 20 violations (14 are hooks plus their own setup skill; only 6 bundle unrelated skills); (c) a RETIRE row without named search locations is rejected; (d) a fused verdict that does not name its gate is rejected; (e) a bare invocation does not enumerate the repository.
- When the operator's answer to an evidence-tier question is "I don't know", the item is recorded UNPROVEN with the tier named, not resolved either way.

### Captured assumptions

- The operator's phrase "don't make videos" was a dictation slip for: do not conclude an artifact is unjustified merely because its justification is not in the repository. Revisit if the operator corrects the reading.
- Findings conform to the repo's detector-findings convention (`docs/conventions/detector-findings/`), as `provenance` and `overengineering` already do, with the inline report first per the operator's Q8 answer. Revisit if the convention proves a poor fit for per-row evidentiary-basis tags.
- ADR 0003's precision bar governs the no-target discovery mode, because that mode emits candidates over a corpus. Discovery mode ships only after a check on this repository reports its candidate count and how many the operator confirmed as real. Revisit if discovery mode is cut from V1.
- The `overengineering` §6 ladder tokens are stable enough to adopt verbatim. Revisit if `overengineering` changes its ladder; the vendoring sync gate will surface that as drift.
- V1 is attended-only, derived from the operator's answers to Q7 ("if not 100% sure, ask") and Q8 ("report first, then discuss"). See Q15.
- `justification` is the plugin name; the operator accepted it over the working name `justify-existence`. Revisit if the handle `/justification:audit <target>` reads wrongly in use.

### Out-of-scope

- Applying any refactor or removal. Remedies route to existing appliers.
- A repository-wide sweep in any mode.
- An unattended or dispatched run mode (deferred, Q15).
- A pre-creation corrector ("before you add that, justify it"). That is a different skill wearing the same name; if wanted later it is a `discipline` corrector.
- Comment-specific logic. `code-tidying:dissolve-comments` and `audit-comment-residue` own that ground; this skill defers to them.
- Editing `docs/PLUGIN-PHILOSOPHY.md` or writing a new ADR in this lane without prior announcement to the sibling sessions.
- A `realign`-style applier sibling.

### Deferred questions

- Q15: Should `/justification:audit` support an unattended or dispatched run mode (recording UNPROVEN and OPEN-INTENT instead of asking)? Defer until V1 has shipped and been used attended at least once. **Arbiter: USER-RESERVED** (an unattended mode changes the acceptance criteria above; `/planning:plan` proposes, the operator resolves).

## Plan

<empty; populated by /planning:plan>
