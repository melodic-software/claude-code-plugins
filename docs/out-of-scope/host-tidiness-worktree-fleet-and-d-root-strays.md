# Worktree fleet reconcile and D: root strays

## Decision

**Parked — host-specific, not marketplace code.** #2931 records a tidiness backlog on one Windows
host (93 registered worktrees and six `D:\` root strays). This marketplace does not ship host
cleanup for that machine.

**Claim:** the worktree-fleet reconcile criterion and the `D:\` stray dispositions stay an operator
backlog on that host; they are not a plugin change. **Basis:** #2931 (`needs-human`). The issue's
own "Why this is filed rather than done" records irreversible removal and two prior tidy-ups that
destroyed live work. Option A parks the host-specific backlog. **As of:** 2026-09-28. **Recheck:**
the operator acts on that host, or files a bounded marketplace issue if a reusable merged-PR plus
`git ls-remote` SHA-match criterion is meant to ship.

## Rationale

- The criterion the issue names (merged-PR record plus `git ls-remote` SHA match, not
  `git merge-base --is-ancestor origin/main`) is a host reconcile rule, not a marketplace verb.
- Carve-outs (`D:/worktrees/_vfy/`, uncommitted salvage on `ccp-2840-fix`, live session
  `D:\spike`) are machine-local evidence. Encoding them in a plugin would freeze one host's
  inventory into shipped code.
- A prior cleanup lane was stopped mid-flight by the repo owner. Unattended deletion of that
  backlog is the failure mode the issue exists to prevent.

## Revisit when

- The operator reconciles that host's worktree fleet and `D:\` strays, or
- A maintainer files a bounded marketplace issue to ship the merged-PR plus `ls-remote` criterion
  as a reusable tool, separate from this host's list.

## Prior requests

- #2931 (2026-09-28): drain shipper parks with this ledger entry (no host deletion executed).
