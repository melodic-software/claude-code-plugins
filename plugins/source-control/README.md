# source-control

A Claude Code plugin bundling the git/GitHub delivery workflow as six
composable skills — commit mechanics, the single-PR lifecycle, the tiered
babysit fleet loop, worktree lifecycle management, convention setup, and
merge-conflict resolution.

## Skills

### `/source-control:commit`

Builds a commit the safe way: drafts a subject matching the resolved
convention — the layered `source-control.md` config (written by
`/source-control:setup`) → the consuming project's own
`CLAUDE.md`/rules/commit-msg hook → Conventional Commits (11-type vocabulary)
as the default — pre-checks it against the
pattern before git runs, appends a `Co-Authored-By: Claude …` trailer, and
feeds the message via Bash heredoc (`git commit -F - --cleanup=verbatim`) —
never PowerShell here-strings, never scratch files in `.git/`. Stages
surgically (`git add <path>`, never `-A`), and supports pathspec-limited
commits when the index is shared with a concurrent session. Right after
staging, it fixes the exec bit on newly-added shebang files and runs the
consuming repo's own formatter/linter (when one is discoverable) against the
staged files — catching what CI's exec-bit and lint lanes would otherwise
catch after the push round-trip.

### `/source-control:pull-request`

Orchestrates the PR lifecycle with two non-negotiable gates — every review
finding is verified before it is presented, and every CI fix is
research-gated:

- **prep** — review the branch diff (via your review agents/skills when
  installed, inline otherwise), verify findings, simplify, then run the
  project's build+test+lint gate as a hard block.
- **create** — branch-name check, default-branch rebase, unrelated-changes
  triage, `Closes #N` derivation from the branch name (validated against the
  live issue), safely-assembled PR body, `gh pr create`.
- **monitor** — async event loop over CI checks + review comments. Event
  delivery prefers a push channel when your environment ships one, falls back
  to a session-persistent Monitor watch (30s `gh` poll), or plain `gh`
  polling in cloud sessions. CI failures are read from complete logs via the
  bundled annotation/ZIP fetch scripts (`gh run view --log-failed`
  truncates); every reviewer comment gets explore → research → classify →
  react → reply → fix → verify-on-GitHub treatment.
- **merge** — 6-gate readiness re-verification, squash merge, worktree
  reuse/cleanup, post-merge CI health check. Never auto-merges.
- **fetch-logs** — tiered CI-log retrieval (annotations → full untruncated
  ZIP via the REST API → per-job text).

### `/source-control:babysit-prs`

Tiered, self-pacing fleet loop over your own open PRs (designed for
`/loop /source-control:babysit-prs`):

- **safe (default)** — discovers YOUR open PRs under the current repo's
  owner (or the configured watched owners), checks each out, keeps the
  branch fresh, processes every review finding individually with
  GitHub-verified evidence per the plugin-scope shared review discipline,
  finding classification mechanically gated by the bundled
  `babysit-readiness-gate.sh`. Never resolves threads, never merges — an
  engine-backed run reports merge-readiness from a read-only merge-gate
  run; the Python-free degrade has no merge gate and reports it unchecked.
- **worker** (explicit keyword) — everything safe does, plus auto-resolving
  pre-push-outdated bot threads and merging PRs a deterministic gate proves
  100% ready (`mergeStateStatus == CLEAN` plus explicit cross-checks, with
  an expected-head pin carried to GitHub's server-side match-head-commit
  guard). Requires Python 3 (stdlib only).
- **autopilot** (explicit keyword) — maximum autonomy for a solo owner:
  every author under the watched owners, resolves any thread it has
  addressed, merges through the same gate, escalates only what it genuinely
  cannot solve. Requires Python 3.

Cross-tier invariants: never an unprotected force-push, never `--admin`,
never GitHub settings or branch-protection changes, never a repository
outside the watched owners, and dependency-manager-authored PRs
(Dependabot/Renovate-class) are never merged autonomously in any tier. A
merge-capable tier engages only when the invocation names it — the
configured `default_tier` applies to explicitly typed invocations only,
never to auto-routed conversational matches. The two guarded mutations run
only through the plugin's pinned wrappers (`source-control-babysit-merge`,
`source-control-babysit-resolve-thread`), which fail closed without an
owner allowlist and reject unattended unpinned merges.

### `/source-control:worktree`

Git worktree lifecycle for parallel-session isolation: `create` (guided
naming, EnterWorktree, post-create setup checks), `status` (porcelain parse,
batched PR cross-reference, staleness classification), `cleanup`
(file-lock-aware removal that never counts a Windows husk as deleted, emits
destructive branch deletion for the user), `audit` (configuration health).

