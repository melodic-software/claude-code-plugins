# Git-hook decisions

The `decisions[]` kinds that `install.mjs plan` returns for the guardrails entries, and what the
setup agent does with each. The installer never applies these itself: each needs judgment about
a file or a choice the user owns.

| Kind | What you do |
|---|---|
| `lefthook-config`, `husky-config` | Merge `snippet` into `file` (a remote plan's snippet is one `remotes:` entry: add it to an existing `remotes:` list), keeping the user's own jobs, comments and order; create the file when absent. For a TOML or JSON lefthook config, write the same job in that format. The `reference-verify` job is `pre-push` and its snippet sets `use_stdin: true`: keep it. When another `pre-push` job there also sets it, tell the user lefthook gives the pushed refs to only one job, so `reference-verify` may check the branch against its upstream instead, and nothing on a branch with no upstream. |
| `lefthook-install` | Run `lefthook install` so the manager's hooks exist in this clone; for a remote plan it also fetches the remote, so rerun it when it reported that it could not sync. |
| `remote-source-dir` | The lefthook config sets `source_dir` (`sourceDir`), and lefthook looks up a remote's scripts under that directory in the fetched copy, which holds them only under `.lefthook/`, so every commit would fail with "script does not exist". Tell the user and run `plan --scope shared` instead, unless they move their scripts to the default `.lefthook/`. |
| `remote-needs-lefthook` | The repository uses husky or plain hooks, which have no remotes: run `plan --scope shared` instead. |
| `husky-install` | Tell the user to run the project's install (husky sets `core.hooksPath` on `npm install`). |
| `husky-shared-only` | Say husky has no per-clone hooks and offer `scope=shared`. |
| `hooks-path` | Plain shared hooks: run `command` (`git config core.hooksPath .githooks`) in this clone, and tell the user every clone runs it once. `block-no-verify` allows that exact value only at local scope (not `--global`, `--system`, `--worktree` or `--file`) and only while `.githooks/` holds the dispatcher setup wrote, and refuses any other. |
| `foreign-hook` | Read the existing hook. If it should keep running, move it to `chainAs` (the dispatcher runs it first, and its rejection stands) and rerun `copy`; otherwise ask. A hook the earlier `install-commit-msg` or `install-pre-commit-content` actions wrote (its second line names `guardrails-commit-msg-convention` or `guardrails-pre-commit-content-invariants`) is replaced, not chained: remove it, its `guardrails-resolve-convention.sh` or `guardrails-content-lib/` beside it, and restore a `<event>.pre-guardrails` hook to `<event>` first. `check` reports these files as the retirement records `guardrails-r001` to `guardrails-r004`. |
| `exclude` | Append `line` to `file` (the clone's `info/exclude`). |
| `gitattributes` | Add `line` to `.gitattributes`, so the shared copies keep LF endings. |
| `modified` | `file` is a locally edited copy, or a hook at the dispatcher's path that carries its sentinel line but is not the dispatcher. Show how it differs from the plugin's version; overwrite with `copy --force` only on the user's yes. |
| `unsafe-path` | `file` is a symlink on the way to a file `copy` writes, so a write could land outside the repository; `copy` reports `unsafe-path` and writes nothing for that entry. Show the user where the link points and ask them to remove it; never write through it. |
| `migrate` | After the shared entries verify `ok`, remove the listed local copies, their `<event>.d/` markers and any `lefthook-local` job, on the user's yes. With `from: shared` (a remote plan), remove `dir` (`.githooks/guardrails/`), the listed `jobs` from the lefthook config, and any exclusion that names `dir` (a lefthook `exclude`, a CI lint skip); a repository with no other `.githooks/` content also drops its `.githooks/**` `.gitattributes` line. These are committed changes, made on the user's yes. |
| `declined` | This clone declined the entry. In an attended run ask whether to install it (an install clears the decline); unattended, leave it. |
| `missing-tool` | Report `install` as the way to get the tool (`jq` for `reference-verify`); never install it yourself. |
| `no-ci-rerun` | Tell the user no CI workflow in this repository runs `tool`, so a skipped or human-passed commit is not re-checked anywhere. |
| `hooks-path-owned` | `core.hooksPath` points the local hooks dir at another tool's directory (`dir`), so nothing was written. Offer `scope=shared` through that manager, or ask before changing `core.hooksPath`. |
| `manager-conflict` | Show `evidence` and ask which manager carries the entries; rerun `plan` with `--manager`. |
