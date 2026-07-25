# D8 — Adversarial challenge of the 57 INLINE-ONLY verdicts

Premise under which this pass ran, supplied by the user and inverting the sweep's burden of proof:
**preserving the MAIN agent's context is the primary goal. If a skill would pollute main context it
dispatches, unless there is a real reason it cannot.** INLINE-ONLY is now the claim needing
justification.

Inputs: [`../LEDGER.md`](../LEDGER.md) rows and
[`../audit/B01.md`](../audit/B01.md)…[`B11.md`](../audit/B11.md) rationales. Per instruction,
`verify/reconciliation.md` and `verify/C.md` were **not** read.

---

## 1. The headline finding — one root cause, not twelve

Almost every live challenge below is the same defect:

> **Multi-action skills were graded on their heaviest action.** The verdict was set by the mutating
> or interactive action, and a read-only sibling action in the *same skill* — `audit`, `scan`,
> `dry-run`, `status`, `check`, `fetch` — carries **no blocker at all** and is where nearly all the
> context volume actually lands.

Eleven of the fourteen challenges below are instances. In several cases the skill's own text says
the read-only action is unblocked, in words, and the rationale did not engage with it:

| Skill | The skill's own words about its read-only action |
|---|---|
| `docs-hygiene:compress` | "Semantic-diff dispatch is mandatory for default action. **Audit is read-only — no dispatch.**" |
| `claude-ops:plugins` | "Read-only dry run… issues **zero** `plugin install\|update\|uninstall\|marketplace update` invocations" |
| `repo-hygiene:clean` | "`scan` … **read-only inventory.** Stop if action is `scan`" · Risk column: `Safe`, Pre-flight `No` |
| `code-tidying:tidy` | "`dry-run` … **Do NOT make edits. Do NOT branch. Do NOT push. Do NOT file tracker items.**" |
| `disk-hygiene:clean` | "Automated, scheduled, remote, unattended, or no-human-in-loop sessions **always audit and stop**" |
| `docs-hygiene:rename-references` | "Audit mode runs phases 1-3 only and reports — **no Edit calls.**" |
| `github:advise` | "A bare invocation of this skill performs **zero mutations**" (hard contract) |

That generalization is worth more than the individual rows: **it also predicts where the 31 rows I
did not open are most likely soft** — any INLINE-ONLY skill with an action router containing an
`audit` / `status` / `dry-run` / `check` row deserves a second look on the same grounds.

Two secondary patterns, both smaller:

- **A start-of-run question was treated as a mid-flow gate.** One intake question asked *before any
  work begins* is resolvable by the parent and passed into the brief. This is the criteria's own
  "mid-flow load-bearing" test failing to be applied. (`discovery:blindspot`,
  `docs-hygiene:rename-references` smart-default pair-pick.)
- **A `disable-model-invocation: true` frontmatter flag was cited as a reinforcing blocker** on five
  rows. It is a self-imposed configuration choice in the marketplace's own file, not a harness
  capability limit. See §6.

---

## 2. Honest coverage — read this before the counts

