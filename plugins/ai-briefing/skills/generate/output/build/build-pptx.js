// Build ai-meeting-1.pptx from slides-data.js using pptxgenjs.
// Theme: dark navy + electric blue + amber. Strategy: Team All-Hands arc.
import PptxGenJS from "pptxgenjs";
import path from "node:path";
import fs from "node:fs";
import { fileURLToPath } from "node:url";
import { loadSlidesData, meetingsDir } from "./lib/paths.js";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const { meta, theme, slides } = await loadSlidesData();
const OUTPUT = path.join(meetingsDir(), `ai-meeting-${meta.meetingNumber}.pptx`);

// Optional org logo as base64 data URI (pptxgenjs needs path or base64). Empty
// when the active brand ships no logo — the addImage sites below skip it.
const logoWhiteData = meta.logoWhite
  ? `data:image/png;base64,${fs.readFileSync(path.resolve(__dirname, meta.logoWhite)).toString("base64")}`
  : "";

const pres = new PptxGenJS();
pres.layout = "LAYOUT_WIDE"; // 13.33 x 7.5 in
pres.title = `${meta.org} — AI Meeting #${meta.meetingNumber}`;
pres.author = meta.org;
pres.company = meta.org;

// Slide width/height in inches
const W = 13.33;
const H = 7.5;

const FONT_HEAD = theme.pptFontHead;
const FONT_BODY = theme.pptFontBody;

// Helper: solid bg + accent strip + footer
function decorate(slide, { showFooter = true, eyebrow = null, showLogo = true } = {}) {
  slide.background = { color: theme.bg };

  // Top accent bar (brand red)
  slide.addShape(pres.ShapeType.rect, {
    x: 0, y: 0, w: W, h: 0.1,
    fill: { color: theme.brandRed }, line: { type: "none" },
  });

  // Side rail (gold)
  slide.addShape(pres.ShapeType.rect, {
    x: 0, y: 0.1, w: 0.18, h: H - 0.1,
    fill: { color: theme.accent2 }, line: { type: "none" },
  });

  if (eyebrow) {
    slide.addText(eyebrow, {
      x: 0.5, y: 0.25, w: W - 4, h: 0.35,
      fontFace: FONT_HEAD, fontSize: 11, bold: true,
      color: theme.accent, charSpacing: 6,
    });
  }

  // Top-right logo (white)
  if (showLogo && logoWhiteData) {
    slide.addImage({
      data: logoWhiteData,
      x: W - 1.65, y: 0.2, w: 1.3, h: 0.36,
      sizing: { type: "contain", w: 1.3, h: 0.36 },
    });
  }

  if (showFooter) {
    slide.addText([
      { text: meta.org, options: { color: theme.textMuted, fontSize: 9 } },
      { text: "  ·  ", options: { color: theme.divider, fontSize: 9 } },
      { text: `AI Meeting #${meta.meetingNumber}`, options: { color: theme.textMuted, fontSize: 9 } },
      { text: "  ·  ", options: { color: theme.divider, fontSize: 9 } },
      { text: meta.date, options: { color: theme.textMuted, fontSize: 9 } },
    ], {
      x: 0.5, y: H - 0.4, w: W - 1, h: 0.3,
      fontFace: FONT_BODY, align: "left",
    });
  }
}

function addSlideNumber(slide, n, total) {
  slide.addText(`${n} / ${total}`, {
    x: W - 1.2, y: H - 0.4, w: 1, h: 0.3,
    fontFace: FONT_BODY, fontSize: 9, color: theme.textMuted,
    align: "right",
  });
}

// ----- Slide types ----------------------------------------------------------

