# playground-integration

## Brief

### TLDR

- Ship one thin wrapper plugin (final name deferred, non-colliding with the upstream bare
  `playground` skill) that points to `playground@claude-plugins-official`: install uplift,
  routing, recipes, cloud-session delivery guidance, and neutral limitation notes. It generates
  nothing itself.
- When the upstream skill is present, the wrapper invokes it; when absent, it emits the install
  commands; when invocation is refused, it degrades to guidance.
- Seed two candidate pairs (playground vs `visualization:visualize`, playground vs
  `prototype:explore-directions`) and record human-gated verdicts through the
  audit-native-overlap pipeline; suggest-install lines exist only where a recorded verdict backs
  them.
- A user-run local pilot (upstream document-critique template reviewing this repo's own SKILL.md
  files) gathers real round-trip evidence; its learnings may revise wrapper content.
- No upstream contributions of any kind: findings about the upstream plugin live only in this
  Brief and in verdict-row evidence.

### Goal

A marketplace consumer who wants the playground pattern (interactive single-file HTML explorers
whose output is a prompt pasted back into Claude Code) reaches the maintained first-party
implementation through this marketplace in one step, with working guidance for the cases the
upstream plugin does not cover (cloud/remote sessions, this repo's routing conventions, known
rough edges), and this repo's own visualization and prototyping skills know when a request is
playground-shaped and route accordingly.

### Constraints

- Do not reimplement playground generation: no templates, no generator, no competing skill. The
  wrapper points, uplifts, and routes.
- NEVER file issues or PRs to anthropics/claude-plugins-official for the findings in this topic
  (user directive, 2026-08-31). Findings are recorded here and in verdict evidence only, and any
  user-facing limitation note is phrased neutrally, never as an upstream defect list.
- All native/first-party-overlap verdicts go through the audit-native-overlap pipeline:
  candidate pairs in its canonical-pair seed, human-gated rows in `docs/native-surfaces/records.json`,
  phrasing per `docs/conventions/native-references/README.md`. No ad-hoc baked references.
- Suggest-install lines only where a recorded verdict backs them; rollout-gated bundled surfaces
  are never mentioned when absent (existing house rule, reaffirmed).
- The wrapper plugin's name must not collide with or shadow the upstream bare `playground`
  skill; its category follows `docs/CATALOG-TAXONOMY.md` (read the taxonomy rule before
  assigning).
- House conventions apply: ai-slop prose rules on all new instruction surfaces, no new hooks,
  `scripts/affected-tests.sh --run` gates the change.

### Acceptance criteria

- The wrapper plugin exists in `.claude-plugin/marketplace.json` with a taxonomy-conforming
  category, a README, and one skill; `skill-quality:check` passes on the skill.
- The skill performs a presence check for the upstream `playground` skill; with it installed, a
  playground-shaped request invokes it via the Skill tool; without it, the skill emits
  `/plugin marketplace update claude-plugins-official` and
  `/plugin install playground@claude-plugins-official` with scope guidance.
- The skill's guidance covers cloud/remote sessions, where upstream's `open <file>.html` cannot
  work: the generated HTML is delivered to the user (file send or artifact) instead of a local
  browser launch.
- The skill carries the five article recipes plus a repo-native SKILL.md-critique recipe.
- The audit-native-overlap canonical-pair seed carries both new candidate pairs, and
  `docs/native-surfaces/records.json` carries human-approved verdict rows whose evidence cites
  upstream commit `ed404106fcd80ba98ecb7c851e531dcb626d13b7` and the corpus slice, dated.
- `scripts/affected-tests.sh --run` passes for the full change set.
- Nothing in the change set proposes, automates, or documents filing anything upstream.

### Captured assumptions

- Consumers can reach `claude-plugins-official`; no air-gapped/offline install path is
  documented in v1 — revisit if a consumer reports an offline or proxy-restricted need.
- Upstream facts are pinned to commit `ed404106fcd80ba98ecb7c851e531dcb626d13b7` (6 templates,
  three output-prompt shapes, dark-only mandate vs light+dark diff-review vs light-only
  code-map, document-critique's partially-stubbed prompt generator, data-explorer's unescaped
  innerHTML rendering) — revisit any dependent wording when upstream moves past that commit, and
  re-verify before baking any phrase.
- The pilot runs on the user's local desktop with the upstream plugin as-is; pilot learnings may
  add wrapper enrichments but never generation.

### Out-of-scope

- Building or hardening playground templates, or standardizing the upstream output-prompt
  contract (noted in verdict evidence only).
- Upstream contributions of any kind.
- The design family (design-sync/consent/revoke, /design routing beyond what visualize already
  does) — the V2 vertical owns it.
- Description/listing-budget, spec-conformance, eval, and script-convention work — V3-V7
  verticals.

### Deferred questions

- Q8 — Final wrapper plugin name (non-colliding with the upstream bare `playground` skill) —
  defer until implementation; **arbiter: /planning:plan** (route through `/naming:name-it-better`).
- Q9 — Pilot learnings intake (what the local document-critique pilot changes in wrapper
  content) — defer until the user has run the pilot; **arbiter: USER-RESERVED**.

## Plan
