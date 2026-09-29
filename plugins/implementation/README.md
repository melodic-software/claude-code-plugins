# implementation

A Claude Code plugin for the **implementation stage** of a disciplined dev
workflow: execute an approved plan with incremental validation, inline or via
orchestrated worker subagents, abandoning a broken approach early instead of
pushing it to PR review. Two user-invocable skills and an internal return-contract skill, one
concern: turning approved plans into verified code.

| Skill | What it does |
|---|---|
| `/implementation:implement` | Inline execution discipline. Mode detection (feature/fix/refactor/config), TDD-by-default cadence, build+test after each logical block, green-checkpoint commits, divergence detection routing back to planning, scope-fence drift detection, phase-boundary handoffs. |
| `/implementation:implement-dispatch` | Orchestrated execution variant. Composes scope-fenced worker briefs, dispatches subagents, verifies returns against direct evidence, builds main-side, and handles divergence in autonomous runs via a conservative-option deviations log. |

Two plugin agents are the dispatch surface `implement-dispatch` routes through; their `model`
frontmatter structurally binds the capability tier, so workers never silently inherit a fast
orchestrator root's model:

| Agent | What it does |
|---|---|
| `implementation:implementer` | Scope-fenced worker dispatched per phase; executes exactly one brief in its assigned or self-provisioned worktree, leaving staging, committing, and pushing to the orchestrator when the brief declares commit authority `orchestrator`. Frontmatter binds the strong tier's current alias. |
| `implementation:phase-verifier` | Fresh-context acceptance verifier dispatched at phase boundaries with the orchestrator's rationale withheld; its tool cage bars Edit/Write and agent spawning (Bash and PowerShell remain for inspection; to narrow Bash, see Narrowing the phase-verifier's Bash), and it is bound never weaker than the implementer it checks. |

## Companion stages (separate plugins)

Build/test/lint, testing, and outcome verification were split out of this plugin into
three companion plugins. This plugin invokes them when installed and degrades
gracefully when absent, no hard dependencies:

- **`toolchain`**. `/toolchain:check` runs after each logical block and at completion;
  when the plugin is absent this skill runs the project's own build/test command.
- **`testing`**. `/testing:plan`, `/testing:write`, `/testing:diagnose` for coverage,
  authoring, and failure diagnosis.
- **`verification`**. `/verification:confirm` for outcome verification at the pre-PR
  handoff; when absent, self-verify the outcome against the plan/intent directly.

## Works in any repo

- **Document placement, via the topic-docs seam.** Plan progress marks, the
  autonomous-run `DEVIATIONS.md` log, status summaries, and handoff notes land per the
  marketplace-wide topic-docs convention (`docs/conventions/topic-docs/README.md`;
  plugin binding: `reference/topic-docs.md`): contract documents in
  `<contract_dir>/<slug>/` (default `docs/topics/`), committed on the task branch and
  pruned before merge; working memory in the self-ignoring `<memory_dir>/` (default
  `.work/`). The tracked `.claude/topic-docs.yaml` concern file is the consumer-side
  source of truth, each lifecycle plugin's own setup (`/discovery:setup`,
  `/planning:setup`, `/verification:setup`) offers to write it.
- **Reads your conventions, assumes none.** Testing structure, commit conventions,
  branch policy, and project invariants come from your own `CLAUDE.md` and rules.
- **Cross-plugin refs degrade gracefully.** Companion plugins (`toolchain`, `testing`,
  `verification`, `tdd`, `planning`, `discovery`, `session-flow`, `source-control`) and
  external marketplace skills are invoked when installed and substituted with inline
  guidance when absent; no step blocks on a missing plugin.
- **Self-contained.** All execution-mode context and the topic-docs binding ship inside
  the plugin and are referenced via `${CLAUDE_PLUGIN_ROOT}`; state and artifacts go to
  your project's own tree per the topic-docs convention above.

## Install

```shell
/plugin marketplace add melodic-software/claude-code-plugins
/plugin install implementation@melodic-software
```

## Migrating from an earlier `implementation`

If you had `implementation` installed before the `0.6.0` split, `build`, `lint`, `setup`,
`test-plan`, `test-write`, `test-e2e`, `test-diagnose`, `verify-changes`, and `verify-improvement`
no longer live here. Those nine skills moved into the new `toolchain`, `testing`, and `verification`
plugins. `implementation` keeps its name, so the marketplace's `renames` map (which migrates a
renamed or removed plugin automatically) does not apply. Install the plugins you relied on:

```shell
/plugin install toolchain@melodic-software      # check (was build), lint, setup
/plugin install testing@melodic-software        # test-plan, test-write, test-e2e, test-diagnose
/plugin install verification@melodic-software   # verify-changes, verify-improvement
```

`/implementation:implement` and `/implementation:implement-dispatch` still run without them.
Build/test falls back to the project's own command and outcome verification falls back to
self-verification, but installing the companion plugins restores the full former surface.

## Configuration

Artifact placement is governed by the tracked `.claude/topic-docs.yaml` concern file
(see the topic-docs seam above); each lifecycle plugin's own setup (`/discovery:setup`,
`/planning:setup`, `/verification:setup`) interviews for and persists it.

