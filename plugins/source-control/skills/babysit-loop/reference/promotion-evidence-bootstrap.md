# Promotion-evidence bootstrap contract

The operator-supplied surfaces the trusted seam in
[`promotion-evidence-resolution.md`](promotion-evidence-resolution.md) reads: what each one is,
where it may live, and why. That file owns the resolution rule and the fail-closed table; this file
owns what an operator provides. A compliant set lets the seam return a qualified read: cycle-shape
step 3 runs the operator-supplied `check-security-binding.mjs` on the three evidence surfaces each
cycle. A cell then resolves
promoted only when the binding's ceiling and the in-epoch evidence say so, and every cell stays
effective-unpromoted when a surface is absent or non-compliant. Operators keep `--merge human-only`
on launch lines; lifting it is the owner's call after Phase 3 of the plan.

## Contents

- [Allowed source class](#allowed-source-class)
- [The four surfaces](#the-four-surfaces)
- [Value shape](#value-shape)
- [Out of scope](#out-of-scope)
- [Verification record](#verification-record)

## Allowed source class

The surfaces come only from the class the autonomy setup skill names for security resolution:
org-level platform configuration outside repo blast radius, or the executor's trusted deployment
config
([`setup/SKILL.md`](https://raw.githubusercontent.com/melodic-software/claude-code-plugins/main/plugins/autonomy/skills/setup/SKILL.md)
"Agent-unwritable bootstrap for security resolution", not restated here). The lane receives their
locations through the four plugin options below. Claude Code reads plugin options from user
settings, the `--settings` flag, and managed settings only, and ignores a project's
`.claude/settings.json` for them
([hook-config-delivery](https://raw.githubusercontent.com/melodic-software/claude-code-plugins/main/docs/conventions/hook-config-delivery/README.md)
fact 5). The lane's step 0 preflight reads the option values substituted into the babysit-loop
skill body ("Promotion-evidence bootstrap options" in [`SKILL.md`](../SKILL.md); fact 7) and never
the `CLAUDE_PLUGIN_OPTION_*` environment mirror.

The resolution helper does not take the values from the lane at all. It reads
`pluginConfigs["<name>@<marketplace>"].options` itself (channel F of
[hook-config-delivery](https://raw.githubusercontent.com/melodic-software/claude-code-plugins/main/docs/conventions/hook-config-delivery/README.md)),
from two sources, managed winning per option:

- The managed settings files at the fixed system path for the platform: `managed-settings.json`,
  then the `managed-settings.d/` drop-ins in the order the managed settings page gives
  ([managed settings](https://code.claude.com/docs/en/managed-settings), "Delivery mechanisms" and
  "How Claude Code combines managed sources", read 2026-10-11; recheck when either section
  changes).
- The user `settings.json`, located only from the helper's own install path
  (`<config>/plugins/cache/<marketplace>/<name>/<version>`), never from `CLAUDE_CONFIG_DIR`, `HOME`
  or another environment value. A `--plugin-dir` install has no such anchor, so only managed
  settings configure it.

So a stub checker or forged surface the lane keeps outside the checkout cannot stand in for an
operator's value: the helper rejects path arguments, and the environment mirror and repository
files never reach it. What the helper cannot see reads as unset and fails closed: a value supplied
only through a session's `--settings` file, a server-managed (remote) policy, or an MDM policy.
Configure the four options in managed settings or user settings.

The helper can also read a managed file Claude Code itself skips. When a higher-ranked managed
source (a remote policy, or an MDM or HKLM policy) delivers policy keys, Claude Code by default
uses that source and ignores the managed settings files
([managed settings](https://code.claude.com/docs/en/managed-settings#how-claude-code-combines-managed-sources),
"How Claude Code combines managed sources", as of 2026-10-11; recheck when that section or the
`managedSourcesBehavior` default changes). The helper sees only the files, so on such a host a
stale `managed-settings.json` the harness no longer applies can still supply these options. Keep the
four options out of managed files on a host whose policy comes from a remote or MDM source, or
remove the stale file.

The helper trusts its own location and the Node process it runs in. A lane that runs a copy of the
helper from another directory, or starts Node with a preload such as `NODE_OPTIONS=--require`, is
running a different program, and no check inside the helper can refuse that; the checker it
spawns gets only `PATH` and `SystemRoot`.

Never a source, for a location or for a surface itself:

- `.claude/source-control.md` at any layer.
- Any file inside the target repository.
- A repository's `.claude/settings.json` `env` block, or the `CLAUDE_PLUGIN_OPTION_*` variables it
  can populate for an unset option (same document, fact 4).
- Anything the lane or an agent working the queue can write.

Each option holds a location, not a credential, so none is declared `sensitive`: the plugin
options page substitutes only non-sensitive values into skill content, which puts the paths in
the lane's context. What protects a surface is that the lane cannot write it, not that its path
stays unknown. Never put a secret in one of these options.

The options say where a surface is; they do not make it unwritable. A user settings file is
writable by any agent running as that user, so a location kept there is only as protected as that
file. Managed settings keep the location out of the agent's reach too, where the managed system
directory itself is not writable by the lane's identity (the managed settings page notes that on
WSL `/etc/claude-code` is user-writable). Whether a deployment meets the requirement is the operator's to establish. This
file states the requirement and does not certify a deployment.

## The four surfaces

| Option | The helper passes it to the checker as | What it names |
|---|---|---|
| `promotion_evidence_binding` | the `<binding.json>` argument | file: the security binding document |
| `promotion_evidence_root` | `--probe-evidence-root <dir>` | directory: the protected evidence surface |
| `promotion_evidence_source` | `--evidence <evidence.json>` | file: epoch-scoped promotion-evidence events |
| `promotion_evidence_checker` | (the program it runs) | file: the `check-security-binding.mjs` that decides promoted |

The checker's `Usage:` comment, and its `usage:` error message, list its three arguments
([`check-security-binding.mjs`](https://raw.githubusercontent.com/melodic-software/claude-code-plugins/main/plugins/autonomy/skills/setup/scripts/check-security-binding.mjs)).

### `promotion_evidence_binding`

The security binding document: each cell's bound `promotion_state` and its `ratified_at`. It lives
in the binding's own home, the settings-as-code repository or org policy home (setup skill,
"Two-surface split"), as a copy the executor provisions on the lane's host.

Agent-unwritable, because the bound state is the ceiling: an agent that can edit the document
raises a cell's bound state, or moves `ratified_at` past a contrary event so the checker drops that
event as pre-epoch. Outside the target repository's blast radius, because that repository is where
the agents being governed write.

### `promotion_evidence_root`

The protected evidence surface. The checker resolves each L2/L3 isolation entry's `probe_evidence`
reference against this directory only, and rejects an absolute reference, a `..` escape, and a link
that resolves outside it.

Agent-unwritable, because the directory is what turns a transcript into proof: a root an agent can
write lets a transcript swapped in after ratification supply the claimed isolation proof. With no
root configured the checker reports `no --probe-evidence-root configured` and treats every L2/L3
entry as unproven. Outside the target repository's blast radius, for the same reason as the binding.

### `promotion_evidence_source`

The events file: a JSON array of `{cell, event, at}` records, `event` one of `gate-failure`,
`reverted-merge`, `verification-divergence`, and `at` an ISO 8601 instant. The checker scopes the
events to each cell's promotion epoch and propagates prerequisite demotions (its evaluation-mode
header comment owns the rules; they are not restated here).

Publication requirements:

- An operator-side publisher writes the file. The lane and any agent working in the target
  repository read it and cannot write it.
- It carries every contrary event since the earliest promoted cell's `ratified_at`. The checker
  demotes only on events present in the file, so a truncated or lagging copy hides a demotion. The
  publisher keeps it current as of each cycle's start.
- A file the checker cannot read as a JSON array is unavailable, and every cell resolves
  effective-unpromoted.

Agent-unwritable, because an agent that can write the file can delete a `reverted-merge` event and
keep its cell promoted. Outside the target repository's blast radius, for the same reason as the
binding.

#### The publisher

[`scripts/publish-promotion-evidence.mjs`](../scripts/publish-promotion-evidence.mjs) builds the
events file from GitHub alone, through read-only `gh api` calls: merged pull requests classed by the
`work-class:` labels their linked issues and the pull request carried at merge time, which of them
merged autonomously (no human enqueued them, or a `--lane-login` identity merged them), reverts of
those merges, every check run and commit status on their merge commits, and the missed-blocking
label a human applied. An autonomous merge whose class cannot be read is listed as unclassed, and
its contrary events count against every promotable cell. Its header comment states what counts as
each event, including the judgment mappings and how to set `--lane-login` for merge-queue merges.

- **Report mode** (no `--out`) prints the events array and the C3 promotion-evidence report to
  stdout and writes nothing. The report gives each promotable cell's predicate terms from
  [work-classes.md](https://raw.githubusercontent.com/melodic-software/claude-code-plugins/main/plugins/autonomy/reference/guardrails/work-classes.md)
  "Suggested default predicates" with counts, window and pass or fail, and lists merged reverts
  it could not match to a merge.
- **`--out <dir>`** writes `evidence.json` and the sidecar `evidence.meta.json`
  (`generated_at`, `through`, `sha256` of the events file, `prev_sha256`), each by a temp file
  and a rename. It refuses to publish when the previous events file does not match its sidecar's
  `sha256`, or when the new events drop one the previous file held.

Run it as the operator, never from the lane, and point `--out` at a directory the lane cannot
write. Which host runs it, under which identity and on what schedule is not decided yet: it waits
on the open decision about the single merge authority
([#4588](https://github.com/melodic-software/claude-code-plugins/issues/4588)). Until then the
resolver does not read the sidecar.

### `promotion_evidence_checker`

The `check-security-binding.mjs` the helper runs (the autonomy plugin's
`skills/setup/scripts/check-security-binding.mjs`), from an install the operator trusts. The
operator names it because this plugin never looks for another plugin's install directory, and the
lane cannot be the source of the program whose output decides `promoted`.

Agent-unwritable, because the helper runs it and reads its verdict as the resolution: a program
the lane or an agent can write, or can point at, prints `bound promoted -> effective promoted` for
any cell. Outside the target repository's blast radius, for the same reason as the binding.

## Value shape

Each option holds one local filesystem path and has no default. Unset means the bootstrap is
absent. A set value is compliant only when it is:

- **Absolute.** A relative path resolves against the launch directory, which for a lane started in
  a checkout is inside the target repository.
- **Outside the target repository's checkout and every worktree the lane creates, and containing
  none of them.** That includes `babysit_worktree_root`, `worktree_root`, and the plugin data
  directory's `worktrees/`, judged after symlinks resolve. A directory surface (the probe evidence
  root) must not be an ancestor of the checkout or a worktree root: a transcript the lane writes
  anywhere beneath it would resolve as evidence.
- **Read-only to the lane.** The lane's identity can read the surface and cannot write it. That is
  a property of the host (ownership, an ACL, a read-only mount, an executor-owned volume). A path
  string cannot show it, so the operator establishes it in how the surface is provisioned.

## Out of scope

- Lowering fail-closed. An unset, unreadable, relative, or repository-inside surface never falls
  back to a weaker read.
- Reading promotion evidence from `.claude/source-control.md` or any other repo-local or
  agent-writable surface.
- Lifting `--merge human-only`. Operators keep it on launch lines whether or not the bootstrap is
  present; lifting it is the owner's call after Phase 3 of the plan.
- A `--credential-roots` surface. The lane passes the checker none, so a binding whose L2/L3
  isolation entries rest on filesystem credential probes is rejected by the checker and every cell
  resolves effective-unpromoted. The phased plan is in
  [`promotion-evidence-implementation-plan.md`](promotion-evidence-implementation-plan.md).

## Verification record

- **Claim:** the checker takes the binding document, `--evidence`, and `--probe-evidence-root` on
  one usage line. With no root, every L2/L3 entry is unproven under a reason beginning
  `no --probe-evidence-root configured`. An evidence file that is unreadable or not a JSON array
  resolves every cell effective-unpromoted. Plugin options are read only from user settings,
  `--settings`, and managed settings, a repository's `env` block can populate the
  `CLAUDE_PLUGIN_OPTION_*` variable of an unset option, and a skill body's option placeholders
  substitute into model-visible content, non-sensitive values only.
- **Basis:** `plugins/autonomy/skills/setup/scripts/check-security-binding.mjs` (`Usage:` comment,
  `verifyProbeTranscript`, `resolveEffectivePromotion`, evaluation-mode header comment);
  `docs/conventions/hook-config-delivery/README.md` facts 4, 5, and 7; the
  [plugin manifest reference](https://code.claude.com/docs/en/plugins/manifest-reference#reference-a-saved-value)
  `${user_config.KEY}` entry ("In skill and agent content, only non-sensitive values are
  substituted"), fetched 2026-10-07.
- **As of:** 2026-09-29.
- **Recheck:** any of those changing the usage line, the quoted reason, the evidence shape, or the
  plugin-option read scopes.

- **Claim:** the checker leaves an L2/L3 entry unproven, with a reason beginning
  `no --credential-roots configured`, when a filesystem credential probe is evaluated and the
  `--credential-roots` argument is absent. The lane's helper passes the checker the binding,
  `--evidence`, and `--probe-evidence-root` only, and a checker exit of 1 fails the helper closed.
- **Basis:** `plugins/autonomy/skills/setup/scripts/check-security-binding.mjs` (`Usage:` comment,
  the `credentialRoots === null` branch of the credential-probe check, `verifyProbeTranscript`);
  `plugins/source-control/skills/babysit-loop/scripts/resolve-promotion-evidence.mjs` (the
  `spawnSync` argv and the non-zero-exit branch), checked 2026-10-01.
- **As of:** 2026-10-01.
- **Recheck:** the checker gaining a default for credential roots, or the helper passing more
  arguments.

- **Claim:** the checker is the program that prints each cell's `bound X -> effective Y` line in
  evaluation mode, and the helper reports that line as the resolution. The helper reads the
  checker path from `promotion_evidence_checker` in the operator's settings and refuses a path
  inside the checkout or a worktree root, or containing one, with or without symlinks resolved,
  and a probe evidence root that is an ancestor of either. This plugin does not discover another
  plugin's install directory, so the bootstrap names the checker.
- **Basis:** `plugins/autonomy/skills/setup/scripts/check-security-binding.mjs` (the
  `Effective promotion state (evaluation mode):` print);
  `plugins/source-control/skills/babysit-loop/scripts/resolve-promotion-evidence.mjs`
  (`resolveInput`, the `spawnSync` call);
  [`docs/plugin-philosophy.md`](https://raw.githubusercontent.com/melodic-software/claude-code-plugins/main/docs/plugin-philosophy.md)
  "Keep plugins horizontally decoupled", checked 2026-10-11.
- **As of:** 2026-10-11.
- **Recheck:** the checker's print format changing, or the decoupling rule changing.

- **Claim:** the helper takes no bootstrap value as an argument or from the environment. It reads
  the four options from the managed settings files and the install-anchored user `settings.json`,
  managed winning per option, and fails closed when an option is unset there, a source exists but
  cannot be read or parsed, its `pluginConfigs`, this plugin's entry or its `options` is not an
  object, or a value is
  not a string (`null` included). A lane-chosen checker or binding passed as
  an argument, or offered through the `CLAUDE_PLUGIN_OPTION_*` mirror, a checkout
  `.claude/settings.json`, `.claude/source-control.md`, `CLAUDE_CONFIG_DIR` or `HOME`, does not
  yield `promoted`.
- **Basis:** `plugins/source-control/skills/babysit-loop/scripts/operator-options.mjs`
  (`readOperatorOptions`, `resolveInstall`, `managedSettingsFiles`) and its cases in
  `resolve-promotion-evidence.test.mjs`; the managed system paths, drop-in order and source ranking
  on the [managed settings](https://code.claude.com/docs/en/managed-settings) page and the
  `pluginConfigs` scope ("User or managed", project and local entries ignored) in the
  [settings reference](https://code.claude.com/docs/en/settings-reference#pluginconfigs), both read
  2026-10-11.
- **As of:** 2026-10-11.
- **Recheck:** the managed system paths, drop-in merge order or source ranking changing; the
  `pluginConfigs` read scopes changing; or the plugin cache layout
  `<config>/plugins/cache/<marketplace>/<name>/<version>` changing.
