---
description: "Verify and configure the work-items plugin for this repo. check read-only inspects the tracker binding (.work-item-tracker.json), tracked .github/recurring-schedule.json (presence, JSON validity, unique reconciliation keys), jq and tracker-seam entry gates, recurring-maintenance role label, work-class axis, and capability-tier axis; apply binds the provider, writes the schedule, migrates work-class and capability-tier labels when authorized, backfills legacy frontier stamps to the label, and optionally remaps canonical role labels. First-time bind writes minimum viable config only, binding, role labels, both label axes, legacy backfill, empty skeleton, and candidate inference plus per-item interview is opt-in via --seed-schedule or a skip-RECOMMENDED offer (silent when unattended); a schedule with items is summarized and offered updates as before. Use when: 'set up work-items', 'bind the tracker provider', 'is work-items configured', 'configure the recurring schedule', 'work-items setup', 'seed recurring items', 'bulk-seed the recurring schedule', 'remap the work-item role labels', or the due/recheck/work actions report no recurring schedule configured, or the seam reports no binding. Re-runnable. Safe to invoke again to reconfigure or to seed the schedule later."
argument-hint: "check | apply [--seed-schedule] [--accept-recommended]"
user-invocable: true
disable-model-invocation: true
---

## Purpose

Verify and configure the work-items plugin for the consuming repo. Setup owns three concerns: **bind
the tracker provider** (the tracked `.work-item-tracker.json` at the project root, the once-per-repo
declaration the seam needs before any verb runs; see "Provider binding" below), the tracked
recurring-schedule config at `.github/recurring-schedule.json` so the `due`, `recheck`, and `work`
actions resolve a real schedule instead of degrading to "no recurring schedule configured", and the
optional canonical-role → label remap in the binding (see "Canonical role labels" below). The
recurring-schedule pass is the bulk path for seeding or reshaping the whole schedule at once; the
per-item `add --recurring` path (which appends a single row as a side effect of filing its work item)
stays as-is. That bulk pass is opt-in rather than part of initial config: a first-time bind writes the
empty skeleton and stops there, because that bind is usually reached as a detour from another verb
reporting "no binding", the operator came to do something else, and should not be walked through a
per-item interview to get there.

Check-centric per the uniform setup contract (`docs/PLUGIN-PHILOSOPHY.md`
"Setup is explicit and repeatable" in the marketplace repository): `check` inspects read-only and
reports a PASS/FAIL/INFO table; `apply` binds the provider, writes or reshapes the schedule, and
offers the role remap, then re-runs `check`. No argument or `check` runs the check; `apply` runs the
check first, then the bind-and-write flow; `apply --seed-schedule` additionally opts in to the
candidate-inference-and-interview pass. Idempotent: re-running reads the on-disk files and offers
updates rather than overwriting blind. The schedule file is a plain tracked
JSON file the skill reads and writes directly (Read / Write / `jq`). It is not a tracker record, so it
does not route through the work-item-tracker seam; only operations on the work items themselves (labels,
item lookups, edits) go through the bound provider.

## Resolving the paths

Root both paths at the project root, never a bare relative path (which breaks when invoked from a
subdirectory):

```bash
BINDING="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel)}/.work-item-tracker.json"
SCHEDULE="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel)}/.github/recurring-schedule.json"
```

Both files are version-controlled and shared by the whole team. They belong in the consumer's tree
(`.work-item-tracker.json` at the project root, the schedule under `.github/`), never in the plugin
directory or any machine-local state.

## Provider binding (the tracker seam)

`apply` runs this first, the recurring-schedule and role-label passes below resolve the binding; the
`check` binding probe validates it read-only. The tracker seam runs against exactly one provider per
repo, declared in the tracked `.work-item-tracker.json` at the project root (resolved as `BINDING`
above); every seam verb resolves the bound provider from it, and with no binding the seam hard-errors
(exit 3). The seam **ships with this plugin** and bundles the `github`, `local-markdown`, `jira`, `gitea`, and `linear`
adapters. Installing the plugin is enough; a repo only declares which one it uses. Binding shape, discovery, and
adapter resolution are the seam contract's
[`${CLAUDE_PLUGIN_ROOT}/tools/work-item-tracker/CONTRACT.md`](${CLAUDE_PLUGIN_ROOT}/tools/work-item-tracker/CONTRACT.md)
"Setup (binding file)" and "Adapter resolution".

