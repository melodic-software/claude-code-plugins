// Multi-gate deck validator.
//
// Gates (each fails independently):
//   1. Zod schema — slides-data.js shape
//   2. HTML render — every URL appears as anchor, headlines match, 0 console errors
//   3. Slide overflow detection (visual quality)
//   4. URL reachability via linkinator (X URLs excluded by collection policy)
//   5. PDF text coverage — every URL appears in PDF text layer
//   6. PPTX slide count match
//   7. Responsive matrix — 6 viewport×zoom combos, capture screenshots, check overflow
//
// Outputs: shots/*.png + audit.json. Exit 0 = green, 1 = blocking issues.
import { chromium } from "playwright";
import fs from "node:fs/promises";
import path from "node:path";
import { pathToFileURL } from "node:url";
import { validateDeck } from "./lib/schema.js";
import { formatUrlDisplay } from "./lib/url-display.js";
import { loadSlidesData, meetingsDir, shotsDir } from "./lib/paths.js";

let slidesData;
try {
  slidesData = await loadSlidesData();
} catch (err) {
  console.error(
    `validate.js: could not load slides-data.js — run \`node emit-slides-data.js\` first to generate it.\n  (${err.message})`,
  );
  process.exit(1);
}
const { meta, theme, slides, providerLogos } = slidesData;
const HTML = path.join(meetingsDir(), `ai-meeting-${meta.meetingNumber}.html`);
const PDF = path.join(meetingsDir(), `ai-meeting-${meta.meetingNumber}.pdf`);
const PPTX = path.join(meetingsDir(), `ai-meeting-${meta.meetingNumber}.pptx`);
const SHOTS_DIR = shotsDir();
await fs.mkdir(SHOTS_DIR, { recursive: true });
// Purge stale screenshots before regen. Without this, section reordering
// between meetings leaves orphan section-NN-foo.png files alongside the
// current set, polluting the audit. Idempotent: only removes PNG/JSON.
try {
  const stale = await fs.readdir(SHOTS_DIR);
  for (const f of stale) {
    if (/\.(png|json)$/i.test(f)) {
      await fs.unlink(path.join(SHOTS_DIR, f)).catch(() => {});
    }
  }
} catch {
  // dir doesn't exist yet — mkdir below handles it
}
await fs.mkdir(SHOTS_DIR, { recursive: true });

const issues = { blocking: [], warnings: [] };

// ────────────────────────────────────────────────────────────────────
// Gate 1: Zod schema
// ────────────────────────────────────────────────────────────────────
console.log("\n[1/7] Schema (Zod) ...");
try {
  validateDeck({ meta, theme, providerLogos, slides });
  console.log("  ✓ slides-data.js shape OK");
} catch (e) {
  issues.blocking.push(`Schema: ${e.message}`);
  console.log(`  ✗ ${e.message}`);
}

// ────────────────────────────────────────────────────────────────────
// Gate 2-3: HTML render — URLs, headlines, console errors, overflow
// ────────────────────────────────────────────────────────────────────
console.log("\n[2/7] HTML render + URL/headline coverage ...");
const browser = await chromium.launch({ headless: true });
const context = await browser.newContext({ viewport: { width: 1600, height: 900 } });
const page = await context.newPage();

const consoleErrs = [];
const externalRenderRequests = [];
page.on("pageerror", (e) => consoleErrs.push(`PAGEERR: ${e.message}`));
page.on("console", (m) => { if (m.type() === "error") consoleErrs.push(`CONSOLE: ${m.text()}`); });
await page.route(/^https?:\/\//, (route) => {
  externalRenderRequests.push(route.request().url());
  return route.abort("blockedbyclient");
});

await page.goto(pathToFileURL(HTML).href, { waitUntil: "load" });
await page.waitForSelector("main#deck");
await page.evaluate(async () => {
  await document.fonts.ready;
  await new Promise((resolve) =>
    requestAnimationFrame(() => requestAnimationFrame(resolve)),
  );
});

// Section-based audit (sectioned-scroll deck). One screenshot per <section>.
// Page-wide URL/headline coverage check (vs old per-slide approach).
const total = slides.length; // legacy field name — used downstream for PDF page check
const sectionInfo = await page.evaluate(() => {
  const sections = [...document.querySelectorAll("main#deck > section.section")];
  return sections.map((s) => ({ id: s.id, h1: s.querySelector("h1")?.innerText.trim() || "", h2: s.querySelector("h2")?.innerText.trim() || "" }));
});

