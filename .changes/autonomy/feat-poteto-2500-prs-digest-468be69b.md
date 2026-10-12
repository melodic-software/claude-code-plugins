---
bump: minor
---

### Added

- **A `feature-map-upkeep` routine class.** `reference/routines.md` lists it under Code quality / knowledge with status `join: proven recurring manual pattern`, and its Class parameters bullet sets isolation by driver, the cloud setup note and the cadence. No leaf under `routines/` is written until a consumer records a manual run.
- **The eng-metrics digest reports trust inputs.** A `## Trust inputs` section in `reference/routines/eng-metrics-digest.md` names the inputs the work-class suggested default predicates use (autonomous completions, deterministic-gate pass rate, human-reverted merges, demotion events, missed-blocking AI-review findings) by pointer to their owner, and the output contract says the narrative includes them. The digest reports them and decides no promotion.
- **A GitHub label kick for the trigger.** `skills/setup/templates/trigger-adapters.md` gains a kick with no enqueue for the autonomous-eligible label (`on: issues` type `labeled`). Only a trusted human's label kicks: the event's `sender` is a `User` whose repository permission is `admin` or `write`, read through the permissions API, never from issue text; a bot, App or untrusted label does nothing. The kick fires a `cloud-routine` drain through the routine's `/fire` trigger only when the `execution_target` for `work-items:work-loop` is `cloud-routine` and the execution-target convention admits that stage to cloud hosts, which it does not today. For a `local-worktree` or `local-background` target the job does nothing and the scheduled drain picks the item up; for `cloud-session`, `cloud-project` or a refused `cloud-routine` the job does nothing and the scheduled drain also skips the lane, so the item waits until the target is local. An App acting through a write user's user access token labels as that user and passes the check; the App exclusion holds for installation tokens only. No workflow ships in this repository.

### Changed

- **The label kick's notes say a bot-applied label leaves the drain idle.** `skills/setup/templates/trigger-adapters.md` adds a note that a label an App applies through its installation token carries the App's `[bot]` login, which the drain refuses, so an App-run triage lane never makes an item admissible; the role and `work-class:` labels must come from a user with `write` or higher.
- **The label kick's notes say the drain now checks the labeler.** `skills/setup/templates/trigger-adapters.md` no longer leaves a triage user's label to the drain as an open question: `/work-items:work-loop` admits an item only when whoever last applied its role and `work-class:` labels holds `write` or higher.
- **`reference/trigger-dispatch.md` points host choice at the execution-target convention.** "Executor surface classes" says which host runs each local-lane stage is set by `docs/conventions/execution-target/`, separate from `executor_class`, and changes no merge policy.
