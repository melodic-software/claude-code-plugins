# Action: `start`

Claim a work item through the seam (assignee + lease record).

## Usage

```
/work-items:track start <number or text match>
```

## Workflow

1. **Resolve the item.** If a number is given, build its fully-qualified ID (adapter: "Resolve item ID"). If text is given, search for it (adapter: "Search items", bare read) — the search emits raw `gh` fields, so take the matched item's `number` and build its fully-qualified ID via "Resolve item ID" (the seam rejects a bare number). If multiple matches, present them and ask the user to clarify; if exactly one, proceed.

1. **Pre-check + reclaim.** Fetch current state, then clear any stale lease so a crashed session's claim is recoverable — `reclaim` is idempotent, so a live lease is left untouched (matches `work` Step 0):

   ```bash
   TRACKER="${CLAUDE_PLUGIN_ROOT}/tools/work-item-tracker/work-item-tracker.sh"
   [[ -f "$TRACKER" ]] || TRACKER="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel)}/tools/work-item-tracker/work-item-tracker.sh"
   "$TRACKER" get-item "<id>"
   "$TRACKER" reclaim "<id>"
   ```

   If the item is still assigned to another user after reclaim, its lease is live — warn: "Item `<id>` held by {assignee} (live lease). Proceed anyway? (yes / pick different)". Without the reclaim, `claim` would back off (exit 7) on the stale assignee before evaluating lease expiry.

   Exit `6` (capability-unsupported, CONTRACT.md "Exit codes") means the bound provider declares `reclaim: false` (e.g. `local-markdown`, whose `claim` already race-checks the lease pre-write — CONTRACT.md "Adapter contract") — not an error; skip the stale-lease check and proceed straight to Claim.

   A **harness denial of the `reclaim` call itself** takes the same posture. Under auto mode the permission classifier can refuse the Bash tool call before the script runs, so no exit code is produced (CONTRACT.md "Exit codes"; observed on `#1381`). Report it once, skip the stale-lease check, and proceed straight to Claim — never retry the denied call, and never self-widen permissions to work around it (`${CLAUDE_PLUGIN_ROOT}/reference/permission-preflight.md` "Why a preflight, not a fixer"). A live foreign lease is still caught: `claim` backs off with exit `7`.

1. **Claim via the seam.** The `claim` verb runs the full race-safe, same-identity-aware protocol (assign `@me` → re-read → post lease comment → re-read leases → back off on a foreign earlier lease) and emits the claim object, or exits `7` on a lost race:

   ```bash
   TRACKER="${CLAUDE_PLUGIN_ROOT}/tools/work-item-tracker/work-item-tracker.sh"
   [[ -f "$TRACKER" ]] || TRACKER="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel)}/tools/work-item-tracker/work-item-tracker.sh"
   "$TRACKER" claim "<id>"
   ```

   - Exit `0` — claim held; the emitted object carries `holder`, `lease_comment_id`, `acquired_at`, `ttl_hours`. Record `lease_comment_id` if you may renew later (`${CLAUDE_PLUGIN_ROOT}/tools/work-item-tracker/work-item-tracker.sh renew-lease "<id>" --lease-comment-id <n>`).
   - Exit `7` — another session won; report it and pick a different item (do NOT retry the same one).

   Claim identity is the authenticated session user, never the bot (seam identity routing: `${CLAUDE_PLUGIN_ROOT}/tools/work-item-tracker/CONTRACT.md` "Identity routing (GitHub adapter)").

1. **Confirm:** "Claimed **`<id>`**: {title}. Ready to work — follow the project's development workflow."

