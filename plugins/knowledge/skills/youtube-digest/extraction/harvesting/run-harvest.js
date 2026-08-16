#!/usr/bin/env node
/**
 * CLI: harvest links from yt-dlp info JSON metadata.
 *
 * Usage: node harvesting/run-harvest.js <info-json-path>
 */

import fs from "node:fs/promises";

import { writeStderr, writeStdout } from "@melodic/video-digestion/shared/terminal";

import { isMainModule } from "../lib/cli-entrypoint.js";
import { parseVideoMetadata } from "../acquisition/video-metadata.js";
import { harvestMetadataLinks, summarizeHeatmap } from "./harvest-links.js";

/**
 * @param {string[]} argv
 */
export async function runHarvestCli(argv) {
  const infoPath = argv[2];
  if (!infoPath) {
    writeStderr("Usage: node harvesting/run-harvest.js <info-json-path>");
    return 1;
  }

  const raw = await fs.readFile(infoPath, "utf8");
  const metadata = parseVideoMetadata(JSON.parse(raw));
  const links = harvestMetadataLinks(metadata);
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
