---
name: sweep-all
description: "Compose this plugin's discipline correctors into ONE batched pass — not a corrector itself, but a router that fans out an audit-only subagent per in-scope corrector and then applies their corrections on the main thread in a fixed order. At conversation start it instead reports a cheap posture digest (which disciplines are in scope) with no audit. Use when: 'sweep all disciplines', 'ground ourselves', 're-anchor everything', 'run the whole re-anchor bundle', 'posture batch', 'set our posture before we start', 'batch the correctors', or at conversation start to set posture across every standing discipline at once. Membership is each corrector's own tier metadata; for a single discipline, invoke that corrector directly."
user-invocable: true
disable-model-invocation: false
metadata:
  workflow-stage: anytime
  summary: Batch every discipline corrector into one audited re-anchor pass
---

# Sweep all disciplines

A **declared second species** in this plugin: NOT a corrector. Every sibling
skill re-anchors ONE discipline; this one carries no discipline of its own —
it is a pure router that COMPOSES the correctors into a single batched
re-anchor pass. It holds zero discipline text: the disciplines live in the
correctors, the shared method lives in
[`${CLAUDE_PLUGIN_ROOT}/context/re-anchor-audit-correct.md`](../../context/re-anchor-audit-correct.md),
and membership + order live in each corrector's own tier metadata. This skill
names no members — it globs and reads them, so the bundle cannot drift from a
hand-maintained list.

## Two modes

1. **Session-start digest (cheap, default when nothing has happened yet).**
   Derive the posture from the skill listing and each corrector's tier
   metadata — NO corrector bodies load, NO audit runs. Report which
   correctors are core (run every session), which are situational
   (relevance-gated), and which are never-batched. This is the
   conversation-start case: set posture, audit nothing.
2. **Full batch pass (mid-session, or on explicit request).** Preflight that
   the fan-out can inherit this conversation (mandatory — see Preflight), then
   fan out an audit-only subagent per in-scope corrector and apply their
   corrections once, on the main thread, in a fixed order (below). A failed
   preflight degrades to mode 1.

## Resolving membership (never named inline)

Glob the sibling corrector directories and read each one's
`metadata.discipline-batch` (`core` / `situational` / `never`) and
`metadata.discipline-batch-rank`. The runbook never hardcodes member names;
the tier is colocated with each corrector, so changing a shipped tier is a PR
to that corrector — drift is structurally impossible.

- **core** — in scope every session.
- **situational** — in scope only when relevant to THIS conversation. Route
  from the corrector's own listing description (its trigger phrases and
  "at conversation start on …" clause), not from a guess. Report which
  situational correctors were included and which were skipped and why — a
  skip is always reported, never silent.
- **never** — excluded from the batch by execution or interaction class (the
  `-deep` fan-out tiers; `scrutinize-dont-coast`, which needs a non-fork
  fresh context and stops to remediate with the user). Report that they
  exist and are invoked directly, not batched.

**userConfig overlay** (see Configuration) applies after tier resolution:
`exclude` drops a member, `promote` lifts a situational corrector to
always-run, `demote` drops a core corrector to relevance-gated. Report the
net effect when an overlay changes the resolved set. Zero-config = tiers
exactly as the correctors declare them.

## Preflight: prove the fan-out can inherit (before step 1)

The batched pass is only meaningful if its subagents actually inherit this
conversation — establish that before dispatching, never by assuming it. A
subagent with no history has nothing to audit, and some share of them will
invent a ledger from the system prompt rather than say so — six of eight did in
the run this preflight comes from, and the two that refused are the only reason
it was caught. The batched pass's step 3 then merges those ledgers and its
step 4 **writes their remedies to the working tree**. That is the failure this
preflight exists to prevent: a correctness pass whose failure mode is
confident, invented corrections applied to real files.

