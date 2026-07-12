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
the per-item `add --recurring` path (which appends a single item as a side effect of filing its issue)
stays as-is. Idempotent: re-running reads the existing file and offers updates rather than overwriting
blind.

The item shape, the root `{"items": []}` structure, and the cadence-duration table are defined once in
[`${CLAUDE_PLUGIN_ROOT}/skills/work-items/actions/add.md`](../work-items/actions/add.md) (step "If
`--recurring`" and the Cadence Duration Table). This skill produces items in that exact shape — read
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
   the user names last), settle its fields against the shape in `actions/add.md`: `id` (kebab-case),
   `title`, `cadence` (one of the cadence table's values), `area[]`, `category`, `triggers[]` (external
   events warranting an early recheck — e.g. "new major framework release"), `notes`, and
   `close_previous`. Compute `next_due` as today + the cadence's day count (Cadence Duration Table in
   `actions/add.md`); set `last_checked` to today. Present one item at a time with your recommended
   values marked; the user accepts or edits before you move on.
4. **Confirm labels exist (optional).** The `due` / `work` actions match recurring issues by the
   `recurring` label and `[Maintenance]` title prefix; the `cadence:{cadence}` labels are used by the
   taxonomy. Offer to create any missing universal labels once via `gh label create`, or note their
   absence — never assume they exist. This step files no issues; the recurring automation or a later
   `add --recurring` creates the issues when items come due.
5. **Write the schedule.** Read the current file (if any), merge the accepted items into the `items`
   array (replace matching `id`s, append new ones), and write it back with the `{"items": [ ... ]}`
   root. Preserve any existing items the user did not touch. Confirm the file is tracked, not ignored.

## Output

A tracked `.github/recurring-schedule.json` in the consuming repo, plus a one-paragraph summary of the
items written (id, cadence, next_due), whether any labels were created, and how to re-run this setup to
reconfigure.

## What this skill does NOT do

- File issues or run a recurring check — that is `/work-items:work-items` (`add`, `due`, `recheck`,
  `work`). Setup only writes the schedule config.
- Duplicate the per-item `add --recurring` path — that path stays for filing a single recurring issue;
  setup is the bulk / initial-config path that seeds or reshapes the whole schedule.
- Write machine-local state — the schedule lives in the consumer's tracked `.github/`, never in the
  plugin directory or plugin data directory.
