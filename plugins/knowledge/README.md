# knowledge

A Claude Code plugin that ingests external knowledge into durable, synthesized
artifacts. Its first shipped pipeline distills a technical book (PDF or EPUB) into
concept-organized, author-attributed **skill reference files**; a re-runnable
`setup` action settles where synthesized artifacts land in the consuming repo.

## Skills

| Skill | Invoke | What it does |
|---|---|---|
| `book-distill` | `/knowledge:book-distill` | Turns a technical book (PDF/EPUB) into concept-organized, author-attributed skill reference files through a structured, multi-session read-write pipeline, updating the target skill's routing table. |
| `youtube-digest` | `/knowledge:youtube-digest` | Watches a single public YouTube video (transcript + visual frames), harvests reference links, drives external research, and synthesizes a prioritized repo-applicability menu. Actions: `watch`, `queue`, `transcript`, `resume`. |
| `setup` | `/knowledge:setup` | Validates `library_dir` against the repository's artifact convention and routes personal option changes through Claude Code's plugin configuration prompt. |

## What book-distill produces

- **Concept-organized reference files** (60-160 lines each), named by what they
  teach rather than by chapter number, with the author attributed in section
  headers.
- **Routing-table and quick-decision-guide updates** to the target skill's
  `SKILL.md`, so the skill loads the right reference file for a given developer
  question at query time.
- **Multi-author merges** — where two books cover the same concept, their
  content is consolidated into a shared file.

You name the target skill when you invoke `/knowledge:book-distill`, so output
lands somewhere you chose (`${CLAUDE_PROJECT_DIR}/.claude/skills/<target>/`) —
either an existing skill it extends or a new one it creates. Cross-session state
(the file plan, page map, and a checklist) persists under `${CLAUDE_PLUGIN_DATA}`,
which survives plugin updates.

## Usage caution — copyright

This plugin is a neutral tool; **you own the rights decision** for everything you
distill with it. A condensed distillation of a copyrighted book is a
**derivative work** (17 U.S.C. §§ 101, 106) — the copyright holder's exclusive
rights include preparing and distributing derivatives — so distilled outputs
carry **redistribution risk**. Keeping a private distillation for your own study
is a different act from publishing, committing, or sharing one; fair use is a
defense raised after the fact, not a safe harbor you can assume in advance.
Publish, commit, or redistribute a distilled output only once you have satisfied
yourself that doing so is lawful for that book. This is a caution, not legal
advice.

The distilled output is written into a skill that Claude later **auto-loads as
model context** — so review it before you commit or share it: treat the source
book as untrusted input and confirm the distillation reflects the book rather than
any instructions injected through its text.

## Revisit condition

`youtube-digest` ships as a skill inside this plugin rather than a standalone plugin
because a separate plugin cannot reach this one's vendored `video-digestion`
package — plugins are isolated, with no sibling reach-outs. Extract a standalone
`youtube` plugin once that package is independently distributable, or a consumer
needs video without the rest of the knowledge stack.

## Requirements

- A PDF or EPUB you have the right to read. PDF works natively with Claude
  Code's Read tool; EPUB requires unzipping and text extraction first.
- **Bash + coreutils** for the skills' inline mechanics (`book-distill`
  hashes its progress-file slug with `sha256sum`/`shasum` on every run) — on
  native Windows, install
  [Git for Windows](https://code.claude.com/docs/en/setup#set-up-on-windows)
  so they run under Git Bash, which bundles `sha256sum`.
- **`unzip` on `PATH` for the EPUB branch** — not bundled with Git Bash;
  install it or extract the EPUB with another archive tool first. PDF-only
  use does not need it.

## Install

```shell
/plugin marketplace add melodic-software/claude-code-plugins
/plugin install knowledge@melodic-software
```

Migrating from the standalone `book-distill` plugin? Nothing to do — the
marketplace's `renames` map migrates `book-distill@melodic-software` to
`knowledge@melodic-software` automatically on your next session; the skill is now
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
| `library_dir` | directory | `.` (repo root) | Project-relative directory where the plugin's ingestion pipelines land synthesized artifacts. `book-distill` is unaffected — it writes to the target skill you name at invocation — so today this is a reserved seam. A working-notes or artifacts convention declared in your own project's `CLAUDE.md` or rules takes precedence. |
| `yt_dlp_js_runtimes` | string | `node` | `youtube-digest`: JavaScript runtime yt-dlp uses for YouTube signature deciphering. Set to `off` to omit the flag entirely. |
| `yt_dlp_cookies_file` | string | (empty) | `youtube-digest`: path to a Netscape cookies.txt for authenticated acquisition. Never commit cookie files. |
| `yt_dlp_cookies_from_browser` | string | (empty) | `youtube-digest`: browser to pull YouTube cookies from (`chrome`, `firefox`, `edge`, …), forcing one instead of the automatic fallback. A cookies file wins over this. |
| `max_concurrent_acquires` | number | `1` | `youtube-digest`: cap on concurrent yt-dlp acquisitions during a batch (1–3). Higher increases HTTP 429 risk. |

`book-distill` itself writes to a **target skill** you name at invocation, so it
needs no configuration to run; `library_dir` is the shared artifact-landing seam
the plugin's ingestion pipelines resolve through. The `youtube-digest` acquisition
options above tune yt-dlp authentication and throttling; **course-platform
credentials are intentionally not** `userConfig` — they stay in shell env vars
because a `sensitive` option persists as plaintext on Windows today.

## License

MIT (SPDX-License-Identifier: MIT). See the LICENSE file at the root of the
melodic-software/claude-code-plugins repository.
