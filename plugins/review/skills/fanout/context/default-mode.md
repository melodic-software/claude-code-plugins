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

**Never overwrite an existing path.** The timestamp has second resolution and the topic is producer-chosen, so `${TS}-<topic>.md` can already exist — another producer wrote in the same second under the same topic. Write `${TS}-<topic>-2.md` instead (the smallest integer `>= 2` whose path is free); the timestamp prefix keeps the directory's name sort chronological either way. Overwriting destroys that producer's findings before the fix action ever sees them, and no consumer can recover them. This is producer hygiene, not an identity: the fix action identifies a consumed file by its CONTENT digest ([`fix-pass-mode.md`](fix-pass-mode.md) "Step 1: Build the merge set"), never by the shape of its name, so a producer that ignores this rule loses only its own findings and can never corrupt the merge.

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

## By dimension

<the same findings regrouped under one `### <dimension>` heading per Stage-0 category present, rows in merged-rank order with their rank numbers unchanged>

## Unparsed

<raw text of any finding Stage 0 could not parse — never dropped>

## Surfaces

Ran: [...]. Returned no result: [...] (with cause when known).
```

**`date:` MUST be the instant the file is written** — not the date of the commit under review, not a scan date, not a template constant. `review:fanout` writes the same UTC instant its file name carries. The consumer leans on this: with no digest to compare (a pre-0.20.0 record), `date:` is the only evidence that a same-named file is a NEWER file rather than the one already consumed ([`fix-pass-mode.md`](fix-pass-mode.md) "Step 1"). A producer that declares a constant `date:` makes its files indistinguishable by age, which is why that comparison subtracts only on a strictly older candidate and keeps everything else. The file name must also end in `.md`, which is what makes it visible to the consumer's scan at all.

`date`, `tier`, the `## By dimension` breakdown, the `## Unparsed` appendix, and the `## Surfaces` reconciliation line are required **of `review:fanout`'s own writer** — they keep the report honest about coverage and never silently drop a finding. They are not the admission test: a third-party producer that omits them is still consumed, on the terms in [`fix-pass-mode.md`](fix-pass-mode.md) "Step 1: Build the merge set". Emit them anyway — a detector that does contributes its coverage to the merged report instead of a blank. The breakdown exists because a merged rank can mask one dimension failing badly while the others pass; the fix action parses `## Findings`, `## Unparsed`, `## Surfaces`, and `tier:` — unioning the last two across producers — but not the breakdown, so the breakdown alone is presentation-additive.

**Cell-escaping rule (required — the fix action parses this table):** inside `Finding` and `Action` cells, escape literal `|` as `\|` and replace newlines with spaces. Reviewer text routinely contains pipes (TypeScript unions, shell pipelines); unescaped, a row splits into phantom columns and the fix action misreads it.

**Multiple producers, one directory.** Nothing authenticates the writer: this shape is the whole integration contract, so any component that writes a conforming file reaches the fix action without a fanout edit. The fix action therefore consumes the merged SET of unconsumed conforming files for the exact current branch and marks what it consumed — by content digest, not by file name — [`fix-pass-mode.md`](fix-pass-mode.md) "Step 1: Build the merge set". A producer needs nothing beyond this shape; it must NOT append into another producer's file, which would need a write-ordering convention that does not exist.
