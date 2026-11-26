import { Buffer } from "node:buffer";
import { mkdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";

export const CAP = 32768;
export const MAIN_LOOP_ONLY = "the execution file holds main-loop messages only";

const textOf = (content) =>
  typeof content === "string" ? content : (content ?? []).map((block) => block?.text ?? "").join("\n");
const serialize = (value) => `${JSON.stringify(value, null, 2)}\n`;

export function turnCounts(messages) {
  const counts = { main_loop: 0, subagent: 0, main_loop_turns: 0, subagent_turns: 0 };
  const seen = new Set();
  messages.forEach((m, index) => {
    if (m?.type !== "assistant") return;
    const sub = m.parent_tool_use_id != null;
    counts[sub ? "subagent" : "main_loop"] += 1;
    const id = typeof m.message?.id === "string" ? m.message.id : `#${index}`;
    const key = `${sub}:${id}`;
    if (seen.has(key)) return;
    seen.add(key);
    counts[sub ? "subagent_turns" : "main_loop_turns"] += 1;
  });
  return counts.subagent === 0 ? { ...counts, note: MAIN_LOOP_ONLY } : counts;
}

export function actTurns(messages, { redact = (text) => text } = {}) {
  const result = messages.filter((m) => m?.type === "result").at(-1) ?? {};
  const stderr = messages
    .filter((m) => m?.type === "user")
    .map((m) => textOf(m.message?.content))
    .filter((text) => text.includes("<local-command-stderr>"));
  const models = Object.keys(result.modelUsage ?? {});
  const denials = result.permission_denials ?? [];
  const denied = denials.slice(0, 20).map((d) => {
    const i = d?.tool_input ?? {};
    const input = i.command ?? i.file_path ?? i.path ?? i.pattern ?? null;
    return { tool_name: String(d?.tool_name ?? "").slice(0, 100), input: input == null ? null : redact(String(input)).slice(0, 300) };
  });
  while (Buffer.byteLength(JSON.stringify(denied), "utf8") > 8192) denied.pop();
  const diag = {
    subtype: result.subtype == null ? null : String(result.subtype).slice(0, 100),
    is_error: result.is_error ?? null,
    num_turns: result.num_turns ?? null,
    turn_counts: turnCounts(messages),
    duration_ms: result.duration_ms ?? null,
    models: models.slice(0, 10).map((name) => name.slice(0, 100)),
    local_command_stderr: stderr.slice(0, 4).map((text) => redact(text).slice(0, 2000)),
    local_command_stderr_total: stderr.length,
    denied,
    denied_total: denials.length,
  };
  let text = serialize(diag);
  while (Buffer.byteLength(text, "utf8") > CAP && (diag.local_command_stderr.length > 0 || diag.denied.length > 0)) {
    if (diag.local_command_stderr.length > 0) diag.local_command_stderr.shift();
    else diag.denied.pop();
    text = serialize(diag);
  }
  return { diag, models, text };
}

export async function runStep({ core, executionFile, replyDir, redact, summary = false }) {
  const out = `${replyDir}/act-turns.json`;
  rmSync(out, { force: true });
  let messages;
  try {
    messages = JSON.parse(readFileSync(executionFile, "utf8"));
  } catch (error) {
    core.setFailed(`No readable execution file: ${error.code ?? error.name}`);
    return;
  }
  if (!Array.isArray(messages)) messages = [];
  const { diag, models, text } = actTurns(messages, { redact });
  mkdirSync(replyDir, { recursive: true });
  writeFileSync(out, text);
  if (summary) {
    const more = diag.denied_total - diag.denied.length;
    const shown = {
      ...diag,
      denied: [
        ...diag.denied.map((d) => (d.input == null ? d.tool_name : `${d.tool_name}: ${d.input}`)),
        ...(more > 0 ? [`(+${more} more)`] : []),
      ],
    };
    await core.summary
      .addHeading("Skill run", 3)
      .addCodeBlock(JSON.stringify(shown, null, 2).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;"), "json")
      .write();
  }
  core.info(JSON.stringify({ subtype: diag.subtype, is_error: diag.is_error, num_turns: diag.num_turns, models: models.length }));
  if (Number.isSafeInteger(diag.num_turns) && diag.num_turns >= 0) {
    core.setOutput("turns", String(diag.num_turns));
  }
  if (!(diag.num_turns > 0) || models.length === 0) {
    core.setFailed(
      "no-model-turn: the skill ended without a model turn, so it did nothing; " +
        "the step summary and the skill-reply artifact hold the result fields and any local-command stderr",
    );
  }
}
