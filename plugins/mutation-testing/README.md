# mutation-testing

A Claude Code plugin for the **test stage** of a disciplined dev workflow. It measures whether a test
suite can actually *detect* faults, not merely *execute* code. The three skills share one concern,
proving the tests check something.

| Skill | What it does |
|---|---|
| `/mutation-testing:principles` | Knowledge router. Mutant states, operator catalogs, mutation score vs covered-code score vs test strength vs MSI, the oracle gap, equivalent mutants, arid nodes, and why not to gate on the score. Five reference spokes load on demand; a quick decision guide answers the common questions with no file load. |
| `/mutation-testing:setup` | Verify and configure. Detect the ecosystem, confirm the mutation tool is installed and drives the project's test runner, measure the baseline suite, settle the diff target and operator set, write the tracked config and an empty arid-node suppression record. `check` inspects read-only; `apply` interviews and writes. |
| `/mutation-testing:audit` | Mutation analysis, read-only with respect to tracked source. By default it is diff-scoped: at most one mutant per changed line, executed against the cached covering tests, always reverted. `--exercised [<test-path>]` instead mutates the production code the changed tests call and runs each mutant against those tests only, so it judges the new tests rather than the suite; it needs the `testing` plugin to recognize test files and, under the manual protocol, the config's `test-command`. Survivor triage is delegated to a fresh-context reviewer, which also says why each productive survivor lived (`no-assertion` or `input-gap`); the report ranks files by oracle gap and hands survivors to the test-authoring lane. `--persist-findings` additionally writes the survivors into the memory tier as a findings file the `review:fanout` `fix` action consumes. Before that write, it proves the destination is outside tracked space, either by probing the checkout that governs the destination or by establishing from two independent signals that no checkout does. `--record-mutants <file>` records the mutants an exercised run applied; `--replay-mutants <file>` applies exactly those mutants after the tests change and reports `Gate: block` when a kill was lost (`/testing:cleanup` uses the pair). |

## Why this exists

Coverage tells you a line **executed**. It cannot tell you the line was **checked**. A file at 95%
coverage and 40% covered-code mutation score has tests that run the code and assert almost nothing
about it, and a coverage report will call that file healthy.

## Works in any repo

- **Reads your conventions, assumes none.** Ecosystem, test runner, source roots, and diff target
  come from your own project. Detected from what exists, confirmed with you at setup, then recorded
  in a tracked config file so runs are deterministic.
- **Cross-plugin refs degrade gracefully.** Test authoring defers to `/testing:write` when the
  `testing` plugin is installed and hands the survivor list back otherwise; failing-suite diagnosis
  routes to `/testing:diagnose` when installed and to the project's own test command otherwise;
  test-design questions route to `/tdd:principles` when installed and to the project's own guidance
  otherwise. No step blocks on a missing plugin.
- **Self-contained.** Operator catalogs, metric formulas, the scaling protocol, and the manual
  fallback for languages with no tool ship inside the plugin and are referenced via
  `${CLAUDE_PLUGIN_ROOT}`.

## What it deliberately does not do

- **No score gate.** The config has no threshold field. A mutation score has a permanent, unknowable
  ceiling below 100% because equivalent mutants cannot all be removed, and every point is
  purchasable by suppressing a mutant, so a gate selects for suppression over testing. Report the
  number; rank by the gap; let the surviving mutants be the finding.
- **No whole-repo nightly ratchet.** Diff-scoped, at most one mutant per changed line. The
  un-scoped, un-suppressed, gated shape is the one that kept this technique unused for three
  decades.
- **No test authoring.** `audit` never both creates a gap and closes it.
- **No mutation left behind.** Every mutant is reverted on every exit path; a run that cannot restore
  the tree reports that as its headline finding.

## Install

```shell
/plugin marketplace add melodic-software/claude-code-plugins
/plugin install mutation-testing@melodic-software
```

## Configuration

`/mutation-testing:setup apply` writes two tracked files in the consuming repo:

- `.claude/mutation-testing.md`. Tool, invocation command, diff target, mutate globs, operator set,
  timeout, measured baseline suite time, optional mutant cap, and an optional `test-command` whose
  `{tests}` placeholder `audit --exercised` fills with the test paths (for `dotnet test`, with one
  test project and a class filter per run).
- `.claude/mutation-testing-arid.md`, the arid-node suppression record, shaped by the marketplace's
  finding-suppression convention: a mapping keyed by a derived `finding_id`, every entry carrying all
  five required keys (`check`, `claim`, `sites`, `reason`, `date`) with the id derived from its own
  constituents. An entry missing any of them is malformed and does not suppress.

