# Upstream source: AI Hero course lessons (Matt Pocock)

Provenance record for everything in this marketplace vetted against the AI Hero course lessons
(Matt Pocock's course on working with coding agents). This is a distinct source from the
[mattpocock/skills](https://github.com/mattpocock/skills) repository, whose record is the SSOT at
[mattpocock-skills.md](mattpocock-skills.md): the course is prose lessons with no releases, tags,
or changelogs, so it needs its own recheck regime. Where a lesson restates something the skills
repo also ships, the row cites both bases.

Vetting ran as six lanes on the `pocock-course-lanes` contract
(issues [#2899](https://github.com/melodic-software/claude-code-plugins/issues/2899) through
[#2904](https://github.com/melodic-software/claude-code-plugins/issues/2904)). Lanes decide but
never implement: every ADOPT row points at a filed work item; changes execute through the normal
pipeline.

## Row schema (fixed at creation, per amendment A2)

Each row is a four-part record per
[docs/conventions/upstream-drift/README.md](../conventions/upstream-drift/README.md): the claim,
the basis it was derived against, the as-of date, and a recheck trigger. Columns:

| Lesson claim | Ours | Verdict | Reasoning, basis, as-of |

Verdicts: **ADOPT** (with the filed work item), **REJECT** (with reason), **TRACK** (on a named
event), **COVERED** (already present at parity or stronger, with evidence).

**Recheck trigger, all rows (fixed at creation):** divergence at re-fetch. A read-time re-fetch
of the row's basis (the lesson text, or the upstream artifact the row cites) finds the source no
longer matching the record; the divergence, never the lookup, fires the row, and a firing follows
the upstream-drift maintenance procedure. A row may state a stronger trigger inline; bare "when
the lesson updates" is not a valid trigger form here because the course publishes no observable
update signal.

## Lane 1: handoff (issue #2899, decided 2026-08-17)

Basis for all lane 1 rows: the course handoff lesson as captured in the lane contract
(`docs/topics/pocock-course-lanes/PLAN.md`, 2026-08-17) plus upstream
`skills/productivity/handoff/SKILL.md` read live at `068b6e0` (2026-08-17). Our side read live
the same day: `plugins/session-flow/skills/handoff/SKILL.md`,
`plugins/session-flow/reference/save-point.md`, `plugins/session-flow/reference/structure.md`
(exploration verified by a fresh-context agent, 14/14 sampled claims confirmed).

| Lesson claim | Ours | Verdict | Reasoning, basis, as-of |
|---|---|---|---|
| Handoff serves crossing boundaries: another agent, another repo, a colleague, a forked side task | `session-flow:handoff` "When to invoke" list; "sharing state with another session or machine" bullet | **ADOPT** (as a union) | User decision (#2899 comment 1): our dominant session-chain use (dumb-zone escape, session-ID chain, retrospective reconstruction) is named first-class ALONGSIDE his taxonomy, not instead of it; the deliverable is explicit routing signals for which form to use when. Filed: [#2956](https://github.com/melodic-software/claude-code-plugins/issues/2956). As-of 2026-08-17 |
| A single purpose argument ("What will the next session be used for?") tailors the doc to the next session's focus | No purpose argument; surface is `[file\|prompt] [topic]`; intent lives in the verbatim Original goal section | **ADOPT** | Shape decided in-lane: optional trailing free text `[file\|prompt] [topic] [purpose...]`; tailors emphasis only (Resumption brief lead, Suggested skills selection, Remaining-actions order); never drops sections; never alters the resume-prompt shape (find-handoff detection contract); Original-goal immutability wins on conflict. Filed: [#2955](https://github.com/melodic-software/claude-code-plugins/issues/2955). As-of 2026-08-17 |
| Save the handoff to the OS temp directory, not the current workspace | `<memory_dir>/handoffs/` (default `.work/handoffs/`), memory tier, self-gitignored | **REJECT** | Placement is load-bearing for us: retro's `previous_handoff` chain-walk, find-handoff recovery, and the cross-machine origin line all depend on workspace placement; OS-temp volatility is the failure class upstream's own corpus hit (temp-sweep in mattpocock/skills#306 context, durability ask in #482). His self-cleaning benefit is replaced by user-controlled removal. Confirms the #1477 finding-4 verdict (PR #1560). As-of 2026-08-17 |
| Lifecycle: temp placement self-cleans, so files never accumulate | Accumulation by design ("Multiple handoffs accumulate in the directory, fine", structure.md); nothing expires files | **REJECT** (silent expiry) | User decision (#2899 comment 1): handoffs stay primarily ephemeral in a location we control; cleanup is user-controlled removal, never silent expiry or OS cleanup. Retention is load-bearing (chain-walk, recovery, carry-forward), which is the recorded #1477 finding-4 rationale (issue comment 5084364831); this lane confirms rather than reverses it. Promote-content-never-file rule and worktree caveat filed: [#2956](https://github.com/melodic-software/claude-code-plugins/issues/2956). As-of 2026-08-17 |
| Do not duplicate content captured in other artifacts (specs, plans, ADRs, issues, commits, diffs); reference by path or URL | Partial: "Summarize; never transcribe" (File roles), "reference it rather than restating" (Decisions); no general rule | **ADOPT** | User decision (#2899 comment 1): state the general rule explicitly in the skill body, mirroring upstream's wording; explicit over implicit. Filed: [#2956](https://github.com/melodic-software/claude-code-plugins/issues/2956). As-of 2026-08-17 |
| Include a suggested-skills section naming what the next agent should invoke | Suggested skills is a mandatory section of the handoff structure | **COVERED** | Present at parity or stronger (presence-gated per-skill suggestions, structure.md mandatory section set). As-of 2026-08-17 |
| Redact sensitive information (API keys, passwords, PII) | Mandatory redaction step with the git-remote-userinfo strip exception | **COVERED** | Ours is the more specified form of the same rule. As-of 2026-08-17 |
| `disable-model-invocation: true`: only the user triggers a handoff | Model-invocable under strict trigger discipline (instrument signal, observed drift, user report; never self-estimated budget) | **REJECT** | User decision (round 5): proactive "we should hand off now" prompting is wanted, and instrument-triggered forks plus skill-to-skill reach (his own invocation-reach invariant makes user-only skills unreachable from other skills) depend on model invocation. Token cost of carrying triggers acknowledged and accepted. Known gap: the zone instrument is statusline-teed and silent in cloud/headless sessions, filed as [#2957](https://github.com/melodic-software/claude-code-plugins/issues/2957). As-of 2026-08-17 |
| A handoff skill needs only ~15 lines | Three-layer engine (skill, shared save-point engine, structure doc) | **REJECT** | The engine's size is accumulated incident response, not up-front design: claim provenance and constraint re-scan from his own failure corpus (#1477, PR #1560), loop re-arm (#1447/#1515), rooted resume paths (#1780), Original-goal immutability (#1906), background-continuation disambiguation (#2115). Our minimal tier already exists as prompt-only mode (writes no file, documented retro-gap cost). As-of 2026-08-17 |

House decisions recorded alongside the rows (not lesson claims): the worktree caveat (a handoff
written inside a worktree dies with `git worktree remove`; acceptable only when the worktree
completes as a merged PR unit) and the promote-content-never-file rule (durable value is promoted
into committed artifacts; no handoff file is ever committed). Both in
[#2956](https://github.com/melodic-software/claude-code-plugins/issues/2956).

## Lanes 2 through 5

Rows land here as each lane closes: phase boundaries (#2900), compaction doctrine (#2901),
plan mode (#2902), and interview parity (#2903).

## Coverage index and consolidation

Owned by lane 6 ([#2904](https://github.com/melodic-software/claude-code-plugins/issues/2904)):
the per-lesson coverage index mapping every claim to its disposition, dictionary-term adoption,
and final consolidation of this document.
