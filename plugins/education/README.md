# education

A Claude Code plugin that coaches you through learning a subject — across
multiple sessions — instead of lecturing at you. It runs a
**Knowledge → Skills → Wisdom** progression grounded in your real goal, and keeps
persistent per-topic learning state so each session builds on the last.

Invoke `/education:teach` with an action for coached, multi-session learning, for
example `/education:teach topic rust-ownership`,
`/education:teach codebase auth-flow`, or `/education:teach primer color-grading`.
For a one-shot plain-language explanation, invoke `/education:explain` — or just
say "I don't get it" and let it auto-invoke. After Claude finishes a change,
invoke `/education:quiz-me` to be quizzed on what was done.

## What it does

`teach` is the multi-session coach; `explain` is its one-shot sibling; `quiz-me`
verifies you absorbed a completed change.

- **`/education:teach topic <subject>`** — learn a general subject from external
  high-trust sources (books, courses, docs, communities).
- **`/education:teach codebase <topic>`** — learn a concept grounded in the
  repository you launch it from. It discovers the repo's own docs, conventions,
  and source at teach-time and teaches from what it finds — nothing about the
  project is assumed.
- **`/education:teach primer <domain>`** — a single-session vocabulary primer for
  an unfamiliar domain, so you can prompt or direct work in it precisely. No
  workspace.
- **`/education:explain [thing]`** — a one-shot, plain-language explainer. It
  drops any concept, code, error, architecture, or the previous assistant
  response to genuinely plain words (concrete analogy, zero jargon), then layers
  altitude up only on request (high-school, then peer level). An empty argument
  explains the previous assistant response, so "I don't get it" needs no topic.
  It closes by offering `/education:teach` when you want ongoing coaching rather
  than a single explanation.
- **`/education:quiz-me`** — a post-work comprehension check. After a change is
  complete, it generates a self-contained HTML report of what was done (context,
  intuition, decisions) with a quiz at the bottom you answer — verifying that
  *you* absorbed the work, not just that the artifact is correct. It is
  non-gating by default; the `quiz_policy` setting tunes how often a quiz is
  offered. Its `recall <query>` action answers "what did we do on `<ticket>`" from
  a retained report library first, git and tracker history second.
- Supporting `teach` actions: `mission`, `glossary`, `resources`, `explain`,
  `exercise`, `assess`, `resume`, `status`.

The coach asks questions before giving answers, teaches just beyond your current
level (the zone of proximal development), and grounds every claim in a source
fetched or a file read that session rather than from memory.

## How it works

