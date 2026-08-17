# Deviations log — overengineering-detection-skill implementation

Conservative deviations taken during autonomous orchestrated implementation, per the
implement-dispatch non-interactive divergence rule. Reviewed at PR time.

## Phase 1 (commit b8e7464a)

1. **Layer enum made forge-neutral.** `design/design-resolution.md`'s type sketch listed
   `github-apps`; the shipped `context/findings-artifact.md` enum uses `forge-apps` (whole enum:
   `agent-hooks · agent-instructions · repo-hooks · vcs-hooks · ci-lanes · gate-scripts ·
   satellite-workflows · branch-protection · forge-apps · external-integrations`). A baked forge
   name violates the Brief's consumer-agnostic constraint and is the token class the portability
   gate polices. Blast radius: Phases 3–4 must use this enum, not the sketch's.
2. **Refuted "no consumer means retire" claim appears once, explicitly marked refuted.** The plan
   said the claim "must NOT appear"; the shipped `scrutiny-method.md` §9 closes with a paragraph
   recording it as refuted and deliberately not a rule, so later readers do not re-derive it as an
   obvious inference. Read as truer to the plan's intent (the claim must not be *cited as
   support*); deletes cleanly if the reviewer disagrees (last paragraph of §9).
3. **Finding-id constituents specified concretely** (`check`/`claim`/`sites` shapes with
   `anchor/v1`), beyond the plan's "per the finding-suppression id discipline" — required for the
   durable judgment record to be implementable; the hash computation itself is pointed at, not
   restated.
4. **Forward pointers to Phase 2 files** (`reference/consumer-config.md`, `reference/topic-docs.md`)
   ship one phase before those files exist. Resolves when Phase 2 lands (same PR).

Known transient: `scripts/check-plugin-manifest-presence.sh` is red between Phase 1 and Phase 2
(plugin directory exists, marketplace entry not yet added — Phase 2 owns it). Closed by Phase 2
(commit 1346501b).

## Phase 2 (commit 1346501b)

1. **`docs/CATALOG.md` stale until Phase 5** — `generate-catalog.mjs --check` red with exactly the
   missing `overengineering` bullet; Phase 5 regenerates (plan already assigns it). Transient.
2. **Topic-docs convention registration added to Phase 5 scope.** The binding introduces a fourth
   first-level concern name (`overengineering`) under the memory root, but
   `docs/conventions/topic-docs/README.md`'s Implementers table and reserved-names list were
   outside both the plan's Phase 2 table and the worker's fence. Decision: Phase 5 adds the
   Implementers row and reserves the name (small convention edit aligned with plan intent;
   precedent `mutation-testing` lacks a row, but reserving prevents a topic-slug collision).
3. **Phase 1's `.work/` sanity grep is non-empty by design from Phase 2 on.** The topic-docs
   binding documents the contract's default memory root (`.work/overengineering/<branch-slug>/`),
   exactly as the review/planning plugins document theirs. The check's intent — no discovery-corpus
   citations — still holds: `.work/overengineering-detection-skill/` appears nowhere in shipped
   files; Phase 6 should use the corpus-specific grep.
4. **README cites the two skills before they exist** (Phases 3–4 create them); the repo's
   skill-reference hook will re-fire on README writes until Phase 4 lands. Self-resolving.
5. **Consumer-config key design** (mapping-not-list protected categories with seven bundled ids,
   per-row `null` threshold disable, `observation_window` {days, release_cycles}, no single
   disable-all token, intentionally-dormant deliberately not a consumer key in V1, derived
   suppression example) — worker discretion within the briefed scope, recorded with rationale
   in `reference/consumer-config.md`. Phases 3–4 must consume these key names as shipped.

## Phase 3 (commit a958dd64)

1. **Layer semantics derived where the enum named but did not define.** `repo-hooks` = repo-declared
   lifecycle automation not VCS-triggered (task-runner/package lifecycle scripts, build pre/post,
   bootstrap); `vcs-hooks` = configured hooks path + installed contents + tracked sources + hook-
   manager manifest, wiring answered from installed state; `satellite-workflows` = automation that
   gates nothing. Consistent with the Phase 1 forge-neutral intent; recorded for Phase 1 author
   review at PR time.
2. **Frontmatter description names the flag-for-human cap in one clause** — ruled discovery text
   (existence, not semantics; §7 remains the sole definition site).
