# debugging

A Claude Code plugin that debugs **observed failures** via a disciplined
six-phase loop. Observed failures include a wrong UI, a bad log line, a
performance regression, a screenshot of a bug, or a production symptom.
It is the discipline that separates a fixed
bug from a lucky one: no phase proceeds without a fast, deterministic,
agent-runnable pass/fail signal.

Invoke it with `/debugging:debug <bug description>`, or let Claude reach for it
when you describe broken behavior with no pre-existing reproduction.

## Skills

| Skill | Use it for |
|---|---|
| `/debugging:debug` | A failure you can see: reproduce it with a loop, rank and probe the causes, then fix it with a regression test and clean up. |
| `/debugging:analyze-profile` | A CPU profile, heap snapshot or performance trace: read it down to a file:line cause with no fix (record one with `/app-control:drive capture`). Needs Python 3.10 or later. |

## The six phases

1. **Build the reproduction loop**, where most of the effort goes. One quick command
   that gives the same pass or fail for this bug on every run. Ten kinds of loop,
   ranked from a failing test down to a script a person runs by hand.
2. **Reproduce**. Run the loop; confirm it shows *the* failure the user described,
   then minimize the reproduction.
3. **Hypothesize**. Rank three to five candidate causes, each with a prediction a
   test could disprove, before the first test runs.
4. **Instrument**. Each probe checks one prediction and changes one thing; each
   temporary log line carries the session marker that Phase 6 searches for.
   Slowdowns are measured against a baseline instead.
5. **Fix + regression test**. The test comes first, at a *correct seam*; when no such seam
   exists, the missing seam is reported as the finding.
6. **Cleanup + post-mortem**. Remove instrumentation, verify the original repro is
   gone, and capture what would have prevented the bug.

## Works in any repo

- **Self-contained.** The methodology, the per-ecosystem debugging reference, the
  phase checklist, and the human-in-the-loop script template all ship inside the
  plugin and are referenced via `${CLAUDE_PLUGIN_ROOT}`.
- **Graceful degrade.** Where a phase mentions an adjacent capability, such as a
  test-investigation routine, a TDD helper, a headless-browser driver, an
  architecture-audit agent, an issue tracker, or an outcome verifier, it is treated as
  **optional**: if your environment provides it, the skill uses it; otherwise it
  proceeds with self-contained inline guidance. No phase blocks on a missing tool.
- **Reads your conventions, assumes none.** Test naming, module layout, banned APIs,
  and where working notes live come from your own project's `CLAUDE.md`, its
  `.claude/rules/` project rules, and tool config.

## Install

```shell
/plugin marketplace add melodic-software/claude-code-plugins
/plugin install debugging@melodic-software
```

## Configuration

One plugin option, `medium`, sets where the post-mortem view goes; the shared medium
resolver reads it beside the repository's `rendered-views` files (options reference below).
The option declares a fixed list of values, which needs Claude Code v2.1.271 or later.
The phase checklist is a bundled template you copy into your own working-notes location
(or track inline). The only plugin data written is the resolver's record of which
retired-file notices it has already shown for a project.

A repository can commit `debugging.yaml` in its convention home (default `docs/conventions`)
to set these keys, checked against [`schemas/debugging.schema.json`](schemas/debugging.schema.json):

| Key | Values | Default | What it controls |
|---|---|---|---|
| `always_on_signal` | `when-instrumented`, `always`, `never` | `when-instrumented` | When `/debugging:debug` Phase 6 proposes one cheap, always-on signal that would have shown the deciding fact at first look: only after Phase 4 instrumentation ran, on every run, or never. |
| `verification`, `verification_skills.<skill>` | `off`, `light`, `standard`, `strict` | `light` | Whether `/debugging:debug` dispatches its fresh-context outcome verifier: `light` and `off` skip it and record the outcome unverified. Read from the default branch only, through `lib/read-verification.sh`; a skill entry beats the plugin value ([verification level](../../docs/contracts/verification-level/README.md)). |

<!-- BEGIN GENERATED: plugin options. Edit plugin.json, then run scripts/sync-plugin-options-docs.py -->

### Options reference

Generated from this plugin's `.claude-plugin/plugin.json`. For how Claude Code asks for
these and hands them to the plugin, see [User configuration](https://code.claude.com/docs/en/plugins/manifest-reference#user-configuration).

| Option | Type | Default | Description |
| --- | --- | --- | --- |
| `medium` | string | `"auto"` | Where the post-mortem view goes. auto (default): a local file; terminal: no page; file: a local file; artifact: a private Artifact; hosted is read as artifact. A team rendered-views file never publishes. |

### How to set these

Set the options above for `debugging@<marketplace>`, replacing `<marketplace>` with the
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
