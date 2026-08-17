# Lane 3 summary: compaction doctrine (#2901)

Closed 2026-08-17. Vetted the merged Compaction + Auto-Compaction lessons (source committed at
`docs/topics/pocock-course-lanes/lessons/03-compaction-and-auto-compaction.md`) against the
house doctrine: the handoff skill's fork-beats-compaction section, the continuation router's
compact-last-with-steering edge, and context-guard's evidence-degraded marker and zone contract.

## Decisions (register Q24-Q29, provenance: user's standing acceptance of this session's recommendations)

- **Q24 compact-as-default: REJECTED.** His compaction lesson's "saves re-exploration" default
  framing loses to fork-beats-compaction; his own phase-boundaries lesson places compact at the
  tree's bottom, converging with our last-resort-with-steering edge. No change to house doctrine.
- **Q25 steered-compact-for-QA carve-out: REJECTED, track-on-event.** Evidence degradation is
  trigger-independent; his own AFK criterion routes finished-work QA to a subagent. Key fact:
  `post-compact-mark.sh` already records `trigger: manual|auto|unknown`, so differentiation is
  buildable the day real evidence justifies it; that recorded field is the reopen observable.
- **Q26 auto-compact stance: ADOPTED (convergent).** "Auto-compact firing means the boundary
  decision was left too late; the human owns it" matches the instrumented design (operator-only
  menus per check I23). Filed #2995: context-guard documents the verified config surfaces
  (autoCompactWindow 100k-1M, env-var precedence, C1-C3 two-pool) and the zones-below-trigger
  guidance.
- **Q27 primary/secondary-source vocabulary: ADOPT terms, REJECT the irrecoverability half.**
  In Claude Code the on-disk JSONL transcript persists losslessly across compaction; only the
  model-visible context turns secondary. Term adoption executes in lane 6.
- **Q28 C5/C6: recorded, not blocked.** C5 (queueing during compaction) stays UNDOCUMENTED and
  untaught; C6 keeps its docs-only single-pool label; the interactive probe remains an open cure.
- **Q29 Boris sections 63-64: cited as vendored nuance.** Aligned with house stance; 300k-400k
  rot reports and the 400000 env-var practice held as named anchors, never adopted numbers;
  vendored content stays unedited.

## Outputs

- Rows: `docs/upstream/aihero-course.md` "Lane 3" section (12 rows + house-decisions paragraph).
- Work item filed: #2995 (context-guard auto-compact-window documentation). No other plugin
  change decided; Q24/Q25/Q27 dispositions require none.
- Lane-6 parcels: primary/secondary-source term adoption (with the transcript refinement);
  C4-refutation phrasing available for the coverage index.

## Notes for later lanes

- Lane 4 consumes C7-C9 verdicts (plan-mode mechanics; C9-positive single-pool label).
- The #2957 cloud zone-signal gap was weighed here: it does not change Q26's disposition (the
  stance is about who owns the decision, not the instrument's availability in one environment),
  but #2995's docs should acknowledge headless/cloud sessions lack the statusline tee.
