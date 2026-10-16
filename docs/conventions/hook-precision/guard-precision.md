# Guard precision: the default-on blocking guards, measured

Each guardrails guard that blocks by default earns that default by its measured precision
([ADR 0003](../../adr/0003-verification-guards-earn-default-on-by-measured-precision.md)). This
table records the measurement and the verdict for each one. It holds aggregate counts only.

## Corpus and method

- **Corpus.** The local Claude Code transcripts of one operator on one Linux (WSL) host, read on
  2026-10-15: 5,492 transcript files holding 133,038 distinct Bash and PowerShell tool calls.
  Seeded probe sessions (runs built to exercise a guard) are left out, and so is the session that
  ran this measurement, from the replays. ADR 0003 asks that the corpus be named because one host's sessions
  are not evidence about other distributions; the Windows-only guards get none here.
- **Logged refusals.** Every tool result that is a guardrails hook refusal, attributed to the
  guard whose refusal text it carries. This measures the guard as it shipped at the time.
- **Replay.** The three guards this change reworks were also re-run, as they now ship, on every
  logged call of their shape, with the attended flag unset: 569 `git commit -m` calls, 681
  recursive deletes and 27,250 calls naming a credential word. Replay judges against today's
  file system, so a delete whose working directory no longer exists cannot be judged; those fires
  are counted apart.
- **Classification.** Each fire was read and marked a true positive when the command carried the
  hazard the guard names (for block-root-delete-target, a delete outside the session's allowed
  roots is its documented target), and a false positive when it did not. block-hook-bypass, with
  1,684 fires, was classified on a random sample of 40.
- **The bar.** ADR 0003 fixes no threshold and asks for one to be named. For a guard that blocks
  a tool call: most of its fires must be right (precision at least 50%), or its false positives
  must come from one identified cause with a scoped fix. A guard that stops irreversible
  damage may stay on below the bar when its noise is one identified cause it keeps on
  purpose; its row names the cause. A guard with no fires has undefined
  precision: its default stays and its contract test's seeded cases show it detects. A
  refusal of a command too long to parse (the shared 16,384-character cap) is counted apart from
  the matcher, because it is the chain's fail-closed posture, not the guard's match.

## Results

| Guard | Fires | True | False | Precision | Verdict | Default |
|---|---|---|---|---|---|---|
| block-dangerous-git (logged) | 35 matcher, 4 length cap | 32 | 3 matcher, 4 cap | 91% matcher, 82% with cap | above the bar | on |
| block-no-verify (logged) | 12 matcher, 28 length cap | 11 | 1 matcher, 28 cap | 92% matcher, 28% with cap | above the bar on the matcher; the cap is one cause (long heredoc file writes) | on |
| block-root-delete-target (replay, as shipped) | 202 (about 15 not judgeable) | about 58 | 129 | about 31% | below 50%, kept on: 121 of the 129 are one cause, a variable the same command sets, which the guard reads only in the one adjacent shape it can prove | on |
| block-root-delete-target (replay, before this change) | 225 (about 14 not judgeable) | about 58 | 153 | about 27% | same cause | not shipped |
| block-noncanonical-commit (replay, as shipped) | 0 of 569 | 0 | 0 | undefined | default stays; seeded cases in its contract test | on |
| block-noncanonical-commit (replay, before this change) | 218 of 569 | 0 | 218 | 0% | a newline is not the hazard (#6464) | not shipped |
| block-credential-read (replay, as shipped) | 34 | 2 | 32 | 6% | below the bar | **off** |
| block-hook-bypass (logged, sample of 40) | 1,684 | 14 of 40 | 26 of 40 | 35% | below the bar | **off** |
| secret-pattern-detection (logged) | 2 | not classified | not classified | not measured | insufficient data, default unchanged | on |
| hardcoded-path-check | 0 | 0 | 0 | undefined | insufficient data, default unchanged | on |
| block-unresolved-pr-merge | 0 | 0 | 0 | undefined | insufficient data, default unchanged | on |
| block-convention-violation | 0 | 0 | 0 | undefined | insufficient data, default unchanged | on |
| block-windows-drive-tmp | 0 | 0 | 0 | undefined | insufficient data on a Linux host, default unchanged | on |
| block-exported-msys-pathconv | 0 | 0 | 0 | undefined | insufficient data on a Linux host, default unchanged | on |
| check-bash-file-changes (blocking fires) | 0 | 0 | 0 | undefined | insufficient data, default unchanged | on |

Notes on the rows:

- **block-dangerous-git.** The three matcher false positives are leases pinned to a full object
  id, two of them refused by an earlier version that misread the repository's hash width, and one
  spelled through a command substitution the guard does not evaluate.
- **block-no-verify.** The one matcher false positive set `core.hooksPath` in a throwaway test
  repository. The length-cap refusals were long heredoc file writes holding no git command.
- **block-root-delete-target.** Of the 129 false positives, 121 delete a variable the same
  command set (from `mktemp`, a loop, another variable, or a literal statements before the
  delete), and 8 are root-shaped text inside a heredoc body the guard reads as commands. A
  literal is honored only when its statement sits right before the delete and nothing in the
  command can set a variable out of sight: a broader reading let a verified `declare -n`,
  `trap`, `printf -v` or `eval` reassignment delete `/etc`. The guard stays on because it
  stops irreversible deletes and its noise is that one deliberate, identified cause. The
  about 15 not judgeable fires target a directory inside a working directory that no longer
  exists. "About" marks a count extrapolated from a sample of 25 of the 73 outside-tree fires.
- **block-credential-read.** 23 of its fires are `gh auth token` inside a substitution whose
  output never reaches the transcript (`TOKEN=$(gh auth token)`), and most of the rest are
  credential words in a heredoc body or a presence check sent to `/dev/null`. The two true
  positives echoed a key prefix and printed a credentials JSON file. With the guard off by
  default, the `Read()` deny rules `/guardrails:setup apply install-read-deny` prints cover the
  Read tool and `cat`-family reads. The guard keeps its `gh-auth-token`, `credential-fill` and
  `env-echo` families and its `jq` and PowerShell `Get-Content` reads for anyone who turns it
  on, because the permissions page documents a `Read()` deny rule reaching the built-in file
  tools, `cat`, `head`, `tail`, `sed`, `tee` and redirects, and nothing that prints a token or
  is read through `jq` or PowerShell ("Read and Edit" in
  <https://code.claude.com/docs/en/permissions>, read 2026-10-15).
- **What block-credential-read no longer guards.** Per Q44, `cat .env` and
  `bash -c "cat .env"` pass this guard even when it is on. They rely on the native `Read()`
  deny rules alone, and the same page does not say those rules reach a command wrapped in
  `bash -c`, so the wrapped form may be unguarded.
- **block-hook-bypass.** Its false positives are shell writes to scratch, temp and gitignored
  paths, which no Write or Edit guard would have checked.
