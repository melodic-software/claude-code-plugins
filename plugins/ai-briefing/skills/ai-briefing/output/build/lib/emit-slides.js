// Convert parsed briefing buckets → ordered slide objects matching the
// 11-type schema in lib/schema.js. Implements canonical slide order,
// per-bucket HIGH→MED→LOW partition, split rules, cross-provider clusters.

// Canonical bucket order. Keys MUST match the H2 headings in briefing markdown
// (case-insensitive prefix match against parser output).
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

// Special-purpose buckets emitted outside the standard HIGH/MED/LOW per-provider loop.
// Recognized via SPECIAL_BUCKET_PATTERNS — matched in addition to BUCKET_ORDER above.
const SPECIAL_BUCKETS = {
  "dev-tools": /^dev tools|^dev-tools|^dev tools — release walk/i,
  "patterns": /^patterns|^notable patterns/i,
  "breaking":  /^breaking & deprecated|^breaking and deprecated|^breaking\/deprecated/i,
  "pace":     /^pace|^velocity|^cadence/i,
  "trends":   /^trends|^cross-meeting trends/i,
};

/** Map a parsed briefing item → the bullet shape every slide renderer expects. */
function toBullet(item) {
  return {
    title: item.headline || "Untitled",
    body: item.body || "",
    urls: item.urls || [],
    date: item.date || null,
  };
}

/** Match an H2 heading from briefing.md to a canonical bucket key. */
function bucketKey(heading) {
  const h = heading.toLowerCase();
  // Special buckets take precedence over fuzzy provider matches
  for (const [key, re] of Object.entries(SPECIAL_BUCKETS)) {
    if (re.test(h)) return key;
  }
  for (const b of BUCKET_ORDER) {
    if (h === b.key) return b.key;
    if (h.startsWith(b.key)) return b.key;
    // alias matches
    if (b.key === "xai" && /grok/.test(h)) return b.key;
    if (b.key === "meta" && /llama/.test(h)) return b.key;
    if (b.key === "real-world" && /(real.world|robotics|autonomous)/.test(h)) return b.key;
    if (b.key === "compute" && /(compute|infrastructure|nvidia|chip|gpu|datacenter)/.test(h)) return b.key;
    if (b.key === "legal" && /(legal|lawsuit|regulatory|trial)/.test(h)) return b.key;
  }
  return null;
}

/** Build news/condensed slides for a tier of items, splitting when >7. */
function tierSlides({ items, tier, providerKey, label }) {
  if (!items || items.length === 0) return [];
  const slides = [];
  const slideType = tier === "high" ? "news" : "condensed";
  const baseTitle = `${label} — ${tier === "high" ? "Highlights" : tier === "med" ? "also worth noting" : "color & notes"}`;

  // HIGH split into chunks of ≤5 with topical title; MED/LOW single slide w/ 2-col when >7
  const MAX_HIGH = 5;
  if (tier === "high" && items.length > MAX_HIGH) {
    for (let i = 0; i < items.length; i += MAX_HIGH) {
      const chunk = items.slice(i, i + MAX_HIGH);
      const part = Math.floor(i / MAX_HIGH) + 1;
      slides.push({
        type: slideType,
        provider: providerKey,
        tier,
        title: `${label} — part ${part}`,
        bullets: chunk.map(toBullet),
      });
    }
  } else if (tier !== "high" && items.length > 14) {
    // MED/LOW too dense even in 2-col — split into multiple condensed slides
    const MAX_MED = 14;
    for (let i = 0; i < items.length; i += MAX_MED) {
      const chunk = items.slice(i, i + MAX_MED);
      const part = Math.floor(i / MAX_MED) + 1;
      slides.push({
        type: slideType,
        provider: providerKey,
        tier,
        title: `${baseTitle} (${part})`,
        bullets: chunk.map(toBullet),
      });
    }
  } else {
    slides.push({
      type: slideType,
      provider: providerKey,
      tier,
      title: baseTitle,
      bullets: items.map(toBullet),
    });
  }
  return slides;
}

/** Synthesize patterns slide from cross-bucket signals. Heuristic — caller can override
 *  by authoring `## Patterns` in the briefing markdown (parsed into buckets.patterns._items). */
