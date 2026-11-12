---
topic: trust-measures
section: computed
abstract: 'C1 (HIGH): "Over 2026-08-20 to 2026-11-11 on origin/main there were 7652 landings, of which 13 carry a revert subject, a revert rate of 0.17%"'
claims:
  - claim: "Over 2026-08-20 to 2026-11-11 on origin/main there were 7652 landings, of which 13 carry a revert subject, a revert rate of 0.17%"
    id: C1
    confidence: HIGH
    claim_kind: content
    source_owner: "melodic-software"
    tiers: [0]
    applies_to: "version-independent"
    sources:
      - url: "command: bash plugins/work-items/skills/measure-delivery/scripts/delivery-metrics.sh --repo <repo root> --deploy-signal merge-to-default-branch --since 2026-08-20 --until 2026-11-11 --bucket month (output: snapshot-c1.txt, measurement 1)"
        tier: 0
        pool: "git history read by delivery-metrics.sh"
        measures: "first-parent landings (deployments: 7652) and landings that revert (rework_deployments: 13) over the window"
        role: primary
        published: 2026-11-12
        dated_by: "run date of the command"
        applies_to: "version-independent"
        standing: current
      - url: "command: git rev-list --count --first-parent origin/main --since=2026-08-20T00:00:00Z --until=2026-11-12T00:00:00Z; git log --first-parent origin/main (same window) --grep='^Revert \"' --grep='^revert[(:]' (output: snapshot-c1.txt, measurements 2a and 2b)"
        tier: 0
        pool: "git history read by the git CLI directly"
        measures: "landing count (7652) and revert-subject landings (13 of 15 grep hits; 2 hit a body line), independent of the skill's parser"
        role: corroborator
        published: 2026-11-12
        dated_by: "run date of the command"
        applies_to: "version-independent"
        standing: current
      - url: "command: gh pr list -R melodic-software/claude-code-plugins --state merged --search \"revert in:title merged:2026-08-20..2026-11-11\" --limit 100 (output: snapshot-c1.txt, measurement 3)"
        tier: 0
        pool: "GitHub pull request records via the search API"
        measures: "merged PRs in the window whose title starts with a revert form (13), read from GitHub, not from git"
        role: corroborator
        published: 2026-11-12
        dated_by: "run date of the command"
        applies_to: "version-independent"
        standing: current
    inference: "Three reads agree on 13 revert landings, two of them on 7652 landings; 13/7652 is 0.17%"
    qualifiers: ["history as of the last fetch", "counts reverts only by subject form; a hand-written undo under another subject is missed", "this is a revert-based proxy: DORA's deployment rework rate counts any unplanned deployment caused by a production incident, including forward fixes, and no incident record exists here to count those"]
  - claim: "delivery-metrics.sh resolves 6 of the window's revert landings to an earlier landing (change fail rate 0.0008) and leaves 7 unresolved"
    id: C5
    confidence: MEDIUM
    claim_kind: content
    source_owner: "melodic-software"
    tiers: [0]
    applies_to: "version-independent"
    sources:
      - url: "command: delivery-metrics.sh as for C1 (output: snapshot-c1.txt, measurement 1)"
        tier: 0
        pool: "git history read by delivery-metrics.sh"
        measures: "failed_deployments and unresolved_reverts from the skill's target resolution"
        role: primary
        published: 2026-11-12
        dated_by: "run date of the command"
        applies_to: "version-independent"
        standing: current
    inference: "One measurement only; target resolution was not re-derived by a second method"
    qualifiers: ["one measurement"]
  - claim: "In merged PRs from 2026-11-10T11:07Z to 2026-11-12T18:50Z, about 61% were authored and merged by GitHub App identities with no review or comment from the kyle-sexton login: 305 of 500 by gh pr list and 315 of 511 by a GraphQL search of the same merged-at window"
    id: C2
    confidence: MEDIUM
    claim_kind: content
    source_owner: "melodic-software"
    tiers: [0]
    applies_to: "version-independent"
    sources:
      - url: "command: gh pr list -R melodic-software/claude-code-plugins --state merged --limit 500 --json number,author,mergedBy,mergedAt,reviews,comments (output: snapshot-c2.txt, measurement 1)"
        tier: 0
        pool: "GitHub PR records via gh pr list"
        measures: "author, merger, review and comment logins on the 500 most recent merged PRs"
        role: primary
        published: 2026-11-12
        dated_by: "run date of the command"
        applies_to: "version-independent"
        standing: current
      - url: "command: gh api graphql --paginate, search is:pr is:merged merged:2026-11-10T11:07:29Z..2026-11-12T18:50:44Z (output: snapshot-c2.txt, measurement 2)"
        tier: 0
        pool: "GitHub PR records via the GraphQL search API"
        measures: "author and merger actor types, review and comment author logins on all 511 PRs merged in the window"
        role: corroborator
        published: 2026-11-12
        dated_by: "run date of the command"
        applies_to: "version-independent"
        standing: current
    inference: "Two reads of GitHub's records agree at 61.0% and 61.6%; two pools are below the three a HIGH claim needs"
    qualifiers: ["a 2.3-day window", "a lower bound: owner-login PRs may also be agent sessions", "label events and commits pushed by the owner were not read"]
  - claim: "In the same window, 198 of 510 first-parent commits on origin/main carry a Claude co-author trailer, against 191 of the 500 merged PRs authored by the kyle-sexton login"
    id: C3
    confidence: MEDIUM
    claim_kind: content
    source_owner: "melodic-software"
    tiers: [0]
    applies_to: "version-independent"
    sources:
      - url: "command: git rev-list --count --first-parent origin/main --since=2026-11-10T11:07:29Z -i --grep=co-authored-by:.claude"
        tier: 0
        pool: "git history read by the git CLI directly"
        measures: "count of trailer-bearing landings; not joined per PR to author login"
        role: primary
        published: 2026-11-12
        dated_by: "run date of the command"
        applies_to: "version-independent"
        standing: current
    inference: "The two counts are close but were not joined PR by PR, so this indicates rather than shows that owner-login PRs are agent sessions"
    qualifiers: ["no per-PR join"]
  - claim: "On this machine the corrections findings buffer read returned no rows and the checkout has no .work/codify directory"
    id: C4
    confidence: MEDIUM
    claim_kind: content
    source_owner: "melodic-software"
    tiers: [0]
    applies_to: "version-independent"
    sources:
      - url: "command: bash plugins/corrections/tools/findings-buffer/buffer.sh read; find .work/codify -maxdepth 3; find .work -maxdepth 2 -name 'codify*' (output: snapshot-c4.txt)"
        tier: 0
        pool: "local stores on this machine"
        measures: "rows in the local-file buffer adapter and presence of codify proposals on this checkout"
        role: primary
        published: 2026-11-12
        dated_by: "run date of the command"
        applies_to: "version-independent"
        standing: current
    inference: "Three probes of one machine's stores; one pool, so below HIGH"
    qualifiers: ["this machine only; other fleet machines were not read"]
