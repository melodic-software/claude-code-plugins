# review

A Claude Code plugin bundling one cohesive capability: **code review**. Nine
agents, read-only over the reviewed code, plus orchestration skills: a single-lens quality gate, a
multi-surface review fan-out that normalizes every reviewer's output into one
severity-ranked, deduplicated findings report, and the other review skills listed below.

## Components

### Agents (nine, read-only over the reviewed code)

| Agent | Concern |
|---|---|
| `code-reviewer` | Quality, convention adherence, and design judgment automated tooling misses; checks a Fowler design-smell list chosen by `smell_baseline` (advisory, project standards override) |
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
  live.

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

*Basis for the two limits:* [Create custom subagents](https://code.claude.com/docs/en/sub-agents)
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
- **`/review:council [--yes]`**. Council review: a panel of configured members (provider, model,
  brief, effort), chosen for the change by ordered rules over its paths, size tier and merge
  risk, writes one ranked findings report in fanout's shape. Claude members run as
  `brief-reviewer`; Codex members run through `scripts/codex-review.sh`. A member that cannot run
  as configured is reported, never replaced. One round by default; above one
  (`council_max_rounds`), `/review:fanout fix` runs between rounds and later rounds review only
  what it changed. Opt-in for lanes through `council_lanes`. Posts nothing.
- **`/review:explain-change [pr-number|this branch] [--event ready] [--policy off|offer|always] [--quiz]`**.
  Change digest for a pull request: why, before and after, a risk map that a fresh-context
  agent checks (disputed rows stay, marked), where to focus, a run-e2e recording link when one
  exists for the head, annotated hunks, and a quiz on request. The markdown digest is the
  record. An interactive view is built only from the checked-in template plus the digest as
  escaped JSON, outside the working tree, and is published as a private Artifact unless `medium`
  says otherwise; the shipped default publishes only a public repository's diff with no
  credential-shaped hunk, and keeps any other page local. The `review-digest` cascade concern sets `digest_policy` (`off`, `offer` by
  default, or `always` at the ready flip) and the offer thresholds. It never posts to the pull
  request and never gates merge. Its risk map is a `/review:merge-risk` rating.
- **`/review:merge-risk [pr-number|pr-url|this branch] [--dir <dir>]`**. Merge-risk rating of one
  pull request against one rubric: alignment with the closing issue, impact, verification,
  reversibility and error detection, each `LOW` to `CRITICAL`, checked blind by a fresh-context
  agent. Returns the rows for the head it read and a `demote` flag, which may only send an
  unattended merge to a human and never makes a pull request merge-eligible. Posts nothing and
  gates nothing.
- **`/review:code-review`**. CI code-review lane command for a pull request
  (correctness / maintainability; security scoped out where a separate security
  lane runs, folded back in where none does).
- **`/review:security-review`**. CI security-review lane command for a pull
  request (org-authored; built-in `/security-review` is unusable under Actions
  checkout).

- **Prerequisite check**. `node "<plugin root>/lib/prerequisites.mjs" check "<plugin root>"` reports whether node
  resolves; `bash "<plugin root>/scripts/check-hook-registration.sh"` reports whether the
  connected-page guard below is registered and denies a sample page. Both are read-only.

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

## Revert cases

The `evals/revert-*` cases measure what `/review:code-review` misses, using merged pull requests
that a later revert undid. A case is caught when the review's reply cites, as `<file>:<line>`,
a line the pull request added and the revert removed. The grader matches the citation, not
the finding's content. `evals/revert-cases.sh` lists the pairs, builds the
cases and reports a run. Run `list` and `build` from a clone with full history:

1. `bash plugins/review/evals/revert-cases.sh list` prints one row per revert pair: original
   pull request, original commit, revert pull request (`-` for a direct commit), revert commit,
   then the pair count. A revert is a `revert:` or `revert(<scope>):` subject or a
   `This reverts commit <sha>` body line; when neither names its original, each merged
   non-revert pull request the message names by number is tried, so one revert can list several
   pairs, and a message can name one it did not undo, which the verifier below rejects. The
   script skips a pair whose original names no pull
   request, whose revert removes no line the original added, or whose original no longer
   reverses cleanly onto the revert's parent, and prints each skip with its reason on stderr.
2. `bash plugins/review/evals/revert-cases.sh build <original> <revert> <slug>` writes
   `evals/revert-<pr>-<slug>/` with a regex grader on those lines and `fixtures.tar.gz`: the
   files holding those lines at the base and the merge, and the original commit message as the
   pull request context. They are an archive because they are byte copies of history that
   repository lints must not judge. Its `case.yaml` records the pull request, the revert and the lines, matched by
   their text. A verifier agent then checks the lines against the revert and drops any that only
   repeat a reverted line's text. `build` writes the lines to three places, and nothing rebuilds
   one from another, so the verifier drops each line from all three: the `# lines:` comment in
   `case.yaml`, `expected_outcome` in `prompt.md`, and the line alternation in
   `graders/caught.md`, removing a file's whole alternative when none of its lines remain. A line
   left in the grader still counts a citation of it as caught. Last, the verifier names itself on
   the `confirmed-by:` line. Until then the case's scaffold refuses to run.
3. Run the cases, then report caught or missed per case and the total:

   ```bash
   claude plugin eval plugins/review --case 'revert-*' --scaffold --ablation none --runs 1 --json result.json --max-cost-usd <usd>
   bash plugins/review/evals/revert-cases.sh report result.json
   ```

   Check the run with the evals plugin's `run-validity.py`, passing `--scaffolded`, before
   reading the total. A run with an
   error or skipped judge calls is not comparable and is left out of the total. Below 5
   comparable cases, the total is marked indicative only. Run it on the base and on a change to a
   review lane's prompt, model or effort, and compare the two totals. No CI job runs these cases,
   and no required check depends on them.

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

Each setting is set per user through the option below or per repository in
`docs/conventions/review.yaml` (written by `/review:setup apply`). `downstream_probe` decides whether `/review:quality-gate downstream` runs the one probe it writes
for its safety fact (`run`) or only states it (`report`). It is a policy floor: `report` in either
layer wins, and the repository value is read from the default branch. `fanout_diversity` decides
whether `/review:fanout run-everything` runs one reviewer agent per concern (`lens`, the default)
or sends one review prompt to each model tier the role map names (`model`), or runs the lens roster
with the Codex reviewer as its model-diversity panel (`codex`). `fanout_act_on_cap` decides how
many rows under each `### Spec` and `### Standards` heading of a `/review:fanout` report are marked
act on (default `2`); every other row stays in the report. `smell_baseline` decides which
design-smell list the `code-reviewer` agent checks: the shipped baseline (`default`), none (`off`),
or a path to the repository's own list, which `/review:setup apply` can write from the catalog in
[`reference/design-smells.md`](reference/design-smells.md). The `council_*` keys configure
`/review:council`: its member catalog, fallback panel, selection rules, round count, score table and
the repository-only lane switch, read from the base branch when a change edits the file. Keys,
values and resolution:
[`reference/config.md`](reference/config.md).

<!-- BEGIN GENERATED: plugin options. Edit plugin.json, then run scripts/sync-plugin-options-docs.py -->

### Options reference

Generated from this plugin's `.claude-plugin/plugin.json`. For how Claude Code asks for
these and hands them to the plugin, see [User configuration](https://code.claude.com/docs/en/plugins/manifest-reference#user-configuration).

| Option | Type | Default | Description |
| --- | --- | --- | --- |
| `connected_page_guard_enabled` | boolean | `true` | Runs the PreToolUse hook that denies an Artifact publish of an HTML page whose content security policy names a loopback connect-src. On by default. Turn off to allow publishing such a page. |
| `downstream_probe` | string | `"run"` | run (default): /review:quality-gate downstream mode writes one probe for its safety fact in a temp directory outside the tree and runs it. report: it shows the probe without running it. report here or in a repository's docs/conventions/review.yaml (default branch) wins over run. |
| `fanout_diversity` | string | `"lens"` | lens (default): /review:fanout run-everything runs one reviewer agent per concern. model: one review prompt per fan-out model tier. codex: the lens roster plus the Codex reviewer as the model panel. A repository's docs/conventions/review.yaml fanout_diversity wins over this option. |
| `fanout_act_on_cap` | number<br>*min 1* | `2` | How many rows under each By axis heading (Spec, Standards) of a /review:fanout report are marked act on; default 2, a whole number of at least 1. The other rows stay in the report, marked no. A repository's docs/conventions/review.yaml fanout_act_on_cap wins over this option. |
| `smell_baseline` | string | `"default"` | default (default): the code-reviewer agent checks the shipped design-smell baseline. off: no smell check. A repository-relative .md path: that list, or the shipped one when the file is missing or the reviewed change edits it. A repository's docs/conventions/review.yaml smell_baseline wins over this option. |
| `council_max_rounds` | number<br>*min 1* | `1` | How many review rounds /review:council runs at most; default 1, a whole number of at least 1. Above 1, /review:fanout fix runs between rounds. A repository's docs/conventions/review.yaml council_max_rounds wins over this option. |
| `council_scores` | string | `"off"` | on: the /review:council report carries a mark table by member and round; off (default): none. A repository's docs/conventions/review.yaml council_scores wins over this option. |
| `council_members` | string | *(none)* | Your /review:council member catalog as JSON, the shape of council_members in docs/conventions/review.yaml, e.g. {"codex-adv":{"provider":"codex","brief":"adversarial"}}. Empty (default): the repository's value or three Opus members. The repository's value wins; invalid JSON is reported and ignored. |
| `council_panel` | string | *(none)* | Your /review:council fallback panel as a JSON list of member ids. Empty (default): the repository's value or every catalog member. A repository's value wins; invalid JSON is reported and ignored. |
| `council_rules` | string | *(none)* | Your /review:council selection rules as a JSON list, the same shape as council_rules in docs/conventions/review.yaml. Empty (default): the repository's rules or none. A repository's value wins; invalid JSON is reported and ignored. |
| `medium` | string | `"auto"` | Where /review:explain-change sends a digest page. auto (default): the shipped artifact default, which the publish gate keeps local for a non-public repository or a credential-shaped diff; terminal: no page; file: a local file; artifact: publish anyway; hosted: the shared page host. |

### How to set these

Set the options above for `review@<marketplace>`, replacing `<marketplace>` with the
marketplace you installed this plugin from:

- **In a session or headless:** [`/plugin` in a session](https://code.claude.com/docs/en/plugins/cli-reference#plugin-in-a-session) or
  [`claude plugin configure`](https://code.claude.com/docs/en/plugins/cli-reference#plugin-configure). The configure command is the preferred
  headless route in the [plugin-reconfiguration convention](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/contracts/plugin-reconfiguration/README.md), which records its limits.
- **By hand:** under [`pluginConfigs`](https://code.claude.com/docs/en/settings-reference#pluginconfigs) in your **user** settings.

Do **not** uninstall the plugin to reconfigure it: see [What an uninstall deletes and keeps](https://code.claude.com/docs/en/plugins/cli-reference#what-an-uninstall-deletes-and-keeps).
For a Claude Code release without `plugin configure`, see [Plugin install](https://code.claude.com/docs/en/plugins/cli-reference#plugin-install).

### Upstream documentation

- [User configuration](https://code.claude.com/docs/en/plugins/manifest-reference#user-configuration)
- [Plugin configure](https://code.claude.com/docs/en/plugins/cli-reference#plugin-configure)
- [Plugin install options](https://code.claude.com/docs/en/plugins/cli-reference#plugin-install)
- [Plugins and skills settings](https://code.claude.com/docs/en/settings-reference#plugins-and-skills)
- [Settings files and who they affect](https://code.claude.com/docs/en/settings#settings-files-and-who-they-affect)
- [Manage installed plugins](https://code.claude.com/docs/en/plugins/install#manage-installed-plugins)

<!-- END GENERATED: plugin options -->

## License

MIT (SPDX-License-Identifier: MIT).
