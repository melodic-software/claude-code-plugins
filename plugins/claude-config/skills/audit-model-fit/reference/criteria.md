# Model-Fit Criteria

Version: 1.0.0
Last updated: 2026-07-21

This file defines the checks the `audit-model-fit` audit runs against local Claude Code instruction
surfaces. It sweeps for deterministic constraints that hobble newer, more capable models — instructions
that made a prior, weaker model behave but now only narrow a capable one — and proposes removals or
rewrites. It **never** applies them: output is a findings report plus proposed diffs, human-gated.

The governing question — the pruning bar every finding is measured against — is from Anthropic's
guidance: **"Would removing this instruction cause Claude to make mistakes?"** If no, the instruction is
a removal or loosening candidate.

Sources (verify against these; do not fabricate deep-link anchors):

- [Prompting Claude Fable 5](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-fable-5)
  — "re-evaluate which instructions, tools, and guardrails are still needed"; skills built for prior
  models are "often too prescriptive… and can degrade output quality".
- [Claude prompting best practices](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/claude-prompting-best-practices)
- [Claude Code best practices](https://code.claude.com/docs/en/best-practices) — the pruning bar.

## Surfaces

The deterministic spine is
`bash "${CLAUDE_PLUGIN_ROOT}/skills/audit-model-fit/scripts/instruction-surface-scan.sh"`. It enumerates,
across the consuming repo (and the user-global `~/.claude/CLAUDE.md`):

- user + project `CLAUDE.md` (`CLAUDE.md`, `.claude/CLAUDE.md`, `CLAUDE.local.md`, `~/.claude/CLAUDE.md`)
- skill `SKILL.md` bodies + their `context/` and `reference/` files
- agent definitions (`.claude/agents/*.md`)
- `.claude/rules/**/*.md`
- output styles (`.claude/output-styles/*.md`) and prompt-type hook scripts (`.claude/hooks`)

It flags the two grep-able smells (C1 bare prohibitions, C3 example-dense files) as **candidates** and
is advisory (always exits 0). `--candidates` lists each `file:line`; `--count` prints the
bare-prohibition candidate count. The other checks are model judgment applied while reading the surfaces
— the script does not verdict them.

Prose surfaces (CLAUDE.md, skill bodies + context, agents, rules, output styles) are grep-scanned for
the two candidate smells. **Hook scripts are enumerated (counted) but not grep-scanned** — a prompt-type
hook's instruction text is embedded in code, where a "never/do not" grep is noise; read the hook bodies
by hand in Phase 2 and apply the same checks.

Findings are reported, never applied. There is no `--fix`.

---

## C1: Bare prohibition — "never/do not X" with no stated why [rewrite, not delete]

**What**: A prohibition (`never`, `do not`, `must not`, `shall not`) with no rationale attached. The
scan flags the prohibition lines; whether a rationale is present is the model's call.

**Why it is a smell**: a capable model follows a reasoned constraint and generalizes it; a bare "never
X" it cannot reason about is both easier to misapply and a frequent relic of steering a weaker model.

**Treatment**: rewrite to **prohibition + rationale**, not deletion. The constraint may still be needed
— only the missing *why* is the defect. Delete only if the pruning bar says removing it changes nothing.

## C2: Over-prescriptive step list → cull to intent + constraints [rewrite]

**What**: A mechanical, numbered step-by-step recipe for something a capable model already sequences
correctly on its own.

**Why it is a smell**: prescriptive step lists built for prior models "can degrade output quality" — they
over-constrain the model's own planning. Keep the *goal* and the *hard constraints*; drop the mechanics.

**Treatment**: rewrite to state the intent and the non-negotiable constraints, removing steps that only
narrate an obvious procedure. Keep any step that encodes a genuine hard constraint (an ordering that
matters, a safety gate, an external contract).

## C3: Example-dense block — over-constraining format steering [rewrite; NOT a blanket ban]

**What**: An instruction surface carrying far more format-steering example blocks than needed. The scan
flags files with **more than 5** fenced/`<example>` blocks as candidates.

**Why it is a smell — and its limit**: current guidance still recommends keeping **3–5** examples to
steer format; examples are not the enemy. Only volume **well beyond** that range starts pinning the
model to a rigid template. Do **not** blanket-flag example blocks.

**Treatment**: trim toward the 3–5 that genuinely steer format; keep coverage of the distinct shapes,
drop near-duplicates. A file at or below the range is not a finding.

## C4: Stale model-era workaround [remove/loosen]

**What**: An instruction that reads as compensating for a prior, less-capable model's specific weakness —
verbose over-specification of things a capable model now gets right (belaboring output format it would
infer, re-explaining a concept it knows, defensive "if you are unsure, do X" scaffolding for a task it
now handles).

**Why it is a smell**: it is pure carrying cost — tokens and rigidity spent to fix a model that is no
longer running.

**Treatment**: apply the pruning bar. If removing it would not cause mistakes on the current model,
propose removal or loosening.

---

## The pruning bar (applies to every finding)

For each candidate, ask: **would removing this instruction cause Claude to make mistakes?**

- **No** → removal/loosening candidate (report the proposed diff).
- **Yes** → keep it. If it is a bare prohibition (C1), still propose the rationale rewrite.

A clean sweep — every instruction earns its place — is a valid outcome. Do not manufacture findings.

## Compose with — distinct intents, route out (do not restate their logic)

- `claude-memory:audit` — instruction-layer **health** (well-formed `CLAUDE.md`, length, valid rules)
  against a codified checklist. Same surfaces, same pruning bar, different question: health/structure
  vs. model-fit. Route health/length/structure findings there; keep constraint-loosening here.
- `skill-quality:check` — **structural** lint of a SKILL.md (frontmatter, line caps, broken refs). This
  audit is content/fit, not structure. Structural defects route there.
- `docs-hygiene:compress` — **token brevity** (shorten prose without semantic loss). This audit removes
  now-unnecessary *constraints*, not just words. A prohibition that should stay but read tighter is a
  compress job; a prohibition that should loosen is this audit.
- `claude-config:audit` — **config-file** hygiene (settings.json / .mcp.json / hooks / permissions). This
  audit reads instruction *content*, not config correctness.

## Cross-repo routing — standards-managed materializations

A finding inside a file that is a **materialization synced from `melodic-software/standards`** (owned
upstream per that repo's `distribution/sync-manifest.yml`) is **never edited in place** — the local copy
would be overwritten on the next sync and the change lost. Route such a finding upstream to
`melodic-software/standards` (or the owning source repo the manifest names) as the change target, and
say so in the report. Locally-owned surfaces are edited via the normal human-gated proposed diff. When
the manifest is not reachable from the consuming repo, still apply the rule: flag any file that looks
vendored/synced and note it needs upstream routing rather than an in-place edit.

## Output format

```text
## Model-Fit Report — {date}

### Surfaces scanned
(inventory from instruction-surface-scan.sh)

### Findings
| # | Check | Surface | Finding | Pruning-bar verdict | Proposed change | Routing |
|---|-------|---------|---------|---------------------|-----------------|---------|

### Proposed diffs
(per finding: the exact before/after rewrite — human applies, never auto-applied)
```

For a standards-managed finding, the Routing column reads "upstream: melodic-software/standards" and no
in-place diff is proposed for that file.
