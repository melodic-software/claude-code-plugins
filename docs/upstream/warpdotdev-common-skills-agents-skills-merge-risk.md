# Upstream source: warpdotdev/common-skills (.agents/skills/merge-risk)

This page records what this repository takes from, adapts, already has, or rejects in
[warpdotdev/common-skills](https://github.com/warpdotdev/common-skills) (MIT). Rows hold our
decisions in our own words; read upstream at each row's link for what it says.

**Last audited upstream state:** `warpdotdev/common-skills@8792394ff1b655e0af451b8fabb68ef0cfcbd208` under `.agents/skills/merge-risk/` (upstream HEAD of `main` when read, 2026-11-03)

**Recheck trigger:** a change, between the pinned commit and upstream HEAD, to a path a row we took
or rejected something from links, a unit removed or added under the scope: re-audit the affected
rows.

The skill credits Matt Pocock's `pr` skill, which [`mattpocock-skills.md`](mattpocock-skills.md)
already records (row `pr`). Our counterpart is `/review:merge-risk`
(`plugins/review/skills/merge-risk/`), which rates merge risk against one rubric
(`reference/rubric.md`) that its rater and its blind checker both read. It replaced the risk-only
action of `/review:explain-change` ([#6943](https://github.com/melodic-software/claude-code-plugins/issues/6943),
[#7024](https://github.com/melodic-software/claude-code-plugins/pull/7024)): explaining a change and
rating its merge risk change for different reasons, so the explainer now consumes the rating
instead of owning it. No merge gate reads its `demote` flag yet; wiring it is open owner question
Q57.

## Attribution table

**Stated**: the upstream gives this problem where the label's link points. **Inference**: we
derived it from the mechanism. Disposition is `take`, `adapt`, `already have` or `reject`, with the
reason.

| Idea (link at the pin) | What it does | Upstream problem, motivation, goal | Our problem | Disposition |
|---|---|---|---|---|
| [Output shape](https://github.com/warpdotdev/common-skills/blob/8792394ff1b655e0af451b8fabb68ef0cfcbd208/.agents/skills/merge-risk/SKILL.md#L10-L19) | One overall verdict line, then one block per category listing what raises its risk, with file links | A reviewer must see at a glance where to look on a PR an agent wrote, so human review is spent on the risky ones. **Stated** ([launch post](https://x.com/BHolmesDev/status/2112653011369807971)) | Deciding which agent PRs need a human; `/review:merge-risk` returns per-area rows plus a JSON result that names the head it rated (`plugins/review/skills/merge-risk/SKILL.md`, step 5) | **already have:** our result is machine-readable and bound to one head, which a comment-only verdict is not |
| [Alignment category](https://github.com/warpdotdev/common-skills/blob/8792394ff1b655e0af451b8fabb68ef0cfcbd208/.agents/skills/merge-risk/SKILL.md#L23) | Grades whether the diff matches its description and source issue, and whether side changes the agent made on the way are written down | An agent makes unrequested side fixes that a reviewer cannot see without reading every line. **Stated** ([samples post](https://x.com/BHolmesDev/status/2112653033507299421)) | pr-verify grades the diff against the linked issue and refuses after an issue-body edit ([`docs/conventions/pr-pipeline/README.md`, "Verifier verdict"](../conventions/pr-pipeline/README.md#verifier-verdict)); spec mode flags extra behavior as `scope-creep` (`plugins/review/skills/quality-gate/context/spec.md:18`). No surface requires an unrequested side change to be named in the PR body | **adapt:** the rubric's alignment area grades against the closing issue, never the PR body, and an unnamed side change raises it to `MEDIUM` (`plugins/review/skills/merge-risk/reference/rubric.md`). Grading against the description is rejected: the agent writes the description after the work ([reply](https://x.com/karanjagtiani04/status/2112668770477224084)) |
| [Impact category](https://github.com/warpdotdev/common-skills/blob/8792394ff1b655e0af451b8fabb68ef0cfcbd208/.agents/skills/merge-risk/SKILL.md#L24-L26) | Rates how far a change reaches, and treats a fixed list of sensitive areas as risky at any diff size | A two-line change to auth or payments outweighs a large cosmetic one. **Inference** | The merge lane's fixed path floor and cost paths (`COST_PATHS` and `HOLD_PATH_CLASSES` in `.github/scripts/pr-merge/merge-holds.mjs`), which this repository switched off as holds by owner decision Q15 (`docs/conventions/pr-pipeline.yaml`, the `merge.diff-check` block and its `path-holds` comment) | **adapt:** the rubric rates a change that widens an automated actor's authority, or touches auth, billing, personal data or infrastructure as code, `HIGH` by judgment, the class the #7024 replay missed on #6205. That is a rating, not a path hold, so Q15 stands; the gate's path floor stays the deterministic list, and a CODEOWNERS-style sensitivity file ([reply](https://x.com/BHolmesDev/status/2112875545788895706)) is rejected as a third list |
| [Verification category](https://github.com/warpdotdev/common-skills/blob/8792394ff1b655e0af451b8fabb68ef0cfcbd208/.agents/skills/merge-risk/SKILL.md#L27-L29) | Requires end-to-end proof for user-facing changes and measurements for performance changes, and asks that untested edge cases be named | Unit tests alone do not show a UI or performance change works. **Stated** ([launch post](https://x.com/BHolmesDev/status/2112653011369807971)) | `ready` keeps a PR in draft when a plan's required screenshots or recording cannot be gathered (`plugins/source-control/skills/pull-request/reference/ready-for-review.md:163-174`); a visual change's Verification section carries before/after media (`reference/create.md:387`); `/verification:confirm` and `/verification:measure` own the evidence | **already have:** our ready flow closes the gap before review rather than reporting it after |
| [Rollback cost category](https://github.com/warpdotdev/common-skills/blob/8792394ff1b655e0af451b8fabb68ef0cfcbd208/.agents/skills/merge-risk/SKILL.md#L30) | Rates how hard the change is to undo once live, using the one-way and two-way door framing | A revert in git does not undo a migration that ran or a message that was sent. **Inference** | The door definitions in `lib/one-way-doors.md` (synced into planning and review); the C4 work class (`plugins/autonomy/reference/guardrails/work-classes.md:33-39`) | **adapt:** the rubric rates any one-way door `HIGH`, so `demote` fires on it alone. The door definition moved to one shared source, `lib/one-way-doors.md`, synced into the planning and review plugins, so design and merge-risk read the same words. That is a veto, as one reply argued and the author accepted ([reply](https://x.com/BHolmesDev/status/2112678515225268314)) |
| [Error detection category](https://github.com/warpdotdev/common-skills/blob/8792394ff1b655e0af451b8fabb68ef0cfcbd208/.agents/skills/merge-risk/SKILL.md#L31) | Checks that a production failure surfaces to someone before users report it, and looks for fallbacks that hide breakage | **Inference**: generated code often catches and discards errors | No review lane checks for swallowed errors; the rubric exists only as a tidy pass (`plugins/code-tidying/skills/tidy-diff/reference/generated-code-residue.md:56-57`) and a contract (`docs/contracts/liveness-assertion/README.md:10`) | **adapt:** the rubric has an error-detection area. It rates the risk only; finding and fixing such code stays with the tidy pass |
| [Verdict scale](https://github.com/warpdotdev/common-skills/blob/8792394ff1b655e0af451b8fabb68ef0cfcbd208/.agents/skills/merge-risk/SKILL.md#L35-L39) | Three grades per category, each mapped to a number | **Inference**: lets categories be combined into one score | Our levels run `LOW` to `CRITICAL` (`reference/rubric.md`) | **reject:** our four labels already cover this, and nothing needs a number |
| [Weighted score](https://github.com/warpdotdev/common-skills/blob/8792394ff1b655e0af451b8fabb68ef0cfcbd208/.agents/skills/merge-risk/SKILL.md#L41-L53) | Combines the category grades with fixed weights into a mean and cuts it into three bands | **Inference**: gives one verdict from five grades | `demote` is set by any `HIGH` or `CRITICAL` label (`SKILL.md`, step 5) | **reject:** a mean lets one HIGH category average down to medium. A reply worked this out for an irreversible payments change ([reply](https://x.com/yomo_dev/status/2112672663168553111)) |
| [Score kept internal](https://github.com/warpdotdev/common-skills/blob/8792394ff1b655e0af451b8fabb68ef0cfcbd208/.agents/skills/merge-risk/SKILL.md#L55) | Hides the arithmetic from the reader | **Inference**: false precision would invite argument over decimals | the rubric says levels are labels, never a computed score | **already have** |
| [Credits](https://github.com/warpdotdev/common-skills/blob/8792394ff1b655e0af451b8fabb68ef0cfcbd208/.agents/skills/merge-risk/SKILL.md#L4-L8) | Names Matt Pocock's `pr` skill as the source | Attribution | Recorded in [`mattpocock-skills.md`](mattpocock-skills.md), row `pr` | **already have** |

## Ideas from the launch thread

These come from replies to the [launch post](https://x.com/BHolmesDev/status/2112653011369807971),
not from a file at the pin, so they are not drift inputs.

| Idea | Our surface | Disposition |
|---|---|---|
| A PR body can carry text that tells the grader to approve ([reply](https://x.com/kurtextrem/status/2112833622893871390)); no mitigation was given | The lanes read the PR body as data (`plugins/review/skills/code-review/SKILL.md:142`, `docs/contracts/untrusted-content/README.md:13-25`); merge-risk marks `area`, `why` and `checker` as data (`SKILL.md`, step 5) | **already have** |
| Bind the verdict to the commit it graded (an x.com reply, since deleted) | `/review:merge-risk` step 4 re-reads the head and diff, and its result names the head; `plugins/verification/scripts/confirm-verdict.sh:11-12` | **already have** |
| A PR that edits the grader's own rules rates high ([reply](https://x.com/wfouaaad/status/2117641184638091709)) | The floor's `trust` and `gate` classes (`HOLD_PATH_CLASSES` rows for `docs/conventions/pr-pipeline.yaml`, `**/.claude/**`, `**/CLAUDE.md`, `merge-holds.mjs` itself, `docs/review/**` and the `pr-review-*` workflows), held off by Q15; `plugins/review/**`, which holds the CI lane skill bodies, is not in the floor | **already have** (gap noted, no change while Q15 stands) |
| Grade the stack as a whole, intermediate states included ([reply](https://x.com/harrisonju/status/2112950775190036673)) | `/work-items:ship` lands an integration branch through one PR (`plugins/work-items/skills/ship/SKILL.md:110-119`); close-out review covers the whole container (`plugins/review/skills/quality-gate/context/close-out.md:15-18`) | **reject:** we do not ship GitHub PR stacks |
| Grade with a model other than the author's ([reply](https://x.com/heyarunb/status/2112806554911297791)) | `plugins/review/agents/lane-verifier.md:5` is `model: inherit`; `/review:fanout` model diversity is opt-in | **open:** owner decision on a different grader model, pending |
| Join each grade to later reverts to measure how often low-risk merges escape ([reply](https://x.com/latent_node/status/2113260969938088300)) | `/work-items:measure-delivery` reports change fail rate with no grade slice (`plugins/work-items/skills/measure-delivery/SKILL.md:3`); the #7024 replay did this by hand once (11 PRs, 0 demotions, 1 missed risk) | **open:** owner decision on joining merge-risk results to reverts, pending |

## License notice

The repository's LICENSE file reads MIT (copyright Denver Technologies, Inc.), and GitHub reports
`MIT`; they agree. No upstream text or code is copied here or into any plugin.

- **Pointer**: <https://github.com/warpdotdev/common-skills/blob/8792394ff1b655e0af451b8fabb68ef0cfcbd208/LICENSE>
- **As of**: 2026-11-03
- **Recheck trigger**: the LICENSE file or GitHub's reported license changes.
