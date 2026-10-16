# Git-hook decisions

The `decisions[]` kinds that `install.mjs plan` returns, and what the setup agent does with each.
The installer never applies these itself: each needs judgment about a file or a choice the user
owns.

| Kind | What you do |
|---|---|
| `lefthook-config`, `husky-config` | Merge `snippet` into `file`, keeping the user's own jobs, comments and order; create the file when absent. For a TOML or JSON lefthook config, write the same job in that format. |
| `lefthook-install` | Run `lefthook install` so the manager's hooks exist in this clone. |
| `husky-install` | Tell the user to run the project's install (husky sets `core.hooksPath` on `npm install`). |
| `husky-shared-only` | Say husky has no per-clone hooks and offer `scope=shared`. |
| `hooks-path` | Plain shared hooks: run `command` in this clone, and tell the user every clone runs it once. |
| `foreign-hook` | Read the existing hook. If it should keep running, move it to `chainAs` (the dispatcher runs it first) and rerun `copy`; otherwise ask. |
| `exclude` | Append `line` to `file` (the clone's `info/exclude`). |
| `gitattributes` | Add `line` to `.gitattributes`, so the shared copies keep LF endings. |
| `modified` | Show how the copy differs from the plugin's script; overwrite with `copy --force` only on the user's yes. |
| `migrate` | After the shared entry verifies `ok`, remove the listed local copies, their `<event>.d/` markers and any `lefthook-local` job, on the user's yes. |
| `declined` | This clone declined the entry. In an attended run ask whether to install it (an install clears the decline); unattended, leave it. |
| `missing-tool` | Report `install` as the way to get the tool; never install it yourself. |
| `no-ci-rerun` | Tell the user no CI workflow in this repository runs `tool`, so a skipped or human-passed commit is not re-checked anywhere. |
| `hooks-path-owned` | `core.hooksPath` points the local hooks dir at another tool's directory (`dir`), so nothing was written. Offer `scope=shared` through that manager, or ask before changing `core.hooksPath`. |
| `manager-conflict` | Show `evidence` and ask which manager carries the entry; rerun `plan` with `--manager`. |
