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
| `/playbooks:repo-sweep review` | Ask the user what went wrong, dispatch an independent reviewer on the last step, merge both lists, audit and file each problem after approval | [reference/review.md](reference/review.md) |

No argument: run `${CLAUDE_SKILL_DIR}/scripts/state.sh` (below). Exit 10 or 11 means `plan`; exit 0
means `next`. Say which you chose.

Read the matching procedure file before acting. Each action runs in a fresh session: `next` and
`review` rebuild all state from the PR body and the branch, never from the conversation.

Sweeps run in worktree-isolated sessions. In procedures, call scripts by path (`S/state.sh`, not
`bash S/state.sh`; they are executable) and run each git command as its own Bash invocation.
File issue bodies from a path, not from stdin. The full record is the worktree skill's
[reference/gather-block.md](https://raw.githubusercontent.com/melodic-software/claude-code-plugins/main/plugins/source-control/skills/worktree/reference/gather-block.md),
"Command shapes an isolated session accepts".

**Record.** Claim: a worktree-isolated session refused `bash <script>`, a chained
`git fetch ... && git merge --ff-only ...`, and `gh issue create --body-file -` fed from a
heredoc whose text mentioned git; direct script paths, one git command per call, and a body file
were accepted. Basis: observed during the melodic-software/.github sweep (PR
melodic-software/.github#153), recorded in
[#4537](https://github.com/melodic-software/claude-code-plugins/issues/4537). Rechecked against
Claude Code 2.1.284 on 2026-09-29: the Command shape bullet of
<https://code.claude.com/docs/en/worktrees#how-claude-code-enforces-isolation> and the changelog
after 2.1.259 through 2.1.284 name none of the three forms. Changelog 2.1.257 stopped refusing
heredocs that never touch git and 2.1.259 stopped refusing loops, xargs pipelines and
launcher-wrapped commands that cannot reach the main checkout; 2.1.274 refused more nested
expansions. Status: all three forms unverified, so the conservative procedure stays. Not
re-probed in a live isolated session. As of: 2026-09-29. Recheck: the Command shape bullet or a
release note changes which Bash forms an isolated session accepts, or a live isolated session
runs the three forms. The procedure files point here for these shapes.

## Scripts

All under `${CLAUDE_SKILL_DIR}/scripts/`. Invoke by path, not through `bash`. Exit 2 is a usage
error everywhere; codes 10 and up carry the meanings below; any other non-zero code is a failed
`gh`, `git`, or `jq` call.

| Script | Does | Exit codes |
|---|---|---|
| `catalog.sh <catalog>` | TSV per entry: id, phase, skills, args, checked, issue, applies-when, prime (`false` skips orchestrate/use-your-skills in `next`). `--override <id>` / `--notes <id>` print that block | 1 duplicate id, entry with no `- skill:` line, unknown id |
| `skill-version.sh [--dir <loaded-dir>] <skill>...` | `<skill>@<version>`. `plugin:skill`: with `--dir` before it, the version of the copy the session loaded, from the nearest `plugin.json` or the plugin cache path, naming on stderr a version that differs from the install record; else the installed plugin's version, `@unknown` when not installed. `REPO_SWEEP_PLUGIN_DIRS` (colon-separated, as passed to `--plugin-dir`) overrides the install record. Bare name: `@personal` or `@project` when a skill of that name there replaces the bundled one, else `@builtin-<claude --version>`, `@unknown` when that prints none | 2 `--dir` with no value or no skill after it |
| `history.sh <catalog>` | TSV id, recommendation (`run`, `rerun`, `rerun-optional`), reason, from merged sweep PRs then `Playbook-Step` trailers | 1 catalog error |
| `render.sh --checklist <catalog> <selection-line> [<recs-tsv>]` | The PR checklist block plus `Not run:` | 1 bad id, selection, or TSV |
| `render.sh --page <catalog> <recs-tsv>` | The filled selection page on stdout | 1 as above, or template missing |
| `state.sh` | `key value` lines: `pr`, `branch`, `pr-state`, `mergeable CONFLICTING`, `playbook`, `dirty`, `untick-committed <id> <sha> <skill@version>...`, `done-unverified <id>`, `next <id> in-progress\|pending`, `sweep <n> <branch>` | 0 next step found; 1 no markers; 10 no sweep PR; 11 PR merged or closed; 12 dirty tree, step pending; 13 all done; 14 one open sweep on another branch; 15 several open sweeps |
| `tick.sh <id> in-progress` / `[--partial <detail>] committed <sha> <skill@version>...` / `[--partial <detail>] filed <issue-url> <skill@version>...` / `no-findings <skill@version>...` / `partial <detail> <skill@version>...` / `not-applicable <evidence>` / `[--partial <detail>] report-only <n> <skill@version>...` / `[--partial <detail>] declined <n> <skill@version>...` | Sets that checklist line, re-reads the body to confirm | 1 line missing, already done, or edit did not land |
| `guard.sh <base-sha> <pr-snapshot-file>` | Checks a step stayed on the branch and opened no PR | 10 stop (prints `branch-changed`, `base-not-ancestor`, `new-pr` lines); 11 prints `squash git reset --soft <base-sha>` |

The page template is `${CLAUDE_PLUGIN_ROOT}/reference/repo-sweep-plan-page.html`.

## Formats

**Catalog** (`catalogs/<playbook>.md`, playbook name is the file stem): `###` heading is the
entry id; `- skill:` one or more skill names, comma-separated, run in order, each `plugin:skill`
or a bare name for a skill bundled with Claude Code; `- args:`,
`- applies-when:`, `- checked: true|false`, optional `- prime: false` (omit or any other value
means `next` invokes orchestrate and use-your-skills), optional `- issue:` one line each; optional
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

`[ ]` pending, `[~]` in progress (left in place when a step stops partway), `[x]` done. A done
line is one base outcome, then an optional partial suffix, or the separate not-applicable form:

- Base outcomes: `committed <short-sha>`, `no findings`, `no fix-eligible findings (N
  report-only)` when the skill produced report-only tiers the user reviewed and nothing was edited,
  `filed <issue-url>` when the step's only findings were fixed in another repository and filed
  there (`history.sh` adds no rerun path for it, so only a changed skill version recommends one;
  the operator decides when the upstream issue closes), or `findings declined (N)` when the user declined every fix-eligible finding shown. No commit
  carries the scope decisions of a declined step, so they live in a `repo-sweep scope decisions:
  <id>` comment on the sweep PR.
- Suffix `, partial coverage: <detail>` (one line, no commas) when the skill ran but did not
  cover the whole repo. It follows any base outcome, so partial never hides a commit or a
  report-only count. `tick.sh <id> partial <detail>` is the shorthand for `no findings` plus the
  suffix; `--partial <detail>` right after `<id>` adds it to `committed`, `report-only`, and `declined`.
  `history.sh` recommends `rerun` after partial coverage.
- `not applicable: <evidence>` replaces the base outcome and records no `skill@version`. `history.sh` ignores such a line for
  version history.

The next step is the first `[~]`, else the first `[ ]`.
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
- A bare skill name is stamped `@builtin-<version>` without proof that the bundled skill exists.
  A same-named personal or project skill replaces the bundled one and is stamped `@personal` or
  `@project` instead ([skills: resolve skills that share a name](https://code.claude.com/docs/en/skills#resolve-skills-that-share-a-name),
  fetched 2026-09-27). The Claude Code version standing in for a bundled skill's version is an
  inference from the observed path: a bundled skill loaded from
  `/tmp/claude-1000/bundled-skills/2.1.283/...` while `claude --version` printed 2.1.283
  ([#4601](https://github.com/melodic-software/claude-code-plugins/issues/4601)); no docs page
  states it. As of 2026-09-29, from that observation. Recheck when that docs table changes or a
  Claude Code release note gives bundled skills their own versions.
- A session keeps the plugin versions it loaded until `/reload-plugins` or a new session, while
  `installed_plugins.json` moves on a mid-session update. Without `--dir`, `skill-version.sh`
  reports the installed version, which may never have run; `next` passes each skill's loaded
  directory and stops after an update notice. A `--plugin-dir` sweep sets
  `REPO_SWEEP_PLUGIN_DIRS` to the same directories. Record: the running session keeps the
  versions it loaded
  ([plugins: loading](https://code.claude.com/docs/en/plugins/loading), fetched 2026-09-28);
  the Skill tool's "Base directory for this skill" line is the only source of the loaded path,
  and no docs page names it. Recheck when the loading page changes or a plugin env var exposes
  the loaded version.
- One session per sweep. `tick.sh` verifies its own write but takes no lock; two sessions ticking
  one PR body can lose a tick.
- An override exists only while a skill hardcodes its own branch, PR, or commit structure and
  offers no flag for the caller to set them. State it as your own instruction before invoking the
  skill; never append it to the skill's arguments. `plan` flags an override whose tracking issue
  has closed so it can be removed from the catalog.
- A skill that commits anyway is squashed into the one step commit by `guard.sh` exit 11. A skill
  that switches branch or opens a PR stops the step (exit 10); run `review` to file it.
- `review` never reuses the session that ran the step: dispatch a separate reviewer with procedure
  files and artifacts only, then merge its list with what the user reports.
- Dotfiles sweeps run in a chezmoi source worktree and apply each changed target right after the
  step commit; see [reference/next.md](reference/next.md).
