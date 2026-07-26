---
name: setup
description: "Configure the source-control plugin. check (read-only): report the effective commit-subject / PR-title convention merged across its user-global, team, and personal-overlay layers, and the babysit-prs userConfig surface (effective config, branch-protection posture, Windows long paths, lane-script permission reachability). apply: interview the repo and write the convention config to a chosen layer, and walk the sanctioned babysit reconfigure paths. Use when: 'set up source-control', 'configure commit convention', 'source-control setup', 'what commit format does this repo use', 'set my personal commit convention', 'override the team convention locally', 'configure babysit', 'check babysit config', or /commit, /pull-request, or /babysit-prs report missing configuration. Actions: check (read-only verification, default) | apply (write the convention config; document the babysit config paths). Re-runnable and safe."
argument-hint: "check | apply [layer=user|team|local] [subject_pattern=<anchored-regex | 'Conventional Commits'>]"
user-invocable: true
disable-model-invocation: true
---

## Purpose

Inspect and configure the source-control plugin per the uniform setup contract: `check` reports the
effective configuration, `apply` writes it. Two configuration surfaces:

1. The commit-subject / PR-title convention config, layered across a user-global file, the tracked
   team file, and a gitignored personal overlay and merged per key by
   [../../reference/config-resolution.md](../../reference/config-resolution.md) — resolved first by
   `/source-control:commit` and `/source-control:pull-request` before they fall back to inference or
   the bundled Conventional Commits default. Conventional Commits is genuinely optional — some orgs
   gate on ticket-prefixed subjects (`WEB-123: description`) — so the plugin ships a sensible
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

Anchor at the repo root: resolve `REPO_ROOT` once — `${CLAUDE_PROJECT_DIR}` when set, otherwise
`git rev-parse --show-toplevel` — and use that literal resolved path for every repo-relative read
below, never a cwd-relative path (invoked from a nested directory, a cwd-relative path would inspect
the wrong file). Re-resolve `REPO_ROOT` at the top of every self-contained Bash call — a fresh shell
does not carry a prior call's variables.

Read all three layers, then report **one effective-configuration table** — a row per key, its
resolved value, and which layer supplied it — followed by a per-layer presence line. Never present a
single layer's value as the effective convention; a reader who cannot see which layer won cannot
tell why `/commit` behaves as it does.

```text
key                        value                       won by
subject_pattern            ^[A-Z]+-\d+: .+             team
pr_title_pattern           Same as subject_pattern      team
trailer_policy             none                         local overlay
pr_body_attribution        none                         local overlay
pr_body_required_sections  Summary, Test plan           plugin default
```

`pr_body_required_sections` is a **list**-valued key (like `type_list`, and unlike every scalar row
above it) — render it comma-joined for this report regardless of how many lines the winning layer's
file spells it across. When every layer leaves it unset, the row still resolves — to the plugin's
portable default, `Summary` and `Test plan` — so `won by` reads `plugin default` rather than the row
going blank; this is the one key whose "no layer sets it" state is itself a reportable, named value,
not a bare absence. A winning layer declaring the literal keyword `none` renders the row's value as
`none (no required sections)` with that layer in `won by` — a resolved value distinct from the unset
row above, per config-resolution.md.

Per-layer verdicts:

- **User-global** (`~/.claude/source-control.md`): present → report which keys it contributes;
  absent → INFO. It is outside the repo, so no git check applies to it.
- **Team** (`REPO_ROOT/.claude/source-control.md`): present → PASS. **FAIL** when excluded by
  `.gitignore` — teammates would never receive the shared convention; report the matching rule.
  Absent → INFO, remediable by `apply`.
- **Local overlay** (`REPO_ROOT/.claude/source-control.local.md`): PASS only when an ignore rule
  matches it **and** it is not in the index. Two distinct failures hide behind one symptom and need
  different remediations, so probe them separately — see the two-probe form under `apply`. Absent →
  INFO, which is the common case.