// Screenshot each section by scrolling it into view
for (let i = 0; i < sectionInfo.length; i++) {
  const id = sectionInfo[i].id;
  await page.evaluate((sid) => {
    document.getElementById(sid)?.scrollIntoView({ behavior: "instant", block: "start" });
  }, id);
  await page.waitForTimeout(180);
  const shotPath = path.join(SHOTS_DIR, `section-${String(i + 1).padStart(2, "0")}-${id}.png`);
  await page.screenshot({ path: shotPath, fullPage: false });
}

// Page-wide DOM extraction — section grouping concatenates bullets so
// per-slide structure is gone. Verify URL + headline coverage at page level.
const pageData = await page.evaluate(() => {
  return {
    urls: Array.from(document.querySelectorAll(".news-url")).map((a) => a.href),
    headlines: Array.from(document.querySelectorAll(".news-headline, .flair-headline, .pattern-headline")).map((s) => s.innerText.trim()),
    // Skip decorative orb-overflow sections (open, qa) — orb gradients are intentionally
    // transform-translated past edges; overflow:hidden clips them visually but scrollWidth
    // still reports the layout extent. Pure cosmetic, no scrollbar appears.
    sectionOverflows: [...document.querySelectorAll("main#deck > section.section")]
      .filter((s) => !["open", "qa"].includes(s.id))
      .filter((s) => s.scrollWidth > s.clientWidth + 4)
      .map((s) => ({ id: s.id, sw: s.scrollWidth, cw: s.clientWidth })),
  };
});

await browser.close();

// All source URLs across ALL slides (bullets[].urls + items[].urls)
const allUrls = new Set();
slides.forEach((s) => (s.bullets || []).forEach((b) => (b.urls || []).forEach((u) => allUrls.add(u))));
slides.forEach((s) => (s.items || []).forEach((it) => (it.urls || []).forEach((u) => allUrls.add(u))));

// All source headlines (bullet titles + flair item titles + pattern item titles)
const expectedHeadlines = [];
slides.forEach((s) => {
  (s.bullets || []).forEach((b) => expectedHeadlines.push(b.title));
  if (s.type === "flair" || s.type === "patterns") (s.items || []).forEach((it) => expectedHeadlines.push(it.title));
});

// Normalize trailing slash — browsers canonicalize <a href="https://host"> to "https://host/"
const normUrl = (u) => u.replace(/\/+$/, "");
const renderedUrlSet = new Set(pageData.urls.map(normUrl));
const urlMismatches = [...allUrls].filter((u) => !renderedUrlSet.has(normUrl(u)));
const headlineMismatches = expectedHeadlines.filter((exp) => !pageData.headlines.some((h) => h.startsWith(exp.slice(0, 30))));

console.log(`  Sections rendered:      ${sectionInfo.length}`);
console.log(`  Expected URLs (source): ${[...allUrls].length}`);
console.log(`  Rendered (DOM):         ${pageData.urls.length}`);
console.log(`  Missing URLs:           ${urlMismatches.length}`);
console.log(`  Missing headlines:      ${headlineMismatches.length}`);
console.log(`  Console errors:         ${consoleErrs.length}`);
if (urlMismatches.length) issues.blocking.push(`URL coverage: ${urlMismatches.length} missing`);
if (headlineMismatches.length) issues.blocking.push(`Headline coverage: ${headlineMismatches.length} missing`);
if (consoleErrs.length) issues.blocking.push(`Console errors: ${consoleErrs.length}`);
if (externalRenderRequests.length) {
  issues.blocking.push(`External render requests: ${externalRenderRequests.length}`);
}

console.log(`\n[3/7] Section horizontal overflow ...`);
console.log(`  Sections w/ horizontal overflow: ${pageData.sectionOverflows.length}`);
pageData.sectionOverflows.forEach((s) => console.log(`    #${s.id}  scrollWidth=${s.sw} clientWidth=${s.cw}`));
if (pageData.sectionOverflows.length) issues.warnings.push(`Section h-overflow: ${pageData.sectionOverflows.map((s) => s.id).join(", ")}`);

