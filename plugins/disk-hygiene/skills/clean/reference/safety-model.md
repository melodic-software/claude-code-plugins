# Safety model

## Trust boundaries

The target path, optional policy, model-authored plan, filesystem metadata, Git output, and process
handle output are untrusted inputs. The Python boundary parses them without shell interpolation,
canonicalizes every selected path under the snapshot root, and rejects absolute paths, traversal,
overlap, and entries absent from the snapshot.

Candidate patterns are advisory. The model supplies contextual evidence, but the engine alone decides
whether an exact plan is mechanically eligible. Neither layer may weaken the other:

- model judgment excludes work product and defers to owning-system cleanup;
- deterministic checks exclude protected/changed/tracked/linked/mounted/open/unverifiable entries;
- explicit human approval authorizes one tier and exact list;
- the engine binds that preview to a snapshot nonce and plan digest.

## Non-overridable checks

- target containment and no filesystem/OS-managed roots;
- no target root, protected shell-folder root, OS registry/profile hive, VCS metadata or tracked file;
- no symlink, Windows junction/reparse traversal, or nested mount point;
- exact file identity and complete descendant set unchanged since snapshot;
- Git index queried with `git ls-files` whenever a worktree is present;
- live-handle state proven clear; missing authority or tooling blocks;
- no elevation and no handle closing;
- one confidence tier per plan and approval.

The policy overlay can add protections, disable candidate hints, and add consumer hints. It cannot
remove a non-overridable check or baseline protected name.

## Handle semantics and honest scope

On Windows, `CreateFile` with a zero share mode conflicts with existing access and
`FILE_FLAG_BACKUP_SEMANTICS` permits the same probe for directories. Sharing violations are `locked`;
access/privilege failures are `needs-elevation`; other errors are unverified.

On Linux/macOS, `lsof <file>` or `lsof +D <directory>` supplies the process view. `+D` is bounded by
the caller's authority and may be slow; a timeout, diagnostic, absent binary, or unexpected exit is
`handle-state-unverified`. The plugin never substitutes deletion failure because POSIX may unlink an
open file while the process retains the underlying object.

The check and deletion cannot be one atomic cross-platform operation. Apply therefore repeats identity
and handle checks immediately before each removal, walks only snapshot entries bottom-up, and reports
partial outcomes. A backup remains the recovery mechanism.

## Outcome vocabulary

| Outcome | Meaning | Next action |
|---|---|---|
| `locked` | A current handle was observed | Close the owning application yourself, rescan |
| `changed-or-link` | Identity changed or a link appeared | Keep; investigate and rescan |
| `protected` | Hard or consumer protection matched | Keep |
| `needs-elevation` | Access could not be proven without greater privilege | Defer to a human-run elevated workflow |
| `handle-state-unverified` | Handle tool/authority/timeout prevented proof | Keep; install/configure the declared verifier if desired |
| `delete-failed` | Final OS operation failed after preflight | Keep remaining content; inspect the reported error |

## Primary references

Verified 2026-07-15: [Claude skills](https://code.claude.com/docs/en/skills),
[PreToolUse hooks](https://code.claude.com/docs/en/hooks),
[Python `os`](https://docs.python.org/3/library/os.html),
[Python `os.path`](https://docs.python.org/3/library/os.path.html),
[Git `ls-files`](https://git-scm.com/docs/git-ls-files),
[Windows `CreateFile`](https://learn.microsoft.com/en-us/windows/win32/api/fileapi/nf-fileapi-createfilew),
[`lsof`](https://lsof.readthedocs.io/en/stable/), and
[Linux `unlink(2)`](https://man7.org/linux/man-pages/man2/unlink.2.html).
