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
  // Same class as the `setup` name rule above — provisioning, not a
  // dev-lifecycle action. It onboards a tracker the plugin does not bundle,
  // and routes bundled providers to `work-items/setup`; it just is not named
  // `setup`, so the rule above does not reach it.
  ["work-items/onboard-adapter", "infra setup"],
  ["dometrain/sync", "maintainer-only vendored-content drift check"],
  ["firecrawl/update", "maintainer-only upstream sync"],
  ["playbooks/update", "maintainer-only upstream sync"],
]);

// Characters that make a plain YAML scalar unsafe at value start (flow/block
// indicators, anchors, tags, comments, quotes, list dash, flow entry separator,
// complex-mapping-key indicator). Held as a Set of single characters, not a
// regex, so no escaping layer can distort it.
//
// `,` and `?` were added after a parser sweep found them clearing every rule
// here while failing a real YAML parse outright (#3189): a leading `,` raises a
// ParserError and a leading `? ` a ScannerError. They belong to the same
// c-indicator class as the rest of this set and were simply missing from it.
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
    // the source line explains the CI failure they cause (#3189).
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
