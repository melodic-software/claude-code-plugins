# Upstream source — mattpocock/skills

Single source of truth for everything in this marketplace derived from
[mattpocock/skills](https://github.com/mattpocock/skills) (Matt Pocock, "AI Skills for Real
Engineers", MIT). Provenance lives HERE and in plugin CHANGELOGs — never in skill bodies, where
it is agent-facing noise. Content citations an agent actually uses (e.g. the Fowler smell
baseline in `review`) are not provenance records and stay in place.

**Last audited upstream state:** v1.2.3, `main@84fdeff` (this repo's audit: the
`pocock-skills-v12-sync` topic). Git history of this file records *when*; this line records only
*what was audited*.

**Recheck trigger:** a mattpocock/skills release whose changeset names any skill in the
attribution table below — re-audit the affected row(s). Release notes name skills explicitly
(`gh release view <tag> -R mattpocock/skills`).

## Attribution table

| Upstream skill / source | Ours | Relation | What was taken / rejected |
|---|---|---|---|
| `to-questionnaire` (Productivity; graduated from in-progress in v1.2.0 #593) | `planning:questionnaire` | Derived | Interview-the-send invariant kept; output relocated cwd → topic-docs memory slice (PII); grill→interview vocabulary; tracker-item option added. Re-audited against v1.2.3: no delta — his graduation commit is a 100%-similarity rename, his one body change (template XML-ification) is already reflected in our template, and ours is otherwise a superset (route-away, overwrite guard, role-slug multi-recipient) |
| `wayfinder` | `planning:wayfind` | Partial | Fog-of-war framing + ticket-vs-fog (sharpness) distinction; REJECTED file-based map (native tracker primitives instead) and upstream tracker seam. v1.2 re-audit: ADOPTED parallel research burn-down (work-mode exception + chart-mode offer) and the in-chart no-fog bail-out; "decision ticket" term present as our "decision item" (parity under work-items vocabulary); REJECTED `research/<name>` branch (two-lane branch-naming prohibition; resolution comments + memory tier already home the findings); map-clears handoff already present-stronger (named graduation targets) |
| `batch-grill-me` / `grilling` rounds | `planning:interview` (propagated to `prd`/`design`/`plan`) | Derived (behavior) | Frontier-rounds model, facts-vs-decisions split, confirmation gate; no-grill vocabulary constraint; background fact sub-agents. v1.2 re-audit: ADOPTED ❓/➡️ emoji anchors as opt-in `userConfig` (`use_emoji_question_markers`, default off; decoration of the single verdict marker); answer-by-number dictation and any-order answering confirmed already present; REJECTED one-question-at-a-time opt-out line (his seam is the consumer's own global CLAUDE.md — platform-native, nothing for the plugin to ship) |
| grilling-family rework (upstream PR #532) | `planning:interview`, `architecture:improve` | Partial | decision-tree rename, domain-routing, primitive-vs-variant boundary; ADR 3-gate + glossary purity are house additions |
| `git-guardrails-claude-code` (misc) | `guardrails` `block-dangerous-git` hook | Derived (capability only) | Capability adopted; substring-matching implementation REJECTED wholesale (false-blocks) — house argv-grammar parser instead |
| upstream PR #464 (review checklist) | `review` code-reviewer Fowler baseline | Pointer | Surfaced the idea; content re-derived from Fowler, *Refactoring* 2nd ed. ch. 3 — no upstream phrasing |
| upstream issues #186/#306/#617/#482 (handoff failures) | `session-flow` handoff claim-provenance + constraint re-scan rules | Derived (failure corpus) | Two rules adopted from incident threads; rest rejected (verdicts on issue #1477) |
| `triage` | `work-items:triage` | Influence (phrasing) | "A PR is an item with attached code" ≈ upstream's "a PR is an issue with attached code"; state-machine framing convergent. Recorded for honesty; no structured port |
| `to-tickets` | `work-items:decompose` | Influence (vocabulary) | Vertical-slice / tracer-bullet decomposition vocabulary overlaps upstream; mechanics are house-built on the work-item seam |
| `improve-codebase-architecture` YAGNI scoping filter (v1.2 #533) | `architecture:improve` deepening Phase 1 | Partial | ADOPTED scope-before-scanning: user-named direction scopes the scan, else recent-commit hot spots pull attention first (precomputed context widened to 20 commits). REJECTED his `CONTEXT.md` reference (our glossary-discovery ladder) and HTML-report machinery (previously rejected) |
| `diagnosing-bugs` (v1.2.3 Redact + tagged logs) | `debugging:debug`, `testing:diagnose` | Partial | ADOPTED the redaction guard in both skills (secrets `<REDACTED>` before any shown command/output/artifact; env-var credentials; signal-lines-only quoting) and the `[DEBUG-a4f2]` tagged-log convention in `testing:diagnose` (already present in `debugging:debug`). TRACKED, not adopted: feedback-loop-first doctrine (10 ranked loop types, 3–5 ranked hypotheses) — our phase structures work; re-evaluate on a release whose changeset names `diagnosing-bugs` |
| `wait-what` (Productivity, NEW in v1.2 #751) | `discipline:wait-what` | Derived | Ported near-verbatim (one-sentence re-pitch body: back up, add missing context, ASD-STE100 register + inline gloss, ubiquitous language) as a declared non-corrector species in `discipline` beside `tighten-your-output`/`mind-your-maxims` — home chosen on the blame axis (the drift is the model's output, not the user's comprehension). Name KEPT with an explicit PLUGIN-PHILOSOPHY naming-exception entry (utterance-is-mechanism + upstream muscle-memory parity; a 5-generator/3-judge naming tournament's grammar-clean winner `re-pitch` was declined by the user). REJECTED his fixed `CONTEXT.md` filename (our format-externalized glossary discovery: nearest glossary per consumer convention, silent degradation). Shape evidence: his X thread (status 2084753070437609606 → 2084941367659168064 → 2085681281795232026) — the same instruction failed as passive global CLAUDE.md AND as an output style; only the on-demand skill works, so the register text lives in the body, invoked at the moment of loss |
| ask-matt `PHASE-BOUNDARIES.md` (v1.2) | `session-flow:workflow` continuation router + `context-guard` zones | Convergent / rejected | Tree audited element-by-element at parity or stronger (ordered first-yes-wins router, compact-last-with-steering, boundary-only trigger; ours adds clean-stop, user-gated background, instrumented zones, worker relay). ADOPTED one zone-gated criterion: prefer continue when the next stage consumes this stage's reasoning verbatim. REJECTED "handoff only for what travels" narrowing (contradicts our fork-beats-compaction stance) and the ~150k smart-zone figure (self-declared-debated folklore; no official numeric threshold exists — our measured bands stand, his dictionary entry noted as one more folklore anchor) |

## Not adopted (decided, with reasons)

`ask-matt` router (marketplace shape differs), `setup-matt-pocock-skills` (we configure via
`userConfig` + consumer docs), `teach` (education plugin covers), `migrate-to-shoehorn` /
`scaffold-exercises` / `setup-pre-commit` (personal/low-value), writing-beats/-fragments/-shape
(out of scope), Codex `agents/openai.yaml` sidecars (no Codex target). The v1.2 behavior deltas
(owned-skill lane) and the `wait-what` port are closed — outcomes in the attribution table
above. Open evaluations are tracked in the topic plan
(`docs/topics/pocock-skills-v12-sync/PLAN.md` lanes): `wizard` and the infra subset
(version-sync drift check, `.out-of-scope/` KB, "It's working if" sections,
writing-for-agents cross-pollination).

## Harness findings learned from this upstream (recheck-worthy)

- **Upstream issue [#693](https://github.com/mattpocock/skills/issues/693):** Claude's desktop
  and web surfaces drop user-invoked skills from the skill listing. Affects OUR user-invoked
  skills on those surfaces too. Recheck when that issue changes state.
- **Codex dual-harness gotcha (upstream v1.2.2, PR #766):** `policy.allow_implicit_invocation:
  false` in an `agents/openai.yaml` sidecar hides a *model-invoked* skill from Codex entirely —
  the policy line belongs only on user-invoked skills. Relevant only if we ever target Codex.

## Map

Full verified 35-skill upstream↔ours map (relations, v1.2 deltas, drift findings):
[`docs/topics/pocock-skills-v12-sync/his-ours-map.md`](../topics/pocock-skills-v12-sync/his-ours-map.md).
