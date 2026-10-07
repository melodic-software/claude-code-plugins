#!/usr/bin/env node
// L1: scripted runs of every fixture through each CLI, with no model in the loop. Measures whether
// the obvious command sequence works, wall time, command count and snapshot output size.
//
//   node run-l1.mjs --out results/<date>/l1.json [--tools playwright-cli,agent-browser]
//                   [--delays 0,1500] [--repeat 1] [--base http://127.0.0.1:4400]
//
// Tool binaries resolve from PLAYWRIGHT_CLI_BIN / AGENT_BROWSER_BIN, else from PATH. Both are pointed
// at the same Chromium (BT_CHROME) so the browser build is not a variable; set it to a Chromium the
// pinned playwright-cli can drive.

import { execFile } from "node:child_process";
import { mkdirSync, mkdtempSync, writeFileSync, readFileSync, statSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fixtures } from "./lib/cases.mjs";

const arg = (k, d) => { const i = process.argv.indexOf(`--${k}`); return i > 0 ? process.argv[i + 1] : d; };
const base = arg("base", "http://127.0.0.1:4400");
const outFile = arg("out", `results/${new Date().toISOString().slice(0, 10)}/l1.json`);
const toolNames = arg("tools", "playwright-cli,agent-browser").split(",");
const delays = arg("delays", "0,1500").split(",").map(Number);
const repeat = Number(arg("repeat", 1));
const only = arg("only", "");
const chrome = process.env.BT_CHROME;
const pwBin = process.env.PLAYWRIGHT_CLI_BIN ?? "playwright-cli";
const abBin = process.env.AGENT_BROWSER_BIN ?? "agent-browser";
const work = mkdtempSync(join(tmpdir(), "bt-l1-"));
const uploadFile = join(work, "receipt.txt");
writeFileSync(uploadFile, "receipt for benchmark upload\n");
const uploadSize = statSync(uploadFile).size;
const pwConfig = join(work, "pw.config.json");
writeFileSync(pwConfig, JSON.stringify({ browser: { browserName: "chromium", launchOptions: { headless: true, ...(chrome ? { executablePath: chrome } : {}) } } }));

function sh(bin, args, cwd, env = {}) {
  const t = Date.now();
  return new Promise((resolve) =>
    execFile(bin, args, { cwd, env: { ...process.env, ...env }, timeout: 60000, maxBuffer: 32 << 20 }, (err, stdout, stderr) =>
      resolve({ ok: !err, code: err?.code ?? 0, out: String(stdout), err: String(stderr), ms: Date.now() - t }),
    ),
  );
}

// Each adapter maps the tool-agnostic ops onto that CLI's documented commands.
const adapters = {
  "playwright-cli": (session, cwd) => {
    const run = (...a) => sh(pwBin, [`-s=${session}`, ...a], cwd);
    return {
      version: () => sh(pwBin, ["--version"], cwd),
      open: (u) => run("open", `--config=${pwConfig}`, u),
      snapshot: () => run("snapshot"),
      click: (ref) => run("click", ref),
      fill: (ref, text) => run("fill", ref, text),
      press: (key) => run("press", key),
      eval: (js) => run("--raw", "eval", `() => (${js})`),
      dismissDialog: () => run("dialog-dismiss"),
      tabLast: async () => { const l = await run("tab-list"); const n = (l.out.match(/^- \d+:/gm) ?? []).length; return run("tab-select", String(Math.max(0, n - 1))); },
      mouseClick: async (x, y) => { await run("mousemove", String(x), String(y)); await run("mousedown"); return run("mouseup"); },
      upload: async (ref) => { await run("click", ref); return run("upload", uploadFile); },
      download: async (ref) => {
        const r = await run("click", ref);
        await new Promise((res) => setTimeout(res, 800));
        const m = r.out.match(/Downloaded file .* to "([^"]+)"/);
        return { ...r, file: m ? join(cwd, m[1]) : null };
      },
      close: () => run("close"),
    };
  },
  "agent-browser": (session, cwd) => {
    const env = chrome ? { AGENT_BROWSER_EXECUTABLE_PATH: chrome } : {};
    const run = (...a) => sh(abBin, ["--session", session, ...a], cwd, env);
    return {
      version: () => sh(abBin, ["--version"], cwd),
      open: (u) => run("open", u),
      snapshot: () => run("snapshot"),
      click: (ref) => run("click", `@${ref}`),
      fill: (ref, text) => run("fill", `@${ref}`, text),
      press: (key) => run("press", key),
      eval: (js) => run("eval", js),
      dismissDialog: () => run("dialog", "dismiss"),
      tabLast: async () => { const l = await run("tab", "list"); const ids = [...l.out.matchAll(/\[(t\d+)\]/g)].map((x) => x[1]); return run("tab", ids.at(-1) ?? "t1"); },
      mouseClick: async (x, y) => { await run("mouse", "move", String(x), String(y)); await run("mouse", "down"); return run("mouse", "up"); },
      upload: () => run("upload", "input[type=file]", uploadFile),
      download: async (ref) => { const path = join(cwd, "report.txt"); const r = await run("download", `@${ref}`, path); return { ...r, file: path }; },
      close: () => run("close"),
    };
  },
};

