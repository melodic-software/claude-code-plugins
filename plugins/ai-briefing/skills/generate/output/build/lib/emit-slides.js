const BUCKET_ORDER = [
  { key: "anthropic",   label: "Anthropic",                provider: "anthropic" },
  { key: "openai",      label: "OpenAI",                   provider: "openai" },
  { key: "legal",       label: "Legal & regulatory",       provider: null },
  { key: "google",      label: "Google",                   provider: "google" },
  { key: "cursor",      label: "Cursor",                   provider: "cursor" },
  { key: "xai",         label: "xAI / Grok",               provider: "xai" },
  { key: "meta",        label: "Meta / Llama",             provider: "meta" },
  { key: "deepseek",    label: "DeepSeek",                 provider: "deepseek" },
  { key: "microsoft",   label: "Microsoft",                provider: "microsoft" },
  { key: "other",       label: "Other",                    provider: null },
  { key: "compute",     label: "Compute & Infrastructure", provider: "nvidia" },
  { key: "real-world",  label: "Real-world AI",            provider: "tesla" },
  { key: "extras",      label: "EXTRAS",                   provider: null },
];

const SPECIAL_BUCKETS = {
  "dev-tools": /^dev tools|^dev-tools|^dev tools — release walk/i,
  "patterns": /^patterns|^notable patterns/i,
  "breaking":  /^breaking & deprecated|^breaking and deprecated|^breaking\/deprecated/i,
  "pace":     /^pace|^velocity|^cadence/i,
  "trends":   /^trends|^cross-meeting trends/i,
};

function toBullet(item) {
  return {
    title: item.headline || "Untitled",
    body: item.body || "",
    urls: item.urls || [],
    date: item.date || null,
  };
}

function toPatternItem(item) {
  return {
    title: item.headline || "Untitled",
    body: item.body || "",
  };
}

function bucketKey(heading) {
  const h = heading.toLowerCase();
  for (const [key, re] of Object.entries(SPECIAL_BUCKETS)) {
    if (re.test(h)) return key;
  }
  for (const b of BUCKET_ORDER) {
    if (h.startsWith(b.key)) return b.key;
    if (b.key === "xai" && /grok/.test(h)) return b.key;
    if (b.key === "meta" && /llama/.test(h)) return b.key;
    if (b.key === "real-world" && /(real.world|robotics|autonomous)/.test(h)) return b.key;
    if (b.key === "compute" && /(compute|infrastructure|nvidia|chip|gpu|datacenter)/.test(h)) return b.key;
    if (b.key === "legal" && /(legal|lawsuit|regulatory|trial)/.test(h)) return b.key;
  }
  return null;
}

const TIER_TITLE_SUFFIX = {
  high: "Highlights",
  med: "also worth noting",
  low: "color & notes",
};

function tierSlides({ items, tier, providerKey, label }) {
  if (!items || items.length === 0) return [];
  const slideType = tier === "high" ? "news" : "condensed";
  const baseTitle = `${label} — ${TIER_TITLE_SUFFIX[tier]}`;

  const MAX_HIGH = 5;
  const MAX_MED = 14;
  const cap = tier === "high" ? MAX_HIGH : MAX_MED;
  const chunks = [];
  for (let i = 0; i < items.length; i += cap) chunks.push(items.slice(i, i + cap));

  const partTitle = (part) => {
    if (chunks.length === 1) return baseTitle;
    return tier === "high" ? `${label} — part ${part}` : `${baseTitle} (${part})`;
  };
  return chunks.map((chunk, idx) => ({
    type: slideType,
    provider: providerKey,
    tier,
    title: partTitle(idx + 1),
    bullets: chunk.map(toBullet),
  }));
}

const NON_PROVIDER_BUCKETS = new Set(["patterns", "breaking", "dev-tools", "pace", "trends"]);

