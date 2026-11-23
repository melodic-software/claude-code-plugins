import { existsSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { breakerStatus } from "./breaker.mjs";
import { query } from "./process.mjs";
import { EXIT, guardValues, oneLine, pickBinary, setup, Stop } from "./runner.mjs";
import { cacheFact, factsDir, installedVersion, MODELS_FILE } from "./update.mjs";

/** Output schema version of `external-agents models`; bump it on any change a consumer could notice. */
export const MODELS_SCHEMA = 1;

const PARSERS = {
  tab_lines: (text) =>
    text
      .split(/\r?\n/)
      .map((line) => line.trim())
      .filter(Boolean)
      .map((line) => {
        const [id, ...rest] = line.split("\t");
        return rest.length ? { id, name: rest.join("\t").trim() } : { id };
      }),
  codex_catalog: (text) =>
    JSON.parse(text)
      .models.filter((m) => m.visibility !== "hide")
      .map((m) => ({
        id: m.slug,
        name: m.display_name,
        efforts: (m.supported_reasoning_levels ?? []).map((level) => level.effort),
        default_effort: m.default_reasoning_level,
        ...(typeof m.context_window === "number" && Number.isFinite(m.context_window) && m.context_window > 0
          ? { context_window: m.context_window }
          : {}),
      })),
};

/** The effort choices a help text lists on the effort flag's line, as `(low|medium|high)`. */
export function effortChoices(help, flag) {
  const line = help.split(/\r?\n/).find((l) => l.trimStart().startsWith(flag) && /[\s,]/.test(l.trimStart()[flag.length] ?? " "));
  const choices = line?.match(/\(([a-z0-9]+(?:\|[a-z0-9]+)+)\)/);
  return choices ? choices[1].split("|") : null;
}

function fact(dir, name, args, ask) {
  const file = join(dir, `${name}.txt`);
  const cached = existsSync(file) ? readFileSync(file, "utf8") : "";
  if (cached.trim()) return cached;
  const got = cacheFact(dir, name, args, ask);
  if (got.skipped) throw new Stop("failed", got.skipped);
  return got.text;
}

/** The installed CLI's models and effort levels as one JSON document; never starts a model turn. */
export async function models(opts) {
  const product = opts.product ?? "external-agents";
  const out = (code, doc) => ({ code, stdout: `${JSON.stringify({ schema: MODELS_SCHEMA, product, ...doc }, null, 2)}\n`, stderr: "" });
  try {
    const state = setup(opts);
    const { ctx, record, settings } = state;
    if (!record.models) throw new Stop("unavailable", `the ${record.product} record names no model list command`);
    const { binary, missing } = pickBinary(ctx, record, settings);
    if (!binary) throw new Stop("unavailable", `${record.binary.name} not found (tried ${missing.tried.join(", ")}); install it, or set ${record.product}.binary_path`);
    guardValues(record, binary, {}, false);
    const ask = (args) => query(binary, args, { env: ctx.env, cwd: ctx.cwd });
    const { version } = installedVersion(record, ask);
    const dir = factsDir(ctx, record, version);
    const command = (args) => [record.binary.name, ...args].join(" ");

    let list;
    try {
      list = PARSERS[record.models.format](fact(dir, MODELS_FILE, record.models.args, ask));
    } catch (error) {
      throw error instanceof Stop ? error : new Stop("failed", `${command(record.models.args)} printed output this record cannot read (${oneLine(error.message)})`);
    }
    const doc = {
      status: "ok",
      cli: { name: record.binary.name, version },
      unset_model: record.unset_model,
      models: list,
      models_source: command(record.models.args),
    };
    const helpName = record.models.effort_help;
    if (helpName) {
      const args = record.help[helpName];
      doc.efforts = effortChoices(fact(dir, helpName, args, ask), record.effort_flag);
      if (!doc.efforts) throw new Stop("failed", `${command(args)} lists no ${record.effort_flag} choices this record can read`);
      doc.efforts_source = `${command(args)} (${record.effort_flag})`;
    }
    doc.tools = [...(record.harness?.tools ?? [])];
    doc.image = record.harness?.image ?? false;
    doc.breaker = breakerStatus(ctx.dataDir, record.product, ctx.now());
    doc.docs_index = record.docs_index;
    return { ...out(EXIT.ok, doc), stderr: state.notices.map((n) => `notice: ${n}\n`).join("") };
  } catch (error) {
    const reason = oneLine(error?.message ?? error);
    if (!(error instanceof Stop) || error.kind === "failed") return out(EXIT.failed, { status: "failed", reason });
    return out(error.kind === "refused" ? EXIT.usage : EXIT.unavailable, { status: error.kind, reason });
  }
}
