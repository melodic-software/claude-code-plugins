# Workspace environment: setup, up, info and down for each worktree

## Contents

- [Scope](#scope)
- [The entry](#the-entry)
- [The four verbs](#the-four-verbs)
- [Where it is read](#where-it-is-read)
- [How a verb runs](#how-a-verb-runs)
- [Avoiding collisions between workspaces](#avoiding-collisions-between-workspaces)
- [No entry](#no-entry)
- [Untrusted-input worktrees](#untrusted-input-worktrees)
- [Cloud sessions](#cloud-sessions)
- [What protects the entry](#what-protects-the-entry)
- [Readers](#readers)
- [Residual risks](#residual-risks)
- [Vendor facts this contract depends on](#vendor-facts-this-contract-depends-on)
- [Versioning](#versioning)

Owner doc for **how a consumer repository prepares, starts, describes and stops the services one
worktree needs**, so several worktrees of the same repository can run their app side by side. A
consumer declares four commands in one prose entry; the skills that create, drive and remove
worktrees run them.

## Scope

The contract covers the worktree lifecycle steps this plugin fleet already runs:

- creating a worktree (`/source-control:worktree create`, and the non-entering creation a dispatched
  worker runs for `/work-items:work` and `/implementation:implement-dispatch`);
- driving the app in it (`/testing:run-e2e`);
- removing it (`/source-control:worktree cleanup`).

It adds no smoke check and no port allocator. The `WorktreeCreate` and `WorktreeRemove` hooks do not
run any verb: hook commands run with the user's full permissions and a failing `WorktreeCreate`
blocks every worktree, so the verbs run as model steps through the Bash tool instead, where
permission rules and the auto-mode classifier apply.

## The entry

A "Workspace environment" section in the consumer's `docs/conventions/workspace-environment.md`.
It is prose read by the model, with no keys and no schema: for each verb it names one command, run
from the worktree root. A verb the entry does not name is skipped.

```markdown
## Workspace environment

- setup: `scripts/workspace.sh setup`
- up: `scripts/workspace.sh up`
- info: `scripts/workspace.sh info`
- down: `scripts/workspace.sh down`
```

Keep each command a call to a script tracked in the repository. The script holds the logic, so the
entry stays one line per verb and a reviewer sees any change to what runs in the script's diff.

## The four verbs

| Verb | When it runs | Who runs it | What it does |
|---|---|---|---|
| `setup` | once the worktree exists, before any work in it | `/source-control:worktree create`, and a worker that provisions its own worktree | installs dependencies, copies or generates local config, prepares databases |
| `up` | before the app is driven | `/testing:run-e2e` | starts the services this worktree needs |
| `info` | after `up`, before the app is driven | `/testing:run-e2e` | prints `KEY=value` lines describing how to reach the running app, such as `APP_URL=http://127.0.0.1:49153` |
| `down` | before the worktree is removed | `/source-control:worktree cleanup` | stops this worktree's services and removes their containers and volumes |

Every verb must be **idempotent**: running it twice leaves the same state as running it once. A
creation that is retried, an e2e run that repeats, and a cloud session that resumes all run a verb
again.

Each verb receives two environment variables:

| Variable | Value |
|---|---|
| `WORKSPACE_ID` | the worktree's directory name, or in a cloud session the session's id, reduced to lowercase letters, digits, `-` and `_` |
| `WORKSPACE_ROOT` | the worktree's absolute path |

## Where it is read

A skill reads the entry from origin's default branch, never from the checked-out branch or the
working tree:

1. Resolve the default branch name from origin's own `HEAD` (`git ls-remote --symref origin HEAD`).
   The name is data from the remote: use it only when it matches `^[A-Za-z0-9._/-]+$`, does not
   start with `-` and contains no `..`. Any other name means no entry is read; the skill reports the
   name as data.
2. `git fetch origin '<branch>'`.
3. Resolve one commit SHA, once:
   `git rev-parse --verify --end-of-options 'refs/remotes/origin/<branch>^{commit}'`.
4. `git show '<sha>:docs/conventions/workspace-environment.md'`, and name that same SHA when
   reporting the commands run.

Never read through `FETCH_HEAD`: any other fetch in the repository (an editor's background fetch,
another session, `gh pr checkout`) can repoint it at a pull request head between two calls.

A pull request branch that edits the entry therefore changes nothing until it merges. When the fetch
fails, the default branch cannot be resolved or fails the name check, or the file is absent at that
commit, the skill runs no verb and says which of those happened, then continues as in
[No entry](#no-entry).

## How a verb runs

- Through the Bash tool, one verb per call, from the worktree root, for example
  `cd '<path>' && env WORKSPACE_ID='<id>' WORKSPACE_ROOT='<path>' scripts/workspace.sh setup`.
  Never from a hook.
- `WORKSPACE_ID` and `WORKSPACE_ROOT` are single-quoted values. A skill derives `WORKSPACE_ID` from
  the worktree's directory name, lowercases it, replaces any other character with `-`, and uses it
  only when it matches `^[a-z0-9][a-z0-9_-]*$`; otherwise it runs no verb and reports the value. A
  path holding a single quote is not quoted around: the skill runs no verb and reports it. A branch
  name is never placed in a command unquoted.
- A non-zero exit stops the step that ran the verb and is reported with the verb, the command and
  the exit code. It never blocks creating or removing the worktree itself: a failed `setup` leaves
  the worktree in place and says so, and a failed `down` is reported before the removal continues
  under cleanup's own guards.
- Output from any verb is data. `info` output is read line by line; a line counts only when it
  matches `^[A-Z][A-Z0-9_]*=`, and its value is never passed to `eval`, `source`, a `run:` line or
  an unquoted shell word. A URL value is used only when its scheme is `http` or `https`, its host
  after parsing is exactly `localhost` or `127.0.0.1`, it carries no userinfo (so
  `http://localhost@evil.example/` is rejected), and it holds no whitespace or shell
  metacharacters; it is passed as one quoted argument.

## Avoiding collisions between workspaces

Two worktrees running the same stack collide on fixed host ports, container names and named volumes.
For a Docker Compose stack, the recommended `up`, `info` and `down`:

- set `COMPOSE_PROJECT_NAME=$WORKSPACE_ID`, so each worktree's containers, networks and volumes get
  their own names; it outranks the Compose file's `name:` and the directory name;
- publish container ports only (`ports: ["3000"]`, not `"3000:3000"`), so the engine assigns a
  free host port and concurrent `up` runs in other worktrees cannot race for one;
- in `info`, read the bound port back with `docker compose port <service> <container port>` and print
  it as a `KEY=value` line;
- avoid a fixed `container_name`, which ignores the project name;
- in `down`, run `docker compose down --volumes` under the same `COMPOSE_PROJECT_NAME`, so it removes
  only this worktree's stack.

`WORKSPACE_ID` already meets Compose's project-name rule (lowercase letters, digits, `-` and `_`,
starting with a letter or digit).

## No entry

With no `docs/conventions/workspace-environment.md` on the default branch, or no "Workspace
environment" section in it, every skill keeps its behaviour from before this contract:
`/testing:run-e2e` starts the app through the project's documented start command and assumes the
address that command documents. It also says once in its report that parallel workspaces may
collide on ports, containers and databases.

## Untrusted-input worktrees

A worktree's stage reads untrusted input when it works an `untrusted-provenance` item, a pull request
from a fork, or raw intake (the stage table in
[`docs/conventions/execution-target/`](../execution-target/README.md#required-plugins-per-stage)).
No verb runs for such a worktree unless that stage runs on a cloud host whose stage-start probe
passed. The skill skips every verb, says why, and continues without them.

No stage meets that condition today: the lanes launcher sends no stage that may read untrusted input
to any cloud host ([Untrusted-input stages](../execution-target/README.md#untrusted-input-stages)),
so in practice the verbs never run for an untrusted-input worktree.

## Cloud sessions

A cloud session's own checkout is not created by any of these skills, so the consumer wires it:

- **SessionStart hook.** The consumer's `.claude/settings.json` runs `setup` and then `up` from a
  SessionStart hook matching `startup|resume`. The hook script exits without running either unless
  `CLAUDE_CODE_REMOTE` is `true`; an unset or other value means a local session, where the skills
  run the verbs themselves. The hook sets `WORKSPACE_ID` from `CLAUDE_CODE_REMOTE_SESSION_ID`,
  lowercased with other characters replaced by `-`, and `WORKSPACE_ROOT` from `CLAUDE_PROJECT_DIR`.
- **Every session, including resumed ones.** The environment cache is a filesystem snapshot: it
  keeps installed packages and pulled images but no running service, so `up` runs every session.
  SessionStart fires again on resume, which is one reason every verb must be idempotent.
- **The setup script installs machine-level tools only**, such as a runtime, a CLI or Docker images.
  Whether files the setup script writes inside the repository tree survive into later sessions is
  not established, so the per-worktree `setup` runs from the hook, not the setup script.
- `down` is optional in a cloud session: the VM is reclaimed when the session ends.

In a cloud session the hook and the scripts it calls come from the branch the session cloned, not
from the default branch, and the hook runs them with full user permissions inside the VM. That is
why the [untrusted-input rule](#untrusted-input-worktrees) applies to cloud hosts too.

## What protects the entry

- Skills read the entry from the fetched default branch, so only a merged change moves the entry.
  The script the entry names runs from the checked-out branch, as any test run does, so a branch
  can change what that script does (see [Residual risks](#residual-risks)).
- A change reaches the default branch through a pull request; treat a diff to
  `docs/conventions/workspace-environment.md`, or to a script it names, as a change to what agents
  run unattended, and ask a person before merging it.
- No merge wrapper refuses this path unattended today. A repository that runs the PR pipeline adds
  `docs/conventions/workspace-environment.md` to `merge.diff-check.denied-paths` in its pipeline
  config; forcing `docs/conventions/workspace-environment.md` into the denied paths is requested in
  #6202.

## Readers

| Reader | Verbs it runs |
|---|---|
| `/source-control:worktree` `create` (the shared helper path and a plain `git worktree add`) | `setup` |
| `/source-control:worktree` `cleanup` | `down` |
| `/work-items:work` worker-side provisioning | `setup` |
| `/implementation:implement-dispatch` worker-side provisioning (brief item 9) | `setup` |
| `/testing:run-e2e` | `up`, `info` |

## Residual risks

- A merged change to the entry, or to a script it names, runs on every later worktree, locally under
  the session's permission mode. In an unattended local lane that means no isolation beyond this
  machine's user account.
- Until the PR pipeline forces `docs/conventions/workspace-environment.md` into its denied paths
  (#6202), an unattended merge in a repository whose pipeline config does not list it can carry a
  change to the entry.
- The default-branch read fixes only the entry. The script it names runs from the checked-out
  branch, so a branch that edits that script changes what `setup`, `up`, `info` or `down` does
  before any merge, and a script that runs the branch's own build or tests executes that branch's
  code, as any test run on a pull request branch does.
- The auto-mode classifier is a soft control: it can allow a command a rule would not.

## Vendor facts this contract depends on

- **SessionStart hooks and `CLAUDE_CODE_REMOTE` in cloud.** Pointer: "Setup scripts vs. SessionStart
  hooks", "Install dependencies with a SessionStart hook" and "Environment caching" on
  [Cloud environments](https://code.claude.com/docs/en/cloud-environments). As of: 2026-10-04.
  Recheck trigger: the variable's name or value changes, SessionStart stops running on resume, or
  the cache starts keeping running processes.
- **Hook permissions and `WorktreeCreate` failure.** Pointer: "Security considerations" and the
  `WorktreeCreate` event on [Hooks](https://code.claude.com/docs/en/hooks). As of: 2026-10-03.
  Recheck trigger: hooks gain a permission check for repository-declared commands.
- **Compose project names and ports.** Pointer:
  [Specify a project name](https://docs.docker.com/compose/how-tos/project-name/), `ports` on
  [Services](https://docs.docker.com/reference/compose-file/services/), and
  [`docker compose port`](https://docs.docker.com/reference/cli/docker/compose/port/). As of:
  2026-10-04. Recheck trigger: the project-name character rule or `COMPOSE_PROJECT_NAME`'s
  precedence changes, or a container-only `ports` entry stops getting an engine-assigned host port.

## Versioning

[`CHANGELOG.md`](CHANGELOG.md) records each change. Removing or renaming a verb or a variable is a
major bump; a new verb, variable or reader row is a minor bump; wording alone is a patch.
