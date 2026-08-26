# Changelog — session-flow plugin

## [0.34.8]

### Changed

- **Long files carry a `## Contents` index.** The 438-line plugin README and the 442-line
  reference/structure.md gained Contents sections, including the handoff document's own body
  sections as lookup targets. Purely additive. Progressive-disclosure audit, missing-toc
  treatment.

## [0.34.7]

### Changed

- **`retro`'s ecosystem-improvement catalog points at the hook-events docs instead of copying them.** The ~25-row Hook Events table (a capability list the official docs own, and one that grows faster than a copy can track) is replaced by a pointer to <https://code.claude.com/docs/en/hooks>. From the repo-wide derivability/point-dont-copy audit (PR #3387).

## [0.34.6]

### Changed

- **Long reference files carry a `## Contents` index.** 2 reference files in this plugin gained one.

  The predicate is `audit-progressive-disclosure`'s own: a reference file over 300 lines with no
  table of contents, which both official sources agree on by that length. Scope came from the
  detector's tier classification rather than a line count, so `SKILL.md` files are excluded by
  construction: they are invocation tier, not the on-demand reference tier the rule names. Files
  with fewer than five H2s were held out, because a three-row index on a long file earns nothing and
  the doctrine offers a grep recipe instead. Purely additive, with anchors generated from each
  file's own headings and verified to resolve. Docs-hygiene sweep, L2-progressive-disclosure.

## [0.34.5]

### Changed

- **`retro`'s ecosystem improvement catalog is linked from `SKILL.md` with its read condition.** It
  was reachable only from `context/session.md`, which put it two levels from the hub. The
  `context/session.md` pointer is unchanged. Docs-hygiene sweep, L2-progressive-disclosure.

## [0.34.4]

### Changed

- **`find-handoff`'s recovery ladder keeps its spine and moves two rungs to spokes.** Rungs 1 and
  3 were 230 of the body's 486 lines and are attempted in order, so a run that resolves at rung 1
  never executes rung 3's grep machinery and a run that reaches rung 3 has finished with rung 1's
  glob rules. Each rung now has its own file under `skills/find-handoff/reference/`, cited from a
  ladder that still reads end to end. Rungs 2, 4, 5, and 6 stay in the body: rung 2 is seven lines
  and rungs 4 to 6 are the confirmation gate and the handoff every path reaches. Docs-hygiene
  sweep, L2-progressive-disclosure.

## [0.34.3]

### Changed

- **The README's opening sentence splits in two.** 86 words carrying seven appositives before the
  reader reached a verb they could act on. The `fourteen skills` count is unchanged. Docs-hygiene
  sweep, L8-write-for-humans.

## [0.34.2]

### Changed

- **Options-reference regeneration.** `scripts/sync-plugin-options-docs.py` dropped the
  phrase `in order to` from its shared options template, per the repo's own
  write-for-humans style rule that the phrase is just `to`. The generated options
  block in `README.md` regenerated with the shorter wording; no other change.

## [0.34.1]

### Changed

- **Behavior-preserving simplification pass (repo-wide batch-simplify).** keep-going:
  `check-usage-limit-reset.py`'s nested day-rollback conditional flattened (equivalent by
  construction, both branches else-less; a 553k-case brute-force sweep over reset strings,
  zones, and DST-transition days found zero mismatches) and a misleading `owner_id` local
  renamed `getuid`; its test file splits a mislabeled assertion into its own test (13 tests).
  retro: `parse_transcript.py`'s two byte-identical emit-and-exit branches fold into
  `_emit_multi_and_exit()`; a test reuses the existing `_run_script` helper. running-retro:
  `arm_observer.py`'s function-body imports hoisted to module level. Suites green
  (13 + 37 + 72); every change AST-diff-verified.

## [0.34.0]

### Added

