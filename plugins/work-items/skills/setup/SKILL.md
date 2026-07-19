---
name: setup
description: "Verify and configure the work-items plugin for this repository. check inspects read-only the tracked .github/recurring-schedule.json (presence, JSON validity, unique reconciliation keys), the jq and tracker-seam entry gates, and the recurring-maintenance role label; apply interviews the consumer for their recurring work items, infers candidates from the repo, writes the schedule, and optionally remaps the canonical role labels in the tracker binding. Use when: 'set up work-items', 'is work-items configured', 'configure the recurring schedule', 'work-items setup', 'seed recurring items', 'remap the work-item role labels', or the due/recheck/work actions report no recurring schedule configured. Re-runnable — safe to invoke again to reconfigure."
argument-hint: "check | apply"
user-invocable: true
disable-model-invocation: true
---

## Purpose

Verify and manage the consuming repo's tracked recurring-schedule config at
`.github/recurring-schedule.json` so the `due`, `recheck`, and `work` actions resolve a real schedule
instead of degrading to "no recurring schedule configured". This is the bulk / initial-config path;
the per-item `add --recurring` path (which appends a single row as a side effect of filing its work
item) stays as-is. Setup also owns the optional canonical-role → label remap in the tracker binding
(see "Canonical role labels" below).

The schedule is optional: with none, the recurring actions degrade gracefully, so its absence is a
reported INFO, never a FAIL. `check` inspects read-only; `apply` seeds or reshapes the schedule, then
re-runs `check`. No argument or `check` runs the check; `apply` runs the check first, then the
interview-and-write flow. Idempotent: re-running reads the existing file and offers updates rather than
overwriting blind. The schedule file is a plain tracked JSON file the skill reads and writes directly
(Read / Write / `jq`) — it is not a tracker record, so it does not route through the work-item-tracker
seam; only operations on the work items themselves (labels, item lookups, edits) go through the bound
provider.

## Resolving the schedule path

Root the path at the project root, never a bare relative path (which breaks when invoked from a
subdirectory):

```bash
SCHEDULE="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel)}/.github/recurring-schedule.json"
```

The file is version-controlled and shared by the whole team — it belongs in the consumer's `.github/`,
never in the plugin directory or any machine-local state.

## `check` (read-only)

Probe the schedule config and the seam's entry gates, and report a PASS/FAIL/INFO table with one
remediation line per FAIL. Modify nothing, and do NOT file items or run a recurring check.

1. **`jq` entry gate** — the authoritative check is
   [`${CLAUDE_PLUGIN_ROOT}/reference/tracker-seam.md`](${CLAUDE_PLUGIN_ROOT}/reference/tracker-seam.md)
   "entry-point presence checks"; probe it (`command -v jq`), don't restate it. Absent is FAIL with that
   reference's install remediation — the schedule snippets parse with `jq` unconditionally.
2. **Schedule presence** — resolve `SCHEDULE` (above). Absent → INFO: `due` / `recheck` / `work`
   degrade to "no recurring schedule configured"; `apply` seeds it. Present → continue.
3. **Schedule validity** — a present file parses as JSON with the root `{"items": [ ... ]}` shape
   (FAIL otherwise), and **both reconciliation keys are unique across the whole `items` array — every
   `id` AND every `title`**. A duplicate `id` (the key `recheck <id>` resolves against) or duplicate
   `title` (the key `due` / `work` match `[Maintenance] {title}` against) silently breaks
   reconciliation — FAIL, naming the collision.
4. **Tracked, not ignored** — a present schedule must be committed to be team-shared:
   `git check-ignore -v` on the resolved path; a non-empty result is FAIL with the matching pattern.
