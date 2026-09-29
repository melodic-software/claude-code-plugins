# Machine profile: design

Design for a re-runnable machine profile that discovers host facts once, stores them, and hands
each plugin's `setup` the answers. Tracked by
[#4666](https://github.com/melodic-software/claude-code-plugins/issues/4666). This document
records design only: it changes no setup contract, no invocation-mode class, and no plugin.

## Contents

- [Problem](#problem)
- [Model: split read from write](#model-split-read-from-write)
- [Storage location](#storage-location)
- [Document shape](#document-shape)
- [Verdict vocabulary](#verdict-vocabulary)
- [Manual-change policy](#manual-change-policy)
- [Reuse and machine-health](#reuse-and-machine-health)
- [Placement](#placement)
- [Out of scope until the later decision](#out-of-scope-until-the-later-decision)
- [Acceptance criteria left for the build](#acceptance-criteria-left-for-the-build)
- [Open questions](#open-questions)
- [Verification record](#verification-record)

## Problem

Configuring the fleet on a new or changed machine means running each plugin's `setup` skill, and
each one re-derives the same host facts: which binaries resolve, which identity domains exist and
where their tree boundaries fall, which `gh` configuration belongs to which tree, where worktrees
and reports already live. None of that discovery is plugin-specific and none of it is stored, so
every machine and every re-run repeats it, and nothing records whether a kept default was examined
or never looked at.

The failure this design exists to prevent is a default recorded as decided without a
look: an option holding a profile name kept at its default while a profile of that name existed on
disk, and a claim that no per-repo configuration layer exists made without reading
[config-cascade](../conventions/config-cascade/README.md), which defines that layer.

## Model: split read from write

Four parts, each with one owner.

| Part | Behavior | Writes |
|---|---|---|
| Discover | Probes the host and prints what it observed | nothing |
| Store | Holds the observed facts and the verdict for each | one document in the profile's own data directory, after confirm |
| Apply | Hands each setup the values it needs and lets that setup make its change | whatever the target setup owns, after confirm |
| Setup | Keeps its own prerequisite logic; ships and versions with its plugin | its own surface only |

The profile is a driver, not a replacement. It never absorbs a setup skill's prerequisite logic:
that logic ships with the plugin and goes stale if a second copy lives elsewhere.

Actions, named as suggestions: `profile` (discover, print, offer to record), `diff` (compare the
stored document with the host now), `explain` (show the observation behind one recorded value),
and `apply` (behind an explicit confirm). Everything except `apply` and the confirmed store write
is read-only.

### How discovery reaches each plugin's checks

Discovery has three routes, in order of preference:

1. **A model-invocable check skill.** Five plugins ship a `/<plugin>:check` that reads its own
   `setup/SKILL.md` and follows only the `check` section: `actionlint`, `biome-format`,
   `context7`, `go-format`, and `markdown-format`. The profile invokes these directly.
2. **`claude-ops:prerequisites`.** It reads each enabled plugin's `prerequisites.json` and probes
   the declared binaries. The profile invokes it once and reads its table.
3. **Reproduction.** Every other `setup` skill is `disable-model-invocation: true`, and a hidden
   skill cannot be invoked by another skill (the invocation-reach invariant in
   [invocation-mode](../conventions/invocation-mode/README.md)). For those the profile can run
   the same probes the setup's `check` section describes, and every result so produced is labeled
   `reproduced`, never presented as the setup's own output. Where no probe is safe to
   reproduce, it relays the `/<plugin>:setup check` line for the operator to type.

Each check skill states that pre-computed context lines in a setup file do not run when the file is
read, so the probes are re-run through Bash. That re-run is already a reproduction; the label makes
it visible.

Discovery degrades without hard dependencies: it uses the `discovery` and `planning` skills when
installed, native agents otherwise, and reports which mode ran.

## Storage location

| Option | Fits | Fails |
|---|---|---|
| The profile plugin's `${CLAUDE_PLUGIN_DATA}` | Host facts are generated machine state, one set per machine, and the directory is update-safe | Deleted on uninstall from the last scope unless `--keep-data` is passed |
| `~/.claude/<name>` | Reaches every repo | That is config-cascade's user-global layer, which carries operator preferences. Host facts are observations, not preferences, and a shared directory has no per-plugin isolation |
| A repository | Versioned and reviewable | Host specifics (paths, identities, tree boundaries) would travel with the repository to every clone; the fleet forbids runtime dependence on machine paths and consumer layout |

**Recommendation: the profile plugin's `${CLAUDE_PLUGIN_DATA}`.**
**Basis:** [plugin-philosophy](../plugin-philosophy.md) "Configuration ownership and scope" assigns
"installed dependencies, cache, or generated machine state" to `${CLAUDE_PLUGIN_DATA}`;
config-cascade assigns `~/.claude/<name>` to operator preferences across repos; the repository row
follows from plugin-philosophy's "Design boundary" (runtime behavior must not depend on absolute
machine paths or an undocumented consumer layout).

Two consequences to record with the storage choice:

- **Keying.** [plugin-data-report-keying](../conventions/plugin-data-report-keying/README.md)
  rule 1 keys every write by project identity. The shared machine section describes the host, which
  is the same for every project, so it is not project-keyed: that is a deviation to ratify, not a
  silent skip. Per-domain sections are keyed by the tree they describe. Rule 3 still holds: a
  missing document at the derived location reads as "no profile for this machine" and offers to
  produce one, never a fallback to another path.
- **Uninstall fragility.** Rule 4 of the same convention applies: the document is regenerable from
  the host, so losing it costs a re-run, not data. The skill states this once, near the path.

The store holds names, paths, and observation commands. It never holds a credential, a token, or a
sensitive `userConfig` value, which live in the OS keychain (fact 8 of
[hook-config-delivery](../conventions/hook-config-delivery/README.md)).

## Document shape

One structured JSON document, not a prose convention doc: config-cascade's expression doctrine
keeps structured data and mutable state as dedicated files. The document has a shared machine
section and one section per identity domain.

```text
machine:
  facts:    [ Record ]              # binaries, core count, worktree and report roots, OS
domains:
  <domain-key>:                     # one per identity domain, keyed by its tree root
    tree:      <tree root>          # the boundary observed, never assumed
    identity:  { git_include, gh_config_dir }
    facts:     [ Record ]
    options:   [ Record ]           # per-plugin option states for this domain
Record:
  key, value, verdict,
  observed_by:  <the command or path that produced it>,
  mode:         observed | reproduced,
  supplied_by:  <layer or channel that supplied the value>
```

### Identity domains

A machine can hold several identity domains, each owning a subtree. Discovery detects them per
tree, from observations only:

- **Conditional git includes.** The `includeIf` entries in the effective git configuration, read
  with `git config --list --show-origin`, name each tree boundary and the identity file it selects.
- **Per-tree `GH_CONFIG_DIR`.** Run `gh` from inside each tree and record the configuration
  directory it resolves, so the `gh` account is attached to the tree, not to the machine.

`pluginConfigs` has one slot: Claude Code reads it from user settings, `--settings`, and managed
settings only, and `install --config` writes user settings whatever scope flag is given (facts 5
and 9 of hook-config-delivery). A profile that ignores the split would write one domain's identity
machine-wide. So an option whose correct value is a per-domain identity is recorded under its
domain and is never applied into the single slot; `apply` shows the conflict and stops for that
option.

### Resolution and guards

- Each value resolves through the layer and channel its owning surface declares, and the record
  says which supplied it: a config-cascade layer (user-global, team, local overlay) or a
  hook-config-delivery channel. An option's own owner doc, not the profile, says which applies.
- Discovery detects local guards that would block an apply, such as a read-only or immutable
  attribute on a git-config include file, and emits the command for the operator instead of
  attempting the write.
- When an option cannot express what discovery found, the profile offers to file a gap with the
  observed topology attached. It files nothing without a confirm.

## Verdict vocabulary

Every option state carries one verdict:

| Verdict | Meaning | Requires |
|---|---|---|
| `set` | A non-default value is in force | the layer that supplied it |
| `default-verified` | Unset; discovery looked and here is what it saw | the observation, including "looked and found nothing" |
| `default-unexamined` | Unset; nothing was looked at | nothing, and it stays this until a look happens |
| `blocked` | A guard prevents the change | the guard and the operator command |

There is no bare `keep`. Rules the build enforces structurally:

- An unset option whose value is a path, profile, identity, root, or name is a question. Discovery
  looks on disk before a verdict, and the verdict cites what it found or states that it looked and
  found nothing.
- `default-unexamined` never becomes `default-verified` by written rationale, only by an
  observation. A rationale without an observation is the failure this vocabulary exists to stop.
- A value equal to its default is never written to mark it decided.
- Every recorded state carries `observed_by`, the command or path that produced it. A record with
  no `observed_by` is invalid and cannot be emitted.
- A result produced by reproducing a setup probe carries `mode: reproduced`.

## Manual-change policy

Warn, never silently re-assert.

- `diff` and `profile` compare each stored value with what discovery observes now. A difference is
  reported with both values and both `observed_by` entries. The store cannot tell an operator's
  hand edit from a host change, so it reports the difference and does not attribute it.
- Nothing reapplies a stored value on its own: no hook, no session-start step, no scheduled run.
  `apply` re-asserts a value only when the operator selects it in that run, after `diff` has shown
  what will change.
- Re-running discovery on an unchanged machine reports no change and asks nothing.

## Reuse and machine-health

The profile reuses what exists instead of adding a parallel path:

- The five wrapper `check` skills and `claude-ops:prerequisites` are its read route for binaries.
  It adds no probe they already run.
- The `prerequisites.json` manifest is the fleet's declaration of external tools. The profile
  reads it and does not declare tools of its own. Two manifests today (`claude-ops` and
  `playwright`) still name a model-hidden `:setup check`, which the profile can only reproduce or
  relay.

**machine-health consumes the store, and does not compete with it.** machine-health owns severity,
trend, history, and reporting for host findings. Its `config` category today holds one shipped
check, `environment-health` (environment variables and `PATH`, Windows only); macOS and Linux
checks are scaffolded and report `NOT_IMPLEMENTED`. It is therefore a category, not yet a
declared-configuration drift check. The feed is a machine-health check, shipped or added through
its catalog overlay, that reads the profile's document and emits findings in machine-health's own
output schema. The split of ownership:

| Concern | Owner |
|---|---|
| Observed facts, verdicts, provenance, per-domain shape | the profile |
| Severity, trend, history, report | machine-health |
| Which setting is correct for a plugin | that plugin's `setup` |

The profile assigns no severity and keeps no history. machine-health does no option discovery. The
document's path reaches the check as an explicit argument, not an inherited variable, for the reason
machine-health's own audit gives: a subprocess can inherit another plugin's `CLAUDE_PLUGIN_DATA`.
Until such a check exists, and on hosts where machine-health's checks are not implemented, the
profile's `diff` is the only consumer.

## Placement

**Recommendation: a skill in `claude-ops`, not a new plugin.**
**Basis:** `claude-ops` already owns fleet state and ships `prerequisites` and `inventory`, the two
skills the profile reads; a new plugin would add a third owner of host facts beside
`machine-health`. Judgment on the remaining half: whether the skill's scope is too broad for
`claude-ops` is the owner's call. The formal placement record is a separate decision record, not
this document.

## Out of scope until the later decision

Held for the owner's later ruling on this document:

- Any change to the setup contract, and any change to `validate-plugin-contracts.mjs`.
- Amending invocation-mode class (ii) or adding a class, and any change to a `setup` skill's
  `disable-model-invocation` value.
- Adding a model-invocable `check` skill for a plugin that lacks one.
- Version bumps and CHANGELOG entries for any touched plugin.
- The skill itself, its scripts, and its tests.

## Acceptance criteria left for the build

This document meets the design-doc criterion only. The build has to meet these, each with a fixture
tree under a scratch `HOME` and no real-host specifics:

- **Unchanged-machine rerun.** Discovery on an unchanged fixture reports no change and asks no
  question. Test: run twice over one fixture, assert an empty diff and no prompt.
- **No verdict without an observation.** The document writer rejects a record whose `observed_by`
  is empty, and a `default-verified` record whose observation is absent. Test: attempt to emit
  each and assert a refusal.
- **Read-only discovery.** Discovery leaves the fixture `HOME` and repository byte-identical.
  Test: hash both trees before and after. `apply` writes nothing without an explicit confirm.

## Open questions

Each is for the later decision on this document.

1. **Class (ii).** Amend class (ii), add a class, or leave the setup skills hidden and rely on
   reproduction. Recommendation: leave them hidden until the profile is built and shows a check the
   wrappers and reproduction cannot cover. Unblocks: whether the fleet contract change happens at
   all.
2. **Placement.** Confirm `claude-ops` or choose a new plugin. Recommendation: `claude-ops`.
   Unblocks: the placement record and the skill's directory.
3. **Keying deviation.** Ratify a non-project-keyed machine section under plugin-data-report-keying.
   Recommendation: ratify, with per-domain sections keyed by tree. Unblocks: the store's path scheme.
4. **The machine-health feed.** Whether machine-health ships a `config` check that reads the
   profile, or the profile's `diff` stays the only consumer. Recommendation: ship the check only
   once the profile exists and runs on an OS whose machine-health checks are implemented. Unblocks: the handoff
   contract.

## Verification record

**Claim:** origin/main has 59 plugin-level setup skills, all `disable-model-invocation: true`; eight
`check` skills, of which five wrap a setup `check` section; seven `prerequisites.json` manifests;
one shipped machine-health `config` check.
**Basis:** at `c514a8abe`, `ls plugins/*/skills/setup/SKILL.md | wc -l` (59) and
`grep -L 'disable-model-invocation: true' plugins/*/skills/setup/SKILL.md` (none);
`plugins/*/skills/check/SKILL.md` frontmatter and body (eight, five reading `setup/SKILL.md`);
`find plugins -name prerequisites.json` (seven);
`plugins/machine-health/skills/audit/catalog/checks.jsonc` (one `"category": "config"` entry,
`environment-health`); `docs/conventions/config-cascade/README.md`;
`docs/conventions/hook-config-delivery/README.md` facts 5, 8, and 9.
**As of:** 2026-09-29.
**Recheck:** a setup skill drops `disable-model-invocation`, a plugin gains or loses a `check`
skill or a `prerequisites.json`, machine-health adds a `config` check, or either convention doc
changes the facts cited.
