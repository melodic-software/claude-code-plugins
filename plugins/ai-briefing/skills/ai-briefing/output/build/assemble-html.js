// Assemble single-file sectioned-scroll HTML deck from build modules.
// One <section> per provider/group, sticky top nav with scroll-spy chips,
// keyboard nav steps section-by-section, scroll-snap proximity, hash deep-link.
// Print mode (?print=1) re-paginates one section per page for build-pdf.js.

import fs from "node:fs/promises";
import fsSync from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { buildSections, escape } from "./build-sections.js";
import { buildCss } from "./build-css.js";
import { buildClientJs } from "./build-client-js.js";
import { loadSlidesData, meetingsDir } from "./lib/paths.js";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const { meta, theme, slides, providerLogos } = await loadSlidesData();

function loadEmbeddedAssets(buildDir) {
  let logoWhiteData = "";
  if (meta.logoWhite) {
    const logoWhiteB64 = fsSync.readFileSync(path.resolve(buildDir, meta.logoWhite)).toString("base64");
    logoWhiteData = `data:image/png;base64,${logoWhiteB64}`;
  }

  const providerLogoSvg = {};
  for (const [slug, logoPath] of Object.entries(providerLogos)) {
    if (!logoPath) continue;
    try {
      const raw = fsSync.readFileSync(path.resolve(buildDir, logoPath), "utf-8");
      providerLogoSvg[slug] = raw.replace(/<title>[^<]*<\/title>/, "");
    } catch {
      /* missing logo — render text-only header */
    }
  }

  return { logoWhiteData, providerLogoSvg };
}

function assembleDocument({ meta, theme, slides, logoWhiteData, providerLogoSvg }) {
  const { sectionsHtml, topnavHtml, groups } = buildSections({ slides, meta, logoWhiteData, providerLogoSvg });
  const css = buildCss(theme);
  const js = buildClientJs(groups);

  const html = `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8" />
<meta name="viewport" content="width=device-width, initial-scale=1.0" />
<meta name="color-scheme" content="dark" />
<title>${escape(meta.org)} — AI Meeting #${meta.meetingNumber}</title>
<style>${css}</style>
</head>
<body>
${topnavHtml}
<main id="deck">
${sectionsHtml}
</main>
<div id="progress" style="width:0%"></div>
<div id="help"><kbd>← →</kbd> sections · <kbd>space</kbd> next · click chips · scroll freely</div>
<script>${js}</script>
</body>
</html>
`;

  return { html, groups };
}

export async function assembleHtml() {
  const output = path.join(meetingsDir(), `ai-meeting-${meta.meetingNumber}.html`);
  const { logoWhiteData, providerLogoSvg } = loadEmbeddedAssets(__dirname);
  const { html, groups } = assembleDocument({ meta, theme, slides, logoWhiteData, providerLogoSvg });

  await fs.mkdir(meetingsDir(), { recursive: true });
  await fs.writeFile(output, html, "utf-8");
  const stats = await fs.stat(output);
  console.log(`HTML written: ${output}`);
  console.log(`Sections:    ${groups.length}`);
  console.log(`Slide source items: ${slides.length}`);
  console.log(`Size: ${(stats.size / 1024).toFixed(1)} KB`);
}
