# Findings-file contract

The shape a findings file must have, and the rules binding whoever writes one.

This file sits at plugin level, outside every skill directory, because it is a
spec that components outside this plugin must read to conform. The repo-level
detector-findings convention cites it, and a convention cannot reach into a
skill's private `context/` tree. `review:fanout` reads it as its own writer
contract; a third-party detector reads it to produce a file the fix action will
consume.

## Findings-writer contract

Persist the ranked report (post-normalization) to the findings location (SKILL.md "Shared inputs"):

```bash
TS="$(date -u +%Y%m%dT%H%M%SZ)"   # colon-free, Windows-safe
# write to <findings-location>/${TS}-<topic>.md   (<topic> sanitized to [a-z0-9._-])
```

**Relativize machine paths BEFORE writing** — strip the repo root, replace the home directory with `~`. Findings cite `file:line` repo-relative only.

**Never overwrite an existing path.** The timestamp has second resolution and the topic is producer-chosen, so `${TS}-<topic>.md` can already exist — another producer wrote in the same second under the same topic. Write `${TS}-<topic>-2.md` instead (the smallest integer `>= 2` whose path is free); the timestamp prefix keeps the directory's name sort chronological either way. Overwriting destroys that producer's findings before the fix action ever sees them, and no consumer can recover them. This is producer hygiene, not an identity: the fix action identifies a consumed file by its CONTENT digest ([`fix-pass-mode.md`](../skills/fanout/context/fix-pass-mode.md) "Step 1: Build the merge set"), never by the shape of its name, so a producer that ignores this rule loses only its own findings and can never corrupt the merge.

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

**`date:` MUST be the instant the file is written** — not the date of the commit under review, not a scan date, not a template constant. `review:fanout` writes the same UTC instant its file name carries. The consumer leans on this: with no digest to compare (a pre-0.20.0 record), `date:` is the only evidence that a same-named file is a NEWER file rather than the one already consumed ([`fix-pass-mode.md`](../skills/fanout/context/fix-pass-mode.md) "Step 1"). A producer that declares a constant `date:` makes its files indistinguishable by age, which is why that comparison subtracts only on a strictly older candidate and keeps everything else. The file name must also end in `.md`, which is what makes it visible to the consumer's scan at all.

`date`, `tier`, the `## By dimension` breakdown, the `## Unparsed` appendix, and the `## Surfaces` reconciliation line are required **of `review:fanout`'s own writer** — they keep the report honest about coverage and never silently drop a finding. They are not the admission test: a third-party producer that omits them is still consumed, on the terms in [`fix-pass-mode.md`](../skills/fanout/context/fix-pass-mode.md) "Step 1: Build the merge set". Emit them anyway — a detector that does contributes its coverage to the merged report instead of a blank. The breakdown exists because a merged rank can mask one dimension failing badly while the others pass; the fix action parses `## Findings`, `## Unparsed`, `## Surfaces`, and `tier:` — unioning the last two across producers — but not the breakdown, so the breakdown alone is presentation-additive.

**Cell-escaping rule (required — the fix action parses this table):** inside `Finding` and `Action` cells, escape literal `|` as `\|` and replace newlines with spaces. Reviewer text routinely contains pipes (TypeScript unions, shell pipelines); unescaped, a row splits into phantom columns and the fix action misreads it.

**Multiple producers, one directory.** Nothing authenticates the writer: this shape is the whole integration contract, so any component that writes a conforming file reaches the fix action without a fanout edit. The fix action therefore consumes the merged SET of unconsumed conforming files for the exact current branch and marks what it consumed — by content digest, not by file name — [`fix-pass-mode.md`](../skills/fanout/context/fix-pass-mode.md) "Step 1: Build the merge set".

The rules binding a NON-fanout producer — where it writes, which fields it computes for itself, its coexistence obligations, and what it may omit — are a cross-plugin concern owned by the detector-findings convention:
<https://raw.githubusercontent.com/melodic-software/claude-code-plugins/main/docs/conventions/detector-findings/README.md>.
The contract owns every general producer rule; this section records fanout's own writer contract.
