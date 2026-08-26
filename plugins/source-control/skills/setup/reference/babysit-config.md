# Babysit config

Every `babysit.*` key `/source-control:setup` knows: what it means, its default, how `check`
validates it, and what `apply` writes. The `check` and `apply` flows in
[`../SKILL.md`](../SKILL.md) name which keys they visit; this file is what the keys mean.

## Contents

- [What `check` reports](#what-check-reports)
- [What `apply` writes](#what-apply-writes)

## What `check` reports

1. **Effective configuration.** Report every babysit `userConfig` key with its resolved value or its
   inference when unset. The authoritative render is the effective-configuration block that loads
   with `/source-control:babysit-prs` (its `help` mode prints it without taking any other action); a
   surviving literal `${user_config.…}` placeholder there means the key is unset. For each unset key
   state what will be inferred at run time. `babysit_watched_owners` → the current repo's owner,
   `babysit_self_logins` → none (your `gh api user --jq .login` login is always used, extras only add
   to it), `babysit_default_tier` → `safe`, `babysit_merge_method` → repo convention then squash, the
   review-trigger keys → module dormant, `babysit_worktree_root` → the plugin data dir's
   `worktrees/` subdirectory. Unset keys are INFO (documented defaults), not FAIL.
2. **Branch-protection posture across watched repos.** For each watched owner (or the current repo's
   owner when `babysit_watched_owners` is unset), enumerate the repos babysit would touch. Repos
   with open PRs authored by the self logins, via
   `gh search prs --state open --author @me --owner <owner> --json repository`, and for each, read
   the default branch's effective rules (`gh api repos/<owner>/<repo>/rules/branches/<default-branch>`,
   falling back to `gh api repos/<owner>/<repo>/branches/<default-branch>/protection` for classic
   protection). Flag every repo reporting zero required reviews AND zero required status contexts as
   **unprotected**: the merge gate refuses gate-proven merges there for non-self authors, and for a
   self author whenever the base is not the default branch (`--allow-unprotected` is the deliberate
   override), so an unprotected repo in an autopilot fleet deserves a protection rule, not an
   override.
3. **Windows long-path support for the worktree root.** On Windows, worktrees under the (possibly
   deep) worktree root can exceed 260 characters. Probe `git config --get core.longpaths` and the OS
   policy (registry value `LongPathsEnabled` under
   `HKLM\SYSTEM\CurrentControlSet\Control\FileSystem`); report each as enabled/disabled with the
   remediation (`git config --global core.longpaths true`; the OS value needs an elevated change, so
   report it, never attempt it). Skip this probe silently on non-Windows.
4. **Lane-script reachability under the host permission layer.** The babysit lane declares its own
   bundled scripts, engine, gates, and guarded wrappers, invocable without a per-call permission
   denial as a prerequisite, and for the paths that prove readiness it declares no degrade tier
   (`babysit-prs` "Engine and degrade"; the contract, including why a denied mutation degrades
   while a denied check cannot, is `skills/babysit-prs/reference/safety.md` "Lane-Script
   Reachability"). Probe it here so the operator learns of a gap before a cycle stalls on it, in
   two parts:
   - **Canary (the load-bearing half).** Run the lane's mandated invocation forms against
     non-mutating targets, **both** of them, because they live under different path prefixes:

     ```bash
     bash "${CLAUDE_PLUGIN_ROOT}/bin/source-control-babysit-merge" --help
     bash "${CLAUDE_PLUGIN_ROOT}/scripts/babysit-readiness-gate.sh" --help
     ```

     These are the exact spellings the lane uses for every merge and for every readiness
     declaration, with `--help` so each prints usage and exits 0 without touching the network or
     GitHub. Probe both: an allow rule or classifier decision covering the `bin/` wrapper says
     nothing about the `scripts/` helper, so a canary that ran only the first would certify a
     path the lane's readiness verdict never travels, and the readiness gate has no degrade tier
     at all. A **tool-call denial on either is a FAILED prerequisite**, not an INFO note. The
     reason is fail-closed posture, not logical certainty: the classifier decides per call, so a
     denied `--help` does not *prove* the production shapes are denied any more than a permitted
     one proves they are allowed. What it does establish is that the mandated spelling reaches the
     classifier and can lose there, and the cheapest, most obviously harmless shape is the one
     least likely to be denied while the heavier ones pass. A prerequisite check whose weakest
     probe was refused must report FAILED rather than assume the untested shapes fare better.
     Name which form was denied, say plainly that the production shapes were not probed, report
     the denial verbatim with the remediation below, and never retry it or re-spell it as a raw
     interpreter invocation to get past the denial, that form is exactly what the wrapper exists
     to replace.

     **A pass is reachability, not a guarantee. Report it as such.** A permitted `--help` proves
     the mandated spelling exists and that a call to it got through; it does *not* prove the
     production shapes (`owner/repo#N --allowed-owners …`, `<N> --extra-self …`) will be
     permitted, because the classifier decides per call, at call time. That per-call property cuts
     both ways: it leaves a pass provisional, and it is why the FAILED verdict above is a
     fail-closed choice rather than a proof. The probes stay `--help`-only
     deliberately: the merge wrapper's read-only production shape is a live GitHub call, so a
     representative probe would make a `check` run start touching the fleet it was asked to
     inspect, which the plugin's `babysit-wrapper-help` shell test exists to keep from
     regressing. The
     residual gap is covered rather than hidden: a denial that lands mid-cycle instead is
     fail-honest by the mechanism this section rests on, the gate prints `READINESS_UNPROVEN`,
     or nothing at all when the call never happened, and
     `skills/babysit-prs/reference/loop.md` §5.5 requires the per-PR **Gate verdict** line to
     quote that stdout verbatim, so an unproven readiness surfaces in the report instead of
     being absorbed. The canary is the proactive convenience; the quoted verdict is the
     enforcement.
   - **Effective configuration (context for the canary).** Run `claude auto-mode config` and report
     whether its effective rules cover this plugin's bundled scripts. It prints the merged result
     across the scopes the classifier reads `autoMode` from. User settings and managed settings,
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

   The remediation is always the operator's to apply, never write settings from this skill.

## What `apply` writes

`/source-control:babysit-prs` is configured through the plugin's native `userConfig`, which Claude
Code owns (`pluginConfigs`), this skill never hand-edits it. It documents and walks the two
sanctioned paths:

- **Interactive:** `/plugin configure source-control@<marketplace>` (or the `/plugin` dialog → source-control →
  configure), any time. Claude Code prompts per key using the manifest's types and defaults.
- **Headless / CI:** rerun the install with the new values:
  `claude plugin install source-control@<marketplace> -s <scope> --config KEY=VALUE` (repeatable
  per key). Multi-value keys (`babysit_watched_owners`, `babysit_self_logins`,
  `babysit_review_bot_logins`, `babysit_extra_bot_logins`) are supplied comma-joined. Against an
  already-installed plugin it prints `already installed` **and still writes the value**, verified
  on Claude Code 2.1.240 (a non-sensitive option at `user` scope: a non-default value written to
  an installed plugin, then restored). The short-circuit is about the install, not the config
  write. Re-verify before relying on it outside those conditions. A `sensitive` option, or
  `project`/`local` scope, were not covered. Do **not** uninstall to reconfigure: uninstalling
  drops this plugin's entire stored `pluginConfigs` entry, resetting every option in the README's
  Options reference table to its manifest default: the babysit fleet's owners, logins, tiers,
  caps, and worktree roots all revert. `-s` defaults to `user`, so pass the scope
  `claude plugin list` reports for this plugin, and run from that project's directory for a
  `project`/`local` scope, or the write lands at a scope that does not load.

When an uninstall is warranted for a reason other than reconfiguring (troubleshooting, changing
scopes, reinstalling a version), pass `--keep-data`. Uninstalling from the **last remaining scope**
otherwise deletes this plugin's `${CLAUDE_PLUGIN_DATA}` directory (Rule 4 of the marketplace's
`plugin-data-report-keying` convention). That directory holds
`${CLAUDE_PLUGIN_DATA}/state/babysit-prs`: the babysit-prs queue state, the worker leases, and the
feedback ledger, which no `userConfig` key relocates. It is also the **last** resolution rung for
both worktree roots. `babysit_worktree_root` falls back to `${CLAUDE_PLUGIN_DATA}/worktrees`
whenever it is unset, while `/source-control:worktree create` reaches that same directory only when
neither the target repository's `melodic.worktreeroot` git config nor `worktree_root` resolves. So
check where the roots actually resolve before assuming the directory is disposable: babysit's own
worktrees are ephemeral scratch that rebuild from GitHub, but the state directory and any
`/source-control:worktree` tree still holding uncommitted work do not.

Reconfiguring `userConfig` does not reach the already-running session, after either path, the new
values become visible only in a fresh session. Do not re-run the babysit `check` in the same session
expecting the change and report a false failure; instead report "reconfigured; verify with `check` in
a fresh session".
