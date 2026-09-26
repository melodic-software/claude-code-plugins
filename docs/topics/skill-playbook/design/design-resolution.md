---
outcome: early-exit
tier: B
---

# Design resolution: skill-playbook

Light design. The Brief settles behavior; this file pins the three formats the scripts and the
skill body share. Nothing else is a new contract.

## Catalog file

Path: `plugins/playbooks/skills/repo-sweep/catalogs/<playbook>.md`. Only `hygiene.md` ships. The
playbook name is the file stem.

```markdown
# Playbook: hygiene

## Phase 1: code

### dead-code

- skill: code-tidying:audit-dead-code
- args: .
- applies-when: repo has source code
- checked: true
- issue: #4503

#### Override

Stay on the current branch. Do not create a branch, pull request, or commit; repo-sweep commits.
Tracking issue: melodic-software/claude-code-plugins#4503.
```

- `###` heading: entry id, kebab-case, unique in the file. Ids, not skill names, key the
  checklist, because one step can run two skills (residue then dissolve).
- `skill:` one or more `plugin:skill` names, comma-separated, run in the listed order.
- `args`, `applies-when`, `checked` (`true`/`false`), `issue` (optional): one line each.
- `#### Override` (optional): free text up to the next heading. `next` states it as its own
  instruction before invoking the skill; it is never appended to the skill's arguments.
- `#### Notes` (optional): step guidance for the agent, not passed to the skill.
- File order is run order. Phase headings group entries for display only.

## PR checklist

The sweep PR body holds one block between markers. Only lines inside it are machine-read.

```markdown
<!-- repo-sweep:begin playbook=hygiene -->
- [ ] dead-code: code-tidying:audit-dead-code
- [x] batch-simplify: code-tidying:batch-simplify@2.3.0, committed 1a2b3c4
- [x] residue-dissolve: code-tidying:audit-comment-residue@1.1.0, code-tidying:dissolve-comments@1.4.0, no findings
<!-- repo-sweep:end -->

Not run:
- testing-audit: not applicable, repo has no tests
```

- Line grammar: `- [ ] <id>: <skills>` when pending; `- [~] <id>: <skills>` while in progress
  (set before the step runs, left in place when a step stops partway); `- [x] <id>: <skill@version,
  ...>, committed <short-sha>` or `..., no findings` when done.
- The next step is the first `- [~]` line, else the first `- [ ]` line, inside the markers.
- `Not run:` records entries left unchecked at plan time with the reason. Outside the markers.

## Commit trailers

Every step commit ends with:

```text
Scope decisions:
- <question>: <answer>

Playbook: hygiene
Playbook-Step: code-tidying:audit-dead-code@1.4.0
```

One `Playbook-Step` trailer per skill the step ran. All trailers, including `Co-Authored-By:`,
sit in one final paragraph so git parses them together. A skill that committed several times
inside a step is squashed (`git reset --soft <base>`) into this one commit. History reads them with
`git log --format='%(trailers:key=Playbook-Step,valueonly)'`.

## Selection page round trip

The page emits one line the user pastes back: `repo-sweep-selection: <id>,<id>,...` (ordered,
checked ids only). The render script turns that line into the checklist, so the checklist has one
formatter.
