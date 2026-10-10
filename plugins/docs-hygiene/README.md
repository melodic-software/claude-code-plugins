# docs-hygiene

A Claude Code plugin bundling documentation-hygiene skills. One cohesive
capability: keeping a repository's tracked markdown lean, deduplicated, and
free of decayed references. Each skill is invocable on its own; together they
cover the flavor, noise, duplication, boundary, rename, worth, loading,
and authoring axes of doc upkeep.

The plugin contract (five concerns, five boundaries) is ratified and lives in
[`reference/plugin-contract.md`](reference/plugin-contract.md). Naming the files of a
tree against a casing rule is the separate `docs-naming` plugin; `rename-references`
here sweeps the references after a rename someone already made.

## The skills

| Skill | What it does |
|---|---|
| `/docs-hygiene:compress` | Tightens markdown by dropping flavor (filler, hedging, and articles only when `compress_articles` is `cut`) while preserving all content, behind a mandatory fresh-context semantic-diff audit that reverts any semantic loss. Supports an optional `caveman` plugin backend (`/caveman:compress`) with a built-in in-session fallback. |
| `/docs-hygiene:audit-noise` | Read-only classifier for nine markdown noise shapes (historical citations, ghost refs to ephemeral working directories, "why this file exists" preambles, hard-coupled consumer lists, scope/loading meta-commentary, plan/changeset references, conversational antecedents, tracker/PR back-references, prohibitions with no positive alternative) with tiered findings and per-shape treatment guidance. `--persist-findings` routes the negation findings to the `review:fanout` fix relay. |
| `/docs-hygiene:extract-ssot` | Deduplicates repeated content into a single named source of truth and migrates call sites to cite it by heading. Reports duplication at every multiplicity in three labeled buckets: a lone recap of an existing SSOT, a drifting pair with no declared owner, and a cluster that meets the Rule of Three. Refuse-fast verification gates reserve *creating* a new artifact for three or more instances; below that the skill offers only non-abstracting remedies. |
| `/docs-hygiene:audit-encapsulation` | Detects external citations reaching into skill-private surfaces inside `.claude/skills/<name>/` (private subdirectories, heading anchors, schema files) and routes each violation to a remediation path. Ships its own public-surface contract reference. |
| `/docs-hygiene:rename-references` | Sweeps stale references after renames, the forms plain token grep misses: slash-command tokens, relative paths from moved files, frontmatter chains and globs, via a 12-form pattern library with audit, half-rename detection, and apply modes. |
| `/docs-hygiene:audit-derivability` | Read-only, document-level worth classifier: could a fresh agent re-derive this whole document from the code, config, and structure? Weighs derivability, re-derivation cost, drift risk, and fact ownership into a verdict (delete, convert-to-pointer, keep-as-derivation-cache, keep-owns-facts), splits it by audience, and confirms load-bearing deletions with a fresh-context spot-test. Where the other five trim *inside* a doc, this decides whether the doc should exist. |
| `/docs-hygiene:audit-progressive-disclosure` | Read-only progressive-disclosure classifier: grades agent-facing instruction markdown against a three-tier load-cost model (always-loaded / invocation-loaded / on-demand) and emits seven finding shapes in two lanes. Split opportunities (oversize, mixed-concerns, tier-mismatch) and hub/spoke structure defects (blind-pointer, orphan-spoke, deep-nesting, missing-toc), with tiered treatment guidance. Thresholds are advisory settings of ours, each pointing at the Anthropic guidance it follows from the skill's own records; a deterministic `detect.sh` emits the facts, the judgment layer adjudicates. |
| `/docs-hygiene:write-for-agents` | The write-side complement to the audit skills: authoring-time doctrine that fires while agent-consumed markdown is being written (CLAUDE.md/AGENTS.md content, rules files, agent-loaded reference docs, pointer lines, doc-plus-pointer extractions). Two-loads budgeting, branch-covering pointers, steps-vs-reference separation, observable completion criteria, split-by-sequence, positive-form prompting, which surfaces are system prompt, with a verified auto-read surface reference and a trigger-reliability eval suite. |
| `/docs-hygiene:setup` | Check-only setup for the plugin's one external prerequisite: resolves `markdownlint-cli2` from `PATH` or the repository's `node_modules/.bin`, runs it with `--version`, and reports the install remediation when it is missing or broken. Installs nothing and writes nothing. |
| `/docs-hygiene:write-for-humans` | The other half of the write-side pair: authoring-time doctrine for prose a **person** reads. End-user READMEs, RFCs, design docs, release notes, tutorials, how-to guides, reference pages, explanations. Resolves the consuming project's own declared style guide first and reaches for a bundled default set only as the fallback: Diátaxis document modes, Google developer style, ASD-STE100 instruction rules, and Global English disambiguation. The plugin therefore never silently imposes a house style. Ships the mode picker, a rhythm section against machine-cadence prose, one sentence-rules spoke, links-only source records, and after-writing checks that run the project's prose linter and `/ai-slop:audit`. |

