# L4 encapsulation. Leaked skills in `plugins/repo-fleet-hygiene`

2 violations, both from the plugin README into `repo-fleet-hygiene:audit`.

**Owning skill:** `repo-fleet-hygiene:audit` (`plugins/repo-fleet-hygiene/skills/audit/`).
**Private surfaces reached:** `reference/security-review.md`, `reference/official-sources.md`.
**Leak kind:** private subdir (2 of 2).
**Citing file:** `plugins/repo-fleet-hygiene/README.md`, an external consumer under the contract.

Both cites use a label that shows the leak clearly: the link text is written as if the file were at
the README's own level (`reference/security-review.md`), while the target reaches down into the
skill. A reader cannot tell from the label that the address is inside a private body.

## V-rfh-01. `plugins/repo-fleet-hygiene/README.md:180`

Verbatim:

```text
[`reference/security-review.md`](skills/audit/reference/security-review.md). The audit script uses no
```

**Public surface element:** `/repo-fleet-hygiene:audit`. The sentence continues into a claim about
what the audit script does, so the caller wants the skill's behavior and its stated guarantees.

**Replacement text:**

```text
`/repo-fleet-hygiene:audit`, which carries the security-review posture. The audit script uses no
```

## V-rfh-02. `plugins/repo-fleet-hygiene/README.md:186`

Verbatim:

```text
[`reference/official-sources.md`](skills/audit/reference/official-sources.md).
```

**Public surface element:** `/repo-fleet-hygiene:audit`.

**Replacement text:**

```text
`/repo-fleet-hygiene:audit`, which records the official sources it checks against.
```

## Judgment note

`reference/official-sources.md` is an upstream-drift record, the same genre the repo tracks in
`docs/conventions/upstream-drift/README.md`. If the reconciliation pass decides that upstream-drift
records should be addressable repo-wide, this becomes a **Path A. promote** alongside V-slop-02 in
`ai-slop.md` rather than the route above. As a standalone finding, route is sufficient: nothing
outside this plugin reads the record.

## Cross-lane observations

- L8 (write-for-humans): both lines are in a HUMAN-audience README. The replacements keep the
  sentence intact; verify the surrounding paragraph still scans after the link is dropped.
