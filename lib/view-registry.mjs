const interactiveOnly = (context = {}) => (context.interactive === false ? { ok: false, reason: "non-interactive run" } : { ok: true });

const entry = (id, publishes, reportName, reachable, deliver) => Object.freeze({ id, publishes, reportName, reachable, deliver });

export const MEDIUMS = Object.freeze({
  terminal: entry("terminal", false, "the terminal", () => ({ ok: true }), () => ({ location: "terminal" })),
  file: entry("file", false, "a local file", interactiveOnly, (view) => ({ location: view.path })),
  artifact: entry("artifact", true, "a private Artifact on claude.ai", interactiveOnly, (view) => ({ location: "artifact", publish: view.path })),
  hosted: entry("hosted", true, "the shared page host", interactiveOnly, (view) => ({ location: "hosted", publish: view.path })),
});

/** The registry entry for `id`, own keys only, so an inherited name such as `toString` is no medium. */
export const mediumOf = (id) => (typeof id === "string" && Object.hasOwn(MEDIUMS, id) ? MEDIUMS[id] : undefined);

/** The one fallback chain: a view that cannot be served on a medium steps down this list. */
export const FALLBACK_CHAIN = Object.freeze(["artifact", "file", "terminal"]);

/** The chain's last step builds no page: the record stands on its own. */
export const NO_PAGE = FALLBACK_CHAIN.at(-1);

/** A scope may say `auto`, which is no preference: it resolves exactly as unset. */
export const NO_PREFERENCE = "auto";

export const PALETTE_ROLES = Object.freeze(["bg", "fg", "panel", "muted", "accent", "link", "focus"]);
export const TYPE_STACKS = Object.freeze(["serif", "sans", "mono"]);

/** Shipped light and dark palette roles and type stacks, matching `lib/html-tokens.css`. */
export const SHIPPED_TOKENS = Object.freeze({
  palette: Object.freeze({
    light: Object.freeze({
      bg: "#FAF9F5",
      fg: "#141413",
      panel: "#FFFFFF",
      muted: "#87867F",
      accent: "#D97757",
      link: "#A0512E",
      focus: "#A0512E",
    }),
    dark: Object.freeze({
      bg: "#141413",
      fg: "#FAF9F5",
      panel: "#3D3D3A",
      muted: "#D1CFC5",
      accent: "#D97757",
      link: "#E89B7E",
      focus: "#E89B7E",
    }),
  }),
  type: Object.freeze({
    serif: "ui-serif, Georgia, serif",
    sans: "system-ui, -apple-system, sans-serif",
    mono: "ui-monospace, 'SF Mono', Menlo, monospace",
  }),
});

/** Canonical plugin `userConfig` option shape for per-user branding (docs/contracts/plugin-option-naming). */
export const BRANDING_USER_CONFIG_OPTION = Object.freeze({
  key: "branding",
  type: "string",
  title: "Rendered-view branding (JSON)",
  description:
    "Palette, type and logo overrides for rendered HTML pages as one JSON object matching branding in docs/conventions/rendered-views.yaml. Empty (default): shipped look. Repository team and personal override files win; invalid values are reported and ignored.",
  default: "",
});

const HEX_COLOR = Object.freeze({ type: "string", pattern: "^#[0-9A-Fa-f]{6}$" });
const PALETTE_SCHEME = Object.freeze({
  type: "object",
  additionalProperties: false,
  properties: Object.freeze(Object.fromEntries(PALETTE_ROLES.map((role) => [role, HEX_COLOR]))),
});
const FONT_ENTRY = Object.freeze({
  type: "object",
  additionalProperties: false,
  properties: Object.freeze({
    family: Object.freeze({ type: "string" }),
    file: Object.freeze({ type: "string" }),
    weight: Object.freeze({ type: ["string", "integer"] }),
    style: Object.freeze({ type: "string", enum: Object.freeze(["normal", "italic"]) }),
  }),
});

