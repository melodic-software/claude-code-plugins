# Loop-lane launch prompts

Reusable templates for the three-lane topology. Fill the variables, paste a
block. Nothing below is specific to one repository except the profile you
fill in yourself.

## Variables

Replace every `{{...}}` occurrence in the block you are pasting.

| Variable | Meaning | Example |
|---|---|---|
| `{{REPO}}` | Target repository, `owner/name` | `acme/widgets` |
| `{{TIER}}` | babysit-prs tier: `safe`, `worker`, `autopilot` | `worker` |
| `{{STOP}}` | `--drain` to finish and stop; omit to stand | `--drain` |
| `{{SHARD}}` | Attended terminal's bucket | `[ratify]` |
| `{{RUNTIME_SURFACES}}` | Doc-shaped paths that are runtime | see profile |

`{{TIER}}` widens discovery, fixing, threads, drafts, barriers, and
escalation. It never raises merge authority — that binds only from the
target repo's tracked config (below).

## Per-repository profile

Fill this once per repository, before first launch. Every answer is a fact
about that repo, not a preference.

- **Merge rung** — read `babysit_loop_merge` in the target repo's tracked
  `.claude/source-control.md` on its default branch. Absent or no
  loop-lane keys at all means **every merge is human**, whatever tier you
  pass.
- **Tracker binding present?** `.work-item-tracker.json` must resolve from
  the worker lane's working directory or its preflight stops the lane.
- **Role labels** — the human-gated and autonomous-eligible names come
  from that file's `config.role_labels`, not from a literal. Resolve the
  `autonomous-eligible` role **before** any query below; a repo that remapped
  it makes the default `agent-ready` the wrong population, and the counts
  come back empty for a fully-stamped backlog:

  ```bash
  ROLE=$(jq -r '.config.role_labels."autonomous-eligible" // "agent-ready"' \
    .work-item-tracker.json)
  ```

- **Is a classification source present, and how many items carry one?** The
  merge partition reads "the triage stamp in the item body **or** labels" —
  either satisfies it, so count the **union**, never one source alone. A
  label-only repo returns zero on a body-only count and vice versa; either
  in isolation under-reports the merge-eligible population and feeds the rung
  decision a wrong number.

  ```bash
  gh label list --limit 200 | grep -i work-class
  gh issue list --label "$ROLE" --limit 500 --json number,body,labels \
    --jq '[.[] | select((.body | test("Work-class: C[0-9]"))
           or (.labels | any(.name | test("work-class"; "i"))))] | length'
  ```

  **Always pass `--limit`** — `gh issue list` silently truncates at 30, so an
  unbounded count under-reports any backlog past that.

  A repository that records classifications only as body trailers is fully
  merge-capable and needs no label provisioning. Conclude "nothing can merge"
  only when the union is empty.
- **`{{RUNTIME_SURFACES}}`** — paths that look like documentation but are
  loaded by an agent at run time. This drives classification: a change to a
  runtime surface is never mechanical, so an under-listed value is a safety
  hole, not a cosmetic omission — it lets a behavioral change be stamped C2
  and merged unattended.

  **Define it fail-closed: every plugin-tree `.md` is runtime until proven
  inert.** A forward derivation — grep the skill bodies for what they load,
  then treat the results as the boundary — is tempting and is wrong twice
  over. It misses every load directive that is not a markdown link (bare
  `Read references/shared/*.md` lines, glob directives, paths built at run
  time), and any pattern that strips the originating file yields ambiguous
  bare names: `context/audit.md` alone names three different runtime files
  in this repo. A boundary that silently under-reports is worse than no
  boundary, because it reads as coverage.

  So invert it. Start from the whole tree and subtract only what is provably
  not loaded:

  ```bash
  find plugins -name '*.md' | grep -vE '/(CHANGELOG|README)\.md$'
  ```

  Everything that survives is runtime for classification purposes —
  `SKILL.md`, `agents/*.md`, `commands/*.md`, and every `reference/**`,
  `references/**`, `context/**`, `templates/**` file at any depth. Removing
  a further path from the set requires showing that nothing loads it, per
  path, not per directory name. In an application repo the set may be
  genuinely empty — but prove that, do not assume it.

