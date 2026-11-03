# 3.2 CI failure resolution (RESEARCH-GATED)

Part of [Phase 3: Monitor](monitor.md), which lists every section's file; a bare § number names a section listed there. Every push and every pause for input in this phase follows the phase-wide rules in [§3.0.6](monitor-multi-pr-scan.md) ("Monitor does the work").

**Rule: no edit without research.** For each failed check:

1. **Read full failure context:** the prioritized chain in [§3.1](monitor-ci-loop.md) above (annotations → full ZIP → last-resort CLI view). Never broad keyword grep
2. **Explore:** read source files, check similar code, review the project's own rules, check `git log`
3. **Research:** research the specific error in the exact framework/version, via your environment's research skill when one exists, otherwise direct doc lookups. Require multi-source consensus (aim for 3 sources)
4. **Present the proposed fix with evidence:** error, root cause, proposed fix, sources with URLs, confidence level (HIGH/MEDIUM/LOW). If LOW, escalate. If MEDIUM, present trade-offs
5. **Implement** (only after 1-4): make the change, re-run the project's build/test/lint gate, commit. Push once per cycle, after every failed check is fixed and with any [§3.3.2](monitor-comments.md) review fixes, which wait for every reviewer on the head (§3.3.2 step 0)
6. **Loop restarts:** new push triggers 3.1 again. Track iteration count

**Stale branch recovery.** If CI fails because the branch is behind the default branch (merge conflicts, "branch is not up to date" errors, or tests failing on default-branch-only changes): integrate, resolve conflicts conservatively, push, and restart the monitor loop from 3.1. Unlike a code failure, the integration itself has no research gate; only conflicts requiring intent judgment do.

**Merge-forward is the default integration; rebase is the exception.** `git merge <remote>/<default-branch>` *into* the PR branch resolves staleness and pushes **fast-forward**, with no force-push and no history rewrite. A rebase rewrites the branch and demands `git push --force-with-lease`, which permission classifiers commonly deny in autonomous/auto-mode sessions, and a denied force-push is no reason to open a fresh branch and PR: the stale branch needed a merge-forward. Under a squash-only default branch, the PR branch's merge commits collapse to one commit on merge, so linear-history requirements hold. Repeated merge-forwards as the default branch moves cost nothing. Rebase only when the project's convention requires a linear PR branch *and* force-push is actually available.

**Escalation guard.** After **3 fix iterations**, STOP and present a history table; the root cause may be environmental.
