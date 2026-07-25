# Safety model

## Trust boundaries

The target path, optional policy, model-authored plan, filesystem metadata, Git output, and process
handle output are untrusted inputs. The Python boundary parses them without shell interpolation,
canonicalizes every selected path under the snapshot root, and rejects absolute paths, traversal,
overlap, and entries absent from the snapshot.

Standing-policy `additional_hints[].reason` prose is likewise untrusted: the additive-only design
means a hint can never authorize anything, but its reason text reaches the model's triage reasoning
unlabeled — treat it as an unverified claim requiring independent evidence, never as a finding.

Candidate patterns are advisory. The model supplies contextual evidence, but the engine alone decides
whether an exact plan is mechanically eligible. Neither layer may weaken the other:

- model judgment excludes work product and defers to owning-system cleanup;
- deterministic checks exclude protected/changed/tracked/linked/mounted/open/unverifiable entries;
- explicit human approval authorizes one tier and exact list;
- the engine binds that preview to a snapshot nonce and plan digest.

## Non-overridable checks

- target containment; an OS-managed root (per `system_roots()` — the OS drive holding an existing
  Windows install / `Program Files` / `ProgramData`, or `/` holding `/bin`, `/etc`, …) is denied,
  while a non-OS volume root (a Windows Dev Drive: a drive root carrying only the per-volume metadata
  every volume has and no OS-install marker) is a valid target rather than blanket-denied — but as a
  known-large root it is routed through the large-target scan gate below (bound or confirm), and
  deletion stays gated by the preview and per-tier approval;
- the audit root itself is never a removal candidate; no protected shell-folder root, OS
  registry/profile hive, VCS metadata or tracked file;
- no symlink, Windows reparse traversal, non-root mount target, nested mount, or Linux bind mount
  (a volume root is itself a mount point and is governed by the OS-managed/confirmation reasoning
  above, not this structural mount veto);
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

