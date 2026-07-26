# Format-before-push check

Run this against the paths just staged for **this commit** — never the whole index — before
drafting the commit message, catching locally what CI would otherwise catch after a push. Run only
what is already configured and discoverable in the consuming repo; never install or invent a
formatter. If nothing is discoverable, skip silently — do not block a commit on tooling that does
not exist.

Discovery order:

- `package.json` `scripts.format` / `scripts.lint` (`npm run format`, `npm run lint`)
- `biome.json` / `biome.jsonc` (`biome check --write`, scoped to the changed paths)
- A `Makefile` `format` or `lint` target
- `.editorconfig` paired with an installed `editorconfig-checker`
- Any other formatter/linter config already at the repo root (`.prettierrc`, `rustfmt.toml`,
  `.golangci.yml`, a markdown-lint config, …), run with its matching CLI

## Scope every invocation to this commit's path list

Use the explicit path list from the staging step — the same list a pathspec-limited commit would
use — never a bare/whole-repo invocation. When the index also holds staged work outside this
commit's scope (see [pathspec-commits.md](pathspec-commits.md)), a whole-index run would mutate or
block on paths this commit does not own; the explicit path list is what keeps the check inside this
commit's boundary.

## Expand directory pathspecs before filtering

The path list can itself be a directory pathspec (`-- path/to/dir/`) rather than individual files.
A directory handed straight to a formatter is not "one file" the filter below can evaluate — most
formatters treat a directory argument as a recursive target and walk everything under it, not just
this commit's staged files, and an exists/status check silently no-ops against a directory (it
always "exists" and carries no cached status of its own). Before any filtering, expand every
directory entry into its actual staged files via `git diff --cached --name-only -- <dir>`, then
filter that expanded, file-only list.

## Filter to existing, formatter-supported files before invoking

The staged path list (after directory expansion) can include a path this commit deletes or renames
away from, or a path of a type the tool does not format at all (a binary asset, an extension outside
the tool's supported set). Passing those through can make the tool exit non-zero even though CI
would never have formatted them either — Prettier, for example, errors on a missing path or an
unrecognized extension unless told otherwise. Filter in two ordered stages, not one on-disk check:

1. **Cached-status stage first.** Drop paths whose `git diff --cached --name-status` entry is `D`
   (a staged deletion) or the old side of an `R` rename, using that **cached/staged** status — never
   an on-disk existence check as a proxy for "this path is deleted". `git rm --cached <path>` stages
   a deletion while leaving the file present in the working tree; an existence check alone would
   miss that, and the formatter/re-stage flow would silently turn the intended deletion back into a
   tracked, formatted file.
2. **Worktree-existence stage second**, applied only to what stage 1 did not drop. A path staged as
   `A`/`M`/the new side of an `R` can still have no file on disk (removed from the working tree
   without staging that removal) — still in the index, not a deletion by cached status, but the
   formatter has nothing to read, so drop it here rather than letting the tool fail on a missing
   path.

When the tool supports it, also pass its ignore-unknown mode (Prettier's `--ignore-unknown` / `-u`,
or `--no-error-on-unmatched-pattern` for an unmatched pattern) for paths of an unsupported type,
instead of hand-rolling an extension allowlist. If filtering leaves no paths for a given tool, skip
that tool's invocation silently.

## Package-script and Makefile path-scoping are not automatic

`npm run <script> -- <paths>` only narrows the run when the underlying command is itself written to
accept trailing path arguments. Many `scripts.format` / `scripts.lint` entries hardcode a broad
target already (`"format": "prettier --write ."`, `"lint": "eslint ."`); appending paths after an
already-hardcoded `.` does not replace it, so the script still sweeps the whole repo despite the
paths you passed.

`make format` / `make lint` has the same gap for a different reason: Make has no trailing-path-
argument convention — appended words after the target name are parsed as *additional targets*, not
arguments to the `format` recipe — so a conventional `format: prettier --write .` target still
sweeps the whole repo regardless of what you append.

Before relying on either, read the actual command the script or recipe runs: pass paths through only
when that command has no hardcoded target of its own (or is documented to accept path args).
Otherwise skip the package script / Make target and invoke the underlying CLI directly with the
explicit path list, using the repo's **already-installed** binary — never `npx <tool>` or
`npm exec <tool>`, which can silently fetch an unpinned latest version from the registry when the
package is not already installed, violating the "never install or invent a formatter" rule above.
Prefer the project-local no-install path (`node_modules/.bin/prettier --write <path>...`,
`node_modules/.bin/eslint <path>...`, or the ecosystem equivalent), or a version pinned by the
repo's own lockfile/manifest. If no locally-installed binary is discoverable, skip this step
silently rather than reaching for an unpinned fetch.

## Preserve partial staged selections when re-staging

Before running the formatter, snapshot which paths already have a partial-staging split —
`git diff --stat -- <path>` non-empty (unstaged changes exist) at the same time
`git diff --cached --stat -- <path>` is also non-empty (staged changes exist) — captured from the
state **before** the formatter runs, not after.

A path with no pre-formatter unstaged diff is safe to blanket `git add <path>` once the formatter
finishes, even though that now produces a worktree diff: the only worktree change is the formatter's
own edit, so re-staging it is the intended "stage file, run formatter, re-stage its fix" flow.

A path that already had a pre-formatter split means the user deliberately left some hunks unstaged;
running a formatter over that file mixes its edits into the same worktree copy the user only
partially wants staged — stop and surface it instead of silently re-staging the whole file.
