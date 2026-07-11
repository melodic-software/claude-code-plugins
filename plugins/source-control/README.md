# source-control

A Claude Code plugin bundling the git/GitHub delivery workflow as three
composable skills — commit mechanics, the full PR lifecycle, and worktree
lifecycle management.

## Skills

### `/source-control:commit`

Builds a commit the safe way: drafts a **Conventional Commits** subject
(11-type vocabulary, consumer convention wins), pre-checks it against the
pattern before git runs, appends a `Co-Authored-By: Claude …` trailer, and
feeds the message via Bash heredoc (`git commit -F - --cleanup=verbatim`) —
never PowerShell here-strings, never scratch files in `.git/`. Stages
surgically (`git add <path>`, never `-A`), and supports pathspec-limited
commits when the index is shared with a concurrent session.

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
- **babysit** — self-pacing all-PR loop (designed for
  `/loop /pull-request babysit`): discovers every open PR, checks each out,
  processes every finding individually with GitHub-verified evidence, and is
  mechanically gated by the bundled `babysit-readiness-gate.sh` (classification
  rows must cover source findings before readiness can be declared). Never
  merges.
- **fetch-logs** — tiered CI-log retrieval (annotations → full untruncated
  ZIP via the REST API → per-job text).

### `/source-control:worktree`

Git worktree lifecycle for parallel-session isolation: `create` (guided
naming, EnterWorktree, post-create setup checks), `status` (porcelain parse,
batched PR cross-reference, staleness classification), `cleanup`
(file-lock-aware removal that never counts a Windows husk as deleted, emits
destructive branch deletion for the user), `audit` (configuration health).

## Works in any repo

- **Self-contained.** Everything runs on `git`, `gh`, and scripts bundled
  under `${CLAUDE_PLUGIN_ROOT}`; transient CI-log scratch goes to
  `${CLAUDE_PLUGIN_DATA}` (or `mktemp`).
- **Graceful degrade.** Adjacent capabilities — review agents, a simplifier,
  a verify skill, a research skill, a work-item tracker, a CI-log-audit
  agent, a GitHub-events push channel — are used when your environment
  provides them and replaced by inline guidance when absent. No phase blocks
  on a missing tool.
- **Reads your conventions, assumes none.** Commit-message convention, branch
  naming, PR template, merge style, and bot-identity wrappers come from the
  consuming project's own `CLAUDE.md`, rules, and hooks. Defaults (
  Conventional Commits, squash merge) apply only when the project declares
  nothing.

## Install

```shell
/plugin marketplace add melodic-software/claude-code-plugins
/plugin install source-control@melodic-software
```

## Configuration

No `userConfig`. Optional environment variables:

| Variable | Used by | Effect |
|---|---|---|
| `WORKTREE_STALE_DAYS` | `/worktree status` | Staleness threshold (default 14 days) |
| `BABYSIT_SELF_LOGINS` | babysit readiness gate | Extra posting identities (csv) whose replies count as your classification rows — e.g. a project bot account (default: your `gh api user` login) |
| `FETCH_LOGS_SCRATCH` / `FETCH_LOGS_REPO` / `FETCH_LOGS_MAX_BYTES` | `fetch-logs` | Scratch dir, repo override, size cap for CI-log ZIPs |

## Security

- No hooks, no MCP servers, no telemetry, no outbound network beyond `git`
  and `gh` against the repository the session already targets.
- Writes to GitHub (comments, reactions, thread resolution, PR creation,
  merge) happen only inside the documented `/pull-request` phases, with the
  merge decision always behind a human gate.
- Bundled scripts are read-only against the GitHub API except where the
  skill body documents a write.
