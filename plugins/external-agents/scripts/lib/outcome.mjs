const isMap = (v) => v !== null && typeof v === "object" && !Array.isArray(v);

const parseObject = (text) => {
  try {
    const value = JSON.parse(text);
    return isMap(value) ? value : null;
  } catch {
    return null;
  }
};

const lastLine = (text) => text.split(/\r?\n/).map((l) => l.trim()).filter(Boolean).at(-1) ?? "";

function readEvents(output, stdout) {
  const seen = { thread: null, lastStage: null, errors: [], items: [] };
  for (const line of stdout.split(/\r?\n/)) {
    if (!line.startsWith("{")) continue;
    const event = parseObject(line);
    if (typeof event?.type !== "string") continue;
    if (event.type === output.thread_event && seen.thread === null) seen.thread = event[output.thread_field] ?? null;
    if (output.failure_events.includes(event.type)) seen.errors.push(event.error?.message ?? event.message ?? event.type);
    if (event.type === output.item_event && isMap(event.item)) seen.items.push(event.item);
    if (!event.type.startsWith(output.item_prefix)) seen.lastStage = event.type;
  }
  return seen;
}

function deniedItems(rules, items) {
  const denied = [];
  for (const item of items) {
    const hit = rules.some((rule) => {
      if (rule.kind !== "json_item_failed" || !rule.item_types.includes(item.type)) return false;
      if (!(rule.statuses ?? ["failed"]).includes(item.status)) return false;
      const text = rule.text_field === undefined ? undefined : item[rule.text_field];
      const cannotRuleOutRefusal = typeof text !== "string";
      return cannotRuleOutRefusal || rule.patterns.some((p) => text.includes(p));
    });
    if (hit) denied.push(item);
  }
  return denied;
}

const describe = (item) => item.command ?? (Array.isArray(item.changes) ? item.changes.map((c) => c.path).join(", ") : item.type);

function unavailable(record, text, now) {
  for (const rule of record.unavailable ?? []) {
    if (!rule.patterns.some((p) => text.includes(p))) continue;
    let resetAt = null;
    const stated = rule.reset_pattern && new RegExp(rule.reset_pattern).exec(text)?.[1];
    if (stated) {
      const at = Date.parse(stated.replace(/(\d)(st|nd|rd|th)\b/g, "$1"));
      if (Number.isFinite(at) && at > now) resetAt = new Date(at).toISOString();
    }
    return { class: rule.class, reset_at: resetAt };
  }
  return null;
}

/**
 * @returns the fields a finished run adds to its job file. `status` is `ok` only when every
 * success condition holds; a refusal the mode caused wins over every other reading.
 */
export function classify(record, { exitCode, stdout, stderr, finalMessage, mode, now = Date.now() }) {
  const output = record.output;
  let thread = null;
  let message = finalMessage ?? "";
  let denied = [];
  let failedCommands = [];
  let mcp = [];
  let error = null;
  const why = [];

  if (output.kind === "jsonl_events") {
    const seen = readEvents(output, stdout);
    thread = seen.thread;
    const deniedSet = deniedItems(record.soft_deny, seen.items);
    denied = deniedSet.map(describe);
    failedCommands = seen.items.filter((i) => i.status === "failed" && !deniedSet.includes(i)).map(describe);
    mcp = seen.items.filter((i) => (output.mcp_item_types ?? []).includes(i.type)).map((i) => `${i.server}.${i.tool}`);
    if (seen.errors.length) {
      error = seen.errors.at(-1);
      why.push(error);
    } else if (seen.lastStage !== output.turn_ok_event) {
      why.push(`the run ended without ${output.turn_ok_event}`);
    }
  } else {
    const envelope = parseObject(stdout.trim()) ?? parseObject(lastLine(stdout));
    if (!envelope) {
      why.push("no JSON result on stdout");
    } else {
      thread = envelope[output.thread_field] ?? null;
      message = typeof envelope[output.message_field] === "string" ? envelope[output.message_field] : "";
      if (envelope[output.error_field]) error = String(envelope[output.error_field]);
      for (const rule of record.soft_deny) {
        if (rule.kind !== "json_array_nonempty" || !Array.isArray(envelope[rule.field])) continue;
        denied.push(...envelope[rule.field].map((d) => d?.display_name ?? d?.action ?? JSON.stringify(d)));
      }
      if (envelope[output.status_field] !== output.success_value) why.push(error ?? `${output.status_field} is ${JSON.stringify(envelope[output.status_field])}`);
    }
    for (const rule of record.soft_deny) {
      if (rule.kind === "stderr_substring" && stderr.includes(rule.text) && denied.length === 0) denied.push(rule.text);
    }
  }

  let printed = null;
  if (exitCode !== 0) {
    const lines = stderr.split(/\r?\n/).map((l) => l.trim()).filter(Boolean);
    printed = lines.find((l) => /^error\b/i.test(l)) ?? lines.at(-1) ?? null;
    if (error === null && printed) why.unshift(printed);
    why.unshift(`exit ${exitCode}`);
  }
  if (message.trim() === "" && !why.length) why.push("no final message");

  const notices = [];
  const fallback = record.modes[mode]?.fallback_warning;
  if (fallback && stderr.includes(fallback.pattern)) {
    notices.push(`the CLI warned: ${fallback.pattern}`);
    if (fallback.severity === "downgrade") why.push(`the ${mode} mode was not applied`);
  }

  const status = denied.length ? "blocked-by-mode" : why.length ? "failed" : "ok";
  return {
    status,
    reason: why.length ? [...new Set(why)].join("; ") : null,
    thread_id: thread,
    message,
    denied_commands: { count: denied.length, commands: denied },
    failed_commands: { count: failedCommands.length, commands: failedCommands },
    mcp_calls: { count: mcp.length, tools: [...new Set(mcp)] },
    last_error: error ?? printed,
    unavailable: status === "failed" && error ? unavailable(record, error, now) : null,
    notices,
  };
}