The artifact this pass audits was itself corrected once for an untiered coverage claim (C1: "21
rows, zero flips" → 13 tested / 8 summary-level / 15 untested). I will not repeat that shape.

Counts below were verified by script (extract the 57 row names from the checklist, intersect with the
files opened, diff), not hand-tallied.

| Tier | Count | What it means |
|---|---|---|
| **Opened the SKILL.md myself, full read** | 19 | Verdict below is mine, from primary text |
| **Opened the SKILL.md myself, targeted read** | 6 | Read the action router + the contested phase, not the whole file |
| **Not opened — judged on the batch rationale against the criteria only** | 32 | **Inherited, not independently verified** |
| **Total** | **57** | |

- **14 challenged** (all from the 25 I opened).
- **11 upheld after my own read** — including 3 where I judge the *stated reason* wrong and the
  *verdict* right, and 1 where I correct the checklist in the opposite direction.
- **32 upheld without independent verification.**

I also opened `/github:audit`, which is **not** one of the 57 (it is DISPATCH-DEFAULT); it is
excluded from every count above and read only for the §5.1 comparison.

**How much the 32 unopened rows should worry you — measured, not guessed.** I applied §1's own
predictor to them by script: grep each unopened SKILL.md for a read-only action token
(`audit` / `scan` / `dry-run` / `status` / `check` / `preview`) rendered as an action-router entry.
Across all 32 it returns **three** hits — `claude-memory:stateless` (`status`, already served by an
`!`-precomputed snapshot, so nothing to reclaim), `education:teach` (`status`), and
`implementation:implement-dispatch` (`status`). A broader ranking by read-only *phrase* density put
`session-flow:reconcile` top with six hits; I opened it to check, and all six are the scope statement
that **sibling sessions** are report-only — not a dispatchable action. Its actual subject is "the
off-thread work **this session** spawned" and "**this session's** task ledger" via
`TaskList`/`TaskGet`/`TaskUpdate`, which the background filter drops. Upheld.

So the read-only-sibling-action seam — the source of 11 of my 14 challenges — is **largely exhausted
by the 25 rows I opened.** The unopened 32 skew hard toward the two blocker classes the predictor
does not reach and that survive the inverted burden cleanly: **dropped harness tools**
(`TaskCreate`/`TaskGet`/`TaskList`/`TaskUpdate`, `ScheduleWakeup`, `Workflow`, plan mode) and
**live-transcript / session-state subjects**. That is a reason for moderate confidence in them, not a
clearance — but it is evidence, not an apology.

Files opened (25 rows): `worktree`, `pull-request`, `github:advise`, `rename-references`, `compress`,
`extract-ssot`, `repo-hygiene:clean`, `disk-hygiene:clean`, `tidy`, `claude-ops:plugins`, `wayfind`,
`audit-answers`, `quality-gate`, `blindspot`, `architecture:improve`, `bug-report:write`,
`point-dont-copy`, `reuse-or-replace`, `firecrawl:update` (full); `es:simulation`, `es:methodology`,
`prd`, `design`, `kindle-dedrm:manage`, `work-items:work` (targeted). Plus `session-flow:reconcile`,
opened during the predictor check and upheld — counted in the 32 as inherited, since I read it only
against one hypothesis rather than auditing it whole.

---

## 3. Challenges — Group A: stand alone, need no pending decision

These do not turn on the start-of-run-gate rule or the parent-supplied-scope principle. The named
action simply has no blocker. **Actionable today.** Ranked by main-context pollution avoided.

### A1. `/source-control:pull-request` — INLINE-ONLY → DISPATCH-OPTIONAL (`fetch-logs`: DISPATCH-DEFAULT)

- **Dispatchable phase:** the `fetch-logs <pr|run> [--raw|--job]` action, in full. Secondarily
  `prep review-only` and `status`.
- **Evidence:** `fetch-logs --raw` returns the "Full GitHub Actions log ZIP, **dumped in scope**"
  (SKILL.md action table). The size cap is `fetch_logs_max_bytes`, default **52428800 bytes = 50 MB**
  (`source-control/.claude-plugin/plugin.json:168`; documented in `README.md:175`). It is a declared
  **public action**, "for ad-hoc post-mortem," with zero decision gates. And it is **not rare**:
  "`monitor` invokes this action internally on CI failure," so it lands on the common path.
- **Why the blocker does not reach it:** B10's blocker is the "Decision gates (pause for user)" table
  — prep-findings triage, commit message, CI fix proposal, "Merge confirmation — irreversible."
  Every one of those sits in `prep`/`create`/`merge`/`full`. `fetch-logs` appears in none of them.
- **Pollution avoided:** up to 50 MB of raw CI log per invocation, whose product is a one-paragraph
  root-cause diagnosis the parent acts on. Nothing in the ZIP is re-read. This is the single largest
  measurable figure in the whole set, by orders of magnitude.
- The skill already dispatches its comparable case: "For ≥3 findings, **MANDATORY subagent dispatch**
  … preserves main session context." The same argument applies verbatim to log retrieval.

### A2. `/code-tidying:tidy` — INLINE-ONLY → DISPATCH-OPTIONAL (`dry-run`: DISPATCH-DEFAULT)

- **Dispatchable phase:** `dry-run [<lane>]` = Phases A–D entire.
- **Evidence:** SKILL.md action table — "Run Phases A-D (triage, explore, research, hunt). Present
  the prioritized findings table and the proposed PR scope. **Do NOT make edits. Do NOT branch. Do
  NOT push. Do NOT file tracker items.**"
- **Why the blocker does not reach it:** B02's blockers are Phase B (branch), Phase E (commit per
  tidying), Phase H (`/pull-request create` then `gh pr checks --watch` until green), the Phase A
  ambiguity pause, and the SOFT-exclusion interactive override. All are Phases B/E/H or a
  pre-dispatch question. Phases A–D contain none of them.
