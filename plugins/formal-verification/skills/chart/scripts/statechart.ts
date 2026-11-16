#!/usr/bin/env node
import { type ChildProcess, spawn } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { parseArgs } from "node:util";
import { CHART_STATES, DEFAULT_LIMITS, RERUN_STATES } from "./ir.ts";
import { killGroup, messageOf } from "./run.ts";
import { checkSpecName, childEnv, freshOut } from "./stage.ts";

const MAX_TIMEOUT_SECONDS = Math.floor((2 ** 31 - 1) / 1000);

const USAGE = `Usage: statechart SPEC.tla --jar FILE [--java FILE] [--chart-states N] [--rerun-states N]
                  [--timeout-seconds N] [--heap SIZE] [--output-bytes N] [--interval-max N]
                  [--modules A,B] [--config FILE] [--view FILE] [--out DIR]

Checks SPEC.tla with TLC and draws its state graph as Mermaid. Above the chart budget, the
chart draws only the paths to the rules that break, and with no rule broken there is no
chart.mmd. The command installs nothing: it runs the jar and the Java you name.
  --jar FILE          tla2tools.jar, the TLC model checker.
  --java FILE         The java binary, Java 11 or later. Default: java on PATH.
  --chart-states N    The chart budget in distinct states. Default: ${CHART_STATES}.
  --rerun-states N    After the first break, each TLC run stops at N distinct states.
                      Default: ${RERUN_STATES}.
  --timeout-seconds N Each Java run is killed after N seconds, at most ${MAX_TIMEOUT_SECONDS}.
                      Default: ${DEFAULT_LIMITS.timeoutSeconds}.
  --heap SIZE         The Java heap cap, as -Xmx takes it. Default: ${DEFAULT_LIMITS.heap}.
  --output-bytes N    Each Java run is killed once it prints N bytes. Default: ${DEFAULT_LIMITS.outputBytes}.
  --interval-max N    A larger interval reaches the view as {lo, hi}. Default: ${DEFAULT_LIMITS.intervalMax}.
  --modules A,B       The standard modules a spec may use. Default: ${DEFAULT_LIMITS.modules.join(",")}.
  The view file is code: never pass one taken from untrusted content.
  --config FILE  TLC config. Default: SPEC.cfg beside the spec.
  --view FILE    A module that exports state(vars) and, if you want, step(action, from, to),
                 group(vars), colors, and title. state() returns a string for a flat chart, an
                 array for parent states, or an object for regions. Default: each state's values.
                 colors gives each group blue, orange, purple, yellow, teal, tan, or pink.
  --out DIR      Where to write report.md, chart.mmd, tlc.out, and tlc-RULE.out for each
                 property that breaks and each rule that breaks off the chart. The folder must
                 be new or empty. Default: SPEC-chart.
Exit code: TLC's own on the config as written: 0 when every rule holds, 1 when a rule breaks,
and 2 when TLC stops with an error, a signal kills the check, or the command cannot run. 130 or
143 when SIGINT or SIGTERM stops the check. Only exits 0 and 1 write output.`;

let stop: NodeJS.Signals | undefined;
const stopped = new Promise<void>((resolve) => {
  for (const name of ["SIGINT", "SIGTERM"] as const)
    process.on(name, () => {
      stop ??= name;
      resolve();
    });
});

let flags;
let specFile;
try {
  const args = parseArgs({
    allowPositionals: true,
    options: {
      config: { type: "string" },
      view: { type: "string" },
      out: { type: "string" },
      jar: { type: "string" },
      java: { type: "string" },
      "chart-states": { type: "string" },
      "rerun-states": { type: "string" },
      "timeout-seconds": { type: "string" },
      heap: { type: "string" },
      "output-bytes": { type: "string" },
      "interval-max": { type: "string" },
      modules: { type: "string" },
    },
  });
  flags = args.values;
  [specFile] = args.positionals;
  if (args.positionals.length !== 1) throw new Error("Give one SPEC.tla.");
  checkSpecName(specFile);
  if (!flags.jar)
    throw new Error("Give --jar with the path of tla2tools.jar. The command installs nothing.");
  for (const name of [
    "chart-states",
    "rerun-states",
    "timeout-seconds",
    "output-bytes",
    "interval-max",
  ] as const)
    if (flags[name] !== undefined && !/^[1-9][0-9]*$/.test(flags[name]))
      throw new Error(`--${name} must be a positive whole number.`);
  if (Number(flags["timeout-seconds"]) > MAX_TIMEOUT_SECONDS)
    throw new Error(`--timeout-seconds must be at most ${MAX_TIMEOUT_SECONDS}.`);
  if (flags.heap !== undefined && !/^[1-9][0-9]*[kKmMgG]?$/.test(flags.heap))
    throw new Error("--heap must be a size such as 4g or 512m.");
  if (flags.modules !== undefined && !/^\w+(,\w+)*$/.test(flags.modules))
    throw new Error("--modules must be module names separated by commas.");
} catch (error) {
  console.error(`${messageOf(error)}\n\n${USAGE}`);
  process.exit(2);
}

