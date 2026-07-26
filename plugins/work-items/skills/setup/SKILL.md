---
name: setup
description: "Verify and configure the work-items plugin for this repository. check inspects read-only the tracker provider binding (.work-item-tracker.json), the tracked .github/recurring-schedule.json (presence, JSON validity, unique reconciliation keys), the jq and tracker-seam entry gates, and the recurring-maintenance role label; apply binds the tracker provider (seeds .work-item-tracker.json with the provider + non-secret config), writes the schedule, and optionally remaps the canonical role labels in the tracker binding. On a first-time bind apply writes that minimum viable config only — binding, role-label pass, empty schedule skeleton — and the pass that infers candidates from the repo and interviews the consumer for their recurring work items is opt-in, via the --seed-schedule argument or a single offer whose recommended default is skip (applied silently with no interactive user); a schedule that already carries items is summarized and offered updates exactly as before. Use when: 'set up work-items', 'bind the tracker provider', 'is work-items configured', 'configure the recurring schedule', 'work-items setup', 'seed recurring items', 'bulk-seed the recurring schedule', 'remap the work-item role labels', or the due/recheck/work actions report no recurring schedule configured, or the seam reports no binding. Re-runnable — safe to invoke again to reconfigure or to seed the schedule later."
argument-hint: "check | apply [--seed-schedule]"
user-invocable: true
disable-model-invocation: true
---

## Purpose

Verify and configure the work-items plugin for the consuming repo. Setup owns three concerns: **bind
the tracker provider** (the tracked `.work-item-tracker.json` at the project root — the once-per-repo
declaration the seam needs before any verb runs; see "Provider binding" below), the tracked
recurring-schedule config at `.github/recurring-schedule.json` so the `due`, `recheck`, and `work`
actions resolve a real schedule instead of degrading to "no recurring schedule configured", and the
optional canonical-role → label remap in the binding (see "Canonical role labels" below). The
recurring-schedule pass is the bulk path for seeding or reshaping the whole schedule at once; the
per-item `add --recurring` path (which appends a single row as a side effect of filing its work item)
stays as-is. That bulk pass is opt-in rather than part of initial config: a first-time bind writes the
empty skeleton and stops there, because that bind is usually reached as a detour from another verb
reporting "no binding" — the operator came to do something else, and should not be walked through a
per-item interview to get there.

`check` inspects read-only and reports a PASS/FAIL/INFO table; `apply` binds the provider, writes or
reshapes the schedule, and offers the role remap, then re-runs `check`. No argument or `check` runs the
check; `apply` runs the check first, then the bind-and-write flow; `apply --seed-schedule` additionally
opts in to the candidate-inference-and-interview pass. Idempotent: re-running reads the
on-disk files and offers updates rather than overwriting blind. The schedule file is a plain tracked
JSON file the skill reads and writes directly (Read / Write / `jq`) — it is not a tracker record, so it
does not route through the work-item-tracker seam; only operations on the work items themselves (labels,
item lookups, edits) go through the bound provider.

## Resolving the paths

Root both paths at the project root, never a bare relative path (which breaks when invoked from a
subdirectory):

```bash
BINDING="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel)}/.work-item-tracker.json"
SCHEDULE="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel)}/.github/recurring-schedule.json"
```

Both files are version-controlled and shared by the whole team — they belong in the consumer's tree
(`.work-item-tracker.json` at the project root, the schedule under `.github/`), never in the plugin
directory or any machine-local state.

## Provider binding (the tracker seam)

`apply` runs this first — the recurring-schedule and role-label passes below resolve the binding; the
`check` binding probe validates it read-only. The tracker seam runs against exactly one provider per
repo, declared in the tracked `.work-item-tracker.json` at the project root (resolved as `BINDING`
above); every seam verb resolves the bound provider from it, and with no binding the seam hard-errors
(exit 3). The seam **ships with this plugin** and bundles the `github`, `local-markdown`, and `jira`
adapters — installing the plugin is enough; a repo only declares which one it uses. Binding shape, discovery, and
adapter resolution are the seam contract's
[`${CLAUDE_PLUGIN_ROOT}/tools/work-item-tracker/CONTRACT.md`](${CLAUDE_PLUGIN_ROOT}/tools/work-item-tracker/CONTRACT.md)
"Setup (binding file)" and "Adapter resolution".

