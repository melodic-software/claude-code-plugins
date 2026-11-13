// Hand-curated grouping layer for the generated skill cheat sheet
// (docs/skill-cheat-sheet.md). Owns the stage/group vocabulary and order, the
// exclusion entries, the shared summary guard, the command a person types for
// each workflow stage, the cited "runs for you" claims, and the upstream
// records the Upstream column reads. Per-skill detail (stage, summary,
// cadence, arguments) lives in each SKILL.md's frontmatter, never here, and
// which stages a kind of task runs lives in the Task kinds table of
// plugins/session-flow/skills/workflow/context/steps.md, never here.

// Workflow-stage headings mirror the H2 headings in
// plugins/session-flow/skills/workflow/context/steps.md (the generator's
// --check mode prefix-matches them against that file, same order, so a
// session-flow stage rename fails the sheet's own gate). The three
// non-workflow groups are owned here.
export const STAGES = [
  { slug: "interview", heading: "1. Interview", workflow: true },
  { slug: "explore", heading: "2. Explore", workflow: true },
  { slug: "research", heading: "3. Research", workflow: true },
  { slug: "prd", heading: "4. PRD", workflow: true },
  { slug: "design", heading: "5. Design", workflow: true },
  { slug: "plan", heading: "6. Plan", workflow: true },
  { slug: "decompose", heading: "7. Decompose", workflow: true },
  { slug: "implement", heading: "8. Implement", workflow: true },
  { slug: "test", heading: "9. Test", workflow: true },
  { slug: "review", heading: "10. Review", workflow: true },
  { slug: "verify", heading: "11. Verify outcome", workflow: true },
  { slug: "retro", heading: "12. Retrospective", workflow: true },
  { slug: "pr", heading: "Ship: PR lifecycle (after stage 11)", workflow: true },
  { slug: "anytime", heading: "Anytime / cross-cutting", workflow: false },
  { slug: "session", heading: "Session lifecycle", workflow: false },
  { slug: "operator", heading: "Operator cadence", workflow: false },
];

// `cadence` is required when `workflow-stage: operator`,
// forbidden otherwise. `continuous` covers self-paced standing loops that
// have no daily/weekly rhythm.
export const CADENCES = ["daily", "weekly", "continuous"];

export const SUMMARY_MAX_CODEPOINTS = 100;

// Exclusions are explicit, each with a reason. An in-scope skill must carry
// `workflow-stage` XOR appear here; the generator fails on silent omission,
// orphaned entries, and excluded-but-mapped conflicts.
export const EXCLUDED_PLUGINS = new Map([
  ["ai-briefing", "personal-domain plugin"],
  ["gaming", "personal-domain plugin"],
  ["kindle-dedrm", "personal-domain plugin"],
  ["knowledge", "personal-domain plugin"],
  ["machine-health", "personal-domain plugin"],
  ["songwriting", "personal-domain plugin"],
  ["x", "personal-domain plugin"],
]);

// Rule-based exclusion: every skill named `setup` is plugin provisioning, not
// a dev-lifecycle action.
export const EXCLUDED_SKILL_NAME = { name: "setup", reason: "infra setup" };

// Skill-level exclusions, keyed `plugin/skill`.
export const EXCLUDED_SKILLS = new Map([
  // Same class as the `setup` name rule above: provisioning, not a
  // dev-lifecycle action. It onboards a tracker the plugin does not bundle,
  // and routes bundled providers to `work-items/setup`; it just is not named
  // `setup`, so the rule above does not reach it.
  ["work-items/onboard-adapter", "infra setup"],
  // Same class again: it emits a gate and its suite into the consuming
  // repository once, which is provisioning. The dev-lifecycle actions in this
  // plugin's file-name set are `audit-file-names` and `realign-file-names`.
  ["docs-naming/generate-file-name-gate", "infra setup"],
  // The return-contract copies. One text, three byte-identical copies, each
  // preloaded into its own plugin's agents by a `skills:` entry and reachable
  // no other way: `user-invocable: false`, never a dev-lifecycle action a
  // reader picks off the sheet.
  ["discovery/report", "dispatched only"],
  ["implementation/report", "dispatched only"],
  ["plugin-quality/report", "dispatched only"],
  // A control skill: /app-control:drive reads it from disk and never invokes
  // it, and the control-skill contract allows it no `metadata` key.
  ["harness-ops/control-claude-code", "control skill read by app-control drive"],
  ["dometrain/update", "maintainer-only upstream sync"],
  ["firecrawl/update", "maintainer-only upstream sync"],
  ["playbooks/update", "maintainer-only upstream sync"],
]);

