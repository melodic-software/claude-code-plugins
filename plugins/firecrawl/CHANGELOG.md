# Changelog

All notable changes to the `firecrawl` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.4.2]

### Changed

- **Core pattern now conforms to the topic-docs ephemeral tier.** Spill files are
  created via the platform temp primitive (`mktemp -t`, never a bare relative
  template, which would resolve against the current directory and drop the file
  inside the consumer's repository) instead of a hand-rolled `date +%s%N` nonce
  under a hardcoded `/tmp`, and self-consumed spill files are
  removed after the selective `Read` (kept only when the user asked for the file
  itself), so a research-heavy session no longer accumulates one orphan file per
  call. The update skill's preservation rule, the command reference, and the eval
  expectations follow the same pattern.

  The Windows gotcha states what actually governs the outcome: where the Bash
  tool is Git Bash, `mktemp -t` resolves through the `/tmp` mount to `%TEMP%`;
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
