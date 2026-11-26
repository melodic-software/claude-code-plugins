// https://docs.github.com/en/rest/checks/runs#list-check-run-annotations
export const STOP_RECORD_TITLE = "stop-record";

const slug = (value) => typeof value === "string" && /^[a-z0-9][a-z0-9_-]{0,39}$/.test(value);
const RESET = /^[0-9]{9,12}$/;
const PRE_RECORD_DEFER_TEXT = /\bcause=defer reset=([0-9]{9,12})\b/;

const poolOk = (pool) => pool === null || pool === "*" || slug(pool);
const resetOk = (reset) => reset === null || (Number.isSafeInteger(reset) && RESET.test(String(reset)));

/** The workflow command that records one stop. Throws on a field outside the record's shape. */
export function stopRecordLine({ pool = null, cause, reset = null }) {
  if (!slug(cause) || !poolOk(pool) || !resetOk(reset)) {
    throw new Error(`a stop record takes a slug cause, a slug or "*" pool or null, and an epoch-second reset or null; got ${JSON.stringify({ pool, cause, reset })}`);
  }
  return `::notice title=${STOP_RECORD_TITLE}::${JSON.stringify({ pool, cause, reset })}`;
}

/** The stop one annotation records, from the record or the older text form, or null. */
export function readStop(annotation) {
  const message = String(annotation?.message ?? "");
  if (annotation?.title === STOP_RECORD_TITLE) {
    let record;
    try {
      record = JSON.parse(message);
    } catch {
      return null;
    }
    const { pool = null, cause, reset = null } = record ?? {};
    return slug(cause) && poolOk(pool) && resetOk(reset) ? { pool, cause, reset } : null;
  }
  const text = PRE_RECORD_DEFER_TEXT.exec(message);
  return text ? { pool: null, cause: "defer", reset: Number(text[1]) } : null;
}

/** The epoch-second resets of the defer stops among a job's annotations. */
export const deferResets = (annotations) =>
  annotations
    .map(readStop)
    .filter((stop) => stop?.cause === "defer" && stop.reset !== null)
    .map((stop) => stop.reset);
