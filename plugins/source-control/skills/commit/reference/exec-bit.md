# Exec-bit check: rationale and manual fallback

The mechanic lives in `<skill-dir>/scripts/exec-bit-check.sh`. Run it; this file explains why it
does what it does, and what to do when it cannot run.

## Why a script rather than prose

The rule is simple and the failure silent: a long session stops executing a paragraph it read fifty
turns ago, and nothing looks wrong until the consuming repo's CI rejects a `100644` shebang file.
Prose decays first, so the procedure is a command, and this file holds only the reasoning.

## What it checks

Every path this change stages at a **new** index entry whose staged blob begins with `#!` while its
staged mode is `100644`.

- **Newly-added only.** An already-tracked executable file needs no action, and a full-repo sweep
  is a different job with a different blast radius.
- **New means new *entry*, not the letter `A`.** The same staged file reports as `A <path>` with
  rename/copy detection off and as `R<score> <old> <new>` or `C<score> <src> <dst>` with it on.
  Rename detection is on by default (`diff.renames`) and copy detection turns on with
  `diff.renames=copies`, so keying on `A` alone would fail open on the consumer's diff
  configuration. **A rename and a copy are not symmetric here**, so they are judged differently:
  - A **rename** destination is the same tracked file at a new path, so it is a candidate **only
    when its source was `100755`**: that makes it a *dropped* bit rather than a tracked file's own
    deliberate `100644` moving along. A `core.filemode=false` platform drops the bit on `mv` plus
    `git add`; a sourced library or template with a shebang and no exec bit is not a defect and is
    never touched.

    **The rename arm is the one place the check's answer still depends on `diff.renames`,** and it
    splits on the *default* setting: `git mv` of a `100644` shebang file reads as `D`+`A` under
    `diff.renames=false` and **is** reported through the `A` branch, while the same index and HEAD
    read as `R100` under the default `diff.renames=true` and are **not**. The gate stays because
    dropping it would flip a deliberately non-executable sourced library to `100755` whenever it
    moves, and making the `A` branch match would report *less*, risking silence on genuinely new
    files. So
    **content-determinism is a property of the `A` and `C` classes, not of the whole tool**; do not
    restate it unqualified.
  - A **copy** destination is a path that did **not** previously exist, so it is newly added
    whatever the source's mode, and a candidate unconditionally, exactly as an `A` is. Gating it on
    the source mode would make the answer depend on `diff.renames`: the same staged content would
    be reported as `A` with copy detection off and missed as `C` with it on.

  The `100644`-plus-shebang filter then does the rest on either arm, so a destination that carried
  its source's `100755` through is dropped too. The rename arm is why the scan reads
  `git diff --cached --raw` rather than `--name-status`: only the raw record carries the source
  mode. A pathspec matching only the source side breaks the pairing back into `D`/`M`, so a scoped
  run never reaches a destination the caller did not name.
- **Symlinks skipped first.** A symlink stages as mode `120000`. Git tracks the link's own mode,
  not its target's, so exec-bit semantics do not apply; `git update-index --chmod=+x` fails on a
  `120000` entry, and following the link to `chmod` its target could reach a file outside the
  repository. So the staged mode is checked **before** anything probes for a shebang.
- **The shebang is read from the staged blob**, not the worktree file: the index is what a plain
  commit records, and `git cat-file blob <sha>` sidesteps every quoting hazard of a worktree path.

## Why both the worktree bit and the index entry

`git update-index --chmod=+x` overrides the **index entry only**, leaving the worktree file's mode
untouched. A worktree/index mismatch causes three failures:

1. `git status` reports a mode-only diff immediately after the commit;
2. a later `git add <path>` re-reads the still-`0644` worktree mode and reverts the index to
   `100644`;
3. the pathspec-limited commit form (`git commit -- <path>`, `--only` mode) records the **worktree**
   mode rather than the index, so an index-only fix still ships a non-executable blob.

So the worktree bit is set first, then the index: the order that survives a later `git add`.

**And the index write is never optional.** Under `core.filemode=false`, the Windows/NTFS default, git
ignores worktree permission bits and stages everything `100644`, so `chmod +x` alone **never**
reaches the index and `git update-index --chmod=+x` is the only way to a `100755` entry.
`exec-bit-check.test.sh` pins the behavior with `core.filemode` set explicitly, so the case tests
the same thing on every platform.

## `--fix` refuses an unscoped run

`--fix` mutates index entries, so it requires an explicit scope: `-- <path>...` (this commit's
paths) or `--all` as a deliberate whole-index opt-in. Without one it exits 2 and changes nothing.

The reason is surgical staging. The staged set can hold another concurrent session's work (the
premise of the pathspec-limited commit form), and silently rewriting its mode entries and
`chmod`-ing its worktree files is the blanket mutation `git add -A` is banned for.

`--list` and `--probe` stay unscoped by default: they only read, so a whole-index view is useful
and harmless.

## Repository-root anchoring

Every mode anchors at the repository root first. `git diff --cached --name-status` emits paths
relative to the **repository root**, but a `git ls-files` pathspec resolves against the
**current directory**. From a subdirectory every lookup misses and the check reports no offenders even when
they exist: a fail-open backstop, worse than none.

Caller pathspecs are relative to the caller's cwd, so they are re-anchored via
`git rev-parse --show-prefix` **before** the directory change; otherwise a scoped `--fix` run from a
subdirectory would silently match nothing. Absolute paths and `:`-prefixed magic pathspecs are
already unambiguous and left alone.

The skill's config-layer probes anchor the same way, for the same reason: from a subdirectory they
would report both repo-scoped config layers absent and silently drop the team convention and
`trailer_policy`.

## Symlinks: two different cases

- **Staged as a symlink** (mode `120000`): skipped before the shebang probe, as described above.
- **Staged as a regular file but replaced in the worktree by a symlink**: *refused*, not skipped.
  `-e` follows a symlink, so an unguarded `chmod +x` would make the link's **target** executable,
  a file that can sit outside the repository. So the `-L` test runs **before** `-e`, and the path
  is reported as a failure rather than silently handled.

## Path output modes

`--list` is newline-delimited. A git pathname may contain a newline, breaking the
one-record-per-line contract, so such a path is shell-quoted (`%q`) to keep the ambiguity visible.
`--probe` does the same, since it is injected into skill context as a single line. Use
**`--list0`** (NUL-delimited) for full unambiguity, since NUL is the one byte a git pathname cannot
contain. Pair it with `read -r -d ''`.

## Ordering within the commit flow

Run the exec-bit check **after** the format-before-push check, never before. The format check
re-stages its fixes with `git add`, and (on a `core.filemode=true` repository) that re-add re-reads
the worktree mode, silently undoing an earlier exec-bit fix. Running the exec-bit check last makes
it the final mutation for the affected paths.

## Manual fallback

If the script is unavailable (an unusual install layout, or the skill's guidance followed without
the plugin), the equivalent inline form is:

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