- **Pollution avoided:** Phase C is a full `/discovery:explore` over the lane scope *or*, when the
  discovery plugin is absent, "read 5-10 representative files"; plus a `/discovery:research` pass or
  "a focused inline research pass." Phase D.2 then "walk[s] the lane's scope globs" classifying every
  candidate, after reading `reference/tidyings.md` (26-entry taxonomy) and `reference/exclusions.md`
  ("read it at the start of every run"). Bundled reference + lane files alone are **634 lines**; the
  source reads are unbounded by lane size. Output: one prioritized findings table.
- B02 **named this exact slice and declined to act on it** — "that is a clean pointer-returning
  escape hatch *if one is ever wanted*." Under the inverted premise it is wanted.

### A3. `/github:advise` — INLINE-ONLY → DISPATCH-OPTIONAL (bare invocation)

- **Dispatchable phase:** Steps 1–4 on a bare invocation — topic routing, method-ladder doc
  grounding, live-`gh` current-state anchoring, and the advisory draft.
- **Evidence:** "**Read-only contract (hard)** — A bare invocation of this skill performs zero
  mutations," enumerated in five write-capability bullets.
- **Why the blocker does not reach it:** B04's two blockers are (1) `--apply` routing to
  `guided-apply` per-step confirms, and (2) the `offer_browser_automation` executable offer.
  `--apply` is "declared at invocation" and "never widens what a bare invocation may do mid-flight."
  The browser offer is triple-gated: method ladder must land on a UI-only surface **and**
  `offer_browser_automation` must not be `false` **and** resolved change routing must be
  `guided-apply` (the unconfigured default is `propose`, which reports rather than offers). Neither
  reaches the bare read-only path — which is the whole path, most of the time.
- **Pollution avoided:** the method ladder fetches canonical GitHub doc pages *and* verifies fetch
  integrity per page, then Step 3 reads live org/repo/billing state through `gh`. Shared reference is
  **457 lines** (`areas.md`, `method-ladder.md`, `change-routing.md`, `browser-automation.md`,
  `conventions-file.md`) before a single fetched page. Output: a recommendation with citations.
- **This is also a finding against the artifact — see §5.1.** B04 itself conceded the phase:
  "the method-ladder doc-grounding phase (fetch + fetch-integrity verification) is **offloadable**."

### A4. `/repo-hygiene:clean` — INLINE-ONLY → DISPATCH-OPTIONAL (`scan`, `stash`, branch audit, every `--dry-run`)

- **Dispatchable phases:** §1 `scan`; §4.2 branch audit (the audit, not the deletion); §4.3 stash
  audit; and the `--dry-run` half of `caches` / `build` / `tree` / `tree-batch` / `all-batch`.
- **Evidence:** action table lists `scan` at Risk `Safe`, Pre-flight `No`; §1 says "read-only
  inventory. **Stop if action is `scan`**." §4.3: "read-only per-stash facts (age, source branch,
  diffstat, PR/merge signal, advisory). **Never drops a stash.**" Every mutating tier is
  `--dry-run` by default and writes a manifest before any apply.
- **Why the blocker does not reach it:** B09's rationale is "**Every mutating path** is gated on a
  human decision… the skill's own autonomous fallback is `abort`." True, and it never addresses the
  non-mutating paths — which is where the whole filesystem walk happens. "Both selective mutating
  tiers pay the filesystem walk **once**" in the dry-run; the apply "removes it without re-walking."
  The expensive half is explicitly the unblocked half.
