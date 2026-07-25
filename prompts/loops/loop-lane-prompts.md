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

**Run the whole profile from a checkout of `{{REPO}}`.** Every `gh` command
below reads the *ambient* repository when given no `--repo`, so profiling from
a neutral directory or a sibling checkout silently describes the wrong backlog
— and these counts feed the rung decision. The `.work-item-tracker.json` and
`.claude/source-control.md` reads need that working directory anyway. If you
must profile from elsewhere, add `--repo {{REPO}}` to **every** `gh` read below
without exception; one bare command is enough to mix two repositories' numbers
into one profile.

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

  The taxonomy is strict about how that resolution fails: an **absent** file
  or entry defaults *with a loud warning*, while a **present but malformed**
  entry — null, empty, or not a string — is a configuration error and never
  permission to fall back silently. A bare `//` default collapses both cases
  into a silent substitution, which is the failure mode that queries the
  wrong population and reports an empty backlog as fact.

  ```bash
  ROLE=$(jq -er '
    if has("config") and (.config | has("role_labels"))
         and (.config.role_labels | has("autonomous-eligible"))
    then .config.role_labels."autonomous-eligible"
         | if type == "string" and length > 0 then .
           else "MALFORMED" | halt_error(1) end
    else "" end' .work-item-tracker.json) || {
      echo "role_labels.autonomous-eligible is malformed — fix the binding" >&2
      exit 1
    }
  if [ -z "$ROLE" ]; then
    echo "WARNING: no autonomous-eligible mapping; defaulting to agent-ready" >&2
    ROLE=agent-ready
  fi
  ```

- **Is a classification source present, and how many items carry one?** The
  merge partition reads "the triage stamp in the item body **or** labels" —
  either satisfies it, so count the **union**, never one source alone. A
  label-only repo returns zero on a body-only count and vice versa; either
  in isolation under-reports the merge-eligible population and feeds the rung
  decision a wrong number.

  Match the **canonical grammar**, not a loose substring. The vocabulary is
  C1–C5, so `C[0-9]` also counts a stray `Work-class: C9`, and a bare
  `work-class` label test counts an unrelated `work-class: pending`. Both
  inflate a readiness number the rung decision then trusts. Anchor the trailer
  to line start and compare labels against the five strings `gh label list`
  actually returned — substitute them into `VALID` below:

  ```bash
  gh label list --limit 200 | grep -i work-class
  # Substitute the five strings the command above actually returned.
  VALID='["work-class: read-only","work-class: mechanical","work-class: scoped",
          "work-class: structural","work-class: untrusted-provenance"]'
  LIMIT=500
  gh issue list --label "$ROLE" --limit "$LIMIT" --json number,body,labels \
    | jq --argjson valid "$VALID" --argjson limit "$LIMIT" '
        {fetched: length,
         truncated: (length >= $limit),
         classified: [.[] | select(
           (.body | test("(^|\\n)Work-class: C[1-5]( |\\r|\\n|$)"))
           or (any(.labels[].name; . as $n | $valid | index($n)))
         )] | length}'
  ```

  Two mechanics worth not rediscovering. `gh issue list` has **no
  `--argjson`** — pipe to `jq` instead of using `--jq`. And jq's regex engine
  does **not** honor `(?m)`, so the trailer is anchored with `(^|\n)`.

  The trailing `( |\r|\n|$)` is a **token boundary, not merely a non-digit**:
  it rejects `C12` after matching `C1`, and equally rejects `C2foo` and `C3?`,
  which a `[^0-9]` guard would have counted as canonical. Every widening of
  this pattern inflates the readiness count the rung decision trusts, so keep
  it strict — the canonical trailer always continues with a space or ends the
  line.

  Both line-ending alternatives are load-bearing, and both are easy to drop as
  redundant. Because the engine is not multiline, `$` means end of the whole
  body, so a bare `Work-class: C2` followed by any further body section
  matches only via `\n`; and a CRLF body needs `\r` (measured on this
  repository: 7 issue bodies and 5 PR bodies carry CR). Omit either and a
  body-stamp repo under-reports, to the point of reporting zero.

  **`--limit` is a ceiling, not an all-pages switch.** It is documented as
  "maximum number of issues to fetch", and its default is 30 — so an
  unbounded call silently under-reports any backlog past thirty, and a
  `--limit 500` call silently under-reports one past five hundred. Raising
  the number only moves the cliff. That is why the command reports
  `truncated` alongside the count: **if `truncated` is true the classified
  figure is a floor, not a total, and is not safe to feed a rung decision** —
  raise `LIMIT` and re-run until it reports false. (`gh api --paginate`
  fetches every page, but returns raw REST issues without the `gh`-computed
  fields this query reads, so the explicit ceiling plus a truncation flag is
  the honest shape here.)

  A repository that records classifications only as body trailers is fully
  merge-capable and needs no label provisioning. Conclude "nothing can merge"
  only when the union is empty.