const codeOf = (error: unknown) =>
  error instanceof Error && "code" in error ? error.code : undefined;

try {
  const configFile = flags.config ?? specFile.replace(/\.tla$/, ".cfg");
  if (!fs.existsSync(configFile))
    throw new Error(`Cannot find the TLC config ${configFile}. Pass --config FILE.`);
  const out = flags.out ?? specFile.replace(/\.tla$/, "-chart");
  const dest = freshOut(out);
  const options = {
    jar: flags.jar,
    java: flags.java ?? "java",
    bounds: {
      chartStates: Number(flags["chart-states"] ?? CHART_STATES),
      rerunStates: Number(flags["rerun-states"] ?? RERUN_STATES),
    },
    limits: {
      timeoutSeconds: Number(flags["timeout-seconds"] ?? DEFAULT_LIMITS.timeoutSeconds),
      heap: flags.heap ?? DEFAULT_LIMITS.heap,
      outputBytes: Number(flags["output-bytes"] ?? DEFAULT_LIMITS.outputBytes),
      intervalMax: Number(flags["interval-max"] ?? DEFAULT_LIMITS.intervalMax),
      modules: flags.modules ? flags.modules.split(",") : DEFAULT_LIMITS.modules,
    },
  };

  let base = path.dirname(dest);
  while (!fs.existsSync(base)) base = path.dirname(base);
  const stage = fs.mkdtempSync(path.join(base, `.${path.basename(dest)}.statechart-`));
  const done = path.join(stage, "done");
  let tmp: string | undefined;
  let janitor: ChildProcess | undefined;
  let exitCode: number;
  try {
    tmp = fs.mkdtempSync(path.join(os.tmpdir(), "statechart-"));
    const runtime = process.versions.deno
      ? [
          "run",
          "--quiet",
          "--no-prompt",
          "--allow-read",
          "--allow-write",
          "--allow-run",
          "--allow-env",
        ]
      : process.execArgv;
    const worker = spawn(
      process.execPath,
      [
        ...runtime,
        path.join(import.meta.dirname, "worker.ts"),
        stage,
        specFile,
        configFile,
        JSON.stringify(options),
        ...(flags.view ? [flags.view] : []),
      ],
      {
        detached: true,
        stdio: ["ignore", "inherit", "inherit"],
        env: childEnv(tmp),
      },
    );
    janitor = spawn(
      "/bin/sh",
      [
        "-c",
        'while read -r line; do :; done; kill -s KILL -- "-$1"; rm -rf -- "$2" "$3"',
        "sh",
        String(worker.pid),
        stage,
        tmp,
      ],
      { detached: true, stdio: ["pipe", "ignore", "ignore"] },
    );
    const exited = new Promise<number>((resolve) =>
      worker.on("exit", (code) => resolve(code ?? 2)),
    );
    await Promise.race([stopped, exited]);
    await killGroup(worker.pid as number);
    const verdict = await exited;
    if (stop) {
      console.error(`${stop} stopped the check, so the command wrote nothing.`);
      exitCode = 128 + os.constants.signals[stop];
    } else if (worker.signalCode) {
      console.error(`${worker.signalCode} killed the check, so the command wrote nothing.`);
      exitCode = 2;
    } else if ((verdict === 0 || verdict === 1) && fs.existsSync(done)) {
      fs.mkdirSync(path.dirname(dest), { recursive: true });
      try {
        fs.renameSync(done, dest);
      } catch (error) {
        if (codeOf(error) !== "ENOTEMPTY" && codeOf(error) !== "EEXIST") throw error;
        throw new Error(
          `${path.join(out, fs.readdirSync(dest).sort()[0])} appeared while the check ran, so the command wrote nothing. Pass --out with a new folder.`,
          { cause: error },
        );
      }
      process.stdout.write(fs.readFileSync(path.join(dest, "report.md")));
      console.log(`\nWrote ${out}`);
      exitCode = verdict;
    } else exitCode = 2;
  } finally {
    fs.rmSync(stage, { recursive: true, force: true });
    if (tmp) fs.rmSync(tmp, { recursive: true, force: true });
    janitor?.kill("SIGKILL");
  }
  process.exit(exitCode);
} catch (error) {
  console.error(messageOf(error));
  process.exit(2);
}
