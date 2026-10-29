### Assistant final message, turn 1

I added `tq branch start <id> <title>`, but I couldn't build or run anything: shell access is blocked in this session. So none of it has been compiled or tested, and the forge request is based on a guess about the API.

**Needs confirming first:** nothing in the repo describes the forge API. The draft review request sends `POST {TARNQUILL_FORGE_URL}/api/review-requests` with a Bearer token from `TARNQUILL_FORGE_TOKEN`. The body is `{sourceBranch, targetBranch: "main", title, workItem, draft: true}`, and it reads a `url` from the response. All of that is in `src/Tarnquill.Cli/Infrastructure/ForgeClient.cs`, marked with a TODO. If you tell me the real endpoint, it's a quick change. The command also needs `TARNQUILL_FORGE_URL` to be set, because the README says that's where the forge address comes from.

**What it does:**
1. Checks the arguments: the id must be a number, as `item comment` requires, and the title must contain at least one letter or digit. Bad input exits with code 2.
2. Fails if `work/<id>-<slug>` already exists locally.
3. Checks the forge URL and token before touching git, so a missing token doesn't leave a branch half set up.
4. Fetches `origin main`, fails if the branch already exists on `origin`, creates the branch from `origin/main` and pushes it.
5. Opens the draft review request. If that step fails after the push, the error says the branch was already pushed, so you know only the review request needs retrying.

It follows the repo's CLI conventions: `--help`, exit codes 0/1/2, `--json`, and a `--dry-run` that changes nothing. All git calls go through `ProcessRunner.Run`, and the token is only read from the environment, never from a flag.

The slug is built by `BranchName.Slugify`, which I put in `Tarnquill.Core` so it can be checked. It keeps lowercase ASCII letters and digits, turns everything else into single dashes, and cuts at 40 characters. For example, `Fix login timeout` becomes `work/42-fix-login-timeout`. Because of this, the CLI project now references Core.

**Files:**
- New: `src/Tarnquill.Core/BranchName.cs`, `src/Tarnquill.Cli/Infrastructure/ForgeClient.cs`, `src/Tarnquill.Cli/Commands/BranchStartCommand.cs`
- Changed: `Program.cs` (routing and usage text), `Tarnquill.Cli.csproj`, the checks project (slug checks), `AGENTS.md`, `README.md`

**To verify:** run `make build`, `make check`, and `make tq ARGS="branch start 42 'Fix login timeout' --dry-run"`.

### Assistant final message, turn 2

`make check` now passes all 11 checks.

- **A mistake of mine:** the first run of `make check` also failed one of the slug checks I wrote earlier. I had miscounted the expected value; the code was right. I corrected the check, and that run is the one where everything passed.

**Still not run:** `make check` worked, but the command that also ran `make build` and tried `tq branch start` was blocked. So the CLI project hasn't been compiled and the new command hasn't been run, even in dry-run. To try it:

```sh
make build
make tq ARGS="branch start 42 'Fix login timeout' --dry-run --json"
```

The forge endpoint (`POST {TARNQUILL_FORGE_URL}/api/review-requests`) is still a guess. Send me the real one and I'll update `ForgeClient.cs`.

None of this is committed yet.
