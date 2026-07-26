// Section grouping and HTML fragment generation for single-file HTML deck.

import { formatUrlDisplay } from "./lib/url-display.js";
import { isAllowedUrlScheme } from "./lib/url-policy.js";

export const escape = (s) =>
  String(s ?? "")
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;");

const SECTION_LABELS = {
  hero: "Cover",                  // renamed from "Hero" — chip label only; section id stays "hero"
  open: "Open Share",
  agenda: "Agenda",
  welcome: "Welcome",
  levels: "Levels",
  anthropic: "Anthropic",
  openai: "OpenAI",
  legal: "Legal & Reg.",
  google: "Google",
  cursor: "Cursor",
  xai: "xAI / Grok",
  meta: "Meta / Llama",
  deepseek: "DeepSeek",
  microsoft: "Microsoft",
  other: "Other",
  compute: "Compute",
  "real-world": "Real-world",
  extras: "Extras",
  patterns: "Patterns",
  pace: "Pace",
  devtools: "Dev Tools",
  breaking: "Breaking & Deprecated",
  tools: "Tools",
  tips: "Tips",
  problems: "Problems",
  taskforce: "Task Force",
  qa: "Q&A",
};

// Linear primary nav order. "news" is a virtual chip — no section element with id="news";
// it represents the parent grouping of all `parentSection: "news"` sections.
const PRIMARY_NAV_ORDER = ["hero", "agenda", "welcome", "levels", "news", "tools", "tips", "problems", "taskforce", "qa"];

// Group consecutive slides sharing the same section.
export function groupSections(allSlides) {
  const groups = [];
  let current = null;
  for (const s of allSlides) {
    const key = s.section || `_unsec_${groups.length}`;
    if (!current || current.key !== key) {
      current = { key, slides: [] };
      groups.push(current);
    }
    current.slides.push(s);
  }
  return groups;
}

function renderHero(s, logoWhiteData) {
  return `
  <div class="hero-bg">
    <span class="orb orb-1"></span>
    <span class="orb orb-2"></span>
    <span class="orb orb-3"></span>
    <span class="orb orb-4"></span>
    <div class="hero-grid"></div>
  </div>
  <div class="hero-bar-top"></div>
  <div class="hero-bar-bottom"></div>
  <div class="hero-content">
    ${logoWhiteData ? `<img class="hero-logo" src="${logoWhiteData}" alt="" />` : ""}
    <p class="hero-eyebrow">${escape(s.eyebrow)}</p>
    <h1 class="hero-title">${escape(s.title)}</h1>
    <p class="hero-date">${escape(s.subtitle)}</p>
  </div>
  <p class="hero-hint">↓ scroll · or use ← → to step sections</p>`;
}

function renderAgenda(s) {
  return `
  <h2 class="section-h2">${escape(s.title)}</h2>
  <ol class="agenda-grid">
    ${s.items.map((it, i) => `
      <li class="agenda-card">
        <span class="agenda-num">${String(i + 1).padStart(2, "0")}</span>
        <span class="agenda-text">${escape(it)}</span>
      </li>
    `).join("")}
  </ol>`;
}

function renderWelcome(s) {
  return `
  <h2 class="section-h2">${escape(s.title)}</h2>
  <blockquote class="lead-quote">${escape(s.lead)}</blockquote>
  <ul class="pill-row">
    ${s.items.map((it) => `<li class="pill">${escape(it)}</li>`).join("")}
  </ul>`;
}

function renderLevels(s) {
  const palette = ["#3F3E87", "#5D5CB0", "#8080FF", "#80BEFF", "#FFD466", "#FFB901"];
  const goldIdx = [4, 5];
  return `
  <h2 class="section-h2">${escape(s.title)}</h2>
  <ul class="levels-list">
    ${s.levels.map((lvl, i) => `
      <li class="level-row">
        <span class="level-badge${goldIdx.includes(i) ? " gold" : ""}" style="background:${palette[i]}">L${lvl.n}</span>
        <span class="level-text">${escape(lvl.label)}</span>
      </li>
    `).join("")}
  </ul>`;
}

