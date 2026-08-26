---
description: "Configure the source-control plugin. check (read-only): report the effective commit-subject / PR-title convention merged across its user-global, team, and personal-overlay layers, and the babysit-prs userConfig surface (effective config, branch-protection posture, Windows long paths, lane-script permission reachability). apply: interview the repo and write the convention config to a chosen layer, and walk the sanctioned babysit reconfigure paths. Use when: 'set up source-control', 'configure commit convention', 'source-control setup', 'what commit format does this repo use', 'set my personal commit convention', 'override the team convention locally', 'configure babysit', 'check babysit config', or /commit, /pull-request, or /babysit-prs report missing configuration. Actions: check (read-only verification, default) | apply (write the convention config; document the babysit config paths). Re-runnable and safe."
argument-hint: "check | apply [layer=user|team|local] [subject_pattern=<anchored-regex | 'Conventional Commits'>]"
user-invocable: true
disable-model-invocation: true
---

## Purpose

Inspect and configure the source-control plugin per the uniform setup contract
(`docs/PLUGIN-PHILOSOPHY.md` "Setup is explicit and repeatable" in the marketplace repository):
`check` reports the effective configuration, `apply` writes it. Two configuration surfaces:

1. The commit-subject / PR-title convention config, layered across a user-global file, the tracked
   team file, and a gitignored personal overlay and merged per key by
   [../../reference/config-resolution.md](../../reference/config-resolution.md). Resolved first by
   `/source-control:commit` and `/source-control:pull-request` before they fall back to inference or
   the bundled Conventional Commits default. Conventional Commits is genuinely optional, some orgs
   gate on ticket-prefixed subjects (`WEB-123: description`), so the plugin ships a sensible
   default, not a hardcoded requirement.
2. The `/source-control:babysit-prs` native `userConfig` surface (not a tracked repo file).

Idempotent: re-running reads the existing configuration and offers updates rather than overwriting
blind. The plugin ships a working zero-config default (Conventional Commits / inference for the
convention; the safe babysit tier over your own PRs), so an unconfigured surface is **INFO**, never
FAIL.

Action routing: no argument or `check` runs the check; `apply` runs the check first, then
remediation. When `apply` carries a `subject_pattern=` argument it writes the convention
non-interactively; with no arguments in an interactive session it runs the convention interview
(spoke below). `layer=` selects which config layer `apply` writes, defaulting to the tracked team
file.

## `check` (read-only)

Report a PASS/FAIL/INFO table across both surfaces; modify nothing.

### Convention config

Anchor at the repo root: resolve `REPO_ROOT` once, `${CLAUDE_PROJECT_DIR}` when set, otherwise
`git rev-parse --show-toplevel`, and use that literal resolved path for every repo-relative read
below, never a cwd-relative path (invoked from a nested directory, a cwd-relative path would inspect
the wrong file). Re-resolve `REPO_ROOT` at the top of every self-contained Bash call, a fresh shell
does not carry a prior call's variables.

Read all three layers, then report **one effective-configuration table**, a row per key, its
resolved value, and which layer supplied it, followed by a per-layer presence line. Never present a
single layer's value as the effective convention; a reader who cannot see which layer won cannot
tell why `/source-control:commit` behaves as it does.

```text
key                        value                       won by
subject_pattern            ^[A-Z]+-\d+: .+             team
pr_title_pattern           Same as subject_pattern      team
trailer_policy             none                         local overlay
pr_body_attribution        none                         local overlay
pr_body_required_sections  Summary, Test plan           plugin default
```

`pr_body_required_sections` is a **list**-valued key (like `type_list`, and unlike every scalar row
above it), render it comma-joined for this report regardless of how many lines the winning layer's
file spells it across. When every layer leaves it unset, the row still resolves, to the plugin's
portable default, `Summary` and `Test plan`, so `won by` reads `plugin default` rather than the row
going blank; this is the one key whose "no layer sets it" state is itself a reportable, named value,
not a bare absence. A winning layer declaring the literal keyword `none` renders the row's value as
`none (no required sections)` with that layer in `won by`, a resolved value distinct from the unset
row above, per config-resolution.md.

Per-layer verdicts:

- **User-global** (`~/.claude/source-control.md`): present → report which keys it contributes;
  absent → INFO. It is outside the repo, so no git check applies to it.
- **Team** (`REPO_ROOT/.claude/source-control.md`): present → PASS. **FAIL** when excluded by
  `.gitignore`. Teammates would never receive the shared convention; report the matching rule.
  Absent → INFO, remediable by `apply`.