const findRef = (snap, name) => {
  const line = snap.split("\n").find((l) => l.includes(`"${name}"`) && /ref=/.test(l));
  return line?.match(/ref=([a-z0-9]+)/i)?.[1];
};
const parseEval = (out) => { const s = out.trim(); try { return JSON.parse(s); } catch { return s; } };

async function runFixture(tool, f, variant, delay, rep) {
  const runId = `l1-${tool}-${f.id}${variant ? variant : ""}-d${delay}-r${rep}-${Date.now().toString(36)}`;
  const cwd = mkdtempSync(join(work, `${f.id}-`));
  const session = runId.replace(/[^a-z0-9-]/gi, "").slice(-40);
  const t = adapters[tool](session, cwd);
  const url = `${base}/f/${f.path}?run=${runId}&delay=${delay}${variant ? `&variant=${variant}` : ""}`;
  const m = { commands: 0, snapshotBytes: 0, errors: [] };
  let answer = "", dismissNext = false;
  const track = (r, what) => { m.commands += 1; if (!r.ok) m.errors.push({ what, code: r.code, msg: (r.err || r.out).trim().slice(0, 300) }); return r; };
  const snapRef = async (name) => {
    const s = track(await t.snapshot(), "snapshot");
    m.snapshotBytes += s.out.length;
    const ref = findRef(s.out, name);
    if (!ref) m.errors.push({ what: `ref "${name}"`, msg: "not found in snapshot" });
    return ref;
  };
  const start = Date.now();
  for (const step of f.steps) {
    switch (step.op) {
      case "open": track(await t.open(url), "open"); break;
      case "clickName": { const ref = await snapRef(step.name); if (ref) { track(await t.click(ref), `click ${step.name}`); if (dismissNext) { track(await t.dismissDialog(), "dialog dismiss"); dismissNext = false; } } break; }
      case "clickNameIfVariant": if (variant === step.variant) { const ref = await snapRef(step.name); if (ref) track(await t.click(ref), `click ${step.name}`); } break;
      case "fillName": { const ref = await snapRef(step.name); if (ref) track(await t.fill(ref, step.text), `fill ${step.name}`); break; }
      case "press": track(await t.press(step.key), `press ${step.key}`); break;
      case "dialog": if (variant !== "B") dismissNext = true; break;
      case "waitMs": await new Promise((r) => setTimeout(r, step.ms)); break;
      case "waitText": {
        const end = Date.now() + 10000;
        let seen = false;
        while (!seen && Date.now() < end) {
          const r = await t.eval(`document.body.innerText.includes(${JSON.stringify(step.text)})`);
          m.commands += 1;
          seen = parseEval(r.out) === true;
          if (!seen) await new Promise((res) => setTimeout(res, 250));
        }
        if (!seen) m.errors.push({ what: `waitText ${step.text}`, msg: "timeout" });
        break;
      }
      case "read": { const r = track(await t.eval(step.js), "read"); answer += ` ${parseEval(r.out)}`; break; }
      case "scrollTo": track(await t.eval(`(${step.js}, true)`), "scroll"); break;
      case "tabLast": track(await t.tabLast(), "tab"); break;
      case "clickCanvas": { const r = track(await t.eval(step.js), "coords"); const [x, y] = parseEval(r.out) ?? []; track(await t.mouseClick(x, y), "mouse click"); break; }
      case "upload": {
        if (tool === "playwright-cli") { const ref = await snapRef(variant === "B" ? "Choose receipt file" : "Receipt file"); if (ref) track(await t.upload(ref), "upload"); }
        else track(await t.upload(), "upload");
        break;
      }
      case "download": {
        const ref = await snapRef(variant === "B" ? "Export quarterly report" : "Download quarterly report");
        if (ref) { const r = track(await t.download(ref), "download"); try { if (r.file) answer += readFileSync(r.file, "utf8"); } catch (e) { m.errors.push({ what: "read download", msg: e.message }); } }
        break;
      }
    }
  }
  await new Promise((r) => setTimeout(r, 400));
  const wallMs = Date.now() - start;
  await t.close();
  const state = await (await fetch(`${base}/__state?run=${runId}`)).json();
  const pass = !!f.grade(state, answer, { uploadSize, variant });
  return { tool, fixture: f.id, variant: variant ?? null, delay, rep, pass, wallMs, ...m, answer: answer.trim().slice(0, 200) };
}

const versions = {};
for (const tool of toolNames) versions[tool] = (await adapters[tool]("v", work).version()).out.trim();
const results = [];
for (let rep = 1; rep <= repeat; rep++)
  for (const delay of delays)
    for (const f of fixtures.filter((x) => !only || only.split(",").includes(x.id)))
      for (const variant of f.variants ?? [undefined])
        for (const tool of toolNames) {
          const r = await runFixture(tool, f, variant, delay, rep);
          results.push(r);
          console.log(`${r.pass ? "PASS" : "FAIL"} ${tool.padEnd(14)} ${f.id}${variant ?? ""} d${delay} ${r.wallMs}ms snap=${r.snapshotBytes}B${r.errors.length ? `  ${r.errors.map((e) => `${e.what}: ${e.msg}`).join(" | ").slice(0, 160)}` : ""}`);
        }

mkdirSync(dirname(outFile), { recursive: true });
writeFileSync(outFile, JSON.stringify({ layer: "L1", at: new Date().toISOString(), base, chrome: chrome ?? "tool default", versions, delays, repeat, results }, null, 2) + "\n");
console.log(`\nwrote ${outFile}`);
