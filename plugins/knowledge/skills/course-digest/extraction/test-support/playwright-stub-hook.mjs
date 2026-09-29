/** ESM resolve hook mapping the bare specifier `playwright` to test-support/playwright-stub.mjs. */
const stubUrl = new URL("./playwright-stub.mjs", import.meta.url).href;

export function resolve(specifier, context, next) {
  if (specifier === "playwright") return { url: stubUrl, shortCircuit: true };
  return next(specifier, context);
}