- **Pollution avoided:** 26 bundled scripts' output; a stash audit emits a per-stash diffstat;
  `all-batch --dry-run` emits per-repo `Outcome`/`Reason` lines across an entire ghq fleet plus
  `UnmatchedSkip:` warnings. Context/reference files total **710 lines**. Output: a byte total and a
  confirmation prompt.
- **Split shape:** subagent runs the walk and returns `Manifest: <path>` + `Summary: planned=N
  bytes=K`; the parent shows the gate and applies the *same manifest*. The manifest hand-off is
  already the skill's own contract — it is designed for exactly this seam.

### A5. `/disk-hygiene:clean` — INLINE-ONLY → DISPATCH-OPTIONAL (audit lane; mechanism caveat in §6)

- **Dispatchable phases:** steps 1–3 — snapshot, ownership/evidence triage, classify and report.
- **Evidence:** "**Automated, scheduled, remote, unattended, or no-human-in-loop sessions always
  audit and stop.**" The audit-only lane is not merely unblocked; it is the skill's *documented
  behavior for exactly the conditions a subagent runs under*.
- **Why the blocker does not reach it:** B03's blockers are the step-5 `AskUserQuestion` exact-tier
  approval and the `--confirmed-large-scan` confirmation. Both are in the `--execute` lane.
- **Correcting B03's second point:** it says the read-only scan "*already* fans out … so the
  dispatchable half is done." The skill says the opposite about the expensive part: "Each fan-out
  worker receives a bounded subtree and returns evidence only. **The parent owns classification, the
  single report,** every approval, preview, and all execution." The classification pass over every
  returned entry, plus step 2's per-entry ownership investigation ("inspect enough neighboring
  content and metadata"), is parent-side and unbounded by target size. The rule constrains *workers*
  from approving or deleting; it says nothing requiring the classifying parent to be the main
  conversation.
- **Pollution avoided:** a home-directory or Dev-Drive walk plus per-entry provenance evidence.
  Output: a tiered findings table.

### A6. `/docs-hygiene:rename-references` — INLINE-ONLY → DISPATCH-OPTIONAL (all `audit` modes, `preview`, `blocklist`)

- **Dispatchable phases:** `audit <old> to <new>`, `audit blast`, `audit half-rename`,
  `audit orphans`, `preview`, `blocklist`.
- **Evidence:** "**Audit mode runs phases 1-3 only and reports — no Edit calls.** Preview mode runs
  1-4 and reports planned edits — no Edit." Phase 4 (`Confirm` via `AskUserQuestion`) is reached only
  by apply mode.
- **Why the blocker does not reach it:** B03 names two `AskUserQuestion` sites. The first — "If
  multiple candidates surface, present via `AskUserQuestion` — user picks which pair to audit" — is
  the **smart default's pair detection**, i.e. a question asked *before the sweep starts*. With an
  explicit `<old> to <new>` pair the branch is never entered. The second is apply-mode Phase 4.
  Neither reaches an explicit-pair audit.
- **Pollution avoided:** Phase 2 runs the full pattern library — **12 syntactic forms** — "in
  parallel against tracked text files," aggregating per-file hit counts, then Phase 3 triages every
  match into 3 buckets. On a skill/identifier rename it *first* enumerates coupled-sibling renames
  and "queue[s] EACH as its own rename pair," multiplying the sweep. Context files total **759
  lines** before any grep result. Output: a bucket-distribution table.
- Group A on the *explicit-pair* form. The bare `audit` form (parent hands over a pair it detected)
  is Group B — see B2.

### A7. `/docs-hygiene:compress` — INLINE-ONLY → DISPATCH-OPTIONAL (`audit`)

- **Dispatchable phase:** the `audit [target]` action.
- **Evidence:** hard rule — "Semantic-diff dispatch is mandatory for default action. **Audit is
  read-only — no dispatch.**" So `audit` needs no `Agent`, which is B03's entire blocker.
- **Why the blocker does not reach it:** B03's blocker is the mandatory semantic-diff verifier
  needing `Agent`, plus the "When NOT to use → **Subagent context invoking `/compress` for batch
  fan-out**" line. That line is scoped to batch fan-out of the *default* action. `audit` is exempt
  by the skill's own hard rule.