function buildPatternsSlide(buckets) {
  // Authored content beats heuristic — if `## Patterns` H2 has bullets, render them directly.
  const authored = buckets.patterns?._items;
  if (authored && authored.length > 0) {
    return {
      type: "patterns",
      title: "Notable patterns this window",
      subtitle: "Synthesis & themes",
      items: authored.map((it) => ({
        title: it.headline || "Untitled",
        body: it.body || "",
      })),
    };
  }

  // Heuristic fallback when no authored Patterns section exists.
  const bucketKeys = Object.keys(buckets).filter((k) => k !== "patterns" && k !== "breaking" && k !== "dev-tools" && k !== "pace" && k !== "trends" && Object.values(buckets[k] || {}).some((arr) => arr.length > 0));
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

/** Build "Breaking & Deprecated" slide from authored `## Breaking & Deprecated` H2. */
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

/** Build "Pace" velocity slide from authored `## Pace` H2 (or auto-derive from bucket counts). */
function buildPaceSlide(buckets) {
  const authored = buckets.pace?._items;
  if (authored && authored.length > 0) {
    return {
      type: "patterns",
      title: "Pace this window",
      subtitle: "Vendor cadence at a glance",
      items: authored.map((it) => ({
        title: it.headline || "Untitled",
        body: it.body || "",
      })),
    };
  }
  return null; // No auto-derivation in the first cut — author the section to enable.
}

/** Build dev-tool slides — per-tool ordered by DEV_TOOL_PRIORITY. Each H3 in the
 *  briefing's `## Dev Tools — Release Walk` section becomes one slide.
 *  Maps tool-name patterns to ordered keys; missing tools are silently skipped. */
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
  // Map each H3 tier to a priority key; skip H3s that don't match any priority.
  const matched = {};
  for (const [tier, items] of Object.entries(dt)) {
    if (tier === "_items") continue; // bare-bullets fallback (no H3) — ignored for dev-tools
    for (const tool of DEV_TOOL_PRIORITY) {
      if (tool.re.test(tier) && !matched[tool.key]) {
        matched[tool.key] = { tool, items, heading: tier };
        break;
      }
    }
  }
  // Emit in priority order regardless of authoring order
  for (const tool of DEV_TOOL_PRIORITY) {
    const m = matched[tool.key];
    if (!m || !m.items || m.items.length === 0) continue;
    slides.push({
      type: "news",
      provider: tool.provider,
      tier: "high",
      title: `Dev Tools — ${m.tool.label}`,
      subtitle: m.heading.replace(new RegExp(m.tool.label, "i"), "").replace(/^[\s—-]+|[\s—-]+$/g, "") || undefined,
      bullets: m.items.map(toBullet),
    });
  }
  return slides;
}

/** Stable sort items in each tier by extracted date desc (most recent → oldest).
 *  Undated items stay at top in source order. Uses Array.prototype.sort with
 *  index tracking to remain stable across V8 versions. */
function sortItemsByDate(items) {
  if (!items || items.length === 0) return items;
  return items
    .map((it, idx) => ({ it, idx }))
    .sort((a, b) => {
      const ad = a.it.date;
      const bd = b.it.date;
      if (ad == null && bd == null) return a.idx - b.idx;
      if (ad == null) return -1; // undated first
      if (bd == null) return 1;
      if (ad !== bd) return bd - ad; // newer first
      return a.idx - b.idx;          // tie → source order
    })
    .map((x) => x.it);
}

function sortTiersByDate(normalized) {
  for (const bucket of Object.keys(normalized)) {
    const data = normalized[bucket];
    if (!data) continue;
    if (data.high) data.high = sortItemsByDate(data.high);
    if (data.med)  data.med  = sortItemsByDate(data.med);
    if (data.low)  data.low  = sortItemsByDate(data.low);
    if (data._items) data._items = sortItemsByDate(data._items);
    // Per-tool dev-tools tiers (raw H3 keys) — sort each
    if (bucket === "dev-tools") {
      for (const k of Object.keys(data)) {
        if (k === "_items" || k === "high" || k === "med" || k === "low") continue;
        data[k] = sortItemsByDate(data[k]);
      }
    }
  }
}

/** Mutate `normalized` to apply tier auto-balance:
 *   - HIGH > 7 → demote weakest (last) item to MED until HIGH ≤ 7
 *   - MED ≥ 5 AND HIGH < 3 → promote first MED item to HIGH until balance
 *   Authoring intent always wins for explicit tier markers in headlines (e.g. "[STATE: GA]"). */
