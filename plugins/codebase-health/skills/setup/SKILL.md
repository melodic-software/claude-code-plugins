---
description: "Verify and configure the codebase-health plugin for this repository. check inspects the audit-dimension config read-only across its layers (the dimensions_file userConfig option, the tracked team codebase-health.md in the convention home, the personal override), and reports presence, dimension source lists and tracked-not-ignored; apply interviews the user, infers audit targets from the repo layout, and writes the team file. Use when: 'set up codebase-health', 'is codebase-health configured', 'configure the audit', 'codebase-health setup', the audit skill reports missing or thin config, or audit dimensions need tuning. Re-runnable. Safe to invoke again to reconfigure."
argument-hint: "[check|apply]"
user-invocable: true
disable-model-invocation: true
---

## Purpose

Verify and manage the consuming repo's tracked audit-dimension config at
`<home>/codebase-health.md` so `/codebase-health:audit` runs deterministically instead of
re-inferring targets every run.

The config is optional: with none, the audit re-infers its targets each run, so its absence is a
reported INFO, never a FAIL. `check` inspects the effective merged config read-only; `apply`
interviews and writes the team file, then re-runs `check`. No argument or `check`
runs the check; `apply` runs the check first, then the interview-and-write flow.
Idempotent: re-running reads the existing config and offers updates rather than overwriting blind.

## The config layers

The layers, `<home>`, the root rule, and the merge semantics live in
`${CLAUDE_PLUGIN_ROOT}/reference/config.md` (one Read of that file; this skill implements
it and does not restate it). In short: `userConfig` (the `dimensions_file` option) → team
(`<home>/codebase-health.md`, tracked) → personal (`<home>/codebase-health.local.md`, gitignored),
globs unioned and example-claims concatenated, with an empty-list opt-out. Anchor every
repo-relative read at the repo root (`git rev-parse --show-toplevel`), never at the CWD.

The `userConfig` layer, as Claude Code substituted it into this skill (empty, or a literal
`${user_config.…}` placeholder, means unset):

| Option | Value |
|---|---|
| `dimensions_file` | `${user_config.dimensions_file}` |