**Stage 1 — read your own tool schemas. Zero dispatch, diagnostic only.** Two
documented sentences pair up: fork mode "removes the `run_in_background`
parameter from the `Agent` tool", while `CLAUDE_CODE_DISABLE_BACKGROUND_TASKS`
set to `1` removes it from "Bash and subagent tools"
(<https://code.claude.com/docs/en/sub-agents>,
<https://code.claude.com/docs/en/env-vars>). So `Agent` still carrying it means
fork mode is not env-var-enabled; `Agent` lacking it **while `Bash` keeps it**
excludes the disabled-background-tasks cause and leaves fork mode as the
remaining documented explanation; both lacking it says nothing about fork mode.
**This stage never gates** — the docs tie the removal to the env-var path and
say nothing about what the server-side rollout does to the parameter, so no
branch is conclusive in either direction. It explains what stage 2 finds; it
never replaces stage 2 and never aborts on its own.

**Stage 2 — an inheritance-proof canary. The decider, and it costs one fork.**
Dispatch ONE fork alone, ahead of the first wave, that answers the proof
question and **nothing else** — no corrector, no audit, no ledger. Gate the
whole fan-out on it.

It is deliberately not folded into a member's real audit, which would look free
and is not: a fork inherits everything the session holds when it spawns, so a
member ledger returned before wave 1 would sit in every later fork's inherited
context and anchor its audit — breaking the independence step 3 relies on (see
"the forks stay independent by design"). A proof-only canary returns nothing
that can anchor anyone. Budget the guard as one extra fork; that is what it
costs to know the other ledgers are real.

Every fork — canary and members alike — answers one inheritance-proof question
FIRST, before any audit content, and stops and says so plainly if it cannot.
Conversations differ, so specify the question's *properties*, not a fixed
question. All four are required:

- **Its answer exists only in this conversation's history** — not in a file, not
  in a `CLAUDE.md`: a non-fork subagent's initial context still contains "every
  level of the CLAUDE.md hierarchy the main conversation loads" plus the
  delegation message you write
  (<https://code.claude.com/docs/en/sub-agents>). Nor derivable from this
  plugin.
- **The dispatch prompt neither contains nor paraphrases the answer** — else a
  non-inheriting subagent answers it from the prompt alone.
- **It keys on ordinary inherited material** — a prior user turn or tool result.
  Out-of-band or host-injected content is not reliably inherited (observed once
  in a fork-enabled session: an out-of-band advisor result was absent from a
  fork's inherited transcript — not documented behavior, and a proof keyed on it
  would have read as a false negative).
- **It cannot be guessed.** An answer a non-inheriting subagent could hit by
  chance — a yes/no, a binary choice, a detail common to most sessions — clears
  the main thread's check without proving anything, and the blind ledgers behind
  it then reach the corrective write — and blind forks guess alike, since they
  share the question and the model, so one lucky answer is not one bad ledger.
  Small-domain values fail this test even when they are exact: a turn count, a
  file count, a finding count are all guessable. Require a long verbatim
  string or a specific identifier, and when in doubt mint the value (below)
  rather than picking one out of the history.

When the conversation offers no detail meeting all four — a thin session that
opened straight into a full batch over an already-dirty tree — do not degrade.
**Mint one.** "A fork inherits everything the main session has at the moment it
spawns" (<https://code.claude.com/docs/en/sub-agents>), so emit a fresh
high-entropy value into the transcript as an ordinary main-thread tool result
BEFORE the canary spawns, and ask for it back. It is unguessable by
construction, exists in no file, and a non-inheriting subagent cannot produce
it — so the proof works at any conversation length, and thin history never
costs the user the audit they asked for.

**Verify on the main thread, and fail closed.** Check the answer against what
this context knows. Absent, ambiguous, or unverifiable proof counts as NOT
inherited — a plausible-looking answer is not a pass, because fabrication is the
exposure being defended against. Canary verified → fan the members out. Canary
unproven → degrade; never re-dispatch the batch blind.

A member that returns unproven LATER, mid-fan-out, is a different case: the
canary already established that inheritance works here, and earlier waves'
ledgers are checkpointed and real. Discard that member's ledger, retry it once,
and if it is still unproven **keep every verified ledger, correct forward from
those, and report the unproven members as open** — do not throw away proven
audits by collapsing the whole pass to the digest. Reserve the digest for a
failed canary, when nothing has been proven at all.

**A failed canary degrades; it does not stop empty-handed.** Run the
session-start posture digest (mode 1) — no fan-out, no cost — and report that
the inheriting audit fan-out could not run, which signal established that, and
that every corrector remains available for direct invocation, one at a time,
each running the shared loop in THIS context with no fork at all. That is the
same position `setup` reports as the full-batch prerequisite; this runbook is
where it executes. The batch does **not** sequence the correctors itself as a
substitute — that recreates the salience dilution the declared delta below
exists to prevent, and yields audits weaker than the ones it declined to run.

**What is gated, and what is not documented.** `CLAUDE_CODE_FORK_SUBAGENT` set
to `1` enables fork-spawning and `0` disables it "overriding any server-side
rollout", and a staged rollout can enable it without the variable
(<https://code.claude.com/docs/en/env-vars>,
<https://code.claude.com/docs/en/sub-agents>). What the harness does when the
`fork` type is requested while fork mode is OFF is **not documented on any
current page** — observed once, in the failed full-batch run this preflight
comes from, as subagents returning with no inherited conversation. Treat it as
an observation, not a contract; the preflight does not rest on it, proving
inheritance positively rather than predicting the shape of its absence.

## The batched pass — a declared delta from the shared loop

Recorded here as a **declared delta** per the shared method doc's
declared-delta rule (this runbook is not a corrector, but it orchestrates the
shared loop across members and diverges from its per-corrector
"correct forward now" step, so the divergence is part of this skill's
contract, not silent drift). Two divergences are declared: the **inserted
preflight** above, which sits before this list's step 1 and gates the whole
pass, and the split below. The shared loop has each corrector run steps 1–3
itself, in its own context. This runbook **splits** them: the audit
(steps 1–2) runs in per-corrector subagents; the correction (step 3) is
collected and applied ONCE on the main thread, serialized in rank order.
Rationale: a dozen disciplines each correcting forward independently in one
context recreates the salience dilution this plugin exists to fix, and a
merged pass lets order matter. The shared method's Non-negotiables are
unchanged and bind every member.

1. **Fan out, audit-only** — after the preflight above has proved inheritance.
   For each in-scope corrector, dispatch a
   conversation-inheriting **fork** subagent — the Agent tool's
   `subagent_type: "fork"`, which inherits the full conversation history the
   audit must read. A fresh/typed subagent receives no history, and a
   skill-level `context: fork` also discards it — neither can audit this
   conversation. The forks read the live working tree — do NOT isolate them
   (see Gotchas: isolation would hide the uncommitted work in flight, which is
   usually the thing under audit). Their no-writes rule is trusted, not
   enforced — see Gotchas, and treat a fork that wrote as untrusted output:
   stop rather than correct on top of it. Instruct
   each fork: answer the preflight's inheritance-proof question first, then
   load exactly this ONE corrector's
   `SKILL.md`, run shared-loop steps 1–2 only (re-anchor + self-audit), make
   NO writes, and return a findings ledger. Each ledger entry carries the
   concrete located finding AND the remedy this corrector would apply for it
   (the shared loop's step-3 corrective action, *described* not performed — the
   fork still writes nothing), or an honest "clean". Capturing the proposed
   remedy in the audit is what gives step 3 the reporter→remedy data to key on;
   a ledger of bare violations would leave the dedup with nothing to preserve.

   **Wave sizing, budget, and what counts as a failure.** Prefer ONE wave:
   dispatch every in-scope member together, so no member's ledger is in the
   transcript when another member spawns. That independence is load-bearing,
   not decoration — step 3's dedup and step 4's ordering both assume the
   ledgers were formed without seeing each other, and a fork inherits
   everything the session holds at the moment it spawns. Splitting the fan-out
   is what breaks it, so do not import the `-deep` siblings' "roughly a dozen"
   wave: it is calibrated for cheap fresh-context subagents that carry no such
   invariant.

   One wave is usually possible, and the two documented limits are not the
   same kind of limit. `CLAUDE_CODE_MAX_TOOL_USE_CONCURRENCY` ("Maximum number
   of read-only tools and subagents that can execute in parallel", documented
   default 10) caps how many run at once — it does not cap how many you
   dispatch. The hard one is `CLAUDE_CODE_MAX_CONCURRENT_SUBAGENTS` (documented
   default 20): past it, "spawning another with the Agent tool fails with
   `Concurrent subagent limit reached`, and the error tells Claude not to
   retry." Every Agent-tool subagent counts against it, forks included, shared
   with everything else the session is running, and against
   `CLAUDE_CODE_MAX_SUBAGENTS_PER_SESSION` (documented default 200)
   (<https://code.claude.com/docs/en/sub-agents>,
   <https://code.claude.com/docs/en/env-vars>). So even a fully-admitted set —
   every core plus every situational corrector — dispatches in one wave in an
   otherwise-quiet session.

   **Never drop a relevant corrector to fit a budget.** Membership resolution
   decides what is in scope; concurrency decides only when it runs. If the
   session already holds enough subagents that the full set cannot be
   dispatched, wait for capacity and then dispatch it whole. Split only if that
   is not possible, and then **say so in the report**: every member in a later
   wave inherits the earlier waves' ledgers and can be anchored by them. That
   is a real weakening of the independence the dedup relies on, disclosed, not
   hidden. Only a split fan-out needs the `-deep` siblings' per-wave
   checkpointing of the collected ledgers; a single wave has no partial state
   to lose.

   **Retry, and what counts as a failure.** Retry only a failed subset, once —
   and **failure includes a ledger returned without verified inheritance
   proof**, not only an errored dispatch: a fabricated ledger is the exposure
   the retry rule exists for. One dispatch error is explicitly NOT a retryable
   failure: `Concurrent subagent limit reached`, which the harness tells Claude
   not to retry. That is a capacity race, not a failed audit — wait for
   capacity and dispatch, rather than retrying into the same wall. A retry is anchored by construction, one wave or
   many: it spawns after other members' ledgers have landed, so it inherits
   them. There is no un-anchored rerun available inside this conversation —
   re-running the whole pass would inherit MORE, not less, since every ledger
   is already in the transcript any new fork copies. So do not offer a clean
   rerun; report each retried member's ledger as anchored and weigh it as such.
   A member still unproven after its one retry is reported
   open, and the verified ledgers are kept and corrected — see the preflight's
   mid-fan-out rule; only a failed canary collapses the pass to the digest.
2. **Collect** every ledger.
3. **Dedup by root cause.** Before correcting, group ledger entries across
   correctors that name the SAME underlying finding — distinct disciplines
   routinely surface one root cause as separate entries (e.g. a recall-based
   claim flagged independently by `do-your-research`, `recheck-against-upstream`,
   and `mind-your-maxims`). Group them into one finding carrying the union of
   their located evidence and, keyed BY reporting corrector, the remedy that
   corrector asks for — a reporter→remedy mapping, not a flat remedy list beside
   a separate reporter list, so step 4 knows which remedy belongs to which rank.
   What dedup collapses is the
   re-analysis and the re-reporting of one root cause — NOT the corrective work:
   a shared root cause can demand more than one remedy that are not
   interchangeable (verifying or retracting the unsupported claim satisfies the
   research reporters, but `mind-your-maxims` may still require a reader-facing
   uncertainty disclosure), and every reporter's remedy is still applied. This
   grouping is the ONLY place ledgers combine: the forks stay independent by
   design (no shared ledger across forks — that independence is what keeps each
   audit's perspective un-anchored), and grouping is by root cause, not by
   corrector. A finding only one corrector raised passes through unchanged.
4. **Correct once, in rank order.** Walk the in-scope members — the core and
   situational correctors that ran (never-tier carries no rank and was already
   excluded at membership resolution) — by ascending `discipline-batch-rank`,
   and correct forward each finding on the main thread now — the shared loop's
   step 3, batched. For a grouped finding, "once" means the root cause is
   analyzed and corrected in a single pass, not that its remedies collapse to
   one: apply every reporter's distinct remedy, each at its own reporting
   corrector's rank (so the research retraction and the `mind-your-maxims`
   disclosure both happen, in rank order), rather than dropping the
   lower-priority reporters' corrective work. The order:
   `use-your-skills` first (fix which skills govern the work) → evidence
   correctors (get the facts right) → structural correctors → `mind-your-maxims`
   (communication) → `tighten-your-output` dead last, so it never tightens
   text a later corrector rewrites. Correcting on the main thread does not
   suppress the shared method's fresh-context escalation: where a finding's
   suspected drift source is this context's own judgement, re-derive it in a
   fresh-context (non-fork) subagent blind to that reasoning, per the method
   doc's Non-negotiable — the batch orchestrates the correction here, it does
   not waive that escalation. (The fork *audit* inherits context on purpose:
   step 2 is a same-context self-audit; this carve-out is about step 4.)
5. **Report** one consolidated ledger: per corrector — corrected / clean /
   open; a root-cause finding merged in step 3 is listed once, attributed to
   every corrector that reported it; plus which situational members ran versus
   were skipped, and which never-members exist for direct use.

## Member human-gates survive batching

The batch never converts a member's human gate into an autonomous action.
The shared method's outward-artifact carve-out (no PR, issue, or published
comment without explicit opt-in) holds, as do `follow-our-standards`'
upstream-divergence routing (draft and route, do not file),
`pick-for-the-problem`'s incumbent-replacement decisions, and
`recheck-against-upstream`'s undocumented-divergence calls. The batch
surfaces these for the user; it does not resolve them unasked.

## Configuration

The overlay reads three personal-scalar `userConfig` options (configured
through Claude Code's native plugin-config flow — see the plugin README —
never a hand-edited member), substituted here at load:

- Excluded correctors: `${user_config.batch_exclude}`
- Promoted to always-run: `${user_config.batch_promote}`
- Demoted to relevance-gated: `${user_config.batch_demote}`

Each is a comma-separated list of corrector names. An unset option does not
reliably substitute to empty: on a zero-config or headless install, or for a
user who never ran plugin-config, the literal `${user_config.…}` token
survives instead. Treat BOTH an empty value AND a surviving literal
placeholder as unset — no overlay from that key — and never read the literal
token as a corrector name. Apply
after tier resolution: `batch_exclude` drops a member, `batch_promote` lifts a
situational corrector to always-run, `batch_demote` drops a core corrector to
relevance-gated. Report the net effect whenever the overlay changes the set.

## What this skill does NOT do

- **Not a corrector.** It owns no discipline and re-anchors nothing itself.
- **Not `use-your-skills`.** That corrector routes to the ONE skill fitting a
  task; this composes the whole posture bundle.
- **Not a session or SDLC orchestrator.** Staged navigation and session
  lifecycle belong to the `session-flow` plugin; this only sequences the
  re-anchor correctors.
- **Does not batch the `never` tier** — the `-deep` fan-out siblings and
  `scrutinize-dont-coast` are invoked directly.
- **Does not name its members inline** — membership is each corrector's own
  tier metadata.

## Gotchas

- **Fork, not fresh/typed, and not skill-level `context: fork`.** Only the
  Agent-tool `subagent_type: "fork"` inherits the conversation the audit
  reads; the other two start blank.
- **Audit in the forks, correct on the main thread.** Parallel forks that
  wrote would race and re-dilute salience; the value is one ordered
  correction pass.
- **The forks' no-writes rule is trusted, not enforced — say so.** A named
  subagent's tool access can be narrowed with `tools` / `disallowedTools`; a
  fork's cannot. Forks "skip both filters and receive the main conversation's
  exact tool pool", and a fork's system prompt and tools are "Same as main
  session" (<https://code.claude.com/docs/en/sub-agents>). So every audit fork
  holds Write, Edit, and Bash and is only *asked* not to use them. Never
  present the audit fan-out's read-only posture as harness-enforced. If you
  want assurance that the fan-out honored it, capture the working tree's state
  before the FIRST dispatch (the canary included) and compare afterwards, and
  treat any difference as a fork that wrote — untrusted output, stop rather
  than correct on top of it. That is detection after the fact, not prevention,
  and a robust comparison is more than a `git status` diff — specifying one is
  tracked in `#1631` rather than half-specified here.
- **`isolation: "worktree"` was considered for the audit forks and rejected.**
  The Agent tool accepts it on a fork, and it would move a fork's file edits
  off the user's checkout — but a git worktree is created from a commit, so the
  fork would not see the uncommitted work in flight, which is usually the very
  thing the audit exists to inspect. It also would not bound a write addressed
  by an absolute path, and inherited history is full of absolute paths. It
  trades a real loss of audit fidelity for partial containment. Record this if
  it is proposed again.
- **The preflight is the guard, not an optimization.** Skipping it does not
  make the sweep cheaper — it makes every ledger unfalsifiable, and the
  batched pass's step 4 writes those ledgers' remedies to the working tree.
- **Forks run at the parent model's cost.** An Agent-tool fork ignores a model
  override and inherits the whole conversation, so each in-scope corrector's
  audit runs at the parent model over the full transcript; the wave cap bounds
  burst, not per-fork cost. Keeping the `never` tier out and relevance-gating
  the situational tier are what hold the fan-out small. Order of magnitude from
  a real full-batch run on a mid-length session: each fork consumed
  ~170K tokens (inherited transcript), so an 8-in-scope pass ran ~1.4M tokens
  for the audit phase alone, plus one more fork for the proof-only canary.
  Budget the sweep as a
  deliberate spend, not a reflex — on a long transcript the per-fork cost only
  grows.
- **`tighten-your-output` stays last** — tightening before the other
  corrections would tighten text they then rewrite.
- **A situational skip is reported, not silent** — the user sees what was
  left out and why.
