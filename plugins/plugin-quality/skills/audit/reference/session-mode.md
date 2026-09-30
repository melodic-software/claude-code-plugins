# Session mode, arm, evidence bar, research gate, review seams

The bulk behind the short pointers in [`../SKILL.md`](../SKILL.md). Every entry here feeds the
existing pipeline; none adds a step.

## Contents

- [Entry rules](#entry-rules)
- [`arm`](#arm)
- [`session`](#session)
- [Evidence bar](#evidence-bar)
- [Research gate](#research-gate)
- [Review seams by role](#review-seams-by-role)

## Entry rules

- `session` and `arm` run only when the operator types them. No hook starts either, no schedule
  does, and the model never selects one. A model that judges a session worth the pass says so in
  one line and waits; it does not run the mode.
- Each is a whole argument. Beside any other token, stop and name the accepted set
  (`<plugin>[:<component>]`, `session`, `arm`); never guess which one was meant.
- Nothing here changes step 6. An unattended `session` run falls to rung 4 like any other
  unattended run.

## `arm`

Run at session start. It audits nothing.

1. If `<plugin-data-dir>/armed/<session_id>.json` already exists, report it and stop before any
   launch; never start a second observer for one session. `<plugin-data-dir>` and `<session_id>`
   resolve exactly as the evidence packet's layout resolves them.
2. Invoke `/session-flow:running-retro arm` when the session-flow plugin is installed. Absent:
   say the observer cannot be armed here and stop. Do not build a substitute observer.
3. When the launcher reports the observer armed, write that file with `armed_at` (UTC),
   `session_id`, and the launcher's one-line result verbatim. The directory sits beside
   `evidence/`, never under it, so retention and the resume rule never read it as a packet.
4. If the launcher reports it did not arm, write nothing and relay its message.

The observer files its findings into the session's running-retro ledger only after the session
ends, so a `session` run inside the live session does not find them from the observer.

## `session`

Run at session end, over what the session used.

1. **Locate the parser (reuse, no second parser).** `parse_transcript.py` is owned by
   `/session-flow:retro`. It sits at `skills/retro/scripts/parse_transcript.py` inside the
   session-flow plugin. Find the installed copy by searching the installed plugins for that
   relative path under a `session-flow` directory (the install layout is Claude Code's, so this
   states no path), taking the highest version when several match, and confirm it with
   `<python> <path> --help` (exit 0; the parser needs Python 3.10+).
   No hit, or a non-zero exit: say the parser is absent and stop; the operator can still run
   `/plugin-quality:audit <plugin>:<component>` by name.
2. **Parse this session.** `<python> <path> <session_id> <session-data-dir>`, with the session
   data directory resolved as `/session-flow:retro` "Paths" resolves it. Read
   `data.plugin_usage`: `skills` maps `<plugin>:<skill>` to an invocation count, from the
   model's Skill tool calls and the operator's typed `/<plugin>:<skill>` commands. Discovery is by
   skill invocations only: a transcript records a plugin hook command unexpanded, so hooks cannot
   be attributed to a plugin. A missing `plugin_usage` key means the found parser predates it: say
   so and stop.
3. **Build the list.** One row per used skill (`<plugin>:<skill>`, count), ordered by count. Drop
   this audit's own row unless the operator adds it back. A plugin whose hooks ran but whose
   skills did not is added by hand at the confirm step.
4. **Confirm.** Show the list and wait: the operator removes rows, adds targets by hand, or
   accepts. An empty confirmed list ends the run with "nothing to audit". The list is never
   applied unconfirmed while an operator is present.
5. **Feed the pipeline.** The confirmed list is the resolved target list of the SKILL's Target
   resolution: one packet per target, steps 1 to 3 per target, steps 4 to 6 once over the union.
   When the session's running-retro ledger (found by `session_id`) exists, add it to each
   target's step-1 evidence as a source of transcript excerpts. An armed observer writes it only
   after the session ends, so a run inside the live session has it only from an in-session
   `/session-flow:running-retro` checkpoint. The audit never waits for the ledger and never
   fabricates one; without it the evidence is the transcript itself.

Unattended, the discovered list stands as the confirmed list. Record it in `evidence.md` as
auto-resolved with its source (the parser run), the same treatment step 4 gives a safe default.

## Evidence bar

A candidate finding is fileable only when a session artifact backs it: a report the component
printed, an exit code, or a transcript excerpt, saved in the packet and cited by file. A
reproduction the auditor ran and saved counts (its output and exit code are the artifact). These
do not count alone: a doc citation, the auditor's reading of the source, an opinion, a
recollection of what happened.

A candidate without one is **unfiled**. Record it in `contract.md` under `## Unfiled`, one row per
candidate: the candidate, the reason no artifact backs it, and the artifact that would qualify it.
Tell the operator in the step 3 presentation. An unfiled candidate is never emitted, in any sink,
at any confidence. It re-enters step 3 only when an artifact is obtained (for example a reproduction
run in this session) and saved to the packet.

## Research gate

Every load-bearing claim in the item carries a `research:` line in the ledger
(`reference/categories.md`); a claim without a checked tier record is stated as an open question.
A suggested change (a remediation the item proposes, as opposed to a defect it reports) also
carries a readiness label, decided at step 4:

1. Run `/discovery:research` on the change when the discovery plugin is installed: the question is
   whether current authoritative sources support the change.
2. Record the result in the item under `## Research`: each source with its tier as the research
   pass assigns it, its URL, the fetch date, and whether it supports or dissents. Do not restate
   the tier definitions; the research skill owns them.
3. Only a change with that section filled gets `agent-ready`. Every other change gets
   `needs-decision`. Research absent, declined, or empty means `needs-decision`. The audit never
   assigns `agent-ready` on its own judgment.

The two label names are this repository's readiness vocabulary. Where the target repository names
its states differently, use its equivalent for each and keep the rule.

## Review seams by role

Step 5's role seams are named by what they do, never by a fixed list. Resolve each at run time by
matching the role against the skills this session actually lists (the in-context listing, or
`/session-flow:show-options` for the untruncated catalog). Report the resolved skill, or the
fallback, in the step 5 seam-resolution line. A skill that fills a role by a different name still
fills it.

| Role | What it asks of the write-up | Absent fallback |
|---|---|---|
| Adversarial re-examination | A fresh-context pass tries to refute each finding blind to how it was reached | A fresh subagent re-derives each finding from its cited artifact and reports which did not reproduce |
| Upstream conformance | Each claim about harness or upstream behavior matches current official docs | The auditor's own step 2 per-topic doc check is the only conformance check; the write-up says so |
| Adaptation chapter for the running model | The suggested changes fit current guidance for the model this session runs on | Skip; the write-up notes that no model-specific guidance was consulted |
| Scope challenge | Each suggested change is asked whether it needs to exist and whether a smaller one covers it (the overengineering audit) | One line per change in the item answering those two questions |

These seams follow the effort rows: they run at `high` and above and are skipped below it, with the
write-up saying so. The zone table decides where they run.