## Adopting a new repository

1. Land `babysit_loop_*` keys in that repo's tracked
   `.claude/source-control.md` on the default branch. Without this the
   merge lane runs and merges nothing.
2. Confirm the work-class label axis exists:
   `gh label list | grep -i work-class`. Record the exact strings in the
   profile — prefix, casing, and spacing vary by repository.
3. If it does not exist, provision it before going further. No lane may
   create labels; the label set is IaC-owned, and the five members are
   ratified as aliases of the autonomy program's C1–C5 risk classes with
   the alias map single-sourced in the label declarations. Add them
   through the `github-iac` repository that owns that org's labels, not
   by hand with `gh label create`.
4. Stamp the agent-ready items, or accept that nothing auto-merges.
5. Point one worker lane and one merge lane at it, on different machines.

## How to inject these

Standing rules must live **inside** the recurring prompt. `/loop <prompt>`
re-sends that text every iteration; rules pasted as a separate turn live in
conversation context only and are lost to compaction. One block, everything
in it — never setup-then-loop as two turns.

**`loop.md` alternative.** Put the body in `~/.claude/loop.md` on that
machine, minus the leading `/loop` line, then type bare `/loop`. Edits take
effect on the next iteration, so a running lane can be tuned without
restarting. One default prompt per location; use the user-level file
because `.claude/loop.md` is git-tracked and conflicts across machines.

## Topology rules

- **One worker lane per repository.** Item claims are provider-arbitrated
  and safe across machines, but durable loop state is not: both lanes
  resolve the same telemetry issue and sentinel, making `item_cap`,
  `clean_streak`, `rate_limit_latch` and `first_drain_complete`
  last-writer-wins. One machine setting `first_drain_complete` ends the C3
  earn-trust gate for both. Use two machines for two repositories.
- **One merge lane per repository.** babysit-prs leases are machine-local
  files, so a second machine gets no mutual exclusion.
- **Merge lane off the attended machine.** It competes for the same
  account's rate window your interactive session needs.
- **Worker lane launches from a checkout** of `{{REPO}}`. The merge lane
  may launch anywhere; it reads the target's config over the API.
- **Never run two lanes from the same working directory.** Claude Code
  stores the scheduled-task list in the project's `.claude` directory, so
  two sessions in one folder contend on it. Use separate clones or
  worktrees per lane, even on the same machine.

## Models

Launch each lane with an explicit `--model`. It applies to that session
only, so a global default is left undisturbed. Aliases, never dated model
IDs — the alias tracks the current recommended model and a pinned ID rots.

- **Worker lane root — `sonnet`.** Snapshot, admission gate, dispatch,
  telemetry upsert. Bookkeeping, not diff reasoning.
- **Merge lane root — `sonnet`.** The rung partition is deterministic;
  the real work happens in dispatched workers.
- **Attended queue — `opus`.** Human in the loop, and where
  classification proposals are made.
- **Dispatched implementers — `opus`.** Strong tier, and the freshest
  knowledge cutoff of the four.
- **Conflict and security subagents — `fable`.** Frontier tier, which
  babysit-loop requires for conflict workers unconditionally.
- **Mechanical greps and log pulls — `haiku`.** Per-dispatch override
  only: 200k context and an old cutoff, never for a question about
  current harness behavior.

```bash
claude --model sonnet   # worker lane
claude --model sonnet   # merge lane
claude --model opus     # attended queue
```

Pair the fast roots with a stronger advisor (`advisorModel: opus`). A fast
orchestrator plus an advisor at or above the main tier is the convention's
recommended shape, and it is what makes a `sonnet` root safe. Leave effort
at its default; Opus and Sonnet already default to high in Claude Code.

## Concurrent workers on one repository

The obvious idea — two worker lanes on one repo, one taking oldest items
and one taking newest — does not work, for two independent reasons.

**The sharding is not expressible.** Selection Priority tier 3 sorts
oldest-first on `createdAt`, deterministically, and no code path reads
anything a launch prompt can set. Both lanes would chase the same oldest
candidate.

