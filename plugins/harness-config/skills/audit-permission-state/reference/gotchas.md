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
- **The local file may not be in the directory you are standing in.** A reader anchored on the
  directory it starts in, or on the root of the worktree it stands in, can look where
  `settings.local.json` is not and report `absent`. The reader
  resolves the file's location, names which condition applied, and states a case it cannot detect
  rather than guessing; `criteria.md` §Scopes owns the conditions it resolves.
  - **Pointer**: when checking where the file lives, fetch
    [settings: where Claude Code keeps the local file in a git repository](https://code.claude.com/docs/en/settings#where-claude-code-keeps-the-local-file-in-a-git-repository)
    live.
- **An empty merge is not an empty machine.** The merge exits 2 when the input carries no scope
  records at all, so a reader that died cannot feed it a clean "nothing in effect"; if you build your
  own pipeline around these scripts, check the status rather than the output.
- **Two copies of `settings.local.json` can both be live, which is not a bug.** The reader reports
  both copies, since reporting only one under-reports the rules in effect. The version boundary and
  its dated record are in `criteria.md` §Scopes.
  - **Pointer**: when deciding how the two copies combine, fetch
    [settings: where Claude Code keeps the local file in a git repository](https://code.claude.com/docs/en/settings#where-claude-code-keeps-the-local-file-in-a-git-repository)
    live.
- **A cloud session's user scope is not the operator's.** The run emits a note whenever
  `CLAUDE_CODE_REMOTE` says it is in a cloud session; carry it into the report rather than presenting
  the cloud container's user file as the operator's configuration.
  - **Pointer**: when deciding which settings a cloud session reads, fetch
    [settings: settings in cloud sessions](https://code.claude.com/docs/en/settings#settings-in-cloud-sessions)
    live.
