# review

A Claude Code plugin bundling one cohesive capability: **code review**. Nine
agents, read-only over the reviewed code, plus orchestration skills: a single-lens quality gate, a
multi-surface review fan-out that normalizes every reviewer's output into one
severity-ranked, deduplicated findings report, and the other review skills listed below.

## Components

### Agents (nine, read-only over the reviewed code)

| Agent | Concern |
|---|---|
| `code-reviewer` | Quality, convention adherence, and design judgment automated tooling misses; carries a named Fowler design-smell baseline (advisory, project standards override) |
| `security-reviewer` | Cross-ecosystem security audit. OWASP Top 10, injection, secrets, auth (P1–P5 severity) |
| `architecture-guardian` | Dependency direction, boundary integrity, pattern compliance |
| `doc-drift-detector` | Documentation that no longer matches the code. Stale, missing, aspirational |
| `ecosystem-specialist` | Multi-language build/test/lint verification, detected from changed paths |
| `ci-log-auditor` | GitHub Actions run audit. Masked failures, skipped jobs, suspicious successes, perf outliers |
| `brief-reviewer` | Runs the review brief it is dispatched with: quality-gate slice, downstream, spec, close-out and restatement work, fanout criteria slices, and the explain-change risk-map check. Its tools exclude `Agent` and `Skill`, so it cannot fan out |
| `stage-normalizer` | Fanout findings pipeline Stage 0 (extraction) and Stage 3 (dedup). Holds `Read` only, because it reads untrusted reviewer output; inherits the model so role routing applies |
| `lane-verifier` | Hunter or verifier subagent for the CI lanes (`/review:code-review`, `/review:security-review`). Its tools exclude `Agent` and `Skill`, so it cannot re-invoke the lane's skill; inherits the model and pins no effort, so the lane's choice holds |

No review skill dispatches a general-purpose or `Explore` subagent: every subagent a review skill
starts is one of these nine, so no reviewer can spawn agents or invoke a review skill and fan out.

