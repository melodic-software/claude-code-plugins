# Changelog

All notable changes to the `context7` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

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
  declaring it only restated the path while registering a second, unnamespaced command — which
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
  BSD/macOS, and the example echoes the generated path in the same call — the
  docs output is redirected, so without the echo a following `Read` has no way
  to locate the randomly named file.

## [0.4.2]

### Changed

- Skills with `!` dynamic-context injections now declare `shell: bash` explicitly, per
  the pinned precompute convention — bash-only pipelines must not fall through to a
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
  (silently broken auth) — it is not a parse failure. Both context docs now
  carry verified-date + official-link riders.

## [0.3.0]

### Changed

- Renamed the `context7` skill → `lookup`. Update any `/context7:context7` invocations to
  `/context7:lookup`; the plugin ID (`context7`) is unchanged, only the skill's leaf name moved.