function buildTitle(s, slide) {
  slide.background = { color: theme.bg };

  // Top brand-red bar + bottom gold bar
  slide.addShape(pres.ShapeType.rect, {
    x: 0, y: 0, w: W, h: 0.22,
    fill: { color: theme.brandRed }, line: { type: "none" },
  });
  slide.addShape(pres.ShapeType.rect, {
    x: 0, y: H - 0.14, w: W, h: 0.14,
    fill: { color: theme.accent2 }, line: { type: "none" },
  });

  // Brand glow shapes (indigo + periwinkle)
  slide.addShape(pres.ShapeType.ellipse, {
    x: W - 5, y: -2, w: 7, h: 7,
    fill: { color: theme.bgCard, transparency: 25 }, line: { type: "none" },
  });
  slide.addShape(pres.ShapeType.ellipse, {
    x: -1.5, y: H - 4, w: 5, h: 5,
    fill: { color: theme.accent, transparency: 70 }, line: { type: "none" },
  });
  slide.addShape(pres.ShapeType.ellipse, {
    x: W / 2, y: H - 2.5, w: 3.5, h: 3.5,
    fill: { color: theme.accent2, transparency: 85 }, line: { type: "none" },
  });

  // Org logo (large, top-left)
  if (logoWhiteData) {
    slide.addImage({
      data: logoWhiteData,
      x: 0.8, y: 0.7, w: 3.5, h: 0.95,
      sizing: { type: "contain", w: 3.5, h: 0.95 },
    });
  }

  slide.addText(s.eyebrow.toUpperCase(), {
    x: 0.8, y: 2.05, w: 11, h: 0.45,
    fontFace: FONT_HEAD, fontSize: 14, bold: true,
    color: theme.accent2, charSpacing: 12,
  });

  slide.addText(s.title, {
    x: 0.8, y: 2.6, w: 11, h: 1.7,
    fontFace: FONT_HEAD, fontSize: 76, bold: true,
    color: theme.text,
  });

  slide.addText(s.subtitle, {
    x: 0.8, y: 4.5, w: 11, h: 0.7,
    fontFace: FONT_HEAD, fontSize: 34,
    color: theme.accent,
  });

  slide.addText(meta.tagline, {
    x: 0.8, y: 5.4, w: 11, h: 0.5,
    fontFace: FONT_BODY, fontSize: 14,
    color: theme.text, italic: true,
  });

  slide.addText(s.footer, {
    x: 0.8, y: 5.95, w: 11, h: 0.4,
    fontFace: FONT_BODY, fontSize: 12,
    color: theme.textMuted, italic: true,
  });
}

function buildAgenda(s, slide) {
  decorate(slide, { eyebrow: "MEETING ROADMAP" });

  slide.addText(s.title, {
    x: 0.5, y: 0.7, w: 12, h: 1,
    fontFace: FONT_HEAD, fontSize: 48, bold: true,
    color: theme.text,
  });

  // 2-column agenda grid
  const colW = 5.6;
  const rowH = 0.65;
  const startX = 0.7;
  const startY = 2.2;
  const half = Math.ceil(s.items.length / 2);

  s.items.forEach((item, i) => {
    const col = i < half ? 0 : 1;
    const row = i < half ? i : i - half;
    const x = startX + col * (colW + 0.5);
    const y = startY + row * (rowH + 0.2);

    slide.addShape(pres.ShapeType.roundRect, {
      x, y, w: colW, h: rowH,
      fill: { color: theme.bgAccent }, line: { color: theme.divider, width: 0.5 },
      rectRadius: 0.08,
    });
    slide.addText(`${(i + 1).toString().padStart(2, "0")}`, {
      x: x + 0.15, y, w: 0.7, h: rowH,
      fontFace: FONT_HEAD, fontSize: 18, bold: true,
      color: theme.accent, valign: "middle",
    });
    slide.addText(item, {
      x: x + 0.85, y, w: colW - 1, h: rowH,
      fontFace: FONT_BODY, fontSize: 16,
      color: theme.text, valign: "middle",
    });
  });
}

