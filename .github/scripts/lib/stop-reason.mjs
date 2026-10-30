// stop-reason.mjs: the machine-readable reason a lane's stop comment carries,
// shared by every lane that writes one. A comment that hands work to a person
// carries an HTML marker, `<!-- stop-reason lane=<lane> reason=<code> -->`,
// and a visible line, "Reason: `<code>`". The code names which of the owner's
// reasons for a person applies (intent, design, security, cost), or `none`,
// which never routes to a person.
//
// A lane script that runs from a copy of its own directory imports this as
// `../lib/stop-reason.mjs`: collect-base-activity copies the base
// .github/scripts/lib/ beside that copy. No dependencies.

// Every code a stop may carry.
export const STOP_REASONS = Object.freeze(["intent", "design", "security", "cost", "none"]);
// The codes that may hand work to a person.
export const PERSON_REASONS = Object.freeze(STOP_REASONS.filter((code) => code !== "none"));

const LANE = /^[a-z][a-z0-9-]{0,63}$/;

// `code`, when it is one of STOP_REASONS; throws otherwise.
export function stopReason(code) {
  if (!STOP_REASONS.includes(code)) {
    throw new Error(`stop reason \`${code}\` is not one of ${STOP_REASONS.join(", ")}`);
  }
  return code;
}

// Whether `code` may hand work to a person: one of PERSON_REASONS.
export const isPersonReason = (code) => PERSON_REASONS.includes(code);

// The HTML marker for `lane`'s stop with `code`.
export function reasonMarker(lane, code) {
  if (!LANE.test(String(lane))) {
    throw new Error(`stop reason lane \`${lane}\` is not a lowercase lane name`);
  }
  return `<!-- stop-reason lane=${lane} reason=${stopReason(code)} -->`;
}

// The visible line naming `code`.
export const reasonLine = (code) => `Reason: \`${stopReason(code)}\``;

// [marker, line] for a comment that hands `lane`'s work to a person; throws
// for `none` or any code that is not a person reason.
export function personReasonLines(lane, code) {
  if (!isPersonReason(code)) {
    throw new Error(`stop reason \`${code}\` never hands work to a person`);
  }
  return [reasonMarker(lane, code), reasonLine(code)];
}

const MARKER = /^<!-- stop-reason lane=([a-z][a-z0-9-]{0,63}) reason=([a-z]+) -->$/m;

// {lane, reason} from the first marker line in `body`, or null when it has
// none or its code is not one of STOP_REASONS.
export function parseReason(body) {
  const match = MARKER.exec(String(body ?? ""));
  return match && STOP_REASONS.includes(match[2]) ? { lane: match[1], reason: match[2] } : null;
}
