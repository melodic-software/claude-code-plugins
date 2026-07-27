# Exec-bit check — rationale and manual fallback

The mechanic lives in `${CLAUDE_PLUGIN_ROOT}/skills/commit/scripts/exec-bit-check.sh`. Run it;
this file explains why it does what it does, and what to do when it cannot run.

## Why a script rather than prose

The rule is simple and the failure is silent, which is the worst combination for prose: a long
session stops executing a paragraph it read fifty turns ago, and nothing about the commit looks
wrong until the consuming repo's CI rejects a `100644` shebang file. Prose is the tier that decays
first — so the ordered procedure is a command, and the prose here is only the reasoning behind it.

## What it checks

Every path staged as a **new** file (`A`) whose staged blob begins with `#!` while its staged mode
is `100644`.

- **Newly-added only.** An already-tracked file that was already executable needs no action, and a
  full-repo sweep is a different job with a different blast radius.
- **Symlinks skipped first.** A symlink stages as mode `120000`. Git tracks the link's own mode,
  not its target's, so exec-bit semantics do not apply; `git update-index --chmod=+x` fails outright
  on a `120000` entry, and following the link to `chmod` its target could reach a file outside the
  repository entirely. The staged mode is therefore checked **before** anything probes for a
  shebang.
- **The shebang is read from the staged blob**, not the worktree file. The index is what a plain
  commit records, and reading `git cat-file blob <sha>` also sidesteps every quoting hazard a
  worktree path carries.

## Why both the worktree bit and the index entry

`git update-index --chmod=+x` overrides the **index entry only**; it leaves the worktree file's
actual mode untouched. A worktree/index mismatch causes three separate failures:

1. `git status` reports a mode-only diff immediately after the commit;
2. a later `git add <path>` re-reads the still-`0644` worktree mode and reverts the index to
   `100644`;
3. the pathspec-limited commit form (`git commit -- <path>`, `--only` mode) records the **worktree**
   mode rather than the index, so an index-only fix still ships a non-executable blob.

So the worktree bit is set first, then the index — that order is the one that survives a later
`git add`.

**And the index write is never optional.** Under `core.filemode=false` — the default on
Windows/NTFS — git ignores worktree permission bits entirely and stages everything `100644`. On
such a repository `chmod +x` alone **never** reaches the index, and `git update-index --chmod=+x`
is the only thing that can produce a `100755` entry. This is exactly the platform where the
advisory prose version of this check was most likely to look like it had worked and not have.
`exec-bit-check.test.sh` pins the behavior with `core.filemode` set explicitly, so the case tests
the same thing on every platform.

## `--fix` refuses an unscoped run

`--fix` mutates index entries, so it requires an explicit scope: either `-- <path>...` (this
commit's paths) or `--all` as a deliberate whole-index opt-in. Without one it exits 2 and changes
nothing.

The reason is this skill's own surgical-staging discipline. The staged set can hold another
concurrent session's work — the whole premise of the pathspec-limited commit form — and silently
rewriting that session's mode entries, plus `chmod`-ing its worktree files, is exactly the blanket
mutation `git add -A` is banned for. A fixer whose default is "everything staged" would invert the
skill's default.

`--list` and `--probe` stay unscoped by default: they only read, so a whole-index view is useful
and harmless. That asymmetry is deliberate, not an oversight.

## Repository-root anchoring

Every mode anchors at the repository root before doing anything. `git diff --cached --name-status`
always emits paths relative to the **repository root**, but a `git ls-files` pathspec resolves
against the **current directory**. Run from a subdirectory those two disagree, every lookup misses,
and the check reports no offenders even when they exist — a fail-open backstop, which is worse than
no backstop at all.

Caller pathspecs are relative to the caller's cwd, so they are re-anchored via
`git rev-parse --show-prefix` **before** the directory change; otherwise a scoped `--fix` run from a
subdirectory would silently match nothing. Absolute paths and `:`-prefixed magic pathspecs are
already unambiguous and are left alone.

The skill's config-layer probes anchor the same way, for the same reason: a session
started in a subdirectory would otherwise report both repo-scoped config layers absent and silently
drop the team convention and `trailer_policy`.

## Symlinks: two different cases

- **Staged as a symlink** (mode `120000`) — skipped before the shebang probe, as described above.
- **Staged as a regular file but replaced in the worktree by a symlink** — *refused*, not skipped.
  This is a worktree/index disagreement, and it is a real escape: `-e` follows a symlink, so an
  unguarded `chmod +x` would make the link's **target** executable — a file that can sit entirely
  outside the repository. The `-L` test therefore runs **before** `-e`, and the path is reported as
  a failure rather than silently handled.

## Path output modes

`--list` is newline-delimited. A git pathname may legally contain a newline, which would break the
one-record-per-line contract, so such a path is shell-quoted (`%q`) to keep the ambiguity visible
rather than silent. `--probe` does the same, since it is injected into skill context as a single
line. Use **`--list0`** (NUL-delimited) when a caller needs full unambiguity — NUL is the one byte a
git pathname cannot contain. Pair it with `read -r -d ''`.

## Ordering within the commit flow

Run the exec-bit check **after** the format-before-push check, never before. The format check
re-stages its own fixes with `git add`, and (on a `core.filemode=true` repository) that re-add
re-reads the worktree mode — silently undoing an exec-bit fix applied earlier. Running the
exec-bit check last makes it the final mutation for the affected paths.

## Manual fallback

If the script is unavailable — an unusual install layout, or a consumer running the skill's
guidance without the plugin — the equivalent inline form is:

```bash
for f in <newly-added paths>; do
  mode=$(git ls-files --stage -- "$f" | cut -d' ' -f1)
  case "$mode" in 100644) ;; *) continue ;; esac  # skip 100755, symlinks (120000), gitlinks
  git cat-file blob "$(git ls-files --stage -- "$f" | cut -d' ' -f2)" | head -c 2 | grep -q '^#!' || continue
  chmod +x -- "$f"
  git update-index --chmod=+x -- "$f"
done
```

Scope it to the files newly added in the current change set, never a full-repo sweep.