function buildSection(s, slide) {
  decorate(slide, { eyebrow: "WELCOME" });

  slide.addText(s.title, {
    x: 0.5, y: 0.7, w: 12, h: 1,
    fontFace: FONT_HEAD, fontSize: 44, bold: true,
    color: theme.text,
  });

  // Big lead quote
  slide.addText(`"${s.lead}"`, {
    x: 0.7, y: 2.2, w: 11.9, h: 2,
    fontFace: FONT_HEAD, fontSize: 24, italic: true,
    color: theme.accent, valign: "top",
  });

  // Sub-items as pills
  const startX = 0.7;
  const startY = 4.8;
  const pillW = 3.8;
  s.items.forEach((it, i) => {
    const x = startX + i * (pillW + 0.3);
    slide.addShape(pres.ShapeType.roundRect, {
      x, y: startY, w: pillW, h: 0.9,
      fill: { color: theme.bgAccent }, line: { color: theme.accent, width: 1 },
      rectRadius: 0.45,
    });
    slide.addText(it, {
      x, y: startY, w: pillW, h: 0.9,
      fontFace: FONT_HEAD, fontSize: 18, bold: true,
      color: theme.text, align: "center", valign: "middle",
    });
  });
}

function buildLevels(s, slide) {
  decorate(slide, { eyebrow: "REFERENCE" });

  slide.addText(s.title, {
    x: 0.5, y: 0.7, w: 12, h: 1,
    fontFace: FONT_HEAD, fontSize: 44, bold: true,
    color: theme.text,
  });

  const startX = 0.7;
  const startY = 2.1;
  const rowH = 0.7;
  const numW = 1.0;

  // Color scale across levels (indigo -> periwinkle -> sky -> gold)
  const palette = ["3F3E87", "5D5CB0", "8080FF", "80BEFF", "FFD466", "FFB901"];

  s.levels.forEach((lvl, i) => {
    const y = startY + i * (rowH + 0.1);
    slide.addShape(pres.ShapeType.roundRect, {
      x: startX, y, w: numW, h: rowH,
      fill: { color: palette[i] }, line: { type: "none" },
      rectRadius: 0.08,
    });
    slide.addText(`L${lvl.n}`, {
      x: startX, y, w: numW, h: rowH,
      fontFace: FONT_HEAD, fontSize: 24, bold: true,
      color: theme.text, align: "center", valign: "middle",
    });
    slide.addShape(pres.ShapeType.rect, {
      x: startX + numW + 0.15, y: y + 0.05, w: 11, h: rowH - 0.1,
      fill: { color: theme.bgAccent }, line: { type: "none" },
    });
    slide.addText(lvl.label, {
      x: startX + numW + 0.4, y, w: 10.7, h: rowH,
      fontFace: FONT_BODY, fontSize: 18,
      color: theme.text, valign: "middle",
    });
  });
}

function buildNews(s, slide) {
  const eyebrowSuffix = s.tier && s.tier !== "high" ? ` · ${s.tier} signal` : "";
  decorate(slide, { eyebrow: "AI LATEST NEWS" + eyebrowSuffix });

  slide.addText(s.title, {
    x: 0.5, y: 0.65, w: 9.5, h: 0.7,
    fontFace: FONT_HEAD, fontSize: 28, bold: true,
    color: theme.text,
  });

  if (s.subtitle) {
    slide.addText(s.subtitle, {
      x: 0.5, y: 1.2, w: 9.5, h: 0.4,
      fontFace: FONT_BODY, fontSize: 13, italic: true,
      color: theme.accent2,
    });
  }

  // Allocate vertical space proportional to URL count to keep all links visible.
  const startY = 1.75;
  const totalH = H - startY - 0.5;
  const weights = s.bullets.map((b) => 1 + Math.max(0, (b.urls?.length ?? 1) - 1) * 0.32);
  const wSum = weights.reduce((a, b) => a + b, 0);
  let cursor = startY;

  s.bullets.forEach((b, i) => {
    const rowH = (totalH * weights[i]) / wSum;
    const y = cursor;
    cursor += rowH;

    // Left accent dot (brand red)
    slide.addShape(pres.ShapeType.ellipse, {
      x: 0.55, y: y + 0.18, w: 0.16, h: 0.16,
      fill: { color: theme.brandRed }, line: { type: "none" },
    });

    // Title + body
    const richText = [
      { text: b.title, options: { fontFace: FONT_HEAD, fontSize: 12.5, bold: true, color: theme.text } },
      { text: "  —  ", options: { fontSize: 12.5, color: theme.brandRed } },
      { text: b.body, options: { fontFace: FONT_BODY, fontSize: 11, color: theme.text } },
    ];
    slide.addText(richText, {
      x: 0.85, y: y + 0.02, w: 12.2, h: rowH - 0.05,
      valign: "top",
    });

    // ALL URLs — each as separate hyperlinked line
    const urls = b.urls ?? [];
    const urlBlock = urls.flatMap((u, j) => [
      ...(j > 0 ? [{ text: "\n", options: { fontSize: 4 } }] : []),
      { text: u, options: { fontFace: FONT_BODY, fontSize: 8.5, color: theme.accent, hyperlink: { url: u } } },
    ]);
    if (urlBlock.length > 0) {
      const bodyChars = b.body.length + b.title.length;
      const titleBodyLines = Math.max(2, Math.ceil(bodyChars / 110));
      const urlY = y + 0.04 + titleBodyLines * 0.21;
      slide.addText(urlBlock, {
        x: 0.85, y: urlY, w: 12.2, h: rowH - (urlY - y) - 0.02,
        valign: "top",
      });
    }
  });
}

