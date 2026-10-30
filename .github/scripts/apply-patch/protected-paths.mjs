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
};
const pathRule = (name) => (entry) => PATH_RULES[name](segments(entry.path));
const pathRefused = (path) => Object.values(PATH_RULES).some((rule) => rule(segments(path))) || path.includes("\\");

// The protected-path rows of apply-patch.mjs REFUSALS, which spreads them in.
export const PROTECTED_REFUSALS = {
  // A backslash reads as a directory separator on Windows checkouts.
  backslash: { kind: "protected-path", test: (entry) => entry.path.includes("\\") },
  "github-workflows": { kind: "protected-path", test: pathRule("github-workflows") },
  codeowners: { kind: "protected-path", test: pathRule("codeowners") },
  gitmodules: { kind: "protected-path", test: pathRule("gitmodules") },
  settings: { kind: "protected-path", test: pathRule("settings") },
  "lane-grants": { kind: "protected-path", test: pathRule("lane-grants") },
  "rename-into-refused": { kind: "protected-path", test: (entry) => entry.renamedFrom !== undefined && pathRefused(entry.path) },
};