// ────────────────────────────────────────────────────────────────────
// Gate 4: URL reachability via linkinator. X URLs are user-supplied citation
// metadata only and must not be fetched by this plugin.
// ────────────────────────────────────────────────────────────────────
console.log(`\n[4/7] URL reachability (linkinator) ...`);
const linkResults = { broken: [] };
try {
  const { LinkChecker } = await import("linkinator");
  const checker = new LinkChecker();
  const result = await checker.check({
    path: HTML,
    recurse: false,
    timeout: 8000,
    retry: false,
    linksToSkip: [
      // Skip self-references and image data URIs
      /^data:/, /^file:/, /^#/,
      /^https?:\/\/(?:x|twitter)\.com(?:\/|$)/i,
    ],
  });
  for (const link of result.links) {
    if (link.state !== "BROKEN") continue;
    linkResults.broken.push(`${link.url} [${link.status}]`);
  }
  console.log(`  Checked ${result.links.length} links`);
  console.log(`  Broken:    ${linkResults.broken.length}`);
  console.log("  X URLs:     skipped by collection policy");
  if (linkResults.broken.length) issues.warnings.push(`Broken links: ${linkResults.broken.length}`);
} catch (e) {
  console.log(`  ⚠ linkinator skipped: ${e.message}`);
  issues.warnings.push(`linkinator skipped: ${e.message}`);
}

// ────────────────────────────────────────────────────────────────────
// Gate 5: PDF text coverage (unpdf)
// ────────────────────────────────────────────────────────────────────
console.log(`\n[5/7] PDF text coverage (unpdf) ...`);
const pdfResult = { totalPages: 0, missingUrls: [] };
try {
  const { extractText, getDocumentProxy } = await import("unpdf");
  const buf = await fs.readFile(PDF);
  const pdf = await getDocumentProxy(new Uint8Array(buf));
  const { text, totalPages } = await extractText(pdf, { mergePages: true });
  pdfResult.totalPages = totalPages;
  // Compare URL count — every source URL should appear in PDF text layer.
  // HTML renders short display form (formatUrlDisplay), so check that the
  // displayed form is in the text; href itself is preserved in PDF annotations
  // (clickable links work independently of text-layer content).
  const urlList = [...allUrls];
  for (const u of urlList) {
    const displayed = formatUrlDisplay(u);
    if (!text.includes(displayed) && !text.includes(u)) {
      pdfResult.missingUrls.push(u);
    }
  }
  console.log(`  PDF pages:    ${totalPages} (sections: ${sectionInfo.length}; slide objects: ${total})`);
  console.log(`  URLs in PDF:  ${urlList.length - pdfResult.missingUrls.length} / ${urlList.length}`);
  console.log(`  Missing URLs: ${pdfResult.missingUrls.length}`);
  // PDF pages should be ≥ section count (sections may span multiple pages when content is long)
  if (totalPages < sectionInfo.length) issues.warnings.push(`PDF page count ${totalPages} < section count ${sectionInfo.length}`);
  if (pdfResult.missingUrls.length) issues.warnings.push(`PDF missing ${pdfResult.missingUrls.length} URLs`);
} catch (e) {
  console.log(`  ⚠ unpdf check skipped: ${e.message}`);
  issues.warnings.push(`unpdf skipped: ${e.message}`);
}

// ────────────────────────────────────────────────────────────────────
// Gate 6: PPTX slide count (node-pptx-parser)
// ────────────────────────────────────────────────────────────────────
console.log(`\n[6/7] PPTX slide count (node-pptx-parser) ...`);
const pptxResult = { slideCount: 0 };
try {
  const mod = await import("node-pptx-parser");
  const PPTXParser = mod.default || mod.PPTXParser || mod;
  const parser = new PPTXParser(PPTX);
  const parsed = await parser.parse();
  pptxResult.slideCount = parsed?.slides?.length || 0;
  console.log(`  PPTX slides:  ${pptxResult.slideCount} (expected: ${total})`);
  if (pptxResult.slideCount !== total) issues.warnings.push(`PPTX slide count ${pptxResult.slideCount} ≠ ${total}`);
} catch (e) {
  console.log(`  ⚠ node-pptx-parser check skipped: ${e.message}`);
  issues.warnings.push(`pptx-parser skipped: ${e.message}`);
}