Step 1's keep-or-re-bind recommendation and the steps 2–3 interview are all decisions. With no
interactive user, resolve them by `apply`'s "Autonomous invocation" rule below rather than asking,
it fixes what the RECOMMENDED answers resolve to (including that an existing binding is kept), and
when this pass must stop instead of guessing.

1. **Read the current binding first.** If `.work-item-tracker.json` exists, load it and report the
   bound `provider` and `config`. RECOMMENDED: keep it. Re-bind only to switch providers or fix
   config. If it is absent, say so and continue to the interview.
2. **Choose the provider**, recommendation first. One line each below; the selection detail,
   how to verify a `github` bind, what each provider can and cannot do, and every config key,
   is `reference/providers.md`. Read it before recommending, and cite it when explaining a
   capability gap.
   - **`github`** (RECOMMENDED). Full-parity coordination over GitHub Issues via the ambient `gh`
     CLI. `gh repo view --json owner,name` is the operative bind-time test (`gh auth status` is
     not, see the reference).
   - **`local-markdown`**, the offline reference provider; branch- and worktree-confined, so
     **never** a coordination surface. Needs `config.storage_dir`.
   - **`jira`**. Read/resolve-only against a Jira Cloud project set. Consume-only, so it does not
     enable `/work-items:work` or `track start`.
   - **`linear`**. Full verb parity with `github`, so it **is** a coordination surface. Personal
     API key (the headless-appropriate credential); issue numbering lives outside the repo.
   - **`gitea`**. Gitea / Forgejo, self-hostable and free. Issues and dependency edges, but **no
     leases and no sub-items**, so `/work-items:work` cannot claim on it.
   - **another provider**. Put its adapter consumer-local under
     `<repo root>/tools/work-item-tracker/adapters/<provider>/`; the seam resolves those ahead of
     the bundled set, so no fork is needed. `/work-items:onboard-adapter` (if installed) generates
     one rather than starting from a blank file.
3. **Settle the config, all non-secret.** `lease_ttl_hours` (REQUIRED for every provider;
   RECOMMENDED `24`) plus that provider's own subtree, the per-provider key table is in
   `reference/providers.md`. Interview for each value; for any token, ask for the env-var **NAME**
   and probe that it resolves in-env at bind time.
   - **Secrets never go in this file**. It is tracked in git. A provider that needs an API token
     references it by env-var name / the repo's secret-store convention from inside its adapter, never
     as a literal here. `github` needs none (ambient `gh`); `jira`, `gitea`, and `linear` reference theirs by
     `auth_env` name.
4. **Write the binding.** Re-read `.work-item-tracker.json` from disk immediately before writing and
   merge: preserve any existing `config.role_labels` (owned by the role-label pass below) and any
   other keys. Write `schema_version: "1.0"`, the chosen `provider`, the `config`, and, unless one
   already exists, the self-describing `docs` pointer (CONTRACT.md "Setup (binding file)"). Confirm
   the file is tracked, not ignored.
5. **Ensure the personal-overlay gitignore line.** The gitignored per-user overlay
   (`.work-item-tracker.local.json`, allowlisted keys only. CONTRACT.md "Setup (binding file)") sits
   at the repo root, outside the `.claude/**/*.local.*` convention line, so `apply` must confirm a
   repository `.gitignore` rule covers it even when the overlay file does not exist yet, and append
   that line when none does, **announcing the edit** (ADR 0015; touch nothing else there).
   `$GIT_DIR/info/exclude` and `core.excludesFile` do not protect a teammate. A *tracked* overlay
   in the index is a finding to stop and report, never ignore. Ignored and untracked are **two
   independent probes**; a bare `git check-ignore` is silent for an already-tracked path. Run the
   probes as [`reference/overlay-ignore-probes.md`](reference/overlay-ignore-probes.md) specifies,
   including why the ignore verdict must NOT come from `check-ignore -v`'s exit code.

Example (`github`; `local-markdown` adds `"storage_dir": ".work-items"`):

```json
{
  "schema_version": "1.0",
  "provider": "github",
  "docs": "Work-item tracker binding — see the work-items plugin's tools/work-item-tracker/CONTRACT.md (Setup)",
  "config": { "lease_ttl_hours": 24 }
}
```

## `check` (read-only)

