export function specSource({ written, body, splitChild, splitMarked, ownFiling, briefed, recurring, drift, incident, monitor = null, deadLinks = null, demotion = null }) {
  const claimed = written || splitChild !== undefined;
  const own = !claimed && !splitMarked && ownFiling;
  const brief = !claimed && !splitMarked && !own && briefed;
  const schedule = claimed || own || brief ? null : recurring;
  const upstream = claimed || schedule !== null ? null : drift;
  const redMain = claimed || schedule !== null || upstream !== null ? null : incident;
  const signal = claimed || schedule !== null || upstream !== null || redMain !== null ? null : monitor;
  const rollup = claimed || schedule !== null || upstream !== null || redMain !== null || signal !== null ? null : deadLinks;
  const alert = claimed || schedule !== null || upstream !== null || redMain !== null || signal !== null || rollup !== null ? null : demotion;
  const source =
    schedule !== null
      ? "recurring-schedule"
      : upstream !== null
        ? "upstream-drift"
        : redMain !== null
          ? "main-red-incident"
          : signal !== null
            ? "monitor-incident"
            : rollup !== null
              ? "dead-link-rollup"
              : alert !== null
                ? "demotion-alert"
                : undefined;
  const filed = own || brief ? String(body ?? "") : null;
  return {
    ...(source !== undefined && { source }),
    body: written && typeof body === "string" ? body : (splitChild ?? filed ?? schedule ?? upstream ?? redMain ?? signal ?? rollup ?? alert),
  };
}
