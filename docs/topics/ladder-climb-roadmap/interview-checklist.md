# ladder-climb-roadmap — interview decision-tree ledger

Session: 2026-07-21. Round 1 asked; operator conditionally accepted all RECOMMENDED pending
deep verification; verification ran (4 blind agents: boris-verify, gh-verify, cc-verify,
sec-verify); all surviving RECs locked. Five items await explicit operator answers.

## Resolved (Round 1 + verification, 2026-07-21)

### A — #509 enforcement design (locked per verified REC)
- [x] Q1 forcing mechanism = GitHub required status check + workflow-applied evidence label; no
      dedicated review loop. ATTRIBUTION: enforcement is the OPERATOR's mandate + consensus
      practice (OpenSSF Scorecard branch-protection; GitHub protected-branch docs; NIST
      SP 800-218A same-bar-for-AI-code) — NOT prescribed by Boris (his posture is default-on +
      automatic; step-2 merge is manual). Nothing in Boris contradicts it.
- [x] Q2 promote EXECUTION to required now; VERDICT gating stays advisory per #377 knob floors
      (C3 Layer-2 promotable on its evidence predicate). Progressive-enforcement pattern
      verified (CodeQL alert-first rollout; Gatekeeper dryrun→warn→deny).
- [x] Q3 every-PR semantics: check reports on every PR; job-level conditional gives non-sensitive
      diffs an explicit "not-applicable" verdict. Mechanics verified: workflow-level path filter
      + required check wedges Pending (docs); job-level if-skip reports Success (docs).
      REVISIT-TRIGGER: if a merge queue is enabled, the workflow must add the merge_group
      trigger or its required check is never reported (docs).
- [x] Q4 evidence: check run = canonical (App-only creation — tamper-resistant; queryable via
      API; #440 report-only safe); label = glance layer only (flippable at Triage — verified
      weak); findings ride the #377 verification record.
- [x] Q5 lane-responsibility conventions home = autonomy guardrail matrix hub; skills point at it.
- [x] Q6 no standing review loop; one-shot backfill sweep at cutover.
- Implementation split: github-iac (ruleset rule — rulesets + IaC verified), ci-workflows
  (workflow always-report shape), claude-code-plugins (caller moves path filter to job level).