Steps 2 and 3 are an interview. With no interactive user, resolve them by `apply`'s "Autonomous
invocation" rule below rather than asking — it fixes what the RECOMMENDED answers resolve to, and
when this pass must stop instead of guessing.

1. **Read the current binding first.** If `.work-item-tracker.json` exists, load it and report the
   bound `provider` and `config`. RECOMMENDED: keep it — re-bind only to switch providers or fix
   config. If it is absent, say so and continue to the interview.
2. **Choose the provider**, recommendation first:
   - **`github`** (RECOMMENDED) — coordination over GitHub Issues via the ambient `gh` CLI; needs no
     provider config beyond the lease TTL. Confirm `gh` is installed and authenticated (`gh auth
     status`); the seam hard-errors at call time when `gh` ≥ 2.94 is absent.
   - **`local-markdown`** — the offline reference provider (one markdown file per item); never a
     coordination surface. Requires `config.storage_dir` (no baked default) — a tracked directory the
     items live in (e.g. `.work-items`).
   - **`jira`** — read/resolve-only against a Jira Cloud project set (consume-only: no ticket
     creation/claim/mutation; write verbs exit `6`). Requires `config.jira` (`site`, non-empty
     `project_keys[]`, `auth_email`, `auth_env`) and `curl`; the API token is referenced by env-var
     name only, never stored. Binding shape and the deferred live-instance facts are the seam
     contract's "jira adapter". Selecting it does not enable `/work-items:work` or `track start`
     (both need writes) — an accepted gap.
   - **another provider** — supply its adapter consumer-local at
     `${CLAUDE_PROJECT_DIR}/tools/work-item-tracker/adapters/<provider>/` (the seam resolves
     consumer-local adapters ahead of the bundled set, so a repo can add an unshipped provider or
     shadow a bundled one without forking the plugin); set `provider` to its name here.
3. **Settle the config — all non-secret:**
   - `lease_ttl_hours` (REQUIRED, every provider) — claim-lease lifetime in hours. RECOMMENDED `24`.
   - `storage_dir` (REQUIRED for `local-markdown` only) — the item-store directory.
   - `jira` (REQUIRED for `jira` only) — an object with `site` (Cloud host), non-empty
     `project_keys[]`, `auth_email`, and `auth_env` (the env-var NAME holding the API token);
     optional `blocked_by_link_type` / `done_category_keys` override the deferred live-instance
     defaults. Interview for these; probe that the token resolves in-env at bind time (never store
     it). Per the operator secret-binding classification, the token's durable home is the OS-native
     credential store, with the env var as the CI/headless fallback — never a plaintext file.
   - **Secrets never go in this file** — it is tracked in git. A provider that needs an API token
     references it by env-var name / the repo's secret-store convention from inside its adapter, never
     as a literal here. `github` needs none (ambient `gh`); `jira` references its token by `auth_env` name.
4. **Write the binding.** Re-read `.work-item-tracker.json` from disk immediately before writing and
   merge: preserve any existing `config.role_labels` (owned by the role-label pass below) and any other
   keys. Write `schema_version: "1.0"`, the chosen `provider`, and the `config`. Confirm the file is
   tracked, not ignored.

Example (`github`):

```json
{
  "schema_version": "1.0",
  "provider": "github",
  "config": { "lease_ttl_hours": 24 }
}
```

Example (`local-markdown`):

```json
{
  "schema_version": "1.0",
  "provider": "local-markdown",
  "config": { "lease_ttl_hours": 24, "storage_dir": ".work-items" }
}
```

## `check` (read-only)

