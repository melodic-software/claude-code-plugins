# proactive-vs-reactive-skills

## Brief

### TLDR

Development-workflow skills load the consumer's standards proactively (at plan/build time) instead of colliding with them reactively at review time. One shared, concern-named standards index — consumed by planning AND review — makes skills build to the criteria they'll be reviewed against.

### Goal

Eliminate the rework loop where `/architect`-planned and `/implement`-built work violates consumer standards (code conventions, engineering philosophy, design-review criteria) that only surface during review. Proactive grounding becomes the DEFAULT behavior of lifecycle skills — no mode fork, no sibling skill variants — with cost governed by existing scale/blast-radius gates and progressive disclosure.

V1 (locked): the `standards` concern contract + a two-consumer pilot.

1. Versioned concern contract at `docs/conventions/standards/` — index schema, layers, precedence, resolution ladder.
2. `planning:architect` gains a proactive standards-loading step (plan formulation grounds in the loaded criteria).
3. `review:quality-gate` `criteria` mode resolves criteria through the SAME index (build/review symmetry).
4. Idempotent setup bootstrap in those two plugins only.

Fleet rollout (implement, design, prototype, testing, …) follows in per-plugin waves after the pilot proves the contract.

### Constraints

- **Repo-agnostic, no baked opinions (C1).** Every default — including the concern folder location — is reconfigurable via re-runnable setup. Only the discovery anchor stays conventional. Plugin never names the user's org, repos, or layout.
- **Default layout (three layers, seam-2 shape):** user-global `~/.claude/standards/` → team-tracked `docs/standards/` → personal gitignored `docs/standards/*.local.md` (setup ships the `.gitignore` line). Team layer deliberately OUTSIDE `.claude/` (verified: `.claude/` writes are specially permission-guarded even under acceptEdits; reads are prompt-free anywhere in the working directory).
- **Policy precedence inversion:** layers are additive; personal layers may ADD or TIGHTEN only; direct conflict → team-tracked wins. Skills state which layer contributed when a personal rule materially shapes output.
- **Progressive disclosure:** root index is a thin routing map (in-scope surfaces + context clues, no content); standards files are SRP-organized (one concern per file); skills pull only sections matching the surfaces the task touches (e.g. C# conventions only when touching C#).
- **Resolution ladder (playbook-adopted):** index present → use it; absent → infer from not-auto-loaded usual suspects (docs folders, ecosystem configs — never re-read auto-loaded CLAUDE.md/.claude/rules) and OFFER to persist; can't infer → ask once; else safe ecosystem default. No silent writes, ever.
- **Setup mode 2:** skills usable immediately with defaults; setup optional, idempotent, re-runnable anytime; setup may offer (never force) reorganizing mixed/spread consumer standards content toward the SRP + index shape.
- **Horizontal decoupling:** no cross-plugin imports. Each consuming plugin carries a synced `reference/` binding copy of the contract (topic-docs/hook-utils precedent); per-plugin idempotent bootstrap — first setup writes the index, later setups validate/offer reconfigure.
- **Anti-waterfall:** grounding depth rides the existing plan-scale/blast-radius gates; trivial work pays near zero. No grounding flag, no `--ungrounded` escape hatch.
- **Process gates:** fresh-docs mandate (WebFetch current plugin docs) before any file change; per-plugin migration gate + plugin-acceptance security review; version bumps + changelog per delivery rules.

### Acceptance criteria

- `docs/conventions/standards/README.md` exists: index schema, three layers, precedence-inversion rule, resolution ladder, versioning — and both pilot plugins carry a synced binding copy.
- `plugins/planning/skills/architect/SKILL.md` carries the proactive standards step; a plan produced for a task touching surface X cites the standards sections loaded for X; grounding depth demonstrably scales with the plan-scale tier (trivial plan → no standards fetch beyond ambient context).
- `plugins/review/skills/quality-gate` `criteria` mode resolves criteria through the same index when present (grep confirms the binding reference, exercise confirms the load).
- Setup in both pilot plugins bootstraps `docs/standards/` idempotently in a clean non-source repo via `--plugin-dir` (run twice → no diff on second run).
- Absent-index fallback: in a repo with no index, the skill infers from repo context and offers persistence — verified by exercise; zero unprompted writes.
- No hardcoded consumer paths (`grep` for absolute paths / org names in changed plugin files → zero hits); `claude plugin validate` passes; both plugins version-bumped with changelog entries.

### Captured assumptions

- File reads need no permission approval anywhere in the working directory, all environments; `.claude/` writes sit on the protected-directory prompt list (both verified against the official permissions doc, 2026-07-17).
- `standards` is the umbrella term (adopted conventions become standards — research-confirmed 2026-07-17); "guidance" rejected as advisory-only connotation.
- Auto-loaded surfaces (consumer `CLAUDE.md`, `.claude/rules`) apply ambiently and are never re-fetched by the grounding step.
- Two consumers (one proactive, one reactive) are sufficient to validate the multi-plugin concern design before fleet rollout.

### Out-of-scope

- Dual proactive/reactive skill variants and mode flags — ruled out (playbook: depth/intensity variants are arguments, never siblings; here not even an argument).
- Meta-setup plugin for shared plugin conventions — deferred; trigger: ≥3 shared concerns AND observed bootstrap drift/nagging across plugins.
- Restructuring the `melodic-software/standards` repo itself ("am I doing the standards repo right") — separate effort, own session.
- Fleet rollout waves beyond the two-plugin pilot — planned after pilot verdict.

### Deferred questions

- Index/contract schema detail (surface taxonomy: ecosystem × layer × stage; file format; root-index shape) → **/design**
- Per-skill step placement inside architect/quality-gate bodies + binding-copy sync mechanics (extend existing sync machinery?) → **/architect**
- Plugin-upgrade migration handling: inside re-runnable setup vs separate action → **/design**
- Wave-2 rollout inventory + inclusion rule (which dev-workflow skills, what order) → **USER-RESERVED** (scope decision at wave time)

## Plan

<!-- /architect fills this section -->
