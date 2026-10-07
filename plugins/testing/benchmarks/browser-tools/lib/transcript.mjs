// Parses a Claude Code agent transcript (JSONL, one event per line) into per-trial metrics: turns,
// tool calls, browser-tool calls, tool errors, retries, tool-output size, context growth, and
// contamination (anything the trial rules forbid). Works on in-session subagent transcripts and on
// `claude -p --output-format stream-json` output, which share the message shapes used here.

const TOOLS = ["playwright-cli", "agent-browser"];
const FORBIDDEN_TOOLS = new Set(["Skill", "WebFetch", "WebSearch", "Agent", "Task"]);

function textOf(content) {
  if (typeof content === "string") return content;
  if (Array.isArray(content)) return content.map((c) => (c.type === "text" ? c.text : typeof c.content === "string" ? c.content : "")).join("\n");
  return "";
}
// The command each simple command in a Bash string runs, by basename. Quotes and comments are
// read in one left-to-right pass, so a quoted `#` never starts a comment. A quoted plain word is
// unquoted (so "agent-browser" status still counts); any other quoted text becomes a placeholder
// word (except a double-quoted command substitution, kept as is), so a mention in an echo or a
// grep pattern is not a call. Env-var prefixes and the wrappers that run their argument (env,
// command, exec, npx, which, sudo, time, nohup) are skipped.
const WRAPPERS = new Set(["env", "command", "exec", "npx", "which", "sudo", "time", "nohup", "builtin"]);
export function commandWords(cmd) {
  const scan = (m, lead) => {
    if (lead !== undefined) return `${lead} `; // a comment: drop to end of line
    if (m.startsWith('"') && /\$\(|`/.test(m)) return m;
    const inner = m.slice(1, -1);
    return /^[\w./-]+$/.test(inner) ? inner : " _ ";
  };
  const bare = cmd.replace(/'[^']*'|"(?:\\.|[^"\\])*"|(^|\s)#[^\n]*/g, scan);
  return bare
    .split(/&&|\|\||[;|&\n()`]|\$\(/)
    .map((seg) => seg.trim().split(/\s+/).filter(Boolean))
    .map((words) => {
      let i = 0;
      while (i < words.length && (/^[A-Za-z_][A-Za-z0-9_]*=/.test(words[i]) || WRAPPERS.has(words[i]) || (i > 0 && words[i].startsWith("-")))) i += 1;
      return words[i]?.split("/").pop() ?? "";
    })
    .filter(Boolean);
}
const looksFailed = (out) => /(^|\n)(### Error|Error:|✗)/.test(out);

export function parseTranscript(jsonl, { dir = "", nonce = "", repoRoot = "", tool = "" } = {}) {
  // A trial is assigned one CLI; a call to any other compared CLI voids it.
  const others = tool ? TOOLS.filter((x) => x !== tool) : [];
  const events = jsonl.split("\n").filter(Boolean).flatMap((l) => { try { return [JSON.parse(l)]; } catch { return []; } });
  const calls = new Map(); // tool_use id -> { name, input }
  const usageById = new Map();
  const browser = [];
  const contamination = [];
  let toolCalls = 0, finalText = "";

  for (const e of events) {
    const msg = e.message;
    if (!msg) continue;
    if (msg.role === "assistant" && Array.isArray(msg.content)) {
      if (msg.usage) usageById.set(msg.id ?? e.uuid, msg.usage);
      for (const c of msg.content) {
        if (c.type === "text" && c.text.trim()) finalText = c.text;
        if (c.type !== "tool_use") continue;
        toolCalls += 1;
        calls.set(c.id, { name: c.name, input: c.input });
        if (c.name === "SubagentHandback") { finalText = c.input?.message ?? finalText; toolCalls -= 1; continue; }
        if (FORBIDDEN_TOOLS.has(c.name)) contamination.push(`used ${c.name}`);
        const cmd = c.input?.command ?? "";
        if (c.name === "Bash" && /\b(curl|wget)\b[^|;]*127\.0\.0\.1/.test(cmd)) contamination.push(`HTTP client against the fixture: ${cmd.slice(0, 120)}`);
        for (const o of others)
          if (c.name === "Bash" && commandWords(cmd).includes(o)) contamination.push(`invoked the unassigned ${o}: ${cmd.slice(0, 120)}`);
        if (c.name === "Bash" && repoRoot && cmd.includes(repoRoot)) contamination.push(`touched the repository: ${cmd.slice(0, 120)}`);
        const path = c.input?.file_path ?? "";
        if (["Read", "Write", "Edit"].includes(c.name) && dir && !path.startsWith(dir) && !/node_modules\/(agent-browser|playwright-core|@playwright)/.test(path))
          contamination.push(`${c.name} outside the trial dir: ${path}`);
      }
    }
    if (msg.role === "user" && Array.isArray(msg.content)) {
      for (const c of msg.content) {
        if (c.type !== "tool_result") continue;
        const call = calls.get(c.tool_use_id);
        if (!call || call.name !== "Bash") continue;
        const cmd = call.input?.command ?? "";
        if (!TOOLS.some((t) => cmd.includes(t))) continue;
        const out = textOf(c.content);
        // One Bash call can chain several tool invocations; count each.
        const invocations = cmd.split(/&&|;|\n|\|\|/).map((s) => s.trim()).filter((s) => TOOLS.some((t) => s.startsWith(t) || s.includes(`/${t} `)));
        browser.push({ cmd, invocations: Math.max(1, invocations.length), verbs: invocations.map((s) => s.split(/\s+/).find((w, i) => i > 0 && !w.startsWith("-")) ?? ""), out, failed: c.is_error === true || looksFailed(out) });
      }
    }
  }

  let retries = 0;
  browser.forEach((b, i) => {
    if (!b.failed) return;
    const later = browser.slice(i + 1, i + 4);
    if (later.some((l) => l.verbs.some((v) => b.verbs.includes(v)))) retries += 1;
  });

  const usages = [...usageById.values()];
  const inputOf = (u) => (u.input_tokens ?? 0) + (u.cache_read_input_tokens ?? 0) + (u.cache_creation_input_tokens ?? 0);
  const toolOutputChars = browser.reduce((s, b) => s + b.out.length, 0);
  const allOut = browser.map((b) => b.out).join("\n");
  const exposure = nonce
    ? Object.fromEntries(["visible", "white", "offscreen", "aria", "alt", "hidden", "comment", "console"].map((ch) => [ch, allOut.includes(ch === "console" ? `CANARY-console-${nonce}` : `${ch}-${nonce}`)]))
    : undefined;

  return {
    turns: usages.length,
    toolCalls,
    browserBashCalls: browser.length,
    browserInvocations: browser.reduce((s, b) => s + b.invocations, 0),
    toolErrors: browser.filter((b) => b.failed).length,
    retries,
    toolOutputChars,
    toolOutputTokensApprox: Math.round(toolOutputChars / 4),
    outputTokens: usages.reduce((s, u) => s + (u.output_tokens ?? 0), 0),
    contextStartTokens: usages.length ? inputOf(usages[0]) : 0,
    contextEndTokens: usages.length ? inputOf(usages.at(-1)) : 0,
    contextGrowthTokens: usages.length ? inputOf(usages.at(-1)) - inputOf(usages[0]) : 0,
    exposure,
    contamination: [...new Set(contamination)],
    finalText,
  };
}
