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
- no symlink, Windows reparse traversal, target mount, nested mount, or Linux bind mount;
- exact file identity and complete descendant set unchanged since snapshot;
- repository markers re-discovered from live filesystem state and the Git index queried with
  `git ls-files` at preview and apply; snapshot VCS/protection annotations are never trusted;
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

Execution is intentionally not cross-platform. Linux requires readable `/proc/self/mountinfo`,
`O_NOFOLLOW`, and descriptor-relative stat/unlink/rmdir. Apply anchors the target and every parent to
directory descriptors, verifies those descriptor identities, repeats live mount/protection/Git/handle
checks immediately before each operation, and walks only snapshot entries bottom-up. Once captured
children have been removed, apply opens the directory itself with `O_NOFOLLOW`, verifies its stable
device/inode/type identity, proves it empty through that descriptor, rechecks the name-to-descriptor
identity, and only then calls descriptor-relative `rmdir`. Windows and macOS return
`execution-platform-unsupported`; their audit and report behavior is unchanged.

The skill-scoped Bash guard accepts only complete literal words in the three declared engine command
shapes. It rejects every Bash expansion family, glob/word-splitting input, redirection, operator,
escape, and compound-command form before validating arguments. Canonical script-path comparison uses
the host platform's path case rules; POSIX path identity is never case-folded.

Managed state is engine-ineligible. Even current native dry-run evidence is recorded only as a
report-only handoff because this engine cannot independently authenticate the owning product's state
or cleanup contract.

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

Verified 2026-07-16: [Claude skills](https://code.claude.com/docs/en/skills),
[PreToolUse hooks](https://code.claude.com/docs/en/hooks),
[GNU Bash shell expansions](https://www.gnu.org/software/bash/manual/html_node/Shell-Expansions.html),
[Python 3.11 `os`](https://docs.python.org/3.11/library/os.html),
[Python 3.11 `os.path`](https://docs.python.org/3.11/library/os.path.html),
[Git `ls-files`](https://git-scm.com/docs/git-ls-files),
[Windows `CreateFile`](https://learn.microsoft.com/en-us/windows/win32/api/fileapi/nf-fileapi-createfilew),
[Windows reparse points](https://learn.microsoft.com/en-us/windows/win32/fileio/reparse-point-operations),
[`GetLogicalDrives`](https://learn.microsoft.com/en-us/windows/win32/api/fileapi/nf-fileapi-getlogicaldrives),
[Linux `mountinfo`](https://man7.org/linux/man-pages/man5/proc_pid_mountinfo.5.html),
[`lsof`](https://lsof.readthedocs.io/en/stable/), and
[Linux `unlink(2)`](https://man7.org/linux/man-pages/man2/unlink.2.html).
