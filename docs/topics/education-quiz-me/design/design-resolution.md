# Design resolution — education-quiz-me

outcome: light-design (Tier B)

Prompt-only skill addition — no code types, no package topology change. The design surface
is two contracts, sketched here; everything else follows the sibling patterns read in
`.work/education-quiz-me/EXPLORE.md` (memory tier).

## Contract sketch

### userConfig (education `plugin.json`, first userConfig for this plugin)

| Key | Type | Default | Unset behavior |
|---|---|---|---|
| `quiz_policy` | string | `on-request` | `on-request` — skill acts only when invoked; `always` offers a quiz after every completed change; `above-threshold` offers when the change meets the documented size/blast-radius bar; `off` disables even on-request generation prompts inside other flows (direct invocation always works) |
| `report_library_dir` | directory | *(unset)* | artifacts land under `${CLAUDE_PLUGIN_DATA}/<project-slug>/reports/` (teach's slug recipe); set to point at a corpus checkout — same seam class as knowledge `library_dir` (#798), adopt its indirection scheme when that lands |

Consumption via the "Effective configuration (substituted at load)" table pattern
(surviving `${user_config.…}` literal = unset → documented default).

### Report artifact

Self-contained single-file HTML (all CSS/JS inline, no remote fetch, `file://`-opened,
no secrets — teach `context/lessons.md` precedent), markdown fallback. Sections: context,
intuition, decisions, what-was-done, quiz at bottom (canonical prompt pattern, Field Guide
blog). Claude holds the answer key; grading happens in-conversation, not in the page.

## Boundary map (non-overlap, documented in SKILL.md)

- `verification:confirm` — object = artifact ("did we build the right thing / does it work").
- `/planning:interview` — pre-work; extracts USER intent (user holds answers).
- teach `assess`/`exercise` actions — quiz the learner on LEARNING CONTENT in a workspace.
- This skill — post-work; verifies the HUMAN's comprehension of COMPLETED WORK (Claude
  holds answers). Non-gating by default.
