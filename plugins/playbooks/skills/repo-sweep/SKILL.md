---
description: "Run a playbook of hygiene skills through one repository per sweep: one branch, one draft PR whose body holds the step checklist, one commit per step, /clear between steps, resumable from any session or machine. Actions: plan (recommend run, rerun, or not-applicable per catalog entry, open the selection page, open the draft PR), next (run the first unticked step), review (file skill defects found in the last step). Use when: 'sweep this repo', 'run the hygiene playbook', 'repo sweep', 'next sweep step', 'continue the sweep', 'review the last sweep step'."
argument-hint: "plan | next | review"
user-invocable: true
disable-model-invocation: true
metadata:
  workflow-stage: anytime
  summary: Run the hygiene skill catalog through one repo, one PR, one commit per step
---

# repo-sweep

Runs the skills in `catalogs/hygiene.md`, in file order, against the current repository. The
catalog is the only home for which skills run, their order, arguments, applies-when tests,
default checked state, and override text; changing a sweep means editing the catalog.

## Invocation

| Invocation | Action | Procedure |
|---|---|---|
| `/playbooks:repo-sweep plan` | Recommend per entry, open the selection page, create the sweep branch and draft PR | [reference/plan.md](reference/plan.md) |
| `/playbooks:repo-sweep next` | Run the first unticked step: audit, review findings with the user, fix, one commit, tick | [reference/next.md](reference/next.md) |
| `/playbooks:repo-sweep review` | Ask what went wrong in the last step; audit and file each problem after approval | [reference/review.md](reference/review.md) |

No argument: run `state.sh` (below). Exit 10 or 11 means `plan`; exit 0 means `next`. Say
which you chose.

Read the matching procedure file before acting. Each action runs in a fresh session: `next` and
`review` rebuild all state from the PR body and the branch, never from the conversation.

## Scripts

All under `${CLAUDE_SKILL_DIR}/scripts/`. Exit 2 is a usage error everywhere; codes 10 and up
carry the meanings below; any other non-zero code is a failed `gh`, `git`, or `jq` call.

| Script | Does | Exit codes |
|---|---|---|
| `catalog.sh <catalog>` | TSV per entry: id, phase, skills, args, checked, issue, applies-when. `--override <id>` / `--notes <id>` print that block | 1 duplicate id, missing skill, unknown id |
| `skill-version.sh <plugin:skill>...` | `plugin:skill@version`; `@builtin` without a plugin prefix, `@unknown` when not installed | 0 |
| `history.sh <catalog>` | TSV id, recommendation (`run`, `rerun`, `rerun-optional`), reason, from merged sweep PRs then `Playbook-Step` trailers | 1 catalog error |
| `render.sh --checklist <catalog> <selection-line> [<recs-tsv>]` | The PR checklist block plus `Not run:` | 1 bad id, selection, or TSV |
| `render.sh --page <catalog> <recs-tsv>` | The filled selection page on stdout | 1 as above, or template missing |
| `state.sh` | `key value` lines: `pr`, `branch`, `pr-state`, `playbook`, `dirty`, `untick-committed <id> <sha> <skill@version>...`, `done-unverified <id>`, `next <id> in-progress\|pending`, `sweep <n> <branch>` | 0 next step found; 1 no markers; 10 no sweep PR; 11 PR merged or closed; 12 dirty tree, step pending; 13 all done; 14 one open sweep on another branch; 15 several open sweeps |
| `tick.sh <id> in-progress` / `committed <sha> <skill@version>...` / `no-findings <skill@version>...` | Sets that checklist line, re-reads the body to confirm | 1 line missing, already done, or edit did not land |
| `guard.sh <base-sha> <pr-snapshot-file>` | Checks a step stayed on the branch and opened no PR | 10 stop (prints `branch-changed`, `base-not-ancestor`, `new-pr` lines); 11 prints `squash git reset --soft <base-sha>` |

The page template is `${CLAUDE_PLUGIN_ROOT}/reference/repo-sweep-plan-page.html`.

## Formats

**Catalog** (`catalogs/<playbook>.md`, playbook name is the file stem): `###` heading is the
entry id; `- skill:` one or more `plugin:skill` names, comma-separated, run in order; `- args:`,
`- applies-when:`, `- checked: true|false`, optional `- issue:` one line each; optional
`#### Override` and `#### Notes` blocks. `##` phase headings group entries for display only.
Arguments in angle brackets are resolved per repo before the step runs.

**PR checklist**, the only machine-read part of the PR body:

```markdown
<!-- repo-sweep:begin playbook=hygiene -->
- [ ] dead-code: code-tidying:audit-dead-code
- [~] batch-simplify: code-tidying:batch-simplify
- [x] residue-dissolve: code-tidying:audit-comment-residue@1.1.0, code-tidying:dissolve-comments@1.4.0, no findings
<!-- repo-sweep:end -->
```

`[ ]` pending, `[~]` in progress (left in place when a step stops partway), `[x]` done with
`committed <short-sha>` or `no findings`. The next step is the first `[~]`, else the first `[ ]`.
A `Not run:` list outside the markers records entries left unchecked at plan time.

**Step commit** ends with a `Scope decisions:` section, then one final trailer paragraph:

```text
Scope decisions:
- <question>: <answer>

Playbook: hygiene
Playbook-Step: code-tidying:audit-dead-code@1.4.0
Co-Authored-By: ...
```

One `Playbook-Step` per skill the step ran.

**Selection line** the page emits: `repo-sweep-selection: <id>,<id>,...`, checked ids in order.

## Repo order

Alphabetical from `.github`, the chezmoi dotfiles source last. `plan` states this; nothing
tracks which repo is next.

## Next

/source-control:pull-request ready

After the last step, to merge the base, verify, and mark the sweep PR ready.

## Gotchas

- Reruns are not deterministic. A skill that ran at the same version can still find new things,
  so `rerun-optional` is never skipped automatically; the user decides.
- One session per sweep. `tick.sh` verifies its own write but takes no lock; two sessions ticking
  one PR body can lose a tick.
- An override exists because the skill hardcodes its own branch, PR, or commit structure. State
  it as your own instruction before invoking the skill; never append it to the skill's arguments.
  `plan` flags an override whose tracking issue has closed so it can be removed from the catalog.
- A skill that commits anyway is squashed into the one step commit by `guard.sh` exit 11. A skill
  that switches branch or opens a PR stops the step (exit 10); run `review` to file it.
- Dotfiles sweeps run in a chezmoi source worktree and apply each changed target right after the
  step commit; see [reference/next.md](reference/next.md).