- **Secondary, weaker challenge on the default action:** `context/fan-out-orchestration.md` already
  prescribes "**the main session dispatches separate compress + audit subagents**, reconciling per
  finding." The invariant is that the verifier is a *different context from the compressor* — not
  that the compressor must be the main thread. A parent that spawns both satisfies it. This makes the
  default action a spawn-depth capability question, which is the criteria's own recorded-recursion
  case, not an impossibility.
- **Pollution avoided:** `audit` on a directory reads **every target `.md` in full** to compute the
  per-file expected-yield heuristic (`context/target-types.md`); context files total **348 lines**.
  Output: a four-column table (`target`, `expected_yield_pct`, `classify`, `reason`).

### A8. `/claude-ops:plugins` — INLINE-ONLY → DISPATCH-OPTIONAL (`audit`; mechanism caveat in §6)

- **Dispatchable phase:** the `audit` action.
- **Evidence:** "Read-only dry run… run the full algorithm in `context/sync.md` with every mutating
  CLI call replaced by 'would run: `<command>`'… but issue **zero** `plugin
  install|update|uninstall|marketplace update` invocations."
- **Why the blocker does not reach it:** B02's blockers are `install_new: ask` (sync Step 4),
  `converge.md`'s per-plugin `AskUserQuestion`, and converge's autonomous-session abort. All three
  are `sync`/`converge`. The `audit` row's Mutates column is a bare "No."
- **Rebutting B02's dismissal:** "Output is a terse fixed-section report anyway — no context win."
  That inverts the metric. The *output* being terse and the *input* being bulky is precisely the
  dispatch profile — it is the highest-value shape, not the lowest. The input is
  `fleet-state.sh --all` across every marketplace in `known_marketplaces.json` × every installed
  plugin × every scope, joined against `installed_plugins.json` and per-scope `enabledPlugins`, then
  the full sync algorithm's delta computation. Context files: **409 lines**.

### A9. `/event-storming:simulation` — INLINE-ONLY → DISPATCH-OPTIONAL (`--discover-bcs`)

*Corroborates* the checklist's own existing sub-action note; this adds the pollution grounding.

- **Dispatchable phase:** `--discover-bcs [board-url]`.
- **Evidence:** "Reads **ALL board items** via MCP, applies Brandolini's 6 heuristics (Ch. 6)
  **mechanically against the data**, and produces a structured BC analysis with heuristic evidence.
  Can be run at any time against any completed BP board — **results are reproducible.**" No user turn
  anywhere in the description.
- **Why the blocker does not reach it:** B04's blocker is `--simulate`'s "uses AskUserQuestion to
  guide the user through selecting which BC to explore next" and "**Never auto-advance formats — the
  user chooses each step.**" Both are `--simulate`.
- **Pollution avoided:** a completed Big Picture board is hundreds of stickies; the sibling
  methodology skill reads boards "via `miro_list_board_items` (**full pagination**)". Output: one BC
  table with heuristic evidence.
- Also unblocked on the same grounds, secondarily: `--process-model` / `--design-level` /
  `--evaluate` all begin by reading an existing board to extract state. **Mechanism caveat in §6**
  (MCP tool availability in a subagent).

### A10. `/source-control:worktree` — INLINE-ONLY → DISPATCH-OPTIONAL (`status`, `audit`, `cleanup --dry-run`)

- **Dispatchable phases:** `status`, `audit`, `cleanup --dry-run`.
- **Evidence:** B10's blocker is precise and correct — but it names its own bound: "**confined to the
  `EnterWorktree` terminal, not to provisioning.**" `status` is "Inventory all worktrees with PR
  association and staleness detection" via `git worktree list --porcelain`, one batched `gh pr list`,
  and last-commit dates. `audit` = "Step 1: run the `status` action internally" plus a config-health
  checklist. `cleanup --dry-run` "reports candidates and takes no action." None calls `EnterWorktree`.
- **Pollution avoided:** modest and fleet-size-dependent — worktree list, one `gh pr list`, the
  6-status classification table, `worktree_stale_days` handling; **301 lines** of context files.
  Ranked here because the win is small, not because the argument is weak.

### A11. `/planning:wayfind` — INLINE-ONLY → DISPATCH-OPTIONAL (`work` mode, non-interactive frontier)

