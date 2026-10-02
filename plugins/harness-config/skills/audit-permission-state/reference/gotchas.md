# Gotchas and verification status

Read this when a result looks wrong, when debugging a stage by hand, or before trusting a managed
surface on macOS or Linux. The skill body carries the rules; this file carries the failure modes that
produce a confidently wrong answer and the honest limits of what has been verified.

## Verification status

The Windows registry surface was verified end to end against a real registry key. The macOS
preferences domain and the Linux managed paths are **not** verified on real hardware. They are an
honest manual-verification gap, not a claim. Treat a macOS `plist` record as reporting the surface,
not its contents: the reader names the domain and does not yet inventory its rules.

The Windows and ownership branches of the local-scope resolver are covered by the test suite through
their fixture seams (`PERMISSION_STATE_OSTYPE`, `PERMISSION_STATE_OWNER_OVERRIDE`), not against a
native Windows machine or a foreign-owned checkout. Same distinction: the logic is tested, the
platform is not.

## Failure modes

- **A registry read that silently reports "no policy."** On Git Bash, MSYS rewrites any argument
  containing backslashes as though it were a POSIX path, so a registry key reaches `reg.exe` mangled
  and the query dies with `ERROR: Invalid syntax`. A caller that only checks the exit status reads
  that as "no managed policy deployed" on a machine that has one. The reader disables the rewrite for
  those calls; if you invoke `reg` yourself while debugging, do the same or you will reproduce the
  wrong answer by hand.
- **A missing shared library must not look like a clean machine.** If the plugin's
  `lib/managed-scope.sh` cannot be sourced, the reader exits 2 rather than reporting every managed
  surface `absent`. A reader that cannot load its own location list must not answer the question.
- **A summary of zeros is not a clean machine.** Every stage summary carries a `status=` token.
  `status=incomplete` means at least one scope could not be opened, so the counts beside it cover only
  what was read. Read the token before the counts; a finding count of zero under `status=incomplete`
  is the report saying it could not look, not that it looked and found nothing.
- **The local file is not under the worktree you are standing in.** `settings.local.json` resolves
  through worktrees to the main checkout, so a reader anchored on `git rev-parse --show-toplevel`
  looks where the file is not and reports `absent`. Four documented conditions keep it in the start
  directory instead: outside a git repository, when the repository root is the home directory, on
  Windows, and when the repository root or its `.git` or `.claude` entry is not owned by the current
  user. The reader resolves all four and names which one applied. A fifth case is not detectable and
  is stated rather than guessed: the Agent SDK's `resolveSettings()` helper always reads the file from
  the starting directory, which is a helper's behavior and not a property of a running session.
- **An empty merge is not an empty machine.** The merge exits 2 when the input carries no scope
  records at all, so a reader that died cannot feed it a clean "nothing in effect"; if you build your
  own pipeline around these scripts, check the status rather than the output.
- **Two live copies of `settings.local.json` are normal, not a bug.** When a pre-v2.1.211 copy sits in
  the start directory, the repository-root copy wins on a shared key but permission rules from both
  stay in effect. Reporting only one of them under-reports what is live. The dated record for the
  boundary is `criteria.md` §Scopes.
- **A cloud session's user scope is not the operator's.** There, the operator's own user settings and
  local file are not read at all and only server-managed settings arrive, so a `present` user record
  describes the container. The run emits a note whenever `CLAUDE_CODE_REMOTE` says so; carry it into
  the report rather than presenting the container's file as the operator's configuration.
