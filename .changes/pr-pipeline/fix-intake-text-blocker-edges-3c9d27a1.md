---
bump: patch
---

### Fixed

- Intake apply-verdict now writes a native blocked-by edge for each blocker the issue body names, not only those the triage model's `Blocked by:` line lists, so admission, which reads only native edges, no longer admits an issue whose blocker is named only in its text and the issue lane no longer hands it back to a person. A line that starts with `Blocked by` or `Depends on`, and each list item under a `Blocked by` or `Depends on` heading, names its `#<n>` references and this repository's issue URLs; fenced and inline code, HTML comments, `>` quotes, other repositories' references and pull request URLs name nothing, and a Markdown link, inline or by reference, counts as its target alone, so `[#12](<another repository's issue URL>)` names nothing. Each number is only a candidate: it gets an edge when GitHub answers it is an open issue of this repository, not a pull request, with no edge yet, at most 10 per issue, with the existing missed-edge handling. Edges are written on an escalated verdict too, so an `agent-ready` label a person adds later still finds them; an edge missed on a verdict that is not ready only warns, since no `status: ready` waits on it (`.github/scripts/intake-triage/edges.mjs`, `.github/scripts/intake-triage/apply-verdict.mjs`).
