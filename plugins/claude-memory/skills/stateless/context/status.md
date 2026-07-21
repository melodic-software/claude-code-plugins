# Status Workflow (read-only)

Report the effective auto-memory posture for the current repo. Change nothing.

## Step 1: Read the snapshot

The SKILL.md snapshot already ran `scope-report.sh`, which lists each settings scope file
(managed / user / project / local), its existence, the live
`CLAUDE_CODE_DISABLE_AUTO_MEMORY` OS-env value, and the default memory directory with its
`MEMORY.md` line count and topic-file count. If the snapshot is missing, run:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/stateless/scripts/scope-report.sh"
```

## Step 2: Read the setting values from each present scope

The snapshot reports which settings files exist but not their key values. For each scope
listed `PRESENT`, Read the file and extract:

- `autoMemoryEnabled` (boolean, if set)
- `autoMemoryDirectory` (string, if set)
- `env.CLAUDE_CODE_DISABLE_AUTO_MEMORY` (if set in the `env` block)

Absent keys inherit the default: `autoMemoryEnabled` defaults to `true` (auto memory is on).
On Windows, managed policy may be in the registry rather than a file — note it as unread if
you cannot inspect it, don't assume it is empty.

## Step 3: Resolve the effective state

- **Enabled state.** `CLAUDE_CODE_DISABLE_AUTO_MEMORY` overrides `autoMemoryEnabled` (docs):
  if the env var is set anywhere (OS env or any `env` block), it is authoritative — `=1` →
  **off**, `=0` → **on** even against `autoMemoryEnabled: false`. If the env var is unset,
  apply settings precedence (managed > local > project > user) to `autoMemoryEnabled`
  (default `true`). When the env var and the setting disagree, report the effective state as
  the env var dictates and call out the disagreement so the user can align them.
- **Store location.** If any scope sets `autoMemoryDirectory`, the effective directory is that
  override (highest-precedence scope wins), not the slug-derived default the snapshot printed.
  Expand `~/` and report the real path, plus whether `MEMORY.md` and topic files exist there.
- **Store contents.** Report the `MEMORY.md` line count and topic-file count at the effective
  directory (re-list if the effective dir differs from the default).

## Step 4: Report

Present a short posture summary:

1. **Effective auto-memory state**: on / off / conflicting (with the reason).
2. **Where it is configured**: which scope(s) set `autoMemoryEnabled` / the env var, and to what.
3. **Store**: effective directory path; present or empty; line/topic counts if present.
4. **Next actions**: if on and the user wants it off, point to `disable`; if files exist and
   the user wants them gone, point to `purge`; for the Claude Desktop / claude.ai account
   store, summarize [desktop.md](desktop.md).

Do not edit files or delete anything in this action.