**They would not duplicate work, but they would corrupt shared state.**
The claim is provider-arbitrated (assignee plus lease; exit 7 means
"another session won, advance, do not retry"), so two lanes interleave
correctly. Durable loop state is the problem — both resolve the same
telemetry issue and sentinel, making these last-writer-wins:

- `item_cap` and `clean_streak` — the adaptive cap stops reflecting either
  machine's real experience. Annoying, not dangerous.
- `rate_limit_latch` — one machine can clear the other's pause latch.
- `first_drain_complete` — one machine setting it ends C3 earn-trust
  admission for **both**. This is the one that matters: it widens autonomy
  with no human ratification, which is the opposite of that gate's purpose.

**Recommendation: one worker lane per repository.** A single lane already
runs its adaptive item cap (2–3) times the dispatch wave cap (3–5), so
6–15 concurrent workers; rate limits bind long before lane count does. For
more parallelism, point the second machine at a **different repository** —
no shared state, no contention, and the sharding problem disappears.

---

## 1 — Worker lane

> **=== COPY FROM HERE ===**
>
> /loop /work-items:work-loop
>
> Repository: `{{REPO}}`
>
> **Standing authorization.** Autonomous lane. These standing rules are
> the direction that `/work-items:triage`'s mutation gate and the
> self-observation filing contract require: triage, classify, label,
> comment, file follow-up items, claim items, author branches and PRs —
> all without a human turn. Prefix every comment and item you create with
> the AI disclaimer specified by triage. You never merge.
>
> **Discipline.** Every cycle, and every dispatch brief you compose at
> every nesting depth, invokes `/discipline:sweep-all`. Do not enumerate
> the individual disciplines — that skill resolves its own membership and
> a hand-copied list drifts. If the `discipline` plugin is not installed
> here, inline the equivalent standing instructions instead: verify claims
> against authoritative sources before acting, prefer installed skills
> over ad-hoc approaches, and re-check work against the active
> conventions.
>
> **Return contract, every subagent, every depth.** Return at most two
> lines: a verdict token and an identifier or path. Everything else goes
> to a file in your worktree or a comment on the item. Do not summarize
> your work back to me. Speak to me only when fully blocked and unable to
> escalate through the tracker.
>
> **Work classes are not yours to set.** The autonomy contract is
> explicit: "no repo-local (agent-writable) surface may supply the class
> used for admission." Never apply or change a `work-class:` label. An
> item without one still goes through the admission gate's own
> classification, and a candidate the gate cannot confidently classify
> fails closed to human-gated and is escalated, never worked. What the
> missing label costs is merge eligibility only. List unstamped items in
> your cycle report.
>
> **Worktrees are not yours to remove.** The worker's worktree persists
> through the whole PR lifecycle and is cleaned up only by whoever merges
> — never mid-lifecycle, never by this lane. Report accumulation instead.
>
> **Prefer single shell invocations** over `for` loops and `&&` chains
> where a single call would do: the auto-mode classifier blocks compound
> forms and nobody is awake to approve a retry. Preference, not
> prohibition — code a skill mandates verbatim, including the telemetry
> upsert block, runs exactly as written.
>
> **=== COPY TO HERE ===**

---

## 2 — Merge lane

`{{STOP}}` matters more than it looks. The drain-terminal state — stop
cleanly once every remaining item is human-gated or escalated with no PR in
flight — is scoped to the drain shape only. Standing mode has no
activity-timeout stop at all; its exits are the seven-day expiry, a
cycle-budget hit, or you. Left standing, the lane sits at the one-hour
wakeup ceiling for days rather than finishing.

