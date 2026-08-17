# AI Hero course — core-lane decision record (lanes 3–5)

Interim decision record for the course's original six-lane contract's remaining discussion
lanes (3 compaction, 4 plan-mode, 5 grilling parity), run as a session chain on
`claude/pocock-steering-course-00zkvd` (restarted from the default branch after the steering
chain merged). Lane 6
([#2904](https://github.com/melodic-software/claude-code-plugins/issues/2904)) harvests these
rows into `docs/upstream/aihero-course.md` (its deliverable) and dissolves this file then —
the same graduation contract as the sibling steering record
(`docs/upstream/aihero-steering-lanes.md`).

Contract rules apply unchanged (`docs/topics/pocock-course-lanes/PLAN.md`, branch
`claude/plan-mode-discussion-55kszx`): interview-first per lane, claim ladder, lanes discuss
and decide but do not implement. Harness-behavior citations below reference the contract's
durable C1–C9 verdict table ("Harness-claims verdicts", verified 2026-08-17).

## Lane 3 — compaction doctrine (#2901, closed 2026-08-17)

Interview: 1 round, 5 questions, register gate clean (5/5), user confirmed. **Parity lane —
zero work items filed**; the known context-guard doc drift was already filed (#2973).

| Claim / concern (lesson) | Verdict | Detail |
|---|---|---|
| Steered compaction as the default continuation mechanism; compact-before-QA as its ideal case | REJECT | QA over a compaction summary grades the summary (secondary evidence), never the work — exactly what context-guard's PostCompact evidence-degraded marker encodes; boundary validation routes to a fresh-context subagent (our shipped phase-verifier pattern), which his own phase-boundaries lesson concedes. Marker affirmed UNCHANGED — no boundary-timed carve-out (a hook cannot observe intent, and a conditional marker stops being evidence) |
| `/compact [instructions]` steering exists and is useful | CONFIRMED (C6) — for continuation only | Acknowledged as real (docs-verified); legitimate for steering an intentional between-phases compact while the window is still fresh (`session-flow:handoff` "Fork beats compaction" doctrine unchanged); never a QA substrate |
| "If auto-compact fires, something went wrong" (diagnostic half) | ADOPT (anchor phrase) | Convergent with context-guard's design: the zones exist to act before auto-compact fires; a firing = a missed boundary. Recorded as framing anchor, not a number |
| "The human owns the boundary" / disable auto-compact (prescriptive half) | REJECT | Unattended cloud/autonomous sessions have no human at the boundary; the licensed version is the instrumented ladder — observable zones → advisory injection → opt-in blocking gate (grace budget, handoff-path always writable). Auto-compact stays enabled as the last-resort safety net; a degraded continuation beats a hard stall |
| Compaction "seeds a fresh session" | REFUTED (C4) | Same session continues over a structured summary; only fork/`--fork-session` makes a new session ID. Our doctrine already states the mechanism correctly — no doc change |
| Messages queue during compaction | TRACK (C5, UNDOCUMENTED) | Never taught until cured; named Tier-0 cure: live interactive-session probe. Trigger: official docs documenting the behavior, or the cure being run |
| Transcript = primary source, compaction summary = secondary source | ADOPT (vocabulary) → lane 6 | Convergent with the save-point engine's lossless-transcript-vs-model-visible-conversation rule; term pair routed to #2904's adoption list (already a candidate there) |

## Lane 4 — plan-mode (#2902)

*(pending)*

## Lane 5 — grilling parity (#2903)

*(pending)*