This skill writes only the team file (`<home>/codebase-health.md`). It never writes `userConfig`,
user settings or `pluginConfigs`. The user sets the option through Claude Code's native flow,
interactively with `/plugin configure codebase-health@<marketplace>` or by a headless route, as the
marketplace's plugin-reconfiguration convention gives them in
[§ The routes](../../reference/plugin-reconfiguration.md#the-routes)
(it owns the verified-version record). Apply the scope and failure-signal caveats in its
[§ Caveats every setup skill's short form carries](../../reference/plugin-reconfiguration.md#caveats-every-setup-skills-short-form-carries).
Whenever this skill gives the routes, read both sections and print what they give, the fallback
route, its behavior on an already-installed plugin and the scope to pass included, rather than only
naming them, and leave out the verified-version record. Never uninstall to reconfigure; that
section links what an uninstall deletes. Then rerun `check` in a **fresh session**, since a
same-session `check` can still show the old value, and report only an observed value.

- **Pointer**: for the headless command's flags, how it reports a saved or refused value, and when
  a saved value applies, fetch
  [plugin CLI reference § plugin configure](https://code.claude.com/docs/en/plugins/cli-reference#plugin-configure)
  live.

## `check` (read-only)

Inspect the effective merged config and report a PASS/FAIL/WARN/INFO table with one remediation
line per FAIL. Modify nothing, and do not run an audit. That is `/codebase-health:audit`.

1. **Layer presence (effective, across layers)**. Resolve `<home>` and classify the root as the
   config contract says, then report each layer: the `dimensions_file` option and the file it
   names, `<home>/codebase-health.md`, and `<home>/codebase-health.local.md`. Report the *effective
   merged* result honoring opt-outs (dimensions present, glob counts, example-claim counts) and
   which layer contributes what. No layer present → INFO: the audit re-infers targets each run;
   `apply` writes `<home>/codebase-health.md` to make the run deterministic. When the
   `dimensions_file` cannot be read, WARN it was not considered rather than presenting the readable
   layers as the whole effective config.
2. **Retired conventions.** Run
   `bash "${CLAUDE_PLUGIN_ROOT}/lib/check-retirements.sh" --manifest "${CLAUDE_PLUGIN_ROOT}/retirements.yaml" --root "<root>"`,
   with `<root>` the path `git rev-parse --show-toplevel` printed. Never leave out `--root`: the
   helper otherwise checks `${CLAUDE_PROJECT_DIR}` first, a subdirectory when the session started
   in one. When the root does not resolve, the root rule already skips these layers: skip this
   step and say so. Exit 0 → PASS (any `report-only` TSV rows printed as INFO history; they are no
   longer read as config layers and cleanup is not offered). Exit 1 → one finding per active TSV
   row: `migrate` is FAIL, `delete`/`remove-line` WARN, `report-only` INFO; remediation is `apply`.
   Exit 2 → FAIL, never silent. Bash unavailable → report the step UNKNOWN with remediation, never
   green.
3. **Dimension source lists**. For each dimension present in the team file, its
   declared source lists parse and name real paths/globs. A dimension whose source list is
   malformed or fails to parse is FAIL, naming it. A dimension deliberately zeroed (empty source
   lists) by the personal or `userConfig` layer is INFO (an opt-out), reported as removed, not
   broken.
4. **Tracked, not ignored**. A present team file (`<home>/codebase-health.md`) must be committed to
   be team-shared: run `git check-ignore -v <team file>`; a non-empty result is FAIL with the
   matching pattern. A personal file (`<home>/codebase-health.local.md`) is expected to be ignored:
   INFO when ignored, FAIL when tracked or staged. The `dimensions_file` sits outside the worktree,
   so no git verdict applies to it.
5. **Other-layer divergence**. INFO: when the personal or `userConfig` layer changes the team
   file's effect (adds globs, or opts a dimension out with empty source lists), say so explicitly,
   since `apply` writes only the team file.

## `apply` (idempotent)

Run `check`, then interview and write the team file. Never create, write,
edit or rewrite `<home>/codebase-health.md` by any tool (Write, Edit,
or a Bash redirect, `tee`, `sed -i` or interpreter), until the user confirms the proposed changes
in a later turn. Even when every value looks unambiguous, the turn that drafts the config ends by
presenting it and asking, not by writing.

1. **Start from the effective config `check` just reported.** This step writes only the *team*
   file, so name what the personal or `userConfig` layer contributes. When a personal or
   `userConfig` opt-out zeroes a dimension, a team-scope re-enable will not restore it on this
   machine, because that layer keeps removing it; prompt the user to remove or update the opt-out
   in that layer too. The interview proposes changes against that baseline, and nothing is dropped
   without the user confirming.
2. **Explore the repo to draft defaults.** Before asking anything, infer candidates:
   - **documentation** primary-sources: doc directories (`docs/`, `README.md`), agent-instruction
     files (`AGENTS.md`, `CLAUDE.md`), ADR directories, convention docs.
   - **configuration** primary-sources: build config, lint config, CI workflows, git-hook config,
     detected from what actually exists.
   - **code-quality** primary-sources: source roots; verification-sources: test roots **plus the
     same source roots**, a cross-file DRY/SOLID claim is validated by reading peer source files,
     which a discovery agent can only read when they are in `verification-sources` (the fence forbids
     the other primary-source files). Omitting them makes cross-file findings unreachable.
   - **architecture** primary-sources: dependency manifests + architecture docs;
     verification-sources: analyzers / architecture tests where present **plus the dependency
     manifests and source roots**. Dependency-direction and boundary claims need peer manifests
     readable, for the same fence reason.
3. **Interview, one decision at a time.** Present each dimension's drafted globs with a
   recommendation; let the user accept, edit, or remove the dimension. Offer custom dimensions
   last ("anything else this repo should audit as its own dimension?").
4. **Draft example-claims.** For each accepted dimension, read one or two representative
   primary-source files and propose 2–4 concrete `{ claim, verify-via }` rows drawn from real
   sentences in them. Concrete rows teach the discovery pass what drift looks like in this repo, the highest-value part of the config. The user approves or edits each row.
5. **Write the config, once the user has confirmed it.** Materialize `<home>/codebase-health.md`,
   creating `<home>` when missing, following the structure in
   [`${CLAUDE_PLUGIN_ROOT}/skills/setup/templates/config-template.md`](templates/config-template.md) (replace every placeholder comment
   with real values; drop unused placeholder rows). Never write it under `.claude/`.
6. **Verify after remediation.** Re-run the `check` probes on the written file. Dimension source lists
   parse and name real paths, and both halves of the tracked-file pair hold:
   `git check-ignore -v <home>/codebase-health.md` reports no match (a match is FAIL; surface the
   pattern and offer to fix `.gitignore` before reporting success) and
   `git ls-files --error-unmatch <home>/codebase-health.md` exits 0 (non-zero means un-ignored but
   still untracked, the guaranteed state right after a fresh write, so report "written but
   untracked: commit it to share with the team", never success). Then **offer the personal
   override convention**: personal overrides go in `<home>/codebase-health.local.md`; recommend the
   consumer add the recursive `<home>/**/*.local.*` line (written with the bound home) to
   `.gitignore` if not already covered, but never edit their `.gitignore` yourself. Dimensions for
   every repository go in the file the `dimensions_file` option names.

Re-running `apply` after everything passes changes nothing and reports "already configured".

## Output

`check`: the PASS/FAIL/WARN/INFO table with per-layer provenance. `apply`: a tracked
`<home>/codebase-health.md`, the re-run check result, and a
one-paragraph summary of what was written and how to re-run this setup to reconfigure.

## What this skill does not do

- Run an audit. That is `/codebase-health:audit`. `check` only inspects config.
- Write `userConfig`, user settings, `pluginConfigs`, the personal override, or the consumer's
  `.gitignore`.
- Write into the plugin directory or the plugin data directory. Configuration lives in the
  consumer's team and personal files and the user's own `dimensions_file`.
