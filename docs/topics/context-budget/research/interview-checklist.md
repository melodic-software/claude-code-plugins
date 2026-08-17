# /planning:interview Checklist — startup-context-baseline

Topic: a skill that establishes and trims a session's fixed startup context baseline.
Mode: `me` (relentless), engineering domain.
Invoked via working-tree SKILL.md (plugin registry not loaded this session — cloud-bootstrap.sh:11-17).

## Steps

- [x] Step 1: Survey before you ask
- [ ] Step 1.5: Auto-detect — SKIPPED (`me` mode forced by user)
- [x] Step 2: Drive the frontier-rounds loop
- [x] Step 3: Recognize the stop condition
- [x] Step 4: Persist the contract — Brief at docs/topics/context-budget/PLAN.md; --brief gate exit 0 (brief=ok)
- [x] Step 5: Hand off — final report delivered; Phase 0 named as the execution start; session config: repo default, no pinned model

## Survey output

Fleet already owns: `/context` as ground-truth inventory (checks-and-sweep.md:288); `/doctor` for
unused skills/MCP/plugins vs context cost (checks-and-sweep.md:12); `claude-config:unhobble`
(behavioral ablation, project scope, `~/.claude` opt-in only); `claude-config:audit-instructions`
(text vs doctrine); `claude-config:audit` (settings/MCP/hooks/plugins drift);
`context-guard` (live per-session occupancy zones, NOT baseline composition);
`mcp-tools:audit` (author-side MCP tool-definition quality, not consumer-side cost).
Doctrine already written: `docs/PLUGIN-PHILOSOPHY.md:551` "Instruction economy".
Named open gap: `coverage-matrix.md:30` S7 — "deferred tool loading is unowned" (PARTIAL).
Estimator precedent: chars/4.0 divisor, `article-sections.md:26`.
Headless `/context` evidence: `checks-and-sweep.md:443` — `claude -p "/context"` exits 0, full output.

## Open-question register

- Q1 | withdrawn | round 1 | Home: new plugin vs claude-config vs context-guard | superseded by Q8, which asked it unambiguously and was answered
- Q2 | answered | round 1 | Shape: one skill w/ modes vs audit+trim pair | ONE skill, audit default action, can also fix
- Q3 | answered | round 1 | Scope: user-global + project, or project only | both
- Q4 | answered | round 1 | Mutation posture | apply on user approval; auto-mode bypass is a named risk
- Q5 | answered | round 1 | v1 surface list | all six of the course's + anything that affects context
- Q6 | answered | round 1 | Measurement engine | headless /context + interactive human check + empirical probing
- Q7 | answered | round 1 | Delegation seam to bundled /doctor | yes, consult the bundled doctor
- Q8 | answered | round 2 | Namespace | new `context-budget` plugin, single skill `/context-budget:audit`
- Q9 | answered | round 2 | Core payload | per-tool attribution of the un-itemized System tools pools
- Q10 | answered | round 2 | Auto-mode gate | AskUserQuestion per mutation; project writes on approval, user-global prints only — pending the auto-mode research, which may supply a stronger gate
- Q11 | answered | round 2 | Verb-alignment issue scope | narrow: description/verb-contract mismatches only, owned by skill-quality
- Q12 | answered | round 2 | Ablation loop | yes — measure, toggle, re-measure, record the delta
- Q13 | answered | round 3 | Does a deferred tool cost prefix tokens | YES — deferral does not shrink the request; schema ships every turn
- Q14 | answered | round 3 | What drops System tools 17.9k→3.5k | bare-name denies (Workflow 7.9k + Artifact 4.4k measured) plus includeGitInstructions ~2.4k
- Q15 | deferred | round 3 | Guided-wizard UX detail | build-phase decision — also in the Brief's Deferred questions

## Round 2 outcome

All Round 2 recommendations accepted by the operator. Remaining frontier is blocked on the nine
research runs; per the operator, no design is final until they return.
Completeness check against the source material: `source-levers.md` (L1-L12 lever inventory,
the source's own arithmetic problems, and the request-logger rejection).

## Empirical findings (this session)

`claude -p "/context"` at CLI v2.1.232, exit 0, 213 lines of markdown. Sections: category table,
per-agent table (token counts + Source), per-skill table (token counts + Source).
Category totals: System prompt 5.1k / System tools 18.1k / System tools (deferred) 17.8k /
Custom agents 1.5k / Skills 9.9k / Messages 591 = 35.3k of a 967k window.
Skill rows by Source: 152 `Plugin (x)`, 14 `Built-in`, 6 `claude.ai sync`, 1 `User`; 12 plugin agents.
**Per-skill and per-agent attribution already exists natively. Per-TOOL attribution does not —
`System tools` (18.1k) and `System tools (deferred)` (17.8k) are lump sums.**
Tool schemas cost ~3x what 65 plugins and 173 skills cost combined.

Bare-alias question: 46 plugins carry a `setup` leaf, 10 carry an `audit` leaf
(`scripts/skill-leaf-name-registry.txt` registers both with an open `*` owner set).

## Decision tree (`me` mode)

- [x] Home / namespace — new `context-budget` plugin
- [x] Component shape — one skill, `audit` default action, fix path behind override
- [x] Config scope — read all scopes; write posture differs by scope
- [x] Mutation posture — apply on approval; PreToolUse `ask` hook; user-global print-only
- [x] Surface coverage — L1-L12 per source-levers.md
- [x] Measurement engine — headless `/context` A/B differencing
- [x] /doctor seam — cannot invoke (disableModelInvocation); route only
- [ ] Interactive walkthrough UX — DEFERRED to build phase (Q15)
- [x] Baseline/compare ledger — `${CLAUDE_PLUGIN_DATA}` under the new plugin
- [ ] Portability posture for cloud/web surfaces — OPEN, needs operator decision
- [x] Naming — `/context-budget:audit`
- [ ] Evals shape — build phase

## Session-shorthand glossary

- **startup baseline** — the fixed per-session payload before any user message: system prompt,
  tool schemas, skill catalogue lines, memory files, MCP/connector surface.
- **trim lever** — an operator-controllable switch that removes something from that baseline.
- **schema-removing vs call-blocking** — whether a lever actually drops a tool definition from the
  request payload, or merely refuses the call while the definition still ships. Load-bearing.