Probe the binding, the schedule config, and the seam's entry gates, and report a PASS/FAIL/INFO table
with one remediation line per FAIL. Modify nothing, and do NOT bind, file items, or run a recurring
check.

1. **`jq` entry gate** — the authoritative check is
   [`${CLAUDE_PLUGIN_ROOT}/reference/tracker-seam.md`](${CLAUDE_PLUGIN_ROOT}/reference/tracker-seam.md)
   "entry-point presence checks"; probe it (`command -v jq`), don't restate it. Absent is FAIL with that
   reference's install remediation — the schedule snippets parse with `jq` unconditionally.
2. **Tracker provider binding** — resolve `BINDING` (above). Absent → INFO: the tracker seam is not
   bound, so every seam verb hard-errors (exit 3) until `apply` seeds it, and the role remap has nothing
   to configure; the remediation is `/work-items:setup apply`. Present → validate without mutating: it
   parses as JSON, carries `schema_version` and a `provider`, and that provider resolves to a bundled
   adapter (`github`, `local-markdown`, `jira`) or a consumer-local one at
   `${CLAUDE_PROJECT_DIR}/tools/work-item-tracker/adapters/<provider>/`; `config.lease_ttl_hours` is
   present, `local-markdown` additionally carries `config.storage_dir`, and `jira` additionally carries
   `config.jira` (`site`, non-empty `project_keys[]`, `auth_email`, `auth_env`). A malformed shape, an
   unknown/unresolvable provider, or a missing required config key is FAIL, naming what is wrong.
3. **Schedule presence** — resolve `SCHEDULE` (above). Absent → INFO: `due` / `recheck` / `work`
   degrade to "no recurring schedule configured"; `apply` seeds it. Present → continue.
4. **Schedule validity** — a present file parses as JSON with the root `{"items": [ ... ]}` shape
   (FAIL otherwise), and **both reconciliation keys are unique across the whole `items` array — every
   `id` AND every `title`**. A duplicate `id` (the key `recheck <id>` resolves against) or duplicate
   `title` (the key `due` / `work` match `[Maintenance] {title}` against) silently breaks
   reconciliation — FAIL, naming the collision.
5. **Tracked, not ignored** — a present schedule (and a present binding) must be committed to be
   team-shared: `git check-ignore -v` on the resolved paths; a non-empty result is FAIL with the
   matching pattern.
6. **Recurring-maintenance role label** — role-label resolution is an action-entry invariant per the
   tracker-seam reference; probe it. With no binding (probe 2 INFO) the role remap has nothing to
   configure — INFO. With a binding present, resolve
   `config.role_labels["recurring-maintenance"]` (default `recurring` when the entry is absent; a
   malformed, empty, or non-string configured value is FAIL). When a schedule exists, verify the
   resolved label is present via the adapter's label listing (GitHub adapter: `gh label list`): an
   absent label means a seeded `[Maintenance]` item lands unlabeled and goes invisible to the next
   `due` / `work` pass — FAIL, with the remediation being the repo's declared label provisioning
   process (never `gh label create` ad hoc). Missing `cadence:{cadence}` labels are taxonomy niceties —
   INFO.

## `apply` (idempotent)

Run `check`, then bind the provider (step 1) before the schedule and role-label passes. The schedule
branches on **how many rows the schedule already carries** — never on whether the file exists. A
skipped first-time `apply` leaves `{"items": []}` on disk, so a file-absence gate would make the
seeding path unreachable by re-running:

- **Schedule carries ≥1 item** — unchanged from before: summarize it, infer candidates, and interview
  against that baseline (steps 3–5), offering updates. `--seed-schedule` is a no-op here; this branch
  already interviews.
- **Schedule absent, or present with an empty `items` array** — write only the minimum viable config:
  the provider binding, the role-label pass, and the empty `{"items": []}` skeleton so `due` /
  `recheck` / `work` stop degrading to "no recurring schedule configured". Steps 4–5 do not run: no
  candidate inference, no per-item interview. **This is the default.**
