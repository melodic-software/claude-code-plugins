### Assistant final message, turn 1

I added `tq branch start <id> <title>`. It builds with no warnings, and the dry-run works in both text and `--json` modes. I haven't run it against a real forge or remote, and I don't know your forge's API, so the review-request call is my guess at it. Check that first.

**Usage**
```
tq branch start 42 "Fix login timeout"    # → work/42-fix-login-timeout
tq branch start 42 Fix login --dry-run --json
```
It runs `git fetch origin main`, then `git switch --no-track -c work/<id>-<slug> origin/main`, then `git push -u origin <branch>`, and then opens a draft review request. It follows the CLI rules in `AGENTS.md`:
- **Help and exit codes:** it has `--help`, and exits 0 on success, 1 on failure and 2 on usage errors.
- **JSON and dry-run:** `--json` prints the result as JSON, and `--dry-run` prints the steps without running git or calling the forge.
- **Token:** it reads the token only from `TARNQUILL_FORGE_TOKEN`.
- **External commands:** git runs through `ProcessRunner.Run`.

**Things to check**
- **Forge API (a guess):** the README says the forge is reached through `TARNQUILL_FORGE_URL`, but there's no forge client in the repo to copy from. `src/Tarnquill.Cli/Infrastructure/ForgeClient.cs` sends `POST {TARNQUILL_FORGE_URL}/api/review-requests` with a `Bearer` token and `{source, target, title, body, draft: true}`, and reads `url` from the response. The path and payload are in that one file, so tell me the real API and I'll match it.
- **Branch base:** it branches from a freshly fetched `origin/main`, not your local `main`, so a stale local copy can't leak in.
- **Order of steps:** the command checks the forge URL, the token and that the branch doesn't already exist before touching git. If the push or the forge call fails later, the error says what was already done and how to retry.
- **Slugs:** a slug is lowercase ASCII letters and digits separated by `-`, cut to 40 characters. This logic is in `src/Tarnquill.Core/BranchName.cs` and has new checks in the checks project, all passing. To use it from the CLI, I added a project reference from `Tarnquill.Cli` to `Tarnquill.Core`.

**Not verified**
- I couldn't test the usage-error exit code or the missing-environment-variable path because those commands were blocked by the permission mode. The full flow has never run, since this repo has no remote configured.
- `make check` fails, but on two checks that were already there: `Paging.PageCount` returns 3 for (10, 5) and 1 for (0, 5). It uses `total / pageSize + 1` instead of rounding up. I left it alone because it's outside this task; it's a one-line fix if you want it.

I also listed the command in the tools section of `AGENTS.md` and in the `tq` usage text. Nothing is committed.

### Assistant final message, turn 2

I fixed `Paging.PageCount`, and `make check` now passes all 11 checks, including the two that were failing before.

In `src/Tarnquill.Core/Paging.cs`, the method now rounds up only when there's a remainder: `total / pageSize + (total % pageSize == 0 ? 0 : 1)`. That gives 2 pages for 10 items at 5 per page and 0 pages for 0 items. I avoided `(total + pageSize - 1) / pageSize` because it can overflow when `total` is close to `int.MaxValue`.

The forge request in `branch start` still uses the endpoint and fields I guessed: `POST /api/review-requests` with a Bearer token. If you send me the forge's real API for creating a review request, I'll match it in `ForgeClient.cs`. Nothing is committed yet.
