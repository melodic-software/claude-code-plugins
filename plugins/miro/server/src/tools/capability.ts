// Board items come back from the SDK as a union whose members expose different methods.
// This narrows that union to the members that carry `method` as a callable, so a tool can
// reject an item kind it cannot handle before calling into it.
export function hasCapability<T, K extends PropertyKey>(
  value: T,
  method: K,
): value is Extract<T, Record<K, (...args: never[]) => unknown>> {
  return method in (value as object) && typeof (value as Record<K, unknown>)[method] === "function";
}
