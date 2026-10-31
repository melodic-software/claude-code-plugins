# knowledge: work root

Every knowledge skill resolves where it writes from one rule, implemented once in
`scripts/work-root.mjs` (written `<plugin-root>/scripts/work-root.mjs` below; each skill's
`SKILL.md` shows the command with the plugin root filled in).

## The rule

- **Session root**: `git rev-parse --show-toplevel` run in the session's working directory, so a
  session that has entered a worktree resolves to that worktree. Git runs without an inherited
  `GIT_DIR`, `GIT_WORK_TREE`, `GIT_INDEX_FILE` or env-passed config entries. When neither the
  working directory nor any ancestor holds a `.git`, the session root is the working directory
  itself; a git error where a `.git` exists (dubious ownership, a corrupt repository, git
  missing) is an error, never a fallback. Never `CLAUDE_PROJECT_DIR`: in a worktree session it can name a checkout other
  than the one the session writes to.
  - **Pointer**: for where `CLAUDE_PROJECT_DIR` points after a session enters a worktree, see
    <https://code.claude.com/docs/en/worktrees#ask-claude-to-create-a-worktree>; for the write
    refusal, see <https://code.claude.com/docs/en/worktrees#how-claude-code-enforces-isolation>.
  - **As of**: 2026-10-11
  - **Recheck trigger**: either section changes where `CLAUDE_PROJECT_DIR` points inside a
    worktree session or which writes the isolation checks refuse.
- **Work root**: the session root joined with the `library_dir` setting. Missing, empty, `.`, or a value
  that is exactly one `${user_config.<key>}` token left unsubstituted means the session root; any
  other value holding `${user_config.` is an error. A relative value
  resolves against the session root; an absolute value, a leading `~` (the home directory) and a
  `${NAME}` / `%NAME%` environment-variable reference are used as they expand. An unset or empty
  variable fails the run: report it and stop.
- **Progress key** (distill's cross-session state): the session root's basename lowercased, each
  run of other characters a single `-`, then `-` and the first 8 hex of the SHA-256 of the session
  root path. The main checkout's key is its basename slug plus a hash of its top-level path; each
  worktree has its own top-level path, so it gets its own key.

## Commands

```bash
node "<plugin-root>/scripts/work-root.mjs" --library-dir '<library_dir>'   # the work root
node "<plugin-root>/scripts/work-root.mjs"                                 # the session root
node "<plugin-root>/scripts/work-root.mjs" --progress-key                  # the progress key
```

Run from the session's working directory. Pass the value in single quotes, literal in bash and
PowerShell: the script expands `~` and the variable itself and exits 1 on an unset one, where a
shell would substitute an empty string. Resolve once, before the first write, and use the printed
absolute path for every write after it. Node code imports `sessionRoot`, `workRoot` and
`progressKey` from the same file.
