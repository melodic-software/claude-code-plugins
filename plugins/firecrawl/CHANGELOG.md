# Changelog

All notable changes to the `firecrawl` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

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
- Normalized fleet-wide framing this plugin restates (cross-vendor advisor
  fallback, untrusted-content posture, attribution/idiom prose — as touched) to the canonical
  SSOT wording, operable text kept inline with provenance-only citations (#2698).

## [0.5.1]

### Changed

- **`/firecrawl:firecrawl`'s `Use when:` list now opens with typed phrases.** It previously listed
  only *conditions* ("WebFetch returns 403/429", "a page requires JS rendering") — accurate, but
  nothing a user types, and nothing the gate's trigger-drop protection could track.
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
  declaring it only restated the path while registering a second, unnamespaced command — which
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
  for `-t` when `TMPDIR` is unset — so with a bare template and no `-t` the flag
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
  not exist. The skill's `shell: bash` frontmatter does **not** cover this —
  that field governs only the `!` dynamic-context injection evaluated at
  skill-load time, not the Bash tool calls the skill body issues.

## [0.4.1]

### Changed

- Skills with `!` dynamic-context injections now declare `shell: bash` explicitly, per
  the pinned precompute convention — bash-only pipelines must not fall through to a
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
  INFO — the plugin is lazy-install by design) and `FIRECRAWL_API_KEY` presence in the OS
  user environment (presence only — the key value is never printed, logged, or persisted).
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
