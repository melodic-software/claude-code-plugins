/**
 * Download all referenced resources from resources.json files.
 *
 * Scans all modules/lessons for resources.json, extracts download URLs
 * and PDF links, fetches each file, and saves to the course data directory.
 *
 * Usage: node download-resources.js --course-dir <path> [--dry-run]
 */

import { existsSync, mkdirSync, readdirSync, readFileSync, statSync, writeFileSync } from "node:fs";
import http from "node:http";
import https from "node:https";
import { basename, dirname, extname, join } from "node:path";

import { createLogger } from "@melodic/video-digestion/shared/logger";

import { loadCourseDir, parseCliArgs, resolveLogLevel } from "./utils.js";

const args = parseCliArgs({
  "dry-run": { type: "boolean", default: false },
});
const log = createLogger(resolveLogLevel(args));

function download(url, destPath, timeout = 30000) {
  return new Promise((resolve, reject) => {
    const client = url.startsWith("https") ? https : http;
    const req = client.get(url, { timeout }, (res) => {
      if (res.statusCode >= 300 && res.statusCode < 400 && res.headers.location) {
        download(res.headers.location, destPath, timeout).then(resolve).catch(reject);
        return;
      }
      if (res.statusCode !== 200) {
        reject(new Error(`HTTP ${res.statusCode} for ${url.substring(0, 80)}`));
        return;
      }
      const chunks = [];
      res.on("data", (chunk) => chunks.push(chunk));
      res.on("end", () => {
        const buffer = Buffer.concat(chunks);
        writeFileSync(destPath, buffer);
        resolve(buffer.length);
      });
      res.on("error", reject);
    });
    req.on("error", reject);
    req.on("timeout", () => {
      req.destroy();
      reject(new Error("Timeout"));
    });
  });
}

function collectResourcesFromFile(full, buckets) {
  const data = JSON.parse(readFileSync(full, "utf-8"));
  const lessonDir = basename(dirname(full));
  const moduleDir = basename(dirname(dirname(full)));
  const context = { lessonDir, moduleDir, source: full };

  for (const d of data.downloads ?? []) {
    buckets.allDownloads.push({ ...d, ...context });
  }
  for (const p of data.pdfLinks ?? []) {
    buckets.allPdfs.push({ ...p, ...context });
  }
  for (const a of data.articleLinks ?? []) {
    if (!a.href?.includes("affiliate")) {
      buckets.allArticles.push({ ...a, ...context });
    }
  }
}

function walkModules(dir, buckets) {
  for (const entry of readdirSync(dir)) {
    const full = join(dir, entry);
    if (statSync(full).isDirectory()) {
      walkModules(full, buckets);
    } else if (entry === "resources.json") {
      collectResourcesFromFile(full, buckets);
    }
  }
}

function buildDownloadItems({
  uniqueDownloads,
  uniquePdfs,
  downloadsDir,
  slidesDir,
  resourcesDir,
}) {
  return [
    ...uniqueDownloads.map((d) => {
      const filename = d.label || basename(new URL(d.href).pathname);
      const ext = extname(filename).toLowerCase();
      const targetDir = ext === ".sql" || ext === ".json" ? resourcesDir : downloadsDir;
      return { href: d.href, filename, destPath: join(targetDir, filename) };
    }),
    ...uniquePdfs.map((p) => {
      const filename = p.label || basename(new URL(p.href).pathname);
      return { href: p.href, filename, destPath: join(slidesDir, filename) };
    }),
  ];
}

async function downloadOneItem(item, stats) {
  if (existsSync(item.destPath)) {
    stats.skipped++;
    return;
  }

  try {
    const bytes = await download(item.href, item.destPath);
    stats.totalBytes += bytes;
    stats.success++;
    if (stats.success % 10 === 0) {
      log.info(`  ${stats.success} downloaded, ${stats.failed} failed, ${stats.skipped} skipped`);
    }
  } catch (e) {
    stats.failed++;
    log.warn(`  FAIL: ${item.filename} — ${e.message.substring(0, 60)}`);
  }
}

async function downloadAllItems(downloadItems) {
  const stats = { success: 0, failed: 0, skipped: 0, totalBytes: 0 };
  await downloadItems.reduce(async (chain, item) => {
    await chain;
    await downloadOneItem(item, stats);
  }, Promise.resolve());
  return stats;
}

async function main() {
  const { courseDir } = loadCourseDir(args, { logger: log });
  const modulesDir = join(courseDir, "modules");
  const downloadsDir = join(courseDir, "code", "downloads");
  const slidesDir = join(courseDir, "slides");
  const resourcesDir = join(courseDir, "resources");

  if (!existsSync(modulesDir)) {
    log.error(`Modules directory not found: ${modulesDir}`);
    process.exit(1);
  }

  const buckets = { allDownloads: [], allPdfs: [], allArticles: [] };
  walkModules(modulesDir, buckets);
  const { allDownloads, allPdfs, allArticles } = buckets;

  const uniqueDownloads = [...new Map(allDownloads.map((d) => [d.href, d])).values()];
  const uniquePdfs = [...new Map(allPdfs.map((p) => [p.href, p])).values()];
  const uniqueArticles = [...new Map(allArticles.map((a) => [a.href, a])).values()];

  log.info(`\nResources found:`);
  log.info(`  Downloads: ${uniqueDownloads.length} unique files`);
  log.info(`  PDFs: ${uniquePdfs.length} unique files`);
  log.info(`  Articles: ${uniqueArticles.length} unique links (saved as references)`);

  if (args["dry-run"]) {
    log.info("\n[DRY RUN] Would download:");
    for (const d of uniqueDownloads) {
      log.info(`  DL: ${d.label}`);
    }
    for (const p of uniquePdfs) {
      log.info(`  PDF: ${p.label}`);
    }
    log.info("\nArticle references:");
    for (const a of uniqueArticles) {
      log.info(`  ${a.label}`);
    }
    return;
  }

  mkdirSync(downloadsDir, { recursive: true });
  mkdirSync(slidesDir, { recursive: true });
  mkdirSync(resourcesDir, { recursive: true });

  const downloadItems = buildDownloadItems({
    uniqueDownloads,
    uniquePdfs,
    downloadsDir,
    slidesDir,
    resourcesDir,
  });

  log.info("\nDownloading files...\n");
  const { success, failed, skipped, totalBytes } = await downloadAllItems(downloadItems);

  const articlesPath = join(courseDir, "article-links.json");
  writeFileSync(articlesPath, JSON.stringify(uniqueArticles, null, 2), "utf-8");

  const mb = (totalBytes / 1024 / 1024).toFixed(1);
  log.info(`\n========================================`);
  log.info(`Downloaded: ${success} files (${mb} MB)`);
  log.info(`Skipped (exist): ${skipped}`);
  log.info(`Failed: ${failed}`);
  log.info(`Articles saved: ${uniqueArticles.length} references`);
  log.info(`\nOutput:`);
  log.info(`  ${downloadsDir}`);
  log.info(`  ${slidesDir}`);
  log.info(`  ${resourcesDir}`);
  log.info(`  ${articlesPath}`);
}

main().catch((e) => {
  log.error("Fatal:", e);
  process.exit(1);
});
