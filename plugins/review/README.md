# review

A Claude Code plugin bundling one cohesive capability: **code review**. Six reviewer
agents, read-only over the reviewed code, plus orchestration skills: a single-lens quality gate, a
multi-surface review fan-out that normalizes every reviewer's output into one
severity-ranked, deduplicated findings report, and the other review skills listed below.

## Components

### Agents (six, read-only over the reviewed code)

| Agent | Concern |
|---|---|
| `code-reviewer` | Quality, convention adherence, and design judgment automated tooling misses; carries a named Fowler design-smell baseline (advisory, project standards override) |
| `security-reviewer` | Cross-ecosystem security audit. OWASP Top 10, injection, secrets, auth (P1–P5 severity) |
| `architecture-guardian` | Dependency direction, boundary integrity, pattern compliance |
| `doc-drift-detector` | Documentation that no longer matches the code. Stale, missing, aspirational |
| `ecosystem-specialist` | Multi-language build/test/lint verification, detected from changed paths |
| `ci-log-auditor` | GitHub Actions run audit. Masked failures, skipped jobs, suspicious successes, perf outliers |

All six declare persistent per-project memory (`memory: local`, stored under
`.claude/agent-memory-local/` and never checked into version control) so they can learn a
codebase's patterns across sessions without dirtying the consumer repo's tracked tree. Two
limits apply:

- **Memory needs auto memory.** With `autoMemoryEnabled: false` or
  `CLAUDE_CODE_DISABLE_AUTO_MEMORY=1` in your settings, the `memory` field has no effect: nothing
  persists across sessions and each agent's `## Memory` section does nothing.
- **"Read-only" is an instruction, not a tool boundary.** None of the six lists `Write` or `Edit`,
  but with auto memory on the harness enables both so the agent can manage its memory files,
  and nothing scopes them to the memory directory. `permissionMode` cannot narrow a plugin
  subagent either. Bash is a second unenforced write path for all six agents, and
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
- **`/review:explain-change [pr-number|this branch] [--event ready] [--policy off|offer|always] [--quiz]`**.
  Change digest for a pull request: why, before and after, a risk map that a fresh-context
  agent checks (disputed rows stay, marked), where to focus, a run-e2e recording link when one
  exists for the head, annotated hunks, and a quiz on request. The markdown digest is the
  record. An interactive view is built only from the checked-in template plus the digest as
  escaped JSON, outside the working tree, and is published as a private Artifact unless `medium`
  says otherwise; the shipped default publishes only a public repository's diff with no
  credential-shaped hunk, and keeps any other page local. The `review-digest` cascade concern sets `digest_policy` (`off`, `offer` by
  default, or `always` at the ready flip) and the offer thresholds. It never posts to the pull
  request and never gates merge. `/review:pr-explainer` is a one-release stub that points here.
- **`/review:audit-enforceability <findings-file>`**. Read-only enforcement audit over ONE
  operator-named findings file: derives a class per finding, maps it to the cheapest deterministic
  rung (editorconfig severity, analyzer-pack rule, custom analyzer, Semgrep rule, architecture
  test, hook, or llm-only), and writes one proposal stub per finding naming that rung and its
  owner. It proposes a rung and never implements one.
- **`/review:ratchet [<counter, rule or claim>]`**. Holds a count with a checked-in CI ceiling: a
  lint rule's violations, a suppression count, a verified performance counter, or a telemetry
  count. A zero count turns the rule on with no ceiling; a non-zero one is recorded at its measured
  value in the ceilings file CI already checks (`.performance/ratchets.json` when CI calls
  `ratchet.py check` with no `--file`), or in a new `.ratchets.json`, with a check step inside the
  required job and a same-PR or scheduled tightening plan. Counters only, never durations. It
  writes proposed files uncommitted and never merges.
- **`/review:code-review`**. CI code-review lane command for a pull request
  (correctness / maintainability; security scoped out where a separate security
  lane runs, folded back in where none does).
- **`/review:security-review`**. CI security-review lane command for a pull
  request (org-authored; built-in `/security-review` is unusable under Actions
  checkout).

### Workflows