> **=== COPY FROM HERE ===**
>
> /loop /source-control:babysit-loop {{REPO}} {{TIER}} {{STOP}}
>
> Repository: `{{REPO}}`
>
> **Standing authorization.** Autonomous lane. Advance PRs, fix
> branch-owned CI and review failures, resolve outdated bot threads, and
> merge within whatever rung the repository's tracked config resolves. You
> never claim backlog items and never author work-item PRs — that is the
> worker lane's authority.
>
> **PR ordering.** Ordering only, never eligibility — eligibility is the
> skill's deterministic partition and nothing here overrides it. Within
> the eligible set, prefer PRs that unblock other work, then oldest.
>
> **Escalation.** When a PR is stuck — merge conflict, a decision you
> cannot make from the item and the diff, a barrier the tier permits
> attempting — dispatch the conflict subagent at the frontier capability
> tier, as the skill requires, and never below it. Before acting on a
> non-trivial resolution, get a second opinion from an independent
> subagent that did not produce it. If the two disagree, escalate rather
> than pick.
>
> **Discipline.** Every dispatch brief at every depth invokes
> `/discipline:sweep-all`. If that plugin is absent here, inline the
> equivalent standing instructions instead.
>
> **Return contract.** Subagents return at most two lines — verdict plus
> identifier. Speak to me only when fully blocked.
>
> **Work classes are not yours to set.** Never apply or change a
> `work-class:` label to make a PR merge-eligible. A PR whose close-linked
> item carries no work class is not eligible at any rung, including
> full-autonomy. That is the correct outcome, not an obstacle: report it
> and move on. Manufacturing your own merge eligibility is the one thing
> this lane must never do.
>
> **Contention.** A worker lane authoring PRs here is expected and is not
> contention. Apply the skill's own per-PR foreign-activity suppression:
> yield on the specific PR showing unaccounted same-login activity, keep
> processing the rest. Stop the whole lane only if a second *merge* lane
> appears to be running against this repository.
>
> **Prefer single shell invocations** over `for` loops and `&&` chains
> where a single call would do. Preference, not prohibition — code a skill
> mandates verbatim runs exactly as written.
>
> **=== COPY TO HERE ===**

---

## 3 — Attended queue

Human-in-the-loop, no `/loop` wrapper. attend-queue has no shard parameter
and no row-level claim, so `{{SHARD}}` is operator convention rather than
enforcement. Give each terminal a different value.

> **=== COPY FROM HERE ===**
>
> /work-items:attend-queue
>
> Repository: `{{REPO}}`
> Shard: `{{SHARD}}`
> Runtime surfaces in this repo: `{{RUNTIME_SURFACES}}`
>
> I am present. Recommend, then wait for my direction before mutating.
>
> **Stay inside your shard.** Work only rows carrying the tag on the
> `Shard` line. Do not read, comment on, label, or otherwise mutate rows
> in the other buckets — another terminal owns them and there is no claim
> protocol to stop you both.
>
> Use `/planning:interview` to drive an escalated question to a decision,
> and write the answer back as a comment on the item — the decision lives
> on the tracker, not in this session.
>
> **Work-class labels: you propose, I apply.** The autonomy contract
> forbids any repo-local agent-writable surface from supplying the class
> used for admission, and a label you write is exactly that surface. You
> never run the label command yourself — not even to transcribe a trailer
> I already ratified. Hand me the exact command to paste.
>
> Many items carry an operator-ratified trailer in the body, of the form
> `Work-class: C3 (bug-fix-shaped) — attended triage <date>,
> operator-ratified`. Grep for it before judging anything; never classify
> from a title. Give me one line per item mapping trailer to label, plus
> the ready-to-paste command:
>
> `gh issue edit <numbers> --add-label "<label>"`
>
> Resolve the exact label strings live rather than assuming them — the
> prefix, casing, and spacing are per-repository, and a guessed string
> either errors or creates a stray label. Run
> `gh label list --limit 200 | grep -i work-class` at the start of the
> session and use what it returns, mapping C1 through C5 onto the five
> members in ascending risk order.
>
> **If that returns nothing, do not stop.** The merge partition accepts a
> recorded class from the item **body or** labels, so a repository with no
> label axis is still merge-capable through body trailers. Report the
> absence once, then keep working the queue: grep the trailers, propose
> classes for untrailered items, and record ratified classes as body
> trailers instead of labels. Only the label-writing half is unavailable —
> triage, classification, and escalation all still apply.
>
> For an item with no trailer, propose a class with your reasoning and
> wait. Two traps: `mechanical` is narrow — deterministic, trivially
> reversible maintenance such as dependency bumps, lint, format, sync —
> and a change to any path listed on the `Runtime surfaces` line is not
> mechanical no matter how doc-shaped it looks.
>
> **The boundary is fail-closed.** Treat a doc-shaped path as runtime
> unless you can show nothing loads it — and a link grep is not that proof:
> skill bodies also load files through bare `Read <path>` directives and
> globs no link pattern returns. Anything you cannot prove inert is not
> mechanical. Fail toward the higher class.
>
> Never route a `work-class:` label through `/work-items:track` — that
> path validates against a taxonomy that does not yet carry the axis.
>
> **=== COPY TO HERE ===**

