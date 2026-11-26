export function hasCapability<T, K extends PropertyKey>(
  value: T,
  method: K,
): value is Extract<T, Record<K, (...args: never[]) => unknown>> {
  return method in (value as object) && typeof (value as Record<K, unknown>)[method] === "function";
}
