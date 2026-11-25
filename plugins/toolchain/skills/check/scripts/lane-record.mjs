import { spawnSync } from "node:child_process";
import { readFileSync, realpathSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { basename, dirname, isAbsolute, posix, relative, resolve, sep } from "node:path";
import { pathToFileURL } from "node:url";

export const COMMAND_KEYS = [
  "build-cmd",
  "test-cmd",
  "test-changed-cmd",
  "check-cmd",
  "lint-cmd",
  "fix-cmd",
  "code-fix-cmd",
];

const ECOSYSTEM_ID = /^[a-z0-9]+(?:-[a-z0-9]+)*$/;
const ASSUMED_LINE = /^\s*assumed:\s*([a-z0-9]+(?:-[a-z0-9]+)*)\.(\S+?)=(.+) \(([^()]+):([1-9]\d*)\)\s*$/;
const LINE_BREAK = /\r\n|\r|\n/;
const RECORDS_FOLDER = /^(?:docs\/conventions|\.claude)\/ecosystems(?:\/|$)/i;
const RECORD_FILE = /^(?:docs\/conventions|\.claude)\/ecosystems\/([^/]+?)(?:\.local)?\.yaml$/;
const SHELL_WORD = /^[A-Za-z0-9._:@/-]+$/;

const UNSAFE_RANGES = [
  [0x0, 0x1f],
  [0x7f, 0x9f],
  [0xad, 0xad],
  [0x61c, 0x61c],
  [0x180e, 0x180e],
  [0x200b, 0x200f],
  [0x2028, 0x202e],
  [0x2060, 0x2064],
  [0x2066, 0x206f],
  [0xfeff, 0xfeff],
];
const hasUnsafe = (text) =>
  [...text].some((ch) => {
    const code = ch.codePointAt(0);
    return UNSAFE_RANGES.some(([low, high]) => code >= low && code <= high);
  });

const CI_FILES = [
  /^\.github\/(?:workflows|actions)\//,
  /^\.gitlab-ci\.ya?ml$/,
  /^\.gitlab\//,
  /^\.circleci\//,
  /^\.?azure-pipelines(?:\.ya?ml$|\/)/,
  /^\.pipelines\//,
  /(?:^|\/)Jenkinsfile$/,
  /^\.buildkite\//,
  /^bitbucket-pipelines\.ya?ml$/,
  /^\.travis\.ya?ml$/,
  /^\.?appveyor\.ya?ml$/,
  /^\.drone\.ya?ml$/,
  /^\.woodpecker(?:\.ya?ml$|\/)/,
];

const INSTALL_VERBS = {
  npm: [
    "i", "in", "ins", "inst", "insta", "instal", "isnt", "isnta", "isntal", "isntall", "add", "it", "cit", "ci",
    "clean-install", "clean-install-test", "install-test", "install-ci-test", "update", "up", "upgrade", "udpate",
    "exec", "x", "link", "ln", "rebuild", "rb", "ic", "install-clean", "isntall-clean", "sit", "init", "create",
  ],
  pnpm: [
    "i", "add", "update", "up", "upgrade", "dlx", "exec", "fetch", "import", "rebuild", "rb", "it", "install-test", "init",
    "create",
  ],
  yarn: ["add", "up", "upgrade", "upgrade-interactive", "dlx", "exec", "global", "init", "create"],
  bun: ["i", "add", "update", "x", "link", "init", "create"],
  pip: ["download", "wheel"],
  uv: ["sync", "add", "pip", "tool"],
  poetry: ["add", "update", "sync"],
  dotnet: ["restore", "tool", "workload", "add", "new"],
  cargo: ["add", "fetch", "update"],
  go: ["get", "mod"],
  gem: [],
  bundle: ["add", "update"],
};
const BARE_INSTALLS = new Set(["yarn", "bundle"]);
const SHELL_KEYWORDS = new Set(["if", "then", "elif", "else", "while", "until", "do", "!", "eval", "source", "."]);
const REFUSED_TOOLS = new Set([
  "npx", "pnpx", "bunx", "uvx", "pipx", "ensurepip", "sudo", "doas", "gsudo", "pkexec", "su", "apt", "apt-get", "brew", "choco",
  "winget", "scoop", "snap", "dnf", "yum", "apk", "pacman", "zypper", "port", "nix-env", "curl", "wget",
]);
const WRAPPERS = new Set(["env", "command", "exec", "nice", "nohup", "time", "xargs", "stdbuf", "setsid", "timeout", "ionice", "chrt"]);
const SHELLS = /^(?:(?:ba|da|z|k|fi)?sh|pwsh|powershell|cmd)$/;

const LOCKFILES = {
  "package-lock.json": "npm",
  "npm-shrinkwrap.json": "npm",
  "pnpm-lock.yaml": "pnpm",
  "yarn.lock": "yarn",
  "bun.lock": "bun",
  "bun.lockb": "bun",
};

const GIT_ENV = (() => {
  const env = { ...process.env, GIT_NO_REPLACE_OBJECTS: "1", GIT_TERMINAL_PROMPT: "0" };
  for (const name of ["GIT_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE", "GIT_OBJECT_DIRECTORY", "GIT_COMMON_DIR"]) delete env[name];
  return env;
})();

const toPosix = (p) => p.split(sep).join("/");
const label = (entry) => `${entry.ecosystem}.${entry.key}=${entry.value} (${entry.file}:${entry.line})`;

export function parseAssumed(text) {
  const entries = [];
  const errors = [];
  const skipped = [];
  for (const raw of text.split(LINE_BREAK)) {
    if (!/^\s*assumed:/.test(raw)) continue;
    const m = raw.match(ASSUMED_LINE);
    if (!m) {
      errors.push(`malformed assumed: line: ${raw.trim()}`);
      continue;
    }
    const [, ecosystem, key, rawValue, file, line] = m;
    const value = rawValue.trim();
    if (key === "gates" || key.startsWith("gates.") || key.startsWith("gates[")) {
      skipped.push(`${raw.trim()}: a gate is not proposed`);
      continue;
    }
    if (!COMMAND_KEYS.includes(key)) {
      errors.push(`assumed: line names ${ecosystem}.${key}, not a command key: ${raw.trim()}`);
      continue;
    }
    if (!value || value !== rawValue) {
      errors.push(`malformed assumed: line (empty or padded value): ${raw.trim()}`);
      continue;
    }
    entries.push({ ecosystem, key, value, file: file.trim(), line: Number(line) });
  }
  return { entries, errors, skipped };
}

function segments(command) {
  return command
    .split(/&&|\|\||[;|&\n(){}]/)
    .map((part) =>
      part
        .trim()
        .split(/\s+/)
        .map((token) => token.replace(/["'\\]/g, ""))
        .filter(Boolean),
    )
    .filter((tokens) => tokens.length > 0);
}

function toolName(token) {
  const name = basename(token).replace(/\.(?:exe|cmd|bat)$/i, "");
  return /^pip[\d.]*$/.test(name) ? "pip" : name;
}

function verbReason(name, args) {
  const positional = args.filter((t) => !t.startsWith("-"));
  if (!positional.length) return null;
  const verbs = args[0].startsWith("-") ? positional : [args[0]];
  for (const verb of verbs) {
    if (verb === "install") return `runs an install verb (${name} install)`;
    if (Object.hasOwn(INSTALL_VERBS, name) && INSTALL_VERBS[name].includes(verb)) return `runs an install verb (${name} ${verb})`;
  }
  return null;
}

function toolReason(name, args) {
  if (REFUSED_TOOLS.has(name)) return `runs ${name}`;
  if (SHELLS.test(name) && args.some((t) => /^(?:-\w*c\w*|-Command|-EncodedCommand|\/[cCkK])$/.test(t))) {
    return `runs a command string through ${name}`;
  }
  if (name === "uv" && args.some((t) => t.startsWith("--with"))) return "runs uv with an added dependency";
  if (name === "go" && args[0] === "run" && args.some((t) => t.includes("@"))) return "runs go run on a versioned module, which downloads it";
  if (/^(?:python[\d.]*|py)$/.test(name)) {
    const at = args.findIndex((t) => /^-[A-Za-z]*m./.test(t));
    if (at !== -1) {
      const module = toolName(args[at].replace(/^-[A-Za-z]*?m/, ""));
      const reason = toolReason(module, args.slice(at + 1)) ?? verbReason(module, args.slice(at + 1));
      if (reason) return reason;
    }
  }
  return verbReason(name, args);
}

export function installReason(command) {
  if (/[$`]|[<>]\(/.test(command)) return "holds a shell expansion or command substitution";
  for (let tokens of segments(command)) {
    while (tokens.length && /^[A-Za-z_][A-Za-z0-9_]*=/.test(tokens[0])) tokens = tokens.slice(1);
    if (!tokens.length) continue;
    const lead = toolName(tokens[0]);
    if (WRAPPERS.has(lead) || SHELL_KEYWORDS.has(tokens[0])) return `starts with ${tokens[0]}, which runs the rest as another command`;
    if (BARE_INSTALLS.has(lead) && tokens.slice(1).every((t) => t.startsWith("-"))) return `runs ${lead} with no verb, which installs`;
    for (let i = 0; i < tokens.length; i++) {
      const reason = toolReason(toolName(tokens[i]), tokens.slice(i + 1));
      if (reason) return reason;
    }
  }
  return null;
}

function yamlScalar(text) {
  const trimmed = text.trim();
  if (trimmed.startsWith('"')) {
    try {
      return JSON.parse(trimmed);
    } catch {
      return undefined;
    }
  }
  if (trimmed.startsWith("'")) {
    const m = trimmed.match(/^'((?:[^']|'')*)'$/);
    return m ? m[1].replaceAll("''", "'") : undefined;
  }
  if (/^[[{&*!|>%@`~]/.test(trimmed) || /^(?:null|true|false|-?\d[\d.]*)$/i.test(trimmed)) return undefined;
  return trimmed.replace(/\s+#.*$/, "");
}

function braceScan(lines, onLine) {
  let depth = 0;
  let inString = false;
  let escaped = false;
  for (let i = 0; i < lines.length; i++) {
    if (onLine(i, depth, inString)) return i;
    for (const ch of lines[i]) {
      if (inString) {
        if (escaped) escaped = false;
        else if (ch === "\\") escaped = true;
        else if (ch === '"') inString = false;
      } else if (ch === '"') inString = true;
      else if (ch === "{") depth++;
      else if (ch === "}") depth--;
    }
  }
  return -1;
}

function scriptsBlock(lines) {
  const start = braceScan(lines, (i, depth, inString) => depth === 1 && !inString && /^\s*"scripts"\s*:\s*\{/.test(lines[i]));
  if (start === -1) return null;
  const end = braceScan(lines, (i, depth, inString) => i > start && depth === 1 && !inString);
  return { start, end: end === -1 ? lines.length : end - 1 };
}

function manifestScript(entry, ctx) {
  if (ctx.rel !== "package.json") return "cites a package.json outside the repository root, which no plain run command reaches";
  let manifest;
  try {
    manifest = JSON.parse(ctx.content);
  } catch {
    return "package.json does not parse";
  }
  const scripts = manifest?.scripts;
  const m = ctx.text.match(/^\s*"((?:[^"\\]|\\.)+)"\s*:/);
  const block = scriptsBlock(ctx.lines);
  const index = entry.line - 1;
  if (!m || !scripts || typeof scripts !== "object" || !block || index <= block.start || index > block.end) {
    return "the cited line is not a package.json script";
  }
  let name;
  try {
    name = JSON.parse(`"${m[1]}"`);
  } catch {
    return "the cited line is not a package.json script";
  }
  if (!Object.hasOwn(scripts, name)) return "the cited line is not a package.json script";
  if (!SHELL_WORD.test(name)) return "the script name holds characters a shell would read";
  const kept = ctx.src.tracked(Object.keys(LOCKFILES));
  if (!kept) return "git could not list the lockfiles, so the package manager is unknown";
  const managers = [...new Set(kept.map((path) => LOCKFILES[path]))];
  if (managers.length > 1) return `lockfiles name more than one package manager (${managers.join(", ")})`;
  const pm = managers[0] ?? "npm";
  const allowed = [`${pm} run ${name}`];
  if (name === "test") allowed.push(`${pm} test`);
  return allowed.includes(entry.value) ? null : `the script ${JSON.stringify(name)} runs as ${allowed.map((a) => `\`${a}\``).join(" or ")}`;
}

function makeTarget(entry, ctx) {
  if (ctx.rel.includes("/")) return "cites a Makefile outside the repository root";
  const kept = ctx.src.tracked(["GNUmakefile", "makefile", "Makefile"]);
  if (!kept) return "git could not list the makefiles";
  const picked = kept[0];
  if (!picked) return "the base tracks no GNUmakefile, makefile or Makefile";
  if (picked !== ctx.rel) return `make reads ${picked}, not ${ctx.rel}`;
  const m = ctx.text.match(/^([^\s:=#][^:=#]*?)\s*::?(?!:?=)/);
  const targets = m ? m[1].split(/\s+/).filter((t) => /^[A-Za-z0-9_][A-Za-z0-9_./-]*$/.test(t)) : [];
  if (!targets.length) return "the cited line is not a Makefile target";
  return targets.some((t) => entry.value === `make ${t}`) ? null : `the cited target runs as \`make ${targets[0]}\``;
}

function justRecipe(entry, ctx) {
  if (ctx.rel.includes("/")) return "cites a justfile outside the repository root";
  const m = ctx.text.match(/^@?([A-Za-z0-9_][A-Za-z0-9_-]*)(?:\s+[^:=]*)?:(?!=)/);
  if (!m) return "the cited line is not a justfile recipe";
  return entry.value === `just ${m[1]}` ? null : `the cited recipe runs as \`just ${m[1]}\``;
}

function buildEntry(entry, ctx) {
  const name = basename(ctx.rel);
  const known = /\.(?:sln|slnx|csproj|fsproj|vbproj)$/.test(name) || ctx.rel === "Cargo.toml" || ctx.rel === "go.mod";
  if (!known) return undefined;
  if (entry.line !== 1) return "cite a build entry point by its first line";
  if (ctx.rel === "Cargo.toml") {
    return /^cargo (?:build|test|check)$/.test(entry.value) ? null : "the command is not cargo's build, test or check verb";
  }
  if (ctx.rel === "go.mod") {
    return /^go (?:build|test|vet) \.\/\.\.\.$/.test(entry.value) ? null : "the command is not go's build, test or vet verb on ./...";
  }
  if (!SHELL_WORD.test(ctx.rel)) return "the entry point's path holds characters a shell would read";
  const m = entry.value.match(/^dotnet (build|test) (\S+)$/);
  const target = m ? m[2].replace(/^\.\//, "") : null;
  return target === ctx.rel ? null : `the command is not \`dotnet build\` or \`dotnet test\` on ${ctx.rel}`;
}

function isStatedFile(rel) {
  if (/(?:^|\/)(?:node_modules|vendor|third_party)\//.test(rel)) return false;
  if (rel === "CLAUDE.md" || rel === ".claude/CLAUDE.md" || basename(rel) === "AGENTS.md") return true;
  if (["CONTRIBUTING.md", ".github/CONTRIBUTING.md", "docs/CONTRIBUTING.md"].includes(rel)) return true;
  return /^\.claude\/rules\/.+\.md$/.test(rel);
}

const FORBID_WORDS = /\b(?:never|not|cannot|can\s+not|no|avoid|instead\s+of|forbid\w*|prohibit\w*|unless|without|only)\b|n['’]t\b/i;
function headingLines(lines) {
  let fence = null;
  return lines.map((line) => {
    const marker = line.match(/^ {0,3}(`{3,}|~{3,})/)?.[1];
    if (fence) {
      if (marker && marker[0] === fence[0] && marker.length >= fence.length) fence = null;
      return false;
    }
    if (marker) {
      fence = marker;
      return false;
    }
    return /^ {0,3}#{1,6}(?:\s|$)/.test(line);
  });
}

function citedBlock(lines, index) {
  const heading = headingLines(lines);
  let start = index;
  while (start > 0 && !heading[start]) start--;
  let end = index;
  while (end + 1 < lines.length && !heading[end + 1]) end++;
  return { start, block: lines.slice(start, end + 1) };
}

function statedLine(entry, ctx) {
  const spans = [...ctx.text.matchAll(/`([^`]+)`/g)].map((m) => m[1].trim());
  if (!spans.includes(entry.value) && ctx.text.trim() !== entry.value) {
    return "the cited instructions line does not state the command as a whole code span";
  }
  const index = entry.line - 1;
  const { start, block } = citedBlock(ctx.lines, index);
  const unspan = (line) => line.replace(/`([^`]*)`/g, (_, code) => (code.trim() === entry.value ? " " : ` ${code} `));
  const prose = block.map((line) => unspan(line).replace(/[_*]/g, " "));
  if (ctx.text.trim() === entry.value) prose[index - start] = "";
  if (prose.some((line) => FORBID_WORDS.test(line))) return "the cited instructions block may forbid the command";
  return null;
}

function recordedLine(entry, ctx, stem) {
  if (stem !== entry.ecosystem) return `the cited record is for ${stem}, not ${entry.ecosystem}`;
  const m = ctx.text.match(/^([a-z-]+)\s*:\s*(.*)$/);
  if (!m || m[1] !== entry.key) return `the cited record line does not hold ${entry.key}`;
  return yamlScalar(m[2]) === entry.value ? null : `the cited record line holds a different ${entry.key}`;
}

function runGit(cwd, args, options = {}) {
  const result = spawnSync("git", ["--literal-pathspecs", "-c", "core.fsmonitor=false", "-C", cwd, ...args], {
    encoding: "utf8",
    env: GIT_ENV,
    maxBuffer: 64 * 1024 * 1024,
    ...options,
  });
  return result.error ? { status: -1, stdout: "" } : result;
}

function gitToplevel(dir) {
  const top = runGit(dir, ["rev-parse", "--show-toplevel"]);
  if (top.status !== 0) return null;
  try {
    return realpathSync(top.stdout.trim());
  } catch {
    return null;
  }
}

function requireCommit(root, ref) {
  if (ref.startsWith("-") || runGit(root, ["rev-parse", "--verify", "--quiet", `${ref}^{commit}`]).status !== 0) {
    throw new Error(`${ref} is not a commit in ${root}`);
  }
}

function remoteDefaultRef(root, remote) {
  const local = runGit(root, ["symbolic-ref", "--quiet", `refs/remotes/${remote}/HEAD`]).stdout.trim();
  if (local) return local;
  const listed = runGit(root, ["ls-remote", "--symref", "--end-of-options", remote, "HEAD"], { timeout: 30_000 });
  const m = listed.status === 0 ? listed.stdout.match(/^ref: refs\/heads\/(\S+)\tHEAD$/m) : null;
  if (!m) return "";
  const ref = `refs/remotes/${remote}/${m[1]}`;
  return runGit(root, ["rev-parse", "--verify", "--quiet", `${ref}^{commit}`]).status === 0 ? ref : "";
}

function defaultBranchBase(root) {
  const branch = runGit(root, ["branch", "--show-current"]).stdout.trim();
  const tracked = branch ? runGit(root, ["config", `branch.${branch}.remote`]).stdout.trim() : "";
  const remotes = runGit(root, ["remote"]).stdout.split("\n").filter(Boolean);
  for (const remote of [...new Set([tracked, "origin", ...remotes])].filter((r) => remotes.includes(r))) {
    const head = remoteDefaultRef(root, remote);
    if (!head) continue;
    const mergeBase = runGit(root, ["merge-base", head, "HEAD"]);
    if (mergeBase.status === 0) return { ref: mergeBase.stdout.trim(), name: `the merge-base with ${head.replace(/^refs\/remotes\//, "")}` };
  }
  return null;
}

function gitRoot(dir) {
  const root = realpathSync(dir);
  if (gitToplevel(root) !== root) throw new Error(`${root} is not the root of a git work tree, or git failed there`);
  return root;
}

export function baseRevision(repo, ref, name = ref) {
  const root = gitRoot(repo);
  requireCommit(root, ref);
  const listTree = (paths) => runGit(root, ["ls-tree", "-z", ref, "--", ...paths]);
  const regularFiles = (stdout) =>
    stdout
      .split("\0")
      .map((row) => row.match(/^100(?:644|755) blob \S+\t(.+)$/s)?.[1])
      .filter(Boolean);
  const regularFile = (rel) => {
    const listed = listTree([rel]);
    return listed.status === 0 && regularFiles(listed.stdout).includes(rel);
  };
  return {
    root,
    name,
    locate(file) {
      const rel = posix.normalize(file).replace(/^\.\//, "");
      if (rel === "." || rel === ".." || rel.startsWith("../") || isAbsolute(rel)) return { reason: "cites a file outside the repository" };
      return { rel };
    },
    read(rel) {
      if (!regularFile(rel)) return null;
      const shown = runGit(root, ["cat-file", "blob", `${ref}:${rel}`]);
      return shown.status === 0 ? shown.stdout : null;
    },
    tracked(paths) {
      const listed = listTree(paths);
      if (listed.status !== 0) return null;
      const kept = new Set(regularFiles(listed.stdout));
      return paths.filter((p) => kept.has(p));
    },
  };
}

export function checkSource(entry, src) {
  if (isAbsolute(entry.file) || entry.file.includes("\\")) return { reason: "cites an absolute or non-POSIX path" };
  const located = src.locate(entry.file);
  if (located.reason) return located;
  const { rel } = located;
  const cited = posix.normalize(entry.file).replace(/^\.\//, "");
  if (CI_FILES.some((re) => re.test(rel) || re.test(cited))) return { reason: "cites a CI workflow file" };
  if (hasUnsafe(entry.value)) return { reason: "the command holds a control or invisible character" };
  const install = installReason(entry.value);
  if (install) return { reason: install };
  const content = src.read(rel);
  if (content === null) return { reason: `the cited file ${entry.file} is not a tracked regular file at ${src.name}` };
  const lines = content.split(LINE_BREAK);
  const text = lines[entry.line - 1];
  if (text === undefined) return { reason: `the cited file has no line ${entry.line}` };
  const ctx = { src, rel, content, lines, text };
  const recorded = rel.match(RECORD_FILE);
  if (recorded) return { reason: recordedLine(entry, ctx, recorded[1]), kind: "recorded" };
  if (isStatedFile(rel)) return { reason: statedLine(entry, ctx), kind: "stated" };
  if (basename(rel) === "package.json") return { reason: manifestScript(entry, ctx), kind: "inferred" };
  if (/^(?:GNUmakefile|[Mm]akefile)$/.test(basename(rel))) return { reason: makeTarget(entry, ctx), kind: "inferred" };
  if (/^(?:\.?justfile|Justfile)$/.test(basename(rel))) return { reason: justRecipe(entry, ctx), kind: "inferred" };
  const built = buildEntry(entry, ctx);
  if (built !== undefined) return { reason: built, kind: "inferred" };
  return { reason: "the cited file is not a record, an instructions file, a manifest script, a task-runner target or a build entry point" };
}

export function renderRecord(globs, values) {
  const out = ["globs:", ...globs.map((g) => `  - ${JSON.stringify(g)}`)];
  for (const key of COMMAND_KEYS) {
    if (Object.hasOwn(values, key)) out.push(`${key}: ${JSON.stringify(values[key])}`);
  }
  return `${out.join("\n")}\n`;
}

function quotedString(text) {
  let parsed;
  try {
    parsed = JSON.parse(text);
  } catch {
    return undefined;
  }
  return typeof parsed === "string" && parsed && !hasUnsafe(parsed) ? parsed : undefined;
}

export function parseRecord(text) {
  const lines = text.split(LINE_BREAK);
  const values = {};
  const errors = [];
  let globs = null;
  if (hasUnsafe(text.replace(/\r\n|\r|\n/g, ""))) errors.push("record holds a control or invisible character");
  for (let i = lines[0] === "---" ? 1 : 0; i < lines.length; i++) {
    const line = lines[i];
    if (/^ *(?:#.*)?$/.test(line)) continue;
    const m = line.match(/^([A-Za-z0-9_-]+):(?: +(.*?))? *$/);
    if (!m) {
      errors.push(`record line ${i + 1} is not a top-level key: ${line.trim()}`);
      continue;
    }
    const [, key, rest = ""] = m;
    if (key === "globs") {
      if (globs) errors.push("record holds globs twice");
      globs = [];
      if (rest) {
        let parsed;
        try {
          parsed = JSON.parse(rest);
        } catch {
          parsed = null;
        }
        const items = Array.isArray(parsed) ? parsed.map((g) => quotedString(JSON.stringify(g))) : [undefined];
        if (items.includes(undefined)) errors.push(`record line ${i + 1}: globs is not a list of double-quoted strings`);
        else globs.push(...items);
        continue;
      }
      while (i + 1 < lines.length && /^ +- /.test(lines[i + 1])) {
        i++;
        const item = quotedString(lines[i].replace(/^ +- +/, "").replace(/ +$/, ""));
        if (item === undefined) errors.push(`record line ${i + 1}: a glob is not a double-quoted string`);
        else globs.push(item);
      }
      continue;
    }
    if (!COMMAND_KEYS.includes(key)) {
      errors.push(`record holds ${key}, which a lane record may not hold`);
      continue;
    }
    if (Object.hasOwn(values, key)) {
      errors.push(`record holds ${key} twice`);
      continue;
    }
    const value = rest.startsWith('"') ? quotedString(rest) : undefined;
    if (value === undefined) {
      errors.push(`record line ${i + 1}: ${key} is not a double-quoted command string`);
      continue;
    }
    values[key] = value;
  }
  if (!globs || globs.length === 0) errors.push("record has no non-empty globs list");
  return { globs: globs ?? [], values, errors };
}

export function verifyRecord(recordText, assumedText, { ecosystem, src }) {
  const { entries, errors } = parseAssumed(assumedText);
  const record = parseRecord(recordText);
  errors.push(...record.errors);
  for (const [key, value] of Object.entries(record.values)) {
    const candidates = entries.filter((e) => e.ecosystem === ecosystem && e.key === key && e.value === value);
    if (!candidates.length) {
      errors.push(`${ecosystem}.${key}=${value}: no assumed: line from this run logs it`);
      continue;
    }
    const reasons = candidates.map((e) => checkSource(e, src).reason);
    if (!reasons.includes(null)) errors.push(`${ecosystem}.${key}=${value}: ${reasons.join("; ")}`);
  }
  return errors;
}

export function buildRecord(assumedText, { ecosystem, globs, src }) {
  const { entries, errors, skipped } = parseAssumed(assumedText);
  const notes = [...skipped];
  const values = {};
  const seen = {};
  for (const entry of entries.filter((e) => e.ecosystem === ecosystem)) {
    const checked = checkSource(entry, src);
    if (checked.reason) {
      errors.push(`${label(entry)}: ${checked.reason}`);
      continue;
    }
    if (Object.hasOwn(seen, entry.key) && seen[entry.key] !== entry.value) {
      errors.push(`${ecosystem}.${entry.key}: the run logged two different commands`);
      continue;
    }
    seen[entry.key] = entry.value;
    if (checked.kind === "recorded") {
      notes.push(`${label(entry)}: already recorded, not proposed`);
      continue;
    }
    values[entry.key] = entry.value;
  }
  if (!errors.length && !Object.keys(values).length) errors.push(`no assumed: line for ${ecosystem} to propose`);
  if (!globs.length || globs.some((g) => !g || hasUnsafe(g))) errors.push("give at least one non-empty --glob");
  if (errors.length) return { errors, notes };
  const text = renderRecord(globs, values);
  const recheck = verifyRecord(text, assumedText, { ecosystem, src });
  return recheck.length ? { errors: recheck, notes } : { text, values, notes };
}

function realAncestor(path) {
  const rest = [];
  for (let probe = path; ; probe = dirname(probe)) {
    try {
      return resolve(realpathSync(probe), ...rest);
    } catch {
      if (dirname(probe) === probe) return path;
      rest.unshift(basename(probe));
    }
  }
}

function outRefusal(repo, out) {
  let parent;
  try {
    parent = realpathSync(dirname(resolve(out)));
  } catch {
    return { usage: `the directory of ${out} does not exist` };
  }
  const target = resolve(parent, basename(out));
  const homeRecords = resolve(homedir(), ".claude", "ecosystems");
  const roots = [repo, gitToplevel(parent)].filter(Boolean);
  const inRecords = roots.some((root) => RECORDS_FOLDER.test(toPosix(relative(root, target))));
  const inHome = [homeRecords, realAncestor(homeRecords)].some((dir) => {
    const fromHome = toPosix(relative(dir.toLowerCase(), target.toLowerCase()));
    return fromHome !== ".." && !fromHome.startsWith("../") && !isAbsolute(fromHome);
  });
  if (inRecords || inHome) return { refused: `${out} is inside an ecosystem records folder; write the draft elsewhere` };
  return null;
}

const USAGE = `Usage:
  node lane-record.mjs write --ecosystem <id> --glob <pattern> [--glob <pattern>...] --out <file> [--base <ref>] [--repo <dir>] [--lines <file>]
  node lane-record.mjs verify --record <file> --base <ref> [--ecosystem <id>] [--repo <dir>] [--lines <file>]
The assumed: lines come from --lines, else standard input. --repo must be the root of a git work tree.
Each cited file is read at --base <ref>; write mode defaults to the merge-base with the default branch.
Exit 0: written or verified. Exit 1: refused, nothing written. Exit 2: usage or I/O error.
`;

function parseArgs(args) {
  const opts = { globs: [] };
  const mode = args[0];
  for (let i = 1; i < args.length; i += 2) {
    const flag = args[i];
    const value = args[i + 1];
    if (value === undefined) throw new Error(`${flag} needs a value`);
    if (flag === "--glob") opts.globs.push(value);
    else if (["--ecosystem", "--out", "--repo", "--record", "--lines", "--base"].includes(flag)) opts[flag.slice(2)] = value;
    else throw new Error(`unknown argument ${JSON.stringify(flag)}`);
  }
  return { mode, opts };
}

export async function main(args, stdinText) {
  if (args.includes("-h") || args.includes("--help")) {
    process.stdout.write(USAGE);
    return 0;
  }
  const usage = (message) => {
    process.stderr.write(`lane-record: ${message}\n${USAGE}`);
    return 2;
  };
  let mode;
  let opts;
  try {
    ({ mode, opts } = parseArgs(args));
  } catch (error) {
    return usage(error.message);
  }
  if (mode !== "write" && mode !== "verify") return usage("the mode is write or verify");
  if (mode === "verify" && !opts.base) return usage("verify needs --base <ref>, the commit the cited lines must already hold");
  let repo;
  let src;
  try {
    repo = gitRoot(opts.repo || gitToplevel(process.cwd()) || process.cwd());
    const base = opts.base ? { ref: opts.base, name: opts.base } : defaultBranchBase(repo);
    if (!base) throw new Error("cannot find the default branch to compare the cited files with");
    src = baseRevision(repo, base.ref, base.name);
  } catch (error) {
    return usage(error.message);
  }
  let input;
  try {
    input = stdinText ?? readFileSync(opts.lines ?? 0, "utf8");
  } catch (error) {
    return usage(`cannot read the assumed: lines: ${error.message}`);
  }
  const refuse = (errors) => {
    for (const e of errors) process.stderr.write(`refused: ${e}\n`);
    return 1;
  };
  if (mode === "verify") {
    if (!opts.record) return usage("verify needs --record");
    const ecosystem = opts.ecosystem ?? basename(opts.record).replace(/(?:\.local)?\.yaml$/, "");
    if (!ECOSYSTEM_ID.test(ecosystem)) return usage(`${JSON.stringify(ecosystem)} is not an ecosystem id`);
    let recordText;
    try {
      recordText = readFileSync(opts.record, "utf8");
    } catch (error) {
      return usage(`cannot read ${opts.record}: ${error.message}`);
    }
    const errors = verifyRecord(recordText, input, { ecosystem, src });
    if (errors.length) return refuse(errors);
    process.stdout.write(`verified: every command in ${opts.record} comes from an assumed: line of this run\n`);
    return 0;
  }
  if (!opts.ecosystem || !ECOSYSTEM_ID.test(opts.ecosystem) || !opts.out) return usage("write needs --ecosystem <id> and --out <file>");
  const outCheck = outRefusal(repo, opts.out);
  if (outCheck?.usage) return usage(outCheck.usage);
  if (outCheck?.refused) return refuse([outCheck.refused]);
  const built = buildRecord(input, { ecosystem: opts.ecosystem, globs: opts.globs, src });
  for (const note of built.notes) process.stderr.write(`note: ${note}\n`);
  if (built.errors) return refuse(built.errors);
  try {
    writeFileSync(opts.out, built.text, { flag: "wx" });
  } catch (error) {
    return usage(`cannot write ${opts.out} (it must not exist yet): ${error.message}`);
  }
  process.stdout.write(`wrote ${opts.out}: ${Object.keys(built.values).join(", ")}\n`);
  return 0;
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  process.exitCode = await main(process.argv.slice(2));
}
