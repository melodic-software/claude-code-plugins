const citationOnlyHosts = ["x.com", "twitter.com"];

const allowedSchemes = new Set(["http:", "https:", "mailto:", "tel:"]);

/** True when `value` parses as a URL whose scheme is on the allowlist. */
export function isAllowedUrlScheme(value) {
	try {
		return allowedSchemes.has(new URL(value).protocol.toLowerCase());
	} catch {
		return false;
	}
}

function normalizeHost(hostname) {
	return hostname.toLowerCase().replace(/\.$/, "");
}

function isCitationOnlyHost(hostname) {
	const normalized = normalizeHost(hostname);
	return citationOnlyHosts.some(
		(host) => normalized === host || normalized.endsWith(`.${host}`),
	);
}

function isDottedQuad(octets) {
	return (
		octets.length === 4 &&
		octets.every((n) => Number.isInteger(n) && n >= 0 && n <= 255)
	);
}

function isPrivateIPv4(host) {
	const octets = host.split(".").map(Number);
	if (!isDottedQuad(octets)) return false;
	const [a, b, c] = octets;
	return (
		a === 0 ||
		a === 10 ||
		(a === 100 && b >= 64 && b <= 127) ||
		a === 127 ||
		(a === 169 && b === 254) ||
		(a === 172 && b >= 16 && b <= 31) ||
		(a === 192 && b === 0 && c === 0) ||
		(a === 192 && b === 0 && c === 2) ||
		(a === 192 && b === 88 && c === 99) || // 192.88.99.0/24 deprecated 6to4 relay anycast (RFC 7526)
		(a === 192 && b === 168) ||
		(a === 198 && (b === 18 || b === 19)) ||
		(a === 198 && b === 51 && c === 100) ||
		(a === 203 && b === 0 && c === 113) ||
		a >= 224
	);
}

const hextetRe = /^[0-9a-f]{1,4}$/i;

// RFC 4291 form 3 (trailing dotted quad) must parse: the DNS resolver can answer
// in it, and reading the quad as hex misreads `192.168.1.1` as 0x192.
function expandIPv6(address) {
	const halves = address.split("::");
	if (halves.length > 2) return null;
	const parse = (part) => {
		if (part === "") return [];
		const tokens = part.split(":");
		let trailing = [];
		if (tokens[tokens.length - 1].includes(".")) {
			const octets = tokens.pop().split(".").map(Number);
			if (!isDottedQuad(octets)) return null;
			trailing = [(octets[0] << 8) | octets[1], (octets[2] << 8) | octets[3]];
		}
		if (!tokens.every((h) => hextetRe.test(h))) return null;
		return [...tokens.map((h) => parseInt(h, 16)), ...trailing];
	};
	const head = parse(halves[0]);
	const tail = halves.length === 2 ? parse(halves[1]) : [];
	if (head === null || tail === null) return null;
	const groups =
		halves.length === 2
			? [...head, ...Array(8 - head.length - tail.length).fill(0), ...tail]
			: head;
	if (
		groups.length !== 8 ||
		groups.some((g) => !Number.isInteger(g) || g < 0 || g > 0xffff)
	) {
		return null;
	}
	return groups;
}

function isPrivateIPv6(address) {
	const g = expandIPv6(address);
	if (!g) return false;

	const embedsIPv4 =
		(g.slice(0, 5).every((h) => h === 0) && g[5] === 0xffff) ||
		(g[0] === 0x0064 &&
			g[1] === 0xff9b &&
			g.slice(2, 6).every((h) => h === 0));
	if (embedsIPv4) {
		const v4 = `${g[6] >> 8}.${g[6] & 0xff}.${g[7] >> 8}.${g[7] & 0xff}`;
		return isPrivateIPv4(v4);
	}

	// RFC 8215: 64:ff9b:1::/48 is local-use NAT64 with no fixed-width v4 suffix,
	// so the whole prefix is refused rather than unwrapped.
	if (g[0] === 0x0064 && g[1] === 0xff9b && g[2] === 0x0001) return true;

	if ((g[0] & 0xe000) !== 0x2000) return true;

	if (g[0] === 0x2001 && (g[1] & 0xfe00) === 0) return true;
	if (g[0] === 0x2001 && g[1] === 0x0db8) return true;
	if (g[0] === 0x2002) return true;
	if (g[0] === 0x3fff && (g[1] & 0xf000) === 0) return true; // 3fff::/20 documentation (RFC 9637)

	return false;
}

const ipv4LiteralRe = /^\d{1,3}(?:\.\d{1,3}){3}$/;

function isBracketedIPv6(host) {
	return host.startsWith("[") && host.endsWith("]");
}

function isIpLiteral(host) {
	return isBracketedIPv6(host) || ipv4LiteralRe.test(host);
}

function isPrivateHost(hostname) {
	const host = normalizeHost(hostname);
	if (host === "localhost" || host.endsWith(".localhost")) return true;
	if (isBracketedIPv6(host)) return isPrivateIPv6(host.slice(1, -1));
	return ipv4LiteralRe.test(host) && isPrivateIPv4(host);
}

async function lookupAllAddresses(hostname) {
	const { lookup } = await import("node:dns/promises");
	return lookup(hostname, { all: true });
}

/**
 * Return true for links that must not be included in reachability checks.
 *
 * SSRF guard, two layers: a literal IP host is judged directly against the
 * non-global blocks above, and a DNS name is resolved (every A/AAAA record)
 * and refused when ANY resolved address is non-global — so a hostname whose
 * record points at, e.g., 169.254.169.254 is never dereferenced. A name that
 * does not resolve is skipped too: nothing reachable to check. Residual,
 * documented in the CHANGELOG: the checker performs its own resolution at
 * fetch time, so a rebind between this gate and the fetch, or a redirect hop
 * to a private target inside the checker, remains outside this gate.
 *
 * `resolveHost` is injectable for tests; production uses the real resolver.
 */
export async function shouldSkipLinkCheck(link, resolveHost = lookupAllAddresses) {
	if (/^(?:data:|file:|#)/i.test(link)) return true;

	try {
		const url = new URL(link);
		if (isPrivateHost(url.hostname)) return true;
		if (url.protocol !== "http:" && url.protocol !== "https:") return false;
		if (isCitationOnlyHost(url.hostname)) return true;

		const host = normalizeHost(url.hostname);
		if (!isIpLiteral(host)) {
			let records;
			try {
				records = await resolveHost(host);
			} catch {
				return true;
			}
			const addresses = Array.isArray(records) ? records : [records];
			if (addresses.length === 0) return true;
			for (const record of addresses) {
				const address =
					typeof record === "string" ? record : record?.address;
				if (typeof address !== "string" || address.length === 0) {
					return true;
				}
				const nonGlobal = address.includes(":")
					? isPrivateIPv6(address)
					: isPrivateIPv4(address);
				if (nonGlobal) return true;
			}
		}
		return false;
	} catch {
		return false;
	}
}