- **Dispatchable phase:** `work` mode restricted to its own non-interactive frontier.
- **Evidence:** the skill *defines* the autonomous lane: "In a non-interactive session, further
  filter OUT `needs-human` items; if that empties the frontier, STOP with a truthful 'all remaining
  decisions need a human'." `wayfind: research` items are labelled "**autonomous-capable**" and
  route to `/discovery:research` — DISPATCH-DEFAULT in this same sweep.
- **Why the blockers do not reach it:** B06 gives three. (1) The `allowed-tools:` `Bash(gh …)` grants
  — **void under B07's fleet-wide adjudication**, which the checklist ratifies: "Not a blocker
  (adjudicated in B07, applied fleet-wide): a skill's `allowed-tools` grant." B06 was written against
  the earlier criteria and this leg should be struck. (2) `chart` mode's non-interactive refusal —
  correct, and it is why `chart` stays inline; it says nothing about `work`. (3) "Does not resolve a
  HITL item for the human (inviolable)" — this is the *reason the autonomous branch exists*. Dispatch
  satisfies the rule by filtering; it does not violate it.
- **Pollution avoided:** step 1 map hygiene reads the map issue plus every decision item and its
  resolution comments through `gh`; step 2 computes the frontier; then research-typed items pull in
  a full research pass. Grows linearly with map size.

---

## 4. Challenges — Group B: depend on a pending principle

These turn on the same two unratified ambiguities the checklist is already holding three flips
against (the **start-of-run-gate rule** and the **parent-supplied-scope principle**). They are not
actionable until those are decided.

### B1. `/discovery:blindspot` — INLINE-ONLY → DISPATCH-OPTIONAL *(start-of-run gate)*

**Independently corroborated** — the checklist records `renorm.md` and `validator-B` flipping this
row the same way. I arrived at it blind of both; count it as corroboration, not a new find.

- **Dispatchable phase:** step 2 (Scan) and step 3 (Output), with step 1's intake answer supplied by
  the parent in the brief.
- **Evidence:** step 1 is "**Intake — ask the user's starting point first (one question).**" One
  question, before any work. Nothing after it needs the user.
- **The stronger argument B03 missed — inheritance inconsistency.** The scan phase is defined *by
  reference to a DISPATCH-DEFAULT skill*: "read the target area (the codebase-reading, git-history,
  and project-structure dimensions of `${CLAUDE_PLUGIN_ROOT}/skills/explore/SKILL.md`)."
  `/discovery:explore` performs those same reads and is DISPATCH-DEFAULT with a `discovery:explorer`
  plugin-agent. Same reads, same volume, opposite verdict.
- **Rebutting "no artifact to point at":** B03 leans on "This skill does NOT write `EXPLORE.md`."
  But the deliverable is blindspot cards plus one prompt "wrapped in clear copy-start / copy-end
  markers" — a small, structured, verbatim-returnable payload. That is what a subagent returns
  *well*. Absence of a file is not absence of a returnable result.
- **Pollution avoided:** an explore-grade sweep of an unfamiliar codebase area plus git history and
  project structure, or a domain lane fetching official docs. Output: a handful of cards.

### B2. `/docs-hygiene:rename-references` bare `audit` — *(parent-supplied scope)*

The explicit-pair form is Group A (A6). The **bare** `audit` form additionally needs the parent to
detect the rename pair and hand it in, which is the parent-supplied-scope principle. Same pollution
figures as A6.

### B3. `/re-anchor:point-dont-copy` — INLINE-ONLY → DISPATCH-OPTIONAL (audit half) *(parent-supplied scope)*

**Independently corroborated** — `renorm.md` flipped this row; I reached it from the skill text.

- **Dispatchable phase:** the audit sweep. The re-anchor and the forward correction stay inline.
- **Evidence:** all **six** of the skill's own audit signals are artifact-located, none
  transcript-located: copied or paraphrased content a named source owns; extracted value tables or
  verbatim config blocks; hard-coded tool schemas or capability lists "**in a durable doc**"; a
  reference to an internal script/file name where the public contract would do; a closed enumeration
  of duties; "the same passage, literal, or concept appearing in **two or more places**."