function buildPatternsSlide(buckets) {
  const authored = buckets.patterns?._items;
  if (authored && authored.length > 0) {
    return {
      type: "patterns",
      title: "Notable patterns this window",
      subtitle: "Synthesis & themes",
      items: authored.map(toPatternItem),
    };
  }

  const bucketKeys = Object.keys(buckets).filter(
    (k) => !NON_PROVIDER_BUCKETS.has(k) && Object.values(buckets[k] || {}).some((arr) => arr.length > 0),
  );
  if (bucketKeys.length < 3) return null;

  const items = [
    { title: "Multi-bucket activity", body: `${bucketKeys.length} buckets had notable items this window — broad coverage cycle.` },
  ];
  if (buckets.compute) items.push({ title: "Compute as bottleneck", body: "Compute / Infrastructure activity present — chip + datacenter signals affect all model providers." });
  if (buckets.legal) items.push({ title: "Legal pressure", body: "Legal & regulatory items in window — lawsuits / rulings / AGs reshape access + cost." });
  if (buckets["real-world"]) items.push({ title: "Real-world deployment", body: "Real-world AI items — autonomous vehicles, humanoid robotics moving from research to production." });
  if (buckets.microsoft && buckets.openai) items.push({ title: "Enterprise AI vertical", body: "Microsoft + OpenAI both shipping enterprise-vertical productization." });
  if (items.length < 3) return null;

  return {
    type: "patterns",
    title: "Notable patterns this window",
    subtitle: "Synthesis & themes",
    items,
  };
}

function buildBreakingSlide(buckets) {
  const items = buckets.breaking?._items;
  if (!items || items.length === 0) return null;
  return {
    type: "news",
    provider: null,
    tier: "high",
    title: "Breaking & Deprecated",
    subtitle: "Heads-up: removals, EOL, security advisories",
    bullets: items.map(toBullet),
  };
}

function buildPaceSlide(buckets) {
  const authored = buckets.pace?._items;
  if (authored && authored.length > 0) {
    return {
      type: "patterns",
      title: "Pace this window",
      subtitle: "Vendor cadence at a glance",
      items: authored.map(toPatternItem),
    };
  }
  return null;
}

const DEV_TOOL_PRIORITY = [
  { key: "claude-code",    re: /claude\s*code/i,                          label: "Claude Code",     provider: "anthropic" },
  { key: "cursor",         re: /cursor/i,                                  label: "Cursor",          provider: "cursor" },
  { key: "codex",          re: /codex/i,                                   label: "OpenAI Codex",    provider: "openai" },
  { key: "github-copilot", re: /github\s*copilot|gh\s*copilot|copilot/i,   label: "GitHub Copilot",  provider: "microsoft" },
  { key: "augment-code",   re: /augment(\s*code)?|auggie/i,                label: "Augment Code",    provider: null },
];
function buildDevToolSlides(buckets) {
  const dt = buckets["dev-tools"];
  if (!dt) return [];
  const slides = [];
  const matched = {};
  for (const [tier, items] of Object.entries(dt)) {
    if (tier === "_items") continue;
    for (const tool of DEV_TOOL_PRIORITY) {
      if (tool.re.test(tier) && !matched[tool.key]) {
        matched[tool.key] = { items, heading: tier };
        break;
      }
    }
  }
  for (const tool of DEV_TOOL_PRIORITY) {
    const m = matched[tool.key];
    if (!m || !m.items || m.items.length === 0) continue;
    slides.push({
      type: "news",
      provider: tool.provider,
      tier: "high",
      title: `Dev Tools — ${tool.label}`,
      subtitle: m.heading.replace(new RegExp(tool.label, "i"), "").replace(/^[\s—-]+|[\s—-]+$/g, "") || undefined,
      bullets: m.items.map(toBullet),
    });
  }
  return slides;
}

function sortItemsByDate(items) {
  return items.toSorted((a, b) => {
    if (a.date == null || b.date == null) return (b.date == null) - (a.date == null);
    return b.date - a.date;
  });
}

const SORTED_TIERS = ["high", "med", "low", "_items"];

function sortTiersByDate(normalized) {
  for (const [bucket, data] of Object.entries(normalized)) {
    const keys = bucket === "dev-tools" ? Object.keys(data) : SORTED_TIERS;
    for (const k of keys) {
      if (data[k]) data[k] = sortItemsByDate(data[k]);
    }
  }
}

function balanceTiers(normalized) {
  for (const data of Object.values(normalized)) {
    if (!data) continue;
    const high = data.high || [];
    const med = data.med || [];
    while (high.length > 7) med.unshift(high.pop());
    while (med.length >= 5 && high.length < 3) high.push(med.shift());
    data.high = high;
    data.med = med;
  }
}

/**
 * Convert structured briefing → slide array.
 *
 * @param {{meta, buckets}} briefing — output of parseBriefing()
 * @param {{meetingNumber, date, window, org}} ctx
 */
