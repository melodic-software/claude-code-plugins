---
description: "Write a mid-session save-point for /clear-and-resume — a durable handoff file (default) or a copy-paste resume prompt when follow-ups are small. Use when: 'handoff', 'save state', 'checkpoint this', 'pause', 'come back later', the user reports the session is heavy, a context-measuring mechanism says to fork, or your own responses are visibly drifting, repeating, or looping. Never on your own estimate of the remaining window — a budget reading is not a decay signal. For delegating the continuation to a background agent, use the sibling continue-in-background skill."
argument-hint: "[file|prompt] [topic] [purpose...] (e.g., /handoff, /handoff prompt, /handoff file phase-3 review the design with the team)"
user-invocable: true
disable-model-invocation: false
shell: bash
metadata:
  workflow-stage: session
  summary: Write a mid-session save-point for clear-and-resume
---

## Context — gather first

Take `session-id`, `branch`, `status`, and `recent-commits` at `-5`. Probe commands, the
one-command-per-call and treat-failure-as-unknown rules, and the `$`-expansion rationale — which bit
this skill hardest, failing it at load in exactly the isolated sessions that most need a save-point:
[`${CLAUDE_PLUGIN_ROOT}/reference/gather.md`](${CLAUDE_PLUGIN_ROOT}/reference/gather.md).

## Purpose

Context bloat is expensive and quality degrades as context rots. When a task has room left but the
session should fork anyway, capture a save-point — a handoff document, or just a copy-paste resume
prompt when follow-ups are small — and `/clear`.

**What licenses that judgment matters as much as the judgment.** The trigger is the user's own
report, an instrument that measures the window, or visible decay in the responses themselves —
never a self-estimated budget. A remaining-context reading is a measurement, not a decay signal;
volunteering a handoff on the strength of one interrupts work that was fine.

Based on the canonical pattern Anthropic recommends for the `/clear` workflow: put the rest of the
plan in a handoff file; explain what you tried, what worked, and what didn't, so the next agent with
fresh context can load that file and nothing else. The save-point captures a *snapshot* of in-flight
state — including the approaches already ruled out — so the next session doesn't waste effort
rediscovering dead ends.

This skill delivers the save-point for a MANUAL resume: the user `/clear`s and pastes the resume
prompt themselves. To hand the resume prompt to a fresh background agent that continues the task
now, use the sibling `/session-flow:continue-in-background` skill instead — same save-point engine,
different delivery.

## Arguments

`$ARGUMENTS` carries `[file|prompt] [topic] [purpose...]` — all optional and positional:

