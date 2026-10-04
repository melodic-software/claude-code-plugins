# Load nothing head-controlled into a pipeline skill activity

- Status: accepted
- Date: 2026-10-04

## Context

A skill activity in the PR pipeline runs Claude Code through claude-code-action on a checkout of
the PR head ([`pr-run-activity.md`](../conventions/pr-pipeline/pr-run-activity.md)). Lanes read
their config and scripts from a base SHA so a PR cannot change the rules it is judged by. Five
facts showed that this alone does not keep the PR out of the activity. Line references into
claude-code-action are at the pinned commit `ed670b4`.

- **The base itself can be PR-chosen.** The first runner trusted the event's base SHA. A security
  review of the runner found that a PR into an unprotected branch, such as a stacked PR, then
  chose the actions, config and trusted-actor list it was judged by, and ran its own actions in the
  report job that holds `checks: write`.
- **Claude Code loads project settings from the checkout.** claude-code-action defaults
  `settingSources` to `user`, `project` and `local` unless `claude_args` passes
  `--setting-sources` (`base-action/src/parse-sdk-options.ts:338-344`). Project settings, hooks,
  `CLAUDE.md`, `AGENTS.md` and `.mcp.json` all come from the checkout. This repository's
  `.claude/settings.json` declares the `melodic-software` marketplace as a directory source at
  `./`, enables plugins, and runs a script on `SessionStart`; on a head checkout the PR controls all
  three. The action's marketplace input rejects a URL with a `#<ref>` suffix, so a marketplace URL
  cannot pin the base SHA; a local path is accepted (`base-action/src/install-plugins.ts:7-8`,
  `:15-23`).
- **The GitHub token reaches Claude whatever the checkout set.** The action writes the token it was
  given into the origin URL in `.git/config` and exports it to Claude as `GH_TOKEN` and
  `GITHUB_TOKEN` (`src/github/operations/git-config.ts:70`, `replaceCheckoutCredentials`;
  `src/entrypoints/run.ts:189-191`), whatever
  `persist-credentials` the checkout set.
- **Every Bash child inherits the credentials, with no root needed.** The action puts
  `CLAUDE_CODE_OAUTH_TOKEN` in Claude's environment (`action.yml:336`). It sets
  `CLAUDE_CODE_SUBPROCESS_ENV_SCRUB` only when `allowed_non_write_users` is set (`action.yml:301`)
  and installs bubblewrap only then (`action.yml:225-247`). Without the scrub, any command the
  skill runs can read both tokens from its own environment or from `/proc/<ancestor>/environ`.
- **A verdict step after the skill is forgeable by code the skill ran.** A gate skill's verdict is
  read in the same job after the skill, and head code that ran first can write a `$RUNNER_TEMP`
  file-command file, set `BASH_ENV`, or leave a process running.

## Decision

A skill activity loads no settings, hooks, instructions, plugins or base from the PR head, and the
code it may run is limited by what it holds. Line references are to
[`pr-run-activity.yml`](../../.github/workflows/pr-run-activity.yml) on the default branch.

1. **Only the default branch is a trusted base.** The run job checks out the default branch tip
   first and runs the kill switch and trigger gate from it. It fails red unless the PR targets the
   default branch and the gated base SHA is an ancestor of the default branch tip, and only then
   checks that SHA out (lines 113-175). The report job checks out the default branch tip, then the
   run job's base SHA only when the tip holds it, and never the event's base SHA (lines 608-638).
2. **`--setting-sources user`.** `claude_args` passes it, so no project or local settings, hooks,
   `CLAUDE.md`, `AGENTS.md` or `.mcp.json` load (lines 391-394).
3. **Plugins from a base copy.** Before the head checkout, the run job copies the base tree's
   `plugins/` and `.claude-plugin/` to `$RUNNER_TEMP/base-marketplace`, and the plugin installs only
   from that path (lines 253-304, 388-389). The runner exposes no marketplace input.
4. **The action's own restore as a second layer.** On PR events where claude-code-action treats the
   head as untrusted, it replaces `.claude`, `.mcp.json`, `CLAUDE.md` and its other listed config
   paths with the base branch's copies before Claude starts. For a `read` skill, the next step puts
   back only what that restore changed, so the dirty-tree check counts the skill's own edits and
   not the action's (lines 456-491).