- **Local overlay ignore rule** (`.claude/*.local.*`, covering
  `REPO_ROOT/.claude/source-control.local.md`): probe the ignore rule whether or
  not the overlay file exists. The rule's job is to be in place **before** the
  first overlay is written; conditioning the probe on the file already existing
  is the window that produces the exposure. Missing rule → FAIL, remediable by
  `apply` (which writes the line at team-layer bind, not only at `layer=local`).
  Probe with `git check-ignore --no-index -v -- .claude/source-control.local.md`
  (the path does not need to exist). A match counts only when `-v` names a
  repository `.gitignore` as the source. `$GIT_DIR/info/exclude` and
  `core.excludesFile` are operator-local and do not protect a teammate.
- **Local overlay file** (`REPO_ROOT/.claude/source-control.local.md`): when
  present, PASS only when an ignore rule matches it **and** it is not in the
  index. Two distinct failures hide behind one symptom and need different
  remediations, so probe them separately. See the two-probe form under
  `apply`. Absent file is OK once the ignore rule itself is present.

**FAIL** when the *effective* `subject_pattern` is not machine-checkable. It must be either the
literal keyword `Conventional Commits` or an anchored regex (`^…`-style); a plain-language
description cannot be evaluated by `/source-control:commit` or `/source-control:pull-request`. Name the layer that supplied the
offending value.

With **all three layers absent**: INFO, no declared convention; `/source-control:commit` and `/source-control:pull-request` infer
from the repo's own `CLAUDE.md`/rules/commit-msg hook, then fall back to the bundled Conventional
Commits default. The remediation is `apply` to persist a convention.

**Neutral-SSOT drift probes.** When a `convention_source` pointer is declared or a neutral file is
resolved (explicit pointer, or the well-known default `docs/conventions/source-control/commit-convention.yml`),
`check` surfaces two drift conditions the resolver otherwise handles silently. Round-trip the
enforcement resolver (`lib/resolve-convention-pattern.sh <REPO_ROOT> subject_pattern`) and read its
diagnostics:

- **Broken pointer / neutral file → FAIL.** A declared `convention_source` whose target is missing,
  or a resolved neutral file that fails the seam's safety/dialect/empty-key contract, disables
  enforcement fail-closed. This is easy to miss because nothing signals it until a commit is
  unexpectedly blocked or allowed, so surface it here, naming the resolver's diagnostic and the
  remediation (restore the file, fix the pointer, or `apply` to rewrite it).
- **Shadowed markdown → WARN.** A neutral file resolves (via pointer or the well-known default) **and**
  `.claude/source-control.md` still carries a markdown-H2 `subject_pattern`/`pr_title_pattern` for the
  same key: the neutral value wins (rungs 1–2 over rung 3) and the stale markdown is inert but
  misleading. Recommend `apply` to retire the duplicate (migration removes it), per
  [reference/apply-convention.md](reference/apply-convention.md) "Migration retires duplicates".

### Babysit config

Read [reference/babysit-config.md](reference/babysit-config.md) when `check` or `apply` touches a
`babysit.*` key: it owns every key, its default, its validation, and what `apply` writes. The
`check` and `apply` flows above name which keys they visit, not what the keys mean.

## `apply` (idempotent)

Run `check` first. Then write the convention (surface 1) and walk the sanctioned babysit
reconfigure paths (surface 2).

### Convention config

The full write path is normative in
[reference/apply-convention.md](reference/apply-convention.md). Read it before writing any layer.
In brief:

- **Target layer.** `layer=` picks `user` / `team` (default) / `local`; infer the layer from the
  request's wording and state the pick before writing, the wrong layer either misses teammates or
  commits a personal preference to shared history.
- **Non-interactive** (`subject_pattern=`): an in-place *update*, never a fresh file. Carry every
  independent key, recompute derived keys (`type_list`, `pr_title_pattern`), reject a
  non-machine-checkable value, and for an overlay omit requested keys the layers below already
  resolve identically.
- **Interactive:** the interview. Anchor at `REPO_ROOT`, read all three layers first, infer before
  asking (declared prose, commit-msg hooks, commit-history consensus over the configurable
  `setup_inference_*` window), interview one decision at a time with a recommendation first, settle
  the optional keys (`trailer_policy`, `pr_body_attribution`, `pr_body_required_sections`,
  including the `none` value and the omission-never-resets trap), write the template, verify per
  layer (team = tracked and staged; local = ignored and untracked, two independent probes; user =
  no git command at all), and report the new **effective merge**, not just what was written.