### B — proving-ground routine + evidence drain
- [x] Q7 routine identity = hourly-drain of C2-classed items on autonomy-demo-scratch
      (binding-ratified surfaces; extends #352 dispatch seam).
- [x] Q8 RULED (2026-07-21): direction locked = local scheduled headless run (Desktop
      scheduled tasks / OS scheduler); ALL implementation details explicitly deferred to
      #778's plan as operator questions: auth path (--bare/API-key billing vs OAuth),
      model per run, schedule window, failure handling, per-run budget cap, PR-flow
      mechanics, Desktop-app feasibility on this machine (unverified). Bias audit
      recorded: mechanism has zero Boris basis (his step-3 products are product names
      only); elimination was doc-constraint-driven; hourly-drain identity follows the
      user-ratified WP6 binding (ratified precedent, named). Visibility surfaces committed:
      GitHub artifacts, telemetry scoreboard, scheduler run history, optional desktop
      notification.
      ORIGINAL REC TRAIL: Desktop scheduled tasks
      (code.claude.com/docs/en/desktop-scheduled-tasks; local machine, min 1-min interval)
      matches demo-local-session. Excluded: cloud Routines (no local file access, 1h floor),
      /loop cron (7-day expiry, session-bound). Unattended posture: claude -p,
      --permission-mode dontAsk + explicit allow rules (+ #495 preflight). Build-time verify:
      --bare skips OAuth (needs ANTHROPIC_API_KEY/apiKeyHelper) — pick auth path at build.
      AWAITING OPERATOR one-tap.
- [x] Q9 demo items move to PR-flow (C2 predicate needs merge/revert inputs; close-only can
      never satisfy it).
- [x] Q10/Q11 ANSWERED + POSTED (2026-07-21): "no, <1h" on autonomy-demo-scratch#4 —
      honest low-value data point; the run's purpose was the pipeline proof.
- AMENDMENT to Q8 (operator, 2026-07-21): NATIVE-FIRST — prefer Claude Code's own
      scheduled-task surfaces over hand-managed OS scheduled tasks unless the native
      path can't be easily managed; add a periodic recheck-against-upstream trigger
      (scheduling features are advancing; re-verify options at each build touchpoint).
- PRINCIPLE ratified (operator, 2026-07-21): separate Boris CONCEPTS (agnostic,
      portable) from IMPLEMENTATION (machine/repo/user/org-specific). Contracts and
      setup stay agnostic; machine-specifics live in bindings only. The autonomy
      plugin's contract-vs-org-binding shape is the template; roadmap items carry it.

### C — #607 batch (locked)
- [x] Q12 folded members stay open + land #552 native sub-issues.
- [x] Q13 close #280 as completed.
- [x] Q14 fold additions into #552 review; ratify early high→medium flips retroactively.
- [x] Q15 authorize ONE batch-capped T2 historic-normalization directive.
- [x] Q16 title convention ruled inside #552 review; taxonomy home github-iac.
- [x] Q17 #524 confirmed ready.

### D
- [x] Q18 RULED: promote #380–#382 (area:security) into the 7/26 set; rest of disk-hygiene
      stays C. (Label/gauge update = tower execution item.)

### E
- [x] Q19 RULED + EXECUTED (2026-07-21): (a) #304 INCLUDED on roadmap (not parked) —
      trust-loop hardening, org-standard basis (Boris silent on fresh-eyes; recorded on
      #304); (b) underspecification DONE (acceptance criteria live in shipped planning
      skill); (c) youtube-watch deleted; (d) sweep executed — deleted 6 verified-complete
      .work dirs (youtube-watch, plugin-organization, plugin-fleet-sync-skill,
      interview-batch-rounds, plugin-philosophy, underspecification), archived 4
      unverified (naming-theory, upstream-ports, salvage-and-absorb,
      proactive-vs-reactive-skills) + 12 superseded pre-7/19 handoff intermediates;
      chain heads/origin/≥7/19 retained. (Prior executions: Brief-rescue PR #776;
      github-lane coordination note; #554 pointer.)

### F — roadmap shape (locked)
- [x] Q20 snowball criterion ratified: compounding builds outrank linear burn in every pick-order.
- [x] Q21 github-plugin lane: finish phase 6–7, no new scope until ignition.
- [x] Q22 A1/A2 burn = parallel fodder only.
- [x] Q23 7/26 north star + #627 gauge authoritative.
- [x] Q24 file context-pull work item (wikis/discussions leg), day-job trigger.
- [x] Q25 universal scope = deferred-with-trigger (day-job adoption), confirmed not dropped.

## Verification ledger (per-claim, 2026-07-21)

VERIFIED: C1 capture==live doc (string-diff, zero drift) · C2/C3/C4 Boris text ("widespread"
restored in C3) · C6/C7 path-filter/job-conditional (GitHub docs) · C8 rulesets+IaC · C10 label
perms + fork caveat · C11 conversation-resolution rule · C12 headless -p (+--bare flag note) ·
C13 scheduling trio (Routines/Desktop tasks/loop-cron w/ 7-day expiry) · C14 sandboxing
(NO native Windows — WSL2 only; roadmap constraint) · C15 permission modes (dontAsk = CI
posture; auto aborts headless on repeated blocks) · C16 OTEL (resource attrs, TRACEPARENT,
CLAUDE_CODE_ENHANCED_TELEMETRY_BETA — matches #351 probes) · C18 required-check consensus ·
C19 advisory→blocking progression · C20 check-as-evidence (SLSA/attestations) · C21
label-weak/check-strong · C22 NIST SP 800-218A same-bar (medium-high; PDF not visually
confirmed).
CORRECTED: C3 (+"widespread") · C9 (merge_group trigger requirement) · T1 attribution
(operator mandate, not Boris) · Q8 REC (Desktop scheduled tasks).
UNVERIFIABLE: companion Claude artifact (non-member read disabled) · claude-code-action
setupBranch/persist-credentials caveat absent from official docs (stands on upstream issue
only — tagged verified-by-issue-not-docs) · Boris's "LSPs" mention has no official CC doc.

## Codification targets (execute after final five answered)

1. #509: design ruling comment (T1–T6 + attribution + merge_group trigger) → issue; ADR 0002
   status update (interim → resolved-by-ruling); design-threads record.
2. #607: rulings comment (Q12–Q17).
3. New issues: 2→3 ignition tracking item (routine + evidence drain, per curation §4c verify);
   context-pull leg (Q24).
4. Q19 dispositions as ruled.
5. Roadmap PLAN.md Brief (`docs/topics/ladder-climb-roadmap/PLAN.md`) + /planning:plan.
6. Session handoff.
