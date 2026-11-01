// The "Check the skill took a model turn" step of pr-run-activity-read.yml and
// pr-run-activity-write.yml: reads the skill run's execution file, writes
// act-turns.json within the 32768-byte carry cap and sets the step's turns and
// models outputs. A slash command whose expansion fails ends with a `success`
// result and no model turn, so the act did nothing: that fails the step.
//
// Each runner copies this file out of the base before the model runs, with
// its SHA-256 as a step output, and the step imports only a copy that matches.
// It imports nothing but node: modules, so the step can load it from its bytes.
import { Buffer } from "node:buffer";
import { mkdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";

export const CAP = 32768;
export const MAIN_LOOP_ONLY = "the execution file holds main-loop messages only";

const textOf = (content) =>
  typeof content === "string" ? content : (content ?? []).map((block) => block?.text ?? "").join("\n");

// Assistant messages in the main loop (null parent_tool_use_id) and in
// subagents (set), as messages and as distinct model turns by message id, so a
// num_turns past --max-turns can be checked against the run's own evidence.
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

// The run fields act-turns.json records, with `redact` applied to every text
// the run produced, and the file's text, within CAP: the oldest stderr entries
// drop first, then denials from the end.
export function actTurns(messages, { redact = (text) => text } = {}) {
  const result = messages.filter((m) => m?.type === "result").at(-1) ?? {};
  const stderr = messages
    .filter((m) => m?.type === "user")
    .map((m) => textOf(m.message?.content))
    .filter((text) => text.includes("<local-command-stderr>"));
  const models = Object.keys(result.modelUsage ?? {});
  const diag = {
    subtype: result.subtype == null ? null : String(result.subtype).slice(0, 100),
    is_error: result.is_error ?? null,
    num_turns: result.num_turns ?? null,
    turn_counts: turnCounts(messages),
    duration_ms: result.duration_ms ?? null,
    models: models.slice(0, 10).map((name) => name.slice(0, 100)),
    // The CLI's own report of a failed slash command expansion: the first 4,
    // each cut to 2000 characters; local_command_stderr_total counts them all.
    local_command_stderr: stderr.slice(0, 4).map((text) => redact(text).slice(0, 2000)),
    local_command_stderr_total: stderr.length,
    // The first 20 calls the permission mode denied, each with its tool name
    // cut to 100 characters and its command, file_path, path or pattern cut to
    // 300; denied_total counts them all. Entries drop from the end until denied
    // serializes to at most 8192 bytes (a JSON-escaped control character is 6 bytes).
    denied: (() => {
      const kept = (result.permission_denials ?? []).slice(0, 20).map((d) => {
        const i = d?.tool_input ?? {};
        const input = i.command ?? i.file_path ?? i.path ?? i.pattern ?? null;
        return { tool_name: String(d?.tool_name ?? "").slice(0, 100), input: input == null ? null : redact(String(input)).slice(0, 300) };
      });
      while (Buffer.byteLength(JSON.stringify(kept), "utf8") > 8192) kept.pop();
      return kept;
    })(),
    denied_total: (result.permission_denials ?? []).length,
  };
  let text = `${JSON.stringify(diag, null, 2)}\n`;
  while (Buffer.byteLength(text, "utf8") > CAP && (diag.local_command_stderr.length > 0 || diag.denied.length > 0)) {
    if (diag.local_command_stderr.length > 0) diag.local_command_stderr.shift();
    else diag.denied.pop();
    text = `${JSON.stringify(diag, null, 2)}\n`;
  }
  return { diag, models, text };
}

// The step body. `summary` writes the run fields to the step summary: the
// write runner does; the read runner shows them only after its scan job's leak scan.
export async function runStep({ core, executionFile, replyDir, redact, summary = false }) {
  // Head code could have planted one; only this step's copy is uploaded.
  rmSync(`${replyDir}/act-turns.json`, { force: true });
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
  writeFileSync(`${replyDir}/act-turns.json`, text);
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
      // addCodeBlock does not escape its text.
      .addCodeBlock(JSON.stringify(shown, null, 2).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;"), "json")
      .write();
  }
  // JSON escapes newlines, so no field can start a workflow command.
  core.info(JSON.stringify({ subtype: diag.subtype, is_error: diag.is_error, num_turns: diag.num_turns, models: models.length }));
  if (Number.isSafeInteger(diag.num_turns) && diag.num_turns >= 0) {
    core.setOutput("turns", String(diag.num_turns));
  }
  // The CLI's modelUsage keys, the models the run used; the report job's
  // lane-record.mjs drops a list that fails its shape.
  core.setOutput("models", models.join(","));
  if (!(diag.num_turns > 0) || models.length === 0) {
    core.setFailed(
      "no-model-turn: the skill ended without a model turn, so it did nothing; " +
        "the step summary and the skill-reply artifact hold the result fields and any local-command stderr",
    );
  }
}
