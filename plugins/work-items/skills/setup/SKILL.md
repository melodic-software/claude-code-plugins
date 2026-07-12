---
name: setup
description: "Configure the work-items plugin's recurring-schedule seam for this repository: interview the consumer for their recurring work items (cadence, tiers, next_due), infer candidates from the repo layout, and write the tracked .github/recurring-schedule.json. Use when: 'set up work-items', 'configure the recurring schedule', 'work-items setup', 'seed recurring items', or the due/recheck/work actions report no recurring schedule configured. Re-runnable — safe to invoke again to reconfigure."
argument-hint: "(no arguments — interactive interview)"
user-invocable: true
disable-model-invocation: false
---

## Purpose

Write (or update) the consuming repo's tracked recurring-schedule config at
`.github/recurring-schedule.json` so the `due`, `recheck`, and `work` actions resolve a real schedule
instead of degrading to "no recurring schedule configured". This is the bulk / initial-config path;
the per-item `add --recurring` path (which appends a single row as a side effect of filing its work
item) stays as-is. Idempotent: re-running reads the existing file and offers updates rather than
overwriting blind. The schedule file is a plain tracked JSON file the skill reads and writes directly
(Read / Write / `jq`) — it is not a tracker record, so it does not route through the work-item-tracker
seam; only operations on the work items themselves (labels, item lookups, edits) go through the bound
provider.

The row shape, the root `{"items": []}` structure, and the cadence-duration table are defined once in
[`${CLAUDE_PLUGIN_ROOT}/skills/work-items/actions/add.md`](../work-items/actions/add.md) (step "If
`--recurring`" and the Cadence Duration Table). This skill produces rows in that exact shape — read
that file for the authoritative field list before writing.

## Resolving the schedule path

Root the path at the project root, never a bare relative path (which breaks when invoked from a
subdirectory):

```bash
SCHEDULE="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel)}/.github/recurring-schedule.json"
```

The file is version-controlled and shared by the whole team — it belongs in the consumer's `.github/`,
never in the plugin directory or any machine-local state.

## Task

Apply the convention-resolution ladder — config present → use it and offer updates; absent → infer
candidates from the repo and persist what the user accepts; cannot infer → ask; otherwise write the
empty `{"items": []}` skeleton so the recurring actions stop degrading.

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
   [`../work-items/actions/add.md`](../work-items/actions/add.md): `id` (kebab-case),
   `title`, `cadence` (one of the cadence table's values), `area[]`, `category`, `triggers[]` (external
   events warranting an early recheck — e.g. "new major framework release"), `notes`, and
   `close_previous`. Present one item at a time with your recommended values marked; the user accepts
   or edits before you move on. Date handling depends on whether the item is new or already present —
   setup seeds the schedule but never performs the maintenance, so it must not advance the cadence
   clock on an existing item (that is `recheck`'s job, gated on the check actually being done):
   - **New item:** seed `last_checked` to today and `next_due` to today + the cadence's day count
     (Cadence Duration Table in [`../work-items/actions/add.md`](../work-items/actions/add.md)).
   - **Existing item:** preserve its current `last_checked` and `next_due` as-is. Only recompute
     `next_due` when the user explicitly reschedules or changes the cadence — and even then never set
     `last_checked` to today (setup did no maintenance). Blindly resetting the dates would drop an
     already-overdue item out of the `due` / `work` recurring tiers, which both select on
     `next_due <= today`.
4. **Ensure the `recurring` label exists — it is load-bearing, not optional.** `due` / `work`
   enumerate open maintenance items by the `recurring` label (adapter: "List items", `--label
   recurring`), and the create path filters out labels the repo lacks — so if you write a schedule while
   the `recurring` label is absent, the first `[Maintenance]` item created (by the recurring automation
   or the `work` due-recurring tier) lands without that label, is invisible to the next `due` / `work`
   pass, and gets duplicated or reported as orphaned. When the label is missing, create it once through
   the bound provider (a provider label op — for the GitHub adapter, `gh label create recurring`; see
   the adapter's operations reference) — recommend this and default to it. If the user declines, tell
   them plainly that the schedule cannot be reconciled until the label exists, and do not silently treat
   it as optional. The `cadence:{cadence}` labels are taxonomy niceties (not required for
   reconciliation) — offer to create the missing ones, or note their absence. This step files no items;
   for a row now in the schedule, its `[Maintenance]` item is created — item only, no extra schedule
   row — by the consuming repo's recurring automation or the `work` due-recurring tier when `next_due`
   arrives. Do **not** point users at `add --recurring` to create it: that per-item path appends another
   schedule row, duplicating an already-seeded item.
5. **Write the schedule.** Read the current file (if any) and merge the accepted items into the `items`
   array, keying each edited item on the **original `id` it had when read in step 1**, not its final
   `id` — so an id rename replaces the original row instead of leaving it behind. Concretely: replace
   the row whose id matches the item's origin id; append only genuinely new items (no origin row); and
   when the user renamed an id, drop the old-id row so `due` / `work` never see two rows for the same
   maintenance (which would create duplicate items). Preserve any existing rows the user did not
   touch. Before writing, **verify both reconciliation keys are unique across the whole `items` array —
   every final `id` AND every final `title`.** `id` is the key `recheck <id>` resolves against; `title`
   is the key `due` / `work` match items against (`[Maintenance] {title}`). A new row or a rename that
   collides with a different preserved row on either key silently breaks reconciliation — a duplicate
   `id` makes `recheck` ambiguous, and a duplicate `title` makes two rows share one open item (or the
   second row gets skipped/claimed against the wrong maintenance). On any collision, stop and prompt the
   user to merge the two rows, replace one, or pick a unique value; never write a schedule with a
   duplicate `id` or `title`. Then write it back with the `{"items": [ ... ]}` root. Confirm the file is
   tracked, not ignored.
6. **Reconcile an existing row's open item when it is renamed OR dropped.** Both operations strand the
   row's live `[Maintenance] {old title}` recurring item (if still open): after write the schedule no
   longer carries that title, so `due` / `work` — which derive recurring candidates only from the
   schedule, and whose frontier tiers exclude `recurring`-labeled items — will never surface it again,
   leaving it stale outside the normal flow (a rename additionally risks a duplicate under the new
   title). For each renamed or dropped existing row, look up its open item under the OLD title (adapter:
   "Search items", `--label recurring`). Provider search is substring/prefix, not exact-title equality,
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

## Output

A tracked `.github/recurring-schedule.json` in the consuming repo, plus a one-paragraph summary of the
items written (id, cadence, next_due), whether any labels were created, and how to re-run this setup to
reconfigure.

## What this skill does NOT do

- File work items or run a recurring check — that is `/work-items:work-items` (`add`, `due`, `recheck`,
  `work`). Setup only writes the schedule config.
- Duplicate the per-item `add --recurring` path — that path stays for filing a single recurring item;
  setup is the bulk / initial-config path that seeds or reshapes the whole schedule.
- Write machine-local state — the schedule lives in the consumer's tracked `.github/`, never in the
  plugin directory or plugin data directory.
