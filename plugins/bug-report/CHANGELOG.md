# Changelog

All notable changes to the `bug-report` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.8.0]

### Added

- **`scan` — proactive bug hunting over resting code.** A third skill,
  `/bug-report:scan`, that looks for defects **nobody has observed yet**: no diff, no failing test,
  no stack trace, no comment marker required. One invocation is one bounded pass — hunt a target
  (`/bug-report:scan <path|feature|diff>`) or, bare, the next lane in a rotation, then stop. Findings
  come out in this plugin's existing five-field shape, each labeled `reproduced` or
  `verified-by-reading`.
- **Recall and precision are separated into two stages.** Per-lens hunter subagents are told to be
  generous; a **separate fresh-context verification gate** is told to refute, and only candidates
  that survive it reach the report. The agent that discovers a candidate never grades it, refuted
  candidates are retained in the report with their refuting argument rather than silently dropped,
  and refill waves after a fully refuted wave are capped. Five V1 lenses ship in
  `skills/scan/context/lenses.md`: contract-vs-body mismatch, boundary and edge cases, cross-file
  consistency drift, state and concurrency hazards, and git-hotspot-guided reads.
- **Bare invocation is read-only toward the repository; filing needs `--track`.** A bare run never
  edits, branches, pushes, or files. `--track` files verified findings through the `work-items` seam
  as **raw intake** — duplicate search first, `needs-triage` resolved from the consumer's live label
  set across both label axes, no label creation, and a body provenance line the lane cursor later
  reads. It degrades to report-only with a printed notice when no tracker resolves. `--dry-run`
  persists nothing and advances nothing.
- **Rotation state is derived statelessly, never from `.work/`.** Bare runs pick their lane down a
  three-rung ladder — tracker filing history, then the cursor block in the newest persisted report
  under `${CLAUDE_PLUGIN_DATA}`, then a deterministic date-derived floor — so a fresh clone rotates
  correctly with zero stored state. The run reports which rung it used. Per-run budget: stop at 3
  verified findings or a complete lane sample, at most 10 candidates per wave, at most 2 refill
  waves. A lane sample being complete is never reported as the lane being bug-free.
- **`reference/config.md` — the single home for the `.claude/bug-report.md` key contract.** Layers
  and resolution order, per-key merge semantics declared beside the keys they govern (`lanes`
  concatenate with an explicit empty-list opt-out; `filing_posture` is a nearest-wins scalar), the
  file format, and the key partition rule that keeps `output_dir` a native `userConfig` value and out
  of the cascade file. Both `scan` and `setup` cite it; neither restates it.

### Changed

- **`setup` is no longer check-only: it is now `check | apply`.** The plugin gained a second
  configuration surface — the tracked, cascade-layered `.claude/bug-report.md` that `scan` reads for
  its lanes and filing posture — which dissolves the check-only carve-out 0.5.0 adopted. `check`
  still inspects both surfaces read-only; `apply` writes or updates that one tracked file and
  nothing else, drafting lane candidates from the repository, confirming them one decision at a
  time, updating conservatively rather than overwriting, and verifying against the file on disk
  afterward. `output_dir` is unchanged: it stays a personal `userConfig` value that Claude Code's
  own configuration prompt owns, and this skill still never writes it.
- **Convention registries record the new surfaces.** The config-cascade convention gains a
  `bug-report` implementers row, and the plugin-data report-keying row now covers `scan` as a
  slug-keyed producer of findings reports and cursor metadata alongside `write`'s `--file` reports.

## [0.7.4]

### Changed

- **setup:** normalized restated setup-contract prose (preamble, probe-ladder
  opening, never-writes boundary, and/or headless-reconfigure recipe as present) to the
  canonical fleet wording, keeping the operable text inline with a provenance-only citation
  (whole-repo extract-ssot batch, #2698).

## [0.7.3]

### Fixed

- **`setup` skill:** the headless reconfiguration route no longer prescribes `claude plugin
  uninstall` + reinstall. That instruction rested on an unversioned claim that `claude plugin
  install --config` is ignored once a plugin is installed, and following it dropped the plugin's
  whole stored `pluginConfigs` entry, resetting every declared option to its manifest default.
  On Claude Code 2.1.240 a plain `claude plugin install … --config` against an already-installed
  plugin prints `already installed` and still writes the value, so that is now the documented
  route — stamped with the CLI version it was verified against
  ([#3111](https://github.com/melodic-software/claude-code-plugins/issues/3111)). This skill is
  check-only — it has no `apply` action — and `check` still closes by telling the reader to
  rerun it in a fresh session and report the observed value, never asserting an unobserved
  change.
- **Docs:** the generated options block's headless route no longer implies `--config` applies
  only at install time, and now carries the CLI version its claim was verified against
  ([#3111](https://github.com/melodic-software/claude-code-plugins/issues/3111)). The block also
  now separates the write from its effect: the value is stored immediately, but hooks are handed
  their `CLAUDE_PLUGIN_OPTION_*` at session start, so a check run in the same session still
  reports the old value and that is not a failed write. Two upstream links that pointed at empty
  backward-compatibility anchors on the settings page were repointed at the headings that hold
  the content.

## [0.7.2]

### Changed

- **`setup`: the "write a report instead" boundary names the Skill tool (#3002).** "use
  `/bug-report:write`" became "invoke `/bug-report:write` via the Skill tool". Wording only — the
  boundary itself is unchanged. Follows the invocation-mode rubric's cross-skill phrasing rule,
  now unconditional after the fleet sweep.

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
