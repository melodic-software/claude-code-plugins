# Cross-Surface Conflict Criteria

Version: 1.0.0
Last updated: 2026-07-24

The criteria for the cross-surface conflict pass. Where [criteria.md](criteria.md) judges one surface
against current model capability, this file judges **two surfaces against each other**: the unit is a
*pair* of files, and the finding is that both claim authority over one behavior and disagree.

The three shared axes (evidence tier, authority, severity) are defined once in
[criteria.md](criteria.md) and are not restated here.

**Recheck triggers** — re-verify against live docs when any fires: a change to the memory page's
precedence or load-order text; a change to the skills page's statements about instruction authority;
any new instruction surface added to the product.

## Sources

Every precedence claim below is quoted from a page fetched when this file was written. A claim these
pages do not make is recorded as unresolved and given no winner.

- Memory — CLAUDE.md, `.claude/rules/`, auto memory — <https://code.claude.com/docs/en/memory>
- Skills — <https://code.claude.com/docs/en/skills>

## Why this pass exists

> **Consistency**: if two rules contradict each other, Claude may pick one arbitrarily. Review your
> CLAUDE.md files, nested CLAUDE.md files in subdirectories, and `.claude/rules/` periodically to
> remove outdated or conflicting instructions.
> — memory

The official guidance is to perform this review periodically. It names no mechanism that performs it.
This pass is that mechanism.

## Boundary: the memory layer already has a contradiction check

`claude-memory`'s `audit` skill ships **C6 Consistency** — "Do any instructions contradict each other
across CLAUDE.md, CLAUDE.local.md, and rules files?", grading a contradiction FAIL and a redundancy
WARN ([`plugins/claude-memory/skills/audit/reference/criteria.md`](../../../../claude-memory/skills/audit/reference/criteria.md),
check C6). It is a live check, not a stray reference: the determinism contract names C6 in the
judgment tier. This pass **extends** C6 outward rather than re-implementing it.

| Pair | Owner |
|---|---|
| Both halves inside project `CLAUDE.md` / `CLAUDE.local.md` / `.claude/rules/**` / auto-memory | `claude-memory`'s C6 |
| At least one half outside that set | this pass |

Route accordingly. When a pair is wholly memory-layer, report it as an observation and point the
operator at `/claude-memory:audit` rather than grading it here; when that plugin is not installed,
keep it as a finding so nothing is silently dropped. This mirrors the reciprocal routing
`claude-memory` already performs for content-fit findings.

**Ruling: `~/.claude/rules/` is *outside* C6's population**, so a user-global rule contradicting a
project rule belongs here. C6's own enumeration is project-relative — the audit workflow discovers
rules with `find .claude/rules`, and the orphan-rule script scans `.claude/rules/*.md`. The plugin
does resolve a user-level directory, but only for auto-memory under `~/.claude/projects/<slug>/`,
never for rules. Its official-guidance reference notes `~/.claude/rules/` exists as background and
never audits it.

## Prerequisite: co-residency

A conflict requires both directives to be in the same context window at the same time. Matching text
shapes without this gate produces noise, because most surface pairs never co-load.

| Surface | When resident | Source |
|---|---|---|
| User `CLAUDE.md` | Every session, in full | memory: "CLAUDE.md files are loaded in full regardless of length" |
| Project `CLAUDE.md` / `CLAUDE.local.md` | Every session in that tree, concatenated after user scope | memory: "All discovered files are concatenated into context rather than overriding each other" |
| Nested `CLAUDE.md` in a subdirectory | On demand, when Claude reads a file there | memory: "they are included when Claude reads files in those subdirectories" |
| `.claude/rules/*` without `paths` | Every session | memory: "loaded at launch with the same priority as `.claude/CLAUDE.md`" |
| `.claude/rules/*` with `paths` | Only when a matching file is read | memory: "only apply when Claude is working with files matching the specified patterns" |
| Skill body | Only once invoked, then for the rest of the session | skills: "a skill's body loads only when it's used" |
| Auto memory `MEMORY.md` | Every session, first 200 lines or 25KB | memory |

**Guaranteed pairs** are any two of {user `CLAUDE.md`, project `CLAUDE.md`, unscoped rules,
`MEMORY.md`}. **Conditional pairs** involve a skill body, a path-scoped rule, or a nested `CLAUDE.md`
— real, but they only bite once that surface loads. Report the distinction; do not drop conditional
pairs, because the worked example below is one.

## The five gates

A pair is a conflict only when **all five** hold. Any gate failing removes it from the finding set.

1. **Co-residency** — the two surfaces can be resident simultaneously, per the table above.
2. **Same observable** — both constrain the same decidable act, identified as a (verb, object,
   trigger) triple rather than by topic similarity. "Emoji in a GitHub reaction" and "emoji in
   assistant prose" are two observables, not one.
3. **Opposed polarity** — for at least one input satisfying both triggers, the two prescribed actions
   cannot both be taken.
