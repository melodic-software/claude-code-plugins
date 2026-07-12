// CSS generation for single-file HTML deck.

export function buildCss(theme) {
  return `
:root {
  --bg: #${theme.bg};
  --bg-accent: #${theme.bgAccent};
  --bg-card: #${theme.bgCard};
  --brand-indigo: #${theme.brandIndigo};
  --brand-red: #${theme.brandRed};
  --accent: #${theme.accent};
  --accent2: #${theme.accent2};
  --accent3: #${theme.accent3};
  --text: #${theme.text};
  --text-muted: #${theme.textMuted};
  --divider: #${theme.divider};
  --font-head: ${theme.htmlFontHead};
  --font-body: ${theme.htmlFontBody};

  /* Fluid typography per RESEARCH-ux.md §4 (clamp + WCAG large-text floor 24px) */
  --fs-body: clamp(1.1rem, 0.9vw + 0.7rem, 1.4rem);
  --fs-body-tight: clamp(1.05rem, 0.8vw + 0.65rem, 1.3rem);
  --fs-card-title: clamp(1.4rem, 1.4vw + 0.8rem, 2rem);
  --fs-tier-h3: clamp(1.5rem, 1.5vw + 0.8rem, 2.25rem);
  --fs-section-h2: clamp(2.4rem, 3.5vw + 0.5rem, 4.25rem);
  /* Hero capped tight so 'AI Meeting #N' (15-char band w/ Ubuntu Bold) fits 1366+ */
  --fs-hero: clamp(2.75rem, 5.6vw, 6.25rem);
  --fs-hero-date: clamp(1.4rem, 1.4vw + 0.5rem, 2.2rem);
  --fs-eyebrow: clamp(0.7rem, 0.4vw + 0.55rem, 0.95rem);

  --nav-h: 64px;        /* primary row only; sub-strip overlays when expanded */
  --nav-h-expanded: 116px; /* primary + sub-strip when on news territory */
  --section-pad-x: 5vw;
  --section-pad-y: 4.5vh;
  --content-max: 1400px;
}

* { box-sizing: border-box; margin: 0; padding: 0; }
*::-webkit-scrollbar { width: 10px; height: 10px; }
*::-webkit-scrollbar-track { background: var(--bg); }
*::-webkit-scrollbar-thumb { background: var(--divider); border-radius: 5px; }
*::-webkit-scrollbar-thumb:hover { background: var(--accent); }

html {
  scroll-snap-type: y proximity;
  /* Reserve for collapsed primary row only (sub-strip is overlay-friendly) */
  scroll-padding-top: var(--nav-h);
  scroll-behavior: smooth;
  background: var(--bg);
  color: var(--text);
  font-family: var(--font-body);
  font-size: 16px;
  -webkit-font-smoothing: antialiased;
  -moz-osx-font-smoothing: grayscale;
}
body.in-news { /* sub-strip expanded — bump scroll-padding so anchor jumps land below it */ }
body.in-news html, html:has(body.in-news) {
  scroll-padding-top: var(--nav-h-expanded);
}
body { font-size: var(--fs-body); min-height: 100vh; }
img { display: block; }
a { color: var(--accent3); }
a:hover { color: var(--accent2); }

/* ─── Top sticky nav (linear primary + collapsing news sub-strip) ─── */
#topnav {
  position: sticky; top: 0; z-index: 50;
  display: flex; align-items: stretch; gap: 1rem;
  padding: 0 var(--section-pad-x);
  background: rgba(15, 21, 48, 0.94);
  backdrop-filter: blur(12px);
  -webkit-backdrop-filter: blur(12px);
  border-bottom: 1px solid var(--divider);
  transition: padding 220ms ease;
}
.topnav-brand {
  display: flex; align-items: center; gap: 0.8rem;
  text-decoration: none; color: var(--text);
  flex-shrink: 0; min-height: var(--nav-h);
}
.topnav-brand img { height: 36px; width: auto; flex-shrink: 0; }
.topnav-meta {
  display: flex; flex-direction: column; justify-content: center;
  font-family: var(--font-head); line-height: 1.15;
}
.topnav-mtg { font-size: 0.95rem; font-weight: 700; color: var(--text); }
.topnav-date { font-size: 0.78rem; color: var(--text-muted); letter-spacing: 0.04em; }

.chips-wrap {
  flex: 1; min-width: 0;
  display: flex; flex-direction: column; justify-content: flex-start;
}
.chips {
  display: flex; gap: 0.45rem; list-style: none;
  overflow-x: auto; flex-wrap: nowrap;
  scrollbar-width: none;
  align-items: center;
}
.chips::-webkit-scrollbar { display: none; }

/* Primary row — always visible at nav-h height */
.chips-primary {
  min-height: var(--nav-h);
}
.chips-primary a {
  display: inline-flex; align-items: center;
  padding: 0.4rem 1rem; border-radius: 999px;
  border: 1px solid var(--divider);
  color: var(--text-muted);
  font-family: var(--font-head); font-weight: 600;
  font-size: 0.88rem; letter-spacing: 0.03em;
  text-decoration: none; white-space: nowrap;
  transition: background 180ms, color 180ms, border-color 180ms, box-shadow 180ms;
  flex-shrink: 0;
}
.chips-primary a:hover {
  color: var(--text); border-color: var(--accent);
}
.chips-primary a[aria-current="location"] {
  background: var(--accent); color: var(--text); border-color: var(--accent);
}
/* "News" parent chip — visually distinct (brand-red active state) */
.chip-news-parent {
  font-weight: 700 !important;
  border-color: var(--accent) !important;
  color: var(--text) !important;
}
.chip-news-parent::before {
  content: "";
  display: inline-block; width: 8px; height: 8px; border-radius: 50%;
  background: var(--brand-red); margin-right: 0.5rem;
  box-shadow: 0 0 10px rgba(216,56,24,0.6);
}
.chip-news-parent[aria-current="location"] {
  background: var(--brand-red) !important; border-color: var(--brand-red) !important;
  box-shadow: 0 0 14px rgba(216,56,24,0.5);
}
.chip-news-parent[aria-current="location"]::before {
  background: var(--text);
  box-shadow: 0 0 10px rgba(255,255,255,0.6);
}

/* Sub-strip — collapsed by default; expands when body.in-news class is set */
.chips-sub {
  max-height: 0;
  overflow: hidden;
  padding: 0;
  border-top: 0 solid var(--divider);
  opacity: 0;
  transition: max-height 220ms ease, opacity 180ms ease, padding 220ms ease, border-top-width 220ms ease;
  align-items: center;
  gap: 0.35rem;
}
body.in-news .chips-sub {
  max-height: 52px;
  opacity: 1;
  padding: 0.5rem 0;
  border-top: 1px solid var(--divider);
}
.chips-sub .chips-label {
  font-family: var(--font-head); font-weight: 700; font-size: 0.65rem;
  letter-spacing: 0.3em; color: var(--accent2); text-transform: uppercase;
  padding: 0 0.65rem 0 0; flex-shrink: 0; line-height: 1;
}
.chips-sub a {
  display: inline-flex; align-items: center;
  padding: 0.28rem 0.8rem; border-radius: 999px;
  border: 1px solid var(--divider);
  color: var(--text-muted);
  font-family: var(--font-head); font-weight: 500;
  font-size: 0.78rem; letter-spacing: 0.03em;
  text-decoration: none; white-space: nowrap;
  transition: background 180ms, color 180ms, border-color 180ms;
  flex-shrink: 0;
}
.chips-sub a:hover { color: var(--text); border-color: var(--accent); }
.chips-sub a[aria-current="location"] {
  background: var(--brand-red); color: var(--text); border-color: var(--brand-red);
  box-shadow: 0 0 10px rgba(216,56,24,0.4);
}

/* ─── Section container ─── */
.section {
  position: relative;
  min-height: calc(100vh - var(--nav-h));
  padding: var(--section-pad-y) var(--section-pad-x) 6vh;
  scroll-snap-align: start;
  display: flex; flex-direction: column;
}
.section > * { max-width: var(--content-max); width: 100%; margin-left: auto; margin-right: auto; }

/* Short-content sections — center vertically + horizontally for visual consistency */
.section.type-section,         /* welcome */
.section.type-prompt,          /* tools / tips / problems */
.section.type-blank,           /* taskforce */
.section.type-agenda {         /* agenda */
  justify-content: center;
  align-items: center;
  text-align: center;
}
.section.type-section .section-h2,
.section.type-prompt .section-h2,
.section.type-blank .section-h2,
.section.type-agenda .section-h2 {
  margin-left: auto; margin-right: auto;
}
.section.type-section .lead-quote {
  max-width: 70%; margin: 1.5rem auto 2.5rem; text-align: center;
}
.section.type-section .pill-row {
  justify-content: center;
}
.section.type-blank .blank-card {
  width: 100%; max-width: 1100px; margin: 1.5rem auto 0;
}

.section-eyebrow {
  font-family: var(--font-head); font-weight: 700; color: var(--accent2);
  letter-spacing: 0.4em; font-size: var(--fs-eyebrow);
  text-transform: uppercase; margin-bottom: 0.8rem;
}
.section-h2 {
  font-family: var(--font-head); font-weight: 800;
  font-size: var(--fs-section-h2); line-height: 1.05;
  margin-bottom: 1.2rem; text-wrap: balance;
}
.section-sub {
  color: var(--accent3); font-style: italic;
  font-size: var(--fs-body); margin-bottom: 1.5rem;
}

/* ─── Hero — full-bleed, animated background, no max-width ─── */
.section-hero {
  background: linear-gradient(135deg, #0F0E2E 0%, #1F1E47 50%, #3F3E87 100%);
  align-items: stretch; justify-content: center;
  padding: 0; overflow: hidden;
  display: flex; flex-direction: column;
}
.section-hero > * { max-width: none; margin-left: 0; margin-right: 0; }
.hero-bar-top { position: absolute; top: 0; left: 0; right: 0; height: 14px; background: var(--accent); z-index: 3; }
.hero-bar-bottom { position: absolute; bottom: 0; left: 0; right: 0; height: 8px; background: var(--accent2); z-index: 3; }
.hero-bg { position: absolute; inset: 0; overflow: hidden; pointer-events: none; }
.hero-bg .orb {
  position: absolute; border-radius: 50%; filter: blur(80px);
  animation: orb-drift 24s ease-in-out infinite alternate;
}
.hero-bg .orb-1 { width: 75vh; height: 75vh; right: -10vh; top: -22vh; background: radial-gradient(circle, var(--accent) 0%, transparent 70%); opacity: 0.6; animation-duration: 22s; }
.hero-bg .orb-2 { width: 60vh; height: 60vh; left: -14vh; bottom: -16vh; background: radial-gradient(circle, var(--accent2) 0%, transparent 70%); opacity: 0.5; animation-duration: 28s; animation-delay: -8s; }
.hero-bg .orb-3 { width: 45vh; height: 45vh; left: 38%; top: 18%; background: radial-gradient(circle, var(--accent3) 0%, transparent 70%); opacity: 0.4; animation-duration: 18s; animation-delay: -4s; }
.hero-bg .orb-4 { width: 35vh; height: 35vh; right: 28%; bottom: 10%; background: radial-gradient(circle, var(--brand-red) 0%, transparent 70%); opacity: 0.28; animation-duration: 32s; animation-delay: -14s; }
@keyframes orb-drift {
  0%   { transform: translate(0, 0) scale(1); }
  50%  { transform: translate(8vh, -6vh) scale(1.08); }
  100% { transform: translate(-6vh, 4vh) scale(0.95); }
}
.hero-grid {
  position: absolute; inset: 0;
  background-image:
    linear-gradient(rgba(128,128,255,0.07) 1px, transparent 1px),
    linear-gradient(90deg, rgba(128,128,255,0.07) 1px, transparent 1px);
  background-size: 80px 80px;
  mask-image: radial-gradient(ellipse at center, black 30%, transparent 75%);
  -webkit-mask-image: radial-gradient(ellipse at center, black 30%, transparent 75%);
  opacity: 0.55;
  animation: grid-pan 60s linear infinite;
}
@keyframes grid-pan {
  0%   { background-position: 0 0; }
  100% { background-position: 80px 80px; }
}
@media (prefers-reduced-motion: reduce) {
  .hero-bg .orb { animation: none; }
  .hero-grid { animation: none; }
}
.hero-content {
  position: relative; z-index: 2;
  width: 100%;
  padding: 0 6vw;
  display: flex; flex-direction: column; justify-content: center;
  align-items: flex-start;   /* prevent flex-stretch from blowing up logo + headings */
  flex: 1;
  text-align: left;
}
.hero-content > * { max-width: 100%; }
.hero-logo {
  height: 7vh; max-height: 80px; width: auto;
  margin-bottom: 2vh;
  filter: drop-shadow(0 4px 12px rgba(0,0,0,0.3));
}
.hero-eyebrow {
  font-family: var(--font-head); font-weight: 700; color: var(--accent2);
  letter-spacing: 0.5em; font-size: clamp(0.85rem, 0.6vw + 0.5rem, 1.1rem);
  text-transform: uppercase; margin-bottom: 1rem;
}
.hero-title {
  font-family: var(--font-head); font-weight: 700;
  font-size: var(--fs-hero); line-height: 1;
  margin-bottom: 1.2rem; text-wrap: balance;
  background: linear-gradient(135deg, #FFFFFF 20%, #FFB901 80%, #80BEFF 100%);
  -webkit-background-clip: text; background-clip: text; color: transparent;
  letter-spacing: -0.02em;
  filter: drop-shadow(0 0 24px rgba(255,185,1,0.15));
  /* Hero font caps at 6.25rem (100px) so 'AI Meeting #N' fits 1280+ viewports */
}
.hero-date {
  font-family: var(--font-head); font-size: var(--fs-hero-date);
  color: var(--accent2); font-weight: 600; margin-bottom: 0;
}
.hero-hint {
  position: absolute; bottom: 4vh; left: 0; right: 0;
  z-index: 2;
  font-family: var(--font-body); font-size: 0.95rem; color: var(--text-muted);
  opacity: 0.6; letter-spacing: 0.05em;
  text-align: center;
  pointer-events: none;
}

/* ─── Agenda ─── */
.agenda-grid {
  list-style: none; display: grid;
  grid-template-columns: repeat(3, 1fr);
  grid-auto-rows: 1fr;
  gap: 1rem 1.2rem;
  width: 100%;
  max-width: 1280px;
  margin: 1.2rem auto 0;
  text-align: left;
}
.agenda-card {
  display: flex; align-items: center; gap: 1.1rem;
  background: var(--bg-accent); border: 1px solid var(--divider);
  border-radius: 12px; padding: 1.15rem 1.3rem;
  min-height: 5.5rem;
}
.agenda-num {
  font-family: var(--font-head); font-weight: 700;
  font-size: 1.6rem; color: var(--accent2);
  min-width: 2.6rem; flex-shrink: 0;
}
.agenda-text { font-size: var(--fs-body); color: var(--text); line-height: 1.35; }
@media (max-width: 1024px) {
  .agenda-grid { grid-template-columns: repeat(2, 1fr); }
}
@media (max-width: 640px) {
  .agenda-grid { grid-template-columns: 1fr; }
}

/* ─── Welcome ─── */
.lead-quote {
  font-family: var(--font-head); font-style: italic;
  font-size: clamp(1.5rem, 1.5vw + 0.8rem, 2.25rem);
  color: var(--accent); line-height: 1.4; margin: 1.5rem 0 2.5rem;
  max-width: 80%; text-wrap: balance;
}
.pill-row { display: flex; gap: 1.2rem; list-style: none; flex-wrap: wrap; }
.pill {
  font-family: var(--font-head); font-weight: 700; font-size: var(--fs-body);
  background: var(--bg-accent); border: 1.5px solid var(--accent);
  color: var(--text); padding: 0.7rem 1.8rem; border-radius: 999px;
}

/* ─── Levels ─── */
.levels-list { list-style: none; display: flex; flex-direction: column; gap: 0.7rem; }
.level-row { display: flex; align-items: stretch; gap: 0.9rem; }
.level-badge {
  font-family: var(--font-head); font-weight: 700; font-size: 1.4rem;
  color: var(--text); padding: 0.7rem 1.4rem; border-radius: 8px;
  display: flex; align-items: center; justify-content: center; min-width: 5rem;
}
.level-badge.gold { color: #1F1E47; }
.level-text {
  font-size: var(--fs-body); color: var(--text); flex: 1;
  background: var(--bg-accent); padding: 0 1.5rem;
  display: flex; align-items: center; border-radius: 6px;
}

/* ─── Open share ─── */
.section-open {
  background: linear-gradient(135deg, #1F1E47 0%, #3F3E87 60%, #082858 100%);
  align-items: center; justify-content: center; text-align: center;
  overflow: hidden;
}
.section-open .orb-open-1 {
  position: absolute; width: 75vh; height: 75vh; border-radius: 50%;
  left: 0; top: 0; transform: translate(-20vh, -20vh);
  background: radial-gradient(circle, var(--brand-red) 0%, transparent 70%);
  opacity: 0.18; filter: blur(80px);
  pointer-events: none;
}
.section-open .orb-open-2 {
  position: absolute; width: 60vh; height: 60vh; border-radius: 50%;
  right: 0; bottom: 0; transform: translate(15vh, 15vh);
  background: radial-gradient(circle, var(--accent2) 0%, transparent 70%);
  opacity: 0.22; filter: blur(70px);
  pointer-events: none;
}
.open-content {
  position: relative; z-index: 2; max-width: var(--content-max);
  margin: 0 auto; padding: 4vh 2rem;
}
.open-logo {
  height: 6vh; max-height: 60px; width: auto; margin: 0 auto 2.5vh;
  filter: drop-shadow(0 4px 12px rgba(0,0,0,0.4));
}
.open-eyebrow {
  font-family: var(--font-head); font-weight: 700; color: var(--brand-red);
  letter-spacing: 0.5em; font-size: clamp(0.85rem, 0.5vw + 0.55rem, 1.05rem);
  margin-bottom: 1.2rem;
}
.open-title {
  font-family: var(--font-head); font-weight: 700;
  font-size: clamp(2.5rem, 6vw, 6rem); line-height: 1; margin-bottom: 1.5rem;
  background: linear-gradient(135deg, #FFFFFF 30%, #FFB901 80%);
  -webkit-background-clip: text; background-clip: text; color: transparent;
  text-wrap: balance;
}
.open-sub {
  font-family: var(--font-head); font-weight: 600;
  font-size: clamp(1.2rem, 1.2vw + 0.6rem, 1.85rem);
  color: var(--accent3); margin: 0 auto 1.2rem; max-width: 80%; text-wrap: balance;
}
.open-note {
  font-family: var(--font-body); font-size: var(--fs-body); color: var(--text-muted);
  font-style: italic; max-width: 70%; margin: 0 auto;
}

/* ─── News section ─── */
.section-header {
  display: flex; align-items: center; gap: 1.5rem; margin-bottom: 2rem;
  padding-bottom: 1rem; border-bottom: 2px solid var(--brand-red);
}
.section-header .provider-logo {
  flex-shrink: 0; width: 64px; height: 64px;
  display: flex; align-items: center; justify-content: center;
  color: var(--text); opacity: 0.92;
}
.section-header .provider-logo svg { width: 100%; height: 100%; fill: currentColor; }
.section-header-text { flex: 1; min-width: 0; }
.section-header .section-eyebrow { margin-bottom: 0.4rem; }
.section-header .section-h2 { margin-bottom: 0; }

.tier { margin-bottom: 2.5rem; }
.tier:last-child { margin-bottom: 0; }
.tier-heading {
  font-family: var(--font-head); font-weight: 700;
  font-size: var(--fs-tier-h3); line-height: 1.2;
  margin-bottom: 1rem; padding-left: 0.8rem;
  border-left: 4px solid transparent;
}
.tier-high .tier-heading { border-left-color: var(--accent2); color: var(--accent2); }
.tier-med .tier-heading { border-left-color: var(--accent3); color: var(--accent3); }
.tier-low .tier-heading { border-left-color: var(--text-muted); color: var(--text-muted); }

.news-list {
  list-style: none; display: flex; flex-direction: column; gap: 1rem;
}
/* MED tier .compact: still single column — user wants prominence not density */
.news-list.compact {
  display: flex; flex-direction: column; gap: 0.85rem;
}
.tier-low .news-list { gap: 0.5rem; }
.news-item { display: flex; gap: 0.9rem; align-items: flex-start; }
.news-dot {
  width: 11px; height: 11px; border-radius: 50%;
  background: var(--brand-red);
  margin-top: 0.55rem; flex-shrink: 0;
  box-shadow: 0 0 14px rgba(216,56,24,0.6);
}
.tier-med .news-dot { background: var(--accent3); box-shadow: 0 0 12px rgba(128,190,255,0.45); width: 11px; height: 11px; margin-top: 0.55rem; }
.tier-low .news-dot { background: var(--text-muted); box-shadow: none; width: 7px; height: 7px; margin-top: 0.65rem; }
.news-body { line-height: 1.45; flex: 1; min-width: 0; }
.news-headline {
  font-family: var(--font-head); font-weight: 700;
  color: var(--text); font-size: var(--fs-body);
}
/* MED tier upgraded — nearly equal to HIGH per user feedback ("better served as a bigger breakdown") */
.tier-med .news-headline { font-size: var(--fs-body); color: var(--text); }
.tier-low .news-headline { font-size: var(--fs-body-tight); color: var(--text-muted); font-weight: 600; }
/* news-em-dash: ACCENT2 yellow (was brandRed which fails AA contrast on bg at body size — see RESEARCH-ux.md §10) */
.news-em-dash { color: var(--accent2); font-weight: 700; }
.news-date { color: var(--text-muted); font-size: var(--fs-body-tight); font-variant-numeric: tabular-nums; margin-right: 0.35rem; font-weight: 600; }
.news-text { color: var(--text); font-size: var(--fs-body); }
.tier-med .news-text { font-size: var(--fs-body); color: var(--text); }
.tier-low .news-text { font-size: var(--fs-body-tight); color: var(--text-muted); }
/* Long unbroken tokens (env-var names, snake_case literals, URL fragments)
   force min-width on .news-body/text at narrow viewports. overflow-wrap:anywhere
   allows mid-token break ONLY when needed; min-width:0 lets flex/grid children
   shrink below their content's intrinsic width. */
.news-body, .news-text, .news-headline, .news-url, .pattern-text {
  overflow-wrap: anywhere; min-width: 0;
}
.news-urls {
  list-style: none; padding: 0.4rem 0 0; margin: 0;
  display: flex; flex-direction: column; gap: 0.1rem;
}
.news-urls li { padding: 0; line-height: 1.3; }
.news-url {
  display: inline-block; color: var(--accent3);
  font-size: 0.88rem;
  text-decoration: none; word-break: break-all;
  position: relative; z-index: 10;
}
.tier-med .news-url, .tier-low .news-url { font-size: 0.82rem; }
.news-url::before { content: "↳ "; color: var(--accent2); }
.news-url:hover { text-decoration: underline; color: var(--accent2); }

/* ─── Patterns ─── */
.patterns-list { list-style: none; display: flex; flex-direction: column; gap: 0.9rem; }
.pattern-item { display: flex; gap: 0.9rem; align-items: flex-start; }
.pattern-arrow { color: var(--brand-red); font-weight: 700; font-size: 1.6rem; line-height: 1; flex-shrink: 0; margin-top: 0.1rem; }
.pattern-body { line-height: 1.45; flex: 1; min-width: 0; }
.pattern-headline { font-family: var(--font-head); font-weight: 700; color: var(--accent2); font-size: var(--fs-body); }
.pattern-text { color: var(--text); font-size: var(--fs-body); }

/* ─── Prompt slides ─── */
.prompt-card {
  background: var(--bg-accent);
  border: 2px solid var(--brand-red);
  border-radius: 18px; padding: 4rem 3rem; margin: 1.5rem auto;
  max-width: 1000px; text-align: center;
  box-shadow: 0 0 50px rgba(216,56,24,0.25), inset 0 0 30px rgba(128,128,255,0.08);
  position: relative;
}
.prompt-card::before {
  content: ""; position: absolute; top: -2px; left: 30%; right: 30%; height: 2px;
  background: linear-gradient(90deg, transparent, var(--accent2), transparent);
}
.prompt-q {
  font-family: var(--font-head); font-style: italic; font-weight: 600;
  color: var(--accent2);
  font-size: clamp(1.6rem, 1.8vw + 0.8rem, 2.6rem);
  line-height: 1.3; text-wrap: balance;
}
.prompt-note {
  text-align: center; color: var(--text-muted); font-style: italic;
  font-size: var(--fs-body); margin-top: 1.5rem;
}

/* ─── Blank (task force) ─── */
.blank-card {
  flex: 1; margin: 1.5rem 0 0; min-height: 30vh;
  background: rgba(20,40,71,0.5); border: 2px dashed var(--divider);
  border-radius: 14px;
  display: flex; align-items: center; justify-content: center;
}
.blank-card p { color: var(--text-muted); font-style: italic; font-size: var(--fs-body); }

/* ─── Q&A ─── */
.section-qa {
  background: linear-gradient(135deg, #1F1E47 0%, #3F3E87 100%);
  align-items: center; justify-content: center; text-align: center;
  overflow: hidden;
}
.section-qa .orb-qa-1 {
  position: absolute; width: 80vh; height: 80vh; border-radius: 50%;
  left: 0; top: 0; transform: translate(-25vh, -25vh);
  background: radial-gradient(circle, var(--accent) 0%, transparent 70%);
  opacity: 0.25; filter: blur(80px);
  pointer-events: none;
}
.section-qa .orb-qa-2 {
  position: absolute; width: 70vh; height: 70vh; border-radius: 50%;
  right: 0; bottom: 0; transform: translate(20vh, 20vh);
  background: radial-gradient(circle, var(--accent2) 0%, transparent 70%);
  opacity: 0.18; filter: blur(80px);
  pointer-events: none;
}
.section-qa .orb-qa-3 {
  position: absolute; width: 50vh; height: 50vh; border-radius: 50%;
  left: 50%; top: 50%; transform: translate(-50%,-50%);
  background: radial-gradient(circle, var(--accent3) 0%, transparent 70%);
  opacity: 0.12; filter: blur(60px);
}
.qa-content { position: relative; z-index: 2; }
.qa-logo {
  height: 7vh; max-height: 70px; width: auto;
  margin: 0 auto 3vh;
  filter: drop-shadow(0 4px 12px rgba(0,0,0,0.4));
}
.qa-big {
  font-family: var(--font-head); font-weight: 700;
  font-size: clamp(4rem, 9vw, 9rem);
  letter-spacing: -0.04em; line-height: 1;
  background: linear-gradient(135deg, #FFFFFF 0%, #FFB901 50%, #80BEFF 100%);
  -webkit-background-clip: text; background-clip: text; color: transparent;
}
.qa-sub {
  font-family: var(--font-head); font-size: var(--fs-tier-h3); color: var(--accent);
  letter-spacing: 0.25em; margin-top: 1rem;
}
.qa-line { width: 80px; height: 3px; background: var(--accent2); margin: 1.5rem auto; }

/* ─── Progress bar ─── */
#progress {
  position: fixed; bottom: 0; left: 0; height: 3px;
  background: linear-gradient(90deg, var(--accent), var(--accent2));
  z-index: 60; transition: width 200ms linear;
  pointer-events: none;
}

/* ─── Help hint ─── */
#help {
  position: fixed; bottom: 0.7rem; left: 50%; transform: translateX(-50%); z-index: 40;
  font-size: 0.7rem; color: var(--text-muted); opacity: 0.55;
  font-family: var(--font-body); pointer-events: none;
}
#help kbd {
  background: var(--bg-card); padding: 1px 6px; border-radius: 4px;
  border: 1px solid var(--divider); font-size: 0.65rem; color: var(--text);
}

/* ─── Reduced motion ─── */
@media (prefers-reduced-motion: reduce) {
  html { scroll-snap-type: none; scroll-behavior: auto; }
  * { animation-duration: 0.01ms !important; transition-duration: 0.01ms !important; }
}

/* ─── Print mode (?print=1 query OR @media print) ─── */
body.print-mode { overflow: visible; }
body.print-mode html, html.print-mode { scroll-snap-type: none; scroll-behavior: auto; }
body.print-mode #topnav, body.print-mode #help, body.print-mode #progress { display: none; }
body.print-mode .section {
  break-after: page; page-break-after: always;
  min-height: 100vh; height: 100vh;
}
body.print-mode .section:last-child { break-after: auto; page-break-after: auto; }

@media print {
  html { scroll-snap-type: none; scroll-behavior: auto; }
  #topnav, #help, #progress { display: none; }
  .section { break-after: page; page-break-after: always; min-height: 100vh; height: 100vh; }
  .section:last-child { break-after: auto; page-break-after: auto; }
  .news-url { color: var(--accent3) !important; }
}

/* ─── Responsive primitives (Gate 7 matrix) ─── */

/* Chip-nav scroll-x on narrow widths so chips remain reachable instead of wrapping */
@media (max-width: 900px) {
  #topnav { overflow-x: auto; -webkit-overflow-scrolling: touch; }
  #topnav .chips { white-space: nowrap; flex-wrap: nowrap; }
  .topnav-meta { display: none; }
}

/* Force news URLs to break anywhere — long URLs no longer trigger horizontal scroll */
.news-url, .pattern-headline, .news-headline {
  overflow-wrap: anywhere;
  word-break: break-word;
}

/* Levels grid stacks single-column on narrow */
@media (max-width: 700px) {
  .level-row { flex-direction: column; align-items: stretch; }
  .news-list.compact { grid-template-columns: 1fr; }
  .topnav-meta { display: none; }
}

/* Speaker notes — hidden by default, revealed via ?notes=1 flag (handled in JS) */
.speaker-notes { display: none; }
body.show-speaker-notes .speaker-notes {
  display: block;
  position: absolute; bottom: 1rem; left: 1rem; right: 1rem;
  background: rgba(0,0,0,0.7); color: var(--text); padding: 0.6rem 0.8rem;
  border-radius: 6px; font-size: 0.85rem; line-height: 1.35;
  border-left: 3px solid var(--accent2);
}
`;
}
