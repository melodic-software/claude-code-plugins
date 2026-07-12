// Zod schema for slides-data.js exports. Validates shape after emit, and as
// part of validate.js gates. Catches accidental drift in slide-type fields.
import { z } from "zod";

const Url = z.string().url();
const Hex6 = z.string().regex(/^[0-9A-Fa-f]{6}$/);

const Bullet = z.object({
  title: z.string().min(1),
  body: z.string().default(""),
  urls: z.array(Url).default([]),
});

const PatternItem = z.object({
  title: z.string().min(1),
  body: z.string().min(1),
});

const Tier = z.enum(["high", "med", "low"]);

// Common optional fields — section key + optional parent-section grouping.
// `section` is the unique scroll-snap section id.
// `parentSection` (e.g. "news") groups multiple sections into a single nav-chip parent.
// `speakerNotes` is rendered as PPTX speaker notes (build-pptx.js) + HTML <aside class="speaker-notes">
// (revealed only when the URL carries ?notes=1).
// PPTX/PDF/legacy paginated builds ignore section/parentSection. Render derives sticky-nav grouping from these.
const sectionField = {
  section: z.string().optional(),
  parentSection: z.string().optional(),
  speakerNotes: z.string().optional(),
};

const SlideTitle = z.object({
  type: z.literal("title"),
  eyebrow: z.string(),
  title: z.string(),
  subtitle: z.string(),
  footer: z.string(),
  ...sectionField,
});

const SlideAgenda = z.object({
  type: z.literal("agenda"),
  title: z.string(),
  items: z.array(z.string()).min(1),
  ...sectionField,
});

const SlideSection = z.object({
  type: z.literal("section"),
  title: z.string(),
  lead: z.string(),
  items: z.array(z.string()).min(1),
  ...sectionField,
});

const SlideLevels = z.object({
  type: z.literal("levels"),
  title: z.string(),
  levels: z.array(z.object({ n: z.number().int().min(0), label: z.string() })).length(6),
  ...sectionField,
});

const SlideOpen = z.object({
  type: z.literal("open"),
  title: z.string(),
  subtitle: z.string(),
  note: z.string().optional(),
  ...sectionField,
});

const SlideNews = z.object({
  type: z.literal("news"),
  provider: z.string().nullable(),
  tier: Tier.optional(),
  title: z.string(),
  subtitle: z.string().optional(),
  bullets: z.array(Bullet).min(1),
  ...sectionField,
});

const SlideCondensed = z.object({
  type: z.literal("condensed"),
  provider: z.string().nullable(),
  tier: Tier,
  title: z.string(),
  subtitle: z.string().optional(),
  bullets: z.array(Bullet).min(1),
  ...sectionField,
});

const SlidePatterns = z.object({
  type: z.literal("patterns"),
  title: z.string(),
  subtitle: z.string().optional(),
  items: z.array(PatternItem).min(1),
  ...sectionField,
});

const SlidePrompt = z.object({
  type: z.literal("prompt"),
  title: z.string(),
  prompt: z.string(),
  note: z.string().optional(),
  ...sectionField,
});

const SlideBlank = z.object({
  type: z.literal("blank"),
  title: z.string(),
  placeholder: z.string(),
  ...sectionField,
});

const SlideQA = z.object({
  type: z.literal("qa"),
  title: z.string(),
  subtitle: z.string(),
  ...sectionField,
});

export const Slide = z.discriminatedUnion("type", [
  SlideTitle, SlideAgenda, SlideSection, SlideLevels, SlideOpen,
  SlideNews, SlideCondensed, SlidePatterns, SlidePrompt, SlideBlank,
  SlideQA,
]);

export const Meta = z.object({
  meetingNumber: z.number().int().min(1),
  org: z.string(),
  tagline: z.string(),
  date: z.string(),
  window: z.string(),
  logoColor: z.string(),
  logoWhite: z.string(),
});

export const Theme = z.object({
  bg: Hex6, bgAccent: Hex6, bgCard: Hex6,
  brandIndigo: Hex6, brandRed: Hex6,
  accent: Hex6, accent2: Hex6, accent3: Hex6,
  text: Hex6, textMuted: Hex6, divider: Hex6,
  pptFontHead: z.string(), pptFontBody: z.string(),
  htmlFontHead: z.string(), htmlFontBody: z.string(),
});

export const ProviderLogos = z.record(z.string(), z.string().nullable());

export const Deck = z.object({
  meta: Meta,
  theme: Theme,
  providerLogos: ProviderLogos,
  slides: z.array(Slide).min(10),
});

/**
 * Throws a friendly error if the data doesn't match. Returns the parsed value.
 */
export function validateDeck(input) {
  const result = Deck.safeParse(input);
  if (!result.success) {
    const issues = result.error.issues.map((i) => `  ${i.path.join(".")}: ${i.message}`).join("\n");
    throw new Error(`slides-data schema violation:\n${issues}`);
  }
  return result.data;
}