function renderOpen(s, logoWhiteData) {
  return `
  <span class="orb orb-open-1"></span>
  <span class="orb orb-open-2"></span>
  <div class="open-content">
    ${logoWhiteData ? `<img class="open-logo" src="${logoWhiteData}" alt="" />` : ""}
    <p class="open-eyebrow">SHARE THE FLOOR</p>
    <h2 class="open-title">${escape(s.title)}</h2>
    <p class="open-sub">${escape(s.subtitle)}</p>
    ${s.note ? `<p class="open-note">${escape(s.note)}</p>` : ""}
  </div>`;
}

function renderPrompt(s) {
  return `
  <h2 class="section-h2">${escape(s.title)}</h2>
  <div class="prompt-card">
    <p class="prompt-q">&ldquo;${escape(s.prompt)}&rdquo;</p>
  </div>
  ${s.note ? `<p class="prompt-note">${escape(s.note)}</p>` : ""}`;
}

function renderBlank(s) {
  return `
  <h2 class="section-h2">${escape(s.title)}</h2>
  <div class="blank-card">
    <p>${escape(s.placeholder)}</p>
  </div>`;
}

function renderQA(s, logoWhiteData) {
  return `
  <span class="orb orb-qa-1"></span>
  <span class="orb orb-qa-2"></span>
  <span class="orb orb-qa-3"></span>
  <div class="qa-content">
    ${logoWhiteData ? `<img class="qa-logo" src="${logoWhiteData}" alt="" />` : ""}
    <h2 class="qa-big">Q &amp; A</h2>
    <p class="qa-sub">${escape(s.subtitle)}</p>
    <div class="qa-line"></div>
  </div>`;
}

function renderPatterns(s) {
  return `
  <p class="section-eyebrow">SYNTHESIS</p>
  <h2 class="section-h2">${escape(s.title)}</h2>
  ${s.subtitle ? `<p class="section-sub">${escape(s.subtitle)}</p>` : ""}
  <ul class="patterns-list">
    ${s.items.map((it) => `
      <li class="pattern-item">
        <span class="pattern-arrow">→</span>
        <div class="pattern-body">
          <span class="pattern-headline">${escape(it.title)}</span>
          <span class="pattern-text"> — ${escape(it.body)}</span>
        </div>
      </li>
    `).join("")}
  </ul>`;
}

function renderNewsSection(sectionKey, sectionSlides, providerLogoSvg) {
  const label = SECTION_LABELS[sectionKey] || sectionKey;
  const provider = sectionSlides.find((s) => s.provider)?.provider || sectionKey;
  const providerLogo = providerLogoSvg[provider]
    ? `<span class="provider-logo">${providerLogoSvg[provider]}</span>`
    : "";

  const byTier = { high: [], med: [], low: [] };
  for (const s of sectionSlides) {
    const tier = s.tier || (s.type === "news" ? "high" : "med");
    if (byTier[tier]) byTier[tier].push(...(s.bullets || []));
  }

  const tierBlock = (tier, heading) => {
    const bullets = byTier[tier];
    if (!bullets || bullets.length === 0) return "";
    return `
    <div class="tier tier-${tier}">
      <h3 class="tier-heading">${heading}</h3>
      <ul class="news-list ${tier === "high" ? "" : "compact"}">
        ${bullets.map((b) => {
          const urls = (b.urls || []).filter(isAllowedUrlScheme);
          const dateStr = b.date ? new Date(b.date).toISOString().slice(0, 10) : "";
          return `
        <li class="news-item">
          <span class="news-dot"></span>
          <div class="news-body">
            ${dateStr ? `<span class="news-date">${escape(dateStr)}</span> ` : ""}<span class="news-headline">${escape(b.title)}</span>
            ${b.body ? `<span class="news-em-dash"> — </span><span class="news-text">${escape(b.body)}</span>` : ""}
            ${urls.length ? `<ul class="news-urls">${urls.map((u) => `<li><a class="news-url" href="${escape(u)}" target="_blank" rel="noreferrer">${escape(formatUrlDisplay(u))}</a></li>`).join("")}</ul>` : ""}
          </div>
        </li>`;
        }).join("")}
      </ul>
    </div>`;
  };

  return `
  <header class="section-header">
    ${providerLogo}
    <div class="section-header-text">
      <p class="section-eyebrow">AI LATEST NEWS</p>
      <h2 class="section-h2">${escape(label)}</h2>
    </div>
  </header>
  ${tierBlock("high", "Highlights")}
  ${tierBlock("med", "Also worth noting")}
  ${tierBlock("low", "Color &amp; notes")}`;
}

