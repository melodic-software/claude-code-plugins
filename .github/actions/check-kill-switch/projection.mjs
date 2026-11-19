export const WINDOW_SECONDS = 3600;
export const MIN_ELAPSED_SECONDS = 60;

export function projectedLeft({ limit, remaining, reset } = {}, now, horizon = Number.POSITIVE_INFINITY) {
  const left = reset - now;
  if (![limit, remaining, reset, now].every(Number.isFinite) || limit <= 0 || remaining < 0 || remaining > limit || left < 0 || !(horizon >= 0)) {
    return null;
  }
  const elapsed = WINDOW_SECONDS - Math.min(left, WINDOW_SECONDS);
  const used = limit - remaining;
  const ahead = Math.min(left, horizon);
  const atHorizon = elapsed < MIN_ELAPSED_SECONDS ? remaining : remaining - (used * ahead) / elapsed;
  return Math.max(0, atHorizon) / limit;
}