- **Schedule present but not parseable as the `{"items": [ ... ]}` root** — no `items` key, a null or
  non-array `items`, a non-object root, or invalid JSON. This is a `check` FAIL, not a zero-row
  schedule: stop and report it rather than treating it as either branch, because overwriting or
  "leaving it untouched" both leave a malformed file the recurring actions cannot read.

Seeding rows on the empty/absent branch is **opt-in**, satisfied by any one of: the explicit
`--seed-schedule` argument; an accepted yes/no offer; or an invocation that in its own words asks for
the schedule to be seeded (e.g. "seed a sensible recurring schedule for this repo") — an explicit
request IS the opt-in, so honor it without re-asking. Otherwise offer exactly once, before step 4, as a
single yes/no with **skip marked RECOMMENDED**: name that seeding walks them through one interview per
candidate item, that the skeleton alone already stops the degradation, and that re-running `apply` (or
`apply --seed-schedule`) bulk-seeds later at any time. On skip, say so plainly and go to step 6.

### Autonomous invocation (no interactive user)

When `apply` runs in an unattended or loop-driven context there is nobody to answer any of its
questions, and blocking on one strands the run. This rule governs **every** decision in `apply`, not
only the seeding offer — the seeding offer is the last question in the flow, and the bind and
role-label passes above it ask their own:

- **A decision whose RECOMMENDED answer is safe resolves to it silently.** Do not present it. Say in
  the summary which defaults were taken so the operator can revisit them.
- **A decision with no safe default is never guessed.** Stop and report it as a named blocker, with
  the one command that resolves it. Writing an invented binding is worse than not binding: every seam
  verb then resolves a provider the repo did not choose.

Applied to the three passes:

| pass | unattended resolution |
| --- | --- |
| Provider binding (step 1) | Bind `github` with `config.lease_ttl_hours: 24` — both RECOMMENDED — **only when `gh` is installed and `gh auth status` succeeds**. Otherwise stop: `local-markdown` and `jira` need `storage_dir` / `config.jira` values that have no defaults and cannot be inferred, so there is no provider left to choose safely. Report "tracker binding needs a provider decision; run `/work-items:setup apply` with a user present". |
| Role labels (step 2) | Keep the defaults — the RECOMMENDED answer, and the one that writes nothing. The pass runs and completes as a no-op: `config.role_labels` is left absent, so every role resolves to its documented fallback. A remap is a repo-vocabulary decision no default can stand in for. |
| Schedule seeding (before step 4) | Skip — the RECOMMENDED answer. Write the empty `{"items": []}` skeleton and go to step 6. |

So an autonomous first-time bind on a `gh`-ready repo produces the binding, the role-label pass, and
the empty skeleton, and nothing else. Absent an opt-in, never infer and never interview.
`--seed-schedule` carries the opt-in decision without the offer prompt, but the pass it selects is
step 5's per-item interview — so it is not a non-interactive seeding path, and an unattended caller
should not be directed at it.

The row shape, the root `{"items": []}` structure, and the cadence-duration table are defined once in
[`${CLAUDE_PLUGIN_ROOT}/skills/track/actions/add.md`](${CLAUDE_PLUGIN_ROOT}/skills/track/actions/add.md)
(step "If `--recurring`" and the Cadence Duration Table) — read that file for the authoritative field
list before writing. Proceed non-interactively where the invocation and the repo make the values
unambiguous; ask only where an item genuinely needs the user.

1. **Bind the tracker provider first.** Run the "Provider binding" procedure above — seed or update
   `.work-item-tracker.json` before any pass below resolves it. Every step that follows reads the bound
   provider and its `config.role_labels` from that file; the seam hard-errors (exit 3) without it.
2. **Offer the canonical role→label remap.** Run the "Canonical role labels (optional remap)" procedure
   below, which writes `config.role_labels` into the binding just seeded. It is anchored here — after
   the bind, before any schedule work — so it runs identically on the skipped first-time path (where no
   interview happens) and on the seeding path, and every later step resolves the post-remap labels.
