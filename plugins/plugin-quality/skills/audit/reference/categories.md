# Category ledger

The shape `collect-categories.sh` grades and `collect-standards.sh` feeds.
An audit that omits a section is incomplete. `none` is a real answer.
A skipped section is not.

## Sections

| Heading | Closes with |
|---|---|
| `## Errors` | `none`, or one `###` finding per observed defect |
| `## Improvements` | `none`, or findings for behavior the component's own contract or the official component model implies and the component does not do |
| `## Quality of life` | `none`, or findings for friction the operator hit while using the component |
| `## Standards alignment` | `none`, `unresolved` (no convention home and no standards source resolved; the collector's fallback line may follow), or findings |
| `## Emitted findings` | `not-applicable` when the component does not emit findings to a user, or one `###` sample per sampled finding |

The same file carries the auditor's other returns under `## Blindspots`,
`## Doc-worthy gotchas` (each graded `general` or `situational` in its body),
and `## Unverified claims`. These headings are allowed, optional, and not
graded. Any other heading is malformed.

## Finding fields

Errors, improvements, and quality-of-life findings:

```text
### short title
evidence: packet reference or reproduction
remediation: the change, when one is proposed
research: open-question
```

or, when the claim and any remediation are recommendations:

```text
research: tier-0
primary: <url> saved=<path> span=<quoted span>
corroborator: <url> saved=<path> span=<quoted span>
corroborator: <url> saved=<path> span=<quoted span>
```

`tier-1` is the same shape. Every finding in these three sections carries `research:`, not
only those with a `remediation:`: the claim is the statement the work item relies on (what the
harness, a doc, or the plugin does), and a claim that cannot meet the bar is
`open-question`, emitted as an open question and never as a recommendation. One `research:`
line covers the finding's claim and its remediation. A tier record needs the fetched
primary and at least two independent corroborators, each naming the file the bytes were
saved to (an absolute path with no spaces, inside the directory that holds the ledger; a rung-2 read saves the text it received the same way). The
collector checks each record rather than trusting it: the saved file resolves inside the ledger's directory, exists and is
non-empty, and the span, which must sit on one line, is in it (`grep -F` semantics). A
corroborator that repeats the primary's or another corroborator's URL does not count. Standards
findings and emitted-finding samples are graded by their own fields below, and need `research:`
only when they carry a `remediation:`. The tier names are discovery's
source-tier table (`plugins/discovery/skills/research/context/discipline.md`);
this file does not restate that table.

Standards findings add:

```text
convention: <home>/<topic>/README.md:<line>
component: <path>:<line>
```

`convention:` names the source the component disagrees with: the convention home's topic doc
as above, `discipline:<name>` for a posture corrector the session lists, or
`<standards path>:<line>` for a file in the standards repository. `component:` always carries
the line. The collector checks that both fields are present, not the shape of the source.

Emitted-finding samples:

```text
### short title
plugin-said: what the audited plugin reported
verdict: confirmed
basis: the fetched source the verdict rests on
```

`verdict` is `confirmed`, `false`, or `unvalidated`. `confirmed` and `false` require
`basis:`. `false` is the finding class "the plugin reported X and X was false".
`unvalidated` is not a grade that the plugin was correct.

## Collectors

Run from the audit skill directory:

```bash
bash scripts/collect-categories.sh --notes <audit-notes.md>
bash scripts/collect-standards.sh --component <file> --root <repo>
```

`collect-categories.sh` exits 1 when a section or field is missing.
`collect-standards.sh` exits 0 when the convention home is unresolved and
prints `probes: skipped` plus the fallback. It exits 3 when the resolver
FAILs, and 1 when a probe disagrees. A `status=candidate` line (seam-phrasing)
is a lead, not a finding: it never changes the exit, and it becomes a
Standards alignment finding only after the cited line is read against the
convention's three elements and instructs an invocation. Hook-budget is `not-applicable` here
because cost is measured, not grep-graded; the hook lens still asks for it.
Windows-path-emit is `not-graded` unless a suppressor is exported: the
collector cannot see a POSIX path handed to a Windows-native process, so the
auditor reads the component for that against the convention.