- **`{{RUNTIME_SURFACES}}`** — paths that look like documentation but are
  loaded by an agent at run time. This drives classification: a change to a
  runtime surface is never mechanical, so an under-listed value is a safety
  hole, not a cosmetic omission — it lets a behavioral change be stamped C2
  and merged unattended.

  **Define it fail-closed: every tracked `.md` in the repository is runtime
  until proven inert.** A forward derivation — grep the skill bodies for what
  they load, then treat the results as the boundary — is tempting and is wrong
  twice over. It misses every load directive that is not a markdown link (bare
  `Read references/shared/*.md` lines, glob directives, paths built at run
  time), and any pattern that strips the originating file yields ambiguous
  bare names: `context/audit.md` alone names three different runtime files
  in this repo. A boundary that silently under-reports is worse than no
  boundary, because it reads as coverage.

  So invert it. **The whole tracked `.md` set is the boundary**; subtraction
  is per path and needs proof:

  ```bash
  git ls-files '*.md'
  ```

  **A plugin tree is not the outer edge.** Some of the most behavioral
  Markdown sits outside it: `.claude/source-control.md` supplies the merge
  rung this very profile reads, and a root `CLAUDE.md` (or `AGENTS.md`)
  supplies operating rules every agent loads. Start the boundary at
  `plugins/` and an issue changing either one is ordinary documentation —
  stamped C2 and merged unattended while it changes lane or agent behavior.

  **No filename is inert by convention — `README.md` least of all.** In this
  repo `tools/work-item-tracker/adapters/github/README.md` is the GitHub
  adapter's operations reference: `reference/tracker-seam.md` routes every
  provider-specific operation to it, and `skills/work/SKILL.md` consults it
  for the open-linked-PR query. Editing it changes lane behavior. A blanket
  `README.md` exclusion would have let exactly that edit be stamped C2 and
  merged unattended — the same hole in a new coat.

  Subtract a path only after showing nothing loads it: no skill body, agent,
  or command references it by link, by bare `Read` directive, by glob, or by
  `${CLAUDE_PLUGIN_ROOT}`-relative path. That is a per-path proof, never a
  filename or directory-name rule. In an application repo the set may be
  genuinely empty — but prove that, do not assume it.

## Adopting a new repository

1. Land `babysit_loop_*` keys in that repo's tracked
   `.claude/source-control.md` on the default branch. Without this the
   merge lane runs and merges nothing.
2. Decide where this repository records work classes. The merge partition
   accepts **either** an issue-body trailer **or** a label, so a repo may
   adopt on body trailers alone and never provision a label axis. Check what
   is already there — from a checkout of the target, or with an explicit
   `--repo`, for the same reason the profile above states:
   `gh label list --repo <owner/name> --limit 200 | grep -i work-class`, plus
   the body-trailer count from the profile's union command.
3. **Only if you want the label axis** — it is optional, not a prerequisite —
   provision it before stamping, and **never from a lane**: no lane creates
   labels, and discovery never implies write permission. Route by what the
   target repository declares, rather than assuming an owner:
   - **It declares a label-management source of truth** (a label-as-code repo,
     a documented process) — route the change there and keep every lane action
     read-only. Melodic repositories declare `github-iac`; that is this org's
     answer, not a portable one, so resolve the target's own declaration.
   - **It declares none** — creating a label needs the user's explicit
     authorization plus the repository's documented contribution process. Ask;
     do not run `gh label create` on your own initiative.

   Whichever path, the five members are aliases of the autonomy program's
   C1–C5 risk classes, with the alias map single-sourced in the label
   declarations.
