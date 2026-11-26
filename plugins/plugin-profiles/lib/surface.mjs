const ALL = ["session", "folder", "initial"];
const LOCAL = ["folder", "initial"];

const KNOWN = {
  cli: { name: "the Claude Code CLI", targets: ALL },
  "sdk-cli": { name: "claude -p", targets: ALL },
  "claude-vscode": { name: "VS Code", targets: LOCAL },
  "claude-desktop": { name: "Claude Desktop", targets: LOCAL },
};

export function detectSurface(env) {
  if (env.CLAUDE_CODE_REMOTE === "true") return { id: "cloud", name: "a cloud session", why: "reads no local or user settings", targets: [] };
  const entry = env.CLAUDE_CODE_ENTRYPOINT;
  if (Object.hasOwn(KNOWN, entry ?? "")) return { id: entry, ...KNOWN[entry] };
  if (!entry && !env.CLAUDECODE) return { id: "terminal", name: "a terminal outside Claude Code", targets: ALL };
  return { id: "unknown", name: "surface not detected", targets: ["folder"] };
}

export const doesNotApply = (surface) => surface.targets.length === 0;

export function refusal(surface, target, profile) {
  if (doesNotApply(surface)) return `plugin profiles do not apply here: ${surface.name} ${surface.why}, so nothing is written`;
  if (surface.targets.includes(target)) return null;
  const offer = profile ? `; apply it to this folder instead: apply ${profile} --for folder` : "";
  return `--for ${target} is not available on ${surface.name}${offer}`;
}

export function surfaceLine(surface) {
  if (doesNotApply(surface)) return `Surface: ${surface.name}; plugin profiles do not apply here and nothing is written.`;
  return `Surface: ${surface.name} (applies --for ${surface.targets.join(", ")}).`;
}