function buildCondensed(s, slide) {
  const eyebrow = `AI LATEST NEWS · ${s.tier} signal`;
  decorate(slide, { eyebrow });

  slide.addText(s.title, {
    x: 0.5, y: 0.65, w: 9.5, h: 0.6,
    fontFace: FONT_HEAD, fontSize: 24, bold: true,
    color: theme.text,
  });

  if (s.subtitle) {
    slide.addText(s.subtitle, {
      x: 0.5, y: 1.15, w: 9.5, h: 0.35,
      fontFace: FONT_BODY, fontSize: 12, italic: true,
      color: theme.accent2,
    });
  }

  const startY = 1.6;
  const totalH = H - startY - 0.5;
  const useTwoCol = s.bullets.length > 7;
  const colW = useTwoCol ? (W - 1.4) / 2 - 0.2 : W - 1.4;
  const colCount = useTwoCol ? 2 : 1;
  const rowsPerCol = Math.ceil(s.bullets.length / colCount);
  const rowH = totalH / rowsPerCol;

  s.bullets.forEach((b, i) => {
    const col = useTwoCol ? Math.floor(i / rowsPerCol) : 0;
    const row = useTwoCol ? i % rowsPerCol : i;
    const x = 0.7 + col * (colW + 0.4);
    const y = startY + row * rowH;

    slide.addShape(pres.ShapeType.ellipse, {
      x, y: y + 0.14, w: 0.12, h: 0.12,
      fill: { color: theme.accent2 }, line: { type: "none" },
    });

    const rich = [
      { text: b.title, options: { fontFace: FONT_HEAD, fontSize: 10, bold: true, color: theme.text } },
    ];
    if (b.body) {
      rich.push({ text: " — ", options: { fontSize: 10, color: theme.brandRed } });
      rich.push({ text: b.body, options: { fontFace: FONT_BODY, fontSize: 9, color: theme.textMuted } });
    }
    slide.addText(rich, {
      x: x + 0.2, y, w: colW - 0.25, h: rowH * 0.55,
      valign: "top",
    });

    const urls = b.urls ?? [];
    if (urls.length > 0) {
      const urlText = urls.flatMap((u, j) => [
        ...(j > 0 ? [{ text: "\n", options: { fontSize: 3 } }] : []),
        { text: u, options: { fontFace: FONT_BODY, fontSize: 7, color: theme.accent, hyperlink: { url: u } } },
      ]);
      slide.addText(urlText, {
        x: x + 0.2, y: y + rowH * 0.55, w: colW - 0.25, h: rowH * 0.4,
        valign: "top",
      });
    }
  });
}