// The command a person types for each workflow stage, keyed by stage slug:
// `skills` in the order to type them, and `byKind` replacing them for a kind
// named in the Task kinds table. The generator joins this with that table to
// build the "By kind of task" view, and fails on a stage the table uses with
// no entry here, a skill not on the sheet, or a byKind key that is not a kind.
export const STAGE_COMMANDS = new Map([
  ["interview", { skills: ["planning/interview"] }],
  ["explore", { skills: ["discovery/explore"] }],
  ["research", { skills: ["discovery/research"] }],
  ["prd", { skills: ["planning/prd"] }],
  [
    "design",
    {
      skills: ["planning/design"],
      byKind: { "UI change": ["user-experience/structure", "user-interface/design", "planning/design"] },
    },
  ],
  ["plan", { skills: ["planning/plan"] }],
  ["decompose", { skills: ["work-items/decompose"] }],
  ["implement", { skills: ["implementation/implement"], byKind: { Bug: ["debugging/debug"] } }],
  ["test", { skills: ["testing/write"] }],
  [
    "review",
    { skills: ["review/quality-gate"], byKind: { "UI change": ["review/quality-gate", "user-interface/audit"] } },
  ],
  ["verify", { skills: ["verification/confirm"] }],
  ["retro", { skills: ["session-flow/retro"] }],
  ["pr", { skills: ["source-control/pull-request"] }],
]);

// What a stage command runs for the person, keyed `plugin/skill`. Each claim's
// `cite` is plain text (no backtick, asterisk or pipe) that must appear on
// exactly one line of the skill's SKILL.md, or of `file` in the skill
// directory: the line that makes the call. The sheet quotes it.
export const RUNS_FOR_YOU = new Map([
  ["planning/interview", [
    { does: "Sends unfamiliar territory to `/discovery:blindspot` first", cite: "Route to a blindspot-surfacing exploration FIRST" },
  ]],
  ["planning/plan", [
    { does: "Sends you to `/discovery:explore` first when the area has not been explored", cite: "suggest the exploration capability first" },
    { does: "Sends you to `/discovery:research` first when a claim the plan relies on is unresearched", cite: "suggest the research capability first" },
  ]],
  ["implementation/implement", [
    { does: "Runs `/toolchain:check` as the final build check", cite: "via the Skill tool for all affected ecosystems" },
    { does: "Hands the outcome verdict to `/verification:confirm`", cite: "which renders it from outside the producing loop" },
  ]],
  ["debugging/debug", [
    { does: "Reads a profile or trace with `/debugging:analyze-profile` when nothing reproduces", cite: "heap snapshot or performance trace and nothing reproduces, hand it to" },
  ]],
  ["testing/write", [
    { does: "Runs the new tests through `/toolchain:check`", cite: "Run the new tests by invoking" },
  ]],
  ["review/quality-gate", [
    { does: "Hands the diff to a fresh-context reviewer for the lens you name, against the pull request's base", cite: "dispatched reviewers diff" },
  ]],
  ["verification/confirm", [
    { does: "Runs `/toolchain:check` and `/toolchain:lint` for the build, test and lint checks, and stops on a failure", cite: "cross-cutting via the Skill tool, then the architecture-test gate" },
    { does: "Finds the touched features with `/app-control:drive affected`", cite: "Touched features come from" },
    { does: "Drives the changed flows through `/testing:run-e2e`", cite: "Apply the proof level, then auto-trigger" },
  ]],
  ["source-control/pull-request", [
    { does: "`prep` runs a review, checks each finding, simplifies and re-runs the build", cite: "Review (skipped when the CI code-review lane covers it" },
    { does: "`ready` updates the branch, runs the code and security reviews and the verify gate, then flips the draft", cite: "run the code and security reviews over the PR diff in fresh-context subagents" },
  ]],
]);

