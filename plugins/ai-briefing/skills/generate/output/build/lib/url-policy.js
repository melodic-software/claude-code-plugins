const citationOnlyHosts = ["x.com", "twitter.com"];

// Schemes safe to render as an href, embed as a PPTX hyperlink, or hand to the
// reachability checker. http/https/mailto/tel are the schemes a legitimate
// briefing may contain and are inert at every sink; every other scheme
// (javascript:, data:, file:, blob:, vbscript:, and rarer ones such as ftp:) is
// rejected as deliberate fail-closed hardening.
const allowedSchemes = new Set(["http:", "https:", "mailto:", "tel:"]);

/** True when `value` parses as a URL whose scheme is on the allowlist. */
export function isAllowedUrlScheme(value) {
	let protocol;
	try {
		protocol = new URL(value).protocol;
	} catch {
		return false;
	}
	return allowedSchemes.has(protocol.toLowerCase());
}

function isCitationOnlyHost(hostname) {
	const normalized = hostname.toLowerCase().replace(/\.$/, "");
	return citationOnlyHosts.some(
		(host) => normalized === host || normalized.endsWith(`.${host}`),
	);
}

function isPrivateIPv4(host) {
	const octets = host.split(".").map(Number);
	if (
		octets.length !== 4 ||
		octets.some((n) => !Number.isInteger(n) || n < 0 || n > 255)
	) {
		return false;
	}
	const [a, b] = octets;
	return (
		a === 0 || // 0.0.0.0/8 "this host"
		a === 10 || // 10.0.0.0/8 private
		a === 127 || // 127.0.0.0/8 loopback
		(a === 172 && b >= 16 && b <= 31) || // 172.16.0.0/12 private
		(a === 192 && b === 168) || // 192.168.0.0/16 private
		(a === 169 && b === 254) // 169.254.0.0/16 link-local (cloud metadata)
	);
}

// Expand a WHATWG-canonical IPv6 literal (brackets already stripped) to its eight
// 16-bit groups, or null when it is not a well-formed address.
function expandIPv6(address) {
	const halves = address.split("::");
	if (halves.length > 2) return null;
	const parse = (part) =>
		part === "" ? [] : part.split(":").map((h) => parseInt(h, 16));
	const head = parse(halves[0]);
	const tail = halves.length === 2 ? parse(halves[1]) : [];
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
	if (g.every((h) => h === 0)) return true; // :: unspecified
	if (g.slice(0, 7).every((h) => h === 0) && g[7] === 1) return true; // ::1 loopback
	if ((g[0] & 0xfe00) === 0xfc00) return true; // fc00::/7 unique-local
	if ((g[0] & 0xffc0) === 0xfe80) return true; // fe80::/10 link-local
	if (g.slice(0, 5).every((h) => h === 0) && g[5] === 0xffff) {
		// ::ffff:a.b.c.d IPv4-mapped — check the embedded v4 address.
		const v4 = `${g[6] >> 8}.${g[6] & 0xff}.${g[7] >> 8}.${g[7] & 0xff}`;
		return isPrivateIPv4(v4);
	}
	return false;
}

// True for hosts that must never be dereferenced during a reachability check.
// Relies on WHATWG URL canonicalization to fold decimal/hex/octal/integer IPv4
// and compressed IPv6 into the literal forms matched here. DNS names that resolve
// to a private address at fetch time are not covered — the checker resolves DNS
// itself, so a rebind remains out of reach of this offline literal gate.
function isPrivateHost(hostname) {
	const host = hostname.toLowerCase().replace(/\.$/, "");
	if (host === "localhost" || host.endsWith(".localhost")) return true;
	if (host.startsWith("[") && host.endsWith("]")) {
		return isPrivateIPv6(host.slice(1, -1));
	}
	if (/^\d{1,3}(?:\.\d{1,3}){3}$/.test(host)) return isPrivateIPv4(host);
	return false;
}

/** Return true for links that must not be included in reachability checks. */
export async function shouldSkipLinkCheck(link) {
	if (/^(?:data:|file:|#)/i.test(link)) return true;

	try {
		const url = new URL(link);
		// SSRF guard: never let the reachability checker fetch a
		// private/loopback/link-local/reserved host.
		if (isPrivateHost(url.hostname)) return true;
		return (
			(url.protocol === "http:" || url.protocol === "https:") &&
			isCitationOnlyHost(url.hostname)
		);
	} catch {
		return false;
	}
}