Each topic gets a **workspace** — a mission (why you're learning this), a glossary,
curated resources, and per-concept slices (a lesson, a durable reference
cheat-sheet, and optional practice). Learning state is treated as **your documents,
not machine internals**: topic-mode workspaces default to a `Claude Learning/` home
in your OS Documents folder (when one is eligible), while codebase-mode workspaces
stay under `${CLAUDE_PLUGIN_DATA}` by default — their lessons can embed snippets
from your repo, and Documents folders are often cloud-synced. Either way the state
survives plugin updates, stays out of your project's tree, and lets you resume a
topic weeks later; the root is configurable (see Configuration). Durable references
are re-verified lazily on revisit (age × domain-velocity) so stale facts get
refreshed before they're taught. See the skill body for the full pedagogy.

## Requirements

- **Bash + coreutils** (`sha256sum`/`shasum`, `realpath`, `tr`, `sed`) for the
  skill's inline mechanics — on native Windows, install
  [Git for Windows](https://code.claude.com/docs/en/setup#set-up-on-windows) so
  they run under Git Bash, which bundles all of them.
- For `codebase` mode, launch it from the repository you want to learn — the
  plugin reads that repo's own docs and source.
- `topic` mode fetches documentation URLs to ground explanations in primary
  sources; if your setup restricts `WebFetch`, allow it or seed `RESOURCES.md`
  manually.

## Install

```shell
/plugin marketplace add melodic-software/claude-code-plugins
/plugin install education@<marketplace>
```

## Configuration

All settings are optional, with defaults that preserve zero-config behavior:

| Setting | Type | Default | What it does |
| --- | --- | --- | --- |
| `quiz_policy` | string | `on-request` | When `quiz-me` offers a quiz: `off` (never), `on-request` (only when asked), `always` (after each completed change), `above-threshold` (when the change is large). Offer cadence only — a report is never generated without your confirmation. Unknown values act as `on-request`. |
| `report_library_dir` | directory | *(unset)* | Where `quiz-me` stores reports. Unset uses the plugin's own `${CLAUDE_PLUGIN_DATA}`; set it to a corpus checkout to redirect the library root there. Reports never land in the repo you are working in. |
| `workspace_root` | directory | *(unset)* | Where `teach` roots learning workspaces. Unset resolves a ladder: a project declaration, this setting, a one-time ask, the OS Documents `Claude Learning/` home (topic mode only), then `${CLAUDE_PLUGIN_DATA}`. Codebase-mode workspaces stay under plugin data unless explicitly rooted elsewhere. Values inside the repo you are working in are refused. |

Configure them through the `/plugin` dialog, or headless at install time with
`claude plugin install education@<marketplace> --config quiz_policy=always`. A literal
non-home `report_library_dir` may be rejected by the hardcoded-path guardrails until
the #798 path-indirection work lands.

Run `/education:setup` to validate the effective `quiz_policy`, report-library root,
and teach workspace root without reading settings files.

<!-- BEGIN GENERATED: plugin options — edit plugin.json, then run scripts/sync-plugin-options-docs.py -->

### Options reference

Generated from this plugin's `.claude-plugin/plugin.json`. Every option Claude Code
will prompt for when the plugin is enabled, with the environment variable each hook
reads it from.

| Option | Type | Default | Environment variable | Description |
| --- | --- | --- | --- | --- |
| `quiz_policy` | string | `"on-request"` | `CLAUDE_PLUGIN_OPTION_QUIZ_POLICY` | When quiz-me offers a post-work comprehension quiz. One of: off (never offers), on-request (only when asked), always (after each completed change), above-threshold (when the change is large). Governs offer cadence only — a report is never generated without your confirmation. Unknown values are treated as on-request. |
| `report_library_dir` | directory | *(none)* | `CLAUDE_PLUGIN_OPTION_REPORT_LIBRARY_DIR` | Where quiz-me stores generated reports and quizzes. Unset uses the plugin's own persistent data directory; set it to a corpus checkout to redirect the library root there. Artifacts never land in the consuming repo's tree. |
| `workspace_root` | directory | *(none)* | `CLAUDE_PLUGIN_OPTION_WORKSPACE_ROOT` | Where /education:teach stores learning workspaces. Unset resolves a ladder: project declaration, this setting, a one-time ask, the OS Documents folder's 'Claude Learning' home (topic mode only), then the plugin's persistent data directory. Codebase-mode workspaces stay under plugin data unless a project declaration or this setting names a root, since their lessons can embed private-repo snippets and Documents roots are often cloud-synced. Grammar: absolute, ~-home-relative, or ${NAME} / %NAME% environment references; a relative value resolves against the project; a value inside the consuming repo is refused — declare an in-repo root in the project's own CLAUDE.md or rules instead. |

### How to set these

Three supported routes, in the order most people want them:

1. **Interactively** — Claude Code prompts for declared options when you enable the
   plugin. To change them later: `/plugin configure education@<marketplace>`.
2. **Headless** — repeat `--config` for each option. Replace
   `<marketplace>` with the marketplace you installed this plugin from:

   ```shell
   claude plugin install education@<marketplace> -s <scope> --config quiz_policy=<value>
   ```

   The same command reconfigures a plugin that is **already installed**: it prints
   `already installed` and still writes the value — verified on Claude Code 2.1.240,
   for a non-sensitive option at `user` scope, by writing a non-default value to an
   installed plugin and restoring it. The short-circuit message is about the install,
   not the config write. That has not been verified for a `sensitive` option or for
   `project`/`local` scope. Do **not** `claude plugin uninstall` in order to
   reconfigure: uninstalling drops this plugin's whole stored `pluginConfigs` entry,
   resetting every option in the table above to its default. `-s` defaults to `user`,
   so pass the scope `claude plugin list` reports for this plugin.

3. **By hand, in settings** — add the value under `pluginConfigs` in your **user**
   settings (`~/.claude/settings.json`):

   ```json
   {
     "pluginConfigs": {
       "education@<marketplace>": {
         "options": {
           "quiz_policy": <value>
         }
       }
     }
   }
   ```

   Plugin option values are read from **user**, `--settings`, and managed settings
   only — **not** from a project's `.claude/settings.json`. To vary behavior per
   repository, enable or disable the plugin in that project's `enabledPlugins`
   instead of setting an option there.

Do not set the `CLAUDE_PLUGIN_OPTION_*` variables yourself. They are how Claude Code
hands a configured value to a hook process; the value comes from the routes above.

### Upstream documentation

- [User configuration](https://code.claude.com/docs/en/plugins-reference#user-configuration) — the `userConfig` schema and the `CLAUDE_PLUGIN_OPTION_<KEY>` export
- [Plugin install options](https://code.claude.com/docs/en/plugins-reference#plugin-install) — the `--config` flag's reference entry
- [Plugins and skills settings](https://code.claude.com/docs/en/settings-reference#plugins-and-skills) — `enabledPlugins`, `extraKnownMarketplaces`, `pluginConfigs`
- [Settings files and who they affect](https://code.claude.com/docs/en/settings#settings-files-and-who-they-affect) — user vs project vs local precedence
- [Manage installed plugins](https://code.claude.com/docs/en/discover-plugins#manage-installed-plugins) — enabling, disabling, `/plugin list`

<!-- END GENERATED: plugin options -->

## License

MIT (SPDX-License-Identifier: MIT).
