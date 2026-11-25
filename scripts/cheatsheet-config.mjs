
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

export const CADENCES = ["daily", "weekly", "continuous"];

export const SUMMARY_MAX_CODEPOINTS = 100;

export const EXCLUDED_PLUGINS = new Map([
  ["ai-briefing", "personal-domain plugin"],
  ["gaming", "personal-domain plugin"],
  ["kindle-dedrm", "personal-domain plugin"],
  ["knowledge", "personal-domain plugin"],
  ["machine-health", "personal-domain plugin"],
  ["songwriting", "personal-domain plugin"],
  ["x", "personal-domain plugin"],
]);

export const EXCLUDED_SKILL_NAME = { name: "setup", reason: "infra setup" };

export const EXCLUDED_SKILLS = new Map([
  ["work-items/onboard-adapter", "infra setup"],
  ["docs-naming/generate-file-name-gate", "infra setup"],
  ["discovery/report", "dispatched only"],
  ["implementation/report", "dispatched only"],
  ["plugin-quality/report", "dispatched only"],
  ["harness-ops/control-claude-code", "control skill read by app-control drive"],
  ["dometrain/update", "maintainer-only upstream sync"],
  ["firecrawl/update", "maintainer-only upstream sync"],
  ["playbooks/update", "maintainer-only upstream sync"],
]);

export const REVIEW_PR_MAP_HEADING = "Review and pull-request skill map";
export const REVIEW_PR_AUDIENCES = ["author", "reviewer", "CI lane"];
export const REVIEW_PR_POSTS = ["yes", "no", "through another skill"];
export const REVIEW_PR_MAP = [
  {
    skill: "review/quality-gate",
    job: "Single-lens review checkpoint of a change before it is ready",
    audience: ["author", "reviewer"],
    posts: "no",
    basis: "Durable findings are `<UTC-timestamp>-<mode>.md` in that directory",
  },
  {
    skill: "review/fanout",
    job: "Every reviewer at once, merged into one ranked report on disk",
    audience: ["author", "reviewer"],
    posts: "no",
    basis: "violates the review modes' report-only contract",
  },
  {
    skill: "review/council",
    job: "Configured panel of reviewers, one ranked report, optional fix rounds",
    audience: ["author", "reviewer"],
    posts: "no",
    basis: "Findings stay on disk; no PR comment",
  },
  {
    skill: "review/explain-change",
    job: "Digest of one PR: why, before and after, risk map, where to focus",
    audience: ["reviewer"],
    posts: "no",
    basis: "It never comments, reviews, labels, or sets a check status",
  },
  {
    skill: "review/merge-risk",
    job: "Checked merge-risk rating of one PR, with a demote-only flag",
    audience: ["reviewer"],
    posts: "no",
    basis: "Never posts or gates.",
  },
  {
    skill: "review/reviewer-media",
    job: "Decides whether a PR needs a walkthrough video and builds it from the digest",
    audience: ["author", "CI lane"],
    posts: "through another skill",
    basis: "hands the manifest to /source-control:pull-request media",
  },
  {
    skill: "review/code-review",
    job: "CI lane: correctness and maintainability findings on one PR",
    audience: ["CI lane"],
    posts: "yes",
    basis: "This lane posts only through its wrapper's mechanics",
  },
  {
    skill: "review/security-review",
    job: "CI lane: logic, trust-boundary and Actions security findings on one PR",
    audience: ["CI lane"],
    posts: "yes",
    basis: "In the CI lane this skill posts only through its wrapper's mechanics",
  },
  {
    skill: "source-control/pull-request",
    job: "Whole PR lifecycle: prep, create, ready, monitor, merge, evidence, media",
    audience: ["author"],
    posts: "yes",
    basis: "post one evidence comment, or update",
  },
  {
    skill: "source-control/babysit-prs",
    job: "Tiered fleet pass advancing open PRs; resolves threads and merges only at worker and autopilot",
    audience: ["author"],
    posts: "yes",
    basis: "auto-resolves *pre-push-outdated* bot threads",
  },
  {
    skill: "source-control/babysit-loop",
    job: "One repository's PR queue run as a standing merge lane",
    audience: ["CI lane"],
    posts: "through another skill",
    basis: "invoking /source-control:babysit-prs each cycle",
  },
  {
    skill: "playwright/demo-video",
    job: "Produced demo video of a web UI change, quality-checked from frames",
    audience: ["author"],
    posts: "yes",
    basis: "goes locally through `gh pr comment --attach`",
  },
  {
    skill: "explainer-video/produce",
    job: "Renders a narrated video from a topic or a storyboard",
    audience: ["author"],
    posts: "no",
    basis: "places a finished video in a pull request",
  },
];

