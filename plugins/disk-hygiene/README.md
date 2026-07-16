# disk-hygiene

`/disk-hygiene:clean` audits an arbitrary directory tree for abandoned temporary files, stale locks,
failed atomic-write remnants, empty leftovers, and similar disk residue. It is a context-aware audit,
not a static delete list: bundled patterns are discovery hints only, and every finding needs evidence
that it is not work product.

The default lane is read-only. Cleanup is available only through a fresh, exact-path preview followed
by explicit approval of one confidence tier. The engine then rechecks every candidate before removing
only the entries captured in the snapshot; it never follows links or recursively deletes an
unvalidated tree.

## Safety contract

- The side-effecting skill is manual-only (`disable-model-invocation: true`). Automated, scheduled,
  remote, or otherwise unattended sessions audit and stop.
- Confidence controls report ordering, never authorization. High, medium, and low each require a
  separate approval naming every path and its logical byte count.
- Filesystem roots, OS-managed roots, user shell-folder roots, VCS metadata/tracked content, mount
  points, symlinks/junctions, entries changed since the scan, and paths outside the target are hard
  stops. These predicates cannot be disabled by policy.
- A live-handle preflight runs immediately before deletion. Windows uses an exclusive `CreateFile`
  probe for every entry. Linux/macOS require `lsof`; absence, incomplete authority, or diagnostics
  produce `handle_state_unverified` and block the tier. The plugin never elevates itself.
- A managed directory is handed to its owning product's documented cleanup/GC command. A manual
  candidate for managed state is invalid without recorded evidence from that command.
- The skill-scoped guard denies shell deletion bypasses and returns a final `ask` decision for the
  exact engine apply command, so even a pre-approved Bash rule cannot silently skip the mutation prompt.
- Deletion walks the validated snapshot bottom-up. New entries are not traversed; they make the
  directory non-empty and therefore skipped. The report separates removed, locked, changed,
  protected, needs-elevation, and unverified outcomes and records logical bytes plus observed free-space
  delta.

No guard can eliminate filesystem time-of-check/time-of-use races. This implementation narrows the
window by revalidating identity and handles immediately before each operation and fails closed on any
uncertainty. Backups remain the recovery boundary for user data.

## Requirements and platform support

- Python 3.11+ available as `python` is required for scanning, validation, the skill-scoped guard, and
  cleanup. The plugin never downloads a runtime.
- Git is optional for ordinary trees. If a target contains or sits inside a Git worktree, Git becomes
  required so tracked content can be proven safe; otherwise cleanup for that subtree is blocked.
- Windows uses only Python's standard library and Win32 APIs exposed by the OS. It never invokes UAC.
- Linux and macOS require `lsof` for the optional execution lane. Without it, audits and previews work,
  but cleanup fails closed. `lsof` warnings or authority gaps also block cleanup.

## Usage

```text
/disk-hygiene:clean <target-directory>
/disk-hygiene:clean --policy <policy.json> <target-directory>
```

The skill stores snapshots, plans, and reports under `${CLAUDE_PLUGIN_DATA}`. It never writes generated
state into the installed plugin directory or the audited target.

The optional policy file has this shape:

```json
{
  "version": 1,
  "disabled_hint_ids": ["common-lock-file"],
  "additional_hints": [
    {
      "id": "my-tool-staging",
      "os": ["all"],
      "kind": "name_glob",
      "pattern": "temp_git_*",
      "confidence_ceiling": "medium",
      "reason": "My tool's documented clone-staging convention"
    }
  ],
  "additional_protected_path_globs": ["client-deliverables/**"]
}
```

Candidate hints can be disabled or extended. Consumer protection globs are additive. Hard safety
predicates and the baseline protected-name/root rules are non-overridable.

## Relationship to other tools

- Use `/repo-hygiene:clean` for deterministic caches, build outputs, Git metadata, or a fresh-pull reset
  inside one repository. `disk-hygiene` does not duplicate those mechanisms.
- Use a product's own prune/GC/uninstall command for state it owns. This skill reports the handoff and
  records the native result; it does not infer eligibility from version-like names or age alone.
- `git clean` remains the authority for ignored/untracked repository files. This plugin protects every
  tracked path and does not emulate Git's path rules.

## Plugin-acceptance security review

- **Code execution:** the plugin runs bundled, standard-library Python. The skill-scoped PreToolUse
  guard blocks direct shell deletion during the workflow and forces a final permission prompt for the
  exact engine command. No `eval`, dynamic shell construction, or
  downloads are used. Paths cross the process boundary as JSON or individually quoted CLI arguments.
- **MCP / external trust:** no MCP server, agent, dependency, or third-party service is shipped.
- **Configuration:** no `userConfig` and no credentials. Optional policy is an explicit invocation
  argument and contains patterns only.
- **Isolation:** bundled assets resolve from `${CLAUDE_PLUGIN_ROOT}`; generated state belongs under
  `${CLAUDE_PLUGIN_DATA}`. The audited target is read, then mutated only through the gated lane.
- **Egress:** none. `git` and `lsof` are local read-only subprocesses.
- **Provenance:** Melodic Software, MIT. No vendored code.

Security review result: **accept** for the declared local code-execution surface. Any later network,
credential, dependency, or MCP surface reopens this review.

## Sources

Verified 2026-07-15 against current primary documentation:

- [Create plugins](https://code.claude.com/docs/en/plugins) and
  [plugins reference](https://code.claude.com/docs/en/plugins-reference) — plugin structure, cache
  isolation, manifests, versions, and local `--plugin-dir` testing.
- [Skills](https://code.claude.com/docs/en/skills) — side-effecting skills should be manual-only;
  supporting files, arguments, and skill-scoped hooks.
- [Hooks](https://code.claude.com/docs/en/hooks) — current `PreToolUse` decision output.
- [Create a marketplace](https://code.claude.com/docs/en/plugin-marketplaces) — relative plugin sources.
- [Python filesystem APIs](https://docs.python.org/3/library/os.html) and
  [path APIs](https://docs.python.org/3/library/os.path.html) — non-following metadata, junction, and
  mount detection.
- [Git `ls-files`](https://git-scm.com/docs/git-ls-files) — the index/tracked-file authority.
- [Windows `CreateFile`](https://learn.microsoft.com/en-us/windows/win32/api/fileapi/nf-fileapi-createfilew)
  — sharing conflicts and directory handles via `FILE_FLAG_BACKUP_SEMANTICS`.
- [`lsof` maintained documentation](https://lsof.readthedocs.io/en/stable/) — open-file lookup and
  Linux/macOS support; the recursive `+D` authority limitation is why diagnostics fail closed.
- [POSIX `unlink`](https://pubs.opengroup.org/onlinepubs/9799919799/functions/unlink.html) and
  [Linux `unlink(2)`](https://man7.org/linux/man-pages/man2/unlink.2.html) — open-file unlink semantics
  motivate an explicit preflight rather than relying on deletion failure.

## License

MIT (SPDX-License-Identifier: MIT). See the repository root `LICENSE`.
