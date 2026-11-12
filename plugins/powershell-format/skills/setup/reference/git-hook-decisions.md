<!-- GENERATED from lib/git-hooks/git-hook-decisions.md by scripts/sync-shared-copies.sh. Do not edit this copy:
edit the canonical source, then rerun the script. -->

# Git-hook decisions

The `decisions[]` kinds that `install.mjs plan` returns, and what the setup agent does with each.
The installer never applies these itself: each needs judgment about a file or a choice the user
owns.

| Kind | What you do |
|---|---|
| `lefthook-config`, `husky-config` | Merge `snippet` into `file`, keeping the user's own jobs, comments and order; create the file when absent. For a TOML or JSON lefthook config, write the same job in that format. |
| `lefthook-install` | Run `lefthook install` so the manager's hooks exist in this clone. |
| `husky-install` | Tell the user to run the project's install so husky's hooks exist in this clone. |
| `husky-shared-only` | Say husky has no per-clone hooks and offer `scope=shared`. |
| `shared-entries` | Comes before `hooks-path`: `files` are repository paths under `.githooks/` that `hooks-path` may also run, though this plugin did not install them (other markers, this plugin's own marker with the script it names when that script is not the copy `copy` writes, `*.pre-checks` hooks, other hook files, tracked `.githooks/local/` files). Show the user the list and what each marker or hook runs, and run `hooks-path` only on their yes. |
| `hooks-path` | Plain shared hooks: run `command` in this clone, and tell the user every clone runs it once. |
| `foreign-hook` | Read the existing hook. If it should keep running, move it to `chainAs` (the dispatcher runs it first) and rerun `copy`; otherwise ask. |
| `exclude` | Append `line` to `file` (the clone's `info/exclude`). |
| `gitattributes` | Add `line` to `.gitattributes`, so the shared copies keep LF endings. |
| `modified` | `file` is a locally edited copy, or a hook at the dispatcher's path that carries its sentinel line but is not the dispatcher. Show how it differs from the plugin's version; overwrite with `copy --force` only on the user's yes. |
| `unsafe-path` | `file` is a symlink on the way to a file `copy` writes, so a write could land outside the repository; `copy` reports `unsafe-path` and writes nothing for that entry. Show the user where the link points and ask them to remove it; never write through it. |
| `migrate` | After the shared entry verifies `ok`, remove the listed local copies, their `<event>.d/` markers and any `lefthook-local` job, on the user's yes. |
| `superseded` | `entry` was installed under an earlier name of this plugin, `from`. Show the user the list and, on their yes, retire it: delete `dirs` (`git rm -r` for tracked `.githooks/` content, so teammates get the removal), `markers`, and any hook-manager line that runs one of `scripts`; remove each of `jobs` (`name` from `file`); unset each `config` key at its `scope` (`git config --<scope> --unset-all <key>`, or with a `value`, `git config --<scope> --fixed-value --unset <key> <value>`). For each of `declines` with `carry` true, first run `install.mjs decline --entry <entry>`, adding `--opt-in` when `value` is false (an opt-in over a wider decline, which keeps the hook running) and `--global` when `scope` is `global`; then unset every listed decline key at its `scope`. Rerun `plan` until no `superseded` decision remains. |
| `declined` | This clone declined the entry. In an attended run ask whether to install it (an install clears the decline); unattended, leave it. |
| `missing-tool` | Report `install` as the way to get the tool; never install it yourself. |
| `no-ci-rerun` | Tell the user no CI workflow in this repository runs `tool`, so a skipped or human-passed commit is not re-checked anywhere. |
| `hooks-path-owned` | `core.hooksPath` points the local hooks dir at another tool's directory (`dir`), so nothing was written. Offer `scope=shared` through that manager, or ask before changing `core.hooksPath`. |
| `manager-conflict` | Show `evidence` and ask which manager carries the entry; rerun `plan` with `--manager`. |
