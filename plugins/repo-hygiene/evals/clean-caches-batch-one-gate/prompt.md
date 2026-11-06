---
description: "Fleet caches clearing goes through clean-batch behind one gate. Slash-invoked with trailing prose, so there is no Skill grader; resolve-clean-action.sh on the unquoted prompt prints Action: caches-batch. The legacy prompt said 'all my ghq repos'; ghq is not in the sandbox, so the prompt names the three repositories the scaffold writes under repos/. clean SKILL.md line 132: each selective tier has a batch form behind ONE gate; line 248: clean-batch.sh --tier caches, default --dry-run; line 252: the dry-run writes a batch plan and prints BatchPlan: and Summary: ... bytes= (surface the bytes), the gate runs once, then --apply --batch-plan <path> once; action-router.md line 73: never per repo. batch-dry-run-ran is the with-only indicator. no-single-repo-caches fails a direct clean-caches.sh call; no-tree-batch fails any tree reset. reports-bytes, asks-confirm (an abort also passes), no-per-repo-gate and names-batch-plan grade the gate. The file graders read each repo's pytest cache, which an apply removes. The apply of the shown plan needs a later user turn and is not measured. The dry-run writes its plan under the plugin data directory; if the sandbox refuses that write, the run must fall back to --batch-plan FILE and reports-bytes or names-batch-plan may fail on that alone. Needs --scaffold --allow-tools Bash."
tags: [repo-hygiene, clean, outcome, batch, destructive-gate, no-network]
max_turns: 25
timeout_seconds: 900
allowed_tools: [Skill, Read, Glob, Grep, Bash]
expected_outcome: "clean-batch.sh --tier caches runs as a dry-run over the three repositories; the reply gives the reclaimable bytes, names the batch plan and asks for one confirmation for the whole batch (or aborts); nothing is applied and every repo's cache survives."
---

/repo-hygiene:clean caches-batch Clear the tool and linter caches across the three repositories under repos/ in this workspace.
