# Gather-block composition record

The owner record for one harness claim that many skills in this marketplace repeat: a skill's
whole pre-compute block reaches the shell as a single invocation, so a git-bearing block is one
compound git command and a worktree-isolated session refuses it. Cite this heading instead of
restating the claim.

## The pre-compute block runs as one shell invocation

**Claim.** Claude Code submits the commands in a skill's `## Pre-computed context` block to the
shell as one invocation rather than one call per line. A block that carries a git command
therefore reads to a worktree-isolated session as a compound command containing git, which that
session's isolation check refuses. Git reads a skill needs on every run belong in separate body
calls, one command per call, where each is screened on its own.

**Basis.** Three sources, none of which alone settles it:

- [Extend Claude with skills](https://code.claude.com/docs/en/skills) documents the injection
  mechanism, the inline and fenced `!` forms, the shell each runs under, and the abort on failure.
  It does not state how a block's commands are grouped into invocations, so the composition itself
  is not a documented fact.
- [Worktrees](https://code.claude.com/docs/en/worktrees#how-claude-code-enforces-isolation)
  documents four checks: file edits into the main checkout, a command whose working directory
  resolves to the main checkout or cannot be verified to stay outside it, a git redirect into the
  main checkout, and a command shape whose text cannot show that any git it runs stays inside the
  worktree. The "can't verify" sentence is scoped to git. A `$` expansion that never runs git is
  not that check. **Claim, basis, as of, recheck:** those four checks, the worktrees section
  linked above, 2026-09-28, and a re-fetch of that section that changes the four checks or stops
  scoping the command-shape check to git.
- `scripts/check-skill-precompute-compose.sh` in this repository is the gate that encodes the
  observed behavior. It refuses a skill whose pre-compute block holds a git command together with
  more than one injection line, which is the shape that breaks only in isolated agents while
  continuous integration stays green.

**Verified.** The composition half, 2026-09-06, against Claude Code 2.1.263 and the skills page.
The isolation half, 2026-09-28, against the worktrees page named above.

**Recheck trigger.** Any of these: the skills page gains or loses a statement about how a block's
commands are submitted to the shell; the worktrees page changes the four checks or stops scoping
the command-shape check to git; a release note names skill shell injection or worktree isolation;
or `check-skill-precompute-compose.sh` stops refusing the git-plus-multiple-lines shape.

**Scope.** The composition claim is the load-bearing half. The isolation half is documented
upstream and stands on the worktrees page alone.

## Command shapes an isolated session accepts

Worker skills cite this heading for the Bash forms a worktree-isolated session runs. Every refusal
below comes from Claude Code's worktree isolation, not from this repository's hooks: no hook here
emits the refusal text, and a hook block names the plugin it comes from, which a
harness refusal lacks. The check is by design and cannot be turned off, per the Command shape
bullet of the worktrees page.

| Refused shape | Accepted rewrite |
|---|---|
| A compound command that contains git (`a && b`) | One command per Bash call, so each is screened alone |
| When the command can run git: a path or command built from a variable or expansion (`$VAR`, `${VAR}`, `${!name}`, `${ cmd; }`) | A literal absolute path; a bare `$HOME` is the one expansion observed to pass |
| `bash <script>` or `sh <script>` | The executable path, `<script>` itself |
| When the command can run git: a file read through a shell pipeline (unprobed) | The Read tool |
| `--body-file -` or any stdin heredoc whose text mentions git | A body file written first, passed by path |
| A path containing `github` (the ghq layout `github.com/<org>/<repo>`) | Unverified: no documented rule; not probed; refusals reported on such paths were not attributed. Not an accepted rewrite |

The expansion and pipeline rows apply only when the command can run git, because the command-shape
check is scoped to git. Claude Code 2.1.257 stopped refusing loops, `$VAR` reads, `"$(...)"`, and
heredocs that never touch git, and 2.1.259 stopped refusing loops, xargs pipelines, and
launcher-wrapped commands that cannot reach the main checkout. A `$` expansion in a command that
never runs git is not refused by this check.

**Claim.** The compound-git, `bash <script>` and stdin-heredoc shapes are refused by the isolation
check, and the right column runs for those three rows; each was observed in a live isolated
session. The variable-path, shell-pipeline and `github` rows were not observed, and the `github`
row is unverified. No live probe of any row was run against the current release.

**Basis.** The Command shape bullet of
<https://code.claude.com/docs/en/worktrees#how-claude-code-enforces-isolation> (a command is
blocked when the text cannot show that its git stays in the worktree: a computed command name,
unparseable syntax, or an expansion that could run an unspelled command), and the observed sweep
refusals in [#4537](https://github.com/melodic-software/claude-code-plugins/issues/4537). The docs
do not name `github` paths, so that row rests on the absence of any such rule, not on a probe.

**As of.** 2026-10-01, Claude Code 2.1.287.

**Recheck.** The Command shape bullet changes, a release note changes which Bash forms an isolated
session accepts, or a live `isolation: "worktree"` agent runs any row, which settles it.
