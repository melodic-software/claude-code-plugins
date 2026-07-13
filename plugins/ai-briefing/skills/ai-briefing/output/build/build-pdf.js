// Print HTML deck to PDF via Playwright headless chromium.
import { chromium } from "playwright";
import path from "node:path";
import fs from "node:fs/promises";
import { pathToFileURL } from "node:url";
import { loadSlidesData, meetingsDir } from "./lib/paths.js";

const { meta } = await loadSlidesData();
const HTML_PATH = path.join(meetingsDir(), `ai-meeting-${meta.meetingNumber}.html`);
const PDF_PATH = path.join(meetingsDir(), `ai-meeting-${meta.meetingNumber}.pdf`);

const url = pathToFileURL(HTML_PATH).href + "?print=1";

const browser = await chromium.launch({ headless: true });
const context = await browser.newContext({
  viewport: { width: 1280, height: 720 },
});
const page = await context.newPage();
await page.goto(url, { waitUntil: "networkidle" });

// Wait for fonts to settle
await page.evaluate(() => document.fonts.ready);
await page.waitForTimeout(400);

// Letter landscape, full color, one slide per page
await page.pdf({
  path: PDF_PATH,
  format: "Letter",
  landscape: true,
  printBackground: true,
  margin: { top: 0, right: 0, bottom: 0, left: 0 },
  preferCSSPageSize: false,
});

await browser.close();

const stats = await fs.stat(PDF_PATH);
console.log(`PDF written: ${PDF_PATH}`);
console.log(`Size: ${(stats.size / 1024).toFixed(1)} KB`);
