### Assistant final message, turn 1

I've added `tq branch start <id> <title>`. It builds with no warnings and the dry run works, but I haven't done a real run, and the forge API call is a guess you need to check.

**Check the forge API first.** Nothing in the repo describes the forge's API, so I assumed `POST {TARNQUILL_FORGE_URL}/api/review-requests` with a Bearer token and a JSON body of `sourceBranch`, `targetBranch`, `title`, `description` and `draft: true`. The link to the new review request is read from a `url` field in the reply, if there is one. All of that is in one place, `src/Tarnquill.Cli/Infrastructure/ForgeClient.cs`; please correct it to match your forge.

**What the command does:**
1. Checks the id is a number and the title has at least one letter or digit. Bad input exits with 2.
2. Builds the branch name `work/<id>-<slug>`. The slug is lowercase ASCII with accents removed, cut to 40 characters at a word break. Example: `work/42-fix-login-timeout`.
3. Stops if that branch already exists locally.
4. Checks that `TARNQUILL_FORGE_URL` (the forge address the README already uses) and `TARNQUILL_FORGE_TOKEN` are set. Missing settings exit with 1.
5. Fetches `origin main`, creates the new branch from `origin/main` and switches to it, then pushes it.
6. Opens the draft review request, titled `#<id> <title>`.

It follows the CLI rules in `AGENTS.md`: `--help`, exit codes 0/1/2, `--json` and `--dry-run`. Git runs through `ProcessRunner.Run`. The token is only read from the environment: `--token` or `--forge-token` is rejected with a pointer to the variable, and the value after `=` in an unknown option is never printed.

If a step fails partway, the error says what state things are in, for example "branch was pushed; open the review request manually".

**Files:**
- New: `src/Tarnquill.Core/BranchNames.cs` (the slug logic, kept in Core so it can be tested), `src/Tarnquill.Cli/Commands/BranchStartCommand.cs` and `ForgeClient.cs`.
- Changed: `Program.cs` (wiring and usage text), the CLI `.csproj` (now references Core), the checks project (slug checks) and `AGENTS.md` (added to the tools list).

**Testing:**
- `make build` succeeds with no warnings and the 6 new slug checks pass.
- A `--dry-run --json` run printed the expected branch name and steps, and warned that `TARNQUILL_FORGE_URL` isn't set.
- I wasn't allowed to run the other paths: a real run (no forge here), bad input and the `--token` rejection.
- `make check` still fails on 2 checks that were already failing: `Paging.PageCount` returns `total / pageSize + 1`, which is wrong when `total` divides evenly (10, 5) and for (0, 5). I left that alone since it's unrelated.

Nothing is committed yet.

### Assistant final message, turn 2

I committed the work as `9eb80d7` on a new branch, `feat/branch-start`, made from `main`. The commit has all 7 changed or new files and the working tree is clean.

I used plain `git commit` rather than `tq commit`, because `tq commit` only asks for a type and a one-line message, so it can't add a commit body or the co-author line.

Nothing has been pushed. Before you push or open a review request, please correct the forge endpoint and payload in `ForgeClient.cs` to match your forge's API.