- B08 conceded this ("several audit signals are artifact-located") then rested on "main-context
  salience is the deliverable." That is true of the *re-anchor* half and the *correction* half, not
  of the sweep. The split is clean: subagent returns located findings; parent re-anchors and corrects.
- **Pollution avoided:** a duplication sweep across the repo's doc corpus. The skill's stated
  conversation-start trigger is "documentation work," so the corpus is the whole point.

### B4. `/re-anchor:reuse-or-replace` — INLINE-ONLY → DISPATCH-OPTIONAL (audit half) *(parent-supplied scope)*

**Independently corroborated** — `renorm.md` flipped this row too.

- Same shape as B3, with a sharper cost: finding "a divergent error-handling, logging, naming, or
  interface approach introduced **where the codebase already has an established one**" requires
  sweeping the codebase for *the established way*. That search is the context sink and it is entirely
  file-located. "A divergence whose rationale was never recorded in the repo's ADR/docs convention"
  likewise means reading the ADR set.
- Only "what this session just produced" is transcript-bound, and the parent can hand the diff over.

---

## 5. Findings against the artifact itself

### 5.1 A same-plugin split that the normalization pass missed — inside a single batch

`/github:audit` = **DISPATCH-DEFAULT (plugin-agent)**. `/github:advise` = **INLINE-ONLY**. Adjacent
rows, **both in B04**.

They carry a **byte-identical "Read-only contract (hard)"** section — the same five write-capability
bullets, verbatim in both SKILL.md files. Both resolve mechanics through the same
`${CLAUDE_PLUGIN_ROOT}/reference/method-ladder.md`, both fetch and integrity-verify official GitHub
docs, both read live `gh` state under the same read-only contract. The only asymmetry is that
`advise` additionally offers an opt-in `--apply` flag.