1. **Suggest branch name.** Signal the closing-keyword link upstream so `/pull-request create` can auto-inject `Closes #N` from the branch parse. The agent NEVER runs `git checkout` itself; it emits the command for the user.

   **Derive the branch `<type>` vocabulary** (the commit-layer prefix — `feat`/`fix`/`chore`/…) from the item's **issue type**. Prefer the native GitHub Issue Type when present: `Bug` → `fix`, `Feature` → `feat`, `Task` → `chore`. Fall back to a `type:` label (personal / non-org repos, or a not-yet-migrated org item): the coarse long-form labels map like the native types — `type: bug` → `fix`, `type: feature` → `feat`, `type: task` → `chore`; a legacy commit-style label maps by Conventional Commits priority — `feat > fix > refactor > docs > chore > test > build > perf`, first match wins, strip the `type:` prefix. Default to `chore` when neither is present.

   **Derive `<slug>`** from the item title: lowercase, replace non-alphanumeric runs with `-`, trim leading/trailing `-`, cap 40 chars.

   **Existing-branch check first** (skip prompt if branch already correct):

   ```bash
   BRANCH="$(git branch --show-current 2>/dev/null || true)"
   CURRENT_N=""
   if [[ "$BRANCH" =~ ^[a-z]+/(routine-issue-)?([0-9]+)- ]]; then
     CURRENT_N="${BASH_REMATCH[2]}"
   fi
   # Resolve <base-ref> for the suggestions below from the remote's OWN default
   # branch. The local symbolic ref is only a cache — a clone made by
   # `git remote add` + `git fetch` never has it — so fall through to asking the
   # remote itself. No literal default is guessed at either rung.
   BASE_REF="$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null || true)"
   if [[ -z "$BASE_REF" ]]; then
     REMOTE_HEAD="$(git ls-remote --symref origin HEAD 2>/dev/null |
       sed -n 's|^ref: refs/heads/\([^[:space:]]*\).*|\1|p' | head -n1)"
     [[ -n "$REMOTE_HEAD" ]] && BASE_REF="origin/$REMOTE_HEAD"
   fi
   ```

   `<base-ref>` below is a placeholder the agent substitutes with the resolved value, exactly as it substitutes `<type>` / `<N>` / `<slug>`. The emitted command runs in the USER's terminal, which never saw the agent's `BASE_REF` assignment — emitting the variable unexpanded would hand over an empty pathspec.

   **`BASE_REF` still empty** (offline, no `origin` remote, or a remote with no HEAD) — do NOT substitute a guessed default branch, which is the failure this resolution exists to prevent. Emit the command with no start-point (`git checkout -b <type>/<N>-<slug>`, which branches from the current `HEAD`) and say the default branch could not be resolved, so the user can supply a base explicitly.

   - **`CURRENT_N` == claimed `<N>`** → acknowledge: "Already on `<current-branch>` — branch matches claimed #N. No rename needed." Skip prompt. Done.
   - **`CURRENT_N` is a different number** → multi-claim 3-option (below).
   - **`CURRENT_N` empty** (no number on current branch) → present bare suggestion: "Suggest branch `<type>/<N>-<slug>`. Switch? (yes / no — orphan-PR path)". On `yes`, emit `git checkout -b <type>/<N>-<slug> <base-ref>` for the user. On `no`, continue on current branch — `/pull-request create` falls through to its interactive Closes-keyword prompt.

   **Multi-claim 3-option** — when on `<other-type>/<OTHER>-<other-slug>` and just claimed #N (different item):

   1. **Switch to `<type>/<N>-<slug>`** — WARN: uncommitted work on the current branch must be committed or stashed first; the agent never runs `git stash` on a shared branch without confirming. Emit `git checkout -b <type>/<N>-<slug> <base-ref>` for the user.
   1. **Stay on current branch and cover both in one PR** — `/pull-request create` will inject `Closes #<OTHER>` + `Closes #<N>` at PR-time via its multi-issue prompt.
   1. **Skip** — decide later; continue on current branch without rename.

## Notes

- In GitHub Actions context, `@me` cannot resolve to a human — pass `--session-id "$GITHUB_ACTOR"` to `claim` for diagnostic attribution; the assignee is still the authenticated token identity.
- The seam claim replaces the retired `status:considering` / `status:claimed` label hold protocol — coordination is assignee + lease, race-safe via lease-comment identity (`${CLAUDE_PLUGIN_ROOT}/tools/work-item-tracker/CONTRACT.md` "Lease protocol").
- Stale claims (expired lease, no activity) are cleared by the `reclaim` verb at session start (`/work-items:track audit`, `/work-items:work`).
