# The parent's cross-family contract

Everything the **parent** owes a dispatched `discovery:explorer` or `discovery:researcher` run that
is **identical for both families**. It exists because it did not: five statements below were
previously carried in two to six copies each, and every one of them had drifted apart by the time
the drift was audited — the envelope's field list, the pre-dispatch baseline command, the claim
about `$ARGUMENTS`, the agents' write boundary, and what to do with a partial slice.

Three files answer "what does the parent owe", and the split is deliberate:

| File | Owns |
|---|---|
| **this file** | what is the same for exploration and research |
| `${CLAUDE_PLUGIN_ROOT}/skills/explore/reference/dispatch.md` | explore-only: the collision rule, the six-dimension cost of a re-dispatch, that family's ladder |
| `${CLAUDE_PLUGIN_ROOT}/skills/research/context/dispatch.md` | research-only: the coverage ledger, the fan-out sub-slice rule, that family's ladder |

A statement that would be true of both families belongs here, and the other two point at it. Adding
a second copy is the defect this file removes.

## The pre-dispatch envelope

Six fields. The agent refuses to guess any of them, which is what makes the envelope safe to
mandate: an unresolved field surfaces as a failed dispatch instead of a confident answer to a
question nobody asked.

Write them as **labelled lines in the dispatch prompt**, not as prose the agent has to parse a
parenthetical out of:

```text
Topic: <the resolved topic>                     # /discovery:explore → Scope: <the resolved scope>
Reason: <the decision this feeds, and who the output is for>
Memory slice: <memory_dir>/<slug>/              # the sub-slice on a fan-out or a collision
Memory root: <memory_dir>
Budget: <the depth this session authorized>
Capability flags: nested spawning <available|unavailable>
```

Those labels are the ones `/discovery:research-deep` already ships in its literal dispatch block;
they are reproduced here rather than reinvented, so the two cannot drift.

**Memory root is its own line, not derivable from the slice path.** When the slice is nested — a
sub-slice for a collision or a parallel fan-out — no one can tell from the path alone which ancestor
is the configured root, and the root is where the self-ignoring `.gitignore` guard belongs. An agent
that has to derive it derives-and-flags rather than stopping, so the cost is a recoverable wrong
guess, not a halt: it is the one envelope field whose absence is degradable. Topic/scope, reason and
slice path are the hard stop.

### Capability flags carry what was probed, and nothing else

`nested-spawning` is a session property the parent can actually establish, which is why it is the
only flag. Two things are **not** flags, and asserting either would be the shape this plugin refuses
everywhere else:

- **The child's ability to write.** The parent's own `mkdir -p` + baseline touch proves that *the
  parent* can write there; the guard that has actually fired in the field was on **subagent**
  writes. There is no pre-dispatch probe for it that does not either lie or corrupt the freshness
  baseline — an agent-side probe `touch` into the slice makes the slice's newest file older than
  nothing and defeats the check `--newer-than` performs. The write question is answered *after* the
  fact, by `persistence: written | by-value` in the return payload, and that is the mechanism the
  ladders' by-value rung exists for.
- **Anything the parent did not check this session.** A flag copied from a previous dispatch is a
  recollection, not a probe.

## The pre-dispatch baseline

The gate's freshness input. Without it a slice that already holds an earlier run's artifact set
passes every on-disk check even when this dispatch wrote nothing at all.

Create the slice and touch the baseline immediately before dispatching, then hand that file to the
gate as `--newer-than`:

```bash
# POSIX shells (bash, zsh, Git Bash)
mkdir -p <memory-slice path> && touch <memory-slice path>/.<explore|research>-dispatch
```

```powershell
# PowerShell — `touch` is not a command here and `mkdir -p` is a parameter error
New-Item -ItemType Directory -Force -Path '<memory-slice path>' | Out-Null
New-Item -ItemType File -Force -Path '<memory-slice path>/.<explore|research>-dispatch' | Out-Null
```

Run whichever matches the shell this session actually has — on Windows without Git Bash that is
PowerShell, and the POSIX line fails there in a way that reads as a broken instruction rather than a
wrong shell.

Creating the directory is not decoration: on a first-time topic the slice does not exist yet, a bare
`touch` fails there, and the dispatch either stops before it starts or reaches a gate with no
baseline to grade against. A baseline the parent *named* but did not create exits 2 rather than
quietly reporting `freshness=unchecked` — a check the caller asked for and only appeared to get is
worse than one it knowingly skipped.