- **Conversation-export suggestions (export-session-flow Brief, #3355).** Three skills now
  suggest the built-in `/export` command at their natural decision points, closing the one
  durability gap the artifact layer leaves open: the conversation itself, whose transcript is
  retention-swept (`cleanupPeriodDays`, default 30 days) and has no durable home. `clean-stop`
  names the conversation as a machine-local item in its durability sweep (with an off-machine
  caveat, since the export destination dies with the disk too); `handoff` offers the export on
  its prompt-only path, where the transcript is the handoff's only record; `retro` offers it
  after the chain-coverage report, since a session worth retrospecting is worth keeping. All
  three suggestions are presence-gated per the native-references convention (never asserting
  the command exists), name the shared destination `<memory_dir>/exports/<TS>-<topic>.txt`
  (now a reserved concern directory in the topic-docs convention, 2.5.2), require the memory
  root's self-ignore guard before the path is offered, and are offer-only: nothing invokes
  `/export` (built-ins are user-invoked and the command has no headless form) and nothing
  records whether the user ran it. Overlap verdict for the referenced native surface:
  `docs/native-surfaces/records.json` (`export` × `session-flow:clean-stop`, complementary).

## [0.33.0]

### Added

- **`orchestrate`: SendMessage worker-continuation guidance (#3341 follow-on decision, topic
  `list-agents-send-message-plugin-fit`).** The priming addendum now names `SendMessage` as the
  mechanism behind imperative 4's worker reuse and mid-flight intervention, presence-gated on the
  tool resolving in the session, with the three operative caveats (completed workers auto-resume,
  user-stopped workers refuse, re-invoking the dispatch tool spawns a second worker instead of
  resuming). Export modes still omit the addendum, so the pasted brief stays tool-agnostic. Backing
  quotes, version floors (v2.1.191/v2.1.199), the derived deny-rule caveat, and a same-day
  empirical probe (two completed subagents resumed by agent ID in a cloud session) land in
  `context/sources.md` under "SendMessage worker continuation", verified 2026-08-24 against the
  sub-agents and cross-session-messaging pages with the standard recheck triggers.

### Fixed

- **`reference/observer.md`: corrected the SendMessage gating claim.** The findings-return channel
  previously said reaching a still-running session is "gated behind experimental agent-teams",
  which conflated two surfaces: cross-session messaging is its own feature (v2.1.224+, native
  Windows v2.1.234+; per the page, once a session meets the requirements it is "on with nothing
  to enable"), and only structured team-protocol messages require agent teams. The bullet now quotes and stamps the availability sentence
  (verified 2026-08-24) and keeps the design decision unchanged on its surviving grounds: consent,
  next-tool-round delivery latency, and the durable ledger as the crash-safe primary.

## [0.32.6]

### Changed

- **Instruction-surface de-slop (#2891, shard 2).** Rewrote this plugin's `README.md` and every
  `SKILL.md` to drop em dashes under the repo's zero-tolerance house policy, using
  `/ai-slop:audit fix` semantics: periods or commas, or a restructured sentence, never
  parentheses, en dashes, or a spaced hyphen as a stand-in. Meaning stays; only the mark
  and the sentence break change. The generated options block is ignore-fenced because
  `scripts/sync-plugin-options-docs.py` still emits em dashes from its shared template.
  Protocol strings that producers emit or consumers match (`Re-arm <i> of <n> — <L> lines:`,
  the fenced `ORCHESTRATION BRIEF` title, the workflow glance map) stay as written; the
  detector declines fenced and inline-code spans.

## [0.32.5]

### Changed

- **setup:** normalized restated setup-contract prose (preamble, probe-ladder
  opening, never-writes boundary, and/or headless-reconfigure recipe as present) to the
  canonical fleet wording, keeping the operable text inline with a provenance-only citation
  (whole-repo extract-ssot batch, #2698).
- Normalized fleet-wide framing this plugin restates (cross-vendor advisor
  fallback, untrusted-content posture, attribution/idiom prose — as touched) to the canonical
  SSOT wording, operable text kept inline with provenance-only citations (#2698).

## [0.32.4]

### Fixed

- **`setup` skill:** the headless reconfiguration route no longer prescribes `claude plugin
  uninstall` + reinstall. That instruction rested on an unversioned claim that `claude plugin
  install --config` is ignored once a plugin is installed, and following it dropped the plugin's
  whole stored `pluginConfigs` entry, resetting every declared option to its manifest default.
  On Claude Code 2.1.240 a plain `claude plugin install … --config` against an already-installed
  plugin prints `already installed` and still writes the value, so that is now the documented
  route — stamped with the CLI version it was verified against
  ([#3111](https://github.com/melodic-software/claude-code-plugins/issues/3111)). `apply` also
  now separates the write from its effect: the stored value changes immediately, but the running
  session's hooks keep the `CLAUDE_PLUGIN_OPTION_*` they were handed at session start, so
  verification means rerunning `check` in a FRESH session — a same-session rerun reports the old
  value, which is not a failed write. It never asserts an unobserved change.
- **Docs:** the generated options block's headless route no longer implies `--config` applies
  only at install time, and now carries the CLI version its claim was verified against
  ([#3111](https://github.com/melodic-software/claude-code-plugins/issues/3111)). The block also
  now separates the write from its effect: the value is stored immediately, but hooks are handed
  their `CLAUDE_PLUGIN_OPTION_*` at session start, so a check run in the same session still
  reports the old value and that is not a failed write. Two upstream links that pointed at empty
  backward-compatibility anchors on the settings page were repointed at the headings that hold
  the content.

## [0.32.3]

### Changed

- **Handoff instruction walk compressed (#3018).** `docs-hygiene:compress` over the three files
  loaded at `/session-flow:handoff` invocation — `reference/save-point.md`,
  `reference/structure.md`, and `skills/handoff/SKILL.md` — dropping flavor (articles, filler,
  hedging, verbose verbs) and leaving every load-bearing contract intact: the `find-handoff`
  detection signals (rails, `` `/clear`, then copy everything between the dashed lines ``,
  `Read @…-handoff-…` directive, `Re-arm <i> of <n> — <L> lines:` length-delimited entries), the
  redaction rules (git-remote-URL userinfo strip vs shape markers), rooted-path / `Handoff origin:`
  rationale, and both-path original-goal / claim-provenance / purpose rules. Measured
  `LC_ALL=C.UTF-8 wc -c` against the pre-compress snapshots: save-point **40831 → 40679** (152 B,
  0.37%), structure **23296 → 23269** (27 B, 0.12%), SKILL **19641 → 19632** (9 B, 0.05%) — **188 B
  total, 0.22%**. Line counts are essentially unchanged (one wrap-only extra line on save-point).
  The walk was already author-time-disciplined; remaining yield sits under the compress skill's
  2–3% always-loaded bound. Shipped under the issue's explicit `--force` (named-file compress of
  this walk), not as a claim that the files were verbose.

  **Stop-hook escalation re-reviewed; still deferred.** 0.26.1 recorded a lightweight Stop-hook
  validator (`last_assistant_message` regex for the detection-contract signals, PostToolUse
  skill-ran marker, one bounded block, fail-open, hook-budget README share, sibling contract test)
  as the next step *if the rails prompt goes missing again after that reorder*. This pass found no
  remaining instruction defect that would cause a rails-drop: STOP still ends the underlying task
  and never the response before the prompt is on screen; the emit box is still never satisfied by
  writing the file; output order is still panel → checklist → rails-last. The original deferral
  grounds still hold — a single observed occurrence, file-mode recovery via `find-handoff` rung 1,
  and a false-positive block that lands at the degraded occupancy the skill runs under — and a
  0.22% flavor cut does not change occupancy enough to flip them. No hook shipped.

## [0.32.2]

### Fixed

- **`running-retro` and `retro` routed a skill candidate to a surface that cannot take one.**
  0.32.0 had both skills "hand an accepted candidate to `/playbooks:skill-authoring`" and hand the
  shape over rather than drafting one inline — but that skill takes no arguments and performs no
  actions: it is a knowledge surface. Handing it a candidate resolves to nothing, so the
  destination 0.32.0 set out to give a candidate did not exist. Both now say to read it for the
  doctrine and draft against it, still gated on `/skill-quality:check` and still presence-gated
  with the recorded-but-no-authoring-route fallback. The reason for not drafting ad hoc is
  unchanged and now attaches to the right mechanism: the playbook carries the conventions a
  retro-tail draft is most likely to miss.

  **0.32.1's Skill-tool phrasing is kept, not reverted.** That release respelled
  `retro/context/session.md`'s route as an explicit Skill-tool invocation and deliberately left
  `running-retro`'s list alone, because that list sits under "Offer routing — never auto-apply".
  The two changes compose: 0.32.1 fixed how the invocation is spelled, this one fixes what the
  invocation was claimed to do. `session.md` therefore still names the Skill tool — it invokes the
  skill to *read* it — while `running-retro` keeps its offer-shaped wording, so the asymmetry
  0.32.1 argued for survives.

## [0.32.1]

### Changed

- **Cross-skill chains name the Skill tool (#3002).** `find-handoff`'s deliberate-save-point
  hand-off to `/session-flow:keep-going`; `handoff`'s route to the
  `/session-flow:continue-in-background` sibling; `keep-going`'s two hand-backs to
  `/session-flow:handoff`; `reanchor`'s two hand-offs to `/session-flow:keep-going`;
  `show-options`' durable-state probe route to `/session-flow:orient`;
  `workflow/context/spec-first.md`'s mid-stage `/session-flow:handoff` escape hatch;
  `retro/context/session.md`'s skill-candidate hand-off to `/playbooks:skill-authoring`;
  `workflow/context/steps.md`'s phase-boundary save-point.
  `running-retro`'s routing list is untouched — its section is titled
  "Offer routing — never auto-apply", and so is `workflow/context/wrap-up.md`, whose table
  column is literally "Suggest" under a heading that says to *suggest* these before the user
  leaves. Wording only.

## [0.32.0]

### Added

- **`running-retro` and `retro`: a new-skill candidate now has somewhere to go.** Both skills are
  required to produce skill candidates — `running-retro`'s checkpoint block ends with a
  "New-skill candidates" line, and `retro`'s skill-candidate analysis is marked REQUIRED — and
  neither named a destination. `running-retro` offered exactly three routes (codify, tracker,
  nothing), none of them authoring; `retro` gave a recommendation format and stopped. A candidate
  with no destination is a finding that evaporates between sessions.

  Both now hand an accepted candidate to `/playbooks:skill-authoring`, gated on
  `/skill-quality:check`, presence-gated with the stated fallback of recording it and saying there
  is no authoring route here. Both also say to hand the shape over rather than drafting one inline:
  a skill written ad hoc at the end of a retro is the one most likely to miss the conventions the
  authoring surface exists to carry.

  Absorbed from an upstream cursor/plugins skill (`docs/upstream/cursor-pstack.md`, the `reflect`
  section), whose contribution here is routing an accepted learning by edit size. An adversarial
  audit of the plan widened the fix: the plan had scoped it to `running-retro` on the reasoning that
  `retro`'s five dimensions are closed, which is a non-sequitur — `retro` closes its *scoring*
  dimensions, not the improvement analysis that produces the candidates.

## [0.31.0]

### Changed

- **`show-options` is model-invoked (#3024).** It landed a day after course lane 8's fleet grade,
  so the rubric's table never covered it and its `true` sat un-attributed to any exception class.
  Graded now against `docs/conventions/invocation-mode/README.md`, none of the three fits: the
  Spotlight ledger is incidental bookkeeping rather than a side effect whose timing must be a
  human's, the skill is a one-shot render rather than a persistent mode-entry, and — unlike
  `discipline:wait-what`, the class-(i) skill it most resembles — its trigger is *uttered*
  ("what are my options", "what am I forgetting"), not a state only the human can detect. It is
  also not the rubric's rejected router, which routes **the agent** to hidden skills: this one
  renders a menu and does not execute the pick, and `claude-ops:inventory` (itself model-invoked)
  and `docs/SKILL-CHEAT-SHEET.md` already name the hidden set to a human from model-reachable
  surfaces. The flip was gated on re-checking ADR 0016's latent rationale for shipping V1
  manual-only, and it does not hold it — see that ADR's two revision notes.

  Unlike the prior flip (`planning:questionnaire`, #2969), **no trigger-phrase work was needed**:
  this description was written with real phrases from the start, so the flip makes phrases that
  already existed reachable rather than adding any. What the `true` cost was that a human saying
  "what are my options" out loud reached nothing, and that `workflow`'s boundary paragraph pointed
  the model at a target the invocation-reach invariant made unreachable. Both are now paid.

- **`workflow`'s description routes the option-menu ask to `show-options`.** The reciprocal
  amendment ADR 0016 made — `workflow`'s "never present both" governs **stage** routing and cedes
  option surfacing — lived only in `workflow`'s body, which is loaded *after* description matching
  has already picked a skill. With `show-options` now model-invoked, the two are matched against
  the same user text, and "what comes next" sits one phrasing away from "what should I run next".
  The disambiguation therefore has to be in the description to fire at all, so it is: `workflow`
  now names `show-options` as the owner of the ranked menu. Behavior at every other trigger is
  unchanged.

## [0.30.0]

### Changed

- **`workflow`'s pre-PR sequence cites an owner doc for its order, and its override-boundary
  paragraph is corrected (closes #3047).** `pre-pr.md` declared its step order "fixed plugin
  identity … there is no seam to reorder it," while a sibling plugin in the same fleet was
  reordering it at the handoff point: `implementation:implement`'s completion step, titled *"Hand
  off to the pre-PR sequence,"* prescribed outcome verification **before** review, where this
  sequence puts review at step 2 and outcome verification at step 7. That made the
  no-seam claim inaccurate as written, whichever order won.

  The order is unchanged — it was right. Outcome verification renders on the code that ships, and
  steps 4–6 (simplify, review the simplify diff, re-test) mutate the diff between review and
  verification; a verdict rendered before them describes code that no longer exists by step 8. The
  competing reading ("confirm it works before spending review effort") is already served earlier,
  by step 1 and by the caller's own build check and test pass.

  What changed is **who owns the order**: `docs/conventions/pre-pr-ordering/` now does, with a
  registry row in `PLUGIN-PHILOSOPHY.md`. The registry's own trigger — a new cross-plugin
  convention lands in an owner doc *before a second plugin adopts it* — had already fired. This
  file keeps ownership of what each step does and cites the owner for the order, and the
  override-boundary paragraph now says the order is **fleet identity rather than this plugin's
  identity**: a sibling prescribing a different order at a handoff is a defect against that
  convention, not a permitted local variation. Consumer gates, commands, and review criteria are
  honored exactly as before.

## [0.29.0]

### Added

- **Save-point engine — a "You are here" position panel for the operator.** Both save-point skills
  produced exactly two things a human could see: a ticked enforcement checklist, which is the
  skill's own audit trail, and the rails resume prompt, which is a block to copy. Everything that
  answers "what did we do, where are we, what is next" was computed and then filed into the handoff
  document — whose stated reader is a session with no prior context (`reference/structure.md`) — so
  the operator never read it. On the prompt-only path there is no file at all, and the recap existed
  nowhere. At the moment the human is deciding whether this is a sane place to stop and whether the
  work is still pointed where they wanted it, the skill showed them a compliance checklist.

  **The panel renders state that was already established.** A new engine section, "Emit the position
  panel", owns it once for both citing skills: a vertical rail with one line per unit, the current
  position marked in the gutter, a completeness read, and three one-line blocks (done this session /
  where we are / up next). It restates what "Locate the position first" and the sections above
  already produced — it triggers no read the save-point did not already need, which is the line
  between it and `orient`'s on-demand durable + off-thread sweep.

  **The count is of completed units only.** An in-progress unit counts against the total, never
  toward it — rounding the current unit up reports work as landed while the operator is looking at
  the line saying it is not, and it is the one arithmetic a progress read is most tempted into.

  **Units are resolved from the work, not assumed.** A first-match ladder takes workflow-checklist
  stages, then plan/spec/PRD phases, then an issue chain, then live `TaskList` items (full path
  only, where they are already fetched; prompt-only skips that rung, since "no non-trivial task
  list to reconstitute" is one of the criteria that selects prompt-only, and makes the one call
  when that path was forced), then
  completion criteria — so the panel reads differently on differently-shaped work. Work with none of
  those gets the three prose blocks and explicitly no rail: inventing phases to have something to
  draw produces a map of a plan that does not exist, which the operator would then resume against.

  **The rail is vertical because a horizontal one wraps.** One unit per line, one line per block,
  never a continuation line. A `→`-chained row wraps at whatever width the terminal happens to be,
  and the wrap orphans the position marker from the unit it marks — destroying the single thing the
  panel exists to show. Above 8 units the middle elides to a `… N more` line, keeping the ends and
  the current position; the whole panel is capped at 16 lines.

  **It cannot become a reason to lose the rails prompt.** The one observed failure of this engine is
  a turn that ends before the prompt reaches the screen, and the panel is new text standing between
  the start of the response and that prompt. So the caps are load-bearing, an uncertain panel
  degrades to one abbreviated line rather than growing, and the engine states outright that the
  panel never gates the rails. `handoff` fixes its order as panel → checklist → rails, keeping the
  rails-last rule intact; `continue-in-background` emits panel → rails → launch and passes the agent
  exactly the text between the rails, never a line of the panel.

  Not a detection-contract change: the panel sits above every keyed signal and outside the copy
  region, so `find-handoff` recovers exactly what it recovered before and needs no edit. Four evals
  join the two suites, grading the shape — vertical rail, elision above 8 units, prose fallback with
  no invented units, and the agent payload staying panel-free — rather than mere presence.

## [0.28.0]

### Added

- **`workflow` — eval coverage for the continuation router (refs #2972, AI Hero course lane 2
  #2900, decision Q23).** The router had zero eval coverage: five cases existed and none exercised
  the `continue` path, while one of its ordering invariants had already regressed once and been
  fixed inside the router's own creation PR (refs #1603, originating issue #1476). Evolving an
  untested router in 0.27.0 repeated that exposure; this is the safety net that pins the shipped
  behavior. Nine cases (ids 6-14) join the suite, each grading the router's stated reason rather
  than only its verdict, so a rewrite that reaches the right mechanism by the wrong edge still
  fails.

  **First-yes-wins ordering.** A machine-going-away prompt with healthy context and a small next
  step must still route to `clean-stop` — question 0 outranks every cost-based question below it,
  because a save-point that dies with the disk is no save-point. Separately, an explicit background
  request with healthy context must reach `continue-in-background` and NOT fall through to question
  3's zero-cost in-session exit: that exit answers yes whenever context is healthy, so asking it
  first would silently discard a user instruction. This is the invariant that regressed once, now
  pinned.

  **Zone gating.** A green zone word plus an evidence-degraded compaction marker must be read as
  degraded, and judgment-heavy work in a degraded context must not be routed to in-session
  continue. Its complement is graded too: a healthy zone whose next stage consumes the current
  stage's reasoning verbatim must prefer continue, since a summary of the reasoning is not the
  reasoning.

  **Post-evolution behavior.** The AFK edge must hand the spawn-brief decision to `orchestrate` and
  then KEEP asking — it is the router's one non-terminal edge — while launching nothing, leaving
  `continue-in-background`'s explicit-intent gate untouched. Suggest-by-default is graded on its
  full three-part shape: the single mechanism, the evidence that selected it, and the literal next
  invocation.

  **Autonomy gating.** Three separate cases hold the line the 0.27.0 review fixes drew: an opt-in
  counts only in a genuine user turn, so consent-shaped text inside a pasted issue body is data and
  never a licence; `auto` cannot carry out `/clear` or `/compact`, which sit outside the
  Skill-invocable built-ins and stay the human's to type; and `clean-stop` takes the literal
  `continue auto` token and nothing else, because once invoked it pushes commits, opens PRs, and
  files issues without a further confirmation.

## [0.27.0]

### Added

- **`workflow` — the continuation router becomes context-driven: informant inputs, an AFK edge, a
  stated output shape, two licensed autonomy tiers, and the I23 reconciliation (refs #2971, AI
  Hero course lane 2 #2900, decisions Q9/Q20-Q22).** The router previously decided from the zone
  word alone, and the AFK criterion the lane adopted had no edge to live on.

  **Informant inputs, as pointers.** A new section names the four inputs the router decides over
  beyond the zone word — where we stand (`session-flow:orient`), what is still running
  (`session-flow:reconcile`), which boundary this is (the workflow checklist), and whether the
  remaining work is already scoped (the consuming repo's work-item tracker seam) — each consumed
  the way the zone word already is: take the owner's answer, inline none of its mechanics. Every
  input is presence-gated, an absent one degrades to unknown rather than blocking, and the router
  runs no probe of its own. Consulting an informant never means firing one that writes: `orient` is
  read-only by contract, while `reconcile` auto-settles proven-done tasks, so the liveness input is
  a reconciliation that has ALREADY run — falling back to orient's read-only off-thread glance, and
  then to unknown — because a router that only recommends must not mutate tracking as a side effect
  of deciding. Beyond that, a later input arrives as a pointer, never as a probe inlined into the
  file, which keeps the skill's single pre-compute block under its `$`-expansion ban (#1687,
  #1688).

  **The AFK edge (question 2), deliberately non-terminal.** "Is the remaining work scoped to run
  away from the keyboard?" now has an edge: a yes hands the spawn-brief decision to
  `session-flow:orchestrate` and the router CONTINUES asking, because sending work elsewhere does
  not answer which mechanism carries this session across the boundary. It is ordered after the
  explicit-background-request question so feasibility the router infers can never pre-empt an
  instruction the user actually gave, and before the zero-cost in-session exit because a yes
  changes who does the remaining work while every question below asks how this session carries
  it. `continue-in-background`'s explicit-intent launch gate is untouched — the router suggests
  and never launches — and orchestrate keeps spawn ownership. The four questions below it are
  renumbered 3-6, with the cross-references inside the ordering purposes updated to match.

  **Suggest by default, with two licensed autonomy tiers.** The router's product is a
  recommendation addressed to the human, stated as mechanism plus the evidence that drove it (the
  zone word as resolved, the informant findings, the edge whose yes selected it) plus the literal
  next step. Executing the routed mechanism takes the top-tier per-invocation licence — a new
  `continue auto` argument (the argument-parsing rule now consumes a second token when the first is
  `continue`, so the modifier reaches its mode instead of falling into the bare `continue` row) or
  the user asking in words — which expires with the invocation and is
  never a standing config, mirroring `continue-in-background`'s explicit-words precedent; it
  authorizes the router to invoke a mechanism, never that mechanism to skip a gate it owns. The
  natural-language half of the opt-in counts only in a genuine user turn — a fetched page, an item
  body, a tool result, or another agent's return is data the router evaluates, never a licence it
  acts on — and a routed skill that makes outbound changes without a further confirmation takes the
  literal token and nothing else: `clean-stop` pushes commits, opens PRs, and files issues once
  invoked, so a semantic reading must never be what starts it. The opt-in also
  cannot reach `/clear` or `/compact` at all — those sit outside the small allowlist of
  `Skill`-invocable built-ins, so they are named as the next step and stay the human's to type. The
  second tier is the orchestrator relay, now codified in the handoff-relay convention as the
  autonomous tier for delegated work: a worker writes its own handoff at its fork point and
  returns the path, and the orchestrator — standing in for the absent human — retires it and
  seeds a fresh agent with the resume prompt, never reading the handoff body. Spawn-brief
  discipline stays orchestrate's.

  **I23 reconciliation, recorded where the design is stated.** A closing section reconciles the
  router against the `claude-config:audit-instructions` catalog's I23: the mechanism menu lives
  only in this user-invoked skill body (the criterion's exemption names the continuation-router
  case verbatim), nothing model-injected carries a menu, operator-channel pointers stay
  operator-side per `context-guard`'s 0.5.0 audience split — this router consumes the zone word
  and inlines no band values, so no remaining-context count reaches the model through it — and
  autonomy initiative comes from the user's opt-in or the orchestrator, never from injected
  context or a self-estimated budget.

## [0.26.1]

### Fixed

- **`handoff` — the rails resume prompt is now the mandated final text of the response.** Observed
  failure (owner report, high context occupancy): the handoff file was written correctly but the
  turn ended without ever emitting the copy/paste rails prompt, leaving the operator nothing to
  paste after `/clear` — a turn-termination failure, not a content failure. The post-write
  checklist previously implied ticks after the rails, so the response tail was checklist
  bureaucracy ending on "**EXECUTION STOPS HERE**" — a salient stop cue reachable before the rails
  were ever emitted. The output order is now fixed and stated as a hard rule: ticked checklist
  first, then the rails prompt plus every below-the-rails `/loop` re-arm note as the last text of
  the turn, with nothing after (the below-rail notes are included deliberately — the engine's
  detection contract names them part of the recoverable unit, so a bare "rails last" mandate would
  institutionalize dropping the re-arm). Both paths' `EXECUTION STOPS HERE` items now point at the
  rule.

  **The ambiguity that let it happen is fixed at its source, in the STOP gate itself.** Ordering
  alone treated the symptom: the deeper defect was that "the skill produces the save-point, THEN
  STOPS" reads, to a reader under load, as "the save-point is the file" — making STOP the next act
  once the file lands, in the single most emphatic section of the document. The engine says the
  opposite ("A resume prompt is ALWAYS emitted. The only decision is whether to ALSO write a
  durable handoff file"), so the prompt is the MANDATORY half of a save-point and the file the
  optional one, and the observed failure delivered the optional half while dropping the required
  one — leaving the operator a `/clear` they cannot resume from, worse than never running the skill
  because the skill reported success. The hard-rule section now defines what STOP means and the one
  thing it never means, the gate's emit box is marked as never satisfied by having written the
  file, and its STOP box as reachable only once that box is genuinely ticked. The failure is
  recorded in `context/gotchas.md` with its recovery (`find-handoff` rung 1), and eval 12
  (`rails-prompt-is-the-final-text-not-replaced-by-the-file`) pins the behavior under the
  high-occupancy condition none of the existing eight exercised.

  **Escalation ladder, recorded here on purpose:** this is the deliberately minimal fix — two
  fresh-context validators challenged a proposed deterministic Stop-hook enforcement as premature
  (single observed occurrence; the full path is already recoverable via `find-handoff` rung 1; the
  false-positive cost of blocking a stop lands at exactly the degraded occupancy the skill runs
  under). If the rails prompt goes missing again after this reorder, the agreed next step is a
  lightweight Stop-hook validator: `last_assistant_message` regex for the detection-contract
  signals, a PostToolUse skill-ran marker (never transcript parsing), one bounded block,
  fail-open, plus the hook-budget README share and a sibling contract test.

## [0.26.0]

### Added

- **`handoff` — routing-signals table, session-chain use named first-class, do-not-duplicate and
  promote-content rules, worktree caveat (refs #2956, AI Hero course lane 1 #2899).** "When to
  invoke" now names the session-chain/retrospective use (save-point, `/clear`, fresh session,
  with the `session_id`/`previous_handoff` chain `retro` walks) as a first-class owned use case
  alongside the boundary-crossing taxonomy (colleague, other repo or checkout, other agent,
  forked side task), and a compact routing-signals table maps situation to form: deep-window
  escape with chain value takes the full file (the default); small follow-ups with no chain
  value take prompt-only, accepting the documented retro-gap cost; a differing next-session
  focus takes either form plus the purpose argument; AFK-but-work-continues routes to the
  sibling `continue-in-background` skill; a machine that may go away routes to `clean-stop`
  semantics; boundary crossing takes the full file plus purpose plus the `Handoff origin:` line.
  The skill body states the general do-not-duplicate rule (content captured in specs, plans,
  ADRs, issues, commits, or diffs is referenced by path or URL, never restated — the existing
  "Summarize; never transcribe" guidance stated as a general rule, mirroring upstream) and the
  promote-content-never-file rule (durable value is promoted into a committed artifact — topic
  contract, issue, PR body — while the handoff file stays ephemeral and uncommitted; cleanup of
  `handoffs/` remains user-controlled removal, never silent expiry). The engine doc's
  destination section (`reference/save-point.md`) gains the worktree caveat: a save-point
  written inside a worktree checkout lives in that worktree's memory root and dies with
  `git worktree remove` — acceptable only when the worktree completes as a merged PR unit; when
  pausing un-merged worktree work, write from the main checkout or rely on `clean-stop`'s
  preserve-before-remove step. `find-handoff`'s detection contract is untouched. Adopted per the
  lane 1 decisions (`docs/upstream/aihero-course.md`, lane 1).

## [0.25.0]

### Added

- **`handoff` / `continue-in-background` — optional trailing purpose argument (refs #2955,
  AI Hero course lane 1 #2899).** Both producers' surface extends from `[file|prompt] [topic]` to
  `[file|prompt] [topic] [purpose...]`: everything after the topic token is optional
  natural-language purpose text answering "what will the next session be used for?" — no quoting,
  no new syntax, and existing invocations parse identically. The engine doc
  (`reference/save-point.md`, "The purpose argument tailors emphasis only") owns the semantics:
  purpose tailors emphasis only — the Resumption brief leads with it, Suggested skills are
  selected for it, Remaining actions are ordered by it where ordering is otherwise free — and it
  never drops or reorders the mandatory section set, never alters the emitted resume-prompt shape
  (`find-handoff`'s detection contract is untouched), and never amends the Original goal: a
  purpose that contradicts the goal is flagged at write time, not silently obeyed. On the
  prompt-only path — which writes none of the tailoring surfaces and can hand the rails block to
  a background agent as the only thing it sees — a stated purpose travels inline between the
  rails as a `Purpose:` line below the goal quote, never discarded (content between the rails,
  not a detection-contract shape change). Adopted from upstream `mattpocock/skills` `handoff`'s
  purpose argument per the lane 1 decision (`docs/upstream/aihero-course.md`, lane 1). Three eval
  cases cover the tailoring bounds, the conflict flag, and the prompt-only carriage.

## [0.24.0]

### Added

- `show-options` — a human-facing menu answering "what should I run next?". Five buckets (Now, Next,
  Skipped upstream, Later, and a rotating Spotlight of three), each rendered as a ranked shortlist of
  at most five plus the complete remainder by bare name with an explicit count — except `Later`,
  which is tier-2 only. `Later` is what makes the never-omit rule true: an in-domain skill beyond the
  near horizon (testing and review early in a session) fits no other bucket, and rendering it as one
  counted line catches it without recreating a dumping-ground bucket. Its contract is two
  rules: never omit a candidate's name, and never invent one; a skill believed to have already run is
  ranked normally and annotated rather than dropped. Candidates resolve from the full installed
  catalog rather than the in-context skill listing, which omits every manual-only skill and drops
  descriptions starting with the least-invoked ones. A pool sourced from that listing discloses its
  truncation in the output. Durable state is the primary signal, and the skill routes to `orient`
  for it rather than adding another copy of the probe block seven skills already carry.

### Changed

- `workflow` — its "When two capabilities both fit" precedence section now states that the
  route-to-exactly-one rule governs **stage** routing, and cedes option surfacing to `show-options`.
  Without that carve the two skills' contracts read as contradictory: one is required never to
  present both candidates, the other exists to present the whole set.
- `setup` and the plugin README — skill counts updated for the fourteenth skill. The README's
  "other eleven skills are zero-config" line was already off by one before this change and is now
  correct at thirteen.
- **`reference/gather.md` — the durable-state probe block is extracted to one owner doc.** Seven
  skills (`continue-in-background`, `find-handoff`, `handoff`, `orient`, `retro`, `running-retro`,
  `workflow`) each carried a near-identical copy of the probe list, the one-command-per-call and
  treat-failure-as-unknown rules, and the `#1687` no-precompute rationale. Each now names the probe
  subset it takes and cites the seam. The per-consumer differences are preserved and documented as
  deliberate rather than normalised away: `orient` reads `git log -8` where the save-point skills
  read `-5`, `retro` alone takes `git diff --name-only HEAD`, `find-handoff` takes no git state
  beyond the branch, and `workflow` takes no session id. `continue-in-background`'s warning that this
  block is never the dirty-tree gate is kept at its call site and generalised in the seam.

## [0.23.9]

### Changed

- Behavior-preserving simplifications from the repository-wide batch-simplify pass:
  duplicated helpers folded, dead code and redundant constructs removed, no functional
  change. Every group was verified by a fresh-context verifier agent against the
  plugin's own test suite.

## [0.23.8]

### Changed

- **`orchestrate`: dated fork→non-fork child probe note (#2738).**
  `context/sources.md` records a 2026-08-15 empirical probe attempt on Claude Code
  2.1.232 for whether a below-limit Agent-tool fork can spawn a non-fork child.
  Outcome: **inconclusive (fixture failure)** — CLI not logged in (`Not logged in
  · Please run /login`), so no Agent-tool dispatch ran. Documented as
  authentication/fixture gap, not a null finding; docs-implied path remains
  behavior-unconfirmed until a logged-in re-run.

## [0.23.7]

### Changed

- **`orchestrate`: cloud / unobservable rate-limit headroom fallback.** Imperative 7 now treats a
  missing/stale/`rate_limits`-less `rate-limit-guard` tee (the expected cloud / remote state) as
  thin headroom by default: small concurrent-worker cap, short waves, scale only on own-session
  rate-limit errors or live sibling-automation 429s — never invent window percentages. Gotchas and
  sources cite the reader contract's degraded-mode section; the live cloud statusline producer
  remains that contract's documented residual (#2697, #2736, #2747).

## [0.23.6]

### Changed

- **`orchestrate`: harness-claim corrections from a plugin-quality audit.** (1) "A fork is a leaf,
  never an intermediate tier" overreached the docs — the sub-agents page states only "A fork can't
  spawn further forks", and its depth-limit carve-out implies a below-limit fork holds a working
  Agent tool; the sentence now carries the narrow documented claim with citation. (2) The cap
  inventory said two env-var caps remain, but workflow agents and agent-team teammates "follow
  their own limits instead" — including the CPU-dependent, non-overridable workflow concurrency
  bound that actually bound an 88-agent evidence run at 2 concurrent on a 4-CPU container; the
  tiered-delegation section and `sources.md` now carry the current quotes (re-verified
  2026-08-15), the third concurrency rider (resumed subagents take a fresh slot), the
  Large-workflow threshold riders, and the v2.1.232 fork-default note. (3) The `${CLAUDE_EFFORT}`
  priming addendum now self-detects the direct-read fallback (a literal placeholder means the
  substitution never ran) instead of degrading silently.

## [0.23.5]

### Changed

- **README:** the Network section's closed roster of network-free skills is reopened to a category
  statement ("every skill not named above"), so skill additions no longer silently drift the list
  (repo-wide `/docs-hygiene:audit-noise` run, 2026-08-15).

## [0.23.4]

### Fixed

- **A failing vendored tzdata zip degrades to exit 3, not exit 1 (#2672).**
  `_ensure_bundled_tzdata()` wraps ZipFile/extractall in try/except so a corrupt
  or truncated `tzdata-zoneinfo.zip` cannot abort the script with exit 1 (this
  script's "limit still holds" code). Failures join the missing-bundle path and
  surface as exit 3 (`timezone-unavailable`). The tempfile cache name also carries
  a per-user component and refuses a symlinked or foreign-owned cache directory
  before putting it on `sys.path`.

## [0.23.3]

### Fixed

- **`keep-going` usage-limit reset checker on Windows (#2647).**
  `check-usage-limit-reset.py` now bundles the first-party `tzdata` package as
  `skills/keep-going/scripts/vendor/tzdata-zoneinfo.zip`, extracts it once into
  a tempfile cache, and puts that cache on `sys.path` before resolving IANA
  zones, so messages like `resets 7:10pm (America/New_York)` work when the host
  has no system TZDB (the stock Windows case). The zip form keeps zone tab text
  out of hygiene/typos. A missing zone after that fallback exits `3` with
  `timezone-unavailable:` instead of collapsing into exit `2` (`unparsed:`).

## [0.23.2]

### Changed

- **Docs:** actionable `/plugin configure` guidance now uses the marketplace-qualified form
  (`<plugin>@<marketplace>`; generated option blocks use `@<marketplace>`) per
  [`docs/extensibility-contract-smoke-tests.md`](../../docs/extensibility-contract-smoke-tests.md)
  Test E (#1360). Targetless references to the flow stay unqualified.

## [0.23.1]

### Fixed

- **Running-retro observer resumes when transcript growth returns after idle (#1471).** Hitting the
  mtime-idle threshold now enters a short confirmation window (`--idle-confirm-seconds`, default
  30s) instead of ending immediately; renewed growth cancels the pending end and returns to
  watching. After post-end analysis, if the transcript grew again the observer re-arms instead of
  exiting permanently.

## [0.23.0]

### Added

- **The context-guard zone seam is now consumed plugin-wide (#1602).** The plugin-wide decision the
  issue tracked is made: every skill whose correctness depends on how degraded the current window is
  reads the seam, presence-gated, instead of estimating. `keep-going` gains a zone-input section
  (a degraded or evidence-degraded window routes the continuation toward `handoff` rather than
  pushing judgment-heavy work through it), `running-retro`'s subjective-state note now carries the
  measured zone word next to the self-read, and `orchestrate`'s fan-out imperative resolves the word
  before a delegation decision. All three follow the pattern `handoff` and the `workflow`
  continuation router already established: resolve per the reader contract (which owns the snapshot
  path, staleness rule, and bands), consume only the zone word, inline no band values, and treat
  absent-plugin / absent-snapshot / `unknown` as degraded. Self-estimating the window remains
  explicitly forbidden at each consumption site — the motivating incident was a session reporting
  "around 40%" while the instrument read 15%.

## [0.22.5]

### Added

- **`keep-going` usage-limit reset checker** — `check-usage-limit-reset.py` parses the
  `resets …` clause from a limit message and exits lifted/blocked/unparsed (#1321).

## [0.22.4]

### Added

- **`Brain fried` output style** — ambient simplified register for cognitively depleted
  sessions; opt-in via `/config` (#1223).

## [0.22.3]

### Changed

- **Upstream doc stamps re-verified against the live pages (2026-08-10).** Each dated claim below was re-checked against the complete raw markdown source of the page it cites (`https://code.claude.com/docs/en/<page>.md`), not a summarized fetch, and each was confirmed by a verbatim quote before its stamp was refreshed. No claim changed; only the verification dates moved.

  - `skills/orchestrate/SKILL.md` — the workflow size guideline's agent counts (fewer than 5 for
    `small`, 15 for `medium`, 50 for `large`) and the `Large workflow` warning above 25
    agents (workflows reference).
  - `skills/orchestrate/context/sources.md` — all twelve remaining dated quotes, the densest
    citation block in the repo, re-checked one by one against the sub-agents, workflows, changelog,
    and `whats-new/2026-w32` pages. Every quote still matches word for word: the depth-limit
    `Agent` withholding and the fork's error-instead-of-spawn, the two tool filters and the
    first filter's list (which still contains `Workflow`), the fork exemption, the agent-teams
    task/cron carve-out, `Concurrent subagent limit reached` at 20 running with the ultracode
    exemption and the `/subtask` slot rider, the v2.1.172 / v2.1.217 / v2.1.219 / v2.1.178
    changelog entries, and the workflow runtime caps (16 concurrent, 1,000 per run, `Large
    workflow` above 25 agents or 1.5M projected tokens, requiring v2.1.203). Every dated citation
    in the file moved, including the depth-limit stamp, whose date wraps onto its own line and so
    escaped the first sweep.

    The 0.22.2 finding above is independently re-confirmed: the sub-agents page now states
    outright, "There's no limit on the total number of subagents Claude can spawn over a
    session", and `CLAUDE_CODE_MAX_SUBAGENTS_PER_SESSION` appears nowhere on it. That negative is
    trustworthy here because the check ran against the complete page rather than a truncated
    fetch.

## [0.22.2]

### Fixed

- **`orchestrate` no longer records a per-session subagent cap that no longer exists.** The sources
  file and the SKILL both carried "at most 200 subagents per session"
  (`CLAUDE_CODE_MAX_SUBAGENTS_PER_SESSION`, v2.1.212+), read from the sub-agents page on 2026-07-29.
  That cap was removed in v2.1.220–v2.1.224 — "The 200-subagent-per-session cap is removed, so
  long-running sessions no longer refuse new subagents; the concurrency and depth limits still
  apply" ([2026-w32](https://code.claude.com/docs/en/whats-new/2026-w32)) — and both the cap and its
  variable are gone from the reference page. A long-running orchestration planned around a session
  total was budgeting against a ceiling that is not there.
- The concurrency limit gains two riders recorded on the same re-read (verified 2026-08-10): sessions
  with `ultracode` active are exempt from it, and an in-session `/subtask` fork takes a slot while it
  runs but is never blocked by the limit.
- The superseded claim is kept in `sources.md` as an explicit **Superseded** note rather than
  deleted, so a reader who remembers the old cap finds out what replaced it instead of finding
  silence.

## [0.22.1]

### Fixed

- **`find-handoff`: a background continuation that COMPLETED is no longer read as one that failed.**
  The background-delivery screening rechecked the continuation's current state before excluding a
  save-point, but keyed that recheck on `claude agents` presence and collapsed every absence into
  "keep the candidate, noting the failed background attempt". `claude agents --json` lists ACTIVE
  sessions only — a completed background session is excluded by the CLI and surfaces only under
  `--all`, carrying a `state` (observed: `done`, `stopped`) where a live one carries a `status`
  (observed: `idle`, `busy`); verified this session against `claude agents --help` ("`--all` — With
  --json: also include completed background sessions") and a live `--json --all` sample, and it is
  the same contract `claude-ops`' `lane-launcher.sh` (`load_sessions`) already relies on. So a
  finished continuation looked identical to a dead one: the ladder surfaced its save-point as a lost
  handoff labelled a failed attempt, inviting the operator to redo completed work and letting a
  recent completed continuation bury the older manual handoff they were actually looking for. The
  recheck now reads `claude agents --json --all` and resolves four ways instead of two — live
  (exclude, work running), terminal-and-completed (exclude, work FINISHED, point at that session's
  output), terminal-and-not-completed (keep, the restart artifact the recheck exists for), and
  absent even from `--all` (UNKNOWN, keep, never called a failure, since the `--all` history is
  bounded) — keyed on the launched `sessionId` where the transcript recorded one, with the
  `continue-<topic>` slug remaining an ambiguous key that routes to UNKNOWN. Stated once at the
  step-1 screening site and governing every screening site, with the prompt-only site and the
  Gotchas bullet aligned to it; `evals.json` case 8's stale expectation corrected and a case added
  for the completed-continuation branch. (claude-code-plugins#1033 review thread.)

## [0.22.0]

### Removed

- **The bare `/<skill>` alias for this plugin's skills.** Their `SKILL.md` files no longer
  declare a frontmatter `name`. The field is optional and defaults to the directory name, so
  declaring it only restated the path while registering a second, unnamespaced command — which
  the slash-command picker then echoed back as `/plugin:skill (skill)`. Invoke a skill by its
  namespaced command; the command itself is unchanged.

## [0.21.3]

### Changed

- **`workflow`: the continuation router's continue question gains the primary-source criterion.**
  Within a still-healthy zone, prefer continuing when the next stage consumes this stage's
  reasoning verbatim — a summary of the reasoning is not the reasoning. Explicitly bounded: it
  never overrides a degraded zone, where the degradation-wins stance holds and handoff remains
  the route. (Criterion from upstream mattpocock/skills ask-matt `PHASE-BOUNDARIES.md` v1.2,
  adopted zone-gated; the rest of that tree audited at parity or rejected — registry: the
  marketplace repository's `docs/upstream/mattpocock-skills.md`.)

## [0.21.2]

### Changed

- **`running-retro` and `reconcile`: listing descriptions tightened (1,116 → 869 and
  1,072 → 837 chars)** — trimmed the explanatory prose from each frontmatter `description` toward
  the shared skill-listing budget (claude-code-plugins#2022, option 2). Every single-quoted
  trigger phrase is preserved verbatim (skill-quality check 3); both skills' contracts and sibling
  boundaries are unchanged in the bodies.

## [0.21.1]

### Changed

- **`retro`: mode selection no longer turns on a context-percentage the model cannot measure.**
  `SKILL.md` and `context/quick.md` both routed to `quick` when the context window was ">75% used" —
  a figure a session can only fabricate, which the sibling `handoff` skill already disclaims by name
  ("never by a fixed token count"). Both now key off observable signals: a long or quality-degraded
  session, or a compaction that has occurred.

- **`running-retro`: the detached observer's analysis prompt is XML-sectioned.** `observer.py`'s
  `_analysis_prompt` ran roughly a thousand words of tools, trust boundary, method, inputs, and task
  together as undelimited prose, and it is executed by the cheap default model (`claude-haiku-4-5`)
  with no follow-up turn to recover from a misread. The five parts are now wrapped in `<tools>`,
  `<trust_boundary>`, `<method>`, `<inputs>`, and `<task>`, with two section leads lightly
  reworded to fit the tags; every compute-don't-assert rule, dependency check, and the mandatory
  redaction pass carry over verbatim.

- **`workflow`: the depth expectation in `context/philosophy.md` reads in normal case.** "Default to
  HIGH confidence, HIGH accuracy, HIGH attention to detail" plus a second sentence repeating it
  collapses to one sentence stating the same expectation.

## [0.21.0]

### Changed

- **`handoff` no longer fires on a self-estimated context budget.** Its `description` listed
  "context is heavy" among the triggers, and the body's "When to invoke" repeated it as "Mid-task,
  context heavy (check `/context` output or user report)" — telling the model to judge its own
  window and volunteer a handoff on that judgement. A description is resident in context by default
  (<https://code.claude.com/docs/en/skills>, verified 2026-08-08), so that trigger was live in every
  session with the plugin installed, and it is the shape the `claude-config` instruction-audit
  catalog's check I23 detects.

  Three signals now license the skill, and a self-estimated budget is not among them: **the user's
  own report**, **an instrument that measures the window** (`context-guard`'s zone report is one),
  and **visible decay in the responses themselves** — drift, repetition, looping. The third is
  explicitly the model's to read, because decay shows up in the output and never in a budget number.
  Nothing about the save-point engine, the arguments, the STOP gate, or the emitted artifacts
  changes, and the skill stays model-invocable: only the budget clause is gone.

  The "Fork beats compaction" section keeps its window-position threshold and gains a one-line
  anchor saying what it always meant — it picks between two continuation mechanisms and never
  licenses the continuation itself.

## [0.20.0]

### Changed

- **`retro` quick mode: the findings bar is now a decidable test, not a qualitative label.** "Only
  errors, regressions, or significant behavioral gaps — skip minor issues" gated findings on
  "significant"/"minor", which current models apply faithfully at the finding stage and convert
  into withheld findings (Sonnet 5 prompting guide, "Code review harnesses": state the bar
  concretely "rather than using qualitative terms"). The bar now enumerates what qualifies — a
  wrong result produced, a regression against earlier session behavior, a skipped or failed
  verification, a repeated user correction — and what is omitted (style, phrasing, self-corrected
  one-off friction). The max-3 cap is unchanged.

## [0.19.0]

### Changed

- **Orchestration imperative 2 ("SPEC EVERY SPAWN") now names the reason as a required field.** It
  previously asked for an objective, an output format, tools and sources, boundaries, and a model
  tier — five things, none of them intent. The imperative now leads with the reason the work is
  being asked for: the larger task it feeds, who the output is for, and what it enables.
  - This travels further than the other surfaces changed alongside it, because these imperatives are
    also an **export**: `handoff` and `worker` modes emit them verbatim between dashed rails for a
    target that left the session and inherits nothing. A worker pasted that brief was previously
    told to spec five things and given no slot for the one a spawned worker most conspicuously
    lacks.
  - Sourced from Anthropic's Fable 5 prompting guide, "Give the reason, not only the request", with
    the citation added to `context/sources.md` under imperative 2 — that ledger backs every
    imperative with the page it came from, so a field added without one would be the only unsourced
    clause in the brief.

## [0.18.0]

### Added

- **`retro`: the multi-session parser now reports chain coverage (#1980).** Chain discovery walks
  `previous_handoff` pointers backwards, so it stops at the first session that wrote no handoff
  file — and a walk that ended early was indistinguishable in the output from a genuinely short
  chain. The reported case ran a 10-session chain linked by hand-pasted continuation prompts and
  got a retrospective authored from 2 sessions, with nothing signalling the gap. The multi-session
  output carries a `chain_coverage` block (`requested` / `found` / `available` / `ratio`), where
  `available` counts the transcripts present for the project — the denominator the walk itself
  cannot see — and the human-readable `summary` carries the same ratio. The skill now states its
  discovery basis and must not present a low-coverage chain retro silently; below ~0.5 it names the
  counts and offers `--sessions` with the ids enumerated.

### Fixed

- **`retro`: `parse_transcript.py --sessions` accepts a comma-joined list instead of silently
  resolving nothing (#1980).** The option is declared `nargs="+"`, so `--sessions a,b,c` — the
  shape a caller reaches for when the ids were just written into prose — was consumed as ONE
  literal token. It matched no transcript file, and the run reported "0 with transcript" for a
  chain whose transcripts all existed: a wrong answer rather than an error. Tokens are now split on
  `,` after parsing (a session id never contains one, so the split cannot change the meaning of a
  correctly space-separated invocation), empty fragments are dropped, and a `--sessions` value that
  resolves to no ids at all reaches the existing usage error.

- **`retro`: a repeated session-id is parsed once, not once per mention.** Every multi-session
  number is a sum over the requested list, so naming one id twice — easy once a comma-joined list
  can be mixed with a space-separated one — doubled the aggregate token and turn totals and counted
  a single transcript twice against an `available` denominator that counts its file once,
  publishing a `chain_coverage.ratio` of 2.0 and a summary reading "covering 2 of 1 transcript(s)".
  `build_multi_session_output` now deduplicates its ids first-occurrence-wins, which keeps the
  order the roles depend on (first id = current session). The rule lives in that one function so
  every entry point is covered, `--chain-from` included; the walk's own cycle guard stays, because
  a pointer cycle has to terminate the walk rather than be cleaned up after it.
  `chain_coverage.requested` and the `pass` status now compare against the deduplicated list, so a
  run that named an id twice reports `requested: 1` and still passes.

## [0.17.24]

### Fixed

- **`orchestrate`'s priming addendum called dynamic workflows "(main-session-only)", which a fork
  disproves.** The `Workflow` tool is stripped by the first of the two filters that narrow a
  subagent's inherited tool pool — but forks skip both filters and receive the main conversation's
  exact tool pool, so a fork reaches the surface the parenthetical said only the main session could.
  A session priming itself off that line would rule out a fork as a workflow-capable delegate on a
  false premise, which matters precisely where the addendum is read: choosing what to delegate. The
  parenthetical now reads **(withheld from non-fork workers)**, which scopes the sentence's
  "surfaces a worker cannot" to the workers it is actually true of; the rest of the addendum is
  unchanged. `context/sources.md` gains a **Priming addendum — surface reachability** section
  carrying both halves the claim needs as verified verbatim quotes — `Workflow`'s membership in the
  first filter and the forks-skip-both-filters exemption — since either alone proves nothing. The
  file's existing fork quotes covered only the `Agent` tool at the depth limit, a different
  mechanism.

- **The same claim appeared unqualified twice more, both times about the export brief.** "What this
  skill does NOT do" and the `worker-export-inherit-line` eval each justified omitting agent teams
  and dynamic workflows from the export because "a spawned worker cannot reach either" — true of a
  named subagent, false of a fork. Both now say **a pasted target**, matching the formulation the
  addendum itself already used twelve lines above; a pasted brief only ever reaches a target that
  inherited none of the session's context, which is never a fork. The graded export behavior is
  unchanged.

## [0.17.23]

### Fixed

- **A handoff chain preserved state perfectly and intent not at all: nothing made the user's own
  goal a mandatory, immutable field, so each save-point serialized the process machinery as the
  mission.** The goal appeared in exactly one place — a line inside the six-line `Resumption brief`,
  a section whose own contract is to restate facts owned below. So every hop re-derived the goal
  from a conversation that had already lost it, each paraphrase individually plausible, and what
  survived was the phase, the bundle, and the checklist in front of the writer. `Completion
  criteria` compounded it: the section demanded observability and said nothing about framing, so
  criteria stated as process steps passed — and a process criterion is satisfiable while the goal is
  no closer, reporting done when the process finished rather than when the work landed. Each resumed
  session then optimized the wrong objective faithfully, with nothing on any resume path testing the
  work against what it was for.

  `reference/structure.md` now opens with body section 1, **`Original goal`** — the user's statement
  quoted verbatim with its date, never paraphrased; `Amended:` defaulting to `None.` and changeable
  only on an explicit dated statement from whoever set the goal, prior goal retained above it; and a
  drift-check line, `Next action serves it by:`, that ties the first remaining action back to the
  goal and, when it cannot be written, says so as drift rather than staying silent. Immutability is
  enforced as a step, not an adjective: whenever `previous_handoff` is emitted, the write procedure
  opens that file from disk THIS turn and reproduces its quote and amendments unchanged — the same
  did-the-read check the live `TaskList` call already carries. The `Resumption brief` stops
  restating the goal and points at §1. `Completion criteria` now requires both halves — the
  goal-state a criterion establishes AND the command or diff that settles it — with process
  milestones demoted to a subordinate `Process milestones` sub-heading, since goal-framed
  criteria are the harder ones to settle mechanically, which is exactly why writers drifted to
  process framing. Sections renumbered 1-14; the doc's internal cross-references moved with them.
  `skills/handoff`'s post-write checklist gains the matching assertions on both paths — the quote
  copied off disk rather than rebuilt, the drift-check answered, criteria goal-framed, and the
  verbatim goal line present on prompt-only — because a rule the writer is never checked against is
  the rule it drifts from; `context/gotchas.md` carries the failure pattern, and the skill's eval
  set covers both paths.

- **Nothing re-anchored a resumed session to its goal, so the drift ran unnoticed across many
  sessions.** The check now sits on all three surfaces a resume can cross.
  `reference/save-point.md` gains an `Original goal — mandatory on BOTH paths` rule (prompt-only
  writes no body sections, so it carries the verbatim goal inline between the rails — below an
  active `/goal` re-arm when one holds the first line, above its remaining-work bullets, and with
  every dated amendment travelling under the original quote rather than collapsing to a single
  line — it points at no file, and a prompt-only save-point listing just the
  follow-ups is the precise shape that loses the goal), and the rails directive becomes `Read @…,
  confirm its Original goal still governs the remaining next steps, then continue them.` — the
  directive because it is the one artifact every resume passes through, including the dominant bare
  paste that invokes no skill at all, the agent `continue-in-background` launches, and a
  `find-handoff` recovery. Not a detection-contract change: signal 1 is matched on the
  `…handoffs/<TS>-handoff-…` shape, which the clause leaves untouched. It does carry one structural
  consequence, recorded where `structure.md` describes how that doc is cited elsewhere: the
  directive now names `Original goal` by name (never by number), so renaming that one section
  ripples out to it, where before no rename ripple existed. `skills/keep-going` owns the
  skill-mediated path — goal alignment is now its own step, sitting after the read-only
  inventory/inspection and BEFORE any recovery action, because resuming or restarting work that
  serves a drifted goal re-arms the drift before anything has tested it: read the handoff's
  `Original goal`, say in one sentence how the next action
  serves it, and treat an unstatable connection as drift rather than a wording problem. A handoff
  carrying no `Original goal` is itself a flagged defect — the goal is never inferred from the
  process the file describes, since that process is the thing that drifted; the user is asked for it
  in their own words first. `skills/reanchor` covers the third path — the deliberate "is this still
  current" pass over an old plan, where neither of the other two ever runs — as a fifth premise
  check beside its PR, base-drift, surface-rename, and stale-memory ones. That framing is the point:
  a recorded goal is a documented claim about what the work is FOR, and it goes stale exactly the
  way a PR's state does, so it sits inside reanchor's existing boundary rather than stretching it
  toward intent. Because reanchor reads a chain, it can do what no single-document check can — open
  the prior handoff and compare the quotes across links, reporting a re-derived goal as drift
  between them. It reports and hands to `keep-going`; it never re-derives the next action or amends
  a goal. None of the three is sufficient alone: reanchor is opt-in and fires only once staleness is
  already suspected, which is precisely when a drifted chain looks healthiest. Both skills carry
  eval cases for the new check, including the absent-goal case each must refuse to infer past.

## [0.17.22]

### Fixed

- **`/session-flow:orchestrate`'s FRESH-CONTEXT VERIFY imperative told a session to hand
  every edit batch to a separate verifier without saying which edits count, so it licensed
  verifying the bookkeeping about the work.** A campaign's ledgers, checklists, and status
  rows are edit batches too; applied to them the imperative spawns verifiers on process
  records, and on the records those verifications produce. Imperative 3 in
  `skills/orchestrate/SKILL.md` now scopes itself to what ships: a process record about the
  work (ledger, checklist, status log) is not the work and stays at self-check however many
  of them a batch touched, and a record OF a verification is never itself verified. An eval
  exercises the discrimination.

  The clause is terse and self-contained on purpose, and it is the one place this rule is
  restated. The `playbooks` plugin's `fable-5` orchestration chapter owns the rule with its
  rationale; this skill's imperatives also **export** as a paste-ready brief for a target
  that leaves the session, and that brief is model- and tool-agnostic by construction —
  nothing in it may depend on a repo file — so a pointer is not an expressible form here.
  It sits in the sub-clause body, leaving the `compact` headline-only export unchanged.

## [0.17.21]

### Fixed

- **The observer's poll interval was documented and read but never declared, so the plugin's own
  config surface could not set it.** `observer-arm.sh` lists
  `CLAUDE_PLUGIN_OPTION_OBSERVER_POLL_SECONDS` among its supported knobs and reads it into the
  `--poll-seconds` the observer loop sleeps on, but the manifest declared no
  `observer_poll_seconds` entry. Only a declared `userConfig` option is prompted for, stored under
  `pluginConfigs[<id>].options`, and exported to hook processes, so nothing the consumer could set
  through `/plugin` ever reached the hook — it always took the hardcoded 5-second fallback, and
  silently, since a `:-5` read cannot distinguish an undeliverable value from an unset one. (A
  hand-written repo `env` block could still populate the variable, per
  `docs/conventions/hook-config-delivery/`; that is the workaround, not the interface.) Its five
  siblings on the same hook — `observer_enabled`, `observer_analysis_*`, `observer_idle_seconds`,
  `observer_max_seconds` — were all declared; this one was missed. The manifest now declares it,
  alongside the idle and lifetime knobs it is read with, bounded at `min: 1` because the value
  reaches `time.sleep` unvalidated: `0` spins the detached observer continuously and a negative
  value raises there, killing it silently since the launcher's output is suppressed. The key is
  added to the two inventories that enumerate the observer knobs — the plugin README's config
  table and `skills/setup`'s effective-value report — so `/session-flow:setup` reports it and its
  reinstall guidance, which resupplies every non-default key, no longer silently resets it to 5.

## [0.17.20]

### Fixed

- **The resume prompt's path was rootless, so it resolved against a real-but-wrong directory
  whenever the resuming session's cwd was not the worked-in repo root (#1644).** The save-point
  engine specified the directive as `Read @<memory_dir>/handoffs/<TS>-handoff-<topic>.md` — "the
  path the write step actually used" — and `memory_dir` is repo-relative by contract, so the one
  artifact the operator carries across `/clear` lost the root the handoff file was written under.
  Pasted into a session whose cwd was a different repository (or a subdirectory of the right one),
  the `@`-reference resolved somewhere else; when that somewhere else had its own `handoffs/`
  directory, the failure presented as "the file is missing" rather than "the path has no root".
  The directive now carries the **absolute**, forward-slash-normalized path, matching what the
  topic-docs binding already does on its no-project-root branch, and a `Handoff origin:` line
  inside the rails names the repository and repo-relative path so a resume on another machine or
  checkout can re-resolve — computed at emit time, not a stored frontmatter field. The `@` mention
  is documented as an accelerator rather than the mechanism: official docs state an `@` path "can
  be relative or absolute" but document no drive-letter or whitespace-bearing form, so the
  directive is written to stay actionable when expansion does not fire.
- **`find-handoff` inherited the same single-root assumption, so the skill built to recover this
  failure could not recover it (#1644).** Its transcript rung located the correct directive, then
  resolved the relative path against the source transcript's `cwd` — which is not necessarily the
  repository the producer wrote into — and dropped the candidate on the existence check. The
  detection contract now accepts **both** the rooted and the legacy rootless form, matching on the
  shape they share and diverging only at that check, so the corpus already on disk keeps
  recovering. A path that resolves to nothing is now **UNRESOLVED, not discarded** — on both forms,
  for different reasons: a rootless one because resolving it against the producer's `cwd` is an
  inference, and a rooted one because an absolute path is machine-local and a resume on another
  machine or checkout cannot satisfy it. The rooted miss is exactly what `Handoff origin:` exists
  for, so the existence check reads that line and re-resolves against the repository it names before
  giving up. Either way the skill spends one bounded, read-only widening over repository roots
  already in hand, then surfaces the candidate at the confirm gate with its directive verbatim and
  names the precise reason — the path has no root, or nothing is at that absolute path on this
  machine — rather than reporting a missing file.
- **The bounded widening could sweep a whole home directory, because it globbed under a `cwd` it
  never verified was a repository root.** The recorded `cwd` of a session launched straight from a
  home directory *is* that home directory, so globbing a filename under it recursively walks most of
  the user's files — the machine-wide scan the rule forbids, reached by accident rather than by
  intent, and slow enough to time the recovery out. A `cwd` now earns a place in the widening set
  only once `git -C <cwd> rev-parse --show-toplevel` confirms it, and the search runs under the top
  level that prints rather than under `cwd` itself. A `cwd` with no top level contributes no root;
  the candidate stays UNRESOLVED and the operator is asked which checkout to look in, which is the
  honest answer when nothing in hand can name one.
- **`Handoff origin:` embedded the `origin` remote URL verbatim, and a remote URL routinely carries
  a credential.** The userinfo component of an HTTPS remote holds a PAT, a stored password, or a
  credential helper's `x-access-token:<token>@` — and this line sits *inside* the rails, in the
  region the operator is told to copy, so an embedded secret travels into the next session and onto
  every machine the prompt is forwarded to. The producer now strips everything from `://` up to and
  including the `@` before embedding what is left, and falls back to the repository's root directory
  name when a URL cannot be sanitized with confidence. Remote URLs are named as an explicit vector
  in both redaction passes — a token in a URL reads as one more path segment, which is the shape a
  model-driven sweep is likeliest to walk past — and `find-handoff` applies the same check to the
  value it surfaces at the confirm gate and derives a widening root from, since a recovered handoff
  predates this rule as easily as it predates the rooted path. Both passes state the **precedence**
  explicitly, because the git-URL rule and the general redaction rule prescribe different outputs for
  the same secret class and a model executing them could not otherwise tell which wins: the URL is
  reduced to its bare scheme-and-host form and NOT replaced with a shape marker. That is a deliberate
  exception — the general rule redacts to a marker because the whole value is secret and unneeded,
  whereas a remote URL's host and path are non-secret and load-bearing, so `<REDACTED: remote URL>`
  would trade a credential leak for a broken recovery. The sanitization boundaries are stated too: a
  bare ssh account name (`ssh://git@host/…`) is not a credential and stays, since the secret is the
  local key the URL does not carry; and "cannot be sanitized with confidence" gets a test — fall back
  to the root directory name when the userinfo boundary is undeterminable, as with more than one `@`
  ahead of the path or the SCP-style `git@host:<owner>/<repo>.git` form that has no `://` to anchor
  stripping on. The exception is scoped to git remote URLs and stated not to generalize: a connection
  string keeps the shape marker, because what earns a remote URL its host-preserving strip is that
  recovery re-resolves from the surviving host and path — nothing re-resolves from a database host, so
  preserving one would disclose infrastructure for no benefit.

### Notes

- **Rung 1 still cannot correlate a glob candidate to the repository the work was in (#1644).** A
  handoff file records no durable repository identity — the frontmatter carries `type`, `date`,
  `topic`, `session_id`, and `previous_handoff` — so nothing can reject a same-cwd, different-repo
  candidate. Closing it requires a new frontmatter field, a cross-cutting schema change every
  handoff already on disk would lack; that decision is deliberately left outside this fix and
  tracked as #1778. The rung
  now states the gap in place rather than reading as closed, and the transcript-based substitute is
  explicitly rejected: it depends on a transcript that may be absent and returns nothing for every
  rootless legacy handoff, which is exactly where the check is needed.

## [0.17.19]

### Added

- **workflow: end-of-phase continuation router (#1476).** The stage map answered "what comes
  next"; a new `context/continuation.md` spoke (argument mode `continue`, plus a default-mode
  step at phase boundaries) answers "which continuation MECHANISM carries the session there".
  The outcome set is derived from the mechanisms this plugin actually installs plus the
  built-ins — continue / `/clear` / `handoff` / `continue-in-background` / `clean-stop` /
  `/compact` — not inherited from any source diagram; `reconcile`/`orient` are deliberately
  non-terminals (state hygiene informs the decision, never carries the session). Every ordering
  edge carries its stated purpose in the doc: machine-loss is asked FIRST (a save-point that
  dies with the disk is no save-point), the zero-cost exits precede every writing mechanism,
  background delegation precedes handoff (same save-point engine, different delivery, but the
  strictly narrower gate — it is explicit-request-gated, and the generic handoff question would
  otherwise swallow it, since a background continuation always passes the work to another agent),
  and `/compact` is the deliberate last resort with the tradeoff owned
  by handoff's "Fork beats compaction when the window is deep" section (pointer, not copy). Zone
  input is presence-gated on the `context-guard` reader contract with NO inlined band values —
  the router consumes only the zone word and degrades to judgment tests when the seam is absent
  or `unknown`, honoring the evidence-degraded marker. Also documents the handoff-relay
  convention for workers: a worker at its zone boundary writes its own handoff and returns the
  PATH only; the parent spawns a successor pointed at the file without ever reading it.

### Fixed

- **The explicit-background question was ordered after the zero-cost continue-in-session
  question, so it was unreachable whenever context was healthy.** The prior release ordered the
  explicit-background check before the generic handoff question (so handoff would not swallow
  it), but left it after the router's own first question — "is there enough smart zone left?" —
  which answers yes whenever context is healthy and silently discards an explicit user request to
  continue in the background, the exact "edge that loses its purpose" the router's own governing
  rule warns against. The explicit-background-and-feasibility question is now asked first,
  immediately after the machine-going-away check, on the same "a hard fact outranks a cost
  heuristic" ground that check already established; a request that still needs human input, or
  that the session cannot hand off autonomously, falls through unchanged to the questions below.

## [0.17.18]

### Fixed

- **`orchestrate`'s nested-subagent drift note asserted a disagreement that upstream has since
  resolved (melodic-software/claude-code-plugins#1312).** 0.17.14 recorded that the `sub-agents`
  page lagged the changelog and still described the off-by-default state, and told readers to treat
  the changelog as authoritative for the default. Re-verified 2026-07-29 against the raw markdown of
  both surfaces: the page now states the depth-3 default itself ("By default, a subagent can spawn
  subagents of its own, up to three layers below the main conversation") and carries its own
  version-history note covering all three regimes. The two surfaces agree, so the note is rewritten
  as a resolved-drift record — it keeps the historical split and the empirical 2.1.220 observation,
  because the page carries no dated revision history and a cached or vendored copy can still be
  showing the old account.
- **One quote marked `(verbatim, verified 2026-07-26)` was no longer verbatim.** The tool-list
  gating sentence read "…lets that subagent spawn subagents of its own **once you allow nested
  spawning**…"; the page now reads "…**while the depth limit allows it**…". Corrected, and the
  superseded "while nesting is off" framing is replaced with the page's current at-the-limit
  semantics, including that a fork at the limit keeps `Agent` but the tool errors instead of
  spawning.
- Every imperative-5 claim re-verified against byte-exact raw markdown and re-anchored to
  2026-07-29; the changelog is recorded as current through v2.1.220.
- **Imperative 7's `/config` size-guideline quote was not byte-exact** — it read `small`
  "fewer than 5" where the workflows page's table reads "Fewer than 5 agents" (likewise 15 and 50).
  Corrected and anchored to 2026-07-29. Caught by the independent citation audit outside the
  reported hunks; fixed in passing rather than left in a file whose purpose is exact quotation.
- The superseded page text quoted inside the resolved-drift note is now labelled as page text
  captured 2026-07-26 and no longer reproducible upstream, so it is not mistaken for a live quote.

### Added

- **The file header now states what `(verbatim)` tolerates** — link syntax stripped to its text,
  inline emphasis dropped or added, `\_` unescaped from raw changelog lines, and a sentence-final
  period on a mid-sentence fragment. Anything that changes wording is a defect, not a normalization.
  The convention was previously unwritten, so a reviewer could not tell a deliberate normalization
  from a drifted quote.

### Notes

- The `v2.1.172` reference is a **historical citation** — the release that shipped nesting — not a
  verification pin, and the file now says so inline. The `sub-agents` page's own version-history
  note independently corroborates it. Bumping it would corrupt a correct citation.
- `SKILL.md` and `context/gotchas.md` state their drift observations in dated past tense
  ("on 2026-07-26 the page still described…"), so both remain accurate and are unchanged. Their
  behavioral-probe guidance stands on its own regardless of whether the surfaces agree.

## [0.17.17]

### Fixed

- **`continue-in-background`'s dirty-tree gate had no branch for a consuming directory that is not
  a git repository (melodic-software/claude-code-plugins#929).** The gate opened by running
  `git status --porcelain -uall`, which in a non-repo directory (a session started in `$HOME`, say)
  fails with `fatal: not a git repository` and leaves the skill with no specified behavior.
  - The gate now establishes repository status first with `git rev-parse --is-inside-work-tree`.
    Two results are specified and everything else falls through to a deliberate default, so the
    gate is exhaustive by construction rather than by enumeration. `true` → inspect the tree as
    before. Positively identified as *not a git repository* **and** no `WorktreeCreate` hook
    configured → launch: there is no uncommitted work to protect and no worktree isolation to
    lose, because background sessions then write to the working directory directly rather than
    moving into an isolated worktree (<https://code.claude.com/docs/en/agent-view>); the launch
    report states that reading.
  - The hook is part of that branch's condition, not a parenthetical premise. `WorktreeCreate` is
    the isolation path for non-Git source control
    (`plugins/playbooks/skills/boris/reference/worktrees.md`) and "replaces the default worktree
    creation entirely" (`docs/conventions/topic-docs/README.md`), so a configured hook moves the
    launched session into a workspace the consuming checkout's local changes never reach — exactly
    what the dirty-tree gate exists to prevent. Absence of the hook must therefore be
    *established*; a configured hook, or an absence that cannot be established, falls to the wide
    default below and does not launch.
  - Anything else is UNKNOWN tree state, not clean, and does not launch. That default is wide on
    purpose: a failure for some other reason (dubious ownership, a damaged repository, git missing
    from `PATH`), and also a *successful* `false` — inside a bare repository or a `.git`
    directory, where the command exits 0 and there is no work tree. Routing by exit status alone
    in either direction would have turned a gate that protects uncommitted work into one that
    fails open on exactly the cases where the tree is least readable.
  - The context-gathering block's "treat any failure as an unknown value and carry on" is now
    scoped to itself. It colors the save-point and is not the gate; its shrug, and its non-`-uall`
    `git status` output, must not be carried into the gate, which reads a git failure the opposite
    way.
  - The post-launch enforcement checklist and the gotchas index carry the same branches, so the
    surfaces the user verifies the exit shape against no longer disagree with the gate.
  - Four eval cases added: a non-repo directory with no `WorktreeCreate` hook that launches, a
    non-repo directory *with* one that does not, a git failure that is not "not a git repository"
    that does not, and a zero-exit `false` that does not.

## [0.17.16]

### Fixed

- **0.17.15 was based on a wrong diagnosis and did not fix anything
  (melodic-software/claude-code-plugins#1687).** That release removed git from seven skills'
  pre-compute blocks on the theory that the harness composes a block into one shell invocation and
  the worktree-isolation guard refuses a git-bearing compound command. An adversarial re-probe
  refutes it. `git status --porcelain 2>/dev/null | head -20 || echo clean` — git, a pipe, a
  redirect, and a `||` — **passes** from a worktree-isolated agent. `echo "${CLAUDE_CODE_SESSION_ID:-unknown}" || echo "unknown"`,
  which has no git at all, is **refused**. Git, pipes, redirects, `||`, and multi-line composition
  are all irrelevant.
  - **The real trigger is a `$`-expansion.** A command is refused iff it contains one in any form
    other than bare `$HOME` or `"$HOME"`; a skill fails to load iff its pre-compute block contains at
    least one such expansion. Because 0.17.15 kept
    `` !`echo "${CLAUDE_CODE_SESSION_ID:-unknown}" || echo "unknown"` `` in six of the seven skills,
    `handoff`, `continue-in-background`, `orient`, `retro`, `running-retro`, and `find-handoff`
    stayed uninvocable from an isolated agent for the whole of 0.17.15. Only `workflow` was fixed,
    and only incidentally — its entire pre-compute block had been deleted.
  - The session-id pre-compute line is removed from all six. The value is re-acquired in the skill
    body with `printenv CLAUDE_CODE_SESSION_ID`, which carries no `$` and is observed to pass under
    isolation. Failure is treated as "unknown, carry on", as before.
  - Deleting that line emptied the `## Pre-computed context` block of `handoff`,
    `continue-in-background`, `orient`, `retro`, and `running-retro`, so the now-bare heading is
    removed too. Only `find-handoff` still has a pre-compute block.
  - `find-handoff`'s transcript-dir glob keeps its pre-compute line with `${HOME}` reduced to bare
    `$HOME`; the full line was run verbatim under isolation and passes. Its body reference to the
    "pre-computed" session id is repointed at the gathered value.
  - The 0.17.15 body prose asserted the falsified mechanism and derived an instruction from it ("do
    not restore it as a `| head -20` pipe" — a form now observed to pass). That rationale is
    corrected and compressed to one sentence in all seven skills, `workflow` included. The 20-entry
    read bound is kept as a plain instruction; only its false justification is dropped.
  - **New observation, beyond what #1687 recorded.** `echo $CLAUDE_CODE_SESSION_ID` — bare, no
    braces — is also refused, while `echo $HOME` passes. The guard's allowlist is therefore
    name-specific, not merely form-specific, and `HOME` is the only member found across two
    independent probe sessions. That is uncharacterized upstream behavior: a guard tightening would
    regress `find-handoff`'s remaining pre-compute line, and nothing else in this plugin.
  - What was verified, precisely: from this worktree-isolated agent, every command form above was
    run standalone and its PASS/REFUSED result recorded, including the replacement `printenv` call
    and `find-handoff`'s rewritten glob line. The **edited skills have not been invoked** from an
    isolated agent and cannot be — skills load from the version-keyed plugin cache, so `0.17.16`
    does not exist there until this ships and plugins are updated. Confirm then, with a negative
    control. CI cannot prove this fix; it never invokes a skill from an isolated agent.
  - Still out of scope: several bodies and `reference/` snippets run `$`-bearing shell (for example
    `retro`'s transcript parser invocation). Those skills now **load** under isolation, but those
    specific body commands remain subject to the same guard.

## [0.17.15]

### Fixed

- **Every git-bearing skill in this plugin was uninvocable from a worktree-isolated agent
  (melodic-software/claude-code-plugins#1619).** The harness composes an entire
  `## Pre-computed context` block into ONE shell invocation, and the worktree-isolation Bash guard
  refuses a git-bearing compound command it cannot statically verify — so `handoff`,
  `continue-in-background`, `workflow`, `running-retro`, `orient`, `retro`, and `find-handoff` all
  failed at load with `this command is too complex to verify that it stays inside the worktree`.
  The failure hit hardest exactly where these skills matter most: an isolated parallel agent could
  not write a save-point, orient itself, or recover a handoff.
  - The git lines are removed from each skill's pre-compute block and re-acquired in the skill body
    as **individual** Bash calls, one command per call. Non-git pre-compute lines are untouched —
    they were never the problem (`knowledge:course-digest`, four complex non-git lines, loads fine
    under isolation).
  - The old lines carried caps (`git status --porcelain | head -20`) and `2>/dev/null || echo`
    fallbacks that a plain Bash call does not reproduce. Both are restated as reading rules: treat a
    failed command as "unknown, carry on", and honor the 20-entry bound **when reading** rather than
    re-adding a `| head -20` pipe — a piped git command is compound, which is the shape that started
    this.
  - `find-handoff` is the proof that line count is not the trigger: it carried a single, pipe-free
    git line among three non-git lines and was refused, while a skill whose *only* pre-compute line
    is a compound git command loads. The rule is git-in-a-composed-block, not per-line complexity.
  - `shell: bash` is deliberately left in place on every affected skill, including `workflow`, which
    now has no `!` lines at all. The key is inert without pre-compute lines, and removing it is a
    frontmatter-contract change with no behavioral benefit.
  - What was verified, precisely: from an `Agent` with `isolation: "worktree"`, the **unfixed**
    skills were observed to be refused, plain git commands were observed to succeed as individual
    Bash calls, and a multi-line non-git pre-compute block was observed to load
    (`knowledge:course-digest`, the positive control). The **edited** skills have not been invoked
    from an isolated agent: skills load from the version-keyed plugin cache, so `0.17.15` does not
    exist there until this ships and plugins are updated. Confirm then. CI cannot prove this fix —
    it never invokes a skill from an isolated agent.

## [0.17.14]

### Fixed

- **`orchestrate`'s nested-subagent sources were stale, but not in the direction the audit reported
  (melodic-software/claude-code-plugins#1479 audit follow-up).** The audit's top finding claimed
  `SKILL.md`'s "a configurable default of three" was factually wrong and that nesting is off by
  default. Re-verification refutes that: the byte-exact changelog records v2.1.219 —
  "Subagents can now spawn nested subagents up to depth 3 by default (was 1); set
  `CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH=1` to disable nesting" — and the harness agrees (a non-fork
  subagent one layer down held a fully-schema'd `Agent` tool on 2.1.220 with the variable unset).
  The finding had been drawn from the `sub-agents` prose page, which still documents the superseded
  v2.1.217–2.1.218 off-by-default state. `SKILL.md`'s claim stands; what changed is where it is
  sourced from.
  - `context/sources.md`'s imperative-5 block is rewritten to current text. Its previous quotes
    ("a background subagent at depth five does not receive the Agent tool", "The limit is fixed and
    not configurable") no longer appear in the page and are contradicted by the env var existing.
    The block now carries version-pinned changelog quotes for the depth default, the current
    tool-list gating sentence, all three separately-overridable caps with their defaults, and an
    explicit drift note recording that the two official surfaces currently disagree and which one to
    believe for what.
  - `SKILL.md`'s depth paragraph re-attributes the depth-3 default to the changelog (which carries
    it) rather than the `sub-agents` page (which currently contradicts it), pins each state to its
    version, and adds a **confirm-nesting-from-behavior** rule: have a worker of the *same agent
    definition* you plan to use as the intermediate tier attempt a trivial nested spawn and report
    the outcome before committing a design to a second layer — a tree authored from either page
    alone can be wrong in both directions; the gate is definition-specific, so a spawn from another
    agent type proves nothing; and holding `Agent` is necessary but not sufficient, since the tool
    can be listed while the spawn is still refused.
    A refusal is then read rather than assumed: a depth rejection names depth, while a permission
    refusal says nothing about the ceiling, because spawns are classifier-evaluated before launch
    (v2.1.178).

### Added

- **A non-binding size anchor for imperative 7's small/medium/large.** The sizing had no numeric
  reference at all, leaving it rationalizable either way. The Tiered-delegation section (which the
  export brief omits, keeping the pasted brief model- and tool-agnostic) now cites the platform's
  own numbers — the `/config` workflow size guideline's "fewer than 5 / 15 / 50 agents" and the
  `Large workflow` flag above 25 — as a reference point, with an explicit instruction to say which
  one you are overriding when your sizing and the anchor disagree by an order of magnitude.
- **The priming addendum now reads the session's own effort level** via the documented
  `${CLAUDE_EFFORT}` substitution, closing one of the two calibration factors imperative 7 named
  with no consumable signal. It is the level a spawn inherits when neither the call nor the agent
  definition sets one — a definition's own `effort` frontmatter overrides the session — which is
  precisely the over-provisioning imperative 7 exists to stop. Priming-only and export-omitted, so
  the pasted brief stays agnostic; the addendum also notes `ultracode` reports as `xhigh` and so
  cannot reveal whether script-held workflow orchestration is active.
- **`context/gotchas.md`** — the skill had no gotchas surface (a `skill-quality:check` warning). It
  records four earned failure modes: the nesting ceiling outrunning the prose docs, a denied spawn
  being misread as a depth answer, a clean worker return that is a wrong-target return, and priming
  being mistaken for emitting. Routed from the Purpose section alongside `context/sources.md`, so it
  actually enters working context — a spoke the hub never points at clears the static check without
  changing behavior.
- **Two eval cases covering decision-criteria quality, not just export mechanics.** The existing
  five all tested formatting and emission; nothing exercised the judgments the skill is for.
  `sizes-small-ask-single-agent` forces a size classification on a concrete small ask, and
  `tiers-wide-fanout-cheaper-default` asserts the cheaper-tier default at wide fan-out with the
  judgment-heavy stage kept as the explicit exception.

## [0.17.13]

### Added

- **Handoff structure doc hardened from the upstream handoff-failure corpus audit
  (melodic-software/claude-code-plugins#1477).** Two write-side rules added, both adopted because a
  real failure mode upstream demonstrated the gap and nothing in the existing template guarded it:
  - **Claim provenance.** A status claim may be stated plainly only when this session verified it;
    anything inherited (a prior handoff's assertion, an issue label, a remembered state) carries an
    explicit `UNVERIFIED (<source>)` marker — an inherited claim is a claim to falsify, not a fact
    to forward. Closes the laundering gap where an unverified "not built yet" forwarded as fact
    causes the resuming session to rebuild something that already exists. The existing
    fresh-reads-this-turn checklist items governed only what the writing session could probe; they
    said nothing about claims the session inherited and could not probe. Lives in `save-point.md` as
    a BOTH-paths rule (mirroring the existing redaction pass) — `reference/structure.md` points to
    it for the full-file path's body sections, and `skills/handoff/SKILL.md`'s prompt-only checklist
    carries its own tick so an inline remaining-work bullet cannot forward an inherited claim
    unmarked either.
  - **Edge-case re-scan for Constraints that must hold.** Before closing the section, re-scan for
    *but* / *except* / *unless* / "the exception is" / "the corner case" — those words mark
    mid-discussion constraints that never rose to a top-line bullet, the category a resuming session
    ships as a bug. The template forced the section to exist but had no recall step for constraints
    buried inside accepted decisions. After an unexpected compaction the model-visible conversation
    is the summarizer's output, not the original turns, so `reference/structure.md` now requires the
    section to say explicitly whether it re-scanned the lossless on-disk transcript (`retro`'s
    parser reads the same record) or is disclosing that pre-compaction turns went unscanned — never
    presenting a post-compaction scan as complete without saying which.

## [0.17.12]

### Added

- **The detached observer's distilled observations now carry enough structure for the headless
  running-retro analysis to COMPUTE sequencing/batching/dependency claims, not just drop them.**
  `summarize_record()` previously stripped every tool call down to its name and every tool result
  down to a bare count, so `observer.py`'s headless `_analysis_prompt` — despite instructing the
  analyzer to "group tool-use events by API message id" and check for a dependency before flagging a
  missed-batching Efficiency finding — had no field it could actually compute either claim from. Two
  additions close the gap: an assistant event now carries `mid` (a bounded correlation key derived
  from the transcript's own API message id, when present) so events sharing one `mid` can be
  recognized as one batched turn versus separate sequential turns — verified against real session
  transcripts (of 6,352 tool-bearing message ids across 200 live sessions, 1,412 (~22%) spanned 2+
  tool-bearing records, confirmed again as a positive control against this repo's own session
  transcripts, 580/5,431 (~11%)), so `mid` — not record adjacency — is what makes batching computable
  at all — and both assistant
  (`calls[].in`) and user (`results[].out`) events now carry a bounded (80-char) preview of each tool
  call's input/result, keyed by a bounded correlation id, so a later call's input can be checked
  against an earlier call's output for a genuine dependency. Both fields are omitted (not padded) when
  the underlying data isn't present, and ids are shortened to an 8-char correlation key rather than
  persisting the full opaque id. This measurably grows the observations file on tool-heavy sessions:
  re-measured against the final schema over 24 real session transcripts carrying 20+ tool-bearing
  records each, distilled by this version and by the version it replaces, the observations grow
  **61.9% in aggregate** (per-file mean 63.0%, median 61.4%, range 43.7–116.0%). The growth is
  almost entirely the preview content itself, which is the point — a real, bounded,
  single-analysis-call cost against a cheap model, not an unbounded one. Every field has a hard cap,
  and the flags below are emitted only when they apply. Redundant/wasteful bytes (verbose ids, a
  `tool_results` count now superseded by `len(results)`, JSON-dumping a tool-result content-block
  list instead of extracting its text) were cut wherever doing so didn't reduce the analyzer's
  actual computing capability.
  Every bounded field pairs with an out-of-band flag when the preview is incomplete (`cut` on a
  `calls`/`results` entry, `say_cut`/`human_cut` beside the narration), so a value cut short of a
  dependency reads as unknown rather than as a clean absence that would license an
  asserted-and-wrong finding. The flag is out-of-band rather than a trailing marker in the text
  because an in-band marker can't be told apart from a value that genuinely ends in those characters
  (a complete tool result reading `Processing complete...`), which would suppress computable
  findings in the other direction. `cut` also covers a mixed content-block result — text alongside
  an image or document block keeps only the text, so the preview is incomplete even though it fits
  the limit. A `results` entry additionally carries `err` when the call failed, because a failed
  call's own output preview is routinely empty and a later retry is control-dependent on having
  seen that failure.
  `_analysis_prompt` updated to reference the new fields and flags. Its dependency check is now five
  explicit places rather than two, any one of which makes a sequential pair correctly sequential:
  it compares the earlier call's own `calls[].in` against the later call's, since a side-effecting
  call (`mkdir` before a `Write` into that directory) returns nothing and narrates nothing so a
  result-only comparison read a required sequence as a missed batch; it treats a state-wide consumer
  (a build, test, lint, typecheck, or VCS command) after a state mutation as dependent even though
  neither input names a shared path, since `Edit foo.py` then `Bash pytest` is the most common
  sequential pair in a coding session and the resource comparison structurally cannot see it, with an
  undecidable mutation dropping rather than routing; and it treats a retry after an
  `err` result as control-dependent — recognized by a shared resource, repeated arguments, or a
  visible correction of the failed input (`git stats` → `git status`), but never by tool name alone,
  since a failed `Read` of one file followed by a `Read` of another is two independent calls.
  Where a failure sits in the pair and none of that evidence is legible, the pair is unknown rather
  than independent and the claim is dropped — a failure between two calls is never license to report
  a missed batch. A candidate pair must also sit inside one user turn — no
  intervening `human` or `turn_boundary` event — before the dependency test runs at all, since two
  calls answering different human prompts could never have been batched however independent they
  are. That precondition needs the boundary to be visible, and keying it off extractable text left it
  invisible in every session carrying no `stop_hook_summary` record at that point — a prompt encoded
  as `content: ["next request"]` (a bare string, which retro's canonical `parse_transcript.py`
  already counts as a human message) emitted no `human`, and an image- or document-only prompt yields
  no readable narration at all, so calls answering prompts on either side became a candidate pair.
  `summarize_record()` now reads a bare string as a human message like a `text` block, and marks the
  boundary STRUCTURALLY: any user record carrying content that is not a `tool_result` is the human
  speaking — text, a bare string, an image, a document, or a block type that does not exist yet —
  while a pure tool-result record stays inside the turn, since marking those would split every
  genuinely batched turn and suppress real findings. Its grouping rule no longer both asserts sequential
  execution for a missing `mid` and calls
  that case uncomputable — a missing grouping key is now uniformly uncomputable, never evidence of
  sequential execution.
  `tools` is unaffected and still carries the tool-call names a "delegation" finding needs (a Task/
  Agent tool name), so delegation required no new field — the gap #1485 closes is sequencing/batching/
  dependency only. The in-session checkpoint path (which reads the raw transcript directly) is
  unaffected. Follow-up from #1473 (PR #1482) and Codex's review of it — filed as #1485, scoped to the
  schema change deferred out of that PR. This supersedes the headless prompt's 0.17.5 caveat that
  `summarize_record()` never preserves a message id: it now does, so the prompt's absent-key wording
  is scoped to the per-record case (the raw record carried no id) rather than to the schema.

## [0.17.11]

### Fixed

- **Two surfaces still described the pre-0.17.9 re-arm shape.** 0.17.9 made the loop re-arm one
  counted, length-delimited entry per surviving loop, but `handoff`'s gotcha entry was not swept
  with the rest — it still warned about "an active `/loop`" singular and called the re-arm a single
  unstructured follow-up message, which is the shape the engine stopped emitting. It now names the
  one-per-loop rule and the counted header, so the checklist, the engine doc, and the gotcha say the
  same thing.
- **The entry header no longer spells out an ungrammatical worked example.** `<L>` is a fixed
  `lines` token deliberately — a parser should not need English plurals to find a boundary — but the
  no-launch-signal fallback illustrated it as the literal `Re-arm 1 of 1 — 1 lines:`, putting
  "1 lines" into terminal output an operator reads. The invariance is now stated once as a property
  of the header, and both the engine doc and `find-handoff` reference the generic form, so the
  fallback needs no example of its own and `1 lines` reads as well-formed rather than as drift.

## [0.17.10]

### Fixed

- **`observer.py`'s `_pid_alive` Windows liveness check no longer assumes a fixed decoder for
  `tasklist` output.** #1483/#1496 (0.17.7-era) hardcoded `encoding="utf-8"` with
  `errors="replace"` on the `subprocess.run` call. `tasklist`'s piped output actually follows the
  **console output code page**, which is not fixed — measured on one machine, the same command in
  the same session returned UTF-8 bytes under `GetConsoleOutputCP=65001` and CP437 bytes under
  `GetConsoleOutputCP=437` (two shells in one session genuinely disagreed), so a hardcoded `oem`
  would have been wrong in the opposite direction just as often. Before #1496's `errors="replace"`,
  a CP437 console plus a process name containing an undefined-in-cp1252 byte (e.g. `ü`) raised
  `UnicodeDecodeError` inside `subprocess`'s reader thread, leaving `out.stdout` as `None` and
  `str(pid) in out.stdout` raising out of `_pid_alive` — `errors="replace"` closed that crash path
  but left the decoder assumption in place as a correctness smell (harmless today only because the
  predicate matches ASCII digits, which mojibake in a process *name* cannot change). `_pid_alive`
  now drops decoding entirely and matches `str(pid).encode("ascii")` against `tasklist`'s raw
  `stdout` bytes, removing the code-page question from the call site altogether (#1512).

## [0.17.9]

### Fixed

- **The multi-loop re-arm landed on the producer only, so recovery and the handoff checklists still
  spoke of one loop.** 0.17.8 taught `save-point.md` to emit "one re-arm message per loop left
  standing", but the surfaces that consume that output were not moved with it: `find-handoff`'s
  capture step asked for "the re-arm instruction" and matched a single `send /loop …` shape, its
  confirm gate surfaced the note "when one was found", and both of `handoff`'s enforcement
  checklists still read "if a loop is active, a below-the-rails note". A handoff written with three
  surviving loops therefore recovered one of them and dropped two after `/clear` — the producer-side
  failure 0.17.8 fixed, reintroduced one layer down in the consumer, which is the same shape as the
  two recovery defects already fixed in this series. The capture now keeps matching past the first
  hit; the confirm gate surfaces all of them; the redaction invariant and the
  *does NOT do* list are pluralized so they cannot be read as licensing a single-note recovery; and
  `save-point.md`'s own detection contract names the recoverable unit as every re-arm message the
  producer wrote, so the two sides state one rule.
- **The re-arm entries are length-delimited, so an arbitrary multi-line loop prompt survives
  recovery.** The producer quotes the original prompt verbatim and a `/loop` prompt can carry
  newlines, so an entry is not reliably one physical line — and no content test can bound it.
  Matching command wording cuts the first multi-line prompt in half and swallows every entry behind
  it; a marker fares no better, since a verbatim prompt is allowed to contain whatever marker is
  chosen and would then split its own command. Each entry is now headed
  `Re-arm <i> of <n> — <L> lines:` with the body on exactly the next `<L>` lines, and the block is
  emitted last in the message. Counting lines is the one boundary that cannot collide with what it
  delimits. `<n>` is retained as a self-check rather than a scanner: `find-handoff` reports what it
  recovered against what the producer said it wrote, instead of presenting a subset as the whole
  set. `save-point.md`'s detection contract states the same boundary, so the stable contract an
  agent reads cannot send it back to the wording match its consumer no longer performs.

## [0.17.8]

### Fixed

- **The save-point engine's resume prompt dropped the `/loop` wrapper.** The engine doc's
  goal-aware re-arm rule ("Emit the copy/paste resume prompt") had no loop-aware counterpart, so a
  resume prompt written for a session running under `/loop` read as a bare continuation task.
  Pasted after `/clear` — which clears every session-scoped scheduled task
  (<https://code.claude.com/docs/en/scheduled-tasks#limitations>) — that ran the continuation once
  and silently dropped the recurring behavior, with no error to signal it. `save-point.md` now
  carries a loop-aware re-arm rule: the rails block stays the unwrapped resume directive, and a note
  below the bottom rail has the reader send `/loop [<interval>] <original prompt>` as a SEPARATE
  follow-up message, quoting the interval and prompt verbatim from the launch turn. The re-arm
  carries the ORIGINAL loop prompt rather than the resume directive because `/loop` re-runs the
  prompt it was given on *every* iteration
  (<https://code.claude.com/docs/en/scheduled-tasks#run-a-prompt-repeatedly-with-%2Floop>) while a
  save-point is an immutable record of one moment — wrapping the directive would make every later
  tick re-read that frozen file and replay an already-finished remainder instead of doing the loop's
  actual recurring job. Order is stated (bootstrap first, re-arm second) so the re-armed loop's first
  iteration cannot run ahead of the continuation it resumes into. Both re-arm rules now key off a
  concrete conversational signal — this session's own `/loop` launch turn (corroborated, never
  gated, by a later `ScheduleWakeup` reschedule) and an established `/goal` call — rather than
  "infer from conversation" prose. Neither re-arm can ride inside the other's prompt argument, since
  a command is recognized only at a message's start
  (<https://code.claude.com/docs/en/commands>), so each is its own message: `/goal` keeps the first
  line between the rails, `/loop` follows separately. The launch-turn signal is read as a set rather
  than a single find: a session can hold up to 50 scheduled tasks at once
  (<https://code.claude.com/docs/en/scheduled-tasks#manage-scheduled-tasks>) and `/clear` takes all
  of them, so the rule enumerates every surviving loop and emits one re-arm message per loop —
  a singular rule would have preserved one and silently dropped the rest. Elapsed time retires a
  launch from that set alongside an explicit stop: a recurring task expires seven days after creation
  (<https://code.claude.com/docs/en/scheduled-tasks#seven-day-expiry>), so a launch turn older than
  that is already gone and re-arming it would resurrect a schedule that had already ended.
  `handoff/SKILL.md`'s two enforcement checklists and `handoff/context/gotchas.md` are updated to
  match.
- **Lost-handoff recovery dropped that same `/loop` re-arm.** The re-arm note is the one piece of a
  resume prompt that cannot sit between the rails — a command is recognized only at a message's
  start (<https://code.claude.com/docs/en/commands>), so it is a separate follow-up message and its
  instruction lives below the bottom rail. `find-handoff` recovered only the block between the
  rails, so an operator who ran `/clear` before copying and then recovered the handoff got the
  continuation back and the loop not at all — the very failure the re-arm rule exists to prevent,
  reintroduced one layer down. `save-point.md`'s detection contract now defines the recoverable
  resume prompt as the rails block PLUS the below-rail re-arm note, and `find-handoff` captures it
  (shape-matched and anchored to the bottom rail, on both file and prompt-only modes) and surfaces
  it at the confirm gate. The capture is deliberately not a detection key — it is read only from an
  already-qualified candidate, so it admits no new false positives — and it runs through the same
  redaction pass as everything else, since it quotes the operator's original loop prompt verbatim.
  The capture also runs on the known-location glob short-circuit, which reaches the confirm gate
  without a transcript in hand: it pulls step 5's `session_id` → `<session_id>.jsonl` lookup ahead
  of the gate and reads that one file's tail, so the default discovery path surfaces the note too
  rather than promising it and delivering nothing.
  The note is bound to its candidate by content — the rails block whose `Read @…` directive names
  that exact file — rather than by reading the transcript's tail, since one session can emit
  several handoffs and a loop stopped and relaunched between them would otherwise re-arm the wrong
  recurring work. Same correlate-by-content rule the background-delivery screening already uses.
- **The `/loop` re-arm note is now conditioned on the paste, not on the citing skill.** The engine
  is shared with `/session-flow:continue-in-background`, whose successful launch clears nothing and
  pastes nothing — it hands the rails prompt straight to a detached agent, so the loop stays armed
  on the foreground session and the note's unconditional "after pasting the block above" wording
  described a paste that never happens. Keying the note off the citing skill would have been just
  as wrong in the other direction: the engine emits the prompt BEFORE that skill's dirty-tree gate
  and launch run, and either can fall back to `/clear`-then-paste, which does clear. The note is
  therefore worded conditionally — re-arm if you paste after `/clear`, including on those
  fallbacks; a launch that succeeds needs none. Transferring the loop *into* the launched agent is
  deliberately not done: arming a recurring schedule inside a detached session the operator is not
  watching is a behavior to decide on its own merits, not a side effect of writing a save-point.

## [0.17.7]

### Fixed

- **`observer.py`'s `_pid_alive` Windows liveness check now decodes `tasklist` output as UTF-8
  explicitly.** Its `subprocess.run` call passed `text=True` with no `encoding=`, so Python fell
  back to the platform code page (cp1252 on Windows) instead of UTF-8 — the same class of defect
  `_run_analysis`'s subprocess call was fixed for (#1472). Currently harmless in practice (the only
  check is an ASCII integer substring match against `tasklist`'s stdout), but left implicit it
  risked the same silent-corruption pattern if the check's output-parsing ever changed.
  `errors="replace"` is set alongside it for the same reason as `_run_analysis`'s fix: a
  truncated/invalid byte sequence decodes rather than raising. A full sweep of every other
  `subprocess.run`/`subprocess.Popen` and `open()`/`read_text`/`write_text` call across
  `session-flow`'s production scripts (`observer.py`, `arm_observer.py`,
  `retro/scripts/parse_transcript.py`) found every other text-mode call site already
  UTF-8-explicit or intentionally binary (`"rb"` mode, or a raw `os.open` file descriptor with no
  text decoding involved) (#1483).

## [0.17.6]

### Fixed

- **`running-retro`'s detached observer launcher can spawn again — both the manual `arm` action and
  the opt-in SessionStart auto-arm hook were dead.** `arm_observer.py`'s spawn call referenced an
  undefined `observer` name for the child process's working directory (the resolved script-path
  variable is `observer_py`), raising an unhandled `NameError` on every invocation. Both entry points
  route through this same launcher, so the entire detached-observer feature was inoperable on any
  platform. Fixed the undefined name and widened the narrow `except OSError` guard around the spawn
  call to catch any spawn-time exception, so a future failure at that call site degrades gracefully
  (`observer: failed to spawn: ...`, exit 0) instead of escaping as a raw traceback.

## [0.17.5]

### Fixed

- **running-retro's analysis prompts had no rule requiring structural transcript claims to be
  computed rather than asserted.** An independent fresh-context validation found the checkpoint
  analyzer accurate on findings that harvested the session's own self-declared observations but
  0/2 on independently inferred structural claims (tool-call sequencing/batching/delegation,
  "emerging pattern" occurrence counts) — one asserted-and-wrong claim routed as a tracker issue a
  human would have filed for a non-problem. Both callers of the checkpoint method now carry a
  compute-don't-assert rule naming the observed failure modes: the in-session checkpoint
  delegation (`context/checkpoint.md`'s Method section and delegation prompt template) and the
  detached observer's headless analysis prompt (`observer.py`'s `_analysis_prompt`, which has no
  delegation prompt to fall back on and needed the rule inline). A structural claim that can't be
  computed from the record must now be dropped rather than asserted uncomputed (#1473). The
  headless prompt's message-id-grouping guidance now notes explicitly that the distilled
  observations it receives may not carry a message-id field at all — `summarize_record()` never
  preserves one — so an absent field reads as uncomputable rather than as license to assert from
  impression. The compute-don't-assert rule now also covers the judgment built on top of a
  computed structural fact: a correctly computed sequencing fact does not by itself prove a missed
  batching opportunity (genuinely dependent calls are correctly sequential, not a miss), so both
  prompts now require checking for a dependency before routing an Efficiency finding for
  unbatched/sequential calls — and that check is not narrowed to data flow alone: a control,
  resource, or side-effect dependency (e.g. a directory created before a file is written into it)
  is just as real a reason two calls had to run in order.

## [0.17.4]

### Fixed

- **The running-retro detached observer's analysis subprocess no longer flashes a visible console
  window on Windows, and no longer corrupts non-ASCII ledger entries into mojibake.** `observer.py`'s
  `_run_analysis` called `subprocess.run` for the headless `claude -p` analysis pass with no
  `creationflags` (unlike `arm_observer.py`'s own windowless `spawn_detached`, whose flag set was
  never carried to this later call) and no explicit `encoding=`, so Windows decoded UTF-8 output with
  the platform's cp1252 default. Both are now set explicitly: `CREATE_NO_WINDOW` on Windows only, and
  `encoding="utf-8", errors="replace"` unconditionally — `errors="replace"` keeps a truncated/invalid
  byte sequence from raising past the surrounding `TimeoutExpired`/`OSError` handling (#1472).

## [0.17.3]

### Fixed

- **The shared concern-value parser no longer reads a declared key as absent over YAML key spacing.**
  `parse-concern-value.sh` anchored on the exact regex `^<key>:`, so `memory_dir : .work` (YAML
  permits whitespace before the `:`) and a root block mapping written at a uniform indent both
  resolved to the caller's fallback — substituting a value the repo never chose for one it did.
  Both shapes now resolve, matched at the document's own base indentation so a same-named key
  nested under another mapping never answers for the root one — including when the root key is
  present but deliberately empty. Synced from `lib/parse-concern-value.sh`; version bumped so installed
  copies receive it.

## [0.17.2]

### Fixed

- **Setup's headless reconfigure recipe no longer claims `-y` is CLI-required for a non-TTY
  `uninstall`.** Verified against the live CLI (2.1.220) and current docs: `-y` only skips
  `uninstall`'s `--prune` confirmation, and this recipe never passes `--prune` — so `-y` had no
  effect and is no longer part of the recipe (#1410).

## [0.17.1]

### Changed

- **Setup's `apply` now documents the headless reconfiguration route beside the interactive one.**
  Every observer tunable is native `userConfig`, and `apply` routed reconfiguration through
  `/plugin configure session-flow` only. A headless or CI consumer reading that had no path at all,
  and the obvious guess — re-running `claude plugin install --config` — silently does nothing on an
  already-installed plugin, so the reader would have concluded the value was set when it was not.
  The flag's fresh-install-only behavior is now stated where the reconfiguration guidance lives,
  along with the uninstall-then-reinstall route it forces and the note that one install should carry
  every key being changed. The recipe passes `-s <scope>` on both halves and `-y` on the uninstall:
  both commands default to `-s user`, so an unscoped pair removes a separate user record while a
  project- or local-scoped install keeps loading, and a non-TTY uninstall requires the confirmation
  flag to run at all.

## [0.17.0]

### Changed

- **handoff: the save-point body-section taxonomy is restructured.** The old eight sections led with
  the costly layer — a resuming session learned what to do next in section six of eight — which
  inverts the ladder the org's `progressive-disclosure` convention prescribes. The set now opens
  with a six-line `Resumption brief` a reader can stop at, and the remaining sections are ordered
  frame, world, memory, frontier. Three kinds of state that previously had no home are now owned:
  invariants that must hold, persistent side effects that must not be repeated, and hard-won
  findings that are neither a decision nor a failed approach. `Open questions / next steps` is split
  four ways — a slash in a heading meant it owned more than one taxon, and its numbered list mixed
  the ordered remainder of the work with self-resolvable unknowns and outside blockers — and the
  `Progress` / `Files modified` overlap is resolved into a single file-role map. Every section is now always
  present, with an explicit "nothing to report" rather than an omission, so a cold reader can tell
  silence from oversight. The file-role map owns *how far each file's change got*, not just its
  role: the old blanket "nothing about what changed inside it" left completed progress and
  half-finished uncommitted edits with no owner at all — completion criteria describe outcomes and
  the ordered remainder describes future work — so a cold session had to reconstruct both from the
  working tree, the exact rediscovery this document exists to prevent. Committed work still points
  at its commit range rather than transcribing a diff; uncommitted or half-done work says which part
  is implemented and working and which part is not, because no commit records that.
- **handoff: the emitted resume directive no longer names a section.** It read
  `continue per its "Open questions / next steps"`; it now reads `continue its remaining next steps`.
  The heading was the only runtime coupling to the taxonomy, so the section set can move again
  without touching `save-point.md`, and handoffs already on disk stay resumable. Nothing parses a
  handoff body heading, so existing save-points are unaffected.
- **handoff: consumers cite the section list instead of restating it.** `save-point.md` carried a
  full inline recap that had already drifted from the owner doc on two of eight names, and four more
  files carried partial or differently-spelled copies — one section had accumulated five spellings.
  Per the org's `reference-dont-duplicate` convention a closed enumeration is a mapping table that
  must be cited, never recapped, so `reference/structure.md` is now the single home and the copies
  are pointers.
- **handoff: the "all eight body sections present" checklist assertion is retired.** A count is
  satisfiable by eight wrong sections, it has gone stale before, and it duplicated a value derivable
  from the doc it described. The checklist now walks the structure doc.
- **orchestrate: documents the shape of a multi-tier delegation tree** — what the top tier owns,
  why coordination belongs low in the chain, what a tier-crossing return payload should carry,
  ephemerality as a cost control rather than tidiness, and why a clean worker return is not
  evidence of a correct one. No new machinery; the existing imperatives already permit the tree,
  this names its shape.

### Removed

- **handoff: the write-only `previous_session_id` frontmatter field.** The chain walker
  (`skills/retro/scripts/parse_transcript.py`) only ever read `session_id` and `previous_handoff`;
  the third field was written by the spec, asserted by five documents, seeded by test fixtures, and
  consumed by nothing. Storing the prior session's id in a second place invited the two pointers to
  disagree — the walker resolves it by reading the prior file's own `session_id`. Chain-walking is
  unchanged, verified by the existing chain tests with the field removed from their fixtures.
  The `running-retro` ledger's own `previous_session_id` is a separate, live field and is untouched.

## [0.16.0]

### Added

- find-handoff: new skill (#976). Recovers a lost handoff after `/clear` — the
  failure mode where `/session-flow:handoff` wrote a save-point but the operator
  cleared the session before copying the dashed-rail resume prompt, leaving the
  fresh session with zero context and no path to the handoff on disk. Runs a
  read-only detection ladder: known-location glob of the current repo's
  `<memory_dir>/handoffs/`, then a bounded, recency-ranked scan of transcripts
  (excluding the current session's own file — `/clear` opens a new transcript in
  the same project dir, so the pre-clear content is a sibling) for the handoff
  directive and dashed-rail markers, then a confirm-before-resume gate. Detection
  is substring matching over transcript JSONL (empirically verified: the
  `Read @…-handoff-*.md` directive and `─` rails survive verbatim), not JSON
  parsing — so the skill ships no parser and does not couple to `retro`'s
  transcript parser. Handles both handoff output modes (file-based and
  prompt-only, which writes no file). Read-only and redaction-aware throughout:
  surfaces only the resume prompt + handoff metadata, never raw transcript
  content. Routes to `/session-flow:keep-going` when the recovered session ended
  mid-work. Chains in from `keep-going` step 4 when a post-`/clear` session has no
  known handoff path.

### Changed

- reference/save-point.md: documented the resume-prompt output shape (the
  `Read @…-handoff-*.md` directive, the `─` rails + instruction line, and
  `Prior session: <UUID>`) as a stable detection contract `find-handoff` keys
  off, so a future format change is a knowing break. reference/structure.md notes
  the `type: handoff` frontmatter is part of the same contract, and
  reference/topic-docs.md lists `find-handoff` among the skills that read the
  topic-docs binding to locate the handoffs directory. keep-going step 4 routes
  to `find-handoff` when the handoff path was lost.

## [0.15.2]

### Fixed

- **`reanchor`'s eval case 7 renamed off the pre-rename plugin name (`#1328`).**
  `skills/reanchor/evals/evals.json` still named the negative-routing case
  `negative-routing-rule-discipline-is-re-anchor-plugin` after the `re-anchor` -> `discipline`
  plugin rename (`#1276`); the case's `expected_output` and `expectations` were rewritten in that
  commit but its `id` field was missed. Renamed to
  `negative-routing-rule-discipline-is-discipline-plugin`, matching the sibling
  `negative-routing-*` case names. No other file references the old name.

## [0.15.1]

### Changed

- All five skills whose pre-computed context block injects the session id
  (`orient`, `retro`, `running-retro`, `handoff`, `continue-in-background`) now
  carry a `|| echo "unknown"` fallback on that injection, matching the sibling
  git injections in the same block. Injection failure, timeout, and stderr
  semantics are undocumented upstream, so the standing convention is a
  `|| <fallback>` on every injected command — `skill-quality:check` flags a
  missing one as an advisory WARN. On this particular line the guard is
  unreachable in practice (`${VAR:-unknown}` resolves at expansion time, so
  `echo` receives a formed string and exits 0); it buys block-wide uniformity
  and a quiet gate, not protection against a failure mode the sibling git lines
  genuinely have.

## [0.15.0]

### Added

- running-retro: detached-observer substrate + lifecycle. Evolves running-retro
  from PULL-only (invoked in-session) to a path that can also fire *after* the
  session ends — a `/loop` structurally cannot. A stdlib-only Python 3.10+ tailer
  (`skills/running-retro/scripts/observer.py`, launched detached by
  `arm_observer.py`) outlives the session, tails the transcript out-of-band at
  zero context cost via a no-persistent-handle poll→open→read-new-bytes→close
  loop (safe by construction against the Windows share-mode write edge), detects
  end by mtime-idle, then runs the same checkpoint method headless (a cheap
  `claude -p`) and appends the redacted findings to this session's ledger. The
  analysis run is Read-only (`--allowedTools Read` under `--permission-mode
  dontAsk`) — no code execution over untrusted transcript content — and is the
  single semantic redaction pass; the transient distilled observations are
  machine-local (`${CLAUDE_PLUGIN_DATA}/session-flow-observer/`) and deleted
  after use, so only redacted findings reach the durable ledger. Entry: a new
  `arm` action on running-retro is primary; an OPT-IN SessionStart hook
  (`observer_enabled`, default off — zero-config behavior unchanged) automates the
  same launcher, guarded against self-arming (`CLAUDE_CODE_ENTRYPOINT`, stdin
  `agent_type`, `source`, analysis-run marker). Untrusted-data boundary cites the
  shared `reference/off-thread-work.md`. Native Observer-Agents recorded as a
  deferred alternative (trigger: transcript-level feed / documented-stabilized
  upstream), substrate kept thin so migration stays cheap. Full substrate +
  lifecycle in `reference/observer.md`. The plugin now bundles twelve skills.
- setup: new check-centric skill (`disable-model-invocation`), added because the
  observer introduced an external prerequisite (Python 3.10+) and a `userConfig`
  surface — the uniform setup contract's trigger. `check` verifies the observer's
  prerequisites (Python 3.10+, `jq`, `claude` on PATH) and reports the effective
  config, flagging the `--bare`/OAuth-auth and idle-threshold hazards; no write
  path (reconfiguration routes through `/plugin configure`).
- `userConfig`: the plugin's first config surface — six observer keys
  (`observer_enabled`, `observer_analysis_enabled`, `observer_analysis_model`
  [default `claude-haiku-4-5`, the cost lever], `observer_analysis_bare`,
  `observer_idle_seconds`, `observer_max_seconds`), all defaulting to zero-config
  behavior.
- hooks: opt-in `SessionStart` hook (`hooks/observer-arm.sh`) — the plugin's
  first hook asset; no-ops unless `observer_enabled` is on.

### Notes

- `--bare` on the analysis run is off by default and gated behind
  `observer_analysis_bare`: verified on CLI 2.1.218, `--bare` drops the OAuth-login
  credential state and the run reports "Not logged in". The measured cost lever is
  the model, not `--bare` (which was a projected, never-measured optimization in
  the design memo). Enable it only where auth is an env-var API key that survives it.

## [0.14.0]

### Added

- reconcile: new skill. The prune-and-reconcile counterpart to
  `keep-going`'s resume — where keep-going asks "is it stuck, pick it back up",
  reconcile asks "is anything still running that should be retired, and
  does the task ledger
  match reality?" Inventories the off-thread work this session spawned, inspects
  each item's real state, retires the genuinely finished by clearing them from
  tracking, and closes this session's task-ledger items whose work is proven
  complete. Also reports the read-only liveness of sibling sessions in the same
  project — transcript mtime plus a coarse tail read, never a deep parse of the
  officially-unstable JSONL. Auto-settles the provably-finished (closing a task
  is evidence-gated — the mirror of keep-going's "never kill what you cannot
  prove is dead"); GATES any kill of still-running work, the gate kept in-skill
  because the three inventory skills' blast radii differ. Fixes this session
  only: sibling sessions are visible but report-only, and a spawned subagent's
  internal task list is not readable. MCP / browser / playwright tool-state
  enumeration is deferred with a trigger (no generic tool-state surface exists;
  closing user-owned state would be destructive-against-user). The plugin now
  bundles eleven skills.
- reference/off-thread-work.md: shared engine doc. The open-ended
  off-thread-work inventory kinds and the inspect-real-state-first invariant —
  the mechanics `keep-going`, `orient`, and `reconcile` all share (Rule of
  Three) — are extracted to a plugin-level reference all three cite via
  `${CLAUDE_PLUGIN_ROOT}`, each thinned to its own delta (same
  point-not-copy shape as `reference/topic-docs.md` and re-anchor's
  `context/re-anchor-audit-correct.md` engine doc). The three skills' autonomy
  gates are deliberately NOT extracted — different blast radii, kept in-skill.

### Changed

- keep-going: inventory + inspect steps now cite the shared
  `reference/off-thread-work.md` for the off-thread kinds and the
  inspect-real-state invariant rather than restating them inline; the duplicated
  "tools change over time" gotcha (now owned by the shared doc) is removed. The
  richer Active-verification protocol stays in keep-going (reconcile
  cites it). Description gains a reciprocal boundary line pointing at
  `reconcile` for
  retire/reconcile vs resume; all prior trigger phrases preserved.
- orient: the off-thread-work glance in "What it reads" now points at the shared
  `reference/off-thread-work.md` for the full open-ended kinds set while keeping
  its at-a-glance examples; no behavior change.

## [0.13.1]

### Changed

- Fresh-eyes review/verify delegation sites now prefer a cross-vendor
  advisor when one is installed, with the fresh-context same-vendor
  subagent as the stated fallback — presence-gated per the seam-phrasing
  convention (#933). `workflow`'s Review stage (`context/steps.md`) names
  the example command (the OpenAI Codex plugin, invoked per its own docs);
  `orchestrate`'s fresh-context-verify imperative states the preference
  tool-agnostically and names no command, because that imperative is
  exported verbatim into the skill's model- and tool-agnostic
  worker/handoff brief, where a named command would be exactly the
  unresolvable route the rule forbids.

## [0.13.0]

### Added

- continue-in-background: new skill (#233). Background delegation extracted from
  `/handoff --bg` into its own honestly named, discoverable entry point: produce a
  save-point, then launch a detached `claude --bg` session seeded with the rails
  resume prompt. Owns the delivery: explicit-intent hard gate (model-invocable for
  discoverability, but launches only on the user's explicit request — never
  self-elected, with an eval covering the gate), dirty-tree gate,
  launch + report, fallback-on-failure, and its own STOP rule. Also surfaces the
  The rails prompt is passed to the launch via a temp file rather than an inline
  heredoc — prompt content is untrusted session text, and a crafted line matching
  a heredoc sentinel could otherwise break out of the quoting into the shell; the
  resolved topic slug is sanitized to `[a-z0-9-]` before it reaches the `--name`
  flag for the same reason. Also surfaces the
  launched-session behavior the flag never documented: the agent is a NEW session
  that inherits neither the current session's CLI flags nor its model/effort
  choices — both resolve from the launch command's own flags and the launch
  directory's settings (per the agent-view and env-vars official docs, cited in
  the skill).
- reference/save-point.md: shared save-point engine. Save-point production —
  destination resolution, locate-position, full-vs-prompt-only choice, mandatory
  redaction pass, handoff-file write, rails resume prompt — extracted from the
  handoff skill into a plugin-level reference both delivery skills cite via
  `${CLAUDE_PLUGIN_ROOT}` (same shape as `reference/topic-docs.md`). No content
  duplicated in either skill; no runtime skill-to-skill invocation. The handoff
  document-structure doc moves with it (`skills/handoff/context/structure.md` →
  `reference/structure.md`) so the shared engine never reaches into one
  consumer's internal layout.

### Changed (breaking)

- handoff: `--bg` removed outright — no alias, no deprecation window. `/handoff`
  is now purely the manual `/clear`-then-paste save-point; background delegation
  lives in `continue-in-background`. The background trigger phrase ("continue in
  the background") moves from handoff's description to the new skill's — the
  trigger partition leaves zero overlap. Handoff's two `--bg` evals
  (no-launch-default, dirty-tree fallback) migrate to the new skill's eval set,
  rephrased for the new entry point; handoff keeps default-path coverage.

### Fixed

- retro / handoff: reconciled the "declared save-point" vocabulary mismatch between the
  retro multi-session snippet and the handoff skill's "Where handoffs live". Both now
  consistently name the CLAUDE.md/`.claude/rules`-inferred rung-2 value a **working-docs
  convention** resolving the memory-tier ROOT (`memory_dir`) — never the full handoffs
  path directly. Previously, a declared handoffs location such as `.claude/handoffs`
  passed through retro's snippet doubled into `.claude/handoffs/handoffs` because the
  snippet's "save-point convention" label implied a full location while its code appended
  `/handoffs` to it. The snippet's env var is renamed `DECLARED_SAVEPOINT` ->
  `DECLARED_MEMORY_DIR` to match. The snippet also no longer silently swallows a missing
  handoff chain: an empty `ls` result now surfaces an explicit fallback message and drops
  to the single-session parser form instead of passing an empty `--chain-from` value.

## [0.12.3]

### Changed

- orchestrate: sharpened imperative 7's per-worker tiering into an explicit volume-based default.
  Past a wide fan-out the cheaper tier is now the DEFAULT the whole fleet inherits (volume
  multiplies every notch of over-provisioning), with an explicitly-hard stage (verify,
  judge/adjudicate, judgment-heavy synthesis) as the standing exception that keeps the parent
  tier — closing the residual enhancement from the spawn-inherit fix. Tier is also broadened
  beyond model to reasoning effort: the doc-confirmed per-worker `effort` lever means a cheaper
  tier can be a cheaper model, a lower effort, or both. Guidance stays model-/tool-agnostic in the
  imperatives and export brief; the version-pinned platform specifics behind it (the fleet-model
  inherit mechanism, the platform's own wide-run threshold, and the `effort` enum) are recorded as
  citations in the skill's `context/sources.md`.

## [0.12.2]

### Changed

- Skills with `!` dynamic-context injections now declare `shell: bash` explicitly, per
  the pinned precompute convention — bash-only pipelines must not fall through to a
  PowerShell host.

## [0.12.1] — 2026-07-21

Changed:

- handoff: the "Full-path write procedure" doc's `MEMORY_ROOT` placeholder
  note now points at the shared `parse-concern-value.sh` helper (the
  retro skill's Phase 1.1 snippet is the worked call form) instead of a
  bare "resolve it first" reminder with no mechanism named. Doc pointer
  only — the handoff skill has no script of its own to rewire.

## [0.12.0] — 2026-07-21

Added:

- orient: new skill. Read-only session orientation — answers "where do we stand,
  what are we doing, and why" by synthesizing both the live conversation and the
  durable, off-thread state a conversation does not hold: handoff save-points,
  the workflow checklist, running-retro ledgers (resolved through the plugin's
  topic-docs binding), plus git state, open PRs, open work-items, and a glance at
  off-thread work. It complements the built-in `/recap` (conversation-only,
  auto-fires) by adding the durable layer recap never sees; a skill cannot invoke
  `/recap` (built-ins other than a small allowlist are not Skill-invocable), so it
  synthesizes the conversation summary inline. Strictly read-only: it writes
  nothing, ends nothing, and routes rather than acts — freshness verification to
  `reanchor`, off-thread recovery to `keep-going`, next-stage to `workflow`,
  learnings to `retro`. The plugin now bundles nine skills.

Changed:

- keep-going: hardened. (1) Broadened from "after an interruption" to also cover
  a live-session poke — "check the monitor", "poke it", "is it stuck", "stop
  staring at it" — with an active-verification protocol: read the real
  monitor/subagent output first, treat progress-vs-elapsed as a suspicion-raiser
  only, and act on evidence; killing or restarting off-thread work is now gated
  as a side effect so live-but-slow work is not killed on a hunch. (2) Usage-limit
  stall fix: once a limit lifts and the session is executing again the block is
  already over, so it continues rather than summarizing-and-stalling; the
  time-vs-reset check is scoped to the orchestration case (a limited worker),
  reset information being available in-session only via the limit message text and
  interactive `/usage`. While still blocked it hands back via `/session-flow:handoff`
  rather than self-arming a scheduler. (3) Intent is inferred from the
  conversation, arguments optional. Existing recovery behavior and all prior
  trigger phrases are preserved.

## [0.11.0] — 2026-07-20

Added:

- running-retro: new skill. Takes an in-flight retrospective checkpoint
  mid-session — the live counterpart to `retro`'s end-of-session pass. Zero-arm:
  nothing to set up in advance, because the session transcript on disk is
  lossless across compaction (the same record `retro`'s parser already reads in
  production). The main agent contributes a 2-3 line subjective-state note — the
  one signal disk cannot hold — then delegates the analysis to a fresh subagent
  that runs `retro`'s parser and selectively reads flagged transcript spans,
  classifies each finding by category and suggested resolution route (CLAUDE.md
  fix / rule fix / skill change / new-skill candidate / tracker issue), and
  returns a compact findings block. Findings append to a cumulative running
  ledger — one stable file per session chain — resolved through the plugin's
  topic-docs binding (`<memory_dir>/running-retros/`, default
  `.work/running-retros/`, memory-tier, never committed). It captures and routes
  only: codification stays with `/session-flow:retro codify`, tracker filing is
  offered never automatic, the session is never scored, and the skill is
  non-terminating (unlike `handoff`, it does not `/clear`). A mandatory redaction
  pass runs on both the subagent findings and the ledger write. Composes with
  `/loop` for periodic checkpoints; ships no scheduler of its own. The plugin now
  bundles eight skills.

## [0.10.4] — 2026-07-20

Fixed:

- retro: the Phase 1.1 multi-session snippet no longer truncates a quoted
  `memory_dir` at an interior `#`. `HANDOFF_DIR` resolution now routes through the
  shared `parse-concern-value.sh` helper (materialized from
  `lib/parse-concern-value.sh`), which peels surrounding quotes *before* stripping
  comments, so `memory_dir: "a#b"` resolves to `a#b` rather than `a`. The snippet
  also surfaces resolution rung 2 — a save-point convention inferred from
  `CLAUDE.md` / `.claude/rules`, passed as `DECLARED_SAVEPOINT` — instead of
  collapsing straight from an absent concern file to `.work`; prose stays an
  inference source the agent resolves, not a machine key.
- retro: a comment-only `memory_dir` (e.g. `memory_dir: # use default`, YAML-null)
  now resolves through the fallback instead of being taken literally as
  `# use default/handoffs`, so the handoff-chain search degrades to the declared
  save-point / `.work` default rather than a bogus directory.

## [0.10.3] — 2026-07-19

Changed:

- workflow / retro: the override boundary is now explicit. The stage taxonomy
  and the pre-PR sequence skeleton (workflow) and the five scoring dimensions
  (retro) are documented as fixed plugin identity with no consumer-config seam
  to swap them — what adapts is stage execution, gate commands, and the
  conventions each dimension scores against, all flowing through the consumer
  conventions the skills already name, never by editing the plugin. Documents
  the existing boundary per the extensibility contract; no behavior change.

## [0.10.2] — 2026-07-19

Fixed:

- retro: the Phase 1.1 multi-session snippet now derives `HANDOFF_DIR` from the
  resolved `memory_dir` (reads the `.claude/topic-docs.yaml` concern file, falls
  back to `.work`) instead of hard-coding the bare default `.work/handoffs`. A
  copy-as-is run of the snippet previously bypassed the memory_dir seam, missing
  the handoff chain in any repo that relocates its memory tier.

## [0.10.1] — 2026-07-19

Changed:

- Topic-docs binding points instead of restating (fleet conformance wave,
  registry single-home): the binding doc no longer restates the contract's
  five-rung resolution order and runtime guards — it applies the contract's
  own sections and keeps only the plugin-specific no-project-root fallback
  detail.

## [0.10.0] — 2026-07-18

Added:

- clean-stop: new skill. Gets a session to a durable, linked stopping point
  before the machine may go away — inspect every repo/worktree touched, push
  unpushed or coherently committable work durable (surfacing ambiguous WIP and
  stashes rather than force-committing or dropping them), ensure every pushed
  branch has a PR, file follow-ups as issues linked to that PR, and put the
  resume context in PR/issue bodies (never only a local file) to a cold-agent
  acceptance bar. Prunes only provably-safe branches and worktrees; gates
  destructive cleanup on proven safety. Closes on a free-and-clear verdict or a
  named dangling list. It is the go/stop mirror of keep-going (which recovers
  after an interruption; this makes the interruption safe beforehand) and
  supersedes a local handoff when the machine itself may go away. PR / issue /
  worktree mechanics route to whatever capabilities are installed, falling back
  to direct git / gh. The plugin now bundles seven skills.

## [0.9.1] — 2026-07-18

Fixed:

- orchestrate: worker model tier is now an explicit spawn decision. SPEC EVERY SPAWN adds the
  model tier to the per-worker spec, and CALIBRATE TO CONDITIONS adds per-worker tiering (cheap
  tier for high-volume mechanical work, parent tier reserved for judgment-heavy
  synthesis/verify; wider fan-out defaults cheaper). Closes the failure mode where a wide
  fan-out silently inherited the parent session's premium model on every worker — an omitted
  model defaults to `inherit` per the subagents doc (resolution order and cost-control quote
  now cited in `context/sources.md`).

## [0.9.0] — 2026-07-18

Added:

- reanchor: new skill. Verifies a session's working assumptions against live
  reality before it builds on them — for the PRs/issues/branches a handoff or
  locked plan references it confirms each is still in the claimed state, reports
  current behind-base divergence, confirms cited skills/plugins still exist under
  that name and that installed versions match the repo source, and flags
  memory-tier entries whose subjects have since landed. It reports the drift and
  re-anchors; it does not resume the work (the keep-going sibling), enumerate
  worktrees, or triage PR feedback. The plugin now bundles six skills.

## [0.8.0] — 2026-07-17

Changed:

- Adopt topic-docs contract 2.0.0 (visibility semantics): `reference/topic-docs.md` states
  handoffs and the workflow checklist are checkout-local; the checklist is the stage-ledger kind
  the contract's `.worktreeinclude` template carries into new worktrees, while handoffs are
  session-scoped and deliberately not carried.

## [0.7.1]

### Changed

- References to the renamed `/planning:plan` skill (was `/planning:architect`, planning 0.13.0 breaking rename) retargeted. Version bumped so existing installs receive the rewritten prompts.

## [0.7.0] — 2026-07-17

Added:

- keep-going: new skill. Recovers and continues a session after any
  interruption (rate limit, crash, disconnect, gap) — inventory off-thread
  work, inspect each item's real state from its artifact rather than
  assuming, resume the resumable / restart the dead / surface the
  unrecoverable, then reconcile the main thread from a fresh read of its
  backing plan or handoff file and continue. Safe/idempotent work
  auto-resumes; re-running side-effectful work (push, PR comment, deploy) is
  gated against double-firing. It is the resume counterpart to handoff, and
  the interruption cause is deliberately not diagnosed (recovery is
  identical regardless). The plugin now bundles five skills.

## [0.6.0] — 2026-07-16

Changed:

- orchestration-brief renamed to `orchestrate`. The default action
  arms/primes the current session — the skill's primary job — which the old
  name undersold by foregrounding the secondary export brief; the verb also
  matches the action-skill naming convention. Invocation is now
  `/session-flow:orchestrate`; the old `/session-flow:orchestration-brief`
  token no longer resolves. Export modes are unchanged (`handoff` / `worker`
  args), and the exported document is still an orchestration brief.

Added:

- orchestrate: seventh imperative CALIBRATE TO CONDITIONS — size the whole
  orchestration (whether to delegate at all, fan-out width, nesting depth) to
  the active model's capability, advisor/verifier availability, context
  pressure, and concurrent-session / rate-limit headroom, with
  small/medium/large fan-out sizing and single-agent as the floor.

## [0.5.0] — 2026-07-15

Added:

- handoff: mandatory redaction pass over ALL outbound handoff content
  (file, resume prompt, `--bg` launch) — secrets/tokens/credentials/PII
  replaced with shape markers before anything is written or emitted; the
  `--bg` process-argument visibility note now leans on it. New checklist
  ticks on both paths.
- handoff: mandatory "Suggested skills" body section — fully-qualified,
  "if installed"-qualified forward pointers naming the skills the
  resuming session should invoke for the remaining work (eight body
  sections now).
- handoff: fork-beats-compaction guidance — once the session is deep
  enough into its context window that reasoning quality degrades
  (roughly beyond the final third), a fresh-session fork from the
  handoff file beats continuing over a compacted history; threshold is
  relative, never a token count.
- handoff: re-read-from-disk + append-over-rewrite discipline when
  extending a handoff file that already exists on disk.
- workflow: on-ramp classes that merge into the stage sequence partway
  (raw bug/issue intake via diagnosis into implement, foggy
  too-big-to-plan efforts via wayfinding into plan, codebase-upkeep
  findings entering a fresh cycle), with graceful if-installed
  cross-plugin routing and no enumerated skill catalog.
- workflow: single-owner routing when two adjacent capabilities both
  fit — exclusion language wins, then the more specific claim, then the
  earlier stage.
- workflow: stale-map gotcha — re-check the described flows against the
  actual capability inventory whenever capabilities are added, renamed,
  or retired.

## [0.4.0] — 2026-07-15

Added:

- retro: `reference/ecosystem-improvement-catalog.md` — placement decision
  tree (project vs personal scope, laptop-dies test), per-target
  recommendation formats (memory, rules, hooks, skills, agents, MCP
  servers, settings), and a hook-event table verified against the current
  official hooks docs. Loaded by session-mode Phase 3.
- handoff: `context/gotchas.md` — failure patterns (prompt-only when
  durability is required, plan-anticipated work dropped on batch pushback,
  handoff without verifiable sanity-check evidence, continuing past an
  explicit stop). Loaded on demand from the SKILL.md checklist.

## [0.3.0] — 2026-07-14

Adopt the marketplace topic-docs convention
(`docs/conventions/topic-docs/`, contract v1.0.0):

- Handoff save-points move from `.claude/handoffs/` to the memory
  tier's concern-scoped handoffs directory — `<memory_dir>/handoffs/`
  (default `.work/handoffs/`), never committed. The workflow
  checklist moves to the topic's own memory slice —
  `<memory_dir>/<slug>/workflow-checklist.md` (default
  `.work/<slug>/`), a per-topic stage ledger: a fixed filename in the
  shared handoffs directory would clobber across two in-flight
  topics. The session's first memory-tier write verifies the resolved
  memory root's self-ignore guard (a `.gitignore` containing `*`),
  creating it (announced) when absent. No skill edits the consumer's
  root `.gitignore`. A consumer-declared convention
  (`.claude/topic-docs.yaml`, `CLAUDE.md` / rules) still wins;
  filename timestamps stay ISO-basic UTC.
- New `reference/topic-docs.md` — the plugin's binding to the contract
  (memory tier, handoffs concern directory, resolution order, guards).
  The handoff, workflow, and retro skills resolve placement through
  it; none bakes its own paths.
- The prior `.claude/handoffs/` location is retired outright — no
  compatibility layer, no dual-read window, no migration tooling;
  move residual content manually.
