# Default mode — lifecycle-tiered dispatch

The skill's default action: read the git facts, classify the change into a lifecycle tier, dispatch the applicable surfaces, normalize, and persist findings.

## Clean-tree short-circuit + untracked-only diagnostic

Decide whether there is anything *diffable* to review — BEFORE tier classification:

1. **Truly clean** — `git status --porcelain` empty AND the branch is not ahead of its base (the pre-computed committed shortstat is empty) AND no open PR → report "no changes to review", spawn nothing, write no findings file. A clean committed branch with no PR yet is the *reviewable* case below, not this one.
2. **Untracked-only** — porcelain shows ONLY `??` entries AND the branch is not ahead of its base AND no open PR → report: ``Only untracked files present — `git diff` cannot show them; `git add` them to include in review.`` Spawn nothing. **Do NOT stage the files** — review modes mutate nothing but the findings file.
3. **Reviewable** — tracked uncommitted changes OR ahead of base OR an open PR → proceed against the review diff base.

## Leaf diff target

Dispatched surfaces diff the **review diff base** (SKILL.md "Shared inputs") in EVERY case — `git diff <merge-base>` includes uncommitted tracked edits alongside committed branch changes, so it covers dirty trees, clean committed branches, and open PRs alike, while `git diff HEAD` on a dirty ahead-of-base branch would show only the dirty edits and drop the committed changes. Instruct each surface to run the merge-base command itself — never a hardcoded `git diff HEAD`.

## Tier classification

Deterministic diff-size thresholds, refined by a judgment layer — a 30-line change touching auth or crossing a module boundary is NOT "small" in risk even if small in size; promote it. Size = the SUM of the two pre-computed shortstats (committed-vs-merge-base + uncommitted) so dirty tracked edits count; when an open PR targets a non-default base, recompute the committed side against that `baseRefName` first.

| Tier | Size trigger | Promote when | Surfaces |
|---|---|---|---|
| **small** | <50 changed lines | — | `code-reviewer`; + `security-reviewer` when auth/input/secrets paths are touched |
| **medium** | 50–300 | small diff but security-sensitive, boundary-crossing, or high blast radius | small set + orchestrator plugin(s) (SKILL.md "Orchestrator plugins") + `architecture-guardian` when module/layer structure is touched |
| **large** | >300 OR cross-cutting (many dirs / many ecosystems) | medium diff that is cross-cutting | medium set + the project's ownerless review-criteria docs as slice-subagents (`leaf-roster.md`) |

## Tier transparency (mandatory)

Before dispatch emit ONE line:

```text
Tier: <small|medium|large>; surfaces run: [<list>]; surfaces SKIPPED at this tier: [<list>]
```

A skip is a fidelity choice — a small auth-touching diff that skips the security surface is a downgrade; naming the skip lets the user override ("run medium anyway").

## Findings-writer contract

Persist the ranked report (post-normalization) to the findings location (SKILL.md "Shared inputs"):

```bash
TS="$(date -u +%Y%m%dT%H%M%SZ)"   # colon-free, Windows-safe
# write to <findings-location>/${TS}-<topic>.md   (<topic> sanitized to [a-z0-9._-])
```

**Relativize machine paths BEFORE writing** — strip the repo root, replace the home directory with `~`. Findings cite `file:line` repo-relative only.

### Findings-file shape (stable contract — the fix action consumes it)

```markdown
---
type: review-findings
date: <ISO-8601 UTC>
branch: <branch>
tier: <small|medium|large>
---

## Findings

| Rank | Tier | Confidence | Location | Surface(s) | Finding | Action |
|------|------|------------|----------|------------|---------|--------|
| 1 | CRITICAL | high | path:line | code-reviewer, pr-review-toolkit | ... | ... |

## Unparsed

<raw text of any finding Stage 0 could not parse — never dropped>

## Surfaces

Ran: [...]. Returned no result: [...] (with cause when known).
```

`tier`, the `## Unparsed` appendix, and the `## Surfaces` reconciliation line are required — they keep the report honest about coverage and never silently drop a finding.

**Cell-escaping rule (required — the fix action parses this table):** inside `Finding` and `Action` cells, escape literal `|` as `\|` and replace newlines with spaces. Reviewer text routinely contains pipes (TypeScript unions, shell pipelines); unescaped, a row splits into phantom columns and the fix action misreads it.