**On an N-topic fan-out, one baseline at the slice root serves every sub-slice.** The gate compares
each sub-slice index's mtime against the file it is handed, and a baseline touched now is newer than
anything an earlier run left anywhere under the slice, so a per-sub-slice baseline is optional
rather than owed.

The memory root's self-ignoring `.gitignore` guard is a **different** obligation and is not part of
this baseline — see "What this gate does not grade" below.

## Scope and topic do not arrive by argument substitution

A dispatched run gets its topic or scope from the **dispatch prompt**. It does not get it from the
`$ARGUMENTS` placeholder the skill body carries, and it has no conversation to fall back on: a
non-fork subagent starts with no history by design. So the operative rule is:

> **Never rely on seeing an unfilled slot.** Whatever a preloaded body renders as, the agent treats
> a topic or scope that did not arrive in its dispatch prompt as a **parent-envelope failure it
> reports rather than repairs** — never as an empty scope to fill in, and never as a licence to run
> a general sweep.

That rule holds whichever way the harness renders the placeholder, which matters because **the
harness's behavior on this path is not documented in either direction.** Recorded as unsupported,
not as false — nothing below establishes that a preloaded body renders the placeholder empty, and
nothing establishes that it does not:

- <https://code.claude.com/docs/en/skills> (raw markdown, fetched 2026-08-11) scopes the placeholder
  to invocation: "`$ARGUMENTS` | All arguments passed when invoking the skill." It states that
  preload is a different path — "Subagents with preloaded skills work differently: the full skill
  content is injected at startup" — and says nothing about argument substitution on it.
- <https://code.claude.com/docs/en/sub-agents> (raw markdown, same date) likewise: "The full content
  of each listed skill is injected into the subagent's context at startup." No mention of arguments.
- The nearest documented analogue points the *other* way. The `context: fork` walkthrough on the
  skills page shows the subagent "receives the skill content as its prompt (`"Research \$ARGUMENTS
  thoroughly..."`)" — the placeholder arriving as literal text, on a path that is not this one.

**Re-check both pages before restating any mechanism here.** Through 0.14.0 this plugin asserted a
specific empty-string rendering of the placeholder on the preload path as settled fact, at five
sites plus a weaker sixth and in two evals files: the operational conclusion was right and the
stated reason was never sourced.

### A different question: `${CLAUDE_…}`-shaped text a *caller* supplies

Do not merge this with the section above. One is about a placeholder **the plugin's own body**
carries on the preload path; this one is about placeholder-shaped text **a caller** types or writes
into a dispatch prompt. Neither is evidence for the other. All three entry skills point here rather
than each carrying its own copy.

**A `${CLAUDE_…}`-shaped token in a topic or scope may not arrive as you typed it.** Stated as what
was observed and what is documented, because the mechanism is neither:

- **Observed 2026-08-10:** an argument naming *another* plugin's `${CLAUDE_PLUGIN_DATA}` directory
  reached a dispatched discovery agent rewritten to **this** plugin's own path. The agent was asked
  a factually wrong question and answered it correctly.
- **Documented** (`plugins-reference`, `skills`, both fetched 2026-08-11): skill and agent content
  is a substitution site for `${CLAUDE_PLUGIN_ROOT}`, `${CLAUDE_PLUGIN_DATA}` and
  `${CLAUDE_PROJECT_DIR}` "anywhere the placeholder appears", and there is **no escape** for them —
  "A backslash before any other `$` is left unchanged" covers `$ARGUMENTS` and declared argument
  names, not these.
- **Not documented on any page:** whether argument-supplied text is itself scanned for those
  placeholders. The ordering is unstated, so do not read the observation above as a mechanism.

Practically: name a path in plain words rather than passing a `${CLAUDE_…}` token and expecting it
back. The `topic_as_received` / `scope_as_received` echo-back in the acceptance gate is what catches
this whichever way the substitution actually runs — and it matters most under
`/discovery:research-deep`, where one topic is copied into every envelope of an N-way fan-out, so
check each dispatched agent's echo against the envelope it was sent, per topic, before synthesis.

**This caveat expires 2027-02-11.** Re-fetch both pages then. After that date it is an unverified
claim, not a fact — say so rather than repeating it.

## Running the acceptance gate

Both `SKILL.md` files carry the gate's steps. Two things about *running* it are the same for both.

### The gate ships no permission grant, and the un-run case is a halt

