# changelog apply --ci: the unattended run and its plan

`apply --ci <X.Y.Z | A..B>` runs `apply` with nobody to answer. It asks nothing, pushes nothing,
opens no pull request, files no issue, comments on nothing, and never writes the ledger. It decides
each row from evidence alone, commits the rows it can apply on one local branch per owner plugin,
and writes a plan that the calling workflow acts on. Anything it cannot decide on evidence becomes a
handoff in the plan: never a guess, never a prompt.

## Range

`--ci` needs an explicit release or range; pasted text and the default range are not accepted. With
none, the run writes no plan (see The plan); when the status script reports the range
`not computed`, the plan is written with status `stopped`. A single release `X` is the range `X..X`.

Branch names cannot hold `..` (git-check-ref-format(1)), so a branch carries the range's ref form
`<ref>`: `X` for a single release and `A-B` for a range. Keys, the plan directory and commit subjects
keep `A..B`.

## Phases under --ci

| Phase | Interactive | `--ci` |
|---|---|---|
| 0 Ingest | as written | Cap exceeded: status `stopped`, one `docs-conformance` handoff carrying the script's `recommend` line. A `warn` line goes to `warnings` |
| 1 Explore, 2 Research | as written | Unchanged. An uncited research claim leaves its row unverified |
| 3 Scope gate | the user picks rows | The rule below picks; nothing is asked |
| 4 Hand off | stage skills, user confirms filing | Branch rows run through the stage skills with `--unattended`; every other row is a handoff, filed by the workflow, not here |
| 5 Native drift | files work items | Its would-be work items are handoffs of kind `native-drift`, each with a plan `key` in the grammar under The plan whose lens is `native-drift` and whose last segment is the item's drift identity `<kind>/<surface>/<component>` with every character outside `[A-Za-z0-9_./-]` (such as `:` and `@`) replaced by `-`, so each drift item keeps its own key; for example the drift key `native-drift:recheck:code-review:review:code-reviewer@agent` gives `changelog:2.1.319..2.1.319:native-drift:recheck/code-review/review-code-reviewer-agent`. The full drift key stays the `Drift key: <key>` line in its body; behavior probes are listed in `probes` and never run live. The previous-run summary is never advanced, so a retry derives the same handoffs and the keys dedupe them |

## Order and checkpoints

The run can end at its turn cap or timeout at any step, and the workflow publishes only the plan
on disk. So the plan is written as soon as the rows are decided and rewritten, whole, as each
step finishes:

1. Once the branch rule below has sorted every row, write the plan with status `planned`, no
   `branches`, each would-be branch row as a `not-applied` handoff whose reason says the run
   ended before its branch, and a `warnings` entry saying Phase 5 has not run.
2. Run Phase 5 and rewrite the plan with its handoffs and `probes`, dropping that warning.
3. Work the branches. After each one commits, rewrite the plan: add its `branches` entry and drop
   its rows from `handoffs`. After one fails, rewrite its rows' reason to the failure.

A stopped run's plan then opens the pull requests for the branches it finished and files every
other row.

## Which rows get a branch

A row goes on a branch only when every condition holds:

1. Its lens is `correct`.
2. Both halves of its false-versus-true pair are cited: the component's line (`file:line`) and a
   docs page stating the true half. A changelog line alone does not meet this; a changelog-versus-docs
   disagreement is a `docs-lag` handoff.
3. The local verifier re-checked it against the current tree.
4. Its edits stay inside one owner plugin: `plugins/<plugin>/` and that plugin's changelog entry or
   fragment location (here `.changes/<plugin>/`), and touch no hold path (the `hold-paths` list in
   `.github/workflows/pr-review-security-hosted.yml`). The workflow's scan job stops the release
   with `stop_reason` `hold-path` when a branch changes one.
