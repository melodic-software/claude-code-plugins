const citationOnlyHosts = ["x.com", "twitter.com"];

function isCitationOnlyHost(hostname) {
	const normalized = hostname.toLowerCase().replace(/\.$/, "");
	return citationOnlyHosts.some(
		(host) => normalized === host || normalized.endsWith(`.${host}`),
	);
}

/** Return true for links that must not be included in reachability checks. */
export async function shouldSkipLinkCheck(link) {
	if (/^(?:data:|file:|#)/i.test(link)) return true;

	try {
		const url = new URL(link);
		return (
			(url.protocol === "http:" || url.protocol === "https:") &&
			isCitationOnlyHost(url.hostname)
		);
	} catch {
		return false;
	}
}
