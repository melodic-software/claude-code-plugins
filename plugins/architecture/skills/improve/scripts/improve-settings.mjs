#!/usr/bin/env node

import { readFileSync } from "node:fs";
import { dirname, join, resolve as resolvePath } from "node:path";
import { fileURLToPath } from "node:url";
import { resolve as resolveConfig } from "../../../lib/config-cascade.mjs";

const here = dirname(fileURLToPath(import.meta.url));
const schema = JSON.parse(readFileSync(join(here, "../../../schemas/architecture.schema.json"), "utf8"));
const improveSchema = schema.properties.improve;
const KEYS = Object.keys(improveSchema.properties);

function fail(message) {
  process.stderr.write(`improve-settings: ${message}\n`);
  process.exit(2);
}

function parseArgs(argv) {
  const opts = { repo: ".", home: "docs/conventions", config: true };
  for (let i = 0; i < argv.length; i += 1) {
    const flag = argv[i];
    if (flag === "--no-config") opts.config = false;
    else if (flag === "--repo" || flag === "--home") {
      if (i + 1 >= argv.length) fail(`${flag} needs a value`);
      i += 1;
      opts[flag.slice(2)] = argv[i];
    } else fail(`unknown argument ${JSON.stringify(flag)}`);
  }
  return opts;
}

const opts = parseArgs(process.argv.slice(2));
const defaults = { improve: Object.fromEntries(KEYS.map((key) => [key, improveSchema.properties[key].default])) };
const values = { ...defaults.improve };
const source = Object.fromEntries(KEYS.map((key) => [key, "defaults"]));
const errors = [];

if (opts.config) {
  const result = resolveConfig({ plugin: "architecture", projectRoot: resolvePath(opts.repo), home: opts.home, schema, defaults, userConfig: {} });
  for (const key of KEYS) {
    if (result.values.improve && Object.hasOwn(result.values.improve, key)) {
      values[key] = result.values.improve[key];
      source[key] = result.provenance[`improve.${key}`] ?? "defaults";
    }
  }
  for (const layer of result.layers) {
    layer.errors.forEach((message, i) => {
      const key = layer.error_keys[i];
      if (key === null || key === "improve" || key.startsWith("improve.")) errors.push(message);
    });
  }
}

process.stdout.write(`${JSON.stringify({ values, source, errors })}\n`);
