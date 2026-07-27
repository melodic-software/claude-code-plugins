# Changelog

All notable changes to the `planning` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.27.0]

### Added

- **`draft-goal-condition` drafts conditions for goals no metric can measure (#1652).** Step 2
  assumed a checkable condition already existed, so an intent with no honest metric either got a
  manufactured one or nothing. A new branch builds the condition from three moves instead — a
  structural constraint, enumerated required contents, and a self-verification sub-step that
  requires the verifying work rather than its verdict. The branch states why the third move must be
  worded that way: the evaluator calls no tools, so it can only credit verification Claude performed
  in the transcript, and an assertion that checking happened is indistinguishable from the checking.
  Co-drafting a still-vague intent points at `/planning:interview` rather than restating it.
- **`draft-goal-condition`'s Step 0 router gains the dynamic-workflows lever (#1654).** The router
  offered `/loop`, routines and `/schedule`, a Stop hook, and a one-shot prompt as alternatives to
  `/goal`, leaving work that needs more agents than one conversation can coordinate with nowhere to
  route. Two caveats ship with the row, each because it turns a plausible recommendation into a dead
  one. The `ultracode` keyword runs one task as a workflow, changes nothing else, and is honored
  only from a human-typed prompt, whereas `/effort ultracode` is the standing session setting
  (`xhigh` effort plus per-task workflow planning) and needs a model offering `xhigh` — so the two
  are not interchangeable. And the `Workflow` tool is filtered out of every non-fork subagent, so a
  lever whose work lands in dispatched non-fork subagents — the loop lanes' item-workers, for
  instance — cannot be this one however well it otherwise fits. The row also carries the
  availability fact that keeps it from being skipped as
  preview-gated: all paid plans, switched on from the `/config` **Dynamic workflows** row on Pro.

## [0.26.3]

### Fixed

- **Headless reconfigure recipe now preserves install scope (#1406).** The `claude plugin
  uninstall` → `claude plugin install ... --config` recipe in `skills/setup/SKILL.md` defaulted
  both halves to `-s user`. When this plugin is installed at `project` or `local` scope, that
  silently uninstalled a separate user-scope record while the effective project/local install kept
  loading, and the reinstall landed at a scope that does not load. Both commands now carry
  `-s <scope>`, sourced from what `claude plugin list` reports for this plugin — the same fix
  already applied to `session-flow` and `rate-limit-guard` in #1393.

## [0.26.2]

### Fixed

- **`interview`'s `recommends-session-config` eval no longer only covers the
  downstream-execution-session framing.** The single eval asserted config for
  "the downstream execution session" for every case, so a general/terminal
  session — which has no downstream consumer and should be told to configure the
  current/next session, applied now — could still pass on the stale
  downstream-only framing. Split into two cases: eval 9
  (`recommends-session-config-engineering-downstream`) keeps the downstream
  framing, now explicitly scoped to the engineering/handoff path, and new eval 10
  (`recommends-session-config-general-current-session`) asserts the current/next
  session framing for a general/terminal decision — including the 0.26.1 timing
  contract: an early first read right after the Step 1 survey classifies the
  domain as general, the stop-boundary recommendation as a refresh of it, and
  the offer to re-evaluate the reached understanding when config was raised
  only at the end. Covers the skill-side reframe that landed in 0.26.1.

## [0.26.1]

### Fixed

- **`interview`'s session-config guidance no longer reads as a runtime imperative to
  a nonexistent downstream session.** The mid-task "raise the model/effort" rule was
  phrased as an instruction to an executing actor, but `/interview` terminates at
  handoff and never wires that context into whatever session executes next — it is
  now framed as a watch-for the interview hands the **user** at handoff. Separately,
  the recommendation's header framed itself as configuring "the downstream execution
  session," which the "Both domains" section then extended to general sessions even
  though a general session is terminal with no downstream consumer (SKILL.md Step 5).
  General/terminal sessions now frame the recommendation as config for the
  current/next session, applied now; the "Both domains" scope is unchanged. The
  handoff checklist's Step 5 is aligned to the same split.
- **`interview`'s general-session config recommendation now lands early enough to
  act on.** With the current/next-session framing, a recommendation first emitted at
  the stop boundary arrives after the work it was derived from is complete — the
  general session is terminal, so applying `/model`, effort, or `/advisor` there
  cannot improve the reached understanding. General/terminal sessions now surface a
  first read right after the Step 1 survey classifies the domain as general (when
  survey signals warrant a change), refresh it at the stop boundary, and — when the
  config was raised only at the end — offer to re-evaluate the reached understanding
  under the raised config. Engineering timing is unchanged: the downstream execution
  session has not started yet, so the stop/handoff boundary remains early enough.

## [0.26.0]

### Changed

- **`draft-goal-condition` is now reachable from lever-selection intent.** Its
  Step 0 was already the lever-fit router across `/goal`, `/loop`, routines and
  `/schedule`, a Stop hook, and a one-shot prompt, but the description sold only
  the drafting half, so "which of these should I use" never reached it. The
  description now leads with the routing and carries five lever-selection
  triggers (`'which loop should I use'`, `'/goal or /loop'`,
  `'should this be a routine'`, `'pick the right autonomy lever'`,
  `'what kind of loop is this'`). Every pre-existing trigger phrase is
  preserved, and the rewrite also switches the trigger list to the `Use when:`
  form the authoring gate expects, clearing a standing warning.

### Fixed

- **`draft-goal-condition` no longer restates the `/goal` condition shape it
  tells itself never to hardcode.** Step 2 enumerated a four-part shape and
  Step 3's tightening rule named those parts, while the skill's own gotcha
  forbids baking the shape into this file — and the restatement had already
  drifted: the live page prescribes three elements and treats the turn/time
  clause separately. Both steps now defer to the shape Step 1 reads off the live
  page.

## [0.25.0]

### Added

- **`audit-answers` — independent adversarial validation of a completed
  `/planning:interview`'s answers.** It runs over any filled ledger, whether the
  human hand-answered the rounds or the recommendations were auto-accepted. When
  open branches remain it accepts each one's recommended answer to fill them
  first (holding the mechanical never-auto floor — `USER-RESERVED` deferred
  questions and the interview's auto-guard class always route to the human), then
  dispatches **1–3 fresh-context (non-fork) validator subagents** that re-examine
  each answer with its **rationale withheld** (audit the decision, not the pitch)
  and return a per-answer verdict
  — **CONFIRMED / CHALLENGED / RECLASSIFIED-TO-HUMAN** — plus shaky
  dependency-chain flags. Triaged confirm: CONFIRMED answers collapse to one
  line; CHALLENGED and RECLASSIFIED answers become real questions in the
  `/planning:interview` round format, and the human confirmation round is
  mandatory. It **validates, never derives** — subagent-invented answers are out
  of scope (fresh-context independence is real only for checking an answer, not
  producing one). The adversarial evidence discipline is `devils-advocate`'s,
  cited rather than duplicated; the dispatch and per-answer verdict contract are
  purpose-built because the input (a pre-enumerated ledger) and output
  (per-answer verdicts fed back as interview questions) differ from
  `devils-advocate`'s plan-artifact stress-test. `/planning:interview` gains one
  Composition-table row pointing at it (#1043).

## [0.24.5]

### Changed

- **`interview` round-format legibility levers.** The round-header restate now
  doubles as a **session-hop anchor** that re-grounds a resumed reader before any
  question; per-question context is capped at one line and used only when the
  header restate doesn't reach the question or the session just resumed after a
  gap. The `My recommendation:` line is the **single verdict marker** — no
  stacked standalone `(RECOMMENDED)` badge, no repeated tag in the Alternatives
  list. Session-local shorthand is now defined once at first use and parked in
  the ledger's **shorthand glossary** (ephemeral session vocabulary, distinct
  from the project's ubiquitous language). A dense round can be offered as an
  **HTML decision-table artifact** rendering the whole frontier
  (question / recommendation / alternatives / deciding-what, rows numbered to the
  terminal `Q<N>`, answers still returned by number, degrading to a fenced
  markdown table) — a rendering surface, never a round split or question cap.
  `AskUserQuestion` guidance sharpened to simple selections / binary confirms
  only. Guidance-only; no new skill, action, or config (#1042).

## [0.24.4]

### Changed

- Fresh-eyes delegation sites in `plan` (Step 3 plan-reviewer dispatch) and `devils-advocate`
  (fresh-context requirement) now prefer a cross-vendor advisor when one is installed (e.g. the OpenAI Codex plugin, invoked per its own docs), with the fresh-context
  same-vendor sub-agent as the stated fallback — presence-gated per the seam-phrasing convention.

## [0.24.3]

### Changed

- `devils-advocate` plan-review mode now routes incumbency-driven assumptions to the
  `incumbent` mode instead of leaving them as prose. When Round 2's evidence check finds
  an assumption whose *only* support is that the status quo already uses the thing
  ("we already use X"), the resulting finding's Mitigation names the follow-up —
  `/planning:devils-advocate incumbent <target>`, the Alternatives Sweep on that
  incumbent. Suggestion only: it is never auto-run, so scope stays one mode per
  invocation. An assumption also backed by a requirement, benchmark, or doc is verified
  on that evidence and does not trigger the routing.

## [0.24.2]

### Changed

- Skills with `!` dynamic-context injections now declare `shell: bash` explicitly, per
  the pinned precompute convention — bash-only pipelines must not fall through to a
  PowerShell host.

## [0.24.1]

### Changed

- `devils-advocate` names the seam with `/re-anchor:pick-for-the-problem` (light
  in-session nudge vs this formal, dispatched, verdict-producing review before a
  plan commits) and documents the leading-depth-token order with a usage example
  (`deep incumbent <target>`; `incumbent deep <target>` folds the token into the
  target).

## [0.24.0]

### Added

- **`devils-advocate` gains an `incumbent` mode — adversarial review of the status
  quo.** Alongside stress-testing a plan you hand it, the skill can now turn the same
  discipline on an **incumbent** tool, library, or approach already in place:
  `/planning:devils-advocate incumbent <target>`. A new **Alternatives Sweep** replaces
  the assumption-driven rounds — it explores the incumbent first-hand (a fresh
  sub-agent runs `/discovery:explore`, never trusting a parent digest), names the
  problem the incumbent actually solves, surveys alternatives on the
  native > official > vetted-third-party ladder with coupling priced, and reaches a
  **KEEP / MIGRATE / RESEARCH** verdict. It inherits the skill's evidence mandate (no
  training-data-only findings) and routes load-bearing evaluations to
  `/discovery:research` (`/re-anchor:pick-for-the-problem` supplies the full selection
  discipline when installed). Research depth is a per-invocation `deep` / `shallow`
  token, defaulting to the existing risk-scaled behavior. Scope is pre-implementation
  decision support — keep-or-replace before a plan commits — not a post-hoc audit of a
  running system. Additive; plan-review mode is unchanged.

## [0.23.1]

### Changed

- **`plan` Step 2 no longer re-derives design inline.** The design-default axes
  walk and build-technique selection edged into `/planning:design` territory,
  contradicting the skill's own "consume design artifacts — do not re-derive
  design inline" rule. The design-default checklist is now framed as an **audit
  against the plan** (confirming the plan carries design's resolved
  configurability / extension-point / observability / testability threads and
  type-collaboration shape, owned by `design`'s "Design defaults") rather than a
  fresh derivation — matching `design-handoff`'s existing "walks its
  design-default checklist against the plan" handoff language. Magic-literal
  hygiene stays plan's own review check. Build-technique selection now routes
  design / viability / raw-feasibility uncertainty **upstream** (`/planning:design`
  or a `/prototype:pressure-test` spike) and has plan consume the outcome,
  keeping only the kept-slice integration sequencing as plan's own call.
  Documentation-only; no behavior change (#265).

## [0.23.0]

### Added

- **`interview` recommends the downstream session's model, effort, and advisor.**
  The interview already reads task complexity and ambiguity to drive its rounds; at
  the stop/handoff boundary it now turns that read into a recommendation for how the
  execution session should be configured — a **model tier** (capability: raise when
  the assistant would be confidently wrong despite full context) and an **effort
  level** (thoroughness: raise when it would under-explore or under-verify) picked per
  the official distinction, plus the **advisor** pairing when the main model is a
  faster tier (a faster main without a stronger advisor is not the recommended config
  for non-trivial work). The current model names, tiers, and accepted pairings are
  read **live** from the official docs each run and never pinned in the skill (the
  durable distinction is stable; the names drift) — mirroring `draft-goal-condition`'s
  live-doc discipline. A doc-fetch failure **degrades, never halts**: it falls back to
  the durable distinction with a visible note rather than guessing a model name. The
  recommendation is advisory (applied via `/model`, `/advisor`, the effort setting),
  fires for engineering and general sessions alike, and carries an inverse mid-task
  direction (surface "too complex for the current model/effort" when execution
  warrants). Detail in the new `skills/interview/context/session-config.md` (#231).

## [0.22.3]

### Changed

- Documentation-only: the License section now states the plugin's own MIT
  license inline and no longer points at a `LICENSE` file at the repository
  root, which an installed consumer running from the isolated plugin cache
  cannot reach. No behavior change.

## [0.22.2]

### Changed

- Cited `/testing:plan`'s test-type classification table as the single source of
  truth for which test type a given change needs (unit / integration / e2e /
  architecture / analyzer). The `plan` skill's Step 2 test-strategy guidance (and its
  `plan-template.md`) and the `design` skill's test-seam posture thread now point at
  that table instead of letting a competing test-type take grow in each site. Pointer
  only; no restated table, no behavior change (#264).

## [0.22.1]

### Changed

- Broadened the `interview` skill's "Facts are yours; decisions are the user's"
  discipline: the environment an agent resolves facts from is not only the working
  tree. When a task NAMES an external repo or resource — a sibling checkout under a
  known repo root / workspace layout, or an `owner/repo` reachable through its host —
  that is a resolvable fact too, so the agent checks the filesystem layout and queries
  the repo host directly before defaulting to a user question. Kept as a cue, not a
  mandate. Guidance only; no behavior change.

## [0.22.0]

### Added

- **New skill `draft-goal-condition`** — crafts a paste-ready `/goal` completion
  condition from a stated intent. It reads the **current** official `/goal` docs
  live for the condition shape and character limit (nothing is hardcoded, so the
  skill does not rot when the documented contract changes between Claude Code
  versions), gates the draft to the doc's transcript-demonstrable effective-condition
  shape, and — because a model cannot reliably count characters — proves the draft
  fits the limit with a deterministic counter rather than estimation. Includes a
  lever-fit gate (step 0) that routes interval-shaped work to `/loop` and
  cloud/sessionless work to routines/`/schedule` instead of authoring a goal.
- **New plugin-root script `scripts/goal-condition-length.sh`** (with companion
  `goal-condition-length.test.sh`) — a mechanical, model-free character-length
  gate. The limit is passed in by the caller (read live from the docs), never
  baked into the script; exit `0` within limit, `1` over, `2` usage/env error.

## [0.21.2]

### Added

- Named the **underspecification**/**underspecified** concept — a task missing the
  constraints needed to act safely — in the planning-pipeline skills that already
  cover it: `interview` (description trigger keywords + Purpose, as the pipeline's
  underspecification resolver), `prd` (routing an underspecified engineering task to
  `/interview`), and `design` (Purpose, naming the concept its underspecified-types
  gap-finding instantiates). Vocabulary only; no behavior change.

## [0.21.1]

### Changed

- Cross-plugin invocation tokens updated for the fleet naming-grammar wave
  (`/domain-driven-design:curate-language`, `/prototype:pressure-test`,
  `/prototype:explore-directions`); behavior unchanged.

## [0.21.0]

### Changed

- **`domain-driven-design` dependency downgraded to presence-gated
  collaboration** (fleet conformance wave: native `dependencies` are reserved
  for plugins genuinely broken without their collaborator, and every planning
  skill works standalone). The manifest entry is removed — the plugin no
  longer auto-installs; every `/domain-driven-design:curate-language`
  invocation site now carries the installed-ness gate and a stated fallback
  (terms recorded in the design artifacts / Brief glossary notes).

## [0.20.0]

### Changed

- **`setup` split onto the uniform check/apply contract.** `check` inspects both concerns read-only —
  the topic-docs seam (`.claude/topic-docs.yaml` effective values — absent is INFO, since the documented
  defaults apply — schema parse validity, the committed-tier `git check-ignore` conflict, and the
  deferred `gitbook` vault backend) and the standards index presence at `<standards_dir>/README.md`
  (absent is INFO; a behind-version index reports a DIRECTIONAL delta) — and reports a PASS/FAIL/INFO
  table; `apply` runs the two-concern resolve-and-persist flow, then re-runs `check` to verify. The
  topic-docs resolution, the standards-contract bootstrap (implemented by reference), and the conflict
  guard are unchanged; the read-only inspection path and the `check | apply` argument-hint are new.
  `check` also reports the effective `use_ask_user_question` toggle, and `apply` carries the
  `--config` fresh-install-only reconfigure guidance for it.

## [0.19.0]

### Added

- **New `/planning:questionnaire` skill** (user-invoked only): turns a decision another person
  holds into a Markdown discovery questionnaire delivered async. It interviews the user about the
  *send* only — recipient's role/expertise/relationship, and what the user needs back — never
  about the subject the recipient holds, then writes questions aimed at that knowledge gap to the
  topic's memory slice (default `.work/`; the self-ignoring memory tier keeps recipient names out
  of git history) and reports the path. Delivery is out-of-band; an optional
  "awaiting answer" work item goes through the work-item-tracker seam when one is bound and is
  skipped gracefully otherwise. This is the third routing bucket beside `/planning:interview`'s
  facts-vs-decisions split (a person-arbitered deferral); the interview-side pull-out reference
  lands separately. Adapted from Matt Pocock's `to-questionnaire` (no live upstream sync path —
  re-audit opportunistically). Ships with four evals covering the send-only contract, the
  never-quiz-the-subject guardrail, self-answerable routing back to `/planning:interview`, and
  tracker-absent graceful degrade.

### Changed

- Planning README: the interview row's stale "depth-first Q&A" phrasing now says frontier-rounds.

## [0.18.0]

### Changed

- **Frontier-rounds cadence propagated to sibling skills** (`/planning:prd` Step 4, `/planning:design`
  collaborative stance, `/planning:plan` scope-clarity check and confidence-gate interview
  round): each asks every settled-prerequisite question as one numbered round with recommendations,
  dependent questions waiting on their prerequisites — replacing the one-question-at-a-time cadence
  the interview skill dropped in 0.13.0. `/planning:brainstorm`'s single intake question is
  intentionally unchanged.
- Siblings now render a round via `AskUserQuestion` only through the same `use_ask_user_question`
  user config the interview skill reads (on, and ≤4 independent questions) instead of deciding
  prose-vs-card inline.
- The interview-round description in `/planning:plan` is stated once in
  `context/tag-decisions.md`; the SKILL.md confidence-gate summary no longer duplicates it.

## [0.17.0]

### Changed

- Adopt topic-docs contract 2.0.0 (visibility semantics): `reference/topic-docs.md` records that
  baselines are checkout-local and `PLAN.md` carries distilled values only;
  `/planning:plan`'s baseline step no longer directs `PLAN.md` to reference the stored
  memory-slice capture (pointer discipline — the path is invisible outside the writing checkout).
- `/planning:wayfind` map-issue Notes carry durable pointers only (PRs, committed docs, prior
  items, external links); memory-tier artifact content is distilled inline instead of pointed at —
  tracker issues are durable surfaces under the contract's pointer discipline.

## [0.16.0]

### Added

- **Proactive standards grounding in `/planning:plan`**: Step 2 opens with a "Ground in
  consumer standards" formulation input that resolves the consumer's standards index through the
  new `reference/standards-contract.md` binding (synced from the marketplace's standards
  convention), matches task surfaces against the index's Applies-when clues, selectively loads
  only non-ambient matched sections, and cites what it loaded in the plan's new "Standards
  grounding" template element. Grounding depth rides the existing plan-scale table — trivial and
  small plans skip it. The plan reviewer gains a matching standards-citation axis.
- **Standards bootstrap in `/planning:setup`**: a second setup concern implements the binding's
  normative Setup-and-migration section — idempotent index bootstrap with a conforming-index
  short-circuit, row-path validation, directional version-delta migration, and a setup-owned
  `<standards_dir>/.gitignore` for personal overlays. The ignore-file prohibition is scoped
  accordingly: setup never edits an ignore file it did not itself create.
- **Tripwire test** `tests/standards-binding.test.sh` guards the load-bearing grounding markers
  (heading placement, binding references, ladder-pointer discipline) against future prose edits.

## [0.15.0]

### Changed

- **BREAKING: `/planning:domain-modeling` moved out of this plugin** — it now lives in the new
  `domain-driven-design` plugin as `/domain-driven-design:curate-language`. The skill maintains
  vocabulary only and explicitly refuses bounded-context discovery, so "domain-modeling"
  over-promised; the concern is DDD language stewardship, not planning-stage task shaping. Invokers
  of `/planning:domain-modeling` must switch to the new command.
- **Declared a dependency on `domain-driven-design`**, so installing `planning` auto-installs the
  glossary steward and the pipeline's inline vocabulary updates (`interview`, `design`) keep working
  cross-plugin.

## [0.14.0]

### Changed

- **BREAKING: `/planning:architect` is renamed `/planning:plan`** (skill directory, frontmatter
  `name`, and every in-repo reference). The `architect` name was a pre-migration shadow-compromise:
  before plugins, a flat local skill named `plan` would have collided with surfaces already using
  that word, so the skill shipped under `architect`. Plugin namespacing removed that constraint —
  `/planning:plan` is unambiguous and says what the skill produces. Claude Code's built-in `/plan`
  (the plan-mode toggle) is unaffected: plugin skills have no bare command form, so the full
  invocation is always `/planning:plan`. Consumers invoking `/planning:architect` must switch to
  `/planning:plan`; no `renames`-map entry is provided (clean break while the marketplace settles).
  "architect this" remains a trigger phrase in the skill description.

## [0.13.0]

### Changed

- **`/planning:interview` asks in frontier rounds instead of one question at a time** (behavioral
  change): each round asks every question whose prerequisites are settled as one numbered set, each
  with a recommendation; the answers recompute the frontier, and dependent questions wait for the
  round after their prerequisite resolves. A frontier of one question degenerates to the previous
  behavior. Partial replies resolve only what was answered — unanswered questions re-surface next
  round, and accept-shorthands ("accept all recommendations", "yes to Q5–Q7") are honored. Adapted
  from Matt Pocock's batch-grill-me rounds model.
- The `me`-mode canonical framing now splits facts from decisions: facts are resolved from the
  environment (with non-blocking sub-agent dispatch for slow lookups — only downstream questions
  wait), and decisions always go to the user; the blanket "explore the environment instead of
  asking" clause is gone.
- The stop condition gains an explicit confirmation gate for `me`/`auto`: an empty frontier is not
  sufficient — the user confirms the restated shared understanding before the contract persists.
  `lock` is exempt (invoking it is the confirmation).

### Added

- `use_ask_user_question` user config (boolean, default `false`): opt in to rendering a round of
  up to 4 independent questions through the `AskUserQuestion` tool; inline prose stays the default
  and remains the fallback for larger or dependency-carrying rounds.
- Question-budget guidance: upstream artifacts (research, exploration, PRD, design) count as
  settled prerequisites, and a ballooning frontier routes to `/planning:wayfind` instead of a
  marathon session. No numeric question cap.

## [0.12.0]

### Changed

- **`/planning:wayfind` label taxonomy follows the colon-space axis grammar**: the typed decision-item
  labels are now `wayfind: research|interview|design|prototype|task` (previously `wayfind:research`
  etc.), so label-as-code owners with a `prefix: value` naming grammar can declare the taxonomy
  verbatim instead of carrying a grammar exception. `work-map` and `needs-human` stay flat
  (grammar-exempt). Frontier queries and the bootstrap presence check match the new names. Maps
  charted under the old names need a one-time label rename before `work` mode can route them.

## [0.11.1]

### Fixed

- **GitBook remains non-writable throughout planning close-out**: `/planning:architect` and the
  topic-docs binding now route `vault_backend: gitbook` to the in-repo `docs` promotion path without
  invoking GitBook API/MCP or Git Sync writes. `/planning:setup` reports the deferred, non-writable
  status whenever the effective value is `gitbook` — preserved from an existing file, inferred from
  the repo's own conventions, or chosen during the interview — instead of implying that any of those
  paths enables a writer.
- **`/planning:architect` Action Router recognizes `close-out`**: the PR-time close-out procedure was
  documented but unreachable through the router, so `close-out` fell through to full planning instead
  of running the close-out steps. The router now routes it directly, and the eval that exercises the
  GitBook-deferral close-out path is reachable again.

## [0.11.0]

### Added

- Added `/planning:domain-modeling`, the active owner for committed project-glossary changes:
  discovery-first consumer format/location resolution, canonical terms plus rejected synonyms,
  tight what-it-IS definitions, purity/admission guards, and routing among already-known bounded
  contexts. It deliberately does not discover bounded contexts or create speculative empty files.

### Changed

- `/planning:interview` and `/planning:design` now invoke the domain-modeling owner when vocabulary
  resolves instead of maintaining parallel glossary disciplines.

## [0.10.1]

### Changed

- Synced sibling-skill invocation routes to the reorganized plugin taxonomy across
  `architect`, `brainstorm`, and `devils-advocate`: `/tdd:tdd` is now
  `/tdd:principles`; `/implementation:verify-improvement` is now
  `/verification:measure`; `/implementation:verify-changes` is now
  `/verification:confirm`; `/improve-architecture:improve-architecture` is now
  `/architecture:improve`; `/work-items:work-items` is now `/work-items:track`.

## [0.10.0]

### Added

- **ADR admission test at `/planning:architect` close-out**: a decision graduates as an ADR only
  when ALL three hold — hard to reverse, surprising without context, the result of a real
  trade-off; ADRs stay minimal (title + a few sentences, optional sections only when they earn
  their place), and the ADR is preferably written the moment the decision crystallizes rather
  than batched at graduation.
- **Durability-over-precision authoring rule in `/planning:prd`**: PRD content describes
  interfaces, types, and behavioural contracts — never file paths or line numbers — and never
  assumes the current implementation structure persists.
- **Test-seam posture thread in `/planning:design` Phase 2**: sketch the seams the feature will
  be tested at — prefer existing seams, place new ones as high as possible, drive toward the
  fewest (ideal: one) — and confirm the sketch with the user before design output is finalized.
  `/planning:prd` gains a one-line pointer routing test-seam sketching to `/planning:design`.
- **Non-goals graduation edge in `/planning:prd`**: a permanent, deliberate rejection (not a
  deferral) graduates to the consuming repo's rejected-concept ledger at
  `docs/out-of-scope/<concept>.md` — one file per concept, accreting a "Prior requests" log — so
  repeat proposals get answered by the ledger; consumer convention with graceful degrade (create
  lazily; plain Non-goals suffice when no ledger exists).
- **Committed project-glossary format** (`skills/design/context/project-glossary.md`): one term
  per entry, 1–2 sentence what-it-IS definition, an `Avoid:` line pinning rejected synonyms,
  project-context terms only, lazy creation at the repo root (or per-context with a root map
  file), updated the moment a term resolves. `/planning:design`'s type-modeling and terminology
  guidance now writes through it.
- **Re-read-before-write discipline for multi-turn shared artifacts**: `/planning:architect`
  (PLAN.md) and `/planning:design` (design-threads.md and peers) re-read the artifact from disk
  before every write — another turn or agent may have modified it — and prefer appending or
  refining over wholesale rewrites.

## [0.9.0]

### Added

- **Agent-team composition guidance in `/planning:architect` Step 4.5**: design for an agent team
  when parallel-safe workers must message each other (vs independent fan-out sub-agents);
  decompose by context boundary / disjoint clean-interface file-set, never by lifecycle role;
  dependency-order the task list so blocked tasks auto-unblock; teammates are not
  worktree-isolated, so disjoint file ownership is mandatory. The Step 4.5 routing enum regains
  the agent-team surface.

### Changed

- **Baseline capture routes to the measurement SSOT**: `/planning:architect` Step 2 routes to
  `/implementation:verify-improvement` (`performance baseline` / `metrics baseline`) when
  installed instead of restating the measure/store/compare mechanism inline; manual capture
  remains the degrade path.
- **`/planning:devils-advocate` follow-ups regain the verification pointer**: suggests
  `/implementation:verify-changes` (if installed) when code changes were involved.

## [0.8.0]

### Changed

- **Migrate to the topic-docs convention** (`docs/conventions/topic-docs/`, v1.0.0). Artifacts now
  split by document nature across two tiers sharing one topic slug: contract documents — `PRD.md`,
  `PLAN.md` (Brief + Plan), and ALL of `design/` including the `design-threads.md` /
  `design-resolution.md` gate files — land in `docs/topics/<topic-slug>/`, committed on the task
  branch and pruned before merge; working memory — `interview-checklist.md`,
  `architect-checklist.md`, `baselines/`, resume notes — lands in the never-committed,
  self-ignoring `.work/<topic-slug>/`. `contract_tier: local` keeps contract kinds in the memory
  tier for solo/offline work. Every pipeline skill resolves placement by citing the plugin's
  **deltas-only** binding `reference/topic-docs.md` — its artifact/tier table and the vault-seam
  close-out pointer; the contract owns the resolution order, slug spec, and runtime guards
  (self-ignore is verified on the session's first memory-tier write, scoped to the resolved
  memory root).
- **`/planning:setup` now writes the tracked concern file** `.claude/topic-docs.yaml`
  (offering and preserving every schema key — `contract_dir`, `memory_dir`, `contract_tier`,
  `vault_backend`; shape per the convention's `topic-docs.schema.json`) instead of the
  `notes_dir` userConfig. It runs the committed-tier `git check-ignore -v` conflict check before
  writing — only when the chosen tier is `branch` (local mode has no committed tier to guard) —
  and never edits the consumer's root `.gitignore`.
- **`/planning:architect` owns the contract-slice close-out**: at PR time the approved PLAN.md is
  pasted into the PR description inside a `<details>` block; durable outcomes graduate through the
  knowledge-vault seam by resolving the concern file's `vault_backend` (`docs` default: guarded,
  history-preserving `git mv` into `docs/adr/` / `docs/specs/`; other values name a
  consumer-documented backend, degrading to `docs` when its tools are absent); a final commit
  prunes `docs/topics/<topic-slug>/` leaving context pointers.
- **Baselines are memory-tier**: the architect's baseline-capture step stores raw, machine-bound
  captures under `.work/<topic-slug>/baselines/`; PLAN.md records the distilled baseline, target,
  and comparison — never the raw output.
- **`/planning:brainstorm` opt-in persistence** targets the memory tier
  (`.work/<topic-slug>/brainstorm.md`), never the contract slice.
- **`/planning:wayfind`** cites the convention's memory tier and slug spec for its
  `.work/<slug>/` execution artifacts (alignment only — the map stays tracker-native).

### Removed

- **`history.md`** — every instruction that appended dated scope-change / pivot / restart notes to
  a sibling `history.md` is gone. Scope changes now append a dated note to the relevant section of
  the artifact itself, and the commit message carries the pivot rationale — contracts are
  branch-tracked, so git log is the history.

- **`notes_dir` userConfig and the `.claude/notes/` layout** — retired outright. No compatibility
  layer, no dual-read window, no migration tooling; move residual content manually.