function buildPatterns(s, slide) {
  decorate(slide, { eyebrow: "SYNTHESIS" });

  slide.addText(s.title, {
    x: 0.5, y: 0.65, w: 12, h: 0.6,
    fontFace: FONT_HEAD, fontSize: 28, bold: true,
    color: theme.text,
  });

  if (s.subtitle) {
    slide.addText(s.subtitle, {
      x: 0.5, y: 1.2, w: 12, h: 0.35,
      fontFace: FONT_BODY, fontSize: 13, italic: true,
      color: theme.accent2,
    });
  }

  const startY = 1.7;
  const totalH = H - startY - 0.5;
  const rowH = totalH / s.items.length;

  s.items.forEach((it, i) => {
    const y = startY + i * rowH;
    slide.addText("→", {
      x: 0.55, y: y + 0.04, w: 0.4, h: rowH,
      fontFace: FONT_HEAD, fontSize: 16, bold: true,
      color: theme.brandRed, valign: "top",
    });
    const rich = [
      { text: it.title, options: { fontFace: FONT_HEAD, fontSize: 11, bold: true, color: theme.accent2 } },
      { text: " — ", options: { fontSize: 11, color: theme.brandRed } },
      { text: it.body, options: { fontFace: FONT_BODY, fontSize: 10, color: theme.text } },
    ];
    slide.addText(rich, {
      x: 1.0, y: y + 0.02, w: 12.0, h: rowH - 0.04,
      valign: "top",
    });
  });
}

function buildOpen(s, slide) {
  slide.background = { color: theme.bg };

  // Brand glow
  slide.addShape(pres.ShapeType.ellipse, {
    x: -2, y: -2, w: 8, h: 8,
    fill: { color: theme.brandRed, transparency: 78 }, line: { type: "none" },
  });
  slide.addShape(pres.ShapeType.ellipse, {
    x: W - 4, y: H - 5, w: 7, h: 7,
    fill: { color: theme.accent2, transparency: 80 }, line: { type: "none" },
  });

  if (logoWhiteData) {
    slide.addImage({
      data: logoWhiteData,
      x: W / 2 - 1.4, y: 0.9, w: 2.8, h: 0.75,
      sizing: { type: "contain", w: 2.8, h: 0.75 },
    });
  }

  slide.addText("SHARE THE FLOOR", {
    x: 0, y: 2.2, w: W, h: 0.5,
    fontFace: FONT_HEAD, fontSize: 16, bold: true,
    color: theme.brandRed, align: "center", charSpacing: 14,
  });

  slide.addText(s.title, {
    x: 0, y: 2.8, w: W, h: 1.6,
    fontFace: FONT_HEAD, fontSize: 90, bold: true,
    color: theme.text, align: "center",
  });

  slide.addText(s.subtitle, {
    x: 0.7, y: 4.7, w: W - 1.4, h: 0.7,
    fontFace: FONT_HEAD, fontSize: 24,
    color: theme.accent3, align: "center",
  });

  if (s.note) {
    slide.addText(s.note, {
      x: 0.7, y: 5.6, w: W - 1.4, h: 0.5,
      fontFace: FONT_BODY, fontSize: 14, italic: true,
      color: theme.textMuted, align: "center",
    });
  }
}

function buildPrompt(s, slide) {
  decorate(slide, { eyebrow: "DISCUSSION" });

  slide.addText(s.title, {
    x: 0.5, y: 0.7, w: 12, h: 1,
    fontFace: FONT_HEAD, fontSize: 44, bold: true,
    color: theme.text,
  });

  // Centered question — brand-red border for energy
  slide.addShape(pres.ShapeType.roundRect, {
    x: 1.2, y: 2.5, w: 10.9, h: 2.6,
    fill: { color: theme.bgAccent }, line: { color: theme.brandRed, width: 3 },
    rectRadius: 0.2,
  });

  slide.addText(`"${s.prompt}"`, {
    x: 1.4, y: 2.5, w: 10.5, h: 2.6,
    fontFace: FONT_HEAD, fontSize: 32, italic: true,
    color: theme.accent2, align: "center", valign: "middle",
  });

  if (s.note) {
    slide.addText(s.note, {
      x: 0.7, y: 5.4, w: 11.9, h: 0.6,
      fontFace: FONT_BODY, fontSize: 16,
      color: theme.textMuted, align: "center", italic: true,
    });
  }
}