3. **Read the current schedule file first.** If `.github/recurring-schedule.json` exists, load it and
   present a short summary (item count, each item's `id` / `cadence` / `next_due`, and which are already
   overdue against today). The interview proposes changes against that baseline; nothing is dropped
   without the user confirming. If the file is absent or carries an empty `items` array, say so and
   settle the opt-in decision above before steps 4–5.
4. **Infer candidate items before asking — steps 4 and 5 run on the seeding path only** (the schedule
   already carries ≥1 item, or seeding was opted into). On the default skipped path, run neither and go
   straight to step 6. Recurring items can't be fully derived, but don't skip the rung — propose
   candidates from what the repo actually contains, each with a recommended cadence:
   - Dependency manifests (`package.json`, `*.csproj` / `Directory.Packages.props`, `pyproject.toml`,
     `Cargo.toml`, `go.mod`) → a "Review dependency manifest / check for updates" item (recommend
     `quarterly`).
   - Lint / formatter config (`.editorconfig`, `eslint.config.*`, `ruff.toml`, analyzer rulesets) → a
     "Review linter config against current defaults" item (recommend `quarterly`).
   - CI workflow definitions (`.github/workflows/`) → a "Review CI workflow pins / action versions"
     item (recommend `quarterly`).
   - Security-sensitive surfaces (auth, secrets handling, `SECURITY.md`) → a "Security review" item
     (recommend `semi-annual` or `quarterly`).
   Present these as a starting menu; the user keeps, edits, or drops each. Do not invent items the repo
   gives no signal for.
