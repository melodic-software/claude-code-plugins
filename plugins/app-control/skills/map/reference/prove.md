# Calling drive and proving

Read before step 2 of `create` and again before step 5. Map never drives the app itself: every
launch, step and capture goes through `/app-control:drive`, invoked through the Skill tool.

## Sign-in comes first

This rule overrides every other rule on this page, "fix the files and run again" included.

- Any failure at a sign-in step is a failed sign-in: a rejected password, a timeout, an unset
  credential variable, a page that never loaded, a non-zero exit from the CLI's `sign-in`.
- The scope is one attempt per account per create run, across every drive call in it: step 2's
  check and step 5's proof alike. Only committed config allows more for an account.
- A failed sign-in stops proving. That account is not tried again in this run and no other
  account takes its place; the outcome is unproven, with drive's evidence for that step.
- The count lives in this run only. Write no file to keep it.

## The drive calls

Each drive run gets its own new temporary directory outside the checkout, and every call in that
run passes the app slug and that same `--out <dir>`:

1. Step 2, the start check: `/app-control:drive <slug> --out <dir>` with no feature (launch and
   ready), then `/app-control:drive cleanup <slug> --out <dir>`.
2. Step 5, the proof: `/app-control:drive <slug> <feature> --out <dir>`, then
   `/app-control:drive capture --kind <kind> <slug> --out <dir>` for one artifact, then
   `/app-control:drive cleanup <slug> --out <dir>`.

Step 2's report must carry `No control skill: drive used <fallback>.` or name
`.claude/skills/control-<slug>` as its control skill. Any other control skill means drive ran
another app's skill: stop, write nothing, and name that skill. Step 5's report must name
`.claude/skills/control-<slug>`.

## Proving

- A step that fails because the control skill is wrong (a handle, a route, a precondition): fix
  the files and run step 5 again, once. The rerun stops before any sign-in step for an account that
  already submitted an attempt in this run. A second failure leaves the skill written but unproven.
- A send to anyone not on the recipient allowlist is refused by the CLI's send command (exit 4):
  the run stops at the form and never presses send.
- Create commits nothing, so the CLI reads empty committed defaults and refuses every send,
  extra sign-in attempt and write step. Report those steps as unproven until `config/defaults.json`
  is committed; never loosen the CLI to prove them.
- A healthy app that still fails: written but unproven, with drive's evidence. Never call it done.
- A tool the hub names cannot run on this host: `blocked: driver unavailable`, with drive's report.
  Do not edit the hub or switch tools.

## Checks after the proof

- **Evidence.** Every evidence path in drive's step 5 report exists in its run directory and is not
  empty. A missing or empty one means unproven.
- **No orphan.** For each launch record drive wrote (step 2 and step 5), read the pid's start time
  and command line bytes from the process table and hash the bytes as drive's launch record does. A
  process whose pid, start time and hash all equal the record is one this run started and left
  alive: report it and do not call the skill proven. A pid that is gone, or whose start time or
  hash differs, is not ours; leave it alone. Never look a process up by name (`pgrep`, `pidof`,
  `ps` filtered by name). When the process table cannot be read, say the check did not run.

When the proof ran against a stand-in (a local identity stub, a seeded database, a mail catcher),
name each thing the stand-in did that the target will not, and mark those steps unverified against
the target.