function renderGroup(group, logoWhiteData, providerLogoSvg) {
  const lead = group.slides[0];
  const sectionKey = group.key;
  const cls = `section section-${sectionKey} type-${lead.type}`;

  let inner = "";
  if (lead.type === "title") inner = renderHero(lead, logoWhiteData);
  else if (lead.type === "agenda") inner = renderAgenda(lead);
  else if (lead.type === "section") inner = renderWelcome(lead);
  else if (lead.type === "levels") inner = renderLevels(lead);
  else if (lead.type === "open") inner = renderOpen(lead, logoWhiteData);
  else if (lead.type === "prompt") inner = renderPrompt(lead);
  else if (lead.type === "blank") inner = renderBlank(lead);
  else if (lead.type === "qa") inner = renderQA(lead, logoWhiteData);
  else if (lead.type === "patterns") inner = renderPatterns(lead);
  else if (lead.type === "news" || lead.type === "condensed") {
    inner = renderNewsSection(sectionKey, group.slides, providerLogoSvg);
  } else {
    inner = `<h2>Unknown: ${escape(lead.type)}</h2>`;
  }

  const notesPieces = group.slides
    .map((s) => (s.speakerNotes || "").trim())
    .filter((n) => n.length > 0);
  const notesAside = notesPieces.length > 0
    ? `<aside class="speaker-notes" aria-hidden="true">${notesPieces.map((n) => escape(n)).join(" • ")}</aside>`
    : "";

  return `<section id="${escape(sectionKey)}" class="${cls}">${inner}${notesAside}</section>`;
}

function renderTopnav(groups, meta, logoWhiteData) {
  const groupKeys = new Set(groups.map((g) => g.key));

  const newsSubKeys = groups
    .filter((g) => g.slides[0]?.parentSection === "news")
    .map((g) => g.key);

  const primaryChips = PRIMARY_NAV_ORDER
    .filter((k) => k === "news" || groupKeys.has(k))
    .map((k) => {
      const label = k === "news" ? "News" : (SECTION_LABELS[k] || k);
      const isNewsChip = k === "news" ? "chip-news-parent" : "";
      return `<li><a href="#${escape(k)}" class="${isNewsChip}" data-key="${escape(k)}">${escape(label)}</a></li>`;
    }).join("");

  const subChips = newsSubKeys.map((k) => {
    const label = SECTION_LABELS[k] || k;
    return `<li><a href="#${escape(k)}" class="chip-news-sub" data-key="${escape(k)}">${escape(label)}</a></li>`;
  }).join("");

  return `
  <nav id="topnav" aria-label="Section navigation">
    <a class="topnav-brand" href="#hero" aria-label="Top">
      ${logoWhiteData ? `<img src="${logoWhiteData}" alt="" />` : ""}
      <span class="topnav-meta"><span class="topnav-mtg">AI Meeting #${meta.meetingNumber}</span><span class="topnav-date">${escape(meta.date)}</span></span>
    </a>
    <div class="chips-wrap">
      <ul class="chips chips-primary" role="list" aria-label="Primary sections">
        ${primaryChips}
      </ul>
      <ul class="chips chips-sub" role="list" aria-label="News subsections" data-news-sub>
        <li class="chips-label">News</li>
        ${subChips}
      </ul>
    </div>
  </nav>`;
}

export function buildSections({ slides, meta, logoWhiteData, providerLogoSvg }) {
  const groups = groupSections(slides);
  const sectionsHtml = groups.map((g) => renderGroup(g, logoWhiteData, providerLogoSvg)).join("\n");
  const topnavHtml = renderTopnav(groups, meta, logoWhiteData);
  return { sectionsHtml, topnavHtml, groups };
}
