/** ESM resolve hook mapping the bare specifier `playwright` to a stub whose chromium.launch rejects. */
const stubSource =
  'export const chromium = { launch: async () => { throw new Error("playwright stub: chromium.launch blocked in tests"); } };';

export function resolve(specifier, context, next) {
  if (specifier === "playwright") {
    return { url: `data:text/javascript,${encodeURIComponent(stubSource)}`, shortCircuit: true };
  }
  return next(specifier, context);
}