`check` inspects and reports; it writes nothing. Read [reference/check.md](reference/check.md)
when invoked with `check` or with no action, and again at the start of `apply`, which runs the same
probes first: it owns the probe order, every PASS/FAIL/INFO row, and the remediation line each FAIL
prints. `apply` below consumes those probe results and never re-derives them. The `jq` and
tracker-binding entry gates that check.md's probe 1 tests are defined in
[`${CLAUDE_PLUGIN_ROOT}/reference/tracker-seam.md`](${CLAUDE_PLUGIN_ROOT}/reference/tracker-seam.md)
"entry-point presence checks"; read it for what each gate enforces and its remediation.

## `apply` (idempotent)

Run `check`, then bind the provider (step 1) before the schedule and role-label passes. The schedule
branches on **how many rows the schedule already carries**, never on whether the file exists. A
skipped first-time `apply` leaves `{"items": []}` on disk, so a file-absence gate would make the
seeding path unreachable by re-running:

- **Schedule carries ≥1 item**. Unchanged from before: summarize it, infer candidates, and interview
  against that baseline (steps 7–9), offering updates. `--seed-schedule` is a no-op here; this branch
  already interviews.
- **Schedule absent, or present with an empty `items` array**. Write only the minimum viable config:
  the provider binding, the role-label pass, and the empty `{"items": []}` skeleton so `due` /
  `recheck` / `work` stop degrading to "no recurring schedule configured". Steps 4–5 do not run: no
  candidate inference, no per-item interview. **This is the default.**
- **Schedule present but not parseable as the `{"items": [ ... ]}` root**, no `items` key, a null or
  non-array `items`, a non-object root, or invalid JSON. This is a `check` FAIL, not a zero-row
  schedule: stop and report it rather than treating it as either branch, because overwriting or
  "leaving it untouched" both leave a malformed file the recurring actions cannot read.

Seeding rows on the empty/absent branch is **opt-in**, satisfied by any one of: the explicit
`--seed-schedule` argument; an accepted yes/no offer; or an invocation that in its own words asks for
the schedule to be seeded (e.g. "seed a sensible recurring schedule for this repo"), an explicit
request IS the opt-in, so honor it without re-asking. Otherwise offer exactly once, before step 7, as a
single yes/no with **skip marked RECOMMENDED**: name that seeding walks them through one interview per
candidate item, that the skeleton alone already stops the degradation, and that re-running `apply` (or
`apply --seed-schedule`) bulk-seeds later at any time. On skip, say so plainly and go to step 10.

### Autonomous invocation (no interactive user)

When `apply` runs in an unattended or loop-driven context there is nobody to answer any of its
questions, and blocking on one strands the run. Read
[reference/autonomous-apply.md](reference/autonomous-apply.md) before the first decision point of
an unattended `apply`, and follow it for every decision in the flow, not only the seeding offer: it
owns the silent-resolve rule, the never-guess rule, the per-pass unattended resolutions, and what
the run must say in its summary about each decision it took without asking.

### The `apply` flow, step by step

Attended and unattended runs take the same twelve steps; only the answers differ.

The row shape, the root `{"items": []}` structure, and the cadence-duration table are defined once in
[`${CLAUDE_PLUGIN_ROOT}/skills/track/actions/add.md`](${CLAUDE_PLUGIN_ROOT}/skills/track/actions/add.md)
(step "If `--recurring`" and the Cadence Duration Table). Read that file for the authoritative field
list before writing. Proceed non-interactively where the invocation and the repo make the values
unambiguous; ask only where an item genuinely needs the user.

1. **Bind the tracker provider first.** Run the "Provider binding" procedure above. Seed or update
   `.work-item-tracker.json` before any pass below resolves it. Every step that follows reads the bound
   provider and its `config.role_labels` from that file; the seam hard-errors (exit 3) without it.
2. **Offer the canonical role→label remap.** Run the "Canonical role labels (optional remap)" procedure
   below, which writes `config.role_labels` into the binding just seeded. It is anchored here, after
   the bind, before any schedule work, so it runs identically on the skipped first-time path (where no
   interview happens) and on the seeding path, and every later step resolves the post-remap labels.
3. **Migrate the work-class label axis.** Run the "Work-class label axis (migration)" procedure below.
   It discovers missing canonical members and provisions them when authorized. When any member is still
   missing after this pass, stop. Triage and the work-loop admission gate cannot operate correctly.
