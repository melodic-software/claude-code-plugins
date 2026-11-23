export class AddError extends Error {}

const TOKEN = /^[A-Za-z0-9][A-Za-z0-9._-]*(?:[@:][A-Za-z0-9][A-Za-z0-9._-]*)?$/;
const nameOf = (id) => id.slice(0, id.lastIndexOf("@"));

/** Each --profile-add word as an installed plugin id; known() gives the ids a profile or marketplace names, for a missing plugin's install line. */
export const resolveAdded = (tokens, inventory, known = () => []) => [...new Set(tokens.map((token) => resolveOne(token, inventory, known)))];

function resolveOne(token, inventory, known) {
  if (!TOKEN.test(token)) throw new AddError(`--profile-add takes a plugin id, a plugin name, plugin:skill or a skill name, never settings text or a path: ${JSON.stringify(token)}`);
  if (token.includes("@")) {
    if (inventory.has(token)) return token;
    throw notInstalled(token, [token]);
  }
  const [plugin, skill] = token.split(":");
  const ids = [...inventory.keys()];
  const carries = (id, name) => inventory.get(id).skills?.includes(name);
  let found = ids.filter((id) => nameOf(id) === plugin);
  if (skill !== undefined && found.some((id) => carries(id, skill))) found = found.filter((id) => carries(id, skill));
  if (skill === undefined && !found.length) found = ids.filter((id) => carries(id, token));
  if (found.length === 1) return found[0];
  if (found.length) throw new AddError(`--profile-add ${token} matches more than one installed plugin; give one of: ${found.sort().join(", ")}`);
  const candidates = known().filter((id) => nameOf(id) === plugin);
  if (!candidates.length) throw new AddError(`--profile-add ${token}: no installed plugin or skill is named ${token}, and no profile or known marketplace names a plugin ${plugin}; install it with: claude plugin install ${plugin}@<marketplace>`);
  throw notInstalled(token, candidates);
}

const notInstalled = (token, ids) =>
  new AddError(`--profile-add ${token} is not installed. Install it with: ${ids.map((id) => `claude plugin install ${id}`).join("; or ")}`);