5. **Tracker binding + recurring-maintenance role label** — role-label resolution is an action-entry
   invariant per the tracker-seam reference; probe it. `.work-item-tracker.json` absent → INFO (the
   tracker seam isn't bound; the role remap has nothing to configure). Present → resolve
   `config.role_labels["recurring-maintenance"]` (default `recurring` when the entry is absent; a
   malformed, empty, or non-string configured value is FAIL). When a schedule exists, verify the
   resolved label is present via the adapter's label listing (GitHub adapter: `gh label list`): an
   absent label means a seeded `[Maintenance]` item lands unlabeled and goes invisible to the next
   `due` / `work` pass — FAIL, with the remediation being the repo's declared label provisioning
   process (never `gh label create` ad hoc). Missing `cadence:{cadence}` labels are taxonomy niceties —
   INFO.

## `apply` (idempotent)

Run `check`, then apply the convention-resolution ladder — config present → use it and offer updates;
absent → infer candidates from the repo and persist what the user accepts; cannot infer → ask;
otherwise write the empty `{"items": []}` skeleton so the recurring actions stop degrading. The row
shape, the root `{"items": []}` structure, and the cadence-duration table are defined once in
[`${CLAUDE_PLUGIN_ROOT}/skills/track/actions/add.md`](${CLAUDE_PLUGIN_ROOT}/skills/track/actions/add.md)
(step "If `--recurring`" and the Cadence Duration Table) — read that file for the authoritative field
list before writing. Proceed non-interactively where the invocation and the repo make the values
unambiguous; ask only where an item genuinely needs the user.

1. **Read the current file first.** If `.github/recurring-schedule.json` exists, load it and present a
   short summary (item count, each item's `id` / `cadence` / `next_due`, and which are already
   overdue against today). The interview proposes changes against that baseline; nothing is dropped
   without the user confirming. If the file is absent, say so and continue to inference.
2. **Infer candidate items before asking.** Recurring items can't be fully derived, but don't skip the
   rung — propose candidates from what the repo actually contains, each with a recommended cadence:
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
3. **Interview, one decision at a time, recommendation first.** For each candidate (and any custom item
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
4. **Confirm the recurring-maintenance role label is present — it is load-bearing, not optional.**
   Resolve the role from `.work-item-tracker.json` `config.role_labels["recurring-maintenance"]`,
   defaulting to `recurring` only when the file or entry is absent (a malformed, empty, or non-string
   configured value is an error, not a fallback). `due` / `work` enumerate open maintenance items with
   that resolved label, and the create path filters out labels the repo lacks — so if you write a
   schedule while the resolved label is absent, the first `[Maintenance]` item created (by the recurring
   automation or the `work` due-recurring tier) lands without that label, is invisible to the next
   `due` / `work` pass, and gets duplicated or reported as orphaned. Verify presence via the adapter's
   label listing (for the GitHub adapter, `gh label list`). **When the repository declares a
   label-as-code source of truth, that system is the sole writer — never `gh label create` labels ad
   hoc.** When the resolved label is missing, tell the user plainly that the schedule cannot be
   reconciled until the label is added through the repository's declared provisioning process; do not
   silently treat it as optional. This step files no items; for a row now in the schedule, its
   `[Maintenance]` item is created — item only, no extra schedule row — by the consuming repo's
   recurring automation or the `work` due-recurring tier when `next_due` arrives. Do **not** point users
   at `add --recurring` to create it: that per-item path appends another schedule row, duplicating an
   already-seeded item.
5. **Write the schedule.** Read the current file (if any) and merge the accepted items into the `items`
   array, keying each edited item on the **original `id` it had when read in step 1**, not its final
   `id` — so an id rename replaces the original row instead of leaving it behind. Concretely: replace
   the row whose id matches the item's origin id; append only genuinely new items (no origin row); and
   when the user renamed an id, drop the old-id row so `due` / `work` never see two rows for the same
   maintenance (which would create duplicate items). Preserve any existing rows the user did not
   touch. Before writing, **verify both reconciliation keys are unique across the whole `items` array —
   every final `id` AND every final `title`.** On any collision, stop and prompt the user to merge the
   two rows, replace one, or pick a unique value; never write a schedule with a duplicate `id` or
   `title`. Then write it back with the `{"items": [ ... ]}` root.
6. **Reconcile an existing row's open item when it is renamed OR dropped.** Both operations strand the
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
7. **Verify after remediation.** Re-run the `check` probes on the written schedule — JSON validity,
   unique `id`/`title`, tracked-not-ignored — and report the actual results, never success on the write
   alone.

## Canonical role labels (optional remap)

After the schedule interview, offer the role→label remap. The work-items actions speak three
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
   uses a different vocabulary for these markers.
3. **On a remap**, per role:
   - Verify the target label exists via the adapter's label listing; route creation through the
     repo's label-as-code owner exactly as in the schedule step above — never create ad hoc.
   - For `human-gated`, warn before writing: the seam's `list-frontier --autonomous` exclusion
     keys on this label, and the shipped seam reads `needs-human` — remap it only when the bound
     seam resolves the same `config.role_labels` key, or the frontier filter and the skill will
     disagree about what autonomous agents may pick up.
4. **Write the binding**: re-read `.work-item-tracker.json` from disk immediately before writing
   and merge only the `config.role_labels` key — the binding carries seam-required keys
   (`provider`, `config.lease_ttl_hours`, …) that must survive untouched. Omit entries that keep
   their default rather than snapshotting defaults into the file.

Re-running `apply` after everything passes changes nothing and reports "already configured".

## Output

A tracked `.github/recurring-schedule.json` in the consuming repo, plus a one-paragraph summary of the
items written (id, cadence, next_due), whether any labels were created, any role→label remap written
to `.work-item-tracker.json`, and how to re-run this setup to reconfigure.

## What this skill does NOT do

- File work items or run a recurring check — that is `/work-items:track` (`add`, `due`, `recheck`)
  and `/work-items:work`. `check` only inspects config; `apply` only writes the schedule config.
- Duplicate the per-item `add --recurring` path — that path stays for filing a single recurring item;
  setup is the bulk / initial-config path that seeds or reshapes the whole schedule.
- Write machine-local state — the schedule lives in the consumer's tracked `.github/`, never in the
  plugin directory or plugin data directory.
