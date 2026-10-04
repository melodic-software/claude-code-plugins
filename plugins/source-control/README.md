# source-control

A Claude Code plugin bundling the git/GitHub delivery workflow as six
composable skills. Commit mechanics, the single-PR lifecycle, the tiered
babysit fleet loop, worktree lifecycle management, convention setup, and
merge-conflict resolution.

## Contents

- [Skills](#skills)
  - [`/source-control:commit`](#source-controlcommit)
  - [`/source-control:pull-request`](#source-controlpull-request)
  - [`/source-control:babysit-prs`](#source-controlbabysit-prs)
  - [`/source-control:worktree`](#source-controlworktree)
  - [`/source-control:setup`](#source-controlsetup)
  - [`/source-control:resolve-conflicts`](#source-controlresolve-conflicts)
- [Hooks](#hooks)
  - [`pr-body-linkage-gate`](#pr-body-linkage-gate)
  - [`pr-linkage-mcp-gate`](#pr-linkage-mcp-gate)
  - [`worktree-add-claim-gate`](#worktree-add-claim-gate)
- [Works in any repo](#works-in-any-repo)
- [Install](#install)
- [Configuration](#configuration)
  - [Options reference](#options-reference)
  - [How to set these](#how-to-set-these)
  - [Upstream documentation](#upstream-documentation)
- [Security](#security)

## Skills

### `/source-control:commit`

Builds a commit the safe way: drafts a subject matching the resolved
convention, the layered `source-control.md` config (written by
`/source-control:setup`) → the consuming project's own
`CLAUDE.md`/rules/commit-msg hook → Conventional Commits (11-type vocabulary)
as the default. Pre-checks it against the
pattern before git runs, appends a `Co-authored-by: Claude …` trailer, and
feeds the message via Bash heredoc (`git commit -F - --cleanup=verbatim`),
never PowerShell here-strings, never scratch files in `.git/`. Stages
surgically (`git add <path>`, never `-A`), and supports pathspec-limited
commits when the index is shared with a concurrent session. Right after
staging, it fixes the exec bit on newly-added shebang files and runs the
consuming repo's own formatter/linter (when one is discoverable) against the
staged files. Catching what CI's exec-bit and lint lanes would otherwise
catch after the push round-trip.

### `/source-control:pull-request`

Orchestrates the PR lifecycle with two non-negotiable gates, every review
finding is verified before it is presented, and every CI fix is
research-gated:

- **prep**. Review the branch diff (via your review agents/skills when
  installed, inline otherwise), verify findings, simplify, then run the
  project's build+test+lint gate as a hard block.
- **create**. Branch-name check, default-branch rebase, unrelated-changes
  triage, `Closes #N` derivation from the branch name (validated against the
  live issue), safely-assembled PR body, `gh pr create`.
- **monitor**. Async event loop over CI checks + review comments. Event
  delivery prefers a push channel when your environment ships one, falls back
  to a session-persistent Monitor watch (30s `gh` poll), or plain `gh`
  polling in cloud sessions. CI failures are read from complete logs via the
  bundled annotation/ZIP fetch scripts (`gh run view --log-failed`
  truncates); every reviewer comment gets explore → research → classify →
  react → reply → fix → verify-on-GitHub treatment.
- **merge**. 6-Gate readiness re-verification, squash merge, worktree
  reuse/cleanup, post-merge CI health check. Never auto-merges.
- **fetch-logs**. Tiered CI-log retrieval (annotations → full untruncated
  ZIP via the REST API → per-job text).

### `/source-control:babysit-prs`

Tiered, self-pacing fleet loop over your own open PRs (designed for
`/loop /source-control:babysit-prs`):

- **safe (default)**. Discovers YOUR open PRs under the current repo's
  owner (or the configured watched owners), checks each out, keeps the
  branch fresh, processes every review finding individually with
  GitHub-verified evidence per the plugin-scope shared review discipline,
  finding classification mechanically gated by the bundled
  `babysit-readiness-gate.sh`. Never resolves threads, never merges, an
  engine-backed run reports merge-readiness from a read-only merge-gate
  run; the Python-free degrade has no merge gate and reports it unchecked.
- **worker** (explicit keyword). Everything safe does, plus auto-resolving
  pre-push-outdated bot threads and merging PRs a deterministic gate proves
  100% ready (`mergeStateStatus == CLEAN` plus explicit cross-checks, with
  an expected-head pin carried to GitHub's server-side match-head-commit
  guard). Requires Python 3 (stdlib only).
- **autopilot** (explicit keyword). Maximum autonomy for a solo owner:
  every author under the watched owners, resolves any thread it has
  addressed, merges through the same gate, escalates only what it genuinely
  cannot solve. Requires Python 3.

Cross-tier invariants: never an unprotected force-push, never `--admin`,
never GitHub settings or branch-protection changes, never a repository
outside the watched owners, and dependency-manager-authored PRs
(Dependabot/Renovate-class) are never merged autonomously in any tier. A
merge-capable tier engages only when the invocation names it, the
configured `default_tier` applies to explicitly typed invocations only,
never to auto-routed conversational matches. The two guarded mutations run
only through the plugin's pinned wrappers (`source-control-babysit-merge`,
`source-control-babysit-resolve-thread`), which fail closed without an
owner allowlist and reject unattended unpinned merges.

### `/source-control:worktree`

Git worktree lifecycle for parallel-session isolation: `create` (guided
naming, EnterWorktree, post-create setup checks), `status` (porcelain parse,
batched PR cross-reference, staleness classification, unclaimed-lock
report), `cleanup`
(file-lock-aware removal that never counts a Windows husk as deleted, emits
destructive branch deletion for the user), `audit` (configuration health,
including linked worktrees with no lock reason).

Supported interface: `scripts/worktree-create.sh --existing-branch <name>` checks out
an existing local branch into a new worktree instead of creating one, and cannot be
combined with `--base-ref`. Exit codes are listed in the script header. Known
consumer: `/repo-fleet-hygiene:sync`. A consumer outside this plugin must locate the
script through the installed plugin root, never a monorepo-relative path.

### `/source-control:setup`

`check` (read-only, default) reports the effective commit-subject / PR-title
convention, one row per key with the config layer that supplied it, and the
babysit-prs `userConfig` surface. `apply` interviews the repo and writes the
convention config. Inferring first from the repo's own `CLAUDE.md`/rules,
commit-msg hook, or git log history before asking, and offering Conventional
Commits (11-type vocabulary) as the recommended default or a custom pattern
(e.g. a ticket-prefix regex) for orgs that don't use Conventional Commits.
Supply `subject_pattern=` to write it non-interactively, and
`layer=user|team|local` to pick which layer receives it (default: the tracked
team file). Re-runnable to reconfigure.

### `/source-control:check`

Read-only and model-invocable. Reports whether `jq` resolves for the plugin's
hooks, with the install route from `prerequisites.json` when it does not. It
never installs.

### `/source-control:resolve-conflicts`

Resolves in-progress merge/rebase/cherry-pick conflicts intent-first: reads
the history behind BOTH sides of every hunk before editing (log/blame,
commit messages, PR/issue context via `gh` when available), composes both
changes by default, and drops a side only with evidence, never mechanical
`--ours`/`--theirs` picking. After the markers are gone it sweeps for
semantic conflicts the merge machinery can't flag (renamed symbol vs new
call site) and runs the project's build/test gates before concluding via
`--continue`. `--abort` is never a resolution strategy. Only an explicit
user decision to abandon the integration.

## Hooks

An installed mod can stop this plugin's `PreToolUse` hooks from running: they run after the last
mod calls `next`, so a mod that answers a `tool.call` without calling it skips them
([where settings hooks run in the order](https://code.claude.com/docs/en/plugins/mods/events#where-settings-hooks-run-in-the-order)).
A mod can also approve a call they blocked, because its `tool.check` hook runs after them
([approve or refuse a tool call before the user is asked](https://code.claude.com/docs/en/plugins/mods/events#approve-or-refuse-a-tool-call-before-the-user-is-asked)).

### `pr-body-linkage-gate`

A `PreToolUse` hook on the Bash tool. When a `gh pr create` / `gh pr edit`
carries a PR body the hook can read statically, it validates that body against
the same contract the repository's required PR-contract check enforces,
a closing keyword (or an explicit no-linked-issue marker) plus four non-empty
contract sections (`## Summary`, `## Fix`, `## Verification`, `## Related`),
and blocks the call with every missing or empty requirement named, so the
failure surfaces before the PR exists rather than a CI round trip later.
`/source-control:pull-request create` already gates its own body; this covers
the calls that bypass the skill.

Enforcement is keyed to the consuming repository's own policy: it runs only
where one of the repo's `.github/workflows/*.yml` / `*.yaml` files `uses:` the
`pr-contract` composite step (the SHA-pinned
`melodic-software/ci-workflows/.github/actions/pr-contract@<sha>` form, or
ci-workflows' own local `./.github/actions/pr-contract`). A body the hook
cannot read statically always passes: an unexpanded variable, an absent body
flag, a body flag with no value, an unreadable file, a `--repo`-targeted
invocation, or a call following a `cd`/`pushd` on the same command line, which
moves the directory the workflow scan and any relative `--body-file` resolved
against. Set `pr_body_linkage_gate_enabled` to `false` to turn it off.

The registration carries an `if` filter, `Bash(*gh *)`, the same shape as the
`Bash(*worktree*)` filter on the worktree gates, so the hook process is spawned only
for a command line that carries `gh` followed by a space somewhere in its text (Claude Code checks each
subcommand of a compound command, and runs the hook regardless when it cannot tell what
a command expands to). The leading wildcard is deliberate: the `if` field matches the
command name, so the narrower `Bash(gh *)` never launched the gate for a wrapped call
such as `env GH_TOKEN=x gh pr create`, `sudo gh pr create` or
`bash -c "cd x && gh pr create"`, whose first word is not `gh`. The wider filter is a
superset of the hook's own first check (a `gh` word anywhere on the line), so nothing
it would have judged is skipped; a plain `git status` still does not pay for it, and a
non-`gh` line that happens to contain `gh` followed by a space (`echo high tide`) pays one bash start
before the hook's own jq-free regex pre-filter dismisses it. What the filter still
cannot see is a `gh` that only appears after a `$()`, a backtick or a `$VAR` expands;
Claude Code spawns the hook regardless for such a command, so the gate still judges
it, and the dotfiles fan-out harness reports those spawns as `RAN(best-effort)` on its
`$()` sample.

#### Measured cost

Its share of the [hook budget](../../docs/conventions/hook-budget/README.md),
counted as kernel process creations rather than wall time: the host that
reported this hook timing out pays 0.3-0.9 s per spawn, so wall time there says
more about contention than about the hook. Counted with
`strace -f -e trace=clone,clone3,fork,vfork,execve`, telemetry sink off:

| Path | clone-family | `execve` |
| --- | --- | --- |
| A `gh` call with no `pr` in it | 7 | 2 |
| `gh pr create` with a readable body (allow or block) | 11 | 3 |
| `pr-linkage-mcp-gate`, an MCP create (allow or block) | 11 | 4 |

Two of each `execve` count belong to `lib/hook-utils.sh`, not to these hooks:
one `jq -e .` validating the payload and one `git rev-parse` resolving the repo
root. The gates themselves spend one batched `jq` over the whole payload, plus,
on the MCP surface only, the `git remote get-url` its origin-match scope guard
needs. `hooks/pr-linkage-spawn-budget.test.sh` holds these numbers as ceilings
with no headroom, and proves itself non-vacuous against three mutants.

#### Telemetry (opt-in)

The hook emits one structured
[hook-telemetry](../../docs/conventions/hook-telemetry/README.md) envelope per
run to whatever `HOOK_TELEMETRY_SINK` names. Carrying `status` (`blocked` on a
block, `ok` otherwise), `duration_ms`, and a `data` payload of labels only: the
outcome and which body form was read (`body-literal`, `body-file`,
`stdin-heredoc`, `body-substitution`). Never the PR body, the command, or a
path. Unset `HOOK_TELEMETRY_SINK` → no-op.

### `pr-linkage-mcp-gate`

The MCP-surface sibling of `pr-body-linkage-gate`: a `PreToolUse` hook on the
GitHub MCP server's `create_pull_request` / `update_pull_request` tools, which
is how cloud/remote sessions, where the `gh` CLI doesn't exist, open PRs. It
covers both the `mcp__github__<tool>` names and the
`mcp__plugin_<plugin>_github__<tool>` names of a plugin-bundled server.
Same contract, same authority (a workflow in the consuming repository's own
`.github/workflows/` that `uses:` the `pr-contract` composite step), same
block-with-the-fix-named behavior. The MCP payload hands over the body as a plain JSON field, so the
Bash sibling's static-readability caveats don't apply here; the scope guards
that remain are the workflow scan above, an origin-remote match on the call's
`owner`/`repo` (another repository's PR is not this repo's policy), and an
`update_pull_request` that carries no `body` field, which changes nothing CI
already validated and passes. A `create_pull_request` with no `body` at all
blocks. GitHub would open the PR with an empty body, which the CI check
rejects. Set `pr_linkage_mcp_gate_enabled` to `false` to turn it off.

Telemetry matches the sibling's: one envelope per run (`ok`/`blocked`,
`duration_ms`, and the tool name as its only data label), only when
`HOOK_TELEMETRY_SINK` is set.

### `worktree-add-claim-gate`

A `PostToolUse` hook on the Bash tool. After a raw `git worktree add` it
claims **the parsed add target** (same tokenizer / `git -C` / wrapper
chdir composition as the containment sibling) with a session-distinct
reason. It does not claim every unlocked tree. Two concurrent adds
must not assign both to whichever hook runs first. `echo git worktree
add` is not a git call. `worktree-create.sh` already locks the trees it
creates; this hook is the route for the adds that bypass the helper.
Existing reasons are never rewritten. The lock is a claim other agents
can read; it does not block concurrent writes (git-worktree(1)).

The worktree scripts (`worktree-claim.sh`, `landed-work.sh`, `worktree-facts.sh list`)
require git 2.36.0 or newer for `git worktree list --porcelain -z`; on older git they
fail closed with a message naming the floor and the installed version.

`scripts/worktree-claim.sh report` lists unclaimed linked worktrees;
`check-enter <path> --session-id <id>` surfaces a foreign live claim and
stops; `release <path> --session-id <id>` unlocks a claim this session armed
and refuses a foreign one; `stale <path>` is a read-only test (exit 0) that a
claim's session has no live transcript on this host, which `cleanup` combines
with a merged or landed branch before offering to remove a locked worktree. Set `worktree_add_claim_gate_enabled` to `false` to turn the hook
off; the script remains the documented gate.

This hook and its `PreToolUse` sibling `worktree-add-containment-gate` are registered
with the `if` filter `Bash(*worktree*)`: the hook process is spawned only for a command
whose text carries `worktree`, which is also each hook's own first check, so every
`git worktree add` spelling they judged before (including `git -C <dir> worktree add`
and wrapped forms) still reaches them, and every other Bash call no longer pays for
two hook processes. The same best-effort caveat applies: a command containing `$()`, a
backtick or `$VAR` spawns both processes whatever its text, since the filter cannot see
what the substitution expands to.

#### Measured cost

The two Bash-matcher worktree gates and the `WorktreeCreate` gate, counted as kernel
process creations rather than wall time: the host that reported these hooks timing out
pays 0.3-0.9 s per spawn, so wall time there describes contention more than it describes
the hook. Counted with `strace -f -e trace=clone,clone3,fork,vfork,execve`:

| Path | clone-family | `execve` |
| --- | --- | --- |
| Either Bash gate, a `worktree` command that is not an `add` | 7 | 2 |
| `worktree-add-containment-gate`, an `add` it allows | 18 | 5 |
| `worktree-add-containment-gate`, an `add` it blocks | 18-22 | 5-7 |
| `worktree-add-claim-gate`, a parsed `add` target | 22 | 6 |
| `worktree-create-gate`, before it reaches the placement helper | 13 | 4 |

Four of the seven creations on the not-an-`add` path belong to
[`lib/hook-utils.sh`](../../lib/hook-utils.sh), not to these gates: the
`hook::buffer_stdin` substitution and `hook::json_complete`'s `printf | jq -e .`. The
gates' own share of that path is one `printf '%s' "$INPUT" | jq` field read, 3 creations
and 1 `execve`. That feed is the form the library prescribes and is kept on purpose: a
here-string would cost 1 creation, but bash fills a here-string's pipe itself and
deadlocks at the pipe capacity on Git Bash (#1587), which on a hook is the timeout. The
block-path spread is the ancestor walk: a `.git`-directory target asks `git rev-parse` a
third time, and a block message that names a configured root reads the
`worktreeroot.path` key. `hooks/worktree-gates-spawn-budget.test.sh` holds these
numbers as ceilings, proves itself non-vacuous against seven mutants, one per change, and
fails when a gate feeds its payload to a reader by here-string.

## Works in any repo

- **Self-contained.** Everything else runs on `git`, `gh` (authenticated), `jq`,
  and Bash scripts bundled under `${CLAUDE_PLUGIN_ROOT}` (Git Bash on native
  Windows); `unzip` is additionally required by the CI-log fetch path
  (`fetch-failed-logs`), which exits with a remediation message when it is
  absent. Transient CI-log scratch goes to `${CLAUDE_PLUGIN_DATA}` (or
  `mktemp`).
- **Graceful degrade.** Adjacent capabilities (review agents, a simplifier,
  a verify skill, a research skill, a work-item tracker, a CI-log-audit
  agent, a GitHub-events push channel) are used when your environment
  provides them and replaced by inline guidance when absent. No phase blocks
  on a missing tool.
- **Reads your conventions, assumes none.** Commit-subject / PR-title
  convention resolves from the `source-control.md` config (written by
  `/source-control:setup`) first, a `~/.claude` user-global file, the tracked
  team file, and a gitignored `.claude/source-control.local.md` personal
  overlay, merged per key, then the consuming project's own
  `CLAUDE.md`, rules, and hooks; branch naming, PR template, merge style, and
  bot-identity wrappers also come from the project's own `CLAUDE.md` and
  rules. Defaults (Conventional Commits, squash merge) apply only when the
  project declares nothing.

## Requirements

- **Node.js** on `PATH`. Every hook row launches through `node hooks/exec-bash.mjs`, and Claude
  Code's native binary neither ships nor uses Node
  ([setup](https://code.claude.com/docs/en/setup), fetched 2026-09-29). Without `node` the hooks do
  not launch and the PR-linkage and worktree gates are not enforced. The setup `check` reports
  whether `node` resolves.

## Install

```shell
/plugin marketplace add melodic-software/claude-code-plugins
/plugin install source-control@<marketplace>
```

## Configuration

`/source-control:babysit-prs` is configured through the plugin's native
`userConfig` surface, the `/plugin` dialog, or
`claude plugin install --config KEY=VALUE` for headless installs; run
`/source-control:setup` for guided check/apply. Every key is optional:
zero-config behavior is the safe tier over your own PRs under the current
repo's owner.

| Key | Type | Default / absent behavior |
|---|---|---|
| `lane_instance` | string | sanitized lowercased hostname (writer identity suffixing `babysit-loop`'s telemetry marker; must be distinct across concurrent lane instances) |
| `pr_body_linkage_gate_enabled` | boolean | `true` (the PR-body hook above; inert in a repo with no workflow using the `pr-contract` step) |
| `pr_linkage_mcp_gate_enabled` | boolean | `true` (the MCP-surface sibling; inert in a repo with no workflow using the `pr-contract` step) |
| `babysit_watched_owners` | string (multiple) | infer the current repo's owner |
| `babysit_self_logins` | string (multiple) | your `gh api user` login (extras add to it) |
| `babysit_default_tier` | string | `safe` (explicit invocations only) |
| `babysit_merge_method` | string (picker) | `auto`: repo convention, then squash |
| `babysit_stacked_prs` | boolean | `false`: a stacked PR layer is held for a human |
| `babysit_review_trigger_phrase` | string | review-trigger module dormant |
| `babysit_review_bot_logins` | string (multiple) | review-trigger module dormant; merge gate's review-settle hold dormant |
| `babysit_review_gate_context` | string | review gate treated as absent |
| `babysit_review_settle_minutes` | number | review-settle hold dormant (pair it with `babysit_review_bot_logins`) |
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
| `promotion_evidence_binding` | file | no promotion-evidence bootstrap; every promotable cell stays effective-unpromoted (absolute path to the security binding document, outside the target repository, read-only to the lane; contract: [promotion-evidence-bootstrap.md](skills/babysit-loop/reference/promotion-evidence-bootstrap.md)) |
| `promotion_evidence_root` | directory | no probe evidence root; every promotable cell stays effective-unpromoted (absolute path to the protected `--probe-evidence-root` directory, outside the target repository, read-only to the lane) |
| `promotion_evidence_source` | file | no evidence source; every promotable cell stays effective-unpromoted (absolute path to the operator-published epoch-scoped events file, outside the target repository, read-only to the lane) |
| `promotion_evidence_checker` | file | no checker; every promotable cell stays effective-unpromoted (absolute path to the autonomy plugin's `check-security-binding.mjs` from an install the operator trusts, outside the target repository, read-only to the lane) |
| `worktree_root` | directory | `worktrees/` under the plugin data dir (external root for `/source-control:worktree create`; never inside a repository or a repository-discovery root) |
| `worktree_stale_days` | number | 14 (staleness threshold for `/source-control:worktree status`) |
| `worktree_reap_after_hours` | number | 48 (last-commit age past which `/source-control:worktree cleanup` proposes a safe worktree by default) |
| `fetch_logs_max_bytes` | number | 52428800 (CI-log ZIP size cap for `fetch-logs`) |
| `branch_issue_pattern` | string | deprecated fallback: set the `branch_issue_pattern` key on the layered `.claude/source-control.md` surface instead, which wins when present. Absent in both: the built-in `<type>/<N>-<slug>` (and `routine-issue-<N>`) branch-to-issue grammar; set an ERE (last capture group = the numeric GitHub issue number) for a scheme that places the number differently, e.g. `^[^/]+/([0-9]+)-` (`alice/1234-slug`) or `-([0-9]+)$` (`feat/add-widget-1234`) |
| `setup_inference_window` | string | `1 year` (`git log --since` window for `/source-control:setup`'s commit-history convention inference; any git-approxidate) |
| `setup_inference_recency_days` | number | 90 (recent-vs-older split boundary in the inference report) |
| `setup_inference_min_commits` | number | 50 (below this many classifiable subjects, inference widens to full history and reports low confidence) |

The commit-subject / PR-title convention is separate: run
**`/source-control:setup`** to interview your repo and write the
`source-control.md` config. Idempotent and safe to re-run. `apply layer=team`
appends the recursive `.claude/**/*.local.*` line to your `.gitignore` when it is missing, so the
personal overlay layer stays out of version control; `layer=local` never edits `.gitignore` and
fails with a recommendation when the overlay is exposed.
Remaining optional environment variables:

| Variable | Used by | Effect |
|---|---|---|
| `FETCH_LOGS_SCRATCH` / `FETCH_LOGS_REPO` | `fetch-logs` | Scratch dir and repo override |

The plugin-scope finding-classification gate accepts extra posting identities via its
`--extra-self` flag (fed from `babysit_self_logins`), added to your
`gh api user` login; its `--self` flag still provides a full override.

### Option details

**`pr_body_linkage_gate_enabled`.** The required sections are `## Summary`, `## Fix`,
`## Verification`, and `## Related`. Enforced only in a repository whose `.github/workflows` carry
a workflow that uses the `pr-contract` composite step.

**`pr_linkage_mcp_gate_enabled`.** The MCP-surface sibling of `pr-body-linkage-gate`, covering
cloud and remote sessions that open PRs without the `gh` CLI. It checks the same closing keyword
and non-empty sections, with the same policy scope: enforced only in a repository whose
`.github/workflows` carry a workflow that uses the `pr-contract` composite step.

**`branch_issue_pattern`.** The last capture group must resolve to digits (`Closes #N` honors only
a numeric issue). Set it for a non-default branch scheme that places the number differently, for
example `^[^/]+/([0-9]+)-` for `alice/1234-slug` or `-([0-9]+)$` for `feat/add-widget-1234`.

**`worktree_root`.** When absent, the skill supplies the plugin data dir default explicitly rather
than reading it from the environment (it is not per-plugin in a Bash-tool subprocess). The root is
deliberately outside the repository tree and outside repository-discovery roots such as a ghq root,
which a checkout-relative default would land inside. The in-repo `.claude/worktrees/` default is
never used because the nesting invariant forbids its nested placement; that claim is stated,
measured, dated and given an expiry in exactly one place: `skills/worktree/SKILL.md` "The nesting
invariant, dated measurement".

**`worktree_add_containment_gate_enabled`.** The message names the external root resolved from the
`worktreeroot.path` git config key, then the `worktree_root` plugin option, then the plugin data
dir. The hook blocks only the nesting class: a conforming target passes with no advisory, and a
target it cannot resolve statically (dynamic path, prior `cd`, unreadable payload) always passes.
The nesting invariant's measurement, disputed arms and expiry live in `skills/worktree/SKILL.md`
"The nesting invariant, dated measurement".

**`worktree_add_claim_gate_enabled`.** Only the parsed add target is claimed, not every currently
unlocked linked worktree. Existing lock reasons, including the `worktree-create.sh` helper string,
are never rewritten. The lock is a claim other agents can read, not a write mutex. With the hook
off, `scripts/worktree-claim.sh report` still lists unclaimed plain-add trees and `check-enter`
still surfaces a foreign live claim. The key is an on/off switch only.

**`worktree_create_gate_enabled`.** A WorktreeCreate hook has no "not applicable" channel: measured
on Claude Code 2.1.228, a non-zero exit and an exit 0 without a path both fail the creation. That
is why `false` makes the gate refuse out loud, and every harness-driven creation path
(`claude --worktree`, a subagent with `isolation: "worktree"`, a background session) fails with a
message naming the real stand-downs. To let Claude Code place worktrees itself, set
`worktree.bgIsolation` to `"none"` in settings, or disable this plugin. Probe, verbatim harness
output and the as-of stamp: `skills/worktree/fixtures/README.md`.

**`babysit_self_logins`.** The self set drives self-comment suppression, same-login
classification, readiness-gate classification rows, the merge-gate self-exemption, and the
resolve-thread bot-only test (a self-authored reply to a bot thread no longer counts as a
disqualifying human participant). Which authors' PRs the queue discovers is `--author`'s job,
independent of this set.

**`babysit_intended_write_identity`.** Example drift: a bot-token mint failed and the write silently
fell back to your personal login; the cycle status surfaces an attribution-drift material finding
instead of proceeding silently. A value that is not actually a posting identity would flag every
write.

**`babysit_default_tier`.** Valid values are `safe`, `worker`, and `autopilot`.

**`babysit_autopilot_merge_tier`.** The autopilot merge tier (#476) needs a genuine approving
review from a distinct bot account. The gate merges only when every criterion holds: issue-linked,
lane-authored, no `do-not-merge` label, distinct-bot approval on the live head, and no human
blocking comment. It ships off as a deliberate operator opt-in.

**`babysit_review_settle_minutes`.** Once the window elapses the gate stops waiting. The value is a
number of minutes, fractions allowed, and must convert to at least one second.

**`babysit_approval_downgrade_logins`.** The one case the structural approval-downgrade reaches is
a review body carrying blocking-looking prose that still parses as an approval verdict (no
CRITICAL/IMPORTANT or required-fix marker). Naming a login opts its own such approvals into the
more conservative `material` bucket. A review already in the APPROVED state, or a plain clean
approval with no blocking-looking prose, is ignored regardless.

**`lane_instance`.** Follows the loop-lane convention's lane-instance identity rule. The marker is
`source-control:babysit-loop@<id>`, so each concurrently running lane instance owns its own comment
and none can overwrite another's durable state. The value must be stable across restarts and
distinct across concurrent instances; two lanes on one machine each need an explicit value. Set an
opaque id if a machine name should not be published in a public tracker.

**`promotion_evidence_binding`, `promotion_evidence_root`, `promotion_evidence_source`,
`promotion_evidence_checker`.** Each is honored from user, `--settings`, or managed plugin settings
only, never from `.claude/source-control.md` or any repository file. Contract:
[promotion-evidence-bootstrap.md](skills/babysit-loop/reference/promotion-evidence-bootstrap.md).
The binding is the binding argument of the autonomy plugin's `check-security-binding.mjs`. The
probe root is the protected evidence surface the seam resolves isolation probe transcripts against.
The checker is the autonomy plugin's `skills/setup/scripts/check-security-binding.mjs`; it decides
whether a cell is promoted, which is why it must sit outside the target repository and every lane
worktree.

**`setup_inference_min_commits`.** Still below the threshold after widening, the inference is
reported low-confidence rather than authoritative.

<!-- BEGIN GENERATED: plugin options. Edit plugin.json, then run scripts/sync-plugin-options-docs.py -->

### Options reference

Generated from this plugin's `.claude-plugin/plugin.json`. Every option Claude Code
will prompt for when the plugin is enabled, with the environment variable each hook
reads it from.

| Option | Type | Default | Environment variable | Description |
| --- | --- | --- | --- | --- |
| `pr_body_linkage_gate_enabled` | boolean | `true` | `CLAUDE_PLUGIN_OPTION_PR_BODY_LINKAGE_GATE_ENABLED` | Blocks a gh pr create or gh pr edit whose statically readable PR body would fail the repository's required PR-contract check: no closing keyword, or a missing or empty Summary, Fix, Verification, or Related section. On by default. A body the hook cannot read statically always passes. |
| `pr_linkage_mcp_gate_enabled` | boolean | `true` | `CLAUDE_PLUGIN_OPTION_PR_LINKAGE_MCP_GATE_ENABLED` | Blocks a GitHub MCP create_pull_request or update_pull_request whose PR body would fail the repository's required PR-contract check, covering sessions that open PRs without the gh CLI. On by default. Enforced only for the repository the origin remote names. |
| `branch_issue_pattern` | string | *(none)* | `CLAUDE_PLUGIN_OPTION_BRANCH_ISSUE_PATTERN` | Deprecated fallback: set branch_issue_pattern in .claude/source-control.md instead, which wins. A POSIX ERE whose last capture group extracts the numeric GitHub issue number from the branch name. Absent: the built-in <type>/<N>-<slug> (and routine-issue-<N>) convention. |
| `pr_open_state` | string | `"draft"` | `CLAUDE_PLUGIN_OPTION_PR_OPEN_STATE` | State /source-control:pull-request create opens a PR in. draft (default) opens a draft that the ready action flips later; ready opens it for review at once. A repository's pr_open_state in docs/conventions/source-control.yaml wins over this value. |
| `fetch_logs_max_bytes` | number<br>*min 1* | `52428800` | `CLAUDE_PLUGIN_OPTION_FETCH_LOGS_MAX_BYTES` | Aborts a CI-log ZIP fetch larger than this many bytes. Default 52428800 (50 MiB). |
| `worktree_root` | directory | *(none)* | `CLAUDE_PLUGIN_OPTION_WORKTREE_ROOT` | External root under which /worktree create places worktrees, as <root>/<owner>-<repo>-<slug>, a path outside every repository (on Windows, the same drive as the repo). Absent: the worktrees/ subdirectory of the plugin data dir. Never the in-repo .claude/worktrees/ default. |
| `worktree_stale_days` | number<br>*min 1* | `14` | `CLAUDE_PLUGIN_OPTION_WORKTREE_STALE_DAYS` | Days since last commit before /worktree status classifies a worktree as stale. Default 14. |
| `worktree_reap_after_hours` | number<br>*min 1* | `48` | `CLAUDE_PLUGIN_OPTION_WORKTREE_REAP_AFTER_HOURS` | Hours since last commit before /worktree cleanup proposes an already-safe worktree for removal by default. Default 48. |
| `worktree_add_containment_gate_enabled` | boolean | `true` | `CLAUDE_PLUGIN_OPTION_WORKTREE_ADD_CONTAINMENT_GATE_ENABLED` | Blocks a raw Bash git worktree add whose resolved target lands inside a git repository (a working tree, or a .git or bare directory), naming the configured external root. On by default. A conforming target, or one the hook cannot resolve statically, passes silently. |
| `worktree_add_claim_gate_enabled` | boolean | `true` | `CLAUDE_PLUGIN_OPTION_WORKTREE_ADD_CLAIM_GATE_ENABLED` | After a raw Bash git worktree add, locks the parsed add target with a session-distinct claim (host, session id, timestamp) so concurrent adds cannot steal each other's trees. On by default. Off leaves plain-add trees unclaimed. |
| `worktree_create_gate_enabled` | boolean | `true` | `CLAUDE_PLUGIN_OPTION_WORKTREE_CREATE_GATE_ENABLED` | Redirects a WorktreeCreate away from Claude Code's default location, which may be inside the repository, to the configured worktree_root. On by default. Off does not hand placement back to Claude Code: the gate refuses and every harness-driven worktree creation fails. |
| `babysit_watched_owners` | string (multiple) | *(none)* | `CLAUDE_PLUGIN_OPTION_BABYSIT_WATCHED_OWNERS` | GitHub owners (users or orgs) babysit-prs may act under. Absent: the current repo's owner is inferred per run. |
| `babysit_self_logins` | string (multiple) | *(none)* | `CLAUDE_PLUGIN_OPTION_BABYSIT_SELF_LOGINS` | Extra GitHub posting identities (for example a project bot account) added to your gh api user login to form the self set babysit-prs treats as its own. Not a discovery filter. Absent: your gh login alone. |
| `babysit_intended_write_identity` | string | *(none)* | `CLAUDE_PLUGIN_OPTION_BABYSIT_INTENDED_WRITE_IDENTITY` | The single GitHub login babysit-prs's own writes should land under, typically the bot posting identity; a recorded write landing under a different self login surfaces an attribution-drift finding. Set it to one of your self logins. Absent: the check is dormant. |
| `babysit_default_tier` | string | `"safe"` | `CLAUDE_PLUGIN_OPTION_BABYSIT_DEFAULT_TIER` | Tier an explicit bare /source-control:babysit-prs invocation runs. safe (default) checks, fixes, and reports; worker adds resolving outdated bot threads and gate-proven merges; autopilot adds all authors under the watched owners. Never applies to auto-routed invocations. |
| `babysit_merge_method` | string | `"auto"` | `CLAUDE_PLUGIN_OPTION_BABYSIT_MERGE_METHOD` | Merge method for gate-proven merges. auto (default) uses the repository's declared method, then squash; squash, merge, or rebase forces that method when the repository declares none. |
| `babysit_stacked_prs` | boolean | `false` | `CLAUDE_PLUGIN_OPTION_BABYSIT_STACKED_PRS` | Lets the merge gate merge a native stacked PR layer, which lands every open layer below it. Each of those layers must pass the same gate. Off by default: a stack layer is held for a human. |
| `babysit_autopilot_merge_tier` | boolean | `false` | `CLAUDE_PLUGIN_OPTION_BABYSIT_AUTOPILOT_MERGE_TIER` | Turns on the autopilot merge tier: a distinct bot account submits an approving review, then the gate merges only when every criterion holds. Off by default; PRs go to the human merge-ready list. Requires babysit_lane_logins, babysit_approver_bot_logins, and babysit_merge_block_labels. |
| `babysit_lane_logins` | string (multiple) | *(none)* | `CLAUDE_PLUGIN_OPTION_BABYSIT_LANE_LOGINS` | Author logins recognized as pipeline lanes for the autopilot merge tier's lane-authored criterion. Absent: the tier (when on) refuses fail-closed. |
| `babysit_approver_bot_logins` | string (multiple) | *(none)* | `CLAUDE_PLUGIN_OPTION_BABYSIT_APPROVER_BOT_LOGINS` | Bot logins whose approving review satisfies the autopilot merge tier's author-is-not-approver criterion. Absent: the tier (when on) refuses fail-closed. |
| `babysit_merge_block_labels` | string (multiple) | *(none)* | `CLAUDE_PLUGIN_OPTION_BABYSIT_MERGE_BLOCK_LABELS` | Labels that veto an autopilot-merge-tier merge, for example do-not-merge. Absent and undeclared in the target repository: the tier (when on) refuses fail-closed. |
| `babysit_review_trigger_phrase` | string | *(none)* | `CLAUDE_PLUGIN_OPTION_BABYSIT_REVIEW_TRIGGER_PHRASE` | Comment phrase that requests an AI re-review (posted and recognized). Read only from this option: a target repository cannot supply it. Absent: the review-trigger module stays dormant. |
| `babysit_review_bot_logins` | string (multiple) | *(none)* | `CLAUDE_PLUGIN_OPTION_BABYSIT_REVIEW_BOT_LOGINS` | Logins of the AI review bots the trigger phrase addresses, and whose review of the live head the merge gate waits for. Absent: the review-trigger module and the merge gate's review-settle hold stay dormant. |
| `babysit_review_settle_minutes` | number | *(none)* | `CLAUDE_PLUGIN_OPTION_BABYSIT_REVIEW_SETTLE_MINUTES` | How long after a head appears a review bot's re-review may still be in flight; the merge gate holds an unreviewed head until the window elapses. Requires babysit_review_bot_logins. Absent: the hold stays dormant. Set it above the reviewer's observed latency. |
| `babysit_review_gate_context` | string | *(none)* | `CLAUDE_PLUGIN_OPTION_BABYSIT_REVIEW_GATE_CONTEXT` | Check or status context name of the AI-review gate. Absent: the gate is treated as absent (degrade). |
| `babysit_ci_gateway_context` | string | *(none)* | `CLAUDE_PLUGIN_OPTION_BABYSIT_CI_GATEWAY_CONTEXT` | Check or status context name of a CI gateway check. Absent: gateway classification unused. |
| `babysit_extra_bot_logins` | string (multiple) | *(none)* | `CLAUDE_PLUGIN_OPTION_BABYSIT_EXTRA_BOT_LOGINS` | Additional logins to treat as bots when structural detection cannot identify them. Absent: structural detection only. |
| `babysit_extra_dependency_manager_logins` | string (multiple) | *(none)* | `CLAUDE_PLUGIN_OPTION_BABYSIT_EXTRA_DEPENDENCY_MANAGER_LOGINS` | Dependency-manager bot logins beyond the built-in dependabot and renovate set whose PRs the merge gate holds unless --allow-dependency is passed, the same as the built-ins. Absent: the built-in set only. |
| `babysit_approval_downgrade_logins` | string (multiple) | *(none)* | `CLAUDE_PLUGIN_OPTION_BABYSIT_APPROVAL_DOWNGRADE_LOGINS` | AI reviewer logins whose approval carrying blocking-looking prose is surfaced as a material finding instead of ignored. Every bot's such approval is downgraded to non-blocking regardless. Absent: such approvals are ignored for every bot. |
| `babysit_skip_downgrade_logins` | string (multiple) | *(none)* | `CLAUDE_PLUGIN_OPTION_BABYSIT_SKIP_DOWNGRADE_LOGINS` | AI reviewer logins whose skip or no-op review is not treated as an approval. Absent: the downgrade heuristic stays dormant. |
| `babysit_max_quiet_recheck_seconds` | number | `14400` | `CLAUDE_PLUGIN_OPTION_BABYSIT_MAX_QUIET_RECHECK_SECONDS` | Longest a quiet PR may go without a worker recheck, in seconds. Default 14400. |
| `babysit_stuck_check_age_seconds` | number | `1800` | `CLAUDE_PLUGIN_OPTION_BABYSIT_STUCK_CHECK_AGE_SECONDS` | Minimum age before a pending non-required check under UNSTABLE is reported stuck (a stuck_queued or never_settling material finding). Default 1800. Orphaned status contexts with no backing run are detected structurally and ignore this threshold. |
| `babysit_advisory_fix_round_cap` | number | `100` | `CLAUDE_PLUGIN_OPTION_BABYSIT_ADVISORY_FIX_ROUND_CAP` | Per-PR cap on advisory-only fix rounds; never caps blocking defects. Default 100. |
| `babysit_worker_concurrency_cap` | number | `10` | `CLAUDE_PLUGIN_OPTION_BABYSIT_WORKER_CONCURRENCY_CAP` | Maximum per-PR workers dispatched concurrently in one cycle. Default 10. |
| `babysit_worktree_root` | directory | *(none)* | `CLAUDE_PLUGIN_OPTION_BABYSIT_WORKTREE_ROOT` | Root directory for babysit-managed ephemeral worktrees. Absent: the worktrees/ subdirectory of the plugin data dir. |
| `lane_instance` | string | *(none)* | `CLAUDE_PLUGIN_OPTION_LANE_INSTANCE` | Writer identity for this machine's babysit-loop telemetry, the suffix of its telemetry marker, so concurrent lane instances never overwrite each other. Absent: the sanitized lowercased hostname. Must match ^\[a-z0-9\]\[a-z0-9-\]{0,31}$. It appears verbatim in tracker comments. |
| `promotion_evidence_binding` | file | *(none)* | `CLAUDE_PLUGIN_OPTION_PROMOTION_EVIDENCE_BINDING` | Absolute path to the security binding document the babysit-loop promotion-evidence seam reads. It must sit outside the target repository and every lane worktree, readable but not writable by the lane. Absent: no bootstrap is configured and every promotable cell stays effective-unpromoted. |
| `promotion_evidence_root` | directory | *(none)* | `CLAUDE_PLUGIN_OPTION_PROMOTION_EVIDENCE_ROOT` | Absolute path to the directory passed as --probe-evidence-root, the protected surface isolation probe transcripts resolve against. Outside the target repository and every lane worktree, read-only to the lane. Absent: every promotable cell stays effective-unpromoted. |
| `promotion_evidence_source` | file | *(none)* | `CLAUDE_PLUGIN_OPTION_PROMOTION_EVIDENCE_SOURCE` | Absolute path to the epoch-scoped promotion-evidence events file passed as --evidence, published by an operator-side process. Outside the target repository and every lane worktree, read-only to the lane. Absent: every promotable cell stays effective-unpromoted. |
| `promotion_evidence_checker` | file | *(none)* | `CLAUDE_PLUGIN_OPTION_PROMOTION_EVIDENCE_CHECKER` | Absolute path to the check-security-binding.mjs the promotion-evidence seam runs, from an autonomy plugin install the operator trusts. Outside the target repository and every lane worktree, read-only to the lane. Absent: every promotable cell stays effective-unpromoted. |
| `setup_inference_window` | string | `"1 year"` | `CLAUDE_PLUGIN_OPTION_SETUP_INFERENCE_WINDOW` | git log --since window /source-control:setup samples for commit-subject convention inference; any git approxidate, for example 1 year or 6 months. Default 1 year. |
| `setup_inference_recency_days` | number<br>*min 1* | `90` | `CLAUDE_PLUGIN_OPTION_SETUP_INFERENCE_RECENCY_DAYS` | Boundary for the recency split in /source-control:setup's convention-inference report: subjects newer than this many days are the recent bucket, weighted as the live convention when its share diverges from the older bucket. Default 90. |
| `setup_inference_min_commits` | number<br>*min 1* | `50` | `CLAUDE_PLUGIN_OPTION_SETUP_INFERENCE_MIN_COMMITS` | Below this many classifiable subjects in the window, /source-control:setup widens inference to full history; still below it, the inference is reported low-confidence. Default 50. |

### How to set these

Three supported routes, in the order most people want them:

1. **Interactively.** Claude Code prompts for declared options when you enable the
   plugin. To change them later: `/plugin configure source-control@<marketplace>`.
2. **Headless.** Repeat `--config` for each option. Replace
   `<marketplace>` with the marketplace you installed this plugin from:

   ```shell
   claude plugin install source-control@<marketplace> -s <scope> --config pr_body_linkage_gate_enabled=<value>
   ```

   The same command reconfigures a plugin that is **already installed**: it prints
   `already installed` and still writes the value. The short-circuit message is
   about the install, not the config write. Do **not** `claude plugin uninstall` to
   reconfigure: uninstalling drops this plugin's whole stored `pluginConfigs` entry,
   resetting every option in the table above to its default. `-s` defaults to `user`,
   so pass the scope `claude plugin list` reports for this plugin. The verified-version
   record lives in the [plugin-reconfiguration convention](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/plugin-reconfiguration/README.md).

   The value is stored immediately; the session you are in does not change. Hooks are
   handed their `CLAUDE_PLUGIN_OPTION_*` when the session starts, so start a fresh
   Claude Code session before expecting new behavior. A check run in the old session
   still reports the old value, and that is not a failed write.

3. **By hand, in settings.** Add the value under `pluginConfigs` in your **user**
   settings (`~/.claude/settings.json`):

   ```json
   {
     "pluginConfigs": {
       "source-control@<marketplace>": {
         "options": {
           "pr_body_linkage_gate_enabled": <value>
         }
       }
     }
   }
   ```

   Plugin option values are read from **user**, `--settings`, and managed settings
   only, **not** from a project's `.claude/settings.json`. To vary behavior per
   repository, enable or disable the plugin in that project's `enabledPlugins`
   instead of setting an option there.

Do not set the `CLAUDE_PLUGIN_OPTION_*` variables yourself. They are how Claude Code
hands a configured value to a hook process; the value comes from the routes above.

### Upstream documentation

- [User configuration](https://code.claude.com/docs/en/plugins/manifest-reference#user-configuration): the `userConfig` schema and the `CLAUDE_PLUGIN_OPTION_<KEY>` export
- [Plugin install options](https://code.claude.com/docs/en/plugins/cli-reference#plugin-install): the `--config` flag's reference entry
- [Plugins and skills settings](https://code.claude.com/docs/en/settings-reference#plugins-and-skills): `enabledPlugins`, `extraKnownMarketplaces`, `pluginConfigs`
- [Settings files and who they affect](https://code.claude.com/docs/en/settings#settings-files-and-who-they-affect): user vs project vs local precedence
- [Manage installed plugins](https://code.claude.com/docs/en/discover-plugins#manage-installed-plugins): enabling, disabling, `/plugin list`

<!-- END GENERATED: plugin options -->

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
  unprotected-repo refusals), the safe default never resolves threads or
  merges, and configuration alone can never grant an auto-routed invocation
  merge authority.
- Bundled scripts are read-only against the GitHub API except where the
  skill body documents a write.
