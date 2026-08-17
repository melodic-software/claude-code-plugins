# improvement

A Claude Code plugin answering the question the fleet had no entry point for: **"what should we
improve here, and how do we know?"** One skill, one concern: finding improvement candidates —
across dimensions, at any size — and backing every one with evidence.

| Skill | What it does |
|---|---|
| `/improvement:find` | Evidence-first improvement finder. Point it at a repo, a feature, a concept, or a process surface — with a vague or specific prompt — and it produces a ranked, evidence-cited list of improvement candidates led by the highest value-to-effort, deliberates on the picked candidate through an interview, and hands off to the planning pipeline. Runnable unattended as a tech-debt-sweep routine. |

## Evidence-first identity

Every candidate cites its evidence — repo-native signals such as churn hotspots and CI health,
local telemetry, or (weakest) model judgment from reading the target — and ranking confidence is
a function of evidence strength. When the target has no measurement at all, the top-ranked
candidate becomes "instrument this so future runs can rank on data," handed to the pipeline like
any other improvement. Evidence gaps are recorded, never papered over.

The finder is read-only: it discovers and deliberates, and execution requests route through the
normal interview → discovery → planning → implementation → verification pipeline. It delegates to
installed specialized lanes where they add value and never re-implements what an owned lane
already does.

Routine-wrapper guidance (recommended unattended cadence, prompt tuning surface, scheduling
alternatives) lands with the skill content.
