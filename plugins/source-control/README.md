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
pattern before git runs, appends a `Co-authored-by: Claude …` trailer, and
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
cannot read statically always passes — an unexpanded variable, an absent body
flag, a body flag with no value, an unreadable file, a `--repo`-targeted
invocation, or a call following a `cd`/`pushd` on the same command line, which
moves the directory the gate file and any relative `--body-file` resolved
against. Set `pr_body_linkage_gate_enabled` to `false` to turn it off.

#### Telemetry (opt-in)

The hook emits one structured
[hook-telemetry](../../docs/conventions/hook-telemetry/README.md) envelope per
run to whatever `HOOK_TELEMETRY_SINK` names — carrying `status` (`blocked` on a
block, `ok` otherwise), `duration_ms`, and a `data` payload of labels only: the
outcome and which body form was read (`body-literal`, `body-file`,
`stdin-heredoc`, `body-substitution`). Never the PR body, the command, or a
path. Unset `HOOK_TELEMETRY_SINK` → no-op.

### `pr-linkage-mcp-gate`

The MCP-surface sibling of `pr-body-linkage-gate`: a `PreToolUse` hook on the
GitHub MCP server's `create_pull_request` / `update_pull_request` tools, which
is how cloud/remote sessions — where the `gh` CLI doesn't exist — open PRs.
Same contract, same authority (the consuming repository's own
`.github/workflows/pr-issue-linkage.yml`), same block-with-the-fix-named
behavior. The MCP payload hands over the body as a plain JSON field, so the
Bash sibling's static-readability caveats don't apply here; the scope guards
that remain are the gate-file check, an origin-remote match on the call's
`owner`/`repo` (another repository's PR is not this repo's policy), and an
`update_pull_request` that carries no `body` field, which changes nothing CI
already validated and passes. A `create_pull_request` with no `body` at all
blocks — GitHub would open the PR with an empty body, which the CI check
rejects. Set `pr_linkage_mcp_gate_enabled` to `false` to turn it off.