**FAIL** when the *effective* `subject_pattern` is not machine-checkable — it must be either the
literal keyword `Conventional Commits` or an anchored regex (`^…`-style); a plain-language
description cannot be evaluated by `/commit` or `/pull-request`. Name the layer that supplied the
offending value.

With **all three layers absent**: INFO — no declared convention; `/commit` and `/pull-request` infer
from the repo's own `CLAUDE.md`/rules/commit-msg hook, then fall back to the bundled Conventional
Commits default. The remediation is `apply` to persist a convention.

**Neutral-SSOT drift probes.** When a `convention_source` pointer is declared or a neutral file is
resolved (explicit pointer, or the well-known default `docs/conventions/source-control/commit-convention.yml`),
`check` surfaces two drift conditions the resolver otherwise handles silently — round-trip the
enforcement resolver (`lib/resolve-convention-pattern.sh <REPO_ROOT> subject_pattern`) and read its
diagnostics:

- **Broken pointer / neutral file → FAIL.** A declared `convention_source` whose target is missing,
  or a resolved neutral file that fails the seam's safety/dialect/empty-key contract, disables
  enforcement fail-closed. This is easy to miss because nothing signals it until a commit is
  unexpectedly blocked or allowed — so surface it here, naming the resolver's diagnostic and the
  remediation (restore the file, fix the pointer, or `apply` to rewrite it).
- **Shadowed markdown → WARN.** A neutral file resolves (via pointer or the well-known default) **and**
  `.claude/source-control.md` still carries a markdown-H2 `subject_pattern`/`pr_title_pattern` for the
  same key: the neutral value wins (rungs 1–2 over rung 3) and the stale markdown is inert but
  misleading. Recommend `apply` to retire the duplicate (migration removes it), per
  [reference/apply-convention.md](reference/apply-convention.md) "Migration retires duplicates".

### Babysit config

1. **Effective configuration.** Report every babysit `userConfig` key with its resolved value or its
   inference when unset. The authoritative render is the effective-configuration block that loads
   with `/source-control:babysit-prs` (its `help` mode prints it without taking any other action); a
   surviving literal `${user_config.…}` placeholder there means the key is unset. For each unset key
   state what will be inferred at run time — `babysit_watched_owners` → the current repo's owner,
   `babysit_self_logins` → none (your `gh api user --jq .login` login is always used, extras only add
   to it), `babysit_default_tier` → `safe`, `babysit_merge_method` → repo convention then squash, the
   review-trigger keys → module dormant, `babysit_worktree_root` → the plugin data dir's
   `worktrees/` subdirectory. Unset keys are INFO (documented defaults), not FAIL.
2. **Branch-protection posture across watched repos.** For each watched owner (or the current repo's
   owner when `babysit_watched_owners` is unset), enumerate the repos babysit would touch — repos
   with open PRs authored by the self logins, via
   `gh search prs --state open --author @me --owner <owner> --json repository` — and for each, read
   the default branch's effective rules (`gh api repos/<owner>/<repo>/rules/branches/<default-branch>`,
   falling back to `gh api repos/<owner>/<repo>/branches/<default-branch>/protection` for classic
   protection). Flag every repo reporting zero required reviews AND zero required status contexts as
   **unprotected**: the merge gate refuses gate-proven merges there for non-self authors
   (`--allow-unprotected` is the deliberate override), so an unprotected repo in an autopilot fleet
   deserves a protection rule, not an override.
3. **Windows long-path support for the worktree root.** On Windows, worktrees under the (possibly
   deep) worktree root can exceed 260 characters. Probe `git config --get core.longpaths` and the OS
   policy (registry value `LongPathsEnabled` under
   `HKLM\SYSTEM\CurrentControlSet\Control\FileSystem`); report each as enabled/disabled with the
   remediation (`git config --global core.longpaths true`; the OS value needs an elevated change, so
   report it — never attempt it). Skip this probe silently on non-Windows.
