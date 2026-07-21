# Changelog

All notable changes to the `toolchain` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.9.0]

### Added

- **`lychee-offline` added to the `cross-cutting` ecosystem default.** The bundled
  `reference/ecosystems/cross-cutting.yaml` `check-cmd` now runs `lychee --offline --no-progress
  './**/*.md'` alongside `typos`/`gitleaks`/editorconfig-checker — on-disk link/anchor integrity,
  network-free (`--offline` skips external URLs; only local file and fragment targets are verified).
  Opt-in follows the same per-tool-config pattern as the existing cross-cutting tools: an optional
  `lychee.toml` at repo root customizes the ruleset (exclusions, fragment-check mode), absent means
  lychee's own defaults. `install-hint` gains the `lycheeverse.lychee` winget package / `lychee`
  brew formula. Per Brief item 3, `docs/topics/lint-static-analysis-gaps/PLAN.md`. Closes #833.

## [0.8.0]

### Added

- **`go` ecosystem batch default** (`build-cmd: go build ./...`, `test-cmd: go test ./...`,
  `check-cmd`/`fix-cmd: golangci-lint run [--fix] ./...`, `project-discovery: ["go.mod"]` for
  nested-module coverage, a `go-mod-tidy-drift` gate via `go mod tidy -diff`) added to
  `reference/ecosystems/go.yaml` — closes the Go toolchain CI/local-parity gap. Gated behind an
  `opt-in` key (`.golangci.yml`/`.golangci.yaml`/`.golangci.toml`/`.golangci.json` presence) —
  empirically verified golangci-lint v2 with no config file still applies its own fixed "standard"
  linter preset unconditionally, the same imposed-unconfigured-opinion risk the 0.6.0 dotnet gate
  addressed.
- `context/go.md` reference file — Go-specific gotchas (`./...` module-boundary behavior,
  golangci-lint's home-directory config fallback, `go mod tidy -diff`'s Go 1.23+ requirement).
- `docs/conventions/ecosystem-commands/examples/go.yaml` worked-example fixture.
- `go`/`golang` added to `/toolchain:check` and `/toolchain:lint`'s covered-ecosystem lists and
  alias tables.

## [0.7.0]

### Added

- **`pyright` added to the bundled Python ecosystem default's `check-cmd`.** Local `/toolchain:check`
  now runs `uv run pyright` alongside the existing ruff lint/format check, closing the gap where CI
  gated pyright but the local batch was ruff-only. Rung-4 fallback only — a consumer's own
  `.claude/ecosystems/python.yaml` overrides `check-cmd` key-by-key and is unaffected. `fix-cmd` is
  unchanged (pyright has no fix mode). `context/python.md` documents the default standard-mode gotcha
  for untyped projects.

## [0.6.0]

### Added

- **dotnet ecosystem `opt-in` key** (`.editorconfig` with a `[*]` or C#-glob
  section, walked from the changed file up to the repo root or a
  `root = true` marker, whichever comes first — empirically verified against
  dotnet SDK 10.0.302 that a universal `[*]` section governs `dotnet format`'s
  output on `.cs` files just as a `[*.cs]` section would, that a
  `.editorconfig` with only unrelated globs has zero effect, and that a
  nested `root = true` marker genuinely stops EditorConfig discovery before
  it reaches an outer section) — closes the one lint-bearing ecosystem gap
  where a config-presence opt-in didn't exist.
- **`/toolchain:check` now honors `opt-in`** for the lint phase (it never did
  before — `dotnet format --verify-no-changes` ran unconditionally whenever
  `.cs`/`.csproj`/etc. files changed, regardless of whether the repo
  configured any style/analyzer preferences). Build and test are unaffected;
  only the lint phase is gated. This binary run/skip treatment applies to
  single-condition ecosystems (dotnet, python); multi-tool ecosystems whose
  `opt-in` bundles several sub-tools into one opaque command string (bash,
  cross-cutting) are unchanged from prior behavior — a bundled command
  cannot be partially suppressed, a known limitation documented in
  `check/SKILL.md`'s Gotchas.
- **Visible `skip (opt-in unmet: ...)` status** in both `/toolchain:check`
  and `/toolchain:lint` results tables — a single-condition ecosystem whose
  `opt-in` isn't met is now reported, not silently dropped from output as
  it previously was in `/toolchain:lint` for every opt-in-bearing ecosystem.

### Fixed

- dotnet's lint/format check no longer imposes Roslyn's built-in formatting
  defaults on a repo that never configured `.editorconfig`/analyzer
  preferences — matching the same "never impose an unconfigured opinion"
  posture already applied at the hook layer by `ruff-format`/`typos-format`.

## [0.5.2]

### Changed

- Skills with `!` dynamic-context injections now declare `shell: bash` explicitly, per
  the pinned precompute convention — bash-only pipelines must not fall through to a
  PowerShell host.
## [0.5.1]

### Changed

- Documentation-only: the License section now states the plugin's own MIT
  license inline and no longer points at a `LICENSE` file at the repository
  root, which an installed consumer running from the isolated plugin cache
  cannot reach. No behavior change.

## [0.5.0]

### Removed

- **`/toolchain:setup` no longer offers the topic-docs concern file — relocated to the lifecycle
  plugins that own it.** Setup step 6 wrote `.claude/topic-docs.yaml`, a consumer config resolved by
  the `implementation` and `verification` plugins for artifact placement; no `/toolchain:*` skill reads
  it, so this build/test/lint plugin was writing another plugin's consumer config. Setup is now scoped
  solely to the ecosystem command surface it owns (the tracked `.claude/ecosystems/*.yaml` files):
  `check` no longer reports the topic-docs concern and `apply` no longer offers it, and the orphaned
  `reference/topic-docs.md` binding that only step 6 read is removed. The shared concern file is offered
  by each lifecycle plugin's own setup — `/discovery:setup`, `/planning:setup`, and the new
  `/verification:setup` — independent of whether the others are installed. Closes #263.

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