- **`/review:fanout-sweep`** (`workflows/fanout-sweep.js`). The leaf fan-out of
  `/review:fanout run-everything` as a saved workflow: the four reviewer agents by tier, then one
  agent per project criteria slice, then one extraction agent that turns the raw findings into
  records. Its `args` carry `diffBase` (required; without it the run dispatches nothing),
  `slices`, `roles` and `maxConcurrent` (default 4). `roles` is the map `/multi-agent:route all`
  prints. Without it, built-in fallbacks run slice agents on `opus` at `high` effort and the
  extractor on `sonnet` at `low`. The reviewer agents keep the model and effort pinned in their
  own definitions.

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
  `docs/conventions/ecosystem-commands/README.md`), falling back to your documented conventions,
  then its own bundled generic defaults as a last resort.
- **Graceful degrade.** Optional orchestrator plugins. `pr-review-toolkit` and `code-review` from
  the official marketplace, and `codex` from the OpenAI Codex marketplace. They add adversarial breadth
  when installed; every path works without them. Claude Code's bundled `/code-review` command and
  the managed Code Review GitHub App service are two further surfaces, distinct from the
  `code-review` marketplace plugin despite the shared name. **`/review` is one of them, not this
  plugin**: per [code-review](https://code.claude.com/docs/en/code-review#review-a-diff-locally)
  (fetched 2026-08-10), "`/review` is an alias of `/code-review`; before v2.1.223, it was a separate
  command that ran a single-pass, read-only review of a GitHub pull request." A bare `/review` is
  that bundled reviewer, so name this plugin's skills by their namespaced commands
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

Enforcement-rung proposal stubs go to the separate
`enforceability/<branch-slug>/` directory under the same root, and the stub writer is handed both resolved homes so a stub
can never land in the directory the `fanout` `fix` action scans, nor in the findings file's own
directory.

## Install

```shell
/plugin marketplace add melodic-software/claude-code-plugins
/plugin install review@melodic-software
```

## Configuration

Review criteria and findings location route through your own project context: review
criteria docs and severity vocabulary override the bundled baseline, and a documented
findings location in your `CLAUDE.md`/rules overrides the default path.

Two settings. `ratchet_offer` decides whether `/review:audit-enforceability` stubs offer a
`/review:ratchet` count ceiling; set it per user through the option below, or per repository in
`docs/conventions/review.yaml` (written by `/review:setup apply`), which wins.
`downstream_probe` decides whether `/review:quality-gate downstream` runs the one probe it writes
for its safety fact (`run`) or only states it (`report`). It is a policy floor: `report` in either
layer wins, and the repository value is read from the default branch. Keys, values and resolution:
[`reference/config.md`](reference/config.md).

<!-- BEGIN GENERATED: plugin options. Edit plugin.json, then run scripts/sync-plugin-options-docs.py -->

### Options reference

Generated from this plugin's `.claude-plugin/plugin.json`. Every option Claude Code
will prompt for when the plugin is enabled, with the environment variable each hook
reads it from.

| Option | Type | Default | Environment variable | Description |
| --- | --- | --- | --- | --- |
| `ratchet_offer` | boolean | `true` | `CLAUDE_PLUGIN_OPTION_RATCHET_OFFER` | When on (default), /review:audit-enforceability stubs on a rung that counts violations offer /review:ratchet for a non-zero count once the rule exists. Off leaves the offer out. A repository's docs/conventions/review.yaml ratchet_offer wins over this option. |
| `downstream_probe` | string | `"run"` | `CLAUDE_PLUGIN_OPTION_DOWNSTREAM_PROBE` | run (default): /review:quality-gate downstream mode writes one probe for its safety fact in a temp directory outside the tree and runs it. report: it shows the probe without running it. report here or in a repository's docs/conventions/review.yaml (default branch) wins over run. |

### How to set these

Three supported routes, in the order most people want them:

1. **Interactively.** Claude Code prompts for declared options when you enable the
   plugin. To change them later: `/plugin configure review@<marketplace>`.
2. **Headless.** Repeat `--config` for each option. Replace
   `<marketplace>` with the marketplace you installed this plugin from:

   ```shell
   claude plugin install review@<marketplace> -s <scope> --config ratchet_offer=<value>
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
       "review@<marketplace>": {
         "options": {
           "ratchet_offer": <value>
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

## License

MIT (SPDX-License-Identifier: MIT).
