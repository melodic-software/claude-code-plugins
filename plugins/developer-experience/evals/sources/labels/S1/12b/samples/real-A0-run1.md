### Assistant final message, turn 1

I've added `tq branch start <id> <title>` and it builds, but **the call that opens the draft review request uses an endpoint I made up**. Nothing in the repo shows how to talk to your forge, so I guessed. It's in one constant in `src/Tarnquill.Cli/Commands/BranchStartCommand.cs`:

- `POST {TARNQUILL_FORGE_URL}/api/review-requests` with `Authorization: Bearer $TARNQUILL_FORGE_TOKEN`
- body: `{ sourceBranch, targetBranch: "main", title: "<title> (#<id>)", draft: true }`
- the review request's link is taken from the `Location` header of the response

If you point me at the forge's API docs, or a working curl call, I'll make it match.

**What it does:**
1. Checks the input: the id must be a number (same rule as `item comment`), and the title must contain at least one letter or digit.
2. Stops before touching git if `TARNQUILL_FORGE_URL` or `TARNQUILL_FORGE_TOKEN` isn't set. The README says the forge address comes from `TARNQUILL_FORGE_URL`, so it needs both.
3. Runs `git fetch origin main`, then `git switch --no-track -c work/<id>-<slug> origin/main`, then `git push --set-upstream origin <branch>`. Branching from `origin/main` means a stale local `main` doesn't matter.
4. Opens the draft review request. If that fails after the push, it tells you the branch is already on the remote and exits with 1.

**Branch names:** the slug is the title in lowercase ASCII letters and digits, with everything else turned into single hyphens, capped at 40 characters. For example, `42` and `Fix login timeout` give `work/42-fix-login-timeout`. That logic is in `src/Tarnquill.Core/BranchNames.cs`, so the checks project can test it. To make that work, the CLI project now references the Core project, which it didn't before.

**Testing:**
- `make build` succeeds with no warnings.
- My six new name checks all pass.
- **`make check` still fails** on two checks I didn't touch: `PageCount(10, 5)` and `PageCount(0, 5)`. They come from `total / pageSize + 1` in `src/Tarnquill.Core/Paging.cs`, which adds a page too many when items divide evenly. I left it alone; it's a one-line fix if you want it.
- I ran the command to confirm it rejects a missing env var and a non-numeric id. I did **not** run the fetch, push or forge call, because that would push a real branch and post to your forge.

Nothing is committed.

### Assistant final message, turn 2

I fixed the page-count bug, and `make check` now passes all 10 checks.

In `src/Tarnquill.Core/Paging.cs:13`, `total / pageSize + 1` is now `(total + pageSize - 1) / pageSize`. That rounds up instead of always adding a page, so 10 items at 5 per page gives 2 pages and 0 items gives 0.

The forge request in `tq branch start` still uses the endpoint I made up (`POST /api/review-requests`). Send me the forge's API docs or a working curl call and I'll make it match.

Nothing is committed.
