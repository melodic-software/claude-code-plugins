# The `tree-batch` action — multi-repo working-tree realignment

Full detail for the batch `tree` mode. SKILL.md §6.5 carries the headline; this
file carries gates, the script contract, and examples. The single-repo `tree`
action ([git-tree-reset.md](git-tree-reset.md)) is unchanged; `tree-batch` is an
additive orchestrator over it.

## Why this exists

A hand-rolled `ghq list` reset loop `reset --hard`'d a repo it was meant to skip:
the skip-match compared a Windows backslash path against a forward-slash path and
silently failed, discarding an uncommitted `.claude/settings.json` edit that was
never staged and could not be recovered. `tree-batch` is the supported capability
that closes both defects — separator-agnostic skip-matching and a dirty-by-default
guard — so the batch reset never has to be hand-rolled again.

## Scope

**In:** run the single-repo `tree` reset across a set of repositories behind one
confirmation gate, with a skip list and a dirty guard, then report a per-repo
outcome summary.

**Out:** the other tiers (`caches` / `build` / `git` / `all`) — `tree` is the
destructive tier that caused the incident and the only one whose batch form needs
these guards; a multi-tier batch is a possible future extension, not built here.
Also out (delegated to the single-repo `tree`, unchanged): the actual reset /
clean / upstream resolution / reparse-point restore. The batch layer runs no
destructive git command itself.

## Script

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/clean/scripts/git-tree-reset-batch.sh \
  [--dry-run|--apply] \
  [--repo DIR]... [--repos-from FILE|-]... \
  [--skip ENTRY]... [--skip-from FILE]... \
  [--include-dirty] \
  [--force-default-branch] [--include-deps] [--include-secrets]
```

Default: `--dry-run`. Output labels and full flag help: script `--help`.

### Repo sources

A `ghq list`, a shell glob, and an explicit list all reduce to a path list:

| Source | How |
| --- | --- |
| explicit list | `--repo DIR` (repeatable) |
| shell glob | the shell expands it into repeated `--repo DIR` |
| `ghq list` | `ghq list -p \| … --repos-from -` (or `--repos-from FILE`) |

Inputs are resolved to their canonical toplevel (`git rev-parse --show-toplevel`)
and deduped, so the same repo named two ways is processed once.

### Skip list (separator-agnostic — the core fix)

`--skip ENTRY` (repeatable) / `--skip-from FILE`. Each enumerated repo path and
each skip entry is normalized to a separator-agnostic key before comparison, so a
skip written with `\` matches a repo path enumerated with `/` and vice versa. An
entry may be an absolute path, an `owner/repo` suffix, or a bare `repo` name;
matching is anchored on segment boundaries (`repo` never matches `other-repo`). A
skip entry that matches **no** enumerated repo is reported as `UnmatchedSkip:` —
the silent skip-failure that caused the data loss is now a visible warning.

### Dirty guard (skip dirty by default)

A repo with uncommitted or untracked changes, OR unpushed commits, is **skipped**
by default with the reason reported. `--include-dirty` opts in and passes
`--allow-unpushed` through so unpushed repos actually reset. This re-enables the
exact data-loss vector, so it is gated like `--include-secrets`: its own explicit
confirmation, naming which repos' uncommitted changes will be discarded.

### Per-repo outcome

Each repo emits `Repo:` / `Outcome:` / `Reason:`. Outcomes: `would-reset` (dry-run)
/ `done` (apply) / `skipped` (skip-list, dirty, or no-upstream) / `blocked`
(default-branch, upstream-unresolved, or a non-git input) / `failed` (child reset
failed mid-apply). A closing `Summary:` line totals each bucket. Child exit codes
map straight through, so single-repo safety semantics are preserved verbatim.

### Default-branch reality

A "fresh-clone state" fleet is typically all on the default branch, and the child
blocks a default-branch reset unless `--force-default-branch`. Expect an all-blocked
dry-run summary in that case and pass `--force-default-branch` once you have
confirmed the plan — the dry-run surfaces this before any mutation.

## Gates

- **Single batch-wide gate:** run `--dry-run` once, show the whole-batch plan (the
  per-repo outcomes + `Summary` + any `UnmatchedSkip`), `AskUserQuestion` once, then
  `--apply` once. One confirmation covers the batch — do not gate per repo. When the
  repo list comes from `--repos-from -` (stdin), the `--apply` invocation must re-run
  the same `ghq list -p | …` pipe (stdin is consumed once); the list is re-enumerated
  at apply, a benign window in the same class as the child's fetch-between-dry-run-and-
  apply.
- `--include-dirty` and `--include-secrets` each need their own explicit
  confirmation; the `--include-dirty` confirmation must name the dirty repos whose
  uncommitted changes will be discarded.
- **Autonomous sessions** (`CLAUDE_CODE_REMOTE`, `/loop`, `/schedule`): the batch
  `--apply` aborts, same as the single-repo `tree` — user re-invokes interactively.
- The wrapper runs each child reset as a subprocess, so the session destructive
  guard sees only `bash git-tree-reset-batch.sh`, not an inline `reset --hard` —
  invoke via the wrapper, never inline git.

## Examples

Dry-run the whole ghq tree, skipping one repo, keeping the batch on feature
branches only:

```bash
ghq list -p | bash ${CLAUDE_PLUGIN_ROOT}/skills/clean/scripts/git-tree-reset-batch.sh \
  --repos-from - --skip melodic-software/standards
```

Apply across an explicit set that is on default branches (fresh-clone reset),
after confirming the dry-run:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/clean/scripts/git-tree-reset-batch.sh --apply \
  --force-default-branch --repo ~/repos/a --repo ~/repos/b
```

Include dirty repos (discards their uncommitted changes — confirm separately):

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/clean/scripts/git-tree-reset-batch.sh --apply \
  --include-dirty --repos-from repos.txt
```
