export function specSource({ written, body, splitChild, splitMarked, ownFiling, briefed, recurring, drift, incident }) {
  const claimed = written || splitChild !== undefined;
  const own = !claimed && !splitMarked && ownFiling;
  const brief = !claimed && !splitMarked && !own && briefed;
  const schedule = claimed || own || brief ? null : recurring;
  const upstream = claimed || schedule !== null ? null : drift;
  const redMain = claimed || schedule !== null || upstream !== null ? null : incident;
  const source = schedule !== null ? "recurring-schedule" : upstream !== null ? "upstream-drift" : redMain !== null ? "main-red-incident" : undefined;
  const filed = own || brief ? String(body ?? "") : null;
  return {
    ...(source !== undefined && { source }),
    body: written && typeof body === "string" ? body : (splitChild ?? filed ?? schedule ?? upstream ?? redMain),
  };
}
