// The paths a lane patch may not change, as apply-patch.mjs refuses them.
// No imports: admission (intake-triage/admit.mjs) loads it to refuse an issue
// whose criteria name one of these paths before a lane run is spent on it.

// A path's segments in lower case with `.`, `..` and empty segments resolved,
// so `.GitHub/x` and `a/../.github/x` read as `.github/x`.
export function segments(path) {
  const out = [];
  for (const part of String(path).toLowerCase().split("/")) {
    if (part === "..") {
      out.pop();
    } else if (part !== "" && part !== ".") {
      out.push(part);
    }
  }
  return out;
}

const LANE_GRANT_FILES = Object.freeze([".github/actions/resolve-config/lane-grants.json", ".github/standards/trusted-actors/trusted-actors.json"]);

// The directories and files Claude Code denies every write to under the lanes'
// dontAsk permission mode
// (https://code.claude.com/docs/en/permission-modes#protected-paths, as of
// 2026-11-11; recheck when that section's lists or exceptions change).
// .gitmodules is its own rule. The page gives no depth. A probe on 2026-11-11
// (Claude Code 2.1.322, `claude -p --permission-mode dontAsk` writing each
// path with Write) was denied each name below the checkout root too, wrote
// under .claude/worktrees/ at any depth, and wrote Markdown under
// .claude/agent-memory/ and .claude/agent-memory-local/ only at the root;
// recheck with the same probe when the section changes.
const CLAUDE_PROTECTED_DIRS = new Set([".git", ".vscode", ".idea", ".husky", ".cargo", ".devcontainer", ".yarn", ".mvn"]);
export const CLAUDE_PROTECTED_FILES = new Set([
  ".gitconfig",
  ".bashrc",
  ".bash_profile",
  ".bash_login",
  ".bash_aliases",
  ".bash_logout",
  ".zshrc",
  ".zprofile",
  ".zshenv",
  ".zlogin",
  ".zlogout",
  ".profile",
  ".envrc",
  ".npmrc",
  ".yarnrc",
  ".yarnrc.yml",
  ".pnp.cjs",
  ".pnp.loader.mjs",
  ".pnpmfile.cjs",
  "bunfig.toml",
  ".bunfig.toml",
  ".bazelrc",
  ".bazelversion",
  ".bazeliskrc",
  ".pre-commit-config.yaml",
  "lefthook.yml",
  "lefthook.yaml",
  ".lefthook.yml",
  ".lefthook.yaml",
  "gradle-wrapper.properties",
  "maven-wrapper.properties",
  ".devcontainer.json",
  ".ripgreprc",
  "pyrightconfig.json",
  ".mcp.json",
  ".claude.json",
]);
// A protected directory counts named bare too (`.vscode/`, `.config/git`), as
// admission reads an issue that adds files under it; the root agent-memory
// directories count as writable, since Markdown under them is.
const claudeDirWritable = (s, i) => s[i + 1] === "worktrees" || (i === 0 && ["agent-memory", "agent-memory-local"].includes(s[1]) && (s.length === 2 || s.at(-1).endsWith(".md")));
const claudeProtected = (s) =>
  CLAUDE_PROTECTED_FILES.has(s.at(-1)) ||
  s.some((part, i) => CLAUDE_PROTECTED_DIRS.has(part) || (part === ".config" && s[i + 1] === "git") || (part === ".claude" && !claudeDirWritable(s, i)));

export const PATH_RULES = {
  // The lane token has no workflows permission, so GitHub refuses the push.
  "github-workflows": (s) => s[0] === ".github" && s[1] === "workflows",
  // The three places GitHub reads a CODEOWNERS file from
  // (docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/about-code-owners,
  // as of 2026-10-22; recheck when that page names another location).
  codeowners: (s) => s.at(-1) === "codeowners" && (s.length === 1 || (s.length === 2 && [".github", "docs"].includes(s[0]))),
  gitmodules: (s) => s.at(-1) === ".gitmodules",
  // A settings file outside plugins/, whose files are this repository's product.
  settings: (s) => s[0] !== "plugins" && /^settings[^/]*\.json$/.test(s.at(-1) ?? ""),
  // The central lane grant file and the trusted-actor list, which decide what
  // every admitted repository's lanes may mint and who may start them (ADR 0085
  // Decision 6).
  "lane-grants": (s) => LANE_GRANT_FILES.includes(s.join("/")),
  // Optional: only a row whose model writes the patch names it.
  "claude-protected": claudeProtected,
};
const pathRule = (name) => (entry) => PATH_RULES[name](segments(entry.path));
// The universal path rules: a merge or shared-copy patch carries the base's
// own changes, which may rename into a path Claude Code protects.
const pathRefused = (path) => Object.entries(PATH_RULES).some(([name, rule]) => name !== "claude-protected" && rule(segments(path))) || path.includes("\\");

// The protected-path rows of apply-patch.mjs REFUSALS, which spreads them in.
export const PROTECTED_REFUSALS = {
  // A backslash reads as a directory separator on Windows checkouts.
  backslash: { kind: "protected-path", test: (entry) => entry.path.includes("\\") },
  "github-workflows": { kind: "protected-path", test: pathRule("github-workflows") },
  codeowners: { kind: "protected-path", test: pathRule("codeowners") },
  gitmodules: { kind: "protected-path", test: pathRule("gitmodules") },
  settings: { kind: "protected-path", test: pathRule("settings") },
  "lane-grants": { kind: "protected-path", test: pathRule("lane-grants") },
  "claude-protected": { kind: "protected-path", optional: true, test: pathRule("claude-protected") },
  "rename-into-refused": { kind: "protected-path", test: (entry) => entry.renamedFrom !== undefined && pathRefused(entry.path) },
};