## Requirements

- **Bash + git**. Ambient skill mechanics (Git Bash on native Windows;
  the skills' scripts strip CRLF and avoid Windows-hostile constructs).
- **`markdownlint-cli2`**. **Required by `/docs-hygiene:compress`**, whose
  post-edit lint pass is the mandatory ship gate. It must be on `PATH` or
  installed in the consuming repo (`node_modules/.bin/markdownlint-cli2`);
  when absent, `compress` stops at the entry point with that remediation
  instead of shipping unverified output. `compress` is the only skill that gates
  its entry point on it; `extract-ssot` names it as one option for its ship-gate
  lint step, and no other skill calls it. `/docs-hygiene:setup` checks it.
- **`caveman` plugin** (optional), a compression backend for `compress`,
  detected with `claude` and `jq` when both are on `PATH`; absent, an in-session
  fallback applies and every verification gate still runs.

## Install

```shell
/plugin marketplace add melodic-software/claude-code-plugins
/plugin install docs-hygiene@melodic-software
```

## How the skills adapt to your repo

Bare invocations with no target share a confirmation-gated clean-tree /
no-scope fallback (`context/clean-tree-fallback.md`): offer a corpus run with
prescribed defaults, never auto-start, and no-op on decline or silence.

<!-- markdown-discipline-ignore -->
The bundled defaults are repo-agnostic: detectors run against the repository
they are invoked in, output destinations default to conventional locations
(e.g. `.claude/rules/<topic>.md` for an extracted rule), and ephemeral-path
detection covers memory slices under `.work/<slug>/` and the retired `.claude/notes/`. Refine any of these through
your own repository's `CLAUDE.md` / `.claude/rules`, the skills read the
consuming project's context; nothing requires editing the plugin.

## Configuration

| Setting | Type | Default | What it does |
| --- | --- | --- | --- |
| `compress_articles` | string | `keep` | Whether `compress` removes `a`, `an` and `the`. `keep` leaves them and runs the in-session Edit backend with word-level cuts only; `cut` allows removing them and uses the `caveman` backend when it is installed. A repository can set it for everyone in `docs/conventions/docs-hygiene.yaml`, which wins; keys and layers: [`reference/config.md`](reference/config.md). |

`/docs-hygiene:setup` reports the effective `compress_articles`, and `/docs-hygiene:setup apply`
writes the repository's `docs/conventions/docs-hygiene.yaml`. The detector and fact-emitter
scripts are read-only and make no network call; `compress` persists optional snapshots under the
plugin's own data directory.

<!-- BEGIN GENERATED: plugin options. Edit plugin.json, then run scripts/sync-plugin-options-docs.py -->

### Options reference

Generated from this plugin's `.claude-plugin/plugin.json`. Every option Claude Code
will prompt for when the plugin is enabled, with the environment variable each hook
reads it from.

| Option | Type | Default | Environment variable | Description |
| --- | --- | --- | --- | --- |
| `compress_articles` | string | `"keep"` | `CLAUDE_PLUGIN_OPTION_COMPRESS_ARTICLES` | Whether /docs-hygiene:compress removes a, an and the. keep (default): articles stay, and compression runs on the in-session Edit backend with word-level cuts only. cut: articles may be removed, and the caveman backend runs when installed. docs/conventions/docs-hygiene.yaml overrides this. |

### How to set these

Three supported routes, in the order most people want them:

1. **Interactively.** Claude Code prompts for declared options when you enable the
   plugin. To change them later: `/plugin configure docs-hygiene@<marketplace>`.
2. **Headless.** Repeat `--config` for each option. Replace
   `<marketplace>` with the marketplace you installed this plugin from:

   ```shell
   claude plugin install docs-hygiene@<marketplace> -s <scope> --config compress_articles=<value>
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
       "docs-hygiene@<marketplace>": {
         "options": {
           "compress_articles": <value>
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
- [Manage installed plugins](https://code.claude.com/docs/en/plugins/install#manage-installed-plugins): enabling, disabling, `/plugin list`

<!-- END GENERATED: plugin options -->

## License

MIT (SPDX-License-Identifier: MIT).
