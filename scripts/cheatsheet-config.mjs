// Hand-curated grouping layer for the generated skill cheat sheet
// (docs/SKILL-CHEAT-SHEET.md). Owns exactly three things: the stage/group
// vocabulary and order, the exclusion entries, and the shared summary guard.
// Per-skill detail (stage, summary, cadence) lives in each SKILL.md's
// `metadata:` frontmatter — never here.

// Workflow-stage headings mirror the H2 headings in
// plugins/session-flow/skills/workflow/context/steps.md (the generator's
// --check mode prefix-matches them against that file, same order, so a
// session-flow stage rename fails the sheet's own gate). The three
// non-workflow groups are owned here.
export const STAGES = [
  { slug: "contract", heading: "0. Contract", workflow: true },
  { slug: "explore", heading: "1. Explore", workflow: true },
  { slug: "research", heading: "2. Research", workflow: true },
  { slug: "plan", heading: "3. Plan", workflow: true },
  { slug: "implement", heading: "4. Implement", workflow: true },
  { slug: "test", heading: "5. Test", workflow: true },
  { slug: "review", heading: "6. Review", workflow: true },
  { slug: "verify", heading: "7. Verify outcome", workflow: true },
  { slug: "retro", heading: "8. Retrospective", workflow: true },
  { slug: "pr", heading: "PR lifecycle (after step 7)", workflow: true },
  { slug: "anytime", heading: "Anytime / cross-cutting", workflow: false },
  { slug: "session", heading: "Session lifecycle", workflow: false },
  { slug: "operator", heading: "Operator cadence", workflow: false },
];

// `cadence` is required when `workflow-stage: operator`,
// forbidden otherwise. `continuous` covers self-paced standing loops that
// have no daily/weekly rhythm.
export const CADENCES = ["daily", "weekly", "continuous"];

export const SUMMARY_MAX_CODEPOINTS = 100;

// Exclusions are explicit, each with a reason — an in-scope skill must carry
// `workflow-stage` XOR appear here; the generator fails on silent omission,
// orphaned entries, and excluded-but-mapped conflicts.
export const EXCLUDED_PLUGINS = new Map([
  ["ai-briefing", "personal-domain plugin"],
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
  ["dometrain/sync", "maintainer-only vendored-content drift check"],
  ["firecrawl/update", "maintainer-only upstream sync"],
  ["playbooks/update", "maintainer-only upstream sync"],
]);

// Characters that make a plain YAML scalar unsafe at value start (flow/block
// indicators, anchors, tags, comments, quotes, list dash). Held as a Set of
// single characters, not a regex, so no escaping layer can distort it.
const YAML_UNSAFE_LEAD = new Set([
  "[", "]", "{", "}", ">", "|", "*", "&", "!", "%", "@", "`", '"', "'", "#", "-",
]);

// Shared `summary` guard, enforced identically by the sweep's
// apply script and the generator. The value must survive as a plain YAML
// scalar: an invalid frontmatter value makes Claude Code load the skill with
// ALL frontmatter silently dropped, so anything YAML could reinterpret is
// rejected outright. Rejecting " #" also means no trailing-comment stripping
// ambiguity between YAML parsers and the regex readers (skill-quality's
// skill_frontmatter::metadata_field). Length is counted in Unicode
// codepoints, not bytes.
export function summaryError(summary) {
  if (typeof summary !== "string" || summary.length === 0) return "empty summary";
  if ([...summary].length > SUMMARY_MAX_CODEPOINTS) {
    return `summary exceeds ${SUMMARY_MAX_CODEPOINTS} codepoints`;
  }
  for (const ch of summary) {
    const cp = ch.codePointAt(0);
    if (cp < 0x20 || cp === 0x7f) return "summary contains a tab or control character";
  }
  if (YAML_UNSAFE_LEAD.has(summary[0])) return "summary starts with a YAML-special character";
  if (summary.includes(": ")) return 'summary contains ": " (YAML mapping indicator)';
  if (summary.includes(" #")) return 'summary contains " #" (YAML comment start)';
  if (summary.endsWith(":") || summary.endsWith(" ")) {
    return "summary ends with a colon or whitespace";
  }
  return null;
}
