// GENERATED from lib/view-registry.mjs by scripts/sync-shared-copies.sh. Do not edit this copy:
// edit the canonical source, then rerun the script.
// The medium registry for rendered views: one entry per medium, the one fallback chain, and each
// view lane's registration. Skills never name a medium themselves; they reach this through
// lib/view-settings.mjs. Adding a medium or a lane is an addition here, never a skill edit.
//
//   MediumEntry { id, publishes, reachable(context) -> {ok, reason}, deliver(view, context) -> {location}, reportName }
//   Lane        { laneId, kinds, hostedCapable, default }
//
// `context.interactive` is false in a CI or other non-interactive run, where only the terminal is
// reachable (docs/contracts/rendered-views/README.md, "Reachability and preference"). A lane's
// `default` is its shipped medium, applied when no scope decides; null leaves the choice to the
// skill's own content rule.

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

/** A scope may say `auto`, which is no preference: it resolves exactly as unset. */
export const NO_PREFERENCE = "auto";

/** The rendered-views concern's schema, for the cascade reader: one key, `medium`. */
export const SCHEMA = Object.freeze({
  type: "object",
  additionalProperties: false,
  properties: { medium: { type: "string", enum: [NO_PREFERENCE, ...Object.keys(MEDIUMS)] } },
});

const lane = (laneId, kinds, hostedCapable, medium) => Object.freeze({ laneId, kinds: Object.freeze(kinds), hostedCapable, default: medium });

export const LANES = Object.freeze(
  Object.fromEntries(
    [
      lane("review:explain-change", ["digest"], true, "artifact"),
      lane("visualization:present", ["deck"], false, "artifact"),
      lane("visualization:visualize", [], false, null),
      lane("planning", ["plan", "brainstorm"], false, "file"),
      lane("architecture", ["landscape", "containers", "components", "dependencies", "data", "events", "flow", "context", "deployment"], false, "file"),
      lane("discovery:blindspot", ["blindspot"], false, "file"),
      lane("debugging:debug", ["post-mortem"], false, "file"),
      lane("education:illustrate", [], false, "file"),
      lane("work-items:morning-brief", ["morning-brief"], false, "file"),
      lane("work-items:triage", ["board"], false, "file"),
      lane("adhd:clarify", [], false, null),
      lane("codebase-health:audit", [], false, null),
      lane("overengineering:audit", [], false, null),
      lane("education:teach", [], false, null),
      lane("prototype:explore-directions", [], false, null),
      lane("prototype:pressure-test", [], false, null),
      lane("ai-briefing:generate", [], false, null),
    ].map((l) => [l.laneId, l]),
  ),
);

/** The lane registration for `id`, own keys only. */
export const laneOf = (id) => (typeof id === "string" && Object.hasOwn(LANES, id) ? LANES[id] : undefined);

/** `medium` as `lane` reads it: `hosted` is `artifact` unless the lane sends pages to a page host. */
export const readAs = (medium, laneEntry) => (medium === "hosted" && !laneEntry.hostedCapable ? "artifact" : medium);

/**
 * The medium actually used for `preferred` on `laneEntry`: `preferred` itself when reachable, else the
 * first reachable medium after it on the fallback chain (a hosted page steps to `artifact` first).
 * @returns {{medium: string, fell: null | string}} fell: why `preferred` was not used
 */
export function fallBack(preferred, laneEntry, context = {}) {
  const want = readAs(preferred, laneEntry);
  const start = FALLBACK_CHAIN.indexOf(want === "hosted" ? "artifact" : want);
  const candidates = want === "hosted" ? ["hosted", ...FALLBACK_CHAIN.slice(start)] : FALLBACK_CHAIN.slice(start);
  const wanted = mediumOf(want);
  if (!wanted) throw new Error(`view-registry: unknown medium ${JSON.stringify(preferred)}`);
  const first = wanted.reachable(context);
  if (first.ok) return { medium: want, fell: null };
  const medium = candidates.find((id) => mediumOf(id).reachable(context).ok) ?? "terminal";
  return { medium, fell: `${want} unreachable: ${first.reason}` };
}

/** The report line every view lane prints, then one line per notice. */
export function reportLines({ medium, decidedBy, notices = [] }) {
  return [`view: ${medium ?? NO_PREFERENCE} (${decidedBy})`, ...notices.map((n) => `notice: ${n.text}`)];
}