// ────────────────────────────────────────────────────────────────────
// Gate 7: Responsive matrix — 6 viewport×zoom combos
// ────────────────────────────────────────────────────────────────────
console.log(`\n[7/7] Responsive matrix (viewport × zoom) ...`);
const responsiveMatrix = [
  { name: "desktop-100", viewport: { width: 1920, height: 1080 }, zoom: 1.0 },
  { name: "desktop-150", viewport: { width: 1920, height: 1080 }, zoom: 1.5 },
  { name: "desktop-200", viewport: { width: 1920, height: 1080 }, zoom: 2.0 },
  { name: "laptop-100",  viewport: { width: 1366, height: 768  }, zoom: 1.0 },
  { name: "tablet-100",  viewport: { width: 1024, height: 768  }, zoom: 1.0 },
  { name: "mobile-100",  viewport: { width: 414,  height: 896  }, zoom: 1.0 },
];
const responsiveResults = [];
try {
  const browser2 = await chromium.launch({ headless: true });
  for (const m of responsiveMatrix) {
    const ctx2 = await browser2.newContext({ viewport: m.viewport, deviceScaleFactor: 1 });
    const p2 = await ctx2.newPage();
    await p2.route(/^https?:\/\//, (route) => route.abort("blockedbyclient"));
    await p2.goto(pathToFileURL(HTML).href, { waitUntil: "load" });
    await p2.waitForSelector("main#deck");
    await p2.evaluate((z) => { document.documentElement.style.zoom = String(z); }, m.zoom);
    await p2.evaluate(async () => {
      await document.fonts.ready;
      await new Promise((resolve) =>
        requestAnimationFrame(() => requestAnimationFrame(resolve)),
      );
    });

    // Per-section overflow check
    const overflows = await p2.evaluate(() => {
      return [...document.querySelectorAll("main#deck > section.section")]
        .filter((s) => !["open", "qa"].includes(s.id))
        .filter((s) => s.scrollWidth > s.clientWidth + 4)
        .map((s) => ({ id: s.id, sw: s.scrollWidth, cw: s.clientWidth }));
    });

    // Single full-page screenshot per matrix combo (decks can be long; cap height)
    const shotPath = path.join(SHOTS_DIR, `responsive-${m.name}.png`);
    await p2.screenshot({ path: shotPath, fullPage: false });
    responsiveResults.push({ name: m.name, viewport: m.viewport, zoom: m.zoom, overflowCount: overflows.length, overflows });
    await ctx2.close();
  }
  await browser2.close();

  console.log(`  Combos checked:   ${responsiveResults.length}`);
  for (const r of responsiveResults) {
    const tag = r.overflowCount > 0 ? "⚠" : "✓";
    console.log(`  ${tag} ${r.name.padEnd(14)} ${r.viewport.width}×${r.viewport.height} @${r.zoom}x → overflow sections: ${r.overflowCount}`);
  }
  const totalRespOverflow = responsiveResults.reduce((acc, r) => acc + r.overflowCount, 0);
  if (totalRespOverflow > 0) {
    issues.warnings.push(`Responsive overflows: ${totalRespOverflow} across ${responsiveMatrix.length} combos`);
  }
} catch (e) {
  console.log(`  ⚠ Gate 7 skipped: ${e.message}`);
  issues.warnings.push(`Responsive matrix skipped: ${e.message}`);
}

// ────────────────────────────────────────────────────────────────────
// Summary
// ────────────────────────────────────────────────────────────────────
const summary = {
  total,
  sectionCount: sectionInfo.length,
  sectionIds: sectionInfo.map((s) => s.id),
  consoleErrors: consoleErrs,
  urlMismatches,
  headlineMismatches,
  sectionOverflows: pageData.sectionOverflows,
  linkResults,
  pdfResult,
  pptxResult,
  responsiveResults,
  issues,
};
await fs.writeFile(path.join(SHOTS_DIR, "audit.json"), JSON.stringify(summary, null, 2));

console.log(`\n${"=".repeat(70)}`);
console.log(`AUDIT SUMMARY`);
console.log(`${"=".repeat(70)}`);
console.log(`  Sections rendered: ${sectionInfo.length} (slide objects: ${total})`);
console.log(`  Blocking issues: ${issues.blocking.length}`);
issues.blocking.forEach((m) => console.log(`    ✗ ${m}`));
console.log(`  Warnings:        ${issues.warnings.length}`);
issues.warnings.forEach((m) => console.log(`    ⚠ ${m}`));
console.log(`  Audit JSON:      ${path.join(SHOTS_DIR, "audit.json")}`);
console.log(`  Screenshots:     ${SHOTS_DIR}/slide-*.png`);

if (issues.blocking.length) {
  console.log(`\n✗ VALIDATION FAILED — blocking issues present.`);
  process.exit(1);
}
console.log(`\n✓ VALIDATION PASSED — deck is ship-ready.`);
