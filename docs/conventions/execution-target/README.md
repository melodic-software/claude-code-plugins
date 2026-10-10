# Execution target: which host runs each local-lane stage

## Contents

- [Scope](#scope)
- [The file](#the-file)
- [Values](#values)
- [Resolution](#resolution)
- [Where it is read](#where-it-is-read)
- [What protects the file](#what-protects-the-file)
- [Cloud launch rule](#cloud-launch-rule)
- [Stage-start probe and fallback](#stage-start-probe-and-fallback)
- [Untrusted-input stages](#untrusted-input-stages)
- [Required plugins per stage](#required-plugins-per-stage)
- [Readers](#readers)
- [Residual risks](#residual-risks)
- [Vendor facts this contract depends on](#vendor-facts-this-contract-depends-on)
- [Versioning](#versioning)

Owner doc for **where a consumer repository's local-lane stages run**: on this machine (the default),
in a local background session, or on a Claude cloud host. One setting, `execution_target`, per stage,
held in one YAML file the repository owner changes by pull request.

## Scope

`execution_target` places the stages a local lane runs: pre-ready build work (`/work-items:work`),
the work loop (`/work-items:work-loop`), local triage (`/work-items:triage`) and the babysit loop
(`/source-control:babysit-loop`, which runs `/source-control:babysit-prs`). In a repository that runs
the PR pipeline's lanes, post-ready work is placed by the pipeline config
([`docs/conventions/pr-pipeline/`](../pr-pipeline/README.md)), not by this file. Merge authority is
not part of this setting and does not change with the host.

## The file

`docs/conventions/execution-target.yaml` in the consumer repository, validated by
[`execution-target.schema.json`](execution-target.schema.json) beside this README
(ADR [0060](../../adr/0060-home-plugin-customization-in-docs-conventions-yaml.md) Decisions 1, 5
and 6). It is a policy floor: it has a team layer only, and no plugin declares a `userConfig` option
for it, so no per-user or local overlay can move a stage.

```yaml
default: local-worktree
class:
  untrusted-provenance: cloud-session
skill:
  work-items:
    work-loop: local-background
  source-control:
    babysit-loop: local-worktree
```

| Key | Read as | Meaning |
|---|---|---|
| `default` | `default` | Host for any stage no narrower key names. |
| `class:` map, keyed by work-class label | `class.<label>`, e.g. `class.untrusted-provenance` | Host for items of that class. Labels: `read-only`, `mechanical`, `scoped`, `structural`, `untrusted-provenance`. |
| `skill:` map, keyed by plugin, then skill | `skill.<plugin>.<skill>`, e.g. `skill.work-items.work-loop` | Host for one stage skill. |

Readers use the shared reader `lib/parse-concern-value.sh` with those dotted keys; each key segment
is `[A-Za-z0-9_-]`, which is why the `skill:` map nests plugin then skill rather than holding a
`<plugin>:<skill>` key.

## Values

| Value | What runs |
|---|---|
| `local-worktree` (default) | Today's local launch: for a lane, `claude --bg -n <name> --permission-mode auto` from the repository root. |
| `local-background` | `claude --bg -n <name> --permission-mode auto` from the lane's own linked worktree. Background sessions are a research preview. |
| `cloud-session` | `claude --cloud "<probe preamble + prompt>"` under the [cloud launch rule](#cloud-launch-rule). For per-PR fix work in the post-PR stage, the vendor's cloud form is `/autofix-pr`, which the operator runs on the PR's branch; the launcher does not run it. |
| `cloud-routine` | A routine the operator creates at claude.ai with the stage's prompt and its own trigger. The launcher prints the setup steps and launches nothing; a stage that may read untrusted input gets no steps and is skipped (see [Untrusted-input stages](#untrusted-input-stages)). It holds no routine token: firing a routine through its API trigger needs a token kept in the consumer's CI secret store, outside this setting. |
| `cloud-project` | A thread in a claude.ai project on the repository. The launcher prints the setup steps and launches nothing; a stage that may read untrusted input gets no steps and is skipped. |

A value outside this table resolves to `local-worktree`, and the reader reports the key and value.

## Resolution

For a stage, the first key that holds a value wins:

1. `skill.<plugin>.<skill>` for the stage skill;
2. `class.<label>` for the item's work class (a per-item reader), or `class.untrusted-provenance` for
   a stage whose input is always untrusted (a lane reader; see
   [Untrusted-input stages](#untrusted-input-stages));
3. `default`;
4. `local-worktree`.

An absent file, a file the shared reader rejects, or a failed fetch resolves every stage to
`local-worktree`, and the reader says why.

## Where it is read

The default branch is the one origin's own `HEAD` names (`git ls-remote --symref origin HEAD`). A
reader reads no policy when origin's `HEAD` cannot be read or disagrees with the local `origin/HEAD`
symref, when a `url.<base>.insteadOf` or `pushInsteadOf` rule in any git config scope rewrites
origin's URL, or when `remote.origin.url` has more than one value. In each case every stage resolves
to `local-worktree` and a `work-items:triage` lane is skipped.

These checks catch a stale or moved symref and the plain forms of a redirected origin. They are not
a boundary against someone who can write the checkout's git config, who can point origin at any
repository; the policy is only as trustworthy as the checkout the launcher runs in.

A reader then runs `git fetch origin <default branch>`, reads the file with
`git show <commit>:docs/conventions/execution-target.yaml` from the fetched commit, and prints that
commit's SHA with the value and the key that supplied it. It never reads the working tree, so an
unmerged or uncommitted edit cannot move a stage.

## What protects the file

- A change reaches the default branch through a pull request, and AGENTS.md-style rules that ask a
  person before merging a change to what agents may do unattended apply to an interactive merge.
- A repository that runs the PR pipeline adds this file to `merge.diff-check.denied-paths` in its
  pipeline config. The pipeline does not force this path today; forcing it is requested in #6202.
- Every reader prints the SHA it read, so a run shows which policy placed it.

No CODEOWNERS rule or ruleset is required: in a single-maintainer repository an author cannot approve
their own pull request, so a code-owner rule would block every change to the file.

## Cloud launch rule

`claude --cloud` runs only when all of these hold; otherwise the stage runs `local-worktree`, except a
stage that may read untrusted input, which is skipped (see [Untrusted-input stages](#untrusted-input-stages)):

- the stage's input is never untrusted (its row below reads "never"); no current local-lane stage
  qualifies, so the lanes launcher sends no lane to `cloud-session` today;
- the launch runs from a clean linked worktree (no uncommitted or untracked changes) checked out at
  the pushed commit the stage needs (the fetched default-branch commit for a lane);
- origin's configured URL is a github.com `owner/repo`, and `gh api user/installations` lists an
  installation of the Claude GitHub App (`claude`) that covers that repository (all repositories of
  its owner, or the repository among the selected ones). The slug comes from origin, the remote
  `claude --cloud` clones from, never from `gh`'s default repository;
- the lane's telemetry can be read: an explicit numeric `telemetry.issue` in that same repository (a
  `telemetry.repo` naming any other repository is refused, and no issue is found by title), so a probe
  fallback can reach the launcher;
- the lane does not request the autonomy lane-stop gate, which cannot be armed in a cloud session.

The App check exists because, without the App, `claude --cloud` uploads a bundle of the local
repository (all its branches, and edits to tracked files not yet committed) instead of cloning from
GitHub.

## Stage-start probe and fallback

A stage on a cloud host runs the probe before anything else. The lanes launcher puts it in front of
the lane prompt; a per-item dispatcher puts it in front of the item brief. The probe:

1. confirms each plugin in the stage's row of [Required plugins per stage](#required-plugins-per-stage)
   is loaded in the session, not only declared;
2. confirms one read from the work-item tracker succeeds;
3. for a stage that merges, confirms the merge wrapper's read-only check passes;
4. records the session's permission mode, whether connector (MCP) tools are present, and whether a
   request to a host outside the Trusted network allowlist fails, under `execution_target_probe` in
   the lane's telemetry state block.

On a gap in steps 1-3 the stage writes `execution_target_fallback: {"reason": ..., "at": ...}` to the
lane's telemetry state block and, for a per-item stage, the marker comment
`<!-- execution-target:fallback v1 -->` on the item; it clears the item's in-flight mark, claims
nothing and exits. A passing probe sets `execution_target_fallback` to `null`.

- **Lane fallback.** The launcher reads the newest `execution_target_fallback` on the lane's telemetry
  issue, counting only comments written by the `gh`-authenticated login or the lane's configured
  `telemetry.author`; a comment from anyone else, `null` included, changes nothing. A value it has
  not yet honored moves exactly one launch to `local-worktree`; the launcher records the value's hash
  in its plugin data directory, and the next launch probes the cloud again.
- **Item fallback.** The dispatcher runs the item `local-worktree` on its next cycle and does not send
  it to the cloud again while the marker stands; the marker stays until the item closes.

Because `claude agents --json` does not list cloud sessions, the launcher records each cloud launch in
its plugin data directory: `start` does not send a second cloud session for a lane while that record
stands, and `restart` sends a new one (the earlier session is archived by hand at claude.ai).

## Untrusted-input stages

A stage reads untrusted input when it triages raw intake, works a pull request from a fork in the
post-PR stage, or works an `untrusted-provenance` item. The guard keys on that input's provenance,
not on the item's work class alone (the autonomy isolation ladder's "Axes" section: input
provenance decides whether the `L3` bar applies,
`plugins/autonomy/reference/guardrails/isolation-ladder.md`):

- **Enforced by the launcher.** The no-connector and denied-egress check has no deterministic form
  yet, so the lanes launcher refuses every cloud host (`cloud-session`, `cloud-routine` and
  `cloud-project`) for every stage whose "Reads untrusted input" column is anything but "never", for
  a lane with no `stage` and for a stage outside the table
  (`lanes.json` is lane-writable, so a missing or unknown stage counts as untrusted). Such a lane is
  skipped, not run locally: the launcher prints an error naming `/work-items:attend-queue` as the
  escalation route and files nothing.
- **Repeated in the probe.** The probe preamble still tells a cloud session to read untrusted input
  only when it finds no connector tools and the step 4 egress request fails, and otherwise to stop
  and leave the item for `/work-items:attend-queue`, as a second line of defense.
- `/work-items:triage` reads raw intake on every run, so the lanes launcher resolves
  `class.untrusted-provenance` for it after its `skill` key, and skips a triage lane whenever the
  policy read is refused (see [Where it is read](#where-it-is-read)).

## Required plugins per stage

Derived from the skills each stage skill invokes on its normal path. A `cloud-routine` stage may carry
only the connectors its row lists; the probe fails on any other.

| Stage | Required plugins | Reads untrusted input | `cloud-routine` connectors |
|---|---|---|---|
| `work-items:work-loop` | work-items, implementation, source-control | when it triages raw intake | none |
| `work-items:work` | work-items, implementation, source-control | when the item is `untrusted-provenance` | none |
| `work-items:triage` | work-items | always | none |
| `source-control:babysit-loop` | source-control, work-items | when a PR comes from a fork | none |
| `source-control:babysit-prs` | source-control | when a PR comes from a fork | none |

The lanes launcher carries a copy of the plugin column (`stage_required_plugins` in
`plugins/harness-ops/skills/lanes/scripts/lane-launcher.sh`); change both together.

## Readers

| Reader | Keys it reads |
|---|---|
| `/harness-ops:lanes` launcher (`start`, `restart`) | `skill.<plugin>.<skill>` for the lane's `stage`, `class.untrusted-provenance` for `work-items:triage`, `default` |

## Residual risks

- A direct push to the default branch, or a merge outside the protected paths above, changes the
  file without a person's review. The printed SHA shows it afterwards; nothing blocks it.
- Anyone who can write the checkout's git config can redirect origin in ways the URL checks above do
  not see, and so choose the policy a launch reads.
- Until the PR pipeline forces this path (#6202), an unattended `pr-merge` in a repository whose
  pipeline config does not list it can carry a change to it.
- The untrusted-input guard is enforced by refusing those stages every cloud host: no `claude
  --cloud` launch and no routine or project setup steps. When a deterministic
  connector and egress check lets the launcher admit them, the guard for them rests on that check and
  on the probe instruction.
- Trusted-input cloud stages run with the account's connectors and the environment's network level;
  an environment at network level All gives full egress. The probe records this posture and does not
  block on it.
- A cloud-to-local fallback runs on this machine, below the `L2` floor the autonomy isolation ladder
  sets for unattended runs ("Unattended floor"), the same as every local lane today. The fallback is
  reported in telemetry and in the launcher's output, never silent.
- No security binding reads a per-host isolation floor (ADR 0038); this setting only places stages.
- How `claude --cloud` picks a branch from a linked worktree on a detached HEAD at the pushed commit is
  not documented; the first live cloud run records it.

## Vendor facts this contract depends on

- **Routine triggers.** Pointer: the "Supported events" table on
  [Routines](https://code.claude.com/docs/en/routines#supported-events) (pull request and release
  events), and its "Connectors" section (every connected connector is included by default and its
  tools run without approval). As of: 2026-10-04. Recheck trigger: the table gains an issues event, or
  the connector default changes. The open conflict is anthropics/claude-code#72290 (an issue-opened
  routine trigger that did not fire, closed as stale); nothing here relies on an issue trigger.
- **Cloud launch and upload.** Pointer:
  [From terminal to cloud](https://code.claude.com/docs/en/claude-code-on-the-web#from-terminal-to-cloud)
  and [Send local repositories without GitHub](https://code.claude.com/docs/en/claude-code-on-the-web#send-local-repositories-without-github).
  As of: 2026-10-04. Recheck trigger: `--cloud` stops uploading a bundle when the App is missing, or
  gains a branch or worktree option.
- **Cloud environments.** Pointer: "What carries over from your setup" and "Network access" on
  [Cloud environments](https://code.claude.com/docs/en/cloud-environments). As of: 2026-10-04.
  Recheck trigger: either table changes.

## Versioning

[`CHANGELOG.md`](CHANGELOG.md) records each change. Removing or renaming a key or value is a major
bump; a new value, key or reader row is a minor bump; wording alone is a patch.