export const STAGE_COMMANDS = [
  { stage: "interview", skill: "planning/interview" },
  { stage: "explore", skill: "discovery/explore" },
  { stage: "research", skill: "discovery/research" },
  { stage: "prd", skill: "planning/prd" },
  { stage: "design", skill: "planning/design" },
  { stage: "plan", skill: "planning/plan" },
  { stage: "decompose", skill: "work-items/decompose" },
  {
    stage: "implement",
    skill: "implementation/implement",
    also: [{ when: "when the breakage is not yet diagnosed, first", skill: "debugging/debug" }],
  },
  {
    stage: "test",
    skill: "testing/write",
    also: [{ when: "when a test fails,", skill: "testing/fix-failing" }],
  },
  { stage: "review", skill: "review/quality-gate" },
  {
    stage: "verify",
    skill: "verification/confirm",
    runs: [
      {
        claim: "runs the build, test and lint checks through `/toolchain:check` and `/toolchain:lint`",
        basis: "invoke `/toolchain:check` (if enabled) and `/toolchain:lint` (if enabled) cross-cutting via the Skill tool",
      },
      {
        claim: "finds the touched features with `/app-control:drive affected`",
        basis: "invoke `/app-control:drive affected --base <ref> --out <evidence dir>/affected`",
      },
      {
        claim: "drives the touched features with `/testing:run-e2e`",
        basis: "invoke `/testing:run-e2e` (if enabled) via the Skill tool",
      },
    ],
  },
  {
    stage: "pr",
    skill: "source-control/pull-request",
    runs: [
      {
        claim: "`ready` runs the code and security reviews in fresh-context subagents and the verify gate before marking the PR ready",
        basis: "run the code and security reviews over the PR diff in fresh-context subagents",
      },
    ],
  },
];

export const UPSTREAM_RECORDS = [
  { path: "docs/upstream/cursor-pstack.md", label: "pstack" },
  { path: "docs/upstream/mattpocock-skills.md", label: "Pocock" },
];

const YAML_UNSAFE_LEAD = new Set([
  "[", "]", "{", "}", ">", "|", "*", "&", "!", "%", "@", "`", '"', "'", "#", "-",
  ",", "?",
]);

export function summaryError(summary) {
  if (typeof summary !== "string" || summary.length === 0) return "empty summary";
  if ([...summary].length > SUMMARY_MAX_CODEPOINTS) {
    return `summary exceeds ${SUMMARY_MAX_CODEPOINTS} codepoints`;
  }
  for (const ch of summary) {
    const cp = ch.codePointAt(0);
    if (cp < 0x20 || cp === 0x7f) return "summary contains a tab or control character";
    if ((cp >= 0x80 && cp <= 0x9f) || cp === 0x2028 || cp === 0x2029) {
      return "summary contains a C1 control or Unicode line separator";
    }
  }
  if (YAML_UNSAFE_LEAD.has(summary[0])) return "summary starts with a YAML-special character";
  if (summary === "=") return "summary is the YAML value-key special `=`";
  if (summary.includes(": ")) return 'summary contains ": " (YAML mapping indicator)';
  if (summary.includes(" #")) return 'summary contains " #" (YAML comment start)';
  if (summary.endsWith(":") || summary.endsWith(" ")) {
    return "summary ends with a colon or whitespace";
  }
  return null;
}
