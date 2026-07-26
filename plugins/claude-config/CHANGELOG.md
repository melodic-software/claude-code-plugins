# Changelog

All notable changes to the `claude-config` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

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