---

## Known gaps that outlive any one repository

- **No relaunch owner.** Nothing restarts a stopped lane; a cycle-budget
  hit, crash, or harness restart writes a restart-request to a surface
  with no consumer. `/schedule` is the wrong fix — it creates cloud
  Routines with no access to local checkouts. A local option is a
  scheduled headless `claude -p` reading each lane's telemetry
  `restart_request`.
- **Account rotation is undetectable.** The rate-limit tee carries no
  account identifier and is last-writer-wins. Rotate only at session
  boundaries, never mid-cycle, or a fresh account's healthy windows get
  fed to a lane running on an exhausted one.
- **C2 auto-merge may lack its promotion evidence.** The autonomy matrix
  specifies ≥20 autonomous C2 completions over ≥14 days with 100%
  deterministic-gate pass and 0 human-reverted merges before the C2
  auto-merge cell is eligible. Adoption of the tracked config is the
  loop-lane convention's ratification path, but the evidence predicate is
  separate — check whether your repo has it before treating auto-merge as
  earned rather than merely enabled.

---

## Profile: melodic-software/claude-code-plugins

Filled instance for the repository in use as of 2026-07-25.

| Variable | Value |
|---|---|
| `{{REPO}}` | `melodic-software/claude-code-plugins` |
| `{{TIER}}` | `autopilot` |
| `{{STOP}}` | `--drain` |
| `{{RUNTIME_SURFACES}}` | see below — derived, not a two-glob list |

- Runtime surfaces: **not** just `SKILL.md` and `reference/*.md`. Under the
  fail-closed definition above, `plugins/**` holds 875 markdown files, of
  which 128 are `CHANGELOG.md`/`README.md`; the remaining **747 are runtime**
  — `SKILL.md`, `agents/*.md` (the six installed reviewer agents among them),
  `context/**` (57 directories), `references/**`, nested `reference/**`, and
  `templates/**`. Re-run the command rather than reusing these numbers; they
  move with every plugin added.
- Merge rung: `c2-mechanical`, live in tracked config on `main`. Raising to
  `c3-autonomous` is a one-line edit to `.claude/source-control.md`.
- Work-class labels: deployed. Exact strings, ascending risk:
  `work-class: read-only`, `work-class: mechanical`, `work-class: scoped`,
  `work-class: structural`, `work-class: untrusted-provenance`.
- Stamped `agent-ready` items, re-counted live on 2026-07-25: **44 open, all
  44 label-stamped** — 7 `mechanical`, 32 `scoped`, 5 `structural` (33 of
  them also carry a body trailer). At `c2-mechanical` only the 7 are
  merge-eligible; at `c3-autonomous`, 39. These move as the backlog drains —
  re-run the union count rather than quoting this line.
- No autonomy binding file exists, so the C2 promotion evidence above is
  not recorded here.
- `#820` carries `do-not-merge`; its body embeds a veto-before-merge
  clause.
- Open lane issues: #1288–#1295.

### Tier is not the rung

`autopilot` is the maximum the prompt can set. It widens six of the seven
autonomy dimensions — discovery scope, fixing, thread resolution, draft
elevation, barrier handling, escalation posture. It does **not** touch
merge authority, which is floored at whatever the tracked config says and
can only be lowered by an argument, never raised.

So the two knobs are independent, and both are needed for "merge things
overnight without me":

