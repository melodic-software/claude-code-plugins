# Execution target: sending an item's build to a cloud session

The repository's execution-target policy can send an admitted item's build to a Claude cloud
session instead of this machine. The contract is `docs/conventions/execution-target/README.md` in
this plugin's marketplace repository (the setting, its resolution order, the cloud launch rule, the
stage-start probe and the untrusted-input guard); this file holds only what the work loop does with
it.

## When it runs

In step 4, once per admitted item, before that item's `/work-items:work` invocation. Skip it, and
run the item locally, when the bound provider is not `github`: a cloud session clones from GitHub.

## The call

From the loop's checkout:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/work-loop/scripts/cloud-dispatch.sh" --item <number> --class <label> --launch
```

`<number>` is the item's issue number. `<label>` is the class the admission gate gave the item, as
the contract's label: C1 `read-only`, C2 `mechanical`, C3 `scoped`, C4 `structural`, C5
`untrusted-provenance`.

The script owns every deterministic step: it fetches origin's default branch and reads
`docs/conventions/execution-target.yaml` from that commit, resolves `skill.work-items.work`, then
`class.<label>`, then `default`, then `local-worktree`, applies the untrusted-input guard and the
cloud launch rule (github.com origin, no fallback marker on the item, a Claude GitHub App
installation covering the repository, a clean linked worktree at the fetched commit), writes the
cloud brief and runs `claude --cloud` from that worktree. It prints one JSON object; act on its
`dispatch` field and never write a cloud brief by hand. The brief carries no item text: the cloud
session reads the item through the tracker, as data.

## What each result means

| `dispatch` | Do this |
|---|---|
| `local` | Invoke `/work-items:work` for the item as step 4 describes. `reason` says why (the resolved value, a refused launch, the fallback marker); put it in the cycle report. |
| `cloud` | Do not invoke `/work-items:work` locally: the cloud session runs it. Append `{"item":<number>,"session_url":<session_url>,"sha":"<sha>","at":"<UTC ISO-8601>"}` to `cloud_dispatches` in the durable loop state, and report `cloud: #<item> (<session_url or "session URL not printed">, policy <sha> via <key>)`. |
| `escalate` | The policy sent an item that may hold untrusted input to a cloud host. Run it nowhere: step 5 escalates it as `kind=escalated`, and the one-line question says the execution target is `cloud-session` for an item of class `<label>` and asks the operator to change the policy or work the item by hand. |

Only `cloud-session` dispatches per item. `local-background`, `cloud-routine` and `cloud-project`
resolve to the local run, and the `reason` says so.

## In flight

Each `cloud_dispatches` entry is an item in flight on a cloud host:

- The admission gate drops a frontier candidate that has an entry, the same as one with an open
  closing PR.
- Each entry holds one slot of the adaptive item cap, so a cycle starts at most `item_cap` minus
  the number of entries (never below zero) items.
- An entry leaves the list at the first cycle where one of these holds:
  1. The adapter's "Open linked PRs" operation finds an open closing PR for the item. Count the item
     **clean**; the in-flight precondition covers it from then on.
  2. The item carries the marker comment `<!-- execution-target:fallback v1 -->` (the cloud
     session's probe found a gap). The item runs locally from the next cycle on, and the script
     keeps it local while the marker stands. A fallback changes neither streak nor cap.
  3. The item has no open closing PR and no live seam lease, and the binding's lease TTL
     (`config.lease_ttl_hours`) has passed since `at`. Post the fallback marker comment on the
     item yourself, with the reason "no pull request or live claim within the lease TTL", count the
     item **dirty**, and let it run locally from the next cycle on.

A cycle that launches a cloud session has made progress for the no-progress detector. An item
waiting in `cloud_dispatches` is not actionable work in view, as with an open closing PR.

## What the cloud session does

The brief opens with the contract's stage-start probe for `work-items:work`, then runs
`/work-items:work <number>` on its autonomous invocation path, which claims the item, builds it and
opens a draft pull request. The probe posts one comment on the item whose first line is
`<!-- execution-target:probe v1 -->`, listing the session's permission mode, whether connector
tools are present and whether egress outside the Trusted allowlist fails; the lane's telemetry
comment has one writer, so the session never edits it. On a gap the same comment carries the
fallback marker and the session claims nothing. The session never merges and never deletes a
branch.

## Gotchas

- `claude --cloud` prints no documented session URL for a new session, so `session_url` can be
  `null`; the item's probe comment and the claude.ai session list still identify the session.
- The cloud session runs with the account's connectors and the environment's network level; the
  contract's "Residual risks" section lists what that leaves open. That is why no item that may
  hold untrusted input is sent there.
