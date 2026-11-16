// The Claude Code surface a run sits under, and the apply targets that work there.
//
//   detectSurface(env) -> {id, name, targets: ["session" | "folder" | "initial"]}
//   refusal(surface, target, profile) -> null, or the reason an apply or clear for target is refused
//
// CLAUDE_CODE_REMOTE=true marks a cloud session (documented on the env-vars page). The values of
// CLAUDE_CODE_ENTRYPOINT are not documented: cli, sdk-cli (claude -p), claude-vscode and
// claude-desktop are the values Claude Code 2.1.325 sets. CLAUDECODE=1 marks a process Claude Code
// started, so a run with neither variable is a terminal, where `claude --settings` is the CLI.
// Only the CLI is known to honor `claude --settings`; an undetected surface allows the folder
// level alone.
const ALL = ["session", "folder", "initial"];
const LOCAL = ["folder", "initial"];

const KNOWN = {
  cli: { name: "the Claude Code CLI", targets: ALL },
  "sdk-cli": { name: "claude -p", targets: ALL },
  "claude-vscode": { name: "VS Code", targets: LOCAL },
  "claude-desktop": { name: "Claude Desktop", targets: LOCAL },
};

export function detectSurface(env) {
  if (env.CLAUDE_CODE_REMOTE === "true") return { id: "cloud", name: "a cloud session", targets: [] };
  const entry = env.CLAUDE_CODE_ENTRYPOINT;
  if (Object.hasOwn(KNOWN, entry ?? "")) return { id: entry, ...KNOWN[entry] };
  if (!entry && !env.CLAUDECODE) return { id: "terminal", name: "a terminal outside Claude Code", targets: ALL };
  return { id: "unknown", name: "surface not detected", targets: ["folder"] };
}

export const doesNotApply = (surface) => surface.targets.length === 0;

export function refusal(surface, target, profile) {
  if (doesNotApply(surface)) return `plugin profiles do not apply here: ${surface.name} reads no local or user settings, so nothing is written`;
  if (surface.targets.includes(target)) return null;
  const offer = profile ? `; apply it to this folder instead: apply ${profile} --for folder` : "";
  return `--for ${target} is not available on ${surface.name}${offer}`;
}

export function surfaceLine(surface) {
  if (doesNotApply(surface)) return `Surface: ${surface.name}; plugin profiles do not apply here and nothing is written.`;
  return `Surface: ${surface.name} (applies --for ${surface.targets.join(", ")}).`;
}
