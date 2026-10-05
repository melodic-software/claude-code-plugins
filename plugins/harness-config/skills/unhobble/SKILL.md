---
description: "Bare-baseline experiment: strip a repo's standing instructions, log stumbles against the bare model, then restore only those with repeated same-cause evidence. Measures the model where audit-instructions judges the text. Use when: 'unhobble', 'run the bare experiment', 'delete my CLAUDE.md and see', 'does the model still need these instructions', 'new model dropped, re-baseline', 'instruction ablation experiment', 'deletion watch', 'watch this rule before deleting it'. Human-gated, resumable."
argument-hint: "[snapshot|bare|observe|readd|watch|status|decide]"
user-invocable: true
disable-model-invocation: false
metadata:
  workflow-stage: anytime
  summary: Strip instructions to a bare baseline, log real stumbles, re-add only what evidence earns
---

**Arguments.** `[snapshot|bare|observe|readd|watch|status|decide]`. Omit the phase for the guided full flow.
`decide` is not a phase; see Decide.

## Purpose

As models improve, instruction surfaces written for older models become the ceiling: the model reads
every standing line every session, and lines that correct mistakes it no longer makes cost context
and constrain behavior. Official doctrine says cut any line whose removal would not cause mistakes
([best-practices](https://code.claude.com/docs/en/best-practices)); the strongest form of that test
is empirical: delete, run, watch. This skill operationalizes the experiment its sibling
`audit-instructions` can only reason about: instead of judging instruction *text* against doctrine,
it measures the *model* against the repo with the instructions gone, and lets observed stumbles,
not guesses, decide what returns.

Rebuild rule (the whole contract in one line): **an instruction returns only after the bare model
repeatedly stumbles on the same thing, and the re-added line cites the evidence.**

## When to run

- A frontier model generation ships (the canonical trigger, since instructions written for the
  previous generation are now suspect).
- The repo's instruction surface has grown past the point anyone can say which lines still earn
  their cost.
- On a cadence the operator chooses (see Cadence wiring below). The talk-circuit heuristic is
  "every six months", but the model release is the real event.

## Scope and safety rails

- **Project scope by default.** The experiment strips the *project's* surfaces: project CLAUDE.md /
  CLAUDE.local.md / `.claude/CLAUDE.md`, the `AGENTS.md` and `.claude/AGENTS.md` a session reads
  natively once those are gone (**whether a session reads one at all depends on availability and the
  instruction-files mode, and this body does not restate either**; the four-part record is this
  plugin's [reference/agents-md-liveness.md](../../reference/agents-md-liveness.md)),
  `.claude/rules/`, `.claude/skills/`, `.claude/agents/`, project-settings hooks,
  and plugins enabled at any scope. User-global files (`~/.claude/**`) are edited only when the
  operator explicitly opts in per phase-1 prompt, never by default. A plugin enabled at user
  scope is still classified, and a behavioral one is ablated by the project `enabledPlugins`
  overlay below, not by editing the user settings file.
- **Managed settings are never touched.** Org-managed policy is not the operator's to ablate.
- **Reversible by construction.** Tracked-file changes happen on a dedicated experiment branch;
  untracked/settings changes are backed up to plugin state before modification or removal and
  restored from that manifest. Nothing is destroyed: git history and the snapshot manifest are the safety net.
- **Human-gated.** Every mutating step (strip, restore, re-add, watch removal) presents its exact change set and
  waits for operator confirmation. Bare invocation of a phase never mutates silently.
- **Security posture is out of scope.** Hooks that enforce policy (secrets gates, PR-body contracts,
  permission guards) are classified `policy` at snapshot time and are NOT stripped by default:
  the experiment measures model capability, and policy gates are not model-era workarounds. The
  operator may force-include one explicitly; the manifest records that choice.

## State

`manifest.json` and `stumbles.md` live in the repo at `.claude/unhobble/<experiment-id>/`, where
`<experiment-id>` is `<repo-basename>-<model-version>-<YYYYMMDD>-<nonce>` (a short random suffix
minted at snapshot). Phase 1 writes both files with the Write or Edit tool. The Phase 2 strip
commit carries them, and every later ledger or manifest update is committed on the experiment
branch the same way, so a later session's clone already holds the ledger.
`${CLAUDE_PLUGIN_DATA}/unhobble/<experiment-id>/` holds only `backups/`. It is
not the home of the manifest or the ledger.

The basename is a convenience label, not the identity. The manifest records `origin_url`,
`branch`, and `base_commit`, and no absolute host path. Every later phase resolves the current
origin URL and current branch, and checks that the recorded `base_commit` is still an ancestor of
HEAD. A mismatch aborts and names the field plus the recorded and current values. A repo with no
remote records `origin_url` as an empty string and compares that. `snapshot` never reuses an
existing experiment directory: a fresh run mints a fresh id. Resuming an open experiment means
passing its phase commands from a checkout of the recorded origin, on the recorded branch, at a
commit that still contains `base_commit`. A different absolute path is not a mismatch.

- `manifest.json`: every surface found, its classification (`behavioral` | `policy` | `hybrid` | `convention` |
  `non-derivable`, which is kept and restored like `policy`),
  what was stripped, how to restore it (repo-relative path, restore mechanism, backup location under
  the plugin data dir), `origin_url`, `branch`, `base_commit`, `branch_deviation` (empty, or why the
  experiment branch is not `experiment/unhobble-<model-version>`), target model, `effort` (see
  Effort below), `phase`
  (`snapshot` | `bare` | `observe` | `readd` | `closed`, or `watch` for a Deletion watch experiment),
  phase timestamps, and optionally `pr_url` (the experiment pull request, written when one opens).
  No absolute host path, in any field.
- `stumbles.md`: the observation ledger (one row per observed failure: date, task, what the model
  did, what was expected, suspected missing instruction, severity, effort), with any deletion watch
  recorded above the table (see Deletion watch).
- `backups/`, under `${CLAUDE_PLUGIN_DATA}` only: pre-strip copies of any non-git-tracked file
  modified or removed (settings hook entries, and an untracked instruction file the plan classified
  behavioral, which git cannot restore and so is never stripped through the git helper). Never
  commit `backups/`.

**Effort.** Caller effort for this run is `${CLAUDE_EFFORT}`. Copy that value into the manifest
`effort` field when Phase 1 writes the manifest, and into the Effort cell of each ledger row when
the row is written, so a stumble can later be compared with the effort level of the session it
happened in. Write `unset` when the value is empty or still reads as the dollar-brace placeholder
instead of a level name: the substitution did not run, or no level was available. Record what
rendered, never a guessed level; the value changes nothing else about the experiment.

- **Pointer**: for the `CLAUDE_EFFORT` substitution, see
  <https://code.claude.com/docs/en/skills#available-string-substitutions>.
- **As of**: 2026-10-02
- **Recheck trigger**: that table states what renders when no effort level is available, or drops
  the substitution.

`status` reads `manifest.json` and `stumbles.md` and prints:

- phase: manifest `phase`.
- elapsed days: today minus the first phase timestamp.
- ledger row count: table rows in `stumbles.md`.
- register holds: rules the close recorded as register holds (0 before `readd` closes).
- confounds: every `unstripped-*` record in the manifest, plus any confound the observe phase noted.
- PR URL: manifest `pr_url`; the line is omitted while the manifest lacks that optional field.
- re-add candidates and open and closed deletion watches.

## Phase 1: snapshot

1. Verify a clean working tree; refuse to start on a dirty tree or on the default branch. Create or
   confirm a dedicated branch (suggest `experiment/unhobble-<model-version>`). When the session is
   pinned to a designated branch (a cloud session's assigned branch, or one the operator names), use
   it as the experiment branch instead of creating one, and record `branch_deviation` in the
   manifest naming that branch and the pin. The default-branch refusal still applies to it.
   **Clean here means no
   tracked modification and no unrelated untracked file.** An untracked instruction file from the
   `instruction-files.sh` list is admitted, and only that: it is the ordinary shape of a
   `CLAUDE.local.md`, it is what step 3 is about to classify, and a gate that read it as dirt would
   refuse every repository the manifest backup route at Phase 2 exists for. Admitting it is not
   waiving it: an untracked file the plan classifies behavioral goes through that route, never
   through the git helper, and one the plan keeps is left in place like any other kept surface.
2. Inventory the live project instruction surfaces (the same liveness discipline as
   `audit-instructions` Phase A, lighter: what actually loads in a session here, not what is merely
   on disk). Record line counts per surface.
3. Classify **every surface the strip plan will touch**: hooks, rules, instruction files
   (CLAUDE.md / CLAUDE.local.md / `.claude/CLAUDE.md`, `AGENTS.md` / `.claude/AGENTS.md`,
   `.claude/skills/`, `.claude/agents/`), and project-enabled
   plugins alike: `policy` (enforces team/safety policy regardless of model, so kept), `behavioral`
   (corrects or scaffolds model behavior, so stripped), `hybrid` (one unit carrying both, with the
   split named, trimmed and never removed whole), or `convention` (team conventions in git, the
   operator's call, default set by the oracle test below). For hook entries specifically, the
   classification rubric, covering mechanism vs class, the hybrid trim-not-delete rule, and the
   ground-truth-oracle carve-out (behavioral purpose with a non-derivable machine oracle is a
   keep), is owned by the marketplace's plugin-philosophy "Classifying a hook" section
   (<https://github.com/melodic-software/claude-code-plugins/blob/main/docs/plugin-philosophy.md>);
   read it there and apply it to hooks, never re-derive it. Non-hook surfaces (rules, instruction files,
   skills, agents, plugins) classify by the class definitions above; `hybrid` applies to any unit
   whose behavioral and policy surfaces can be split in place. Classification is per unit that
   Phase 2 acts on: a hook entry, a rule file, a skill, an agent, a plugin. A **mixed** instruction
   file, where a CLAUDE.md or an AGENTS.md carrying both convention sections and behavioral lines is
   the common case, is not classified whole: split it in the strip plan, naming which sections are stripped and
   which are preserved (extracted to a retained file or left in place), so the convention
   carve-out holds at section granularity rather than being deleted wholesale with the file. A
   **hybrid hook entry** gets the same treatment at its own granularity: the strip plan names the
   behavioral surface (an injected prose payload, a coaching string) and the policy residue (the
   gate, the finding relay), and strips only the former, via the hook's own kill switch or
   config where one exists, otherwise recorded as `unstripped-hybrid-hook` with the confound
   noted for the observe phase. Never remove a hybrid entry's wiring whole; that takes the policy
   residue down with the behavioral surface.

   **Convention units: the oracle test.** The default for a `convention` unit rests on the
   [instruction exception register](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/instruction-exception-register/README.md)
   and the ground-truth-oracle rule in the plugin-philosophy section linked above. No vendor page
   states a convention exemption, and the register's definition of "highly important areas" is this
   repository's own. Ask per unit what still checks the convention once its text is gone.
   **Gating oracle remains** (a CI check, hook, or ruleset that fails or blocks a violation and is
   not itself stripped): default strip the prose and keep the gate, classified `policy`; a stumble
   then shows as a gate failure to log. **Advisory oracle remains** (a linter warning or report that
   blocks nothing): default kept, since a violation passes and a silent ledger says nothing; strip
   only on the operator's explicit call, recorded in the manifest. **No oracle:** default kept, and
   removal is permanent only through a closed Deletion watch. A unit matching a register class is
   kept whatever the test says.

   **Product surfaces.** Record any unit under `plugins/<name>/` (a skill, agent, hook, command, or
   any shipped file) as `unstripped-product-surface` and never strip it, whatever its class. The
   reason is changelog-parity: `check-changelog-parity.sh`, in the repository scripts directory,
   pairs a plugin's shipped files with its version and CHANGELOG (or a changelog fragment for a
   plugin in fragment mode), and an experiment branch carries no product change (Gotchas, two
   hats). Only the repo's own session surfaces are strip candidates.

   **Plugins, every one enabled at any scope.** Inventory user, project, and local
   `enabledPlugins`, and the set `claude plugin list --json` reports enabled. Emit one row per
   plugin: id, scopes, the component types it ships, hook-wiring or not, class, and the Phase 2
   action. A plugin is hook-wiring when it ships `hooks/hooks.json` or a manifest `hooks` field.
   **Claim:** those are the two places a plugin declares hooks. **Basis:** the plugins
   reference "Standard layout" table and `hooks` manifest field
   (<https://code.claude.com/docs/en/plugins-reference>), fetched 2026-09-28. **As of:**
   2026-09-28. **Recheck:** that page names another hook location. Classify each wired
   entry with the "Classifying a hook" rubric linked above; do not restate it and do not invent
   a second hook rubric. A plugin whose every component is policy (or behavioral with a
   non-derivable oracle) is kept, classified `policy`. One that carries such an entry beside a
   plainly behavioral component is `hybrid`: kept whole, recorded `unstripped-mixed-plugin`, with
   a per-hook kill switch still available when the plugin exposes one. One whose every component
   is behavioral is the overlay candidate. A plugin with no hook wiring is not
   automatically skill-only: inventory every component type that same table lists (MCP and LSP
   servers, agents, `bin/` executables, monitors, output styles, workflows, settings). An MCP or
   LSP server, executable, or monitor gives the model a capability it cannot derive, so the plugin
   is `non-derivable`. Only then apply this rubric to its skills, commands, agents, output styles,
   workflows, and settings: `policy`
   when one encodes an invariant you would keep with a perfect model; `non-derivable` when one
   carries a machine fact or procedure the model cannot derive; `behavioral` when all are
   convenience the model can do without. `policy` and `non-derivable` stay. `behavioral` is the
   overlay candidate. When the components disagree (a policy or non-derivable component beside
   behavioral ones), the plugin is `hybrid`: kept whole and recorded `unstripped-mixed-plugin`,
   the same rule as for hook-wiring plugins. A plugin force-enabled by managed settings cannot be disabled from project
   scope; record it kept. Managed settings are never edited.
4. Write `manifest.json` and an empty `stumbles.md` under `.claude/unhobble/<experiment-id>/`
   with the Write or Edit tool. Do not write them with a shell redirect or a heredoc. Present the
   strip plan (what goes, what stays and why) and stop for confirmation. Do not commit yet: the
   strip commit carries both files.

## Phase 2: bare

Apply the confirmed strip plan:

- Tracked instruction files: per the plan's per-file (and, for mixed files, per-section)
  classification, `git rm` / `git mv` a file classified behavioral whole; for a mixed file,
  remove the behavioral sections and keep the convention sections in place or in an extracted
  retained file. A file classified `hybrid` operationalizes exactly like a mixed file, stripping the
  behavioral sections and keeping the policy residue in place or extracted. The classes differ in what
  the residue is (policy vs convention), not in the mechanics. One commit, message
  `experiment: strip instruction surfaces for unhobble baseline`, and that commit includes
  `.claude/unhobble/<experiment-id>/manifest.json` and `stumbles.md`, with `phase: bare`. The
  clean-tree check already ran in Phase 1, before those files existed; other uncommitted dirt still
  refuses this phase.
- The root instruction files, for a plan that strips them whole, go through
  [scripts/instruction-files.sh](scripts/instruction-files.sh): `list <root>` reports which of
  `CLAUDE.md`, `CLAUDE.local.md`, `.claude/CLAUDE.md`, `AGENTS.md` and `.claude/AGENTS.md` are
  present, and `strip <root> <name>…` `git rm`s the ones the plan classified behavioral, printing
  what it moved, after checking every one of them is tracked and clean: `git rm` refuses an
  untracked file and a modified one alike, and either refusal mid-loop would leave the files ahead
  of it gone and the rest still loading. **An untracked instruction file, the ordinary case for
  `CLAUDE.local.md`, is not this helper's to strip**, since git holding the undo is what lets it
  remove anything at all. One the plan classified behavioral takes the same route as the settings
  entries below: back it up under
  `${CLAUDE_PLUGIN_DATA}/unhobble/<experiment-id>/backups/`, record the path and its restore in the
  manifest, and remove the working-tree file. The helper
  names it rather than stripping it, so the bare baseline is still
  reached, by the path that can actually restore it. **Name the files the plan approved.** A repository can hold
  a behavioral `CLAUDE.md` beside an `AGENTS.md` the plan classified `policy` or `convention` and
  chose to keep, and a strip of the whole list would delete the surface the plan said to retain;
  `--all` is there for the case where the plan did approve every one.
  **Both `AGENTS.md` names are strip CANDIDATES wherever the strip could make them live, and each
  is then classified like any other file.** Candidacy and classification are separate questions:
  candidacy asks whether removing the `CLAUDE.md` names would put this file in context, and
  classification asks what the file is. Neither is answered by "nothing appears to read it today",
  which is why Phase 1 must consider both names rather than passing over them: a session reads them
  as the project instructions only when no `CLAUDE.md` name displaces them, and this strip removes exactly those
  names, so a repository whose `CLAUDE.md` is a one-line `@AGENTS.md` shim ends the strip with its
  entire instruction surface still loading, from the file the shim pointed at, unless the plan
  considered that file at all. **What candidacy is conditional on is whether the strip could make the
  file live at all.** Removing the `CLAUDE.md` names is what makes a session read an `AGENTS.md`,
  but only in a session where `AGENTS.md` support is available and the instruction-files mode reads
  one: where availability is known unavailable, or the mode is `claude-md` or `managed-only`, the
  file stays unread after the strip, so stripping it changes nothing about the baseline being
  measured and only perturbs the other tools that read it. Leave it out of the candidate set only
  when a condition is known to rule it out **and** no `CLAUDE.md` imports or symlinks it; a merely
  unresolved condition keeps it, and so does a shim or import, since that import is itself a live
  path into context regardless of native support. The conditions carry their dated records in this
  plugin's [reference/agents-md-liveness.md](../../reference/agents-md-liveness.md); read them there
  rather than restating them here. What the classification then says is binding on an `AGENTS.md`
  exactly as on a `CLAUDE.md`: one classified `policy` or `convention` is kept and never named to
  `strip`, and a mixed or `hybrid` one is split at section granularity, not handed to `strip`,
  which only moves whole files.
- Project-settings hook entries classified `behavioral`: back up the settings file to
  `${CLAUDE_PLUGIN_DATA}/unhobble/<experiment-id>/backups/`,
  remove the entries, record the exact JSON paths removed in the manifest. An entry classified
  `hybrid` is never removed whole: strip its behavioral surface through the hook's own kill switch
  or config where one exists, else leave it wired and record `unstripped-hybrid-hook` (observe
  phase notes the confound), per the plan's named split.
- Plugins classified `behavioral`: record the prior enabled set in the manifest, then write
  `"<plugin>@<marketplace>": false` into the committed project `.claude/settings.json`
  `enabledPlugins` map. Keep every key in byte order (`LC_ALL=C` sort), one per line, which is
  what the repository catalog-enablement gate checks (check-plugin-catalog-enablement, under
  the repository scripts directory); an explicit `false` passes that gate
  as a recorded opt-out. Record each key's prior project value (absent or `true`) in the
  manifest. Restore to that value: set `true` back where the project had `true`, and delete the
  key where the `false` was newly added over another scope's enablement.
  A plugin classified `hybrid` is kept whole, behavioral parts recorded as
  `unstripped-mixed-plugin` (label unchanged for manifest continuity). Within that kept plugin, a
  behavioral or hybrid hook may still be stripped when a per-hook kill switch exists (a
  `<hook>_enabled`-style userConfig option): record the option flipped and its prior value,
  restoring by flipping it back. No switch means the hook stays loaded:
  `unstripped-behavioral-hook` or `unstripped-hybrid-hook`, as before.
  **Claim:** a project-scope `enabledPlugins` value of `false` overrides a user-scope `true` for
  the same `plugin@marketplace` key. **Basis:** the settings reference
  `enabledPlugins` section, "Project settings take precedence over user settings"
  (<https://code.claude.com/docs/en/settings-reference>), fetched 2026-09-28. The worked example
  on that page is the other direction: a user `false` does not disable a project `true`.
  **As of:** 2026-09-28. **Recheck:** that section no longer says project settings take
  precedence over user settings, or it states that a project `false` does not override a user
  `true`. Do not call an arm stripped until a fresh session's `claude plugin list --json` omits
  the plugin. One that is still listed is a confound; local or managed scope can still win.
- Print the "you are bare" summary: what a fresh session will now load, which plugins were
  disabled, which were kept as policy or tooling, which are `unstripped-mixed-plugin`, and how
  to restore everything (`readd` phase reads the manifest; `git` holds the files).

Start a **fresh session** after stripping. The current session already carries the old
instructions in context, so it cannot measure their absence.

## Phase 3: observe

Work normally on real tasks for a meaningful window (days of real work, not one toy prompt). When
the model stumbles, doing something an instruction used to prevent, missing a convention, or breaking a
workflow, append a row to `stumbles.md` with the Write or Edit tool and commit that update on the
experiment branch. The Effort cell is filled as State's Effort paragraph says:

| Date | Task | What happened | Expected | Suspected missing instruction | Severity | Effort |

The first ledger commit sets `phase: observe`. Log honestly, including surprises in the other direction (things the bare model now does *better*;
mark those `improvement`, since they are the deletions proving themselves). The ledger is the experiment's
entire evidentiary output: an unlogged stumble cannot earn an instruction back. An empty ledger after
real work licenses deleting an editorial candidate only. The strip removed the whole surface at once,
so a ledger cannot attribute silence to one rule: a consequential rule the ledger did not defend goes
back to a Deletion watch (or is restored) and is never made permanent by this ledger, and a
protected-class rule is restored (Phase 4).

## Phase 4: readd

**Refuse to run while the manifest `phase` is `bare` or `observe`.** Print the phase and the ledger
row count from `stumbles.md`, and stop: the strip just landed or the window is open, and rows logged
so far are not yet the evidence the gate reads. The operator ends the window by saying so; that sets
`phase: readd`, committed. A watch experiment (`phase: watch`) never reaches this phase; its
restore and close rules are under Deletion watch, unchanged.

1. Group ledger rows by suspected missing instruction. The gate: **at least two rows, same
   underlying cause.** One-off failures do not reopen a standing line; retry the task first.
   The grammar is shared with the Deletion watch: a row is one ledger line, rows that share an
   underlying cause count as one, and the commit that acts cites the rows. The watch defines no second
   grammar, only its own threshold: one attributed row after aggregation ends a watch, where restoring
   here takes two. That asymmetry is this skill's rule, not the spec's: restoring is cheap and
   reversible, and the removal is the risky act.

   **Ledger grouping.** No script parses `stumbles.md` (`instruction-files.sh` handles instruction
   files only), so read the table and cluster it by hand. Put each row under its suspected missing
   instruction, then merge groups whose rows share one underlying cause. Report every group as:
   the instruction, its row dates, and `clears` (two or more rows) or `below the gate` (one row).
   Rows marked `improvement` never count toward a group. Present the report and stop; restoring
   goes through steps 2 to 5.
2. For a root instruction file being restored whole,
   `scripts/instruction-files.sh restore <root> <pre-strip-commit> <name>…` puts back the names it
   is given, and only those. **Name the file the ledger defended; never restore the set.** A
   restore that returned every stripped file would hand back the instructions the ledger did not
   defend, which is the whole result this phase exists to protect. **`--all` is the abandon path,
   never the close path.** Closing an experiment normally leaves the undefended editorial surfaces
   retired, per steps 4 and 5 below; that is the finding, so a close never calls it. It is for walking the
   whole experiment back to its pre-strip state and discarding the result: it overwrites what is on
   disk rather than skipping it, and it removes an instruction file the pre-strip state did not have
   **and git tracks**. One that was never tracked it names and leaves, since git cannot tell a file
   the experiment created from one that predated it and was never committed, and deleting the
   second is unrecoverable; an abandon can therefore leave an untracked file of the experiment's own
   behind, named on stderr for the operator to remove.
   For each group that clears the gate, restore the narrowest instruction that addresses the cause,
   a single line or rule file rather than the whole pre-experiment surface, and cite the ledger rows in
   the restoring commit or an adjacent comment.
3. For instructions being rewritten rather than restored verbatim, route the text-level judgment to
   `audit-instructions` (same plugin), which owns instruction-content-vs-doctrine analysis.
4. Everything the ledger did not defend and that is editorial stays deleted. A consequential rule
   (Deletion watch defines the tier) the ledger did not defend is not left deleted on this ledger:
   restore it, or restore it and open a Deletion watch, which alone can make its removal permanent.
   A rule matching a protected class in the [instruction exception
   register](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/instruction-exception-register/README.md)
   is restored regardless of whether the ledger logged a stumble against it. The strip itself
   is fine: it is reversible and branch-local, which is why the experiment may run over a protected
   rail at all. What the register forbids is leaving one deleted on the evidence of silence. A rail
   whose absence is unrecoverable will not usually announce itself inside one experiment window;
   "no stumble was observed" is the weakest evidence available against it, and the register exists
   because that inference is the one this phase would otherwise make. Restoring a protected rule
   this way is not a failed deletion, so do not count it as a retained surface in the ledger's
   defense tally; record it as a register hold with its class.
5. Close the experiment: final manifest update (`phase: closed`, surfaces restored vs retired
   counts, register holds and consequential rules sent to a watch listed separately), and merge or
   fold the experiment branch per the repo's normal PR flow. The register hold covers only protected rules, so before that merge run
   `/review:security-review` against the pull request (if the `review` plugin is installed). Its
   instruction-surface lens checks every rule the merge leaves deleted for a guardrail nothing else
   enforces. Without the plugin, record in the pull request body that the retired rules got no
   security pass.

## Deletion watch

`watch` is the deletion direction of the re-add grammar above. It does not add a row shape, a
second ledger, or a second gate. Use it for one consequential rule: a rule that governs a
situation and does not match the instruction exception register. An editorial candidate (removal
would not change behavior, the content is derivable, or it restates the obvious) does not enter
a watch; `audit-instructions` clears that tier on its normal criteria. A protected-class rule
never enters a watch. Name the class and stop.

A watch is the only route to a permanent consequential deletion, whether the rule came from an
audit or from a strip's undefended surface. It runs inside an experiment. When none is open, start
one for the single rule: mint an experiment id, create the dedicated experiment branch, and write `manifest.json` and an empty
`stumbles.md` under `.claude/unhobble/<experiment-id>/` as Phase 1 does (see State), with
`phase: watch` and the watched rule as the only surface. Before any removal, record the watch in `stumbles.md`, above the
ledger table: the rule, quoted,
and the surface it lives on; the governed situation, stated as where its absence would show; the
window, a count of qualifying sessions (sessions that entered that situation), not a wall-clock
duration; and the disqualifier, any stumble attributable to the rule, which ends the watch.

Present the rule, its surface, and the watch record, and wait for confirmation. Then remove the
rule and keep it removed for the whole window. Qualifying sessions are fresh sessions on the
experiment branch with the rule removed, never the session that removed it. Each one that entered
the governed situation is counted by a dated one-line entry under the watch record, committed on
the branch; the window is met when the entries reach the recorded count. A watched rule is never kept
loaded: a rule still in context prevents the stumble it exists to prevent, so zero attributed rows
would say nothing about whether it can go. A disqualifying stumble ends the watch and restores the
rule.

Attribute a stumble by that governed situation. Same-cause aggregation is the re-add gate's rule.
Co-absence is not attribution. When several rules were removed together, a stumble attaches to
one rule only when exactly one removed rule governs the situation. When two do, the row attaches
to the group and those deletions are reverted together.

A watch that never accumulates qualifying sessions expires unresolved. Report that. It is not
evidence the rule can go.

The deletion is warranted when the qualifying-session count is met and the attributed row count,
after same-cause aggregation, is zero. The commit that makes the removal permanent cites the watch
the way a restoring commit cites its ledger rows. Present the closed watch and wait for
confirmation before the removal is kept. A closed watch with
zero attributed rows is what clears the consequential tier. Until that citation exists, the tier
is not clear, and silence is not a warrant.

## Decide

`decide` resolves the open decisions an experiment leaves (a convention unit's default, a
consequential rule that needs a watch, a kept-or-retired call) without a new engine, script, or
manifest schema. It composes skills that are already there:

1. List the open decisions from the manifest and ledger, one line each.
2. When the `discovery` plugin is installed, run `/discovery:research` once per decision and keep
   one memo per decision. When it is absent, say so and ask the operator each decision as a
   question instead; the steps below do not run.
3. Give each decision's memo to two blind decision agents that never see each other's answer.
4. Two agents that agree give a consensus: present it with the memo and stop for confirmation.
   Two that disagree return to the operator as a question that states both positions.

`decide` never mutates. A confirmed decision is applied by the phase that owns it.

## Cadence wiring (optional)

The re-run trigger is the next frontier model release. To make that standing rather than
remembered: if the `work-items` plugin is installed, add a recurring item ("re-run
`/harness-config:unhobble` against the new model") rechecked on model upgrades; otherwise a note in
the repo's own conventions or a calendar reminder serves. This skill never wires a schedule itself:
scheduling surfaces vary per consumer and are the operator's choice.

## Gotchas

- **Do not run the observe phase inside this session.** Instructions already in context defeat the
  measurement; strip, then start fresh sessions for real work.
- **A plugin marketplace repo has two hats.** Running this skill in a plugin-publishing repo
  ablates that repo's *own* session surfaces only; the components it ships to consumers are its
  product, audited by their own acceptance gates, not stripped by this experiment. Phase 1 records
  each one under `plugins/<name>/` as `unstripped-product-surface`, and changelog-parity is why.
- **`CLAUDE_CODE_SIMPLE=1` / `--bare` and `CLAUDE_CODE_SIMPLE_SYSTEM_PROMPT=1` are not part of this
  contract.** Two distinct, documented switches (official env-vars reference; binary-verified
  2026-08-17): simple mode (`CLAUDE_CODE_SIMPLE=1`, CLI flag `--bare`) disables fetches, keychain
  reads, and `CLAUDE.md` auto-discovery, while `CLAUDE_CODE_SIMPLE_SYSTEM_PROMPT=1` swaps in the
  lean built-in system prompt. Both ablate *Claude Code's own* surfaces, so this skill neither sets
  nor depends on either: the experiment here ablates *your* instructions, which is the part you
  own. (Measuring what those product-side switches buy belongs to a context-budget audit, not to
  this experiment.)
- **Windows:** repo-relative restore paths in `manifest.json` use forward slashes. The manifest
  still records no absolute host path.
- **Machine-specific paths.** A committed manifest that contains an absolute host path fails the
  machine-specific-paths CI lane. This skill records none: identity is `origin_url`, `branch`, and
  `base_commit`.
- **State writes go through Write or Edit.** Write the manifest and the ledger with those tools,
  never a shell redirect or heredoc: a shell write skips the Write and Edit hook gates. Where the
  guardrails plugin's `block-hook-bypass` hook is installed it can block such a write; its README
  states what it catches and what it exempts.

## What this skill does NOT do

- Never strips managed settings, user-global surfaces (without explicit opt-in), or policy-classified
  hooks by default.
- Never mutates without presenting the change set and getting confirmation.
- Does not judge instruction text against doctrine; that is `audit-instructions`.
- Does not schedule its own re-runs; cadence wiring is the operator's, per above.