- **Method** (`file` | `prompt`) — recognized ONLY as the first token. `file` forces the full
  durable handoff; `prompt` forces prompt-only. Omitted → auto-detect (engine doc, "Choosing the
  path").
- **Topic** — short kebab slug for the filename. When the first token is not a method keyword it IS
  the topic (`/session-flow:handoff phase-3`); with a method present it is the second token. Omitted → inferred
  from context.
- **Purpose** — everything after the topic token is optional natural-language purpose text
  answering "what will the next session be used for?" — no quoting, no new syntax, and
  invocations without it parse exactly as before. What purpose is allowed to change (emphasis
  only) and what it may never touch is owned by the engine doc ("The purpose argument tailors
  emphasis only"); parse it from `$ARGUMENTS` in place, never pre-compute.

## Hard rule — handoff ALWAYS terminates current execution

**The whole point of `/session-flow:handoff` is `/clear` + fresh-session resume.** The skill produces the
save-point, THEN STOPS. It does NOT keep executing the underlying task in the current session; that
defeats the purpose. STOP is the default and near-universal outcome — NEVER unlocked by the user
having listed multiple steps, nor by the remaining work being "small".

**Mandatory STOP gate (walk every box):**

- [ ] Path chosen (full vs prompt-only) per the engine doc
- [ ] Copy/paste resume prompt emitted between two dashed rails (engine doc, "Emit the copy/paste
  resume prompt")
- [ ] `/clear`-then-paste instruction surfaced to the user
- [ ] **STOP.** No further work items, no next phase, no follow-on skill, no commit/push. The
  session ends as far as the task is concerned

**NOT authorization to continue (these all STOP):**

- A multi-step pipeline naming `/session-flow:handoff` (e.g. "handoff, then verify, then PR") → the listed steps
  run in the FRESH session AFTER `/clear`. Naming `/session-flow:handoff` names a `/clear` boundary, not a waiver
- "do all of it" → authorizes executing the phases across the session chain, but each `/session-flow:handoff`
  between them still enforces its `/clear` boundary (that is WHY the handoffs get written)
- A standalone user-invoked `/session-flow:handoff` → always STOP, regardless of surrounding instructions

The only exception: the user's prior turn used explicit stay-in-session language about handoffs
specifically (e.g. "don't `/clear` between phases, keep going").

## When to invoke

- Mid-task and the user reports the session is heavy, or a context-measuring mechanism says to
  fork (`context-guard`'s zone report is one) — never your own estimate of the remaining window
- Quality degrading (context rot) — responses drifting, repeating, or looping. This is the signal
  that is yours to read, because decay shows up in the output and never in a budget number
- Extending the session chain — the deliberate escape-and-resume cadence (save-point, `/clear`,
  fresh session) whose handoff files carry the `session_id`/`previous_handoff` chain that
  `/session-flow:retro` later walks for retrospective reconstruction. A first-class use this
  skill owns, not a byproduct of the others
- About to pause for hours/overnight; want a clean resume
- About to switch to a different task; this one isn't done
- Last turn had an unexpected compaction
- Crossing a boundary — handing the work to a colleague, another repository or checkout, or
  another agent, or forking a mid-phase side task into its own session
- Sharing state with another session or machine

### Routing signals — which form to use when

| Situation | Route |
|---|---|
| Deep-window escape with session-chain value | Full handoff file — the default |
| Small follow-ups, no chain value | Prompt-only — accepting its documented retro-gap cost (no file, no chain pointer for `/session-flow:retro` to walk) |
| The next session's focus differs from this one's | Either form, plus the purpose argument (emphasis tailoring only, per the engine doc) |
| Going AFK but the work should keep moving | The sibling `/session-flow:continue-in-background` skill — only on the user's explicit request |
| The machine itself may go away | `/session-flow:clean-stop` semantics — make everything durable off-machine first; a save-point alone is a local file that strands with the machine |
| Crossing a boundary (colleague, other repo, other agent) | Full file, plus the purpose argument, plus the `Handoff origin:` line the full path's resume prompt already carries — the line the other side re-resolves the file from |

## Fork beats compaction when the window is deep

This section picks between two continuation mechanisms; it never licenses the continuation itself.
That licence comes from "When to invoke" above, and the thresholds here apply only once it is
granted.

Two ways to keep going past a heavy context: fork (handoff file + `/clear` + fresh session) or
continue in place over a compacted history. Compaction suits an intentional break between phases
while the window is still mostly fresh — the summarized turns were genuinely disposable. Once the
session has consumed enough of its context window that reasoning quality degrades — roughly beyond
the final third of the window — fork instead: a handoff file carries forward exactly the state that
matters, chosen deliberately, while a compaction summary carries forward whatever the summarizer
happened to keep, and the degradation that prompted the move rides along into the continued
session. Judge the threshold by window position and response quality, never by a fixed token count
— it shifts with model and configuration.

## Reference other artifacts; promote durable value — never commit the file

**Do not duplicate content captured in another artifact.** Content that already lives in a spec,
plan, ADR, issue, commit, or diff is referenced by path or URL, never restated in the save-point.
The engine's per-section guidance ("Summarize; never transcribe" in the structure doc's file-roles
section) is this rule applied locally; it holds across the whole save-point, on both paths.

**Promote the content, never the file.** When a handoff carries durable value — a decision, a
constraint, a finding worth keeping beyond this task — promote that substance into a committed
artifact (a topic contract, an issue, a PR body) and reference it from there. The handoff file
itself stays ephemeral and is never committed. Cleanup of the `handoffs/` directory remains
user-controlled removal — nothing expires, sweeps, or ages these files out silently.

## Produce the save-point

The save-point machinery — destination resolution, locating the position, full-vs-prompt-only
choice, the mandatory redaction pass, the handoff-file write, and the rails resume prompt — lives
in the shared engine doc
[`${CLAUDE_PLUGIN_ROOT}/reference/save-point.md`](${CLAUDE_PLUGIN_ROOT}/reference/save-point.md).
Walk it top to bottom; do not restate or improvise any of its steps.

## Delivery: `/clear`-then-paste

This skill's delivery step is the engine's default exit: the rails resume prompt with the
"`/clear`, then copy everything between the dashed lines" instruction above the top rail. The user
types `/clear` and pastes; nothing is launched on their behalf.

## Post-write enforcement checklist

Tick each item in the response so the user can verify the exit shape. Missing any tick = handoff
incomplete. Known failure patterns live in `context/gotchas.md` — load on demand when a step feels
ambiguous.

**Full path:**

- [ ] Position located + next stage named (fresh reads this turn)
- [ ] Handoff file written to the handoff location (self-ignore guard verified first) with
  frontmatter per the engine's structure doc (`${CLAUDE_PLUGIN_ROOT}/reference/structure.md`)
- [ ] `previous_handoff` present IF this session continued a prior handoff's task (chain continuity
  per the same structure doc); omitted otherwise — including when the directory holds only
  unrelated-task handoffs. When present, that file was opened from disk THIS turn and its
  `Original goal` quote and amendments copied over unchanged — never rebuilt from the conversation
- [ ] `Original goal` carries the user's goal in their own words, quoted with its date — not a
  paraphrase and not the process serving it — and the drift-check sentence tying the next action
  back to it is answered (structure doc, "Original goal")
- [ ] Completion criteria read as goal-states, each keeping the command or diff that settles it;
  process milestones sit under the subordinate sub-heading, never as criteria
- [ ] Every body section the structure doc defines is present — walked from that doc this turn, not
  written from memory; a section with nothing to report says so explicitly rather than being omitted
- [ ] Claim provenance applied — inherited status marked `UNVERIFIED (<source>)`, not stated as
  plain fact (engine doc, "Claim provenance")
- [ ] Redaction pass swept the file AND the prompt (secrets/tokens/credentials/PII replaced with
  shape markers)
- [ ] TaskList captured with literal recreate calls in the environment section, from a live
  `TaskList` call this turn (OR an explicit statement that there is nothing to recreate)
- [ ] Purpose text (when the invocation carried any) applied per the engine doc's tailoring
  rules — the Resumption brief leads with it, Suggested skills are selected for it, Remaining
  actions are ordered by it where free; no section dropped, resume-prompt shape untouched, and a
  goal-conflicting purpose flagged rather than obeyed. No purpose given → nothing to tick
- [ ] Resume prompt emitted between dashed rails, `@`-referencing the file by its **absolute**,
  forward-slash-normalized path — never the bare `<memory_dir>/handoffs/…` segment, which resolves
  against the resuming session's cwd — with the `Handoff origin:` line naming the repository
  (a remote URL with its userinfo credential stripped) and repo-relative path a different machine
  re-resolves from; copy instruction above
  the top rail; `/goal` first line if a goal is active; a below-the-rails note re-arming EVERY
  surviving loop — one `/loop [<interval>] <original prompt>` line per loop, each its own follow-up
  message (engine doc, "Emit the copy/paste resume prompt")
- [ ] **EXECUTION STOPS HERE**

**Prompt-only path:**

- [ ] Prompt-only justified (all auto-detect criteria hold, OR `prompt` explicitly passed)
- [ ] The verbatim goal sits between the rails above the remaining-work bullets — below an active
  `/goal` first line, which it never displaces — and when the goal has recorded amendments, the
  original dated quote travels with EVERY dated amendment line, never collapsed to a single line;
  prompt-only writes no file, so the goal travels in the prompt or not at all (engine doc,
  "Original goal — mandatory on BOTH paths")
- [ ] Claim provenance applied to every inline remaining-work bullet — inherited status marked
  `UNVERIFIED (<source>)`, not stated as plain fact (engine doc, "Claim provenance")
- [ ] Redaction pass swept the prompt (secrets/tokens/credentials/PII replaced with shape markers)
- [ ] Purpose text (when the invocation carried any) travels inline as the `Purpose:` line below
  the goal quote and above the remaining-work bullets (engine doc, "The purpose argument tailors
  emphasis only") — never discarded; a goal-conflicting purpose flagged rather than obeyed. No
  purpose given → nothing to tick
- [ ] Self-contained resume prompt between dashed rails — remaining-work bullets inline
- [ ] Copy instruction above the rails; `/goal` first line if a goal is active; a below-the-rails
  note re-arming EVERY surviving loop — one `/loop [<interval>] <original prompt>` line per loop,
  each its own follow-up message (engine doc, "Emit the copy/paste resume prompt")
- [ ] **EXECUTION STOPS HERE** — "small enough" means the prompt captures the work, NOT "small
  enough to skip `/clear` and finish in-session"

## What this skill does NOT do

- **Does not commit** — handoff docs are durable task state, not source code. Commit ready code
  changes separately; describe uncommitted work in the file-roles section
- **Does not invoke `/clear`** — the user types `/clear`. The skill produces the save-point, emits
  the resume prompt, and stops
- **Does not launch a background agent** — background delegation is the sibling
  `/session-flow:continue-in-background` skill, and it fires only on the user's explicit request
- **Does not continue executing the underlying task** — per the hard rule above. Prompt-only does
  NOT relax this
- **Does not replace a contract or plan** — it captures in-flight state at any point
- **Does not summarize the whole conversation** — task-relevant state only