5. It is not security-relevant: the item is not a security fix (the rubric's "never skip" class),
   and the owner surface does not enforce permissions, guard tool calls, or handle tokens or secrets.

Every other row is a handoff, with `kind` naming why:

| kind | Row |
|---|---|
| `adopt` | Any adopt row, defer pending probe included: adopting is a decision |
| `nomination` | A replace row, for `/harness-ops:audit-native-overlap` |
| `too-large` | Fails condition 4, or redesigns a component |
| `security` | Fails condition 5 |
| `unverified` | Fails condition 2 or 3 |
| `docs-lag` | A changelog-versus-docs pair, for `/harness-ops:known-issues` |
| `stage-missing` | The planning, implementation or verification plugin is not installed |
| `not-applied` | Its branch failed: the plan was unapproved or verification failed |
| `docs-conformance`, `native-drift` | As in the phase table |

## Branches

For each owner plugin with branch rows, from the base commit:

1. When `changelog/<plugin>/v<ref>` already exists locally (an earlier run in this checkout), leave
   it untouched: list it in `branches` with its current head when its commits from the base touch
   only the paths in condition 4, else move its rows to `not-applied` handoffs. Skip steps 2 to 5.
2. `git switch -c changelog/<plugin>/v<ref>`.
3. `/planning:plan --unattended`, recording in `Approval:` the upstream-apply-changelog lane as the
   mandate and the plugin's pull request as the review surface; `/implementation:implement`;
   `/verification:confirm --unattended`. The plugin's changelog entry is part of the edit.
4. Commit with the subject `chore(<plugin>): address Claude Code v<A..B> changelog` (`v<X>` for a
   single release).
5. Switch back to the base commit.

When the plan comes back unapproved or verification fails, delete that local branch and move its
rows to `not-applied` handoffs. A branch this run did not create is never modified.

## The plan

Written to `<memory_dir>/claude-code-changelog/<A>..<B>/ci-plan.json`, at each checkpoint above. The run's last message ends
with two lines, `ci-plan: <path>` and `status: <status>`. A `no-range` stop has no range directory:
it writes no plan and ends with `ci-plan: none` and `status: stopped`.

Branch names and handoff keys derive from the range, lens and owner surface only, so a rerun of the
same release reproduces them and the workflow can skip what already exists. Every handoff `key`,
native-drift included, matches `^changelog:[0-9.]+\.\.[0-9.]+:[a-z-]+:[A-Za-z0-9_./-]{1,200}$`, and
both sides of `..` are the release being applied, for example
`changelog:2.1.319..2.1.319:adopt:plugins/source-control/skills/pull-request/SKILL.md`.
The workflow stops the release on any other key. `marker.advance` is
always false: the marker moves in the ledger pull request once every row is in a final state
([decisions.md](decisions.md)), so the next run seeing the same release is expected.

```json
{
  "schema": "changelog-ci-plan/1",
  "status": "planned",
  "stop_reason": null,
  "range": "2.1.284..2.1.284",
  "base_sha": "<40 hex>",
  "warnings": [],
  "marker": { "advance": false, "reason": "--ci never writes the ledger" },
  "branches": [
    {
      "plugin": "hooks-kit",
      "branch": "changelog/hooks-kit/v2.1.284",
      "base_sha": "<40 hex>",
      "head_sha": "<40 hex>",
      "files": ["plugins/hooks-kit/skills/elicitation-hooks/SKILL.md", ".changes/hooks-kit/<fragment>.md"],
      "rows": ["changelog:2.1.284..2.1.284:correct:plugins/hooks-kit/skills/elicitation-hooks/SKILL.md"],
      "pr": {
        "title": "chore(hooks-kit): address Claude Code v2.1.284 changelog",
        "body": "No related issue: Claude Code v2.1.284 changelog intake\n\n## Summary\n..."
      }
    }
  ],
  "handoffs": [
    {
      "key": "changelog:2.1.284..2.1.284:adopt:plugins/mcp-kit/scripts/reconnect-servers.sh",
      "kind": "adopt",
      "owner_surface": "plugins/mcp-kit/scripts/reconnect-servers.sh",
      "lens": "adopt",
      "items": ["2.1.284-003"],
      "required_sentence": "Reconnects failed MCP servers one at a time.",
      "reason": "adopting is a decision",
      "title": "harness-ops changelog v2.1.284: adopt on reconnect-servers.sh",
      "body": "..."
    }
  ],
  "notes": [],
  "probes": []
}
```

`status` is `stopped` (no rows were derived; `stop_reason` is `cap-exceeded` or
`range-not-computed`; the scan job alone sets `hold-path`) or `planned` (rows were derived; `branches` and `handoffs` may each be empty).
Handoff bodies carry item ids and the required sentence, never changelog text, matching the ledger
rule in [decisions.md](decisions.md). The workflow groups a release's handoffs into one issue, a
checklist item per handoff. A `cap-exceeded` or `hold-path` plan is the same on every run for its release, so the
workflow files its issue even with no handoffs, opens the issue with a line naming the
`stop_reason`, and marks the release done once that issue holds every handoff key; a filing that
fails leaves the release for the next run. A `range-not-computed` plan can pass on a later run (the
changelog fetch failed, or the page lags the tag), so the workflow files nothing and leaves the
release for the next run. PR bodies follow the consuming repository's pull request template.