// Upstream records whose attribution table maps an upstream unit to ours. The
// Upstream column links the record's table for each skill a row names as
// `plugin:skill` in its second cell.
export const UPSTREAM_RECORDS = [
  { label: "pstack", path: "docs/upstream/cursor-pstack.md", heading: "Attribution table" },
  { label: "Pocock", path: "docs/upstream/mattpocock-skills.md", heading: "Attribution table" },
];

// Characters that make a plain YAML scalar unsafe at value start (flow/block
// indicators, anchors, tags, comments, quotes, list dash, flow entry separator,
// complex-mapping-key indicator). Held as a Set of single characters, not a
// regex, so no escaping layer can distort it.
const YAML_UNSAFE_LEAD = new Set([
  "[", "]", "{", "}", ">", "|", "*", "&", "!", "%", "@", "`", '"', "'", "#", "-",
  ",", "?",
]);

// Shared `summary` guard, enforced identically by the sweep's
// apply script and the generator.
//
// The rule this guard approximates is a FIXED POINT: the literal text after
// `summary:` must be what every reader of this repo recovers, whether it reads
// with a real YAML parser or with a regex. Claude Code documents that malformed
// frontmatter loads the skill with empty metadata, so a value the parser
// rejects costs the skill its whole frontmatter; a value the parser accepts but
// reinterprets (a quoted scalar it unescapes, a bare `true` it reads as a
// boolean) makes the parsed value and the regex-read value disagree. Requiring
// a plain, unquoted, colon-free scalar is the largest subset a dependency-light
// regex reader can recover exactly, which is why the constraint is stricter
// than YAML alone requires. Rejecting " #" likewise removes any
// trailing-comment stripping ambiguity between the readers.
//
// This function is the fast approximation, not the definition. The definition
// is executable and lives in scripts/check-summary-reader-parity.test.sh:
// a real YAML parse of the frontmatter must yield a string identical to the
// regex-read text. That oracle catches the value-reinterpreting cases this
// character-level guard deliberately does not enumerate, because a denylist of
// resolver spellings (`true`, `017`, `12:34`, `2026-08-23`) only ever holds the
// spellings someone was already burned by.
//
// Length is counted in Unicode codepoints, not bytes.
export function summaryError(summary) {
  if (typeof summary !== "string" || summary.length === 0) return "empty summary";
  if ([...summary].length > SUMMARY_MAX_CODEPOINTS) {
    return `summary exceeds ${SUMMARY_MAX_CODEPOINTS} codepoints`;
  }
  for (const ch of summary) {
    const cp = ch.codePointAt(0);
    if (cp < 0x20 || cp === 0x7f) return "summary contains a tab or control character";
    // C1 controls and the Unicode line separators are rejected by a real YAML
    // reader outright (C1) or consumed as line breaks (NEL/LS/PS), which breaks
    // the document structure. Neither is visible in an editor, so nothing about
    // the source line explains the CI failure they cause.
    if ((cp >= 0x80 && cp <= 0x9f) || cp === 0x2028 || cp === 0x2029) {
      return "summary contains a C1 control or Unicode line separator";
    }
  }
  if (YAML_UNSAFE_LEAD.has(summary[0])) return "summary starts with a YAML-special character";
  // `=` alone is YAML's `tag:yaml.org,2002:value` special and does not load as
  // the string "=". Only the whole-value form is special.
  if (summary === "=") return "summary is the YAML value-key special `=`";
  if (summary.includes(": ")) return 'summary contains ": " (YAML mapping indicator)';
  if (summary.includes(" #")) return 'summary contains " #" (YAML comment start)';
  if (summary.endsWith(":") || summary.endsWith(" ")) {
    return "summary ends with a colon or whitespace";
  }
  return null;
}