### `/source-control:setup`

`check` (read-only, default) reports the effective commit-subject / PR-title
convention — one row per key with the config layer that supplied it — and the
babysit-prs `userConfig` surface. `apply` interviews the repo and writes the
convention config — inferring first from the repo's own `CLAUDE.md`/rules,
commit-msg hook, or git log history before asking, and offering Conventional
Commits (11-type vocabulary) as the recommended default or a custom pattern
(e.g. a ticket-prefix regex) for orgs that don't use Conventional Commits.
Supply `subject_pattern=` to write it non-interactively, and
`layer=user|team|local` to pick which layer receives it (default: the tracked
team file). Re-runnable to reconfigure.

### `/source-control:resolve-conflicts`

Resolves in-progress merge/rebase/cherry-pick conflicts intent-first: reads
the history behind BOTH sides of every hunk before editing (log/blame,
commit messages, PR/issue context via `gh` when available), composes both
changes by default, and drops a side only with evidence — never mechanical
`--ours`/`--theirs` picking. After the markers are gone it sweeps for
semantic conflicts the merge machinery can't flag (renamed symbol vs new
call site) and runs the project's build/test gates before concluding via
`--continue`. `--abort` is never a resolution strategy — only an explicit
user decision to abandon the integration.

## Hooks

### `pr-body-linkage-gate`

A `PreToolUse` hook on the Bash tool. When a `gh pr create` / `gh pr edit`
carries a PR body the hook can read statically, it validates that body against
the same contract the repository's required `pr-issue-linkage` check enforces —
a closing keyword (or an explicit no-linked-issue marker) plus a non-empty
`## Related` section — and blocks the call with the missing half named, so the
failure surfaces before the PR exists rather than a CI round trip later.
`/source-control:pull-request create` already gates its own body; this covers
the calls that bypass the skill.

Enforcement is keyed to the consuming repository's own policy: it runs only
where `.github/workflows/pr-issue-linkage.yml` exists, and a body the hook
cannot read statically (an unexpanded variable, an absent body flag, a
`--repo`-targeted invocation) always passes. Set
`pr_body_linkage_gate_enabled` to `false` to turn it off.

#### Telemetry (opt-in)

The hook emits one structured
[hook-telemetry](../../docs/conventions/hook-telemetry/README.md) envelope per
run to whatever `HOOK_TELEMETRY_SINK` names — carrying `status` (`blocked` on a
block, `ok` otherwise), `duration_ms`, and a `data` payload of labels only: the
outcome and which body form was read (`body-literal`, `body-file`,
`stdin-heredoc`, `body-substitution`). Never the PR body, the command, or a
path. Unset `HOOK_TELEMETRY_SINK` → no-op.

## Works in any repo

- **Self-contained.** Everything runs on `git`, `gh` (authenticated), `jq`,
  and Bash scripts bundled under `${CLAUDE_PLUGIN_ROOT}` (Git Bash on native
  Windows); `unzip` is additionally required by the CI-log fetch path
  (`fetch-failed-logs`), which exits with a remediation message when it is
  absent. Transient CI-log scratch goes to `${CLAUDE_PLUGIN_DATA}` (or
  `mktemp`).
- **Graceful degrade.** Adjacent capabilities — review agents, a simplifier,
  a verify skill, a research skill, a work-item tracker, a CI-log-audit
  agent, a GitHub-events push channel — are used when your environment
  provides them and replaced by inline guidance when absent. No phase blocks
  on a missing tool.
- **Reads your conventions, assumes none.** Commit-subject / PR-title
  convention resolves from the `source-control.md` config (written by
  `/source-control:setup`) first — a `~/.claude` user-global file, the tracked
  team file, and a gitignored `.claude/source-control.local.md` personal
  overlay, merged per key — then the consuming project's own
  `CLAUDE.md`, rules, and hooks; branch naming, PR template, merge style, and
  bot-identity wrappers also come from the project's own `CLAUDE.md` and
  rules. Defaults (Conventional Commits, squash merge) apply only when the
  project declares nothing.

## Install

```shell
/plugin marketplace add melodic-software/claude-code-plugins
/plugin install source-control@melodic-software
```

## Configuration

`/source-control:babysit-prs` is configured through the plugin's native
`userConfig` surface — the `/plugin` dialog, or
`claude plugin install --config KEY=VALUE` for headless installs; run
`/source-control:setup` for guided check/apply. Every key is optional:
zero-config behavior is the safe tier over your own PRs under the current
repo's owner.