5. **Subprocess isolation.** The skill step sets `CLAUDE_CODE_SUBPROCESS_ENV_SCRUB=1`, which strips
   the OAuth token and other credentials from Bash, hook and MCP subprocesses and gives Bash its own
   PID namespace (lines 373-379). It keeps `GH_TOKEN` and `GITHUB_TOKEN` by design
   ([environment variables](https://code.claude.com/docs/en/env-vars), as of 2026-10-04), so a
   subprocess still holds the activity's GitHub token. Because the action installs bubblewrap only
   for `allowed_non_write_users`, the run job installs bubblewrap and socat itself and fails red
   when `bwrap` is missing (lines 306-327).
6. **No root and no unneeded token in the head-code job.** A `read` activity mints no App token
   (lines 189-220). Before the head checkout the run job makes the docker socket root-only, deletes
   the runner user's sudoers entry, and fails red if either still works (lines 329-348).
7. **A skill that holds a write token or gates must not run head code.** A skill whose effect is not
   `read` holds a contents-write App token in its process and in the git config, so it runs no test,
   build or other PR code through Bash. A `gating: gate` skill must end in a schema-checked verdict
   (`--json-schema`, lines 283-292) that the next step reads from the action's `structured_output`
   and fails on unless it is exactly `pass` (lines 433-454); since that step runs after the skill,
   a gate skill runs no head code either. Gating tests, linters and builds run as a `script`
   activity. A lane that needs head code with a write effect runs outside this contract until a
   split design exists: a read-only run, then a separate step that makes the signed commit.

The model step also runs with `--permission-mode dontAsk` and
`--allowedTools "Skill(<plugin>:<skill>)"`, so the skill's own `allowed-tools` decide what else it
may use.

## Alternatives considered

- **Trust the event's base SHA.** Rejected: a PR into a non-default branch would choose the actions,
  config and trusted-actor list it is judged by.
- **Default setting sources.** Rejected: the head's settings, hooks and marketplace declaration
  would load, so a PR could replace the plugin or run a hook in the lane.
- **Pin the marketplace by URL at the base SHA.** Rejected: the action rejects a `#<ref>` suffix.
- **Rely on the action's restore alone.** Rejected: it applies only on PR events it treats as
  untrusted, not on `workflow_dispatch`, and it is the action's behavior rather than this
  repository's contract.
- **Rely on `persist-credentials: false` to keep the token out of head code.** Rejected: the action
  rewrites the origin URL with the token.
- **A `sandbox.credentials` deny to also strip `GH_TOKEN` from subprocesses.** Rejected: it breaks
  `gh` inside skills.
- **Read the gate verdict from the skill's own files or reply text.** Rejected: head code could
  write them; the verdict comes only from the action's `structured_output`.

## Consequences

Evidence is from runs in `melodic-software/pr-pipeline-sandbox`, whose staged runner matched the
default-branch workflow at each commit named.

- Head isolation held on both event types (runs 6a-6d, runner `5dde7ca`):
  [37220036528](https://github.com/melodic-software/pr-pipeline-sandbox/actions/runs/37220036528)
  and [37220036159](https://github.com/melodic-software/pr-pipeline-sandbox/actions/runs/37220036159)
  on `pull_request`,
  [37220033402](https://github.com/melodic-software/pr-pipeline-sandbox/actions/runs/37220033402)
  and [37220035192](https://github.com/melodic-software/pr-pipeline-sandbox/actions/runs/37220035192)
  on `workflow_dispatch`. Each head added a `SessionStart` hook or a same-named head marketplace;
  each log shows only the `base-marketplace` add and one install, no match for the head
  marketplace, its version or the hook marker, and a clean tree. The undo step ran on the PR events
  and was skipped on dispatch.
- The skill saw the base plugin, not the head's: on runner `ae092ae`, run
  [37223060696](https://github.com/melodic-software/pr-pipeline-sandbox/actions/runs/37223060696)'s
  reply artifact holds exactly the base marker string, and the head's marker is absent.
- A stacked PR gets a failure check and runs nothing: run
  [37222032673](https://github.com/melodic-software/pr-pipeline-sandbox/actions/runs/37222032673)
  failed every run job at "Assert the base is on the default branch", with no head checkout, mint or
  act step.
- Sudo and docker are gone before head code: run
  [37222034731](https://github.com/melodic-software/pr-pipeline-sandbox/actions/runs/37222034731)
  read `sudo: a password is required`, a root-only socket, and a skipped mint for a `read` activity.
- A gate skill's verdict decides its check: runs
  [37223056307](https://github.com/melodic-software/pr-pipeline-sandbox/actions/runs/37223056307)
  (`fail`, check failure) and
  [37223332017](https://github.com/melodic-software/pr-pipeline-sandbox/actions/runs/37223332017)
  (`pass`, check success) on runner `ae092ae`.
- The scrub works as documented: in run
  [37223500535](https://github.com/melodic-software/pr-pipeline-sandbox/actions/runs/37223500535),
  Bash ran as pid 2 under `bwrap` with no ancestor visible, and Bash's environment, its own
  `environ` and bwrap's held no OAuth token and no `sk-ant-` value. `GH_TOKEN` and `GITHUB_TOKEN`
  were present, and `gh api` and `curl https://api.github.com` both succeeded from sandboxed Bash.
- Skills cannot lean on project `CLAUDE.md` or rules in a lane; what a skill needs must be in the
  skill.
- Claude's output is hidden in the action log, so the run job writes the skill's final reply to the
  step summary and a 7-day artifact as data for audit.
- Accepted residual: a skill's subprocesses hold the activity's GitHub token: the job
  `GITHUB_TOKEN` for `read`, the effect-scoped one-hour App token otherwise, which the model already
  holds.
- Accepted residual: the isolation step sets `kernel.apparmor_restrict_unprivileged_userns=0` for
  the whole runner, which re-enables unprivileged user namespaces for head code too. A user
  namespace local-root exploit would restore the runner memory route. Trying the
  `bwrap-userns-restrict` AppArmor profile instead is a follow-up.
- Accepted residual, decided and not built: the App private key and the OAuth token are in the run
  job's secret set even for `read` jobs, because a step-level `if:` is evaluated after the job
  receives its secrets. The decided fix is a token broker (an OIDC exchange) that keeps the App key
  off any runner that runs head code. Until it lands, no live lane that runs head code or holds a
  write effect may be configured.
- Accepted residual, decided and not built: on `pull_request` the runner itself loads from the PR's
  merge commit, so a PR that edits `.github/workflows/` can drop these flags. The bound is who can
  push `.github/workflows/`; the decided fix is a ruleset or CODEOWNERS protection on
  `.github/workflows/**`, required before the first live caller of `pr-run-activity.yml`.
- Accepted residual: `pr-fix-ci` runs tests with a write effect, so it waits on the split design.
- Re-derive this record when the claude-code-action pin moves past `ed670b4` and its setting-source
  default, marketplace parsing, credential handling, scrub defaults or restore list changes, or
  when the Claude Code docs change what the subprocess scrub keeps.
