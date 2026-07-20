# Changelog

All notable changes to the `toolchain` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.4.4]

### Changed

- Documentation-only: the License section now states the plugin's own MIT
  license inline and no longer points at a `LICENSE` file at the repository
  root, which an installed consumer running from the isolated plugin cache
  cannot reach. No behavior change.

## [0.4.3]

### Changed

- **Presence-gated `dotnet-msbuild:*` build-diagnostics references in `context/dotnet.md` reframed as
  .NET-ecosystem forward references.** The `## Marketplace plugin skills for build diagnostics (invoke
  only when installed)` list gains a lead-in that frames its `dotnet-msbuild:*` skills as applicable
  when your stack is .NET and as forward references to the planned `dotnet-*` plugin family — invoked
  only when the plugin is installed, otherwise falling back to the section's own prose remediation and
  binlog gotcha (the generic path stays first-class). Framing only: no skill reference was removed,
  renamed, or genericized, and no command string was altered. Aligns this file with the presence-gated
  forward-reference convention the merged `testing` (#491) and `verification` (#526) siblings adopted,
  per the ratified #412 disposition. Addresses #412; the sibling `implementation` finding (#405) tracks
  the same pattern separately.

## [0.4.2]

### Fixed

- **Remote selected from those present, not assumed `origin`.** The clean-working-tree branch-diff
  fallback in `/toolchain:check` and `/toolchain:lint` resolved the remote from the current branch's
  `branch.<name>.remote`, but when that was unset (an unpushed feature branch) it forced `REMOTE=origin`
  unconditionally. In a clone made with a differently named remote (`git clone -o vendor`) that has no
  `origin` and no pushed upstream, `origin` does not exist, so `git symbolic-ref refs/remotes/origin/HEAD`
  and every subsequent probe failed and the branch diff was skipped ("branch diff unavailable") — the
  `origin` fallback the 0.4.1 note claimed "still resolves" a `git clone -o vendor` did not hold for the
  not-yet-pushed case. Both call sites now probe candidate remotes in priority order — the branch's
  tracking remote, then `origin` if present, then the rest — and select the first whose default branch
  resolves to a locally available `refs/remotes/<remote>/<branch>` tracking ref. This also skips a remote
  that was added but never fetched (whose `git ls-remote` default-branch query succeeds over the network
  but leaves no local ref for `git merge-base`) in favor of a later remote that has one, rather than
  committing to the alphabetically first remote and bailing. The common tracking-remote case still
  short-circuits on the first candidate with no extra network calls, and detection still degrades
  gracefully (skips the branch-diff path) when no candidate yields a local default branch. Candidate
  remote names are option-parse-safe: the tracking-ref checks use the fully-qualified
  `refs/remotes/<remote>/<branch>` form and the `git ls-remote` probe passes `--end-of-options`, so a
  Git-legal remote whose name begins with a dash (`git clone --origin=-x`) is not misparsed as a command
  option and skipped. A cross-plugin shared default-branch helper remains the broader fix tracked by
  #436/#442.
- **Remote-prefix strip no longer breaks on `#` in a remote name.** The default-branch resolution
  stripped the `$REMOTE/` prefix with `sed "s#^$REMOTE/##"`, whose `#` delimiter collides with a
  `#` in the remote name (a Git-legal character), corrupting `DEFAULT_BRANCH` and silently skipping
  the branch diff. Both call sites now strip the prefix with the `${DEFAULT_BRANCH#"$REMOTE/"}`
  parameter expansion, which treats the remote name literally regardless of its characters.

## [0.4.1]

### Fixed

- **Default branch resolved by detection, not assumption.** The clean-working-tree branch-diff
  fallback in `/toolchain:check` and `/toolchain:lint` carried a bare `<default-branch>` placeholder
  with no resolution guidance, so the model would likely guess `main`/`master` — a baked repo
  assumption the convention-resolution discipline forbids. Both call sites now resolve the tracked
  remote (`branch.<name>.remote`, falling back to `origin` — never a hardcoded remote name, so a repo
  cloned with a different remote name still resolves), then the default branch via
  `git symbolic-ref --short refs/remotes/$REMOTE/HEAD` (with the `$REMOTE/` prefix stripped), falling
  back to a `git ls-remote --symref "$REMOTE" HEAD` query of that remote's own default branch, matching
  the infer-don't-guess discipline applied elsewhere. The resolution is now an explicit
  assignment that runs before `git merge-base` consumes it (previously it was descriptive prose,
  leaving `$DEFAULT_BRANCH` unset so the documented command expanded to `git merge-base "" HEAD`);
  `merge-base` runs against the remote-tracking ref `$REMOTE/$DEFAULT_BRANCH`, which resolves in a
  clean checkout without a local branch of that name. When no default branch resolves, the
  branch-diff path is skipped rather than guessed.

## [0.4.0]

### Changed

- **`/toolchain:setup` adopts the uniform setup contract** (fleet conformance wave) — delivering the
  `apply` action the 0.3.0 topic-docs note recorded as the contract's follow-on. The skill now splits
  into a read-only `check` action (default) that reports which ecosystems are configured, each one's
  resolved build/test/lint command surface, and the topic-docs concern file — validating the tracked
  files against the contract's `ecosystem.schema.json`, treating an unconfigured ecosystem as INFO
  (the bundled rung-4 default resolves) and FAILing only a configured-but-broken file (schema-invalid,
  or excluded by `.gitignore`) — and an `apply` action that infers and writes the tracked config. The
  previous interview (infer per-ecosystem commands, write `.claude/ecosystems/*.yaml`, offer
  `.claude/topic-docs.yaml`) becomes `apply`'s interview path; `apply <ecosystem>` scopes the run to
  one ecosystem and writes an unambiguous inference non-interactively. The per-ecosystem inference,
  schema conformance, overlay convention, and topic-docs handling (including the deferred GitBook
  backend) are preserved unchanged.

## [0.3.0]

### Changed

- Adopt topic-docs contract 2.0.0 (visibility semantics): `reference/topic-docs.md` clarifies the
  contract's visibility mechanisms are consumer-repo root materializations outside the concern
  file's schema, and `/toolchain:setup` does not write them today (a setup-skill apply action is
  the contract's recorded follow-on).

## [0.2.0]

### Changed

- **BREAKING: `/toolchain:build` renamed to `/toolchain:check`.** The skill runs build + test + lint
  as a deterministic pass/fail gate, and per the marketplace naming grammar `check` = gate; "build"
  is also a null phase for several covered ecosystems (Python, Markdown). The skill directory,
  frontmatter `name`, and every repo-wide reference move together; no `renames`-map entry is added
  (clean breaking change while the marketplace is settling). Invoke `/toolchain:check` where you
  previously invoked `/toolchain:build`; behavior, arguments, and the resolution ladder are unchanged.

## [0.1.1]

### Fixed

- **`/toolchain:setup` reports `vault_backend: gitbook` as deferred and non-writable.** Offering
  or preserving the key now cites the ADR
  (`docs/adr/0001-defer-gitbook-as-knowledge-vault-backend.md`) and states that durable writes still
  target `docs`; the skill never configures or tests a GitBook API, MCP, or Git Sync writer.

## [0.1.0]

### Added

- Initial release — three skills extracted from the `implementation` plugin (skill names unchanged):
  `/toolchain:build` (polyglot build + test + lint for changed files, resolved through the four-rung
  ecosystem-commands ladder), `/toolchain:lint` (lint + format only, plus the `yaml` and `cross-cutting`
  surfaces), and `/toolchain:setup` (re-runnable writer of the tracked `.claude/ecosystems/*.yaml`
  command config and the offered `.claude/topic-docs.yaml` concern file).
- Bundled reference: the resolution ladder, the schema-conformant per-ecosystem portable defaults under
  `reference/ecosystems/`, and the plugin-local `reference/topic-docs.md` binding that `/toolchain:setup`
  reads to offer the topic-docs concern file.
- Cross-plugin references to the `verification` plugin's `/verification:confirm` are informational and
  degrade gracefully — this plugin never hard-depends on any other plugin.