/** Schema for the `branding` key of `rendered-views` settings. */
export const BRANDING_SCHEMA = Object.freeze({
  type: "object",
  additionalProperties: false,
  properties: Object.freeze({
    palette: Object.freeze({
      type: "object",
      additionalProperties: false,
      properties: Object.freeze({ light: PALETTE_SCHEME, dark: PALETTE_SCHEME }),
    }),
    type: Object.freeze({
      type: "object",
      additionalProperties: false,
      properties: Object.freeze({
        serif: Object.freeze({ type: "string" }),
        sans: Object.freeze({ type: "string" }),
        mono: Object.freeze({ type: "string" }),
        fonts: Object.freeze({ type: "array", items: FONT_ENTRY }),
      }),
    }),
    logo: Object.freeze({
      type: "object",
      additionalProperties: false,
      properties: Object.freeze({
        svg: Object.freeze({ type: "string" }),
        file: Object.freeze({ type: "string" }),
        label: Object.freeze({ type: "string" }),
      }),
    }),
  }),
});

/** The rendered-views concern's schema, for the cascade reader: `medium` and `branding`. */
export const SCHEMA = Object.freeze({
  type: "object",
  additionalProperties: false,
  properties: Object.freeze({
    medium: Object.freeze({ type: "string", enum: Object.freeze([NO_PREFERENCE, ...Object.keys(MEDIUMS)]) }),
    branding: BRANDING_SCHEMA,
  }),
});

const producer = (producerId, kinds, hostedCapable, medium, hasMediumOption) => Object.freeze({ producerId, kinds: Object.freeze(kinds), hostedCapable, default: medium, hasMediumOption });

export const PRODUCERS = Object.freeze(
  Object.fromEntries(
    [
      producer("review:explain-change", ["digest"], true, "artifact", true),
      producer("visualization:present", ["deck"], false, "artifact", true),
      producer("visualization:visualize", [], false, null, true),
      producer("planning", ["plan", "brainstorm", "design"], false, "artifact", true),
      producer("architecture", ["landscape", "containers", "components", "dependencies", "data", "events", "flow", "context", "deployment"], false, "file", true),
      producer("discovery:blindspot", ["blindspot"], false, "file", true),
      producer("debugging:debug", ["post-mortem"], false, "file", true),
      producer("education:illustrate", [], false, "file", true),
      producer("work-items:morning-brief", ["morning-brief"], false, "file", true),
      producer("work-items:triage", ["board"], false, "file", true),
      producer("adhd:clarify", [], false, null, true),
      producer("codebase-health:audit", [], false, null, true),
      producer("overengineering:audit", [], false, null, false),
      producer("education:teach", [], false, null, true),
      producer("prototype:explore-directions", [], false, null, false),
      producer("prototype:pressure-test", [], false, null, false),
      producer("ai-briefing:generate", [], false, null, false),
    ].map((l) => [l.producerId, l]),
  ),
);

/** The producer registration for `id`, own keys only. */
export const producerOf = (id) => (typeof id === "string" && Object.hasOwn(PRODUCERS, id) ? PRODUCERS[id] : undefined);

/** `medium` as `producer` reads it: `hosted` is `artifact` unless the producer sends pages to a page host. */
export const readAs = (medium, producerEntry) => (medium === "hosted" && !producerEntry.hostedCapable ? "artifact" : medium);

/**
 * The medium actually used for `preferred` on `producerEntry`: `preferred` itself when reachable, else the
 * first reachable medium after it on the fallback chain (a hosted page steps to `artifact` first).
 * @returns {{medium: string, fell: null | string}} fell: why `preferred` was not used
 */
export function fallBack(preferred, producerEntry, context = {}) {
  const want = readAs(preferred, producerEntry);
  const wanted = mediumOf(want);
  if (!wanted) throw new Error(`view-registry: unknown medium ${JSON.stringify(preferred)}`);
  const first = wanted.reachable(context);
  if (first.ok) return { medium: want, fell: null };
  const start = FALLBACK_CHAIN.indexOf(want === "hosted" ? "artifact" : want);
  const medium = FALLBACK_CHAIN.slice(start).find((id) => MEDIUMS[id].reachable(context).ok) ?? "terminal";
  return { medium, fell: `${want} unreachable: ${first.reason}` };
}

/** The report line every view producer prints, then one line per notice. */
export function reportLines({ medium, decidedBy, notices = [] }) {
  return [`view: ${medium ?? NO_PREFERENCE} (${decidedBy})`, ...notices.map((n) => `notice: ${n.text}`)];
}
