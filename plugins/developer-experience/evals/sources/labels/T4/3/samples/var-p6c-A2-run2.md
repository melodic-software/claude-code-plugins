### Assistant final message, turn 1

# Setup check: tarnquill

Nothing was written. Next `apply` would **migrate** the conventions file out of `.claude/`.

| # | Item | Result | Evidence | Remediation |
|---|---|---|---|---|
| 1 | Pointer line | **FAIL** (`stale`) | `AGENTS.md:13` points at `.claude/developer-experience.md`. The helper won't accept that path (exit 2: "the conventions file is never under .claude/"). Against the default `docs/conventions/developer-experience.md` (`source: default`) it reports `stale`. | Run apply; it rewrites the line through the helper. |
| 1a | Path source | INFO | No convention home is bound, so the path falls back to the plugin default `docs/conventions/developer-experience.md`. | Accept that path or name another before `apply`. Basis: verified (helper output `source: default`; `reference/conventions-file.md:19-21`). |
| 2 | Load | **FAIL** (`missing-import CLAUDE.md`) | `CLAUDE.md` exists and doesn't import `AGENTS.md`. With the default instruction-file setting, Claude Code reads `CLAUDE.md` instead, so the pointer line isn't seen. | Add to CLAUDE.md: `@AGENTS.md`. This skill never edits `CLAUDE.md`, so add it by hand. To move instructions into `AGENTS.md` later: `claude plugin install instruction-placement@<marketplace>`. |
| 3 | Conventions file location | **FAIL** (old location) | The file is at `.claude/developer-experience.md`, which has `written_against: developer-experience@0.0.1` and the `# Developer tooling conventions` heading. Nothing exists at `docs/conventions/developer-experience.md`. The only file that refers to the old path is `AGENTS.md:13`. | Run apply to migrate. Deleting the old file needs its own yes. |
| 4a | Sections present | PASS | All five sections the plugin defines (Tools, Shared helpers, CLI contract, Secrets, Platforms) are there, each with a marker. | — |
| 4b | `CLI contract` (`source=default`) | **FAIL** | `.claude/developer-experience.md:19-20`: the body doesn't match the current default. The file was written against 0.0.1 and the plugin is now 0.1.0, so `apply` would replace it with the 0.1.0 default. I can't tell whether this text was the 0.0.1 default or a team edit. | If the team wrote this text, change the marker to `source=chosen` before `apply` so the body is kept. Otherwise let `apply` update it. |
| 4c | `chosen` sections | INFO | The plugin now has defaults for Secrets and Platforms. These are `chosen` sections, so they are never rewritten. | — |
| 5b | Fact: "`tq item comment` posts a tracker comment" | **FAIL** | `ItemCommentCommand.cs:24-28` only writes `.tarnquill/outbox/<id>.json`. Nothing in the repo sends it. | Rephrase: "queues the comment as JSON in `.tarnquill/outbox/<id>.json`; nothing in this repo sends it. Non-interactive." |
| 5c | Fact: Secrets, "Tokens come from `TARNQUILL_FORGE_TOKEN`" | **FAIL** | No file reads `TARNQUILL_FORGE_TOKEN`. The only forge variable is `TARNQUILL_FORGE_URL` (`README.md:13`), and no source file reads that either. | Rephrase as a team rule ("New and changed tools read tokens from the environment, never from a flag"), or move the variable under `## Not yet`. |
| 5d | Fact: `tq commit` is interactive with no bypass | PASS | `CommitCommand.cs:11-20` | — |
| 5e | Fact: `tq env check` checks required tools | PASS | `EnvCheckCommand.cs:9`. It only checks `git`; worth saying so. | — |
| 5f | Fact: `scripts/build.sh` and `scripts/build.ps1` | PASS | Both exist and run `dotnet build` on the solution. | — |
| 5g | Tools completeness | INFO | `scripts/clean-outbox.sh` (deletes queued outbox JSON, non-interactive) isn't listed under Tools. | Add it under Tools. |
| 5h | Fact: `ProcessRunner.Run` in `src/Tarnquill.Cli/Infrastructure/` | PASS | `ProcessRunner.cs:9` | — |
| 5i | Fact: Platforms | PASS | `build.sh` covers bash and `build.ps1` covers pwsh, and the projects target `net10.0`. No file names macOS explicitly. | — |
| 6 | User level | — | Not run (no `--user`). | — |

**Next `apply` state: migrate.** It would carry `.claude/developer-experience.md` to `docs/conventions/developer-experience.md` (or the path you choose), set `written_against: developer-experience@0.1.0` and point the `AGENTS.md` line at the new path through the helper. The false facts in 5b–5c are team content, so `apply` copies them across unchanged unless you say which fix to use. You'd need to add the `@AGENTS.md` import to `CLAUDE.md` yourself either way.

To go ahead, run `/developer-experience:setup apply`. You can add `--path <file>` if you don't want the default location.
