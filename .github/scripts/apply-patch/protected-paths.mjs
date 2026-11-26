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

const CLAUDE_PROTECTED_DIRS = new Set([".git", ".vscode", ".idea", ".husky", ".cargo", ".devcontainer", ".yarn", ".mvn"]);
const CLAUDE_PROTECTED_FILES = new Set([
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
const claudeDirWritable = (s, i) => s[i + 1] === "worktrees" || (i === 0 && ["agent-memory", "agent-memory-local"].includes(s[1]) && (s.length === 2 || s.at(-1).endsWith(".md")));
const claudeProtected = (s) =>
  CLAUDE_PROTECTED_FILES.has(s.at(-1)) ||
  s.some((part, i) => CLAUDE_PROTECTED_DIRS.has(part) || (part === ".config" && s[i + 1] === "git") || (part === ".claude" && !claudeDirWritable(s, i)));

export const PATH_RULES = {
  "github-workflows": (s) => s[0] === ".github" && s[1] === "workflows",
  codeowners: (s) => s.at(-1) === "codeowners" && (s.length === 1 || (s.length === 2 && [".github", "docs"].includes(s[0]))),
  gitmodules: (s) => s.at(-1) === ".gitmodules",
  settings: (s) => s[0] !== "plugins" && /^settings[^/]*\.json$/.test(s.at(-1) ?? ""),
  "lane-grants": (s) => LANE_GRANT_FILES.includes(s.join("/")),
  "claude-protected": claudeProtected,
};
const pathRule = (name) => (entry) => PATH_RULES[name](segments(entry.path));
const pathRefused = (path) => Object.entries(PATH_RULES).some(([name, rule]) => name !== "claude-protected" && rule(segments(path))) || path.includes("\\");

export const PROTECTED_REFUSALS = {
  backslash: { kind: "protected-path", test: (entry) => entry.path.includes("\\") },
  "github-workflows": { kind: "protected-path", test: pathRule("github-workflows") },
  codeowners: { kind: "protected-path", test: pathRule("codeowners") },
  gitmodules: { kind: "protected-path", test: pathRule("gitmodules") },
  settings: { kind: "protected-path", test: pathRule("settings") },
  "lane-grants": { kind: "protected-path", test: pathRule("lane-grants") },
  "claude-protected": { kind: "protected-path", optional: true, test: pathRule("claude-protected") },
  "rename-into-refused": { kind: "protected-path", test: (entry) => entry.renamedFrom !== undefined && pathRefused(entry.path) },
};
