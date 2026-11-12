# Changelog

All notable changes to the `firecrawl` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.8.9] - 2026-11-12

### Changed

- Synced the shared library copies this plugin carries; their pointer records no longer carry an as-of date or recheck trigger.

## [0.8.8] - 2026-11-11

### Changed

- The setup skill's pre-computed context keeps its fallback for a row showing the `disableSkillShellExecution` placeholder and adds a pointer record to the skills docs' "Inject dynamic context" section, where that placeholder text is documented.

## [0.8.7] - 2026-11-11

### Changed

- Internal simplification, no behavior change.

## [0.8.6] - 2026-11-11

### Changed

- The firecrawl and update skills point at the CLI README and Claude Code docs sections for WebFetch and WebSearch behavior, CLI defaults and limits, the default endpoint, what `init` installs, self-update and the `shell` frontmatter field, instead of restating them. The `agent` reference drops its stale model list and default and points at the README's agent options. No behavior change.

## [0.8.5] - 2026-11-09

### Changed

- Internal simplification, no behavior change.

## [0.8.4] - 2026-11-07

### Changed

- `/firecrawl:firecrawl` matches `firecrawl-cli` 1.29.0: main-content extraction is the default and `--full-page` keeps navigation, headers and footers on `scrape`, `batch-scrape`, `search --scrape` and `parse`; `research search-github` is gone (use `developer`); `research search-papers --sort date_desc` is documented.
- A global CLI install updates itself in the background, so the install step and `/firecrawl:update --apply` now run `firecrawl update --disable-auto`, keeping CLI upgrades behind `/firecrawl:update`'s gates; `--apply` writes nothing when that fails, and the rollback is the pinned reinstall after turning automatic updates off.
- The sync record moves to the current upstream `SKILL.md` and CLI 1.29.0, and the pointers whose recheck trigger fired are re-stamped.

## [0.8.3] - 2026-11-06

### Fixed

- run setup's status checks as single Bash calls

  `firecrawl --version`, `firecrawl --status` and each env-var presence test
  run alone, one call per variable with its name spelled out, so no command
  chains probes or loops with shell-specific indirect expansion.

## [0.8.2] - 2026-11-06

### Changed

