# Design resolution — overengineering-detection-skill

outcome: early-exit (Tier B — light design; no separate `/planning:design` pass)

## Why early-exit is sufficient

- The deliverable is a markdown-only plugin (two SKILL.md bodies, shared context docs, manifest,
  evals). Its module topology is prescribed by this marketplace's own conventions
  (`docs/PLUGIN-PHILOSOPHY.md` structure/naming, `plugins/<name>/skills/<verb>/` layout), not
  designed anew.
- The design-significant threads were resolved and user-locked in the 14-decision interview
  (`.work/overengineering-detection-skill/interview-checklist.md`): skill split (Q14 — two
  single-purpose skills, plugin-level shared context doc, artifact-seam composition), verdict
  ladder (Q9), report format (Q12), protected categories (Q13), V1 cadence (Q5).
- The one novel contract — the findings artifact — is a localized instance of two existing
  marketplace contracts: `docs/PLUGIN-ARTIFACT-PROTOCOL.md` (protocol v2) for placement/seam
  behavior, and `docs/conventions/finding-suppression/` for the stable-id shape. Its type sketch
  is below; no new cross-plugin protocol is introduced.

## Type sketch — the findings artifact (audit → realign seam)

One markdown file, memory tier, concern-scoped (resolved through the plugin's `reference/topic-docs.md`
binding; never committed):

```markdown
---
type: overengineering-findings        # deliberately NOT `type: review-findings` — see below
schema: 1
date: <UTC, colon-free>
scope: <what was walked: repo root + surface layers covered>
branch: <branch at audit time>
---

# Overengineering audit — findings

## Summary        <counts per verdict class, per surface layer>

## Findings       <one section per item, stable order: layer → path → id>

### <finding-id>  <content-derived stable id: hash of (layer, artifact-path, check), per the
                   finding-suppression id discipline — diffable across runs>
- **Artifact:** <path / workflow / hook entry / app name>
- **Layer:** <claude-hooks | repo-hooks | git-hooks | ci | satellite-workflows | gate-scripts |
   branch-protection | github-apps | standing-instructions | external>
- **Verdict:** KEEP | RETIRE | DOWNGRADE | CONSOLIDATE | UNPROVEN | FLAG-FOR-HUMAN
- **Evidence:** <≥1 empirical citation, or UNPROVEN; doc-only support explicitly marked unverified>
- **Intent reconstruction:** <original problem, confidence; OPEN-INTENT when unattended + low-confidence>
- **Rediscovery:** <simplest adequate re-solution, native-first; tech-drift note>
- **Cost weighing:** <removal/refactor/testing cost entering the verdict>
- **Status:** OPEN | ACCEPTED | REJECTED | REALIGNED | ABLATION-<state>   # realign owns transitions
```

**Deliberately NOT `type: review-findings`:** the `review:fanout` fix relay auto-applies findings
by frontmatter type alone; routing consent-gated realignment through it would launder the per-item
human gate (`docs/conventions/detector-findings/README.md` — "handing a consent-gated write to an
apply relay would launder that gate"). The realign skill is the artifact's only consumer.

## Collaboration shape

- `overengineering:audit` (producer, read-only) → findings artifact → `overengineering:realign`
  (consumer, mutation behind per-item user acceptance). Both skills reference the plugin-level
  `context/scrutiny-method.md`; neither duplicates it.
- Cross-plugin references (interview/explore/research/plan skills, neighbor audits, HTML render)
  are presence-gated with documented prose fallbacks per `docs/PLUGIN-PHILOSOPHY.md`.
