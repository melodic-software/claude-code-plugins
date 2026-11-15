#!/usr/bin/env node
import { spawnSync } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { toolArgs } from "./tlc.ts";

const here = path.dirname(fileURLToPath(import.meta.url));
const corpus = path.join(here, "corpus");
const names = process.argv.slice(2);
if (!process.env.TLA2TOOLS) {
  console.error("Set TLA2TOOLS to the path of tla2tools.jar: this script records TLC's real output.");
  process.exit(2);
}

for (const name of names.length ? names : fs.readdirSync(corpus)) {
  const dir = path.join(corpus, name);
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "statechart-update-"));
  try {
    const tlc = path.join(tmp, "tlc");
    const out = path.join(tmp, "out");
    fs.mkdirSync(tlc);
    const view = path.join(dir, "view.mjs");
    const r = spawnSync(
      process.execPath,
      [
        path.join(here, "../statechart.ts"),
        path.join(dir, `${name}.tla`),
        ...(fs.existsSync(view) ? ["--view", view] : []),
        "--out",
        out,
        ...toolArgs(path.join(here, "java.ts")),
      ],
      {
        encoding: "utf8",
        env: { ...process.env, STATECHART_JAVA: process.env.JAVA ?? "java", STATECHART_RECORD: tlc },
      },
    );
    if (r.stderr) {
      console.error(`${name}: ${r.stderr}`);
      process.exitCode = 1;
      continue;
    }
    for (const f of fs.readdirSync(dir))
      if (/\.(out|exit|dot|mmd|md)$/.test(f)) fs.rmSync(path.join(dir, f));
    for (const f of fs.readdirSync(tlc)) fs.copyFileSync(path.join(tlc, f), path.join(dir, f));
    for (const f of ["chart.mmd", "report.md"]) fs.copyFileSync(path.join(out, f), path.join(dir, f));
    console.log(`updated ${name}`);
  } finally {
    fs.rmSync(tmp, { recursive: true, force: true });
  }
}
