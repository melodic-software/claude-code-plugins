# Scope: the empty-argument ladder, resolved by script

The plugin's `scripts/scope-code-files.sh` (`../../../scripts/scope-code-files.sh` from this file)
resolves the ladder deterministically and prints the rung it landed on, the base it compared
against, the count, and the paths:

> Paths in this file are written relative to the plugin, not as `${CLAUDE_PLUGIN_ROOT}`. Pointer
> for where the token is substituted:
> [Available string substitutions](https://code.claude.com/docs/en/skills#available-string-substitutions).

```text
rung=<uncommitted|branch|repository> base=<ref|none> files=<n>
<path>
...
```

| Rung | Exists when | Files |
|---|---|---|
| `uncommitted` | the working tree has any change | the changed and untracked code files; a rename lists its new path only |
| `branch` | the tree is clean and HEAD carries commits the base branch lacks | code files changed since the merge-base with the base (the pull request's diff, when one exists) |
| `repository` | the tree is clean on the base branch, or no base resolves while clean | every tracked code file |

The base is `--base <ref>` when given, else `refs/remotes/origin/HEAD`, else the first of
`origin/main`, `origin/master`, `main`, `master` that exists. <!-- portability-ok: documents the script's detection-first order (the remote's own HEAD is read before any name is tried); the names are the last-resort fallback, not an assumed default -->

The ladder advances on **absence** of a rung, never on emptiness: a rung that exists but yields zero
code files is reported with `files=0`, so a docs-only branch reports its files as out of scope
instead of silently escalating to the whole repository. Widening to the `repository` rung is taken
without asking and runs in **safe** mode, whatever the posture, with the rung, its file count and
the explicit-target re-run in the report; `report` keeps its posture there, since it edits nothing.
Outside `report`, a non-interactive run proceeds in safe mode on any widened rung, and `necessary`
and `none` apply to the whole repository only through an explicit target.

Granularity is the `comment_edit_scope` setting. Under `diff`, the default, only comments on the
lines the change adds are triaged on the `uncommitted` and `branch` rungs, so a pass over a pull
request edits that pull request's comments and no one else's. Under `files`, every comment in a
listed file is triaged: a pull request that touches a file is then the moment its existing comments
get read, and the tier-0 proof in [safety.md](safety.md) makes each deletion safe regardless of
which commit introduced the comment. The `repository` rung and an explicit target are whole files
under either value.

On the `repository` rung, order the files with
`../../../scripts/rank-comment-targets.py` before triage. Its ranking is a reading
order and never evidence: a high rank says look here first, not that a comment there is wrong.
Byte-identical files collapse to one row with an `instances` count; triage the canonical copy and
run its declared sync afterwards, never a copy.