4. **Lane-script reachability under the host permission layer.** The babysit lane declares its own
   bundled scripts — engine, gates, and guarded wrappers — invocable without a per-call permission
   denial as a prerequisite, and for the paths that prove readiness it declares no degrade tier
   (`babysit-prs` "Engine and degrade"; the contract, including why a denied mutation degrades
   while a denied check cannot, is `skills/babysit-prs/reference/safety.md` "Lane-Script
   Reachability"). Probe it here so the operator learns of a gap before a cycle stalls on it, in
   two parts:
   - **Canary (the load-bearing half).** Run the lane's mandated invocation forms against
     non-mutating targets — **both** of them, because they live under different path prefixes:

     ```bash
     bash "${CLAUDE_PLUGIN_ROOT}/bin/source-control-babysit-merge" --help
     bash "${CLAUDE_PLUGIN_ROOT}/scripts/babysit-readiness-gate.sh" --help
     ```

     These are the exact spellings the lane uses for every merge and for every readiness
     declaration, with `--help` so each prints usage and exits 0 without touching the network or
     GitHub. Probe both: an allow rule or classifier decision covering the `bin/` wrapper says
     nothing about the `scripts/` helper, so a canary that ran only the first would certify a
     path the lane's readiness verdict never travels — and the readiness gate has no degrade tier
     at all. A **tool-call denial on either is a FAILED prerequisite**, not an INFO note. The
     reason is fail-closed posture, not logical certainty: the classifier decides per call, so a
     denied `--help` does not *prove* the production shapes are denied any more than a permitted
     one proves they are allowed. What it does establish is that the mandated spelling reaches the
     classifier and can lose there — and the cheapest, most obviously harmless shape is the one
     least likely to be denied while the heavier ones pass. A prerequisite check whose weakest
     probe was refused must report FAILED rather than assume the untested shapes fare better.
     Name which form was denied, say plainly that the production shapes were not probed, report
     the denial verbatim with the remediation below, and never retry it or re-spell it as a raw
     interpreter invocation to get past the denial — that form is exactly what the wrapper exists
     to replace.

     **A pass is reachability, not a guarantee — report it as such.** A permitted `--help` proves
     the mandated spelling exists and that a call to it got through; it does *not* prove the
     production shapes (`owner/repo#N --allowed-owners …`, `<N> --extra-self …`) will be
     permitted, because the classifier decides per call, at call time. That per-call property cuts
     both ways: it leaves a pass provisional, and it is why the FAILED verdict above is a
     fail-closed choice rather than a proof. The probes stay `--help`-only
     deliberately: the merge wrapper's read-only production shape is a live GitHub call, so a
     representative probe would make a `check` run start touching the fleet it was asked to
     inspect — which the plugin's `babysit-wrapper-help` shell test exists to keep from
     regressing. The
     residual gap is covered rather than hidden: a denial that lands mid-cycle instead is
     fail-honest by the mechanism this section rests on — the gate prints `READINESS_UNPROVEN`,
     or nothing at all when the call never happened, and
     `skills/babysit-prs/reference/loop.md` §5.5 requires the per-PR **Gate verdict** line to
     quote that stdout verbatim, so an unproven readiness surfaces in the report instead of
     being absorbed. The canary is the proactive convenience; the quoted verdict is the
     enforcement.
   - **Effective configuration (context for the canary).** Run `claude auto-mode config` and report
     whether its effective rules cover this plugin's bundled scripts. It prints the merged result
     across the scopes the classifier reads `autoMode` from — user settings and managed settings —
     so read that output rather than hunting for the underlying files; the managed scopes are not
     locally readable as ordinary settings files. **Forward the launch-time scope when there is
     one.** `--settings` is a global flag consumed at launch, not an input the subcommand accepts,
     so a bare `claude auto-mode config` spawned from a session that was itself launched with
     `--settings <file>` reports without that scope and under-states the effective rules. Probe
     with `claude --settings <file> auto-mode config` in that case, and say which form was used;
     when the scope came from an Agent SDK settings object with no file to re-supply, report the
     probe as scope-incomplete rather than as the effective configuration. A missing or
     narrow-looking block is INFO, never FAIL on its own: settings cannot prove reachability,
     because a host safety classifier decides per call, at call time. Pair it with the
     [auto-mode configuration reference](https://code.claude.com/docs/en/auto-mode-config).

   The remediation is always the operator's to apply — never write settings from this skill.

## `apply` (idempotent)

Run `check` first. Then write the convention (surface 1) and walk the sanctioned babysit
reconfigure paths (surface 2).

### Convention config

The full write path is normative in
[reference/apply-convention.md](reference/apply-convention.md) — read it before writing any layer.
In brief:

- **Target layer.** `layer=` picks `user` / `team` (default) / `local`; infer the layer from the
  request's wording and state the pick before writing — the wrong layer either misses teammates or
  commits a personal preference to shared history.
- **Non-interactive** (`subject_pattern=`): an in-place *update*, never a fresh file — carry every
  independent key, recompute derived keys (`type_list`, `pr_title_pattern`), reject a
  non-machine-checkable value, and for an overlay omit requested keys the layers below already
  resolve identically.
- **Interactive:** the interview — anchor at `REPO_ROOT`, read all three layers first, infer before
  asking (declared prose, commit-msg hooks, commit-history consensus over the configurable
  `setup_inference_*` window), interview one decision at a time with a recommendation first, settle
  the optional keys (`trailer_policy`, `pr_body_attribution`, `pr_body_required_sections` —
  including the `none` value and the omission-never-resets trap), write the template, verify per
  layer (team = tracked and staged; local = ignored and untracked, two independent probes; user =
  no git command at all), and report the new **effective merge**, not just what was written.

- **Neutral SSOT:** a `team` write may materialize a tool-agnostic flat-scalar YAML file other tools
  consume too. It defaults to the well-known path `docs/conventions/source-control/commit-convention.yml`
  (resolved with no pointer); `## convention_source` is written only to relocate it. **Recommended as
  the default when a second enforcement consumer exists** (commit-msg hook, CI title check), markdown-only
  when this plugin is the sole consumer; migration retires markdown keys the neutral file takes over
  (spoke section "Neutral convention SSOT").

Every step's exact contract — the interview steps, the written-file template, the per-layer
verification scripts, and the failure remediations — lives in the spoke; this summary never
overrides it.

### Babysit config

`/source-control:babysit-prs` is configured through the plugin's native `userConfig`, which Claude
Code owns (`pluginConfigs`) — this skill never hand-edits it. It documents and walks the two
sanctioned paths:

- **Interactive:** `/plugin configure source-control` (or the `/plugin` dialog → source-control →
  configure), any time — Claude Code prompts per key using the manifest's types and defaults.
- **Headless / CI:** `--config` only applies on a fresh install (ignored once installed), so
  reconfiguring headless means `claude plugin uninstall source-control -s <scope>` then
  reinstalling with the new values:
  `claude plugin install source-control@<marketplace> -s <scope> --config KEY=VALUE` (repeatable
  per key). Multi-value keys (`babysit_watched_owners`, `babysit_self_logins`,
  `babysit_review_bot_logins`, `babysit_extra_bot_logins`) are supplied comma-joined. Both
  commands default to `-s user` — pass the scope `claude plugin list` reports for this plugin,
  and run from that project's directory for a `project`/`local` scope. Defaulting instead
  uninstalls a separate user-scope record while the effective install stays in place, so the
  reinstall lands at a scope that does not load. Uninstalling also drops the stored
  `pluginConfigs` entry, so the reinstall must re-supply **every** key whose value should stay
  non-default, not only the key being changed — this plugin declares twenty-nine, so a reinstall
  that passes one silently resets the babysit fleet's owners, logins, tiers, caps, and worktree
  roots to their manifest defaults. Record the current values before uninstalling; afterwards
  there is nothing left to read them from.

Reconfiguring `userConfig` does not reach the already-running session — after either path, the new
values become visible only in a fresh session. Do not re-run the babysit `check` in the same session
expecting the change and report a false failure; instead report "reconfigured; verify with `check` in
a fresh session".

## Output

A convention config file at the chosen layer (when `apply` wrote one), plus the resulting effective
merge with the winning layer per key, a one-paragraph summary of where the convention came from
(inferred or user-declared), and — for babysit — the `check` probe report and the reconfigure path
used. `check` alone reports the effective configuration across both surfaces and changes nothing.

## Gotchas

Skill-behavior failure patterns hit in real runs. Add to this section when new ones are discovered.

- **Omitting a key never resets it.** Per-key fallthrough means a section left out of a higher
  layer inherits the lower layer's value — resetting to the portable default *over* a lower layer
  that sets the key requires writing the explicit default value; omission only inherits (the
  `apply` interview states this when it applies).
- **`none` and absence are different states** for `trailer_policy`, `pr_body_attribution`, and
  `pr_body_required_sections`: absence falls through (ultimately to the bundled default), `none` is
  a resolved opt-out that wins its layer's per-key override.
- **Gate inference on the resolved value, never file presence.** A `source-control.md` layer that
  contributes only other keys leaves `subject_pattern` unresolved — skipping inference because
  "some config file exists" recommends the bundled default over the repo's real convention.
- **Nested-directory invocations silently read the wrong files.** Anchor every repo-relative read
  at `REPO_ROOT` (`${CLAUDE_PROJECT_DIR}`, else `git rev-parse --show-toplevel`) — a cwd-relative
  `.claude/source-control.md` read from a subdirectory misses the repo-root config and degrades
  without an error. Re-resolve in each self-contained Bash call.
- **Linked worktrees hide the hooks directory.** Resolve it with `git rev-parse --git-path hooks`
  — in a linked worktree `.git` is a file, and `core.hooksPath` can move the directory anywhere.
- **History inference clocks: `--since` filters by committer date.** Render `%cd`, not `%ad` — a
  rebased or cherry-picked commit enters the window by committer date but would bucket by its old
  author date, skewing the recency split (review-caught during #1139). A shallow clone truncates
  the window silently — probe `git rev-parse --is-shallow-repository` and report the actual span.
- **Same-session `userConfig` reads are stale.** Reconfigured babysit values become visible only
  in a fresh session — re-running `check` in the same session reports a false failure.
- **A broken `convention_source` pointer or well-known file fails closed.** Enforcement and drafting
  surface it as a config error rather than silently falling back to markdown values a migration may
  have retired — verify the neutral file round-trips through the resolver at write time. The neutral
  file resolves by a fixed 3-rung precedence (explicit pointer > well-known
  `docs/conventions/source-control/commit-convention.yml` **when git-tracked** > markdown-H2); an
  untracked/gitignored file at the well-known path is skipped on both surfaces (policy floor), and
  `check` warns when a resolved neutral file shadows a stale markdown-H2 duplicate.

## What this skill does NOT do

- Make a commit or open a PR — that's `/source-control:commit` and `/source-control:pull-request`.
- Enforce the convention at commit time — a project's own `commit-msg` hook (when one exists) remains
  the authoritative gate; this config only tells the plugin's skills what shape to draft and
  pre-check against.
- Write the consumer's `.gitignore`. The personal overlay needs `.claude/*.local.*` ignored; this
  skill recommends the line and leaves the edit to the consumer.
- Write the plugin cache, Claude Code user settings, or `pluginConfigs` — the convention lives in the
  consumer's own config layers; babysit settings live in Claude-Code-owned `userConfig`,
  reconfigured only through the two paths above.
