#!/usr/bin/env node
import { createHash } from "node:crypto";
import { readFileSync, writeFileSync } from "node:fs";
import { join, resolve, win32 } from "node:path";
import { fileURLToPath } from "node:url";
import { escapeHtml } from "../../../lib/html-escape.mjs";
import { managedSettingsFiles, OptionsError, readOperatorOptions, resolveInstall } from "../../../lib/plugin-options.mjs";
import { buildView, ViewBuildError } from "../../../lib/view-builder.mjs";
import { findRoot, resolveBranding } from "../../../lib/view-settings.mjs";

const PLUGIN_ROOT = resolve(fileURLToPath(new URL("../../..", import.meta.url)));
const BRAND_CSS = [
  ".rv-brand { display: inline-flex; align-items: center; gap: 0.5rem; margin-right: auto; }",
  ".rv-brand svg { height: 1.5rem; width: auto; display: block; }",
  ".rv-brand-mark { display: inline-block; width: 1.5rem; height: 1.5rem; background-size: contain; background-repeat: no-repeat; background-position: center; }",
  ".rv-brand-label { font-family: var(--sans); font-weight: 600; font-size: 0.95rem; color: var(--fg); }",
].join("\n");

function readBrandingOption(explicitOption) {
  if (typeof explicitOption === "string" && explicitOption !== "" && !/^\$\{user_config\./.test(explicitOption)) {
    return explicitOption;
  }
  if (process.env.CLAUDE_PLUGIN_OPTION_BRANDING) {
    return process.env.CLAUDE_PLUGIN_OPTION_BRANDING;
  }
  try {
    return readOperatorOptions(resolveInstall(PLUGIN_ROOT), managedSettingsFiles(), ["branding"]).branding?.value ?? null;
  } catch (err) {
    if (err instanceof OptionsError) {
      process.stderr.write(`notice: branding userConfig: ${err.message}\n`);
      return null;
    }
    throw err;
  }
}

function applyBranding(template, tokensCss, branding) {
  const tokens = tokensCss.replace(/\r\n?/g, "\n").replace(/^(?:\s*\/\*[\s\S]*?\*\/\s*)+/, "").trim();
  const logo = branding?.logo;
  const parts = [];
  if (logo?.kind === "svg" && logo.svg) {
    parts.push(logo.svg);
  } else if (logo?.kind === "image") {
    parts.push(`<span class="rv-brand-mark rv-logo" role="img" aria-label="${escapeHtml(logo.label || "Brand logo")}"></span>`);
  }
  if (logo?.label) {
    parts.push(`<span class="rv-brand-label">${escapeHtml(logo.label)}</span>`);
  }
  const slot = parts.length ? `<div class="rv-brand">${parts.join("")}</div>` : "";
  const extraCss = [slot ? BRAND_CSS : "", branding?.css ?? ""].filter(Boolean).join("\n");
  let out = template.replace(/<style>\s*/i, (open) => `${open}${tokens}\n`);
  if (extraCss) out = out.replace(/<\/style>/i, (close) => `\n${extraCss}\n${close}`);
  if (slot) out = out.replace(/<div class="rv-bar">/i, (bar) => `${bar}${slot}`);
  return out;
}

const STAMP = /^\d{4}-\d{2}-\d{2}T\d{9}Z$/;
const FINDING_KEY = /^[a-z-]{1,16}:[0-9a-f]{16}$/;
const CHECK_ID = /^[a-z0-9-]{1,64}$/;
const REMEDIATION_ID = /^[a-z0-9-]{1,64}$/;
const SEVERITIES = ["crit", "warn", "unknown", "info", "ok"];
const ITEM_FIELDS_SHOWN = 8;
const TEXT_MAX = 300;
const RUN_PLACEHOLDER = 'value="run-stamp"';
const EXCLUSION_WITHHELD = "(exclusion value withheld)";

export class CheckupInputError extends Error {}

const isScalar = (value) => ["string", "number", "boolean"].includes(typeof value);
const text = (value) => {
  if (!isScalar(value)) {
    return "";
  }
  const flat = String(value).replace(/[\p{Cc}\p{Zl}\p{Zp}\p{Bidi_Control}]/gu, " ");
  return flat.length > TEXT_MAX ? `${flat.slice(0, TEXT_MAX - 3)}...` : flat;
};
const severity = (value) => {
  const s = typeof value === "string" ? value.toLowerCase() : "";
  return SEVERITIES.includes(s) ? s : "unknown";
};
const isObject = (value) => value !== null && typeof value === "object" && !Array.isArray(value);

function itemEvidence(item, exclusion) {
  const hidden = ["key", "severity", "muted", "title", ...(exclusion ? ["value"] : [])];
  return Object.entries(item)
    .filter(([name, value]) => !hidden.includes(name) && isScalar(value))
    .slice(0, ITEM_FIELDS_SHOWN)
    .map(([name, value]) => text(`${name}: ${value}`));
}

/**
 * The page data and the id map rows for one run. Pure: no file access.
 *
 * @param {unknown} latest the parsed latest.json
 * @param {string[]} remediations the shipped remediation ids
 * @param {string} report the file name of the run's markdown report
 * @returns {{ data: object, rows: Record<string, object> }}
 */
export function toCheckupData(latest, remediations, report) {
  if (!isObject(latest) || !Array.isArray(latest.checks)) {
    throw new CheckupInputError("latest.json holds no checks array");
  }
  const rows = {};
  const checks = latest.checks
    .filter(isObject)
    .map((check, order) => ({ check, order, rank: SEVERITIES.indexOf(severity(check.severity)) }))
    .sort((a, b) => a.rank - b.rank || a.order - b.order)
    .map(({ check }) => check);

  const areas = checks.map((check, a) => {
    const checkId = typeof check.id === "string" && CHECK_ID.test(check.id) ? check.id : null;
    const listed = isObject(check.detail) && Array.isArray(check.detail.items) ? check.detail.items.filter(isObject) : [];
    const items = listed.map((item, i) => {
      const keyed = typeof item.key === "string" && FINDING_KEY.test(item.key);
      const mutable = checkId !== null && keyed && item.muted !== true;
      const exclusion = keyed && item.key.startsWith("exclusion:");
      const title = exclusion ? [EXCLUSION_WITHHELD, text(item.exclusion_type), text(item.change)].filter(Boolean).join(" ") : text(item.title);
      if (mutable) {
        rows[`areas-${a + 1}-items-${i + 1}-mute-1`] = { action: "mute", check_id: checkId, finding_key: item.key, label: title };
      }
      return {
        title,
        severity: severity(item.severity),
        detail: item.muted === true ? "muted" : mutable ? "" : "cannot be muted",
        evidence: itemEvidence(item, exclusion),
        mute: mutable ? [{ label: "Mute this item" }] : [],
      };
    });
    return {
      title: text(check.id) || "unnamed check",
      severity: severity(check.severity),
      summary: text(check.summary),
      count: items.length ? `${items.length} item${items.length === 1 ? "" : "s"}` : "no items",
      items,
    };
  });

  const offered = remediations.filter((id) => REMEDIATION_ID.test(id));
  offered.forEach((id, r) => {
    rows[`remediations-${r + 1}`] = { action: "approve", remediation_id: id };
  });

  const counts = SEVERITIES.map((s) => `${checks.filter((c) => severity(c.severity) === s).length} ${s.toUpperCase()}`).join(", ");
  const run = {
    host: text(latest.hostname),
    "ran-at": text(latest.run_id),
    elevated: latest.elevated === true ? "elevated" : "not elevated",
    report: text(report),
  };
  if (typeof latest.discovery_path === "string" && latest.discovery_path) {
    run.notes = text(win32.basename(latest.discovery_path));
  }
  return {
    data: {
      run: [run],
      counts,
      areas,
      remediations: offered.map((id) => ({ title: id })),
    },
    rows,
  };
}

/** The template with its hidden run choice set to the lowercased run stamp. */
export function withRunChoice(template, runStamp) {
  if (!STAMP.test(runStamp) || template.split(RUN_PLACEHOLDER).length !== 2) {
    throw new CheckupInputError("the template needs exactly one run choice placeholder and a valid run stamp");
  }
  return template.replace(RUN_PLACEHOLDER, `value="${runStamp.toLowerCase()}"`);
}

function main(argv) {
  const args = {};
  for (let i = 0; i < argv.length; i += 2) {
    args[argv[i]] = argv[i + 1];
  }
  const required = ["--latest", "--views-dir", "--run-stamp", "--remediations", "--report"];
  const known = [...required, "--branding-option"];
  const ok =
    argv.length % 2 === 0 &&
    required.every((key) => typeof args[key] === "string") &&
    Object.entries(args).every(([key, value]) => known.includes(key) && typeof value === "string" && (value !== "" || key === "--remediations" || key === "--branding-option"));
  if (!ok || !STAMP.test(args["--run-stamp"])) {
    console.error("usage: build-checkup-view.mjs --latest <latest.json> --views-dir <dir> --run-stamp <yyyy-MM-ddTHHmmssfffZ> --remediations <id,id> --report <file name> [--branding-option <value>]");
    return 2;
  }
  const stamp = args["--run-stamp"];
  let latest;
  let template;
  try {
    latest = JSON.parse(readFileSync(args["--latest"], "utf8").replace(/^\uFEFF/, ""));
    template = readFileSync(new URL("../templates/checkup.html", import.meta.url), "utf8");
  } catch (err) {
    console.error(err.message);
    return err instanceof SyntaxError ? 1 : 2;
  }
  try {
    const remediations = args["--remediations"].split(",").filter(Boolean);
    const { data, rows } = toCheckupData(latest, remediations, args["--report"]);
    const tokensCss = readFileSync(new URL("../../../reference/html-tokens.css", import.meta.url), "utf8");
    const branding = resolveBranding({ userConfig: readBrandingOption(args["--branding-option"] ?? null), projectRoot: findRoot() });
    for (const notice of branding.notices) {
      process.stderr.write(`notice: ${notice.text}\n`);
    }
    const branded = applyBranding(withRunChoice(template, stamp), tokensCss, branding);
    const page = buildView({ profile: "interactive", template: branded, data });
    const base = join(args["--views-dir"], `checkup-${stamp}`);
    const idMap = {
      format: "checkup-ids/1",
      run_id: text(latest.run_id),
      built_at: new Date().toISOString(),
      page_sha256: createHash("sha256").update(page, "utf8").digest("hex"),
      rows,
    };
    writeFileSync(`${base}.json`, JSON.stringify(data, null, 2));
    writeFileSync(`${base}.ids.json`, JSON.stringify(idMap, null, 2));
    writeFileSync(`${base}.html`, page);
    console.log(`${base}.html`);
    return 0;
  } catch (err) {
    console.error(err.message);
    return err instanceof ViewBuildError || err instanceof CheckupInputError ? 1 : 2;
  }
}

if (process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1]) {
  process.exitCode = main(process.argv.slice(2));
}