`implement_dispatch_wave_cap` sets how many worker rows of one plan phase
`/implementation:implement-dispatch` runs at once. Unset, the skill keeps its internal 3–5
wave default. The cap bounds all worker rows in flight in a phase, whichever worktrees they use. Rows that
share a worktree under the default worker authority are further serialized to one at a time,
whatever the cap allows. A `--wave-cap` argument from a chaining caller, such as `/work-items:work`
threading its own `work_dispatch_concurrency_cap`, takes precedence for that invocation. The
Options reference lists the key.

Testing cadence is project policy. TDD remains the fallback when the consuming project's
`CLAUDE.md` or rules do not declare another cadence. To opt out, add an explicit project
instruction, for example:

```markdown
## Testing

Use tests-after for implementation work; do not use test-first TDD.
```

`/implementation:implement` follows that project instruction in every execution mode.

### Narrowing the phase-verifier's Bash

`implementation:phase-verifier` keeps `Bash` for diffs, greps, and read-only checks, so its
read-only contract is enforced by its prompt, not by its tool list. The only instrument that keeps
`Bash` while blocking specific commands is a Bash deny rule in `permissions.deny`. A
`disallowedTools` entry with a specifier removes the whole tool, and a plugin agent's own `hooks`
and `permissionMode` frontmatter are ignored. A deny rule applies to the whole session, the main
conversation and every subagent, so deny only commands no one in the session should run. For
example, in the project's `.claude/settings.json`:

```json
{
  "permissions": {
    "deny": ["Bash(git push *)", "Bash(git reset --hard *)"]
  }
}
```

A Bash rule matches the command text, not the program: `Bash(git push *)` does not stop
`git -C . push`, and `Bash(rm *)` does not stop `bash -c 'rm ...'`. Treat it as a guard against
the usual invocation, not a security boundary; use sandboxing for enforcement that does not depend
on command text.

The verifier also holds `PowerShell`, which a Bash rule does not cover. Deny the same commands as
`PowerShell(...)` rules (for example `"PowerShell(git push *)"`) where the PowerShell tool is
available.

Basis: the Claude Code sub-agents page ("Control subagent capabilities": `disallowedTools`
specifiers and Bash deny rules; "Choose the subagent scope": fields ignored for plugin
subagents) and the permissions page ("What a Bash rule doesn't match"), at
<https://code.claude.com/docs/en/sub-agents> and
<https://code.claude.com/docs/en/permissions>, verified 2026-09-27. Recheck when a release note
touches subagent tool restrictions or Bash permission-rule matching.

<!-- BEGIN GENERATED: plugin options. Edit plugin.json, then run scripts/sync-plugin-options-docs.py -->

### Options reference

Generated from this plugin's `.claude-plugin/plugin.json`. Every option Claude Code
will prompt for when the plugin is enabled, with the environment variable each hook
reads it from.

| Option | Type | Default | Environment variable | Description |
| --- | --- | --- | --- | --- |
| `implement_dispatch_wave_cap` | number<br>*min 1* | *(none)* | `CLAUDE_PLUGIN_OPTION_IMPLEMENT_DISPATCH_WAVE_CAP` | Maximum worker rows /implementation:implement-dispatch runs at once within one plan phase, the size of one dispatch wave. Give a whole number of rows; a fractional value is floored since a row is discrete. The cap bounds all worker rows in flight in a phase, whichever worktrees they use. Rows that share a worktree under the default worker authority are further serialized to one at a time, whatever the cap allows. A --wave-cap argument from a chaining caller (for example /work-items:work threading its work_dispatch_concurrency_cap) takes precedence for that invocation. Leave unset to keep the internal 3-5 wave default. This key declares no default, so an unset value stays distinguishable from a configured one. |

### How to set these

Three supported routes, in the order most people want them:

1. **Interactively.** Claude Code prompts for declared options when you enable the
   plugin. To change them later: `/plugin configure implementation@<marketplace>`.
2. **Headless.** Repeat `--config` for each option. Replace
   `<marketplace>` with the marketplace you installed this plugin from:

   ```shell
   claude plugin install implementation@<marketplace> -s <scope> --config implement_dispatch_wave_cap=<value>
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
       "implementation@<marketplace>": {
         "options": {
           "implement_dispatch_wave_cap": <value>
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

- [User configuration](https://code.claude.com/docs/en/plugins-reference#user-configuration): the `userConfig` schema and the `CLAUDE_PLUGIN_OPTION_<KEY>` export
- [Plugin install options](https://code.claude.com/docs/en/plugins-reference#plugin-install): the `--config` flag's reference entry
- [Plugins and skills settings](https://code.claude.com/docs/en/settings-reference#plugins-and-skills): `enabledPlugins`, `extraKnownMarketplaces`, `pluginConfigs`
- [Settings files and who they affect](https://code.claude.com/docs/en/settings#settings-files-and-who-they-affect): user vs project vs local precedence
- [Manage installed plugins](https://code.claude.com/docs/en/discover-plugins#manage-installed-plugins): enabling, disabling, `/plugin list`

<!-- END GENERATED: plugin options -->

## License

MIT (SPDX-License-Identifier: MIT).
