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
| `to-questionnaire` (Productivity; graduated from in-progress in v1.2.0 #593) | `planning:questionnaire` | Derived | Interview-the-send invariant kept; output relocated cwd → topic-docs memory slice (PII); grill→interview vocabulary; tracker-item option added |
| `wayfinder` | `planning:wayfind` | Partial | Fog-of-war framing + ticket-vs-fog (sharpness) distinction; REJECTED file-based map (native tracker primitives instead) and upstream tracker seam |
| `batch-grill-me` / `grilling` rounds | `planning:interview` (propagated to `prd`/`design`/`plan`) | Derived (behavior) | Frontier-rounds model, facts-vs-decisions split, confirmation gate; no-grill vocabulary constraint; background fact sub-agents |
| grilling-family rework (upstream PR #532) | `planning:interview`, `architecture:improve` | Partial | decision-tree rename, domain-routing, primitive-vs-variant boundary; ADR 3-gate + glossary purity are house additions |
| `git-guardrails-claude-code` (misc) | `guardrails` `block-dangerous-git` hook | Derived (capability only) | Capability adopted; substring-matching implementation REJECTED wholesale (false-blocks) — house argv-grammar parser instead |
| upstream PR #464 (review checklist) | `review` code-reviewer Fowler baseline | Pointer | Surfaced the idea; content re-derived from Fowler, *Refactoring* 2nd ed. ch. 3 — no upstream phrasing |
| upstream issues #186/#306/#617/#482 (handoff failures) | `session-flow` handoff claim-provenance + constraint re-scan rules | Derived (failure corpus) | Two rules adopted from incident threads; rest rejected (verdicts on issue #1477) |
| `triage` | `work-items:triage` | Influence (phrasing) | "A PR is an item with attached code" ≈ upstream's "a PR is an issue with attached code"; state-machine framing convergent. Recorded for honesty; no structured port |
| `to-tickets` | `work-items:decompose` | Influence (vocabulary) | Vertical-slice / tracer-bullet decomposition vocabulary overlaps upstream; mechanics are house-built on the work-item seam |

## Not adopted (decided, with reasons)

`ask-matt` router (marketplace shape differs), `setup-matt-pocock-skills` (we configure via
`userConfig` + consumer docs), `teach` (education plugin covers), `migrate-to-shoehorn` /
`scaffold-exercises` / `setup-pre-commit` (personal/low-value), writing-beats/-fragments/-shape
(out of scope), Codex `agents/openai.yaml` sidecars (no Codex target). Open evaluations are
tracked in the topic plan (`docs/topics/pocock-skills-v12-sync/PLAN.md` lanes): `wait-what`,
`wizard`, and the v1.2 behavior deltas.

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