The checklist's normalization pass 2 reports: "**Same-plugin same-blocker splits** — one caught and
corrected in-batch (B10's babysit pair). **No cross-batch split found: no plugin spans two
batches.**" That framing searched only for *cross-batch* splits. This one is *within* B04 and was
not caught. Pass 2's clearance should be re-scoped to within-batch splits as well.

### 5.2 A correction in the opposite direction — the checklist over-carves `event-storming:methodology`

The checklist lists `event-storming:methodology --<format>` among "four INLINE-ONLY rows [that]
contain a clearly dispatchable **sub-action**," on the ground that it is "a pure reference read of
`reference/*.md` with no user turn."

**No user turn is necessary but not sufficient.** Under a context-preservation metric the question is
whether the raw content is *destined for* main context. Here it is: the user invoked `--big-picture`
to get the facilitation methodology **in the conversation**, to apply it. The reference corpus is
**1697 lines** across seven files (`big-picture-workshop.md` 432, `design-level.md` 311,
`process-modeling.md` 242, `patterns-and-anti-patterns.md` 217, `remote-eventstorming.md` 182,
`notation-and-building-blocks.md` 168, `glossary-and-tools.md` 145). Dispatching it and returning a
summary destroys the deliverable — this is the criteria's own "the deliverable IS the in-conversation
utterance" case. **Recommend striking `methodology --<format>` from the dispatchable-sub-action list.**

By contrast, methodology's *board* read at Interactive-Discovery step 1 —
"`miro_list_board_items` (**full pagination**)" — genuinely is offloadable raw volume, and is not
listed. The carve-out is on the wrong phase.

### 5.3 Three rows where the verdict is right and the stated reason is not

Reported so the justifications are repaired, not the verdicts flipped:

- **`docs-hygiene:extract-ssot`** — B03 cites the per-cluster human gate and the `execute`→
  `/rename-references` chain. The skill carries a **stronger, non-interaction blocker B03 did not
  cite**: "Every extraction decision must be grounded in **direct evidence captured this session** —
  grep output or file reads **you performed yourself**… **a subagent's survey summary is NOT Tier
  0**… **A subagent roster is a lead list, never proof.**" That is an explicit correctness contract
  binding the *deciding* context to its own greps. It survives every criteria amendment. *Narrow
  carve-out:* the `verify` action is a "6-gate cheap check" that is "**OPTIONAL — does not gate
  `plan`/`execute`**," so a subagent verdict there contaminates nothing. Low value; noted for
  completeness.
- **`planning:wayfind`** — leg (1), the `allowed-tools` grant, is void under B07's ratified
  fleet-wide rule. See A11.
- **`bug-report:write`** — B01 leads with the `AskUserQuestion` blocker (the rejected tool-shaped
  form) and *then* gives the real reason as an aside. The real reason is dispositive on its own:
  "**Does not run a broad exploration or research pass**"; step 2 is "a fast breadth pass," skippable
  entirely with `--no-survey`. There is nothing to reclaim. Reorder the justification.

### 5.4 The `--check`-is-too-small rulings hold

B04 and B05 carved out `firecrawl:update --check` and `kindle-dedrm:manage update` as read-only but
judged them too small to pay for a hop. I read both and **agree**:

- `firecrawl:update --check` — one npm metadata call plus one upstream `SKILL.md` fetch and SHA
  compare. Output: a short drift report. Maintainer-only.
- `kindle-dedrm:manage update` — `check-drift.sh` plus a few HEAD requests, one `gh` releases call,
  and a tutorial-page fetch, diffed against `references/sources.md` / `versions.md` baselines. The
  skill's 803 lines of `references/` are **not** read by this action.

Both correctly INLINE-ONLY. Listed to show the read-only-action pattern was applied with a cost
threshold, not mechanically.

---

## 6. Two harness dependencies — declared, not resolved

Both affect *mechanism*, never the phase argument. Each phase finding above stands on its own; these
determine only *how* the dispatch is wired, and each is a decision for the user.

**`disable-model-invocation: true`.** Cited as a reinforcing blocker on five INLINE-ONLY rows
(`claude-ops:plugins`, `disk-hygiene:clean`, `education:teach`, `planning:questionnaire`,
`firecrawl:update`), always framed as "blocks `skills:` preload." Two things:

1. The checklist's own criteria say **runtime invocation, not `skills:` preload, is the marketplace
   default and the safer one** — "Every agent this marketplace ships today … uses runtime invocation,
   none uses `skills:`." So "blocks preload" argues against a mechanism the fleet does not use.
2. Whether the flag *also* blocks a subagent's runtime `Skill` call is **unverified** — I did not
   confirm it against the harness. If it does, the fix is either flipping the flag (a marketplace
   file the user owns) or a user-invoked entry point. Either way it is a **configuration choice, not
   a capability limit**, and under the inverted burden "we set a flag that prevents dispatch" is not
   "it cannot dispatch."

**MCP tool availability in a dispatched subagent** (`event-storming:simulation --discover-bcs`,
and methodology's board read). Whether `mcp__plugin_miro_miro__*` tools reach a plugin-agent or a
forked subagent is **unverified**. A2/A9's phase argument does not depend on the answer; the
mechanism does.

---

## 7. Summary

**14 challenged · 11 upheld on my own read · 32 upheld without independent verification.**
(Counts script-verified; see §2 for why the unopened 32 are lower-risk than the 14/25 hit rate alone
would imply.)

Group A (actionable today, no pending decision):
`pull-request` · `tidy` · `github:advise` · `repo-hygiene:clean` · `disk-hygiene:clean` ·
`rename-references` (explicit pair) · `compress` · `claude-ops:plugins` · `es:simulation` ·
`worktree` · `wayfind`

Group B (blocked on a pending principle):
`blindspot` · `rename-references` (bare audit) · `point-dont-copy` · `reuse-or-replace`

**Group B adds no new rows.** Its three row-moving members *are* the three flips the checklist is
already holding; `rename-references` bare-audit is the same row as A6. Group B's contribution is
independent corroboration of pending flips, not additional scope — do not count it twice.

Against the artifact: one within-batch same-plugin split (§5.1), one over-carve to strike (§5.2),
three justifications to repair (§5.3).

Distribution effect, with the corroboration overlap removed:

| Adopted | DISPATCH-OPTIONAL | INLINE-ONLY |
|---|---|---|
| Today (as recorded) | 29 | 57 |
| Group A only (11 new rows) | 40 | 46 |
| Group A + the three already-held flips | 43 | 43 |
