# Changelog

All notable changes to the `claude-config` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.30.0]

Two graded outputs move, which is why this is a minor rather than a patch: a baseline deny finding can
now come back `info` where it previously came back `error`, and adding a baseline deny rule is no longer
offered as a mechanical `--fix`.

### Changed

- **`audit`: Category B stopped manufacturing an `error` on every repo whose destructive-git
  enforcement is a hook rather than a deny rule.** The category iterates the baseline patterns and
  states flatly that each "must appear" in `permissions.deny`; the only two ways out were prose the
  *consuming repo* writes — a documented exemption in its own rules files, or its own documented hook
  conventions. Neither is keyed on a hook that is actually installed and enabled, and `grep -rn "hook"`
  across the whole skill returns no `hooks.json` read, no plugin-hook enumeration, and no coverage
  concept at all. So a repo that blocks `git push --force` with a `PreToolUse` hook exiting 2 — which
  the permissions reference says stops the call *before* permission rules are evaluated, ahead even of
  an allow rule — was told its security floor was missing. "Narrowing the baseline" now carries a third
  narrowing: a family already blocked by a **live** `PreToolUse` hook is `info`, not `error`, whether
  the hook came from the repo or from a plugin.
- **The narrowing is fenced by three preconditions, because a careless downgrade is worse than the
  false positive it replaces.** The hook must be *live* — `disableAllHooks`, `allowManagedHooksOnly`,
  or `strictPluginOnlyCustomization` can have switched it off already, and a hook a setting has
  disabled blocks nothing, so under any of those the finding stands unnarrowed. The hook must be on the
  tool surface the pattern defends — `sensitive-file-deny` is a `Read`-pattern family, so a hook
  matching only `Bash` leaves the `Read`/`Grep`/`Glob` path open and retires nothing. And it must block
  *that* family: coverage of `git push --force` says nothing about `git clean -fd`, nor a long flag
  about its short spelling. Narrow per family, pattern by pattern.
- **Every downgrade names its own residual.** Hook coverage is contingent in ways a deny rule is not,
  and an `info` that hides that is worse than the `error` it replaced, so the off-ramp obliges the
  report to say what ends the coverage: disabling or uninstalling the providing plugin, any per-guard
  opt-out the hook exposes, and later suppression by `disableAllHooks` / `allowManagedHooksOnly` /
  `strictPluginOnlyCustomization` even where none is set today.
- **`audit`: adding a baseline deny rule is judgment-required, not an auto-fix.** The Phase 5 matrix
  graded it `Auto-fixable: Yes (from checklist)` / `Requires judgment: No` — the column that tells a
  user not to think about it, next to a prompt whose offered reply `'all'` applies the lot in one
  keystroke. It also contradicted this skill's own baseline reference, which says adding a deny for a
  family a project hook escalates to an *ask* suppresses that prompt and must be audited against the
  project's hook conventions. The judgment is now written out: is the family already covered, and would
  the addition suppress a gate the project built deliberately. *Moving* a deny rule from local to
  project stays mechanical — that is bug #8961 placement, not a policy change — and `SKILL.md`'s prose
  restatement of the matrix splits the two the same way instead of asserting the opposite.
- Scope stated honestly: the applied change was *more* deny rules, which is fail-closed, and a
  confirmation gate already existed and was already pinned by eval #2 — so this was never "unattended
  auto-apply". The graded harm is unwanted config growth against a stated simplification goal, plus the
  loss of a human approve/reject decision where a hook returned `ask`. A hook that blocks by `exit 2`
  short-circuits before permission rules and suppresses nothing.

### Fixed

- **The narrowings were unreachable from where the check runs.** Category B's directive delegates by
  *pattern* — "iterate the patterns in required-permissions.md" — and the checklist likewise says
  "assert presence per sub-category". Neither named the off-ramp sections, so they were prose elsewhere
  in a file the category cites only for its tables, and a new off-ramp added there alone would have
  inherited the same weak wiring. Category B and the checklist's B.1–B.3 severity table now both point
  at "Narrowing the baseline" and say the tabled severities are the *unnarrowed* rating.
- **The skill assumed absence where it simply could not see.** It has no enumeration path over a
  plugin's `hooks/hooks.json` — it reads the settings-declared layer only — so on most runs it does not
  know what is installed. A missing baseline pattern with no hook inventory behind it is now stated
  conditionally ("if a `PreToolUse` hook on `Bash` already blocks this family, this finding is void")
  and says which inventory would settle it, rather than asserting the gap. Fail open, not fail silent.

### Added

- **Category D now reads the hook-suppression levers**, because the new narrowing depends on a reading
  nothing was taking. `disableAllHooks` in the settings-declared layer and `allowManagedHooksOnly` /
  `strictPluginOnlyCustomization` in the managed layer each switch hooks off, and Category D checked
  script paths, readability, timeouts, matchers, and events without ever asking whether the hooks it
  inventoried could run at all. It reports each lever as set or unset with the hooks it disables —
  `info`, because a repo may set any of them deliberately and the reading is state rather than a
  defect. Category B may not take its third narrowing on a reading that was never made: an unread lever
  leaves the narrowing **unavailable**, not assumed clear.
- **And the dependency is sequenced, since Category B runs before Category D.** A–I is presentation
  order, not a dependency ban: Category B pulls the lever reading forward before taking the narrowing,
  or defers the downgrade and revises the severity once Category D has run. On a scope-filtered run that
  never reaches Category D — `/audit permissions` is exactly this — the narrowing is unavailable unless
  the operator supplies the state. Stated in both Category B and "Narrowing the baseline", so a reader
  arriving at either one gets it.
- Eval #8 `baseline-deny-narrowed-by-installed-hook` grades the narrowing *per family*: force-push and
  hard-reset patterns drop to `info` under a live Bash hook, while `git clean` patterns the hook does
  not match and `sensitive-file-deny` Read patterns it cannot reach stay at their unnarrowed severity.
  Eval #9 `no-hook-inventory-states-the-finding-conditionally` grades the fail-open half, and eval #10
  `suppressed-hook-does-not-narrow-the-baseline` grades the negative case the liveness precondition
  exists for: a declared hook under `disableAllHooks: true` narrows nothing, and the finding holds at
  `error`.

## [0.29.2]

### Changed

- **Upstream doc stamps re-verified against the live pages (2026-08-10).** Each dated claim below was re-checked against the complete raw markdown source of the page it cites (`https://code.claude.com/docs/en/<page>.md`), not a summarized fetch, and each was confirmed by a verbatim quote before its stamp was refreshed. No claim changed; only the verification dates moved.

  - `skills/audit/scripts/check-structure.sh` — managed-settings paths, and the legacy
    `C:\ProgramData\ClaudeCode\managed-settings.json` location being unsupported since v2.1.75
    (settings reference).
  - `skills/audit-pass/reference/doctor-handoff.md` — `/doctor` proposing fixes it applies only
    after confirmation (debug-your-config reference).
  - `skills/audit-pass/SKILL.md` — `@path` imports not reducing context because imported files
    load at launch (memory reference).

## [0.29.1]

### Fixed

