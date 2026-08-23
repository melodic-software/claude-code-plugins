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

**Dispatch policy:** the producing main thread MUST NOT run the steps below inline — the thread that
wrote the change is the worst judge of what the change reaches, for the same reason `self` mode
refuses an inline checklist. Its model of "what this touches" is the one it already had while
writing, so an inline pass re-derives the author's own blast-radius assumption and confirms it.
Orchestrate a fresh-context read-only subagent; the main thread gathers inputs, dispatches, verifies
findings against the tree, and presents the verdict. Where the verdict is high-stakes and correlated
blind spots are the risk, prefer a cross-vendor advisor **when one is installed and set up** — e.g.
the OpenAI Codex plugin, when its documented surface can take this artifact, invoked per its own
docs — with the fresh-context same-vendor subagent as the stated fallback, never a route to a
command that may not resolve
(per `docs/PLUGIN-PHILOSOPHY.md` "Fresh-eyes checkpoints" in the marketplace repository).

## Orchestrator sequence (main thread)

1. **Gather inputs** — the resolved review diff base (SKILL.md "Shared inputs") and the changed
   symbol list from Step 1.
2. **Choose the worker** — a general read-only subagent. This mode has no dedicated agent, unlike
   `architecture` and `security`: its checks are not a fixed per-ecosystem baseline but a search
   shaped by what the diff changed, so the brief carries the specifics instead of an agent
   definition.
3. **Dispatch** with the brief below.
4. **Verify every finding before presenting** — open the named file, confirm the caller or reader
   exists and behaves as claimed. Worker output is synthesis, not evidence, and this mode's findings
   point at files the diff never touched, so an unverified one sends a reviewer to the wrong place.
5. **Present** the confirmed and cleared lists (Step 4) plus the cheapest-test handback.

## Worker brief

```text
You are a fresh-context reviewer. You did NOT author this change.

Inputs: git diff <review-diff-base>, plus the changed symbols named below.

Your job is what this change breaks OUTSIDE its own diff. Do not review the
changed lines — another mode does that. Listing callers is not the job either.

Search for the breakage a grep does not show: a library whose source behaves
unlike its docs, a wire format another service parses, a column a report reads,
a flag that changes which branch runs, a consumer several hops out or in another
language. A search that finds nothing is still an answer — report it as cleared,
with what you searched.

Do not edit files. Return two lists — confirmed and cleared — each finding with
its file:line and what you checked. Use only the severity and confidence
vocabulary given; introduce no other scale.
```

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

That formula and the discipline behind it are owned by `/playbooks:fable-5 verification` when the
`playbooks` plugin is installed — invoke it **with the chapter name**, rather than reading into the
plugin's files, and rather than bare, which arms that playbook's entire doctrine as standing session
instructions for the rest of the run. When it is not installed, the rule stands on its own as
written here. Do not invent a grading scale for it — the unverified claim is marked in words, and
its confidence is the shared `confidence` axis.

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
