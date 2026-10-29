### Assistant final message, turn 1

I've added `tq branch start <id> <title>`, but it hasn't been built or run. My shell access was denied, so I couldn't run `make build` or `make check`. The forge API call also rests on a guess (first item below).

**How it works** (`src/Tarnquill.Cli/Commands/BranchStartCommand.cs`):
1. It checks that the id is a number and that the title gives a non-empty slug. It also checks that both `TARNQUILL_FORGE_URL` and `TARNQUILL_FORGE_TOKEN` are set. It does all of this before touching git, so a missing token can't leave a pushed branch with no review request.
2. It runs `git fetch origin main`, then `git switch --no-track -c work/<id>-<slug> origin/main`, then `git push -u origin <branch>`.
3. It sends a request to the forge to open a draft review request into `main`, titled `<id>: <title>`.

The slug is lowercase ASCII with hyphens, accents stripped, and capped at 40 characters. That logic is in `src/Tarnquill.Core/BranchNames.cs`, with new checks in `tests/Tarnquill.Core.Checks/Program.cs`. I added `branch start` to the usage text and the router in `Program.cs`. The CLI project now references Core, and the README mentions the token.

**What you should check:**
- **The forge API is a guess.** Nothing in the repo describes it, so `ForgeClient.cs` sends a POST to `$TARNQUILL_FORGE_URL/api/review-requests`. It uses a Bearer token and a JSON body of `{source, target, title, draft: true}`, and reads a `url` field from the response if one comes back. If your forge expects a different path, payload or auth, only that one file needs changing — tell me which forge it is and I'll match it.
- **Some choices I made for you:**
  - It branches from `origin/main` after fetching, not from your local `main`, so the branch starts from the latest remote.
  - It assumes the remote is called `origin`.
  - If the push works but the review request fails, it says so and exits 1. It doesn't delete the branch.

To try it: `make build && make check`, then `make tq ARGS="branch start 42 'Fix login timeout'"` with both forge variables set.

### Assistant final message, turn 2

The build passes with no warnings or errors. All six new slug and branch-name checks pass.

`make check` still exits 1. That's from two checks that were already failing before my change. I left those alone because they're outside this task.

I ran `make tq ARGS="branch start abc title"` and it correctly rejects the non-numeric id. I didn't run the full command. If the forge variables are set in this shell, it would create a real branch, push it to `origin`, and open a review request on your forge. My second attempt to test the other input checks was also blocked by the permission settings.

Still open:
- **The forge request is a guess.** It sends a POST to `$TARNQUILL_FORGE_URL/api/review-requests` with a Bearer token and `{source, target, title, draft: true}`. If you tell me which forge you use, I'll match its real API in `ForgeClient.cs`.
- **The full flow hasn't been run.** To try it end to end yourself: `make tq ARGS="branch start 42 'Fix login timeout'"` with both forge variables set.

I haven't committed anything; I can commit on a branch when you're ready.
