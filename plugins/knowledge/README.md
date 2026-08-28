# knowledge

A Claude Code plugin that ingests external knowledge into durable, synthesized
artifacts. Its first shipped pipeline distills a technical book (PDF or EPUB) into
concept-organized, author-attributed **skill reference files**; a re-runnable
`setup` action settles where synthesized artifacts land in the consuming repo.

## Skills

| Skill | Invoke | What it does |
|---|---|---|
| `book-distill` | `/knowledge:book-distill` | Turns a technical book (PDF/EPUB) into concept-organized, author-attributed skill reference files through a structured, multi-session read-write pipeline, updating the target skill's routing table. |
| `course-digest` | `/knowledge:course-digest` | Extracts and synthesizes an online video course (Dometrain, Teachable), transcripts, frames, resources, companion code, into repo-applicable recommendations. Actions: full pipeline (default), `extract`, `analyze`, `status`, `resume`, `continue`. |
| `docpage-digest` | `/knowledge:docpage-digest` | Ingests a single online documentation page (docs-site URL) into a verified knowledge slice. Unaltered original, INDEX inventory, per-section model-matched digests, dual verification (one cross-vendor verifier), and an interview-ready handoff artifact. Publisher profiles (fetch channel, applicability filter, doc queue) are separable context files; first profile: Anthropic docs. |
| `map-corpus` | `/knowledge:map-corpus` | Maps a multi-resource documentation corpus into a verified, classified, triaged slice before any digesting: bounded discovery, a user-approved link map classifying every discovered URL, deterministic node manifests over immutable snapshots, and a per-node relevance inventory whose evidence a script gate verifies, handing an approved queue to N runs of `/knowledge:docpage-digest`. |
| `video-digest` | `/knowledge:video-digest` | Watches a single public video from YouTube or X (Twitter), transcript + visual frames, harvests reference links, drives external research, and synthesizes a prioritized repo-applicability menu. Actions: `watch`, `queue`, `transcript`, `resume`. |
| `setup` | `/knowledge:setup` | `check` (default) verifies `library_dir` against the repository's artifact convention and probes the extraction prerequisites read-only; `apply` routes personal option changes through Claude Code's plugin configuration prompt; `apply install-deps` provisions the video pipelines' node dependencies and Chromium. |

## What book-distill produces

- **Concept-organized reference files** (60-160 lines each), named by what they
  teach rather than by chapter number, with the author attributed in section
  headers.
- **Routing-table and quick-decision-guide updates** to the target skill's
  `SKILL.md`, so the skill loads the right reference file for a given developer
  question at query time.
- **Multi-author merges**, where two books cover the same concept, their
  content is consolidated into a shared file.

You name the target skill when you invoke `/knowledge:book-distill`, so output
lands somewhere you chose (`${CLAUDE_PROJECT_DIR}/.claude/skills/<target>/`): either an existing skill it extends or a new one it creates. Cross-session state
(the file plan, page map, and a checklist) persists under `${CLAUDE_PLUGIN_DATA}`,
which survives plugin updates.

## Usage caution. Copyright

This plugin is a neutral tool; **you own the rights decision** for everything you
distill with it. A condensed distillation of a copyrighted book is a
**derivative work** (17 U.S.C. §§ 101, 106), the copyright holder's exclusive
rights include preparing and distributing derivatives, so distilled outputs
carry **redistribution risk**. Keeping a private distillation for your own study
is a different act from publishing, committing, or sharing one; fair use is a
defense raised after the fact, not a safe harbor you can assume in advance.
Publish, commit, or redistribute a distilled output only once you have satisfied
yourself that doing so is lawful for that book. This is a caution, not legal
advice.

The distilled output is written into a skill that Claude later **auto-loads as
model context**, so review it before you commit or share it: treat the source
book as untrusted input and confirm the distillation reflects the book rather than
any instructions injected through its text.

## Revisit condition