export function emitSlides(briefing, ctx) {
  const { buckets } = briefing;

  const normalized = {};
  for (const [heading, tiers] of Object.entries(buckets)) {
    const key = bucketKey(heading);
    if (!key) continue;
    const bucket = (normalized[key] ??= {});
    for (const [tier, items] of Object.entries(tiers)) {
      const append = (k) => { bucket[k] = (bucket[k] || []).concat(items); };
      const t = tier.toLowerCase();
      if (t === "_items") append("_items");
      else if (t.startsWith("high")) append("high");
      else if (t.startsWith("med")) append("med");
      else if (t.startsWith("low")) append("low");
      else if (key === "dev-tools") append(tier);
      else if (t.startsWith("rob") || t.startsWith("pattern")) append(t);
    }
  }

  balanceTiers(normalized);
  sortTiersByDate(normalized);

  const slides = [];

  slides.push({
    type: "title",
    section: "hero",
    eyebrow: ctx.org || "AI Briefing",
    title: `AI Meeting #${ctx.meetingNumber}`,
    subtitle: ctx.date,
    footer: `Briefing window: ${ctx.window}`,
  });

  slides.push({
    type: "agenda",
    section: "agenda",
    title: "Agenda",
    items: [
      "Welcome + Goals",
      "AI Generative Levels",
      "Open share (news from the room)",
      "AI Latest News",
      "AI Tools & Techniques",
      "AI Tips & Tricks / Show and Tell",
      "AI Problems / Brainstorm",
      "AI Task Force Update",
      "Q & A",
    ],
  });

  slides.push({
    type: "section",
    section: "welcome",
    title: "Welcome & Goals",
    lead: "The primary goal of this meeting is to change our culture to evolve and think about leveraging AI in everything we do.",
    items: ["Share Tips & Tricks", "Share Workflows", "Show and Tell"],
  });

  slides.push({
    type: "levels",
    section: "levels",
    title: "AI Generative Levels",
    levels: [
      { n: 0, label: "Writing every line yourself" },
      { n: 1, label: "AI autocompletes your code" },
      { n: 2, label: "AI writes functions from descriptions" },
      { n: 3, label: "AI builds features from specifications" },
      { n: 4, label: "AI agents execute entire workflows" },
      { n: 5, label: "Autonomous domain experts" },
    ],
  });

  slides.push({
    type: "open",
    section: "open",
    parentSection: "news",
    title: "Open share",
    subtitle: "Anybody have any news to share before we get into the briefing?",
    note: "Headlines, links, breaking AI news — anything we should add to today's coverage.",
  });

  const pushNews = (section, ...newsSlides) => {
    for (const s of newsSlides) {
      if (!s) continue;
      s.section = section;
      s.parentSection = "news";
      slides.push(s);
    }
  };

  for (const b of BUCKET_ORDER) {
    const data = normalized[b.key];
    if (!data) continue;
    pushNews(b.key, ...["high", "med", "low"].flatMap((tier) =>
      tierSlides({ items: data[tier], tier, providerKey: b.provider, label: b.label })));
  }

  pushNews("devtools", ...buildDevToolSlides(normalized));
  pushNews("patterns", buildPatternsSlide(normalized));
  pushNews("pace", buildPaceSlide(normalized));
  pushNews("breaking", buildBreakingSlide(normalized));

  slides.push({
    type: "prompt",
    section: "tools",
    title: "AI Tools & Techniques",
    prompt: "What are tools and techniques that people use daily?",
    note: "Open discussion — share what's working in your stack right now.",
  });
  slides.push({
    type: "prompt",
    section: "tips",
    title: "AI Tips & Tricks · Show and Tell",
    prompt: "Anyone have tips & tricks / show and tell?",
    note: "Live demos welcome — short and concrete beats polished.",
  });
  slides.push({
    type: "prompt",
    section: "problems",
    title: "AI Problems",
    prompt: "What problems are you having? What works, what doesn't?",
    note: "Surface friction so the task force can prioritize.",
  });
  slides.push({
    type: "blank",
    section: "taskforce",
    title: "AI Task Force Update",
    placeholder: "Status, in-flight initiatives, blockers, asks.",
  });
  slides.push({
    type: "qa",
    section: "qa",
    title: "Q & A",
    subtitle: "Feedback · Review · Open Floor",
  });

  return slides;
}
