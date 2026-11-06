---
description: "The fleet scan is read-only and has no gate. Slash-invoked with trailing prose, so there is no Skill grader; resolve-clean-action.sh on the unquoted prompt prints Action: scan-batch (the legacy word 'space' resolves to scan and sent it to menu). The legacy prompt said 'all my ghq repos'; ghq is not in the sandbox, so the prompt names the three repositories the scaffold writes under repos/. clean SKILL.md line 132: scan-batch is read-only and has no gate; line 254: --tier scan writes no plan, takes no --apply or --batch-plan, needs no confirmation gate, and prints per-repo Outcome: scanned and Summary: repos=N planned=0 bytes=K; action-router.md line 72: user gate None. scan-batch-ran is the with-only indicator. no-apply-or-plan and no-other-tier fail a plan, an apply or any mutating tier; no-confirm-gate fails a reply that asks to confirm an apply or a deletion. names-each-repo and reports-bytes grade the per-repo outcomes and the summed bytes. The file graders read each repo's build output. Needs --scaffold --allow-tools Bash."
tags: [repo-hygiene, clean, outcome, batch, scan, no-network]
max_turns: 20
timeout_seconds: 900
allowed_tools: [Skill, Read, Glob, Grep, Bash]
expected_outcome: "clean-batch.sh --tier scan runs once over the three repositories; the reply reports each repo's outcome and the summed reclaimable bytes and asks for no confirmation; nothing is removed."
---

/repo-hygiene:clean scan-batch Tell me how much I could reclaim across the three repositories under repos/ in this workspace.