That decline was re-examined and AFFIRMED by the maintainer on 2026-07-23 (issue #1116), against
the framing "new-trust-surface risk of a Windows deletion lane vs the residual approval-to-execution
window the decline leaves in the manual lane": with the manual lane's per-item revalidation rules
and the `handoff-verify` revalidation (#1109, landed), the residual window is small, while a
descriptor-anchored Windows apply is a large new surface. Recorded reversal trigger: a post-#1109
near-miss recurrence in the manual lane reopens this as a design issue with full security review.

## Manual-handoff revalidation (`handoff-verify`)

`handoff-verify` brings snapshot binding to the platforms where apply is unsupported, without
adding an engine deletion lane. It takes the snapshot plus the human-approved exact path list
(same containment rules as plan candidates: relative, non-root, no traversal, present in the
snapshot, non-overlapping), re-validates the target root with preview's link/mount/OS-managed/
protected-path checks but a deliberately tolerant root-identity check — stable device/inode/type
(the same object identity apply uses for directories) instead of preview's full stat identity,
because deleting one approved root-level item changes the root's own mtime and the manual lane
re-verifies between items; a replaced root still refuses. It then reruns the per-path
identity/reparse/protection/descendant/VCS/handle checks against live state and emits one
machine-readable verdict per path. It deliberately does not apply platform execution blockers —
it exists exactly where `execution-platform-unsupported` blocks the engine lane — and it has no
deletion capability of any kind: the model deletes only verdict-`clear` paths in the manual lane,
per item, under the final human permission prompt the PowerShell guard raises.

| Verdict | Meaning | Manual-lane action |
|---|---|---|
| `clear` | Every check passed against live state at emission time | Delete this exact path immediately — verify one path per deletion, never one batch for all (earlier checks age while later paths are probed) |
| `gone` | The path no longer exists | Nothing to delete; report it |
| `drifted` | Identity, kind, or the captured descendant set changed since the snapshot | Keep; the approval no longer describes what is on disk — rescan |
| `contested` | Protection, VCS state, a live handle, elevation, or unverifiable state | Keep; the reasons list names each contest — resolve and re-verify |

Fail-closed mapping: every unverifiable condition (handle tool missing or timing out, unreadable
state, truncated coverage) lands in `contested`, never `clear`. A `clear` verdict authorizes
nothing by itself — it reports that revalidation found no change and no contest at that instant;
the human approval and the per-item prompt remain the authorization. Verdicts expire immediately:
any delay or interruption means re-running handoff-verify. Managed-state exclusion stays where it
always was in the manual lane — model judgment plus human review of the audit report — because
snapshot entries carry no owner claim for the engine to check.

The skill-scoped Bash guard accepts only complete literal words in the four declared engine command
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

Because this lane enumerates spellings instead of denying unknown commands, its coverage is
knowingly partial: the flagged set is deletion- and recycle-shaped (plus `robocopy` mirror/purge/move
and .NET `Delete`), so destructive **non-deletion** spellings — `Move-Item`/`mv`, `Rename-Item`,
overwriting writers (`Set-Content`, `Out-File`, `>`, `New-Item -Force`), and volume operations
(`Format-Volume`, `Clear-Disk`) — reach the tool with no guard verdict at all, in audit-only mode
included. Data loss through those spellings is held only by the per-path human approval the manual
handoff already requires and the consumer's own permission policy, never by this guard.
TODO(#387): extend the flagged set to those spellings.

**Kill-switch enforcement (since 0.9.0): both surfaces resolve it by reading user settings.** The guard
registers on two surfaces — the **plugin-level engine gate** (`hooks/hooks.json`, exec form,
`--mode engine-gate`) and the **skill-scoped belt** (the clean skill's frontmatter hook) — and both
resolve `disk_hygiene_enabled` the same single way: by reading it from `pluginConfigs` in the
`settings.json` files, through the shared `lib/killswitch_config.py` reader (the same read the setup
skill's `kill_switch_probe.py` reports). Neither surface takes the value from the process environment.
Claude Code honors that key only from user, managed, and `--settings` scope since 2.1.207 — a project or
local `.claude/settings.json` is ignored — so a hostile repo cannot flip it. The **user** file is located
from `${CLAUDE_PLUGIN_ROOT}` (the plugin's true install path, which a repo cannot forge) and **never**
from `CLAUDE_CONFIG_DIR`/`HOME`, which a repo `settings.json` `env` block could inject. A marker-less
install root (a `--plugin-dir` checkout, whose path has no `plugins/cache` segment) yields no trusted
user-settings path, so the user scope is skipped there and the switch relies on managed settings, failing
closed to enabled otherwise. The **managed**
(enterprise) file at its fixed root-owned system path is read too and, as the highest-precedence
non-overridable scope, an explicitly configured value there **wins over the user file** — so an
organization can enforce audit-only mode; the sibling `managed-settings.d/` drop-in directory is merged
over it (later files win). The one honored source the guard cannot read is a session's `--settings` file
(a runtime CLI flag no hook observes); a value supplied only there is not enforced. When the value
resolves `false` (audit-only mode), `false` is guard-enforced — denied outright, not merely prompted — but
the two surfaces reach different lanes. The **always-on engine gate** enforces it against every Bash
engine invocation **whether or not the clean skill is active**; it defers (no output) on any command that
does not reference the engine, so it does **not** see PowerShell deletion spellings. Those are enforced by
the **skill-scoped belt** (`powershell_decision`) — denied outright in audit-only — only **while the clean
skill is active**. An absent, unreadable, or ambiguous read fails **closed to enabled**: the guard stays
active and forces a human prompt before every mutation, so an unreadable toggle never silently disables
the guard.

This replaces the earlier delivery, where the gate carried a bare `${user_config.disk_hygiene_enabled}`
argument. Because the declared userConfig `default` is not implemented upstream
(#46477 / #39455 / #39827), an unset-but-defaulted token was neither substituted nor exported as `CLAUDE_PLUGIN_OPTION_*` and
its presence **dropped the whole engine-gate hook** — so on a default install the gate never ran at all,
the real shape of the "PowerShell bypass" originally reported. Reading settings directly needs no
`default` substitution, so that inert-by-default failure is gone. **Recheck** the tamper and scoping
premises if 2.1.207's user-scope-only `pluginConfigs` behavior changes upstream.

PreToolUse hooks with a `Bash|PowerShell` matcher fire for the PowerShell tool on 2.1.218 (payload
`tool_name` is literally `PowerShell`, confirmed by a live block through that tool); there is no harness
firing divergence. The gate defers instantly (no output) for any command that does not reference the
engine, so it never taxes unrelated work; its coverage marker is the engine script name, a belt against
casual invocation, not an authority (renaming the script evades the gate but not the engine's own
preview/approval-token containment). The model additionally reads the `disk_hygiene_enabled` value from
the skill content and self-enforces audit-only — now defense-in-depth over the guard, not the only path.
Even when the switch resolves enabled, the PowerShell lane is a raised bar, not fail-closed: an unknown
mutation spelling passes it, so the engine's own containment, revalidation, and platform gates remain the
deletion authority.

A depth-limited scan records every directory it declined to enter in `truncated_paths`. Truncated
directories have no captured descendant set, so the preview blocks them (and anything beneath them)
as `truncated-not-inventoried`; they are coverage gaps, never candidates.

A scan of a known-large root — the user home directory, or a non-OS volume root (a Windows Dev
Drive) now that reasoned classification admits it as a valid target — is gated before it walks.
Absent an explicit `--max-depth` bound or a `--confirmed-large-scan` acknowledgement, the engine
performs a cheap top-level probe and returns `large-target-confirmation-required` instead of the
unbounded traversal, so an unauthenticated whole-volume walk cannot begin by omission. This is
scan-cost gating (time and resources), distinct from the hard rejection of an OS-managed root as an
invalid target.

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