- **`audit`: the MANDATORY env-var check told auditors to do the exact thing that fabricates
  findings.** Category F required fetching `code.claude.com/docs/en/env-vars` and searching it for
  each name, calling that page "the authoritative source" — with no word about how to read it. The
  page carries 315 variable rows and truncates through a summarizing fetch, which then reports the
  rows past the cutoff as absent; `env-vars` produced that false negative on three independent
  fetches (#2182). An auditor following this row as written could flag a perfectly valid variable as
  unrecognized and never know. The row now routes through the
  [`.md` fetch route](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/upstream-drift/README.md#reading-the-basis--the-fetch-route)
  — `curl` to a file, grep the file — and states that a truncated read supports no finding at all.
- **`audit`: and the inverse error the same row invited.** "Authoritative source" plus "do not flag
  as unrecognized without checking this page" reads as *absent here means not a real variable*.
  It does not: `CLAUDE_CODE_ENTRYPOINT`, `CLAUDE_CODE_ENHANCED_TELEMETRY_BETA`, and
  `CLAUDE_CODE_EXPERIMENTAL_OBSERVER_AGENTS` are each cited as real in this repo and each absent
  from a full verbatim read of the page on 2026-08-10. The row now caps the strongest available
  verdict at "not documented on `env-vars`" and names the sibling pages to check first.
- **`audit-instructions`: the effort-audit reading list promised a release the page does not state.**
  It sent auditors to `env-vars` for `CLAUDE_CODE_DISABLE_ADAPTIVE_THINKING` "with the models **and
  release** it reaches"; the row states the models — "Has no effect on Fable 5, Sonnet 5, or Opus
  4.7 and later" — and no release at all (verbatim read, 2026-08-10). Sending a reader to look for
  something that is not there invites them to invent it. The clause is corrected, and the entry
  routes through the fetch route for the same truncation reason as Category F above.
- **`audit-pass`: `DISABLE_DOCTOR_COMMAND` is documented, and the handoff said it was not.**
  `reference/doctor-handoff.md` carried it as a design-phase channel "not documented on the current
  official pages … does not appear in the environment variables list (checked 2026-07-24)". A live
  verbatim read on 2026-08-10 found it, and found it describing this skill precisely: "Set to `1` to
  hide the `/doctor` setup checkup skill and its `/checkup` alias … Doesn't affect the `claude
  doctor` terminal command. Before v2.1.205, this variable hid the `/doctor` diagnostics screen
  command" — which independently corroborates the v2.1.205 cutover the same section already states.
  It moves up into the verified list with the scope the row actually draws (session skill, not the
  terminal command). The pass still **detects** rather than predicts: a documented suppression lever
  says an operator could have set it, never that they did. The `skillOverrides` half is untouched and
  still says so — this run re-derived the `env-vars` basis only, and the recheck trigger now names
  the settings fetch that would retire the stale half.

## [0.29.0]

### Removed

- **The bare `/<skill>` alias for this plugin's skills.** Their `SKILL.md` files no longer
  declare a frontmatter `name`. The field is optional and defaults to the directory name, so
  declaring it only restated the path while registering a second, unnamespaced command — which
  the slash-command picker then echoed back as `/plugin:skill (skill)`. Invoke a skill by its
  namespaced command; the command itself is unchanged.

## [0.28.1]

### Fixed

- **`unhobble`: the classification contract can now represent a hybrid hook entry.** The phase-1
  contract allowed only `policy` | `behavioral` | `convention` per hook entry and reserved
  splitting for instruction files, while phase 2 removed a behavioral entry's wiring whole — so a
  hook carrying both a policy gate and behavioral prose could only be over-stripped or
  over-kept, contradicting the marketplace rubric's trim-not-delete rule for hybrids
  (PLUGIN-PHILOSOPHY "Classifying a hook"; flagged by review on the rubric PR #2033). Phase 1 adds
  the `hybrid` class (delegating the rubric itself to the philosophy doc), phase 2 strips a
  hybrid's behavioral surface via the hook's own kill switch or config where one exists and
  otherwise records `unstripped-hybrid-hook` with the observe-phase confound noted, and the
  manifest enum carries the new class.

## [0.28.0]

### Added

- **`audit`: Category I — deep-link registration** (issue #2072). `disableDeepLinkRegistration` had
  no coverage, leaving two findings undetectable. The settings page documents exactly one value that
  produces the effect — the string `"disable"` — so a key that is **present** and set to something
  the author meant as a flag (boolean `true`) leaves the documented prevention simply never invoked,
  and nothing exempts the machine from the default first-prompt handler registration (warning; an
  absent key is a consumer accepting the default on purpose and never fires). Separately, the
  deep-links page states that enforcing this "across an organization so users cannot re-enable it"
  requires managed settings, so no scope this skill reads by value can satisfy such a requirement —
  and where one is declared and the key nonetheless sits with `"disable"` in a readable scope, that
  visible attempt is reported as a placement that cannot enforce it (warning). The claim stops at
  the placement: server-managed delivery, MDM plist, and registry policy are managed sources with no
  file on the path this skill resolves, so nothing about the managed layer is decidable here and a
  bypass is exactly what cannot be proven — which is why this row sits a tier below its
  `enforceAvailableModels` sibling rather than mirroring its `error`. The row routes the
  administrator to `/status`, which names the active managed source. Like two of
  Category H's rows, the value check also has an authoring-time path — the declared settings schema
  types the key `"type": "string", "enum": ["disable"]`, so a schema-aware editor flags a boolean
  before the file is ever loaded — and the row says why it stays anyway. The section states its own
  reach: `check-structure.sh` does not report this key, so a `settings.local.json` or
  managed-settings occurrence is recorded as not inspectable rather than absent, and handler
  presence on the machine is workstation state the section explicitly does not audit.

  The section takes the letter **I**, not the G the issue named: G is live as the table-less
  procedural "skill-listing budget" category.

### Fixed

- **Four category enumerations had fallen behind the checklist.** `README.md` advertised "seven
  categories" and `evals/evals.json` eval 5 "a full seven-category audit", while
  `validation-categories.md`'s own header and eval 1's expectations both stopped at G — every one
  already stale when Category H landed, and two behind after this one.

## [0.27.5]

### Fixed

- **`audit`: Category E's incompatible-marketplace check rested on a false premise** (issue #1989
  row 253). The checklist flagged "plugins from incompatible marketplaces (Agent Skills format)"
  by the rule "Repos with only root `marketplace.json` but no per-plugin `plugin.json` are
  incompatible" — a shape the [Strict mode
  section](https://code.claude.com/docs/en/plugin-marketplaces#strict-mode) documents as SUPPORTED:
  under `strict: false` "the marketplace entry is the entire definition", the plugin repo provides
  raw files, and the entry's `skills`/`agents`/`hooks` fields expose them. Anthropic's own
  `anthropic-agent-skills` marketplace ships three such plugins with zero `plugin.json` files
  repo-wide, so the old rule fired an `error` on a conforming marketplace. The row now tests
  `strict` rather than `plugin.json` presence: it flags only a plugin with NEITHER a per-plugin
  `plugin.json` NOR a `strict: false` entry declaring its components — the residual case where
  nothing defines what loads — and records the same page's inverse failure, a `strict: false`
  entry paired with a component-declaring `plugin.json`. Severity stays `error`; both the check
  label and its verify cell were rewritten, since the label carried the false premise too.

## [0.27.4]

### Fixed

- **`audit-instructions`: two internally-inconsistent claims in the criteria preamble** (criteria
  1.21.0 → 1.21.1; issue #1989 row 248). The per-row-trigger rationale justified stamps as naming
  "only the events the Sources set would *miss*" — but a value change on a Sources page IS a change
  to that page, so the catalog trigger already fires and nothing is missed. The paragraph now states
  what a per-row trigger actually buys: **specificity about what to re-read** — the literal the row
  restates and the event that would move it — so a re-verification pass goes straight to that value
  instead of re-reading the page to find what mattered. The recheck-trigger paragraph's "Every check
  cites one of those pages" was falsified by the three checks whose Source line reads `none` — I16,
  I19, I22 (the Stopping condition rule is sourceless too, but is not a check) — and is now scoped
  to checks that cite a source, with the exception stated on the two-way split the file now
  makes: a sourceless row grounded in a categorical absence has nothing of its own to go stale,
  while one that calibrates against page content (the Stopping condition) is staled by the pages it
  calibrates against, which the catalog-wide trigger already covers. No source was invented
  for any sourceless row, and the catalog-trigger-wins precedence and whole-catalog firing rule are
  unchanged.

## [0.27.3]

### Fixed

- **`audit-instructions`: the hook-event blockability partition in `conflict-criteria.md` was
  closed** (conflict-criteria 1.3.0 → 1.4.0; issue #1989 row 244). The exit-2 bullet enumerated six
  "blockable" and five "non-blockable" events as an exhaustive split, while the hooks page's
  "Exit code 2 behavior per event" table documents far more — including five events this repository's
  own hooks already register (`ConfigChange` and `PostToolBatch` block; `StopFailure`,
  `PermissionDenied`, and `InstructionsLoaded` have their exit code ignored), every one of them
  ungradeable under the old text. The bullet now defers to that table as the sole authority and
  restates none of its rows: resolve the handler's event, read its row, and pair on the row's own
  `Can block?` cell — taking the paired content from what the row states is prevented rather than
  assuming a tool call or a prompt, and recording an event with no row (or an unreachable table) as
  `blockability-unresolved` instead of inferring it. The `SubagentStop` subagent-scoping rule and
  the `PostToolUse`/`PreToolUse` worked pair are kept as examples. The file's recheck trigger no
  longer fires on a row added to the upstream table, and `evals/evals.json` eval 16 now tests the
  lookup procedure rather than the memorized split.

## [0.27.2]

### Fixed

- **`conflict-scan.sh`: the coordinated-directive boundary honored only a subset of the mandate
  tokens, so the most common phrasing silently dropped real conflicts.** `COORD_ERE` carried a
  hand-copied token list that had fallen behind `MANDATE_ERE`: `use`, `present`, and `ask` were in
  the classifier and absent from the coordinator. ``Never use `Bash` and use `Read` `` therefore
  found no boundary, `Read` inherited the leading `never`, and its pair with ``Never use `Read` ``
  went unreported — while ``Always use `Read` `` produced a false conflict from the same misreading.
  `always` masked the gap throughout, being present in both lists. The coordinator is now COMPOSED
  from the two classifier alternations rather than restated, so the divergence that caused this is
  unrepresentable; two regression cases cover the bare-`use` and `present` forms.

- **`audit-instructions`: the skill hardcoded `~/.claude` in the very paths its own rule forbids
  hardcoding.** Phase A resolves the user root as `${CLAUDE_CONFIG_DIR:-~/.claude}` and says never to
  hardcode it, yet the auto-memory entrypoint, the scope-filter list, and the memory-layer surface
  list all named `~/.claude` literally. `CLAUDE_CONFIG_DIR` relocates the whole tree including
  `projects/`, so a hardcoded default read a store the session no longer writes. Every operative path
  now resolves against that root; quoted upstream text and the `${CLAUDE_CONFIG_DIR:-~/.claude}` form
  itself are unchanged.

- **`audit-instructions`: I3 named a `skills:` preload as a valid deferral destination, which defers
  nothing.** The check rejects `@path` imports because they load unconditionally, then offered a
  preload — but the full content of each skill named in an agent's `skills:` field is injected into
  every dispatch, exactly the load profile the check exists to avoid, as the skill's own co-residency
  table states. I3 now permits only conditional runtime invocation, and says to report that no safe
  deferral is available rather than proposing a preload.

- **`audit-instructions`: Phase A never inventoried a subagent's own memory, so a criterion it
  declares in scope could not fire.** The co-residency table graded an agent-definition-versus-its-own
  `memory` contradiction as real, but no inventory step reached that `MEMORY.md`. Phase A now
  enumerates it per scope (`user` under the resolved user root, `project`, `local`), and the
  co-residency table carries its own row.

- **`audit-instructions`: the liveness gate resolved a closed five-input list that omitted hook
  enablement.** A hook that cannot fire carries no live instruction text, so a pass comparing against
  it grades a dead surface. The gate now resolves `disableAllHooks` **per settings scope** — a user,
  project, or local disable cannot reach managed hooks, so managed hook text stays live and must not
  be dropped with the rest — together with `allowManagedHooksOnly` and its force-enabled-plugin
  exemption.

- **`audit-instructions`: a nested project memory pair was routed to a check that never discovers the
  file.** The skill routed any project-scope pair to `claude-memory`'s C6, which discovers with
  `find . -maxdepth 1`, so a `src/api/CLAUDE.md` pair was graded by neither pass. The boundary is now
  **root-level** project, matching the routing table the criteria reference already owned. Scoped
  narrowly: `.claude/rules/**` still routes to C6, whose rules discovery is recursive.

- **`conflict-scan.sh`: `and` coordinating an opposite directive was not a window boundary.** "Always
  use `Read` and never use `Bash`" against "Never use `Read`" yielded zero candidates, because the
  first entity's window swallowed the second directive's `never` and took its polarity; the same line
  with `but never` yielded one. A **bare** `and` cannot be the boundary — "never use `Bash` and
  `Grep`" is one directive over two objects, and cutting there strips the token governing the second.
  The boundary therefore requires a polarity token after the coordinator, and is consumed
  asymmetrically: a leading window resumes after the coordinator alone so that token still classifies
  its entity. Three cases cover the fix and the false negative it must not introduce.

- **`audit-instructions`: I14's startup set omitted `./.claude/CLAUDE.md`.** A project keeping its
  memory there loads it at launch exactly as `./CLAUDE.md` would, so naming only the bare path let the
  redundant read of the active file escape the check. Both supported root locations are now in the
  set, matching what Phase A already inventories.

- **`audit-instructions`: I14 exempted supporting documents unconditionally, ignoring startup
  imports.** `@path` imports are expanded into context at launch, recursively, so a startup file
  carrying `@AGENTS.md` or `@docs/CONTRIBUTING.md` makes that document resident and an instruction to
  go read it is the redundant retrieval the check exists to find. The exemption now applies only to
  what no active startup import reaches, resolved the way I15 already resolves imports.

- **`setup` and the README: `awk` and `sort` were scoped to one skill and are used by three.**
  `check-plugin-drift.sh` (both), `permission-rule-check.sh` (both), and `fix-plugin-drift.sh`
  (`sort`) call them with no prerequisite check, so `audit` and `audit-permission-grants` fail
  mid-run on a bare `command not found` rather than on a named prerequisite. Only
  `conflict-scan.sh` probes and `exit 2`s. Both surfaces now name all three skills, and the README's
  requirements section names `awk` and `sort` alongside `jq` and `curl`.

## [0.27.1]

### Changed

- **`audit-instructions`: listing description tightened (1,197 → 948 chars)** — trimmed the
  explanatory prose from the frontmatter `description` toward the shared skill-listing budget
  (claude-code-plugins#2022, option 2). Every single-quoted trigger phrase is preserved verbatim
  (skill-quality check 3); the audit's scope and report-only contract are unchanged in the body.

## [0.27.0]

### Added

- **New skill `audit-prompting-postures` — the additive lane of prompting-guide alignment.** The
  existing `audit-instructions` catalog detects instruction text that is present and wrong; nothing
  detected posture guidance that is absent and needed. The new skill classifies each locally-owned
  component by purpose (orchestrating, code-changing, long-running, destructive-capable, …) and
  judges ten guide-prescribed postures (`reference/postures.md`: delegation criteria/caps,
  minimal-scope, anti-test-gaming, investigate-before-answering, progress-claim grounding,
  autonomy/checkpoint, destructive-action confirmation, context-budget reassurance, multi-window
  state, parallel-call steering) against applicability predicates, defaulting to NOT-APPLICABLE.
  Report-only; proposal wording comes from a live fetch of the guide, never from the catalog
  (pointer-not-copy).
- **`audit-instructions`: catalog row I28 — over-aggressive trigger emphasis and blanket tool
  defaults** (criteria 1.20.0 → 1.21.0). Detects forced-compliance emphasis ("CRITICAL: You MUST
  use…") and blanket tool defaults ("If in doubt, use [tool]") — unscoped, sourced to the
  best-practices page's Tool-usage, Overthinking, and Migration sections, fenced for
  destructive-gate emphasis and stated hard preconditions. `instruction-scan.sh` now seeds it
  (`I28-a` case-sensitive emphasis, `I28-b` blanket defaults) and also seeds the existing I25
  sampling-parameter row (`temperature`/`top_p`/`top_k` prescriptions).

### Changed

- **`audit-instructions`: I8 base (over-prescriptive scaffolding) is now unscoped** (criteria
  1.20.0 → 1.21.0) via the model-agnostic best-practices statement ("Prefer general instructions
  over prescriptive steps…"); the delegation-throttle worked instance keeps its own `fable-5`
  scope because the Opus 5 and Opus 4.8 guides recommend the opposite shape (caps) on their
  targets. **I21** gains a sentence separating calibration staleness (its subject) from level
  adequacy (the Opus 4.8 guide's `xhigh` recommendation for coding and agentic lanes, which is
  the surface's sizing decision).
- **`setup` and `audit-pass` prose carry their reasoning.** `setup`'s read-only instruction is
  stated as what the check does rather than as a bare prohibition, and its repo-root anchoring rule
  now says why a CWD-relative read is wrong (it resolves a different — or missing — file depending
  on the invoking subdirectory or worktree). Five passages in `audit-pass`'s run contract that
  narrated the authoring session's own history are restated as present-tense rejected-alternative
  rationale, keeping the anti-relitigation content.
- **`audit`'s Phase 4 report table carries a worked example row**, so a model generating the report
  has a concrete shape to match rather than a bare header.
- **`audit-pass`: the 892-line run contract is split per topic.** `reference/run-contract.md` is
  now a routing index over five topic files that follow the contract's own section structure —
  `terms.md`, `finding-identity.md` (§1), `report-location-and-schema.md` (§2, §7),
  `run-state-and-resumability.md` (§3, §5), `suppression.md` (§4), `determinism-tiers.md` (§6) —
  so a lane needing one mechanic loads that file, not the whole contract. Content moved verbatim,
  the §-numbering travels with it, inbound links repointed to the owning files, and the one
  remaining authoring-history clause is restated in present tense.

### Fixed

- **`audit` now actually covers machine-scope managed settings, closing the false coverage claim
  its checklist made.** Phase 1's `check-structure.sh` resolves the OS-specific managed-settings
  path (macOS `/Library/Application Support/ClaudeCode/`, Linux/WSL `/etc/claude-code/`, Windows
  `%ProgramFiles%\ClaudeCode\`; the pre-v2.1.75 ProgramData location deliberately unprobed) and
  reports the file and its `managed-settings.d/` drop-in directory structure-only — same
  no-secrets posture as `settings.local.json` — with the Config Files table naming the layer as
  report-only routing that `--fix` never edits. The checklist's "+ managed settings" tick is
  restored, now truthful. Paths verified against the live settings doc 2026-08-08.
- **`audit-automation-gaps`' checklist replaced two unmeasurable thresholds with the real gate.**
  "cost > 2× expected benefit" and "false-positive risk > 30% on representative sample" appeared
  only in the template; neither cost, benefit, nor a representative sample is defined or measured
  anywhere in the skill. The three anti-noise ticks fold into one that points at SKILL.md §2.3's
  eight named gates, each of which states the evidence it requires.

## [0.26.0]

### Added

- **`audit-instructions`: I23 gains a pre-scan pattern, and the calibration it was waiting on is
  now recorded** (catalog 1.20.0). The row shipped unseeded because the threshold and
  window-position phrasings vary far more than the fixed shapes I8-b matches, and because a
  continuation skill can barely be model-invocable without naming a context trigger somewhere — so
  a loose pattern would have fired on every consumer's handoff skill. **What the seeding actually
  waited on was a policy, not a regex.** It is now stated: three signals license a surface to route
  into a handoff, a fork, or a new session — the user's own report, an instrument that measures the
  window, and visible decay in the model's own output — and a self-estimated budget is none of the
  three. Under that rule the population the blast-radius argument feared resolves into true
  positives rather than noise.

  Two supporting clauses ship with it. **Residency is a severity input, not an admission test:** a
  trigger in a `description` is resident whenever the skill listing admits it, which is the default
  since `disable-model-invocation: true` also suppresses the description from context
  (<https://code.claude.com/docs/en/skills>, verified 2026-08-08), while a body-borne trigger costs
  context only on load or at subagent startup under preloading — both are findings, the resident one
  merely costlier to leave. And **remediation moves the trigger rather than withdrawing the skill:**
  flipping continuation skills to `disable-model-invocation: true` was considered and refused, since
  it forfeits every model-side invocation the skill has to remove one clause.

- **`instruction-scan.sh` emits `I23` candidate rows.** The pattern marks budget phrasing alone and
  never the stop/summarize/hand-off verb it licenses, because the trigger and the action routinely
  sit in different sentences; counter-steer text, documents about the pattern, and operator-facing
  budgets therefore match too, on the same advisory over-production contract the I8 families carry.
  It is deliberately not anchored to the bare term "context window" — ordinary vocabulary in any
  surface discussing sessions, and matching it would return the corpus instead of a candidate set.
  Measured over the marketplace's 193 skills the pattern yields 20 rows in 10 files.

## [0.25.0]

### Added

- **`audit-instructions`: new catalog row I27 — effort lowered to shorten the response** (criteria
  1.18.0 → 1.19.0; issue #1996 decision b). Detects instruction text premising response brevity on
  a lower effort level — a misconception both the Opus 5 prompting guide and the effort page's
  Opus 5 section refute ("lowering effort can reduce thinking volume without reliably shortening
  the visible response"). `Model scope: opus-5` (both statements are model-qualified; promotion
  gate unmet, with the unscope trigger recorded on the row). Seeded by a new `instruction-scan.sh`
  I27 family (an effort-lowering directive and a brevity token required on one line; regression cases
  added) with cost/latency-ground, length-instruction-only, audience-test, and config-value
  fences; both statements verified against the live pages 2026-08-08 (guide raw-`.md`
  byte-identical to the 2026-07-25 corpus capture).

### Changed

- **`audit-instructions`: family-alias abort now suggests the normalized token** (issue #1996
  decision e). The fail-loud abort on a version-ambiguous `--target-model`/settings value (e.g. a
  bare `opus` pin) still refuses to guess, and now ALSO names the normalized version token the
  alias currently resolves to per the live model-config docs as a suggested `--target-model`
  value the user confirms — turning the dead-end abort into a one-confirmation retry without
  weakening the never-guess contract.

### Fixed

- **`audit-instructions`: stale check-range in `evals/evals.json`** — the memory-layer eval still
  said "I6-I16" (predating I17–I22) and credited `--opinion` gating to I16 alone; now "I6-I27"
  with the current `OPINION`-gated set (I16, I19, I22).

## [0.24.0]

### Added

- **`audit-instructions`: four checks from the Sonnet 5 and Opus 4.8 prompting guides**
  (catalog 1.18.0). Every behavioral claim was verified 2026-08-08 against the raw-`.md` channel of
  its source page, with byte sizes and MD5 stamps recorded per row:
  - **I24 — instruction relying on silent generalization** (unscoped; gate met by the two guides'
    "More literal instruction following" sections, whose Detect sentences are stated
    verbatim-identically). Flags text demonstrating one instance where a whole class is meant — a
    worked example standing in for a rule, an undecidable "etc." tail, a single item named inside
    an iterating procedure, an unstated per-item iteration — and proposes explicit scope
    statements. Additive, so the stopping condition does not bind it.
  - **I25 — sampling parameter prescribed where the model rejects it** (unscoped; range as Detect
    condition: Opus 4.7 or later, Sonnet 5, Fable 5, and Mythos 5 — the Fable/Mythos arm carries
    over from Opus 5 per the migration guide). Prescribing non-default
    `temperature`/`top_p`/`top_k` — variety steering, `temperature = 0` determinism — publishes a
    400. Fences: model-gated claims, SDK/config expressions (config-mechanics discriminator),
    non-sampling senses of "temperature", meta discussion.
  - **I26 — generic negative steering on open-ended design briefs** (unscoped; both guides'
    "Design and frontend defaults" sections converge). Generic negatives shift the model to a
    different fixed palette; remediation is a concrete spec or the propose-N-directions step — on
    Sonnet 5 the documented variety mechanism now that `temperature` is not accepted. Concrete
    enumerable negatives (the guides' own anti-slop snippet shape) stay sanctioned.
  - **I17-d — tool reliance with thinking disabled and no explicit tool nudge** (Model scope:
    `sonnet-5`; the coupling — "With thinking disabled, the model is less likely to reach for tools
    or consider searching" — is stated only there; the Opus 4.8 guide states an uncoupled,
    different default, recorded as the scope negative).

### Changed

- **`audit-instructions`: I8-e (forced interim-status cadence) unscoped — its own recheck trigger
  fired.** The row shipped `sonnet-5`-scoped with the trigger "any second model guide stating the
  claim"; the Opus 4.8 guide's "User-facing progress updates" section now states the claim
  near-verbatim, so the promotion gate is met and the row fires for every target model. I8-d cedes
  the cadence shape to I8-e fleet-wide (one finding per line) and keeps the remaining short-turn
  shapes; the Fable 5 verified negative was re-verified 2026-08-08 and is retained as a reading,
  no longer load-bearing for scope.
- **`audit-instructions`: I8-b corroboration extended.** The Opus 4.8 guide states the same three
  trigger phrases, coverage prompt, and concrete-bar remediation; recorded alongside the existing
  Opus 5 + Sonnet 5 citations (gate was already met). "don't nitpick" appears nowhere in the
  Opus 5 guide — re-verified 2026-08-08 against that guide's raw `.md`.
- **`audit-instructions`: Sources list** gains the Opus 4.8 prompting guide and What's new in
  Claude Sonnet 5; the migration-guide entry now also names the sampling-parameter ranges it
  carries. Both SKILL.md catalog ranges updated to I26.

## [0.23.0]

### Added

- **I23 — context-budget directive to stop, summarize, or hand off** (criteria 1.16.0 → 1.17.0).
  Tier `behavioral`, `Model scope: fable-5` with the promotion gate unmet, carrying the four-part
  stamp plus a **verified negative**: both sibling guides were fetched as raw markdown and searched,
  and neither states the claim.
  - Detects instruction text telling the model to watch its own remaining context and stop,
    summarize, hand off, or trim its work on that basis, and injected hook output surfacing a
    remaining-context count where the surface could avoid it. The guide names the count as the usual
    trigger, so the disclosure and the directive are one subject; the row tracks the guide's "where
    possible" hedge rather than reading it as an absolute.
  - The discriminator is who decides, on what evidence: a directive tells the model to judge its own
    window, a mechanism resolves the window from an instrumented signal and acts itself. **A hook
    that injects an exit menu stays in scope** however well instrumented its trigger, because the
    measurement decides only when to ask and the model still decides whether to stop — the injection
    manufactures the initiative rather than replacing it. A `PreToolUse` deny is the contrast that
    fixes the line.
  - Fenced against a measured-signal mechanism, a user-invoked continuation skill (including a router
    falling back to its own judgement when no instrument is available), a routing condition that
    sizes an artifact rather than abandoning the work, a budget rendered to the operator, and a
    document about the pattern. A playbook stating the counter-steer is exempt on **polarity** rather
    than audience — it instructs the opposite of Detect, so it never satisfies Detect at all.
  - No pre-scan pattern is seeded, and the row says why in its own terms rather than borrowing
    I8-e's: an unfenced true positive is attested, so this row waits on calibration of the threshold
    and window-position phrasings, not on an instance. The blast radius is the reason that
    calibration is owed first — a continuation skill can barely be model-invocable without naming a
    context trigger somewhere, and one such trigger lives in a `description`, which is resident
    whenever the listing admits it.
- **A section covering `effort:` and `model:` frontmatter on skills and agents** in
  `skills/audit/reference/audit-checklist.md`, category H. This closes a seam between two skills
  this plugin ships: I21 in the instruction-audit catalog explicitly hands frontmatter pins to
  `claude-config:audit`, and that skill's category H read only `settings.json` keys — so a component
  pinning an effort level was reached by neither, each pointing at the other. The rows report a
  missing re-derivation rather than a preferred level, exempt a pin at the resolved model's own
  default, and carry a dated stamp for the claim that a definition's `effort` overrides the session
  level.

### Changed

- **The catalog states an admission rule.** A row's observable must be **anchored to** text that is
  present: a check detects a passage a surface contains — what it says, or an attribute it lacks
  while saying it — and an obligation anchored to no passage at all is refused on shape rather than
  weighed on its source. Integrating one model guide raised that question at four separate sections
  and answered it four times by hand; the rule now settles it once, and requires an audit declining a
  row on this ground to name where the guidance routed instead — doctrine or a mechanism — so "no
  row" never reads as "not covered".
  - **The line is the anchor, not the polarity of the sentence.** I6 (a prohibition carrying no
    rationale marker) and I7 (a request stating no motivation) are both worded as absences and both
    admissible, because each names a line a reader can point at. A rule tested on polarity would have
    refused two shipped rows, which is what an adversarial pass on this change caught before merge.
- **I8's base row now cites the general principle, not only the migration framing.** Both of its
  sources sat in sections about migrating older material, which pointed an auditor at what looks
  like leftover prior-model scaffolding and past freshly authored over-enumeration — the same defect
  with no legacy provenance to recognize it by. The row now also cites "Strong instruction
  following", where the principle is stated on its own, and says plainly that age is not an element
  of the check.
- **I8-a records the second-guide corroboration for its independence carve-out.** Read without it,
  the Opus 5 guide ("remove verification instructions") and the Fable 5 guide ("make
  self-verification explicit", "separate, fresh-context verifier subagents tend to outperform
  self-critique") look contradictory, and a reader had to resolve that alone. They are not: the
  anti-pattern is the instructed *self*-check, and the architected independent verifier is what the
  Fable 5 guide is asking for. The scope annotation does not move — the gate wants a second guide
  stating this row's *detection* claim, and the Fable 5 guide states no such thing.
- **New `unhobble` skill — the empirical bare-baseline experiment.** Reversibly strips a project's
  standing instruction surfaces (CLAUDE.md, rules, behavioral hooks, skills, enabled plugins) on a
  dedicated experiment branch, has the operator work normally against the bare model while logging
  observed stumbles to a ledger, then re-adds only instructions with repeated same-cause evidence —
  each restore citing its ledger rows. Policy-classified hooks and managed settings are never
  stripped; every mutation is human-gated; state persists under `${CLAUDE_PLUGIN_DATA}/unhobble/`
  for resume. The canonical trigger is a frontier model release. Operationalizes the
  delete-and-re-add doctrine from official best-practices ("Would removing this cause Claude to
  make mistakes? If not, cut it") and Anthropic's own 80% system-prompt reduction for the
  Opus 5 / Fable 5 generation; `audit-instructions` remains the static text-vs-doctrine
  counterpart and receives routed rewrite judgments. Tracked-file stripping is delete-with-net
  (`git rm` on the experiment branch) rather than in-place disable — a deliberate choice: git is
  the restore mechanism, and a renamed-but-present file could still be read.

## [0.22.1]

### Fixed

- **`audit-instructions`: three precision fixes from a conformance audit of the catalog against
  its own sources** (criteria 1.16.0 → 1.16.1). `instruction-scan.sh`'s header comments still
  described all three I8 pattern families as "Opus-5-scoped catalog rows" — stale since I8-b's
  promotion to unscoped; the comments now state the split (I8-a/I8-c scoped, I8-b unscoped).
  I8-a's Detect line truncated the guide's trigger phrase ("include a final verification step"
  → the guide's "include a final verification step for any non-trivial task"). I8-b's opening
  claimed the Sonnet 5 guide states the same claim "about the same three trigger phrases" while
  its own Source paragraph concedes "don't nitpick" appears nowhere in the Opus 5 guide; the
  annotation now matches its Source (two shared phrases, third's provenance in the Source line).
- **`audit-instructions`: the normalized version token's grammar is now stated.** SKILL.md's
  resolution ladder said to normalize alias → version "against the live model-config docs" but
  never defined the token shape those docs do not publish; the ladder now names the local
  grammar (lowercase family-hyphen-version, e.g. `opus-5`) so a consumer resolving a full model
  name or alias lands on the exact string the catalog's `Model scope` annotations match against.

## [0.22.0]

### Changed

- **`audit`: Category D no longer prescribes shell form with "no `args`" for hook commands.** The
  row rested on a rationale — that the `"command":"bash"` + `args` variant "backslash-mangles
  `${CLAUDE_PROJECT_DIR}` on native Windows" — that the [hooks
  reference](https://code.claude.com/docs/en/hooks) contradicts: in exec form "path placeholders
  like `${CLAUDE_PLUGIN_ROOT}` are substituted into `command` and into each `args` element as plain
  strings", and "No shell tokenization happens on any platform." Mangling requires a shell, and exec
  form has none. The real Windows defect behind the observation is narrower and is now its own row:
  exec form "requires `command` to resolve to a real executable such as a `.exe`", so `"command":
  "bash"` finds the WSL relay `System32\bash.exe` and the launch fails — the failure this repo hit
  in #1006, where a fail-open guard enforced nothing. That is a defect in naming `bash` as the
  executable, not in exec form, and the fix is a real binary plus the script path in `args`.

  Category D now follows the page's own guidance — "Prefer exec form for any hook that references a
  path placeholder. In shell form, wrap each placeholder in double quotes" — and flags only the
  unquoted placeholder, never shell form itself. Quoted shell form stays a correct spelling, which
  it must: the page endorses omitting `args` for pipes, `&&`, redirects, and `.cmd`/`.bat` shims,
  and this repository's own hooks use it. The replacement warns without swinging into the
  mirror-image false positive the old row produced. The executable-resolution row is scoped to
  Windows-targeting repos, since `bash` and `sh` are ordinary executables elsewhere, and it names
  `"shell": "bash"` alongside the `node`-plus-`args` pattern as a documented fix.

  **A PowerShell bare-`$CLAUDE_PROJECT_DIR` row was drafted and then dropped**, because it could not
  clear this repository's own fresh-docs bar. It carried a quote attributed to the hooks page that
  is not on that page — re-fetched 2026-08-08 and searched: the page's only placeholder-quoting
  guidance is the generic "In shell form, wrap each placeholder in double quotes", and it says
  nothing about PowerShell resolving an undefined variable. The underlying claim also depends on
  whether the harness substitutes the *bare* `$NAME` spelling before PowerShell ever parses it,
  which the page does not document either. An audit checklist that emits findings a consumer cannot
  trace to a documented rule is the exact defect 0.21.9 removed and this release corrects; a row
  resting on an unverifiable premise is worse than no row. The generic quoting row already covers
  the safe advice.

### Added

- **`audit`: a Category D row asserting hook `timeout` is expressed in SECONDS.** The hooks
  reference states: "Seconds before canceling. Defaults: 600 for `command`, `http`, and `mcp_tool`;
  30 for `prompt`; 60 for `agent`." A consumer run found three hooks configured in milliseconds.

  The row flags a **recognizably millisecond-scale** value — a round thousands multiple such as
  `30000` or `120000`, which read as seconds are 8 and 33 hours — and deliberately does NOT flag
  merely-large ones. The page documents defaults, not a maximum, so a long-running hook may
  legitimately exceed 600, and a rule keyed on `> 600` would manufacture findings against correct
  configuration. Where the value is large but not millisecond-shaped, the checklist asks for
  corroboration from the hook's expected runtime before anything is reported. The likely source of
  the confusion is the Bash/PowerShell tools' own `tool_input.timeout`, whose example value on this
  page is `120000`; the page does not state that field's unit in prose, so the checklist does not
  claim it does.

## [0.21.9]

### Removed

- **`audit`: the Category B `:*` check, which rested on a false premise and could never report
  clean.** [Configure permissions](https://code.claude.com/docs/en/permissions) states that "The
  `:*` suffix is an equivalent way to write a trailing wildcard, so `Bash(ls:*)` matches the same
  commands as `Bash(ls *)`" — it is not deprecated. Across the 127 pages listed in `llms.txt`, no
  line carries both the deprecation word-stem and `:*`, and the changelog maintains `:*` in its
  current voice,
  hardening `Bash(find:*)` and `Bash(rm:*)` and fixing `Bash(cmd:*)` and `Bash(git log:*)` matching.
  The label traces to issue
  [#23869](https://github.com/anthropics/claude-code/issues/23869), whose reporter used the word; it
  was closed as not planned.

  The check was also inoperable: its verification shipped `grep ':*'`, which in basic regex means
  zero or more colons and so matches every line. Escaping does not rescue it — `grep -F ':*'` matches
  `WebFetch(domain:*)`, and the permissions doc documents `Agent(isolation:*)`, `WebFetch(domain:*)`
  and `WebFetch(domain:*.example.com)` as legitimate syntax, so a correctly escaped check would trade
  a never-clean result for false positives on documented rules. The only accurate replacement —
  flagging a `:*` that is not at pattern end, which the page shows never matches — has no instance in
  this repo. The known-issues row keeps its citation and drops its tracked action. Generic
  "deprecated syntax" wording elsewhere stands: the settings doc documents real deprecations.

- **`audit-permission-grants`: the routing eval that asserted the removed check.** Its scope-boundary
  eval routed a `:*` check to the sibling skill, so after the removal prose and eval disagreed and
  the grader could reward a response repeating the false label. It now exercises the same routing
  boundary through a check that still exists.

### Fixed

- **`audit`: settings, hooks, MCP and permission syntax do not all live on the settings page.** The
  skill attributed four upstream invariants to that one page and one audit phase. The page defers
  hook format and complete permission-rule syntax to their own pages, and the skill's own checklist
  already routes hook events elsewhere. Each is now resolved against its own official page when a
  check needs it.

- **`audit`: hook matchers are not simply "valid regex".** [Hooks
  reference](https://code.claude.com/docs/en/hooks) makes the evaluation path depend on the matcher's
  characters — letters, digits, `_`, `-`, spaces, `,` and `|` give an exact-string list; anything
  else gives an unanchored JavaScript regex, so `Edit.*` also matches `NotebookEdit`. The check
  now examines the intended path and anchoring rather than syntactic validity.

- **`audit-automation-gaps`: hook inventory reached one of six hook locations.** It now covers user,
  project and local settings, managed policy settings, each enabled plugin's `hooks/hooks.json`, and
  skill or agent frontmatter — an inventory missing five locations can report a gap that is already
  filled.

- **`audit-automation-gaps`: slowness alone no longer disqualifies a hook.** `async: true` runs a
  command hook in the background for exactly the long-running case the gate rejected, so the gate now
  turns on whether the hook must block. Async hooks cannot block tool calls or return decisions, and
  only `command` hooks support it.

- **`audit-automation-gaps`: the "Not scriptable" gate no longer claims to cover reasoning-only
  concerns.** `prompt` hooks send a prompt to a model for single-turn evaluation and `agent` hooks
  spawn a subagent that can use tools to verify conditions — those mechanize the concerns the gloss
  assigned to the gate. Agent hooks are experimental and may change.

- **`audit-pass`: built-in output styles do not drop the coding instructions.** The claim was
  unscoped, but [Output styles](https://code.claude.com/docs/en/output-styles) says "Custom output
  styles leave out Claude Code's built-in software engineering instructions … unless
  `keep-coding-instructions` is set to `true`", and the built-in **Default** style "is the existing
  system prompt" — a direct counterexample. `keep-coding-instructions` is frontmatter in an
  output-style file, and built-in styles have no file, so the exception could not apply to them. The
  attestation date moves with the re-fetch; the operative `force-for-plugin` claim is unchanged.

## [0.21.8]

### Changed

- **`audit-instructions`: `I6` gains model-delta corroboration and `I15` reasoning-cost
  corroboration from Anthropic's context-engineering blog** (criteria 1.16.0). Both rows rested on
  live-doc sources alone; [The new rules of context engineering for Claude 5 generation
  models](https://claude.com/blog/the-new-rules-of-context-engineering-for-claude-5-generation-models)
  (2026-07-24) states each from the vendor's own system prompts and shipped guidance, so the
  citation is added rather than a new row minted — the digest's conflicting-directive question
  resolved to existing `I15` coverage plus this rationale, and its bare-prohibition candidate to
  `I6` as already-covered doctrine.

  `I6`: the blog's retired system-prompt line "In code: default to writing no comments. Never write
  multi-paragraph docstrings or multi-line comment blocks — one short line max." is a worked
  instance of the row's Detect shape, its stated obsolescence ("newer models have better judgement
  and can handle these decisions well without explicit rules") is the model-delta ground, and its
  replacement — "Write code that reads like the surrounding code: match its comment density,
  naming, and idiom" — is an instance of the row's positive-reframing remediation, shipped by
  upstream.

  `I15`: the blog's "Unhobbling Claude" adds the cost the memory doc's arbitrary-pick sentence does
  not state — even a correctly resolved conflict taxes reasoning ("Claude must think more carefully
  about these overlapping and conflicting messages before deciding what to do"), evidenced by
  "several conflicting messages in a single request" as Anthropic's own system prompt, skills, and
  user requests clash with each other.

  The page joins `## Sources` and is therefore inside the catalog-wide recheck trigger like every
  other entry, keeping the trigger-set-equals-source-set invariant; it is noted there as a dated
  post, static once published, so that recheck is expected to find it unchanged. Neither citation
  carries a per-row verification stamp: the catalog owes one where a row restates a volatile
  upstream literal — a level name, a model range, a type predicate — and both rows quote prose
  rather than restate such a literal. Both rows keep the `ANTHROPIC-DOCS` Authority their primary
  documentation sources carry; primary sources are unchanged — the blog corroborates, it does not
  define.

## [0.21.7]

### Added

- **`audit`: category H, the model and effort settings no category reached.** The skill advertises
  settings-file and environment-variable correctness "against current official docs", and categories
  A–G reach schema, permissions, MCP servers, hooks, plugins, environment variables, and the
  skill-listing budget. None reached the model-configuration keys, so `effortLevel`,
  `fallbackModel`, `availableModels`, and `enforceAvailableModels` went unaudited in a skill whose
  stated scope includes them. Phase 2's enumeration, `validation-categories.md`, and a mandatory
  Phase 3 model-config fetch all move with it, so the category is reachable by the skill's own flow
  rather than stranded in the checklist.

  The four rows share one shape: each names a value the harness accepts into the file and then does
  not apply as its author expects. `effortLevel: max` is not the level that persists; a fourth
  `fallbackModel` entry risks being ignored; a specific model listed beside its own family wildcard
  narrows the allowlist to that one version; `enforceAvailableModels` without a non-empty
  `availableModels` does nothing at all.

  Three rows are `warning`. The `enforceAvailableModels` pairing is `error`, because this skill's own
  severity guide rates an enforcement bypass that way and that is what the finding is: an
  administrator who set the key believes the Default option is constrained when it is not. That row
  fires only on `enforceAvailableModels: true` with the list unset or empty — an explicit `false` is
  someone disabling enforcement deliberately, so the check gates on the value rather than the key's
  presence.

  **`check-structure.sh` now reports the four keys by value for `settings.local.json`.** Category H
  can read `settings.json` and `~/.claude/settings.json` directly, but the safe-read rule routes the
  local file through this helper, and the helper emitted only environment, permission, and plugin
  counts — so a key living only in `settings.local.json` was invisible and its defect silently
  missed. Counts could not have closed that: the allowlist wildcard rule turns on which family each
  entry names, and the fallback cap turns on entry order. The four values are configuration
  identifiers — level names, model names, a boolean — not credentials, so emitting them leaves the
  secret guard untouched, and a test asserts env values and env key names still never appear.
  `unset` and `(empty list)` are reported distinctly because they are different findings. Existing
  output lines are unchanged; the new lines are appended, and the script's own suite covers the
  addition (10 checks before, 24 after).

  **How loudly each surfaces differs, and the rows say so individually.** An earlier draft claimed a
  blanket runtime silence; that is false for the allowlist row, where a narrowed alias shows a
  substitution notice naming both models. Two rows also have an authoring-time path — the declared
  schema constrains `effortLevel` by `enum` and `fallbackModel` by `maxItems` — so a schema-aware
  editor catches them first. They stay because the schema is advisory and the harness reads a file
  that violates it. Where the two authorities disagree they are reported separately: `maxItems` caps
  RAW array length while the page caps the chain after deduplication, so a four-entry chain holding
  one duplicate fails the schema and satisfies the harness.

  Rows were admitted on one test: the key must appear in a file this skill actually opens. That
  excluded the managed-source placement rule for the `availableModels` pair, which no local file can
  decide, and it is carried as guidance in the verify column instead of a verdict. `modelOverrides`
  key validation is excluded for a different reason and stated as a closing note: deciding whether a
  key is a real model ID means resolving it against Models overview, and that page's own restatement
  deferral governs new consumers of the facts it owns.

  **The frontmatter-`effort` lint stays deferred and untouched.** That separate item would lint the
  `effort` frontmatter field in this repository's own agents and skills; it has no host, and the
  value list it would need is deliberately not restated in this repo. Category H is a different item
  on three counts — a different key (`effortLevel`, not `effort`), a different file (a consumer's
  settings, not this repo's component frontmatter), and a host that already exists. Its deferral
  permits exactly this: a new item with a chosen host, rather than the deferral being lifted.

  The rows do restate the session-only effort semantics rather than citing this repo's philosophy
  doc, deliberately: this checklist ships into consumer repositories where that doc is not present,
  so a citation would resolve to nothing and the row would lose its detection. Note the rows also
  quote the upstream page verbatim where categories A–F restate their sources inline instead. That
  is a deliberate departure — these findings turn on exact wording a reader will want to check
  against the page — and the Phase 3.3 fetch is what keeps the quotes honest as the page moves.

  Verified 2026-08-04 against <https://code.claude.com/docs/en/model-config>, fetched as raw
  markdown (82,975 B), and against the declared settings schema at
  <https://json.schemastore.org/claude-code-settings.json>. Recheck trigger: the `effortLevel`
  accepted-value set changing, the three-model fallback-chain cap changing, the wildcard-disabling
  rule for a specific family entry changing, or the schema's `enum`/`maxItems` constraints diverging
  further from the page.

### Fixed

- **`audit-instructions`: `I17`'s `effortLevel: max` carve-out justified itself with a false claim**
  (criteria 1.15.0). It read that the settings schema "accepts `low`, `medium`, `high`, `xhigh`
  only, so that string is unreachable there". The schema is advisory JSON Schema: the value is
  writable, the file merely fails validation, and the harness reads it anyway — which is precisely
  why the new `audit` category H checks for it. Left as written, one plugin asserted both that the
  value cannot appear in a settings file and that a sibling category hunts it there. The carve-out
  itself is unchanged and still correct — an instruction-text catalog should not hunt the literal —
  but it now rests on the editor-catches-it-at-authoring-time reason rather than an impossibility
  that does not hold, and points at the category that does own the file-level check.

## [0.21.6]

### Changed

- **`audit-instructions`: `I8-c`'s scope is now positively confirmed narrow, and the row states what
  the leakage costs beyond the turn it appears in** (criteria 1.14.0). The row flags a
  don't-think / don't-reason directive, and rested on a single source — the Opus 5 guide's "Running
  with thinking disabled" — with `Model scope: opus-5` held only by the fact that no wider statement
  had been found.

  Troubleshooting thinking states the same claim from the symptom side, "System-prompt rules
  instructing the model not to think or not to reason increase the tag leakage", and it does so on a
  **model-agnostic feature page** — the surface where a wider claim would surface if there were one.
  It names Claude Opus 5 anyway. So the scope stays where it is, but for a better reason: upstream
  had the chance to widen and declined, which is the reasoning `I10` already applies to a declined
  widening. The promotion gate remains unmet, deliberately.

- **The consequence clause the row was missing.** The same section states that "A leaked tool call
  never runs, and in agentic loops the leaked text stays in the conversation history, so later turns
  are affected as well", and that leakage is "most commonly on tool-heavy workloads such as search".
  Both now travel with the row: the first because it makes the finding a history-poisoning failure
  in an autonomous lane rather than one malformed response, and the second because it tells an
  auditor which surfaces to read first. The `Source` line carries its own verification date and a
  recheck trigger keyed to the claim gaining a model beyond Opus 5, which is the event that would
  move the promotion gate.

- **The `Sources` block's parenthetical for that page** covered the per-request 400s and the effort
  restriction's model range only, so it understated what the catalog now cites the page for; it
  names the leakage claim as well.

## [0.21.5]

### Added

- **`audit-instructions`: `I18-a`, a leading thinking block treated as required where the model does
  not require one** (criteria 1.13.0, taking the next minor over PR #1917). I18 covered only what a
  surface does to thinking blocks it *has* — dropping the `signature`, the `type == "thinking"`
  filter, editing the latest turn's blocks. The opposite error had no row: believing a block must
  be there. The Steering
  thinking page states the relaxation outright — "Assistant turns don't need to start with a
  thinking block" — with three consequences that become the row's three detect shapes: reinsertion
  when assembling history from mixed sources, rewriting history on resume under a different
  thinking configuration, and logic that reads an assistant turn's first block as though it were a
  thinking block.

  **It is a sub-row of I18 rather than a new criterion because the two are one mechanism seen from
  both ends.** The remediation a reader reaches for once they believe a block is required is to
  fabricate one, and a hand-built block carries no valid `signature` — which is I18's own shape 1
  and a rejected request. So this row is the upstream *cause* of an I18 violation; both are reported
  when a surface states the premise and acts on it. I18 gains a two-sentence lead-in naming the
  pairing and a `Base row:` label; its detect, fences, source and stamp are unchanged.

  **Reach is I18's, unchanged, for all three shapes** — a path back to the model, whatever the file
  format. Presence-assuming logic that only ever *reads* is recorded as out of reach rather than
  excused: the page's caution sits in the request/response frame and says nothing about stored
  transcripts, whether a harness transcript carries thinking blocks at all is unestablished, and the
  harm there would be the consumer's own logic rather than a 400 — a code-correctness matter this
  catalog does not audit. The row carries a `Re-scope when` clause for the day that shape is
  documented. Severity is `warning` against I18's `error` on its own footing: wasted work plus a
  fabrication risk, not a guaranteed rejected request.

  **The carve-out is upstream's own, and exactly as wide as its source.** Models using a legacy
  manual thinking budget do enforce that the final assistant turn of a thinking-enabled request
  begins with one, so text scoped to that mode AND that turn is correct; a legacy-scoped
  instruction demanding the block on every assistant turn over-requires past its own source and
  still flags — the finding is the missing gate, never the mention, as in `I17-c`. The row also
  fences itself against being read as license to drop blocks: the relaxation "is about validation,
  not about what you should send".

  **Decisive source, with the sibling as corroboration.** The Thinking page carries the same pair
  compressed into one sentence inside "Thinking with tool use" — extended (manual) mode "additionally
  enforces that the final assistant turn of a thinking-enabled request begins with a thinking block",
  and "Adaptive mode relaxes this: no assistant turn needs to start with one." Steering thinking is
  where the relaxation is stated operatively, with the three history-shape consequences the detect
  shapes are drawn from and the presence caution, so it is cited as decisive and the sibling as
  corroboration. Separate from both is that page's strip claim — the API "may strip thinking blocks
  that would create an invalid turn structure" — server-side degradation of a request rather than a
  rule about what history a caller may send. The Steering thinking page joins Sources. Local
  coverage measured 2026-08-04: zero
  operative instances, on the same footing as I18, with a re-measure clause. The one transcript
  consumer here, `session-flow`'s retro parser, selects blocks by each item's own `type` rather than
  by position, so it is correct by construction rather than by this rule.

## [0.21.4]

### Changed

- **`audit-instructions`: `I17` gains a second arm — the models that reject a thinking-disable
  outright, at every effort level** (criteria 1.11.0 → 1.12.0). The base row detected a *pairing*: a
  thinking-disable surface together with `xhigh` or `max` effort, on Opus 5 and later. The Thinking
  page states a second restriction in the paragraph directly after that one — "Claude Fable 5,
  Claude Mythos 5, and Claude Mythos Preview reject `thinking: {type: "disabled"}`: thinking cannot
  be turned off on these models" — with no effort qualifier at all.

  **The gap was a wrong remediation, not only a missed case, which is why this amends the base row
  rather than adding a sibling.** Either reading of the old row's range was a defect. Read as
  covering Fable 5, the row fired and handed out `Remediate`'s "lower the effort to `high` or below,
  or leave thinking on" — advice whose first branch still returns a 400 on that family. Read as
  excluding it, the unconditional reject went undetected and the row's own `Must NOT flag` fence
  ("a thinking-disable surface named with no effort level in reach of it") actively excused it. Both
  are now scoped to the arm that earns them: the fence applies to the Opus 5 arm, and the second
  arm's remediation has one branch, not two.

  **Only the API form joins the second arm.** On **Fable 5** the harness disable surfaces —
  `MAX_THINKING_TOKENS=0`, the session toggle, `alwaysThinkingEnabled` — are silent no-ops rather
  than errors, which is `I17-a`'s failure and stays there; for **Mythos 5 and Mythos Preview the
  harness pages state nothing**, so the row claims nothing about their harness surfaces. The
  scoping matters because model configuration names Fable 5 alone and never discusses Mythos
  — asserting the family would be the catalog breaking its own does-not-state standard. The row
  heading changes from "at an
  effort level that forbids it" to "where the model forbids it", since an arm with no effort operand
  no longer fits the old wording. **Local coverage measured, not asserted:** zero operative
  instances, with all six occurrences of the disable literal being documents *about* the
  restriction — the audience-test fence, not a passed check.

- **`audit-instructions`: `I17-b` extends from effort churn to thinking churn, and its harness
  carve-out is re-scoped to the half that earns it.** The row detected a mid-session *effort* change
  prescribed without its cache cost. The Thinking page puts the thinking configuration in the same
  position as effort — both "are rendered into the prompt itself, so changing any of them starts a
  new cache prefix" — naming switches among `adaptive`, `enabled` and `disabled` and changes to
  `budget_tokens`.

  **The carve-out is the load-bearing part.** The old row excused "a Claude Code surface" wholesale,
  because the harness "asks you to confirm before applying the change". That dialog is documented
  for effort alone: `code.claude.com/docs/en/prompt-caching` names exactly two settings outside the
  prompt text that are still part of the cache key — model and effort level. Left unscoped, the
  extended row would have silently asserted that the harness warns before a thinking toggle, which
  nothing upstream says. The carve-out now names effort explicitly, and the thinking half is stated
  for the API and Agent SDK callers the page's claim actually covers rather than reaching for a
  harness consequence the docs do not carry.

- **`audit-instructions`: the Thinking page's Sources entry names the two properties these arms rest
  on** — the models that reject a thinking-disable outright, and what a thinking or effort change
  does to the cache prefix. `I17` base and `I17-b` were re-verified live against their full source
  sets on 2026-08-04 and carry that stamp; `I17-a` carries a split stamp — only its new
  session-toggle/`alwaysThinkingEnabled` clause was re-verified 2026-08-04, its original claims
  keep their 2026-08-02 check; `I17-c` is untouched and keeps its own. `I17-a`'s Detect gains the harness controls its explanation already
  named: the session thinking toggle or `alwaysThinkingEnabled` presented as turning thinking off on
  Fable 5 is now flagged (model configuration states they "have no effect there") — previously the
  base row routed that failure to `I17-a` while no arm of it actually detected it. `I17-b` also
  gains a reach clause — its thinking half covers API and Agent SDK surfaces only, since the harness
  documents neither a dialog nor a cost for a mid-session thinking toggle — and a co-firing note
  against `I17-c` scoped to accepted changes: a rejected request completes no turn and an ignored
  value changes no configuration, so where `I17-c` condemns the control the cache-cost claim never
  materializes and `I17-c` fires alone; both fire only when a surface prescribes both an invalid
  control and, separately, an accepted mid-session change.

## [0.21.3]

### Added

- **`audit-instructions`: `I8-e`, forced interim-status cadence, scoped `sonnet-5`** (criteria 1.10.0
  → 1.11.0). The Sonnet 5 guide prescribes removing exactly the scaffolding `I8-d` reaches on a
  Fable 5 target — "If you've added scaffolding to force interim status messages ("After every 3
  tool calls, summarize progress"), try removing it" — on its own ground, that the model already
  reports well without it.

  **It is scoped, not unscoped, and that was the contested call.** The obvious reading is that a
  second model guide now converges on `I8-d`'s cadence arm, which would meet the promotion gate and
  let one row fire fleet-wide. It does not. The gate wants two guides *stating* the claim, and the
  Fable 5 guide never states it: its "Longer turns by default" section prescribes adjusting client
  timeouts, streaming, and progress indicators, says nothing about removing instructed status
  cadence, and elsewhere that guide recommends *adding* a send-to-user progress mechanism. `I8-d`
  reaches the cadence by inference from a turn-duration premise — a legitimate ground for a scoped
  row, but not a second statement. Two scoped rows therefore cover one instruction shape from the two
  guides that reach it; exact-match scoping means they never co-fire, and both rows now say so, so a
  later reader does not "deduplicate" them.

  `I8-d`'s detect and fences are unchanged; it gains one cross-reference bullet naming the
  relationship.

- **`audit-instructions`: `I17-c`, a fixed thinking budget prescribed where adaptive reasoning
  ignores or rejects it.** `I17-a` already covers `MAX_THINKING_TOKENS=0` sold as a universal off
  switch — the claim that thinking can be turned *off*. Nothing covered the adjacent claim that
  thinking depth can be *set to a number*, whose two arms fail in opposite ways: a nonzero
  `MAX_THINKING_TOKENS` is silently ignored on adaptive-reasoning models and
  `CLAUDE_CODE_DISABLE_ADAPTIVE_THINKING` cannot rescue it, while API `thinking: {type: "enabled",
  budget_tokens: N}` returns a hard 400 across Opus 4.7 and later, Sonnet 5, Fable 5, and Mythos 5.
  Unscoped, with the model ranges as Detect conditions rather than a `Model scope` annotation, for
  the reason `I17` base states.

  **The row's central fence is that the finding is the missing gate, never the mention.**
  `CLAUDE_CODE_DISABLE_ADAPTIVE_THINKING` is *not* a retired variable: it is live on Opus 4.6 and
  Sonnet 4.6, where it does exactly what it says, and it lost its reach over the adaptive-reasoning
  models only at Claude Code v2.1.111 — so the gate is a release as well as a model set, and text
  scoped to an earlier release is also correct. The obvious implementation — grep for the variable
  name and call every hit stale — would flag every accurate piece of documentation about it, so the
  row carries I12's precondition rule applied to these literals explicitly.

### Changed

- **`audit-instructions`: `SKILL.md` records why `I8-e` is not seeded** into the deterministic
  pre-scan. It sits with `I8`'s base row and `I8-d` in the lane-only list, but on a narrower ground:
  its skeleton is patternable, and it waits only on an attested instance to calibrate the interval
  forms against — not on the "phrasings too varied" reason its neighbours carry.

- **`audit-instructions`: the model migration guide joins the catalog's Sources.** `I17-c`'s API arm
  cites it for the model range over which manual extended thinking is rejected. Per the catalog's own
  rule that the trigger set is the source set, this **widens the catalog-wide recheck trigger** —
  every row now re-verifies when that page changes. That is the intended consequence of citing it,
  recorded here rather than left as a side effect of adding a bullet.

## [0.21.2]

### Changed

- **`audit-instructions`: I10's `Model scope: fable-5` is now positively sourced instead of resting
  on a declined widening** (criteria 1.9.0 → 1.10.0). The row's conclusion does not move — Mythos 5
  is still not in scope, and still should not be. What moves is the ground under it. Since 0.18.0
  the row held its narrow scope by reading an omission: the Thinking page names both Claude Fable 5
  and Claude Mythos 5 for the adjacent raw-chain-of-thought property, then names Fable 5 alone for
  the refusal, and the row inferred deliberateness from that declined chance to widen. That is an
  argument from authorial choice, and it is the weakest link in an otherwise well-cited row —
  silence is evidence only until someone finds the sentence.

  The sentence exists, on the page that owns Mythos 5: "Claude Fable 5 includes safety classifiers
  that can decline certain requests. Claude Mythos 5 does not include these classifiers, so this
  section applies to Claude Fable 5 only" ([Introducing Claude Fable 5 and Claude Mythos
  5](https://platform.claude.com/docs/en/about-claude/models/introducing-claude-fable-5-and-claude-mythos-5),
  fetched 2026-08-03, HTTP 200).

  **The row states it as two steps, each from the page that owns its half**, rather than letting
  either page settle it alone. The introducing page excludes the whole classifier *set* for
  Mythos 5 — "these classifiers," referring to the set that can decline requests — and Refusals and
  fallback puts this row's category inside that set, listing `reasoning_extraction` among the
  categories a refusal reports. Collapsing the two into one citation would rebuild the near-miss
  scope inheritance the catalog's model-scoping block forbids, only pointing the other way; keeping
  them separate is what makes it a citation rather than an inference wearing one. Note that Refusals
  and fallback attributes the classifiers to Claude Fable 5 **and Claude Opus 5** and never mentions
  Mythos 5 — the exclusion is the introducing page's alone to state, which is why both are cited.

  The introducing page joins `## Sources`, so the catalog-wide recheck trigger fires this row if the
  page changes; which models carry the classifier set is a per-model fact and will move. No narrower
  per-row trigger is owed, per the stamp rule's own carve-out for claims the Sources set already
  covers. The 0.18.0 entry below is left as written — it records what shipped then, and the
  reasoning it describes was correct for the sources available at the time.

## [0.21.1]

### Added

- **`audit-instructions`: row I8-d, short-turn assumptions** (criteria 1.8.0 → 1.9.0). Tier
  `behavioral`, `Model scope: fable-5` — the promotion gate is unmet and stays unmet: the claim
  appears in one model guide and on no model-agnostic page, so the row is inert on other targets
  and reports `skipped-for-target`.

  **Detect** is instruction text resting on the premise that a turn is short — a forced
  interim-status cadence ("summarize every N tool calls"), a directive to answer quickly, any
  progress rhythm pinned to a turn rather than to the work. Individual requests now run for
  minutes at higher effort and autonomous runs for hours, so such a rhythm fires on work that has
  not reached a reportable boundary and interrupts exactly the long runs the model is used for.
  Four fences keep it off legitimate text: an output-length instruction is I8 base's subject, not
  this one's (the axis here is the turn's duration, never the reply's size); a latency or duration
  requirement the surface genuinely owns — an SLA, a downstream timeout, a human review rhythm — is
  a constraint it is entitled to state; a document *about* the pattern is exempt on the same
  audience test I8-b, I17, I18 and I20 already use; and a cadence carrying its own explicit
  observability or interruptibility rationale is a design the surface is entitled to make — that is
  the very guarantee the row's Remediate line protects — exempt unless evidence shows it was
  calibrated to an obsolete turn length rather than to the work.

  The row is **lane-only, not seeded** by `instruction-scan.sh`, and `SKILL.md` now says so
  alongside the existing I8-c disclosure. A pattern family was considered and declined: the
  phrasings are too varied for a rule that would earn its false-positive rate, and the one
  candidate string in this repository resolves to the exempt meta case, so the family would have
  shipped with a known false positive and no true one.

  The guide pairs this behavior with advice to adjust **client timeouts, streaming, and progress
  indicators**. That half is harness client configuration rather than instruction content, so the
  row states plainly that it is out of scope and that no row claims it — the shape that *would*
  reach this catalog is instruction text prescribing a short client timeout, and none is attested.

### Changed

- **`audit-instructions`: I8's base row gains one named worked instance — the delegation
  throttle.** A cap on concurrent workers, a one-at-a-time rule, or an instruction to block until
  each subagent returns, *where the surface's own ground is that subagent handling is unreliable*.
  Current guidance runs the other way (readier dispatch, asynchronous orchestrator-to-worker
  communication), so such a throttle is the base row's generic case with a name on it — which is
  why it lands as recognition material inside I8 rather than as a fourth rule competing with it.
  The qualifier is the whole fence: **a cap carrying its own non-model rationale is not this
  instance.** Reviewability of returns, rate limits, cost, and shared mutable state each justify a
  bound on their own terms, and that justification belongs to the surface making it. The base row's
  Source gains the guide's "Parallel subagents" sentence as the instance's basis; the row restates
  no volatile literal and so owes no per-row verification stamp under the catalog's own
  binds-on-touch rule.

## [0.21.0]

### Added

- **`audit-instructions`: the two agnostic-mechanism rows from the IA-6 / IA-10-A2 ownership split —
  I21 and I22** (criteria 1.7.0 → 1.8.0). Both source rules were **compounds**: an agnostic
  mechanism fused to a consumer-state instance naming this fleet's own machines, files, and dates.
  Routing either wholesale was wrong in both directions — outward it would ship our private state to
  every consumer, inward it would strand a reusable staleness control. Each was split at the
  mechanism/instance line; only the mechanism halves are here. The instance halves (a dated vet, a
  chezmoi-managed fleet pin) are drafted for the consumer repository and deliberately ship nowhere
  in this plugin.

  - **I21 — effort level pinned across a model change with no re-sweep** (`mechanical`,
    `ANTHROPIC-DOCS`, `warning`, unscoped). The effort scale is calibrated per model, so the same
    level name does not carry the same underlying value across models, and a level measured against
    one model then carried to the next is a pin nobody re-measured. The promotion gate is met on the
    strong form: model configuration states the calibration property **with no model qualifier**, so
    that page alone carries the row; the effort page's Opus 5 subsection is cited only for the
    remediation's wording, and its per-model placement does not narrow a property stated generally.

    **The model range is a Detect condition, not a `Model scope` annotation**, on I17's reasoning.
    It is in Detect because the *consequence* varies: Claude Code applies a model's default effort
    on first run of Fable 5, Opus 4.8, or Opus 4.7 and holds it, so a carried level there is
    overridden harmlessly — while **Opus 5 has no such hold** and a stale pin actually reaches the
    request. One thing is recorded as **unresolved rather than inferred**: the page names `/effort`
    and `--effort` as *examples* ("such as") of the explicit choice that releases the hold, so
    whether a settings-file `effortLevel` pin releases it is not stated anywhere read for this row.
    The row therefore fires on the missing re-derivation regardless of model, and the hold is
    severity context, never a fence.

    Four fences keep it honest. A prescription of **`high` is exempt only where `high` is the
    resolved target's default** — it is "Equivalent to not setting the parameter", so on such a model
    it carries no measured calibration. **The exemption keys to the resolved target, never to the
    wording**, which is what makes it correct: `high` is the default everywhere **except Opus 4.7,
    which defaults to `xhigh`**, so when the target is 4.7 the exemption lifts and a broad
    model-agnostic "always use `high`" naming no model is a finding — indeed the sharper case, since
    a pin written where `high` was the no-op default becomes a silent step-down the moment it reaches
    a model whose default sits above it. A resolved target always exists, because the skill body
    aborts rather than run against an unresolved one, so the fence never guesses. A **per-task**
    choice
    (`ultrathink`, "reach for `xhigh` on hard problems") is not a durable pin. **`effort:`
    frontmatter and `effortLevel` keys route to `claude-config:audit`** on I17's
    instruction-text-versus-config discriminator. And **schema documentation and its illustrative
    samples** are fenced **separately** rather than folded into the config fence, because a worked
    example quoted inside documentation prose is not a key living in a config file and the config
    fence would not have reached it — the level in a sample demonstrates syntax, not a measured
    choice. That fence ends where the demonstration does: documenting the field *and then telling the
    reader which level to put there* is prescribing, and stays in scope.

  - **I22 — model-routing doctrine with no baseline named** (`mechanical`, `OPINION`, `info`,
    default **off**, enabled by `--opinion`). First-party lane assignments derived from a reading of
    vendor selection pages, written down with neither the baseline they came from nor an event that
    re-opens them, become a claim about a model generation that has since passed, told in the
    present tense. Its own contribution beyond "attach a trigger" is the **delta-not-re-run**
    discipline: the action on a trigger is a targeted delta check against the named baseline, never
    a re-derivation from scratch — a trigger nobody can afford to run is not a control.

    **The row carries no baseline of its own, by design.** Naming a date or a vet here would hand
    every consumer a foreign snapshot as their baseline, reproducing in their repos the exact drift
    the check exists to catch.

    Its third-party fence is stated **narrowly on purpose**: transcribed practice is out of scope
    only because there is no vet to point at, **not** because a sync stamp makes it fresh. A stamp
    tracks whether the transcription is current, never whether the transcribed advice still names a
    live model — so a stale lane recommendation inside a faithfully synced pack stays stale. That
    residual is the transcribing surface's to carry, and the fence says so rather than implying the
    sync path has it covered.

    Its non-duplication is stated in the row rather than assumed. **I19** covers a restated
    *benchmark figure* and asks for the four-part record; it says nothing about lane assignments and
    nothing about how to act when a trigger fires. **The catalog-wide recheck trigger** does not
    reach it either — that trigger governs *this catalog's* staleness against its Sources, not an
    audited surface's staleness against the pages its doctrine was read from. It ships
    `Source: none` on I19's footing and adds no Sources entry for the same reason.

### Changed

- **`audit-instructions`: the model-configuration and effort Sources entries name what I21 depends
  on** — the per-model calibration of the effort scale and the first-run default hold, and `high`'s
  equivalence to omitting the parameter plus the carry-over sweep advice. The catalog's "the trigger
  set is the source set" invariant makes these parentheticals load-bearing: a dependency the entry
  does not name is a dependency nothing watches.

- **`audit-instructions`: `--opinion` no longer restates which rows it enables.** The flag's
  description in the skill body carried its own copy of the `OPINION` row set, which is a second
  place to update on every new `OPINION` row and, when stale, silently narrows the flag below what
  the catalog actually defines. The set is now read from the catalog at run time, where the
  enablement policy already lives, and the run's tier-transparency line reports the count it found —
  removing the drift class rather than correcting one instance of it.

## [0.20.1]

### Fixed

- **`audit-pass`: age alone no longer reclaims an applying run's lock where the platform exposes no
  process start identity (#1786).** The reclamation rule's second conjunct was a start-identity
  match, and the "where none exists, **age alone reclaims**" fallback had no liveness conjunct at
  all — the lease's heartbeat was mentioned one sentence later as prose no reclamation test
  consulted. A live `--fix` exceeding 30 minutes on such a platform lost its lock to a second
  applying run, contradicting assertion 3.1's *"exactly one proceeds"* on exactly the platform least
  able to detect the collision. The lock now records the holder's **run id** (and its start identity
  where one exists) so reclamation can find the holder's lease, and where no start identity is
  available the lease is the second conjunct: past 30 minutes a **stale** or `released` lease
  reclaims and says so, a **live** lease refuses exactly as it would inside the window, naming the
  run id and `heartbeat_at`. The classification reuses §3's existing two-sided liveness test rather
  than introducing a second one. This does not reintroduce the unreclaimable lock the age bound
  guards against: a crashed holder stops refreshing, so its lease goes stale within the liveness
  threshold, and a missing or unreadable lease is treated as stale — the absence of a heartbeat is
  not evidence of life. Same defect class and same remedy shape as `claude-ops`' restart-consumer
  (#1759/#1760), where a live PID without a boot identity may only defer a reclaim — that deferral
  needs a hard ceiling only because its holder publishes no lease. A lock written *before* this rule
  carries no run id and is covered too: reclamation establishes the conjunct the other way round, by
  enumerating every lease under `runs/<state-key>/`, so upgrading mid-run never hands a live holder's
  lock away. The order of the two writes is now normative for the same reason — an applying run
  writes its lease **before** it takes the lock, since a lock whose lease does not yet exist would
  read as stale and be reclaimed on age alone through the window between them. New assertions 3.12,
  3.13, and 3.14; new evals 27 and 29.
- **`audit-pass`: a suppression no longer re-applies silently across an anchor collision (#1786).**
  §1 guarantees that two identical normalized excerpts under one heading path collide and that *"no
  suppression carries forward across it"* (assertion 1.10a), but §4's matching table had no
  collision exception — and a collided site's anchor is by construction **unchanged**, since the
  occurrence discriminator digests the heading path. A previously-suppressed excerpt that later
  gained an identical duplicate therefore satisfied the `SAME, UNCHANGED` row exactly and
  re-suppressed itself with no report. Collision is now tested ahead of the anchor comparison in
  every row and routes to the existing `OLD CLOSED, NEW OPENED` disposition — entry stale per 4.2,
  finding unsuppressed, collision named with its occurrence count — reusing the section's
  established fail-closed answer to an ambiguous match rather than adding a fifth disposition. New
  assertion 4.7; new eval 28.

## [0.20.0]

### Added

- **`audit-instructions`: four consumer-facing rows — I17, I18, I19, I20** (criteria 1.6.0 →
  1.7.0). All four carry knowledge outward rather than inward: they detect defects in repos this
  fleet does not control, and each is agnostic to user, machine, company and repo.

  - **I17 — thinking disabled at an effort level that forbids it**, as a base row plus **I17-a**
    and **I17-b**, on I8's pattern: three shapes with three different decisive sources are three
    rows, not one row with three citations, and splitting them lets each carry its own severity.
    Base row (`error`): pairing a thinking-disable surface with `xhigh` or `max` effort returns a
    per-request 400, and the pairing is assemblable from configuration literals alone. **No harness
    documentation describes a pre-request guard**, so the row states the hazard as real and
    unguarded and deliberately does **not** claim the harness prevents it. It also catches the
    `ultracode` **setting**, which matches neither literal but "sends `xhigh` to the model" and so
    produces the identical rejection — match the effort that reaches the request, not the spelling.
    The same spelling as a **prompt keyword** is fenced out: it runs one task as a workflow
    "without changing the session's effort level", so no effort reaches the request. And it tells
    an auditor **not** to hunt `effortLevel: max`: the settings schema stops at `"xhigh"`, so that
    literal is unreachable there. I17-a (`warning`) is `MAX_THINKING_TOKENS=0` sold as a universal
    off switch, which it is not — no effect on Fable 5, parameter merely omitted on third-party
    providers. I17-b (`info`) is a mid-session effort change prescribed without its cache cost, and
    it explicitly does **not** fire on Claude Code surfaces, where the harness already asks for
    confirmation; it is for surfaces instructing an API or Agent SDK caller, where no dialog exists.

    **The model range is carried as a Detect condition, not a `Model scope` annotation** — the
    catalog's annotation is for rows sourced from a single model's *guide*, matches by exact string
    equality, and has no range form, so annotating `opus-5` would make the row inert on the next
    generation while the restriction ("Claude Opus 5 and later models") still holds. The source is
    a model-agnostic feature page, so the promotion gate is met and the row is unscoped. I20 handles
    its own model range the same way.

    The settings-file scan is explicitly **not** taken: it belongs to `claude-config:audit`, and an
    instruction-content catalog that also scanned settings files would claim authority a sibling
    already holds. The discriminator is whether the content instructs, not which file holds it, so
    a prompt-type hook's injected text stays in scope even though it lives in a settings file.
  - **I18 — thinking blocks altered on the way back to the model.** Signature preservation, the
    `block.type == "thinking"` type-filter smell, and within-turn echo integrity. Reach is wider
    than Messages API client code — Agent SDK callers, harness integrations, and tooling that
    rewrites a stored transcript later replayed or resumed — but the criterion is **a path back to
    the model**, not the file format read, so read-only transcript analysis stays out. The row
    ships **no `redacted_thinking` handling clause premised on those blocks being present in local
    transcripts** — that premise is unevidenced. The term survives only inside the upstream
    sentence that is the type filter's entire stated failure mode, which is where the harm lives.
    Zero instances of all three shapes here, recorded as a dated measurement with its own trigger
    rather than left to read as a clean audit.
  - **I19 — restated external benchmark figure with no recheck trigger.** `OPINION`-tier and off by
    default, because no official page states that a restated benchmark figure needs a
    re-derivation event; the four-part shape it asks for is this monorepo's upstream-drift
    convention, and in a standalone install the four parts rather than the path are the
    requirement. Carries one fence the fleet needed: **a verbatim upstream baseline held for drift
    detection is never flagged**, since stamping it would corrupt the byte comparison it exists to
    serve. That is a genuine suppression, which is what separates it from plugin-cache content and
    managed materializations — those are still flagged, and the finding becomes a routing
    recommendation to the owning repository.
  - **I20 — prefilled assistant response**, at `error`: following the instruction produces a
    rejected request, the same consequence class as I17 and I18. Severity tracks consequence, not
    expected frequency — this is a standing model-delta row whose hit rate here is zero, and it
    fires in consumer repos that still prefill.

- **`audit-instructions`: per-row verification stamps** (criteria 1.6.0 → 1.7.0). A row restating a
  volatile upstream *literal* now carries the four-part record — claim, basis, as-of date, and a
  recheck trigger naming an observable event. A row that only points at its page carries none,
  because a pointer cannot go stale. The block resolves its own relationship to the catalog-wide
  Recheck-triggers rule rather than leaving two authorities over one behavior, which is precisely
  the conflict I15 exists to find: a per-row stamp **supplements** the catalog trigger and never
  narrows it, a row's own trigger names only what the Sources set would miss, and **the catalog
  trigger wins** where they disagree. The requirement **binds on touch**, per the upstream-drift
  convention, so rows predating it are not retroactively non-compliant. Shipping a check that
  silently encoded a snapshot as permanent truth would reproduce, in consumers' repos, the drift
  this catalog exists to detect.

- **`audit-instructions`: five pages join `## Sources`** — effort, thinking troubleshooting,
  settings, environment variables, and prompt caching. As at 0.18.0 and 0.19.0 this is a
  second-order change, and it is intended: the Recheck-triggers block makes the trigger set the
  source set, so adding a page widens the staleness trigger for the **entire** catalog, not only
  for the rows that cite it. A cited page nothing watches would leave those rows depending on an
  unwatched source.

## [0.19.0]

### Changed

- **`audit-instructions`: I8-b (conservative-reporting detection) is promoted to unscoped**
  (criteria 1.5.0 → 1.6.0). The row carried `Model scope: opus-5` and fired only when the resolved
  target model was Opus 5. The **Sonnet 5** prompting guide, "Code review harnesses", states the
  same claim about the same behavior — a review prompt saying "only report high-severity issues",
  "be conservative", or "don't nitpick" is followed literally, so the model investigates just as
  thoroughly and then withholds findings below the stated bar. Two first-party model guides of the
  same class converging is the promotion gate's **second arm**, so the row is now annotated the way
  I7 is and fires for every target model. The Sonnet 5 guide joins `## Sources`, as the
  Recheck-triggers block requires of every cited page. The Detect line's "which **this** model
  follows literally" is now "which **current models** follow literally" — the demonstrative
  referred to the row's scoped model, and an unscoped row has none.

  **The Recheck-triggers block no longer enumerates the model-specific pages.** It read
  "Model-specific pages (the Fable 5 and Opus 5 guides) are superseded on each model generation" —
  a closed list the Sonnet 5 addition immediately falsified. It now reads "the per-model prompting
  guides under Sources", which stays true as guides join. The enumeration also contradicted its own
  paragraph three lines above, which argues that "naming a subset would leave the harness-behavior
  rows depending on pages nothing watches."

- **I8-b's Source line now cites the phrase it could not.** The row's Detect names three trigger
  phrases; **"don't nitpick" appears nowhere in the Opus 5 guide**, which states only the other
  two. The Sonnet 5 guide names all three verbatim, so it is that phrase's only cited home, and the
  Source line says so rather than leaving a trigger phrase attributed to a page that does not
  contain it.

- **I8-b's Remediate line gains the constructive half.** It said only "rephrase to
  report-everything + a separate filter/rank pass", which does not answer the case where a
  single-pass self-filter is genuinely wanted. The Sonnet 5 guide covers that case — "be concrete
  about where the bar is rather than using qualitative terms like `important`" — so the line now
  keeps the filter and asks for an enumerable test in place of a qualitative label.

  **Promoting this row flags nothing new in this repository.** The scanner's I8-b population here
  is 23 candidate rows across 6 files, every one of them already fenced by the row's own two
  fences — the restraint-clause shape (`code-tidying`'s tidyings catalog) and the quoted/meta
  surface (this criteria file, the scanner and its tests, two model-adaptation delta chapters).

## [0.18.0]

### Added

- **`audit-instructions`: I10 gains a second corroborating source and a concretized remediation**
  (criteria 1.4.0 → 1.5.0). The Thinking page states the same `reasoning_extraction` refusal I10
  already cited from the Fable 5 guide, from a second, independent page — a feature page rather than
  a model guide. The row records why that citation does **not** move the promotion gate: the page's
  own section names both Claude Fable 5 and Claude Mythos 5 for the adjacent raw-chain-of-thought
  property, then names Fable 5 alone for the refusal, so the narrower scope is deliberate rather
  than an omission. **`Model scope: fable-5` is unchanged, and `mythos-5` is deliberately not
  added** — no source states the refusal for Mythos 5, and inheriting it from a claim about a
  different property is exactly the near-miss scope inheritance the catalog's model-scoping block
  forbids.

  **The Remediate line now names the surfaces instead of gesturing at them.** It said "read
  structured `thinking` blocks or use a send-to-user tool"; the sanctioned reading surfaces are
  `Ctrl+O` verbose mode and the `showThinkingSummaries: true` setting in Claude Code, and
  `display: "summarized"` on the API. The two Claude Code surfaces are stated on the model
  configuration page, **not** on the Thinking page, so both pages join the catalog's `## Sources`
  list — the Recheck-triggers block makes the trigger set the source set, and a cited page nothing
  watches would leave the row depending on an unwatched source.

## [0.17.0]

### Fixed

- **`audit-instructions`: the conflict pass excluded command hooks whose output is injected into the
  session's context (#1726).** `conflict-criteria.md` carried "Command-type hooks are outside this
  pass entirely", citing the context-window doc's compaction table, whose hooks row reads "Not
  applicable; hooks run as code, not context". That row is about the hook *mechanism* — a hook
  definition is not a context block to be re-injected — and the same page says the opposite about
  handler *output*: a `PostToolUse` hook "reports back via `hookSpecificOutput.additionalContext`.
  That field enters Claude's context." The exclusion therefore dropped one half of every pair whose
  hook side was live standing instruction text, silently, since a per-surface lane never sees the
  surface at all.

  **The discriminator is now whether the handler's output reaches this session's context, not
  whether the handler is `type: "command"`** (criteria 1.1.0 → 1.3.0). Handler stdout on
  `SessionStart`, `UserPromptSubmit`, and `UserPromptExpansion`, and
  `hookSpecificOutput.additionalContext` on a main-session event that accepts it, enter the
  comparison set **as text**; stdout on any other event still does not. `mcp_tool` shares the stdout
  channel and `http` the JSON one. `prompt` and `agent` handlers keep their existing treatment —
  they return a decision, so they still enter as the act they gate, never as their prose.

  **Type still decides registrability, and the pass resolves the event×type pair before admitting a
  surface.** "Not all events support every hook type"; `SessionStart` takes only `command` and
  `mcp_tool`, so an `http` handler there is not a surface with unreadable text but one that cannot
  be registered at all. An `http` handler also has no stdout — it returns a response body.

  Four residency bounds ship with the admission, so the widening does not manufacture pairs.
  `SubagentStart` and `SubagentStop` `additionalContext` is "Context added to **the subagent's**
  context", so it fails gate 1 against every main-session surface exactly as the active output style
  does — it pairs against the agent definition it runs under, never against the main conversation's
  `MEMORY.md` or output style. Injected text is ordinary message history rather than a re-injected
  surface (a `SessionStart` hook re-injects after compaction only on the `compact` matcher, so a
  `startup`-only hook's pair is conditional there). Exit-2 stderr reaches Claude but is turn-scoped
  error feedback, not a standing directive, and it carries a gate only on the events that can
  actually block. And a hook's own configuration — command line, arguments, `matcher` — remains the
  gate rather than instruction text.

  Phase A's hook inventory splits into the two kinds accordingly, across settings scopes, managed
  settings, and plugin `hooks/hooks.json`, under unchanged no-secrets handling; where the injected
  text is not literal in the config (a handler that runs a script) the surface is recorded with its
  event and `matcher` and marked `text-unresolved` — a distinct marker, since a bare `unresolved`
  already names a precedence verdict — rather than invented. Because a hook-injected surface
  has no file of its own, the Output format now defines its anchor as the settings file, plugin
  `hooks/hooks.json`, or component frontmatter where the emitting handler is configured, qualified
  by that handler's event and `matcher`. The `hooks` scope value and the non-memory surface
  partition widen from "prompt-type hooks" to "hook instruction text" — without which the newly
  admitted surface could be read but never produce a finding — as do the two consumer surfaces that
  restate the list, the skill's own `description` and the plugin README. Skill and agent frontmatter,
  a documented hook location Phase A did not inventory at all, is added alongside — **split by
  ownership rather than filed under one tier.** A frontmatter hook in a user- or project-scope
  `.claude/skills/**/SKILL.md` or `.claude/agents/*.md` is as editable as the body it rides on, so it
  joins the **editable** inventory and produces a proposal of its own; only an enabled plugin's
  *cached* components stay in the read-only tier, whose contract yields no proposal and routes to
  another owner. Filing every frontmatter hook read-only would have mishandled the locally owned
  ones — and reading the item as plugin-cache-only would have left them inventoried nowhere. A
  frontmatter hook anchors at its own component file and frontmatter line, and a subagent's `Stop`
  hook is registered as `SubagentStop`, so the effective event is resolved before pairing.

  **The exit-2 gate is applied only where exit 2 can actually block.** Treating every exit-2 stderr
  message as the act it blocks manufactured an unsatisfiable conflict on events that block nothing:
  a `PostToolUse` linter exiting 2 would have read as a prohibition on the very tool a `CLAUDE.md`
  requires, though the tool already ran and the hook can neither block nor undo it — as this
  repository's own `PostToolUse` linter records at `plugins/actionlint/hooks/actionlint-check.sh`.
  The hooks page's per-event exit-2 table now partitions the treatment: exit 2 blocks on
  `PreToolUse`, `UserPromptSubmit`, `Stop`, `SubagentStop`, `PreCompact`, and `UserPromptExpansion`,
  where the stderr enters as the act it blocks; on `PostToolUse`, `Notification`, `SubagentStart`,
  `SessionStart`, and `SessionEnd` nothing is prevented, so the message stays transient feedback and
  pairs as nothing. `SubagentStop` blocks but is subagent-scoped, so its act pairs inside the
  subagent rather than against a main-session surface.

  The hooks page is added to Sources and to the recheck triggers in both criteria files (catalog
  1.3.0 → 1.4.0, for the widened surface partition and I13 surface set); the per-event exit-2 table
  and the set of supported hook locations join the recheck triggers as newly load-bearing. Eval 14
  pins the admission on the case that exposed the gap: a `SessionStart` `type: "command"` handler
  injecting a standing behavioral block, against an active output style's format contract. Eval 15
  pins a project-scope frontmatter hook landing in the editable inventory rather than the read-only
  tier, and eval 16 pins a `PostToolUse` exit-2 handler producing no conflict against a `CLAUDE.md`
  that requires the tool it ran after.

## [0.16.0]

### Changed

- **`audit-instructions`: `conflict-criteria.md` gains two adjudication cautions on the mechanism
  escape hatch (criteria 1.0.0 → 1.1.0).** No must-not-flag case was added and `conflict-scan.sh` is
  unchanged. First: both tool-removal mechanisms — a bare-name `permissions.deny` rule and
  `disallowed-tools` — work by taking the tool out of Claude's pool, so recommending one against a
  skill whose text *requires* that tool leaves the mandate unsatisfiable rather than stricter; when
  the mandating side is a gate, the mechanism must land together with a rewrite of that side, and the
  pair is what gets recommended, never the rule alone. Second, and deliberately a caution rather than
  a drop rule: **availability-conditioning does not fail gate 5.** Rephrasing a mandate as "`X` when it
  is in the pool, otherwise ask inline" narrows how an act is performed, not whether — that is a subset
  of an always-resident prohibition's scope, not a disjoint condition, so the two still overlap
  wherever the tool is present and must-not-flag case 12 does not apply. Gate 3 then decides the pair
  on the rewritten text, testing the branch where the tool *is* present. Without this, a skill could
  neutralize a live Type A finding by appending a condition or softening a verb. The must-not-flag
  table gains a non-numbered row pointing at it, so a reader working the table finds it beside case 12.
  The permissions page is added to Sources and to the recheck triggers, since both cautions now rest
  on it.

### Fixed

- **`audit-instructions`: Worked Example 1's corpus counts were never reproducible from the method
  the example states (#1723).** It read "62 lines name the tool and 11 carry a
  `use_ask_user_question` opt-in gate on the same line, leaving 51 ungated". Measured with the
  example's own stated method — `plugins/**/*.md`, changelogs excluded — the figures are 69/11/58
  both at current `main` and at `049a4b9243`, the commit that shipped the doc, so this is a wrong
  measurement rather than drift; only the gated count, `11`, reproduces. Four plausible alternative
  denominators were tried and none reaches 62. The hardcoded figures are replaced by the two
  `git grep` commands that compute them, with `conflict-criteria.md` itself excluded from the pathspec
  — it names both tokens, including on the command lines, so an unexcluded measurement counts itself
  and drifts whenever the example is edited.

- **`audit-instructions`: Worked Example 1 no longer records a verdict on its own subject.** #1724
  changed the mandate side the example quotes. Rather than declare the pair closed, the example now
  shows the pre-fix state and its gate walkthrough, then states explicitly that **this file does not
  adjudicate the resulting pair** — the rewrite was authored in the same repository as these criteria,
  so a verdict here would be the author grading their own text, and the pair's operator-level half is
  an open question (now cited: #1722). It names two things not to assume while re-running the gates:
  that the pair dissolved because one side acquired a condition, and that a softened verb settles
  gate 3. It keeps what the history does establish — **no winner was named**, because the
  skill-body-versus-memory-surface authority relation the Unresolved table denies still does not
  exist, and a rewrite on one side is never the operator's decision.

- **`audit-instructions`: `conflict-scan.test.sh` Case 2's comment** no longer describes its fixture as
  the live worked example; the text it was drawn from is no longer in `repo-hygiene`. Comment only —
  no fixture, assertion, or scanner behavior changed, and the suite still passes 41/41.

## [0.15.0]

### Added

- **`audit-instructions`: Opus-5 model-delta rows in I8, and model scoping as a catalog axis**
  (criteria 1.2.0 → 1.3.0), from the dual-verified Opus 5 prompting-guide corpus. I8 gains three
  Opus-5-scoped rows: I8-a instructed self-check removal (classified by reviewer INDEPENDENCE —
  architected fresh-context or cross-vendor review is never a finding — with carve-out lanes for
  security review, destructive operations, managed-upstream-file changes, and PR merge gates);
  I8-b conservative-reporting detection, behavioral, with two criteria-owned fences
  (restraint-clause shape — the `code-tidying` tidyings "When NOT to apply" text is the canonical
  non-finding — and quoted/meta surfaces that discuss the pattern rather than instruct with it);
  I8-c don't-think / don't-reason directives. A new "Model scoping" section defines the semantics:
  single-model-sourced rows fire only when the run's resolved target model matches by exact
  equality of the normalized version token (point releases and dated IDs never auto-match a
  base-version scope), otherwise reported `skipped-for-target`; fleet-wide promotion only via the
  documented gate. I8's base row and I10 are annotated with their `fable-5` scope (single-model
  sources; gate unmet) — a deliberate coverage narrowing: on any non-`fable-5` target those two
  now report `skipped-for-target` instead of findings, until the promotion gate is met.
- **`audit-instructions`: `--target-model <version>` argument.** Default resolution ladder:
  explicit argument, else the session's effective model (launch overrides included, not the bare
  settings pin) normalized alias → version against live model-config docs; anything that cannot
  normalize to a single version — family alias (e.g. `opus` with a context-window suffix), absent
  `model` setting, custom/gateway deployment ID — aborts the run non-interactively with the exact
  argument to pass, instead of silently assuming the newest version. The report's
  tier-transparency line names the resolved target.
- **`audit-instructions`: report-header cost line** — checks run per surface, model-scoped rows
  skipped for the target, estimated per-surface token delta versus the prior catalog version, and
  confirmation that the run adds zero new interactive gates (report-only contract unchanged).
- **`instruction-scan.sh`: I8 candidate families with per-family ids** (`I8-a` instructed
  self-check, `I8-b` conservative-reporting, `I8-c` don't-think / don't-reason), with regression
  tests, curly-apostrophe (U+2019) coverage in the contraction patterns (also retrofitted to the
  pre-existing I6 tokens), and stem forms that catch inflections. Advisory over-production is
  unchanged and deliberate: restraint clauses, quoted/meta text, idioms, and substring near-misses
  are emitted as candidates; the fences live in criteria.md and are adjudicated by the model lane.

## [0.14.0]

### Added

- **"Scope of a Read deny" in `audit`'s `reference/required-permissions.md`.** The
  `sensitive-file-deny` table recommended `Read(./.env)` / `Read(./secrets/**)` /
  `Read(./.claude/settings.local.json)` with no statement of what a `Read` deny actually reaches, so a
  reader came away believing the file was protected. The new subsection splits covered from not
  covered against current official docs: the rule reaches the built-in file tools (Read, Grep, Glob,
  LSP), `@file` mentions, IDE selection context, Edit on the same path, **and the file commands Claude
  Code recognizes inside a Bash command such as `cat`, `head`, `tail`, and `sed`** — but *not* an
  arbitrary subprocess that opens the path itself, which is how a `python -c` or `node -e` one-liner
  reads a denied file with no deny firing. Remedies are ranked rather than listed: the sandbox
  (`sandbox.filesystem.denyRead`, `sandbox.credentials.files` with `"mode": "deny"`) is the documented
  OS-level enforcement path, carrying the platform limit that it does not run on native Windows; a
  `PreToolUse` hook on `Bash|PowerShell` is explicitly a speed bump, not a boundary, because it
  inspects the same evadable command string; and where no OS-level boundary exists the durable control
  is that the secret is not in a file the session's OS principal can read at all — directory location
  is explicitly named as *not* a boundary, since a subprocess opens absolute paths and relocation
  changes nothing about who can read the file. Enumerating shell readers as `Bash(cat *)`
  deny globs is named as a non-remedy, since upstream documents argument-constraining Bash patterns as
  fragile. Two facts are flagged unverified rather than asserted: whether PowerShell-tool reads
  (`Get-Content`, `type`) are covered at all, and the full membership of the recognized-command set,
  which upstream gives with "such as".
- **The sandbox's four escape surfaces, tabled alongside the recommendation.** `sandbox.enabled: true`
  on its own is not a boundary: `allowUnsandboxedCommands` lets a failing command be retried outside
  it, `failIfUnavailable` defaults to warning and running unsandboxed, `excludedCommands` runs listed
  commands outside and can always be appended to, and `filesystem.disabled` lifts the `denyRead` and
  `credentials.files` read protections outright. All four are open at their defaults, so an
  enabled-but-default sandbox is reported as partial — recommending it without them would repeat the
  defect this release fixes.
- **`check-structure.sh` now separates unreadable from malformed.** A `Read` deny merged into a
  sandbox boundary, or plain filesystem permissions, makes the script's `open()` fail; it previously
  surfaced as `Valid JSON: no` and failed the run, i.e. a false malformed-config finding. The script
  now reports `Present: yes` / `Readable: no` with a `not inspectable` note and exits cleanly, and
  both `SKILL.md` Phase 1 and `context/procedures.md` say that is a correct result to record rather
  than a reason to find another reader. Covered by a new test case that announces a skip where the
  platform does not enforce `chmod 000`.
- **Eval 7 on the `audit` skill (`read-deny-scope-not-overstated`).** Asks whether present deny
  patterns mean the secrets are protected; expects the scope split, the ranked remedies, and no
  `Bash(cat *)` enumeration.

### Changed

- **Category B now reports the secret-file Read denies with their scope.** `SKILL.md`'s "Required
  permission patterns" section routes the finding write-up through the new subsection, in both
  directions — a present baseline is not reported as proof the file is unreachable.
- **`context/procedures.md` no longer implies its own `settings.local.json` recipes escape the
  baseline deny.** It now states that the safety is in what gets emitted, not what gets opened:
  `check-structure.sh` reads the file from a subprocess and is safe because it emits counts only,
  while the supplemental `cat … | jq` recipes are blocked in a project carrying the recommended deny —
  correctly so. Routing around that block with an interpreter one-liner is prohibited; the audit
  reports the file as not inspectable under the project's own rule instead.
- **"Interaction with hook-based gates" now states the ordering in both directions.** "A deny rule
  fires before any `PreToolUse` hook" was true only of the loosening direction, and the two hook cases
  are now kept apart. A *returned decision* cannot loosen a rule: deny and ask rules are evaluated
  regardless of which decision the hook returns. *Exit 2* short-circuits instead: it stops the call
  before permission rules are evaluated at all, so it blocks past an allow rule and nothing downstream
  runs, including an otherwise-matching ask rule. The consequence for this baseline — a deny entry
  suppressing a project hook's ask escalation — is unchanged.

## [0.13.0]

### Added

- **A read-only inventory tier in `audit-instructions` Phase A.** I15 (shipped in 0.12.0) compares
  a *pair* of surfaces, so it has to read text no proposal may ever touch. Phase A now inventories
  three such tiers read-only rather than excluding them outright: org-managed policy (the managed
  `CLAUDE.md`, a `claudeMd` settings value, and managed prompt-type hook text), upstream-owned but
  live instruction text (skill bodies and agent definitions from an enabled plugin's cache, managed
  materializations, and `type: "prompt"` handler text in an enabled plugin's `hooks/hooks.json` —
  effective `enabledPlugins` gates all three alike, since a disabled plugin's cache stays on disk
  while none of its components load, and the selected install record, not merely an enabled plugin's
  presence in the cache, picks which version's directory is read), and every out-of-scope conflict
  counterpart. A scope argument narrows which side may *produce* a finding, never which surfaces are
  read, and the `Arguments` section now says so rather than describing the filter as narrowing the
  inventory. Read-only inventory changes no ownership: those surfaces still propose nothing and still
  route upstream. Prompt-hook text is extracted from `.claude/settings.local.json` and managed
  settings as well as project and user `settings.json`, prompt text only, never a command line or
  secret-bearing value.
- **A no-change representation in the `audit-instructions` report contract.** A finding whose check
  forbids proposing an edit — the I15 managed-policy case, anything routed to an owning repository —
  records `no change proposed` and who owns the resolution instead of a fenced diff, so the per-finding
  diff requirement no longer contradicts the checks that forbid an edit.
- **`audit-instructions` check I16 — definition-site locality.** An instruction governing one named
  thing while living somewhere other than that thing's own definition. A different axis from I3:
  I3 is load *timing*, I16 is *locality*, and an instruction can be correctly deferred and still
  misplaced. `OPINION`-tier, off by default, enabled by `--opinion`, capped at `info`, never applied.
  The destination is constrained to a surface Claude loads: where the subject's definition site is an
  ordinary README or reference file, the proposal colocates the text *and* retains a one-line pointer
  on a loaded surface, so a locality fix never silently drops the behavior the instruction enforced.
- **`audit-instructions` stopping condition on I6 and I8.** Neither carried an a-priori bound, so
  both trimmed without a floor. It withholds a proposal where the instruction guards a
  high-consequence area (safety gate, irreversible action, security boundary, external contract,
  genuine ordering) and reports every withholding. `OPINION`-tier but **enabled by default** with an
  explicit `--no-stopping-condition` opt-out, because it withholds rather than emits — defaulting a
  suppressor off would delete the only bound on two trimming checks.
- **`OPINION`-tier enablement policy in the catalog.** Emitting rules default off, `info`-capped,
  never fix-applied; withholding rules default on; `OPINION`-derived advice inside a backed check
  follows its host's enablement and is labelled inline. Every run reports how many `OPINION` checks
  were available, how many did not run, and the argument that enables them.
- **YAML frontmatter on `reference/criteria.md`** carrying `version` (1.2.0) and `last-updated`,
  replacing the body-prose version line — a contract surface with three parse paths now stamps its
  version machine-readably.

### Changed

- **`audit-instructions` I3 detection now names its real criterion — loaded more broadly than the
  content is relevant.** The old wording said "always-loaded surface", but none of the non-memory
  surfaces this check runs on are literally always loaded: a skill body or agent definition loads in
  full on every use of its component. The second detect case covers exactly that, and requires
  establishing the component's breadth first — a skill or agent that exists only for the content's
  concern loads it precisely when it is relevant and is not a finding.
- **`audit-instructions` I3 remediation now qualifies its destination and prices the move.** A
  destination qualifies only if it defers loading, so `@path` imports do not — a split into imports
  satisfied the check's letter while changing the load profile not at all. A finding must also state
  that a `paths:`-scoped rule or a nested `CLAUDE.md` is lost after compaction until a matching file
  is read again. A move into a **new** skill is priced too: the body defers, but the listing entry it
  adds — `name` plus the combined `description` and `when_to_use`, truncated at 1,536 characters — is
  always in context, so "move it to a skill" moves part of the cost into the always-loaded tier
  rather than out of it. A move into a skill that already exists adds no entry and is not charged.
  `disable-model-invocation: true` is the only field that keeps a description out of context, and it
  makes the skill user-invocable only; `skillOverrides` does not reach plugin skills. Stated as a
  cost on the recommendation, never as a budget threshold.
- **`audit-instructions` I9 remediation names the interface destination.** Where an example block
  exists to enumerate what a caller may pass, the finding names an argument enumeration, a
  frontmatter field, or a typed `argument-hint` instead. `OPINION`-derived, labelled as such in the
  finding, never fix-applied; the detection is unchanged and stays officially backed.
- **`Authority` gloss no longer asserts that every row is `ANTHROPIC-DOCS`.** The two
  `OPINION`-tier rules this release adds are the first that are not; the axis stays a closed
  three-value set.
- **I3 remediation refuses a `paths:`-scoped rule for content taken out of an agent definition.**
  Path-scoped content is invisible inside a subagent context, so that destination removed the
  instructions from every dispatch instead of deferring them. Agent-originated content now needs an
  agent-reachable destination — a skill the definition invokes, or text kept where it is.

### Fixed

- **The conflict pass resolves effective liveness before it pairs anything.** It received Phase A's
  filesystem inventory and treated presence in the tree as liveness, but liveness is a session
  property: the launch directory decides which ancestor `CLAUDE.md` files are candidates,
  `claudeMdExcludes` (merged across every settings layer) can kill one that is present, omitting
  `project` from `--setting-sources` skips project rules entirely, and `--add-dir` with
  `CLAUDE_CODE_ADDITIONAL_DIRECTORIES_CLAUDE_MD` adds live memory files the tree walk never sees.
  Uncorrected, the pass reported conflicts one side of which was dead and missed live counterparts
  it never inventoried — silently, and reproducibly only on the machine that produced them. Phase A
  now resolves those controls and reports them in the tier-transparency line; surfaces whose
  liveness an out-of-session inventory cannot determine are marked `liveness-unresolved` and their
  pairs are reported rather than graded.
- **A prompt hook enters the comparison set as the gate it imposes, never as its prose.** Per
  [hooks](https://code.claude.com/docs/en/hooks), a `type: "prompt"` handler sends its text to a
  separate Claude model for single-turn evaluation returning a yes/no decision — it is never
  injected into the main conversation. Comparing that raw prompt against a `CLAUDE.md`, skill, or
  output style manufactured conflicts between two models that satisfy their own instructions
  independently (an evaluator told to return JSON only against a main-session Markdown-output rule).
  The pass now compares the act the hook blocks, under its event and `matcher`. This also closes the
  `UNVERIFIED` residency row that told the reader to fetch the hooks page.
- **Auto memory and a plugin-supplied active output style join the read-only inventory.** Both are
  resident every session and neither was reachable: auto memory was excluded outright for routing,
  yet `conflict-criteria.md` assigns every pair involving it to I15 *because* `claude-memory`'s C6
  does not read `MEMORY.md` — so the pair was audited by neither skill. And the user- and
  project-scope output-style scans cannot reach the plugin cache, while a plugin style with
  `force-for-plugin` applies "automatically whenever the plugin is enabled, without requiring users
  to select it", overriding the user's `outputStyle`
  ([output-styles](https://code.claude.com/docs/en/output-styles)) — so the *active* style could be
  absent from the corpus entirely. Phase A now inventories the loaded part of `MEMORY.md` at the
  effective auto-memory location and the one style that resolves active, both read-only, with
  ownership and routing unchanged.
- **Auto memory's enabled state is resolved by precedence, not by any one scope.**
  `CLAUDE_CODE_DISABLE_AUTO_MEMORY` is authoritative wherever it is set (`=1` off, `=0` on, even
  against `autoMemoryEnabled: false`); with it unset, settings precedence (managed > local > project
  > user) decides, defaulting to on. Reading a lower-scope `false` as decisive would have dropped a
  `MEMORY.md` that a higher-precedence scope re-enabled. `/claude-memory:stateless` owns the
  resolver and reports the effective state, including a variable/setting disagreement.
- **An agent definition no longer pairs against the main conversation's auto memory.** The residency
  table listed `MEMORY.md` as resident every session and made every agent-definition pair guaranteed,
  but "the main conversation's auto memory isn't loaded into subagents; the exception is a fork"
  ([memory](https://code.claude.com/docs/en/memory)) — so those two never occupy one context and the
  pass was reporting conflicts between contexts that do not coexist. The row, the guaranteed-pairs
  set, and the co-residency prose now carry the exception, while keeping the two pairs that are real:
  a fork inherits the parent, and a subagent that enables its own `memory` field can contradict the
  definition it runs under.
- **The plugin-source known limit no longer contradicts the read-only tier.** It said Phase A "never
  reaches `plugins/`" and that agent-versus-memory pairs have no second side, which the new tier
  makes false for every *installed, enabled* plugin — two executable instructions disagreeing about
  whether the same data is available. The limit is narrowed to what is still true: a marketplace
  repository's `plugins/**` **authoring** tree is plugin source, not an installed plugin, and nothing
  there loads into the session being audited, so pairs drawn wholly from it (a skill's stated default
  against its own plugin README) still have no counterpart and stay with #1421. The
  tier-transparency line reports that narrower limit only — reporting installed-plugin surfaces as
  uncovered would understate the coverage the pass now has.
- **Auto memory is inventoried only when it is effectively on.** It is on by default, but
  `autoMemoryEnabled: false` at any settings scope or `CLAUDE_CODE_DISABLE_AUTO_MEMORY=1` turns it
  off, and a `MEMORY.md` left on disk from before is then neither loaded nor written. Phase A
  resolves that state before inventorying the file — the same gate the plugin-cache surfaces already
  carry, and for the same reason: pairing live instructions against text no session sees is a
  manufactured finding.
- **Eval 8 required naming a winner for a pair the precedence table calls unresolved.** It asked the
  run to "say which side to change" for a skill body against a `CLAUDE.md`, which
  `conflict-criteria.md` classifies as unresolved because the skills page states no authority
  relation between the two and "silence is not a winner". The eval now requires an `unresolved`
  verdict with both anchors quoted and the choice left to the operator, with the mechanism route
  offered as an option rather than a verdict.
- **Eval 7 required dropping a real contradiction when `claude-memory` is absent.** It expected the
  run to report memory-layer contradictions as unchecked and name the sibling skill, but
  `conflict-criteria.md`'s fallback contract keeps the pair as an I15 finding when that plugin is not
  installed. The routing exists to avoid two findings for one pair, not to lose the only one; the
  eval now requires the fallback.
- **Eval 13 required the wrong reason for refusing an agent-definition import split.** It rewarded
  saying that an `@path` in an agent definition loads at launch, which the catalog's own I13 says is
  false — `@` carries no import meaning outside the memory-layer surfaces, so the referenced file
  would not load at all. The eval now requires that explanation, which is what makes the split a
  silent removal rather than a failed saving.
- **`audit-permission-grants` no longer points outside the plugin root.** Both `SKILL.md` and
  `reference/criteria.md` reached the permission-rule-hygiene convention through a `../` relative
  link. An installed plugin runs from an isolated cache holding only the plugin's own tree, so the
  link normalized above the cache root and resolved to nothing — the skill directed a read that
  cannot succeed in installed form, while resolving fine in a full-repo checkout, which is why it
  survived. Both now point at the convention's published URL, the form sibling plugins already use
  for marketplace conventions. Nothing was copied into the plugin: the convention stays the single
  owner of the principle, the three anti-patterns, and the correct pattern. What a run actually needs
  was already in-plugin — each check's **Recommend** line — and both files now say so, so a report
  never depends on fetching anything.

## [0.12.0]

### Added

- **`audit-pass` skill** (`/claude-config:audit-pass`). One coordinated, ordered, resumable pass over
  a named target repository's instruction surface. It defines no criteria: every check is delegated
  to the plugin that owns it through a presence-gated namespaced invocation with a documented
  fallback, and nothing crosses a plugin boundary but that invocation. What it adds is the run
  semantics — a three-scope inventory (managed policy read-only, user scope routed as
  recommendations, project scope) taken before any check runs; an exclusion set derived at run time
  from the target's own shared-source registry, the `vendor/` layout rule, `git worktree list`, and
  the pass's own artifacts, never transcribed; content-derived finding identity; a constituent-keyed
  suppression record whose entries resolve through a four-way disposition table in which only an exact
  match is silent — a one-sided anchor change carries forward as `needs-reconfirmation`, a deeper
  change closes the old entry and opens the new finding, and every disappeared finding is accounted
  for as a fix, a successor, or an unexplained disappearance that fails the self-check, which is the
  detector the convergence property previously lacked; per-lane incremental persistence with resume;
  and one human gate per run. Liveness is read from two ground-truth sources — `InstructionsLoaded`
  for the memory layer and `/context` for Skills, Custom Agents, and MCP Tools — because either alone
  under-covers the surface set silently; `managed-settings.json`'s `claudeMd` key is observed by
  neither and is reported as a known gap. Read-only on bare invocation, mutation only behind `--fix`, and never an edit
  to managed policy or a user-scope file. `/doctor` is an operator handoff rather than a dispatch,
  because it is interactive; when its three-part prerequisite or v2.1.206 version floor is unmet the
  run names it as the missing capability and states what goes unchecked. Findings report in three
  tiers — derived (exact equality across runs), judged (a stability tolerance whose violation fails
  the run's self-check), delegated (no property) — and every run reports in one line how many
  `OPINION`-tier checks were available, were not run, and the argument that enables them. The
  determinism gate **measures its own precondition** rather than assuming it: HEAD and a **state
  digest** — every inventoried surface and every dirty path, each paired with the content hash of its
  current bytes — are captured at the **scan baseline** (Phase 1's inventory frozen, before any lane
  reads, since the digest spans that inventory and is not computable before it exists) and again at
  the **audit endpoint**, and a target that
  moved mid-run reports `indeterminate` rather than `passed`, with the properties marked not
  evaluated. Three things the naive form gets wrong, all closed here: a *count* holds still while an
  already-dirty file's contents change, so the digest pairs each path with its content; the digest
  spans **every inventoried scope**, because a `~/.claude/CLAUDE.md` edit moves what the lanes read
  while the target's HEAD and dirty set both hold still, and reporting that as a defect would be an
  accusation where an abstention is correct; and the endpoint is captured **before** Phase 5, so a
  `--fix` run's own accepted edits fall outside the measured read window instead of marking every
  successful mutating run `indeterminate`. The pass's own artifacts are excluded from the digest on
  the same list that excludes them from the scan, so a `--report-to` write does not invalidate the
  run's own gate. A checkout shared with concurrent sessions is the normal case for the first
  operator, and an unfalsifiable pass is worse than an honest indeterminate.
- **Finding-suppression convention** (`docs/conventions/finding-suppression/`). Owner doc for the
  suppression record `audit-pass` reads at `.claude/audit-pass.md`: entries store the finding's
  constituents — `check`, `claim`, and every `(surface, anchor)` site — under a derived `finding_id`
  key, with the constituents authoritative and a key that does not hash from its own body reported
  malformed. Also the required reason and date, per-key merge (never a closed list, which one personal
  entry would discard whole), the policy-floor precedence inversion where the team layer wins a
  conflict, and the five obligations on any consuming skill. Layering defers to the config-cascade
  contract.

### Changed

- **`setup` now covers a consumer-project configuration surface.** `audit-pass`'s tracked suppression
  record makes the plugin's previous "owns no consumer-project configuration" claim false, so `check`
  gains per-layer verification of the record (user-global INFO, team must be tracked, overlay must be
  gitignored) plus malformed-entry reporting, and `apply` gains its one write path.

## [0.11.0]

### Added

- **`audit-instructions` check I15 and Phase B2: cross-surface conflict pass.** Detects two
  instruction surfaces that both claim authority over one behavior and contradict each other — a unit
  of judgment the per-surface Phase B lanes are structurally blind to, since each lane sees only one
  half of a pair. The catalog row owns the definition, comparison set, `@path`/symlink resolution,
  `AGENTS.md` exclusion, remediation-by-scope and must-not-flag cases; Phase B2 answers it. The pass
  consumes Phase A's inventory rather than re-enumerating surfaces, and reads surfaces Phase A
  recorded as *skipped* (plugin-cache, managed materializations, org policy) as read-only conflict
  participants, since a contradiction is real whether or not this repo may edit either side.
- **`reference/conflict-criteria.md`.** The five gates a pair must clear (co-residency, same
  observable, opposed polarity, no arbitration, non-vacuous trigger overlap), three conflict types
  and their remediation routes, a residency table covering every surface Phase A inventories, a
  precedence table separating what the official docs settle from what they leave unresolved, a
  13-case must-not-flag set, and two worked examples. **Split-brain is not a fourth type**: two files
  where only one ever loads fails the co-residency gate by construction, so listing it as a conflict
  type would make it unreachable. It is reported separately as *orphaned instruction drift* — the
  state a contradiction grows out of, not a contradiction today.
- **A boundary against `claude-memory:audit`'s C6 consistency check drawn on C6's actual population,
  not on the name of the layer.** C6 discovers files project-relative (`find . -maxdepth 1` over
  `CLAUDE.md`/`CLAUDE.local.md`, plus `find .claude/rules`) and its check text names only those
  files. So only a pair with **both halves in root-level project** `CLAUDE.md` / `CLAUDE.local.md` /
  `.claude/rules/**` routes to C6. Any pair with a `~/.claude/` side, any pair involving auto-memory
  `MEMORY.md`, and any pair reaching a **nested** `CLAUDE.md` / `CLAUDE.local.md` stays with this
  pass — C6 discovers with `find . -maxdepth 1` and never reads the nested files, so routing those
  out on a layer label would have left them audited by neither skill.
- **`scripts/conflict-scan.sh` + tests.** Advisory deterministic pre-scan emitting
  `fileA:lineA|fileB:lineB|entity|flags` candidate pairs, always exit 0, matching the existing
  `instruction-scan.sh` contract. An entity is a CamelCase identifier anywhere **or a single
  capitalized word inside backticks** — the second form is what reaches single-word tools (`Bash`,
  `Read`, `Edit`), and requiring the backticks is what keeps sentence-initial capitalized words out.
  Neither form is a hardcoded tool list, so a tool the scan has never heard of is still covered.
  Polarity is read from a window around each mention and **both halves of that window stop at a
  sentence boundary**, so only a polarity token in the entity's own sentence classifies it:
  `X must not be used` is a prohibition, a trailing clause past a full stop is not, and a prohibition
  in the *preceding* sentence no longer overrides the mandate that governs the entity. A boundary is
  a sentence-ending mark followed by a space — a bare mark also occurs inside a dotted config path or
  a version number — or a contrastive conjunction with or without a preceding comma, so "always use
  `Read` but never use `Bash`" classifies each entity on its own clause rather than sharing one
  polarity. `while` still requires its comma, being temporal as often as contrastive. An
  opt-in gate suppresses a pair only when it reads as a **condition** rather than as the subject, so
  "never use `X` for opt-in prompts" is still classified. Classification and pairing run in a single
  `awk` pass bucketed by entity; a subprocess per mention did not finish on an instruction tree this
  size.
- **`conflicts` scope argument.** Runs Phase A plus Phase B2 only, so a scheduled hygiene routine can
  compose the conflict check on its own token budget without paying for the full audit.

### Changed

- `audit-instructions` reports conflicts as **pairs** in their own report subsection — both
  `path:line` anchors, both claims quoted verbatim, and either a doc-cited precedence winner or an
  explicit `unresolved`. The skill never picks a winner the official docs do not state.

## [0.10.0]

### Added

- **`audit-instructions` checks I12–I14**, extending the existing `reference/criteria.md` catalog
  rather than standing up a second one. Each row carries its must-not-flag cases, and the three new
  official sources (CLI reference, subagents, skills) join the catalog's source list.
- **I12 — stale or misattributed harness-capability claim.** The subject is the product, not the
  model, which separates it from I8. Detection needs an official page stating something incompatible
  with the claim, or a failed reproduction — and each arm is bounded so the check cannot manufacture
  findings. **Documentation silence is not drift**: pages are rewritten and condensed, and this
  repository keeps empirical tests for behaviors the docs never specified. **A reproduction must
  match every stated precondition** — version, OS, setting, account tier, feature flag, launch mode —
  and a failure without them is inconclusive rather than a finding.
- **I13 — prose written on the assumption that an `@path` imported**, on a surface where `@` carries
  no import meaning. The finding is the false premise, not the citation form: an inert `@path` is
  still a legible path, so "follow `@reference/rules.md`" works and flagging it would report a
  working instruction. Remediation rewrites the assertion into an explicit read, because swapping the
  syntax alone leaves the claim false — no citation form imports anything on these surfaces.
- **I14 — an instruction to read a surface the main conversation already loads at startup.** Bounded
  to the root `CLAUDE.md`, the user `CLAUDE.md` at the **resolved** `${CLAUDE_CONFIG_DIR:-~/.claude}`,
  the root `CLAUDE.local.md`, unconditional project rules and managed policy files. Nested
  `CLAUDE.md` and `CLAUDE.local.md` files and path-scoped rules load lazily and are exempt, as is any
  read where **the file is the operation's subject** — the startup copy is a launch-time snapshot, so

### Changed

- **Recheck triggers now watch every page in the catalog's source list**, not the three originally
  named. Each check cites one of those pages, so a subset left the new harness-behavior rows
  depending on pages nothing watched.
- **The surface partition no longer widens a row.** It said the full catalog applies on non-memory
  surfaces while I13 and I14 declare narrower surface sets, so a lane could emit I14 findings on
  prompt-type hooks and output styles the criterion excludes. Each row's own declaration bounds it.
- **The `description` carries the new checks' trigger vocabulary.** It framed the skill purely as
  finding instructions the model no longer needs, and only the description is available during skill
  selection — so a request about a stale harness claim, a non-loading `@path`, or a redundant
  startup-surface read would not have selected the catalog that answers it.
- **`Authority` gloss restated descriptively.** The axis is a closed three-value set, not a rule
  that every row is `ANTHROPIC-DOCS` — `TALK` and `OPINION` stay reachable, and the two
  `OPINION`-tier rules this release adds are the first to use one.

## [0.9.3]

### Added

- **`setup` evals.** The skill shipped none, against the repo's own rule that a skill carrying
  behavioral warrants demonstrates them. Four cases cover the behaviors its SKILL.md asserts and
  nothing else: a bare invocation routes to `check` and writes nothing; a missing `curl` FAILs
  scoped to `check-plugin-drift.sh` alone rather than downgrading the rest of the audit surface;
  an install request under `apply` yields platform instructions without executing a package
  manager, and never reports a prerequisite resolved on an install command's exit code; and an
  audit request under `setup` routes to the audit skills by name instead of being performed.

## [0.9.2]

### Changed

- Fresh-eyes delegation sites now prefer a cross-vendor advisor when one is installed
  (e.g. the OpenAI Codex plugin, invoked per its own docs), with the fresh-context same-vendor
  subagent as the stated fallback — presence-gated per the seam-phrasing convention.

## [0.9.1]

### Added

- **`audit-instructions` eval: `step-list-culled-not-preserved`.** Exercises check I8's
  step-list nuance: a mechanical numbered procedure is culled to intent plus hard constraints
  (genuine ordering, safety gates, external contracts kept) rather than preserved verbatim.
  Absorbed from the superseded `audit-model-fit` suite (its C2 analog), per the follow-up
  material recorded when 0.9.0 removed that skill.

## [0.9.0]

### Added

- **`audit-instructions` skill** (`/claude-config:audit-instructions`). A read-only audit of the
  locally-owned Claude Code instruction surfaces — user + project `CLAUDE.md`, `.claude/rules`,
  skill bodies, agent definitions, prompt-type hooks, output styles — for instructions current
  models no longer need: prior-model workarounds, over-prescriptive scaffolding, bare prohibitions,
  reasoning-echo directives, and approach-pinning example blocks. It ships an eleven-check catalog
  (`reference/criteria.md`) cited to current official prompting doctrine, tiers every finding
  mechanical vs behavioral, and packages proposed removals/rewrites as human-gated diffs — never
  auto-applied. An advisory grep-only scanner (`scripts/instruction-scan.sh`) seeds the mechanical
  tier. It partitions with `claude-memory`'s `audit` skill: on memory-layer surfaces it runs only
  the model-era checks and routes hygiene findings there; on non-memory surfaces the full catalog
  applies. Upstream-owned plugin-cache and managed-materialization findings route to the owning
  repository rather than being edited in place.

### Fixed

- Corrected stale `claude-memory` skill-name references (`health` → its current name `audit`)
  across the plugin's skills and README — the `audit`, `audit-automation-gaps`, and
  `audit-permission-grants` route-out notes and the README's instruction-layer and migration
  sections. The `claude-memory` memory-layer skill was renamed `health` → `audit`; the old
  `/claude-memory:health` invocation no longer resolves.

### Removed

- **`audit-model-fit` skill superseded by `audit-instructions`.** Both audits answer the same
  question — locally-owned instruction surfaces vs current model capability — and repo doctrine
  admits only one skill per question. `audit-instructions` carries the fuller catalog (eleven checks
  I1–I11 with authority tags and evidence tiers), the `claude-memory` hygiene partition, and the
  adversarial fresh-context verify pass, so it strictly covers `audit-model-fit`'s four checks and
  supersedes it. Both were built concurrently from the same underlying issue (#800); `audit-model-fit`
  (added in 0.8.0 below) is removed here.

## [0.8.1]

### Changed

- Skills with `!` dynamic-context injections now declare `shell: bash` explicitly, per
  the pinned precompute convention — bash-only pipelines must not fall through to a
  PowerShell host.

## [0.8.0]

### Added

- **`audit-model-fit` skill** (`/claude-config:audit-model-fit`). A fourth audit that sweeps the local
  Claude Code instruction surfaces — user + project `CLAUDE.md`, skill `SKILL.md` bodies + context
  files, agent definitions, `.claude/rules/**`, prompt-type hooks and output styles — for deterministic
  constraints that hobble newer, more capable models, and proposes removals/rewrites. Check catalog:
  bare prohibitions with no rationale (rewrite to add the *why*, never blanket-delete), over-prescriptive
  step lists (cull to intent + hard constraints), over-constraining example blocks (trim toward the
  recommended 3–5, not a blanket ban), and stale model-era workarounds — each measured against "would
  removing this cause Claude to make mistakes?". A bundled `instruction-surface-scan.sh` enumerates the
  surfaces and flags the two grep-able smells as candidates; the judgment stays in the skill body.
  **Report-only and human-gated**: it presents findings plus proposed diffs and never edits any
  instruction file itself (no `--fix`). Findings inside `melodic-software/standards`-managed
  materializations route upstream per the sync-manifest rather than being edited in place. Composes with
  (distinct intents, pointers only) `claude-memory:audit` (instruction-layer *health*, same surfaces),
  `skill-quality:check` (structure), `docs-hygiene:compress` (token brevity), and the sibling `audit`
  (config-file correctness). The plugin `description` now reads "Four audit skills".

## [0.7.1]

### Changed

- Documentation-only: the License section now states the plugin's own MIT
  license inline and no longer points at a `LICENSE` file at the repository
  root, which an installed consumer running from the isolated plugin cache
  cannot reach. No behavior change.

## [0.7.0]

### Changed

- **BREAKING — two skills renamed to the `audit-*` naming grammar** (fleet conformance wave, naming
  grammar): `automation-gaps` → `audit-automation-gaps` (`/claude-config:automation-gaps` →
  `/claude-config:audit-automation-gaps`) and `permission-hygiene` → `audit-permission-grants`
  (`/claude-config:permission-hygiene` → `/claude-config:audit-permission-grants`). The old
  invocations stop resolving; update any saved references. The `audit` skill is unchanged.

## [0.6.0]

### Added

- **`setup` skill on the uniform contract** (`/claude-config:setup`). Closes the doctrine-tracked
  setup gap: the plugin's audit scripts require external CLIs (`jq` for all three skills, `curl` for
  the plugin-drift check) but no setup shipped. `check` (default, read-only) probes `jq`/`curl`/the
  bash shell against the bundled scripts as source of truth and reports PASS/FAIL/INFO — `jq` missing
  is a plugin-wide FAIL, `curl` missing a scoped FAIL for the drift check only. `apply` gives platform
  install guidance and re-verifies; it installs no system package and writes nothing. README
  Requirements now names the bash/Git-Bash shell prerequisite alongside `jq`/`curl`.

## [0.5.0]

### Changed

- Renamed the plugin `claude-config-audit` → `claude-config`. Reinstall as
  `claude-config@melodic-software` and update any `/claude-config-audit:*` invocations to the
  `/claude-config:*` namespace.
- Renamed the `settings-audit` skill → `audit` (`/claude-config:audit`) and the
  `automation-deep-dive` skill → `automation-gaps` (`/claude-config:automation-gaps`).
  `permission-hygiene` keeps its name (now `/claude-config:permission-hygiene`).

### Removed

- Extracted the `memory-health` skill into the new standalone `claude-memory` plugin, where it ships as
  the `health` skill (`/claude-memory:health`). Install `claude-memory@melodic-software` for the
  instruction/memory-layer audit.

## [0.4.0]

### Added

- "Pre-computed context" blocks in the `automation-deep-dive`, `memory-health`, and `settings-audit`
  skills: `!`-executed commands inject live repo facts (automation inventory; memory/rules/CLAUDE.md
  counts and the RD1/M2 script-backed check counts; installed Claude Code version) at skill load, so
  each audit starts from guaranteed-fresh evidence instead of relying on the model to remember to run
  the bundled scripts. Every command carries an `|| echo` fallback so skill load never hard-fails.
  No `allowed-tools` self-grant ships with the blocks: a `Bash(bash <path>*)` grant is the
  interpreter-led P1 shape this plugin's own `permission-hygiene` criteria flag (auto mode drops it),
  and `!`-execution does not route through `allowed-tools`.