- **Pointer**: when checking which tools a built-in subagent holds, fetch
  [create custom subagents: built-in subagents](https://code.claude.com/docs/en/sub-agents#built-in-subagents)
  live. **As of**: 2026-10-04. **Recheck trigger**: that section changes a built-in subagent's
  tool list.

The first six declare persistent per-project memory (`memory: local`, stored under
`.claude/agent-memory-local/` and never checked into version control) so they can learn a
codebase's patterns across sessions without dirtying the consumer repo's tracked tree. Two
limits apply:

- **Memory needs auto memory.** With `autoMemoryEnabled: false` or
  `CLAUDE_CODE_DISABLE_AUTO_MEMORY=1` in your settings, the `memory` field has no effect: nothing
  persists across sessions and each agent's `## Memory` section does nothing.
- **"Read-only" is an instruction, not a tool boundary.** None of the first six lists `Write` or
  `Edit`, but with auto memory on the harness enables both so the agent can manage its memory
  files, and nothing scopes them to the memory directory. The last three declare no `memory`
  field, so auto memory grants them neither. `permissionMode` cannot narrow a plugin
  subagent either. Bash is a second unenforced write path for every agent except `stage-normalizer`, and
  `ecosystem-specialist` runs build and test commands that write artifacts. Keeping writes to
  the memory directory and off the reviewed code is the agents' own convention.

Each agent also treats the reviewed code, `REVIEW.md`, rules files and cited documents as data:
an instruction embedded in them is reported as a finding, and project conventions override an
agent's baseline only as review criteria.

*Basis for the two limits, as of 2026-09-28:* [Create custom subagents](https://code.claude.com/docs/en/sub-agents)
states that with memory enabled "Read, Write, and Edit tools are automatically enabled so the
subagent can manage its memory files", that turning auto memory off means "the `memory` field
has no effect", and lists `permissionMode` among the fields ignored for plugin subagents.
*Recheck* when that page stops carrying any of those three statements, or a release note names
subagent memory tools, auto memory, or plugin-subagent frontmatter restrictions.

Invoke via `@review:<agent>` or let Claude delegate.

### Skills

- **`/review:quality-gate [mode]`**, the single-lens checkpoint between "code works"
  and "code is ready". Modes: `self` (fresh-context self-review), `code`, `architecture`,
  `security`, `spec` (spec-fidelity: did the change deliver what the originating item, plan, or
  brief asked for), `close-out` (the same fidelity lens at spec-container scale, one cumulative
  pass over everything a container shipped, across however many PRs, against the container's own
  body; derives its own diff basis per execution shape, and its acceptance-criteria rollup gains a
  requirement-pattern column when the container's criteria carry bracketed EARS tags),
  `downstream` (what the change breaks
  outside its own diff: callers, serialization boundaries, cross-service consumers), `pr`,
  `criteria`, `slice <name>`, `restatement`.
- **`/review:fanout [mode]`**. Breadth review: fans out across the
  reviewer agents, the project's own per-concern review criteria docs, and optional
  orchestrator review plugins, then normalizes everything into one ranked findings report.
  Modes: default (auto-scales to diff size), `run-everything` (full roster), `fix` (applies
  the merged set of persisted findings, the only mutating mode).
- **`/review:explain-change [pr-number|this branch] [--event ready] [--policy off|offer|always] [--quiz] [--risk-only]`**.
  Change digest for a pull request: why, before and after, a risk map that a fresh-context
  agent checks (disputed rows stay, marked), where to focus, a run-e2e recording link when one
  exists for the head, annotated hunks, and a quiz on request. The markdown digest is the
  record. An interactive view is built only from the checked-in template plus the digest as
  escaped JSON, outside the working tree, and is published as a private Artifact unless `medium`
  says otherwise; the shipped default publishes only a public repository's diff with no
  credential-shaped hunk, and keeps any other page local. The `review-digest` cascade concern sets `digest_policy` (`off`, `offer` by
  default, or `always` at the ready flip) and the offer thresholds. It never posts to the pull
  request and never gates merge. `--risk-only` returns just the checked risk map and a `demote`
  flag, which may only send an unattended merge to a human and never makes a pull request
  merge-eligible.
- **`/review:code-review`**. CI code-review lane command for a pull request
  (correctness / maintainability; security scoped out where a separate security
  lane runs, folded back in where none does).
- **`/review:security-review`**. CI security-review lane command for a pull
  request (org-authored; built-in `/security-review` is unusable under Actions
  checkout).

- **`/review:check`**. Read-only: reports whether node resolves and the connected-page guard
  below is registered. Installs nothing.

### Hook

A PreToolUse hook on the `Artifact` tool denies a call that would publish an HTML page whose
content security policy names a loopback `connect-src`: a connected page (built with
`--connect`) works only on this machine and stays a local file. It reads the file content, so a
connected page from any builder is caught, in `file_path` or in `files`. Every other Artifact
call passes, as does a file it cannot read. Turn it off with `connected_page_guard_enabled`.
It is not the approval-marker publish gate (#7956), and it does not cover
`/visualization:present`'s `--argument artifact` flag.

### Workflows

- **`/review:fanout-sweep`** (`workflows/fanout-sweep.js`). The leaf fan-out of
  `/review:fanout run-everything` as a saved workflow: the four reviewer agents by tier, then one
  `brief-reviewer` agent per project criteria slice, then one `stage-normalizer` agent that turns the raw findings
  into records. Its `args` carry `diffBase` (required; without it the run dispatches nothing),
  `slices`, `roles` and `maxConcurrent` (default 4). `roles` is the map `/multi-agent:route all`
  prints; only the extractor is routed, and without it a built-in fallback runs the extractor on
  `sonnet` at `medium`. The reviewer agents, slices included, keep the model and effort pinned in
  their own definitions.

## Recall cases

The `evals/recall-*` cases measure whether `/review:code-review` finds bugs the review lanes
missed in this repository. Each case's scaffold rebuilds a reverted or fixed pull request's
affected files offline from `evals/fixtures/`, and its regex grader reports the bug found or
missed at the file and line of the rebuilt files. Each `case.yaml` records the pull request, its
base commit, the bug's `file:line`, the fix and who confirmed the location. The lane's other
findings on that pull request stay in the run output and are not graded.

A pull request that changes a review lane's prompt, model or effort cites the recall score before
and after the change: the number of `recall-*` cases found, from the same command run on the base
and on the change:

```bash
claude plugin eval plugins/review --case 'recall-*' --scaffold --ablation none --runs 1 --max-cost-usd <usd>
```

## Requirements

- **git**. Every reviewer works from diffs, branches, and history.
- **`gh` CLI, authenticated**, required by `ci-log-auditor` (all CI-run
  evidence routes through `gh api`) and by PR-scoped review flows; the agent
  stops with a remediation message when `gh` is missing or unauthenticated.
  Local-diff reviews without a CI/PR angle work without it.
- **Bash** for the agents' inline commands. Git Bash on native Windows
  (install
  [Git for Windows](https://code.claude.com/docs/en/setup#set-up-on-windows));
  no standalone `jq` is required.

## Works in any repo

- **Reads your conventions, assumes none.** Every agent and skill reads the consuming
  project's own review criteria, severity vocabulary, and conventions first (`CLAUDE.md`,
  project rules, `REVIEW.md`/review docs); the plugin's bundled baseline
  (`context/severity.md`) applies only where the project defines nothing.
- **Command truth from `.claude/ecosystems/`.** `ecosystem-specialist` resolves each
  ecosystem's build/test/lint command from the consumer's `.claude/ecosystems/<ecosystem>.yaml`
  files when present (the marketplace-wide ecosystem-commands contract,
  `docs/contracts/ecosystem-commands/README.md`), falling back to your documented conventions,
  then its own bundled generic defaults as a last resort.
- **Graceful degrade.** Optional orchestrator plugins. `pr-review-toolkit` and `code-review` from
  the official marketplace, and `codex` from the OpenAI Codex marketplace. They add adversarial breadth
  when installed; every path works without them. Claude Code's bundled `/code-review` command and
  the managed Code Review GitHub App service are two further surfaces, distinct from the
  `code-review` marketplace plugin despite the shared name. **`/review` is one of them, not this
  plugin**: per [code-review](https://code.claude.com/docs/en/code-review-local)
  (fetched 2026-08-10), "`/review` is an alias of `/code-review`; before v2.1.223, it was a separate
  command that ran a single-pass, read-only review of a GitHub pull request." Recheck when that
  page changes the `/review` alias note. A bare `/review` is that bundled reviewer, so name this plugin's skills by their namespaced commands
  (`/review:quality-gate`, `/review:fanout`) rather than abbreviating to the plugin name. The
  0.18.0 removal of the bare `/<skill>` alias already made the namespaced form the only one this
  plugin registers. See the Boundary sections of
  [`skills/quality-gate/context/pr.md`](skills/quality-gate/context/pr.md) and
  [`skills/fanout/SKILL.md`](skills/fanout/SKILL.md) for how each skill relates to all three.
- **Self-contained.** The severity baseline and all mode guidance ship inside the plugin
  and are referenced via `${CLAUDE_PLUGIN_ROOT}`.

## Findings location

Review findings persist to the memory tier, concern-scoped on the branch axis, under
`.work/reviews/<branch-slug>/` by default (`.work/` unless the project's instructions declare another
memory root). The memory root self-ignores (a `.gitignore` containing `*`,
created on the session's first memory-tier write), so findings never enter version control.

## Install

```shell
/plugin marketplace add melodic-software/claude-code-plugins
/plugin install review@melodic-software
```

## Configuration

Review criteria and findings location route through your own project context: review
criteria docs and severity vocabulary override the bundled baseline, and a documented
findings location in your `CLAUDE.md`/rules overrides the default path.

Three settings, each set per user through the option below or per repository in
`docs/conventions/review.yaml` (written by `/review:setup apply`). `ratchet_offer` is unused: no
skill in this plugin reads it. `downstream_probe` decides whether `/review:quality-gate downstream` runs the one probe it writes
for its safety fact (`run`) or only states it (`report`). It is a policy floor: `report` in either
layer wins, and the repository value is read from the default branch. `fanout_diversity` decides
whether `/review:fanout run-everything` runs one reviewer agent per concern (`lens`, the default)
or sends one review prompt to each model tier the role map names (`model`). Keys, values and resolution:
[`reference/config.md`](reference/config.md).

<!-- BEGIN GENERATED: plugin options. Edit plugin.json, then run scripts/sync-plugin-options-docs.py -->

### Options reference

Generated from this plugin's `.claude-plugin/plugin.json`. Every option Claude Code
will prompt for when the plugin is enabled, with the environment variable each hook
reads it from.

| Option | Type | Default | Environment variable | Description |
| --- | --- | --- | --- | --- |
| `connected_page_guard_enabled` | boolean | `true` | `CLAUDE_PLUGIN_OPTION_CONNECTED_PAGE_GUARD_ENABLED` | Runs the PreToolUse hook that denies an Artifact publish of an HTML page whose content security policy names a loopback connect-src. On by default. Turn off to allow publishing such a page. |
| `ratchet_offer` | boolean | `true` | `CLAUDE_PLUGIN_OPTION_RATCHET_OFFER` | Unused: no skill in this plugin reads it. |
| `downstream_probe` | string | `"run"` | `CLAUDE_PLUGIN_OPTION_DOWNSTREAM_PROBE` | run (default): /review:quality-gate downstream mode writes one probe for its safety fact in a temp directory outside the tree and runs it. report: it shows the probe without running it. report here or in a repository's docs/conventions/review.yaml (default branch) wins over run. |
| `fanout_diversity` | string | `"lens"` | `CLAUDE_PLUGIN_OPTION_FANOUT_DIVERSITY` | lens (default): /review:fanout run-everything runs one reviewer agent per concern. model: it sends one review prompt to each distinct fan-out model tier instead. A repository's docs/conventions/review.yaml fanout_diversity wins over this option. |

### How to set these

Three supported routes:

1. **Interactively.** Open this plugin's options dialog ([`/plugin` in a session](https://code.claude.com/docs/en/plugins/cli-reference#plugin-in-a-session)):
   `/plugin configure review@<marketplace>`.
2. **Headless.** Save the values with [`claude plugin configure`](https://code.claude.com/docs/en/plugins/cli-reference#plugin-configure),
   run from the project the plugin is installed in. Replace
   `<marketplace>` with the marketplace you installed this plugin from:

   ```shell
   claude plugin configure review@<marketplace> --values-stdin < values.json
   ```

   `values.json` holds a JSON object of strings, booleans included:

   ```json
   {"connected_page_guard_enabled": "<value>"}
   ```

   This is the preferred headless route in the [plugin-reconfiguration convention](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/contracts/plugin-reconfiguration/README.md), which records its
   limits: the Claude Code version it needs, which install it finds, how it rejects a bad
   value, and why a session started before the change keeps the old value until a fresh
   session starts. Do **not** `claude plugin uninstall` to reconfigure: see
   [What an uninstall deletes and keeps](https://code.claude.com/docs/en/plugins/cli-reference#what-an-uninstall-deletes-and-keeps).

   The fallback the convention names, for a Claude Code release without
   `plugin configure`, reruns the install with the new value, passing the scope
   `claude plugin list` reports for this plugin:

   ```shell
   claude plugin install review@<marketplace> -s <scope> --config connected_page_guard_enabled=<value>
   ```

3. **By hand, in settings.** Add the value under `pluginConfigs` in your **user**
   settings (`~/.claude/settings.json`):

   ```json
   {
     "pluginConfigs": {
       "review@<marketplace>": {
         "options": {
           "connected_page_guard_enabled": <value>
         }
       }
     }
   }
   ```

   The [`pluginConfigs`](https://code.claude.com/docs/en/settings-reference#pluginconfigs)
   entry names the settings scopes Claude Code reads this key from.

Do not set the `CLAUDE_PLUGIN_OPTION_*` variables yourself; set the value through one
of the routes above.

### Upstream documentation

- [User configuration](https://code.claude.com/docs/en/plugins/manifest-reference#user-configuration): the `userConfig` schema and the `CLAUDE_PLUGIN_OPTION_<KEY>` export
- [Plugin configure](https://code.claude.com/docs/en/plugins/cli-reference#plugin-configure): the `--values-stdin` flag's reference entry
- [Plugin install options](https://code.claude.com/docs/en/plugins/cli-reference#plugin-install): the `--config` flag's reference entry
- [Plugins and skills settings](https://code.claude.com/docs/en/settings-reference#plugins-and-skills): `enabledPlugins`, `extraKnownMarketplaces`, `pluginConfigs`
- [Settings files and who they affect](https://code.claude.com/docs/en/settings#settings-files-and-who-they-affect): user vs project vs local precedence
- [Manage installed plugins](https://code.claude.com/docs/en/plugins/install#manage-installed-plugins): enabling, disabling, `/plugin list`

<!-- END GENERATED: plugin options -->

## License

MIT (SPDX-License-Identifier: MIT).