| Key | Type | Default / absent behavior |
|---|---|---|
| `pr_body_linkage_gate_enabled` | boolean | `true` (the PR-body hook above; inert in a repo with no `pr-issue-linkage` workflow) |
| `babysit_watched_owners` | string (multiple) | infer the current repo's owner |
| `babysit_self_logins` | string (multiple) | your `gh api user` login (extras add to it) |
| `babysit_default_tier` | string | `safe` (explicit invocations only) |
| `babysit_merge_method` | string | repo convention, then squash |
| `babysit_review_trigger_phrase` | string | review-trigger module dormant |
| `babysit_review_bot_logins` | string (multiple) | review-trigger module dormant; merge gate's review-settle hold dormant |
| `babysit_review_gate_context` | string | review gate treated as absent |
| `babysit_review_settle_minutes` | string | review-settle hold dormant (pair it with `babysit_review_bot_logins`) |
| `babysit_ci_gateway_context` | string | gateway check unused |
| `babysit_extra_bot_logins` | string (multiple) | structural bot detection only |
| `babysit_extra_dependency_manager_logins` | string (multiple) | built-in dependabot/renovate dependency-manager set only |
| `babysit_approval_downgrade_logins` | string (multiple) | an approval carrying blocking-looking prose is downgraded to ignored structurally (every bot); a named login instead surfaces its own as material. Real APPROVED-state reviews and plain clean approvals are ignored regardless. |
| `babysit_skip_downgrade_logins` | string (multiple) | downgrade heuristic dormant |
| `babysit_max_quiet_recheck_seconds` | number | 14400 |
| `babysit_stuck_check_age_seconds` | number | 1800 (min age before a pending non-required check under UNSTABLE reports stuck) |
| `babysit_advisory_fix_round_cap` | number | 100 |
| `babysit_worker_concurrency_cap` | number | 10 |
| `babysit_worktree_root` | directory | `worktrees/` under the plugin data dir |
| `worktree_stale_days` | number | 14 (staleness threshold for `/worktree status`) |
| `fetch_logs_max_bytes` | number | 52428800 (CI-log ZIP size cap for `fetch-logs`) |
| `branch_issue_pattern` | string | built-in `<type>/<N>-<slug>` (and `routine-issue-<N>`) branch-to-issue grammar; set an ERE (last capture group = the numeric GitHub issue number) for a scheme that places the number differently, e.g. `^[^/]+/([0-9]+)-` (`alice/1234-slug`) or `-([0-9]+)$` (`feat/add-widget-1234`) |
| `setup_inference_window` | string | `1 year` (`git log --since` window for `/setup`'s commit-history convention inference; any git-approxidate) |
| `setup_inference_recency_days` | number | 90 (recent-vs-older split boundary in the inference report) |
| `setup_inference_min_commits` | number | 50 (below this many classifiable subjects, inference widens to full history and reports low confidence) |

The commit-subject / PR-title convention is separate: run
**`/source-control:setup`** to interview your repo and write the
`source-control.md` config — idempotent and safe to re-run. Add
`.claude/*.local.*` to your `.gitignore` so the personal overlay layer stays
out of version control (no skill here edits your `.gitignore`).
Remaining optional environment variables:

| Variable | Used by | Effect |
|---|---|---|
| `FETCH_LOGS_SCRATCH` / `FETCH_LOGS_REPO` | `fetch-logs` | Scratch dir and repo override |

The plugin-scope finding-classification gate accepts extra posting identities via its
`--extra-self` flag (fed from `babysit_self_logins`), added to your
`gh api user` login; its `--self` flag still provides a full override.

## Security

- One local hook (`pr-body-linkage-gate`, above), no MCP servers, no telemetry
  unless you opt in (see below), no outbound network beyond `git` and `gh`
  against the repository the session already targets. The hook reads only the
  Bash command it is gating, the body file that command names, and the
  repository's own workflow directory; it never runs `git`, `gh`, or any
  network call.
- Writes to GitHub (comments, reactions, thread resolution, PR creation,
  merge) happen only inside the documented `/pull-request` phases and the
  `/babysit-prs` loop. `/babysit-prs` merges only in its explicit
  `worker`/`autopilot` opt-in tiers, and only through a deterministic merge
  gate (expected-head pin, fail-closed owner allowlist, dependency-PR and
  unprotected-repo refusals) — the safe default never resolves threads or
  merges, and configuration alone can never grant an auto-routed invocation
  merge authority.
- Bundled scripts are read-only against the GitHub API except where the
  skill body documents a write.
