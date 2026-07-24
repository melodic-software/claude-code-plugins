# Coverage matrix — source rules against what already enforces them

Each row maps a section of [article-sections.md](article-sections.md) to the incumbent that already
covers it, and states what is left over. Verdict values: `COVERED` (an incumbent enforces it),
`PARTIAL` (an incumbent touches it but leaves a stated remainder), `GAP` (nothing enforces it),
`N/A` (framing or out-of-scope, no check possible).

## Incumbents, as verified 2026-07-24

| Incumbent | Surface it owns | How verified |
|---|---|---|
| `/doctor` (built-in, alias `/checkup`) | Deduplicates local `CLAUDE.md` against checked-in ones; trims checked-in `CLAUDE.md` by cutting content Claude could derive from the codebase; migrates the always-loaded remainder into skills and nested `CLAUDE.md` files; finds unused skills, MCP servers, and plugins against their context cost; flags slow hooks. Reports first, confirms before changing. | Fetched <https://code.claude.com/docs/en/commands> this session |
| `claude-config:audit-instructions` | Checks I1–I11 over user + project `CLAUDE.md`, `.claude/rules`, skill bodies, agent definitions, prompt-type hooks, output styles. Report-only, human-gated. | Read `SKILL.md` + `reference/criteria.md` this session |
| `claude-memory:audit` / `stateless` | Memory-layer hygiene (I1–I5 on memory surfaces); auto-memory inspection and disablement | Skill descriptions read this session |
| `docs-hygiene:extract-ssot` / `compress` / `audit-derivability` / `audit-noise` | Duplicate content into one SSOT; brevity; whether a doc earns its existence; five noise shapes | Skill descriptions read this session |
| `skill-quality:check` | Structural skill lint — frontmatter, listing-budget cap, line caps, broken refs | Skill description read this session |
| `plugin-quality:audit` | Post-use behavioral audit of a plugin component | Skill description read this session |
| `playbooks:fable-5` | The model's *operating* doctrine (how to work), not context *authoring* — a different axis, and a structural exemplar: `SKILL.md` plus 13 on-demand chapters under `context/` | Read this session |

## The matrix

| § | Rule | Incumbent | Verdict |
|---|---|---|---|
| S1 | Context is assembled, reused, and cannot be prompt-specific | — (framing) | `N/A` |
| S2 | 80% system-prompt removal; `/doctor` rightsizes skills and `CLAUDE.md` | `/doctor` | `COVERED` — and it is Anthropic's own tool, so anything built here must complement it |
| S3 | Instructions conflict *across* surfaces, and reconciling them costs reasoning | none — I1–I11 all judge a line or a file in isolation; `extract-ssot` finds *repetition*, not *contradiction* | **`GAP`** — the largest one, and the article's own headline example |
| S4 | Memory, artifacts, and skills are now destinations that `CLAUDE.md` content should move to | `/doctor` (migrates to skills + nested `CLAUDE.md`); `audit-instructions` I3 (move to skill or path-scoped rule); `claude-memory` (auto-memory) | `PARTIAL` — artifacts are named as a destination by neither |
| S5 | Absolute rules give way to context-sensitive judgement | `audit-instructions` I6 (bare prohibition → positive reframing), I8 (model-era re-audit of over-prescriptive scaffolding) | `COVERED` |
| S6 | Examples constrain; design expressive interfaces instead | `audit-instructions` I9 covers the *negative* half (approach-pinning example blocks) | `PARTIAL` — the *positive* half is unowned: nothing audits whether a skill's `argument-hint`, arguments, enumerations, and frontmatter are expressive enough that prose examples become unnecessary |
| S7 | Progressive disclosure — file trees, on-demand loading, deferred tools | `/doctor` (migrate always-loaded guidance); `audit-instructions` I3; `skill-quality:check` (line caps) | `PARTIAL` — splitting one long `SKILL.md` into a chapter tree is implied by line caps but never prescribed as a remediation; deferred tool loading is unowned |
| S8 | Do not repeat an instruction across surfaces; it belongs at the definition of the thing it governs | `docs-hygiene:extract-ssot` (dedupe to one SSOT) | `PARTIAL` — dedupe picks *a* home; nothing encodes *which* home is correct (the placement rule) |
| S9 | Auto-memory replaces `#`-hotkey writes into `CLAUDE.md` | `claude-memory:audit` / `stateless`; `/memory` | `COVERED` |
| S10 | Rich references — HTML artifacts, code-as-spec, test-suite-as-spec, port targets, rubrics driving verifier agents | none | **`GAP`** — wholly unowned |
| S11 | The system prompt is product context; harness authors invest there | — (out of scope for a Claude Code plugin) | `N/A` — but the repo's own agent definitions are the local analogue, already inside `audit-instructions` scope |
| S12 | `CLAUDE.md`: lightweight, gotcha-dense, no obviousness, progressive disclosure | `/doctor` (trim + migrate); `audit-instructions` I1–I5 routed to `claude-memory` on memory surfaces | `COVERED` |
| S13 | Skills: lightweight guides, split long ones, encode particular opinions, **except stay constrained in highly important areas** | `audit-instructions` I8; `skill-quality:check` | `PARTIAL` — the carve-out is the calibration knob and no incumbent encodes it, so a trimming pass has no principled stopping point |
| S14 | Prefer code > structured artifact > prose > screenshot as a reference | none | **`GAP`** — same gap as S10 |
| S15 | Simplify; `claude doctor` automates part of it; the Fable field guide covers model-specific prompting | `/doctor`; `playbooks:fable-5` (adjacent axis); `criteria.md` already cites the Fable 5 guide as a source and names its supersession trigger | `COVERED` |

## What the matrix says

Four genuine gaps, in descending order of how much they justify new surface:

1. **S3 — cross-surface instruction conflict.** No incumbent compares two instruction surfaces
   against each other. This is the article's own headline failure mode and the only gap with a
   named, reproducible symptom.
2. **S10 + S14 — reference quality.** Nothing audits or steers what a plan, spec, or skill points
   at. Distinct from every incumbent, but this is *authoring guidance*, not an auditable defect —
   the shape it should take is undecided.
3. **S6 — interface expressiveness.** The positive counterpart to I9. Plausibly a check added to
   `skill-quality:check` rather than anything new.
4. **S8 + S13 — the placement rule and the importance carve-out.** Both are calibration
   refinements to incumbents (`extract-ssot`, `audit-instructions` I8), not standalone surface.

Everything else is already enforced, most of it by `/doctor` — which is Anthropic's own tool,
shipping the same doctrine, and improving on its own release cadence. Any surface added here must
be defensible against "`/doctor` already does this."