Telemetry matches the sibling's: one envelope per run (`ok`/`blocked`,
`duration_ms`, and the tool name as its only data label), only when
`HOOK_TELEMETRY_SINK` is set.

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
/plugin install source-control@<marketplace>
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
| `lane_instance` | string | sanitized lowercased hostname (writer identity suffixing `babysit-loop`'s telemetry marker; must be distinct across concurrent lane instances) |
| `pr_body_linkage_gate_enabled` | boolean | `true` (the PR-body hook above; inert in a repo with no `pr-issue-linkage` workflow) |
| `pr_linkage_mcp_gate_enabled` | boolean | `true` (the MCP-surface sibling; inert in a repo with no `pr-issue-linkage` workflow) |
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
| `worktree_root` | directory | `worktrees/` under the plugin data dir (external root for `/source-control:worktree create`; never inside a repository or a repository-discovery root) |
| `worktree_stale_days` | number | 14 (staleness threshold for `/source-control:worktree status`) |
| `fetch_logs_max_bytes` | number | 52428800 (CI-log ZIP size cap for `fetch-logs`) |
| `branch_issue_pattern` | string | built-in `<type>/<N>-<slug>` (and `routine-issue-<N>`) branch-to-issue grammar; set an ERE (last capture group = the numeric GitHub issue number) for a scheme that places the number differently, e.g. `^[^/]+/([0-9]+)-` (`alice/1234-slug`) or `-([0-9]+)$` (`feat/add-widget-1234`) |
| `setup_inference_window` | string | `1 year` (`git log --since` window for `/source-control:setup`'s commit-history convention inference; any git-approxidate) |
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
  merge) happen only inside the documented `/source-control:pull-request` phases and the
  `/source-control:babysit-prs` loop. `/source-control:babysit-prs` merges only in its explicit
  `worker`/`autopilot` opt-in tiers, and only through a deterministic merge
  gate (expected-head pin, fail-closed owner allowlist, dependency-PR and
  unprotected-repo refusals) — the safe default never resolves threads or
  merges, and configuration alone can never grant an auto-routed invocation
  merge authority.
- Bundled scripts are read-only against the GitHub API except where the
  skill body documents a write.

<!-- BEGIN GENERATED: plugin options — edit plugin.json, then run scripts/sync-plugin-options-docs.py -->

### Options reference

Generated from this plugin's `.claude-plugin/plugin.json`. Every option Claude Code
will prompt for when the plugin is enabled, with the environment variable each hook
reads it from.

| Option | Type | Default | Environment variable | Description |
| --- | --- | --- | --- | --- |
| `lane_instance` | string | *(none)* | `CLAUDE_PLUGIN_OPTION_LANE_INSTANCE` | Writer identity for this machine's loop-lane telemetry, per the loop-lane convention's lane-instance identity rule. It becomes the suffix of the babysit-loop telemetry sentinel marker (`source-control:babysit-loop@<id>`), so each concurrently running lane instance owns its own comment and none can overwrite another's durable state. Must match ^\[a-z0-9\]\[a-z0-9-\]{0,31}$, be stable across restarts, and be distinct across concurrent instances; two lanes on one machine each need an explicit value. Absent: the sanitized lowercased hostname. The value appears verbatim in tracker comments — set an opaque id if a machine name should not be published in a public tracker. |
| `pr_body_linkage_gate_enabled` | boolean | `true` | `CLAUDE_PLUGIN_OPTION_PR_BODY_LINKAGE_GATE_ENABLED` | Block a `gh pr create`/`gh pr edit` whose statically-readable PR body would fail the repository's required pr-issue-linkage check (missing a closing keyword, or a missing/empty `## Related` section). Enforced only in a repository that carries .github/workflows/pr-issue-linkage.yml; a body the hook cannot read statically always passes. |
| `pr_linkage_mcp_gate_enabled` | boolean | `true` | `CLAUDE_PLUGIN_OPTION_PR_LINKAGE_MCP_GATE_ENABLED` | Block a GitHub MCP create_pull_request/update_pull_request whose PR body would fail the repository's required pr-issue-linkage check — the MCP-surface sibling of pr-body-linkage-gate, covering cloud/remote sessions that open PRs without the gh CLI. Same policy scope: enforced only in a repository that carries .github/workflows/pr-issue-linkage.yml, and only for the repository the origin remote names. |
| `worktree_add_containment_gate_enabled` | boolean | `true` | `CLAUDE_PLUGIN_OPTION_WORKTREE_ADD_CONTAINMENT_GATE_ENABLED` | Block a raw Bash `git worktree add` whose resolved target lands inside a git repository — a working tree, or a .git / bare directory — with a message naming the configured external root (melodic.worktreeroot git config key, then the worktree_root plugin option, then the plugin data dir). Blocks ONLY the nesting class: a conforming target passes silently, with no advisory, and a target the hook cannot resolve statically (dynamic path, prior cd, unreadable payload) always passes. The nesting invariant's measurement, disputed arms and expiry live in exactly one place: `skills/worktree/SKILL.md` § "The nesting invariant, verified". |
| `worktree_create_gate_enabled` | boolean | `true` | `CLAUDE_PLUGIN_OPTION_WORKTREE_CREATE_GATE_ENABLED` | Redirect a WorktreeCreate away from Claude Code's default location, which may be inside the repository, to the configured worktree_root. Turning this OFF does NOT hand placement back to Claude Code: a WorktreeCreate hook has no 'not applicable' channel — measured on Claude Code 2.1.228, a non-zero exit and an exit-0-without-a-path both fail the creation — so `false` makes the gate refuse out loud, and every harness-driven creation path (`claude --worktree`, a subagent with `isolation: "worktree"`, a background session) fails with a message naming the real stand-downs. To let Claude Code place worktrees itself, set `worktree.bgIsolation` to `"none"` in settings, or disable this plugin. Probe, verbatim harness output and the as-of stamp: `skills/worktree/fixtures/README.md`. |
| `babysit_watched_owners` | string (multiple) | *(none)* | `CLAUDE_PLUGIN_OPTION_BABYSIT_WATCHED_OWNERS` | GitHub owners (users/orgs) babysit-prs may act under. Absent: the current repo's owner is inferred per run. |
| `babysit_self_logins` | string (multiple) | *(none)* | `CLAUDE_PLUGIN_OPTION_BABYSIT_SELF_LOGINS` | Extra GitHub posting identities (e.g. a project bot account) added to your `gh api user` login — the self set babysit-prs treats as its own: self-comment suppression, same-login classification, readiness-gate classification rows, the merge-gate self-exemption, and the resolve-thread bot-only test (a self-authored reply to a bot thread no longer counts as a disqualifying human participant). Not a discovery filter — which authors' PRs the queue discovers is `--author`'s job, independent of this set. Absent: your gh login alone. |
| `babysit_intended_write_identity` | string | *(none)* | `CLAUDE_PLUGIN_OPTION_BABYSIT_INTENDED_WRITE_IDENTITY` | The single GitHub login babysit-prs's own writes are intended to land under — typically the bot posting identity. When a write the orchestrator recorded performing lands under a different `babysit_self_logins` identity (e.g. a bot-token mint failed and the write silently fell back to your personal login), the cycle status surfaces an attribution-drift material finding instead of proceeding silently. Set it to one of your self logins; a value that is not actually a posting identity would flag every write. Absent: the check is dormant. |
| `babysit_default_tier` | string | `"safe"` | `CLAUDE_PLUGIN_OPTION_BABYSIT_DEFAULT_TIER` | Tier an explicit bare /source-control:babysit-prs invocation runs: safe, worker, or autopilot. Never applies to auto-routed invocations. |
| `babysit_merge_method` | string | *(none)* | `CLAUDE_PLUGIN_OPTION_BABYSIT_MERGE_METHOD` | Merge method for gate-proven merges: merge, squash, or rebase. Absent: repo convention, then squash. |
| `babysit_autopilot_merge_tier` | boolean | `false` | `CLAUDE_PLUGIN_OPTION_BABYSIT_AUTOPILOT_MERGE_TIER` | Enable the #476 autopilot merge tier: a distinct bot account submits a genuine approving review, then the gate merges only when every criterion holds (issue-linked, lane-authored, no do-not-merge label, distinct-bot approval on the live head, no human blocking comment). Ships DISABLED; a deliberate operator opt-in. Requires babysit_lane_logins, babysit_approver_bot_logins, and babysit_merge_block_labels to be set. Absent/false: the tier does not exist and PRs go to the human merge-ready list. |
| `babysit_lane_logins` | string (multiple) | *(none)* | `CLAUDE_PLUGIN_OPTION_BABYSIT_LANE_LOGINS` | Author logins recognized as pipeline lanes for the autopilot merge tier's lane-authored criterion. Absent: the tier (when enabled) refuses fail-closed. |
| `babysit_approver_bot_logins` | string (multiple) | *(none)* | `CLAUDE_PLUGIN_OPTION_BABYSIT_APPROVER_BOT_LOGINS` | Bot logins whose approving review satisfies the autopilot merge tier's author != approver criterion. Absent: the tier (when enabled) refuses fail-closed. |
| `babysit_merge_block_labels` | string (multiple) | *(none)* | `CLAUDE_PLUGIN_OPTION_BABYSIT_MERGE_BLOCK_LABELS` | Labels that veto an autopilot-merge-tier merge, e.g. do-not-merge. Absent: the tier (when enabled) refuses fail-closed. |
| `babysit_review_trigger_phrase` | string | *(none)* | `CLAUDE_PLUGIN_OPTION_BABYSIT_REVIEW_TRIGGER_PHRASE` | Comment phrase that requests an AI re-review (posted and recognized). Absent: the review-trigger module stays dormant. |
| `babysit_review_bot_logins` | string (multiple) | *(none)* | `CLAUDE_PLUGIN_OPTION_BABYSIT_REVIEW_BOT_LOGINS` | Logins of the AI review bots the trigger phrase addresses, and whose review of the live head the merge gate waits for. Absent: the review-trigger module stays dormant and the merge gate's review-settle hold stays dormant. |
| `babysit_review_settle_minutes` | string | *(none)* | `CLAUDE_PLUGIN_OPTION_BABYSIT_REVIEW_SETTLE_MINUTES` | How long after a head appears a review bot's re-review may still be in flight. The merge gate holds a head that bot has not reviewed yet until the window elapses, then stops waiting. Requires babysit_review_bot_logins; absent, the hold stays dormant. Set it above the reviewer's observed latency. |
| `babysit_review_gate_context` | string | *(none)* | `CLAUDE_PLUGIN_OPTION_BABYSIT_REVIEW_GATE_CONTEXT` | Check/status context name of the AI-review gate. Absent: gate treated as absent (degrade). |
| `babysit_ci_gateway_context` | string | *(none)* | `CLAUDE_PLUGIN_OPTION_BABYSIT_CI_GATEWAY_CONTEXT` | Check/status context name of a CI gateway check. Absent: gateway classification unused. |
| `babysit_extra_bot_logins` | string (multiple) | *(none)* | `CLAUDE_PLUGIN_OPTION_BABYSIT_EXTRA_BOT_LOGINS` | Additional logins to treat as bots when structural detection cannot identify them. Absent: structural detection only. |
| `babysit_extra_dependency_manager_logins` | string (multiple) | *(none)* | `CLAUDE_PLUGIN_OPTION_BABYSIT_EXTRA_DEPENDENCY_MANAGER_LOGINS` | Additional dependency-manager bot logins beyond the built-in dependabot/renovate set whose PRs the merge gate holds absent --allow-dependency, the same as the built-ins. Absent: built-in dependency-manager set only. |
| `babysit_approval_downgrade_logins` | string (multiple) | *(none)* | `CLAUDE_PLUGIN_OPTION_BABYSIT_APPROVAL_DOWNGRADE_LOGINS` | AI reviewer logins whose approval is surfaced as a `material` finding instead of `ignored` in the one case the structural approval-downgrade reaches: a review body carrying blocking-looking prose that still parses as an approval verdict (no CRITICAL/IMPORTANT or required-fix marker). Every bot's such approval is downgraded to non-blocking regardless; naming a login opts its own into the more-conservative `material` bucket rather than being ignored. Does not affect a review already in the APPROVED state or a plain clean approval with no blocking-looking prose — both are ignored regardless. Absent: such approvals are ignored for every bot. |
| `babysit_skip_downgrade_logins` | string (multiple) | *(none)* | `CLAUDE_PLUGIN_OPTION_BABYSIT_SKIP_DOWNGRADE_LOGINS` | AI reviewer logins whose skip/no-op review is not treated as an approval. Absent: the downgrade heuristic stays dormant. |
| `babysit_max_quiet_recheck_seconds` | number | `14400` | `CLAUDE_PLUGIN_OPTION_BABYSIT_MAX_QUIET_RECHECK_SECONDS` | Longest a quiet PR may go without a worker recheck. |
| `babysit_stuck_check_age_seconds` | number | `1800` | `CLAUDE_PLUGIN_OPTION_BABYSIT_STUCK_CHECK_AGE_SECONDS` | Minimum age before a pending non-required check under UNSTABLE is reported stuck (stuck_queued / never_settling material finding). Orphaned status contexts with no backing run are detected structurally and ignore this threshold. |
| `babysit_advisory_fix_round_cap` | number | `100` | `CLAUDE_PLUGIN_OPTION_BABYSIT_ADVISORY_FIX_ROUND_CAP` | Per-PR cap on advisory-only fix rounds (never caps blocking defects). |
| `babysit_worker_concurrency_cap` | number | `10` | `CLAUDE_PLUGIN_OPTION_BABYSIT_WORKER_CONCURRENCY_CAP` | Maximum per-PR workers dispatched concurrently in one cycle. |
| `babysit_worktree_root` | directory | *(none)* | `CLAUDE_PLUGIN_OPTION_BABYSIT_WORKTREE_ROOT` | Root directory for babysit-managed ephemeral worktrees. Absent: the worktrees/ subdirectory of the plugin data dir. |
| `worktree_root` | directory | *(none)* | `CLAUDE_PLUGIN_OPTION_WORKTREE_ROOT` | External root under which /worktree create places worktrees, as <root>/<owner>-<repo>-<slug> — a path OUTSIDE every repository (on Windows, the same drive as the repo). Absent: the worktrees/ subdirectory of the plugin data dir, which the skill supplies explicitly rather than reading from the environment (not per-plugin in a Bash-tool subprocess). Deliberately outside the repository tree AND outside repository-discovery roots such as a ghq root, which a checkout-relative default would land inside. Never the in-repo .claude/worktrees/ default, whose nested placement the nesting invariant forbids — that claim is stated, measured, dated and given an expiry in exactly one place: `skills/worktree/SKILL.md` § "The nesting invariant, verified". |
| `worktree_stale_days` | number<br>*min 1* | `14` | `CLAUDE_PLUGIN_OPTION_WORKTREE_STALE_DAYS` | Days since last commit before /worktree status classifies a worktree as stale |
| `fetch_logs_max_bytes` | number<br>*min 1* | `52428800` | `CLAUDE_PLUGIN_OPTION_FETCH_LOGS_MAX_BYTES` | Abort a CI-log ZIP fetch larger than this |
| `branch_issue_pattern` | string | *(none)* | `CLAUDE_PLUGIN_OPTION_BRANCH_ISSUE_PATTERN` | POSIX ERE for extracting the numeric GitHub issue number from the current branch name; the LAST capture group holds it and must resolve to digits (Closes #N honors only a numeric issue). Set this for a non-default branch scheme that places the number differently, e.g. '^\[^/\]+/(\[0-9\]+)-' for 'alice/1234-slug' or '-(\[0-9\]+)$' for 'feat/add-widget-1234'. Absent: the built-in '<type>/<N>-<slug>' (and routine-issue-<N>) convention. |
| `setup_inference_window` | string | `"1 year"` | `CLAUDE_PLUGIN_OPTION_SETUP_INFERENCE_WINDOW` | git log --since window /source-control:setup samples for commit-subject convention inference (any git-approxidate, e.g. '1 year', '6 months'). Absent: 1 year. |
| `setup_inference_recency_days` | number<br>*min 1* | `90` | `CLAUDE_PLUGIN_OPTION_SETUP_INFERENCE_RECENCY_DAYS` | Boundary for the recency split in /source-control:setup's convention-inference report — subjects newer than this many days are the 'recent' bucket, weighted as the live convention when its share diverges from the older bucket. Absent: 90. |
| `setup_inference_min_commits` | number<br>*min 1* | `50` | `CLAUDE_PLUGIN_OPTION_SETUP_INFERENCE_MIN_COMMITS` | Below this many classifiable subjects in the window, /source-control:setup widens inference to full history; still below it, the inference is reported low-confidence rather than authoritative. Absent: 50. |

### How to set these

Three supported routes, in the order most people want them:

1. **Interactively** — Claude Code prompts for declared options when you enable the
   plugin. To change them later: `/plugin configure source-control@<marketplace>`.
2. **Headless** — repeat `--config` for each option. Replace
   `<marketplace>` with the marketplace you installed this plugin from:

   ```shell
   claude plugin install source-control@<marketplace> -s <scope> --config lane_instance=<value>
   ```

   The same command reconfigures a plugin that is **already installed**: it prints
   `already installed` and still writes the value — verified on Claude Code 2.1.240,
   for a non-sensitive option at `user` scope, by writing a non-default value to an
   installed plugin and restoring it. The short-circuit message is about the install,
   not the config write. That has not been verified for a `sensitive` option or for
   `project`/`local` scope. Do **not** `claude plugin uninstall` in order to
   reconfigure: uninstalling drops this plugin's whole stored `pluginConfigs` entry,
   resetting every option in the table above to its default. `-s` defaults to `user`,
   so pass the scope `claude plugin list` reports for this plugin.

   The value is stored immediately; the session you are in does not change. Hooks are
   handed their `CLAUDE_PLUGIN_OPTION_*` when the session starts, so start a fresh
   Claude Code session before expecting new behavior — a check run in the old session
   still reports the old value, and that is not a failed write.

3. **By hand, in settings** — add the value under `pluginConfigs` in your **user**
   settings (`~/.claude/settings.json`):

   ```json
   {
     "pluginConfigs": {
       "source-control@<marketplace>": {
         "options": {
           "lane_instance": <value>
         }
       }
     }
   }
   ```

   Plugin option values are read from **user**, `--settings`, and managed settings
   only — **not** from a project's `.claude/settings.json`. To vary behavior per
   repository, enable or disable the plugin in that project's `enabledPlugins`
   instead of setting an option there.

Do not set the `CLAUDE_PLUGIN_OPTION_*` variables yourself. They are how Claude Code
hands a configured value to a hook process; the value comes from the routes above.

### Upstream documentation

- [User configuration](https://code.claude.com/docs/en/plugins-reference#user-configuration) — the `userConfig` schema and the `CLAUDE_PLUGIN_OPTION_<KEY>` export
- [Plugin install options](https://code.claude.com/docs/en/plugins-reference#plugin-install) — the `--config` flag's reference entry
- [Plugins and skills settings](https://code.claude.com/docs/en/settings-reference#plugins-and-skills) — `enabledPlugins`, `extraKnownMarketplaces`, `pluginConfigs`
- [Settings files and who they affect](https://code.claude.com/docs/en/settings#settings-files-and-who-they-affect) — user vs project vs local precedence
- [Manage installed plugins](https://code.claude.com/docs/en/discover-plugins#manage-installed-plugins) — enabling, disabling, `/plugin list`

<!-- END GENERATED: plugin options -->