`video-digest` ships as a skill inside this plugin rather than a standalone plugin
because a separate plugin cannot reach this one's vendored `video-digestion`
package. Plugins are isolated, with no sibling reach-outs. Extract a standalone
`youtube` plugin once that package is independently distributable, or a consumer
needs video without the rest of the knowledge stack.

## Requirements

- A PDF or EPUB you have the right to read. PDF works natively with Claude
  Code's Read tool; EPUB requires unzipping and text extraction first.
- **Bash + coreutils** for the skills' inline mechanics (`book-distill`
  hashes its progress-file slug with `sha256sum`/`shasum` on every run). On
  native Windows, install
  [Git for Windows](https://code.claude.com/docs/en/setup#set-up-on-windows)
  so they run under Git Bash, which bundles `sha256sum`.
- **`unzip` on `PATH` for the EPUB branch**, not bundled with Git Bash;
  install it or extract the EPUB with another archive tool first. PDF-only
  use does not need it.

## Install

```shell
/plugin marketplace add melodic-software/claude-code-plugins
/plugin install knowledge@<marketplace>
```

Migrating from the standalone `book-distill` plugin? Nothing to do. The
marketplace's `renames` map migrates `book-distill@<marketplace>` to
`knowledge@<marketplace>` automatically on your next session; the skill is now
invoked as `/knowledge:book-distill`.

One exception: an **in-progress multi-session distillation** stores its resume
checklist under the plugin's `${CLAUDE_PLUGIN_DATA}` directory, which is keyed by
plugin id and is **not** migrated by `renames` (that map rewrites `enabledPlugins`
and `pluginConfigs`, not plugin data). If you have a distillation in flight, copy
your old `book-distill` plugin-data directory to the new `knowledge` one before
resuming so the resume pointer survives.

## Configuration

Personal options, prompted by Claude Code at enable time (all optional; zero-config
defaults keep every pipeline working):

| Option | Type | Default | Purpose |
|---|---|---|---|
| `library_dir` | directory | `.` (repo root) | Directory where the plugin's ingestion pipelines land synthesized artifacts; a relative value resolves against the project directory. Portable non-project roots: an absolute path, a leading `~` (home-relative), or an env-var reference `${NAME}` / `%NAME%` (e.g. `${KNOWLEDGE_CORPUS_DIR}`) so a machine-varying root never needs a literal machine path in the stored value. Expanded when a pipeline resolves the root (the `video-digest` launcher and the `docpage-digest` work root today), failing loud on an unset variable. `book-distill` is unaffected. It writes to the target skill you name at invocation. A working-notes or artifacts convention declared in your own project's `CLAUDE.md` or rules takes precedence. |
| `yt_dlp_js_runtimes` | string | `node` | `video-digest`: JavaScript runtime yt-dlp uses for YouTube signature deciphering. Set to `off` to omit the flag entirely. |
| `yt_dlp_cookies_file` | string | (empty) | `video-digest`: path to a Netscape cookies.txt for authenticated acquisition. Never commit cookie files. |
| `yt_dlp_cookies_from_browser` | string | (empty) | `video-digest`: browser to pull YouTube cookies from (`chrome`, `firefox`, `edge`, …), forcing one instead of the automatic fallback. A cookies file wins over this. |
| `max_concurrent_acquires` | number | `1` | `video-digest`: cap on concurrent yt-dlp acquisitions during a batch (1–3). Higher increases HTTP 429 risk. |

`book-distill` itself writes to a **target skill** you name at invocation, so it
needs no configuration to run; `library_dir` is the shared artifact-landing seam
the plugin's ingestion pipelines resolve through. The `video-digest` acquisition
options above tune yt-dlp authentication and throttling; **course-platform
credentials are intentionally not** `userConfig`. They stay in shell env vars
because a `sensitive` option persists as plaintext on Windows today.

<!-- ai-slop-ignore-start: generated options block; source is plugin.json + scripts/sync-plugin-options-docs.py -->
<!-- BEGIN GENERATED: plugin options — edit plugin.json, then run scripts/sync-plugin-options-docs.py -->

### Options reference

Generated from this plugin's `.claude-plugin/plugin.json`. Every option Claude Code
will prompt for when the plugin is enabled, with the environment variable each hook
reads it from.

| Option | Type | Default | Environment variable | Description |
| --- | --- | --- | --- | --- |
| `library_dir` | directory | `"."` | `CLAUDE_PLUGIN_OPTION_LIBRARY_DIR` | Directory where synthesized knowledge artifacts land. Default is the consuming repo root; a relative value is resolved against the project directory. Portable non-project roots: an absolute path, a leading ~ (home-relative), or an environment-variable reference ${NAME} / %NAME% (e.g. ${KNOWLEDGE_CORPUS_DIR}) so a machine-varying root never needs a literal machine path in this stored value. A working-notes or artifacts convention declared in your own project's CLAUDE.md or rules takes precedence. |
| `yt_dlp_js_runtimes` | string | `"node"` | `CLAUDE_PLUGIN_OPTION_YT_DLP_JS_RUNTIMES` | JavaScript runtime yt-dlp uses for YouTube signature deciphering. Default 'node'. Set to 'off' to omit the --js-runtimes flag entirely. |
| `yt_dlp_cookies_file` | string | *(none)* | `CLAUDE_PLUGIN_OPTION_YT_DLP_COOKIES_FILE` | Path to a Netscape-format cookies.txt for authenticated video acquisition (YouTube bot checks; the three login-required X cases). Empty by default (unauthenticated; YouTube adds an automatic browser-cookie fallback on a bot check — X never iterates browser profiles). Never commit cookie files. |
| `yt_dlp_cookies_from_browser` | string | *(none)* | `CLAUDE_PLUGIN_OPTION_YT_DLP_COOKIES_FROM_BROWSER` | Browser to pull cookies from (e.g. chrome, firefox, edge), forcing one instead of the automatic platform-ordered fallback. YouTube only — the X adapter is cookies-file-only. Empty by default. A cookies file, when set, wins over this. |
| `max_concurrent_acquires` | number<br>*min 1, max 3* | `1` | `CLAUDE_PLUGIN_OPTION_MAX_CONCURRENT_ACQUIRES` | Cap on concurrent yt-dlp acquisition runs during a batch. Default 1; raising it increases HTTP 429 throttling risk. |

### How to set these

Three supported routes, in the order most people want them:

1. **Interactively** — Claude Code prompts for declared options when you enable the
   plugin. To change them later: `/plugin configure knowledge@<marketplace>`.
2. **Headless** — repeat `--config` for each option. Replace
   `<marketplace>` with the marketplace you installed this plugin from:

   ```shell
   claude plugin install knowledge@<marketplace> -s <scope> --config library_dir=<value>
   ```

   The same command reconfigures a plugin that is **already installed**: it prints
   `already installed` and still writes the value — verified on Claude Code 2.1.240,
   for a non-sensitive option at `user` scope, by writing a non-default value to an
   installed plugin and restoring it. The short-circuit message is about the install,
   not the config write. That has not been verified for a `sensitive` option or for
   `project`/`local` scope. Do **not** `claude plugin uninstall` to
   reconfigure: uninstalling drops this plugin's whole stored `pluginConfigs` entry,
   resetting every option in the table above to its default. `-s` defaults to `user`,
   so pass the scope `claude plugin list` reports for this plugin.

   The value is stored immediately; the session you are in does not change. Hooks are
   handed their `CLAUDE_PLUGIN_OPTION_*` when the session starts, so start a fresh
   Claude Code session before expecting new behavior — a check run in the old session
   still reports the old value, and that is not a failed write.

3. **By hand, in settings** — add the value under `pluginConfigs` in your **user**
   settings (`~/.claude/settings.json`):

   ```json
   {
     "pluginConfigs": {
       "knowledge@<marketplace>": {
         "options": {
           "library_dir": <value>
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
<!-- ai-slop-ignore-end -->

## License

MIT (SPDX-License-Identifier: MIT).
