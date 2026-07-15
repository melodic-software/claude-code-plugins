# Execution Phase Gotchas

Build this file iteratively from real failure patterns encountered during implementation. Each entry should describe what went wrong, why, and how to avoid it.

## Initial entries (from project history and research)

### Pushing through a broken approach

**What happens**: Plan assumed API X works a certain way, but implementation reveals it doesn't. Instead of replanning, you write workarounds until the code is a mess of hacks.

**Why it's bad**: Workarounds compound. Each one constrains the next, until the implementation is fragile and unmaintainable. The replan you avoided for 10 minutes becomes a 2-hour rewrite.

**How to avoid**: When you find yourself writing the second workaround, stop. Route back to the planning skill for a plan review. A 5-minute replan is cheaper than an hour of accumulated hacks.

### Building on broken code

**What happens**: A build error appears after the first logical block, but you continue implementing the next block because "I'll fix it later."

**Why it's bad**: Second block's code may compile against the wrong types, methods, or signatures — you're writing code against a broken API. When you fix block 1, block 2 may need significant rework.

**How to avoid**: Fix build errors before continuing. Incremental validation cadence (implement → build → test → commit) exists precisely for this.

### Forgetting the branch check

**What happens**: You start implementing on `main` and only catch it at push (a pre-push hook blocks it) or merge (branch protection requires a PR).

**Why it's bad**: Not catastrophic, but it wastes the work-on-main commit cycle. You either rebase the work onto a new branch or rewrite history.

**How to avoid**: Step 1 of `/implementation:implement` checks the branch. `git checkout -b <type>/<description>` takes 2 seconds.

### Mixing concerns in commits

**What happens**: A single commit contains a refactor, a bug fix, and a new feature, all touching the same files.

**Why it's bad**: If the feature needs reverting, you lose the refactor and bug fix too. PR review can't evaluate each change on its own merits.

**How to avoid**: Follow Tidy First principle — structural commits separate from behavioral commits. Commit more often, not less.

---

*Add new entries here as they're discovered. Format: What happens / Why it's bad / How to avoid.*