function buildBlank(s, slide) {
  decorate(slide, { eyebrow: "TASK FORCE" });

  slide.addText(s.title, {
    x: 0.5, y: 0.7, w: 12, h: 1,
    fontFace: FONT_HEAD, fontSize: 44, bold: true,
    color: theme.text,
  });

  // Open canvas — placeholder hint only
  slide.addShape(pres.ShapeType.roundRect, {
    x: 0.7, y: 2.2, w: 11.9, h: 4.4,
    fill: { color: theme.bgAccent, transparency: 50 }, line: { color: theme.divider, width: 1, dashType: "dash" },
    rectRadius: 0.15,
  });

  slide.addText(s.placeholder, {
    x: 0.7, y: 2.2, w: 11.9, h: 4.4,
    fontFace: FONT_BODY, fontSize: 18,
    color: theme.textMuted, align: "center", valign: "middle", italic: true,
  });
}

function buildQA(s, slide) {
  slide.background = { color: theme.bg };

  // Brand glow decorations
  slide.addShape(pres.ShapeType.ellipse, {
    x: -2, y: -2, w: 8, h: 8,
    fill: { color: theme.accent, transparency: 80 }, line: { type: "none" },
  });
  slide.addShape(pres.ShapeType.ellipse, {
    x: W - 4, y: H - 5, w: 7, h: 7,
    fill: { color: theme.accent2, transparency: 85 }, line: { type: "none" },
  });
  slide.addShape(pres.ShapeType.ellipse, {
    x: W / 2 - 3, y: 1.5, w: 6, h: 6,
    fill: { color: theme.bgCard, transparency: 75 }, line: { type: "none" },
  });

  // Logo top-center
  if (logoWhiteData) {
    slide.addImage({
      data: logoWhiteData,
      x: W / 2 - 1.4, y: 0.7, w: 2.8, h: 0.75,
      sizing: { type: "contain", w: 2.8, h: 0.75 },
    });
  }

  slide.addText("Q & A", {
    x: 0, y: 2.5, w: W, h: 2,
    fontFace: FONT_HEAD, fontSize: 140, bold: true,
    color: theme.text, align: "center",
  });

  slide.addText(s.subtitle, {
    x: 0, y: 4.7, w: W, h: 0.6,
    fontFace: FONT_HEAD, fontSize: 22,
    color: theme.accent, align: "center", charSpacing: 8,
  });

  slide.addShape(pres.ShapeType.line, {
    x: W / 2 - 1, y: 5.6, w: 2, h: 0,
    line: { color: theme.brandRed, width: 3 },
  });
}

// ----- Main loop ------------------------------------------------------------

const total = slides.length;
slides.forEach((s, i) => {
  const slide = pres.addSlide();
  switch (s.type) {
    case "title":   buildTitle(s, slide); break;
    case "agenda":  buildAgenda(s, slide); break;
    case "section": buildSection(s, slide); break;
    case "levels":  buildLevels(s, slide); break;
    case "news":    buildNews(s, slide); break;
    case "condensed": buildCondensed(s, slide); break;
    case "patterns": buildPatterns(s, slide); break;
    case "prompt":  buildPrompt(s, slide); break;
    case "blank":   buildBlank(s, slide); break;
    case "qa":      buildQA(s, slide); break;
    case "open":    buildOpen(s, slide); break;
    default: throw new Error(`Unknown slide type: ${s.type}`);
  }
  if (s.type !== "title" && s.type !== "qa") {
    addSlideNumber(slide, i + 1, total);
  }
  if (s.speakerNotes) {
    slide.addNotes(s.speakerNotes);
  }
});

await fs.promises.mkdir(meetingsDir(), { recursive: true });
await pres.writeFile({ fileName: OUTPUT });
console.log(`PPTX written: ${OUTPUT}`);
console.log(`Slide count: ${total}`);
