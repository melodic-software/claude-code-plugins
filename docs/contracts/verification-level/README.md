# Verification level: how much independent checking a skill runs

One setting, `verification`, decides whether a skill's verifier-subagent steps run, and how many.
Each plugin keeps it in its own team file; this page owns what the levels mean. It never touches
CI merge gates: the pull request lanes (`pr-verify`, the review lanes, `ci-status`) run whatever
the level says.

## Keys

In a plugin's team file, `<home>/<plugin>.yaml`, validated by that plugin's schema. `<home>` is
the convention home named by the pointer line, read at the same default-branch commit by
`lib/resolve-convention-home.sh`; with no pointer line, or a declined one, it is
`docs/conventions`. A broken pointer skips the layer.

```yaml
verification: light          # the plugin's level
verification_skills:
  confirm: strict            # one skill's level; beats the plugin's
```

| Level | What an adopting skill does |
|---|---|
| `off` | everything `light` does, and also skips the skill's own real-check steps that its text names as `off`-skippable |
| `light` | skips the verifier dispatch and writes `verification: skipped (light)` where the verdict would go; it never checks inline in its place |
| `standard` | the default: today's behavior |
| `strict` | always runs the verifier passes that are optional today, such as a carve-out for mechanical, behavior-preserving changes |

Where the verifier is the product (a scan whose findings are the verifier's output), `light`
emits the results labeled unverified instead of skipping them.

## Resolution

`read-verification.sh --plugin <plugin> --skill <skill>`, shipped in each adopting plugin's `lib/`
(source `lib/read-verification.sh`), resolves the level and always prints one line, for example
`verification: light (docs/conventions/implementation.yaml verification at origin/main, commit <sha>)`.

- `verification_skills.<skill>` wins; otherwise `verification`; otherwise `standard`.
- A plugin whose team file sits at a fixed path whatever the convention home passes it with
  `--file <path>`, and the convention home is not read: `bugs`, `testing` and `mutation-testing`
  pass `--file docs/conventions/<plugin>.yaml`. Without `--file` the file is `<home>/<plugin>.yaml`.
- **Team layer only, read from the default branch.** Floor direction `team-only`
  ([config-cascade](../config-cascade/README.md#sanctioned-exception-class-policy-floor-precedence-inversion)):
  the file is read at `origin/<default>` after a fetch, never the working tree, so a branch cannot
  lower its own level. There is no user option and no personal override. When the working tree's
  copy gives another level, a second line names both copies.
- The root rule of `lib/config-root.sh classify` comes first: a `$HOME` or non-repository root
  skips the layer. So do no `origin`, a default branch name outside letters, digits, `.`, `_`, `/`
  and `-` (or one with a leading `-` or `..`), and an unfetched default branch. Each skip resolves
  `standard` with its reason.
- An invalid value, at either key, is named and resolves `standard`, as does a file that does not
  parse. A failed fetch reads the last fetched copy and says it may be stale.

## Interactions with other settings

- **`proof_level`** (verification plugin, stricter wins) is unchanged: `off` never drops evidence a
  resolved `live` or `strict` proof level requires.
- **`verify_mechanical_phases`** (implementation plugin, floor `true`): `true` keeps the phase
  verifier on every phase under `light` and `off`. `strict` implies `true`.
- **`pre_ready`** (source-control) decides whether the ready flow's verify step runs;
  `verification` decides only what happens inside it.
- **The PR-prep gate.** When PR prep calls `/verification:confirm`, a `NOT VERIFIED` whose only
  cause is `verification: skipped (<level>)`, from a level the default branch set, does not block
  PR creation: the report names it and the PR body carries the skipped line. A level that turns
  verification down never becomes a new blocker. Any other `NOT VERIFIED` cause still blocks, and
  Stage 1's mechanical checks still run and gate under `light` and, in `/verification:confirm`,
  under `off`.

## Exempt skills

A skill that is itself the independent check when invoked does not read the level:
`/planning:audit-answers`, `/performance:verify`, `/discipline:scrutinize-dont-coast`,
`/review:quality-gate`, `/review:fanout`, `/planning:devils-advocate` and
`/review:security-review`.

## Adopters

| Skill | Steps the level governs |
|---|---|
| `/verification:confirm` | the fresh-context verifier for the Stage 2 verdict ("Independence of the verdict") |
| `/implementation:implement-dispatch` | the phase verifier and the post-phase source commit verifier (Gates, Phase boundaries) |
| `/discovery:research`, `/discovery:explore`, `/discovery:trace-intent` | the sibling verifier (parent contract, "The sibling verifier, stated once"); `strict` widens research's grading to every row and claim |
| `/discipline:do-your-research`, `/discipline:recheck-against-upstream`, `/discipline:sweep-all` | the fresh-context confirmation of a clean audit on load-bearing work (shared method, step 2), the fresh-context re-derivation (step 3) and the fan-out tiers' dispatch; `strict` takes do-your-research's fan-out tier at `full` depth |
| `/education:quiz-me` | the fresh-context answer-key pass |
| `/planning:plan` | the plan-reviewer dispatch in Step 3 |
| `/session-flow:orchestrate`, `/session-flow:workflow`, `/session-flow:retro` | imperative 3's verifier in a primed session; the fresh-context reviewer in pre-PR step 2, without which Stage 10 is not done; retro's single-pass analysis and scoring under `retro_lenses: 1` |
| `/harness-config:audit-automation-gaps` | the fresh-context refusal gate (2.3), whose verdicts `light` lists as `unverified`, and the Phase 4 step 6 reviewer |
| `/harness-config:audit-instructions` | the Phase C verifiers (per lane, B2 and I33) |
| `/harness-config:audit-pass` | the Phase 5 apply-verify dispatch and the Phase 6 main-session verification |
| `/harness-config:audit-prompting-postures` | the Phase D verifier, on proposals and on verdicts |
| `/bugs:scan` | the Step 4 gate, the product: `light` reports candidates as `unverified` |
| `/mutation-testing:audit` | the Phase 4 triage, the product: `light` reports survivors as unclassified |
| `/testing:cleanup` | the Cannot-fail-only mode's step 2 skeptic: `light` clears no row, so that mode deletes nothing |
| `/debugging:debug` | the fresh-context outcome verifier when no outcome-verification capability is used |
| `/implementation:implement` | the fresh-context verifier at each phase boundary (item 1 of the ritual) |
| `/docs-hygiene:compress` | the semantic-diff subagent and its revert pass (Hard rules); `compare` is not governed |
| `/docs-hygiene:audit-derivability` | the empirical spot-test and the keep-sample (Classification method) |
| `/docs-hygiene:audit-noise` | the fresh-context verification pass over the merged verdicts |
| `/code-tidying:batch-simplify` | the per-group refutation verifier (Phase 6, "The verification level") |
| `/ai-slop:audit` | the fix flow's semantic-diff subagent |
| `/attribution:audit` | the review pass, the refutation pass, and the fix flow's semantic-diff subagent; not the judges |
| `/explainer-video:produce` | the step 7 fresh-context frame judge on the delivery render: `light` reports the frames as not independently judged |
| `/knowledge:video-digest` | the 9.4 vision fidelity spot-check: `light` reports the slice structural complete only |
| `/event-storming:simulation` | the fresh-context rubric scorer ("How to Run an Evaluation", step 3), the product: `light` leaves every criterion `unscored` |