- The firecrawl, setup and update `evals.json` files are retired into the `evals/` case suite ([#8635](https://github.com/melodic-software/claude-code-plugins/issues/8635)). Nine of the thirteen legacy cases become new cases: `fc-map-before-crawl` (a whole-site extraction runs `firecrawl map` before any crawl, caps every crawl with `--limit` or `--max-depth`, and writes output with `-o`), `setup-bare-defaults-to-check` (a bare `/firecrawl:setup` runs check without asking, reads the main skill first and covers all four probe areas), `setup-missing-cli-is-info` (an absent CLI and unset key are INFO under the lazy-install design), `setup-apply-no-write-path` (apply installs nothing and writes no key, giving the user-run guidance instead), `setup-status-timeout-indeterminate` (an unanswered `firecrawl --status` is INDETERMINATE and directs no key change), `setup-persisted-login-auth-passes` (a working `firecrawl login` passes, and no env key is added on top), `update-bare-gates-before-mutation` (a bare update installs and rewrites nothing without a gate's yes), `update-installed-copy-refused` (the installed marketplace copy is refused and `/plugin marketplace update` named) and `update-init-login-refused` (update runs neither `firecrawl init` nor `firecrawl login`). The other four were already covered: `fc-blocked-routes` gains a grader that every `-o` target is a `mktemp` spill file, `fc-plain-page` one that the page is fetched with WebFetch, `fc-init-refused` three for the parallel-install reason, no MCP-server claim and env-var setup, and `update-check-read-only` covers the read-only `--check`. The setup cases other than the bare check give the machine state as facts: the CLI is on the smoke host's PATH (the missing-CLI and apply cases), and a run carries no `FIRECRAWL_API_KEY` and has no network (the timeout and login cases). All three `evals.json` files are deleted.

## [0.8.1] - 2026-11-03

### Fixed

`/firecrawl:update --apply` no longer records the wrong CLI version or rollback target when something other than npm owns the `firecrawl` command. It exits 2 before installing, writing nothing and naming the command's path, when the command resolves outside npm's global bin, and it exits 2 without writing `upstream.md` when the command does not read npm latest after the install. The skill's rollback line now says to update the owner's pin in that case.

The update flow now runs `--apply`, which records only the CLI version and rollback target. A new `--record-upstream` mode records the upstream SHA after Gate 2 or when there was no content delta, installing nothing, so a declined or abandoned Gate 2 keeps showing as drift in `--check`.

## [0.8.0] - 2026-11-03

### Added

- `batch-scrape` in `/firecrawl:firecrawl`, for many known URLs as one job

### Changed

- sync the wrapper skill with upstream and `firecrawl-cli` 1.26.24

  `search-feedback` documents `--valuable-results` for returned results and
  narrows `--valuable-sources` to URLs the search did not return. `crawl`
  documents blocking on a job id and writes `--status` output to disk. The
  wrapper no longer says the CLI reads exactly three env vars.
  `/firecrawl:update` records the new upstream hash and CLI version.

## [0.7.8] - 2026-11-02

### Changed

- Hook notices name the bundled checker command; `check` is optional (#12485).

## [0.7.7] - 2026-11-02

### Changed

- Shared `prerequisites.mjs` synced where this plugin carries it (#6633): a manifest may declare an optional `session_probe`, which opts the plugin into harness-ops' session-start probe.

## [0.7.6] - 2026-11-01

### Changed

- `firecrawl` drops three passages from its update notes that repeated what the skill already says: the CLI release-cadence sentence (its upstream link stays under Related), a second "updates arrive through `/plugin marketplace update`" line, and a Related bullet for `/firecrawl:update` that the "Updating the skill and CLI" section already covers. Measured with no loss on Opus 5.5 and Sonnet 5.5.

## [0.7.5] - 2026-10-30

### Changed

- Shared copies synced: links and paths to marketplace plugin contracts now name `docs/contracts/<name>/`, where the contracts moved from `docs/conventions/<name>/`. The old paths keep a stub with every section heading.

## [0.7.4] - 2026-10-27

### Security

- Shared `prerequisites.mjs` synced: each dependency probe runs from the library's own directory, so a probed tool never starts with the user's repository as its working directory.

## [0.7.3] - 2026-10-25

### Changed

- Shared `prerequisites.mjs` synced where this plugin carries it (#9684): `detect.version` accepts an exclusive `below` bound; no other change to this plugin.

## [0.7.2] - 2026-10-20

### Fixed

- `/firecrawl:update --check` no longer counts a firecrawl CLI that is not installed as drift: it reports it and exits 0 when upstream is unchanged, so its exit codes follow the shared drift-check contract (0 no drift, 1 drift, 2 unverifiable). (#6493)
- The `--check` report prints the recorded last-sync date and SHA256 instead of `recorded)`: a never-synced placeholder such as `(none recorded)` now reads as empty. (#6493)

- Shared `prerequisites.mjs` synced: a `node-pkg` or `python-pkg` entry reads `CLAUDE_PLUGIN_DATA` only when its last path segment is this plugin's name or starts with `<plugin>-`, and treats a literal `${...}` value as unset, so another plugin's data directory reports `unverified` instead of `missing`.

## [0.7.1] - 2026-10-16

### Changed

- Shared `prerequisites.mjs` synced: the SessionStart probe now also reports a drifted git-hook entry for a plugin that ships `git-hooks/entries.json`. This plugin ships none, so its behavior is unchanged.

## [0.7.0] - 2026-10-13

### Added

- **`developer`, `research` and `doctor` in `/firecrawl:firecrawl`.** The commands table and `context/commands.md` cover the coding-agent index search, the paper index (GitHub history goes through `developer`, since the research GitHub endpoint is deprecated), and `doctor <job-id>` for a failed job, with flags read from `firecrawl-cli` 1.26.3 `--help`. A new gotcha says to run `doctor` before retrying a failed job with guessed flags.

### Changed

- **Shared `prerequisites.mjs` synced: its per-probe timeout is now 20 seconds, up from 5,** so `firecrawl --status` behind a key-injecting wrapper (a secret lookup plus two API calls) no longer false-fails on a slow run. A hung probe now costs at most 20 seconds per entry.

- The native web tools record points at the live WebFetch and WebSearch sections by anchor instead of restating their behavior, and `/firecrawl:update` points at the skills frontmatter reference for the `name` default.

- **First recorded upstream sync.** `/firecrawl:update`'s `upstream.md` records the upstream `SKILL.md` hash from 2026-10-11 and CLI 1.26.3, so `--check` no longer reports upstream drift for it.

### Fixed

- **The auth prerequisite now asks the CLI instead of the session environment.** The `firecrawl-api-key` env entry is replaced by a required `firecrawl-auth` entry that passes when `firecrawl --status` reports Authenticated, the test `/firecrawl:setup` already treats as authoritative. `/harness-ops:prerequisites` no longer reports the firecrawl skill blocked when `FIRECRAWL_API_KEY` is absent from the Claude Code environment but the CLI is authenticated another way (a wrapper that injects the key into the CLI process only, or `firecrawl login`), and still fails when the CLI is unauthenticated. The README requirement says the same.

- Shared library comments that restated Claude Code hook, plugin and managed-settings behavior now point at the live docs sections, and the prerequisites probe no longer gives a wrong reason for always exiting 0.

- **The `firecrawl init` warning matches what it does now.** It installs upstream's CLI skills globally for every detected agent, plus workflow skills when selected, and registers no MCP server, which the old text said it did. Eval case 4 checks the corrected contract.

- **`firecrawl` and `setup` load under `claude -p` again.** Both pre-computed rows held a brace
  group, which Claude Code's shell permission check refuses even when quote-free (`A group in braces
  or double parentheses in this command can't be checked before it runs`); outside auto mode that
  aborts the skill with no output. `setup`'s probe is now `command -v firecrawl 2>/dev/null || echo
  absent`, pre-approved in its `allowed-tools`. The status row drops the 0.5.7 brace group and
  repeats the guard before the fallback instead:
  `command -v firecrawl >/dev/null 2>&1 && firecrawl --status 2>/dev/null | head -10 || command -v firecrawl >/dev/null 2>&1 || echo "NOT INSTALLED ..."`.
  It renders the same as the 0.5.7 row with and without `pipefail`, for an absent CLI, output under
  the cap and output over it (checked with a fake `firecrawl` on `PATH`), and the existing
  `Bash(command -v firecrawl*)` grant covers both guards.

- **The shared prerequisites checker now finds a `python-pkg` in the plugin's own installed Python
  set.** A module that the interpreter cannot import on its own is looked up in the set a plugin
  with a committed `requirements.txt` installs into its data directory
  (`<data>/python/<lock hash>-<interpreter tag>/`), imported the way that plugin's launcher runs
  it. Before, such a package was reported missing. When the data directory is unknown (no
  `--data-dir`, no `CLAUDE_PLUGIN_DATA`), the entry reports `unverified` instead of failing.
  Refs #6112.

## [0.6.4] - 2026-10-10

### Changed

- **The update skill's sync-state file is now `skills/update/upstream.md`**, renamed from `UPSTREAM.md` so every markdown file in the repository is lower-kebab-case (ADR 0059). `scripts/update.sh`, the skill body, its flow reference, and its evals read and write the new name.

## [0.6.3] - 2026-10-04

### Changed

- **Shared `prerequisites` checker copies synced ([#6225](https://github.com/melodic-software/claude-code-plugins/issues/6225)); no change to this plugin's behavior.**

## [0.6.2] - 2026-10-03

### Changed

- **Shared `prerequisites.mjs` synced ([#6084](https://github.com/melodic-software/claude-code-plugins/issues/6084)); no change to this plugin's lib.**
  The prerequisite check now counts a Windows App Execution Alias (a Store or winget install on PATH) as found,
  except App Installer's Python install stub. A `cli` or `runtime` entry can set `reject_store_alias` to skip aliases instead; no entry in this plugin does.

## [0.6.1] - 2026-10-03

### Changed

- Shared `prerequisites.sh`, `prerequisites.ps1` synced ([#5843](https://github.com/melodic-software/claude-code-plugins/issues/5843)); no change to this plugin's own behavior.

## [0.6.0] - 2026-10-02

### Added

- `prerequisites.json`, declaring the external tools this plugin runs and what stops working
  without each, and the generated `lib/prerequisites.mjs` checker with its `.sh` and `.ps1`
  stubs that read it ([#5841](https://github.com/melodic-software/claude-code-plugins/issues/5841)).

## [0.5.25] - 2026-10-02

### Fixed

- `plugin.json` no longer sets `$schema`. claude.ai's marketplace sync stripped it with a warning, and Claude Code ignores it at load time.

## [0.5.24] - 2026-10-02

### Fixed

- The `setup` `argument-hint` uses Claude Code's official bracket notation: it leads with its check
  action and keeps alternatives inside brackets with an unspaced `|`.
- The `update` `argument-hint` uses Claude Code's official bracket notation: it drops the prose
  after the grammar, which the skill body now carries.

## [0.5.23] - 2026-10-01

### Changed

- References to the `claude-config`, `claude-memory` and `claude-ops` plugins now use their new
  names, `harness-config`, `harness-memory` and `harness-ops`.

## [0.5.22] - 2026-10-01

### Changed

- Dropped citations of the removed topic-docs convention and the `docs/specs` tree.

## [0.5.21] - 2026-09-30

### Changed

- Test-only: the suites remove their temporary directories on exit. No behavior change.

## [0.5.20] - 2026-09-29

### Added

- `firecrawl` carries a Boundary section for the built-in `WebFetch` and `WebSearch` tools: the built-ins for a plain unprotected page or a quick inline lookup, this skill for blocked or JS-rendered pages, full text on disk, crawls, and browser interaction. The four-part record is in the skill's `context/native-web-tools.md`. The section's bullets follow the native-references template and describe the built-ins without asserting they are available.

## [0.5.19] - 2026-09-29

### Fixed

- `firecrawl` states the `firecrawl init --all --browser` prohibition in plain sentence case instead of bold capitals (#4120).
- `update` flow no longer names the unmarked `/skill-creator:skill-creator` route; it points to the rewrite helper the `update` skill body names, so the marketplace attribution lives in one place (#4119).
- `firecrawl` argument hint makes the command slot required again (`<scrape|search|...|credit-usage> [args]`) instead of an all-optional bracket list.

## [0.5.18] - 2026-09-28

### Changed

- **Argument hints** on `firecrawl` stay inside the 100-character house style
  ([#3542](https://github.com/melodic-software/claude-code-plugins/issues/3542)).
  Examples, defaults, and flag catalogs that exceeded the budget now live in the skill body.

## [0.5.17] - 2026-09-27

### Fixed

- `update` names the `skill-creator` rewrite helper as the `skill-creator` plugin from Anthropic's `claude-plugins-official` marketplace, when installed, instead of an unmarked `/skill-creator:skill-creator` route (#4119).

## [0.5.16] - 2026-09-27

### Changed

- **`setup` probes `firecrawl` at load time.** The `command -v firecrawl` check runs as pre-computed
  context, so `check` reads the result instead of making a Bash call. The FAIL rules are unchanged,
  a policy-disabled injection falls back to the Bash probe, and any post-remediation re-check still
  probes live.

## [0.5.15] - 2026-09-25

### Changed

- Comment-only pass with /code-tidying:dissolve-comments: restating comments, history narration and ticket back-references removed from scripts and tests, over-budget rationale shortened. Every edit is certified comment-only by a token-level proof, so behavior is unchanged; the removed text is recorded in the commit bodies.

## [0.5.14]

### Changed

- The four update.sh copies (boris, skill-authoring, playwright, firecrawl) now share one idiom: a single tr call strips quotes and carriage returns from metadata fields, require_tool no longer carries a redundant return, and the firecrawl sha fetch uses the same short-circuit shape as its siblings. The two test suites drop an unread fixture variable.

## [0.5.13]

### Changed

- The desktop-notification, eol-normalizer, go-format, and github test suites route repeated invocations through shared runner and counter helpers, the eol-normalizer hook derives its status from the taken message directly, and the education workspace lister and firecrawl updater drop a redundant subshell and conjunct, with identical output.

## [0.5.12]

### Changed

- Cite the marketplace `docs/` doctrine files by their lower-kebab names (`docs/plugin-philosophy.md`, `docs/migration-playbook.md`, and siblings); the files were renamed and the old uppercase paths no longer resolve.

## [0.5.11]

### Changed

- **`firecrawl`: description prose no longer addresses the reader.** Anthropic's skill-authoring guidance keeps first and second person out of a description because it is injected into the system prompt; the rewritten clauses name the user, the session, or the repository instead. Quoted trigger phrases are unchanged.

## [0.5.10]

### Changed

- **The plugin's prose drops its em dashes.** Six surfaces were rewritten: this changelog, `skills/setup/SKILL.md`, `skills/update/UPSTREAM.md`, and three `skills/firecrawl/context/` and `skills/update/context/` documents. Wording only, with no change to any command, flag, or auth rule. All ten command headings in `context/commands.md` changed anchor, and that file's own Contents block was updated in the same pass; nothing outside it linked them. Four em dashes stay inside single-line inline code spans that reproduce real probe text, which the detector already exempts. The released sections corrected in place are 0.5.7, 0.5.6, 0.5.2, 0.5.1, 0.5.0, 0.4.2, 0.4.1, and 0.3.0: their wording changed, their facts did not.
- **`skills/update/scripts/update.sh` writes `UPSTREAM.md` without em dashes.** That file is generated by a heredoc in the update script, so a purge of the output alone would be undone by the next `--apply`. The generator is the fix site, and its heredoc now matches the committed file byte for byte, which makes a re-run a no-op rather than a diff.
- **The plugin's markdown is declared in `scripts/em-dash-purged-paths.txt`.** The gate now defends `CHANGELOG.md`, every `skills/*/SKILL.md`, `skills/update/UPSTREAM.md`, and the two context trees.

- **Manifest description drops its em dashes.** Wording only; the plugin's behavior, options, and defaults are unchanged. The description renders into `docs/CATALOG.md`, which the repository's em-dash gate reads.

## [0.5.9]

### Changed

- **firecrawl:** the description lists all ten subcommands and states each trigger once; the
  Purpose paragraph explains the spill-file saving by mechanism instead of restating a third-party
  benchmark figure; `context/commands.md` drops the retired MCP family name from the `interact`
  entry.
- **update:** `UPSTREAM.md` records no sync until `scripts/update.sh --apply` writes one, replacing
  a seeded date that predates the plugin; `context/update-flow.md` describes the per-run temp
  directory the script creates and removes instead of hardcoded `/tmp` paths; the body drops the
  auto-fire prohibition that `disable-model-invocation: true` already enforces; `--check` is the
  read-only mode rather than a "default", matching the argument hint, and eval case 1 says so.
- Applied from the 2026-09 prompt-audit against Claude Fable 5.1
  (docs/specs/prompt-audit-skills-2026-09.md).

## [0.5.8]

### Changed

- **`update.sh`: `--help` answers before the checkout guard, matching the vendor-update family.**
  The `SKILL.md not found` check ran ahead of the mode dispatch, so `--help` exited 2 with that
  error outside a plugin checkout instead of printing usage. It now runs after the help arm, which
  is the one behavior this change alters deliberately: `--check` and `--apply` still hit the guard
  in the same place, with the same message and the same exit 2.
- **A dead local dropped from `run_apply`.** `latest` was assigned from `latest_cli_version` and
  never read; the call stays as a registry preflight that must fail before `npm install` mutates
  the global CLI, so its exit status is still what gates the run.

## [0.5.7]

### Fixed

- **`firecrawl`: the `NOT INSTALLED` token could fire on an installed, working CLI.** The status
  probe was
  `command -v firecrawl >/dev/null 2>&1 && firecrawl --status 2>/dev/null | head -10 || echo "NOT INSTALLED — run: npm install -g firecrawl-cli"`.
  Under `set -o pipefail` the `&&` list takes the
  pipeline's status, and `head -10` closing the pipe kills `firecrawl` with SIGPIPE when
  `--status` prints more than the cap, so the `||` fires on a healthy CLI. The rendered context
  then shows ten lines of real status followed by an instruction to install a CLI that is already
  installed, and the paragraph beneath it tells the reader to go get an API key.

  This site predates the guard sweep that introduced the same defect elsewhere: it is where the
  guard-first shape was copied FROM, so it was never touched by that sweep and has carried the
  exposure since it was written. Fixed in the same pass as the sites that copied it.

  Proven by execution in three states, each with and without `pipefail`, against a fake `firecrawl`
  on `PATH`. Absent: both shapes render `NOT INSTALLED …` under both settings. Present, output under
  the cap: both render the output, no token, under both settings. Present, output over the cap:
  without `pipefail` both render ten lines and no token; with `pipefail` the old shape renders ten
  lines **and** `NOT INSTALLED — run: npm install -g firecrawl-cli`, and this one renders the ten
  lines alone.

  The data pipeline now sits in a brace group closed by `:`, the shape `docs-hygiene` 0.21.23 and
  `code-tidying` 0.14.13 established. The command still begins `command -v firecrawl`, so the
  existing `Bash(command -v firecrawl*)` grant still matches. No grant changed.

## [0.5.6]

### Fixed

- **`update`: the "never synced" fallback could not render.** The last-sync probe was
  `grep -m1 '^- Last sync:' "${CLAUDE_SKILL_DIR}/UPSTREAM.md" 2>/dev/null | sed 's/^- //' || echo "never — run this skill with --check"`.
  `sed` exits 0 whether `grep` matched, found nothing, or
  never opened the file, so a missing or unstamped `UPSTREAM.md` rendered an empty value instead of
  the instruction to run `--check`. Verified by execution: against a missing file the old shape
  rendered `[]` and the new one renders `[never — run this skill with --check]`; against the real
  `UPSTREAM.md` both render `Last sync: 2026-05-22`. The probe now guards itself
  (`grep ... >/dev/null 2>&1 && grep -m1 -o 'Last sync:.*' ... || echo ...`), which also retires the
  `sed` stage. Every subcommand still starts `grep -m1` and still names `UPSTREAM.md`, so the
  existing `allowed-tools: Bash(grep -m1 *UPSTREAM.md*)` grant continues to match; nothing was
  widened.

## [0.5.5]

### Changed

- **`setup`: normalized the probe-don't-recite directive and repaired residual grammar defects.**
  The directive had fractured under the same per-plugin de-slop campaign;
  `docs/PLUGIN-PHILOSOPHY.md` now owns the rule under a `runtime-grounded` clause, and the eighteen
  sites that campaign fractured carry one wording. Twenty setup skills assert the rule; the other
  two, `context-guard` and `rate-limit-guard`, state it about their own scripts in their own words
  and are left for a separate pass, so the fleet is not yet down to a single form. Whole-repo
  extract-ssot sweep.

## [0.5.4]

### Changed

- **Authoring-doctrine pass over `README.md`.** Fixed sentences that parsed two ways. Every edit was verified against the file by an agent that did not propose it. Prose only; no behavior, contract, or trigger phrase changed.

## [0.5.3]

### Changed

- **Instruction-surface de-slop (#2891, firecrawl cluster).** Rewrote this plugin's `README.md` and every
  `SKILL.md` to drop em dashes under the repo's zero-tolerance house policy, using
  `/ai-slop:audit fix` semantics: periods or commas, or a restructured sentence, never
  parentheses, en dashes, or a spaced hyphen as a stand-in. Meaning stays; only the mark
  and the sentence break change. The generated options block is ignore-fenced because
  `scripts/sync-plugin-options-docs.py` still emits em dashes from its shared template.
  Changing `skills/update/SKILL.md` required shipping `skills/update/evals/evals.json`
  so the changed-skill `--require-evals` gate stays green.

## [0.5.2]

### Changed

- **setup:** normalized restated setup-contract prose (preamble, probe-ladder
  opening, never-writes boundary, and/or headless-reconfigure recipe as present) to the
  canonical fleet wording, keeping the operable text inline with a provenance-only citation
  (whole-repo extract-ssot batch, #2698).
- Normalized the fleet-wide framing this plugin restates, as touched (cross-vendor advisor
  fallback, untrusted-content posture, attribution/idiom prose), to the canonical
  SSOT wording, operable text kept inline with provenance-only citations (#2698).

## [0.5.1]

### Changed

- **`/firecrawl:firecrawl`'s `Use when:` list now opens with typed phrases.** It previously listed
  only *conditions* ("WebFetch returns 403/429", "a page requires JS rendering"). Those are
  accurate, but nothing a user types, and nothing the gate's trigger-drop protection could track.
  `'scrape this page'`, `'crawl this site'`, `'search the web for X'`, `'WebFetch is blocked'`,
  `'this page needs JS'` and `'extract the text from this PDF'` now front the list; every original
  condition is retained behind them.

## [0.5.0]

### Changed

- **`update`'s preservation rules no longer require a frontmatter `name`** on the wrapper skill.
  The rule was what would have re-added the field on the next integration run.

### Removed

- **The bare `/<skill>` alias for this plugin's skills.** Their `SKILL.md` files no longer
  declare a frontmatter `name`. The field is optional and defaults to the directory name, so
  declaring it only restated the path while registering a second, unnamespaced command, which
  the slash-command picker then echoed back as `/plugin:skill (skill)`. Invoke a skill by its
  namespaced command; the command itself is unchanged.

## [0.4.2]

### Changed

- **Core pattern now conforms to the topic-docs ephemeral tier.** Spill files are
  created via the platform temp primitive (`mktemp "${TMPDIR:-/tmp}/fc-…-XXXXXX"`,
  never a bare relative template, which would resolve against the current
  directory and drop the file inside the consumer's repository) instead of a
  hand-rolled `date +%s%N` nonce
  under a hardcoded `/tmp`, and self-consumed spill files are
  removed after the selective `Read` (kept only when the user asked for the file
  itself), so a research-heavy session no longer accumulates one orphan file per
  call. The update skill's preservation rule, the command reference, and the eval
  expectations follow the same pattern.

  The temp root rides in the positional TEMPLATE rather than in a flag.
  `-p` (which GNU also spells `--tmpdir`) is documented in both dialects but does
  not mean the same thing: GNU treats the template as relative to that directory
  and lets the flag beat `TMPDIR`, while BSD/macOS consult it only as a fallback
  for `-t` when `TMPDIR` is unset. So with a bare template and no `-t` the flag
  does nothing there and the template resolves against the current directory,
  silently writing into the consumer's repo. GNU additionally marks `-t`
  deprecated, and BSD's `-t` takes a prefix rather than a template. An absolute
  path in the positional TEMPLATE is reinterpreted by neither dialect.

  `scripts/update.sh` moves off `mktemp -d -t` to the same positional form. On
  BSD that `-t` argument is a *prefix* rather than a template, so the run
  directory came out named differently there than on GNU; both now agree.

  The Windows gotcha states what actually governs the outcome: where the Bash
  tool is Git Bash, `${TMPDIR:-/tmp}` resolves through the `/tmp` mount to `%TEMP%`;
  on a Windows host without Git Bash the PowerShell tool runs and `mktemp` does
  not exist. The skill's `shell: bash` frontmatter does **not** cover this.
  That field governs only the `!` dynamic-context injection evaluated at
  skill-load time, not the Bash tool calls the skill body issues.

## [0.4.1]

### Changed

- Skills with `!` dynamic-context injections now declare `shell: bash` explicitly, per
  the pinned precompute convention. Bash-only pipelines must not fall through to a
  PowerShell host.

## [0.4.0]

### Changed

- **Extracted the maintainer update/drift pipeline into its own sibling skill,
  `/firecrawl:update`** (issue #261). `UPSTREAM.md`, `scripts/update.sh` (+ its
  regression tests), `context/update-flow.md`, and the "Updating the skill and
  CLI" / "Safety" / Preservation-rules sections move out of the user-facing
  `/firecrawl:firecrawl` wrapper into a dedicated maintainer-facing skill
  (`user-invocable`, `disable-model-invocation: true`), mirroring the
  `playbooks:update` standalone pattern. The wrapper now carries only its
  user-facing scrape/search/crawl surface plus a pointer to the update skill;
  the invocation moves from `/firecrawl:firecrawl update` to `/firecrawl:update`.
  No behavior change to the update flow itself.

## [0.3.1]

### Changed

- Documentation-only: the License section now states the plugin's own MIT
  license inline and no longer points at a `LICENSE` file at the repository
  root, which an installed consumer running from the isolated plugin cache
  cannot reach. No behavior change.

## [0.3.0]

### Added

- **Uniform-contract `setup` skill** (fleet conformance wave). `/firecrawl:setup check` reads
  the main skill as the single source of truth and probes the `firecrawl` binary (absence is
  INFO: the plugin is lazy-install by design) and `FIRECRAWL_API_KEY` presence in the OS
  user environment (presence only: the key value is never printed, logged, or persisted).
  `apply` is guidance-and-verify with no write path: it defers to the main skill's documented
  `npm install -g firecrawl-cli` flow and points at the OS-appropriate way to set the key,
  writing nothing.

## [0.2.2]

### Added

- This changelog (fleet conformance wave: every versioned plugin ships a
  Keep-a-Changelog file).

## [0.2.1]

First versioned release covered by this changelog; see the git history of
`plugins/firecrawl/` for earlier changes.