3. **`shell: bash` declared** — the two `!` precompute injections use `2>/dev/null` (bash-only per
   check 19), each with a no-checkout fallback.
4. **Routing-row wording** for the unhobble route made harness-neutral ("agent-layer
   standing-instruction ablation the evidence cannot settle") — same route target.
5. Tooling note for later phases: the Write tool refuses `report-*`/`findings-*` filenames in
   subagents; write under a neutral name and `mv` (shell heredoc is hook-blocked).

## Phase 4 (commit 2a55bd60)

1. **Minimal argument surface** — finding ids and layer names narrow the queue; no mode verbs
   (ablation-window conclusion handled by the status-driven queue, not a `conclude-ablations`
   action). Worker discretion; brief left arguments unspecified.
2. **Six evals, not seven** — the branch/schema refusal is body-covered rather than a seventh
   scenario, staying tight to the plan's mandated six.
3. **`workflow-stage: implement`** (sibling audit uses `anytime`) — matches the skill's mutating
   role.
4. **Two `!` precompute injections** (branch, UTC date) with fallbacks; date needed so observation
   windows and suppression entries never carry a guessed date.

## Phase 5 (commits 5ae7047c + 61fc5133)

1. **Roster registration completed across all four SSOT-linked surfaces** (orchestrator follow-up
   commit 61fc5133, extending the plan's Phase 5 scope per the Phase 2 deviation): topic-docs
   CHANGELOG 2.5.1, tier row, schema `memory_dir` description, and the docs-hygiene `audit-noise`
   bare-root exemption (script + SKILL.md prose, plugin 0.15.3 + changelog; detect.test.sh 59/59).
   Precedent followed: convention 2.4.4 (`running-retros`) updated the same surface set. The
   audit-noise evals' three-name enumeration is scenario stimulus and stays true with four roots —
   left unchanged.
2. **Verb row placed alphabetically** in the verb table (matching existing order) rather than
   appended.

## Phase 6 (commits 37b247a9 + orchestrator marks)

1. **All plan experiments PASS on fresh-context dry runs** (agent-hooks layer, unattended):
   read-only proven twice (clean porcelain before/after both audit runs); all 35 finding ids
   independently re-derived by run 2 and matched run 1 (incl. the two-site pr-linkage id);
   carry-forward proven blind (hand-edited ACCEPTED survived a merge by an uninformed executor);
   stable-spine diff showed identical id set/order with only genuine verdict movement; realign
   walked to the per-item gate and stopped — artifact byte-identical (sha256 match), "no mutation
   path before acceptance" confirmed.
2. **The dry runs surfaced ~27 friction findings → 19 deduplicated fixes** applied in 37b247a9
   (member-line format + container-is-the-finding rule, per-layer item-unit pinning, `settings:`
   kind prefix, Rediscovery dispositions, merge-precedence rules, §9 minimum-observation guard,
   realign unattended clause + rung-1-inapplicable + CONSOLIDATE handling + two named gates +
   broadened judgment surfacing, doc-root disambiguation, delegated-write route). All gates re-run
   green; both skills PASS skill-quality.
3. **Accepted: realign SKILL.md at 228 lines carries one soft-target WARN** (200-line nudge;
   PASS, 0 errors). Clearing it needs a progressive-disclosure spoke — declined as not worth a
   new file for 28 lines; PR reviewer may overrule.
4. **`/plugin-quality:audit` (handoff remaining-action 4) deferred with justification**: it audits
   an INSTALLED plugin's claims-vs-reality, and this plugin is not installed in the build
   environment; three fresh-context dry runs + five per-phase verifiers + skill-quality PASS
   exceed its intent for this PR. Recommended as post-merge follow-up on an installed copy.
5. **Housekeeping default applied** (plan's fallback gate): the discovery corpus
   (`.work/overengineering-detection-skill/`) stays uncommitted; the plan carries the load-bearing
   findings inline.
6. **Deferred-lane probe**: issues #2897 and #2898 confirmed open via the forge API, correctly
   scoped, blocked-on-V1 as recorded.
7. The dry-run findings artifact (memory tier, gitignored) is a test fixture from this build; the
   audit's real first-run disposition of the dead pr-linkage hook remains a user decision through
   the audit output, per the plan.
