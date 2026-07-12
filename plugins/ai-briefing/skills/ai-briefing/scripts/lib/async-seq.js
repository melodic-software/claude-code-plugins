// Sequential async helpers — avoid await-in-loop while preserving execution order.

export async function mapSequential(items, fn) {
  return items.reduce(async (resultsP, item, index) => {
    const results = await resultsP;
    results.push(await fn(item, index));
    return results;
  }, Promise.resolve([]));
}

export async function forEachSequential(items, fn) {
  await items.reduce(async (prevP, item, index) => {
    await prevP;
    await fn(item, index);
  }, Promise.resolve());
}

export async function findSequential(items, predicate) {
  return items.reduce(async (foundP, item, index) => {
    const found = await foundP;
    if (found !== undefined) return found;
    return (await predicate(item, index)) ?? undefined;
  }, Promise.resolve(undefined));
}
