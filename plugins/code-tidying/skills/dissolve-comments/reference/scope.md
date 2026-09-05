# Scope — the empty-argument ladder, resolved by script

`${CLAUDE_PLUGIN_ROOT}/scripts/scope-code-files.sh` resolves the ladder deterministically and prints
the rung it landed on, the base it compared against, the count, and the paths:

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
instead of silently escalating to the whole repository. Widening to the `repository` rung is
confirmed with the user in an interactive session; a non-interactive run proceeds in **safe** mode
on any widened rung.

Granularity is per file: every comment in a listed file is triaged, not only the lines the diff
added. That is deliberate. A pull request that touches a file is the moment its existing comments
get read, and the tier-0 proof in [safety.md](safety.md) makes each deletion safe regardless of
which commit introduced the comment.

On the `repository` rung, order the files with
`${CLAUDE_PLUGIN_ROOT}/scripts/rank-comment-targets.py` before triage. Its ranking is a reading
order and never evidence: a high rank says look here first, not that a comment there is wrong.
Byte-identical files collapse to one row with an `instances` count; triage the canonical copy and
run its declared sync afterwards, never a copy.
