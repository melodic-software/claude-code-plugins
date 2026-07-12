// S2 capture validation + in-process retry helper (S3/S4).

export function validateCaptures({ posts, replies, cutoff }) {
  const cutoffDate = new Date(cutoff);
  const allTweets = [...(posts?.tw || []), ...(replies?.tw || [])];
  const dates = allTweets.map((t) => new Date(t.d)).filter((d) => !Number.isNaN(d.getTime()));
  const oldest = dates.length ? new Date(Math.min(...dates.map((d) => d.getTime()))) : null;
  const cutoffReached =
    posts?.tw?.some((t) => new Date(t.d) < cutoffDate) ||
    replies?.tw?.some((t) => new Date(t.d) < cutoffDate);
  const within24h = oldest ? oldest.getTime() - cutoffDate.getTime() <= 24 * 3600 * 1000 : false;
  const stableIters = Math.max(posts?.stable_iterations ?? 0, replies?.stable_iterations ?? 0);
  const emptyAndStable = allTweets.length === 0 && stableIters >= 3;
  return {
    status: "complete",
    cutoff_reached: !!cutoffReached,
    oldest_captured: oldest ? oldest.toISOString().substring(0, 16) : null,
    tweets_in_window: allTweets.length,
    passed: !!(cutoffReached || within24h || emptyAndStable),
  };
}

export async function withRetries(fn, maxRetries, attempt = 0) {
  try {
    return await fn(attempt);
  } catch (err) {
    if (attempt >= maxRetries) throw err;
    await new Promise((r) => setTimeout(r, 1500 * (attempt + 1)));
    return withRetries(fn, maxRetries, attempt + 1);
  }
}