4. **Migrate the capability-tier label axis.** Run the procedure in
   [reference/capability-tier-axis-migration.md](reference/capability-tier-axis-migration.md), which
   provisions the canonical `capability-tier: frontier` member defined in
   [`${CLAUDE_PLUGIN_ROOT}/reference/capability-tier-labels.md`](${CLAUDE_PLUGIN_ROOT}/reference/capability-tier-labels.md).
   When the canonical member is still missing after this pass, stop. Triage cannot stamp frontier-tier
   quota guard and the work-loop reader fails closed to general tier.
5. **Backfill legacy frontier-tier body stamps.** Run the procedure in
   [reference/capability-tier-backfill.md](reference/capability-tier-backfill.md). This pass is
   load-bearing on upgrade (#1716): items already triaged with only a body prose frontier-tier stamp
   will not be re-triaged, so setup applies the label here once the axis exists.
6. **Read the current schedule file first.** If `.github/recurring-schedule.json` exists, load it and
   present a short summary (item count, each item's `id` / `cadence` / `next_due`, and which are already
   overdue against today). The interview proposes changes against that baseline; nothing is dropped
   without the user confirming. If the file is absent or carries an empty `items` array, say so and
   settle the opt-in decision above before steps 7–8.
7. **Infer candidate items before asking. Steps 7 and 8 run on the seeding path only** (the schedule
   already carries ≥1 item, or seeding was opted into). On the default skipped path, run neither and go
   straight to step 9. Recurring items can't be fully derived, but don't skip the rung. Propose
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
8. **Interview, one decision at a time, recommendation first.** When `--accept-recommended` is set
   alongside `--seed-schedule`, skip the interview: accept every inferred candidate from step 7 with
   its recommended field values and proceed to step 9. Otherwise, for each candidate (and any custom item
   the user names last), settle its fields against the shape in
   [`${CLAUDE_PLUGIN_ROOT}/skills/track/actions/add.md`](${CLAUDE_PLUGIN_ROOT}/skills/track/actions/add.md): `id` (kebab-case),
   `title`, `cadence` (one of the cadence table's values), `area[]`, `category`, `triggers[]` (external
   events warranting an early recheck. E.g. "new major framework release"), `notes`, and
   `close_previous`. Present one item at a time with your recommended values marked; the user accepts
   or edits before you move on. Date handling depends on whether the item is new or already present,
   setup seeds the schedule but never performs the maintenance, so it must not advance the cadence
   clock on an existing item (that is `recheck`'s job, gated on the check actually being done):
   - **New item:** seed `last_checked` to today and `next_due` to today + the cadence's day count
     (Cadence Duration Table in [`${CLAUDE_PLUGIN_ROOT}/skills/track/actions/add.md`](${CLAUDE_PLUGIN_ROOT}/skills/track/actions/add.md)).
   - **Existing item:** preserve its current `last_checked` and `next_due` as-is. Only recompute
     `next_due` when the user explicitly reschedules or changes the cadence, and even then never set
     `last_checked` to today (setup did no maintenance). Blindly resetting the dates would drop an
     already-overdue item out of the `due` / `work` recurring tiers, which both select on
     `next_due <= today`.
9. **Confirm the recurring-maintenance role label is present in the provider. Load-bearing whenever
   the schedule will carry rows.** (Step 2 settled which label string each role resolves to; this step
   verifies that string actually exists.) Key this on the schedule's **final row count**, not on what
   this run wrote: with ≥1 row (written now or already on disk) a missing label is reported as a hard
   finding, exactly as spelled out below. With zero
   rows, the skipped first-time bind's empty skeleton, no `[Maintenance]` item can ever be created
   from that schedule, so a missing label is **informational, not a gate**: report it, note it must
   exist before the schedule is ever seeded, and continue without blocking the bind.
   Resolve the role from `.work-item-tracker.json` `config.role_labels["recurring-maintenance"]`,
   defaulting to `recurring` only when the file or entry is absent (a malformed, empty, or non-string
   configured value is an error, not a fallback). `due` / `work` enumerate open maintenance items with
   that resolved label, and the create path filters out labels the repo lacks, so if you write a
   schedule while the resolved label is absent, the first `[Maintenance]` item created (by the recurring
   automation or the `work` due-recurring tier) lands without that label, is invisible to the next
   `due` / `work` pass, and gets duplicated or reported as orphaned. Verify presence via the adapter's
   label listing (for the GitHub adapter, `gh label list`). **When the repository declares a
   label-as-code source of truth, that system is the sole writer, never `gh label create` labels ad
   hoc.** When the resolved label is missing and the schedule carries rows, tell the user plainly that
   the schedule cannot be reconciled until the label is added through the repository's declared
   provisioning process; do not silently treat it as optional. This step files no items; for a row now
   in the schedule, its `[Maintenance]` item is created, item only, no extra schedule row, by the consuming repo's
   recurring automation or the `work` due-recurring tier when `next_due` arrives. Do **not** point users
   at `add --recurring` to create it: that per-item path appends another schedule row, duplicating an
   already-seeded item.
10. **Write the schedule.** On the skipped path there is nothing to merge: write the `{"items": []}`
   skeleton when the file is absent, leave an already-empty file untouched, and go to step 12. Step 11
   has no renamed or dropped row to reconcile. Otherwise read the current file (if any) and merge the
   accepted items into the `items`
   array, keying each edited item on the **original `id` it had when read in step 6**, not its final
   `id`, so an id rename replaces the original row instead of leaving it behind. Concretely: replace
   the row whose id matches the item's origin id; append only genuinely new items (no origin row); and
   when the user renamed an id, drop the old-id row so `due` / `work` never see two rows for the same
   maintenance (which would create duplicate items). Preserve any existing rows the user did not
   touch. Before writing, **verify both reconciliation keys are unique across the whole `items` array,
   every final `id` AND every final `title`.** On any collision, stop and prompt the user to merge the
   two rows, replace one, or pick a unique value; never write a schedule with a duplicate `id` or
   `title`. Then write it back with the `{"items": [ ... ]}` root. Confirm the file is tracked, not
   ignored.
11. **Reconcile an existing row's open item when it is renamed OR dropped.** Both operations strand the
   row's live `[Maintenance] {old title}` recurring item (if still open): after write the schedule no
   longer carries that title, so `due` / `work`, which derive recurring candidates only from the
   schedule, and whose frontier tiers exclude items carrying the resolved recurring-maintenance label, will never surface it again,
   leaving it stale outside the normal flow (a rename additionally risks a duplicate under the new
   title). For each renamed or dropped existing row, look up its open item under the OLD title (adapter:
   "Search items", `--label <resolved recurring-maintenance label>`). Provider search is
   substring/prefix, not exact-title equality,
   so it can return a longer item (`[Maintenance] Review CI workflow pins`) when the old title was
   `Review CI`. **filter the results to the one whose title equals `[Maintenance] {old title}`
   exactly** before acting, and never reconcile against a mere prefix/substring match. When exactly one
   exact match exists. **Renamed row:** rename that item to `[Maintenance] {new title}` (a provider title-edit op.
   GitHub adapter: `gh issue edit <N> --title ...`) to keep the reconciliation key consistent, or
   close it (adapter: "Close item") if the user is instead retiring the item; **Dropped row:** close that item (adapter: "Close item") with a comment noting the recurring item
   was retired from the schedule. Otherwise the `recurring`-labeled issue lingers unreachable.
   A rename or drop with no exact-match open item needs no reconciliation.

12. **Verify after remediation.** Re-run the `check` probes on the written binding and schedule. Binding
   validity, including that any `config.role_labels` step 2 wrote survived the step-10 write intact and
   is well-formed; JSON validity; unique `id`/`title`; tracked-not-ignored, and report the actual
   results, never success on the write alone. This re-run is scoped to those probes: step 9 already
   owns whether the resolved recurring-maintenance label exists in the provider, so do not repeat that
   lookup here; steps 3–4 already own work-class and capability-tier axis provisioning.

## Work-class label axis (migration)

`apply` runs this pass at **step 3** of its numbered flow, after the role-label pass and before any
schedule work. Triage's autonomous-eligible outcomes and the work-loop admission gate require all five
canonical members from
[`${CLAUDE_PLUGIN_ROOT}/reference/work-class-labels.md`](${CLAUDE_PLUGIN_ROOT}/reference/work-class-labels.md).

1. **Skip when `.work-item-tracker.json` is absent**, nothing is bound yet.
2. **Skip when the bound provider has no label listing** (`local-markdown`, read-only `jira`), report
   INFO and continue; triage verifies at item-edit time.
3. **Discover** via the adapter's label listing (GitHub: `gh label list --limit 200`, filter
   `work-class:`). Compare against the five canonical members in the reference.
4. **All present**. Report "work-class axis provisioned" and continue.
5. **Any missing, label-as-code owner declared**, stop. Name each missing label and route remediation
   to that owner; never `gh label create` ad hoc.
6. **Any missing, no label-as-code owner, interactive user present**, offer to create each missing
   label via the adapter's label-creation mechanics (GitHub: `gh label create "<name>" --description
   "<description>" --color "<color>"` using the reference table). RECOMMENDED: create all missing
   members, this pass is the upgrade migration for repos that predated the axis. Re-list after
   creation and confirm all five exist before continuing.
7. **Any missing, no label-as-code owner, no interactive user**, stop per `apply`'s "Autonomous
   invocation" rule: "work-class axis needs provisioning; run `/work-items:setup apply` with a user
   present".

## Canonical role labels (optional remap)

`apply` runs this pass at **step 2** of its numbered flow, immediately after the bind and before any
schedule work. See that list above. The work-items actions speak three
canonical roles. `autonomous-eligible`, `human-gated`, `recurring-maintenance`, and resolve each
repo-actual label string from the tracker binding: `.work-item-tracker.json`, key
`config.role_labels`. Absent entries fall back to the defaults `agent-ready` / `needs-human` /
`recurring`, so a repo that never remaps needs no binding change at all. Role semantics and the
binding shape live in the plugin's
[`${CLAUDE_PLUGIN_ROOT}/reference/label-taxonomy.md`](${CLAUDE_PLUGIN_ROOT}/reference/label-taxonomy.md)
"Canonical roles".

1. **Skip silently when `.work-item-tracker.json` is absent**, the tracker seam isn't bound in
   this repo, so there is nothing to remap.
2. **Read the current binding first** and present each role with its currently-resolved label
   (the default when unset). RECOMMENDED: keep the defaults. Remap only when the repo already
   uses a different vocabulary for these markers. With no interactive user, take that recommendation
   silently per `apply`'s "Autonomous invocation" rule: the pass completes as a no-op, leaving
   `config.role_labels` absent so every role resolves to its documented fallback.
3. **On a remap**, per role:
   - Verify the target label exists via the adapter's label listing; route creation through the
     repo's label-as-code owner under the same policy the schedule step applies, never create ad hoc.
   - For `human-gated`, warn before writing: the seam's `list-frontier --autonomous` exclusion
     keys on this label, and the shipped seam reads `needs-human`. Remap it only when the bound
     seam resolves the same `config.role_labels` key, or the frontier filter and the skill will
     disagree about what autonomous agents may pick up.
4. **Write the binding**: re-read `.work-item-tracker.json` from disk immediately before writing
   and merge only the `config.role_labels` key, the binding carries seam-required keys
   (`provider`, `config.lease_ttl_hours`, …) that must survive untouched. Omit entries that keep
   their default rather than snapshotting defaults into the file.

Re-running `apply` once every role resolves as intended changes nothing **in this pass** and reports
"already configured" for the role labels. That says nothing about the rest of `apply`: a schedule still
carrying zero rows re-offers seeding on every run, by design.

## Output

A tracked `.work-item-tracker.json` binding (provider + non-secret config) and a tracked
`.github/recurring-schedule.json`, both in the consuming repo, plus a one-paragraph summary: the bound
provider and config, the recurring items written (id, cadence, next_due), or, on the skipped path,
that only the empty skeleton was written and that `apply --seed-schedule` bulk-seeds rows whenever the
operator wants them, whether any labels were created, any role→label remap written to
`.work-item-tracker.json`, and how to re-run this setup to reconfigure. On a `check`-only run, the
PASS/FAIL/INFO table and its remediation lines, mutating nothing.

## What this skill does NOT do

- Run tracker operations, no item is created, claimed, or closed here. Filing and coordination are
  `/work-items:track` (`add`, `due`, `recheck`), `/work-items:work`, and `/work-items:triage`. `check`
  only inspects config; `apply` seeds the binding, schedule, and optional role→label remap.
- Write the plugin cache, Claude Code user settings, or `pluginConfigs`.
- Duplicate the per-item `add --recurring` path, that path stays for filing a single recurring item;
  setup is the bulk path that seeds or reshapes the whole schedule, opt-in on a first-time bind.
- Author or vendor a provider adapter, the seam ships the `github`, `local-markdown`, and `jira`
  adapters; a consumer-supplied adapter lives in the consuming repo at
  `${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel)}/tools/work-item-tracker/adapters/<provider>/`, not written by setup.
- Store secrets, the binding is tracked in git and carries non-secret config only (a provider token is
  referenced by name from inside its adapter, never written here).
- Write machine-local state, the binding and schedule live in the consumer's tracked tree, never in
  the plugin directory or plugin data directory.
