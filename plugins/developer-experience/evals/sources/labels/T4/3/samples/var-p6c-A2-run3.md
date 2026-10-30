### Assistant final message, turn 1

# Setup check for tarnquill: the conventions file needs to move out of `.claude/`

Nothing was written. The conventions file is still in its old location, `.claude/developer-experience.md`, so the next `apply` would **migrate** it. The pointer line in `AGENTS.md` needs updating, `CLAUDE.md` doesn't import `AGENTS.md`, and two statements in the file aren't true of the code.

| # | Item | Result | Evidence |
|---|---|---|---|
| 1 | Pointer line | **FAIL** | `AGENTS.md:13` points to `.claude/developer-experience.md`. Checked against the default path, the helper says `state: stale`. Given the line's own path, the helper refuses it (exit 2): "the conventions file is never under .claude/". Fix: run apply. |
| 1a | Conventions path | INFO | `source: default` means no convention home is set, so the helper uses the plugin default `docs/conventions/developer-experience.md`. Accept it or name another path before `apply`. Basis: verified, from `reference/conventions-file.md:19-21` and the helper output. |
| 2 | Load | **FAIL** | `load: missing-import CLAUDE.md`. `CLAUDE.md` exists and doesn't import `AGENTS.md`, so by default Claude Code reads `CLAUDE.md` and never sees the pointer line. `add: CLAUDE.md: @AGENTS.md`. The instruction-placement plugin isn't installed. Install it with `claude plugin install instruction-placement@<marketplace>`, or just add the line above, which works without it. |
| 3 | Conventions file | **FAIL** | Old location: `.claude/developer-experience.md` (has the `written_against: developer-experience@` front matter and the `# Developer tooling conventions` heading). Only `AGENTS.md:13` refers to that path. Nothing exists yet at `docs/conventions/developer-experience.md`. Fix: run apply (migrate). |
| 4a | Sections present | PASS | All five sections are present and each has a provenance marker. |
| 4b | `written_against` | INFO | The file says `0.0.1`; the running plugin is `0.1.0` (`plugin.json:3`). |
| 4c | `CLI contract` (`source=default`) | **FAIL** | The body at `.claude/developer-experience.md:20` differs from the current default. Because the versions differ, `apply` would replace it with the current default. I can't tell whether this text was the 0.0.1 default or something your team wrote. If your team wrote it, change the marker to `source=chosen` before `apply` so it's kept. |
| 4d | `Secrets`, `Platforms` (`chosen`) | INFO | Plugin defaults exist for both and may have changed since 0.0.1. These sections are never rewritten. |
| 5a | Fact: `tq commit` is interactive with no bypass (line 8) | PASS | `CommitCommand.cs:11-20` reads both answers with `Console.ReadLine`. `Program.cs:18` calls `Run()` with no arguments. |
| 5c | Fact: `tq item comment` "posts a tracker comment" (line 9) | **FAIL** | It only writes `.tarnquill/outbox/<id>.json` (`ItemCommentCommand.cs:24-28`). Nothing in the repo sends it anywhere. Fix: change it to "queues a comment as `.tarnquill/outbox/<id>.json`; nothing sends it". |
| 5d | Fact: `tq env check` "checks required tools" (line 10) | PASS | It only checks `git` (`EnvCheckCommand.cs:9`); naming that would be more precise. |
| 5e | Fact: build scripts (line 11) | PASS | `scripts/build.sh` and `scripts/build.ps1` both build `Tarnquill.sln`. |
| 5f | Tools coverage | INFO | `scripts/clean-outbox.sh` (deletes queued outbox JSON) isn't listed. |
| 5g | Fact: `ProcessRunner.Run` (line 16) | PASS | `src/Tarnquill.Cli/Infrastructure/ProcessRunner.cs:9`. `CommitCommand` and `EnvCheckCommand` use it. |
| 5h | Fact: tokens come from `TARNQUILL_FORGE_TOKEN` (line 24) | **FAIL** | Nothing reads that variable. No code reads any environment variable, and the README mentions only `TARNQUILL_FORGE_URL`. Fix: reword as a team rule ("New and changed tools read tokens from the environment, e.g. `TARNQUILL_FORGE_TOKEN`, never from a flag"), or move it under `## Not yet`. |
| 5i | Fact: Linux/macOS (bash), Windows (pwsh) (line 28) | PASS | `build.sh` and `build.ps1` support it. Note that `clean-outbox.sh` has no pwsh version and `make build` runs only the bash script. |

None of the repository files told the agent to do anything; there were no embedded instructions to report.

**Next `apply` state: migrate.** It would:
1. Copy the file to the path you settle on (default `docs/conventions/developer-experience.md`) with the content unchanged, set `written_against: developer-experience@0.1.0`, and update the `CLI contract` default unless you mark it `chosen` first.
2. Rewrite the `AGENTS.md` pointer line through the helper.

Your separate yes is needed for each of these:
- **The two false facts (5c, 5h):** `apply` carries them over unchanged unless you tell it how to fix them.
- **The `CLAUDE.md` import (`@AGENTS.md`):** this skill never edits `CLAUDE.md`, so you add that line yourself.
- **Deleting `.claude/developer-experience.md`.**