5. **Interview, one decision at a time, recommendation first.** For each candidate (and any custom item
   the user names last), settle its fields against the shape in
   [`${CLAUDE_PLUGIN_ROOT}/skills/track/actions/add.md`](${CLAUDE_PLUGIN_ROOT}/skills/track/actions/add.md): `id` (kebab-case),
   `title`, `cadence` (one of the cadence table's values), `area[]`, `category`, `triggers[]` (external
   events warranting an early recheck — e.g. "new major framework release"), `notes`, and
   `close_previous`. Present one item at a time with your recommended values marked; the user accepts
   or edits before you move on. Date handling depends on whether the item is new or already present —
   setup seeds the schedule but never performs the maintenance, so it must not advance the cadence
   clock on an existing item (that is `recheck`'s job, gated on the check actually being done):
   - **New item:** seed `last_checked` to today and `next_due` to today + the cadence's day count
     (Cadence Duration Table in [`${CLAUDE_PLUGIN_ROOT}/skills/track/actions/add.md`](${CLAUDE_PLUGIN_ROOT}/skills/track/actions/add.md)).
   - **Existing item:** preserve its current `last_checked` and `next_due` as-is. Only recompute
     `next_due` when the user explicitly reschedules or changes the cadence — and even then never set
     `last_checked` to today (setup did no maintenance). Blindly resetting the dates would drop an
     already-overdue item out of the `due` / `work` recurring tiers, which both select on
     `next_due <= today`.
6. **Confirm the recurring-maintenance role label is present in the provider — load-bearing whenever
   the schedule will carry rows.** (Step 2 settled which label string each role resolves to; this step
   verifies that string actually exists.) Key this on the schedule's **final row count**, not on what
   this run wrote: with ≥1 row (written now or already on disk) a missing label is reported as a hard
   finding, exactly as spelled out below. With zero
   rows — the skipped first-time bind's empty skeleton — no `[Maintenance]` item can ever be created
   from that schedule, so a missing label is **informational, not a gate**: report it, note it must
   exist before the schedule is ever seeded, and continue without blocking the bind.
   Resolve the role from `.work-item-tracker.json` `config.role_labels["recurring-maintenance"]`,
   defaulting to `recurring` only when the file or entry is absent (a malformed, empty, or non-string
   configured value is an error, not a fallback). `due` / `work` enumerate open maintenance items with
   that resolved label, and the create path filters out labels the repo lacks — so if you write a
   schedule while the resolved label is absent, the first `[Maintenance]` item created (by the recurring
   automation or the `work` due-recurring tier) lands without that label, is invisible to the next
   `due` / `work` pass, and gets duplicated or reported as orphaned. Verify presence via the adapter's
   label listing (for the GitHub adapter, `gh label list`). **When the repository declares a
   label-as-code source of truth, that system is the sole writer — never `gh label create` labels ad
   hoc.** When the resolved label is missing and the schedule carries rows, tell the user plainly that
   the schedule cannot be reconciled until the label is added through the repository's declared
   provisioning process; do not silently treat it as optional. This step files no items; for a row now
   in the schedule, its `[Maintenance]` item is created — item only, no extra schedule row — by the consuming repo's
   recurring automation or the `work` due-recurring tier when `next_due` arrives. Do **not** point users
   at `add --recurring` to create it: that per-item path appends another schedule row, duplicating an
   already-seeded item.
7. **Write the schedule.** On the skipped path there is nothing to merge: write the `{"items": []}`
   skeleton when the file is absent, leave an already-empty file untouched, and go to step 9 — step 8
   has no renamed or dropped row to reconcile. Otherwise read the current file (if any) and merge the
   accepted items into the `items`
   array, keying each edited item on the **original `id` it had when read in step 3**, not its final
   `id` — so an id rename replaces the original row instead of leaving it behind. Concretely: replace
   the row whose id matches the item's origin id; append only genuinely new items (no origin row); and
   when the user renamed an id, drop the old-id row so `due` / `work` never see two rows for the same
   maintenance (which would create duplicate items). Preserve any existing rows the user did not
   touch. Before writing, **verify both reconciliation keys are unique across the whole `items` array —
   every final `id` AND every final `title`.** On any collision, stop and prompt the user to merge the
   two rows, replace one, or pick a unique value; never write a schedule with a duplicate `id` or
   `title`. Then write it back with the `{"items": [ ... ]}` root. Confirm the file is tracked, not
   ignored.
8. **Reconcile an existing row's open item when it is renamed OR dropped.** Both operations strand the
   row's live `[Maintenance] {old title}` recurring item (if still open): after write the schedule no
   longer carries that title, so `due` / `work` — which derive recurring candidates only from the
   schedule, and whose frontier tiers exclude items carrying the resolved recurring-maintenance label — will never surface it again,
   leaving it stale outside the normal flow (a rename additionally risks a duplicate under the new
   title). For each renamed or dropped existing row, look up its open item under the OLD title (adapter:
   "Search items", `--label <resolved recurring-maintenance label>`). Provider search is
   substring/prefix, not exact-title equality,
   so it can return a longer item (`[Maintenance] Review CI workflow pins`) when the old title was
   `Review CI` — **filter the results to the one whose title equals `[Maintenance] {old title}`
   exactly** before acting, and never reconcile against a mere prefix/substring match. When exactly one
   exact match exists:
   - **Renamed row:** rename that item to `[Maintenance] {new title}` (a provider title-edit op —
     GitHub adapter: `gh issue edit <N> --title ...`) to keep the reconciliation key consistent, or
     close it (adapter: "Close item") if the user is instead retiring the item.
   - **Dropped row:** close that item (adapter: "Close item") with a comment noting the recurring item
     was retired from the schedule — otherwise the `recurring`-labeled issue lingers unreachable.
   A rename or drop with no exact-match open item needs no reconciliation.
9. **Verify after remediation.** Re-run the `check` probes on the written binding and schedule — binding
   validity, including that any `config.role_labels` step 2 wrote survived the step-7 write intact and
   is well-formed; JSON validity; unique `id`/`title`; tracked-not-ignored — and report the actual
   results, never success on the write alone. This re-run is scoped to those probes: step 6 already
   owns whether the resolved label exists in the provider, so do not repeat that lookup here.

## Canonical role labels (optional remap)

`apply` runs this pass at **step 2** of its numbered flow, immediately after the bind and before any
schedule work — see that list above. The work-items actions speak three
canonical roles — `autonomous-eligible`, `human-gated`, `recurring-maintenance` — and resolve each
repo-actual label string from the tracker binding: `.work-item-tracker.json`, key
`config.role_labels`. Absent entries fall back to the defaults `agent-ready` / `needs-human` /
`recurring`, so a repo that never remaps needs no binding change at all. Role semantics and the
binding shape live in the plugin's
[`${CLAUDE_PLUGIN_ROOT}/reference/label-taxonomy.md`](${CLAUDE_PLUGIN_ROOT}/reference/label-taxonomy.md)
"Canonical roles".

1. **Skip silently when `.work-item-tracker.json` is absent** — the tracker seam isn't bound in
   this repo, so there is nothing to remap.
2. **Read the current binding first** and present each role with its currently-resolved label
   (the default when unset). RECOMMENDED: keep the defaults — remap only when the repo already
   uses a different vocabulary for these markers. With no interactive user, take that recommendation
   silently per `apply`'s "Autonomous invocation" rule: the pass completes as a no-op, leaving
   `config.role_labels` absent so every role resolves to its documented fallback.
3. **On a remap**, per role:
   - Verify the target label exists via the adapter's label listing; route creation through the
     repo's label-as-code owner under the same policy the schedule step applies — never create ad hoc.
   - For `human-gated`, warn before writing: the seam's `list-frontier --autonomous` exclusion
     keys on this label, and the shipped seam reads `needs-human` — remap it only when the bound
     seam resolves the same `config.role_labels` key, or the frontier filter and the skill will
     disagree about what autonomous agents may pick up.
4. **Write the binding**: re-read `.work-item-tracker.json` from disk immediately before writing
   and merge only the `config.role_labels` key — the binding carries seam-required keys
   (`provider`, `config.lease_ttl_hours`, …) that must survive untouched. Omit entries that keep
   their default rather than snapshotting defaults into the file.

Re-running `apply` once every role resolves as intended changes nothing **in this pass** and reports
"already configured" for the role labels. That says nothing about the rest of `apply`: a schedule still
carrying zero rows re-offers seeding on every run, by design.

## Output

A tracked `.work-item-tracker.json` binding (provider + non-secret config) and a tracked
`.github/recurring-schedule.json`, both in the consuming repo, plus a one-paragraph summary: the bound
provider and config, the recurring items written (id, cadence, next_due) — or, on the skipped path,
that only the empty skeleton was written and that `apply --seed-schedule` bulk-seeds rows whenever the
operator wants them — whether any labels were created, any role→label remap written to
`.work-item-tracker.json`, and how to re-run this setup to reconfigure. On a `check`-only run, the
PASS/FAIL/INFO table and its remediation lines, mutating nothing.

## What this skill does NOT do

- Run tracker operations — no item is created, claimed, or closed here. Filing and coordination are
  `/work-items:track` (`add`, `due`, `recheck`), `/work-items:work`, and `/work-items:triage`. `check`
  only inspects config; `apply` seeds the binding, schedule, and optional role→label remap.
- Duplicate the per-item `add --recurring` path — that path stays for filing a single recurring item;
  setup is the bulk path that seeds or reshapes the whole schedule, opt-in on a first-time bind.
- Author or vendor a provider adapter — the seam ships the `github`, `local-markdown`, and `jira`
  adapters; a consumer-supplied adapter lives in the consuming repo at
  `${CLAUDE_PROJECT_DIR}/tools/work-item-tracker/adapters/<provider>/`, not written by setup.
- Store secrets — the binding is tracked in git and carries non-secret config only (a provider token is
  referenced by name from inside its adapter, never written here).
- Write machine-local state — the binding and schedule live in the consumer's tracked tree, never in
  the plugin directory or plugin data directory.