They are kept separate deliberately: a config diff reads as a policy change, a suppression diff reads
as an accepted finding. **Their layering also differs.** The config layers per the config-cascade
convention (the user layer in `userConfig` → team → `.local.md` overlay, later wins). The
suppression record sits in the cascade's policy-floor precedence-inversion class: on a conflict
the **team** layer wins, and a personal-layer entry for an id the team layer does not carry **does
not suppress at all**. It is reported `personal-only, not applied`. A personal layer is a draft
surface there, so one developer cannot hide a finding the team never accepted.

The user layer is this plugin's `userConfig`, not a file: two options that mean the same thing in
every repository, the operator set and a mutant cap. A repository's team or local file overrides
them. `/mutation-testing:setup apply user` settles them and names the route below for saving them;
it writes nothing itself. `apply local` writes the untracked `.local.md` overlay instead of the team
file.

<!-- BEGIN GENERATED: plugin options. Edit plugin.json, then run scripts/sync-plugin-options-docs.py -->

### Options reference

Generated from this plugin's `.claude-plugin/plugin.json`. Every option Claude Code
will prompt for when the plugin is enabled, with the environment variable each hook
reads it from.

| Option | Type | Default | Environment variable | Description |
| --- | --- | --- | --- | --- |
| `operators` | string | *(none)* | `CLAUDE_PLUGIN_OPTION_OPERATORS` | Your operator set for every repository: default (the tool's own defaults) or narrow (statement-block removal plus relational-operator replacement, for a cheaper run). A repository's mutation-testing config overrides it. Unset by default. |
| `max_mutants` | number<br>*min 1* | *(none)* | `CLAUDE_PLUGIN_OPTION_MAX_MUTANTS` | Your cap on how many mutants one audit run generates, in every repository. A repository's mutation-testing config overrides it, and the audit's --max flag overrides both. Unset by default, so the effort cap applies. |

### How to set these

Three supported routes:

1. **Interactively.** Open this plugin's options dialog ([`/plugin` in a session](https://code.claude.com/docs/en/plugins/cli-reference#plugin-in-a-session)):
   `/plugin configure mutation-testing@<marketplace>`.
2. **Headless.** Save the values with [`claude plugin configure`](https://code.claude.com/docs/en/plugins/cli-reference#plugin-configure),
   run from the project the plugin is installed in. Replace
   `<marketplace>` with the marketplace you installed this plugin from:

   ```shell
   claude plugin configure mutation-testing@<marketplace> --values-stdin < values.json
   ```

   `values.json` holds a JSON object of strings, booleans included:

   ```json
   {"operators": "<value>"}
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
   claude plugin install mutation-testing@<marketplace> -s <scope> --config operators=<value>
   ```

3. **By hand, in settings.** Add the value under `pluginConfigs` in your **user**
   settings (`~/.claude/settings.json`):

   ```json
   {
     "pluginConfigs": {
       "mutation-testing@<marketplace>": {
         "options": {
           "operators": <value>
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

## Sources

The reference material is distilled from primary sources, fetched 2026-08-10:

- [Stryker. Mutant states and metrics](https://stryker-mutator.io/docs/mutation-testing-elements/mutant-states-and-metrics/),
  [Stryker.NET configuration](https://stryker-mutator.io/docs/stryker-net/configuration/),
  [StrykerJS incremental](https://stryker-mutator.io/docs/stryker-js/incremental/)
- [PIT](https://pitest.org/) and its [mutation operators](https://pitest.org/quickstart/mutators/)
- [Infection. MSI](https://infection.github.io/guide/)
- Petrović & Ivanković, *State of Mutation Testing at Google*, ICSE-SEIP 2018
  (<https://dl.acm.org/doi/10.1145/3183519.3183521>)
- Petrović, Ivanković, Fraser & Just, *Practical Mutation Testing at Scale*
  (<https://arxiv.org/abs/2102.11378>)
- Jia & Harman, *An Analysis and Survey of the Development of Mutation Testing*, IEEE TSE 37(5), 2011
  (<https://dl.acm.org/doi/10.1109/TSE.2010.62>)
- Ojdanic et al., *Mind the Gap: The Difference Between Coverage and Mutation Score Can Guide Testing
  Efforts* (<https://arxiv.org/abs/2309.02395>)
- DeMillo, Lipton & Sayward, *Hints on Test Data Selection*, IEEE Computer, 1978

## License

MIT (SPDX-License-Identifier: MIT).