produced_by: phase-1-2-rework
---

# Computed

Raw outputs: `snapshot-c1.txt`, `snapshot-c2.txt` and `snapshot-c4.txt` in this slice.

## Per-measure table

| Measure | Data source | Computable now | Definition to use | Value |
|---|---|---|---|---|
| Revert rate | git history, through /work-items:measure-delivery | Yes | Landings with a revert subject / landings (the skill's deployment rework rate), a revert proxy for DORA's rework rate | C1 (HIGH): "Over 2026-08-20 to 2026-11-11 on origin/main there were 7652 landings, of which 13 carry a revert subject, a revert rate of 0.17%" |
| No-human-touch merge share | GitHub API via gh (author, merger, reviews, comments) | Lower bound only | Merged PRs with no human review, comment, approval, merge or commit, over merged PRs | C2 (MEDIUM): "In merged PRs from 2026-11-10T11:07Z to 2026-11-12T18:50Z, about 61% were authored and merged by GitHub App identities with no review or comment from the kyle-sexton login: 305 of 500 by gh pr list and 315 of 511 by a GraphQL search of the same merged-at window" |
| Corrections converted to checks | none tracked | No | Proven codify proposals whose check was later installed, over codify proposals | C4 (MEDIUM): "On this machine the corrections findings buffer read returned no rows and the checkout has no .work/codify directory" |

## Gaps

- C5 (MEDIUM): "delivery-metrics.sh resolves 6 of the window's revert landings to an earlier landing (change fail rate 0.0008) and leaves 7 unresolved"
- The no-human-touch and corrections values in the table above are MEDIUM: two pools and one pool respectively.
- C3 (MEDIUM): "In the same window, 198 of 510 first-parent commits on origin/main carry a Claude co-author trailer, against 191 of the 500 merged PRs authored by the kyle-sexton login"

## Notes

- No-human-touch share: owner-login PRs cannot be split into human and agent actions by login alone; a full measure needs a per-PR signal for that.
- Corrections converted to checks: needs a tracked record first, such as a trailer or label on the PR that installs a codify-proposed check.
