# Resume detect (Step 0.4)

Full AskUserQuestion options + branch logic for the MANDATORY resume-detect check before building a new run checklist. State persists across `/clear` — the runner's per-profile JSONs + `briefing-deltas.md` survive any session boundary.

## Table of contents

- Detect call
- AskUserQuestion options
- Branch logic per option
- Auto-mode policy

## Detect call

```bash
node scripts/per-profile-runner.js detect-resume
```

**On `{noActiveRun: true}`** → fall through to Step 0.5 (build checklist + open new run).

**On `{noActiveRun: false, run_id, status, current_index, total, by_status, anti_bot, scope, cutoff, next_handle, items_added, completed_handles, deltas_lines, ...}`** → surface to user via `AskUserQuestion`.

## AskUserQuestion options

```text
Active run detected:
  run_id:        <run_id>
  status:        <in_progress|paused>
  scope:         <scope>
  cutoff:        <cutoff>
  progress:      <current_index>/<total> profiles
  navs:          <anti_bot.navs_used>/<anti_bot.cap>
  items added:   <items_added> in briefing-deltas.md (<deltas_lines> lines)
  next handle:   <next_handle>
  by_status:     <by_status>

Choose:
  [continue]      Resume orchestration loop from index <current_index>. Pick up posts/replies for <next_handle> next.
  [synthesize]    Stop capturing. Run summary + pipeline regen against what's captured so far. Mark run complete.
  [scrap]         Mark this run abandoned. Start a fresh run with current --scope/--cutoff/etc.
  [show-deltas]   Print briefing-deltas.md, then re-ask.
  [abort]         Exit. Run state untouched.
```

## Branch logic per option

- **continue:** skip Step 0.5 + Step 0.7 confirmation gate; jump straight to Wave 1 orchestration loop. The runner's `next-handle` auto-resolves the latest live run; no flags needed. Honor anti-bot pause as before — if `status === 'paused'`, first call `node ... resume-paused` to bump session_count + reset navs_used = 0, then loop.
- **synthesize:** mark run complete via `node ... summary` (recomputes by_status; sets master.status='complete' if conditions met) → run pipeline regen (Step 5 onwards: emit-slides-data + build-html/pptx/pdf + validate). Output reflects partial coverage; surface that in the summary line at top of meeting markdown.
- **scrap:** call `node ... abandon --reason="<short reason from user>"`. Then fall through to Step 0.5 normally — `init` (without --force) succeeds because the prior run is no longer in_progress/paused. New run gets fresh `run_id`.
- **show-deltas:** `cat ${CLAUDE_PLUGIN_DATA}/<profile>/context/runs/<run_id>/briefing-deltas.md`. Re-prompt the same 5-option AskUserQuestion afterward.
- **abort:** print "Aborted. Run <run_id> left at index <current_index>/<total>." and stop.

## Auto-mode policy

When running non-interactively (`/loop`, `/schedule`, `claude -p`, `CLAUDE_CODE_REMOTE=true`, `--yes`), default to **continue** if the active run's `--scope` and `--cutoff` match the current invocation; else default to **abort** with explanatory output. Don't auto-scrap — that's destructive.
