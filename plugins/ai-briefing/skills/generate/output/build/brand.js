// Neutral default brand that emit-slides-data.js embeds into slides-data.js. A consumer
// profile overlays org name, tagline, logos, and theme; edit this file only on a rebrand.
//
// `logoColor` / `logoWhite` are empty by default (no bundled org logo); the build
// scripts skip logo embedding when empty. A profile supplies logo asset paths.

export const brand = {
  org: "AI Briefing",
  tagline: "AI industry news, aggregated and ranked.",
  logoColor: "",
  logoWhite: "",
  // Footer rendered by the build scripts as "<org> · AI Meeting #<meeting_n> · <date>".
  footerTemplate: "{org} · AI Meeting #{meeting_n} · {date}",
};

export const theme = {
  bg: "0F1424", bgAccent: "1C2440", bgCard: "2B3358",
  brandIndigo: "23305C", brandRed: "C0432E",
  accent: "6E8BFF", accent2: "F2B441", accent3: "8FB6FF",
  text: "FFFFFF", textMuted: "B4BAD4", divider: "3C456E",
  pptFontHead: "Arial", pptFontBody: "Arial",
  htmlFontHead: "'Segoe UI', system-ui, sans-serif",
  htmlFontBody: "'Open Sans', 'Segoe UI', system-ui, sans-serif",
};
