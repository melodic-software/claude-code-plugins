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
the host platform's path case rules; POSIX path identity is never case-folded. A `--data-root` value
is accepted only when it matches the plugin data directory the guard derives from
`${CLAUDE_PLUGIN_ROOT}` — the only substitution a skill-frontmatter hook receives, passed to the
guard as `--plugin-root` and mapped to `<plugins>/data/<id>` per the documented
[persistent-data-directory](https://code.claude.com/docs/en/plugins-reference#persistent-data-directory)
layout. A host that can substitute `${CLAUDE_PLUGIN_DATA}` itself may instead pass it directly as
`--authorized-data-root`, and the `CLAUDE_PLUGIN_DATA` environment variable is honored last; absent
every channel the flag fails closed. `--max-depth` accepts only a bare positive-integer literal.
`--confirmed-large-scan` is the one valueless scan flag; the guard permits at most one and rejects
any trailing value, so the scan grammar stays exact.

Deriving the data root from `${CLAUDE_PLUGIN_ROOT}` couples to the one undocumented part of that
layout — the `cache/<marketplace>/<name>/<version>` shape of the installation root (the install root
is the version leaf; a directly-linked local install omits it). The guard anchors on the
`<plugins>/cache` marker rather than a fixed depth, taking the marketplace and name from the two
segments after `cache` and reading `data` as `cache`'s sibling, so a version leaf does not shift the
result. That coupling is acceptable only because its sole failure mode is fail-closed: an
unrecognized layout yields no authority, so `--data-root` engine calls are denied while the
destructive-action guard stays fully active. The plugins reference documents all three path
variables (`CLAUDE_PLUGIN_ROOT`/`CLAUDE_PLUGIN_DATA`/`CLAUDE_PROJECT_DIR`) as exported to hook
processes as environment variables, so the guard's `CLAUDE_PLUGIN_DATA` env fallback should carry the
authority wherever the runtime honors that for skill hooks — the derivation is then a redundant belt.
An earlier Claude Code build was observed not to export it to a skill hook, which is why both
channels exist.

A `claude --plugin-dir <checkout>` development session is the one shape with no derivable authority: a
bare checkout has no `<plugins>/cache/<marketplace>` structure and no stable marketplace-keyed data
`<id>`, so the marker walk finds nothing. That dev workflow relies solely on the `CLAUDE_PLUGIN_DATA`
environment variable; where a Claude Code build does not export it to a skill hook, the engine lane is
fail-closed there (every `--data-root` invocation denied) while the destructive-action guard itself
stays fully active. This is a deliberate safe-over-convenient tradeoff for a development-only mode,
not a security gap — a local developer sets `CLAUDE_PLUGIN_DATA` or exercises the engine lane through
a real marketplace install.

The same guard also covers the PowerShell tool with the inverse tradeoff: PowerShell stays open for
read-only support work, while engine invocations are hard-denied (Bash is the only engine lane) and
known deletion spellings and .NET Delete calls resolve against the `disk_hygiene_enabled` kill
switch. When the guard sees execution enabled they are downgraded to a final human permission prompt;
when it sees a configured `false` (audit-only mode) they are denied outright, so the kill switch would
block deletions on the PowerShell lane too and not only the Bash engine apply.

That kill-switch enforcement is, however, only as reachable as the value is. The guard reads it from a
`--disk-hygiene-enabled` argv flag or the `CLAUDE_PLUGIN_OPTION_DISK_HYGIENE_ENABLED` environment
variable, but a skill-frontmatter hook receives neither — Claude Code substitutes only
`${CLAUDE_PLUGIN_ROOT}` into a skill hook's args and does not inject `CLAUDE_PLUGIN_OPTION_*` into its
environment. So in the bundled skill deployment the guard defaults to enabled and cannot honor a
configured `false` by denying; it still forces a human prompt before every mutation, and the model
itself reads the substituted `disk_hygiene_enabled` value from the skill content and self-enforces
audit-only. Enforcing the kill switch in the guard needs a delivery channel skill hooks do not yet
have (a plugin-scoped hook or MCP server that can carry the value, or Claude Code adding
`${user_config.*}` substitution for skill hooks). Even when the switch is reachable, the PowerShell
lane is a raised bar, not fail-closed: an unknown mutation spelling passes it, so the engine's own
containment, revalidation, and platform gates remain the deletion authority.

A depth-limited scan records every directory it declined to enter in `truncated_paths`. Truncated
directories have no captured descendant set, so the preview blocks them (and anything beneath them)
as `truncated-not-inventoried`; they are coverage gaps, never candidates.

A scan of a known-large root — the user home directory — is gated before it walks. Absent an explicit
`--max-depth` bound or a `--confirmed-large-scan` acknowledgement, the engine performs a cheap
top-level probe and returns `large-target-confirmation-required` instead of the unbounded traversal,
so an unauthenticated whole-home walk cannot begin by omission. This is scan-cost gating (time and
resources), distinct from the hard rejection of filesystem and OS-managed roots as invalid targets.

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
