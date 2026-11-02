# GitHub repository-tree adapter

How `/knowledge:map-corpus` reads a GitHub repository for its `repo-tree` discovery rung. The
skill names the operation; this file holds GitHub's commands. The parsing half is the `github`
entry in the skill's `discovery/repo_tree_adapters.py`, selected by `parse_discovery.py --forge
github`.

## Pin the ref

Resolve the branch, tag or SHA the user named to its commit SHA, and record it in the checklist:

```bash
gh api "repos/<owner>/<repo>/commits/<ref>" --jq .sha
```

The [Get a commit](https://docs.github.com/en/rest/commits/commits#get-a-commit) endpoint takes a
commit SHA, branch or tag name as `ref` and returns the commit's `sha` (read 2026-11-02).

## Snapshot the listing

```bash
gh api "repos/<owner>/<repo>/git/trees/<sha>?recursive=1" > discovery/repo-tree.json
```

The snapshot is immutable like every other discovery snapshot. Per
[Get a tree](https://docs.github.com/en/rest/git/trees#get-a-tree) (read 2026-11-02): any value of
`recursive` returns the whole subtree, each `tree` entry carries `path`, `mode`, `type` and `sha`,
and a recursive listing is capped at 100,000 entries and 7 MB. Past the cap the response sets
`truncated` to `true`, and the parser refuses it: a truncated listing is not a complete
denominator. Stop and ask the user to narrow the corpus. A subtree listing is no substitute, since
its paths are relative to that subtree and the parser builds URLs from full repository paths.

The parser keeps entries whose `type` is `blob`. A `tree` entry is a directory and a `commit`
entry is a submodule; neither is a file to classify.

## URLs the adapter builds

- **Repository seed:** `https://github.com/<owner>/<repo>/tree/<sha>`, the link-map seed and its
  `ignore` row.
- **Resource URL:** `https://raw.githubusercontent.com/<owner>/<repo>/<sha>/<path>`, with the path
  percent-encoded. The raw form, because a `blob` URL snapshots the HTML page around the file.
