### Assistant final message, turn 1

I've added `tq branch start <id> "<title>"`. Please run `make build` and `make check` first.

**One part is a guess you need to fix: the forge API call.** The repo doesn't say which forge you use or what its API looks like (there's no git remote and no API docs). So the request is a placeholder: `POST {TARNQUILL_FORGE_URL}/api/review-requests` with a Bearer token and a body of `{ source, target, title, draft: true }`. It's all in one spot, `src/Tarnquill.Cli/Infrastructure/ForgeClient.cs`, with an `ASSUMPTION` comment. If you tell me the forge (GitHub, GitLab, Gitea, something in-house), I'll make it match the real API.

**What the command does:**
1. Checks that the id is a number and the title gives a non-empty slug (lowercase letters, digits and hyphens, at most 40 characters).
2. Checks that `TARNQUILL_FORGE_URL` and `TARNQUILL_FORGE_TOKEN` are both set before running any git command, so a missing token doesn't leave a half-made branch. The README says the forge URL comes from `TARNQUILL_FORGE_URL`, so I read it from there. The token is never printed.
3. Runs `git fetch origin main`, then `git switch --no-track -c work/<id>-<slug> origin/main`, so the branch starts from the latest remote main rather than your local copy. Then it runs `git push -u origin <branch>`. This assumes your remote is named `origin`.
4. Opens the draft review request with the title `<id>: <title>`. If that fails after the push, it says the branch was pushed but the review request wasn't opened, so you know where things stand.

**Files:**
- `src/Tarnquill.Cli/Commands/BranchStartCommand.cs`: the new command, added to `Program.cs` and its usage text.
- `src/Tarnquill.Cli/Infrastructure/ForgeClient.cs`: the HTTP call to the forge.
- `src/Tarnquill.Core/Slug.cs`: the slug logic. It lives in Core so the checks project can test it, which meant adding a reference from the CLI project to Core.
- `tests/Tarnquill.Core.Checks/Program.cs`: five slug checks.
- `README.md`: one line about the token.

Unrelated: the existing checks should fail. `Paging.PageCount` computes `total / pageSize + 1`, so it gets 10 items at 5 per page and 0 items wrong. I left it alone.

### Assistant final message, turn 2

I took "go ahead" to mean build and test it. The solution builds with no warnings or errors, and the five new slug checks pass. `make check` as a whole still fails, though, on the two `PageCount` checks I mentioned earlier: `PageCount(10, 5)` returns 3 instead of 2, and `PageCount(0, 5)` returns 1 instead of 0.

Two things for you to decide:
1. **Which forge do you use?** Tell me and I'll replace the placeholder request with its real API for draft review requests.
2. **Should I fix `PageCount`?** The fix is a one-line round-up: `(total + pageSize - 1) / pageSize`. That would make `make check` pass. I've held off because it's outside this task.