- **Neutral SSOT:** a `team` write may materialize a tool-agnostic flat-scalar YAML file other tools
  consume too. It defaults to the well-known path `docs/conventions/source-control/commit-convention.yml`
  (resolved with no pointer); `## convention_source` is written only to relocate it. **Recommended as
  the default when a second enforcement consumer exists** (commit-msg hook, CI title check), markdown-only
  when this plugin is the sole consumer; migration retires markdown keys the neutral file takes over
  (spoke section "Neutral convention SSOT").

Every step's exact contract, the interview steps, the written-file template, the per-layer
verification scripts, and the failure remediations, lives in the spoke; this summary never
overrides it.

### Babysit config

Read [reference/babysit-config.md](reference/babysit-config.md) when `check` or `apply` touches a
`babysit.*` key: it owns every key, its default, its validation, and what `apply` writes. The
`check` and `apply` flows above name which keys they visit, not what the keys mean.

## Output

A convention config file at the chosen layer (when `apply` wrote one), plus the resulting effective
merge with the winning layer per key, a one-paragraph summary of where the convention came from
(inferred or user-declared), and, for babysit, the `check` probe report and the reconfigure path
used. `check` alone reports the effective configuration across both surfaces and changes nothing.

## Gotchas

Skill-behavior failure patterns hit in real runs. Add to this section when new ones are discovered.

- **Omitting a key never resets it.** Per-key fallthrough means a section left out of a higher
  layer inherits the lower layer's value. Resetting to the portable default *over* a lower layer
  that sets the key requires writing the explicit default value; omission only inherits (the
  `apply` interview states this when it applies).
- **`none` and absence are different states** for `trailer_policy`, `pr_body_attribution`, and
  `pr_body_required_sections`: absence falls through (ultimately to the bundled default), `none` is
  a resolved opt-out that wins its layer's per-key override.
- **Gate inference on the resolved value, never file presence.** A `source-control.md` layer that
  contributes only other keys leaves `subject_pattern` unresolved. Skipping inference because
  "some config file exists" recommends the bundled default over the repo's real convention.
- **Nested-directory invocations silently read the wrong files.** Anchor every repo-relative read
  at `REPO_ROOT` (`${CLAUDE_PROJECT_DIR}`, else `git rev-parse --show-toplevel`), a cwd-relative
  `.claude/source-control.md` read from a subdirectory misses the repo-root config and degrades
  without an error. Re-resolve in each self-contained Bash call.
- **Linked worktrees hide the hooks directory.** Resolve it with `git rev-parse --git-path hooks`,
  in a linked worktree `.git` is a file, and `core.hooksPath` can move the directory anywhere.
- **History inference clocks: `--since` filters by committer date.** Render `%cd`, not `%ad`, a
  rebased or cherry-picked commit enters the window by committer date but would bucket by its old
  author date, skewing the recency split (review-caught during #1139). A shallow clone truncates
  the window silently. Probe `git rev-parse --is-shallow-repository` and report the actual span.
- **Same-session `userConfig` reads are stale.** Reconfigured babysit values become visible only
  in a fresh session. Re-running `check` in the same session reports a false failure.
- **A broken `convention_source` pointer or well-known file fails closed.** Enforcement and drafting
  surface it as a config error rather than silently falling back to markdown values a migration may
  have retired. Verify the neutral file round-trips through the resolver at write time. The neutral
  file resolves by a fixed 3-rung precedence (explicit pointer > well-known
  `docs/conventions/source-control/commit-convention.yml` **when git-tracked** > markdown-H2); an
  untracked/gitignored file at the well-known path is skipped on both surfaces (policy floor), and
  `check` warns when a resolved neutral file shadows a stale markdown-H2 duplicate.

## What this skill does NOT do

- Make a commit or open a PR, that's `/source-control:commit` and `/source-control:pull-request`.
- Enforce the convention at commit time, a project's own `commit-msg` hook (when one exists) remains
  the authoritative gate; this config only tells the plugin's skills what shape to draft and
  pre-check against.
- Write the consumer's `.gitignore`, except the one `.claude/*.local.*` line at
  team-layer bind / `apply`. That line must exist before any overlay is written,
  so `apply` appends it when missing and announces the edit. Everything else in
  `.gitignore` stays the consumer's.
- Write the plugin cache, Claude Code user settings, or `pluginConfigs`. The convention lives in
  the consumer's own config layers; babysit settings live in Claude-Code-owned `userConfig`,
  reconfigured only through the two paths above.
