# One finding, presented, applied, verified

The loop this skill runs. Everything here is per finding; nothing in it is ever
run over a set.

## 1. Present, before asking

Print this block from the record, not from your own reading of the tree:

```text
FN-9a1c4e70   docs/PLUGIN-PHILOSOPHY.md  ->  docs/plugin-philosophy.md

  Collision:        none
  References:       61 site(s) in 48 file(s)
  Rewritten:        54 current-tier site(s)
  Listed, frozen:   6 historical, 1 released
  Needs a human:    2 site(s) marked review
  Generated:        docs/architecture/landscape.json (rebuilt by its own command)
```

Then, before the question, two things the counts do not carry:

- **Every `review` site individually**, with its file, line, and excerpt. These
  are ambiguous bare stems. The apply never writes one, so an operator who wants
  a `review` site changed is agreeing to edit it by hand afterwards, and needs to
  see it now to know that.
- **The form table for every tier the finding touches**, from
  [`../../audit-file-names/context/tiers.md`](../../audit-file-names/context/tiers.md).
  Accepting a rename is accepting what happens to each shape of citation, and a
  maintainer who expects a frozen tier to change needs to see that it will not.

Ask for this finding, by id. Nothing else.

## 2. Apply, one id per call

```bash
${CLAUDE_SKILL_DIR}/scripts/apply-rename.sh \
  --artifact <resolved>/file-names.md --id FN-9a1c4e70 --root <repo>
```

`--dry-run` prints the same decisions without touching the tree; use it when the
operator asks what a finding would do, never as a substitute for the presentation
above.

The output is five rows: `APPLIED`, `EDITED`, `SKIPPED`, `DRIFTED`,
`REGENERATED`. Read them back rather than summarizing them.

- `DRIFTED` above zero means a site's recorded line no longer carries the old
  name. The script named each one on stderr and edited none of them. Say which,
  and say that a re-audit is what settles it. Do not go and edit them.
- The exits: `0` applied, `1` blocked with the reason and the remedy on stderr
  and nothing changed, `2` a usage or prerequisite problem. A `1` is reported to
  the operator as it was written; it is not retried with different arguments.

## 3. Sweep for stragglers, per pair

The audit's sweep found the sites it knows how to classify. Forms outside that
set exist in any real tree. For every pair whose record reached `applying` or
`applied`, including one whose apply was interrupted, invoke the sibling through
the Skill tool:

```text
/docs-hygiene:rename-references audit orphans <old> to <new>
```

It is an audit. Anything it finds is reported to the operator, with the decision
about it left to them.

## 4. Verify, then move to the next finding

- `git -C <repo> diff --name-status HEAD` shows one `R` line for this pair, and
  every other changed path appears in this record's site table.
- A frozen-tier file in the record is absent from that list.
- The record reads `- **Status:** applied`.

Then present the next finding. One acceptance covers one finding, and the next
one starts at step 1.

## On a decline

Write `declined` into the record and stop. Then offer, once, the durable form:
an entry under `file_names.exempt_paths` in the tracked
`.claude/docs-hygiene.json`, which every checkout carries, unlike the artifact.

Offer it; never take it. Declining this rename and agreeing never to be asked
again are two decisions, and the operator makes the second one.
