# Changelog

All notable changes to the `bug-report` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.7.1]

### Changed

- **Docs:** actionable `/plugin configure` guidance now uses the marketplace-qualified form
  (`<plugin>@<marketplace>`; generated option blocks use `@<marketplace>`) per
  [`docs/extensibility-contract-smoke-tests.md`](../../docs/extensibility-contract-smoke-tests.md)
  Test E (#1360). Targetless references to the flow stay unqualified.

## [0.7.0]

### Removed

- **The bare `/<skill>` alias for this plugin's skills.** Their `SKILL.md` files no longer
  declare a frontmatter `name`. The field is optional and defaults to the directory name, so
  declaring it only restated the path while registering a second, unnamespaced command — which
  the slash-command picker then echoed back as `/plugin:skill (skill)`. Invoke a skill by its
  namespaced command; the command itself is unchanged.

## [0.6.0]

### Changed

- **Filed reports carry the native GitHub Issue Type (`#552` member 1).** All three filing sites
  (the write skill's hand-off step, the README filing section, and both report-footer templates) now
  pass `--type Bug` on `gh issue create`, with the org-only caveat: native Issue Types are an
  org-repo feature, so on personal / non-org repos the flag is dropped and a `type: bug` label is
  added instead when the repo defines one. Previously filed issues carried no type axis at all.

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

### Changed

- **Setup adopts the uniform contract's check-only carve-out** (fleet
  conformance wave, dim 8). The plugin's entire configuration is the native
  `output_dir` userConfig, so `check` is the sole action: it verifies and
  reports, states the machine-private-vs-repository tradeoff instead of
  asking, and routes reconfiguration through Claude Code's native flow with
  the fresh-install-only `--config` semantics stated. Rechecks after
  reconfiguration defer to a fresh session (the rendered value is injected at
  load).

## [0.4.0]

### Changed

- Renamed the `bug-report` skill → `write`. Update any `/bug-report:bug-report` invocations to
  `/bug-report:write`; the plugin ID (`bug-report`) is unchanged, only the skill's leaf name moved.