- **Tier `autopilot`** — in the prompt below. Already maximal.
- **Merge rung** — one line in `.claude/source-control.md` on `main`.
  Currently `c2-mechanical`. Change to `c3-autonomous` and 39 of the 44
  open `agent-ready` items become eligible instead of 7.

`full-autonomy` as a rung adds only C4 `structural` and C5
`untrusted-provenance` on top of `c3-autonomous` — refactors, migrations,
contract changes, and fork PRs. That is the category least suited to
landing unattended, for near-zero throughput gain over c3. Recommend
`c3-autonomous`.

Neither rung bypasses classification: an item with no work-class label is
ineligible at every rung including `full-autonomy`.

---

## Ready to paste — melodic-software/claude-code-plugins

All placeholders filled. One worker lane, one merge lane, on different
machines; neither on the attended box.

### Worker lane — launch from a checkout of the repo

> **=== COPY FROM HERE ===**
>
> /loop /work-items:work-loop
>
> Repository: `melodic-software/claude-code-plugins`
>
> **Standing authorization.** Autonomous lane. These standing rules are
> the direction that `/work-items:triage`'s mutation gate and the
> self-observation filing contract require: triage, classify, label,
> comment, file follow-up items, claim items, author branches and PRs —
> all without a human turn. Prefix every comment and item you create with
> the AI disclaimer specified by triage. You never merge.
>
> **Discipline.** Every cycle, and every dispatch brief you compose at
> every nesting depth, invokes `/discipline:sweep-all`. Do not enumerate
> the individual disciplines — that skill resolves its own membership and
> a hand-copied list drifts. If the `discipline` plugin is not installed
> here, inline the equivalent standing instructions instead: verify claims
> against authoritative sources before acting, prefer installed skills
> over ad-hoc approaches, and re-check work against the active
> conventions.
>
> **Return contract, every subagent, every depth.** Return at most two
> lines: a verdict token and an identifier or path. Everything else goes
> to a file in your worktree or a comment on the item. Do not summarize
> your work back to me. Speak to me only when fully blocked and unable to
> escalate through the tracker.
>
> **Work classes are not yours to set.** The autonomy contract is
> explicit: "no repo-local (agent-writable) surface may supply the class
> used for admission." Never apply or change a `work-class:` label. An
> item without one still goes through the admission gate's own
> classification, and a candidate the gate cannot confidently classify
> fails closed to human-gated and is escalated, never worked. What the
> missing label costs is merge eligibility only. List unstamped items in
> your cycle report.
>
> **Worktrees are not yours to remove.** The worker's worktree persists
> through the whole PR lifecycle and is cleaned up only by whoever merges
> — never mid-lifecycle, never by this lane. Report accumulation instead.
>
> **Prefer single shell invocations** over `for` loops and `&&` chains
> where a single call would do: the auto-mode classifier blocks compound
> forms and nobody is awake to approve a retry. Preference, not
> prohibition — code a skill mandates verbatim, including the telemetry
> upsert block, runs exactly as written.
>
> **=== COPY TO HERE ===**

### Merge lane — any machine except the attended one