4. Stamp the autonomous-eligible items in whichever source this repo uses, or
   accept that nothing auto-merges. An item with no recorded class in
   **either** source is ineligible at every rung.
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
- **Worker lane and attended queue both launch from a checkout** of
  `{{REPO}}`. Only the merge lane may launch anywhere — it takes `owner/repo`
  as an argument and reads the target's config over the API. Neither
  `/work-items:work-loop` nor `/work-items:attend-queue` accepts a repository
  argument: both resolve `.work-item-tracker.json` and every provider
  operation from the working directory. A `Repository:` line in the prompt is
  documentation for the reader, **not** a binding — an attended session
  started from `$HOME` or a sibling repo either stops on a missing binding or,
  worse, reads and mutates whichever repository it happens to be sitting in.
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

**A `sonnet` root silently makes every implementer `sonnet` too.** The
`model` frontmatter field defaults to `inherit`, and neither `/work-items:work`
nor `implement-dispatch` sets one, so subagents dispatched from a
`--model sonnet` root run Sonnet — not the strong tier this section promises.
The three tiers above are aspirational unless something overrides that
inheritance. Resolution order is: `CLAUDE_CODE_SUBAGENT_MODEL`, then the
per-invocation `model` parameter, then frontmatter, then the main
conversation's model
(<https://code.claude.com/docs/en/sub-agents>, verified 2026-07-25).

Two ways to make the tiering real. Prefer the per-dispatch instruction —
`CLAUDE_CODE_SUBAGENT_MODEL` is a blunt floor that would also pull mechanical
greps up off `haiku`:

- **Per-dispatch (recommended).** The lane bodies below carry a standing
  dispatch-model rule. Because `/loop` re-sends the prompt each iteration,
  that rule survives compaction — a rule stated once in conversation does not.
- **Environment floor.** Export `CLAUDE_CODE_SUBAGENT_MODEL=opus` for that
  lane's shell. It wins over everything, including a deliberate `haiku`
  per-dispatch choice, so it costs the fast tier entirely.

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
> Runtime surfaces in this repo: `{{RUNTIME_SURFACES}}`
>
> **Standing authorization.** Autonomous lane. These standing rules are
> the direction that `/work-items:triage`'s mutation gate and the
> self-observation filing contract require: triage, classify, label,
> comment, file follow-up items, claim items, author branches and PRs —
> all without a human turn. Prefix every comment and item you create with
> the AI disclaimer specified by triage. You never merge.
>
> **Discipline.** Invoke `/discipline:sweep-all` **once per cycle, at the
> cycle root only** — never inside a dispatch brief, and never from a
> subagent. That skill fans out one audit fork per corrector itself, so a
> brief that re-invokes it has each fork start another full sweep, and so on
> down: the fan-out multiplies with depth and burns worker slots and rate
> limit before any lane work runs. Dispatched subagents inherit the posture
> the root sweep already set; they do not re-run it. Do not enumerate the
> individual disciplines either — that skill resolves its own membership and
> a hand-copied list drifts. If the `discipline` plugin is not installed
> here, inline the equivalent standing instructions instead: verify claims
> against authoritative sources before acting, prefer installed skills
> over ad-hoc approaches, and re-check work against the active
> conventions.
>
> **Dispatch model, every dispatch.** Your root runs on the fast tier and
> subagents inherit it by default, so an unqualified dispatch silently runs
> an implementer at orchestrator strength. Pass an explicit per-invocation
> `model` on every dispatch: `opus` for anything that reads or edits source,
> writes a PR, or makes a judgment call; `fable` for conflict resolution and
> any security-surface work class, unconditionally; `haiku` only for
> mechanical greps and log pulls. Never leave it to inherit.
>
> **Return contract, every subagent, every depth.** Return at most two
> lines: a verdict token and an identifier or path. Everything else goes
> to a file in your worktree or a comment on the item. Do not summarize
> your work back to me. Speak to me only when fully blocked and unable to
> escalate through the tracker.
>
> **One exception: a skill that defines its own return shape wins.** Where a
> skill's contract specifies what its subagents return, that contract governs
> and this two-line rule does not apply — `/discipline:sweep-all`'s audit
> forks are the live case: they must return a full findings ledger (each
> located finding plus its proposed remedy) and are explicitly forbidden to
> write files, so both halves of the rule above would break it. Truncating
> such a return to two lines silently discards the data the parent needs to
> act on.
>
> **Work classes are not yours to set — in either surface.** The autonomy
> contract is explicit: "no repo-local (agent-writable) surface may supply
> the class used for admission." Never apply or change a `work-class:`
> label, **and never write a `Work-class: C<n>` trailer into an item body.**
> Your standing authorization to triage and classify does not reach these:
> the merge partition reads the class from body or labels alike, so writing
> either one is you manufacturing merge eligibility for a PR you authored.
> That is the single thing this lane must never do — it is a self-certifying
> producer, and it is why the contract names agent-writable surfaces rather
> than naming labels. Propose a class in your cycle report and leave the
> recording to the attended queue's operator.
>
> An item without a recorded class still goes through the admission gate's
> own classification, and a candidate the gate cannot confidently classify
> fails closed to human-gated and is escalated, never worked.
>
> **That gate needs the runtime boundary, so it is on the `Runtime surfaces`
> line above.** A change to any path in it is **never mechanical**, however
> doc-shaped it looks — those paths are loaded by an agent at run time, so
> editing one changes behavior. Without the boundary the gate would judge
> such an item C2 and admit it autonomously. The boundary is fail-closed:
> a path is runtime unless you can show nothing loads it, per path, and a
> link grep is not that proof — bare `Read <path>` directives, globs, and
> `${CLAUDE_PLUGIN_ROOT}`-relative paths return from no link pattern. When
> you cannot prove a path inert, classify to the higher class.
>
> **A missing label is not a missing class.** The merge partition accepts a
> recorded class from the item **body or** labels, so an item carrying a
> `Work-class: C<n>` body trailer is merge-eligible with no label at all.
> Report an item as unstamped only when **both** sources are empty —
> reporting body-stamped items as unstamped drives label provisioning that
> nothing needs. List genuinely unclassified items in your cycle report.
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
> **Discipline.** Invoke `/discipline:sweep-all` **once per cycle, at the
> cycle root only** — never inside a dispatch brief, and never from a
> subagent. That skill fans out its own audit fork per corrector, so
> re-invoking it inside a brief multiplies the fan-out with every nesting
> level. Dispatched subagents inherit the posture the root sweep set. If that
> plugin is absent here, inline the equivalent standing instructions instead.
>
> **Dispatch model, every dispatch.** Your root runs on the fast tier and
> subagents inherit it by default, so the frontier-tier conflict worker this
> skill requires would silently run at orchestrator strength unless you say
> otherwise. Pass an explicit per-invocation `model`: `fable` for conflict
> resolution and every security-surface work class, unconditionally; `opus`
> for CI fixes, review-comment work, and any judgment call; `haiku` only for
> mechanical log pulls. Never leave it to inherit.
>
> **Return contract.** Subagents return at most two lines — verdict plus
> identifier. Speak to me only when fully blocked. **A skill that defines its
> own return shape wins over this rule** — `/discipline:sweep-all`'s audit
> forks owe a full findings ledger and may write nothing, so truncating them
> to two lines would discard exactly what the parent acts on.
>
> **Work classes are not yours to set — in either surface.** Never apply or
> change a `work-class:` label, **and never write a `Work-class: C<n>`
> trailer into an item body**, to make a PR merge-eligible. You read the
> class from body or labels alike, so writing either is you authoring the
> input to your own merge decision. A PR whose close-linked item carries no
> recorded class in either source is not eligible at any rung, including
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

**Launch every terminal from a checkout or worktree of `{{REPO}}`.**
attend-queue takes no repository argument and binds to its working directory;
the `Repository:` line below documents intent, it does not target anything.
Since the shards below want several terminals at once and two lanes must never
share a working directory, give each terminal its own worktree.

Human-in-the-loop, no `/loop` wrapper. attend-queue has no shard parameter
and no row-level claim, so `{{SHARD}}` is operator convention rather than
enforcement. Give each terminal a different value.

**`{{SHARD}}` must be a predicate the queue's own rows can satisfy.** The
attention view tags every row with exactly one of three kinds — `[escalated]`,
`[ratify]`, `[intake]`. Nothing emits a compound tag, so a value like
`[intake] evens` matches no row and that terminal silently works nothing.
Split beyond three terminals with an explicit predicate over a property the
row actually carries — item number parity is the reliable one:

- `[intake] where item number is even`
- `[intake] where item number is odd`

**Never define a floater or any overlapping bucket.** With no row-level
claim, two terminals whose predicates intersect will mutate the same rows
concurrently. Shards must partition, not overlap.

**Sharding costs you lane telemetry.** attend-queue upserts its pass report
into one comment keyed by a fixed marker, and that upsert reconciles
duplicate comments rather than merging concurrent bodies — the last terminal
to PATCH overwrites every other shard's report. The skill offers no per-shard
marker, so the only safe answers are: run one terminal and keep telemetry, or
shard and have every terminal skip the upsert. The prompts below take the
second, since sharding is the reason to be here. Do not split the difference —
letting one "primary" shard write it records a partial pass as the whole.

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
> **Stay inside your shard.** The `Shard` line is a **full predicate**, not
> just a tag: evaluate every clause of it. A row qualifies only when it
> carries the named tag **and** satisfies any further condition on that line
> — so `[intake] where item number is odd` selects odd-numbered `[intake]`
> rows only, and matching the tag alone would put you on a sibling
> terminal's rows. Do not read, comment on, label, or otherwise mutate any
> row your full predicate does not select: another terminal owns it and
> there is no claim protocol to stop you both.
>
> **Do not write lane telemetry.** Every attend-queue session upserts its
> pass report into ONE comment keyed by a fixed marker, and the upsert
> reconciles duplicate comments rather than merging concurrent bodies — so
> with several shards running, the last terminal to PATCH silently erases
> every other shard's handled-row and guard-mode report. Skip the telemetry
> upsert entirely and put your pass report in this session instead. Only a
> single-terminal attended session may write it.
>
> Use `/planning:interview` to drive an escalated question to a decision
> **when the `planning` plugin is installed here**; otherwise ask the
> focused questions inline, one at a time, most load-bearing first — the
> same fallback attend-queue itself specifies, since `work-items` installs
> independently of `planning` and an unconditional invocation would just
> stall every escalated row. Either way, write the answer back as a comment
> on the item — the decision lives on the tracker, not in this session.
>
> **Work classes: you propose, I apply — labels and body trailers alike.**
> The autonomy contract forbids any repo-local agent-writable surface from
> supplying the class used for admission. A label you write is exactly that
> surface, **and so is an item body you edit** — `babysit-loop` reads the
> class from either one. You never run the label command yourself, and never
> write a `Work-class: C<n>` trailer into a body — not even to transcribe a
> class I already ratified. Hand me the exact command to paste, for whichever
> surface this repository records classes in.
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
> classes for untrailered items, escalate, and triage.
>
> **You never write the class into the body either.** The body is a
> repo-local agent-writable surface exactly as the label is, and
> `babysit-loop` reads the trailer to decide merge eligibility — so an agent
> writing a trailer is an agent manufacturing its own merge eligibility, the
> one thing the admission rule forbids. Hand me the exact body-edit command
> to paste, the same way you hand me the label command.
>
> For an item with no trailer, propose a class with your reasoning and
> wait. Two traps: `mechanical` is narrow — deterministic, trivially
> reversible maintenance such as dependency bumps, lint, format, sync —
> and a change to any path listed on the `Runtime surfaces` line is not
> mechanical no matter how doc-shaped it looks.
>
> **The boundary is fail-closed.** Treat a doc-shaped path as runtime
> unless you can show nothing loads it — and a link grep is not that proof:
> skill bodies also load files through bare `Read <path>` directives, globs,
> and plugin-root-relative paths no link pattern returns. **No filename is
> inert by convention**, `README.md` included — an adapter or tool README is
> frequently an operations reference a skill consults at run time. Anything
> you cannot prove inert per path is not mechanical. Fail toward the higher
> class.
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

- Runtime surfaces: **not** just `SKILL.md` and `reference/*.md`, and not
  bounded by `plugins/` either. Under the fail-closed definition above,
  **every tracked markdown file** (`git ls-files '*.md'`) is runtime for
  classification until individually proven inert. The plugin tree is the bulk
  — `SKILL.md`, `agents/*.md` (the six installed reviewer agents among them),
  `context/**` (57 directories), `references/**`, nested `reference/**`, and
  `templates/**` — but the two most behavioral files sit outside it:
  `.claude/source-control.md` supplies the merge rung, and root `CLAUDE.md`
  supplies the operating rules every agent in this repo loads. Not even
  `README.md` is safe to exclude by name here:
  `tools/work-item-tracker/adapters/github/README.md` is the GitHub adapter's
  operations reference, loaded by `reference/tracker-seam.md` and
  `skills/work/SKILL.md`. Re-run the listing rather than reusing a count; it
  moves with every plugin added.
- Merge rung: `c2-mechanical`, live in tracked config on `main`. Raising to
  `c3-autonomous` is a one-line edit to `.claude/source-control.md` — a
  mechanically trivial one the guardrail matrix does not currently authorize
  (see "Tier is not the rung" below).
- Work-class labels: deployed. Exact strings, ascending risk:
  `work-class: read-only`, `work-class: mechanical`, `work-class: scoped`,
  `work-class: structural`, `work-class: untrusted-provenance`.
- Stamped `agent-ready` items: **every open one carries a class label**, and
  the population is overwhelmingly `scoped`, with `mechanical` and
  `structural` in low single digits. At `c2-mechanical` only the `mechanical`
  handful is merge-eligible; at `c3-autonomous`, nearly all of them.

  **No absolute count is recorded here, deliberately.** Over one day of
  authoring this document the open count read 50, 44, 40, 38, 28, then 25 —
  it fell by three *between two commands in the same session*, because the
  worker lane drains it continuously. Any number written here is wrong before
  it is read. Run the union command above and use what it returns; a rung
  decision made from a quoted figure is a decision about a repository that no
  longer exists.
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
  Currently `c2-mechanical`. Changing it to `c3-autonomous` takes the
  eligible set from the `mechanical` handful to nearly the whole open
  `agent-ready` backlog — run the union command for the live figures rather
  than trusting a number written here. Whether that raise is
  *authorized* is a separate question from whether the seam supports it: the
  guardrail matrix sets C3 merge policy to `human merge` and lists no C3
  auto-merge promotion cell, so the flip is filed as an operator decision
  rather than a ready edit.

`full-autonomy` as a rung adds only C4 `structural` and C5
`untrusted-provenance` on top of `c3-autonomous` — refactors, migrations,
contract changes, and fork PRs. That is the category least suited to
landing unattended, for near-zero throughput gain over c3, so `full-autonomy`
is never the answer here.

**But that ranking is not a recommendation to raise.** The governing policy
is `plugins/autonomy/reference/guardrails.md`'s matrix, which sets C3 merge
policy to `human merge`, and its promotion table, which defines an auto-merge
evidence predicate for C2 only — C3 has no auto-merge promotion cell at all.
Until that policy defines a C3 promotion path, **stay at `c2-mechanical`**:
the eligible-count arithmetic above says what the seam would do, not what
the contract permits. Raising the rung anyway is an operator decision to
override the matrix, and it belongs in a change to the policy first.

Neither rung bypasses classification: an item with **no recorded class in
either source** — no `Work-class: C<n>` body trailer and no `work-class:`
label — is ineligible at every rung including `full-autonomy`. A missing
label alone costs nothing where a trailer exists.

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
> Runtime surfaces in this repo: **every tracked markdown file**
> (`git ls-files '*.md'`) — the plugin tree is the bulk of it, plus
> `.claude/source-control.md` (this lane's merge rung) and root
> `CLAUDE.md` / `AGENTS.md`. No filename is exempt by convention:
> `tools/work-item-tracker/adapters/github/README.md` is the GitHub
> adapter's operations reference.
>
> **Standing authorization.** Autonomous lane. These standing rules are
> the direction that `/work-items:triage`'s mutation gate and the
> self-observation filing contract require: triage, classify, label,
> comment, file follow-up items, claim items, author branches and PRs —
> all without a human turn. Prefix every comment and item you create with
> the AI disclaimer specified by triage. You never merge.
>
> **Discipline.** Invoke `/discipline:sweep-all` **once per cycle, at the
> cycle root only** — never inside a dispatch brief, and never from a
> subagent. That skill fans out one audit fork per corrector itself, so a
> brief that re-invokes it has each fork start another full sweep, and so on
> down: the fan-out multiplies with depth and burns worker slots and rate
> limit before any lane work runs. Dispatched subagents inherit the posture
> the root sweep already set; they do not re-run it. Do not enumerate the
> individual disciplines either — that skill resolves its own membership and
> a hand-copied list drifts. If the `discipline` plugin is not installed
> here, inline the equivalent standing instructions instead: verify claims
> against authoritative sources before acting, prefer installed skills
> over ad-hoc approaches, and re-check work against the active
> conventions.
>
> **Dispatch model, every dispatch.** Your root runs on the fast tier and
> subagents inherit it by default, so an unqualified dispatch silently runs
> an implementer at orchestrator strength. Pass an explicit per-invocation
> `model` on every dispatch: `opus` for anything that reads or edits source,
> writes a PR, or makes a judgment call; `fable` for conflict resolution and
> any security-surface work class, unconditionally; `haiku` only for
> mechanical greps and log pulls. Never leave it to inherit.
>
> **Return contract, every subagent, every depth.** Return at most two
> lines: a verdict token and an identifier or path. Everything else goes
> to a file in your worktree or a comment on the item. Do not summarize
> your work back to me. Speak to me only when fully blocked and unable to
> escalate through the tracker.
>
> **One exception: a skill that defines its own return shape wins.** Where a
> skill's contract specifies what its subagents return, that contract governs
> and this two-line rule does not apply — `/discipline:sweep-all`'s audit
> forks are the live case: they must return a full findings ledger (each
> located finding plus its proposed remedy) and are explicitly forbidden to
> write files, so both halves of the rule above would break it. Truncating
> such a return to two lines silently discards the data the parent needs to
> act on.
>
> **Work classes are not yours to set — in either surface.** The autonomy
> contract is explicit: "no repo-local (agent-writable) surface may supply
> the class used for admission." Never apply or change a `work-class:`
> label, **and never write a `Work-class: C<n>` trailer into an item body.**
> Your standing authorization to triage and classify does not reach these:
> the merge partition reads the class from body or labels alike, so writing
> either one is you manufacturing merge eligibility for a PR you authored.
> That is the single thing this lane must never do — it is a self-certifying
> producer, and it is why the contract names agent-writable surfaces rather
> than naming labels. Propose a class in your cycle report and leave the
> recording to the attended queue's operator.
>
> An item without a recorded class still goes through the admission gate's
> own classification, and a candidate the gate cannot confidently classify
> fails closed to human-gated and is escalated, never worked.
>
> **That gate needs the runtime boundary, so it is on the `Runtime surfaces`
> line above.** A change to any path in it is **never mechanical**, however
> doc-shaped it looks — those paths are loaded by an agent at run time, so
> editing one changes behavior. Without the boundary the gate would judge
> such an item C2 and admit it autonomously. The boundary is fail-closed:
> a path is runtime unless you can show nothing loads it, per path, and a
> link grep is not that proof — bare `Read <path>` directives, globs, and
> `${CLAUDE_PLUGIN_ROOT}`-relative paths return from no link pattern. When
> you cannot prove a path inert, classify to the higher class.
>
> **A missing label is not a missing class.** The merge partition accepts a
> recorded class from the item **body or** labels, so an item carrying a
> `Work-class: C<n>` body trailer is merge-eligible with no label at all.
> Report an item as unstamped only when **both** sources are empty —
> reporting body-stamped items as unstamped drives label provisioning that
> nothing needs. List genuinely unclassified items in your cycle report.
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
> **Discipline.** Invoke `/discipline:sweep-all` **once per cycle, at the
> cycle root only** — never inside a dispatch brief, and never from a
> subagent. That skill fans out its own audit fork per corrector, so
> re-invoking it inside a brief multiplies the fan-out with every nesting
> level. Dispatched subagents inherit the posture the root sweep set. If that
> plugin is absent here, inline the equivalent standing instructions instead.
>
> **Dispatch model, every dispatch.** Your root runs on the fast tier and
> subagents inherit it by default, so the frontier-tier conflict worker this
> skill requires would silently run at orchestrator strength unless you say
> otherwise. Pass an explicit per-invocation `model`: `fable` for conflict
> resolution and every security-surface work class, unconditionally; `opus`
> for CI fixes, review-comment work, and any judgment call; `haiku` only for
> mechanical log pulls. Never leave it to inherit.
>
> **Return contract.** Subagents return at most two lines — verdict plus
> identifier. Speak to me only when fully blocked. **A skill that defines its
> own return shape wins over this rule** — `/discipline:sweep-all`'s audit
> forks owe a full findings ledger and may write nothing, so truncating them
> to two lines would discard exactly what the parent acts on.
>
> **Work classes are not yours to set — in either surface.** Never apply or
> change a `work-class:` label, **and never write a `Work-class: C<n>`
> trailer into an item body**, to make a PR merge-eligible. You read the
> class from body or labels alike, so writing either is you authoring the
> input to your own merge decision. A PR whose close-linked item carries no
> recorded class in either source is not eligible at any rung, including
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

Each terminal launches from its own worktree of the repo — attend-queue binds
to its working directory, and two lanes never share one.

Change the `Shard` line per terminal. A non-overlapping four-way split, each
value a predicate the attention view's own rows satisfy:

- `[ratify]`
- `[escalated]`
- `[intake] where item number is even`
- `[intake] where item number is odd`

No fifth floater — with no row-level claim, an overlapping bucket means two
terminals mutating the same row.

> **=== COPY FROM HERE ===**
>
> /work-items:attend-queue
>
> Repository: `melodic-software/claude-code-plugins`
> Shard: `[ratify]`
> Runtime surfaces in this repo: **every tracked markdown file**
> (`git ls-files '*.md'`) — the plugin tree is the bulk of it (`SKILL.md`,
> `agents/*.md`, `commands/*.md`, and every `reference/**`, `references/**`,
> `context/**`, `templates/**` file at any depth), but it is not the edge:
> `.claude/source-control.md` supplies this lane's merge rung, and root
> `CLAUDE.md` / `AGENTS.md` supply operating rules every agent loads. No
> filename is exempt by convention either: this repo's
> `tools/work-item-tracker/adapters/github/README.md` is the GitHub adapter's
> operations reference, so even a README edit here can change lane behavior.
> Treat a path as runtime unless you can show nothing loads it.
>
> I am present. Recommend, then wait for my direction before mutating.
>
> **Stay inside your shard.** The `Shard` line is a **full predicate**, not
> just a tag: evaluate every clause of it. A row qualifies only when it
> carries the named tag **and** satisfies any further condition on that line
> — so `[intake] where item number is odd` selects odd-numbered `[intake]`
> rows only, and matching the tag alone would put you on a sibling
> terminal's rows. Do not read, comment on, label, or otherwise mutate any
> row your full predicate does not select: another terminal owns it and
> there is no claim protocol to stop you both.
>
> **Do not write lane telemetry.** Every attend-queue session upserts its
> pass report into ONE comment keyed by a fixed marker, and the upsert
> reconciles duplicate comments rather than merging concurrent bodies — so
> with several shards running, the last terminal to PATCH silently erases
> every other shard's handled-row and guard-mode report. Skip the telemetry
> upsert entirely and put your pass report in this session instead. Only a
> single-terminal attended session may write it.
>
> Use `/planning:interview` to drive an escalated question to a decision
> **when the `planning` plugin is installed here**; otherwise ask the
> focused questions inline, one at a time, most load-bearing first — the
> same fallback attend-queue itself specifies, since `work-items` installs
> independently of `planning` and an unconditional invocation would just
> stall every escalated row. Either way, write the answer back as a comment
> on the item — the decision lives on the tracker, not in this session.
>
> **Work classes: you propose, I apply — labels and body trailers alike.**
> The autonomy contract forbids any repo-local agent-writable surface from
> supplying the class used for admission. A label you write is exactly that
> surface, **and so is an item body you edit** — `babysit-loop` reads the
> class from either one. You never run the label command yourself, and never
> write a `Work-class: C<n>` trailer into a body — not even to transcribe a
> class I already ratified. Hand me the exact command to paste, for whichever
> surface this repository records classes in.
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
> **The boundary is fail-closed.** Any tracked markdown path is runtime
> unless you can show nothing loads it — and a link grep is not that
> proof: skill bodies also load files through bare `Read <path>` directives,
> globs, and `${CLAUDE_PLUGIN_ROOT}`-relative paths no link pattern returns.
> **No filename is inert by convention**, `README.md` included — this repo's
> GitHub adapter README is loaded by `reference/tracker-seam.md`. Anything
> you cannot prove inert per path is not mechanical. Fail toward the higher
> class.
>
> Never route a `work-class:` label through `/work-items:track` — that
> path validates against a taxonomy that does not yet carry the axis.
>
> **=== COPY TO HERE ===**