4. **No arbitration** — neither directive, nor any third resident text, says which wins. An explicit
   precedence sentence, a deference clause, or a config opt-in gate resolves the pair.
5. **Non-vacuous trigger overlap** — a realistic prompt fires both. Directives scoped to disjoint
   conditions (interactive versus autonomous, code versus prose) do not overlap.

### Conflict types, by remediation route

- **Type A — direct contradiction.** Both absolute, opposite polarity. Route: arbitrate, or drop one.
- **Type B — modality collision.** One absolute ("never"), one conditional ("when warranted"), same
  act. The absolute reads as a hard rule and the conditional reads as license, and neither author
  sees the other.
- **Type C — unarbitrated co-authority.** Two surfaces each assert ownership of one decision with no
  precedence statement. Route: one precedence sentence at the higher surface.
- **Type D — split-brain.** Two files govern the same behavior but only one is loaded, so the
  divergence is invisible in-session. Route: import or symlink so both load, or delete the orphan.

## Precedence: what the docs settle, and what they do not

**Report the conflicting pair. Do not adjudicate it.** Where the official docs define an order, cite
it and name the winner. Where they do not, report the conflict as unresolved and invent no winner.

### Settled — cite and name the winner

| Claim | Verbatim source |
|---|---|
| Project rules beat user rules | memory: "User-level rules are loaded before project rules, **giving project rules higher priority**." |
| An unscoped rule ranks equal to `.claude/CLAUDE.md` | memory: "Rules without `paths` frontmatter are loaded at launch with the **same priority** as `.claude/CLAUDE.md`." |
| A mechanism beats instruction text | memory: "Settings rules are enforced by the client regardless of what Claude decides to do. CLAUDE.md instructions shape Claude's behavior but are **not a hard enforcement layer**." |
| Managed policy cannot be excluded | memory: "Managed policy CLAUDE.md files cannot be excluded." |

### Unresolved — report, and name no winner

| Pair | Why |
|---|---|
| User `CLAUDE.md` vs project `CLAUDE.md` | memory: "All discovered files are **concatenated into context rather than overriding each other**", and "Claude may pick one arbitrarily." |
| Skill body vs any `CLAUDE.md` | The skills page states no authority relation between a skill body and a memory surface. Silence is not a winner. |
| Managed policy vs lower scopes | "Loads before" and "cannot be excluded" are load ordering and non-excludability. The docs never say it overrides. |

**Do not infer a winner from load order.** The memory page's "instructions closer to where you
launched Claude are read last" is ordering prose that sits beside an explicit denial of override
semantics. Reading it as "later wins" invents precedence the docs decline to state.

**The escape hatch worth naming.** Because a mechanism outranks instruction text, an instruction-level
conflict that keeps recurring is often best resolved by moving one side to a mechanism rather than by
rewriting prose — a `PreToolUse` hook, a `permissions.deny` rule, or, for a tool a specific skill must
never call, the skill's own `disallowed-tools` frontmatter (skills: "Tools removed from Claude's
available pool while this skill is active. Use for autonomous skills that should never call certain
tools, such as `AskUserQuestion` for a background loop"). Offer this as an option; the choice is the
operator's.

## Running the pass

Two departures from the skill's per-surface lanes, both forced by the pairwise unit:

- **One lane over the pair set, not one lane per surface.** A per-surface lane cannot see the second
  half of a pair — that blindness is the reason this pass exists. Bound it under the skill's own
  dispatch gate.
- **Read beyond the editable set.** A surface the inventory recorded as *skipped* — installed
  plugin-cache content, a managed materialization, org-managed policy CLAUDE.md — is still a valid
  conflict participant, because a contradiction is real whether or not this repo may edit either
  side. Include skipped surfaces as read-only participants. When remediation lands on one, it routes
  to the owning repository per the skill's Scope boundary instead of becoming a proposed diff.

## Must-not-flag set

False positives are the failure mode. Each case below is either suppressed by the pre-scan (pinned in
`scripts/conflict-scan.test.sh`) or dropped by the lane at the named gate.

| # | Case | Dropped by | Gate |
|---|---|---|---|
| 1 | Two directives in the **same file** | pre-scan | not cross-surface by construction |
| 2 | A mandate conditioned on an explicit **user-config opt-in** | pre-scan | 4 — the opt-in is arbitration |
| 3 | A prohibition **trailing** the entity and governing a different object | pre-scan | 2 |
| 4 | A prohibition **distant** from the entity on a long line | pre-scan | 2 |
| 5 | Two surfaces that both **mandate** the same entity | pre-scan | 3 |
| 6 | Disagreement about **different entities** | pre-scan | 2 |
| 7 | **Permissive** language ("may override") read as a mandate | pre-scan | 3 |
| 8 | A surface carrying an explicit **deference clause** | lane | 4 |
| 9 | A **general rule plus a narrower exception** | lane | 3 |
| 10 | Two directives about **different scopes** of one topic | lane | 2 |
| 11 | A **scope declaration** — an artifact listing the surfaces it operates on | lane | 2 — not a behavioral claim |
| 12 | Directives scoped to **disjoint conditions** (interactive vs autonomous) | lane | 5 |
| 13 | The **same word with two referents** across surfaces | lane | 2 |