> **=== COPY FROM HERE ===**
>
> /loop /source-control:babysit-loop melodic-software/claude-code-plugins autopilot --drain
>
> Repository: `melodic-software/claude-code-plugins`
>
> **Standing authorization.** Autonomous lane. Advance PRs, fix
> branch-owned CI and review failures, resolve outdated bot threads, and
> merge within whatever rung the repository's tracked config resolves. You
> never claim backlog items and never author work-item PRs — that is the
> worker lane's authority.
>
> **PR ordering.** Ordering only, never eligibility — eligibility is the
> skill's deterministic partition and nothing here overrides it. Within
> the eligible set, prefer PRs that unblock other work, then oldest.
>
> **Escalation.** When a PR is stuck — merge conflict, a decision you
> cannot make from the item and the diff, a barrier the tier permits
> attempting — dispatch the conflict subagent at the frontier capability
> tier, as the skill requires, and never below it. Before acting on a
> non-trivial resolution, get a second opinion from an independent
> subagent that did not produce it. If the two disagree, escalate rather
> than pick.
>
> **Discipline.** Every dispatch brief at every depth invokes
> `/discipline:sweep-all`. If that plugin is absent here, inline the
> equivalent standing instructions instead.
>
> **Return contract.** Subagents return at most two lines — verdict plus
> identifier. Speak to me only when fully blocked.
>
> **Work classes are not yours to set.** Never apply or change a
> `work-class:` label to make a PR merge-eligible. A PR whose close-linked
> item carries no work class is not eligible at any rung, including
> full-autonomy. That is the correct outcome, not an obstacle: report it
> and move on. Manufacturing your own merge eligibility is the one thing
> this lane must never do.
>
> **Contention.** A worker lane authoring PRs here is expected and is not
> contention. Apply the skill's own per-PR foreign-activity suppression:
> yield on the specific PR showing unaccounted same-login activity, keep
> processing the rest. Stop the whole lane only if a second *merge* lane
> appears to be running against this repository.
>
> **Prefer single shell invocations** over `for` loops and `&&` chains
> where a single call would do. Preference, not prohibition — code a skill
> mandates verbatim runs exactly as written.
>
> **=== COPY TO HERE ===**

### Attended queue — melo-desk-001

Change the `Shard` line per terminal. Suggested split across five:
`[ratify]`, `[escalated]`, `[intake]` evens, `[intake]` odds, and one
floater working whatever backs up.

> **=== COPY FROM HERE ===**
>
> /work-items:attend-queue
>
> Repository: `melodic-software/claude-code-plugins`
> Shard: `[ratify]`
> Runtime surfaces in this repo: **every markdown file under `plugins/`
> except `CHANGELOG.md` and `README.md`** — 747 of 875 at last count. That
> is the boundary: `SKILL.md`, `agents/*.md`, `commands/*.md`, and every
> `reference/**`, `references/**`, `context/**`, `templates/**` file at any
> depth. Treat a path as runtime unless you can show nothing loads it.
>
> I am present. Recommend, then wait for my direction before mutating.
>
> **Stay inside your shard.** Work only rows carrying the tag on the
> `Shard` line. Do not read, comment on, label, or otherwise mutate rows
> in the other buckets — another terminal owns them and there is no claim
> protocol to stop you both.
>
> Use `/planning:interview` to drive an escalated question to a decision,
> and write the answer back as a comment on the item — the decision lives
> on the tracker, not in this session.
>
> **Work-class labels: you propose, I apply.** The autonomy contract
> forbids any repo-local agent-writable surface from supplying the class
> used for admission, and a label you write is exactly that surface. You
> never run the label command yourself — not even to transcribe a trailer
> I already ratified. Hand me the exact command to paste.
>
> Many items carry an operator-ratified trailer in the body, of the form
> `Work-class: C3 (bug-fix-shaped) — attended triage <date>,
> operator-ratified`. Grep for it before judging anything; never classify
> from a title. Give me one line per item mapping trailer to label, plus
> the ready-to-paste command:
>
> `gh issue edit <numbers> --add-label "<label>"`
>
> The five labels in this repository, ascending risk:
> `work-class: read-only`, `work-class: mechanical`, `work-class: scoped`,
> `work-class: structural`, `work-class: untrusted-provenance`.
>
> For an item with no trailer, propose a class with your reasoning and
> wait. Two traps: `mechanical` is narrow — deterministic, trivially
> reversible maintenance such as dependency bumps, lint, format, sync —
> and a change to any path on the `Runtime surfaces` line is not mechanical
> no matter how doc-shaped it looks, because those are runtime here.
>
> **The boundary is fail-closed.** A markdown path under `plugins/` is
> runtime unless you can show nothing loads it — and a link grep is not that
> proof: skill bodies also load files through bare `Read <path>` directives
> and globs no link pattern returns. `CHANGELOG.md` and `README.md` are the
> only reliably inert names. Anything else you cannot prove inert is not
> mechanical. Fail toward the higher class.
>
> Never route a `work-class:` label through `/work-items:track` — that
> path validates against a taxonomy that does not yet carry the axis.
>
> **=== COPY TO HERE ===**
