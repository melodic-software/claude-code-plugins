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

Persist the ranked report (post-normalization) to the findings location (SKILL.md "Shared inputs"),
on the terms of the findings-file contract:
[`findings-file-shape.md`](../../../reference/findings-file-shape.md).

Read it before writing a findings file. It carries the file-name and timestamp rules, the
frontmatter and table shape the fix action parses, the cell-escaping rule, and the never-overwrite
rule. It sits at plugin level rather than here because the repo-level detector-findings convention
and third-party producers both cite it, and neither can reach into this skill's `context/` tree.
