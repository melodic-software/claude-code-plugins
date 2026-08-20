# Downstream review mode

What does this change break **outside its own diff**? Every other mode in this skill judges the
changed lines; this one judges what the changed lines reach. It is the only mode whose findings are
expected to name files the diff never touches.

Listing the callers is not the job — a grep finds those in seconds. The job is the breakage a grep
does not show: the library whose source behaves unlike its docs, the wire format another service
parses, the column a report reads, the flag that changes which branch runs, the consumer three hops
out in another language.

Severity and confidence come from the shared vocabulary
([`${CLAUDE_PLUGIN_ROOT}/context/severity.md`](${CLAUDE_PLUGIN_ROOT}/context/severity.md)) or the
project's own when it defines one. **This mode adds no grading scale of its own** — not a proof
level, not an evidence rung, not a confidence variant. The two existing axes carry every finding.

## Step 1: Read what actually changed

The diff, the symbols it adds, changes and removes, and what now behaves differently — including the
part the diff does not spell out. A renamed parameter is a signature change; a widened return type is
a contract change; a removed guard is a precondition moved onto every caller.

## Step 2: Ask the single-fact question once, then move on

Many changes that look alarming are safe because of one fact — "this only evicts entries already past
their TTL", "the compiler rejects every caller that was not updated". Ask it first, because when such
a fact exists, verifying that one thing collapses most of the scary cases at once.

**Then enumerate the risks anyway.** The single fact is a probe, never the report's structure. A
change with three independent risks organised around its most legible one leaves the other two not
merely unmentioned but structurally invisible — the report has no slot for them. Annotate which risks
collapsed into a shared fact; never let that annotation become the outline.

## Step 3: Look where grep stops

The reachable surfaces a symbol search misses, in rough order of how often they bite:

- **Library behaviour** — read the dependency's own source for the call you changed, and check its
  pinned version and any local patch. Documented behaviour and shipped behaviour diverge.
- **Serialization boundaries** — JSON an API returns, a persisted column, a cache key shape, a wire
  format, a file another tool parses. A field rename is invisible to a compiler and fatal to a reader.
- **Timing and lifecycle** — teardown order, microtask versus macrotask, cancellation, retry, whether
  a handler can now run after unmount or after close.
- **Configuration reach** — feature flags, environment-dependent branches, defaults a consumer relies
  on precisely because it never overrides them.
- **Cross-language and cross-service readers** — anything consuming the same bytes without sharing
  the type definition.

A search that finds nothing is an answer worth reporting. Never invent a caller or an API to fill a
gap: cite `file:line` for what you found, and say plainly what you looked for and did not find.

## Step 4: Split confirmed from cleared

Both halves are deliverables. The cleared list is what makes the confirmed list trustworthy — a
report with no cleared concerns has not shown its work, only its conclusions.

- **Confirmed risks** — each names how it breaks, its `file:line`, how likely it is, what it costs
  when it happens, and how a reader can check it themselves.
- **Cleared concerns** — what was investigated and why it turned out fine.

**A safety fact you could not verify never clears a concern.** It belongs in the confirmed list,
carrying the reason it is unverified. This is the whole discipline of the mode: an unverified
assumption that has been sorted into the reassuring column is worse than one nobody looked at,
because it now reads as checked.

## Step 5: Say plainly what is unverified

This skill does not run builds or tests (see the parent skill's "What this skill does NOT do"), so a
claim resting on an unrun check is stated as **"assessed, not verified because Y"** — naming Y.

That formula and the discipline behind it are owned by the fable-5 playbook's verification chapter
(`playbooks/fable-5/context/verification.md`) when the `playbooks` plugin is installed; when it is
not, the rule stands on its own as written here. Do not invent a grading scale for it — the
unverified claim is marked in words, and its confidence is the shared `confidence` axis.

## Step 6: Hand back the cheapest test that would catch it

Name the smallest test or reproduction that fails if the most serious confirmed risk is real. Do not
write it here — this mode reports.

- Authoring the test routes to `/testing:write` when the `testing` plugin is installed.
- Proving the test actually catches the bug routes to `/mutation-testing:audit` when the
  `mutation-testing` plugin is installed — which is stronger than asserting it will, because the
  mutant is re-run and the agent that wrote the test does not grade itself into a pass.
- Neither installed: state the test in enough detail that a reader can write it, and say that its
  existence is unverified.

## Skip conditions — when this is the wrong mode

- **The change is not written yet.** Assessing a plan's reach before implementation is
  `/planning:plan`'s Step 3b scalar and `/planning:devils-advocate`'s adversarial rounds. This mode
  needs a diff.
- **The change is a rename sweep.** Counting and bucketing stale references after a rename is
  `/docs-hygiene:rename-references audit blast` — mechanical, token-scoped, and better at it.
- **The question is whether the diff does what was asked.** That is `spec` mode; this one does not
  care what was asked, only what else it reaches.
