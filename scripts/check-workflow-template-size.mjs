import { readdirSync, readFileSync } from "node:fs";
import { createRequire } from "node:module";
import path from "node:path";
import process from "node:process";
import { pathToFileURL } from "node:url";

const NAME = "check-workflow-template-size";
const CONFIG = ".github/workflow-template-size.json";
const WORKFLOWS = ".github/workflows";
const LOCAL = "./.github/workflows/";
const NODE = 24;
const STRING = 26;

export async function loadYaml(root) {
  const requireFrom = createRequire(path.join(root, ".github/standards/runner-policy/package.json"));
  return import(pathToFileURL(requireFrom.resolve("yaml")).href);
}

export const costOf = (yaml, text) => measure(yaml, text).bytes;

function measure(yaml, text) {
  const doc = yaml.parseDocument(text, { version: "1.2" });
  if (doc.errors.length > 0) throw new Error(`does not parse: ${doc.errors[0].message}`);
  const cost = (node) => {
    if (yaml.isAlias(node)) return cost(node.resolve(doc));
    if (yaml.isMap(node)) return node.items.reduce((sum, pair) => sum + cost(pair.key) + cost(pair.value), NODE);
    if (yaml.isSeq(node)) return node.items.reduce((sum, item) => sum + cost(item), NODE);
    if (yaml.isScalar(node) && typeof node.value === "string") return NODE + STRING + 2 * node.value.length;
    return NODE;
  };
  return { doc, bytes: cost(doc.contents) };
}

function localCalls(doc) {
  const jobs = doc.toJS({ maxAliasCount: -1 })?.jobs;
  if (jobs === null || typeof jobs !== "object") return [];
  return Object.values(jobs)
    .map((job) => job?.uses)
    .filter((uses) => typeof uses === "string" && uses.startsWith(LOCAL))
    .map((uses) => uses.slice(LOCAL.length));
}

export function estimate(yaml, name, read, stack = []) {
  if (stack.includes(name)) throw new Error(`call cycle: ${[...stack, name].join(" -> ")}`);
  let parsed;
  try {
    parsed = measure(yaml, read(name));
  } catch (error) {
    throw new Error(`${name}: ${error.message}`);
  }
  let { bytes } = parsed;
  let calls = 0;
  for (const callee of localCalls(parsed.doc)) {
    const inner = estimate(yaml, callee, read, [...stack, name]);
    bytes += inner.bytes;
    calls += 1 + inner.calls;
  }
  return { bytes, calls };
}

const whole = (value) => Number.isSafeInteger(value) && value >= 0;

export function readConfig(root) {
  const config = JSON.parse(readFileSync(path.join(root, CONFIG), "utf8"));
  const figure = config["failing-figure"];
  if (!whole(figure) || figure === 0) throw new Error(`${CONFIG}: failing-figure must be a positive whole number`);
  if (!whole(config.margin) || config.margin >= figure) {
    throw new Error(`${CONFIG}: margin must be a whole number below failing-figure`);
  }
  return config;
}

export const failLine = (config) => config["failing-figure"] - config.margin;

function main() {
  const usage = `usage: ${NAME}.sh [--check]`;
  const args = process.argv.slice(2);
  if (args.length > 1 || (args.length === 1 && args[0] !== "--check")) {
    process.stderr.write(`${usage}\n`);
    process.exit(2);
  }
  const root = path.resolve(import.meta.dirname, "..");
  const fail = (message) => {
    process.stderr.write(`${NAME}: ${message}\n`);
    process.exit(2);
  };
  return loadYaml(root).then(
    (yaml) => {
      let config;
      try {
        config = readConfig(root);
      } catch (error) {
        fail(error.message);
      }
      const line = failLine(config);
      const dir = path.join(root, WORKFLOWS);
      const read = (name) => readFileSync(path.join(dir, name), "utf8");
      const findings = [];
      const passes = [];
      for (const name of readdirSync(dir).filter((file) => /\.ya?ml$/.test(file)).sort()) {
        let result;
        try {
          result = estimate(yaml, name, read);
        } catch (error) {
          fail(error.message);
        }
        if (result.calls === 0) continue;
        const file = `${WORKFLOWS}/${name}`;
        if (result.bytes >= line) {
          findings.push(
            `${file}:1: estimated template memory ${result.bytes} over ${result.calls} local reusable call(s) is within ${config.margin} of the known-failing figure ${config["failing-figure"]} (${CONFIG}); move step bodies into sourced scripts or cut what the called files repeat`,
          );
        } else {
          passes.push(`${file}: ${result.bytes} bytes, ${line - result.bytes} under the fail line ${line}`);
        }
      }
      if (findings.length > 0) {
        process.stderr.write(`${findings.join("\n")}\n${NAME}: ${findings.length} finding(s)\n`);
        process.exit(1);
      }
      process.stdout.write(`${passes.join("\n")}${passes.length > 0 ? "\n" : ""}${NAME}: ${passes.length} caller(s) under the fail line ${line}.\n`);
    },
    () => fail("the yaml package is not installed; run npm ci --prefix .github/standards/runner-policy"),
  );
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) await main();
