#!/usr/bin/env node
/**
 * CLI: harvest links from acquisition info JSON metadata.
 *
 * Usage: node harvesting/run-harvest.js <info-json-path> [--url <source-url>]
 *
 * Harvest composition is adapter-owned; the owning adapter resolves from
 * `--url` when given, otherwise from the info JSON's `webpage_url`. Neither
 * present (or an unowned host) fails closed listing the supported sources.
 */

import fs from "node:fs/promises";

import { writeStderr, writeStdout } from "@melodic/video-digestion/shared/terminal";

import { isMainModule } from "../lib/cli-entrypoint.js";
import { UnsupportedSourceError } from "../adapters/adapter-contract.js";
import { resolveSourceAdapter, supportedHosts } from "../adapters/registry.js";
import { parseVideoMetadata } from "../acquisition/video-metadata.js";
import { harvestMetadataLinks, summarizeHeatmap } from "./harvest-links.js";

/**
 * @param {string[]} argv
 */
export async function runHarvestCli(argv) {
  const args = argv.slice(2);
  /** @type {string|undefined} */
  let urlFlag;
  /** @type {string[]} */
  const positional = [];
  for (let i = 0; i < args.length; i++) {
    if (args[i] === "--url") {
      urlFlag = args[i + 1];
      if (!urlFlag) {
        writeStderr("`--url` requires a value");
        return 1;
      }
      i++;
      continue;
    }
    positional.push(args[i]);
  }
  const infoPath = positional[0];
  if (!infoPath) {
    writeStderr("Usage: node harvesting/run-harvest.js <info-json-path> [--url <source-url>]");
    return 1;
  }

  const raw = await fs.readFile(infoPath, "utf8");
  const rawInfo = JSON.parse(raw);
  const metadata = parseVideoMetadata(rawInfo);

  const sourceUrl =
    urlFlag ??
    (rawInfo && typeof rawInfo === "object" && typeof rawInfo.webpage_url === "string"
      ? rawInfo.webpage_url
      : null);
  if (!sourceUrl) {
    writeStderr(
      `Cannot resolve the source adapter: the info JSON has no webpage_url — pass --url <source-url>. Supported sources: ${supportedHosts().join(", ")}`,
    );
    return 1;
  }

  /** @type {import('../adapters/adapter-contract.js').SourceAdapter} */
  let adapter;
  try {
    adapter = resolveSourceAdapter(sourceUrl);
  } catch (error) {
    if (error instanceof UnsupportedSourceError) {
      writeStderr(error.message);
      return 1;
    }
    throw error;
  }

  const links = harvestMetadataLinks(metadata, adapter);
  const heatmap = summarizeHeatmap(metadata.heatmap);

  writeStdout(
    JSON.stringify(
      {
        videoId: metadata.id,
        linkCount: links.length,
        heatmap,
        links,
      },
      null,
      2,
    ),
  );

  return 0;
}

if (isMainModule(import.meta.url)) {
  runHarvestCli(process.argv)
    .then((code) => {
      process.exitCode = code;
    })
    .catch((error) => {
      writeStderr(error instanceof Error ? error.message : String(error));
      process.exitCode = 1;
    });
}
