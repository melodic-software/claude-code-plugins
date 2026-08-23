# Changelog

All notable changes to the `implementation` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.15.3]

### Changed

- Normalized fleet-wide framing this plugin restates (cross-vendor advisor
  fallback, untrusted-content posture, attribution/idiom prose — as touched) to the canonical
  SSOT wording, operable text kept inline with provenance-only citations (#2698).

## [0.15.2]

### Fixed

- **`implement-dispatch`'s unverified-versus-omitted rule names the lanes it borrows from.** It
  read "the same grounding rule the loop lanes apply to their cycle reports" — an unresolvable
  pointer for a consumer who installs `implementation` alone and has never met that phrase. It now
  names `work-items:work-loop` and `source-control:babysit-loop`, which is what 0.15.0's own
  release note already told a changelog reader the rule cited. The wording deliberately echoes
  theirs: same reason, same unwatched-run failure mode, so a reader who has seen one recognises the
  other.

## [0.15.1]

### Changed

- **Cross-skill chains name the Skill tool (#3002).** `implement`'s Karpathy pre-execution
  checklist, its scope-creep and major-divergence replan routes, its research escalation, the
  pre-PR sequence read (`/session-flow:workflow pre-pr`), the config/docs verification note, and
  all four rows of its handoff table — the mid-implementation research row and the pre-PR-sequence
  row were left bare beside two rewritten siblings; `implement-dispatch`'s main-side build/test in
  both the cadence step and the integration table, the worker's worktree provisioning
  (`/source-control:worktree`), and the inline-routed hand-back.
  Wording only — routing thresholds, gates, and step order unchanged.

- **`implement-dispatch`: citations to `/implementation:implement`'s NAMED STEPS stay citations
  (#3002).** The first pass rewrote "run the `/implementation:implement` 'Step 1: Prerequisite
  Check' preflight" into "invoke `/implementation:implement` via the Skill tool and run its
  'Step 1…'", and did the same to the Step 3 divergence ladder, the Step 4 phase-boundary ritual,
  and two integration-table rows. Those are different actions: the text says to APPLY another
  skill's enumerated checklist here, not to hand control to it — and handing control to it is a
  re-entry hazard, since `/implementation:implement`'s Step 0 detects worker routing and chains
  straight back into this skill. All five sites are back to the citation form, and the
  Prerequisites paragraph now says outright that the criteria are enumerated in place and names
  the loop it would otherwise create. Genuine whole-skill hand-backs (the inline-routed cadence
  hand-back, and "All phases complete" → Step 5) keep the invocation phrasing.

## [0.15.0]

### Added

- **`implement-dispatch`: the autonomous deviation log is now append-only, and each entry carries
  its evidence and its outcome.** Absorbed from an upstream cursor/plugins skill
  (`docs/upstream/cursor-pstack.md`, the `show-me-your-work` section). `DEVIATIONS.md` already
  recorded what was planned, what was done instead, why, and the blast radius; it said nothing about
  whether the entry could be edited later, how an entry should be backed, or whether the choice
  actually worked. Four rules close that: append and supersede rather than edit, because rewriting
  history hides the reversal a PR reviewer most needs to see; evidence is a pointer (a SHA, a
  `file:line`, a test name) and preferably one a committed script produced, so the reviewer can
  re-run it rather than believe it; an entry carries its outcome and says `unverified` rather than
  reading as settled; and one entry is one decision, because an entry that does not fit on a line or
  two is a decision that is not crisp yet.

  The unverified-versus-omitted rule deliberately cites the grounding discipline
  `work-items:work-loop` and `source-control:babysit-loop` already apply to their cycle reports
  rather than restating it a third time — same reason, same unwatched-run failure mode.

  Selected as the landing site after checking every audit-trail surface in the fleet: this is the
  only one that is a decision trail written by the acting agent at decision time. The others are a
  change inventory, loop counters, a hook-wired notification record, an in-place status comment,
  OTel spans whose contract forbids a parallel schema, and a human-attested return record that says
  outright it is "not activity". That table is in the provenance file, and it is why this landed as
  an absorb into one consumer instead of a marketplace convention.

## [0.14.0]

### Changed

- **`implement`'s completion handoff stops prescribing its own pre-PR order (closes #3047).**
  Step 5 is titled *"Hand off to the pre-PR sequence"* and then prescribed an order that sequence
  forbids: `/verification:confirm` first, review after. `session-flow`'s `pre-pr.md` puts review at
  step 2 and outcome verification at step 7, with the simplify pass (4–6) between them — so under
  this skill's order, `confirm` rendered its verdict on pre-simplify code and the simplify edits
  shipped unverified.

  Both sites (step 5 and the chaining table's completion row) now read **review → verify → PR**,
  with every presence gate intact: `/review:quality-gate`, then `/verification:confirm` once the
  diff is final, then `/source-control:pull-request`, each gated on its plugin being installed and
  each keeping its stated fallback. Step 5 also now points at
  `/session-flow:workflow pre-pr` (gated) for the sequence itself, so the handoff names its
  destination instead of paraphrasing it.

  This was a one-surface correction, not a coin flip between two doctrines. The `verification`
  plugin's **own** chaining table already fired on "review gate passes (no blocking findings)" →
  suggest `/verification:confirm`, and suggested the PR flow only after a CONFIRMED verdict. The
  skill that renders the verdict, the skill that lists the sequence, and the plugin that opens the
  PR all agreed; this handoff step was the lone dissenter. The order now has an owner doc,
  `docs/conventions/pre-pr-ordering/`, which both surfaces cite.

## [0.13.2]

### Changed

- **Upstream doc stamps re-verified against the live pages (2026-08-10).** Each dated claim below was re-checked against the complete raw markdown source of the page it cites (`https://code.claude.com/docs/en/<page>.md`), not a summarized fetch, and each was confirmed by a verbatim quote before its stamp was refreshed. No claim changed; only the verification dates moved.

  - `agents/implementer.md` — a subagent at the spawn-depth limit doing its delegated work itself
    and returning one summary (subagents reference), quoted verbatim.
  - `skills/implement-dispatch/SKILL.md` — the subagent model resolution order
    (`CLAUDE_CODE_SUBAGENT_MODEL`, then the per-invocation `model` parameter, then frontmatter,
    then the main conversation's model).

## [0.13.1]

### Changed

- **`/implementation:implement`'s `description` now uses `Use when:`.** Its routing phrases sat
  behind a lowercase `use for`, which the skill-quality gate does not recognize as trigger phrasing.
  `'build this'`, `'write the code'`, `'make this change'` and `'apply the plan'` join the four
  already there, all of which are preserved verbatim.
- **`/implementation:implement-dispatch` gained typed trigger phrases.** Its `Use when` clause
  described a *state* ("the plan routes phases to worker surfaces") with no phrase a user would
  type, so the gate saw no trackable trigger at all. `'dispatch this to workers'`,
  `'run this with subagents'`, `'execute the plan in parallel'` and `'fan the plan out'` now precede
  that condition, which is retained.

## [0.13.0]

### Removed

- **The bare `/<skill>` alias for this plugin's skills.** Their `SKILL.md` files no longer
  declare a frontmatter `name`. The field is optional and defaults to the directory name, so
  declaring it only restated the path while registering a second, unnamespaced command — which
  the slash-command picker then echoed back as `/plugin:skill (skill)`. Invoke a skill by its
  namespaced command; the command itself is unchanged.

## [0.12.1]

### Added

- **The TDD cadence now defines "minimum to pass" so it cannot be satisfied by gaming the
  assertion.** "Implement the minimum to pass (green)" is exactly the phrasing a literal model can
  meet by hardcoding the test's expected values, special-casing its inputs, or weakening the
  assertion. Step 2 now states that the minimum means the smallest *correct* implementation, and
  requires a deliberate, stated correction when the test itself is wrong.
- **`feature.md` gained a gold-plating pitfall.** Its sibling `bugfix.md` has carried "Fix minimally"
  all along, and `SKILL.md`'s scope-creep guard only routes a *bigger task* back to planning — it
  never addressed building beyond an agreed slice. The new pitfall sets the bar at a second caller
  existing rather than being anticipated.

## [0.12.0]

### Changed

- **`implement`: the mid-phase handoff no longer triggers on a self-estimated context budget.** The
  guidance read "Mid-phase handoff is still appropriate when context is heavy or a pause is
  imminent", which asks the model to judge its own window and hand off on that judgement — the shape
  the `claude-config` instruction-audit catalog's check I23 detects, and the same clause removed from
  `session-flow`'s `handoff` in this pass. The licensed triggers are now an imminent pause, the
  user's report, an instrument that measures the window, or visible drift in the responses; a budget
  reading is a measurement, not a decay signal. Writing the ad-hoc note stays exactly as valuable as
  before — only the trigger that invented the occasion is gone.

## [0.11.0]

### Changed

- **The phase-worker brief now states why the phase exists**, alongside the scope fence, the
  divergence-escalation clause, the project invariants, the acceptance criteria, and any model
  routing. This is the highest-stakes dispatch surface in the marketplace — its workers edit source
  — and it was specifying every boundary and no intent.
  - A fence and a reason do different jobs, and the brief said so only halfway: a fence states what
    a worker may not touch, and a worker that knows only its boundaries resolves every *in-bounds*
    ambiguity toward the literal brief instead of the outcome. That is how a phase comes back
    conforming and useless — passing its scope fence, passing its acceptance criteria as written,
    and not being the change that was wanted.
  - Sourced from Anthropic's Fable 5 prompting guide, "Give the reason, not only the request", which
    names long-running agents drawing on multiple workstreams as the case where intent matters most.

## [0.10.0]

### Added

- **Structural capability-tier model bindings at the dispatch seam (`#1649`).** Two new plugin
  agents, `implementer` and `phase-verifier`, carry an explicit `model` frontmatter binding of the
  strong capability tier's current alias, replacing the default `inherit` that let a fast
  orchestrator root silently run implementers (and their verifiers) at orchestrator strength.
  `implement-dispatch`'s cadence now dispatches workers as `implementation:implementer` (step 2)
  and the phase-boundary verifier as `implementation:phase-verifier`, reserving the per-invocation
  `model` parameter for upward (frontier-tier) routing only, with a gotcha documenting that a set
  `CLAUDE_CODE_SUBAGENT_MODEL` (any value but `inherit`) outranks the binding. Tier definitions
  stay order-defined and family-agnostic per the marketplace's loop-lane convention §3 — the alias
  binding lives only at this seam, and the verifier binds never weaker than the implementer it
  checks. Frontmatter binds a floor, not a session-relative value, so both the cadence and the
  agent bodies record the upward-only override duty when the session's model resolves above the
  binding (per the plugin philosophy's session-relative ladder). Each agent also declares an
  explicit tool cage — a change from the previously ungoverned generic-subagent tool surface: the
  implementer grants file edit, search, shell, web research, skill invocation, and nested dispatch
  (that last one conditional — the harness withholds `Agent` from a subagent at the spawn-depth
  limit whatever the `tools` list says); the phase-verifier bars Edit/Write and agent spawning, with
  Bash retained for inspection (stated as the cage it is, not as "read-only", per the plugin
  philosophy's named-agent bar). Both also bind `effort` rather than inheriting the session's level,
  matching this marketplace's other named agents — a model binding alone would still let an
  orchestrator that lowered effort for its own bookkeeping lower it for the phase work. Neither
  agent sets `maxTurns`, unlike every `discovery` and `review` agent in this marketplace (all of
  which cap, between 25 and 40). The documented semantics are that the
  field is the "maximum number of agentic turns before the subagent stops"; *applied inference,* not
  a documented claim: a stop is not a failure signal, so the return an orchestrator receives from a
  capped verifier that outran its budget is a truncated report shaped exactly like a verdict. The
  phase-verifier is therefore contracted to return INCONCLUSIVE rather than a partial PASS, and
  `implement-dispatch`'s phase-boundary clause makes that return re-dispatch a fresh verifier
  against the named gap instead of marking the phase `[DONE]`. The implementer is uncapped for the
  narrower reason that a phase's length is set by its brief — a real exposure, since its cage grants
  edit and shell, and one the brief's scope fence rather than a turn budget is the control for.
  (Frontmatter `model` and `effort` values, the env → parameter → frontmatter → inherit resolution
  order, the `maxTurns` definition quoted above, and the depth-limit `Agent` withholding verified
  against <https://code.claude.com/docs/en/sub-agents>, 2026-07-27.)

## [0.9.2]

### Changed

- **`implement`: the phase-boundary handoff step no longer restates `session-flow`'s save-point
  section list.** It carried a reordered, partial copy of that taxonomy which had already drifted
  from the owner doc. When `session-flow` is installed the step now defers to
  `/session-flow:handoff`, which owns the format. Without it, this skill owns the fallback shape, so
  the step states it directly: the note must stand on its own — what shipped, the decisions made and
  why, the approaches tried and ruled out, the files modified, anything already applied that must
  not be repeated, and the ordered remainder — plus the two items specific to a phase boundary, the
  sanity-check evidence and the next-phase pointer. The fallback is unchanged in substance; what
  changed is that it is now stated as this skill's own contract rather than as a copy of another
  plugin's section names.

## [0.9.1]

### Changed

- `/implementation:implement` now makes its existing project-policy precedence explicit across the
  central cadence and its feature and bugfix mode contexts: TDD remains the fallback when the
  consumer is silent, while a testing-cadence instruction in the consumer's `CLAUDE.md` or rules
  overrides the fallback. The README documents a concrete tests-after opt-out; no user-scoped
  `userConfig` option was added. Closes #406.

## [0.9.0]

### Added

- **`implement-dispatch` gains an optional `--wave-cap <N>` argument that overrides the internal 3–5
  concurrent-wave default (`#573`).** The parameter is the single enforcement point for a
  caller-configured concurrency ceiling: passed, it caps concurrent dispatch waves at `N`; omitted, the
  internal 3–5 default stands, so existing callers are unaffected. `/work-items:work` threads its
  `work_dispatch_concurrency_cap` here (and passes nothing when the key is unset), wiring the
  previously-inert config to real enforcement. A fractional argument is floored to whole waves and a
  value below 1 is treated as 1, since a wave is discrete.

## [0.8.0]

### Added

- **`implement-dispatch`'s brief-composition step now covers worker-side worktree provisioning for the
  autonomous lane (`#572`).** When provisioning is worker-side — the autonomous work-lane, where the
  orchestrator cannot invoke `/source-control:worktree create` without transitioning its own session —
  the brief makes materializing the isolated worktree the worker's first step (the non-entering
  creation seam, or a plain `git worktree add`, worked via `git -C` without entering), and instructs
  the worker to bring the branch current with the default branch, commit, push, and return the
  worktree path + branch so the orchestrator can open the PR against the pushed branch. The
  interactive default — the brief supplies a pre-existing worktree path — is unchanged.

## [0.7.8]

### Changed

- `implement-dispatch`'s fresh-context verifier before marking a phase `[DONE]` (`skills/implement-dispatch/SKILL.md`)
  now prefers a cross-vendor advisor when one is installed (e.g. the OpenAI Codex plugin, invoked per its own docs), with the fresh-context same-vendor verifier sub-agent as the stated fallback —
  presence-gated per the seam-phrasing convention.

## [0.7.7]

### Changed

- `implement-dispatch`'s "Compose the brief" step (`skills/implement-dispatch/SKILL.md`) now front-loads
  CI-hygiene and early-push clauses alongside the existing worktree-cwd clause: no issue-number back-references
  in code comments (the `comment-hygiene` check flags them; `TODO(#issue)` is the sanctioned exception);
  any new regular file with a shebang (never a `120000` symlink — `git update-index --chmod=+x` fails on
  one) must be marked executable on both the worktree and the index, in order — `chmod +x <path>`, then
  `git add <path>` to stage it (a not-yet-tracked path fails `git update-index --chmod=+x` outright), then
  `git update-index --chmod=+x <path>` to force the index mode explicitly, since a plain `git add` alone
  can't be trusted to carry an executable bit across every platform/filesystem (the `exec-bit` check flags
  a tracked shebang file recorded non-executable); and commit and push as early as practical — before the
  CI-poll tail — so a mid-flight worker session-limit death never orphans unpushed work. That early commit
  is a source-only checkpoint; the phase-boundary plan-mark commit (`/implementation:implement` Step 4 item
  4) still runs separately, orchestrator-side, once the phase's acceptance criteria are verified — a scoped
  exception to inline mode's combined source+marks commit, noted in "Phase boundaries." PR creation stays
  out of every worker brief; it belongs to the orchestrator's post-verification flow (Step 5), invoked only
  after every worker return is verified and the build/test gate passes. Reinforced as Gotchas-section
  reminders, matching the worktree-cwd clause's existing pattern. Closes #819, where fresh dispatched
  workers repeatedly learned these same PR-contract constraints via red CI instead of the brief.

## [0.7.6]

### Changed

- Skills with `!` dynamic-context injections now declare `shell: bash` explicitly, per
  the pinned precompute convention — bash-only pipelines must not fall through to a
  PowerShell host.

## [0.7.5]

### Changed

- Documentation-only: the License section now states the plugin's own MIT
  license inline and no longer points at a `LICENSE` file at the repository
  root, which an installed consumer running from the isolated plugin cache
  cannot reach. No behavior change.

## [0.7.4]

### Changed

- `implement-dispatch`'s "Compose the brief" step (`skills/implement-dispatch/SKILL.md`) now requires
  a worktree-cwd clause whenever a worker edits in a dedicated worktree: the brief must give the
  worktree's absolute path and instruct the worker to never rely on the shell's working directory
  persisting across separate tool calls — anchoring every command that touches the worktree (file
  edits and git operations alike: `status`, `add`, `commit`, `diff`, `log`) with
  `git -C <worktree-path>` (or a re-`cd` per call) rather than a one-time `cd`, since cwd can drift
  between a read and the next write and silently risks committing into the wrong checkout. Reinforced
  as a Gotchas-section reminder. Closes the correctness gap behind #566, where a dispatched worker's
  edits landed in the canonical checkout instead of its assigned out-of-tree worktree.

## [0.7.3]

### Changed

- Stack-qualified the `implement` skill's optional-collaborator references: the mode contexts
  (`skills/implement/context/feature.md`, `bugfix.md`, `refactor.md`) retain their `dotnet-*`
  marketplace-skill names and `## Marketplace plugin skills (invoke only when installed)` presence
  gate, and each now opens with a lead-in that frames those skills as .NET-ecosystem forward
  references — invoked only when your stack is .NET and the plugin is installed — with an explicit
  fallback to the project's own tooling otherwise, so a non-.NET consumer keeps the generic path
  first-class rather than being handed a dead list. Matches the conforming `testing` (#491) and
  `verification` (#526) pattern per the ratified #412 disposition governing #405. No reference
  removal; every reference stays optional and installed-gated.

## [0.7.2]

### Changed

- Layer-vocabulary agnosticism: the `implement` skill's cross-layer guidance
  (`skills/implement/SKILL.md` "Dependency direction" and
  `skills/implement/context/feature.md` step 3) no longer bakes the .NET/Clean-Architecture
  layer names (Core/Domain/Application/Infrastructure) as a universal execution order. The
  principle is restated as dependency direction — implement depended-upon components before
  their dependents, respecting the project's own dependency direction — and the layer names
  are demoted to a clearly-marked ".NET, for example" illustration, per the
  `docs/PLUGIN-PHILOSOPHY.md` design boundary.

## [0.7.1]

### Fixed

- Branch-naming grammar in `/implementation:implement` Step 1 and its gotchas no longer presents
  `<type>/<description>` as the mandated form; it now defers to the consuming project's branch-naming
  convention (its `CLAUDE.md` / `AGENTS.md` / rules) and frames `<type>/<description>` as a common default, mirroring
  the commit-message convention deferral. The branch-check eval is reframed to accept any convention-
  compliant branch name rather than a single hardcoded grammar.

## [0.7.0]

### Changed

- Adopt topic-docs contract 2.0.0 (visibility semantics): `reference/topic-docs.md` ties the
  phase-commit rule to the contract's visibility guarantee — isolated contexts see the contract
  slice as committed state only — and states the by-value return rule for dispatched workers.

## [0.6.2]

### Changed

- References to the renamed `/planning:plan` skill (was `/planning:architect`, planning 0.13.0 breaking rename) retargeted. Version bumped so existing installs receive the rewritten prompts.

## [0.6.1]

### Changed

- References to the renamed `/toolchain:build` skill now invoke `/toolchain:check` (toolchain 0.2.0 breaking rename). Version bumped so existing installs pick up the rewritten prompts.

## [0.6.0]

### Changed — nine skills extracted into three new plugins (migration required to retain them)

**The `implementation` plugin is now two skills — `/implementation:implement` and
`/implementation:implement-dispatch`.** The other nine skills moved out into three new plugins.
Consumers who relied on any moved skill MUST install the new plugin that now owns it to keep the
capability — there is no renames-map path for extracted skills:

- **`build`, `lint`, `setup` → the new `toolchain` plugin** (skill names unchanged):
  `/toolchain:build`, `/toolchain:lint`, `/toolchain:setup`. The `reference/resolution-ladder.md` and
  the `reference/ecosystems/` portable defaults moved with them.
- **`test-plan`, `test-write`, `test-e2e`, `test-diagnose` → the new `testing` plugin, renamed:**
  `/testing:plan`, `/testing:write`, `/testing:e2e`, `/testing:diagnose`.
- **`verify-changes`, `verify-improvement` → the new `verification` plugin, renamed:**
  `/verification:confirm`, `/verification:measure`.

This split is **presence-gated graceful degradation, NOT a hard dependency.**
`/implementation:implement` and `/implementation:implement-dispatch` still run their cadence when a
companion plugin is absent — they fall back to the project's own build/test command and to self-verifying
the outcome against the plan/intent — and prefer the companion skill (`/toolchain:build`,
`/verification:confirm`, `/testing:*`) when it is installed. To restore the full former surface, install
`toolchain`, `testing`, and/or `verification`.

### Changed

- **Seam references rewritten to the new namespaces and presence-gated.** Every in-skill reference to a
  moved skill now names its new plugin (`/toolchain:*`, `/testing:*`, `/verification:*`); active
  invocations are gated with a graceful fallback, and relationship prose that called the moved skills
  "siblings" is reframed to "companion skills in separate plugins."
- **`reference/topic-docs.md` trimmed** to the artifacts these two skills write — `PLAN.md` progress
  marks, the `DEVIATIONS.md` log, the status summary, and handoff notes. Verification manifests and
  baselines are now the `verification` plugin's, bound in its own `reference/topic-docs.md`.

## [0.5.0]

### Added

- **Optional `tool-pin` version-drift warning in `/lint`.** The ecosystem-commands contract gains an
  optional `tool-pin` key (pinned tool versions keyed by tool name; contract 1.1.0): when the resolved
  config pins a tool version, `/lint` warns if the installed version drifts from the pin (a pin
  typically mirrors the consumer's own CI pin). Inert when absent — no pin, no check.
- **`/implement` over-correction trap logs to the session retro.** When the Step 3.5 over-correction
  guard fires, document it in the session's retro — surfaced to `/session-flow:retro` when the
  `session-flow` plugin is installed; otherwise noted in the completion summary.

## [0.4.0]

### Changed

- **Consume the topic-docs convention** (`docs/conventions/topic-docs/README.md`). Artifact placement
  follows document nature across two tiers, bound for this plugin in the shared
  `reference/topic-docs.md`: `PLAN.md` progress marks and the `DEVIATIONS.md` log are contract-tier
  (`docs/topics/<slug>/`, committed on the task branch, pruned before merge — or the memory tier under
  `contract_tier: local`); baselines, raw captures, and the status summary are memory-tier
  (self-ignoring `.work/<slug>/`); fallback handoff notes land in the memory tier's `.work/handoffs/`
  home owned by `session-flow`. Placement resolves through the contract's resolution order (concern
  file `.claude/topic-docs.yaml` first) with its runtime guards: `git check-ignore` on the session's
  first contract-slice write, and a first-per-session self-ignore check scoped to the resolved memory
  root; no edits to the consumer's root `.gitignore`.
- **`/implement` Step 4 phase commits carry plan + source together.** With the plan tracked on the
  task branch, "commit the plan changes alongside the phase's source-code changes in a single commit"
  is now literal git behavior — one commit, one story; memory-tier files never enter the commit.
- **`/verify-changes` evidence directory renamed `verify/` → `verification/`.** The distilled,
  `verified_at_sha`-keyed manifest is contract-tier at `docs/topics/<slug>/verification/` and meets
  the contract's redaction bar (no raw captures, machine-local paths, usernames, or credentials);
  raw captures stay in `.work/<slug>/scratch/`. The skill's evals assert the migrated locations.
- **`/verify-improvement` baselines are memory-tier** at `.work/<slug>/baselines/` — machine-bound
  measurements, never committed, no longer beside the plan artifact (contract-tier at
  `docs/topics/<slug>/PLAN.md`); the comparison summary surfaces in the plan and the PR body.

### Added

- **`reference/topic-docs.md`** — the plugin's **deltas-only** binding to the topic-docs contract:
  its per-artifact tier table and the `DEVIATIONS.md` pin and phase-commit rule — the contract owns
  the resolution order, slug spec, and runtime guards. All consuming skills reference this one
  document.
- **`/implementation:setup` offers the `.claude/topic-docs.yaml` concern file** — one question
  (`contract_tier: branch` recommended), offering and preserving every schema key (`contract_dir`,
  `memory_dir`, `contract_tier`, `vault_backend`), conflict-checked with `git check-ignore -v` on
  the chosen contract root before writing — only when the chosen tier is `branch` (local mode has
  no committed tier to guard); never edits the consumer's root `.gitignore`.

### Removed

- **`notes_dir` userConfig option and the `.claude/notes/<slug>/` layout.** Retired outright — no
  compatibility layer, no dual-read window, no migration tooling; move residual content manually.

## [0.3.0]

### Added

- **Rich-form evals for five skills.** `evals/evals.json` ships for `implement`, `implement-dispatch`,
  `build`, `lint`, and `setup` — the skills' judgment-bearing contracts (mode/orchestration routing,
  divergence and scope-fence guardrails, skip-not-FAIL and consumer-config-precedence behavior, and the
  config-writer's interview/write-scope discipline) are now covered by objectively-verifiable cases,
  modeled on the `bug-report` rich-form exemplar and validated against
  `plugins/skill-quality/reference/evals.schema.json`. Evals are a shipped component, so this minor bump
  is their delivery vehicle; no behavioral change to the skills themselves.

## [0.2.0]

### Changed

- **Consume the ecosystem-commands contract.** The two divergent per-ecosystem reference tables
  (`skills/build/reference/ecosystem-config.md` and `skills/lint/reference/ecosystem-config.md`) are
  replaced by ONE bundled, schema-conformant set of portable-default files at
  `reference/ecosystems/<ecosystem>.yaml`, validated against the contract's `ecosystem.schema.json`
  (`docs/conventions/ecosystem-commands/README.md`). Both `/build` and `/lint` now read the one
  location.
- **Ladder resolution in `/build` and `/lint`.** Each ecosystem's command surface resolves through the
  contract's four-rung ladder (shared doc: `reference/resolution-ladder.md`): consumer
  `.claude/ecosystems/<ecosystem>.yaml` (additive over a `~/.claude/ecosystems/` user-global base and a
  `.local.yaml` overlay) → inference → ask → bundled portable defaults. A malformed consumer file warns
  and degrades to inference, never a hard stop. Bundled defaults are the rung-4 fallback only, never
  written into a consumer repo outside setup or a persisted inference.
- **Unified command keys.** The old build-table `lint-cmd` and lint-table `check-cmd` were the same
  verb; they collapse to the contract's `check-cmd`. Command keys are now `build-cmd`, `test-cmd`,
  `check-cmd`, `fix-cmd`.

### Added

- **`/implementation:setup`** — re-runnable skill that interviews, infers, and writes the consuming
  repo's tracked `.claude/ecosystems/*.yaml`, the ladder's writer for the infer/ask rungs.

### Design decisions (from the wave-2 design gate; recorded, not reopened)

- **Data unified, scope preserved.** Unifying the tables into one 8-ecosystem set would have pulled the
  lint-only `yaml` and `cross-cutting` surfaces into `/build` — and `cross-cutting`'s `**` glob matches
  every change. Per the contract's canonical-verb-vs-context-binding split, the *data* is unified while
  each skill keeps its *scope* (binding is per-surface): `/build` covers
  dotnet/python/typescript/bash/powershell/markdown; `yaml` and `cross-cutting` remain `/lint`-only.
- **Reconciled divergences.** Where the two old tables disagreed, the contract's worked examples are the
  authority: dropped the lint-table's `$REPO_ROOT/`-prefixed dotnet command in favor of the contract's
  `<solution-or-project-file>` form (the running skill resolves absolute paths).
- **Config home is concern-named** `.claude/ecosystems/` (a recorded precedent-extension of the
  extensibility-contract seam, since more than one plugin consumes it). No new `userConfig` knob — the
  path is conventional, not declared. Task-runner deferred — command values stay opaque strings.

## [0.1.0]

- Initial release: ten skills — `implement`, `implement-dispatch`, `build`, `lint`, `test-write`,
  `test-plan`, `test-diagnose`, `test-e2e`, `verify-changes`, `verify-improvement`.
