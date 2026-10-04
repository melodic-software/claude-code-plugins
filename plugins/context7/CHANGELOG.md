# Changelog

All notable changes to the `context7` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.6.8] - 2026-10-04

### Changed

- **Shared `prerequisites` checker copies synced ([#6225](https://github.com/melodic-software/claude-code-plugins/issues/6225)); no change to this plugin's behavior.**

## [0.6.7] - 2026-10-03

### Changed

- **Shared `prerequisites.mjs` synced ([#6084](https://github.com/melodic-software/claude-code-plugins/issues/6084)); no change to this plugin's lib.**
  The prerequisite check now counts a Windows App Execution Alias (a Store or winget install on PATH) as found,
  except App Installer's Python install stub. A `cli` or `runtime` entry can set `reject_store_alias` to skip aliases instead; no entry in this plugin does.

## [0.6.6] - 2026-10-03

### Changed

- Shared `prerequisites.sh`, `prerequisites.ps1` synced ([#5843](https://github.com/melodic-software/claude-code-plugins/issues/5843)); no change to this plugin's own behavior.

## [0.6.5] - 2026-10-03

### Changed

- `prerequisites.json` is converted to the schema `docs/conventions/prerequisites/` owns: a `requires` list whose entries carry `id`, `kind`, `need`, `for`, `detect`, `degrade`, `install` and `check`, in place of the retired `tools` list, and now declares `node`, which the shared checker needs ([#5840](https://github.com/melodic-software/claude-code-plugins/issues/5840)). The plugin now ships the shared checker, `lib/prerequisites.mjs` with its `lib/prerequisites.sh` and `lib/prerequisites.ps1` stubs, generated from the repository's canonical copy.

## [0.6.4] - 2026-10-02

### Fixed

- `plugin.json` no longer sets `$schema`. claude.ai's marketplace sync stripped it with a warning, and Claude Code ignores it at load time.
- The `lookup` skill description no longer contains angle brackets: placeholders such as `<X>` are now uppercase words. The Agent Skills spec forbids XML tags in a description, and claude.ai strips them.

## [0.6.3] - 2026-10-02

### Fixed

- The `lookup` `argument-hint` uses Claude Code's official bracket notation: it keeps alternatives
  inside brackets with an unspaced `|`.
- The `setup` `argument-hint` uses Claude Code's official bracket notation: it leads with its check
  action and keeps alternatives inside brackets with an unspaced `|`.

## [0.6.2] - 2026-09-30

### Fixed

- **`lookup`'s `update.md` runs `update.sh` from a path that resolves.** The three `update.sh` commands cited the script through the literal plugin-root token, which does not expand in a context file. They now read `<skill-dir>/scripts/update.sh`, and `SKILL.md` gains a `## Spoke paths` section saying `<skill-dir>` is the skill's directory.

## [0.6.1] - 2026-09-29

### Changed

- **`lookup` drops the anti-laziness clause from its philosophy line
  ([#4120](https://github.com/melodic-software/claude-code-plugins/issues/4120)).** The line no longer
  says "even for libraries you 'know.'" and still says to verify against Context7 before claiming how a
  library works.

## [0.6.0] - 2026-09-29

### Added

- **`/context7:check`, a model-invocable read-only check
  ([#4240](https://github.com/melodic-software/claude-code-plugins/issues/4240)).**
  `prerequisites.json` named `/context7:setup check`, which `disable-model-invocation: true`
  hides from Claude. It now names `/context7:check`, which follows only the `check` section of
  `setup` and never installs.

### Changed

- **`lookup` restores the clause "even for libraries you 'know.'" in its philosophy line
  ([#4120](https://github.com/melodic-software/claude-code-plugins/issues/4120)).** The 0.5.9 removal
  contradicted #4120's acceptance criterion, which left the clause unedited pending a human decision.
  The decision (keep the removal or keep the clause) is open on #4120.
- **`lookup` states its default action as a sentence.** The `**Arguments.**` line now ends with
  "Default action is lookup, e.g. /context7:lookup react "useEffect cleanup"." No behavior change.
- **Declared in-place correction to the released `## [0.5.10]` section (#2388 sanction).** Its body
  described the claude-ops prerequisites mechanism, not what context7 shipped. It now reads "Declares the
  `ctx7` CLI in `prerequisites.json` so `/claude-ops:prerequisites` can report it when missing." The heading
  is unchanged.

## [0.5.11] - 2026-09-28

### Changed

- **Argument hints** on `lookup` stay inside the 100-character house style
  ([#3542](https://github.com/melodic-software/claude-code-plugins/issues/3542)).
  Examples, defaults, and flag catalogs that exceeded the budget now live in the skill body.

## [0.5.10] - 2026-09-28

### Changed

- Declares the `ctx7` CLI in `prerequisites.json` so `/claude-ops:prerequisites` can report it when missing.

## [0.5.9] - 2026-09-27

### Changed

- `lookup`'s philosophy line drops the anti-laziness clause "even for libraries you 'know.'" It still says to verify against Context7 before claiming how a library works (#4120).

## [0.5.8] - 2026-09-25

### Changed

- Comment-only pass with /code-tidying:dissolve-comments: restating comments, history narration and ticket back-references removed from scripts and tests, over-budget rationale shortened. Every edit is certified comment-only by a token-level proof, so behavior is unchanged; the removed text is recorded in the commit bodies.

## [0.5.7]

### Changed

- The ai-slop audit detector reads its phrase_add and phrase_remove config keys through one helper, its suite shares the branch-line and tier assertions, and the context7 updater drops a dead echo fallback, with identical output.

## [0.5.6]

### Changed

- Cite the marketplace `docs/` doctrine files by their lower-kebab names (`docs/plugin-philosophy.md`, `docs/migration-playbook.md`, and siblings); the files were renamed and the old uppercase paths no longer resolve.

## [0.5.5]

### Changed

- **The plugin's prose drops its em dashes.** Five surfaces were rewritten: this changelog and the four `skills/lookup/context/` documents. Wording only, with no change to any command, flag, transport, or quota rule. Two em dashes inside fenced bash examples are left alone, because there they sit in a command a reader copies. No heading changed, so no anchor moved. The released sections corrected in place are 0.5.0, 0.4.3, 0.4.2, and 0.3.1: their wording changed, their facts did not.
- **The vendored upstream tree under `skills/lookup/vendor/` is untouched.** It is reference material from the Context7 project, not this repository's writing, and the repository's own rule keeps its formatting out of the house style.
- **The plugin's markdown is declared in `scripts/em-dash-purged-paths.txt`.** The gate now defends `CHANGELOG.md`, every `skills/*/SKILL.md`, and the `skills/lookup/context/` tree. The vendor tree stays excluded.

## [0.5.4]

### Changed

- **lookup:** the MCP-versus-CLI content ratio has one dated home in `context/mcp.md`, now with a
  recheck trigger, and the five other sites point at it; the resolve-first rule and the `vendor/`
  note state their reasons at normal volume; the secrets rule in `context/lookup.md` is stated
  twice instead of three times; `context/cli.md` drops the deprecated `ctx7 skills` rows and alias
  line and states the optional query argument without a version diff; `context/mcp.md` drops the
  serialization note; the description names the intent category with two example phrases.
- **setup:** the description names the intent category with three example phrases; the idempotence
  rule is stated once, in `apply`; the plugin-cache boundary carries its reason; the MCP guidance
  points at `context/mcp.md` for the content ratio.
- Applied from the 2026-09 prompt-audit against Claude Fable 5.1
  (docs/specs/prompt-audit-skills-2026-09.md).

## [0.5.3]

### Changed

- **Instruction-surface de-slop (#2891, context7 cluster).** Rewrote this plugin's `README.md` and every
  `SKILL.md` to drop em dashes under the repo's zero-tolerance house policy, using
  `/ai-slop:audit fix` semantics: periods or commas, or a restructured sentence, never
  parentheses, en dashes, or a spaced hyphen as a stand-in. Meaning stays; only the mark
  and the sentence break change. Vendored `skills/lookup/vendor/**/SKILL.md` is left
  untouched: it is detector-excluded upstream baseline, not a rewrite target.

## [0.5.2]

### Changed

- **setup:** normalized restated setup-contract prose (preamble, probe-ladder
  opening, never-writes boundary, and/or headless-reconfigure recipe as present) to the
  canonical fleet wording, keeping the operable text inline with a provenance-only citation
  (whole-repo extract-ssot batch, #2698).

## [0.5.1]

### Changed

- **`/context7:lookup`'s `description` now leads with typed trigger phrases.** It previously stated
  the routing condition only as prose ("whenever a question names a library, framework, SDK, CLI
  tool, or cloud service"), which reads as a summary rather than a trigger spec, and the phrases a
  user actually types were absent. `Use when:` now fronts `'look up the docs for X'`,
  `'what's the API for X'`, `'how do I configure X'`, `'latest docs for X'`,
  `'check context7 for X'` and `'how do I migrate to X v2'`, with the names-a-library condition
  folded in behind them instead of stated twice.

## [0.5.0]

### Removed

- **The bare `/<skill>` alias for this plugin's skills.** Their `SKILL.md` files no longer
  declare a frontmatter `name`. The field is optional and defaults to the directory name, so
  declaring it only restated the path while registering a second, unnamespaced command, which
  the slash-command picker then echoed back as `/plugin:skill (skill)`. Invoke a skill by its
  namespaced command; the command itself is unchanged.

## [0.4.4]

### Added

- **The upstream-integration protocol records restrained trigger phrasing as a customization to
  preserve.** `context/update.md`'s "What to preserve" table now states that upstream's blanket
  forcing language in triggers is deliberately not carried into any non-vendor surface, so a port
  does not quietly import it. The vendored baselines keep upstream's wording verbatim, and a genuine
  call-order dependency stated in body prose is outside the row's scope.

## [0.4.3]

### Changed

- **Dump-to-disk pipe example uses `mktemp` instead of a hardcoded `/tmp` path**,
  conforming the illustrative CLI composability example to the topic-docs
  ephemeral tier. The temp root rides in the positional template
  (`mktemp "${TMPDIR:-/tmp}/ctx7-XXXXXX"`) so the form works on both GNU and
  BSD/macOS, and the example echoes the generated path in the same call. The
  docs output is redirected, so without the echo a following `Read` has no way
  to locate the randomly named file.

## [0.4.2]

### Changed

- Skills with `!` dynamic-context injections now declare `shell: bash` explicitly, per
  the pinned precompute convention. Bash-only pipelines must not fall through to a
  PowerShell host.

## [0.4.1]

### Changed

- Documentation-only: the License section now states the plugin's own MIT
  license inline and no longer points at a `LICENSE` file at the repository
  root, which an installed consumer running from the isolated plugin cache
  cannot reach. No behavior change.

## [0.4.0]

### Changed

- **Setup adopts the uniform `check` / `apply` contract.** The single interactive
  flow is split into a read-only `check` (default) that reports the `ctx7` CLI,
  `CONTEXT7_API_KEY` presence, and MCP-server state as PASS/FAIL/INFO, and an
  `apply` that resolves what `check` found. The global CLI install is gated behind
  an explicit `apply install-cli` subaction. Auth is reported by presence only and
  its value is never printed; an env-var change defers verification to a fresh
  session. README setup bullet updated to the action shape.

## [0.3.1]

### Changed

- **CLI/platform facts re-verified against `ctx7` 0.5.5 and corrected**
  (fleet conformance wave: freshness riders). `--base-url` default is
  `https://context7.com` (not `/api`), version flag is lowercase `-v`,
  `library`'s query argument is optional, the `skills` surface is deprecated
  upstream (this plugin never invokes it), and new top-level
  `remove`/`uninstall` + `upgrade` commands are listed.
- **Claude Code unset-env-var MCP behavior corrected**: the config loads with
  a missing-variable warning and the literal `${VAR}` text is sent as-is
  (silently broken auth). It is not a parse failure. Both context docs now
  carry verified-date + official-link riders.

## [0.3.0]

### Changed

- Renamed the `context7` skill → `lookup`. Update any `/context7:context7` invocations to
  `/context7:lookup`; the plugin ID (`context7`) is unchanged, only the skill's leaf name moved.