Neither skill declares `allowed-tools`, and that is a conclusion rather than an omission. Three
independent legs, all from <https://code.claude.com/docs/en/skills> (raw markdown, fetched
2026-08-11):

1. **The substituting token cannot name these scripts.** "Claude Code substitutes
   `${CLAUDE_SKILL_DIR}` and `${CLAUDE_PROJECT_DIR}` in two places: the skill's markdown content,
   and Bash rules in the `allowed-tools` frontmatter." `${CLAUDE_PLUGIN_ROOT}` is not on that list,
   so a rule written with it stays a literal string and never matches. And `${CLAUDE_SKILL_DIR}` is
   "the directory containing the skill's `SKILL.md` file … for plugin skills, this is the skill's
   subdirectory within the plugin, **not the plugin root**" — while these gate scripts live at the
   plugin root on purpose, because one gate serves both families.
2. **An interpreter-led rule is an anti-pattern in this repo.** `bash` is not one of the wrappers
   Claude Code strips before matching, so a rule covering `bash <path> …` has to name `bash` — see
   `docs/conventions/permission-rule-hygiene/README.md`, anti-pattern 1.
3. **The grant would not last long enough anyway.** It "grants permission for the listed tools
   during the turn that invokes the skill … The grant clears when you send your next message." The
   parent runs this gate *after* a dispatch returns, which is a later turn.

So the honest statement is the one the rest of this plugin already makes about un-run checks:

> **A gate that could not run is a FAIL, never a skip.** If the invocation is denied, prompts and is
> declined, or errors out, report that and halt exactly as on a non-zero exit. Do not substitute a
> reading of the directory — the context most motivated to call the dispatch finished is the one
> that would be doing the reading.

**Operator setup, once, optional.** The documented way to cover a multi-turn command is settings,
not frontmatter: "To pre-approve tools for the whole session rather than a single turn, add allow
rules to those permission settings instead." An operator who wants this gate to run without a prompt
adds a rule for the two script paths to their own `~/.claude/settings.json`. The plugin cannot ship
it — a plugin's `settings.json` supports only the `agent` and `subagentStatusLine` keys.

### What this gate does not grade

The memory root's self-ignoring `.gitignore` guard. Stated here because "an obligation nobody
grades" was previously left implicit, and an unstated gap reads as a covered one:

- **`/discovery:setup` owns verify-or-create** for the guard at enable time, and owns the standing
  rule that the consumer's root `.gitignore` is never edited.
- **The agent owns it at run time** when the root is unguarded, which is why the memory root is its
  own envelope field.
- **The acceptance gate never checks it.** It grades the artifact set and the coverage ledger. A
  missing guard is a hygiene defect the parent can see in one `git status`, not a reason to discard
  a good run — so it is not wired into a gate that halts the workflow.

## Resume first, then decide about the slice

A dispatch that returns no payload at all, and a `status: truncated` return, both leave a partial
slice. Both also usually leave a **live agent**. The order is:

> **Resume first where the agent is still reachable; decide about the slice from what the resume
> returns.** Discarding first throws away the evidence that would tell you whether the slice is
> worth keeping — a resume has recovered a complete artifact set from retained context, and the
> discard-first reading would have re-dispatched a finished run at full cost.

The harness supports this, verified against <https://code.claude.com/docs/en/sub-agents> (raw
markdown, fetched 2026-08-11):

- "Resumed subagents retain their full conversation history, including all previous tool calls,
  results, and reasoning. The subagent picks up exactly where it stopped rather than starting
  fresh."
- "A completed subagent that receives a `SendMessage` auto-resumes in the background without a new
  `Agent` invocation."
- "When a subagent completes, Claude receives its agent ID" — address it by ID, not by name.

**The discard is what happens next, not instead.** Discard the partial slice — clearing it, or
assigning a fresh sub-slice — when the resume is refused, is unavailable, or comes back without a
usable payload. It stays mandatory there: a half-marked coverage ledger cannot be told apart from a
complete one by the coverage script, and a half-written artifact set cannot be told apart from a
complete one by reading it.

**`truncated` still means the turn-budget stop**, and nothing here widens it. That is the invariant
the `persistence:` axis was built around: a run that finished its work and could not save it is
`status: complete` + `persistence: by-value`, and its rung comes before this one in both ladders,
because the payload has already said why the disk is empty.

The full per-family ladders — including the by-value rung that precedes the resume rung, and
research's clear-the-slice rule — are in the two files named at the top of this document.