Case 13 is the sharpest in practice, because keyword overlap is exactly what a text scan sees. Two
live instances: a hook blocking shell-redirection file writes reads as contradicting guidance to use a
heredoc for multi-line strings, but one observable is *writing a file by redirection* and the other is
*passing a string to a command's stdin*; and "never skip emoji reactions" against a no-emoji output
rule is a GitHub reaction API call versus assistant prose. Both are correctly-scoped alignments.

Case 8 is the posture the repo already models: a surface that says the project's documented
conventions override its own baseline wherever they conflict has *resolved* the conflict, not created
one. Treat such a clause as the remediation template for Type C, never as a finding.

Case 9 matters most for an absolute that carries its own exception clause sitting beside a directive
presupposing exactly that exception. The pre-scan marks the exception rather than dropping the pair,
because whether the exception is *reachable from the other surface* is gate 4 and needs judgment: an
exception only a human can trigger is not reachable by an invoked skill, so the pair survives.

## Deterministic pre-scan

`scripts/conflict-scan.sh` narrows the quadratic search space to a review queue. It decides only the
four gates a text scan can decide — distinct files, same entity, opposed polarity, and the opt-in
filter — and emits `fileA:lineA|fileB:lineB|entity|flags`, always exiting 0. Entities are derived by
CamelCase shape rather than from a hardcoded tool list, so the scan stays correct as the tool surface
changes.

It is advisory. A row is a candidate, never a finding: gates 2 and 5 are not greppable, and the lane
refines every row against the must-not-flag set above.

**Why it stays advisory rather than becoming a CI gate.** Measured over this repository's own skill
bodies plus its root `CLAUDE.md`, the scan returns 169 candidate rows in about 2 seconds. 121 of them
name a CamelCase *proper noun* — `GitHub`, `PowerShell`, `EventStorming`, `GraphQL` — not a directive
about a tool. Only the `AskUserQuestion` rows survive entity triage. A 28% precision rate is a good
review queue and a bad gate, so no conflict class in this pass is currently gate-grade: gates 2 and 5
carry the discrimination, and both need a model. Should a class ever reach gate-grade precision, its
home is a repo-level `scripts/check-*.sh` + `.test.sh` + `ci.yml` lane following the silent-skip
gate's documented lane shape — not this skill.

## Worked examples

Two instances, both verified in this repository, both illustrating a different half of the pass.

**1. A skill body against the user's global CLAUDE.md — cross-layer, conditional, safety-bearing.**
`~/.claude/CLAUDE.md` carries "Ask questions inline; never use the `AskUserQuestion` tool unless
explicitly asked to use it", resident in every session. Against it,
`plugins/repo-hygiene/skills/clean/SKILL.md` states "**Mandatory gate:** show dry-run output →
`AskUserQuestion` → only then `--apply`". Across `plugins/**/*.md` excluding changelogs, 62 lines name
the tool and 11 carry a `use_ask_user_question` opt-in gate on the same line, leaving 51 ungated.

All five gates hold. Gate 4 turns on the prohibition's exception being unreachable: "unless explicitly
asked" is satisfiable by the user, never by an invoked skill. Type A, conditional co-residency,
verdict **unresolved** — the skills page states no authority relation between a skill body and a
memory surface. It is not a style nit: in `repo-hygiene:clean` and `disk-hygiene:clean` that call *is*
the destructive-action confirmation gate, so resolving toward the CLAUDE.md degrades a safety
mechanism while resolving toward the skill disobeys a standing instruction. Report both anchors and
let the operator choose.

**2. A skill's `description` against its own body — the divergence class, inside this repo.**
`claude-memory:audit`'s description sells "memory health" and greps zero for conflict, contradict, or
consistency, while the skill ships C6, an explicit contradiction check. The two surfaces disagree
about what the skill does. This is why three independent incumbent searches over skill descriptions
concluded no conflict detector existed in this repository: a check invisible from the discovery
surface is, for routing purposes, absent. Type C.

## Output format

A conflict finding is a **pair**, so it is reported as one. For each finding give:

- both anchors as `path:line`, mandate side first
- the behavior at issue, stated as the (verb, object, trigger) triple
- the two contradictory claims **quoted verbatim**
- the conflict type (A–D), and which surfaces are guaranteed versus conditional co-residents
- the precedence verdict: the winner **with its doc citation**, or `unresolved` with the reason

A clean pass ("No cross-surface conflicts found.") is a valid outcome. This pass never edits a file
and never picks a winner the docs do not state.