function balanceTiers(normalized) {
  for (const bucket of Object.keys(normalized)) {
    const data = normalized[bucket];
    if (!data) continue;
    const high = data.high || [];
    const med = data.med || [];
    // Demote weakest from HIGH when over-saturated
    while (high.length > 7) {
      const moved = high.pop();
      med.unshift(moved);
    }
    // Promote strongest from MED when HIGH is under-saturated
    while (med.length >= 5 && high.length < 3) {
      const moved = med.shift();
      high.push(moved);
    }
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

  // Normalize bucket keys to canonical
  const normalized = {};
  for (const [heading, tiers] of Object.entries(buckets)) {
    const key = bucketKey(heading);
    if (!key) continue;
    normalized[key] = normalized[key] || {};
    // Merge tiers (case-insensitive)
    for (const [tier, items] of Object.entries(tiers)) {
      const t = tier.toLowerCase();
      if (t === "_items") {
        // No-H3 bullets (Patterns / Breaking / Pace authored under H2 directly)
        normalized[key]._items = (normalized[key]._items || []).concat(items);
      } else if (t.startsWith("high")) normalized[key].high = (normalized[key].high || []).concat(items);
      else if (t.startsWith("med")) normalized[key].med = (normalized[key].med || []).concat(items);
      else if (t.startsWith("low")) normalized[key].low = (normalized[key].low || []).concat(items);
      else if (key === "dev-tools") {
        // Per-tool H3 tiers (Claude Code, Cursor, Codex, etc.) — preserve raw heading text
        normalized[key][tier] = (normalized[key][tier] || []).concat(items);
      } else if (t.startsWith("rob") || t.startsWith("pattern")) {
        // EXTRAS sub-tiers
        normalized[key][t] = (normalized[key][t] || []).concat(items);
      }
    }
  }

  // Apply tier auto-balance before emitting per-bucket slides
  balanceTiers(normalized);
  // Sort each tier by date desc (most recent → oldest); undated stay at top
  sortTiersByDate(normalized);

  const slides = [];

  // 1. Title (hero)
  slides.push({
    type: "title",
    section: "hero",
    eyebrow: ctx.org || "AI Briefing",
    title: `AI Meeting #${ctx.meetingNumber}`,
    subtitle: ctx.date,
    footer: `Briefing window: ${ctx.window}`,
  });

  // 2. Agenda
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

  // 3. Welcome
  slides.push({
    type: "section",
    section: "welcome",
    title: "Welcome & Goals",
    lead: "The primary goal of this meeting is to change our culture to evolve and think about leveraging AI in everything we do.",
    items: ["Share Tips & Tricks", "Share Workflows", "Show and Tell"],
  });

  // 4. Levels
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

  // 5. Open share — first slide of the NEWS group (intake before briefing items)
  slides.push({
    type: "open",
    section: "open",
    parentSection: "news",
    title: "Open share",
    subtitle: "Anybody have any news to share before we get into the briefing?",
    note: "Headlines, links, breaking AI news — anything we should add to today's coverage.",
  });

  // 6+. Per-bucket news in canonical order. Each tier slide tagged with section = bucket key + parentSection: news.
  for (const b of BUCKET_ORDER) {
    const data = normalized[b.key];
    if (!data) continue;

    const sectionSlides = [];
    sectionSlides.push(...tierSlides({ items: data.high, tier: "high", providerKey: b.provider, label: b.label }));
    sectionSlides.push(...tierSlides({ items: data.med,  tier: "med",  providerKey: b.provider, label: b.label }));
    sectionSlides.push(...tierSlides({ items: data.low,  tier: "low",  providerKey: b.provider, label: b.label }));
    // Stamp section key + parent on every slide in this bucket so HTML render groups them.
    sectionSlides.forEach(s => { s.section = b.key; s.parentSection = "news"; });
    slides.push(...sectionSlides);
  }

  // Dev Tools — Release Walk (per-tool, ordered by DEV_TOOL_PRIORITY)
  const devToolSlides = buildDevToolSlides(normalized);
  for (const s of devToolSlides) {
    s.section = "devtools";
    s.parentSection = "news";
    slides.push(s);
  }

  // Patterns synthesis (cross-bucket; under news parent)
  const patterns = buildPatternsSlide(normalized);
  if (patterns) {
    patterns.section = "patterns";
    patterns.parentSection = "news";
    slides.push(patterns);
  }

  // Pace / velocity (authored)
  const pace = buildPaceSlide(normalized);
  if (pace) {
    pace.section = "pace";
    pace.parentSection = "news";
    slides.push(pace);
  }

  // Breaking & Deprecated
  const breaking = buildBreakingSlide(normalized);
  if (breaking) {
    breaking.section = "breaking";
    breaking.parentSection = "news";
    slides.push(breaking);
  }

  // Discussion prompts
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
